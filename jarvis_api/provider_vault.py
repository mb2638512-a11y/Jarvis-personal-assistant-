"""Encrypted PC-side OpenAI-compatible provider vault.

The vault is hosted by the Windows Jarvis backend. Clients receive provider
metadata and model IDs only; credentials are decrypted only inside this process.
"""
from __future__ import annotations

import secrets
import sqlite3
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import httpx
from cryptography.fernet import Fernet, InvalidToken
from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, Field, field_validator

from jarvis_api.config import settings
from jarvis_api.remote_control import _auth as _remote_auth

router = APIRouter(prefix="/api/models/providers", tags=["PC provider vault"])
ROOT = Path(__file__).resolve().parent.parent
DB_PATH = ROOT / "data" / "provider_vault.sqlite3"
KEY_PATH = ROOT / "data" / "provider_vault.key"


def _fernet() -> Fernet:
    configured = settings.provider_vault_key.strip()
    if configured:
        try:
            return Fernet(configured.encode("ascii"))
        except (ValueError, UnicodeEncodeError) as exc:
            raise HTTPException(status_code=500, detail="JARVIS_PROVIDER_VAULT_KEY is invalid.") from exc
    KEY_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        key = KEY_PATH.read_bytes().strip()
        Fernet(key)
    except FileNotFoundError:
        key = Fernet.generate_key()
        with KEY_PATH.open("xb") as handle:
            handle.write(key)
        try:
            KEY_PATH.chmod(0o600)
        except OSError:
            pass
    except (ValueError, OSError) as exc:
        raise HTTPException(status_code=500, detail="Provider vault key file cannot be read.") from exc
    return Fernet(key)


@contextmanager
def _db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS providers (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, base_url TEXT NOT NULL,
        model TEXT NOT NULL, credential BLOB NOT NULL, active INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )""")
    db.commit()
    try:
        yield db
        db.commit()
    finally:
        db.close()


def _admin(token: str | None, request: Request) -> None:
    peer = request.client.host if request.client else ""
    if peer in {"127.0.0.1", "::1", "localhost"}:
        return
    expected = settings.remote_gateway_token.strip()
    if not expected or not token or not secrets.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail="Jarvis PC administrator authorization required.")


def _safe_base(value: str) -> str:
    from urllib.parse import urlsplit
    parsed = urlsplit(value.strip().rstrip("/"))
    local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"}
    if (parsed.scheme != "https" and not local_http) or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Provider base URL must be HTTPS (localhost is allowed for local models).")
    return value.strip().rstrip("/")


class ProviderInput(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    base_url: str = Field(min_length=8, max_length=500)
    model: str = Field(min_length=1, max_length=300)
    api_key: str = Field(min_length=1, max_length=4000)

    @field_validator("base_url")
    @classmethod
    def validate_base_url(cls, value: str) -> str:
        return _safe_base(value)


def _public(row: sqlite3.Row) -> dict[str, Any]:
    return {"id": row["id"], "name": row["name"], "base_url": row["base_url"],
            "model": row["model"], "active": bool(row["active"]),
            "credential_present": True, "created_at": row["created_at"]}


@router.get("")
async def list_providers(
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
) -> dict[str, Any]:
    _admin(x_jarvis_remote_token, request)
    with _db() as db:
        rows = db.execute("SELECT * FROM providers ORDER BY created_at DESC").fetchall()
    return {"providers": [_public(row) for row in rows], "credentials_exposed": False}


@router.post("")
async def add_provider(
    body: ProviderInput,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
) -> dict[str, Any]:
    _admin(x_jarvis_remote_token, request)
    provider_id = str(uuid.uuid4())
    encrypted = _fernet().encrypt(body.api_key.encode("utf-8"))
    with _db() as db:
        active = db.execute("SELECT COUNT(*) FROM providers WHERE active=1").fetchone()[0]
        db.execute(
            "INSERT INTO providers(id,name,base_url,model,credential,active) VALUES(?,?,?,?,?,?)",
            (provider_id, body.name.strip(), body.base_url, body.model.strip(), encrypted, 1 if not active else 0),
        )
        row = db.execute("SELECT * FROM providers WHERE id=?", (provider_id,)).fetchone()
    return {"provider": _public(row), "credentials_exposed": False}


@router.post("/{provider_id}/activate")
async def activate_provider(
    provider_id: str,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
) -> dict[str, Any]:
    _admin(x_jarvis_remote_token, request)
    with _db() as db:
        found = db.execute("SELECT id FROM providers WHERE id=?", (provider_id,)).fetchone()
        if not found:
            raise HTTPException(status_code=404, detail="Provider not found.")
        db.execute("UPDATE providers SET active=0")
        db.execute("UPDATE providers SET active=1 WHERE id=?", (provider_id,))
    return {"active_provider_id": provider_id}


@router.delete("/{provider_id}")
async def delete_provider(
    provider_id: str,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
) -> dict[str, Any]:
    _admin(x_jarvis_remote_token, request)
    with _db() as db:
        cur = db.execute("DELETE FROM providers WHERE id=?", (provider_id,))
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="Provider not found.")
        active = db.execute("SELECT id FROM providers ORDER BY created_at LIMIT 1").fetchone()
        db.execute("UPDATE providers SET active=0")
        if active:
            db.execute("UPDATE providers SET active=1 WHERE id=?", (active["id"],))
    return {"deleted": True, "provider_id": provider_id}


def active_provider() -> dict[str, str] | None:
    try:
        with _db() as db:
            row = db.execute("SELECT * FROM providers WHERE active=1 LIMIT 1").fetchone()
        if not row:
            return None
        key = _fernet().decrypt(row["credential"]).decode("utf-8")
        return {"id": row["id"], "name": row["name"], "base_url": row["base_url"],
                "model": row["model"], "api_key": key}
    except (InvalidToken, UnicodeDecodeError, sqlite3.Error):
        return None


@router.get("/catalog")
async def shared_catalog(x_jarvis_device_token: str | None = Header(default=None)) -> dict[str, Any]:
    _remote_auth(None, x_jarvis_device_token)
    with _db() as db:
        rows = db.execute("SELECT * FROM providers ORDER BY active DESC, created_at DESC").fetchall()
    catalogue = []
    for row in rows:
        item = _public(row)
        try:
            key = _fernet().decrypt(row["credential"]).decode("utf-8")
            async with httpx.AsyncClient(timeout=15) as client:
                response = await client.get(
                    row["base_url"].rstrip("/") + "/models",
                    headers={"Authorization": "Bearer " + key, "Accept": "application/json"},
                )
                response.raise_for_status()
                payload = response.json()
            data = payload.get("data", []) if isinstance(payload, dict) else []
            item["models"] = sorted({str(model["id"]) for model in data if isinstance(model, dict) and model.get("id")})
            item["live_verified"] = True
        except (InvalidToken, UnicodeDecodeError, httpx.HTTPError, ValueError, TypeError):
            item["models"] = []
            item["live_verified"] = False
        catalogue.append(item)
    active = next((item for item in catalogue if item["active"]), None)
    return {"host": "pc", "providers": catalogue, "active_model": active["model"] if active else None,
            "credentials_exposed": False, "shared_backend": True}
