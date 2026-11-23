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
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.LightMode
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.GeneratedDesignTokens
import com.moviepilot.designsystem.LocalAppearanceStore
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAppearanceMode
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativePrimaryTabBar
import com.moviepilot.designsystem.NativeSecondaryTabBar
import com.moviepilot.designsystem.NativeSegmentedControl
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
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
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
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
) {
    val colors = LocalMoviePilotColors.current
    val appearance = LocalAppearanceStore.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val host = serverUrl.substringAfter("://").substringBefore("/")
    val rustVersion = remember { RustCoreBridge.version() }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val localHaze = remember { HazeState() }

    var stats by remember { mutableStateOf(DashboardStatsDto()) }
    var activeSitesCount by remember { mutableIntStateOf(0) }
    var usersCount by remember { mutableIntStateOf(1) }
    var mediaServersCount by remember { mutableIntStateOf(0) }
    var notificationsCount by remember { mutableIntStateOf(0) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadAll() {
        stats = repository.fetchDashboardStats()
        activeSitesCount = repository.fetchSites().count { it.isActive }
        usersCount = repository.fetchUsers().size.coerceAtLeast(1)
        mediaServersCount = repository.fetchMediaServers().count { it.enabled }
        notificationsCount = repository.fetchNotificationChannels().count { it.enabled }
        isRefreshing = false
    }

    LaunchedEffect(Unit) { loadAll() }

    val usedRatio = if (stats.totalBytes > 0) (stats.usedBytes / stats.totalBytes).toFloat().coerceIn(0.02f, 1f) else 0f
    val freeBytes = (stats.totalBytes - stats.usedBytes).coerceAtLeast(0.0)
    val topBlurAlpha by remember {
        derivedStateOf {
            if (listState.firstVisibleItemIndex > 0) 1f
            else (listState.firstVisibleItemScrollOffset / 110f).coerceIn(0f, 1f)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { loadAll() }
            },
            modifier = Modifier
                .fillMaxSize()
                .hazeSource(localHaze),
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item { NativeGlassTopBar(title = "设置", onBack = onBack, showTopBlur = false) }

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
                item {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        QuickTile("站点管理", "$activeSitesCount 启用", Icons.Outlined.Language, colors.success, Modifier.weight(1f), onOpenSites)
                        QuickTile("用户管理", "$usersCount 位成员", Icons.Outlined.Group, colors.accent, Modifier.weight(1f), onOpenUsers)
                        QuickTile("渠道授权", "已授 $notificationsCount", Icons.Outlined.Key, colors.success, Modifier.weight(1f), onOpenNotifications)
                    }
                }

                // 3. 基础分组列表
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("基础配置", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                        CinematicPanel(padding = 0.dp, showsShadow = false) {
                            Column {
                                SettingsRow(Icons.Outlined.Search, "订阅与搜索", "站点范围 · 规则组", onOpenSubscribeSearch)
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                SettingsRow(Icons.Outlined.Public, "媒体数据源", "搜索与元数据来源", onOpenMediaSources)
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                SettingsRow(Icons.Outlined.Download, "下载器", "qBittorrent · Transmission", onOpenDownloaders)
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                SettingsRow(Icons.Outlined.Dns, "媒体服务器", "$mediaServersCount 个", onOpenMediaServers)
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                SettingsRow(Icons.Outlined.Folder, "整理与目录", "目录映射与刮削", onOpenDirectories)
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                SettingsRow(Icons.Outlined.PlayCircle, "播放偏好", "自适应 · 1.0x", onOpenPlayback)
                            }
                        }
                        Text(
                            "底层代理、并发与高级系统参数请在 Web 管理台配置。",
                            color = colors.textMuted,
                            fontSize = 12.sp,
                            modifier = Modifier.padding(start = 6.dp, top = 2.dp),
                        )
                    }
                }

                // 4. 外观、通知与扩展生态
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("通知与个性化", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                        CinematicPanel(padding = 0.dp, showsShadow = false) {
                            Column {
                                SettingsRow(Icons.Outlined.Notifications, "通知渠道", "$notificationsCount 个已启用", onOpenNotifications)
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                SettingsRow(Icons.Outlined.Palette, "外观与主题", appearance.summaryText, onOpenAppearance)
                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 52.dp))
                                SettingsRow(Icons.Outlined.Extension, "插件中心", "市场 · 已安装 · 数据页", onOpenPlugins)
                            }
                        }
                    }
                }

                // 5. 账号与共享内核信息
                item {
                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                        Column {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text("Rust 共享内核", color = colors.textSecondary, fontSize = 14.sp)
                                NativeAdaptiveBadge("v$rustVersion · UniFFI", tint = colors.accent)
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

        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = topBlurAlpha,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )
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
 * Android Material 3 主题与外观页：
 * 支持实时预览卡、Android 12+ Material You 壁纸动态取色开关、深浅/跟随系统模式、
 * 6 套渐变色板、强调色与 AGSL 动态流光。
 */
@Composable
fun AppearanceSettingsScreen(onBack: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    val store = LocalAppearanceStore.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val localHaze = remember { HazeState() }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            NativeGlassTopBar(title = "主题与外观", onBack = onBack)
            LazyColumn(
                modifier = Modifier
                    .weight(1f)
                    .hazeSource(localHaze),
                contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 52.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                // 1. 实时预览卡
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("实时预览", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                        CinematicPanel(padding = 14.dp) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(Brush.linearGradient(colors.palette))
                                    .border(0.8.dp, Color.White.copy(alpha = 0.2f), RoundedCornerShape(16.dp))
                                    .padding(14.dp),
                            ) {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Box(
                                            modifier = Modifier
                                                .size(38.dp)
                                                .clip(RoundedCornerShape(10.dp))
                                                .background(colors.accent),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Icon(Icons.Rounded.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                                        }
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text("MoviePilot Material 3 主题", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                                            Text(store.summaryText, color = colors.textSecondary, fontSize = 12.sp)
                                        }
                                        NativeAdaptiveBadge("活跃", tint = colors.accent, filled = true)
                                    }
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Box(Modifier.weight(0.75f).height(6.dp).clip(CircleShape).background(colors.accent))
                                        Box(Modifier.weight(0.25f).height(6.dp).clip(CircleShape).background(colors.chipFill))
                                    }
                                }
                            }
                        }
                    }
                }

                // 2. Android 12+ Material You 系统壁纸动态取色
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    item {
                        CinematicPanel(padding = 16.dp) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text("Material You 动态取色", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                        NativeAdaptiveBadge("Android 12+", tint = colors.accent)
                                    }
                                    Text("跟随系统壁纸自动提取 Material 3 主题色与表面色阶", color = colors.textMuted, fontSize = 12.sp)
                                }
                                Switch(
                                    checked = store.dynamicColorEnabled,
                                    onCheckedChange = { store.updateDynamicColorEnabled(it) },
                                    colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                                )
                            }
                        }
                    }
                }

                // 3. 外观主题（Material 3 SingleChoiceSegmentedButtonRow 连接式分段选择）
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("外观模式", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
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
                    }
                }

                // 4. 背景过渡颜色 2×3 渐变实景色板卡
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("背景色板预设", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                        val presets = GeneratedDesignTokens.backgroundPresets
                        presets.chunked(3).forEach { row ->
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                row.forEach { preset ->
                                    val selected = !store.dynamicColorEnabled && store.backgroundPresetId == preset.id
                                    val stops = if (colors.isDark) preset.darkStops else preset.lightStops
                                    Column(
                                        modifier = Modifier.weight(1f).clickable {
                                            store.updateDynamicColorEnabled(false)
                                            store.updateBackgroundPreset(preset.id)
                                        },
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .height(62.dp)
                                                .clip(RoundedCornerShape(14.dp))
                                                .background(Brush.linearGradient(stops))
                                                .border(
                                                    width = if (selected) 2.dp else 0.7.dp,
                                                    color = if (selected) colors.accent else Color.White.copy(alpha = 0.22f),
                                                    shape = RoundedCornerShape(14.dp),
                                                ),
                                        ) {
                                            if (selected) {
                                                Box(
                                                    modifier = Modifier
                                                        .align(Alignment.TopEnd)
                                                        .padding(6.dp)
                                                        .size(18.dp)
                                                        .clip(CircleShape)
                                                        .background(colors.accent),
                                                    contentAlignment = Alignment.Center,
                                                ) {
                                                    Icon(Icons.Rounded.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(12.dp))
                                                }
                                            }
                                        }
                                        Text(
                                            text = preset.titleZh,
                                            color = if (selected) colors.textPrimary else colors.textSecondary,
                                            fontSize = 12.sp,
                                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                // 5. 起始/中间/结束过渡色
                item {
                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                        Column {
                            RainbowColorRow("起始过渡色", colors.palette.getOrElse(0) { Color(0xFF30334A) })
                            HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                            RainbowColorRow("中间过渡色", colors.palette.getOrElse(1) { Color(0xFF4A3B57) })
                            HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                            RainbowColorRow("结束过渡色", colors.palette.lastOrNull() ?: Color(0xFF242E40))
                        }
                    }
                }

                // 6. 强调色圆点 + AGSL 流光开关
                item {
                    CinematicPanel(padding = 16.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text("主题强调色", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                GeneratedDesignTokens.accentPresets.filter { it.id != "custom" }.forEach { acc ->
                                    val active = !store.dynamicColorEnabled && store.accentPresetId == acc.id
                                    Box(
                                        modifier = Modifier
                                            .size(36.dp)
                                            .clip(CircleShape)
                                            .background(acc.color)
                                            .border(if (active) 3.dp else 1.dp, if (active) Color.White else Color.White.copy(alpha = 0.3f), CircleShape)
                                            .clickable {
                                                store.updateDynamicColorEnabled(false)
                                                store.updateAccentPreset(acc.id)
                                            },
                                    )
                                }
                            }
                            HorizontalDivider(color = colors.divider)
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("AGSL GPU 动态流光", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    Text("Android 13+ 原生着色器 15fps 呼吸流动", color = colors.textMuted, fontSize = 12.sp)
                                }
                                Switch(
                                    checked = store.animateBackground,
                                    onCheckedChange = { store.updateAnimateBackground(it) },
                                    colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RainbowColorRow(title: String, currentColor: Color) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
        Box(modifier = Modifier.size(30.dp), contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                drawCircle(
                    brush = Brush.sweepGradient(
                        listOf(Color(0xFFFF4D4D), Color(0xFFFFD166), Color(0xFF06D6A0), Color(0xFF118AB2), Color(0xFF9B5DE5), Color(0xFFFF4D4D)),
                    ),
                    style = Stroke(width = 3.dp.toPx()),
                )
            }
            Box(Modifier.size(20.dp).clip(CircleShape).background(currentColor))
        }
    }
}

/**
 * Android 原生插件中心：
 * 支持 HorizontalPager 左右手势在「已安装 / 插件市场」之间丝滑切换、关键词搜索、下拉刷新，
 * 点击任意插件推进至独立的 `PluginDetailScreen` 全屏呈现原生数据页 / JSON 配置 / Vue 模块联邦。
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
    val scope = rememberCoroutineScope()
    val pagerState = rememberPagerState(initialPage = if (initialInstalledOnly) 0 else 1, pageCount = { 2 })

    var installedPlugins by remember { mutableStateOf<List<PluginItemDto>>(emptyList()) }
    var marketPlugins by remember { mutableStateOf<List<PluginItemDto>>(emptyList()) }
    var isRefreshing by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }

    suspend fun loadTab(installedOnly: Boolean) {
        if (installedOnly) {
            installedPlugins = repository.fetchPlugins(true)
        } else {
            marketPlugins = repository.fetchPlugins(false)
        }
        isRefreshing = false
    }

    LaunchedEffect(Unit) {
        loadTab(true)
        loadTab(false)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = if (pagerState.currentPage == 0) "已安装插件 (${installedPlugins.size})" else "插件市场 (${marketPlugins.size})",
            onBack = onBack,
        )

        // 搜索栏
        CinematicPanel(padding = 12.dp, cornerRadius = 18.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
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

        Spacer(Modifier.height(10.dp))

        NativePrimaryTabBar(
            tabs = listOf("已安装 (${installedPlugins.size})", "插件市场 (${marketPlugins.size})"),
            selectedIndex = pagerState.currentPage,
            onSelect = { idx -> scope.launch { pagerState.animateScrollToPage(idx) } },
        )

        Spacer(Modifier.height(10.dp))

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
                    contentPadding = PaddingValues(start = margin, end = margin, bottom = 52.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(filtered, key = { "${pageIdx}_${it.id}" }) { plugin ->
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
                                    Box(
                                        modifier = Modifier
                                            .size(48.dp)
                                            .clip(CircleShape)
                                            .background(Brush.linearGradient(listOf(Color(0xFF29B6F6), Color(0xFF0288D1)))),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        if (!plugin.icon.isNullOrBlank()) {
                                            AsyncImage(
                                                model = plugin.icon,
                                                contentDescription = plugin.name,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize().clip(CircleShape),
                                            )
                                        } else {
                                            Icon(Icons.Rounded.Extension, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
                                        }
                                    }
                                }
                                HorizontalDivider(color = colors.divider)
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Icon(Icons.Rounded.AccountCircle, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                                        Text(plugin.author.ifBlank { "MoviePilot" }, color = colors.textSecondary, fontSize = 12.sp)
                                    }
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                        if (plugin.hasPage) {
                                            NativeAdaptiveBadge("数据页", tint = colors.info)
                                        }
                                        if (plugin.installed) {
                                            NativeAdaptiveBadge(if (plugin.state) "已启用" else "未启用", tint = if (plugin.state) colors.success else colors.textMuted)
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
 * - 支持 `HorizontalPager` 在「数据页 / 参数配置」之间丝滑滑动；
 * - 顶栏右侧 Android 标准 `⋮` 溢出菜单：支持一键切换「网页样式查看（Vue 模块联邦）」与手动刷新；
 * - 退出带有未保存修改的配置页时，拦截系统返回与 Up 按钮弹出 Material 3 `AlertDialog` 确认。
 */
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

    val hasDataPage = plugin.hasPage
    val pageCount = if (hasDataPage) 2 else 1
    val pagerState = rememberPagerState(initialPage = 0, pageCount = { pageCount })

    var pageJson by remember(plugin.id) { mutableStateOf<String?>(null) }
    var formJson by remember(plugin.id) { mutableStateOf<String?>(null) }
    var isLoading by remember(plugin.id) { mutableStateOf(true) }
    var forceVueWebMode by remember(plugin.id) { mutableStateOf(false) }
    var showOverflowMenu by remember { mutableStateOf(false) }
    var hasUnsavedChanges by remember { mutableStateOf(false) }
    var showDiscardDialog by remember { mutableStateOf(false) }
    val vueChrome = remember(plugin.id) { VuePluginChromeController(plugin.name) }

    suspend fun loadPluginResources() {
        isLoading = true
        if (hasDataPage) {
            pageJson = repository.fetchPluginPageJson(plugin.id)
        }
        formJson = repository.fetchPluginFormJson(plugin.id) ?: samplePluginFormJson(plugin.name)
        isLoading = false
    }

    LaunchedEffect(plugin.id) { loadPluginResources() }

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
    val openInVueWebView = forceVueWebMode || detectedVuePlugin

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

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = resolvedTopTitle,
            onBack = attemptLeave,
            trailing = {
                Box {
                    androidx.compose.material3.IconButton(
                        onClick = { showOverflowMenu = true },
                        modifier = Modifier.size(48.dp),
                    ) {
                        Icon(
                            Icons.Rounded.MoreVert,
                            contentDescription = "插件菜单",
                            tint = colors.textPrimary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    DropdownMenu(
                        expanded = showOverflowMenu,
                        onDismissRequest = { showOverflowMenu = false },
                    ) {
                        // Vue 模块联邦接管后的标题栏动作自动投影至原生顶栏菜单（1:1 对齐 iOS）
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
                        if (!detectedVuePlugin) {
                            DropdownMenuItem(
                                text = { Text(if (forceVueWebMode) "切换回原生渲染" else "网页样式查看（Vue 模块联邦）") },
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
                    }
                }
            },
        )

        if (!isLoading && !openInVueWebView && hasDataPage) {
            NativeSecondaryTabBar(
                tabs = listOf("数据页", "参数配置"),
                selectedIndex = pagerState.currentPage,
                onSelect = { idx -> scope.launch { pagerState.animateScrollToPage(idx) } },
            )
        }

        if (isLoading && !forceVueWebMode && !plugin.renderMode.equals("vue", ignoreCase = true)) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.accent)
            }
        } else if (openInVueWebView) {
            // Vue 模块联邦插件：直接免登进入隔离兼容模式，并通过 moviepilot.chrome v1 协议接管标题栏、动作、关闭与原背景
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
                    NativePluginFormRenderer(
                        pluginId = plugin.id,
                        pluginName = plugin.name,
                        documentJson = formJson ?: samplePluginFormJson(plugin.name),
                        vueSession = vueSession,
                        onSaveFullModel = { fullModel ->
                            scope.launch {
                                val ok = repository.savePluginFormModel(plugin.id, fullModel)
                                hasUnsavedChanges = false
                                snackbar?.showSnackbar(
                                    if (ok) "已无损保存「${plugin.name}」插件配置"
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

private fun samplePluginFormJson(name: String): String = """
{
  "render_mode": "vuetify",
  "conf": [
    {"component": "VAlert", "props": {"text": "由 Rust mp-core-plugin 实时解码生成的原生表单：$name"}},
    {"component": "VSwitch", "props": {"model": "enabled", "label": "启用插件"}},
    {"component": "VCronField", "props": {"model": "cron", "label": "执行周期"}}
  ],
  "model": {"enabled": true, "cron": "*/15 * * * *"}
}
"""
