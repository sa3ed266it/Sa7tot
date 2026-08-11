from __future__ import annotations

from datetime import date
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class APIModel(BaseModel):
    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


class TransactionKind(StrEnum):
    expense = "expense"
    income = "income"
    transfer = "transfer"


class Cadence(StrEnum):
    weekly = "weekly"
    monthly = "monthly"
    yearly = "yearly"


class SubscriptionStatus(StrEnum):
    active = "active"
    paused = "paused"
    cancelled = "cancelled"


class RecurrenceKind(StrEnum):
    expense = "expense"
    income = "income"


class RecurrenceCadence(StrEnum):
    daily = "daily"
    weekly = "weekly"
    monthly = "monthly"


class RecurrenceStatus(StrEnum):
    active = "active"
    paused = "paused"
    cancelled = "cancelled"


class CurrencyFields(BaseModel):
    currency_code: str = Field(min_length=3, max_length=3)
    currency_exponent: int = Field(default=2, ge=0, le=6)

    @field_validator("currency_code")
    @classmethod
    def uppercase_currency(cls, value: str) -> str:
        value = value.upper()
        if not value.isalpha():
            raise ValueError("currency_code must contain three letters")
        return value


class OptionalCurrencyFields(BaseModel):
    currency_code: str | None = Field(default=None, min_length=3, max_length=3)
    currency_exponent: int | None = Field(default=None, ge=0, le=6)

    @field_validator("currency_code")
    @classmethod
    def uppercase_currency(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.upper()
        if not value.isalpha():
            raise ValueError("currency_code must contain three letters")
        return value


class CategoryBrief(APIModel):
    id: UUID
    name: str
    income: bool
    icon_identifier: str
    color: str
    preset_key: str | None


class AccountBrief(APIModel):
    id: UUID
    name: str
    currency_code: str


class TransferBrief(APIModel):
    source_account_id: UUID
    source_account_name: str
    destination_account_id: UUID
    destination_account_name: str


class SubscriptionBrief(APIModel):
    id: UUID | None = None
    service_id: str | None = None
    display_name: str | None = None


class RecurrenceBrief(APIModel):
    rule_id: UUID
    occurrence_id: UUID
    scheduled_date: date
