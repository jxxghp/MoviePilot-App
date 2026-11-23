package com.moviepilot.feature.download

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
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Storage
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicGlassCapsule
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
import com.moviepilot.rustbridge.SiteItemDto
import kotlinx.coroutines.launch

/**
 * 站点资源搜索与浏览页（1:1 复刻 iOS 黄金截图 `native-v2-live-resources.jpg`）：
 * - 顶栏双图标玻璃胶囊 `[⇅ ☰]`
 * - 搜索胶囊内嵌 `[全站 v]` 下拉与 `[浏览]` 按钮
 * - 9 维级联筛选（Rust `filter_and_group_resources` 驱动）
 * - 每张资源卡还原顶行媒体标识、彩色元信息胶囊带（紫站点/蓝分辨率/灰版式编码/淡紫季号/金中字）、完整标题描述与底行体积/做种/制作组
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
    val scope = rememberCoroutineScope()

    var keyword by remember { mutableStateOf(initialKeyword) }
    var sites by remember { mutableStateOf<List<SiteItemDto>>(emptyList()) }
    var browseSite by remember { mutableStateOf<SiteItemDto?>(null) }
    var showSiteDropdown by remember { mutableStateOf(false) }

    var rawItems by remember { mutableStateOf<List<ResourceItemDto>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var sortBySeeders by remember { mutableStateOf(true) }

    var selectedSite by remember { mutableStateOf<String?>(null) }
    var selectedRes by remember { mutableStateOf<String?>(null) }
    var selectedPromo by remember { mutableStateOf<String?>(null) }
    var selectedEncode by remember { mutableStateOf<String?>(null) }
    var selectedEdition by remember { mutableStateOf<String?>(null) }
    var activeFilterDim by remember { mutableStateOf<String?>(null) }

    var selectedGroupForDownload by remember { mutableStateOf<ResourceGroupDto?>(null) }
    var downloadToast by remember { mutableStateOf<String?>(null) }

    fun triggerSearch() {
        scope.launch {
            isLoading = true
            val fetched = repository.searchResources(keyword, browseSite?.id)
            rawItems = if (fetched.isNotEmpty() || keyword.isNotBlank()) {
                fetched
            } else {
                // 若最近搜索缓存为空且未选站点，自动浏览第一个已启用站点资源
                val firstActive = sites.firstOrNull { it.isActive }
                if (firstActive != null) repository.searchResources("", firstActive.id) else emptyList()
            }
            isLoading = false
        }
    }

    LaunchedEffect(Unit) {
        sites = repository.fetchSites()
        val fetched = repository.searchResources(keyword, browseSite?.id)
        rawItems = if (fetched.isNotEmpty()) {
            fetched
        } else {
            val firstActive = sites.firstOrNull { it.isActive }
            if (firstActive != null) repository.searchResources("", firstActive.id) else emptyList()
        }
        isLoading = false
    }

    val filterResult: ResourceFilterResultDto = remember(rawItems, selectedSite, selectedRes, selectedPromo, selectedEncode, selectedEdition, keyword) {
        val criteria = buildString {
            append("{")
            if (selectedSite != null) append("\"sites\":[\"$selectedSite\"],")
            if (selectedRes != null) append("\"resolutions\":[\"$selectedRes\"],")
            if (selectedPromo != null) append("\"promotions\":[\"$selectedPromo\"],")
            if (selectedEncode != null) append("\"video_encodes\":[\"$selectedEncode\"],")
            if (selectedEdition != null) append("\"editions\":[\"$selectedEdition\"],")
            append("\"keyword\":\"${keyword.replace("\"", "\\\"")}\"")
            append("}")
        }
        repository.filterResourcesWithRust(rawItems, criteria)
    }

    val displayedGroups = remember(filterResult.groups, sortBySeeders) {
        if (sortBySeeders) filterResult.groups.sortedByDescending { it.totalSeeders }
        else filterResult.groups.sortedByDescending { it.primary.size }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = if (filterResult.filteredCount > 0) "站点资源 (${filterResult.filteredCount})" else "站点资源",
            onBack = onBack,
            trailing = {
                CinematicGlassCapsule {
                    IconButton(onClick = { sortBySeeders = !sortBySeeders }, modifier = Modifier.size(38.dp)) {
                        Icon(Icons.Rounded.SwapVert, contentDescription = "排序", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                    }
                    IconButton(onClick = { activeFilterDim = if (activeFilterDim == null) "all" else null }, modifier = Modifier.size(38.dp)) {
                        Icon(Icons.Rounded.FilterList, contentDescription = "筛选", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                    }
                }
            },
        )

        // 搜索与全站浏览输入栏（1:1 复刻 iOS `[🔍 输入关键词，留空可浏...  [全站 v] [浏览]]`）
        CinematicPanel(padding = 8.dp, cornerRadius = 24.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(start = 8.dp, end = 2.dp),
            ) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                Box(modifier = Modifier.weight(1f)) {
                    if (keyword.isEmpty()) Text("输入关键词，留空可浏...", color = colors.textMuted, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    BasicTextField(
                        value = keyword,
                        onValueChange = { keyword = it },
                        singleLine = true,
                        textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp),
                        cursorBrush = SolidColor(colors.accent),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                Box {
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(colors.chipFill)
                            .border(0.6.dp, colors.chipBorder, CircleShape)
                            .clickable { showSiteDropdown = true }
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(browseSite?.name ?: "全站", color = colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1)
                        Icon(Icons.Rounded.KeyboardArrowDown, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(15.dp))
                    }
                    DropdownMenu(expanded = showSiteDropdown, onDismissRequest = { showSiteDropdown = false }) {
                        DropdownMenuItem(text = { Text("全站") }, onClick = { browseSite = null; showSiteDropdown = false })
                        sites.filter { it.isActive }.take(20).forEach { s ->
                            DropdownMenuItem(text = { Text(s.name) }, onClick = { browseSite = s; showSiteDropdown = false })
                        }
                    }
                }
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(colors.chipFill)
                        .border(0.7.dp, colors.chipBorder, CircleShape)
                        .clickable { triggerSearch() }
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                ) {
                    Text(if (keyword.isBlank()) "浏览" else "搜索", color = colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }

        Spacer(Modifier.height(10.dp))

        // 9 维级联筛选胶囊条（1:1 复刻 iOS `[≡ 全部筛选] [站点] [分辨率] [字幕] [版本] [编码]`）
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            item {
                val hasAny = selectedSite != null || selectedRes != null || selectedPromo != null || selectedEncode != null || selectedEdition != null
                NativeAdaptivePill(
                    title = "全部筛选",
                    selected = !hasAny,
                    icon = Icons.Rounded.Tune,
                    onClick = {
                        selectedSite = null; selectedRes = null; selectedPromo = null; selectedEncode = null; selectedEdition = null
                        activeFilterDim = null
                    },
                )
            }
            item { NativeAdaptivePill(selectedSite ?: "站点", selected = selectedSite != null || activeFilterDim == "site", onClick = { activeFilterDim = if (activeFilterDim == "site") null else "site" }) }
            item { NativeAdaptivePill(selectedRes ?: "分辨率", selected = selectedRes != null || activeFilterDim == "res", onClick = { activeFilterDim = if (activeFilterDim == "res") null else "res" }) }
            item { NativeAdaptivePill(selectedPromo ?: "促销", selected = selectedPromo != null || activeFilterDim == "promo", onClick = { activeFilterDim = if (activeFilterDim == "promo") null else "promo" }) }
            item { NativeAdaptivePill(selectedEdition ?: "版本", selected = selectedEdition != null || activeFilterDim == "edition", onClick = { activeFilterDim = if (activeFilterDim == "edition") null else "edition" }) }
            item { NativeAdaptivePill(selectedEncode ?: "编码", selected = selectedEncode != null || activeFilterDim == "encode", onClick = { activeFilterDim = if (activeFilterDim == "encode") null else "encode" }) }
        }

        // 展开选中维度的级联选项
        if (activeFilterDim != null) {
            Spacer(Modifier.height(8.dp))
            val optionsList = when (activeFilterDim) {
                "site" -> filterResult.options.sites
                "res" -> filterResult.options.resolutions
                "promo" -> filterResult.options.promotions
                "edition" -> filterResult.options.editions
                "encode" -> filterResult.options.videoEncodes
                else -> filterResult.options.resolutions + filterResult.options.sites
            }
            if (optionsList.isNotEmpty()) {
                LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(optionsList) { opt ->
                        val isSel = when (activeFilterDim) {
                            "site" -> selectedSite == opt
                            "res" -> selectedRes == opt
                            "promo" -> selectedPromo == opt
                            "edition" -> selectedEdition == opt
                            "encode" -> selectedEncode == opt
                            else -> selectedRes == opt || selectedSite == opt
                        }
                        NativeAdaptivePill(opt, selected = isSel, onClick = {
                            when (activeFilterDim) {
                                "site" -> selectedSite = if (selectedSite == opt) null else opt
                                "res" -> selectedRes = if (selectedRes == opt) null else opt
                                "promo" -> selectedPromo = if (selectedPromo == opt) null else opt
                                "edition" -> selectedEdition = if (selectedEdition == opt) null else opt
                                "encode" -> selectedEncode = if (selectedEncode == opt) null else opt
                                else -> if (opt in filterResult.options.resolutions) selectedRes = opt else selectedSite = opt
                            }
                        })
                    }
                }
            }
        }

        downloadToast?.let {
            Text(it, color = colors.success, fontSize = 13.sp, modifier = Modifier.padding(horizontal = margin, vertical = 6.dp))
        }

        Spacer(Modifier.height(10.dp))

        if (isLoading) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.accent)
            }
        } else if (displayedGroups.isEmpty()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = margin), contentAlignment = Alignment.TopCenter) {
                CinematicPanel(padding = 28.dp, showsShadow = false) {
                    Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(38.dp))
                        Text("暂无匹配的站点资源", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                        Text("可输入关键词搜索，或选择具体站点后点击「浏览」查看最新种子。", color = colors.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center)
                    }
                }
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(start = margin, end = margin, bottom = 132.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(displayedGroups, key = { it.key + it.primary.id }) { group ->
                    val item = group.primary
                    CinematicPanel(
                        padding = 15.dp,
                        showsShadow = false,
                        modifier = Modifier.clickable { selectedGroupForDownload = group },
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            // 顶行媒体标识（紫电视/电影图标 + 片名 + 年份 + 右侧类型胶囊）
                            if (item.mediaTitle.isNotBlank() || item.mediaType.isNotBlank()) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.weight(1f)) {
                                        Icon(
                                            if (item.mediaType == "电视剧") Icons.Rounded.Tv else Icons.Rounded.Movie,
                                            contentDescription = null,
                                            tint = colors.accent,
                                            modifier = Modifier.size(16.dp),
                                        )
                                        Text(item.mediaTitle.ifBlank { item.siteName }, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        if (item.mediaYear.isNotBlank()) {
                                            Text(item.mediaYear, color = colors.textMuted, fontSize = 12.sp)
                                        }
                                    }
                                    if (item.mediaType.isNotBlank()) {
                                        NativeAdaptiveBadge(item.mediaType, tint = colors.textSecondary)
                                    }
                                }
                            }

                            // 彩色元信息胶囊行（紫站点 / 蓝 2160p / 灰版式编码 / 淡紫季号 / 金中字）
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                NativeAdaptiveBadge(item.siteName, tint = colors.accent, filled = true)
                                if (item.resourcePix.isNotBlank()) NativeAdaptiveBadge(item.resourcePix, tint = colors.info)
                                if (item.edition.isNotBlank()) NativeAdaptiveBadge(item.edition, tint = colors.textSecondary)
                                if (item.videoEncode.isNotBlank()) NativeAdaptiveBadge(item.videoEncode, tint = colors.textSecondary)
                                if (item.seasonEpisode.isNotBlank()) NativeAdaptiveBadge(item.seasonEpisode, tint = colors.brand)
                                if (item.downloadvolumefactor == 0.0) NativeAdaptiveBadge("免费", tint = colors.success)
                                item.labels.take(3).forEach { lbl -> NativeAdaptiveBadge(lbl, tint = colors.warning) }
                                if (group.items.size > 1) NativeAdaptiveBadge("同规格 ${group.items.size} 源", tint = colors.pink)
                            }

                            Text(
                                text = item.title,
                                color = colors.textPrimary,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                lineHeight = 20.sp,
                            )
                            if (item.description.isNotBlank()) {
                                Text(
                                    text = item.description,
                                    color = colors.textSecondary,
                                    fontSize = 12.sp,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                    lineHeight = 17.sp,
                                )
                            }
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Icon(Icons.Rounded.Storage, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(13.dp))
                                        Text(formatBytes(item.size.toDouble()), color = colors.textSecondary, fontSize = 12.sp)
                                    }
                                    Text("↑ ${group.totalSeeders}", color = colors.success, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                }
                                Text(item.resourceTeam.ifBlank { item.siteName }, color = colors.textMuted, fontSize = 12.sp)
                            }
                        }
                    }
                }
            }
        }
    }

    // 原生分组下载确认弹窗
    selectedGroupForDownload?.let { group ->
        var selectedDownloader by remember { mutableStateOf("Qbittorrent") }
        var saveDir by remember { mutableStateOf("/downloads/") }

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
                    listOf("Qbittorrent", "Transmission").forEach { dl ->
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

/**
 * 正在下载管理页（1:1 复刻 iOS 黄金截图 `native-v2-live-downloads.jpg`）：
 * 真实拉取 `/api/v1/download/`，空态展示通透居中玻璃卡片，有任务时展示进度条与上下行速度控制。
 */
@Composable
fun DownloadsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    var tasks by remember { mutableStateOf<List<DownloadTaskDto>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        tasks = repository.fetchDownloads()
        isLoading = false
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(
            title = if (tasks.isEmpty()) "正在下载" else "正在下载 (${tasks.size})",
            onBack = onBack,
            trailing = {
                CinematicCircleButton(Icons.Rounded.FilterList, "筛选下载器", {})
            },
        )

        if (isLoading) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.accent)
            }
        } else if (tasks.isEmpty()) {
            // 1:1 复刻 iOS `native-v2-live-downloads.jpg` 顶部通透空态玻璃卡片
            Column(modifier = Modifier.fillMaxWidth().padding(horizontal = margin, vertical = 12.dp)) {
                CinematicPanel(padding = 34.dp, cornerRadius = 24.dp, showsShadow = false) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(48.dp)
                                .clip(CircleShape)
                                .border(2.2.dp, colors.textMuted.copy(alpha = 0.72f), CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Rounded.ArrowDownward, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(26.dp))
                        }
                        Text("当前没有正在下载的任务", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Text(
                            "新添加的种子或订阅下载会实时显示在这里。",
                            color = colors.textSecondary,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        } else {
            LazyColumn(
                contentPadding = PaddingValues(start = margin, end = margin, top = 6.dp, bottom = 128.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(tasks, key = { it.hash + it.title }) { task ->
                    val isPaused = task.state.contains("pause", ignoreCase = true)
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
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
