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
    val mascotWidthPx = with(density) { 50.dp.toPx() }
    val mascotHeightPx = with(density) { 60.dp.toPx() }
    val screenSizeKey = cfg.screenWidthDp to cfg.screenHeightDp

    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }
    var anchorX by remember { mutableFloatStateOf(-1f) }
    var anchorY by remember { mutableFloatStateOf(-1f) }
    var rootWidthPx by remember { mutableFloatStateOf(0f) }
    var rootHeightPx by remember { mutableFloatStateOf(0f) }
    var lastOrientation by remember { mutableStateOf(cfg.orientation) }
    var isDragging by remember { mutableStateOf(false) }
    var isBlinking by remember { mutableStateOf(false) }
    var isIdleDocked by remember { mutableStateOf(false) }
    var idleRevision by remember { mutableIntStateOf(0) }

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

    LaunchedEffect(idleRevision) {
        isIdleDocked = false
        delay(3200L)
        if (!isDragging) {
            isIdleDocked = true
        }
    }

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
        targetValue = when {
            isDragging -> 1.06f
            isIdleDocked -> 0.90f
            else -> 1.0f
        },
        animationSpec = tween(durationMillis = 200),
        label = "mascotDragScale",
    )
    val idleAlpha by animateFloatAsState(
        targetValue = when {
            isDragging -> 1.0f
            isIdleDocked -> 0.50f
            else -> 0.94f
        },
        animationSpec = tween(durationMillis = 260),
        label = "mascotIdleAlpha",
    )
    val dockShiftTargetPx = run {
        if (!isIdleDocked || isDragging || anchorX < 0f) {
            0f
        } else {
            val vw = if (rootWidthPx > 0f) rootWidthPx else view.width.toFloat()
            val centerAbsX = anchorX + offsetX + mascotWidthPx * 0.5f
            if (vw > 0f && centerAbsX < vw * 0.5f) {
                (safeLeftPx - mascotWidthPx * 0.34f) - (anchorX + offsetX)
            } else if (vw > 0f) {
                (vw - safeRightPx - mascotWidthPx * 0.66f) - (anchorX + offsetX)
            } else {
                0f
            }
        }
    }
    val dockShiftPx by animateFloatAsState(
        targetValue = dockShiftTargetPx,
        animationSpec = tween(durationMillis = 280),
        label = "mascotDockShift",
    )

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
            .size(width = 50.dp, height = 60.dp)
            .graphicsLayer {
                scaleX = dragScale
                scaleY = dragScale
                alpha = idleAlpha
            }
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = {
                        isIdleDocked = false
                        isDragging = true
                    },
                    onDragEnd = {
                        isDragging = false
                        idleRevision++
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
                }
            }
            .clickable {
                idleRevision++
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val sx = size.width / 56f
            val sy = size.height / 68f
            val cx = size.width * 0.5f
            val cy = size.height * 0.5f

            val outline = Color(0x6B473080)
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
