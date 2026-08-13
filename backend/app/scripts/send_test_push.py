from __future__ import annotations

import argparse
import asyncio
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.config import get_settings
from app.core.database import dispose_engine, engine
from app.services.apns import APNsClient, APNsError, PushPayload
from app.services.push_devices import active_device_tokens


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send a development-only generic APNs test push")
    parser.add_argument("--user-id", required=True, type=UUID)
    parser.add_argument("--allow-development-test-push", action="store_true")
    return parser.parse_args()


async def run() -> None:
    args = parse_args()
    settings = get_settings()
    if settings.is_production or not args.allow_development_test_push:
        raise SystemExit("Refusing test push: use APP_ENV=development and explicit test intent")
    environment = settings.apns_environment.lower()
    if environment not in {"development", "production"}:
        raise SystemExit("APNS_ENVIRONMENT must be development or production")

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with session_factory() as session:
        devices = await active_device_tokens(session, args.user_id, environment=environment)

    if not devices:
        print("No active APNs devices found")
        return

    client = APNsClient(settings)
    payload = PushPayload(title="Sa7tot test", body="Push foundation test")
    sent = 0
    deactivated = 0
    for device in devices:
        try:
            await client.send(device.token, payload)
            sent += 1
        except APNsError as error:
            if error.kind == "permanent":
                async with session_factory() as session:
                    from app.services.push_devices import deactivate_device_token

                    await deactivate_device_token(session, args.user_id, device.token)
                deactivated += 1

    print(f"APNs test push complete: attempted={len(devices)} sent={sent} deactivated={deactivated}")
    await dispose_engine()


if __name__ == "__main__":
    asyncio.run(run())
