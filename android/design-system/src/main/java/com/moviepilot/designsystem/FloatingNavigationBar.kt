package com.moviepilot.designsystem

import android.content.res.Configuration
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage

/**
 * Android Material 3 Expressive 顶级 5 大对等导航目标：
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
                cutoutColor = if (active) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainer,
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
                NativeNetworkEntityLogo(
                    imageUrl = userAvatarUrl,
                    kind = "avatar",
                    value = userInitial,
                    size = 24.dp,
                    cornerRadius = 12.dp,
                )
            }
        }
    }
}

/**
 * Material 3 Expressive 底部 5 Tab 导航栏：
 * - 默认采用 **圆角悬浮导航栏**（`FloatingPill`：外层 `32.dp` 悬浮圆角胶囊底座 + 柔和层级阴影）；
 * - 选中态将 **图标与文字整体包裹在同一圆角胶囊指示器内** 联合高亮，杜绝图标与文字割裂感；
 * - 支持在「外观与主题」中切换为 **圆角贴底**（`RoundedDock`）模式。
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
    val scheme = MaterialTheme.colorScheme
    val haptic = LocalHapticFeedback.current
    val barBg = scheme.surfaceContainer
    val isFloating = colors.navBarStyle == ExpressiveNavBarStyle.FloatingPill
    val barShape = if (isFloating) {
        RoundedCornerShape(32.dp)
    } else {
        RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp)
    }
    val activeFg = if (colors.isDark) scheme.primary else scheme.onSecondaryContainer

    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (isFloating) {
                    Modifier
                        .navigationBarsPadding()
                        .padding(horizontal = 14.dp, vertical = 10.dp)
                } else {
                    Modifier
                },
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(
                    elevation = if (isFloating) (if (colors.isDark) 12.dp else 8.dp) else (if (colors.isDark) 8.dp else 5.dp),
                    shape = barShape,
                    ambientColor = Color.Black.copy(alpha = if (colors.isDark) 0.50f else 0.16f),
                    spotColor = Color.Black.copy(alpha = if (colors.isDark) 0.50f else 0.16f),
                )
                .clip(barShape)
                .background(barBg, barShape)
                .border(
                    width = 0.8.dp,
                    color = scheme.outlineVariant.copy(alpha = if (colors.isDark) 0.50f else 0.72f),
                    shape = barShape,
                )
                .then(if (!isFloating) Modifier.navigationBarsPadding() else Modifier),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(68.dp)
                    .padding(horizontal = 6.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MainTab.entries.forEach { tab ->
                    val active = tab == selectedTab
                    val pillBg by animateColorAsState(
                        targetValue = if (active) scheme.secondaryContainer else Color.Transparent,
                        animationSpec = tween(200),
                        label = "navPillBg",
                    )
                    val contentColor by animateColorAsState(
                        targetValue = if (active) activeFg else colors.textSecondary,
                        animationSpec = tween(200),
                        label = "navPillFg",
                    )
                    val interaction = remember { MutableInteractionSource() }
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(24.dp))
                            .background(pillBg, RoundedCornerShape(24.dp))
                            .clickable(
                                interactionSource = interaction,
                                indication = ripple(bounded = true, color = scheme.primary),
                                role = Role.Tab,
                                onClick = {
                                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    onTabClick(tab)
                                },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            MainTabIcon(
                                tab = tab,
                                active = active,
                                tint = contentColor,
                                userAvatarUrl = userAvatarUrl,
                                userInitial = userInitial,
                            )
                            Text(
                                text = tab.label,
                                color = contentColor,
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontSize = 11.sp,
                                    fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                                ),
                                maxLines = 1,
                                overflow = TextOverflow.Clip,
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Android Material 3 Expressive 宽屏 / 折叠屏展开 / 平板侧边导航栏（NavigationRail 规范）：
 * 当窗口宽度 >= 680dp 时自动替换底部 NavigationBar，顶置高对比圆形/圆角搜索 FAB。
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
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        header = {
            Spacer(Modifier.height(14.dp))
            FloatingActionButton(
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    onSearchClick()
                },
                shape = CircleShape,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
                elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 2.dp),
            ) {
                Icon(Icons.Rounded.Search, contentDescription = "全局搜索")
            }
            Spacer(Modifier.height(14.dp))
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
                        tint = if (active) MaterialTheme.colorScheme.primary else colors.textSecondary,
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
                    selectedIconColor = MaterialTheme.colorScheme.primary,
                    selectedTextColor = MaterialTheme.colorScheme.primary,
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
