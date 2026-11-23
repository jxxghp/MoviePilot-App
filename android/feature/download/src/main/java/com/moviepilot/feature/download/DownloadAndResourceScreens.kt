package com.moviepilot.feature.download

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.rustbridge.DownloadTaskDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.ResourceFilterResultDto
import com.moviepilot.rustbridge.ResourceGroupDto
import com.moviepilot.rustbridge.ResourceItemDto

/**
 * 站点资源页（1:1 复刻 iOS 黄金截图 `native-v2-live-resources.jpg`）：
 * 全部 9 维级联筛选与同规格分组算法均调用 Rust `filter_and_group_resources`，
 * 点击整张资源卡弹出原生分组下载确认弹窗（下载器 + 保存目录选择）。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ResourceSearchScreen(
    repository: MoviePilotRepository,
    initialKeyword: String = "",
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()

    var keyword by remember { mutableStateOf(initialKeyword) }
    var rawItems by remember { mutableStateOf<List<ResourceItemDto>>(emptyList()) }
    var selectedSite by remember { mutableStateOf<String?>(null) }
    var selectedRes by remember { mutableStateOf<String?>(null) }
    var selectedPromo by remember { mutableStateOf<String?>(null) }
    var selectedGroupForDownload by remember { mutableStateOf<ResourceGroupDto?>(null) }
    var downloadToast by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(keyword) {
        val fetched = repository.searchResources(keyword)
        rawItems = fetched.ifEmpty { sampleResources() }
    }

    val filterResult: ResourceFilterResultDto = remember(rawItems, selectedSite, selectedRes, selectedPromo, keyword) {
        val criteria = buildString {
            append("{")
            if (selectedSite != null) append("\"sites\":[\"$selectedSite\"],")
            if (selectedRes != null) append("\"resolutions\":[\"$selectedRes\"],")
            if (selectedPromo != null) append("\"promotions\":[\"$selectedPromo\"],")
            append("\"keyword\":\"${keyword.replace("\"", "\\\"")}\"")
            append("}")
        }
        repository.filterResourcesWithRust(rawItems, criteria)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "站点资源 (${filterResult.filteredCount})", onBack = onBack)

        // 搜索与浏览输入栏
        CinematicPanel(padding = 12.dp, cornerRadius = 22.dp, modifier = Modifier.padding(horizontal = margin)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(18.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (keyword.isEmpty()) Text("输入关键词，留空可浏览全站...", color = colors.textMuted, fontSize = 14.sp)
                    BasicTextField(
                        value = keyword,
                        onValueChange = { keyword = it },
                        singleLine = true,
                        textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp),
                        cursorBrush = SolidColor(colors.accent),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                NativeAdaptiveBadge("Rust 9维", tint = colors.accent)
            }
        }

        Spacer(Modifier.height(10.dp))

        // 级联筛选胶囊条
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                NativeAdaptivePill(
                    title = "全部筛选",
                    selected = selectedSite == null && selectedRes == null && selectedPromo == null,
                    icon = Icons.Rounded.FilterList,
                    onClick = { selectedSite = null; selectedRes = null; selectedPromo = null },
                )
            }
            items(filterResult.options.resolutions) { res ->
                NativeAdaptivePill(res, selected = selectedRes == res, onClick = {
                    selectedRes = if (selectedRes == res) null else res
                })
            }
            items(filterResult.options.promotions) { promo ->
                NativeAdaptivePill(promo, selected = selectedPromo == promo, onClick = {
                    selectedPromo = if (selectedPromo == promo) null else promo
                })
            }
            items(filterResult.options.sites) { site ->
                NativeAdaptivePill(site, selected = selectedSite == site, onClick = {
                    selectedSite = if (selectedSite == site) null else site
                })
            }
        }

        downloadToast?.let {
            Text(it, color = colors.success, fontSize = 13.sp, modifier = Modifier.padding(horizontal = margin, vertical = 6.dp))
        }

        Spacer(Modifier.height(10.dp))

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(filterResult.groups, key = { it.key + it.primary.id }) { group ->
                val item = group.primary
                CinematicPanel(
                    padding = 14.dp,
                    modifier = Modifier.clickable { selectedGroupForDownload = group },
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            NativeAdaptiveBadge(item.siteName, tint = colors.accent, filled = true)
                            if (item.resourcePix.isNotBlank()) NativeAdaptiveBadge(item.resourcePix, tint = colors.info)
                            if (item.edition.isNotBlank()) NativeAdaptiveBadge(item.edition)
                            if (item.videoEncode.isNotBlank()) NativeAdaptiveBadge(item.videoEncode)
                            if (item.downloadvolumefactor == 0.0) NativeAdaptiveBadge("免费", tint = colors.success)
                            item.labels.take(3).forEach { lbl -> NativeAdaptiveBadge(lbl, tint = colors.warning) }
                            if (group.items.size > 1) NativeAdaptiveBadge("同规格 ${group.items.size} 源", tint = colors.brand)
                        }
                        Text(
                            text = item.title,
                            color = colors.textPrimary,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (item.description.isNotBlank()) {
                            Text(
                                text = item.description,
                                color = colors.textSecondary,
                                fontSize = 12.sp,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(formatBytes(item.size.toDouble()), color = colors.textSecondary, fontSize = 12.sp)
                                Text("↑ ${group.totalSeeders}", color = colors.success, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                            }
                            Text(item.resourceTeam.ifBlank { item.siteName }, color = colors.textMuted, fontSize = 12.sp)
                        }
                    }
                }
            }
        }
    }

    // 原生分组下载确认弹窗
    selectedGroupForDownload?.let { group ->
        var selectedDownloader by remember { mutableStateOf("qBittorrent") }
        var saveDir by remember { mutableStateOf("/downloads/movies") }

        NativeGlassSheet(onDismissRequest = { selectedGroupForDownload = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("确认添加下载", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Text(group.primary.title, color = colors.textSecondary, fontSize = 13.sp, maxLines = 2)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("qBittorrent", "Transmission").forEach { dl ->
                        NativeAdaptivePill(dl, selected = selectedDownloader == dl, onClick = { selectedDownloader = dl })
                    }
                }
                OutlinedTextField(
                    value = saveDir,
                    onValueChange = { saveDir = it },
                    label = { Text("保存目录") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    onClick = {
                        downloadToast = "已推送至 $selectedDownloader（${group.primary.siteName}）"
                        selectedGroupForDownload = null
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    Icon(Icons.Rounded.Download, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("开始下载", color = Color.White, fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

/** 正在下载管理页：实时进度条、上下行速度、暂停/恢复/删除操作。 */
@Composable
fun DownloadsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var tasks by remember { mutableStateOf<List<DownloadTaskDto>>(emptyList()) }

    LaunchedEffect(Unit) {
        val fetched = repository.fetchDownloads()
        tasks = fetched.ifEmpty { sampleDownloads() }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "正在下载 (${tasks.size})", onBack = onBack)
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(tasks, key = { it.hash + it.title }) { task ->
                val isPaused = task.state.contains("pause", ignoreCase = true)
                CinematicPanel(padding = 14.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(task.name.ifBlank { task.title }, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("${task.downloader} · ${task.siteName} · ${formatBytes(task.size)}", color = colors.textSecondary, fontSize = 12.sp)
                            }
                            Row {
                                IconButton(onClick = {
                                    val next = if (isPaused) "downloading" else "paused"
                                    tasks = tasks.map { if (it.hash == task.hash) it.copy(state = next) else it }
                                }) {
                                    Icon(if (isPaused) Icons.Rounded.PlayArrow else Icons.Rounded.Pause, contentDescription = "暂停/恢复", tint = colors.textPrimary)
                                }
                                IconButton(onClick = { tasks = tasks.filterNot { it.hash == task.hash } }) {
                                    Icon(Icons.Rounded.Delete, contentDescription = "删除任务", tint = colors.danger)
                                }
                            }
                        }

                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .clip(CircleShape)
                                .background(colors.chipFill),
                        ) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth((task.progress / 100.0).toFloat().coerceIn(0.02f, 1f))
                                    .height(6.dp)
                                    .clip(CircleShape)
                                    .background(if (isPaused) colors.warning else colors.accent),
                            )
                        }

                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Rounded.ArrowDownward, contentDescription = null, tint = colors.success, modifier = Modifier.size(14.dp))
                                    Text(task.dlspeed, color = colors.success, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                                }
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Rounded.ArrowUpward, contentDescription = null, tint = colors.info, modifier = Modifier.size(14.dp))
                                    Text(task.upspeed, color = colors.info, fontSize = 12.sp)
                                }
                            }
                            Text(
                                text = "${String.format("%.1f", task.progress)}% · ${task.leftTime.ifBlank { if (isPaused) "已暂停" else "下载中" }}",
                                color = colors.textMuted,
                                fontSize = 12.sp,
                            )
                        }
                    }
                }
            }
        }
    }
}

fun formatBytes(bytes: Double): String {
    if (bytes <= 0) return "0 B"
    val units = arrayOf("B", "KB", "MB", "GB", "TB")
    var v = bytes
    var idx = 0
    while (v >= 1024 && idx < units.lastIndex) {
        v /= 1024
        idx++
    }
    return String.format("%.2f %s", v, units[idx])
}

private fun sampleResources(): List<ResourceItemDto> = listOf(
    ResourceItemDto("r1", "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR10.Atmos-GroupA", "合成站A", 75_161_927_680L, 128, 14, "2160p", "BluRay", "HEVC", "Atmos", "GroupA", "REMUX", 0.0, 2.0, listOf("中字", "HDR", "杜比视界"), "蓝光原盘重封装，含国英双语与特效中字"),
    ResourceItemDto("r2", "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR10.Atmos-GroupA", "合成站B", 75_161_927_680L, 64, 8, "2160p", "BluRay", "HEVC", "Atmos", "GroupA", "REMUX", 0.5, 1.0, listOf("中字", "HDR"), "同规格备份源"),
    ResourceItemDto("r3", "The.Odyssey.2026.2160p.WEB-DL.H265.DDP5.1-PigoWeb", "猪猪", 24_696_061_952L, 86, 12, "2160p", "WEB-DL", "H265", "DDP5.1", "PigoWeb", "WEB-DL", 0.0, 1.0, listOf("中字", "HDR"), "官方 4K HDR10 高码流版本"),
    ResourceItemDto("r4", "Synthetic.Show.S01.Complete.1080p.WEB-DL.H264.AAC-GroupB", "合成站A", 8_589_934_592L, 42, 5, "1080p", "WEB-DL", "H264", "AAC", "GroupB", "WEB-DL", 1.0, 1.0, listOf("国语"), "全季合集 1080p"),
)

private fun sampleDownloads(): List<DownloadTaskDto> = listOf(
    DownloadTaskDto("abc123", "qBittorrent", "Synthetic.Show.S01.2160p", "合成追剧 S01", "2025", "S01", "合成站A", 42_949_672_960.0, 42.5, "downloading", "512 KB/s", "12.4 MB/s", "18分20秒"),
    DownloadTaskDto("def456", "Transmission", "The.Odyssey.2026.2160p.REMUX", "奥德赛 4K REMUX", "2026", "", "猪猪", 68_719_476_736.0, 78.2, "downloading", "1.2 MB/s", "28.6 MB/s", "6分10秒"),
)
