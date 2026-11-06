# Jarvis Personal Assistant

A practical, security-first personal assistant project. This repository is the source of truth for code, tests, and build workflows.

## Repository branches
- `main`: shared backend, tests, documentation, CI and release workflow.
- `windows-app`: dedicated branch for the Windows desktop/host application.
- `android-app`: dedicated branch for the Android client.

## Honest status
The earlier visual prototype/source bundle is not present on the current clean branches. This feature branch is based on the preserved `backup/pre-cleanup-2026-10-26-main` branch so the previous backend source remains available while this integration is developed. The repository still does **not** contain a complete Android application or a production Windows installer.

## Current backend foundation
- FastAPI backend with an OpenAI-compatible chat endpoint (requires your own provider API key).
- Atticus-backed Windows device agent using vendored `winctl.py` through the typed remote task broker.
- Google ARTEMIS bridge for task submission/status against a separately hosted, private Android automation daemon.
- Postiz Public API adapter for channels, posts, media URL import, next scheduling slots, and channel/post analytics.
- Postiz credentials stay server-side; action routes require a separate gateway token.
- Explicit configuration through environment variables; secrets are not committed.
- Unit tests for configuration, safe failure behavior, mocked Postiz API requests, and the ARTEMIS bridge.
- GitHub Actions CI workflow for the Python test suite.

## Windows PC host (recommended first deployment)\n\nThe main Windows PC can run Jarvis locally as the first control center. Run `scripts/install-windows-host.ps1`, configure `.env`, then start `scripts/start-windows-host.ps1` and `scripts/start-windows-agent.ps1` in separate PowerShell windows. The API binds to localhost only. For other devices, use a private HTTPS network such as Tailscale Serve; see [Windows PC Host Setup](docs/WINDOWS_PC_HOST_SETUP.md).\n\nThe current multi-device broker still uses a shared gateway token; one-time pairing links, per-device credentials, and revocation controls are not implemented yet. Do not share the token with untrusted devices.\n\n## Quick start (backend)
Python 3.11+
```bash
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
pip install -e ".[dev]"
# Copy .env.example to .env and configure the providers you use.
uvicorn jarvis_api.main:app --reload
```

Open `http://127.0.0.1:8000/docs` for the OpenAPI interface. Never put provider API keys or the Postiz gateway token in frontend code or commit them.

## API
- `GET /health`: process health only.
- `GET /status`: AI provider configuration status.
- `POST /api/chat`: OpenAI-compatible chat endpoint.
- `GET /api/postiz/status`: Postiz configuration status only; does not claim a live connection.
- `GET /api/postiz/channels`: list Postiz integrations.
- `GET /api/postiz/posts?startDate=<ISO>&endDate=<ISO>`: list posts.
- `POST /api/postiz/posts`: create a draft, schedule a post, or publish immediately when `type: "now"` is explicitly requested.
- `DELETE /api/postiz/posts/{id}`: delete a Postiz post/group.
- `POST /api/postiz/upload-from-url`: import HTTPS media via Postiz.
- `GET /api/postiz/find-slot/{integration_id}`: get the next scheduling slot.
- `GET /api/postiz/analytics/{integration_id}` and `GET /api/postiz/analytics/post/{id}`: analytics.

See [three-engine runtime integration](docs/THREE_REPO_RUNTIME_INTEGRATION.md), [Postiz integration guide](docs/POSTIZ_INTEGRATION.md), and [shared client API contract](docs/JARVIS_CLIENT_API.md). The complete phased delivery and acceptance checklist is in [End-to-end integration programme](docs/END_TO_END_INTEGRATION_PROGRAMME.md). Protected Postiz action routes require `X-Jarvis-Postiz-Token`. Until Jarvis user authentication and per-user permissions exist, keep them on a trusted network or behind an authenticated private gateway; do not embed this token in Android or Windows clients.

## Verification and releases
- CI workflow: [Jarvis backend CI](.github/workflows/ci.yml).
- Existing platform release workflow: [Platform Release](.github/workflows/platform-release.yml).
- A successful mocked test suite does not prove that a live Postiz instance, social account, or real publishing operation is connected.
- Android source migration and a genuine Windows installer remain separate unfinished tasks; no APK or EXE is claimed by this backend integration.

## Next steps
1. Configure Postiz credentials in the deployment secret store.
2. Run the Windows device agent on the paired PC and verify its heartbeat/task result.
3. Configure a private ARTEMIS host with an attached Android device and verify `/api/artemis/status`.
4. Verify a protected `GET /api/postiz/channels` request against a non-production Postiz workspace.
5. Add Jarvis sign-in and per-user authorization before exposing remote actions to public clients.


## Personal insights: usage, wellbeing and security

- Android and shared web frontend now include an opt-in insights dashboard for app-use summaries, wellbeing check-ins, and client-reported security events.
- Private API routes are under `/api/wellbeing`; they require `X-Jarvis-Gateway-Token` and `JARVIS_REMOTE_GATEWAY_TOKEN` on the backend.
- `scripts/windows-usage-collector.py` is an opt-in Windows foreground-app timer. It reports executable names and durations only, not window titles or keystrokes.
- Important: the Android Usage Access collector is **not implemented yet**. The Android dashboard can display submitted records, but does not automatically read phone usage until a native collector is built and permissioned.
- Individual reels watched inside Instagram/YouTube/TikTok cannot be reliably inferred from Android app screen time. Reel counts stay unknown unless a reliable source explicitly reports them.
- Health is voluntary journaling, not medical advice or diagnosis. Security events are reports, not a full antivirus scan.
- Read [Personal Insights implementation and privacy notes](docs/PERSONAL_INSIGHTS.md) and open the [Device Health dashboard](web/device-health.html). The Windows hardware reporter is `scripts/windows-device-health.py`; it submits CPU/RAM/disk/battery/network metrics to `/api/wellbeing/device-metrics`. Device security reports are accepted by `/api/wellbeing/device-security` when a client submits them. The current Windows reporter does not yet submit security-posture reports. Shared-secret auth is an initial private-network safeguard, not a replacement for user accounts and per-device authorization.


## Command Center UI (in development)

- The primary Flutter app screen is the responsive Jarvis Command Center for Android and Windows.
- The desktop/mobile web reference is available at [web/command-center.html](web/command-center.html).
- The dashboard reads the shared PC backend health, AI provider status, integrations status and ARTEMIS status endpoints. It displays an unverified/offline state when the backend cannot be reached; it does not fabricate CPU, RAM, agent, model or memory metrics.
- Quick actions open the existing chat, pairing, model hub, device health, ARTEMIS, Postiz and integration workspaces.
- The Command Center branch has not yet passed a GitHub Actions build. Do not treat the source commit as a signed installer or production release.
