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

    def test_medals_and_l10n_synced_to_android_and_harmony(self):
        android_medals = list((ROOT / "android/app/src/main/assets/community_medals").iterdir())
        harmony_medals = list((ROOT / "harmony/entry/src/main/resources/rawfile/community_medals").iterdir())
        self.assertEqual(len(android_medals), 73)
        self.assertEqual(len(harmony_medals), 73)
        self.assertTrue((ROOT / "android/app/src/main/res/values/strings.xml").is_file())
        self.assertTrue((ROOT / "harmony/entry/src/main/resources/base/element/string.json").is_file())


if __name__ == "__main__":
    unittest.main()
