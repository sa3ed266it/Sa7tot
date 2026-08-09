from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, date, datetime
from uuid import UUID, uuid5

from sqlalchemy import delete, or_

from app.core.config import get_settings
from app.core.database import engine, session_factory
from app.models.entities import Account, Category, Profile, Subscription, SubscriptionOccurrence, Transaction

SEED_NAMESPACE = UUID("4e7c8f5f-d095-4be2-a832-2c95f7c9ce1c")


def seed_id(user_id: UUID, kind: str, name: str) -> UUID:
    return uuid5(SEED_NAMESPACE, f"{user_id}:{kind}:{name}")


async def seed_user(user_id: UUID, reset: bool) -> None:
    today = date.today()
    now = datetime.now(UTC)
    main_account_id = seed_id(user_id, "account", "main")
    savings_account_id = seed_id(user_id, "account", "savings")
    groceries_id = seed_id(user_id, "category", "groceries")
    salary_id = seed_id(user_id, "category", "salary")
    subscription_id = seed_id(user_id, "subscription", "netflix")
    income_id = seed_id(user_id, "transaction", "income")
    expense_id = seed_id(user_id, "transaction", "expense")
    transfer_id = seed_id(user_id, "transaction", "transfer")

    async with session_factory() as session:
        if reset:
            await session.execute(
                delete(SubscriptionOccurrence).where(
                    SubscriptionOccurrence.user_id == user_id,
                    SubscriptionOccurrence.subscription_id == subscription_id,
                )
            )
            await session.execute(
                delete(Transaction).where(
                    Transaction.user_id == user_id,
                    or_(
                        Transaction.id.in_((income_id, expense_id, transfer_id)),
                        Transaction.subscription_id == subscription_id,
                    ),
                )
            )
            await session.execute(
                delete(Subscription).where(Subscription.user_id == user_id, Subscription.id == subscription_id)
            )
            await session.execute(
                delete(Category).where(
                    Category.user_id == user_id,
                    Category.id.in_((groceries_id, salary_id)),
                )
            )
            await session.execute(
                delete(Account).where(
                    Account.user_id == user_id,
                    Account.id.in_((main_account_id, savings_account_id)),
                )
            )
            await session.flush()

        profile = await session.get(Profile, user_id)
        if profile is None:
            session.add(Profile(user_id=user_id, locale="it-IT", timezone="Europe/Rome", default_currency_code="EUR"))
        else:
            profile.locale = "it-IT"
            profile.timezone = "Europe/Rome"
            profile.default_currency_code = "EUR"

        main_account = await _owned_or_missing(session, Account, main_account_id, user_id)
        if main_account is None:
            main_account = Account(
                id=main_account_id,
                user_id=user_id,
                name="Conto principale",
                type="bank",
                currency_code="EUR",
                currency_exponent=2,
                opening_balance_minor=100_000,
                icon_name="building.columns.fill",
                color="#5E7CE2",
                sort_order=0,
            )
            session.add(main_account)

        savings_account = await _owned_or_missing(session, Account, savings_account_id, user_id)
        if savings_account is None:
            savings_account = Account(
                id=savings_account_id,
                user_id=user_id,
                name="Risparmi",
                type="bank",
                currency_code="EUR",
                currency_exponent=2,
                opening_balance_minor=0,
                icon_name="banknote.fill",
                color="#35A77A",
                sort_order=1,
            )
            session.add(savings_account)

        groceries = await _owned_or_missing(session, Category, groceries_id, user_id)
        if groceries is None:
            session.add(
                Category(
                    id=groceries_id,
                    user_id=user_id,
                    name="Spesa",
                    normalized_name="spesa",
                    income=False,
                    icon_identifier="sf:cart.fill",
                    color="#E05A47",
                    sort_order=0,
                )
            )

        salary = await _owned_or_missing(session, Category, salary_id, user_id)
        if salary is None:
            session.add(
                Category(
                    id=salary_id,
                    user_id=user_id,
                    name="Stipendio",
                    normalized_name="stipendio",
                    income=True,
                    icon_identifier="sf:arrow.down.circle.fill",
                    color="#35A77A",
                    sort_order=0,
                )
            )

        subscription = await _owned_or_missing(session, Subscription, subscription_id, user_id)
        if subscription is None:
            session.add(
                Subscription(
                    id=subscription_id,
                    user_id=user_id,
                    account_id=main_account_id,
                    service_id="netflix",
                    amount_minor=1_599,
                    currency_code="EUR",
                    currency_exponent=2,
                    cadence="monthly",
                    cadence_interval=1,
                    billing_anchor=today,
                    next_billing_date=today,
                    status="active",
                )
            )

        await session.flush()
        await _ensure_transaction(
            session,
            income_id,
            user_id,
            kind="income",
            account_id=main_account_id,
            amount_minor=250_000,
            occurred_at=now,
            category_id=salary_id,
            note="Stipendio",
        )
        await _ensure_transaction(
            session,
            expense_id,
            user_id,
            kind="expense",
            account_id=main_account_id,
            amount_minor=4_250,
            occurred_at=now,
            category_id=groceries_id,
            note="Spesa",
        )
        await _ensure_transaction(
            session,
            transfer_id,
            user_id,
            kind="transfer",
            account_id=main_account_id,
            destination_account_id=savings_account_id,
            amount_minor=10_000,
            occurred_at=now,
            note="Risparmio",
        )
        await session.commit()


async def _owned_or_missing(session, model, record_id: UUID, user_id: UUID):
    record = await session.get(model, record_id)
    if record is not None and record.user_id != user_id:
        raise RuntimeError(f"seed record ID collision for {model.__tablename__}")
    return record


async def _ensure_transaction(
    session,
    transaction_id: UUID,
    user_id: UUID,
    *,
    kind: str,
    account_id: UUID,
    amount_minor: int,
    occurred_at: datetime,
    category_id: UUID | None = None,
    destination_account_id: UUID | None = None,
    note: str | None = None,
) -> None:
    transaction = await _owned_or_missing(session, Transaction, transaction_id, user_id)
    if transaction is None:
        session.add(
            Transaction(
                id=transaction_id,
                user_id=user_id,
                kind=kind,
                account_id=account_id,
                destination_account_id=destination_account_id,
                amount_minor=amount_minor,
                currency_code="EUR",
                currency_exponent=2,
                occurred_at=occurred_at,
                local_day=occurred_at.date(),
                category_id=category_id,
                note=note,
                origin="seed_dev",
                review_status="confirmed",
            )
        )
    else:
        transaction.kind = kind
        transaction.account_id = account_id
        transaction.destination_account_id = destination_account_id
        transaction.amount_minor = amount_minor
        transaction.currency_code = "EUR"
        transaction.currency_exponent = 2
        transaction.occurred_at = occurred_at
        transaction.local_day = occurred_at.date()
        transaction.category_id = category_id
        transaction.note = note
        transaction.origin = "seed_dev"
        transaction.review_status = "confirmed"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Seed deterministic development data for one explicit user UUID.")
    parser.add_argument("--user-id", required=True, type=UUID, help="UUID that owns every seeded record")
    parser.add_argument("--reset", action="store_true", help="Remove this script's deterministic records first")
    parser.add_argument(
        "--allow-development-reset",
        action="store_true",
        help="Explicitly permit --reset against the development database",
    )
    parser.add_argument(
        "--force-production",
        action="store_true",
        help="Explicitly permit seeding when APP_ENV=production",
    )
    args = parser.parse_args()
    settings = get_settings()
    if settings.is_production and not args.force_production:
        parser.error("refusing to seed APP_ENV=production without --force-production")
    if args.reset:
        if settings.is_production:
            parser.error("refusing --reset against APP_ENV=production")
        if settings.app_env.lower() == "development" and not args.allow_development_reset:
            parser.error("refusing --reset in development without --allow-development-reset")
        if settings.app_env.lower() not in {"test", "development"}:
            parser.error("refusing --reset outside APP_ENV=test or APP_ENV=development")
    return args


def main() -> None:
    args = parse_args()
    asyncio.run(_run(args.user_id, args.reset))
    print("seed: ok")


async def _run(user_id: UUID, reset: bool) -> None:
    try:
        await seed_user(user_id, reset)
    finally:
        await engine.dispose()


if __name__ == "__main__":
    main()
