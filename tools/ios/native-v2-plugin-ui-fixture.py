#!/usr/bin/env python3
"""在原生登录 API-only 夹具上增加插件配置闭环，全部内容为源码样例或明确合成数据。"""

import argparse
from collections import Counter
import copy
import importlib.util
import json
from pathlib import Path
import time
from urllib.parse import parse_qs, urlsplit


BASE_PATH = Path(__file__).with_name("native-v2-fixture.py")
SPEC = importlib.util.spec_from_file_location("native_entry_fixture", BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)
FIXTURE_PATH = Path(__file__).resolve().parents[2] / "ios/Tests/MoviePilotPluginUITests/Fixtures/mediadirwatcher-form.json"
PHYSICAL_ID = "MediaDirWatcher_copy"


def documents():
    """整个官方 get_form 仅复制 JSON；未来字段/分身/复杂控制用例显式合成，不执行插件。"""
    source = json.loads(FIXTURE_PATH.read_text())
    source["model"]["future"] = {"integer": 9007199254740993, "hidden": "fixture-only-hidden"}
    unsupported = copy.deepcopy(source)
    unsupported["conf"].append({"component": "VRow", "props": {"v-show": "false"}, "content": [
        {"component": "VCronField", "props": {"model": "cron", "label": "计划"}},
        {"component": "VAceEditor", "props": {"model": "advanced", "label": "高级配置"}}
    ]})
    unsupported["model"]["cron"] = "0 9 * * *"
    controls = {
        "render_mode": "vuetify",
        "conf": [{"component": "VForm", "content": [
            {"component": "VRow", "content": [
                {"component": "VSwitch", "props": {"model": "enabled", "label": "显示目录"}},
                {"component": "VTextField", "props": {"model": "path", "label": "条件目录", "v-show": "enabled"}},
            ]},
            {"component": "VRow", "content": [
                {"component": "VSelect", "props": {"model": "sources", "label": "数据来源", "multiple": True, "clearable": True,
                    "items": [{"title": "数字一", "value": 1}, {"title": "字符一", "value": "1"}, {"title": "数字二", "value": 2}]}},
                {"component": "VTextField", "props": {"model": "secret", "label": "合成密码", "type": "password"}},
                {"component": "VTextField", "props": {"model": "amount", "label": "限制数量", "type": "number", "min": 1, "max": 9}},
            ]},
        ]}],
        "model": {"enabled": False, "path": "/media/preserved", "sources": [1, "old"],
                  "secret": "fixture-only-private", "amount": 2, "future": {"integer": 9007199254740993}},
    }
    cron = json.loads(FIXTURE_PATH.with_name("libraryscraper-form.json").read_text())
    cron["model"]["future"] = {"integer": 9007199254740993, "hidden": "fixture-only-hidden"}
    compatibility = {
        "render_mode": "vuetify",
        "conf": [{"component": "VSwitch", "props": {"model": "enabled", "label": "启用计划"}}] + [
            {"component": "VCronField", "props": {"model": key, "label": title, "clearable": key != "empty"}}
            for key, title in [("cron", "插件间隔"), ("empty", "空值计划"), ("missing", "可选计划")]],
        "model": {"enabled": False, "cron": 6, "empty": None, "future": {"integer": 9007199254740993}},
    }
    weekday = json.loads(FIXTURE_PATH.with_name("libraryintegrity-cron-node.json").read_text())
    weekday["model"]["future"] = {"integer": 9007199254740993, "hidden": "fixture-only-hidden"}
    cert_combo = json.loads(FIXTURE_PATH.with_name("certmanager-combobox-node.json").read_text())
    library_combo = json.loads(FIXTURE_PATH.with_name("libraryintegrity-combobox-node.json").read_text())
    for document in [cert_combo, library_combo]:
        document["model"]["future"] = {"integer": 9007199254740993, "hidden": "fixture-only-hidden"}
    combo_modes = {
        "render_mode": "vuetify",
        "conf": [{"component": "VCombobox", "props": {
            "model": "choice", "label": "标量预设", "return-object": False, "clearable": True,
            "items": [{"title": "数字一", "value": 1}, {"title": "字符一", "value": "1"},
                      {"title": "精确数字", "value": 9007199254740993}],
        }}] + [{"component": "VCombobox", "props": {"model": key, "label": label, "clearable": True}}
               for key, label in [("empty", "空值"), ("missing", "缺失值")]],
        "model": {"choice": "legacy", "empty": None, "future": {"integer": 9007199254740993}},
    }
    return {PHYSICAL_ID: source, "UnsupportedFixture": unsupported, "NativeControlsFixture": controls,
            "LibraryScraper_copy": cron, "CronCompatibilityFixture": compatibility,
            "LibraryIntegrityWeekdayFixture": weekday, "CertManagerCombobox_copy": cert_combo,
            "LibraryCombobox_copy": library_combo, "ComboboxModesFixture": combo_modes}


class PluginFixture(BASE.NativeFixture):
    """使用相同真实登录/身份契约，新增状态仅留在进程内存。"""

    def __init__(self, port):
        """回环监听后替换处理器，不启动浏览器或任何前端服务。"""
        super().__init__(port)
        self.RequestHandlerClass = PluginHandler
        self.documents = documents()
        self.plugin_counts = Counter()
        self.plugin_mode = "ready"
        self.receipts = []


class PluginHandler(BASE.NativeHandler):
    """精确路径/查询/身份白名单，不接受任意插件代理地址。"""

    def do_PUT(self):
        """配置提交只有明确一次 PUT，没有自动重试端点。"""
        self.dispatch()

    def dispatch(self):
        """登录复用原夹具；插件接口严格校验管理员、部署前缀与物理 ID。"""
        url = urlsplit(self.path)
        if not url.path.startswith("/__plugins/") and "/api/v1/plugin" not in url.path:
            return super().dispatch()
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 <= length <= 4 * 1024 * 1024:
            return self.reply(413, {"success": False})
        body = self.rfile.read(length)
        if url.path == "/__plugins/state" and self.command == "GET":
            with self.server.lock:
                value = {"counts": dict(self.server.plugin_counts), "receipts": copy.deepcopy(self.server.receipts),
                         "models": {key: copy.deepcopy(value["model"]) for key, value in self.server.documents.items()},
                         "unexpected": dict(self.server.unexpected)}
            return self.reply(200, value)
        if url.path == "/__plugins/config" and self.command == "POST":
            try:
                value = json.loads(body)
                mode = value.get("mode", "ready")
                if mode not in {"ready", "fail_save_once", "slow_save"}:
                    raise ValueError()
            except (ValueError, TypeError, AttributeError):
                return self.reply(400, {"success": False})
            with self.server.lock:
                self.server.plugin_mode = mode
                if value.get("reset"):
                    self.server.documents = documents()
                    self.server.plugin_counts.clear()
                    self.server.receipts.clear()
            return self.reply(200, {"success": True})
        parts = url.path.strip("/").split("/")
        name = parts[0] if parts else ""
        endpoint = "/".join(parts[1:]) + ("/" if url.path.endswith("/") else "")
        with self.server.lock:
            self.server.plugin_counts[f"{self.command} {name}/{endpoint}"] += 1
            mode = self.server.profiles.get(name, {}).get("mode")
        if mode is None or mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            return self.reply(401, {"success": False})
        if name != "a":
            return self.reply(403, {"success": False})
        if self.command == "GET" and endpoint == "api/v1/plugin/" and parse_qs(url.query) == {"state": ["installed"]}:
            return self.reply(200, [
                {"id": PHYSICAL_ID, "source_plugin_id": "MediaDirWatcher", "installed": True,
                 "plugin_name": "媒体目录监控", "plugin_desc": "监控媒体目录中的新增内容", "plugin_version": "1.2.1"},
                {"id": "NativeControlsFixture", "source_plugin_id": "NativeControlsFixture", "installed": True,
                 "plugin_name": "原生控件验收", "plugin_desc": "合成条件、多选与密码用例", "plugin_version": "fixture"},
                {"id": "UnsupportedFixture", "source_plugin_id": "MediaDirWatcher", "installed": True,
                 "plugin_name": "未支持能力验收", "plugin_desc": "合成隐藏 Cron 与未支持编辑器", "plugin_version": "fixture"},
                {"id": "LibraryScraper_copy", "source_plugin_id": "LibraryScraper", "installed": True,
                 "plugin_name": "媒体库刮削", "plugin_desc": "官方完整 Cron 表单（合成服务）", "plugin_version": "fixture"},
                {"id": "CronCompatibilityFixture", "source_plugin_id": "CronCompatibilityFixture", "installed": True,
                 "plugin_name": "计划兼容验收", "plugin_desc": "合成间隔、空值与可选字段", "plugin_version": "fixture"},
                {"id": "LibraryIntegrityWeekdayFixture", "source_plugin_id": "LibraryIntegrity", "installed": True,
                 "plugin_name": "数字星期源码节点", "plugin_desc": "真实 Cron 节点与合成模型，非完整插件表单", "plugin_version": "fixture"},
                {"id": "CertManagerCombobox_copy", "source_plugin_id": "CertManager", "installed": True, "plugin_name": "DNS 组合框（来源节点）",
                 "plugin_desc": "真实预设与节点；模型合成，非完整插件", "plugin_version": "fixture"},
                {"id": "LibraryCombobox_copy", "source_plugin_id": "LibraryIntegrity", "installed": True, "plugin_name": "媒体库组合框（来源节点）",
                 "plugin_desc": "真实空预设多选节点；模型合成", "plugin_version": "fixture"},
                {"id": "ComboboxModesFixture", "installed": True, "plugin_name": "组合框类型验收", "plugin_desc": "合成标量、空值与缺失值", "plugin_version": "fixture"},
            ], {"X-Total-Count": "9"})
        prefix = "api/v1/plugin/form/"
        if self.command == "GET" and endpoint.startswith(prefix) and not url.query:
            plugin = endpoint[len(prefix):]
            with self.server.lock:
                document = copy.deepcopy(self.server.documents.get(plugin))
            if document is not None:
                return self.reply(200, document)
        prefix = "api/v1/plugin/"
        if self.command == "PUT" and endpoint.startswith(prefix) and not url.query:
            plugin = endpoint[len(prefix):]
            with self.server.lock:
                original = self.server.documents.get(plugin)
                save_mode = self.server.plugin_mode
                if save_mode == "fail_save_once":
                    self.server.plugin_mode = "ready"
            if original is not None:
                try:
                    value = json.loads(body)
                    if not isinstance(value, dict) or not set(original["model"]).issubset(value) or "application/json" not in self.headers.get("Content-Type", ""):
                        raise ValueError()
                except (ValueError, TypeError):
                    return self.reply(400, {"success": False})
                if save_mode == "slow_save":
                    time.sleep(3)
                if save_mode == "fail_save_once":
                    return self.reply(503, {"success": False})
                with self.server.lock:
                    original["model"] = value
                    self.server.receipts.append({"plugin": plugin, "model": copy.deepcopy(value)})
                return self.reply(200, {"success": True, "message": "", "data": None})
        with self.server.lock:
            self.server.unexpected[f"{self.command} {url.path}"] += 1
        self.reply(404, {"success": False})


def main():
    """与原入口夹具共用 5330，显式启动后只保存合成内存数据。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=5330)
    args = parser.parse_args()
    server = PluginFixture(args.port)
    print(f"Native plugin API-only fixture: 127.0.0.1:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
