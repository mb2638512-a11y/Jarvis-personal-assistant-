# Vendored upstream projects

Jarvis keeps reviewed upstream source snapshots under this directory. These are ordinary
tracked directories in the Jarvis repository, **not Git submodules**. A normal clone of
Jarvis already contains the tracked files; no `git submodule update` command is required.

## Included upstreams

| Upstream | Source repository | Intended Jarvis role | Current integration status |
|---|---|---|---|
| Atticus Windows | https://github.com/FindlayHi/atticus-windows | Windows desktop automation and local computer actions | `windows/jarvis_device_agent.py` uses the vendored `winctl.py` primitives through Jarvis's typed task broker; agent must run on the Windows PC |
| Google ARTEMIS | https://github.com/google/artemis | Android UI automation on a connected phone/emulator | `jarvis_api/artemis.py` bridges to a separately running private ARTEMIS daemon; host/device/model configuration is still required |
| Postiz | https://github.com/gitroomhq/postiz-app | Social channels, publishing, scheduling and analytics | Source snapshot present; Jarvis FastAPI Public API adapter exists in `jarvis_api/postiz.py`; live account connection is not verified |

## Integration boundaries

- Jarvis uses its **own** Android and Windows client interfaces. Do not embed or ship the upstream
  product frontends as Jarvis screens.
- Atticus automation executes on the user's Windows device through `windows/jarvis_device_agent.py`; the agent accepts typed allow-listed actions only.
- ARTEMIS runs as a separate Python 3.12+ Android device host. Jarvis calls it through `jarvis_api/artemis.py`; keep the daemon behind a private VPN/tunnel or authenticated HTTPS proxy.
- Postiz credentials belong only in the backend environment. Never expose its API key or the
  Jarvis Postiz gateway token to Android or Windows clients.
- Vendored source does not mean a project is installed, compiled, or live-connected. See `docs/THREE_REPO_RUNTIME_INTEGRATION.md` for host setup and verification steps.
- Preserve each upstream license, copyright notice, and required attribution. Review the
  applicable license before redistributing a build that includes upstream code.
