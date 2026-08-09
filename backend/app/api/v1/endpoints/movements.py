from __future__ import annotations

from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.movements import MovementsResponse
from app.services.movements import get_account_movements

router = APIRouter(prefix="/accounts", tags=["movimenti"])


@router.get("/{account_id}/movements", response_model=MovementsResponse)
async def get_movements(
    account_id: UUID,
    limit: int | None = Query(default=None, ge=1),
    cursor: str | None = Query(default=None),
    filter: str = Query(default="all", pattern="^(all|type|day|week|month|category|recurring)$"),
    income: bool | None = Query(default=None),
    day: date | None = Query(default=None),
    week_start: date | None = Query(default=None),
    month: str | None = Query(default=None, pattern="^\\d{4}-\\d{2}$"),
    category_id: UUID | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    settings = get_settings()
    page_limit = min(limit or settings.page_size_default, settings.page_size_max)
    return await get_account_movements(
        session,
        user.id,
        account_id,
        page_limit,
        cursor,
        filter=filter,
        income=income,
        day=day,
        week_start=week_start,
        month=month,
        category_id=category_id,
    )
