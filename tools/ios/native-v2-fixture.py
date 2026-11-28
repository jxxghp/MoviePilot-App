#!/usr/bin/env python3
"""仅提供回环 API 的原生入口夹具；不提供前端、脚本或真实账号数据。"""

import argparse
import base64
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import struct
import threading
import time
import zlib
from urllib.parse import parse_qs, unquote, urlencode, urlsplit


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
                        "timer": "*/15 * * * *", "trigger_type": "timer", "state": "P", "run_count": 2, "result": None,
                        "actions": [
                            {
                                "id": "act-scan", "type": "ScanFileAction", "name": "扫描下载目录",
                                "description": "扫描新增媒体文件", "position": {"x": 24, "y": 24},
                                "data": {"source": "/downloads", "loop": False}, "timeout": 60,
                            },
                            {
                                "id": "act-transfer", "type": "TransferFileAction", "name": "自动整理入库",
                                "description": "按分类转移至媒体库", "position": {"x": 24, "y": 156},
                                "data": {"source": "/downloads", "target": "/video"}, "timeout": 120,
                            },
                        ],
                        "flows": [
                            {"id": "flow-1", "source": "act-scan", "target": "act-transfer", "animated": True}
                        ],
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
                        "is_active": True, "is_superuser": False, "is_otp": True,
                        "avatar": "synthetic-avatar", "settings": {"theme": "dark"},
                        "permissions": {"discovery": True, "search": True, "subscribe": True, "manage": False,
                                        "features": {"plugin.demo.main": False}},
                    },
                ],
                "user_configs": {},
                "mediaserver_bindings": {},
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

    def do_HEAD(self):
        """处理媒体流预检与 Range 探测。"""
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
                    "partial-discovery-failed", "subscribe-failed", "mediaserver",
                    "logs-empty", "logs-failed",
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
                            "timer": "*/15 * * * *", "trigger_type": "timer", "state": "P", "run_count": 2, "result": None,
                            "actions": [
                                {
                                    "id": "act-scan", "type": "ScanFileAction", "name": "扫描下载目录",
                                    "description": "扫描新增媒体文件", "position": {"x": 24, "y": 24},
                                    "data": {"source": "/downloads", "loop": False}, "timeout": 60,
                                },
                                {
                                    "id": "act-transfer", "type": "TransferFileAction", "name": "自动整理入库",
                                    "description": "按分类转移至媒体库", "position": {"x": 24, "y": 156},
                                    "data": {"source": "/downloads", "target": "/video"}, "timeout": 120,
                                },
                            ],
                            "flows": [
                                {"id": "flow-1", "source": "act-scan", "target": "act-transfer", "animated": True}
                            ],
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
                    profile["mediaserver_bindings"] = {}
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
        if name in self.server.profiles and self.command in {"GET", "HEAD"}:
            if endpoint == "api/v1/mediaserver/stream":
                self.mediaserver_stream_endpoint(name)
                return
            if self.command == "GET" and endpoint == "api/v1/mediaserver/stream-info":
                self.mediaserver_stream_info_endpoint(name)
                return
        if name in self.server.profiles and self.command == "GET":
            if (
                endpoint in self.business_endpoints()
                or path in {
                    f"/{name}/api/v1/download/",
                    f"/{name}/api/v1/subscribe/",
                    f"/{name}/api/v1/site/",
                    f"/{name}/api/v1/workflow/",
                    f"/{name}/api/v1/user/",
                    f"/{name}/api/v1/authorization/",
                }
                or re.fullmatch(r"api/v1/download/(?:start|stop)/[a-z0-9]+", endpoint)
                or re.fullmatch(r"api/v1/site/(?:test|icon)/[0-9]+", endpoint)
                or re.fullmatch(r"api/v1/search/media/1[0-9]{2}", endpoint)
                or re.fullmatch(r"api/v1/media/(?:[0-9]+|tt[0-9]+)", endpoint)
                or re.fullmatch(r"api/v1/tmdb/(?:credits|recommend|similar)/[0-9]+/(?:电影|电视剧)", endpoint)
                or re.fullmatch(r"api/v1/tmdb/person(?:/credits)?/[0-9]{3}", endpoint)
                or re.fullmatch(r"api/v1/user/config/[A-Za-z0-9_.-]+", endpoint)
                or re.fullmatch(r"api/v1/subscribe/[0-9]+", endpoint)
                or re.fullmatch(r"api/v1/subscribe/media/[A-Za-z0-9_-]+", endpoint)
                or re.fullmatch(r"api/v1/music/album/[A-Za-z0-9_-]+", endpoint)
                or re.fullmatch(r"api/v1/music/artist/[A-Za-z0-9_-]+(?:/albums)?", endpoint)
                or re.fullmatch(r"api/v1/message/agent/sessions/[A-Za-z0-9_-]+", endpoint)
            ):
                self.business_endpoint(name, endpoint)
                return
            if path == f"/{name}/api/v1/plugin/":
                self.plugin_list_endpoint(name)
                return
            if endpoint in {"api/v1/plugin/statistic", "api/v1/plugin/rating"}:
                self.plugin_stats_endpoint(name, endpoint)
                return
            if endpoint == "api/v1/site/userdata/latest":
                self.site_userdata_endpoint(name)
                return
            if endpoint == "api/v1/plugin/dashboard/meta":
                self.plugin_dashboard_meta_endpoint(name)
                return
            if re.fullmatch(r"api/v1/plugin/dashboard/[A-Za-z][A-Za-z0-9_]*(?:/[A-Za-z0-9_-]+)?", endpoint):
                self.plugin_dashboard_endpoint(name, endpoint)
                return
            if endpoint == "api/v1/plugin/remotes":
                self.plugin_remotes_endpoint(name)
                return
            if endpoint == "api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js":
                self.plugin_remote_entry_js_endpoint(name)
                return
            if endpoint == "api/v1/plugin/VueCompatDemo/status":
                self.plugin_vue_demo_status_endpoint(name)
                return
            if re.fullmatch(r"api/v1/plugin/page/[A-Za-z][A-Za-z0-9_]*", endpoint):
                self.plugin_page_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/plugin/(?:install|reset)/[A-Za-z][A-Za-z0-9_]*", endpoint):
                self.plugin_action_endpoint(name, endpoint)
                return
            if endpoint in {"api/v1/workflow/actions", "api/v1/workflow/shares"} or re.fullmatch(r"api/v1/workflow/[0-9]+", endpoint):
                self.workflow_read_endpoint(name, endpoint)
                return
            if endpoint == "api/v1/system/logging":
                self.logging_endpoint(name)
                return
            if endpoint == "api/v1/system/global":
                self.system_global_endpoint(name)
                return
            if endpoint in {
                "api/v1/system/nettest/targets", "api/v1/system/nettest",
                "api/v1/system/modulelist", "api/v1/system/ruletest",
                "api/v1/system/runscheduler",
                "api/v1/system/global/user",
                "api/v1/media/recognize",
            } or re.fullmatch(r"api/v1/system/(?:setting|moduletest)/[A-Za-z0-9_]+", endpoint):
                self.system_setting_read_endpoint(name, endpoint)
                return
            if endpoint in {"api/v1/system/img/0", "api/v1/system/img/1", "api/v1/system/cache/image"}:
                self.image_endpoint(name, endpoint)
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
            if endpoint == "api/v1/workflow/fork":
                self.workflow_fork_endpoint(name, body)
                return
            if endpoint == "api/v1/system/env":
                self.system_env_update_endpoint(name, body)
                return
            if re.fullmatch(r"api/v1/system/setting/[A-Za-z0-9_]+", endpoint):
                self.system_setting_update_endpoint(name, endpoint, body)
                return
            if path == f"/{name}/api/v1/user/":
                self.user_mutate_endpoint(name, "POST", body)
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
            if endpoint == "api/v1/message/agent/stream":
                self.agent_stream_endpoint(name, body)
                return
            if endpoint == "api/v1/mediaserver/progress":
                with self.server.lock:
                    self.server.profiles[name]["counts"]["POST api/v1/mediaserver/progress"] += 1
                self.reply(200, {"success": True, "message": "", "data": {"reported": True}})
                return
            if endpoint == "api/v1/mediaserver/account-bindings":
                self.mediaserver_account_bind_endpoint(name, body)
                return
            if endpoint == "api/v1/notification/app":
                with self.server.lock:
                    self.server.profiles[name]["counts"]["POST api/v1/notification/app"] += 1
                self.reply(200, {
                    "success": True, "message": "",
                    "data": {
                        "owner": "0123456789abcdef0123456789abcdef",
                        "devices": [],
                    },
                })
                return
            if re.fullmatch(r"api/v1/message/agent/sessions/[A-Za-z0-9_-]+/stop", endpoint):
                self.agent_stop_endpoint(name, endpoint)
                return
        if name in self.server.profiles and self.command == "PUT":
            if re.fullmatch(r"api/v1/message/agent/sessions/[A-Za-z0-9_-]+/display", endpoint):
                self.agent_display_endpoint(name, endpoint, body)
                return
            if path == f"/{name}/api/v1/subscribe/":
                self.subscribe_update_endpoint(name, body)
                return
            if re.fullmatch(r"api/v1/subscribe/status/[0-9]+", endpoint):
                self.subscribe_status_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/workflow/[0-9]+", endpoint):
                self.workflow_update_endpoint(name, endpoint, body)
                return
            if path == f"/{name}/api/v1/user/":
                self.user_mutate_endpoint(name, "PUT", body)
                return
        if name in self.server.profiles and self.command == "DELETE":
            if endpoint == "api/v1/history/transfer":
                self.history_delete_endpoint(name, body)
                return
            if endpoint == "api/v1/transfer/queue":
                with self.server.lock:
                    self.server.profiles[name]["counts"]["DELETE api/v1/transfer/queue"] += 1
                self.reply(200, {"success": True, "message": "", "data": None})
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
            if re.fullmatch(r"api/v1/message/agent/sessions/[A-Za-z0-9_-]+", endpoint):
                self.agent_session_delete_endpoint(name, endpoint)
                return
            if re.fullmatch(r"api/v1/mediaserver/account-bindings/[^/]+", endpoint):
                self.mediaserver_account_unbind_endpoint(name, endpoint)
                return
        allowed = {
            ("GET", "api/v1/login/initialization"),
            ("POST", "api/v1/login/initialization"),
            ("POST", "api/v1/login/access-token"),
            ("GET", "api/v1/user/current"),
            ("GET", "api/v1/auth/providers"),
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
        elif endpoint == "api/v1/auth/providers":
            self.reply(
                200,
                {
                    "success": True,
                    "message": "",
                    "data": [
                        {
                            "id": "system:passkey",
                            "type": "system",
                            "method": "passkey",
                            "enabled": True,
                        }
                    ],
                },
            )
        else:
            self.current(name, mode)

    @staticmethod
    def business_endpoints():
        """列出 smoke 验收允许的媒体、来源与管理员仪表盘只读端点。"""
        return {
            "api/v1/discover/source",
            "api/v1/recommend/source",
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
            "api/v1/mediaserver/browse",
            "api/v1/mediaserver/filters",
            "api/v1/mediaserver/detail",
            "api/v1/mediaserver/seasons",
            "api/v1/mediaserver/season-episodes",
            "api/v1/mediaserver/search",
            "api/v1/mediaserver/account-bindings",
            "api/v1/danmaku/config",
            "api/v1/media/search",
            "api/v1/media/source",
            "api/v1/rule/groups",
            "api/v1/download/clients",
            "api/v1/download/paths",
            "api/v1/search/last",
            "api/v1/search/title",
            "api/v1/history/transfer",
            "api/v1/transfer/queue",
            "api/v1/widget/context",
            "api/v1/message/web",
            "api/v1/storage/options",
            "api/v1/system/env",
            "api/v1/subscribe/calendar",
            "api/v1/subscribe/popular",
            "api/v1/subscribe/shares",
            "api/v1/message/agent/commands",
            "api/v1/message/agent/sessions",
            "api/v1/dashboard/cpu",
            "api/v1/dashboard/network",
            "api/v1/dashboard/memory",
            "api/v1/dashboard/downloader",
            "api/v1/dashboard/system",
            "api/v1/dashboard/transfer",
            "api/v1/github/community",
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
            or (
                endpoint.startswith("api/v1/mediaserver/")
                and endpoint != "api/v1/mediaserver/account-bindings"
            )
            or endpoint.startswith("api/v1/tmdb/")
            or endpoint.startswith("api/v1/music/")
            or endpoint == "api/v1/media/search"
            or re.fullmatch(r"api/v1/media/(?:[0-9]+|tt[0-9]+)", endpoint)
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
        if endpoint == "api/v1/recommend/source":
            value = []
        elif endpoint in {"api/v1/discover/tmdb_movies", "api/v1/discover/tmdb_tvs"}:
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
        elif endpoint == "api/v1/message/agent/commands":
            value = [
                {"command": "/search", "description": "搜索影视资源"},
                {"command": "/subscribe", "description": "查看订阅列表"},
            ]
        elif endpoint == "api/v1/message/agent/sessions":
            with self.server.lock:
                value = [
                    {k: v for k, v in row.items() if k != "messages"}
                    for row in self.server.profiles[name]["agent_sessions"]
                ]
        elif re.fullmatch(r"api/v1/message/agent/sessions/[A-Za-z0-9_-]+", endpoint):
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
            "api/v1/authorization",
        }:
            value = []
        elif endpoint == "api/v1/danmaku/config":
            value = {"enabled": False, "sources": []}
        elif re.fullmatch(r"api/v1/subscribe/media/[A-Za-z0-9_-]+", endpoint):
            value = None
        elif endpoint == "api/v1/mediaserver/account-bindings":
            value = self.list_mediaserver_account_bindings(name)
        elif endpoint.startswith("api/v1/mediaserver/"):
            value = self.mediaserver_fixture(endpoint, query, mode)
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
        elif endpoint == "api/v1/rule/groups":
            value = {"rule_groups": [{"name": "4K 优先", "rule_string": "", "media_type": "电影"}]}
        elif endpoint == "api/v1/download/clients":
            value = [{"name": "Qbittorrent", "type": "qbittorrent"}]
        elif endpoint == "api/v1/download/paths":
            value = [{"name": "电影库", "save_path": "local:/downloads/movies", "download_path": "/downloads/movies"}]
        elif endpoint == "api/v1/site":
            value = [{"id": 3, "name": "合成站", "domain": "syn.example.test", "is_active": True, "pri": 1}]
        elif re.fullmatch(r"api/v1/site/test/[0-9]+", endpoint):
            value = None
        elif re.fullmatch(r"api/v1/site/icon/[0-9]+", endpoint):
            value = {
                "icon": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
            }
        elif endpoint == "api/v1/history/transfer":
            with self.server.lock:
                rows = list(self.server.profiles[name]["history"])
            value = {"list": rows, "total": len(rows)}
        elif endpoint == "api/v1/transfer/queue":
            value = [
                {
                    "media": {"title": "合成待整理剧集", "title_year": "合成待整理剧集 (2026)"},
                    "season": 1,
                    "tasks": [
                        {
                            "fileitem": {
                                "storage": "local", "type": "file",
                                "path": "/downloads/tv/ep01.mkv", "name": "ep01.mkv",
                            },
                            "state": "waiting",
                        }
                    ],
                }
            ]
        elif endpoint == "api/v1/widget/context":
            value = {
                "version": 1,
                "owner": "0123456789abcdef0123456789abcdef",
                "availableContents": ["overview", "downloads", "imports", "subscriptions"],
            }
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
            if not query.get("start") or not query.get("end"):
                self.reply(422, {"detail": "start/end required"})
                return
            start = query["start"][0]
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
        elif endpoint == "api/v1/dashboard/cpu":
            value = 23.5
        elif endpoint == "api/v1/dashboard/network":
            value = [1024.0, 2048.0]
        elif endpoint == "api/v1/dashboard/memory":
            value = {"total": 8_589_934_592, "used": 4_294_967_296, "cached": 0, "available": 4_294_967_296}
        elif endpoint == "api/v1/dashboard/downloader":
            value = {"download_speed": 1024, "upload_speed": 512, "download_size": 4096, "upload_size": 8192, "free_space": 1_073_741_824}
        elif endpoint == "api/v1/dashboard/system":
            value = {"hostname": "synthetic", "operating_system": "Fixture", "runtime": 600, "version": "v3-synthetic"}
        elif endpoint == "api/v1/dashboard/transfer":
            value = [1, 2, 0, 3, 1, 4, 2]
        elif endpoint == "api/v1/github/community":
            value = {"login": "synthetic", "medals": []}
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
            raw_id = endpoint.rsplit("/", 1)[-1]
            media_src = query.get("media_source", [""])[0]
            media_type = query.get("type_name", [""])[0]
            if media_src not in {"themoviedb", "imdb", "douban", "bangumi"} or media_type not in {"电影", "电视剧"}:
                self.reply(422, {"success": False})
                return
            digits = "".join(ch for ch in raw_id if ch.isdigit()) or "101"
            item_id = int(digits[-3:]) if len(digits) > 3 else int(digits)
            value = self.media(item_id, media_type, media_source=media_src, raw_id=raw_id)
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

    def workflow_read_endpoint(self, name, endpoint):
        """返回工作流详情（含 actions/flows）、动作目录或社区分享列表。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"GET {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a" and not self.permissions(mode)["manage"]:
            self.reply(403, {"success": False})
            return
        if endpoint == "api/v1/workflow/actions":
            catalog = [
                {
                    "type": "ScanFileAction",
                    "name": "扫描目录",
                    "description": "扫描指定目录并输出媒体文件列表",
                    "data": {"source": "/downloads", "loop": False},
                },
                {
                    "type": "TransferFileAction",
                    "name": "整理文件",
                    "description": "识别并整理文件至目标媒体库",
                    "data": {"source": "/downloads", "target": "/video"},
                },
                {
                    "type": "SendMessageAction",
                    "name": "发送通知",
                    "description": "将执行结果推送至消息渠道",
                    "data": {"title": "工作流完成", "channel": "default"},
                },
            ]
            self.reply(200, {"success": True, "message": "", "data": catalog})
            return
        if endpoint == "api/v1/workflow/shares":
            shares = [
                {
                    "id": 901,
                    "share_title": "每日热门榜单自动订阅",
                    "share_comment": "定时抓取热门榜单并按评分过滤自动加入订阅",
                    "share_user": "MoviePilot",
                    "name": "每日热门榜单自动订阅",
                    "description": "定时抓取热门榜单",
                    "timer": "0 8 * * *",
                    "trigger_type": "timer",
                    "actions": "[]",
                    "flows": "[]",
                    "count": 128,
                }
            ]
            self.reply(200, {"success": True, "message": "", "data": shares})
            return
        wf_id = int(endpoint.rsplit("/", 1)[-1])
        with self.server.lock:
            match = next((wf for wf in self.server.profiles[name]["workflows"] if wf["id"] == wf_id), None)
        if not match:
            self.reply(404, {"success": False})
            return
        self.reply(200, {"success": True, "message": "", "data": match})

    def workflow_update_endpoint(self, name, endpoint, body):
        """单次保存画布编辑后的工作流节点与连线。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"PUT {endpoint}"] += 1
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
        wf_id = int(endpoint.rsplit("/", 1)[-1])
        with self.server.lock:
            for wf in self.server.profiles[name]["workflows"]:
                if wf["id"] == wf_id:
                    wf["actions"] = payload.get("actions", wf.get("actions", []))
                    wf["flows"] = payload.get("flows", wf.get("flows", []))
        self.reply(200, {"success": True, "message": "", "data": None})

    def workflow_fork_endpoint(self, name, body):
        """单次复用社区工作流分享至本地清单。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/workflow/fork"] += 1
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
        with self.server.lock:
            self.server.profiles[name]["workflows"].append({
                "id": 32,
                "name": payload.get("share_title") or payload.get("name") or "复用工作流",
                "description": payload.get("share_comment") or "",
                "timer": payload.get("timer") or "0 8 * * *",
                "trigger_type": "timer",
                "state": "W",
                "run_count": 0,
                "result": None,
                "actions": [],
                "flows": [],
            })
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

    def system_setting_read_endpoint(self, name, endpoint):
        """按管理员权限返回八类专项系统设置与网络连通性测试结果。"""
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
        if endpoint == "api/v1/system/nettest/targets":
            targets = [
                {"id": "tmdb", "name": "TMDB API", "address": "api.themoviedb.org"},
                {"id": "github", "name": "GitHub", "address": "github.com"},
            ]
            self.reply(200, {"success": True, "message": "", "data": targets})
            return
        if endpoint == "api/v1/system/nettest":
            self.reply(200, {"success": True, "message": "", "data": {"time": 42.0}})
            return
        if endpoint == "api/v1/system/modulelist":
            self.reply(200, {
                "success": True, "message": "",
                "data": {"modules": [
                    {"id": "TheMovieDbModule", "name": "TMDB 元数据", "name_i18n": "TMDB 元数据"},
                    {"id": "QbittorrentModule", "name": "Qbittorrent 下载器", "name_i18n": "Qbittorrent 下载器"},
                ]},
            })
            return
        if endpoint.startswith("api/v1/system/moduletest/"):
            self.reply(200, {"success": True, "message": "", "data": None})
            return
        if endpoint == "api/v1/media/recognize":
            self.reply(200, {
                "success": True, "message": "",
                "data": {
                    "meta_info": {
                        "name": "黑客帝国", "type": "电影", "resource_pix": "2160p",
                        "edition": "BluRay", "resource_team": "SYN",
                    },
                    "media_info": {
                        "title": "黑客帝国", "title_year": "黑客帝国 (1999)",
                        "type": "电影", "overview": "合成名称识别测试返回结果。",
                    },
                },
            })
            return
        if endpoint == "api/v1/system/ruletest":
            self.reply(200, {
                "success": True, "message": "",
                "data": {
                    "matched": True, "priority": 98, "rulegroup_name": "4K 优先",
                    "meta_info": {"name": "黑客帝国", "resource_pix": "2160p", "resource_team": "SYN"},
                    "media_info": {"title": "黑客帝国", "title_year": "黑客帝国 (1999)", "type": "电影"},
                },
            })
            return
        if endpoint == "api/v1/system/runscheduler":
            self.reply(200, {"success": True, "message": "", "data": None})
            return
        if endpoint == "api/v1/system/global/user":
            self.reply(200, {"success": True, "message": "", "data": {}})
            return
        key = endpoint.rsplit("/", 1)[-1]
        defaults = {
            "Directories": [
                {
                    "name": "默认电影目录", "storage": "local", "download_path": "/downloads/movies",
                    "library_path": "/media/movies", "media_type": "电影", "media_category": "院线",
                    "transfer_type": "link", "monitor_type": "downloader",
                }
            ],
            "Storages": [{"name": "本地存储", "type": "local"}],
            "Downloaders": [{"name": "Qbittorrent", "type": "qbittorrent", "enabled": True, "default": True}],
            "MediaServers": [{"name": "Emby 主库", "type": "emby", "enabled": True, "default": True}],
            "Notifications": [{"name": "合成推送", "type": "wechat", "enabled": True, "switchs": ["整理入库", "订阅通知"]}],
            "UserFilterRuleGroups": [{"name": "4K 优先", "media_type": "电影", "rule_string": "4K > 1080P"}],
            "CustomIdentifiers": ["合成剧集 => 合成追剧"],
            "ScrapingSwitchs": {"movie_nfo": True, "movie_poster": True, "tv_nfo": True},
            "IndexerSites": [3],
            "RssSites": [3],
        }
        self.reply(200, {"success": True, "message": "", "data": {"value": defaults.get(key)}})

    def system_setting_update_endpoint(self, name, endpoint, body):
        """单次保存管理员专项系统配置项。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"POST {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        try:
            json.loads(body)
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        self.reply(200, {"success": True, "message": "", "data": None})

    def user_mutate_endpoint(self, name, method, body):
        """单次创建或更新非敏感用户资料与权限配置。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"{method} api/v1/user/"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a":
            self.reply(403, {"success": False})
            return
        try:
            payload = json.loads(body)
        except (ValueError, TypeError):
            self.reply(422, {"success": False})
            return
        with self.server.lock:
            users = self.server.profiles[name]["users"]
            if method == "POST":
                users.append({
                    "id": 30, "name": payload.get("name", "new-user"),
                    "email": payload.get("email"),
                    "is_active": bool(payload.get("is_active", True)),
                    "is_superuser": bool(payload.get("is_superuser", False)),
                    "is_otp": False,
                    "permissions": payload.get("permissions") or {},
                })
            else:
                uid = payload.get("id")
                for row in users:
                    if row["id"] == uid:
                        row["email"] = payload.get("email")
                        row["is_active"] = bool(payload.get("is_active", True))
                        row["is_otp"] = bool(payload.get("is_otp", False))
                        row["avatar"] = payload.get("avatar")
                        row["settings"] = payload.get("settings") or {}
                        row["permissions"] = payload.get("permissions") or {}
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

    def logging_endpoint(self, name):
        """还原资源 Cookie、管理员、倒序快照与正数 length 持续 SSE 的真实日志协议。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/system/logging"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Cookie") != f"MoviePilot={self.resource_token(name)}":
            return self.reply(401, {"detail": "Not authenticated"})
        if name != "a":
            return self.reply(403, {"detail": "用户权限不足"})
        query = parse_qs(urlsplit(self.path).query)
        logfile = query.get("logfile", ["moviepilot.log"])[0]
        if logfile not in {"moviepilot.log", "plugins/demoplugin.log"}:
            return self.reply(404, {"detail": "Not Found"})
        if mode == "logs-failed":
            return self.reply(503, {"detail": "合成日志服务暂不可用"})
        title = "合成插件日志" if logfile.startswith("plugins/") else "合成系统日志"
        lines = [] if mode == "logs-empty" else [
            f"INFO 2026-11-21 09:50:01 {title} {number:03d}"
            for number in range(450, 0, -1)
        ]
        if lines and logfile.startswith("plugins/"):
            lines[:4] = [
                "INFO:     [MoviePilot] 2026-11-21 09:50:01,123 [-] demoplugin.py - 合成插件日志 450",
                "【WARNING】2026-11-21 09:50:01,123 demoplugin.py - 合成插件日志 449",
                "2026-11-21 09:50:01,123 [ERROR] [-] - demoplugin.py - 合成插件日志 448",
                "[DEBUG] 2026-11-21 09:50:01,123 [-] - demoplugin.py - 合成插件日志 447",
            ]
        if query.get("length") == ["-1"]:
            with self.server.lock:
                profile["counts"]["log-snapshot"] += 1
            raw = ("\n" + "\n\n".join(lines) if lines else "").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)
            return
        with self.server.lock:
            profile["counts"]["log-stream"] += 1
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            for line in lines[:50][::-1]:
                self.wfile.write(f"data: {line}\n\n".encode())
            while True:
                self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
                time.sleep(0.5)
        except OSError:
            pass  # 客户端主动取消流后结束本连接，不污染测试输出。

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

    def plugin_stats_endpoint(self, name, endpoint):
        """返回插件安装统计或评分映射，供插件卡片展示下载量与评分。"""
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
        if endpoint == "api/v1/plugin/statistic":
            self.reply(200, {"success": True, "message": "", "data": {"AutoSignIn": 3200, "DemoPlugin": 120}})
        else:
            self.reply(
                200,
                {
                    "success": True,
                    "message": "",
                    "data": {
                        "AutoSignIn": {"average_rating": 4.8, "rating_count": 42},
                        "DemoPlugin": {"average_rating": 4.9, "rating_count": 15},
                    },
                },
            )

    def site_userdata_endpoint(self, name):
        """返回站点最新非敏感上/下载量与做种数，供站点卡片展示流量比例图示。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/site/userdata/latest"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if name != "a" and not self.permissions(mode)["manage"]:
            self.reply(403, {"success": False})
            return
        rows = [
            {
                "domain": "synthetic.test",
                "name": "合成主站",
                "upload": 12_884_901_888_000,
                "download": 3_221_225_472_000,
                "ratio": 4.0,
                "seeding": 48,
            }
        ]
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

    def plugin_remotes_endpoint(self, name):
        """返回合成 Vue 联邦插件远程入口清单（完全无前端 HTML / 3000 端口依赖）。"""
        query = parse_qs(urlsplit(self.path).query)
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/plugin/remotes"] += 1
            mode = profile["mode"]
        if mode == "expired":
            self.reply(401, {"success": False})
            return
        if query.get("token", [""])[0] != "moviepilot":
            self.reply(403, {"detail": "Forbidden"})
            return
        self.reply(
            200,
            [
                {
                    "id": "VueCompatDemo",
                    "url": "/api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js?v=1.2.0",
                    "name": "合成远程组件插件",
                    "version": "1.2.0",
                    "bundle_hash": "a1b2c3d4e5f6",
                }
            ],
        )

    def plugin_remote_entry_js_endpoint(self, name):
        """返回可被 @module-federation/enhanced/runtime 加载的 ESM 合成联邦插件容器。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/plugin/file/vuecompatdemo/dist/assets/remoteEntry.js"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        js_body = r"""
let sharedScope = null;

export function init(scope) {
  sharedScope = scope;
}

async function resolveSharedVue(scope) {
  const pkg = scope && scope.vue;
  if (!pkg) throw new Error('Shared vue not found in federation shareScope');
  const versions = Object.values(pkg);
  if (!versions.length) throw new Error('Shared vue version map is empty');
  const entry = versions[0];
  if (typeof entry.lib === 'function') return entry.lib();
  if (typeof entry.get === 'function') {
    const factory = await entry.get();
    return typeof factory === 'function' ? factory() : factory;
  }
  return entry;
}

function createDemoComponent(Vue, mode) {
  const { defineComponent, h, ref, onMounted, resolveComponent } = Vue;
  return defineComponent({
    name: mode === 'Config' ? 'VueCompatDemoConfig' : 'VueCompatDemoPage',
    emits: ['close', 'switch', 'save', 'action'],
    props: {
      api: { type: Object, required: true },
      hostSdk: { type: Object, default: null },
      initialConfig: { type: Object, default: () => ({}) },
      pluginId: { type: String, default: 'VueCompatDemo' },
    },
    setup(props, { emit }) {
      const apiStatus = ref('正在经 Native Bridge 请求状态…');
      const tokenAudit = ref('校验中…');
      const confirmResult = ref('尚未触发确认框');
      const nativeCapResult = ref('尚未校验本地能力');
      const refreshCount = ref(0);

      function buildTinyWavBase64() {
        const sampleRate = 8000;
        const numSamples = 1600;
        const dataSize = numSamples * 2;
        const buf = new ArrayBuffer(44 + dataSize);
        const view = new DataView(buf);
        const writeStr = (off, str) => {
          for (let i = 0; i < str.length; i++) view.setUint8(off + i, str.charCodeAt(i));
        };
        writeStr(0, 'RIFF');
        view.setUint32(4, 36 + dataSize, true);
        writeStr(8, 'WAVE');
        writeStr(12, 'fmt ');
        view.setUint32(16, 16, true);
        view.setUint16(20, 1, true);
        view.setUint16(22, 1, true);
        view.setUint32(24, sampleRate, true);
        view.setUint32(28, sampleRate * 2, true);
        view.setUint16(32, 2, true);
        view.setUint16(34, 16, true);
        writeStr(36, 'data');
        view.setUint32(40, dataSize, true);
        for (let i = 0; i < numSamples; i++) {
          const sample = Math.round(Math.sin((2 * Math.PI * 440 * i) / sampleRate) * 6000);
          view.setInt16(44 + i * 2, sample, true);
        }
        let bin = '';
        const bytes = new Uint8Array(buf);
        for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
        return btoa(bin);
      }

      async function onVerifyNativeCaps() {
        try {
          const native = props.hostSdk && props.hostSdk.native;
          if (!native) {
            nativeCapResult.value = '本地能力失败：缺少 hostSdk.native';
            return;
          }
          const caps = await native.device.getCapabilities();
          const hasAudioRec = Array.isArray(caps.capabilities) && caps.capabilities.includes('audio.record');
          const hasAudioPlay = Array.isArray(caps.capabilities) && caps.capabilities.includes('audio.play');
          const hasPlayNative = Array.isArray(caps.capabilities) && caps.capabilities.includes('media.playNative');
          await native.device.copyText('mp-native-cap-ok');
          const clip = await native.device.readClipboard();
          const awakeOn = await native.device.keepAwake(true);
          const awakeOff = await native.device.keepAwake(false);
          const recStatus = await native.audio.getRecordStatus();
          const wavB64 = buildTinyWavBase64();
          const playRes = await native.audio.play({ base64: wavB64, mimeType: 'audio/wav', volume: 0.2 });
          const stopRes = await native.audio.stop();
          if (
            caps.platform === 'ios' &&
            hasAudioRec &&
            hasAudioPlay &&
            hasPlayNative &&
            clip.text === 'mp-native-cap-ok' &&
            awakeOn.enabled === true &&
            awakeOff.enabled === false &&
            recStatus.state === 'idle' &&
            playRes.playbackId &&
            stopRes.stopped === true
          ) {
            nativeCapResult.value = '本地能力与音频播放自检通过 (' + caps.capabilities.length + ' 项)';
          } else {
            nativeCapResult.value = '本地能力校验不完整：' + JSON.stringify({ caps: caps.platform, clip: clip.text, rec: recStatus.state });
          }
        } catch (err) {
          nativeCapResult.value = '本地能力异常：' + (err && err.message ? err.message : String(err));
        }
      }

      async function loadStatus() {
        try {
          const res = await props.api.get('plugin/VueCompatDemo/status');
          const msg = (res && res.message) ? res.message : JSON.stringify(res);
          const count = (res && res.data && res.data.items) ? res.data.items : 0;
          apiStatus.value = 'API 代理返回：' + msg + ' · 条目 ' + count;
        } catch (err) {
          apiStatus.value = 'API 代理失败：' + (err && err.message ? err.message : String(err));
        }
      }

      onMounted(() => {
        let hasAuth = false;
        try {
          hasAuth = window.localStorage.getItem('auth') !== null;
        } catch (_) {}
        tokenAudit.value = hasAuth ? '检测到 auth 残留' : '零令牌安全校验通过';
        loadStatus();
        if (props.hostSdk && props.hostSdk.shell && typeof props.hostSdk.shell.registerButton === 'function') {
          props.hostSdk.shell.registerButton({
            title: '刷新状态',
            icon: 'mdi-refresh',
            action: () => {
              refreshCount.value += 1;
              loadStatus();
            },
          });
        }
      });

      function onTriggerToast() {
        if (props.hostSdk && props.hostSdk.ui && props.hostSdk.ui.toast) {
          props.hostSdk.ui.toast.success('原生 Toast 桥接成功');
        }
      }

      async function onTriggerConfirm() {
        if (props.hostSdk && props.hostSdk.ui && typeof props.hostSdk.ui.confirm === 'function') {
          const ok = await props.hostSdk.ui.confirm({
            title: '原生确认测试',
            content: '来自联邦插件的原生确认弹窗',
            confirmText: '确定',
            cancelText: '取消',
          });
          confirmResult.value = ok ? '原生确认结果：已确认' : '原生确认结果：已取消';
        }
      }

      return () => {
        const VCard = resolveComponent('VCard');
        const VCardTitle = resolveComponent('VCardTitle');
        const VCardText = resolveComponent('VCardText');
        const VBtn = resolveComponent('VBtn');
        const VChip = resolveComponent('VChip');

        // 故意包裹一层全宽白色不透明根容器，用于验证 Layer 3 视觉融合自动将其洗净为透明
        return h(
          'div',
          {
            class: 'demo-opaque-wrapper',
            style: {
              width: '100%',
              minHeight: '460px',
              backgroundColor: 'rgb(255, 255, 255)',
              padding: '16px',
              boxSizing: 'border-box',
            },
          },
          [
            h(
              VCard,
              { class: 'mb-4', variant: 'flat' },
              {
                default: () => [
                  h(
                    'div',
                    {
                      style: {
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        padding: '12px 16px 4px',
                        gap: '8px',
                      },
                    },
                    [
                      h(VCardTitle, { class: 'pa-0' }, () => '合成联邦插件运行正常'),
                      h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px' } }, [
                        h(
                          VBtn,
                          {
                            size: 'small',
                            variant: 'tonal',
                            color: 'primary',
                            onClick: () => {
                              refreshCount.value += 1;
                              loadStatus();
                            },
                          },
                          () => '刷新状态'
                        ),
                        h(
                          VBtn,
                          {
                            size: 'small',
                            variant: 'tonal',
                            color: 'secondary',
                            'aria-label': '关闭插件',
                            onClick: () => emit('close'),
                          },
                          () => '关闭插件'
                        ),
                      ]),
                    ]
                  ),
                  h(VCardText, null, () => [
                    h('div', { style: { marginBottom: '10px', fontSize: '14px' } }, apiStatus.value),
                    h(
                      'div',
                      { style: { display: 'flex', flexWrap: 'wrap', gap: '8px', marginBottom: '12px' } },
                      [
                        h(VChip, { color: 'success', size: 'small', variant: 'tonal' }, () => tokenAudit.value),
                        h(VChip, { color: 'primary', size: 'small', variant: 'tonal' }, () => '本地预热联邦运行时 v2'),
                        h(VChip, { color: 'info', size: 'small', variant: 'tonal' }, () => '刷新次数 ' + refreshCount.value),
                      ]
                    ),
                    h('div', { style: { fontSize: '13px', opacity: '0.85' } }, confirmResult.value),
                    h('div', { style: { fontSize: '13px', opacity: '0.9', marginTop: '6px' } }, nativeCapResult.value),
                  ]),
                ],
              }
            ),
            h(
              VCard,
              { variant: 'flat' },
              {
                default: () => [
                  h(VCardTitle, null, () => '原生能力桥接验证'),
                  h(VCardText, null, () => [
                    h(
                      'div',
                      { style: { display: 'flex', flexWrap: 'wrap', gap: '12px' } },
                      [
                        h(
                          VBtn,
                          { color: 'primary', variant: 'flat', onClick: onTriggerToast },
                          () => '触发原生 Toast'
                        ),
                        h(
                          VBtn,
                          { color: 'secondary', variant: 'tonal', onClick: onTriggerConfirm },
                          () => '触发原生确认框'
                        ),
                        h(
                          VBtn,
                          { color: 'success', variant: 'tonal', onClick: onVerifyNativeCaps },
                          () => '自检原生音频与硬件能力'
                        ),
                      ]
                    ),
                  ]),
                ],
              }
            ),
          ]
        );
      };
    },
  });
}

export async function get(moduleName) {
  const Vue = await resolveSharedVue(sharedScope);
  if (moduleName === './Config' || moduleName === 'Config') {
    const comp = createDemoComponent(Vue, 'Config');
    return () => ({ __esModule: true, default: comp });
  }
  const comp = createDemoComponent(Vue, 'Page');
  return () => ({ __esModule: true, default: comp });
}
"""
        data = js_body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def plugin_vue_demo_status_endpoint(self, name):
        """校验 Native Bridge 代发的鉴权 API 请求并返回状态数据。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/plugin/VueCompatDemo/status"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        self.reply(
            200,
            {
                "success": True,
                "message": "本地预热运行时直通成功 (v1.2.0)",
                "data": {"items": 42, "engine": "local-shell-v2"},
            },
        )

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
            profile["counts"]["POST api/v1/message/agent/stream"] += 1
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

    def agent_display_endpoint(self, name, endpoint, body):
        """保存真实 Agent 展示消息合同，后续详情必须返回客户端提交的完整快照。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"PUT {endpoint}"] += 1
            expired = profile["mode"] == "expired"
        if expired or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        try:
            payload = json.loads(body)
            messages = payload.get("messages", [])
            if not isinstance(messages, list) or any(
                not isinstance(message, dict) or message.get("role") not in {"user", "assistant", "system", "tool"}
                for message in messages
            ):
                raise ValueError("invalid display messages")
        except (ValueError, TypeError, AttributeError):
            self.reply(422, {"success": False})
            return
        sid = endpoint.split("/")[-2]
        with self.server.lock:
            row = next((row for row in profile["agent_sessions"] if row["session_id"] == sid), None)
            if row is None:
                row = {"session_id": sid}
                profile["agent_sessions"].append(row)
            row["messages"] = messages
            row["message_count"] = len(messages)
            row["title"] = payload.get("title") or "新会话"
            summary = {key: value for key, value in row.items() if key != "messages"}
        self.reply(200, {"success": True, "message": "", "data": summary})

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

    def system_global_endpoint(self, name):
        """返回客户端启动时查询的非敏感全局图片与域名开关（对齐 /api/v1/system/global?token=moviepilot）。"""
        query = parse_qs(urlsplit(self.path).query)
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/system/global"] += 1
            mode = profile["mode"]
            env = dict(profile["env"])
        if mode == "unavailable":
            self.reply(503, {"success": False})
            return
        if query.get("token", [""])[0] != "moviepilot":
            self.reply(403, {"success": False})
            return
        self.reply(200, {
            "success": True,
            "message": "",
            "data": {
                "GLOBAL_IMAGE_CACHE": bool(env.get("GLOBAL_IMAGE_CACHE", False)),
                "TMDB_IMAGE_DOMAIN": env.get("TMDB_IMAGE_DOMAIN", "image.tmdb.org"),
                "BANGUMI_PROXY_ENABLE": bool(env.get("BANGUMI_PROXY_ENABLE", False)),
                "BANGUMI_IMAGE_DOMAIN": env.get("BANGUMI_IMAGE_DOMAIN", ""),
            },
        })

    def image_endpoint(self, name, endpoint="api/v1/system/img/0"):
        """仅接受同一实例的资源 Cookie，并确认客户端没有转发主令牌。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"GET {endpoint}"] += 1
            if endpoint != "api/v1/system/img/0":
                profile["counts"]["GET api/v1/system/img/0"] += 1
            mode = profile["mode"]
        query = parse_qs(urlsplit(self.path).query)
        reference = (query.get("imgurl") or query.get("url") or [""])[0]
        if (
            mode == "expired" or self.headers.get("Authorization") is not None
            or self.headers.get("Cookie") != f"MoviePilot={self.resource_token(name)}"
        ):
            with self.server.lock:
                profile["counts"]["image-auth-rejected"] += 1
            self.reply(401, {"success": False})
        elif not re.fullmatch(
            r"https://images\.example\.test/(?:1[0-9]{2}|3[0-9]{2}|5[0-9]{2})/(?:poster|backdrop)\.png",
            reference,
        ):
            self.reply(400, {"success": False})
        else:
            with self.server.lock:
                profile["counts"]["image-served"] += 1
            self.reply_image(reference)

    def list_mediaserver_account_bindings(self, name):
        """返回当前登录账号的个人媒体服务器绑定列表（对齐后端 verify_token 语义，无需超管或发现权限）。"""
        with self.server.lock:
            saved = dict(self.server.profiles[name]["mediaserver_bindings"].get("Emby") or {})
        bound = bool(saved.get("bound"))
        return [
            {
                "server": "Emby",
                "server_type": "emby",
                "sync_mode": "session" if bound else "userdata",
                "supports_binding": True,
                "bound": bound,
                "status": "bound" if bound else "unbound",
                "remote_username": saved.get("remote_username") if bound else None,
                "source": "manual" if bound else None,
                "updated_at": saved.get("updated_at") if bound else None,
            }
        ]

    def mediaserver_account_bind_endpoint(self, name, body):
        """验证当前登录令牌并记录个人媒体服务器绑定，不要求超级管理员或特定业务权限。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["POST api/v1/mediaserver/account-bindings"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        try:
            payload = json.loads(body)
            server = str(payload.get("server") or "").strip()
            username = str(payload.get("username") or "").strip()
            password = str(payload.get("password") or "")
            token = str(payload.get("token") or "").strip()
        except (ValueError, TypeError, AttributeError):
            self.reply(422, {"detail": "invalid payload"})
            return
        if server != "Emby":
            self.reply(404, {"detail": "未找到对应的已启用媒体服务器"})
            return
        if not token and (not username or not password):
            self.reply(422, {"detail": "请填写媒体服务器用户名和密码"})
            return
        remote_user = username or f"native-{name}"
        with self.server.lock:
            self.server.profiles[name]["mediaserver_bindings"]["Emby"] = {
                "bound": True,
                "remote_username": remote_user,
                "updated_at": 1795827600,
            }
        updated = self.list_mediaserver_account_bindings(name)[0]
        self.reply(200, {"success": True, "message": "媒体服务器账号绑定成功", "data": updated})

    def mediaserver_account_unbind_endpoint(self, name, endpoint):
        """解除当前登录账号在指定媒体服务器上的个人同步令牌绑定。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"DELETE {endpoint}"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        server = endpoint.rsplit("/", 1)[-1]
        with self.server.lock:
            removed = self.server.profiles[name]["mediaserver_bindings"].pop(server, None) is not None
        self.reply(
            200,
            {
                "success": True,
                "message": "已解除媒体服务器账号绑定" if removed else "当前服务器未绑定账号",
                "data": None,
            },
        )

    @staticmethod
    def mediaserver_fixture(endpoint, query, mode):
        """在 mediaserver 验收模式下返回多维 Emby 风格媒体库浏览、三层详情与播前选轨夹具。"""
        if mode != "mediaserver":
            if endpoint == "api/v1/mediaserver/browse":
                return {"items": [], "total_count": 0, "start_index": 0, "limit": 30, "has_more": False}
            if endpoint == "api/v1/mediaserver/filters":
                return {"genres": [], "years": []}
            return [] if endpoint != "api/v1/mediaserver/detail" else None

        server = query.get("server", ["Emby"])[0] or "Emby"
        if endpoint == "api/v1/mediaserver/clients":
            return [{"name": "Emby", "type": "emby"}]
        if endpoint == "api/v1/mediaserver/library":
            return [
                {
                    "id": "lib-tv", "item_id": "lib-tv", "server": "Emby", "server_type": "emby",
                    "name": "电视剧集", "type": "电视剧", "item_count": 24,
                    "image": "https://images.example.test/301/backdrop.png",
                    "link": "https://emby.example.test/web/index.html#!/videos?parentId=lib-tv",
                },
                {
                    "id": "lib-movies", "item_id": "lib-movies", "server": "Emby", "server_type": "emby",
                    "name": "精选电影", "type": "电影", "item_count": 68,
                    "image": "https://images.example.test/302/backdrop.png",
                    "link": "https://emby.example.test/web/index.html#!/videos?parentId=lib-movies",
                },
            ]
        if endpoint == "api/v1/mediaserver/playing":
            return [
                {
                    "id": "ep-101", "item_id": "ep-101", "server": "Emby", "type": "Episode",
                    "title": "星际迷航：新世界", "subtitle": "S01E01 陌生新世界",
                    "year": "2025", "percent": 42.0,
                    "image": "https://images.example.test/311/backdrop.png",
                }
            ]
        if endpoint == "api/v1/mediaserver/latest":
            return [
                {
                    "id": "series-100", "item_id": "series-100", "server": "Emby", "type": "Series",
                    "title": "星际迷航：新世界", "subtitle": "第 2 季", "year": "2025",
                    "image": "https://images.example.test/301/poster.png",
                },
                {
                    "id": "movie-200", "item_id": "movie-200", "server": "Emby", "type": "Movie",
                    "title": "深空回响", "subtitle": "4K HDR", "year": "2025",
                    "image": "https://images.example.test/302/poster.png",
                },
            ]
        if endpoint == "api/v1/mediaserver/filters":
            return {
                "genres": ["科幻", "冒险", "剧情"],
                "years": [2025, 2024, 2023],
                "item_types": ["Movie", "Series"],
                "sort_options": ["date_created", "title", "premiere_date", "rating", "date_played"],
            }
        if endpoint == "api/v1/mediaserver/browse":
            items = [
                {
                    "item_id": "series-100", "server": server, "server_type": "emby",
                    "item_type": "Series", "media_type": "电视剧", "title": "星际迷航：新世界",
                    "subtitle": "2 季", "year": "2025", "rating": 8.9, "child_count": 2,
                    "poster": "https://images.example.test/301/poster.png",
                    "backdrop": "https://images.example.test/301/backdrop.png",
                    "played": False, "played_percentage": 35.0,
                },
                {
                    "item_id": "movie-200", "server": server, "server_type": "emby",
                    "item_type": "Movie", "media_type": "电影", "title": "深空回响",
                    "subtitle": "2025", "year": "2025", "rating": 8.4, "duration_ms": 7440000,
                    "poster": "https://images.example.test/302/poster.png",
                    "backdrop": "https://images.example.test/302/backdrop.png",
                    "played": True, "played_percentage": 100.0,
                },
            ]
            search = (query.get("search", [""])[0] or "").strip()
            if search:
                items = [it for it in items if search in it["title"]]
            played = query.get("played", [""])[0]
            if played == "true":
                items = [it for it in items if it.get("played")]
            elif played == "false":
                items = [it for it in items if not it.get("played")]
            return {
                "items": items, "total_count": len(items),
                "start_index": 0, "limit": 30, "has_more": False,
            }
        if endpoint == "api/v1/mediaserver/seasons":
            return [
                {
                    "item_id": "season-1", "server": server, "server_type": "emby",
                    "item_type": "Season", "media_type": "电视剧", "title": "第 1 季",
                    "subtitle": "共 3 集", "year": "2024", "season_number": 1, "child_count": 3,
                    "series_id": "series-100", "series_name": "星际迷航：新世界",
                    "poster": "https://images.example.test/303/poster.png",
                },
                {
                    "item_id": "season-2", "server": server, "server_type": "emby",
                    "item_type": "Season", "media_type": "电视剧", "title": "第 2 季",
                    "subtitle": "共 2 集", "year": "2025", "season_number": 2, "child_count": 2,
                    "series_id": "series-100", "series_name": "星际迷航：新世界",
                    "poster": "https://images.example.test/304/poster.png",
                },
            ]
        if endpoint == "api/v1/mediaserver/season-episodes":
            return [
                {
                    "item_id": "ep-101", "server": server, "server_type": "emby",
                    "item_type": "Episode", "media_type": "电视剧", "title": "陌生新世界",
                    "subtitle": "S01E01", "overview": "进取号在未知星系收到神秘求救信号，开启全新航程。",
                    "year": "2024", "duration_ms": 3120000, "season_number": 1, "episode_number": 1,
                    "series_id": "series-100", "series_name": "星际迷航：新世界", "season_id": "season-1",
                    "thumb": "https://images.example.test/311/backdrop.png",
                    "played": False, "played_percentage": 42.0, "resume_position_ms": 1310000,
                },
                {
                    "item_id": "ep-102", "server": server, "server_type": "emby",
                    "item_type": "Episode", "media_type": "电视剧", "title": "彗星之子",
                    "subtitle": "S01E02", "overview": "船员试图改变一颗古老彗星的轨道以拯救行星文明。",
                    "year": "2024", "duration_ms": 3000000, "season_number": 1, "episode_number": 2,
                    "series_id": "series-100", "series_name": "星际迷航：新世界", "season_id": "season-1",
                    "thumb": "https://images.example.test/312/backdrop.png",
                    "played": False, "played_percentage": 0.0,
                },
                {
                    "item_id": "ep-103", "server": server, "server_type": "emby",
                    "item_type": "Episode", "media_type": "电视剧", "title": "伊利里亚的幽灵",
                    "subtitle": "S01E03", "overview": "一场离子风暴席卷星舰，引发船员间的光敏异变。",
                    "year": "2024", "duration_ms": 2940000, "season_number": 1, "episode_number": 3,
                    "series_id": "series-100", "series_name": "星际迷航：新世界", "season_id": "season-1",
                    "thumb": "https://images.example.test/313/backdrop.png",
                    "played": True, "played_percentage": 100.0,
                },
            ]
        if endpoint == "api/v1/mediaserver/search":
            return [
                {
                    "id": "series-100", "item_id": "series-100", "server": server, "server_type": "emby",
                    "title": "星际迷航：新世界", "subtitle": "科幻 / 冒险", "year": "2025",
                    "type": "电视剧", "image": "https://images.example.test/301/poster.png",
                },
                {
                    "id": "movie-200", "item_id": "movie-200", "server": server, "server_type": "emby",
                    "title": "深空回响", "subtitle": "科幻", "year": "2025",
                    "type": "电影", "image": "https://images.example.test/302/poster.png",
                },
            ]
        if endpoint == "api/v1/mediaserver/detail":
            item_id = (query.get("itemid") or query.get("item_id") or [""])[0]
            sources = [
                {
                    "id": "src-4k",
                    "name": "2160p HDR10 · HEVC · 18.4 GB",
                    "container": "mkv",
                    "size": 19756849561,
                    "bitrate": 24500000,
                    "duration_ms": 3120000,
                    "streams": [
                        {
                            "index": 0, "type": "video", "codec": "hevc",
                            "width": 3840, "height": 2160, "video_range": "HDR10",
                            "display_title": "4K HEVC HDR10",
                        },
                        {
                            "index": 1, "type": "audio", "codec": "dts",
                            "language": "chi", "display_title": "中文 (DTS-HD MA 5.1)",
                            "channels": 6, "channel_layout": "5.1", "is_default": True,
                        },
                        {
                            "index": 2, "type": "audio", "codec": "truehd",
                            "language": "eng", "display_title": "English (Dolby Atmos 7.1)",
                            "channels": 8, "channel_layout": "7.1", "is_default": False,
                        },
                        {
                            "index": 3, "type": "subtitle", "codec": "ass",
                            "language": "chi", "display_title": "简繁双语特效 (ASS)",
                            "is_default": True, "is_external": True,
                            "subtitle_id": "ms:src-4k:3.ass",
                        },
                        {
                            "index": 4, "type": "subtitle", "codec": "subrip",
                            "language": "eng", "display_title": "English (SRT)",
                            "is_default": False, "is_external": False,
                        },
                    ],
                },
                {
                    "id": "src-1080p",
                    "name": "1080p WEB-DL · H264 · 4.2 GB",
                    "container": "mp4",
                    "size": 4509715660,
                    "bitrate": 6200000,
                    "duration_ms": 3120000,
                    "streams": [
                        {
                            "index": 0, "type": "video", "codec": "h264",
                            "width": 1920, "height": 1080, "video_range": "SDR",
                            "display_title": "1080P H264",
                        },
                        {
                            "index": 1, "type": "audio", "codec": "aac",
                            "language": "chi", "display_title": "中文 (AAC 2.0)",
                            "channels": 2, "channel_layout": "2.0", "is_default": True,
                        },
                    ],
                },
            ]
            people = [
                {"id": "p1", "name": "安松·蒙特", "role": "饰 克里斯托弗·派克", "type": "Actor", "image": "https://images.example.test/501/poster.png"},
                {"id": "p2", "name": "丽贝卡·罗梅恩", "role": "饰 一号大副", "type": "Actor", "image": "https://images.example.test/502/poster.png"},
            ]
            if item_id == "series-100":
                return {
                    "item_id": "series-100", "server": server, "server_type": "emby",
                    "item_type": "Series", "media_type": "电视剧",
                    "title": "星际迷航：新世界", "original_title": "Star Trek: Strange New Worlds",
                    "tagline": "探索未知星海的壮丽航程",
                    "overview": "讲述派克船长带领进取号探索银河系中全新世界的经典科幻剧集，每集呈现独立而震撼的星际冒险。",
                    "year": "2025", "premiere_date": "2024-05-05", "rating": 8.9, "critic_rating": 98.0,
                    "ratings": [
                        {"source": "imdb", "value": 8.9, "scale": "ten"},
                        {"source": "rottentomatoes", "value": 98.0, "scale": "percent"},
                    ],
                    "genres": ["科幻", "冒险", "剧情"], "studios": ["Paramount+"],
                    "poster": "https://images.example.test/301/poster.png",
                    "backdrop": "https://images.example.test/301/backdrop.png",
                    "child_count": 2, "season_count": 2, "episode_count": 5, "tmdb_id": "103516",
                    "play_url": "https://emby.example.test/web/index.html#!/item?id=series-100",
                    "people": people, "media_sources": [], "can_play": False,
                }
            if item_id == "season-1":
                return {
                    "item_id": "season-1", "server": server, "server_type": "emby",
                    "item_type": "Season", "media_type": "电视剧",
                    "title": "第 1 季", "series_id": "series-100", "series_name": "星际迷航：新世界",
                    "season_number": 1, "child_count": 3, "episode_count": 3, "year": "2024", "rating": 8.8,
                    "overview": "第一季共 3 集，进取号重返星际舰队执行首轮深空探索任务。",
                    "genres": ["科幻", "冒险"], "tmdb_id": "103516",
                    "poster": "https://images.example.test/303/poster.png",
                    "backdrop": "https://images.example.test/301/backdrop.png",
                    "play_url": "https://emby.example.test/web/index.html#!/item?id=season-1",
                    "people": people, "media_sources": [], "can_play": False,
                }
            return {
                "item_id": item_id or "ep-101", "server": server, "server_type": "emby",
                "item_type": "Episode", "media_type": "电视剧",
                "title": "陌生新世界", "series_id": "series-100", "series_name": "星际迷航：新世界",
                "season_id": "season-1", "season_name": "第 1 季",
                "season_number": 1, "episode_number": 1,
                "year": "2024", "premiere_date": "2024-05-05", "rating": 9.1, "critic_rating": 96.0,
                "ratings": [
                    {"source": "imdb", "value": 9.1, "scale": "ten"},
                    {"source": "rottentomatoes", "value": 96.0, "scale": "percent"},
                ],
                "duration_ms": 3120000, "resume_position_ms": 1310000, "played_percentage": 42.0,
                "overview": "进取号在未知星系收到神秘求救信号，派克船长必须决定是否介入这颗行星的首次接触事件。",
                "genres": ["科幻", "冒险"], "tmdb_id": "103516",
                "poster": "https://images.example.test/301/poster.png",
                "backdrop": "https://images.example.test/311/backdrop.png",
                "thumb": "https://images.example.test/311/backdrop.png",
                "play_url": "https://emby.example.test/web/index.html#!/item?id=ep-101",
                "people": people, "media_sources": sources, "can_play": True,
            }
        return []

    _SAMPLE_MP4_CACHE = None

    @classmethod
    def _sample_mp4_bytes(cls):
        if cls._SAMPLE_MP4_CACHE is None:
            cls._SAMPLE_MP4_CACHE = (
                Path(__file__).resolve().with_name("synthetic-sample.mp4").read_bytes()
            )
        return cls._SAMPLE_MP4_CACHE

    def mediaserver_stream_info_endpoint(self, name):
        """返回受控媒体播放清单并签发同源流 Cookie，供多内核实机播放验收使用。"""
        query = parse_qs(urlsplit(self.path).query)
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"]["GET api/v1/mediaserver/stream-info"] += 1
            mode = profile["mode"]
        if mode == "expired" or self.headers.get("Authorization") != f"Bearer synthetic-native-{name}":
            self.reply(401, {"success": False})
            return
        if not self.permissions(mode)["discovery"]:
            self.reply(403, {"success": False})
            return
        item_id = (query.get("itemid") or query.get("item_id") or ["ep-101"])[0]
        server = (query.get("server") or ["Emby"])[0]
        media_source_id = (query.get("media_source_id") or [""])[0]
        params = [("itemid", item_id), ("server", server)]
        if media_source_id:
            params.append(("media_source_id", media_source_id))
        content_url = (
            f"http://127.0.0.1:{self.server.server_port}/{name}/api/v1/mediaserver/stream?"
            + urlencode(params)
        )
        self.reply(
            200,
            {
                "success": True,
                "message": "",
                "data": {
                    "item_id": item_id,
                    "server": server,
                    "server_type": "emby",
                    "title": "陌生新世界",
                    "content_url": content_url,
                    "media_type": "video",
                    "media_source_id": media_source_id or "src-1080p",
                    "play_session_id": f"sess-{item_id}",
                    "progress_sync_mode": "proxy",
                    "duration_ms": 40000,
                    "resume_position_ms": 0,
                    "subtitles": [],
                },
            },
            headers={
                "Set-Cookie": f"mp_media_token=synthetic-stream-{name}; Path=/; HttpOnly",
            },
        )

    def mediaserver_stream_endpoint(self, name):
        """按同源令牌或签发 Cookie 提供支持 HTTP Range 的合成 MP4 测试视频流。"""
        with self.server.lock:
            profile = self.server.profiles[name]
            profile["counts"][f"{self.command} api/v1/mediaserver/stream"] += 1
            mode = profile["mode"]
        expected_auth = f"Bearer synthetic-native-{name}"
        expected_cookie = f"mp_media_token=synthetic-stream-{name}"
        auth_ok = self.headers.get("Authorization") == expected_auth
        cookie_ok = expected_cookie in (self.headers.get("Cookie") or "")
        if mode == "expired" or not (auth_ok or cookie_ok):
            self.reply(401, {"success": False})
            return
        payload = self._sample_mp4_bytes()
        total = len(payload)
        range_header = self.headers.get("Range")
        start = 0
        end = total - 1
        status = 200
        if range_header and range_header.startswith("bytes="):
            spec = range_header[6:].split(",", 1)[0].strip()
            if "-" in spec:
                raw_start, raw_end = spec.split("-", 1)
                try:
                    if raw_start == "":
                        suffix = int(raw_end)
                        start = max(0, total - suffix)
                    else:
                        start = int(raw_start)
                        if raw_end != "":
                            end = min(total - 1, int(raw_end))
                    if 0 <= start <= end < total:
                        status = 206
                    else:
                        self.send_response(416)
                        self.send_header("Content-Range", f"bytes */{total}")
                        self.end_headers()
                        return
                except ValueError:
                    status = 200
                    start, end = 0, total - 1
        chunk = payload[start : end + 1]
        self.send_response(status)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-store")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
        self.send_header("Content-Length", str(len(chunk)))
        self.end_headers()
        if self.command == "GET":
            try:
                self.wfile.write(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass

    @staticmethod
    def media(item_id, media_type, media_source="themoviedb", raw_id=None):
        """提供显式标记的合成记录，编号区分搜索、发现与详情请求，并附带多来源评分字段。"""
        vote_by_source = {"imdb": 8.5, "douban": 8.6, "bangumi": 8.4}
        base = {
            "media_source": media_source, "media_id": str(raw_id or item_id), "tmdb_id": item_id,
            "imdb_id": f"tt0000{item_id}", "douban_id": f"3000{item_id}",
            "type": media_type, "title": f"合成{media_type} {item_id}", "year": "2025",
            "release_date": "2025-07-15",
            "tagline": "跨越边界的原生体验",
            "runtime": 124 if media_type == "电影" else None,
            "number_of_seasons": 2 if media_type == "电视剧" else None,
            "genres": [{"name": "科幻"}, {"name": "冒险"}],
            "directors": [{"id": 503, "name": "合成导演", "source": "themoviedb"}],
            "poster_path": f"https://images.example.test/{item_id}/poster.png",
            "backdrop_path": f"https://images.example.test/{item_id}/backdrop.png",
            "overview": "本条记录用于验证原生客户端的检索与详情直连。",
            "vote_average": vote_by_source.get(media_source, 8.3),
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
            permissions["subscribe"] = False
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
