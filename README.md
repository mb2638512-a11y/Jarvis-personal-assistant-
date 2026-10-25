# Jarvis Personal Assistant

A practical, security-first personal assistant project. This repository is the source of truth for code, tests, and build workflows.

## Honest status
The repository initially contained only this README. The earlier visual prototype/source bundle is not present in this Git repository, so it has **not** been migrated here yet. This commit establishes a real backend foundation and CI checks; it does not claim that Android-to-Windows control or a finished mobile app already works.

## Current foundation
- FastAPI backend with an OpenAI-compatible chat endpoint (requires your own provider API key).
- Explicit configuration through environment variables; secrets are not committed.
- Unit tests for configuration and safe failure behavior.
- GitHub Actions for Python tests and security/dependency checks.

## Quick start (backend)
Python 3.11+
```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
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

## Roadmap
1. Recover and migrate the prior app source into this repo.
2. Build the app UI against this real API; remove fake connection indicators.
3. Add authenticated Windows host pairing and a permission-limited command protocol.
4. Add Android and Windows CI builds after the real client source is present.
5. Verify each feature with tests and device-level checks before marking it working.

## Safety
Remote PC actions must be explicitly paired, authenticated, permission-scoped, logged, and require confirmation for sensitive actions. Do not expose the Windows control agent directly to the public internet.