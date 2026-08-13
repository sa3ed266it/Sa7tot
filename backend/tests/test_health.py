from __future__ import annotations

from httpx import AsyncClient


async def test_readiness_checks_database(client: AsyncClient):
    live_response = await client.get("/health/live")
    response = await client.get("/health/ready")

    assert live_response.status_code == 200
    assert live_response.json() == {"status": "ok"}
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
