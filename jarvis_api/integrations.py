"""Shared capability registry for Jarvis desktop and mobile clients.

Upstream engines run in their appropriate execution environments: Atticus on
Windows, ARTEMIS beside an authorized Android test device, and Postiz as a
server-side social publishing service. This module reports readiness without
pretending these external runtimes are already connected.
"""
from pathlib import Path
from typing import Any

from fastapi import APIRouter

from jarvis_api.config import settings

router = APIRouter(prefix="/api/integrations", tags=["Shared integrations"])
ROOT = Path(__file__).resolve().parent.parent
VENDOR_ROOT = ROOT / "backend" / "vendor"

INTEGRATIONS: tuple[dict[str, Any], ...] = (
    {"id": "atticus", "name": "Jarvis Windows Automation", "upstream": "https://github.com/FindlayHi/atticus-windows", "runtime": "windows-device-agent", "client_support": ["windows", "android"], "execution_host": "paired-windows-device", "capabilities": ["voice-assistant", "window-management", "file-search", "ui-automation"], "vendor_path": "atticus-windows", "requires_device_agent": True},
    {"id": "artemis", "name": "Jarvis Android Device Automation", "upstream": "https://github.com/google/artemis", "runtime": "android-device-agent", "client_support": ["windows", "android"], "execution_host": "paired-android-device-or-emulator", "capabilities": ["android-ui-automation", "device-testing", "screenshots", "logcat"], "vendor_path": "artemis", "requires_device_agent": True},
    {"id": "postiz", "name": "Jarvis Social Publishing", "upstream": "https://github.com/gitroomhq/postiz-app", "runtime": "server-side-api", "client_support": ["windows", "android"], "execution_host": "shared-server", "capabilities": ["social-publishing", "post-scheduling", "channels", "analytics"], "vendor_path": "postiz-app", "requires_device_agent": False},
)


def integration_status() -> dict[str, Any]:
    results = []
    for item in INTEGRATIONS:
        source_path = VENDOR_ROOT / item["vendor_path"]
        source_present = (source_path / "UPSTREAM_README.md").is_file()
        configured = item["id"] == "postiz" and bool(settings.postiz_api_key.strip())
        results.append({**item, "source_present": source_present, "configured": configured, "live_connected": False, "ready": False, "note": ("Both clients can request this capability through the shared backend, but the required paired device agent and authenticated task transport are not implemented." if item["requires_device_agent"] else "Both clients use the same server-side adapter; live credentials and upstream connectivity must be verified.")})
    return {"shared_backend": True, "client_platforms": ["windows", "android"], "integrations": results, "production_ready": False}


router_status = integration_status


@router.get("/status")
async def get_integrations_status() -> dict[str, Any]:
    return integration_status()
