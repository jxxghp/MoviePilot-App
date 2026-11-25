package com.moviepilot.pluginhost.runtime

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import com.moviepilot.designsystem.MoviePilotColors
import com.moviepilot.designsystem.NativeAppearanceStore
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Android 端视觉融合 Token 投影器（与 `MoviePilot-Frontend/src/plugin-shell/types.ts` `NativeVisualTokens` 1:1 对齐），
 * 自动继承 Material You 动态壁纸取色、AMOLED 纯黑模式、自定义圆角尺度与系统字体缩放。
 */
data class AndroidPluginVisualTokens(
    val mode: String,
    val platform: String = "android",
    val backgroundPreset: String,
    val isAmoledBlack: Boolean = false,
    val highContrast: Boolean = false,
    val accentHex: String,
    val onAccentHex: String,
    val textPrimaryHex: String,
    val textSecondaryHex: String,
    val surfaceGlassRgba: String,
    val surfaceElevatedRgba: String,
    val surfaceBorderRgba: String,
    val surfaceBlurPx: Int = 18,
    val solidSurfaceHex: String,
    val fieldFillRgba: String,
    val fieldBorderRgba: String,
    val chipFillRgba: String,
    val chipBorderRgba: String,
    val dividerRgba: String,
    val panelRadiusPx: Int,
    val sheetRadiusPx: Int,
    val borderWidthPx: Double = 0.75,
    val successHex: String,
    val warningHex: String,
    val dangerHex: String,
    val infoHex: String,
    val brandHex: String,
) {
    fun toJsonObject(): JsonObject = buildJsonObject {
        put("mode", mode)
        put("platform", platform)
        put("backgroundPreset", backgroundPreset)
        put("isAmoledBlack", isAmoledBlack)
        put("highContrast", highContrast)
        put("accentHex", accentHex)
        put("onAccentHex", onAccentHex)
        put("textPrimaryHex", textPrimaryHex)
        put("textSecondaryHex", textSecondaryHex)
        put("surfaceGlassRgba", surfaceGlassRgba)
        put("surfaceElevatedRgba", surfaceElevatedRgba)
        put("surfaceBorderRgba", surfaceBorderRgba)
        put("surfaceBlurPx", surfaceBlurPx)
        put("solidSurfaceHex", solidSurfaceHex)
        put("fieldFillRgba", fieldFillRgba)
        put("fieldBorderRgba", fieldBorderRgba)
        put("chipFillRgba", chipFillRgba)
        put("chipBorderRgba", chipBorderRgba)
        put("dividerRgba", dividerRgba)
        put("panelRadiusPx", panelRadiusPx)
        put("sheetRadiusPx", sheetRadiusPx)
        put("borderWidthPx", borderWidthPx)
        put(
            "semantic",
            buildJsonObject {
                put("success", successHex)
                put("warning", warningHex)
                put("danger", dangerHex)
                put("info", infoHex)
                put("brand", brandHex)
            },
        )
    }

    companion object {
        fun from(
            colors: MoviePilotColors,
            appearance: NativeAppearanceStore,
            @Suppress("UNUSED_PARAMETER") fontScale: Float,
        ): AndroidPluginVisualTokens {
            val isDark = colors.isDark
            val amoled = isDark && appearance.pureBlackDark
            val accentHex = colors.accent.toHex6()
            val onAccentHex = if (colors.accent.luminance() > 0.55f) "#18181B" else "#FFFFFF"
            val surfaceGlass = if (amoled) {
                "rgba(18,21,28,0.88)"
            } else if (isDark) {
                colors.surfaceContainer.toRgba(0.76f)
            } else {
                colors.surfaceContainerLow.toRgba(0.84f)
            }
            val surfaceElevated = if (amoled) {
                "rgba(26,30,40,0.94)"
            } else if (isDark) {
                colors.surfaceContainerHigh.toRgba(0.90f)
            } else {
                colors.surfaceContainer.toRgba(0.94f)
            }
            return AndroidPluginVisualTokens(
                mode = if (isDark) "dark" else "light",
                backgroundPreset = appearance.paletteId,
                isAmoledBlack = amoled,
                accentHex = accentHex,
                onAccentHex = onAccentHex,
                textPrimaryHex = colors.textPrimary.toHex6(),
                textSecondaryHex = colors.textSecondary.toHex6(),
                surfaceGlassRgba = surfaceGlass,
                surfaceElevatedRgba = surfaceElevated,
                surfaceBorderRgba = colors.divider.toRgba(if (isDark) 0.34f else 0.24f),
                solidSurfaceHex = colors.solidSurface.toHex6(),
                fieldFillRgba = colors.fieldFill.toRgba(if (isDark) 0.55f else 0.85f),
                fieldBorderRgba = colors.fieldBorder.toRgba(if (isDark) 0.42f else 0.32f),
                chipFillRgba = colors.chipFill.toRgba(if (isDark) 0.72f else 0.82f),
                chipBorderRgba = colors.chipBorder.toRgba(if (isDark) 0.38f else 0.24f),
                dividerRgba = colors.divider.toRgba(if (isDark) 0.28f else 0.20f),
                panelRadiusPx = colors.cardRadiusDp.coerceIn(12, 24),
                sheetRadiusPx = colors.sheetRadiusDp.coerceIn(16, 28),
                successHex = colors.success.toHex6(),
                warningHex = colors.warning.toHex6(),
                dangerHex = colors.danger.toHex6(),
                infoHex = colors.info.toHex6(),
                brandHex = colors.brand.toHex6(),
            )
        }

        private fun Color.toHex6(): String = String.format("#%06X", 0xFFFFFF and toArgb())

        private fun Color.toRgba(alphaOverride: Float): String {
            val argb = toArgb()
            val r = (argb shr 16) and 0xFF
            val g = (argb shr 8) and 0xFF
            val b = argb and 0xFF
            return String.format(java.util.Locale.US, "rgba(%d,%d,%d,%.2f)", r, g, b, alphaOverride)
        }
    }
}
