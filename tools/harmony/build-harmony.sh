#!/usr/bin/env bash
# 构建并校验 HarmonyOS NEXT HAP 包（需本机或 CI 镜像安装华为 Command Line Tools / hvigorw）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT_DIR="${1:-$ROOT/artifacts}"
mkdir -p "$OUT_DIR"

if ! command -v hvigorw >/dev/null 2>&1; then
  echo "未检测到 hvigorw，请在已安装 DevEco Studio / HarmonyOS Command Line Tools 的环境中运行。" >&2
  exit 1
fi

python3 "$ROOT/tools/sync-all.py" --check
if command -v ohrs >/dev/null 2>&1 && [[ -n "${OHOS_NDK_HOME:-}" ]]; then
  bash "$ROOT/tools/rust/build-harmony.sh"
fi

cd "$ROOT/harmony"
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=release --no-daemon

HAP_SRC="$(find "$ROOT/harmony/entry/build" -name "*.hap" | head -n 1)"
HAP_DST="$OUT_DIR/MoviePilot-${VERSION}-harmony-unsigned.hap"
cp "$HAP_SRC" "$HAP_DST"
python3 "$ROOT/tools/harmony/verify-hap.py" "$HAP_DST" --version "$VERSION"
echo "HarmonyOS NEXT HAP 构建与校验通过：$HAP_DST"
