package com.moviepilot.designsystem

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 响应式多形态布局计算器（手机 / 折叠屏展开 / 平板横屏），1:1 对齐 `shared/design-tokens/layout.json`。
 */
object AdaptiveDeviceLayout {

    /** 当前窗口是否达到宽屏阈值（>= 600dp 切换并常驻侧边 NavigationRail）。 */
    @Composable
    fun isWideCanvas(): Boolean = LocalConfiguration.current.screenWidthDp >= 600

    /** 当前窗口是否达到超宽桌面/平板横屏阈值。 */
    @Composable
    fun isExpandedCanvas(): Boolean = LocalConfiguration.current.screenWidthDp >= GeneratedDesignTokens.BREAKPOINT_EXPANDED_DP

    /** 水平舒适边距（手机 20dp / 宽屏 24dp / 超宽屏 28dp）。 */
    @Composable
    fun horizontalMargin(): Dp {
        val w = LocalConfiguration.current.screenWidthDp
        return when {
            w >= 960 -> GeneratedDesignTokens.MARGIN_EXPANDED_DP.dp
            w >= 680 -> GeneratedDesignTokens.MARGIN_WIDE_DP.dp
            else -> GeneratedDesignTokens.MARGIN_COMPACT_DP.dp
        }
    }

    /** 2:3 竖版海报网格列数（3 ~ 6 列自适应）。 */
    @Composable
    fun posterGridColumns(): Int {
        val w = LocalConfiguration.current.screenWidthDp
        return when {
            w >= 1040 -> 6
            w >= 780 -> 5
            w >= 540 -> 4
            else -> 3
        }
    }

    /** 1:1 音乐方卡网格列数（2 ~ 5 列自适应）。 */
    @Composable
    fun squareGridColumns(): Int {
        val w = LocalConfiguration.current.screenWidthDp
        return when {
            w >= 980 -> 5
            w >= 720 -> 4
            w >= 500 -> 3
            else -> 2
        }
    }

    /** 业务信息卡片列数（>= 740dp 双列，否则单列）。 */
    @Composable
    fun cardGridColumns(): Int = if (LocalConfiguration.current.screenWidthDp >= 740) 2 else 1

    /** 发现页横向海报卡宽度。 */
    @Composable
    fun discoverPosterWidth(): Dp {
        val w = LocalConfiguration.current.screenWidthDp
        return when {
            w >= 960 -> 148.dp
            w >= 680 -> 136.dp
            else -> 112.dp
        }
    }

    /** 发现页首屏主视觉高度。 */
    @Composable
    fun discoverHeroHeight(): Dp {
        val cfg = LocalConfiguration.current
        val w = cfg.screenWidthDp
        val h = cfg.screenHeightDp
        val computed = when {
            w >= 740 && w > h -> (h * 0.60f).coerceIn(420f, 560f)
            w >= 740 -> (h * 0.54f).coerceIn(480f, 620f)
            else -> (h * 0.58f).coerceIn(430f, 560f)
        }
        return computed.dp
    }
}
