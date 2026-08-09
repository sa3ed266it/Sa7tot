from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.categories import CategoryCreate, CategoryOut, CategoryUpdate
from app.services.categories import (
    create_category,
    list_categories,
    soft_delete_category,
    update_category,
)

router = APIRouter(prefix="/categories", tags=["categories"])


@router.get("", response_model=list[CategoryOut])
async def get_categories(session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)):
    return await list_categories(session, user.id)


@router.post("", response_model=CategoryOut, status_code=status.HTTP_201_CREATED)
async def post_category(
    payload: CategoryCreate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await create_category(session, user.id, payload)


@router.patch("/{category_id}", response_model=CategoryOut)
async def patch_category(
    category_id: UUID,
    payload: CategoryUpdate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await update_category(session, user.id, category_id, payload)


@router.delete("/{category_id}", response_model=CategoryOut)
async def delete_category(
    category_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await soft_delete_category(session, user.id, category_id)
