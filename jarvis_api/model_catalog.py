"""PC-hosted model catalogue shared by every Jarvis client.

Provider credentials remain in the host environment and are never serialized
into these responses. Android and Windows clients consume the same catalogue.
"""
from __future__ import annotations

from typing import Any

import httpx
from fastapi import APIRouter

from jarvis_api.config import settings

router = APIRouter(prefix="/api/models", tags=["Shared AI models"])


@router.get("/catalog")
async def model_catalog() -> dict[str, Any]:
    base = settings.base_url.rstrip("/")
    configured = bool(settings.api_key.strip() and settings.model.strip())
    models: list[dict[str, str]] = []
    live_verified = False
    if settings.api_key.strip() and base.startswith("https://"):
        try:
            async with httpx.AsyncClient(timeout=settings.request_timeout_seconds) as client:
                response = await client.get(
                    f"{base}/models",
                    headers={"Authorization": f"Bearer {settings.api_key}"},
                )
                response.raise_for_status()
                payload = response.json()
                rows = payload.get("data", []) if isinstance(payload, dict) else []
                models = [
                    {"id": str(item["id"]), "object": str(item.get("object", "model"))}
                    for item in rows if isinstance(item, dict) and item.get("id")
                ]
                live_verified = True
        except (httpx.HTTPError, ValueError):
            # A configured provider is not reported as live when /models fails.
            live_verified = False
    active = settings.model.strip()
    if active and not any(item["id"] == active for item in models):
        models.insert(0, {"id": active, "object": "configured-default"})
    return {
        "host": "pc",
        "configured": configured,
        "provider_base_url": base,
        "active_model": active or None,
        "models": models,
        "live_verified": live_verified,
        "credentials_exposed": False,
        "note": "This is the shared PC-hosted model catalogue. Provider API keys never leave the host.",
    }


@router.get("/health")
async def model_health() -> dict[str, Any]:
    return {
        "configured": bool(settings.api_key.strip() and settings.model.strip()),
        "active_model": settings.model.strip() or None,
        "provider_base_url": settings.base_url.rstrip("/"),
        "credential_present": bool(settings.api_key.strip()),
        "credential_exposed": False,
    }
