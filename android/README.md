# Jarvis Android client

Flutter chat source is in `lib/main.dart`. Default URL is Android emulator host `http://10.0.2.2:8000`; use Settings to configure a reachable server. Do not embed provider API keys.

CI generates Android scaffolding with `flutter create --platforms=android .` if needed. APKs are CI artifacts; Play Store publication requires secure signing configuration.