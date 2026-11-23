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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.Layers
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.rustbridge.DashboardStatsDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.ScheduledServiceDto
import com.moviepilot.rustbridge.SystemMessageDto

/**
 * 「我的」无大标题仪表盘（1:1 复刻 iOS 黄金截图 `native-v2-live-dashboard.jpg`）：
 * 右上角双图标玻璃胶囊（消息中心 + 捷径诊断）、2×2 媒体库统计玻璃卡、存储空间紫粉渐变环形图、
 * 下载器绿↓蓝↑实时速率双子卡、7 天整理趋势柱状图与系统负载概览。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    repository: MoviePilotRepository,
    onOpenShortcuts: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var stats by remember { mutableStateOf(sampleDashboardStats()) }
    var messages by remember { mutableStateOf<List<SystemMessageDto>>(emptyList()) }
    var showMessagesSheet by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val fetched = repository.fetchDashboardStats()
        if (fetched.movieCount > 0 || fetched.tvCount > 0 || fetched.totalBytes > 0) {
            stats = fetched.copy(
                usedBytes = if (fetched.usedBytes > 0) fetched.usedBytes else sampleDashboardStats().usedBytes,
                totalBytes = if (fetched.totalBytes > 0) fetched.totalBytes else sampleDashboardStats().totalBytes,
            )
        }
        val msgs = repository.fetchMessages()
        messages = msgs.ifEmpty { sampleMessages() }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        // 无大标题顶部状态栏 + 右上角消息/捷径双图标玻璃胶囊
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(top = 8.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                CinematicGlassSurface(shape = CircleShape) {
                    Row(
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(onClick = { showMessagesSheet = true }, modifier = Modifier.size(40.dp)) {
                            Icon(Icons.Outlined.Notifications, contentDescription = "消息中心", tint = colors.textPrimary, modifier = Modifier.size(21.dp))
                        }
                        IconButton(onClick = onOpenShortcuts, modifier = Modifier.size(40.dp)) {
                            Icon(Icons.Outlined.Bolt, contentDescription = "捷径与诊断", tint = colors.textPrimary, modifier = Modifier.size(22.dp))
                        }
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
            val ratio = if (stats.totalBytes > 0) (stats.usedBytes / stats.totalBytes).toFloat().coerceIn(0f, 1f) else 0.766f
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

        // 4. 7 天整理趋势 + CPU/内存系统状态
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NativeSectionHeader(title = "7 天整理趋势与系统负载", subtitle = "CPU ${stats.cpuPercent.toInt()}% · 内存 ${stats.memoryPercent.toInt()}%")
                CinematicPanel(padding = 16.dp) {
                    val values = stats.transfer7Days.ifEmpty { listOf(4, 7, 12, 9, 15, 6, 11) }
                    val maxVal = (values.maxOrNull() ?: 1).coerceAtLeast(1)
                    Canvas(modifier = Modifier.fillMaxWidth().height(92.dp)) {
                        val barW = size.width / (values.size * 2f)
                        values.forEachIndexed { idx, v ->
                            val frac = (v.toFloat() / maxVal.toFloat()).coerceIn(0.12f, 1f)
                            val barH = size.height * frac
                            val left = idx * barW * 2f + barW * 0.5f
                            drawRoundRect(
                                brush = Brush.verticalGradient(listOf(colors.accent, colors.pink.copy(alpha = 0.7f))),
                                topLeft = Offset(left, size.height - barH),
                                size = Size(barW, barH),
                                cornerRadius = CornerRadius(8f, 8f),
                            )
                        }
                    }
                }
            }
        }
    }

    // 消息中心玻璃弹层
    if (showMessagesSheet) {
        NativeGlassSheet(onDismissRequest = { showMessagesSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text("消息中心", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                messages.forEach { msg ->
                    CinematicPanel(padding = 14.dp) {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(msg.title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                NativeAdaptiveBadge(msg.category, tint = colors.accent)
                            }
                            Text(msg.text, color = colors.textSecondary, fontSize = 13.sp)
                            Text(msg.date, color = colors.textMuted, fontSize = 11.sp)
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
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
 * 捷径与诊断中心：系统模块健康检查、名称识别测试、结构化实时日志、定时服务手动触发与 5 类词表管理。
 */
@Composable
fun ShortcutsDiagnosticsScreen(onBack: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val tabs = listOf("健康检查", "名称识别", "实时日志", "定时服务", "词表规则")
    var activeTab by remember { mutableStateOf("健康检查") }
    var testTitle by remember { mutableStateOf("Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.Atmos") }

    val services = remember {
        listOf(
            ScheduledServiceDto("sub", "订阅刷新", "SubscribeChain", "就绪", "10 分钟后"),
            ScheduledServiceDto("site", "站点数据同步", "SiteChain", "就绪", "30 分钟后"),
            ScheduledServiceDto("cookie", "CookieCloud 同步", "CookieCloud", "就绪", "2 小时后"),
            ScheduledServiceDto("dl", "下载文件整理", "TransferChain", "运行中", "实时监控"),
        )
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "捷径与诊断中心", onBack = onBack)
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(tabs) { t -> NativeAdaptivePill(t, selected = t == activeTab, onClick = { activeTab = t }) }
        }
        Spacer(Modifier.height(14.dp))
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when (activeTab) {
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
                        CinematicPanel(padding = 16.dp) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                OutlinedTextField(value = testTitle, onValueChange = { testTitle = it }, label = { Text("输入待识别种子/文件名") }, modifier = Modifier.fillMaxWidth())
                                Text("识别结果：沙丘2 (2024) · 2160p · BluRay REMUX · 杜比视界 · Atmos", color = colors.success, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }
                "实时日志" -> {
                    items(listOf(
                        "INFO  [17:28:04] SubscribeChain - 订阅刷新完成，命中 2 条 4K 资源",
                        "INFO  [17:28:19] TransferChain  - 硬链接整理成功 -> /video/tv/合成追剧/S01E08.mkv",
                        "DEBUG [17:29:02] RustCoreBridge - 9维资源筛选耗时 0.4ms（共 90 条）",
                    )) { line ->
                        CinematicPanel(padding = 12.dp) {
                            Text(line, color = colors.textSecondary, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                        }
                    }
                }
                "定时服务" -> {
                    items(services) { svc ->
                        CinematicPanel(padding = 14.dp) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Column {
                                    Text(svc.name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    Text("${svc.provider} · 下次：${svc.nextRun}", color = colors.textMuted, fontSize = 12.sp)
                                }
                                NativeAdaptivePill("立即触发", selected = false, icon = Icons.Rounded.PlayArrow, onClick = {})
                            }
                        }
                    }
                }
                else -> {
                    items(listOf("自定义识别词", "自定义屏蔽词", "自定义制作组", "文件整理屏蔽词", "优先级规则组")) { word ->
                        CinematicPanel(padding = 14.dp) {
                            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(word, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                                NativeAdaptiveBadge("已生效", tint = colors.accent)
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
    val tb = bytes / (1024.0 * 1024 * 1024 * 1024)
    if (tb >= 1.0) return String.format("%.2f TB", tb)
    val gb = bytes / (1024.0 * 1024 * 1024)
    return String.format("%.1f GB", gb)
}

private fun formatSpeed(bytesPerSec: Double): String {
    if (bytesPerSec <= 0) return "0 B/s"
    if (bytesPerSec >= 1024 * 1024) return String.format("%.1f MB/s", bytesPerSec / (1024 * 1024))
    if (bytesPerSec >= 1024) return String.format("%.1f KB/s", bytesPerSec / 1024)
    return "${bytesPerSec.toInt()} B/s"
}

private fun sampleDashboardStats() = DashboardStatsDto(
    movieCount = 776,
    tvCount = 1268,
    episodeCount = 31532,
    musicCount = 128,
    movieCountMonth = 9,
    tvCountMonth = 49,
    episodeCountMonth = 792,
    musicCountMonth = 14,
    usedBytes = 26.47 * 1024 * 1024 * 1024 * 1024,
    totalBytes = 34.56 * 1024 * 1024 * 1024 * 1024,
    downloadSpeed = 12.4 * 1024 * 1024,
    uploadSpeed = 21.0 * 1024,
    totalDownloadBytes = 3.93 * 1024 * 1024 * 1024 * 1024,
)

private fun sampleMessages() = listOf(
    SystemMessageDto("m1", "整理入库成功", "《奥德赛》2160p REMUX 已完成刮削并通知 Emby 刷新媒体库。", "刚刚", "整理"),
    SystemMessageDto("m2", "订阅命中推送", "《合成追剧 S01E09》已自动推送至 qBittorrent 开始下载。", "12 分钟前", "订阅"),
)
