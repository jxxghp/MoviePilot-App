#!/usr/bin/env python3
"""从 shared/l10n/*.strings.json 生成 Android strings.xml 与鸿蒙 string.json，并校验 iOS 词条一致性。"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]


def stable_key_id(raw_key: str, prefix: str = "mp_") -> str:
    """将任意中文/标点词条键映射为合法且稳定的标识符。"""
    ascii_part = re.sub(r"[^a-zA-Z0-9]+", "_", raw_key).strip("_").lower()[:24]
    digest = hashlib.sha1(raw_key.encode("utf-8")).hexdigest()[:8]
    return f"{prefix}{ascii_part}_{digest}" if ascii_part else f"{prefix}{digest}"


def to_android_format(text: str) -> str:
    """将 Apple %@ 格式占位符转换为 Android %1$s / %2$s 并转义 XML 特殊字符。"""
    count = 0
    def repl(_m: re.Match[str]) -> str:
        nonlocal count
        count += 1
        return f"%{count}$s"
    converted = re.sub(r"%@", repl, text)
    escaped = escape(converted, {"'": r"\'", '"': r'\"'})
    escaped = escaped.replace("\n", r"\n")
    return escaped


def to_harmony_format(text: str) -> str:
    """将 Apple %@ 占位符转换为鸿蒙 %s 格式。"""
    return text.replace("%@", "%s")


def write_or_check(path: Path, content: str, check: bool, drifted: list[str], root: Path) -> None:
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == content:
        return
    if check:
        drifted.append(str(path.relative_to(root)))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def sync_l10n(root: Path = ROOT, check: bool = False) -> list[str]:
    """生成 Android 与鸿蒙三语种资源文件（iOS 保留原有原始文案键以零回归）。"""
    drifted: list[str] = []
    app_data = json.loads((root / "shared/l10n/app.strings.json").read_text(encoding="utf-8"))["entries"]
    widget_data = json.loads((root / "shared/l10n/widgets.strings.json").read_text(encoding="utf-8"))["entries"]

    merged = {}
    for k, v in app_data.items():
        merged[stable_key_id(k, "mp_")] = v
    for k, v in widget_data.items():
        merged[stable_key_id(k, "mp_widget_")] = v

    # Android values (zh-Hans -> default + zh-rCN, zh-Hant -> zh-rTW, en -> en)
    android_langs = [
        ("values", "zh-Hans"),
        ("values-zh-rCN", "zh-Hans"),
        ("values-zh-rTW", "zh-Hant"),
        ("values-en", "en"),
    ]
    for folder, lang in android_langs:
        lines = [
            '<?xml version="1.0" encoding="utf-8"?>',
            "<!-- 自动生成自 shared/l10n/*.strings.json，请勿手工修改 -->",
            "<resources>",
            '    <string name="app_name">MoviePilot</string>',
        ]
        for key_id in sorted(merged.keys()):
            val = to_android_format(merged[key_id][lang])
            lines.append(f'    <string name="{key_id}" formatted="false">{val}</string>')
        lines.append("</resources>")
        lines.append("")
        write_or_check(
            root / f"android/app/src/main/res/{folder}/strings.xml",
            "\n".join(lines),
            check,
            drifted,
            root,
        )

    # HarmonyOS resources/(base|zh_CN|zh_TW|en_US)/element/string.json
    harmony_langs = [
        ("base", "zh-Hans"),
        ("zh_CN", "zh-Hans"),
        ("zh_TW", "zh-Hant"),
        ("en_US", "en"),
    ]
    for folder, lang in harmony_langs:
        items = [{"name": "app_name", "value": "MoviePilot"}]
        for key_id in sorted(merged.keys()):
            items.append({"name": key_id, "value": to_harmony_format(merged[key_id][lang])})
        payload = json.dumps({"string": items}, ensure_ascii=False, indent=2) + "\n"
        write_or_check(
            root / f"harmony/entry/src/main/resources/{folder}/element/string.json",
            payload,
            check,
            drifted,
            root,
        )

    return drifted


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="仅检查词条生成物是否同步")
    args = parser.parse_args(argv)
    drifted = sync_l10n(ROOT, check=args.check)
    if drifted:
        print("多语言资源未同步：", ", ".join(drifted), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
