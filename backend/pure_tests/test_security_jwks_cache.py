from __future__ import annotations

import asyncio
import json
import time
from uuid import UUID

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.core.config import Settings
from app.core.security import JWTKeyFetchError, JWTValidationError, SupabaseJWTValidator


class MutableClock:
    def __init__(self) -> None:
        self.value = time.monotonic()

    def __call__(self) -> float:
        return self.value

    def advance(self, seconds: float) -> None:
        self.value += seconds


def _validator(clock: MutableClock | None = None) -> SupabaseJWTValidator:
    return SupabaseJWTValidator(
        Settings(
            database_url="postgresql+asyncpg://localhost/sa7tot",
            supabase_url="https://project.supabase.co",
        ),
        clock=clock or MutableClock(),
    )


def _key_pair(kid: str):
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(private_key.public_key()))
    public_jwk["kid"] = kid
    return private_key, public_jwk


def _token(private_key, kid: str) -> str:
    return jwt.encode(
        {
            "sub": "11111111-1111-1111-1111-111111111111",
            "aud": "authenticated",
            "iss": "https://project.supabase.co/auth/v1",
            "exp": int(time.time()) + 3600,
        },
        private_key,
        algorithm="RS256",
        headers={"kid": kid},
    )


@pytest.mark.asyncio
async def test_jwks_first_fetch_then_cache_hit(monkeypatch):
    validator = _validator()
    private_key, jwk = _key_pair("key-1")
    fetch_count = 0

    async def fetch():
        nonlocal fetch_count
        fetch_count += 1
        return {"keys": [jwk]}

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    token = _token(private_key, "key-1")

    assert (await validator.validate(token)).id == UUID("11111111-1111-1111-1111-111111111111")
    assert (await validator.validate(token)).id == UUID("11111111-1111-1111-1111-111111111111")
    assert fetch_count == 1


@pytest.mark.asyncio
async def test_jwks_ttl_expiry_refetches(monkeypatch):
    clock = MutableClock()
    validator = _validator(clock)
    private_key, jwk = _key_pair("key-1")
    fetch_count = 0

    async def fetch():
        nonlocal fetch_count
        fetch_count += 1
        return {"keys": [jwk]}

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    token = _token(private_key, "key-1")
    await validator.validate(token)
    clock.advance(601)
    await validator.validate(token)
    assert fetch_count == 2


@pytest.mark.asyncio
async def test_unknown_kid_refreshes_once_and_can_use_new_key(monkeypatch):
    validator = _validator()
    first_private, first_jwk = _key_pair("key-1")
    second_private, second_jwk = _key_pair("key-2")
    fetch_count = 0
    current_keys = [first_jwk]

    async def fetch():
        nonlocal fetch_count
        fetch_count += 1
        return {"keys": current_keys}

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    await validator.validate(_token(first_private, "key-1"))
    current_keys[:] = [second_jwk]
    await validator.validate(_token(second_private, "key-2"))
    assert fetch_count == 2


@pytest.mark.asyncio
async def test_concurrent_first_validation_has_one_jwks_fetch(monkeypatch):
    validator = _validator()
    private_key, jwk = _key_pair("key-1")
    fetch_count = 0

    async def fetch():
        nonlocal fetch_count
        fetch_count += 1
        await asyncio.sleep(0.01)
        return {"keys": [jwk]}

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    token = _token(private_key, "key-1")
    users = await asyncio.gather(*(validator.validate(token) for _ in range(12)))
    assert len(users) == 12
    assert fetch_count == 1


@pytest.mark.asyncio
async def test_concurrent_unknown_kid_has_one_refresh(monkeypatch):
    validator = _validator()
    first_private, first_jwk = _key_pair("key-1")
    second_private, second_jwk = _key_pair("key-2")
    fetch_count = 0
    current_keys = [first_jwk]

    async def fetch():
        nonlocal fetch_count
        fetch_count += 1
        await asyncio.sleep(0.01)
        return {"keys": current_keys}

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    await validator.validate(_token(first_private, "key-1"))
    current_keys[:] = [second_jwk]
    await asyncio.gather(*(validator.validate(_token(second_private, "key-2")) for _ in range(12)))
    assert fetch_count == 2


@pytest.mark.asyncio
async def test_unknown_kid_and_invalid_signature_are_rejected(monkeypatch):
    validator = _validator()
    private_key, jwk = _key_pair("key-1")
    other_private, _ = _key_pair("other")

    async def fetch():
        return {"keys": [jwk]}

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    with pytest.raises(JWTValidationError, match="No matching"):
        await validator.validate(_token(private_key, "missing"))
    with pytest.raises(JWTValidationError):
        await validator.validate(_token(other_private, "key-1"))


@pytest.mark.asyncio
@pytest.mark.parametrize("claim", ["iss", "aud", "exp"])
async def test_jwt_claim_validation_remains_strict(monkeypatch, claim):
    validator = _validator()
    private_key, jwk = _key_pair("key-1")

    async def fetch():
        return {"keys": [jwk]}

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    payload = {
        "sub": "11111111-1111-1111-1111-111111111111",
        "aud": "authenticated",
        "iss": "https://project.supabase.co/auth/v1",
        "exp": int(time.time()) + 3600,
    }
    payload[claim] = {
        "iss": "https://other.example.com",
        "aud": "other-audience",
        "exp": int(time.time()) - 1,
    }[claim]
    token = jwt.encode(payload, private_key, algorithm="RS256", headers={"kid": "key-1"})
    with pytest.raises(JWTValidationError):
        await validator.validate(token)


@pytest.mark.asyncio
async def test_jwks_network_failure_does_not_bypass_auth(monkeypatch):
    validator = _validator()

    async def fetch():
        raise JWTKeyFetchError("network unavailable")

    monkeypatch.setattr(validator, "_fetch_jwks", fetch)
    private_key, _ = _key_pair("key-1")
    with pytest.raises(JWTKeyFetchError, match="network unavailable"):
        await validator.validate(_token(private_key, "key-1"))
