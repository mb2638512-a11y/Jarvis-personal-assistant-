"""Initial cross-platform Jarvis API scaffold.

This is a safe starter, not a production task executor. Platform actions must be
implemented in adapters and authorized before execution.
"""
from __future__ import annotations

import os
import platform as host_platform
import secrets
import threading
import time
from typing import Literal
from uuid import uuid4

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

API_VERSION = "1.0.0"
app = FastAPI(
    title="Jarvis Shared Backend",
    version=API_VERSION,
    description="Shared API contract for Android and Windows clients.",
)

_lock = threading.Lock()
_tasks: dict[str, dict] = {}
_idempotency: dict[str, str] = {}


class TaskRequest(BaseModel):
    task: str = Field(min_length=1, max_length=10_000)
    platform: Literal["android", "windows"] | None = None
    requestedCapabilities: list[str] = Field(default_factory=list)
    dryRun: bool = False


class TaskAccepted(BaseModel):
    taskId: str
    status: Literal["queued", "running"]


class ApprovalDecision(BaseModel):
    decision: Literal["approve", "reject"]


def _host() -> str:
    name = host_platform.system().lower()
    if name == "windows":
        return "windows"
    if name == "android" or "ANDROID_ROOT" in os.environ:
        return "android"
    return "server"


def _capabilities(target: str) -> list[dict]:
    # Capabilities remain unavailable until a real adapter + permission flow exists.
    common = [
        {"id": "task.submit", "status": "available", "requiresConfirmation": False, "permission": None},
        {"id": "task.cancel", "status": "available", "requiresConfirmation": False, "permission": None},
    ]
    if target == "windows":
        platform_caps = [
            {"id": "windows.window_control", "status": "unsupported", "requiresConfirmation": True, "permission": "windows_adapter_not_implemented"},
            {"id": "windows.files", "status": "unsupported", "requiresConfirmation": True, "permission": "windows_adapter_not_implemented"},
            {"id": "windows.process_launch", "status": "unsupported", "requiresConfirmation": True, "permission": "windows_adapter_not_implemented"},
        ]
    elif target == "android":
        platform_caps = [
            {"id": "android.intents", "status": "unsupported", "requiresConfirmation": True, "permission": "android_adapter_not_implemented"},
            {"id": "android.notifications", "status": "unsupported", "requiresConfirmation": True, "permission": "notification_permission_and_adapter"},
            {"id": "android.accessibility", "status": "unsupported", "requiresConfirmation": True, "permission": "explicit_user_enabled_accessibility_service"},
        ]
    else:
        platform_caps = []
    return common + platform_caps


@app.get("/api/v1/health")
def health() -> dict:
    return {"status": "ok", "apiVersion": API_VERSION}


@app.get("/api/v1/capabilities")
def capabilities(platform: Literal["android", "windows", "server"] | None = None) -> dict:
    target = platform or _host()
    return {"platform": target, "capabilities": _capabilities(target)}


@app.post("/api/v1/tasks", response_model=TaskAccepted, status_code=202)
def submit_task(
    request: TaskRequest,
    idempotency_key: str = Header(alias="Idempotency-Key", min_length=8, max_length=128),
) -> TaskAccepted:
    with _lock:
        existing = _idempotency.get(idempotency_key)
        if existing:
            old = _tasks.get(existing)
            if old and old["request"] != request.model_dump():
                raise HTTPException(status_code=409, detail="Idempotency-Key already used for a different request")
            if old:
                return TaskAccepted(taskId=existing, status=old["status"])
        task_id = str(uuid4())
        _tasks[task_id] = {
            "status": "queued",
            "request": request.model_dump(),
            "createdAt": time.time(),
            "result": {
                "message": "Accepted by API scaffold. No platform action has been executed.",
                "implemented": False,
            },
        }
        _idempotency[idempotency_key] = task_id
    return TaskAccepted(taskId=task_id, status="queued")


@app.get("/api/v1/tasks/{task_id}")
def get_task(task_id: str) -> dict:
    with _lock:
        task = _tasks.get(task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="Task not found")
        return {"taskId": task_id, "status": task["status"], "result": task["result"]}


@app.post("/api/v1/tasks/{task_id}/cancel", status_code=202)
def cancel_task(task_id: str) -> dict:
    with _lock:
        task = _tasks.get(task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="Task not found")
        if task["status"] in ("queued", "running"):
            task["status"] = "cancelled"
        return {"taskId": task_id, "status": task["status"]}


@app.get("/")
def root() -> dict:
    return {
        "service": "Jarvis Shared Backend",
        "api": "/api/v1",
        "docs": "/docs",
        "warning": "Starter scaffold only; production authentication and platform adapters are not implemented.",
    }
