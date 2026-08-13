from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.endpoints import (
    accounts,
    bootstrap,
    budget,
    categories,
    movements,
    profile,
    push,
    recurrences,
    subscriptions,
    transactions,
    upcoming,
)

router = APIRouter(prefix="/v1")
router.include_router(bootstrap.router)
router.include_router(accounts.router)
router.include_router(budget.router)
router.include_router(categories.router)
router.include_router(transactions.router)
router.include_router(movements.router)
router.include_router(profile.router)
router.include_router(push.router)
router.include_router(subscriptions.router)
router.include_router(recurrences.router)
router.include_router(upcoming.router)
