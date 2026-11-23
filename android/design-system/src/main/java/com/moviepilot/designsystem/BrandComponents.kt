package com.moviepilot.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.SecondaryTabRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** 自适应高对比小角标（对齐 iOS `NativeAdaptiveBadge`）。 */
@Composable
fun NativeAdaptiveBadge(
    text: String,
    tint: Color? = null,
    filled: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val fg = when {
        filled -> Color.White
        tint != null -> tint
        else -> colors.chipText
    }
    val bg = when {
        filled && tint != null -> tint
        tint != null -> tint.copy(alpha = 0.16f)
        else -> colors.chipFill
    }
    val border = tint?.copy(alpha = 0.30f) ?: colors.chipBorder

    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(bg)
            .border(0.6.dp, border, CircleShape)
            .padding(horizontal = 9.dp, vertical = 3.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = fg,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
    }
}

/**
 * Material Design 3 一级页面切换页签栏（`PrimaryTabRow` / `PrimaryScrollableTabRow`）：
 * - 专用于平级功能域与独立视图切换（如「已安装 / 插件市场」、「我的工作流 / 社区分享」、「全部 / 电影 / 电视剧 / 音乐」）；
 * - 配合 `HorizontalPager` 支持整屏左右跟手滑动，底部紫色圆角指示条 + 细分隔线，符合 Google Play / YouTube / Pixel 规范。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativePrimaryTabBar(
    tabs: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    scrollable: Boolean = false,
    modifier: Modifier = Modifier,
) {
    if (tabs.isEmpty()) return
    val safeIndex = selectedIndex.coerceIn(0, tabs.lastIndex)
    val scheme = MaterialTheme.colorScheme
    val content: @Composable () -> Unit = {
        tabs.forEachIndexed { index, title ->
            val selected = index == safeIndex
            Tab(
                selected = selected,
                onClick = { onSelect(index) },
                selectedContentColor = scheme.primary,
                unselectedContentColor = scheme.onSurfaceVariant,
                text = {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontSize = 14.sp,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                        ),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
            )
        }
    }
    if (scrollable) {
        PrimaryScrollableTabRow(
            selectedTabIndex = safeIndex,
            modifier = modifier.fillMaxWidth(),
            containerColor = Color.Transparent,
            contentColor = scheme.primary,
            edgePadding = 16.dp,
            indicator = {
                TabRowDefaults.PrimaryIndicator(
                    modifier = Modifier.tabIndicatorOffset(safeIndex, matchContentSize = true),
                    width = Dp.Unspecified,
                    height = 3.dp,
                    color = scheme.primary,
                )
            },
            divider = { HorizontalDivider(color = scheme.outlineVariant.copy(alpha = 0.45f)) },
            tabs = content,
        )
    } else {
        PrimaryTabRow(
            selectedTabIndex = safeIndex,
            modifier = modifier.fillMaxWidth(),
            containerColor = Color.Transparent,
            contentColor = scheme.primary,
            indicator = {
                TabRowDefaults.PrimaryIndicator(
                    modifier = Modifier.tabIndicatorOffset(safeIndex, matchContentSize = true),
                    width = Dp.Unspecified,
                    height = 3.dp,
                    color = scheme.primary,
                )
            },
            divider = { HorizontalDivider(color = scheme.outlineVariant.copy(alpha = 0.45f)) },
            tabs = content,
        )
    }
}

/**
 * Material Design 3 二级页内章节页签栏（`SecondaryTabRow`）：
 * - 专用于二级详情页内部视图切换（如插件详情页的「数据页 / 参数配置」），满宽细下划线指示条与顶栏自然衔接。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeSecondaryTabBar(
    tabs: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (tabs.isEmpty()) return
    val safeIndex = selectedIndex.coerceIn(0, tabs.lastIndex)
    val scheme = MaterialTheme.colorScheme
    SecondaryTabRow(
        selectedTabIndex = safeIndex,
        modifier = modifier.fillMaxWidth(),
        containerColor = Color.Transparent,
        contentColor = scheme.primary,
        indicator = {
            TabRowDefaults.SecondaryIndicator(
                modifier = Modifier.tabIndicatorOffset(safeIndex, matchContentSize = false),
                height = 2.5.dp,
                color = scheme.primary,
            )
        },
        divider = { HorizontalDivider(color = scheme.outlineVariant.copy(alpha = 0.45f)) },
    ) {
        tabs.forEachIndexed { index, title ->
            val selected = index == safeIndex
            Tab(
                selected = selected,
                onClick = { onSelect(index) },
                selectedContentColor = scheme.primary,
                unselectedContentColor = scheme.onSurfaceVariant,
                text = {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontSize = 14.sp,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                        ),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
            )
        }
    }
}

/**
 * Material Design 3 连接式分段单选按钮（`SingleChoiceSegmentedButtonRow`）：
 * - 专用于同一数据或设置的 2~4 项互斥状态/模式切换（如「深色 / 浅色 / 跟随系统」、「全部 / 成功 / 失败」、「1.0x / 1.25x / 1.5x / 2.0x」）；
 * - 紧连胶囊轮廓 + 选中态 Tonal 容器与勾选图标，与独立筛选芯片 `FilterChip` 明确分层。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeSegmentedControl(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    icons: List<ImageVector?>? = null,
    modifier: Modifier = Modifier,
) {
    if (options.isEmpty()) return
    val safeIndex = selectedIndex.coerceIn(0, options.lastIndex)
    val scheme = MaterialTheme.colorScheme
    SingleChoiceSegmentedButtonRow(modifier = modifier.fillMaxWidth()) {
        options.forEachIndexed { index, label ->
            val selected = index == safeIndex
            val customIcon = icons?.getOrNull(index)
            SegmentedButton(
                selected = selected,
                onClick = { onSelect(index) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = scheme.secondaryContainer,
                    activeContentColor = scheme.onSecondaryContainer,
                    activeBorderColor = scheme.outlineVariant,
                    inactiveContainerColor = scheme.surfaceContainerLow,
                    inactiveContentColor = scheme.onSurfaceVariant,
                    inactiveBorderColor = scheme.outlineVariant,
                ),
                icon = {
                    if (customIcon != null) {
                        Icon(
                            imageVector = customIcon,
                            contentDescription = null,
                            modifier = Modifier.size(SegmentedButtonDefaults.IconSize),
                        )
                    } else {
                        SegmentedButtonDefaults.Icon(active = selected)
                    }
                },
                label = {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
            )
        }
    }
}

/**
 * Material Design 3 风格筛选与分类芯片（FilterChip 规范）：
 * - 采用 Material 3 标志性 `10.dp` 微圆角与 Tonal 选中容器色，配合原生 Ripple 与最小 48dp 无障碍触控区；
 * - 选中态且未传入自定义图标时可选展示轻巧勾选或高亮强调色，呈现纯正 Android Material 3 辨识度。
 */
@Composable
fun NativeAdaptivePill(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    icon: ImageVector? = null,
    tint: Color? = null,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val activeColor = tint ?: MaterialTheme.colorScheme.primary
    val chipShape = RoundedCornerShape(10.dp)
    val bgColor = if (selected) {
        if (tint != null) tint.copy(alpha = if (colors.isDark) 0.28f else 0.16f)
        else MaterialTheme.colorScheme.secondaryContainer
    } else {
        colors.chipFill.copy(alpha = if (colors.isDark) 0.55f else 0.80f)
    }
    val fgColor = if (selected) {
        if (tint != null) (if (colors.isDark) Color.White else tint)
        else MaterialTheme.colorScheme.onSecondaryContainer
    } else {
        colors.chipText
    }
    Row(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .heightIn(min = 36.dp)
            .clip(chipShape)
            .background(bgColor)
            .border(
                width = if (selected) 1.dp else 0.75.dp,
                color = if (selected) activeColor.copy(alpha = 0.55f) else colors.chipBorder,
                shape = chipShape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = fgColor,
                modifier = Modifier.size(16.dp),
            )
        } else if (selected) {
            Icon(
                imageVector = Icons.Rounded.Check,
                contentDescription = null,
                tint = activeColor,
                modifier = Modifier.size(15.dp),
            )
        }
        Text(
            text = title,
            color = fgColor,
            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp),
            maxLines = 1,
        )
    }
}

/** 圆形实时磨砂玻璃图标按钮（用于全幅摄影背景上的悬浮控制，确保 48dp 无障碍触控热区与原生 Ripple）。 */
@Composable
fun CinematicCircleButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp,
) {
    val colors = LocalMoviePilotColors.current
    CinematicGlassSurface(
        shape = CircleShape,
        blurRadiusDp = 18.dp,
        darkTintAlpha = 0.42f,
        lightTintAlpha = 0.72f,
        modifier = modifier
            .minimumInteractiveComponentSize()
            .size(size)
            .clickable(onClick = onClick),
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = contentDescription,
                tint = colors.textPrimary,
                modifier = Modifier.size(22.dp),
            )
        }
    }
}

/** 全局 Material 3 底部浮动 Snackbar 宿主（支持“撤销”等非阻塞操作反馈）。 */
val LocalSnackbarHostState = compositionLocalOf<SnackbarHostState?> { null }

/**
 * Android Material Design 3 顶部应用栏（TopAppBar 规范 + 顶部状态栏渐进模糊）：
 * - 严格遵循 Material 3 64dp 栏高、48dp 无障碍 Up 返回图标按钮（原生 Ripple，非 iOS 玻璃泡泡）；
 * - 标题使用 `MaterialTheme.typography.titleLarge` 左对齐排布；
 * - 内置状态栏渐进模糊罩防止滚动内容与状态栏重叠。
 */
@Composable
fun NativeGlassTopBar(
    title: String,
    onBack: (() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    showTopBlur: Boolean = true,
    centerTitle: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Box(modifier = modifier.fillMaxWidth()) {
        if (showTopBlur) {
            NativeTopStatusBarProgressiveBlur(
                visibilityProgress = 1f,
                extraHeight = 62.dp,
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .heightIn(min = 64.dp)
                .padding(horizontal = if (onBack != null) 8.dp else 18.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "返回上一级",
                        tint = colors.textPrimary,
                        modifier = Modifier.size(24.dp),
                    )
                }
                Spacer(Modifier.width(4.dp))
            } else if (centerTitle) {
                Spacer(Modifier.width(48.dp))
            }
            Box(
                modifier = Modifier.weight(1f),
                contentAlignment = if (centerTitle) Alignment.Center else Alignment.CenterStart,
            ) {
                Text(
                    text = title,
                    color = colors.textPrimary,
                    style = if (centerTitle) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (trailing != null) {
                Spacer(Modifier.width(8.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    content = trailing,
                )
                if (onBack != null) Spacer(Modifier.width(4.dp))
            } else if (centerTitle && onBack != null) {
                Spacer(Modifier.width(48.dp))
            }
        }
    }
}

/** Android Material Design 3 单手可达右下角主动作 FAB（16dp Squircle，遵循 primaryContainer 规范）。 */
@Composable
fun NativeGlassFab(
    icon: ImageVector,
    label: String? = null,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val container = MaterialTheme.colorScheme.primaryContainer
    val content = MaterialTheme.colorScheme.onPrimaryContainer
    if (!label.isNullOrBlank()) {
        ExtendedFloatingActionButton(
            onClick = onClick,
            icon = {
                Icon(
                    imageVector = icon,
                    contentDescription = label,
                    modifier = Modifier.size(22.dp),
                )
            },
            text = {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelLarge,
                )
            },
            shape = RoundedCornerShape(16.dp),
            containerColor = container,
            contentColor = content,
            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 6.dp),
            modifier = modifier,
        )
    } else {
        FloatingActionButton(
            onClick = onClick,
            shape = RoundedCornerShape(16.dp),
            containerColor = container,
            contentColor = content,
            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 6.dp),
            modifier = modifier,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = "主操作",
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

/** 区块标题行（Material 3 `titleLarge` + 最小 44dp 可点击热区）。 */
@Composable
fun NativeSectionHeader(
    title: String,
    subtitle: String? = null,
    onClickMore: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(10.dp))
            .then(if (onClickMore != null) Modifier.clickable(onClick = onClickMore) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = title,
            color = colors.textPrimary,
            style = MaterialTheme.typography.titleLarge.copy(fontSize = 19.sp),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    color = colors.textSecondary,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            if (onClickMore != null) {
                if (subtitle.isNullOrBlank()) {
                    Text(
                        text = "全部",
                        color = MaterialTheme.colorScheme.primary,
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp),
                    )
                }
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = "查看更多$title",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

/** 动态按资源名加载已同步的 36+ 官方品牌图标（`logo_tmdb`、`logo_douban`、`brandmark` 等）。 */
@Composable
fun NativeBrandDrawable(
    drawableName: String,
    size: Dp = 36.dp,
    cornerRadius: Dp = 10.dp,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val resId = remember(drawableName) {
        context.resources.getIdentifier(drawableName.lowercase().replace("-", "_"), "drawable", context.packageName)
    }
    if (resId != 0) {
        androidx.compose.foundation.Image(
            painter = painterResource(id = resId),
            contentDescription = drawableName,
            contentScale = ContentScale.Crop,
            modifier = modifier
                .size(size)
                .clip(RoundedCornerShape(cornerRadius)),
        )
    } else {
        val colors = LocalMoviePilotColors.current
        Box(
            modifier = modifier
                .size(size)
                .clip(RoundedCornerShape(cornerRadius))
                .background(colors.accent.copy(alpha = 0.25f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Movie,
                contentDescription = null,
                tint = colors.accent,
                modifier = Modifier.size(size * 0.55f),
            )
        }
    }
}

/** 通用 2:3 竖版影视海报卡（像素级对齐 iOS：右上角高对比绿圆白勾已入库标 / 黑透评分胶囊，底部居中标题与年份）。 */
@Composable
fun NativePosterCard(
    title: String,
    year: String,
    posterUrl: String?,
    voteAverage: Double = 0.0,
    inLibrary: Boolean = false,
    bottomBadgeText: String? = null,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val shape = RoundedCornerShape(13.dp)
    Column(
        modifier = modifier.clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(shape)
                .background(
                    Brush.linearGradient(
                        listOf(
                            colors.accent.copy(alpha = 0.22f),
                            Color(0xFF28203A),
                        ),
                    ),
                )
                .border(0.6.dp, Color.White.copy(alpha = 0.14f), shape),
        ) {
            var imageFailed by remember(posterUrl) { mutableStateOf(false) }
            if (!posterUrl.isNullOrBlank() && !imageFailed) {
                AsyncImage(
                    model = posterUrl,
                    contentDescription = title,
                    contentScale = ContentScale.Crop,
                    onError = { imageFailed = true },
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Column(
                    modifier = Modifier.fillMaxSize().padding(10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Movie,
                        contentDescription = null,
                        tint = colors.accent.copy(alpha = 0.55f),
                        modifier = Modifier.size(28.dp),
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = title,
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
            }
            if (inLibrary) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(21.dp)
                        .clip(CircleShape)
                        .background(Color(0xFF2CC856))
                        .border(1.4.dp, Color.White.copy(alpha = 0.92f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Check,
                        contentDescription = "已入库",
                        tint = Color.White,
                        modifier = Modifier.size(13.dp),
                    )
                }
            } else if (voteAverage > 0.0) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.Black.copy(alpha = 0.66f))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = String.format("%.1f", voteAverage),
                        color = Color.White,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
            if (!bottomBadgeText.isNullOrBlank()) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(6.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.68f))
                        .padding(horizontal = 7.dp, vertical = 3.dp),
                ) {
                    Text(
                        text = bottomBadgeText,
                        color = Color(0xFFFFC55C),
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            text = title,
            color = colors.textPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (year.isNotBlank()) {
            Text(
                text = year,
                color = colors.textMuted,
                fontSize = 11.sp,
                maxLines = 1,
            )
        }
    }
}

/**
 * 1:1 像素级复刻 iOS `NativeAgentFloatingMascot.swift`（源自 Web `CssRobotRenderer.vue`）：
 * 紫蓝三段立体渐变头壳、右倾 20° 圆球天线、-3° 微倾头部、深色面罩、半眯下弧弯月双眼（7.2s 慢速眨眼）、
 * 白色播放三角圆润躯干、外展 ±17° 短手与圆润短腿，支持全屏任意位置平滑拖曳、零残影。
 */
@Composable
fun FloatingAgentMascot(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }
    var isDragging by remember { mutableStateOf(false) }
    var isBlinking by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        while (true) {
            delay(7200L)
            if (!isDragging) {
                isBlinking = true
                delay(160L)
                isBlinking = false
            }
        }
    }

    val eyeScaleY by animateFloatAsState(
        targetValue = if (isBlinking) 0.15f else 1.0f,
        animationSpec = tween(durationMillis = if (isBlinking) 110 else 180),
        label = "mascotBlink",
    )
    val dragScale by animateFloatAsState(
        targetValue = if (isDragging) 1.06f else 1.0f,
        animationSpec = tween(durationMillis = 140),
        label = "mascotDragScale",
    )

    Box(
        modifier = modifier
            .offset { IntOffset(offsetX.roundToInt(), offsetY.roundToInt()) }
            .size(width = 56.dp, height = 68.dp)
            .graphicsLayer {
                scaleX = dragScale
                scaleY = dragScale
            }
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = { isDragging = true },
                    onDragEnd = { isDragging = false },
                    onDragCancel = { isDragging = false },
                ) { change, dragAmount ->
                    change.consume()
                    offsetX += dragAmount.x
                    offsetY += dragAmount.y
                }
            }
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val sx = size.width / 56f
            val sy = size.height / 68f
            val cx = size.width * 0.5f
            val cy = size.height * 0.5f

            val outline = Color(0xFF473080)
            val shellStart = Color(0xFFDBD1FF)
            val shellMid = Color(0xFFA385FA)
            val shellEnd = Color(0xFF7A57E0)
            val faceStart = Color(0xFF262140)
            val faceEnd = Color(0xFF0F1224)
            val eyeColor = Color(0xFFF0EBFF)

            // 底层柔影
            drawOval(
                color = Color.Black.copy(alpha = 0.22f),
                topLeft = Offset(cx - 17f * sx, cy + 25f * sy),
                size = Size(34f * sx, 8f * sy),
            )

            // 1. 左/右小短腿 (offset y=+25)
            for (side in listOf(-1f, 1f)) {
                val legW = 8f * sx
                val legH = 9f * sy
                val lx = cx + side * 8f * sx - legW * 0.5f
                val ly = cy + 25f * sy - legH * 0.5f
                drawRoundRect(
                    brush = Brush.verticalGradient(listOf(shellMid, outline), startY = ly, endY = ly + legH),
                    topLeft = Offset(lx, ly),
                    size = Size(legW, legH),
                    cornerRadius = CornerRadius(4f * sx, 4f * sy),
                )
                drawRoundRect(
                    color = outline,
                    topLeft = Offset(lx, ly),
                    size = Size(legW, legH),
                    cornerRadius = CornerRadius(4f * sx, 4f * sy),
                    style = Stroke(width = 1.5f * sx),
                )
            }

            // 2. 左/右微倾胶囊小手臂 (offset y=+14, ±17°)
            for ((side, deg) in listOf(-1f to 17f, 1f to -17f)) {
                val armW = 7f * sx
                val armH = 13f * sy
                val ax = cx + side * 16f * sx
                val ay = cy + 14f * sy
                rotate(degrees = deg, pivot = Offset(ax, ay)) {
                    drawRoundRect(
                        brush = Brush.verticalGradient(listOf(shellMid, shellEnd), startY = ay - armH * 0.5f, endY = ay + armH * 0.5f),
                        topLeft = Offset(ax - armW * 0.5f, ay - armH * 0.5f),
                        size = Size(armW, armH),
                        cornerRadius = CornerRadius(armW * 0.5f, armW * 0.5f),
                    )
                    drawRoundRect(
                        color = outline,
                        topLeft = Offset(ax - armW * 0.5f, ay - armH * 0.5f),
                        size = Size(armW, armH),
                        cornerRadius = CornerRadius(armW * 0.5f, armW * 0.5f),
                        style = Stroke(width = 1.5f * sx),
                    )
                }
            }

            // 3. 圆润躯干 + MoviePilot 白色播放三角核心 (offset y=+14)
            val bodyW = 26f * sx
            val bodyH = 19f * sy
            val bx = cx - bodyW * 0.5f
            val by = cy + 14f * sy - bodyH * 0.5f
            drawRoundRect(
                brush = Brush.linearGradient(
                    listOf(shellMid, shellEnd),
                    start = Offset(bx, by),
                    end = Offset(bx + bodyW, by + bodyH),
                ),
                topLeft = Offset(bx, by),
                size = Size(bodyW, bodyH),
                cornerRadius = CornerRadius(9f * sx, 9f * sy),
            )
            drawRoundRect(
                color = outline,
                topLeft = Offset(bx, by),
                size = Size(bodyW, bodyH),
                cornerRadius = CornerRadius(9f * sx, 9f * sy),
                style = Stroke(width = 1.6f * sx),
            )
            val playCx = cx + 0.8f * sx
            val playCy = cy + 14f * sy
            val playPath = Path().apply {
                moveTo(playCx - 3.3f * sx, playCy - 4.1f * sy)
                lineTo(playCx + 4.3f * sx, playCy)
                lineTo(playCx - 3.3f * sx, playCy + 4.1f * sy)
                close()
            }
            drawPath(playPath, Color.White)

            // 4. 头部 + 倾斜天线 + 深色玻璃面罩 + 半眯下弧弯月双眼 (offset y=-7, rot -3°)
            val headPivot = Offset(cx, cy - 7f * sy)
            rotate(degrees = -3f, pivot = headPivot) {
                // 倾斜天线与顶部圆球 (+20°)
                val antBase = Offset(headPivot.x + 2f * sx, headPivot.y - 14f * sy)
                rotate(degrees = 20f, pivot = antBase) {
                    drawLine(
                        color = outline,
                        start = antBase,
                        end = Offset(antBase.x, antBase.y - 9f * sy),
                        strokeWidth = 2.5f * sx,
                        cap = StrokeCap.Round,
                    )
                    val ballCenter = Offset(antBase.x, antBase.y - 10.5f * sy)
                    drawCircle(color = shellStart, radius = 3.5f * sx, center = ballCenter)
                    drawCircle(color = outline, radius = 3.5f * sx, center = ballCenter, style = Stroke(width = 1.5f * sx))
                }

                // 头壳 44×30
                val headW = 44f * sx
                val headH = 30f * sy
                val hx = headPivot.x - headW * 0.5f
                val hy = headPivot.y - headH * 0.5f
                drawRoundRect(
                    brush = Brush.linearGradient(
                        listOf(shellStart, shellMid, shellEnd),
                        start = Offset(hx, hy),
                        end = Offset(hx + headW, hy + headH),
                    ),
                    topLeft = Offset(hx, hy),
                    size = Size(headW, headH),
                    cornerRadius = CornerRadius(10.5f * sx, 10.5f * sy),
                )
                drawRoundRect(
                    color = outline,
                    topLeft = Offset(hx, hy),
                    size = Size(headW, headH),
                    cornerRadius = CornerRadius(10.5f * sx, 10.5f * sy),
                    style = Stroke(width = 1.8f * sx),
                )

                // 深色玻璃面罩 33×19
                val faceW = 33f * sx
                val faceH = 19f * sy
                val fx = headPivot.x - 1.5f * sx - faceW * 0.5f
                val fy = headPivot.y + 0.5f * sy - faceH * 0.5f
                drawRoundRect(
                    brush = Brush.verticalGradient(listOf(faceStart, faceEnd), startY = fy, endY = fy + faceH),
                    topLeft = Offset(fx, fy),
                    size = Size(faceW, faceH),
                    cornerRadius = CornerRadius(7f * sx, 7f * sy),
                )
                drawRoundRect(
                    color = outline.copy(alpha = 0.9f),
                    topLeft = Offset(fx, fy),
                    size = Size(faceW, faceH),
                    cornerRadius = CornerRadius(7f * sx, 7f * sy),
                    style = Stroke(width = 1.4f * sx),
                )

                // 半眯困倦下弧弯月双眼（1:1 复刻 SleepyRobotEyeShape）
                fun drawSleepyEye(ecx: Float, eTopY: Float) {
                    val ew = 7.4f * sx
                    val eh = 5.2f * sy * eyeScaleY
                    val rx = ew * 0.5f
                    val outerRy = eh
                    val innerRy = eh * 0.52f
                    val path = Path()
                    val steps = 16
                    for (i in 0..steps) {
                        val theta = (i.toDouble() / steps) * PI
                        val x = ecx - rx * cos(theta).toFloat()
                        val y = eTopY + outerRy * sin(theta).toFloat()
                        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    for (i in steps downTo 0) {
                        val theta = (i.toDouble() / steps) * PI
                        val x = ecx - rx * cos(theta).toFloat()
                        val y = eTopY + innerRy * sin(theta).toFloat()
                        path.lineTo(x, y)
                    }
                    path.close()
                    drawPath(path, eyeColor)
                }

                val eyeCenterBaseX = headPivot.x - 1.5f * sx
                val eyeTopY = headPivot.y - 1.6f * sy
                drawSleepyEye(eyeCenterBaseX - 7.4f * sx, eyeTopY)
                drawSleepyEye(eyeCenterBaseX + 7.4f * sx, eyeTopY + 0.5f * sy)
            }
        }
    }
}
