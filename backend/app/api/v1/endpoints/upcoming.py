from __future__ import annotations

from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.upcoming import UpcomingResponse
from app.services.upcoming import get_upcoming

router = APIRouter(prefix="/accounts", tags=["upcoming"])


@router.get("/{account_id}/upcoming", response_model=UpcomingResponse)
async def get_upcoming_endpoint(
    account_id: UUID,
    limit: int | None = Query(default=None, ge=1),
    days: int | None = Query(default=None, ge=0, le=366),
    until: date | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    settings = get_settings()
    page_limit = min(limit or settings.page_size_default, settings.page_size_max)
    return await get_upcoming(session, user.id, account_id, page_limit, days=days, until=until)
