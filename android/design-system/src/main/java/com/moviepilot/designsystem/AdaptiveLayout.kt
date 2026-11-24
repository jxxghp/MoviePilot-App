package com.moviepilot.designsystem

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 响应式多形态布局计算器（手机 / 折叠屏展开 / 平板横屏），1:1 对齐 `shared/design-tokens/layout.json`。
 */
object AdaptiveDeviceLayout {

    /** 侧边常驻 NavigationRail 标准宽度。 */
    val WideRailWidth: Dp = 80.dp

    /** 当前窗口是否达到宽屏阈值（>= 600dp 切换并常驻侧边 NavigationRail）。 */
    @Composable
    fun isWideCanvas(): Boolean = LocalConfiguration.current.screenWidthDp >= 600

    /** 当前窗口是否为短高度视口（手机横屏或上下分屏，< 480dp）。 */
    @Composable
    fun isCompactHeight(): Boolean = LocalConfiguration.current.screenHeightDp < 480

    /** 当前窗口是否处于横屏比例（宽 > 高）。 */
    @Composable
    fun isLandscape(): Boolean = LocalConfiguration.current.let { it.screenWidthDp > it.screenHeightDp }

    /** 当前窗口是否达到超宽桌面/平板横屏阈值。 */
    @Composable
    fun isExpandedCanvas(): Boolean = LocalConfiguration.current.screenWidthDp >= GeneratedDesignTokens.BREAKPOINT_EXPANDED_DP

    /** 扣除宽屏侧边导航栏后的主内容有效可用宽度（dp）。 */
    @Composable
    fun effectiveContentWidthDp(): Int {
        val w = LocalConfiguration.current.screenWidthDp
        return if (w >= 600) (w - WideRailWidth.value.toInt()).coerceAtLeast(320) else w
    }

    /** 水平舒适边距（手机 20dp / 宽屏 24dp / 超宽屏 28dp）。 */
    @Composable
    fun horizontalMargin(): Dp {
        val w = effectiveContentWidthDp()
        return when {
            w >= 880 -> GeneratedDesignTokens.MARGIN_EXPANDED_DP.dp
            w >= 600 -> GeneratedDesignTokens.MARGIN_WIDE_DP.dp
            else -> GeneratedDesignTokens.MARGIN_COMPACT_DP.dp
        }
    }

    /** 2:3 竖版海报网格列数（3 ~ 6 列自适应，已扣除侧边导航栏宽度）。 */
    @Composable
    fun posterGridColumns(): Int {
        val w = effectiveContentWidthDp()
        return when {
            w >= 960 -> 6
            w >= 700 -> 5
            w >= 500 -> 4
            else -> 3
        }
    }

    /** 1:1 音乐方卡网格列数（2 ~ 5 列自适应，已扣除侧边导航栏宽度）。 */
    @Composable
    fun squareGridColumns(): Int {
        val w = effectiveContentWidthDp()
        return when {
            w >= 900 -> 5
            w >= 640 -> 4
            w >= 480 -> 3
            else -> 2
        }
    }

    /** 业务信息卡片列数（有效内容宽 >= 660dp 双列，否则单列）。 */
    @Composable
    fun cardGridColumns(): Int = if (effectiveContentWidthDp() >= 660) 2 else 1

    /** 发现页横向海报卡宽度。 */
    @Composable
    fun discoverPosterWidth(): Dp {
        val cfg = LocalConfiguration.current
        val w = effectiveContentWidthDp()
        return when {
            cfg.screenHeightDp < 480 && cfg.screenWidthDp > cfg.screenHeightDp -> 118.dp
            w >= 880 -> 148.dp
            w >= 600 -> 136.dp
            else -> 112.dp
        }
    }

    /** 发现页首屏主视觉高度（手机横屏紧凑限高以露出首排货架，平板与竖屏保持沉浸比例）。 */
    @Composable
    fun discoverHeroHeight(): Dp {
        val cfg = LocalConfiguration.current
        val w = cfg.screenWidthDp
        val h = cfg.screenHeightDp
        val computed = when {
            w > h && h < 480 -> (h * 0.60f).coerceIn(212f, 264f)
            w >= 740 && w > h -> (h * 0.56f).coerceIn(330f, 460f)
            w >= 740 -> (h * 0.54f).coerceIn(480f, 620f)
            else -> (h * 0.58f).coerceIn(430f, 560f)
        }
        return computed.dp
    }
}
