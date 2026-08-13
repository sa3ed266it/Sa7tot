from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import jwt

from app.core.config import Settings, get_settings


@dataclass(frozen=True)
class PushPayload:
    title: str
    body: str
    category: str | None = None
    deep_link: str | None = None
    subscription_id: str | None = None

    def as_apns_payload(self) -> dict[str, Any]:
        aps: dict[str, Any] = {"alert": {"title": self.title, "body": self.body}, "sound": "default"}
        if self.category:
            aps["category"] = self.category
        payload: dict[str, Any] = {"aps": aps}
        if self.deep_link:
            payload["deep_link"] = self.deep_link
        if self.subscription_id:
            payload["subscription_id"] = self.subscription_id
        return payload


class APNsError(RuntimeError):
    def __init__(self, kind: str, reason: str | None = None, status_code: int | None = None):
        self.kind = kind
        self.reason = reason
        self.status_code = status_code
        super().__init__(reason or kind)


@dataclass(frozen=True)
class APNsSendResult:
    apns_id: str | None


def classify_apns_response(status_code: int, reason: str | None = None) -> str:
    if status_code == 200:
        return "success"
    if status_code in {400, 410} and reason in {
        "BadDeviceToken",
        "DeviceTokenNotForTopic",
        "Unregistered",
    }:
        return "permanent"
    if status_code == 403 or reason in {"ExpiredProviderToken", "InvalidProviderToken", "MissingProviderToken"}:
        return "authentication"
    if status_code in {408, 429} or status_code >= 500:
        return "transient"
    return "invalid"


class APNsClient:
    """Minimal APNs HTTP/2 provider client.

    Credentials are loaded only from backend environment configuration. The
    client is intentionally independent from subscription scheduling and can be
    replaced by a queued worker in a later phase.
    """

    def __init__(self, settings: Settings | None = None, http_client: httpx.AsyncClient | None = None):
        self.settings = settings or get_settings()
        self.http_client = http_client
        self._owns_http_client = http_client is None
        self._cached_jwt: tuple[str, datetime] | None = None

    async def send(self, device_token: str, payload: PushPayload) -> APNsSendResult:
        key_id = self.settings.apns_key_id
        team_id = self.settings.apns_team_id
        private_key = self.settings.apns_private_key_material()
        if not key_id or not team_id or not private_key:
            raise APNsError("configuration", "APNs provider credentials are not configured")

        token = self._provider_token(key_id, team_id, private_key)
        client = self.http_client or httpx.AsyncClient(http2=True, timeout=10.0)
        try:
            response = await client.post(
                f"{self.settings.apns_base_url}/3/device/{device_token.lower()}",
                headers={
                    "authorization": f"bearer {token}",
                    "content-type": "application/json",
                    "apns-topic": self.settings.apns_bundle_id,
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                },
                content=json.dumps(payload.as_apns_payload()),
            )
        except httpx.HTTPError as exc:
            raise APNsError("transient", "APNs transport failed") from exc
        finally:
            if self._owns_http_client:
                await client.aclose()

        reason = None
        if response.content:
            try:
                reason = response.json().get("reason")
            except (ValueError, TypeError):
                reason = None
        kind = classify_apns_response(response.status_code, reason)
        if kind != "success":
            raise APNsError(kind, reason, response.status_code)
        return APNsSendResult(apns_id=response.headers.get("apns-id"))

    def _provider_token(self, key_id: str, team_id: str, private_key: str) -> str:
        now = datetime.now(UTC)
        if self._cached_jwt and self._cached_jwt[1] > now + timedelta(minutes=1):
            return self._cached_jwt[0]
        encoded = jwt.encode(
            {"iss": team_id, "iat": int(now.timestamp())},
            private_key,
            algorithm="ES256",
            headers={"kid": key_id},
        )
        self._cached_jwt = (encoded, now + timedelta(minutes=45))
        return encoded
