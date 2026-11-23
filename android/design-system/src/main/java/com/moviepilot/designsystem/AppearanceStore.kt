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
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Material 3 Expressive 排版体系（醒目加粗展示标题 + 清晰层级与数字可读性）。 */
val MoviePilotTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 42.sp,
        lineHeight = 46.sp,
        letterSpacing = (-0.8).sp,
    ),
    headlineLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.ExtraBold,
        fontSize = 32.sp,
        lineHeight = 38.sp,
        letterSpacing = (-0.4).sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 26.sp,
        lineHeight = 32.sp,
        letterSpacing = (-0.2).sp,
    ),
    headlineSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 21.sp,
        lineHeight = 28.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
        letterSpacing = (-0.15).sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 22.sp,
        letterSpacing = 0.1.sp,
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
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
        letterSpacing = 0.2.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.35.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        letterSpacing = 0.2.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.4.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 0.4.sp,
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

/** Material 3 Expressive 界面圆角尺度（支持紧凑 / 标准 / 表现力三档自定义）。 */
enum class ExpressiveCornerStyle(val id: String, val title: String, val cardDp: Int, val sheetDp: Int) {
    Compact("compact", "紧凑", 14, 20),
    Standard("standard", "标准", 18, 24),
    Expressive("expressive", "表现力", 22, 28);

    companion object {
        fun fromId(id: String?): ExpressiveCornerStyle =
            entries.firstOrNull { it.id == id } ?: Expressive
    }
}

/** 底部导航栏样式：圆角悬浮栏（默认） vs 圆角贴底栏。 */
enum class ExpressiveNavBarStyle(val id: String, val title: String) {
    FloatingPill("floating_pill", "圆角悬浮"),
    RoundedDock("rounded_dock", "圆角贴底");

    companion object {
        fun fromId(id: String?): ExpressiveNavBarStyle =
            entries.firstOrNull { it.id == id } ?: FloatingPill
    }
}

/** 单套深浅表现力色阶定义。 */
@Immutable
data class ExpressivePaletteTone(
    val canvas: Color,
    val headerTint: Color,
    val headerTitle: Color,
    val headerButtonBg: Color,
    val headerButtonFg: Color,
    val surfaceLow: Color,
    val surface: Color,
    val surfaceHigh: Color,
    val primary: Color,
    val onPrimary: Color,
    val primaryContainer: Color,
    val onPrimaryContainer: Color,
    val secondary: Color,
    val secondaryContainer: Color,
    val onSecondaryContainer: Color,
    val outline: Color,
    val divider: Color,
    val playerTint: Color,
    val playerAccent: Color,
    val playerOnAccent: Color,
    val playerDock: Color,
    val playerButtonBg: Color,
)

/** Material 3 Expressive 精选主题色板。 */
@Immutable
data class ExpressivePalettePreset(
    val id: String,
    val titleZh: String,
    val subtitleZh: String,
    val dark: ExpressivePaletteTone,
    val light: ExpressivePaletteTone,
)

object ExpressivePalettes {
    val SapphireInk = ExpressivePalettePreset(
        id = "sapphire_ink",
        titleZh = "深海蓝调",
        subtitleZh = "深蓝墨韵",
        dark = ExpressivePaletteTone(
            canvas = Color(0xFF0E1117),
            headerTint = Color(0xFF0B254A),
            headerTitle = Color(0xFFBAC9FF),
            headerButtonBg = Color(0xFF133B73),
            headerButtonFg = Color(0xFFEAF0FF),
            surfaceLow = Color(0xFF161A23),
            surface = Color(0xFF1C212D),
            surfaceHigh = Color(0xFF252C3C),
            primary = Color(0xFFBAC9FF),
            onPrimary = Color(0xFF0B2559),
            primaryContainer = Color(0xFF1C3B73),
            onPrimaryContainer = Color(0xFFDAE3FF),
            secondary = Color(0xFFF0B8C9),
            secondaryContainer = Color(0xFF2A3552),
            onSecondaryContainer = Color(0xFFDCE4FF),
            outline = Color(0xFF424B61),
            divider = Color(0xFF283042),
            playerTint = Color(0xFF542239),
            playerAccent = Color(0xFFF0C2D0),
            playerOnAccent = Color(0xFF471629),
            playerDock = Color(0xFF3A1527),
            playerButtonBg = Color(0xFF6B354F),
        ),
        light = ExpressivePaletteTone(
            canvas = Color(0xFFF4F7FD),
            headerTint = Color(0xFFDCE6FB),
            headerTitle = Color(0xFF143C80),
            headerButtonBg = Color(0xFFC5D6F8),
            headerButtonFg = Color(0xFF0E2C62),
            surfaceLow = Color(0xFFFFFFFF),
            surface = Color(0xFFEEF3FC),
            surfaceHigh = Color(0xFFE2E9F7),
            primary = Color(0xFF2352A8),
            onPrimary = Color(0xFFFFFFFF),
            primaryContainer = Color(0xFFD6E2FF),
            onPrimaryContainer = Color(0xFF072154),
            secondary = Color(0xFF8C3658),
            secondaryContainer = Color(0xFFD8E3FA),
            onSecondaryContainer = Color(0xFF142B59),
            outline = Color(0xFFBFC9DC),
            divider = Color(0xFFDCE3F1),
            playerTint = Color(0xFF652944),
            playerAccent = Color(0xFFF6CCD9),
            playerOnAccent = Color(0xFF471629),
            playerDock = Color(0xFF471B30),
            playerButtonBg = Color(0xFF7C3B59),
        ),
    )

    val BerryVelvet = ExpressivePalettePreset(
        id = "berry_velvet",
        titleZh = "莓果微醺",
        subtitleZh = "丝绒酒红",
        dark = ExpressivePaletteTone(
            canvas = Color(0xFF140D12),
            headerTint = Color(0xFF491C32),
            headerTitle = Color(0xFFF3C0CF),
            headerButtonBg = Color(0xFF652845),
            headerButtonFg = Color(0xFFFFE6EE),
            surfaceLow = Color(0xFF1F151C),
            surface = Color(0xFF281B24),
            surfaceHigh = Color(0xFF34232F),
            primary = Color(0xFFF3C0CF),
            onPrimary = Color(0xFF4D172A),
            primaryContainer = Color(0xFF662744),
            onPrimaryContainer = Color(0xFFFFD9E3),
            secondary = Color(0xFFD5C1FF),
            secondaryContainer = Color(0xFF492739),
            onSecondaryContainer = Color(0xFFFFD9E3),
            outline = Color(0xFF5A404F),
            divider = Color(0xFF3A2734),
            playerTint = Color(0xFF56213A),
            playerAccent = Color(0xFFF3C0CF),
            playerOnAccent = Color(0xFF4A1629),
            playerDock = Color(0xFF3A1427),
            playerButtonBg = Color(0xFF6E3450),
        ),
        light = ExpressivePaletteTone(
            canvas = Color(0xFFFDF6F8),
            headerTint = Color(0xFFF7DBE4),
            headerTitle = Color(0xFF6D1F40),
            headerButtonBg = Color(0xFFEEC6D4),
            headerButtonFg = Color(0xFF51132D),
            surfaceLow = Color(0xFFFFFFFF),
            surface = Color(0xFFF6EBEF),
            surfaceHigh = Color(0xFFEEDCE3),
            primary = Color(0xFF8F3056),
            onPrimary = Color(0xFFFFFFFF),
            primaryContainer = Color(0xFFFFD8E4),
            onPrimaryContainer = Color(0xFF3B091D),
            secondary = Color(0xFF60499B),
            secondaryContainer = Color(0xFFF3D9E3),
            onSecondaryContainer = Color(0xFF4D172A),
            outline = Color(0xFFD7BDC7),
            divider = Color(0xFFEAD7DF),
            playerTint = Color(0xFF652543),
            playerAccent = Color(0xFFF7CAD8),
            playerOnAccent = Color(0xFF4A1629),
            playerDock = Color(0xFF46182F),
            playerButtonBg = Color(0xFF7D3858),
        ),
    )

    val MintAurora = ExpressivePalettePreset(
        id = "mint_aurora",
        titleZh = "极光青柠",
        subtitleZh = "松墨青翠",
        dark = ExpressivePaletteTone(
            canvas = Color(0xFF0D1412),
            headerTint = Color(0xFF0D382D),
            headerTitle = Color(0xFF9EE6CB),
            headerButtonBg = Color(0xFF155142),
            headerButtonFg = Color(0xFFE0FFF3),
            surfaceLow = Color(0xFF151E1B),
            surface = Color(0xFF1B2723),
            surfaceHigh = Color(0xFF24342F),
            primary = Color(0xFF9EE6CB),
            onPrimary = Color(0xFF043829),
            primaryContainer = Color(0xFF144E3E),
            onPrimaryContainer = Color(0xFFC2F7E2),
            secondary = Color(0xFFBAC9FF),
            secondaryContainer = Color(0xFF1E3F35),
            onSecondaryContainer = Color(0xFFC4F6E2),
            outline = Color(0xFF3E5750),
            divider = Color(0xFF263833),
            playerTint = Color(0xFF143C32),
            playerAccent = Color(0xFFA4ECD1),
            playerOnAccent = Color(0xFF053829),
            playerDock = Color(0xFF0C2821),
            playerButtonBg = Color(0xFF215346),
        ),
        light = ExpressivePaletteTone(
            canvas = Color(0xFFF3FAF7),
            headerTint = Color(0xFFD2F0E4),
            headerTitle = Color(0xFF0C523E),
            headerButtonBg = Color(0xFFB5E4D2),
            headerButtonFg = Color(0xFF073B2C),
            surfaceLow = Color(0xFFFFFFFF),
            surface = Color(0xFFE9F4EF),
            surfaceHigh = Color(0xFFDCECE5),
            primary = Color(0xFF116B52),
            onPrimary = Color(0xFFFFFFFF),
            primaryContainer = Color(0xFFB7F0D9),
            onPrimaryContainer = Color(0xFF023325),
            secondary = Color(0xFF2D599E),
            secondaryContainer = Color(0xFFD1ECE1),
            onSecondaryContainer = Color(0xFF0A4333),
            outline = Color(0xFFB6CFC5),
            divider = Color(0xFFD5E7DF),
            playerTint = Color(0xFF174A3D),
            playerAccent = Color(0xFFB4F1DA),
            playerOnAccent = Color(0xFF053829),
            playerDock = Color(0xFF0F3229),
            playerButtonBg = Color(0xFF256152),
        ),
    )

    val WarmTerracotta = ExpressivePalettePreset(
        id = "warm_terracotta",
        titleZh = "琥珀暖阳",
        subtitleZh = "焦糖暖棕",
        dark = ExpressivePaletteTone(
            canvas = Color(0xFF15110D),
            headerTint = Color(0xFF422A12),
            headerTitle = Color(0xFFFFD09E),
            headerButtonBg = Color(0xFF5D3B1A),
            headerButtonFg = Color(0xFFFFEFE0),
            surfaceLow = Color(0xFF1F1A14),
            surface = Color(0xFF282119),
            surfaceHigh = Color(0xFF342B21),
            primary = Color(0xFFFFD09E),
            onPrimary = Color(0xFF472605),
            primaryContainer = Color(0xFF5E3B18),
            onPrimaryContainer = Color(0xFFFFE2C4),
            secondary = Color(0xFFE7C0D6),
            secondaryContainer = Color(0xFF45311E),
            onSecondaryContainer = Color(0xFFFFE2C4),
            outline = Color(0xFF5B4C3D),
            divider = Color(0xFF3A3026),
            playerTint = Color(0xFF4A2E16),
            playerAccent = Color(0xFFFFD2A3),
            playerOnAccent = Color(0xFF472605),
            playerDock = Color(0xFF321E0D),
            playerButtonBg = Color(0xFF634022),
        ),
        light = ExpressivePaletteTone(
            canvas = Color(0xFFFCF7F2),
            headerTint = Color(0xFFF7E2CC),
            headerTitle = Color(0xFF6A3A0C),
            headerButtonBg = Color(0xFFEDD0B2),
            headerButtonFg = Color(0xFF4F2A07),
            surfaceLow = Color(0xFFFFFFFF),
            surface = Color(0xFFF5ECE3),
            surfaceHigh = Color(0xFFECE0D3),
            primary = Color(0xFF8C5016),
            onPrimary = Color(0xFFFFFFFF),
            primaryContainer = Color(0xFFFFE0BF),
            onPrimaryContainer = Color(0xFF381B00),
            secondary = Color(0xFF7B486A),
            secondaryContainer = Color(0xFFF3E2CF),
            onSecondaryContainer = Color(0xFF472605),
            outline = Color(0xFFD4C2B0),
            divider = Color(0xFFE8DACC),
            playerTint = Color(0xFF5B391C),
            playerAccent = Color(0xFFFFDAB2),
            playerOnAccent = Color(0xFF472605),
            playerDock = Color(0xFF3D2511),
            playerButtonBg = Color(0xFF734B29),
        ),
    )

    val ExpressiveViolet = ExpressivePalettePreset(
        id = "expressive_violet",
        titleZh = "幻夜紫韵",
        subtitleZh = "星夜紫韵",
        dark = ExpressivePaletteTone(
            canvas = Color(0xFF100E17),
            headerTint = Color(0xFF291B4F),
            headerTitle = Color(0xFFD5BFFF),
            headerButtonBg = Color(0xFF3E2975),
            headerButtonFg = Color(0xFFF2EBFF),
            surfaceLow = Color(0xFF181523),
            surface = Color(0xFF211C2F),
            surfaceHigh = Color(0xFF2B253D),
            primary = Color(0xFFD5BFFF),
            onPrimary = Color(0xFF31166B),
            primaryContainer = Color(0xFF412B7A),
            onPrimaryContainer = Color(0xFFECE2FF),
            secondary = Color(0xFFF2B8D0),
            secondaryContainer = Color(0xFF342A52),
            onSecondaryContainer = Color(0xFFE9DEFF),
            outline = Color(0xFF4E4665),
            divider = Color(0xFF312B42),
            playerTint = Color(0xFF37225E),
            playerAccent = Color(0xFFDCC9FF),
            playerOnAccent = Color(0xFF2E1463),
            playerDock = Color(0xFF241540),
            playerButtonBg = Color(0xFF4C337B),
        ),
        light = ExpressivePaletteTone(
            canvas = Color(0xFFF8F6FD),
            headerTint = Color(0xFFE5DCFA),
            headerTitle = Color(0xFF422687),
            headerButtonBg = Color(0xFFD4C6F7),
            headerButtonFg = Color(0xFF2E166B),
            surfaceLow = Color(0xFFFFFFFF),
            surface = Color(0xFFF0EBF9),
            surfaceHigh = Color(0xFFE6DFF3),
            primary = Color(0xFF5D3FA8),
            onPrimary = Color(0xFFFFFFFF),
            primaryContainer = Color(0xFFE7DDFF),
            onPrimaryContainer = Color(0xFF230B59),
            secondary = Color(0xFF913E65),
            secondaryContainer = Color(0xFFE3DAF8),
            onSecondaryContainer = Color(0xFF31166B),
            outline = Color(0xFFC8BFD9),
            divider = Color(0xFFE0D9EC),
            playerTint = Color(0xFF452B75),
            playerAccent = Color(0xFFE4D5FF),
            playerOnAccent = Color(0xFF2E1463),
            playerDock = Color(0xFF2F1C52),
            playerButtonBg = Color(0xFF5C3E94),
        ),
    )

    val all: List<ExpressivePalettePreset> = listOf(
        SapphireInk,
        BerryVelvet,
        MintAurora,
        WarmTerracotta,
        ExpressiveViolet,
    )

    fun byId(id: String?): ExpressivePalettePreset =
        all.firstOrNull { it.id == id } ?: SapphireInk
}

/**
 * 全局原生外观状态存储（Material 3 Expressive 主题体系）：
 * 支持 5 套精选表现力色板、Android 12+ Material You 壁纸动态取色、AMOLED 纯黑模式、
 * 播放封面动态取色、圆角尺度自定义与底部导航栏风格切换。
 */
@Stable
class NativeAppearanceStore(context: Context? = null) {
    private val prefs = context?.getSharedPreferences("mp_appearance_v2", Context.MODE_PRIVATE)

    var mode by mutableStateOf(
        NativeAppearanceMode.fromId(prefs?.getString("mode", GeneratedDesignTokens.DEFAULT_MODE)),
    )
        private set

    var paletteId by mutableStateOf(
        prefs?.getString("palette_id", ExpressivePalettes.SapphireInk.id)
            ?: ExpressivePalettes.SapphireInk.id,
    )
        private set

    var pureBlackDark by mutableStateOf(prefs?.getBoolean("pure_black", false) ?: false)
        private set

    /** Android 12+ Material You 系统壁纸动态取色开关。 */
    var dynamicColorEnabled by mutableStateOf(prefs?.getBoolean("dynamic_color", false) ?: false)
        private set

    /** 播放界面与悬浮迷你播控条随封面自动取色。 */
    var albumArtDynamicColor by mutableStateOf(prefs?.getBoolean("album_art_color", true) ?: true)
        private set

    var cornerStyle by mutableStateOf(
        ExpressiveCornerStyle.fromId(prefs?.getString("corner_style", ExpressiveCornerStyle.Expressive.id)),
    )
        private set

    var navBarStyle by mutableStateOf(
        ExpressiveNavBarStyle.fromId(prefs?.getString("nav_bar_style", ExpressiveNavBarStyle.FloatingPill.id)),
    )
        private set

    var animateBackground by mutableStateOf(prefs?.getBoolean("animate_bg", false) ?: false)
        private set

    // 兼容旧属性读取
    val backgroundPresetId: String get() = paletteId
    val accentPresetId: String get() = paletteId

    fun updateMode(newMode: NativeAppearanceMode) {
        mode = newMode
        prefs?.edit()?.putString("mode", newMode.id)?.apply()
    }

    fun updatePalette(id: String) {
        paletteId = id
        prefs?.edit()?.putString("palette_id", id)?.apply()
    }

    fun updatePureBlackDark(enabled: Boolean) {
        pureBlackDark = enabled
        prefs?.edit()?.putBoolean("pure_black", enabled)?.apply()
    }

    fun updateDynamicColorEnabled(enabled: Boolean) {
        dynamicColorEnabled = enabled
        prefs?.edit()?.putBoolean("dynamic_color", enabled)?.apply()
    }

    fun updateAlbumArtDynamicColor(enabled: Boolean) {
        albumArtDynamicColor = enabled
        prefs?.edit()?.putBoolean("album_art_color", enabled)?.apply()
    }

    fun updateCornerStyle(style: ExpressiveCornerStyle) {
        cornerStyle = style
        prefs?.edit()?.putString("corner_style", style.id)?.apply()
    }

    fun updateNavBarStyle(style: ExpressiveNavBarStyle) {
        navBarStyle = style
        prefs?.edit()?.putString("nav_bar_style", style.id)?.apply()
    }

    fun updateAnimateBackground(enabled: Boolean) {
        animateBackground = enabled
        prefs?.edit()?.putBoolean("animate_bg", enabled)?.apply()
    }

    fun updateBackgroundPreset(id: String) = updatePalette(id)
    fun updateAccentPreset(id: String) = updatePalette(id)

    fun resetToDefaults() {
        updateMode(NativeAppearanceMode.Dark)
        updatePalette(ExpressivePalettes.SapphireInk.id)
        updatePureBlackDark(false)
        updateDynamicColorEnabled(false)
        updateAlbumArtDynamicColor(true)
        updateCornerStyle(ExpressiveCornerStyle.Expressive)
        updateNavBarStyle(ExpressiveNavBarStyle.FloatingPill)
        updateAnimateBackground(false)
    }

    val currentPreset: ExpressivePalettePreset
        get() = ExpressivePalettes.byId(paletteId)

    val summaryText: String
        get() {
            val base = if (dynamicColorEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                "Material You 壁纸取色"
            } else {
                currentPreset.titleZh
            }
            val oled = if (pureBlackDark) " · 纯黑" else ""
            return "${mode.title} · $base$oled"
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

/** 运行时颜色表（Material 3 Expressive 语义色阶，确保所有主次组件高对比可读）。 */
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
    // Material 3 Expressive 专属角色
    val headerTint: Color,
    val headerTitle: Color,
    val headerButtonBg: Color,
    val headerButtonFg: Color,
    val sheetSurface: Color,
    val cardRadiusDp: Int,
    val sheetRadiusDp: Int,
    val navBarStyle: ExpressiveNavBarStyle,
    val playerTint: Color,
    val playerAccent: Color,
    val playerOnAccent: Color,
    val playerDock: Color,
    val playerButtonBg: Color,
)

/** 根据背景色亮度自动挑选 AAA 级前景文字色（浅粉彩色用深墨色，深饱和色用纯白）。 */
fun Color.contrastingForeground(): Color =
    if (luminance() > 0.44f) Color(0xFF0C152B) else Color.White

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
    val preset = store.currentPreset
    val tone = if (isDark) preset.dark else preset.light

    val resolvedPrimary = dynamicScheme?.primary ?: tone.primary
    val resolvedOnPrimary = dynamicScheme?.onPrimary ?: tone.onPrimary
    val resolvedPrimaryContainer = dynamicScheme?.primaryContainer ?: tone.primaryContainer
    val resolvedOnPrimaryContainer = dynamicScheme?.onPrimaryContainer ?: tone.onPrimaryContainer

    val baseBg = if (isDark && store.pureBlackDark) {
        Color(0xFF000000)
    } else {
        dynamicScheme?.background ?: tone.canvas
    }
    val surfLow = if (isDark && store.pureBlackDark) {
        Color(0xFF10131A)
    } else {
        dynamicScheme?.surfaceContainerLow ?: tone.surfaceLow
    }
    val surfMid = if (isDark && store.pureBlackDark) {
        Color(0xFF161A23)
    } else {
        dynamicScheme?.surfaceContainer ?: tone.surface
    }
    val surfHigh = if (isDark && store.pureBlackDark) {
        Color(0xFF1F2533)
    } else {
        dynamicScheme?.surfaceContainerHigh ?: tone.surfaceHigh
    }

    val headerTint = if (dynamicScheme != null) {
        if (isDark) dynamicScheme.primaryContainer.copy(alpha = 0.58f).compositeOver(baseBg)
        else dynamicScheme.primaryContainer
    } else {
        tone.headerTint
    }
    val headerTitle = dynamicScheme?.primary ?: tone.headerTitle
    val headerBtnBg = if (dynamicScheme != null) {
        if (isDark) dynamicScheme.primaryContainer else dynamicScheme.primary.copy(alpha = 0.16f).compositeOver(headerTint)
    } else {
        tone.headerButtonBg
    }
    val headerBtnFg = dynamicScheme?.onPrimaryContainer ?: tone.headerButtonFg

    val playerTint = if (dynamicScheme != null) {
        if (isDark) dynamicScheme.tertiaryContainer.copy(alpha = 0.72f).compositeOver(Color(0xFF160F18))
        else dynamicScheme.tertiary.copy(alpha = 0.85f).compositeOver(Color(0xFF281322))
    } else {
        tone.playerTint
    }
    val playerAccent = if (dynamicScheme != null) dynamicScheme.onTertiaryContainer else tone.playerAccent
    val playerOnAccent = playerAccent.contrastingForeground()

    return MoviePilotColors(
        isDark = isDark,
        accent = resolvedPrimary,
        palette = listOf(baseBg, surfLow, surfMid, baseBg),
        textPrimary = dynamicScheme?.onSurface ?: if (isDark) Color(0xFFF0F2F8) else Color(0xFF121622),
        textSecondary = dynamicScheme?.onSurfaceVariant ?: if (isDark) Color(0xFFB3BCCF) else Color(0xFF4B556B),
        textMuted = dynamicScheme?.outline ?: if (isDark) Color(0xFF818BA3) else Color(0xFF727C94),
        success = s.success.resolve(isDark),
        warning = s.warning.resolve(isDark),
        danger = dynamicScheme?.error ?: s.danger.resolve(isDark),
        info = s.info.resolve(isDark),
        brand = dynamicScheme?.tertiary ?: resolvedPrimary,
        pink = dynamicScheme?.secondary ?: tone.secondary,
        cyan = s.cyan.resolve(isDark),
        chipFill = surfHigh,
        chipBorder = dynamicScheme?.outlineVariant ?: tone.outline.copy(alpha = 0.55f),
        chipText = dynamicScheme?.onSurface ?: if (isDark) Color(0xFFEAF0FA) else Color(0xFF161C2C),
        badgeFill = dynamicScheme?.secondaryContainer ?: tone.secondaryContainer,
        fieldFill = dynamicScheme?.surfaceContainerHighest ?: surfHigh,
        fieldBorder = dynamicScheme?.outlineVariant ?: tone.outline,
        divider = (dynamicScheme?.outlineVariant ?: tone.divider).copy(alpha = 0.75f),
        primaryButtonBg = resolvedPrimary,
        primaryButtonFg = resolvedOnPrimary,
        solidSurface = baseBg,
        surfaceContainerLow = surfLow,
        surfaceContainer = surfMid,
        surfaceContainerHigh = surfHigh,
        activeIndicator = dynamicScheme?.secondaryContainer ?: tone.secondaryContainer,
        headerTint = headerTint,
        headerTitle = headerTitle,
        headerButtonBg = headerBtnBg,
        headerButtonFg = headerBtnFg,
        sheetSurface = baseBg,
        cardRadiusDp = store.cornerStyle.cardDp,
        sheetRadiusDp = store.cornerStyle.sheetDp,
        navBarStyle = store.navBarStyle,
        playerTint = playerTint,
        playerAccent = playerAccent,
        playerOnAccent = playerOnAccent,
        playerDock = tone.playerDock,
        playerButtonBg = tone.playerButtonBg,
    )
}

private fun Color.compositeOver(background: Color): Color {
    val a = alpha.coerceIn(0f, 1f)
    return Color(
        red = red * a + background.red * (1f - a),
        green = green * a + background.green * (1f - a),
        blue = blue * a + background.blue * (1f - a),
        alpha = 1f,
    )
}

/** MoviePilot Android Material 3 Expressive 原生主题包装器。 */
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
    val tone = if (isDark) appearanceStore.currentPreset.dark else appearanceStore.currentPreset.light
    val materialScheme = if (dynamicScheme != null) {
        if (isDark && appearanceStore.pureBlackDark) {
            dynamicScheme.copy(
                background = Color.Black,
                surface = Color.Black,
                surfaceContainerLowest = Color.Black,
                surfaceContainerLow = colors.surfaceContainerLow,
                surfaceContainer = colors.surfaceContainer,
                surfaceContainerHigh = colors.surfaceContainerHigh,
            )
        } else {
            dynamicScheme
        }
    } else if (isDark) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = colors.primaryButtonFg,
            primaryContainer = tone.primaryContainer,
            onPrimaryContainer = tone.onPrimaryContainer,
            secondary = tone.secondary,
            onSecondary = tone.secondary.contrastingForeground(),
            secondaryContainer = tone.secondaryContainer,
            onSecondaryContainer = tone.onSecondaryContainer,
            tertiary = colors.brand,
            background = colors.solidSurface,
            onBackground = colors.textPrimary,
            surface = colors.solidSurface,
            onSurface = colors.textPrimary,
            surfaceVariant = colors.surfaceContainer,
            onSurfaceVariant = colors.textSecondary,
            surfaceContainerLowest = colors.solidSurface,
            surfaceContainerLow = colors.surfaceContainerLow,
            surfaceContainer = colors.surfaceContainer,
            surfaceContainerHigh = colors.surfaceContainerHigh,
            surfaceContainerHighest = colors.surfaceContainerHigh,
            outline = colors.fieldBorder,
            outlineVariant = colors.divider,
            error = colors.danger,
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = colors.primaryButtonFg,
            primaryContainer = tone.primaryContainer,
            onPrimaryContainer = tone.onPrimaryContainer,
            secondary = tone.secondary,
            onSecondary = Color.White,
            secondaryContainer = tone.secondaryContainer,
            onSecondaryContainer = tone.onSecondaryContainer,
            tertiary = colors.brand,
            background = colors.solidSurface,
            onBackground = colors.textPrimary,
            surface = colors.solidSurface,
            onSurface = colors.textPrimary,
            surfaceVariant = colors.surfaceContainer,
            onSurfaceVariant = colors.textSecondary,
            surfaceContainerLowest = colors.solidSurface,
            surfaceContainerLow = colors.surfaceContainerLow,
            surfaceContainer = colors.surfaceContainer,
            surfaceContainerHigh = colors.surfaceContainerHigh,
            surfaceContainerHighest = colors.surfaceContainerHigh,
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
