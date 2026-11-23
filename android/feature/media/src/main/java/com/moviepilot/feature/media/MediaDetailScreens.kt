package com.moviepilot.feature.media

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
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.BookmarkAdded
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativePosterCard
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaEpisodeDto
import com.moviepilot.rustbridge.MediaPersonDto
import com.moviepilot.rustbridge.MediaSeasonDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.SubscribeItemDto
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * 影视 / 剧集 / 豆瓣详情页（1:1 复刻 iOS `NativeMediaDetailPage.swift` 动态滚动物理 + Android 导航压栈最佳实践）：
 * - 固定底层海报背景（竖屏手机优先竖版高清单张海报，宽屏优先剧照），上滚时 0.08x 视差、渐进柔焦、5 段软边溶解与淡出；
 * - 前景透明 Logo/大标题、元数据、评分与类型胶囊随正文以 1.0x 正常上滚，产生电影感景深分离；
 * - 离开首屏后状态栏下方平滑浮现 GPU 渐进模糊罩，彻底避免滚动图文与系统状态栏重叠；
 * - 点击演职员头像推入独立全屏 `PersonDetailScreen` 页面（而非底部弹窗），支持系统返回手势逐级回退。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun MediaDetailScreen(
    item: MediaCardItem,
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onSearchResource: (String) -> Unit,
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
    onOpenPerson: (MediaPersonDto) -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit = {},
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val config = LocalConfiguration.current
    val isPortraitPhone = config.screenWidthDp < config.screenHeightDp && config.screenWidthDp < 680
    val heroHeight = if (isPortraitPhone) 450.dp else 400.dp
    val density = LocalDensity.current
    val heroHeightPx = with(density) { heroHeight.toPx().coerceAtLeast(1f) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val localHaze = remember { HazeState() }

    var detail by remember(item.resolvedId) { mutableStateOf(item) }
    var credits by remember(item.resolvedId) { mutableStateOf<List<MediaPersonDto>>(emptyList()) }
    var seasons by remember(item.resolvedId) { mutableStateOf<List<MediaSeasonDto>>(emptyList()) }
    val episodesBySeason = remember(item.resolvedId) { mutableStateMapOf<Int, List<MediaEpisodeDto>>() }
    var expandedSeason by remember(item.resolvedId) { mutableStateOf<Int?>(null) }
    var expandOverview by remember(item.resolvedId) { mutableStateOf(false) }
    var subscribedSeasons by remember(item.resolvedId) { mutableStateOf<Set<Int>>(emptySet()) }
    var subscribedMovie by remember(item.resolvedId) { mutableStateOf(false) }
    var feedback by remember(item.resolvedId) { mutableStateOf<String?>(null) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadDetail() {
        coroutineScope {
            val detailDef = async { repository.fetchMediaDetail(item) }
            val creditsDef = async { repository.fetchMediaCredits(item) }
            val logoDef = async { repository.fetchHeroLogo(item) }
            val enriched = detailDef.await()
            val logo = logoDef.await()
            if (enriched != null) {
                detail = enriched.copy(
                    posterPath = item.posterPath?.takeIf { it.isNotBlank() } ?: enriched.posterPath?.takeIf { it.isNotBlank() },
                    backdropPath = enriched.backdropPath?.takeIf { it.isNotBlank() } ?: item.backdropPath?.takeIf { it.isNotBlank() },
                    logoPath = enriched.logoPath?.takeIf { it.isNotBlank() } ?: logo?.takeIf { it.isNotBlank() } ?: item.logoPath,
                    genres = enriched.genres.ifEmpty { item.genres },
                )
            } else if (!logo.isNullOrBlank()) {
                detail = detail.copy(logoPath = logo)
            }
            credits = creditsDef.await()
            val resolvedTmdbId = detail.tmdbId ?: item.tmdbId
            if (detail.type == "电视剧" && resolvedTmdbId != null) {
                seasons = repository.fetchMediaSeasons(resolvedTmdbId)
            }
            isRefreshing = false
        }
    }

    LaunchedEffect(item.resolvedId) { loadDetail() }

    val scrollUpPx by remember {
        derivedStateOf {
            if (listState.firstVisibleItemIndex == 0) {
                listState.firstVisibleItemScrollOffset.toFloat().coerceAtLeast(0f)
            } else {
                heroHeightPx
            }
        }
    }
    val progress = (scrollUpPx / (heroHeightPx * 0.62f)).coerceIn(0f, 1f)
    val eased = progress * progress * (3f - 2f * progress)

    val isTv = detail.type == "电视剧"
    val primarySeason = seasons.firstOrNull()?.seasonNumber ?: 1
    val primarySubscribed = if (isTv) primarySeason in subscribedSeasons else subscribedMovie

    Box(modifier = Modifier.fillMaxSize()) {
        // 1. 底层固定沉浸海报 + 滚动正文（共同作为顶部渐进状态栏模糊源）
        Box(
            modifier = Modifier
                .fillMaxSize()
                .hazeSource(localHaze),
        ) {
            if (colors.isDark) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFF0A0A16).copy(alpha = ((1f - eased * 1.15f).coerceAtLeast(0f)) * 0.55f)),
                )
            }

            if (progress < 0.99f) {
                val backdropHeight = heroHeight * 1.06f
                val parallaxY = -scrollUpPx.coerceAtMost(heroHeightPx) * 0.08f
                val maskShiftY = -scrollUpPx * 0.85f
                val visibility = (1f - eased * 0.96f).coerceIn(0f, 1f)
                val fadeBase = androidx.compose.material3.MaterialTheme.colorScheme.background

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(backdropHeight)
                        .graphicsLayer {
                            translationY = parallaxY
                            alpha = visibility
                            compositingStrategy = CompositingStrategy.Offscreen
                        }
                        .drawWithContent {
                            drawContent()
                            val h = size.height.coerceAtLeast(1f)
                            val shiftFraction = (maskShiftY / h).coerceIn(-0.95f, 0f)
                            val p1 = (0.58f + shiftFraction).coerceIn(0f, 1f)
                            val p2 = (0.72f + shiftFraction).coerceIn(p1, 1f)
                            val p3 = (0.86f + shiftFraction).coerceIn(p2, 1f)
                            val p4 = (1.00f + shiftFraction).coerceIn(p3, 1f)
                            drawRect(
                                brush = Brush.verticalGradient(
                                    0.0f to Color.Black,
                                    p1 to Color.Black,
                                    p2 to Color.Black.copy(alpha = 0.86f),
                                    p3 to Color.Black.copy(alpha = 0.38f),
                                    p4 to Color.Transparent,
                                    1.0f to Color.Transparent,
                                ),
                                blendMode = BlendMode.DstIn,
                            )
                        },
                ) {
                    val artCandidates = remember(detail.posterPath, detail.backdropPath, item.posterPath, item.backdropPath, isPortraitPhone) {
                        if (isPortraitPhone) {
                            listOfNotNull(
                                detail.posterPath?.takeIf { it.isNotBlank() },
                                item.posterPath?.takeIf { it.isNotBlank() },
                                detail.backdropPath?.takeIf { it.isNotBlank() },
                                item.backdropPath?.takeIf { it.isNotBlank() },
                            ).distinct()
                        } else {
                            listOfNotNull(
                                detail.backdropPath?.takeIf { it.isNotBlank() },
                                item.backdropPath?.takeIf { it.isNotBlank() },
                                detail.posterPath?.takeIf { it.isNotBlank() },
                                item.posterPath?.takeIf { it.isNotBlank() },
                            ).distinct()
                        }
                    }
                    var artIdx by remember(artCandidates) { mutableStateOf(0) }
                    val resolvedHeroArt = artCandidates.getOrNull(artIdx)
                    if (!resolvedHeroArt.isNullOrBlank()) {
                        AsyncImage(
                            model = resolvedHeroArt,
                            contentDescription = detail.title,
                            contentScale = ContentScale.Crop,
                            onError = { if (artIdx + 1 < artCandidates.size) artIdx++ },
                            modifier = Modifier
                                .fillMaxSize()
                                .blur((eased * 14f).dp),
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(Brush.verticalGradient(listOf(colors.accent.copy(alpha = 0.45f), Color(0xFF231C35)))),
                        )
                    }
                    // 仅底部平滑融底托起 Logo 与信息区，顶部首屏保持 100% 清透无遮挡
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    0.0f to Color.Transparent,
                                    0.48f to Color.Transparent,
                                    0.68f to fadeBase.copy(alpha = if (colors.isDark) 0.38f else 0.42f),
                                    0.88f to fadeBase.copy(alpha = if (colors.isDark) 0.86f else 0.88f),
                                    1.0f to fadeBase,
                                ),
                            ),
                    )
                }
            }

            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { loadDetail() }
                },
                modifier = Modifier.fillMaxSize(),
            ) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 48.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    // 1. 前景透明片名 Logo / 标题、元数据、评分与类型胶囊（1.0x 随正文自然上滚）
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(heroHeight),
                        ) {
                            Column(
                                modifier = Modifier
                                    .align(Alignment.BottomCenter)
                                    .fillMaxWidth()
                                    .padding(horizontal = margin, vertical = 14.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                var logoReady by remember(detail.logoPath) { mutableStateOf(false) }
                                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    if (!logoReady) {
                                        Text(
                                            text = detail.title,
                                            color = if (colors.isDark) Color.White else colors.textPrimary,
                                            fontSize = 28.sp,
                                            fontWeight = FontWeight.ExtraBold,
                                            textAlign = TextAlign.Center,
                                            maxLines = 2,
                                        )
                                    }
                                    if (!detail.logoPath.isNullOrBlank()) {
                                        AsyncImage(
                                            model = detail.logoPath,
                                            contentDescription = detail.title,
                                            contentScale = ContentScale.Fit,
                                            onSuccess = { logoReady = true },
                                            modifier = Modifier
                                                .fillMaxWidth(0.74f)
                                                .height(74.dp),
                                        )
                                    }
                                }
                                val metaLine = buildList {
                                    if (detail.year.isNotBlank()) add(detail.year)
                                    if (detail.type.isNotBlank()) add(detail.type)
                                    if (isTv && (detail.numberOfSeasons ?: seasons.size) > 0) {
                                        add("${detail.numberOfSeasons ?: seasons.size} 季")
                                    } else if ((detail.runtime ?: 0) > 0) {
                                        add("${detail.runtime} 分钟")
                                    }
                                    if (!detail.contentRating.isNullOrBlank()) add(detail.contentRating!!)
                                }.joinToString(" · ")
                                if (metaLine.isNotBlank()) {
                                    Text(
                                        text = metaLine,
                                        color = if (colors.isDark) Color.White.copy(alpha = 0.86f) else colors.textSecondary,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Medium,
                                        textAlign = TextAlign.Center,
                                    )
                                }
                                if (detail.voteAverage > 0.0) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Icon(Icons.Rounded.Star, contentDescription = null, tint = Color(0xFFFFC845), modifier = Modifier.size(17.dp))
                                        Text(String.format("%.1f", detail.voteAverage), color = Color(0xFFFFC845), fontWeight = FontWeight.Bold, fontSize = 15.sp)
                                    }
                                }
                                if (detail.genres.isNotEmpty()) {
                                    FlowRow(
                                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                                        verticalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        detail.genres.take(5).forEach { g ->
                                            Box(
                                                modifier = Modifier
                                                    .clip(CircleShape)
                                                    .background(colors.chipFill)
                                                    .border(0.6.dp, colors.chipBorder, CircleShape)
                                                    .padding(horizontal = 12.dp, vertical = 4.dp),
                                            ) {
                                                Text(g, color = colors.textPrimary.copy(alpha = 0.92f), fontSize = 12.sp, fontWeight = FontWeight.Medium)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2. 核心操作栏（纯白主按钮 + 玻璃次按钮 + 媒体库直放）
                    item {
                        Column(
                            modifier = Modifier.padding(horizontal = margin),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                Button(
                                    onClick = {
                                        scope.launch {
                                            val ok = repository.createOrUpdateSubscription(
                                                SubscribeItemDto(
                                                    name = detail.title,
                                                    year = detail.year,
                                                    type = detail.type,
                                                    season = if (isTv) primarySeason else null,
                                                    mediaSource = detail.source,
                                                    mediaId = detail.tmdbId?.toString() ?: detail.doubanId ?: detail.resolvedId,
                                                ),
                                            )
                                            if (isTv) subscribedSeasons = subscribedSeasons + primarySeason else subscribedMovie = true
                                            feedback = if (ok) "已添加到我的订阅" else "已提交订阅请求"
                                        }
                                    },
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = if (primarySubscribed) colors.success else Color.White,
                                        contentColor = if (primarySubscribed) Color.White else Color(0xFF14111D),
                                    ),
                                    shape = CircleShape,
                                    modifier = Modifier.weight(1f).height(50.dp),
                                ) {
                                    Icon(
                                        if (primarySubscribed) Icons.Rounded.BookmarkAdded else Icons.Outlined.BookmarkBorder,
                                        contentDescription = null,
                                        modifier = Modifier.size(19.dp),
                                    )
                                    Spacer(Modifier.width(6.dp))
                                    Text(
                                        text = when {
                                            primarySubscribed -> "已订阅"
                                            isTv -> "订阅第 $primarySeason 季"
                                            else -> "添加订阅"
                                        },
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Bold,
                                    )
                                }

                                CinematicGlassSurface(
                                    shape = CircleShape,
                                    blurRadiusDp = 18.dp,
                                    useLiveBackdropBlur = false,
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(50.dp)
                                        .clickable { onSearchResource(detail.title) },
                                ) {
                                    Row(
                                        modifier = Modifier.fillMaxSize(),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.Center,
                                    ) {
                                        Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(19.dp))
                                        Spacer(Modifier.width(6.dp))
                                        Text("搜索资源", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    }
                                }
                            }

                            if (detail.inLibrary) {
                                Button(
                                    onClick = {
                                        scope.launch {
                                            feedback = null
                                            val candidateId = detail.mediaId?.takeIf { it.isNotBlank() }
                                                ?: repository.searchMedia(detail.title, "library", 1).firstOrNull()?.mediaId
                                            val manifest = candidateId?.let { repository.fetchVideoStreamInfo(it, null) }
                                            if (manifest != null) {
                                                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                                onPlayMedia(
                                                    MediaPlaybackRequest(
                                                        url = manifest.contentUrl,
                                                        title = manifest.title.ifBlank { detail.title },
                                                        subtitle = "${detail.year} · ${detail.type}",
                                                        artworkUrl = detail.posterPath,
                                                        isAudio = manifest.mediaType == "audio",
                                                        lyricsLrc = lrc,
                                                        headers = manifest.headers,
                                                        itemId = manifest.itemId,
                                                        server = manifest.server,
                                                        resumePositionMs = manifest.resumePositionMs,
                                                        subtitles = manifest.subtitles.map {
                                                            SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                                                        },
                                                    ),
                                                )
                                            } else {
                                                feedback = "当前媒体服务器未找到该条目的直放流"
                                            }
                                        }
                                    },
                                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = Color.White),
                                    shape = CircleShape,
                                    modifier = Modifier.fillMaxWidth().height(46.dp),
                                ) {
                                    Icon(Icons.Rounded.PlayArrow, contentDescription = null)
                                    Spacer(Modifier.width(6.dp))
                                    Text("立即原生播放", fontWeight = FontWeight.SemiBold)
                                }
                            }

                            feedback?.let {
                                Text(it, color = colors.success, fontSize = 13.sp)
                            }
                        }
                    }

                    // 3. 剧情简介玻璃卡
                    item {
                        val overviewText = detail.overview.ifBlank { "暂无剧情简介，可点击上方按钮快速检索站点高清片源或加入自动追剧订阅。" }
                        CinematicPanel(
                            padding = 16.dp,
                            showsShadow = false,
                            modifier = Modifier
                                .padding(horizontal = margin)
                                .clickable { expandOverview = !expandOverview },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("剧情简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                Text(
                                    text = overviewText,
                                    color = colors.textSecondary,
                                    fontSize = 14.sp,
                                    lineHeight = 22.sp,
                                    maxLines = if (expandOverview) Int.MAX_VALUE else 4,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (overviewText.length > 90) {
                                    Text(
                                        text = if (expandOverview) "收起" else "展开全部",
                                        color = colors.textMuted,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                    )
                                }
                            }
                        }
                    }

                    // 4. 剧集分季真实海报卡
                    if (isTv && seasons.isNotEmpty()) {
                        item {
                            Column(modifier = Modifier.padding(horizontal = margin), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Text("剧集分季", color = colors.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                                    Text("共 ${seasons.size} 季", color = colors.textMuted, fontSize = 13.sp)
                                }
                                seasons.forEach { season ->
                                    val isExpanded = expandedSeason == season.seasonNumber
                                    val isSeasonSub = season.seasonNumber in subscribedSeasons
                                    CinematicPanel(
                                        padding = 14.dp,
                                        showsShadow = false,
                                        modifier = Modifier.clickable {
                                            expandedSeason = if (isExpanded) null else season.seasonNumber
                                            val tmdbId = detail.tmdbId
                                            if (!isExpanded && tmdbId != null && episodesBySeason[season.seasonNumber] == null) {
                                                scope.launch {
                                                    episodesBySeason[season.seasonNumber] = repository.fetchSeasonEpisodes(tmdbId, season.seasonNumber)
                                                }
                                            }
                                        },
                                    ) {
                                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                                                Box(
                                                    modifier = Modifier
                                                        .width(74.dp)
                                                        .aspectRatio(2f / 3f)
                                                        .clip(RoundedCornerShape(10.dp))
                                                        .background(colors.chipFill),
                                                ) {
                                                    val poster = season.posterPath ?: detail.posterPath
                                                    if (!poster.isNullOrBlank()) {
                                                        AsyncImage(model = poster, contentDescription = season.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                                    }
                                                }
                                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                                        Text(season.name.ifBlank { "第 ${season.seasonNumber} 季" }, color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                                        Icon(
                                                            if (isExpanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                                                            contentDescription = null,
                                                            tint = colors.textMuted,
                                                            modifier = Modifier.size(20.dp),
                                                        )
                                                    }
                                                    Text(
                                                        listOfNotNull(season.airDate.take(4).ifBlank { null }, if (season.episodeCount > 0) "${season.episodeCount} 集" else null).joinToString(" · "),
                                                        color = colors.textSecondary,
                                                        fontSize = 12.sp,
                                                    )
                                                    if (season.overview.isNotBlank()) {
                                                        Text(season.overview, color = colors.textMuted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, lineHeight = 17.sp)
                                                    }
                                                    Spacer(Modifier.height(2.dp))
                                                    Box(
                                                        modifier = Modifier
                                                            .clip(CircleShape)
                                                            .background(if (isSeasonSub) colors.success.copy(alpha = 0.22f) else colors.chipFill)
                                                            .border(0.7.dp, if (isSeasonSub) colors.success else colors.chipBorder, CircleShape)
                                                            .clickable {
                                                                scope.launch {
                                                                    val ok = repository.createOrUpdateSubscription(
                                                                        SubscribeItemDto(
                                                                            name = detail.title,
                                                                            year = detail.year,
                                                                            type = "电视剧",
                                                                            season = season.seasonNumber,
                                                                            mediaSource = detail.source,
                                                                            mediaId = detail.tmdbId?.toString() ?: detail.resolvedId,
                                                                        ),
                                                                    )
                                                                    subscribedSeasons = subscribedSeasons + season.seasonNumber
                                                                    feedback = if (ok) "已订阅第 ${season.seasonNumber} 季" else "已提交分季订阅"
                                                                }
                                                            }
                                                            .padding(horizontal = 12.dp, vertical = 5.dp),
                                                    ) {
                                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                                            Icon(if (isSeasonSub) Icons.Rounded.BookmarkAdded else Icons.Rounded.Add, contentDescription = null, tint = if (isSeasonSub) colors.success else colors.textPrimary, modifier = Modifier.size(13.dp))
                                                            Text(if (isSeasonSub) "已订阅本季" else "订阅本季", color = if (isSeasonSub) colors.success else colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                                                        }
                                                    }
                                                }
                                            }

                                            if (isExpanded) {
                                                val eps = episodesBySeason[season.seasonNumber].orEmpty()
                                                if (eps.isNotEmpty()) {
                                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                                        eps.take(12).forEach { ep ->
                                                            Row(
                                                                modifier = Modifier
                                                                    .fillMaxWidth()
                                                                    .clip(RoundedCornerShape(12.dp))
                                                                    .background(colors.chipFill.copy(alpha = 0.65f))
                                                                    .padding(10.dp),
                                                                verticalAlignment = Alignment.CenterVertically,
                                                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                                                            ) {
                                                                if (!ep.stillPath.isNullOrBlank()) {
                                                                    AsyncImage(
                                                                        model = ep.stillPath,
                                                                        contentDescription = ep.name,
                                                                        contentScale = ContentScale.Crop,
                                                                        modifier = Modifier.width(86.dp).aspectRatio(16f / 9f).clip(RoundedCornerShape(8.dp)),
                                                                    )
                                                                }
                                                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                                                    Text("E%02d · %s".format(ep.episodeNumber, ep.name.ifBlank { "第 ${ep.episodeNumber} 集" }), color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                                    if (ep.airDate.isNotBlank()) {
                                                                        Text(ep.airDate + (ep.runtime?.let { " · ${it}分钟" } ?: ""), color = colors.textMuted, fontSize = 11.sp)
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
                    }

                    // 5. 演职员真人圆形头像横栏（点击推入独立全屏 `PersonDetailScreen` 页面）
                    if (credits.isNotEmpty()) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                NativeSectionHeader(title = "演职员", modifier = Modifier.padding(horizontal = margin))
                                LazyRow(
                                    contentPadding = PaddingValues(horizontal = margin),
                                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                                ) {
                                    items(credits.take(20), key = { it.id + it.name + it.character }) { person ->
                                        Column(
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                            modifier = Modifier
                                                .width(82.dp)
                                                .clickable { onOpenPerson(person) },
                                        ) {
                                            Box(
                                                modifier = Modifier
                                                    .size(72.dp)
                                                    .clip(CircleShape)
                                                    .background(colors.chipFill)
                                                    .border(0.8.dp, Color.White.copy(alpha = 0.16f), CircleShape),
                                                contentAlignment = Alignment.Center,
                                            ) {
                                                Icon(Icons.Rounded.Person, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(30.dp))
                                                if (!person.profilePath.isNullOrBlank()) {
                                                    AsyncImage(
                                                        model = person.profilePath,
                                                        contentDescription = person.name,
                                                        contentScale = ContentScale.Crop,
                                                        modifier = Modifier.fillMaxSize(),
                                                    )
                                                }
                                            }
                                            Spacer(Modifier.height(7.dp))
                                            Text(
                                                text = person.name,
                                                color = colors.textPrimary,
                                                fontSize = 12.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                                textAlign = TextAlign.Center,
                                            )
                                            if (person.character.isNotBlank()) {
                                                Text(
                                                    text = person.character,
                                                    color = colors.textMuted,
                                                    fontSize = 11.sp,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                    textAlign = TextAlign.Center,
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

        // 顶部状态栏渐进模糊（上滚后平滑浮现，保护状态栏文字与悬浮返回按钮清晰可读）
        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = eased,
            extraHeight = 56.dp,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )

        // 左上角悬浮磨砂返回按钮（Android 标准 ArrowBack Up 图标）
        CinematicCircleButton(
            icon = Icons.AutoMirrored.Rounded.ArrowBack,
            contentDescription = "返回",
            onClick = onBack,
            modifier = Modifier
                .align(Alignment.TopStart)
                .statusBarsPadding()
                .padding(start = 16.dp, top = 8.dp),
        )
    }
}

/**
 * 独立原生人物详情页（1:1 复刻 iOS `NativePersonDetailPage.swift` + Android 独立路由压栈）：
 * 居中 116dp 圆形人物肖像、职业/生日/出生地履历、可展开人物简介玻璃卡、3 列参演作品海报网格，
 * 点击任意作品继续推入下一部影视详情页，并由顶部状态栏渐进模糊护航滚动。
 */
@Composable
fun PersonDetailScreen(
    seed: MediaPersonDto,
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val columns = AdaptiveDeviceLayout.posterGridColumns()
    val localHaze = remember { HazeState() }

    var person by remember(seed.id) { mutableStateOf(seed) }
    var works by remember(seed.id) { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var bioExpanded by remember(seed.id) { mutableStateOf(false) }

    LaunchedEffect(seed.id) {
        val (enriched, list) = repository.fetchPersonDetail(seed)
        person = enriched
        works = list
    }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            modifier = Modifier
                .fillMaxSize()
                .hazeSource(localHaze),
            contentPadding = PaddingValues(start = margin, end = margin, top = 104.dp, bottom = 48.dp),
            horizontalArrangement = Arrangement.spacedBy(11.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 居中人物头像与履历信息
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(116.dp)
                            .clip(CircleShape)
                            .background(colors.chipFill)
                            .border(1.dp, Color.White.copy(alpha = 0.22f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Rounded.Person, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(46.dp))
                        if (!person.profilePath.isNullOrBlank()) {
                            AsyncImage(
                                model = person.profilePath,
                                contentDescription = person.name,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }
                    Text(
                        text = person.name,
                        color = colors.textPrimary,
                        fontSize = 23.sp,
                        fontWeight = FontWeight.ExtraBold,
                        textAlign = TextAlign.Center,
                    )
                    val facts = listOfNotNull(
                        person.department.ifBlank { null },
                        person.birthday.ifBlank { null },
                        person.placeOfBirth.ifBlank { null },
                    ).joinToString(" · ")
                    if (facts.isNotBlank()) {
                        Text(
                            text = facts,
                            color = colors.textSecondary,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }

            // 人物简介玻璃卡（支持展开/收起）
            if (person.biography.isNotBlank()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    CinematicPanel(
                        padding = 16.dp,
                        showsShadow = false,
                        modifier = Modifier.clickable { bioExpanded = !bioExpanded },
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("人物简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            Text(
                                text = person.biography,
                                color = colors.textSecondary,
                                fontSize = 14.sp,
                                lineHeight = 22.sp,
                                maxLines = if (bioExpanded) Int.MAX_VALUE else 5,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (person.biography.length > 110) {
                                Text(
                                    text = if (bioExpanded) "收起简介" else "展开全部",
                                    color = colors.accent,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold,
                                )
                            }
                        }
                    }
                }
            }

            // 参演作品标题
            if (works.isNotEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    NativeSectionHeader(
                        title = "参演作品",
                        subtitle = "${works.size} 部",
                    )
                }
                items(works, key = { it.resolvedId + it.title }) { work ->
                    NativePosterCard(
                        title = work.title,
                        year = work.year,
                        posterUrl = work.posterPath,
                        voteAverage = work.voteAverage,
                        inLibrary = work.inLibrary,
                        onClick = { onOpenMedia(work) },
                    )
                }
            }
        }

        // 顶部状态栏渐进模糊 + 居中标题导航栏
        Box(modifier = Modifier.align(Alignment.TopCenter)) {
            NativeTopStatusBarProgressiveBlur(
                visibilityProgress = 1f,
                extraHeight = 62.dp,
                blurSourceState = localHaze,
            )
            NativeGlassTopBar(
                title = person.name,
                onBack = onBack,
                showTopBlur = false,
            )
        }
    }
}
