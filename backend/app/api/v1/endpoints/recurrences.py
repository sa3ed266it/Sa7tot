from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.common import RecurrenceStatus
from app.schemas.recurrences import RecurrenceCreate, RecurrenceMaterializationOut, RecurrenceRuleOut, RecurrenceUpdate
from app.services.recurrences import (
    change_recurrence_status,
    create_recurrence_rule,
    get_recurrence_rule,
    list_recurrence_rules,
    materialize_due_recurrences,
    update_recurrence_rule,
)

router = APIRouter(prefix="/recurrences", tags=["recurrences"])


@router.get("", response_model=list[RecurrenceRuleOut])
async def get_recurrences(session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)):
    return await list_recurrence_rules(session, user.id)


@router.post("", response_model=RecurrenceRuleOut, status_code=status.HTTP_201_CREATED)
async def post_recurrence(
    payload: RecurrenceCreate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await create_recurrence_rule(session, user.id, payload)


@router.post("/materialize", response_model=RecurrenceMaterializationOut)
async def post_materialize_recurrences(
    session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)
):
    result = await materialize_due_recurrences(session, user.id)
    return RecurrenceMaterializationOut(
        generated_count=result.generated_count,
        skipped_archived_account_count=result.skipped_archived_account_count,
        skipped_invalid_category_count=result.skipped_invalid_category_count,
        skipped_currency_mismatch_count=result.skipped_currency_mismatch_count,
    )


@router.get("/{rule_id}", response_model=RecurrenceRuleOut)
async def get_recurrence(
    rule_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await get_recurrence_rule(session, user.id, rule_id)


@router.patch("/{rule_id}", response_model=RecurrenceRuleOut)
async def patch_recurrence(
    rule_id: UUID,
    payload: RecurrenceUpdate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await update_recurrence_rule(session, user.id, rule_id, payload)


async def _set_status(rule_id: UUID, status_value: RecurrenceStatus, session: AsyncSession, user: CurrentUser):
    return await change_recurrence_status(session, user.id, rule_id, status_value)


@router.post("/{rule_id}/pause", response_model=RecurrenceRuleOut)
async def pause_recurrence(
    rule_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await _set_status(rule_id, RecurrenceStatus.paused, session, user)


@router.post("/{rule_id}/resume", response_model=RecurrenceRuleOut)
async def resume_recurrence(
    rule_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await _set_status(rule_id, RecurrenceStatus.active, session, user)


@router.post("/{rule_id}/cancel", response_model=RecurrenceRuleOut)
async def cancel_recurrence(
    rule_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await _set_status(rule_id, RecurrenceStatus.cancelled, session, user)
