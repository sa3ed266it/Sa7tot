from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Account, Subscription, SubscriptionOccurrence, Transaction
from app.services.common import display_subscription_name, get_or_create_profile
from app.services.scheduling import next_occurrence_after, occurrences_through


@dataclass(frozen=True, slots=True)
class MaterializationResult:
    generated_count: int
    skipped_archived_account_count: int


async def materialize_due_subscriptions(
    session: AsyncSession, user_id: UUID, now: datetime | None = None
) -> MaterializationResult:
    now = now or datetime.now(UTC)
    if now.tzinfo is None:
        raise DomainError(422, "materialization time must include a timezone", "timezone_required")
    now = now.astimezone(UTC)
    profile = await get_or_create_profile(session, user_id)
    today = now.astimezone(ZoneInfo(profile.timezone)).date()

    subscriptions = list(
        (
            await session.scalars(
                select(Subscription)
                .where(
                    Subscription.user_id == user_id,
                    Subscription.status == "active",
                    Subscription.next_billing_date <= today,
                )
                .with_for_update()
            )
        ).all()
    )
    generated_count = 0
    skipped_archived = 0

    for subscription in subscriptions:
        account = await session.scalar(
            select(Account).where(
                Account.id == subscription.account_id,
                Account.user_id == user_id,
            )
        )
        if account is None or account.is_archived:
            skipped_archived += 1
            continue
        if account.currency_code != subscription.currency_code:
            raise DomainError(
                409,
                "subscription currency no longer matches its account",
                "subscription_currency_mismatch",
            )

        due_dates = occurrences_through(
            subscription.next_billing_date,
            today,
            subscription.billing_anchor,
            subscription.cadence,
            subscription.cadence_interval,
        )
        for scheduled_date in due_dates:
            occurrence_key = make_occurrence_key(subscription.id, scheduled_date)
            occurrence = await session.scalar(
                select(SubscriptionOccurrence)
                .where(
                    SubscriptionOccurrence.subscription_id == subscription.id,
                    SubscriptionOccurrence.occurrence_key == occurrence_key,
                )
                .with_for_update()
            )
            if occurrence is not None and occurrence.transaction_id is not None:
                continue
            if occurrence is None:
                occurrence = SubscriptionOccurrence(
                    user_id=user_id,
                    subscription_id=subscription.id,
                    occurrence_key=occurrence_key,
                    scheduled_date=scheduled_date,
                )
                session.add(occurrence)

            transaction = Transaction(
                user_id=user_id,
                kind="expense",
                account_id=account.id,
                amount_minor=subscription.amount_minor,
                currency_code=subscription.currency_code,
                currency_exponent=subscription.currency_exponent,
                occurred_at=now,
                local_day=scheduled_date,
                category_id=subscription.category_id,
                note=subscription.note,
                origin="subscription",
                review_status="confirmed",
                subscription_id=subscription.id,
                subscription_service_id=subscription.service_id,
                subscription_occurrence_key=occurrence_key,
                subscription_display_name=display_subscription_name(subscription.service_id, subscription.custom_name),
            )
            session.add(transaction)
            await session.flush()
            occurrence.transaction_id = transaction.id
            occurrence.materialized_at = now
            generated_count += 1

        subscription.next_billing_date = next_occurrence_after(
            today,
            subscription.billing_anchor,
            subscription.cadence,
            subscription.cadence_interval,
        )

    await session.commit()
    return MaterializationResult(generated_count, skipped_archived)


def make_occurrence_key(subscription_id: UUID, scheduled_date: date) -> str:
    return f"{subscription_id}|{scheduled_date.isoformat()}"
