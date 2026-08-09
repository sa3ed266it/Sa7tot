from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.accounts import AccountCreate, AccountOut, AccountUpdate
from app.services.accounts import archive_account, create_account, list_accounts, update_account

router = APIRouter(prefix="/accounts", tags=["accounts"])


@router.get("", response_model=list[AccountOut])
async def get_accounts(session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)):
    return await list_accounts(session, user.id)


@router.post("", response_model=AccountOut, status_code=status.HTTP_201_CREATED)
async def post_account(
    payload: AccountCreate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await create_account(session, user.id, payload)


@router.patch("/{account_id}", response_model=AccountOut)
async def patch_account(
    account_id: UUID,
    payload: AccountUpdate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await update_account(session, user.id, account_id, payload)


@router.post("/{account_id}/archive", response_model=AccountOut)
async def post_archive_account(
    account_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await archive_account(session, user.id, account_id)
