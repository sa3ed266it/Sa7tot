from __future__ import annotations

import unicodedata
from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import DomainError
from app.models.entities import Profile


def normalize_name(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).strip().casefold()
    return " ".join(normalized.split())


def normalize_currency(value: str) -> str:
    value = value.upper().strip()
    if len(value) != 3 or not value.isalpha():
        raise DomainError(422, "currency_code must contain three letters", "invalid_currency")
    return value


def ensure_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        raise DomainError(422, "occurred_at must include a timezone", "timezone_required")
    return value.astimezone(UTC)


def local_day_for(value: datetime, timezone_name: str) -> date:
    try:
        timezone = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise DomainError(422, "profile timezone is invalid", "invalid_timezone") from exc
    return value.astimezone(timezone).date()


async def get_or_create_profile(session: AsyncSession, user_id) -> Profile:
    profile = await session.get(Profile, user_id)
    if profile is None:
        await session.execute(
            pg_insert(Profile).values(user_id=user_id).on_conflict_do_nothing(index_elements=[Profile.user_id])
        )
        profile = await session.get(Profile, user_id)
        if profile is None:
            raise RuntimeError("profile creation did not return a profile")
    return profile


async def require_profile(session: AsyncSession, user_id) -> Profile:
    profile = await session.scalar(select(Profile).where(Profile.user_id == user_id))
    if profile is None:
        raise DomainError(404, "profile not found", "profile_not_found")
    return profile


def display_subscription_name(service_id: str | None, custom_name: str | None, stored_name: str | None = None) -> str:
    if stored_name and stored_name.strip():
        return stored_name.strip()
    if custom_name and custom_name.strip():
        return custom_name.strip()
    if service_id and service_id.strip():
        known = {
            "amazon-prime": "Amazon Prime",
            "chatgpt": "ChatGPT",
            "netflix": "Netflix",
            "spotify": "Spotify",
            "adobe-creative-cloud": "Adobe Creative Cloud",
        }
        return known.get(service_id, service_id.replace("-", " ").title())
    return "Abbonamento"
