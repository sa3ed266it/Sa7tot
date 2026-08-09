from __future__ import annotations

from datetime import date, datetime
from enum import StrEnum
from uuid import UUID

from pydantic import Field

from app.schemas.common import APIModel, CurrencyFields


class BudgetPeriod(StrEnum):
    day = "day"
    week = "week"
    month = "month"
    year = "year"


class BudgetMutation(CurrencyFields):
    amount_minor: int = Field(ge=0)
    period_type: BudgetPeriod
    period_start: date | None = None


class BudgetCategoryMutation(BudgetMutation):
    category_id: UUID


class BudgetCategoryOut(APIModel):
    id: UUID
    category_id: UUID
    category_name: str | None
    category_deleted: bool
    category_icon_identifier: str | None
    category_color: str | None
    amount_minor: int
    spent_minor: int
    remaining_minor: int
    progress: float
    currency_code: str
    currency_exponent: int
    period_type: BudgetPeriod
    period_start: date
    period_end: date
    created_at: datetime
    updated_at: datetime


class MainBudgetOut(APIModel):
    id: UUID
    amount_minor: int
    spent_minor: int
    remaining_minor: int
    progress: float
    currency_code: str
    currency_exponent: int
    period_type: BudgetPeriod
    period_start: date
    period_end: date
    created_at: datetime
    updated_at: datetime


class BudgetSummaryOut(APIModel):
    main: MainBudgetOut | None
    categories: list[BudgetCategoryOut]
