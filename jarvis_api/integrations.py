"""Shared capability registry for Jarvis desktop and mobile clients.

The integrations are executed in their proper environments: Atticus primitives
on a paired Windows device, ARTEMIS on a private Android device host, and
Postiz through its server-side Public API. Source presence is never reported as
a live connection.
"""
from __future__ import annotations

import sqlite3
import time
from pathlib import Path
from typing import Any

from fastapi import APIRouter

from jarvis_api.config import settings

router = APIRouter(prefix="/api/integrations", tags=["Shared integrations"])
ROOT = Path(__file__).resolve().parent.parent
VENDOR_ROOT = ROOT / "backend" / "vendor"
REMOTE_DB = ROOT / "data" / "remote_tasks.sqlite3"

INTEGRATIONS: tuple[dict[str, Any], ...] = (
    {
        "id": "atticus", "name": "Jarvis Windows Automation",
        "upstream": "https://github.com/FindlayHi/atticus-windows",
        "runtime": "windows-device-agent", "execution_host": "paired-windows-device",
        "capabilities": ["open_url", "open_app", "type_text", "press_key", "screenshot", "get_status"],
        "vendor_path": "atticus-windows",
    },
    {
        "id": "artemis", "name": "Jarvis Android Automation",
        "upstream": "https://github.com/google/artemis",
        "runtime": "private-artemis-daemon", "execution_host": "paired-android-device-host",
        "capabilities": ["android-ui-automation", "device-testing", "screenshots", "logcat", "task-status"],
        "vendor_path": "artemis",
    },
    {
        "id": "postiz", "name": "Jarvis Social Publishing",
        "upstream": "https://github.com/gitroomhq/postiz-app",
        "runtime": "server-side-public-api", "execution_host": "shared-server",
        "capabilities": ["social-publishing", "post-scheduling", "channels", "analytics"],
        "vendor_path": "postiz-app",
    },
)


def _windows_agent_online() -> bool:
    if not REMOTE_DB.is_file():
        return False
    try:
        with sqlite3.connect(REMOTE_DB, timeout=1) as db:
            row = db.execute(
                "SELECT 1 FROM agents WHERE platform='windows' AND status='online' AND last_seen>=? LIMIT 1",
                (time.time() - 45,),
            ).fetchone()
            return row is not None
    except sqlite3.Error:
        return False


def integration_status() -> dict[str, Any]:
    results = []
    for item in INTEGRATIONS:
        source_path = VENDOR_ROOT / item["vendor_path"]
        source_present = (source_path / "UPSTREAM_README.md").is_file()
        if item["id"] == "atticus":
            configured = bool(settings.remote_gateway_token.strip())
            live_connected = configured and _windows_agent_online()
            note = "A paired Windows device agent must be running. It executes typed allow-listed actions through the vendored Atticus Windows primitives."
        elif item["id"] == "artemis":
            configured = bool(settings.artemis_base_url.strip() and settings.artemis_gateway_token.strip())
            live_connected = False  # The dedicated /api/artemis/status endpoint performs the live probe.
            note = "ARTEMIS runs as a separate private Android device host. Configure its HTTPS URL and bearer token; the daemon must not be exposed publicly."
        else:
            configured = bool(settings.postiz_api_key.strip() and settings.postiz_gateway_token.strip())
            live_connected = False  # Only a protected upstream request can verify credentials and workspace connectivity.
            note = "Postiz Public API adapter is connected in Jarvis backend code. Credentials and a real workspace request are still required to verify live publishing."
        results.append({
            **item,
            "source_present": source_present,
            "configured": configured,
            "live_connected": live_connected,
            "ready": source_present and configured and live_connected,
            "note": note,
        })
    return {
        "shared_backend": True,
        "client_platforms": ["windows", "android"],
        "integrations": results,
        "production_ready": all(item["ready"] for item in results),
    }


router_status = integration_status


@router.get("/status")
async def get_integrations_status() -> dict[str, Any]:
    return integration_status()
