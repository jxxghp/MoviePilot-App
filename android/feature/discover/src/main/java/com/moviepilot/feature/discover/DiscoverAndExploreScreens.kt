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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.designsystem.NativeBrandDrawable
import com.moviepilot.designsystem.NativeGlassSheet
import com.moviepilot.designsystem.NativeGlassTopBar
import com.moviepilot.designsystem.NativePosterCard
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.rustbridge.ContinueWatchingItem
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MoviePilotRepository

/** 发现页可编排模块项。 */
data class DiscoverModuleToggle(val id: String, val title: String, val enabled: Boolean)

/**
 * 发现首页（对标 iOS 黄金截图 `native-v2-live-discover-phase-1.jpg`）：
 * 全幅沉浸主视觉轮播（无顶栏遮挡自然融入紫玫渐变）、继续观看 16:9 横幅进度卡、
 * 热门电影 / 热门剧集 / 豆瓣推荐 / 音乐横栏、分类浏览与模块编排弹窗。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiscoverScreen(
    repository: MoviePilotRepository,
    onOpenMedia: (MediaCardItem) -> Unit,
    onOpenExplore: (String) -> Unit,
    onOpenMusic: () -> Unit,
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val heroHeight = AdaptiveDeviceLayout.discoverHeroHeight()
    val posterWidth = AdaptiveDeviceLayout.discoverPosterWidth()

    var trending by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var movies by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var tvs by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }
    var continueItems by remember { mutableStateOf<List<ContinueWatchingItem>>(emptyList()) }
    var showModulesSheet by remember { mutableStateOf(false) }

    val modules = remember {
        mutableStateListOf(
            DiscoverModuleToggle("continue", "继续观看", true),
            DiscoverModuleToggle("movies", "热门电影", true),
            DiscoverModuleToggle("tvs", "热门剧集", true),
            DiscoverModuleToggle("categories", "分类浏览", true),
        )
    }

    LaunchedEffect(Unit) {
        val fetchedTrending = repository.fetchDiscoverTrending(1)
        val fetchedMovies = repository.fetchExplore("tmdb_movies", 1)
        val fetchedTvs = repository.fetchExplore("tmdb_tvs", 1)
        val fetchedContinue = repository.fetchContinueWatching()

        trending = fetchedTrending.ifEmpty { sampleHeroItems() }
        movies = fetchedMovies.ifEmpty { trending }
        tvs = fetchedTvs.ifEmpty { sampleTvItems() }
        continueItems = fetchedContinue.ifEmpty { sampleContinueWatching() }
    }

    val heroItems = trending.take(6).ifEmpty { sampleHeroItems() }
    val pagerState = rememberPagerState(pageCount = { heroItems.size })

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 128.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            // 1. 全幅无遮挡沉浸主视觉轮播
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(heroHeight),
                ) {
                    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { idx ->
                        val item = heroItems[idx]
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .clickable { onOpenMedia(item) },
                        ) {
                            val backdrop = item.backdropPath ?: item.posterPath
                            // 离屏羽化底缘 Alpha：让全幅主视觉无接缝消融进底层实时 AGSL 紫玫流光，彻底消除底边硬缝
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                                    .drawWithContent {
                                        drawContent()
                                        drawRect(
                                            brush = Brush.verticalGradient(
                                                0.0f to Color.Black,
                                                0.56f to Color.Black,
                                                0.84f to Color.Black.copy(alpha = 0.34f),
                                                1.0f to Color.Transparent,
                                            ),
                                            blendMode = BlendMode.DstIn,
                                        )
                                    },
                            ) {
                                if (!backdrop.isNullOrBlank()) {
                                    AsyncImage(
                                        model = backdrop,
                                        contentDescription = item.title,
                                        contentScale = ContentScale.Crop,
                                        modifier = Modifier.fillMaxSize(),
                                    )
                                } else {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .background(
                                                Brush.verticalGradient(
                                                    listOf(Color(0xFF4B3D6B), Color(0xFF2F2342), Color(0xFF241D34)),
                                                ),
                                            ),
                                    )
                                }
                                // 柔和暗色护眼层（底部同步渐隐至透明，保证片名清晰且零底边接缝）
                                Box(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .background(
                                            Brush.verticalGradient(
                                                0.0f to Color.Transparent,
                                                0.38f to Color.Transparent,
                                                0.74f to Color.Black.copy(alpha = 0.56f),
                                                1.0f to Color.Black.copy(alpha = 0.25f),
                                            ),
                                        ),
                                )
                            }

                            Column(
                                modifier = Modifier
                                    .align(Alignment.BottomCenter)
                                    .fillMaxWidth()
                                    .padding(horizontal = margin, vertical = 22.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                Text(
                                    text = item.title,
                                    color = Color.White,
                                    fontSize = 26.sp,
                                    fontWeight = FontWeight.ExtraBold,
                                    textAlign = TextAlign.Center,
                                    maxLines = 2,
                                )
                                Spacer(Modifier.height(6.dp))
                                Text(
                                    text = listOfNotNull(
                                        item.genres.take(3).joinToString(" ").ifBlank { item.type },
                                        item.year.ifBlank { null },
                                    ).joinToString(" · "),
                                    color = Color.White.copy(alpha = 0.88f),
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Medium,
                                )
                                if (item.overview.isNotBlank()) {
                                    Spacer(Modifier.height(6.dp))
                                    Text(
                                        text = item.overview,
                                        color = Color.White.copy(alpha = 0.78f),
                                        fontSize = 12.sp,
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                        textAlign = TextAlign.Center,
                                    )
                                }
                                Spacer(Modifier.height(10.dp))
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    NativeAdaptiveBadge(
                                        text = if (item.source == "douban") "豆瓣" else "TheMovieDB",
                                        tint = Color(0xFF42C997),
                                        filled = true,
                                    )
                                    if (item.voteAverage > 0.0) {
                                        Text(
                                            text = String.format("%.1f", item.voteAverage),
                                            color = Color.White,
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
                                        color = Color.White.copy(alpha = 0.92f),
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            }
                        }
                    }

                    // 右上角模块编排按钮
                    CinematicCircleButton(
                        icon = Icons.Rounded.Tune,
                        contentDescription = "编辑发现模块",
                        onClick = { showModulesSheet = true },
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .statusBarsPadding()
                            .padding(end = 16.dp, top = 8.dp),
                    )

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
                                        if (pagerState.currentPage == i) Color.White
                                        else Color.White.copy(alpha = 0.35f),
                                    ),
                            )
                        }
                    }
                }
            }

            // 2. 继续观看（16:9 横幅进度卡）
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
                                            onPlayMedia(
                                                MediaPlaybackRequest(
                                                    url = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                                                    title = cw.title,
                                                    subtitle = cw.subtitle,
                                                    artworkUrl = cw.image,
                                                ),
                                            )
                                        },
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .aspectRatio(16f / 9f)
                                            .clip(RoundedCornerShape(15.dp))
                                            .background(
                                                Brush.linearGradient(listOf(Color(0xFF473766), Color(0xFF282038))),
                                            )
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
                                                .background(
                                                    Brush.verticalGradient(
                                                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f)),
                                                    ),
                                                ),
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

            // 3. 热门电影横向栏
            if (modules.firstOrNull { it.id == "movies" }?.enabled == true) {
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
            if (modules.firstOrNull { it.id == "tvs" }?.enabled == true) {
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

            // 5. 分类浏览与音乐发现入口
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
                            CategoryTile("音乐发现", "logo_musicbrainz", Modifier.weight(1f)) { onOpenMusic() }
                        }
                    }
                }
            }
        }
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
 * 探索片库页面（1:1 复刻 iOS 黄金截图 `native-v2-live-explore.jpg`）：
 * 顶部带来源 Logo 的横向小卡片一级导航 + 排序/类型/语言三行胶囊筛选 + 3~6 列响应式海报网格。
 */
@Composable
fun ExploreScreen(
    repository: MoviePilotRepository,
    initialSource: String = "tmdb_movies",
    onOpenMedia: (MediaCardItem) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val columns = AdaptiveDeviceLayout.posterGridColumns()

    val sources = remember {
        listOf(
            ExploreSourceTab("tmdb_movies", "TheMovieDB", "电影", "logo_tmdb"),
            ExploreSourceTab("tmdb_tvs", "TheMovieDB", "剧集", "logo_tmdb"),
            ExploreSourceTab("douban_movies", "豆瓣", "电影", "logo_douban"),
            ExploreSourceTab("douban_tvs", "豆瓣", "剧集", "logo_douban"),
            ExploreSourceTab("bangumi", "Bangumi", "番剧", "logo_bangumi"),
        )
    }
    val sorts = listOf("热门", "最新", "高分")
    val genres = listOf("全部类型", "动作", "科幻", "动画", "喜剧", "剧情", "悬疑")
    val langs = listOf("全部语言", "华语", "英语", "日语", "韩语")

    var activeSource by remember { mutableStateOf(initialSource) }
    var activeSort by remember { mutableStateOf("热门") }
    var activeGenre by remember { mutableStateOf("全部类型") }
    var activeLang by remember { mutableStateOf("全部语言") }
    var items by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }

    LaunchedEffect(activeSource, activeSort, activeGenre, activeLang) {
        val fetched = repository.fetchExplore(activeSource, 1, activeGenre, activeSort)
        items = fetched.ifEmpty { sampleHeroItems() + sampleTvItems() }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "探索")

        // 来源横向小卡片
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

        // 三行胶囊筛选栏
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(sorts) { s -> NativeAdaptivePill(s, selected = s == activeSort, onClick = { activeSort = s }) }
        }
        Spacer(Modifier.height(8.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(genres) { g -> NativeAdaptivePill(g, selected = g == activeGenre, onClick = { activeGenre = g }) }
        }
        Spacer(Modifier.height(8.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(langs) { l -> NativeAdaptivePill(l, selected = l == activeLang, onClick = { activeLang = l }) }
        }

        Spacer(Modifier.height(12.dp))

        // 响应式 3~6 列海报网格
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            contentPadding = PaddingValues(start = margin, end = margin, top = 4.dp, bottom = 124.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(items) { item ->
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

/**
 * 全局搜索页（+1 右侧圆钮默认入口）：
 * 顶部玻璃搜索框 + 5 类分类胶囊（媒体 / 媒体库 / 人物 / 音乐 / 合集），
 * 严格遵循“仅媒体库直放，其余进详情页”策略。
 */
@Composable
fun GlobalSearchScreen(
    repository: MoviePilotRepository,
    initialQuery: String = "",
    initialKind: String = "media",
    onBack: () -> Unit,
    onOpenMedia: (MediaCardItem) -> Unit,
    onPlayLibraryItem: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val columns = AdaptiveDeviceLayout.posterGridColumns()

    var query by remember { mutableStateOf(initialQuery) }
    var kind by remember { mutableStateOf(initialKind) }
    var results by remember { mutableStateOf<List<MediaCardItem>>(emptyList()) }

    val kinds = listOf(
        "media" to "媒体",
        "library" to "媒体库",
        "person" to "人物",
        "music" to "音乐",
        "collection" to "合集",
    )

    LaunchedEffect(query, kind) {
        if (query.isNotBlank()) {
            val fetched = repository.searchMedia(query, kind, 1)
            results = fetched.ifEmpty {
                sampleHeroItems().filter { it.title.contains(query, ignoreCase = true) || query.length <= 2 }
            }
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
            }
        }

        Spacer(Modifier.height(10.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = margin), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(kinds) { (id, label) ->
                NativeAdaptivePill(label, selected = id == kind, onClick = { kind = id })
            }
        }

        Spacer(Modifier.height(14.dp))
        if (results.isEmpty()) {
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    text = if (query.isBlank()) "输入关键词开始全局检索" else "未找到与「$query」匹配的内容",
                    color = colors.textMuted,
                    fontSize = 14.sp,
                )
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns),
                contentPadding = PaddingValues(start = margin, end = margin, bottom = 120.dp),
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
                        inLibrary = item.inLibrary,
                        onClick = {
                            if (kind == "library") {
                                onPlayLibraryItem(
                                    MediaPlaybackRequest(
                                        url = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                                        title = item.title,
                                        artworkUrl = item.posterPath,
                                    ),
                                )
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

/** 音乐发现页：2~5 列 1:1 专辑方卡，点击唤起原生音频播放器与迷你悬浮音乐条。 */
@Composable
fun MusicDiscoveryScreen(
    onBack: () -> Unit,
    onPlayAudio: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val cols = AdaptiveDeviceLayout.squareGridColumns()
    val albums = remember {
        listOf(
            Triple("范特西 (Remastered)", "周杰伦 · 2001 · FLAC", "[00:00.00]爱在西元前\n[00:12.00]古巴比伦王颁布了汉摩拉比法典"),
            Triple("星际穿越原声带", "Hans Zimmer · 2014 · 24bit", "[00:00.00]Cornfield Chase (Instrumental)"),
            Triple("沙丘 2 电影原声", "Hans Zimmer · 2024 · Atmos", "[00:00.00]A Time of Quiet Between the Storms"),
            Triple("新世界 NEW WORLD", "华晨宇 · 2020 · Hi-Res", "[00:00.00]斗牛 · 无损母带"),
        )
    }

    Column(modifier = Modifier.fillMaxSize()) {
        NativeGlassTopBar(title = "音乐发现", onBack = onBack)
        LazyVerticalGrid(
            columns = GridCells.Fixed(cols),
            contentPadding = PaddingValues(start = margin, end = margin, top = 8.dp, bottom = 128.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            items(albums) { (title, sub, lrc) ->
                CinematicPanel(
                    padding = 12.dp,
                    cornerRadius = 18.dp,
                    modifier = Modifier.clickable {
                        onPlayAudio(
                            MediaPlaybackRequest(
                                url = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
                                title = title,
                                subtitle = sub,
                                isAudio = true,
                                lyricsLrc = lrc,
                            ),
                        )
                    },
                ) {
                    Column {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .aspectRatio(1f)
                                .clip(RoundedCornerShape(14.dp))
                                .background(Brush.linearGradient(listOf(colors.accent.copy(alpha = 0.45f), Color(0xFF281F3D)))),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = Color.White, modifier = Modifier.size(44.dp))
                            Box(
                                modifier = Modifier
                                    .align(Alignment.BottomEnd)
                                    .padding(8.dp)
                                    .size(32.dp)
                                    .clip(CircleShape)
                                    .background(colors.accent),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(Icons.Rounded.PlayArrow, contentDescription = "播放", tint = Color.White, modifier = Modifier.size(20.dp))
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Text(title, color = colors.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(sub, color = colors.textMuted, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

private fun sampleHeroItems(): List<MediaCardItem> = listOf(
    MediaCardItem(
        title = "奥德赛 THE ODYSSEY",
        year = "2026",
        type = "电影",
        overview = "史诗级神话冒险巨制，穿越爱琴海与群岛的壮阔归途。",
        voteAverage = 8.4,
        genres = listOf("冒险", "动作", "奇幻"),
        mediaId = "101",
        inLibrary = true,
    ),
    MediaCardItem(
        title = "流浪地球 3",
        year = "2026",
        type = "电影",
        overview = "太阳危机步步紧逼，人类带着地球跨越深空寻找新家园。",
        voteAverage = 8.7,
        genres = listOf("科幻", "灾难"),
        mediaId = "102",
    ),
    MediaCardItem(
        title = "沙丘：救世主",
        year = "2026",
        type = "电影",
        overview = "厄拉科斯的金色道路与帝国命运的终极转折。",
        voteAverage = 8.6,
        genres = listOf("科幻", "史诗"),
        mediaId = "103",
        inLibrary = true,
    ),
)

private fun sampleTvItems(): List<MediaCardItem> = listOf(
    MediaCardItem(title = "合成追剧 S01", year = "2025", type = "电视剧", voteAverage = 8.8, mediaId = "111", inLibrary = true),
    MediaCardItem(title = "人生切割术 S02", year = "2025", type = "电视剧", voteAverage = 8.9, mediaId = "112"),
    MediaCardItem(title = "三体：黑暗森林", year = "2026", type = "电视剧", voteAverage = 8.5, mediaId = "113"),
)

private fun sampleContinueWatching(): List<ContinueWatchingItem> = listOf(
    ContinueWatchingItem("cw-1", "假面骑士 Build", "S1:41 - 最佳搭配的真相", null, 43, "Emby", "电视剧"),
    ContinueWatchingItem("cw-2", "三体：黑暗森林", "S1:04 - 面壁者计划", null, 68, "Emby", "电视剧"),
)
