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
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.BookmarkAdded
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.MultiSourceRatingsRow
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeCardListSkeleton
import com.moviepilot.designsystem.NativeCastRowSkeleton
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeEpisodeShelfSkeleton
import com.moviepilot.designsystem.NativeMediaDetailSkeleton
import com.moviepilot.designsystem.NativeOverviewLinesSkeleton
import com.moviepilot.designsystem.NativePersonDetailSkeleton
import com.moviepilot.designsystem.NativePosterCard
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.designsystem.NativeSkeletonBlock
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import com.moviepilot.designsystem.ProvideSkeletonShimmer
import com.moviepilot.designsystem.SkeletonCardStyle
import com.moviepilot.designsystem.SkeletonSurfaceRole
import com.moviepilot.designsystem.nativePosterGridSkeletonItems
import com.moviepilot.feature.subscribe.SubscribeFilesSheet
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.QueueTrackSpec
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaEpisodeDto
import com.moviepilot.rustbridge.MediaLibraryStatusDto
import com.moviepilot.rustbridge.MediaPersonDto
import com.moviepilot.rustbridge.MediaRatingBadgeDto
import com.moviepilot.rustbridge.MediaSeasonDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.SubscribeItemDto
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
    onOpenServerDetail: ((itemId: String, server: String, title: String) -> Unit)? = null,
    onOpenSeasonDetail: ((seriesItem: MediaCardItem, season: MediaSeasonDto, seriesItemId: String, server: String) -> Unit)? = null,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val config = LocalConfiguration.current
    val w = config.screenWidthDp
    val h = config.screenHeightDp
    val isLandscape = w > h
    val isCompactLandscape = isLandscape && h < 480
    val isPortraitPhone = !isLandscape && w < 680
    val heroHeight = when {
        isCompactLandscape -> (h * 0.54f).coerceIn(196f, 248f).dp
        isLandscape -> (h * 0.52f).coerceIn(320f, 420f).dp
        isPortraitPhone -> 450.dp
        else -> 420.dp
    }
    val density = LocalDensity.current
    val heroHeightPx = with(density) { heroHeight.toPx().coerceAtLeast(1f) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    var detail by remember(item.resolvedId) { mutableStateOf(item) }
    var multiRatings by remember(item.resolvedId) { mutableStateOf(repository.seedRatingsForCard(item)) }
    var credits by remember(item.resolvedId) { mutableStateOf<List<MediaPersonDto>>(emptyList()) }
    var seasons by remember(item.resolvedId) { mutableStateOf<List<MediaSeasonDto>>(emptyList()) }
    val episodesBySeason = remember(item.resolvedId) { mutableStateMapOf<Int, List<MediaEpisodeDto>>() }
    var expandedSeason by remember(item.resolvedId) { mutableStateOf<Int?>(null) }
    var expandOverview by remember(item.resolvedId) { mutableStateOf(false) }
    var subscribedSeasons by remember(item.resolvedId) { mutableStateOf<Set<Int>>(emptySet()) }
    var subscribedMovie by remember(item.resolvedId) { mutableStateOf(false) }
    var userMovieOverride by remember(item.resolvedId) { mutableStateOf<Boolean?>(null) }
    val userSeasonOverrides = remember(item.resolvedId) { mutableStateMapOf<Int, Boolean>() }
    var movieSubscribeId by remember(item.resolvedId) { mutableStateOf<Int?>(null) }
    val seasonSubscribeIds = remember(item.resolvedId) { mutableStateMapOf<Int, Int>() }
    var pendingUnsubscribeSeason by remember(item.resolvedId) { mutableStateOf<Int?>(null) }
    var showUnsubscribeDialog by remember(item.resolvedId) { mutableStateOf(false) }
    var activeSubscribeFilesId by remember(item.resolvedId) { mutableStateOf<Int?>(null) }
    var isMutatingSubscribe by remember(item.resolvedId) { mutableStateOf(false) }
    var libraryStatus by remember(item.resolvedId) { mutableStateOf(MediaLibraryStatusDto(inLibrary = item.inLibrary)) }
    var playableEpisodesBySeason by remember(item.resolvedId) { mutableStateOf<Map<Int, Map<Int, String>>>(emptyMap()) }
    var remoteExistingBySeason by remember(item.resolvedId) { mutableStateOf<Map<Int, Set<Int>>>(emptyMap()) }
    var episodeAvailabilityLoaded by remember(item.resolvedId) { mutableStateOf(false) }
    var feedback by remember(item.resolvedId) { mutableStateOf<String?>(null) }
    var feedbackIsError by remember(item.resolvedId) { mutableStateOf(false) }
    var isDetailLoading by remember(item.resolvedId) { mutableStateOf(true) }
    var loadingSeasons by remember(item.resolvedId) { mutableStateOf<Set<Int>>(emptySet()) }
    var isRefreshing by remember { mutableStateOf(false) }

    suspend fun loadDetail(clearUserOverrides: Boolean = false) {
        if (clearUserOverrides) {
            userMovieOverride = null
            userSeasonOverrides.clear()
        }
        if (!isRefreshing) {
            isDetailLoading = true
        }
        coroutineScope {
            val detailDef = async { repository.fetchMediaDetail(item) }
            val creditsDef = async { repository.fetchMediaCredits(item) }
            val logoDef = async { repository.fetchHeroLogo(item) }
            val enriched = detailDef.await()
            val logo = logoDef.await()
            if (enriched != null) {
                detail = enriched.copy(
                    type = if (MoviePilotRepository.isTvType(item.type) || MoviePilotRepository.isTvType(enriched.type)) "电视剧" else enriched.type,
                    posterPath = item.posterPath?.takeIf { it.isNotBlank() } ?: enriched.posterPath?.takeIf { it.isNotBlank() },
                    backdropPath = enriched.backdropPath?.takeIf { it.isNotBlank() } ?: item.backdropPath?.takeIf { it.isNotBlank() },
                    logoPath = enriched.logoPath?.takeIf { it.isNotBlank() } ?: logo?.takeIf { it.isNotBlank() } ?: item.logoPath,
                    genres = enriched.genres.ifEmpty { item.genres },
                    season = enriched.season ?: item.season,
                )
            } else if (!logo.isNullOrBlank()) {
                detail = detail.copy(logoPath = logo)
            }
            credits = creditsDef.await()
            val resolvedIsTv = MoviePilotRepository.isTvType(detail.type) || MoviePilotRepository.isTvType(item.type)
            if (resolvedIsTv) {
                val fetchedSeasons = repository.fetchMediaSeasonsForItem(detail)
                seasons = fetchedSeasons
                val defaultSeason = detail.season ?: item.season ?: fetchedSeasons.firstOrNull()?.seasonNumber
                if (expandedSeason == null && defaultSeason != null && onOpenSeasonDetail == null) {
                    expandedSeason = defaultSeason
                    if (episodesBySeason[defaultSeason] == null) {
                        loadingSeasons = loadingSeasons + defaultSeason
                        episodesBySeason[defaultSeason] = repository.fetchSeasonEpisodesSmart(detail, defaultSeason)
                        loadingSeasons = loadingSeasons - defaultSeason
                    }
                }
            }
            isDetailLoading = false
            val querySeason = if (resolvedIsTv) (detail.season ?: item.season ?: seasons.firstOrNull()?.seasonNumber ?: 1) else null
            val libStatus = repository.checkMediaInLibraryStatus(detail, season = querySeason)
            libraryStatus = libStatus
            if (resolvedIsTv) {
                subscribedSeasons = libStatus.subscribedSeasons.keys +
                    (if (libStatus.subscribed && querySeason != null) setOf(querySeason) else emptySet())
                libStatus.seasonSubscribeIds.forEach { (k, v) -> seasonSubscribeIds[k] = v }
                if (querySeason != null && libStatus.subscribeId != null) {
                    seasonSubscribeIds.putIfAbsent(querySeason, libStatus.subscribeId!!)
                }
                val playableDef = async {
                    if (libStatus.itemId.isNotBlank()) {
                        repository.fetchPlayableSeriesEpisodes(libStatus.itemId, libStatus.server.ifBlank { null })
                    } else {
                        emptyMap()
                    }
                }
                val remoteExistsDef = async { repository.fetchRemoteExistingEpisodes(detail) }
                playableEpisodesBySeason = playableDef.await()
                remoteExistingBySeason = remoteExistsDef.await()
                episodeAvailabilityLoaded = true
            } else {
                subscribedMovie = libStatus.subscribed
                if (libStatus.subscribeId != null) {
                    movieSubscribeId = libStatus.subscribeId
                }
            }
            if (libStatus.inLibrary && !detail.inLibrary) {
                detail = detail.copy(inLibrary = true)
            }
            multiRatings = repository.seedRatingsForCard(detail)
            launch {
                val enrichedRatings = repository.fetchMultiSourceRatings(
                    item = detail,
                    serverItemId = libStatus.itemId,
                    serverName = libStatus.server,
                )
                if (enrichedRatings.isNotEmpty()) {
                    multiRatings = enrichedRatings
                }
            }
            isRefreshing = false
        }
    }

    LaunchedEffect(item.resolvedId) { loadDetail(clearUserOverrides = false) }

    val scrollUpPxProvider: () -> Float = {
        if (listState.firstVisibleItemIndex == 0) {
            listState.firstVisibleItemScrollOffset.toFloat().coerceAtLeast(0f)
        } else {
            heroHeightPx
        }
    }
    val easedProvider: () -> Float = {
        val p = (scrollUpPxProvider() / (heroHeightPx * 0.62f)).coerceIn(0f, 1f)
        p * p * (3f - 2f * p)
    }
    val isHeroScrolledAway by remember(heroHeightPx) {
        derivedStateOf {
            listState.firstVisibleItemIndex > 0 || listState.firstVisibleItemScrollOffset >= (heroHeightPx * 0.62f).toInt()
        }
    }

    val isTv = MoviePilotRepository.isTvType(detail.type) || MoviePilotRepository.isTvType(item.type) || seasons.isNotEmpty()
    val effectiveSubscribedSeasons = remember(subscribedSeasons, userSeasonOverrides.toMap()) {
        val base = subscribedSeasons.toMutableSet()
        userSeasonOverrides.forEach { (sNum, active) ->
            if (active) base += sNum else base -= sNum
        }
        base.toSet()
    }
    val effectiveMovieSubscribed = userMovieOverride ?: subscribedMovie
    val requestedSeason = detail.season ?: item.season
    val primarySeason = when {
        requestedSeason != null -> requestedSeason
        isTv && effectiveSubscribedSeasons.size == 1 -> effectiveSubscribedSeasons.first()
        else -> seasons.firstOrNull()?.seasonNumber ?: 1
    }
    val primarySubscribed = if (isTv) {
        if (requestedSeason != null) requestedSeason in effectiveSubscribedSeasons else effectiveSubscribedSeasons.isNotEmpty()
    } else {
        effectiveMovieSubscribed
    }
    val subscribedEmeraldBg = if (colors.isDark) Color(0xFF1F9D55) else Color(0xFF1F9D55)
    val subscribedEmeraldAccent = if (colors.isDark) Color(0xFF34C759) else Color(0xFF1F9D55)

    suspend fun subscribeTarget(targetSeason: Int?, totalEps: Int = 0) {
        if (isMutatingSubscribe) return
        isMutatingSubscribe = true
        val canonicalIdentity = MoviePilotRepository.normalizeCanonicalMediaIdentity(
            source = detail.source,
            mediaId = detail.mediaId,
            tmdbId = detail.tmdbId,
            doubanId = detail.doubanId,
            bangumiId = detail.bangumiId,
            imdbId = detail.imdbId,
            tvdbId = detail.tvdbId,
        )
        val (ok, msg, subId) = repository.createOrUpdateSubscriptionFull(
            SubscribeItemDto(
                name = detail.title,
                year = detail.year,
                type = if (isTv) "电视剧" else "电影",
                season = if (isTv) (targetSeason ?: 1) else null,
                totalEpisode = totalEps,
                mediaSource = canonicalIdentity?.first ?: "themoviedb",
                mediaId = canonicalIdentity?.second.orEmpty(),
            ),
        )
        isMutatingSubscribe = false
        if (ok) {
            if (isTv) {
                val sNum = targetSeason ?: 1
                userSeasonOverrides[sNum] = true
                subscribedSeasons = subscribedSeasons + sNum
                if (subId != null && subId > 0) seasonSubscribeIds[sNum] = subId
                feedback = "已订阅第 $sNum 季"
            } else {
                userMovieOverride = true
                subscribedMovie = true
                if (subId != null && subId > 0) movieSubscribeId = subId
                feedback = "已添加到我的订阅"
            }
            feedbackIsError = false
        } else {
            feedbackIsError = true
            feedback = msg
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // 1. 底层固定沉浸海报 + 滚动正文（仅在绘制阶段更新视差与透明度，零整页重组）
        Box(
            modifier = Modifier.fillMaxSize(),
        ) {
            if (colors.isDark && !isHeroScrolledAway) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            alpha = ((1f - easedProvider() * 1.15f).coerceAtLeast(0f)) * 0.55f
                        }
                        .background(Color(0xFF0A0A16)),
                )
            }

            if (!isHeroScrolledAway) {
                val backdropHeight = heroHeight * 1.06f
                val fadeBase = androidx.compose.material3.MaterialTheme.colorScheme.background

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(backdropHeight)
                        .graphicsLayer {
                            val sPx = scrollUpPxProvider()
                            translationY = -sPx.coerceAtMost(heroHeightPx) * 0.08f
                            alpha = (1f - easedProvider() * 0.96f).coerceIn(0f, 1f)
                            compositingStrategy = CompositingStrategy.Offscreen
                        }
                        .drawWithContent {
                            drawContent()
                            val maskShiftY = -scrollUpPxProvider() * 0.85f
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
                            modifier = Modifier.fillMaxSize(),
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
                    scope.launch { loadDetail(clearUserOverrides = true) }
                },
                modifier = Modifier.fillMaxSize(),
            ) {
                val isUnseeded = detail.posterPath.isNullOrBlank() &&
                    detail.backdropPath.isNullOrBlank() &&
                    detail.overview.isBlank() &&
                    detail.year.isBlank() &&
                    (detail.title.isBlank() || detail.title.startsWith("媒体详情 #"))
                if (isDetailLoading && isUnseeded) {
                    NativeMediaDetailSkeleton(
                        heroHeight = heroHeight,
                        isCompactLandscape = isCompactLandscape,
                        isLandscape = isLandscape,
                        showServerExtras = false,
                    )
                } else {
                ProvideSkeletonShimmer {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 28.dp + bottomOverlayInset),
                    verticalArrangement = Arrangement.spacedBy(if (isCompactLandscape) 12.dp else 18.dp),
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
                                    .padding(horizontal = margin, vertical = if (isCompactLandscape) 8.dp else 14.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(if (isCompactLandscape) 4.dp else 8.dp),
                            ) {
                                var logoReady by remember(detail.logoPath) { mutableStateOf(false) }
                                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    if (!logoReady) {
                                        Text(
                                            text = detail.title,
                                            color = if (colors.isDark) Color.White else colors.textPrimary,
                                            fontSize = if (isCompactLandscape) 22.sp else 28.sp,
                                            fontWeight = FontWeight.ExtraBold,
                                            textAlign = TextAlign.Center,
                                            maxLines = if (isCompactLandscape) 1 else 2,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    if (!detail.logoPath.isNullOrBlank()) {
                                        AsyncImage(
                                            model = detail.logoPath,
                                            contentDescription = detail.title,
                                            contentScale = ContentScale.Fit,
                                            onSuccess = { logoReady = true },
                                            modifier = Modifier
                                                .fillMaxWidth(if (isCompactLandscape) 0.54f else 0.74f)
                                                .height(if (isCompactLandscape) 48.dp else 74.dp),
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
                                val resolvedDetailRatings = multiRatings.ifEmpty {
                                    repository.seedRatingsForCard(detail)
                                }
                                if (resolvedDetailRatings.isNotEmpty()) {
                                    MultiSourceRatingsRow(
                                        badges = resolvedDetailRatings.map { it.source to it.label },
                                        isDark = colors.isDark,
                                        compact = isCompactLandscape,
                                    )
                                } else if (detail.voteAverage > 0.0) {
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

                    // 2. 核心操作栏（深浅双模高对比度主按钮 + 玻璃次按钮 + 媒体库直放；宽横屏三键同行直达）
                    item {
                        val actionBtnHeight = if (isCompactLandscape) 44.dp else 50.dp
                        val canPlayNow = detail.inLibrary || libraryStatus.inLibrary
                        val inlinePlayInRow = canPlayNow && isLandscape
                        val triggerPlayNow: () -> Unit = {
                            scope.launch {
                                feedback = null
                                val targetSrv = libraryStatus.server.takeIf { it.isNotBlank() }
                                var playTargetId = libraryStatus.itemId.takeIf { it.isNotBlank() }
                                    ?: detail.mediaId?.takeIf { it.isNotBlank() && !it.contains(":") }
                                    ?: repository.searchMedia(detail.title, "library", 1).firstOrNull()?.mediaId
                                var queueList: List<MediaPlaybackRequest> = emptyList()
                                var playTitleOverride: String? = null
                                if (isTv && !playTargetId.isNullOrBlank()) {
                                    val seasonMap = if (playableEpisodesBySeason.isNotEmpty()) {
                                        playableEpisodesBySeason
                                    } else {
                                        repository.fetchPlayableSeriesEpisodes(playTargetId!!, targetSrv).also {
                                            playableEpisodesBySeason = it
                                        }
                                    }
                                    val firstSeason = seasonMap.keys.sortedWith(compareBy<Int> { it == 0 }.thenBy { it }).firstOrNull()
                                    val epMap = firstSeason?.let { seasonMap[it] }.orEmpty()
                                    val sortedEps = epMap.keys.sorted()
                                    val firstEp = sortedEps.firstOrNull()
                                    if (firstSeason != null && firstEp != null && epMap[firstEp] != null) {
                                        playTargetId = epMap[firstEp]
                                        playTitleOverride = "${detail.title} · S%02dE%02d".format(firstSeason, firstEp)
                                        queueList = sortedEps.mapIndexedNotNull { idx, epNum ->
                                            val qid = epMap[epNum] ?: return@mapIndexedNotNull null
                                            MediaPlaybackRequest(
                                                url = "",
                                                title = "${detail.title} · S%02dE%02d".format(firstSeason, epNum),
                                                subtitle = targetSrv.orEmpty(),
                                                artworkUrl = detail.posterPath,
                                                itemId = qid,
                                                server = targetSrv.orEmpty(),
                                                queueIndex = idx,
                                                lazySpec = QueueTrackSpec.MediaServerItem(itemId = qid, server = targetSrv.orEmpty()),
                                            )
                                        }
                                    }
                                }
                                val manifest = playTargetId?.let { repository.fetchVideoStreamInfo(it, targetSrv) }
                                if (manifest != null) {
                                    val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                    onPlayMedia(
                                        MediaPlaybackRequest(
                                            url = manifest.contentUrl,
                                            title = playTitleOverride ?: manifest.title.ifBlank { detail.title },
                                            subtitle = listOfNotNull(
                                                manifest.server.ifBlank { targetSrv },
                                                detail.year.ifBlank { null },
                                                detail.type.ifBlank { null },
                                            ).joinToString(" · "),
                                            artworkUrl = detail.posterPath,
                                            isAudio = manifest.mediaType == "audio",
                                            lyricsLrc = lrc,
                                            headers = manifest.headers,
                                            sameOriginHeaders = manifest.sameOriginHeaders,
                                            streamHeaders = manifest.streamHeaders,
                                            proxyFallbackUrl = manifest.proxyFallbackUrl,
                                            activeRouteKind = manifest.activeRouteKind,
                                            fallbackRoutes = manifest.fallbackRoutes,
                                            originUrl = manifest.originUrl,
                                            itemId = manifest.itemId,
                                            server = manifest.server.ifBlank { targetSrv.orEmpty() },
                                            serverType = manifest.serverType,
                                            mediaSourceId = manifest.mediaSourceId.orEmpty(),
                                            playSessionId = manifest.playSessionId,
                                            progressSyncMode = manifest.progressSyncMode,
                                            resumePositionMs = manifest.resumePositionMs,
                                            subtitles = manifest.subtitles.map {
                                                SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                                            },
                                            danmakuEnabled = manifest.danmakuEnabled,
                                            seriesName = manifest.seriesName,
                                            seasonNumber = manifest.seasonNumber,
                                            episodeNumber = manifest.episodeNumber,
                                            year = manifest.year,
                                            tmdbId = manifest.tmdbId,
                                            fileName = manifest.fileName,
                                            fileSize = manifest.fileSize,
                                            queue = queueList,
                                            queueIndex = 0,
                                        ),
                                    )
                                } else {
                                    feedbackIsError = true
                                    feedback = "当前媒体服务器未找到该条目的直放流"
                                }
                            }
                        }

                        Column(
                            modifier = Modifier.padding(horizontal = margin),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                val primaryBtnBg = when {
                                    primarySubscribed -> subscribedEmeraldBg
                                    colors.isDark -> Color.White
                                    else -> colors.accent
                                }
                                val primaryBtnFg = when {
                                    primarySubscribed -> Color.White
                                    colors.isDark -> Color(0xFF14111D)
                                    else -> colors.primaryButtonFg
                                }
                                Button(
                                    onClick = {
                                        if (primarySubscribed) {
                                            pendingUnsubscribeSeason = if (isTv) {
                                                effectiveSubscribedSeasons.minOrNull() ?: primarySeason
                                            } else {
                                                null
                                            }
                                            showUnsubscribeDialog = true
                                        } else {
                                            val epCnt = seasons.firstOrNull { it.seasonNumber == primarySeason }?.episodeCount ?: 0
                                            scope.launch { subscribeTarget(if (isTv) primarySeason else null, epCnt) }
                                        }
                                    },
                                    enabled = !isMutatingSubscribe,
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = primaryBtnBg,
                                        contentColor = primaryBtnFg,
                                    ),
                                    shape = CircleShape,
                                    modifier = Modifier.weight(1f).height(actionBtnHeight),
                                ) {
                                    Icon(
                                        if (primarySubscribed) Icons.Rounded.CheckCircle else Icons.Outlined.BookmarkBorder,
                                        contentDescription = null,
                                        modifier = Modifier.size(19.dp),
                                    )
                                    Spacer(Modifier.width(6.dp))
                                    Text(
                                        text = when {
                                            primarySubscribed && isTv && effectiveSubscribedSeasons.size > 1 ->
                                                "已订阅 ${effectiveSubscribedSeasons.size} 季"
                                            primarySubscribed && isTv ->
                                                "第 ${effectiveSubscribedSeasons.firstOrNull() ?: primarySeason} 季已订阅"
                                            primarySubscribed -> "已订阅"
                                            isTv -> "订阅第 $primarySeason 季"
                                            else -> "添加订阅"
                                        },
                                        fontSize = if (isCompactLandscape) 14.sp else 15.sp,
                                        fontWeight = FontWeight.Bold,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }

                                CinematicGlassSurface(
                                    shape = CircleShape,
                                    blurRadiusDp = 18.dp,
                                    useLiveBackdropBlur = false,
                                    modifier = Modifier
                                        .weight(1f)
                                        .height(actionBtnHeight)
                                        .clickable { onSearchResource(detail.title) },
                                ) {
                                    Row(
                                        modifier = Modifier.fillMaxSize(),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.Center,
                                    ) {
                                        Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(19.dp))
                                        Spacer(Modifier.width(6.dp))
                                        Text("搜索资源", color = colors.textPrimary, fontSize = if (isCompactLandscape) 14.sp else 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                    }
                                }

                                if (inlinePlayInRow) {
                                    Button(
                                        onClick = triggerPlayNow,
                                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                                        shape = CircleShape,
                                        modifier = Modifier.weight(1f).height(actionBtnHeight),
                                    ) {
                                        if (libraryStatus.server.isNotBlank()) {
                                            NativeEntityLogo(
                                                kind = "mediaserver",
                                                value = libraryStatus.serverType.ifBlank { libraryStatus.server },
                                                size = 17.dp,
                                                cornerRadius = 5.dp,
                                            )
                                            Spacer(Modifier.width(6.dp))
                                        } else {
                                            Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(19.dp))
                                            Spacer(Modifier.width(6.dp))
                                        }
                                        Text(
                                            text = if (libraryStatus.server.isNotBlank()) "立即播放 · ${libraryStatus.server}" else "立即播放",
                                            fontWeight = FontWeight.SemiBold,
                                            fontSize = if (isCompactLandscape) 14.sp else 15.sp,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                }
                            }

                            if (canPlayNow && !inlinePlayInRow) {
                                Button(
                                    onClick = triggerPlayNow,
                                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                                    shape = CircleShape,
                                    modifier = Modifier.fillMaxWidth().height(46.dp),
                                ) {
                                    if (libraryStatus.server.isNotBlank()) {
                                        NativeEntityLogo(
                                            kind = "mediaserver",
                                            value = libraryStatus.serverType.ifBlank { libraryStatus.server },
                                            size = 18.dp,
                                            cornerRadius = 5.dp,
                                        )
                                        Spacer(Modifier.width(6.dp))
                                    } else {
                                        Icon(Icons.Rounded.PlayArrow, contentDescription = null)
                                        Spacer(Modifier.width(6.dp))
                                    }
                                    Text(
                                        text = if (libraryStatus.server.isNotBlank()) "立即播放 · ${libraryStatus.server}" else "立即播放",
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            }

                            feedback?.let {
                                Text(it, color = if (feedbackIsError) colors.warning else colors.success, fontSize = 13.sp)
                            }
                        }
                    }

                    // 3. 剧情简介玻璃卡
                    item {
                        val showOverviewShimmer = isDetailLoading && detail.overview.isBlank()
                        val overviewText = detail.overview.ifBlank { "暂无剧情简介，可点击上方按钮快速检索站点高清片源或加入自动追剧订阅。" }
                        CinematicPanel(
                            padding = 16.dp,
                            showsShadow = false,
                            modifier = Modifier
                                .padding(horizontal = margin)
                                .then(if (!showOverviewShimmer) Modifier.clickable { expandOverview = !expandOverview } else Modifier),
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("剧情简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                if (showOverviewShimmer) {
                                    NativeOverviewLinesSkeleton(lines = 3)
                                } else {
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
                    }

                    // 4. 剧集分季真实海报卡
                    if (isTv && seasons.isEmpty() && isDetailLoading) {
                        item(key = "md_seasons_loading") {
                            NativeEpisodeShelfSkeleton(
                                cardWidth = 224.dp,
                                cardHeight = 126.dp,
                                count = 4,
                                contentPadding = PaddingValues(horizontal = margin),
                                showHeader = true,
                            )
                        }
                    } else if (isTv && seasons.isNotEmpty()) {
                        item {
                            Column(modifier = Modifier.padding(horizontal = margin), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Text("剧集分季", color = colors.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                                    Text("共 ${seasons.size} 季", color = colors.textMuted, fontSize = 13.sp)
                                }
                                seasons.forEach { season ->
                                    val isExpanded = expandedSeason == season.seasonNumber && onOpenSeasonDetail == null
                                    val isSeasonSub = season.seasonNumber in effectiveSubscribedSeasons
                                    val seasonExistingSet = remember(
                                        playableEpisodesBySeason,
                                        remoteExistingBySeason,
                                        libraryStatus.existingEpisodesBySeason,
                                        season.seasonNumber,
                                    ) {
                                        buildSet {
                                            addAll(libraryStatus.existingEpisodesBySeason[season.seasonNumber].orEmpty())
                                            addAll(remoteExistingBySeason[season.seasonNumber].orEmpty())
                                            addAll(playableEpisodesBySeason[season.seasonNumber]?.keys.orEmpty())
                                        }
                                    }
                                    CinematicPanel(
                                        padding = 14.dp,
                                        showsShadow = false,
                                        modifier = Modifier.clickable {
                                            if (onOpenSeasonDetail != null) {
                                                onOpenSeasonDetail(detail, season, libraryStatus.itemId, libraryStatus.server)
                                            } else {
                                                expandedSeason = if (isExpanded) null else season.seasonNumber
                                                if (!isExpanded && episodesBySeason[season.seasonNumber] == null) {
                                                    scope.launch {
                                                        loadingSeasons = loadingSeasons + season.seasonNumber
                                                        episodesBySeason[season.seasonNumber] = repository.fetchSeasonEpisodesSmart(
                                                            detail,
                                                            season.seasonNumber,
                                                            libraryStatus.itemId,
                                                            libraryStatus.server,
                                                        )
                                                        loadingSeasons = loadingSeasons - season.seasonNumber
                                                    }
                                                }
                                            }
                                        },
                                    ) {
                                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
                                                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                                        Text(
                                                            text = season.name.ifBlank { if (season.seasonNumber == 0) "特别篇" else "第 ${season.seasonNumber} 季" },
                                                            color = colors.textPrimary,
                                                            fontSize = 16.sp,
                                                            fontWeight = FontWeight.Bold,
                                                            maxLines = 1,
                                                            overflow = TextOverflow.Ellipsis,
                                                            modifier = Modifier.weight(1f),
                                                        )
                                                        when {
                                                            seasonExistingSet.isNotEmpty() && season.episodeCount > 0 && seasonExistingSet.size < season.episodeCount -> {
                                                                NativeAdaptiveBadge(
                                                                    text = "已入库 ${seasonExistingSet.size}/${season.episodeCount}",
                                                                    tint = colors.warning,
                                                                )
                                                            }
                                                            seasonExistingSet.isNotEmpty() -> {
                                                                NativeAdaptiveBadge(text = "已入库", tint = colors.success)
                                                            }
                                                            episodeAvailabilityLoaded -> {
                                                                NativeAdaptiveBadge(text = "未入库", tint = colors.textMuted)
                                                            }
                                                        }
                                                        Icon(
                                                            imageVector = if (onOpenSeasonDetail != null) {
                                                                Icons.AutoMirrored.Rounded.KeyboardArrowRight
                                                            } else if (isExpanded) {
                                                                Icons.Rounded.ExpandLess
                                                            } else {
                                                                Icons.Rounded.ExpandMore
                                                            },
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
                                                            .background(
                                                                if (isSeasonSub) subscribedEmeraldBg else colors.chipFill,
                                                            )
                                                            .border(
                                                                0.8.dp,
                                                                if (isSeasonSub) subscribedEmeraldAccent else colors.chipBorder,
                                                                CircleShape,
                                                            )
                                                            .clickable {
                                                                if (isSeasonSub) {
                                                                    pendingUnsubscribeSeason = season.seasonNumber
                                                                    showUnsubscribeDialog = true
                                                                } else {
                                                                    scope.launch {
                                                                        subscribeTarget(season.seasonNumber, season.episodeCount)
                                                                    }
                                                                }
                                                            }
                                                            .padding(horizontal = 12.dp, vertical = 5.5.dp),
                                                    ) {
                                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                                            Icon(
                                                                if (isSeasonSub) Icons.Rounded.CheckCircle else Icons.Rounded.Add,
                                                                contentDescription = null,
                                                                tint = if (isSeasonSub) Color.White else colors.textPrimary,
                                                                modifier = Modifier.size(14.dp),
                                                            )
                                                            Text(
                                                                if (isSeasonSub) "第 ${season.seasonNumber} 季已订阅" else "订阅本季",
                                                                color = if (isSeasonSub) Color.White else colors.textPrimary,
                                                                fontSize = 12.sp,
                                                                fontWeight = FontWeight.SemiBold,
                                                            )
                                                        }
                                                    }
                                                }
                                            }

                                            // 横向滚动 16:9 横版剧照卡片列表（与媒体库详情页剧集列表 100% 视觉一致）
                                            if (isExpanded) {
                                                val eps = episodesBySeason[season.seasonNumber].orEmpty()
                                                if (eps.isEmpty() && season.seasonNumber in loadingSeasons) {
                                                    NativeEpisodeShelfSkeleton(
                                                        cardWidth = 224.dp,
                                                        cardHeight = 126.dp,
                                                        count = 3,
                                                    )
                                                } else if (eps.isNotEmpty()) {
                                                    val existingEps = libraryStatus.existingEpisodesBySeason[season.seasonNumber].orEmpty().toSet()
                                                    LazyRow(
                                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                                    ) {
                                                        items(eps, key = { "s${season.seasonNumber}_e${it.episodeNumber}" }) { ep ->
                                                            val inLibEp = ep.episodeNumber in existingEps
                                                            val stillUrl = ep.stillPath ?: detail.backdropPath ?: season.posterPath ?: detail.posterPath
                                                            Column(
                                                                modifier = Modifier.width(224.dp),
                                                                verticalArrangement = Arrangement.spacedBy(6.dp),
                                                            ) {
                                                                Box(
                                                                    modifier = Modifier
                                                                        .fillMaxWidth()
                                                                        .aspectRatio(16f / 9f)
                                                                        .clip(RoundedCornerShape(14.dp))
                                                                        .background(colors.surfaceContainerHigh)
                                                                        .border(0.6.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(14.dp)),
                                                                ) {
                                                                    if (!stillUrl.isNullOrBlank()) {
                                                                        AsyncImage(
                                                                            model = stillUrl,
                                                                            contentDescription = ep.name,
                                                                            contentScale = ContentScale.Crop,
                                                                            modifier = Modifier.fillMaxSize(),
                                                                        )
                                                                    }
                                                                    Box(
                                                                        modifier = Modifier
                                                                            .align(Alignment.TopStart)
                                                                            .padding(8.dp)
                                                                            .clip(CircleShape)
                                                                            .background(Color.Black.copy(alpha = 0.62f))
                                                                            .padding(horizontal = 8.dp, vertical = 2.5.dp),
                                                                    ) {
                                                                        Text(
                                                                            text = "E%02d".format(ep.episodeNumber),
                                                                            color = Color.White,
                                                                            fontSize = 11.sp,
                                                                            fontWeight = FontWeight.Bold,
                                                                        )
                                                                    }
                                                                    if (inLibEp) {
                                                                        Row(
                                                                            modifier = Modifier
                                                                                .align(Alignment.TopEnd)
                                                                                .padding(8.dp)
                                                                                .clip(CircleShape)
                                                                                .background(Color(0xFF1F9D55).copy(alpha = 0.92f))
                                                                                .padding(horizontal = 7.dp, vertical = 2.5.dp),
                                                                            verticalAlignment = Alignment.CenterVertically,
                                                                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                                                                        ) {
                                                                            Icon(Icons.Rounded.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(11.dp))
                                                                            Text("已入库", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                                                                        }
                                                                    }
                                                                    if ((ep.runtime ?: 0) > 0) {
                                                                        Box(
                                                                            modifier = Modifier
                                                                                .align(Alignment.BottomEnd)
                                                                                .padding(8.dp)
                                                                                .clip(RoundedCornerShape(6.dp))
                                                                                .background(Color.Black.copy(alpha = 0.64f))
                                                                                .padding(horizontal = 6.dp, vertical = 2.dp),
                                                                        ) {
                                                                            Text("${ep.runtime}分钟", color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                                                                        }
                                                                    }
                                                                }
                                                                Text(
                                                                    text = "${ep.episodeNumber}. ${ep.name.ifBlank { "第 ${ep.episodeNumber} 集" }}",
                                                                    color = colors.textPrimary,
                                                                    fontSize = 13.5.sp,
                                                                    fontWeight = FontWeight.Bold,
                                                                    maxLines = 1,
                                                                    overflow = TextOverflow.Ellipsis,
                                                                )
                                                                val descText = ep.overview.ifBlank { ep.airDate }
                                                                if (descText.isNotBlank()) {
                                                                    Text(
                                                                        text = descText,
                                                                        color = colors.textMuted,
                                                                        fontSize = 12.sp,
                                                                        lineHeight = 16.sp,
                                                                        maxLines = 2,
                                                                        overflow = TextOverflow.Ellipsis,
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

                    // 5. 演职员真人圆形头像横栏（点击推入独立全屏 `PersonDetailScreen` 页面）
                    if (credits.isEmpty() && isDetailLoading) {
                        item(key = "md_cast_loading") {
                            NativeCastRowSkeleton(
                                avatarSize = 72.dp,
                                contentPadding = PaddingValues(horizontal = margin),
                                showHeader = true,
                            )
                        }
                    } else if (credits.isNotEmpty()) {
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
            }
        }

        // 顶部状态栏渐进柔化罩（上滚后仅在绘制层平滑浮现，保护状态栏文字与悬浮返回按钮清晰可读）
        NativeTopStatusBarProgressiveBlur(
            visibilityProgressProvider = easedProvider,
            extraHeight = 56.dp,
            modifier = Modifier.align(Alignment.TopCenter),
        )

        // 左上角悬浮磨砂返回按钮（Android 标准 ArrowBack Up 图标，自动避让状态栏与左侧刘海）
        CinematicCircleButton(
            icon = Icons.AutoMirrored.Rounded.ArrowBack,
            contentDescription = "返回",
            onClick = onBack,
            size = if (isCompactLandscape) 40.dp else 44.dp,
            modifier = Modifier
                .align(Alignment.TopStart)
                .windowInsetsPadding(
                    WindowInsets.statusBars
                        .union(WindowInsets.displayCutout)
                        .only(WindowInsetsSides.Top + WindowInsetsSides.Start),
                )
                .padding(start = 16.dp, top = if (isCompactLandscape) 6.dp else 8.dp),
        )
    }

    // 点击已订阅按钮：支持查看关联文件详情（若已知 subscribeId）或二次确认取消订阅
    if (showUnsubscribeDialog) {
        val targetSeason = pendingUnsubscribeSeason
        val knownSubId = if (isTv && targetSeason != null) {
            seasonSubscribeIds[targetSeason] ?: libraryStatus.seasonSubscribeIds[targetSeason]
        } else {
            movieSubscribeId ?: libraryStatus.subscribeId
        }
        AlertDialog(
            onDismissRequest = { showUnsubscribeDialog = false },
            title = {
                Text(
                    if (isTv && targetSeason != null) "第 $targetSeason 季已订阅" else "《${detail.title}》已订阅",
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        if (knownSubId != null && knownSubId > 0) {
                            "你可以查看当前订阅关联的下载任务与媒体库文件详情，或取消该订阅。"
                        } else {
                            "确认取消该订阅吗？取消后将不再自动搜索与下载更新。"
                        },
                    )
                    if (knownSubId != null && knownSubId > 0) {
                        NativeAdaptivePill(
                            title = "查看订阅文件详情",
                            selected = true,
                            icon = Icons.Rounded.FolderOpen,
                            tint = colors.accent,
                            onClick = {
                                showUnsubscribeDialog = false
                                activeSubscribeFilesId = knownSubId
                            },
                        )
                    }
                }
            },
            dismissButton = {
                TextButton(onClick = { showUnsubscribeDialog = false }) {
                    Text("保留订阅")
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showUnsubscribeDialog = false
                        scope.launch {
                            isMutatingSubscribe = true
                            val (ok, msg) = repository.unsubscribeMediaWithMessage(detail, season = if (isTv) targetSeason else null)
                            isMutatingSubscribe = false
                            if (ok) {
                                if (isTv && targetSeason != null) {
                                    userSeasonOverrides[targetSeason] = false
                                    subscribedSeasons = subscribedSeasons - targetSeason
                                    seasonSubscribeIds.remove(targetSeason)
                                    feedback = "已取消第 $targetSeason 季订阅"
                                } else {
                                    userMovieOverride = false
                                    subscribedMovie = false
                                    movieSubscribeId = null
                                    feedback = "已取消订阅"
                                }
                                feedbackIsError = false
                            } else {
                                feedbackIsError = true
                                feedback = msg
                            }
                        }
                    },
                ) {
                    Text("取消订阅", color = colors.danger)
                }
            },
        )
    }

    activeSubscribeFilesId?.let { subId ->
        SubscribeFilesSheet(
            subscribeId = subId,
            seedSubscribe = SubscribeItemDto(
                id = subId,
                name = detail.title,
                year = detail.year,
                type = if (isTv) "电视剧" else "电影",
                season = pendingUnsubscribeSeason ?: (if (isTv) primarySeason else null),
                poster = detail.posterPath,
                backdrop = detail.backdropPath,
                vote = detail.voteAverage,
            ),
            repository = repository,
            onDismiss = { activeSubscribeFilesId = null },
            onPlayMedia = onPlayMedia,
            onOpenServerItem = onOpenServerDetail?.let { cb ->
                { itemId, server, fallbackTitle ->
                    activeSubscribeFilesId = null
                    cb(itemId, server, fallbackTitle)
                }
            },
        )
    }
}

/**
 * 独立原生人物详情页（1:1 复刻 iOS `NativePersonDetailPage.swift` + Android 独立路由压栈）：
 * 居中 116dp 圆形人物肖像（短屏横屏自动切换紧凑横排肖像栏）、职业/生日/出生地履历、可展开人物简介玻璃卡、自适应参演作品海报网格，
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
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val columns = AdaptiveDeviceLayout.posterGridColumns()
    val gridState = rememberLazyGridState()

    var person by remember(seed.id) { mutableStateOf(seed) }
    var works by remember(seed.id) { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var isLoading by remember(seed.id) { mutableStateOf(true) }
    var bioExpanded by remember(seed.id) { mutableStateOf(false) }

    LaunchedEffect(seed.id) {
        isLoading = true
        val (enriched, list) = repository.fetchPersonDetail(seed)
        person = enriched
        works = list
        isLoading = false
    }

    ExpressiveTintedScaffold(
        title = person.name.ifBlank { "人物详情" },
        subtitle = person.department.takeIf { it.isNotBlank() },
        onBack = onBack,
    ) {
        if (isLoading && person.name.isBlank() && person.profilePath.isNullOrBlank()) {
            NativePersonDetailSkeleton()
        } else {
        ProvideSkeletonShimmer {
        LazyVerticalGrid(
            state = gridState,
            columns = GridCells.Fixed(columns),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = if (compactHeight) 12.dp else 20.dp,
                bottom = 28.dp + bottomOverlayInset,
            ),
            horizontalArrangement = Arrangement.spacedBy(11.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 人物头像与履历信息（短高度横屏切换紧凑横排布局，避免 116dp 竖向堆叠吞噬网格）
            item(span = { GridItemSpan(maxLineSpan) }) {
                val facts = listOfNotNull(
                    person.department.ifBlank { null },
                    person.birthday.ifBlank { null },
                    person.placeOfBirth.ifBlank { null },
                ).joinToString(" · ")
                if (compactHeight) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(72.dp)
                                .clip(CircleShape)
                                .background(colors.chipFill)
                                .border(1.dp, colors.borderSubtle.copy(alpha = 0.45f), CircleShape),
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
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(
                                text = person.name,
                                color = colors.textPrimary,
                                fontSize = 19.sp,
                                fontWeight = FontWeight.ExtraBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (facts.isNotBlank()) {
                                Text(
                                    text = facts,
                                    color = colors.textSecondary,
                                    fontSize = 13.sp,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            } else if (isLoading) {
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier.size(width = 160.dp, height = 13.dp),
                                )
                            }
                        }
                    }
                } else {
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
                                .border(1.dp, colors.borderSubtle.copy(alpha = 0.45f), CircleShape),
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
                        if (facts.isNotBlank()) {
                            Text(
                                text = facts,
                                color = colors.textSecondary,
                                fontSize = 13.sp,
                                textAlign = TextAlign.Center,
                            )
                        } else if (isLoading) {
                            NativeSkeletonBlock(
                                cornerRadius = 5.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 168.dp, height = 13.dp),
                            )
                        }
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
            } else if (isLoading) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    CinematicPanel(padding = 16.dp, showsShadow = false) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("人物简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            NativeOverviewLinesSkeleton(lines = 4)
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
            } else if (isLoading) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    NativeSectionHeader(title = "参演作品")
                }
                nativePosterGridSkeletonItems(
                    columns = columns,
                    count = columns * 2,
                )
            }
        }
        }
        }
    }
}

// ==================== 季媒体与分集详情页（点击媒体详情单季卡片进入） ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediaSeasonDetailScreen(
    seriesItem: MediaCardItem,
    initialSeason: MediaSeasonDto,
    initialSeriesItemId: String = "",
    initialServer: String = "",
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onSearchResource: (String) -> Unit,
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val cardCols = AdaptiveDeviceLayout.cardGridColumns()
    val scope = rememberCoroutineScope()

    val seasonNum = initialSeason.seasonNumber
    val seasonTitle = initialSeason.name.ifBlank { if (seasonNum == 0) "特别篇" else "第 $seasonNum 季" }

    var seasonInfo by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf(initialSeason) }
    var episodes by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf<List<MediaEpisodeDto>>(emptyList()) }
    var playableMap by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf<Map<Int, String>>(emptyMap()) }
    var existingSet by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf<Set<Int>>(emptySet()) }
    var resolvedSeriesId by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf(initialSeriesItemId) }
    var resolvedServer by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf(initialServer) }
    var isSubscribed by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf(false) }
    var subscribeRecordId by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf<Int?>(null) }
    var isLoading by remember(seriesItem.resolvedId, seasonNum) { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var isMutatingSub by remember { mutableStateOf(false) }
    var playingEpisodeNum by remember { mutableStateOf<Int?>(null) }
    var expandOverview by remember { mutableStateOf(false) }
    var showUnsubscribeConfirm by remember { mutableStateOf(false) }
    var activeSubscribeFilesId by remember { mutableStateOf<Int?>(null) }
    var feedback by remember { mutableStateOf<String?>(null) }
    var feedbackIsError by remember { mutableStateOf(false) }
    var reloadTrigger by remember { mutableStateOf(0) }

    suspend fun reloadSeasonAll() {
        if (!isRefreshing) isLoading = true
        coroutineScope {
            val statusDef = async { repository.checkMediaInLibraryStatus(seriesItem, season = seasonNum) }
            val seasonsDef = async { repository.fetchMediaSeasonsForItem(seriesItem) }
            val remoteExistsDef = async { repository.fetchRemoteExistingEpisodes(seriesItem, season = seasonNum) }

            val libSt = statusDef.await()
            if (libSt.itemId.isNotBlank()) resolvedSeriesId = libSt.itemId
            if (libSt.server.isNotBlank()) resolvedServer = libSt.server
            isSubscribed = seasonNum in libSt.subscribedSeasons.keys || libSt.subscribed
            subscribeRecordId = libSt.seasonSubscribeIds[seasonNum] ?: libSt.subscribeId

            seasonsDef.await().firstOrNull { it.seasonNumber == seasonNum }?.let { enriched ->
                seasonInfo = seasonInfo.copy(
                    name = enriched.name.ifBlank { seasonInfo.name },
                    overview = enriched.overview.ifBlank { seasonInfo.overview },
                    airDate = enriched.airDate.ifBlank { seasonInfo.airDate },
                    episodeCount = if (enriched.episodeCount > 0) enriched.episodeCount else seasonInfo.episodeCount,
                    posterPath = enriched.posterPath ?: seasonInfo.posterPath,
                    voteAverage = if (enriched.voteAverage > 0.0) enriched.voteAverage else seasonInfo.voteAverage,
                )
            }

            val playableDef = async {
                if (resolvedSeriesId.isNotBlank()) {
                    repository.fetchPlayableSeasonEpisodes(resolvedSeriesId, seasonNum, resolvedServer.ifBlank { null })
                } else {
                    emptyMap()
                }
            }
            val episodesDef = async {
                repository.fetchSeasonEpisodesSmart(
                    item = seriesItem,
                    seasonNumber = seasonNum,
                    seriesItemId = resolvedSeriesId,
                    server = resolvedServer,
                )
            }

            val loadedPlayable = playableDef.await()
            val loadedRemote = remoteExistsDef.await()[seasonNum].orEmpty()
            val loadedEpisodes = episodesDef.await()

            playableMap = loadedPlayable
            existingSet = buildSet {
                addAll(libSt.existingEpisodesBySeason[seasonNum].orEmpty())
                addAll(loadedRemote)
                addAll(loadedPlayable.keys)
            }

            episodes = if (loadedEpisodes.isNotEmpty()) {
                loadedEpisodes
            } else {
                val maxEp = maxOf(seasonInfo.episodeCount, existingSet.maxOrNull() ?: 0)
                if (maxEp > 0) {
                    (1..maxEp).map { num -> MediaEpisodeDto(episodeNumber = num, name = "第 $num 集") }
                } else {
                    emptyList()
                }
            }
        }
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(seriesItem.resolvedId, seasonNum, reloadTrigger) {
        reloadSeasonAll()
    }

    fun launchEpisodePlayback(targetEp: MediaEpisodeDto) {
        val targetItemId = playableMap[targetEp.episodeNumber] ?: return
        if (playingEpisodeNum != null) return
        playingEpisodeNum = targetEp.episodeNumber
        scope.launch {
            feedback = null
            val srv = resolvedServer.takeIf { it.isNotBlank() }
            val epByNum = episodes.associateBy { it.episodeNumber }
            val sortedNums = playableMap.keys.sorted()
            var targetQueueIdx = 0
            val queue = sortedNums.mapIndexedNotNull { idx, epNum ->
                val qid = playableMap[epNum] ?: return@mapIndexedNotNull null
                if (epNum == targetEp.episodeNumber) targetQueueIdx = idx
                val meta = epByNum[epNum]
                val epLabel = "S%02dE%02d".format(seasonNum, epNum)
                val qTitle = if (!meta?.name.isNullOrBlank()) {
                    "${seriesItem.title} · $epLabel · ${meta!!.name}"
                } else {
                    "${seriesItem.title} · $epLabel"
                }
                MediaPlaybackRequest(
                    url = "",
                    title = qTitle,
                    subtitle = srv.orEmpty(),
                    artworkUrl = meta?.stillPath ?: seasonInfo.posterPath ?: seriesItem.posterPath,
                    itemId = qid,
                    server = srv.orEmpty(),
                    queueIndex = idx,
                    lazySpec = QueueTrackSpec.MediaServerItem(itemId = qid, server = srv.orEmpty()),
                )
            }
            val manifest = repository.fetchVideoStreamInfo(targetItemId, srv)
            playingEpisodeNum = null
            if (manifest != null) {
                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                val epCode = "S%02dE%02d".format(seasonNum, targetEp.episodeNumber)
                val displayEpName = targetEp.name.ifBlank { "第 ${targetEp.episodeNumber} 集" }
                onPlayMedia(
                    MediaPlaybackRequest(
                        url = manifest.contentUrl,
                        title = "${seriesItem.title} · $epCode · $displayEpName",
                        subtitle = listOfNotNull(
                            manifest.server.ifBlank { srv },
                            seasonTitle,
                        ).joinToString(" · "),
                        artworkUrl = targetEp.stillPath ?: seasonInfo.posterPath ?: seriesItem.posterPath,
                        isAudio = manifest.mediaType == "audio",
                        lyricsLrc = lrc,
                        headers = manifest.headers,
                        sameOriginHeaders = manifest.sameOriginHeaders,
                        streamHeaders = manifest.streamHeaders,
                        proxyFallbackUrl = manifest.proxyFallbackUrl,
                        activeRouteKind = manifest.activeRouteKind,
                        fallbackRoutes = manifest.fallbackRoutes,
                        originUrl = manifest.originUrl,
                        itemId = manifest.itemId,
                        server = manifest.server.ifBlank { srv.orEmpty() },
                        serverType = manifest.serverType,
                        mediaSourceId = manifest.mediaSourceId.orEmpty(),
                        playSessionId = manifest.playSessionId,
                        progressSyncMode = manifest.progressSyncMode,
                        resumePositionMs = manifest.resumePositionMs,
                        subtitles = manifest.subtitles.map {
                            SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                        },
                        danmakuEnabled = manifest.danmakuEnabled,
                        seriesName = manifest.seriesName?.takeIf { it.isNotBlank() } ?: seriesItem.title,
                        seasonNumber = manifest.seasonNumber ?: seasonNum,
                        episodeNumber = manifest.episodeNumber ?: targetEp.episodeNumber,
                        year = manifest.year ?: seriesItem.year.toIntOrNull(),
                        tmdbId = manifest.tmdbId ?: seriesItem.tmdbId?.toString(),
                        fileName = manifest.fileName,
                        fileSize = manifest.fileSize,
                        queue = queue,
                        queueIndex = targetQueueIdx,
                    ),
                )
            } else {
                feedbackIsError = true
                feedback = "无法读取该集的播放流，请检查媒体服务器状态"
            }
        }
    }

    ExpressiveTintedScaffold(
        title = seasonTitle,
        subtitle = seriesItem.title,
        onBack = onBack,
        actions = {
            ExpressiveHeaderActionButton(
                icon = Icons.Rounded.Refresh,
                contentDescription = "刷新本季信息",
                onClick = { reloadTrigger += 1 },
            )
        },
    ) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                isRefreshing = true
                scope.launch { reloadSeasonAll() }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 14.dp,
                    bottom = bottomOverlayInset + 28.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                item(key = "season_hero") {
                    SeasonDetailHeroCard(
                        seriesItem = seriesItem,
                        season = seasonInfo,
                        inLibraryCount = existingSet.size,
                        totalEpisodes = maxOf(seasonInfo.episodeCount, episodes.size),
                        serverName = resolvedServer,
                        isLoading = isLoading,
                    )
                }

                item(key = "season_actions") {
                    val firstPlayableNum = playableMap.keys.sorted().firstOrNull()
                    SeasonDetailActionRow(
                        firstPlayableEpisode = firstPlayableNum,
                        serverName = resolvedServer,
                        isPlayingFirst = firstPlayableNum != null && playingEpisodeNum == firstPlayableNum,
                        isSubscribed = isSubscribed,
                        isMutatingSub = isMutatingSub,
                        hasSubscribeFiles = isSubscribed && (subscribeRecordId ?: 0) > 0,
                        onPlayFirst = {
                            val num = firstPlayableNum ?: return@SeasonDetailActionRow
                            val ep = episodes.firstOrNull { it.episodeNumber == num }
                                ?: MediaEpisodeDto(episodeNumber = num, name = "第 $num 集")
                            launchEpisodePlayback(ep)
                        },
                        onToggleSubscribe = {
                            if (isSubscribed) {
                                showUnsubscribeConfirm = true
                            } else {
                                if (isMutatingSub) return@SeasonDetailActionRow
                                isMutatingSub = true
                                scope.launch {
                                    val identity = MoviePilotRepository.normalizeCanonicalMediaIdentity(
                                        source = seriesItem.source,
                                        mediaId = seriesItem.mediaId,
                                        tmdbId = seriesItem.tmdbId,
                                        doubanId = seriesItem.doubanId,
                                        bangumiId = seriesItem.bangumiId,
                                        imdbId = seriesItem.imdbId,
                                        tvdbId = seriesItem.tvdbId,
                                    )
                                    val (ok, msg, subId) = repository.createOrUpdateSubscriptionFull(
                                        SubscribeItemDto(
                                            name = seriesItem.title,
                                            year = seriesItem.year,
                                            type = "电视剧",
                                            season = seasonNum,
                                            totalEpisode = maxOf(seasonInfo.episodeCount, episodes.size),
                                            mediaSource = identity?.first ?: "themoviedb",
                                            mediaId = identity?.second.orEmpty(),
                                        ),
                                    )
                                    isMutatingSub = false
                                    if (ok) {
                                        isSubscribed = true
                                        if (subId != null && subId > 0) subscribeRecordId = subId
                                        feedbackIsError = false
                                        feedback = "已订阅 $seasonTitle"
                                    } else {
                                        feedbackIsError = true
                                        feedback = msg
                                    }
                                }
                            }
                        },
                        onOpenFiles = { subscribeRecordId?.let { activeSubscribeFilesId = it } },
                        onSearchSeason = {
                            onSearchResource("${seriesItem.title} S%02d".format(seasonNum))
                        },
                    )
                }

                feedback?.let { msg ->
                    item(key = "season_feedback") {
                        Text(
                            text = msg,
                            color = if (feedbackIsError) colors.warning else colors.success,
                            fontSize = 13.sp,
                        )
                    }
                }

                val effectiveOverview = seasonInfo.overview.ifBlank { seriesItem.overview }
                if (effectiveOverview.isNotBlank()) {
                    item(key = "season_overview") {
                        CinematicPanel(
                            padding = 16.dp,
                            showsShadow = false,
                            modifier = Modifier.clickable { expandOverview = !expandOverview },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("本季简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                Text(
                                    text = effectiveOverview,
                                    color = colors.textSecondary,
                                    fontSize = 14.sp,
                                    lineHeight = 22.sp,
                                    maxLines = if (expandOverview) Int.MAX_VALUE else 4,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (effectiveOverview.length > 100) {
                                    Text(
                                        text = if (expandOverview) "收起简介" else "展开全部",
                                        color = colors.textMuted,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                    )
                                }
                            }
                        }
                    }
                }

                item(key = "episodes_header") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("本季剧集", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        if (episodes.isNotEmpty()) {
                            Text(
                                text = if (existingSet.isNotEmpty()) {
                                    "已入库 ${existingSet.size} / 共 ${episodes.size} 集"
                                } else {
                                    "共 ${episodes.size} 集"
                                },
                                color = colors.textMuted,
                                fontSize = 12.5.sp,
                            )
                        }
                    }
                }

                if (isLoading && episodes.isEmpty()) {
                    item(key = "episodes_skeleton") {
                        NativeCardListSkeleton(
                            style = SkeletonCardStyle.PosterRow,
                            count = 4,
                            columns = cardCols,
                            contentPadding = PaddingValues(0.dp),
                        )
                    }
                } else if (episodes.isEmpty()) {
                    item(key = "episodes_empty") {
                        CinematicPanel(padding = 24.dp, showsShadow = false) {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Text("暂无本季分集明细", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                                Text("数据源尚未提供该季的分集信息。", color = colors.textSecondary, fontSize = 13.sp)
                            }
                        }
                    }
                } else {
                    items(episodes, key = { "ep_${seasonNum}_${it.episodeNumber}" }) { ep ->
                        val isPlayable = playableMap.containsKey(ep.episodeNumber)
                        val inLib = isPlayable || ep.episodeNumber in existingSet
                        val stillUrl = ep.stillPath ?: seriesItem.backdropPath ?: seasonInfo.posterPath ?: seriesItem.posterPath
                        SeasonDetailEpisodeCard(
                            episode = ep,
                            stillUrl = stillUrl,
                            inLibrary = inLib,
                            isPlayable = isPlayable,
                            isPlaying = playingEpisodeNum == ep.episodeNumber,
                            busy = playingEpisodeNum != null,
                            onPlay = { launchEpisodePlayback(ep) },
                            onSearchEpisode = {
                                onSearchResource("${seriesItem.title} S%02dE%02d".format(seasonNum, ep.episodeNumber))
                            },
                        )
                    }
                }
            }
        }
    }

    if (showUnsubscribeConfirm) {
        AlertDialog(
            onDismissRequest = { showUnsubscribeConfirm = false },
            title = { Text("取消订阅") },
            text = { Text("确认取消《${seriesItem.title}》$seasonTitle 的订阅吗？") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showUnsubscribeConfirm = false
                        scope.launch {
                            isMutatingSub = true
                            val (ok, msg) = repository.unsubscribeMediaWithMessage(seriesItem, season = seasonNum)
                            isMutatingSub = false
                            if (ok) {
                                isSubscribed = false
                                subscribeRecordId = null
                                feedbackIsError = false
                                feedback = "已取消 $seasonTitle 订阅"
                            } else {
                                feedbackIsError = true
                                feedback = msg
                            }
                        }
                    },
                ) {
                    Text("取消订阅", color = colors.danger, fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(onClick = { showUnsubscribeConfirm = false }) {
                    Text("保留")
                }
            },
        )
    }

    activeSubscribeFilesId?.let { subId ->
        SubscribeFilesSheet(
            subscribeId = subId,
            seedSubscribe = SubscribeItemDto(
                id = subId,
                name = seriesItem.title,
                year = seriesItem.year,
                type = "电视剧",
                season = seasonNum,
                poster = seasonInfo.posterPath ?: seriesItem.posterPath,
                backdrop = seriesItem.backdropPath,
            ),
            repository = repository,
            onDismiss = { activeSubscribeFilesId = null },
            onPlayMedia = onPlayMedia,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SeasonDetailHeroCard(
    seriesItem: MediaCardItem,
    season: MediaSeasonDto,
    inLibraryCount: Int,
    totalEpisodes: Int,
    serverName: String,
    isLoading: Boolean,
) {
    val colors = LocalMoviePilotColors.current
    val posterUrl = season.posterPath ?: seriesItem.posterPath
    val rating = if (season.voteAverage > 0.0) season.voteAverage else seriesItem.voteAverage

    CinematicPanel(padding = 16.dp, showsShadow = false) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(
                modifier = Modifier
                    .width(96.dp)
                    .aspectRatio(2f / 3f)
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.chipFill),
                contentAlignment = Alignment.Center,
            ) {
                if (!posterUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = posterUrl,
                        contentDescription = season.name,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Text(seriesItem.title.take(2), color = colors.textPrimary, fontWeight = FontWeight.Bold)
                }
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                Text(
                    text = seriesItem.title,
                    color = colors.textSecondary,
                    fontSize = 12.5.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = season.name.ifBlank { if (season.seasonNumber == 0) "特别篇" else "第 ${season.seasonNumber} 季" },
                    color = colors.textPrimary,
                    fontSize = 19.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )

                val metaText = listOfNotNull(
                    season.airDate.takeIf { it.isNotBlank() },
                    if (totalEpisodes > 0) "共 $totalEpisodes 集" else null,
                ).joinToString(" · ")
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (metaText.isNotBlank()) {
                        Text(metaText, color = colors.textSecondary, fontSize = 12.5.sp)
                    }
                    if (rating > 0.0) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.Star, contentDescription = null, tint = Color(0xFFFFC845), modifier = Modifier.size(13.dp))
                            Text(" ${String.format("%.1f", rating)}", color = colors.warning, fontSize = 12.5.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }

                val srvSuffix = if (serverName.isNotBlank()) " · $serverName" else ""
                when {
                    inLibraryCount > 0 && totalEpisodes > 0 && inLibraryCount < totalEpisodes -> {
                        NativeAdaptiveBadge(text = "部分入库 $inLibraryCount/$totalEpisodes 集$srvSuffix", tint = colors.warning)
                    }
                    inLibraryCount > 0 && totalEpisodes > 0 -> {
                        NativeAdaptiveBadge(text = "已入库 $inLibraryCount/$totalEpisodes 集$srvSuffix", tint = colors.success)
                    }
                    inLibraryCount > 0 -> {
                        NativeAdaptiveBadge(text = "已入库 $inLibraryCount 集$srvSuffix", tint = colors.success)
                    }
                    !isLoading -> {
                        NativeAdaptiveBadge(text = "未入库", tint = colors.textMuted)
                    }
                }

                if (seriesItem.genres.isNotEmpty()) {
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        seriesItem.genres.take(3).forEach { g ->
                            Box(
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(colors.chipFill)
                                    .border(0.6.dp, colors.chipBorder, CircleShape)
                                    .padding(horizontal = 9.dp, vertical = 3.dp),
                            ) {
                                Text(g, color = colors.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SeasonDetailActionRow(
    firstPlayableEpisode: Int?,
    serverName: String,
    isPlayingFirst: Boolean,
    isSubscribed: Boolean,
    isMutatingSub: Boolean,
    hasSubscribeFiles: Boolean,
    onPlayFirst: () -> Unit,
    onToggleSubscribe: () -> Unit,
    onOpenFiles: () -> Unit,
    onSearchSeason: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val emeraldBg = Color(0xFF1F9D55)

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (firstPlayableEpisode != null) {
            val srvSuffix = if (serverName.isNotBlank()) " · $serverName" else ""
            Button(
                onClick = onPlayFirst,
                enabled = !isPlayingFirst,
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.accent,
                    contentColor = colors.primaryButtonFg,
                ),
                shape = CircleShape,
                modifier = Modifier.fillMaxWidth().height(46.dp),
            ) {
                Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(6.dp))
                Text(
                    text = if (isPlayingFirst) "准备播放…" else "播放第 $firstPlayableEpisode 集$srvSuffix",
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Button(
                onClick = onToggleSubscribe,
                enabled = !isMutatingSub,
                colors = ButtonDefaults.buttonColors(
                    containerColor = when {
                        isSubscribed -> emeraldBg
                        colors.isDark -> Color.White
                        else -> colors.accent
                    },
                    contentColor = when {
                        isSubscribed -> Color.White
                        colors.isDark -> Color(0xFF14111D)
                        else -> colors.primaryButtonFg
                    },
                ),
                shape = CircleShape,
                modifier = Modifier.weight(1f).height(46.dp),
            ) {
                Icon(
                    imageVector = if (isSubscribed) Icons.Rounded.CheckCircle else Icons.Outlined.BookmarkBorder,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = when {
                        isMutatingSub -> "处理中…"
                        isSubscribed -> "本季已订阅"
                        else -> "订阅本季"
                    },
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                )
            }

            if (hasSubscribeFiles) {
                Box(
                    modifier = Modifier
                        .size(46.dp)
                        .clip(CircleShape)
                        .background(emeraldBg.copy(alpha = 0.20f))
                        .border(0.8.dp, emeraldBg.copy(alpha = 0.45f), CircleShape)
                        .clickable(onClick = onOpenFiles),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Rounded.FolderOpen,
                        contentDescription = "查看订阅文件详情",
                        tint = Color(0xFF34C759),
                        modifier = Modifier.size(20.dp),
                    )
                }
            }

            CinematicGlassSurface(
                shape = CircleShape,
                blurRadiusDp = 16.dp,
                useLiveBackdropBlur = false,
                modifier = Modifier
                    .weight(1f)
                    .height(46.dp)
                    .clickable(onClick = onSearchSeason),
            ) {
                Row(
                    modifier = Modifier.fillMaxSize(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("搜索本季", color = colors.textPrimary, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun SeasonDetailEpisodeCard(
    episode: MediaEpisodeDto,
    stillUrl: String?,
    inLibrary: Boolean,
    isPlayable: Boolean,
    isPlaying: Boolean,
    busy: Boolean,
    onPlay: () -> Unit,
    onSearchEpisode: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val isUpcoming = remember(episode.airDate) {
        runCatching {
            episode.airDate.length >= 10 &&
                java.time.LocalDate.parse(episode.airDate.take(10)).isAfter(java.time.LocalDate.now())
        }.getOrDefault(false)
    }

    CinematicPanel(
        padding = 12.dp,
        showsShadow = false,
        modifier = if (isPlayable && !busy) Modifier.clickable(onClick = onPlay) else Modifier,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Box(
                    modifier = Modifier
                        .width(138.dp)
                        .aspectRatio(16f / 9f)
                        .clip(RoundedCornerShape(11.dp))
                        .background(colors.surfaceContainerHigh)
                        .border(0.6.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(11.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    if (!stillUrl.isNullOrBlank()) {
                        AsyncImage(
                            model = stillUrl,
                            contentDescription = episode.name,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                    Box(
                        modifier = Modifier
                            .align(Alignment.TopStart)
                            .padding(6.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.66f))
                            .padding(horizontal = 7.dp, vertical = 2.dp),
                    ) {
                        Text(
                            text = "E%02d".format(episode.episodeNumber),
                            color = Color.White,
                            fontSize = 10.5.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                    if ((episode.runtime ?: 0) > 0) {
                        Box(
                            modifier = Modifier
                                .align(Alignment.BottomEnd)
                                .padding(6.dp)
                                .clip(RoundedCornerShape(5.dp))
                                .background(Color.Black.copy(alpha = 0.66f))
                                .padding(horizontal = 5.5.dp, vertical = 1.5.dp),
                        ) {
                            Text("${episode.runtime}分钟", color = Color.White, fontSize = 9.5.sp)
                        }
                    }
                    if (isPlayable) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(Color.Black.copy(alpha = 0.48f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.PlayArrow,
                                contentDescription = "播放本集",
                                tint = Color.White,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "${episode.episodeNumber}. ${episode.name.ifBlank { "第 ${episode.episodeNumber} 集" }}",
                            color = colors.textPrimary,
                            fontSize = 14.5.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        when {
                            inLibrary -> NativeAdaptiveBadge(text = "已入库", tint = colors.success)
                            isUpcoming -> NativeAdaptiveBadge(text = "未开播", tint = colors.info)
                            else -> NativeAdaptiveBadge(text = "未入库", tint = colors.textMuted)
                        }
                    }

                    if (episode.airDate.isNotBlank() || episode.voteAverage > 0.0) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            if (episode.airDate.isNotBlank()) {
                                Text(episode.airDate, color = colors.textSecondary, fontSize = 12.sp)
                            }
                            if (episode.voteAverage > 0.0) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Rounded.Star, contentDescription = null, tint = Color(0xFFFFC845), modifier = Modifier.size(12.dp))
                                    Text(" ${String.format("%.1f", episode.voteAverage)}", color = colors.warning, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }

                    if (episode.overview.isNotBlank()) {
                        Text(
                            text = episode.overview,
                            color = colors.textMuted,
                            fontSize = 12.sp,
                            lineHeight = 17.sp,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isPlayable) {
                    NativeAdaptivePill(
                        title = if (isPlaying) "准备播放…" else "播放本集",
                        selected = true,
                        icon = Icons.Rounded.PlayArrow,
                        tint = colors.accent,
                        onClick = { if (!busy) onPlay() },
                    )
                } else {
                    NativeAdaptivePill(
                        title = "搜本集",
                        selected = false,
                        icon = Icons.Rounded.Search,
                        onClick = onSearchEpisode,
                    )
                }
            }
        }
    }
}
