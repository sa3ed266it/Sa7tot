from __future__ import annotations

from uuid import UUID

from app.schemas.accounts import AccountOut
from app.schemas.categories import CategoryOut
from app.schemas.common import APIModel
from app.schemas.transactions import TransactionOut


class AccountSnapshot(APIModel):
    id: UUID
    name: str
    currency_code: str
    currency_exponent: int
    balance_minor: int


class MovementSummary(APIModel):
    income_minor: int
    expenses_minor: int


class DayGroup(APIModel):
    day: str
    subtotal_minor: int
    movements: list[TransactionOut]


class MovementsResponse(APIModel):
    account: AccountSnapshot
    summary: MovementSummary
    days: list[DayGroup]
    next_cursor: str | None


class BootstrapSubscriptionSummary(APIModel):
    active_count: int
    paused_count: int
    next_billing_date: str | None


class ProfileOut(APIModel):
    user_id: UUID
    locale: str | None
    timezone: str
    default_currency_code: str
    month_start_day: int
    week_start_day: int


class BootstrapResponse(APIModel):
    profile: ProfileOut
    accounts: list[AccountOut]
    categories: list[CategoryOut]
    subscription_summary: BootstrapSubscriptionSummary
