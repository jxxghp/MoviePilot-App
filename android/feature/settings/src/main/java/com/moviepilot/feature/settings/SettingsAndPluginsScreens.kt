package com.moviepilot.feature.settings

import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.Logout
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Extension
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Contrast
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.LightMode
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.RestartAlt
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveCornerStyle
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveMorphingPlayButton
import com.moviepilot.designsystem.ExpressiveNavBarStyle
import com.moviepilot.designsystem.ExpressivePalettes
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.ExpressiveWavySlider
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeAppearanceMode
import com.moviepilot.designsystem.NativeNetworkEntityLogo
import com.moviepilot.designsystem.NativeSegmentedControl
import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.designsystem.contrastingForeground
import com.moviepilot.pluginhost.IsolatedVuePluginWebView
import com.moviepilot.pluginhost.NativePluginDataPageView
import com.moviepilot.pluginhost.NativePluginFormRenderer
import com.moviepilot.pluginhost.VuePluginChromeController
import com.moviepilot.pluginhost.VuePluginSessionPayload
import com.moviepilot.pluginhost.VuePluginSurface
import com.moviepilot.rustbridge.DashboardStatsDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.PluginItemDto
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SessionState
import com.moviepilot.rustcore.PermissionsFfi
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Android Material 3 设置主中心：
 * 真实存储空间卡、三枚快捷统计磁贴、完整基础与个性设置入口、下拉刷新与顶部状态栏渐进模糊。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsHubScreen(
    repository: MoviePilotRepository,
    serverUrl: String,
    userName: String,
    onBack: (() -> Unit)? = null,
    onOpenSites: () -> Unit,
    onOpenUsers: () -> Unit,
    onOpenSubscribeSearch: () -> Unit,
    onOpenMediaSources: () -> Unit,
    onOpenDownloaders: () -> Unit,
    onOpenMediaServers: () -> Unit,
    onOpenDirectories: () -> Unit,
    onOpenPlayback: () -> Unit,
    onOpenNotifications: () -> Unit,
    onOpenAppearance: () -> Unit,
    onOpenPlugins: () -> Unit,
    onLogout: () -> Unit,
    onOpenChannelAuth: () -> Unit = {},
    permissions: PermissionsFfi? = null,
) {
    val colors = LocalMoviePilotColors.current
    val appearance = LocalAppearanceStore.current
    val context = LocalContext.current
    val playbackPrefs = remember(context) { PlaybackPreferencesStore(context) }
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val host = serverUrl.substringAfter("://").substringBefore("/")
    val rustVersion = remember { RustCoreBridge.version() }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val isAdmin = permissions?.admin != false

    var stats by remember { mutableStateOf(DashboardStatsDto()) }
    var activeSitesCount by remember { mutableIntStateOf(0) }
    var usersCount by remember { mutableIntStateOf(1) }
    var mediaServersCount by remember { mutableIntStateOf(0) }
    var notificationsCount by remember { mutableIntStateOf(0) }
    var authorizedCount by remember { mutableIntStateOf(0) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadAll() {
        stats = repository.fetchDashboardStats()
        if (isAdmin) {
            activeSitesCount = repository.fetchSites().count { it.isActive }
            usersCount = repository.fetchUsers().size.coerceAtLeast(1)
            mediaServersCount = repository.fetchMediaServers().count { it.enabled }
            notificationsCount = repository.fetchNotificationChannels().count { it.enabled }
            authorizedCount = repository.fetchChannelAuthorizations().size
        }
        isRefreshing = false
    }

    LaunchedEffect(isAdmin) { loadAll() }

    val usedRatio = if (stats.totalBytes > 0) (stats.usedBytes / stats.totalBytes).toFloat().coerceIn(0.02f, 1f) else 0f
    val freeBytes = (stats.totalBytes - stats.usedBytes).coerceAtLeast(0.0)

    ExpressiveTintedScaffold(
        title = "设置",
        subtitle = host.ifBlank { "MoviePilot 实例配置" },
        onBack = onBack,
    ) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { loadAll() }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            LazyColumn(
                state = listState,
                modifier = Modifier.widthIn(max = 860.dp).fillMaxSize(),
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 16.dp,
                    bottom = bottomOverlayInset + 28.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // 1. 顶部实例与真实存储进度条卡
                item {
                    CinematicPanel(padding = 16.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Box(Modifier.size(8.dp).clip(CircleShape).background(colors.success))
                                    Text(host.ifBlank { "MoviePilot" }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                                }
                                Text(
                                    text = if (stats.totalBytes > 0) "${fmtStorage(stats.usedBytes)} / ${fmtStorage(stats.totalBytes)}" else "-- / --",
                                    color = colors.textPrimary,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                            Box(modifier = Modifier.fillMaxWidth().height(7.dp).clip(CircleShape).background(colors.chipFill)) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth(usedRatio)
                                        .height(7.dp)
                                        .clip(CircleShape)
                                        .background(Brush.horizontalGradient(listOf(colors.accent, colors.pink))),
                                )
                            }
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text("• 已用 ${(usedRatio * 100).roundToInt()}%", color = colors.accent, fontSize = 12.sp)
                                Text("可用 ${fmtStorage(freeBytes)}", color = colors.textSecondary, fontSize = 12.sp)
                            }
                        }
                    }
                }

                // 2. 三枚并列快捷磁贴（站点管理 / 用户管理 / 渠道授权）
                if (isAdmin) {
                    item {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            QuickTile("站点管理", "$activeSitesCount 启用", Icons.Outlined.Language, colors.success, Modifier.weight(1f), onOpenSites)
                            QuickTile("用户管理", "$usersCount 位成员", Icons.Outlined.Group, colors.accent, Modifier.weight(1f), onOpenUsers)
                            QuickTile(
                                title = "渠道授权",
                                subtitle = if (authorizedCount > 0) "已绑 $authorizedCount" else "5分钟绑定码",
                                icon = Icons.Outlined.Key,
                                dotColor = colors.success,
                                modifier = Modifier.weight(1f),
                                onClick = onOpenChannelAuth,
                            )
                        }
                    }
                }

                // 3. 基础分组列表（非管理员仅展示本机播放偏好）
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("基础配置", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                        CinematicPanel(padding = 0.dp, showsShadow = false) {
                            Column {
                                if (isAdmin) {
                                    SettingsRow(Icons.Outlined.Search, "订阅与搜索", "站点范围 · 规则组", onOpenSubscribeSearch)
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                    SettingsRow(Icons.Outlined.Public, "媒体数据源", "搜索与元数据来源", onOpenMediaSources)
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                    SettingsRow(Icons.Outlined.Download, "下载器", "qBittorrent · Transmission · rTorrent", onOpenDownloaders)
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                    SettingsRow(Icons.Outlined.Dns, "媒体服务器", "$mediaServersCount 个", onOpenMediaServers)
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                    SettingsRow(Icons.Outlined.Folder, "整理与目录", "目录映射与刮削", onOpenDirectories)
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                }
                                SettingsRow(Icons.Outlined.PlayCircle, "播放偏好", playbackPrefs.summaryText, onOpenPlayback)
                            }
                        }
                        if (isAdmin) {
                            Text(
                                "底层代理、并发与高级系统参数请在 Web 管理台配置。",
                                color = colors.textMuted,
                                fontSize = 12.sp,
                                modifier = Modifier.padding(start = 6.dp, top = 2.dp),
                            )
                        }
                    }
                }

                // 4. 通知与个性化
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("通知与个性化", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                        CinematicPanel(padding = 0.dp, showsShadow = false) {
                            Column {
                                if (isAdmin) {
                                    SettingsRow(Icons.Outlined.Notifications, "通知渠道", "$notificationsCount 个已启用", onOpenNotifications)
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                } else {
                                    SettingsRow(Icons.Outlined.Key, "渠道授权", "生成 5 分钟机器人绑定码", onOpenChannelAuth)
                                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                }
                                SettingsRow(Icons.Outlined.Palette, "外观与主题", appearance.summaryText, onOpenAppearance)
                            }
                        }
                    }
                }

                // 5. 账号与版本信息
                item {
                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                        Column {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text("客户端版本", color = colors.textSecondary, fontSize = 14.sp)
                                NativeAdaptiveBadge("v$rustVersion", tint = colors.accent)
                            }
                            HorizontalDivider(color = colors.divider)
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable(onClick = onLogout)
                                    .padding(horizontal = 16.dp, vertical = 15.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Icon(Icons.AutoMirrored.Rounded.Logout, contentDescription = null, tint = colors.danger, modifier = Modifier.size(20.dp))
                                Text("退出登录（$userName）", color = colors.danger, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
            }
        }
    }
}

@Composable
private fun QuickTile(
    title: String,
    subtitle: String,
    icon: ImageVector,
    dotColor: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(padding = 14.dp, modifier = modifier.clickable(onClick = onClick)) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(22.dp))
            Text(title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(dotColor))
                Text(subtitle, color = colors.textSecondary, fontSize = 11.sp, maxLines = 1)
            }
        }
    }
}

@Composable
private fun SettingsRow(
    icon: ImageVector,
    title: String,
    value: String,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(38.dp)
                .clip(CircleShape)
                .background(androidx.compose.material3.MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.72f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = androidx.compose.material3.MaterialTheme.colorScheme.onSecondaryContainer,
                modifier = Modifier.size(20.dp),
            )
        }
        Spacer(Modifier.width(14.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                title,
                color = colors.textPrimary,
                style = androidx.compose.material3.MaterialTheme.typography.titleMedium.copy(fontSize = 15.sp),
            )
            if (value.isNotBlank()) {
                Text(
                    value,
                    color = colors.textSecondary,
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Spacer(Modifier.width(6.dp))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(20.dp))
    }
}

/**
 * Android Material 3 Expressive 主题与外观中心：
 * 交互式实时预览舞台（染色顶栏 + 胶囊页签 + 流动波浪进度条 + 形变主播放钮）、
 * 深浅/跟随系统与 AMOLED 纯黑模式、5 套表现力主题色板、Android 12+ Material You 壁纸动态取色、
 * 播放封面动态取色、界面圆角尺度与底部导航栏风格自定义。
 */
@Composable
fun AppearanceSettingsScreen(onBack: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    val store = LocalAppearanceStore.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val paletteCols = if (LocalConfiguration.current.screenWidthDp >= 680) 3 else 2
    var previewPlaying by remember { mutableStateOf(true) }
    var previewProgress by remember { mutableStateOf(0.58f) }

    ExpressiveTintedScaffold(
        title = "主题与外观",
        subtitle = store.summaryText,
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Refresh,
                contentDescription = "恢复默认外观",
                onClick = { store.resetToDefaults() },
            )
        },
    ) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyColumn(
            modifier = Modifier.widthIn(max = 860.dp).fillMaxSize(),
            contentPadding = PaddingValues(start = margin, end = margin, top = 16.dp, bottom = 56.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            // 1. 实时表现力预览舞台（可点击测试形变主钮与流动波浪进度条）
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("实时预览", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(colors.sheetRadiusDp.dp))
                            .background(colors.headerTint)
                            .border(0.8.dp, colors.divider, RoundedCornerShape(colors.sheetRadiusDp.dp)),
                    ) {
                        Column {
                            // 模拟染色顶栏 + 表现力胶囊页签
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 14.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        text = "MoviePilot",
                                        color = colors.headerTitle,
                                        fontSize = 20.sp,
                                        fontWeight = FontWeight.ExtraBold,
                                    )
                                    NativeAdaptiveBadge(
                                        text = if (store.dynamicColorEnabled) "Material You" else store.currentPreset.titleZh,
                                        tint = colors.accent,
                                        filled = true,
                                    )
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Box(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(colors.accent)
                                            .padding(horizontal = 14.dp, vertical = 6.dp),
                                    ) {
                                        Text("发现", color = colors.primaryButtonFg, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    }
                                    Box(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(if (colors.isDark) Color(0xFF0A1220).copy(alpha = 0.72f) else Color.White.copy(alpha = 0.75f))
                                            .padding(horizontal = 14.dp, vertical = 6.dp),
                                    ) {
                                        Text("媒体库", color = colors.headerTitle, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                    Box(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(if (colors.isDark) Color(0xFF0A1220).copy(alpha = 0.72f) else Color.White.copy(alpha = 0.75f))
                                            .padding(horizontal = 14.dp, vertical = 6.dp),
                                    ) {
                                        Text("订阅", color = colors.headerTitle, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                }
                            }

                            // 模拟 28dp 圆角正文区 + 丝绒播控条预览
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(topStart = colors.sheetRadiusDp.dp, topEnd = colors.sheetRadiusDp.dp))
                                    .background(colors.sheetSurface)
                                    .padding(14.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(colors.cardRadiusDp.dp))
                                        .background(colors.playerTint)
                                        .padding(horizontal = 14.dp, vertical = 12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(
                                            text = "正在播放 · 交互预览",
                                            color = Color.White,
                                            fontSize = 13.sp,
                                            fontWeight = FontWeight.Bold,
                                        )
                                        ExpressiveWavySlider(
                                            value = previewProgress,
                                            onValueChange = { previewProgress = it },
                                            onValueChangeFinished = {},
                                            isPlaying = previewPlaying,
                                            activeColor = colors.playerAccent,
                                            inactiveColor = Color.White.copy(alpha = 0.28f),
                                            modifier = Modifier.height(22.dp),
                                        )
                                    }
                                    ExpressiveMorphingPlayButton(
                                        isPlaying = previewPlaying,
                                        onClick = { previewPlaying = !previewPlaying },
                                        containerColor = colors.playerAccent,
                                        contentColor = colors.playerOnAccent,
                                        width = 50.dp,
                                        height = 46.dp,
                                        iconSize = 24.dp,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // 2. 外观模式 + AMOLED 纯黑开关
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("显示模式", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    val modes = listOf(
                        Triple(NativeAppearanceMode.Dark, "深色", Icons.Rounded.DarkMode),
                        Triple(NativeAppearanceMode.Light, "浅色", Icons.Rounded.LightMode),
                        Triple(NativeAppearanceMode.System, "跟随系统", Icons.Rounded.Contrast),
                    )
                    val selectedIdx = modes.indexOfFirst { it.first == store.mode }.coerceAtLeast(0)
                    NativeSegmentedControl(
                        options = modes.map { it.second },
                        selectedIndex = selectedIdx,
                        onSelect = { idx -> store.updateMode(modes[idx].first) },
                        icons = modes.map { it.third },
                    )
                    if (colors.isDark) {
                        CinematicPanel(padding = 16.dp) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text("AMOLED 纯黑模式", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    Text("深色画布切换纯黑 #000000，极致对比与省电", color = colors.textMuted, fontSize = 12.sp)
                                }
                                Switch(
                                    checked = store.pureBlackDark,
                                    onCheckedChange = { store.updatePureBlackDark(it) },
                                    colors = SwitchDefaults.colors(
                                        checkedTrackColor = colors.accent,
                                        checkedThumbColor = colors.primaryButtonFg,
                                    ),
                                )
                            }
                        }
                    }
                }
            }

            // 3. 精选 Material 3 Expressive 主题色板（5 套高辨识度双色调色板，宽屏 3 列自适应）
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("表现力主题色板", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    ExpressivePalettes.all.chunked(paletteCols).forEach { row ->
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            row.forEach { preset ->
                                val selected = !store.dynamicColorEnabled && store.paletteId == preset.id
                                val tone = if (colors.isDark) preset.dark else preset.light
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(colors.cardRadiusDp.dp))
                                        .background(if (selected) colors.activeIndicator else colors.surfaceContainerLow)
                                        .border(
                                            width = if (selected) 1.8.dp else 0.7.dp,
                                            color = if (selected) colors.accent else colors.divider,
                                            shape = RoundedCornerShape(colors.cardRadiusDp.dp),
                                        )
                                        .clickable {
                                            store.updateDynamicColorEnabled(false)
                                            store.updatePalette(preset.id)
                                        }
                                        .padding(14.dp),
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    ) {
                                        // 四分色环徽章：染色顶栏 + 主色 + 播控丝绒 + 画布
                                        Box(modifier = Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                                            Canvas(modifier = Modifier.fillMaxSize()) {
                                                drawArc(tone.headerTint, 180f, 180f, true)
                                                drawArc(tone.primary, 0f, 110f, true)
                                                drawArc(tone.playerTint, 110f, 70f, true)
                                            }
                                            if (selected) {
                                                Box(
                                                    modifier = Modifier
                                                        .size(20.dp)
                                                        .clip(CircleShape)
                                                        .background(tone.primary),
                                                    contentAlignment = Alignment.Center,
                                                ) {
                                                    Icon(
                                                        Icons.Rounded.Check,
                                                        contentDescription = null,
                                                        tint = tone.primary.contrastingForeground(),
                                                        modifier = Modifier.size(13.dp),
                                                    )
                                                }
                                            }
                                        }
                                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                            Text(
                                                text = preset.titleZh,
                                                color = colors.textPrimary,
                                                fontSize = 14.sp,
                                                fontWeight = FontWeight.Bold,
                                                maxLines = 1,
                                            )
                                            Text(
                                                text = preset.subtitleZh,
                                                color = colors.textSecondary,
                                                fontSize = 11.sp,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                        }
                                    }
                                }
                            }
                            repeat(paletteCols - row.size) {
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }

            // 4. 动态取色开关组（Material You 壁纸 + 播放封面自动着色）
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("动态配色引擎", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    CinematicPanel(padding = 0.dp) {
                        Column {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 16.dp, vertical = 14.dp),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Text("Material You 壁纸取色", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                            NativeAdaptiveBadge("Android 12+", tint = colors.accent)
                                        }
                                        Text("跟随系统壁纸自动生成表现力主题色", color = colors.textMuted, fontSize = 12.sp)
                                    }
                                    Switch(
                                        checked = store.dynamicColorEnabled,
                                        onCheckedChange = { store.updateDynamicColorEnabled(it) },
                                        colors = SwitchDefaults.colors(
                                            checkedTrackColor = colors.accent,
                                            checkedThumbColor = colors.primaryButtonFg,
                                        ),
                                    )
                                }
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                            }
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 14.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text("播放封面动态取色", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    Text("全屏播放与迷你条随封面自动着色", color = colors.textMuted, fontSize = 12.sp)
                                }
                                Switch(
                                    checked = store.albumArtDynamicColor,
                                    onCheckedChange = { store.updateAlbumArtDynamicColor(it) },
                                    colors = SwitchDefaults.colors(
                                        checkedTrackColor = colors.accent,
                                        checkedThumbColor = colors.primaryButtonFg,
                                    ),
                                )
                            }
                        }
                    }
                }
            }

            // 5. 界面形状与导航栏样式自定义
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("形状与导航布局", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                    CinematicPanel(padding = 16.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("卡片圆角尺度", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                val cornerOptions = ExpressiveCornerStyle.entries
                                NativeSegmentedControl(
                                    options = cornerOptions.map { it.title },
                                    selectedIndex = cornerOptions.indexOf(store.cornerStyle).coerceAtLeast(0),
                                    onSelect = { idx -> store.updateCornerStyle(cornerOptions[idx]) },
                                )
                            }
                            HorizontalDivider(color = colors.divider)
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("底部导航栏形态", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                val navOptions = ExpressiveNavBarStyle.entries
                                NativeSegmentedControl(
                                    options = navOptions.map { it.title },
                                    selectedIndex = navOptions.indexOf(store.navBarStyle).coerceAtLeast(0),
                                    onSelect = { idx -> store.updateNavBarStyle(navOptions[idx]) },
                                )
                            }
                            HorizontalDivider(color = colors.divider)
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text("悬浮智能助手按钮", color = colors.textPrimary, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold)
                                    Text("在一级主页面右下角显示可拖拽 AI 助手悬浮球", color = colors.textMuted, fontSize = 12.sp)
                                }
                                Switch(
                                    checked = store.showAgentMascot,
                                    onCheckedChange = { store.updateShowAgentMascot(it) },
                                    colors = SwitchDefaults.colors(
                                        checkedTrackColor = colors.accent,
                                        checkedThumbColor = colors.primaryButtonFg,
                                    ),
                                )
                            }
                        }
                    }
                }
            }
            }
        }
    }
}

/**
 * Android 原生插件中心：
 * 支持 HorizontalPager 左右手势在「已安装 / 插件市场」之间丝滑切换、关键词搜索、下拉刷新，
 * 市场一键安装与在线更新（`GET /api/v1/plugin/install/{id}`），
 * 图标回退统一使用官方 `logo_plugin`，点击任意插件进入 `PluginDetailScreen`。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun PluginsCenterScreen(
    repository: MoviePilotRepository,
    initialInstalledOnly: Boolean = true,
    onBack: () -> Unit,
    onOpenPluginDetail: (PluginItemDto) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    val pagerState = rememberPagerState(initialPage = if (initialInstalledOnly) 0 else 1, pageCount = { 2 })

    var installedPlugins by remember { mutableStateOf<List<PluginItemDto>>(emptyList()) }
    var marketPlugins by remember { mutableStateOf<List<PluginItemDto>>(emptyList()) }
    var isRefreshing by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    val installingIds = remember { mutableStateMapOf<String, Boolean>() }

    suspend fun loadTab(installedOnly: Boolean) {
        if (installedOnly) {
            installedPlugins = repository.fetchPlugins(true)
        } else {
            marketPlugins = repository.fetchPlugins(false)
        }
        isRefreshing = false
    }

    suspend fun reloadBoth() {
        installedPlugins = repository.fetchPlugins(true)
        marketPlugins = repository.fetchPlugins(false)
        isRefreshing = false
    }

    LaunchedEffect(Unit) {
        reloadBoth()
    }

    ExpressiveTintedScaffold(
        title = "插件中心",
        onBack = onBack,
        headerExtra = {
            ExpressivePillTabRow(
                tabs = listOf("已安装 (${installedPlugins.size})", "插件市场 (${marketPlugins.size})"),
                selectedIndex = pagerState.currentPage,
                onSelect = { idx -> scope.launch { pagerState.animateScrollToPage(idx) } },
                onTintedHeader = true,
            )
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(14.dp))
            // 搜索栏
            CinematicPanel(padding = 12.dp, cornerRadius = 22.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                    Box(modifier = Modifier.weight(1f)) {
                        if (searchQuery.isEmpty()) Text("搜索插件名称、作者或标签", color = colors.textMuted, fontSize = 14.sp)
                        BasicTextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            singleLine = true,
                            textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp),
                            cursorBrush = SolidColor(colors.accent),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    if (searchQuery.isNotEmpty()) {
                        IconButton(onClick = { searchQuery = "" }, modifier = Modifier.size(22.dp)) {
                            Icon(Icons.Rounded.Close, contentDescription = "清除", tint = colors.textMuted, modifier = Modifier.size(16.dp))
                        }
                    }
                }
            }

            Spacer(Modifier.height(12.dp))

            HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { pageIdx ->
                val raw = if (pageIdx == 0) installedPlugins else marketPlugins
                val filtered = remember(raw, searchQuery) {
                    val q = searchQuery.trim().lowercase()
                    if (q.isEmpty()) raw else raw.filter { p ->
                        p.name.lowercase().contains(q) ||
                            p.desc.lowercase().contains(q) ||
                            p.author.lowercase().contains(q) ||
                            p.labels.any { it.lowercase().contains(q) }
                    }
                }
                PullToRefreshBox(
                    isRefreshing = isRefreshing,
                    onRefresh = {
                        isRefreshing = true
                        scope.launch { loadTab(pageIdx == 0) }
                    },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    LazyColumn(
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomOverlayInset + 28.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(filtered, key = { "${pageIdx}_${it.id}" }) { plugin ->
                            val isInstalling = installingIds[plugin.id] == true
                            CinematicPanel(
                                padding = 16.dp,
                                modifier = Modifier.clickable { onOpenPluginDetail(plugin) },
                            ) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                                Text(plugin.name, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                Text("v${plugin.version}", color = colors.textSecondary, fontSize = 12.sp)
                                                if (plugin.hasUpdate) {
                                                    NativeAdaptiveBadge("有更新", tint = colors.warning)
                                                }
                                            }
                                            if (plugin.desc.isNotBlank()) {
                                                Text(plugin.desc, color = colors.textSecondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                            }
                                            if (plugin.labels.isNotEmpty()) {
                                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                                    plugin.labels.take(4).forEach { lbl -> NativeAdaptiveBadge(lbl) }
                                                }
                                            }
                                        }
                                        NativeNetworkEntityLogo(
                                            imageUrl = plugin.icon,
                                            kind = "plugin",
                                            value = plugin.name,
                                            size = 48.dp,
                                            cornerRadius = 14.dp,
                                        )
                                    }
                                    HorizontalDivider(color = colors.divider)
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Icon(Icons.Rounded.AccountCircle, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                                            Text(plugin.author.ifBlank { "MoviePilot" }, color = colors.textSecondary, fontSize = 12.sp)
                                        }
                                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                            if (plugin.hasPage) {
                                                NativeAdaptiveBadge("数据页", tint = colors.info)
                                            }
                                            if (plugin.installed && !plugin.hasUpdate) {
                                                NativeAdaptiveBadge(
                                                    if (plugin.state) "已启用" else "未启用",
                                                    tint = if (plugin.state) colors.success else colors.textMuted,
                                                )
                                            } else {
                                                NativeAdaptivePill(
                                                    title = when {
                                                        isInstalling -> "处理中…"
                                                        plugin.hasUpdate -> "更新"
                                                        else -> "安装"
                                                    },
                                                    selected = true,
                                                    icon = if (plugin.hasUpdate) Icons.Rounded.Refresh else Icons.Rounded.Download,
                                                    onClick = {
                                                        if (!isInstalling) {
                                                            scope.launch {
                                                                installingIds[plugin.id] = true
                                                                val (ok, msg) = repository.installPlugin(
                                                                    pluginId = plugin.id,
                                                                    repoUrl = plugin.repoUrl,
                                                                    force = plugin.hasUpdate,
                                                                )
                                                                if (ok) reloadBoth()
                                                                installingIds.remove(plugin.id)
                                                                snackbar?.showSnackbar(msg)
                                                            }
                                                        }
                                                    },
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * 独立全屏插件详情与运行时宿主页面（完整对齐 JSON 表单 + 数据页 + Vue 模块联邦）：
 * - 彻底移除任何伪造默认表单回退，防止空表单误覆盖服务端真实插件配置；
 * - 支持未安装插件一键安装（`GET /api/v1/plugin/install/{id}`）、在线更新、重置插件（`GET /api/v1/plugin/reset/{id}`）与卸载插件（`DELETE /api/v1/plugin/{id}`）；
 * - 支持 `HorizontalPager` 在「数据页 / 参数配置」之间丝滑滑动与未保存修改离开拦截。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PluginDetailScreen(
    plugin: PluginItemDto,
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current

    val auth = repository.session.value as? SessionState.Authenticated
    val vueSession = remember(auth) {
        VuePluginSessionPayload(
            serverUrl = auth?.serverUrl ?: "http://127.0.0.1:3000",
            authToken = auth?.token.orEmpty(),
            userId = auth?.identity?.id ?: 1,
            userName = auth?.identity?.name ?: "admin",
            avatar = auth?.identity?.avatar.orEmpty(),
            isSuperuser = auth?.identity?.isSuperuser ?: true,
            originCookies = repository.exportOriginCookieEntries(),
        )
    }

    var isInstalled by remember(plugin.id) { mutableStateOf(plugin.installed) }
    var hasUpdate by remember(plugin.id) { mutableStateOf(plugin.hasUpdate) }
    var isInstallingOrMutating by remember(plugin.id) { mutableStateOf(false) }

    val hasDataPage = plugin.hasPage
    val pageCount = if (hasDataPage) 2 else 1
    val pagerState = rememberPagerState(initialPage = 0, pageCount = { pageCount })

    var pageJson by remember(plugin.id) { mutableStateOf<String?>(null) }
    var formJson by remember(plugin.id) { mutableStateOf<String?>(null) }
    var isLoading by remember(plugin.id) { mutableStateOf(plugin.installed) }
    var forceVueWebMode by remember(plugin.id) { mutableStateOf(false) }
    var showOverflowMenu by remember { mutableStateOf(false) }
    var hasUnsavedChanges by remember { mutableStateOf(false) }
    var showDiscardDialog by remember { mutableStateOf(false) }
    var showResetConfirm by remember { mutableStateOf(false) }
    var showUninstallConfirm by remember { mutableStateOf(false) }
    val vueChrome = remember(plugin.id) { VuePluginChromeController(plugin.name) }

    suspend fun loadPluginResources() {
        if (!isInstalled) {
            isLoading = false
            return
        }
        isLoading = true
        if (hasDataPage) {
            pageJson = repository.fetchPluginPageJson(plugin.id)
        }
        formJson = repository.fetchPluginFormJson(plugin.id)
        isLoading = false
    }

    LaunchedEffect(plugin.id, isInstalled) { loadPluginResources() }

    LaunchedEffect(vueChrome.shouldDismiss) {
        if (vueChrome.shouldDismiss) {
            onBack()
        }
    }

    val detectedVuePlugin = remember(plugin.renderMode, pageJson, formJson) {
        fun declaresVue(raw: String?): Boolean {
            if (raw.isNullOrBlank()) return false
            val compact = raw.replace(" ", "")
            return compact.contains("\"render_mode\":\"vue\"", ignoreCase = true)
        }
        plugin.renderMode.equals("vue", ignoreCase = true) ||
            declaresVue(pageJson) ||
            declaresVue(formJson)
    }
    val openInVueWebView = isInstalled && (forceVueWebMode || detectedVuePlugin)

    val attemptLeave: () -> Unit = {
        when {
            openInVueWebView && vueChrome.requestClose() -> Unit
            hasUnsavedChanges -> showDiscardDialog = true
            else -> onBack()
        }
    }

    BackHandler(enabled = hasUnsavedChanges || openInVueWebView) {
        attemptLeave()
    }

    val currentIsConfigTab = !hasDataPage || pagerState.currentPage == 1
    val resolvedTopTitle = if (openInVueWebView && vueChrome.title.isNotBlank()) {
        vueChrome.title
    } else {
        plugin.name
    }

    ExpressiveTintedScaffold(
        title = resolvedTopTitle,
        onBack = attemptLeave,
        actions = {
            if (isInstalled) {
                Box {
                    ExpressiveHeaderActionButton(
                        icon = Icons.Rounded.MoreVert,
                        contentDescription = "插件菜单",
                        onClick = { showOverflowMenu = true },
                    )
                    DropdownMenu(
                        expanded = showOverflowMenu,
                        onDismissRequest = { showOverflowMenu = false },
                    ) {
                        if (openInVueWebView && vueChrome.actions.isNotEmpty()) {
                            vueChrome.actions.forEach { act ->
                                DropdownMenuItem(
                                    text = { Text(act.title) },
                                    enabled = act.enabled,
                                    leadingIcon = {
                                        Icon(
                                            when {
                                                act.icon?.contains("cog") == true || act.icon?.contains("tune") == true -> Icons.Rounded.Tune
                                                act.icon?.contains("refresh") == true || act.icon?.contains("sync") == true -> Icons.Rounded.Refresh
                                                else -> Icons.Rounded.Extension
                                            },
                                            contentDescription = null,
                                        )
                                    },
                                    onClick = {
                                        showOverflowMenu = false
                                        vueChrome.invokeAction(act.id)
                                    },
                                )
                            }
                        }
                        if (hasUpdate) {
                            DropdownMenuItem(
                                text = { Text("更新插件版本") },
                                leadingIcon = { Icon(Icons.Rounded.Download, contentDescription = null) },
                                onClick = {
                                    showOverflowMenu = false
                                    scope.launch {
                                        isInstallingOrMutating = true
                                        val (ok, msg) = repository.installPlugin(plugin.id, plugin.repoUrl, force = true)
                                        isInstallingOrMutating = false
                                        if (ok) {
                                            hasUpdate = false
                                            loadPluginResources()
                                        }
                                        snackbar?.showSnackbar(msg)
                                    }
                                },
                            )
                        }
                        if (!detectedVuePlugin) {
                            DropdownMenuItem(
                                text = { Text(if (forceVueWebMode) "标准视图查看" else "网页视图查看") },
                                leadingIcon = {
                                    Icon(
                                        if (forceVueWebMode) Icons.Rounded.Tune else Icons.Rounded.Language,
                                        contentDescription = null,
                                    )
                                },
                                onClick = {
                                    showOverflowMenu = false
                                    forceVueWebMode = !forceVueWebMode
                                },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text("刷新插件数据") },
                            leadingIcon = { Icon(Icons.Rounded.Refresh, contentDescription = null) },
                            onClick = {
                                showOverflowMenu = false
                                scope.launch { loadPluginResources() }
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("重置插件数据") },
                            leadingIcon = { Icon(Icons.Rounded.RestartAlt, contentDescription = null) },
                            onClick = {
                                showOverflowMenu = false
                                showResetConfirm = true
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("卸载此插件", color = colors.danger) },
                            leadingIcon = { Icon(Icons.Rounded.Delete, contentDescription = null, tint = colors.danger) },
                            onClick = {
                                showOverflowMenu = false
                                showUninstallConfirm = true
                            },
                        )
                    }
                }
            }
        },
        headerExtra = if (isInstalled && !isLoading && !openInVueWebView && hasDataPage) {
            {
                ExpressivePillTabRow(
                    tabs = listOf("数据页", "参数配置"),
                    selectedIndex = pagerState.currentPage,
                    onSelect = { idx -> scope.launch { pagerState.animateScrollToPage(idx) } },
                    scrollable = false,
                    onTintedHeader = true,
                )
            }
        } else {
            null
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            if (!isInstalled) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = margin, vertical = 24.dp),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    CinematicPanel(padding = 20.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                                NativeNetworkEntityLogo(
                                    imageUrl = plugin.icon,
                                    kind = "plugin",
                                    value = plugin.name,
                                    size = 56.dp,
                                    cornerRadius = 16.dp,
                                )
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(plugin.name, color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                                    Text(
                                        "v${plugin.version} · 作者 ${plugin.author.ifBlank { "MoviePilot" }}",
                                        color = colors.textSecondary,
                                        fontSize = 12.5.sp,
                                    )
                                }
                            }
                            if (plugin.desc.isNotBlank()) {
                                Text(plugin.desc, color = colors.textSecondary, fontSize = 13.5.sp)
                            }
                            if (plugin.labels.isNotEmpty()) {
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    plugin.labels.forEach { lbl -> NativeAdaptiveBadge(lbl) }
                                }
                            }
                            Button(
                                enabled = !isInstallingOrMutating,
                                onClick = {
                                    scope.launch {
                                        isInstallingOrMutating = true
                                        val (ok, msg) = repository.installPlugin(plugin.id, plugin.repoUrl, force = false)
                                        isInstallingOrMutating = false
                                        snackbar?.showSnackbar(msg)
                                        if (ok) {
                                            isInstalled = true
                                        }
                                    }
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = colors.accent,
                                    contentColor = colors.primaryButtonFg,
                                ),
                                shape = CircleShape,
                                modifier = Modifier.fillMaxWidth().height(48.dp),
                            ) {
                                if (isInstallingOrMutating) {
                                    CircularProgressIndicator(
                                        color = colors.primaryButtonFg,
                                        strokeWidth = 2.dp,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Spacer(Modifier.width(8.dp))
                                }
                                Text(if (isInstallingOrMutating) "正在安装插件…" else "立即安装插件", fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            } else if (isLoading && !forceVueWebMode && !plugin.renderMode.equals("vue", ignoreCase = true)) {
                Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.accent)
                }
            } else if (openInVueWebView) {
                IsolatedVuePluginWebView(
                    pluginId = plugin.id,
                    session = vueSession,
                    surface = if (currentIsConfigTab) VuePluginSurface.Config else VuePluginSurface.DataPage,
                    chromeController = vueChrome,
                    pluginHasPage = hasDataPage,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                )
            } else {
                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.weight(1f),
                ) { idx ->
                    val isPageTab = hasDataPage && idx == 0
                    if (isPageTab) {
                        val raw = pageJson
                        if (raw.isNullOrBlank()) {
                            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Text("该插件暂未返回数据页内容", color = colors.textSecondary, fontSize = 14.sp)
                            }
                        } else if (raw.contains("\"render_mode\":\"vue\"") || raw.contains("\"render_mode\": \"vue\"")) {
                            IsolatedVuePluginWebView(
                                pluginId = plugin.id,
                                session = vueSession,
                                surface = VuePluginSurface.DataPage,
                                modifier = Modifier.fillMaxSize(),
                            )
                        } else {
                            NativePluginDataPageView(
                                rawPageJson = raw,
                                resolveImageUrl = { repository.resolveImageUrl(it) },
                                onTriggerAction = { api, method, params ->
                                    val res = repository.triggerPluginAction(api, method, params)
                                    scope.launch { snackbar?.showSnackbar(res.second) }
                                    res
                                },
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    } else {
                        val realFormJson = formJson
                        if (realFormJson.isNullOrBlank()) {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(horizontal = margin),
                                contentAlignment = Alignment.Center,
                            ) {
                                CinematicPanel(padding = 20.dp) {
                                    Column(
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(10.dp),
                                        modifier = Modifier.fillMaxWidth(),
                                    ) {
                                        Text("暂未获取到插件配置表单", color = colors.textPrimary, fontSize = 15.5.sp, fontWeight = FontWeight.Bold)
                                        Text(
                                            "为防止空数据覆盖服务端真实配置，系统不会生成虚拟表单。您可点击刷新重试或切换网页视图查看。",
                                            color = colors.textSecondary,
                                            fontSize = 12.5.sp,
                                        )
                                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                            NativeAdaptivePill(
                                                title = "重新加载",
                                                selected = true,
                                                icon = Icons.Rounded.Refresh,
                                                onClick = { scope.launch { loadPluginResources() } },
                                            )
                                            NativeAdaptivePill(
                                                title = "网页视图查看",
                                                selected = false,
                                                icon = Icons.Rounded.Language,
                                                onClick = { forceVueWebMode = true },
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            NativePluginFormRenderer(
                                pluginId = plugin.id,
                                pluginName = plugin.name,
                                documentJson = realFormJson,
                                vueSession = vueSession,
                                onSaveFullModel = { fullModel ->
                                    scope.launch {
                                        val ok = repository.savePluginFormModel(plugin.id, fullModel)
                                        hasUnsavedChanges = false
                                        snackbar?.showSnackbar(
                                            if (ok) "已保存「${plugin.name}」插件配置"
                                            else "保存「${plugin.name}」配置失败，请稍后重试",
                                        )
                                    }
                                },
                                onTriggerAction = { api, method, params ->
                                    val res = repository.triggerPluginAction(api, method, params)
                                    scope.launch { snackbar?.showSnackbar(res.second) }
                                    res
                                },
                                onDirtyChanged = { hasUnsavedChanges = it },
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }
                }
            }
        }
    }

    if (showResetConfirm) {
        AlertDialog(
            onDismissRequest = { showResetConfirm = false },
            title = { Text("确认重置插件数据？") },
            text = { Text("确定要重置「${plugin.name}」的配置与缓存数据吗？此操作不可撤销。") },
            dismissButton = {
                TextButton(onClick = { showResetConfirm = false }) { Text("取消") }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showResetConfirm = false
                        scope.launch {
                            isInstallingOrMutating = true
                            val (ok, msg) = repository.resetPlugin(plugin.id)
                            isInstallingOrMutating = false
                            if (ok) {
                                hasUnsavedChanges = false
                                loadPluginResources()
                            }
                            snackbar?.showSnackbar(msg)
                        }
                    },
                ) {
                    Text("确认重置", color = colors.warning)
                }
            },
        )
    }

    if (showUninstallConfirm) {
        AlertDialog(
            onDismissRequest = { showUninstallConfirm = false },
            title = { Text("确认卸载插件？") },
            text = { Text("卸载后将从 MoviePilot 实例移除「${plugin.name}」。") },
            dismissButton = {
                TextButton(onClick = { showUninstallConfirm = false }) { Text("取消") }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showUninstallConfirm = false
                        scope.launch {
                            isInstallingOrMutating = true
                            val (ok, msg) = repository.uninstallPlugin(plugin.id)
                            isInstallingOrMutating = false
                            snackbar?.showSnackbar(msg)
                            if (ok) {
                                hasUnsavedChanges = false
                                onBack()
                            }
                        }
                    },
                ) {
                    Text("卸载", color = colors.danger)
                }
            },
        )
    }

    // Vue 联邦插件系统确认框原生接管（Material 3 AlertDialog）
    vueChrome.confirmation?.let { confirm ->
        AlertDialog(
            onDismissRequest = { vueChrome.respondConfirmation(false) },
            title = { Text(confirm.title) },
            text = { Text(confirm.message) },
            dismissButton = {
                TextButton(
                    onClick = { vueChrome.respondConfirmation(false) },
                    enabled = confirm.cancelEnabled,
                ) {
                    Text(confirm.cancelText)
                }
            },
            confirmButton = {
                TextButton(
                    onClick = { vueChrome.respondConfirmation(true) },
                    enabled = confirm.confirmEnabled,
                ) {
                    Text(
                        confirm.confirmText,
                        color = if (confirm.destructive) colors.danger else colors.accent,
                    )
                }
            },
        )
    }

    // Android Material 3 标准未保存离开确认对话框（左对齐内容 + 右下角 取消 / 放弃）
    if (showDiscardDialog) {
        AlertDialog(
            onDismissRequest = { showDiscardDialog = false },
            title = { Text("放弃未保存的配置？") },
            text = { Text("您对「${plugin.name}」所做的参数修改尚未保存，离开页面将丢失这些更改。") },
            dismissButton = {
                TextButton(onClick = { showDiscardDialog = false }) {
                    Text("继续编辑")
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    showDiscardDialog = false
                    hasUnsavedChanges = false
                    onBack()
                }) {
                    Text("放弃修改", color = colors.danger)
                }
            },
        )
    }
}

private fun fmtStorage(bytes: Double): String {
    val tb = bytes / (1024.0 * 1024.0 * 1024.0 * 1024.0)
    if (tb >= 1.0) return String.format("%.2f TB", tb)
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return String.format("%.1f GB", gb)
}
