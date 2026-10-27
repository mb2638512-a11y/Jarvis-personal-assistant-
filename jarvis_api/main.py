from pathlib import Path
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, field_validator

from jarvis_api.config import settings
from jarvis_api.integrations import router as integrations_router
from jarvis_api.postiz import router as postiz_router

app = FastAPI(title="Jarvis Personal Assistant API", version="0.2.0")
app.include_router(postiz_router)
app.include_router(integrations_router)


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
    configured = bool(settings.api_key.strip() and settings.model.strip())
    return {
        "service": "jarvis-api",
        "provider": "openai-compatible",
        "configured": configured,
        "ready": configured,
        "postiz_configured": bool(settings.postiz_api_key.strip()),
        "note": "Configuration status only; a successful provider request has not been verified by this endpoint.",
    }


@app.post("/api/chat", response_model=ChatResponse)
async def chat(body: ChatRequest) -> ChatResponse:
    if not settings.api_key.strip() or not settings.model.strip():
        raise HTTPException(
            status_code=503,
            detail="AI provider is not configured. Set JARVIS_API_KEY and JARVIS_MODEL.",
        )

    base_url = settings.base_url.rstrip("/")
    if not base_url.startswith("https://") and not (
        base_url.startswith("http://")
        and base_url.split("/")[2].split(":")[0] in {"localhost", "127.0.0.1"}
    ):
        raise HTTPException(
            status_code=500,
            detail="Provider URL must use HTTPS except for localhost.",
        )

    payload = {
        "model": settings.model,
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
                    "Authorization": f"Bearer {settings.api_key}",
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
