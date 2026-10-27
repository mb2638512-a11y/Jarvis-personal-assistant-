# Jarvis end-to-end verification checklist

## Checkout all upstream sources

The three upstream repositories are vendored as ordinary source files in the Jarvis Git tree. A normal clone is sufficient; do not use submodule commands:

```bash
git clone --branch feature/vendor-three-repos https://github.com/mb2638512-a11y/Jarvis-personal-assistant-.git
cd Jarvis-personal-assistant-
```

## Start self-hosted Postiz

Requirements: Docker Engine/Desktop and a machine with enough memory/storage for Postiz's services.

- Linux/macOS: `bash scripts/run-postiz.sh`
- Windows PowerShell: `./scripts/run-postiz.ps1`

The scripts run the upstream Postiz Docker Compose definition from `backend/vendor/postiz-app/docker-compose.yaml`. Review upstream environment settings, persistent volumes, default credentials and network exposure before using it outside a development machine. Do not expose Postiz or Jarvis action routes publicly without TLS, strong authentication, per-user authorization and firewall restrictions.

Set Jarvis's server-side `JARVIS_POSTIZ_BASE_URL` to the URL of the self-hosted Postiz Public API (normally `https://your-host/api/public/v1`; for local development, use the actual port and path configured by Postiz). Configure `JARVIS_POSTIZ_API_KEY` and a high-entropy `JARVIS_POSTIZ_GATEWAY_TOKEN` only in the backend environment/secrets store. Never put these values in Android, Windows, or web client bundles.

## Automated checks

From the Jarvis repository root:

```bash
python -m pip install -e ".[dev]"
ruff check jarvis_api tests windows
pytest -q
```

Flutter app checks (when Flutter SDK is installed and the Flutter client is in the checkout):

```bash
flutter analyze
flutter test
flutter build apk --release
```

Windows executable builds are verified by the repository's GitHub Actions workflow. A successful build proves packaging, not successful sign-in, live API connectivity, platform permission flows, or production installer behavior.

## Required live acceptance tests before calling this production-ready

- [ ] Verify the three submodule commit SHAs and review upstream licenses/security advisories.
- [ ] Start Postiz and confirm its health/readiness endpoint and persistent storage.
- [ ] From the Jarvis backend, call protected `GET /api/postiz/channels` with a real server-side API key and gateway token.
- [ ] Verify invalid/missing gateway tokens are rejected and credentials never appear in logs or client responses.
- [ ] Create a **draft** first; verify it appears in Postiz. Do not test publishing to a real social account without explicit operator approval.
- [ ] Test schedule, media import, deletion and analytics against a disposable/test workspace.
- [ ] Test Jarvis chat/config/status and Postiz actions on Android and Windows through the same backend; keep secrets server-side.
- [ ] Test backend restart, Postiz restart, timeouts, upstream 4xx/5xx, and database persistence.
- [ ] Complete platform-specific authorization, accessibility, networking and release-signing checks.

## Current known limits

The upstream source trees are vendored in the Jarvis Git tree, with upstream attribution and licenses retained. The API adapter's unit tests are mocked; they do not prove a live Postiz workspace is connected. The shared integration status endpoint deliberately reports live connections as false until device agents/task transport and real Postiz credentials are configured and verified. Live acceptance checks require real devices, a deployed Postiz instance and valid credentials, which must not be fabricated or committed.
