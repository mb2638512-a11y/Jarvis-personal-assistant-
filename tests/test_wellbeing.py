from fastapi.testclient import TestClient

from jarvis_api.main import app
from jarvis_api import wellbeing


def test_wellbeing_routes_require_gateway_token(monkeypatch, tmp_path):
    monkeypatch.setattr(wellbeing, "_DB", tmp_path / "wellbeing.sqlite3")
    monkeypatch.setattr(wellbeing.settings, "remote_gateway_token", "test-secret")
    client = TestClient(app)

    response = client.get("/api/wellbeing/usage", params={"device_id": "phone"})
    assert response.status_code == 401

    response = client.post(
        "/api/wellbeing/usage",
        headers={"X-Jarvis-Gateway-Token": "test-secret"},
        json={
            "device_id": "phone",
            "platform": "android",
            "app_id": "com.example.video",
            "app_label": "Video",
            "foreground_seconds": 120,
        },
    )
    assert response.status_code == 200
    assert response.json()["accepted"] is True

    summary = client.get(
        "/api/wellbeing/usage",
        params={"device_id": "phone", "days": 7},
        headers={"X-Jarvis-Gateway-Token": "test-secret"},
    )
    assert summary.status_code == 200
    assert summary.json()["apps"][0]["app_label"] == "Video"
    assert summary.json()["apps"][0]["seconds"] == 120


def test_checkin_and_security_event_are_stored(monkeypatch, tmp_path):
    monkeypatch.setattr(wellbeing, "_DB", tmp_path / "wellbeing.sqlite3")
    monkeypatch.setattr(wellbeing.settings, "remote_gateway_token", "test-secret")
    client = TestClient(app)
    headers = {"X-Jarvis-Gateway-Token": "test-secret"}

    checkin = client.post(
        "/api/wellbeing/checkins",
        headers=headers,
        json={"device_id": "pc", "mood": 4, "energy": 3, "sleep_hours": 7.5},
    )
    assert checkin.status_code == 200
    assert checkin.json()["saved"] is True

    event = client.post(
        "/api/wellbeing/security-events",
        headers=headers,
        json={
            "device_id": "pc",
            "severity": "medium",
            "category": "update",
            "summary": "A security update was installed",
            "source": "windows-agent",
        },
    )
    assert event.status_code == 200

    events = client.get(
        "/api/wellbeing/security-events",
        params={"device_id": "pc"},
        headers=headers,
    )
    assert events.status_code == 200
    assert events.json()["events"][0]["category"] == "update"
