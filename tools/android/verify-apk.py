#!/usr/bin/env python3
"""校验 Android APK 的完整性：含 libmoviepilot_core.so、ABI 对齐（防 JNA UnsatisfiedLinkError）、签名块与共享资产。"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

MAX_RUST_SO_BYTES = 6 * 1024 * 1024


def verify_apk(
    apk_path: Path,
    expected_version: str | None = None,
    expected_abis: list[str] | None = None,
) -> dict:
    if not apk_path.is_file():
        raise ValueError(f"APK 不存在：{apk_path}")
    with zipfile.ZipFile(apk_path, "r") as zf:
        names = set(zf.namelist())
        if "AndroidManifest.xml" not in names:
            raise ValueError("APK 缺少 AndroidManifest.xml")
        if "classes.dex" not in names:
            raise ValueError("APK 缺少 classes.dex")

        # 校验所有打包进 lib/<abi>/ 的目录都必须包含 libmoviepilot_core.so，杜绝混合 ABI 导致 UnsatisfiedLinkError
        abi_dirs = sorted({n.split("/")[1] for n in names if n.startswith("lib/") and len(n.split("/")) >= 3})
        rust_libs = sorted(n for n in names if n.endswith("/libmoviepilot_core.so"))
        if not rust_libs:
            raise ValueError("APK 缺少 Rust 共享内核 libmoviepilot_core.so")

        rust_abis = sorted({n.split("/")[1] for n in rust_libs})
        if abi_dirs != rust_abis:
            raise ValueError(
                f"APK 存在未包含 libmoviepilot_core.so 的多余 ABI 目录（会导致装机闪退）：lib={abi_dirs}, rust={rust_abis}"
            )
        if expected_abis and sorted(expected_abis) != rust_abis:
            raise ValueError(f"APK ABI 列表与期望不符：{rust_abis} != {sorted(expected_abis)}")

        for so_name in rust_libs:
            so_size = zf.getinfo(so_name).file_size
            if so_size > MAX_RUST_SO_BYTES:
                raise ValueError(f"{so_name} 体积超出上限（{so_size} > {MAX_RUST_SO_BYTES}）")

        medals = [n for n in names if n.startswith("assets/community_medals/")]
        if len(medals) < 73:
            raise ValueError(f"APK 社区勋章资产数量不足：{len(medals)} < 73")

        logos = {Path(n).stem for n in names if n.startswith("res/") and "logo_" in Path(n).name}
        if "resources.arsc" in names:
            arsc_bytes = zf.read("resources.arsc")
            logos |= {m.decode("ascii") for m in re.findall(rb"logo_[a-z0-9_]+", arsc_bytes)}
        if len(logos) < 36:
            raise ValueError(f"APK 服务品牌 Logo 资源不足：{len(logos)} < 36")

        # 校验已签名（V1 META-INF 或 APK Signature Block v2/v3）
        has_v1_sig = any(n.startswith("META-INF/") and n.endswith((".RSA", ".DSA", ".EC")) for n in names)
        raw_bytes = apk_path.read_bytes()
        has_v2_sig = b"APK Sig Block 42" in raw_bytes
        if not (has_v1_sig or has_v2_sig):
            raise ValueError("APK 未签名，无法在 Android 设备直接安装")

        if expected_version and expected_version.encode("utf-8") not in raw_bytes and expected_version.encode("utf-16le") not in raw_bytes:
            # 二进制 AXML 字符串池通常以 UTF-8 或 UTF-16LE 存储 versionName
            ManifestBytes = zf.read("AndroidManifest.xml")
            if expected_version.encode("utf-8") not in ManifestBytes and expected_version.encode("utf-16le") not in ManifestBytes:
                raise ValueError(f"AndroidManifest.xml 未检测到期望版本号：{expected_version}")

        return {
            "apk": str(apk_path),
            "sizeBytes": apk_path.stat().st_size,
            "abis": rust_abis,
            "medalAssets": len(medals),
            "logoAssets": len(logos),
            "signedV2": has_v2_sig,
            "expectedVersion": expected_version,
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--version", default=None)
    parser.add_argument("--abis", default=None, help="期望包含的逗号分隔 ABI 列表")
    args = parser.parse_args(argv)
    expected_abis = [a.strip() for a in args.abis.split(",") if a.strip()] if args.abis else None
    try:
        report = verify_apk(args.apk, args.version, expected_abis)
    except ValueError as err:
        print(f"APK 校验失败：{err}", file=sys.stderr)
        return 1
    print(f"APK 校验通过：{report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
