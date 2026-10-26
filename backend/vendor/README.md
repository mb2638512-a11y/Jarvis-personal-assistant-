# Vendored upstream projects

These projects are pinned Git submodules, not copied source snapshots. Clone them with:

```bash
git clone --recurse-submodules https://github.com/mb2638512-a11y/Jarvis-personal-assistant-.git
# or, in an existing clone:
git submodule update --init --recursive
```

## Included upstreams

- `atticus-windows` — https://github.com/FindlayHi/atticus-windows
- `artemis` — https://github.com/google/artemis
- `postiz-app` — https://github.com/gitroomhq/postiz-app

Each submodule is pinned to a reviewed upstream commit. Updates should be deliberate and accompanied by compatibility/security review; do not auto-follow upstream `main`.

## Integration boundaries

- Atticus Windows is a Windows desktop assistant; its UI automation must remain on the user's Windows device and require confirmation for consequential actions.
- ARTEMIS is isolated as a separate project until its exact role, dependency requirements, and API contract are validated against Jarvis.
- Postiz is also available through Jarvis's server-side Public API adapter in `jarvis_api/postiz.py`. The Postiz API key belongs only in the backend environment, never in Android/Windows clients.
- A Git submodule pins source; it does **not** mean the upstream project is installed, compiled, integrated at runtime, or verified by tests.
