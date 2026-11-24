package com.moviepilot.feature.media

import android.content.Intent
import android.net.Uri
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
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Subtitles
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicGlassCapsule
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import com.moviepilot.feature.subscribe.SubscribeFilesSheet
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaLibraryStatusDto
import com.moviepilot.rustbridge.MediaPersonDto
import com.moviepilot.rustbridge.MediaServerBrowseItemDto
import com.moviepilot.rustbridge.MediaServerItemDetailDto
import com.moviepilot.rustbridge.MediaServerSourceDto
import com.moviepilot.rustbridge.MediaServerStreamTrackDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.SubscribeItemDto
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import java.util.Locale
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

private data class ExternalLinkChipItem(
    val title: String,
    val url: String,
)

private fun formatDurationMinutes(durationMs: Long?): String? {
    val ms = durationMs ?: return null
    if (ms <= 0L) return null
    val totalMin = (ms / 60_000L).coerceAtLeast(1L)
    val hours = totalMin / 60L
    val mins = totalMin % 60L
    return if (hours > 0L) {
        if (mins > 0L) "${hours}小时${mins}分钟" else "${hours}小时"
    } else {
        "${totalMin}分钟"
    }
}

private fun formatResumeClock(positionMs: Long): String {
    val totalSec = (positionMs / 1000L).coerceAtLeast(0L)
    val h = totalSec / 3600L
    val m = (totalSec % 3600L) / 60L
    val s = totalSec % 60L
    return if (h > 0L) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}

private fun formatBytesSize(bytes: Long?): String? {
    val b = bytes ?: return null
    if (b <= 0L) return null
    val gb = b / (1024.0 * 1024.0 * 1024.0)
    return if (gb >= 1.0) {
        String.format(Locale.US, "%.1f GB", gb)
    } else {
        String.format(Locale.US, "%.0f MB", b / (1024.0 * 1024.0))
    }
}

/**
 * 原生媒体服务器条目详情页（对应 `GET /api/v1/mediaserver/detail`，1:1 对齐参考界面）：
 * - 全幅响应式摄影级 Hero（紧凑横屏限高）、服务器品牌徽标、直放/续播与权威订阅切换、多版本源选择；
 * - 16:9 横版剧照横向滚动剧集列表（优先采用 `ep.thumb ?: ep.backdrop ?: detail.backdrop ?: ep.poster`）；
 * - 2:3 竖版海报 + 右下角半透明评分角标的「类似作品」横栏；
 * - 带链接图标的「链接」胶囊横栏（豆瓣 / IMDb / TheMovieDb / Trakt / TVDB / 播放页）；
 * - 顶对齐边框卡片式「媒体信息」轨道规格横栏（视频 / 音频 / 字幕；剧集页自动拉取首集或选中集媒体源）。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun MediaServerDetailScreen(
    itemId: String,
    server: String,
    fallbackTitle: String = "",
    fallbackPoster: String? = null,
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
    onSearchResource: (String) -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenServerDetail: (itemId: String, server: String, title: String, poster: String?) -> Unit,
    onOpenPerson: (MediaPersonDto) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val context = LocalContext.current
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
        isPortraitPhone -> 445.dp
        else -> 415.dp
    }
    val density = LocalDensity.current
    val heroHeightPx = with(density) { heroHeight.toPx().coerceAtLeast(1f) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val localHaze = remember { HazeState() }

    val screenKey = "$server:$itemId"
    var detail by remember(screenKey) { mutableStateOf<MediaServerItemDetailDto?>(null) }
    var seasons by remember(screenKey) { mutableStateOf<List<MediaServerBrowseItemDto>>(emptyList()) }
    var selectedSeasonId by remember(screenKey) { mutableStateOf<String?>(null) }
    var selectedSeasonNum by remember(screenKey) { mutableStateOf<Int?>(null) }
    var episodes by remember(screenKey) { mutableStateOf<List<MediaServerBrowseItemDto>>(emptyList()) }
    var selectedEpisodeId by remember(screenKey) { mutableStateOf<String?>(null) }
    var episodeFallbackSources by remember(screenKey) { mutableStateOf<List<MediaServerSourceDto>>(emptyList()) }
    var selectedSourceIndex by remember(screenKey) { mutableIntStateOf(0) }
    var similarItems by remember(screenKey) { mutableStateOf<List<MediaCardItem>>(emptyList()) }

    var expandOverview by remember(screenKey) { mutableStateOf(false) }
    var isLoading by remember(screenKey) { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var showTopMoreMenu by remember { mutableStateOf(false) }
    var feedback by remember(screenKey) { mutableStateOf<String?>(null) }
    var feedbackIsError by remember(screenKey) { mutableStateOf(false) }

    // 权威乐观订阅状态（跨异步加载保活，支持退订与查看订阅文件详情）
    var libraryStatus by remember(screenKey) { mutableStateOf(MediaLibraryStatusDto(inLibrary = true, server = server, itemId = itemId)) }
    var subscribedMovie by remember(screenKey) { mutableStateOf(false) }
    var subscribedSeasons by remember(screenKey) { mutableStateOf<Set<Int>>(emptySet()) }
    var userMovieOverride by remember(screenKey) { mutableStateOf<Boolean?>(null) }
    val userSeasonOverrides = remember(screenKey) { mutableStateMapOf<Int, Boolean>() }
    var movieSubscribeId by remember(screenKey) { mutableStateOf<Int?>(null) }
    val seasonSubscribeIds = remember(screenKey) { mutableStateMapOf<Int, Int>() }
    var showUnsubscribeDialog by remember(screenKey) { mutableStateOf(false) }
    var activeSubscribeFilesId by remember(screenKey) { mutableStateOf<Int?>(null) }
    var isMutatingSubscribe by remember(screenKey) { mutableStateOf(false) }

    fun toCardSeed(d: MediaServerItemDetailDto): MediaCardItem {
        val isTvItem = MoviePilotRepository.isTvType(d.mediaType.ifBlank { d.itemType })
        val normIdentity = MoviePilotRepository.normalizeCanonicalMediaIdentity(
            source = d.mediaSource,
            mediaId = d.mediaId,
            tmdbId = d.tmdbId?.toIntOrNull(),
            doubanId = d.doubanId,
            imdbId = d.imdbId,
            tvdbId = d.tvdbId,
        )
        return MediaCardItem(
            title = d.seriesName.ifBlank { d.title },
            year = d.year,
            type = if (isTvItem) "电视剧" else "电影",
            overview = d.overview,
            posterPath = d.poster ?: fallbackPoster,
            backdropPath = d.backdrop ?: d.thumb,
            voteAverage = d.rating,
            source = normIdentity?.first ?: "themoviedb",
            tmdbId = d.tmdbId?.toIntOrNull(),
            doubanId = d.doubanId,
            imdbId = d.imdbId,
            tvdbId = d.tvdbId,
            mediaId = normIdentity?.second,
            season = selectedSeasonNum ?: d.seasonNumber,
            serverItemId = d.itemId,
            serverName = d.server.ifBlank { server },
            serverType = d.serverType,
            inLibrary = true,
        )
    }

    suspend fun loadEpisodeStreamPreviewIfNeeded(epItemId: String?, srv: String, currentDetail: MediaServerItemDetailDto?) {
        if (currentDetail == null || currentDetail.mediaSources.isNotEmpty() || epItemId.isNullOrBlank()) return
        val epDetail = repository.fetchMediaServerItemDetail(epItemId, srv, enrichMetadata = false)
        if (epDetail != null && epDetail.mediaSources.isNotEmpty()) {
            episodeFallbackSources = epDetail.mediaSources
            selectedSourceIndex = 0
        }
    }

    suspend fun loadAll(clearOverrides: Boolean = false) {
        if (clearOverrides) {
            userMovieOverride = null
            userSeasonOverrides.clear()
        }
        val fetched = repository.fetchMediaServerItemDetail(itemId, server.ifBlank { null })
        if (fetched == null) {
            isLoading = false
            isRefreshing = false
            return
        }
        detail = fetched
        isLoading = false

        val activeSrv = fetched.server.ifBlank { server }
        val isSeries = fetched.itemType.equals("Series", ignoreCase = true) ||
            (MoviePilotRepository.isTvType(fetched.mediaType) &&
                !fetched.itemType.equals("Episode", ignoreCase = true) &&
                !fetched.itemType.equals("Season", ignoreCase = true))
        val isSeason = fetched.itemType.equals("Season", ignoreCase = true)

        coroutineScope {
            val similarDef = async { repository.fetchSimilarMediaForServerItem(fetched) }

            if (isSeries || isSeason) {
                val seriesTargetId = if (isSeason) {
                    fetched.seriesId?.takeIf { it.isNotBlank() } ?: fetched.parentId?.takeIf { it.isNotBlank() } ?: fetched.itemId
                } else {
                    fetched.itemId
                }
                val fetchedSeasons = repository.fetchMediaServerSeasons(seriesTargetId, activeSrv)
                seasons = fetchedSeasons
                val chosenSeason = if (isSeason) {
                    fetchedSeasons.firstOrNull { it.itemId == fetched.itemId || it.seasonNumber == fetched.seasonNumber }
                        ?: fetchedSeasons.firstOrNull()
                } else {
                    fetchedSeasons.firstOrNull { (it.seasonNumber ?: 1) > 0 } ?: fetchedSeasons.firstOrNull()
                }
                val sId = chosenSeason?.itemId ?: (if (isSeason) fetched.itemId else null)
                val sNum = chosenSeason?.seasonNumber ?: fetched.seasonNumber ?: 1
                selectedSeasonId = sId
                selectedSeasonNum = sNum

                val fetchedEps = repository.fetchMediaServerSeasonEpisodes(
                    seriesId = seriesTargetId,
                    server = activeSrv,
                    seasonId = sId,
                    seasonNumber = sNum,
                )
                episodes = fetchedEps
                val firstEp = fetchedEps.firstOrNull { !it.played } ?: fetchedEps.firstOrNull()
                selectedEpisodeId = firstEp?.itemId
                loadEpisodeStreamPreviewIfNeeded(firstEp?.itemId, activeSrv, fetched)
            }

            val isTv = MoviePilotRepository.isTvType(fetched.mediaType.ifBlank { fetched.itemType })
            val querySeason = if (isTv) (selectedSeasonNum ?: fetched.seasonNumber ?: 1) else null
            val statusDef = async {
                repository.checkMediaInLibraryStatus(toCardSeed(fetched), season = querySeason)
            }

            similarItems = similarDef.await()
            val libSt = statusDef.await()
            libraryStatus = libSt
            if (isTv) {
                subscribedSeasons = libSt.subscribedSeasons.keys +
                    (if (libSt.subscribed && querySeason != null) setOf(querySeason) else emptySet())
                libSt.seasonSubscribeIds.forEach { (k, v) -> seasonSubscribeIds[k] = v }
                if (querySeason != null && libSt.subscribeId != null) {
                    seasonSubscribeIds.putIfAbsent(querySeason, libSt.subscribeId!!)
                }
            } else {
                subscribedMovie = libSt.subscribed
                if (libSt.subscribeId != null) movieSubscribeId = libSt.subscribeId
            }
        }
        isRefreshing = false
    }

    LaunchedEffect(screenKey) {
        loadAll(clearOverrides = false)
    }

    val d = detail
    val isTv = d?.let { MoviePilotRepository.isTvType(it.mediaType.ifBlank { it.itemType }) } ?: false
    val activeServerName = d?.server?.ifBlank { server } ?: server
    val effectiveSources = remember(d?.mediaSources, episodeFallbackSources) {
        val own = d?.mediaSources.orEmpty()
        own.ifEmpty { episodeFallbackSources }
    }
    val selectedSource = effectiveSources.getOrNull(selectedSourceIndex.coerceIn(0, (effectiveSources.size - 1).coerceAtLeast(0)))
    val primaryVideoTrack = remember(selectedSource) {
        selectedSource?.streams?.firstOrNull { it.type.equals("video", ignoreCase = true) }
    }

    val effectiveSubscribedSeasons = remember(subscribedSeasons, userSeasonOverrides.toMap()) {
        val set = subscribedSeasons.toMutableSet()
        userSeasonOverrides.forEach { (sNum, active) ->
            if (active) set += sNum else set -= sNum
        }
        set.toSet()
    }
    val effectiveMovieSubscribed = userMovieOverride ?: subscribedMovie
    val currentSeasonNum = selectedSeasonNum ?: d?.seasonNumber ?: 1
    val isCurrentSubscribed = if (isTv) {
        currentSeasonNum in effectiveSubscribedSeasons || effectiveSubscribedSeasons.isNotEmpty()
    } else {
        effectiveMovieSubscribed
    }
    val subscribedEmeraldBg = Color(0xFF1F9D55)
    val subscribedEmeraldBorder = if (colors.isDark) Color(0xFF34C759) else Color(0xFF1F9D55)

    fun startStreamPlayback(targetItemId: String, titleFallback: String, subtitleFallback: String, artwork: String?, sourceId: String? = null) {
        scope.launch {
            feedback = null
            val manifest = repository.fetchVideoStreamInfo(targetItemId, activeServerName.ifBlank { null }, sourceId)
            if (manifest != null) {
                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                onPlayMedia(
                    MediaPlaybackRequest(
                        url = manifest.contentUrl,
                        title = manifest.title.ifBlank { titleFallback },
                        subtitle = subtitleFallback,
                        artworkUrl = artwork,
                        isAudio = manifest.mediaType == "audio",
                        lyricsLrc = lrc,
                        headers = manifest.headers,
                        itemId = manifest.itemId,
                        server = manifest.server.ifBlank { activeServerName },
                        resumePositionMs = manifest.resumePositionMs,
                        subtitles = manifest.subtitles.map {
                            SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                        },
                    ),
                )
            } else {
                feedbackIsError = true
                feedback = "暂无法从媒体服务器获取该条目的直放流"
            }
        }
    }

    suspend fun handleSubscribeCurrent() {
        val cur = detail ?: return
        if (isMutatingSubscribe) return
        isMutatingSubscribe = true
        val seed = toCardSeed(cur)
        val identity = MoviePilotRepository.normalizeCanonicalMediaIdentity(
            source = seed.source,
            mediaId = seed.mediaId,
            tmdbId = seed.tmdbId,
            doubanId = seed.doubanId,
            imdbId = seed.imdbId,
            tvdbId = seed.tvdbId,
        )
        val sNum = if (isTv) currentSeasonNum else null
        val epCnt = if (isTv) (episodes.size.takeIf { it > 0 } ?: cur.episodeCount ?: 0) else 0
        val (ok, msg, createdId) = repository.createOrUpdateSubscriptionFull(
            SubscribeItemDto(
                name = cur.seriesName.ifBlank { cur.title },
                year = cur.year,
                type = if (isTv) "电视剧" else "电影",
                season = sNum,
                totalEpisode = epCnt,
                mediaSource = identity?.first ?: "themoviedb",
                mediaId = identity?.second.orEmpty(),
            ),
        )
        isMutatingSubscribe = false
        if (ok) {
            if (isTv && sNum != null) {
                userSeasonOverrides[sNum] = true
                subscribedSeasons = subscribedSeasons + sNum
                if (createdId != null && createdId > 0) seasonSubscribeIds[sNum] = createdId
                feedback = "已订阅第 $sNum 季"
            } else {
                userMovieOverride = true
                subscribedMovie = true
                if (createdId != null && createdId > 0) movieSubscribeId = createdId
                feedback = "已添加到我的订阅"
            }
            feedbackIsError = false
        } else {
            feedbackIsError = true
            feedback = msg
        }
    }

    val externalLinks = remember(d, isTv) {
        if (d == null) {
            emptyList()
        } else {
            buildList {
                val mediaKindPath = if (isTv) "tv" else "movie"
                val traktKind = if (isTv) "show" else "movie"
                d.doubanId?.takeIf { it.isNotBlank() }?.let { dbId ->
                    add(ExternalLinkChipItem("豆瓣", "https://movie.douban.com/subject/$dbId/"))
                }
                d.imdbId?.takeIf { it.isNotBlank() }?.let { imdb ->
                    add(ExternalLinkChipItem("IMDb", "https://www.imdb.com/title/$imdb/"))
                }
                d.tmdbId?.takeIf { it.isNotBlank() }?.let { tmdb ->
                    add(ExternalLinkChipItem("TheMovieDb", "https://www.themoviedb.org/$mediaKindPath/$tmdb"))
                }
                when {
                    !d.imdbId.isNullOrBlank() ->
                        add(ExternalLinkChipItem("Trakt", "https://trakt.tv/search/imdb/${d.imdbId}?id_type=$traktKind"))
                    !d.tmdbId.isNullOrBlank() ->
                        add(ExternalLinkChipItem("Trakt", "https://trakt.tv/search/tmdb/${d.tmdbId}?id_type=$traktKind"))
                }
                d.tvdbId?.takeIf { it.isNotBlank() }?.let { tvdb ->
                    val tvdbKind = if (isTv) "series" else "movie"
                    add(ExternalLinkChipItem("TheTVDB", "https://thetvdb.com/dereferrer/$tvdbKind/$tvdb"))
                }
                d.playUrl?.takeIf { it.isNotBlank() }?.let { pUrl ->
                    add(ExternalLinkChipItem(d.server.ifBlank { "媒体服务器" }, pUrl))
                }
            }
        }
    }

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

    Box(modifier = Modifier.fillMaxSize()) {
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

            // 底层摄影感视差 Hero 背景
            if (progress < 0.99f) {
                val backdropHeight = heroHeight * 1.06f
                val parallaxY = -scrollUpPx.coerceAtMost(heroHeightPx) * 0.08f
                val maskShiftY = -scrollUpPx * 0.85f
                val visibility = (1f - eased * 0.96f).coerceIn(0f, 1f)
                val fadeBase = MaterialTheme.colorScheme.background

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
                            val hPx = size.height.coerceAtLeast(1f)
                            val shiftFraction = (maskShiftY / hPx).coerceIn(-0.95f, 0f)
                            val p1 = (0.56f + shiftFraction).coerceIn(0f, 1f)
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
                    val artCandidates = remember(d?.poster, d?.backdrop, d?.thumb, fallbackPoster, isPortraitPhone) {
                        if (isPortraitPhone) {
                            listOfNotNull(d?.poster, fallbackPoster, d?.backdrop, d?.thumb).filter { it.isNotBlank() }.distinct()
                        } else {
                            listOfNotNull(d?.backdrop, d?.thumb, d?.poster, fallbackPoster).filter { it.isNotBlank() }.distinct()
                        }
                    }
                    var artIdx by remember(artCandidates) { mutableIntStateOf(0) }
                    val resolvedArt = artCandidates.getOrNull(artIdx)
                    if (!resolvedArt.isNullOrBlank()) {
                        AsyncImage(
                            model = resolvedArt,
                            contentDescription = d?.title ?: fallbackTitle,
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
                                .background(Brush.verticalGradient(listOf(colors.accent.copy(alpha = 0.42f), Color(0xFF231C35)))),
                        )
                    }
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    0.0f to Color.Transparent,
                                    0.46f to Color.Transparent,
                                    0.68f to fadeBase.copy(alpha = if (colors.isDark) 0.40f else 0.44f),
                                    0.88f to fadeBase.copy(alpha = if (colors.isDark) 0.88f else 0.90f),
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
                    scope.launch { loadAll(clearOverrides = true) }
                },
                modifier = Modifier.fillMaxSize(),
            ) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 32.dp + bottomOverlayInset),
                    verticalArrangement = Arrangement.spacedBy(if (isCompactLandscape) 14.dp else 20.dp),
                ) {
                    // 1. Hero 标题、服务器徽标与规格胶囊
                    item(key = "ms_hero") {
                        val displayTitle = d?.title?.ifBlank { fallbackTitle } ?: fallbackTitle
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
                                if (activeServerName.isNotBlank()) {
                                    Row(
                                        modifier = Modifier
                                            .clip(CircleShape)
                                            .background(Color.Black.copy(alpha = if (colors.isDark) 0.50f else 0.12f))
                                            .border(0.6.dp, Color.White.copy(alpha = 0.22f), CircleShape)
                                            .padding(horizontal = 10.dp, vertical = 4.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        NativeEntityLogo(
                                            kind = "mediaserver",
                                            value = (d?.serverType?.ifBlank { activeServerName }) ?: activeServerName,
                                            size = 16.dp,
                                            cornerRadius = 4.dp,
                                        )
                                        Text(
                                            text = activeServerName,
                                            color = if (colors.isDark) Color.White else colors.textPrimary,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                    }
                                }

                                var logoReady by remember(d?.logoUrl) { mutableStateOf(false) }
                                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                                    if (!logoReady) {
                                        Text(
                                            text = displayTitle.ifBlank { "媒体库详情" },
                                            color = if (colors.isDark) Color.White else colors.textPrimary,
                                            fontSize = if (isCompactLandscape) 22.sp else 28.sp,
                                            fontWeight = FontWeight.ExtraBold,
                                            textAlign = TextAlign.Center,
                                            maxLines = if (isCompactLandscape) 1 else 2,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    if (!d?.logoUrl.isNullOrBlank()) {
                                        AsyncImage(
                                            model = d!!.logoUrl,
                                            contentDescription = displayTitle,
                                            contentScale = ContentScale.Fit,
                                            onSuccess = { logoReady = true },
                                            modifier = Modifier
                                                .fillMaxWidth(if (isCompactLandscape) 0.54f else 0.72f)
                                                .height(if (isCompactLandscape) 46.dp else 72.dp),
                                        )
                                    }
                                }

                                if (!d?.tagline.isNullOrBlank() && !isCompactLandscape) {
                                    Text(
                                        text = d!!.tagline,
                                        color = if (colors.isDark) Color.White.copy(alpha = 0.78f) else colors.textSecondary,
                                        fontSize = 13.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        textAlign = TextAlign.Center,
                                    )
                                }

                                val resolutionTag = remember(primaryVideoTrack) {
                                    val wPx = primaryVideoTrack?.width ?: 0
                                    val hPx = primaryVideoTrack?.height ?: 0
                                    when {
                                        wPx >= 3800 || hPx >= 2100 -> "4K"
                                        wPx >= 1900 || hPx >= 1000 -> "1080P"
                                        wPx >= 1200 || hPx >= 700 -> "720P"
                                        else -> null
                                    }
                                }
                                FlowRow(
                                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    if ((d?.rating ?: 0.0) > 0.0) {
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                                            modifier = Modifier.padding(end = 2.dp),
                                        ) {
                                            Icon(Icons.Rounded.Star, contentDescription = null, tint = Color(0xFFFFC845), modifier = Modifier.size(16.dp))
                                            Text(String.format("%.1f", d!!.rating), color = Color(0xFFFFC845), fontWeight = FontWeight.Bold, fontSize = 14.sp)
                                        }
                                    }
                                    if (!d?.year.isNullOrBlank()) {
                                        HeroMetaChip(d!!.year)
                                    }
                                    formatDurationMinutes(d?.durationMs ?: selectedSource?.durationMs)?.let { dur ->
                                        HeroMetaChip(dur)
                                    }
                                    if (!d?.officialRating.isNullOrBlank()) {
                                        HeroMetaChip(d!!.officialRating)
                                    }
                                    if (!selectedSource?.container.isNullOrBlank()) {
                                        HeroMetaChip(selectedSource!!.container.uppercase())
                                    }
                                    if (resolutionTag != null) {
                                        HeroMetaChip(resolutionTag)
                                    }
                                    if (!primaryVideoTrack?.videoRange.isNullOrBlank()) {
                                        HeroMetaChip(primaryVideoTrack!!.videoRange!!)
                                    }
                                }

                                if (!d?.genres.isNullOrEmpty() && !isCompactLandscape) {
                                    Text(
                                        text = d!!.genres.take(5).joinToString(" · "),
                                        color = if (colors.isDark) Color.White.copy(alpha = 0.80f) else colors.textSecondary,
                                        fontSize = 12.5.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }

                    if (isLoading && d == null) {
                        item(key = "ms_loading") {
                            Box(modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(color = colors.accent)
                            }
                        }
                    } else if (d != null) {
                        // 2. 主操作按钮行（立即播放 / 继续播放 + 权威订阅切换 + 多版本切换胶囊）
                        item(key = "ms_actions") {
                            val btnHeight = if (isCompactLandscape) 44.dp else 50.dp
                            val targetPlayEp = if (episodes.isNotEmpty()) {
                                episodes.firstOrNull { it.itemId == selectedEpisodeId }
                                    ?: episodes.firstOrNull { !it.played }
                                    ?: episodes.first()
                            } else {
                                null
                            }
                            val playTargetId = targetPlayEp?.itemId ?: d.itemId
                            val resumeMs = targetPlayEp?.resumePositionMs?.takeIf { it > 0L } ?: d.resumePositionMs
                            val playLabel = when {
                                resumeMs > 0L -> "继续播放 · ${formatResumeClock(resumeMs)}"
                                targetPlayEp != null && targetPlayEp.episodeNumber != null ->
                                    "播放 E%02d".format(targetPlayEp.episodeNumber)
                                else -> "立即播放"
                            }

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
                                            startStreamPlayback(
                                                targetItemId = playTargetId,
                                                titleFallback = targetPlayEp?.title?.ifBlank { d.title } ?: d.title,
                                                subtitleFallback = listOfNotNull(
                                                    activeServerName.ifBlank { null },
                                                    d.year.ifBlank { null },
                                                ).joinToString(" · "),
                                                artwork = d.poster ?: fallbackPoster,
                                                sourceId = if (targetPlayEp == null) selectedSource?.id?.ifBlank { null } else null,
                                            )
                                        },
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = if (colors.isDark) Color.White else colors.accent,
                                            contentColor = if (colors.isDark) Color(0xFF14111D) else colors.primaryButtonFg,
                                        ),
                                        shape = CircleShape,
                                        modifier = Modifier.weight(1.15f).height(btnHeight),
                                    ) {
                                        Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(20.dp))
                                        Spacer(Modifier.width(6.dp))
                                        Text(
                                            text = playLabel,
                                            fontSize = if (isCompactLandscape) 14.sp else 15.sp,
                                            fontWeight = FontWeight.Bold,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }

                                    Button(
                                        onClick = {
                                            if (isCurrentSubscribed) {
                                                showUnsubscribeDialog = true
                                            } else {
                                                scope.launch { handleSubscribeCurrent() }
                                            }
                                        },
                                        enabled = !isMutatingSubscribe,
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = if (isCurrentSubscribed) subscribedEmeraldBg else colors.surfaceContainerHigh,
                                            contentColor = if (isCurrentSubscribed) Color.White else colors.textPrimary,
                                        ),
                                        shape = CircleShape,
                                        modifier = Modifier
                                            .weight(1f)
                                            .height(btnHeight)
                                            .then(
                                                if (isCurrentSubscribed) {
                                                    Modifier.border(0.8.dp, subscribedEmeraldBorder, CircleShape)
                                                } else {
                                                    Modifier.border(0.8.dp, colors.chipBorder, CircleShape)
                                                },
                                            ),
                                    ) {
                                        Icon(
                                            if (isCurrentSubscribed) Icons.Rounded.CheckCircle else Icons.Outlined.BookmarkBorder,
                                            contentDescription = null,
                                            modifier = Modifier.size(18.dp),
                                        )
                                        Spacer(Modifier.width(6.dp))
                                        Text(
                                            text = when {
                                                isCurrentSubscribed && isTv && effectiveSubscribedSeasons.size > 1 ->
                                                    "已订阅 ${effectiveSubscribedSeasons.size} 季"
                                                isCurrentSubscribed && isTv ->
                                                    "第 ${if (currentSeasonNum in effectiveSubscribedSeasons) currentSeasonNum else (effectiveSubscribedSeasons.firstOrNull() ?: currentSeasonNum)} 季已订阅"
                                                isCurrentSubscribed -> "已订阅"
                                                isTv -> "订阅第 $currentSeasonNum 季"
                                                else -> "添加订阅"
                                            },
                                            fontSize = if (isCompactLandscape) 13.5.sp else 14.5.sp,
                                            fontWeight = FontWeight.Bold,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                }

                                if (effectiveSources.size > 1) {
                                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        itemsIndexed(effectiveSources) { idx, src ->
                                            val vTrack = src.streams.firstOrNull { it.type.equals("video", true) }
                                            val label = buildList {
                                                add(src.name.ifBlank { vTrack?.displayTitle ?: "版本 ${idx + 1}" })
                                                formatBytesSize(src.size)?.let { add(it) }
                                            }.joinToString(" · ")
                                            NativeAdaptivePill(
                                                title = label,
                                                selected = selectedSourceIndex == idx,
                                                onClick = { selectedSourceIndex = idx },
                                            )
                                        }
                                    }
                                }

                                feedback?.let { msg ->
                                    Text(
                                        text = msg,
                                        color = if (feedbackIsError) colors.warning else colors.success,
                                        fontSize = 13.sp,
                                    )
                                }
                            }
                        }

                        // 3. 剧情简介卡
                        if (d.overview.isNotBlank() || d.studios.isNotEmpty()) {
                            item(key = "ms_overview") {
                                CinematicPanel(
                                    padding = 16.dp,
                                    showsShadow = false,
                                    modifier = Modifier
                                        .padding(horizontal = margin)
                                        .clickable { expandOverview = !expandOverview },
                                ) {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text("剧情简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                        if (d.overview.isNotBlank()) {
                                            Text(
                                                text = d.overview,
                                                color = colors.textSecondary,
                                                fontSize = 14.sp,
                                                lineHeight = 22.sp,
                                                maxLines = if (expandOverview) Int.MAX_VALUE else 4,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                            if (d.overview.length > 90) {
                                                Text(
                                                    text = if (expandOverview) "收起" else "展开全部",
                                                    color = colors.textMuted,
                                                    fontSize = 12.sp,
                                                    fontWeight = FontWeight.Medium,
                                                )
                                            }
                                        }
                                        if (d.studios.isNotEmpty()) {
                                            Text(
                                                text = "出品：${d.studios.take(3).joinToString(" / ")}",
                                                color = colors.textMuted,
                                                fontSize = 12.sp,
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        // 4. 剧集列表（分季胶囊 + 16:9 横版剧照横向滚动卡片，图2顶部区域）
                        if (seasons.isNotEmpty() || episodes.isNotEmpty()) {
                            item(key = "ms_episodes") {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    NativeSectionHeader(
                                        title = "剧集列表",
                                        subtitle = if (episodes.isNotEmpty()) "共 ${episodes.size} 集" else null,
                                        modifier = Modifier.padding(horizontal = margin),
                                    )
                                    if (seasons.size > 1) {
                                        LazyRow(
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            items(seasons, key = { "sea_${it.itemId}_${it.seasonNumber}" }) { sea ->
                                                val sNum = sea.seasonNumber ?: 1
                                                val isPicked = (selectedSeasonId != null && sea.itemId == selectedSeasonId) ||
                                                    (selectedSeasonId == null && selectedSeasonNum == sNum)
                                                val seaTitle = buildString {
                                                    append(sea.title.ifBlank { "第 $sNum 季" })
                                                    sea.childCount?.takeIf { it > 0 }?.let { append(" ($it)") }
                                                }
                                                NativeAdaptivePill(
                                                    title = seaTitle,
                                                    selected = isPicked,
                                                    onClick = {
                                                        if (!isPicked) {
                                                            selectedSeasonId = sea.itemId
                                                            selectedSeasonNum = sNum
                                                            scope.launch {
                                                                val seriesRootId = if (d.itemType.equals("Season", true)) {
                                                                    d.seriesId ?: d.parentId ?: d.itemId
                                                                } else {
                                                                    d.itemId
                                                                }
                                                                val newEps = repository.fetchMediaServerSeasonEpisodes(
                                                                    seriesId = seriesRootId,
                                                                    server = activeServerName,
                                                                    seasonId = sea.itemId,
                                                                    seasonNumber = sNum,
                                                                )
                                                                episodes = newEps
                                                                val firstEp = newEps.firstOrNull { !it.played } ?: newEps.firstOrNull()
                                                                selectedEpisodeId = firstEp?.itemId
                                                                loadEpisodeStreamPreviewIfNeeded(firstEp?.itemId, activeServerName, d)
                                                            }
                                                        }
                                                    },
                                                )
                                            }
                                        }
                                    }

                                    if (episodes.isNotEmpty()) {
                                        LazyRow(
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            itemsIndexed(episodes, key = { idx, ep -> "ep_${ep.itemId}_$idx" }) { idx, ep ->
                                                val epNum = ep.episodeNumber ?: (idx + 1)
                                                // Emby / Jellyfin / Plex 将 16:9 单集剧照存放在 `ep.thumb`，严格遵循优先级：
                                                val stillImage = ep.thumb ?: ep.backdrop ?: d.backdrop ?: ep.poster ?: d.poster
                                                val isSelectedEp = ep.itemId == selectedEpisodeId

                                                Column(
                                                    modifier = Modifier
                                                        .width(228.dp)
                                                        .clickable {
                                                            selectedEpisodeId = ep.itemId
                                                            scope.launch {
                                                                loadEpisodeStreamPreviewIfNeeded(ep.itemId, activeServerName, d)
                                                            }
                                                            startStreamPlayback(
                                                                targetItemId = ep.itemId,
                                                                titleFallback = "${d.seriesName.ifBlank { d.title }} E%02d · ${ep.title}".format(epNum),
                                                                subtitleFallback = activeServerName,
                                                                artwork = stillImage,
                                                            )
                                                        },
                                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                                ) {
                                                    Box(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .aspectRatio(16f / 9f)
                                                            .clip(RoundedCornerShape(14.dp))
                                                            .background(colors.surfaceContainerHigh)
                                                            .border(
                                                                width = if (isSelectedEp) 1.2.dp else 0.6.dp,
                                                                color = if (isSelectedEp) colors.accent else Color.White.copy(alpha = 0.14f),
                                                                shape = RoundedCornerShape(14.dp),
                                                            ),
                                                    ) {
                                                        if (!stillImage.isNullOrBlank()) {
                                                            AsyncImage(
                                                                model = stillImage,
                                                                contentDescription = ep.title,
                                                                contentScale = ContentScale.Crop,
                                                                modifier = Modifier.fillMaxSize(),
                                                            )
                                                        }
                                                        // 集号角标
                                                        Box(
                                                            modifier = Modifier
                                                                .align(Alignment.TopStart)
                                                                .padding(8.dp)
                                                                .clip(CircleShape)
                                                                .background(Color.Black.copy(alpha = 0.64f))
                                                                .padding(horizontal = 8.dp, vertical = 2.5.dp),
                                                        ) {
                                                            Text(
                                                                text = "E%02d".format(epNum),
                                                                color = Color.White,
                                                                fontSize = 11.sp,
                                                                fontWeight = FontWeight.Bold,
                                                            )
                                                        }
                                                        // 已观看对勾
                                                        if (ep.played) {
                                                            Box(
                                                                modifier = Modifier
                                                                    .align(Alignment.TopEnd)
                                                                    .padding(8.dp)
                                                                    .size(22.dp)
                                                                    .clip(CircleShape)
                                                                    .background(Color(0xFF1F9D55)),
                                                                contentAlignment = Alignment.Center,
                                                            ) {
                                                                Icon(Icons.Rounded.Check, contentDescription = "已观看", tint = Color.White, modifier = Modifier.size(13.dp))
                                                            }
                                                        }
                                                        // 时长胶囊
                                                        formatDurationMinutes(ep.durationMs)?.let { epDur ->
                                                            Box(
                                                                modifier = Modifier
                                                                    .align(Alignment.BottomEnd)
                                                                    .padding(start = 8.dp, end = 8.dp, bottom = if (ep.playedPercentage > 0.0) 11.dp else 8.dp)
                                                                    .clip(RoundedCornerShape(6.dp))
                                                                    .background(Color.Black.copy(alpha = 0.66f))
                                                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                                                            ) {
                                                                Text(epDur, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Medium)
                                                            }
                                                        }
                                                        // 底部观看进度条
                                                        if (ep.playedPercentage > 0.0) {
                                                            Box(
                                                                modifier = Modifier
                                                                    .align(Alignment.BottomCenter)
                                                                    .fillMaxWidth()
                                                                    .height(3.5.dp)
                                                                    .background(Color.White.copy(alpha = 0.25f)),
                                                            ) {
                                                                Box(
                                                                    modifier = Modifier
                                                                        .fillMaxWidth((ep.playedPercentage / 100.0).toFloat().coerceIn(0.05f, 1f))
                                                                        .height(3.5.dp)
                                                                        .background(colors.accent),
                                                                )
                                                            }
                                                        }
                                                    }

                                                    Text(
                                                        text = "$epNum. ${ep.title.ifBlank { "第 $epNum 集" }}",
                                                        color = colors.textPrimary,
                                                        fontSize = 13.5.sp,
                                                        fontWeight = FontWeight.Bold,
                                                        maxLines = 1,
                                                        overflow = TextOverflow.Ellipsis,
                                                    )
                                                    if (ep.overview.isNotBlank()) {
                                                        Text(
                                                            text = ep.overview,
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

                        // 5. 演职员横栏
                        if (d.people.isNotEmpty()) {
                            item(key = "ms_people") {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    NativeSectionHeader(title = "演职员", modifier = Modifier.padding(horizontal = margin))
                                    LazyRow(
                                        contentPadding = PaddingValues(horizontal = margin),
                                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                                    ) {
                                        items(d.people.take(20), key = { "${it.id}_${it.name}_${it.role}" }) { p ->
                                            Column(
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                                modifier = Modifier
                                                    .width(80.dp)
                                                    .clickable {
                                                        if (p.id.toIntOrNull() != null) {
                                                            onOpenPerson(
                                                                MediaPersonDto(
                                                                    id = p.id,
                                                                    name = p.name,
                                                                    character = p.role,
                                                                    department = p.type,
                                                                    profilePath = p.image,
                                                                    source = "themoviedb",
                                                                ),
                                                            )
                                                        } else {
                                                            scope.launch {
                                                                val matched = repository.searchMedia(p.name, "person", 1).firstOrNull()
                                                                if (matched != null) {
                                                                    onOpenPerson(
                                                                        MediaPersonDto(
                                                                            id = matched.mediaId ?: matched.tmdbId?.toString().orEmpty(),
                                                                            name = matched.title.ifBlank { p.name },
                                                                            character = p.role,
                                                                            profilePath = matched.posterPath ?: p.image,
                                                                            source = matched.source,
                                                                        ),
                                                                    )
                                                                }
                                                            }
                                                        }
                                                    },
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .size(70.dp)
                                                        .clip(CircleShape)
                                                        .background(colors.chipFill)
                                                        .border(0.8.dp, Color.White.copy(alpha = 0.16f), CircleShape),
                                                    contentAlignment = Alignment.Center,
                                                ) {
                                                    Icon(Icons.Rounded.Person, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(28.dp))
                                                    if (!p.image.isNullOrBlank()) {
                                                        AsyncImage(
                                                            model = p.image,
                                                            contentDescription = p.name,
                                                            contentScale = ContentScale.Crop,
                                                            modifier = Modifier.fillMaxSize(),
                                                        )
                                                    }
                                                }
                                                Spacer(Modifier.height(6.dp))
                                                Text(p.name, color = colors.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                if (p.role.isNotBlank()) {
                                                    Text(p.role, color = colors.textMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 6. 类似作品（1:1 对齐图2：2:3 竖版圆角海报 + 右下角深色半透明评分角标 + 1 行粗体标题 + 1 行年份）
                        if (similarItems.isNotEmpty()) {
                            item(key = "ms_similar") {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    NativeSectionHeader(title = "类似作品", modifier = Modifier.padding(horizontal = margin))
                                    LazyRow(
                                        contentPadding = PaddingValues(horizontal = margin),
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    ) {
                                        items(similarItems, key = { "sim_${it.resolvedId}_${it.title}" }) { sim ->
                                            Column(
                                                modifier = Modifier
                                                    .width(118.dp)
                                                    .clickable {
                                                        if (!sim.serverItemId.isNullOrBlank() && !sim.serverName.isNullOrBlank()) {
                                                            onOpenServerDetail(sim.serverItemId!!, sim.serverName!!, sim.title, sim.posterPath)
                                                        } else {
                                                            onOpenMedia(sim)
                                                        }
                                                    },
                                                verticalArrangement = Arrangement.spacedBy(5.dp),
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxWidth()
                                                        .aspectRatio(2f / 3f)
                                                        .clip(RoundedCornerShape(13.dp))
                                                        .background(colors.surfaceContainerHigh)
                                                        .border(0.6.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(13.dp)),
                                                ) {
                                                    if (!sim.posterPath.isNullOrBlank()) {
                                                        AsyncImage(
                                                            model = sim.posterPath,
                                                            contentDescription = sim.title,
                                                            contentScale = ContentScale.Crop,
                                                            modifier = Modifier.fillMaxSize(),
                                                        )
                                                    }
                                                    if (sim.voteAverage > 0.0) {
                                                        Box(
                                                            modifier = Modifier
                                                                .align(Alignment.BottomEnd)
                                                                .padding(6.dp)
                                                                .clip(RoundedCornerShape(6.dp))
                                                                .background(Color.Black.copy(alpha = 0.72f))
                                                                .padding(horizontal = 6.dp, vertical = 2.dp),
                                                        ) {
                                                            Text(
                                                                text = String.format(Locale.US, "%.1f", sim.voteAverage),
                                                                color = Color.White,
                                                                fontSize = 11.5.sp,
                                                                fontWeight = FontWeight.Bold,
                                                            )
                                                        }
                                                    }
                                                }
                                                Text(
                                                    text = sim.title,
                                                    color = colors.textPrimary,
                                                    fontSize = 13.sp,
                                                    fontWeight = FontWeight.Bold,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                )
                                                if (sim.year.isNotBlank()) {
                                                    Text(
                                                        text = sim.year,
                                                        color = colors.textMuted,
                                                        fontSize = 11.5.sp,
                                                        maxLines = 1,
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 7. 链接（1:1 对齐图2：带前缀链接图标的深色描边胶囊：豆瓣 / IMDb / TheMovieDb / Trakt 等）
                        if (externalLinks.isNotEmpty()) {
                            item(key = "ms_links") {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    NativeSectionHeader(title = "链接", modifier = Modifier.padding(horizontal = margin))
                                    LazyRow(
                                        contentPadding = PaddingValues(horizontal = margin),
                                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        items(externalLinks, key = { it.title + it.url }) { linkItem ->
                                            Row(
                                                modifier = Modifier
                                                    .clip(CircleShape)
                                                    .background(
                                                        if (colors.isDark) Color.White.copy(alpha = 0.05f) else colors.surfaceContainerLow,
                                                    )
                                                    .border(
                                                        width = 0.85.dp,
                                                        color = if (colors.isDark) Color.White.copy(alpha = 0.16f) else colors.chipBorder,
                                                        shape = CircleShape,
                                                    )
                                                    .clickable {
                                                        runCatching {
                                                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(linkItem.url)))
                                                        }
                                                    }
                                                    .padding(horizontal = 15.dp, vertical = 8.5.dp),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(7.dp),
                                            ) {
                                                Icon(
                                                    Icons.Rounded.Link,
                                                    contentDescription = null,
                                                    tint = colors.textSecondary,
                                                    modifier = Modifier.size(16.dp),
                                                )
                                                Text(
                                                    text = linkItem.title,
                                                    color = colors.textPrimary,
                                                    fontSize = 13.5.sp,
                                                    fontWeight = FontWeight.Medium,
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 8. 媒体信息（1:1 对齐图2：顶对齐横向滚动深色描边规格卡：视频 / 音频 / 字幕）
                        val activeStreams = selectedSource?.streams.orEmpty()
                        if (activeStreams.isNotEmpty()) {
                            item(key = "ms_media_info") {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    NativeSectionHeader(title = "媒体信息", modifier = Modifier.padding(horizontal = margin))
                                    LazyRow(
                                        contentPadding = PaddingValues(horizontal = margin),
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        verticalAlignment = Alignment.Top,
                                    ) {
                                        itemsIndexed(activeStreams, key = { idx, tr -> "tr_${selectedSource?.id}_${tr.type}_${tr.index ?: idx}" }) { _, track ->
                                            val videoCount = activeStreams.count { it.type.equals("video", true) }
                                            MediaStreamInfoCard(
                                                track = track,
                                                sourceBitrate = if (videoCount == 1) selectedSource?.bitrate else null,
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

        // 顶部状态栏渐进模糊保护
        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = eased,
            extraHeight = 56.dp,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )

        // 左上角悬浮返回圆钮
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

        // 右上角搜索 + 更多操作胶囊（1:1 对应图2右上角胶囊）
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .windowInsetsPadding(
                    WindowInsets.statusBars
                        .union(WindowInsets.displayCutout)
                        .only(WindowInsetsSides.Top + WindowInsetsSides.End),
                )
                .padding(end = 16.dp, top = if (isCompactLandscape) 6.dp else 8.dp),
        ) {
            CinematicGlassCapsule {
                IconButton(
                    onClick = {
                        val q = d?.seriesName?.ifBlank { d.title } ?: fallbackTitle
                        onSearchResource(q)
                    },
                    modifier = Modifier.size(if (isCompactLandscape) 36.dp else 40.dp),
                ) {
                    Icon(Icons.Rounded.Search, contentDescription = "搜索资源", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                }
                IconButton(
                    onClick = { showTopMoreMenu = true },
                    modifier = Modifier.size(if (isCompactLandscape) 36.dp else 40.dp),
                ) {
                    Icon(Icons.Rounded.MoreHoriz, contentDescription = "更多操作", tint = colors.textPrimary, modifier = Modifier.size(20.dp))
                }
            }
            DropdownMenu(expanded = showTopMoreMenu, onDismissRequest = { showTopMoreMenu = false }) {
                if (d != null && (!d.tmdbId.isNullOrBlank() || !d.doubanId.isNullOrBlank())) {
                    DropdownMenuItem(
                        text = { Text("查看影视元数据页") },
                        onClick = {
                            showTopMoreMenu = false
                            onOpenMedia(toCardSeed(d).copy(serverItemId = null, serverName = null))
                        },
                    )
                }
                if (!d?.playUrl.isNullOrBlank()) {
                    DropdownMenuItem(
                        text = { Text("在浏览器打开播放页") },
                        onClick = {
                            showTopMoreMenu = false
                            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(d!!.playUrl))) }
                        },
                    )
                }
                DropdownMenuItem(
                    text = { Text("刷新详情") },
                    onClick = {
                        showTopMoreMenu = false
                        isRefreshing = true
                        scope.launch { loadAll(clearOverrides = true) }
                    },
                )
            }
        }
    }

    // 取消订阅或查看关联订阅文件详情弹窗
    if (showUnsubscribeDialog && d != null) {
        val targetSeason = if (isTv) {
            if (currentSeasonNum in effectiveSubscribedSeasons) currentSeasonNum else effectiveSubscribedSeasons.minOrNull()
        } else {
            null
        }
        val knownSubId = if (isTv && targetSeason != null) {
            seasonSubscribeIds[targetSeason] ?: libraryStatus.seasonSubscribeIds[targetSeason]
        } else {
            movieSubscribeId ?: libraryStatus.subscribeId
        }
        AlertDialog(
            onDismissRequest = { showUnsubscribeDialog = false },
            title = {
                Text(
                    if (isTv && targetSeason != null) "第 $targetSeason 季已订阅" else "《${d.seriesName.ifBlank { d.title }}》已订阅",
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        if (knownSubId != null && knownSubId > 0) {
                            "可查看当前订阅关联的下载任务与媒体库文件详情，或取消该订阅。"
                        } else {
                            "确认取消该订阅吗？已入库的媒体文件不会受任何影响。"
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
                TextButton(onClick = { showUnsubscribeDialog = false }) { Text("保留订阅") }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showUnsubscribeDialog = false
                        scope.launch {
                            isMutatingSubscribe = true
                            val (ok, msg) = repository.unsubscribeMediaWithMessage(toCardSeed(d), season = if (isTv) targetSeason else null)
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

    if (activeSubscribeFilesId != null && d != null) {
        val subId = activeSubscribeFilesId!!
        SubscribeFilesSheet(
            subscribeId = subId,
            seedSubscribe = SubscribeItemDto(
                id = subId,
                name = d.seriesName.ifBlank { d.title },
                year = d.year,
                type = if (isTv) "电视剧" else "电影",
                season = if (isTv) currentSeasonNum else null,
                poster = d.poster ?: fallbackPoster,
                backdrop = d.backdrop,
                vote = d.rating,
            ),
            repository = repository,
            onDismiss = { activeSubscribeFilesId = null },
            onPlayMedia = onPlayMedia,
            onOpenServerItem = { targetId, targetSrv, title ->
                activeSubscribeFilesId = null
                if (targetId != itemId || targetSrv != activeServerName) {
                    onOpenServerDetail(targetId, targetSrv, title, d.poster)
                }
            },
        )
    }
}

@Composable
private fun HeroMetaChip(text: String) {
    val colors = LocalMoviePilotColors.current
    Box(
        modifier = Modifier
            .clip(CircleShape)
            .background(colors.chipFill.copy(alpha = if (colors.isDark) 0.78f else 0.90f))
            .border(0.6.dp, colors.chipBorder, CircleShape)
            .padding(horizontal = 10.dp, vertical = 3.5.dp),
    ) {
        Text(
            text = text,
            color = colors.textPrimary.copy(alpha = 0.92f),
            fontSize = 11.5.sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/**
 * 单个视频 / 音频 / 字幕轨道技术规格卡（1:1 对齐图2 `媒体信息` 卡片视觉与字段排布）。
 */
@Composable
private fun MediaStreamInfoCard(
    track: MediaServerStreamTrackDto,
    sourceBitrate: Long? = null,
) {
    val colors = LocalMoviePilotColors.current
    val kind = track.type.lowercase()
    val (headerIcon, headerTitle, showDefaultTick) = when (kind) {
        "video" -> Triple<ImageVector, String, Boolean>(Icons.Rounded.Videocam, "视频", false)
        "audio" -> Triple<ImageVector, String, Boolean>(Icons.AutoMirrored.Rounded.VolumeUp, "音频", track.isDefault)
        "subtitle" -> Triple<ImageVector, String, Boolean>(Icons.Rounded.Subtitles, "字幕", track.isDefault)
        else -> Triple<ImageVector, String, Boolean>(Icons.Rounded.Videocam, track.type.ifBlank { "轨道" }, track.isDefault)
    }

    val rows: List<Pair<String, String>> = remember(track, sourceBitrate) {
        buildList {
            fun putIfPresent(label: String, value: String?) {
                val clean = value?.trim()
                if (!clean.isNullOrEmpty() && !clean.equals("null", ignoreCase = true)) {
                    add(label to clean)
                }
            }
            when (kind) {
                "video" -> {
                    val autoTitle = track.displayTitle ?: listOfNotNull(
                        track.height?.takeIf { it > 0 }?.let { "${it}p" },
                        track.codec?.uppercase(),
                    ).joinToString(" ").ifBlank { null }
                    val fallbackBitrate = track.formattedBitrate ?: sourceBitrate?.takeIf { it > 0L }?.let {
                        String.format(Locale.US, "%.1fmbps", it / 1_000_000.0)
                    }
                    putIfPresent("标题", autoTitle)
                    putIfPresent("内嵌标题", track.title)
                    putIfPresent("编码", track.codec)
                    putIfPresent("分辨率", track.formattedResolution)
                    putIfPresent("帧率", track.frameRate)
                    putIfPresent("比特率", fallbackBitrate)
                    putIfPresent("动态范围", track.videoRange)
                    putIfPresent("配置", track.profile)
                    putIfPresent("等级", track.level)
                    putIfPresent("长宽比", track.inferredAspectRatio)
                    track.isInterlaced?.let { putIfPresent("交错", if (it) "是" else "否") }
                    putIfPresent("基色", track.colorPrimaries)
                    putIfPresent("色域", track.colorSpace)
                    track.bitDepth?.takeIf { it > 0 }?.let { putIfPresent("位深", it.toString()) }
                }

                "audio" -> {
                    val autoTitle = track.displayTitle ?: listOfNotNull(
                        track.language,
                        track.codec?.uppercase(),
                    ).joinToString(" ").ifBlank { null }
                    putIfPresent("标题", autoTitle)
                    putIfPresent("内嵌标题", track.title)
                    putIfPresent("语言", track.language)
                    putIfPresent("布局", track.channelLayout)
                    track.channels?.takeIf { it > 0 }?.let { putIfPresent("声道", it.toString()) }
                    putIfPresent("编码", track.codec)
                    putIfPresent("比特率", track.formattedBitrate)
                    track.sampleRate?.takeIf { it > 0 }?.let { putIfPresent("采样率", "${it}Hz") }
                    putIfPresent("外部", if (track.isExternal) "是" else "否")
                    putIfPresent("默认", if (track.isDefault) "是" else "否")
                }

                "subtitle" -> {
                    val autoTitle = track.displayTitle ?: track.title ?: track.language
                    putIfPresent("标题", autoTitle)
                    putIfPresent("内嵌标题", track.title)
                    putIfPresent("语言", track.language)
                    putIfPresent("编码", track.codec)
                    putIfPresent("强制", if (track.isForced) "是" else "否")
                    putIfPresent("外部", if (track.isExternal) "是" else "否")
                    putIfPresent("默认", if (track.isDefault) "是" else "否")
                }

                else -> {
                    putIfPresent("标题", track.displayTitle ?: track.title)
                    putIfPresent("编码", track.codec)
                    putIfPresent("语言", track.language)
                }
            }
        }
    }

    val cardShape = RoundedCornerShape(18.dp)
    val cardBg = if (colors.isDark) Color.White.copy(alpha = 0.045f) else colors.surfaceContainerLow
    val cardBorder = if (colors.isDark) Color.White.copy(alpha = 0.13f) else colors.chipBorder

    Column(
        modifier = Modifier
            .width(236.dp)
            .clip(cardShape)
            .background(cardBg, cardShape)
            .border(0.85.dp, cardBorder, cardShape)
            .padding(horizontal = 16.dp, vertical = 15.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = headerIcon,
                contentDescription = null,
                tint = colors.textPrimary,
                modifier = Modifier.size(19.dp),
            )
            Text(
                text = headerTitle,
                color = colors.textPrimary,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.Bold,
            )
            if (showDefaultTick) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = "默认轨道",
                    tint = colors.textPrimary,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        Spacer(Modifier.height(1.dp))

        rows.forEach { (label, value) ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = label,
                    color = colors.textMuted,
                    fontSize = 12.5.sp,
                    maxLines = 1,
                )
                Text(
                    text = value,
                    color = colors.textSecondary,
                    fontSize = 12.5.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
