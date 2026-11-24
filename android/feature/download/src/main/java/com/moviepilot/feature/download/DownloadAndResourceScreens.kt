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
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Check
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.LocalSnackbarHostState
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeNetworkEntityLogo
import com.moviepilot.rustbridge.DirectoryConfigDto
import com.moviepilot.rustbridge.DownloadTaskDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.ResourceFilterResultDto
import com.moviepilot.rustbridge.ResourceGroupDto
import com.moviepilot.rustbridge.ResourceItemDto
import com.moviepilot.rustbridge.ServiceConfigDto
import com.moviepilot.rustbridge.SiteItemDto
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 站点资源搜索与浏览页（统一升级为 `ExpressiveTintedScaffold`）：
 * - 搜索胶囊内嵌真实站点 Favicon 多选器与搜索/浏览按钮
 * - Rust `filter_and_group_resources` 9 维级联筛选与同规格分组
 * - 下载确认弹窗真实读取系统下载器与目录映射、支持同组任意种子源切换、展示下载器/存储品牌图标并真实调用 `POST /api/v1/download/add`
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ResourceSearchScreen(
    repository: MoviePilotRepository,
    initialKeyword: String = "",
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val snackbar = LocalSnackbarHostState.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    var keyword by rememberSaveable { mutableStateOf(initialKeyword) }
    var sites by remember { mutableStateOf<List<SiteItemDto>>(emptyList()) }
    val siteIcons = remember { mutableStateMapOf<Int, String>() }
    val siteIconsByName = remember { mutableStateMapOf<String, String>() }
    var selectedBrowseSiteIds by rememberSaveable { mutableStateOf<Set<Int>>(emptySet()) }
    var showSitePickerSheet by remember { mutableStateOf(false) }

    var rawItems by remember { mutableStateOf<List<ResourceItemDto>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var sortMode by rememberSaveable { mutableStateOf("seeders") } // seeders | size_desc | size_asc | group_count
    var showSortMenu by remember { mutableStateOf(false) }
    var showAllFiltersSheet by remember { mutableStateOf(false) }

    var selectedSitesFilter by remember { mutableStateOf<Set<String>>(emptySet()) }
    var selectedRes by remember { mutableStateOf<String?>(null) }
    var selectedPromo by remember { mutableStateOf<String?>(null) }
    var selectedEncode by remember { mutableStateOf<String?>(null) }
    var selectedEdition by remember { mutableStateOf<String?>(null) }
    var activeFilterDim by remember { mutableStateOf<String?>(null) }

    var selectedGroupForDownload by remember { mutableStateOf<ResourceGroupDto?>(null) }
    var downloadToast by remember { mutableStateOf<Pair<Boolean, String>?>(null) }

    val sortLabels = remember {
        listOf(
            "seeders" to "做种最多",
            "size_desc" to "体积最大",
            "size_asc" to "体积最小",
            "group_count" to "同源最多",
        )
    }

    fun triggerSearch(targetIds: Set<Int> = selectedBrowseSiteIds) {
        scope.launch {
            isLoading = true
            val idsList = targetIds.toList()
            val fetched = repository.searchResources(keyword, idsList)
            rawItems = if (fetched.isNotEmpty() || keyword.isNotBlank() || idsList.isNotEmpty()) {
                fetched
            } else {
                val firstActive = sites.firstOrNull { it.isActive }
                if (firstActive != null) repository.searchResources("", listOf(firstActive.id)) else emptyList()
            }
            isLoading = false
        }
    }

    LaunchedEffect(Unit) {
        val loadedSites = repository.fetchSites()
        sites = loadedSites
        loadedSites.forEach { s ->
            repository.resolveImageUrl(s.iconUrl)?.let {
                siteIcons[s.id] = it
                siteIconsByName[s.name] = it
            }
            launch {
                repository.fetchSiteIcon(s.id)?.let { raw ->
                    val resolved = repository.resolveImageUrl(raw) ?: raw
                    siteIcons[s.id] = resolved
                    siteIconsByName[s.name] = resolved
                }
            }
        }
        val fetched = repository.searchResources(keyword, selectedBrowseSiteIds.toList())
        rawItems = if (fetched.isNotEmpty()) {
            fetched
        } else {
            val firstActive = loadedSites.firstOrNull { it.isActive }
            if (firstActive != null) repository.searchResources("", listOf(firstActive.id)) else emptyList()
        }
        isLoading = false
    }

    val filterResult: ResourceFilterResultDto = remember(rawItems, selectedSitesFilter, selectedRes, selectedPromo, selectedEncode, selectedEdition, keyword) {
        val criteria = buildString {
            append("{")
            if (selectedSitesFilter.isNotEmpty()) {
                val joined = selectedSitesFilter.joinToString(",") { "\"${it.replace("\"", "\\\"")}\"" }
                append("\"sites\":[$joined],")
            }
            if (selectedRes != null) append("\"resolutions\":[\"$selectedRes\"],")
            if (selectedPromo != null) append("\"promotions\":[\"$selectedPromo\"],")
            if (selectedEncode != null) append("\"video_encodes\":[\"$selectedEncode\"],")
            if (selectedEdition != null) append("\"editions\":[\"$selectedEdition\"],")
            append("\"keyword\":\"${keyword.replace("\"", "\\\"")}\"")
            append("}")
        }
        repository.filterResourcesWithRust(rawItems, criteria)
    }

    val displayedGroups = remember(filterResult.groups, sortMode) {
        when (sortMode) {
            "size_desc" -> filterResult.groups.sortedByDescending { it.primary.size }
            "size_asc" -> filterResult.groups.sortedBy { it.primary.size }
            "group_count" -> filterResult.groups.sortedByDescending { it.items.size }
            else -> filterResult.groups.sortedByDescending { it.totalSeeders }
        }
    }

    val activeFilterCount = selectedSitesFilter.size +
        listOf(selectedRes, selectedPromo, selectedEncode, selectedEdition).count { it != null }
    val browseSiteLabel = when (selectedBrowseSiteIds.size) {
        0 -> "全站"
        1 -> sites.firstOrNull { it.id == selectedBrowseSiteIds.first() }?.name ?: "1 个站点"
        else -> "已选 ${selectedBrowseSiteIds.size} 站"
    }
    val currentSortLabel = sortLabels.firstOrNull { it.first == sortMode }?.second ?: "做种最多"

    ExpressiveTintedScaffold(
        title = if (filterResult.filteredCount > 0) "站点资源 (${filterResult.filteredCount})" else "站点资源",
        onBack = onBack,
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(14.dp))

            // 搜索与多选站点浏览输入栏
            CinematicPanel(padding = 8.dp, cornerRadius = 24.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(start = 8.dp, end = 2.dp),
                ) {
                    Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                    Box(modifier = Modifier.weight(1f)) {
                        if (keyword.isEmpty()) Text("输入关键词，留空可浏览站点", color = colors.textMuted, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        BasicTextField(
                            value = keyword,
                            onValueChange = { keyword = it },
                            singleLine = true,
                            textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp),
                            cursorBrush = SolidColor(colors.accent),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    Row(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (selectedBrowseSiteIds.isNotEmpty()) colors.activeIndicator else colors.chipFill)
                            .border(0.7.dp, if (selectedBrowseSiteIds.isNotEmpty()) colors.accent else colors.borderSubtle.copy(alpha = 0.55f), CircleShape)
                            .clickable { showSitePickerSheet = true }
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        val singleSiteId = selectedBrowseSiteIds.singleOrNull()
                        NativeNetworkEntityLogo(
                            imageUrl = singleSiteId?.let { siteIcons[it] },
                            kind = "site",
                            value = browseSiteLabel,
                            size = 15.dp,
                            cornerRadius = 4.dp,
                        )
                        Text(browseSiteLabel, color = colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1)
                        Icon(Icons.Rounded.KeyboardArrowDown, contentDescription = "选择站点", tint = colors.textSecondary, modifier = Modifier.size(15.dp))
                    }
                    Box(
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(colors.accent)
                            .clickable { triggerSearch() }
                            .padding(horizontal = 14.dp, vertical = 6.dp),
                    ) {
                        Text(if (keyword.isBlank()) "浏览" else "搜索", color = colors.primaryButtonFg, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            Spacer(Modifier.height(10.dp))

            // 排序 + 多维筛选胶囊行
            LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item {
                    Box {
                        NativeAdaptivePill(
                            title = "排序 · $currentSortLabel",
                            selected = sortMode != "seeders",
                            icon = Icons.Rounded.SwapVert,
                            onClick = { showSortMenu = true },
                        )
                        DropdownMenu(expanded = showSortMenu, onDismissRequest = { showSortMenu = false }) {
                            sortLabels.forEach { (key, label) ->
                                DropdownMenuItem(
                                    text = { Text(label, fontWeight = if (sortMode == key) FontWeight.Bold else FontWeight.Normal) },
                                    onClick = {
                                        sortMode = key
                                        showSortMenu = false
                                    },
                                )
                            }
                        }
                    }
                }
                item {
                    NativeAdaptivePill(
                        title = if (activeFilterCount > 0) "全部筛选 ($activeFilterCount)" else "全部筛选",
                        selected = activeFilterCount > 0,
                        icon = Icons.Rounded.Tune,
                        onClick = { showAllFiltersSheet = true },
                    )
                }
                item {
                    val label = when (selectedSitesFilter.size) {
                        0 -> "结果站点"
                        1 -> selectedSitesFilter.first()
                        else -> "结果站点 (${selectedSitesFilter.size})"
                    }
                    NativeAdaptivePill(label, selected = selectedSitesFilter.isNotEmpty() || activeFilterDim == "site", onClick = { activeFilterDim = if (activeFilterDim == "site") null else "site" })
                }
                item { NativeAdaptivePill(selectedRes ?: "分辨率", selected = selectedRes != null || activeFilterDim == "res", onClick = { activeFilterDim = if (activeFilterDim == "res") null else "res" }) }
                item { NativeAdaptivePill(selectedPromo ?: "促销", selected = selectedPromo != null || activeFilterDim == "promo", onClick = { activeFilterDim = if (activeFilterDim == "promo") null else "promo" }) }
                item { NativeAdaptivePill(selectedEdition ?: "版本", selected = selectedEdition != null || activeFilterDim == "edition", onClick = { activeFilterDim = if (activeFilterDim == "edition") null else "edition" }) }
                item { NativeAdaptivePill(selectedEncode ?: "编码", selected = selectedEncode != null || activeFilterDim == "encode", onClick = { activeFilterDim = if (activeFilterDim == "encode") null else "encode" }) }
            }

            if (activeFilterDim != null) {
                Spacer(Modifier.height(8.dp))
                val optionsList = when (activeFilterDim) {
                    "site" -> filterResult.options.sites
                    "res" -> filterResult.options.resolutions
                    "promo" -> filterResult.options.promotions
                    "edition" -> filterResult.options.editions
                    "encode" -> filterResult.options.videoEncodes
                    else -> emptyList()
                }
                if (optionsList.isNotEmpty()) {
                    LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(optionsList) { opt ->
                            val isSel = when (activeFilterDim) {
                                "site" -> opt in selectedSitesFilter
                                "res" -> selectedRes == opt
                                "promo" -> selectedPromo == opt
                                "edition" -> selectedEdition == opt
                                "encode" -> selectedEncode == opt
                                else -> false
                            }
                            NativeAdaptivePill(
                                title = opt,
                                leadingContent = if (activeFilterDim == "site") {
                                    {
                                        NativeNetworkEntityLogo(
                                            imageUrl = siteIconsByName[opt],
                                            kind = "site",
                                            value = opt,
                                            size = 15.dp,
                                            cornerRadius = 4.dp,
                                        )
                                    }
                                } else null,
                                selected = isSel,
                                onClick = {
                                    when (activeFilterDim) {
                                        "site" -> selectedSitesFilter = if (opt in selectedSitesFilter) selectedSitesFilter - opt else selectedSitesFilter + opt
                                        "res" -> selectedRes = if (selectedRes == opt) null else opt
                                        "promo" -> selectedPromo = if (selectedPromo == opt) null else opt
                                        "edition" -> selectedEdition = if (selectedEdition == opt) null else opt
                                        "encode" -> selectedEncode = if (selectedEncode == opt) null else opt
                                    }
                                },
                            )
                        }
                    }
                }
            }

            downloadToast?.let { (ok, msg) ->
                Text(
                    text = msg,
                    color = if (ok) colors.success else colors.warning,
                    fontSize = 13.sp,
                    modifier = Modifier.padding(horizontal = margin, vertical = 6.dp),
                )
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
                    state = listState,
                    contentPadding = PaddingValues(start = margin, end = margin, bottom = 56.dp + bottomOverlayInset),
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

                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Row(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(colors.accent.copy(alpha = if (colors.isDark) 0.24f else 0.14f))
                                            .padding(horizontal = 8.dp, vertical = 3.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                                    ) {
                                        NativeNetworkEntityLogo(
                                            imageUrl = siteIconsByName[item.siteName],
                                            kind = "site",
                                            value = item.siteName,
                                            size = 14.dp,
                                            cornerRadius = 3.dp,
                                        )
                                        Text(item.siteName, color = colors.accent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                    }
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
    }

    // 真实分组下载确认弹窗（动态读取下载器与保存目录、支持同组多站点种子源切换、真实提交 POST /api/v1/download/add）
    selectedGroupForDownload?.let { group ->
        val variants = remember(group) { group.items.ifEmpty { listOf(group.primary) } }
        var chosenVariant by remember(group) { mutableStateOf(group.primary) }
        var configuredDownloaders by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }
        var configuredDirs by remember { mutableStateOf<List<DirectoryConfigDto>>(emptyList()) }
        var selectedDownloader by remember { mutableStateOf("默认下载器") }
        var saveDir by remember { mutableStateOf("") }
        var isSubmitting by remember { mutableStateOf(false) }
        val fieldColors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.fieldBorder,
        )

        LaunchedEffect(group) {
            val dls = repository.fetchDownloaders().filter { it.enabled }
            configuredDownloaders = dls
            dls.firstOrNull { it.isDefault }?.let { selectedDownloader = it.name }
            val dirs = repository.fetchDirectories()
            configuredDirs = dirs
        }

        NativeGlassSheet(onDismissRequest = { if (!isSubmitting) selectedGroupForDownload = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("确认添加下载", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Text(chosenVariant.title, color = colors.textSecondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)

                if (variants.size > 1) {
                    Text("选择同规格站点源 (${variants.size})", color = colors.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        variants.forEach { variant ->
                            val isSelected = variant.id == chosenVariant.id && variant.siteName == chosenVariant.siteName
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(if (isSelected) colors.activeIndicator else colors.surfaceContainerLow)
                                    .border(
                                        width = 0.8.dp,
                                        color = if (isSelected) colors.accent else colors.borderSubtle.copy(alpha = 0.45f),
                                        shape = RoundedCornerShape(14.dp),
                                    )
                                    .clickable { chosenVariant = variant }
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                NativeNetworkEntityLogo(
                                    imageUrl = siteIconsByName[variant.siteName],
                                    kind = "site",
                                    value = variant.siteName,
                                    size = 22.dp,
                                    cornerRadius = 6.dp,
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Text(variant.siteName, color = colors.textPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.Bold)
                                        if (variant.downloadvolumefactor == 0.0) {
                                            NativeAdaptiveBadge("免费", tint = colors.success)
                                        }
                                        Text("↑ ${variant.seeders}", color = colors.success, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                                        Text(formatBytes(variant.size.toDouble()), color = colors.textSecondary, fontSize = 12.sp)
                                    }
                                    Text(variant.title, color = colors.textMuted, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                                if (isSelected) {
                                    Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                                }
                            }
                        }
                    }
                }

                Text("选择下载器", color = colors.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NativeAdaptivePill(
                        title = "默认下载器",
                        leadingContent = {
                            NativeEntityLogo("downloader", "default", size = 16.dp, cornerRadius = 4.dp)
                        },
                        selected = selectedDownloader == "默认下载器",
                        onClick = { selectedDownloader = "默认下载器" },
                    )
                    configuredDownloaders.forEach { dl ->
                        NativeAdaptivePill(
                            title = dl.name,
                            leadingContent = {
                                NativeEntityLogo("downloader", dl.type.ifBlank { dl.name }, size = 16.dp, cornerRadius = 4.dp)
                            },
                            selected = selectedDownloader == dl.name,
                            onClick = { selectedDownloader = dl.name },
                        )
                    }
                }

                if (configuredDirs.any { it.downloadPath.isNotBlank() }) {
                    Text("常用下载目录预设", color = colors.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        NativeAdaptivePill(
                            title = "自动匹配目录",
                            leadingContent = {
                                NativeEntityLogo("storage", "local", size = 16.dp, cornerRadius = 4.dp)
                            },
                            selected = saveDir.isBlank(),
                            onClick = { saveDir = "" },
                        )
                        configuredDirs.filter { it.downloadPath.isNotBlank() }.forEach { dir ->
                            NativeAdaptivePill(
                                title = "${dir.name} (${dir.downloadPath})",
                                leadingContent = {
                                    NativeEntityLogo("storage", dir.storage, size = 16.dp, cornerRadius = 4.dp)
                                },
                                selected = saveDir == dir.downloadPath,
                                onClick = { saveDir = dir.downloadPath },
                            )
                        }
                    }
                }

                OutlinedTextField(
                    value = saveDir,
                    onValueChange = { saveDir = it },
                    label = { Text("保存目录（留空按目录规则自动匹配）") },
                    singleLine = true,
                    colors = fieldColors,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    enabled = !isSubmitting,
                    onClick = {
                        isSubmitting = true
                        scope.launch {
                            val (ok, msg) = repository.addDownload(
                                item = chosenVariant,
                                downloader = selectedDownloader.takeIf { it != "默认下载器" },
                                savePath = saveDir.trim().takeIf { it.isNotBlank() },
                            )
                            isSubmitting = false
                            downloadToast = ok to msg
                            if (ok) {
                                selectedGroupForDownload = null
                            }
                            snackbar?.showSnackbar(msg)
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    if (isSubmitting) {
                        CircularProgressIndicator(color = colors.primaryButtonFg, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("正在提交下载…", fontWeight = FontWeight.SemiBold)
                    } else {
                        Icon(Icons.Rounded.Download, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("开始下载", fontWeight = FontWeight.SemiBold)
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }

    // 多选站点面板（真实加载 `/api/v1/site/icon/{id}` 站点图标 + `logo_site` 兜底）
    if (showSitePickerSheet) {
        val activeSites = remember(sites) { sites.filter { it.isActive } }
        NativeGlassSheet(onDismissRequest = { showSitePickerSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text("选择搜索站点（支持多选）", color = colors.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                        Text(
                            if (selectedBrowseSiteIds.isEmpty()) "当前：全站（留空自动遵循站点范围）"
                            else "已选 ${selectedBrowseSiteIds.size} 个站点",
                            color = colors.textSecondary,
                            fontSize = 12.sp,
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NativeAdaptivePill("全站", selected = selectedBrowseSiteIds.isEmpty(), onClick = { selectedBrowseSiteIds = emptySet() })
                        NativeAdaptivePill("全选", selected = activeSites.isNotEmpty() && selectedBrowseSiteIds.size == activeSites.size, onClick = {
                            selectedBrowseSiteIds = activeSites.map { it.id }.toSet()
                        })
                    }
                }
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().height(340.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            activeSites.forEach { s ->
                                val picked = s.id in selectedBrowseSiteIds
                                NativeAdaptivePill(
                                    title = s.name,
                                    leadingContent = {
                                        NativeNetworkEntityLogo(
                                            imageUrl = siteIcons[s.id],
                                            kind = "site",
                                            value = s.name,
                                            size = 16.dp,
                                            cornerRadius = 4.dp,
                                        )
                                    },
                                    selected = picked,
                                    onClick = {
                                        selectedBrowseSiteIds = if (picked) selectedBrowseSiteIds - s.id else selectedBrowseSiteIds + s.id
                                    },
                                )
                            }
                        }
                    }
                }
                Button(
                    onClick = {
                        showSitePickerSheet = false
                        triggerSearch(selectedBrowseSiteIds)
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    Text(if (keyword.isBlank()) "应用并浏览" else "应用并搜索", fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // 「全部筛选」多维筛选面板
    if (showAllFiltersSheet) {
        NativeGlassSheet(onDismissRequest = { showAllFiltersSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("全部筛选条件", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    NativeAdaptivePill(
                        title = "清空全部",
                        selected = false,
                        onClick = {
                            selectedSitesFilter = emptySet()
                            selectedRes = null
                            selectedPromo = null
                            selectedEncode = null
                            selectedEdition = null
                        },
                    )
                }
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().height(380.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    if (filterResult.options.sites.isNotEmpty()) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("结果站点（可多选）", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    filterResult.options.sites.forEach { s ->
                                        val picked = s in selectedSitesFilter
                                        NativeAdaptivePill(
                                            title = s,
                                            leadingContent = {
                                                NativeNetworkEntityLogo(
                                                    imageUrl = siteIconsByName[s],
                                                    kind = "site",
                                                    value = s,
                                                    size = 16.dp,
                                                    cornerRadius = 4.dp,
                                                )
                                            },
                                            selected = picked,
                                            onClick = {
                                                selectedSitesFilter = if (picked) selectedSitesFilter - s else selectedSitesFilter + s
                                            },
                                        )
                                    }
                                }
                            }
                        }
                    }
                    if (filterResult.options.resolutions.isNotEmpty()) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("分辨率", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    filterResult.options.resolutions.forEach { opt ->
                                        NativeAdaptivePill(opt, selected = selectedRes == opt, onClick = { selectedRes = if (selectedRes == opt) null else opt })
                                    }
                                }
                            }
                        }
                    }
                    if (filterResult.options.promotions.isNotEmpty()) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("促销优惠", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    filterResult.options.promotions.forEach { opt ->
                                        NativeAdaptivePill(opt, selected = selectedPromo == opt, onClick = { selectedPromo = if (selectedPromo == opt) null else opt })
                                    }
                                }
                            }
                        }
                    }
                    if (filterResult.options.editions.isNotEmpty()) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("质量版本", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    filterResult.options.editions.forEach { opt ->
                                        NativeAdaptivePill(opt, selected = selectedEdition == opt, onClick = { selectedEdition = if (selectedEdition == opt) null else opt })
                                    }
                                }
                            }
                        }
                    }
                    if (filterResult.options.videoEncodes.isNotEmpty()) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("视频编码", color = colors.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    filterResult.options.videoEncodes.forEach { opt ->
                                        NativeAdaptivePill(opt, selected = selectedEncode == opt, onClick = { selectedEncode = if (selectedEncode == opt) null else opt })
                                    }
                                }
                            }
                        }
                    }
                    if (filterResult.options.sites.isEmpty() && filterResult.options.resolutions.isEmpty()) {
                        item {
                            Text("当前暂无可筛选结果，请先输入关键词或选择站点浏览。", color = colors.textMuted, fontSize = 13.sp)
                        }
                    }
                }
                Button(
                    onClick = { showAllFiltersSheet = false },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    Text("查看 ${filterResult.filteredCount} 条结果", fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

/**
 * 正在下载管理页（统一升级为 `ExpressiveTintedScaffold` + 4s 实时轮询 + 真实启停/删除/下载器筛选）：
 * - 真实对接 `GET /api/v1/download/`、`GET /api/v1/download/start/{hash}`、`GET /api/v1/download/stop/{hash}` 与 `DELETE /api/v1/download/{hash}`；
 * - 展示 qBittorrent / Transmission / rTorrent 下载器品牌图标；
 * - 页面前台可见期间每 4 秒自动无感轮询进度与速度。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun DownloadsScreen(
    repository: MoviePilotRepository,
    onBack: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val snackbar = LocalSnackbarHostState.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val listState = rememberLazyListState()

    var tasks by remember { mutableStateOf<List<DownloadTaskDto>>(emptyList()) }
    var downloaders by remember { mutableStateOf<List<ServiceConfigDto>>(emptyList()) }
    var selectedDownloaderFilter by rememberSaveable { mutableStateOf<String?>(null) }
    var showFilterSheet by remember { mutableStateOf(false) }
    var confirmDeleteTask by remember { mutableStateOf<DownloadTaskDto?>(null) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun reloadTasks(showSpinner: Boolean = false) {
        if (showSpinner) isLoading = true
        tasks = repository.fetchDownloads(selectedDownloaderFilter)
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(Unit) {
        downloaders = repository.fetchDownloaders().filter { it.enabled }
    }

    LaunchedEffect(selectedDownloaderFilter, lifecycleOwner) {
        reloadTasks(showSpinner = tasks.isEmpty())
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            while (true) {
                delay(4_000L)
                tasks = repository.fetchDownloads(selectedDownloaderFilter)
            }
        }
    }

    ExpressiveTintedScaffold(
        title = if (tasks.isEmpty()) "正在下载" else "正在下载 (${tasks.size})",
        subtitle = selectedDownloaderFilter?.let { "当前筛选：$it" },
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.FilterList,
                contentDescription = "筛选下载器",
                onClick = { showFilterSheet = true },
            )
        },
    ) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { reloadTasks(showSpinner = false) }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            if (isLoading && tasks.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.accent)
                }
            } else if (tasks.isEmpty()) {
                LazyColumn(
                    contentPadding = PaddingValues(start = margin, end = margin, top = 16.dp, bottom = 64.dp + bottomOverlayInset),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    item {
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
                                    if (selectedDownloaderFilter != null) "下载器「$selectedDownloaderFilter」暂无活动种子，可右上角切换为全部下载器。"
                                    else "新添加的种子或订阅下载会实时显示在这里（每 4 秒自动刷新）。",
                                    color = colors.textSecondary,
                                    fontSize = 13.sp,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                    }
                }
            } else {
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(start = margin, end = margin, top = 14.dp, bottom = 84.dp + bottomOverlayInset),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(tasks, key = { "${it.downloader}-${it.hash}-${it.title}" }) { task ->
                        val isPaused = task.state.contains("pause", ignoreCase = true) ||
                            task.state.contains("stop", ignoreCase = true)
                        val dlCfg = downloaders.firstOrNull { it.name.equals(task.downloader, ignoreCase = true) }
                        CinematicPanel(padding = 14.dp, showsShadow = false) {
                            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Row(
                                        modifier = Modifier.weight(1f),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        NativeEntityLogo(
                                            kind = "downloader",
                                            value = dlCfg?.type?.ifBlank { task.downloader } ?: task.downloader,
                                            size = 34.dp,
                                            cornerRadius = 9.dp,
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = task.name.ifBlank { task.title },
                                                color = colors.textPrimary,
                                                fontSize = 15.sp,
                                                fontWeight = FontWeight.Bold,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                            Text(
                                                text = listOfNotNull(
                                                    task.downloader.takeIf { it.isNotBlank() },
                                                    task.siteName.takeIf { it.isNotBlank() },
                                                    formatBytes(task.size),
                                                ).joinToString(" · "),
                                                color = colors.textSecondary,
                                                fontSize = 12.sp,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                        }
                                    }
                                    Row {
                                        IconButton(onClick = {
                                            scope.launch {
                                                val (ok, msg) = if (isPaused) {
                                                    repository.startDownload(task.hash, task.downloader)
                                                } else {
                                                    repository.stopDownload(task.hash, task.downloader)
                                                }
                                                if (ok) {
                                                    val next = if (isPaused) "downloading" else "paused"
                                                    tasks = tasks.map { if (it.hash == task.hash) it.copy(state = next) else it }
                                                }
                                                snackbar?.showSnackbar(msg)
                                            }
                                        }) {
                                            Icon(
                                                if (isPaused) Icons.Rounded.PlayArrow else Icons.Rounded.Pause,
                                                contentDescription = if (isPaused) "恢复下载" else "暂停下载",
                                                tint = colors.textPrimary,
                                            )
                                        }
                                        IconButton(onClick = { confirmDeleteTask = task }) {
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

    // 下载器筛选底部面板（展示各下载器品牌图标）
    if (showFilterSheet) {
        NativeGlassSheet(onDismissRequest = { showFilterSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("按下载器筛选", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NativeAdaptivePill(
                        title = "全部下载器",
                        leadingContent = {
                            NativeEntityLogo("downloader", "default", size = 18.dp, cornerRadius = 5.dp)
                        },
                        selected = selectedDownloaderFilter == null,
                        onClick = {
                            selectedDownloaderFilter = null
                            showFilterSheet = false
                        },
                    )
                    downloaders.forEach { dl ->
                        NativeAdaptivePill(
                            title = dl.name,
                            leadingContent = {
                                NativeEntityLogo("downloader", dl.type.ifBlank { dl.name }, size = 18.dp, cornerRadius = 5.dp)
                            },
                            selected = selectedDownloaderFilter == dl.name,
                            onClick = {
                                selectedDownloaderFilter = dl.name
                                showFilterSheet = false
                            },
                        )
                    }
                }
                Spacer(Modifier.height(20.dp))
            }
        }
    }

    // 删除下载任务二次确认弹窗
    confirmDeleteTask?.let { target ->
        AlertDialog(
            onDismissRequest = { confirmDeleteTask = null },
            title = { Text("确认移除下载任务") },
            text = { Text("确定要从下载器「${target.downloader}」中移除任务「${target.name.ifBlank { target.title }}」吗？") },
            dismissButton = {
                TextButton(onClick = { confirmDeleteTask = null }) { Text("取消") }
            },
            confirmButton = {
                TextButton(onClick = {
                    val deleting = target
                    confirmDeleteTask = null
                    scope.launch {
                        val (ok, msg) = repository.removeDownload(deleting.hash, deleting.downloader)
                        if (ok) {
                            tasks = tasks.filterNot { it.hash == deleting.hash }
                        }
                        snackbar?.showSnackbar(msg)
                    }
                }) {
                    Text("确认移除", color = colors.danger)
                }
            },
        )
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
