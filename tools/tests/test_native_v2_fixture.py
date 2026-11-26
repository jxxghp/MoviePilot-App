"""用真实回环 HTTP 验证夹具没有前端兜底、跨实例令牌或自动初始化捷径。"""

import importlib.util
import json
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

SPEC = importlib.util.spec_from_file_location(
    "native_fixture", Path(__file__).resolve().parents[1] / "ios/native-v2-fixture.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NativeFixtureTests(unittest.TestCase):
    """每个案例独立端口、状态与合成账号，不访问真实后端或磁盘认证信息。"""

    def setUp(self):
        """启动线程化夹具，以真实 HTTP 检验响应和计数。"""
        self.server = MODULE.NativeFixture(0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        """等待夹具关闭，避免测试之间遗留监听端口。"""
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path, body=None, content="application/json", token=None):
        """只收集状态和 JSON；不将认证输入输出到日志。"""
        headers = {"Content-Type": content}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = Request(self.base + path, data=body, headers=headers)
        try:
            response = urlopen(request, timeout=5)
        except HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def test_frontend_is_unavailable_and_recorded(self):
        """HTML、JS 和未声明路径只能返回 404，不能靠假前端使 UI 测试通过。"""
        for path in ("/a/", "/a/index.html", "/a/assets/app.js"):
            self.assertEqual(self.request(path)[0], 404)
        _, stats = self.request("/__native/stats")
        self.assertEqual(sum(stats["unexpected"].values()), 3)

    def test_current_user_rejects_another_instances_token(self):
        """同一主机的不同部署子路径仍必须使用各自令牌。"""
        self.assertEqual(self.request("/a/api/v1/user/current", token="synthetic-native-b")[0], 401)
        status, identity = self.request("/a/api/v1/user/current", token="synthetic-native-a")
        self.assertEqual(status, 200)
        self.assertEqual(identity["data"]["name"], "native-a")

    def test_media_permissions_pagination_and_null_dashboard_count(self):
        """影视发现权限不等于 PT 搜索权限，分页与未报告统计保留后端语义。"""
        _, ready_identity = self.request("/b/api/v1/user/current", token="synthetic-native-b")
        self.assertTrue(ready_identity["data"]["permissions"]["discovery"])
        self.assertTrue(ready_identity["data"]["permissions"]["search"])

        self.request("/__native/config", b'{"profile":"b","mode":"search-failed"}')
        _, failed_identity = self.request("/b/api/v1/user/current", token="synthetic-native-b")
        self.assertTrue(failed_identity["data"]["permissions"]["discovery"])
        self.assertEqual(
            self.request(
                "/b/api/v1/media/search?title=galaxy&type=media&count=8&page=1",
                token="synthetic-native-b",
            )[0],
            503,
        )

        self.request("/__native/config", b'{"profile":"b","mode":"discovery-only"}')
        status, identity = self.request("/b/api/v1/user/current", token="synthetic-native-b")
        self.assertEqual(status, 200)
        self.assertTrue(identity["data"]["permissions"]["discovery"])
        self.assertFalse(identity["data"]["permissions"]["search"])

        base = "/b/api/v1/"
        search = "media/search?title=galaxy&type=media&count=8&page="
        status, first = self.request(base + search + "1", token="synthetic-native-b")
        self.assertEqual((status, len(first["data"])), (200, 8))
        status, second = self.request(base + search + "2", token="synthetic-native-b")
        self.assertEqual((status, len(second["data"])), (200, 1))
        status, discovered = self.request(
            base + "discover/tmdb_movies?page=2", token="synthetic-native-b"
        )
        self.assertEqual((status, len(discovered["data"])), (200, 1))

        self.request("/__native/config", b'{"profile":"b","mode":"resource-search-only"}')
        _, restricted = self.request("/b/api/v1/user/current", token="synthetic-native-b")
        self.assertFalse(restricted["data"]["permissions"]["discovery"])
        self.assertTrue(restricted["data"]["permissions"]["search"])
        self.assertEqual(
            self.request(base + "discover/tmdb_movies?page=1", token="synthetic-native-b")[0],
            403,
        )
        self.assertEqual(
            self.request(base + "recommend/tmdb_trending?page=1", token="synthetic-native-b")[0],
            403,
        )
        self.assertEqual(
            self.request(base + "mediaserver/clients", token="synthetic-native-b")[0],
            403,
        )
        self.assertEqual(self.request(base + search + "1", token="synthetic-native-b")[0], 403)

        _, dashboard = self.request("/a/api/v1/dashboard/statistic", token="synthetic-native-a")
        self.assertIsNone(dashboard["data"]["episode_count"])
        self.assertEqual(dashboard["data"]["episode_count_month"], 4)

    def test_initialization_needs_confirmation_and_never_returns_token(self):
        """创建、重复创建与普通登录分开，完整确认字段不可缺少。"""
        data = {"username": "native-new", "password": "fixture-new123", "api_key": "a" * 64}
        path = "/new/api/v1/login/initialization"
        self.assertEqual(self.request(path, json.dumps(data).encode())[0], 400)
        data["confirm_password"] = data["password"]
        status, response = self.request(path, json.dumps(data).encode())
        self.assertEqual(status, 200)
        self.assertNotIn("access_token", response)
        self.assertEqual(self.request(path, json.dumps(data).encode())[0], 409)
        _, stats = self.request("/__native/stats")
        self.assertNotIn("POST api/v1/login/access-token", stats["new"])

    def test_otp_requires_explicit_second_request_and_preserves_leading_zero(self):
        """挑战、错误验证码、正确验证码都有真实 HTTP 状态，不绕过登录。"""
        self.request("/__native/config", b'{"profile":"a","mode":"otp"}')
        body = b"username=native-a&password=fixture-a123&otp_password="
        path = "/a/api/v1/login/access-token"
        form = "application/x-www-form-urlencoded"
        status, challenge = self.request(path, body, form)
        self.assertEqual(status, 401)
        self.assertEqual(challenge["data"]["mfa_methods"], ["otp"])
        self.assertEqual(self.request(path, body + b"123456", form)[0], 401)
        status, success = self.request(path, body + b"012345", form)
        self.assertEqual(status, 200)
        self.assertEqual(success["user_name"], "native-a")

    def test_detail_status_person_and_subscribe_lifecycle(self):
        """媒体状态、演职员/人物详情和合成订阅增删均严格遵守认证与权限边界。"""
        base = "/a/api/v1/"
        tok = "synthetic-native-a"
        status, credits = self.request(base + "tmdb/credits/113/%E7%94%B5%E5%BD%B1", token=tok)
        self.assertEqual((status, credits["data"][0]["id"]), (200, 501))
        status, person = self.request(base + "tmdb/person/501", token=tok)
        self.assertEqual((status, person["data"]["name"]), (200, "合成主演"))
        status, works = self.request(base + "tmdb/person/credits/501?page=1", token=tok)
        self.assertEqual((status, len(works["data"])), (200, 2))

        query = json.dumps([{"media_source": "themoviedb", "media_id": "113", "mtype": "电影"}]).encode()
        status, before = self.request(base + "media/status", query, token=tok)
        self.assertEqual((status, before["data"][0]["server"], before["data"][0]["subscribed"]), (200, "Emby", False))

        sub_body = json.dumps({
            "name": "合成电影 113", "type": "电影", "year": "2025",
            "media_source": "themoviedb", "media_id": "113", "season": None,
        }).encode()
        status, _ = self.request(base + "subscribe/", sub_body, token=tok)
        self.assertEqual(status, 200)
        status, after = self.request(base + "media/status", query, token=tok)
        self.assertTrue(after["data"][0]["subscribed"])

    def test_mediaserver_stream_info_and_range_stream(self):
        """媒体流清单签发同源 Cookie，流接口严格校权并支持 206 Range 切片。"""
        req = Request(
            self.base + "/a/api/v1/mediaserver/stream-info?itemid=ep-101&server=Emby",
            headers={"Authorization": "Bearer synthetic-native-a"},
        )
        with urlopen(req, timeout=5) as resp:
            self.assertEqual(resp.status, 200)
            cookie_header = resp.headers.get("Set-Cookie", "")
            self.assertIn("mp_media_token=synthetic-stream-a", cookie_header)
            manifest = json.load(resp)["data"]
            self.assertEqual(manifest["item_id"], "ep-101")
            stream_url = manifest["content_url"]

        # 无凭据拒绝
        with self.assertRaises(HTTPError) as ctx:
            urlopen(Request(stream_url), timeout=5)
        self.assertEqual(ctx.exception.code, 401)

        # Cookie + Range 206 返回有效 MP4 头部
        range_req = Request(
            stream_url,
            headers={
                "Cookie": "mp_media_token=synthetic-stream-a",
                "Range": "bytes=0-1023",
            },
        )
        with urlopen(range_req, timeout=5) as stream_resp:
            self.assertEqual(stream_resp.status, 206)
            self.assertEqual(stream_resp.headers.get("Accept-Ranges"), "bytes")
            chunk = stream_resp.read()
            self.assertEqual(len(chunk), 1024)
            self.assertIn(b"ftyp", chunk[:32])

    def test_vue_plugin_local_runtime_endpoints_require_auth_and_serve_esm(self):
        """验证合成联邦插件 remotes、ESM remoteEntry.js 与桥接状态接口在无前端 HTML 情况下独立工作。"""
        forbidden_status, _ = self.request("/a/api/v1/plugin/remotes?token=wrong")
        self.assertEqual(forbidden_status, 403)

        ok_status, items = self.request("/a/api/v1/plugin/remotes?token=moviepilot")
        self.assertEqual(ok_status, 200)
        self.assertEqual(items[0]["id"], "VueCompatDemo")
        self.assertEqual(items[0]["version"], "1.2.0")
        self.assertEqual(items[0]["bundle_hash"], "a1b2c3d4e5f6")

        unauth_status, _ = self.request("/a/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js")
        self.assertEqual(unauth_status, 401)

        js_req = Request(
            self.base + "/a/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js",
            headers={"Authorization": "Bearer synthetic-native-a"},
        )
        with urlopen(js_req, timeout=5) as js_resp:
            self.assertEqual(js_resp.status, 200)
            self.assertIn("javascript", js_resp.headers.get("Content-Type", ""))
            js_body = js_resp.read().decode("utf-8")
            self.assertIn("export async function get(", js_body)
            self.assertIn("emit('close')", js_body)
            self.assertIn("关闭插件", js_body)

        status_code, payload = self.request(
            "/a/api/v1/plugin/VueCompatDemo/status",
            token="synthetic-native-a",
        )
        self.assertEqual(status_code, 200)
        self.assertTrue(payload["success"])
        self.assertEqual(payload["data"]["items"], 42)
