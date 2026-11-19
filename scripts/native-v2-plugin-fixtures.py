#!/usr/bin/env python3
"""从固定 Git 对象中只读提取 UI 数据，绝不导入插件、求值代码或读取用户配置。"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import subprocess


class UnsupportedExpression(ValueError):
    """静态投影遇到未明确允许的表达式时失败，不能悄悄运行或省略。"""


def literal(node: ast.AST, symbols: dict) -> object:
    """仅解释 JSON 常量容器、字符串拼接和显式合成替换，不调用任何函数。"""
    if isinstance(node, ast.Constant):
        if node.value is None or isinstance(node.value, (str, bool, int, float)):
            return node.value
    if isinstance(node, (ast.List, ast.Tuple)):
        return [literal(item, symbols) for item in node.elts]
    if isinstance(node, ast.Dict) and all(key is not None for key in node.keys):
        return {literal(key, symbols): literal(value, symbols) for key, value in zip(node.keys, node.values)}
    if isinstance(node, (ast.Name, ast.Attribute)) and ast.unparse(node) in symbols:
        return symbols[ast.unparse(node)]
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        value = literal(node.operand, symbols)
        if type(value) in (int, float):
            return -value
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = literal(node.left, symbols), literal(node.right, symbols)
        if isinstance(left, str) and isinstance(right, str):
            return left + right
    if isinstance(node, ast.JoinedStr):
        parts = []
        for value in node.values:
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                parts.append(value.value)
            elif isinstance(value, ast.FormattedValue) and value.conversion == -1 and value.format_spec is None:
                replacement = literal(value.value, symbols)
                if not isinstance(replacement, str):
                    raise UnsupportedExpression("仅允许显式字符串替换")
                parts.append(replacement)
            else:
                raise UnsupportedExpression("不执行格式化表达式")
        return "".join(parts)
    raise UnsupportedExpression(f"不支持的静态语法：{type(node).__name__}")


def dictionary(node: ast.AST) -> dict[str, ast.AST]:
    """只按字面量字符串键索引 AST，不执行计算键或展开。"""
    if not isinstance(node, ast.Dict):
        return {}
    return {key.value: value for key, value in zip(node.keys, node.values)
            if isinstance(key, ast.Constant) and isinstance(key.value, str)}


def select(tree: ast.AST, spec: dict) -> ast.AST:
    """按固定源码顺序选首个满足约束的节点，动态候选不能冒充实际运行态。"""
    if spec.get("method"):
        method = next(node for node in ast.walk(tree)
                      if isinstance(node, ast.FunctionDef) and node.name == spec["method"])
        candidates = [node.value for node in ast.walk(method) if isinstance(node, ast.Return)]
    else:
        candidates = []
        for node in ast.walk(tree):
            fields = dictionary(node)
            component = fields.get("component")
            if not isinstance(component, ast.Constant) or component.value != spec["component"]:
                continue
            properties = dictionary(fields.get("props"))
            if spec.get("property") and spec["property"] not in properties:
                continue
            if spec.get("events") and "events" not in fields:
                continue
            if spec.get("props_symbol") and (fields.get("props") is None or ast.unparse(fields["props"]) != spec["props_symbol"]):
                continue
            if spec.get("items_symbol") and (properties.get("items") is None or ast.unparse(properties["items"]) != spec["items_symbol"]):
                continue
            candidates.append(node)
    for candidate in candidates:
        try:
            literal(candidate, spec.get("symbols", {}))
            return candidate
        except UnsupportedExpression:
            continue
    raise ValueError("没有满足静态约束的候选节点")


def specifications() -> list[dict]:
    """所有动态替换均在本地写明为合成值，未从运行服务读取。"""
    return [
        {"file": "autosignin-form.json", "source": "plugins.v3/autosignin/__init__.py",
         "method": "get_form", "surface": "form",
         "symbols": {"site_options": [{"title": "演示站点", "value": 1}]}},
        {"file": "autosports-editor.json", "source": "plugins.v3/autosports/ui/__init__.py",
         "component": "VAceEditor", "surface": "form",
         "model": {"competitions_config": "{}"}},
        {"file": "certmanager-script.json", "source": "plugins.v3/certmanager/__init__.py",
         "component": "VBtn", "property": "onclick", "surface": "form"},
        {"file": "autosubtitle-condition.json", "source": "plugins.v3/autosubtitle/__init__.py",
         "component": "VTextField", "property": "v-show", "surface": "form",
         "model": {"auto_sync": True, "save_path_strategy": "custom"}},
        {"file": "animeupscale-table.json", "source": "plugins.v3/animeupscale/__init__.py",
         "component": "VDataTable", "items_symbol": "job_rows", "surface": "page",
         "symbols": {"job_rows": [{"id": "fixture-job", "input": "/media/example.mkv",
                                   "model": "anime", "status": "queued", "progress": 0,
                                   "fps": 0, "error": None}]}},
        {"file": "chatgpt-action.json", "source": "plugins.v3/chatgpt/__init__.py",
         "component": "VBtn", "events": True, "surface": "page",
         "symbols": {"settings.API_TOKEN": "fixture-only-not-a-real-token"}},
        {"file": "seedstats-chart.json", "source": "plugins.v3/seedstats/__init__.py",
         "component": "VApexChart", "props_symbol": "trend", "surface": "dashboard",
         "symbols": {"trend": {"type": "area", "height": 240,
                               "options": {"xaxis": {"categories": ["00:00", "01:00"]}},
                               "series": [{"name": "上传", "data": [1, 2]}]}}},
    ]


def generate(repository: Path, ref: str, output: Path) -> None:
    """先完成所有静态投影再写夹具，避免源格式变化导致半套结果。"""
    def git(*args: str) -> str:
        """命令参数独立传递，不把路径或引用插入 shell。"""
        return subprocess.check_output(["git", "-C", str(repository), *args], text=True)

    revision = git("rev-parse", ref + "^{commit}").strip()
    pending = {}
    manifest = {"revision": revision, "method": "AST data only; no plugin imports or execution", "fixtures": []}
    for spec in specifications():
        source = git("show", revision + ":" + spec["source"])
        node = select(ast.parse(source), spec)
        value = literal(node, spec.get("symbols", {}))
        surface = spec["surface"]
        if spec.get("method"):
            conf, model = value
            payload = {"render_mode": "vuetify", "conf": conf, "model": model}
        elif surface == "form":
            payload = {"render_mode": "vuetify", "conf": [value], "model": spec.get("model", {})}
        elif surface == "page":
            payload = {"render_mode": "vuetify", "page": [value]}
        else:
            payload = {"render_mode": "vuetify", "id": "SeedStats_fixture", "source_plugin_id": "SeedStats",
                       "key": "traffic", "name": "演示统计", "attrs": {"refresh": 30},
                       "cols": {"cols": 12, "md": 6}, "elements": [value]}
        encoded = json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        pending[spec["file"]] = encoded
        manifest["fixtures"].append({
            "file": spec["file"], "surface": surface, "source": spec["source"],
            "line": node.lineno, "source_sha256": hashlib.sha256(source.encode()).hexdigest(),
            "fixture_sha256": hashlib.sha256(encoded.encode()).hexdigest(),
            "symbols": spec.get("symbols", {}),
            "note": "Envelope/model are synthetic unless get_form tuple; approved dynamic values replaced explicitly.",
        })
    output.mkdir(parents=True, exist_ok=True)
    for name, content in pending.items():
        (output / name).write_text(content)
    (output / "provenance.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    """命令行显式指定来源与输出，默认引用本叶子已复核的固定版本。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugins-repo", type=Path, required=True)
    parser.add_argument("--ref", default="5d473864ee9d3d036b28a124262f38f773a2a452")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    generate(args.plugins_repo, args.ref, args.output)


if __name__ == "__main__":
    main()
