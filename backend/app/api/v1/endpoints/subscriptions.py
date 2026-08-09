from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.common import SubscriptionStatus
from app.schemas.subscriptions import (
    SubscriptionCreate,
    SubscriptionMaterializationOut,
    SubscriptionOut,
    SubscriptionUpdate,
)
from app.services.materialization import materialize_due_subscriptions
from app.services.subscriptions import (
    change_status,
    create_subscription,
    list_subscriptions,
    subscription_display_name,
    update_subscription,
)

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


def to_output(subscription):
    return SubscriptionOut(
        id=subscription.id,
        user_id=subscription.user_id,
        account_id=subscription.account_id,
        category_id=subscription.category_id,
        service_id=subscription.service_id,
        custom_name=subscription.custom_name,
        display_name=subscription_display_name(subscription),
        amount_minor=subscription.amount_minor,
        currency_code=subscription.currency_code,
        currency_exponent=subscription.currency_exponent,
        cadence=subscription.cadence,
        cadence_interval=subscription.cadence_interval,
        billing_anchor=subscription.billing_anchor,
        next_billing_date=subscription.next_billing_date,
        status=subscription.status,
        note=subscription.note,
        created_at=subscription.created_at,
        updated_at=subscription.updated_at,
    )


@router.get("", response_model=list[SubscriptionOut])
async def get_subscriptions(
    session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)
):
    return [to_output(item) for item in await list_subscriptions(session, user.id)]


@router.post("", response_model=SubscriptionOut, status_code=status.HTTP_201_CREATED)
async def post_subscription(
    payload: SubscriptionCreate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return to_output(await create_subscription(session, user.id, payload))


@router.post("/materialize", response_model=SubscriptionMaterializationOut)
async def post_materialize_subscriptions(
    session: AsyncSession = Depends(get_session), user: CurrentUser = Depends(get_current_user)
):
    result = await materialize_due_subscriptions(session, user.id)
    return SubscriptionMaterializationOut(
        generated_count=result.generated_count,
        skipped_archived_account_count=result.skipped_archived_account_count,
    )


@router.patch("/{subscription_id}", response_model=SubscriptionOut)
async def patch_subscription(
    subscription_id: UUID,
    payload: SubscriptionUpdate,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return to_output(await update_subscription(session, user.id, subscription_id, payload))


async def _set_status(subscription_id: UUID, status_value: SubscriptionStatus, session, user):
    return to_output(await change_status(session, user.id, subscription_id, status_value))


@router.post("/{subscription_id}/pause", response_model=SubscriptionOut)
async def pause_subscription(
    subscription_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await _set_status(subscription_id, SubscriptionStatus.paused, session, user)


@router.post("/{subscription_id}/resume", response_model=SubscriptionOut)
async def resume_subscription(
    subscription_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await _set_status(subscription_id, SubscriptionStatus.active, session, user)


@router.post("/{subscription_id}/cancel", response_model=SubscriptionOut)
async def cancel_subscription(
    subscription_id: UUID,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    return await _set_status(subscription_id, SubscriptionStatus.cancelled, session, user)
