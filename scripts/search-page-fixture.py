"""提供仅限回环的搜索页验收数据，复用启动夹具且不连接真实实例。"""

import argparse
import importlib.util
from pathlib import Path
from urllib.parse import urlsplit

spec = importlib.util.spec_from_file_location("startup", Path(__file__).with_name("service-startup-fixture.py"))
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


class SearchHandler(startup.StartupHandler):
    """按类型返回不同来源与站点，供真实原生页面验证桥接选择与搜索参数。"""

    def do_GET(self):
        """其余初始化与登录请求仍使用既有合成服务，不复制认证实现。"""
        path = urlsplit(self.path).path
        data = None
        if path.startswith("/api/v1/__fixture/wallpaper/"):
            index = int(path.rsplit("/", 1)[1])
            image = self.server.wallpapers[index].read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(image)))
            self.end_headers()
            self.wfile.write(image)
            return
        if path == "/api/v1/login/wallpapers":
            data = [f"http://localhost:5297/api/v1/__fixture/wallpaper/{index}" for index in range(len(self.server.wallpapers))]
        elif path == "/api/v1/system/global":
            data = {"APP_VERSION": "v3.2.4", "WALLPAPER": "bing", "WALLPAPER_ROTATION_INTERVAL": 5}
        elif path == "/api/v1/user/config/ThemeCustomizerSettings":
            data = {"value": {"theme": "dark", "primaryColor": "#FFB400", "glassEnabled": True}}
        elif path == "/api/v1/github/auth/status":
            data = {"configured": not self.server.background_notices, "valid": True}
        elif path == "/api/v1/media/source":
            data = [
                {"name": "TMDB", "media_source": "themoviedb", "media_types": ["电影", "电视剧"]},
                {"name": "豆瓣", "media_source": "douban", "media_types": ["电影", "电视剧"]},
                {"name": "MusicBrainz", "media_source": "musicbrainz", "media_types": ["音乐"]},
            ]
        elif path == "/api/v1/site/":
            data = [{"id": 11, "name": "综合站", "is_active": True}, {"id": 22, "name": "音乐站", "is_active": True}]
        elif path == "/api/v1/site/media/music":
            data = [{"id": 22, "name": "音乐站", "is_active": True}]
        elif path == "/api/v1/system/setting/public/IndexerSites":
            data = {"value": [11, 22]}
        if data is not None:
            self.reply(200, {"success": True, "data": data})
        else:
            super().do_GET()


    def do_POST(self):
        """默认确认主题保存，可显式制造错误通知来验证原生背景隔离。"""
        if urlsplit(self.path).path.startswith("/api/v1/user/config/"):
            length = int(self.headers.get("Content-Length", "0"))
            self.rfile.read(length)
            if self.server.background_notices:
                self.reply(404, {})
            else:
                self.reply(200, {"success": True, "data": None})
            return
        super().do_POST()


class SearchServer(startup.StartupServer):
    """在独立端口运行搜索验收，不干扰已有模拟器服务。"""

    def finish_request(self, request, client_address):
        """保留标准 HTTP 生命周期，仅替换合成请求处理器。"""
        SearchHandler(request, client_address, self)


def main():
    """静态前端目录必须显式给出；开发服务器也可仅使用这里的合成 API。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frontend", type=Path, required=True)
    parser.add_argument("--port", type=int, default=5296)
    parser.add_argument("--background-notices", action="store_true")
    parser.add_argument("--wallpaper", type=Path, action="append", default=[])
    args = parser.parse_args()
    server = SearchServer(args.port, args.frontend.resolve())
    server.mode = "ready"
    server.wallpapers = args.wallpaper
    server.background_notices = args.background_notices
    server.serve_forever()


if __name__ == "__main__":
    main()
