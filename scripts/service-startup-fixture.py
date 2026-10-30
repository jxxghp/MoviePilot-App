"""
为 iOS 启动等待验收提供仅监听回环地址的合成服务，不连接真实后端或保存凭据。
"""

import argparse
import json
import socket
import subprocess
import threading
import uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


class StartupServer(ThreadingHTTPServer):
    """
    持有当前故障场景与请求计数，静态页面来自显式指定的兼容前端目录。
    """

    def __init__(self, port, frontend, appearance_simulator=None, profile=None):
        """
        仅绑定本机地址，保留请求统计供 UI 测试确认没有提交或重放密码。
        """
        self.frontend = frontend
        self.mode = "unavailable"
        self.status = 503
        self.guard = threading.Lock()
        self.counts = {}
        self.appearance_simulator = appearance_simulator
        self.profile = profile
        super().__init__(("127.0.0.1", port), StartupHandler)


class StartupHandler(SimpleHTTPRequestHandler):
    """
    提供初始化、原生认证和前端只读接口的隔离响应，不打印请求头或请求正文。
    """

    def __init__(self, *args, **kwargs):
        """
        将静态资源读取限制在调用者指定的前端目录。
        """
        super().__init__(*args, directory=str(args[2].frontend), **kwargs)

    def log_message(self, _format, *args):
        """
        合成服务不输出访问日志，避免后续测试误将认证字段写入日志。
        """

    def reply(self, status, data):
        """
        返回不缓存的 JSON 响应，测试控制状态不会被 URLSession 或 WebKit 缓存。
        """
        if isinstance(data, dict) and "success" in data:
            data = {"message": "", **data}
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def scenario_path(self):
        """
        各用例使用独立实例前缀隔离 Keychain，接口与静态资源仍来自同一合成服务。
        """
        path = urlsplit(self.path).path
        for prefix in ("/automatic", "/cancel", "/background", "/saved", "/response", "/submit", "/layout"):
            if path.startswith(prefix + "/"):
                self.path = self.path[len(prefix):]
                return path[len(prefix):]
        return path

    def do_GET(self):
        """
        查询真实原生使用的接口；临时不可达、损坏响应和过期认证分别保留其语义。
        """
        path = self.scenario_path()
        with self.server.guard:
            mode, status = self.server.mode, self.server.status
            if path.startswith("/api/"):
                self.server.counts[path] = self.server.counts.get(path, 0) + 1
            counts = dict(self.server.counts)
        if path == "/__service/stats":
            self.reply(200, counts)
        elif path == "/api/v1/login/initialization":
            if mode == "disconnected":
                self.connection.shutdown(socket.SHUT_RDWR)
                self.close_connection = True
            elif mode == "unavailable":
                self.reply(status, {"detail": "合成服务尚未就绪"})
            elif mode == "invalid":
                self.reply(200, {"data": {"initialized": "invalid"}})
            elif mode == "legacy":
                self.reply(404, {})
            else:
                self.reply(200, {"success": True, "data": {"initialized": mode != "uninitialized"}})
        elif path == "/api/v1/auth/providers":
            self.reply(404, {})
        elif path == "/api/v1/user/current":
            if mode == "restore-unavailable":
                self.reply(503, {})
            elif mode == "expired" or (
                self.server.profile
                and self.headers.get("Authorization") != f"Bearer profile-{self.server.profile}-only"
            ):
                self.reply(401, {})
            else:
                self.reply(200, {"success": True, "data": {
                    "id": 1, "name": self.username(), "is_superuser": True, "level": 1,
                    "permissions": {},
                }})
        elif path == "/api/v1/system/global":
            self.reply(200, {"success": True, "data": {"APP_VERSION": "v3.2.1"}})
        elif path.startswith("/api/"):
            self.reply(200, {"success": True, "data": []})
        else:
            if not Path(self.translate_path(path)).is_file():
                self.path = "/index.html"
            super().do_GET()

    def do_POST(self):
        """
        控制端仅切换合成故障；登录只统计提交次数并签发固定测试令牌。
        """
        path = self.scenario_path()
        length = int(self.headers.get("Content-Length", "0"))
        if length > 8192:
            self.reply(413, {})
            return
        body = self.rfile.read(length)
        if path == "/__fixture/appearance" and self.server.appearance_simulator:
            data = json.loads(body)
            appearance = data.get("appearance")
            if appearance not in ("light", "dark"):
                self.reply(400, {})
                return
            result = subprocess.run(
                ["xcrun", "simctl", "ui", self.server.appearance_simulator, "appearance", appearance],
                capture_output=True, timeout=10, check=False,
            )
            self.reply(200 if result.returncode == 0 else 503, {})
        elif path == "/__service/config":
            data = json.loads(body)
            with self.server.guard:
                self.server.mode = data["mode"]
                self.server.status = data.get("status", 503)
                if data.get("reset"):
                    self.server.counts.clear()
            self.reply(200, {})
        elif path == "/api/v1/login/access-token":
            with self.server.guard:
                self.server.counts[path] = self.server.counts.get(path, 0) + 1
                mode = self.server.mode
            if mode == "login-unavailable":
                self.reply(503, {})
            elif self.server.profile and not self.valid_credentials(body):
                self.reply(401, {})
            elif self.server.profile and mode == "otp" and (
                parse_qs(body.decode()).get("otp_password") != ["123456"]
            ):
                response = json.dumps({"data": {"mfa_methods": ["otp"]}}).encode()
                self.send_response(401)
                self.send_header("X-MFA-Required", "true")
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response)))
                self.end_headers()
                self.wfile.write(response)
            else:
                self.reply(200, {"success": True, "data": {
                    "access_token": (
                        f"profile-{self.server.profile}-only" if self.server.profile
                        else "startup-fixture-only"
                    ), "super_user": True,
                    "user_id": 1, "user_name": self.username(), "level": 1, "permissions": {},
                }})
        else:
            self.reply(404, {})

    def username(self):
        """
        多服务回归使用固定合成账号，原启动等待场景保持既有身份。
        """
        return f"server-{self.server.profile}" if self.server.profile else "startup-fixture"

    def valid_credentials(self, body):
        """
        校验每个服务独有的合成密码，让串用另一服务的账号无法通过测试。
        """
        values = parse_qs(body.decode())
        return (
            values.get("username") == [self.username()]
            and values.get("password") == [f"fixture-{self.server.profile}"]
        )


def main():
    """
    由开发者显式启动隔离服务，前端必须为已存在的本地产物，不自动构建或下载。
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frontend", type=Path, required=True)
    parser.add_argument("--port", type=int, default=5244)
    parser.add_argument("--profile", choices=("a", "b"), help="多服务回归专用的合成账号")
    parser.add_argument(
        "--appearance-simulator", type=lambda value: str(uuid.UUID(value)),
        help="仅允许外观回归改变此模拟器的系统明暗，须传入明确的设备 UUID",
    )
    args = parser.parse_args()
    if not (args.frontend / "index.html").is_file():
        parser.error("前端目录缺少 index.html")
    with StartupServer(
        args.port, args.frontend.resolve(), args.appearance_simulator, args.profile
    ) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
