from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.push import (
    PushDeviceTokenDeactivationOut,
    PushDeviceTokenOut,
    PushDeviceTokenUpsert,
)
from app.services.push_devices import deactivate_device_token, upsert_device_token

router = APIRouter(prefix="/push/devices", tags=["push"])


@router.put("", response_model=PushDeviceTokenOut)
async def put_device_token(
    payload: PushDeviceTokenUpsert,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    device = await upsert_device_token(session, user.id, payload)
    return PushDeviceTokenOut(
        id=device.id,
        platform=device.platform,
        environment=device.environment,
        is_active=device.is_active,
    )


@router.delete("/{token}", response_model=PushDeviceTokenDeactivationOut)
async def delete_device_token(
    token: str,
    session: AsyncSession = Depends(get_session),
    user: CurrentUser = Depends(get_current_user),
):
    deactivated = await deactivate_device_token(session, user.id, token)
    return PushDeviceTokenDeactivationOut(deactivated=deactivated)
