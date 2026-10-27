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
- Postiz Public API adapter for channels, posts, media URL import, next scheduling slots, and channel/post analytics.
- Postiz credentials stay server-side; action routes require a separate gateway token.
- Explicit configuration through environment variables; secrets are not committed.
- Unit tests for configuration, safe failure behavior, and mocked Postiz API requests.
- GitHub Actions CI workflow for the Python test suite.

## Quick start (backend)
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

See [Postiz integration guide](docs/POSTIZ_INTEGRATION.md) and [shared client API contract](docs/JARVIS_CLIENT_API.md). Protected Postiz action routes require `X-Jarvis-Postiz-Token`. Until Jarvis user authentication and per-user permissions exist, keep them on a trusted network or behind an authenticated private gateway; do not embed this token in Android or Windows clients.

## Verification and releases
- CI workflow: [Jarvis backend CI](.github/workflows/ci.yml).
- Existing platform release workflow: [Platform Release](.github/workflows/platform-release.yml).
- A successful mocked test suite does not prove that a live Postiz instance, social account, or real publishing operation is connected.
- Android source migration and a genuine Windows installer remain separate unfinished tasks; no APK or EXE is claimed by this backend integration.

## Next steps
1. Configure Postiz credentials in the deployment secret store.
2. Run CI and verify a protected `GET /api/postiz/channels` request against a real Postiz workspace.
3. Add Jarvis sign-in and per-user authorization before exposing social actions to remote clients.
4. Wire both Android and Windows clients to the shared backend API and test each platform build.


## Personal insights: usage, wellbeing and security

- Android and shared web frontend now include an opt-in insights dashboard for app-use summaries, wellbeing check-ins, and client-reported security events.
- Private API routes are under `/api/wellbeing`; they require `X-Jarvis-Gateway-Token` and `JARVIS_REMOTE_GATEWAY_TOKEN` on the backend.
- `scripts/windows-usage-collector.py` is an opt-in Windows foreground-app timer. It reports executable names and durations only, not window titles or keystrokes.
- Important: the Android Usage Access collector is **not implemented yet**. The Android dashboard can display submitted records, but does not automatically read phone usage until a native collector is built and permissioned.
- Individual reels watched inside Instagram/YouTube/TikTok cannot be reliably inferred from Android app screen time. Reel counts stay unknown unless a reliable source explicitly reports them.
- Health is voluntary journaling, not medical advice or diagnosis. Security events are reports, not a full antivirus scan.
- Read [Personal Insights implementation and privacy notes](docs/PERSONAL_INSIGHTS.md). Shared-secret auth is an initial private-network safeguard, not a replacement for user accounts and per-device authorization.
