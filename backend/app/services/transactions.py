from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Account, Category, RecurrenceOccurrence, Subscription, Transaction
from app.schemas.common import CategoryBrief, RecurrenceBrief, SubscriptionBrief, TransactionKind, TransferBrief
from app.schemas.transactions import TransactionCreate, TransactionUpdate, TransferCreate
from app.services.common import (
    display_subscription_name,
    ensure_utc,
    get_or_create_profile,
    local_day_for,
    normalize_currency,
)
from app.services.financial import effective_amount_minor


async def get_transaction(session: AsyncSession, user_id: UUID, transaction_id: UUID) -> Transaction:
    transaction = await session.scalar(
        select(Transaction).where(Transaction.id == transaction_id, Transaction.user_id == user_id)
    )
    if transaction is None:
        raise DomainError(404, "transaction not found", "transaction_not_found")
    return transaction


async def create_transaction(session: AsyncSession, user_id: UUID, payload: TransactionCreate) -> Transaction:
    if payload.kind == TransactionKind.transfer:
        raise DomainError(422, "use the transfer endpoint for transfers", "transfer_endpoint_required")
    account = await _active_account(session, user_id, payload.account_id)
    _ensure_currency(payload.currency_code, account.currency_code)
    category = await _optional_category(session, user_id, payload.category_id)
    profile = await get_or_create_profile(session, user_id)
    occurred_at = ensure_utc(payload.occurred_at)

    transaction = Transaction(
        user_id=user_id,
        kind=payload.kind.value,
        account_id=account.id,
        amount_minor=payload.amount_minor,
        currency_code=normalize_currency(payload.currency_code),
        currency_exponent=payload.currency_exponent,
        occurred_at=occurred_at,
        local_day=local_day_for(occurred_at, profile.timezone),
        category_id=category.id if category else None,
        note=payload.note,
        merchant=payload.merchant,
        normalized_merchant=payload.normalized_merchant,
        origin=payload.origin,
        review_status=payload.review_status,
        external_reference=payload.external_reference,
        subscription_id=payload.subscription_id,
        subscription_service_id=payload.subscription_service_id,
        subscription_occurrence_key=payload.subscription_occurrence_key,
        subscription_display_name=payload.subscription_display_name,
    )
    await _validate_subscription_reference(session, user_id, transaction.subscription_id)
    session.add(transaction)
    await session.commit()
    await session.refresh(transaction)
    return transaction


async def update_transaction(
    session: AsyncSession, user_id: UUID, transaction_id: UUID, payload: TransactionUpdate
) -> Transaction:
    transaction = await get_transaction(session, user_id, transaction_id)
    if transaction.kind == TransactionKind.transfer.value:
        raise DomainError(409, "transfer updates are not part of V1", "transfer_update_not_supported")

    values = payload.model_dump(exclude_unset=True)
    kind = values.get("kind", transaction.kind)
    if kind == TransactionKind.transfer:
        raise DomainError(422, "use the transfer endpoint for transfers", "transfer_endpoint_required")

    account_id = values.get("account_id", transaction.account_id)
    account = await _active_account(session, user_id, account_id)
    currency_code = values.get("currency_code", transaction.currency_code)
    currency_exponent = values.get("currency_exponent", transaction.currency_exponent)
    _ensure_currency(currency_code, account.currency_code)
    category_id = values.get("category_id", transaction.category_id)
    category = await _optional_category(session, user_id, category_id)
    profile = await get_or_create_profile(session, user_id)
    occurred_at = ensure_utc(values.get("occurred_at", transaction.occurred_at))

    transaction.kind = kind.value if isinstance(kind, TransactionKind) else kind
    transaction.account_id = account.id
    transaction.amount_minor = values.get("amount_minor", transaction.amount_minor)
    transaction.currency_code = normalize_currency(currency_code)
    transaction.currency_exponent = currency_exponent
    transaction.occurred_at = occurred_at
    transaction.local_day = local_day_for(occurred_at, profile.timezone)
    transaction.category_id = category.id if category else None
    for key in (
        "note",
        "merchant",
        "normalized_merchant",
        "origin",
        "review_status",
        "external_reference",
    ):
        if key in values:
            setattr(transaction, key, values[key])
    await session.commit()
    await session.refresh(transaction)
    return transaction


async def delete_transaction(session: AsyncSession, user_id: UUID, transaction_id: UUID) -> None:
    transaction = await get_transaction(session, user_id, transaction_id)
    await session.delete(transaction)
    await session.commit()


async def create_transfer(session: AsyncSession, user_id: UUID, payload: TransferCreate) -> Transaction:
    if payload.source_account_id == payload.destination_account_id:
        raise DomainError(422, "source and destination accounts must differ", "same_transfer_account")
    source = await _active_account(session, user_id, payload.source_account_id, lock=True)
    destination = await _active_account(session, user_id, payload.destination_account_id, lock=True)
    if source.currency_code != destination.currency_code:
        raise DomainError(422, "transfers require matching currencies", "transfer_currency_mismatch")
    _ensure_currency(payload.currency_code, source.currency_code)
    occurred_at = ensure_utc(payload.occurred_at)
    profile = await get_or_create_profile(session, user_id)

    transaction = Transaction(
        user_id=user_id,
        kind=TransactionKind.transfer.value,
        account_id=source.id,
        destination_account_id=destination.id,
        amount_minor=payload.amount_minor,
        currency_code=source.currency_code,
        currency_exponent=payload.currency_exponent,
        occurred_at=occurred_at,
        local_day=local_day_for(occurred_at, profile.timezone),
        note=payload.note,
        origin="manual",
        review_status="confirmed",
    )
    session.add(transaction)
    await session.commit()
    await session.refresh(transaction)
    return transaction


async def transaction_out(session: AsyncSession, transaction: Transaction, perspective_account: Account | None = None):
    source = await session.get(Account, transaction.account_id)
    destination = (
        await session.get(Account, transaction.destination_account_id) if transaction.destination_account_id else None
    )
    category = await session.get(Category, transaction.category_id) if transaction.category_id else None
    subscription = await session.get(Subscription, transaction.subscription_id) if transaction.subscription_id else None
    recurrence_occurrence = None
    if transaction.recurrence_rule_id:
        recurrence_occurrence = await session.scalar(
            select(RecurrenceOccurrence).where(
                RecurrenceOccurrence.transaction_id == transaction.id,
                RecurrenceOccurrence.user_id == transaction.user_id,
            )
        )

    if transaction.kind == TransactionKind.transfer.value:
        title = "Trasferimento"
    elif transaction.subscription_id or transaction.subscription_service_id:
        title = display_subscription_name(
            transaction.subscription_service_id,
            None,
            transaction.subscription_display_name,
        )
    else:
        title = transaction.note or (category.name if category else transaction.kind.title())

    category_brief = (
        CategoryBrief(
            id=category.id,
            name=category.name,
            income=category.income,
            icon_identifier=category.icon_identifier,
            color=category.color,
            preset_key=category.preset_key,
        )
        if category
        else None
    )
    transfer_brief = (
        TransferBrief(
            source_account_id=source.id,
            source_account_name=source.name,
            destination_account_id=destination.id,
            destination_account_name=destination.name,
        )
        if source and destination
        else None
    )
    subscription_brief = (
        SubscriptionBrief(
            id=subscription.id if subscription else transaction.subscription_id,
            service_id=(subscription.service_id if subscription else transaction.subscription_service_id),
            display_name=display_subscription_name(
                subscription.service_id if subscription else transaction.subscription_service_id,
                subscription.custom_name if subscription else None,
                transaction.subscription_display_name,
            ),
        )
        if subscription or transaction.subscription_id or transaction.subscription_service_id
        else None
    )
    recurrence_brief = (
        RecurrenceBrief(
            rule_id=transaction.recurrence_rule_id,
            occurrence_id=recurrence_occurrence.id,
            scheduled_date=recurrence_occurrence.scheduled_date,
        )
        if transaction.recurrence_rule_id and recurrence_occurrence
        else None
    )
    effective = effective_amount_minor(transaction, perspective_account) if perspective_account is not None else None

    from app.schemas.transactions import TransactionOut

    return TransactionOut(
        id=transaction.id,
        user_id=transaction.user_id,
        kind=transaction.kind,
        account_id=transaction.account_id,
        destination_account_id=transaction.destination_account_id,
        amount_minor=transaction.amount_minor,
        currency_code=transaction.currency_code,
        currency_exponent=transaction.currency_exponent,
        occurred_at=transaction.occurred_at,
        local_day=transaction.local_day,
        title=title,
        effective_amount_minor=effective,
        category=category_brief,
        transfer=transfer_brief,
        subscription=subscription_brief,
        recurrence=recurrence_brief,
        note=transaction.note,
        merchant=transaction.merchant,
        origin=transaction.origin,
        review_status=transaction.review_status,
        external_reference=transaction.external_reference,
        created_at=transaction.created_at,
        updated_at=transaction.updated_at,
    )


async def _active_account(session: AsyncSession, user_id: UUID, account_id: UUID, lock: bool = False) -> Account:
    query = select(Account).where(
        Account.id == account_id,
        Account.user_id == user_id,
        Account.is_archived.is_(False),
    )
    if lock:
        query = query.with_for_update()
    account = await session.scalar(query)
    if account is None:
        raise DomainError(404, "active account not found", "account_not_found")
    return account


async def _optional_category(session: AsyncSession, user_id: UUID, category_id: UUID | None) -> Category | None:
    if category_id is None:
        return None
    category = await session.scalar(
        select(Category).where(
            Category.id == category_id,
            Category.user_id == user_id,
            Category.deleted_at.is_(None),
        )
    )
    if category is None:
        raise DomainError(404, "active category not found", "category_not_found")
    return category


async def _validate_subscription_reference(session: AsyncSession, user_id: UUID, subscription_id: UUID | None) -> None:
    if subscription_id is None:
        return
    subscription = await session.scalar(
        select(Subscription.id).where(Subscription.id == subscription_id, Subscription.user_id == user_id)
    )
    if subscription is None:
        raise DomainError(404, "subscription not found", "subscription_not_found")


def _ensure_currency(payload_currency: str, account_currency: str) -> None:
    if normalize_currency(payload_currency) != normalize_currency(account_currency):
        raise DomainError(422, "transaction currency must match the account currency", "currency_mismatch")
