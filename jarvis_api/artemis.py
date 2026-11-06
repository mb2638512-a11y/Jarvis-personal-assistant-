"""Server-side bridge to a private Google ARTEMIS device host.

ARTEMIS owns Android UI perception/execution. Jarvis only authenticates,
submits reviewed tasks, and relays task state; it never pretends the phone is
connected when the upstream daemon is absent.
"""
from __future__ import annotations

import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any, Literal
from urllib.parse import urlsplit

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field, field_validator

from jarvis_api.config import settings
from jarvis_api.integration_vault import get_integration_config
from jarvis_api.remote_control import _auth as _remote_auth

router = APIRouter(prefix="/api/artemis", tags=["ARTEMIS Android automation"])
DEVICE_RE = re.compile(r"^[A-Za-z0-9._:-]{2,128}$")


def _base_url() -> str:
    config = get_integration_config("artemis") or {}
    raw = (config.get("base_url") or settings.artemis_base_url).strip().rstrip("/")
    if not raw:
        raise HTTPException(status_code=503, detail="ARTEMIS host is not configured.")
    parsed = urlsplit(raw)
    local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"}
    if parsed.scheme != "https" and not local_http:
        raise HTTPException(status_code=500, detail="ARTEMIS host must use HTTPS except localhost.")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise HTTPException(status_code=500, detail="ARTEMIS host URL must not contain credentials or query parameters.")
    return raw


def _configured() -> bool:
    config = get_integration_config("artemis") or {}
    return bool((config.get("base_url") or settings.artemis_base_url.strip()) and (config.get("gateway_token") or settings.artemis_gateway_token.strip()))


async def _request(method: str, path: str, *, body: dict[str, Any] | None = None) -> Any:
    base = _base_url()
    config = get_integration_config("artemis") or {}
    token = config.get("gateway_token") or settings.artemis_gateway_token.strip()
    try:
        async with httpx.AsyncClient(timeout=settings.artemis_timeout_seconds, follow_redirects=False) as client:
            response = await client.request(
                method, f"{base}{path}",
                headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
                json=body,
            )
            response.raise_for_status()
            if not response.content:
                return {"ok": True}
            return response.json()
    except httpx.TimeoutException as exc:
        raise HTTPException(status_code=504, detail="ARTEMIS host request timed out.") from exc
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=502, detail=f"ARTEMIS host returned HTTP {exc.response.status_code}.") from exc
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(status_code=502, detail="ARTEMIS host response could not be processed.") from exc


class ArtemisTaskRequest(BaseModel):
    goal: str = Field(min_length=5, max_length=4000)
    device_serial: str = Field(min_length=2, max_length=128)
    profile: Literal["flash", "pro"] = "flash"
    user_confirmed: bool = False

    @field_validator("goal")
    @classmethod
    def clean_goal(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("goal must contain text")
        return value

    @field_validator("device_serial")
    @classmethod
    def valid_device(cls, value: str) -> str:
        if not DEVICE_RE.fullmatch(value):
            raise ValueError("invalid Android device serial")
        return value


@router.get("/status")
async def artemis_status(
    x_jarvis_remote_token: str | None = Header(default=None),
    x_jarvis_device_token: str | None = Header(default=None),
) -> dict[str, Any]:
    _remote_auth(x_jarvis_remote_token, x_jarvis_device_token)
    if not _configured():
        return {
            "configured": False, "live_connected": False, "ready": False,
            "note": "Configure a private ARTEMIS host URL and gateway token.",
        }
    # A configured URL is not proof of a running daemon or attached phone.
    try:
        status = await _request("GET", "/api/status")
        devices = await _request("GET", "/api/devices")
        device_list = devices.get("devices", []) if isinstance(devices, dict) else devices
        if not isinstance(device_list, list):
            device_list = []
        return {
            "configured": True, "live_connected": True, "ready": bool(device_list),
            "host_status": status, "devices": device_list,
            "note": "Live status read from the configured ARTEMIS host.",
        }
    except HTTPException as exc:
        return {
            "configured": True, "live_connected": False, "ready": False,
            "error": exc.detail, "note": "ARTEMIS is configured but the upstream connection is not verified.",
        }


@router.post("/host/start")
async def start_local_artemis_host(request: Request) -> dict[str, Any]:
    peer = request.client.host if request.client else ""
    if peer not in {"127.0.0.1", "::1", "localhost"}:
        raise HTTPException(status_code=403, detail="ARTEMIS host startup is available only from the Windows PC.")
    if sys.platform != "win32":
        raise HTTPException(status_code=501, detail="Automatic ARTEMIS startup is currently supported on Windows only.")
    root = Path(__file__).resolve().parent.parent
    script = root / "scripts" / "start-artemis.ps1"
    if not script.is_file():
        raise HTTPException(status_code=503, detail="Jarvis ARTEMIS startup script is missing.")
    data_dir = root / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    log_path = data_dir / "artemis-start.log"
    log_handle = log_path.open("ab")
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    try:
        process = subprocess.Popen(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)],
            cwd=str(root),
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            creationflags=flags,
        )
    except OSError as exc:
        log_handle.close()
        raise HTTPException(status_code=500, detail="Could not launch the ARTEMIS setup process.") from exc
    log_handle.close()
    return {"started": True, "pid": process.pid, "log": "data/artemis-start.log", "note": "First startup can take several minutes while dependencies and Android tools are installed."}


@router.post("/tasks")
async def submit_artemis_task(
    body: ArtemisTaskRequest,
    x_jarvis_remote_token: str | None = Header(default=None),
    x_jarvis_device_token: str | None = Header(default=None),
) -> dict[str, Any]:
    _remote_auth(x_jarvis_remote_token, x_jarvis_device_token)
    if not body.user_confirmed:
        raise HTTPException(status_code=403, detail="Android automation requires explicit user confirmation.")
    task_id = str(uuid.uuid4())
    payload = {
        "goal": body.goal,
        "profile": body.profile,
        "device_serial": body.device_serial,
        "session_id": task_id,
        "ingress": "jarvis",
    }
    result = await _request("POST", "/api/run", body=payload)
    tasks = result.get("tasks") if isinstance(result, dict) else None
    if not isinstance(tasks, list) or not tasks or not isinstance(tasks[0], dict):
        raise HTTPException(status_code=502, detail="ARTEMIS did not confirm task admission.")
    admitted = tasks[0]
    admitted_id = admitted.get("task_id") or admitted.get("session_id") or admitted.get("id") or task_id
    return {"task_id": str(admitted_id), "status": str(admitted.get("status") or result.get("status") or "queued"), "device_serial": body.device_serial, "upstream": "artemis"}


@router.get("/tasks/{task_id}")
async def get_artemis_task(
    task_id: str,
    x_jarvis_remote_token: str | None = Header(default=None),
    x_jarvis_device_token: str | None = Header(default=None),
) -> dict[str, Any]:
    _remote_auth(x_jarvis_remote_token, x_jarvis_device_token)
    try:
        parsed = str(uuid.UUID(task_id))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Invalid ARTEMIS task id.") from exc
    result = await _request("GET", f"/api/sessions/{parsed}")
    if not isinstance(result, dict):
        raise HTTPException(status_code=502, detail="ARTEMIS task response was not an object.")
    return result
