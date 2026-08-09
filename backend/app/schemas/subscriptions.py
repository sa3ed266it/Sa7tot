from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.common import APIModel, Cadence, CurrencyFields, OptionalCurrencyFields, SubscriptionStatus


class SubscriptionCreate(CurrencyFields):
    account_id: UUID
    category_id: UUID | None = None
    service_id: str | None = Field(default=None, max_length=200)
    custom_name: str | None = Field(default=None, max_length=200)
    amount_minor: int = Field(gt=0)
    cadence: Cadence
    cadence_interval: int = Field(default=1, ge=1, le=32767)
    billing_anchor: date
    next_billing_date: date | None = None
    status: SubscriptionStatus = SubscriptionStatus.active
    note: str | None = None

    @model_validator(mode="after")
    def validate_identity(self):
        if bool(self.service_id) == bool(self.custom_name):
            raise ValueError("provide exactly one of service_id or custom_name")
        return self


class SubscriptionUpdate(OptionalCurrencyFields):
    account_id: UUID | None = None
    category_id: UUID | None = None
    service_id: str | None = Field(default=None, max_length=200)
    custom_name: str | None = Field(default=None, max_length=200)
    amount_minor: int | None = Field(default=None, gt=0)
    cadence: Cadence | None = None
    cadence_interval: int | None = Field(default=None, ge=1, le=32767)
    billing_anchor: date | None = None
    next_billing_date: date | None = None
    note: str | None = None


class SubscriptionOut(APIModel):
    id: UUID
    user_id: UUID
    account_id: UUID
    category_id: UUID | None
    service_id: str | None
    custom_name: str | None
    display_name: str
    amount_minor: int
    currency_code: str
    currency_exponent: int
    cadence: Cadence
    cadence_interval: int
    billing_anchor: date
    next_billing_date: date
    status: SubscriptionStatus
    note: str | None
    created_at: datetime
    updated_at: datetime


class SubscriptionMaterializationOut(APIModel):
    generated_count: int
    skipped_archived_account_count: int
