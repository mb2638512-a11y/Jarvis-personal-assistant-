#!/usr/bin/env python3
"""Vendor upstream projects into Jarvis with safe, auditable top-level branding."""
from __future__ import annotations
import json, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDORS = [
    {"path":"backend/vendor/atticus-windows","url":"https://github.com/FindlayHi/atticus-windows.git","label":"Jarvis Voice Assistant (upstream: Atticus)","old":"Atticus"},
    {"path":"backend/vendor/artemis","url":"https://github.com/google/artemis.git","label":"Jarvis Android Automation (upstream: ARTEMIS)","old":"ARTEMIS"},
    {"path":"backend/vendor/postiz-app","url":"https://github.com/gitroomhq/postiz-app.git","label":"Jarvis Social Publishing (upstream: Postiz)","old":"Postiz"},
]

def run(args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)

def main():
    for item in VENDORS:
        target = ROOT / item["path"]
        if target.exists():
            if (target / ".git").exists() or any(target.iterdir()):
                raise RuntimeError("Refusing to overwrite non-empty vendor path: " + item["path"])
            target.rmdir()
        target.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", item["url"], str(target)])
        upstream_readme = target / "README.md"
        if upstream_readme.exists():
            original = upstream_readme.read_text(encoding="utf-8", errors="replace")
            (target / "UPSTREAM_README.md").write_text(original, encoding="utf-8")
            match = re.search(r"(?m)^#\\s+(.+)$", original)
            upstream_title = match.group(1) if match else item["old"]
            upstream_readme.write_text(
                "# " + item["label"] + "\\n\\n"
                "Jarvis integration bundle containing upstream project source.\\n\\n"
                "**Upstream project:** " + upstream_title + "\\n"
                "**Upstream repository:** " + item["url"] + "\\n\\n"
                "Original licenses and copyright notices remain authoritative. See "
                "UPSTREAM_README.md and the included license files.\\n",
                encoding="utf-8")
        for package_file in (target / "package.json", target / "apps" / "frontend" / "package.json"):
            if package_file.is_file():
                try:
                    data = json.loads(package_file.read_text(encoding="utf-8"))
                    if isinstance(data, dict) and isinstance(data.get("name"), str):
                        data["jarvisUpstreamPackageName"] = data["name"]
                        if item["old"].lower() in data["name"].lower():
                            data["name"] = re.sub(item["old"], "jarvis", data["name"], flags=re.I)
                        package_file.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\\n", encoding="utf-8")
                except (json.JSONDecodeError, UnicodeDecodeError):
                    print("Skipped non-standard package metadata: " + str(package_file), file=sys.stderr)
        (target / "JARVIS_BRANDING.md").write_text(
            "# Jarvis branding and provenance\\n\\n"
            "Integrated as: **" + item["label"] + "**.\\n\\n"
            "Upstream source: " + item["url"] + "\\n\\n"
            "Branding is limited to the top-level README and safe package metadata. "
            "Internal symbols and protocol names remain unchanged to preserve compatibility. "
            "Keep all upstream licenses and attribution.\\n", encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
