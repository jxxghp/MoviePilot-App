#!/usr/bin/env bash
# 为 HarmonyOS NEXT（API 12+）编译 Rust ohos-rs NAPI 动态库（libmoviepilot_core_ohos.so）并同步到 core_rust_bridge HAR。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_DIR="$ROOT/shared/core-rust"
RUST_DIR="$WORKSPACE_DIR/crates/mp-ffi-ohos"
OUT_HAR="$ROOT/harmony/commons/core_rust_bridge"

if [[ -z "${OHOS_NDK_HOME:-}" ]]; then
  if [[ -d "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native" ]]; then
    export OHOS_NDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
  else
    echo "请设置 OHOS_NDK_HOME 指向 HarmonyOS SDK native 目录。" >&2
    exit 1
  fi
fi

if command -v ohrs >/dev/null 2>&1; then
  cd "$RUST_DIR"
  ohrs build --release --dist "$OUT_HAR/libs"
else
  CLANG="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
  AR="$OHOS_NDK_HOME/llvm/bin/llvm-ar"
  if [[ ! -x "$CLANG" ]]; then
    echo "未找到 OHOS NDK clang：$CLANG" >&2
    exit 1
  fi
  cd "$WORKSPACE_DIR"
  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$CLANG" \
  CC_aarch64_unknown_linux_ohos="$CLANG" \
  AR_aarch64_unknown_linux_ohos="$AR" \
    cargo build -p mp-ffi-ohos --release --target aarch64-unknown-linux-ohos
  mkdir -p "$OUT_HAR/libs/arm64-v8a"
  cp "$WORKSPACE_DIR/target/aarch64-unknown-linux-ohos/release/libmoviepilot_core_ohos.so" \
     "$OUT_HAR/libs/arm64-v8a/libmoviepilot_core_ohos.so"
fi

echo "HarmonyOS NEXT Rust NAPI 动态库构建完成：$OUT_HAR/libs/arm64-v8a/libmoviepilot_core_ohos.so"
