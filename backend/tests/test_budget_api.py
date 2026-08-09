from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from uuid import UUID

import pytest

from app.models.entities import Account, Category, Transaction

TEST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")


@pytest.mark.asyncio
async def test_budget_summary_uses_remote_expenses_only(session, client):
    category = Category(
        user_id=TEST_USER_ID,
        name="Cibo",
        normalized_name="cibo",
        icon_identifier="sf:fork.knife",
        color="#00AA00",
    )
    source = Account(
        user_id=category.user_id,
        name="Conto",
        currency_code="EUR",
        currency_exponent=2,
    )
    destination = Account(
        user_id=category.user_id,
        name="Risparmio",
        currency_code="EUR",
        currency_exponent=2,
    )
    session.add_all([category, source, destination])
    await session.flush()
    now = datetime.now(UTC)
    session.add_all(
        [
            Transaction(
                user_id=category.user_id,
                kind="expense",
                account_id=source.id,
                amount_minor=1250,
                currency_code="EUR",
                currency_exponent=2,
                occurred_at=now - timedelta(hours=1),
                local_day=date.today(),
                category_id=category.id,
                origin="subscription",
            ),
            Transaction(
                user_id=category.user_id,
                kind="income",
                account_id=source.id,
                amount_minor=5000,
                currency_code="EUR",
                currency_exponent=2,
                occurred_at=now - timedelta(hours=1),
                local_day=date.today(),
            ),
            Transaction(
                user_id=category.user_id,
                kind="expense",
                account_id=source.id,
                amount_minor=9000,
                currency_code="EUR",
                currency_exponent=2,
                occurred_at=now + timedelta(days=1),
                local_day=date.today(),
                category_id=category.id,
            ),
            Transaction(
                user_id=category.user_id,
                kind="transfer",
                account_id=source.id,
                destination_account_id=destination.id,
                amount_minor=7000,
                currency_code="EUR",
                currency_exponent=2,
                occurred_at=now - timedelta(hours=1),
                local_day=date.today(),
            ),
        ]
    )
    await session.commit()

    response = await client.put(
        "/v1/budget/main",
        json={"amount_minor": 10000, "currency_code": "EUR", "currency_exponent": 2, "period_type": "month"},
    )
    assert response.status_code == 200
    assert response.json()["main"]["spent_minor"] == 1250
    assert response.json()["main"]["remaining_minor"] == 8750


@pytest.mark.asyncio
async def test_category_budget_is_user_owned_and_reuses_summary(session, client, switch_user):
    category = Category(
        user_id=TEST_USER_ID,
        name="Casa",
        normalized_name="casa",
        icon_identifier="sf:house.fill",
        color="#FFFFFF",
    )
    session.add(category)
    await session.commit()

    response = await client.put(
        f"/v1/budget/categories/{category.id}",
        json={"amount_minor": 25000, "currency_code": "EUR", "currency_exponent": 2, "period_type": "week"},
    )
    assert response.status_code == 200
    assert response.json()["categories"][0]["category_id"] == str(category.id)

    switch_user()
    assert (await client.get("/v1/budget")).json() == {"main": None, "categories": []}


@pytest.mark.asyncio
async def test_deleted_category_budget_remains_safe(session, client):
    category = Category(
        user_id=TEST_USER_ID,
        name="Storico",
        normalized_name="storico",
        icon_identifier="sf:tag.fill",
        color="#FFFFFF",
    )
    session.add(category)
    await session.commit()
    response = await client.put(
        f"/v1/budget/categories/{category.id}",
        json={"amount_minor": 1000, "currency_code": "EUR", "currency_exponent": 2, "period_type": "day"},
    )
    assert response.status_code == 200
    category.deleted_at = datetime.now(UTC)
    await session.commit()
    response = await client.get("/v1/budget")
    assert response.status_code == 200
    assert response.json()["categories"][0]["category_deleted"] is True
