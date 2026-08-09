from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import Field

from app.schemas.common import (
    APIModel,
    CategoryBrief,
    CurrencyFields,
    OptionalCurrencyFields,
    RecurrenceBrief,
    SubscriptionBrief,
    TransactionKind,
    TransferBrief,
)


class TransactionCreate(CurrencyFields):
    kind: TransactionKind
    account_id: UUID
    amount_minor: int = Field(gt=0)
    occurred_at: datetime
    category_id: UUID | None = None
    note: str | None = None
    merchant: str | None = None
    normalized_merchant: str | None = None
    origin: str | None = None
    review_status: str | None = None
    external_reference: str | None = None
    subscription_id: UUID | None = None
    subscription_service_id: str | None = None
    subscription_occurrence_key: str | None = None
    subscription_display_name: str | None = None


class TransactionUpdate(OptionalCurrencyFields):
    kind: TransactionKind | None = None
    account_id: UUID | None = None
    amount_minor: int | None = Field(default=None, gt=0)
    occurred_at: datetime | None = None
    category_id: UUID | None = None
    note: str | None = None
    merchant: str | None = None
    normalized_merchant: str | None = None
    origin: str | None = None
    review_status: str | None = None
    external_reference: str | None = None


class TransferCreate(CurrencyFields):
    source_account_id: UUID
    destination_account_id: UUID
    amount_minor: int = Field(gt=0)
    occurred_at: datetime
    note: str | None = None


class TransactionOut(APIModel):
    id: UUID
    user_id: UUID
    kind: TransactionKind
    account_id: UUID
    destination_account_id: UUID | None
    amount_minor: int
    currency_code: str
    currency_exponent: int
    occurred_at: datetime
    local_day: date
    title: str
    effective_amount_minor: int | None = None
    category: CategoryBrief | None = None
    transfer: TransferBrief | None = None
    subscription: SubscriptionBrief | None = None
    recurrence: RecurrenceBrief | None = None
    note: str | None
    merchant: str | None
    origin: str | None
    review_status: str | None
    external_reference: str | None
    created_at: datetime
    updated_at: datetime
