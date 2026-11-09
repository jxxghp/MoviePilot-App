"""为真实站点浏览与确认下载嵌套弹窗提供合成数据，仅监听回环地址。"""

import argparse
import importlib.util
import json
from pathlib import Path
from urllib.parse import urlsplit

spec = importlib.util.spec_from_file_location("plugin_save", Path(__file__).with_name("plugin-save-fixture.py"))
plugin_save = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin_save)
plugin_save.SCRIPT = plugin_save.SCRIPT.replace("#/plugins", "#/site")

SITE = {
    "id": 1, "name": "演示站点", "domain": "nested.invalid", "url": "https://nested.invalid/",
    "is_active": True, "downloader": "合成下载器",
}
RESOURCE = {
    "site": 1, "site_name": "演示站点", "site_downloader": "合成下载器",
    "title": "MoviePilot Demo S01E01 2026 1080p WEB-DL", "description": "嵌套弹窗回归",
    "page_url": "https://nested.invalid/details/1", "enclosure": "magnet:?xt=urn:btih:fixture",
    "size": 1073741824, "seeders": 10, "peers": 2, "grabs": 3,
    "uploadvolumefactor": 1, "downloadvolumefactor": 1, "labels": [],
    "pubdate": "2026-11-09 12:00:00", "hit_and_run": False,
}


class NestedSheetHandler(plugin_save.PluginSaveHandler):
    """只替换站点和资源数据，原 Vue 父子弹窗、输入与关闭动作保持真实执行。"""

    def do_GET(self):
        """返回固定站点与资源；统计父列表加载次数，检测动画切换是否重建业务内容。"""
        path = urlsplit(self.path).path
        data = None
        if path == "/__nested/state":
            with self.server.guard:
                self.reply(200, {"resource_requests": self.server.resource_requests})
            return
        if path == "/api/v1/site/":
            data = [SITE]
        elif path in ("/api/v1/site/statistic", "/api/v1/site/userdata/latest"):
            data = []
        elif path == "/api/v1/site/category/1":
            data = []
        elif path == "/api/v1/site/resource/1":
            with self.server.guard:
                self.server.resource_requests += 1
            data = [RESOURCE]
        elif path == "/api/v1/download/clients":
            data = [{"name": "合成下载器", "type": "qbittorrent"}]
        if data is None:
            super().do_GET()
        else:
            self.reply(200, {"success": True, "data": data})

    def do_POST(self):
        """场景控制只重置计数；拒绝实际下载，测试只打开和关闭确认表单。"""
        if urlsplit(self.path).path == "/__fixture/scenario":
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            with self.server.guard:
                self.server.resource_requests = 0
            self.reply(200 if data.get("scenario") in ("nested", "default") else 400, {})
        else:
            super().do_POST()


class NestedSheetServer(plugin_save.startup.StartupServer):
    """复用合成登录与主题协议，在独立端口隔离嵌套弹窗验收。"""

    def __init__(self, frontend):
        """仅持有合成数据与有界事件，不连接真实站点或下载器。"""
        super().__init__(5322, frontend)
        self.mode = "ready"
        self.user_configs = {}
        self.resource_requests = 0
        self.state = {"events": []}

    def finish_request(self, request, client_address):
        """在标准 HTTP 生命周期内使用最小站点数据替身。"""
        NestedSheetHandler(request, client_address, self)


def main():
    """复用调用者指定的兼容前端产物，不自动构建或修改前端源码。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frontend", type=Path, required=True)
    args = parser.parse_args()
    frontend = args.frontend.resolve()
    if not (frontend / "index.html").is_file():
        parser.error("--frontend 必须包含已构建的 index.html")
    with NestedSheetServer(frontend) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
