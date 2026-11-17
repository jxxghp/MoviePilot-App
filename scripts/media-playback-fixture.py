"""为 iOS 原生播放器提供仅监听回环地址的短视频验收服务。"""

import argparse
from email.parser import BytesParser
from email.policy import default
import json
import mimetypes
import re
import socket
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit


class PlaybackServer(ThreadingHTTPServer):
    """持有合成影片和不含请求内容的播放计数。"""

    def __init__(
        self, port: int, media: Path, poster: Path, public_base: str | None,
        backend: str | None = None, frontend: str | None = None, ipv6: bool = False
    ) -> None:
        """只绑定回环地址，并确认影片与同名外挂字幕位于本机。"""
        self.media = media.resolve()
        self.poster = poster.resolve()
        self.loopback_base = f"http://[::1]:{port}" if ipv6 else f"http://127.0.0.1:{port}"
        self.public_base = public_base or self.loopback_base
        self.backend = backend
        self.frontend = frontend
        self.subtitle = self.media.with_name(f"{self.media.stem}.zh-CN.srt")
        self.lyrics = self.media.with_name(f"{self.media.stem}.lrc")
        self.counts = {
            "local_range_requests": 0,
            "strm_range_requests": 0,
            "audio_range_requests": 0,
            "upstream_range_requests": 0,
            "subtitle_requests": 0,
            "lyrics_requests": 0,
        }
        self.guard = threading.Lock()
        self.address_family = socket.AF_INET6 if ipv6 else socket.AF_INET
        super().__init__(("::1" if ipv6 else "127.0.0.1", port), PlaybackHandler)


class PlaybackHandler(BaseHTTPRequestHandler):
    """实现合成认证、原生桥接页面及带 Range 的本地和 STRM 播放接口。"""

    def log_message(self, _format: str, *args: object) -> None:
        """禁止访问日志写入授权头、请求参数或播放器状态。"""

    def reply(self, status: int, data: object, *, headers: dict[str, str] | None = None) -> None:
        """发送不缓存的 JSON 数据，响应体不包含认证凭据。"""
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def do_GET(self) -> None:
        """提供 App 登录、媒体清单、同名字幕和 Range 视频响应。"""
        parsed = urlsplit(self.path)
        path = self.normalize_api_path(parsed.path)
        if self.uses_backend(path):
            self.proxy_backend(path)
            return
        if path.startswith(('/api/v1/message/', '/api/v1/system/message', '/api/v1/system/progress/')):
            self.send_response(204)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if path == '/api/v1/media/157336':
            self.reply(200, {'success': True, 'message': '', 'data': {
                'media_source': 'themoviedb', 'media_id': '157336', 'tmdb_id': 157336,
                'title': '星际穿越', 'type': '电视剧', 'year': '2014',
                'episode_run_time': [90], 'genres': [{'id': 878, 'name': '科幻'}],
                'overview': '合成媒体用于验证已入库剧集的选集与原生播放。',
                'poster_path': f'{self.server.public_base}/api/v1/system/img/0',
                'vote_average': 8.7, 'seasons': [{'season_number': 1, 'episode_count': 2, 'name': '第 1 季'}],
            }})
            return
        if path == '/api/v1/media/source':
            self.reply(200, {'success': True, 'message': '', 'data': [
                {'name': 'TMDB', 'media_source': 'themoviedb', 'media_types': ['电影', '电视剧']},
                {'name': 'MusicBrainz', 'media_source': 'musicbrainz', 'media_types': ['音乐']},
            ]})
            return
        if path == '/api/v1/storage/options':
            self.reply(200, {'success': True, 'message': '', 'data': [{'type': 'local', 'name': '本地存储'}]})
            return
        if path == '/api/v1/download/paths':
            self.reply(200, {'success': True, 'message': '', 'data': [{'storage': 'local', 'download_path': '/tmp/'}]})
            return
        if path == '/api/v1/history/transfer':
            entries = []
            for index, (title, name, media_type) in enumerate([
                ('星际穿越', self.server.media.name, '电视剧'), ('晴天', 'moviepilot-playback.m4a', '音乐')
            ]):
                path = str(self.server.media.parent / name)
                entries.append({
                    'id': index + 1, 'title': title, 'year': '2014' if index == 0 else '2003',
                    'type': media_type, 'seasons': 'S01' if index == 0 else None,
                    'episodes': 'E01' if index == 0 else None, 'status': True,
                    'src': path, 'dest': path, 'src_storage': 'local', 'dest_storage': 'local',
                    'image': f'{self.server.public_base}/api/v1/system/img/0',
                    'date': '2026-11-15 15:00:00', 'files': [name], 'mode': 'copy',
                })
            self.reply(200, {'success': True, 'message': '', 'data': {'list': entries, 'total': len(entries)}})
            return
        if path == "/__playback/stats":
            with self.server.guard:
                counts = dict(self.server.counts)
            self.reply(200, counts)
            return
        if path == "/api/v1/login/initialization":
            self.reply(200, {"success": True, "message": "", "data": {"initialized": True}})
            return
        if path == "/api/v1/auth/providers":
            self.reply(200, {"success": True, "message": "", "data": []})
            return
        if path == "/api/v1/system/global":
            self.reply(200, {"success": True, "message": "", "data": {"APP_VERSION": "fixture", "WALLPAPER": ""}})
            return
        if path == "/api/v1/system/module-catalog":
            self.reply(200, {"success": True, "message": "", "data": {"modules": []}})
            return
        if path == "/api/v1/user/current":
            self.reply(200, {"success": True, "message": "", "data": {
                "id": 1, "name": "playback-fixture", "is_superuser": True,
                "level": 1, "permissions": {},
            }})
            return
        if path == "/api/v1/mediaserver/stream-info":
            self.stream_info(parse_qs(parsed.query))
            return
        if path == "/api/v1/mediaserver/search":
            self.search_library(parse_qs(parsed.query))
            return
        if path == "/api/v1/mediaserver/episodes":
            self.reply(200, {"success": True, "message": "", "data": {1: {1: "episode-local-1", 2: "episode-strm-1"}}})
            return
        if path == "/api/v1/system/img/0":
            self.send_poster()
            return
        if path == "/api/v1/mediaserver/stream-subtitle":
            self.stream_subtitle(parse_qs(parsed.query))
            return
        if path == "/api/v1/mediaserver/stream-lyrics":
            self.stream_lyrics(parse_qs(parsed.query))
            return
        if path == "/api/v1/mediaserver/stream":
            self.stream(parse_qs(parsed.query).get("itemid", [""])[0])
            return
        if path == "/__upstream/fixture.mp4":
            with self.server.guard:
                if self.headers.get("Range"):
                    self.server.counts["upstream_range_requests"] += 1
            self.send_file(self.server.media, include_body=True)
            return
        if path.startswith("/api/"):
            self.reply(200, {"success": True, "message": "", "data": []})
            return
        if self.server.frontend and parsed.path not in {'/', '/apps', '/dashboard', '/playback-fixture'}:
            self.proxy_frontend()
            return
        self.send_page()

    def do_POST(self) -> None:
        """只接受固定合成账号的密码表单并签发测试令牌。"""
        path = self.normalize_api_path(urlsplit(self.path).path)
        if self.uses_backend(path):
            self.proxy_backend(path)
            return
        if path in {'/api/v1/storage/list', '/api/v1/media/status', '/api/v1/music/recognize'}:
            body = self.rfile.read(min(int(self.headers.get('Content-Length', '0')), 65536))
            data = json.loads(body)
            if path.endswith('/storage/list'):
                result = [self.file_item(self.server.media)]
                audio_path = self.server.media.with_suffix('.m4a')
                if audio_path.is_file():
                    result.append(self.file_item(audio_path))
            elif path.endswith('/media/status'):
                result = [{'item_id': 'series-search-1', 'subscribed': False, 'seasons': {}} for _ in data]
            else:
                result = {
                    'media_source': 'musicbrainz', 'media_id': 'recording-fixture', 'music_type': 'recording',
                    'title': '晴天', 'artist': '周杰伦', 'artists': ['周杰伦'], 'album': '叶惠美',
                    'year': 2003, 'duration': 30, 'cover_url': f'{self.server.public_base}/api/v1/system/img/0',
                }
            self.reply(200, {'success': True, 'message': '', 'data': result})
            return
        if path == '/api/v1/mediaserver/stream-ticket':
            body = self.rfile.read(min(int(self.headers.get('Content-Length', '0')), 65536))
            self.create_file_stream_ticket(body)
            return
        if path == '/api/v1/mediaserver/stream-info/music':
            body = self.rfile.read(min(int(self.headers.get('Content-Length', '0')), 65536))
            request = json.loads(body)
            if not self.authorized() or request.get('media_id') != 'recording-fixture':
                self.reply(404, {})
                return
            self.reply(200, {'success': True, 'message': '', 'data': {
                'item_id': 'audio-track-1', 'title': '晴天', 'server': 'Navidrome-音乐',
            }})
            return
        if path in {'/api/v1/mediaserver/notexists', '/api/v1/mediaserver/exists_remote'}:
            self.rfile.read(min(int(self.headers.get('Content-Length', '0')), 65536))
            self.reply(200, {'success': True, 'message': '', 'data': [] if path.endswith('/notexists') else {1: [1, 2]}})
            return
        if path != "/api/v1/login/access-token":
            self.reply(404, {})
            return
        length = min(int(self.headers.get("Content-Length", "0")), 8192)
        body = self.rfile.read(length)
        content_type = self.headers.get("Content-Type", "")
        if content_type.startswith("multipart/form-data"):
            message = BytesParser(policy=default).parsebytes(
                f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode() + body
            )
            values = {
                part.get_param("name", header="content-disposition"): [part.get_content()]
                for part in message.iter_parts()
            }
        else:
            values = parse_qs(body.decode("utf-8", errors="replace"))
        if values.get("username") != ["playback-fixture"] or values.get("password") != ["fixture-only"]:
            self.reply(401, {})
            return
        self.reply(200, {
            "access_token": "playback-fixture-token",
            "super_user": True,
            "user_id": 1,
            "user_name": "playback-fixture",
            "level": 1,
            "permissions": {},
        })

    def uses_backend(self, path: str) -> bool:
        """播放、搜索和选集交给真实路由；非播放元数据继续使用合成响应。"""
        prefix = '/api/v1/mediaserver/'
        return bool(self.server.backend and path.startswith(prefix) and path[len(prefix):].startswith(('stream', 'episodes', 'search')))

    def normalize_api_path(self, path: str) -> str:
        """把产品深层路由生成的相对 API 地址映射回夹具根路径。"""
        return path.removeprefix('/product') if path.startswith('/product/api/') else path

    def create_file_stream_ticket(self, body: bytes) -> None:
        """只为夹具持有的本地临时文件签发固定测试票据。"""
        if not self.authorized():
            self.reply(401, {})
            return
        try:
            request = json.loads(body)
            file_item = request.get('file', {})
        except (json.JSONDecodeError, AttributeError):
            self.reply(400, {})
            return
        if file_item.get('storage') != 'local' or file_item.get('type') != 'file':
            self.reply(400, {})
            return
        media_path = str(self.server.media)
        audio_path = str(self.server.media.with_suffix('.m4a'))
        ticket = None
        if file_item.get('path') == media_path:
            ticket = 'file-video-1'
        elif file_item.get('path') == audio_path and self.server.media.with_suffix('.m4a').is_file():
            ticket = 'file-audio-1'
        if ticket is None:
            self.reply(404, {})
            return
        self.reply(200, {'success': True, 'message': '', 'data': {'item_id': ticket}})

    def file_item(self, path: Path) -> dict[str, object]:
        """按产品文件浏览器合同返回一个存在的本地测试文件。"""
        return {'storage': 'local', 'type': 'file', 'path': str(path), 'fileid': str(path),
                'name': path.name, 'basename': path.stem, 'extension': path.suffix.lstrip('.'),
                'size': path.stat().st_size, 'modify_time': path.stat().st_mtime}

    def proxy_frontend(self) -> None:
        """映射产品路由到前端根路径，使相对资源继续命中实际构建产物。"""
        parsed = urlsplit(self.path)
        frontend_path = parsed.path.removeprefix('/product')
        request_path = frontend_path + (f"?{parsed.query}" if parsed.query else "")
        request = urllib.request.Request(self.server.frontend + request_path)
        try:
            response = urllib.request.urlopen(request, timeout=30)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read()
            self.send_response(response.status)
            self.send_header('Content-Type', response.headers.get('Content-Type', 'application/octet-stream'))
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def proxy_backend(self, path: str) -> None:
        """将媒体请求交给隔离的真实后端路由，保留原生 Cookie、Range 和响应状态。"""
        length = min(int(self.headers.get("Content-Length", "0")), 65536)
        body = self.rfile.read(length) if self.command == "POST" else None
        headers = {
            name: self.headers[name]
            for name in ("Authorization", "Cookie", "Range", "Content-Type", "Accept")
            if self.headers.get(name)
        }
        headers["Host"] = urlsplit(self.server.public_base).netloc
        parsed = urlsplit(self.path)
        upstream_path = path + (f"?{parsed.query}" if parsed.query else "")
        request = urllib.request.Request(
            self.server.backend + upstream_path, data=body, headers=headers, method=self.command
        )
        try:
            response = urllib.request.urlopen(request, timeout=30)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            parsed = urlsplit(self.path)
            if response.status == 206 and parsed.path.endswith("/stream"):
                item_id = parse_qs(parsed.query).get("itemid", [""])[0]
                counter = (
                    "strm_range_requests" if item_id == "episode-strm-1"
                    else "audio_range_requests" if item_id == "audio-track-1"
                    else "local_range_requests"
                )
                self._count_range(counter)
            if response.status == 200 and parsed.path.endswith(("/stream-subtitle", "/stream-lyrics")):
                key = "lyrics_requests" if parsed.path.endswith("/stream-lyrics") else "subtitle_requests"
                with self.server.guard:
                    self.server.counts[key] += 1
            self.send_response(response.status)
            for name in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Set-Cookie", "Cache-Control"):
                for value in response.headers.get_all(name, []):
                    self.send_header(name, value)
            self.end_headers()
            try:
                while chunk := response.read(64 * 1024):
                    self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                self.close_connection = True

    def search_library(self, query: dict[str, list[str]]) -> None:
        """返回合成媒体服务器搜索结果，供产品搜索页的模拟器验收使用。"""
        requested_types = query.get("type[]", query.get("type", ["电视剧", "音乐"]))
        items = [
            {
                "server": "Emby-客厅",
                "item_id": "series-search-1",
                "title": "星际穿越",
                "subtitle": "科幻 · 2 集",
                "year": 2014,
                "type": "电视剧",
                "image": f"{self.server.public_base}/api/v1/system/img/0",
            },
            {
                "server": "Navidrome-音乐",
                "item_id": "audio-track-1",
                "title": "晴天",
                "subtitle": "周杰伦 · 叶惠美",
                "year": 2003,
                "type": "音乐",
                "image": f"{self.server.public_base}/api/v1/system/img/0",
            },
        ]
        matching = [item for item in items if item["type"] in requested_types]
        self.reply(200, {"success": True, "message": "", "data": matching})

    def send_poster(self) -> None:
        """使用仓库占位海报响应媒体服务器图片代理请求。"""
        data = self.server.poster.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "public, max-age=300")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def send_page(self) -> None:
        """返回使用正式 NativeChrome 桥协议打开两个已选剧集的最小页面。"""
        page = r"""<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>播放验收</title><style>body{font:17px -apple-system,sans-serif;padding:24px}button{display:block;margin:12px 0;padding:14px}</style>
<body><h1>播放验收</h1><button id="local" disabled>播放本地剧集</button><button id="strm" disabled>播放 STRM 剧集</button><button id="audio" disabled>播放音乐单曲</button>
<p><a href="/product/#/media?media_source=themoviedb&media_id=157336&type=电视剧">产品影片详情</a></p>
<p><a href="/product/#/music/detail?media_source=musicbrainz&media_id=recording-fixture">产品音乐详情</a></p>
<p><a href="/product/#/filemanager">产品文件管理</a></p>
<p><a href="/product/#/history">产品整理历史</a></p>
<script>
(() => {
  const api = window.MoviePilotNative;
  if (!api) return;
  let sessionId;
  let sequence = 0;
  let stateRevision = 0;
  const routeRevision = 0;
  const snapshot = {
    route: {fullPath:'/playback-fixture', rootId:'fixture', title:'播放验收', canGoBack:false},
    roots: [{id:'fixture', path:'/playback-fixture', title:'媒体测试', icon:'movie'}],
    actions: [],
    chrome: {topVisible:true, bottomVisible:true, theme:'system'}
  };
  function post(type, payload) {
    const message = {protocol:'moviepilot.chrome', major:1, type, requestId:`web-${++sequence}`, payload};
    if (sessionId) Object.assign(message, {sessionId, routeRevision, stateRevision});
    api.postMessage(message);
  }
  function play(itemId, title) {
    post('playback.open', {itemId, title, season:1, episode:1});
  }
  window.addEventListener('moviepilot:native-message', event => {
    const message = event.detail;
    if (message.type === 'host.configure') {
      sessionId = message.payload.sessionId;
      stateRevision = 1;
      post('navigation.state', snapshot);
    } else if (message.type === 'chrome.prepare') {
      post('chrome.accepted', {layoutRevision:message.payload.layoutRevision});
      document.querySelectorAll('button').forEach(button => { button.disabled = false; });
    }
  });
  document.querySelector('#local').addEventListener('click', () => play('episode-local-1', '测试剧集 S01E01'));
  document.querySelector('#strm').addEventListener('click', () => play('episode-strm-1', '测试剧集 S01E01'));
  document.querySelector('#audio').addEventListener('click', () => play('audio-track-1', '测试音乐歌曲'));
  post('web.ready', {majors:[1], capabilities:['navigation.v1','actions.v1','layout.v1','menu.v1','notifications.v1','playback.v1']});
})();
</script></body></html>""".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(page)

    def stream_info(self, query: dict[str, list[str]]) -> None:
        """要求固定访问令牌，并返回受控剧集或音乐条目的媒体清单。"""
        item_id = query.get("itemid", [""])[0]
        allowed_ids = {
            "episode-local-1", "episode-strm-1", "audio-track-1", "series-search-1",
            "file-video-1", "file-audio-1",
        }
        if item_id not in allowed_ids:
            self.reply(404, {})
            return
        if not self.authorized():
            self.reply(401, {})
            return
        base = f"{self.server.public_base}/api/v1/mediaserver"
        selected = {"itemid": item_id}
        if server := query.get("server", [""])[0]:
            selected["server"] = server
        content_url = f"{base}/stream?{urlencode(selected)}"
        subtitle_url = f"{base}/stream-subtitle?{urlencode({**selected, 'subtitle_id': self.server.subtitle.name})}"
        is_audio = item_id in {"audio-track-1", "file-audio-1"}
        lyrics_url = f"{base}/stream-lyrics?{urlencode(selected)}"
        self.reply(200, {"success": True, "message": "", "data": {
            "item_id": item_id,
            "title": "测试音乐歌曲" if is_audio else "测试剧集 S01E01",
            "content_url": content_url,
            "media_type": "audio" if is_audio else "video",
            "artist": "周杰伦" if is_audio else None,
            "album": "叶惠美" if is_audio else None,
            "lyrics_url": lyrics_url if is_audio else None,
            "subtitles": [] if is_audio else [{
                "subtitle_id": self.server.subtitle.name,
                "title": "zh CN",
                "language": "zh-CN",
                "url": subtitle_url,
            }],
        }}, headers={"Set-Cookie": "resource_token=fixture-stream-only; Path=/api/v1/mediaserver/stream; HttpOnly; SameSite=Lax"})

    def stream_subtitle(self, query: dict[str, list[str]]) -> None:
        """只提供清单中已声明的同名外挂字幕。"""
        item_id = query.get("itemid", [""])[0]
        subtitle_id = query.get("subtitle_id", [""])[0]
        if not self.authorized() or item_id not in {"episode-local-1", "episode-strm-1"}:
            self.reply(401, {})
            return
        if subtitle_id != self.server.subtitle.name or not self.server.subtitle.is_file():
            self.reply(404, {})
            return
        with self.server.guard:
            self.server.counts["subtitle_requests"] += 1
        data = self.server.subtitle.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def stream_lyrics(self, query: dict[str, list[str]]) -> None:
        """只提供播放清单声明的音乐 LRC 文件。"""
        item_id = query.get("itemid", [""])[0]
        if not self.authorized() or item_id != "audio-track-1":
            self.reply(401, {})
            return
        if not self.server.lyrics.is_file():
            self.reply(404, {})
            return
        with self.server.guard:
            self.server.counts["lyrics_requests"] += 1
        data = self.server.lyrics.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def stream(self, item_id: str) -> None:
        """验证媒体资源 Cookie，并以本地读取或 STRM 上游请求返回视频。"""
        if "resource_token=fixture-stream-only" not in self.headers.get("Cookie", ""):
            self.reply(401, {})
            return
        if item_id in {"episode-local-1", "series-search-1", "file-video-1"}:
            self._count_range("local_range_requests")
            self.send_file(self.server.media, include_body=True)
            return
        if item_id in {"audio-track-1", "file-audio-1"}:
            self._count_range("audio_range_requests")
            audio_path = self.server.media.with_suffix('.m4a')
            self.send_file(audio_path if audio_path.is_file() else self.server.media, include_body=True)
            return
        if item_id != "episode-strm-1":
            self.reply(404, {})
            return
        self._count_range("strm_range_requests")
        upstream = urllib.request.Request(
            f"{self.server.loopback_base}/__upstream/fixture.mp4",
            headers={"Range": self.headers["Range"]} if self.headers.get("Range") else {},
        )
        try:
            with urllib.request.urlopen(upstream, timeout=20) as response:
                self.send_response(response.status)
                for name in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
                    if value := response.headers.get(name):
                        self.send_header(name, value)
                self.end_headers()
                self.wfile.write(response.read())
        except (urllib.error.URLError, BrokenPipeError, ConnectionResetError):
            self.send_error(502)

    def send_file(self, path: Path, *, include_body: bool) -> None:
        """按单个标准字节区间读取文件并写出播放器需要的 Range 标头。"""
        data = path.read_bytes()
        header = self.headers.get("Range")
        start, end = 0, len(data) - 1
        status = 200
        if header:
            matched = re.fullmatch(r"bytes=(\d*)-(\d*)", header.strip())
            if not matched or not any(matched.groups()) or not data:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(data)}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            left, right = matched.groups()
            if left:
                start = int(left)
                end = min(int(right), len(data) - 1) if right else len(data) - 1
            else:
                start = max(0, len(data) - int(right))
            if start >= len(data) or end < start:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(data)}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            status = 206
        body = data[start : end + 1]
        self.send_response(status)
        self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(len(body)))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.end_headers()
        if include_body:
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                self.close_connection = True

    def authorized(self) -> bool:
        """验证测试服务独有的 Bearer 值，不打印或持久化请求头。"""
        return self.headers.get("Authorization") == "Bearer playback-fixture-token"

    def _count_range(self, key: str) -> None:
        """只累计是否收到 Range，不保留完整视频请求头。"""
        if self.headers.get("Range"):
            with self.server.guard:
                self.server.counts[key] += 1


def main() -> None:
    """启动仅绑定回环地址的合成流媒体服务，不连接真实 MoviePilot 实例。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--media", type=Path, required=True, help="合成 MP4，需有同名 .zh-CN.srt 和 .lrc 字幕")
    parser.add_argument("--port", type=int, default=5317)
    parser.add_argument("--ipv6", action="store_true", help="只绑定 IPv6 回环 ::1")
    parser.add_argument("--poster", type=Path, required=True, help="媒体服务器海报响应使用的测试 JPEG")
    parser.add_argument("--public-base", help="通过前端开发代理访问时的回环来源")
    parser.add_argument("--backend", help="可选的回环后端来源，媒体请求转发到其正式路由")
    parser.add_argument("--frontend", help="可选的回环 Vite 来源，用于产品入口验收")
    args = parser.parse_args()
    subtitle = args.media.with_name(f"{args.media.stem}.zh-CN.srt")
    lyrics = args.media.with_name(f"{args.media.stem}.lrc")
    if not args.media.is_file() or not subtitle.is_file() or not lyrics.is_file():
        parser.error("媒体文件与同名 .zh-CN.srt 和 .lrc 文件必须存在")
    if not args.poster.is_file():
        parser.error("--poster 必须是存在的测试 JPEG")
    for origin in (args.backend, args.frontend):
        if origin:
            parsed = urlsplit(origin)
            if parsed.scheme != "http" or parsed.hostname != "127.0.0.1" or parsed.path or parsed.query or parsed.fragment:
                parser.error("--backend 和 --frontend 仅接受不带路径的 http://127.0.0.1:端口")
    with PlaybackServer(args.port, args.media, args.poster, args.public_base, args.backend, args.frontend, args.ipv6) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
