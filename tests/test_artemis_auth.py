from fastapi.testclient import TestClient

from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)


def test_artemis_bridge_requires_paired_device_auth(monkeypatch):
    monkeypatch.setattr(settings, "remote_gateway_token", "host-admin-token")
    response = client.get("/api/artemis/status")
    assert response.status_code == 401
