from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import URL, make_url


class Settings(BaseSettings):
    app_env: str = "development"
    database_url: str = "postgresql+asyncpg://localhost/sa7tot"
    test_database_url: str | None = None

    supabase_url: str | None = None
    supabase_audience: str = "authenticated"

    internal_job_secret: str | None = Field(default=None, repr=False)
    apns_key_id: str | None = None
    apns_team_id: str | None = None
    apns_bundle_id: str = "com.saied.sa7tot"
    apns_private_key: str | None = Field(default=None, repr=False)
    apns_private_key_path: str | None = Field(default=None, repr=False)
    apns_environment: str = "development"
    page_size_default: int = Field(default=50, ge=1, le=200)
    page_size_max: int = Field(default=200, ge=1, le=500)

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    @property
    def sqlalchemy_database_url(self) -> str:
        normalized, _ = self._database_url_parts()
        return normalized.render_as_string(hide_password=False)

    @property
    def sqlalchemy_connect_args(self) -> dict[str, object]:
        _, connect_args = self._database_url_parts()
        return connect_args

    @property
    def supabase_issuer(self) -> str | None:
        base_url = self._supabase_base_url
        return f"{base_url}/auth/v1" if base_url else None

    @property
    def supabase_jwks_url(self) -> str | None:
        base_url = self._supabase_base_url
        return f"{base_url}/auth/v1/.well-known/jwks.json" if base_url else None

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"

    @property
    def apns_base_url(self) -> str:
        environment = self.apns_environment.lower()
        if environment not in {"development", "production"}:
            raise ValueError("APNS_ENVIRONMENT must be development or production")
        return "https://api.push.apple.com" if environment == "production" else "https://api.sandbox.push.apple.com"

    def apns_private_key_material(self) -> str | None:
        if self.apns_private_key:
            return self.apns_private_key.replace("\\n", "\n")
        if self.apns_private_key_path:
            from pathlib import Path

            return Path(self.apns_private_key_path).read_text(encoding="utf-8")
        return None

    @property
    def _supabase_base_url(self) -> str | None:
        if not self.supabase_url:
            return None
        return self.supabase_url.rstrip("/")

    def _database_url_parts(self) -> tuple[URL, dict[str, object]]:
        try:
            url = make_url(self._configured_database_url)
        except (TypeError, ValueError) as exc:
            raise ValueError("DATABASE_URL must be a PostgreSQL connection URL") from exc

        if url.drivername in {"postgres", "postgresql"}:
            url = url.set(drivername="postgresql+asyncpg")
        if url.drivername != "postgresql+asyncpg":
            raise ValueError("DATABASE_URL must use PostgreSQL with the asyncpg driver")

        query = dict(url.query)
        sslmode = str(query.pop("sslmode", "")).lower() or None
        normalized = url.set(query=query)

        connect_args: dict[str, object] = {}
        if sslmode in {"require", "verify-ca", "verify-full"} or (sslmode != "disable" and _is_supabase_host(url.host)):
            connect_args["ssl"] = "require"
        return normalized, connect_args

    @property
    def _configured_database_url(self) -> str:
        if self.app_env.lower() == "test":
            if not self.test_database_url:
                raise ValueError("TEST_DATABASE_URL is required when APP_ENV=test")
            return self.test_database_url
        return self.database_url


def _is_supabase_host(host: str | None) -> bool:
    if not host:
        return False
    return host.endswith(".supabase.co") or host.endswith(".pooler.supabase.com")


@lru_cache
def get_settings() -> Settings:
    return Settings()
