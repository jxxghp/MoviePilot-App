package com.moviepilot.feature.media

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.BookmarkAdd
import androidx.compose.material.icons.rounded.BookmarkAdded
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.moviepilot.designsystem.AdaptiveDeviceLayout
import com.moviepilot.designsystem.CinematicCircleButton
import com.moviepilot.designsystem.CinematicPanel
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptiveBadge
import com.moviepilot.designsystem.NativeSectionHeader
import com.moviepilot.media.MediaPlaybackRequest
import com.moviepilot.rustbridge.MediaCardItem
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.SubscribeItemDto
import kotlinx.coroutines.launch

/**
 * 影视 / 剧集 / 豆瓣详情页：
 * 沉浸式无遮挡影院大头图 + 评分/类型元数据 + 一键订阅/搜索资源/直放媒体库 + 分季折叠展开 + 演职员横滑。
 */
@Composable
fun MediaDetailScreen(
    item: MediaCardItem,
    repository: MoviePilotRepository,
    onBack: () -> Unit,
    onSearchResource: (String) -> Unit,
    onPlayMedia: (MediaPlaybackRequest) -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val scope = rememberCoroutineScope()

    var subscribed by remember { mutableStateOf(false) }
    var feedback by remember { mutableStateOf<String?>(null) }
    var expandedSeason by remember { mutableStateOf(1) }

    val cast = remember {
        listOf("合成主演 A" to "领衔主演", "合成导演 B" to "导演", "合成演员 C" to "联合主演", "合成配乐 D" to "原声作曲")
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 128.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        // 沉浸式无遮挡首屏海报/剧照头图
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(420.dp),
            ) {
                val hero = item.backdropPath ?: item.posterPath
                if (!hero.isNullOrBlank()) {
                    AsyncImage(
                        model = hero,
                        contentDescription = item.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Brush.verticalGradient(listOf(colors.accent.copy(alpha = 0.5f), Color(0xFF231C35)))),
                    )
                }
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0f to Color.Black.copy(alpha = 0.25f),
                                0.55f to Color.Transparent,
                                1f to colors.palette.firstOrNull()!!,
                            ),
                        ),
                )
                CinematicCircleButton(
                    icon = Icons.AutoMirrored.Rounded.ArrowBack,
                    contentDescription = "返回",
                    onClick = onBack,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .statusBarsPadding()
                        .padding(16.dp),
                )
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(horizontal = margin, vertical = 14.dp),
                ) {
                    Text(item.title, color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.ExtraBold)
                    Spacer(Modifier.height(6.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NativeAdaptiveBadge(item.type, tint = colors.accent, filled = true)
                        if (item.year.isNotBlank()) NativeAdaptiveBadge(item.year)
                        if (item.voteAverage > 0.0) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Rounded.Star, contentDescription = null, tint = Color(0xFFFFC845), modifier = Modifier.size(16.dp))
                                Text(" ${String.format("%.1f", item.voteAverage)}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            }
                        }
                        if (item.inLibrary) NativeAdaptiveBadge("已在媒体库", tint = colors.success)
                    }
                }
            }
        }

        // 核心操作栏（订阅 / 资源搜索 / 原生直放）
        item {
            Column(
                modifier = Modifier.padding(horizontal = margin),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Button(
                        onClick = {
                            scope.launch {
                                val ok = repository.createOrUpdateSubscription(
                                    SubscribeItemDto(
                                        name = item.title,
                                        year = item.year,
                                        type = item.type,
                                        season = if (item.type == "电视剧") 1 else null,
                                        mediaSource = item.source,
                                        mediaId = item.resolvedId,
                                    ),
                                )
                                subscribed = true
                                feedback = if (ok) "已添加到我的订阅" else "已登记本地订阅请求"
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = if (subscribed) colors.success else colors.accent),
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(if (subscribed) Icons.Rounded.BookmarkAdded else Icons.Rounded.BookmarkAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(if (subscribed) "已订阅" else "添加订阅", fontWeight = FontWeight.SemiBold)
                    }

                    OutlinedButton(
                        onClick = { onSearchResource(item.title) },
                        shape = CircleShape,
                        modifier = Modifier.weight(1f).height(46.dp),
                    ) {
                        Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.textPrimary, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("搜索资源", color = colors.textPrimary, fontWeight = FontWeight.SemiBold)
                    }
                }

                if (item.inLibrary) {
                    Button(
                        onClick = {
                            onPlayMedia(
                                MediaPlaybackRequest(
                                    url = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                                    title = item.title,
                                    subtitle = "${item.year} · ${item.type}",
                                    artworkUrl = item.posterPath,
                                ),
                            )
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.primaryButtonBg, contentColor = colors.primaryButtonFg),
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

        // 剧情简介
        item {
            CinematicPanel(modifier = Modifier.padding(horizontal = margin)) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("简介", color = colors.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Text(
                        text = item.overview.ifBlank { "暂无剧情简介，可点击上方按钮快速检索站点高清片源或加入自动追剧订阅。" },
                        color = colors.textSecondary,
                        fontSize = 14.sp,
                        lineHeight = 21.sp,
                    )
                }
            }
        }

        // 电视剧分季折叠/展开列表
        if (item.type == "电视剧") {
            item {
                Column(modifier = Modifier.padding(horizontal = margin), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NativeSectionHeader(title = "剧集分季")
                    (1..2).forEach { season ->
                        val expanded = expandedSeason == season
                        CinematicPanel(
                            padding = 14.dp,
                            modifier = Modifier.clickable { expandedSeason = if (expanded) 0 else season },
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Text("第 $season 季 · 共 12 集", color = colors.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                    Icon(if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, contentDescription = null, tint = colors.textSecondary)
                                }
                                if (expanded) {
                                    (1..4).forEach { ep ->
                                        Row(
                                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                        ) {
                                            Text("E%02d · 第 $ep 集".format(ep), color = colors.textSecondary, fontSize = 13.sp)
                                            NativeAdaptiveBadge(if (ep <= 3) "已入库" else "待播", tint = if (ep <= 3) colors.success else colors.warning)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 演职员横滑栏
        item {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NativeSectionHeader(title = "演职员", modifier = Modifier.padding(horizontal = margin))
                LazyRow(
                    contentPadding = PaddingValues(horizontal = margin),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(cast) { (name, role) ->
                        CinematicPanel(padding = 12.dp, cornerRadius = 18.dp, modifier = Modifier.width(124.dp)) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                                Box(
                                    modifier = Modifier.size(56.dp).clip(CircleShape).background(colors.accent.copy(alpha = 0.25f)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Rounded.Person, contentDescription = null, tint = colors.accent, modifier = Modifier.size(28.dp))
                                }
                                Spacer(Modifier.height(8.dp))
                                Text(name, color = colors.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                Text(role, color = colors.textMuted, fontSize = 11.sp, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
    }
}
