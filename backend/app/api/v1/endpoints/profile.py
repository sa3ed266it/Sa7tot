from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.movements import ProfileOut
from app.schemas.profile import ProfileUpdate
from app.services.profile import update_profile

router = APIRouter(prefix="/profile", tags=["profile"])


@router.patch("", response_model=ProfileOut)
async def patch_profile(
    payload: ProfileUpdate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await update_profile(session, user.id, payload)
