from __future__ import annotations

import asyncio
import json
import time
from collections.abc import Callable
from dataclasses import dataclass
from functools import lru_cache
from uuid import UUID

import httpx
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt.algorithms import ECAlgorithm, RSAAlgorithm

from app.core.config import Settings, get_settings

bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True, slots=True)
class CurrentUser:
    id: UUID
    claims: dict[str, object]


class JWTConfigurationError(RuntimeError):
    pass


class JWTValidationError(RuntimeError):
    pass


class JWTKeyFetchError(RuntimeError):
    pass


class SupabaseJWTValidator:
    def __init__(
        self,
        settings: Settings,
        *,
        jwks_ttl_seconds: float = 600.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.settings = settings
        self._jwks_ttl_seconds = jwks_ttl_seconds
        self._clock = clock
        self._jwks_by_kid: dict[str, dict[str, object]] = {}
        self._jwks_expires_at = 0.0
        self._jwks_generation = 0
        self._jwks_lock = asyncio.Lock()
        self._jwks_refresh_task: asyncio.Task[dict[str, object]] | None = None
        self._http_client: httpx.AsyncClient | None = None

    async def validate(self, token: str) -> CurrentUser:
        if not self.settings.supabase_jwks_url or not self.settings.supabase_issuer:
            raise JWTConfigurationError("SUPABASE_URL is not configured for authenticated routes")

        try:
            header = jwt.get_unverified_header(token)
            unverified_claims = jwt.decode(token, options={"verify_signature": False})
            kid = header.get("kid")
            if not isinstance(kid, str) or not kid:
                raise JWTValidationError("The Supabase access token has no signing key identifier")
            jwk = await self._jwk_for_kid(kid)

            key = _key_from_jwk(jwk)
            claims = jwt.decode(
                token,
                key=key,
                algorithms=[header.get("alg", "RS256")],
                audience=self.settings.supabase_audience,
                issuer=self.settings.supabase_issuer,
            )
            user_id = UUID(str(claims["sub"]))
        except JWTValidationError:
            raise
        except (KeyError, TypeError, ValueError, jwt.PyJWTError) as exc:
            raise JWTValidationError("The Supabase access token is invalid") from exc

        if unverified_claims.get("sub") != claims.get("sub"):
            raise JWTValidationError("The Supabase access token subject changed during validation")
        return CurrentUser(id=user_id, claims=claims)

    async def _jwk_for_kid(self, kid: str) -> dict[str, object]:
        now = self._clock()
        observed_generation = self._jwks_generation
        if now < self._jwks_expires_at and kid in self._jwks_by_kid:
            return self._jwks_by_kid[kid]

        await self._refresh_jwks(observed_generation)
        jwk = self._jwks_by_kid.get(kid)
        if jwk is None:
            raise JWTValidationError("No matching Supabase signing key was found")
        return jwk

    async def _refresh_jwks(self, observed_generation: int) -> None:
        async with self._jwks_lock:
            if self._jwks_generation != observed_generation:
                return
            refresh_task = self._jwks_refresh_task
            if refresh_task is None:
                refresh_task = asyncio.create_task(self._fetch_jwks())
                self._jwks_refresh_task = refresh_task

        try:
            jwks = await refresh_task
            raw_keys = jwks.get("keys")
            if not isinstance(raw_keys, list):
                raise JWTKeyFetchError("Supabase signing keys response is malformed")
            keys = {
                str(key["kid"]): key for key in raw_keys if isinstance(key, dict) and isinstance(key.get("kid"), str)
            }
            async with self._jwks_lock:
                if self._jwks_generation == observed_generation:
                    self._jwks_by_kid = keys
                    self._jwks_expires_at = self._clock() + self._jwks_ttl_seconds
                    self._jwks_generation += 1
        finally:
            async with self._jwks_lock:
                if self._jwks_refresh_task is refresh_task:
                    self._jwks_refresh_task = None

    async def _fetch_jwks(self) -> dict[str, object]:
        try:
            client = await self._get_http_client()
            response = await client.get(self.settings.supabase_jwks_url)
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict):
                raise ValueError("JWKS response must be an object")
            return payload
        except (httpx.HTTPError, ValueError, TypeError) as exc:
            raise JWTKeyFetchError("Supabase signing keys could not be loaded") from exc

    async def _get_http_client(self) -> httpx.AsyncClient:
        async with self._jwks_lock:
            if self._http_client is None:
                self._http_client = httpx.AsyncClient(timeout=5)
            return self._http_client

    async def aclose(self) -> None:
        async with self._jwks_lock:
            client = self._http_client
            self._http_client = None
        if client is not None:
            await client.aclose()


def _key_from_jwk(jwk: dict[str, object]):
    key_type = jwk.get("kty")
    serialized = json.dumps(jwk)
    if key_type == "RSA":
        return RSAAlgorithm.from_jwk(serialized)
    if key_type == "EC":
        return ECAlgorithm.from_jwk(serialized)
    raise JWTValidationError(f"Unsupported JWT key type: {key_type}")


@lru_cache
def get_jwt_validator() -> SupabaseJWTValidator:
    return SupabaseJWTValidator(get_settings())


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> CurrentUser:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required")
    try:
        return await get_jwt_validator().validate(credentials.credentials)
    except JWTConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication is not configured for this environment",
        ) from exc
    except JWTKeyFetchError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication keys are temporarily unavailable",
        ) from exc
    except JWTValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token",
        ) from exc
