"""仅监听本机的设置与搜索验收夹具，产品页面来自本次构建。"""

import argparse
import importlib.util
import json
from pathlib import Path
from urllib.parse import urlsplit

SCRIPT_ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "pluginfixture", SCRIPT_ROOT / "plugin-save-fixture.py"
)
plugin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin)
EPISODES = [
    {
        "episode_number": 1,
        "season_number": 1,
        "name": "第一集：重逢",
        "still_path": "/still-1.jpg",
        "overview": "几位歌手在新的舞台相聚，准备首轮演出。",
        "air_date": "2026-11-10",
        "runtime": 48,
    },
    {
        "episode_number": 3,
        "season_number": 1,
        "name": "第三集：新的挑战",
        "still_path": "/still-3.jpg",
        "overview": "新的赛制带来新的挑战。",
        "air_date": "2026-11-17",
        "runtime": 52,
    },
]
SCRIPT = """<script>
let qaSeen=0;
setInterval(async()=>{try{
 const next=await (await fetch('/__qa/navigation')).json();
 if(next.sequence!==qaSeen){qaSeen=next.sequence;if(next.path)location.hash='#'+next.path;}
 await fetch('/__qa/dom',{method:'POST',body:JSON.stringify({path:location.hash,active:document.documentElement.dataset.nativeChrome,sheets:Array.from(document.querySelectorAll('.v-overlay--active.v-dialog')).map(el=>({title:el.getAttribute('aria-label'),medium:el.dataset.nativeSheetSize,close:!!el.querySelector('[data-native-dialog-close]')}))})});
}catch{}},350);
</script>"""


class Handler(plugin.PluginSaveHandler):
    """复用合成认证和插件设置，补充有内容的搜索结果。"""

    def do_GET(self):
        """只返回有限的合成集信息、图片与资源。"""
        path = urlsplit(self.path).path
        if path.startswith(
            ("/api/v1/message/", "/api/v1/system/message", "/api/v1/system/progress/")
        ):
            self.send_response(204)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path == "/api/v1/auth/providers":
            self.reply(200, {"success": True, "data": []})
            return
        if path == "/__qa/navigation":
            self.reply(200, self.server.navigation)
            return
        if path == "/__qa/dom":
            self.reply(200, self.server.dom)
            return
        if path == "/api/v1/system/global":
            self.reply(
                200,
                {
                    "success": True,
                    "data": {
                        "APP_VERSION": "fixture",
                        "TMDB_IMAGE_DOMAIN": "qa-image.test",
                        "GLOBAL_IMAGE_CACHE": False,
                        "WALLPAPER": "",
                    },
                },
            )
            return
        if path == "/api/v1/media/source":
            self.reply(
                200,
                {
                    "success": True,
                    "data": [
                        {
                            "name": "TMDB",
                            "media_source": "themoviedb",
                            "media_types": ["电影", "电视剧"],
                        }
                    ],
                },
            )
            return
        if path == "/api/v1/mediaserver/search":
            self.reply(
                200,
                {
                    "success": True,
                    "data": [
                        {
                            "server": "合成媒体库",
                            "item_id": "series-1",
                            "title": "我是歌手",
                            "subtitle": "音乐 · 2 集",
                            "type": "电视剧",
                            "image": "http://127.0.0.1:5319/__qa/poster.jpg",
                            "year": 2026,
                        }
                    ],
                },
            )
            return
        if path == "/api/v1/mediaserver/episodes":
            self.reply(
                200, {"success": True, "data": {1: {1: "episode-1", 3: "episode-3"}}}
            )
            return
        if path.startswith(("/api/v1/mediaserver/episode-metadata", "/api/v1/tmdb/")):
            self.reply(200, {"success": True, "data": EPISODES})
            return
        if path == "/api/v1/search/last/context":
            data = []
            for index, (site, resolution, season) in enumerate(
                [
                    ("合成站点 A", "1080p", "S01"),
                    ("合成站点 A", "2160p", "S02"),
                    ("合成站点 B", "1080p", "S01"),
                    ("合成站点 B", "2160p", "S02"),
                ]
            ):
                data.append(
                    {
                        "media_info": {},
                        "meta_info": {
                            "name": "音乐节目",
                            "resource_pix": resolution,
                            "season_episode": season,
                            "edition": "WEB-DL",
                            "video_encode": "H.265",
                        },
                        "torrent_info": {
                            "title": f"我是歌手 {season} {resolution} {index}",
                            "site_name": site,
                            "size": 1024**3,
                            "seeders": 7,
                            "volume_factor": "FREE",
                            "page_url": f"https://fixture.test/{index}",
                            "enclosure": f"https://fixture.test/{index}.torrent",
                        },
                    }
                )
            self.reply(200, {"success": True, "data": {"results": data}})
            return
        if path == "/__qa/poster.jpg":
            body = self.server.poster.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path in ("/", "/index.html"):
            body = (
                (self.server.frontend / "index.html")
                .read_bytes()
                .replace(b"<head>", b"<head>" + SCRIPT.encode())
            )
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def do_POST(self):
        """验收控制仅切换回环页面，不连接真实实例。"""
        path = urlsplit(self.path).path
        if path in ("/__qa/navigation", "/__qa/dom"):
            data = json.loads(
                self.rfile.read(int(self.headers.get("Content-Length", "0")))
            )
            if path.endswith("navigation"):
                self.server.navigation = {
                    "path": data["path"],
                    "sequence": self.server.navigation["sequence"] + 1,
                }
            else:
                self.server.dom = data
            self.reply(200, {})
            return
        if path == "/api/v1/login/access-token":
            self.rfile.read(int(self.headers.get("Content-Length", "0")))
            self.reply(
                200,
                {
                    "access_token": "startup-fixture-only",
                    "token_type": "bearer",
                    "super_user": True,
                    "user_id": 1,
                    "user_name": "startup-fixture",
                    "level": 1,
                    "permissions": {},
                },
            )
            return
        super().do_POST()


class Server(plugin.PluginSaveServer):
    """独立端口与临时状态避免干扰其它验收。"""

    def __init__(self, frontend, poster):
        """直接复用已有启动服务器的数据模型。"""
        plugin.startup.StartupServer.__init__(self, 5319, frontend)
        self.poster = poster
        self.mode = "ready"
        self.user_configs = {}
        self.state = {
            "events": [],
            "saves": [],
            "completed": 0,
            "delay": 0,
            "failure": False,
        }
        self.navigation = {"path": "", "sequence": 0}
        self.dom = {}

    def finish_request(self, request, client_address):
        """保持标准请求生命周期。"""
        Handler(request, client_address, self)


def main():
    """前端和图片均由调用者显式指定，夹具不读真实服务配置。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frontend", type=Path, required=True)
    parser.add_argument("--poster", type=Path, required=True)
    args = parser.parse_args()
    frontend = args.frontend.resolve()
    poster = args.poster.resolve()
    if not (frontend / "index.html").is_file() or not poster.is_file():
        parser.error("需要前端构建目录和测试 JPEG 图片")
    Server(frontend, poster).serve_forever()


if __name__ == "__main__":
    main()
