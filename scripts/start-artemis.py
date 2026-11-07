"""Launch the vendored ARTEMIS daemon using the encrypted PC-side Google key."""
from __future__ import annotations

import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARTEMIS_ROOT = ROOT / "backend" / "vendor" / "artemis"


def main() -> int:
    config_path = ROOT / "data" / "integration_vault.sqlite3"
    if not config_path.exists():
        print("ARTEMIS is not configured. Add its host URL, gateway token and Google Gemini API key in Jarvis PC Integration Setup.")
        return 0

    sys.path.insert(0, str(ROOT))
    from jarvis_api.integration_vault import get_integration_config

    config = get_integration_config("artemis") or {}
    google_key = config.get("google_api_key", "").strip()
    if not google_key:
        print("ARTEMIS start skipped: add a Google Gemini API key in Jarvis PC Integration Setup.")
        return 0

    try:
        with urllib.request.urlopen("http://127.0.0.1:8765/api/status", timeout=2) as response:
            if 200 <= response.status < 300:
                print("ARTEMIS daemon is already responding on localhost:8765.")
                return 0
    except (urllib.error.URLError, TimeoutError):
        pass

    if not (ARTEMIS_ROOT / "scripts" / "start.ps1").is_file():
        print("ARTEMIS upstream startup script is missing from the vendored source.")
        return 2

    lock_path = ROOT / "data" / "artemis-start.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if lock_path.exists():
        if lock_path.stat().st_mtime > time.time() - 1200:
            print("ARTEMIS setup is already running in the background.")
            return 0
        lock_path.unlink(missing_ok=True)
    try:
        with lock_path.open("x", encoding="utf-8") as lock:
            lock.write(str(os.getpid()))
    except FileExistsError:
        print("ARTEMIS setup is already running.")
        return 0

    env = os.environ.copy()
    env["GOOGLE_API_KEY"] = google_key
    env["GEMINI_API_KEY"] = google_key
    env["ADB_HOST"] = "127.0.0.1"
    env["ADB_PORT"] = "5037"
    print("Starting the private ARTEMIS daemon. First startup may download Python packages, ADB tools and the Showcase UI.")
    command = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ARTEMIS_ROOT / "scripts" / "start.ps1"),
        "-Port",
        "8765",
        "-NoOpen",
    ]
    try:
        completed = subprocess.run(command, cwd=ARTEMIS_ROOT, env=env, check=False)
        return completed.returncode
    finally:
        lock_path.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
