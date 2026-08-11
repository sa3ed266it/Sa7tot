from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entities import Profile

TEST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")


async def create_account(client: AsyncClient):
    response = await client.post(
        "/v1/accounts",
        json={"name": "Principale", "type": "bank", "currency_code": "EUR", "currency_exponent": 2},
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.mark.asyncio
async def test_profile_currency_update_is_normalized_and_preserves_financial_records(
    client: AsyncClient,
):
    account = await create_account(client)
    category = await client.post("/v1/categories", json={"name": "Cibo", "income": False})
    assert category.status_code == 201, category.text
    transaction = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": account["id"],
            "category_id": category.json()["id"],
            "amount_minor": 1250,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert transaction.status_code == 201, transaction.text
    budget = await client.put(
        "/v1/budget/main",
        json={"amount_minor": 10000, "currency_code": "EUR", "currency_exponent": 2, "period_type": "month"},
    )
    assert budget.status_code == 200, budget.text
    subscription = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "custom_name": "Palestra",
            "amount_minor": 2500,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": "2026-08-08",
        },
    )
    assert subscription.status_code == 201, subscription.text

    updated = await client.patch("/v1/profile", json={"default_currency_code": " usd "})
    assert updated.status_code == 200, updated.text
    assert updated.json()["default_currency_code"] == "USD"

    account_list = await client.get("/v1/accounts")
    assert account_list.json()[0]["currency_code"] == "EUR"
    assert (await client.get(f"/v1/transactions/{transaction.json()['id']}")).json()["currency_code"] == "EUR"
    assert (await client.get("/v1/budget")).json()["main"]["currency_code"] == "EUR"
    assert (await client.get("/v1/subscriptions")).json()[0]["currency_code"] == "EUR"


@pytest.mark.asyncio
async def test_profile_currency_update_rejects_invalid_values_and_is_user_scoped(
    client: AsyncClient,
    switch_user,
    session: AsyncSession,
):
    bootstrap = await client.get("/v1/bootstrap")
    assert bootstrap.status_code == 200
    invalid = await client.patch("/v1/profile", json={"default_currency_code": "12"})
    assert invalid.status_code == 422

    own = await client.patch("/v1/profile", json={"default_currency_code": "USD"})
    assert own.status_code == 200

    switch_user()
    other = await client.patch("/v1/profile", json={"default_currency_code": "GBP"})
    assert other.status_code == 200
    assert other.json()["user_id"] != str(TEST_USER_ID)

    original = await session.scalar(select(Profile).where(Profile.user_id == TEST_USER_ID))
    assert original is not None
    assert original.default_currency_code == "USD"


@pytest.mark.asyncio
async def test_profile_calendar_preferences_update_and_validate(client: AsyncClient):
    updated = await client.patch(
        "/v1/profile",
        json={"month_start_day": 15, "week_start_day": 3},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["month_start_day"] == 15
    assert updated.json()["week_start_day"] == 3

    bootstrap = await client.get("/v1/bootstrap")
    assert bootstrap.status_code == 200, bootstrap.text
    assert bootstrap.json()["profile"]["month_start_day"] == 15
    assert bootstrap.json()["profile"]["week_start_day"] == 3

    invalid_month = await client.patch("/v1/profile", json={"month_start_day": 0})
    invalid_week = await client.patch("/v1/profile", json={"week_start_day": 8})
    assert invalid_month.status_code == 422
    assert invalid_week.status_code == 422
