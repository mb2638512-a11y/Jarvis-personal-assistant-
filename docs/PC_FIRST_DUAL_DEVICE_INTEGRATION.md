# PC-first dual-device integration contract

Status: implementation target; not a claim of completion.

## Product rule

The Windows PC is the authoritative Jarvis host and configuration centre. Android is a paired remote-control client. Android may execute phone-native actions locally, but all shared configuration, provider credentials, social integrations, MCP configuration, orchestration and persistent state live on the Windows host.

## Three upstream engines

| Engine | Runtime owner | What Android can do | What Windows can do |
|---|---|---|---|
| Atticus Windows | Windows host | Remotely request approved PC actions and receive results/screenshots | Use the full supported Windows automation surface through a typed, permission-checked adapter |
| Google ARTEMIS | Windows-hosted private ARTEMIS service connected to Android over ADB/Wi-Fi debugging | Request/approve Android UI automation tasks; view progress/results | Configure/manage ARTEMIS, dispatch tasks, inspect traces and diagnostics |
| Postiz | Windows-hosted Postiz service/API adapter | Manage channels, drafts, schedule and analytics through Jarvis remote UI | Full Postiz workspace/admin and publishing workflow through Jarvis UI |

The Android app is not a second copy of the Windows engines. It is the remote console for the PC plus a thin native phone-action adapter. ARTEMIS is the Android device automation engine; it is hosted/managed from the PC and requires an attached/authorized Android device.

## Shared AI model hub

- Provider profiles, API keys, base URLs, model IDs, task routing and model catalogue are configured and stored on the Windows host.
- The host exposes a single authenticated model catalogue/status API to both clients.
- Chat, agent tasks, Atticus, ARTEMIS and Postiz workflows request models through the host-side model gateway where practical.
- Android displays the exact same model catalogue and readiness state as Windows. It does not need a second API key entry.
- Provider secrets must never be included in QR payloads, APK/EXE assets, API responses, logs, analytics or Git.
- Local models such as Ollama/LM Studio are reachable by the host. The phone accesses them through Jarvis on the host; it must not try to resolve the PC's localhost itself.

## Pairing and trust

1. Windows host displays a short-lived QR challenge and a manual fallback code.
2. QR contains only the private host URL, challenge identifier and one-time random secret; never a provider key or permanent gateway token.
3. The phone redeems the challenge over HTTPS/private VPN.
4. Windows requires an explicit local approval before issuing a device-scoped credential.
5. Host stores only a strong hash of the device credential; Android stores its credential in platform secure storage.
6. Device list, last-seen, capabilities, revoke and rotate controls are available on Windows.
7. Remote actions are typed, allow-listed, audited and confirmation-gated when they send, delete, purchase, publish, type sensitive text or change system state.
8. Public plain HTTP and direct public exposure of the Jarvis/ARTEMIS ports are prohibited.

## Required implementation work

### Windows host
- Windows installer installs/starts Jarvis API, Windows agent, private ARTEMIS runtime prerequisites and optional self-hosted Postiz services.
- A first-run setup wizard configures provider profiles, model routing, storage, integrations and network privacy.
- Add QR challenge display, approval prompt, device management and revoke/rotate controls.
- Add central provider registry/model catalogue and host-side credential storage.
- Add a unified engine status page with separate configured, connected, and live-verified states.
- Run background components with restart/recovery and clear logs.

### Android remote client
- First screen: Scan PC QR / enter code.
- Store the paired device credential in Android secure storage.
- Show paired PC, connection status, engine status, model catalogue and task results.
- Expose remote controls for PC, ARTEMIS phone automation, Postiz, AI model selection and approved integrations.
- Remove provider API-key setup and shared gateway-token entry from Android.
- Keep only phone-native permissions/actions locally (camera for QR, accessibility only where the user explicitly enables ARTEMIS helper, notifications, etc.).

### Shared services
- Per-device authorization and session-to-user/workspace mapping.
- Host-side model gateway and provider health checks.
- MCP server authentication, tool discovery and controlled tool execution.
- Postiz server-side credentials and OAuth workspace integration.
- ARTEMIS private host health, device discovery, task submission and trace retrieval.
- Atticus typed Windows actions with capability checks and explicit confirmations.

## Acceptance gates (must be evidenced, not assumed)

- [ ] Pair Android to Windows by scanning a QR; expired/replayed QR is rejected.
- [ ] Revoke the phone; all subsequent requests from it are rejected.
- [ ] Restart Windows; host services recover and the paired phone reconnects without re-pairing.
- [ ] Add a provider key on Windows; Android sees model names/status without receiving the secret.
- [ ] Run a model request from both Windows and Android through the same host-side provider.
- [ ] Run a harmless Atticus action from Windows locally and from Android remotely; verify result payloads.
- [ ] Run an ARTEMIS task on the paired/ADB-authorized Android device; verify task trace and final result.
- [ ] Connect a Postiz test workspace; list channels, create a draft, schedule a test post, and verify analytics. Publishing to a live social account requires a separate explicit approval.
- [ ] Exercise offline, timeout, wrong-device, revoked-device, invalid-provider-key and host-restart cases.
- [ ] Build and inspect the Windows installer and Android APK; run unit, integration and UI tests.
- [ ] Publish a capability matrix distinguishing implemented, configured, live-verified and unavailable.

## Upstream constraints

- Preserve Atticus and ARTEMIS upstream licenses and attribution.
- Postiz is AGPL-3.0. Review source distribution and network-use obligations before shipping a combined modified product.
- Upstream projects remain vendored engines/adapters; do not replace Jarvis branding or copy their frontends into Jarvis.
- No feature is labelled end-to-end complete based only on mocked tests or a successful CI build.
