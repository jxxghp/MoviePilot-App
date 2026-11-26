#!/usr/bin/env python3
"""在专用模拟器运行 API-only 回归，复用已签名构建并清理本次设备和缓存。"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from urllib.request import urlopen


def run(*args, **kwargs):
    """使用调用方 Xcode 环境运行一条命令，失败时保留原始退出状态。"""
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    """复用 Products 并在专用设备验证登录、权限、Agent、用户编辑与日志快照。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--only-test", action="append", help="只重跑指定用例；缺省执行全部 smoke")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    parent = Path(os.environ["RUNNER_TEMP"]) if os.environ.get("CI") else Path.home() / "Library/Caches/MoviePilotSimulator"
    parent.mkdir(parents=True, exist_ok=True)
    scratch = Path(tempfile.mkdtemp(prefix="api-smoke-", dir=parent))
    simulator = None
    fixture = None
    fixture_log = None
    try:
        # 模拟器安装器不能读取部分外置卷；只复制 Products，避免再次编译。
        products = scratch / "Products"
        shutil.copytree(args.derived_data.resolve() / "Build/Products", products, symlinks=True)
        runs = list(products.glob("*.xctestrun"))
        if len(runs) != 1:
            raise RuntimeError("需要唯一的 build-for-testing xctestrun 产物")
        runtimes = json.loads(run("xcrun", "simctl", "list", "runtimes", "--json", capture_output=True).stdout)["runtimes"]
        available = [r for r in runtimes if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                     and any(d["identifier"] == "com.apple.CoreSimulator.SimDeviceType.iPhone-17" for d in r.get("supportedDeviceTypes", []))]
        runtime = max(available, key=lambda r: tuple(int(n) for n in r["version"].split(".")))
        simulator = run("xcrun", "simctl", "create", f"MoviePilot-API-Smoke-{os.getpid()}",
                        "com.apple.CoreSimulator.SimDeviceType.iPhone-17", runtime["identifier"], capture_output=True).stdout.strip()
        run("xcrun", "simctl", "boot", simulator)
        run("xcrun", "simctl", "bootstatus", simulator, "-b")
        run("xcrun", "simctl", "spawn", simulator, "defaults", "write", "com.apple.Accessibility", "ReduceMotionEnabled", "-bool", "YES")
        # 端口被占用时直接失败，不能接入或停止其他任务的服务。
        import socket
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 5330))
        fixture_log = (output / "fixture.log").open("w")
        fixture = subprocess.Popen([os.environ.get("PYTHON", "python3"), str(root / "tools/ios/native-v2-fixture.py"), "--port", "5330"],
                                   stdout=fixture_log, stderr=subprocess.STDOUT)
        for _ in range(100):
            if fixture.poll() is not None:
                raise RuntimeError("专用 API 夹具启动失败")
            try:
                with urlopen("http://127.0.0.1:5330/__native/stats", timeout=1):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("专用 API 夹具就绪超时")
        tests = ["testNativeAgentChatStreamAndSessionHistory", "testNativeBusinessHidesUnpermittedEntries",
                 "testOTPAndSessionNotRemembered", "testUserEditorPreservesUneditedFields",
                 "testPluginLogSnapshotLoadsRefreshesAndRetries", "testNativeDiagnosticsAndShortcutsTools"]
        if args.only_test:
            if set(args.only_test) - set(tests):
                raise ValueError("只能选择已声明的 smoke 用例")
            tests = list(dict.fromkeys(args.only_test))
        result = scratch / "smoke.xcresult"
        command = ["xcodebuild", "test-without-building", "-xctestrun", str(runs[0]),
                   "-destination", f"platform=iOS Simulator,id={simulator}", "-parallel-testing-enabled", "NO", "-maximum-test-execution-time-allowance", "240",
                   "-clonedSourcePackagesDirPath", "/Volumes/DISK/Xcode/SourcePackages" if Path("/Volumes/DISK").is_dir() else str(parent / "SourcePackages"),
                   "-resultBundlePath", str(result)]
        command += [f"-only-testing:MoviePilotUITests/NativeV2EntryTests/{test}" for test in tests]
        environment = dict(os.environ, TEST_RUNNER_MOVIEPILOT_NATIVE_V2_E2E="1")
        completed = subprocess.run(command, env=environment, check=False)
        if not result.exists():
            raise RuntimeError("模拟器没有生成测试结果，不能视为通过")
        summary = run("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result), capture_output=True).stdout
        (output / "summary.json").write_text(summary)
        counts = json.loads(summary)
        if completed.returncode or counts.get("passedTests") != len(tests) or counts.get("totalTestCount") != len(tests):
            shutil.copytree(result, output / f"failed-{os.getpid()}.xcresult")
            if not completed.returncode:
                raise RuntimeError("API 回归未完整执行全部测试")
        if completed.returncode:
            raise SystemExit(completed.returncode)
    finally:
        if fixture is not None:
            fixture.terminate()
            fixture.wait(timeout=10)
        if fixture_log is not None:
            fixture_log.close()
        if simulator:
            subprocess.run(["xcrun", "simctl", "shutdown", simulator], check=False)
            subprocess.run(["xcrun", "simctl", "delete", simulator], check=False)
        shutil.rmtree(scratch)


if __name__ == "__main__":
    main()
