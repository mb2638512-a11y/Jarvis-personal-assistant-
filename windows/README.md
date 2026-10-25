# Windows client

This branch is reserved for the genuine Windows desktop/host application. The API backend is not itself a desktop app or a Windows installer.

Implementation requirements: a real desktop UI, configurable backend URL, authenticated pairing before phone-to-PC control, allow-listed commands, explicit consent for sensitive actions, visible audit history, and a clear kill switch. Never expose arbitrary shell execution to unauthenticated remote callers.
