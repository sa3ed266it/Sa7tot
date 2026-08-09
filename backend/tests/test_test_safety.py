from __future__ import annotations

import pytest

from app.core.test_safety import validate_test_database_target, validate_test_environment


def test_missing_test_database_url_fails_closed() -> None:
    with pytest.raises(RuntimeError, match="TEST_DATABASE_URL"):
        validate_test_database_target(app_env="test", test_database_url=None, development_database_url=None)


def test_non_test_environment_fails_closed() -> None:
    with pytest.raises(RuntimeError, match="APP_ENV=test"):
        validate_test_database_target(
            app_env="development",
            test_database_url="postgresql+asyncpg://localhost/sa7tot_test",
        )


def test_same_database_target_fails_closed() -> None:
    url = "postgresql+asyncpg://localhost/sa7tot_test"
    with pytest.raises(RuntimeError, match="must not target"):
        validate_test_database_target(app_env="test", test_database_url=url, development_database_url=url)


def test_supabase_target_fails_closed() -> None:
    with pytest.raises(RuntimeError, match="Supabase"):
        validate_test_database_target(
            app_env="test",
            test_database_url="postgresql+asyncpg://postgres:password@db.example.supabase.co:5432/sa7tot_test",
        )


def test_valid_isolated_target_is_allowed() -> None:
    url = validate_test_environment(
        {
            "APP_ENV": "test",
            "TEST_DATABASE_URL": "postgresql+asyncpg://localhost/sa7tot_test",
            "DATABASE_URL": "postgresql+asyncpg://localhost/sa7tot",
        }
    )
    assert url == "postgresql+asyncpg://localhost/sa7tot_test"
