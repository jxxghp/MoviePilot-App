"""验证插件 UI 验收服务的独立边界，避免界面测试依赖宽松伪后端获得假阳性。"""

import importlib.util
import json
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen


SPEC = importlib.util.spec_from_file_location(
    "native_plugin_ui_fixture", Path(__file__).resolve().parents[1] / "native-v2-plugin-ui-fixture.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PluginUIFixtureTests(unittest.TestCase):
    """真实回环 HTTP 分别验证身份、完整模型、故障和禁止前端回退。"""

    def setUp(self):
        """每项测试独立临时端口与内存配置，不占用模拟器 UI 测试服务。"""
        self.server = MODULE.PluginFixture(0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        """结束本案例监听，不留下线程或运行态用户配置。"""
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, path, method="GET", value=None, token="synthetic-native-a"):
        """标准 HTTP 调用；错误响应仍读取 JSON，令牌仅为固定合成字符串。"""
        data = json.dumps(value).encode() if value is not None else None
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = Request(self.base + path, data=data, method=method, headers=headers)
        try:
            response = urlopen(request, timeout=5)
        except HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def test_exact_endpoint_and_physical_full_model(self):
        """state 查询/尾斜杠与分身必须正确，完整模型未知大整数不能舍弃。"""
        self.assertEqual(self.request("/a/api/v1/plugin/?state=installed")[0], 200)
        self.assertEqual(self.request("/a/api/v1/plugin/?installed=true")[0], 404)
        status, form = self.request("/a/api/v1/plugin/form/MediaDirWatcher_copy")
        self.assertEqual(status, 200)
        model = form["model"]
        self.assertEqual(model["future"]["integer"], 9007199254740993)
        self.assertEqual(self.request("/a/api/v1/plugin/MediaDirWatcher", "PUT", model)[0], 404)
        partial = {key: value for key, value in model.items() if key != "future"}
        self.assertEqual(self.request("/a/api/v1/plugin/MediaDirWatcher_copy", "PUT", partial)[0], 400)
        model["scan_interval"] = "7"
        status, acknowledgement = self.request("/a/api/v1/plugin/MediaDirWatcher_copy", "PUT", model)
        self.assertEqual(status, 200)
        self.assertEqual(acknowledgement, {"success": True, "message": "", "data": None})
        _, result = self.request("/__plugins/state")
        self.assertEqual(result["receipts"], [{"plugin": "MediaDirWatcher_copy", "model": model}])

    def test_failure_does_not_commit_or_replay(self):
        """失败结果与成功回执独立，只有另一次显式 PUT 才推进模型。"""
        _, form = self.request("/a/api/v1/plugin/form/MediaDirWatcher_copy")
        model = form["model"]
        model["enabled"] = True
        self.request("/__plugins/config", "POST", {"mode": "fail_save_once"})
        self.assertEqual(self.request("/a/api/v1/plugin/MediaDirWatcher_copy", "PUT", model)[0], 503)
        _, state = self.request("/__plugins/state")
        self.assertFalse(state["models"]["MediaDirWatcher_copy"]["enabled"])
        self.assertEqual(state["receipts"], [])
        self.assertEqual(state["counts"]["PUT a/api/v1/plugin/MediaDirWatcher_copy"], 1)
        self.assertEqual(self.request("/a/api/v1/plugin/MediaDirWatcher_copy", "PUT", model)[0], 200)
        _, state = self.request("/__plugins/state")
        self.assertEqual(len(state["receipts"]), 1)

    def test_no_frontend_or_cross_instance_authentication(self):
        """插件接口同样约束账号/实例令牌，不返回 HTML、Vue 或 JS 兜底。"""
        path = "/a/api/v1/plugin/?state=installed"
        self.assertEqual(self.request(path, token=None)[0], 401)
        self.assertEqual(self.request(path, token="synthetic-native-b")[0], 401)
        self.assertEqual(self.request("/b/api/v1/plugin/?state=installed", token="synthetic-native-b")[0], 403)
        self.request("/__native/config", "POST", {"profile": "a", "mode": "expired"})
        self.assertEqual(self.request(path)[0], 401)
        for path in ["/a/", "/a/assets/index.js", "/a/plugin/MediaDirWatcher"]:
            self.assertEqual(self.request(path)[0], 404)

    def test_bound_new_fields_and_cron_types_are_not_dropped(self):
        """真实源码含默认模型里没有的绑定，完整提交可增加该键并保留未知原值。"""
        _, form = self.request("/a/api/v1/plugin/form/LibraryScraper_copy")
        model = form["model"]
        self.assertNotIn("exclude_paths", model)
        self.assertIn("err_hosts", model)
        model["cron"] = "0 0 last * *"
        model["exclude_paths"] = "/media/skip"
        self.assertEqual(self.request("/a/api/v1/plugin/LibraryScraper_copy", "PUT", model)[0], 200)
        _, form = self.request("/a/api/v1/plugin/form/CronCompatibilityFixture")
        self.assertEqual(type(form["model"]["cron"]), int)
        self.assertIsNone(form["model"]["empty"])
        self.assertNotIn("missing", form["model"])
        self.assertEqual(self.request("/a/api/v1/plugin/CronCompatibilityFixture", "PUT", form["model"])[0], 200)

    def test_combobox_source_and_synthetic_types_remain_distinct(self):
        """真实节点/预设未改写，合成模型的对象、字符串与空/缺失键均由完整 PUT 保留。"""
        _, installed = self.request("/a/api/v1/plugin/?state=installed")
        self.assertEqual(len(installed), 9)
        self.assertTrue(all(item.get("installed") is True for item in installed))
        _, form = self.request("/a/api/v1/plugin/form/CertManagerCombobox_copy")
        props = form["conf"][0]["props"]
        self.assertEqual(props["items"][2], {"title": "Cloudflare", "value": "dns_cf"})
        self.assertNotIn("return-object", props)
        model = form["model"]
        self.assertEqual(model["dns_provider"]["future"], 9007199254740993)
        model["dns_provider"] = props["items"][2]
        self.assertEqual(self.request("/a/api/v1/plugin/CertManagerCombobox_copy", "PUT", model)[0], 200)
        _, form = self.request("/a/api/v1/plugin/form/LibraryCombobox_copy")
        self.assertNotIn("items", form["conf"][0]["props"])
        self.assertTrue(form["conf"][0]["props"]["multiple"])
        self.assertEqual(form["model"]["libraries"][1]["future"], 9007199254740993)
        _, form = self.request("/a/api/v1/plugin/form/ComboboxModesFixture")
        self.assertIsNone(form["model"]["empty"])
        self.assertNotIn("missing", form["model"])


if __name__ == "__main__":
    unittest.main()
