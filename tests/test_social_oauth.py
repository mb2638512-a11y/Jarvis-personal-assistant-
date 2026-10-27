from fastapi.testclient import TestClient

from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)


def test_social_provider_catalog_is_oauth_first_and_has_more_than_30_entries(monkeypatch):
    monkeypatch.setattr(settings, "postiz_app_url", "")
    response = client.get("/api/social/providers")
    assert response.status_code == 200
    data = response.json()
    assert data["oauth_owner"] == "self-hosted-postiz"
    assert data["provider_count"] >= 30
    assert data["configured"] is False
    assert data["connect_url"] is None
    assert all("name" in item and "id" in item for item in data["providers"])


def test_connect_requires_workspace_url(monkeypatch):
    monkeypatch.setattr(settings, "postiz_app_url", "")
    response = client.get("/api/social/connect")
    assert response.status_code == 503


def test_connect_returns_workspace_integrations_route_without_secrets(monkeypatch):
    monkeypatch.setattr(settings, "postiz_app_url", "https://social.example")
    response = client.get("/api/social/connect")
    assert response.status_code == 200
    assert response.json()["url"] == "https://social.example/integrations"
    assert response.json()["method"] == "oauth"
    assert "token" not in response.text.lower()


def test_workspace_url_rejects_public_http(monkeypatch):
    monkeypatch.setattr(settings, "postiz_app_url", "http://social.example")
    response = client.get("/api/social/providers")
    assert response.status_code == 500
    assert "HTTPS" in response.json()["detail"]
