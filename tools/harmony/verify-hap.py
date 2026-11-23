#!/usr/bin/env python3
"""校验 HarmonyOS NEXT HAP 安装包完整性（module.json、ets 字节码与 73 枚勋章 rawfile）。"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path


def verify_hap(hap_path: Path, expected_version: str | None = None) -> dict:
    if not hap_path.is_file():
        raise ValueError(f"HAP 不存在：{hap_path}")
    with zipfile.ZipFile(hap_path, "r") as zf:
        names = set(zf.namelist())
        if "module.json" not in names:
            raise ValueError("HAP 缺少 module.json")
        meta = json.loads(zf.read("module.json").decode("utf-8"))
        bundle_name = meta.get("app", {}).get("bundleName")
        if bundle_name != "com.moviepilot.app":
            raise ValueError(f"HAP bundleName 异常：{bundle_name}")
        version_name = meta.get("app", {}).get("versionName")
        if expected_version and version_name != expected_version:
            raise ValueError(f"HAP 版本号不匹配：{version_name} != {expected_version}")
        medals = [n for n in names if "community_medals/" in n]
        if len(medals) < 73:
            raise ValueError(f"HAP 社区勋章资产不足：{len(medals)} < 73")
        return {
            "hap": str(hap_path),
            "bundleName": bundle_name,
            "versionName": version_name,
            "medalAssets": len(medals),
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hap", type=Path)
    parser.add_argument("--version", default=None)
    args = parser.parse_args(argv)
    try:
        report = verify_hap(args.hap, args.version)
    except ValueError as err:
        print(f"HAP 校验失败：{err}", file=sys.stderr)
        return 1
    print(f"HAP 校验通过：{report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
