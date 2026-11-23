package com.moviepilot.designsystem

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.TravelExplore
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage

/** 四大主导航标签页枚举。 */
enum class MainTab(val id: String, val label: String) {
    Discover("discover", "发现"),
    Explore("explore", "探索"),
    Dashboard("dashboard", "我的"),
    Settings("settings", "设置"),
}

/** 重复点击底栏主图标弹出的 8 项快捷功能入口（严格对齐 iOS 黄金截图顺序与分组）。 */
enum class OverflowMenuDestination(
    val id: String,
    val title: String,
    val icon: ImageVector,
    val group: Int,
) {
    Subscriptions("subscriptions", "我的订阅", Icons.Outlined.BookmarkBorder, 0),
    Calendar("calendar", "订阅日历", Icons.Outlined.CalendarMonth, 0),
    Resources("resources", "站点资源", Icons.Outlined.TravelExplore, 0),
    Downloads("downloads", "下载", Icons.Outlined.Download, 0),
    Files("files", "文件管理", Icons.Outlined.Folder, 1),
    History("history", "整理历史", Icons.Outlined.History, 1),
    Workflows("workflows", "工作流", Icons.Outlined.AccountTree, 1),
    Plugins("plugins", "插件", Icons.Outlined.Extension, 1),
}

/**
 * 4+1 原生悬浮玻璃底部导航栏（像素级对齐 iOS Liquid Glass 布局）：
 * - 左侧悬浮胶囊容纳 4 主 Tab（发现 / 探索 / 我的头像 / 设置），选中态带弹性发光椭圆底托；
 * - 右侧分离式 `+1` 独立玻璃圆钮（默认全局搜索，子页可动态切换为主操作图标）；
 * - 重复点击当前主 Tab 弹出 8 项高透玻璃快捷菜单。
 */
@Composable
fun FloatingFourPlusOneNavBar(
    selectedTab: MainTab,
    onTabClick: (MainTab) -> Unit,
    plusOneIcon: ImageVector = Icons.Rounded.Search,
    plusOneContentDescription: String = "全局搜索",
    onPlusOneClick: () -> Unit,
    userAvatarUrl: String? = null,
    userInitial: String = "M",
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 18.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // 4 主 Tab 悬浮玻璃胶囊
        CinematicGlassSurface(
            shape = RoundedCornerShape(32.dp),
            modifier = Modifier
                .weight(1f)
                .height(64.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .fillMaxHeight()
                    .padding(horizontal = 6.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                MainTab.entries.forEach { tab ->
                    val active = tab == selectedTab
                    val pillPadding by animateDpAsState(
                        targetValue = if (active) 4.dp else 0.dp,
                        animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
                        label = "tabPill",
                    )
                    val tint = if (active) colors.accent else colors.textPrimary.copy(alpha = 0.85f)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clip(RoundedCornerShape(26.dp))
                            .background(
                                if (active) {
                                    if (colors.isDark) Color.White.copy(alpha = 0.14f)
                                    else colors.accent.copy(alpha = 0.14f)
                                } else {
                                    Color.Transparent
                                },
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                            ) { onTabClick(tab) }
                            .padding(horizontal = pillPadding),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            if (tab == MainTab.Dashboard) {
                                Box(
                                    modifier = Modifier
                                        .size(26.dp)
                                        .clip(CircleShape)
                                        .background(colors.accent.copy(alpha = 0.35f))
                                        .border(
                                            width = if (active) 1.5.dp else 0.8.dp,
                                            color = if (active) colors.accent else Color.White.copy(alpha = 0.4f),
                                            shape = CircleShape,
                                        ),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    if (!userAvatarUrl.isNullOrBlank()) {
                                        AsyncImage(
                                            model = userAvatarUrl,
                                            contentDescription = tab.label,
                                            contentScale = ContentScale.Crop,
                                            modifier = Modifier.size(26.dp).clip(CircleShape),
                                        )
                                    } else {
                                        Text(
                                            text = userInitial.take(1).uppercase(),
                                            color = Color.White,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold,
                                        )
                                    }
                                }
                            } else {
                                val icon = when (tab) {
                                    MainTab.Discover -> Icons.Rounded.AutoAwesome
                                    MainTab.Explore -> if (active) Icons.Rounded.Explore else Icons.Outlined.Explore
                                    MainTab.Settings -> if (active) Icons.Rounded.Settings else Icons.Outlined.Settings
                                    MainTab.Dashboard -> Icons.Outlined.Person
                                }
                                Icon(
                                    imageVector = icon,
                                    contentDescription = tab.label,
                                    tint = tint,
                                    modifier = Modifier.size(23.dp),
                                )
                            }
                            Spacer(Modifier.height(2.dp))
                            Text(
                                text = tab.label,
                                color = tint,
                                fontSize = 10.sp,
                                fontWeight = if (active) FontWeight.SemiBold else FontWeight.Medium,
                                maxLines = 1,
                                overflow = TextOverflow.Clip,
                            )
                        }
                    }
                }
            }
        }

        // 右侧分离式 +1 独立玻璃圆钮
        CinematicGlassSurface(
            shape = CircleShape,
            modifier = Modifier
                .size(62.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onPlusOneClick,
                ),
        ) {
            Box(
                modifier = Modifier.size(62.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = plusOneIcon,
                    contentDescription = plusOneContentDescription,
                    tint = colors.textPrimary,
                    modifier = Modifier.size(25.dp),
                )
            }
        }
    }
}

/**
 * 重复点击底栏主图标弹出的 8 项玻璃快捷菜单（像素级复刻 `native-v2-live-overflow-menu.jpg`）：
 * 顶部用户头像 + 角色绿点，两段各 4 项清晰分组，弹簧展开动画。
 */
@Composable
fun FloatingOverflowMenuPopover(
    visible: Boolean,
    userName: String,
    isSuperuser: Boolean,
    userAvatarUrl: String?,
    onSelect: (OverflowMenuDestination) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn() + scaleIn(
            initialScale = 0.86f,
            transformOrigin = TransformOrigin(0.25f, 1f),
            animationSpec = spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMedium),
        ),
        exit = fadeOut() + scaleOut(
            targetScale = 0.90f,
            transformOrigin = TransformOrigin(0.25f, 1f),
        ),
        modifier = modifier,
    ) {
        CinematicGlassSurface(
            shape = RoundedCornerShape(GeneratedDesignTokens.PANEL_CORNER_RADIUS_DP.dp),
            blurRadiusPx = 34f,
            darkScrimAlpha = 0.93f,
            lightScrimAlpha = 0.96f,
            modifier = Modifier.width(236.dp),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 14.dp),
            ) {
                // 头部用户信息
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(colors.accent.copy(alpha = 0.35f))
                            .border(1.dp, Color.White.copy(alpha = 0.35f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (!userAvatarUrl.isNullOrBlank()) {
                            AsyncImage(
                                model = userAvatarUrl,
                                contentDescription = userName,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.size(40.dp).clip(CircleShape),
                            )
                        } else {
                            Text(
                                text = userName.take(1).uppercase().ifBlank { "A" },
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 16.sp,
                            )
                        }
                    }
                    Column {
                        Text(
                            text = userName.ifBlank { "admin" },
                            color = colors.textPrimary,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(7.dp)
                                    .clip(CircleShape)
                                    .background(colors.success),
                            )
                            Text(
                                text = if (isSuperuser) "超级管理员" else "普通成员",
                                color = colors.textSecondary,
                                fontSize = 12.sp,
                            )
                        }
                    }
                }

                HorizontalDivider(
                    color = colors.divider,
                    modifier = Modifier.padding(vertical = 10.dp),
                )

                // 上半组 4 项：订阅 / 日历 / 站点资源 / 下载
                OverflowMenuDestination.entries.filter { it.group == 0 }.forEach { dest ->
                    OverflowMenuRow(dest = dest, onClick = {
                        onDismiss()
                        onSelect(dest)
                    })
                }

                HorizontalDivider(
                    color = colors.divider,
                    modifier = Modifier.padding(vertical = 8.dp),
                )

                // 下半组 4 项：文件管理 / 整理历史 / 工作流 / 插件
                OverflowMenuDestination.entries.filter { it.group == 1 }.forEach { dest ->
                    OverflowMenuRow(dest = dest, onClick = {
                        onDismiss()
                        onSelect(dest)
                    })
                }
            }
        }
    }
}

@Composable
private fun OverflowMenuRow(
    dest: OverflowMenuDestination,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(
            imageVector = dest.icon,
            contentDescription = dest.title,
            tint = colors.textPrimary,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = dest.title,
            color = colors.textPrimary,
            fontSize = 15.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}
