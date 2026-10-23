#!/bin/zsh
# 在完整 Xcode 或 Command Line Tools 下执行同一套核心协议测试。
set -euo pipefail
cd "${0:A:h:h}"

toolchain_path="${DEVELOPER_DIR:-$(xcode-select -p)}"
test_options=()
if [[ "$toolchain_path" == /Library/Developer/CommandLineTools ]]; then
  manifest_path="$toolchain_path/usr/lib/swift/pm/ManifestAPI"
  public_interface="$manifest_path/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
  private_interface="$manifest_path/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
  # 部分升级后的 CLT 遗留旧私有接口，只在本项目的忽略目录中创建一致的覆盖层。
  if [[ -f "$private_interface" && -f "$public_interface" ]] &&
     [[ "$(sed -n '2p' "$public_interface")" != "$(sed -n '2p' "$private_interface")" ]]; then
    overlay_path="$PWD/.build/local-toolchain"
    mkdir -p "$overlay_path/ManifestAPI/PackageDescription.swiftmodule"
    cp "$public_interface" "$overlay_path/ManifestAPI/PackageDescription.swiftmodule/"
    ln -sf "$manifest_path/libPackageDescription.dylib" "$overlay_path/ManifestAPI/libPackageDescription.dylib"
    export SWIFTPM_CUSTOM_LIBS_DIR="$overlay_path"
    print '使用项目内 CLT 接口覆盖层；未修改系统工具链。'
  fi
  test_macros="$toolchain_path/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
  if [[ -f "$test_macros" ]]; then
    test_options=(-Xswiftc -load-plugin-library -Xswiftc "$test_macros")
  fi
fi
exec swift test "${test_options[@]}" "$@"
