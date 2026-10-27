"""Optional ADB bridge for an explicitly authorized Android test device.

This agent runs on the PC that has Android platform-tools installed and an
Android device authorized through USB debugging. It uses fixed ADB argument
arrays (never shell=True) and a small action allowlist. This is a safe bridge,
not a replacement for the complete ARTEMIS runtime.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = os.environ.get("JARVIS_REMOTE_BASE_URL", "").rstrip("/")
TOKEN = os.environ.get("JARVIS_REMOTE_GATEWAY_TOKEN", "")
AGENT_ID = os.environ.get("JARVIS_ANDROID_AGENT_ID", "android-usb-device")
ADB = os.environ.get("ADB_PATH", "adb")
POLL_SECONDS = 2
KEYS = {"ENTER": "66", "ESC": "111", "TAB": "61", "BACK": "4", "HOME": "3", "POWER": "26"}
PACKAGES = {
    "chrome": "com.android.chrome",
    "settings": "com.android.settings",
    "youtube": "com.google.android.youtube",
    "maps": "com.google.android.apps.maps",
}


def request(path: str, method: str = "GET", body: dict | None = None) -> dict:
    payload = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        BASE_URL + path, data=payload, method=method,
        headers={"X-Jarvis-Remote-Token": TOKEN, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def adb(*args: str, binary: bool = False):
    result = subprocess.run([ADB, *args], check=True, capture_output=True, timeout=20)
    return result.stdout if binary else result.stdout.decode("utf-8", errors="replace").strip()


def execute(task: dict) -> dict:
    kind, payload = task["kind"], task.get("payload", {})
    if kind == "get_status":
        return {"platform": "android", "device": adb("get-serialno"), "state": adb("get-state")}
    if kind == "open_url":
        url = payload.get("url", "")
        if not isinstance(url, str) or not url.startswith("https://") or len(url) > 2048:
            raise ValueError("Only HTTPS URLs are allowed")
        adb("shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", url)
        return {"opened": True, "url": url}
    if kind == "open_app":
        app = str(payload.get("app", "")).lower()
        package = PACKAGES.get(app)
        if not package:
            raise ValueError("App is not in the Android package allowlist")
        adb("shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1")
        return {"launched": app, "package": package}
    if kind == "press_key":
        key = str(payload.get("key", "")).upper()
        if key not in KEYS:
            raise ValueError("Key is not in the Android key allowlist")
        adb("shell", "input", "keyevent", KEYS[key])
        return {"pressed": key}
    if kind == "type_text":
        text = payload.get("text")
        if not isinstance(text, str) or not text or len(text) > 1000 or not re.fullmatch(r"[A-Za-z0-9 .,!?@_:/+-]+", text):
            raise ValueError("Android typing accepts up to 1000 safe ASCII characters only")
        adb("shell", "input", "text", text.replace(" ", "%s"))
        return {"typed_characters": len(text)}
    if kind == "screenshot":
        image = adb("exec-out", "screencap", "-p", binary=True)
        output = Path.home() / "Pictures" / "Jarvis-android-screenshot.png"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(image)
        return {"saved_to": str(output), "note": "Screenshot remains on the bridge PC; it is not uploaded."}
    raise ValueError("Unsupported task kind")


def main() -> None:
    if not BASE_URL.startswith("https://") and not BASE_URL.startswith("http://127.0.0.1") and not BASE_URL.startswith("http://localhost"):
        raise SystemExit("Set JARVIS_REMOTE_BASE_URL to HTTPS (HTTP is allowed only for localhost).")
    if not TOKEN:
        raise SystemExit("Set JARVIS_REMOTE_GATEWAY_TOKEN privately.")
    serial = adb("get-serialno")
    if not serial or serial == "unknown":
        raise SystemExit("No authorized Android device found. Connect it and approve USB debugging.")
    request("/api/remote/agents/register", "POST", {
        "id": AGENT_ID, "platform": "android",
        "capabilities": ["open_url", "open_app", "type_text", "press_key", "screenshot", "get_status"],
    })
    print(f"Jarvis Android ADB agent '{AGENT_ID}' connected to {serial}. Ctrl+C stops it.")
    last_heartbeat = 0.0
    while True:
        try:
            now = time.time()
            if now - last_heartbeat >= 25:
                request(f"/api/remote/agents/{AGENT_ID}/heartbeat", "POST")
                last_heartbeat = now
            for task in request(f"/api/remote/agents/{AGENT_ID}/tasks").get("tasks", []):
                try:
                    result = execute(task)
                    outcome = {"status": "succeeded", "result": result}
                    print(f"Task {task['id']} succeeded ({task['kind']}).")
                except Exception as exc:
                    outcome = {"status": "failed", "error": str(exc)[:1000]}
                    print(f"Task {task['id']} failed: {exc}")
                request(f"/api/remote/tasks/{task['id']}/result", "POST", outcome)
        except (urllib.error.URLError, TimeoutError, ValueError, subprocess.SubprocessError) as exc:
            print(f"Broker/device unavailable: {exc}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
