from fastapi.testclient import TestClient

from jarvis_api.config import settings
from jarvis_api.main import app


def test_chat_endpoint_rejects_unpaired_remote_client(monkeypatch):
    monkeypatch.setattr(settings, "remote_gateway_token", "chat-admin-token")
    client = TestClient(app, base_url="https://remote.test")
    response = client.post("/api/chat", json={"message": "Hello Jarvis"})
    assert response.status_code == 401


def test_chat_endpoint_accepts_pc_admin_auth_before_provider_check(monkeypatch):
    monkeypatch.setattr(settings, "remote_gateway_token", "chat-admin-token")
    client = TestClient(app, base_url="https://remote.test")
    response = client.post(
        "/api/chat",
        headers={"X-Jarvis-Remote-Token": "chat-admin-token"},
        json={"message": "Hello Jarvis"},
    )
    assert response.status_code == 503
    assert "provider" in response.json()["detail"].lower()
