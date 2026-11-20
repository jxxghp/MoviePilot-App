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
                    "partial-discovery-failed",
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
        if name in self.server.profiles and self.command == "GET":
            if endpoint in self.business_endpoints() or re.fullmatch(r"api/v1/media/1[0-9]{2}", endpoint):
                self.business_endpoint(name, endpoint)
                return
            if endpoint == "api/v1/system/img/0":
                self.image_endpoint(name)
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
            "api/v1/discover/tmdb_movies",
            "api/v1/discover/tmdb_tvs",
            "api/v1/recommend/tmdb_trending",
            "api/v1/mediaserver/clients",
            "api/v1/mediaserver/playing",
            "api/v1/mediaserver/latest",
            "api/v1/mediaserver/library",
            "api/v1/media/search",
            "api/v1/media/source",
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
            or endpoint == "api/v1/media/search"
            or re.fullmatch(r"api/v1/media/1[0-9]{2}", endpoint)
        )
        if requires_discovery and not self.permissions(mode)["discovery"]:
            self.reply(403, {"success": False})
            return
        if endpoint.startswith("api/v1/dashboard/") and name != "a":
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
            "api/v1/recommend/tmdb_trending",
            "api/v1/mediaserver/clients",
            "api/v1/mediaserver/playing",
            "api/v1/mediaserver/latest",
            "api/v1/mediaserver/library",
        }:
            value = []
        elif endpoint == "api/v1/media/search":
            if title == "galaxy" and page in {"1", "2"}:
                ids = range(121, 129) if page == "1" else [129]
                value = [self.media(item_id, "电影") for item_id in ids]
            else:
                value = []
        elif endpoint == "api/v1/media/source":
            value = [{"name": "TMDB", "media_source": "themoviedb", "media_types": ["电影", "电视剧"]}]
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
        else:
            item_id = int(endpoint.rsplit("/", 1)[-1])
            media_type = query.get("type_name", [""])[0]
            if query.get("media_source") != ["themoviedb"] or media_type not in {"电影", "电视剧"}:
                self.reply(422, {"success": False})
                return
            value = self.media(item_id, media_type)
        self.reply(200, {"success": True, "message": "", "data": value}, self.resource_headers(name))

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
        elif not re.fullmatch(r"https://images\.example\.test/1[0-9]{2}/(?:poster|backdrop)\.png", reference):
            self.reply(400, {"success": False})
        else:
            with self.server.lock:
                profile["counts"]["image-served"] += 1
            self.reply_image(reference)

    @staticmethod
    def media(item_id, media_type):
        """提供显式标记的合成记录，编号区分搜索、发现与详情请求。"""
        return {
            "media_source": "themoviedb", "media_id": str(item_id), "tmdb_id": item_id,
            "type": media_type, "title": f"合成{media_type} {item_id}", "year": "2025",
            "poster_path": f"https://images.example.test/{item_id}/poster.png",
            "backdrop_path": f"https://images.example.test/{item_id}/backdrop.png",
            "overview": "本条记录用于验证原生客户端的检索与详情直连。", "vote_average": 8.3,
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
