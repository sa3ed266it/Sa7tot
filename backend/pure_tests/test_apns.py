import json

import httpx
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.core.config import Settings
from app.services.apns import APNsClient, PushPayload, classify_apns_response


def test_apns_response_classification():
    assert classify_apns_response(200) == "success"
    assert classify_apns_response(410, "Unregistered") == "permanent"
    assert classify_apns_response(400, "BadDeviceToken") == "permanent"
    assert classify_apns_response(403, "InvalidProviderToken") == "authentication"
    assert classify_apns_response(429, "TooManyRequests") == "transient"
    assert classify_apns_response(500, "InternalServerError") == "transient"
    assert classify_apns_response(400, "BadPayload") == "invalid"


def test_push_payload_is_generic_and_future_ready():
    payload = PushPayload(
        title="Test",
        body="Body",
        category="generic",
        deep_link="sa7tot://test",
        subscription_id="subscription-id",
    ).as_apns_payload()
    assert payload["aps"]["alert"] == {"title": "Test", "body": "Body"}
    assert payload["deep_link"] == "sa7tot://test"
    assert payload["subscription_id"] == "subscription-id"


@pytest.mark.asyncio
async def test_apns_client_uses_configured_environment_and_handles_success():
    private_key = ec.generate_private_key(ec.SECP256R1())
    private_key_material = private_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode()
    settings = Settings(
        apns_key_id="test-key",
        apns_team_id="test-team",
        apns_private_key=private_key_material,
        apns_environment="development",
    )

    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "api.sandbox.push.apple.com"
        assert request.headers["apns-topic"] == "com.saied.sa7tot"
        assert json.loads(request.content)["aps"]["alert"]["title"] == "Test"
        return httpx.Response(200, headers={"apns-id": "apns-test-id"}, request=request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler), http2=True) as http_client:
        result = await APNsClient(settings, http_client=http_client).send(
            "AB" * 32,
            PushPayload(title="Test", body="Body"),
        )

    assert result.apns_id == "apns-test-id"
