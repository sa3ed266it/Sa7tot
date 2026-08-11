from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

import pytest
from httpx import AsyncClient

from app.models.entities import Transaction


async def create_account(client: AsyncClient, name: str, opening_balance_minor: int = 0):
    response = await client.post(
        "/v1/accounts",
        json={
            "name": name,
            "type": "bank",
            "currency_code": "EUR",
            "currency_exponent": 2,
            "opening_balance_minor": opening_balance_minor,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.mark.asyncio
async def test_health_and_auth_boundary(client: AsyncClient):
    assert (await client.get("/health")).json() == {"status": "ok"}
    assert (await client.get("/v1/accounts")).status_code == 200


@pytest.mark.asyncio
async def test_account_ownership_and_archive(client: AsyncClient, switch_user):
    account = await create_account(client, "Conto A", 10000)
    assert (await client.get("/v1/accounts")).json()[0]["id"] == account["id"]

    switch_user()
    response = await client.patch(f"/v1/accounts/{account['id']}", json={"name": "Aggiornato"})
    assert response.status_code == 404

    response = await client.post(f"/v1/accounts/{account['id']}/archive")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_account_archive_is_persisted_for_owner(client: AsyncClient):
    account = await create_account(client, "Da archiviare")
    response = await client.post(f"/v1/accounts/{account['id']}/archive")
    assert response.status_code == 200, response.text
    assert response.json()["is_archived"] is True


@pytest.mark.asyncio
async def test_categories_are_unique_and_soft_deleted(client: AsyncClient):
    first = await client.post("/v1/categories", json={"name": " Cibo ", "income": False})
    assert first.status_code == 201, first.text
    duplicate = await client.post("/v1/categories", json={"name": "cibo", "income": False})
    assert duplicate.status_code == 409

    deleted = await client.delete(f"/v1/categories/{first.json()['id']}")
    assert deleted.status_code == 200
    assert deleted.json()["deleted_at"] is not None
    replacement = await client.post("/v1/categories", json={"name": "Cibo", "income": False})
    assert replacement.status_code == 201


@pytest.mark.asyncio
async def test_category_preset_activation_is_idempotent_and_reactivates_same_uuid(client: AsyncClient):
    first = await client.post(
        "/v1/categories/presets/activate",
        json={"preset_key": "expense.food", "income": False, "display_name": "Cibo"},
    )
    assert first.status_code == 200, first.text
    category = first.json()
    assert category["preset_key"] == "expense.food"
    assert category["income"] is False

    repeated = await client.post(
        "/v1/categories/presets/activate",
        json={"preset_key": "expense.food", "income": False, "display_name": "Cibo"},
    )
    assert repeated.status_code == 200
    assert repeated.json()["id"] == category["id"]

    deleted = await client.delete(f"/v1/categories/{category['id']}")
    assert deleted.status_code == 200
    assert deleted.json()["preset_key"] == "expense.food"

    restored = await client.post(
        "/v1/categories/presets/activate",
        json={"preset_key": "expense.food", "income": False, "display_name": "Cibo"},
    )
    assert restored.status_code == 200, restored.text
    assert restored.json()["id"] == category["id"]
    assert restored.json()["deleted_at"] is None


@pytest.mark.asyncio
async def test_category_preset_validation_and_custom_name_conflict(client: AsyncClient):
    unknown = await client.post("/v1/categories/presets/activate", json={"preset_key": "expense.subscriptions"})
    assert unknown.status_code == 422
    assert unknown.json()["error"]["code"] == "unknown_category_preset"

    mismatch = await client.post(
        "/v1/categories/presets/activate",
        json={"preset_key": "expense.food", "income": True},
    )
    assert mismatch.status_code == 422
    assert mismatch.json()["error"]["code"] == "preset_type_mismatch"

    custom = await client.post("/v1/categories", json={"name": "Cibo", "income": False})
    assert custom.status_code == 201
    assert custom.json()["preset_key"] is None

    conflict = await client.post(
        "/v1/categories/presets/activate",
        json={"preset_key": "expense.food", "income": False, "display_name": "Cibo"},
    )
    assert conflict.status_code == 409


@pytest.mark.asyncio
async def test_category_preset_is_user_scoped(client: AsyncClient, switch_user):
    first = await client.post("/v1/categories/presets/activate", json={"preset_key": "income.paycheck"})
    assert first.status_code == 200

    switch_user()
    second = await client.post("/v1/categories/presets/activate", json={"preset_key": "income.paycheck"})
    assert second.status_code == 200
    assert second.json()["id"] != first.json()["id"]


@pytest.mark.asyncio
async def test_removed_preset_category_remains_available_to_historical_transactions(client: AsyncClient):
    account = await create_account(client, "Principale")
    category = await client.post("/v1/categories/presets/activate", json={"preset_key": "expense.food"})
    assert category.status_code == 200
    transaction = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": account["id"],
            "category_id": category.json()["id"],
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert transaction.status_code == 201
    assert (await client.delete(f"/v1/categories/{category.json()['id']}")).status_code == 200
    historical = await client.get(f"/v1/transactions/{transaction.json()['id']}")
    assert historical.status_code == 200
    assert historical.json()["category"]["preset_key"] == "expense.food"


@pytest.mark.asyncio
async def test_category_soft_delete_preserves_historical_transaction(client: AsyncClient):
    account = await create_account(client, "Principale")
    category = await client.post("/v1/categories", json={"name": "Storico", "income": False})
    assert category.status_code == 201
    transaction = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": account["id"],
            "category_id": category.json()["id"],
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert transaction.status_code == 201
    deleted = await client.delete(f"/v1/categories/{category.json()['id']}")
    assert deleted.status_code == 200
    historical = await client.get(f"/v1/transactions/{transaction.json()['id']}")
    assert historical.status_code == 200
    assert historical.json()["id"] == transaction.json()["id"]


@pytest.mark.asyncio
async def test_transaction_update_delete_and_ownership(client: AsyncClient, switch_user):
    account = await create_account(client, "Principale")
    transaction = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": account["id"],
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": datetime.now(UTC).isoformat(),
            "note": "Prima",
        },
    )
    assert transaction.status_code == 201
    updated = await client.patch(
        f"/v1/transactions/{transaction.json()['id']}",
        json={"note": "Dopo"},
    )
    assert updated.status_code == 200
    assert updated.json()["note"] == "Dopo"

    switch_user()
    assert (await client.get(f"/v1/transactions/{transaction.json()['id']}")).status_code == 404
    assert (await client.delete(f"/v1/transactions/{transaction.json()['id']}")).status_code == 404


@pytest.mark.asyncio
async def test_transfer_and_movimenti_account_relative_signs(client: AsyncClient):
    source = await create_account(client, "Principale", 1000)
    destination = await create_account(client, "Risparmi")
    category = await client.post("/v1/categories", json={"name": "Stipendio", "income": True})
    assert category.status_code == 201
    occurred_at = datetime(2026, 8, 8, 10, 0, tzinfo=UTC).isoformat()

    income = await client.post(
        "/v1/transactions",
        json={
            "kind": "income",
            "account_id": source["id"],
            "amount_minor": 10000,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": occurred_at,
            "category_id": category.json()["id"],
            "note": "Stipendio",
        },
    )
    assert income.status_code == 201, income.text

    expense = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": source["id"],
            "amount_minor": 2898,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": occurred_at,
            "note": "Spesa",
        },
    )
    assert expense.status_code == 201, expense.text

    transfer = await client.post(
        "/v1/transfers",
        json={
            "source_account_id": source["id"],
            "destination_account_id": destination["id"],
            "amount_minor": 500,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": occurred_at,
            "note": "Risparmio",
        },
    )
    assert transfer.status_code == 201, transfer.text
    assert transfer.json()["effective_amount_minor"] is None
    assert transfer.json()["transfer"]["source_account_name"] == "Principale"

    movements = await client.get(f"/v1/accounts/{source['id']}/movements", params={"limit": 10})
    assert movements.status_code == 200, movements.text
    payload = movements.json()
    assert payload["account"]["balance_minor"] == 7602
    assert payload["summary"] == {"income_minor": 10000, "expenses_minor": 2898}
    transfer_row = next(row for day in payload["days"] for row in day["movements"] if row["kind"] == "transfer")
    assert transfer_row["effective_amount_minor"] == -500

    first_page = await client.get(f"/v1/accounts/{source['id']}/movements", params={"limit": 2})
    assert first_page.status_code == 200
    assert first_page.json()["next_cursor"]
    assert first_page.json()["days"][0]["subtotal_minor"] == 6602
    income_only = await client.get(
        f"/v1/accounts/{source['id']}/movements",
        params={"filter": "type", "income": "true"},
    )
    assert income_only.status_code == 200
    assert [row["kind"] for day in income_only.json()["days"] for row in day["movements"]] == ["income"]
    assert income_only.json()["days"][0]["subtotal_minor"] == 10000
    second_page = await client.get(
        f"/v1/accounts/{source['id']}/movements",
        params={"limit": 2, "cursor": first_page.json()["next_cursor"]},
    )
    assert second_page.status_code == 200
    first_ids = {row["id"] for day in first_page.json()["days"] for row in day["movements"]}
    second_ids = {row["id"] for day in second_page.json()["days"] for row in day["movements"]}
    assert first_ids.isdisjoint(second_ids)

    destination_movements = await client.get(f"/v1/accounts/{destination['id']}/movements")
    destination_row = next(
        row for day in destination_movements.json()["days"] for row in day["movements"] if row["kind"] == "transfer"
    )
    assert destination_movements.json()["account"]["balance_minor"] == 500
    assert destination_row["effective_amount_minor"] == 500


@pytest.mark.asyncio
async def test_subscription_movements_filter_uses_subscription_identity_and_account_scope(
    client: AsyncClient, session
):
    account = await create_account(client, "Principale")
    other_account = await create_account(client, "Altro")
    category = await client.post("/v1/categories", json={"name": "Servizi", "income": False})
    assert category.status_code == 201, category.text

    today = datetime.now(UTC).date().isoformat()
    subscription = await client.post(
        "/v1/subscriptions",
        json={
            "account_id": account["id"],
            "category_id": category.json()["id"],
            "service_id": "streaming-service",
            "amount_minor": 999,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "cadence": "monthly",
            "billing_anchor": today,
            "next_billing_date": today,
        },
    )
    assert subscription.status_code == 201, subscription.text
    subscription_id = subscription.json()["id"]
    materialized = await client.post("/v1/subscriptions/materialize")
    assert materialized.status_code == 200, materialized.text
    assert materialized.json()["generated_count"] == 1

    ordinary = await client.post(
        "/v1/transactions",
        json={
            "kind": "expense",
            "account_id": account["id"],
            "amount_minor": 100,
            "currency_code": "EUR",
            "currency_exponent": 2,
            "occurred_at": datetime.now(UTC).isoformat(),
        },
    )
    assert ordinary.status_code == 201, ordinary.text

    wrong_account = Transaction(
        user_id=UUID(subscription.json()["user_id"]),
        kind="expense",
        account_id=UUID(other_account["id"]),
        amount_minor=500,
        currency_code="EUR",
        currency_exponent=2,
        occurred_at=datetime.now(UTC),
        local_day=datetime.now(UTC).date(),
        origin="subscription",
        subscription_id=UUID(subscription_id),
        subscription_service_id="streaming-service",
    )
    session.add(wrong_account)
    await session.commit()

    filtered = await client.get(f"/v1/accounts/{account['id']}/movements", params={"filter": "subscription"})
    assert filtered.status_code == 200, filtered.text
    rows = [row for day in filtered.json()["days"] for row in day["movements"]]
    assert len(rows) == 1
    assert rows[0]["subscription"]["id"] == subscription_id
    assert rows[0]["category"]["id"] == category.json()["id"]

    category_filtered = await client.get(
        f"/v1/accounts/{account['id']}/movements",
        params={"filter": "category", "category_id": category.json()["id"]},
    )
    assert category_filtered.status_code == 200
    category_rows = [row for day in category_filtered.json()["days"] for row in day["movements"]]
    assert [row["id"] for row in category_rows] == [rows[0]["id"]]


@pytest.mark.asyncio
async def test_transfer_validation(client: AsyncClient):
    euro = await create_account(client, "Euro")
    yen_response = await client.post(
        "/v1/accounts",
        json={"name": "Yen", "type": "bank", "currency_code": "JPY", "currency_exponent": 0},
    )
    assert yen_response.status_code == 201
    payload = {
        "source_account_id": euro["id"],
        "destination_account_id": euro["id"],
        "amount_minor": 1,
        "currency_code": "EUR",
        "currency_exponent": 2,
        "occurred_at": datetime.now(UTC).isoformat(),
    }
    assert (await client.post("/v1/transfers", json=payload)).status_code == 422
    payload["destination_account_id"] = yen_response.json()["id"]
    assert (await client.post("/v1/transfers", json=payload)).status_code == 422


@pytest.mark.asyncio
async def test_credit_card_balance_preserves_existing_sign_semantics(client: AsyncClient):
    account_response = await client.post(
        "/v1/accounts",
        json={
            "name": "Carta",
            "type": "creditCard",
            "currency_code": "EUR",
            "currency_exponent": 2,
        },
    )
    assert account_response.status_code == 201
    account = account_response.json()
    occurred_at = datetime(2026, 8, 8, 10, 0, tzinfo=UTC).isoformat()
    for kind, amount in (("income", 10000), ("expense", 2000)):
        response = await client.post(
            "/v1/transactions",
            json={
                "kind": kind,
                "account_id": account["id"],
                "amount_minor": amount,
                "currency_code": "EUR",
                "currency_exponent": 2,
                "occurred_at": occurred_at,
            },
        )
        assert response.status_code == 201, response.text
    movements = await client.get(f"/v1/accounts/{account['id']}/movements")
    assert movements.json()["account"]["balance_minor"] == -8000
