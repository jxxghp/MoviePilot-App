// 自动生成自 shared/design-tokens/*.json，请勿手工修改；请运行 python3 tools/sync-all.py。
package com.moviepilot.designsystem

import androidx.compose.ui.graphics.Color

/** 预设背景渐变色板定义（深色与浅色 4 段色点）。 */
data class BackgroundPresetToken(
    val id: String,
    val titleZh: String,
    val titleEn: String,
    val darkStops: List<Color>,
    val lightStops: List<Color>,
)

/** 预设主题强调色定义。 */
data class AccentPresetToken(
    val id: String,
    val titleZh: String,
    val titleEn: String,
    val color: Color,
    val hex: String,
)

/** 自适应深浅色语义色对。 */
data class AdaptiveColorToken(
    val light: Color,
    val dark: Color,
) {
    fun resolve(isDark: Boolean): Color = if (isDark) dark else light
}

/** 三端同源视觉 Token（由 shared/design-tokens 单一事实源自动生成）。 */
object GeneratedDesignTokens {
    const val DEFAULT_MODE: String = "dark"
    const val DEFAULT_BACKGROUND_PRESET: String = "cinematic"
    const val DEFAULT_ACCENT_PRESET: String = "violet"
    const val CUSTOM_BG_START_HEX: String = "#30334A"
    const val CUSTOM_BG_MID_HEX: String = "#4A3B57"
    const val CUSTOM_BG_END_HEX: String = "#242E40"
    const val CUSTOM_ACCENT_HEX: String = "#9E7AF5"
    const val PANEL_CORNER_RADIUS_DP: Float = 24f
    const val PANEL_PADDING_DP: Float = 18f
    const val PANEL_BORDER_WIDTH_DP: Float = 0.7f
    const val SHEET_CORNER_RADIUS_DP: Float = 28f
    const val ANDROID_WINDOW_BLUR_PX: Int = 48
    const val NAV_BAR_BLUR_DP: Float = 22f
    const val MARGIN_COMPACT_DP: Float = 20f
    const val MARGIN_WIDE_DP: Float = 24f
    const val MARGIN_EXPANDED_DP: Float = 28f
    const val BREAKPOINT_WIDE_DP: Float = 680f
    const val BREAKPOINT_TABLET_SPLIT_DP: Float = 840f
    const val BREAKPOINT_EXPANDED_DP: Float = 960f
    const val AMBIENT_FPS: Int = 15

    val backgroundPresets: List<BackgroundPresetToken> = listOf(
        BackgroundPresetToken("cinematic", "星夜紫玫", "Starlit Violet", listOf(Color(0xFF30334A), Color(0xFF4A3B57), Color(0xFF57384A), Color(0xFF242E40)), listOf(Color(0xFFF0EDFC), Color(0xFFF5EBF7), Color(0xFFFAEDF2), Color(0xFFEBF0FC))),
        BackgroundPresetToken("ocean", "深海极光", "Ocean Aurora", listOf(Color(0xFF142947), Color(0xFF1A3D57), Color(0xFF1F4757), Color(0xFF122138)), listOf(Color(0xFFE6F2FC), Color(0xFFE8F7FA), Color(0xFFEDF5FC), Color(0xFFE3F0FA))),
        BackgroundPresetToken("forest", "静谧松林", "Quiet Forest", listOf(Color(0xFF1A3330), Color(0xFF244238), Color(0xFF2E4030), Color(0xFF142629)), listOf(Color(0xFFE8F7F2), Color(0xFFF0FAF0), Color(0xFFF2F7ED), Color(0xFFE6F2F0))),
        BackgroundPresetToken("amber", "暖阳琥珀", "Warm Amber", listOf(Color(0xFF3D2B26), Color(0xFF52362B), Color(0xFF472E33), Color(0xFF292129)), listOf(Color(0xFFFCF2E8), Color(0xFFFCEDE6), Color(0xFFFAF0ED), Color(0xFFF5EDEB))),
        BackgroundPresetToken("graphite", "极简石墨", "Minimal Graphite", listOf(Color(0xFF101218), Color(0xFF181B24), Color(0xFF151821), Color(0xFF0C0E14)), listOf(Color(0xFFF2F2F7), Color(0xFFEDF0F5), Color(0xFFF2F2F5), Color(0xFFE8EBF2))),
        BackgroundPresetToken("custom", "自定义", "Custom", listOf(Color(0xFF30334A), Color(0xFF4A3B57), Color(0xFF57384A), Color(0xFF242E40)), listOf(Color(0xFFF0EDFC), Color(0xFFF5EBF7), Color(0xFFFAEDF2), Color(0xFFEBF0FC))),
    )

    val accentPresets: List<AccentPresetToken> = listOf(
        AccentPresetToken("violet", "星耀紫", "Starlight Violet", Color(0xFF9E7AF5), "#9E7AF5"),
        AccentPresetToken("azure", "极光蓝", "Aurora Azure", Color(0xFF47A3FA), "#47A3FA"),
        AccentPresetToken("emerald", "翡翠绿", "Emerald Green", Color(0xFF3DC78F), "#3DC78F"),
        AccentPresetToken("rose", "珊瑚粉", "Coral Rose", Color(0xFFEB6B9E), "#EB6B9E"),
        AccentPresetToken("amber", "琥珀金", "Amber Gold", Color(0xFFF2A33D), "#F2A33D"),
        AccentPresetToken("custom", "自定义", "Custom", Color(0xFF9E7AF5), "#9E7AF5"),
    )

    object Semantic {
        val success = AdaptiveColorToken(light = Color(0xFF148A47), dark = Color(0xFF75E6A3))
        val warning = AdaptiveColorToken(light = Color(0xFFBD6B08), dark = Color(0xFFFFCC6B))
        val danger = AdaptiveColorToken(light = Color(0xFFCC2933), dark = Color(0xFFFF8A94))
        val info = AdaptiveColorToken(light = Color(0xFF1A70D6), dark = Color(0xFF75C7FF))
        val brand = AdaptiveColorToken(light = Color(0xFF6638C7), dark = Color(0xFFD6BDFF))
        val pink = AdaptiveColorToken(light = Color(0xFFC22E75), dark = Color(0xFFF58FBD))
        val cyan = AdaptiveColorToken(light = Color(0xFF0D809E), dark = Color(0xFF75D6E6))
        val chipFill = AdaptiveColorToken(light = Color(0x0E000000), dark = Color(0x17FFFFFF))
        val chipBorder = AdaptiveColorToken(light = Color(0x1C000000), dark = Color(0x26FFFFFF))
        val chipText = AdaptiveColorToken(light = Color(0xE0242424), dark = Color(0xDBFFFFFF))
        val badgeFill = AdaptiveColorToken(light = Color(0x0F000000), dark = Color(0x1AFFFFFF))
        val badgeMutedText = AdaptiveColorToken(light = Color(0xD1474747), dark = Color(0xADFFFFFF))
        val fieldFill = AdaptiveColorToken(light = Color(0x0E000000), dark = Color(0x17FFFFFF))
        val fieldBorder = AdaptiveColorToken(light = Color(0x1A000000), dark = Color(0x24FFFFFF))
        val primaryButtonBackground = AdaptiveColorToken(light = Color(0xFF1F1F29), dark = Color(0xF0FFFFFF))
        val primaryButtonForeground = AdaptiveColorToken(light = Color(0xFFFFFFFF), dark = Color(0xFF1F1A29))
        val divider = AdaptiveColorToken(light = Color(0x17000000), dark = Color(0x1CFFFFFF))
        val fallbackBackground = AdaptiveColorToken(light = Color(0xFFF0EDFC), dark = Color(0xFF29293B))
        val solidSurface = AdaptiveColorToken(light = Color(0xFFF7F7FC), dark = Color(0xFF473B52))
        val roseGlow = AdaptiveColorToken(light = Color(0x1AB36396), dark = Color(0x1AB36396))
    }

    val materialIcons: Map<String, String> = mapOf(
        "tab_discover" to "AutoAwesome",
        "tab_explore" to "Explore",
        "tab_dashboard" to "AccountCircle",
        "tab_settings" to "Settings",
        "action_search" to "Search",
        "action_add" to "Add",
        "action_refresh" to "Refresh",
        "action_edit" to "Tune",
        "action_filter" to "FilterList",
        "menu_subscriptions" to "Subscriptions",
        "menu_calendar" to "CalendarMonth",
        "menu_resources" to "TravelExplore",
        "menu_downloads" to "Download",
        "menu_files" to "Folder",
        "menu_history" to "History",
        "menu_workflows" to "AccountTree",
        "menu_plugins" to "Extension",
        "feature_sites" to "Language",
        "feature_messages" to "Notifications",
        "feature_shortcuts" to "Bolt",
        "feature_agent" to "SmartToy",
        "feature_music" to "MusicNote",
        "feature_users" to "Group",
        "feature_appearance" to "Palette",
        "feature_system" to "Memory",
        "feature_medals" to "WorkspacePremium",
        "player_play" to "PlayArrow",
        "player_pause" to "Pause",
        "player_pip" to "PictureInPictureAlt",
        "player_lock" to "Lock",
        "player_unlock" to "LockOpen",
        "player_subtitles" to "ClosedCaption",
        "player_audio_track" to "GraphicEq",
        "player_aspect" to "AspectRatio",
        "player_speed" to "Speed",
        "mode_dark" to "DarkMode",
        "mode_light" to "LightMode",
        "mode_system" to "Contrast",
    )
}
