#!/usr/bin/env python3
"""将 shared/assets/{brand,logos,community-medals} 同步至 Android 与鸿蒙资源目录。"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def android_res_name(filename: str) -> str:
    """将文件名规范为 Android drawable 合法小写下划线名称。"""
    stem = Path(filename).stem.lower().replace("-", "_")
    suffix = Path(filename).suffix.lower()
    return f"{stem}{suffix}"


def sync_file(src: Path, dst: Path, check: bool, drifted: list[str], root: Path) -> None:
    if dst.exists() and file_digest(src) == file_digest(dst):
        return
    if check:
        drifted.append(str(dst.relative_to(root)))
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)


def sync_assets(root: Path = ROOT, check: bool = False) -> list[str]:
    """同步品牌图标、平台 Logo 与 73 个社区勋章资产。"""
    drifted: list[str] = []
    assets = root / "shared/assets"

    # Brand PNGs & Logos PNGs
    for src_dir in [assets / "brand", assets / "logos"]:
        if not src_dir.is_dir():
            continue
        for src in sorted(src_dir.iterdir()):
            if not src.is_file() or src.name == ".DS_Store":
                continue
            if src.suffix.lower() in (".png", ".webp", ".jpg"):
                res_name = android_res_name(src.name)
                sync_file(src, root / "android/app/src/main/res/drawable" / res_name, check, drifted, root)
                sync_file(src, root / "harmony/entry/src/main/resources/base/media" / res_name, check, drifted, root)

    # Community medals (73 .webp + .outline.json)
    medals_dir = assets / "community-medals"
    if medals_dir.is_dir():
        for src in sorted(medals_dir.iterdir()):
            if not src.is_file() or src.name == ".DS_Store":
                continue
            sync_file(src, root / "android/app/src/main/assets/community_medals" / src.name, check, drifted, root)
            sync_file(src, root / "harmony/entry/src/main/resources/rawfile/community_medals" / src.name, check, drifted, root)

    return drifted


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="仅检查资产是否已同步")
    args = parser.parse_args(argv)
    drifted = sync_assets(ROOT, check=args.check)
    if drifted:
        print(f"静态资产未同步（共 {len(drifted)} 项，示例：{drifted[:5]}）", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
