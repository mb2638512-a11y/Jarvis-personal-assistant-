"""Opt-in Windows agent for the Jarvis remote task broker.

Configure JARVIS_REMOTE_BASE_URL and JARVIS_REMOTE_GATEWAY_TOKEN in the
agent's environment. Run interactively; do not install as a service until the
user has reviewed the security model. Never executes shell commands.
"""
from __future__ import annotations

import json
import os
import platform
import subprocess
import time
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path

BASE_URL = os.environ.get("JARVIS_REMOTE_BASE_URL", "").rstrip("/")
TOKEN = os.environ.get("JARVIS_REMOTE_GATEWAY_TOKEN", "")
AGENT_ID = os.environ.get("JARVIS_WINDOWS_AGENT_ID", platform.node().lower().replace(" ", "-")[:60])
POLL_SECONDS = 2
APP_ALLOWLIST = {
    "notepad": ["notepad.exe"],
    "calculator": ["calc.exe"],
    "explorer": ["explorer.exe"],
    "chrome": ["chrome.exe"],
    "edge": ["msedge.exe"],
    "firefox": ["firefox.exe"],
}
KEY_ALLOWLIST = {"ENTER": "enter", "ESC": "esc", "TAB": "tab", "CTRL+C": "ctrl+c", "CTRL+V": "ctrl+v", "CTRL+S": "ctrl+s", "ALT+TAB": "alt+tab", "WIN": "win"}


def request(path: str, method: str = "GET", body: dict | None = None) -> dict:
    payload = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        BASE_URL + path,
        data=payload,
        method=method,
        headers={"X-Jarvis-Remote-Token": TOKEN, "X-Jarvis-Agent-Id": AGENT_ID, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def execute(task: dict) -> dict:
    kind, payload = task["kind"], task.get("payload", {})
    if kind == "open_url":
        url = payload.get("url", "")
        if not url.startswith("https://"):
            raise ValueError("Only HTTPS URLs are allowed")
        webbrowser.open(url, new=2)
        return {"opened": True, "url": url}
    if kind == "open_app":
        app = str(payload.get("app", "")).lower()
        if app != "settings" and app not in APP_ALLOWLIST:
            raise ValueError("App is not allowlisted")
        if app == "settings":
            os.startfile("ms-settings:")
        else:
            subprocess.Popen(APP_ALLOWLIST[app], shell=False)
        return {"launched": app}
    if kind == "get_status":
        return {"platform": "windows", "hostname": platform.node(), "python": platform.python_version()}
    if kind in {"type_text", "press_key", "screenshot"}:
        try:
            import pyautogui
        except ImportError as exc:
            raise RuntimeError("Install pyautogui on this Windows agent to enable typing, keys, and screenshots.") from exc
        if kind == "type_text":
            text = payload.get("text")
            if not isinstance(text, str) or len(text) > 4000:
                raise ValueError("Invalid text payload")
            pyautogui.write(text, interval=0.01)
            return {"typed_characters": len(text)}
        if kind == "press_key":
            key = str(payload.get("key", "")).upper()
            if key not in KEY_ALLOWLIST:
                raise ValueError("Key is not allowlisted")
            pyautogui.hotkey(*KEY_ALLOWLIST[key].split("+"))
            return {"pressed": key}
        if kind == "screenshot":
            output = Path.home() / "Pictures" / "Jarvis-screenshot.png"
            output.parent.mkdir(parents=True, exist_ok=True)
            pyautogui.screenshot().save(output)
            return {"saved_to": str(output), "note": "Screenshot remains on this PC; it is not uploaded."}
    raise ValueError("Unsupported task kind")


def main() -> None:
    if not BASE_URL.startswith("https://") and not BASE_URL.startswith("http://127.0.0.1") and not BASE_URL.startswith("http://localhost"):
        raise SystemExit("Set JARVIS_REMOTE_BASE_URL to an HTTPS URL (HTTP is allowed only for localhost).")
    if not TOKEN:
        raise SystemExit("Set JARVIS_REMOTE_GATEWAY_TOKEN. Do not commit it or put it in a client build.")
    request("/api/remote/agents/register", "POST", {
        "id": AGENT_ID, "platform": "windows",
        "capabilities": ["open_url", "open_app", "type_text", "press_key", "screenshot", "get_status"],
    })
    print(f"Jarvis Windows agent '{AGENT_ID}' connected. Press Ctrl+C to stop.")
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
        except (urllib.error.URLError, TimeoutError, ValueError) as exc:
            print(f"Broker unavailable or response invalid: {exc}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
