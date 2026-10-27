# Jarvis shared backend integration status

Jarvis uses one FastAPI backend for both Windows and Android clients. Platform-specific actions execute in the appropriate device-side agent rather than pretending one remote process can control both operating systems directly.

## Upstream responsibilities

- Atticus is a Windows automation engine and must run on the user's Windows device.
- ARTEMIS is an Android device automation/MCP engine and requires an authorized Android device or emulator plus its device runtime.
- Postiz is a server-side social publishing engine. Jarvis uses its API adapter; its separate web UI is not the Jarvis client UI.

The endpoint `/api/integrations/status` reports source presence, intended runtime, capabilities, and verified readiness separately.

## Verification boundary

The three source trees are vendored, and the shared backend exposes an integration status endpoint. Postiz adapter unit tests mock its HTTP boundary. This does not prove live publishing. Atticus has not yet been connected to an authenticated Windows device agent, and ARTEMIS has not yet been connected to an authenticated Android/ADB agent. A durable cross-device task bus, agent enrollment, task cancellation, authorization, and audit logging remain to be implemented. The status endpoint intentionally reports these integrations as not live-connected and not production-ready.

## Required remaining work

1. Implement device-agent enrollment, rotating credentials, heartbeat, capability negotiation, and revocation.
2. Add a durable task queue with ownership, expiry, idempotency, audit events, cancellation, and explicit user confirmation for consequential actions.
3. Connect the Windows agent to Atticus and the Android agent to ARTEMIS/MCP.
4. Run contract tests and real end-to-end tests on a Windows host and authorized Android device.
5. Verify Postiz channel listing and draft creation with real server-side credentials before testing publishing.

Never embed API keys or agent secrets in client binaries. Protect remote actions with TLS, authentication, per-user authorization, rate limits, and audit logs.