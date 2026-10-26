# Jarvis Shared Backend — Android + Windows

## Goal
One shared Jarvis backend and one capability model for Android and Windows. Both clients use the same identity, permissions, task engine, memory, tool registry, and API contracts. Platform-specific actions are implemented by adapters; the UI must not duplicate business logic.

## Architecture
- `core/`: shared task orchestration, policy/permissions, memory interfaces, tool registry, audit events, and platform-neutral services.
- `api/`: versioned HTTPS/WebSocket API consumed by both clients.
- `adapters/windows/`: Windows-only actions (window management, filesystem, process launch, keyboard/mouse) guarded by explicit permissions and confirmation for destructive actions.
- `adapters/android/`: Android actions through official Android APIs and user-granted permissions (intents, notifications, accessibility only when explicitly enabled, media/files via scoped storage, and device capabilities exposed by the OS).
- `clients/windows/` and `clients/android/`: thin clients; UI and device integration only, no duplicated business rules.
- `integrations/atticus/` and `integrations/artemis/`: isolated upstream integration wrappers. Keep upstream projects pinned and unmodified; call their supported interfaces rather than mixing their source into core.
- `tests/contract/`: shared API contract tests; `tests/platform/`: OS-specific adapter tests.

## Important platform reality
"Same full powers" means the same Jarvis features and workflows wherever the OS permits them. It cannot mean identical raw device control: Android sandboxing, scoped storage, permission prompts, background-execution limits, and Windows desktop APIs differ. Never bypass Android security or claim a capability until its adapter, permission flow, and tests exist. When a feature is unavailable, return a clear capability/permission response rather than silently pretending it worked.

## Security baseline
- HTTPS in production; bind local development server to loopback by default.
- Short-lived access tokens, refresh-token rotation, per-device sessions, and revocation.
- Explicit capability scopes, least privilege, and confirmation for sensitive actions.
- Never store provider API keys in client apps or commit secrets.
- Audit sensitive actions without logging passwords, tokens, or private content.
- Validate every request and keep Android Accessibility access opt-in and transparent.

## Delivery sequence
1. Define the versioned API and capability schema.
2. Build shared core and contract tests.
3. Implement Windows and Android adapters against the same contracts.
4. Add Atticus and ARTEMIS behind integration wrappers; do not merge their separate runtimes into one process without compatibility tests.
5. Run API contract tests plus Windows CI and Android emulator/device tests.
6. Only then mark a capability as supported on both platforms.

## Current status
This document establishes the target architecture; it does **not** claim that the shared runtime, Android client, Windows client, or full feature parity has already been implemented. The upstream verification workflow remains a separate test job.
