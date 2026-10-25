#!/usr/bin/env python3
"""核对真机 IPA；组件包仅允许保留共享组的 ad-hoc 元数据签名，仍须安装者重签。"""

import argparse
import hashlib
import json
import plistlib
import re
import struct
import zipfile
from pathlib import Path, PurePosixPath


WIDGET_GROUP = "group.org.moviepilot.widgets"


def verify_metadata_signature(signature: bytes) -> None:
    """只允许无证书的 ad-hoc CodeDirectory 与精确共享组，不把元数据当作 Apple 安装签名。"""
    if len(signature) < 12:
        raise ValueError("代码签名被截断")
    magic, length, count = struct.unpack_from(">3I", signature)
    if magic != 0xFADE0CC0 or not 12 + count * 8 <= length <= len(signature) or count > 32:
        raise ValueError("代码签名索引无效")
    slots = set()
    ranges = []
    entitlements = None
    for index in range(count):
        slot, offset = struct.unpack_from(">2I", signature, 12 + index * 8)
        if slot in slots or offset < 12 + count * 8 or offset + 8 > length:
            raise ValueError("代码签名成员无效")
        slots.add(slot)
        member_magic, size = struct.unpack_from(">2I", signature, offset)
        if size < 8 or offset + size > length or any(offset < end and start < offset + size for start, end in ranges):
            raise ValueError("代码签名成员重叠或截断")
        ranges.append((offset, offset + size))
        if slot == 0 or 0x1000 <= slot <= 0x1005:
            if member_magic != 0xFADE0C02 or size < 44 or struct.unpack_from(">I", signature, offset + 12)[0] & 2 == 0:
                raise ValueError("仅允许 ad-hoc 元数据签名")
        elif slot == 5:
            if member_magic != 0xFADE7171 or size > 65536:
                raise ValueError("共享组声明无效")
            entitlements = plistlib.loads(signature[offset + 8:offset + size])
        elif slot == 0x10000 and size != 8:
            raise ValueError("发布包不能包含 CMS 证书签名")
    if 0 not in slots or entitlements != {"com.apple.security.application-groups": [WIDGET_GROUP]}:
        raise ValueError("发布包必须仅声明约定的 Widget 共享组")


def verify_device_executable(binary: bytes, *, widget_metadata: bool = False) -> None:
    """解析加载命令，核对 arm64 真机平台及允许的无证书元数据签名。"""
    if len(binary) < 32:
        raise ValueError("主程序缺少 Mach-O 头")
    magic, cpu, _, file_type, commands, commands_size, _, _ = struct.unpack_from("<8I", binary)
    if (magic, cpu, file_type) != (0xFEEDFACF, 0x0100000C, 2):
        raise ValueError("主程序必须为 arm64 Mach-O 可执行文件")
    end = 32 + commands_size
    if commands > 4096 or commands_size > 1024 * 1024 or end > len(binary):
        raise ValueError("Mach-O 加载命令被截断")
    position = 32
    platforms = []
    signature = None
    for _ in range(commands):
        if position + 8 > end:
            raise ValueError("Mach-O 加载命令无效")
        command, size = struct.unpack_from("<2I", binary, position)
        if size < 8 or position + size > end:
            raise ValueError("Mach-O 加载命令长度无效")
        if command == 0x32 and size >= 24:  # LC_BUILD_VERSION，PLATFORM_IOS = 2。
            platforms.append(struct.unpack_from("<I", binary, position + 8)[0])
        if command == 0x1D:  # LC_CODE_SIGNATURE。
            if not widget_metadata or signature is not None or size != 16:
                raise ValueError("主程序含非预期签名")
            offset, length = struct.unpack_from("<2I", binary, position + 8)
            if offset < end or length > 4 * 1024 * 1024 or offset + length > len(binary):
                raise ValueError("代码签名范围无效")
            signature = binary[offset:offset + length]
        position += size
    if position != end or platforms != [2]:
        raise ValueError("主程序不是 iOS 真机平台，不能发布模拟器产物")
    if widget_metadata:
        if signature is None:
            raise ValueError("组件包缺少用于重签的共享组元数据")
        verify_metadata_signature(signature)


def verify_ipa(path: Path, version: str, build_number: str) -> dict:
    """读取实际 ZIP，分别验证主 App 与唯一 Widget 扩展的平台、版本、权限与签名边界。"""
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
            if parts[-1] == "embedded.mobileprovision":
                raise ValueError("IPA 不应包含描述文件")
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
        extensions = [name for name in names if name.endswith(".appex/Info.plist")]
        widgets_enabled = info.get("MoviePilotWidgetsEnabled") is True
        widget_metadata = bool(extensions)
        if widgets_enabled and not widget_metadata:
            raise ValueError("已启用小组件却没有嵌入扩展")
        verify_device_executable(archive.read(f"{app_root}/{executable}"), widget_metadata=widget_metadata)
        if widget_metadata:
            extension_root = f"{app_root}/PlugIns/MoviePilotWidgets.appex"
            if extensions != [f"{extension_root}/Info.plist"]:
                raise ValueError("组件包必须且只能嵌入 MoviePilotWidgets 扩展")
            extension = plistlib.loads(archive.read(extensions[0]))
            for key, expected_value in {
                "CFBundleIdentifier": "org.moviepilot.app.widgets",
                "CFBundleShortVersionString": version, "CFBundleVersion": build_number,
                "DTPlatformName": "iphoneos", "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
            }.items():
                if extension.get(key) != expected_value:
                    raise ValueError(f"扩展 {key} 不匹配")
            program = extension.get("CFBundleExecutable")
            if not isinstance(program, str) or "/" in program or program in {"", ".", ".."}:
                raise ValueError("扩展程序名称无效")
            verify_device_executable(archive.read(f"{extension_root}/{program}"), widget_metadata=True)
            for root in [app_root, extension_root]:
                if not archive.read(f"{root}/_CodeSignature/CodeResources"):
                    raise ValueError("ad-hoc 元数据缺少资源封装")
        elif extensions or any("_CodeSignature" in PurePosixPath(name).parts for name in names):
            raise ValueError("旧格式 IPA 不应包含扩展或签名")
    return {
        "file": path.name,
        "version": version,
        "build": build_number,
        "platform": "iPhoneOS",
        "architecture": "arm64",
        "signing": "ad-hoc metadata; requires re-signing" if widget_metadata else "unsigned",
        "widgets": widgets_enabled,
        "widgetExtension": widget_metadata,
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
