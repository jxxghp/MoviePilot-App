"""使用真实前端与合成插件验证保存期间的原生 Sheet 交接，仅监听回环地址。"""

import argparse
import importlib.util
import json
import time
from pathlib import Path
from urllib.parse import urlsplit

spec = importlib.util.spec_from_file_location("startup", Path(__file__).with_name("service-startup-fixture.py"))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)

PLUGIN = {
    "id": "SaveFixture", "plugin_name": "保存回归插件", "plugin_version": "1.0",
    "plugin_desc": "仅用于本机保存回归", "installed": True, "has_page": False,
    "state": True, "runtime_status": "active", "plugin_icon": "none.png",
}
PANEL_PLUGIN = dict(PLUGIN, id="PanelFixture", plugin_name="面板回归插件", has_page=True)

SCRIPT = """<script>
location.hash = '#/plugins';
const handler = window.webkit?.messageHandlers?.moviepilotChrome;
if (handler) {
  const original = handler.postMessage.bind(handler);
  handler.postMessage = message => {
    if (['navigation.state', 'command.result', 'chrome.failed'].includes(message.type)) {
      const payload = message.payload;
      fetch('/__plugin/event', {method:'POST', body:JSON.stringify({
        type:message.type, result:message.type === 'command.result' ? payload : undefined,
        sheet:payload.presentation?.sheet, overlayOpen:payload.presentation?.overlayOpen,
        content:payload.chrome?.content, route:payload.route?.fullPath
      })});
    }
    original(message);
  };
}
window.addEventListener('moviepilot:native-message', event => {
  const message = event.detail;
  if (message?.type.startsWith('presentation.')) fetch('/__plugin/event', {
    method:'POST', body:JSON.stringify({type:message.type, payload:message.payload, requestId:message.requestId})
  });
});
</script>"""


class PluginSaveHandler(startup.StartupHandler):
    """保留真实配置表单、保存请求与弹窗生命周期，不连接外部插件或实例。"""

    def do_GET(self):
        """提供固定插件和表单，并记录不含认证信息的 Sheet 协议事件。"""
        path = urlsplit(self.path).path
        data = None
        if path == "/__plugin/state":
            with self.server.guard:
                self.reply(200, self.server.state)
            return
        if path in ("/", "/index.html"):
            body = (self.server.frontend / "index.html").read_bytes().replace(b"<head>", b"<head>" + SCRIPT.encode())
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/v1/plugin/":
            data = [PLUGIN, PANEL_PLUGIN]
        elif path == "/api/v1/plugin/form/SaveFixture":
            data = {"render_mode": "vuetify", "conf": [
                {"component": "VTextField", "props": {"model": "value", "label": "测试配置"}},
            ], "model": {"value": "保存前"}}
        elif path == "/api/v1/plugin/runtime":
            data = {"ready": True, "generation": 1, "plugins": {}}
        elif path in ("/api/v1/plugin/statistic", "/api/v1/plugin/rating"):
            data = {}
        elif path.startswith("/api/v1/user/config/"):
            with self.server.guard:
                data = {"value": self.server.user_configs.get(path)}
        elif path.startswith("/api/v1/system/setting/"):
            data = {"value": None}
        if data is not None:
            self.reply(200, {"success": True, "data": data})
        else:
            super().do_GET()

    def do_POST(self):
        """主题偏好仅保存在本机夹具内，控制端只接收合成测试场景与有界事件。"""
        path = urlsplit(self.path).path
        if path.startswith("/api/v1/user/config/"):
            length = int(self.headers.get("Content-Length", "0"))
            if length > 8192:
                self.reply(413, {})
                return
            data = json.loads(self.rfile.read(length))
            with self.server.guard:
                self.server.user_configs[path] = data
            self.reply(200, {"success": True, "data": None})
        elif path.startswith("/__plugin/"):
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            with self.server.guard:
                if path == "/__plugin/event":
                    self.server.state["events"].append(data)
                    self.server.state["events"] = self.server.state["events"][-200:]
                elif path == "/__plugin/config":
                    if data.get("reset"):
                        self.server.state["saves"].clear()
                        self.server.state["events"].clear()
                        self.server.state["completed"] = 0
                    self.server.state["delay"] = min(2, max(0, float(data.get("delay", 0))))
                    self.server.state["failure"] = data.get("failure") is True
            self.reply(200, {})
        else:
            super().do_POST()

    def do_PUT(self):
        """每次真实按钮提交只记录一次，并可延迟或拒绝合成保存。"""
        if urlsplit(self.path).path != "/api/v1/plugin/SaveFixture":
            self.reply(404, {})
            return
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
        with self.server.guard:
            self.server.state["saves"].append(data)
            delay, failure = self.server.state["delay"], self.server.state["failure"]
        time.sleep(delay)
        self.reply(200, {"success": not failure, "message": "合成保存失败" if failure else "", "data": None})
        with self.server.guard:
            self.server.state["completed"] += 1


class PluginSaveServer(startup.StartupServer):
    """以独立端口隔离插件保存记录，复用现有原生登录合成协议。"""

    def __init__(self, frontend):
        """静态资源必须由调用者指定，不复用任何真实服务地址或会话。"""
        super().__init__(5312, frontend)
        self.mode = "ready"
        self.user_configs = {}
        self.state = {"events": [], "saves": [], "completed": 0, "delay": 0, "failure": False}

    def finish_request(self, request, client_address):
        """保留标准 HTTP 生命周期，只替换插件所需的合成接口。"""
        PluginSaveHandler(request, client_address, self)


def main():
    """检查显式前端产物目录后启动本机服务。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frontend", type=Path, required=True)
    args = parser.parse_args()
    frontend = args.frontend.resolve()
    if not (frontend / "index.html").is_file():
        parser.error("--frontend 必须包含已构建的 index.html")
    with PluginSaveServer(frontend) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
