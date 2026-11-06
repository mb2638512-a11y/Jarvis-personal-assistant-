from fastapi.testclient import TestClient

from jarvis_api import mcp_registry
from jarvis_api.main import app

client = TestClient(app)


def test_add_mcp_server_discovers_and_lists_tools(monkeypatch, tmp_path):
    monkeypatch.setattr(mcp_registry, "DB_PATH", tmp_path / "mcp.sqlite3")

    async def fake_discover(url):
        assert url == "https://mcp.example.com/mcp"
        return [{"name": "search_docs", "description": "Search docs", "input_schema": {}}]

    monkeypatch.setattr(mcp_registry, "discover_tools", fake_discover)
    response = client.post("/api/mcp/servers", json={
        "name": "Docs", "url": "https://mcp.example.com/mcp"
    })
    assert response.status_code == 200
    assert response.json()["status"] == "connected"
    assert response.json()["tools"][0]["name"] == "search_docs"

    listed = client.get("/api/mcp/servers")
    assert listed.status_code == 200
    assert listed.json()["count"] == 1
    assert listed.json()["servers"][0]["name"] == "Docs"


def test_mcp_server_rejects_plain_http_remote_urls():
    response = client.post("/api/mcp/servers", json={
        "name": "Unsafe", "url": "http://example.com/mcp"
    })
    assert response.status_code == 422


def test_mcp_server_can_be_removed(monkeypatch, tmp_path):
    monkeypatch.setattr(mcp_registry, "DB_PATH", tmp_path / "mcp.sqlite3")

    async def fake_discover(url):
        return []

    monkeypatch.setattr(mcp_registry, "discover_tools", fake_discover)
    added = client.post("/api/mcp/servers", json={
        "name": "Local tools", "url": "http://localhost:9000/mcp"
    }).json()
    removed = client.delete(f"/api/mcp/servers/{added['id']}")
    assert removed.status_code == 200
    assert removed.json()["deleted"] is True
    assert client.get("/api/mcp/servers").json()["count"] == 0
