from fastapi.testclient import TestClient

from jarvis_api.main import app

client = TestClient(app)


def test_integrations_status_has_one_shared_backend_and_three_sources():
    response = client.get("/api/integrations/status")
    assert response.status_code == 200
    data = response.json()
    assert data["shared_backend"] is True
    assert data["client_platforms"] == ["windows", "android"]
    assert {item["id"] for item in data["integrations"]} == {"atticus", "artemis", "postiz"}
    assert all(item["source_present"] for item in data["integrations"])


def test_status_does_not_claim_unverified_live_connections():
    data = client.get("/api/integrations/status").json()
    assert data["production_ready"] is False
    assert all(item["live_connected"] is False for item in data["integrations"])
    assert all(item["ready"] is False for item in data["integrations"])
