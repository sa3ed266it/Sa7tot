from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.models.entities import (
    Profile,
    PushDeviceToken,
    Subscription,
    SubscriptionReminderDelivery,
    SubscriptionReminderDeviceDelivery,
)
from app.services.apns import APNsClient, APNsError, APNsSendResult, PushPayload
from app.services.subscriptions import subscription_display_name

logger = logging.getLogger(__name__)

REMINDER_TYPE = "subscription_renewal"
LEAD_DAYS = 7
DELIVERY_TIME = time(hour=9)
CATCH_UP_DAYS = 3
CLAIM_LEASE = timedelta(minutes=15)
MAX_RETRY_DELAY = timedelta(hours=6)
TERMINAL_EVENT_STATUSES = {"completed", "cancelled", "expired"}
TERMINAL_DEVICE_STATUSES = {"sent", "permanent_failure", "expired"}


class APNsSender(Protocol):
    async def send(self, device_token: str, payload: PushPayload) -> APNsSendResult: ...


@dataclass(frozen=True)
class ReminderRunSummary:
    eligible_subscriptions: int = 0
    logical_events_created_or_reused: int = 0
    device_deliveries_attempted: int = 0
    sent: int = 0
    permanent_failures: int = 0
    retryable_failures: int = 0
    skipped_invalid_timezone: int = 0
    skipped_before_target: int = 0
    skipped_before_delivery_time: int = 0
    skipped_new_inside_window: int = 0
    skipped_inactive: int = 0
    expired: int = 0
    cancelled: int = 0
    no_active_devices: int = 0

    def add(self, **changes: int) -> ReminderRunSummary:
        values = self.__dict__.copy()
        for key, value in changes.items():
            values[key] = values[key] + value
        return ReminderRunSummary(**values)


@dataclass(frozen=True)
class Eligibility:
    eligible: bool
    reason: str
    renewal_date: date
    target_date: date
    local_date: date
    local_time: time
    timezone: str


class SubscriptionReminderService:
    """Durable, provider-agnostic server-side subscription reminder runner."""

    def __init__(
        self,
        session: AsyncSession,
        *,
        environment: str,
        now_utc: datetime | None = None,
        apns_client: APNsSender | None = None,
        settings: Settings | None = None,
        dry_run: bool = False,
    ):
        environment = environment.lower()
        if environment not in {"development", "production"}:
            raise ValueError("environment must be development or production")
        self.session = session
        self.environment = environment
        self.now_utc = _as_utc(now_utc or datetime.now(UTC))
        self.settings = settings or get_settings()
        self.apns_client = apns_client or APNsClient(self.settings)
        self.dry_run = dry_run

    async def run(self) -> ReminderRunSummary:
        summary = ReminderRunSummary()
        subscriptions = list(
            (
                await self.session.scalars(
                    select(Subscription).order_by(Subscription.user_id, Subscription.next_billing_date, Subscription.id)
                )
            ).all()
        )

        for subscription in subscriptions:
            await self._cancel_superseded_events(subscription)
            if subscription.status != "active":
                await self._cancel_open_events(subscription.id, subscription.user_id)
                summary = summary.add(skipped_inactive=1, cancelled=1)
                continue

            profile = await self.session.get(Profile, subscription.user_id)
            eligibility = self._eligibility(subscription, profile)
            if eligibility is None:
                summary = summary.add(skipped_invalid_timezone=1)
                continue

            if not eligibility.eligible:
                if eligibility.reason == "before_target":
                    summary = summary.add(skipped_before_target=1)
                elif eligibility.reason == "before_delivery_time":
                    summary = summary.add(skipped_before_delivery_time=1)
                elif eligibility.reason == "new_inside_window":
                    summary = summary.add(skipped_new_inside_window=1)
                elif eligibility.reason == "expired_window":
                    expired = await self._expire_event(
                        subscription.user_id,
                        subscription.id,
                        subscription.next_billing_date,
                    )
                    summary = summary.add(expired=expired)
                elif eligibility.reason == "renewal_reached":
                    expired = await self._expire_event(
                        subscription.user_id,
                        subscription.id,
                        subscription.next_billing_date,
                    )
                    summary = summary.add(expired=expired)
                continue

            summary = summary.add(eligible_subscriptions=1)
            if self.dry_run:
                summary = await self._dry_run_summary(subscription, summary)
            else:
                summary = await self._process_subscription(subscription, profile, eligibility, summary)

        return summary

    def _eligibility(self, subscription: Subscription, profile: Profile | None) -> Eligibility | None:
        if profile is None:
            logger.warning("subscription reminder skipped: profile missing")
            return None
        try:
            timezone = ZoneInfo(profile.timezone)
        except (ZoneInfoNotFoundError, ValueError):
            logger.warning("subscription reminder skipped: invalid profile timezone")
            return None

        local_now = self.now_utc.astimezone(timezone)
        renewal_date = subscription.next_billing_date
        target_date = renewal_date - timedelta(days=LEAD_DAYS)
        local_date = local_now.date()
        local_time = local_now.timetz().replace(tzinfo=None)

        if local_date >= renewal_date:
            reason = "renewal_reached"
        elif local_date < target_date:
            reason = "before_target"
        elif local_time < DELIVERY_TIME:
            reason = "before_delivery_time"
        elif local_date > target_date + timedelta(days=CATCH_UP_DAYS):
            reason = "expired_window"
        elif (
            subscription.schedule_changed_at is not None
            and subscription.schedule_changed_at.astimezone(timezone).date() > target_date
        ):
            reason = "new_inside_window"
        else:
            reason = "eligible"

        return Eligibility(
            eligible=reason == "eligible",
            reason=reason,
            renewal_date=renewal_date,
            target_date=target_date,
            local_date=local_date,
            local_time=local_time,
            timezone=profile.timezone,
        )

    async def _dry_run_summary(
        self,
        subscription: Subscription,
        summary: ReminderRunSummary,
    ) -> ReminderRunSummary:
        event = await self._find_event(subscription.user_id, subscription.id, subscription.next_billing_date)
        if event is None:
            summary = summary.add(logical_events_created_or_reused=1)
        elif event.status not in TERMINAL_EVENT_STATUSES:
            summary = summary.add(logical_events_created_or_reused=1)

        devices = list(
            (
                await self.session.scalars(
                    select(PushDeviceToken).where(
                        PushDeviceToken.user_id == subscription.user_id,
                        PushDeviceToken.is_active.is_(True),
                        PushDeviceToken.platform == "ios",
                        PushDeviceToken.environment == self.environment,
                    )
                )
            ).all()
        )
        existing_sent_ids: set[UUID] = set()
        if event is not None:
            existing_sent_ids = {
                row.push_device_token_id
                for row in (
                    await self.session.scalars(
                        select(SubscriptionReminderDeviceDelivery).where(
                            SubscriptionReminderDeviceDelivery.reminder_delivery_id == event.id,
                            SubscriptionReminderDeviceDelivery.status == "sent",
                        )
                    )
                ).all()
            }
        attempted = sum(1 for device in devices if device.id not in existing_sent_ids)
        if attempted == 0 and not devices:
            return summary.add(no_active_devices=1)
        return summary.add(device_deliveries_attempted=attempted)

    async def _process_subscription(
        self,
        subscription: Subscription,
        profile: Profile | None,
        eligibility: Eligibility,
        summary: ReminderRunSummary,
    ) -> ReminderRunSummary:
        event = await self._get_or_create_event(subscription)
        summary = summary.add(logical_events_created_or_reused=1)
        if event.status in TERMINAL_EVENT_STATUSES:
            return summary
        if not await self._claim_event(event):
            return summary

        devices = list(
            (
                await self.session.scalars(
                    select(PushDeviceToken).where(
                        PushDeviceToken.user_id == subscription.user_id,
                        PushDeviceToken.is_active.is_(True),
                        PushDeviceToken.platform == "ios",
                        PushDeviceToken.environment == self.environment,
                    )
                )
            ).all()
        )
        if not devices:
            await self._set_event_pending(event.id)
            return summary.add(no_active_devices=1)

        await self._ensure_device_rows(event.id, subscription.user_id, devices)
        await self._reconcile_device_rows(event.id, subscription.user_id, devices)
        rows = list(
            (
                await self.session.execute(
                    select(SubscriptionReminderDeviceDelivery, PushDeviceToken)
                    .join(
                        PushDeviceToken,
                        PushDeviceToken.id == SubscriptionReminderDeviceDelivery.push_device_token_id,
                    )
                    .where(
                        SubscriptionReminderDeviceDelivery.reminder_delivery_id == event.id,
                        SubscriptionReminderDeviceDelivery.user_id == subscription.user_id,
                        PushDeviceToken.user_id == subscription.user_id,
                        PushDeviceToken.is_active.is_(True),
                        PushDeviceToken.environment == self.environment,
                    )
                )
            ).all()
        )

        for delivery, device in rows:
            if delivery.status in TERMINAL_DEVICE_STATUSES:
                continue
            if delivery.next_attempt_at is not None and delivery.next_attempt_at > self.now_utc:
                continue

            current_subscription = await self.session.get(Subscription, subscription.id)
            current_profile = await self.session.get(Profile, subscription.user_id)
            current_eligibility = (
                self._eligibility(current_subscription, current_profile) if current_subscription else None
            )
            if (
                current_subscription is None
                or current_subscription.user_id != event.user_id
                or current_subscription.status != "active"
                or current_subscription.next_billing_date != event.renewal_date
                or current_eligibility is None
                or not current_eligibility.eligible
            ):
                await self._cancel_or_expire_current_event(event.id, current_eligibility)
                break

            delivery.attempt_count += 1
            delivery.last_attempt_at = self.now_utc
            payload = PushPayload(
                title="Sa7tot",
                body=_localized_body(current_subscription, current_profile),
                subscription_id=str(current_subscription.id),
                reminder_type=REMINDER_TYPE,
                renewal_date=event.renewal_date.isoformat(),
                lead_days=LEAD_DAYS,
            )
            summary = summary.add(device_deliveries_attempted=1)
            try:
                result = await self.apns_client.send(device.token, payload)
            except APNsError as error:
                delivery.last_error_kind = error.kind
                delivery.last_error_reason = error.reason
                if error.kind == "permanent":
                    delivery.status = "permanent_failure"
                    device.is_active = False
                    delivery.next_attempt_at = None
                    summary = summary.add(permanent_failures=1)
                else:
                    delivery.status = "retryable"
                    delivery.next_attempt_at = self.now_utc + _retry_delay(delivery.attempt_count)
                    summary = summary.add(retryable_failures=1)
                await self.session.commit()
                continue

            delivery.status = "sent"
            delivery.apns_id = result.apns_id
            delivery.next_attempt_at = None
            delivery.last_error_kind = None
            delivery.last_error_reason = None
            await self.session.commit()
            summary = summary.add(sent=1)

        await self._finalize_event(event.id)
        return summary

    async def _get_or_create_event(self, subscription: Subscription) -> SubscriptionReminderDelivery:
        insert = pg_insert(SubscriptionReminderDelivery).values(
            user_id=subscription.user_id,
            subscription_id=subscription.id,
            renewal_date=subscription.next_billing_date,
            reminder_type=REMINDER_TYPE,
            lead_days=LEAD_DAYS,
            status="pending",
        )
        await self.session.execute(
            insert.on_conflict_do_nothing(constraint="uq_subscription_reminder_deliveries_identity")
        )
        await self.session.flush()
        return await self._find_event(subscription.user_id, subscription.id, subscription.next_billing_date, lock=True)

    async def _find_event(
        self,
        user_id: UUID,
        subscription_id: UUID,
        renewal_date: date,
        *,
        lock: bool = False,
    ) -> SubscriptionReminderDelivery | None:
        query = select(SubscriptionReminderDelivery).where(
            SubscriptionReminderDelivery.user_id == user_id,
            SubscriptionReminderDelivery.subscription_id == subscription_id,
            SubscriptionReminderDelivery.renewal_date == renewal_date,
            SubscriptionReminderDelivery.reminder_type == REMINDER_TYPE,
            SubscriptionReminderDelivery.lead_days == LEAD_DAYS,
        )
        if lock:
            query = query.with_for_update()
        return await self.session.scalar(query)

    async def _claim_event(self, event: SubscriptionReminderDelivery) -> bool:
        if event.status in TERMINAL_EVENT_STATUSES:
            return False
        if (
            event.status == "sending"
            and event.claimed_at is not None
            and event.claimed_at > self.now_utc - CLAIM_LEASE
        ):
            return False
        event.status = "sending"
        event.claimed_at = self.now_utc
        await self.session.commit()
        return True

    async def _ensure_device_rows(
        self,
        event_id: UUID,
        user_id: UUID,
        devices: list[PushDeviceToken],
    ) -> None:
        for device in devices:
            insert = pg_insert(SubscriptionReminderDeviceDelivery).values(
                user_id=user_id,
                reminder_delivery_id=event_id,
                push_device_token_id=device.id,
                status="pending",
                attempt_count=0,
            )
            await self.session.execute(
                insert.on_conflict_do_nothing(constraint="uq_subscription_reminder_device_deliveries_identity")
            )
        await self.session.commit()

    async def _reconcile_device_rows(
        self,
        event_id: UUID,
        user_id: UUID,
        active_devices: list[PushDeviceToken],
    ) -> None:
        active_ids = {device.id for device in active_devices}
        rows = list(
            (
                await self.session.execute(
                    select(SubscriptionReminderDeviceDelivery, PushDeviceToken)
                    .join(
                        PushDeviceToken,
                        PushDeviceToken.id == SubscriptionReminderDeviceDelivery.push_device_token_id,
                    )
                    .where(
                        SubscriptionReminderDeviceDelivery.reminder_delivery_id == event_id,
                        SubscriptionReminderDeviceDelivery.user_id == user_id,
                    )
                )
            ).all()
        )
        for delivery, device in rows:
            if device.id in active_ids and delivery.status == "expired":
                delivery.status = "pending"
                delivery.next_attempt_at = None
            elif device.id not in active_ids and delivery.status not in TERMINAL_DEVICE_STATUSES:
                delivery.status = "expired"
                delivery.next_attempt_at = None
        await self.session.commit()

    async def _finalize_event(self, event_id: UUID) -> None:
        event = await self.session.get(SubscriptionReminderDelivery, event_id)
        if event is None or event.status in {"cancelled", "expired"}:
            return
        rows = list(
            (
                await self.session.scalars(
                    select(SubscriptionReminderDeviceDelivery).where(
                        SubscriptionReminderDeviceDelivery.reminder_delivery_id == event_id
                    )
                )
            ).all()
        )
        event.claimed_at = None
        if rows and all(row.status in TERMINAL_DEVICE_STATUSES for row in rows):
            event.status = "completed"
            event.completed_at = self.now_utc
        else:
            event.status = "pending"
        await self.session.commit()

    async def _set_event_pending(self, event_id: UUID) -> None:
        event = await self.session.get(SubscriptionReminderDelivery, event_id)
        if event is not None and event.status not in TERMINAL_EVENT_STATUSES:
            event.status = "pending"
            event.claimed_at = None
            await self.session.commit()

    async def _cancel_or_expire_current_event(
        self,
        event_id: UUID,
        eligibility: Eligibility | None,
    ) -> None:
        event = await self.session.get(SubscriptionReminderDelivery, event_id)
        if event is None or event.status in TERMINAL_EVENT_STATUSES:
            return
        if eligibility is not None and eligibility.reason in {"before_target", "before_delivery_time"}:
            event.status = "pending"
        else:
            event.status = "expired" if eligibility is not None else "cancelled"
            event.completed_at = self.now_utc
            await self.session.execute(
                SubscriptionReminderDeviceDelivery.__table__.update()
                .where(
                    SubscriptionReminderDeviceDelivery.reminder_delivery_id == event_id,
                    SubscriptionReminderDeviceDelivery.status.not_in(TERMINAL_DEVICE_STATUSES),
                )
                .values(status="expired", next_attempt_at=None)
            )
        event.claimed_at = None
        await self.session.commit()

    async def _cancel_superseded_events(self, subscription: Subscription) -> None:
        events = list(
            (
                await self.session.scalars(
                    select(SubscriptionReminderDelivery).where(
                        SubscriptionReminderDelivery.user_id == subscription.user_id,
                        SubscriptionReminderDelivery.subscription_id == subscription.id,
                        SubscriptionReminderDelivery.renewal_date != subscription.next_billing_date,
                        SubscriptionReminderDelivery.status.not_in(TERMINAL_EVENT_STATUSES),
                    )
                )
            ).all()
        )
        for event in events:
            event.status = "cancelled"
            event.claimed_at = None
            event.completed_at = self.now_utc
            await self.session.execute(
                SubscriptionReminderDeviceDelivery.__table__.update()
                .where(
                    SubscriptionReminderDeviceDelivery.reminder_delivery_id == event.id,
                    SubscriptionReminderDeviceDelivery.status.not_in(TERMINAL_DEVICE_STATUSES),
                )
                .values(status="expired", next_attempt_at=None)
            )
        if events:
            await self.session.commit()

    async def _cancel_open_events(self, subscription_id: UUID, user_id: UUID) -> None:
        events = list(
            (
                await self.session.scalars(
                    select(SubscriptionReminderDelivery).where(
                        SubscriptionReminderDelivery.user_id == user_id,
                        SubscriptionReminderDelivery.subscription_id == subscription_id,
                        SubscriptionReminderDelivery.status.not_in(TERMINAL_EVENT_STATUSES),
                    )
                )
            ).all()
        )
        for event in events:
            event.status = "cancelled"
            event.claimed_at = None
            event.completed_at = self.now_utc
            await self.session.execute(
                SubscriptionReminderDeviceDelivery.__table__.update()
                .where(
                    SubscriptionReminderDeviceDelivery.reminder_delivery_id == event.id,
                    SubscriptionReminderDeviceDelivery.status.not_in(TERMINAL_DEVICE_STATUSES),
                )
                .values(status="expired", next_attempt_at=None)
            )
        if events:
            await self.session.commit()

    async def _expire_event(self, user_id: UUID, subscription_id: UUID, renewal_date: date) -> int:
        event = await self._find_event(user_id, subscription_id, renewal_date)
        if event is None or event.status in TERMINAL_EVENT_STATUSES:
            return 0
        event.status = "expired"
        event.claimed_at = None
        event.completed_at = self.now_utc
        await self.session.execute(
            SubscriptionReminderDeviceDelivery.__table__.update()
            .where(
                SubscriptionReminderDeviceDelivery.reminder_delivery_id == event.id,
                SubscriptionReminderDeviceDelivery.status.not_in(TERMINAL_DEVICE_STATUSES),
            )
            .values(status="expired", next_attempt_at=None)
        )
        await self.session.commit()
        return 1


def _localized_body(subscription: Subscription, profile: Profile | None) -> str:
    name = subscription_display_name(subscription)
    locale = (profile.locale or "en").lower() if profile else "en"
    if locale.startswith("it"):
        return f"{name} si rinnova tra 7 giorni."
    return f"{name} renews in 7 days."


def _retry_delay(attempt_count: int) -> timedelta:
    seconds = min(2 ** max(0, attempt_count - 1) * 60, int(MAX_RETRY_DELAY.total_seconds()))
    return timedelta(seconds=seconds)


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value.astimezone(UTC)
