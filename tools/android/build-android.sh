#!/usr/bin/env bash
# 构建并校验 Android APK（含 Rust 共享内核 libmoviepilot_core.so）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT_DIR="${1:-$ROOT/artifacts}"
mkdir -p "$OUT_DIR"

export ANDROID_HOME="${ANDROID_HOME:-/Volumes/DISK/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/Volumes/DISK/Android/gradle-home}"

bash "$ROOT/tools/rust/build-android.sh"
python3 "$ROOT/tools/sync-all.py" --check

cd "$ROOT/android"
./gradlew :app:testDebugUnitTest :app:assembleDebug --no-daemon

APK_SRC="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
APK_DST="$OUT_DIR/MoviePilot-${VERSION}-android-arm64-v8a.apk"
cp "$APK_SRC" "$APK_DST"
python3 "$ROOT/tools/android/verify-apk.py" "$APK_DST" --version "$VERSION"
echo "Android APK 构建与校验通过：$APK_DST"
