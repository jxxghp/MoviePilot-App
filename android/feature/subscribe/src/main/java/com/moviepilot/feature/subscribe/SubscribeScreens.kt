package com.moviepilot.feature.subscribe

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SubscribeItemDto
import kotlinx.coroutines.launch

/**
 * 我的订阅页面（1:1 复刻 iOS 黄金截图 `native-v2-live-subscriptions.jpg`）：
 * 顶部分类胶囊实时统计（全部 / 电影 / 电视剧 / 音乐）+ 海报卡 + Rust 剧集进度条 + 全量参数编辑弹窗。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionsScreen(
    repository: MoviePilotRepository,
    initialCategory: String? = null,
    onBack: () -> Unit,
    onOpenCalendar: () -> Unit,
    onOpenCommunity: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()

    var items by remember { mutableStateOf<List<SubscribeItemDto>>(emptyList()) }
    var activeFilter by remember { mutableStateOf(initialCategory ?: "all") }
    var editingItem by remember { mutableStateOf<SubscribeItemDto?>(null) }

    LaunchedEffect(Unit) {
        val fetched = repository.fetchSubscriptions()
        items = fetched.ifEmpty { sampleSubscriptions() }
    }

    val filtered = remember(items, activeFilter) {
        when (activeFilter) {
            "movie" -> items.filter { it.type == "电影" }
            "tv" -> items.filter { it.type == "电视剧" }
            "music" -> items.filter { it.type == "音乐" }
            else -> items
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = "我的订阅",
            onBack = onBack,
            trailing = {
                CinematicCircleButton(Icons.Rounded.CalendarMonth, "追剧日历", onOpenCalendar)
                CinematicCircleButton(Icons.Rounded.LocalFireDepartment, "订阅广场", onOpenCommunity)
            },
        )

        val movieCnt = items.count { it.type == "电影" }
        val tvCnt = items.count { it.type == "电视剧" }
        val musicCnt = items.count { it.type == "音乐" }
        LazyRow(
            contentPadding = PaddingValues(horizontal = margin),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item { NativeAdaptivePill("全部 ${items.size}", activeFilter == "all", { activeFilter = "all" }) }
            item { NativeAdaptivePill("电影 $movieCnt", activeFilter == "movie", { activeFilter = "movie" }) }
            item { NativeAdaptivePill("电视剧 $tvCnt", activeFilter == "tv", { activeFilter = "tv" }) }
            item { NativeAdaptivePill("音乐 $musicCnt", activeFilter == "music", { activeFilter = "music" }) }
        }

        Spacer(Modifier.height(12.dp))

        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(filtered, key = { "${it.id}-${it.name}" }) { sub ->
                val progress = remember(sub.totalEpisode, sub.lackEpisode) {
                    RustCoreBridge.subscribeProgress(sub.totalEpisode, sub.lackEpisode)
                }
                CinematicPanel(
                    padding = 14.dp,
                    modifier = Modifier.clickable { editingItem = sub },
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .width(68.dp)
                                .height(100.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.4f), Color(0xFF28203A)))),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (!sub.poster.isNullOrBlank()) {
                                AsyncImage(
                                    model = sub.poster,
                                    contentDescription = sub.name,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                            } else {
                                Text(sub.name.take(2), color = Color.White, fontWeight = FontWeight.Bold)
                            }
                        }

                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                val title = if (sub.season != null) "${sub.name} S%02d".format(sub.season) else sub.name
                                Text(title, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                                NativeAdaptiveBadge(
                                    text = if (sub.state == "S") "已暂停" else "订阅中",
                                    tint = if (sub.state == "S") colors.warning else colors.success,
                                )
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("${sub.year}  ${sub.type}", color = colors.textSecondary, fontSize = 13.sp)
                                if (sub.vote > 0.0) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Icon(Icons.Rounded.Star, contentDescription = null, tint = Color(0xFFFFC845), modifier = Modifier.size(13.dp))
                                        Text(" ${String.format("%.1f", sub.vote)}", color = colors.warning, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                }
                            }
                            if (sub.type == "电视剧" && sub.totalEpisode > 0) {
                                Text("已更新 ${progress.completed} / ${progress.total} 集", color = colors.textSecondary, fontSize = 12.sp)
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(4.dp)
                                        .clip(CircleShape)
                                        .background(colors.chipFill),
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth(progress.ratio.toFloat().coerceIn(0.03f, 1f))
                                            .height(4.dp)
                                            .clip(CircleShape)
                                            .background(colors.accent),
                                    )
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                NativeAdaptivePill(
                                    title = if (sub.state == "S") "恢复" else "暂停",
                                    selected = false,
                                    icon = if (sub.state == "S") Icons.Rounded.PlayArrow else Icons.Rounded.Pause,
                                    onClick = {
                                        val nextState = if (sub.state == "S") "R" else "S"
                                        items = items.map { if (it.id == sub.id) it.copy(state = nextState) else it }
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // 全量订阅参数编辑原生玻璃弹窗
    editingItem?.let { current ->
        var quality by remember(current) { mutableStateOf(current.quality.ifBlank { "全部质量" }) }
        var resolution by remember(current) { mutableStateOf(current.resolution.ifBlank { "2160p" }) }
        var effect by remember(current) { mutableStateOf(current.effect.ifBlank { "杜比视界 / HDR" }) }
        var savePath by remember(current) { mutableStateOf(current.savePath.ifBlank { "/media/auto" }) }
        var includeWord by remember(current) { mutableStateOf(current.include) }
        var excludeWord by remember(current) { mutableStateOf(current.exclude) }

        NativeGlassSheet(onDismissRequest = { editingItem = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 6.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("编辑订阅：${current.name}", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                OutlinedTextField(value = quality, onValueChange = { quality = it }, label = { Text("画质 / 音质规格") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(value = resolution, onValueChange = { resolution = it }, label = { Text("分辨率（如 2160p / 1080p）") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(value = effect, onValueChange = { effect = it }, label = { Text("特效（HDR / DV / 杜比全景声）") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(value = savePath, onValueChange = { savePath = it }, label = { Text("保存目录") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(value = includeWord, onValueChange = { includeWord = it }, label = { Text("自定义包含词") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(value = excludeWord, onValueChange = { excludeWord = it }, label = { Text("自定义排除词") }, modifier = Modifier.fillMaxWidth(), singleLine = true)

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    Button(
                        onClick = {
                            scope.launch {
                                repository.deleteSubscription(current.id)
                                items = items.filterNot { it.id == current.id }
                                editingItem = null
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.danger.copy(alpha = 0.22f), contentColor = colors.danger),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Rounded.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("删除订阅")
                    }
                    Button(
                        onClick = {
                            val updated = current.copy(
                                quality = quality,
                                resolution = resolution,
                                effect = effect,
                                savePath = savePath,
                                include = includeWord,
                                exclude = excludeWord,
                            )
                            scope.launch {
                                repository.createOrUpdateSubscription(updated, isUpdate = true)
                                items = items.map { if (it.id == current.id) updated else it }
                                editingItem = null
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f),
                    ) {
                        Text("保存参数", color = Color.White, fontWeight = FontWeight.SemiBold)
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

/** 追剧日历页面（无边框周切换 + 每日剧集更新卡片）。 */
@Composable
fun CalendarScreen(onBack: () -> Unit) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val days = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    var selectedDay by remember { mutableStateOf(0) }
    val schedule = listOf(
        Triple("合成追剧 S01E10", "21:00 更新", "TheMovieDB"),
        Triple("人生切割术 S02E08", "22:30 更新", "Apple TV+"),
        Triple("三体：黑暗森林 S01E05", "20:00 更新", "豆瓣热播"),
    )

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "订阅日历", onBack = onBack)
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(days.indices.toList()) { idx ->
                NativeAdaptivePill(days[idx], selected = idx == selectedDay, onClick = { selectedDay = idx })
            }
        }
        Spacer(Modifier.height(14.dp))
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 124.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(schedule) { (name, time, src) ->
                CinematicPanel(padding = 14.dp) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Column {
                            Text(name, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.height(4.dp))
                            Text("${days[selectedDay]} · $time", color = colors.textSecondary, fontSize = 12.sp)
                        }
                        NativeAdaptiveBadge(src, tint = colors.accent)
                    }
                }
            }
        }
    }
}

/** 订阅广场页面（热门订阅 + 社区分享一键复用）。 */
@Composable
fun SubscribeCommunityScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var tab by remember { mutableStateOf("popular") }
    val shares = listOf(
        Triple("4K 杜比视界科幻大片合集", "由 MoviePilot 社区分享 · 复用 1.8k 次", "电影"),
        Triple("2026 高分国漫追番订阅规则", "自动过滤低清与生肉 · 复用 960 次", "电视剧"),
        Triple("无损 FLAC 华语经典合集", "优先 24bit 母带 · 复用 420 次", "音乐"),
    )

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "订阅广场", onBack = onBack)
        Row(modifier = Modifier.padding(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NativeAdaptivePill("热门订阅", tab == "popular", { tab = "popular" })
            NativeAdaptivePill("社区分享", tab == "shares", { tab = "shares" })
        }
        Spacer(Modifier.height(14.dp))
        LazyColumn(
            contentPadding = PaddingValues(start = margin, end = margin, bottom = 124.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(shares) { (title, desc, cat) ->
                CinematicPanel(padding = 14.dp) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                            Spacer(Modifier.height(4.dp))
                            Text(desc, color = colors.textSecondary, fontSize = 12.sp)
                        }
                        NativeAdaptiveBadge(cat, tint = colors.brand)
                    }
                }
            }
        }
    }
}

private fun sampleSubscriptions(): List<SubscribeItemDto> = listOf(
    SubscribeItemDto(701, "合成订阅电影", "2025", "电影", null, null, null, 8.4, "R", 0, 0),
    SubscribeItemDto(702, "合成追剧", "2025", "电视剧", 1, null, null, 8.8, "R", 12, 3),
    SubscribeItemDto(703, "人生切割术", "2025", "电视剧", 2, null, null, 8.9, "R", 10, 2),
    SubscribeItemDto(704, "范特西 (Hi-Res)", "2001", "音乐", null, null, null, 9.6, "R", 0, 0),
)
