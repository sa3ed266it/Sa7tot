from __future__ import annotations

from app.core.config import Settings


def test_database_urls_normalize_postgres_and_supabase_tls():
    settings = Settings(
        _env_file=None,
        app_env="development",
        database_url="postgres://user:password@db.example.test:5432/sa7tot?sslmode=require",
        test_database_url=None,
    )
    assert settings.sqlalchemy_database_url == "postgresql+asyncpg://user:password@db.example.test:5432/sa7tot"
    assert settings.sqlalchemy_connect_args == {"ssl": "require"}

    supabase = Settings(
        _env_file=None,
        app_env="development",
        database_url="postgresql+asyncpg://user:password@db.example.supabase.co:5432/postgres",
        test_database_url=None,
    )
    assert supabase.sqlalchemy_connect_args == {"ssl": "require"}


def test_supabase_auth_urls_are_derived_and_optional():
    settings = Settings(_env_file=None)
    assert settings.supabase_issuer is None
    assert settings.supabase_jwks_url is None

    configured = Settings(_env_file=None, supabase_url="https://project.supabase.co/")
    assert configured.supabase_issuer == "https://project.supabase.co/auth/v1"
    assert configured.supabase_jwks_url == "https://project.supabase.co/auth/v1/.well-known/jwks.json"
