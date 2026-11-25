#!/usr/bin/env python3
"""将本地联邦插件运行时壳 shared/plugin-shell 同步至三端资源目录，支持从前端产物导入与 --check 门禁。"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_NAME = "manifest.json"
ALLOWED_ROOT_FILES = {"plugin-shell.html", "remoteEntry.js"}
ALLOWED_SUBDIRS = {"assets"}

PLATFORM_TARGETS = (
    "ios/MoviePilot/Resources/PluginShell",
    "android/core-plugin-host/src/main/assets/plugin_shell",
    "harmony/entry/src/main/resources/rawfile/plugin_shell",
)


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect_shell_files(directory: Path) -> dict[str, Path]:
    """收集壳目录内所有受管文件（排除 .DS_Store 与 manifest.json）。"""
    result: dict[str, Path] = {}
    if not directory.is_dir():
        return result
    for path in sorted(directory.rglob("*")):
        if not path.is_file() or path.name in (".DS_Store", MANIFEST_NAME):
            continue
        rel = path.relative_to(directory).as_posix()
        result[rel] = path
    return result


def build_manifest(ssot_dir: Path, shell_version: str | None = None) -> dict:
    """基于 shared/plugin-shell 文件生成确定性 SHA-256 清单。"""
    files = collect_shell_files(ssot_dir)
    if "plugin-shell.html" not in files:
        raise RuntimeError(f"缺少入口文件：{ssot_dir / 'plugin-shell.html'}")
    entries: dict[str, dict[str, object]] = {}
    combined_hasher = hashlib.sha256()
    for rel, path in sorted(files.items()):
        digest = file_digest(path)
        size = path.stat().st_size
        entries[rel] = {"sha256": digest, "size": size}
        combined_hasher.update(f"{rel}:{digest}\n".encode("utf-8"))
    bundle_hash = combined_hasher.hexdigest()[:16]
    return {
        "schemaVersion": 1,
        "protocol": "moviepilot.pluginHost",
        "protocolMajor": 2,
        "shellVersion": shell_version or bundle_hash,
        "bundleHash": bundle_hash,
        "entry": "plugin-shell.html",
        "files": entries,
    }


def import_from_frontend(source_dir: Path, root: Path = ROOT, shell_version: str | None = None) -> dict:
    """从 MoviePilot-Frontend/dist-plugin-shell 导入极简运行时产物到 shared/plugin-shell。"""
    src = source_dir.resolve()
    if not (src / "plugin-shell.html").is_file():
        raise FileNotFoundError(f"前端构建产物中未找到 plugin-shell.html：{src}")

    ssot_dir = root / "shared/plugin-shell"
    if ssot_dir.exists():
        shutil.rmtree(ssot_dir)
    ssot_dir.mkdir(parents=True, exist_ok=True)

    for name in sorted(ALLOWED_ROOT_FILES):
        candidate = src / name
        if candidate.is_file():
            shutil.copy2(candidate, ssot_dir / name)

    for subdir in sorted(ALLOWED_SUBDIRS):
        candidate_dir = src / subdir
        if candidate_dir.is_dir():
            for item in sorted(candidate_dir.rglob("*")):
                if not item.is_file() or item.name == ".DS_Store":
                    continue
                rel = item.relative_to(src)
                dst = ssot_dir / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, dst)

    manifest = build_manifest(ssot_dir, shell_version=shell_version)
    (ssot_dir / MANIFEST_NAME).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return manifest


def _sync_dir(ssot_dir: Path, dst_dir: Path, check: bool, drifted: list[str], root: Path) -> None:
    expected_files = collect_shell_files(ssot_dir)
    manifest_src = ssot_dir / MANIFEST_NAME
    if manifest_src.is_file():
        expected_files[MANIFEST_NAME] = manifest_src

    existing_files: dict[str, Path] = {}
    if dst_dir.is_dir():
        for path in sorted(dst_dir.rglob("*")):
            if not path.is_file() or path.name == ".DS_Store":
                continue
            existing_files[path.relative_to(dst_dir).as_posix()] = path

    # 删除已失效的旧 hash chunk
    for stale_rel, stale_path in sorted(existing_files.items()):
        if stale_rel not in expected_files:
            if check:
                drifted.append(str(stale_path.relative_to(root)))
            else:
                stale_path.unlink()

    # 拷贝或校验缺失/变更文件
    for rel, src_path in sorted(expected_files.items()):
        dst_path = dst_dir / rel
        if dst_path.is_file() and file_digest(src_path) == file_digest(dst_path):
            continue
        if check:
            drifted.append(str(dst_path.relative_to(root)))
        else:
            dst_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_path, dst_path)

    # 清理空子目录
    if not check and dst_dir.is_dir():
        for sub in sorted(dst_dir.rglob("*"), reverse=True):
            if sub.is_dir() and not any(sub.iterdir()):
                sub.rmdir()


def sync_plugin_shell(root: Path = ROOT, check: bool = False) -> list[str]:
    """校验 shared/plugin-shell 清单并将其同步至 iOS / Android / HarmonyOS。"""
    drifted: list[str] = []
    ssot_dir = root / "shared/plugin-shell"
    manifest_path = ssot_dir / MANIFEST_NAME
    if not ssot_dir.is_dir() or not manifest_path.is_file():
        drifted.append("shared/plugin-shell/manifest.json")
        return drifted

    recorded = json.loads(manifest_path.read_text(encoding="utf-8"))
    computed = build_manifest(ssot_dir, shell_version=recorded.get("shellVersion"))
    if recorded != computed:
        if check:
            drifted.append("shared/plugin-shell/manifest.json")
        else:
            manifest_path.write_text(
                json.dumps(computed, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

    for rel_target in PLATFORM_TARGETS:
        _sync_dir(ssot_dir, root / rel_target, check, drifted, root)

    return drifted


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--import-from",
        type=Path,
        default=None,
        help="从前端构建产物目录（如 ../MoviePilot-Frontend/dist-plugin-shell）导入并同步至三端",
    )
    parser.add_argument(
        "--shell-version",
        type=str,
        default=None,
        help="可选覆盖清单中的 shellVersion 字段",
    )
    parser.add_argument("--check", action="store_true", help="仅检查三端 plugin-shell 产物与清单是否零漂移")
    args = parser.parse_args(argv)

    if args.import_from is not None:
        manifest = import_from_frontend(args.import_from, ROOT, shell_version=args.shell_version)
        print(
            f"已导入 plugin-shell（bundleHash={manifest['bundleHash']}, files={len(manifest['files'])}）。"
        )

    drifted = sync_plugin_shell(ROOT, check=args.check)
    if drifted:
        print(
            f"plugin-shell 运行时壳产物未同步（共 {len(drifted)} 项，示例：{drifted[:5]}）",
            file=sys.stderr,
        )
        return 1
    if not args.check:
        print("plugin-shell 已同步至 iOS / Android / HarmonyOS。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
