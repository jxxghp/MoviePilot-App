"""验证样例投影的无执行边界、可重复性和失败时不输出残缺夹具。"""

import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "ios/native-v2-plugin-fixtures.py"
SPEC = importlib.util.spec_from_file_location("native_plugin_fixtures", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def _resolve_temp_root() -> Path:
    """本地存在外置构建卷时沿用 /Volumes/DISK/TmpBuild，在 GitHub Actions 等无外置卷环境回退到系统临时目录。"""
    external_volume = Path("/Volumes/DISK")
    if external_volume.is_dir() and os.access(external_volume, os.W_OK):
        return external_volume / "TmpBuild/moviepilot-ios-v2/plugin-fixture-tests"
    base = Path(os.environ.get("RUNNER_TEMP") or tempfile.gettempdir())
    return base / "moviepilot-ios-v2/plugin-fixture-tests"


TEMP_ROOT = _resolve_temp_root()


class PluginFixtureTests(unittest.TestCase):
    """夹具生成器只能读取 AST/Git 对象，不执行插件里的任何 Python。"""

    def test_rejects_executable_expressions(self):
        """调用、下标、推导式和未批准属性都不能偷偷变成执行路径。"""
        for expression in ["danger()", "__import__('os').system('x')", "x[0]", "[f() for f in x]", "settings.SECRET"]:
            with self.subTest(expression=expression):
                with self.assertRaises(MODULE.UnsupportedExpression):
                    MODULE.literal(ast.parse(expression, mode="eval").body, {})

    def test_uses_only_explicit_synthetic_symbols(self):
        """明确替换的属性只是字符串数据，格式转换或未知符号会失败。"""
        node = ast.parse('f"plugin/Example/run?apikey={settings.API_TOKEN}"', mode="eval").body
        self.assertEqual(MODULE.literal(node, {"settings.API_TOKEN": "fixture-only"}),
                         "plugin/Example/run?apikey=fixture-only")
        with self.assertRaises(MODULE.UnsupportedExpression):
            MODULE.literal(ast.parse('f"{x!r}"', mode="eval").body, {"x": "fixture"})

    def test_generation_reads_committed_ast_without_import(self):
        """有顶层副作用和未提交污染的假插件，仍只读取固定 SHA 的纯数据。"""
        TEMP_ROOT.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as directory:
            root = Path(directory)
            marker = root / "must-not-exist"
            path = root / "plugins.v3/example/__init__.py"
            path.parent.mkdir(parents=True)
            content = (f"from pathlib import Path\nPath({str(marker)!r}).write_text('bad')\n"
                       "class Example:\n def get_form(self):\n"
                       "  return [{'component': 'VSelect', 'props': {'items': choices}}], {'enabled': False}\n")
            path.write_text(content)
            self.git(root, "init", "-q")
            self.git(root, "add", "plugins.v3")
            self.git(root, "commit", "-qm", "fixture")
            sha = self.git(root, "rev-parse", "HEAD").strip()
            path.write_text("raise RuntimeError('working tree must not run')\n")
            entry = {"file": "example.json", "source": "plugins.v3/example/__init__.py",
                     "method": "get_form", "surface": "form", "symbols": {"choices": ["演示"]}}
            with patch.object(MODULE, "specifications", return_value=[entry]):
                MODULE.generate(root, sha, root / "output")
            result = json.loads((root / "output/example.json").read_text())
            self.assertFalse(result["model"]["enabled"])
            self.assertEqual(result["conf"][0]["props"]["items"], ["演示"])
            manifest = json.loads((root / "output/provenance.json").read_text())
            self.assertEqual(manifest["revision"], sha)
            self.assertEqual(manifest["fixtures"][0]["source_sha256"], hashlib.sha256(content.encode()).hexdigest())
            self.assertFalse(marker.exists())
            bad = {**entry, "file": "bad.json", "source": "plugins.v3/missing/__init__.py"}
            with patch.object(MODULE, "specifications", return_value=[entry, bad]):
                with self.assertRaises(subprocess.CalledProcessError):
                    MODULE.generate(root, sha, root / "failed-output")
            self.assertFalse((root / "failed-output").exists())

    def test_selector_skips_missing_optional_properties(self):
        """缺 props 的早期节点不能让后续合法图表候选崩溃或误选。"""
        tree = ast.parse("x = [{'component':'VApexChart'}, {'component':'VApexChart','props': trend}]")
        node = MODULE.select(tree, {"component": "VApexChart", "props_symbol": "trend", "symbols": {"trend": {}}})
        self.assertEqual(MODULE.literal(node, {"trend": {}})["props"], {})

    def test_source_constants_are_literal_unique_and_traced(self):
        """真实预设来自指定类常量；重复赋值、调用和其它类不能被偷偷运行或替代。"""
        spec = {"source_symbols": {"self._ITEMS": {"class": "Example", "name": "_ITEMS"}}}
        tree = ast.parse("class Example:\n _ITEMS = [{'title':'来源', 'value':1}]\n")
        symbols, evidence = MODULE.source_symbols(tree, spec)
        self.assertEqual(symbols["self._ITEMS"], [{"title": "来源", "value": 1}])
        self.assertEqual(evidence["self._ITEMS"]["line"], 2)
        for text in ["class Example:\n _ITEMS = run()\n",
                     "class Example:\n _ITEMS=[]\n _ITEMS=[1]\n", "class Other:\n _ITEMS=[]\n"]:
            with self.subTest(source=text), self.assertRaises(MODULE.UnsupportedExpression):
                MODULE.source_symbols(ast.parse(text), spec)

    @staticmethod
    def git(root, *args):
        """隔离测试仓库身份与 hooks，不修改用户 Git 配置、不签名、不访问远端。"""
        return subprocess.check_output([
            "git", "-C", str(root), "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
            "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", *args], text=True)


if __name__ == "__main__":
    unittest.main()
