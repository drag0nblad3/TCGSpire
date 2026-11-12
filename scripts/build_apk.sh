#!/usr/bin/env bash
# Builds a debug APK to build/tcgspire.apk. Run only when an APK is requested.
# Needs: Godot 4.4.1 + its export templates installed, JDK 17+, and an Android SDK
# with build-tools (apksigner). Set ANDROID_SDK_ROOT and JAVA_HOME if not standard.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
JAVA="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
# Fixed debug key checked into the repo so every APK installs over the last one.
KS="${DEBUG_KEYSTORE:-$(pwd)/signing/debug.keystore}"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -v -keystore "$KS" -storepass android -alias androiddebugkey -keypass android \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
# Point the Godot editor at the SDK/JDK (headless export reads editor settings).
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$CFG"
cat > "$CFG/editor_settings-4.4.tres" <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JAVA"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
TRES
mkdir -p build
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-debug "Android" build/tcgspire.apk 2>&1 | grep -E "ERROR|error|savepack|Signed|Verified|apksigner" | head -30 || true
test -s build/tcgspire.apk && ls -la build/tcgspire.apk
