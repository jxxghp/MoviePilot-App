package com.moviepilot.designsystem

import android.content.Context
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 骨架屏表面层级角色：
 * - [Tile]：外层独立海报、封面、头像、功能磁贴等块状基底（配 `0.6.dp` 微细高光/暗色描边）；
 * - [Bar]：位于 `CinematicPanel` 或卡片内部的文本行、胶囊、徽标与进度条占位。
 */
enum class SkeletonSurfaceRole {
    Tile,
    Bar,
}

/**
 * 通用业务列表骨架卡片版式枚举，1:1 匹配各业务模块真实卡片几何。
 */
enum class SkeletonCardStyle {
    PosterRow,
    ResourceCard,
    DownloadTaskCard,
    SiteCard,
    IconRow,
    PluginCard,
    WorkflowCard,
    MessageCard,
    FormPanel,
    LogLines,
    ChatBubbles,
}

/**
 * 三态主题（深色 Tonal / AMOLED 纯黑 / 浅色模式）骨架屏校准色阶。
 */
@Immutable
data class SkeletonPaletteTokens(
    val tileFill: Color,
    val tileBorder: Color,
    val barFill: Color,
    val sweepPeak: Color,
)

/**
 * 根据当前 `MoviePilotColors` 与 AMOLED 纯黑开关计算三态主题下的骨架屏底色、描边与扫光峰值。
 */
fun resolveSkeletonPalette(
    colors: MoviePilotColors,
    isPureBlack: Boolean,
): SkeletonPaletteTokens = when {
    colors.isDark && isPureBlack -> SkeletonPaletteTokens(
        tileFill = Color(0xFF151923),
        tileBorder = Color.White.copy(alpha = 0.10f),
        barFill = Color.White.copy(alpha = 0.105f),
        sweepPeak = Color.White.copy(alpha = 0.10f),
    )

    colors.isDark -> SkeletonPaletteTokens(
        tileFill = colors.surfaceContainerHigh.copy(alpha = 0.72f),
        tileBorder = Color.White.copy(alpha = 0.07f),
        barFill = Color.White.copy(alpha = 0.085f),
        sweepPeak = Color.White.copy(alpha = 0.085f),
    )

    else -> SkeletonPaletteTokens(
        tileFill = colors.surfaceContainerHigh.copy(alpha = 0.82f),
        tileBorder = Color.Black.copy(alpha = 0.05f),
        barFill = colors.textPrimary.copy(alpha = 0.075f),
        sweepPeak = Color.White.copy(alpha = 0.70f),
    )
}

/**
 * 页面级共享骨架流光时钟（`0f..1f`；省电模式或系统关闭动画时固定为 `-1f` 静态色块）。
 */
val LocalSkeletonShimmerPhase = compositionLocalOf<State<Float>?> { null }

/**
 * 获取或复用当前骨架屏共享流光时钟：
 * - 若外层已挂载 [ProvideSkeletonShimmer]，直接复用父级 `State<Float>` 避免重复动画器；
 * - 自动检测系统省电模式（`PowerManager.isPowerSaveMode`）与全局动画缩放（`ANIMATOR_DURATION_SCALE`），
 *   无障碍减弱动态效果或省电模式下返回静态 `-1f`，零帧唤醒开销。
 */
@Composable
fun rememberSkeletonShimmerPhase(): State<Float> {
    LocalSkeletonShimmerPhase.current?.let { return it }
    val context = LocalContext.current
    val animateShimmer = remember(context) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val powerSave = pm?.isPowerSaveMode == true
        val animScale = runCatching {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        }.getOrDefault(1f)
        !powerSave && animScale > 0f
    }
    if (!animateShimmer) {
        return remember { mutableFloatStateOf(-1f) }
    }
    val transition = rememberInfiniteTransition(label = "mpSkeletonShimmer")
    return transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1250, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "mpSkeletonPhase",
    )
}

/**
 * 为子树内所有骨架元素注入单一共享流光时钟；嵌套调用时自动透传外层时钟。
 */
@Composable
fun ProvideSkeletonShimmer(
    content: @Composable () -> Unit,
) {
    val existing = LocalSkeletonShimmerPhase.current
    if (existing != null) {
        content()
    } else {
        val phaseState = rememberSkeletonShimmerPhase()
        CompositionLocalProvider(
            LocalSkeletonShimmerPhase provides phaseState,
            content = content,
        )
    }
}

/**
 * 根级骨架屏无障碍语义修饰符：收拢内部碎片节点，向读屏器仅播报一次「正在加载内容」。
 */
fun Modifier.skeletonRootSemantics(description: String = "正在加载内容"): Modifier =
    this.clearAndSetSemantics { contentDescription = description }

/**
 * 子级装饰骨架块无障碍静默修饰符：屏蔽内部占位块的冗余读屏焦点。
 */
fun Modifier.skeletonChildSemantics(): Modifier =
    this.clearAndSetSemantics {}

/**
 * 仅在 Draw 阶段读取流光相位的 GPU 轻量级骨架填充修饰符：
 * - `phaseState.value` 仅在 `onDrawBehind` 闭包内读取，彻底跳过 Composition 与 Layout 阶段；
 * - 自动适配深色 Tonal、AMOLED 纯黑与浅色模式下的基底对比度与 `0.6.dp` 描边。
 */
@Composable
fun Modifier.nativeSkeletonFill(
    shape: Shape = RoundedCornerShape(8.dp),
    role: SkeletonSurfaceRole = SkeletonSurfaceRole.Bar,
    phaseState: State<Float>? = null,
): Modifier {
    val colors = LocalMoviePilotColors.current
    val isPureBlack = LocalAppearanceStore.current.pureBlackDark
    val palette = remember(colors, isPureBlack) { resolveSkeletonPalette(colors, isPureBlack) }
    val resolvedPhase = phaseState ?: rememberSkeletonShimmerPhase()

    return this.drawWithCache {
        val outline = shape.createOutline(size, layoutDirection, this)
        val baseFill = if (role == SkeletonSurfaceRole.Tile) palette.tileFill else palette.barFill
        val borderStrokePx = 0.6.dp.toPx()
        val w = size.width
        val h = size.height
        val bandWidth = (maxOf(w, h) * 0.85f).coerceAtLeast(120.dp.toPx())
        val travel = w + h * 0.45f + bandWidth * 2f
        val peak = palette.sweepPeak
        val halfPeak = peak.copy(alpha = peak.alpha * 0.42f)

        onDrawBehind {
            drawOutline(outline = outline, color = baseFill)

            val phase = resolvedPhase.value
            if (phase in 0f..1f && w > 0.5f && h > 0.5f) {
                val startX = -bandWidth - h * 0.22f + travel * phase
                val shimmerBrush = Brush.linearGradient(
                    colors = listOf(
                        Color.Transparent,
                        halfPeak,
                        peak,
                        halfPeak,
                        Color.Transparent,
                    ),
                    start = Offset(startX, 0f),
                    end = Offset(startX + bandWidth, h * 0.36f + bandWidth * 0.28f),
                )
                drawOutline(outline = outline, brush = shimmerBrush)
            }

            if (role == SkeletonSurfaceRole.Tile && w > borderStrokePx && h > borderStrokePx) {
                when (outline) {
                    is Outline.Rectangle -> {
                        val half = borderStrokePx / 2f
                        drawRect(
                            color = palette.tileBorder,
                            topLeft = Offset(half, half),
                            size = Size(w - borderStrokePx, h - borderStrokePx),
                            style = Stroke(width = borderStrokePx),
                        )
                    }

                    is Outline.Rounded -> {
                        val half = borderStrokePx / 2f
                        val rr = outline.roundRect
                        drawRoundRect(
                            color = palette.tileBorder,
                            topLeft = Offset(half, half),
                            size = Size(w - borderStrokePx, h - borderStrokePx),
                            cornerRadius = CornerRadius(
                                (rr.topLeftCornerRadius.x - half).coerceAtLeast(0f),
                                (rr.topLeftCornerRadius.y - half).coerceAtLeast(0f),
                            ),
                            style = Stroke(width = borderStrokePx),
                        )
                    }

                    is Outline.Generic -> {
                        drawPath(
                            path = outline.path,
                            color = palette.tileBorder,
                            style = Stroke(width = borderStrokePx),
                        )
                    }
                }
            }
        }
    }
}

/**
 * 基础圆角矩形流光骨架块。
 */
@Composable
fun NativeSkeletonBlock(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 8.dp,
    role: SkeletonSurfaceRole = SkeletonSurfaceRole.Bar,
) {
    Box(
        modifier = modifier
            .skeletonChildSemantics()
            .nativeSkeletonFill(
                shape = RoundedCornerShape(cornerRadius),
                role = role,
            ),
    )
}

/**
 * 基础正圆流光骨架块（适用于演职员头像、圆形图标与快捷按钮）。
 */
@Composable
fun NativeSkeletonCircle(
    size: Dp,
    modifier: Modifier = Modifier,
    role: SkeletonSurfaceRole = SkeletonSurfaceRole.Tile,
) {
    Box(
        modifier = modifier
            .size(size)
            .skeletonChildSemantics()
            .nativeSkeletonFill(
                shape = CircleShape,
                role = role,
            ),
    )
}

/**
 * 横向胶囊标签行骨架（适用于顶栏页签、媒体库筛选芯片、下载器与站点选择器加载占位）。
 */
@Composable
fun NativeInlineChipRowSkeleton(
    widths: List<Dp> = listOf(76.dp, 94.dp, 84.dp, 70.dp, 88.dp),
    height: Dp = if (AdaptiveDeviceLayout.isCompactHeight()) 34.dp else 38.dp,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    role: SkeletonSurfaceRole = SkeletonSurfaceRole.Tile,
    modifier: Modifier = Modifier,
) {
    ProvideSkeletonShimmer {
        LazyRow(
            userScrollEnabled = false,
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = modifier
                .fillMaxWidth()
                .skeletonRootSemantics(),
        ) {
            items(widths.size) { index ->
                Box(
                    modifier = Modifier
                        .width(widths[index])
                        .height(height)
                        .skeletonChildSemantics()
                        .nativeSkeletonFill(shape = CircleShape, role = role),
                )
            }
        }
    }
}

/**
 * 剧情简介 / 人物简介卡片内的多行正文流光占位条。
 */
@Composable
fun NativeOverviewLinesSkeleton(
    lines: Int = 3,
    modifier: Modifier = Modifier,
) {
    ProvideSkeletonShimmer {
        val fractions = listOf(1f, 0.92f, 0.66f, 0.84f, 0.58f)
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = modifier
                .fillMaxWidth()
                .skeletonRootSemantics(),
        ) {
            repeat(lines.coerceAtLeast(1)) { idx ->
                NativeSkeletonBlock(
                    cornerRadius = 6.dp,
                    role = SkeletonSurfaceRole.Bar,
                    modifier = Modifier
                        .fillMaxWidth(fractions[idx % fractions.size])
                        .height(13.dp),
                )
            }
        }
    }
}

/**
 * 发现页全屏首帧骨架（1:1 对齐 `discoverHeroHeight()` + `discoverPosterWidth()` + `isCompactHeight()` +
 * 2 组 `2:3` 竖版海报横栏 + 1 组 `238.dp` `16:9` 宽幅横卡横栏，彻底消除分类浏览上跳与中心裸转圈）。
 */
@Composable
fun NativeDiscoverSkeleton(
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val heroHeight = AdaptiveDeviceLayout.discoverHeroHeight()
    val posterWidth = AdaptiveDeviceLayout.discoverPosterWidth()
    val posterRadius = (colors.cardRadiusDp - 4).coerceIn(12, 20).dp
    val fadeBase = MaterialTheme.colorScheme.background

    ProvideSkeletonShimmer {
        LazyColumn(
            userScrollEnabled = false,
            modifier = modifier
                .fillMaxSize()
                .skeletonRootSemantics(),
            contentPadding = PaddingValues(bottom = bottomOverlayInset + 20.dp),
            verticalArrangement = Arrangement.spacedBy(if (compactHeight) 16.dp else 22.dp),
        ) {
            // 1. 全幅沉浸主视觉骨架
            item(key = "sk_discover_hero") {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(heroHeight),
                ) {
                    NativeSkeletonBlock(
                        cornerRadius = 0.dp,
                        role = SkeletonSurfaceRole.Tile,
                        modifier = Modifier.fillMaxSize(),
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    0.0f to Color.Transparent,
                                    0.45f to Color.Transparent,
                                    0.82f to fadeBase.copy(alpha = 0.85f),
                                    1.0f to fadeBase,
                                ),
                            ),
                    )
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                            .padding(horizontal = margin, vertical = if (compactHeight) 14.dp else 22.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(if (compactHeight) 6.dp else 10.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 12.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .width(if (compactHeight) 168.dp else 220.dp)
                                .height(if (compactHeight) 34.dp else 52.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .width(148.dp)
                                .height(13.dp),
                        )
                        if (!compactHeight) {
                            NativeSkeletonBlock(
                                cornerRadius = 6.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.76f)
                                    .widthIn(max = 420.dp)
                                    .height(12.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 6.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.52f)
                                    .widthIn(max = 300.dp)
                                    .height(12.dp),
                            )
                        }
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            NativeSkeletonBlock(
                                cornerRadius = 7.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 58.dp, height = 22.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 7.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 44.dp, height = 16.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 7.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 56.dp, height = 16.dp),
                            )
                        }
                    }
                }
            }

            // 2. 两组 2:3 竖版海报货架骨架（对应热门电影 / 热门剧集）
            items(2, key = { "sk_discover_poster_shelf_$it" }) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SkeletonSectionHeaderRow(modifier = Modifier.padding(horizontal = margin))
                    LazyRow(
                        userScrollEnabled = false,
                        contentPadding = PaddingValues(horizontal = margin),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(6) {
                            Column(
                                modifier = Modifier.width(posterWidth),
                                horizontalAlignment = Alignment.CenterHorizontally,
                            ) {
                                NativeSkeletonBlock(
                                    cornerRadius = posterRadius,
                                    role = SkeletonSurfaceRole.Tile,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(2f / 3f),
                                )
                                Spacer(Modifier.height(6.dp))
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier
                                        .fillMaxWidth(0.78f)
                                        .height(13.dp),
                                )
                                Spacer(Modifier.height(4.dp))
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier
                                        .fillMaxWidth(0.45f)
                                        .height(11.dp),
                                )
                            }
                        }
                    }
                }
            }

            // 3. 16:9 238.dp 宽幅趋势横卡货架骨架
            item(key = "sk_discover_wide_shelf") {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SkeletonSectionHeaderRow(modifier = Modifier.padding(horizontal = margin))
                    LazyRow(
                        userScrollEnabled = false,
                        contentPadding = PaddingValues(horizontal = margin),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        items(4) {
                            Column(
                                modifier = Modifier.width(238.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                NativeSkeletonBlock(
                                    cornerRadius = 16.dp,
                                    role = SkeletonSurfaceRole.Tile,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(16f / 9f),
                                )
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier
                                        .fillMaxWidth(0.72f)
                                        .height(14.dp),
                                )
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier
                                        .fillMaxWidth(0.44f)
                                        .height(12.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SkeletonSectionHeaderRow(
    showTrailing: Boolean = true,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 32.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        NativeSkeletonBlock(
            cornerRadius = 7.dp,
            role = SkeletonSurfaceRole.Bar,
            modifier = Modifier
                .width(104.dp)
                .height(20.dp),
        )
        if (showTrailing) {
            NativeSkeletonBlock(
                cornerRadius = 6.dp,
                role = SkeletonSurfaceRole.Bar,
                modifier = Modifier
                    .width(52.dp)
                    .height(14.dp),
            )
        }
    }
}

/**
 * 单个海报/专辑网格单元骨架（支持 2:3 竖版影视海报与 `inPanel = true` 的 1:1 音乐方卡面板）。
 */
@Composable
fun NativePosterGridCellSkeleton(
    aspectRatio: Float = 2f / 3f,
    inPanel: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val posterRadius = (colors.cardRadiusDp - 4).coerceIn(12, 20).dp
    if (inPanel) {
        CinematicPanel(
            padding = 10.dp,
            cornerRadius = 20.dp,
            modifier = modifier.skeletonChildSemantics(),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NativeSkeletonBlock(
                    cornerRadius = 14.dp,
                    role = SkeletonSurfaceRole.Tile,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(aspectRatio),
                )
                NativeSkeletonBlock(
                    cornerRadius = 5.dp,
                    role = SkeletonSurfaceRole.Bar,
                    modifier = Modifier
                        .fillMaxWidth(0.80f)
                        .height(14.dp),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.56f)
                            .height(12.dp),
                    )
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .width(34.dp)
                            .height(12.dp),
                    )
                }
            }
        }
    } else {
        Column(
            modifier = modifier
                .fillMaxWidth()
                .skeletonChildSemantics(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            NativeSkeletonBlock(
                cornerRadius = posterRadius,
                role = SkeletonSurfaceRole.Tile,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(aspectRatio),
            )
            Spacer(Modifier.height(6.dp))
            NativeSkeletonBlock(
                cornerRadius = 5.dp,
                role = SkeletonSurfaceRole.Bar,
                modifier = Modifier
                    .fillMaxWidth(0.78f)
                    .height(13.dp),
            )
            Spacer(Modifier.height(4.dp))
            NativeSkeletonBlock(
                cornerRadius = 5.dp,
                role = SkeletonSurfaceRole.Bar,
                modifier = Modifier
                    .fillMaxWidth(0.46f)
                    .height(11.dp),
            )
        }
    }
}

/**
 * 向现有 `LazyVerticalGrid` 内直接注入多列海报或音乐方卡骨架项，避免嵌套滚动容器。
 */
fun LazyGridScope.nativePosterGridSkeletonItems(
    columns: Int,
    count: Int = (columns * 3).coerceAtLeast(6),
    aspectRatio: Float = 2f / 3f,
    inPanel: Boolean = false,
) {
    items(
        count = count,
        key = { "sk_poster_grid_item_$it" },
    ) { idx ->
        NativePosterGridCellSkeleton(
            aspectRatio = aspectRatio,
            inPanel = inPanel,
            modifier = if (idx == 0) Modifier.skeletonRootSemantics() else Modifier.skeletonChildSemantics(),
        )
    }
}

/**
 * 自适应多列海报/音乐方卡网格骨架容器（支持可选全宽头部插槽，如音乐拼贴头图骨架）。
 */
@Composable
fun NativePosterGridSkeleton(
    columns: Int = AdaptiveDeviceLayout.posterGridColumns(),
    count: Int = (columns * 3).coerceAtLeast(6),
    aspectRatio: Float = 2f / 3f,
    inPanel: Boolean = false,
    contentPadding: PaddingValues = PaddingValues(
        start = AdaptiveDeviceLayout.horizontalMargin(),
        end = AdaptiveDeviceLayout.horizontalMargin(),
        top = 4.dp,
        bottom = LocalBottomOverlayInset.current + 20.dp,
    ),
    headerContent: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    ProvideSkeletonShimmer {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns.coerceAtLeast(1)),
            userScrollEnabled = false,
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(if (inPanel) 14.dp else 16.dp),
            modifier = modifier
                .fillMaxSize()
                .skeletonRootSemantics(),
        ) {
            if (headerContent != null) {
                item(
                    key = "sk_poster_grid_header",
                    span = { GridItemSpan(maxLineSpan) },
                ) {
                    headerContent()
                }
            }
            nativePosterGridSkeletonItems(
                columns = columns,
                count = count,
                aspectRatio = aspectRatio,
                inPanel = inPanel,
            )
        }
    }
}

/**
 * 1:1 匹配 `ExpressiveMixCollageHeader` 的音乐探索拼贴头图骨架（完整适配横屏 `useSideBySide` 并排布局与竖屏堆叠布局）。
 */
@Composable
fun ExpressiveMixCollageHeaderSkeleton(
    modifier: Modifier = Modifier,
) {
    val cfg = LocalConfiguration.current
    val compactHeight = cfg.screenHeightDp < 480
    val useSideBySide = cfg.screenWidthDp > cfg.screenHeightDp && (compactHeight || cfg.screenWidthDp >= 680)

    @Composable
    fun CollageGraphicSkeleton(compact: Boolean, boxModifier: Modifier) {
        val stageHeight = if (compact) 144.dp else 228.dp
        val capsuleW = if (compact) 108.dp else 166.dp
        val capsuleH = if (compact) 144.dp else 228.dp
        val satSz = if (compact) 52.dp else 76.dp
        Box(
            modifier = boxModifier.height(stageHeight),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(width = capsuleW, height = capsuleH)
                    .rotate(38f)
                    .skeletonChildSemantics()
                    .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Tile),
            )
            NativeSkeletonCircle(
                size = satSz,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .offset(x = if (compact) 10.dp else 18.dp, y = if (compact) 6.dp else 10.dp),
            )
            NativeSkeletonCircle(
                size = satSz,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = if (compact) (-10).dp else (-18).dp, y = if (compact) (-6).dp else (-8).dp),
            )
        }
    }

    ProvideSkeletonShimmer {
        if (useSideBySide) {
            Row(
                modifier = modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 4.dp)
                    .skeletonChildSemantics(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    NativeSkeletonBlock(
                        cornerRadius = 10.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .width(if (compactHeight) 136.dp else 168.dp)
                            .height(if (compactHeight) 26.dp else 32.dp),
                    )
                    NativeSkeletonBlock(
                        cornerRadius = 6.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.76f)
                            .height(14.dp),
                    )
                    Spacer(Modifier.height(2.dp))
                    Box(
                        modifier = Modifier
                            .width(116.dp)
                            .height(42.dp)
                            .skeletonChildSemantics()
                            .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Tile),
                    )
                }
                CollageGraphicSkeleton(
                    compact = true,
                    boxModifier = Modifier.width(if (compactHeight) 216.dp else 256.dp),
                )
            }
        } else {
            Column(
                modifier = modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .skeletonChildSemantics(),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 12.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .width(168.dp)
                                .height(38.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.78f)
                                .height(15.dp),
                        )
                    }
                    Spacer(Modifier.width(12.dp))
                    NativeSkeletonCircle(size = 84.dp, role = SkeletonSurfaceRole.Tile)
                }
                CollageGraphicSkeleton(compact = false, boxModifier = Modifier.fillMaxWidth())
            }
        }
    }
}

/**
 * 人物圆形头像网格骨架（`86.dp` 圆形肖像 + 姓名短条，1:1 匹配全局搜索「人物」分类）。
 */
@Composable
fun NativePersonGridSkeleton(
    columns: Int = AdaptiveDeviceLayout.posterGridColumns(),
    count: Int = (columns * 3).coerceAtLeast(6),
    contentPadding: PaddingValues = PaddingValues(
        start = AdaptiveDeviceLayout.horizontalMargin(),
        end = AdaptiveDeviceLayout.horizontalMargin(),
        bottom = LocalBottomOverlayInset.current + 24.dp,
    ),
    modifier: Modifier = Modifier,
) {
    ProvideSkeletonShimmer {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns.coerceAtLeast(1)),
            userScrollEnabled = false,
            contentPadding = contentPadding,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = modifier
                .fillMaxSize()
                .skeletonRootSemantics(),
        ) {
            items(count, key = { "sk_person_grid_$it" }) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.skeletonChildSemantics(),
                ) {
                    NativeSkeletonCircle(size = 86.dp, role = SkeletonSurfaceRole.Tile)
                    Spacer(Modifier.height(6.dp))
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .width(64.dp)
                            .height(13.dp),
                    )
                }
            }
        }
    }
}

/**
 * 横向剧集卡片货架骨架（默认 `228.dp × 128.dp` 16:9 横版单集剧照卡 + 集号标题与两行简介占位）。
 */
@Composable
fun NativeEpisodeShelfSkeleton(
    cardWidth: Dp = 228.dp,
    cardHeight: Dp = 128.dp,
    count: Int = 4,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    showHeader: Boolean = false,
    showSeasonPills: Boolean = false,
    headerPadding: PaddingValues = contentPadding,
    modifier: Modifier = Modifier,
) {
    ProvideSkeletonShimmer {
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = modifier
                .fillMaxWidth()
                .skeletonRootSemantics(),
        ) {
            if (showHeader) {
                Box(modifier = Modifier.padding(headerPadding)) {
                    SkeletonSectionHeaderRow()
                }
            }
            if (showSeasonPills) {
                NativeInlineChipRowSkeleton(
                    widths = listOf(88.dp, 88.dp, 92.dp),
                    height = 36.dp,
                    contentPadding = contentPadding,
                    role = SkeletonSurfaceRole.Tile,
                )
            }
            LazyRow(
                userScrollEnabled = false,
                contentPadding = contentPadding,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(count, key = { "sk_ep_card_$it" }) {
                    Column(
                        modifier = Modifier
                            .width(cardWidth)
                            .skeletonChildSemantics(),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 14.dp,
                            role = SkeletonSurfaceRole.Tile,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(cardHeight),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.76f)
                                .height(13.5.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.92f)
                                .height(11.5.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.58f)
                                .height(11.5.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * 横向 2:3 竖版海报货架骨架（默认 `118.dp` 宽度，1:1 对齐媒体库详情「类似作品」等横向推荐栏）。
 */
@Composable
fun NativePosterShelfSkeleton(
    posterWidth: Dp = 118.dp,
    count: Int = 6,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    showHeader: Boolean = false,
    headerPadding: PaddingValues = contentPadding,
    modifier: Modifier = Modifier,
) {
    ProvideSkeletonShimmer {
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = modifier
                .fillMaxWidth()
                .skeletonRootSemantics(),
        ) {
            if (showHeader) {
                Box(modifier = Modifier.padding(headerPadding)) {
                    SkeletonSectionHeaderRow(showTrailing = false)
                }
            }
            LazyRow(
                userScrollEnabled = false,
                contentPadding = contentPadding,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(count, key = { "sk_poster_shelf_card_$it" }) {
                    Column(
                        modifier = Modifier
                            .width(posterWidth)
                            .skeletonChildSemantics(),
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 13.dp,
                            role = SkeletonSurfaceRole.Tile,
                            modifier = Modifier
                                .fillMaxWidth()
                                .aspectRatio(2f / 3f),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.80f)
                                .height(13.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.46f)
                                .height(11.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * 演职员圆形头像横栏骨架。
 */
@Composable
fun NativeCastRowSkeleton(
    avatarSize: Dp = 72.dp,
    count: Int = 6,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    showHeader: Boolean = true,
    headerPadding: PaddingValues = contentPadding,
    modifier: Modifier = Modifier,
) {
    ProvideSkeletonShimmer {
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = modifier
                .fillMaxWidth()
                .skeletonRootSemantics(),
        ) {
            if (showHeader) {
                Box(modifier = Modifier.padding(headerPadding)) {
                    SkeletonSectionHeaderRow(showTrailing = false)
                }
            }
            LazyRow(
                userScrollEnabled = false,
                contentPadding = contentPadding,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                items(count, key = { "sk_cast_avatar_$it" }) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier
                            .width(82.dp)
                            .skeletonChildSemantics(),
                    ) {
                        NativeSkeletonCircle(size = avatarSize, role = SkeletonSurfaceRole.Tile)
                        Spacer(Modifier.height(7.dp))
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .width(58.dp)
                                .height(12.dp),
                        )
                        Spacer(Modifier.height(4.dp))
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .width(44.dp)
                                .height(10.5.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * 影视详情页与媒体库条目详情页全屏自适应骨架：
 * - 精准对齐竖屏手机、紧凑手机横屏（`isCompactLandscape`）与平板横屏（`isLandscape`）主视觉高度及按钮列数；
 * - 当 `showServerExtras = true` 时额外渲染「类似作品」海报栏、「链接」胶囊栏与 `236.dp`「媒体信息」音视频流卡片栏。
 */
@Composable
fun NativeMediaDetailSkeleton(
    heroHeight: Dp,
    isCompactLandscape: Boolean,
    isLandscape: Boolean,
    showServerExtras: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val fadeBase = MaterialTheme.colorScheme.background
    val btnHeight = if (isCompactLandscape) 44.dp else 50.dp

    ProvideSkeletonShimmer {
        LazyColumn(
            userScrollEnabled = false,
            modifier = modifier
                .fillMaxSize()
                .skeletonRootSemantics(),
            contentPadding = PaddingValues(bottom = 32.dp + bottomOverlayInset),
            verticalArrangement = Arrangement.spacedBy(if (isCompactLandscape) 14.dp else 18.dp),
        ) {
            // 1. 沉浸式详情头图与标题规格区
            item(key = "sk_detail_hero") {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(heroHeight),
                ) {
                    NativeSkeletonBlock(
                        cornerRadius = 0.dp,
                        role = SkeletonSurfaceRole.Tile,
                        modifier = Modifier.fillMaxSize(),
                    )
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    0.0f to Color.Transparent,
                                    0.46f to Color.Transparent,
                                    0.84f to fadeBase.copy(alpha = 0.88f),
                                    1.0f to fadeBase,
                                ),
                            ),
                    )
                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .fillMaxWidth()
                            .padding(horizontal = margin, vertical = if (isCompactLandscape) 8.dp else 14.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(if (isCompactLandscape) 5.dp else 8.dp),
                    ) {
                        if (showServerExtras) {
                            Box(
                                modifier = Modifier
                                    .width(96.dp)
                                    .height(24.dp)
                                    .skeletonChildSemantics()
                                    .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                            )
                        }
                        NativeSkeletonBlock(
                            cornerRadius = 12.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .width(if (isCompactLandscape) 172.dp else 224.dp)
                                .height(if (isCompactLandscape) 32.dp else 46.dp),
                        )
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            listOf(52.dp, 64.dp, 48.dp, 58.dp).forEach { w ->
                                Box(
                                    modifier = Modifier
                                        .width(w)
                                        .height(22.dp)
                                        .skeletonChildSemantics()
                                        .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                                )
                            }
                        }
                        if (!isCompactLandscape) {
                            NativeSkeletonBlock(
                                cornerRadius = 6.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .width(156.dp)
                                    .height(13.dp),
                            )
                        }
                    }
                }
            }

            // 2. 主操作双键/三键行
            item(key = "sk_detail_actions") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = margin),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    val count = if (isLandscape && showServerExtras) 3 else 2
                    repeat(count) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(btnHeight)
                                .skeletonChildSemantics()
                                .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Tile),
                        )
                    }
                }
            }

            // 3. 剧情简介面板
            item(key = "sk_detail_overview") {
                CinematicPanel(
                    padding = 16.dp,
                    showsShadow = false,
                    modifier = Modifier.padding(horizontal = margin),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 76.dp, height = 16.dp),
                        )
                        NativeOverviewLinesSkeleton(lines = 3)
                    }
                }
            }

            // 4. 16:9 剧集列表横栏骨架
            item(key = "sk_detail_episodes") {
                NativeEpisodeShelfSkeleton(
                    cardWidth = 228.dp,
                    cardHeight = 128.dp,
                    count = 4,
                    contentPadding = PaddingValues(horizontal = margin),
                    showHeader = true,
                    showSeasonPills = true,
                )
            }

            // 5. 演职员圆形头像横栏骨架
            item(key = "sk_detail_cast") {
                NativeCastRowSkeleton(
                    avatarSize = if (showServerExtras) 70.dp else 72.dp,
                    count = 6,
                    contentPadding = PaddingValues(horizontal = margin),
                    showHeader = true,
                )
            }

            // 6. 媒体服务器专属区块：类似作品 + 外部链接胶囊 + 236dp 媒体流信息规格卡
            if (showServerExtras) {
                item(key = "sk_detail_similar") {
                    NativePosterShelfSkeleton(
                        posterWidth = 118.dp,
                        count = 6,
                        contentPadding = PaddingValues(horizontal = margin),
                        showHeader = true,
                    )
                }

                item(key = "sk_detail_links") {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SkeletonSectionHeaderRow(
                            showTrailing = false,
                            modifier = Modifier.padding(horizontal = margin),
                        )
                        NativeInlineChipRowSkeleton(
                            widths = listOf(84.dp, 88.dp, 118.dp, 86.dp),
                            height = 36.dp,
                            contentPadding = PaddingValues(horizontal = margin),
                            role = SkeletonSurfaceRole.Tile,
                        )
                    }
                }

                item(key = "sk_detail_stream_cards") {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SkeletonSectionHeaderRow(
                            showTrailing = false,
                            modifier = Modifier.padding(horizontal = margin),
                        )
                        LazyRow(
                            userScrollEnabled = false,
                            contentPadding = PaddingValues(horizontal = margin),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            items(3, key = { "sk_stream_spec_$it" }) {
                                Column(
                                    modifier = Modifier
                                        .width(236.dp)
                                        .skeletonChildSemantics()
                                        .nativeSkeletonFill(
                                            shape = RoundedCornerShape(18.dp),
                                            role = SkeletonSurfaceRole.Tile,
                                        )
                                        .padding(horizontal = 16.dp, vertical = 15.dp),
                                    verticalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        NativeSkeletonCircle(size = 20.dp, role = SkeletonSurfaceRole.Bar)
                                        NativeSkeletonBlock(
                                            cornerRadius = 6.dp,
                                            role = SkeletonSurfaceRole.Bar,
                                            modifier = Modifier.size(width = 56.dp, height = 16.dp),
                                        )
                                    }
                                    repeat(5) { rIdx ->
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            NativeSkeletonBlock(
                                                cornerRadius = 5.dp,
                                                role = SkeletonSurfaceRole.Bar,
                                                modifier = Modifier.size(width = 42.dp, height = 12.dp),
                                            )
                                            NativeSkeletonBlock(
                                                cornerRadius = 5.dp,
                                                role = SkeletonSurfaceRole.Bar,
                                                modifier = Modifier
                                                    .fillMaxWidth(if (rIdx % 2 == 0) 0.78f else 0.56f)
                                                    .height(12.dp),
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

/**
 * 人物详情页自适应骨架（紧凑横屏 `72.dp` 横排肖像栏 vs 竖屏 `116.dp` 居中圆像 + 人物简介面板 + `posterGridColumns()` 参演海报网格）。
 */
@Composable
fun NativePersonDetailSkeleton(
    modifier: Modifier = Modifier,
) {
    val bottomOverlayInset = LocalBottomOverlayInset.current
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val compactHeight = AdaptiveDeviceLayout.isCompactHeight()
    val columns = AdaptiveDeviceLayout.posterGridColumns()

    ProvideSkeletonShimmer {
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns.coerceAtLeast(1)),
            userScrollEnabled = false,
            modifier = modifier
                .fillMaxSize()
                .skeletonRootSemantics(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = if (compactHeight) 12.dp else 20.dp,
                bottom = 28.dp + bottomOverlayInset,
            ),
            horizontalArrangement = Arrangement.spacedBy(11.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                if (compactHeight) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        NativeSkeletonCircle(size = 72.dp, role = SkeletonSurfaceRole.Tile)
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            NativeSkeletonBlock(
                                cornerRadius = 7.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 148.dp, height = 20.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 6.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 210.dp, height = 13.dp),
                            )
                        }
                    }
                } else {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        NativeSkeletonCircle(size = 116.dp, role = SkeletonSurfaceRole.Tile)
                        NativeSkeletonBlock(
                            cornerRadius = 8.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 148.dp, height = 24.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 196.dp, height = 13.dp),
                        )
                    }
                }
            }

            item(span = { GridItemSpan(maxLineSpan) }) {
                CinematicPanel(padding = 16.dp, showsShadow = false) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 76.dp, height = 16.dp),
                        )
                        NativeOverviewLinesSkeleton(lines = 4)
                    }
                }
            }

            item(span = { GridItemSpan(maxLineSpan) }) {
                SkeletonSectionHeaderRow()
            }

            nativePosterGridSkeletonItems(
                columns = columns,
                count = columns * 2,
                aspectRatio = 2f / 3f,
                inPanel = false,
            )
        }
    }
}

/**
 * 「我的」仪表盘全屏自适应骨架（`wideStatsRow` 4 列 vs 2×2 媒体库统计卡 + `cardGridColumns()` 双列配对存储圆环、下载器双速、7 天趋势柱图与后台服务卡）。
 */
@Composable
fun NativeDashboardSkeleton(
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val isPureBlack = LocalAppearanceStore.current.pureBlackDark
    val palette = remember(colors, isPureBlack) { resolveSkeletonPalette(colors, isPureBlack) }
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val effectiveWidth = AdaptiveDeviceLayout.effectiveContentWidthDp()
    val wideStatsRow = effectiveWidth >= 640
    val cardCols = AdaptiveDeviceLayout.cardGridColumns()
    val bottomOverlayInset = LocalBottomOverlayInset.current

    @Composable
    fun StatGridCardSkeleton(cardModifier: Modifier) {
        CinematicPanel(padding = 16.dp, modifier = cardModifier) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.Top,
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        NativeSkeletonBlock(
                            cornerRadius = 8.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 68.dp, height = 26.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 44.dp, height = 13.dp),
                        )
                    }
                    NativeSkeletonCircle(size = 38.dp, role = SkeletonSurfaceRole.Bar)
                }
                Box(
                    modifier = Modifier
                        .width(78.dp)
                        .height(21.dp)
                        .skeletonChildSemantics()
                        .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                )
            }
        }
    }

    @Composable
    fun StorageRingModuleSkeleton() {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SkeletonSectionHeaderRow()
            CinematicPanel(padding = 18.dp) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    Box(modifier = Modifier.size(92.dp), contentAlignment = Alignment.Center) {
                        Canvas(modifier = Modifier.fillMaxSize().skeletonChildSemantics()) {
                            val stroke = 10.dp.toPx()
                            val inset = stroke / 2f
                            drawArc(
                                color = palette.barFill,
                                startAngle = 0f,
                                sweepAngle = 360f,
                                useCenter = false,
                                topLeft = Offset(inset, inset),
                                size = Size(size.width - stroke, size.height - stroke),
                                style = Stroke(stroke, cap = StrokeCap.Round),
                            )
                        }
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 40.dp, height = 14.dp),
                        )
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 138.dp, height = 17.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 88.dp, height = 13.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 98.dp, height = 13.dp),
                        )
                    }
                }
            }
        }
    }

    @Composable
    fun DownloaderModuleSkeleton() {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SkeletonSectionHeaderRow()
            CinematicPanel(padding = 16.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        repeat(2) {
                            Row(
                                modifier = Modifier
                                    .weight(1f)
                                    .skeletonChildSemantics()
                                    .nativeSkeletonFill(
                                        shape = RoundedCornerShape(16.dp),
                                        role = SkeletonSurfaceRole.Bar,
                                    )
                                    .padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                NativeSkeletonCircle(size = 30.dp, role = SkeletonSurfaceRole.Bar)
                                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                    NativeSkeletonBlock(
                                        cornerRadius = 5.dp,
                                        role = SkeletonSurfaceRole.Bar,
                                        modifier = Modifier.size(width = 62.dp, height = 14.dp),
                                    )
                                    NativeSkeletonBlock(
                                        cornerRadius = 4.dp,
                                        role = SkeletonSurfaceRole.Bar,
                                        modifier = Modifier.size(width = 44.dp, height = 11.dp),
                                    )
                                }
                            }
                        }
                    }
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier.size(width = 136.dp, height = 12.dp),
                    )
                }
            }
        }
    }

    @Composable
    fun TrendChartModuleSkeleton() {
        val barRatios = listOf(0.36f, 0.58f, 0.44f, 0.80f, 0.52f, 0.68f, 0.46f)
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SkeletonSectionHeaderRow()
            CinematicPanel(padding = 16.dp, showsShadow = false) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(132.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.Bottom,
                ) {
                    barRatios.forEach { frac ->
                        Column(
                            modifier = Modifier.weight(1f),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Bottom,
                        ) {
                            NativeSkeletonBlock(
                                cornerRadius = 4.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 18.dp, height = 10.dp),
                            )
                            Spacer(Modifier.height(6.dp))
                            NativeSkeletonBlock(
                                cornerRadius = 6.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height((78f * frac).dp),
                            )
                            Spacer(Modifier.height(6.dp))
                            NativeSkeletonBlock(
                                cornerRadius = 4.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 26.dp, height = 10.dp),
                            )
                        }
                    }
                }
            }
        }
    }

    @Composable
    fun BackgroundServicesModuleSkeleton() {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SkeletonSectionHeaderRow()
            CinematicPanel(padding = 14.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
                    repeat(4) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            NativeSkeletonCircle(size = 20.dp, role = SkeletonSurfaceRole.Bar)
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(5.dp),
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    NativeSkeletonBlock(
                                        cornerRadius = 5.dp,
                                        role = SkeletonSurfaceRole.Bar,
                                        modifier = Modifier.size(width = 112.dp, height = 14.dp),
                                    )
                                    Box(
                                        modifier = Modifier
                                            .size(width = 40.dp, height = 18.dp)
                                            .skeletonChildSemantics()
                                            .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                                    )
                                }
                                NativeSkeletonBlock(
                                    cornerRadius = 4.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier.size(width = 148.dp, height = 11.dp),
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    ProvideSkeletonShimmer {
        LazyColumn(
            userScrollEnabled = false,
            modifier = modifier
                .fillMaxSize()
                .skeletonRootSemantics(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 16.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item(key = "sk_dash_user_profile") {
                CinematicPanel(padding = 18.dp) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        NativeSkeletonCircle(size = 62.dp, role = SkeletonSurfaceRole.Tile)
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            NativeSkeletonBlock(
                                cornerRadius = 6.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 118.dp, height = 20.dp),
                            )
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                listOf(72.dp, 64.dp, 46.dp).forEach { w ->
                                    Box(
                                        modifier = Modifier
                                            .size(width = w, height = 20.dp)
                                            .skeletonChildSemantics()
                                            .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                                    )
                                }
                            }
                            NativeSkeletonBlock(
                                cornerRadius = 5.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 156.dp, height = 13.dp),
                            )
                        }
                    }
                }
            }

            item(key = "sk_dash_media_stats") {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SkeletonSectionHeaderRow()
                    if (wideStatsRow) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            repeat(4) { StatGridCardSkeleton(Modifier.weight(1f)) }
                        }
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            repeat(2) { StatGridCardSkeleton(Modifier.weight(1f)) }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            repeat(2) { StatGridCardSkeleton(Modifier.weight(1f)) }
                        }
                    }
                }
            }

            if (cardCols >= 2) {
                item(key = "sk_dash_pair_1") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Box(Modifier.weight(1f)) { StorageRingModuleSkeleton() }
                        Box(Modifier.weight(1f)) { DownloaderModuleSkeleton() }
                    }
                }
                item(key = "sk_dash_pair_2") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Box(Modifier.weight(1f)) { TrendChartModuleSkeleton() }
                        Box(Modifier.weight(1f)) { BackgroundServicesModuleSkeleton() }
                    }
                }
            } else {
                item(key = "sk_dash_storage") { StorageRingModuleSkeleton() }
                item(key = "sk_dash_downloader") { DownloaderModuleSkeleton() }
                item(key = "sk_dash_trend") { TrendChartModuleSkeleton() }
                item(key = "sk_dash_services") { BackgroundServicesModuleSkeleton() }
            }
        }
    }
}

/**
 * 「更多（工作台）」全屏自适应骨架（分组 2..4 列自适应 `92.dp` 功能磁贴网格，1:1 对齐真实分组卡片结构）。
 */
@Composable
fun NativeWorkspaceSkeleton(
    modifier: Modifier = Modifier,
) {
    val margin = AdaptiveDeviceLayout.horizontalMargin()
    val gridCols = AdaptiveDeviceLayout.effectiveContentWidthDp().let { w ->
        when {
            w >= 1040 -> 4
            w >= 700 -> 3
            else -> 2
        }
    }
    val bottomOverlayInset = LocalBottomOverlayInset.current

    @Composable
    fun WorkspaceTileSkeleton(tileModifier: Modifier) {
        CinematicPanel(
            padding = 14.dp,
            showsShadow = false,
            modifier = tileModifier.heightIn(min = 92.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NativeSkeletonCircle(size = 40.dp, role = SkeletonSurfaceRole.Bar)
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier.size(width = 76.dp, height = 15.dp),
                    )
                    NativeSkeletonBlock(
                        cornerRadius = 4.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.78f)
                            .height(12.dp),
                    )
                }
            }
        }
    }

    @Composable
    fun TileSectionSkeleton(tileCount: Int) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NativeSkeletonBlock(
                cornerRadius = 5.dp,
                role = SkeletonSurfaceRole.Bar,
                modifier = Modifier
                    .padding(start = 4.dp)
                    .size(width = 96.dp, height = 14.dp),
            )
            val rows = (0 until tileCount).chunked(gridCols)
            rows.forEach { rowIndices ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    repeat(rowIndices.size) {
                        WorkspaceTileSkeleton(Modifier.weight(1f))
                    }
                    repeat(gridCols - rowIndices.size) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }

    ProvideSkeletonShimmer {
        LazyColumn(
            userScrollEnabled = false,
            modifier = modifier
                .fillMaxSize()
                .skeletonRootSemantics(),
            contentPadding = PaddingValues(
                start = margin,
                end = margin,
                top = 16.dp,
                bottom = bottomOverlayInset + 28.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item(key = "sk_ws_flow") { TileSectionSkeleton(tileCount = 6) }
            item(key = "sk_ws_plugins") { TileSectionSkeleton(tileCount = 3) }
            item(key = "sk_ws_subscribe") { TileSectionSkeleton(tileCount = 2) }
        }
    }
}

/**
 * 业务卡片列表/网格通用骨架组件：
 * - 完整覆盖 [SkeletonCardStyle] 全部 11 种布局版式；
 * - 支持响应式单列/双列网格（如 `columns = AdaptiveDeviceLayout.cardGridColumns()`）；
 * - 当嵌套在已有 `LazyColumn` 或 `verticalScroll` 弹窗内时，传入 `scrollable = false` 避免嵌套无限高度测量。
 */
@Composable
fun NativeCardListSkeleton(
    style: SkeletonCardStyle,
    count: Int = 5,
    columns: Int = 1,
    contentPadding: PaddingValues = PaddingValues(
        start = AdaptiveDeviceLayout.horizontalMargin(),
        end = AdaptiveDeviceLayout.horizontalMargin(),
        top = 8.dp,
        bottom = LocalBottomOverlayInset.current + 24.dp,
    ),
    scrollable: Boolean = true,
    compact: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val safeCols = columns.coerceAtLeast(1)
    val safeCount = count.coerceAtLeast(1)
    val verticalGap = if (compact) 8.dp else 12.dp

    ProvideSkeletonShimmer {
        if (!scrollable) {
            Column(
                verticalArrangement = Arrangement.spacedBy(verticalGap),
                modifier = modifier
                    .fillMaxWidth()
                    .padding(contentPadding)
                    .skeletonRootSemantics(),
            ) {
                val indices = (0 until safeCount).toList()
                if (safeCols == 1) {
                    indices.forEach { idx ->
                        SkeletonStyleItem(style = style, index = idx, compact = compact)
                    }
                } else {
                    indices.chunked(safeCols).forEach { rowIndices ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.Top,
                        ) {
                            rowIndices.forEach { idx ->
                                Box(Modifier.weight(1f)) {
                                    SkeletonStyleItem(style = style, index = idx, compact = compact)
                                }
                            }
                            repeat(safeCols - rowIndices.size) {
                                Spacer(Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        } else if (safeCols > 1) {
            LazyVerticalGrid(
                columns = GridCells.Fixed(safeCols),
                userScrollEnabled = false,
                contentPadding = contentPadding,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(verticalGap),
                modifier = modifier
                    .fillMaxSize()
                    .skeletonRootSemantics(),
            ) {
                items(safeCount, key = { "sk_card_grid_${style.name}_$it" }) { idx ->
                    SkeletonStyleItem(style = style, index = idx, compact = compact)
                }
            }
        } else {
            LazyColumn(
                userScrollEnabled = false,
                contentPadding = contentPadding,
                verticalArrangement = Arrangement.spacedBy(verticalGap),
                modifier = modifier
                    .fillMaxSize()
                    .skeletonRootSemantics(),
            ) {
                items(safeCount, key = { "sk_card_list_${style.name}_$it" }) { idx ->
                    SkeletonStyleItem(style = style, index = idx, compact = compact)
                }
            }
        }
    }
}

@Composable
private fun SkeletonStyleItem(
    style: SkeletonCardStyle,
    index: Int,
    compact: Boolean,
) {
    val colors = LocalMoviePilotColors.current
    when (style) {
        SkeletonCardStyle.PosterRow -> {
            CinematicPanel(padding = 14.dp, showsShadow = false) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    NativeSkeletonBlock(
                        cornerRadius = 11.dp,
                        role = SkeletonSurfaceRole.Tile,
                        modifier = Modifier
                            .width(68.dp)
                            .height(100.dp),
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            NativeSkeletonBlock(
                                cornerRadius = 6.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.62f)
                                    .height(16.dp),
                            )
                            Box(
                                modifier = Modifier
                                    .size(width = 52.dp, height = 20.dp)
                                    .skeletonChildSemantics()
                                    .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                            )
                        }
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.45f)
                                .height(13.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(4.dp),
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            repeat(3) {
                                Box(
                                    modifier = Modifier
                                        .size(width = 62.dp, height = 30.dp)
                                        .skeletonChildSemantics()
                                        .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                                )
                            }
                        }
                    }
                }
            }
        }

        SkeletonCardStyle.ResourceCard -> {
            CinematicPanel(padding = 15.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 132.dp, height = 14.dp),
                        )
                        Box(
                            modifier = Modifier
                                .size(width = 44.dp, height = 19.dp)
                                .skeletonChildSemantics()
                                .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(64.dp, 48.dp, 54.dp, 44.dp).forEach { w ->
                            Box(
                                modifier = Modifier
                                    .size(width = w, height = 20.dp)
                                    .skeletonChildSemantics()
                                    .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                            )
                        }
                    }
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.94f)
                            .height(15.dp),
                    )
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.68f)
                            .height(13.dp),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 108.dp, height = 12.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 64.dp, height = 12.dp),
                        )
                    }
                }
            }
        }

        SkeletonCardStyle.DownloadTaskCard -> {
            CinematicPanel(padding = 14.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 9.dp,
                            role = SkeletonSurfaceRole.Tile,
                            modifier = Modifier.size(34.dp),
                        )
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            NativeSkeletonBlock(
                                cornerRadius = 5.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.76f)
                                    .height(15.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 4.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.48f)
                                    .height(12.dp),
                            )
                        }
                        NativeSkeletonCircle(size = 28.dp, role = SkeletonSurfaceRole.Bar)
                        NativeSkeletonCircle(size = 28.dp, role = SkeletonSurfaceRole.Bar)
                    }
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(6.dp)
                            .skeletonChildSemantics()
                            .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 126.dp, height = 12.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 84.dp, height = 12.dp),
                        )
                    }
                }
            }
        }

        SkeletonCardStyle.SiteCard -> {
            CinematicPanel(padding = 16.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 12.dp,
                            role = SkeletonSurfaceRole.Tile,
                            modifier = Modifier.size(44.dp),
                        )
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier.size(width = 88.dp, height = 16.dp),
                                )
                                Box(
                                    modifier = Modifier
                                        .size(width = 46.dp, height = 19.dp)
                                        .skeletonChildSemantics()
                                        .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                                )
                            }
                            NativeSkeletonBlock(
                                cornerRadius = 4.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier.size(width = 138.dp, height = 12.dp),
                            )
                        }
                        Box(
                            modifier = Modifier
                                .size(width = 64.dp, height = 34.dp)
                                .skeletonChildSemantics()
                                .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 144.dp, height = 13.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 96.dp, height = 12.dp),
                        )
                    }
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(5.dp)
                            .skeletonChildSemantics()
                            .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                    )
                }
            }
        }

        SkeletonCardStyle.IconRow -> {
            val iconSz = if (compact) 28.dp else 38.dp
            val pad = if (compact) 10.dp else 14.dp
            CinematicPanel(padding = pad, showsShadow = false) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    NativeSkeletonBlock(
                        cornerRadius = if (compact) 8.dp else 10.dp,
                        role = SkeletonSurfaceRole.Tile,
                        modifier = Modifier.size(iconSz),
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(if (index % 2 == 0) 0.58f else 0.72f)
                                .height(if (compact) 13.dp else 15.dp),
                        )
                        if (!compact) {
                            NativeSkeletonBlock(
                                cornerRadius = 4.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.42f)
                                    .height(11.5.dp),
                            )
                        }
                    }
                    Box(
                        modifier = Modifier
                            .size(width = if (compact) 44.dp else 54.dp, height = if (compact) 20.dp else 24.dp)
                            .skeletonChildSemantics()
                            .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                    )
                }
            }
        }

        SkeletonCardStyle.PluginCard -> {
            CinematicPanel(padding = 16.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                NativeSkeletonBlock(
                                    cornerRadius = 5.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier.size(width = 112.dp, height = 16.dp),
                                )
                                NativeSkeletonBlock(
                                    cornerRadius = 4.dp,
                                    role = SkeletonSurfaceRole.Bar,
                                    modifier = Modifier.size(width = 36.dp, height = 12.dp),
                                )
                            }
                            NativeSkeletonBlock(
                                cornerRadius = 4.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.92f)
                                    .height(13.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 4.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.64f)
                                    .height(13.dp),
                            )
                        }
                        NativeSkeletonBlock(
                            cornerRadius = 14.dp,
                            role = SkeletonSurfaceRole.Tile,
                            modifier = Modifier.size(48.dp),
                        )
                    }
                    HorizontalDivider(color = colors.divider)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 88.dp, height = 12.dp),
                        )
                        Box(
                            modifier = Modifier
                                .size(width = 64.dp, height = 28.dp)
                                .skeletonChildSemantics()
                                .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                        )
                    }
                }
            }
        }

        SkeletonCardStyle.WorkflowCard -> {
            CinematicPanel(padding = 16.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 5.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.56f)
                                .height(16.dp),
                        )
                        Box(
                            modifier = Modifier
                                .size(width = 54.dp, height = 20.dp)
                                .skeletonChildSemantics()
                                .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                        )
                    }
                    NativeSkeletonBlock(
                        cornerRadius = 4.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.84f)
                            .height(13.dp),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.52f)
                                .height(12.dp),
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            repeat(2) {
                                Box(
                                    modifier = Modifier
                                        .size(width = 64.dp, height = 32.dp)
                                        .skeletonChildSemantics()
                                        .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                                )
                            }
                        }
                    }
                }
            }
        }

        SkeletonCardStyle.MessageCard -> {
            CinematicPanel(padding = 13.dp, cornerRadius = 20.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NativeSkeletonBlock(
                        cornerRadius = 12.dp,
                        role = SkeletonSurfaceRole.Tile,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(148.dp),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(width = 48.dp, height = 20.dp)
                                .skeletonChildSemantics()
                                .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 92.dp, height = 11.dp),
                        )
                    }
                    NativeSkeletonBlock(
                        cornerRadius = 5.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.74f)
                            .height(15.dp),
                    )
                    NativeSkeletonBlock(
                        cornerRadius = 4.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.92f)
                            .height(13.dp),
                    )
                    NativeSkeletonBlock(
                        cornerRadius = 4.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth(0.58f)
                            .height(13.dp),
                    )
                }
            }
        }

        SkeletonCardStyle.FormPanel -> {
            CinematicPanel(padding = 16.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 6.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 118.dp, height = 16.dp),
                        )
                        Box(
                            modifier = Modifier
                                .size(width = 52.dp, height = 20.dp)
                                .skeletonChildSemantics()
                                .nativeSkeletonFill(shape = CircleShape, role = SkeletonSurfaceRole.Bar),
                        )
                    }
                    NativeSkeletonBlock(
                        cornerRadius = 12.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(46.dp),
                    )
                    NativeSkeletonBlock(
                        cornerRadius = 12.dp,
                        role = SkeletonSurfaceRole.Bar,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(if (index % 2 == 0) 46.dp else 72.dp),
                    )
                }
            }
        }

        SkeletonCardStyle.LogLines -> {
            val widths = listOf(0.90f, 0.74f, 0.96f, 0.66f, 0.84f)
            CinematicPanel(padding = 10.dp, showsShadow = false) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier.size(width = 42.dp, height = 12.dp),
                        )
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(widths[index % widths.size])
                                .height(11.dp),
                        )
                    }
                    if (index % 2 == 0) {
                        NativeSkeletonBlock(
                            cornerRadius = 4.dp,
                            role = SkeletonSurfaceRole.Bar,
                            modifier = Modifier
                                .fillMaxWidth(0.58f)
                                .height(11.dp),
                        )
                    }
                }
            }
        }

        SkeletonCardStyle.ChatBubbles -> {
            val isUser = index % 2 == 1
            if (isUser) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    NativeSkeletonBlock(
                        cornerRadius = 20.dp,
                        role = SkeletonSurfaceRole.Tile,
                        modifier = Modifier
                            .fillMaxWidth(0.56f)
                            .widthIn(max = 280.dp)
                            .height(42.dp),
                    )
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.Top,
                ) {
                    NativeSkeletonCircle(size = 32.dp, role = SkeletonSurfaceRole.Tile)
                    CinematicPanel(
                        padding = 14.dp,
                        showsShadow = false,
                        modifier = Modifier.weight(1f),
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            NativeSkeletonBlock(
                                cornerRadius = 5.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.88f)
                                    .height(14.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 5.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.95f)
                                    .height(14.dp),
                            )
                            NativeSkeletonBlock(
                                cornerRadius = 5.dp,
                                role = SkeletonSurfaceRole.Bar,
                                modifier = Modifier
                                    .fillMaxWidth(0.54f)
                                    .height(14.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}
