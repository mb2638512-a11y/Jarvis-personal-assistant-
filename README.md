# Jarvis Personal Assistant

A practical, security-first personal assistant project. This repository is the source of truth for code, tests, and build workflows.

## Repository branches
- `main`: shared backend, tests, documentation, CI and release workflow.
- `windows-app`: dedicated branch for the Windows desktop/host application.
- `android-app`: dedicated branch for the Android client.

## Honest status
The earlier visual prototype/source bundle is not present in this Git repository, so it has **not** been migrated here yet. The current code is a real FastAPI backend foundation; it is not yet a complete Android or Windows application. Do not treat the backend source ZIP as a Windows installer or an APK.

## Current foundation
- FastAPI backend with an OpenAI-compatible chat endpoint (requires your own provider API key).
- Explicit configuration through environment variables; secrets are not committed.
- Unit tests for configuration and safe failure behavior.
- GitHub Actions for Python tests and a platform release workflow.

## Quick start (backend)
Python 3.11+
```bash
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
pip install -e ".[dev]"
# Copy .env.example to .env, then set JARVIS_API_KEY and JARVIS_MODEL.
uvicorn jarvis_api.main:app --reload
```
Open `http://127.0.0.1:8000/docs`. Configure `JARVIS_API_KEY` and `JARVIS_MODEL` in your environment or .env file to enable live AI responses. Never put API keys in frontend code or commit them.

## API
- `GET /health`: process health only; does not pretend the AI provider is connected.
- `GET /status`: reports whether provider configuration is present, not whether a successful live request has occurred.
- `POST /api/chat`: sends a user message to the configured OpenAI-compatible chat-completions endpoint.

## Build and releases
- Workflow: [Platform Release](.github/workflows/platform-release.yml)
- Run it manually from **Actions → Jarvis Windows and Android Release → Run workflow** to build available artifacts.
- On a `v*` tag, it attempts to publish a GitHub Release with downloadable assets.
- Until the real Android source is migrated, the workflow deliberately reports that no APK can be built. The Windows output is backend source, not a native Windows installer.

## Roadmap
1. Recover and migrate the prior app source into this repo.
2. Build the app UI against this real API; remove fake connection indicators.
3. Add authenticated Windows host pairing and a permission-limited command protocol.
4. Build and test genuine Android APK and Windows desktop installer, then publish both as release assets.
