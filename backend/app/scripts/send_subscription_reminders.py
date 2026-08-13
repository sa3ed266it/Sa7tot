from __future__ import annotations

import argparse
import asyncio
from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.config import get_settings
from app.core.database import dispose_engine, engine
from app.services.subscription_reminders import SubscriptionReminderService


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send server-side subscription renewal reminders")
    parser.add_argument(
        "--environment",
        choices=("development", "production"),
        default=None,
        help="APNs environment; defaults to APNS_ENVIRONMENT",
    )
    parser.add_argument("--dry-run", action="store_true", help="Inspect eligible work without sending APNs")
    parser.add_argument(
        "--now",
        type=_parse_now,
        default=None,
        help="Reference UTC time for deterministic development validation (ISO-8601)",
    )
    parser.add_argument(
        "--allow-production",
        action="store_true",
        help="Explicitly permit production reminder sends",
    )
    return parser.parse_args()


async def run() -> None:
    args = parse_args()
    settings = get_settings()
    environment = (args.environment or settings.apns_environment).lower()
    if environment not in {"development", "production"}:
        raise SystemExit("APNS_ENVIRONMENT must be development or production")
    if environment != settings.apns_environment.lower():
        raise SystemExit("requested environment does not match APNS_ENVIRONMENT")
    if environment == "production" and (not settings.is_production or not args.allow_production):
        raise SystemExit("Refusing production reminder send without production configuration and explicit intent")

    session_factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    try:
        async with session_factory() as session:
            service = SubscriptionReminderService(
                session,
                environment=environment,
                now_utc=args.now,
                settings=settings,
                dry_run=args.dry_run,
            )
            summary = await service.run()
        mode = "dry-run" if args.dry_run else "send"
        print(
            f"subscription reminders {mode}: "
            f"eligible={summary.eligible_subscriptions} "
            f"events={summary.logical_events_created_or_reused} "
            f"attempted={summary.device_deliveries_attempted} "
            f"sent={summary.sent} "
            f"permanent_failures={summary.permanent_failures} "
            f"retryable={summary.retryable_failures} "
            f"invalid_timezone={summary.skipped_invalid_timezone} "
            f"new_inside_window={summary.skipped_new_inside_window} "
            f"expired={summary.expired} "
            f"no_active_devices={summary.no_active_devices}"
        )
    finally:
        await dispose_engine()


def _parse_now(value: str) -> datetime:
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


if __name__ == "__main__":
    asyncio.run(run())
