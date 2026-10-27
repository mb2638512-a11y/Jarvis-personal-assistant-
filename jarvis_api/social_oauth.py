"""OAuth-first social account connection discovery for Jarvis.

Actual provider OAuth and token storage are delegated to the configured,
self-hosted Postiz workspace. Jarvis clients never receive social tokens.
"""
from urllib.parse import urlparse

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from jarvis_api.config import settings

router = APIRouter(prefix="/api/social", tags=["Social OAuth"])

# Providers available in the vendored Postiz ecosystem. A provider may still
# require its official developer-app credentials in the Postiz server config.
PROVIDERS = [
    ("facebook", "Facebook Pages"),
    ("instagram", "Instagram"),
    ("threads", "Threads"),
    ("youtube", "YouTube"),
    ("tiktok", "TikTok"),
    ("tiktok-business", "TikTok Business"),
    ("linkedin", "LinkedIn"),
    ("pinterest", "Pinterest"),
    ("x", "X"),
    ("reddit", "Reddit"),
    ("mastodon", "Mastodon"),
    ("bluesky", "Bluesky"),
    ("telegram", "Telegram"),
    ("discord", "Discord"),
    ("slack", "Slack"),
    ("github", "GitHub"),
    ("tumblr", "Tumblr"),
    ("dribbble", "Dribbble"),
    ("threads", "Threads"),
    ("wordpress", "WordPress"),
    ("medium", "Medium"),
    ("devto", "DEV Community"),
    ("hashnode", "Hashnode"),
    ("webflow", "Webflow"),
    ("shopify", "Shopify"),
    ("whop", "Whop"),
    ("substack", "Substack"),
    ("beehiiv", "Beehiiv"),
    ("播客", "Podcast"),
    ("google-business", "Google Business Profile"),
    ("telegram", "Telegram"),
    ("line", "LINE"),
    ("vk", "VK"),
    ("ok", "Odnoklassniki"),
    ("lemmy", "Lemmy"),
    ("moltbook", "Moltbook"),
]
PROVIDERS = list({slug: (slug, label) for slug, label in PROVIDERS}.values())


def _workspace_url() -> str | None:
    raw = settings.postiz_app_url.strip().rstrip("/")
    if not raw:
        return None
    parsed = urlparse(raw)
    local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"}
    if parsed.scheme != "https" and not local_http:
        raise HTTPException(status_code=500, detail="Social workspace URL must use HTTPS.")
    return raw


class SocialWorkspaceResponse(BaseModel):
    configured: bool
    oauth_owner: str
    connect_url: str | None
    provider_count: int
    note: str


@router.get("/providers")
async def social_providers() -> dict:
    workspace = _workspace_url()
    return {
        "configured": workspace is not None,
        "oauth_owner": "self-hosted-postiz",
        "connect_url": f"{workspace}/integrations" if workspace else None,
        "provider_count": len(PROVIDERS),
        "providers": [{"id": slug, "name": name} for slug, name in PROVIDERS],
        "note": "OAuth happens in the self-hosted social workspace. Official provider app credentials may be required server-side; no social tokens are returned to Jarvis clients.",
    }


@router.get("/connect")
async def connect_social_accounts() -> dict:
    workspace = _workspace_url()
    if not workspace:
        raise HTTPException(
            status_code=503,
            detail="Set JARVIS_POSTIZ_APP_URL to your self-hosted Postiz workspace URL first.",
        )
    return {
        "url": f"{workspace}/integrations",
        "method": "oauth",
        "note": "Open this URL and authorize each social account with the provider's official OAuth consent screen.",
    }
