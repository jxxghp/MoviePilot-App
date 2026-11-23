package com.moviepilot.designsystem

import android.content.Context
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Material Design 3 标准排版体系（依据 mobile-android-design 规范统一字号、字重与行高）。 */
val MoviePilotTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 36.sp,
        lineHeight = 44.sp,
        letterSpacing = (-0.25).sp,
    ),
    headlineLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        lineHeight = 36.sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 24.sp,
        lineHeight = 32.sp,
    ),
    headlineSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 28.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 21.sp,
        lineHeight = 28.sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 22.sp,
        letterSpacing = 0.15.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.15.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.25.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.4.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 0.5.sp,
    ),
)

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
 * 全局原生外观状态存储：驱动 Material 3 视觉体系、Android 12+ Material You 壁纸动态取色、
 * 6 套深浅渐变色板、6 套强调色、自定义三色渐变及动态流光开关，
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

    var animateBackground by mutableStateOf(prefs?.getBoolean("animate_bg", false) ?: false)
        private set

    /** Android 12+ Material You 系统壁纸动态取色开关。 */
    var dynamicColorEnabled by mutableStateOf(prefs?.getBoolean("dynamic_color", false) ?: false)
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

    fun updateDynamicColorEnabled(enabled: Boolean) {
        dynamicColorEnabled = enabled
        prefs?.edit()?.putBoolean("dynamic_color", enabled)?.apply()
    }

    fun resetToDefaults() {
        updateMode(NativeAppearanceMode.Dark)
        updateBackgroundPreset(GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET)
        updateAccentPreset(GeneratedDesignTokens.DEFAULT_ACCENT_PRESET)
        updateAnimateBackground(true)
        updateDynamicColorEnabled(false)
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
            if (dynamicColorEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                return "${mode.title} · Material You 动态取色"
            }
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

/** 解析后的当前深浅色运行时颜色表，融合 Material 3 Tonal Color System，供所有 Compose 组件零分配读取。 */
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
    val surfaceContainerLow: Color,
    val surfaceContainer: Color,
    val surfaceContainerHigh: Color,
    val activeIndicator: Color,
)

val LocalAppearanceStore = compositionLocalOf { NativeAppearanceStore(null) }
val LocalMoviePilotColors = compositionLocalOf {
    resolveMoviePilotColors(isDark = true, store = NativeAppearanceStore(null))
}

fun resolveMoviePilotColors(
    isDark: Boolean,
    store: NativeAppearanceStore,
    dynamicScheme: ColorScheme? = null,
): MoviePilotColors {
    val s = GeneratedDesignTokens.Semantic
    val resolvedAccent = dynamicScheme?.primary ?: store.accentColor
    val rawPresetStops = store.backgroundPalette(isDark)
    // Material 3 Tonal Neutral Surface Ramp：以低饱和中性暗/浅面为基底，融入约 5% 主题种子色倾向（遵循 HCT Neutral/NeutralVariant 体系）
    val seed = rawPresetStops.getOrElse(1) { resolvedAccent }
    fun tintNeutral(base: Color, amount: Float): Color = Color(
        red = base.red * (1f - amount) + seed.red * amount,
        green = base.green * (1f - amount) + seed.green * amount,
        blue = base.blue * (1f - amount) + seed.blue * amount,
        alpha = 1f,
    )
    val baseBg = dynamicScheme?.background ?: tintNeutral(if (isDark) Color(0xFF121116) else Color(0xFFFCF8FF), if (isDark) 0.05f else 0.03f)
    val surfLow = dynamicScheme?.surfaceContainerLow ?: tintNeutral(if (isDark) Color(0xFF1A1920) else Color(0xFFF5F1FA), if (isDark) 0.07f else 0.04f)
    val surfMid = dynamicScheme?.surfaceContainer ?: tintNeutral(if (isDark) Color(0xFF211F28) else Color(0xFFEFEAF6), if (isDark) 0.09f else 0.05f)
    val surfHigh = dynamicScheme?.surfaceContainerHigh ?: tintNeutral(if (isDark) Color(0xFF2B2834) else Color(0xFFE8E2F1), if (isDark) 0.11f else 0.06f)

    val resolvedPalette = if (dynamicScheme != null) {
        listOf(baseBg, surfLow, surfMid, baseBg)
    } else {
        listOf(baseBg, surfLow, surfMid, baseBg)
    }
    return MoviePilotColors(
        isDark = isDark,
        accent = resolvedAccent,
        palette = resolvedPalette,
        textPrimary = dynamicScheme?.onSurface ?: if (isDark) Color(0xFFE6E1E9) else Color(0xFF1C1B1F),
        textSecondary = dynamicScheme?.onSurfaceVariant ?: if (isDark) Color(0xFFCAC4D0) else Color(0xFF49454F),
        textMuted = dynamicScheme?.outline ?: if (isDark) Color(0xFF938F99) else Color(0xFF79747E),
        success = s.success.resolve(isDark),
        warning = s.warning.resolve(isDark),
        danger = dynamicScheme?.error ?: s.danger.resolve(isDark),
        info = s.info.resolve(isDark),
        brand = dynamicScheme?.tertiary ?: s.brand.resolve(isDark),
        pink = dynamicScheme?.secondary ?: s.pink.resolve(isDark),
        cyan = s.cyan.resolve(isDark),
        chipFill = surfHigh,
        chipBorder = dynamicScheme?.outlineVariant ?: if (isDark) Color(0xFF49454F) else Color(0xFFCAC4D0),
        chipText = dynamicScheme?.onSurface ?: if (isDark) Color(0xFFE6E1E9) else Color(0xFF1C1B1F),
        badgeFill = dynamicScheme?.secondaryContainer ?: resolvedAccent.copy(alpha = if (isDark) 0.22f else 0.14f),
        fieldFill = dynamicScheme?.surfaceContainerHighest ?: surfHigh,
        fieldBorder = dynamicScheme?.outlineVariant ?: if (isDark) Color(0xFF49454F) else Color(0xFFCAC4D0),
        divider = (dynamicScheme?.outlineVariant ?: if (isDark) Color(0xFF3A3742) else Color(0xFFE0DBE6)).copy(alpha = 0.72f),
        primaryButtonBg = resolvedAccent,
        primaryButtonFg = dynamicScheme?.onPrimary ?: Color.White,
        solidSurface = baseBg,
        surfaceContainerLow = surfLow,
        surfaceContainer = surfMid,
        surfaceContainerHigh = surfHigh,
        activeIndicator = dynamicScheme?.secondaryContainer ?: resolvedAccent.copy(alpha = if (isDark) 0.28f else 0.16f),
    )
}

/** MoviePilot Android Material 3 原生主题包装器：融合动态取色与 Material 3 ColorScheme。 */
@Composable
fun MoviePilotTheme(
    appearanceStore: NativeAppearanceStore,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val systemDark = isSystemInDarkTheme()
    val isDark = when (appearanceStore.mode) {
        NativeAppearanceMode.Dark -> true
        NativeAppearanceMode.Light -> false
        NativeAppearanceMode.System -> systemDark
    }
    val dynamicScheme = if (appearanceStore.dynamicColorEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        if (isDark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    } else {
        null
    }
    val colors = resolveMoviePilotColors(
        isDark = isDark,
        store = appearanceStore,
        dynamicScheme = dynamicScheme,
    )
    val materialScheme = dynamicScheme ?: if (isDark) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = Color.White,
            primaryContainer = colors.accent.copy(alpha = 0.28f),
            onPrimaryContainer = Color(0xFFF4EEFF),
            secondary = colors.pink,
            secondaryContainer = colors.activeIndicator,
            onSecondaryContainer = Color(0xFFF4EEFF),
            tertiary = colors.brand,
            background = colors.palette.firstOrNull() ?: Color(0xFF171324),
            onBackground = colors.textPrimary,
            surface = colors.solidSurface,
            onSurface = colors.textPrimary,
            surfaceVariant = colors.surfaceContainer,
            onSurfaceVariant = colors.textSecondary,
            surfaceContainerLow = colors.surfaceContainerLow,
            surfaceContainer = colors.surfaceContainer,
            surfaceContainerHigh = colors.surfaceContainerHigh,
            outline = colors.fieldBorder,
            outlineVariant = colors.divider,
            error = colors.danger,
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = Color.White,
            primaryContainer = colors.accent.copy(alpha = 0.16f),
            onPrimaryContainer = Color(0xFF21163A),
            secondary = colors.pink,
            secondaryContainer = colors.activeIndicator,
            onSecondaryContainer = Color(0xFF21163A),
            tertiary = colors.brand,
            background = colors.palette.firstOrNull() ?: Color(0xFFF5F1FC),
            onBackground = colors.textPrimary,
            surface = colors.solidSurface,
            onSurface = colors.textPrimary,
            surfaceVariant = colors.surfaceContainer,
            onSurfaceVariant = colors.textSecondary,
            surfaceContainerLow = colors.surfaceContainerLow,
            surfaceContainer = colors.surfaceContainer,
            surfaceContainerHigh = colors.surfaceContainerHigh,
            outline = colors.fieldBorder,
            outlineVariant = colors.divider,
            error = colors.danger,
        )
    }

    MaterialTheme(
        colorScheme = materialScheme,
        typography = MoviePilotTypography,
    ) {
        CompositionLocalProvider(
            LocalAppearanceStore provides appearanceStore,
            LocalMoviePilotColors provides colors,
            content = content,
        )
    }
}
