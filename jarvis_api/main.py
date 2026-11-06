from pathlib import Path
from typing import Literal

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, field_validator

from jarvis_api.artemis import router as artemis_router
from jarvis_api.config import settings
from jarvis_api.device_pairing import router as device_pairing_router
from jarvis_api.integration_vault import get_integration_config, router as integration_vault_router
from jarvis_api.integrations import router as integrations_router
from jarvis_api.mcp_registry import router as mcp_router
from jarvis_api.model_catalog import router as model_catalog_router
from jarvis_api.postiz import router as postiz_router
from jarvis_api.provider_vault import router as provider_vault_router, active_provider
from jarvis_api.remote_control import _auth as _remote_auth, router as remote_control_router
from jarvis_api.social_oauth import router as social_oauth_router
from jarvis_api.wellbeing import router as wellbeing_router

app = FastAPI(title="Jarvis Personal Assistant API", version="0.2.0")
app.include_router(postiz_router)
app.include_router(artemis_router)
app.include_router(integrations_router)
app.include_router(integration_vault_router)
app.include_router(mcp_router)
app.include_router(social_oauth_router)
app.include_router(remote_control_router)
app.include_router(device_pairing_router)
app.include_router(model_catalog_router)
app.include_router(provider_vault_router)
app.include_router(wellbeing_router)


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=12000)

    @field_validator("message")
    @classmethod
    def message_must_contain_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Message must contain non-whitespace text.")
        return value


class ChatResponse(BaseModel):
    reply: str
    provider: Literal["openai-compatible"]


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/status")
async def status() -> dict[str, object]:
    configured = bool(active_provider() or (settings.api_key.strip() and settings.model.strip()))
    postiz_config = get_integration_config("postiz") or {}
    artemis_config = get_integration_config("artemis") or {}
    return {
        "service": "jarvis-api",
        "provider": "openai-compatible",
        "configured": configured,
        "ready": configured,
        "postiz_configured": bool(postiz_config.get("api_key") or settings.postiz_api_key.strip()),
        "artemis_configured": bool(artemis_config.get("gateway_token") or settings.artemis_gateway_token.strip()),
        "social_oauth_configured": bool(settings.postiz_app_url.strip()),
        "note": "Configuration status only; successful third-party connections must be checked separately.",
    }


@app.post("/api/chat", response_model=ChatResponse)
async def chat(
    body: ChatRequest,
    request: Request,
    x_jarvis_remote_token: str | None = Header(default=None),
    x_jarvis_device_token: str | None = Header(default=None),
) -> ChatResponse:
    peer = request.client.host if request.client else ""
    if peer not in {"127.0.0.1", "::1", "localhost"}:
        _remote_auth(x_jarvis_remote_token, x_jarvis_device_token)
    provider = active_provider()
    api_key = provider["api_key"] if provider else settings.api_key.strip()
    model = provider["model"] if provider else settings.model.strip()
    base_url = (provider["base_url"] if provider else settings.base_url).rstrip("/")
    if not api_key or not model:
        raise HTTPException(status_code=503, detail="AI provider is not configured. Add a provider in PC-hosted Jarvis model settings.")
    if not base_url.startswith("https://") and not (
        base_url.startswith("http://")
        and base_url.split("/")[2].split(":")[0] in {"localhost", "127.0.0.1"}
    ):
        raise HTTPException(
            status_code=500,
            detail="Provider URL must use HTTPS except for localhost.",
        )

    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "You are Jarvis, a helpful personal assistant. Be honest about capabilities.",
            },
            {"role": "user", "content": body.message},
        ],
    }
    try:
        async with httpx.AsyncClient(timeout=settings.request_timeout_seconds) as client:
            response = await client.post(
                f"{base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
            response.raise_for_status()
            data = response.json()
            reply = data["choices"][0]["message"]["content"]
            if not isinstance(reply, str) or not reply.strip():
                raise ValueError("Provider returned an empty response")
            return ChatResponse(reply=reply, provider="openai-compatible")
    except httpx.TimeoutException as exc:
        raise HTTPException(
            status_code=504, detail="AI provider request timed out."
        ) from exc
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"AI provider returned HTTP {exc.response.status_code}.",
        ) from exc
    except (httpx.HTTPError, ValueError, KeyError, IndexError, TypeError) as exc:
        raise HTTPException(
            status_code=502,
            detail="AI provider response could not be processed.",
        ) from exc


# Serve the bundled web UI from the same origin so API requests use the same backend.
_WEB_DIR = Path(__file__).resolve().parent.parent / "web"
if _WEB_DIR.is_dir():
    app.mount("/", StaticFiles(directory=_WEB_DIR, html=True), name="web")
