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

- The Windows device agent registers and heartbeats against the Jarvis task broker, polls typed tasks, executes through Atticus `winctl.py`, and reports completion.
- The ARTEMIS bridge validates Jarvis gateway authentication and explicit user confirmation, then forwards tasks to ARTEMIS `/api/run` and reads `/api/sessions/{id}`.
- The Postiz adapter remains server-side; its API key and action token are not sent to clients.
- `GET /api/integrations/status` reports source/configuration/Windows-agent readiness without treating a copied source tree as a live connection.
- `docs/THREE_REPO_RUNTIME_INTEGRATION.md` contains setup and security boundaries.

## What still requires the user's infrastructure

- Run `windows/jarvis_device_agent.py` on the Windows PC and set the Jarvis backend URL plus remote gateway token.
- Run the ARTEMIS host separately with Python 3.12+, its dependencies, ADB/platform tools, an attached Android phone/emulator, and its own model-provider credentials. Keep the daemon behind a private VPN/tunnel or authenticated HTTPS reverse proxy; do not expose its admin API publicly.
- Configure Postiz workspace/API credentials and verify a protected channels request against a non-production workspace.
- Complete first-party Jarvis user/device authentication and per-user authorization before exposing remote actions or social publishing to the public internet.

## Verification

CI is configured to run on the `android` branch and compile the new device-agent source before running the Jarvis Python tests. A passing mocked test suite proves the adapter contract only; it does not prove that a Windows PC, ARTEMIS Android device, or Postiz account is online.

## Security and licensing

- The Windows agent never accepts arbitrary shell or PowerShell commands.
- Typing and key presses require explicit user confirmation in the broker request.
- Device agents require HTTPS except for localhost development.
- Never package provider, Postiz, ARTEMIS, or remote gateway secrets into public client binaries.
- Preserve upstream license files. Postiz is AGPL-3.0; review obligations before redistributing a combined product.
