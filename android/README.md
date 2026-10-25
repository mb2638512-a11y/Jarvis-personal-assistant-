# Android client

The Android application source must be migrated or implemented here before a genuine APK can be released. The release workflow checks for Flutter (`pubspec.yaml`) or Gradle wrapper source before attempting an APK build. Do not publish a placeholder APK.

Expected integration: configurable HTTPS backend URL, real `/health` and `/api/chat` requests, secure token storage if authentication is introduced, clear permission prompts, and no API provider keys embedded in the APK.
