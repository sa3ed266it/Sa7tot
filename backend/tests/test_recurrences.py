from __future__ import annotations

import asyncio
from datetime import UTC, date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entities import RecurrenceOccurrence, RecurrenceRule, Subscription, Transaction
from app.services.recurrences import materialize_due_recurrences
from app.services.scheduling import occurrence_at_index

TEST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
ROME = ZoneInfo("Europe/Rome")


async def create_account(client: AsyncClient, name: str = "Principale") -> dict:
    response = await client.post(
        "/v1/accounts",
        json={"name": name, "type": "bank", "currency_code": "EUR", "currency_exponent": 2},
    )
    assert response.status_code == 201, response.text
    return response.json()


def today() -> date:
    return datetime.now(UTC).astimezone(ROME).date()


@pytest.mark.asyncio
async def test_recurrence_create_catches_up_and_history_is_separate(client: AsyncClient, session: AsyncSession):
    account = await create_account(client)
    category = await client.post("/v1/categories", json={"name": "Cibo", "income": False})
    assert category.status_code == 201
    anchor = today() - timedelta(days=2)

    response = await client.post(
        "/v1/recurrences",
        json={
            "account_id": account["id"],
            "category_id": category.json()["id"],
            "kind": "expense",
            "amount_minor": 1250,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "title": "Spesa ricorrente",
            "cadence": "daily",
            "cadence_interval": 1,
            "anchor_date": anchor.isoformat(),
        },
    )
    assert response.status_code == 201, response.text
    rule = response.json()
    assert rule["status"] == "active"
    assert date.fromisoformat(rule["next_occurrence_date"]) == today() + timedelta(days=1)

    occurrences = list((await session.scalars(select(RecurrenceOccurrence))).all())
    transactions = list((await session.scalars(select(Transaction))).all())
    assert len(occurrences) == 3
    assert len(transactions) == 3
    assert {transaction.origin for transaction in transactions} == {"recurrence"}
    assert {transaction.local_day for transaction in transactions} == {
        anchor,
        anchor + timedelta(days=1),
        today(),
    }

    history = await client.get(f"/v1/accounts/{account['id']}/movements", params={"filter": "recurring"})
    assert history.status_code == 200, history.text
    rows = [row for day_group in history.json()["days"] for row in day_group["movements"]]
    assert len(rows) == 3
    assert all(row["origin"] == "recurrence" for row in rows)
    assert all(row["recurrence"]["rule_id"] == rule["id"] for row in rows)

    budget = await client.put(
        "/v1/budget/main",
        json={"amount_minor": 5000, "currency_code": "EUR", "currency_exponent": 2, "period_type": "month"},
    )
    assert budget.status_code == 200
    assert budget.json()["main"]["spent_minor"] == 3750

    ordinary = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": account["id"],
            "amount_minor": 500,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert ordinary.status_code == 201
    history_after_ordinary = await client.get(f"/v1/accounts/{account['id']}/movements", params={"filter": "recurring"})
    assert len([row for group in history_after_ordinary.json()["days"] for row in group["movements"]]) == 3


@pytest.mark.asyncio
async def test_recurrence_income_upcoming_and_budget_integration(client: AsyncClient):
    account = await create_account(client)
    income = await client.post(
        "/v1/recurrences",
        json={
            "account_id": account["id"],
            "kind": "income",
            "amount_minor": 10000,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "weekly",
            "anchor_date": today().isoformat(),
        },
    )
    assert income.status_code == 201, income.text

    future_transaction = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": account["id"],
            "amount_minor": 800,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": (datetime.now(UTC) + timedelta(days=2)).isoformat(),
            "note": "Futuro",
        },
    )
    assert future_transaction.status_code == 201

    upcoming = await client.get(f"/v1/accounts/{account['id']}/upcoming")
    assert upcoming.status_code == 200, upcoming.text
    assert [item["kind"] for item in upcoming.json()["items"]] == ["transaction", "recurrence"]
    assert upcoming.json()["items"][1]["transaction_kind"] == "income"

    budget = await client.put(
        "/v1/budget/main",
        json={"amount_minor": 5000, "currency_code": "EUR", "currency_exponent": 2, "period_type": "month"},
    )
    assert budget.status_code == 200
    assert budget.json()["main"]["spent_minor"] == 0


@pytest.mark.asyncio
async def test_recurrence_validation_and_ownership(client: AsyncClient, switch_user):
    account = await create_account(client)
    payload = {
        "account_id": account["id"],
        "kind": "expense",
        "amount_minor": 100,
        "currency_code": "USD",
        "currency_exponent": 2,
        "cadence": "daily",
        "anchor_date": today().isoformat(),
    }
    transfer_payload = {**payload, "kind": "transfer", "currency_code": "EUR"}
    assert (await client.post("/v1/recurrences", json=transfer_payload)).status_code == 422
    assert (await client.post("/v1/recurrences", json=payload)).status_code == 422

    payload["currency_code"] = "EUR"
    created = await client.post("/v1/recurrences", json=payload)
    assert created.status_code == 201
    rule_id = created.json()["id"]

    switch_user()
    assert (await client.get("/v1/recurrences")).json() == []
    assert (await client.get(f"/v1/recurrences/{rule_id}")).status_code == 404
    assert (await client.post(f"/v1/recurrences/{rule_id}/cancel")).status_code == 404


@pytest.mark.asyncio
async def test_recurrence_pause_resume_cancel_preserves_history(client: AsyncClient, session: AsyncSession):
    account = await create_account(client)
    response = await client.post(
        "/v1/recurrences",
        json={
            "account_id": account["id"],
            "kind": "expense",
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "daily",
            "anchor_date": today().isoformat(),
        },
    )
    assert response.status_code == 201
    rule_id = response.json()["id"]
    count_before = len((await session.scalars(select(Transaction).where(Transaction.origin == "recurrence"))).all())

    paused = await client.post(f"/v1/recurrences/{rule_id}/pause")
    assert paused.status_code == 200
    assert paused.json()["status"] == "paused"
    resumed = await client.post(f"/v1/recurrences/{rule_id}/resume")
    assert resumed.status_code == 200
    assert resumed.json()["status"] == "active"
    assert date.fromisoformat(resumed.json()["next_occurrence_date"]) > today()
    cancelled = await client.post(f"/v1/recurrences/{rule_id}/cancel")
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"
    count_after = len((await session.scalars(select(Transaction).where(Transaction.origin == "recurrence"))).all())
    assert count_after == count_before


@pytest.mark.asyncio
async def test_recurrence_update_changes_future_only(client: AsyncClient, session: AsyncSession):
    account = await create_account(client)
    response = await client.post(
        "/v1/recurrences",
        json={
            "account_id": account["id"],
            "kind": "expense",
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "daily",
            "anchor_date": (today() - timedelta(days=1)).isoformat(),
        },
    )
    assert response.status_code == 201
    rule_id = response.json()["id"]
    before = list((await session.scalars(select(Transaction).where(Transaction.origin == "recurrence"))).all())
    assert {transaction.amount_minor for transaction in before} == {100}

    updated = await client.patch(
        f"/v1/recurrences/{rule_id}",
        json={"amount_minor": 250, "title": "Nuovo importo", "anchor_date": (today() + timedelta(days=3)).isoformat()},
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["next_occurrence_date"] == (today() + timedelta(days=3)).isoformat()
    after = list((await session.scalars(select(Transaction).where(Transaction.origin == "recurrence"))).all())
    assert len(after) == len(before)
    assert {transaction.amount_minor for transaction in after} == {100}


@pytest.mark.asyncio
async def test_recurrence_materialization_is_idempotent_and_subscription_is_separate(
    client: AsyncClient, session: AsyncSession
):
    account = await create_account(client)
    response = await client.post(
        "/v1/recurrences",
        json={
            "account_id": account["id"],
            "kind": "expense",
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "weekly",
            "anchor_date": (today() - timedelta(days=14)).isoformat(),
        },
    )
    assert response.status_code == 201
    first = await materialize_due_recurrences(session, TEST_USER_ID)
    second = await materialize_due_recurrences(session, TEST_USER_ID)
    assert first.generated_count == 0
    assert second.generated_count == 0
    occurrence_count = len((await session.scalars(select(RecurrenceOccurrence))).all())
    assert occurrence_count == 3

    subscription = Subscription(
        user_id=TEST_USER_ID,
        account_id=UUID(account["id"]),
        service_id="netflix",
        amount_minor=999,
        currency_code="EUR",
        currency_exponent=2,
        cadence="monthly",
        cadence_interval=1,
        billing_anchor=today(),
        next_billing_date=today() + timedelta(days=30),
        status="active",
    )
    session.add(subscription)
    await session.commit()
    session.add(
        Transaction(
            user_id=TEST_USER_ID,
            kind="expense",
            account_id=UUID(account["id"]),
            amount_minor=999,
            currency_code="EUR",
            currency_exponent=2,
            occurred_at=datetime.now(UTC),
            local_day=today(),
            origin="subscription",
            subscription_id=subscription.id,
        )
    )
    await session.commit()
    history = await client.get(f"/v1/accounts/{account['id']}/movements", params={"filter": "recurring"})
    assert all(row["origin"] == "recurrence" for group in history.json()["days"] for row in group["movements"])
    upcoming = await client.get(f"/v1/accounts/{account['id']}/upcoming")
    assert all(item["kind"] != "subscription" for item in upcoming.json()["items"])


@pytest.mark.asyncio
async def test_archived_account_and_deleted_category_pause_future_materialization(
    client: AsyncClient, session: AsyncSession
):
    account = await create_account(client)
    category_account = await create_account(client, "Secondo")
    category_response = await client.post("/v1/categories", json={"name": "Bloccata", "income": False})
    category_id = category_response.json()["id"]
    account_rule = await client.post(
        "/v1/recurrences",
        json={
            "account_id": account["id"],
            "kind": "expense",
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "daily",
            "anchor_date": (today() + timedelta(days=1)).isoformat(),
        },
    )
    category_rule = await client.post(
        "/v1/recurrences",
        json={
            "account_id": category_account["id"],
            "category_id": category_id,
            "kind": "expense",
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "daily",
            "anchor_date": (today() + timedelta(days=1)).isoformat(),
        },
    )
    assert account_rule.status_code == category_rule.status_code == 201
    account_rule_model = await session.get(RecurrenceRule, UUID(account_rule.json()["id"]))
    category_rule_model = await session.get(RecurrenceRule, UUID(category_rule.json()["id"]))
    account_rule_model.next_occurrence_date = today()
    category_rule_model.next_occurrence_date = today()
    await session.commit()

    assert (await client.post(f"/v1/accounts/{account['id']}/archive")).status_code == 200
    assert (await client.delete(f"/v1/categories/{category_id}")).status_code == 200
    materialized = await client.post("/v1/recurrences/materialize")
    assert materialized.status_code == 200
    assert materialized.json()["generated_count"] == 0
    assert materialized.json()["skipped_archived_account_count"] == 1
    assert materialized.json()["skipped_invalid_category_count"] == 1
    session.expire_all()
    rules = list((await session.scalars(select(RecurrenceRule))).all())
    assert {rule.status for rule in rules} == {"paused"}


@pytest.mark.asyncio
async def test_recurrence_cadence_and_month_end_rules():
    assert occurrence_at_index(date(2024, 1, 31), "daily", 2, 1) == date(2024, 2, 2)
    assert occurrence_at_index(date(2024, 1, 31), "weekly", 2, 1) == date(2024, 2, 14)
    assert occurrence_at_index(date(2024, 1, 31), "monthly", 1, 1) == date(2024, 2, 29)
    assert occurrence_at_index(date(2023, 1, 31), "monthly", 1, 1) == date(2023, 2, 28)
    assert occurrence_at_index(date(2024, 8, 31), "monthly", 1, 1) == date(2024, 9, 30)
    assert occurrence_at_index(date(2024, 2, 29), "monthly", 12, 1) == date(2025, 2, 28)


@pytest.mark.asyncio
async def test_materialization_calls_can_be_started_concurrently(
    client: AsyncClient, session: AsyncSession, session_factory
):
    account = await create_account(client)
    rule = RecurrenceRule(
        user_id=TEST_USER_ID,
        account_id=UUID(account["id"]),
        kind="expense",
        amount_minor=100,
        currency_code="EUR",
        currency_exponent=2,
        cadence="daily",
        cadence_interval=1,
        anchor_date=today(),
        next_occurrence_date=today(),
        status="active",
    )
    session.add(rule)
    await session.commit()

    async with session_factory() as first_session, session_factory() as second_session:
        results = await asyncio.gather(
            materialize_due_recurrences(first_session, TEST_USER_ID),
            materialize_due_recurrences(second_session, TEST_USER_ID),
        )
    assert sorted(result.generated_count for result in results) == [0, 1]
    assert len((await session.scalars(select(RecurrenceOccurrence))).all()) == 1
    assert len((await session.scalars(select(Transaction).where(Transaction.origin == "recurrence"))).all()) == 1
