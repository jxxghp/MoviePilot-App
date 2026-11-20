#!/usr/bin/env python3
"""交互式验证本机 3001 后端；凭据仅存在内存，原始登录活动结果在取证后销毁。"""

import argparse
import getpass
import json
import os
from pathlib import Path
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


def next_page_identities(username, password):
    """只读获取真实下一页标识，用来独立确认 UI 自动翻页，令牌不离开本函数。"""
    base = "http://127.0.0.1:3001/api/v1/"
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


def main():
    """运行已构建的原生 UI 测试，仅保留业务截图和无凭据的通过/失败摘要。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    permitted = (
        Path("/Volumes/DISK/TmpBuild").resolve(),
        Path.home() / "Library/Caches/MoviePilotSimulator",
    )
    if not any(output.is_relative_to(root) for root in permitted):
        raise SystemExit("验收产物只能位于外置任务目录或专用模拟器缓存。")
    output.mkdir(parents=True, exist_ok=False)
    username = getpass.getpass("Login name (hidden): ")
    password = getpass.getpass("Backend password (hidden): ")
    identities = next_page_identities(username, password)
    server = SessionInputServer({
        "username": username, "password": password, "nextPageIdentities": identities,
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
        "-maximum-test-execution-time-allowance", "420",
        "-only-testing:MoviePilotUITests/NativeV2EntryTests/testLiveBackendReadOnlyMediaScreens",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES", "test-without-building",
    ]
    try:
        # 原始输出只留内存，避免 XCTest 的输入活动包含账号或密码。
        result = subprocess.run(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        summary = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(raw), "--format", "json"],
            env=environment, capture_output=True, text=True, check=True,
        )
        value = json.loads(summary.stdout)
        evidence = {key: value.get(key) for key in ("result", "passedTests", "failedTests", "skippedTests")}
        evidence["backend"] = "http://127.0.0.1:3001/"
        (output / "summary.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(raw), "--output-path", str(exported)],
            env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True,
        )
        for row in json.loads((exported / "manifest.json").read_text()):
            for attachment in row.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName", "")
                if name.startswith("native-v2-live-") and name.endswith(".png"):
                    shutil.copy2(exported / attachment["exportedFileName"], output / (name.split("_")[0] + ".png"))
        print(json.dumps(evidence, ensure_ascii=False), flush=True)
        if result.returncode:
            # 只输出已过滤的失败摘要；调用细节和原始活动不保留。
            failures = [
                line.replace(username, "[user]").replace(password, "[secret]")
                for line in result.stdout.decode(errors="replace").splitlines()
                if "error:" in line or "failed (" in line
            ]
            (output / "failures.txt").write_text("\n".join(failures))
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
