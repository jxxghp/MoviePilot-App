#!/usr/bin/env bash
# 为 Android 编译 Rust 共享内核（arm64-v8a / armeabi-v7a / x86_64）并生成 UniFFI Kotlin 绑定。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_DIR="$ROOT/shared/core-rust"
OUT_BRIDGE="$ROOT/android/core-rust-bridge"
JNI_DIR="$OUT_BRIDGE/src/main/jniLibs"
KT_DIR="$OUT_BRIDGE/src/main/java"

if [[ -z "${ANDROID_HOME:-}" ]]; then
  if [[ -d "/Volumes/DISK/Android/sdk" ]]; then
    export ANDROID_HOME="/Volumes/DISK/Android/sdk"
  elif [[ -n "${ANDROID_SDK_ROOT:-}" && -d "${ANDROID_SDK_ROOT}" ]]; then
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
  fi
fi
export ANDROID_SDK_ROOT="${ANDROID_HOME:-}"

if [[ -z "${ANDROID_NDK_HOME:-}" && -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}/ndk" ]]; then
  export ANDROID_NDK_HOME="$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -n 1 || true)"
fi

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  if [[ -d "/Volumes/DISK/TmpBuild" ]]; then
    export CARGO_TARGET_DIR="/Volumes/DISK/TmpBuild/moviepilot-rust-target"
  else
    export CARGO_TARGET_DIR="${RUNNER_TEMP:-$RUST_DIR/target}/moviepilot-rust-target"
  fi
fi

if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "未找到 Android NDK，请设置 ANDROID_NDK_HOME 或安装 Android SDK NDK。" >&2
  exit 1
fi

ABIS="${ANDROID_ABIS:-arm64-v8a}"
mkdir -p "$JNI_DIR" "$KT_DIR"

cd "$RUST_DIR"
# 1. 构建宿主机 cdylib 供 uniffi-bindgen 提取绑定元数据
cargo build --release -p mp-ffi-uniffi
HOST_LIB="$CARGO_TARGET_DIR/release/libmoviepilot_core.dylib"
if [[ ! -f "$HOST_LIB" ]]; then
  HOST_LIB="$CARGO_TARGET_DIR/release/libmoviepilot_core.so"
fi

# 2. 生成 UniFFI Kotlin Coroutines 绑定
cargo run --release -p mp-ffi-uniffi --bin uniffi-bindgen -- \
  generate --library "$HOST_LIB" \
  --language kotlin \
  --out-dir "$KT_DIR" \
  --config "$RUST_DIR/crates/mp-ffi-uniffi/uniffi.toml"

# 3. 清理旧 ABI 目录避免残留不一致架构，再通过 cargo-ndk 交叉编译 Android .so
rm -rf "$JNI_DIR"/*
NDK_ARGS=()
for abi in $ABIS; do
  NDK_ARGS+=(-t "$abi")
done

cargo ndk "${NDK_ARGS[@]}" --platform 28 -o "$JNI_DIR" build --release -p mp-ffi-uniffi

echo "Android Rust 内核与 UniFFI Kotlin 绑定构建完成："
find "$JNI_DIR" -name "libmoviepilot_core.so" -exec ls -lh {} +
