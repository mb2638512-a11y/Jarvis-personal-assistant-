from fastapi.testclient import TestClient

import jarvis_api.remote_control as remote
from jarvis_api.config import settings
from jarvis_api.main import app

client = TestClient(app)
TOKEN = "remote-test-token"
HEADERS = {"X-Jarvis-Remote-Token": TOKEN, "X-Jarvis-Agent-Id": "mustafa-pc"}


def setup(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "remote_gateway_token", TOKEN)
    monkeypatch.setattr(settings, "remote_task_ttl_seconds", 300)
    monkeypatch.setattr(remote, "DB_PATH", tmp_path / "remote.sqlite3")


def test_remote_control_is_disabled_without_token(monkeypatch):
    monkeypatch.setattr(settings, "remote_gateway_token", "")
    response = client.get("/api/remote/status")
    assert response.status_code == 503


def test_remote_control_requires_valid_token(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    assert client.get("/api/remote/status").status_code == 401
    assert client.get("/api/remote/status", headers=HEADERS).status_code == 200


def test_windows_task_can_be_queued_and_claimed_by_registered_agent(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    registered = client.post("/api/remote/agents/register", headers=HEADERS, json={
        "id": "mustafa-pc", "platform": "windows", "capabilities": ["open_url", "screenshot"]
    })
    assert registered.status_code == 200
    queued = client.post("/api/remote/tasks", headers=HEADERS, json={
        "target_platform": "windows", "target_agent": "mustafa-pc",
        "kind": "open_url", "payload": {"url": "https://example.com"}
    })
    assert queued.status_code == 200
    task_id = queued.json()["task_id"]
    polled = client.get("/api/remote/agents/mustafa-pc/tasks", headers=HEADERS)
    assert polled.status_code == 200
    assert polled.json()["tasks"][0]["id"] == task_id
    wrong_agent = client.post(f"/api/remote/tasks/{task_id}/result", headers={
        "X-Jarvis-Remote-Token": TOKEN, "X-Jarvis-Agent-Id": "other-pc"
    }, json={"status": "succeeded", "result": {"opened": True}})
    assert wrong_agent.status_code == 403
    done = client.post(f"/api/remote/tasks/{task_id}/result", headers=HEADERS, json={
        "status": "succeeded", "result": {"opened": True}
    })
    assert done.status_code == 200


def test_remote_control_rejects_shell_and_unconfirmed_typing(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    shell = client.post("/api/remote/tasks", headers=HEADERS, json={
        "target_platform": "windows", "kind": "open_url",
        "payload": {"url": "https://example.com", "command": "format c:"}
    })
    assert shell.status_code == 422
    typing = client.post("/api/remote/tasks", headers=HEADERS, json={
        "target_platform": "windows", "kind": "type_text", "payload": {"text": "hello"}
    })
    assert typing.status_code == 403


def test_remote_control_requires_https_urls(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    response = client.post("/api/remote/tasks", headers=HEADERS, json={
        "target_platform": "windows", "kind": "open_url", "payload": {"url": "http://example.com"}
    })
    assert response.status_code == 422

def test_task_status_reports_real_agent_result(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    registered = client.post("/api/remote/agents/register", headers=HEADERS, json={
        "id": "mustafa-pc", "platform": "windows", "capabilities": ["get_status"]
    })
    assert registered.status_code == 200
    queued = client.post("/api/remote/tasks", headers=HEADERS, json={
        "target_platform": "windows", "target_agent": "mustafa-pc", "kind": "get_status"
    })
    task_id = queued.json()["task_id"]
    assert client.get(f"/api/remote/tasks/{task_id}", headers=HEADERS).json()["status"] == "queued"
    client.get("/api/remote/agents/mustafa-pc/tasks", headers=HEADERS)
    done = client.post(f"/api/remote/tasks/{task_id}/result", headers=HEADERS, json={
        "status": "succeeded", "result": {"hostname": "mustafa-pc"}
    })
    assert done.status_code == 200
    status = client.get(f"/api/remote/tasks/{task_id}", headers=HEADERS)
    assert status.status_code == 200
    assert status.json()["status"] == "succeeded"
    assert status.json()["result"]["hostname"] == "mustafa-pc"


def test_task_status_requires_auth_and_valid_id(monkeypatch, tmp_path):
    setup(monkeypatch, tmp_path)
    assert client.get("/api/remote/tasks/not-a-uuid", headers=HEADERS).status_code == 422
    assert client.get("/api/remote/tasks/00000000-0000-0000-0000-000000000000", headers=HEADERS).status_code == 404
    assert client.get("/api/remote/tasks/00000000-0000-0000-0000-000000000000").status_code == 401

