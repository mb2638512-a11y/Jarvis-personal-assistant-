"""Opt-in Windows hardware telemetry reporter for Jarvis.

Install psutil with pip. Reports aggregate CPU, RAM, system-disk, battery and
network counters, plus process names/resource use. Does not inspect file contents,
keystrokes, window titles, or control the device.
"""
import json
import os
import platform
import time
from datetime import datetime, timezone
from urllib.request import Request, urlopen

import psutil

if platform.system() != "Windows":
    raise SystemExit("Windows only")
BASE = os.environ.get("JARVIS_BACKEND_URL", "").rstrip("/")
TOKEN = os.environ.get("JARVIS_REMOTE_GATEWAY_TOKEN", "")
DEVICE = os.environ.get("JARVIS_DEVICE_ID", "my-windows")
INTERVAL = max(10, min(int(os.environ.get("JARVIS_HEALTH_INTERVAL_SECONDS", "30")), 300))
if not (BASE.startswith("https://") or BASE.startswith("http://localhost") or BASE.startswith("http://127.0.0.1")):
    raise SystemExit("Use HTTPS for remote backend; HTTP only for localhost.")
if not TOKEN:
    raise SystemExit("Set JARVIS_REMOTE_GATEWAY_TOKEN in environment.")

def collect():
    vm = psutil.virtual_memory()
    root = os.environ.get("SystemDrive", "C:") + "\\"
    disk = psutil.disk_usage(root)
    battery = psutil.sensors_battery()
    net = psutil.net_io_counters()
    processes = []
    for proc in psutil.process_iter(["name", "cpu_percent", "memory_info"]):
        try:
            p = proc.info
            memory = p.get("memory_info")
            processes.append({
                "name": (p.get("name") or "unknown")[:100],
                "cpu_percent": float(p.get("cpu_percent") or 0),
                "memory_bytes": int(memory.rss) if memory else 0,
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
    processes.sort(key=lambda item: item["memory_bytes"], reverse=True)
    return {
        "device_id": DEVICE, "platform": "windows",
        "cpu_percent": psutil.cpu_percent(interval=1),
        "memory_percent": vm.percent, "memory_used_bytes": vm.used,
        "memory_total_bytes": vm.total, "disk_percent": disk.percent,
        "disk_free_bytes": disk.free,
        "battery_percent": battery.percent if battery else None,
        "battery_plugged": battery.power_plugged if battery else None,
        "network_sent_bytes": net.bytes_sent, "network_received_bytes": net.bytes_recv,
        "top_processes": processes[:10], "observed_at": datetime.now(timezone.utc).isoformat(),
    }

def main():
    print("Jarvis hardware monitoring active; Ctrl+C stops it.")
    while True:
        try:
            body = json.dumps(collect()).encode()
            req = Request(BASE + "/api/device-health/metrics", data=body, method="POST",
                headers={"Content-Type":"application/json","X-Jarvis-Gateway-Token":TOKEN})
            with urlopen(req, timeout=12) as response:
                print(datetime.now().isoformat(timespec="seconds"), "report sent", response.status)
        except Exception as exc:
            print("Hardware report failed:", exc)
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
