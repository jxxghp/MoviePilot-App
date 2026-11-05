"""仅在回环地址重现 AppPush 未启用与恢复，复用现有原生登录和真实前端。"""

import argparse
import importlib.util
import json
from pathlib import Path
from urllib.parse import urlsplit

spec = importlib.util.spec_from_file_location("startup", Path(__file__).with_name("service-startup-fixture.py"))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


class NotificationHandler(startup.StartupHandler):
    """合成设备管理只记录动作，不保存令牌、认证头或实例请求正文。"""

    def do_GET(self):
        """测试只读取模式和检查次数，其余请求由现有隔离登录服务处理。"""
        if urlsplit(self.path).path == "/__notification/state":
            with self.server.guard:
                self.reply(200, {"mode": self.server.notification_mode, "actions": self.server.actions.copy()})
            return
        super().do_GET()

    def do_POST(self):
        """服务端配置可在 App 不退出登录时恢复，验证开启操作确实重新获取身份。"""
        path = urlsplit(self.path).path
        if path not in ("/__notification/state", "/api/v1/notification/app"):
            super().do_POST()
            return
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 < length <= 8192:
            self.reply(413, {})
            return
        data = json.loads(self.rfile.read(length))
        if path == "/__notification/state":
            mode = data.get("mode")
            if mode not in ("disabled", "ready", "missing-owner"):
                self.reply(400, {})
                return
            with self.server.guard:
                self.server.notification_mode = mode
            self.reply(200, {})
            return
        if self.headers.get("Authorization") != "Bearer startup-fixture-only":
            self.reply(401, {})
            return
        action = data.get("action")
        with self.server.guard:
            self.server.actions.append(action)
            mode = self.server.notification_mode
        if action != "status":
            self.reply(400, {"success": False, "message": "本夹具不向外部推送服务注册或发送通知"})
        elif mode == "disabled":
            self.reply(200, {"success": False, "message": "该通知渠道未启用或不支持此管理动作"})
        else:
            result = {"devices": [], "relay_url": "https://movie-pilot.org/push/app/"}
            if mode == "ready":
                result["owner"] = "a" * 32
            self.reply(200, {"success": True, "data": result})


class NotificationServer(startup.StartupServer):
    """专用端口与独立状态避免影响正在使用的实例和其他模拟器服务。"""

    def __init__(self, port, frontend):
        """登录保持可用，仅设备管理状态由测试显式切换。"""
        super().__init__(port, frontend)
        self.mode = "ready"
        self.notification_mode = "disabled"
        self.actions = []

    def finish_request(self, request, client_address):
        """复用标准 HTTP 连接生命周期并替换设备管理响应。"""
        NotificationHandler(request, client_address, self)


def main():
    """前端产物必须由调用者给出，夹具不自动构建或连接真实服务。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frontend", type=Path, required=True)
    parser.add_argument("--port", type=int, default=5306)
    args = parser.parse_args()
    if not (args.frontend / "index.html").is_file():
        parser.error("前端目录缺少 index.html")
    with NotificationServer(args.port, args.frontend.resolve()) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
