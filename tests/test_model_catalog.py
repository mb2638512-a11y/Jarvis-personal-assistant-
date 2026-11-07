from fastapi.testclient import TestClient

from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)


def test_shared_model_catalog_never_exposes_provider_key(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "do-not-return-this-secret")
    monkeypatch.setattr(settings, "base_url", "https://api.example.test/v1")
    monkeypatch.setattr(settings, "model", "gpt-example")
    response = client.get("/api/models/catalog")
    assert response.status_code == 200
    data = response.json()
    assert data["host"] == "pc"
    assert data["active_model"] == "gpt-example"
    assert data["credentials_exposed"] is False
    assert "do-not-return-this-secret" not in response.text


def test_model_health_only_reports_credential_presence(monkeypatch):
    monkeypatch.setattr(settings, "api_key", "private")
    monkeypatch.setattr(settings, "model", "model-a")
    response = client.get("/api/models/health")
    assert response.status_code == 200
    assert response.json()["credential_present"] is True
    assert response.json()["credential_exposed"] is False
    assert "private" not in response.text
