from fastapi.testclient import TestClient

from jarvis_api import artemis
from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)
TOKEN = "artemis-test-token"


def setup(monkeypatch):
    monkeypatch.setattr(settings, "artemis_base_url", "https://artemis.internal")
    monkeypatch.setattr(settings, "artemis_gateway_token", TOKEN)
    monkeypatch.setattr(settings, "remote_gateway_token", TOKEN)


def test_artemis_status_is_not_configured_without_private_host(monkeypatch):
    monkeypatch.setattr(settings, "artemis_base_url", "")
    monkeypatch.setattr(settings, "artemis_gateway_token", "")
    monkeypatch.setattr(settings, "remote_gateway_token", TOKEN)
    response = client.get("/api/artemis/status", headers={"X-Jarvis-Remote-Token": TOKEN})
    assert response.status_code == 200
    assert response.json()["live_connected"] is False


def test_artemis_task_requires_jarvis_auth_and_user_confirmation(monkeypatch):
    setup(monkeypatch)
    body = {"goal": "Open Android Settings", "device_serial": "emulator-5554", "user_confirmed": True}
    assert client.post("/api/artemis/tasks", json=body).status_code == 401
    assert client.post("/api/artemis/tasks", headers={"X-Jarvis-Remote-Token": TOKEN}, json={**body, "user_confirmed": False}).status_code == 403


def test_artemis_rejects_non_https_public_host(monkeypatch):
    setup(monkeypatch)
    monkeypatch.setattr(settings, "artemis_base_url", "http://public.example:8000")
    response = client.get("/api/artemis/status")
    assert response.status_code == 200
    assert response.json()["live_connected"] is False


def test_artemis_task_forwards_confirmed_goal(monkeypatch):
    setup(monkeypatch)
    async def fake_request(method, path, *, body=None):
        assert method == "POST"
        assert path == "/api/run"
        assert body["goal"] == "Open Android Settings"
        assert body["device_serial"] == "emulator-5554"
        return {"status": "queued", "tasks": [{"task_id": body["session_id"], "status": "queued"}]}
    monkeypatch.setattr(artemis, "_request", fake_request)
    response = client.post("/api/artemis/tasks", headers={"X-Jarvis-Artemis-Token": TOKEN}, json={
        "goal": "Open Android Settings", "device_serial": "emulator-5554", "user_confirmed": True
    })
    assert response.status_code == 200
    assert response.json()["status"] == "queued"
    assert response.json()["upstream"] == "artemis"
