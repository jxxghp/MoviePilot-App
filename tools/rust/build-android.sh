#!/usr/bin/env bash
# 为 Android 编译 Rust 共享内核（arm64-v8a / armeabi-v7a / x86_64）并生成 UniFFI Kotlin 绑定。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_DIR="$ROOT/shared/core-rust"
OUT_BRIDGE="$ROOT/android/core-rust-bridge"
JNI_DIR="$OUT_BRIDGE/src/main/jniLibs"
KT_DIR="$OUT_BRIDGE/src/main/java"

export ANDROID_HOME="${ANDROID_HOME:-/Volumes/DISK/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -n 1)}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/Volumes/DISK/TmpBuild/moviepilot-rust-target}"

if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "未找到 Android NDK，请设置 ANDROID_NDK_HOME。" >&2
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

# 3. 通过 cargo-ndk 交叉编译 Android .so（受控 Release Profile <= 4 MB）
NDK_ARGS=()
for abi in $ABIS; do
  NDK_ARGS+=(-t "$abi")
done

cargo ndk "${NDK_ARGS[@]}" --platform 28 -o "$JNI_DIR" build --release -p mp-ffi-uniffi

echo "Android Rust 内核与 UniFFI Kotlin 绑定构建完成："
find "$JNI_DIR" -name "libmoviepilot_core.so" -exec ls -lh {} +
