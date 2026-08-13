from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Account, Category, Subscription
from app.schemas.common import Cadence, SubscriptionStatus
from app.schemas.subscriptions import SubscriptionCreate, SubscriptionUpdate
from app.services.common import display_subscription_name, get_or_create_profile, normalize_currency
from app.services.scheduling import first_occurrence_on_or_after, next_occurrence_after


async def get_subscription(session: AsyncSession, user_id: UUID, subscription_id: UUID) -> Subscription:
    subscription = await session.scalar(
        select(Subscription).where(
            Subscription.id == subscription_id,
            Subscription.user_id == user_id,
        )
    )
    if subscription is None:
        raise DomainError(404, "subscription not found", "subscription_not_found")
    return subscription


async def list_subscriptions(session: AsyncSession, user_id: UUID) -> list[Subscription]:
    status_order = {"active": 0, "paused": 1, "cancelled": 2}
    query = (
        select(Subscription)
        .where(Subscription.user_id == user_id)
        .order_by(Subscription.next_billing_date.asc(), Subscription.id.asc())
    )
    subscriptions = list((await session.scalars(query)).all())
    return sorted(
        subscriptions,
        key=lambda item: (status_order.get(item.status, 99), item.next_billing_date, str(item.id)),
    )


async def create_subscription(session: AsyncSession, user_id: UUID, payload: SubscriptionCreate) -> Subscription:
    account = await _active_account(session, user_id, payload.account_id)
    category = await _optional_category(session, user_id, payload.category_id)
    currency_code = normalize_currency(payload.currency_code)
    if currency_code != account.currency_code:
        raise DomainError(422, "subscription currency must match the account currency", "currency_mismatch")
    today = await _today_for_user(session, user_id)
    calculated_next_billing_date = first_occurrence_on_or_after(
        today,
        payload.billing_anchor,
        payload.cadence.value,
        payload.cadence_interval,
    )
    next_billing_date = payload.next_billing_date or calculated_next_billing_date
    subscription = Subscription(
        user_id=user_id,
        account_id=account.id,
        category_id=category.id if category else None,
        service_id=_clean(payload.service_id),
        custom_name=_clean(payload.custom_name),
        amount_minor=payload.amount_minor,
        currency_code=currency_code,
        currency_exponent=payload.currency_exponent,
        cadence=payload.cadence.value,
        cadence_interval=payload.cadence_interval,
        billing_anchor=payload.billing_anchor,
        next_billing_date=next_billing_date,
        schedule_changed_at=datetime.now(UTC),
        status=payload.status.value,
        note=_clean(payload.note),
    )
    session.add(subscription)
    await session.commit()
    await session.refresh(subscription)
    return subscription


async def update_subscription(
    session: AsyncSession, user_id: UUID, subscription_id: UUID, payload: SubscriptionUpdate
) -> Subscription:
    subscription = await get_subscription(session, user_id, subscription_id)
    values = payload.model_dump(exclude_unset=True)
    account_id = values.get("account_id", subscription.account_id)
    account = await _active_account(session, user_id, account_id)
    category_id = values.get("category_id", subscription.category_id)
    category = await _optional_category(session, user_id, category_id)
    currency_code = normalize_currency(values.get("currency_code", subscription.currency_code))
    currency_exponent = values.get("currency_exponent", subscription.currency_exponent)
    if currency_code != account.currency_code:
        raise DomainError(422, "subscription currency must match the account currency", "currency_mismatch")

    service_id = values.get("service_id", subscription.service_id)
    custom_name = values.get("custom_name", subscription.custom_name)
    if "service_id" in values or "custom_name" in values:
        if bool(service_id) == bool(custom_name):
            raise DomainError(422, "provide exactly one subscription identity", "invalid_subscription_identity")

    cadence = values.get("cadence", subscription.cadence)
    cadence_value = cadence.value if isinstance(cadence, Cadence) else cadence
    billing_anchor = values.get("billing_anchor", subscription.billing_anchor)
    schedule_changed = any(key in values for key in ("billing_anchor", "cadence", "cadence_interval"))
    if schedule_changed:
        today = await _today_for_user(session, user_id)
        next_billing_date = first_occurrence_on_or_after(
            today,
            billing_anchor,
            cadence_value,
            values.get("cadence_interval", subscription.cadence_interval),
        )
    else:
        next_billing_date = subscription.next_billing_date

    subscription.account_id = account.id
    subscription.category_id = category.id if category else None
    subscription.service_id = _clean(service_id)
    subscription.custom_name = _clean(custom_name)
    subscription.amount_minor = values.get("amount_minor", subscription.amount_minor)
    subscription.currency_code = currency_code
    subscription.currency_exponent = currency_exponent
    subscription.cadence = cadence_value
    subscription.cadence_interval = values.get("cadence_interval", subscription.cadence_interval)
    subscription.billing_anchor = billing_anchor
    subscription.next_billing_date = next_billing_date
    if schedule_changed:
        subscription.schedule_changed_at = datetime.now(UTC)
    subscription.note = _clean(values.get("note", subscription.note))
    await session.commit()
    await session.refresh(subscription)
    return subscription


async def change_status(
    session: AsyncSession, user_id: UUID, subscription_id: UUID, status: SubscriptionStatus
) -> Subscription:
    subscription = await get_subscription(session, user_id, subscription_id)
    today = await _today_for_user(session, user_id)
    subscription.status = status.value
    if status == SubscriptionStatus.active:
        subscription.next_billing_date = next_occurrence_after(
            today,
            subscription.billing_anchor,
            subscription.cadence,
            subscription.cadence_interval,
        )
    await session.commit()
    await session.refresh(subscription)
    return subscription


async def _today_for_user(session: AsyncSession, user_id: UUID) -> date:
    profile = await get_or_create_profile(session, user_id)
    return datetime.now(UTC).astimezone(ZoneInfo(profile.timezone)).date()


def subscription_display_name(subscription: Subscription) -> str:
    return display_subscription_name(subscription.service_id, subscription.custom_name)


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None


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
