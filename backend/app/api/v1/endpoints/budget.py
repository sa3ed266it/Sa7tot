from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.budget import BudgetCategoryMutation, BudgetMutation, BudgetSummaryOut
from app.services.budget import delete_category_budget, delete_main, get_summary, upsert_category, upsert_main

router = APIRouter(prefix="/budget", tags=["budget"])


@router.get("", response_model=BudgetSummaryOut)
async def get_budget(session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)):
    return await get_summary(session, user.id)


@router.put("/main", response_model=BudgetSummaryOut, status_code=status.HTTP_200_OK)
async def put_main_budget(
    payload: BudgetMutation,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await upsert_main(session, user.id, payload)


@router.delete("/main", response_model=BudgetSummaryOut)
async def remove_main_budget(
    session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)
):
    return await delete_main(session, user.id)


@router.put("/categories/{category_id}", response_model=BudgetSummaryOut, status_code=status.HTTP_200_OK)
async def put_category_budget(
    category_id: UUID,
    payload: BudgetMutation,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    category_payload = BudgetCategoryMutation(category_id=category_id, **payload.model_dump())
    return await upsert_category(session, user.id, category_payload)


@router.delete("/categories/{category_id}", response_model=BudgetSummaryOut)
async def remove_category_budget(
    category_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await delete_category_budget(session, user.id, category_id)
