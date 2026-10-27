from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parents[1]
manifest = root / "android/app/src/main/AndroidManifest.xml"
template = root / "android-native/MainActivity.kt"
gradle = root / "android/app/build.gradle.kts"
gradle_text = gradle.read_text(encoding="utf-8") if gradle.exists() else ""
match = re.search(r'namespace\s*=\s*"([^"]+)"', gradle_text)
package_name = match.group(1) if match else "com.jarvis.assistant"
target = root / "android/app/src/main/kotlin" / Path(*package_name.split(".")) / "MainActivity.kt"

if not manifest.exists():
    raise SystemExit("Android scaffolding is missing; run flutter create --platforms=android --org com.jarvis.assistant . first.")
if not template.exists():
    raise SystemExit("Missing tracked Android MainActivity template.")

target.parent.mkdir(parents=True, exist_ok=True)
source = template.read_text(encoding="utf-8")
source = re.sub(r"^package [^\n]+", "package " + package_name, source, count=1, flags=re.MULTILINE)
target.write_text(source, encoding="utf-8")
text = manifest.read_text(encoding="utf-8")
permission = '<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS" tools:ignore="ProtectedPermissions" />'
if "android.permission.PACKAGE_USAGE_STATS" not in text:
    text = re.sub(r'(<manifest\b)', r'\1 xmlns:tools="http://schemas.android.com/tools"', text, count=1)
    text = re.sub(r'(<application\b)', permission + "\n    \\1", text, count=1)
manifest.write_text(text, encoding="utf-8")
print("Installed Jarvis Android Usage Access and device metrics channel.")
