import httpx
from fastapi.testclient import TestClient

from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)
TOKEN = "test-gateway-token"


def configure(monkeypatch):
    monkeypatch.setattr(settings, "postiz_api_key", "test-postiz-key")
    monkeypatch.setattr(settings, "postiz_gateway_token", TOKEN)
    monkeypatch.setattr(settings, "postiz_base_url", "https://postiz.example/api/public/v1")


def test_postiz_status_never_exposes_secrets(monkeypatch):
    configure(monkeypatch)
    response = client.get("/api/postiz/status")
    assert response.status_code == 200
    assert response.json()["configured"] is True
    assert "test-postiz-key" not in response.text
    assert "test-gateway-token" not in response.text
    assert response.json()["live_connection_verified"] is False


def test_postiz_actions_require_gateway_token(monkeypatch):
    configure(monkeypatch)
    assert client.get("/api/postiz/channels").status_code == 401


def test_postiz_actions_disabled_without_gateway_token(monkeypatch):
    configure(monkeypatch)
    monkeypatch.setattr(settings, "postiz_gateway_token", "")
    response = client.get("/api/postiz/channels", headers={"X-Jarvis-Postiz-Token": TOKEN})
    assert response.status_code == 503


def test_postiz_not_configured(monkeypatch):
    monkeypatch.setattr(settings, "postiz_api_key", "")
    monkeypatch.setattr(settings, "postiz_gateway_token", TOKEN)
    response = client.get("/api/postiz/channels", headers={"X-Jarvis-Postiz-Token": TOKEN})
    assert response.status_code == 503


def test_schedule_requires_date(monkeypatch):
    configure(monkeypatch)
    payload = {"type": "schedule", "posts": [{
        "integration": {"id": "channel-1"},
        "value": [{"content": "Hello from Jarvis"}],
        "settings": {"__type": "x"}
    }]}
    response = client.post("/api/postiz/posts", json=payload, headers={"X-Jarvis-Postiz-Token": TOKEN})
    assert response.status_code == 422
    assert "date is required" in response.json()["detail"]


def test_postiz_rejects_http_public_base_url(monkeypatch):
    configure(monkeypatch)
    monkeypatch.setattr(settings, "postiz_base_url", "http://postiz.example/api/public/v1")
    response = client.get("/api/postiz/channels", headers={"X-Jarvis-Postiz-Token": TOKEN})
    assert response.status_code == 500
    assert "HTTPS" in response.json()["detail"]


def test_channels_calls_postiz_with_raw_authorization_header(monkeypatch):
    configure(monkeypatch)
    observed = {}

    async def fake_request(self, method, url, **kwargs):
        observed["method"] = method
        observed["url"] = url
        observed["authorization"] = kwargs["headers"]["Authorization"]
        request = httpx.Request("GET", url)
        return httpx.Response(200, request=request, json=[{"id": "channel-1", "name": "Test"}])

    monkeypatch.setattr(httpx.AsyncClient, "request", fake_request)
    response = client.get("/api/postiz/channels", headers={"X-Jarvis-Postiz-Token": TOKEN})
    assert response.status_code == 200
    assert response.json()[0]["id"] == "channel-1"
    assert observed == {
        "method": "GET",
        "url": "https://postiz.example/api/public/v1/integrations",
        "authorization": "test-postiz-key",
    }


def test_postiz_upstream_error_body_is_not_leaked(monkeypatch):
    configure(monkeypatch)

    async def fake_request(self, method, url, **kwargs):
        request = httpx.Request(method, url)
        response = httpx.Response(429, request=request, text="secret upstream diagnostic")
        raise httpx.HTTPStatusError("failed", request=request, response=response)

    monkeypatch.setattr(httpx.AsyncClient, "request", fake_request)
    response = client.get("/api/postiz/channels", headers={"X-Jarvis-Postiz-Token": TOKEN})
    assert response.status_code == 502
    assert response.json()["detail"] == "Postiz returned HTTP 429."
    assert "secret upstream" not in response.text
