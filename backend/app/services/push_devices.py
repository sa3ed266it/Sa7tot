from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entities import PushDeviceToken
from app.schemas.push import PushDeviceTokenUpsert


async def upsert_device_token(
    session: AsyncSession, user_id: UUID, payload: PushDeviceTokenUpsert
) -> PushDeviceToken:
    normalized_token = payload.token.lower()
    device = await session.scalar(select(PushDeviceToken).where(PushDeviceToken.token == normalized_token))
    now = datetime.now(UTC)
    if device is None:
        device = PushDeviceToken(
            user_id=user_id,
            token=normalized_token,
            platform=payload.platform,
            environment=payload.environment,
            app_version=payload.app_version,
            last_seen_at=now,
            is_active=True,
        )
        session.add(device)
    else:
        device.user_id = user_id
        device.token = normalized_token
        device.platform = payload.platform
        device.environment = payload.environment
        device.app_version = payload.app_version
        device.last_seen_at = now
        device.is_active = True

    await session.commit()
    await session.refresh(device)
    return device


async def deactivate_device_token(session: AsyncSession, user_id: UUID, token: str) -> bool:
    device = await session.scalar(
        select(PushDeviceToken).where(
            PushDeviceToken.user_id == user_id,
            PushDeviceToken.token == token.lower(),
        )
    )
    if device is None or not device.is_active:
        return False

    device.is_active = False
    await session.commit()
    return True


async def active_device_tokens(
    session: AsyncSession, user_id: UUID, environment: str | None = None
) -> list[PushDeviceToken]:
    conditions = [PushDeviceToken.user_id == user_id, PushDeviceToken.is_active.is_(True)]
    if environment is not None:
        conditions.append(PushDeviceToken.environment == environment)
    result = await session.scalars(select(PushDeviceToken).where(*conditions))
    return list(result.all())
