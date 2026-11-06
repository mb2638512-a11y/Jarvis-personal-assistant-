# Jarvis end-to-end integration programme

Updated: 2026-11-06  
Target: one Jarvis experience with a Windows PC host, Android client, local/cloud model providers, and three upstream engines. This is an implementation and verification plan, not a claim that every stage is already complete.

## System architecture

- **Jarvis core/API:** FastAPI service and typed task broker. Runs on the user's Windows PC first; the host must stay awake for remote access.
- **Windows client/agent:** Flutter desktop UI plus a separate Windows agent. The agent accepts typed, allow-listed actions only; no arbitrary shell or PowerShell execution.
- **Android client:** Flutter APK. Android automation is delegated to a separately hosted ARTEMIS runtime with ADB-connected device(s); ARTEMIS is not embedded into the APK.
- **Model layer:** OpenAI-compatible providers. The Flutter model settings support provider profiles and model catalogue sync; local Ollama/LM Studio endpoints and cloud providers need to be reachable from the device making the request.
- **Upstream engines:** Atticus Windows primitives, Google ARTEMIS Android automation host, and Postiz social publishing. These are separate runtimes/services with their own dependencies and credentials.

## Phases and acceptance gates

### Phase 0 — Reproducible desktop release
- [x] Windows x64 ZIP build and GitHub Release asset published.
- [x] Android APK release asset exists.
- [ ] Install the ZIP on a clean Windows 10/11 machine and verify the installer, desktop shortcut, backend startup, and Windows agent startup.
- [ ] Record exact installer logs and test results before marking the release production-ready.

### Phase 1 — Secure device enrollment (next implementation milestone)
- [ ] Replace shared device-agent credentials with expiring one-time pairing codes.
- [ ] Issue unique per-device credentials; store only credential hashes on the host.
- [ ] Add device list, last-seen, capability display, revoke, and rotate controls.
- [ ] Bind task polling and result submission to the enrolled device identity.
- [ ] Keep admin/client authorization separate from device-agent authentication.
- [ ] Test wrong code, expired code, replayed code, wrong device, revoked device, and token rotation.
- [ ] Keep all remote traffic HTTPS/private-network only; never expose the backend port directly to the public internet.

### Phase 2 — Android ↔ PC connection
- [ ] Add Android app settings for the private Jarvis host URL and secure enrollment.
- [ ] Implement Android client authentication without embedding server secrets in the APK.
- [ ] Add device heartbeat/status and a visible connected/disconnected state.
- [ ] Verify phone-to-PC tasks over a private HTTPS path (e.g. Tailscale Serve).
- [ ] Test reconnect after network changes and host restart.
- [ ] Keep sensitive actions confirmation-gated.

### Phase 3 — AI model connectivity
- [x] Flutter app has provider profiles, secure local credential storage, task-aware model selection, and OpenAI-compatible chat calls.
- [x] Provider presets include OpenAI-compatible cloud, Ollama local, and LM Studio local endpoints.
- [ ] Verify local Ollama and LM Studio from Windows desktop.
- [ ] Verify Android access to PC-hosted models using a private HTTPS endpoint; localhost on the phone is not the Windows PC.
- [ ] Test provider model-list sync, chat, timeout, invalid key, fallback, and offline behavior.
- [ ] Keep API keys in secure storage/server-side configuration; never commit them or expose them in logs.
- [ ] Add server-side model routing only if a shared centralized model gateway is required; do not duplicate secrets in clients.

### Phase 4 — Atticus Windows engine
- [x] Vendored Atticus Windows primitives are called by the Jarvis Windows agent.
- [x] Typed actions currently include safe app launch, HTTPS URL open, confirmed text/key input, status, and screenshot capture.
- [ ] Verify every action on a real Windows host and confirm result reporting.
- [ ] Expand capabilities only through reviewed typed operations and explicit permissions.
- [ ] Preserve upstream license and attribution.

Upstream: https://github.com/FindlayHi/atticus-windows

### Phase 5 — Google ARTEMIS Android engine
- [x] Jarvis bridge exposes status, task submission, and task result routes.
- [ ] Provision a separate private ARTEMIS host (Python 3.12+, Android platform tools/ADB, runtime dependencies).
- [ ] Attach and authorize the intended Android device.
- [ ] Configure ARTEMIS model/provider credentials and its private authenticated network endpoint.
- [ ] Verify live device discovery, one confirmed harmless task, task result, timeout, and disconnect handling.
- [ ] Do not expose ARTEMIS daemon administration endpoints to the public internet.

Upstream: https://github.com/google/artemis

### Phase 6 — Postiz social publishing
- [x] Jarvis server-side adapter supports channel listing, post listing, drafts/scheduling/publish-now, media URL import, deletion, scheduling slots, and analytics.
- [ ] Configure a Postiz workspace and official social-provider OAuth applications.
- [ ] Configure Postiz API key and a separate Jarvis action token in the host's private environment.
- [ ] Verify channel listing against a test workspace.
- [ ] Create and inspect a draft first; test scheduling next; publish only after explicit user approval.
- [ ] Add per-user authorization and workspace mapping before exposing social actions beyond a trusted private network.
- [ ] Review Postiz AGPL-3.0 obligations before distributing a combined hosted/modified product.

Upstream: https://github.com/gitroomhq/postiz-app

### Phase 7 — Voice, browser, files, workflows
- [ ] Choose and integrate a supported speech-to-text and text-to-speech stack; verify microphone permissions and language behavior.
- [ ] Add browser automation through a separately permissioned browser worker.
- [ ] Add file operations with explicit allowed folders, preview, confirmation for writes/deletes, and audit logs.
- [ ] Add workflow orchestration with dry-run and approval gates.
- [ ] Do not label these capabilities ready until each action has an integration test and a real-device acceptance test.

### Phase 8 — Security, reliability, and release
- [ ] First-party user sign-in and per-user/device authorization.
- [ ] Secret rotation, device revocation, audit log, rate limits, request size limits, and safe error redaction.
- [ ] Backups and recovery for local task/device state.
- [ ] Installer upgrade/uninstall path and signed release consideration.
- [ ] End-to-end test matrix across Windows 10/11, Android versions, Wi-Fi changes, host restart, and provider outages.
- [ ] Publish a capability matrix separating implemented, configured, live-verified, and unavailable features.

## User-provided setup required

The repository can provide code and tests, but live end-to-end operation requires the user to install the release and authorize their own devices/accounts. The user must supply their own AI provider credentials, Postiz workspace/OAuth setup, and (if Android UI automation is wanted) a private ARTEMIS host plus ADB access. Never request or commit passwords, API keys, device tokens, or private gateway secrets in chat.

## Definition of done

A feature is **implemented** when code exists; **configured** when valid local settings exist; **live-verified** only after a real upstream/device request succeeds; and **end-to-end complete** only after the user-facing workflow passes on the actual Windows PC and Android phone. Mocked unit tests alone do not meet the live-verification gate.
