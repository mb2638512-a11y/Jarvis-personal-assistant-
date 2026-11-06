# Three upstream integrations: actual runtime wiring

Updated: 2026-11-06

Jarvis uses its own clients and backend. These upstream projects are engines, not replacement Jarvis frontends.

## 1. Atticus Windows — paired local device agent

**Upstream:** https://github.com/FindlayHi/atticus-windows

Jarvis now has `windows/jarvis_device_agent.py`. It imports the vendored Atticus `winctl.py` Windows primitives and polls the Jarvis typed task broker. The agent supports the current allow-listed operations:

- Open HTTPS URL
- Launch a small allow-list of Windows applications
- Type user-confirmed text into the focused window (clipboard is restored by the Atticus helper)
- Press user-confirmed allow-listed keys
- Return device status
- Capture the primary display

It does **not** run Atticus's Claude Code CLI, execute natural-language shell commands, or accept arbitrary PowerShell/shell payloads. This is deliberate: the upstream Atticus interactive assistant depends on Claude Code and its own command toolchain; Jarvis routes actions through its own typed broker and model/provider settings.

### Run on the Windows PC

Install Python 3.11+, then from the Jarvis repository root:

```powershell
python -m pip install -e ".[windows-agent]"
$env:JARVIS_BASE_URL="https://YOUR-JARVIS-HOST"
$env:JARVIS_REMOTE_GATEWAY_TOKEN="YOUR_SERVER_SIDE_REMOTE_TOKEN"
$env:JARVIS_AGENT_ID="mustafa-pc"
python windows/jarvis_device_agent.py
```

For local development, `http://127.0.0.1:8000` is permitted. Do not send the remote gateway token over public plain HTTP. Keep the remote broker behind a private gateway/VPN until first-party user/device authentication replaces the shared gateway token.

The agent must be running on the Windows PC for actions to execute. A successful task enqueue alone is not proof of execution; check `GET /api/remote/tasks/{task_id}`.

## 2. Google ARTEMIS — private Android automation host

**Upstream:** https://github.com/google/artemis

ARTEMIS is a separate Python 3.12+ Android device host with an ADB-connected phone/emulator, its own agent runtime, and its own model/provider configuration. It is not an Android SDK that can simply be imported into the Flutter APK.

Jarvis now has a server-side bridge:

- `GET /api/artemis/status` probes the configured ARTEMIS daemon and lists its attached devices.
- `POST /api/artemis/tasks` submits a task to `POST /api/run`.
- `GET /api/artemis/tasks/{task_id}` reads the upstream session result.

The submit route requires `X-Jarvis-Artemis-Token` and `user_confirmed: true`. The bridge forwards the ARTEMIS host bearer token server-side; it never exposes that token to Android or Windows clients.

### Configure

```env
JARVIS_ARTEMIS_BASE_URL=https://YOUR-PRIVATE-ARTEMIS-HOST
JARVIS_ARTEMIS_GATEWAY_TOKEN=YOUR_LONG_RANDOM_JARVIS_GATEWAY_TOKEN
JARVIS_ARTEMIS_TIMEOUT_SECONDS=30
```

Important: ARTEMIS documentation warns that its daemon administration API should not be exposed directly to the public internet. Put it behind a private VPN/tunnel or an authenticated HTTPS reverse proxy that validates the bearer token. The Jarvis bridge's token header alone does not magically add authentication to an unprotected ARTEMIS daemon.

The ARTEMIS host also needs its own runtime dependencies, Android platform tools/ADB, connected device, and model-provider credentials. Jarvis does not silently install or configure these host-side requirements.

## 3. Postiz — server-side social publishing

**Upstream:** https://github.com/gitroomhq/postiz-app

The existing Jarvis FastAPI adapter in `jarvis_api/postiz.py` talks to the Postiz Public API for integrations/channels, posts, scheduling, deletion, media URL import, and analytics. OAuth account authorization remains on the Postiz workspace. API credentials and the Jarvis action token stay server-side.

Required environment:

```env
JARVIS_POSTIZ_API_KEY=...
JARVIS_POSTIZ_BASE_URL=https://api.postiz.com/public/v1
JARVIS_POSTIZ_GATEWAY_TOKEN=...
JARVIS_POSTIZ_APP_URL=https://YOUR-POSTIZ-WORKSPACE
```

Mocked API tests are not proof of a live account connection. Verify with a protected channels request against a non-production workspace before publishing. Keep the Postiz action routes private until Jarvis user sign-in, per-user authorization, and workspace mapping are implemented.

## Shared integration status

- `GET /api/integrations/status` reports source presence, required configuration, and the Windows agent heartbeat.
- `GET /api/artemis/status` performs the ARTEMIS upstream live probe.
- `GET /api/postiz/status` reports configuration only; a protected channels request is required to verify live Postiz connectivity.

## Safety and distribution

- No arbitrary shell/PowerShell command execution is exposed by the Windows device agent.
- Text entry and key presses require explicit confirmation before the broker accepts the task.
- Device agents should use HTTPS; localhost HTTP is allowed only for local development.
- Never put provider API keys, Postiz credentials, ARTEMIS credentials, or remote gateway tokens in a public client build.
- Preserve upstream license files and attribution. Postiz is AGPL-3.0; review distribution obligations before shipping a combined product.
- A source checkout or passing mocked tests does not mean the three upstream runtimes are installed or live-connected.
