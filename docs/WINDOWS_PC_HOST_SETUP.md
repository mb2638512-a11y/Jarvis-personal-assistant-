# Jarvis Windows PC Host (first deployment)

The Windows PC is the initial **single-host control center**. It runs the FastAPI backend and SQLite task/device registry locally. The Windows device agent runs separately on the same PC and polls the local broker. Other devices connect over a private HTTPS network; they must not connect to an exposed public HTTP port.

## What this setup does

- Installs Python dependencies into a project-local `.venv`.
- Creates a local `.env` file from `.env.example` if needed.
- Generates a random `JARVIS_REMOTE_GATEWAY_TOKEN` if it is missing.
- Runs the API bound to `127.0.0.1:8000` (not exposed directly to the LAN).
- Runs the local Windows agent using localhost HTTP, which is permitted only for loopback.
- Stores device/task state in `data/remote_tasks.sqlite3`.

This is a private single-PC development/first-host deployment, not yet a Windows service or a production multi-user pairing system.

## 1. Requirements

- Windows 10/11 x64
- Python 3.11 or newer
- Git
- At least 2 GB free disk space for the environment and dependencies
- For multi-device access: Tailscale installed and signed in on the host and every client PC/device that supports it

## 2. Install on the main PC

Open PowerShell in the cloned Jarvis repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install-windows-host.ps1
```

The installer creates `.venv`, installs the backend and Windows-agent dependencies, and creates `.env`. It does not overwrite an existing `.env`.

Open `.env` in Notepad and configure:
- `JARVIS_API_KEY`: your AI provider key
- `JARVIS_BASE_URL`: provider's OpenAI-compatible API base URL
- `JARVIS_MODEL`: exact model identifier
- Keep `JARVIS_REMOTE_GATEWAY_TOKEN` private; never commit `.env` or paste the token into chat.

## 3. Start the backend

In PowerShell window 1:

```powershell
.\scripts\start-windows-host.ps1
```

Check locally:
- Health: http://127.0.0.1:8000/health
- API docs: http://127.0.0.1:8000/docs
- Integration status: http://127.0.0.1:8000/api/integrations/status

`/health` confirms only that the API process is responding. `/status` reports configuration, not a successful live model call.

## 4. Start control of this PC

In PowerShell window 2, from the same repository root:

```powershell
.\scripts\start-windows-agent.ps1
```

The agent should register as `main-windows-pc` and heartbeat every few seconds. The agent uses a strict allow-list; it does not accept arbitrary shell or PowerShell commands.

## 5. Connect other devices privately

Recommended initial networking: Tailscale. Install and sign in on the host PC and each additional PC. On the host, keep Jarvis bound to localhost and use Tailscale Serve to publish the local API only inside your tailnet over HTTPS. Follow the current Tailscale Serve setup for forwarding the host's HTTPS tailnet name to `http://127.0.0.1:8000`.

On a second Windows PC:
1. Clone the same Jarvis repository.
2. Install its Python environment and Windows-agent dependencies.
3. Set `JARVIS_BASE_URL` to the host's Tailscale HTTPS URL.
4. Set `JARVIS_REMOTE_GATEWAY_TOKEN` to the host's token using a secure local method (do not put it in source code).
5. Set a unique `JARVIS_AGENT_ID`, then start `windows/jarvis_device_agent.py`.

Important: the current broker uses one shared gateway token for trusted agents and admin calls. It does **not yet implement one-time pairing links, per-device credentials, revocation UI, or user accounts**. Do not give this token to untrusted devices. These are the next security milestones before broad device enrollment.

Android/ARTEMIS is not automatically configured by this PC installer. Android automation still requires its separately configured private ARTEMIS host/device runtime and the app's backend URL/auth integration.

## 6. Shutdown and backup

- Stop the API and agent with Ctrl+C in their respective PowerShell windows.
- Back up `data/remote_tasks.sqlite3` and your local `.env` securely.
- Never commit `.env`, SQLite data, API keys, gateway tokens, screenshots, or device output.
- If the main PC is off or asleep, its backend is unavailable. For always-on access, the host PC must stay powered and connected, or the backend later needs migration to an always-on server.

## Current boundaries

This deployment is designed to make the user's own Windows PC the initial Jarvis host. It does not claim that the backend has already been installed on the user's physical PC; the user must run the installer there. A successful startup and a real paired-agent task are required before calling device control operational.
