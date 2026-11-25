#!/usr/bin/env bash
# 为 HarmonyOS NEXT（API 12+）编译 Rust ohos-rs NAPI 动态库（libmoviepilot_core_ohos.so）并同步到 core_rust_bridge HAR。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_DIR="$ROOT/shared/core-rust"
RUST_DIR="$WORKSPACE_DIR/crates/mp-ffi-ohos"
OUT_HAR="$ROOT/harmony/commons/core_rust_bridge"

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  if [[ -d "/Volumes/DISK/TmpBuild" ]]; then
    export CARGO_TARGET_DIR="/Volumes/DISK/TmpBuild/moviepilot-rust-target"
  else
    export CARGO_TARGET_DIR="${RUNNER_TEMP:-$WORKSPACE_DIR/target}/moviepilot-rust-target"
  fi
fi

if [[ -z "${OHOS_NDK_HOME:-}" ]]; then
  if [[ -n "${DEVECO_SDK_HOME:-}" && -d "${DEVECO_SDK_HOME}/default/openharmony/native" ]]; then
    export OHOS_NDK_HOME="${DEVECO_SDK_HOME}/default/openharmony/native"
  elif [[ -n "${HOS_SDK_HOME:-}" && -d "${HOS_SDK_HOME}/default/openharmony/native" ]]; then
    export OHOS_NDK_HOME="${HOS_SDK_HOME}/default/openharmony/native"
  elif [[ -d "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native" ]]; then
    export OHOS_NDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native"
  else
    echo "请设置 OHOS_NDK_HOME 指向 HarmonyOS SDK openharmony/native 目录。" >&2
    exit 1
  fi
fi

# 兼容 setup-ohos 导出到 .../openharmony 而非 .../openharmony/native 的目录层级
if [[ ! -d "$OHOS_NDK_HOME/llvm/bin" && -d "$OHOS_NDK_HOME/native/llvm/bin" ]]; then
  OHOS_NDK_HOME="$OHOS_NDK_HOME/native"
fi

OHOS_TARGETS="${OHOS_TARGETS:-aarch64-unknown-linux-ohos}"

if command -v ohrs >/dev/null 2>&1; then
  cd "$RUST_DIR"
  ohrs build --release --dist "$OUT_HAR/libs"
else
  LLVM_BIN="$OHOS_NDK_HOME/llvm/bin"
  AR="$LLVM_BIN/llvm-ar"
  if [[ ! -x "$AR" ]]; then
    echo "未找到 OHOS NDK llvm-ar：$AR" >&2
    exit 1
  fi
  cd "$WORKSPACE_DIR"
  for target in $OHOS_TARGETS; do
    rustup target add "$target" >/dev/null 2>&1 || true
    case "$target" in
      aarch64-unknown-linux-ohos)
        CLANG="$LLVM_BIN/aarch64-unknown-linux-ohos-clang"
        ABI_DIR="arm64-v8a"
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$CLANG" \
        CC_aarch64_unknown_linux_ohos="$CLANG" \
        AR_aarch64_unknown_linux_ohos="$AR" \
          cargo build -p mp-ffi-ohos --release --target "$target"
        ;;
      x86_64-unknown-linux-ohos)
        CLANG="$LLVM_BIN/x86_64-unknown-linux-ohos-clang"
        ABI_DIR="x86_64"
        CARGO_TARGET_X86_64_UNKNOWN_LINUX_OHOS_LINKER="$CLANG" \
        CC_x86_64_unknown_linux_ohos="$CLANG" \
        AR_x86_64_unknown_linux_ohos="$AR" \
          cargo build -p mp-ffi-ohos --release --target "$target"
        ;;
      *)
        echo "不支持的 OHOS Rust Target：$target" >&2
        exit 1
        ;;
    esac
    mkdir -p "$OUT_HAR/libs/$ABI_DIR"
    cp "$CARGO_TARGET_DIR/$target/release/libmoviepilot_core_ohos.so" \
       "$OUT_HAR/libs/$ABI_DIR/libmoviepilot_core_ohos.so"
    ls -lh "$OUT_HAR/libs/$ABI_DIR/libmoviepilot_core_ohos.so"
  done
fi

echo "HarmonyOS NEXT Rust NAPI 动态库构建完成。"
