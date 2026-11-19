#!/bin/zsh
# 合成媒体和专用模拟器覆盖控制条、IPv6 与系统画中画，不读取真实服务或账号。
set -euo pipefail
cd "${0:A:h:h}"
# 先选定解释器，避免 Xcode 工具链的旧 Python 覆盖支持夹具类型注解的本地环境。
if [[ -x "$PWD/.venv/bin/python" ]]; then
  fixture_python="${MOVIEPILOT_FIXTURE_PYTHON:-$PWD/.venv/bin/python}"
else
  fixture_python="${MOVIEPILOT_FIXTURE_PYTHON:-$(command -v python3)}"
fi
if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
else
  export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
fi
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
xcodebuild_bin="$DEVELOPER_DIR/usr/bin/xcodebuild"
simulator_cache="${MOVIEPILOT_SIMULATOR_CACHE:-$HOME/Library/Caches/MoviePilotSimulator}"
test_root="${MOVIEPILOT_TEST_ROOT:-$simulator_cache/playback}"
derived_data="${MOVIEPILOT_DERIVED_DATA:-$simulator_cache/DerivedData}"
source_packages="${MOVIEPILOT_SOURCE_PACKAGES:-/Volumes/DISK/Xcode/SourcePackages}"
mkdir -p "$test_root"
export PLAYBACK_TEST_ROOT="$test_root"
"$fixture_python" - <<'PY'
import os
from pathlib import Path
root = Path(os.environ['PLAYBACK_TEST_ROOT'])
(root / 'fixture.zh-CN.srt').write_text('1\n00:00:00,000 --> 00:02:00,000\n字幕验收\n')
(root / 'fixture.lrc').write_text('[00:00.00]开头歌词\n[00:02.00]副歌高亮\n')
PY
ffmpeg -v error -y -f lavfi -i testsrc2=size=640x360:rate=24 -f lavfi -i sine=frequency=440 \
  -f lavfi -i sine=frequency=660 -i "$test_root/fixture.zh-CN.srt" -t 120 \
  -map 0:v -map 1:a -map 2:a -map 3:s -c:v libx264 -pix_fmt yuv420p \
  -c:a aac -c:s mov_text -movflags +faststart "$test_root/fixture.mp4"
ffmpeg -v error -y -f lavfi -i color=c=blue:size=320x180 -frames:v 1 "$test_root/poster.jpg"
# 使用已经由当前 runtime 配对的 iPhone 型号，不能把最新硬件与旧 runtime 任意组合。
simulator_configuration=$(xcrun simctl list devices available --json | "$fixture_python" -c 'import json,sys; pairs=[(runtime,d["deviceTypeIdentifier"]) for runtime,devices in json.load(sys.stdin)["devices"].items() if ".iOS-" in runtime for d in devices if d.get("isAvailable") and d["name"].startswith("iPhone")]; print(*pairs[-1]) if pairs else sys.exit("没有可用的 iPhone 模拟器")')
read -r simulator_runtime simulator_type <<< "$simulator_configuration"
playback_simulator=$(xcrun simctl create MoviePilot-Playback-Acceptance "$simulator_type" "$simulator_runtime")
fixture_pids=()
# 只删除本脚本创建的设备与进程；保留结果包供审阅。
trap 'for fixture_pid in "${fixture_pids[@]}"; do kill "$fixture_pid" 2>/dev/null || true; done; xcrun simctl shutdown "$playback_simulator" 2>/dev/null || true; xcrun simctl delete "$playback_simulator"' EXIT
"$fixture_python" scripts/media-playback-fixture.py --port 5317 --media "$test_root/fixture.mp4" \
  --poster "$test_root/poster.jpg" --frontend http://127.0.0.1:5319 > "$test_root/ipv4.log" 2>&1 &
fixture_pids+=($!)
frontend_stage="$test_root/frontend-$(uuidgen)"
if [[ -n "${MOVIEPILOT_FRONTEND_DIST:-}" ]]; then
  frontend_dist="$frontend_stage/dist"
  mkdir -p "$frontend_dist"
  ditto "$MOVIEPILOT_FRONTEND_DIST" "$frontend_dist"
else
  mkdir -p "$frontend_stage"
  curl -fsSL https://github.com/jxxghp/MoviePilot-Frontend/releases/download/v3.2.9/dist.zip -o "$frontend_stage/frontend.zip"
  unzip -q "$frontend_stage/frontend.zip" -d "$frontend_stage"
  frontend_dist="$frontend_stage/dist"
fi
"$fixture_python" scripts/settings-search-fixture.py --frontend "$frontend_dist" \
  --poster "$test_root/poster.jpg" --appearance-simulator "$playback_simulator" > "$test_root/settings.log" 2>&1 &
fixture_pids+=($!)
export TEST_RUNNER_MOVIEPILOT_E2E_SERVER=http://127.0.0.1:5319
export TEST_RUNNER_MOVIEPILOT_E2E_PROCESS_FIXTURE=http://127.0.0.1:5319
export TEST_RUNNER_MOVIEPILOT_E2E_USERNAME=startup-fixture
export TEST_RUNNER_MOVIEPILOT_E2E_PASSWORD=fixture-only
"$fixture_python" scripts/media-playback-fixture.py --ipv6 --port 5320 --media "$test_root/fixture.mp4" --poster "$test_root/poster.jpg" > "$test_root/ipv6.log" 2>&1 &
fixture_pids+=($!)
# 夹具启动失败时立即结束，不让 XCTest 等待一个不存在的播放服务。
"$fixture_python" - <<'PY'
import time
import urllib.error
import urllib.request

opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
for endpoint in (
    'http://127.0.0.1:5317/__playback/stats',
    'http://127.0.0.1:5319/api/v1/login/initialization',
    'http://[::1]:5320/__playback/stats',
):
    for attempt in range(30):
        try:
            with opener.open(endpoint, timeout=1) as response:
                if response.status == 200:
                    break
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.2)
    else:
        raise SystemExit(f'验收夹具未就绪: {endpoint}')
PY
xcrun simctl boot "$playback_simulator"
xcrun simctl bootstatus "$playback_simulator" -b
if [[ -n "${MOVIEPILOT_TEST_ONLY:-}" ]]; then
  selected_tests=("-only-testing:MoviePilotUITests/$MOVIEPILOT_TEST_ONLY")
else
  selected_tests=(
    -only-testing:MoviePilotUITests/MediaPlaybackTests/testVideoSurfaceTapsOnlyToggleControls
    -only-testing:MoviePilotUITests/MediaPlaybackTests/testTrackOptionsPillHidesWhenNoTrackActions
    -only-testing:MoviePilotUITests/MediaPlaybackTests/testDashboardMediaCardsPlayLocally
    -only-testing:MoviePilotUITests/MediaPlaybackTests/testNativeMusicNowPlayingLayout
    -only-testing:MoviePilotUITests/MediaPlaybackTests/testMusicTrackControlsMoveWithinQueue
    -only-testing:MoviePilotUITests/MediaPlaybackTests/testSystemPictureInPictureContinuesOnHomeScreen
    -only-testing:MoviePilotUITests/NativeFrameworkTests/testStorageMenuFollowsAppThemeAcrossSystemThemes
    -only-testing:MoviePilotUITests/NativeFrameworkTests/testSettingsAndSearchSheetsAcceptance
  )
fi
"$xcodebuild_bin" test \
  -project ios/MoviePilot.xcodeproj -scheme MoviePilot \
  -destination "platform=iOS Simulator,id=$playback_simulator" \
  -derivedDataPath "$derived_data" -clonedSourcePackagesDirPath "$source_packages" \
  -resultBundlePath "$test_root/Playback.xcresult" \
  -parallel-testing-enabled NO \
  "${selected_tests[@]}" \
  CODE_SIGN_IDENTITY=-
