from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import pytest
from sqlalchemy import func, select

from app.models.entities import (
    Account,
    Profile,
    PushDeviceToken,
    Subscription,
    SubscriptionReminderDelivery,
    SubscriptionReminderDeviceDelivery,
)
from app.services.apns import APNsError, APNsSendResult, PushPayload
from app.services.subscription_reminders import SubscriptionReminderService

TEST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
OTHER_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
TARGET_NOW = datetime(2026, 8, 1, 7, 15, tzinfo=UTC)  # 09:15 in Europe/Rome
RENEWAL_DATE = date(2026, 8, 8)


class FakeAPNs:
    def __init__(self, outcomes: dict[str, list[APNsSendResult | APNsError]] | None = None):
        self.outcomes = outcomes or {}
        self.sent: list[tuple[str, PushPayload]] = []

    async def send(self, device_token: str, payload: PushPayload) -> APNsSendResult:
        self.sent.append((device_token, payload))
        outcome = self.outcomes.get(device_token, [APNsSendResult(apns_id=f"apns-{len(self.sent)}")])
        if len(outcome) > 1:
            current = outcome.pop(0)
        else:
            current = outcome[0]
        if isinstance(current, APNsError):
            raise current
        return current


async def add_subscription(
    session,
    *,
    user_id: UUID = TEST_USER_ID,
    renewal_date: date = RENEWAL_DATE,
    status: str = "active",
    timezone: str = "Europe/Rome",
    locale: str | None = "en-US",
    schedule_changed_at: datetime | None = None,
) -> Subscription:
    session.add(Profile(user_id=user_id, timezone=timezone, locale=locale, default_currency_code="EUR"))
    account = Account(
        user_id=user_id,
        name="Main",
        type="bank",
        currency_code="EUR",
        currency_exponent=2,
        opening_balance_minor=0,
        icon_name="building.columns.fill",
        color="#5E7CE2",
    )
    session.add(account)
    await session.flush()
    subscription = Subscription(
        user_id=user_id,
        account_id=account.id,
        service_id="netflix",
        amount_minor=1599,
        currency_code="EUR",
        currency_exponent=2,
        cadence="monthly",
        cadence_interval=1,
        billing_anchor=renewal_date,
        next_billing_date=renewal_date,
        schedule_changed_at=schedule_changed_at,
        status=status,
    )
    session.add(subscription)
    await session.commit()
    await session.refresh(subscription)
    return subscription


async def add_device(session, *, user_id: UUID = TEST_USER_ID, token: str, environment: str = "development"):
    device = PushDeviceToken(
        user_id=user_id,
        token=token,
        platform="ios",
        environment=environment,
        is_active=True,
    )
    session.add(device)
    await session.commit()
    await session.refresh(device)
    return device


def service(session, fake: FakeAPNs, *, now: datetime = TARGET_NOW, environment: str = "development"):
    return SubscriptionReminderService(
        session,
        environment=environment,
        now_utc=now,
        apns_client=fake,
    )


@pytest.mark.asyncio
async def test_exact_target_date_sends_localized_name_and_safe_payload(session):
    subscription = await add_subscription(session)
    await add_device(session, token="a" * 64)
    fake = FakeAPNs()

    summary = await service(session, fake).run()

    assert summary.sent == 1
    assert len(fake.sent) == 1
    token, payload = fake.sent[0]
    assert token == "a" * 64
    assert payload.title == "Sa7tot"
    assert payload.body == "Netflix renews in 7 days."
    encoded = payload.as_apns_payload()
    assert encoded["subscription_id"] == str(subscription.id)
    assert encoded["reminder_type"] == "subscription_renewal"
    assert encoded["renewal_date"] == "2026-08-08"
    assert encoded["lead_days"] == 7
    assert "amount" not in encoded
    assert "currency" not in encoded


@pytest.mark.asyncio
async def test_italian_profile_localizes_body(session):
    await add_subscription(session, locale="it-IT")
    await add_device(session, token="b" * 64)
    fake = FakeAPNs()

    await service(session, fake).run()

    assert fake.sent[0][1].body == "Netflix si rinnova tra 7 giorni."


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("now", "reason"),
    [
        (datetime(2026, 7, 31, 7, 15, tzinfo=UTC), "before_target"),
        (datetime(2026, 8, 1, 6, 59, tzinfo=UTC), "before_delivery_time"),
        (datetime(2026, 8, 5, 7, 15, tzinfo=UTC), "expired_window"),
        (datetime(2026, 8, 8, 7, 15, tzinfo=UTC), "renewal_reached"),
    ],
)
async def test_date_and_delivery_time_boundaries(session, now, reason):
    subscription = await add_subscription(session)
    await add_device(session, token="c" * 64)
    fake = FakeAPNs()
    eligibility = service(session, fake, now=now)._eligibility(subscription, await session.get(Profile, TEST_USER_ID))

    assert eligibility is not None
    assert eligibility.reason == reason
    assert eligibility.eligible is False


@pytest.mark.asyncio
async def test_catch_up_is_allowed_only_for_existing_schedule(session):
    before_target = TARGET_NOW - timedelta(days=1)
    await add_subscription(session, schedule_changed_at=before_target)
    await add_device(session, token="d" * 64)
    fake = FakeAPNs()

    summary = await service(session, fake, now=datetime(2026, 8, 3, 7, 15, tzinfo=UTC)).run()

    assert summary.sent == 1


@pytest.mark.asyncio
async def test_europe_rome_dst_boundary_uses_local_delivery_clock(session):
    subscription = await add_subscription(session, renewal_date=date(2026, 3, 29))
    fake = FakeAPNs()
    eligibility = service(
        session,
        fake,
        now=datetime(2026, 3, 22, 8, 15, tzinfo=UTC),
    )._eligibility(subscription, await session.get(Profile, TEST_USER_ID))

    assert eligibility is not None
    assert eligibility.local_date == date(2026, 3, 22)
    assert eligibility.local_time == datetime(2026, 3, 22, 9, 15).time()
    assert eligibility.eligible is True


@pytest.mark.asyncio
async def test_new_subscription_inside_window_does_not_send_misleading_reminder(session):
    await add_subscription(
        session,
        schedule_changed_at=datetime(2026, 8, 2, 8, 0, tzinfo=UTC),
    )
    await add_device(session, token="e" * 64)
    fake = FakeAPNs()

    summary = await service(session, fake, now=datetime(2026, 8, 3, 7, 15, tzinfo=UTC)).run()

    assert summary.sent == 0
    assert summary.skipped_new_inside_window == 1
    assert fake.sent == []
    assert await session.scalar(select(func.count()).select_from(SubscriptionReminderDelivery)) == 0


@pytest.mark.asyncio
async def test_invalid_or_missing_timezone_fails_closed(session):
    await add_subscription(session, timezone="Mars/Olympus")
    await add_device(session, token="f" * 64)
    fake = FakeAPNs()

    summary = await service(session, fake).run()

    assert summary.skipped_invalid_timezone == 1
    assert fake.sent == []
    assert await session.scalar(select(func.count()).select_from(SubscriptionReminderDelivery)) == 0


@pytest.mark.asyncio
@pytest.mark.parametrize("status", ["paused", "cancelled"])
async def test_only_active_subscriptions_are_eligible(session, status):
    await add_subscription(session, status=status)
    await add_device(session, token="1" * 64)
    fake = FakeAPNs()

    summary = await service(session, fake).run()

    assert summary.skipped_inactive == 1
    assert fake.sent == []


@pytest.mark.asyncio
async def test_idempotency_does_not_resend_completed_device(session):
    await add_subscription(session)
    await add_device(session, token="2" * 64)
    fake = FakeAPNs()
    runner = service(session, fake)

    first = await runner.run()
    second = await runner.run()

    assert first.sent == 1
    assert second.sent == 0
    assert len(fake.sent) == 1
    assert await session.scalar(select(func.count()).select_from(SubscriptionReminderDelivery)) == 1
    assert await session.scalar(select(func.count()).select_from(SubscriptionReminderDeviceDelivery)) == 1


@pytest.mark.asyncio
async def test_all_active_devices_receive_independent_delivery(session):
    await add_subscription(session)
    await add_device(session, token="3" * 64)
    await add_device(session, token="4" * 64)
    await add_device(session, token="5" * 64, environment="production")
    inactive = await add_device(session, token="6" * 64)
    inactive.is_active = False
    await session.commit()
    fake = FakeAPNs()

    summary = await service(session, fake).run()

    assert summary.sent == 2
    assert {token for token, _ in fake.sent} == {"3" * 64, "4" * 64}
    assert await session.scalar(select(func.count()).select_from(SubscriptionReminderDeviceDelivery)) == 2


@pytest.mark.asyncio
async def test_permanent_device_failure_deactivates_only_that_device(session):
    await add_subscription(session)
    bad = await add_device(session, token="7" * 64)
    await add_device(session, token="8" * 64)
    fake = FakeAPNs(
        {
            "7" * 64: [APNsError("permanent", "BadDeviceToken", 400)],
            "8" * 64: [APNsSendResult("good")],
        }
    )

    summary = await service(session, fake).run()

    assert summary.permanent_failures == 1
    assert summary.sent == 1
    await session.refresh(bad)
    assert bad.is_active is False
    active_count = await session.scalar(
        select(func.count()).select_from(PushDeviceToken).where(PushDeviceToken.is_active.is_(True))
    )
    assert active_count == 1


@pytest.mark.asyncio
async def test_provider_auth_failure_does_not_deactivate_device(session):
    await add_subscription(session)
    device = await add_device(session, token="9" * 64)
    fake = FakeAPNs({"9" * 64: [APNsError("authentication", "InvalidProviderToken", 403)]})

    summary = await service(session, fake).run()

    assert summary.retryable_failures == 1
    await session.refresh(device)
    assert device.is_active is True


@pytest.mark.asyncio
async def test_transient_failure_is_bounded_and_retryable(session):
    await add_subscription(session)
    fake = FakeAPNs({"a" * 64: [APNsError("transient", "TooManyRequests", 429), APNsSendResult("retry") ]})
    await add_device(session, token="a" * 64)

    first = await service(session, fake).run()
    second = await service(session, fake, now=TARGET_NOW + timedelta(minutes=1, seconds=1)).run()

    assert first.retryable_failures == 1
    assert second.sent == 1


@pytest.mark.asyncio
async def test_schedule_edit_cancels_old_renewal_identity(session):
    subscription = await add_subscription(session, renewal_date=date(2026, 8, 7), schedule_changed_at=None)
    first_fake = FakeAPNs()
    await service(session, first_fake, now=datetime(2026, 7, 31, 7, 15, tzinfo=UTC)).run()

    subscription.next_billing_date = RENEWAL_DATE
    subscription.schedule_changed_at = datetime(2026, 7, 31, 7, 20, tzinfo=UTC)
    await session.commit()
    await add_device(session, token="b" * 64)
    second_fake = FakeAPNs()
    await service(session, second_fake).run()

    events = list((await session.scalars(select(SubscriptionReminderDelivery))).all())
    assert len(events) == 2
    assert {event.status for event in events} == {"cancelled", "completed"}


@pytest.mark.asyncio
async def test_cross_user_device_is_not_targeted(session):
    await add_subscription(session)
    await add_device(session, user_id=OTHER_USER_ID, token="c" * 64)
    fake = FakeAPNs()

    summary = await service(session, fake).run()

    assert summary.no_active_devices == 1
    assert fake.sent == []
