# Vendored upstream projects

Jarvis keeps reviewed upstream source snapshots under this directory. These are ordinary
tracked directories in the Jarvis repository, **not Git submodules**. A normal clone of
Jarvis already contains the tracked files; no `git submodule update` command is required.

## Included upstreams

| Upstream | Source repository | Intended Jarvis role | Current integration status |
|---|---|---|---|
| Atticus Windows | https://github.com/FindlayHi/atticus-windows | Windows desktop automation and local computer actions | Source snapshot present; Jarvis runtime adapter is not yet verified |
| Google ARTEMIS | https://github.com/google/artemis | Agent planning/execution and computer interaction research | Source snapshot present; isolated until a reviewed API adapter is implemented |
| Postiz | https://github.com/gitroomhq/postiz-app | Social channels, publishing, scheduling and analytics | Source snapshot present; Jarvis FastAPI Public API adapter exists in `jarvis_api/postiz.py`; live account connection is not verified |

## Integration boundaries

- Jarvis uses its **own** Android and Windows client interfaces. Do not embed or ship the upstream
  product frontends as Jarvis screens.
- Atticus automation must execute on the user's Windows device and require confirmation for
  consequential actions.
- ARTEMIS remains isolated until its dependencies, security boundary, and API contract have
  been reviewed and connected through a Jarvis-owned adapter.
- Postiz credentials belong only in the backend environment. Never expose its API key or the
  Jarvis Postiz gateway token to Android or Windows clients.
- Vendored source does not mean a project is installed, compiled, connected at runtime, or
  verified by Jarvis tests.
- Preserve each upstream license, copyright notice, and required attribution. Review the
  applicable license before redistributing a build that includes upstream code.
