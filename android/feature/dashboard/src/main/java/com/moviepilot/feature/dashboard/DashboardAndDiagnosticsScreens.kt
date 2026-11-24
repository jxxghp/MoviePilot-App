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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Speed
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.medal3d.CommunityProfile
import com.moviepilot.medal3d.NativeCommunityMedalsWidget
import com.moviepilot.pluginhost.NativePluginDataPageView
import com.moviepilot.rustbridge.DashboardSessionSnapshot
import com.moviepilot.rustbridge.DashboardStatsDto
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.NetTestResultDto
import com.moviepilot.rustbridge.PluginDashboardMetaDto
import com.moviepilot.rustbridge.RecognizeResultDto
import com.moviepilot.rustbridge.ScheduledServiceDto
import com.moviepilot.rustbridge.SystemMessageDto
import com.moviepilot.rustbridge.SystemModuleStatusDto
import com.moviepilot.rustcore.PermissionsFfi
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
    permissions: PermissionsFfi? = null,
) {
    val colors = LocalMoviePilotColors.current
    val context = LocalContext.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val medalJson = remember { Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true } }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val isAdmin = permissions?.admin != false
    val initialCache = remember { repository.cachedDashboard }

    var stats by remember { mutableStateOf(initialCache?.stats ?: DashboardStatsDto()) }
    var communityProfile by remember {
        mutableStateOf(
            initialCache?.communityProfileJson?.let { raw ->
                runCatching { medalJson.decodeFromString<CommunityProfile>(raw) }.getOrNull()
            },
        )
    }
    var bgServices by remember { mutableStateOf(initialCache?.schedules ?: emptyList()) }
    var pluginWidgets by remember {
        mutableStateOf<List<Pair<PluginDashboardMetaDto, String>>>(
            initialCache?.pluginMetas?.mapNotNull { meta ->
                initialCache.pluginWidgets["${meta.id}:${meta.key}"]?.let { Pair(meta, it) }
            } ?: emptyList(),
        )
    }
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
            val svcDef = async { if (isAdmin) repository.fetchScheduledServices() else emptyList() }
            val metaDef = async { repository.fetchPluginDashboardMetas() }

            val loadedStats = statsDef.await()
            val rawMedal = medalDef.await()
            val loadedServices = svcDef.await()
            val metas = metaDef.await()

            stats = loadedStats
            rawMedal?.let { raw ->
                communityProfile = runCatching { medalJson.decodeFromString<CommunityProfile>(raw) }.getOrNull()
            }
            bgServices = loadedServices
            val loaded = mutableListOf<Pair<PluginDashboardMetaDto, String>>()
            val widgetMap = mutableMapOf<String, String>()
            metas.take(4).forEach { meta ->
                repository.fetchPluginDashboardWidgetJson(meta.id, meta.key)?.let { body ->
                    loaded += meta to body
                    widgetMap["${meta.id}:${meta.key}"] = body
                }
            }
            pluginWidgets = loaded
            repository.cachedDashboard = DashboardSessionSnapshot(
                stats = loadedStats,
                communityProfileJson = rawMedal,
                schedules = loadedServices,
                pluginMetas = metas,
                pluginWidgets = widgetMap,
            )
            isRefreshing = false
        }
    }

    LaunchedEffect(Unit) {
        if (repository.cachedDashboard == null) {
            loadDashboard()
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
            if (isAdmin) {
                ExpressiveHeaderActionButton(
                    icon = Icons.Outlined.Bolt,
                    contentDescription = "捷径与诊断",
                    onClick = { showShortcutsSheet = true },
                )
            }
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
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 16.dp,
                    bottom = bottomOverlayInset + 28.dp,
                ),
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

private data class NetTargetPreset(val name: String, val url: String)

private fun resolveModuleLogoKind(mod: SystemModuleStatusDto): Pair<String, String>? {
    val probe = "${mod.id} ${mod.name} ${mod.moduleType} ${mod.subType}".lowercase()
    return when {
        listOf("themoviedb", "tmdb", "douban", "豆瓣", "bangumi", "musicbrainz").any { probe.contains(it) } ->
            "datasource" to probe
        listOf("qbittorrent", "transmission", "rtorrent", "downloader").any { probe.contains(it) } ->
            "downloader" to probe
        listOf("emby", "jellyfin", "plex", "trimemedia", "飞牛", "ugreen", "绿联", "zspace", "极空间", "mediaserver").any { probe.contains(it) } ->
            "mediaserver" to probe
        listOf("wechat", "微信", "telegram", "feishu", "飞书", "slack", "discord", "dingtalk", "钉钉", "vocechat", "synology", "clawbot", "qq", "webpush").any { probe.contains(it) } ->
            "notification" to probe
        listOf("u115", "115", "alipan", "阿里云", "rclone", "smb", "storage", "本地").any { probe.contains(it) } ->
            "storage" to probe
        else -> null
    }
}

/**
 * 捷径与系统诊断中心页面（统一采用 `ExpressiveTintedScaffold` + `ExpressivePillTabRow`）：
 * 全量接入 MoviePilot V3 真实后端接口：
 * - `健康检查`：`GET /api/v1/module/modulelist` + `GET /api/v1/module/moduletest/{id}`；
 * - `名称识别`：`GET /api/v1/media/recognize?title=...`（支持副标题、一键执行与跳转影视详情）；
 * - `网络测试`：`GET /api/v1/system/nettest`（内置常用目标 + 自定义 URL + 代理开关）；
 * - `实时日志`：`GET /api/v1/system/logging`（支持日志级别胶囊过滤、关键字检索与手动刷新）；
 * - `定时服务`：`GET /api/v1/dashboard/schedule` + `/api/v1/system/runscheduler`；
 * - `词表`：5 类识别/屏蔽/剧集规则词表读取与保存。
 */
@Composable
fun ShortcutsDiagnosticsScreen(
    repository: MoviePilotRepository,
    initialTab: String = "词表",
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit = {},
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val scope = rememberCoroutineScope()

    val validTools = remember { listOf("健康检查", "名称识别", "网络测试", "实时日志", "定时服务", "词表") }
    var activeTool by remember(initialTab) {
        mutableStateOf(if (initialTab in validTools) initialTab else "健康检查")
    }
    var services by remember { mutableStateOf<List<ScheduledServiceDto>>(emptyList()) }
    var liveLogs by remember { mutableStateOf<List<String>>(emptyList()) }
    var logLevelFilter by remember { mutableStateOf("全部") }
    var logKeyword by remember { mutableStateOf("") }
    var isRefreshingLogs by remember { mutableStateOf(false) }

    // 健康检查真实状态
    var systemModules by remember { mutableStateOf<List<SystemModuleStatusDto>>(emptyList()) }
    var isLoadingModules by remember { mutableStateOf(false) }
    var isTestingAllModules by remember { mutableStateOf(false) }
    val testingModuleIds = remember { mutableStateMapOf<String, Boolean>() }

    // 名称识别真实状态
    var recognizeTitle by remember { mutableStateOf("") }
    var recognizeSubtitle by remember { mutableStateOf("") }
    var isRecognizing by remember { mutableStateOf(false) }
    var recognizeResult by remember { mutableStateOf<RecognizeResultDto?>(null) }
    var recognizeError by remember { mutableStateOf<String?>(null) }

    // 网络测试真实状态
    val netPresets = remember {
        listOf(
            NetTargetPreset("TheMovieDB API", "https://api.themoviedb.org/3/configuration"),
            NetTargetPreset("TheMovieDB 网站", "https://www.themoviedb.org"),
            NetTargetPreset("TMDB 图片节点", "https://image.tmdb.org"),
            NetTargetPreset("GitHub API", "https://api.github.com"),
            NetTargetPreset("GitHub 主站", "https://github.com"),
            NetTargetPreset("Telegram API", "https://api.telegram.org"),
        )
    }
    var netUseProxy by remember { mutableStateOf(true) }
    var customNetUrl by remember { mutableStateOf("") }
    var isTestingAllNet by remember { mutableStateOf(false) }
    val testingNetUrls = remember { mutableStateMapOf<String, Boolean>() }
    val netResults = remember { mutableStateMapOf<String, NetTestResultDto>() }

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

    suspend fun testSingleModule(moduleId: String) {
        testingModuleIds[moduleId] = true
        val (ok, msg) = repository.testSystemModule(moduleId)
        systemModules = systemModules.map { m ->
            if (m.id == moduleId) m.copy(ok = ok, message = msg) else m
        }
        testingModuleIds.remove(moduleId)
    }

    LaunchedEffect(activeTool) {
        when (activeTool) {
            "健康检查" -> if (systemModules.isEmpty()) {
                isLoadingModules = true
                systemModules = repository.fetchSystemModules()
                isLoadingModules = false
            }
            "定时服务" -> services = repository.fetchScheduledServices()
            "实时日志" -> {
                isRefreshingLogs = true
                liveLogs = repository.fetchSystemLogs(150)
                isRefreshingLogs = false
            }
        }
    }
    LaunchedEffect(activeWordTab, activeTool) {
        if (activeTool == "词表") {
            val list = repository.fetchCustomWordList(currentWordMeta.key)
            wordEditorText = list.joinToString("\n")
        }
    }

    val filteredLogs = remember(liveLogs, logLevelFilter, logKeyword) {
        liveLogs.filter { line ->
            val levelOk = when (logLevelFilter) {
                "ERROR" -> line.contains("ERROR", ignoreCase = true) || line.contains("CRITICAL", ignoreCase = true)
                "WARNING" -> line.contains("WARN", ignoreCase = true)
                "INFO" -> line.contains("INFO", ignoreCase = true)
                "DEBUG" -> line.contains("DEBUG", ignoreCase = true)
                else -> true
            }
            val kwOk = logKeyword.isBlank() || line.contains(logKeyword.trim(), ignoreCase = true)
            levelOk && kwOk
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
        actions = when (activeTool) {
            "词表" -> {
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
            }
            "健康检查" -> {
                {
                    Surface(
                        onClick = {
                            if (!isTestingAllModules && systemModules.isNotEmpty()) {
                                scope.launch {
                                    isTestingAllModules = true
                                    systemModules.forEach { mod -> testSingleModule(mod.id) }
                                    isTestingAllModules = false
                                }
                            }
                        },
                        shape = CircleShape,
                        color = colors.accent,
                        contentColor = colors.primaryButtonFg,
                    ) {
                        Text(
                            if (isTestingAllModules) "检测中…" else "全部自检",
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                        )
                    }
                }
            }
            "实时日志" -> {
                {
                    ExpressiveHeaderActionButton(
                        icon = Icons.Rounded.Refresh,
                        contentDescription = "刷新日志",
                        onClick = {
                            scope.launch {
                                isRefreshingLogs = true
                                liveLogs = repository.fetchSystemLogs(150)
                                isRefreshingLogs = false
                            }
                        },
                    )
                }
            }
            else -> null
        },
        headerExtra = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val toolIdx = validTools.indexOf(activeTool).coerceAtLeast(0)
                ExpressivePillTabRow(
                    tabs = validTools,
                    selectedIndex = toolIdx,
                    onSelect = { idx ->
                        activeTool = validTools[idx]
                        saveMsg = null
                    },
                    scrollable = true,
                    onTintedHeader = true,
                )
                if (activeTool == "词表") {
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
            }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize().imePadding()) {
            saveMsg?.let {
                Text(it, color = colors.success, fontSize = 12.5.sp, modifier = Modifier.padding(horizontal = margin, vertical = 8.dp))
            }

            LazyColumn(
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 14.dp,
                    bottom = bottomOverlayInset + 28.dp,
                ),
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
                        if (services.isEmpty()) {
                            item {
                                CinematicPanel(padding = 20.dp) {
                                    Text("暂无已注册的后台定时服务", color = colors.textSecondary, fontSize = 13.5.sp)
                                }
                            }
                        } else {
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
                    }

                    "健康检查" -> {
                        if (isLoadingModules && systemModules.isEmpty()) {
                            item {
                                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 36.dp), contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator(color = colors.accent)
                                }
                            }
                        } else if (systemModules.isEmpty()) {
                            item {
                                CinematicPanel(padding = 20.dp) {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text("未获取到系统模块列表", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                        Text("请检查当前账号是否具备管理员权限，或点击下方重新拉取。", color = colors.textSecondary, fontSize = 13.sp)
                                        NativeAdaptivePill(
                                            title = "重新加载模块",
                                            selected = true,
                                            icon = Icons.Rounded.Refresh,
                                            onClick = {
                                                scope.launch {
                                                    isLoadingModules = true
                                                    systemModules = repository.fetchSystemModules()
                                                    isLoadingModules = false
                                                }
                                            },
                                        )
                                    }
                                }
                            }
                        } else {
                            item(key = "health_summary_header") {
                                val passCount = systemModules.count { it.ok == true }
                                val failCount = systemModules.count { it.ok == false }
                                CinematicPanel(padding = 14.dp, showsShadow = false) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                            Text("共 ${systemModules.size} 个系统组件", color = colors.textPrimary, fontSize = 14.5.sp, fontWeight = FontWeight.Bold)
                                            Text("点击右上角「全部自检」或单项「检测」调用服务端 moduletest", color = colors.textMuted, fontSize = 12.sp)
                                        }
                                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            if (passCount > 0) NativeAdaptiveBadge("通过 $passCount", tint = colors.success)
                                            if (failCount > 0) NativeAdaptiveBadge("异常 $failCount", tint = colors.danger)
                                        }
                                    }
                                }
                            }
                            items(systemModules, key = { it.id }) { mod ->
                                val isTesting = testingModuleIds[mod.id] == true
                                val logoSpec = remember(mod.id, mod.name, mod.moduleType, mod.subType) { resolveModuleLogoKind(mod) }
                                val badgeTint = when (mod.ok) {
                                    true -> colors.success
                                    false -> colors.danger
                                    null -> colors.textMuted
                                }
                                val badgeLabel = when {
                                    isTesting -> "检测中…"
                                    mod.ok == true -> "正常"
                                    mod.ok == false -> "异常"
                                    else -> "待检测"
                                }
                                CinematicPanel(padding = 14.dp) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        if (logoSpec != null) {
                                            NativeEntityLogo(
                                                kind = logoSpec.first,
                                                value = logoSpec.second,
                                                size = 38.dp,
                                                cornerRadius = 10.dp,
                                            )
                                        } else {
                                            Box(
                                                modifier = Modifier
                                                    .size(38.dp)
                                                    .clip(RoundedCornerShape(10.dp))
                                                    .background(badgeTint.copy(alpha = 0.16f)),
                                                contentAlignment = Alignment.Center,
                                            ) {
                                                Icon(
                                                    imageVector = if (mod.ok == false) Icons.Rounded.ErrorOutline else Icons.Rounded.Shield,
                                                    contentDescription = null,
                                                    tint = badgeTint,
                                                    modifier = Modifier.size(20.dp),
                                                )
                                            }
                                        }
                                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                                Text(mod.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                                NativeAdaptiveBadge(badgeLabel, tint = badgeTint)
                                            }
                                            val metaLine = listOf(mod.moduleType, mod.subType).filter { it.isNotBlank() }.joinToString(" · ")
                                            if (metaLine.isNotBlank()) {
                                                Text(metaLine, color = colors.textMuted, fontSize = 11.5.sp)
                                            }
                                            if (mod.message.isNotBlank() && mod.message != "待检测") {
                                                Text(
                                                    text = mod.message,
                                                    color = if (mod.ok == false) colors.danger else colors.textSecondary,
                                                    fontSize = 12.sp,
                                                )
                                            }
                                        }
                                        NativeAdaptivePill(
                                            title = if (isTesting) "…" else "检测",
                                            selected = false,
                                            onClick = {
                                                if (!isTesting) {
                                                    scope.launch { testSingleModule(mod.id) }
                                                }
                                            },
                                        )
                                    }
                                }
                            }
                        }
                    }

                    "名称识别" -> {
                        item(key = "recognize_input_card") {
                            CinematicPanel(padding = 16.dp) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text("媒体名称与种子元数据识别", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                    Text("调用服务端 /api/v1/media/recognize 实时验证识别词、剧集季集号与 TMDB 匹配结果。", color = colors.textSecondary, fontSize = 12.5.sp)
                                    OutlinedTextField(
                                        value = recognizeTitle,
                                        onValueChange = { recognizeTitle = it },
                                        label = { Text("输入待识别种子标题或文件名") },
                                        placeholder = { Text("例如：Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.Atmos") },
                                        colors = fieldColors,
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    OutlinedTextField(
                                        value = recognizeSubtitle,
                                        onValueChange = { recognizeSubtitle = it },
                                        label = { Text("副标题 / 描述（可选）") },
                                        placeholder = { Text("例如：第1-12集 全集 简繁字幕") },
                                        singleLine = true,
                                        colors = fieldColors,
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Surface(
                                            onClick = {
                                                val target = recognizeTitle.trim()
                                                if (target.isBlank()) {
                                                    recognizeError = "请输入待识别的种子标题或文件名"
                                                    return@Surface
                                                }
                                                scope.launch {
                                                    isRecognizing = true
                                                    recognizeError = null
                                                    val res = repository.recognizeMediaTitle(target, recognizeSubtitle)
                                                    isRecognizing = false
                                                    if (res == null || (res.recognizedTitle.isBlank() && res.cnName.isBlank() && res.enName.isBlank() && res.tmdbId == null)) {
                                                        recognizeResult = res
                                                        recognizeError = "未能匹配到明确的影视元数据，请检查标题或自定义识别词"
                                                    } else {
                                                        recognizeResult = res
                                                    }
                                                }
                                            },
                                            shape = CircleShape,
                                            color = colors.accent,
                                            contentColor = colors.primaryButtonFg,
                                        ) {
                                            Row(
                                                modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                            ) {
                                                if (isRecognizing) {
                                                    CircularProgressIndicator(
                                                        color = colors.primaryButtonFg,
                                                        strokeWidth = 2.dp,
                                                        modifier = Modifier.size(15.dp),
                                                    )
                                                } else {
                                                    Icon(Icons.Rounded.Search, contentDescription = null, modifier = Modifier.size(17.dp))
                                                }
                                                Text(if (isRecognizing) "正在识别…" else "开始识别", fontSize = 14.sp, fontWeight = FontWeight.Bold)
                                            }
                                        }
                                        if (recognizeTitle.isNotBlank() || recognizeResult != null) {
                                            NativeAdaptivePill(
                                                title = "清空",
                                                selected = false,
                                                onClick = {
                                                    recognizeTitle = ""
                                                    recognizeSubtitle = ""
                                                    recognizeResult = null
                                                    recognizeError = null
                                                },
                                            )
                                        }
                                    }
                                    recognizeError?.let { err ->
                                        Text(err, color = colors.warning, fontSize = 12.5.sp)
                                    }
                                }
                            }
                        }

                        recognizeResult?.let { res ->
                            item(key = "recognize_result_card") {
                                CinematicPanel(padding = 16.dp) {
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
                                            if (!res.posterPath.isNullOrBlank()) {
                                                AsyncImage(
                                                    model = res.posterPath,
                                                    contentDescription = res.recognizedTitle,
                                                    contentScale = ContentScale.Crop,
                                                    modifier = Modifier
                                                        .width(84.dp)
                                                        .height(122.dp)
                                                        .clip(RoundedCornerShape(12.dp))
                                                        .background(colors.chipFill),
                                                )
                                            }
                                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                                val displayTitle = res.recognizedTitle.ifBlank { res.cnName.ifBlank { res.enName.ifBlank { res.rawTitle } } }
                                                Text(
                                                    text = buildString {
                                                        append(displayTitle)
                                                        if (res.year.isNotBlank()) append(" (${res.year})")
                                                    },
                                                    color = colors.textPrimary,
                                                    fontSize = 17.sp,
                                                    fontWeight = FontWeight.Bold,
                                                )
                                                if (res.enName.isNotBlank() && res.enName != displayTitle) {
                                                    Text(res.enName, color = colors.textSecondary, fontSize = 12.5.sp)
                                                }
                                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                                    if (res.type.isNotBlank()) NativeAdaptiveBadge(res.type, tint = colors.brand)
                                                    if (res.category.isNotBlank()) NativeAdaptiveBadge(res.category, tint = colors.info)
                                                    res.tmdbId?.let { id ->
                                                        NativeAdaptiveBadge("TMDB #$id", tint = colors.success)
                                                    }
                                                }
                                                val specs = listOf(
                                                    res.seasonEpisode,
                                                    res.resourcePix,
                                                    res.resourceType,
                                                    res.videoEncode,
                                                    res.audioEncode,
                                                    res.resourceTeam,
                                                ).filter { it.isNotBlank() }
                                                if (specs.isNotEmpty()) {
                                                    Text(
                                                        text = specs.joinToString(" · "),
                                                        color = colors.accent,
                                                        fontSize = 12.5.sp,
                                                        fontWeight = FontWeight.SemiBold,
                                                    )
                                                }
                                            }
                                        }
                                        if (res.overview.isNotBlank()) {
                                            Text(res.overview, color = colors.textSecondary, fontSize = 12.5.sp, maxLines = 4)
                                        }
                                        if (res.tmdbId != null) {
                                            Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                                                NativeAdaptivePill(
                                                    title = "打开影视详情",
                                                    selected = true,
                                                    onClick = { onOpenMedia(res.toMediaCardItem()) },
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    "网络测试" -> {
                        item(key = "nettest_controls") {
                            CinematicPanel(padding = 16.dp) {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text("服务端网络连通测速", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                            Text("由 MoviePilot 后端发起真实 HTTP 连通与耗时探测", color = colors.textSecondary, fontSize = 12.sp)
                                        }
                                        Surface(
                                            onClick = {
                                                if (!isTestingAllNet) {
                                                    scope.launch {
                                                        isTestingAllNet = true
                                                        netPresets.forEach { target ->
                                                            testingNetUrls[target.url] = true
                                                            netResults[target.url] = repository.runNetworkTest(target.url, proxy = netUseProxy, name = target.name)
                                                            testingNetUrls.remove(target.url)
                                                        }
                                                        isTestingAllNet = false
                                                    }
                                                }
                                            },
                                            shape = CircleShape,
                                            color = colors.accent,
                                            contentColor = colors.primaryButtonFg,
                                        ) {
                                            Row(
                                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(5.dp),
                                            ) {
                                                Icon(Icons.Rounded.Speed, contentDescription = null, modifier = Modifier.size(16.dp))
                                                Text(if (isTestingAllNet) "测速中…" else "全部测速", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                                            }
                                        }
                                    }
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Text("经由系统代理请求 (proxy)", color = colors.textPrimary, fontSize = 14.sp)
                                        Switch(
                                            checked = netUseProxy,
                                            onCheckedChange = { netUseProxy = it },
                                            colors = SwitchDefaults.colors(
                                                checkedTrackColor = colors.accent,
                                                checkedThumbColor = colors.primaryButtonFg,
                                            ),
                                        )
                                    }
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        OutlinedTextField(
                                            value = customNetUrl,
                                            onValueChange = { customNetUrl = it },
                                            label = { Text("自定义测试 URL") },
                                            placeholder = { Text("https://...") },
                                            singleLine = true,
                                            colors = fieldColors,
                                            modifier = Modifier.weight(1f),
                                        )
                                        NativeAdaptivePill(
                                            title = if (testingNetUrls[customNetUrl.trim()] == true) "…" else "测试",
                                            selected = true,
                                            onClick = {
                                                val raw = customNetUrl.trim()
                                                if (raw.isNotBlank()) {
                                                    val normalized = if (raw.startsWith("http://") || raw.startsWith("https://")) raw else "https://$raw"
                                                    scope.launch {
                                                        testingNetUrls[normalized] = true
                                                        netResults[normalized] = repository.runNetworkTest(normalized, proxy = netUseProxy, name = "自定义地址")
                                                        testingNetUrls.remove(normalized)
                                                    }
                                                }
                                            },
                                        )
                                    }
                                }
                            }
                        }

                        val customUrlNormalized = customNetUrl.trim().let { raw ->
                            if (raw.isBlank()) "" else if (raw.startsWith("http://") || raw.startsWith("https://")) raw else "https://$raw"
                        }
                        if (customUrlNormalized.isNotBlank() && netResults.containsKey(customUrlNormalized)) {
                            val customRes = netResults[customUrlNormalized]!!
                            item(key = "nettest_custom_result") {
                                NetTestResultCard(
                                    title = "自定义地址",
                                    url = customRes.url,
                                    result = customRes,
                                    isTesting = testingNetUrls[customUrlNormalized] == true,
                                    onRetest = {
                                        scope.launch {
                                            testingNetUrls[customUrlNormalized] = true
                                            netResults[customUrlNormalized] = repository.runNetworkTest(customUrlNormalized, proxy = netUseProxy, name = "自定义地址")
                                            testingNetUrls.remove(customUrlNormalized)
                                        }
                                    },
                                )
                            }
                        }

                        items(netPresets, key = { it.url }) { preset ->
                            NetTestResultCard(
                                title = preset.name,
                                url = preset.url,
                                result = netResults[preset.url],
                                isTesting = testingNetUrls[preset.url] == true,
                                onRetest = {
                                    scope.launch {
                                        testingNetUrls[preset.url] = true
                                        netResults[preset.url] = repository.runNetworkTest(preset.url, proxy = netUseProxy, name = preset.name)
                                        testingNetUrls.remove(preset.url)
                                    }
                                },
                            )
                        }
                    }

                    else -> {
                        item(key = "live_log_filter_bar") {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    val levels = listOf("全部", "INFO", "WARNING", "ERROR", "DEBUG")
                                    items(levels) { lv ->
                                        NativeAdaptivePill(
                                            title = lv,
                                            selected = logLevelFilter == lv,
                                            onClick = { logLevelFilter = lv },
                                        )
                                    }
                                }
                                OutlinedTextField(
                                    value = logKeyword,
                                    onValueChange = { logKeyword = it },
                                    placeholder = { Text("过滤日志关键字（模块名 / 异常信息）", color = colors.textMuted) },
                                    singleLine = true,
                                    colors = fieldColors,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                        }
                        if (isRefreshingLogs && liveLogs.isEmpty()) {
                            item {
                                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 32.dp), contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator(color = colors.accent)
                                }
                            }
                        } else if (filteredLogs.isEmpty()) {
                            item {
                                CinematicPanel(padding = 18.dp, showsShadow = false) {
                                    Text(
                                        text = if (liveLogs.isEmpty()) "暂无服务端实时日志输出" else "当前筛选条件下无匹配日志",
                                        color = colors.textSecondary,
                                        fontSize = 13.sp,
                                    )
                                }
                            }
                        } else {
                            itemsIndexed(filteredLogs) { idx, line ->
                                val tint = when {
                                    line.contains("ERROR", true) || line.contains("CRITICAL", true) -> colors.danger
                                    line.contains("WARN", true) -> colors.warning
                                    line.contains("DEBUG", true) -> colors.textMuted
                                    else -> colors.textSecondary
                                }
                                CinematicPanel(padding = 10.dp, showsShadow = false) {
                                    Text(
                                        text = line,
                                        color = tint,
                                        fontSize = 11.sp,
                                        fontFamily = FontFamily.Monospace,
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

@Composable
private fun NetTestResultCard(
    title: String,
    url: String,
    result: NetTestResultDto?,
    isTesting: Boolean,
    onRetest: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val statusTint = when {
        isTesting -> colors.info
        result == null -> colors.textMuted
        !result.ok -> colors.danger
        (result.latencyMs ?: 0L) > 1500L -> colors.warning
        else -> colors.success
    }
    val statusText = when {
        isTesting -> "测速中…"
        result == null -> "未测速"
        result.ok -> result.latencyMs?.let { "${it} ms" } ?: "连通"
        else -> "不可达"
    }
    CinematicPanel(padding = 14.dp) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(statusTint.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (result?.ok == true) Icons.Rounded.CheckCircle else Icons.Rounded.Language,
                    contentDescription = null,
                    tint = statusTint,
                    modifier = Modifier.size(19.dp),
                )
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(title, color = colors.textPrimary, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold)
                    NativeAdaptiveBadge(statusText, tint = statusTint)
                    if (result?.proxy == true) {
                        NativeAdaptiveBadge("代理", tint = colors.info)
                    }
                }
                Text(url, color = colors.textMuted, fontSize = 11.5.sp, maxLines = 1)
                if (result != null && result.message.isNotBlank()) {
                    Text(
                        text = result.message,
                        color = if (result.ok) colors.textSecondary else colors.danger,
                        fontSize = 12.sp,
                    )
                }
            }
            NativeAdaptivePill(
                title = if (isTesting) "…" else "测速",
                selected = false,
                onClick = { if (!isTesting) onRetest() },
            )
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
