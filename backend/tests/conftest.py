from __future__ import annotations

from collections.abc import AsyncIterator, Callable
from uuid import UUID

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import pool, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import Settings
from app.core.test_safety import validate_test_database_target

settings = Settings()
TEST_DATABASE_URL = validate_test_database_target(
    app_env=settings.app_env,
    test_database_url=settings.test_database_url,
    development_database_url=settings.database_url,
)

from app.core.database import get_session  # noqa: E402
from app.core.security import CurrentUser, get_current_user  # noqa: E402
from app.main import app  # noqa: E402

test_engine = create_async_engine(TEST_DATABASE_URL, poolclass=pool.NullPool, pool_pre_ping=True)
test_session_factory = async_sessionmaker(test_engine, expire_on_commit=False, class_=AsyncSession)
TEST_USER_ID = UUID("11111111-1111-1111-1111-111111111111")
OTHER_USER_ID = UUID("22222222-2222-2222-2222-222222222222")
current_user_id = TEST_USER_ID


async def override_user() -> CurrentUser:
    return CurrentUser(id=current_user_id, claims={})


async def override_session() -> AsyncIterator[AsyncSession]:
    async with test_session_factory() as session:
        yield session


@pytest_asyncio.fixture(autouse=True)
async def clean_database() -> AsyncIterator[None]:
    async with test_engine.begin() as connection:
        await connection.execute(
            text(
                "TRUNCATE TABLE recurrence_occurrences, recurrence_rules, subscription_occurrences, transactions, "
                "subscriptions, "
                "budgets, main_budgets, categories, accounts, profiles RESTART IDENTITY CASCADE"
            )
        )
    yield


@pytest_asyncio.fixture
async def session() -> AsyncIterator[AsyncSession]:
    async with test_session_factory() as session:
        yield session


@pytest_asyncio.fixture
async def session_factory():
    yield test_session_factory


@pytest_asyncio.fixture
async def client() -> AsyncIterator[AsyncClient]:
    app.dependency_overrides[get_current_user] = override_user
    app.dependency_overrides[get_session] = override_session
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def switch_user() -> AsyncIterator[Callable[[], None]]:
    global current_user_id
    original = current_user_id

    def switch() -> None:
        global current_user_id
        current_user_id = OTHER_USER_ID

    yield switch
    current_user_id = original
