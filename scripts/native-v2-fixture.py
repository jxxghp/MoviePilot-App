#!/usr/bin/env python3
"""仅提供回环 API 的原生入口夹具；不提供前端、脚本或真实账号数据。"""

import argparse
import base64
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import struct
import threading
import time
import zlib
from urllib.parse import parse_qs, unquote, urlsplit


class NativeFixture(ThreadingHTTPServer):
    """四个部署子路径模拟隔离实例，控制端点只保存合成状态与请求计数。"""

    def __init__(self, port):
        """绑定 IPv4 回环；允许测试使用系统分配端口，不暴露局域网服务。"""
        self.lock = threading.Lock()
        self.profiles = {
            name: {
                "mode": "new" if name == "new" else "ready",
                "counts": Counter(),
                "subscriptions": set(),
                "sub_items": [
                    {
                        "id": 701, "name": "合成订阅电影", "year": "2025", "type": "电影",
                        "season": None, "poster": "https://images.example.test/101/poster.png",
                        "media_source": "themoviedb", "media_id": "101", "state": "R",
                        "vote": 8.4, "best_version": 0,
                    },
                    {
                        "id": 702, "name": "合成追剧", "year": "2025", "type": "电视剧",
                        "season": 1, "poster": "https://images.example.test/111/poster.png",
                        "media_source": "themoviedb", "media_id": "111", "state": "R",
                        "vote": 8.8, "total_episode": 12, "lack_episode": 3,
                        "completed_episode": 9, "best_version": 0,
                    },
                ],
                "downloads": [
                    {
                        "downloader": "Qbittorrent", "hash": "abc123def456",
                        "title": "Synthetic.Show.S01.2160p", "name": "合成追剧", "year": "2025",
                        "season_episode": "S01", "site_name": "合成站", "size": 42_949_672_960.0,
                        "progress": 42.5, "state": "downloading", "upspeed": "512.0K",
                        "dlspeed": "12.4M", "left_time": "18分20秒",
                        "media": {
                            "type": "电视剧", "title": "合成追剧", "season": "S01",
                            "episode": "E09", "backdrop": "https://images.example.test/111/backdrop.png",
                            "poster": "https://images.example.test/111/poster.png",
                            "media_source": "themoviedb", "media_id": "111",
                        },
                    }
                ],
                "history": [
                    {
                        "id": 801, "title": "合成追剧", "type": "电视剧", "year": "2025",
                        "seasons": "S01", "episodes": "E08", "status": True, "mode": "copy",
                        "date": "2026-11-20 21:00:00", "errmsg": None,
                        "src": "/downloads/tv/syn-s01e08.mkv", "dest": "/video/tv/syn-s01e08.mkv",
                        "image": "https://images.example.test/111/poster.png",
                        "media_source": "themoviedb", "media_id": "111",
                    }
                ],
                "files": [
                    {"storage": "local", "type": "dir", "path": "/media/", "name": "media"},
                    {"storage": "local", "type": "file", "path": "/sample.mkv", "name": "sample.mkv", "extension": "mkv", "size": 1_073_741_824},
                ],
                "workflows": [
                    {
                        "id": 31, "name": "合成自动整理", "description": "定时检查下载目录",
                        "timer": "*/15 * * * *", "state": "P", "run_count": 2, "result": None,
                    }
                ],
                "env": {
                    "RECOGNIZE_SOURCE": "themoviedb",
                    "SEARCH_SOURCE": "themoviedb",
                    "SCRAP_FOLLOW_TMDB": True,
                    "SUBSCRIBE_MODE": "spider",
                    "SUBSCRIBE_RSS_INTERVAL": 30,
                    "SUBSCRIBE_SEARCH": False,
                    "TORRENT_TAG": "MOVIEPILOT",
                    "MEDIASERVER_SYNC_INTERVAL": 6,
                    "GLOBAL_IMAGE_CACHE": True,
                    "DEBUG": False,
                    "LOG_LEVEL": "INFO",
                    "TZ": "Asia/Shanghai",
                    "VERSION": "v3.0.0-synthetic",
                },
                "users": [
                    {
                        "id": 10, "name": "native-a", "email": "admin@example.test",
                        "is_active": True, "is_superuser": True, "is_otp": True,
                        "permissions": {"discovery": True, "search": True, "subscribe": True, "manage": True},
                    },
                    {
                        "id": 20, "name": "native-b", "email": "member@example.test",
                        "is_active": True, "is_superuser": False, "is_otp": False,
                        "permissions": {"discovery": True, "search": True, "subscribe": True, "manage": False},
                    },
                ],
                "user_configs": {},
                "market_plugins": [
                    {
                        "id": "AutoSignIn", "plugin_name": "站点自动签到", "plugin_desc": "定时执行站点签到与刷流任务",
                        "plugin_version": "2.4.0", "plugin_label": "站点,定时", "plugin_author": "MoviePilot",
                        "installed": False, "has_update": False, "state": False,
                        "repo_url": "https://github.com/jxxghp/MoviePilot-Plugins", "install_count": 3200,
                    }
                ],
                "installed_plugins": [
                    {
                        "id": "DemoPlugin", "plugin_name": "合成演示插件", "plugin_desc": "用于生命周期重置与卸载测试",
                        "plugin_version": "1.0.0", "plugin_label": "工具", "plugin_author": "MoviePilot",
                        "installed": True, "has_update": False, "has_page": True, "state": True,
                        "repo_url": "https://github.com/jxxghp/MoviePilot-Plugins", "install_count": 120,
                    },
                    {
                        "id": "VueCompatDemo", "plugin_name": "合成远程组件插件", "plugin_desc": "用于受控兼容容器隔离验证",
                        "plugin_version": "1.2.0", "plugin_label": "扩展", "plugin_author": "MoviePilot",
                        "installed": True, "has_update": False, "has_page": True, "state": True,
                        "repo_url": "https://github.com/jxxghp/MoviePilot-Plugins", "install_count": 88,
                    },
                ],
                "agent_sessions": [
                    {
                        "session_id": "sess-1", "title": "合成科幻推荐", "message_count": 2,
                        "messages": [
                            {"id": "m1", "role": "user", "content": "推荐一部科幻片", "tools": []},
                            {"id": "m2", "role": "assistant", "content": "推荐观看《合成电影 101》，评分 8.4。", "tools": [{"message": "已检索 TMDB 评分"}]},
                        ],
                    }
                ],
            }
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
        """处理初始化、登录、媒体状态查询、合成订阅与测试状态控制。"""
        self.dispatch()

    def do_DELETE(self):
        """处理受控合成订阅取消与下载任务删除。"""
        self.dispatch()

    def do_PUT(self):
        """处理受控合成订阅状态切换。"""
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

    @staticmethod
    def png_chunk(kind, data):
        """生成带 CRC 的 PNG 块，夹具不需要图像处理依赖。"""
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    def reply_image(self, reference):
        """生成合成海报渐变，区分不同结果与横幅，不访问外部网络。"""
        width, height = (320, 180) if reference.endswith("/backdrop.png") else (128, 192)
        salt = sum(reference.encode())
        rows = bytearray()
        for y in range(height):
            rows.append(0)
            for x in range(width):
                glow = max(0, 80 - abs(x - width // 3) - abs(y - height // 3))
                rows.extend((45 + salt % 65 + glow, 28 + x * 56 // width + glow, 65 + salt % 75 + glow))
        data = (
            b"\x89PNG\r\n\x1a\n"
            + self.png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + self.png_chunk(b"IDAT", zlib.compress(rows))
            + self.png_chunk(b"IEND", b"")
        )
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
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
                    "ready", "new", "otp", "expired", "unavailable", "slow",
                    "discovery-only", "resource-search-only", "search-failed", "storage-failed",
                    "partial-discovery-failed", "subscribe-failed",
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
                    profile["subscriptions"].clear()
                    profile["sub_items"] = [
                        {
                            "id": 701, "name": "合成订阅电影", "year": "2025", "type": "电影",
                            "season": None, "poster": "https://images.example.test/101/poster.png",
                            "media_source": "themoviedb", "media_id": "101", "state": "R",
                            "vote": 8.4, "best_version": 0,
                        },
                        {
                            "id": 702, "name": "合成追剧", "year": "2025", "type": "电视剧",
                            "season": 1, "poster": "https://images.example.test/111/poster.png",
                            "media_source": "themoviedb", "media_id": "111", "state": "R",
                            "vote": 8.8, "total_episode": 12, "lack_episode": 3,
                            "completed_episode": 9, "best_version": 0,
                        },
                    ]
                    profile["downloads"] = [
                        {
                            "downloader": "Qbittorrent", "hash": "abc123def456",
                            "title": "Synthetic.Show.S01.2160p", "name": "合成追剧", "year": "2025",
                            "season_episode": "S01", "site_name": "合成站", "size": 42_949_672_960.0,
                            "progress": 42.5, "state": "downloading", "upspeed": "512.0K",
                            "dlspeed": "12.4M", "left_time": "18分20秒",
                            "media": {
                                "type": "电视剧", "title": "合成追剧", "season": "S01",
                                "episode": "E09", "backdrop": "https://images.example.test/111/backdrop.png",
                                "poster": "https://images.example.test/111/poster.png",
                                "media_source": "themoviedb", "media_id": "111",
                            },
                        }
                    ]
                    profile["history"] = [
                        {
                            "id": 801, "title": "合成追剧", "type": "电视剧", "year": "2025",
                            "seasons": "S01", "episodes": "E08", "status": True, "mode": "copy",
                            "date": "2026-11-20 21:00:00", "errmsg": None,
                            "src": "/downloads/tv/syn-s01e08.mkv", "dest": "/video/tv/syn-s01e08.mkv",
                            "image": "https://images.example.test/111/poster.png",
                            "media_source": "themoviedb", "media_id": "111",
                        }
                    ]
                    profile["files"] = [
                        {"storage": "local", "type": "dir", "path": "/media/", "name": "media"},
                        {"storage": "local", "type": "file", "path": "/sample.mkv", "name": "sample.mkv", "extension": "mkv", "size": 1_073_741_824},
                    ]
                    profile["workflows"] = [
                        {
                            "id": 31, "name": "合成自动整理", "description": "定时检查下载目录",
                            "timer": "*/15 * * * *", "state": "P", "run_count": 2, "result": None,
                        }
                    ]
                    profile["env"] = {
                        "RECOGNIZE_SOURCE": "themoviedb",
                        "SEARCH_SOURCE": "themoviedb",
                        "SCRAP_FOLLOW_TMDB": True,
                        "SUBSCRIBE_MODE": "spider",
                        "SUBSCRIBE_RSS_INTERVAL": 30,
                        "SUBSCRIBE_SEARCH": False,
                        "TORRENT_TAG": "MOVIEPILOT",
                        "MEDIASERVER_SYNC_INTERVAL": 6,
                        "GLOBAL_IMAGE_CACHE": True,
                        "DEBUG": False,
                        "LOG_LEVEL": "INFO",
                        "TZ": "Asia/Shanghai",
                        "VERSION": "v3.0.0-synthetic",
                    }
                    profile["user_configs"] = {}
                    profile["market_plugins"] = [
                        {
                            "id": "AutoSignIn", "plugin_name": "站点自动签到", "plugin_desc": "定时执行站点签到与刷流任务",
                            "plugin_version": "2.4.0", "plugin_label": "站点,定时", "plugin_author": "MoviePilot",
                            "installed": False, "has_update": False, "state": False,
                            "repo_url": "https://github.com/jxxghp/MoviePilot-Plugins", "install_count": 3200,
                        }
                    ]
                    profile["installed_plugins"] = [
                        {
                            "id": "DemoPlugin", "plugin_name": "合成演示插件", "plugin_desc": "用于生命周期重置与卸载测试",
                            "plugin_version": "1.0.0", "plugin_label": "工具", "plugin_author": "MoviePilot",
                            "installed": True, "has_update": False, "has_page": True, "state": True,
                            "repo_url": "https://github.com/jxxghp/MoviePilot-Plugins", "install_count": 120,
                        },
                        {
                            "id": "VueCompatDemo", "plugin_name": "合成远程组件插件", "plugin_desc": "用于受控兼容容器隔离验证",
                            "plugin_version": "1.2.0", "plugin_label": "扩展", "plugin_author": "MoviePilot",
                            "installed": True, "has_update": False, "has_page": True, "state": True,
                            "repo_url": "https://github.com/jxxghp/MoviePilot-Plugins", "install_count": 88,
                        },
                    ]
                    profile["agent_sessions"] = [
                        {
                            "session_id": "sess-1", "title": "合成科幻推荐", "message_count": 2,
                            "messages": [
                                {"id": "m1", "role": "user", "content": "推荐一部科幻片", "tools": []},
                                {"id": "m2", "role": "assistant", "content": "推荐观看《合成电影 101》，评分 8.4。", "tools": [{"message": "已检索 TMDB 评分"}]},
                            ],
                        }
                    ]
            self.reply(200, {"success": True})
            return
        parts = [unquote(segment) for segment in path.strip("/").split("/") if segment]
        name = parts[0] if parts else ""
        endpoint = "/".join(parts[1:])
        if name in self.server.profiles and self.command == "GET":
            if (
                endpoint in self.business_endpoints()
                or path in {
                    f"/{name}/api/v1/download/",
                    f"/{name}/api/v1/subscribe/",
                    f"/{name}/api/v1/site/",
                    f"/{name}/api/v1/workflow/",
                    f"/{name}/api/v1/user/",
                }
                or re.fullmatch(r"api/v1/download/(?:start|stop)/[a-z0-9]+", endpoint)
                or re.fullmatch(r"api/v1/site/test/[0-9]+", endpoint)
                or re.fullmatch(r"api/v1/search/media/1[0-9]{2}", endpoint)
                or re.fullmatch(r"api/v1/media/1[0-9]{2}", endpoint)
                or re.fullmatch(r"api/v1/tmdb/(?:credits|recommend|similar)/1[0-9]{2}/(?:电影|电视剧)", endpoint)
                or re.fullmatch(r"api/v1/tmdb/person(?:/credits)?/[0-9]{3}", endpoint)
                or re.fullmatch(r"api/v1/user/config/[A-Za-z0-9_.-]+", endpoint)
                or re.fullmatch(r"api/v1/subscribe/[0-9]+", endpoint)
                or re.fullmatch(r"api/v1/music/album/[A-Za-z0-9_-]+", endpoint)
                or re.fullmatch(r"api/v1/music/artist/[A-Za-z0-9_-]+(?:/albums)?", endpoint)
                or re.fullmatch(r"api/v1/agent/sessions/[A-Za-z0-9_-]+", endpoint)
            ):
                self.business_endpoint(name, endpoint)
                return
            if path == f"/{name}/api/v1/plugin/":
                self.plugin_list_endpoint(name)
                return
            if endpoint == "api/v1/plugin/dashboard/meta":
                self.plugin_dashboard_meta_endpoint(name)
                return
            if re.fullmatch(r"api/v1/plugin/dashboard/[A-Za-z][A-Za-z0-9_]*(?:/[A-Za-z0-9_-]+)?", endpoint):
                self.plugin_dashboard_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/plugin/page/[A-Za-z][A-Za-z0-9_]*", endpoint):
                self.plugin_page_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/plugin/(?:install|reset)/[A-Za-z][A-Za-z0-9_]*", endpoint):
                self.plugin_action_endpoint(name, endpoint)
                return
            if endpoint == "api/v1/system/img/0":
                self.image_endpoint(name)
                return
        if name in self.server.profiles and self.command == "POST":
            if endpoint == "api/v1/media/status":
                self.media_status_endpoint(name, body)
                return
            if endpoint == "api/v1/download/add":
                self.download_add_endpoint(name, body)
                return
            if endpoint in {"api/v1/storage/list", "api/v1/storage/mkdir", "api/v1/storage/delete"}:
                self.storage_endpoint(name, endpoint, body)
                return
            if re.fullmatch(r"api/v1/workflow/[0-9]+/(?:run|start|pause|reset)", endpoint):
                self.workflow_action_endpoint(name, endpoint)
                return
            if endpoint == "api/v1/system/env":
                self.system_env_update_endpoint(name, body)
                return
            if re.fullmatch(r"api/v1/user/config/[A-Za-z0-9_.-]+", endpoint):
                self.user_config_update_endpoint(name, endpoint, body)
                return
            if path == f"/{name}/api/v1/subscribe/":
                self.subscribe_create_endpoint(name, body)
                return
            if endpoint == "api/v1/subscribe/fork":
                self.subscribe_fork_endpoint(name, body)
                return
            if endpoint == "api/v1/agent/stream":
                self.agent_stream_endpoint(name, body)
                return
            if re.fullmatch(r"api/v1/agent/sessions/[A-Za-z0-9_-]+/stop", endpoint):
                self.agent_stop_endpoint(name, endpoint)
                return
        if name in self.server.profiles and self.command == "PUT":
            if path == f"/{name}/api/v1/subscribe/":
                self.subscribe_update_endpoint(name, body)
                return
            if re.fullmatch(r"api/v1/subscribe/status/[0-9]+", endpoint):
                self.subscribe_status_endpoint(name, endpoint)
                return
        if name in self.server.profiles and self.command == "DELETE":
            if endpoint == "api/v1/history/transfer":
                self.history_delete_endpoint(name, body)
                return
            if re.fullmatch(r"api/v1/subscribe/media/[A-Za-z0-9_-]+", endpoint):
                self.subscribe_delete_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/subscribe/[0-9]+", endpoint):
                self.subscribe_delete_by_id_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/download/[a-z0-9]+", endpoint):
                self.download_delete_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/plugin/[A-Za-z][A-Za-z0-9_]*", endpoint):
                self.plugin_delete_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/agent/sessions/[A-Za-z0-9_-]+", endpoint):
                self.agent_session_delete_endpoint(name, endpoint)
                return
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

    @staticmethod
    def business_endpoints():
        """列出 smoke 验收允许的媒体、来源与管理员仪表盘只读端点。"""
        return {
            "api/v1/discover/source",
            "api/v1/discover/tmdb_movies",
            "api/v1/discover/tmdb_tvs",
            "api/v1/discover/douban_movies",
            "api/v1/discover/douban_tvs",
            "api/v1/discover/bangumi",
            "api/v1/recommend/tmdb_trending",
            "api/v1/recommend/douban_showing",
            "api/v1/recommend/douban_movie_top250",
            "api/v1/recommend/music_douban",
            "api/v1/recommend/music_weekly",
            "api/v1/music/explore",
            "api/v1/mediaserver/clients",
            "api/v1/mediaserver/playing",
            "api/v1/mediaserver/latest",
            "api/v1/mediaserver/library",
            "api/v1/media/search",
            "api/v1/media/source",
            "api/v1/download/clients",
            "api/v1/download/paths",
            "api/v1/search/last",
            "api/v1/search/title",
            "api/v1/history/transfer",
            "api/v1/message/web",
            "api/v1/storage/options",
            "api/v1/system/env",
            "api/v1/subscribe/calendar",
            "api/v1/subscribe/popular",
            "api/v1/subscribe/shares",
            "api/v1/agent/commands",
            "api/v1/agent/sessions",
            "api/v1/dashboard/statistic",
            "api/v1/dashboard/storage",
            "api/v1/dashboard/schedule",
        }

    def business_endpoint(self, name, endpoint):
        """验证当前服务令牌后回传固定合成媒体数据和标准 API envelope。"""
        query = parse_qs(urlsplit(self.path).query)
        page = query.get("page", ["1"])[0]
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"GET {endpoint}"] += 1
            if endpoint == "api/v1/media/search":
                title = query.get("title", [""])[0]
                key = title if title in {"galaxy", "unsubmitted"} else "other"
                profile["counts"][f"search:{key}:{page}"] += 1
            elif endpoint.startswith("api/v1/discover/"):
                profile["counts"][f"discover:{endpoint.rsplit('/', 1)[-1]}:{page}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        requires_discovery = (
            endpoint.startswith("api/v1/discover/")
            or endpoint.startswith("api/v1/recommend/")
            or endpoint.startswith("api/v1/mediaserver/")
            or endpoint.startswith("api/v1/tmdb/")
            or endpoint.startswith("api/v1/music/")
            or endpoint == "api/v1/media/search"
            or re.fullmatch(r"api/v1/media/1[0-9]{2}", endpoint)
        )
        if requires_discovery and not self.permissions(mode)["discovery"]:
            self.reply(403, {"success": False})
            return
        if (endpoint.startswith("api/v1/dashboard/") or endpoint in {"api/v1/system/env", "api/v1/user"}) and name != "a":
            self.reply(403, {"success": False})
            return
        if (mode, endpoint) in {
            ("search-failed", "api/v1/media/search"),
            ("storage-failed", "api/v1/dashboard/storage"),
            ("partial-discovery-failed", "api/v1/discover/tmdb_tvs"),
        }:
            self.reply(503, {"success": False})
            return
        if endpoint in {"api/v1/discover/tmdb_movies", "api/v1/discover/tmdb_tvs"}:
            is_movie = endpoint.endswith("tmdb_movies")
            first_id = 101 if is_movie else 111
            ids = range(first_id, first_id + 12) if page == "1" else [first_id + 12] if page == "2" else []
            value = [self.media(item_id, "电影" if is_movie else "电视剧") for item_id in ids]
        elif endpoint in {
            "api/v1/discover/douban_movies",
            "api/v1/discover/douban_tvs",
            "api/v1/discover/bangumi",
            "api/v1/recommend/douban_showing",
            "api/v1/recommend/douban_movie_top250",
        }:
            is_movie = "movie" in endpoint or "showing" in endpoint
            first_id = 131 if is_movie else 141
            ids = range(first_id, first_id + 6) if page == "1" else []
            value = [self.media(item_id, "电影" if is_movie else "电视剧") for item_id in ids]
        elif endpoint in {
            "api/v1/recommend/music_douban",
            "api/v1/recommend/music_weekly",
            "api/v1/music/explore",
        }:
            value = [{
                "type": "音乐", "music_type": "album",
                "media_source": "musicbrainz", "media_id": "alb-201", "album_id": "alb-201",
                "title": "合成星际原声带", "artist": "合成乐团", "artists": ["合成乐团"],
                "artist_ids": ["art-301"], "year": 2025, "rating": 9.1,
                "cover_url": "https://images.example.test/101/poster.png",
            }]
        elif re.fullmatch(r"api/v1/music/album/[A-Za-z0-9_-]+", endpoint):
            value = {
                "type": "音乐", "music_type": "album",
                "media_source": "musicbrainz", "media_id": "alb-201",
                "title": "合成星际原声带", "artist": "合成乐团", "artists": ["合成乐团"],
                "artist_ids": ["art-301"], "album_type": "Album", "year": 2025,
                "total_tracks": 2, "cover_url": "https://images.example.test/101/poster.png",
                "overview": "面向原生音乐详情验证的合成专辑曲目。",
                "tracks": [
                    {"title": "序曲：星尘启航", "track_number": 1, "duration": 215, "artist": "合成乐团"},
                    {"title": "终章：漫游银河", "track_number": 2, "duration": 268, "artist": "合成乐团"},
                ],
            }
        elif re.fullmatch(r"api/v1/music/artist/[A-Za-z0-9_-]+/albums", endpoint):
            value = [{
                "type": "音乐", "music_type": "album",
                "media_source": "musicbrainz", "media_id": "alb-201", "album_id": "alb-201",
                "title": "合成星际原声带", "artist": "合成乐团", "artist_ids": ["art-301"],
                "year": 2025, "cover_url": "https://images.example.test/101/poster.png",
            }]
        elif re.fullmatch(r"api/v1/music/artist/[A-Za-z0-9_-]+", endpoint):
            value = {
                "type": "音乐", "music_type": "artist",
                "media_source": "musicbrainz", "media_id": "art-301",
                "name": "合成乐团", "country": "CN", "life_span": "2018 - 至今",
                "image_url": "https://images.example.test/111/poster.png",
                "overview": "专注于影视原声与器乐编排的合成艺人。",
            }
        elif endpoint == "api/v1/agent/commands":
            value = [
                {"command": "/search", "description": "搜索影视资源"},
                {"command": "/subscribe", "description": "查看订阅列表"},
            ]
        elif endpoint == "api/v1/agent/sessions":
            with self.server.lock:
                value = [
                    {k: v for k, v in row.items() if k != "messages"}
                    for row in self.server.profiles[name]["agent_sessions"]
                ]
        elif re.fullmatch(r"api/v1/agent/sessions/[A-Za-z0-9_-]+", endpoint):
            sid = endpoint.rsplit("/", 1)[-1]
            with self.server.lock:
                matched = next((row for row in self.server.profiles[name]["agent_sessions"] if row["session_id"] == sid), None)
            if matched is None:
                self.reply(404, {"success": False})
                return
            value = dict(matched)
        elif endpoint in {
            "api/v1/discover/source",
            "api/v1/recommend/tmdb_trending",
            "api/v1/mediaserver/clients",
            "api/v1/mediaserver/playing",
            "api/v1/mediaserver/latest",
            "api/v1/mediaserver/library",
        }:
            value = []
        elif endpoint.startswith("api/v1/user/config/"):
            cfg_key = endpoint.rsplit("/", 1)[-1]
            with self.server.lock:
                value = {"value": self.server.profiles[name]["user_configs"].get(cfg_key)}
        elif endpoint == "api/v1/media/search":
            if title == "galaxy" and page in {"1", "2"}:
                ids = range(121, 129) if page == "1" else [129]
                value = [self.media(item_id, "电影") for item_id in ids]
            else:
                value = []
        elif endpoint == "api/v1/media/source":
            value = [{"name": "TMDB", "media_source": "themoviedb", "media_types": ["电影", "电视剧"]}]
        elif endpoint == "api/v1/download/clients":
            value = [{"name": "Qbittorrent", "type": "qbittorrent"}]
        elif endpoint == "api/v1/download/paths":
            value = [{"name": "电影库", "save_path": "local:/downloads/movies", "download_path": "/downloads/movies"}]
        elif endpoint == "api/v1/site":
            value = [{"id": 3, "name": "合成站", "domain": "syn.example.test", "is_active": True, "pri": 1}]
        elif re.fullmatch(r"api/v1/site/test/[0-9]+", endpoint):
            value = None
        elif endpoint == "api/v1/history/transfer":
            with self.server.lock:
                rows = list(self.server.profiles[name]["history"])
            value = {"list": rows, "total": len(rows)}
        elif endpoint == "api/v1/storage/options":
            value = [{"type": "local", "name": "本地"}, {"type": "smb", "name": "SMB网络共享"}]
        elif endpoint == "api/v1/workflow":
            with self.server.lock:
                value = list(self.server.profiles[name]["workflows"])
        elif endpoint == "api/v1/system/env":
            with self.server.lock:
                value = dict(self.server.profiles[name]["env"])
        elif endpoint == "api/v1/user":
            with self.server.lock:
                value = list(self.server.profiles[name]["users"])
        elif endpoint == "api/v1/message/web":
            value = [
                {
                    "id": 901, "mtype": "订阅", "title": "合成追剧 S01 已开始下载",
                    "text": "已匹配 2160p 中字版本并提交至 Qbittorrent。",
                    "image": "https://images.example.test/111/backdrop.png",
                    "reg_time": "2026-11-20 22:00:00",
                }
            ]
        elif endpoint in {"api/v1/search/last", "api/v1/search/title"} or endpoint.startswith("api/v1/search/media/"):
            if not self.permissions(mode)["search"]:
                self.reply(403, {"success": False})
                return
            value = [
                {
                    "torrent_info": {
                        "site": 3, "site_name": "合成站",
                        "title": "Synthetic.Movie.2025.2160p.WEB-DL.H265-SYN",
                        "description": "合成资源 4K 中字免费种",
                        "enclosure": "https://tracker.example.test/download/9001",
                        "size": 12_884_901_888.0, "seeders": 64, "peers": 5, "grabs": 120,
                        "downloadvolumefactor": 0.0, "uploadvolumefactor": 2.0,
                        "date_elapsed": "2小时", "labels": ["中字", "官方"], "pri_order": 99,
                        "media_source": "themoviedb", "media_id": "113",
                    },
                    "meta_info": {
                        "resource_pix": "2160p", "video_encode": "H265",
                        "edition": "WEB-DL", "season_episode": "",
                    },
                }
            ]
        elif endpoint == "api/v1/download":
            with self.server.lock:
                value = list(self.server.profiles[name]["downloads"])
        elif re.fullmatch(r"api/v1/download/(?:start|stop)/[a-z0-9]+", endpoint):
            parts_ep = endpoint.split("/")
            action, task_hash = parts_ep[3], parts_ep[4]
            with self.server.lock:
                for row in self.server.profiles[name]["downloads"]:
                    if row["hash"] == task_hash:
                        row["state"] = "downloading" if action == "start" else "unavailable"
            value = None
        elif endpoint == "api/v1/subscribe":
            with self.server.lock:
                value = list(self.server.profiles[name]["sub_items"])
        elif re.fullmatch(r"api/v1/subscribe/[0-9]+", endpoint):
            sub_id = int(endpoint.rsplit("/", 1)[-1])
            with self.server.lock:
                matched = next((row for row in self.server.profiles[name]["sub_items"] if row["id"] == sub_id), None)
            if matched is None:
                self.reply(404, {"success": False})
                return
            value = dict(matched)
        elif endpoint == "api/v1/subscribe/popular":
            stype = query.get("stype", ["电影"])[0]
            item = self.media(101 if stype == "电影" else 111, stype)
            item["popularity"] = 420
            value = [item]
        elif endpoint == "api/v1/subscribe/shares":
            value = [{
                "id": 601, "subscribe_id": 702, "share_title": "合成 4K 杜比洗版",
                "share_comment": "仅保留中字与杜比视界高码率版本", "share_user": "社区影迷",
                "share_uid": "uid-601", "name": "合成追剧", "year": "2025", "type": "电视剧",
                "media_source": "themoviedb", "media_id": "111", "season": 1,
                "poster": "https://images.example.test/111/poster.png", "vote": 8.8,
                "quality": "WEB-DL", "resolution": "4k", "effect": "杜比视界",
                "include": "中字", "total_episode": 12, "count": 18,
            }]
        elif endpoint == "api/v1/subscribe/calendar":
            start = query.get("start", ["2026-11-15"])[0]
            value = {
                "items": [{
                    "date": start,
                    "episodes": [{"episode_number": 10, "name": "合成首播集"}],
                    "runtime": 45,
                    "subscribe": {
                        "id": 702, "name": "合成追剧", "season": 1,
                        "poster": "https://images.example.test/111/poster.png",
                        "total_episode": 12, "completed_episode": 9,
                    },
                }],
                "total": 1,
            }
        elif endpoint == "api/v1/dashboard/statistic":
            value = {
                "movie_count": 12, "tv_count": 8, "episode_count": None,
                "music_count": 5, "user_count": 1, "movie_count_month": 2,
                "tv_count_month": 1, "episode_count_month": 4, "music_count_month": 0,
            }
        elif endpoint == "api/v1/dashboard/storage":
            value = {"total_storage": 1_073_741_824, "used_storage": 536_870_912}
        elif endpoint == "api/v1/dashboard/schedule":
            value = [{
                "id": "fixture-library-scan", "name": "合成媒体库扫描", "provider": "MoviePilot",
                "progress_enable": True, "progress": 37.5, "progress_text_i18n": "正在检查",
                "next_run_i18n": "明天 03:00",
            }]
        elif endpoint.startswith("api/v1/tmdb/credits/"):
            value = [self.person(501, "合成主演", "主角"), self.person(502, "合成配角", "配角")]
        elif endpoint.startswith("api/v1/tmdb/recommend/") or endpoint.startswith("api/v1/tmdb/similar/"):
            value = [self.media(102, "电影"), self.media(111, "电视剧")]
        elif re.fullmatch(r"api/v1/tmdb/person/[0-9]{3}", endpoint):
            person_id = int(endpoint.rsplit("/", 1)[-1])
            value = self.person(person_id, "合成主演" if person_id == 501 else f"合成人物 {person_id}", None)
        elif re.fullmatch(r"api/v1/tmdb/person/credits/[0-9]{3}", endpoint):
            value = [self.media(101, "电影"), self.media(111, "电视剧")]
        else:
            item_id = int(endpoint.rsplit("/", 1)[-1])
            media_type = query.get("type_name", [""])[0]
            if query.get("media_source") != ["themoviedb"] or media_type not in {"电影", "电视剧"}:
                self.reply(422, {"success": False})
                return
            value = self.media(item_id, media_type)
        self.reply(200, {"success": True, "message": "", "data": value}, self.resource_headers(name))

    def media_status_endpoint(self, name, body):
        """按当前实例内存订阅集合回传轻量入库与订阅状态，不访问外部服务。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/media/status"] += 1
            mode = profile["mode"]
            subscriptions = set(profile["subscriptions"])
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["discovery"]:
            self.reply(403, {"success": False})
            return
        try:
            items = json.loads(body)
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        results = []
        for item in items:
            media_id = str(item.get("media_id", ""))
            mtype = item.get("mtype")
            seasons = {
                str(season): "normal"
                for (sub_id, season) in subscriptions
                if sub_id == media_id and season is not None
            }
            subscribed = (media_id, None) in subscriptions if mtype == "电影" else bool(seasons)
            results.append({
                "item_id": f"emby-{media_id}" if media_id == "113" else None,
                "server": "Emby" if media_id == "113" else None,
                "subscribed": subscribed,
                "seasons": seasons,
            })
        self.reply(200, {"success": True, "message": "", "data": results}, self.resource_headers(name))

    def subscribe_create_endpoint(self, name, body):
        """单次记录合成订阅，测试确认与错误保留而不产生真实副作用。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/subscribe/"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["subscribe"]:
            self.reply(403, {"success": False})
            return
        if mode == "subscribe-failed":
            self.reply(503, {"success": False})
            return
        try:
            payload = json.loads(body)
            media_id = str(payload["media_id"])
            season = payload.get("season")
        except (KeyError, ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        with self.server.lock:
            self.server.profiles[name]["subscriptions"].add((media_id, season))
        self.reply(200, {"success": True, "message": "", "data": {"id": 9001}})

    def subscribe_update_endpoint(self, name, body):
        """单次更新合成订阅的高级过滤与洗版字段。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["PUT api/v1/subscribe/"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["subscribe"]:
            self.reply(403, {"success": False})
            return
        try:
            payload = json.loads(body)
            sub_id = int(payload["id"])
        except (KeyError, ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        with self.server.lock:
            for item in self.server.profiles[name]["sub_items"]:
                if item["id"] == sub_id:
                    for key, val in payload.items():
                        if key != "id":
                            item[key] = val
        self.reply(200, {"success": True, "message": "", "data": None})

    def subscribe_fork_endpoint(self, name, body):
        """单次响应分享订阅复用请求。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/subscribe/fork"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["subscribe"]:
            self.reply(403, {"success": False})
            return
        try:
            payload = json.loads(body)
            if not isinstance(payload, dict) or not payload.get("name"):
                raise ValueError()
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        self.reply(200, {"success": True, "message": "", "data": {"id": 9002}})

    def subscribe_delete_endpoint(self, name, endpoint):
        """单次移除合成订阅。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"DELETE {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["subscribe"]:
            self.reply(403, {"success": False})
            return
        if mode == "subscribe-failed":
            self.reply(503, {"success": False})
            return
        query = parse_qs(urlsplit(self.path).query)
        media_id = endpoint.rsplit("/", 1)[-1]
        raw_season = query.get("season", [None])[0]
        season = int(raw_season) if raw_season and raw_season.isdigit() else None
        with self.server.lock:
            self.server.profiles[name]["subscriptions"].discard((media_id, season))
        self.reply(200, {"success": True, "message": "", "data": None})

    def subscribe_status_endpoint(self, name, endpoint):
        """单次切换合成订阅暂停或恢复状态。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"PUT {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["subscribe"]:
            self.reply(403, {"success": False})
            return
        sub_id = int(endpoint.rsplit("/", 1)[-1])
        next_state = parse_qs(urlsplit(self.path).query).get("state", ["R"])[0]
        with self.server.lock:
            for item in self.server.profiles[name]["sub_items"]:
                if item["id"] == sub_id:
                    item["state"] = next_state
        self.reply(200, {"success": True, "message": "", "data": None})

    def subscribe_delete_by_id_endpoint(self, name, endpoint):
        """单次按 ID 删除合成订阅。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"DELETE {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["subscribe"]:
            self.reply(403, {"success": False})
            return
        sub_id = int(endpoint.rsplit("/", 1)[-1])
        with self.server.lock:
            self.server.profiles[name]["sub_items"] = [
                item for item in self.server.profiles[name]["sub_items"] if item["id"] != sub_id
            ]
        self.reply(200, {"success": True, "message": "", "data": None})

    def download_delete_endpoint(self, name, endpoint):
        """单次删除合成下载任务。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"DELETE {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a" and not self.permissions(mode)["manage"]:
            self.reply(403, {"success": False})
            return
        task_hash = endpoint.rsplit("/", 1)[-1]
        with self.server.lock:
            self.server.profiles[name]["downloads"] = [
                row for row in self.server.profiles[name]["downloads"] if row["hash"] != task_hash
            ]
        self.reply(200, {"success": True, "message": "", "data": None})

    def download_add_endpoint(self, name, body):
        """单次记录合成添加下载动作，严格校验搜索权限与请求体格式。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/download/add"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["search"]:
            self.reply(403, {"success": False})
            return
        try:
            payload = json.loads(body)
            if not isinstance(payload.get("torrent_in"), dict) or not payload["torrent_in"].get("title"):
                raise ValueError()
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        self.reply(200, {"success": True, "message": "", "data": {"download_id": "syn-dl-9001"}})

    def history_delete_endpoint(self, name, body):
        """单次删除合成整理历史记录。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["DELETE api/v1/history/transfer"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a" and not self.permissions(mode)["manage"]:
            self.reply(403, {"success": False})
            return
        try:
            record_id = int(json.loads(body)["id"])
        except (KeyError, ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        with self.server.lock:
            self.server.profiles[name]["history"] = [
                row for row in self.server.profiles[name]["history"] if row["id"] != record_id
            ]
        self.reply(200, {"success": True, "message": "", "data": None})

    def storage_endpoint(self, name, endpoint, body):
        """受控合成多存储目录列表、建目录与删除操作。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"POST {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a" and not self.permissions(mode)["manage"]:
            self.reply(403, {"success": False})
            return
        try:
            payload = json.loads(body)
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        if endpoint == "api/v1/storage/list":
            path_val = payload.get("path", "/")
            if path_val == "/media/":
                items = [{"storage": payload.get("storage", "local"), "type": "file", "path": "/media/clip.mkv", "name": "clip.mkv", "extension": "mkv", "size": 524_288_000}]
            else:
                with self.server.lock:
                    items = list(self.server.profiles[name]["files"])
            self.reply(200, {"success": True, "message": "", "data": items})
        elif endpoint == "api/v1/storage/mkdir":
            folder = parse_qs(urlsplit(self.path).query).get("name", [""])[0]
            with self.server.lock:
                self.server.profiles[name]["files"].append({
                    "storage": payload.get("storage", "local"), "type": "dir",
                    "path": f"/{folder}/", "name": folder,
                })
            self.reply(200, {"success": True, "message": "", "data": None})
        else:
            target_path = payload.get("path")
            with self.server.lock:
                self.server.profiles[name]["files"] = [
                    item for item in self.server.profiles[name]["files"] if item["path"] != target_path
                ]
            self.reply(200, {"success": True, "message": "", "data": None})

    def workflow_action_endpoint(self, name, endpoint):
        """单次响应工作流运行、启停与重置请求。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"POST {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a" and not self.permissions(mode)["manage"]:
            self.reply(403, {"success": False})
            return
        parts_ep = endpoint.split("/")
        wf_id, action = int(parts_ep[3]), parts_ep[4]
        with self.server.lock:
            for wf in self.server.profiles[name]["workflows"]:
                if wf["id"] == wf_id:
                    if action == "run":
                        wf["run_count"] += 1
                        wf["state"] = "S"
                    elif action == "start":
                        wf["state"] = "W"
                    elif action == "pause":
                        wf["state"] = "P"
                    elif action == "reset":
                        wf["state"] = "W"
                        wf["result"] = None
        self.reply(200, {"success": True, "message": "", "data": None})

    def system_env_update_endpoint(self, name, body):
        """单次更新受控白名单系统设置项，仅管理员可调用。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/system/env"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        try:
            updates = json.loads(body)
            if not isinstance(updates, dict) or not updates:
                raise ValueError()
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        with self.server.lock:
            self.server.profiles[name]["env"].update(updates)
        self.reply(200, {"success": True, "message": "", "data": None})

    def user_config_update_endpoint(self, name, endpoint, body):
        """单次持久化当前用户的界面模块编排配置。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"POST {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        try:
            payload = json.loads(body) if body else None
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        cfg_key = endpoint.rsplit("/", 1)[-1]
        with self.server.lock:
            self.server.profiles[name]["user_configs"][cfg_key] = payload
        self.reply(200, {"success": True, "message": "", "data": None})

    def plugin_list_endpoint(self, name):
        """按管理员权限返回插件市场或已安装原始数组载荷。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/plugin/"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        state = parse_qs(urlsplit(self.path).query).get("state", ["installed"])[0]
        with self.server.lock:
            rows = list(
                self.server.profiles[name]["market_plugins"]
                if state == "market"
                else self.server.profiles[name]["installed_plugins"]
            )
        self.reply(200, {"success": True, "message": "", "data": rows})

    def plugin_action_endpoint(self, name, endpoint):
        """单次响应管理员插件安装或重置请求。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"GET {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        parts_ep = endpoint.split("/")
        action, plugin_id = parts_ep[3], parts_ep[4]
        if action == "install":
            with self.server.lock:
                for row in self.server.profiles[name]["market_plugins"]:
                    if row["id"] == plugin_id:
                        row["installed"] = True
                        row["has_update"] = False
        self.reply(200, {"success": True, "message": "", "data": {"restart_required": False}})

    def plugin_delete_endpoint(self, name, endpoint):
        """单次响应管理员卸载插件请求。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"DELETE {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        plugin_id = endpoint.rsplit("/", 1)[-1]
        with self.server.lock:
            self.server.profiles[name]["installed_plugins"] = [
                row for row in self.server.profiles[name]["installed_plugins"] if row["id"] != plugin_id
            ]
        self.reply(200, {"success": True, "message": "", "data": None})

    def plugin_page_endpoint(self, name, endpoint):
        """返回插件原生 Vuetify JSON 页面或 Vue 远程组件声明。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"GET {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        plugin_id = endpoint.rsplit("/", 1)[-1]
        if plugin_id == "VueCompatDemo":
            self.reply(200, {"success": True, "message": "", "data": {"render_mode": "vue", "page": []}})
            return
        page = [
            {
                "component": "VRow",
                "content": [
                    {
                        "component": "VAlert",
                        "props": {"type": "success"},
                        "text": "合成插件运行正常，今日已整理 12 项资源。",
                    },
                    {
                        "component": "VApexChart",
                        "props": {
                            "options": {
                                "chart": {"type": "pie"},
                                "title": {"text": "今日站点上传占比 (GB)"},
                                "labels": ["合成站 A", "合成站 B", "合成站 C"],
                            },
                            "series": [42.5, 28.0, 14.5],
                        },
                    },
                    {
                        "component": "VTable",
                        "content": [
                            {
                                "component": "thead",
                                "content": [
                                    {
                                        "component": "tr",
                                        "content": [
                                            {"component": "th", "text": "站点"},
                                            {"component": "th", "text": "状态"},
                                            {"component": "th", "text": "今日上传"},
                                        ],
                                    }
                                ],
                            },
                            {
                                "component": "tbody",
                                "content": [
                                    {
                                        "component": "tr",
                                        "content": [
                                            {"component": "td", "text": "合成站 A"},
                                            {"component": "td", "text": "正常"},
                                            {"component": "td", "text": "42.5 GB"},
                                        ],
                                    },
                                    {
                                        "component": "tr",
                                        "content": [
                                            {"component": "td", "text": "合成站 B"},
                                            {"component": "td", "text": "正常"},
                                            {"component": "td", "text": "28.0 GB"},
                                        ],
                                    },
                                ],
                            },
                        ],
                    },
                ],
            }
        ]
        self.reply(200, {"success": True, "message": "", "data": {"render_mode": "vuetify", "page": page}})

    def plugin_dashboard_meta_endpoint(self, name):
        """返回插件仪表板元信息清单。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/plugin/dashboard/meta"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        self.reply(
            200,
            {
                "success": True,
                "message": "",
                "data": [{"id": "DemoPlugin", "name": "合成插件统计", "key": ""}],
            },
        )

    def plugin_dashboard_endpoint(self, name, endpoint):
        """返回原生 Vuetify 图表格式的插件仪表板卡片。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"GET {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        self.reply(
            200,
            {
                "success": True,
                "message": "",
                "data": {
                    "id": "DemoPlugin",
                    "name": "合成插件统计",
                    "key": "",
                    "render_mode": "vuetify",
                    "elements": [
                        {
                            "component": "VApexChart",
                            "props": {
                                "options": {
                                    "chart": {"type": "donut"},
                                    "title": {"text": "近 7 日任务分布"},
                                    "labels": ["自动整理", "站点签到", "字幕刮削"],
                                },
                                "series": [18, 12, 6],
                            },
                        }
                    ],
                },
            },
        )

    def agent_stream_endpoint(self, name, body):
        """返回标准 text/event-stream SSE 合成回复帧，包含工具调用与文本增量。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/agent/stream"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        try:
            payload = json.loads(body)
            sid = payload.get("session_id") or "sess-live"
            text = payload.get("text") or ""
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        frames = [
            f'data: {json.dumps({"type": "tool", "message": "已检索本地媒体库与订阅", "session_id": sid}, ensure_ascii=False)}\n\n',
            f'data: {json.dumps({"type": "delta", "delta": f"已收到「{text}」，", "session_id": sid}, ensure_ascii=False)}\n\n',
            f'data: {json.dumps({"type": "delta", "delta": "推荐观看《合成电影 101》。", "session_id": sid}, ensure_ascii=False)}\n\n',
            "data: [DONE]\n\n",
        ]
        raw = "".join(frames).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def agent_stop_endpoint(self, name, endpoint):
        """单次响应停止 Agent 任务请求。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"POST {endpoint}"] += 1
        self.reply(200, {"success": True, "message": "已停止", "data": {"stopped": True}})

    def agent_session_delete_endpoint(self, name, endpoint):
        """单次删除指定 Agent 历史会话。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"DELETE {endpoint}"] += 1
        sid = endpoint.rsplit("/", 1)[-1]
        with self.server.lock:
            self.server.profiles[name]["agent_sessions"] = [
                row for row in self.server.profiles[name]["agent_sessions"] if row["session_id"] != sid
            ]
        self.reply(200, {"success": True, "message": "", "data": None})

    @staticmethod
    def resource_token(name):
        """构造仅供夹具验证的独立资源令牌，与生产 JWT 和主登录令牌无关。"""
        claims = json.dumps({"purpose": "resource", "exp": 4_102_444_800, "sub": name}).encode()
        return "fixture." + base64.urlsafe_b64encode(claims).decode().rstrip("=") + ".synthetic"

    def resource_headers(self, name):
        """模拟当前后端在带主令牌请求上签发短效同源 HttpOnly Cookie。"""
        return {"Set-Cookie": f"MoviePilot={self.resource_token(name)}; Path=/; HttpOnly; SameSite=Lax"}

    def image_endpoint(self, name):
        """仅接受同一实例的资源 Cookie，并确认客户端没有转发主令牌。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/system/img/0"] += 1
            mode = profile["mode"]
        query = parse_qs(urlsplit(self.path).query)
        reference = query.get("imgurl", [""])[0]
        if (
            mode == "expired" or self.headers.get("Authorization") is not None
            or self.headers.get("Cookie") != f"MoviePilot={self.resource_token(name)}"
        ):
            with self.server.lock:
                profile["counts"]["image-auth-rejected"] += 1
            self.reply(401, {"success": False})
        elif not re.fullmatch(
            r"https://images\.example\.test/(?:1[0-9]{2}|5[0-9]{2})/(?:poster|backdrop)\.png",
            reference,
        ):
            self.reply(400, {"success": False})
        else:
            with self.server.lock:
                profile["counts"]["image-served"] += 1
            self.reply_image(reference)

    @staticmethod
    def media(item_id, media_type):
        """提供显式标记的合成记录，编号区分搜索、发现与详情请求。"""
        base = {
            "media_source": "themoviedb", "media_id": str(item_id), "tmdb_id": item_id,
            "type": media_type, "title": f"合成{media_type} {item_id}", "year": "2025",
            "release_date": "2025-07-15",
            "tagline": "跨越边界的原生体验",
            "runtime": 124 if media_type == "电影" else None,
            "number_of_seasons": 2 if media_type == "电视剧" else None,
            "genres": [{"name": "科幻"}, {"name": "冒险"}],
            "directors": [{"id": 503, "name": "合成导演", "source": "themoviedb"}],
            "poster_path": f"https://images.example.test/{item_id}/poster.png",
            "backdrop_path": f"https://images.example.test/{item_id}/backdrop.png",
            "overview": "本条记录用于验证原生客户端的检索与详情直连。", "vote_average": 8.3,
        }
        if media_type == "电视剧":
            base["season_info"] = [
                {
                    "season_number": 1, "name": "第 1 季", "air_date": "2024-01-10",
                    "episode_count": 12, "overview": "第一季合成简介。",
                    "poster_path": f"https://images.example.test/{item_id}/poster.png",
                },
                {
                    "season_number": 2, "name": "第 2 季", "air_date": "2025-03-18",
                    "episode_count": 10, "overview": "第二季合成简介。",
                    "poster_path": f"https://images.example.test/{item_id}/poster.png",
                },
            ]
        return base

    @staticmethod
    def person(person_id, name, character):
        """提供合成演职员与人物资料，用于验证原生演职员横栏与人物详情跳钻。"""
        return {
            "source": "themoviedb", "id": person_id, "name": name, "character": character,
            "known_for_department": "Acting", "birthday": "1985-06-12",
            "place_of_birth": "上海",
            "biography": "用于验证原生人物详情页与参演作品网格的合成简介。",
            "profile_path": f"https://images.example.test/{person_id}/poster.png",
        }

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
                "super_user": name == "a", "permissions": self.permissions(mode),
            })

    def current(self, name, mode):
        """严格匹配当前实例令牌；其它实例的令牌即使格式合法也拒绝。"""
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
        else:
            self.reply(200, {"success": True, "data": {
                "id": 10 if name == "a" else 20, "name": f"native-{name}",
                "is_superuser": name == "a", "is_active": True,
                "permissions": self.permissions(mode),
            }})

    @staticmethod
    def permissions(mode):
        """刻意把影视发现和 PT 资源权限分开，验证客户端沿用各自的门禁。"""
        permissions = {
            "discovery": True,
            "search": True,
            "subscribe": True,
            "manage": False,
        }
        if mode == "resource-search-only":
            permissions["discovery"] = False
        elif mode == "discovery-only":
            permissions["search"] = False
        return permissions


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
