#!/usr/bin/env bash
# 构建并校验 Android Release APK（含 Rust 共享内核 libmoviepilot_core.so，支持单架构与全架构通用包）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT_DIR="${1:-$ROOT/artifacts}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

if [[ -z "${ANDROID_HOME:-}" ]]; then
  if [[ -d "/Volumes/DISK/Android/sdk" ]]; then
    export ANDROID_HOME="/Volumes/DISK/Android/sdk"
  elif [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT}" ]]; then
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
  fi
fi
export ANDROID_SDK_ROOT="${ANDROID_HOME:-}"

if [[ -z "${GRADLE_USER_HOME:-}" && -d "/Volumes/DISK/Android/gradle-home" ]]; then
  export GRADLE_USER_HOME="/Volumes/DISK/Android/gradle-home"
fi

# 若注入 Base64 签名证书则自动解包用于正式签名（构建结束即销毁）
TEMP_KEYSTORE=""
cleanup() {
  if [[ -n "$TEMP_KEYSTORE" && -f "$TEMP_KEYSTORE" ]]; then
    rm -f "$TEMP_KEYSTORE"
  fi
}
trap cleanup EXIT

if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" && -z "${ANDROID_KEYSTORE_PATH:-}" ]]; then
  if [[ -d "/Volumes/DISK/TmpBuild" ]]; then
    TEMP_KEYSTORE="$(mktemp "/Volumes/DISK/TmpBuild/.mp-keystore.XXXXXX.jks")"
  else
    TEMP_KEYSTORE="$(mktemp "${RUNNER_TEMP:-$OUT_DIR}/.mp-keystore.XXXXXX.jks")"
  fi
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$TEMP_KEYSTORE"
  export ANDROID_KEYSTORE_PATH="$TEMP_KEYSTORE"
fi

python3 "$ROOT/tools/sync-all.py" --check

build_variant_apk() {
  local abis="$1"
  local dst_name="$2"
  local run_tests="$3"

  ANDROID_ABIS="$abis" bash "$ROOT/tools/rust/build-android.sh"
  cd "$ROOT/android"
  local csv_abis="${abis// /,}"
  if [[ "$run_tests" == "true" ]]; then
    ./gradlew :app:testDebugUnitTest :app:assembleRelease -PMOVIEPILOT_ABI_FILTERS="$csv_abis" --no-daemon
  else
    ./gradlew :app:assembleRelease -PMOVIEPILOT_ABI_FILTERS="$csv_abis" --no-daemon
  fi

  local apk_src="$ROOT/android/app/build/outputs/apk/release/app-release.apk"
  if [[ ! -f "$apk_src" ]]; then
    apk_src="$(find "$ROOT/android/app/build/outputs/apk/release" -name "*.apk" | head -n 1)"
  fi
  local apk_dst="$OUT_DIR/$dst_name"
  cp "$apk_src" "$apk_dst"
  python3 "$ROOT/tools/android/verify-apk.py" "$apk_dst" --version "$VERSION" --abis "$csv_abis"
  echo "Android APK 构建与校验通过：$apk_dst"
}

# 1. 构建主力 arm64-v8a 轻量安装包
build_variant_apk "${ANDROID_ABIS:-arm64-v8a}" "MoviePilot-${VERSION}-android-arm64-v8a.apk" "true"

# 2. 发版模式可选构建含 arm64-v8a / armeabi-v7a / x86_64 的通用安装包
if [[ "${BUILD_UNIVERSAL:-0}" == "1" ]]; then
  build_variant_apk "arm64-v8a armeabi-v7a x86_64" "MoviePilot-${VERSION}-android-universal.apk" "false"
fi
