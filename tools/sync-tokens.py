#!/usr/bin/env python3
"""从 shared/design-tokens/*.json 生成 iOS Swift、Android Kotlin 与鸿蒙 ArkTS 视觉 Token 代码。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def parse_hex_argb(hex_str: str) -> tuple[int, int, int, int]:
    """解析 #RRGGBB 或 #AARRGGBB 为 (a, r, g, b) 四元组（0..255）。"""
    cleaned = hex_str.strip().lstrip("#")
    if len(cleaned) == 6:
        a = 255
        r, g, b = int(cleaned[0:2], 16), int(cleaned[2:4], 16), int(cleaned[4:6], 16)
    elif len(cleaned) == 8:
        a = int(cleaned[0:2], 16)
        r, g, b = int(cleaned[2:4], 16), int(cleaned[4:6], 16), int(cleaned[6:8], 16)
    else:
        raise ValueError(f"非法颜色值：{hex_str!r}")
    return a, r, g, b


def hex_to_u32_argb(hex_str: str) -> str:
    a, r, g, b = parse_hex_argb(hex_str)
    return f"0x{a:02X}{r:02X}{g:02X}{b:02X}"


def hex_to_swift_rgba(hex_str: str) -> str:
    a, r, g, b = parse_hex_argb(hex_str)
    return f"UIColor(red: {r/255.0:.4f}, green: {g/255.0:.4f}, blue: {b/255.0:.4f}, alpha: {a/255.0:.4f})"


def hex_to_swift_color(hex_str: str) -> str:
    a, r, g, b = parse_hex_argb(hex_str)
    if a == 255:
        return f"Color(red: {r/255.0:.4f}, green: {g/255.0:.4f}, blue: {b/255.0:.4f})"
    return f"Color(red: {r/255.0:.4f}, green: {g/255.0:.4f}, blue: {b/255.0:.4f}).opacity({a/255.0:.4f})"


def generate_swift(palette: dict, surfaces: dict, layout: dict, icons: dict) -> str:
    """生成 iOS NativeDesignSystem/GeneratedTokens.swift。"""
    lines = [
        "// 自动生成自 shared/design-tokens/*.json，请勿手工修改；请运行 python3 tools/sync-all.py。",
        "import SwiftUI",
        "import UIKit",
        "",
        "/// 三端同源视觉 Token（由 shared/design-tokens 单一事实源自动生成）。",
        "enum GeneratedDesignTokens {",
        "  /// 背景流光色板（深色/浅色四段色点）。",
        "  enum BackgroundStops {",
    ]
    for preset in palette["backgroundPresets"]:
        pid = preset["id"]
        lines.append(f"    static let {pid}Dark: [Color] = [")
        for c in preset["darkStops"]:
            lines.append(f"      {hex_to_swift_color(c)},")
        lines.append("    ]")
        lines.append(f"    static let {pid}Light: [Color] = [")
        for c in preset["lightStops"]:
            lines.append(f"      {hex_to_swift_color(c)},")
        lines.append("    ]")
    lines.append("  }")
    lines.append("")
    lines.append("  /// 主题强调前景色。")
    lines.append("  enum Accents {")
    for acc in palette["accentPresets"]:
        lines.append(f"    static let {acc['id']} = {hex_to_swift_color(acc['hex'])}")
    lines.append("  }")
    lines.append("")
    lines.append("  /// 自适应语义状态色。")
    lines.append("  enum Semantic {")
    for key, pair in palette["semantic"].items():
        lines.append(f"    static let {key} = Color(")
        lines.append("      uiColor: UIColor {")
        lines.append("        $0.userInterfaceStyle == .dark")
        lines.append(f"          ? {hex_to_swift_rgba(pair['dark'])}")
        lines.append(f"          : {hex_to_swift_rgba(pair['light'])}")
        lines.append("      }")
        lines.append("    )")
    lines.append("  }")
    lines.append("")
    lines.append("  /// 玻璃面板与布局圆角/边距常量。")
    lines.append("  enum Metrics {")
    lines.append(f"    static let panelCornerRadius: CGFloat = {surfaces['panel']['cornerRadius']}")
    lines.append(f"    static let panelDefaultPadding: CGFloat = {surfaces['panel']['defaultPadding']}")
    lines.append(f"    static let panelBorderWidth: CGFloat = {surfaces['panel']['borderWidth']}")
    lines.append(f"    static let marginCompact: CGFloat = {layout['margins']['compact']}")
    lines.append(f"    static let marginWide: CGFloat = {layout['margins']['wide']}")
    lines.append(f"    static let marginExpanded: CGFloat = {layout['margins']['expanded']}")
    lines.append(f"    static let ambientFps: Double = {surfaces['ambientGradient']['fps']}")
    lines.append("  }")
    lines.append("")
    lines.append("  /// 跨端语义图标映射（SF Symbols）。")
    lines.append("  static let sfSymbols: [String: String] = [")
    for icon_id, mapping in icons["icons"].items():
        lines.append(f'    "{icon_id}": "{mapping["sf_symbol"]}",')
    lines.append("  ]")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def generate_kotlin(palette: dict, surfaces: dict, layout: dict, icons: dict) -> str:
    """生成 Android design-system GeneratedTokens.kt。"""
    lines = [
        "// 自动生成自 shared/design-tokens/*.json，请勿手工修改；请运行 python3 tools/sync-all.py。",
        "package com.moviepilot.designsystem",
        "",
        "import androidx.compose.ui.graphics.Color",
        "",
        "/** 预设背景渐变色板定义（深色与浅色 4 段色点）。 */",
        "data class BackgroundPresetToken(",
        "    val id: String,",
        "    val titleZh: String,",
        "    val titleEn: String,",
        "    val darkStops: List<Color>,",
        "    val lightStops: List<Color>,",
        ")",
        "",
        "/** 预设主题强调色定义。 */",
        "data class AccentPresetToken(",
        "    val id: String,",
        "    val titleZh: String,",
        "    val titleEn: String,",
        "    val color: Color,",
        "    val hex: String,",
        ")",
        "",
        "/** 自适应深浅色语义色对。 */",
        "data class AdaptiveColorToken(",
        "    val light: Color,",
        "    val dark: Color,",
        ") {",
        "    fun resolve(isDark: Boolean): Color = if (isDark) dark else light",
        "}",
        "",
        "/** 三端同源视觉 Token（由 shared/design-tokens 单一事实源自动生成）。 */",
        "object GeneratedDesignTokens {",
        f'    const val DEFAULT_MODE: String = "{palette["defaults"]["mode"]}"',
        f'    const val DEFAULT_BACKGROUND_PRESET: String = "{palette["defaults"]["backgroundPreset"]}"',
        f'    const val DEFAULT_ACCENT_PRESET: String = "{palette["defaults"]["accentPreset"]}"',
        f'    const val CUSTOM_BG_START_HEX: String = "{palette["defaults"]["customBackgroundStartHex"]}"',
        f'    const val CUSTOM_BG_MID_HEX: String = "{palette["defaults"]["customBackgroundMidHex"]}"',
        f'    const val CUSTOM_BG_END_HEX: String = "{palette["defaults"]["customBackgroundEndHex"]}"',
        f'    const val CUSTOM_ACCENT_HEX: String = "{palette["defaults"]["customAccentHex"]}"',
        f'    const val PANEL_CORNER_RADIUS_DP: Float = {surfaces["panel"]["cornerRadius"]}f',
        f'    const val PANEL_PADDING_DP: Float = {surfaces["panel"]["defaultPadding"]}f',
        f'    const val PANEL_BORDER_WIDTH_DP: Float = {surfaces["panel"]["borderWidth"]}f',
        f'    const val SHEET_CORNER_RADIUS_DP: Float = {surfaces["sheet"]["cornerRadius"]}f',
        f'    const val ANDROID_WINDOW_BLUR_PX: Int = {surfaces["sheet"]["androidWindowBlurRadiusPx"]}',
        f'    const val NAV_BAR_BLUR_DP: Float = {surfaces["navigation"]["androidRenderEffectBlurDp"]}f',
        f'    const val MARGIN_COMPACT_DP: Float = {layout["margins"]["compact"]}f',
        f'    const val MARGIN_WIDE_DP: Float = {layout["margins"]["wide"]}f',
        f'    const val MARGIN_EXPANDED_DP: Float = {layout["margins"]["expanded"]}f',
        f'    const val BREAKPOINT_WIDE_DP: Float = {layout["breakpoints"]["wideCanvas"]}f',
        f'    const val BREAKPOINT_TABLET_SPLIT_DP: Float = {layout["breakpoints"]["tabletSplit"]}f',
        f'    const val BREAKPOINT_EXPANDED_DP: Float = {layout["breakpoints"]["expandedCanvas"]}f',
        f'    const val AMBIENT_FPS: Int = {surfaces["ambientGradient"]["fps"]}',
        "",
        "    val backgroundPresets: List<BackgroundPresetToken> = listOf(",
    ]
    for preset in palette["backgroundPresets"]:
        dark_list = ", ".join(f"Color({hex_to_u32_argb(c)})" for c in preset["darkStops"])
        light_list = ", ".join(f"Color({hex_to_u32_argb(c)})" for c in preset["lightStops"])
        lines.append(
            f'        BackgroundPresetToken("{preset["id"]}", "{preset["titleZh"]}", "{preset["titleEn"]}", listOf({dark_list}), listOf({light_list})),'
        )
    lines.append("    )")
    lines.append("")
    lines.append("    val accentPresets: List<AccentPresetToken> = listOf(")
    for acc in palette["accentPresets"]:
        lines.append(
            f'        AccentPresetToken("{acc["id"]}", "{acc["titleZh"]}", "{acc["titleEn"]}", Color({hex_to_u32_argb(acc["hex"])}), "{acc["hex"]}"),'
        )
    lines.append("    )")
    lines.append("")
    lines.append("    object Semantic {")
    for key, pair in palette["semantic"].items():
        lines.append(
            f"        val {key} = AdaptiveColorToken(light = Color({hex_to_u32_argb(pair['light'])}), dark = Color({hex_to_u32_argb(pair['dark'])}))"
        )
    lines.append("    }")
    lines.append("")
    lines.append("    val materialIcons: Map<String, String> = mapOf(")
    for icon_id, mapping in icons["icons"].items():
        lines.append(f'        "{icon_id}" to "{mapping["material"]}",')
    lines.append("    )")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def generate_arkts(palette: dict, surfaces: dict, layout: dict, icons: dict) -> str:
    """生成鸿蒙 harmony/commons/design_system GeneratedTokens.ets。"""
    lines = [
        "// 自动生成自 shared/design-tokens/*.json，请勿手工修改；请运行 python3 tools/sync-all.py。",
        "",
        "/** 预设背景渐变色板定义（深色与浅色 4 段色点）。 */",
        "export interface BackgroundPresetToken {",
        "  id: string;",
        "  titleZh: string;",
        "  titleEn: string;",
        "  darkStops: string[];",
        "  lightStops: string[];",
        "}",
        "",
        "/** 预设主题强调色定义。 */",
        "export interface AccentPresetToken {",
        "  id: string;",
        "  titleZh: string;",
        "  titleEn: string;",
        "  hex: string;",
        "}",
        "",
        "/** 深浅色自适应语义色对。 */",
        "export interface AdaptiveHexToken {",
        "  light: string;",
        "  dark: string;",
        "}",
        "",
        "/** 鸿蒙端三端同源视觉 Token（由 shared/design-tokens 自动生成）。 */",
        "export class GeneratedDesignTokens {",
        f'  static readonly DEFAULT_MODE: string = \'{palette["defaults"]["mode"]}\';',
        f'  static readonly DEFAULT_BACKGROUND_PRESET: string = \'{palette["defaults"]["backgroundPreset"]}\';',
        f'  static readonly DEFAULT_ACCENT_PRESET: string = \'{palette["defaults"]["accentPreset"]}\';',
        f'  static readonly PANEL_CORNER_RADIUS_VP: number = {surfaces["panel"]["cornerRadius"]};',
        f'  static readonly PANEL_PADDING_VP: number = {surfaces["panel"]["defaultPadding"]};',
        f'  static readonly PANEL_BORDER_WIDTH_VP: number = {surfaces["panel"]["borderWidth"]};',
        f'  static readonly SHEET_CORNER_RADIUS_VP: number = {surfaces["sheet"]["cornerRadius"]};',
        f'  static readonly NAV_BLUR_RADIUS: number = {surfaces["navigation"]["harmonyBackgroundEffectRadius"]};',
        f'  static readonly NAV_BLUR_SATURATION: number = {surfaces["navigation"]["harmonyBackgroundEffectSaturation"]};',
        f'  static readonly NAV_BLUR_BRIGHTNESS: number = {surfaces["navigation"]["harmonyBackgroundEffectBrightness"]};',
        f'  static readonly POINT_LIGHT_CARD_INTENSITY: number = {surfaces["harmonyPointLight"]["cardIntensity"]};',
        f'  static readonly POINT_LIGHT_CARD_RADIUS: number = {surfaces["harmonyPointLight"]["cardRadiusVp"]};',
        f'  static readonly POINT_LIGHT_NAV_INTENSITY: number = {surfaces["harmonyPointLight"]["navBarIntensity"]};',
        f'  static readonly POINT_LIGHT_NAV_RADIUS: number = {surfaces["harmonyPointLight"]["navBarRadiusVp"]};',
        f'  static readonly MARGIN_COMPACT_VP: number = {layout["margins"]["compact"]};',
        f'  static readonly MARGIN_WIDE_VP: number = {layout["margins"]["wide"]};',
        f'  static readonly MARGIN_EXPANDED_VP: number = {layout["margins"]["expanded"]};',
        f'  static readonly BREAKPOINT_WIDE_VP: number = {layout["breakpoints"]["wideCanvas"]};',
        f'  static readonly BREAKPOINT_TABLET_SPLIT_VP: number = {layout["breakpoints"]["tabletSplit"]};',
        f'  static readonly BREAKPOINT_EXPANDED_VP: number = {layout["breakpoints"]["expandedCanvas"]};',
        f'  static readonly AMBIENT_FPS: number = {surfaces["ambientGradient"]["fps"]};',
        "",
        "  static readonly BACKGROUND_PRESETS: BackgroundPresetToken[] = [",
    ]
    for preset in palette["backgroundPresets"]:
        darks = ", ".join(f"'{c}'" for c in preset["darkStops"])
        lights = ", ".join(f"'{c}'" for c in preset["lightStops"])
        lines.append(
            f"    {{ id: '{preset['id']}', titleZh: '{preset['titleZh']}', titleEn: '{preset['titleEn']}', darkStops: [{darks}], lightStops: [{lights}] }},"
        )
    lines.append("  ];")
    lines.append("")
    lines.append("  static readonly ACCENT_PRESETS: AccentPresetToken[] = [")
    for acc in palette["accentPresets"]:
        lines.append(
            f"    {{ id: '{acc['id']}', titleZh: '{acc['titleZh']}', titleEn: '{acc['titleEn']}', hex: '{acc['hex']}' }},"
        )
    lines.append("  ];")
    lines.append("")
    lines.append("  static readonly SEMANTIC: Record<string, AdaptiveHexToken> = {")
    for key, pair in palette["semantic"].items():
        lines.append(f"    '{key}': {{ light: '{pair['light']}', dark: '{pair['dark']}' }},")
    lines.append("  };")
    lines.append("")
    lines.append("  static readonly OHOS_SYMBOLS: Record<string, string> = {")
    for icon_id, mapping in icons["icons"].items():
        lines.append(f"    '{icon_id}': '{mapping['ohos_symbol']}',")
    lines.append("  };")
    lines.append("")
    lines.append("  /** 解析当前深浅色下的语义色值。 */")
    lines.append("  static semanticColor(key: string, isDark: boolean): string {")
    lines.append("    const pair = GeneratedDesignTokens.SEMANTIC[key];")
    lines.append("    if (!pair) { return isDark ? '#FFFFFF' : '#1C1A24'; }")
    lines.append("    return isDark ? pair.dark : pair.light;")
    lines.append("  }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def write_or_check(path: Path, content: str, check: bool, drifted: list[str], root: Path) -> None:
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == content:
        return
    if check:
        drifted.append(str(path.relative_to(root)))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def sync_tokens(root: Path = ROOT, check: bool = False) -> list[str]:
    """同步三端视觉 Token 代码并返回漂移路径列表。"""
    tok_dir = root / "shared/design-tokens"
    palette = json.loads((tok_dir / "palette.json").read_text(encoding="utf-8"))
    surfaces = json.loads((tok_dir / "surfaces.json").read_text(encoding="utf-8"))
    layout = json.loads((tok_dir / "layout.json").read_text(encoding="utf-8"))
    icons = json.loads((tok_dir / "icons.json").read_text(encoding="utf-8"))

    drifted: list[str] = []
    write_or_check(
        root / "ios/NativeDesignSystem/GeneratedTokens.swift",
        generate_swift(palette, surfaces, layout, icons),
        check,
        drifted,
        root,
    )
    write_or_check(
        root / "android/design-system/src/main/java/com/moviepilot/designsystem/GeneratedTokens.kt",
        generate_kotlin(palette, surfaces, layout, icons),
        check,
        drifted,
        root,
    )
    write_or_check(
        root / "harmony/commons/design_system/src/main/ets/tokens/GeneratedTokens.ets",
        generate_arkts(palette, surfaces, layout, icons),
        check,
        drifted,
        root,
    )
    return drifted


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="仅检查生成物是否最新")
    args = parser.parse_args(argv)
    drifted = sync_tokens(ROOT, check=args.check)
    if drifted:
        print("Design Tokens 生成物过期：", ", ".join(drifted), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
