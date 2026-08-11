from __future__ import annotations

from pydantic import BaseModel, Field, field_validator


class ProfileUpdate(BaseModel):
    default_currency_code: str | None = Field(default=None, min_length=3, max_length=3)
    month_start_day: int | None = Field(default=None, ge=1, le=31)
    week_start_day: int | None = Field(default=None, ge=1, le=7)

    @field_validator("default_currency_code", mode="before")
    @classmethod
    def normalize_currency(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise ValueError("default_currency_code must contain three letters")
        value = value.strip().upper()
        if len(value) != 3 or not value.isalpha():
            raise ValueError("default_currency_code must contain three letters")
        return value
