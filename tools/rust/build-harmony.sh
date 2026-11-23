#!/usr/bin/env bash
# 为 HarmonyOS NEXT（API 12+）编译 Rust ohos-rs NAPI 动态库（libmoviepilot_core_ohos.so）并同步到 core_rust_bridge HAR。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_DIR="$ROOT/shared/core-rust/crates/mp-ffi-ohos"
OUT_HAR="$ROOT/harmony/commons/core_rust_bridge"

if ! command -v ohrs >/dev/null 2>&1; then
  echo "未检测到 ohrs（ohos-rs CLI），请先安装 DevEco Studio / HarmonyOS NDK 与 cargo install ohrs。" >&2
  exit 1
fi

if [[ -z "${OHOS_NDK_HOME:-}" ]]; then
  echo "请设置 OHOS_NDK_HOME 指向 HarmonyOS SDK native 目录。" >&2
  exit 1
fi

cd "$RUST_DIR"
ohrs build --release --dist "$OUT_HAR/libs"
echo "HarmonyOS NEXT Rust NAPI 动态库构建完成：$OUT_HAR/libs"
