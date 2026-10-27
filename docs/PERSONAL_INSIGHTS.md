# Jarvis personal insights: usage, wellbeing and security

The shared FastAPI backend exposes private, opt-in endpoints for Android and Windows clients. Records are stored in `data/wellbeing.sqlite3`.

## Private API

All endpoints require `X-Jarvis-Gateway-Token` matching the server's `JARVIS_REMOTE_GATEWAY_TOKEN`. If the secret is not configured, the endpoints return HTTP 503; an invalid token returns HTTP 401.

- `POST /api/wellbeing/usage`: submit a device/app foreground-duration record. Body: `device_id`, `platform` (`android` or `windows`), `app_id`, `app_label`, `foreground_seconds`; optional `reels_count` only when the client has a genuine source for it.
- `GET /api/wellbeing/usage?device_id=<id>&days=7`: app totals, samples and known client-reported reel counts.
- `POST /api/wellbeing/checkins` / `GET /api/wellbeing/checkins?device_id=<id>`: voluntary mood, energy, sleep-hours and journal notes.
- `POST /api/wellbeing/security-events` / `GET /api/wellbeing/security-events?device_id=<id>`: security events reported by a connected client.

The Windows opt-in foreground-app collector is `scripts/windows-usage-collector.py`. It records executable names and time only; it does not collect window titles, keystrokes, screenshots or content. Configure `JARVIS_BACKEND_URL`, `JARVIS_REMOTE_GATEWAY_TOKEN`, and `JARVIS_DEVICE_ID`, then run it on the user's own Windows account.

## Important limitations

- The Android Flutter screen and shared web dashboard display received data; they do not magically obtain OS usage data. A native Android Usage Access collector still needs to be implemented, permissioned by the device owner, and tested on a real phone.
- Android's standard UsageStats permission can measure time spent in an app, but does not expose the count of individual reels watched inside Instagram, YouTube or TikTok. Those counts remain unknown unless an authorized, reliable data source actually reports them.
- Security entries are client-reported events, not proof of a full antivirus scan. No blanket malware-detection claim is made.
- Health check-ins are private journaling only—not diagnosis, treatment advice, emergency monitoring or medical records.
- This initial version uses one shared gateway secret. Do not expose these endpoints publicly until Jarvis user sign-in, per-device credentials, user-scoped authorization, retention/deletion controls and rate limiting are implemented. Use HTTPS for remote connections.
