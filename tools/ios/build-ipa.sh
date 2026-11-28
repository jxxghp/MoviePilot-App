#!/bin/bash
# 为个人重签构建默认启用生产 APNs 的真机 IPA；不读取 Apple 签名身份。
set -euo pipefail

release_version="${1:?Usage: bash tools/ios/build-ipa.sh VERSION [OUTPUT_DIRECTORY]}"
if [[ ! "$release_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'Version must use MAJOR.MINOR.PATCH.' >&2
  exit 1
fi
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_number="1"
if [[ -f "$source_root/BUILD_NUMBER" ]]; then
  raw_build="$(tr -d '[:space:]' < "$source_root/BUILD_NUMBER")"
  if [[ "$raw_build" =~ ^[1-9][0-9]*$ ]]; then
    build_number="$raw_build"
  fi
fi

output_dir="${2:-$source_root/artifacts}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

if [[ -d "/Volumes/DISK/TmpBuild" ]]; then
  build_dir="$(mktemp -d "/Volumes/DISK/TmpBuild/.ipa-build.XXXXXX")"
else
  build_dir="$(mktemp -d "$output_dir/.ipa-build.XXXXXX")"
fi
trap 'rm -rf "$build_dir"' EXIT

if [[ -n "${CLONED_SOURCE_PACKAGES_DIR:-}" ]]; then
  source_packages_dir="$CLONED_SOURCE_PACKAGES_DIR"
elif [[ -d "/Volumes/DISK/Xcode/SourcePackages" ]]; then
  source_packages_dir="/Volumes/DISK/Xcode/SourcePackages"
else
  source_packages_dir="$build_dir/SourcePackages"
fi
mkdir -p "$source_packages_dir"

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
  -clonedSourcePackagesDirPath "$source_packages_dir" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$release_version" CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  MOVIEPILOT_APNS_ENVIRONMENT=production \
  | tee "$output_dir/build-ios.log"

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
ipa_path="$output_dir/MoviePilot-$release_version-ios-unsigned.ipa"
ditto -c -k --norsrc --noextattr --keepParent "$build_dir/staging/Payload" "$ipa_path"
rm -f "$output_dir/build-ios.log"
python3 "$source_root/tools/ios/verify-ipa.py" "$ipa_path" --version "$release_version" --build-number "$build_number"
echo "iOS IPA 构建与校验通过：$ipa_path"
