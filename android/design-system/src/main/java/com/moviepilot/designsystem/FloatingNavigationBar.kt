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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.rounded.Bookmark
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Android Material 3 Expressive 顶级 4+1 对等导航目标：
 * 发现 · 订阅 · 我的 · 更多 + 右侧分离「搜索」圆钮（1:1 对齐 iOS 与鸿蒙导航架构）。
 */
enum class MainTab(val id: String, val label: String) {
    Discover("discover", "发现"),
    Subscribe("subscribe", "订阅"),
    Dashboard("dashboard", "我的"),
    Workspace("workspace", "更多"),
}

/** 品牌特色带闪星镂空的圆角电视屏图标，用于「发现」主导航（离屏图层镂空，适配激活胶囊与半透磨砂玻璃）。 */
@Composable
private fun DiscoverTvSparkleIcon(
    tint: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(
        modifier = modifier.graphicsLayer {
            compositingStrategy = CompositingStrategy.Offscreen
        },
    ) {
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
            drawPath(p, color = Color.Black, blendMode = BlendMode.DstOut)
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
    compact: Boolean = false,
) {
    val colors = LocalMoviePilotColors.current
    val baseSize = if (compact) 20.dp else 22.dp
    when (tab) {
        MainTab.Discover -> {
            DiscoverTvSparkleIcon(
                tint = tint,
                modifier = Modifier.size(if (compact) 20.dp else 22.dp),
            )
        }
        MainTab.Subscribe -> {
            Icon(
                imageVector = if (active) Icons.Rounded.Bookmark else Icons.Outlined.BookmarkBorder,
                contentDescription = tab.label,
                tint = tint,
                modifier = Modifier.size(baseSize),
            )
        }
        MainTab.Dashboard -> {
            val avatarSize = if (compact) 20.dp else 23.dp
            Box(
                modifier = Modifier
                    .size(avatarSize)
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
                    size = avatarSize,
                    cornerRadius = avatarSize / 2,
                )
            }
        }
        MainTab.Workspace -> {
            Icon(
                imageVector = if (active) Icons.Rounded.GridView else Icons.Outlined.GridView,
                contentDescription = tab.label,
                tint = tint,
                modifier = Modifier.size(baseSize),
            )
        }
    }
}

/**
 * Material 3 Expressive 底部 4+1 分离式悬浮磨砂玻璃胶囊导航栏：
 * - 左侧 `62.dp` 实时背板模糊圆胶囊承载「发现、订阅、我的、更多」4 大主入口；
 * - 右侧独立分离 `62.dp` 圆形实时磨砂玻璃「全局搜索」按钮，与 iOS / 鸿蒙形成统一视觉节奏；
 * - 兼容「外观与主题」中的 `FloatingPill`（标准通透悬浮）与 `RoundedDock`（高不透明度贴底 4+1 胶囊）模式。
 */
@Composable
fun MoviePilotBottomNavigationBar(
    selectedTab: MainTab,
    onTabClick: (MainTab) -> Unit,
    onSearchClick: () -> Unit = {},
    userAvatarUrl: String? = null,
    userInitial: String = "M",
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val scheme = MaterialTheme.colorScheme
    val haptic = LocalHapticFeedback.current
    val isFloating = colors.navBarStyle == ExpressiveNavBarStyle.FloatingPill
    val darkTintAlpha = if (isFloating) 0.74f else 0.88f
    val lightTintAlpha = if (isFloating) 0.88f else 0.95f
    val verticalPad = if (isFloating) 10.dp else 6.dp
    val activeFg = if (colors.isDark) scheme.primary else scheme.onSecondaryContainer
    val activePillTarget = scheme.secondaryContainer.copy(alpha = if (colors.isDark) 0.90f else 0.94f)
    val searchInteraction = remember { MutableInteractionSource() }
    val currentOnTabClick by rememberUpdatedState(onTabClick)
    val currentOnSearchClick by rememberUpdatedState(onSearchClick)

    Row(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 16.dp, vertical = verticalPad),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 左侧 4-Tab 悬浮磨砂玻璃主胶囊
        CinematicGlassSurface(
            shape = CircleShape,
            blurRadiusDp = 24.dp,
            darkTintAlpha = darkTintAlpha,
            lightTintAlpha = lightTintAlpha,
            modifier = Modifier
                .weight(1f)
                .height(62.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MainTab.entries.forEach { tab ->
                    val active = tab == selectedTab
                    val pillBg by animateColorAsState(
                        targetValue = if (active) activePillTarget else Color.Transparent,
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
                            .clip(CircleShape)
                            .background(pillBg, CircleShape)
                            .clickable(
                                interactionSource = interaction,
                                indication = ripple(bounded = true, color = scheme.primary),
                                role = Role.Tab,
                                onClick = {
                                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    currentOnTabClick(tab)
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

        // 右侧分离圆形磨砂玻璃「全局搜索」按钮
        CinematicGlassSurface(
            shape = CircleShape,
            blurRadiusDp = 24.dp,
            darkTintAlpha = darkTintAlpha,
            lightTintAlpha = lightTintAlpha,
            modifier = Modifier.size(62.dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(CircleShape)
                    .clickable(
                        interactionSource = searchInteraction,
                        indication = ripple(bounded = true, color = scheme.primary),
                        role = Role.Button,
                        onClick = {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            currentOnSearchClick()
                        },
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Search,
                    contentDescription = "全局搜索",
                    tint = scheme.onSurface,
                    modifier = Modifier.size(24.dp),
                )
            }
        }
    }
}

/**
 * Android Material 3 Expressive 宽屏 / 手机横屏 / 折叠屏展开 / 平板侧边导航栏（NavigationRail 规范）：
 * - 当窗口宽度 >= 600dp 时自动替换底部 NavigationBar，渲染 4 个一级主 Tab（发现、订阅、我的、更多）与独立分离圆形「搜索」按钮；
 * - 单一合并消费 `systemBars + displayCutout` 的 `Start + Vertical` 安全区，消除双重内边距叠加；
 * - 手机短屏横屏（`< 480dp`）自动压缩按钮与指示胶囊高度，确保全部入口完整同屏展示，并在分屏/大字号下平滑纵向滚动。
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
    val scheme = MaterialTheme.colorScheme
    val haptic = LocalHapticFeedback.current
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val activeFg = if (colors.isDark) scheme.primary else scheme.onSecondaryContainer
    val currentOnTabClick by rememberUpdatedState(onTabClick)
    val currentOnSearchClick by rememberUpdatedState(onSearchClick)

    Surface(
        color = scheme.surfaceContainerLow,
        modifier = modifier.fillMaxHeight(),
    ) {
        Row(modifier = Modifier.fillMaxHeight()) {
            Column(
                modifier = Modifier
                    .fillMaxHeight()
                    .windowInsetsPadding(
                        WindowInsets.systemBars
                            .union(WindowInsets.displayCutout)
                            .only(WindowInsetsSides.Vertical + WindowInsetsSides.Start),
                    )
                    .width(AdaptiveDeviceLayout.WideRailWidth)
                    .verticalScroll(rememberScrollState())
                    .padding(vertical = if (compactHeight) 6.dp else 14.dp, horizontal = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(if (compactHeight) 3.dp else 8.dp),
            ) {
                Surface(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        currentOnSearchClick()
                    },
                    shape = CircleShape,
                    color = scheme.primary,
                    contentColor = scheme.onPrimary,
                    shadowElevation = 2.dp,
                    modifier = Modifier.size(if (compactHeight) 42.dp else 52.dp),
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Icon(
                            Icons.Rounded.Search,
                            contentDescription = "全局搜索",
                            modifier = Modifier.size(if (compactHeight) 20.dp else 24.dp),
                        )
                    }
                }

                Spacer(Modifier.height(if (compactHeight) 4.dp else 10.dp))

                MainTab.entries.forEach { tab ->
                    val active = tab == selectedTab
                    val pillBg by animateColorAsState(
                        targetValue = if (active) scheme.secondaryContainer else Color.Transparent,
                        animationSpec = tween(200),
                        label = "railPillBg",
                    )
                    val contentColor by animateColorAsState(
                        targetValue = if (active) activeFg else colors.textSecondary,
                        animationSpec = tween(200),
                        label = "railPillFg",
                    )
                    val interaction = remember { MutableInteractionSource() }
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .clickable(
                                interactionSource = interaction,
                                indication = ripple(bounded = true, color = scheme.primary),
                                role = Role.Tab,
                                onClick = {
                                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    currentOnTabClick(tab)
                                },
                            )
                            .padding(vertical = if (compactHeight) 2.dp else 4.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(if (compactHeight) 1.dp else 3.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(
                                    width = if (compactHeight) 48.dp else 56.dp,
                                    height = if (compactHeight) 26.dp else 32.dp,
                                )
                                .clip(CircleShape)
                                .background(pillBg, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            MainTabIcon(
                                tab = tab,
                                active = active,
                                tint = contentColor,
                                userAvatarUrl = userAvatarUrl,
                                userInitial = userInitial,
                                compact = compactHeight,
                            )
                        }
                        Text(
                            text = tab.label,
                            color = contentColor,
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontSize = if (compactHeight) 10.sp else 11.sp,
                                lineHeight = if (compactHeight) 12.sp else 14.sp,
                                fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                            ),
                            maxLines = 1,
                            overflow = TextOverflow.Clip,
                        )
                    }
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .width(0.6.dp)
                    .background(scheme.outlineVariant.copy(alpha = if (colors.isDark) 0.36f else 0.55f)),
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
            onSearchClick = {},
        )
    }
}
