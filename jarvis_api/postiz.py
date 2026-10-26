"""Secure server-side adapter for the Postiz Public API.

Postiz API keys are kept on the server and are never returned to clients.
Publishing routes require a separate Jarvis gateway token until first-party
user authentication/authorization is implemented.
"""
from __future__ import annotations

import secrets
from typing import Any, Literal

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel, Field

from jarvis_api.config import settings

router = APIRouter(prefix="/api/postiz", tags=["Postiz social publishing"])


def _configured() -> bool:
    return bool(settings.postiz_api_key.strip())


def _base_url() -> str:
    value = settings.postiz_base_url.rstrip("/")
    if not value.startswith("https://") and not (
        value.startswith("http://")
        and value.split("/")[2].split(":")[0] in {"localhost", "127.0.0.1"}
    ):
        raise HTTPException(status_code=500, detail="Postiz URL must use HTTPS except for localhost.")
    return value


def _require_gateway_token(x_jarvis_postiz_token: str | None = Header(default=None)) -> None:
    expected = settings.postiz_gateway_token.strip()
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Postiz actions are disabled until JARVIS_POSTIZ_GATEWAY_TOKEN is configured.",
        )
    if not x_jarvis_postiz_token or not secrets.compare_digest(x_jarvis_postiz_token, expected):
        raise HTTPException(status_code=401, detail="Valid Jarvis Postiz gateway token required.")


async def _request(method: str, path: str, *, params: dict[str, Any] | None = None,
                   json: dict[str, Any] | None = None) -> Any:
    if not _configured():
        raise HTTPException(status_code=503, detail="Postiz is not configured on this server.")
    url = f"{_base_url()}/{path.lstrip('/')}"
    try:
        async with httpx.AsyncClient(timeout=settings.postiz_timeout_seconds) as client:
            response = await client.request(
                method,
                url,
                headers={"Authorization": settings.postiz_api_key, "Accept": "application/json"},
                params=params,
                json=json,
            )
            response.raise_for_status()
            if response.status_code == 204 or not response.content:
                return {"ok": True}
            return response.json()
    except httpx.TimeoutException as exc:
        raise HTTPException(status_code=504, detail="Postiz request timed out.") from exc
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Postiz returned HTTP {exc.response.status_code}.",
        ) from exc
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(status_code=502, detail="Postiz response could not be processed.") from exc


class PostizPostValue(BaseModel):
    content: str = Field(min_length=1, max_length=30000)
    image: list[dict[str, Any]] = Field(default_factory=list)


class PostizTargetPost(BaseModel):
    integration: dict[str, str]
    value: list[PostizPostValue] = Field(min_length=1)
    settings: dict[str, Any]


class PostizCreatePost(BaseModel):
    type: Literal["draft", "schedule", "now"]
    date: str | None = None
    shortLink: bool = False
    tags: list[dict[str, Any]] = Field(default_factory=list)
    posts: list[PostizTargetPost] = Field(min_length=1, max_length=50)


@router.get("/status")
async def postiz_status() -> dict[str, Any]:
    return {
        "configured": _configured(),
        "base_url_configured": bool(settings.postiz_base_url.strip()),
        "gateway_auth_configured": bool(settings.postiz_gateway_token.strip()),
        "live_connection_verified": False,
        "note": "Run a protected channels request to verify the live Postiz connection.",
    }


@router.get("/channels", dependencies=[Depends(_require_gateway_token)])
async def list_channels() -> Any:
    return await _request("GET", "/integrations")


@router.get("/posts", dependencies=[Depends(_require_gateway_token)])
async def list_posts(
    start_date: str = Query(alias="startDate", min_length=1),
    end_date: str = Query(alias="endDate", min_length=1),
    customer: str | None = Query(default=None),
) -> Any:
    params: dict[str, str] = {"startDate": start_date, "endDate": end_date}
    if customer:
        params["customer"] = customer
    return await _request("GET", "/posts", params=params)


@router.post("/posts", dependencies=[Depends(_require_gateway_token)])
async def create_post(body: PostizCreatePost) -> Any:
    if body.type == "schedule" and not body.date:
        raise HTTPException(status_code=422, detail="date is required when type is 'schedule'.")
    return await _request("POST", "/posts", json=body.model_dump(exclude_none=True))


@router.delete("/posts/{post_id}", dependencies=[Depends(_require_gateway_token)])
async def delete_post(post_id: str) -> Any:
    if not post_id.strip() or len(post_id) > 200:
        raise HTTPException(status_code=422, detail="Invalid Postiz post id.")
    return await _request("DELETE", f"/posts/{post_id}")
