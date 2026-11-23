package com.moviepilot.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeProgressive
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect

/**
 * 局部 GPU 渐进模糊源状态（仅用于全幅摄影背景页与顶部状态栏渐进防重叠模糊）。
 */
val LocalHazeState = compositionLocalOf<HazeState?> { null }

/**
 * Android Material Design 3 实色 Tonal Surface 卡片容器：
 * - 严格遵循 Material Design 3 表面层级（不透明 `surfaceContainerLow` / `surfaceContainer`），
 *   彻底摒弃 iOS 玻璃半透明与对角白色镜面高光边框；
 * - 通过实色阶对比与干净的 16dp~20dp 圆角建立清晰信息层级，兼容 Android 12+ Material You 动态取色。
 */
@Composable
fun CinematicPanel(
    modifier: Modifier = Modifier,
    padding: Dp = GeneratedDesignTokens.PANEL_PADDING_DP.dp,
    cornerRadius: Dp = Dp.Unspecified,
    elevatedBlur: Boolean = false,
    showsShadow: Boolean = false,
    content: @Composable BoxScope.() -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val resolvedRadius = if (cornerRadius == Dp.Unspecified) {
        colors.cardRadiusDp.dp
    } else {
        // 尊重用户所选 Material 3 Expressive 圆角尺度，同时保留显式小胶囊/大圆角语义
        ((cornerRadius.value + colors.cardRadiusDp) / 2f).coerceIn(12f, 26f).dp
    }
    val shape = RoundedCornerShape(resolvedRadius)
    val containerColor = if (elevatedBlur) {
        MaterialTheme.colorScheme.surfaceContainerHigh
    } else {
        MaterialTheme.colorScheme.surfaceContainerLow
    }

    Box(
        modifier = modifier
            .then(
                if (showsShadow && !colors.isDark) {
                    Modifier.shadow(
                        elevation = 1.dp,
                        shape = shape,
                        ambientColor = Color.Black.copy(alpha = 0.08f),
                        spotColor = Color.Black.copy(alpha = 0.08f),
                    )
                } else {
                    Modifier
                },
            )
            .clip(shape)
            .background(containerColor, shape),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding),
            content = content,
        )
    }
}

/**
 * 悬浮摄影前景控件容器（专用于覆盖在影视海报/剧照上的搜索圆钮、详情返回圆钮与悬浮迷你播放条）：
 * 采用高对比度 Material 3 Tonal Scrim + 可选局部 Haze 模糊，确保在任意明暗海报上清晰可读。
 */
@Composable
fun CinematicGlassSurface(
    shape: Shape,
    modifier: Modifier = Modifier,
    blurRadiusDp: Dp = 20.dp,
    darkTintAlpha: Float = 0.72f,
    lightTintAlpha: Float = 0.86f,
    useLiveBackdropBlur: Boolean = true,
    content: @Composable BoxScope.() -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val hazeState = LocalHazeState.current
    val isDark = colors.isDark
    val surfaceColor = MaterialTheme.colorScheme.surfaceContainerHigh
    val fillAlpha = if (isDark) darkTintAlpha else lightTintAlpha
    val borderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = if (isDark) 0.55f else 0.70f)

    val hazeStyle = HazeStyle(
        backgroundColor = surfaceColor,
        tints = listOf(HazeTint(surfaceColor.copy(alpha = fillAlpha))),
        blurRadius = blurRadiusDp,
        noiseFactor = 0.01f,
    )

    Box(
        modifier = modifier
            .shadow(
                elevation = if (isDark) 6.dp else 4.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = if (isDark) 0.36f else 0.14f),
                spotColor = Color.Black.copy(alpha = if (isDark) 0.36f else 0.14f),
            )
            .clip(shape)
            .border(width = 0.75.dp, color = borderColor, shape = shape),
    ) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .then(
                    if (useLiveBackdropBlur && hazeState != null) {
                        Modifier.hazeEffect(state = hazeState, style = hazeStyle)
                    } else {
                        Modifier.background(surfaceColor.copy(alpha = (fillAlpha + 0.14f).coerceAtMost(0.96f)))
                    },
                ),
        )
        content()
    }
}

/** 顶部组合操作 Tonal 胶囊（Material 3 `surfaceContainerHigh` 实色圆胶囊）。 */
@Composable
fun CinematicGlassCapsule(
    modifier: Modifier = Modifier,
    content: @Composable RowScope.() -> Unit,
) {
    CinematicGlassSurface(
        shape = CircleShape,
        useLiveBackdropBlur = false,
        darkTintAlpha = 0.88f,
        lightTintAlpha = 0.94f,
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

/**
 * Android Material Design 3 标准模态底部表单（ModalBottomSheet）：
 * 采用实色 `surfaceContainerLow` 表面、28dp 顶部圆角、标准拖动手柄、外部轻点与系统 Back 返回关闭。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeGlassSheet(
    onDismissRequest: () -> Unit,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        contentColor = colors.textPrimary,
        scrimColor = Color.Black.copy(alpha = if (colors.isDark) 0.54f else 0.32f),
        content = content,
    )
}

/**
 * 顶部状态栏渐进模糊与安全区柔化罩：
 * - 在首屏全幅海报页（`visibilityProgress == 0f`）完全隐藏，保持顶部海报 100% 清透；
 * - 向上滚动后通过 Haze GPU `HazeProgressive.verticalGradient` 从状态栏顶部 100% 模糊羽化至底部透明，
 *   并自然融入 Material 3 `colorScheme.background`，彻底杜绝滚动内容与系统状态栏图标重叠。
 */
@Composable
fun NativeTopStatusBarProgressiveBlur(
    visibilityProgress: Float = 1f,
    extraHeight: Dp = 38.dp,
    blurSourceState: HazeState? = null,
    modifier: Modifier = Modifier,
) {
    val alpha = visibilityProgress.coerceIn(0f, 1f)
    if (alpha <= 0.005f) return

    val colors = LocalMoviePilotColors.current
    val statusBarTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val totalHeight = statusBarTop + extraHeight
    val veilBase = MaterialTheme.colorScheme.background
    val hazeStyle = HazeStyle(
        backgroundColor = veilBase,
        tints = listOf(HazeTint(veilBase.copy(alpha = if (colors.isDark) 0.46f else 0.62f))),
        blurRadius = 22.dp,
        noiseFactor = 0.01f,
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(totalHeight)
            .graphicsLayer { this.alpha = alpha },
    ) {
        if (blurSourceState != null) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .hazeEffect(state = blurSourceState, style = hazeStyle) {
                        progressive = HazeProgressive.verticalGradient(
                            startIntensity = 1f,
                            endIntensity = 0f,
                        )
                    },
            )
        }
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        0.0f to veilBase.copy(alpha = if (colors.isDark) 0.96f else 0.97f),
                        0.46f to veilBase.copy(alpha = if (colors.isDark) 0.78f else 0.84f),
                        0.78f to veilBase.copy(alpha = if (colors.isDark) 0.34f else 0.42f),
                        1.0f to Color.Transparent,
                    ),
                ),
        )
    }
}
