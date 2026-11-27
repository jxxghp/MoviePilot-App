package com.moviepilot.feature.discover

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeInlineChipRowSkeleton
import com.moviepilot.designsystem.NativeSkeletonBlock
import com.moviepilot.designsystem.ProvideSkeletonShimmer
import com.moviepilot.designsystem.SkeletonSurfaceRole
import com.moviepilot.designsystem.nativePosterGridSkeletonItems
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.QueueTrackSpec
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaServerBrowseItemDto
import com.moviepilot.rustbridge.MediaServerClientDto
import com.moviepilot.rustbridge.MediaServerFilterOptionsDto
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 原生媒体服务器浏览页（1:1 对齐 iOS `NativeMediaServerLibraryPage.swift`）：
 * - 支持多媒体服务器与同服务器多媒体库横向切换
 * - 支持防抖关键词搜索、排序（入库时间/发行日期/评分/标题）、风格、年份与观看状态（全部/未看/已看）筛选
 * - 响应式多列海报网格 + 触底分页 + 下拉刷新 + 顶部状态栏渐进模糊
 * - 点击已入库影片或音乐直连 `/api/v1/mediaserver/stream-info` 启动原生认证播放，剧集/详情条目推入原生详情页
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediaServerLibraryScreen(
    repository: MoviePilotRepository,
    initialLibrary: MediaServerLibraryDto,
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit,
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
    onOpenServerDetail: ((itemId: String, server: String, title: String, poster: String?) -> Unit)? = null,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()
    val gridState = rememberLazyGridState()

    var activeServer by remember(initialLibrary) { mutableStateOf(initialLibrary.server) }
    var activeServerType by remember(initialLibrary) { mutableStateOf(initialLibrary.serverType) }
    var activeLibraryId by remember(initialLibrary) { mutableStateOf(initialLibrary.id) }
    var activeLibraryName by remember(initialLibrary) { mutableStateOf(initialLibrary.name.ifBlank { "媒体库" }) }
    var activeLibraryType by remember(initialLibrary) { mutableStateOf(initialLibrary.type) }

    var clients by remember { mutableStateOf<List<MediaServerClientDto>>(emptyList()) }
    var libraries by remember { mutableStateOf<List<MediaServerLibraryDto>>(emptyList()) }
    var filterOptions by remember { mutableStateOf(MediaServerFilterOptionsDto()) }

    var sortBy by remember { mutableStateOf("date_created") }
    var selectedGenre by remember { mutableStateOf("") }
    var selectedYear by remember { mutableStateOf<Int?>(null) }
    var playedFilter by remember { mutableStateOf("all") }
    var searchText by remember { mutableStateOf("") }
    var committedSearch by remember { mutableStateOf("") }

    var items by remember { mutableStateOf<List<MediaServerBrowseItemDto>>(emptyList()) }
    var totalCount by remember { mutableStateOf(0) }
    var hasMore by remember { mutableStateOf(false) }
    var isLoadingLibraries by remember { mutableStateOf(true) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var isLoadingMore by remember { mutableStateOf(false) }
    var statusTip by remember { mutableStateOf<String?>(null) }

    val isMusicLib = activeLibraryType.equals("音乐", ignoreCase = true) ||
        activeLibraryType.equals("music", ignoreCase = true)
    val columns = if (isMusicLib) AdaptiveDeviceLayout.squareGridColumns() else AdaptiveDeviceLayout.posterGridColumns()

    suspend fun reload(showSpinner: Boolean = true) {
        if (showSpinner) isLoading = true
        val itemType = if (activeLibraryType.lowercase() in listOf("合集", "boxsets", "boxset", "collections")) "BoxSet" else null
        val page = repository.fetchMediaServerBrowse(
            server = activeServer,
            libraryId = activeLibraryId.ifBlank { null },
            sortBy = sortBy,
            sortOrder = if (sortBy == "name") "asc" else "desc",
            genre = selectedGenre,
            year = selectedYear,
            playedFilter = playedFilter,
            keyword = committedSearch,
            startIndex = 0,
            limit = 30,
            itemType = itemType,
        )
        items = page.items
        totalCount = page.totalCount
        hasMore = page.hasMore
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(Unit) {
        coroutineScope {
            isLoadingLibraries = true
            clients = repository.fetchMediaServerClients()
            if (clients.isNotEmpty() && clients.none { it.name == activeServer }) {
                val matched = clients.firstOrNull { it.name.equals(activeServer, ignoreCase = true) }
                    ?: clients.firstOrNull { it.type.equals(activeServer, ignoreCase = true) }
                    ?: clients.first()
                activeServer = matched.name
                activeServerType = matched.type
            } else {
                clients.firstOrNull { it.name == activeServer }?.let { activeServerType = it.type }
            }
            libraries = repository.fetchMediaServerLibraries(activeServer.ifBlank { null })
            isLoadingLibraries = false
            if (activeLibraryId.isBlank() && libraries.isNotEmpty()) {
                activeLibraryId = libraries.first().id
                activeLibraryName = libraries.first().name
                activeLibraryType = libraries.first().type
            }
            filterOptions = repository.fetchMediaServerFilters(activeServer, activeLibraryId.ifBlank { null })
            reload(showSpinner = true)
        }
    }

    // 搜索防抖
    LaunchedEffect(searchText) {
        val trimmed = searchText.trim()
        if (trimmed == committedSearch) return@LaunchedEffect
        delay(350)
        committedSearch = trimmed
        reload(showSpinner = false)
    }

    LaunchedEffect(activeServer, activeLibraryId, sortBy, selectedGenre, selectedYear, playedFilter) {
        if (activeServer.isNotBlank()) {
            filterOptions = repository.fetchMediaServerFilters(activeServer, activeLibraryId.ifBlank { null })
            reload(showSpinner = items.isEmpty())
        }
    }

    val activeLibIdx = libraries.indexOfFirst { it.id == activeLibraryId }.coerceAtLeast(0)

    ExpressiveTintedScaffold(
        title = activeLibraryName,
        subtitle = activeServer.takeIf { it.isNotBlank() },
        onBack = onBack,
        headerExtra = if (libraries.isNotEmpty()) {
            {
                ExpressivePillTabRow(
                    tabs = libraries.map { it.name },
                    selectedIndex = activeLibIdx,
                    onSelect = { idx ->
                        val lib = libraries.getOrNull(idx) ?: return@ExpressivePillTabRow
                        if (lib.id != activeLibraryId) {
                            activeLibraryId = lib.id
                            activeLibraryName = lib.name
                            activeLibraryType = lib.type
                            selectedGenre = ""
                            selectedYear = null
                        }
                    },
                    scrollable = true,
                    onTintedHeader = true,
                )
            }
        } else if (isLoadingLibraries) {
            {
                NativeInlineChipRowSkeleton(
                    widths = listOf(84.dp, 92.dp, 76.dp, 88.dp),
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    role = SkeletonSurfaceRole.Tile,
                )
            }
        } else {
            null
        },
    ) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { reload(showSpinner = false) }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            ProvideSkeletonShimmer {
            LazyVerticalGrid(
                state = gridState,
                columns = GridCells.Fixed(columns),
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = if (compactHeight) 10.dp else 16.dp,
                    bottom = 24.dp + bottomOverlayInset,
                ),
                horizontalArrangement = Arrangement.spacedBy(11.dp),
                verticalArrangement = Arrangement.spacedBy(if (compactHeight) 11.dp else 15.dp),
            ) {
                // 1. 多服务器切换栏（展示真实 Emby / Jellyfin / Plex / 飞牛 / 绿联 / 极空间 品牌 Logo）
                if (clients.size > 1) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(clients) { cli ->
                                NativeAdaptivePill(
                                    title = cli.name,
                                    leadingContent = {
                                        NativeEntityLogo(
                                            kind = "mediaserver",
                                            value = cli.type.ifBlank { cli.name },
                                            size = 18.dp,
                                            cornerRadius = 5.dp,
                                        )
                                    },
                                    selected = cli.name == activeServer,
                                    onClick = {
                                        if (cli.name != activeServer) {
                                            activeServer = cli.name
                                            activeServerType = cli.type
                                            activeLibraryId = ""
                                            selectedGenre = ""
                                            selectedYear = null
                                            scope.launch {
                                                isLoadingLibraries = true
                                                libraries = repository.fetchMediaServerLibraries(cli.name)
                                                isLoadingLibraries = false
                                                libraries.firstOrNull()?.let { first ->
                                                    activeLibraryId = first.id
                                                    activeLibraryName = first.name
                                                    activeLibraryType = first.type
                                                }
                                            }
                                        }
                                    },
                                )
                            }
                        }
                    }
                }

                // 2. 库内搜索框
                item(span = { GridItemSpan(maxLineSpan) }) {
                    CinematicGlassSurface(
                        shape = RoundedCornerShape(18.dp),
                        useLiveBackdropBlur = false,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 14.dp, vertical = if (compactHeight) 7.dp else 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                            Box(modifier = Modifier.weight(1f)) {
                                if (searchText.isEmpty()) {
                                    Text("搜索「$activeLibraryName」…", color = colors.textMuted, fontSize = 14.sp)
                                }
                                BasicTextField(
                                    value = searchText,
                                    onValueChange = { searchText = it },
                                    singleLine = true,
                                    textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp),
                                    cursorBrush = SolidColor(colors.accent),
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                            if (searchText.isNotEmpty()) {
                                IconButton(onClick = { searchText = "" }, modifier = Modifier.size(22.dp)) {
                                    Icon(Icons.Rounded.Close, contentDescription = "清除", tint = colors.textMuted, modifier = Modifier.size(16.dp))
                                }
                            }
                        }
                    }
                }

                // 3. 排序 / 观看状态 / 风格 / 年份筛选胶囊
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            val sorts = listOf(
                                "date_created" to "最近入库",
                                "premiere_date" to "发行日期",
                                "rating" to "评分最高",
                                "name" to "名称排序",
                            )
                            items(sorts) { (key, label) ->
                                NativeAdaptivePill(
                                    title = label,
                                    selected = sortBy == key,
                                    onClick = { sortBy = key },
                                )
                            }
                            items(listOf("all" to "全部状态", "unplayed" to "未观看", "played" to "已观看")) { (key, label) ->
                                NativeAdaptivePill(
                                    title = label,
                                    selected = playedFilter == key,
                                    onClick = { playedFilter = key },
                                )
                            }
                        }
                        if (filterOptions.genres.isNotEmpty() || filterOptions.years.isNotEmpty()) {
                            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                item {
                                    NativeAdaptivePill(
                                        title = "全部类型",
                                        selected = selectedGenre.isEmpty(),
                                        onClick = { selectedGenre = "" },
                                    )
                                }
                                items(filterOptions.genres.take(12)) { g ->
                                    NativeAdaptivePill(
                                        title = g,
                                        selected = selectedGenre == g,
                                        onClick = { selectedGenre = if (selectedGenre == g) "" else g },
                                    )
                                }
                                items(filterOptions.years.take(8)) { y ->
                                    NativeAdaptivePill(
                                        title = y.toString(),
                                        selected = selectedYear == y,
                                        onClick = { selectedYear = if (selectedYear == y) null else y },
                                    )
                                }
                            }
                        }
                    }
                }

                // 4. 统计汇总与状态反馈（带服务器品牌图标）
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            if (activeServer.isNotBlank()) {
                                NativeEntityLogo(
                                    kind = "mediaserver",
                                    value = activeServerType.ifBlank { activeServer },
                                    size = 18.dp,
                                    cornerRadius = 5.dp,
                                )
                            }
                            if (isLoading && totalCount == 0) {
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier.size(width = 108.dp, height = 13.dp),
                                )
                            } else {
                                Text(
                                    text = if (totalCount > 0) "共 $totalCount 项 · $activeServer" else activeServer,
                                    color = colors.textSecondary,
                                    fontSize = 12.sp,
                                )
                            }
                        }
                        statusTip?.let { tip ->
                            NativeAdaptiveBadge(tip, tint = colors.warning)
                        }
                    }
                }

                // 5. 内容网格
                if (isLoading && items.isEmpty()) {
                    nativePosterGridSkeletonItems(
                        columns = columns,
                        aspectRatio = if (isMusicLib) 1f else 2f / 3f,
                        inPanel = isMusicLib,
                    )
                } else if (items.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        CinematicPanel(padding = 24.dp) {
                            Text("当前筛选条件下暂无媒体内容", color = colors.textSecondary, fontSize = 14.sp)
                        }
                    }
                } else {
                    itemsIndexed(items, key = { idx, it -> "${it.itemId}_$idx" }) { index, entry ->
                        if (index >= items.size - 6 && hasMore && !isLoadingMore) {
                            LaunchedEffect(items.size) {
                                isLoadingMore = true
                                val next = repository.fetchMediaServerBrowse(
                                    server = activeServer,
                                    libraryId = activeLibraryId.ifBlank { null },
                                    sortBy = sortBy,
                                    sortOrder = if (sortBy == "name") "asc" else "desc",
                                    genre = selectedGenre,
                                    year = selectedYear,
                                    playedFilter = playedFilter,
                                    keyword = committedSearch,
                                    startIndex = items.size,
                                    limit = 30,
                                )
                                val seen = items.map { it.itemId }.toSet()
                                items = items + next.items.filter { it.itemId !in seen }
                                hasMore = next.hasMore && next.items.isNotEmpty()
                                isLoadingMore = false
                            }
                        }

                        val ratio = if (isMusicLib) 1f else (2f / 3f)
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    val resolvedSrv = entry.server.ifBlank { activeServer }
                                    val isDirectAudioTrack = entry.type.equals("Audio", ignoreCase = true)
                                    val isMusicAlbumEntry = entry.type.equals("MusicAlbum", ignoreCase = true) ||
                                        (isMusicLib && !isDirectAudioTrack)
                                    if (!isDirectAudioTrack && onOpenServerDetail != null && entry.itemId.isNotBlank()) {
                                        onOpenServerDetail(entry.itemId, resolvedSrv, entry.title, entry.imageUrl)
                                    } else {
                                        scope.launch {
                                            statusTip = null
                                            val manifest = repository.fetchVideoStreamInfo(entry.itemId, resolvedSrv)
                                            if (manifest != null) {
                                                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                                val siblingAudio = if (isDirectAudioTrack || isMusicLib) {
                                                    items.filter { it.type.equals("Audio", ignoreCase = true) || (!isMusicAlbumEntry && isMusicLib) }
                                                } else {
                                                    emptyList()
                                                }
                                                val audioQueue = siblingAudio.mapIndexed { qIdx, a ->
                                                    val aSrv = a.server.ifBlank { resolvedSrv }
                                                    MediaPlaybackRequest(
                                                        url = "",
                                                        title = a.title,
                                                        subtitle = listOfNotNull(aSrv.ifBlank { null }, a.year.ifBlank { null }).joinToString(" · "),
                                                        artworkUrl = a.imageUrl,
                                                        isAudio = true,
                                                        itemId = a.itemId,
                                                        server = aSrv,
                                                        queueIndex = qIdx,
                                                        lazySpec = QueueTrackSpec.MediaServerItem(a.itemId, aSrv),
                                                    )
                                                }
                                                val curQIdx = siblingAudio.indexOfFirst { it.itemId == entry.itemId }.coerceAtLeast(0)
                                                onPlayMedia(
                                                    MediaPlaybackRequest(
                                                        url = manifest.contentUrl,
                                                        title = manifest.title.ifBlank { entry.title },
                                                        subtitle = listOfNotNull(
                                                            resolvedSrv.ifBlank { null },
                                                            entry.year.ifBlank { null },
                                                        ).joinToString(" · "),
                                                        artworkUrl = entry.imageUrl,
                                                        isAudio = manifest.mediaType == "audio" || isMusicLib,
                                                        lyricsLrc = lrc,
                                                        headers = manifest.headers,
                                                        sameOriginHeaders = manifest.sameOriginHeaders,
                                                        streamHeaders = manifest.streamHeaders,
                                                        proxyFallbackUrl = manifest.proxyFallbackUrl,
                                                        activeRouteKind = manifest.activeRouteKind,
                                                        fallbackRoutes = manifest.fallbackRoutes,
                                                        originUrl = manifest.originUrl,
                                                        itemId = manifest.itemId,
                                                        server = manifest.server.ifBlank { resolvedSrv },
                                                        serverType = manifest.serverType,
                                                        mediaSourceId = manifest.mediaSourceId.orEmpty(),
                                                        playSessionId = manifest.playSessionId,
                                                        progressSyncMode = manifest.progressSyncMode,
                                                        resumePositionMs = manifest.resumePositionMs,
                                                        subtitles = manifest.subtitles.map {
                                                            SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                                                        },
                                                        queue = audioQueue,
                                                        queueIndex = curQIdx,
                                                        danmakuEnabled = manifest.danmakuEnabled,
                                                        seriesName = manifest.seriesName,
                                                        seasonNumber = manifest.seasonNumber,
                                                        episodeNumber = manifest.episodeNumber,
                                                        year = manifest.year,
                                                        tmdbId = manifest.tmdbId,
                                                        fileName = manifest.fileName,
                                                        fileSize = manifest.fileSize,
                                                    ),
                                                )
                                            } else if (onOpenServerDetail != null && entry.itemId.isNotBlank()) {
                                                onOpenServerDetail(entry.itemId, resolvedSrv, entry.title, entry.imageUrl)
                                            } else {
                                                onOpenMedia(
                                                    MediaCardItem(
                                                        tmdbId = entry.tmdbId,
                                                        mediaId = entry.mediaId ?: entry.itemId,
                                                        serverItemId = entry.itemId,
                                                        serverName = resolvedSrv,
                                                        serverType = entry.serverType.ifBlank { activeServerType },
                                                        title = entry.title,
                                                        year = entry.year,
                                                        type = if (MoviePilotRepository.isTvType(entry.type)) "电视剧" else "电影",
                                                        posterPath = entry.imageUrl,
                                                        inLibrary = true,
                                                    ),
                                                )
                                            }
                                        }
                                    }
                                },
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(ratio)
                                    .clip(RoundedCornerShape(13.dp))
                                    .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.22f), Color(0xFF28203A))))
                                    .border(0.6.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(13.dp)),
                            ) {
                                if (!entry.imageUrl.isNullOrBlank()) {
                                    AsyncImage(
                                        model = entry.imageUrl,
                                        contentDescription = entry.title,
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier.fillMaxSize(),
                                    )
                                }
                                if (entry.played) {
                                    Box(
                                        modifier = Modifier
                                            .align(Alignment.TopEnd)
                                            .padding(6.dp)
                                            .size(20.dp)
                                            .clip(CircleShape)
                                            .background(Color(0xFF2CC856)),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(Icons.Rounded.Check, contentDescription = "已观看", tint = Color.White, modifier = Modifier.size(12.dp))
                                    }
                                } else if ((entry.unplayedCount ?: 0) > 0) {
                                    Box(
                                        modifier = Modifier
                                            .align(Alignment.TopEnd)
                                            .padding(6.dp)
                                            .clip(CircleShape)
                                            .background(colors.accent)
                                            .padding(horizontal = 6.dp, vertical = 2.dp),
                                    ) {
                                        Text("${entry.unplayedCount}", color = colors.primaryButtonFg, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                    }
                                }
                                Box(
                                    modifier = Modifier
                                        .align(Alignment.BottomEnd)
                                        .padding(6.dp)
                                        .size(26.dp)
                                        .clip(CircleShape)
                                        .background(Color.Black.copy(alpha = 0.56f)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Rounded.PlayArrow, contentDescription = "播放", tint = Color.White, modifier = Modifier.size(16.dp))
                                }
                            }
                            Spacer(Modifier.height(6.dp))
                            Text(
                                text = entry.title,
                                color = colors.textPrimary,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            val sub = entry.subtitle.ifBlank { entry.year }
                            if (sub.isNotBlank()) {
                                Text(sub, color = colors.textMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                    if (isLoadingMore) {
                        nativePosterGridSkeletonItems(
                            columns = columns,
                            count = columns,
                            aspectRatio = if (isMusicLib) 1f else 2f / 3f,
                            inPanel = isMusicLib,
                        )
                    }
                }
            }
            }
        }
    }
}
