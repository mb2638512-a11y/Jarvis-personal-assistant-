"""One-time QR pairing with explicit approval on the Windows host.

The phone first requests pairing, the PC owner approves it locally, and only
then can the phone exchange the challenge for a device-scoped credential.
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
from urllib.parse import urlsplit

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
    db.execute("""CREATE TABLE IF NOT EXISTS pending_pairings (
        id TEXT PRIMARY KEY, challenge_id TEXT NOT NULL, label TEXT NOT NULL,
        platform TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
        created_at REAL NOT NULL, expires_at REAL NOT NULL
    )""")
    db.commit()
    try:
        yield db
        db.commit()
    finally:
        db.close()


def _admin(token: str | None, request: Request | None = None) -> None:
    peer = request.client.host if request and request.client else ""
    if peer in {"127.0.0.1", "::1", "localhost"}:
        return
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


class PairingStatusRequest(BaseModel):
    challenge_id: str = Field(min_length=36, max_length=36)
    request_id: str = Field(min_length=36, max_length=36)
    code: str = Field(pattern=r"^\d{6}$")


class PairingCompleteRequest(PairingStatusRequest):
    pass


@router.post("/challenge")
async def create_challenge(
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
):
    _admin(x_jarvis_remote_token, request)
    if request.url.scheme != "https" and request.url.hostname not in {"localhost", "127.0.0.1"}:
        raise HTTPException(status_code=400, detail="QR pairing requires HTTPS on non-localhost networks.")
    challenge_id = str(uuid.uuid4())
    code = f"{secrets.randbelow(1_000_000):06d}"
    expires = time.time() + CHALLENGE_TTL
    with _db() as db:
        db.execute("DELETE FROM challenges WHERE expires_at < ?", (time.time() - 600,))
        db.execute("DELETE FROM pending_pairings WHERE expires_at < ?", (time.time() - 600,))
        db.execute(
            "INSERT INTO challenges(id,code_hash,expires_at) VALUES(?,?,?)",
            (challenge_id, _hash(code), expires),
        )
    public_base = settings.public_base_url.strip().rstrip("/")
    if public_base:
        parsed_public = urlsplit(public_base)
        if parsed_public.scheme != "https" or not parsed_public.hostname or parsed_public.username or parsed_public.password or parsed_public.query or parsed_public.fragment:
            raise HTTPException(status_code=500, detail="JARVIS_PUBLIC_BASE_URL must be a clean HTTPS origin.")
    else:
        public_base = str(request.base_url).rstrip("/")
    pairing_uri = f"jarvis://pair?host={public_base}&challenge={challenge_id}&code={code}"
    return {
        "challenge_id": challenge_id,
        "code": code,
        "pairing_uri": pairing_uri,
        "expires_at": expires,
        "expires_in_seconds": CHALLENGE_TTL,
        "note": "One-time challenge only. The PC owner must approve the pairing before a device token is issued.",
    }


@router.post("/redeem")
async def redeem_challenge(body: RedeemRequest):
    now = time.time()
    outcome = "ok"
    request_id = str(uuid.uuid4())
    with _db() as db:
        row = db.execute(
            "SELECT code_hash,expires_at,used,attempts FROM challenges WHERE id=?",
            (body.challenge_id,),
        ).fetchone()
        if row is None or row["used"] or row["expires_at"] < now or row["attempts"] >= 5:
            outcome = "expired"
        elif not secrets.compare_digest(row["code_hash"], _hash(body.code)):
            db.execute("UPDATE challenges SET attempts=attempts+1 WHERE id=?", (body.challenge_id,))
            outcome = "bad_code"
        else:
            db.execute(
                "INSERT INTO pending_pairings(id,challenge_id,label,platform,status,created_at,expires_at) VALUES(?,?,?,?,?,?,?)",
                (request_id, body.challenge_id, body.device_label.strip(), body.platform, "pending", now, row["expires_at"]),
            )
            db.execute("UPDATE challenges SET used=1 WHERE id=?", (body.challenge_id,))
    if outcome == "expired":
        raise HTTPException(status_code=410, detail="Pairing challenge expired, used, or locked.")
    if outcome == "bad_code":
        raise HTTPException(status_code=401, detail="Incorrect pairing code.")
    return {
        "pending_approval": True,
        "request_id": request_id,
        "status": "pending",
        "note": "Approve this device from the Windows Jarvis pairing screen. No device credential has been issued yet.",
    }


@router.post("/pending/status")
async def pairing_status(body: PairingStatusRequest):
    with _db() as db:
        challenge = db.execute(
            "SELECT code_hash,expires_at FROM challenges WHERE id=?",
            (body.challenge_id,),
        ).fetchone()
        pending = db.execute(
            "SELECT status,expires_at FROM pending_pairings WHERE id=? AND challenge_id=?",
            (body.request_id, body.challenge_id),
        ).fetchone()
        if challenge is None or pending is None or not secrets.compare_digest(challenge["code_hash"], _hash(body.code)):
            raise HTTPException(status_code=401, detail="Pairing challenge proof is invalid.")
        if min(challenge["expires_at"], pending["expires_at"]) < time.time():
            raise HTTPException(status_code=410, detail="Pairing request expired.")
        return {"request_id": body.request_id, "status": pending["status"]}


@router.get("/pending")
async def list_pending(
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
):
    _admin(x_jarvis_remote_token, request)
    with _db() as db:
        rows = db.execute(
            "SELECT id,label,platform,created_at,expires_at FROM pending_pairings WHERE status='pending' AND expires_at>=? ORDER BY created_at DESC",
            (time.time(),),
        ).fetchall()
    return {"requests": [dict(row) for row in rows]}


@router.post("/pending/{request_id}/approve")
async def approve_pairing(
    request_id: str,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
):
    _admin(x_jarvis_remote_token, request)
    with _db() as db:
        row = db.execute("SELECT expires_at,status FROM pending_pairings WHERE id=?", (request_id,)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Pending pairing request not found.")
        if row["expires_at"] < time.time():
            db.execute("UPDATE pending_pairings SET status='expired' WHERE id=?", (request_id,))
            raise HTTPException(status_code=410, detail="Pairing request expired.")
        if row["status"] != "pending":
            raise HTTPException(status_code=409, detail="Pairing request is no longer pending.")
        db.execute("UPDATE pending_pairings SET status='approved' WHERE id=?", (request_id,))
    return {"approved": True, "request_id": request_id}


@router.post("/pending/{request_id}/deny")
async def deny_pairing(
    request_id: str,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
):
    _admin(x_jarvis_remote_token, request)
    with _db() as db:
        cur = db.execute(
            "UPDATE pending_pairings SET status='denied' WHERE id=? AND status='pending'",
            (request_id,),
        )
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Pending pairing request not found.")
    return {"denied": True, "request_id": request_id}


@router.post("/complete")
async def complete_pairing(body: PairingCompleteRequest):
    now = time.time()
    with _db() as db:
        challenge = db.execute(
            "SELECT code_hash,expires_at FROM challenges WHERE id=?",
            (body.challenge_id,),
        ).fetchone()
        pending = db.execute(
            "SELECT label,platform,status,expires_at FROM pending_pairings WHERE id=? AND challenge_id=?",
            (body.request_id, body.challenge_id),
        ).fetchone()
        if challenge is None or pending is None or not secrets.compare_digest(challenge["code_hash"], _hash(body.code)):
            raise HTTPException(status_code=401, detail="Pairing challenge proof is invalid.")
        if min(challenge["expires_at"], pending["expires_at"]) < now:
            raise HTTPException(status_code=410, detail="Pairing request expired.")
        if pending["status"] != "approved":
            raise HTTPException(status_code=403, detail="Windows PC approval is required before credentials can be issued.")
        device_id = str(uuid.uuid4())
        credential = secrets.token_urlsafe(32)
        db.execute(
            "INSERT INTO devices(id,label,platform,token_hash,created_at) VALUES(?,?,?,?,?)",
            (device_id, pending["label"], pending["platform"], _hash(credential), now),
        )
        db.execute("UPDATE pending_pairings SET status='completed' WHERE id=?", (body.request_id,))
    return {
        "paired": True,
        "device_id": device_id,
        "device_token": credential,
        "platform": pending["platform"],
        "created_at": now,
        "note": "Credential issued once after local PC approval. Store it in OS secure storage.",
    }


@router.get("/devices")
async def list_devices(
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
):
    _admin(x_jarvis_remote_token, request)
    with _db() as db:
        rows = db.execute(
            "SELECT id,label,platform,created_at,revoked FROM devices ORDER BY created_at DESC"
        ).fetchall()
    return {"devices": [dict(row) for row in rows]}


@router.delete("/devices/{device_id}")
async def revoke_device(
    device_id: str,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
):
    _admin(x_jarvis_remote_token, request)
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
