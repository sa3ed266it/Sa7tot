from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import Field

from app.schemas.common import APIModel


class PushDeviceTokenUpsert(APIModel):
    token: str = Field(min_length=32, max_length=512, pattern=r"^[0-9a-fA-F]+$")
    platform: Literal["ios"] = "ios"
    environment: Literal["development", "production"]
    app_version: str | None = Field(default=None, max_length=64)


class PushDeviceTokenOut(APIModel):
    id: UUID
    platform: Literal["ios"]
    environment: Literal["development", "production"]
    is_active: bool


class PushDeviceTokenDeactivationOut(APIModel):
    deactivated: bool
