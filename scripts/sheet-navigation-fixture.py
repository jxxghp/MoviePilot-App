"""使用真实前端验证媒体搜索的 Sheet 归还，仅监听回环地址并提供合成数据。"""

import argparse
import json
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


SCRIPT = """<script>
location.hash = '#/recommend';
let routeSequence = 0;
let delayPaint = false;
let delayedFrames = 0;
const nextFrame = window.requestAnimationFrame.bind(window);
// 保留真实 requestAnimationFrame，扩大绘制确认与所属入口切换交错的时间窗口。
window.requestAnimationFrame = callback => {
  if (delayedFrames > 0) {
    delayedFrames--;
    return setTimeout(() => nextFrame(callback), 200);
  }
  return nextFrame(callback);
};
window.addEventListener('moviepilot:native-message', event => {
  if (event.detail?.type !== 'presentation.detach' || !delayPaint) return;
  delayedFrames = 2;
  fetch('/__sheet/delayed', {method: 'POST'});
}, true);
setInterval(async () => {
  const state = await (await fetch('/__sheet/state')).json();
  if (state.route !== routeSequence) {
    routeSequence = state.route;
    delayPaint = state.delay;
    location.hash = '#' + state.source;
    setTimeout(() => location.hash = '#/browse/recommend/test?title=搜索回归', 500);
  }
  const rectangle = element => element ? element.getBoundingClientRect().toJSON() : null;
  fetch('/__sheet/page', {method: 'POST', body: JSON.stringify({
    hash: location.hash, sheet: document.documentElement.hasAttribute('data-native-sheet'),
    card: rectangle(document.querySelector('.media-card')),
    search: rectangle(document.querySelector('.media-card .v-card-text button'))
  })});
}, 150);
</script>
"""


class SheetServer(ThreadingHTTPServer):
    """持有隔离的合成搜索记录，不连接或保存任何真实实例数据。"""

    def __init__(self, frontend):
        """静态资源由调用者明确指定，控制端点仅在本机端口开放。"""
        self.frontend = frontend
        self.guard = threading.Lock()
        self.state = {
            "route": 0, "source": "/recommend", "delay": False,
            "searches": [], "delayed": 0, "page": {},
        }
        super().__init__(("127.0.0.1", 5256), SheetHandler)


class SheetHandler(SimpleHTTPRequestHandler):
    """提供真实 MediaCard、站点弹窗和资源页所需的最小合成接口。"""

    def __init__(self, *args, **kwargs):
        """将静态文件服务限制到指定的前端产物目录。"""
        super().__init__(*args, directory=str(args[2].frontend), **kwargs)

    def log_message(self, *_args):
        """不记录请求头或认证正文。"""

    def reply(self, data, status=200, kind="application/json; charset=utf-8"):
        """发送不缓存的 JSON、静态入口或流式搜索响应。"""
        body = data if isinstance(data, bytes) else json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def api(self, data):
        """保留前端实际消费的标准响应信封。"""
        self.reply({"success": True, "message": "", "data": data})

    def do_GET(self):
        """加载实际前端并为登录、卡片和站点选择提供固定输入。"""
        parsed = urlsplit(self.path)
        key = parsed.path.removeprefix("/api/v1/")
        if parsed.path == "/__sheet/state":
            with self.server.guard:
                self.reply(self.server.state)
        elif parsed.path in ("/", "/index.html"):
            self.reply(
                (self.server.frontend / "index.html").read_bytes().replace(
                    b"<head>", b"<head>" + SCRIPT.encode()),
                kind="text/html; charset=utf-8",
            )
        elif key == "auth/providers":
            self.reply({}, 404)
        elif key == "login/initialization":
            self.api({"initialized": True})
        elif key == "user/current":
            self.api({"id": 1, "name": "native-demo", "is_superuser": True,
                      "level": 1, "permissions": {}})
        elif key == "system/global":
            self.api({"APP_VERSION": "v3.2.2"})
        elif key == "media/source":
            self.api([{"media_source": "themoviedb", "name": "TheMovieDB",
                       "media_types": ["电影", "电视剧"], "enabled": True}])
        elif key == "system/module-catalog":
            self.api({"modules": []})
        elif key == "recommend/test":
            self.api([{"media_source": "themoviedb", "media_id": "1001", "tmdb_id": 1001,
                       "title": "合成电影", "year": "2026", "type": "电影", "overview": "原生搜索回归"}])
        elif key.startswith("site/media/"):
            self.api([{"id": i, "name": f"合成站点 {i}", "is_active": True} for i in (1, 2)])
        elif key.endswith("IndexerSites"):
            self.api({"value": [1, 2]})
        elif key.endswith("/stream"):
            with self.server.guard:
                self.server.state["searches"].append(parse_qs(parsed.query))
            self.reply(b'data: {"type":"done","items":[],"total_items":0}\n\n',
                       kind="text/event-stream")
        elif key.startswith(("user/config/", "system/setting/")):
            self.api({"value": None})
        elif parsed.path.startswith("/api/"):
            self.api([])
        else:
            super().do_GET()

    def do_POST(self):
        """测试控制仅切换入口和读取 DOM；搜索必须通过真实界面发起。"""
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        key = urlsplit(self.path).path
        if key == "/__sheet/route":
            value = json.loads(body)
            if value.get("source") not in ("/recommend", "/discover", "/apps"):
                self.reply({}, 400)
                return
            with self.server.guard:
                self.server.state["source"] = value["source"]
                self.server.state["delay"] = value.get("delay") is True
                self.server.state["route"] += 1
            self.reply({})
        elif key == "/__sheet/page":
            with self.server.guard:
                self.server.state["page"] = json.loads(body)
            self.reply({})
        elif key == "/__sheet/delayed":
            with self.server.guard:
                self.server.state["delayed"] += 1
            self.reply({})
        elif key.endswith("login/access-token"):
            self.api({"access_token": "sheet-fixture-only", "super_user": True,
                      "user_id": 1, "user_name": "native-demo", "level": 1, "permissions": {}})
        else:
            self.api([])


def main():
    """验证前端产物存在后启动固定端口的本机验收服务。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frontend", type=Path, required=True)
    args = parser.parse_args()
    frontend = args.frontend.resolve()
    if not (frontend / "index.html").is_file():
        parser.error("--frontend 必须包含已构建的 index.html")
    with SheetServer(frontend) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
