# Jarvis shared backend integration status

Jarvis uses one FastAPI backend for Windows and Android clients. The clients share APIs; operating-system actions execute on a paired native agent for the target OS.

## Social accounts: OAuth-first

The Jarvis Social Hub now lists 30+ provider labels and sends users to the configured self-hosted Postiz workspace at `JARVIS_POSTIZ_APP_URL/integrations`. Social account authorization and token storage are handled in that workspace using the provider's official OAuth flow; the Jarvis UI does not ask users for social passwords or expose provider tokens. Official provider developer-app credentials may still be required in the Postiz server environment. The older public-API adapter remains for compatibility but is not used by the new OAuth-first hub.

Configure `JARVIS_POSTIZ_APP_URL=https://your-social-workspace.example`. The app's provider catalog is a discovery list, not proof every provider is enabled or that OAuth is already connected.

## Cross-device remote control

The shared broker exposes `/api/remote/*` routes for agent registration, heartbeat, typed task queueing, polling, and results. Tasks are stored in SQLite, expire, and reject arbitrary shell/script payloads. Typing and key presses require an explicit confirmation flag; the Windows agent also uses an app/key allowlist.

Configure a strong private `JARVIS_REMOTE_GATEWAY_TOKEN` on the server and set the same value only in trusted clients/agents. Do not commit the token, put it in a public release, or use an untrusted network without HTTPS. The Android app and web dashboard can queue Windows actions. To execute them on a Windows PC, run `scripts/windows-remote-agent.py` interactively on that PC with:
- `JARVIS_REMOTE_BASE_URL=https://your-jarvis-server.example`
- `JARVIS_REMOTE_GATEWAY_TOKEN=<private token>`
- optional `JARVIS_WINDOWS_AGENT_ID=mustafa-pc`

Install `pyautogui` on the Windows PC only if you want the optional typing/key/screenshot features. Screenshots remain on the PC; this agent does not upload them. Stop the agent with Ctrl+C.

For an Android device connected to a PC, install Android platform-tools, enable USB debugging, and approve that PC on the phone. Then set `JARVIS_REMOTE_BASE_URL`, `JARVIS_REMOTE_GATEWAY_TOKEN`, and optionally `JARVIS_ANDROID_AGENT_ID=android-usb-device`, and run `python scripts/android-adb-agent.py`. This bridge only accepts allowlisted ADB actions and does not upload screenshots.

## Important verification boundary

The backend broker and its API tests do not mean that every device engine is fully connected. A Windows agent implementation is included, but it has not been exercised on a real Windows PC in this environment. An optional `scripts/android-adb-agent.py` bridge can route allowlisted actions to an Android device connected to the PC with USB debugging explicitly authorized. It is an ADB bridge, not yet a full Android-native ARTEMIS agent. Atticus remains Windows-specific and ARTEMIS remains Android/ADB-specific; neither engine can natively run on the other OS. Postiz OAuth requires a configured workspace and provider app credentials, and live social account connection/publishing has not been verified.

Before production use, replace the shared gateway token with per-user and per-agent identities, revocable credentials, TLS, rate limits, durable audit logs, task cancellation, and least-privilege authorization. Do not expose the broker publicly without these controls.
