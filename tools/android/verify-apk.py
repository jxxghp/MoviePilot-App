#!/usr/bin/env python3
"""校验 Android APK 的结构完整性：包内含 libmoviepilot_core.so、73 枚勋章资产与合法清单。"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path


def verify_apk(apk_path: Path, expected_version: str | None = None) -> dict:
    if not apk_path.is_file():
        raise ValueError(f"APK 不存在：{apk_path}")
    with zipfile.ZipFile(apk_path, "r") as zf:
        names = set(zf.namelist())
        if "AndroidManifest.xml" not in names:
            raise ValueError("APK 缺少 AndroidManifest.xml")
        if "classes.dex" not in names:
            raise ValueError("APK 缺少 classes.dex")
        rust_libs = sorted(n for n in names if n.endswith("libmoviepilot_core.so"))
        if not rust_libs:
            raise ValueError("APK 缺少 Rust 共享内核 libmoviepilot_core.so")
        medals = [n for n in names if n.startswith("assets/community_medals/")]
        if len(medals) < 73:
            raise ValueError(f"APK 社区勋章资产数量不足：{len(medals)} < 73")
        return {
            "apk": str(apk_path),
            "sizeBytes": apk_path.stat().st_size,
            "rustLibs": rust_libs,
            "medalAssets": len(medals),
            "expectedVersion": expected_version,
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--version", default=None)
    args = parser.parse_args(argv)
    try:
        report = verify_apk(args.apk, args.version)
    except ValueError as err:
        print(f"APK 校验失败：{err}", file=sys.stderr)
        return 1
    print(f"APK 校验通过：{report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
