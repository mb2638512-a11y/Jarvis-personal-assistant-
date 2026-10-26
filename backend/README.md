# Jarvis Backend Integrations

This directory is the integration workspace for the two upstream projects below. Upstream source must remain isolated; do not copy files over Jarvis itself.

## Upstreams
- Atticus Windows: https://github.com/FindlayHi/atticus-windows
- Google ARTEMIS: https://github.com/google/artemis

## Verification status
No upstream clone or test run is claimed by this README. Run `.setup-and-test.ps1` from this directory on a Windows machine with Git, Python, and `uv` available. ARTEMIS device-level checks require an authorized Android device or emulator. Atticus tests are Windows-specific and should be run on Windows.
