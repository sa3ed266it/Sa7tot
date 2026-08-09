from __future__ import annotations

from collections.abc import Mapping

from sqlalchemy.engine import URL, make_url


def validate_test_database_target(
    *,
    app_env: str | None,
    test_database_url: str | None,
    development_database_url: str | None = None,
) -> str:
    """Return a safe test URL or fail closed before any destructive fixture runs."""

    if (app_env or "").lower() != "test":
        raise RuntimeError("destructive database tests require APP_ENV=test")
    if not test_database_url:
        raise RuntimeError("destructive database tests require TEST_DATABASE_URL")

    test_url = _parse_postgres_url(test_database_url, "TEST_DATABASE_URL")
    test_identity = _database_identity(test_url)

    if development_database_url:
        development_url = _parse_postgres_url(development_database_url, "DATABASE_URL")
        if test_identity == _database_identity(development_url):
            raise RuntimeError("TEST_DATABASE_URL must not target the configured DATABASE_URL database")

    database_name = (test_url.database or "").lower()
    if "test" not in database_name:
        raise RuntimeError("TEST_DATABASE_URL must point to a database whose name contains 'test'")
    if _is_supabase_host(test_url.host):
        raise RuntimeError("destructive tests refuse Supabase database targets")

    return test_url.render_as_string(hide_password=False)


def validate_test_environment(environ: Mapping[str, str]) -> str:
    """Validate process configuration without exposing URLs or credentials."""

    return validate_test_database_target(
        app_env=environ.get("APP_ENV"),
        test_database_url=environ.get("TEST_DATABASE_URL"),
        development_database_url=environ.get("DATABASE_URL"),
    )


def _parse_postgres_url(raw_url: str, label: str) -> URL:
    try:
        url = make_url(raw_url)
    except (TypeError, ValueError) as exc:
        raise RuntimeError(f"{label} must be a PostgreSQL connection URL") from exc
    if url.drivername in {"postgres", "postgresql"}:
        url = url.set(drivername="postgresql+asyncpg")
    if url.drivername != "postgresql+asyncpg":
        raise RuntimeError(f"{label} must use PostgreSQL with the asyncpg driver")
    if not url.host or not url.database:
        raise RuntimeError(f"{label} must include a host and database name")
    return url


def _database_identity(url: URL) -> tuple[str, int, str]:
    return (url.host.lower(), url.port or 5432, url.database or "")


def _is_supabase_host(host: str | None) -> bool:
    return bool(host) and (host.endswith(".supabase.co") or host.endswith(".pooler.supabase.com"))
