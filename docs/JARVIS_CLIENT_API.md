# Jarvis shared client API contract

Android and Windows clients should call the same Jarvis backend; they must not call Postiz directly or store the Postiz API key.

- Health: `GET /health`
- AI configuration status: `GET /status`
- Chat: `POST /api/chat` with `{"message":"..."}`
- Postiz status: `GET /api/postiz/status`
- Protected Postiz actions: `GET /api/postiz/channels`, `GET /api/postiz/posts?startDate=<ISO>&endDate=<ISO>`, `POST /api/postiz/posts`, `DELETE /api/postiz/posts/{id}`, `POST /api/postiz/upload-from-url`, `GET /api/postiz/find-slot/{integration_id}`, `GET /api/postiz/analytics/{integration_id}`, and `GET /api/postiz/analytics/post/{post_id}`.

Postiz action requests currently require the server-side gateway token in `X-Jarvis-Postiz-Token`. Do not embed that token in a shipped app. Before enabling remote mobile/desktop publishing, implement Jarvis user authentication, per-user permissions, and server-side session-to-workspace mapping, or put the routes behind an authenticated private gateway. Schedule first and review the queue; use `type: "now"` only when immediate publishing is explicitly requested.
