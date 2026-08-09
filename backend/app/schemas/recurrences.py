from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

from pydantic import Field

from app.schemas.common import APIModel, CurrencyFields, RecurrenceCadence, RecurrenceKind, RecurrenceStatus


class RecurrenceCreate(CurrencyFields):
    account_id: UUID
    category_id: UUID | None = None
    kind: RecurrenceKind
    amount_minor: int = Field(gt=0)
    title: str | None = Field(default=None, max_length=200)
    note: str | None = Field(default=None, max_length=2000)
    merchant: str | None = Field(default=None, max_length=200)
    cadence: RecurrenceCadence
    cadence_interval: int = Field(default=1, ge=1, le=32767)
    anchor_date: date
    status: RecurrenceStatus = RecurrenceStatus.active


class RecurrenceUpdate(APIModel):
    account_id: UUID | None = None
    category_id: UUID | None = None
    kind: RecurrenceKind | None = None
    amount_minor: int | None = Field(default=None, gt=0)
    currency_code: str | None = Field(default=None, min_length=3, max_length=3)
    currency_exponent: int | None = Field(default=None, ge=0, le=6)
    title: str | None = Field(default=None, max_length=200)
    note: str | None = Field(default=None, max_length=2000)
    merchant: str | None = Field(default=None, max_length=200)
    cadence: RecurrenceCadence | None = None
    cadence_interval: int | None = Field(default=None, ge=1, le=32767)
    anchor_date: date | None = None


class RecurrenceRuleOut(APIModel):
    id: UUID
    user_id: UUID
    account_id: UUID
    category_id: UUID | None
    kind: RecurrenceKind
    amount_minor: int
    currency_code: str
    currency_exponent: int
    title: str | None
    note: str | None
    merchant: str | None
    cadence: RecurrenceCadence
    cadence_interval: int
    anchor_date: date
    next_occurrence_date: date
    status: RecurrenceStatus
    created_at: datetime
    updated_at: datetime


class RecurrenceMaterializationOut(APIModel):
    generated_count: int
    skipped_archived_account_count: int
    skipped_invalid_category_count: int
    skipped_currency_mismatch_count: int
