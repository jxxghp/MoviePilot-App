"""一次性真实后端验收通道只用合成输入检查，不访问真实实例。"""

import importlib.util
import json
from pathlib import Path
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

SPEC = importlib.util.spec_from_file_location(
    "native_live", Path(__file__).resolve().parents[1] / "native-v2-live.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LiveInputBoundaryTests(unittest.TestCase):
    """验证回环限制、随机能力、单次消费和错误请求不取走输入。"""

    def setUp(self):
        """以动态端口启动内存通道，凭据为无实际用途的合成字符串。"""
        self.payload = {
            "username": "synthetic-reader", "password": "synthetic-only",
            "nextPageIdentities": ["themoviedb|123|电影"],
        }
        self.server = MODULE.SessionInputServer(self.payload)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        """关闭监听并清空一次性输入引用，避免测试之间留有能力。"""
        self.server.payload = None
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path="/session-input", nonce=None):
        """返回 HTTP 状态和 JSON，不记录会话输入正文。"""
        request = Request(
            self.base + path,
            headers={"X-MoviePilot-Live-Test": nonce or self.server.nonce},
        )
        try:
            response = urlopen(request, timeout=5)
        except HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def test_consumes_the_input_only_once(self):
        """有效请求拿到完整合成输入，重放只收到空对象。"""
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        self.assertGreaterEqual(len(self.server.nonce), 32)
        self.assertEqual(self.request(), (200, self.payload))
        self.assertIsNone(self.server.payload)
        self.assertEqual(self.request(), (403, {}))

    def test_wrong_capability_and_unknown_path_preserve_input(self):
        """错误随机能力和非白名单路径都不能提前消费或读取凭据。"""
        self.assertEqual(self.request(nonce="not-authorized"), (403, {}))
        self.assertEqual(self.request(path="/"), (403, {}))
        self.assertEqual(self.request(), (200, self.payload))
