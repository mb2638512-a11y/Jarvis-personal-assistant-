from fastapi.testclient import TestClient

from jarvis_api.main import app
from jarvis_api import wellbeing


def test_wellbeing_routes_require_gateway_token(monkeypatch, tmp_path):
    monkeypatch.setattr(wellbeing, "_DB", tmp_path / "wellbeing.sqlite3")
    monkeypatch.setattr(wellbeing.settings, "remote_gateway_token", "test-secret")
    client = TestClient(app)

    response = client.get("/api/wellbeing/usage", params={"device_id": "phone"})
    assert response.status_code == 401

    wrong_token = client.get(
        "/api/wellbeing/usage",
        params={"device_id": "phone"},
        headers={"X-Jarvis-Gateway-Token": "wrong-secret"},
    )
    assert wrong_token.status_code == 401

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


def test_device_metrics_and_security_snapshots(monkeypatch, tmp_path):
    monkeypatch.setattr(wellbeing, "_DB", tmp_path / "wellbeing.sqlite3")
    monkeypatch.setattr(wellbeing.settings, "remote_gateway_token", "test-secret")
    client = TestClient(app)
    headers = {"X-Jarvis-Gateway-Token": "test-secret"}

    metrics = client.post("/api/wellbeing/device-metrics", headers=headers, json={
        "device_id": "pc", "platform": "windows", "cpu_percent": 17.5,
        "memory_percent": 61, "memory_used_bytes": 600, "memory_total_bytes": 1000,
        "disk_percent": 80, "disk_free_bytes": 200, "top_processes": [],
    })
    assert metrics.status_code == 200
    latest = client.get("/api/wellbeing/device-metrics", params={"device_id": "pc", "limit": 1}, headers=headers)
    assert latest.status_code == 200
    assert latest.json()["latest"]["cpu_percent"] == 17.5

    security = client.post("/api/wellbeing/device-security", headers=headers, json={
        "device_id": "pc", "platform": "windows", "firewall_enabled": True,
        "antivirus_enabled": True, "realtime_protection": True, "risk_level": "low",
        "findings": [],
    })
    assert security.status_code == 200
    posture = client.get("/api/wellbeing/device-security", params={"device_id": "pc"}, headers=headers)
    assert posture.status_code == 200
    assert posture.json()["latest"]["firewall_enabled"] is True


def test_device_snapshots_require_gateway_token(monkeypatch, tmp_path):
    monkeypatch.setattr(wellbeing, "_DB", tmp_path / "wellbeing.sqlite3")
    monkeypatch.setattr(wellbeing.settings, "remote_gateway_token", "test-secret")
    client = TestClient(app)
    response = client.post("/api/wellbeing/device-metrics", json={
        "device_id": "pc", "platform": "windows", "cpu_percent": 10,
    })
    assert response.status_code == 401
