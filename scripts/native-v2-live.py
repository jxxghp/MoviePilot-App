#!/usr/bin/env python3
"""交互式验证本机 3001 后端；凭据仅存在内存，原始登录活动结果在取证后销毁。"""

import argparse
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import shutil
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess
import threading
from urllib.parse import urlencode
from urllib.request import Request, urlopen


class SessionInputServer(HTTPServer):
    """只向持有一次性随机口令的本机测试运行器交付一次输入。"""

    def __init__(self, payload):
        """绑定动态回环端口，不向局域网暴露真实账号或重复提供凭据。"""
        self.payload = payload
        self.nonce = secrets.token_urlsafe(40)
        self.lock = threading.Lock()
        super().__init__(("127.0.0.1", 0), SessionInputHandler)


class SessionInputHandler(BaseHTTPRequestHandler):
    """不记录路径、头部或正文；成功交付后立即销毁服务持有的凭据引用。"""

    def log_message(self, *_):
        """关闭 HTTP 默认日志，防止认证输入进入控制台或文件。"""

    def do_GET(self):
        """验证随机能力和固定路径，只允许取得一次凭据。"""
        with self.server.lock:
            valid = (
                self.path == "/session-input"
                and secrets.compare_digest(
                    self.headers.get("X-MoviePilot-Live-Test", ""), self.server.nonce
                )
                and self.server.payload is not None
            )
            data = json.dumps(self.server.payload).encode() if valid else b"{}"
            self.server.payload = None if valid else self.server.payload
        self.send_response(200 if valid else 403)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def next_page_identities(username, password, port=3001):
    """只读获取真实下一页标识，用来独立确认 UI 自动翻页，令牌不离开本函数。"""
    base = backend_api_base(port)
    body = urlencode({"username": username, "password": password}).encode()
    request = Request(
        base + "login/access-token", data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urlopen(request, timeout=20) as response:
        token = json.load(response)["access_token"]
    request = Request(
        base + "discover/tmdb_movies?page=2",
        headers={"Authorization": "Bearer " + token},
    )
    with urlopen(request, timeout=45) as response:
        rows = json.load(response)["data"]
    return [
        "|".join((
            item.get("media_source") or "themoviedb",
            str(item.get("media_id") or item["tmdb_id"]),
            item.get("type") or "电影",
        ))
        for item in rows
    ]


def backend_api_base(port):
    """构造固定 IPv4 loopback 的 API 地址，不接受任意服务器或局域网目标。"""
    if not isinstance(port, int) or not (1024 <= port <= 65535):
        raise ValueError("验收只允许连接本机动态端口。")
    return f"http://127.0.0.1:{port}/api/v1/"


def main():
    """运行已构建的原生 UI 测试，仅保留业务截图和无凭据的通过/失败摘要。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target", choices=("media", "plugins"), default="media")
    parser.add_argument("--backend-port", type=int, default=3001)
    parser.add_argument("--username", default="admin")
    args = parser.parse_args()
    backend_url = backend_api_base(args.backend_port).removesuffix("api/v1/")
    output = args.output.resolve()
    permitted = (
        Path("/Volumes/DISK/TmpBuild").resolve(),
        Path.home() / "Library/Caches/MoviePilotSimulator",
    )
    if not any(output.is_relative_to(root) for root in permitted):
        raise SystemExit("验收产物只能位于外置任务目录或专用模拟器缓存。")
    output.mkdir(parents=True, exist_ok=False)
    username = args.username
    password = getpass.getpass("Backend password (hidden): ")
    identities = (
        next_page_identities(username, password, port=args.backend_port)
        if args.target == "media" else []
    )
    server = SessionInputServer({
        "username": username, "password": password, "nextPageIdentities": identities,
        "backendURL": backend_url,
    })
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    raw = output / "raw.xcresult"
    exported = output / "attachments"
    environment = dict(os.environ)
    environment["TEST_RUNNER_MOVIEPILOT_NATIVE_V2_LIVE_INPUT_PORT"] = str(server.server_port)
    environment["TEST_RUNNER_MOVIEPILOT_NATIVE_V2_LIVE_NONCE"] = server.nonce
    environment["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    environment["TMPDIR"] = str(args.derived_data.resolve().parent / "tmp")
    command = [
        "xcodebuild", "-project", "ios/MoviePilot.xcodeproj", "-scheme", "MoviePilot",
        "-destination", "platform=iOS Simulator,id=" + args.device,
        "-derivedDataPath", str(args.derived_data), "-clonedSourcePackagesDirPath",
        "/Volumes/DISK/Xcode/SourcePackages", "-resultBundlePath", str(raw),
        "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
        "-maximum-test-execution-time-allowance", "600",
        "-only-testing:MoviePilotUITests/NativeV2EntryTests/" + (
            "testLiveBackendReadOnlyMediaScreens"
            if args.target == "media" else "testLivePluginFormsAndVueSheetTakeover"
        ),
        "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES", "test-without-building",
    ]
    try:
        # 原始输出只留内存，避免 XCTest 的输入活动包含账号或密码。
        result = subprocess.run(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        summary = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(raw), "--format", "json"],
            env=environment, capture_output=True, text=True, check=True,
        )
        tests = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(raw)],
            env=environment, capture_output=True, text=True, check=True,
        )
        value = json.loads(summary.stdout)
        test_tree = json.loads(tests.stdout)
        evidence = {key: value.get(key) for key in ("result", "passedTests", "failedTests", "skippedTests")}
        evidence["backend"] = backend_url
        evidence["failedTestIds"] = [
            item.get("testIdentifierString")
            for item in value.get("testFailures", [])
            if isinstance(item.get("testIdentifierString"), str)
        ]
        evidence["failureDetails"] = [
            re.sub(r"(?i)bearer\s+[A-Za-z0-9._-]+", "Bearer [redacted]", detail)
            .replace(username, "[redacted]")
            .replace(password, "[redacted]")[:1200]
            for item in value.get("testFailures", [])
            if isinstance(item.get("failureText"), str)
            for detail in [item["failureText"]]
        ]
        def collect_source_lines(node):
            """仅收集 UI 测试自身的失败源码行号，避免输出 XCTest 活动内容。"""
            source = node.get("sourceLocation", {})
            path = source.get("filePath", "")
            line = source.get("lineNumber")
            lines = [line] if (
                node.get("result") == "Failed"
                and path.endswith("NativeV2EntryTests.swift")
                and isinstance(line, int)
            ) else []
            for child in node.get("children", []):
                lines.extend(collect_source_lines(child))
            return lines

        source_lines = {
            line
            for node in test_tree.get("testNodes", [])
            for line in collect_source_lines(node)
        }
        log_text = result.stdout.decode("utf-8", errors="replace")
        source_lines.update(
            int(line)
            for line in re.findall(
                r"NativeV2EntryTests\.swift:(\d+):\s+error:", log_text
            )
        )
        source_lines.update(
            int(match.group(1))
            for item in value.get("testFailures", [])
            if isinstance(item.get("failureText"), str)
            for match in [re.search(r"NativeV2EntryTests\.swift:(\d+)", item["failureText"])]
            if match is not None
        )
        evidence["failedSourceLines"] = sorted(source_lines)
        (output / "summary.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(raw), "--output-path", str(exported)],
            env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True,
        )
        if args.target == "media":
            for row in json.loads((exported / "manifest.json").read_text()):
                for attachment in row.get("attachments", []):
                    name = attachment.get("suggestedHumanReadableName", "")
                    if name.startswith("native-v2-live-") and name.endswith(".png"):
                        shutil.copy2(exported / attachment["exportedFileName"], output / (name.split("_")[0] + ".png"))
        print(json.dumps(evidence, ensure_ascii=False), flush=True)
    finally:
        server.payload = None
        server.shutdown()
        server.server_close()
        thread.join()
        username = password = None
        shutil.rmtree(raw, ignore_errors=True)
        shutil.rmtree(exported, ignore_errors=True)
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
