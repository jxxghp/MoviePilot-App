#!/usr/bin/env python3
"""发布前校验 IPA 的 ZIP、版本与 Mach-O 平台，防止上传模拟器或已签名产物。"""

import argparse
import hashlib
import json
import plistlib
import re
import struct
import zipfile
from pathlib import Path, PurePosixPath


def verify_device_executable(binary: bytes) -> None:
    """解析主程序的 Mach-O 加载命令，确保它是未签名的 arm64 iOS 真机程序。"""
    if len(binary) < 32:
        raise ValueError("主程序缺少 Mach-O 头")
    magic, cpu, _, file_type, commands, commands_size, _, _ = struct.unpack_from("<8I", binary)
    if (magic, cpu, file_type) != (0xFEEDFACF, 0x0100000C, 2):
        raise ValueError("主程序必须为 arm64 Mach-O 可执行文件")
    end = 32 + commands_size
    if end > len(binary):
        raise ValueError("Mach-O 加载命令被截断")
    position = 32
    platforms = []
    for _ in range(commands):
        if position + 8 > end:
            raise ValueError("Mach-O 加载命令无效")
        command, size = struct.unpack_from("<2I", binary, position)
        if size < 8 or position + size > end:
            raise ValueError("Mach-O 加载命令长度无效")
        if command == 0x32 and size >= 24:  # LC_BUILD_VERSION，PLATFORM_IOS = 2。
            platforms.append(struct.unpack_from("<I", binary, position + 8)[0])
        if command == 0x1D:  # LC_CODE_SIGNATURE。
            raise ValueError("主程序含代码签名，发布包应交由安装者自行重签")
        position += size
    if platforms != [2]:
        raise ValueError("主程序不是 iOS 真机平台，不能发布模拟器产物")


def verify_ipa(path: Path, version: str, build_number: str) -> dict:
    """读取实际 ZIP 内容，核对唯一 App、未签名状态及本次发布版本。"""
    with zipfile.ZipFile(path) as archive:
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError(f"ZIP 校验失败：{corrupt}")
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("ZIP 含重名条目")
        for name in names:
            parts = PurePosixPath(name).parts
            if not parts or parts[0] != "Payload" or ".." in parts:
                raise ValueError("ZIP 必须仅包含 Payload 安装目录")
            if "_CodeSignature" in parts or parts[-1] == "embedded.mobileprovision":
                raise ValueError("IPA 不应包含签名或描述文件")
        plists = [name for name in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        if len(plists) != 1:
            raise ValueError("IPA 必须包含且仅包含一个 App")
        info = plistlib.loads(archive.read(plists[0]))
        expected = {
            "CFBundleIdentifier": "org.moviepilot.app",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build_number,
            "DTPlatformName": "iphoneos",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "MoviePilotAPNsEnvironment": "disabled",
        }
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError(f"{key} 不匹配：{info.get(key)!r}，预期 {value!r}")
        executable = info["CFBundleExecutable"]
        if not isinstance(executable, str) or "/" in executable or executable in {"", ".", ".."}:
            raise ValueError("App 主程序名称无效")
        app_root = plists[0].rsplit("/", 1)[0]
        verify_device_executable(archive.read(f"{app_root}/{executable}"))
    return {
        "file": path.name,
        "version": version,
        "build": build_number,
        "platform": "iPhoneOS",
        "architecture": "arm64",
        "signing": "unsigned",
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def main() -> None:
    """从命令行检查发布文件，失败时终止 Actions 的资产上传。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", default="1")
    args = parser.parse_args()
    print(json.dumps(verify_ipa(args.ipa, args.version, args.build_number), ensure_ascii=False))


if __name__ == "__main__":
    main()
