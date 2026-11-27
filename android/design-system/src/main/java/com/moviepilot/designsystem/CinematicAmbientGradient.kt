package com.moviepilot.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Android Material Design 3 沉稳中性画布背景：
 * - 默认采用纯正 Material 3 `colorScheme.background` 实色低眩光底面（深色 `#121116` / 浅色 `#FCF8FF`），
 *   绝不以高饱和紫色霓虹雾背景干扰影视海报与数据层级；
 * - 若用户在「主题与外观」中主动开启柔光氛围，则通过 `drawWithCache` 零分配静态缓存顶部主题径向光晕，
 *   避免后台持续帧定时器在列表滚动期间引发全屏重绘与 GPU 过载。
 */
@Composable
fun CinematicAmbientGradient(
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val store = LocalAppearanceStore.current
    val bgColor = MaterialTheme.colorScheme.background
    val showGlow = store.animateBackground
    val glowColor = colors.accent.copy(alpha = if (colors.isDark) 0.10f else 0.07f)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(bgColor)
            .then(
                if (showGlow) {
                    Modifier.drawWithCache {
                        val brush = Brush.radialGradient(
                            colors = listOf(glowColor, Color.Transparent),
                            center = Offset(size.width * 0.5f, size.height * 0.14f),
                            radius = size.maxDimension * 0.65f,
                        )
                        onDrawBehind {
                            drawRect(brush = brush)
                        }
                    }
                } else {
                    Modifier
                },
            ),
    )
}
