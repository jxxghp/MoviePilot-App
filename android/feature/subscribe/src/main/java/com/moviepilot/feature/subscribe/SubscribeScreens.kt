package com.moviepilot.feature.subscribe

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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.CalendarMonth
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarResult
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicGlassCapsule
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeNetworkEntityLogo
import com.moviepilot.designsystem.NativePosterCard
import com.moviepilot.rustbridge.CalendarEntryDto
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.RustCoreBridge
import com.moviepilot.rustbridge.SubscribeItemDto
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Android Material 3 我的订阅页面：
 * - `HorizontalPager` 支持左右手势在「全部 / 电影 / 电视剧 / 音乐」分类间丝滑切换 + 原生下拉刷新；
 * - 卡片配备 Android 标准尾部 `⋮` 溢出菜单；暂停/恢复订阅时触发底部非阻塞 Snackbar，支持一键「撤销」；
 * - 删除操作使用 Material 3 `AlertDialog` 确认。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SubscriptionsScreen(
    repository: MoviePilotRepository,
    initialCategory: String? = null,
    onBack: (() -> Unit)? = null,
    onOpenSearch: () -> Unit = {},
    onOpenCalendar: () -> Unit,
    onOpenCommunity: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit = {},
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val snackbar = LocalSnackbarHostState.current
    val listState = rememberLazyListState()

    val filterKeys = remember { listOf("all", "movie", "tv", "music") }
    var selectedCategory by rememberSaveable(initialCategory) {
        mutableStateOf(if (initialCategory in filterKeys) initialCategory!! else "all")
    }
    val rootPagerState = rememberPagerState(initialPage = 0, pageCount = { 2 })

    var items by remember { mutableStateOf(repository.cachedSubscriptions.orEmpty()) }
    var isRefreshing by remember { mutableStateOf(false) }
    var editingItem by remember { mutableStateOf<SubscribeItemDto?>(null) }
    var confirmDeleteItem by remember { mutableStateOf<SubscribeItemDto?>(null) }

    suspend fun loadSubs(forceRefresh: Boolean = true) {
        items = repository.fetchSubscriptions(forceRefresh = forceRefresh)
        isRefreshing = false
    }

    LaunchedEffect(Unit) {
        loadSubs(forceRefresh = items.isEmpty())
    }

    fun toggleSubWithUndo(sub: SubscribeItemDto) {
        val prevState = sub.state
        val nextState = if (prevState == "S") "R" else "S"
        scope.launch {
            repository.toggleSubscriptionState(sub.id, nextState)
            items = items.map { if (it.id == sub.id) it.copy(state = nextState) else it }
            val result = snackbar?.showSnackbar(
                message = if (nextState == "S") "已暂停订阅「${sub.name}」" else "已恢复订阅「${sub.name}」",
                actionLabel = "撤销",
                duration = SnackbarDuration.Short,
            )
            if (result == SnackbarResult.ActionPerformed) {
                repository.toggleSubscriptionState(sub.id, prevState)
                items = items.map { if (it.id == sub.id) it.copy(state = prevState) else it }
            }
        }
    }

    ExpressiveTintedScaffold(
        title = if (onBack == null) "订阅" else "我的订阅",
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Search,
                contentDescription = "全局搜索",
                onClick = onOpenSearch,
            )
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.CalendarMonth,
                contentDescription = "追剧日历",
                onClick = onOpenCalendar,
            )
        },
        headerExtra = {
            ExpressivePillTabRow(
                tabs = listOf("我的订阅 (${items.size})", "订阅广场"),
                selectedIndex = rootPagerState.currentPage,
                onSelect = { idx -> scope.launch { rootPagerState.animateScrollToPage(idx) } },
                onTintedHeader = true,
            )
        },
    ) {
        HorizontalPager(state = rootPagerState, modifier = Modifier.fillMaxSize()) { rootIdx ->
            if (rootIdx == 1) {
                SubscribeCommunityContent(
                    repository = repository,
                    onOpenMedia = onOpenMedia,
                    bottomPadding = (if (onBack == null) 120.dp else 48.dp) + bottomOverlayInset,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                val movieCnt = items.count { it.type == "电影" }
                val tvCnt = items.count { it.type == "电视剧" }
                val musicCnt = items.count { it.type == "音乐" }
                val filterChips = listOf(
                    "all" to "全部 ${items.size}",
                    "movie" to "电影 $movieCnt",
                    "tv" to "电视剧 $tvCnt",
                    "music" to "音乐 $musicCnt",
                )
                val filtered = remember(items, selectedCategory) {
                    when (selectedCategory) {
                        "movie" -> items.filter { it.type == "电影" }
                        "tv" -> items.filter { it.type == "电视剧" }
                        "music" -> items.filter { it.type == "音乐" }
                        else -> items
                    }
                }

                Column(modifier = Modifier.fillMaxSize()) {
                    LazyRow(
                        contentPadding = PaddingValues(horizontal = margin, vertical = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(filterChips) { (key, label) ->
                            NativeAdaptivePill(
                                title = label,
                                selected = selectedCategory == key,
                                onClick = { selectedCategory = key },
                            )
                        }
                    }

                    PullToRefreshBox(
                        isRefreshing = isRefreshing,
                        onRefresh = {
                            isRefreshing = true
                            scope.launch { loadSubs(forceRefresh = true) }
                        },
                        modifier = Modifier.weight(1f).fillMaxWidth(),
                    ) {
                        LazyColumn(
                            state = listState,
                            contentPadding = PaddingValues(
                                start = margin,
                                end = margin,
                                bottom = (if (onBack == null) 120.dp else 48.dp) + bottomOverlayInset,
                            ),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            items(filtered, key = { "${selectedCategory}-${it.id}-${it.name}" }) { sub ->
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
                                        .width(72.dp)
                                        .height(106.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.35f), Color(0xFF28203A)))),
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
                                        val title = if (sub.season != null && sub.type == "电视剧") {
                                            "${sub.name} S%02d".format(sub.season)
                                        } else {
                                            sub.name
                                        }
                                        Text(
                                            text = title,
                                            color = colors.textPrimary,
                                            fontSize = 16.sp,
                                            fontWeight = FontWeight.Bold,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.weight(1f),
                                        )
                                        Spacer(Modifier.width(8.dp))
                                        NativeAdaptiveBadge(
                                            text = if (sub.state == "S") "已暂停" else "订阅中",
                                            tint = if (sub.state == "S") colors.warning else colors.success,
                                        )
                                    }

                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text(
                                            text = listOfNotNull(sub.year.takeIf(String::isNotBlank), sub.type).joinToString(" · "),
                                            color = colors.textSecondary,
                                            fontSize = 13.sp,
                                        )
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

                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        NativeAdaptivePill(
                                            title = if (sub.state == "S") "恢复" else "暂停",
                                            selected = false,
                                            icon = if (sub.state == "S") Icons.Rounded.PlayArrow else Icons.Rounded.Pause,
                                            onClick = { toggleSubWithUndo(sub) },
                                        )
                                        NativeAdaptivePill(
                                            title = "编辑",
                                            selected = false,
                                            icon = Icons.Rounded.Edit,
                                            onClick = { editingItem = sub },
                                        )
                                        Spacer(Modifier.weight(1f))
                                        Box(
                                            modifier = Modifier
                                                .size(34.dp)
                                                .clip(CircleShape)
                                                .background(colors.danger.copy(alpha = if (colors.isDark) 0.16f else 0.11f))
                                                .clickable { confirmDeleteItem = sub },
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Icon(
                                                Icons.Rounded.Delete,
                                                contentDescription = "删除订阅",
                                                tint = colors.danger,
                                                modifier = Modifier.size(17.dp),
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

    // 分组订阅编辑玻璃弹窗
    editingItem?.let { current ->
        SubscribeEditorSheet(
            item = current,
            repository = repository,
            onDismiss = { editingItem = null },
            onDelete = {
                editingItem = null
                confirmDeleteItem = current
            },
            onSave = { updated ->
                scope.launch {
                    val (ok, msg) = repository.createOrUpdateSubscriptionWithMessage(updated, isUpdate = true)
                    if (ok) {
                        items = items.map { if (it.id == current.id) updated else it }
                        editingItem = null
                        snackbar?.showSnackbar("已保存「${updated.name}」订阅配置")
                    } else {
                        snackbar?.showSnackbar(msg)
                    }
                }
            },
        )
    }

    // Material 3 破坏性删除二次确认 AlertDialog
    confirmDeleteItem?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmDeleteItem = null },
            title = { Text("删除订阅「${target.name}」？") },
            text = { Text("删除后将停止自动追更该媒体，已下载到媒体库的文件不会受影响。") },
            dismissButton = {
                TextButton(onClick = { confirmDeleteItem = null }) { Text("取消") }
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDeleteItem = null
                    scope.launch {
                        repository.deleteSubscription(target.id)
                        items = items.filterNot { it.id == target.id }
                        snackbar?.showSnackbar("已删除订阅「${target.name}」")
                    }
                }) {
                    Text("确认删除", color = colors.danger)
                }
            },
        )
    }
}

/** 全量订阅编辑弹窗（1:1 对齐 iOS：基础集数 / 画质洗版 / 下载保存 / 多选站点与规则组 / 过滤识别规则）。 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun SubscribeEditorSheet(
    item: SubscribeItemDto,
    repository: MoviePilotRepository,
    onDismiss: () -> Unit,
    onDelete: () -> Unit,
    onSave: (SubscribeItemDto) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    var seasonText by remember(item) { mutableStateOf(item.season?.toString().orEmpty()) }
    var totalEpText by remember(item) { mutableStateOf(if (item.totalEpisode > 0) item.totalEpisode.toString() else "") }
    var startEpText by remember(item) { mutableStateOf(item.startEpisode?.toString().orEmpty()) }
    var episodeGroup by remember(item) { mutableStateOf(item.episodeGroup) }

    var quality by remember(item) { mutableStateOf(item.quality.ifBlank { "全部" }) }
    var resolution by remember(item) { mutableStateOf(item.resolution.ifBlank { "全部" }) }
    var effect by remember(item) { mutableStateOf(item.effect.ifBlank { "全部" }) }
    var bestVersion by remember(item) { mutableStateOf(item.bestVersion) }

    var downloader by remember(item) { mutableStateOf(item.downloader.ifBlank { "默认" }) }
    var savePath by remember(item) { mutableStateOf(item.savePath) }

    var selectedSiteIds by remember(item) { mutableStateOf(item.sites.toSet()) }
    var selectedFilterGroups by remember(item) { mutableStateOf(item.filterGroups.toSet()) }
    var showSitesPicker by remember { mutableStateOf(false) }
    var showGroupsPicker by remember { mutableStateOf(false) }
    var searchImdbId by remember(item) { mutableStateOf(item.searchImdbId) }
    var intervalHours by remember(item) { mutableIntStateOf(item.searchInterval ?: 0) }

    var keyword by remember(item) { mutableStateOf(item.keyword) }
    var includeWord by remember(item) { mutableStateOf(item.include) }
    var excludeWord by remember(item) { mutableStateOf(item.exclude) }
    var mediaCategory by remember(item) { mutableStateOf(item.mediaCategory) }
    var customWords by remember(item) { mutableStateOf(item.customWords) }

    var allSites by remember { mutableStateOf<List<com.moviepilot.rustbridge.SiteItemDto>>(emptyList()) }
    val siteIcons = remember { mutableStateMapOf<Int, String>() }
    var allRuleGroups by remember { mutableStateOf<List<String>>(emptyList()) }
    var allDownloaders by remember { mutableStateOf<List<com.moviepilot.rustbridge.ServiceConfigDto>>(emptyList()) }

    LaunchedEffect(Unit) {
        val activeSites = repository.fetchSites().filter { it.isActive }
        allSites = activeSites
        activeSites.forEach { s ->
            s.iconUrl?.takeIf { it.isNotBlank() }?.let { siteIcons[s.id] = it }
            launch {
                repository.fetchSiteIcon(s.id)?.let { icon ->
                    repository.resolveImageUrl(icon)?.let { siteIcons[s.id] = it }
                }
            }
        }
        allRuleGroups = repository.fetchSubscribeSearchSettings().filterRuleGroups.map { it.name }.filter { it.isNotBlank() }
        allDownloaders = repository.fetchDownloaders().filter { it.enabled }
    }

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // 顶部 取消 · 标题 · 保存 栏
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                NativeAdaptivePill("取消", selected = false, onClick = onDismiss)
                Text(
                    text = "编辑订阅 · ${item.name}",
                    color = colors.textPrimary,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    textAlign = TextAlign.Center,
                )
                NativeAdaptivePill(
                    title = "保存",
                    selected = true,
                    onClick = {
                        onSave(
                            item.copy(
                                season = seasonText.trim().toIntOrNull() ?: item.season,
                                totalEpisode = totalEpText.trim().toIntOrNull() ?: item.totalEpisode,
                                startEpisode = startEpText.trim().toIntOrNull(),
                                episodeGroup = episodeGroup.trim(),
                                quality = if (quality == "全部") "" else quality,
                                resolution = if (resolution == "全部") "" else resolution,
                                effect = if (effect == "全部") "" else effect,
                                bestVersion = bestVersion,
                                downloader = if (downloader == "默认") "" else downloader,
                                savePath = savePath.trim(),
                                sites = selectedSiteIds.toList().sorted(),
                                filterGroups = selectedFilterGroups.toList(),
                                searchImdbId = searchImdbId,
                                searchInterval = intervalHours.takeIf { it > 0 },
                                keyword = keyword,
                                include = includeWord,
                                exclude = excludeWord,
                                mediaCategory = mediaCategory,
                                customWords = customWords,
                            ),
                        )
                    },
                )
            }

            // 分组 0：剧集季集与剧集组（电视剧显示）
            if (item.type == "电视剧") {
                Text("季集设置", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
                CinematicPanel(padding = 0.dp, showsShadow = false) {
                    Column {
                        EditorInlineInputRow("订阅季号", seasonText, "如 1") { seasonText = it.filter(Char::isDigit) }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                        EditorInlineInputRow("总集数", totalEpText, "留空自动获取") { totalEpText = it.filter(Char::isDigit) }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                        EditorInlineInputRow("开始集数", startEpText, "从第几集开始追更") { startEpText = it.filter(Char::isDigit) }
                        HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                        EditorInlineInputRow("剧集组 ID", episodeGroup, "可选 TMDB 剧集组") { episodeGroup = it }
                    }
                }
            }

            // 分组 1：画质与洗版
            Text("画质与洗版", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
            CinematicPanel(padding = 0.dp, showsShadow = false) {
                Column {
                    EditorPickerRow("质量", quality, listOf("全部", "蓝光原盘", "Remux", "BluRay", "WEB-DL", "HDTV")) { quality = it }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    EditorPickerRow("分辨率", resolution, listOf("全部", "4K", "1080p", "720p")) { resolution = it }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    EditorPickerRow("特效", effect, listOf("全部", "杜比视界", "HDR", "中字", "国语")) { effect = it }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("自动洗版", color = colors.textPrimary, fontSize = 15.sp)
                        Switch(checked = bestVersion, onCheckedChange = { bestVersion = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                    }
                }
            }

            // 分组 2：下载器与保存路径（带下载器品牌图标）
            Text("下载与保存", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
            CinematicPanel(padding = 0.dp, showsShadow = false) {
                Column {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("下载器", color = colors.textPrimary, fontSize = 15.sp)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            NativeAdaptivePill(
                                title = "默认",
                                leadingContent = { NativeEntityLogo("downloader", "default", size = 16.dp, cornerRadius = 4.dp) },
                                selected = downloader == "默认",
                                onClick = { downloader = "默认" },
                            )
                            allDownloaders.forEach { dl ->
                                NativeAdaptivePill(
                                    title = dl.name,
                                    leadingContent = {
                                        NativeEntityLogo("downloader", dl.type.ifBlank { dl.name }, size = 16.dp, cornerRadius = 4.dp)
                                    },
                                    selected = downloader == dl.name,
                                    onClick = { downloader = dl.name },
                                )
                            }
                        }
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    EditorInlineInputRow("保存路径", savePath, "留空遵循目录配置") { savePath = it }
                }
            }

            // 分组 3：站点与优先级规则（支持真实站点 Favicon + logo_site 兜底多选！）
            Text("站点与优先级规则", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
            CinematicPanel(padding = 0.dp, showsShadow = false) {
                Column {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { showSitesPicker = !showSitesPicker }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("订阅站点", color = colors.textPrimary, fontSize = 15.sp)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(if (selectedSiteIds.isEmpty()) "跟随系统设置" else "已选 ${selectedSiteIds.size} 站", color = colors.accent, fontSize = 14.sp)
                            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                    if (showSitesPicker && allSites.isNotEmpty()) {
                        FlowRow(
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            NativeAdaptivePill("跟随系统", selected = selectedSiteIds.isEmpty(), onClick = { selectedSiteIds = emptySet() })
                            allSites.forEach { s ->
                                val picked = s.id in selectedSiteIds
                                val resolvedIcon = siteIcons[s.id] ?: repository.resolveImageUrl(s.iconUrl)
                                NativeAdaptivePill(
                                    title = s.name,
                                    leadingContent = {
                                        NativeNetworkEntityLogo(
                                            imageUrl = resolvedIcon,
                                            kind = "site",
                                            value = s.name,
                                            size = 16.dp,
                                            cornerRadius = 4.dp,
                                        )
                                    },
                                    selected = picked,
                                    onClick = {
                                        selectedSiteIds = if (picked) selectedSiteIds - s.id else selectedSiteIds + s.id
                                    },
                                )
                            }
                        }
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { showGroupsPicker = !showGroupsPicker }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("优先级规则组", color = colors.textPrimary, fontSize = 15.sp)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(if (selectedFilterGroups.isEmpty()) "跟随系统设置" else "已选 ${selectedFilterGroups.size} 组", color = colors.accent, fontSize = 14.sp)
                            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                        }
                    }
                    if (showGroupsPicker && allRuleGroups.isNotEmpty()) {
                        FlowRow(
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            NativeAdaptivePill("跟随系统", selected = selectedFilterGroups.isEmpty(), onClick = { selectedFilterGroups = emptySet() })
                            allRuleGroups.forEach { g ->
                                val picked = g in selectedFilterGroups
                                NativeAdaptivePill(g, selected = picked, onClick = {
                                    selectedFilterGroups = if (picked) selectedFilterGroups - g else selectedFilterGroups + g
                                })
                            }
                        }
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("使用 IMDB ID 精确搜索", color = colors.textPrimary, fontSize = 15.sp)
                        Switch(checked = searchImdbId, onCheckedChange = { searchImdbId = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.primaryButtonFg))
                    }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("搜索间隔", color = colors.textPrimary, fontSize = 15.sp)
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(if (intervalHours <= 0) "默认" else "${intervalHours}h", color = colors.textSecondary, fontSize = 14.sp)
                            Row(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(colors.chipFill)
                                    .border(0.6.dp, colors.chipBorder, CircleShape),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                IconButton(onClick = { if (intervalHours > 0) intervalHours-- }, modifier = Modifier.size(34.dp)) {
                                    Icon(Icons.Rounded.Remove, contentDescription = "减少", tint = colors.textPrimary, modifier = Modifier.size(16.dp))
                                }
                                Box(Modifier.width(0.8.dp).height(16.dp).background(colors.divider))
                                IconButton(onClick = { intervalHours++ }, modifier = Modifier.size(34.dp)) {
                                    Icon(Icons.Rounded.Add, contentDescription = "增加", tint = colors.textPrimary, modifier = Modifier.size(16.dp))
                                }
                            }
                        }
                    }
                }
            }

            // 分组 4：过滤与识别规则
            Text("过滤与识别规则", color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(start = 6.dp))
            CinematicPanel(padding = 0.dp, showsShadow = false) {
                Column {
                    EditorInlineInputRow("搜索关键字", keyword, "默认使用片名") { keyword = it }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    EditorInlineInputRow("包含规则", includeWord, "正则，如 中字|简繁") { includeWord = it }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    EditorInlineInputRow("排除规则", excludeWord, "正则，如 枪版|CAM") { excludeWord = it }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    EditorInlineInputRow("媒体分类", mediaCategory, "自定义二级分类") { mediaCategory = it }
                    HorizontalDivider(color = colors.divider, modifier = Modifier.padding(horizontal = 16.dp))
                    EditorInlineInputRow("自定义识别词", customWords, "可选替换词") { customWords = it }
                }
            }

            Button(
                onClick = onDelete,
                colors = ButtonDefaults.buttonColors(containerColor = colors.danger.copy(alpha = 0.18f), contentColor = colors.danger),
                shape = CircleShape,
                modifier = Modifier.fillMaxWidth().height(46.dp),
            ) {
                Icon(Icons.Rounded.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("删除此订阅", fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(22.dp))
        }
    }
}

@Composable
private fun EditorPickerRow(
    label: String,
    value: String,
    options: List<String>,
    onSelect: (String) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = true }
                .padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, color = colors.textPrimary, fontSize = 15.sp)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(value, color = colors.accent, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                Icon(Icons.Rounded.UnfoldMore, contentDescription = null, tint = colors.accent, modifier = Modifier.size(16.dp))
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { opt ->
                DropdownMenuItem(text = { Text(opt) }, onClick = { onSelect(opt); expanded = false })
            }
        }
    }
}

@Composable
private fun EditorInfoRow(label: String, value: String) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = colors.textPrimary, fontSize = 15.sp)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(value, color = colors.textSecondary, fontSize = 14.sp)
            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun EditorInlineInputRow(
    label: String,
    value: String,
    placeholder: String,
    onValueChange: (String) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, color = colors.textPrimary, fontSize = 15.sp)
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            if (value.isEmpty()) {
                Text(placeholder, color = colors.textMuted, fontSize = 14.sp, textAlign = TextAlign.End)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp, textAlign = TextAlign.End),
                cursorBrush = SolidColor(colors.accent),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/**
 * 追剧日历页面（升级为统一 `ExpressiveTintedScaffold`，接入真实 `GET /api/v1/subscribe/calendar`）：
 * 7 天周条在真实有更新的日期显示圆点指示，点击任意播映卡片直达影视详情页。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarScreen(
    repository: MoviePilotRepository? = null,
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit = {},
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val today = remember { LocalDate.now() }
    var weekOffset by rememberSaveable { mutableIntStateOf(0) }
    var selectedDateStr by rememberSaveable { mutableStateOf(today.toString()) }
    val selectedDate = remember(selectedDateStr) {
        runCatching { LocalDate.parse(selectedDateStr) }.getOrDefault(today)
    }
    var calendarEntries by remember { mutableStateOf<List<CalendarEntryDto>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun reloadCalendar() {
        if (repository != null) {
            calendarEntries = repository.fetchSubscribeCalendar()
        }
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(repository) {
        reloadCalendar()
    }

    val weekStart = remember(today, weekOffset) {
        val sundayOffset = today.dayOfWeek.value % 7
        today.minusDays(sundayOffset.toLong()).plusWeeks(weekOffset.toLong())
    }
    val weekDates = remember(weekStart) { (0L..6L).map { weekStart.plusDays(it) } }
    val weekdayLabels = listOf("日", "一", "二", "三", "四", "五", "六")
    val dateFmt = remember { DateTimeFormatter.ofPattern("yyyy-MM-dd") }
    val entriesByDate = remember(calendarEntries) {
        calendarEntries.groupBy { it.airDate.take(10) }
    }
    val dayItems = entriesByDate[selectedDate.format(dateFmt)].orEmpty()

    ExpressiveTintedScaffold(
        title = "追剧日历 · ${selectedDate.monthValue}月",
        subtitle = if (calendarEntries.isNotEmpty()) "近期共 ${calendarEntries.size} 集待播/更新" else null,
        onBack = onBack,
        actions = {
            NativeAdaptivePill(
                title = "今天",
                selected = selectedDate == today && weekOffset == 0,
                onClick = {
                    weekOffset = 0
                    selectedDateStr = today.toString()
                },
            )
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(10.dp))

            // 周视图日期条
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = { weekOffset-- }, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowLeft, contentDescription = "上一周", tint = colors.textSecondary)
                }
                weekDates.forEachIndexed { idx, d ->
                    val dKey = d.format(dateFmt)
                    val isSelected = d == selectedDate
                    val isToday = d == today
                    val hasAiring = !entriesByDate[dKey].isNullOrEmpty()
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(14.dp))
                            .background(if (isSelected) colors.activeIndicator else Color.Transparent)
                            .border(
                                width = if (isSelected) 1.dp else 0.dp,
                                color = if (isSelected) colors.accent.copy(alpha = 0.55f) else Color.Transparent,
                                shape = RoundedCornerShape(14.dp),
                            )
                            .clickable { selectedDateStr = d.toString() }
                            .padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        Text(
                            text = d.dayOfMonth.toString(),
                            color = when {
                                isToday -> colors.pink
                                isSelected -> colors.accent
                                else -> colors.textPrimary
                            },
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            text = weekdayLabels[idx],
                            color = if (isToday) colors.pink else colors.textSecondary,
                            fontSize = 11.sp,
                        )
                        Box(
                            modifier = Modifier
                                .size(5.dp)
                                .clip(CircleShape)
                                .background(
                                    when {
                                        hasAiring && isSelected -> colors.accent
                                        hasAiring -> colors.accent.copy(alpha = 0.78f)
                                        else -> Color.Transparent
                                    },
                                ),
                        )
                    }
                }
                IconButton(onClick = { weekOffset++ }, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = "下一周", tint = colors.textSecondary)
                }
            }

            Spacer(Modifier.height(10.dp))
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = margin),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "${selectedDate.format(dateFmt)} 播出",
                    color = colors.textPrimary,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                )
                if (dayItems.isNotEmpty()) {
                    NativeAdaptiveBadge("${dayItems.size} 部更新", tint = colors.accent)
                }
            }
            Spacer(Modifier.height(10.dp))

            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { reloadCalendar() }
                },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                if (isLoading && calendarEntries.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        androidx.compose.material3.CircularProgressIndicator(color = colors.accent)
                    }
                } else if (dayItems.isEmpty()) {
                    LazyColumn(
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp + bottomOverlayInset),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        item {
                            CinematicPanel(padding = 22.dp) {
                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Icon(Icons.Rounded.CalendarMonth, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(34.dp))
                                    Text("当日暂无订阅剧集更新", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    Text("可切换上方带圆点的日期查看近期排播单集", color = colors.textMuted, fontSize = 12.5.sp)
                                }
                            }
                        }
                    }
                } else {
                    LazyColumn(
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp + bottomOverlayInset),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(dayItems, key = { "${it.id}-${it.airDate}" }) { entry ->
                            CinematicPanel(
                                padding = 14.dp,
                                modifier = Modifier.clickable { onOpenMedia(entry.toMediaCardItem()) },
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .width(66.dp)
                                            .height(98.dp)
                                            .clip(RoundedCornerShape(11.dp))
                                            .background(colors.chipFill),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        if (!entry.poster.isNullOrBlank()) {
                                            AsyncImage(
                                                model = entry.poster,
                                                contentDescription = entry.title,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize(),
                                            )
                                        } else {
                                            Text(entry.title.take(2), color = colors.textPrimary, fontWeight = FontWeight.Bold)
                                        }
                                    }
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                            val headerTitle = if (entry.season != null) {
                                                "${entry.title} S%02d".format(entry.season)
                                            } else {
                                                entry.title
                                            }
                                            Text(
                                                text = headerTitle,
                                                color = colors.textPrimary,
                                                fontSize = 16.sp,
                                                fontWeight = FontWeight.Bold,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                                modifier = Modifier.weight(1f),
                                            )
                                            Spacer(Modifier.width(8.dp))
                                            NativeEntityLogo(
                                                kind = "datasource",
                                                value = entry.source,
                                                size = 18.dp,
                                                cornerRadius = 5.dp,
                                            )
                                        }
                                        val epLine = buildString {
                                            if (entry.episode != null) append("E%02d".format(entry.episode))
                                            if (entry.episodeTitle.isNotBlank()) {
                                                if (isNotEmpty()) append(" · ")
                                                append(entry.episodeTitle)
                                            } else if (entry.episode != null) {
                                                append(" 第 ${entry.episode} 集")
                                            }
                                        }.ifBlank { entry.type }
                                        Text(epLine, color = colors.textPrimary.copy(alpha = 0.90f), fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        Text(
                                            text = entry.airDate,
                                            color = colors.textSecondary,
                                            fontSize = 12.sp,
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

/**
 * 订阅广场页面（统一升级为 `ExpressiveTintedScaffold` + `ExpressivePillTabRow`）：
 * 热门电影 / 热门剧集点击直达详情页，社区分享支持真实 `POST /api/v1/subscribe/fork` 一键复用订阅。
 */
@Composable
fun SubscribeCommunityScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit = {},
) {
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val tabLabels = remember { listOf("热门电影", "热门剧集", "社区分享") }
    var selectedIdx by rememberSaveable { mutableIntStateOf(0) }

    ExpressiveTintedScaffold(
        title = "订阅广场",
        onBack = onBack,
        headerExtra = {
            ExpressivePillTabRow(
                tabs = tabLabels,
                selectedIndex = selectedIdx,
                onSelect = { selectedIdx = it },
                onTintedHeader = true,
            )
        },
    ) {
        SubscribeCommunityContent(
            repository = repository,
            onOpenMedia = onOpenMedia,
            externalTabIndex = selectedIdx,
            onExternalTabSelect = { selectedIdx = it },
            hideInternalTabRow = true,
            bottomPadding = 52.dp + bottomOverlayInset,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun SubscribeCommunityContent(
    repository: MoviePilotRepository,
    onOpenMedia: (MediaCardItem) -> Unit = {},
    externalTabIndex: Int? = null,
    onExternalTabSelect: ((Int) -> Unit)? = null,
    hideInternalTabRow: Boolean = false,
    bottomPadding: androidx.compose.ui.unit.Dp = 120.dp,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val snackbar = LocalSnackbarHostState.current
    val scope = rememberCoroutineScope()
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val cols = AdaptiveDeviceLayout.posterGridColumns()
    val tabKeys = remember { listOf("popular_movie", "popular_tv", "shares") }
    val tabLabels = remember { listOf("热门电影", "热门剧集", "社区分享") }
    var internalIdx by rememberSaveable { mutableIntStateOf(0) }
    val selectedIdx = externalTabIndex ?: internalIdx
    val tab = tabKeys[selectedIdx.coerceIn(0, tabKeys.lastIndex)]
    var items by remember(tab) { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var isLoading by remember(tab) { mutableStateOf(true) }
    var forkedIds by rememberSaveable { mutableStateOf<Set<String>>(emptySet()) }
    var forkingId by remember { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()
    val gridState = rememberLazyGridState()

    LaunchedEffect(tab) {
        isLoading = true
        items = when (tab) {
            "popular_movie" -> repository.fetchSubscribePopular("电影", 1)
            "popular_tv" -> repository.fetchSubscribePopular("电视剧", 1)
            else -> repository.fetchSubscribeShares(1)
        }
        isLoading = false
    }

    Column(modifier = modifier) {
        if (!hideInternalTabRow) {
            Spacer(Modifier.height(10.dp))
            Box(modifier = Modifier.padding(horizontal = margin)) {
                ExpressivePillTabRow(
                    tabs = tabLabels,
                    selectedIndex = selectedIdx,
                    onSelect = {
                        internalIdx = it
                        onExternalTabSelect?.invoke(it)
                    },
                    onTintedHeader = false,
                )
            }
            Spacer(Modifier.height(10.dp))
        } else {
            Spacer(Modifier.height(14.dp))
        }

        if (isLoading && items.isEmpty()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                androidx.compose.material3.CircularProgressIndicator(color = colors.accent)
            }
        } else if (tab == "shares") {
            LazyColumn(
                state = listState,
                contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomPadding),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(items, key = { "${it.resolvedId}-${it.shareUser}" }) { share ->
                    val shareKey = "${share.resolvedId}_${share.shareUser}"
                    val isForked = shareKey in forkedIds
                    val isForking = forkingId == shareKey
                    CinematicPanel(
                        padding = 14.dp,
                        modifier = Modifier.clickable { onOpenMedia(share) },
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier.width(58.dp).height(86.dp).clip(RoundedCornerShape(10.dp)).background(colors.chipFill),
                            ) {
                                if (!share.posterPath.isNullOrBlank()) {
                                    AsyncImage(model = share.posterPath, contentDescription = share.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                }
                            }
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(share.title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                if (!share.shareComment.isNullOrBlank()) {
                                    Text(share.shareComment!!, color = colors.textSecondary, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    if (!share.shareUser.isNullOrBlank()) {
                                        Text("分享者：${share.shareUser}", color = colors.textMuted, fontSize = 11.sp)
                                    }
                                    if (share.popularityCount > 0) {
                                        NativeAdaptiveBadge("复用 ${share.popularityCount}", tint = colors.accent)
                                    }
                                }
                            }
                            NativeAdaptivePill(
                                title = when {
                                    isForked -> "已复用"
                                    isForking -> "复用中…"
                                    else -> "复用订阅"
                                },
                                selected = !isForked,
                                onClick = {
                                    if (!isForked && !isForking) {
                                        forkingId = shareKey
                                        scope.launch {
                                            val (ok, msg) = repository.forkSubscribeShare(share)
                                            forkingId = null
                                            if (ok) {
                                                forkedIds = forkedIds + shareKey
                                            }
                                            snackbar?.showSnackbar(msg)
                                        }
                                    }
                                },
                            )
                        }
                    }
                }
            }
        } else {
            LazyVerticalGrid(
                state = gridState,
                columns = GridCells.Fixed(cols),
                contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomPadding),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(items, key = { "${it.resolvedId}-${it.title}" }) { item ->
                    val hotText = when {
                        item.popularityCount >= 1000 -> "🔥 ${String.format("%.1fk", item.popularityCount / 1000.0)}"
                        item.popularityCount > 0 -> "🔥 ${item.popularityCount}"
                        else -> null
                    }
                    NativePosterCard(
                        title = item.title,
                        year = item.year,
                        posterUrl = item.posterPath,
                        voteAverage = item.voteAverage,
                        inLibrary = item.inLibrary,
                        bottomBadgeText = hotText,
                        onClick = { onOpenMedia(item) },
                    )
                }
            }
        }
    }
}
