# Three-repository integration report

Date: 2026-10-27

## Source repositories pinned

| Project | Upstream | Pinned commit |
|---|---|---|
| Atticus Windows | https://github.com/FindlayHi/atticus-windows | `657cc26d9cac48ce6951958fc4b2b519787a0af6` |
| ARTEMIS | https://github.com/google/artemis | `351ca8422f7b5b54e80a9c1ce03a222e02415b6b` |
| Postiz | https://github.com/gitroomhq/postiz-app | `a5affe62c74e39c1e7ac960d50d8418b807d532c` |

The repositories are included as Git submodules under `backend/vendor/`, with URLs in `.gitmodules`. They are pinned to fixed commits rather than tracking a moving branch.

## Verification status

- **GitHub source metadata:** verified; all three upstream commit refs resolved successfully on 2026-10-27.
- **Submodule wiring:** added to the integration branch. Confirm by cloning with `--recurse-submodules` or running `git submodule update --init --recursive`.
- **Jarvis Postiz API adapter:** implementation exists at `jarvis_api/postiz.py`; API tests are present in `tests/test_postiz.py`. Live Postiz posting still requires a real Postiz API key and configured workspace.
- **Atticus Windows:** upstream source is pinned; no Windows build/test result is claimed for this Jarvis branch.
- **ARTEMIS:** upstream source is pinned; no claim is made that ARTEMIS is runtime-integrated or that its upstream test suite passed.
- **End-to-end platform verification:** pending. A GitHub tree/submodule reference does not execute code. CI results and actual Windows/Android builds must be checked separately.

## Required verification commands

```bash
git submodule update --init --recursive
python -m pip install -e ".[dev]"
pytest -q
```

For the Windows client, follow the upstream Atticus Windows README and run its documented self-tests on Windows. For Postiz, run mocked adapter tests first, then test against a non-production Postiz workspace. Do not test destructive actions against production accounts.

## Security and licensing

- Keep Postiz credentials server-side; never package secrets in desktop/mobile binaries.
- Review each upstream's license, dependencies, permissions, and security advisories before distributing a combined product. Postiz is AGPL-3.0; consult legal advice before incorporating or modifying its source in a distributed proprietary product.
- Treat the three repositories as separate components until explicit adapters and contract tests demonstrate runtime interoperability.
