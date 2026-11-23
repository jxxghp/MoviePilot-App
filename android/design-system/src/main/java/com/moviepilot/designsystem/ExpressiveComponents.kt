package com.moviepilot.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlin.math.PI
import kotlin.math.sin

/**
 * Material 3 Expressive 圆形实色 Tonal 头部操作圆钮。
 */
@Composable
fun ExpressiveHeaderActionButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    containerColor: Color = LocalMoviePilotColors.current.headerButtonBg,
    contentColor: Color = LocalMoviePilotColors.current.headerButtonFg,
    size: Dp = 44.dp,
    modifier: Modifier = Modifier,
) {
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = containerColor,
        contentColor = contentColor,
        modifier = modifier
            .minimumInteractiveComponentSize()
            .size(size),
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            Icon(
                imageVector = icon,
                contentDescription = contentDescription,
                tint = contentColor,
                modifier = Modifier.size(22.dp),
            )
        }
    }
}

/**
 * Material 3 Expressive 染色顶栏 + 胶囊页签 + 顶部 28dp 大圆角正文 Sheet 骨架：
 * - 顶部染色画布（`colors.headerTint`）承载大字号主色标题与圆形 Tonal 操作钮；
 * - 中部可选承载 `ExpressivePillTabRow`（高亮主色胶囊 + 底部迷你居中小横杠指示条）；
 * - 下方正文区以 28dp 顶部圆角平滑浮起，层次清晰分明。
 */
@Composable
fun ExpressiveTintedScaffold(
    title: String,
    subtitle: String? = null,
    onBack: (() -> Unit)? = null,
    actions: (@Composable RowScope.() -> Unit)? = null,
    headerExtra: (@Composable ColumnScope.() -> Unit)? = null,
    modifier: Modifier = Modifier,
    sheetContent: @Composable BoxScope.() -> Unit,
) {
    val colors = LocalMoviePilotColors.current
    val sheetShape = RoundedCornerShape(
        topStart = colors.sheetRadiusDp.dp,
        topEnd = colors.sheetRadiusDp.dp,
    )

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.headerTint),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(top = 8.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = if (onBack != null) 12.dp else 20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (onBack != null) {
                    ExpressiveHeaderActionButton(
                        icon = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "返回上一级",
                        onClick = onBack,
                    )
                }
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = title,
                        color = colors.headerTitle,
                        style = if (onBack == null) {
                            MaterialTheme.typography.headlineLarge
                        } else {
                            MaterialTheme.typography.headlineMedium
                        },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (!subtitle.isNullOrBlank()) {
                        Text(
                            text = subtitle,
                            color = colors.headerTitle.copy(alpha = 0.72f),
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                if (actions != null) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        content = actions,
                    )
                }
            }
            if (headerExtra != null) {
                headerExtra()
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(sheetShape)
                .background(colors.sheetSurface, sheetShape),
            content = sheetContent,
        )
    }
}

/**
 * Material 3 Expressive 表现力胶囊页签栏：
 * - 选中页签呈现发光柔和主色胶囊 + 深墨色粗体文字，且正下方浮现一枚精致的 24×3dp 圆角小横杠指示器；
 * - 未选中页签采用沉稳深色胶囊，与外层染色顶栏形成利落层次，支持等宽平分或横向滚动。
 */
@Composable
fun ExpressivePillTabRow(
    tabs: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    scrollable: Boolean = false,
    onTintedHeader: Boolean = false,
    modifier: Modifier = Modifier,
) {
    if (tabs.isEmpty()) return
    val colors = LocalMoviePilotColors.current
    val scheme = MaterialTheme.colorScheme
    val safeIndex = selectedIndex.coerceIn(0, tabs.lastIndex)
    val inactiveBg = if (onTintedHeader) {
        if (colors.isDark) Color(0xFF0A1220).copy(alpha = 0.78f) else Color.White.copy(alpha = 0.72f)
    } else {
        scheme.surfaceContainerLow
    }
    val inactiveFg = if (onTintedHeader) {
        if (colors.isDark) Color(0xFFE5ECFA) else colors.headerTitle
    } else {
        colors.textSecondary
    }

    @Composable
    fun TabItem(idx: Int, label: String, itemModifier: Modifier) {
        val selected = idx == safeIndex
        val bg by animateColorAsState(
            targetValue = if (selected) scheme.primary else inactiveBg,
            animationSpec = tween(200),
            label = "pillTabBg",
        )
        val fg by animateColorAsState(
            targetValue = if (selected) scheme.onPrimary else inactiveFg,
            animationSpec = tween(200),
            label = "pillTabFg",
        )
        val indicatorWidth by animateDpAsState(
            targetValue = if (selected) 24.dp else 0.dp,
            animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
            label = "pillTabInd",
        )

        Column(
            modifier = itemModifier,
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                modifier = Modifier
                    .then(if (scrollable) Modifier else Modifier.fillMaxWidth())
                    .heightIn(min = 44.dp)
                    .clip(CircleShape)
                    .background(bg, CircleShape)
                    .clickable { onSelect(idx) }
                    .padding(horizontal = 20.dp, vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    color = fg,
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontSize = 14.sp,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.SemiBold,
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box(
                modifier = Modifier
                    .width(indicatorWidth)
                    .height(3.dp)
                    .clip(CircleShape)
                    .background(if (selected) scheme.primary else Color.Transparent),
            )
        }
    }

    if (scrollable) {
        val listState = rememberLazyListState()
        LaunchedEffect(safeIndex, tabs.size) {
            if (safeIndex in tabs.indices) {
                listState.animateScrollToItem(safeIndex)
            }
        }
        LazyRow(
            state = listState,
            modifier = modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            itemsIndexed(tabs) { idx, label ->
                TabItem(idx, label, Modifier)
            }
        }
    } else {
        Row(
            modifier = modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            tabs.forEachIndexed { idx, label ->
                TabItem(idx, label, Modifier.weight(1f))
            }
        }
    }
}

/** 表现力主操作胶囊钮（用于 Sheet 顶部高频动作）。 */
@Composable
fun ExpressiveActionPill(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
    containerColor: Color = MaterialTheme.colorScheme.secondaryContainer,
    contentColor: Color = MaterialTheme.colorScheme.onSecondaryContainer,
    modifier: Modifier = Modifier,
) {
    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = containerColor,
        contentColor = contentColor,
        modifier = modifier.heightIn(min = 42.dp),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon, contentDescription = null, tint = contentColor, modifier = Modifier.size(18.dp))
            Text(label, color = contentColor, style = MaterialTheme.typography.labelLarge)
        }
    }
}

/**
 * Material 3 Expressive 波浪进度条（Wavy Progress Slider）：
 * - 已播放段落绘制实时流动的柔和正弦波浪线（播放时平滑起伏，暂停时优雅展平为直线）；
 * - 进度端点配精致实心圆滑块，支持点击与拖动精准定位。
 */
@Composable
fun ExpressiveWavySlider(
    value: Float,
    onValueChange: (Float) -> Unit,
    onValueChangeFinished: () -> Unit,
    isPlaying: Boolean,
    activeColor: Color,
    inactiveColor: Color,
    modifier: Modifier = Modifier,
) {
    val clamped = value.coerceIn(0f, 1f)
    var widthPx by remember { mutableFloatStateOf(1f) }
    var isDragging by remember { mutableStateOf(false) }

    val infiniteTransition = rememberInfiniteTransition(label = "wavyPhase")
    val phase by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = (2.0 * PI).toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1750, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "wavyShift",
    )
    val amplitudeFactor by animateFloatAsState(
        targetValue = if (isPlaying && !isDragging) 1f else 0f,
        animationSpec = tween(durationMillis = 320),
        label = "wavyAmplitude",
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(34.dp)
            .onSizeChanged { widthPx = it.width.toFloat().coerceAtLeast(1f) }
            .pointerInput(Unit) {
                detectTapGestures { offset ->
                    val ratio = (offset.x / widthPx).coerceIn(0f, 1f)
                    onValueChange(ratio)
                    onValueChangeFinished()
                }
            }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { offset ->
                        isDragging = true
                        onValueChange((offset.x / widthPx).coerceIn(0f, 1f))
                    },
                    onDragEnd = {
                        isDragging = false
                        onValueChangeFinished()
                    },
                    onDragCancel = {
                        isDragging = false
                        onValueChangeFinished()
                    },
                    onHorizontalDrag = { change, _ ->
                        change.consume()
                        onValueChange((change.position.x / widthPx).coerceIn(0f, 1f))
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val cy = size.height / 2f
            val padX = 10.dp.toPx()
            val trackW = (size.width - padX * 2f).coerceAtLeast(1f)
            val thumbX = padX + trackW * clamped
            val strokePx = 4.dp.toPx()

            // 未播放段：简洁半透直轨
            if (thumbX < size.width - padX) {
                drawLine(
                    color = inactiveColor,
                    start = Offset(thumbX + 6.dp.toPx(), cy),
                    end = Offset(size.width - padX, cy),
                    strokeWidth = strokePx,
                    cap = StrokeCap.Round,
                )
            }

            // 已播放段：Material 3 Expressive 流动正弦波浪线
            val activeLen = (thumbX - padX).coerceAtLeast(0f)
            if (activeLen > 2f) {
                val wavelength = 24.dp.toPx()
                val amp = 3.8.dp.toPx() * amplitudeFactor
                val path = Path()
                val steps = (activeLen / 2.5f).toInt().coerceIn(8, 220)
                for (i in 0..steps) {
                    val t = i.toFloat() / steps.toFloat()
                    val x = padX + activeLen * t
                    // 靠近滑块处轻微收口避免突变
                    val endTaper = ((1f - t) * 5f).coerceIn(0f, 1f)
                    val y = cy + sin((x / wavelength) * 2.0 * PI - phase.toDouble()).toFloat() * amp * endTaper
                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                }
                drawPath(
                    path = path,
                    color = activeColor,
                    style = Stroke(width = strokePx, cap = StrokeCap.Round, join = StrokeJoin.Round),
                )
            }

            // 精致实心圆滑块
            val thumbRadius = if (isDragging) 9.5.dp.toPx() else 7.5.dp.toPx()
            drawCircle(
                color = activeColor,
                radius = thumbRadius,
                center = Offset(thumbX, cy),
            )
        }
    }
}

/**
 * Material 3 Expressive 形变播控主按钮（Morphing Squircle / Circle Play-Pause Button）：
 * - 播放时优雅变形为 `22.dp` 圆角方形（Squircle），暂停时弹回饱满正圆（CircleShape）；
 * - 采用高对比柔和主色底面 + 深墨色图标，兼具视觉焦点与触感张力。
 */
@Composable
fun ExpressiveMorphingPlayButton(
    isPlaying: Boolean,
    onClick: () -> Unit,
    containerColor: Color,
    contentColor: Color,
    width: Dp = 84.dp,
    height: Dp = 76.dp,
    iconSize: Dp = 36.dp,
    modifier: Modifier = Modifier,
) {
    val haptic = LocalHapticFeedback.current
    val radius by animateDpAsState(
        targetValue = if (isPlaying) 22.dp else (height / 2),
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium,
        ),
        label = "morphPlayRadius",
    )
    val shape = RoundedCornerShape(radius)
    Surface(
        onClick = {
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            onClick()
        },
        shape = shape,
        color = containerColor,
        contentColor = contentColor,
        modifier = modifier.size(width = width, height = height),
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            Icon(
                imageVector = if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                contentDescription = if (isPlaying) "暂停" else "播放",
                tint = contentColor,
                modifier = Modifier.size(iconSize),
            )
        }
    }
}

/** 连体双圆钮（外侧大圆角 22dp + 内侧微圆角 8dp，紧密成组）。 */
@Composable
fun ExpressiveSplitIconPair(
    firstIcon: ImageVector,
    firstDesc: String,
    firstActive: Boolean = false,
    onFirstClick: () -> Unit,
    secondIcon: ImageVector,
    secondDesc: String,
    secondActive: Boolean = false,
    onSecondClick: () -> Unit,
    containerColor: Color,
    activeContainerColor: Color,
    contentColor: Color,
    activeContentColor: Color,
    modifier: Modifier = Modifier,
) {
    val leftShape = RoundedCornerShape(topStart = 22.dp, bottomStart = 22.dp, topEnd = 8.dp, bottomEnd = 8.dp)
    val rightShape = RoundedCornerShape(topStart = 8.dp, bottomStart = 8.dp, topEnd = 22.dp, bottomEnd = 22.dp)
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            onClick = onFirstClick,
            shape = leftShape,
            color = if (firstActive) activeContainerColor else containerColor,
            modifier = Modifier.size(width = 48.dp, height = 42.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = firstIcon,
                    contentDescription = firstDesc,
                    tint = if (firstActive) activeContentColor else contentColor,
                    modifier = Modifier.size(21.dp),
                )
            }
        }
        Surface(
            onClick = onSecondClick,
            shape = rightShape,
            color = if (secondActive) activeContainerColor else containerColor,
            modifier = Modifier.size(width = 48.dp, height = 42.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = secondIcon,
                    contentDescription = secondDesc,
                    tint = if (secondActive) activeContentColor else contentColor,
                    modifier = Modifier.size(21.dp),
                )
            }
        }
    }
}

data class ExpressiveDockAction(
    val icon: ImageVector,
    val contentDescription: String,
    val active: Boolean = false,
    val onClick: () -> Unit,
)

/** 底部沉入式连体播控胶囊坞（外层深色 30dp 胶囊，内部 3~4 枚圆角分段按钮）。 */
@Composable
fun ExpressiveGroupedActionDock(
    actions: List<ExpressiveDockAction>,
    dockColor: Color,
    buttonColor: Color,
    activeButtonColor: Color,
    iconColor: Color,
    activeIconColor: Color,
    modifier: Modifier = Modifier,
) {
    if (actions.isEmpty()) return
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(30.dp))
            .background(dockColor, RoundedCornerShape(30.dp))
            .padding(6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        actions.forEachIndexed { idx, action ->
            val shape = when {
                actions.size == 1 -> CircleShape
                idx == 0 -> RoundedCornerShape(topStart = 24.dp, bottomStart = 24.dp, topEnd = 10.dp, bottomEnd = 10.dp)
                idx == actions.lastIndex -> RoundedCornerShape(topStart = 10.dp, bottomStart = 10.dp, topEnd = 24.dp, bottomEnd = 24.dp)
                else -> RoundedCornerShape(10.dp)
            }
            Surface(
                onClick = action.onClick,
                shape = shape,
                color = if (action.active) activeButtonColor else buttonColor,
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = action.icon,
                        contentDescription = action.contentDescription,
                        tint = if (action.active) activeIconColor else iconColor,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }
        }
    }
}

/**
 * Material 3 Expressive 有机几何拼贴主视觉（斜置大胶囊海报 + 左上/右下双圆形卫星封面 + 右上大圆形主色播放按钮）：
 * 适用于音乐发现与精选推荐头图，呈现鲜明的表现力视觉辨识度。
 */
@Composable
fun ExpressiveMixCollageHeader(
    headline: String,
    subtitle: String,
    artworkUrls: List<String?>,
    onPlayClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = headline,
                    color = colors.textPrimary,
                    style = MaterialTheme.typography.displayLarge,
                    maxLines = 2,
                )
                Text(
                    text = subtitle,
                    color = colors.textSecondary,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                )
            }
            Spacer(Modifier.width(12.dp))
            Surface(
                onClick = onPlayClick,
                shape = CircleShape,
                color = scheme.primary,
                contentColor = scheme.onPrimary,
                modifier = Modifier
                    .size(84.dp)
                    .shadow(10.dp, CircleShape, ambientColor = scheme.primary.copy(alpha = 0.35f)),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = Icons.Rounded.PlayArrow,
                        contentDescription = "播放精选",
                        tint = scheme.onPrimary,
                        modifier = Modifier.size(36.dp),
                    )
                }
            }
        }

        // 斜置大胶囊主封面 + 左右双圆形卫星封面
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(228.dp),
            contentAlignment = Alignment.Center,
        ) {
            // 中央斜置胶囊
            Box(
                modifier = Modifier
                    .size(width = 166.dp, height = 228.dp)
                    .rotate(38f)
                    .clip(CircleShape)
                    .background(scheme.surfaceContainerHigh),
                contentAlignment = Alignment.Center,
            ) {
                val centerUrl = artworkUrls.getOrNull(0)
                if (!centerUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = centerUrl,
                        contentDescription = headline,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .requiredSize(296.dp)
                            .rotate(-38f),
                    )
                } else {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = scheme.primary, modifier = Modifier.size(48.dp))
                }
            }
            // 左上卫星圆
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .offset(x = 18.dp, y = 10.dp)
                    .size(78.dp)
                    .shadow(8.dp, CircleShape)
                    .clip(CircleShape)
                    .border(2.5.dp, colors.sheetSurface, CircleShape)
                    .background(scheme.surfaceContainerHigh),
                contentAlignment = Alignment.Center,
            ) {
                val leftUrl = artworkUrls.getOrNull(1)
                if (!leftUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = leftUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = colors.pink, modifier = Modifier.size(26.dp))
                }
            }
            // 右下卫星圆
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = (-18).dp, y = (-8).dp)
                    .size(76.dp)
                    .shadow(8.dp, CircleShape)
                    .clip(CircleShape)
                    .border(2.5.dp, colors.sheetSurface, CircleShape)
                    .background(scheme.surfaceContainerHigh),
                contentAlignment = Alignment.Center,
            ) {
                val rightUrl = artworkUrls.getOrNull(2)
                if (!rightUrl.isNullOrBlank()) {
                    AsyncImage(
                        model = rightUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = colors.cyan, modifier = Modifier.size(26.dp))
                }
            }
        }
    }
}
