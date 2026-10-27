from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parents[1]
manifest = root / "android/app/src/main/AndroidManifest.xml"
template = root / "android-native/MainActivity.kt"
target = root / "android/app/src/main/kotlin/com/jarvis/assistant/MainActivity.kt"

if not manifest.exists():
    raise SystemExit("Android scaffolding is missing; run flutter create --platforms=android --org com.jarvis.assistant . first.")
if not template.exists():
    raise SystemExit("Missing tracked Android MainActivity template.")

target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(template, target)
text = manifest.read_text(encoding="utf-8")
permission = '<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" tools:ignore="ProtectedPermissions" />'
if "android.permission.PACKAGE_USAGE_STATS" not in text:
    text = re.sub(r'(<manifest\b)', r'\1 xmlns:tools="http://schemas.android.com/tools"', text, count=1)
    text = re.sub(r'(<application\b)', permission + "\n    \\1", text, count=1)
manifest.write_text(text, encoding="utf-8")
print("Installed Jarvis Android Usage Access and device metrics channel.")
