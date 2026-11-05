#!/bin/bash
# 为个人重签构建默认启用生产 APNs 的真机 IPA；不读取 Apple 签名身份。
set -euo pipefail

release_version="${1:?Usage: bash scripts/build-ipa.sh VERSION [OUTPUT_DIRECTORY]}"
if [[ ! "$release_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'Version must use MAJOR.MINOR.PATCH.' >&2
  exit 1
fi
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${2:-$source_root/artifacts}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
build_dir="$(mktemp -d "$output_dir/.ipa-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcodebuild -version
# 使用真机 SDK；只保留待重签的推送和共享组声明，不注入个人团队。
xcodebuild archive \
  -project "$source_root/ios/MoviePilot.xcodeproj" \
  -scheme MoviePilot \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -archivePath "$build_dir/MoviePilot.xcarchive" \
  -derivedDataPath "$build_dir/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$release_version" CURRENT_PROJECT_VERSION=1 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  MOVIEPILOT_APNS_ENVIRONMENT=production \
  | tee "$output_dir/build.log"

app_path="$build_dir/MoviePilot.xcarchive/Products/Applications/MoviePilot.app"
test -d "$app_path"
mkdir -p "$build_dir/staging/Payload"
ditto --norsrc --noextattr "$app_path" "$build_dir/staging/Payload/MoviePilot.app"
staged_app="$build_dir/staging/Payload/MoviePilot.app"
# 构建变量需在元数据签名前展开；主包保留 APNs，扩展仅保留共享组。
cp "$source_root/ios/MoviePilot/Resources/APNs.entitlements" "$build_dir/app.entitlements"
/usr/libexec/PlistBuddy -c 'Set :aps-environment production' "$build_dir/app.entitlements"
if [[ -d "$staged_app/PlugIns/MoviePilotWidgets.appex" ]]; then
  codesign --force --sign - --timestamp=none --generate-entitlement-der \
    --entitlements "$source_root/ios/MoviePilotWidgets/Widgets.entitlements" \
    "$staged_app/PlugIns/MoviePilotWidgets.appex"
fi
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements "$build_dir/app.entitlements" "$staged_app"
codesign --verify --deep --strict "$staged_app"
ipa_path="$output_dir/MoviePilot-$release_version-unsigned.ipa"
ditto -c -k --norsrc --noextattr --keepParent "$build_dir/staging/Payload" "$ipa_path"
python3 "$source_root/scripts/verify-ipa.py" "$ipa_path" --version "$release_version" --build-number 1
(
  cd "$output_dir"
  shasum -a 256 "$(basename "$ipa_path")" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
