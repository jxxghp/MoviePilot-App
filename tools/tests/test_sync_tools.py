"""验证 SSOT 同步脚本（版本、Design Tokens、多语言、静态资产）的确定性与 --check 门禁。"""

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("sync_all", ROOT / "tools/sync-all.py")
SYNC_ALL = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(SYNC_ALL)


class SyncToolsTests(unittest.TestCase):
    """确保 shared/ 单一事实源与三端生成产物一致。"""

    def test_sync_all_check_is_clean(self):
        drifted = SYNC_ALL.sync_all(ROOT, check=True)
        self.assertEqual(drifted, [], f"存在未同步产物：{drifted[:5]}")

    def test_generated_token_files_exist_for_all_three_platforms(self):
        for rel in [
            "ios/NativeDesignSystem/GeneratedTokens.swift",
            "android/design-system/src/main/java/com/moviepilot/designsystem/GeneratedTokens.kt",
            "harmony/commons/design_system/src/main/ets/tokens/GeneratedTokens.ets",
        ]:
            path = ROOT / rel
            self.assertTrue(path.is_file(), f"缺少生成文件：{rel}")
            self.assertIn("GeneratedDesignTokens", path.read_text(encoding="utf-8"))

    def test_medals_logos_and_l10n_synced_to_android_and_harmony(self):
        android_medals = list((ROOT / "android/app/src/main/assets/community_medals").iterdir())
        harmony_medals = list((ROOT / "harmony/entry/src/main/resources/rawfile/community_medals").iterdir())
        harmony_logos = list((ROOT / "harmony/entry/src/main/resources/rawfile/logos").iterdir())
        self.assertEqual(len(android_medals), 73)
        self.assertEqual(len(harmony_medals), 73)
        self.assertGreaterEqual(len(harmony_logos), 36)
        self.assertTrue((ROOT / "android/app/src/main/res/values/strings.xml").is_file())
        self.assertTrue((ROOT / "harmony/entry/src/main/resources/base/element/string.json").is_file())

    def test_plugin_shell_runtime_synced_to_all_three_platforms(self):
        for rel in [
            "shared/plugin-shell/manifest.json",
            "shared/plugin-shell/plugin-shell.html",
            "ios/MoviePilot/Resources/PluginShell/plugin-shell.html",
            "android/core-plugin-host/src/main/assets/plugin_shell/plugin-shell.html",
            "harmony/entry/src/main/resources/rawfile/plugin_shell/plugin-shell.html",
        ]:
            self.assertTrue((ROOT / rel).is_file(), f"缺少 plugin-shell 资产：{rel}")

    def test_screenshot_gallery_links_match_files_on_disk(self):
        import re

        readme = (ROOT / "screenshots/README.md").read_text(encoding="utf-8")
        refs = set(re.findall(r"!\[[^\]]*\]\(([^)]+)\)", readme))
        for sub in ("ios", "android", "harmony"):
            on_disk = {
                f"{sub}/{p.name}"
                for p in (ROOT / "screenshots" / sub).iterdir()
                if p.is_file() and p.name != ".DS_Store"
            }
            ref_sub = {r for r in refs if r.startswith(sub + "/")}
            self.assertEqual(ref_sub, on_disk, f"{sub} 截图引用与磁盘文件不一致")

    def test_verify_apk_rejects_debug_cert_when_release_cert_required(self):
        import tempfile
        import zipfile

        apk_spec = importlib.util.spec_from_file_location(
            "verify_apk", ROOT / "tools/android/verify-apk.py"
        )
        verify_apk_mod = importlib.util.module_from_spec(apk_spec)
        assert apk_spec and apk_spec.loader
        apk_spec.loader.exec_module(verify_apk_mod)

        def build_synthetic_apk(target_path: Path, cert_cn: bytes) -> None:
            with zipfile.ZipFile(target_path, "w") as zf:
                zf.writestr("AndroidManifest.xml", b"manifest\x002.0.5\x00")
                zf.writestr("classes.dex", b"dex\n039\x00")
                zf.writestr("lib/arm64-v8a/libmoviepilot_core.so", b"\x7fELF")
                for idx in range(73):
                    zf.writestr(f"assets/community_medals/m_{idx}.svg", b"<svg/>")
                for idx in range(36):
                    zf.writestr(f"res/drawable/logo_brand_{idx}.png", b"png")
                zf.writestr("META-INF/CERT.RSA", b"CERT:" + cert_cn)

        with tempfile.TemporaryDirectory() as tmp:
            debug_apk = Path(tmp) / "debug-signed.apk"
            release_apk = Path(tmp) / "release-signed.apk"
            build_synthetic_apk(debug_apk, b"CN=Android Debug,O=Android,C=US")
            build_synthetic_apk(release_apk, b"CN=MoviePilot,OU=Mobile,O=MoviePilot,C=CN")

            # 普通 CI 门禁允许无密钥回退验证打包结构
            report_ci = verify_apk_mod.verify_apk(debug_apk, "2.0.5", ["arm64-v8a"], False)
            self.assertEqual(report_ci["abis"], ["arm64-v8a"])

            # 正式发版门禁必须拒绝 Android Debug 临时证书，放行固定发布证书
            with self.assertRaises(ValueError):
                verify_apk_mod.verify_apk(debug_apk, "2.0.5", ["arm64-v8a"], True)
            report_rel = verify_apk_mod.verify_apk(release_apk, "2.0.5", ["arm64-v8a"], True)
            self.assertEqual(report_rel["expectedVersion"], "2.0.5")


if __name__ == "__main__":
    unittest.main()
