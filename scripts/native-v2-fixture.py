#!/usr/bin/env python3
"""仅提供回环 API 的原生入口夹具；不提供前端、脚本或真实账号数据。"""

import argparse
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import time
from urllib.parse import parse_qs, urlsplit


class NativeFixture(ThreadingHTTPServer):
    """四个部署子路径模拟隔离实例，控制端点只保存合成状态与请求计数。"""

    def __init__(self, port):
        """绑定 IPv4 回环；允许测试使用系统分配端口，不暴露局域网服务。"""
        self.lock = threading.Lock()
        self.profiles = {
            name: {"mode": "new" if name == "new" else "ready", "counts": Counter()}
            for name in ("a", "b", "new", "slow")
        }
        self.unexpected = Counter()
        super().__init__(("127.0.0.1", port), NativeHandler)


class NativeHandler(BaseHTTPRequestHandler):
    """固定 API 契约和受控故障，不把 URL 查询、请求正文或凭据写入日志。"""

    def log_message(self, *_):
        """关闭默认日志，避免以后加入认证字段时意外记录内容。"""

    def do_GET(self):
        """仅处理状态、身份和测试计数读取。"""
        self.dispatch()

    def do_POST(self):
        """仅处理初始化、登录与合成状态控制，不接受网页代理请求。"""
        self.dispatch()

    def reply(self, status, value, headers=None):
        """响应始终是有长度的无缓存 JSON，取消连接不产生包含请求的错误日志。"""
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def dispatch(self):
        """按方法和完整子路径白名单分发，未知前端请求计数后返回 404。"""
        path = urlsplit(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 <= length <= 65536:
            self.reply(413, {"success": False})
            return
        body = self.rfile.read(length)
        if path == "/__native/stats" and self.command == "GET":
            with self.server.lock:
                value = {
                    name: dict(profile["counts"])
                    for name, profile in self.server.profiles.items()
                }
                value["unexpected"] = dict(self.server.unexpected)
            self.reply(200, value)
            return
        if path == "/__native/config" and self.command == "POST":
            try:
                config = json.loads(body)
                name, mode = config["profile"], config["mode"]
                if name not in self.server.profiles or mode not in {
                    "ready", "new", "otp", "expired", "unavailable", "slow"
                }:
                    raise ValueError()
            except (KeyError, ValueError, TypeError):
                self.reply(400, {"success": False})
                return
            with self.server.lock:
                profile = self.server.profiles[name]
                profile["mode"] = mode
                if config.get("reset"):
                    profile["counts"].clear()
            self.reply(200, {"success": True})
            return
        parts = path.strip("/").split("/")
        name = parts[0] if parts else ""
        endpoint = "/".join(parts[1:])
        allowed = {
            ("GET", "api/v1/login/initialization"),
            ("POST", "api/v1/login/initialization"),
            ("POST", "api/v1/login/access-token"),
            ("GET", "api/v1/user/current"),
        }
        if name not in self.server.profiles or (self.command, endpoint) not in allowed:
            with self.server.lock:
                self.server.unexpected[f"{self.command} {path}"] += 1
            self.reply(404, {"success": False})
            return
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"{self.command} {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "slow":
            time.sleep(3)
        if mode == "unavailable":
            self.reply(503, {"success": False})
        elif endpoint.endswith("initialization"):
            self.initialization(name, mode, body)
        elif endpoint.endswith("access-token"):
            self.login(name, mode, body)
        else:
            self.current(name, mode)

    def initialization(self, name, mode, body):
        """重现固定管理员名与完整确认字段，创建成功也不返回登录令牌。"""
        if self.command == "GET":
            self.reply(200, {"initialized": mode != "new", "configured_username": f"native-{name}" if mode == "new" else None})
            return
        if mode != "new":
            self.reply(409, {"success": False})
            return
        try:
            value = json.loads(body)
            valid = (
                set(value) == {"username", "password", "confirm_password", "api_key"}
                and value["username"] == f"native-{name}"
                and value["password"] == value["confirm_password"] == f"fixture-{name}123"
                and 16 <= len(value["api_key"]) <= 256
                and "application/json" in self.headers.get("Content-Type", "")
                and self.headers.get("Authorization") is None
            )
        except (ValueError, TypeError):
            valid = False
        if not valid:
            self.reply(400, {"success": False})
            return
        with self.server.lock:
            self.server.profiles[name]["mode"] = "ready"
        self.reply(200, {"success": True, "data": None})

    def login(self, name, mode, body):
        """合成账号的 OTP 挑战与失败不会返回成功身份，不接受 JSON 登录捷径。"""
        fields = parse_qs(body.decode(), keep_blank_values=True)
        valid = (
            fields.get("username") == [f"native-{name}"]
            and fields.get("password") == [f"fixture-{name}123"]
            and "application/x-www-form-urlencoded" in self.headers.get("Content-Type", "")
            and self.headers.get("Authorization") is None
        )
        if not valid or (mode == "otp" and fields.get("otp_password") not in [[""], ["012345"]]):
            self.reply(401, {"success": False})
        elif mode == "otp" and fields.get("otp_password") != ["012345"]:
            self.reply(401, {"success": False, "data": {"mfa_methods": ["otp"]}}, {"X-MFA-Required": "true"})
        else:
            self.reply(200, {
                "access_token": f"synthetic-native-{name}", "token_type": "bearer",
                "user_id": 10 if name == "a" else 20, "user_name": f"native-{name}",
                "super_user": name == "a", "permissions": {"manage": False},
            })

    def current(self, name, mode):
        """严格匹配当前实例令牌；其它实例的令牌即使格式合法也拒绝。"""
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
        else:
            self.reply(200, {"success": True, "data": {
                "id": 10 if name == "a" else 20, "name": f"native-{name}",
                "is_superuser": name == "a", "is_active": True,
                "permissions": {"manage": False},
            }})


def main():
    """显式命令启动回环服务，退出不保存任何认证输入。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=5330)
    args = parser.parse_args()
    server = NativeFixture(args.port)
    print(f"Native API-only fixture: 127.0.0.1:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
