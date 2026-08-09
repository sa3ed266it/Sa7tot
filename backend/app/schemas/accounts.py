from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.common import APIModel, CurrencyFields, OptionalCurrencyFields


class AccountCreate(CurrencyFields):
    name: str = Field(min_length=1, max_length=200)
    type: str = Field(default="other", min_length=1, max_length=50)
    opening_balance_minor: int = 0
    icon_name: str = Field(default="building.columns.fill", max_length=200)
    color: str = Field(default="#5E7CE2", max_length=32)
    wallet_label: str | None = Field(default=None, max_length=200)
    is_archived: bool = False
    sort_order: int = 0

    @field_validator("name")
    @classmethod
    def non_blank_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("name must not be blank")
        return value


class AccountUpdate(OptionalCurrencyFields):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    type: str | None = Field(default=None, min_length=1, max_length=50)
    opening_balance_minor: int | None = None
    icon_name: str | None = Field(default=None, max_length=200)
    color: str | None = Field(default=None, max_length=32)
    wallet_label: str | None = Field(default=None, max_length=200)
    sort_order: int | None = None


class AccountOut(APIModel):
    id: UUID
    user_id: UUID
    name: str
    type: str
    currency_code: str
    currency_exponent: int
    opening_balance_minor: int
    icon_name: str
    color: str
    wallet_label: str | None
    is_archived: bool
    sort_order: int
    created_at: datetime
    updated_at: datetime
