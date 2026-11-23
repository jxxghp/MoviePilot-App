package com.moviepilot.feature.discover

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.BookmarkAdd
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.FolderSpecial
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicGlassSurface
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeBrandDrawable
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativePosterCard
import com.moviepilot.designsystem.NativePrimaryTabBar
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.rustbridge.ContinueWatchingItem
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MediaServerLibraryDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.MusicAlbumDto
import com.moviepilot.rustbridge.SubscribeItemDto
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/** 发现页可编排模块项。 */
data class DiscoverModuleToggle(val id: String, val title: String, val enabled: Boolean)

/**
 * 发现首页（1:1 复刻 iOS 黄金截图 `native-v2-live-discover-phase-1..4.jpg`）：
 * - 全幅无遮挡沉浸主视觉轮播（异步补拉透明片名 Logo、TMDB 中文类型、发行日期与青绿 TheMovieDB 徽章）
 * - 继续观看 16:9 横幅进度卡（真实 Emby/Jellyfin/Plex 观看进度）
 * - 最近入库 / 热门电影 / 热门剧集 / 分类浏览与底部自定义模块编排弹窗
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen(
    repository: MoviePilotRepository,
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenExplore: (String) -> Unit,
    onOpenMusic: () -> Unit,
    onOpenMediaLibrary: (MediaServerLibraryDto) -> Unit = {},
    onOpenSearch: () -> Unit = {},
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val heroHeight = AdaptiveDeviceLayout.discoverHeroHeight()
    val posterWidth = AdaptiveDeviceLayout.discoverPosterWidth()
    val density = LocalDensity.current
    val heroHeightPx = with(density) { heroHeight.toPx().coerceAtLeast(1f) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val localHaze = remember { HazeState() }

    var trending by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var movies by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var tvs by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var continueItems by remember { mutableStateOf<List<ContinueWatchingItem>>(emptyList()) }
    var latestItems by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var mediaLibraries by remember { mutableStateOf<List<MediaServerLibraryDto>>(emptyList()) }
    val heroLogos = remember { mutableStateMapOf<String, String>() }
    var showModulesSheet by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }

    val modules = remember {
        mutableStateListOf(
            DiscoverModuleToggle("continue", "继续观看", true),
            DiscoverModuleToggle("libraries", "我的媒体库", true),
            DiscoverModuleToggle("movies", "热门电影", true),
            DiscoverModuleToggle("tvs", "热门剧集", true),
            DiscoverModuleToggle("latest", "最近入库", true),
            DiscoverModuleToggle("categories", "分类浏览", true),
        )
    }

    suspend fun loadAll() {
        coroutineScope {
            val trendingDef = async { repository.fetchDiscoverTrending(1) }
            val moviesDef = async { repository.fetchExplore("tmdb_movies", 1) }
            val tvsDef = async { repository.fetchExplore("tmdb_tvs", 1) }
            val continueDef = async { repository.fetchContinueWatching() }
            val latestDef = async { repository.fetchMediaServerLatest() }
            val libsDef = async { repository.fetchMediaServerLibraries() }

            val fetchedTrending = trendingDef.await()
            trending = fetchedTrending
            movies = moviesDef.await().ifEmpty { fetchedTrending }
            tvs = tvsDef.await()
            continueItems = continueDef.await()
            latestItems = latestDef.await()
            mediaLibraries = libsDef.await()
            isRefreshing = false

            // 异步并发补拉前 6 条 Hero 的透明片名 Logo（对齐 iOS `hydrateHeroLogos`）
            fetchedTrending.take(6).forEach { hero ->
                launch {
                    val logo = repository.fetchHeroLogo(hero)
                    if (!logo.isNullOrBlank()) {
                        heroLogos[hero.resolvedId] = logo
                    }
                }
            }
        }
    }

    LaunchedEffect(Unit) { loadAll() }

    val heroItems = trending.take(6)
    val pagerState = rememberPagerState(pageCount = { heroItems.size.coerceAtLeast(1) })

    // 1:1 复刻 iOS `NativeDiscoverPage` 滚动物理曲线：
    // 背景固定于滚动层后方，上滚时 0.07x 轻视差 + smoothstep 18dp 渐进柔焦 + 6 段软边溶解 + 淡出；
    // 前景透明 Logo/标题/评分以 1.0x 正常速度随列表上滚，离开首屏后顶部渐进状态栏模糊同步浮现。
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
    val currentHero = heroItems.getOrNull(pagerState.currentPage)

    Box(modifier = Modifier.fillMaxSize()) {
        // 1. 底层固定沉浸 Hero 背景（与滚动正文分离，形成 0.07x 景深视差与渐进柔焦）
        Box(
            modifier = Modifier
                .fillMaxSize()
                .hazeSource(localHaze),
        ) {
            if (colors.isDark) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFF0A0A16).copy(alpha = ((1f - eased * 1.15f).coerceAtLeast(0f)) * 0.52f)),
                )
            }

            if (currentHero != null && progress < 0.99f) {
                val backdropHeight = heroHeight * 1.08f
                val parallaxY = -scrollUpPx.coerceAtMost(heroHeightPx) * 0.07f
                val maskShiftY = -scrollUpPx * 0.88f
                val visibility = (1f - eased * 0.94f).coerceIn(0f, 1f)
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
                            // 6 段动态软边溶解蒙版（随上滚同步上推，丝滑融进流光背景）
                            val h = size.height.coerceAtLeast(1f)
                            val shiftFraction = (maskShiftY / h).coerceIn(-0.95f, 0f)
                            val p1 = (0.44f + shiftFraction).coerceIn(0f, 1f)
                            val p2 = (0.60f + shiftFraction).coerceIn(p1, 1f)
                            val p3 = (0.78f + shiftFraction).coerceIn(p2, 1f)
                            val p4 = (0.90f + shiftFraction).coerceIn(p3, 1f)
                            val p5 = (1.00f + shiftFraction).coerceIn(p4, 1f)
                            drawRect(
                                brush = Brush.verticalGradient(
                                    0.0f to Color.Black,
                                    p1 to Color.Black,
                                    p2 to Color.Black.copy(alpha = 0.86f),
                                    p3 to Color.Black.copy(alpha = 0.42f),
                                    p4 to Color.Black.copy(alpha = 0.10f),
                                    p5 to Color.Transparent,
                                    1.0f to Color.Transparent,
                                ),
                                blendMode = BlendMode.DstIn,
                            )
                        },
                ) {
                    Crossfade(
                        targetState = currentHero.backdropPath ?: currentHero.posterPath,
                        animationSpec = tween(durationMillis = 360),
                        label = "discoverHeroBackdrop",
                    ) { backdropUrl ->
                        if (!backdropUrl.isNullOrBlank()) {
                            AsyncImage(
                                model = backdropUrl,
                                contentDescription = currentHero.title,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .fillMaxSize()
                                    .blur((eased * 18f).dp),
                            )
                        } else {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(Brush.verticalGradient(listOf(Color(0xFF4B3D6B), Color(0xFF2F2342), Color(0xFF241D34)))),
                            )
                        }
                    }
                    // 底部多段平滑融底：首屏顶部保持 100% 清透无遮挡
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    0.0f to Color.Transparent,
                                    0.36f to Color.Transparent,
                                    0.64f to fadeBase.copy(alpha = (if (colors.isDark) 0.45f else 0.56f) * (1f - eased * 0.4f)),
                                    0.86f to fadeBase.copy(alpha = if (colors.isDark) 0.86f else 0.92f),
                                    1.0f to fadeBase,
                                ),
                            ),
                    )
                    if (eased > 0.01f) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(
                                    if (colors.isDark) Color.Black.copy(alpha = eased * 0.22f)
                                    else fadeBase.copy(alpha = eased * 0.32f),
                                ),
                        )
                    }
                }
            }

            // 2. 前景滚动内容层（支持 Android 原生下拉刷新 PullToRefreshBox）
            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { loadAll() }
                },
                modifier = Modifier.fillMaxSize(),
            ) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 132.dp),
                    verticalArrangement = Arrangement.spacedBy(22.dp),
                ) {
                    // 1. 前景主视觉轮播（透明背景，Logo 与信息随正文以 1.0x 自然上滚）
                    if (heroItems.isNotEmpty()) {
                        item {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(heroHeight),
                            ) {
                                HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { idx ->
                                    val item = heroItems[idx]
                                    val logoUrl = item.logoPath ?: heroLogos[item.resolvedId]
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .clickable { onOpenMedia(item) },
                                    ) {
                                        Column(
                                            modifier = Modifier
                                                .align(Alignment.BottomCenter)
                                                .fillMaxWidth()
                                                .padding(horizontal = margin, vertical = 22.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                        ) {
                                            var logoReady by remember(logoUrl) { mutableStateOf(false) }
                                            Box(
                                                modifier = Modifier.fillMaxWidth(),
                                                contentAlignment = Alignment.Center,
                                            ) {
                                                if (!logoReady) {
                                                    Text(
                                                        text = item.title,
                                                        color = if (colors.isDark) Color.White else colors.textPrimary,
                                                        fontSize = 26.sp,
                                                        fontWeight = FontWeight.ExtraBold,
                                                        textAlign = TextAlign.Center,
                                                        maxLines = 2,
                                                    )
                                                }
                                                if (!logoUrl.isNullOrBlank()) {
                                                    AsyncImage(
                                                        model = logoUrl,
                                                        contentDescription = item.title,
                                                        contentScale = ContentScale.Fit,
                                                        onSuccess = { logoReady = true },
                                                        modifier = Modifier
                                                            .fillMaxWidth(0.72f)
                                                            .height(66.dp),
                                                    )
                                                }
                                            }
                                            Spacer(Modifier.height(8.dp))
                                            Text(
                                                text = listOfNotNull(
                                                    item.genres.take(3).joinToString(" ").ifBlank { item.type },
                                                    item.releaseDate?.takeIf { it.isNotBlank() } ?: item.year.ifBlank { null },
                                                ).joinToString(" · "),
                                                color = if (colors.isDark) Color.White.copy(alpha = 0.90f) else colors.textPrimary.copy(alpha = 0.85f),
                                                fontSize = 13.sp,
                                                fontWeight = FontWeight.Medium,
                                            )
                                            if (item.overview.isNotBlank()) {
                                                Spacer(Modifier.height(6.dp))
                                                Text(
                                                    text = item.overview,
                                                    color = if (colors.isDark) Color.White.copy(alpha = 0.78f) else colors.textSecondary,
                                                    fontSize = 12.sp,
                                                    maxLines = 2,
                                                    overflow = TextOverflow.Ellipsis,
                                                    textAlign = TextAlign.Center,
                                                    lineHeight = 18.sp,
                                                )
                                            }
                                            Spacer(Modifier.height(12.dp))
                                            Row(
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .clip(RoundedCornerShape(5.dp))
                                                        .background(Color(0xFF42C997))
                                                        .padding(horizontal = 7.dp, vertical = 2.dp),
                                                ) {
                                                    Text(
                                                        text = if (item.source == "douban") "豆瓣" else "TheMovieDB",
                                                        color = Color(0xFF0A1A14),
                                                        fontSize = 11.sp,
                                                        fontWeight = FontWeight.ExtraBold,
                                                    )
                                                }
                                                if (item.voteAverage > 0.0) {
                                                    Text(
                                                        text = String.format("%.1f", item.voteAverage),
                                                        color = if (colors.isDark) Color.White else colors.textPrimary,
                                                        fontSize = 13.sp,
                                                        fontWeight = FontWeight.Bold,
                                                    )
                                                    Icon(
                                                        Icons.Rounded.Star,
                                                        contentDescription = null,
                                                        tint = Color(0xFFFFC845),
                                                        modifier = Modifier.size(14.dp),
                                                    )
                                                }
                                                Text(
                                                    text = "查看详情",
                                                    color = if (colors.isDark) Color.White.copy(alpha = 0.92f) else colors.textPrimary,
                                                    fontSize = 13.sp,
                                                    fontWeight = FontWeight.SemiBold,
                                                )
                                            }
                                        }
                                    }
                                }

                                // 轮播指示圆点
                                Row(
                                    modifier = Modifier
                                        .align(Alignment.BottomCenter)
                                        .padding(bottom = 4.dp),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    repeat(heroItems.size) { i ->
                                        Box(
                                            modifier = Modifier
                                                .size(if (pagerState.currentPage == i) 7.dp else 5.dp)
                                                .clip(CircleShape)
                                                .background(
                                                    if (pagerState.currentPage == i) {
                                                        if (colors.isDark) Color.White else colors.textPrimary
                                                    } else {
                                                        if (colors.isDark) Color.White.copy(alpha = 0.35f) else colors.textMuted.copy(alpha = 0.35f)
                                                    },
                                                ),
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // 2. 继续观看（16:9 横幅进度卡，直连 `/api/v1/mediaserver/stream-info` 续播）
                    if (modules.firstOrNull { it.id == "continue" }?.enabled == true && continueItems.isNotEmpty()) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                NativeSectionHeader(
                                    title = "继续观看",
                                    modifier = Modifier.padding(horizontal = margin),
                                )
                                LazyRow(
                                    contentPadding = PaddingValues(horizontal = margin),
                                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                                ) {
                                    items(continueItems) { cw ->
                                        Column(
                                            modifier = Modifier
                                                .width(238.dp)
                                                .clickable {
                                                    scope.launch {
                                                        val manifest = cw.id.takeIf { it.isNotBlank() }?.let { id ->
                                                            repository.fetchVideoStreamInfo(id, cw.server)
                                                        }
                                                        if (manifest != null) {
                                                            onPlayMedia(
                                                                MediaPlaybackRequest(
                                                                    url = manifest.contentUrl,
                                                                    title = manifest.title.ifBlank { cw.title },
                                                                    subtitle = cw.subtitle,
                                                                    artworkUrl = cw.image,
                                                                    isAudio = manifest.mediaType == "audio",
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
                                                            onOpenMedia(
                                                                MediaCardItem(
                                                                    title = cw.title,
                                                                    posterPath = cw.image,
                                                                    backdropPath = cw.image,
                                                                    inLibrary = true,
                                                                ),
                                                            )
                                                        }
                                                    }
                                                },
                                        ) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .aspectRatio(16f / 9f)
                                            .clip(RoundedCornerShape(15.dp))
                                            .background(Brush.linearGradient(listOf(Color(0xFF473766), Color(0xFF282038))))
                                            .border(0.7.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(15.dp)),
                                    ) {
                                        if (!cw.image.isNullOrBlank()) {
                                            AsyncImage(
                                                model = cw.image,
                                                contentDescription = cw.title,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize(),
                                            )
                                        }
                                        Box(
                                            modifier = Modifier
                                                .fillMaxSize()
                                                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f)))),
                                        )
                                        Column(
                                            modifier = Modifier
                                                .align(Alignment.BottomStart)
                                                .fillMaxWidth()
                                                .padding(10.dp),
                                        ) {
                                            Text("看到 ${cw.percent}%", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                                            Spacer(Modifier.height(4.dp))
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .height(3.5.dp)
                                                    .clip(CircleShape)
                                                    .background(Color.White.copy(alpha = 0.25f)),
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .fillMaxWidth((cw.percent / 100f).coerceIn(0.05f, 1f))
                                                        .height(3.5.dp)
                                                        .clip(CircleShape)
                                                        .background(Color.White),
                                                )
                                            }
                                        }
                                    }
                                    Spacer(Modifier.height(7.dp))
                                    Text(cw.title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    if (cw.subtitle.isNotBlank()) {
                                        Text(cw.subtitle, color = colors.textMuted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 2.5 我的媒体库（真实 Emby / Jellyfin / Plex 媒体库横栏，点击直达原生媒体库浏览页）
            if (modules.firstOrNull { it.id == "libraries" }?.enabled == true && mediaLibraries.isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        NativeSectionHeader(
                            title = "我的媒体库",
                            subtitle = mediaLibraries.firstOrNull()?.server,
                            onClickMore = { onOpenMediaLibrary(mediaLibraries.first()) },
                            modifier = Modifier.padding(horizontal = margin),
                        )
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = margin),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(mediaLibraries, key = { "${it.server}_${it.id}" }) { lib ->
                                Column(
                                    modifier = Modifier
                                        .width(174.dp)
                                        .clickable { onOpenMediaLibrary(lib) },
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .aspectRatio(16f / 9f)
                                            .clip(RoundedCornerShape(15.dp))
                                            .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.34f), Color(0xFF282138))))
                                            .border(0.7.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(15.dp)),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        if (!lib.imageUrl.isNullOrBlank()) {
                                            AsyncImage(
                                                model = lib.imageUrl,
                                                contentDescription = lib.name,
                                                contentScale = ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize(),
                                            )
                                            Box(
                                                modifier = Modifier
                                                    .fillMaxSize()
                                                    .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.12f), Color.Black.copy(alpha = 0.68f)))),
                                            )
                                        } else {
                                            Icon(
                                                Icons.Rounded.FolderSpecial,
                                                contentDescription = null,
                                                tint = Color.White.copy(alpha = 0.68f),
                                                modifier = Modifier.size(30.dp),
                                            )
                                        }
                                        Column(
                                            modifier = Modifier
                                                .align(Alignment.BottomStart)
                                                .padding(10.dp),
                                        ) {
                                            Text(lib.name, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                            val meta = listOfNotNull(
                                                lib.server.ifBlank { null },
                                                lib.itemCount?.let { "$it 项" },
                                            ).joinToString(" · ")
                                            if (meta.isNotBlank()) {
                                                Text(meta, color = Color.White.copy(alpha = 0.78f), fontSize = 11.sp, maxLines = 1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 3. 热门电影横向栏
            if (modules.firstOrNull { it.id == "movies" }?.enabled == true && movies.isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        NativeSectionHeader(
                            title = "热门电影",
                            onClickMore = { onOpenExplore("tmdb_movies") },
                            modifier = Modifier.padding(horizontal = margin),
                        )
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = margin),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(movies) { item ->
                                NativePosterCard(
                                    title = item.title,
                                    year = item.year,
                                    posterUrl = item.posterPath,
                                    voteAverage = item.voteAverage,
                                    inLibrary = item.inLibrary,
                                    onClick = { onOpenMedia(item) },
                                    modifier = Modifier.width(posterWidth),
                                )
                            }
                        }
                    }
                }
            }

            // 4. 热门剧集横向栏
            if (modules.firstOrNull { it.id == "tvs" }?.enabled == true && tvs.isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        NativeSectionHeader(
                            title = "热门剧集",
                            onClickMore = { onOpenExplore("tmdb_tvs") },
                            modifier = Modifier.padding(horizontal = margin),
                        )
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = margin),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(tvs) { item ->
                                NativePosterCard(
                                    title = item.title,
                                    year = item.year,
                                    posterUrl = item.posterPath,
                                    voteAverage = item.voteAverage,
                                    inLibrary = item.inLibrary,
                                    onClick = { onOpenMedia(item) },
                                    modifier = Modifier.width(posterWidth),
                                )
                            }
                        }
                    }
                }
            }

            // 5. 最近入库横向栏（来自媒体服务器 Emby/Jellyfin/Plex）
            if (modules.firstOrNull { it.id == "latest" }?.enabled == true && latestItems.isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        NativeSectionHeader(
                            title = "最近入库",
                            modifier = Modifier.padding(horizontal = margin),
                        )
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = margin),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(latestItems) { item ->
                                NativePosterCard(
                                    title = item.title,
                                    year = item.year,
                                    posterUrl = item.posterPath,
                                    voteAverage = 0.0,
                                    inLibrary = true,
                                    onClick = { onOpenMedia(item) },
                                    modifier = Modifier.width(posterWidth),
                                )
                            }
                        }
                    }
                }
            }

            // 6. 分类浏览与音乐发现入口
            if (modules.firstOrNull { it.id == "categories" }?.enabled == true) {
                item {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.padding(horizontal = margin),
                    ) {
                        NativeSectionHeader(title = "分类浏览")
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CategoryTile("豆瓣高分电影", "logo_douban", Modifier.weight(1f)) { onOpenExplore("douban_movies") }
                            CategoryTile("Bangumi 番剧", "logo_bangumi", Modifier.weight(1f)) { onOpenExplore("bangumi") }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            CategoryTile("TMDB 剧集库", "logo_tmdb", Modifier.weight(1f)) { onOpenExplore("tmdb_tvs") }
                            CategoryTile("音乐发现", "logo_musicbrainz", Modifier.weight(1f)) { onOpenExplore("music") }
                        }
                    }
                }
            }

                    // 7. 底部自定义发现模块入口（对齐 iOS discover-phase-4，不破坏顶部 Hero 构图）
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = margin, vertical = 4.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            CinematicGlassSurface(
                                shape = CircleShape,
                                blurRadiusDp = 18.dp,
                                modifier = Modifier.clickable { showModulesSheet = true },
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Icon(Icons.Rounded.Tune, contentDescription = null, tint = colors.accent, modifier = Modifier.size(16.dp))
                                    Text("自定义发现模块", color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 顶部状态栏渐进模糊（首屏 scroll=0 时 0% 透明保持海报无遮挡，上滚后平滑浮现防止内容与状态栏重叠）
        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = eased,
            extraHeight = 40.dp,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )

        // Android 顶栏右上角搜索入口（悬浮半透玻璃圆钮，既不遮挡全幅海报又保持 1 键可达）
        com.moviepilot.designsystem.CinematicCircleButton(
            icon = Icons.Rounded.Search,
            contentDescription = "全局搜索",
            onClick = onOpenSearch,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(top = 8.dp, end = 16.dp),
        )
    }

    if (showModulesSheet) {
        NativeGlassSheet(onDismissRequest = { showModulesSheet = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text("发现模块编排", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Text("控制发现首页各模块显隐状态", color = colors.textSecondary, fontSize = 13.sp)
                modules.forEachIndexed { idx, mod ->
                    CinematicPanel(padding = 12.dp) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Text(mod.title, color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                            Switch(
                                checked = mod.enabled,
                                onCheckedChange = { modules[idx] = mod.copy(enabled = it) },
                                colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                            )
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun CategoryTile(
    title: String,
    logo: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(
        padding = 14.dp,
        cornerRadius = 20.dp,
        modifier = modifier.clickable(onClick = onClick),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            NativeBrandDrawable(drawableName = logo, size = 34.dp, cornerRadius = 9.dp)
            Text(title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** 探索数据源卡定义。 */
private data class ExploreSourceTab(val id: String, val brand: String, val sub: String, val logo: String)

/**
 * 探索片库页面（1:1 复刻 iOS `native-v2-live-explore.jpg`、`explore-douban.jpg`、`music.jpg`）：
 * 顶部 6 张品牌来源横滑卡（TMDB 电影/剧集、豆瓣电影/剧集、Bangumi 番剧、音乐榜单与专辑）
 * + 动态源筛选胶囊 + 自动无限分页海报网格 + 音乐专辑详情与播放弹窗。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExploreScreen(
    repository: MoviePilotRepository,
    initialSource: String = "tmdb_movies",
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenSearch: () -> Unit = {},
    onPlayAudio: (MediaPlaybackRequest) -> Unit = {},
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val columns = AdaptiveDeviceLayout.posterGridColumns()
    val musicColumns = AdaptiveDeviceLayout.squareGridColumns()
    val scope = rememberCoroutineScope()

    val sources = remember {
        listOf(
            ExploreSourceTab("tmdb_movies", "TheMovieDB", "电影", "logo_tmdb"),
            ExploreSourceTab("tmdb_tvs", "TheMovieDB", "剧集", "logo_tmdb"),
            ExploreSourceTab("douban_movies", "豆瓣", "电影", "logo_douban"),
            ExploreSourceTab("douban_tvs", "豆瓣", "剧集", "logo_douban"),
            ExploreSourceTab("bangumi", "Bangumi", "番剧", "logo_bangumi"),
            ExploreSourceTab("music", "音乐", "榜单与专辑", "logo_musicbrainz"),
        )
    }
    val tmdbSorts = listOf("热门", "最新", "高分")
    val tmdbGenres = listOf("全部类型", "动作", "科幻", "动画", "喜剧", "剧情", "悬疑", "犯罪", "奇幻")
    val tmdbLangs = listOf("全部语言", "华语", "英语", "日语", "韩语")
    val doubanTags = listOf("全部", "华语", "欧美", "韩国", "日本", "动作", "喜剧", "科幻", "悬疑")
    val musicFeeds = listOf("douban" to "豆瓣音乐", "weekly" to "本周榜单", "popular" to "热门专辑", "latest" to "近期新发")

    var activeSource by remember(initialSource) { mutableStateOf(initialSource) }
    var activeSort by remember { mutableStateOf("热门") }
    var activeGenre by remember { mutableStateOf("全部类型") }
    var activeLang by remember { mutableStateOf("全部语言") }
    var activeDoubanTag by remember { mutableStateOf("全部") }
    var activeMusicFeed by remember { mutableStateOf("douban") }

    var page by remember { mutableIntStateOf(1) }
    var isLoading by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    var canLoadMore by remember { mutableStateOf(true) }
    var items by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var musicAlbums by remember { mutableStateOf<List<MusicAlbumDto>>(emptyList()) }
    var selectedAlbum by remember { mutableStateOf<MusicAlbumDto?>(null) }
    val localHaze = remember { HazeState() }

    suspend fun reloadCurrent(showMainLoader: Boolean = true) {
        if (showMainLoader) isLoading = true
        page = 1
        canLoadMore = true
        if (activeSource == "music") {
            musicAlbums = repository.fetchMusicFeed(activeMusicFeed, 1)
        } else {
            val fetched = repository.fetchExplore(
                source = activeSource,
                page = 1,
                genre = activeGenre,
                sort = activeSort,
                language = activeLang,
                doubanTag = activeDoubanTag,
            )
            items = fetched
            canLoadMore = fetched.size >= 15
        }
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(activeSource, activeSort, activeGenre, activeLang, activeDoubanTag, activeMusicFeed) {
        reloadCurrent(showMainLoader = true)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize().hazeSource(localHaze)) {
            NativeGlassTopBar(
                title = "探索",
                showTopBlur = false,
                trailing = {
                    IconButton(onClick = onOpenSearch, modifier = Modifier.size(48.dp)) {
                        Icon(Icons.Rounded.Search, contentDescription = "全局搜索", tint = colors.textPrimary, modifier = Modifier.size(24.dp))
                    }
                },
            )

        // 6 大品牌来源横向小卡片
        LazyRow(
            contentPadding = PaddingValues(horizontal = margin),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(sources) { src ->
                val selected = src.id == activeSource
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(18.dp))
                        .background(if (selected) colors.accent.copy(alpha = 0.24f) else colors.chipFill)
                        .border(
                            width = if (selected) 1.2.dp else 0.7.dp,
                            color = if (selected) colors.accent else colors.chipBorder,
                            shape = RoundedCornerShape(18.dp),
                        )
                        .clickable { activeSource = src.id }
                        .padding(horizontal = 12.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    NativeBrandDrawable(drawableName = src.logo, size = 30.dp, cornerRadius = 8.dp)
                    Column {
                        Text(src.brand, color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        Text(src.sub, color = if (selected) colors.accent else colors.textSecondary, fontSize = 11.sp)
                    }
                }
            }
        }

        Spacer(Modifier.height(12.dp))

        if (activeSource == "music") {
            // Material Design 3 音乐榜单页签栏
            val musicIdx = musicFeeds.indexOfFirst { it.first == activeMusicFeed }.coerceAtLeast(0)
            NativePrimaryTabBar(
                tabs = musicFeeds.map { it.second },
                selectedIndex = musicIdx,
                onSelect = { idx -> activeMusicFeed = musicFeeds[idx].first },
                scrollable = musicFeeds.size > 4,
            )
            Spacer(Modifier.height(10.dp))
            if (isLoading && musicAlbums.isEmpty()) {
                Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.accent)
                }
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(musicColumns),
                    contentPadding = PaddingValues(start = margin, end = margin, top = 4.dp, bottom = 128.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    items(musicAlbums, key = { it.id + it.title }) { album ->
                        CinematicPanel(
                            padding = 10.dp,
                            cornerRadius = 20.dp,
                            modifier = Modifier.clickable { selectedAlbum = album },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(1f)
                                        .clip(RoundedCornerShape(14.dp))
                                        .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.55f), Color(0xFF281F3D)))),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = Color.White.copy(alpha = 0.7f), modifier = Modifier.size(38.dp))
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
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(
                                        text = album.artist.ifBlank { "精选专辑" },
                                        color = colors.textSecondary,
                                        fontSize = 12.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f),
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
        } else {
            // 影视筛选胶囊栏（TMDB / 豆瓣 / Bangumi 各自适配）
            LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(tmdbSorts) { s -> NativeAdaptivePill(s, selected = s == activeSort, onClick = { activeSort = s }) }
            }
            Spacer(Modifier.height(8.dp))
            if (activeSource.startsWith("tmdb")) {
                LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(tmdbGenres) { g -> NativeAdaptivePill(g, selected = g == activeGenre, onClick = { activeGenre = g }) }
                }
                Spacer(Modifier.height(8.dp))
                LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(tmdbLangs) { l -> NativeAdaptivePill(l, selected = l == activeLang, onClick = { activeLang = l }) }
                }
            } else if (activeSource.startsWith("douban")) {
                LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(doubanTags) { tag -> NativeAdaptivePill(tag, selected = tag == activeDoubanTag, onClick = { activeDoubanTag = tag }) }
                }
            }

            Spacer(Modifier.height(12.dp))

            // 响应式 3~6 列自动分页海报网格 + 原生下拉刷新
            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { reloadCurrent(showMainLoader = false) }
                },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(columns),
                    contentPadding = PaddingValues(start = margin, end = margin, top = 4.dp, bottom = 128.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    itemsIndexed(items, key = { idx, item -> "${item.resolvedId}-$idx" }) { idx, item ->
                        if (idx >= items.size - 4 && canLoadMore && !isLoading) {
                            LaunchedEffect(page) {
                                isLoading = true
                                val nextPage = page + 1
                                val more = repository.fetchExplore(
                                    source = activeSource,
                                    page = nextPage,
                                    genre = activeGenre,
                                    sort = activeSort,
                                    language = activeLang,
                                    doubanTag = activeDoubanTag,
                                )
                                if (more.isNotEmpty()) {
                                    val seen = items.map { it.resolvedId }.toHashSet()
                                    items = items + more.filter { seen.add(it.resolvedId) }
                                    page = nextPage
                                } else {
                                    canLoadMore = false
                                }
                                isLoading = false
                            }
                        }
                        NativePosterCard(
                            title = item.title,
                            year = item.year,
                            posterUrl = item.posterPath,
                            voteAverage = item.voteAverage,
                            inLibrary = item.inLibrary,
                            onClick = { onOpenMedia(item) },
                        )
                    }
                }
            }
        }
        }
        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = 0.85f,
            extraHeight = 14.dp,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }

    // 音乐专辑详情与订阅/试听弹窗（对齐 iOS `native-v2-live-music-album.jpg`）
    selectedAlbum?.let { album ->
        var subMsg by remember(album.id) { mutableStateOf<String?>(null) }
        NativeGlassSheet(onDismissRequest = { selectedAlbum = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    modifier = Modifier
                        .size(188.dp)
                        .clip(RoundedCornerShape(22.dp))
                        .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.55f), Color(0xFF281F3D)))),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = Color.White, modifier = Modifier.size(56.dp))
                    if (!album.coverUrl.isNullOrBlank()) {
                        AsyncImage(model = album.coverUrl, contentDescription = album.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    }
                }
                Text(album.title, color = colors.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, textAlign = TextAlign.Center)
                Text(
                    listOfNotNull(album.artist.ifBlank { null }, album.year.ifBlank { null }).joinToString(" · "),
                    color = colors.textSecondary,
                    fontSize = 14.sp,
                )
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = {
                            scope.launch {
                                val ok = repository.createOrUpdateSubscription(
                                    SubscribeItemDto(name = album.title, year = album.year, type = "音乐", mediaSource = album.source, mediaId = album.id),
                                )
                                subMsg = if (ok) "已添加音乐专辑订阅" else "订阅请求已提交"
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(Icons.Rounded.BookmarkAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("订阅专辑", fontWeight = FontWeight.Bold)
                    }
                    Button(
                        onClick = {
                            scope.launch {
                                val manifest = repository.fetchMusicStreamInfo(
                                    title = album.title,
                                    artist = album.artist.ifBlank { null },
                                    album = album.title,
                                )
                                if (manifest != null) {
                                    val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                    selectedAlbum = null
                                    onPlayAudio(
                                        MediaPlaybackRequest(
                                            url = manifest.contentUrl,
                                            title = manifest.title.ifBlank { album.title },
                                            subtitle = album.artist,
                                            artworkUrl = album.coverUrl,
                                            isAudio = true,
                                            lyricsLrc = lrc,
                                            headers = manifest.headers,
                                            itemId = manifest.itemId,
                                            server = manifest.server,
                                        ),
                                    )
                                } else {
                                    subMsg = "当前媒体服务器未匹配到该专辑可播放音轨"
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = Color.White),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("媒体库直放", fontWeight = FontWeight.Bold)
                    }
                }
                subMsg?.let { Text(it, color = colors.success, fontSize = 13.sp) }
                if (album.overview.isNotBlank()) {
                    CinematicPanel(padding = 14.dp, showsShadow = false) {
                        Text(album.overview, color = colors.textSecondary, fontSize = 13.sp, lineHeight = 20.sp)
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

/**
 * 全局搜索页（1:1 复刻 iOS `native-v2-live-search.jpg`）：
 * 顶部玻璃搜索框 + 5 类分类胶囊（媒体 / 媒体库 / 人物 / 音乐 / 合集）+ 热门快捷词 + 严格“仅媒体库直放”策略。
 */
@Composable
fun GlobalSearchScreen(
    repository: MoviePilotRepository,
    initialQuery: String = "",
    initialKind: String = "media",
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenPerson: (com.moviepilot.rustbridge.MediaPersonDto) -> Unit = {},
    onPlayLibraryItem: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val columns = AdaptiveDeviceLayout.posterGridColumns()
    val scope = rememberCoroutineScope()

    var query by remember { mutableStateOf(initialQuery) }
    var kind by remember { mutableStateOf(initialKind) }
    var results by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }
    var playError by remember { mutableStateOf<String?>(null) }

    val kinds = listOf(
        "media" to "媒体",
        "library" to "媒体库",
        "person" to "人物",
        "music" to "音乐",
        "collection" to "合集",
    )
    val quickTags = listOf("奥德赛", "钢铁侠", "超感神探", "庆余年", "星际穿越")

    LaunchedEffect(query, kind) {
        if (query.isNotBlank()) {
            isSearching = true
            results = repository.searchMedia(query, kind, 1)
            isSearching = false
        } else {
            results = emptyList()
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "全局搜索", onBack = onBack)

        CinematicPanel(padding = 12.dp, cornerRadius = 22.dp, modifier = Modifier.padding(horizontal = margin)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textSecondary)
                Box(modifier = Modifier.weight(1f)) {
                    if (query.isEmpty()) Text("搜索电影、剧集、媒体库、人物或音乐...", color = colors.textMuted, fontSize = 15.sp)
                    BasicTextField(
                        value = query,
                        onValueChange = { query = it },
                        singleLine = true,
                        textStyle = TextStyle(color = colors.textPrimary, fontSize = 15.sp),
                        cursorBrush = SolidColor(colors.accent),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                if (query.isNotEmpty()) {
                    IconButton(onClick = { query = "" }, modifier = Modifier.size(24.dp)) {
                        Icon(Icons.Rounded.Close, contentDescription = "清除", tint = colors.textMuted, modifier = Modifier.size(16.dp))
                    }
                }
            }
        }

        Spacer(Modifier.height(6.dp))
        val kindIdx = kinds.indexOfFirst { it.first == kind }.coerceAtLeast(0)
        NativePrimaryTabBar(
            tabs = kinds.map { it.second },
            selectedIndex = kindIdx,
            onSelect = { idx -> kind = kinds[idx].first },
            scrollable = kinds.size > 4,
        )

        Spacer(Modifier.height(12.dp))
        if (isSearching) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.accent)
            }
        } else if (results.isEmpty()) {
            Column(
                modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = margin),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted.copy(alpha = 0.55f), modifier = Modifier.size(44.dp))
                Spacer(Modifier.height(10.dp))
                Text(
                    text = if (query.isBlank()) "输入片名、演员或关键词开始搜索" else "未找到与「$query」匹配的内容",
                    color = colors.textMuted,
                    fontSize = 14.sp,
                )
                if (query.isBlank()) {
                    Spacer(Modifier.height(18.dp))
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(quickTags) { kw ->
                            NativeAdaptivePill(kw, selected = false, onClick = { query = kw })
                        }
                    }
                }
            }
        } else if (kind == "person") {
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns),
                contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(results) { item ->
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.clickable {
                            onOpenPerson(
                                com.moviepilot.rustbridge.MediaPersonDto(
                                    id = item.mediaId ?: item.tmdbId?.toString() ?: item.resolvedId,
                                    name = item.title,
                                    profilePath = item.posterPath,
                                    source = item.source,
                                ),
                            )
                        },
                    ) {
                        Box(
                            modifier = Modifier
                                .size(86.dp)
                                .clip(CircleShape)
                                .background(colors.chipFill)
                                .border(0.8.dp, colors.chipBorder, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Rounded.Person, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(34.dp))
                            if (!item.posterPath.isNullOrBlank()) {
                                AsyncImage(model = item.posterPath, contentDescription = item.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                            }
                        }
                        Spacer(Modifier.height(6.dp))
                        Text(item.title, color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns),
                contentPadding = PaddingValues(start = margin, end = margin, bottom = 128.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.weight(1f),
            ) {
                items(results) { item ->
                    NativePosterCard(
                        title = item.title,
                        year = item.year,
                        posterUrl = item.posterPath,
                        voteAverage = item.voteAverage,
                        inLibrary = item.inLibrary || kind == "library",
                        onClick = {
                            if (kind == "library") {
                                scope.launch {
                                    playError = null
                                    val itemId = item.mediaId ?: item.tmdbId?.toString().orEmpty()
                                    val manifest = if (itemId.isNotBlank()) repository.fetchVideoStreamInfo(itemId, null) else null
                                    if (manifest != null) {
                                        val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                        onPlayLibraryItem(
                                            MediaPlaybackRequest(
                                                url = manifest.contentUrl,
                                                title = manifest.title.ifBlank { item.title },
                                                artworkUrl = item.posterPath,
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
                                        onOpenMedia(item)
                                    }
                                }
                            } else {
                                onOpenMedia(item)
                            }
                        },
                    )
                }
            }
        }
    }
}

/** 独立音乐发现入口（与 Explore 内音乐 Tab 共享数据源，支持深链直达）。 */
@Composable
fun MusicDiscoveryScreen(
    onBack: () -> Unit,
    onPlayAudio: (MediaPlaybackRequest) -> Unit,
    repository: MoviePilotRepository? = null,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val cols = AdaptiveDeviceLayout.squareGridColumns()
    val scope = rememberCoroutineScope()
    var albums by remember { mutableStateOf<List<MusicAlbumDto>>(emptyList()) }
    var tip by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(repository) {
        if (repository != null) {
            albums = repository.fetchMusicFeed("douban", 1)
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "音乐发现", onBack = onBack)
        tip?.let { msg ->
            Text(msg, color = colors.warning, fontSize = 12.sp, modifier = Modifier.padding(horizontal = margin, vertical = 4.dp))
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(cols),
            contentPadding = PaddingValues(start = margin, end = margin, top = 8.dp, bottom = 128.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            items(albums) { album ->
                CinematicPanel(
                    padding = 12.dp,
                    cornerRadius = 18.dp,
                    modifier = Modifier.clickable {
                        scope.launch {
                            tip = null
                            val manifest = repository?.fetchMusicStreamInfo(album.title, album.artist.ifBlank { null }, album.title)
                            if (manifest != null) {
                                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                onPlayAudio(
                                    MediaPlaybackRequest(
                                        url = manifest.contentUrl,
                                        title = manifest.title.ifBlank { album.title },
                                        subtitle = album.artist,
                                        artworkUrl = album.coverUrl,
                                        isAudio = true,
                                        lyricsLrc = lrc,
                                        headers = manifest.headers,
                                        itemId = manifest.itemId,
                                        server = manifest.server,
                                    ),
                                )
                            } else {
                                tip = "未在媒体服务器中匹配到「${album.title}」的音频文件"
                            }
                        }
                    },
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .aspectRatio(1f)
                                .clip(RoundedCornerShape(14.dp))
                                .background(Brush.linearGradient(listOf(colors.accent, colors.pink.copy(alpha = 0.7f)))),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = Color.White, modifier = Modifier.size(44.dp))
                            if (!album.coverUrl.isNullOrBlank()) {
                                AsyncImage(model = album.coverUrl, contentDescription = album.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                            }
                        }
                        Text(album.title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOfNotNull(album.artist.ifBlank { null }, album.year.ifBlank { null }).joinToString(" · "), color = colors.textSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}
