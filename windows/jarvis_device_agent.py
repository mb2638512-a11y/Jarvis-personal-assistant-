"""Jarvis Windows device agent backed by the vendored Atticus Windows primitives.

Run on the Windows PC that should be controlled. It polls the Jarvis task broker
and accepts only typed, allow-listed actions; it never executes shell commands.
"""
from __future__ import annotations

import base64
import json
import os
import platform
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ATTICUS_DIR = ROOT / "backend" / "vendor" / "atticus-windows"
sys.path.insert(0, str(ATTICUS_DIR))

try:
    import winctl  # type: ignore
except ImportError as exc:
    raise SystemExit("Atticus Windows dependencies are missing. Install windows-agent requirements first.") from exc

BASE_URL = os.environ.get("JARVIS_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
TOKEN = os.environ.get("JARVIS_REMOTE_GATEWAY_TOKEN", "").strip()
AGENT_ID = os.environ.get("JARVIS_AGENT_ID", platform.node().lower().replace(" ", "-")[:60] or "windows-pc")
POLL_SECONDS = max(1.0, float(os.environ.get("JARVIS_AGENT_POLL_SECONDS", "2")))
APP_NAMES = {
    "notepad": "Notepad",
    "calculator": "Calculator",
    "explorer": "File Explorer",
    "chrome": "Google Chrome",
    "edge": "Microsoft Edge",
    "firefox": "Mozilla Firefox",
    "settings": "Settings",
}
KEYS = {
    "ENTER": 0x0D, "ESC": 0x1B, "TAB": 0x09,
    "CTRL+C": (0x11, 0x43), "CTRL+V": (0x11, 0x56),
    "CTRL+S": (0x11, 0x53), "ALT+TAB": (0x12, 0x09), "WIN": 0x5B,
}


def request_json(path: str, body: dict[str, Any] | None = None, timeout: float = 15) -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"X-Jarvis-Remote-Token": TOKEN, "Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE_URL + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError("Jarvis API returned an invalid response")
    return payload


def execute(kind: str, payload: dict[str, Any]) -> dict[str, Any]:
    if kind == "open_url":
        url = payload["url"]
        if not isinstance(url, str) or not url.startswith("https://"):
            raise ValueError("Only HTTPS URLs are allowed")
        return {"opened": bool(webbrowser.open(url, new=2))}
    if kind == "open_app":
        alias = str(payload["app"]).lower()
        if alias not in APP_NAMES:
            raise ValueError("Application is not allow-listed")
        return {"opened": bool(winctl.launch(APP_NAMES[alias])), "app": alias}
    if kind == "type_text":
        text = payload["text"]
        if not isinstance(text, str) or not 1 <= len(text) <= 4000:
            raise ValueError("Text length is invalid")
        # paste_into restores the user's clipboard after typing.
        return {"detail": str(winctl.paste_into("", text))}
    if kind == "press_key":
        key = str(payload["key"]).upper()
        if key not in KEYS:
            raise ValueError("Key is not allow-listed")
        codes = KEYS[key] if isinstance(KEYS[key], tuple) else (KEYS[key],)
        winctl.keys(*codes)
        return {"pressed": key}
    if kind == "get_status":
        app, _title, _hwnd = winctl.front()
        return {"hostname": platform.node(), "platform": "windows", "foreground_app": app, "monitors": len(winctl.monitors())}
    if kind == "screenshot":
        monitors = winctl.monitors()
        if not monitors:
            raise RuntimeError("No display detected")
        with tempfile.TemporaryDirectory(prefix="jarvis-shot-") as folder:
            path = str(Path(folder) / "screen.jpg")
            winctl.capture(monitors[0], path)
            encoded = base64.b64encode(Path(path).read_bytes()).decode("ascii")
        return {"mime_type": "image/jpeg", "image_base64": encoded, "display": monitors[0]["name"]}
    raise ValueError("Unsupported task type")


def main() -> None:
    if sys.platform != "win32":
        raise SystemExit("The Atticus-backed Jarvis device agent runs on Windows only.")
    parsed = urllib.parse.urlsplit(BASE_URL)
    local_http = parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"}
    if parsed.scheme != "https" and not local_http:
        raise SystemExit("JARVIS_BASE_URL must use HTTPS except for localhost.")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise SystemExit("JARVIS_BASE_URL must not contain credentials or query parameters.")
    if not TOKEN:
        raise SystemExit("Set JARVIS_REMOTE_GATEWAY_TOKEN before starting the agent.")
    capabilities = ["open_url", "open_app", "type_text", "press_key", "screenshot", "get_status"]
    request_json("/api/remote/agents/register", {"id": AGENT_ID, "platform": "windows", "capabilities": capabilities})
    print(f"Jarvis Windows agent registered as {AGENT_ID}. Press Ctrl+C to stop.")
    while True:
        try:
            request_json(f"/api/remote/agents/{urllib.parse.quote(AGENT_ID, safe='')}/heartbeat", {})
            tasks = request_json(f"/api/remote/agents/{urllib.parse.quote(AGENT_ID, safe='')}/tasks").get("tasks", [])
            for task in tasks:
                task_id = task.get("id")
                try:
                    result = execute(task["kind"], task.get("payload") or {})
                    status, error = "succeeded", None
                except Exception as exc:
                    result, status, error = {}, "failed", str(exc)[:1000]
                request_json(f"/api/remote/tasks/{task_id}/result", {"status": status, "result": result, "error": error})
        except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as exc:
            print(f"Jarvis agent connection/action error: {exc}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
