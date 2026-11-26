#!/usr/bin/env bash
# 构建并校验 Android Release APK（含 Rust 共享内核 libmoviepilot_core.so，支持单架构与全架构通用包）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="$ROOT/VERSION_ANDROID"
if [[ ! -f "$VERSION_FILE" ]]; then
  VERSION_FILE="$ROOT/VERSION"
fi
VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
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
# 仅销毁本次从环境解包的一次性证书，不改动维护者已有签名文件。
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
elif [[ -z "${ANDROID_KEYSTORE_PATH:-}" && -f "$HOME/.android/moviepilot-release.env" ]]; then
  # 本地维护者机器存在正式签名环境时自动加载，确保本地构建与 GitHub Release 证书永久一致
  # shellcheck disable=SC1091
  source "$HOME/.android/moviepilot-release.env"
fi

if [[ "${REQUIRE_RELEASE_SIGNING:-0}" == "1" ]]; then
  if [[ -z "${ANDROID_KEYSTORE_PATH:-}" || ! -f "${ANDROID_KEYSTORE_PATH}" || -z "${ANDROID_KEYSTORE_PASSWORD:-}" || -z "${ANDROID_KEY_ALIAS:-}" || -z "${ANDROID_KEY_PASSWORD:-}" ]]; then
    echo "正式发版必须提供完整的 ANDROID_KEYSTORE_* 签名密钥配置，严禁回退临时 Debug 证书。" >&2
    exit 1
  fi
fi

python3 "$ROOT/tools/sync-all.py" --check

# 按指定 ABI 构建安装包，并在同一版本、架构与签名约束下校验产物。
build_variant_apk() {
  local abis="$1"
  local dst_name="$2"
  local run_tests="$3"

  ANDROID_ABIS="$abis" bash "$ROOT/tools/rust/build-android.sh"
  cd "$ROOT/android"
  local csv_abis="${abis// /,}"
  if [[ "$run_tests" == "true" ]]; then
    ./gradlew :app:testDebugUnitTest :core-rust-bridge:testDebugUnitTest :widget:testDebugUnitTest :app:lintDebug :app:assembleRelease -PMOVIEPILOT_ABI_FILTERS="$csv_abis" --no-daemon
  else
    ./gradlew :app:assembleRelease -PMOVIEPILOT_ABI_FILTERS="$csv_abis" --no-daemon
  fi

  local apk_src="$ROOT/android/app/build/outputs/apk/release/app-release.apk"
  if [[ ! -f "$apk_src" ]]; then
    apk_src="$(find "$ROOT/android/app/build/outputs/apk/release" -name "*.apk" | head -n 1)"
  fi
  local apk_dst="$OUT_DIR/$dst_name"
  cp "$apk_src" "$apk_dst"
  # 始终保留必填参数，兼容 macOS Bash 3.2 在 set -u 下不能展开空数组的行为。
  local verify_args=("$apk_dst" --version "$VERSION" --abis "$csv_abis")
  if [[ "${REQUIRE_RELEASE_SIGNING:-0}" == "1" ]]; then
    verify_args+=(--require-release-cert)
  fi
  python3 "$ROOT/tools/android/verify-apk.py" "${verify_args[@]}"
  echo "Android APK 构建与校验通过：$apk_dst"
}

# JVM 回归与设备产物复用相同 Rust 源码构建的宿主库。
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${RUNNER_TEMP:-/Volumes/DISK/TmpBuild}/moviepilot-rust-target}"
export MOVIEPILOT_RUST_HOST_LIB_DIR="$CARGO_TARGET_DIR/release"

# 1. 构建主力 arm64-v8a 轻量安装包
build_variant_apk "${ANDROID_ABIS:-arm64-v8a}" "MoviePilot-${VERSION}-android-arm64-v8a.apk" "true"

# 2. 发版模式可选构建含 arm64-v8a / armeabi-v7a / x86_64 的通用安装包
if [[ "${BUILD_UNIVERSAL:-0}" == "1" ]]; then
  build_variant_apk "arm64-v8a armeabi-v7a x86_64" "MoviePilot-${VERSION}-android-universal.apk" "false"
fi
