from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.movements import BootstrapResponse
from app.services.bootstrap import get_bootstrap

router = APIRouter(tags=["bootstrap"])


@router.get("/bootstrap", response_model=BootstrapResponse)
async def bootstrap(session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)):
    return await get_bootstrap(session, user.id)
