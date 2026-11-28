package com.moviepilot.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material3.DropdownMenu
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
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
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

/** 自适应高对比小角标（依据 Material 3 Expressive 亮度自动计算前景字色，浅粉彩自动配深墨字）。 */
@Composable
fun NativeAdaptiveBadge(
    text: String,
    tint: Color? = null,
    filled: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val resolvedTint = tint ?: MaterialTheme.colorScheme.primary
    val fg = when {
        filled -> resolvedTint.contrastingForeground()
        tint != null -> tint
        else -> colors.chipText
    }
    val bg = when {
        filled -> resolvedTint
        tint != null -> tint.copy(alpha = if (colors.isDark) 0.18f else 0.14f)
        else -> colors.chipFill
    }

    Box(
        modifier = modifier
            .clip(CircleShape)
            .background(bg)
            .padding(horizontal = 10.dp, vertical = 3.5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = text,
            color = fg,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
    }
}

/**
 * 发现页主视觉与影视/媒体库详情页共用的紧凑多元评分微标横排（品牌微图标 + 分数）。
 *
 * @param badges 按展示顺序排列的 `(source, formattedScore)` 列表
 * @param isDark 当前是否处于深色背景或暗色头图之上
 * @param compact 是否使用紧凑字号（横屏窄高等场景）
 * @param modifier 外部修饰符
 */
@Composable
fun MultiSourceRatingsRow(
    badges: List<Pair<String, String>>,
    isDark: Boolean,
    compact: Boolean = false,
    modifier: Modifier = Modifier,
) {
    if (badges.isEmpty()) return
    val colors = LocalMoviePilotColors.current
    val textColor = if (isDark) Color.White else colors.textPrimary
    val iconSize = if (compact) 14.dp else 15.5.dp
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (compact) 9.dp else 12.dp),
    ) {
        badges.forEach { (rawSource, scoreText) ->
            if (scoreText.isBlank()) return@forEach
            val src = rawSource.trim().lowercase()
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                when (src) {
                    "imdb" -> {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(3.5.dp))
                                .background(Color(0xFFF5C518))
                                .padding(horizontal = 4.5.dp, vertical = 1.2.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "IMDb",
                                color = Color(0xFF141414),
                                fontSize = if (compact) 8.5.sp else 9.5.sp,
                                fontWeight = FontWeight.Black,
                                maxLines = 1,
                            )
                        }
                    }
                    "rottentomatoes", "rt", "critic" -> {
                        Box(
                            modifier = Modifier.size(iconSize),
                            contentAlignment = Alignment.TopCenter,
                        ) {
                            Box(
                                modifier = Modifier
                                    .padding(top = 1.5.dp)
                                    .size(iconSize - 1.5.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFFFA320A)),
                            )
                            Box(
                                modifier = Modifier
                                    .size(width = 6.5.dp, height = 2.6.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFF2EA84A)),
                            )
                        }
                    }
                    "douban" -> {
                        NativeEntityLogo(
                            kind = "datasource",
                            value = "douban",
                            size = iconSize,
                            cornerRadius = 3.8.dp,
                        )
                    }
                    "bangumi", "bgm" -> {
                        NativeEntityLogo(
                            kind = "datasource",
                            value = "bangumi",
                            size = iconSize,
                            cornerRadius = 3.8.dp,
                        )
                    }
                    "anilist" -> {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(3.5.dp))
                                .background(Color(0xFF02A9FF))
                                .padding(horizontal = 4.dp, vertical = 1.2.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "AL",
                                color = Color.White,
                                fontSize = if (compact) 8.5.sp else 9.5.sp,
                                fontWeight = FontWeight.Black,
                                maxLines = 1,
                            )
                        }
                    }
                    "community" -> {
                        Text(
                            text = "★",
                            color = Color(0xFFFFC845),
                            fontSize = if (compact) 11.sp else 12.5.sp,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                    else -> {
                        NativeEntityLogo(
                            kind = "datasource",
                            value = "themoviedb",
                            size = iconSize,
                            cornerRadius = 3.8.dp,
                        )
                    }
                }
                Text(
                    text = scoreText,
                    color = textColor,
                    fontSize = if (compact) 11.5.sp else 12.5.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                )
            }
        }
    }
}

/**
 * Material 3 Expressive 一级页面切换页签栏：
 * - 委托 `ExpressivePillTabRow` 绘制柔和主色激活胶囊 + 正下方迷你居中小横杠指示器，
 *   配合 `HorizontalPager` 实现整屏丝滑滑动切换。
 */
@Composable
fun NativePrimaryTabBar(
    tabs: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    scrollable: Boolean = false,
    onTintedHeader: Boolean = false,
    modifier: Modifier = Modifier,
) {
    ExpressivePillTabRow(
        tabs = tabs,
        selectedIndex = selectedIndex,
        onSelect = onSelect,
        scrollable = scrollable,
        onTintedHeader = onTintedHeader,
        modifier = modifier,
    )
}

/**
 * Material 3 Expressive 二级页内章节页签栏：
 * 与一级页签视觉保持完全统一，采用高辨识度表现力大胶囊 + 居中短条指示器样式。
 */
@Composable
fun NativeSecondaryTabBar(
    tabs: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    scrollable: Boolean = false,
    onTintedHeader: Boolean = false,
    modifier: Modifier = Modifier,
) {
    ExpressivePillTabRow(
        tabs = tabs,
        selectedIndex = selectedIndex,
        onSelect = onSelect,
        scrollable = scrollable,
        onTintedHeader = onTintedHeader,
        modifier = modifier,
    )
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
 * Material 3 Expressive 筛选与属性芯片（全圆角胶囊）：
 * - 激活态为高辨识度柔和主色或 `secondaryContainer`；
 * - 未激活态采用柔和实色表面胶囊并配 `0.8.dp` `colors.borderSubtle` 清晰轮廓线（确保浅色与深色模式均满足 >= 3:1 边界对比度）。
 */
@Composable
fun NativeAdaptivePill(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    icon: ImageVector? = null,
    tint: Color? = null,
    leadingContent: (@Composable () -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val scheme = MaterialTheme.colorScheme
    val activeBg = if (tint != null) {
        tint.copy(alpha = if (colors.isDark) 0.28f else 0.16f)
    } else {
        scheme.secondaryContainer
    }
    val activeFg = if (tint != null) {
        tint
    } else {
        scheme.onSecondaryContainer
    }
    val bgColor = if (selected) activeBg else scheme.surfaceContainerLow
    val fgColor = if (selected) activeFg else colors.textSecondary
    val borderColor = if (selected) activeFg.copy(alpha = 0.42f) else colors.borderSubtle

    Row(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .heightIn(min = 38.dp)
            .clip(CircleShape)
            .background(bgColor, CircleShape)
            .border(0.8.dp, borderColor, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 15.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (leadingContent != null) {
            leadingContent()
        } else if (icon != null) {
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
                tint = fgColor,
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
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(
                if (showTopBlur) colors.headerTint else Color.Transparent,
            ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .heightIn(min = 66.dp)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                ExpressiveHeaderActionButton(
                    icon = Icons.AutoMirrored.Rounded.ArrowBack,
                    contentDescription = "返回上一级",
                    onClick = onBack,
                )
                Spacer(Modifier.width(12.dp))
            } else if (centerTitle) {
                Spacer(Modifier.width(44.dp))
            }
            Box(
                modifier = Modifier.weight(1f),
                contentAlignment = if (centerTitle) Alignment.Center else Alignment.CenterStart,
            ) {
                Text(
                    text = title,
                    color = if (showTopBlur) colors.headerTitle else colors.textPrimary,
                    style = if (centerTitle) {
                        MaterialTheme.typography.titleLarge.copy(fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    } else {
                        MaterialTheme.typography.headlineMedium.copy(fontSize = 24.sp, fontWeight = FontWeight.ExtraBold)
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (trailing != null) {
                Spacer(Modifier.width(8.dp))
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    content = trailing,
                )
            } else if (centerTitle && onBack != null) {
                Spacer(Modifier.width(44.dp))
            }
        }
    }
}

/** Material 3 Expressive 单手可达主动作按钮（高对比柔和主色 + 表现力大圆角）。 */
@Composable
fun NativeGlassFab(
    icon: ImageVector,
    label: String? = null,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val container = MaterialTheme.colorScheme.primary
    val content = MaterialTheme.colorScheme.onPrimary
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
            shape = CircleShape,
            containerColor = container,
            contentColor = content,
            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 6.dp),
            modifier = modifier,
        )
    } else {
        FloatingActionButton(
            onClick = onClick,
            shape = RoundedCornerShape(20.dp),
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

/** 区块标题行（Material 3 `titleLarge` + 最小 44dp 可点击热区，支持品牌图标前缀）。 */
@Composable
fun NativeSectionHeader(
    title: String,
    subtitle: String? = null,
    onClickMore: (() -> Unit)? = null,
    leadingContent: (@Composable () -> Unit)? = null,
    subtitleLeading: (@Composable () -> Unit)? = null,
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
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.weight(1f, fill = false),
        ) {
            leadingContent?.invoke()
            Text(
                text = title,
                color = colors.textPrimary,
                style = MaterialTheme.typography.titleLarge.copy(fontSize = 19.sp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            subtitleLeading?.invoke()
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    color = colors.textSecondary,
                    style = MaterialTheme.typography.labelMedium,
                    maxLines = 1,
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

/**
 * 解析 36 枚官方品牌/服务图标资源名：
 * 完整覆盖 `datasource`（数据源）、`downloader`（下载器）、`mediaserver`（媒体服务器）、
 * `notification`（11 类通知渠道）、`storage`（本地与网盘存储）、`site`（站点）、`plugin`（插件）与 `avatar`（默认头像）。
 */
fun resolveEntityLogoDrawable(kind: String, value: String): String {
    val normKind = kind.trim().lowercase()
    val v = value.trim().lowercase()

    fun matchDatasource(): String = when {
        v.contains("douban") || v.contains("豆瓣") -> "logo_douban"
        v.contains("bangumi") || v == "bgm" || v.contains("番剧") -> "logo_bangumi"
        v.contains("musicbrainz") || v == "music" || v.contains("音乐") -> "logo_musicbrainz"
        else -> "logo_tmdb"
    }

    fun matchDownloader(): String = when {
        v.contains("qbittorrent") || v == "qb" -> "logo_qbittorrent"
        v.contains("transmission") || v == "tr" -> "logo_transmission"
        v.contains("rtorrent") || v == "rt" || v.contains("rutorrent") -> "logo_rtorrent"
        else -> "logo_downloader"
    }

    fun matchMediaServer(): String = when {
        v.contains("jellyfin") -> "logo_jellyfin"
        v.contains("plex") -> "logo_plex"
        v.contains("trimemedia") || v.contains("trim") || v.contains("fnos") || v.contains("feiniu") || v.contains("飞牛") -> "logo_trimemedia"
        v.contains("ugreen") || v.contains("绿联") -> "logo_ugreen"
        v.contains("zspace") || v.contains("极空间") -> "logo_zspace"
        v.contains("vyo") -> "logo_vyo"
        v.contains("emby") -> "logo_emby"
        else -> "logo_mediaserver"
    }

    fun matchNotification(): String = when {
        v.contains("wechat") || v.contains("wecom") || v.contains("微信") || v.contains("企业微信") -> "logo_wechat"
        v.contains("clawbot") || v.contains("claw") -> "logo_clawbot"
        v.contains("feishu") || v.contains("lark") || v.contains("飞书") -> "logo_feishu"
        v.contains("telegram") || v == "tg" -> "logo_telegram"
        v.contains("qq") || v.contains("napcat") -> "logo_qq"
        v.contains("vocechat") || v.contains("voce") -> "logo_vocechat"
        v.contains("synology") || v.contains("群晖") -> "logo_synologychat"
        v.contains("slack") -> "logo_slack"
        v.contains("discord") -> "logo_discord"
        v.contains("dingtalk") || v.contains("dingding") || v.contains("钉钉") -> "logo_dingtalk"
        v.contains("webpush") || v.contains("chrome") || v.contains("browser") || v.contains("浏览器") -> "logo_chrome"
        else -> "logo_notification"
    }

    fun matchStorage(): String = when {
        v.contains("u115") || v.contains("115") -> "logo_u115"
        v.contains("alipan") || v.contains("aliyun") || v.contains("阿里") -> "logo_alipan"
        v.contains("rclone") -> "logo_rclone"
        v.contains("smb") || v.contains("cifs") || v.contains("samba") -> "logo_smb"
        else -> "logo_storage"
    }

    return when (normKind) {
        "datasource", "source", "media_source" -> matchDatasource()
        "downloader" -> matchDownloader()
        "mediaserver", "media_server", "server" -> matchMediaServer()
        "notification", "channel" -> matchNotification()
        "storage", "directory" -> matchStorage()
        "site" -> "logo_site"
        "plugin" -> "logo_plugin"
        "avatar", "user" -> "logo_avatar_default"
        else -> when {
            v.startsWith("logo_") -> v
            v.contains("tmdb") || v.contains("themoviedb") || v.contains("douban") || v.contains("bangumi") || v.contains("musicbrainz") -> matchDatasource()
            v.contains("qbittorrent") || v.contains("transmission") || v.contains("rtorrent") -> matchDownloader()
            v.contains("emby") || v.contains("jellyfin") || v.contains("plex") || v.contains("trim") || v.contains("ugreen") || v.contains("zspace") || v.contains("vyo") -> matchMediaServer()
            v.contains("wechat") || v.contains("telegram") || v.contains("slack") || v.contains("vocechat") || v.contains("synology") || v.contains("feishu") || v.contains("dingtalk") || v.contains("discord") || v.contains("clawbot") || v == "qq" || v.contains("webpush") -> matchNotification()
            v.contains("u115") || v.contains("115") || v.contains("alipan") || v.contains("rclone") || v.contains("smb") || v == "local" -> matchStorage()
            else -> "brandmark"
        }
    }
}

/**
 * 统一实体品牌图标组件：
 * 根据实体类别（`kind`）与类型值（`value`）自动匹配并渲染全套 36 枚官方高清 PNG 品牌徽标。
 */
@Composable
fun NativeEntityLogo(
    kind: String,
    value: String,
    size: Dp = 36.dp,
    cornerRadius: Dp = 10.dp,
    modifier: Modifier = Modifier,
) {
    val drawableName = remember(kind, value) { resolveEntityLogoDrawable(kind, value) }
    NativeBrandDrawable(
        drawableName = drawableName,
        size = size,
        cornerRadius = cornerRadius,
        modifier = modifier,
    )
}

/**
 * 支持远端图标 URL 优先加载、失败或为空时平滑回退到官方 `NativeEntityLogo` 的组合图标组件：
 * 专用于 PT 站点 Favicon（回退 `logo_site`）、插件图标（回退 `logo_plugin`）与用户头像（回退 `logo_avatar_default`）。
 */
@Composable
fun NativeNetworkEntityLogo(
    imageUrl: String?,
    kind: String,
    value: String = "",
    size: Dp = 36.dp,
    cornerRadius: Dp = 10.dp,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val context = LocalContext.current
    val density = LocalDensity.current
    val isPureBlack = LocalAppearanceStore.current.pureBlackDark
    val skelPalette = remember(colors, isPureBlack) { resolveSkeletonPalette(colors, isPureBlack) }
    var loadFailed by remember(imageUrl) { mutableStateOf(false) }
    val shape = remember(cornerRadius) { RoundedCornerShape(cornerRadius) }
    if (!imageUrl.isNullOrBlank() && !loadFailed) {
        val targetPx = with(density) { size.roundToPx().coerceIn(48, 256) }
        val request = remember(context, imageUrl, targetPx) {
            coil.request.ImageRequest.Builder(context)
                .data(imageUrl)
                .size(targetPx, targetPx)
                .precision(coil.size.Precision.INEXACT)
                .build()
        }
        Box(
            modifier = modifier
                .size(size)
                .clip(shape)
                .background(skelPalette.tileFill, shape),
            contentAlignment = Alignment.Center,
        ) {
            AsyncImage(
                model = request,
                contentDescription = value.ifBlank { kind },
                contentScale = ContentScale.Crop,
                onError = { loadFailed = true },
                modifier = Modifier.fillMaxSize(),
            )
        }
    } else {
        NativeEntityLogo(
            kind = kind,
            value = value,
            size = size,
            cornerRadius = cornerRadius,
            modifier = modifier,
        )
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

/**
 * 通用 2:3 竖版影视海报卡（像素级对齐 iOS：右上角高对比绿圆白勾已入库标 / 黑透评分胶囊，底部居中标题与年份；
 * 支持可选长按震动反馈 + 原生 `DropdownMenu` 快捷上下文菜单，保持海报构图干净无遮挡）。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun NativePosterCard(
    title: String,
    year: String,
    posterUrl: String?,
    voteAverage: Double = 0.0,
    inLibrary: Boolean = false,
    bottomBadgeText: String? = null,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    contextMenuContent: (@Composable ColumnScope.(dismiss: () -> Unit) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    val context = LocalContext.current
    val haptic = LocalHapticFeedback.current
    val isPureBlack = LocalAppearanceStore.current.pureBlackDark
    val skelPalette = remember(colors, isPureBlack) { resolveSkeletonPalette(colors, isPureBlack) }
    val shape = remember(colors.cardRadiusDp) { RoundedCornerShape((colors.cardRadiusDp - 4).coerceIn(12, 20).dp) }
    var imageFailed by remember(posterUrl) { mutableStateOf(false) }
    var menuExpanded by remember { mutableStateOf(false) }
    val hasLongPress = contextMenuContent != null || onLongClick != null
    val posterRequest = remember(context, posterUrl) {
        posterUrl?.takeIf { it.isNotBlank() }?.let { url ->
            coil.request.ImageRequest.Builder(context)
                .data(url)
                .size(360, 540)
                .precision(coil.size.Precision.INEXACT)
                .build()
        }
    }

    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (hasLongPress) {
                        Modifier.combinedClickable(
                            onClick = onClick,
                            onLongClick = {
                                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                if (contextMenuContent != null) {
                                    menuExpanded = true
                                } else {
                                    onLongClick?.invoke()
                                }
                            },
                        )
                    } else {
                        Modifier.clickable(onClick = onClick)
                    },
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(shape)
                .background(
                    if (posterRequest != null && !imageFailed) {
                        skelPalette.tileFill
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHigh
                    },
                    shape,
                ),
        ) {
            if (posterRequest != null && !imageFailed) {
                AsyncImage(
                    model = posterRequest,
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
                        color = colors.textPrimary,
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
        if (contextMenuContent != null) {
            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = { menuExpanded = false },
            ) {
                contextMenuContent { menuExpanded = false }
            }
        }
    }
}

/** 与 Web `agentPetActions.ts` 对齐的 16 个内置助手动作。 */
enum class AgentMascotAction(val wireName: String, val durationMs: Long) {
    Nod("nod", 1500L),
    Wake("wake", 1800L),
    Wave("wave", 2800L),
    Sit("sit", 4200L),
    EyeRoll("eye-roll", 1900L),
    Faint("faint", 4800L),
    Disassemble("disassemble", 6200L),
    HappyJump("happy-jump", 2600L),
    Sleep("sleep", 6800L),
    Stretch("stretch", 5200L),
    Peek("peek", 2800L),
    Scan("scan", 3200L),
    Charge("charge", 4800L),
    SpinCheer("spin-cheer", 3600L),
    Shy("shy", 3000L),
    Confused("confused", 3400L);

    companion object {
        private val randomPool = listOf(Wave, Sit, Sleep, Stretch, Peek, Shy, Confused)

                /** 选择一个与上次不同的随机待机动作。 */
        fun pickRandomIdle(last: AgentMascotAction?): AgentMascotAction {
            val weighted = buildList {
                for (act in randomPool) {
                    if (act == last) continue
                    val w = when (act) {
                        Sleep -> 3
                        Stretch, Sit -> 2
                        else -> 1
                    }
                    repeat(w) { add(act) }
                }
            }
            return weighted.randomOrNull() ?: Sleep
        }
    }
}

/** 在两种颜色之间按比例插值，用于生成机器人主题色。 */
private fun mixColor(a: Color, b: Color, ratio: Float): Color {
    val t = ratio.coerceIn(0f, 1f)
    return Color(
        red = a.red * (1f - t) + b.red * t,
        green = a.green * (1f - t) + b.green * t,
        blue = a.blue * (1f - t) + b.blue * t,
        alpha = 1f,
    )
}

/**
 * 1:1 复刻 Web `CssRobotRenderer.vue` 的高质感主题自适应机器人悬浮入口：
 * - 基于主题强调色派生外壳高光/中调/暗部与清晰 2dp 实线描边（去除旧版半透明灰雾）；
 * - 靠近屏幕左右边缘闲置 4.2s 进入「贴边探头」形态：保持 100% 不透明，歪头 ±19° 露出半脸与单眼，内侧手臂 78° 扒在最前层；
 * - 5.8s 上半身轻呼吸 + 7.6s 双眨眼 + 全部 16 个 Web 动作 + 拖拽晃动彩蛋（晃 3 次晕眩、6 次散架重组、久拖困惑、轻挪点头）。
 */
@Composable
fun FloatingAgentMascot(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    thinking: Boolean = false,
    motionActive: Boolean = true,
) {
    val colors = LocalMoviePilotColors.current
    val view = LocalView.current
    val cfg = LocalConfiguration.current
    val layoutDir = LocalLayoutDirection.current
    val density = LocalDensity.current
    val safePadding = WindowInsets.systemBars.union(WindowInsets.displayCutout).asPaddingValues()
    val safeLeftPx = with(density) { safePadding.calculateLeftPadding(layoutDir).toPx() }
    val safeRightPx = with(density) { safePadding.calculateRightPadding(layoutDir).toPx() }
    val statusTopPx = with(density) { safePadding.calculateTopPadding().toPx() }
    val navBottomPx = with(density) { safePadding.calculateBottomPadding().toPx() }
    val safeMarginPx = with(density) { 6.dp.toPx() }
    val mascotWidthPx = with(density) { 58.dp.toPx() }
    val mascotHeightPx = with(density) { 70.dp.toPx() }
    val edgeThresholdPx = with(density) { 88.dp.toPx() }
    val shakeDeltaPx = with(density) { 18.dp.toPx() }
    val screenSizeKey = cfg.screenWidthDp to cfg.screenHeightDp

    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }
    var anchorX by remember { mutableFloatStateOf(-1f) }
    var anchorY by remember { mutableFloatStateOf(-1f) }
    var rootWidthPx by remember { mutableFloatStateOf(0f) }
    var rootHeightPx by remember { mutableFloatStateOf(0f) }
    var lastOrientation by remember { mutableStateOf(cfg.orientation) }
    var isDragging by remember { mutableStateOf(false) }
    var isIdleDocked by remember { mutableStateOf(false) }
    var idleRevision by remember { mutableIntStateOf(0) }

    var activeAction by remember { mutableStateOf<AgentMascotAction?>(null) }
    var actionStartMs by remember { mutableStateOf(0L) }
    var lastRandomAction by remember { mutableStateOf<AgentMascotAction?>(null) }
    var animClockMs by remember { mutableStateOf(System.currentTimeMillis()) }

    var dragStartedAtMs by remember { mutableStateOf(0L) }
    var shakePivotX by remember { mutableFloatStateOf(0f) }
    var shakeDir by remember { mutableIntStateOf(0) }
    var shakeTurns by remember { mutableIntStateOf(0) }
    var lastShakeTurnMs by remember { mutableStateOf(0L) }

        /** 启动指定机器人动作并重置对应的动画计时。 */
    fun playAction(act: AgentMascotAction) {
        activeAction = act
        actionStartMs = System.currentTimeMillis()
    }

    fun clampOffsets(rawX: Float, rawY: Float): Pair<Float, Float> {
        val vw = if (rootWidthPx > 0f) rootWidthPx else view.width.toFloat()
        val vh = if (rootHeightPx > 0f) rootHeightPx else view.height.toFloat()
        if (vw <= 0f || vh <= 0f || anchorX < 0f || anchorY < 0f) return rawX to rawY
        val minX = (safeLeftPx + safeMarginPx) - anchorX
        val maxX = (vw - safeRightPx - mascotWidthPx - safeMarginPx) - anchorX
        val minY = (statusTopPx + safeMarginPx) - anchorY
        val maxY = (vh - navBottomPx - mascotHeightPx - safeMarginPx) - anchorY
        val cx = if (maxX >= minX) rawX.coerceIn(minX, maxX) else 0f
        val cy = if (maxY >= minY) rawY.coerceIn(minY, maxY) else 0f
        return cx to cy
    }

    LaunchedEffect(cfg.orientation) {
        if (cfg.orientation != lastOrientation) {
            lastOrientation = cfg.orientation
            offsetX = 0f
            offsetY = 0f
            idleRevision++
        }
    }

    LaunchedEffect(screenSizeKey, rootWidthPx, rootHeightPx, anchorX, anchorY) {
        if (anchorX >= 0f && anchorY >= 0f) {
            val (cx, cy) = clampOffsets(offsetX, offsetY)
            offsetX = cx
            offsetY = cy
        }
    }

    LaunchedEffect(idleRevision, motionActive, thinking) {
        isIdleDocked = false
        if (!motionActive || thinking) return@LaunchedEffect
        delay(4200L)
        if (!isDragging && !thinking) {
            isIdleDocked = true
        }
    }

    LaunchedEffect(activeAction, actionStartMs) {
        val act = activeAction ?: return@LaunchedEffect
        delay(act.durationMs)
        if (activeAction == act) {
            activeAction = null
        }
    }

    LaunchedEffect(thinking) {
        if (thinking) {
            isIdleDocked = false
            playAction(AgentMascotAction.Scan)
        }
    }

    // 30fps 轻量级动画时钟（后台或暂停时停止）
    LaunchedEffect(motionActive) {
        if (!motionActive) return@LaunchedEffect
        while (true) {
            animClockMs = System.currentTimeMillis()
            delay(33L)
        }
    }

    // 12–24s 随机日常闲置动作调度
    LaunchedEffect(motionActive) {
        if (!motionActive) return@LaunchedEffect
        while (true) {
            delay((12000L..24000L).random())
            if (!isDragging && !isIdleDocked && !thinking && activeAction == null) {
                val next = AgentMascotAction.pickRandomIdle(lastRandomAction)
                lastRandomAction = next
                playAction(next)
            }
        }
    }

    val vwNow = if (rootWidthPx > 0f) rootWidthPx else view.width.toFloat()
    val currentLeftPx = anchorX + offsetX
    val distToLeft = if (anchorX >= 0f) currentLeftPx - safeLeftPx else Float.MAX_VALUE
    val distToRight = if (anchorX >= 0f && vwNow > 0f) (vwNow - safeRightPx) - (currentLeftPx + mascotWidthPx) else 0f
    val nearEdge = distToLeft <= edgeThresholdPx || distToRight <= edgeThresholdPx
    val dockLeft = distToLeft < distToRight
    val effectiveDocked = isIdleDocked && !isDragging && !thinking && nearEdge

    val dragScale by animateFloatAsState(
        targetValue = if (isDragging) 1.06f else 1.0f,
        animationSpec = tween(durationMillis = 160),
        label = "mascotDragScale",
    )
    val dockShiftTargetPx = run {
        if (!effectiveDocked || anchorX < 0f || vwNow <= 0f) {
            0f
        } else if (dockLeft) {
            (safeLeftPx - mascotWidthPx * 0.36f) - (anchorX + offsetX)
        } else {
            // 右侧再向外收半身，只露出探头与扒边手臂。
            (vwNow - safeRightPx - mascotWidthPx * 0.50f) - (anchorX + offsetX)
        }
    }
    val dockShiftPx by animateFloatAsState(
        targetValue = dockShiftTargetPx,
        animationSpec = tween(durationMillis = 280),
        label = "mascotDockShift",
    )

    val ink = Color(0xFF090510)
    val accent = colors.accent
    val outline = remember(accent) { mixColor(accent, ink, 0.68f) }
    val outlineSoft = remember(accent) { mixColor(accent, ink, 0.46f) }
    val shellStart = remember(accent) { mixColor(accent, Color.White, 0.54f) }
    val shellMid = remember(accent) { mixColor(accent, Color.White, 0.16f) }
    val shellEnd = remember(accent) { mixColor(accent, ink, 0.18f) }
    val shellShade = Color(0x3D090510)
    val faceStart = Color(0xFF221B3A)
    val faceEnd = Color(0xFF0C0F1E)
    val eyeColor = Color(0xFFF5F2FF)
    val eyeGlow = Color(0xFF72FFF0)

    Box(
        modifier = modifier
            .onGloballyPositioned { coords ->
                val rootPos = coords.positionInRoot()
                val nw = view.width.toFloat()
                val nh = view.height.toFloat()
                if (kotlin.math.abs(rootPos.x - anchorX) > 0.5f) anchorX = rootPos.x
                if (kotlin.math.abs(rootPos.y - anchorY) > 0.5f) anchorY = rootPos.y
                if (kotlin.math.abs(nw - rootWidthPx) > 0.5f) rootWidthPx = nw
                if (kotlin.math.abs(nh - rootHeightPx) > 0.5f) rootHeightPx = nh
            }
            .offset { IntOffset((offsetX + dockShiftPx).roundToInt(), offsetY.roundToInt()) }
            .size(width = 58.dp, height = 70.dp)
            .graphicsLayer {
                scaleX = dragScale
                scaleY = dragScale
                alpha = 1f
            }
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = {
                        isIdleDocked = false
                        isDragging = true
                        activeAction = null
                        dragStartedAtMs = System.currentTimeMillis()
                        shakePivotX = offsetX
                        shakeDir = 0
                        shakeTurns = 0
                        lastShakeTurnMs = 0L
                    },
                    onDragEnd = {
                        isDragging = false
                        idleRevision++
                        val now = System.currentTimeMillis()
                        val recentTurns = if (now - lastShakeTurnMs <= 550L) shakeTurns else 0
                        val elapsed = now - dragStartedAtMs
                        val reaction = when {
                            recentTurns >= 6 -> AgentMascotAction.Disassemble
                            recentTurns >= 3 -> AgentMascotAction.Faint
                            elapsed > 4000L -> AgentMascotAction.Confused
                            else -> AgentMascotAction.Nod
                        }
                        playAction(reaction)
                    },
                    onDragCancel = {
                        isDragging = false
                        idleRevision++
                    },
                ) { change, dragAmount ->
                    change.consume()
                    val (cx, cy) = clampOffsets(offsetX + dragAmount.x, offsetY + dragAmount.y)
                    offsetX = cx
                    offsetY = cy
                    val delta = cx - shakePivotX
                    if (kotlin.math.abs(delta) >= shakeDeltaPx) {
                        val dir = if (delta > 0f) 1 else -1
                        val now = System.currentTimeMillis()
                        if (now - lastShakeTurnMs > 550L) shakeTurns = 0
                        if (shakeDir != 0 && dir != shakeDir) shakeTurns++
                        shakeDir = dir
                        shakePivotX = cx
                        lastShakeTurnMs = now
                    }
                }
            }
            .clickable {
                if (effectiveDocked) {
                    isIdleDocked = false
                    playAction(AgentMascotAction.Wake)
                }
                idleRevision++
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val sx = size.width / 58f
            val sy = size.height / 70f
            val cx = size.width * 0.5f
            val cy = size.height * 0.5f
            val timeSec = (animClockMs % 3_600_000L) / 1000.0
            val act = if (effectiveDocked) null else activeAction
            val p = if (act != null) {
                ((animClockMs - actionStartMs).toDouble() / act.durationMs.coerceAtLeast(100L)).coerceIn(0.0, 1.0)
            } else {
                0.0
            }

            val breath = if (motionActive && act == null && !effectiveDocked && !isDragging) {
                sin((timeSec / 5.8) * 2.0 * PI).coerceAtLeast(0.0)
            } else {
                0.0
            }
            val blinkPhase = (timeSec % 7.6) / 7.6
            val blinkClosed = motionActive && ((blinkPhase in 0.33..0.365) || (blinkPhase in 0.77..0.805))

            var rootOx = 0f
            var rootOy = 0f
            var rootRot = 0f
            var headOx = 0f
            var headOy = (-1.3f * breath.toFloat()) * sy
            var headRot = -3f
            var bodyOy = 0f
            var bodyScaleX = 1f + 0.02f * breath.toFloat()
            var bodyScaleY = 1f + 0.036f * breath.toFloat()
            var leftArmDeg = 17f
            var rightArmDeg = -17f
            var leftArmOx = 0f
            var leftArmOy = 0f
            var rightArmOx = 0f
            var rightArmOy = 0f
            var leftLegOx = 0f
            var leftLegOy = 0f
            var rightLegOx = 0f
            var rightLegOy = 0f
            var eyeOx = 0f
            var eyeOy = 0f
            var eyeScaleY = if (blinkClosed) 0.14f else 1f
            var antennaDeg = 22f
            var showBlush = false
            var showScan = thinking
            var happyEyes = false

            when (act) {
                AgentMascotAction.Nod -> {
                    headOy += sin(p * PI * 4.0).toFloat() * 2.2f * sy
                    headRot += sin(p * PI * 4.0).toFloat() * 6f
                }
                AgentMascotAction.Wake -> {
                    val hop = sin((p * 2.2).coerceAtMost(1.0) * PI).toFloat()
                    rootOy -= hop * 6f * sy
                    antennaDeg -= hop * 18f
                }
                AgentMascotAction.Wave -> {
                    val env = sin((p * 3.0).coerceAtMost(1.0) * PI * 0.5).toFloat() *
                        sin(((1.0 - p) * 3.0).coerceAtMost(1.0) * PI * 0.5).toFloat()
                    rightArmDeg = -17f - env * (128f + sin(p * PI * 10.0).toFloat() * 20f)
                    headRot += env * 7f
                    eyeOx += env * 1.4f * sx
                }
                AgentMascotAction.Sit -> {
                    val env = sin((p * 3.5).coerceAtMost(1.0) * PI * 0.5).toFloat() *
                        sin(((1.0 - p) * 3.5).coerceAtMost(1.0) * PI * 0.5).toFloat()
                    bodyOy += env * 4.5f * sy
                    headOy += env * 5.2f * sy
                    leftLegOx = -2.2f * sx * env
                    leftLegOy = -2.5f * sy * env
                    rightLegOx = 2.2f * sx * env
                    rightLegOy = -2.5f * sy * env
                }
                AgentMascotAction.EyeRoll -> {
                    eyeOx = cos(p * PI * 2.0).toFloat() * 2.4f * sx
                    eyeOy = -kotlin.math.abs(sin(p * PI * 2.0).toFloat()) * 2.6f * sy
                }
                AgentMascotAction.Faint -> {
                    val env = sin((p * 4.0).coerceAtMost(1.0) * PI * 0.5).toFloat() *
                        sin(((1.0 - p) * 4.0).coerceAtMost(1.0) * PI * 0.5).toFloat()
                    rootRot = env * (24f + sin(p * PI * 6.0).toFloat() * 5f)
                    rootOy += env * 4f * sy
                    eyeScaleY = 0.24f
                }
                AgentMascotAction.Disassemble -> {
                    val burst = sin(((p - 0.08) / 0.72).coerceIn(0.0, 1.0) * PI).toFloat()
                    headOy -= burst * 9.5f * sy
                    headRot += burst * 18f
                    leftArmOx = -7.5f * sx * burst
                    leftArmOy = -3f * sy * burst
                    rightArmOx = 7.5f * sx * burst
                    rightArmOy = -3f * sy * burst
                    leftArmDeg += burst * 42f
                    rightArmDeg -= burst * 42f
                    leftLegOx = -4f * sx * burst
                    leftLegOy = 4f * sy * burst
                    rightLegOx = 4f * sx * burst
                    rightLegOy = 4f * sy * burst
                    bodyOy += burst * 2.5f * sy
                }
                AgentMascotAction.HappyJump -> {
                    val bounce = kotlin.math.abs(sin(p * PI * 3.0).toFloat())
                    rootOy -= bounce * 11f * sy
                    leftArmDeg = 17f + bounce * 118f
                    rightArmDeg = -17f - bounce * 118f
                    happyEyes = true
                }
                AgentMascotAction.Sleep -> {
                    val env = sin((p * 4.0).coerceAtMost(1.0) * PI * 0.5).toFloat() *
                        sin(((1.0 - p) * 4.0).coerceAtMost(1.0) * PI * 0.5).toFloat()
                    headOy += env * 2.6f * sy + sin(p * PI * 6.0).toFloat() * 0.8f * sy
                    headRot -= env * 9f
                    eyeScaleY = (1f - env * 0.86f).coerceAtLeast(0.14f)
                }
                AgentMascotAction.Stretch -> {
                    val env = sin((p * 3.0).coerceAtMost(1.0) * PI * 0.5).toFloat() *
                        sin(((1.0 - p) * 3.0).coerceAtMost(1.0) * PI * 0.5).toFloat()
                    bodyScaleY = 1f + env * 0.14f
                    bodyScaleX = 1f - env * 0.06f
                    headOy -= env * 3.6f * sy
                    leftArmDeg = 17f + env * 130f
                    rightArmDeg = -17f - env * 130f
                }
                AgentMascotAction.Peek -> {
                    val look = sin(p * PI * 2.0).toFloat()
                    headOx += look * 4.2f * sx
                    headRot += look * 9f
                    eyeOx += look * 2.6f * sx
                }
                AgentMascotAction.Scan -> {
                    showScan = true
                    eyeOx = sin(p * PI * 4.0).toFloat() * 2.2f * sx
                }
                AgentMascotAction.Charge -> {
                    val env = (p * 1.4).coerceAtMost(1.0).toFloat()
                    rootOx += sin(p * PI * 28.0).toFloat() * 1.3f * sx * env
                    bodyScaleX = 1f + env * 0.06f
                    bodyScaleY = 1f - env * 0.05f
                    leftArmDeg = 17f + env * 36f
                    rightArmDeg = -17f - env * 36f
                }
                AgentMascotAction.SpinCheer -> {
                    rootRot = if (p < 0.65) (p / 0.65).toFloat() * 360f else 0f
                    val lift = sin(p * PI).toFloat()
                    rootOy -= lift * 9f * sy
                    leftArmDeg = 17f + lift * 132f
                    rightArmDeg = -17f - lift * 132f
                    happyEyes = true
                }
                AgentMascotAction.Shy -> {
                    val env = sin((p * 3.5).coerceAtMost(1.0) * PI * 0.5).toFloat() *
                        sin(((1.0 - p) * 3.5).coerceAtMost(1.0) * PI * 0.5).toFloat()
                    showBlush = env > 0.2f
                    headRot += sin(p * PI * 2.0).toFloat() * 7f * env
                    leftArmDeg = 17f - env * 28f
                    rightArmDeg = -17f + env * 28f
                }
                AgentMascotAction.Confused -> {
                    val env = sin((p * 3.5).coerceAtMost(1.0) * PI * 0.5).toFloat() *
                        sin(((1.0 - p) * 3.5).coerceAtMost(1.0) * PI * 0.5).toFloat()
                    headRot += env * 18f
                    eyeOx += env * 1.2f * sx
                }
                null -> Unit
            }

            if (effectiveDocked) {
                rootRot = if (dockLeft) 19f else -19f
                rootOy = -2f * sy
                antennaDeg = if (dockLeft) -12f else 12f
                eyeOx = (if (dockLeft) 2.2f else -2.2f) * sx
            }

            val strokeW = (1.9f * sx).coerceAtLeast(1.6f)
            val bodyVisible = !effectiveDocked

            // 底层柔影
            if (bodyVisible) {
                drawOval(
                    color = outline.copy(alpha = 0.28f),
                    topLeft = Offset(cx + rootOx - 17f * sx, cy + 27f * sy),
                    size = Size(34f * sx, 7.5f * sy),
                )
            }

                        /** 绘制按动作角度旋转的机器人手臂。 */
            fun drawArm(ax: Float, ay: Float, aw: Float, ah: Float, deg: Float) {
                rotate(degrees = deg, pivot = Offset(ax, ay)) {
                    drawRoundRect(
                        brush = Brush.verticalGradient(listOf(shellMid, outlineSoft), startY = ay - ah * 0.5f, endY = ay + ah * 0.5f),
                        topLeft = Offset(ax - aw * 0.5f, ay - ah * 0.5f),
                        size = Size(aw, ah),
                        cornerRadius = CornerRadius(aw * 0.5f, aw * 0.5f),
                    )
                    drawRoundRect(
                        color = outline,
                        topLeft = Offset(ax - aw * 0.5f, ay - ah * 0.5f),
                        size = Size(aw, ah),
                        cornerRadius = CornerRadius(aw * 0.5f, aw * 0.5f),
                        style = Stroke(width = strokeW),
                    )
                }
            }

            rotate(degrees = rootRot, pivot = Offset(cx + rootOx, cy + rootOy)) {
                val baseCx = cx + rootOx
                val baseCy = cy + rootOy

                if (bodyVisible) {
                    // 1. 双腿
                    for (side in listOf(-1f, 1f)) {
                        val lxOff = if (side < 0f) leftLegOx else rightLegOx
                        val lyOff = if (side < 0f) leftLegOy else rightLegOy
                        val legW = 8.4f * sx
                        val legH = 9f * sy
                        val lx = baseCx + side * 7.6f * sx - legW * 0.5f + lxOff
                        val ly = baseCy + 25f * sy - legH * 0.5f + lyOff
                        drawRoundRect(
                            brush = Brush.verticalGradient(listOf(shellMid, outlineSoft), startY = ly, endY = ly + legH),
                            topLeft = Offset(lx, ly),
                            size = Size(legW, legH),
                            cornerRadius = CornerRadius(4f * sx, 4f * sy),
                        )
                        drawRoundRect(
                            color = outline,
                            topLeft = Offset(lx, ly),
                            size = Size(legW, legH),
                            cornerRadius = CornerRadius(4f * sx, 4f * sy),
                            style = Stroke(width = strokeW),
                        )
                    }

                    // 2. 双手臂
                    drawArm(baseCx - 15.8f * sx + leftArmOx, baseCy + 13.5f * sy + leftArmOy, 7.4f * sx, 13.4f * sy, leftArmDeg)
                    drawArm(baseCx + 15.8f * sx + rightArmOx, baseCy + 13.5f * sy + rightArmOy, 7.4f * sx, 13.4f * sy, rightArmDeg)

                    // 3. 躯干 + 胸口播放三角
                    val bodyW = 26.8f * sx * bodyScaleX
                    val bodyH = 19.8f * sy * bodyScaleY
                    val bx = baseCx - bodyW * 0.5f
                    val by = baseCy + 13.8f * sy + bodyOy - bodyH * 0.5f
                    drawRoundRect(
                        brush = Brush.linearGradient(listOf(shellMid, shellEnd), start = Offset(bx, by), end = Offset(bx + bodyW, by + bodyH)),
                        topLeft = Offset(bx, by),
                        size = Size(bodyW, bodyH),
                        cornerRadius = CornerRadius(9.2f * sx, 9.2f * sy),
                    )
                    drawRoundRect(
                        color = Color.White.copy(alpha = 0.24f),
                        topLeft = Offset(bx + 2.5f * sx, by + 1.4f * sy),
                        size = Size(bodyW - 5f * sx, 3.8f * sy),
                        cornerRadius = CornerRadius(3f * sx, 3f * sy),
                    )
                    drawRoundRect(
                        color = shellShade,
                        topLeft = Offset(bx + 1.5f * sx, by + bodyH - 3.6f * sy),
                        size = Size(bodyW - 3f * sx, 2.8f * sy),
                        cornerRadius = CornerRadius(3f * sx, 3f * sy),
                    )
                    drawRoundRect(
                        color = outline,
                        topLeft = Offset(bx, by),
                        size = Size(bodyW, bodyH),
                        cornerRadius = CornerRadius(9.2f * sx, 9.2f * sy),
                        style = Stroke(width = strokeW),
                    )
                    val playCx = baseCx + 0.9f * sx
                    val playCy = baseCy + 13.8f * sy + bodyOy
                    val playPath = Path().apply {
                        moveTo(playCx - 3.4f * sx, playCy - 4.4f * sy)
                        lineTo(playCx + 4.4f * sx, playCy)
                        lineTo(playCx - 3.4f * sx, playCy + 4.4f * sy)
                        close()
                    }
                    drawPath(playPath, if (thinking) eyeGlow else Color.White)
                }

                // 4. 头部 + 天线 + 深色面罩 + 弯月眼睛
                val headPivot = Offset(baseCx + headOx, baseCy - 7.5f * sy + headOy)
                rotate(degrees = headRot, pivot = headPivot) {
                    val antBase = Offset(headPivot.x + 2.2f * sx, headPivot.y - 14.5f * sy)
                    rotate(degrees = antennaDeg, pivot = antBase) {
                        drawLine(
                            color = outline.copy(alpha = if (effectiveDocked) 0.8f else 1f),
                            start = antBase,
                            end = Offset(antBase.x, antBase.y - 8.5f * sy),
                            strokeWidth = 2.6f * sx,
                            cap = StrokeCap.Round,
                        )
                        val ballCenter = Offset(antBase.x, antBase.y - 10.5f * sy)
                        drawCircle(color = shellStart, radius = 3.4f * sx, center = ballCenter)
                        drawCircle(
                            color = outline.copy(alpha = if (effectiveDocked) 0.8f else 1f),
                            radius = 3.4f * sx,
                            center = ballCenter,
                            style = Stroke(width = strokeW * 0.92f),
                        )
                    }

                    val headW = 45f * sx
                    val headH = 31f * sy
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
                        cornerRadius = CornerRadius(10.8f * sx, 10.8f * sy),
                    )
                    drawRoundRect(
                        color = Color.White.copy(alpha = 0.28f),
                        topLeft = Offset(hx + 3f * sx, hy + 1.5f * sy),
                        size = Size(headW - 6f * sx, 4.5f * sy),
                        cornerRadius = CornerRadius(3.5f * sx, 3.5f * sy),
                    )
                    drawRoundRect(
                        color = shellShade,
                        topLeft = Offset(hx + 2f * sx, hy + headH - 3.8f * sy),
                        size = Size(headW - 4f * sx, 3f * sy),
                        cornerRadius = CornerRadius(3f * sx, 3f * sy),
                    )
                    drawRoundRect(
                        color = outline,
                        topLeft = Offset(hx, hy),
                        size = Size(headW, headH),
                        cornerRadius = CornerRadius(10.8f * sx, 10.8f * sy),
                        style = Stroke(width = strokeW),
                    )

                    val faceW = 34f * sx
                    val faceH = 19.8f * sy
                    val fx = headPivot.x - 1.5f * sx - faceW * 0.5f
                    val fy = headPivot.y + 0.6f * sy - faceH * 0.5f
                    drawRoundRect(
                        brush = Brush.verticalGradient(listOf(faceStart, faceEnd), startY = fy, endY = fy + faceH),
                        topLeft = Offset(fx, fy),
                        size = Size(faceW, faceH),
                        cornerRadius = CornerRadius(7.2f * sx, 7.2f * sy),
                    )
                    drawRoundRect(
                        color = if (thinking || showScan) eyeGlow.copy(alpha = 0.65f) else outlineSoft,
                        topLeft = Offset(fx, fy),
                        size = Size(faceW, faceH),
                        cornerRadius = CornerRadius(7.2f * sx, 7.2f * sy),
                        style = Stroke(width = 1.6f * sx),
                    )

                    if (showScan) {
                        val sweep = ((sin(timeSec * 4.2) + 1.0) * 0.5).toFloat()
                        val bxScan = fx + 3f * sx + sweep * (faceW - 6f * sx)
                        drawRect(
                            color = eyeGlow.copy(alpha = 0.30f),
                            topLeft = Offset(bxScan - 2f * sx, fy + 1.5f * sy),
                            size = Size(4f * sx, faceH - 3f * sy),
                        )
                    }

                    if (showBlush) {
                        drawOval(
                            color = Color(0x8CFF73A8),
                            topLeft = Offset(fx + 3f * sx, fy + faceH * 0.60f),
                            size = Size(5.5f * sx, 3f * sy),
                        )
                        drawOval(
                            color = Color(0x8CFF73A8),
                            topLeft = Offset(fx + faceW - 8.5f * sx, fy + faceH * 0.60f),
                            size = Size(5.5f * sx, 3f * sy),
                        )
                    }

                                        /** 绘制带高光与状态变化的机器人眼部。 */
                    fun drawRobotEye(ecx: Float, eCy: Float) {
                        val ew = 7.6f * sx
                        val eh = (5.2f * sy * eyeScaleY).coerceAtLeast(1f)
                        val rx = ew * 0.5f
                        val outerRy = eh
                        val innerRy = eh * 0.52f
                        val dir = if (happyEyes) -1f else 1f
                        val baseY = if (happyEyes) eCy + outerRy * 0.45f else eCy - outerRy * 0.35f
                        val path = Path()
                        val steps = 16
                        for (i in 0..steps) {
                            val theta = (i.toDouble() / steps) * PI
                            val x = ecx - rx * cos(theta).toFloat()
                            val y = baseY + dir * outerRy * sin(theta).toFloat()
                            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                        }
                        for (i in steps downTo 0) {
                            val theta = (i.toDouble() / steps) * PI
                            val x = ecx - rx * cos(theta).toFloat()
                            val y = baseY + dir * innerRy * sin(theta).toFloat()
                            path.lineTo(x, y)
                        }
                        path.close()
                        drawPath(path, if (thinking || showScan) eyeGlow else eyeColor)
                    }

                    val eyeBaseX = fx + faceW * 0.5f + eyeOx
                    val eyeBaseY = fy + faceH * 0.5f - 1.2f * sy + eyeOy
                    drawRobotEye(eyeBaseX - 7.3f * sx, eyeBaseY)
                    drawRobotEye(eyeBaseX + 7.3f * sx, eyeBaseY + 0.5f * sy)
                }

                // 5. 贴边探头专属：内侧小手移至最前层 ±78° 扒住屏幕边缘
                if (effectiveDocked) {
                    drawArm(
                        ax = if (dockLeft) baseCx + 4.5f * sx else baseCx - 4.5f * sx,
                        ay = baseCy + 12.5f * sy,
                        aw = 6.4f * sx,
                        ah = 13.8f * sy,
                        deg = if (dockLeft) -78f else 78f,
                    )
                }
            }
        }
    }
}
