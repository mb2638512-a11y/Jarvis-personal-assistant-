"""One-time QR pairing for Android/Windows clients sharing the Jarvis host.

The QR contains a short-lived challenge code only. Long-lived device credentials
are generated after redemption and are returned once to the redeeming client.
"""
from __future__ import annotations

import hashlib
import secrets
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, Field

from jarvis_api.config import settings

router = APIRouter(prefix="/api/pairing", tags=["Device pairing"])
DB_PATH = Path(__file__).resolve().parent.parent / "data" / "device_pairing.sqlite3"
CHALLENGE_TTL = 180


@contextmanager
def _db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS challenges (
        id TEXT PRIMARY KEY, code_hash TEXT NOT NULL, expires_at REAL NOT NULL,
        used INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS devices (
        id TEXT PRIMARY KEY, label TEXT NOT NULL, platform TEXT NOT NULL,
        token_hash TEXT NOT NULL, created_at REAL NOT NULL, revoked INTEGER NOT NULL DEFAULT 0
    )""")
    db.commit()
    try:
        yield db
        db.commit()
    finally:
        db.close()


def _admin(token: str | None) -> None:
    expected = settings.remote_gateway_token.strip()
    if not expected:
        raise HTTPException(status_code=503, detail="PC pairing administration is not configured.")
    if not token or not secrets.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail="Jarvis PC administrator authorization required.")


def _hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class RedeemRequest(BaseModel):
    challenge_id: str = Field(min_length=36, max_length=36)
    code: str = Field(pattern=r"^\d{6}$")
    device_label: str = Field(min_length=1, max_length=80)
    platform: Literal["android", "windows"] = "android"


@router.post("/challenge")
async def create_challenge(
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
):
    _admin(x_jarvis_remote_token)
    scheme = request.url.scheme
    if scheme != "https" and request.url.hostname not in {"localhost", "127.0.0.1"}:
        raise HTTPException(status_code=400, detail="QR pairing requires HTTPS on non-localhost networks.")
    challenge_id = str(uuid.uuid4())
    code = f"{secrets.randbelow(1_000_000):06d}"
    expires = time.time() + CHALLENGE_TTL
    with _db() as db:
        db.execute("DELETE FROM challenges WHERE expires_at < ?", (time.time() - 600,))
        db.execute(
            "INSERT INTO challenges(id,code_hash,expires_at) VALUES(?,?,?)",
            (challenge_id, _hash(code), expires),
        )
    # No permanent credential or provider secret is ever embedded in this URI.
    pairing_uri = f"jarvis://pair?host={request.base_url}&challenge={challenge_id}&code={code}"
    return {"challenge_id": challenge_id, "code": code, "pairing_uri": pairing_uri,
            "expires_at": expires, "expires_in_seconds": CHALLENGE_TTL,
            "note": "Display this one-time challenge as a QR. It is not an API key."}


@router.post("/redeem")
async def redeem_challenge(body: RedeemRequest):
    now = time.time()
    with _db() as db:
        row = db.execute("SELECT code_hash,expires_at,used,attempts FROM challenges WHERE id=?",
                         (body.challenge_id,)).fetchone()
        if row is None or row["used"] or row["expires_at"] < now or row["attempts"] >= 5:
            raise HTTPException(status_code=410, detail="Pairing challenge expired, used, or locked.")
        if not secrets.compare_digest(row["code_hash"], _hash(body.code)):
            db.execute("UPDATE challenges SET attempts=attempts+1 WHERE id=?", (body.challenge_id,))
            bad_code = True
        else:
            bad_code = False
            db.execute("UPDATE challenges SET used=1 WHERE id=?", (body.challenge_id,))
            device_id = str(uuid.uuid4())
            credential = secrets.token_urlsafe(32)
            db.execute(
                "INSERT INTO devices(id,label,platform,token_hash,created_at) VALUES(?,?,?,?,?)",
                (device_id, body.device_label.strip(), body.platform, _hash(credential), now),
            )
    if bad_code:
        raise HTTPException(status_code=401, detail="Incorrect pairing code.")
    return {"paired": True, "device_id": device_id, "device_token": credential,
            "platform": body.platform, "created_at": now,
            "note": "Store device_token in OS secure storage. It is returned only once."}


@router.get("/devices")
async def list_devices(x_jarvis_remote_token: str | None = Header(default=None)):
    _admin(x_jarvis_remote_token)
    with _db() as db:
        rows = db.execute(
            "SELECT id,label,platform,created_at,revoked FROM devices ORDER BY created_at DESC"
        ).fetchall()
    return {"devices": [dict(row) for row in rows]}


@router.delete("/devices/{device_id}")
async def revoke_device(device_id: str, x_jarvis_remote_token: str | None = Header(default=None)):
    _admin(x_jarvis_remote_token)
    with _db() as db:
        cur = db.execute("UPDATE devices SET revoked=1 WHERE id=?", (device_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Paired device not found.")
    return {"revoked": True, "device_id": device_id}


@router.post("/verify")
async def verify_device(x_jarvis_device_token: str | None = Header(default=None)):
    if not x_jarvis_device_token:
        raise HTTPException(status_code=401, detail="Paired device credential required.")
    with _db() as db:
        row = db.execute(
            "SELECT id,label,platform FROM devices WHERE token_hash=? AND revoked=0",
            (_hash(x_jarvis_device_token),),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=401, detail="Device credential is invalid or revoked.")
    return {"authenticated": True, "device": dict(row)}
