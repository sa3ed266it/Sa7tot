from __future__ import annotations

import json
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
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def validate(self, token: str) -> CurrentUser:
        if not self.settings.supabase_jwks_url or not self.settings.supabase_issuer:
            raise JWTConfigurationError("SUPABASE_URL is not configured for authenticated routes")

        try:
            header = jwt.get_unverified_header(token)
            unverified_claims = jwt.decode(token, options={"verify_signature": False})
            jwks = await self._fetch_jwks()
            jwk = next(
                (key for key in jwks.get("keys", []) if key.get("kid") == header.get("kid")),
                None,
            )
            if jwk is None:
                raise JWTValidationError("No matching Supabase signing key was found")

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

    async def _fetch_jwks(self) -> dict[str, object]:
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                response = await client.get(self.settings.supabase_jwks_url)
                response.raise_for_status()
                return response.json()
        except httpx.HTTPError as exc:
            raise JWTKeyFetchError("Supabase signing keys could not be loaded") from exc


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
