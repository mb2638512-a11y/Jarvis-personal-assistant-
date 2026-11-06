from fastapi.testclient import TestClient

import jarvis_api.device_pairing as pairing
from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app, base_url="https://testserver")
TOKEN = "pairing-test-admin-token"
ADMIN = {"X-Jarvis-Remote-Token": TOKEN}


def setup(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "remote_gateway_token", TOKEN)
    monkeypatch.setattr(pairing, "DB_PATH", tmp_path / "pairing.sqlite3")


def test_qr_challenge_redeem_and_device_verify(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    created = client.post("/api/pairing/challenge", headers=ADMIN)
    assert created.status_code == 200
    challenge = created.json()
    assert challenge["expires_in_seconds"] == 180
    assert "device_token" not in challenge["pairing_uri"]

    redeemed = client.post("/api/pairing/redeem", json={
        "challenge_id": challenge["challenge_id"],
        "code": challenge["code"],
        "device_label": "Mustafa Android",
        "platform": "android",
    })
    assert redeemed.status_code == 200
    token = redeemed.json()["device_token"]
    assert token

    verified = client.post("/api/pairing/verify", headers={"X-Jarvis-Device-Token": token})
    assert verified.status_code == 200
    assert verified.json()["device"]["label"] == "Mustafa Android"

    replay = client.post("/api/pairing/redeem", json={
        "challenge_id": challenge["challenge_id"],
        "code": challenge["code"],
        "device_label": "Replay",
    })
    assert replay.status_code == 410


def test_wrong_code_attempts_are_persisted(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    challenge = client.post("/api/pairing/challenge", headers=ADMIN).json()
    payload = {"challenge_id": challenge["challenge_id"], "code": "000000",
               "device_label": "Phone", "platform": "android"}
    for _ in range(5):
        assert client.post("/api/pairing/redeem", json=payload).status_code == 401
    assert client.post("/api/pairing/redeem", json=payload).status_code == 410


def test_device_revocation_invalidates_credential(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    challenge = client.post("/api/pairing/challenge", headers=ADMIN).json()
    paired = client.post("/api/pairing/redeem", json={
        "challenge_id": challenge["challenge_id"], "code": challenge["code"],
        "device_label": "Phone", "platform": "android"
    }).json()
    device_id = paired["device_id"]
    revoked = client.delete(f"/api/pairing/devices/{device_id}", headers=ADMIN)
    assert revoked.status_code == 200
    assert client.post("/api/pairing/verify", headers={
        "X-Jarvis-Device-Token": paired["device_token"]
    }).status_code == 401


def test_pairing_admin_requires_gateway_token(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    assert client.post("/api/pairing/challenge").status_code == 401
    assert client.get("/api/pairing/devices").status_code == 401
