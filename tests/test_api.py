import httpx
import pytest
from fastapi.testclient import TestClient

from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)


def test_health_is_process_health_only():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_status_does_not_claim_provider_is_connected(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "")
    monkeypatch.setattr(settings, "model", "")
    response = client.get("/status")
    assert response.status_code == 200
    assert response.json()["configured"] is False
    assert response.json()["ready"] is False


def test_chat_fails_clearly_without_provider_config(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "")
    monkeypatch.setattr(settings, "model", "")
    response = client.post("/api/chat", json={"message": "Hello Jarvis"})
    assert response.status_code == 503
    assert "not configured" in response.json()["detail"]


@pytest.mark.parametrize("message", ["", "   ", None, 123])
def test_chat_rejects_invalid_messages(message):
    response = client.post("/api/chat", json={"message": message})
    assert response.status_code == 422


def test_chat_rejects_messages_over_limit():
    response = client.post("/api/chat", json={"message": "x" * 12001})
    assert response.status_code == 422


def test_chat_rejects_non_https_provider_url(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "test-key")
    monkeypatch.setattr(settings, "model", "test-model")
    monkeypatch.setattr(settings, "base_url", "http://example.com/v1")
    response = client.post("/api/chat", json={"message": "hello"})
    assert response.status_code == 500
    assert "HTTPS" in response.json()["detail"]


def test_chat_maps_provider_timeout_to_gateway_timeout(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "test-key")
    monkeypatch.setattr(settings, "model", "test-model")
    monkeypatch.setattr(settings, "base_url", "https://provider.example/v1")

    async def timeout_request(*args, **kwargs):
        raise httpx.TimeoutException("private provider detail")

    monkeypatch.setattr(httpx.AsyncClient, "post", timeout_request)
    response = client.post("/api/chat", json={"message": "hello"})
    assert response.status_code == 504
    assert response.json()["detail"] == "AI provider request timed out."


def test_chat_does_not_leak_provider_error_body(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "test-key")
    monkeypatch.setattr(settings, "model", "test-model")
    monkeypatch.setattr(settings, "base_url", "https://provider.example/v1")

    request = httpx.Request("POST", "https://provider.example/v1/chat/completions")
    provider_response = httpx.Response(
        429,
        request=request,
        text="sensitive upstream body should not be returned",
    )

    async def failed_request(*args, **kwargs):
        raise httpx.HTTPStatusError(
            "upstream error", request=request, response=provider_response
        )

    monkeypatch.setattr(httpx.AsyncClient, "post", failed_request)
    response = client.post("/api/chat", json={"message": "hello"})
    assert response.status_code == 502
    assert response.json()["detail"] == "AI provider returned HTTP 429."
    assert "sensitive" not in response.text
