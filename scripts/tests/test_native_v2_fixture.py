"""用真实回环 HTTP 验证夹具没有前端兜底、跨实例令牌或自动初始化捷径。"""

import importlib.util
import json
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

SPEC = importlib.util.spec_from_file_location(
    "native_fixture", Path(__file__).resolve().parents[1] / "native-v2-fixture.py"
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
