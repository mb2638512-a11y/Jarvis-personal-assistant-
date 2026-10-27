"""Private device telemetry API for Jarvis hardware health and security posture.

This stores snapshots explicitly reported by trusted, opt-in device agents. It
does not itself scan a device or guarantee protection from attackers.
"""
from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Header, HTTPException, Query
from pydantic import BaseModel, Field

from jarvis_api.config import settings

router = APIRouter(prefix="/api/device-health", tags=["device-health"])
_DB = Path(__file__).resolve().parent.parent / "data" / "device_health.sqlite3"


def _connect() -> sqlite3.Connection:
    _DB.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(_DB)
    db.row_factory = sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS metrics (
      id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL,
      platform TEXT NOT NULL, cpu_percent REAL, memory_percent REAL,
      memory_used_bytes INTEGER, memory_total_bytes INTEGER,
      disk_percent REAL, disk_free_bytes INTEGER, battery_percent REAL,
      battery_plugged INTEGER, temperature_c REAL, network_sent_bytes INTEGER,
      network_received_bytes INTEGER, top_processes_json TEXT,
      observed_at TEXT NOT NULL, received_at TEXT NOT NULL
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS security_posture (
      id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL,
      platform TEXT NOT NULL, firewall_enabled INTEGER,
      antivirus_enabled INTEGER, realtime_protection INTEGER,
      disk_encryption TEXT, os_updates TEXT, screen_lock TEXT,
      risk_level TEXT NOT NULL, findings_json TEXT NOT NULL,
      observed_at TEXT NOT NULL, received_at TEXT NOT NULL
    )""")
    db.commit()
    return db


def _authorize(token: str | None) -> None:
    expected = settings.remote_gateway_token.strip()
    if not expected:
        raise HTTPException(503, "Set JARVIS_REMOTE_GATEWAY_TOKEN to enable device telemetry.")
    if token is None or token != expected:
        raise HTTPException(401, "Valid Jarvis gateway token required.")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Metrics(BaseModel):
    device_id: str = Field(min_length=1, max_length=100)
    platform: Literal["android", "windows"]
    cpu_percent: float | None = Field(default=None, ge=0, le=100)
    memory_percent: float | None = Field(default=None, ge=0, le=100)
    memory_used_bytes: int | None = Field(default=None, ge=0)
    memory_total_bytes: int | None = Field(default=None, ge=0)
    disk_percent: float | None = Field(default=None, ge=0, le=100)
    disk_free_bytes: int | None = Field(default=None, ge=0)
    battery_percent: float | None = Field(default=None, ge=0, le=100)
    battery_plugged: bool | None = None
    temperature_c: float | None = Field(default=None, ge=-50, le=200)
    network_sent_bytes: int | None = Field(default=None, ge=0)
    network_received_bytes: int | None = Field(default=None, ge=0)
    top_processes: list[dict[str, str | int | float]] = Field(default_factory=list, max_length=20)
    observed_at: datetime | None = None


class SecurityPosture(BaseModel):
    device_id: str = Field(min_length=1, max_length=100)
    platform: Literal["android", "windows"]
    firewall_enabled: bool | None = None
    antivirus_enabled: bool | None = None
    realtime_protection: bool | None = None
    disk_encryption: str | None = Field(default=None, max_length=80)
    os_updates: str | None = Field(default=None, max_length=120)
    screen_lock: str | None = Field(default=None, max_length=80)
    risk_level: Literal["unknown", "low", "medium", "high", "critical"] = "unknown"
    findings: list[str] = Field(default_factory=list, max_length=50)
    observed_at: datetime | None = None


@router.post("/metrics")
def report_metrics(body: Metrics, x_jarvis_gateway_token: str | None = Header(default=None)) -> dict:
    _authorize(x_jarvis_gateway_token)
    now = _now()
    observed = (body.observed_at or datetime.now(timezone.utc)).isoformat()
    with _connect() as db:
        db.execute("""INSERT INTO metrics
          (device_id,platform,cpu_percent,memory_percent,memory_used_bytes,memory_total_bytes,
           disk_percent,disk_free_bytes,battery_percent,battery_plugged,temperature_c,
           network_sent_bytes,network_received_bytes,top_processes_json,observed_at,received_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
          (body.device_id,body.platform,body.cpu_percent,body.memory_percent,body.memory_used_bytes,
           body.memory_total_bytes,body.disk_percent,body.disk_free_bytes,body.battery_percent,
           None if body.battery_plugged is None else int(body.battery_plugged),body.temperature_c,
           body.network_sent_bytes,body.network_received_bytes,
           __import__("json").dumps(body.top_processes),observed,now))
    return {"accepted": True, "received_at": now}


@router.get("/metrics")
def get_metrics(device_id: str = Query(min_length=1, max_length=100), limit: int = Query(default=60, ge=1, le=500), x_jarvis_gateway_token: str | None = Header(default=None)) -> dict:
    _authorize(x_jarvis_gateway_token)
    with _connect() as db:
        rows = db.execute("""SELECT * FROM metrics WHERE device_id=? ORDER BY id DESC LIMIT ?""", (device_id,limit)).fetchall()
    import json
    items = []
    for row in rows:
        item = dict(row)
        item["battery_plugged"] = None if item["battery_plugged"] is None else bool(item["battery_plugged"])
        item["top_processes"] = json.loads(item.pop("top_processes_json") or "[]")
        items.append(item)
    return {"device_id": device_id, "metrics": items, "latest": items[0] if items else None}


@router.post("/security")
def report_security(body: SecurityPosture, x_jarvis_gateway_token: str | None = Header(default=None)) -> dict:
    _authorize(x_jarvis_gateway_token)
    now = _now()
    observed = (body.observed_at or datetime.now(timezone.utc)).isoformat()
    with _connect() as db:
        db.execute("""INSERT INTO security_posture
          (device_id,platform,firewall_enabled,antivirus_enabled,realtime_protection,
           disk_encryption,os_updates,screen_lock,risk_level,findings_json,observed_at,received_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
          (body.device_id,body.platform,
           None if body.firewall_enabled is None else int(body.firewall_enabled),
           None if body.antivirus_enabled is None else int(body.antivirus_enabled),
           None if body.realtime_protection is None else int(body.realtime_protection),
           body.disk_encryption,body.os_updates,body.screen_lock,body.risk_level,
           __import__("json").dumps(body.findings[:50]),observed,now))
    return {"accepted": True, "received_at": now}


@router.get("/security")
def get_security(device_id: str = Query(min_length=1, max_length=100), limit: int = Query(default=30, ge=1, le=200), x_jarvis_gateway_token: str | None = Header(default=None)) -> dict:
    _authorize(x_jarvis_gateway_token)
    import json
    with _connect() as db:
        rows = db.execute("SELECT * FROM security_posture WHERE device_id=? ORDER BY id DESC LIMIT ?",(device_id,limit)).fetchall()
    items=[]
    for row in rows:
        item=dict(row)
        for key in ("firewall_enabled","antivirus_enabled","realtime_protection"):
            item[key]=None if item[key] is None else bool(item[key])
        item["findings"]=json.loads(item.pop("findings_json") or "[]")
        items.append(item)
    return {"device_id":device_id,"reports":items,"latest":items[0] if items else None}
