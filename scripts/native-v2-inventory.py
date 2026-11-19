#!/usr/bin/env python3
"""从固定 Git 提交生成 iOS v2 范围基线；不导入或运行后端及插件代码。"""

import argparse
import ast
from collections import Counter
import json
from pathlib import Path
import re
import subprocess


class GitSource:
    """只读取一个已获取的版本树，不使用该仓库未提交的源码或凭据。"""

    def __init__(self, root: Path, ref: str):
        """在扫描开始时固定 SHA，防止扫描中移动的远端引用混合两个版本。"""
        self.root = root
        self.ref = ref
        self.sha = self.git("rev-parse", "--verify", f"{ref}^{{commit}}").strip()

    def git(self, *args: str) -> str:
        """通过参数数组调用 Git，不经过 shell，也不隐式 fetch 或修改工作区。"""
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True)

    def read(self, path: str) -> str:
        """按固定提交读取公开源码，不读取运行配置和本机安装数据。"""
        return self.git("show", f"{self.sha}:{path}")

    def files(self) -> list[str]:
        """列举版本树中的受跟踪文件，排除其它任务的未提交文件。"""
        return self.git("ls-tree", "-r", "--name-only", self.sha).splitlines()

    def baseline(self) -> dict:
        """输出可重新定位的仓库、引用及完整提交，不保存本机绝对路径。"""
        return {"repository": self.root.name, "ref": self.ref, "sha": self.sha}


def frontend_routes(source: str) -> list[dict]:
    """提取当前字面量路由；无法配对页面 import 时失败，避免静默漏记。"""
    pattern = (
        r"path:\s*'([^']+)',\s*(?:name:\s*'[^']+',\s*)?"
        r"component:\s*\(\)\s*=>\s*import\('(\.\./pages/[^']+)'\)"
    )
    routes = []
    for match in re.finditer(pattern, source):
        path, component = match.groups()
        end = source.find("\n        },", match.end())
        block = source[match.start():end if end >= 0 else match.end()]
        permission = re.search(r"permission:\s*'([^']+)'", block)
        feature = re.search(r"feature:\s*PERMISSION_FEATURE\.([A-Z_]+)", block)
        routes.append({
            "path": "/" + path.lstrip("/"),
            "source": component.replace("../", "src/", 1),
            "permission": permission.group(1) if permission else None,
            "feature": feature.group(1) if feature else None,
        })
    imports = re.findall(r"component:\s*\(\)\s*=>\s*import\('\.\./pages/", source)
    if len(routes) != len(imports) or len({item["path"] for item in routes}) != len(routes):
        raise ValueError("路由格式已变化或出现重复路径，请先更新扫描器并人工核对。")
    return routes


def endpoint_counts(source: str) -> dict[str, int]:
    """统计源码 HTTP 声明下界；不把未挂载、动态注册或继承路由当成已验证 API。"""
    counts = Counter()
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for decorator in node.decorator_list:
            if not isinstance(decorator, ast.Call) or not isinstance(decorator.func, ast.Attribute):
                continue
            method = decorator.func.attr
            if method in {"get", "post", "put", "patch", "delete", "head", "options", "websocket", "api_route"}:
                if decorator.args and isinstance(decorator.args[0], ast.Constant):
                    counts[method.upper()] += 1
    return dict(sorted(counts.items()))


def plugin_symbols(source: str) -> tuple[list[str], list[str]]:
    """扫描 Python 字典中的字面量组件与声明方法，不执行动态 UI 生成函数。"""
    tree = ast.parse(source)
    components = set()
    methods = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Dict):
            for key, value in zip(node.keys, node.values):
                if isinstance(key, ast.Constant) and key.value == "component":
                    if isinstance(value, ast.Constant) and isinstance(value.value, str):
                        components.add(value.value)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.name in {"get_form", "get_page", "get_dashboard", "get_sidebar_nav", "get_render_mode", "get_agent_pets"}:
                methods.add(node.name)
    return sorted(components), sorted(methods)


def build_inventory(sources: dict[str, GitSource], as_of: str) -> dict:
    """生成页面、弹窗、设置、API 和三代官方插件的可审阅静态范围清单。"""
    front = sources["frontend"]
    front_files = front.files()
    production_vue = [p for p in front_files if p.endswith(".vue") and "/__tests__/" not in p]
    frontend = {
        "routes": frontend_routes(front.read("src/router/index.ts")),
        "pages": [p for p in production_vue if p.startswith("src/pages/")],
        "dialogs": [p for p in production_vue if p.startswith("src/components/dialog/")],
        "setting_views": [p for p in production_vue if p.startswith("src/views/setting/")],
        "components": [p for p in production_vue if p.startswith("src/components/")],
        "api_modules": [p for p in front_files if p.startswith("src/api/") and p.endswith(".ts") and "/__tests__/" not in p],
    }
    backend = sources["backend"]
    endpoints = {}
    for path in backend.files():
        if path.startswith("app/api/endpoints/") and path.endswith(".py"):
            counts = endpoint_counts(backend.read(path))
            if counts:
                endpoints[path] = counts
    plugins = sources["plugins"]
    plugin_files = [p for p in plugins.files() if re.fullmatch(r"plugins(?:\.v[23])?/[^/]+/__init__\.py", p)]
    components = Counter()
    contracts = []
    for path in plugin_files:
        symbols, methods = plugin_symbols(plugins.read(path))
        components.update(symbols)
        if path.startswith("plugins.v3/"):
            contracts.append({"source": path, "declared_methods": methods, "literal_components": symbols})
    return {
        "as_of": as_of,
        "method": "Read-only pinned Git objects. Static declarations/literals only; no host or plugin execution. Counts are scope evidence, not runtime coverage or compatibility acceptance.",
        "baselines": {name: source.baseline() for name, source in sources.items()},
        "frontend": frontend,
        "backend": {
            "router_registry": "app/api/routers.py",
            "declared_operation_counts": endpoints,
            "note": "Includes unmounted declarations; excludes runtime plugin APIs and routes declared outside app/api/endpoints. Reconcile actual OpenAPI and each consumed operation during its implementation leaf.",
        },
        "plugins": {
            "index_counts": {key: len(json.loads(plugins.read(path))) for key, path in [
                ("v1", "package.json"), ("v2", "package.v2.json"), ("v3", "package.v3.json")
            ]},
            "source_counts": dict(sorted(Counter(p.split("/")[0] for p in plugin_files).items())),
            "literal_components_by_source_file_count": dict(components.most_common()),
            "v3_contracts": contracts,
            "note": "Methods may be inherited; components/expressions may be generated in helper files. Third-party and installed legacy plugins require their own sanitized runtime fixtures.",
        },
    }


def main() -> None:
    """显式接收版本和输出位置，支持后续阶段增量核对与离线重放。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--as-of", required=True)
    parser.add_argument("--app-ref", default="origin/main")
    parser.add_argument("--frontend-ref", default="origin/v3")
    parser.add_argument("--backend-ref", default="origin/v3")
    parser.add_argument("--plugins-ref", default="origin/main")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sources = {
        name: GitSource(args.workspace / repository, getattr(args, f"{name}_ref"))
        for name, repository in [
            ("app", "MoviePilot-App"), ("frontend", "MoviePilot-Frontend"),
            ("backend", "MoviePilot"), ("plugins", "MoviePilot-Plugins"),
        ]
    }
    result = build_inventory(sources, args.as_of)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "frontend": {key: len(value) for key, value in result["frontend"].items()},
        "backend_declared_operations": sum(sum(counts.values()) for counts in result["backend"]["declared_operation_counts"].values()),
        "plugin_component_kinds": len(result["plugins"]["literal_components_by_source_file_count"]),
        "output": str(args.output),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
