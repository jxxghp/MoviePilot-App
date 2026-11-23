package com.moviepilot.designsystem

import android.content.res.Configuration
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage

/**
 * Android Material Design 3 顶级 5 大对等导航目标（方案 A）：
 * 发现 · 探索 · 订阅 · 更多 · 我的（设置位于「我的」顶栏右上角，全局搜索位于各影音页顶栏右上角）。
 */
enum class MainTab(val id: String, val label: String) {
    Discover("discover", "发现"),
    Explore("explore", "探索"),
    Subscribe("subscribe", "订阅"),
    Workspace("workspace", "更多"),
    Dashboard("dashboard", "我的"),
}

/** 品牌特色带闪星的圆角电视屏图标，用于「发现」主导航。 */
@Composable
private fun DiscoverTvSparkleIcon(
    tint: Color,
    cutoutColor: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        drawRoundRect(
            color = tint,
            topLeft = Offset(w * 0.06f, h * 0.14f),
            size = Size(w * 0.88f, h * 0.62f),
            cornerRadius = CornerRadius(w * 0.15f, w * 0.15f),
        )
        drawRoundRect(
            color = tint,
            topLeft = Offset(w * 0.30f, h * 0.83f),
            size = Size(w * 0.40f, h * 0.09f),
            cornerRadius = CornerRadius(w * 0.05f, w * 0.05f),
        )
        fun drawStar(cx: Float, cy: Float, r: Float) {
            val inner = r * 0.28f
            val p = Path().apply {
                moveTo(cx, cy - r)
                quadraticTo(cx + inner, cy - inner, cx + r, cy)
                quadraticTo(cx + inner, cy + inner, cx, cy + r)
                quadraticTo(cx - inner, cy + inner, cx - r, cy)
                quadraticTo(cx - inner, cy - inner, cx, cy - r)
                close()
            }
            drawPath(p, color = cutoutColor)
        }
        drawStar(w * 0.56f, h * 0.47f, w * 0.18f)
        drawStar(w * 0.34f, h * 0.33f, w * 0.08f)
    }
}

@Composable
private fun MainTabIcon(
    tab: MainTab,
    active: Boolean,
    tint: Color,
    userAvatarUrl: String?,
    userInitial: String,
) {
    val colors = LocalMoviePilotColors.current
    when (tab) {
        MainTab.Discover -> {
            DiscoverTvSparkleIcon(
                tint = tint,
                cutoutColor = if (colors.isDark) colors.surfaceContainerHigh else Color(0xFFF6F2FC),
                modifier = Modifier.size(22.dp),
            )
        }
        MainTab.Explore -> {
            Icon(
                imageVector = if (active) Icons.Rounded.Explore else Icons.Outlined.Explore,
                contentDescription = tab.label,
                tint = tint,
                modifier = Modifier.size(23.dp),
            )
        }
        MainTab.Subscribe -> {
            Icon(
                imageVector = if (active) Icons.Rounded.Bookmark else Icons.Outlined.BookmarkBorder,
                contentDescription = tab.label,
                tint = tint,
                modifier = Modifier.size(23.dp),
            )
        }
        MainTab.Workspace -> {
            Icon(
                imageVector = if (active) Icons.Rounded.MoreHoriz else Icons.Outlined.MoreHoriz,
                contentDescription = tab.label,
                tint = tint,
                modifier = Modifier.size(24.dp),
            )
        }
        MainTab.Dashboard -> {
            Box(
                modifier = Modifier
                    .size(24.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer)
                    .border(
                        width = if (active) 1.8.dp else 0.9.dp,
                        color = if (active) MaterialTheme.colorScheme.primary else colors.chipBorder,
                        shape = CircleShape,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                if (!userAvatarUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = userAvatarUrl,
                        contentDescription = tab.label,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(24.dp).clip(CircleShape),
                    )
                } else {
                    Text(
                        text = userInitial.take(1).uppercase(),
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

/**
 * Android Material Design 3 标准全宽贴底 5 Tab 导航栏（NavigationBar 规范）：
 * - 手机端采用边缘到边缘贴底 `NavigationBar`，配 64×32dp 激活胶囊指示器、Filled/Outlined 图标切换、原生 Ripple 与触觉反馈；
 * - 底层融合 Haze GPU 轻微磨砂与 Material 3 `surfaceContainer` 色调，既保留通透现代感又完全贴合 Android 肌肉记忆；
 * - 取消 iOS 的 `+1` 独立搜索球与重复点击隐藏菜单，所有 5 大核心模块显性直达。
 */
@Composable
fun MoviePilotBottomNavigationBar(
    selectedTab: MainTab,
    onTabClick: (MainTab) -> Unit,
    userAvatarUrl: String? = null,
    userInitial: String = "M",
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val haptic = LocalHapticFeedback.current
    val barBg = MaterialTheme.colorScheme.surfaceContainer

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(barBg),
    ) {
        HorizontalDivider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
        )
        NavigationBar(
            containerColor = barBg,
            tonalElevation = 0.dp,
            windowInsets = WindowInsets.navigationBars,
            modifier = Modifier.fillMaxWidth(),
        ) {
            MainTab.entries.forEach { tab ->
                val active = tab == selectedTab
                NavigationBarItem(
                    selected = active,
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        onTabClick(tab)
                    },
                    icon = {
                        MainTabIcon(
                            tab = tab,
                            active = active,
                            tint = if (active) MaterialTheme.colorScheme.onSecondaryContainer else colors.textSecondary,
                            userAvatarUrl = userAvatarUrl,
                            userInitial = userInitial,
                        )
                    },
                    label = {
                        Text(
                            text = tab.label,
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Clip,
                        )
                    },
                    alwaysShowLabel = true,
                    colors = NavigationBarItemDefaults.colors(
                        indicatorColor = MaterialTheme.colorScheme.secondaryContainer,
                        selectedIconColor = MaterialTheme.colorScheme.onSecondaryContainer,
                        selectedTextColor = colors.textPrimary,
                        unselectedIconColor = colors.textSecondary,
                        unselectedTextColor = colors.textSecondary,
                    ),
                )
            }
        }
    }
}

/**
 * Android Material Design 3 宽屏 / 折叠屏展开 / 平板侧边导航栏（NavigationRail 规范）：
 * 当窗口宽度 >= 680dp 时自动替换底部 NavigationBar，顶置 Material 3 搜索 FAB。
 */
@Composable
fun FloatingNavigationRail(
    selectedTab: MainTab,
    onTabClick: (MainTab) -> Unit,
    onSearchClick: () -> Unit,
    userAvatarUrl: String? = null,
    userInitial: String = "M",
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val haptic = LocalHapticFeedback.current
    NavigationRail(
        modifier = modifier
            .fillMaxHeight()
            .statusBarsPadding()
            .navigationBarsPadding(),
        containerColor = colors.surfaceContainerLow.copy(alpha = if (colors.isDark) 0.90f else 0.95f),
        header = {
            Spacer(Modifier.height(12.dp))
            FloatingActionButton(
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onSearchClick()
                },
                shape = RoundedCornerShape(16.dp),
                containerColor = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 2.dp),
            ) {
                Icon(Icons.Rounded.Search, contentDescription = "全局搜索")
            }
            Spacer(Modifier.height(12.dp))
        },
    ) {
        MainTab.entries.forEach { tab ->
            val active = tab == selectedTab
            NavigationRailItem(
                selected = active,
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onTabClick(tab)
                },
                icon = {
                    MainTabIcon(
                        tab = tab,
                        active = active,
                        tint = if (active) MaterialTheme.colorScheme.onSecondaryContainer else colors.textSecondary,
                        userAvatarUrl = userAvatarUrl,
                        userInitial = userInitial,
                    )
                },
                label = {
                    Text(
                        text = tab.label,
                        style = MaterialTheme.typography.labelSmall,
                    )
                },
                colors = NavigationRailItemDefaults.colors(
                    indicatorColor = MaterialTheme.colorScheme.secondaryContainer,
                    selectedIconColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    selectedTextColor = colors.textPrimary,
                    unselectedIconColor = colors.textSecondary,
                    unselectedTextColor = colors.textSecondary,
                ),
            )
        }
    }
}

@Preview(name = "BottomNav Dark", uiMode = Configuration.UI_MODE_NIGHT_YES, showBackground = true)
@Preview(name = "BottomNav Light", uiMode = Configuration.UI_MODE_NIGHT_NO, showBackground = true)
@Composable
private fun PreviewMoviePilotBottomNav() {
    MoviePilotTheme(appearanceStore = NativeAppearanceStore(null)) {
        MoviePilotBottomNavigationBar(
            selectedTab = MainTab.Discover,
            onTabClick = {},
        )
    }
}
