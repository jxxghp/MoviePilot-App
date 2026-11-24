#!/usr/bin/env bash
# 构建并校验 HarmonyOS NEXT HAP 包（兼容本机 DevEco Studio 与 GitHub Actions setup-ohos CLI 环境）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
OUT_DIR="${1:-$ROOT/artifacts}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# 自动探测 macOS DevEco Studio 或 CI setup-ohos SDK/CLI 路径
if [[ -z "${DEVECO_SDK_HOME:-}" ]]; then
  if [[ -n "${HOS_SDK_HOME:-}" && -d "${HOS_SDK_HOME}" ]]; then
    export DEVECO_SDK_HOME="${HOS_SDK_HOME}"
  elif [[ -d "/Applications/DevEco-Studio.app/Contents/sdk" ]]; then
    export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
  fi
fi

if [[ -d "/Applications/DevEco-Studio.app/Contents/tools" ]]; then
  DEVECO_TOOLS="/Applications/DevEco-Studio.app/Contents/tools"
  export PATH="$DEVECO_TOOLS/node/bin:$DEVECO_TOOLS/ohpm/bin:$DEVECO_TOOLS/hvigor/bin:$PATH"
fi

if ! command -v hvigorw >/dev/null 2>&1; then
  echo "未检测到 hvigorw，请在已安装 DevEco Studio 或 HarmonyOS Command Line Tools 的环境中运行。" >&2
  exit 1
fi

python3 "$ROOT/tools/sync-all.py" --check
bash "$ROOT/tools/rust/build-harmony.sh"

# 若 CI CLI 工具链的 SDK 平台微版本号（如 26.0.0）与本地工程声明（26.0.1）不同，构建期临时对齐并在退出时无损恢复
PROFILE_FILE="$ROOT/harmony/build-profile.json5"
PROFILE_BACKUP=""
restore_profile() {
  if [[ -n "$PROFILE_BACKUP" && -f "$PROFILE_BACKUP" ]]; then
    cp "$PROFILE_BACKUP" "$PROFILE_FILE"
    rm -f "$PROFILE_BACKUP"
  fi
}
trap restore_profile EXIT

SDK_PKG="${DEVECO_SDK_HOME:-}/default/sdk-pkg.json"
if [[ -f "$SDK_PKG" ]]; then
  INSTALLED_VER="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("data",{}).get("platformVersion",""))' "$SDK_PKG")"
  API_VER="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("data",{}).get("apiVersion",""))' "$SDK_PKG")"
  if [[ -n "$INSTALLED_VER" && "$INSTALLED_VER" != "26.0.1" ]]; then
    if [[ -d "/Volumes/DISK/TmpBuild" ]]; then
      PROFILE_BACKUP="$(mktemp "/Volumes/DISK/TmpBuild/.build-profile.XXXXXX.json5")"
    else
      PROFILE_BACKUP="$(mktemp "${RUNNER_TEMP:-$OUT_DIR}/.build-profile.XXXXXX.json5")"
    fi
    cp "$PROFILE_FILE" "$PROFILE_BACKUP"
    TARGET_STR="${INSTALLED_VER}(${API_VER})"
    python3 -c '
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
for prod in data.get("app", {}).get("products", []):
    prod["targetSdkVersion"] = sys.argv[2]
p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
' "$PROFILE_FILE" "$TARGET_STR"
  fi
fi

cd "$ROOT/harmony"
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildMode=release --no-daemon

HAP_SRC="$(find "$ROOT/harmony/entry/build" -path "*release*" -name "*.hap" | head -n 1)"
if [[ -z "$HAP_SRC" ]]; then
  HAP_SRC="$(find "$ROOT/harmony/entry/build" -name "*.hap" | head -n 1)"
fi
HAP_DST="$OUT_DIR/MoviePilot-${VERSION}-harmony-unsigned.hap"
cp "$HAP_SRC" "$HAP_DST"
python3 "$ROOT/tools/harmony/verify-hap.py" "$HAP_DST" --version "$VERSION"
echo "HarmonyOS NEXT HAP 构建与校验通过：$HAP_DST"
