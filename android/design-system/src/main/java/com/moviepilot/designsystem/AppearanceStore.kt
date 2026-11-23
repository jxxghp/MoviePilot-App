package com.moviepilot.designsystem

import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

/** 外观模式枚举：深色、浅色与跟随系统。 */
enum class NativeAppearanceMode(val id: String, val title: String) {
    Dark("dark", "深色"),
    Light("light", "浅色"),
    System("system", "跟随系统");

    companion object {
        fun fromId(id: String?): NativeAppearanceMode =
            entries.firstOrNull { it.id == id } ?: Dark
    }
}

/**
 * 全局原生外观状态存储：驱动 6 套深浅渐变色板、6 套强调色、自定义三色渐变及动态流光开关，
 * 100% 消费由 `tools/sync-tokens.py` 生成的 `GeneratedDesignTokens`。
 */
@Stable
class NativeAppearanceStore(context: Context? = null) {
    private val prefs = context?.getSharedPreferences("mp_appearance_v1", Context.MODE_PRIVATE)

    var mode by mutableStateOf(
        NativeAppearanceMode.fromId(prefs?.getString("mode", GeneratedDesignTokens.DEFAULT_MODE)),
    )
        private set

    var backgroundPresetId by mutableStateOf(
        prefs?.getString("bg_preset", GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET)
            ?: GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET,
    )
        private set

    var accentPresetId by mutableStateOf(
        prefs?.getString("accent_preset", GeneratedDesignTokens.DEFAULT_ACCENT_PRESET)
            ?: GeneratedDesignTokens.DEFAULT_ACCENT_PRESET,
    )
        private set

    var customBgStartHex by mutableStateOf(
        prefs?.getString("bg_start", GeneratedDesignTokens.CUSTOM_BG_START_HEX)
            ?: GeneratedDesignTokens.CUSTOM_BG_START_HEX,
    )
        private set

    var customBgMidHex by mutableStateOf(
        prefs?.getString("bg_mid", GeneratedDesignTokens.CUSTOM_BG_MID_HEX)
            ?: GeneratedDesignTokens.CUSTOM_BG_MID_HEX,
    )
        private set

    var customBgEndHex by mutableStateOf(
        prefs?.getString("bg_end", GeneratedDesignTokens.CUSTOM_BG_END_HEX)
            ?: GeneratedDesignTokens.CUSTOM_BG_END_HEX,
    )
        private set

    var customAccentHex by mutableStateOf(
        prefs?.getString("accent_hex", GeneratedDesignTokens.CUSTOM_ACCENT_HEX)
            ?: GeneratedDesignTokens.CUSTOM_ACCENT_HEX,
    )
        private set

    var animateBackground by mutableStateOf(prefs?.getBoolean("animate_bg", true) ?: true)
        private set

    fun updateMode(newMode: NativeAppearanceMode) {
        mode = newMode
        prefs?.edit()?.putString("mode", newMode.id)?.apply()
    }

    fun updateBackgroundPreset(id: String) {
        backgroundPresetId = id
        prefs?.edit()?.putString("bg_preset", id)?.apply()
    }

    fun updateAccentPreset(id: String) {
        accentPresetId = id
        prefs?.edit()?.putString("accent_preset", id)?.apply()
    }

    fun updateCustomGradient(startHex: String, midHex: String, endHex: String) {
        customBgStartHex = startHex
        customBgMidHex = midHex
        customBgEndHex = endHex
        backgroundPresetId = "custom"
        prefs?.edit()
            ?.putString("bg_preset", "custom")
            ?.putString("bg_start", startHex)
            ?.putString("bg_mid", midHex)
            ?.putString("bg_end", endHex)
            ?.apply()
    }

    fun updateAnimateBackground(enabled: Boolean) {
        animateBackground = enabled
        prefs?.edit()?.putBoolean("animate_bg", enabled)?.apply()
    }

    fun resetToDefaults() {
        updateMode(NativeAppearanceMode.Dark)
        updateBackgroundPreset(GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET)
        updateAccentPreset(GeneratedDesignTokens.DEFAULT_ACCENT_PRESET)
        updateAnimateBackground(true)
    }

    /** 当前生效的主题强调色。 */
    val accentColor: Color
        get() = if (accentPresetId == "custom") {
            parseHexColor(customAccentHex) ?: GeneratedDesignTokens.accentPresets.first().color
        } else {
            GeneratedDesignTokens.accentPresets.firstOrNull { it.id == accentPresetId }?.color
                ?: GeneratedDesignTokens.accentPresets.first().color
        }

    /** 返回用于 AGSL 流光与渐变铺底的 4 节点同源色板。 */
    fun backgroundPalette(isDark: Boolean): List<Color> {
        if (backgroundPresetId == "custom") {
            val s = parseHexColor(customBgStartHex) ?: Color(0xFF30334A)
            val m = parseHexColor(customBgMidHex) ?: Color(0xFF4A3B57)
            val e = parseHexColor(customBgEndHex) ?: Color(0xFF242E40)
            return listOf(s, m, m, e)
        }
        val preset = GeneratedDesignTokens.backgroundPresets.firstOrNull { it.id == backgroundPresetId }
            ?: GeneratedDesignTokens.backgroundPresets.first()
        return if (isDark) preset.darkStops else preset.lightStops
    }

    /** 设置项副标题概要文案。 */
    val summaryText: String
        get() {
            val presetTitle = GeneratedDesignTokens.backgroundPresets
                .firstOrNull { it.id == backgroundPresetId }?.titleZh ?: "星夜紫玫"
            return "${mode.title} · $presetTitle"
        }

    companion object {
        fun parseHexColor(hex: String): Color? {
            val cleaned = hex.trim().removePrefix("#")
            if (cleaned.length != 6) return null
            val rgb = cleaned.toLongOrNull(16) ?: return null
            return Color((0xFF000000L or rgb))
        }
    }
}

/** 解析后的当前深浅色运行时颜色表，供所有 Compose 组件零分配读取。 */
@Immutable
data class MoviePilotColors(
    val isDark: Boolean,
    val accent: Color,
    val palette: List<Color>,
    val textPrimary: Color,
    val textSecondary: Color,
    val textMuted: Color,
    val success: Color,
    val warning: Color,
    val danger: Color,
    val info: Color,
    val brand: Color,
    val pink: Color,
    val cyan: Color,
    val chipFill: Color,
    val chipBorder: Color,
    val chipText: Color,
    val badgeFill: Color,
    val fieldFill: Color,
    val fieldBorder: Color,
    val divider: Color,
    val primaryButtonBg: Color,
    val primaryButtonFg: Color,
    val solidSurface: Color,
)

val LocalAppearanceStore = compositionLocalOf { NativeAppearanceStore(null) }
val LocalMoviePilotColors = compositionLocalOf {
    resolveMoviePilotColors(isDark = true, store = NativeAppearanceStore(null))
}

fun resolveMoviePilotColors(isDark: Boolean, store: NativeAppearanceStore): MoviePilotColors {
    val s = GeneratedDesignTokens.Semantic
    return MoviePilotColors(
        isDark = isDark,
        accent = store.accentColor,
        palette = store.backgroundPalette(isDark),
        textPrimary = if (isDark) Color(0xFFF6F3FF) else Color(0xFF1C1A24),
        textSecondary = if (isDark) Color(0xB8FFFFFF) else Color(0xB31C1A24),
        textMuted = if (isDark) Color(0x80FFFFFF) else Color(0x852E2A3B),
        success = s.success.resolve(isDark),
        warning = s.warning.resolve(isDark),
        danger = s.danger.resolve(isDark),
        info = s.info.resolve(isDark),
        brand = s.brand.resolve(isDark),
        pink = s.pink.resolve(isDark),
        cyan = s.cyan.resolve(isDark),
        chipFill = s.chipFill.resolve(isDark),
        chipBorder = s.chipBorder.resolve(isDark),
        chipText = s.chipText.resolve(isDark),
        badgeFill = s.badgeFill.resolve(isDark),
        fieldFill = s.fieldFill.resolve(isDark),
        fieldBorder = s.fieldBorder.resolve(isDark),
        divider = s.divider.resolve(isDark),
        primaryButtonBg = s.primaryButtonBackground.resolve(isDark),
        primaryButtonFg = s.primaryButtonForeground.resolve(isDark),
        solidSurface = s.solidSurface.resolve(isDark),
    )
}

/** MoviePilot Android 原生主题包装器：统一注入深浅色解析与设计 Token。 */
@Composable
fun MoviePilotTheme(
    appearanceStore: NativeAppearanceStore,
    content: @Composable () -> Unit,
) {
    val systemDark = isSystemInDarkTheme()
    val isDark = when (appearanceStore.mode) {
        NativeAppearanceMode.Dark -> true
        NativeAppearanceMode.Light -> false
        NativeAppearanceMode.System -> systemDark
    }
    val colors = resolveMoviePilotColors(isDark = isDark, store = appearanceStore)
    CompositionLocalProvider(
        LocalAppearanceStore provides appearanceStore,
        LocalMoviePilotColors provides colors,
        content = content,
    )
}
