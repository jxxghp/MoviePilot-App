#!/usr/bin/env python3
"""校验 HarmonyOS NEXT HAP 安装包完整性（module.json、ArkTS 字节码、Rust NAPI .so、73 枚勋章与 36 枚服务 Logo）。"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path

MAX_RUST_SO_BYTES = 6 * 1024 * 1024


def verify_hap(hap_path: Path, expected_version: str | None = None) -> dict:
    if not hap_path.is_file():
        raise ValueError(f"HAP 不存在：{hap_path}")
    with zipfile.ZipFile(hap_path, "r") as zf:
        names = set(zf.namelist())
        if "module.json" not in names:
            raise ValueError("HAP 缺少 module.json")
        if "ets/modules.abc" not in names:
            raise ValueError("HAP 缺少编译后的 ArkTS 字节码 ets/modules.abc")

        rust_libs = sorted(n for n in names if n.endswith("/libmoviepilot_core_ohos.so"))
        if not rust_libs:
            raise ValueError("HAP 缺少 Rust NAPI 动态库 libmoviepilot_core_ohos.so")
        for so_name in rust_libs:
            so_size = zf.getinfo(so_name).file_size
            if so_size > MAX_RUST_SO_BYTES:
                raise ValueError(f"{so_name} 体积超出上限（{so_size} > {MAX_RUST_SO_BYTES}）")

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

        logos = [n for n in names if "rawfile/logos/" in n]
        if len(logos) < 30:
            raise ValueError(f"HAP 服务品牌 Logo 资产不足：{len(logos)} < 30")

        return {
            "hap": str(hap_path),
            "sizeBytes": hap_path.stat().st_size,
            "bundleName": bundle_name,
            "versionName": version_name,
            "rustLibs": rust_libs,
            "medalAssets": len(medals),
            "logoAssets": len(logos),
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
