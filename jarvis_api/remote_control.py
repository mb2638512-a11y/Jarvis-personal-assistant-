"""Authenticated, typed cross-device task broker.

The broker never accepts shell commands. Real OS execution must be performed by
an explicitly paired Windows or Android agent that validates each task again.
"""
from __future__ import annotations

import json
import re
import secrets
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Literal

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field, HttpUrl, field_validator

from jarvis_api.config import settings

router = APIRouter(prefix="/api/remote", tags=["Cross-device remote control"])
DB_PATH = Path(__file__).resolve().parent.parent / "data" / "remote_tasks.sqlite3"
DEVICE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$")
ALLOWED_APPS = {"notepad", "calculator", "explorer", "chrome", "edge", "firefox", "settings"}
ALLOWED_KEYS = {"ENTER", "ESC", "TAB", "CTRL+C", "CTRL+V", "CTRL+S", "ALT+TAB", "WIN"}
TASK_TYPES = {"open_url", "open_app", "type_text", "press_key", "screenshot", "get_status"}


@contextmanager
def _db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS agents (
        id TEXT PRIMARY KEY, platform TEXT NOT NULL, capabilities TEXT NOT NULL,
        last_seen REAL NOT NULL, status TEXT NOT NULL DEFAULT 'online'
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY, target_platform TEXT NOT NULL, target_agent TEXT,
        kind TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL,
        created_at REAL NOT NULL, expires_at REAL NOT NULL,
        result TEXT, error TEXT
    )""")
    db.commit()
    try:
        yield db
        db.commit()
    finally:
        db.close()


def _auth(token: str | None) -> None:
    expected = settings.remote_gateway_token.strip()
    if not expected:
        raise HTTPException(status_code=503, detail="Remote control is disabled until JARVIS_REMOTE_GATEWAY_TOKEN is configured.")
    if not token or not secrets.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail="Valid Jarvis remote gateway token required.")


def _valid_device_id(value: str) -> str:
    if not DEVICE_RE.fullmatch(value):
        raise HTTPException(status_code=422, detail="Invalid device id.")
    return value


class AgentRegistration(BaseModel):
    id: str = Field(min_length=2, max_length=64)
    platform: Literal["windows", "android"]
    capabilities: list[str] = Field(default_factory=list, max_length=40)

    @field_validator("id")
    @classmethod
    def validate_id(cls, value: str) -> str:
        return _valid_device_id(value)


class RemoteTaskRequest(BaseModel):
    target_platform: Literal["windows", "android"]
    target_agent: str | None = Field(default=None, min_length=2, max_length=64)
    kind: Literal["open_url", "open_app", "type_text", "press_key", "screenshot", "get_status"]
    payload: dict[str, Any] = Field(default_factory=dict)
    user_confirmed: bool = False

    @field_validator("target_agent")
    @classmethod
    def validate_target(cls, value: str | None) -> str | None:
        return _valid_device_id(value) if value else value

    @field_validator("payload")
    @classmethod
    def validate_payload(cls, value: dict[str, Any]) -> dict[str, Any]:
        # Strictly typed actions only: never accept arbitrary shell/PowerShell.
        if "command" in value or "shell" in value or "script" in value:
            raise ValueError("Shell commands and scripts are not supported.")
        return value


def _validate_action(body: RemoteTaskRequest) -> None:
    payload = body.payload
    if body.kind == "open_url":
        url = payload.get("url")
        if not isinstance(url, str) or not url.startswith("https://") or len(url) > 2048:
            raise HTTPException(status_code=422, detail="open_url requires an HTTPS url.")
    elif body.kind == "open_app":
        app = payload.get("app")
        if not isinstance(app, str) or app.lower() not in ALLOWED_APPS:
            raise HTTPException(status_code=422, detail="App is not in the safe application allowlist.")
    elif body.kind == "type_text":
        text = payload.get("text")
        if not body.user_confirmed:
            raise HTTPException(status_code=403, detail="Typing into another device requires explicit user confirmation.")
        if not isinstance(text, str) or not text or len(text) > 4000:
            raise HTTPException(status_code=422, detail="type_text requires 1-4000 characters.")
    elif body.kind == "press_key":
        key = payload.get("key")
        if not body.user_confirmed:
            raise HTTPException(status_code=403, detail="Remote key presses require explicit user confirmation.")
        if not isinstance(key, str) or key.upper() not in ALLOWED_KEYS:
            raise HTTPException(status_code=422, detail="Key is not in the safe key allowlist.")
    elif body.kind in {"screenshot", "get_status"} and payload:
        raise HTTPException(status_code=422, detail=f"{body.kind} does not accept a payload.")


@router.get("/status")
async def remote_status(x_jarvis_remote_token: str | None = Header(default=None)) -> dict[str, Any]:
    _auth(x_jarvis_remote_token)
    now = time.time()
    with _db() as db:
        agents = db.execute("SELECT id,platform,capabilities,last_seen,status FROM agents").fetchall()
        tasks = db.execute("SELECT status,COUNT(*) AS n FROM tasks GROUP BY status").fetchall()
    return {
        "enabled": True,
        "agents": [
            {"id": a["id"], "platform": a["platform"], "capabilities": json.loads(a["capabilities"]),
             "online": a["status"] == "online" and now - a["last_seen"] < 45,
             "last_seen": a["last_seen"]}
            for a in agents
        ],
        "task_counts": {t["status"]: t["n"] for t in tasks},
        "execution_verified": False,
        "note": "The broker is available; actual remote control requires paired native device agents.",
    }


@router.post("/agents/register")
async def register_agent(body: AgentRegistration, x_jarvis_remote_token: str | None = Header(default=None)) -> dict[str, Any]:
    _auth(x_jarvis_remote_token)
    now = time.time()
    with _db() as db:
        db.execute(
            "INSERT INTO agents(id,platform,capabilities,last_seen,status) VALUES(?,?,?,?,?) "
            "ON CONFLICT(id) DO UPDATE SET platform=excluded.platform,capabilities=excluded.capabilities,last_seen=excluded.last_seen,status='online'",
            (body.id, body.platform, json.dumps(body.capabilities), now, "online"),
        )
    return {"registered": True, "id": body.id, "platform": body.platform, "heartbeat_required_seconds": 30}


@router.post("/agents/{agent_id}/heartbeat")
async def heartbeat(agent_id: str, x_jarvis_remote_token: str | None = Header(default=None)) -> dict[str, Any]:
    _auth(x_jarvis_remote_token)
    agent_id = _valid_device_id(agent_id)
    with _db() as db:
        cur = db.execute("UPDATE agents SET last_seen=?,status='online' WHERE id=?", (time.time(), agent_id))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Agent is not registered.")
    return {"ok": True, "heartbeat_at": time.time()}


@router.post("/tasks")
async def create_task(body: RemoteTaskRequest, x_jarvis_remote_token: str | None = Header(default=None)) -> dict[str, Any]:
    _auth(x_jarvis_remote_token)
    _validate_action(body)
    task_id = str(uuid.uuid4())
    now = time.time()
    expires = now + settings.remote_task_ttl_seconds
    with _db() as db:
        if body.target_agent:
            agent = db.execute("SELECT platform,status,last_seen FROM agents WHERE id=?", (body.target_agent,)).fetchone()
            if not agent or agent["platform"] != body.target_platform or agent["status"] != "online" or now - agent["last_seen"] > 45:
                raise HTTPException(status_code=409, detail="Target device is not online or has the wrong platform.")
        db.execute(
            "INSERT INTO tasks(id,target_platform,target_agent,kind,payload,status,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)",
            (task_id, body.target_platform, body.target_agent, body.kind, json.dumps(body.payload), "queued", now, expires),
        )
    return {"task_id": task_id, "status": "queued", "expires_at": expires, "note": "Queued only; task completion is not implied."}


@router.get("/agents/{agent_id}/tasks")
async def poll_tasks(agent_id: str, x_jarvis_remote_token: str | None = Header(default=None)) -> dict[str, Any]:
    _auth(x_jarvis_remote_token)
    agent_id = _valid_device_id(agent_id)
    now = time.time()
    with _db() as db:
        agent = db.execute("SELECT platform FROM agents WHERE id=?", (agent_id,)).fetchone()
        if not agent:
            raise HTTPException(status_code=404, detail="Agent is not registered.")
        db.execute("UPDATE tasks SET status='expired' WHERE status='queued' AND expires_at<?", (now,))
        rows = db.execute(
            "SELECT id,kind,payload,expires_at FROM tasks WHERE status='queued' AND target_platform=? AND (target_agent IS NULL OR target_agent=?) AND expires_at>=? ORDER BY created_at LIMIT 10",
            (agent["platform"], agent_id, now),
        ).fetchall()
        ids = [row["id"] for row in rows]
        if ids:
            db.executemany("UPDATE tasks SET status='running',target_agent=? WHERE id=?", [(agent_id, task_id) for task_id in ids])
    return {"tasks": [{"id": r["id"], "kind": r["kind"], "payload": json.loads(r["payload"]), "expires_at": r["expires_at"]} for r in rows]}


class TaskResult(BaseModel):
    status: Literal["succeeded", "failed", "cancelled"]
    result: dict[str, Any] = Field(default_factory=dict)
    error: str | None = Field(default=None, max_length=1000)


@router.post("/tasks/{task_id}/result")
async def finish_task(task_id: str, body: TaskResult, x_jarvis_remote_token: str | None = Header(default=None)) -> dict[str, Any]:
    _auth(x_jarvis_remote_token)
    try:
        uuid.UUID(task_id)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Invalid task id.") from exc
    with _db() as db:
        cur = db.execute(
            "UPDATE tasks SET status=?,result=?,error=? WHERE id=? AND status='running' AND expires_at>=?",
            (body.status, json.dumps(body.result), body.error, task_id, time.time()),
        )
        if cur.rowcount == 0:
            raise HTTPException(status_code=409, detail="Task is missing, expired, or not running.")
    return {"task_id": task_id, "status": body.status}
