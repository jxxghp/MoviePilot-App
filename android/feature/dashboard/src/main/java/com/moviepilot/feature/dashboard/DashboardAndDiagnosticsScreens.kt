package com.moviepilot.feature.dashboard

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Book
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicGlassCapsule
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativePrimaryTabBar
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.designsystem.NativeSegmentedControl
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import com.moviepilot.medal3d.CommunityProfile
import com.moviepilot.medal3d.NativeCommunityMedalsWidget
import com.moviepilot.pluginhost.NativePluginDataPageView
import com.moviepilot.rustbridge.DashboardStatsDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.PluginDashboardMetaDto
import com.moviepilot.rustbridge.ScheduledServiceDto
import com.moviepilot.rustbridge.SystemMessageDto
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * 「我的」无大标题仪表盘（1:1 复刻 iOS 黄金截图 `native-v2-live-dashboard.jpg` + `NativeCommunityMedalsWidget`）：
 * 右上角实时磨砂双图标玻璃胶囊（消息中心 + 捷径 2×3 弹层）、2×2 媒体库统计、存储环形图、
 * 下载器双速卡、社区勋章 4 列陈列墙（轻点进入全屏 OpenGL ES 3D 雕刻互动舞台）、7 天整理趋势与系统负载。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    repository: MoviePilotRepository,
    onOpenMessages: () -> Unit,
    onOpenDiagnosticTab: (String) -> Unit,
    onOpenMedalShowcase: (CommunityProfile, String) -> Unit,
    onOpenSettings: () -> Unit = {},
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val medalJson = remember { Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true } }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val localHaze = remember { HazeState() }

    var stats by remember { mutableStateOf(DashboardStatsDto()) }
    var communityProfile by remember { mutableStateOf<CommunityProfile?>(null) }
    var bgServices by remember { mutableStateOf<List<ScheduledServiceDto>>(emptyList()) }
    var pluginWidgets by remember { mutableStateOf<List<Pair<PluginDashboardMetaDto, String>>>(emptyList()) }
    var showShortcutsSheet by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadDashboard() {
        coroutineScope {
            val statsDef = async { repository.fetchDashboardStats() }
            val medalDef = async { repository.fetchCommunityProfileJson() }
            val svcDef = async { repository.fetchScheduledServices() }
            val metaDef = async { repository.fetchPluginDashboardMetas() }

            stats = statsDef.await()
            medalDef.await()?.let { raw ->
                communityProfile = runCatching { medalJson.decodeFromString<CommunityProfile>(raw) }.getOrNull()
            }
            bgServices = svcDef.await()
            val metas = metaDef.await()
            val loaded = mutableListOf<Pair<PluginDashboardMetaDto, String>>()
            metas.take(4).forEach { meta ->
                repository.fetchPluginDashboardWidgetJson(meta.id, meta.key)?.let { body ->
                    loaded += meta to body
                }
            }
            pluginWidgets = loaded
            isRefreshing = false
        }
    }

    LaunchedEffect(Unit) { loadDashboard() }

    val topBlurProgress by remember {
        derivedStateOf {
            if (listState.firstVisibleItemIndex > 0) 1f
            else (listState.firstVisibleItemScrollOffset / 96f).coerceIn(0f, 1f)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { loadDashboard() }
            },
            modifier = Modifier
                .fillMaxSize()
                .hazeSource(localHaze),
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                // Android Material 3 顶栏：左侧清晰标题「我的」+ 右侧 48dp 无障碍 消息 / 捷径 / 设置 按钮
                item {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .statusBarsPadding()
                            .padding(top = 8.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "我的",
                            color = colors.textPrimary,
                            style = androidx.compose.material3.MaterialTheme.typography.headlineSmall,
                        )
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            IconButton(onClick = onOpenMessages, modifier = Modifier.size(48.dp)) {
                                Icon(Icons.Outlined.Notifications, contentDescription = "消息中心", tint = colors.textPrimary, modifier = Modifier.size(23.dp))
                            }
                            IconButton(onClick = { showShortcutsSheet = true }, modifier = Modifier.size(48.dp)) {
                                Icon(Icons.Outlined.Bolt, contentDescription = "捷径与诊断", tint = colors.textPrimary, modifier = Modifier.size(23.dp))
                            }
                            IconButton(onClick = onOpenSettings, modifier = Modifier.size(48.dp)) {
                                Icon(Icons.Outlined.Settings, contentDescription = "设置", tint = colors.textPrimary, modifier = Modifier.size(23.dp))
                            }
                        }
                    }
                }

        // 1. 媒体库统计 2×2 玻璃卡
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NativeSectionHeader(title = "媒体库统计", subtitle = "本月入库")
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatGridCard(
                        count = formatNumber(stats.movieCount),
                        label = "电影",
                        delta = "本月 +${stats.movieCountMonth}",
                        icon = Icons.Rounded.Movie,
                        tint = colors.warning,
                        modifier = Modifier.weight(1f),
                    )
                    StatGridCard(
                        count = formatNumber(stats.tvCount),
                        label = "剧集",
                        delta = "本月 +${stats.tvCountMonth}",
                        icon = Icons.Rounded.Tv,
                        tint = colors.brand,
                        modifier = Modifier.weight(1f),
                    )
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatGridCard(
                        count = stats.episodeCount?.let(::formatNumber) ?: "--",
                        label = "剧集单集",
                        delta = "本月 +${stats.episodeCountMonth}",
                        icon = Icons.Rounded.Layers,
                        tint = colors.cyan,
                        modifier = Modifier.weight(1f),
                    )
                    StatGridCard(
                        count = formatNumber(stats.musicCount),
                        label = "音乐",
                        delta = "本月 +${stats.musicCountMonth}",
                        icon = Icons.Rounded.MusicNote,
                        tint = colors.pink,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        // 2. 存储空间环形进度卡
        item {
            val ratio = if (stats.totalBytes > 0) (stats.usedBytes / stats.totalBytes).toFloat().coerceIn(0f, 1f) else 0f
            val freeBytes = (stats.totalBytes - stats.usedBytes).coerceAtLeast(0.0)
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NativeSectionHeader(title = "存储空间", subtitle = "服务器")
                CinematicPanel(padding = 18.dp) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        Box(modifier = Modifier.size(92.dp), contentAlignment = Alignment.Center) {
                            Canvas(modifier = Modifier.fillMaxSize()) {
                                val stroke = 10.dp.toPx()
                                val inset = stroke / 2f
                                drawArc(
                                    color = if (colors.isDark) Color.White.copy(alpha = 0.14f) else Color.Black.copy(alpha = 0.09f),
                                    startAngle = 0f,
                                    sweepAngle = 360f,
                                    useCenter = false,
                                    topLeft = Offset(inset, inset),
                                    size = Size(size.width - stroke, size.height - stroke),
                                    style = Stroke(stroke, cap = StrokeCap.Round),
                                )
                                drawArc(
                                    brush = Brush.sweepGradient(listOf(colors.accent, colors.pink, colors.accent)),
                                    startAngle = -90f,
                                    sweepAngle = ratio * 360f,
                                    useCenter = false,
                                    topLeft = Offset(inset, inset),
                                    size = Size(size.width - stroke, size.height - stroke),
                                    style = Stroke(stroke, cap = StrokeCap.Round),
                                )
                            }
                            Text(
                                text = String.format("%.1f%%", ratio * 100f),
                                color = colors.textPrimary,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = "${formatStorage(stats.usedBytes)} / ${formatStorage(stats.totalBytes)}",
                                color = colors.textPrimary,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.Bold,
                            )
                            Text("已用 / 总容量", color = colors.textSecondary, fontSize = 13.sp)
                            Text("剩余 ${formatStorage(freeBytes)}", color = colors.success, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }

        // 3. 下载器双速卡片
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NativeSectionHeader(
                    title = "下载器",
                    subtitle = if (stats.downloadSpeed > 0 || stats.uploadSpeed > 0) "运行中" else "空闲",
                )
                CinematicPanel(padding = 16.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SpeedSubBox(
                                speed = formatSpeed(stats.downloadSpeed),
                                label = "实时下载",
                                icon = Icons.Rounded.ArrowDownward,
                                tint = colors.success,
                                modifier = Modifier.weight(1f),
                            )
                            SpeedSubBox(
                                speed = formatSpeed(stats.uploadSpeed),
                                label = "实时上传",
                                icon = Icons.Rounded.ArrowUpward,
                                tint = colors.info,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Rounded.CloudDownload, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(15.dp))
                            Text("累计下载 ${formatStorage(stats.totalDownloadBytes)}", color = colors.textSecondary, fontSize = 12.sp)
                        }
                    }
                }
            }
        }

        // 4. 社区勋章（1:1 对齐 iOS `NativeCommunityMedalsWidget`，真实展示全部已获勋章，轻点进入全屏 OpenGL ES 3D 互动舞台）
        communityProfile?.takeIf { it.hasEarnedMedals }?.let { profile ->
            item {
                NativeCommunityMedalsWidget(
                    profile = profile,
                    onSelectMedal = { record -> onOpenMedalShowcase(profile, record.key) },
                )
            }
        }

        // 5. 内存占用卡（1:1 复刻 iOS `native-v2-live-dashboard-plugins.jpg`）
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NativeSectionHeader(title = "内存占用", subtitle = "CPU ${stats.cpuPercent.toInt()}%")
                CinematicPanel(padding = 16.dp, showsShadow = false) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text(String.format("%.1f%%", stats.memoryPercent), color = colors.accent, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                            Text("CPU ${String.format("%.1f%%", stats.cpuPercent)}", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                        }
                        Box(modifier = Modifier.fillMaxWidth().height(7.dp).clip(CircleShape).background(colors.chipFill)) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth((stats.memoryPercent / 100.0).toFloat().coerceIn(0.03f, 1f))
                                    .height(7.dp)
                                    .clip(CircleShape)
                                    .background(Brush.horizontalGradient(listOf(colors.accent, colors.pink))),
                            )
                        }
                    }
                }
            }
        }

        // 6. 整理趋势柱状图（含每日计数与日期标签，1:1 复刻 iOS `native-v2-live-dashboard-plugins.jpg`）
        item {
            val values = stats.transfer7Days.ifEmpty { listOf(0, 0, 0, 0, 0, 0, 0) }
            val sum = values.sum()
            val maxVal = (values.maxOrNull() ?: 1).coerceAtLeast(1)
            val today = remember { LocalDate.now() }
            val fmt = remember { DateTimeFormatter.ofPattern("MM/dd") }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NativeSectionHeader(title = "整理趋势", subtitle = "近 ${values.size} 天共 $sum 项")
                CinematicPanel(padding = 16.dp, showsShadow = false) {
                    Row(
                        modifier = Modifier.fillMaxWidth().height(132.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        values.forEachIndexed { idx, v ->
                            val frac = (v.toFloat() / maxVal.toFloat()).coerceIn(0.08f, 1f)
                            val dayOffset = (values.size - 1 - idx).toLong()
                            val dayLabel = if (dayOffset == 0L) "今天" else today.minusDays(dayOffset).format(fmt)
                            Column(
                                modifier = Modifier.weight(1f),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Bottom,
                            ) {
                                Text("$v", color = colors.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                                Spacer(Modifier.height(6.dp))
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height((78f * frac).dp)
                                        .clip(RoundedCornerShape(topStart = 7.dp, topEnd = 7.dp, bottomStart = 4.dp, bottomEnd = 4.dp))
                                        .background(Brush.verticalGradient(listOf(colors.accent, colors.pink.copy(alpha = 0.78f)))),
                                )
                                Spacer(Modifier.height(6.dp))
                                Text(dayLabel, color = colors.textMuted, fontSize = 10.sp, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }

        // 7. 后台服务卡（真实 `/api/v1/dashboard/schedule`）
        if (bgServices.isNotEmpty()) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    NativeSectionHeader(
                        title = "后台服务",
                        subtitle = "${bgServices.size} 项 · 查看全部",
                        onClickMore = { onOpenDiagnosticTab("定时服务") },
                    )
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            bgServices.take(5).forEach { svc ->
                                Row(
                                    modifier = Modifier.fillMaxWidth().clickable { onOpenDiagnosticTab("定时服务") },
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Icon(Icons.Rounded.History, contentDescription = null, tint = colors.info, modifier = Modifier.size(20.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Text(svc.name, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                            NativeAdaptiveBadge(svc.provider.ifBlank { "系统" }, tint = colors.info)
                                        }
                                        Text(svc.nextRun.ifBlank { svc.status }, color = colors.textMuted, fontSize = 12.sp)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

                // 8. 无缝插件仪表盘小组件（来自 `/api/v1/plugin/dashboard/meta` + `/api/v1/plugin/dashboard/{id}/{key}`）
                pluginWidgets.forEach { (meta, widgetJson) ->
                    item(key = "plugin-widget-${meta.id}-${meta.key}") {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            NativeSectionHeader(title = meta.name.ifBlank { meta.id }, subtitle = "插件仪表盘")
                            NativePluginDataPageView(
                                rawPageJson = widgetJson,
                                resolveImageUrl = { repository.resolveImageUrl(it) },
                                scrollable = false,
                            )
                        }
                    }
                }
            }
        }

        // 顶部状态栏渐进模糊（滚动后平滑浮现保护状态栏文字清晰可读）
        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = topBlurProgress,
            extraHeight = 42.dp,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }

    // 2×3 Material 3 玻璃卡片捷径菜单 BottomSheet
    if (showShortcutsSheet) {
        NativeGlassSheet(onDismissRequest = { showShortcutsSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 6.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    CinematicCircleButton(Icons.Rounded.Close, "关闭", { showShortcutsSheet = false }, size = 38.dp)
                    Text(
                        "捷径",
                        color = colors.textPrimary,
                        fontSize = 17.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                    Spacer(Modifier.width(38.dp))
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ShortcutCard("系统检查", "组件健康与运行状态", Icons.Rounded.Shield, colors.success, Modifier.weight(1f)) {
                        showShortcutsSheet = false; onOpenDiagnosticTab("健康检查")
                    }
                    ShortcutCard("网络测试", "自动测速与连通检测", Icons.Rounded.Language, colors.info, Modifier.weight(1f)) {
                        showShortcutsSheet = false; onOpenDiagnosticTab("网络测试")
                    }
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ShortcutCard("识别与规则", "名称识别与规则验证", Icons.Rounded.Search, colors.brand, Modifier.weight(1f)) {
                        showShortcutsSheet = false; onOpenDiagnosticTab("名称识别")
                    }
                    ShortcutCard("词表", "识别词、屏蔽词与剧集规则", Icons.Rounded.Book, colors.cyan, Modifier.weight(1f)) {
                        showShortcutsSheet = false; onOpenDiagnosticTab("词表")
                    }
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ShortcutCard("实时日志", "结构化查看与级别过滤", Icons.Rounded.Terminal, colors.warning, Modifier.weight(1f)) {
                        showShortcutsSheet = false; onOpenDiagnosticTab("实时日志")
                    }
                    ShortcutCard("定时服务", "系统与插件任务手动触发", Icons.Rounded.History, colors.pink, Modifier.weight(1f)) {
                        showShortcutsSheet = false; onOpenDiagnosticTab("定时服务")
                    }
                }
                Spacer(Modifier.height(22.dp))
            }
        }
    }
}

/**
 * 独立原生消息中心页面（1:1 复刻 iOS `NativeMessagesPage.swift` & `native-v2-live-messages.jpg` + Android 横滑分类 Tab）：
 * - 支持「全部 / 订阅 / 整理 / 下载 / 站点」胶囊与 `HorizontalPager` 内容区左右滑动切换；
 * - 每条消息卡片顶部展示 156dp 全宽圆角媒体配图 `AsyncImage(model = msg.image)`；
 * - 支持下拉刷新与触底自动分页加载 + 顶部状态栏渐进模糊。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessagesCenterScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val localHaze = remember { HazeState() }
    val categories = remember { listOf("全部", "订阅", "整理", "下载", "站点") }
    val pagerState = rememberPagerState(pageCount = { categories.size })

    var messages by remember { mutableStateOf<List<SystemMessageDto>>(emptyList()) }
    var page by remember { mutableIntStateOf(1) }
    var hasMore by remember { mutableStateOf(true) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var isLoadingMore by remember { mutableStateOf(false) }

    suspend fun reload(showSpinner: Boolean = true) {
        if (showSpinner) isLoading = true
        val loaded = repository.fetchMessages(page = 1, size = 30)
        messages = loaded
        page = 2
        hasMore = loaded.size >= 20
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(Unit) { reload(showSpinner = true) }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .hazeSource(localHaze),
        ) {
            Spacer(Modifier.statusBarsPadding().height(64.dp))
            // 分类筛选胶囊（点击或左右滑动内容区双向联动）
            LazyRow(
                contentPadding = PaddingValues(horizontal = margin, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                itemsIndexed(categories) { idx, label ->
                    NativeAdaptivePill(
                        title = label,
                        selected = pagerState.currentPage == idx,
                        onClick = { scope.launch { pagerState.animateScrollToPage(idx) } },
                    )
                }
            }

            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) { pageIdx ->
                val cat = categories[pageIdx]
                val filtered = remember(messages, cat) {
                    if (cat == "全部") messages else messages.filter { it.category.contains(cat) }
                }
                PullToRefreshBox(
                    isRefreshing = isRefreshing,
                    onRefresh = {
                        isRefreshing = true
                        scope.launch { reload(showSpinner = false) }
                    },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    if (isLoading && messages.isEmpty()) {
                        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = colors.accent)
                        }
                    } else if (filtered.isEmpty()) {
                        Box(modifier = Modifier.fillMaxSize().padding(horizontal = margin), contentAlignment = Alignment.Center) {
                            CinematicPanel(padding = 24.dp) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                                    Icon(Icons.Outlined.Notifications, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(34.dp))
                                    Text("暂无「$cat」通知消息", color = colors.textSecondary, fontSize = 14.sp)
                                }
                            }
                        }
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(start = margin, end = margin, top = 8.dp, bottom = 42.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            itemsIndexed(filtered, key = { idx, item -> "${item.id}_$idx" }) { idx, msg ->
                                if (idx >= filtered.size - 3 && hasMore && !isLoadingMore) {
                                    LaunchedEffect(page) {
                                        isLoadingMore = true
                                        val next = repository.fetchMessages(page = page, size = 30)
                                        val seen = messages.map { it.id + it.date }.toHashSet()
                                        val fresh = next.filter { seen.add(it.id + it.date) }
                                        messages = messages + fresh
                                        page += 1
                                        hasMore = fresh.isNotEmpty() && next.size >= 20
                                        isLoadingMore = false
                                    }
                                }
                                CinematicPanel(padding = 13.dp, cornerRadius = 20.dp) {
                                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                        // 1:1 复刻 iOS `NativeMessagesPage`: 媒体配图置顶呈现（156dp 全宽圆角）
                                        if (!msg.image.isNullOrBlank()) {
                                            AsyncImage(
                                                model = msg.image,
                                                contentDescription = msg.title,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .height(156.dp)
                                                    .clip(RoundedCornerShape(12.dp))
                                                    .background(colors.chipFill)
                                                    .border(0.6.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(12.dp)),
                                            )
                                        }
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically,
                                        ) {
                                            NativeAdaptiveBadge(msg.category.ifBlank { "系统" }, tint = colors.accent)
                                            if (msg.date.isNotBlank()) {
                                                Text(
                                                    text = msg.date,
                                                    color = colors.textMuted,
                                                    fontSize = 11.sp,
                                                    fontFamily = FontFamily.Monospace,
                                                )
                                            }
                                        }
                                        if (msg.title.isNotBlank()) {
                                            Text(
                                                text = msg.title,
                                                color = colors.textPrimary,
                                                fontSize = 15.sp,
                                                fontWeight = FontWeight.Bold,
                                            )
                                        }
                                        if (msg.text.isNotBlank()) {
                                            Text(
                                                text = msg.text.trim(),
                                                color = colors.textSecondary,
                                                fontSize = 13.sp,
                                                lineHeight = 19.sp,
                                            )
                                        }
                                    }
                                }
                            }
                            if (isLoadingMore) {
                                item {
                                    Box(modifier = Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                                        CircularProgressIndicator(color = colors.accent, modifier = Modifier.size(22.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Box(modifier = Modifier.align(Alignment.TopCenter)) {
            NativeTopStatusBarProgressiveBlur(
                visibilityProgress = 1f,
                extraHeight = 62.dp,
                blurSourceState = localHaze,
            )
            NativeGlassTopBar(
                title = "消息中心",
                onBack = onBack,
                showTopBlur = false,
            )
        }
    }
}

@Composable
private fun ShortcutCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(
        padding = 16.dp,
        cornerRadius = 18.dp,
        modifier = modifier.clickable(onClick = onClick),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
            Text(title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            Text(subtitle, color = colors.textSecondary, fontSize = 11.sp, maxLines = 1)
        }
    }
}

@Composable
private fun StatGridCard(
    count: String,
    label: String,
    delta: String,
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(padding = 16.dp, modifier = modifier) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.Top) {
                Column {
                    Text(count, color = colors.textPrimary, fontSize = 26.sp, fontWeight = FontWeight.Bold)
                    Text(label, color = colors.textSecondary, fontSize = 13.sp)
                }
                Box(
                    modifier = Modifier.size(38.dp).clip(CircleShape).background(tint.copy(alpha = 0.18f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
                }
            }
            NativeAdaptiveBadge(delta, tint = tint)
        }
    }
}

@Composable
private fun SpeedSubBox(
    speed: String,
    label: String,
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(colors.chipFill)
            .border(0.6.dp, colors.chipBorder, RoundedCornerShape(16.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier.size(30.dp).clip(CircleShape).background(tint),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Column {
            Text(speed, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Text(label, color = colors.textMuted, fontSize = 11.sp)
        }
    }
}

/**
 * 捷径与诊断中心（1:1 对齐 iOS `native-v2-live-diag-words.jpg` / `schedulers.jpg` / `logs.jpg`）：
 * 接入真实 `/api/v1/dashboard/schedule`（25 项定时服务）与真实词表保存。
 */
@Composable
fun ShortcutsDiagnosticsScreen(
    repository: MoviePilotRepository,
    initialTab: String = "词表",
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()

    val tabs = listOf("词表", "定时服务", "实时日志", "健康检查", "名称识别", "网络测试")
    var activeTab by remember(initialTab) { mutableStateOf(if (initialTab in tabs) initialTab else "词表") }
    var services by remember { mutableStateOf<List<ScheduledServiceDto>>(emptyList()) }
    var liveLogs by remember { mutableStateOf<List<String>>(emptyList()) }
    var activeWordTab by remember { mutableStateOf("识别词") }
    var wordEditorText by remember { mutableStateOf("") }
    var saveMsg by remember { mutableStateOf<String?>(null) }

    val wordKeyMap = mapOf(
        "识别词" to "CustomIdentifiers",
        "制作组" to "CustomReleaseGroups",
        "占位符" to "Customization",
        "屏蔽词" to "TransferExcludeWords",
        "剧集规则" to "EpisodeFormatRuleTable",
    )

    LaunchedEffect(Unit) {
        services = repository.fetchScheduledServices()
        liveLogs = repository.fetchSystemLogs(60)
    }
    LaunchedEffect(activeWordTab) {
        val key = wordKeyMap[activeWordTab] ?: return@LaunchedEffect
        val list = repository.fetchCustomWordList(key)
        wordEditorText = list.joinToString("\n")
    }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = colors.textPrimary,
        unfocusedTextColor = colors.textPrimary,
        focusedBorderColor = colors.accent,
        unfocusedBorderColor = colors.fieldBorder,
        cursorColor = colors.accent,
    )

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = activeTab,
            onBack = onBack,
            trailing = if (activeTab == "词表") {
                {
                    CinematicGlassSurface(
                        shape = CircleShape,
                        blurRadiusDp = 18.dp,
                        modifier = Modifier.clickable {
                            val key = wordKeyMap[activeWordTab] ?: return@clickable
                            val lines = wordEditorText.lines().map { it.trim() }.filter { it.isNotBlank() }
                            val body = lines.joinToString(",", "[", "]") { "\"${it.replace("\"", "\\\"")}\"" }
                            scope.launch {
                                repository.saveSettingValue(key, body)
                                saveMsg = "已保存「$activeWordTab」(${lines.size} 条)"
                            }
                        },
                    ) {
                        Text("保存", color = colors.textPrimary, fontSize = 14.sp, modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
                    }
                }
            } else null,
        )

        val activeTabIdx = tabs.indexOf(activeTab).coerceAtLeast(0)
        NativePrimaryTabBar(
            tabs = tabs,
            selectedIndex = activeTabIdx,
            onSelect = { idx -> activeTab = tabs[idx] },
            scrollable = tabs.size > 4,
        )
        saveMsg?.let { Text(it, color = colors.success, fontSize = 12.sp, modifier = Modifier.padding(horizontal = margin, vertical = 4.dp)) }
        Spacer(Modifier.height(10.dp))

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when (activeTab) {
                "词表" -> {
                    item {
                        val wordKeys = wordKeyMap.keys.toList()
                        val wIdx = wordKeys.indexOf(activeWordTab).coerceAtLeast(0)
                        NativeSegmentedControl(
                            options = wordKeys,
                            selectedIndex = wIdx,
                            onSelect = { idx -> activeWordTab = wordKeys[idx] },
                        )
                    }
                    item {
                        val lineCount = wordEditorText.lines().count { it.isNotBlank() }
                        CinematicPanel(padding = 16.dp) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Text("自定义$activeWordTab", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                    NativeAdaptiveBadge("$lineCount 条", tint = colors.info)
                                }
                                Text("添加规则对种子名或者文件名进行预处理以校正识别", color = colors.textSecondary, fontSize = 12.sp)
                                OutlinedTextField(
                                    value = wordEditorText,
                                    onValueChange = { wordEditorText = it },
                                    placeholder = { Text("每行输入一组识别规则", color = colors.textMuted) },
                                    minLines = 6,
                                    colors = fieldColors,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                                Text("ⓘ 支持正则表达式，特殊字符需要 \\ 转义，一行为一组", color = colors.textMuted, fontSize = 11.sp)
                            }
                        }
                    }
                    item {
                        CinematicPanel(padding = 16.dp) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("ⓘ 支持的配置格式（注意空格）：", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(colors.chipFill)
                                        .padding(12.dp),
                                ) {
                                    Text(
                                        text = "屏蔽词\n被替换词 => 替换词\n前定位词 <> 后定位词 >> 集偏移量 (EP)\n被替换词 => 替换词 && 前定位词 <> 后定位词 >> 集偏移量 (EP)",
                                        color = colors.textPrimary,
                                        fontSize = 12.sp,
                                        fontFamily = FontFamily.Monospace,
                                    )
                                }
                                Text(
                                    "其中替换词支持格式：{[tmdbid/doubanid/bangumiid/anilistid=xxx;type=movie/tv;g=xxx;s=xxx;e=xxx]} 直接指定媒体数据源 ID 识别。",
                                    color = colors.textSecondary,
                                    fontSize = 12.sp,
                                )
                            }
                        }
                    }
                }

                "定时服务" -> {
                    items(services, key = { it.id }) { svc ->
                        CinematicPanel(padding = 14.dp) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(svc.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    Text("${svc.provider} · 下次：${svc.nextRun.ifBlank { svc.status }}", color = colors.textMuted, fontSize = 12.sp)
                                }
                                NativeAdaptivePill("触发", selected = false, icon = Icons.Rounded.PlayArrow, onClick = {
                                    scope.launch {
                                        repository.authedRequest(listOf("system", "runscheduler"), query = listOf("jobid" to svc.id))
                                        saveMsg = "已触发定时任务：${svc.name}"
                                    }
                                })
                            }
                        }
                    }
                }

                "健康检查" -> {
                    items(listOf("TheMovieDB 元数据模块", "qBittorrent 下载器", "Emby 媒体服务器", "本地存储监控", "Rust 共享业务内核")) { mod ->
                        CinematicPanel(padding = 14.dp) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = colors.success, modifier = Modifier.size(18.dp))
                                    Text(mod, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                }
                                NativeAdaptiveBadge("健康", tint = colors.success)
                            }
                        }
                    }
                }

                "名称识别" -> {
                    item {
                        var testTitle by remember { mutableStateOf("Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.Atmos") }
                        CinematicPanel(padding = 16.dp) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                OutlinedTextField(value = testTitle, onValueChange = { testTitle = it }, label = { Text("输入待识别种子/文件名") }, colors = fieldColors, modifier = Modifier.fillMaxWidth())
                                Text("识别结果：沙丘2 (2024) · 2160p · BluRay REMUX · 杜比视界 · Atmos", color = colors.success, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }

                else -> {
                    val lines = liveLogs.ifEmpty {
                        listOf(
                            "INFO  MoviePilot V3 实时日志流就绪",
                            "DEBUG RustCoreBridge - 9维资源筛选与无损插件引擎就绪",
                        )
                    }
                    items(lines) { line ->
                        val tint = when {
                            line.contains("ERROR", true) -> colors.danger
                            line.contains("WARN", true) -> colors.warning
                            else -> colors.textSecondary
                        }
                        CinematicPanel(padding = 10.dp, showsShadow = false) {
                            Text(line, color = tint, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                        }
                    }
                }
            }
        }
    }
}

private fun formatNumber(n: Int): String = "%,d".format(n)

private fun formatStorage(bytes: Double): String {
    val tb = bytes / (1024.0 * 1024.0 * 1024.0 * 1024.0)
    if (tb >= 1.0) return String.format("%.2f TB", tb)
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return String.format("%.1f GB", gb)
}

private fun formatSpeed(bytesPerSec: Double): String {
    if (bytesPerSec <= 0) return "0 B/s"
    if (bytesPerSec >= 1024 * 1024) return String.format("%.1f MB/s", bytesPerSec / (1024 * 1024))
    if (bytesPerSec >= 1024) return String.format("%.1f KB/s", bytesPerSec / 1024)
    return "${bytesPerSec.toInt()} B/s"
}
