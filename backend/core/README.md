# Jarvis Shared Backend API

Initial Python/FastAPI scaffold shared by Android and Windows clients.

## Run locally
```bash
python -m venv .venv
# Windows PowerShell: .venv\\Scripts\\Activate.ps1
# Android/Termux/Linux: source .venv/bin/activate
pip install -r backend/requirements.txt
uvicorn backend.core.app:app --host 127.0.0.1 --port 8443
```

Open `http://127.0.0.1:8443/docs` for the development API docs.

## Current endpoints
- `GET /api/v1/health`
- `GET /api/v1/capabilities?platform=android|windows`
- `POST /api/v1/tasks` with `Idempotency-Key`
- `GET /api/v1/tasks/{taskId}`
- `POST /api/v1/tasks/{taskId}/cancel`

## Not production-ready yet
This scaffold only validates API flow and stores task state in memory. It does not execute tasks, persist state, authenticate users, or implement Android/Windows adapters. Platform capabilities are deliberately marked unsupported until real adapters and permission checks exist. Do not expose this service to the public internet before adding authentication, durable storage, TLS, rate limits, audit logging, and security tests.
