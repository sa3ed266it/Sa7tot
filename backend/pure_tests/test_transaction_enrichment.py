from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import UUID, uuid4

import pytest

from app.models.entities import Account, Category, RecurrenceOccurrence, Subscription, Transaction
from app.services.transactions import transactions_out

USER_ID = UUID("11111111-1111-1111-1111-111111111111")
NOW = datetime(2026, 8, 11, 12, 0, tzinfo=UTC)


class _ScalarResult:
    def __init__(self, values):
        self.values = values

    def all(self):
        return self.values


class _BulkSession:
    def __init__(self, values_by_entity):
        self.values_by_entity = values_by_entity
        self.entities = []

    async def scalars(self, statement):
        entity = statement.column_descriptions[0]["entity"]
        self.entities.append(entity)
        return _ScalarResult(self.values_by_entity.get(entity, []))


def _transaction(**values) -> Transaction:
    return Transaction(
        id=values.pop("id", uuid4()),
        user_id=USER_ID,
        kind=values.pop("kind", "expense"),
        account_id=values.pop("account_id"),
        amount_minor=values.pop("amount_minor", 1250),
        currency_code="EUR",
        currency_exponent=2,
        occurred_at=NOW,
        local_day=date(2026, 8, 11),
        created_at=NOW,
        updated_at=NOW,
        **values,
    )


@pytest.mark.asyncio
async def test_transaction_page_relations_are_loaded_in_bounded_batches():
    main = Account(
        id=UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
        user_id=USER_ID,
        name="Main",
        type="bank",
        currency_code="EUR",
        currency_exponent=2,
        opening_balance_minor=0,
    )
    other = Account(
        id=UUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
        user_id=USER_ID,
        name="Savings",
        type="bank",
        currency_code="EUR",
        currency_exponent=2,
        opening_balance_minor=0,
    )
    category = Category(
        id=UUID("cccccccc-cccc-cccc-cccc-cccccccccccc"),
        user_id=USER_ID,
        name="Food",
        normalized_name="food",
        income=False,
        icon_identifier="sf:fork.knife",
        color="#FFFFFF",
    )
    subscription = Subscription(
        id=UUID("dddddddd-dddd-dddd-dddd-dddddddddddd"),
        user_id=USER_ID,
        account_id=main.id,
        amount_minor=1000,
        currency_code="EUR",
        currency_exponent=2,
        cadence="monthly",
        cadence_interval=1,
        billing_anchor=date(2026, 8, 1),
        next_billing_date=date(2026, 9, 1),
        status="active",
        service_id="service",
    )
    occurrence = RecurrenceOccurrence(
        id=UUID("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"),
        user_id=USER_ID,
        rule_id=UUID("ffffffff-ffff-ffff-ffff-ffffffffffff"),
        scheduled_date=date(2026, 8, 11),
        transaction_id=UUID("11111111-2222-3333-4444-555555555555"),
    )
    expense = _transaction(
        id=occurrence.transaction_id,
        account_id=main.id,
        category_id=category.id,
        subscription_id=subscription.id,
        recurrence_rule_id=occurrence.rule_id,
    )
    transfer = _transaction(
        kind="transfer",
        account_id=main.id,
        destination_account_id=other.id,
        amount_minor=5000,
    )
    session = _BulkSession(
        {
            Account: [other],
            Category: [category],
            Subscription: [subscription],
            RecurrenceOccurrence: [occurrence],
        }
    )

    outputs = await transactions_out(session, [expense, transfer], main, USER_ID)

    assert len(session.entities) == 4
    assert outputs[0].category is not None
    assert outputs[0].subscription is not None
    assert outputs[0].recurrence is not None
    assert outputs[1].transfer is not None
    assert outputs[1].transfer.source_account_name == "Main"
    assert outputs[1].transfer.destination_account_name == "Savings"
