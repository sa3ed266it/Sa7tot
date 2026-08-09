from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.transactions import TransactionCreate, TransactionOut, TransactionUpdate, TransferCreate
from app.services.transactions import (
    create_transaction,
    create_transfer,
    delete_transaction,
    get_transaction,
    transaction_out,
    update_transaction,
)

router = APIRouter(tags=["transactions"])


@router.get("/transactions/{transaction_id}", response_model=TransactionOut)
async def get_transaction_endpoint(
    transaction_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    transaction = await get_transaction(session, user.id, transaction_id)
    return await transaction_out(session, transaction)


@router.post("/transactions", response_model=TransactionOut, status_code=status.HTTP_201_CREATED)
async def post_transaction(
    payload: TransactionCreate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    transaction = await create_transaction(session, user.id, payload)
    return await transaction_out(session, transaction)


@router.patch("/transactions/{transaction_id}", response_model=TransactionOut)
async def patch_transaction(
    transaction_id: UUID,
    payload: TransactionUpdate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    transaction = await update_transaction(session, user.id, transaction_id, payload)
    return await transaction_out(session, transaction)


@router.delete("/transactions/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_transaction_endpoint(
    transaction_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    await delete_transaction(session, user.id, transaction_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/transfers", response_model=TransactionOut, status_code=status.HTTP_201_CREATED)
async def post_transfer(
    payload: TransferCreate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    transaction = await create_transfer(session, user.id, payload)
    return await transaction_out(session, transaction)
