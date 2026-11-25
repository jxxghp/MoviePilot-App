package com.moviepilot.feature.discover

import android.content.Context
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
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
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.BookmarkAdd
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.FolderSpecial
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.runtime.saveable.rememberSaveable
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
import androidx.compose.ui.platform.LocalContext
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
import com.moviepilot.designsystem.ExpressiveHeaderActionButton
import com.moviepilot.designsystem.ExpressiveMixCollageHeader
import com.moviepilot.designsystem.ExpressiveMixCollageHeaderSkeleton
import com.moviepilot.designsystem.ExpressivePillTabRow
import com.moviepilot.designsystem.ExpressiveTintedScaffold
import com.moviepilot.designsystem.LocalBottomOverlayInset
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeBrandDrawable
import com.moviepilot.designsystem.NativeDiscoverSkeleton
import com.moviepilot.designsystem.NativeEntityLogo
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativePersonGridSkeleton
import com.moviepilot.designsystem.NativePosterCard
import com.moviepilot.designsystem.NativePosterGridSkeleton
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.designsystem.NativeTopStatusBarProgressiveBlur
import com.moviepilot.designsystem.ProvideSkeletonShimmer
import com.moviepilot.designsystem.nativePosterGridSkeletonItems
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.media.QueueTrackSpec
import com.moviepilot.media.SubtitleTrackItem
import com.moviepilot.rustbridge.ContinueWatchingItem
import com.moviepilot.rustbridge.DiscoverSessionSnapshot
import com.moviepilot.rustbridge.ExploreSessionSnapshot
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

/** 发现页可编排模块项（1:1 对齐 iOS 10 大发现模块）。 */
data class DiscoverModuleToggle(val id: String, val title: String, val enabled: Boolean)

private fun defaultDiscoverModules(): List<DiscoverModuleToggle> = listOf(
    DiscoverModuleToggle("continue", "继续观看", true),
    DiscoverModuleToggle("movies", "热门电影", true),
    DiscoverModuleToggle("tvs", "热门剧集", true),
    DiscoverModuleToggle("trending", "本周趋势", true),
    DiscoverModuleToggle("douban_music", "热门音乐", true),
    DiscoverModuleToggle("douban_showing", "豆瓣热映", false),
    DiscoverModuleToggle("douban_top250", "豆瓣 Top250", false),
    DiscoverModuleToggle("latest", "最新入库", true),
    DiscoverModuleToggle("libraries", "我的媒体库", true),
    DiscoverModuleToggle("categories", "分类浏览", true),
)

private fun loadPersistedDiscoverModules(context: Context): List<DiscoverModuleToggle> {
    val defaults = defaultDiscoverModules()
    val raw = context.getSharedPreferences("mp_discover_modules_v3", Context.MODE_PRIVATE)
        .getString("modules_spec", null)
        ?.takeIf { it.isNotBlank() } ?: return defaults
    val byId = defaults.associateBy { it.id }
    val seen = LinkedHashSet<String>()
    val result = mutableListOf<DiscoverModuleToggle>()
    raw.split(",").forEach { token ->
        val parts = token.split(":")
        val id = parts.getOrNull(0)?.trim().orEmpty()
        val def = byId[id] ?: return@forEach
        if (seen.add(id)) {
            val enabled = parts.getOrNull(1)?.equals("1") ?: def.enabled
            result += def.copy(enabled = enabled)
        }
    }
    defaults.forEach { def ->
        if (seen.add(def.id)) result += def
    }
    return result
}

private fun savePersistedDiscoverModules(context: Context, list: List<DiscoverModuleToggle>) {
    val encoded = list.joinToString(",") { "${it.id}:${if (it.enabled) "1" else "0"}" }
    context.getSharedPreferences("mp_discover_modules_v3", Context.MODE_PRIVATE)
        .edit()
        .putString("modules_spec", encoded)
        .apply()
}

/**
 * 发现首页（完整覆盖 iOS 10 大发现模块，同时遵循 Android Material 3 Expressive 规范）：
 * - 全幅无遮挡沉浸主视觉轮播（透明片名 Logo、TMDB 中文类型、发行日期与评分）
 * - 继续观看 / 热门电影 / 热门剧集 / 本周趋势（16:9 宽幅横卡）/ 热门音乐（1:1 方卡）/
 *   豆瓣热映 / 豆瓣 Top250 / 最新入库 / 我的媒体库（纯封面+右上角数据角标）/ 分类浏览
 * - 支持自定义模块显隐与顺序编排并本地持久化。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen(
    repository: MoviePilotRepository,
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenExplore: (String) -> Unit,
    onOpenMusic: () -> Unit,
    onOpenMusicAlbum: ((MusicAlbumDto) -> Unit)? = null,
    onOpenMediaLibrary: (MediaServerLibraryDto) -> Unit = {},
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val context = LocalContext.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val categoryCols = if (AdaptiveDeviceLayout.effectiveContentWidthDp() >= 640) 3 else 2
    val heroHeight = AdaptiveDeviceLayout.discoverHeroHeight()
    val posterWidth = AdaptiveDeviceLayout.discoverPosterWidth()
    val density = LocalDensity.current
    val heroHeightPx = with(density) { heroHeight.toPx().coerceAtLeast(1f) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val localHaze = remember { HazeState() }

    val initialSnapshot = remember { repository.cachedDiscover }
    var trending by remember { mutableStateOf(initialSnapshot?.trending.orEmpty()) }
    var movies by remember { mutableStateOf(initialSnapshot?.movies.orEmpty()) }
    var tvs by remember { mutableStateOf(initialSnapshot?.tvs.orEmpty()) }
    var musicAlbums by remember { mutableStateOf(initialSnapshot?.musicAlbums.orEmpty()) }
    var doubanShowing by remember { mutableStateOf(initialSnapshot?.showing.orEmpty()) }
    var doubanTop250 by remember { mutableStateOf(initialSnapshot?.top250.orEmpty()) }
    var continueItems by remember { mutableStateOf(initialSnapshot?.continueWatching.orEmpty()) }
    var latestItems by remember { mutableStateOf(initialSnapshot?.latestItems.orEmpty()) }
    var mediaLibraries by remember { mutableStateOf(initialSnapshot?.libraries.orEmpty()) }
    var selectedAlbum by remember { mutableStateOf<MusicAlbumDto?>(null) }
    val heroLogos = remember {
        mutableStateMapOf<String, String>().apply {
            initialSnapshot?.heroLogos?.let { putAll(it) }
        }
    }
    var showModulesSheet by remember { mutableStateOf(false) }
    var isInitialLoading by remember { mutableStateOf(initialSnapshot == null) }
    var isRefreshing by remember { mutableStateOf(false) }

    val modules = remember {
        mutableStateListOf<DiscoverModuleToggle>().apply {
            addAll(loadPersistedDiscoverModules(context))
        }
    }

    fun syncDiscoverCache() {
        repository.cachedDiscover = DiscoverSessionSnapshot(
            trending = trending,
            movies = movies,
            tvs = tvs,
            musicAlbums = musicAlbums,
            showing = doubanShowing,
            top250 = doubanTop250,
            continueWatching = continueItems,
            latestItems = latestItems,
            libraries = mediaLibraries,
            heroLogos = heroLogos.toMap(),
        )
    }

    suspend fun loadAll() {
        coroutineScope {
            val enabledIds = modules.filter { it.enabled }.map { it.id }.toSet()
            val trendingDef = async { repository.fetchDiscoverTrending(1) }
            val moviesDef = async { repository.fetchExplore("tmdb_movies", 1) }
            val tvsDef = async { repository.fetchExplore("tmdb_tvs", 1) }
            val continueDef = async { repository.fetchContinueWatching() }
            val latestDef = async { repository.fetchMediaServerLatest() }
            val libsDef = async { repository.fetchMediaServerLibraries() }
            val musicDef = if ("douban_music" in enabledIds) async { repository.fetchMusicFeed("douban", 1) } else null
            val showingDef = if ("douban_showing" in enabledIds) async { repository.fetchDoubanShowing(1) } else null
            val top250Def = if ("douban_top250" in enabledIds) async { repository.fetchDoubanTop250(1) } else null

            val fetchedTrending = trendingDef.await()
            trending = fetchedTrending
            movies = moviesDef.await().ifEmpty { fetchedTrending }
            tvs = tvsDef.await()
            continueItems = continueDef.await()
            latestItems = latestDef.await()
            mediaLibraries = libsDef.await()
            musicDef?.await()?.let { musicAlbums = it }
            showingDef?.await()?.let { doubanShowing = it }
            top250Def?.await()?.let { doubanTop250 = it }
            isInitialLoading = false
            isRefreshing = false
            syncDiscoverCache()

            // 异步并发补拉前 6 条 Hero 的透明片名 Logo（对齐 iOS `hydrateHeroLogos`）
            fetchedTrending.take(6).forEach { hero ->
                launch {
                    val logo = repository.fetchHeroLogo(hero)
                    if (!logo.isNullOrBlank()) {
                        heroLogos[hero.resolvedId] = logo
                        syncDiscoverCache()
                    }
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        if (trending.isEmpty()) {
            loadAll()
        }
    }

    LaunchedEffect(repository) {
        repository.playbackProgressReporter.playbackStoppedEvents.collect {
            val refreshed = repository.fetchContinueWatching()
            continueItems = refreshed
            syncDiscoverCache()
        }
    }

    // 开启按需榜单（如豆瓣热映 / 豆瓣 Top250 / 热门音乐）时自动懒加载数据
    val showingEnabled = modules.any { it.id == "douban_showing" && it.enabled }
    val top250Enabled = modules.any { it.id == "douban_top250" && it.enabled }
    val musicEnabled = modules.any { it.id == "douban_music" && it.enabled }
    LaunchedEffect(showingEnabled) {
        if (showingEnabled && doubanShowing.isEmpty()) doubanShowing = repository.fetchDoubanShowing(1)
    }
    LaunchedEffect(top250Enabled) {
        if (top250Enabled && doubanTop250.isEmpty()) doubanTop250 = repository.fetchDoubanTop250(1)
    }
    LaunchedEffect(musicEnabled) {
        if (musicEnabled && musicAlbums.isEmpty()) musicAlbums = repository.fetchMusicFeed("douban", 1)
    }

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
                val showInitialSkeleton = isInitialLoading &&
                    heroItems.isEmpty() &&
                    movies.isEmpty() &&
                    tvs.isEmpty() &&
                    continueItems.isEmpty() &&
                    latestItems.isEmpty()
                if (showInitialSkeleton) {
                    NativeDiscoverSkeleton()
                } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = bottomOverlayInset + 20.dp),
                    verticalArrangement = Arrangement.spacedBy(if (compactHeight) 16.dp else 22.dp),
                ) {
                    // 1. 前景主视觉轮播（始终作为 index 0 顶部锚点，避免异步模块加载后列表自动跳滚）
                    item(key = "discover_hero") {
                        if (heroItems.isNotEmpty()) {
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
                                                .padding(horizontal = margin, vertical = if (compactHeight) 12.dp else 22.dp),
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
                                                        fontSize = if (compactHeight) 20.sp else 26.sp,
                                                        fontWeight = FontWeight.ExtraBold,
                                                        textAlign = TextAlign.Center,
                                                        maxLines = if (compactHeight) 1 else 2,
                                                        overflow = TextOverflow.Ellipsis,
                                                    )
                                                }
                                                if (!logoUrl.isNullOrBlank()) {
                                                    AsyncImage(
                                                        model = logoUrl,
                                                        contentDescription = item.title,
                                                        contentScale = ContentScale.Fit,
                                                        onSuccess = { logoReady = true },
                                                        modifier = Modifier
                                                            .fillMaxWidth(if (compactHeight) 0.56f else 0.72f)
                                                            .height(if (compactHeight) 44.dp else 66.dp),
                                                    )
                                                }
                                            }
                                            Spacer(Modifier.height(if (compactHeight) 4.dp else 8.dp))
                                            Text(
                                                text = listOfNotNull(
                                                    item.genres.take(3).joinToString(" ").ifBlank { item.type },
                                                    item.releaseDate?.takeIf { it.isNotBlank() } ?: item.year.ifBlank { null },
                                                ).joinToString(" · "),
                                                color = if (colors.isDark) Color.White.copy(alpha = 0.90f) else colors.textPrimary.copy(alpha = 0.85f),
                                                fontSize = if (compactHeight) 12.sp else 13.sp,
                                                fontWeight = FontWeight.Medium,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                            if (item.overview.isNotBlank()) {
                                                Spacer(Modifier.height(if (compactHeight) 3.dp else 6.dp))
                                                Text(
                                                    text = item.overview,
                                                    color = if (colors.isDark) Color.White.copy(alpha = 0.78f) else colors.textSecondary,
                                                    fontSize = 12.sp,
                                                    maxLines = if (compactHeight) 1 else 2,
                                                    overflow = TextOverflow.Ellipsis,
                                                    textAlign = TextAlign.Center,
                                                    lineHeight = 18.sp,
                                                    modifier = Modifier.widthIn(max = 580.dp),
                                                )
                                            }
                                            Spacer(Modifier.height(if (compactHeight) 6.dp else 12.dp))
                                            Row(
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                            ) {
                                                val srcName = when {
                                                    item.source.contains("douban", true) -> "豆瓣"
                                                    item.source.contains("bangumi", true) -> "Bangumi"
                                                    else -> "TMDB"
                                                }
                                                Row(
                                                    modifier = Modifier
                                                        .clip(RoundedCornerShape(7.dp))
                                                        .background(Color.Black.copy(alpha = if (colors.isDark) 0.45f else 0.08f))
                                                        .border(0.6.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(7.dp))
                                                        .padding(horizontal = 6.dp, vertical = 3.dp),
                                                    verticalAlignment = Alignment.CenterVertically,
                                                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                                                ) {
                                                    NativeEntityLogo(
                                                        kind = "datasource",
                                                        value = item.source,
                                                        size = 16.dp,
                                                        cornerRadius = 4.dp,
                                                    )
                                                    Text(
                                                        text = srcName,
                                                        color = if (colors.isDark) Color.White else colors.textPrimary,
                                                        fontSize = 11.sp,
                                                        fontWeight = FontWeight.Bold,
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
                        } else {
                            Spacer(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(if (compactHeight) 56.dp else 72.dp),
                            )
                        }
                    }

                    // 按用户编排顺序渲染全部 10 大发现模块
                    modules.filter { it.enabled }.forEach { mod ->
                        when (mod.id) {
                            "continue" -> if (continueItems.isNotEmpty()) {
                                item(key = "mod_continue") {
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
                                                                            server = manifest.server.ifBlank { cw.server },
                                                                            serverType = cw.serverType,
                                                                            mediaSourceId = manifest.mediaSourceId.orEmpty(),
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
                                                                            type = cw.type,
                                                                            posterPath = cw.image,
                                                                            backdropPath = cw.image,
                                                                            serverItemId = cw.id.takeIf { it.isNotBlank() },
                                                                            serverName = cw.server.takeIf { it.isNotBlank() },
                                                                            serverType = cw.serverType.takeIf { it.isNotBlank() },
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
                                                            .clip(RoundedCornerShape(16.dp))
                                                            .background(Brush.linearGradient(listOf(Color(0xFF473766), Color(0xFF282038))))
                                                            .border(0.7.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(16.dp)),
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
                                                        if (cw.server.isNotBlank()) {
                                                            Row(
                                                                modifier = Modifier
                                                                    .align(Alignment.TopStart)
                                                                    .padding(8.dp)
                                                                    .clip(CircleShape)
                                                                    .background(Color.Black.copy(alpha = 0.56f))
                                                                    .padding(horizontal = 6.dp, vertical = 3.dp),
                                                                verticalAlignment = Alignment.CenterVertically,
                                                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                                            ) {
                                                                NativeEntityLogo(
                                                                    kind = "mediaserver",
                                                                    value = cw.serverType.ifBlank { cw.server },
                                                                    size = 15.dp,
                                                                    cornerRadius = 4.dp,
                                                                )
                                                                Text(cw.server, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
                                                            }
                                                        }
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

                            "movies" -> if (movies.isNotEmpty()) {
                                item(key = "mod_movies") {
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

                            "tvs" -> if (tvs.isNotEmpty()) {
                                item(key = "mod_tvs") {
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

                            "trending" -> if (trending.isNotEmpty()) {
                                item(key = "mod_trending") {
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        NativeSectionHeader(
                                            title = "本周趋势",
                                            onClickMore = { onOpenExplore("tmdb_movies") },
                                            modifier = Modifier.padding(horizontal = margin),
                                        )
                                        LazyRow(
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                                        ) {
                                            items(trending, key = { "tr_${it.resolvedId}" }) { item ->
                                                Column(
                                                    modifier = Modifier
                                                        .width(238.dp)
                                                        .clickable { onOpenMedia(item) },
                                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                                ) {
                                                    Box(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .aspectRatio(16f / 9f)
                                                            .clip(RoundedCornerShape(16.dp))
                                                            .background(colors.surfaceContainerHigh)
                                                            .border(0.6.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(16.dp)),
                                                    ) {
                                                        val img = item.backdropPath ?: item.posterPath
                                                        if (!img.isNullOrBlank()) {
                                                            AsyncImage(
                                                                model = img,
                                                                contentDescription = item.title,
                                                                contentScale = ContentScale.Crop,
                                                                modifier = Modifier.fillMaxSize(),
                                                            )
                                                        }
                                                        if (item.voteAverage > 0.0) {
                                                            Box(
                                                                modifier = Modifier
                                                                    .align(Alignment.TopEnd)
                                                                    .padding(8.dp)
                                                                    .clip(CircleShape)
                                                                    .background(Color.Black.copy(alpha = 0.62f))
                                                                    .padding(horizontal = 8.dp, vertical = 3.dp),
                                                            ) {
                                                                Text(
                                                                    String.format("%.1f", item.voteAverage),
                                                                    color = Color.White,
                                                                    fontSize = 11.sp,
                                                                    fontWeight = FontWeight.Bold,
                                                                )
                                                            }
                                                        }
                                                    }
                                                    Text(item.title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                    val sub = listOfNotNull(item.year.takeIf { it.isNotBlank() }, item.type.takeIf { it.isNotBlank() }).joinToString(" · ")
                                                    if (sub.isNotBlank()) {
                                                        Text(sub, color = colors.textMuted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            "douban_music" -> if (musicAlbums.isNotEmpty()) {
                                item(key = "mod_music") {
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        NativeSectionHeader(
                                            title = "热门音乐",
                                            onClickMore = { onOpenExplore("music") },
                                            modifier = Modifier.padding(horizontal = margin),
                                        )
                                        LazyRow(
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            items(musicAlbums, key = { "dm_${it.id}_${it.title}" }) { album ->
                                                val side = posterWidth + 14.dp
                                                Column(
                                                    modifier = Modifier
                                                        .width(side)
                                                        .clickable {
                                                            if (onOpenMusicAlbum != null) onOpenMusicAlbum(album) else selectedAlbum = album
                                                        },
                                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                                ) {
                                                    Box(
                                                        modifier = Modifier
                                                            .size(side)
                                                            .clip(RoundedCornerShape(16.dp))
                                                            .background(colors.surfaceContainerHigh)
                                                            .border(0.6.dp, colors.divider, RoundedCornerShape(16.dp)),
                                                        contentAlignment = Alignment.Center,
                                                    ) {
                                                        Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = colors.accent, modifier = Modifier.size(34.dp))
                                                        if (!album.coverUrl.isNullOrBlank()) {
                                                            AsyncImage(
                                                                model = album.coverUrl,
                                                                contentDescription = album.title,
                                                                contentScale = ContentScale.Crop,
                                                                modifier = Modifier.fillMaxSize(),
                                                            )
                                                        }
                                                    }
                                                    Text(album.title, color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                    val caption = listOfNotNull(album.artist.takeIf { it.isNotBlank() }, album.year.takeIf { it.isNotBlank() }).joinToString(" · ")
                                                    if (caption.isNotBlank()) {
                                                        Text(caption, color = colors.textMuted, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            "douban_showing" -> if (doubanShowing.isNotEmpty()) {
                                item(key = "mod_douban_showing") {
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        NativeSectionHeader(
                                            title = "豆瓣热映",
                                            onClickMore = { onOpenExplore("douban_movies") },
                                            modifier = Modifier.padding(horizontal = margin),
                                        )
                                        LazyRow(
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            items(doubanShowing) { item ->
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

                            "douban_top250" -> if (doubanTop250.isNotEmpty()) {
                                item(key = "mod_douban_top250") {
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        NativeSectionHeader(
                                            title = "豆瓣 Top250",
                                            onClickMore = { onOpenExplore("douban_movies") },
                                            modifier = Modifier.padding(horizontal = margin),
                                        )
                                        LazyRow(
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            items(doubanTop250) { item ->
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

                            "latest" -> if (latestItems.isNotEmpty()) {
                                item(key = "mod_latest") {
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        NativeSectionHeader(
                                            title = "最新入库",
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

                            "libraries" -> if (mediaLibraries.isNotEmpty()) {
                                item(key = "mod_libraries") {
                                    val firstLib = mediaLibraries.first()
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        NativeSectionHeader(
                                            title = "我的媒体库",
                                            subtitle = firstLib.server,
                                            subtitleLeading = if (firstLib.server.isNotBlank()) {
                                                {
                                                    NativeEntityLogo(
                                                        kind = "mediaserver",
                                                        value = firstLib.serverType.ifBlank { firstLib.server },
                                                        size = 16.dp,
                                                        cornerRadius = 4.dp,
                                                    )
                                                }
                                            } else null,
                                            onClickMore = { onOpenMediaLibrary(firstLib) },
                                            modifier = Modifier.padding(horizontal = margin),
                                        )
                                        LazyRow(
                                            contentPadding = PaddingValues(horizontal = margin),
                                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                                        ) {
                                            items(mediaLibraries, key = { "${it.server}_${it.id}" }) { lib ->
                                                // 纯净封面呈现（不叠标题遮罩避免挡住封面自带文字），左上角展示服务器品牌图标，右上角展示入库数量
                                                Box(
                                                    modifier = Modifier
                                                        .width(204.dp)
                                                        .aspectRatio(16f / 9f)
                                                        .clip(RoundedCornerShape(18.dp))
                                                        .background(colors.surfaceContainerHigh)
                                                        .border(0.7.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(18.dp))
                                                        .clickable { onOpenMediaLibrary(lib) },
                                                    contentAlignment = Alignment.Center,
                                                ) {
                                                    if (!lib.imageUrl.isNullOrBlank()) {
                                                        AsyncImage(
                                                            model = lib.imageUrl,
                                                            contentDescription = lib.name,
                                                            contentScale = ContentScale.Crop,
                                                            modifier = Modifier.fillMaxSize(),
                                                        )
                                                    } else {
                                                        Column(
                                                            horizontalAlignment = Alignment.CenterHorizontally,
                                                            verticalArrangement = Arrangement.spacedBy(6.dp),
                                                        ) {
                                                            NativeEntityLogo(
                                                                kind = "mediaserver",
                                                                value = lib.serverType.ifBlank { lib.server },
                                                                size = 30.dp,
                                                                cornerRadius = 8.dp,
                                                            )
                                                            Text(
                                                                lib.name,
                                                                color = colors.textPrimary,
                                                                fontSize = 13.sp,
                                                                fontWeight = FontWeight.SemiBold,
                                                                maxLines = 1,
                                                                overflow = TextOverflow.Ellipsis,
                                                            )
                                                        }
                                                    }
                                                    if (lib.server.isNotBlank()) {
                                                        Box(
                                                            modifier = Modifier
                                                                .align(Alignment.TopStart)
                                                                .padding(8.dp)
                                                                .clip(RoundedCornerShape(7.dp))
                                                                .background(Color.Black.copy(alpha = 0.52f))
                                                                .padding(3.dp),
                                                        ) {
                                                            NativeEntityLogo(
                                                                kind = "mediaserver",
                                                                value = lib.serverType.ifBlank { lib.server },
                                                                size = 18.dp,
                                                                cornerRadius = 4.dp,
                                                            )
                                                        }
                                                    }
                                                    val count = lib.itemCount?.takeIf { it >= 0 }
                                                    if (count != null) {
                                                        Box(
                                                            modifier = Modifier
                                                                .align(Alignment.TopEnd)
                                                                .padding(8.dp)
                                                                .clip(CircleShape)
                                                                .background(Color.Black.copy(alpha = 0.56f))
                                                                .border(0.6.dp, Color.White.copy(alpha = 0.24f), CircleShape)
                                                                .padding(horizontal = 8.dp, vertical = 3.dp),
                                                        ) {
                                                            Text(
                                                                text = String.format("%,d", count),
                                                                color = Color.White,
                                                                fontSize = 11.sp,
                                                                fontWeight = FontWeight.Bold,
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            "categories" -> {
                                item(key = "mod_categories") {
                                    val categoryEntries = listOf(
                                        Triple("TMDB 电影", "tmdb_movies", movies.firstOrNull()?.posterPath),
                                        Triple("TMDB 剧集", "tmdb_tvs", tvs.firstOrNull()?.posterPath),
                                        Triple(
                                            "豆瓣电影",
                                            "douban_movies",
                                            doubanShowing.firstOrNull()?.posterPath
                                                ?: doubanTop250.firstOrNull()?.posterPath
                                                ?: movies.getOrNull(1)?.posterPath,
                                        ),
                                        Triple("豆瓣剧集", "douban_tvs", tvs.getOrNull(1)?.posterPath ?: movies.getOrNull(2)?.posterPath),
                                        Triple("Bangumi 番剧", "bangumi", tvs.getOrNull(2)?.posterPath ?: tvs.firstOrNull()?.posterPath),
                                        Triple("音乐探索", "music", musicAlbums.firstOrNull()?.coverUrl ?: movies.getOrNull(3)?.posterPath),
                                    )
                                    Column(
                                        verticalArrangement = Arrangement.spacedBy(12.dp),
                                        modifier = Modifier.padding(horizontal = margin),
                                    ) {
                                        NativeSectionHeader(
                                            title = "分类浏览",
                                            onClickMore = { onOpenExplore("tmdb_movies") },
                                        )
                                        categoryEntries.chunked(categoryCols).forEach { row ->
                                            Row(
                                                modifier = Modifier.fillMaxWidth(),
                                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                                            ) {
                                                row.forEach { (title, sourceKey, poster) ->
                                                    CategoryPosterTile(
                                                        title = title,
                                                        sourceKey = sourceKey,
                                                        posterUrl = poster,
                                                        modifier = Modifier.weight(1f),
                                                        onClick = { onOpenExplore(sourceKey) },
                                                    )
                                                }
                                                repeat(categoryCols - row.size) {
                                                    Spacer(Modifier.weight(1f))
                                                }
                                            }
                                        }
                                    }
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
        }

        // 顶部状态栏渐进模糊（首屏 scroll=0 时 0% 透明保持海报无遮挡，上滚后平滑浮现防止内容与状态栏重叠）
        NativeTopStatusBarProgressiveBlur(
            visibilityProgress = eased,
            extraHeight = 40.dp,
            blurSourceState = localHaze,
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }

    if (showModulesSheet) {
        NativeGlassSheet(onDismissRequest = { showModulesSheet = false }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column {
                        Text("编辑发现模块", color = colors.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                        Text("开关显隐并调整首页模块展示顺序", color = colors.textSecondary, fontSize = 12.5.sp)
                    }
                    NativeAdaptivePill(
                        title = "恢复默认",
                        selected = false,
                        onClick = {
                            modules.clear()
                            modules.addAll(defaultDiscoverModules())
                            savePersistedDiscoverModules(context, modules)
                        },
                    )
                }
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth().weight(1f, fill = false),
                ) {
                    items(modules.size, key = { modules[it].id }) { idx ->
                        val mod = modules[idx]
                        CinematicPanel(padding = 12.dp, showsShadow = false) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Text(
                                    mod.title,
                                    color = colors.textPrimary,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Medium,
                                    modifier = Modifier.weight(1f),
                                )
                                IconButton(
                                    onClick = {
                                        if (idx > 0) {
                                            val item = modules.removeAt(idx)
                                            modules.add(idx - 1, item)
                                            savePersistedDiscoverModules(context, modules)
                                        }
                                    },
                                    enabled = idx > 0,
                                    modifier = Modifier.size(32.dp),
                                ) {
                                    Icon(
                                        Icons.Rounded.ArrowUpward,
                                        contentDescription = "上移",
                                        tint = if (idx > 0) colors.textSecondary else colors.textMuted.copy(alpha = 0.35f),
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                                IconButton(
                                    onClick = {
                                        if (idx < modules.lastIndex) {
                                            val item = modules.removeAt(idx)
                                            modules.add(idx + 1, item)
                                            savePersistedDiscoverModules(context, modules)
                                        }
                                    },
                                    enabled = idx < modules.lastIndex,
                                    modifier = Modifier.size(32.dp),
                                ) {
                                    Icon(
                                        Icons.Rounded.ArrowDownward,
                                        contentDescription = "下移",
                                        tint = if (idx < modules.lastIndex) colors.textSecondary else colors.textMuted.copy(alpha = 0.35f),
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                                Switch(
                                    checked = mod.enabled,
                                    onCheckedChange = { checked ->
                                        modules[idx] = mod.copy(enabled = checked)
                                        savePersistedDiscoverModules(context, modules)
                                    },
                                    colors = SwitchDefaults.colors(
                                        checkedTrackColor = colors.accent,
                                        checkedThumbColor = colors.primaryButtonFg,
                                    ),
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }

    // 发现页点击「热门音乐」方卡后的专辑详情与试听弹层
    selectedAlbum?.let { album ->
        var subMsg by remember(album.id) { mutableStateOf<String?>(null) }
        var isResolvingStream by remember(album.id) { mutableStateOf(false) }
        val coverSize = if (compactHeight) 120.dp else 176.dp
        NativeGlassSheet(onDismissRequest = { selectedAlbum = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(if (compactHeight) 10.dp else 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    modifier = Modifier
                        .size(coverSize)
                        .clip(RoundedCornerShape(22.dp))
                        .background(colors.surfaceContainerHigh),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = colors.accent, modifier = Modifier.size(52.dp))
                    if (!album.coverUrl.isNullOrBlank()) {
                        AsyncImage(model = album.coverUrl, contentDescription = album.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    }
                }
                Text(album.title, color = colors.textPrimary, fontSize = 19.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Text(
                    listOfNotNull(album.artist.ifBlank { null }, album.year.ifBlank { null }).joinToString(" · "),
                    color = colors.textSecondary,
                    fontSize = 13.5.sp,
                )
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = {
                            scope.launch {
                                val (ok, msg) = repository.createOrUpdateSubscriptionWithMessage(
                                    SubscribeItemDto(name = album.title, year = album.year, type = "音乐", mediaSource = album.source, mediaId = album.id),
                                )
                                subMsg = if (ok) "已添加音乐专辑订阅" else msg
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.surfaceContainerHigh, contentColor = colors.textPrimary),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(Icons.Rounded.BookmarkAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("订阅专辑", fontWeight = FontWeight.Bold)
                    }
                    Button(
                        enabled = !isResolvingStream,
                        onClick = {
                            scope.launch {
                                isResolvingStream = true
                                subMsg = null
                                val manifest = repository.fetchMusicStreamInfo(album.title, album.artist.ifBlank { null }, album.title)
                                if (manifest != null) {
                                    val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                    isResolvingStream = false
                                    selectedAlbum = null
                                    onPlayMedia(
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
                                    isResolvingStream = false
                                    subMsg = "当前媒体服务器未匹配到该专辑可播放音轨"
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(if (isResolvingStream) "匹配音轨中…" else "媒体库直放", fontWeight = FontWeight.Bold)
                    }
                }
                subMsg?.let { Text(it, color = colors.success, fontSize = 13.sp) }
                Spacer(Modifier.height(18.dp))
            }
        }
    }
}

@Composable
private fun CategoryPosterTile(
    title: String,
    sourceKey: String,
    posterUrl: String?,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    CinematicPanel(
        padding = 9.dp,
        modifier = modifier.clickable(onClick = onClick),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(colors.surfaceContainerHigh),
                contentAlignment = Alignment.Center,
            ) {
                NativeEntityLogo(
                    kind = "datasource",
                    value = sourceKey,
                    size = 26.dp,
                    cornerRadius = 7.dp,
                )
                if (!posterUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = posterUrl,
                        contentDescription = title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(2.dp)
                            .clip(RoundedCornerShape(5.dp))
                            .background(Color.Black.copy(alpha = 0.65f))
                            .padding(1.5.dp),
                    ) {
                        NativeEntityLogo(
                            kind = "datasource",
                            value = sourceKey,
                            size = 14.dp,
                            cornerRadius = 4.dp,
                        )
                    }
                }
            }
            Text(
                title,
                color = colors.textPrimary,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Icon(
                Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = colors.textMuted,
                modifier = Modifier.size(15.dp),
            )
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
    onBack: (() -> Unit)? = null,
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenMusicAlbum: ((MusicAlbumDto) -> Unit)? = null,
    onPlayAudio: (MediaPlaybackRequest) -> Unit = {},
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val columns = AdaptiveDeviceLayout.posterGridColumns()
    val musicColumns = AdaptiveDeviceLayout.squareGridColumns()
    val scope = rememberCoroutineScope()
    val posterGridState = rememberLazyGridState()
    val musicGridState = rememberLazyGridState()

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

    var activeSource by rememberSaveable { mutableStateOf(initialSource) }
    var lastAppliedInitial by rememberSaveable { mutableStateOf(initialSource) }
    LaunchedEffect(initialSource) {
        if (initialSource != lastAppliedInitial) {
            activeSource = initialSource
            lastAppliedInitial = initialSource
        }
    }
    var activeSort by rememberSaveable { mutableStateOf("热门") }
    var activeGenre by rememberSaveable { mutableStateOf("全部类型") }
    var activeLang by rememberSaveable { mutableStateOf("全部语言") }
    var activeDoubanTag by rememberSaveable { mutableStateOf("全部") }
    var activeMusicFeed by rememberSaveable { mutableStateOf("douban") }

    val cacheKey = remember(activeSource, activeSort, activeGenre, activeLang, activeDoubanTag, activeMusicFeed) {
        if (activeSource == "music") "music|$activeMusicFeed"
        else "$activeSource|$activeSort|$activeGenre|$activeLang|$activeDoubanTag"
    }
    val initialCached = remember(cacheKey) { repository.cachedExplore[cacheKey] }

    var page by remember(cacheKey) { mutableIntStateOf(initialCached?.page ?: 1) }
    var isLoading by remember(cacheKey) { mutableStateOf(initialCached == null) }
    var isRefreshing by remember { mutableStateOf(false) }
    var canLoadMore by remember(cacheKey) { mutableStateOf(initialCached?.hasMore ?: true) }
    var items by remember(cacheKey) { mutableStateOf(initialCached?.items.orEmpty()) }
    var musicAlbums by remember(cacheKey) { mutableStateOf(initialCached?.musicAlbums.orEmpty()) }
    var selectedAlbum by remember { mutableStateOf<MusicAlbumDto?>(null) }

    suspend fun reloadCurrent(showMainLoader: Boolean = true) {
        if (showMainLoader) isLoading = true
        page = 1
        canLoadMore = true
        if (activeSource == "music") {
            val fetchedMusic = repository.fetchMusicFeed(activeMusicFeed, 1)
            musicAlbums = fetchedMusic
            repository.cachedExplore[cacheKey] = ExploreSessionSnapshot(
                musicAlbums = fetchedMusic,
                page = 1,
                hasMore = false,
            )
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
            repository.cachedExplore[cacheKey] = ExploreSessionSnapshot(
                items = fetched,
                page = 1,
                hasMore = canLoadMore,
            )
        }
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(cacheKey) {
        val existing = repository.cachedExplore[cacheKey]
        val alreadyLoaded = if (activeSource == "music") existing?.musicAlbums?.isNotEmpty() == true
        else existing?.items?.isNotEmpty() == true
        if (!alreadyLoaded) {
            reloadCurrent(showMainLoader = true)
        } else {
            isLoading = false
        }
    }

    val activeSourceIdx = sources.indexOfFirst { it.id == activeSource }.coerceAtLeast(0)
    ExpressiveTintedScaffold(
        title = "分类探索",
        onBack = onBack,
        headerExtra = {
            ExpressivePillTabRow(
                tabs = sources.map { if (it.id == "music") "音乐" else "${it.brand} ${it.sub}" },
                selectedIndex = activeSourceIdx,
                onSelect = { idx -> activeSource = sources[idx].id },
                scrollable = true,
                onTintedHeader = true,
                tabIcons = sources.map { src ->
                    {
                        NativeEntityLogo(
                            kind = "datasource",
                            value = src.id,
                            size = 18.dp,
                            cornerRadius = 5.dp,
                        )
                    }
                },
            )
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(if (compactHeight) 6.dp else 12.dp))

        if (activeSource == "music") {
            LazyRow(
                contentPadding = PaddingValues(horizontal = margin),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(musicFeeds) { (key, label) ->
                    NativeAdaptivePill(
                        title = label,
                        leadingContent = {
                            NativeEntityLogo(
                                kind = "datasource",
                                value = if (key == "douban") "douban" else "musicbrainz",
                                size = 16.dp,
                                cornerRadius = 4.dp,
                            )
                        },
                        selected = key == activeMusicFeed,
                        onClick = { activeMusicFeed = key },
                    )
                }
            }
            Spacer(Modifier.height(if (compactHeight) 6.dp else 10.dp))
            if (isLoading && musicAlbums.isEmpty()) {
                NativePosterGridSkeleton(
                    columns = musicColumns,
                    aspectRatio = 1f,
                    inPanel = true,
                    contentPadding = PaddingValues(start = margin, end = margin, top = 4.dp, bottom = bottomOverlayInset + 20.dp),
                    headerContent = {
                        ExpressiveMixCollageHeaderSkeleton(
                            modifier = Modifier.padding(top = 6.dp, bottom = 10.dp),
                        )
                    },
                    modifier = Modifier.weight(1f),
                )
            } else {
                LazyVerticalGrid(
                    state = musicGridState,
                    columns = GridCells.Fixed(musicColumns),
                    contentPadding = PaddingValues(start = margin, end = margin, top = 4.dp, bottom = bottomOverlayInset + 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    if (musicAlbums.isNotEmpty()) {
                        item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                            ExpressiveMixCollageHeader(
                                headline = "精选音乐",
                                subtitle = "今日热门榜单与无损专辑推荐",
                                artworkUrls = musicAlbums.take(3).map { it.coverUrl },
                                onPlayClick = {
                                    val first = musicAlbums.first()
                                    if (onOpenMusicAlbum != null) onOpenMusicAlbum(first) else selectedAlbum = first
                                },
                                modifier = Modifier.padding(top = 6.dp, bottom = 10.dp),
                            )
                        }
                    }
                    items(musicAlbums, key = { it.id + it.title }) { album ->
                        CinematicPanel(
                            padding = 10.dp,
                            cornerRadius = 20.dp,
                            modifier = Modifier.clickable {
                                if (onOpenMusicAlbum != null) onOpenMusicAlbum(album) else selectedAlbum = album
                            },
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
            Spacer(Modifier.height(if (compactHeight) 5.dp else 8.dp))
            if (activeSource.startsWith("tmdb")) {
                LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(tmdbGenres) { g -> NativeAdaptivePill(g, selected = g == activeGenre, onClick = { activeGenre = g }) }
                }
                Spacer(Modifier.height(if (compactHeight) 5.dp else 8.dp))
                LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(tmdbLangs) { l -> NativeAdaptivePill(l, selected = l == activeLang, onClick = { activeLang = l }) }
                }
            } else if (activeSource.startsWith("douban")) {
                LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(doubanTags) { tag -> NativeAdaptivePill(tag, selected = tag == activeDoubanTag, onClick = { activeDoubanTag = tag }) }
                }
            }

            Spacer(Modifier.height(if (compactHeight) 6.dp else 12.dp))

            // 响应式 3~6 列自动分页海报网格 + 原生下拉刷新
            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { reloadCurrent(showMainLoader = false) }
                },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                ProvideSkeletonShimmer {
                    LazyVerticalGrid(
                        state = posterGridState,
                        columns = GridCells.Fixed(columns),
                        contentPadding = PaddingValues(start = margin, end = margin, top = 4.dp, bottom = bottomOverlayInset + 20.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        if (isLoading && items.isEmpty()) {
                            nativePosterGridSkeletonItems(
                                columns = columns,
                                count = columns * 3,
                            )
                        } else if (!isLoading && items.isEmpty()) {
                            item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                                CinematicPanel(padding = 24.dp, showsShadow = false) {
                                    Text("当前筛选条件下暂无片库内容", color = colors.textSecondary, fontSize = 14.sp)
                                }
                            }
                        } else {
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
                                        val merged = items + more.filter { seen.add(it.resolvedId) }
                                        items = merged
                                        page = nextPage
                                        repository.cachedExplore[cacheKey] = ExploreSessionSnapshot(
                                            items = merged,
                                            page = nextPage,
                                            hasMore = canLoadMore,
                                        )
                                    } else {
                                        canLoadMore = false
                                        repository.cachedExplore[cacheKey] = ExploreSessionSnapshot(
                                            items = items,
                                            page = page,
                                            hasMore = false,
                                        )
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
        }
        }
    }

    // 音乐专辑详情与订阅/试听弹窗
    selectedAlbum?.let { album ->
        var subMsg by remember(album.id) { mutableStateOf<String?>(null) }
        var isResolvingStream by remember(album.id) { mutableStateOf(false) }
        val coverSize = if (compactHeight) 124.dp else 188.dp
        NativeGlassSheet(onDismissRequest = { selectedAlbum = null }) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(if (compactHeight) 10.dp else 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    modifier = Modifier
                        .size(coverSize)
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
                                val (ok, msg) = repository.createOrUpdateSubscriptionWithMessage(
                                    SubscribeItemDto(name = album.title, year = album.year, type = "音乐", mediaSource = album.source, mediaId = album.id),
                                )
                                subMsg = if (ok) "已添加音乐专辑订阅" else msg
                            }
                        },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.surfaceContainerHigh,
                            contentColor = colors.textPrimary,
                        ),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(Icons.Rounded.BookmarkAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("订阅专辑", fontWeight = FontWeight.Bold)
                    }
                    Button(
                        enabled = !isResolvingStream,
                        onClick = {
                            scope.launch {
                                isResolvingStream = true
                                subMsg = null
                                val manifest = repository.fetchMusicStreamInfo(
                                    title = album.title,
                                    artist = album.artist.ifBlank { null },
                                    album = album.title,
                                )
                                if (manifest != null) {
                                    val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                    isResolvingStream = false
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
                                    isResolvingStream = false
                                    subMsg = "当前媒体服务器未匹配到该专辑可播放音轨"
                                }
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.primaryButtonFg),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(if (isResolvingStream) "匹配音轨中…" else "媒体库直放", fontWeight = FontWeight.Bold)
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
 * 全局搜索页（Material 3 Expressive 染色顶栏 + 分类胶囊页签 + 28dp 圆角内容区）：
 * 顶部大胶囊搜索框 + 搜索前紧贴输入框展示「热门搜索」推荐词流（避免放在空白页底部）+ 严格“仅媒体库直放”策略。
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun GlobalSearchScreen(
    repository: MoviePilotRepository,
    initialQuery: String = "",
    initialKind: String = "media",
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenPerson: (com.moviepilot.rustbridge.MediaPersonDto) -> Unit = {},
    onOpenMusicAlbum: ((MusicAlbumDto) -> Unit)? = null,
    onPlayLibraryItem: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val columns = AdaptiveDeviceLayout.posterGridColumns()
    val musicCols = AdaptiveDeviceLayout.squareGridColumns()
    val scope = rememberCoroutineScope()

    var query by remember { mutableStateOf(initialQuery) }
    var kind by remember { mutableStateOf(initialKind) }
    var results by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }
    var playError by remember { mutableStateOf<String?>(null) }
    var seriesPickerTarget by remember { mutableStateOf<MediaCardItem?>(null) }
    var resolvingMusicId by remember { mutableStateOf<String?>(null) }

    val kinds = listOf(
        "media" to "媒体",
        "library" to "媒体库",
        "person" to "人物",
        "music" to "音乐",
        "collection" to "合集",
    )
    val quickTags = listOf("奥德赛", "钢铁侠", "超感神探", "庆余年", "星际穿越", "沙丘", "三体")

    LaunchedEffect(query, kind) {
        playError = null
        if (query.isNotBlank()) {
            isSearching = true
            results = repository.searchMedia(query, kind, 1)
            isSearching = false
        } else {
            results = emptyList()
        }
    }

    fun buildMusicSearchQueue(): List<MediaPlaybackRequest> =
        results.mapIndexed { idx, entry ->
            MediaPlaybackRequest(
                url = "",
                title = entry.title,
                subtitle = entry.subtitle.orEmpty(),
                albumTitle = entry.title,
                artworkUrl = entry.posterPath,
                isAudio = true,
                queueIndex = idx,
                lazySpec = QueueTrackSpec.MusicQuery(
                    title = entry.title,
                    artist = entry.subtitle?.takeIf { it.isNotBlank() },
                    album = null,
                ),
            )
        }

    fun playMusicResultAt(index: Int) {
        val item = results.getOrNull(index) ?: return
        if (resolvingMusicId != null) return
        scope.launch {
            resolvingMusicId = item.resolvedId
            playError = null
            val manifest = repository.fetchMusicStreamInfo(
                title = item.title,
                artist = item.subtitle?.takeIf { it.isNotBlank() },
                album = null,
            )
            resolvingMusicId = null
            if (manifest != null) {
                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                val queue = buildMusicSearchQueue()
                onPlayLibraryItem(
                    MediaPlaybackRequest(
                        url = manifest.contentUrl,
                        title = manifest.title.ifBlank { item.title },
                        subtitle = item.subtitle.orEmpty(),
                        artworkUrl = item.posterPath,
                        isAudio = true,
                        lyricsLrc = lrc,
                        headers = manifest.headers,
                        itemId = manifest.itemId,
                        server = manifest.server,
                        mediaSourceId = manifest.mediaSourceId.orEmpty(),
                        queue = queue,
                        queueIndex = index,
                    ),
                )
            } else {
                playError = "媒体服务器暂未匹配到「${item.title}」的可播放音频"
            }
        }
    }

    val kindIdx = kinds.indexOfFirst { it.first == kind }.coerceAtLeast(0)

    ExpressiveTintedScaffold(
        title = "全局搜索",
        onBack = onBack,
        headerExtra = {
            ExpressivePillTabRow(
                tabs = kinds.map { it.second },
                selectedIndex = kindIdx,
                onSelect = { idx -> kind = kinds[idx].first },
                scrollable = true,
                onTintedHeader = true,
            )
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(14.dp))
            CinematicPanel(padding = 13.dp, cornerRadius = 24.dp, modifier = Modifier.padding(horizontal = margin)) {
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

            playError?.let { err ->
                Text(
                    text = err,
                    color = colors.warning,
                    fontSize = 12.5.sp,
                    modifier = Modifier.padding(horizontal = margin, vertical = 6.dp),
                )
            }

            Spacer(Modifier.height(10.dp))
            if (isSearching) {
                if (kind == "person") {
                    NativePersonGridSkeleton(
                        columns = columns,
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomOverlayInset + 24.dp),
                        modifier = Modifier.weight(1f),
                    )
                } else {
                    NativePosterGridSkeleton(
                        columns = if (kind == "music") musicCols else columns,
                        aspectRatio = if (kind == "music") 1f else 2f / 3f,
                        inPanel = kind == "music",
                        contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomOverlayInset + 24.dp),
                        modifier = Modifier.weight(1f),
                    )
                }
            } else if (query.isBlank()) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = margin),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(Icons.Rounded.LocalFireDepartment, contentDescription = null, tint = colors.accent, modifier = Modifier.size(18.dp))
                        Text("热门搜索", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                    }
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        quickTags.forEach { kw ->
                            NativeAdaptivePill(kw, selected = false, onClick = { query = kw })
                        }
                    }
                    Text(
                        text = "切换上方分类胶囊可精准检索媒体库、演职员、音乐与合集",
                        color = colors.textMuted,
                        fontSize = 12.5.sp,
                        modifier = Modifier.padding(top = 4.dp),
                    )
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
                        text = "未找到与「$query」匹配的内容",
                        color = colors.textMuted,
                        fontSize = 14.sp,
                    )
                }
            } else if (kind == "person") {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(columns),
                    contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomOverlayInset + 24.dp),
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
            } else if (kind == "music") {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(musicCols),
                    contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomOverlayInset + 24.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    itemsIndexed(results, key = { idx, it -> "${it.resolvedId}_$idx" }) { idx, item ->
                        val albumSeed = MusicAlbumDto(
                            id = item.mediaId ?: item.resolvedId,
                            albumId = item.mediaId ?: item.resolvedId,
                            title = item.title,
                            artist = item.subtitle.orEmpty(),
                            year = item.year,
                            coverUrl = item.posterPath,
                            source = item.source.ifBlank { "musicbrainz" },
                            voteAverage = item.voteAverage,
                            overview = item.overview,
                        )
                        CinematicPanel(
                            padding = 10.dp,
                            cornerRadius = 18.dp,
                            modifier = Modifier.clickable {
                                if (onOpenMusicAlbum != null && !item.mediaId.isNullOrBlank()) {
                                    onOpenMusicAlbum(albumSeed)
                                } else {
                                    playMusicResultAt(idx)
                                }
                            },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(1f)
                                        .clip(RoundedCornerShape(13.dp))
                                        .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.55f), Color(0xFF281F3D)))),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = Color.White.copy(alpha = 0.72f), modifier = Modifier.size(38.dp))
                                    if (!item.posterPath.isNullOrBlank()) {
                                        AsyncImage(model = item.posterPath, contentDescription = item.title, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                    }
                                    Box(
                                        modifier = Modifier
                                            .align(Alignment.BottomEnd)
                                            .padding(7.dp)
                                            .size(32.dp)
                                            .clip(CircleShape)
                                            .background(Color.Black.copy(alpha = 0.65f))
                                            .clickable { playMusicResultAt(idx) },
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(
                                            Icons.Rounded.PlayArrow,
                                            contentDescription = "播放 ${item.title}",
                                            tint = Color.White,
                                            modifier = Modifier.size(18.dp),
                                        )
                                    }
                                }
                                Text(item.title, color = colors.textPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                val sub = listOfNotNull(item.subtitle?.takeIf { it.isNotBlank() }, item.year.takeIf { it.isNotBlank() }).joinToString(" · ")
                                if (sub.isNotBlank()) {
                                    Text(
                                        text = if (resolvingMusicId == item.resolvedId) "正在匹配音轨…" else sub,
                                        color = if (resolvingMusicId == item.resolvedId) colors.accent else colors.textSecondary,
                                        fontSize = 11.5.sp,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                val audioLibItems = remember(results, kind) {
                    if (kind == "library") results.filter { it.type == "音乐" } else emptyList()
                }
                LazyVerticalGrid(
                    columns = GridCells.Fixed(columns),
                    contentPadding = PaddingValues(start = margin, end = margin, bottom = bottomOverlayInset + 24.dp),
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
                                val hasServerTarget = !item.serverItemId.isNullOrBlank() && !item.serverName.isNullOrBlank()
                                if (kind == "library" && MoviePilotRepository.isTvType(item.type) && (hasServerTarget || !item.mediaId.isNullOrBlank())) {
                                    seriesPickerTarget = item.copy(
                                        serverItemId = item.serverItemId ?: item.mediaId,
                                    )
                                } else if (kind == "library" && item.type == "音乐") {
                                    scope.launch {
                                        playError = null
                                        val itemId = item.serverItemId ?: item.mediaId.orEmpty()
                                        val srv = item.serverName
                                        val manifest = if (itemId.isNotBlank()) repository.fetchVideoStreamInfo(itemId, srv) else null
                                        if (manifest != null) {
                                            val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                            val audioQueue = audioLibItems.mapIndexed { qIdx, aItem ->
                                                val aId = aItem.serverItemId ?: aItem.mediaId.orEmpty()
                                                val aSrv = aItem.serverName ?: manifest.server
                                                MediaPlaybackRequest(
                                                    url = "",
                                                    title = aItem.title,
                                                    subtitle = aItem.subtitle ?: aSrv,
                                                    artworkUrl = aItem.posterPath,
                                                    isAudio = true,
                                                    itemId = aId,
                                                    server = aSrv,
                                                    queueIndex = qIdx,
                                                    lazySpec = QueueTrackSpec.MediaServerItem(aId, aSrv),
                                                )
                                            }
                                            val curQIdx = audioLibItems.indexOfFirst { it.resolvedId == item.resolvedId }.coerceAtLeast(0)
                                            onPlayLibraryItem(
                                                MediaPlaybackRequest(
                                                    url = manifest.contentUrl,
                                                    title = manifest.title.ifBlank { item.title },
                                                    subtitle = item.subtitle ?: manifest.server,
                                                    artworkUrl = item.posterPath,
                                                    isAudio = true,
                                                    lyricsLrc = lrc,
                                                    headers = manifest.headers,
                                                    itemId = manifest.itemId,
                                                    server = manifest.server,
                                                    mediaSourceId = manifest.mediaSourceId.orEmpty(),
                                                    queue = audioQueue,
                                                    queueIndex = curQIdx,
                                                ),
                                            )
                                        } else {
                                            onOpenMedia(item)
                                        }
                                    }
                                } else if (kind == "library" && hasServerTarget) {
                                    onOpenMedia(item)
                                } else if (kind == "library") {
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
                                                    mediaSourceId = manifest.mediaSourceId.orEmpty(),
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

    seriesPickerTarget?.let { target ->
        QuickSeriesEpisodePickerSheet(
            cardItem = target,
            repository = repository,
            onDismiss = { seriesPickerTarget = null },
            onOpenDetail = { onOpenMedia(target) },
            onPlayEpisode = onPlayLibraryItem,
        )
    }
}

/**
 * 独立音乐探索页（对应 `moviepilot://music`，完整支持豆瓣音乐 / 本周榜单 / 热门专辑 / 近期新发四大榜单与专辑详情直达）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MusicDiscoveryScreen(
    onBack: () -> Unit,
    onPlayAudio: (MediaPlaybackRequest) -> Unit,
    onOpenAlbum: ((MusicAlbumDto) -> Unit)? = null,
    repository: MoviePilotRepository? = null,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val cols = AdaptiveDeviceLayout.squareGridColumns()
    val scope = rememberCoroutineScope()

    val feeds = remember {
        listOf(
            "douban" to "豆瓣音乐",
            "weekly" to "本周榜单",
            "popular" to "热门专辑",
            "latest" to "近期新发",
        )
    }
    var selectedFeedKey by rememberSaveable { mutableStateOf("douban") }
    var filterKeyword by rememberSaveable { mutableStateOf("") }
    var albums by remember(selectedFeedKey) {
        mutableStateOf(repository?.cachedExplore?.get("music|$selectedFeedKey")?.musicAlbums.orEmpty())
    }
    var isLoading by remember(repository, selectedFeedKey) {
        mutableStateOf(repository != null && albums.isEmpty())
    }
    var isRefreshing by remember { mutableStateOf(false) }
    var resolvingAlbumId by remember { mutableStateOf<String?>(null) }
    var tip by remember { mutableStateOf<String?>(null) }

    suspend fun loadFeed(force: Boolean) {
        if (repository == null) {
            isLoading = false
            isRefreshing = false
            return
        }
        val cacheKey = "music|$selectedFeedKey"
        if (!force) {
            val cached = repository.cachedExplore[cacheKey]?.musicAlbums
            if (!cached.isNullOrEmpty()) {
                albums = cached
                isLoading = false
                isRefreshing = false
                return
            }
        }
        if (albums.isEmpty()) isLoading = true
        val fetched = repository.fetchMusicFeed(selectedFeedKey, 1)
        albums = fetched
        repository.cachedExplore[cacheKey] = ExploreSessionSnapshot(
            musicAlbums = fetched,
            page = 1,
            hasMore = false,
        )
        isLoading = false
        isRefreshing = false
    }

    LaunchedEffect(repository, selectedFeedKey) {
        loadFeed(force = false)
    }

    val filteredAlbums = remember(albums, filterKeyword) {
        val kw = filterKeyword.trim().lowercase()
        if (kw.isEmpty()) {
            albums
        } else {
            albums.filter {
                it.title.lowercase().contains(kw) || it.artist.lowercase().contains(kw)
            }
        }
    }
    val feedIdx = feeds.indexOfFirst { it.first == selectedFeedKey }.coerceAtLeast(0)

    ExpressiveTintedScaffold(
        title = "音乐探索",
        onBack = onBack,
        headerExtra = {
            ExpressivePillTabRow(
                tabs = feeds.map { it.second },
                selectedIndex = feedIdx,
                onSelect = { idx -> selectedFeedKey = feeds[idx].first },
                scrollable = true,
                onTintedHeader = true,
            )
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Spacer(Modifier.height(12.dp))
            CinematicPanel(padding = 11.dp, cornerRadius = 22.dp, showsShadow = false, modifier = Modifier.padding(horizontal = margin)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textMuted, modifier = Modifier.size(18.dp))
                    Box(modifier = Modifier.weight(1f)) {
                        if (filterKeyword.isEmpty()) Text("筛选专辑或艺人名称", color = colors.textMuted, fontSize = 14.sp)
                        BasicTextField(
                            value = filterKeyword,
                            onValueChange = { filterKeyword = it },
                            singleLine = true,
                            textStyle = TextStyle(color = colors.textPrimary, fontSize = 14.sp),
                            cursorBrush = SolidColor(colors.accent),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    if (filterKeyword.isNotEmpty()) {
                        IconButton(onClick = { filterKeyword = "" }, modifier = Modifier.size(22.dp)) {
                            Icon(Icons.Rounded.Close, contentDescription = "清除", tint = colors.textMuted, modifier = Modifier.size(15.dp))
                        }
                    }
                }
            }

            tip?.let { msg ->
                Text(msg, color = colors.warning, fontSize = 12.sp, modifier = Modifier.padding(horizontal = margin, vertical = 6.dp))
            }

            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = {
                    isRefreshing = true
                    scope.launch { loadFeed(force = true) }
                },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                if (isLoading && filteredAlbums.isEmpty()) {
                    NativePosterGridSkeleton(
                        columns = cols,
                        aspectRatio = 1f,
                        inPanel = true,
                        contentPadding = PaddingValues(start = margin, end = margin, top = 14.dp, bottom = bottomOverlayInset + 24.dp),
                        modifier = Modifier.fillMaxSize(),
                    )
                } else if (!isLoading && filteredAlbums.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize().padding(horizontal = margin, vertical = 20.dp), contentAlignment = Alignment.TopCenter) {
                        CinematicPanel(padding = 24.dp, showsShadow = false) {
                            Text("暂无匹配的音乐专辑，可切换上方榜单或下拉刷新。", color = colors.textSecondary, fontSize = 14.sp)
                        }
                    }
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(cols),
                        contentPadding = PaddingValues(start = margin, end = margin, top = 14.dp, bottom = bottomOverlayInset + 24.dp),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(filteredAlbums, key = { "${it.source}_${it.id}_${it.title}" }) { album ->
                            val isResolvingThis = resolvingAlbumId == album.id
                            CinematicPanel(
                                padding = 11.dp,
                                cornerRadius = 18.dp,
                                modifier = Modifier.clickable(enabled = resolvingAlbumId == null) {
                                    if (onOpenAlbum != null) {
                                        onOpenAlbum(album)
                                    } else {
                                        scope.launch {
                                            resolvingAlbumId = album.id
                                            tip = null
                                            val manifest = repository?.fetchMusicStreamInfo(album.title, album.artist.ifBlank { null }, album.title)
                                            resolvingAlbumId = null
                                            if (manifest != null) {
                                                val lrc = manifest.lyricsUrl?.let { repository.downloadSameOriginText(it) }
                                                onPlayAudio(
                                                    MediaPlaybackRequest(
                                                        url = manifest.contentUrl,
                                                        title = manifest.title.ifBlank { album.title },
                                                        subtitle = album.artist,
                                                        albumTitle = album.title,
                                                        artworkUrl = album.coverUrl,
                                                        isAudio = true,
                                                        lyricsLrc = lrc,
                                                        headers = manifest.headers,
                                                        itemId = manifest.itemId,
                                                        server = manifest.server,
                                                        mediaSourceId = manifest.mediaSourceId.orEmpty(),
                                                    ),
                                                )
                                            } else {
                                                tip = "未在媒体服务器中匹配到「${album.title}」的音频文件"
                                            }
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
                                        if (album.voteAverage > 0.0) {
                                            Box(
                                                modifier = Modifier
                                                    .align(Alignment.TopEnd)
                                                    .padding(6.dp)
                                                    .clip(CircleShape)
                                                    .background(Color.Black.copy(alpha = 0.64f))
                                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                                            ) {
                                                Text("%.1f".format(album.voteAverage), color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                            }
                                        }
                                    }
                                    Text(album.title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(
                                        if (isResolvingThis) "正在匹配媒体库音轨…" else listOfNotNull(album.artist.ifBlank { null }, album.year.ifBlank { null }).joinToString(" · "),
                                        color = if (isResolvingThis) colors.accent else colors.textSecondary,
                                        fontSize = 12.sp,
                                        maxLines = 1,
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
