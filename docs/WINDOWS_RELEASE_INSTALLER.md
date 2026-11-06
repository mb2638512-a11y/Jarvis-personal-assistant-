# Jarvis Windows release bundle

The Windows ZIP contains the Flutter desktop client and runtime, FastAPI backend, Windows device agent, installer, and launcher.

## Install

1. Download Jarvis-Windows-x64.zip from GitHub Releases.
2. Extract the ZIP.
3. Run Install-Jarvis.ps1 with PowerShell.
4. The installer uses winget to install Python 3.11 if needed, installs backend dependencies, and creates a desktop shortcut.
5. Add your OpenAI-compatible provider API key and model in the .env editor opened during setup. Keep this file private.
6. Start Jarvis from the desktop shortcut.

The launcher starts the local API and Windows agent, then opens the desktop app. Windows defaults to http://127.0.0.1:8000.

## Important boundaries

This is a self-hosted PC bundle, not an offline AI model pack. It does not bundle hosted LLM weights or credits, Postiz, ARTEMIS, Tailscale, Android ADB drivers, OAuth credentials, or third-party services. Those integrations need their own setup and credentials.

The API binds to localhost. Do not expose port 8000 directly to the public internet. For private remote access, install and sign in to Tailscale on each trusted device, then run scripts/expose-windows-host-tailscale.ps1 from the installed host folder. The current remote broker still uses a shared gateway token; one-time pairing and per-device revocation are not implemented yet.

The host PC must remain powered on and awake while serving other devices. This release is unsigned; Windows SmartScreen may show an unknown-publisher warning. Review scripts before running them.
