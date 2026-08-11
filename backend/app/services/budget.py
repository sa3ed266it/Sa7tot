from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Budget, Category, MainBudget, Profile, Transaction
from app.schemas.budget import BudgetCategoryMutation, BudgetMutation, BudgetPeriod
from app.services.common import get_or_create_profile, normalize_currency
from app.services.financial_calendar import financial_month_window, financial_week_window


def _zone(timezone_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        return ZoneInfo("Europe/Rome")


def _period_start(
    now: date,
    period: BudgetPeriod,
    supplied: date | None,
    month_start_day: int,
    week_start_day: int,
    timezone_name: str,
) -> date:
    if period is BudgetPeriod.day:
        return now
    if period is BudgetPeriod.week:
        return financial_week_window(now, week_start_day, timezone_name).local_start
    if period is BudgetPeriod.month:
        return financial_month_window(now, month_start_day, timezone_name).local_start
    return now.replace(month=1, day=1)


def _next_start(start: date, period: str, month_start_day: int, timezone_name: str) -> date:
    if period == BudgetPeriod.day:
        return start + timedelta(days=1)
    if period == BudgetPeriod.week:
        return start + timedelta(days=7)
    if period == BudgetPeriod.month:
        return financial_month_window(start, month_start_day, timezone_name).local_end
    return date(start.year + 1, 1, 1)


def _normalize_start(start: date, period: str, today: date, month_start_day: int, timezone_name: str) -> date:
    current = start
    while _next_start(current, period, month_start_day, timezone_name) <= today:
        current = _next_start(current, period, month_start_day, timezone_name)
    return current


def _utc_window(start: date, end: date, timezone_name: str) -> tuple[datetime, datetime]:
    zone = _zone(timezone_name)
    return (
        datetime.combine(start, time.min, tzinfo=zone).astimezone(UTC),
        datetime.combine(end, time.min, tzinfo=zone).astimezone(UTC),
    )


async def _spent(
    session: AsyncSession,
    user_id: UUID,
    start: date,
    end: date,
    timezone_name: str,
    category_id: UUID | None,
    currency_code: str,
) -> int:
    lower, upper = _utc_window(start, end, timezone_name)
    query = select(Transaction.amount_minor).where(
        Transaction.user_id == user_id,
        Transaction.kind == "expense",
        Transaction.currency_code == currency_code,
        Transaction.occurred_at >= lower,
        Transaction.occurred_at < upper,
        Transaction.occurred_at <= datetime.now(UTC),
    )
    if category_id is not None:
        query = query.where(Transaction.category_id == category_id)
    amounts = (await session.scalars(query)).all()
    return sum(amounts)


def _remaining(amount: int, spent: int) -> int:
    return amount - spent


def _progress(amount: int, spent: int) -> float:
    return 0.0 if amount <= 0 else min(max(spent / amount, 0.0), 1.0)


async def _normalize_budget(
    budget: MainBudget | Budget,
    today: date,
    month_start_day: int,
    week_start_day: int,
    timezone_name: str,
) -> bool:
    if budget.period_type == BudgetPeriod.week:
        normalized = financial_week_window(today, week_start_day, timezone_name).local_start
    elif budget.period_type == BudgetPeriod.month:
        normalized = financial_month_window(today, month_start_day, timezone_name).local_start
    else:
        normalized = _normalize_start(
            budget.period_start, budget.period_type, today, month_start_day, timezone_name
        )
    if normalized == budget.period_start:
        return False
    budget.period_start = normalized
    return True


async def get_summary(session: AsyncSession, user_id: UUID) -> dict:
    profile = await get_or_create_profile(session, user_id)
    today = datetime.now(_zone(profile.timezone)).date()
    main = await session.scalar(select(MainBudget).where(MainBudget.user_id == user_id))
    categories = list(
        (
            await session.scalars(
                select(Budget).where(Budget.user_id == user_id).order_by(Budget.created_at.asc(), Budget.id.asc())
            )
        ).all()
    )
    changed = False
    for budget in [main, *categories] if main else categories:
        changed = await _normalize_budget(
            budget,
            today,
            profile.month_start_day,
            profile.week_start_day,
            profile.timezone,
        ) or changed
    if changed:
        await session.commit()
    return {
        "profile": profile,
        "main": await _main_out(session, main, profile) if main else None,
        "categories": [await _category_out(session, budget, profile) for budget in categories],
    }


async def _main_out(session: AsyncSession, budget: MainBudget, profile: Profile) -> dict:
    end = _next_start(budget.period_start, budget.period_type, profile.month_start_day, profile.timezone)
    spent = await _spent(
        session, budget.user_id, budget.period_start, end, profile.timezone, None, budget.currency_code
    )
    return {
        "id": budget.id,
        "amount_minor": budget.amount_minor,
        "spent_minor": spent,
        "remaining_minor": _remaining(budget.amount_minor, spent),
        "progress": _progress(budget.amount_minor, spent),
        "currency_code": budget.currency_code,
        "currency_exponent": budget.currency_exponent,
        "period_type": budget.period_type,
        "period_start": budget.period_start,
        "period_end": end,
        "created_at": budget.created_at,
        "updated_at": budget.updated_at,
    }


async def _category_out(session: AsyncSession, budget: Budget, profile: Profile) -> dict:
    category = await session.scalar(
        select(Category).where(Category.id == budget.category_id, Category.user_id == budget.user_id)
    )
    end = _next_start(budget.period_start, budget.period_type, profile.month_start_day, profile.timezone)
    spent = await _spent(
        session, budget.user_id, budget.period_start, end, profile.timezone, budget.category_id, budget.currency_code
    )
    return {
        "id": budget.id,
        "category_id": budget.category_id,
        "category_name": category.name if category else None,
        "category_deleted": category is None or category.deleted_at is not None,
        "category_icon_identifier": category.icon_identifier if category else None,
        "category_color": category.color if category else None,
        "amount_minor": budget.amount_minor,
        "spent_minor": spent,
        "remaining_minor": _remaining(budget.amount_minor, spent),
        "progress": _progress(budget.amount_minor, spent),
        "currency_code": budget.currency_code,
        "currency_exponent": budget.currency_exponent,
        "period_type": budget.period_type,
        "period_start": budget.period_start,
        "period_end": end,
        "created_at": budget.created_at,
        "updated_at": budget.updated_at,
    }


async def upsert_main(session: AsyncSession, user_id: UUID, payload: BudgetMutation) -> dict:
    profile = await get_or_create_profile(session, user_id)
    today = datetime.now(_zone(profile.timezone)).date()
    budget = await session.scalar(select(MainBudget).where(MainBudget.user_id == user_id))
    start = _period_start(
        today,
        payload.period_type,
        payload.period_start,
        profile.month_start_day,
        profile.week_start_day,
        profile.timezone,
    )
    if budget is None:
        budget = MainBudget(user_id=user_id)
        session.add(budget)
    budget.amount_minor = payload.amount_minor
    budget.currency_code = normalize_currency(payload.currency_code)
    budget.currency_exponent = payload.currency_exponent
    budget.period_type = payload.period_type.value
    budget.period_start = start
    await session.commit()
    return await get_summary(session, user_id)


async def upsert_category(session: AsyncSession, user_id: UUID, payload: BudgetCategoryMutation) -> dict:
    profile = await get_or_create_profile(session, user_id)
    category = await session.scalar(
        select(Category).where(Category.id == payload.category_id, Category.user_id == user_id)
    )
    if category is None:
        raise DomainError(404, "category not found", "category_not_found")
    if category.income:
        raise DomainError(422, "income categories cannot have a spending budget", "income_category_budget")
    today = datetime.now(_zone(profile.timezone)).date()
    budget = await session.scalar(
        select(Budget).where(Budget.user_id == user_id, Budget.category_id == payload.category_id)
    )
    if budget is None:
        budget = Budget(user_id=user_id, category_id=payload.category_id)
        session.add(budget)
    budget.amount_minor = payload.amount_minor
    budget.currency_code = normalize_currency(payload.currency_code)
    budget.currency_exponent = payload.currency_exponent
    budget.period_type = payload.period_type.value
    budget.period_start = _period_start(
        today,
        payload.period_type,
        payload.period_start,
        profile.month_start_day,
        profile.week_start_day,
        profile.timezone,
    )
    await session.commit()
    return await get_summary(session, user_id)


async def delete_category_budget(session: AsyncSession, user_id: UUID, category_id: UUID) -> dict:
    budget = await session.scalar(select(Budget).where(Budget.user_id == user_id, Budget.category_id == category_id))
    if budget is None:
        raise DomainError(404, "category budget not found", "budget_not_found")
    await session.delete(budget)
    await session.commit()
    return await get_summary(session, user_id)


async def delete_main(session: AsyncSession, user_id: UUID) -> dict:
    budget = await session.scalar(select(MainBudget).where(MainBudget.user_id == user_id))
    if budget is None:
        raise DomainError(404, "main budget not found", "budget_not_found")
    await session.delete(budget)
    await session.commit()
    return await get_summary(session, user_id)
