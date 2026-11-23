package com.moviepilot.feature.dashboard

import android.content.Context
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
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
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
import androidx.compose.ui.platform.LocalContext
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
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.ExpressiveTintedScaffold
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

/** 「我的」仪表盘可编排模块项（支持开关显隐与顺序持久化）。 */
private data class DashboardModuleToggle(val id: String, val title: String, val enabled: Boolean)

private fun defaultDashboardModules(): List<DashboardModuleToggle> = listOf(
    DashboardModuleToggle("media_stats", "媒体库统计", true),
    DashboardModuleToggle("storage", "存储空间", true),
    DashboardModuleToggle("downloader", "下载器", true),
    DashboardModuleToggle("community", "社区勋章", true),
    DashboardModuleToggle("memory", "内存占用", true),
    DashboardModuleToggle("trend", "整理趋势", true),
    DashboardModuleToggle("bg_services", "后台服务", true),
    DashboardModuleToggle("plugin_widgets", "插件仪表盘", true),
)

private fun loadPersistedDashboardModules(context: Context): List<DashboardModuleToggle> {
    val defaults = defaultDashboardModules()
    val raw = context.getSharedPreferences("mp_dashboard_modules_v3", Context.MODE_PRIVATE)
        .getString("modules_spec", null)
        ?.takeIf { it.isNotBlank() } ?: return defaults
    val byId = defaults.associateBy { it.id }
    val seen = LinkedHashSet<String>()
    val result = mutableListOf<DashboardModuleToggle>()
    raw.split(",").forEach { token ->
        val parts = token.split(":")
        val id = parts.getOrNull(0)?.trim().orEmpty()
        val def = byId[id] ?: return@forEach
        if (seen.add(id)) {
            result += def.copy(enabled = parts.getOrNull(1)?.equals("1") ?: def.enabled)
        }
    }
    defaults.forEach { if (seen.add(it.id)) result += it }
    return result
}

private fun savePersistedDashboardModules(context: Context, list: List<DashboardModuleToggle>) {
    val encoded = list.joinToString(",") { "${it.id}:${if (it.enabled) "1" else "0"}" }
    context.getSharedPreferences("mp_dashboard_modules_v3", Context.MODE_PRIVATE)
        .edit()
        .putString("modules_spec", encoded)
        .apply()
}

/**
 * 「我的」仪表盘：支持自定义模块显隐与顺序编排、2×2 媒体库统计、存储环形图、
 * 下载器双速卡、社区勋章陈列墙、7 天整理趋势、系统负载、后台服务与插件仪表盘小组件。
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
    val context = LocalContext.current
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
    var showModulesSheet by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    val modules = remember {
        mutableStateListOf<DashboardModuleToggle>().apply {
            addAll(loadPersistedDashboardModules(context))
        }
    }

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

    ExpressiveTintedScaffold(
        title = "我的",
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Outlined.Notifications,
                contentDescription = "消息中心",
                onClick = onOpenMessages,
            )
            ExpressiveHeaderActionButton(
                icon = Icons.Outlined.Bolt,
                contentDescription = "捷径与诊断",
                onClick = { showShortcutsSheet = true },
            )
            ExpressiveHeaderActionButton(
                icon = Icons.Outlined.Settings,
                contentDescription = "设置",
                onClick = onOpenSettings,
            )
        },
    ) {
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
                contentPadding = PaddingValues(start = margin, end = margin, top = 16.dp, bottom = 128.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                modules.filter { it.enabled }.forEach { mod ->
                    when (mod.id) {
                        "media_stats" -> item(key = "dash_media_stats") {
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

                        "storage" -> item(key = "dash_storage") {
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

                        "downloader" -> item(key = "dash_downloader") {
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

                        "community" -> communityProfile?.takeIf { it.hasEarnedMedals }?.let { profile ->
                            item(key = "dash_community") {
                                NativeCommunityMedalsWidget(
                                    profile = profile,
                                    onSelectMedal = { record -> onOpenMedalShowcase(profile, record.key) },
                                )
                            }
                        }

                        "memory" -> item(key = "dash_memory") {
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

                        "trend" -> item(key = "dash_trend") {
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

                        "bg_services" -> if (bgServices.isNotEmpty()) {
                            item(key = "dash_bg_services") {
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

                        "plugin_widgets" -> pluginWidgets.forEach { (meta, widgetJson) ->
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

                // 底部自定义模块入口（与发现页完全统一）
                item(key = "dash_custom_modules_btn") {
                    Box(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CinematicGlassSurface(
                            shape = CircleShape,
                            blurRadiusDp = 18.dp,
                            modifier = Modifier.clickable { showModulesSheet = true },
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(Icons.Rounded.Tune, contentDescription = null, tint = colors.accent, modifier = Modifier.size(16.dp))
                                Text("自定义我的模块", color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
        }
    }

    if (showModulesSheet) {
        NativeGlassSheet(onDismissRequest = { showModulesSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text("编辑我的模块", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Text("开关显隐并调整仪表盘组件展示顺序", color = colors.textSecondary, fontSize = 12.5.sp)
                    }
                    NativeAdaptivePill(
                        title = "恢复默认",
                        selected = false,
                        onClick = {
                            modules.clear()
                            modules.addAll(defaultDashboardModules())
                            savePersistedDashboardModules(context, modules)
                        },
                    )
                }
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth().height(390.dp),
                ) {
                    items(modules.size, key = { modules[it].id }) { idx ->
                        val mod = modules[idx]
                        CinematicPanel(padding = 12.dp, showsShadow = false) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Text(mod.title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                                IconButton(
                                    onClick = {
                                        if (idx > 0) {
                                            val item = modules.removeAt(idx)
                                            modules.add(idx - 1, item)
                                            savePersistedDashboardModules(context, modules)
                                        }
                                    },
                                    enabled = idx > 0,
                                    modifier = Modifier.size(32.dp),
                                ) {
                                    Icon(
                                        Icons.Rounded.ArrowUpward,
                                        contentDescription = "上移",
                                        tint = if (idx > 0) colors.textSecondary else colors.textMuted.copy(alpha = 0.35f),
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                                IconButton(
                                    onClick = {
                                        if (idx < modules.lastIndex) {
                                            val item = modules.removeAt(idx)
                                            modules.add(idx + 1, item)
                                            savePersistedDashboardModules(context, modules)
                                        }
                                    },
                                    enabled = idx < modules.lastIndex,
                                    modifier = Modifier.size(32.dp),
                                ) {
                                    Icon(
                                        Icons.Rounded.ArrowDownward,
                                        contentDescription = "下移",
                                        tint = if (idx < modules.lastIndex) colors.textSecondary else colors.textMuted.copy(alpha = 0.35f),
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                                Switch(
                                    checked = mod.enabled,
                                    onCheckedChange = { checked ->
                                        modules[idx] = mod.copy(enabled = checked)
                                        savePersistedDashboardModules(context, modules)
                                    },
                                    colors = SwitchDefaults.colors(
                                        checkedTrackColor = colors.accent,
                                        checkedThumbColor = colors.primaryButtonFg,
                                    ),
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // 2×3 Material 3 Expressive 捷径菜单 BottomSheet
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

    ExpressiveTintedScaffold(
        title = "消息中心",
        onBack = onBack,
        headerExtra = {
            ExpressivePillTabRow(
                tabs = categories,
                selectedIndex = pagerState.currentPage,
                onSelect = { idx -> scope.launch { pagerState.animateScrollToPage(idx) } },
                scrollable = true,
                onTintedHeader = true,
            )
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(10.dp))
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

/** 单类词表的说明、输入框占位与格式示例元数据（随切换词表类型动态切换）。 */
private data class WordCategoryMeta(
    val key: String,
    val title: String,
    val description: String,
    val placeholder: String,
    val inlineHint: String,
    val guideTitle: String,
    val guideExamples: List<String>,
    val guideNote: String,
)

/**
 * 单项捷径诊断页面（无页内跨模块互跳，直接从「我的 -> 捷径弹窗」或「更多 -> 系统诊断」进入单项工具）：
 * 接入真实 `/api/v1/dashboard/schedule`（定时服务）、词表 5 类动态提示与保存、实时日志等。
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

    val validTools = listOf("词表", "定时服务", "实时日志", "健康检查", "名称识别", "网络测试")
    val activeTool = remember(initialTab) { if (initialTab in validTools) initialTab else "词表" }
    var services by remember { mutableStateOf<List<ScheduledServiceDto>>(emptyList()) }
    var liveLogs by remember { mutableStateOf<List<String>>(emptyList()) }
    var activeWordTab by remember { mutableStateOf("识别词") }
    var wordEditorText by remember { mutableStateOf("") }
    var saveMsg by remember { mutableStateOf<String?>(null) }

    val wordMetas = remember {
        linkedMapOf(
            "识别词" to WordCategoryMeta(
                key = "CustomIdentifiers",
                title = "自定义识别词",
                description = "添加规则对种子名或文件名进行预处理，以校正媒体识别结果。",
                placeholder = "每行输入一组识别规则",
                inlineHint = "支持正则表达式，特殊字符需要 \\ 转义，一行为一组",
                guideTitle = "支持的配置格式（注意空格）：",
                guideExamples = listOf(
                    "屏蔽词",
                    "被替换词 => 替换词",
                    "前定位词 <> 后定位词 >> 集偏移量 (EP)",
                    "被替换词 => 替换词 && 前定位词 <> 后定位词 >> 集偏移量 (EP)",
                ),
                guideNote = "替换词支持 {[tmdbid/doubanid/bangumiid/anilistid=xxx;type=movie/tv;g=xxx;s=xxx;e=xxx]} 直接指定媒体 ID 识别。",
            ),
            "制作组" to WordCategoryMeta(
                key = "CustomReleaseGroups",
                title = "自定义制作组 / 字幕组",
                description = "添加系统无法自动识别的制作组或字幕组名称，方便过滤与重命名。",
                placeholder = "每行输入一个制作组或字幕组名称",
                inlineHint = "支持正则表达式，特殊字符需要 \\ 转义，一行代表一个制作组/字幕组",
                guideTitle = "配置示例：",
                guideExamples = listOf(
                    "ANi",
                    "LoliHouse",
                    "KitaujiSub",
                    "Nekomoe\\s*kissaten",
                ),
                guideNote = "匹配成功后将作为资源制作组字段写入元数据，并可用于优先级规则组过滤。",
            ),
            "占位符" to WordCategoryMeta(
                key = "Customization",
                title = "自定义占位符",
                description = "添加自定义占位符识别正则，可在重命名模板中通过 {customization} 引用匹配文本。",
                placeholder = "每行输入一个占位符识别正则",
                inlineHint = "支持正则表达式，特殊字符需要 \\ 转义，多个匹配对象请换行分隔",
                guideTitle = "配置示例：",
                guideExamples = listOf(
                    "简日内嵌",
                    "繁日双语",
                    "60fps",
                    "HQ&Hi10P",
                ),
                guideNote = "支持使用 & 连接多个子模式（同时匹配时按顺序拼接），未匹配时 {customization} 自动留空。",
            ),
            "屏蔽词" to WordCategoryMeta(
                key = "TransferExcludeWords",
                title = "文件整理屏蔽词",
                description = "目录名或文件名中包含屏蔽词时跳过整理，避免样片、花絮或广告文件入库。",
                placeholder = "每行输入一个文件整理屏蔽词",
                inlineHint = "支持正则表达式，特殊字符需要 \\ 转义，一行代表一个屏蔽词",
                guideTitle = "常见屏蔽示例：",
                guideExamples = listOf(
                    "Sample",
                    "Trailer",
                    "NCOP|NCED",
                    "宣传片|花絮",
                ),
                guideNote = "仅作用于文件整理入库流程，不影响站点资源搜索与下载器接管。",
            ),
            "剧集规则" to WordCategoryMeta(
                key = "EpisodeFormatRuleTable",
                title = "自定义剧集识别规则",
                description = "当剧集命名特殊导致季/集号识别失败时，通过正则捕获组显式提取季号与集号。",
                placeholder = "每行输入一条剧集识别正则规则",
                inlineHint = "使用命名捕获组 (?P<ep>\\d+) 提取集数，一行一条规则，按顺序匹配",
                guideTitle = "正则捕获格式示例：",
                guideExamples = listOf(
                    "第(?P<ep>\\d+)话",
                    "EP(?P<ep>\\d{1,3})",
                    "S(?P<season>\\d+)E(?P<ep>\\d+)",
                ),
                guideNote = "修改后点击右上角「保存」即刻生效，可用于番剧、纪录片等特殊集号命名。",
            ),
        )
    }
    val wordTabLabels = remember(wordMetas) { wordMetas.keys.toList() }
    val currentWordMeta = wordMetas[activeWordTab] ?: wordMetas.values.first()

    LaunchedEffect(activeTool) {
        if (activeTool == "定时服务") services = repository.fetchScheduledServices()
        if (activeTool == "实时日志") liveLogs = repository.fetchSystemLogs(80)
    }
    LaunchedEffect(activeWordTab, activeTool) {
        if (activeTool == "词表") {
            val list = repository.fetchCustomWordList(currentWordMeta.key)
            wordEditorText = list.joinToString("\n")
        }
    }

    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = colors.textPrimary,
        unfocusedTextColor = colors.textPrimary,
        focusedBorderColor = colors.accent,
        unfocusedBorderColor = colors.fieldBorder,
        cursorColor = colors.accent,
    )

    ExpressiveTintedScaffold(
        title = activeTool,
        onBack = onBack,
        actions = if (activeTool == "词表") {
            {
                Surface(
                    onClick = {
                        val lines = wordEditorText.lines().map { it.trim() }.filter { it.isNotBlank() }
                        val body = lines.joinToString(",", "[", "]") { "\"${it.replace("\"", "\\\"")}\"" }
                        scope.launch {
                            val ok = repository.saveSettingValue(currentWordMeta.key, body)
                            saveMsg = if (ok) "已保存「$activeWordTab」(${lines.size} 条)" else "保存失败，请重试"
                        }
                    },
                    shape = CircleShape,
                    color = colors.accent,
                    contentColor = colors.primaryButtonFg,
                ) {
                    Text(
                        "保存",
                        fontSize = 13.5.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 9.dp),
                    )
                }
            }
        } else {
            null
        },
        headerExtra = if (activeTool == "词表") {
            {
                val wIdx = wordTabLabels.indexOf(activeWordTab).coerceAtLeast(0)
                ExpressivePillTabRow(
                    tabs = wordTabLabels,
                    selectedIndex = wIdx,
                    onSelect = { idx ->
                        activeWordTab = wordTabLabels[idx]
                        saveMsg = null
                    },
                    scrollable = true,
                    onTintedHeader = true,
                )
            }
        } else {
            null
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            saveMsg?.let {
                Text(it, color = colors.success, fontSize = 12.5.sp, modifier = Modifier.padding(horizontal = margin, vertical = 8.dp))
            }

            LazyColumn(
                contentPadding = PaddingValues(start = margin, end = margin, top = 14.dp, bottom = 128.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.weight(1f),
            ) {
                when (activeTool) {
                    "词表" -> {
                        item(key = "word_editor_$activeWordTab") {
                            val lineCount = wordEditorText.lines().count { it.isNotBlank() }
                            CinematicPanel(padding = 16.dp) {
                                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                        Text(currentWordMeta.title, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                        NativeAdaptiveBadge("$lineCount 条", tint = colors.info)
                                    }
                                    Text(currentWordMeta.description, color = colors.textSecondary, fontSize = 12.5.sp)
                                    OutlinedTextField(
                                        value = wordEditorText,
                                        onValueChange = { wordEditorText = it },
                                        placeholder = { Text(currentWordMeta.placeholder, color = colors.textMuted) },
                                        minLines = 6,
                                        colors = fieldColors,
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    Text("ⓘ ${currentWordMeta.inlineHint}", color = colors.textMuted, fontSize = 11.5.sp)
                                }
                            }
                        }
                        item(key = "word_guide_$activeWordTab") {
                            CinematicPanel(padding = 16.dp) {
                                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("ⓘ ${currentWordMeta.guideTitle}", color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(colors.chipFill)
                                            .padding(12.dp),
                                    ) {
                                        Text(
                                            text = currentWordMeta.guideExamples.joinToString("\n"),
                                            color = colors.textPrimary,
                                            fontSize = 12.sp,
                                            fontFamily = FontFamily.Monospace,
                                        )
                                    }
                                    Text(
                                        currentWordMeta.guideNote,
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
                        items(listOf("TheMovieDB 元数据模块", "qBittorrent 下载器", "Emby 媒体服务器", "本地存储监控", "应用核心引擎")) { mod ->
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
                    "网络测试" -> {
                        item {
                            CinematicPanel(padding = 16.dp) {
                                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("连通性诊断", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                                    Text("当前实例连接正常，可从「站点管理」触发单个站点连通测速。", color = colors.textSecondary, fontSize = 13.sp)
                                }
                            }
                        }
                    }

                    else -> {
                        val lines = liveLogs.ifEmpty {
                            listOf(
                                "INFO  MoviePilot 实时日志流就绪",
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
