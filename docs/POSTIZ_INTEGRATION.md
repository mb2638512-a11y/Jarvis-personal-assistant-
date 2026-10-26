# Jarvis ↔ Postiz integration

This adds a server-side adapter for Postiz's Public API. It does not create social accounts, grant platform approvals, or claim a live Postiz connection until credentials and a real account are configured.

## Configuration

Copy `.env.example` to `.env` and set:

- `JARVIS_POSTIZ_API_KEY`: Postiz API key/token. It is sent in the upstream `Authorization` header without adding a `Bearer ` prefix.
- `JARVIS_POSTIZ_BASE_URL`: Cloud default is `https://api.postiz.com/public/v1`. For self-hosting, use `https://your-postiz-host/api/public/v1`.
- `JARVIS_POSTIZ_GATEWAY_TOKEN`: long random secret required by the Jarvis client when calling any action route. Keep it server-side; do not bake it into a public mobile/desktop app. Until Jarvis user authentication and per-user authorization are added, expose these routes only on a trusted network or behind an authenticated gateway.
- `JARVIS_POSTIZ_TIMEOUT_SECONDS`: upstream timeout (default 20 seconds).

The Postiz key and gateway token must never be committed or returned by API endpoints.

## Routes

- `GET /api/postiz/status`: configuration status only; never sends a request to Postiz.
- `GET /api/postiz/channels`: lists Postiz integrations/channels.
- `GET /api/postiz/posts?startDate=<ISO>&endDate=<ISO>[&customer=<id>]`: lists posts in the requested date range.
- `POST /api/postiz/posts`: creates a draft, schedules a post, or explicitly publishes now. Body follows Postiz's Public API shape: `type` is `draft`, `schedule`, or `now`; scheduled posts require `date`; `posts` identifies each integration/channel, content values, and provider-specific settings.
- `DELETE /api/postiz/posts/{post_id}`: deletes the selected Postiz post/group.
- `POST /api/postiz/upload-from-url`: asks Postiz to import an HTTPS media URL.
- `GET /api/postiz/find-slot/{integration_id}`: asks Postiz for the next scheduling slot.
- `GET /api/postiz/analytics/{integration_id}`: channel analytics, optionally with `startDate` and `endDate`.
- `GET /api/postiz/analytics/post/{post_id}`: analytics for a post.

Every action route requires `X-Jarvis-Postiz-Token: <JARVIS_POSTIZ_GATEWAY_TOKEN>`. The backend deliberately does not make the Postiz credential available to Android or Windows clients. The current scaffold has no user sign-in/authorization layer, so do not expose action routes directly to the public internet.

## Verification

Unit tests mock the Postiz HTTP boundary and verify request routing, raw Authorization header behavior, missing configuration, gateway authentication, schedule validation, HTTPS enforcement, analytics/slot routing, and upstream error redaction. These are deterministic tests, not a live credential or social publishing test.

## Official references

- https://docs.postiz.com/public-api
- https://docs.postiz.com/self-host/installation/overview
- https://github.com/gitroomhq/postiz-app (AGPL-3.0)
