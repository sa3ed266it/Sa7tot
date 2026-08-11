from __future__ import annotations

from datetime import UTC, datetime

import pytest
from conftest import test_engine
from httpx import AsyncClient
from sqlalchemy import event


async def _create_account(client: AsyncClient) -> dict:
    response = await client.post(
        "/v1/accounts",
        json={
            "name": "Performance account",
            "type": "bank",
            "currency_code": "EUR",
            "currency_exponent": 2,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.mark.asyncio
async def test_movimenti_page_uses_bounded_queries_and_full_day_aggregate(client: AsyncClient):
    account = await _create_account(client)
    category_ids = []
    for index in range(55):
        category_response = await client.post(
            "/v1/categories",
            json={"name": f"Performance {index}", "income": False},
        )
        assert category_response.status_code == 201, category_response.text
        category_ids.append(category_response.json()["id"])
    occurred_at = datetime.now(UTC).replace(microsecond=0).isoformat()

    for index in range(55):
        response = await client.post(
            "/v1/transactions",
            json={
                "kind": "expense",
                "account_id": account["id"],
                "category_id": category_ids[index],
                "amount_minor": index + 1,
                "currency_code": "EUR",
                "currency_exponent": 2,
                "occurred_at": occurred_at,
            },
        )
        assert response.status_code == 201, response.text

    statements: list[str] = []

    def count_selects(_, __, statement, *___):
        if statement.lstrip().upper().startswith("SELECT"):
            statements.append(statement)

    event.listen(test_engine.sync_engine, "before_cursor_execute", count_selects)
    try:
        response = await client.get(f"/v1/accounts/{account['id']}/movements", params={"limit": 50})
    finally:
        event.remove(test_engine.sync_engine, "before_cursor_execute", count_selects)

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["next_cursor"] is not None
    assert len([row for group in payload["days"] for row in group["movements"]]) == 50
    assert payload["days"][0]["subtotal_minor"] == -sum(range(1, 56))
    assert payload["account"]["balance_minor"] == -sum(range(1, 56))
    assert payload["summary"] == {"income_minor": 0, "expenses_minor": sum(range(1, 56))}
    assert len(statements) <= 7
