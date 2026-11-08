# Three-repository integration report

Updated: 2026-11-06

## Upstream source snapshots

The following source trees are tracked inside Jarvis under `backend/vendor/`. They are ordinary copied source snapshots, not Git submodules. Each retains its upstream license and attribution.

| Project | Upstream | Jarvis runtime integration |
|---|---|---|
| Atticus Windows | https://github.com/FindlayHi/atticus-windows | `windows/jarvis_device_agent.py` imports the vendored Windows control primitives and executes typed, allow-listed actions through `/api/remote`. |
| Google ARTEMIS | https://github.com/google/artemis | `jarvis_api/artemis.py` submits and retrieves tasks from a separately running, private ARTEMIS daemon. |
| Postiz | https://github.com/gitroomhq/postiz-app | `jarvis_api/postiz.py` calls the Postiz Public API for channel, post, scheduling, upload, and analytics operations. |

## What is now connected in code

- The Windows device agent registers and heartbeats against the Jarvis task broker, polls typed tasks, executes through vendored Atticus `winctl.py` primitives, and reports completion. This is not yet the full Atticus conversational brain.
- The ARTEMIS bridge validates paired-device or PC-admin authentication and explicit user confirmation, then forwards tasks to ARTEMIS `/api/run` and reads `/api/sessions/{id}`. The Android client has a task UI; the daemon still needs installation/startup and a physical ADB device test.
- The Postiz adapter remains server-side; its API key and action token are not sent to clients. A live Postiz workspace and publishing round-trip are not yet verified.
- `GET /api/integrations/status` reports source/configuration/Windows-agent readiness without treating a copied source tree as a live connection.
- `docs/THREE_REPO_RUNTIME_INTEGRATION.md` contains setup and security boundaries.

## What still requires the user's infrastructure

- Run `windows/jarvis_device_agent.py` on the Windows PC and set the Jarvis backend URL plus remote gateway token.
- Run the ARTEMIS host separately with Python 3.12+, its dependencies, ADB/platform tools, an attached Android phone/emulator, and its own model-provider credentials. Keep the daemon behind a private VPN/tunnel or authenticated HTTPS reverse proxy; do not expose its admin API publicly.
- Configure Postiz workspace/API credentials and verify a protected channels request against a non-production workspace.
- Complete first-party Jarvis user/device authentication and per-user authorization before exposing remote actions or social publishing to the public internet.

## Verification

CI now runs Python tests/compile, backend-focused lint, and Flutter builds for Android APK and Windows installer on the PC-first integration PR. Previous backend run passed 61 tests; the latest approval-gate changes are awaiting a fresh run. A passing mocked test suite proves the adapter contract only; it does not prove that a Windows PC, ARTEMIS Android device, or Postiz account is online.

## Security and licensing

- The Windows agent never accepts arbitrary shell or PowerShell commands.
- Typing and key presses require explicit user confirmation in the broker request.
- Device agents require HTTPS except for localhost development.
- Never package provider, Postiz, ARTEMIS, or remote gateway secrets into public client binaries.
- Preserve upstream license files. Postiz is AGPL-3.0; review obligations before redistributing a combined product.


## Current limitations (do not mark as end-to-end complete yet)

- QR pairing now has a real PC approval queue. The Android device receives its credential only after approval; the credential is stored in Android secure storage and only its hash is persisted by Jarvis.
- The Windows agent currently uses a narrow, typed set of vendored Atticus Windows primitives. The full Atticus conversational runtime is not invoked; upstream relies on Claude Code CLI, so integration with Jarvis's shared model hub needs separate work.
- ARTEMIS is vendored and the Jarvis bridge/client UI exists, but the ARTEMIS daemon is not yet automatically installed or started by the Windows installer. It requires Python 3.12+, its own runtime dependencies and an authorized Android ADB device.
- Postiz source, Public API adapter, Android/Windows publishing UI, and encrypted PC-side API credential setup are present. No live workspace key/OAuth account or publish round-trip has been tested.
- The PC-side provider vault encrypts model provider keys, Postiz API keys and ARTEMIS credentials at rest; Android model/provider configuration remains read-only. Windows and Android have not yet been physically paired and exercised together.
- Tailscale Serve setup is attempted by the Windows host launcher; the user must install/sign in to Tailscale on both devices and enable tailnet HTTPS before QR pairing can work off localhost.
