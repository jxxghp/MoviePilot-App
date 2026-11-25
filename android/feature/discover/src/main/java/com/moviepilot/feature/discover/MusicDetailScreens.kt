package com.moviepilot.feature.discover

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.PlayCircle
import androidx.compose.material.icons.rounded.VideoLibrary
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeCardListSkeleton
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativePosterGridSkeleton
import com.moviepilot.designsystem.SkeletonCardStyle
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.QueueTrackSpec
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaServerBrowseItemDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.MusicAlbumDetailDto
import com.moviepilot.rustbridge.MusicAlbumDto
import com.moviepilot.rustbridge.MusicArtistDetailDto
import com.moviepilot.rustbridge.MusicTrackDto
import kotlinx.coroutines.launch

private fun formatTrackDurationSeconds(seconds: Int): String {
    if (seconds <= 0) return ""
    val m = seconds / 60
    val s = seconds % 60
    return "%d:%02d".format(m, s)
}

/**
 * 原生音乐专辑详情页（对齐 iOS `NativeMusicAlbumDetailPage`）：
 * - 1:1 阴影封面、可点击艺人入口（直达 `MusicArtistDetailScreen`）、流派与年份胶囊；
 * - 支持「播放全部」与「订阅专辑 / 已订阅专辑（二次确认退订）」；
 * - 完整支持多碟（Multi-Disc）分组曲目列表，点击任意曲目实时匹配 `/api/v1/mediaserver/stream-info/music` 并将整张专辑载入播放队列。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MusicAlbumDetailScreen(
    seed: MusicAlbumDto,
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onOpenArtist: (artistId: String, artistName: String, source: String) -> Unit,
    onPlayAudio: (MediaPlaybackRequest) -> Unit,
    canSubscribe: Boolean = true,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val scope = rememberCoroutineScope()

    val lookupKey = "${seed.source}|${seed.lookupAlbumId}"
    var detail by remember(lookupKey) { mutableStateOf<MusicAlbumDetailDto?>(null) }
    var isLoading by remember(lookupKey) { mutableStateOf(true) }
    var isSubscribed by remember(lookupKey) { mutableStateOf(false) }
    var isMutatingSub by remember(lookupKey) { mutableStateOf(false) }
    var showUnsubscribeConfirm by remember(lookupKey) { mutableStateOf(false) }
    var resolvingTrackIndex by remember(lookupKey) { mutableStateOf<Int?>(null) }
    var feedback by remember(lookupKey) { mutableStateOf<Pair<String, Boolean>?>(null) }

    LaunchedEffect(lookupKey) {
        isLoading = true
        val loaded = repository.fetchMusicAlbumDetail(
            albumId = seed.lookupAlbumId,
            source = seed.source,
            releaseId = seed.releaseId,
        )
        detail = loaded
        isLoading = false
        if (canSubscribe && seed.id.isNotBlank()) {
            isSubscribed = repository.checkMusicAlbumSubscribed(seed.source, seed.id)
        }
    }

    val resolvedTitle = detail?.title?.ifBlank { seed.title } ?: seed.title
    val resolvedArtist = detail?.artist?.ifBlank { seed.artist } ?: seed.artist
    val primaryArtistId = detail?.artistIds?.firstOrNull()?.takeIf { it.isNotBlank() } ?: seed.artistId
    val resolvedCover = detail?.coverUrl ?: seed.coverUrl
    val resolvedYear = detail?.year?.ifBlank { seed.year } ?: seed.year
    val resolvedOverview = detail?.overview?.ifBlank { seed.overview } ?: seed.overview
    val tracks = detail?.tracks.orEmpty()
    val totalTrackCount = detail?.totalTracks?.takeIf { it > 0 } ?: tracks.size.takeIf { it > 0 } ?: seed.totalTracks

    fun buildAlbumQueue(): List<MediaPlaybackRequest> {
        if (tracks.isEmpty()) {
            return listOf(
                MediaPlaybackRequest(
                    url = "",
                    title = resolvedTitle,
                    subtitle = resolvedArtist,
                    albumTitle = resolvedTitle,
                    artworkUrl = resolvedCover,
                    isAudio = true,
                    lazySpec = QueueTrackSpec.MusicQuery(
                        title = resolvedTitle,
                        artist = resolvedArtist.ifBlank { null },
                        album = resolvedTitle,
                    ),
                ),
            )
        }
        return tracks.mapIndexed { idx, track ->
            val trackArtist = track.artist.ifBlank { resolvedArtist }
            MediaPlaybackRequest(
                url = "",
                title = track.title,
                subtitle = listOfNotNull(trackArtist.ifBlank { null }, resolvedTitle.ifBlank { null }).joinToString(" · "),
                albumTitle = resolvedTitle,
                artworkUrl = resolvedCover,
                isAudio = true,
                queueIndex = idx,
                lazySpec = QueueTrackSpec.MusicQuery(
                    title = track.title,
                    artist = trackArtist.ifBlank { null },
                    album = resolvedTitle,
                ),
            )
        }
    }

    fun playAlbumTrackAt(targetIndex: Int) {
        if (resolvingTrackIndex != null) return
        scope.launch {
            resolvingTrackIndex = targetIndex
            feedback = null
            val queue = buildAlbumQueue()
            val chosen = queue.getOrNull(targetIndex) ?: queue.firstOrNull()
            if (chosen == null) {
                resolvingTrackIndex = null
                return@launch
            }
            val querySpec = chosen.lazySpec as? QueueTrackSpec.MusicQuery
            val manifest = repository.fetchMusicStreamInfo(
                title = querySpec?.title ?: chosen.title,
                artist = querySpec?.artist,
                album = querySpec?.album ?: resolvedTitle,
            )
            resolvingTrackIndex = null
            if (manifest != null) {
                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                val resolvedReq = chosen.copy(
                    url = manifest.contentUrl,
                    title = manifest.title.ifBlank { chosen.title },
                    lyricsLrc = lrc,
                    headers = manifest.headers,
                    itemId = manifest.itemId,
                    server = manifest.server,
                    serverType = manifest.serverType,
                    mediaSourceId = manifest.mediaSourceId.orEmpty(),
                    playSessionId = manifest.playSessionId,
                    progressSyncMode = manifest.progressSyncMode,
                    queue = queue,
                    queueIndex = targetIndex.coerceIn(0, (queue.size - 1).coerceAtLeast(0)),
                )
                val updatedQueue = queue.mapIndexed { i, item ->
                    if (i == resolvedReq.queueIndex) resolvedReq.copy(queue = emptyList()) else item
                }
                onPlayAudio(resolvedReq.copy(queue = updatedQueue))
            } else {
                feedback = "媒体服务器暂未匹配到曲目「${chosen.title}」的可播放音频" to true
            }
        }
    }

    val discGroups = remember(tracks) {
        tracks.groupBy { it.discNumber }.toSortedMap()
    }
    val hasMultipleDiscs = discGroups.size > 1
    val subscribedEmeraldBg = Color(0xFF1F9D55)

    ExpressiveTintedScaffold(
        title = "专辑详情",
        subtitle = resolvedArtist.ifBlank { null },
        onBack = onBack,
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 16.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 1. 封面、标题、艺人跳转入口与元数据胶囊
            item(key = "album_header") {
                val artSize = if (compactHeight) 150.dp else 208.dp
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(artSize)
                            .shadow(18.dp, RoundedCornerShape(22.dp))
                            .clip(RoundedCornerShape(22.dp))
                            .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.55f), Color(0xFF281F3D))))
                            .border(0.8.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(22.dp)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(64.dp))
                        if (!resolvedCover.isNullOrBlank()) {
                            AsyncImage(
                                model = resolvedCover,
                                contentDescription = resolvedTitle,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }

                    Text(
                        text = resolvedTitle,
                        color = colors.textPrimary,
                        fontSize = if (compactHeight) 20.sp else 23.sp,
                        fontWeight = FontWeight.ExtraBold,
                        textAlign = TextAlign.Center,
                    )

                    if (resolvedArtist.isNotBlank()) {
                        if (!primaryArtistId.isNullOrBlank()) {
                            Surface(
                                onClick = {
                                    onOpenArtist(primaryArtistId, resolvedArtist, detail?.source ?: seed.source)
                                },
                                shape = CircleShape,
                                color = colors.chipFill,
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Text(
                                        text = resolvedArtist,
                                        color = colors.accent,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                    Icon(
                                        Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                                        contentDescription = "查看艺人详情",
                                        tint = colors.accent,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                            }
                        } else {
                            Text(
                                text = resolvedArtist,
                                color = colors.textSecondary,
                                fontSize = 14.5.sp,
                                fontWeight = FontWeight.Medium,
                            )
                        }
                    }

                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        if (resolvedYear.isNotBlank()) {
                            NativeAdaptiveBadge(resolvedYear, tint = colors.textSecondary)
                        }
                        val albumKind = detail?.albumType?.ifBlank { seed.albumType }.orEmpty()
                        if (albumKind.isNotBlank()) {
                            NativeAdaptiveBadge(albumKind, tint = colors.accent)
                        }
                        if (totalTrackCount > 0) {
                            NativeAdaptiveBadge("$totalTrackCount 首曲目", tint = colors.info)
                        }
                        if (seed.voteAverage > 0.0) {
                            NativeAdaptiveBadge("★ %.1f".format(seed.voteAverage), tint = colors.warning)
                        }
                    }
                }
            }

            // 2. 主操作栏：「播放全部」+「订阅专辑 / 已订阅专辑」
            item(key = "album_actions") {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Button(
                        onClick = { playAlbumTrackAt(0) },
                        enabled = resolvingTrackIndex == null,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accent,
                            contentColor = colors.primaryButtonFg,
                        ),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(48.dp),
                    ) {
                        if (resolvingTrackIndex == 0) {
                            CircularProgressIndicator(
                                color = colors.primaryButtonFg,
                                strokeWidth = 2.dp,
                                modifier = Modifier.size(18.dp),
                            )
                        } else {
                            Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(20.dp))
                        }
                        Spacer(Modifier.width(6.dp))
                        Text(
                            text = if (resolvingTrackIndex == 0) "匹配音轨中…" else "播放全部",
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp,
                        )
                    }

                    if (canSubscribe && seed.id.isNotBlank()) {
                        Button(
                            onClick = {
                                if (isSubscribed) {
                                    showUnsubscribeConfirm = true
                                } else {
                                    scope.launch {
                                        isMutatingSub = true
                                        val (ok, msg) = repository.subscribeMusicAlbum(
                                            title = resolvedTitle,
                                            mediaSource = detail?.source ?: seed.source,
                                            mediaId = seed.id,
                                            year = resolvedYear,
                                            totalTracks = totalTrackCount,
                                        )
                                        isMutatingSub = false
                                        if (ok) isSubscribed = true
                                        feedback = msg to !ok
                                    }
                                }
                            },
                            enabled = !isMutatingSub,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isSubscribed) subscribedEmeraldBg else colors.surfaceContainerHigh,
                                contentColor = if (isSubscribed) Color.White else colors.textPrimary,
                            ),
                            shape = CircleShape,
                            modifier = Modifier
                                .weight(1f)
                                .height(48.dp)
                                .border(
                                    0.8.dp,
                                    if (isSubscribed) subscribedEmeraldBg else colors.chipBorder,
                                    CircleShape,
                                ),
                        ) {
                            Icon(
                                imageVector = if (isSubscribed) Icons.Rounded.CheckCircle else Icons.Outlined.BookmarkBorder,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(
                                text = if (isSubscribed) "已订阅专辑" else "订阅专辑",
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.5.sp,
                            )
                        }
                    }
                }
            }

            feedback?.let { (msg, isErr) ->
                item(key = "album_feedback") {
                    CinematicPanel(padding = 12.dp, showsShadow = false) {
                        Text(
                            text = msg,
                            color = if (isErr) colors.warning else colors.success,
                            fontSize = 13.sp,
                        )
                    }
                }
            }

            if (resolvedOverview.isNotBlank()) {
                item(key = "album_overview") {
                    CinematicPanel(padding = 16.dp, showsShadow = false) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("专辑简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                            Text(resolvedOverview, color = colors.textSecondary, fontSize = 13.5.sp, lineHeight = 21.sp)
                        }
                    }
                }
            }

            // 3. 分碟曲目列表
            if (isLoading && detail == null) {
                item(key = "album_tracks_skeleton") {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("曲目列表", color = colors.textPrimary, fontSize = 16.5.sp, fontWeight = FontWeight.Bold)
                        NativeCardListSkeleton(
                            style = SkeletonCardStyle.IconRow,
                            count = 6,
                            contentPadding = PaddingValues(0.dp),
                            scrollable = false,
                        )
                    }
                }
            } else if (tracks.isNotEmpty()) {
                discGroups.forEach { (discNum, discTracks) ->
                    item(key = "album_disc_$discNum") {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                text = if (hasMultipleDiscs) "曲目列表 · Disc $discNum" else "曲目列表 (${tracks.size})",
                                color = colors.textPrimary,
                                fontSize = 16.5.sp,
                                fontWeight = FontWeight.Bold,
                            )
                            CinematicPanel(padding = 0.dp, showsShadow = false) {
                                Column {
                                    discTracks.forEachIndexed { localIdx, tr ->
                                        val globalIndex = tracks.indexOf(tr).coerceAtLeast(0)
                                        val isResolving = resolvingTrackIndex == globalIndex
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clickable(enabled = resolvingTrackIndex == null) {
                                                    playAlbumTrackAt(globalIndex)
                                                }
                                                .padding(horizontal = 16.dp, vertical = 13.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            Text(
                                                text = "%02d".format(tr.trackNumber.takeIf { it > 0 } ?: (localIdx + 1)),
                                                color = colors.textMuted,
                                                fontSize = 13.sp,
                                                fontWeight = FontWeight.SemiBold,
                                                modifier = Modifier.width(26.dp),
                                            )
                                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                                Text(
                                                    text = tr.title,
                                                    color = colors.textPrimary,
                                                    fontSize = 14.5.sp,
                                                    fontWeight = FontWeight.SemiBold,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                )
                                                if (tr.artist.isNotBlank() && tr.artist != resolvedArtist) {
                                                    Text(
                                                        text = tr.artist,
                                                        color = colors.textSecondary,
                                                        fontSize = 12.sp,
                                                        maxLines = 1,
                                                        overflow = TextOverflow.Ellipsis,
                                                    )
                                                }
                                            }
                                            val durStr = formatTrackDurationSeconds(tr.durationSeconds)
                                            if (durStr.isNotEmpty()) {
                                                Text(durStr, color = colors.textMuted, fontSize = 12.sp)
                                            }
                                            if (isResolving) {
                                                CircularProgressIndicator(
                                                    color = colors.accent,
                                                    strokeWidth = 2.dp,
                                                    modifier = Modifier.size(18.dp),
                                                )
                                            } else {
                                                Icon(
                                                    Icons.Rounded.PlayCircle,
                                                    contentDescription = "播放 ${tr.title}",
                                                    tint = colors.accent,
                                                    modifier = Modifier.size(22.dp),
                                                )
                                            }
                                        }
                                        if (localIdx < discTracks.lastIndex) {
                                            HorizontalDivider(
                                                color = colors.divider,
                                                modifier = Modifier.padding(start = 54.dp, end = 16.dp),
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

    if (showUnsubscribeConfirm) {
        AlertDialog(
            onDismissRequest = { showUnsubscribeConfirm = false },
            title = { Text("取消音乐订阅") },
            text = { Text("确认取消订阅专辑「$resolvedTitle」吗？") },
            dismissButton = {
                TextButton(onClick = { showUnsubscribeConfirm = false }) {
                    Text("保留")
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showUnsubscribeConfirm = false
                        scope.launch {
                            isMutatingSub = true
                            val (ok, msg) = repository.unsubscribeMusicAlbum(
                                mediaSource = detail?.source ?: seed.source,
                                mediaId = seed.id,
                            )
                            isMutatingSub = false
                            if (ok) isSubscribed = false
                            feedback = msg to !ok
                        }
                    },
                ) {
                    Text("取消订阅", color = colors.danger)
                }
            },
        )
    }
}

/**
 * 原生音乐艺术家详情页（对齐 iOS `NativeMusicArtistDetailPage`）：
 * 展示圆形艺人头像、国家/地区与活跃年代、艺人简介及自适应方形专辑作品网格。
 */
@Composable
fun MusicArtistDetailScreen(
    artistId: String,
    artistName: String,
    source: String,
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onOpenAlbum: (MusicAlbumDto) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val cols = AdaptiveDeviceLayout.squareGridColumns()

    val key = "$source|$artistId"
    var detail by remember(key) { mutableStateOf<MusicArtistDetailDto?>(null) }
    var isLoading by remember(key) { mutableStateOf(true) }

    LaunchedEffect(key) {
        isLoading = true
        detail = repository.fetchMusicArtistDetail(
            artistId = artistId,
            source = source,
            fallbackName = artistName,
        )
        isLoading = false
    }

    val displayName = detail?.name?.ifBlank { artistName } ?: artistName
    val metaLine = remember(detail) {
        listOfNotNull(
            detail?.area?.ifBlank { detail?.country }?.takeIf { it.isNotBlank() },
            detail?.lifeSpan?.takeIf { it.isNotBlank() },
        ).joinToString(" · ")
    }
    val albums = detail?.albums.orEmpty()

    ExpressiveTintedScaffold(
        title = displayName,
        subtitle = metaLine.ifBlank { "音乐人" },
        onBack = onBack,
    ) {
        if (isLoading && detail == null) {
            NativePosterGridSkeleton(
                columns = cols,
                aspectRatio = 1f,
                inPanel = true,
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 16.dp,
                    bottom = bottomOverlayInset + 24.dp,
                ),
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(cols),
                contentPadding = PaddingValues(
                    start = margin,
                    end = margin,
                    top = 16.dp,
                    bottom = bottomOverlayInset + 28.dp,
                ),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "artist_header") {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(112.dp)
                                .clip(CircleShape)
                                .background(colors.chipFill)
                                .border(1.dp, colors.chipBorder, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Rounded.Person, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(48.dp))
                            if (!detail?.imageUrl.isNullOrBlank()) {
                                AsyncImage(
                                    model = detail?.imageUrl,
                                    contentDescription = displayName,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                        }
                        Text(displayName, color = colors.textPrimary, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                        if (metaLine.isNotBlank()) {
                            Text(metaLine, color = colors.textSecondary, fontSize = 13.sp)
                        }
                    }
                }

                if (!detail?.overview.isNullOrBlank()) {
                    item(span = { GridItemSpan(maxLineSpan) }, key = "artist_bio") {
                        CinematicPanel(padding = 16.dp, showsShadow = false) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("艺人简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                                Text(detail?.overview.orEmpty(), color = colors.textSecondary, fontSize = 13.5.sp, lineHeight = 21.sp)
                            }
                        }
                    }
                }

                if (albums.isNotEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }, key = "artist_albums_title") {
                        Text(
                            text = "专辑作品 (${albums.size})",
                            color = colors.textPrimary,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                    items(albums, key = { "${it.source}_${it.id}_${it.title}" }) { album ->
                        val enrichedAlbum = if (album.artist.isBlank()) {
                            album.copy(artist = displayName, artistId = artistId)
                        } else {
                            album
                        }
                        CinematicPanel(
                            padding = 10.dp,
                            cornerRadius = 18.dp,
                            modifier = Modifier.clickable { onOpenAlbum(enrichedAlbum) },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(1f)
                                        .clip(RoundedCornerShape(13.dp))
                                        .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.50f), Color(0xFF281F3D)))),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(36.dp))
                                    if (!album.coverUrl.isNullOrBlank()) {
                                        AsyncImage(
                                            model = album.coverUrl,
                                            contentDescription = album.title,
                                            contentScale = ContentScale.Crop,
                                            modifier = Modifier.fillMaxSize(),
                                        )
                                    }
                                }
                                Text(
                                    text = album.title,
                                    color = colors.textPrimary,
                                    fontSize = 13.5.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (album.year.isNotBlank()) {
                                    Text(album.year, color = colors.textMuted, fontSize = 12.sp)
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
 * 全局搜索媒体库剧集快捷分季/选集直放弹窗：
 * 支持一键切换分季、高亮智能续播集、带整季连播队列立即播放，或进入完整媒体库详情页。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickSeriesEpisodePickerSheet(
    cardItem: MediaCardItem,
    repository: MoviePilotRepository,
    onDismiss: () -> Unit,
    onOpenDetail: () -> Unit,
    onPlayEpisode: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val scope = rememberCoroutineScope()
    val seriesId = cardItem.serverItemId ?: cardItem.mediaId.orEmpty()
    val serverName = cardItem.serverName.orEmpty()

    var seasons by remember(seriesId) { mutableStateOf<List<MediaServerBrowseItemDto>>(emptyList()) }
    var selectedSeasonIdx by remember(seriesId) { mutableIntStateOf(0) }
    var episodes by remember(seriesId) { mutableStateOf<List<MediaServerBrowseItemDto>>(emptyList()) }
    var isLoading by remember(seriesId) { mutableStateOf(true) }
    var resolvingEpId by remember { mutableStateOf<String?>(null) }
    var errorMsg by remember { mutableStateOf<String?>(null) }

    suspend fun loadEpisodesFor(season: MediaServerBrowseItemDto?) {
        isLoading = true
        episodes = repository.fetchMediaServerSeasonEpisodes(
            seriesId = seriesId,
            server = serverName,
            seasonId = season?.itemId,
            seasonNumber = season?.seasonNumber ?: 1,
        )
        isLoading = false
    }

    LaunchedEffect(seriesId, serverName) {
        if (seriesId.isBlank()) {
            isLoading = false
            return@LaunchedEffect
        }
        val loadedSeasons = repository.fetchMediaServerSeasons(seriesId, serverName)
        seasons = loadedSeasons
        val defaultIdx = loadedSeasons.indexOfFirst { (it.seasonNumber ?: 1) > 0 }.takeIf { it >= 0 } ?: 0
        selectedSeasonIdx = defaultIdx
        loadEpisodesFor(loadedSeasons.getOrNull(defaultIdx))
    }

    val smartIdx = remember(episodes) { MoviePilotRepository.smartNextPlayableEpisodeIndex(episodes) ?: 0 }

    fun triggerEpisodePlay(epIndex: Int) {
        val ep = episodes.getOrNull(epIndex) ?: return
        if (resolvingEpId != null) return
        scope.launch {
            resolvingEpId = ep.itemId
            errorMsg = null
            val epServer = ep.server.ifBlank { serverName }
            val manifest = repository.fetchVideoStreamInfo(ep.itemId, epServer.ifBlank { null })
            resolvingEpId = null
            if (manifest != null) {
                val queue = episodes.mapIndexed { i, item ->
                    val num = item.episodeNumber ?: (i + 1)
                    MediaPlaybackRequest(
                        url = "",
                        title = "${cardItem.title} E%02d · ${item.title.ifBlank { "第 $num 集" }}".format(num),
                        subtitle = epServer,
                        artworkUrl = item.thumb ?: item.backdrop ?: cardItem.posterPath,
                        itemId = item.itemId,
                        server = item.server.ifBlank { epServer },
                        resumePositionMs = item.resumePositionMs,
                        queueIndex = i,
                        lazySpec = QueueTrackSpec.MediaServerItem(
                            itemId = item.itemId,
                            server = item.server.ifBlank { epServer },
                        ),
                    )
                }
                val num = ep.episodeNumber ?: (epIndex + 1)
                val activeReq = MediaPlaybackRequest(
                    url = manifest.contentUrl,
                    title = "${cardItem.title} E%02d · ${ep.title.ifBlank { manifest.title }}".format(num),
                    subtitle = epServer,
                    artworkUrl = ep.thumb ?: ep.backdrop ?: cardItem.posterPath,
                    isAudio = false,
                    headers = manifest.headers,
                    itemId = manifest.itemId,
                    server = manifest.server.ifBlank { epServer },
                    mediaSourceId = manifest.mediaSourceId.orEmpty(),
                    resumePositionMs = manifest.resumePositionMs.takeIf { it > 0L } ?: ep.resumePositionMs,
                    subtitles = manifest.subtitles.map {
                        SubtitleTrackItem(it.subtitleId, it.title, it.language, it.url)
                    },
                    queue = queue,
                    queueIndex = epIndex,
                )
                onDismiss()
                onPlayEpisode(activeReq)
            } else {
                errorMsg = "暂无法拉取该集播放流"
            }
        }
    }

    NativeGlassSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = cardItem.title,
                        color = colors.textPrimary,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = listOfNotNull(serverName.ifBlank { null }, "选择分季与剧集直放").joinToString(" · "),
                        color = colors.textSecondary,
                        fontSize = 12.5.sp,
                    )
                }
                NativeAdaptivePill(
                    title = "详情页",
                    selected = false,
                    icon = Icons.Rounded.VideoLibrary,
                    onClick = {
                        onDismiss()
                        onOpenDetail()
                    },
                )
            }

            if (seasons.size > 1) {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    itemsIndexed(seasons) { idx, sea ->
                        val sNum = sea.seasonNumber ?: (idx + 1)
                        NativeAdaptivePill(
                            title = sea.title.ifBlank { "第 $sNum 季" },
                            selected = idx == selectedSeasonIdx,
                            onClick = {
                                if (selectedSeasonIdx != idx) {
                                    selectedSeasonIdx = idx
                                    scope.launch { loadEpisodesFor(sea) }
                                }
                            },
                        )
                    }
                }
            }

            errorMsg?.let { Text(it, color = colors.warning, fontSize = 12.5.sp) }

            if (isLoading) {
                NativeCardListSkeleton(
                    style = SkeletonCardStyle.IconRow,
                    count = 4,
                    contentPadding = PaddingValues(0.dp),
                    scrollable = false,
                )
            } else if (episodes.isEmpty()) {
                Text("未查询到该剧集可播放分集，请进入详情页查看。", color = colors.textSecondary, fontSize = 13.5.sp)
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    itemsIndexed(episodes) { idx, ep ->
                        val epNum = ep.episodeNumber ?: (idx + 1)
                        val recommended = idx == smartIdx
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(15.dp))
                                .background(if (recommended) colors.activeIndicator else colors.surfaceContainerLow)
                                .clickable(enabled = resolvingEpId == null) { triggerEpisodePlay(idx) }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text(
                                text = "E%02d".format(epNum),
                                color = if (recommended) colors.accent else colors.textMuted,
                                fontSize = 12.5.sp,
                                fontWeight = FontWeight.Bold,
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = ep.title.ifBlank { "第 $epNum 集" },
                                    color = colors.textPrimary,
                                    fontSize = 14.sp,
                                    fontWeight = if (recommended) FontWeight.Bold else FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                if (ep.resumePositionMs > 30_000L && !ep.played) {
                                    Text("继续观看", color = colors.accent, fontSize = 11.5.sp)
                                }
                            }
                            if (ep.played) {
                                Icon(Icons.Rounded.Check, contentDescription = "已看", tint = Color(0xFF1F9D55), modifier = Modifier.size(16.dp))
                            }
                            if (resolvingEpId == ep.itemId) {
                                CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                            } else if (recommended) {
                                Icon(Icons.Rounded.GraphicEq, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                            } else {
                                Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(12.dp))
        }
    }
}
