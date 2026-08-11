from __future__ import annotations

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.categories import CategoryOut
from app.schemas.movements import (
    BootstrapResponse,
    BootstrapSubscriptionSummary,
    ProfileOut,
)
from app.services.accounts import list_accounts
from app.services.categories import list_categories
from app.services.common import get_or_create_profile
from app.services.subscriptions import list_subscriptions


async def get_bootstrap(session: AsyncSession, user_id: UUID) -> BootstrapResponse:
    profile = await get_or_create_profile(session, user_id)
    await session.commit()
    accounts = await list_accounts(session, user_id, active_only=True)
    categories = await list_categories(session, user_id)
    subscriptions = await list_subscriptions(session, user_id)
    active = [item for item in subscriptions if item.status == "active"]
    paused = [item for item in subscriptions if item.status == "paused"]
    next_date = min((item.next_billing_date for item in active), default=None)
    return BootstrapResponse(
        profile=ProfileOut(
            user_id=profile.user_id,
            locale=profile.locale,
            timezone=profile.timezone,
            default_currency_code=profile.default_currency_code,
            month_start_day=profile.month_start_day,
            week_start_day=profile.week_start_day,
        ),
        accounts=accounts,
        categories=[CategoryOut.model_validate(category) for category in categories],
        subscription_summary=BootstrapSubscriptionSummary(
            active_count=len(active),
            paused_count=len(paused),
            next_billing_date=next_date.isoformat() if next_date else None,
        ),
    )
