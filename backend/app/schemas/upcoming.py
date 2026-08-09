from __future__ import annotations

from datetime import date
from typing import Annotated, Literal
from uuid import UUID

from pydantic import Field

from app.schemas.common import AccountBrief, APIModel, CategoryBrief, RecurrenceCadence, RecurrenceKind
from app.schemas.transactions import TransactionOut


class UpcomingTransactionItem(APIModel):
    kind: Literal["transaction"]
    effective_date: date
    transaction: TransactionOut


class UpcomingRecurrenceItem(APIModel):
    kind: Literal["recurrence"]
    effective_date: date
    rule_id: UUID
    scheduled_date: date
    account: AccountBrief
    category: CategoryBrief | None
    transaction_kind: RecurrenceKind
    amount_minor: int
    currency_code: str
    currency_exponent: int
    title: str | None
    note: str | None
    merchant: str | None
    cadence: RecurrenceCadence
    cadence_interval: int


UpcomingItem = Annotated[UpcomingTransactionItem | UpcomingRecurrenceItem, Field(discriminator="kind")]


class UpcomingResponse(APIModel):
    account: AccountBrief
    items: list[UpcomingItem]
