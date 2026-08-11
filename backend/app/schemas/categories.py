from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.schemas.common import APIModel


class CategoryCreate(APIModel):
    name: str = Field(min_length=1, max_length=200)
    income: bool = False
    icon_identifier: str = Field(default="sf:tag.fill", max_length=200)
    color: str = Field(default="#FFFFFF", max_length=32)
    sort_order: int = 0


class CategoryPresetActivation(APIModel):
    preset_key: str = Field(min_length=1, max_length=100)
    income: bool | None = None
    display_name: str | None = Field(default=None, min_length=1, max_length=200)


class CategoryUpdate(APIModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    income: bool | None = None
    icon_identifier: str | None = Field(default=None, max_length=200)
    color: str | None = Field(default=None, max_length=32)
    sort_order: int | None = None


class CategoryOut(APIModel):
    id: UUID
    user_id: UUID
    name: str
    income: bool
    icon_identifier: str
    color: str
    sort_order: int
    preset_key: str | None
    deleted_at: datetime | None
    created_at: datetime
    updated_at: datetime
