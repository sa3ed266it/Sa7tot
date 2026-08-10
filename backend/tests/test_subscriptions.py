from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entities import SubscriptionOccurrence, Transaction
from app.services.materialization import materialize_due_subscriptions
from app.services.scheduling import (
    first_occurrence_on_or_after,
    next_occurrence_after,
    occurrence_at_index,
)

TEST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")


async def create_account(client: AsyncClient):
    response = await client.post(
        "/v1/accounts",
        json={"name": "Principale", "type": "bank", "currency_code": "EUR", "currency_exponent": 2},
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.mark.asyncio
async def test_subscription_identity_and_status(client: AsyncClient):
    account = await create_account(client)
    invalid = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "service_id": "netflix",
            "custom_name": "Netflix personale",
            "amount_minor": 1599,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": "2026-08-08",
        },
    )
    assert invalid.status_code == 422

    response = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "service_id": "netflix",
            "amount_minor": 1599,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": "2026-08-08",
        },
    )
    assert response.status_code == 201, response.text
    assert response.json()["display_name"] == "Netflix"

    paused = await client.post(f"/v1/subscriptions/{response.json()['id']}/pause")
    assert paused.status_code == 200
    resumed = await client.post(f"/v1/subscriptions/{response.json()['id']}/resume")
    assert resumed.status_code == 200
    assert resumed.json()["status"] == "active"
    cancelled = await client.post(f"/v1/subscriptions/{response.json()['id']}/cancel")
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"


@pytest.mark.asyncio
async def test_subscription_access_is_scoped_to_owner(client: AsyncClient, switch_user):
    account = await create_account(client)
    response = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "custom_name": "Solo mio",
            "amount_minor": 999,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": "2026-08-08",
        },
    )
    assert response.status_code == 201, response.text
    subscription_id = response.json()["id"]

    switch_user()
    assert (await client.get("/v1/subscriptions")).json() == []
    assert (await client.patch(f"/v1/subscriptions/{subscription_id}", json={"note": "No"})).status_code == 404
    assert (await client.post(f"/v1/subscriptions/{subscription_id}/cancel")).status_code == 404


@pytest.mark.asyncio
async def test_scheduler_handles_eom_leap_year_and_intervals():
    assert occurrence_at_index(date(2024, 1, 31), "monthly", 1, 1) == date(2024, 2, 29)
    assert occurrence_at_index(date(2023, 1, 31), "monthly", 1, 1) == date(2023, 2, 28)
    assert next_occurrence_after(date(2024, 2, 29), date(2024, 1, 31), "monthly", 1) == date(2024, 3, 31)
    assert first_occurrence_on_or_after(date(2024, 5, 1), date(2024, 1, 31), "monthly", 2) == date(2024, 5, 31)
    assert occurrence_at_index(date(2024, 2, 29), "yearly", 1, 1) == date(2025, 2, 28)


@pytest.mark.asyncio
async def test_materialization_is_idempotent_and_keeps_scheduled_date(client: AsyncClient, session: AsyncSession):
    account = await create_account(client)
    response = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "custom_name": "Palestra",
            "amount_minor": 2500,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": "2024-01-31",
            "next_billing_date": "2024-01-31",
        },
    )
    assert response.status_code == 201, response.text
    subscription_id = response.json()["id"]
    now = datetime(2024, 3, 31, 9, 15, tzinfo=UTC)

    first = await materialize_due_subscriptions(session, TEST_USER_ID, now)
    assert first.generated_count == 3
    second = await materialize_due_subscriptions(session, TEST_USER_ID, now)
    assert second.generated_count == 0

    transactions = list((await session.scalars(select(Transaction))).all())
    occurrences = list((await session.scalars(select(SubscriptionOccurrence))).all())
    assert len(transactions) == 3
    assert len(occurrences) == 3
    assert all(transaction.occurred_at == now for transaction in transactions)
    assert {transaction.local_day for transaction in transactions} == {
        date(2024, 1, 31),
        date(2024, 2, 29),
        date(2024, 3, 31),
    }
    assert all(occurrence.transaction_id is not None for occurrence in occurrences)
    assert {occurrence.subscription_id for occurrence in occurrences} == {UUID(subscription_id)}


@pytest.mark.asyncio
async def test_start_date_semantics_materialize_today_without_historical_backfill(client: AsyncClient):
    account = await create_account(client)
    today = datetime.now(UTC).astimezone(ZoneInfo("Europe/Rome")).date()
    past_anchor = today - timedelta(days=2)
    response = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "custom_name": "Palestra oggi",
            "amount_minor": 2500,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "weekly",
            "billing_anchor": today.isoformat(),
        },
    )
    assert response.status_code == 201, response.text
    assert response.json()["next_billing_date"] == today.isoformat()

    materialized = await client.post("/v1/subscriptions/materialize")
    assert materialized.status_code == 200, materialized.text
    assert materialized.json()["generated_count"] == 1
    repeated = await client.post("/v1/subscriptions/materialize")
    assert repeated.json()["generated_count"] == 0

    old_response = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "custom_name": "Nessun arretrato",
            "amount_minor": 2500,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "weekly",
            "billing_anchor": past_anchor.isoformat(),
        },
    )
    assert old_response.status_code == 201, old_response.text
    assert date.fromisoformat(old_response.json()["next_billing_date"]) > today


@pytest.mark.asyncio
async def test_materialized_subscription_without_note_has_null_note_and_preserves_metadata(
    client: AsyncClient, session: AsyncSession
):
    account = await create_account(client)
    today = datetime.now(UTC).astimezone(ZoneInfo("Europe/Rome")).date()
    response = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "service_id": "amazon-prime",
            "amount_minor": 499,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": today.isoformat(),
        },
    )
    assert response.status_code == 201, response.text
    subscription_id = UUID(response.json()["id"])

    materialization = await materialize_due_subscriptions(session, TEST_USER_ID)
    assert materialization.generated_count == 1

    transaction = await session.scalar(
        select(Transaction).where(Transaction.subscription_id == subscription_id)
    )
    assert transaction is not None
    assert transaction.note is None
    assert transaction.origin == "subscription"
    assert transaction.subscription_service_id == "amazon-prime"
    assert transaction.subscription_display_name == "Amazon Prime"


@pytest.mark.asyncio
async def test_materialized_subscription_with_user_note_retains_note(
    client: AsyncClient, session: AsyncSession
):
    account = await create_account(client)
    today = datetime.now(UTC).astimezone(ZoneInfo("Europe/Rome")).date()
    response = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "service_id": "amazon-prime",
            "amount_minor": 499,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": today.isoformat(),
            "note": "Family shared plan",
        },
    )
    assert response.status_code == 201, response.text
    subscription_id = UUID(response.json()["id"])

    materialization = await materialize_due_subscriptions(session, TEST_USER_ID)
    assert materialization.generated_count == 1

    transaction = await session.scalar(
        select(Transaction).where(Transaction.subscription_id == subscription_id)
    )
    assert transaction is not None
    assert transaction.note == "Family shared plan"
    assert transaction.subscription_service_id == "amazon-prime"
    assert transaction.subscription_display_name == "Amazon Prime"

