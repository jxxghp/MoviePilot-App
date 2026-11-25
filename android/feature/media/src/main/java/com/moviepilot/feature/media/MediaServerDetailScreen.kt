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
import androidx.compose.material.icons.automirrored.rounded.OpenInNew
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircle
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Subtitles
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import com.moviepilot.designsystem.NativeEpisodeShelfSkeleton
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeMediaDetailSkeleton
import com.moviepilot.designsystem.NativePosterShelfSkeleton
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import com.moviepilot.designsystem.PlaybackPreferencesStore
import com.moviepilot.designsystem.ProvideSkeletonShimmer
import com.moviepilot.feature.subscribe.SubscribeFilesSheet
import com.moviepilot.media.ChineseSubtitleMatcher
import com.moviepilot.media.ExternalPlayerLauncher
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.QueueTrackSpec
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
    var previewedEpisodeId by remember(screenKey) { mutableStateOf<String?>(null) }
    var episodeFallbackSources by remember(screenKey) { mutableStateOf<List<MediaServerSourceDto>>(emptyList()) }
    var selectedSourceIndex by remember(screenKey) { mutableIntStateOf(0) }
    var selectedPrePlayAudioOrdinal by remember(screenKey) { mutableIntStateOf(0) }
    var selectedPrePlaySubtitleIdx by remember(screenKey) { mutableIntStateOf(0) }
    var showVersionPickerSheet by remember { mutableStateOf(false) }
    var showPrePlayAudioSheet by remember { mutableStateOf(false) }
    var showPrePlaySubtitleSheet by remember { mutableStateOf(false) }
    var similarItems by remember(screenKey) { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    val playbackPrefs = remember(context) { PlaybackPreferencesStore(context) }
    val episodesRowState = rememberLazyListState()

    var expandOverview by remember(screenKey) { mutableStateOf(false) }
    var isLoading by remember(screenKey) { mutableStateOf(true) }
    var isLoadingEpisodes by remember(screenKey) { mutableStateOf(false) }
    var isLoadingSimilar by remember(screenKey) { mutableStateOf(false) }
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
            previewedEpisodeId = epItemId
            episodeFallbackSources = epDetail.mediaSources
            selectedSourceIndex = 0
        }
    }

    suspend fun loadAll(clearOverrides: Boolean = false) {
        if (clearOverrides) {
            userMovieOverride = null
            userSeasonOverrides.clear()
        }
        if (detail == null) {
            isLoading = true
        }
        val fetched = repository.fetchMediaServerItemDetail(itemId, server.ifBlank { null })
        if (fetched == null) {
            isLoading = false
            isLoadingEpisodes = false
            isLoadingSimilar = false
            isRefreshing = false
            return
        }

        val activeSrv = fetched.server.ifBlank { server }
        val isMusicAlbumItem = fetched.itemType.equals("MusicAlbum", ignoreCase = true) ||
            fetched.mediaType.equals("MusicAlbum", ignoreCase = true)
        val isEpisodeItem = fetched.itemType.equals("Episode", ignoreCase = true)
        val isSeries = !isMusicAlbumItem && (fetched.itemType.equals("Series", ignoreCase = true) ||
            (MoviePilotRepository.isTvType(fetched.mediaType) &&
                !isEpisodeItem &&
                !fetched.itemType.equals("Season", ignoreCase = true)))
        val isSeason = fetched.itemType.equals("Season", ignoreCase = true)

        isLoadingSimilar = similarItems.isEmpty()
        isLoadingEpisodes = (isSeries || isSeason || isMusicAlbumItem) && episodes.isEmpty()
        detail = fetched
        isLoading = false

        coroutineScope {
            launch {
                try {
                    similarItems = repository.fetchSimilarMediaForServerItem(fetched)
                } finally {
                    isLoadingSimilar = false
                }
            }

            if (isMusicAlbumItem) {
                launch {
                    try {
                        val tracks = repository.fetchMediaServerSeasonEpisodes(
                            seriesId = fetched.itemId,
                            server = activeSrv,
                            seasonId = null,
                            seasonNumber = null,
                        )
                        episodes = tracks
                        selectedEpisodeId = tracks.firstOrNull()?.itemId
                    } finally {
                        isLoadingEpisodes = false
                    }
                }
            } else if (isEpisodeItem && !fetched.seriesId.isNullOrBlank()) {
                launch {
                    val siblingEps = repository.fetchMediaServerSeasonEpisodes(
                        seriesId = fetched.seriesId!!,
                        server = activeSrv,
                        seasonId = fetched.seasonId,
                        seasonNumber = fetched.seasonNumber,
                    )
                    episodes = siblingEps
                    selectedEpisodeId = fetched.itemId
                }
            } else if (isSeries || isSeason) {
                launch {
                    try {
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
                        val smartIdx = MoviePilotRepository.smartNextPlayableEpisodeIndex(fetchedEps) ?: 0
                        val firstEp = fetchedEps.getOrNull(smartIdx)
                        selectedEpisodeId = firstEp?.itemId
                        isLoadingEpisodes = false
                        loadEpisodeStreamPreviewIfNeeded(firstEp?.itemId, activeSrv, fetched)
                    } finally {
                        isLoadingEpisodes = false
                    }
                }
            }

            launch {
                val isTv = MoviePilotRepository.isTvType(fetched.mediaType.ifBlank { fetched.itemType })
                val querySeason = if (isTv) (selectedSeasonNum ?: fetched.seasonNumber ?: 1) else null
                val libSt = repository.checkMediaInLibraryStatus(toCardSeed(fetched), season = querySeason)
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
        }
        isRefreshing = false
    }

    LaunchedEffect(screenKey) {
        loadAll(clearOverrides = false)
    }

    LaunchedEffect(repository, screenKey) {
        repository.playbackProgressReporter.playbackStoppedEvents.collect { (stoppedServer, _) ->
            val currentSrv = detail?.server?.ifBlank { server } ?: server
            if (stoppedServer.isBlank() || currentSrv.isBlank() || stoppedServer == currentSrv) {
                loadAll(clearOverrides = false)
            }
        }
    }

    val d = detail
    val isMusicAlbum = d?.let {
        it.itemType.equals("MusicAlbum", ignoreCase = true) || it.mediaType.equals("MusicAlbum", ignoreCase = true)
    } ?: false
    val isTv = d?.let { !isMusicAlbum && MoviePilotRepository.isTvType(it.mediaType.ifBlank { it.itemType }) } ?: false
    val activeServerName = d?.server?.ifBlank { server } ?: server
    val effectiveSources = remember(d?.mediaSources, episodeFallbackSources) {
        val own = d?.mediaSources.orEmpty()
        own.ifEmpty { episodeFallbackSources }
    }
    val selectedSource = effectiveSources.getOrNull(selectedSourceIndex.coerceIn(0, (effectiveSources.size - 1).coerceAtLeast(0)))
    val primaryVideoTrack = remember(selectedSource) {
        selectedSource?.streams?.firstOrNull { it.type.equals("video", ignoreCase = true) }
    }
    val audioStreams = remember(selectedSource) {
        selectedSource?.streams?.filter { it.type.equals("audio", ignoreCase = true) }.orEmpty()
    }
    val subtitleStreams = remember(selectedSource) {
        selectedSource?.streams?.filter { it.type.equals("subtitle", ignoreCase = true) }.orEmpty()
    }

    // 当版本媒体源变更时，初始化默认音轨与（受播放偏好控制的）中文优先字幕预选项
    LaunchedEffect(selectedSource?.id, audioStreams.size, subtitleStreams.size, playbackPrefs.preferChineseSub) {
        selectedPrePlayAudioOrdinal = audioStreams.indexOfFirst { it.isDefault }.takeIf { it >= 0 } ?: 0
        selectedPrePlaySubtitleIdx = if (subtitleStreams.isEmpty()) {
            0
        } else if (playbackPrefs.preferChineseSub) {
            val bestZh = subtitleStreams.mapIndexed { idx, s ->
                idx to ChineseSubtitleMatcher.scoreChineseSubtitle(
                    language = s.language,
                    label = s.displayTitle ?: s.title,
                    isDefault = s.isDefault,
                    isExternal = s.isExternal,
                )
            }.filter { it.second > 0 }.maxByOrNull { it.second }?.first
            bestZh ?: subtitleStreams.indexOfFirst { it.isDefault }.takeIf { it >= 0 } ?: 0
        } else {
            subtitleStreams.indexOfFirst { it.isDefault }.takeIf { it >= 0 } ?: 0
        }
    }

    // 横向剧集列表初始加载后自动平滑滚向智能续播集
    LaunchedEffect(episodes.firstOrNull()?.itemId, episodes.size, isMusicAlbum) {
        if (!isMusicAlbum && episodes.isNotEmpty()) {
            val smartIdx = MoviePilotRepository.smartNextPlayableEpisodeIndex(episodes) ?: 0
            if (smartIdx > 0 && smartIdx in episodes.indices) {
                runCatching { episodesRowState.scrollToItem(smartIdx) }
            }
        }
    }

    fun formatAudioStreamSummary(tr: MediaServerStreamTrackDto, fallbackIndex: Int): String =
        listOfNotNull(
            tr.displayTitle?.takeIf { it.isNotBlank() } ?: tr.title?.takeIf { it.isNotBlank() },
            tr.language?.takeIf { it.isNotBlank() && it != "und" },
            tr.codec?.uppercase()?.takeIf { it.isNotBlank() },
            tr.channelLayout?.takeIf { it.isNotBlank() } ?: tr.channels?.takeIf { it > 0 }?.let { "${it}ch" },
        ).distinct().joinToString(" · ").ifBlank { "音轨 ${fallbackIndex + 1}" }

    fun formatSubtitleStreamSummary(tr: MediaServerStreamTrackDto, fallbackIndex: Int): String {
        val kindPrefix = if (tr.isExternal) "外挂" else "内嵌"
        val core = listOfNotNull(
            tr.displayTitle?.takeIf { it.isNotBlank() } ?: tr.title?.takeIf { it.isNotBlank() },
            tr.language?.takeIf { it.isNotBlank() && it != "und" },
        ).distinct().joinToString(" · ").ifBlank { "字幕 ${fallbackIndex + 1}" }
        return "$kindPrefix · $core"
    }

    fun formatSourceSpecSummary(src: MediaServerSourceDto, fallbackIndex: Int): String {
        val vTrack = src.streams.firstOrNull { it.type.equals("video", ignoreCase = true) }
        val resLabel = when {
            (vTrack?.width ?: 0) >= 3800 || (vTrack?.height ?: 0) >= 2100 -> "4K"
            (vTrack?.width ?: 0) >= 1900 || (vTrack?.height ?: 0) >= 1000 -> "1080P"
            (vTrack?.width ?: 0) >= 1200 || (vTrack?.height ?: 0) >= 700 -> "720P"
            else -> vTrack?.formattedResolution
        }
        return listOfNotNull(
            src.name.takeIf { it.isNotBlank() },
            resLabel,
            vTrack?.codec?.uppercase()?.takeIf { it.isNotBlank() },
            vTrack?.videoRange?.takeIf { it.isNotBlank() },
            src.container.uppercase().takeIf { it.isNotBlank() },
            formatBytesSize(src.size),
        ).distinct().joinToString(" · ").ifBlank { "版本 ${fallbackIndex + 1}" }
    }

    fun buildSeasonOrAlbumQueue(currentDetail: MediaServerItemDetailDto): List<MediaPlaybackRequest> {
        if (episodes.isEmpty()) return emptyList()
        val seriesPrefix = currentDetail.seriesName.ifBlank { currentDetail.title }
        return episodes.mapIndexed { i, ep ->
            val epNum = ep.episodeNumber ?: (i + 1)
            val epSrv = ep.server.ifBlank { activeServerName }
            val epTitle = if (isMusicAlbum) {
                ep.title.ifBlank { "曲目 $epNum" }
            } else {
                "$seriesPrefix E%02d · ${ep.title.ifBlank { "第 $epNum 集" }}".format(epNum)
            }
            MediaPlaybackRequest(
                url = "",
                title = epTitle,
                subtitle = if (isMusicAlbum) seriesPrefix else epSrv,
                albumTitle = if (isMusicAlbum) currentDetail.title else "",
                artworkUrl = ep.thumb ?: ep.backdrop ?: ep.poster ?: currentDetail.poster ?: fallbackPoster,
                isAudio = isMusicAlbum,
                itemId = ep.itemId,
                server = epSrv,
                serverType = currentDetail.serverType,
                resumePositionMs = ep.resumePositionMs,
                queueIndex = i,
                lazySpec = QueueTrackSpec.MediaServerItem(
                    itemId = ep.itemId,
                    server = epSrv,
                ),
            )
        }
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

    fun startStreamPlayback(
        targetItemId: String,
        titleFallback: String,
        subtitleFallback: String,
        artwork: String?,
        sourceId: String? = null,
        queue: List<MediaPlaybackRequest> = emptyList(),
        queueIndex: Int = 0,
        launchInExternalPlayer: Boolean = false,
    ) {
        scope.launch {
            feedback = null
            val manifest = repository.fetchVideoStreamInfo(targetItemId, activeServerName.ifBlank { null }, sourceId)
            if (manifest != null) {
                val forceAudio = isMusicAlbum || manifest.mediaType == "audio"
                if (launchInExternalPlayer) {
                    val ok = ExternalPlayerLauncher.launchExternalPlayerChooser(
                        context = context,
                        streamUrl = manifest.contentUrl,
                        title = manifest.title.ifBlank { titleFallback },
                        isAudio = forceAudio,
                        headers = manifest.headers,
                    )
                    if (!ok) {
                        feedbackIsError = true
                        feedback = "未找到可用的外部播放器应用"
                    }
                    return@launch
                }
                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                val preAudio = audioStreams.getOrNull(selectedPrePlayAudioOrdinal)
                val disableSubs = subtitleStreams.isNotEmpty() && selectedPrePlaySubtitleIdx < 0
                val preSub = if (!disableSubs) subtitleStreams.getOrNull(selectedPrePlaySubtitleIdx) else null

                onPlayMedia(
                    MediaPlaybackRequest(
                        url = manifest.contentUrl,
                        title = if (queue.isNotEmpty() && !isMusicAlbum) titleFallback else manifest.title.ifBlank { titleFallback },
                        subtitle = subtitleFallback,
                        albumTitle = if (isMusicAlbum) (d?.title.orEmpty()) else "",
                        artworkUrl = artwork,
                        isAudio = forceAudio,
                        lyricsLrc = lrc,
                        headers = manifest.headers,
                        itemId = manifest.itemId,
                        server = manifest.server.ifBlank { activeServerName },
                        serverType = manifest.serverType.ifBlank { d?.serverType.orEmpty() },
                        mediaSourceId = manifest.mediaSourceId ?: sourceId.orEmpty(),
                        playSessionId = manifest.playSessionId,
                        progressSyncMode = manifest.progressSyncMode,
                        resumePositionMs = manifest.resumePositionMs,
                        subtitles = manifest.subtitles.map {
                            SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                        },
                        queue = queue,
                        queueIndex = queueIndex,
                        externalPlayUrl = d?.playUrl,
                        preferredAudioIndex = selectedPrePlayAudioOrdinal.takeIf { audioStreams.isNotEmpty() },
                        preferredAudioLang = preAudio?.language ?: preAudio?.displayTitle,
                        preferredSubtitleId = preSub?.subtitleId?.takeIf { it.isNotBlank() },
                        preferredSubtitleLang = preSub?.language ?: preSub?.displayTitle ?: preSub?.title,
                        disableSubtitles = disableSubs,
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
                if (isLoading && d == null) {
                    NativeMediaDetailSkeleton(
                        heroHeight = heroHeight,
                        isCompactLandscape = isCompactLandscape,
                        isLandscape = isLandscape,
                        showServerExtras = true,
                    )
                } else {
                ProvideSkeletonShimmer {
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

                    if (d != null) {
                        // 2. 主操作按钮行（立即播放 / 继续播放 / 播放全部 + 权威订阅切换 + 外部播放器/客户端 + 播前选轨卡）
                        item(key = "ms_actions") {
                            val btnHeight = if (isCompactLandscape) 44.dp else 50.dp
                            val smartEpIdx = remember(episodes) {
                                MoviePilotRepository.smartNextPlayableEpisodeIndex(episodes) ?: 0
                            }
                            val targetPlayEpIdx = if (episodes.isNotEmpty()) {
                                if (d.itemType.equals("Episode", ignoreCase = true)) {
                                    episodes.indexOfFirst { it.itemId == d.itemId }.takeIf { it >= 0 } ?: smartEpIdx
                                } else {
                                    episodes.indexOfFirst { it.itemId == selectedEpisodeId }.takeIf { it >= 0 } ?: smartEpIdx
                                }
                            } else {
                                0
                            }
                            val targetPlayEp = if (episodes.isNotEmpty() && !d.itemType.equals("Episode", ignoreCase = true)) {
                                episodes.getOrNull(targetPlayEpIdx)
                            } else {
                                null
                            }
                            val playTargetId = targetPlayEp?.itemId ?: d.itemId
                            val resumeMs = targetPlayEp?.resumePositionMs?.takeIf { it > 0L } ?: d.resumePositionMs
                            val resolvedSourceId = if (targetPlayEp == null || targetPlayEp.itemId == previewedEpisodeId) {
                                selectedSource?.id?.ifBlank { null }
                            } else {
                                null
                            }
                            val playLabel = when {
                                isMusicAlbum -> "播放全部"
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
                                            val queue = buildSeasonOrAlbumQueue(d)
                                            val titleFallback = if (targetPlayEp != null && !isMusicAlbum) {
                                                val epNum = targetPlayEp.episodeNumber ?: (targetPlayEpIdx + 1)
                                                "${d.seriesName.ifBlank { d.title }} E%02d · ${targetPlayEp.title}".format(epNum)
                                            } else {
                                                targetPlayEp?.title?.ifBlank { d.title } ?: d.title
                                            }
                                            startStreamPlayback(
                                                targetItemId = playTargetId,
                                                titleFallback = titleFallback,
                                                subtitleFallback = listOfNotNull(
                                                    activeServerName.ifBlank { null },
                                                    d.year.ifBlank { null },
                                                ).joinToString(" · "),
                                                artwork = targetPlayEp?.thumb ?: d.poster ?: fallbackPoster,
                                                sourceId = resolvedSourceId,
                                                queue = queue,
                                                queueIndex = targetPlayEpIdx,
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

                                    if (!isMusicAlbum) {
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
                                }

                                // 外部播放器与媒体服务器原生客户端快捷胶囊
                                val nativeClientScheme = remember(d.serverType, activeServerName, playTargetId, d.playUrl) {
                                    ExternalPlayerLauncher.buildMediaServerDeepLink(d.serverType, activeServerName, playTargetId, d.playUrl)
                                }
                                FlowRow(
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    NativeAdaptivePill(
                                        title = "外部播放器",
                                        selected = false,
                                        icon = Icons.AutoMirrored.Rounded.OpenInNew,
                                        onClick = {
                                            startStreamPlayback(
                                                targetItemId = playTargetId,
                                                titleFallback = targetPlayEp?.title?.ifBlank { d.title } ?: d.title,
                                                subtitleFallback = activeServerName,
                                                artwork = d.poster ?: fallbackPoster,
                                                sourceId = resolvedSourceId,
                                                launchInExternalPlayer = true,
                                            )
                                        },
                                    )
                                    if (!nativeClientScheme.isNullOrBlank() || !d.playUrl.isNullOrBlank()) {
                                        NativeAdaptivePill(
                                            title = "在 ${activeServerName.ifBlank { "媒体客户端" }} 打开",
                                            selected = false,
                                            icon = Icons.Rounded.Link,
                                            onClick = {
                                                val ok = ExternalPlayerLauncher.launchMediaServerClientOrFallback(
                                                    context = context,
                                                    serverType = d.serverType,
                                                    serverName = activeServerName,
                                                    itemId = playTargetId,
                                                    playUrl = d.playUrl,
                                                )
                                                if (!ok) {
                                                    feedbackIsError = true
                                                    feedback = "本机暂未安装对应媒体客户端且无网页播放地址"
                                                }
                                            },
                                        )
                                    }
                                }

                                // 播前版本 / 音轨 / 字幕选择器卡（1:1 对齐 iOS prePlayTrackSelectorCard）
                                if (!isMusicAlbum && selectedSource != null) {
                                    val curAudioLabel = audioStreams.getOrNull(selectedPrePlayAudioOrdinal)?.let {
                                        formatAudioStreamSummary(it, selectedPrePlayAudioOrdinal)
                                    } ?: "默认音轨"
                                    val curSubtitleLabel = when {
                                        selectedPrePlaySubtitleIdx < 0 -> "关闭字幕"
                                        subtitleStreams.isNotEmpty() -> subtitleStreams.getOrNull(selectedPrePlaySubtitleIdx)?.let {
                                            formatSubtitleStreamSummary(it, selectedPrePlaySubtitleIdx)
                                        } ?: "默认字幕"
                                        else -> "无字幕"
                                    }
                                    CinematicPanel(padding = 0.dp, showsShadow = false) {
                                        Column {
                                            PrePlaySelectorRow(
                                                label = if (effectiveSources.size > 1) "版本" else "视频",
                                                value = formatSourceSpecSummary(selectedSource, selectedSourceIndex),
                                                interactive = effectiveSources.size > 1,
                                                onClick = { showVersionPickerSheet = true },
                                            )
                                            if (audioStreams.isNotEmpty()) {
                                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 16.dp))
                                                PrePlaySelectorRow(
                                                    label = "音轨",
                                                    value = curAudioLabel,
                                                    interactive = audioStreams.size > 1,
                                                    onClick = { showPrePlayAudioSheet = true },
                                                )
                                            }
                                            if (subtitleStreams.isNotEmpty()) {
                                                HorizontalDivider(color = colors.divider, modifier = Modifier.padding(start = 16.dp))
                                                PrePlaySelectorRow(
                                                    label = "字幕",
                                                    value = curSubtitleLabel,
                                                    interactive = true,
                                                    onClick = { showPrePlaySubtitleSheet = true },
                                                )
                                            }
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

                        // 4. 剧集列表 / 音乐专辑曲目列表
                        if (seasons.isNotEmpty() || episodes.isNotEmpty() || isLoadingEpisodes) {
                            item(key = "ms_episodes") {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    val sectionTitle = when {
                                        isMusicAlbum -> "曲目列表"
                                        d.itemType.equals("Episode", ignoreCase = true) -> "本季更多剧集"
                                        else -> "剧集列表"
                                    }
                                    val sectionSub = if (!isLoadingEpisodes && episodes.isNotEmpty()) {
                                        "共 ${episodes.size} ${if (isMusicAlbum) "首" else "集"}"
                                    } else {
                                        null
                                    }
                                    NativeSectionHeader(
                                        title = sectionTitle,
                                        subtitle = sectionSub,
                                        modifier = Modifier.padding(horizontal = margin),
                                    )
                                    if (!isMusicAlbum && seasons.size > 1) {
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
                                                                isLoadingEpisodes = true
                                                                try {
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
                                                                    val smartIdx = MoviePilotRepository.smartNextPlayableEpisodeIndex(newEps) ?: 0
                                                                    val firstEp = newEps.getOrNull(smartIdx)
                                                                    selectedEpisodeId = firstEp?.itemId
                                                                    isLoadingEpisodes = false
                                                                    loadEpisodeStreamPreviewIfNeeded(firstEp?.itemId, activeServerName, d)
                                                                } finally {
                                                                    isLoadingEpisodes = false
                                                                }
                                                            }
                                                        }
                                                    },
                                                )
                                            }
                                        }
                                    }

                                    if (isLoadingEpisodes) {
                                        NativeEpisodeShelfSkeleton(
                                            cardWidth = 228.dp,
                                            cardHeight = 128.dp,
                                            count = 4,
                                            contentPadding = PaddingValues(horizontal = margin),
                                        )
                                    } else if (isMusicAlbum && episodes.isNotEmpty()) {
                                        CinematicPanel(
                                            padding = 0.dp,
                                            showsShadow = false,
                                            modifier = Modifier.padding(horizontal = margin),
                                        ) {
                                            Column {
                                                episodes.forEachIndexed { idx, track ->
                                                    val trackNum = track.episodeNumber ?: (idx + 1)
                                                    Row(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .clickable {
                                                                selectedEpisodeId = track.itemId
                                                                val queue = buildSeasonOrAlbumQueue(d)
                                                                startStreamPlayback(
                                                                    targetItemId = track.itemId,
                                                                    titleFallback = track.title.ifBlank { "曲目 $trackNum" },
                                                                    subtitleFallback = d.seriesName.ifBlank { d.title },
                                                                    artwork = track.thumb ?: track.poster ?: d.poster ?: fallbackPoster,
                                                                    queue = queue,
                                                                    queueIndex = idx,
                                                                )
                                                            }
                                                            .padding(horizontal = 16.dp, vertical = 13.dp),
                                                        verticalAlignment = Alignment.CenterVertically,
                                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                                    ) {
                                                        Text(
                                                            text = "%02d".format(trackNum),
                                                            color = colors.textMuted,
                                                            fontSize = 13.sp,
                                                            fontWeight = FontWeight.SemiBold,
                                                            modifier = Modifier.width(26.dp),
                                                        )
                                                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                                            Text(
                                                                text = track.title.ifBlank { "曲目 $trackNum" },
                                                                color = colors.textPrimary,
                                                                fontSize = 14.5.sp,
                                                                fontWeight = FontWeight.SemiBold,
                                                                maxLines = 1,
                                                                overflow = TextOverflow.Ellipsis,
                                                            )
                                                            formatDurationMinutes(track.durationMs)?.let { dur ->
                                                                Text(dur, color = colors.textMuted, fontSize = 11.5.sp)
                                                            }
                                                        }
                                                        Icon(
                                                            Icons.Rounded.PlayCircle,
                                                            contentDescription = "播放 ${track.title}",
                                                            tint = colors.accent,
                                                            modifier = Modifier.size(24.dp),
                                                        )
                                                    }
                                                    if (idx < episodes.lastIndex) {
                                                        HorizontalDivider(
                                                            color = colors.divider,
                                                            modifier = Modifier.padding(start = 54.dp, end = 16.dp),
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    } else if (episodes.isNotEmpty()) {
                                        LazyRow(
                                            state = episodesRowState,
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            itemsIndexed(episodes, key = { idx, ep -> "ep_${ep.itemId}_$idx" }) { idx, ep ->
                                                val epNum = ep.episodeNumber ?: (idx + 1)
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
                                                            val queue = buildSeasonOrAlbumQueue(d)
                                                            startStreamPlayback(
                                                                targetItemId = ep.itemId,
                                                                titleFallback = "${d.seriesName.ifBlank { d.title }} E%02d · ${ep.title}".format(epNum),
                                                                subtitleFallback = activeServerName,
                                                                artwork = stillImage,
                                                                sourceId = if (ep.itemId == previewedEpisodeId) selectedSource?.id?.ifBlank { null } else null,
                                                                queue = queue,
                                                                queueIndex = idx,
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
                        if (isLoadingSimilar && similarItems.isEmpty()) {
                            item(key = "ms_similar_loading") {
                                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                    NativeSectionHeader(title = "类似作品", modifier = Modifier.padding(horizontal = margin))
                                    NativePosterShelfSkeleton(
                                        posterWidth = 118.dp,
                                        count = 6,
                                        contentPadding = PaddingValues(horizontal = margin),
                                    )
                                }
                            }
                        } else if (similarItems.isNotEmpty()) {
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
                if (d != null) {
                    DropdownMenuItem(
                        text = { Text("外部播放器播放") },
                        onClick = {
                            showTopMoreMenu = false
                            val ep = episodes.firstOrNull { it.itemId == selectedEpisodeId }
                            val targetId = ep?.itemId ?: d.itemId
                            startStreamPlayback(
                                targetItemId = targetId,
                                titleFallback = ep?.title?.ifBlank { d.title } ?: d.title,
                                subtitleFallback = activeServerName,
                                artwork = d.poster ?: fallbackPoster,
                                sourceId = if (ep == null || ep.itemId == previewedEpisodeId) selectedSource?.id?.ifBlank { null } else null,
                                launchInExternalPlayer = true,
                            )
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("在 ${activeServerName.ifBlank { "客户端" }} 打开") },
                        onClick = {
                            showTopMoreMenu = false
                            val ep = episodes.firstOrNull { it.itemId == selectedEpisodeId }
                            ExternalPlayerLauncher.launchMediaServerClientOrFallback(
                                context = context,
                                serverType = d.serverType,
                                serverName = activeServerName,
                                itemId = ep?.itemId ?: d.itemId,
                                playUrl = d.playUrl,
                            )
                        },
                    )
                }
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

    // 播前版本选择弹窗
    if (showVersionPickerSheet && effectiveSources.size > 1) {
        NativeGlassSheet(onDismissRequest = { showVersionPickerSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("选择播放版本", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    itemsIndexed(effectiveSources) { idx, src ->
                        val picked = idx == selectedSourceIndex
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (picked) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable {
                                    selectedSourceIndex = idx
                                    showVersionPickerSheet = false
                                }
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = formatSourceSpecSummary(src, idx),
                                color = colors.textPrimary,
                                fontSize = 14.5.sp,
                                fontWeight = if (picked) FontWeight.Bold else FontWeight.Normal,
                                modifier = Modifier.weight(1f),
                            )
                            if (picked) {
                                Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
                Spacer(Modifier.height(14.dp))
            }
        }
    }

    // 播前音轨预选弹窗
    if (showPrePlayAudioSheet && audioStreams.isNotEmpty()) {
        NativeGlassSheet(onDismissRequest = { showPrePlayAudioSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("预选播放音轨", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    itemsIndexed(audioStreams) { idx, tr ->
                        val picked = idx == selectedPrePlayAudioOrdinal
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (picked) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable {
                                    selectedPrePlayAudioOrdinal = idx
                                    showPrePlayAudioSheet = false
                                }
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = formatAudioStreamSummary(tr, idx),
                                color = colors.textPrimary,
                                fontSize = 14.5.sp,
                                fontWeight = if (picked) FontWeight.Bold else FontWeight.Normal,
                                modifier = Modifier.weight(1f),
                            )
                            if (picked) {
                                Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
                Spacer(Modifier.height(14.dp))
            }
        }
    }

    // 播前字幕预选弹窗
    if (showPrePlaySubtitleSheet && subtitleStreams.isNotEmpty()) {
        NativeGlassSheet(onDismissRequest = { showPrePlaySubtitleSheet = false }) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("预选播放字幕", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item(key = "sub_off") {
                        val offPicked = selectedPrePlaySubtitleIdx < 0
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (offPicked) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable {
                                    selectedPrePlaySubtitleIdx = -1
                                    showPrePlaySubtitleSheet = false
                                }
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = "关闭字幕",
                                color = colors.textPrimary,
                                fontSize = 14.5.sp,
                                fontWeight = if (offPicked) FontWeight.Bold else FontWeight.Normal,
                            )
                            if (offPicked) {
                                Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                    itemsIndexed(subtitleStreams) { idx, tr ->
                        val picked = idx == selectedPrePlaySubtitleIdx
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(if (picked) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable {
                                    selectedPrePlaySubtitleIdx = idx
                                    showPrePlaySubtitleSheet = false
                                }
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(
                                text = formatSubtitleStreamSummary(tr, idx),
                                color = colors.textPrimary,
                                fontSize = 14.5.sp,
                                fontWeight = if (picked) FontWeight.Bold else FontWeight.Normal,
                                modifier = Modifier.weight(1f),
                            )
                            if (picked) {
                                Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
                Spacer(Modifier.height(14.dp))
            }
        }
    }
}

@Composable
private fun PrePlaySelectorRow(
    label: String,
    value: String,
    interactive: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (interactive) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = label,
            color = colors.textSecondary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
        Text(
            text = value,
            color = colors.textPrimary,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.End,
            modifier = Modifier.weight(1f),
        )
        if (interactive) {
            Icon(
                imageVector = Icons.Rounded.UnfoldMore,
                contentDescription = null,
                tint = colors.textMuted,
                modifier = Modifier.size(17.dp),
            )
        }
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
