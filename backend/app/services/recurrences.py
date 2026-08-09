from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Account, Category, RecurrenceOccurrence, RecurrenceRule, Transaction
from app.schemas.common import RecurrenceStatus
from app.schemas.recurrences import RecurrenceCreate, RecurrenceUpdate
from app.services.common import normalize_currency
from app.services.scheduling import next_occurrence_after, occurrences_through

ROME = ZoneInfo("Europe/Rome")


@dataclass(frozen=True, slots=True)
class RecurrenceMaterializationResult:
    generated_count: int = 0
    skipped_archived_account_count: int = 0
    skipped_invalid_category_count: int = 0
    skipped_currency_mismatch_count: int = 0


async def get_recurrence_rule(session: AsyncSession, user_id: UUID, rule_id: UUID) -> RecurrenceRule:
    rule = await session.scalar(
        select(RecurrenceRule).where(RecurrenceRule.id == rule_id, RecurrenceRule.user_id == user_id)
    )
    if rule is None:
        raise DomainError(404, "recurrence rule not found", "recurrence_not_found")
    return rule


async def list_recurrence_rules(session: AsyncSession, user_id: UUID) -> list[RecurrenceRule]:
    status_order = {
        RecurrenceStatus.active.value: 0,
        RecurrenceStatus.paused.value: 1,
        RecurrenceStatus.cancelled.value: 2,
    }
    rules = list(
        (
            await session.scalars(
                select(RecurrenceRule)
                .where(RecurrenceRule.user_id == user_id)
                .order_by(RecurrenceRule.next_occurrence_date.asc(), RecurrenceRule.id.asc())
            )
        ).all()
    )
    return sorted(rules, key=lambda rule: (status_order.get(rule.status, 99), rule.next_occurrence_date, str(rule.id)))


async def create_recurrence_rule(
    session: AsyncSession, user_id: UUID, payload: RecurrenceCreate, now: datetime | None = None
) -> RecurrenceRule:
    account = await _active_account(session, user_id, payload.account_id)
    category = await _optional_category(session, user_id, payload.category_id)
    currency_code = normalize_currency(payload.currency_code)
    _ensure_currency(currency_code, account.currency_code)
    anchor_date = payload.anchor_date
    rule = RecurrenceRule(
        user_id=user_id,
        account_id=account.id,
        category_id=category.id if category else None,
        kind=payload.kind.value,
        amount_minor=payload.amount_minor,
        currency_code=currency_code,
        currency_exponent=payload.currency_exponent,
        title=_clean(payload.title),
        note=_clean(payload.note),
        merchant=_clean(payload.merchant),
        cadence=payload.cadence.value,
        cadence_interval=payload.cadence_interval,
        anchor_date=anchor_date,
        next_occurrence_date=anchor_date,
        status=payload.status.value,
    )
    session.add(rule)
    await session.flush()
    if rule.status == RecurrenceStatus.active.value:
        await materialize_due_recurrences(session, user_id, now=now)
    else:
        await session.commit()
    await session.refresh(rule)
    return rule


async def update_recurrence_rule(
    session: AsyncSession, user_id: UUID, rule_id: UUID, payload: RecurrenceUpdate, now: datetime | None = None
) -> RecurrenceRule:
    rule = await get_recurrence_rule(session, user_id, rule_id)
    values = payload.model_dump(exclude_unset=True)
    account = await _active_account(session, user_id, values.get("account_id", rule.account_id))
    category = await _optional_category(session, user_id, values.get("category_id", rule.category_id))
    currency_code = normalize_currency(values.get("currency_code", rule.currency_code))
    _ensure_currency(currency_code, account.currency_code)

    kind = values.get("kind", rule.kind)
    kind_value = kind.value if hasattr(kind, "value") else kind
    if kind_value == "transfer":
        raise DomainError(422, "transfers cannot recur", "transfer_recurrence_not_supported")

    schedule_changed = any(key in values for key in ("anchor_date", "cadence", "cadence_interval"))
    rule.account_id = account.id
    rule.category_id = category.id if category else None
    rule.kind = kind_value
    rule.amount_minor = values.get("amount_minor", rule.amount_minor)
    rule.currency_code = currency_code
    rule.currency_exponent = values.get("currency_exponent", rule.currency_exponent)
    for key in ("title", "note", "merchant"):
        if key in values:
            setattr(rule, key, _clean(values[key]))
    rule.cadence = _enum_value(values.get("cadence", rule.cadence))
    rule.cadence_interval = values.get("cadence_interval", rule.cadence_interval)
    rule.anchor_date = values.get("anchor_date", rule.anchor_date)
    if schedule_changed:
        # Keep the supplied anchor as the complete future schedule. An active past anchor
        # is then caught up by the same materializer used for creation.
        rule.next_occurrence_date = rule.anchor_date

    await session.flush()
    if schedule_changed and rule.status == RecurrenceStatus.active.value:
        await materialize_due_recurrences(session, user_id, now=now)
    else:
        await session.commit()
    await session.refresh(rule)
    return rule


async def change_recurrence_status(
    session: AsyncSession, user_id: UUID, rule_id: UUID, status: RecurrenceStatus, now: datetime | None = None
) -> RecurrenceRule:
    rule = await get_recurrence_rule(session, user_id, rule_id)
    current_date = _today(now)
    rule.status = status.value
    if status is RecurrenceStatus.active:
        # Resuming intentionally skips the paused interval and never backfills it.
        rule.next_occurrence_date = next_occurrence_after(
            current_date, rule.anchor_date, rule.cadence, rule.cadence_interval
        )
    await session.commit()
    await session.refresh(rule)
    return rule


async def materialize_due_recurrences(
    session: AsyncSession, user_id: UUID, now: datetime | None = None
) -> RecurrenceMaterializationResult:
    now = now or datetime.now(UTC)
    if now.tzinfo is None:
        raise DomainError(422, "materialization time must include a timezone", "timezone_required")
    now = now.astimezone(UTC)
    today = now.astimezone(ROME).date()
    rules = list(
        (
            await session.scalars(
                select(RecurrenceRule)
                .where(
                    RecurrenceRule.user_id == user_id,
                    RecurrenceRule.status == RecurrenceStatus.active.value,
                    RecurrenceRule.next_occurrence_date <= today,
                )
                .order_by(RecurrenceRule.next_occurrence_date.asc(), RecurrenceRule.id.asc())
                .with_for_update()
            )
        ).all()
    )
    generated = archived = invalid_category = currency_mismatch = 0

    for rule in rules:
        account = await session.scalar(
            select(Account).where(Account.id == rule.account_id, Account.user_id == user_id).with_for_update()
        )
        if account is None or account.is_archived:
            rule.status = RecurrenceStatus.paused.value
            archived += 1
            continue
        if account.currency_code != rule.currency_code:
            rule.status = RecurrenceStatus.paused.value
            currency_mismatch += 1
            continue

        category = None
        if rule.category_id is not None:
            category = await session.scalar(
                select(Category).where(
                    Category.id == rule.category_id,
                    Category.user_id == user_id,
                    Category.deleted_at.is_(None),
                )
            )
            if category is None:
                rule.status = RecurrenceStatus.paused.value
                invalid_category += 1
                continue

        due_dates = occurrences_through(
            rule.next_occurrence_date,
            today,
            rule.anchor_date,
            rule.cadence,
            rule.cadence_interval,
        )
        for scheduled_date in due_dates:
            occurrence = await session.scalar(
                select(RecurrenceOccurrence)
                .where(
                    RecurrenceOccurrence.user_id == user_id,
                    RecurrenceOccurrence.rule_id == rule.id,
                    RecurrenceOccurrence.scheduled_date == scheduled_date,
                )
                .with_for_update()
            )
            if occurrence is not None and occurrence.transaction_id is not None:
                rule.next_occurrence_date = next_occurrence_after(
                    scheduled_date, rule.anchor_date, rule.cadence, rule.cadence_interval
                )
                continue
            if occurrence is None:
                occurrence = RecurrenceOccurrence(
                    user_id=user_id,
                    rule_id=rule.id,
                    scheduled_date=scheduled_date,
                )
                session.add(occurrence)
                await session.flush()

            transaction = Transaction(
                user_id=user_id,
                kind=rule.kind,
                account_id=rule.account_id,
                amount_minor=rule.amount_minor,
                currency_code=rule.currency_code,
                currency_exponent=rule.currency_exponent,
                # This is the real materialization time. scheduled_date remains authoritative
                # in recurrence_occurrences and transactions.local_day.
                occurred_at=now,
                local_day=scheduled_date,
                category_id=category.id if category else None,
                note=rule.note or rule.title or rule.merchant,
                merchant=rule.merchant,
                origin="recurrence",
                review_status="confirmed",
                recurrence_rule_id=rule.id,
            )
            session.add(transaction)
            await session.flush()
            occurrence.transaction_id = transaction.id
            occurrence.materialized_at = now
            generated += 1
            rule.next_occurrence_date = next_occurrence_after(
                scheduled_date, rule.anchor_date, rule.cadence, rule.cadence_interval
            )

    await session.commit()
    return RecurrenceMaterializationResult(generated, archived, invalid_category, currency_mismatch)


def _today(now: datetime | None) -> date:
    value = now or datetime.now(UTC)
    if value.tzinfo is None:
        raise DomainError(422, "materialization time must include a timezone", "timezone_required")
    return value.astimezone(ROME).date()


async def _active_account(session: AsyncSession, user_id: UUID, account_id: UUID) -> Account:
    account = await session.scalar(
        select(Account).where(
            Account.id == account_id,
            Account.user_id == user_id,
            Account.is_archived.is_(False),
        )
    )
    if account is None:
        raise DomainError(404, "active account not found", "account_not_found")
    return account


async def _optional_category(session: AsyncSession, user_id: UUID, category_id: UUID | None) -> Category | None:
    if category_id is None:
        return None
    category = await session.scalar(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == user_id,
            Category.deleted_at.is_(None),
        )
    )
    if category is None:
        raise DomainError(404, "active category not found", "category_not_found")
    return category


def _ensure_currency(payload_currency: str, account_currency: str) -> None:
    if payload_currency != account_currency:
        raise DomainError(422, "recurrence currency must match the account currency", "currency_mismatch")


def _enum_value(value):
    return value.value if hasattr(value, "value") else value


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None
