"""Opt-in Windows foreground-app usage collector for Jarvis.

Run only on your own Windows account. Reports app executable names and foreground
seconds; it deliberately does not collect window titles, keystrokes, screenshots,
or content. Configure JARVIS_BACKEND_URL, JARVIS_REMOTE_GATEWAY_TOKEN, and
JARVIS_DEVICE_ID in the process environment before starting.
"""
from __future__ import annotations

import ctypes
import json
import os
import platform
import time
from datetime import datetime, timezone
from ctypes import wintypes
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

if platform.system() != "Windows":
    raise SystemExit("This opt-in collector only runs on Windows.")

BACKEND = os.environ.get("JARVIS_BACKEND_URL", "").rstrip("/")
TOKEN = os.environ.get("JARVIS_REMOTE_GATEWAY_TOKEN", "")
DEVICE_ID = os.environ.get("JARVIS_DEVICE_ID", "my-windows")
INTERVAL = max(2, min(int(os.environ.get("JARVIS_USAGE_POLL_SECONDS", "5")), 60))
if not BACKEND.startswith("https://") and not BACKEND.startswith("http://127.0.0.1") and not BACKEND.startswith("http://localhost"):
    raise SystemExit("Set JARVIS_BACKEND_URL to HTTPS (HTTP is allowed only for localhost).")
if not TOKEN.strip():
    raise SystemExit("Set JARVIS_REMOTE_GATEWAY_TOKEN; never put it in source code.")

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
user32.GetForegroundWindow.restype = wintypes.HWND
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


def foreground_app() -> tuple[str, str]:
    hwnd = user32.GetForegroundWindow()
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    if not pid.value:
        return "unknown", "Unknown app"
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
    if not handle:
        return f"pid:{pid.value}", "Restricted app"
    try:
        buffer = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(buffer))
        if kernel32.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            executable = os.path.basename(buffer.value)[:250]
            return executable.lower(), executable
        return f"pid:{pid.value}", "Restricted app"
    finally:
        kernel32.CloseHandle(handle)


def send(app_id: str, app_label: str, seconds: int, observed_at: str) -> None:
    payload = json.dumps({
        "device_id": DEVICE_ID, "platform": "windows",
        "app_id": app_id, "app_label": app_label,
        "foreground_seconds": seconds, "observed_at": observed_at,
    }).encode()
    request = Request(
        f"{BACKEND}/api/wellbeing/usage", data=payload, method="POST",
        headers={"Content-Type": "application/json", "X-Jarvis-Gateway-Token": TOKEN},
    )
    with urlopen(request, timeout=10) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"Jarvis returned HTTP {response.status}")


def main() -> None:
    print(f"Jarvis usage collection active for device {DEVICE_ID!r}. Ctrl+C stops it.")
    print("Only foreground app executable names and durations are collected.")
    current_id, current_label = foreground_app()
    started = time.monotonic()
    observed_at = datetime.now(timezone.utc).isoformat()
    try:
        while True:
            time.sleep(INTERVAL)
            app_id, app_label = foreground_app()
            if (app_id, app_label) != (current_id, current_label):
                elapsed = max(0, round(time.monotonic() - started))
                try:
                    if elapsed:
                        send(current_id, current_label, elapsed, observed_at)
                        print(f"Sent {current_label}: {elapsed}s")
                except (HTTPError, URLError, TimeoutError, RuntimeError) as exc:
                    print(f"Could not send usage summary (not stored locally): {exc}")
                current_id, current_label = app_id, app_label
                started = time.monotonic()
                observed_at = datetime.now(timezone.utc).isoformat()
    except KeyboardInterrupt:
        elapsed = max(0, round(time.monotonic() - started))
        if elapsed:
            try:
                send(current_id, current_label, elapsed, observed_at)
            except Exception as exc:
                print(f"Final report failed: {exc}")
        print("Jarvis usage collection stopped.")


if __name__ == "__main__":
    main()
