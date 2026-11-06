"""Encrypted server-side credentials for third-party integrations."""
from __future__ import annotations

import json
import secrets
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from urllib.parse import urlsplit

from cryptography.fernet import InvalidToken
from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, Field, field_validator

from jarvis_api.config import settings
from jarvis_api.provider_vault import _fernet

router = APIRouter(prefix="/api/integration-config", tags=["PC integration vault"])
DB_PATH = Path(__file__).resolve().parent.parent / "data" / "integration_vault.sqlite3"


@contextmanager
def _db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute("""CREATE TABLE IF NOT EXISTS integration_configs (
        name TEXT PRIMARY KEY, encrypted_payload BLOB NOT NULL, updated_at REAL NOT NULL
    )""")
    db.commit()
    try:
        yield db
        db.commit()
    finally:
        db.close()


def _admin(request: Request, token: str | None) -> None:
    peer = request.client.host if request.client else ""
    if peer in {"127.0.0.1", "::1", "localhost"}:
        return
    expected = settings.remote_gateway_token.strip()
    if not expected:
        raise HTTPException(status_code=503, detail="Jarvis PC administrator authorization is not configured.")
    if not token or not secrets.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail="Jarvis PC administrator authorization required.")


def _safe_url(value: str) -> str:
    value = value.strip().rstrip("/")
    parsed = urlsplit(value)
    local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"}
    if (parsed.scheme != "https" and not local_http) or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Integration URL must use HTTPS, except localhost.")
    return value


def get_integration_config(name: str) -> dict[str, str] | None:
    try:
        with _db() as db:
            row = db.execute("SELECT encrypted_payload FROM integration_configs WHERE name=?", (name,)).fetchone()
        if not row:
            return None
        raw = _fernet().decrypt(row["encrypted_payload"]).decode("utf-8")
        data = json.loads(raw)
        return data if isinstance(data, dict) else None
    except (InvalidToken, ValueError, UnicodeDecodeError, json.JSONDecodeError, sqlite3.Error):
        return None


def _save(name: str, data: dict[str, str]) -> None:
    encrypted = _fernet().encrypt(json.dumps(data, separators=(",", ":")).encode("utf-8"))
    with _db() as db:
        db.execute(
            "INSERT INTO integration_configs(name,encrypted_payload,updated_at) VALUES(?,?,?) "
            "ON CONFLICT(name) DO UPDATE SET encrypted_payload=excluded.encrypted_payload,updated_at=excluded.updated_at",
            (name, encrypted, time.time()),
        )


class PostizConfig(BaseModel):
    base_url: str = Field(min_length=8, max_length=500)
    api_key: str = Field(min_length=1, max_length=4000)

    @field_validator("base_url")
    @classmethod
    def valid_url(cls, value: str) -> str:
        return _safe_url(value)


class ArtemisConfig(BaseModel):
    base_url: str = Field(min_length=8, max_length=500)
    gateway_token: str = Field(min_length=16, max_length=4000)

    @field_validator("base_url")
    @classmethod
    def valid_url(cls, value: str) -> str:
        return _safe_url(value)


@router.get("")
async def get_integration_configs(
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
) -> dict[str, object]:
    _admin(request, x_jarvis_remote_token)
    postiz = get_integration_config("postiz")
    artemis = get_integration_config("artemis")
    return {
        "postiz": {
            "configured": bool((postiz or {}).get("api_key") or settings.postiz_api_key.strip()),
            "base_url": (postiz or {}).get("base_url") or settings.postiz_base_url,
            "credential_exposed": False,
        },
        "artemis": {
            "configured": bool((artemis or {}).get("gateway_token") or settings.artemis_gateway_token.strip()),
            "base_url": (artemis or {}).get("base_url") or settings.artemis_base_url,
            "credential_exposed": False,
        },
    }


@router.put("/postiz")
async def save_postiz_config(
    body: PostizConfig,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
) -> dict[str, object]:
    _admin(request, x_jarvis_remote_token)
    _save("postiz", {"base_url": body.base_url, "api_key": body.api_key})
    return {"saved": True, "service": "postiz", "credential_exposed": False, "base_url": body.base_url}


@router.put("/artemis")
async def save_artemis_config(
    body: ArtemisConfig,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
) -> dict[str, object]:
    _admin(request, x_jarvis_remote_token)
    _save("artemis", {"base_url": body.base_url, "gateway_token": body.gateway_token})
    return {"saved": True, "service": "artemis", "credential_exposed": False, "base_url": body.base_url}
