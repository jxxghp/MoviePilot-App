package com.moviepilot.designsystem

import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.view.WindowManager
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindowProvider

/**
 * 低雾感透色玻璃分组面板（严格对齐 iOS `CinematicPanel`）：
 * - 深色模式下透出底层星夜紫玫流光，仅叠极轻紫玫透色光泽 + 0.7dp 对角镜面高光细边，绝不发灰发黑；
 * - 浅色模式下呈现洁净磨砂白玻璃 + 淡主题色折射；
 * - 支持在悬浮表面开启 API 31+ 原生硬件 `RenderEffect.createBlurEffect` 实时背景折射模糊。
 */
@Composable
fun CinematicPanel(
    modifier: Modifier = Modifier,
    padding: Dp = GeneratedDesignTokens.PANEL_PADDING_DP.dp,
    cornerRadius: Dp = GeneratedDesignTokens.PANEL_CORNER_RADIUS_DP.dp,
    elevatedBlur: Boolean = false,
    showsShadow: Boolean = true,
    content: @Composable BoxScope.() -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val shape = RoundedCornerShape(cornerRadius)
    val isDark = colors.isDark

    val fillBrush = if (isDark) {
        Brush.linearGradient(
            colors = listOf(
                Color.White.copy(alpha = if (elevatedBlur) 0.13f else 0.085f),
                colors.accent.copy(alpha = if (elevatedBlur) 0.10f else 0.055f),
                Color(0xFFB36396).copy(alpha = if (elevatedBlur) 0.12f else 0.075f),
            ),
        )
    } else {
        Brush.linearGradient(
            colors = listOf(
                Color.White.copy(alpha = if (elevatedBlur) 0.78f else 0.64f),
                Color.White.copy(alpha = if (elevatedBlur) 0.66f else 0.52f),
                colors.accent.copy(alpha = 0.06f),
            ),
        )
    }

    val borderBrush = if (isDark) {
        Brush.linearGradient(
            colors = listOf(
                Color.White.copy(alpha = 0.24f),
                Color.White.copy(alpha = 0.08f),
                Color.White.copy(alpha = 0.15f),
            ),
        )
    } else {
        Brush.linearGradient(
            colors = listOf(
                Color.White.copy(alpha = 0.88f),
                Color.Black.copy(alpha = 0.08f),
                colors.accent.copy(alpha = 0.20f),
            ),
        )
    }

    val baseModifier = modifier
        .then(
            if (showsShadow) {
                Modifier.shadow(
                    elevation = if (isDark) 6.dp else 4.dp,
                    shape = shape,
                    ambientColor = Color.Black.copy(alpha = if (isDark) 0.22f else 0.08f),
                    spotColor = Color.Black.copy(alpha = if (isDark) 0.22f else 0.08f),
                )
            } else {
                Modifier
            },
        )
        .clip(shape)

    Box(modifier = baseModifier) {
        // 底层硬件 RenderEffect 柔化玻璃基材（API 31+），保持前景文字 100% 锐利不模糊
        Box(
            modifier = Modifier
                .matchParentSize()
                .then(
                    if (elevatedBlur && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Modifier.graphicsLayer {
                            renderEffect = RenderEffect.createBlurEffect(
                                18f,
                                18f,
                                Shader.TileMode.CLAMP,
                            ).asComposeRenderEffect()
                        }
                    } else {
                        Modifier
                    },
                )
                .background(
                    if (isDark) {
                        colors.palette.firstOrNull()?.copy(alpha = if (elevatedBlur) 0.58f else 0.30f)
                            ?: Color(0x4D2A2438)
                    } else {
                        Color.White.copy(alpha = if (elevatedBlur) 0.56f else 0.42f)
                    },
                ),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(fillBrush, shape)
                .border(
                    width = GeneratedDesignTokens.PANEL_BORDER_WIDTH_DP.dp,
                    brush = borderBrush,
                    shape = shape,
                )
                .padding(padding),
            content = content,
        )
    }
}

/** 为任意交互悬浮容器（底栏、+1 圆钮、溢出菜单）提供 API 31+ 原生硬件模糊玻璃基底。 */
@Composable
fun CinematicGlassSurface(
    shape: Shape,
    modifier: Modifier = Modifier,
    blurRadiusPx: Float = 26f,
    darkScrimAlpha: Float = 0.80f,
    lightScrimAlpha: Float = 0.86f,
    content: @Composable BoxScope.() -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val isDark = colors.isDark
    val borderBrush = if (isDark) {
        Brush.linearGradient(
            listOf(
                Color.White.copy(alpha = 0.34f),
                Color.White.copy(alpha = 0.10f),
                colors.accent.copy(alpha = 0.26f),
            ),
        )
    } else {
        Brush.linearGradient(
            listOf(
                Color.White.copy(alpha = 0.92f),
                Color.Black.copy(alpha = 0.08f),
                colors.accent.copy(alpha = 0.22f),
            ),
        )
    }

    Box(
        modifier = modifier
            .shadow(
                elevation = if (isDark) 12.dp else 8.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = if (isDark) 0.38f else 0.14f),
                spotColor = Color.Black.copy(alpha = if (isDark) 0.38f else 0.14f),
            )
            .clip(shape),
    ) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .then(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        Modifier.graphicsLayer {
                            renderEffect = RenderEffect.createBlurEffect(
                                blurRadiusPx,
                                blurRadiusPx,
                                Shader.TileMode.CLAMP,
                            ).asComposeRenderEffect()
                        }
                    } else {
                        Modifier
                    },
                )
                .background(
                    if (isDark) {
                        Color(0xFF231D32).copy(alpha = darkScrimAlpha)
                    } else {
                        Color.White.copy(alpha = lightScrimAlpha)
                    },
                ),
        )
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(
                    Brush.linearGradient(
                        if (isDark) {
                            listOf(
                                Color.White.copy(alpha = 0.14f),
                                colors.accent.copy(alpha = 0.08f),
                                Color(0xFFB36396).copy(alpha = 0.10f),
                            )
                        } else {
                            listOf(
                                Color.White.copy(alpha = 0.52f),
                                colors.accent.copy(alpha = 0.06f),
                            )
                        },
                    ),
                )
                .border(width = 0.85.dp, brush = borderBrush, shape = shape),
        )
        content()
    }
}

/**
 * 原生透明玻璃模态半屏弹窗（`NativeGlassSheet`）：
 * 基于 Material 3 `ModalBottomSheet` 完整保留原生下拉弹性手势与 Predictive Back，
 * 并在 API 31+ 开启系统级 `Window.setBackgroundBlurRadius`（`FLAG_BLUR_BEHIND`），绝不用 Box 伪造弹窗。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeGlassSheet(
    onDismissRequest: () -> Unit,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val sheetBg = if (colors.isDark) {
        colors.palette.getOrElse(1) { Color(0xFF342A42) }.copy(alpha = 0.90f)
    } else {
        colors.palette.firstOrNull()?.copy(alpha = 0.93f) ?: Color(0xEEF4F0FA)
    }

    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        shape = RoundedCornerShape(
            topStart = GeneratedDesignTokens.SHEET_CORNER_RADIUS_DP.dp,
            topEnd = GeneratedDesignTokens.SHEET_CORNER_RADIUS_DP.dp,
        ),
        containerColor = sheetBg,
        contentColor = colors.textPrimary,
        scrimColor = Color.Black.copy(alpha = if (colors.isDark) 0.42f else 0.22f),
    ) {
        val view = LocalView.current
        SideEffect {
            val window = (view.parent as? DialogWindowProvider)?.window
            if (window != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                window.addFlags(WindowManager.LayoutParams.FLAG_BLUR_BEHIND)
                window.attributes = window.attributes.apply {
                    blurBehindRadius = GeneratedDesignTokens.ANDROID_WINDOW_BLUR_PX
                }
            }
        }
        content()
    }
}
