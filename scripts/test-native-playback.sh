#!/bin/zsh
# 合成媒体和专用模拟器覆盖控制条、IPv6 与系统画中画，不读取真实服务或账号。
set -euo pipefail
cd "${0:A:h:h}"
if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi
test_root="${MOVIEPILOT_TEST_ROOT:-/Volumes/DISK/TmpBuild/moviepilot-playback}"
derived_data="${MOVIEPILOT_DERIVED_DATA:-$test_root/DerivedData}"
source_packages="${MOVIEPILOT_SOURCE_PACKAGES:-/Volumes/DISK/Xcode/SourcePackages}"
mkdir -p "$test_root"
export PLAYBACK_TEST_ROOT="$test_root"
python3 - <<'PY'
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
simulator_configuration=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; pairs=[(runtime,d["deviceTypeIdentifier"]) for runtime,devices in json.load(sys.stdin)["devices"].items() if ".iOS-" in runtime for d in devices if d.get("isAvailable") and d["name"].startswith("iPhone")]; print(*pairs[-1]) if pairs else sys.exit("没有可用的 iPhone 模拟器")')
read -r simulator_runtime simulator_type <<< "$simulator_configuration"
playback_simulator=$(xcrun simctl create MoviePilot-Playback-Acceptance "$simulator_type" "$simulator_runtime")
fixture_pids=()
# 只删除本脚本创建的设备与进程；保留结果包供审阅。
trap 'for fixture_pid in "${fixture_pids[@]}"; do kill "$fixture_pid" 2>/dev/null || true; done; xcrun simctl shutdown "$playback_simulator" 2>/dev/null || true; xcrun simctl delete "$playback_simulator"' EXIT
python3 scripts/media-playback-fixture.py --port 5317 --media "$test_root/fixture.mp4" --poster "$test_root/poster.jpg" > "$test_root/ipv4.log" 2>&1 &
fixture_pids+=($!)
mkdir -p "$test_root/frontend"
curl -fsSL https://github.com/jxxghp/MoviePilot-Frontend/releases/download/v3.2.8/dist.zip -o "$test_root/frontend.zip"
unzip -q "$test_root/frontend.zip" -d "$test_root/frontend"
python3 scripts/settings-search-fixture.py --frontend "$test_root/frontend/dist" \
  --poster "$test_root/poster.jpg" --appearance-simulator "$playback_simulator" > "$test_root/settings.log" 2>&1 &
fixture_pids+=($!)
export TEST_RUNNER_MOVIEPILOT_E2E_SERVER=http://127.0.0.1:5319
export TEST_RUNNER_MOVIEPILOT_E2E_PROCESS_FIXTURE=http://127.0.0.1:5319
export TEST_RUNNER_MOVIEPILOT_E2E_USERNAME=startup-fixture
export TEST_RUNNER_MOVIEPILOT_E2E_PASSWORD=fixture-only
python3 scripts/media-playback-fixture.py --ipv6 --port 5320 --media "$test_root/fixture.mp4" --poster "$test_root/poster.jpg" > "$test_root/ipv6.log" 2>&1 &
fixture_pids+=($!)
xcrun simctl boot "$playback_simulator"
xcrun simctl bootstatus "$playback_simulator" -b
xcodebuild test \
  -project ios/MoviePilot.xcodeproj -scheme MoviePilot \
  -destination "platform=iOS Simulator,id=$playback_simulator" \
  -derivedDataPath "$derived_data" -clonedSourcePackagesDirPath "$source_packages" \
  -resultBundlePath "$test_root/Playback.xcresult" \
  -parallel-testing-enabled NO \
  -only-testing:MoviePilotUITests/MediaPlaybackTests/testVideoSurfaceTapsOnlyToggleControls \
  -only-testing:MoviePilotUITests/MediaPlaybackTests/testTrackOptionsPillHidesWhenNoTrackActions \
  -only-testing:MoviePilotUITests/MediaPlaybackTests/testSystemPictureInPictureContinuesOnHomeScreen \
  -only-testing:MoviePilotUITests/NativeFrameworkTests/testStorageMenuFollowsAppThemeAcrossSystemThemes \
  -only-testing:MoviePilotUITests/NativeFrameworkTests/testSettingsAndSearchSheetsAcceptance \
  CODE_SIGN_IDENTITY=-
