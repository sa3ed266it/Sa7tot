from __future__ import annotations

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.profile import ProfileUpdate
from app.services.common import get_or_create_profile, normalize_currency


async def update_profile(session: AsyncSession, user_id: UUID, payload: ProfileUpdate):
    profile = await get_or_create_profile(session, user_id)
    if payload.default_currency_code is not None:
        profile.default_currency_code = normalize_currency(payload.default_currency_code)
    if payload.month_start_day is not None:
        profile.month_start_day = payload.month_start_day
    if payload.week_start_day is not None:
        profile.week_start_day = payload.week_start_day
    await session.commit()
    await session.refresh(profile)
    return profile
