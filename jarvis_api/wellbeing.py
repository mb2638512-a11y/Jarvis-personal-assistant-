"""Opt-in personal usage, wellbeing check-ins, and security event journal.

This records only information explicitly submitted by a paired client. Android's
UsageStats can report app foreground time with user-granted access; it cannot
reliably tell how many individual reels a user watched inside third-party apps.
"""
from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Header, HTTPException, Query
from pydantic import BaseModel, Field

from jarvis_api.config import settings

router = APIRouter(prefix="/api/wellbeing", tags=["wellbeing"])
_DB = Path(__file__).resolve().parent.parent / "data" / "wellbeing.sqlite3"


def _connect() -> sqlite3.Connection:
    _DB.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(_DB)
    db.row_factory = sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS usage_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL,
        platform TEXT NOT NULL, app_id TEXT NOT NULL, app_label TEXT NOT NULL,
        foreground_seconds INTEGER NOT NULL, reels_count INTEGER,
        observed_at TEXT NOT NULL, recorded_at TEXT NOT NULL
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS checkins (
        id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL,
        mood INTEGER, energy INTEGER, sleep_hours REAL, note TEXT,
        created_at TEXT NOT NULL
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS security_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL,
        severity TEXT NOT NULL, category TEXT NOT NULL, summary TEXT NOT NULL,
        source TEXT NOT NULL, created_at TEXT NOT NULL
    )""")
    db.commit()
    return db


def _authorize(token: str | None) -> None:
    expected = settings.remote_gateway_token.strip()
    if not expected:
        raise HTTPException(503, "Set JARVIS_REMOTE_GATEWAY_TOKEN before enabling private wellbeing APIs.")
    if token is None or token != expected:
        raise HTTPException(401, "Valid Jarvis gateway token required.")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class UsageEvent(BaseModel):
    device_id: str = Field(min_length=1, max_length=100)
    platform: Literal["android", "windows"]
    app_id: str = Field(min_length=1, max_length=250)
    app_label: str = Field(min_length=1, max_length=150)
    foreground_seconds: int = Field(ge=0, le=86400)
    reels_count: int | None = Field(default=None, ge=0, le=100000)
    observed_at: datetime | None = None


class Checkin(BaseModel):
    device_id: str = Field(min_length=1, max_length=100)
    mood: int | None = Field(default=None, ge=1, le=5)
    energy: int | None = Field(default=None, ge=1, le=5)
    sleep_hours: float | None = Field(default=None, ge=0, le=24)
    note: str | None = Field(default=None, max_length=1000)


class SecurityEvent(BaseModel):
    device_id: str = Field(min_length=1, max_length=100)
    severity: Literal["info", "low", "medium", "high", "critical"]
    category: str = Field(min_length=1, max_length=80)
    summary: str = Field(min_length=1, max_length=500)
    source: str = Field(default="client", max_length=100)


@router.post("/usage")
def ingest_usage(event: UsageEvent, x_jarvis_gateway_token: str | None = Header(default=None)) -> dict:
    _authorize(x_jarvis_gateway_token)
    recorded = _now()
    observed = (event.observed_at or datetime.now(timezone.utc)).isoformat()
    with _connect() as db:
        db.execute(
            """INSERT INTO usage_events
            (device_id,platform,app_id,app_label,foreground_seconds,reels_count,observed_at,recorded_at)
            VALUES (?,?,?,?,?,?,?,?)""",
            (event.device_id, event.platform, event.app_id, event.app_label,
             event.foreground_seconds, event.reels_count, observed, recorded),
        )
    return {"accepted": True, "recorded_at": recorded, "reels_count_source": "client_reported" if event.reels_count is not None else None}


@router.get("/usage")
def usage_summary(
    device_id: str = Query(min_length=1, max_length=100),
    days: int = Query(default=7, ge=1, le=90),
    x_jarvis_gateway_token: str | None = Header(default=None),
) -> dict:
    _authorize(x_jarvis_gateway_token)
    with _connect() as db:
        rows = db.execute(
            """SELECT platform,app_id,app_label,SUM(foreground_seconds) AS seconds,
            SUM(reels_count) AS reels_count,COUNT(*) AS samples,MAX(observed_at) AS last_seen
            FROM usage_events WHERE device_id=? AND observed_at >= datetime('now', ?)
            GROUP BY platform,app_id,app_label ORDER BY seconds DESC""",
            (device_id, f"-{days} days"),
        ).fetchall()
    items = [dict(row) for row in rows]
    return {"device_id": device_id, "period_days": days,
            "total_foreground_seconds": sum(item["seconds"] or 0 for item in items),
            "apps": items,
            "reels_note": "Only source-reported counts are shown. Android app-usage permission does not reveal individual reels watched inside other apps."}


@router.post("/checkins")
def create_checkin(checkin: Checkin, x_jarvis_gateway_token: str | None = Header(default=None)) -> dict:
    _authorize(x_jarvis_gateway_token)
    created = _now()
    with _connect() as db:
        cursor = db.execute(
            "INSERT INTO checkins(device_id,mood,energy,sleep_hours,note,created_at) VALUES(?,?,?,?,?,?)",
            (checkin.device_id, checkin.mood, checkin.energy, checkin.sleep_hours, checkin.note, created),
        )
        checkin_id = cursor.lastrowid
    return {"id": checkin_id, "created_at": created, "saved": True,
            "disclaimer": "Wellbeing journaling only; not a diagnosis or emergency service."}


@router.get("/checkins")
def list_checkins(
    device_id: str = Query(min_length=1, max_length=100),
    limit: int = Query(default=30, ge=1, le=100),
    x_jarvis_gateway_token: str | None = Header(default=None),
) -> dict:
    _authorize(x_jarvis_gateway_token)
    with _connect() as db:
        rows = db.execute(
            "SELECT id,mood,energy,sleep_hours,note,created_at FROM checkins WHERE device_id=? ORDER BY id DESC LIMIT ?",
            (device_id, limit),
        ).fetchall()
    return {"device_id": device_id, "checkins": [dict(row) for row in rows]}


@router.post("/security-events")
def create_security_event(event: SecurityEvent, x_jarvis_gateway_token: str | None = Header(default=None)) -> dict:
    _authorize(x_jarvis_gateway_token)
    created = _now()
    with _connect() as db:
        cursor = db.execute(
            "INSERT INTO security_events(device_id,severity,category,summary,source,created_at) VALUES(?,?,?,?,?,?)",
            (event.device_id, event.severity, event.category, event.summary, event.source, created),
        )
        event_id = cursor.lastrowid
    return {"id": event_id, "created_at": created, "saved": True}


@router.get("/security-events")
def list_security_events(
    device_id: str = Query(min_length=1, max_length=100),
    limit: int = Query(default=50, ge=1, le=100),
    x_jarvis_gateway_token: str | None = Header(default=None),
) -> dict:
    _authorize(x_jarvis_gateway_token)
    with _connect() as db:
        rows = db.execute(
            "SELECT id,severity,category,summary,source,created_at FROM security_events WHERE device_id=? ORDER BY id DESC LIMIT ?",
            (device_id, limit),
        ).fetchall()
    return {"device_id": device_id, "events": [dict(row) for row in rows]}
