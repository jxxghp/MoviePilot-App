"""验证真实发布边界：真机/模拟器、主包/扩展、无证书元数据与权限白名单。"""

import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path


SPEC = importlib.util.spec_from_file_location("verify_ipa", Path(__file__).parents[1] / "verify-ipa.py")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


def metadata(*, flags=2, cms=b"", group=VERIFY.WIDGET_GROUP, extra=None):
    """构造有限合成签名成员，不调用或读取真实代码签名身份。"""
    entitlement = {"com.apple.security.application-groups": [group]}
    entitlement.update(extra or {})
    xml = plistlib.dumps(entitlement)
    members = [
        (0, struct.pack(">11I", 0xFADE0C02, 44, 0x20001, flags, 0, 0, 0, 0, 0, 0, 0)),
        (5, struct.pack(">2I", 0xFADE7171, len(xml) + 8) + xml),
    ]
    if cms:
        members.append((0x10000, struct.pack(">2I", 0xFADE0B01, len(cms) + 8) + cms))
    offset = 12 + 8 * len(members)
    table = bytearray()
    body = bytearray()
    for slot, member in members:
        table += struct.pack(">2I", slot, offset)
        body += member
        offset += len(member)
    return struct.pack(">3I", 0xFADE0CC0, offset, len(members)) + table + body


def executable(*, platform=2, signature=None):
    """合成仅含平台与签名加载命令的 arm64 文件，专门覆盖包解析边界。"""
    commands = struct.pack("<6I", 0x32, 24, platform, 0, 0, 0)
    count = 1
    if signature is not None:
        count += 1
        commands += struct.pack("<4I", 0x1D, 16, 32 + 24 + 16, len(signature))
    return struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2, count, len(commands), 0, 0) + commands + (signature or b"")


def archive(path, *, widgets=True, enabled=None, extension_version="1.0.1", extension_platform=2, provision=False,
            bundle="com.moviepilot.app", app_environment="production", signed_environment="production", widget_push=False):
    """构造完整 ZIP，分别改变扩展元数据而不依赖构建目录或网络。"""
    common = {
        "CFBundleShortVersionString": "1.0.1", "CFBundleVersion": "1", "DTPlatformName": "iphoneos",
        "CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundleExecutable": "MoviePilot",
    }
    root = "Payload/MoviePilot.app"
    app = dict(common, CFBundleIdentifier=bundle, MoviePilotAPNsEnvironment=app_environment)
    app["MoviePilotWidgetsEnabled"] = widgets if enabled is None else enabled
    with zipfile.ZipFile(path, "w") as target:
        if widgets:
            extension = dict(common, CFBundleIdentifier=bundle + ".widgets", CFBundleShortVersionString=extension_version,
                             NSExtension={"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"})
            extension_root = f"{root}/PlugIns/MoviePilotWidgets.appex"
            target.writestr(f"{extension_root}/Info.plist", plistlib.dumps(extension))
            target.writestr(f"{extension_root}/MoviePilot", executable(platform=extension_platform,
                             signature=metadata(extra={"aps-environment": "production"} if widget_push else None)))
            target.writestr(f"{extension_root}/_CodeSignature/CodeResources", b"synthetic-resources")
        target.writestr(f"{root}/_CodeSignature/CodeResources", b"synthetic-resources")
        target.writestr(f"{root}/Info.plist", plistlib.dumps(app))
        extra = {"aps-environment": signed_environment} if signed_environment is not None else None
        target.writestr(f"{root}/MoviePilot", executable(signature=metadata(extra=extra)))
        if provision:
            target.writestr(f"{root}/embedded.mobileprovision", b"synthetic-forbidden-profile")


class IpaBoundaryTests(unittest.TestCase):
    """上传前拒绝模拟器、证书签名、推送配置不一致、额外权限和扩展版本漂移。"""

    def test_accepts_apns_metadata_with_or_without_widget(self):
        """主包始终保留生产推送声明，扩展可选且不持有推送权限；均仍需重签。"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.ipa"
            for widgets, enabled in [(False, False), (True, False), (True, True)]:
                with self.subTest(widgets=widgets, enabled=enabled):
                    archive(path, widgets=widgets, enabled=enabled)
                    value = VERIFY.verify_ipa(path, "1.0.1", "1")
                    self.assertEqual(value["widgets"], enabled)
                    self.assertEqual(value["widgetExtension"], widgets)
                    self.assertEqual(value["signing"], "ad-hoc metadata; requires re-signing")
                    self.assertEqual(value["bundleIdentifier"], "com.moviepilot.app")
                    self.assertEqual(value["apnsEnvironment"], "production")

    def test_rejects_disabled_mismatched_or_missing_native_push(self):
        """主包配置与生产推送权限须一致，旧包名和扩展夹带推送权限均不能发布。"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.ipa"
            for options in [dict(bundle="org.moviepilot.app"), dict(app_environment="disabled"),
                            dict(app_environment="development"), dict(signed_environment=None),
                            dict(signed_environment="development"), dict(widget_push=True),
                            dict(widgets=False, signed_environment=None)]:
                with self.subTest(options=options), self.assertRaises(ValueError):
                    archive(path, **options)
                    VERIFY.verify_ipa(path, "1.0.1", "1")

    def test_rejects_certificate_or_extra_entitlements(self):
        """扩展不能夹带 APNs；主包和扩展均不得包含 CMS 或调试权限。"""
        for signature in [metadata(flags=0), metadata(cms=b"synthetic-cms"), metadata(group="group.other"),
                          metadata(extra={"aps-environment": "development"}), metadata(extra={"get-task-allow": True})]:
            with self.assertRaises(ValueError):
                VERIFY.verify_device_executable(executable(signature=signature), widget_metadata=True)
        with self.assertRaises(ValueError):
            VERIFY.verify_device_executable(executable(signature=metadata(extra={"aps-environment": "production", "get-task-allow": True})),
                                            widget_metadata=True, native_push=True)

    def test_rejects_wrong_extension_version_platform_or_profile(self):
        """主包正确不能掩盖嵌入扩展是模拟器、旧版本或夹带描述文件。"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.ipa"
            for options in [dict(extension_version="1.0.0"), dict(extension_platform=7), dict(provision=True), dict(widgets=False, enabled=True)]:
                with self.subTest(options=options), self.assertRaises(ValueError):
                    archive(path, **options)
                    VERIFY.verify_ipa(path, "1.0.1", "1")

    def test_rejects_truncated_or_missing_signature(self):
        """共享组元数据不能缺失，损坏的索引和 Mach-O 均须明确失败。"""
        for binary in [b"", executable(), executable(signature=metadata()[:-12]), executable(platform=7, signature=metadata())]:
            with self.assertRaises(ValueError):
                VERIFY.verify_device_executable(binary, widget_metadata=True)


if __name__ == "__main__":
    unittest.main()
