from fastapi.testclient import TestClient

from jarvis_api import device_pairing as pairing
from jarvis_api.config import settings
from jarvis_api.main import app
import jarvis_api.remote_control as remote

client = TestClient(app, base_url="https://testserver")
TOKEN = "pairing-test-admin-token"
ADMIN = {"X-Jarvis-Remote-Token": TOKEN}


def setup(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "remote_gateway_token", TOKEN)
    monkeypatch.setattr(pairing, "DB_PATH", tmp_path / "pairing.sqlite3")


def request_pairing():
    challenge = client.post("/api/pairing/challenge", headers=ADMIN).json()
    payload = {
        "challenge_id": challenge["challenge_id"],
        "code": challenge["code"],
        "device_label": "Mustafa Android",
        "platform": "android",
    }
    request = client.post("/api/pairing/redeem", json=payload)
    assert request.status_code == 200
    assert request.json()["pending_approval"] is True
    request_id = request.json()["request_id"]
    status_body = {**payload, "request_id": request_id}
    return challenge, payload, request_id, status_body


def approve_pairing(challenge, payload, request_id):
    approved = client.post(f"/api/pairing/pending/{request_id}/approve", headers=ADMIN)
    assert approved.status_code == 200
    completed = client.post("/api/pairing/complete", json={
        "challenge_id": challenge["challenge_id"],
        "request_id": request_id,
        "code": payload["code"],
    })
    assert completed.status_code == 200
    return completed.json()


def test_qr_pairing_requires_explicit_pc_approval_and_issues_device_credential(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    challenge, payload, request_id, status_body = request_pairing()
    assert challenge["expires_in_seconds"] == 180
    assert "device_token" not in challenge["pairing_uri"]

    pending_status = client.post("/api/pairing/pending/status", json=status_body)
    assert pending_status.status_code == 200
    assert pending_status.json()["status"] == "pending"

    before_approval = client.post("/api/pairing/complete", json=status_body)
    assert before_approval.status_code == 403

    token_data = approve_pairing(challenge, payload, request_id)
    token = token_data["device_token"]
    assert token

    verified = client.post("/api/pairing/verify", headers={"X-Jarvis-Device-Token": token})
    assert verified.status_code == 200
    assert verified.json()["device"]["label"] == "Mustafa Android"

    replay = client.post("/api/pairing/redeem", json=payload)
    assert replay.status_code == 410


def test_wrong_code_attempts_are_persisted(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    challenge = client.post("/api/pairing/challenge", headers=ADMIN).json()
    payload = {
        "challenge_id": challenge["challenge_id"],
        "code": "000000",
        "device_label": "Phone",
        "platform": "android",
    }
    for _ in range(5):
        assert client.post("/api/pairing/redeem", json=payload).status_code == 401
    assert client.post("/api/pairing/redeem", json=payload).status_code == 410


def test_device_revocation_invalidates_credential(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    challenge, payload, request_id, _ = request_pairing()
    paired = approve_pairing(challenge, payload, request_id)
    revoked = client.delete(f"/api/pairing/devices/{paired['device_id']}", headers=ADMIN)
    assert revoked.status_code == 200
    assert client.post("/api/pairing/verify", headers={
        "X-Jarvis-Device-Token": paired["device_token"]
    }).status_code == 401


def test_pairing_admin_requires_gateway_token(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    assert client.post("/api/pairing/challenge").status_code == 401
    assert client.get("/api/pairing/devices").status_code == 401
    assert client.get("/api/pairing/pending").status_code == 401


def test_paired_device_credential_authenticates_shared_remote_api(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    monkeypatch.setattr(remote, "DB_PATH", tmp_path / "remote.sqlite3")
    monkeypatch.setattr(pairing, "DB_PATH", tmp_path / "device_pairing.sqlite3")
    challenge, payload, request_id, _ = request_pairing()
    paired = approve_pairing(challenge, payload, request_id)
    headers = {"X-Jarvis-Device-Token": paired["device_token"]}
    registered = client.post("/api/remote/agents/register", headers=headers, json={
        "id": "mustafa-phone", "platform": "android",
        "capabilities": ["get_status", "open_url"]
    })
    assert registered.status_code == 200
    assert registered.json()["registered"] is True
    status = client.get("/api/remote/status", headers=headers)
    assert status.status_code == 200
