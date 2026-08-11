from __future__ import annotations

import base64
import json
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Transaction
from app.schemas.movements import AccountSnapshot, DayGroup, MovementsResponse, MovementSummary
from app.services.accounts import get_account
from app.services.financial import effective_amount_minor
from app.services.financial_calendar import financial_month_window, financial_week_window
from app.services.common import get_or_create_profile
from app.services.transactions import transaction_out


async def get_account_movements(
    session: AsyncSession,
    user_id: UUID,
    account_id: UUID,
    limit: int,
    cursor: str | None,
    *,
    filter: str = "all",
    income: bool | None = None,
    day: date | None = None,
    week_start: date | None = None,
    month: str | None = None,
    category_id: UUID | None = None,
) -> MovementsResponse:
    account = await get_account(session, user_id, account_id)
    profile = await get_or_create_profile(session, user_id)
    now = datetime.now(UTC)
    ownership = or_(
        Transaction.account_id == account.id,
        Transaction.destination_account_id == account.id,
    )
    base_query = select(Transaction).where(
        Transaction.user_id == user_id,
        ownership,
        Transaction.occurred_at <= now,
    )
    all_current = list((await session.scalars(base_query.order_by(Transaction.occurred_at.asc()))).all())
    balance = account.opening_balance_minor + sum(
        effective_amount_minor(transaction, account) for transaction in all_current
    )
    income_total = sum(transaction.amount_minor for transaction in all_current if transaction.kind == "income")
    expenses_total = sum(transaction.amount_minor for transaction in all_current if transaction.kind == "expense")

    filtered_query = base_query
    if filter == "type":
        filtered_query = filtered_query.where(Transaction.kind == ("income" if income else "expense"))
    elif filter == "day" and day is not None:
        filtered_query = filtered_query.where(Transaction.local_day == day)
    elif filter == "week" and week_start is not None:
        period = financial_week_window(week_start, profile.week_start_day, profile.timezone)
        filtered_query = filtered_query.where(
            Transaction.occurred_at >= period.utc_start,
            Transaction.occurred_at < period.utc_end,
        )
    elif filter == "month" and month is not None:
        try:
            components = [int(part) for part in month.split("-")]
            if len(components) == 2:
                year, month_number = components
                anchor = date(year, month_number, 1)
            else:
                year, month_number, day = components
                anchor = date(year, month_number, day)
            period = financial_month_window(anchor, profile.month_start_day, profile.timezone)
        except (ValueError, TypeError):
            raise DomainError(422, "month is invalid", "invalid_month") from None
        filtered_query = filtered_query.where(
            Transaction.occurred_at >= period.utc_start,
            Transaction.occurred_at < period.utc_end,
        )
    elif filter == "category" and category_id is not None:
        filtered_query = filtered_query.where(Transaction.category_id == category_id)
    elif filter == "recurring":
        filtered_query = filtered_query.where(
            Transaction.origin == "recurrence",
            Transaction.recurrence_rule_id.is_not(None),
        )

    filtered_transactions = list(
        (await session.scalars(filtered_query.order_by(Transaction.occurred_at.desc(), Transaction.id.desc()))).all()
    )
    subtotals: dict[str, int] = {}
    for transaction in filtered_transactions:
        key = transaction.local_day.isoformat()
        subtotals[key] = subtotals.get(key, 0) + effective_amount_minor(transaction, account)

    page_query = filtered_query
    if cursor:
        cursor_time, cursor_id = decode_cursor(cursor)
        page_query = page_query.where(
            or_(
                Transaction.occurred_at < cursor_time,
                and_(Transaction.occurred_at == cursor_time, Transaction.id < cursor_id),
            )
        )
    page_query = page_query.order_by(Transaction.occurred_at.desc(), Transaction.id.desc()).limit(limit)
    page = list((await session.scalars(page_query)).all())

    outputs = [await transaction_out(session, transaction, account) for transaction in page]
    grouped: dict[str, list] = {}
    for transaction, output in zip(page, outputs, strict=True):
        key = transaction.local_day.isoformat()
        grouped.setdefault(key, []).append(output)

    days = [
        DayGroup(day=day, subtotal_minor=subtotals[day], movements=grouped[day])
        for day in sorted(grouped, reverse=True)
    ]
    next_cursor = encode_cursor(page[-1].occurred_at, page[-1].id) if len(page) == limit else None
    return MovementsResponse(
        account=AccountSnapshot(
            id=account.id,
            name=account.name,
            currency_code=account.currency_code,
            currency_exponent=account.currency_exponent,
            balance_minor=balance,
        ),
        summary=MovementSummary(income_minor=income_total, expenses_minor=expenses_total),
        days=days,
        next_cursor=next_cursor,
    )


def encode_cursor(occurred_at: datetime, transaction_id: UUID) -> str:
    payload = {"occurred_at": occurred_at.astimezone(UTC).isoformat(), "id": str(transaction_id)}
    raw = json.dumps(payload, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        padding = "=" * (-len(cursor) % 4)
        payload = json.loads(base64.urlsafe_b64decode(cursor + padding))
        occurred_at = datetime.fromisoformat(payload["occurred_at"])
        if occurred_at.tzinfo is None:
            raise ValueError
        return occurred_at.astimezone(UTC), UUID(payload["id"])
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        raise DomainError(422, "cursor is invalid", "invalid_cursor") from exc
