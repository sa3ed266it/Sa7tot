from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Category, RecurrenceRule, Transaction
from app.schemas.common import AccountBrief, CategoryBrief, RecurrenceStatus
from app.schemas.upcoming import UpcomingRecurrenceItem, UpcomingResponse, UpcomingTransactionItem
from app.services.accounts import get_account
from app.services.recurrences import materialize_due_recurrences
from app.services.transactions import transaction_out

ROME = ZoneInfo("Europe/Rome")


async def get_upcoming(
    session: AsyncSession,
    user_id: UUID,
    account_id: UUID,
    limit: int,
    days: int | None = None,
    until: date | None = None,
    now: datetime | None = None,
) -> UpcomingResponse:
    account = await get_account(session, user_id, account_id)
    now = now or datetime.now(UTC)
    if now.tzinfo is None:
        raise DomainError(422, "now must include a timezone", "timezone_required")
    now = now.astimezone(UTC)
    today = now.astimezone(ROME).date()
    if days is not None and until is not None:
        raise DomainError(422, "provide either days or until, not both", "upcoming_window_conflict")
    window_end = until or (today + timedelta(days=days)) if days is not None else until
    if window_end is not None and window_end < today:
        raise DomainError(422, "upcoming window cannot end before today", "invalid_upcoming_window")

    # Due recurrence rules are materialized before projections are read. A current-day
    # occurrence is therefore never left as a stale projection.
    await materialize_due_recurrences(session, user_id, now=now)

    ownership = or_(Transaction.account_id == account.id, Transaction.destination_account_id == account.id)
    transaction_query = select(Transaction).where(
        Transaction.user_id == user_id,
        ownership,
        Transaction.occurred_at > now,
    )
    if window_end is not None:
        transaction_query = transaction_query.where(Transaction.local_day <= window_end)
    future_transactions = list(
        (
            await session.scalars(
                transaction_query.order_by(
                    Transaction.local_day.asc(), Transaction.occurred_at.asc(), Transaction.id.asc()
                ).limit(limit)
            )
        ).all()
    )
    transaction_items = [
        UpcomingTransactionItem(
            kind="transaction",
            effective_date=transaction.local_day,
            transaction=await transaction_out(session, transaction, account),
        )
        for transaction in future_transactions
    ]

    rule_query = select(RecurrenceRule).where(
        RecurrenceRule.user_id == user_id,
        RecurrenceRule.account_id == account.id,
        RecurrenceRule.status == RecurrenceStatus.active.value,
        RecurrenceRule.next_occurrence_date > today,
    )
    if window_end is not None:
        rule_query = rule_query.where(RecurrenceRule.next_occurrence_date <= window_end)
    rules = list(
        (
            await session.scalars(
                rule_query.order_by(RecurrenceRule.next_occurrence_date.asc(), RecurrenceRule.id.asc())
            )
        ).all()
    )
    categories = (
        {
            category.id: category
            for category in (
                await session.scalars(
                    select(Category).where(
                        Category.user_id == user_id,
                        Category.id.in_([rule.category_id for rule in rules if rule.category_id is not None]),
                    )
                )
            ).all()
        }
        if any(rule.category_id is not None for rule in rules)
        else {}
    )
    recurrence_items = [
        UpcomingRecurrenceItem(
            kind="recurrence",
            effective_date=rule.next_occurrence_date,
            rule_id=rule.id,
            scheduled_date=rule.next_occurrence_date,
            account=AccountBrief(id=account.id, name=account.name, currency_code=account.currency_code),
            category=_category_brief(categories.get(rule.category_id)),
            transaction_kind=rule.kind,
            amount_minor=rule.amount_minor,
            currency_code=rule.currency_code,
            currency_exponent=rule.currency_exponent,
            title=rule.title,
            note=rule.note,
            merchant=rule.merchant,
            cadence=rule.cadence,
            cadence_interval=rule.cadence_interval,
        )
        for rule in rules
    ]

    items = [*transaction_items, *recurrence_items]
    items.sort(key=lambda item: (item.effective_date, _stable_item_id(item)))
    return UpcomingResponse(
        account=AccountBrief(id=account.id, name=account.name, currency_code=account.currency_code),
        items=items[:limit],
    )


def _category_brief(category: Category | None) -> CategoryBrief | None:
    if category is None:
        return None
    return CategoryBrief(
        id=category.id,
        name=category.name,
        income=category.income,
        icon_identifier=category.icon_identifier,
        color=category.color,
        preset_key=category.preset_key,
    )


def _stable_item_id(item: UpcomingTransactionItem | UpcomingRecurrenceItem) -> str:
    if item.kind == "transaction":
        return str(item.transaction.id)
    return str(item.rule_id)
