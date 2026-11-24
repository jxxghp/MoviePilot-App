#!/usr/bin/env python3
"""将根 VERSION 与 BUILD_NUMBER 同步到 iOS / Android / 鸿蒙三端工程配置。"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_version_info(root: Path = ROOT) -> tuple[str, int]:
    """读取根 VERSION（MAJOR.MINOR.PATCH）与可选 BUILD_NUMBER（缺省为 1）。"""
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError(f"VERSION 必须符合 MAJOR.MINOR.PATCH 格式，当前值：{version!r}")
    build_file = root / "BUILD_NUMBER"
    if not build_file.exists():
        return version, 1
    build_raw = build_file.read_text(encoding="utf-8").strip()
    if not build_raw.isdigit() or int(build_raw) <= 0:
        raise ValueError(f"BUILD_NUMBER 必须为正整数，当前值：{build_raw!r}")
    return version, int(build_raw)


def version_code_from_semver(version: str, build_number: int) -> int:
    """生成单调递增的 Android/鸿蒙整型版本号（major*1000000 + minor*10000 + patch*100 + build）。"""
    major, minor, patch = (int(part) for part in version.split("."))
    return major * 1_000_000 + minor * 10_000 + patch * 100 + build_number


def apply_or_check(path: Path, new_text: str, check: bool, drifted: list[str]) -> None:
    """写入文件或在 --check 模式下记录漂移。"""
    old_text = path.read_text(encoding="utf-8") if path.exists() else None
    if old_text == new_text:
        return
    if check:
        drifted.append(str(path.relative_to(ROOT)))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(new_text, encoding="utf-8")


def sync_version(root: Path = ROOT, check: bool = False) -> list[str]:
    """同步三端版本号并返回 --check 模式下的漂移路径列表。"""
    version, build_number = read_version_info(root)
    version_code = version_code_from_semver(version, build_number)
    drifted: list[str] = []

    # 1. iOS project.yml
    ios_yml = root / "ios/project.yml"
    if ios_yml.exists():
        text = ios_yml.read_text(encoding="utf-8")
        text = re.sub(r"(MARKETING_VERSION:\s*).*", rf"\g<1>{version}", text)
        text = re.sub(r"(CURRENT_PROJECT_VERSION:\s*).*", rf"\g<1>{build_number}", text)
        apply_or_check(ios_yml, text, check, drifted)

    # 2. Android gradle.properties (若 android 目录存在则同步)
    android_props = root / "android/gradle.properties"
    if (root / "android").is_dir() or android_props.exists():
        lines = android_props.read_text(encoding="utf-8").splitlines() if android_props.exists() else [
            "org.gradle.jvmargs=-Xmx3072m -Dfile.encoding=UTF-8",
            "android.useAndroidX=true",
            "kotlin.code.style=official",
            "android.nonTransitiveRClass=true",
        ]
        updated = []
        seen = set()
        kv = {
            "MOVIEPILOT_VERSION_NAME": version,
            "MOVIEPILOT_VERSION_CODE": str(version_code),
            "MOVIEPILOT_BUILD_NUMBER": str(build_number),
        }
        for line in lines:
            matched = False
            for k, v in kv.items():
                if line.startswith(f"{k}="):
                    updated.append(f"{k}={v}")
                    seen.add(k)
                    matched = True
                    break
            if not matched:
                updated.append(line)
        for k, v in kv.items():
            if k not in seen:
                updated.append(f"{k}={v}")
        apply_or_check(android_props, "\n".join(updated) + "\n", check, drifted)

    # 3. HarmonyOS AppScope/app.json5 (若 harmony 目录存在则同步)
    harmony_app = root / "harmony/AppScope/app.json5"
    if harmony_app.exists():
        data = json.loads(harmony_app.read_text(encoding="utf-8"))
        data.setdefault("app", {})
        data["app"]["versionCode"] = version_code
        data["app"]["versionName"] = version
        apply_or_check(harmony_app, json.dumps(data, ensure_ascii=False, indent=2) + "\n", check, drifted)

    # 4. Rust workspace Cargo.toml
    cargo_toml = root / "shared/core-rust/Cargo.toml"
    if cargo_toml.exists():
        cargo_text = cargo_toml.read_text(encoding="utf-8")
        cargo_text = re.sub(
            r'(\[workspace\.package\]\s*\nversion\s*=\s*")[^"]+(")',
            rf"\g<1>{version}\2",
            cargo_text,
            count=1,
        )
        apply_or_check(cargo_toml, cargo_text, check, drifted)

    return drifted


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="仅检查版本是否已同步，不修改文件")
    args = parser.parse_args(argv)
    drifted = sync_version(ROOT, check=args.check)
    if drifted:
        print("版本号未同步：", ", ".join(drifted), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
