from __future__ import annotations

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.models.entities import PushDeviceToken

TOKEN = "ab" * 32


async def register(client: AsyncClient, token: str = TOKEN):
    return await client.put(
        "/v1/push/devices",
        json={
            "token": token,
            "platform": "ios",
            "environment": "development",
            "app_version": "2.1.4",
        },
    )


@pytest.mark.asyncio
async def test_device_registration_is_authenticated_and_idempotent(client: AsyncClient, session):
    first = await register(client)
    assert first.status_code == 200, first.text

    repeated = await register(client)
    assert repeated.status_code == 200
    assert repeated.json()["id"] == first.json()["id"]
    assert repeated.json()["is_active"] is True
    assert await session.scalar(select(func.count()).select_from(PushDeviceToken)) == 1


@pytest.mark.asyncio
async def test_device_token_can_be_deactivated_only_by_current_user(client: AsyncClient, switch_user, session):
    created = await register(client)
    token_id = created.json()["id"]

    switch_user()
    other_user_delete = await client.delete(f"/v1/push/devices/{TOKEN}")
    assert other_user_delete.status_code == 200
    assert other_user_delete.json() == {"deactivated": False}

    switch_user()
    owner_delete = await client.delete(f"/v1/push/devices/{TOKEN}")
    assert owner_delete.status_code == 200
    assert owner_delete.json() == {"deactivated": True}
    device = await session.get(PushDeviceToken, token_id)
    assert device is not None
    assert device.is_active is False


@pytest.mark.asyncio
async def test_invalid_platform_and_token_are_rejected(client: AsyncClient):
    invalid_platform = await client.put(
        "/v1/push/devices",
        json={"token": TOKEN, "platform": "android", "environment": "development"},
    )
    assert invalid_platform.status_code == 422

    invalid_token = await client.put(
        "/v1/push/devices",
        json={"token": "not-a-token", "platform": "ios", "environment": "development"},
    )
    assert invalid_token.status_code == 422


@pytest.mark.asyncio
async def test_token_re_registration_reassigns_installation_without_duplicate(
    client: AsyncClient, switch_user, session
):
    first = await register(client)
    switch_user()
    second = await register(client)
    assert second.json()["id"] == first.json()["id"]
    device = await session.scalar(select(PushDeviceToken).where(PushDeviceToken.token == TOKEN))
    assert str(device.user_id) != "11111111-1111-1111-1111-111111111111"
    assert device.is_active is True
