# Jarvis local-first device architecture

## Goal
Android and Windows should run device health and security-insight features on the device that owns the data. Those local features must not require a separately hosted Jarvis server. The same Flutter UI and API/data contract should be shared across both platforms.

## What is implemented on the current `android` branch
- Android device metrics are read through the native Android MethodChannel and displayed locally without a gateway token or network upload.
- Windows hardware telemetry can run in local-only mode. Leave both `JARVIS_BACKEND_URL` and `JARVIS_REMOTE_GATEWAY_TOKEN` unset to print local readings without sending network requests.
- Shared-backend sync is optional: set both variables, and use HTTPS for a remote backend. HTTP is allowed only for exact localhost/127.0.0.1.
- The existing FastAPI wellbeing API remains available for users who explicitly want multi-device sync.

## Important platform boundaries
- A device-local feature is not a cloud backend. The app can read supported hardware and store/display local information without a server.
- AI chat still needs an inference engine: either a separately installed local model/runtime supported by the device, or an external model API. Social-network OAuth/publishing also requires those providers and their remote APIs. The app must not pretend those features work offline when no provider is configured.
- Android does not expose unrestricted system security/antivirus status to ordinary apps. Unknown checks must remain unknown; the dashboard must not claim the phone is virus-free.
- Windows local hardware monitoring is currently a Python collector, not yet a packaged Windows GUI/installer. It requires Python and the project dependencies. A true single-installer Windows build and fully integrated local Windows UI are still required before claiming install-and-go parity.
- Current Android metrics are RAM/storage/battery; Android CPU load is not collected. Android Usage Access is separate and requires explicit permission.

## Security requirements for the full cross-platform app
1. Keep all device telemetry local by default; show a clear opt-in before sync.
2. Do not ship a shared server gateway secret in the Android APK or Windows binary.
3. If sync is enabled, authenticate users and bind each device to its own revocable credential; enforce device ownership on every read/write.
4. Store local secrets using Android Keystore / Windows Credential Manager or DPAPI, not plain-text config.
5. Use HTTPS for remote traffic, bounded timeouts, request validation, and redacted logs.
6. Keep security posture reports as client-reported observations, not proof of device integrity.
7. Test Android and Windows builds independently; only publish installers after CI succeeds.

## Local-only Windows monitor
From a Python 3.11+ environment with the project dependencies installed, run:
```powershell
python scripts/windows-device-health.py
```
It prints local snapshots and does not connect to a server when both sync environment variables are unset. Press Ctrl+C to stop. To enable optional sync, configure both environment variables in the current session and restart the script.
