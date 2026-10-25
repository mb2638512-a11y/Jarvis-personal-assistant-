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
