from __future__ import annotations

from collections.abc import Iterable

from app.models.entities import Account, Transaction


def is_credit_account(account: Account) -> bool:
    return account.type == "creditCard"


def transaction_belongs(transaction: Transaction, account_id) -> bool:
    return transaction.account_id == account_id or transaction.destination_account_id == account_id


def effective_amount_minor(transaction: Transaction, account: Account) -> int:
    if not transaction_belongs(transaction, account.id):
        return 0

    if transaction.kind == "income":
        amount = transaction.amount_minor
    elif transaction.kind == "expense":
        amount = -transaction.amount_minor
    elif transaction.account_id == account.id:
        amount = -transaction.amount_minor
    else:
        amount = transaction.amount_minor

    return -amount if is_credit_account(account) else amount


def account_balance(account: Account, transactions: Iterable[Transaction]) -> int:
    return account.opening_balance_minor + sum(
        effective_amount_minor(transaction, account) for transaction in transactions
    )
