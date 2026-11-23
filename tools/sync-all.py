#!/usr/bin/env python3
"""一键同步 VERSION/Design Tokens/L10n/Assets 到三端，并支持 --check 作为 CI 门禁。"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
ROOT = TOOLS_DIR.parent


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, TOOLS_DIR / filename)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def sync_all(root: Path = ROOT, check: bool = False) -> list[str]:
    drifted: list[str] = []
    drifted.extend(_load("sync_tokens", "sync-tokens.py").sync_tokens(root, check=check))
    drifted.extend(_load("sync_l10n", "sync-l10n.py").sync_l10n(root, check=check))
    drifted.extend(_load("sync_assets", "sync-assets.py").sync_assets(root, check=check))
    drifted.extend(_load("sync_version", "sync-version.py").sync_version(root, check=check))
    return drifted


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="仅检查所有 SSOT 产物是否同步")
    args = parser.parse_args(argv)
    drifted = sync_all(ROOT, check=args.check)
    if drifted:
        print(f"检测到 {len(drifted)} 处未同步产物：", ", ".join(drifted[:10]), file=sys.stderr)
        return 1
    print("SSOT 同步校验全部通过。" if args.check else "SSOT 已同步至三端。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
