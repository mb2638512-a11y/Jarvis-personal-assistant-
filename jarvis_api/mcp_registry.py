"""User-managed MCP server registry and tool discovery.

Only HTTPS endpoints and loopback HTTP are accepted. Server credentials are
intentionally not collected by this first-party UI; use a private authenticated
gateway or a local MCP proxy until per-user secret storage is implemented.
"""
from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, field_validator

router = APIRouter(prefix="/api/mcp", tags=["MCP tools"])
DB_PATH = Path(__file__).resolve().parent.parent / "data" / "mcp_servers.sqlite3"
NAME_RE = re.compile(r"^[^\\x00-\\x1f]{1,80}$")


class ServerInput(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    url: str = Field(min_length=8, max_length=2048)

    @field_validator("name")
    @classmethod
    def valid_name(cls, value: str) -> str:
        value = value.strip()
        if not NAME_RE.match(value):
            raise ValueError("Enter a server name (1–80 characters).")
        return value

    @field_validator("url")
    @classmethod
    def safe_url(cls, value: str) -> str:
        value = value.strip().rstrip("/")
        parsed = urlparse(value)
        loopback = parsed.hostname in {"localhost", "127.0.0.1", "::1"}
        if parsed.scheme != "https" and not (parsed.scheme == "http" and loopback):
            raise ValueError("MCP servers must use HTTPS. HTTP is allowed only for localhost.")
        if not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
            raise ValueError("Enter a valid MCP URL without embedded credentials or fragments.")
        return value


def _db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS mcp_servers (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, url TEXT NOT NULL,
        tools_json TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL DEFAULT 'saved',
        error TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )""")
    db.commit()
    return db


def _decode_response(response: httpx.Response) -> dict[str, Any]:
    try:
        data = response.json()
        if isinstance(data, dict):
            return data
    except (ValueError, json.JSONDecodeError):
        pass
    # Support the JSON data frames used by MCP streamable HTTP/SSE responses.
    for line in response.text.splitlines():
        if line.startswith("data:"):
            try:
                data = json.loads(line[5:].strip())
                if isinstance(data, dict):
                    return data
            except json.JSONDecodeError:
                continue
    raise ValueError("MCP server did not return a readable JSON-RPC response.")


async def discover_tools(url: str) -> list[dict[str, Any]]:
    headers = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=12, follow_redirects=False) as client:
        init = await client.post(url, headers=headers, json={
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"protocolVersion": "2025-03-26",
                       "capabilities": {}, "clientInfo": {"name": "Jarvis", "version": "0.1.0"}},
        })
        init.raise_for_status()
        result = _decode_response(init)
        if "error" in result:
            raise ValueError(str(result["error"].get("message", "MCP initialization failed")))
        session_id = init.headers.get("Mcp-Session-Id")
        request_headers = dict(headers)
        if session_id:
            request_headers["Mcp-Session-Id"] = session_id
        await client.post(url, headers=request_headers, json={
            "jsonrpc": "2.0", "method": "notifications/initialized"
        })
        listed = await client.post(url, headers=request_headers, json={
            "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}
        })
        listed.raise_for_status()
        payload = _decode_response(listed)
        if "error" in payload:
            raise ValueError(str(payload["error"].get("message", "Tool discovery failed")))
        tools = payload.get("result", {}).get("tools", [])
        if not isinstance(tools, list):
            raise ValueError("MCP tools/list returned an invalid tools collection.")
        return [{
            "name": str(tool.get("name", ""))[:120],
            "description": str(tool.get("description", ""))[:500],
            "input_schema": tool.get("inputSchema", {}),
        } for tool in tools if isinstance(tool, dict) and tool.get("name")]


@router.get("/servers")
async def list_servers() -> dict[str, Any]:
    with _db() as db:
        rows = db.execute("SELECT * FROM mcp_servers ORDER BY created_at DESC").fetchall()
    servers = []
    for row in rows:
        servers.append({
            "id": row["id"], "name": row["name"], "url": row["url"],
            "status": row["status"], "error": row["error"],
            "tools": json.loads(row["tools_json"]),
        })
    return {"servers": servers, "count": len(servers)}


@router.post("/servers")
async def add_server(body: ServerInput) -> dict[str, Any]:
    import uuid
    try:
        tools = await discover_tools(body.url)
        status, error = "connected", ""
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
        tools, status, error = [], "saved_unverified", str(exc)[:300]
    server_id = uuid.uuid4().hex
    with _db() as db:
        db.execute(
            "INSERT INTO mcp_servers (id,name,url,tools_json,status,error) VALUES (?,?,?,?,?,?)",
            (server_id, body.name, body.url, json.dumps(tools), status, error),
        )
        db.commit()
    return {"id": server_id, "name": body.name, "url": body.url,
            "status": status, "error": error, "tools": tools}


@router.post("/servers/{server_id}/refresh")
async def refresh_server(server_id: str) -> dict[str, Any]:
    with _db() as db:
        row = db.execute("SELECT * FROM mcp_servers WHERE id=?", (server_id,)).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="MCP server not found.")
    try:
        tools = await discover_tools(row["url"])
        status, error = "connected", ""
    except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
        tools, status, error = [], "saved_unverified", str(exc)[:300]
    with _db() as db:
        db.execute("UPDATE mcp_servers SET tools_json=?,status=?,error=? WHERE id=?",
                   (json.dumps(tools), status, error, server_id))
        db.commit()
    return {"id": server_id, "name": row["name"], "url": row["url"],
            "status": status, "error": error, "tools": tools}


@router.delete("/servers/{server_id}")
async def delete_server(server_id: str) -> dict[str, bool]:
    with _db() as db:
        cursor = db.execute("DELETE FROM mcp_servers WHERE id=?", (server_id,))
        db.commit()
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="MCP server not found.")
    return {"deleted": True}
