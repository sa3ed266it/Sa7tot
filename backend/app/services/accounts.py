from __future__ import annotations

from uuid import UUID

from sqlalchemy import exists, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Account, Transaction
from app.schemas.accounts import AccountCreate, AccountUpdate
from app.services.common import normalize_currency


async def get_account(session: AsyncSession, user_id: UUID, account_id: UUID) -> Account:
    account = await session.scalar(select(Account).where(Account.id == account_id, Account.user_id == user_id))
    if account is None:
        raise DomainError(404, "account not found", "account_not_found")
    return account


async def list_accounts(session: AsyncSession, user_id: UUID, active_only: bool = False) -> list[Account]:
    query = select(Account).where(Account.user_id == user_id)
    if active_only:
        query = query.where(Account.is_archived.is_(False))
    query = query.order_by(Account.sort_order.asc(), Account.created_at.asc(), Account.id.asc())
    return list((await session.scalars(query)).all())


async def create_account(session: AsyncSession, user_id: UUID, payload: AccountCreate) -> Account:
    account = Account(
        user_id=user_id,
        name=payload.name,
        type=payload.type,
        currency_code=normalize_currency(payload.currency_code),
        currency_exponent=payload.currency_exponent,
        opening_balance_minor=payload.opening_balance_minor,
        icon_name=payload.icon_name,
        color=payload.color,
        wallet_label=payload.wallet_label,
        is_archived=payload.is_archived,
        sort_order=payload.sort_order,
    )
    session.add(account)
    await session.commit()
    await session.refresh(account)
    return account


async def update_account(session: AsyncSession, user_id: UUID, account_id: UUID, payload: AccountUpdate) -> Account:
    account = await get_account(session, user_id, account_id)
    values = payload.model_dump(exclude_unset=True)
    if "currency_code" in values:
        values["currency_code"] = normalize_currency(values["currency_code"])
        if values["currency_code"] != account.currency_code:
            has_transactions = await session.scalar(select(exists().where(Transaction.account_id == account.id)))
            if has_transactions:
                raise DomainError(
                    409,
                    "account currency cannot change after transactions exist",
                    "account_currency_locked",
                )
    for key, value in values.items():
        if value is not None:
            setattr(account, key, value)
    await session.commit()
    await session.refresh(account)
    return account


async def archive_account(session: AsyncSession, user_id: UUID, account_id: UUID) -> Account:
    account = await get_account(session, user_id, account_id)
    account.is_archived = True
    await session.commit()
    await session.refresh(account)
    return account
