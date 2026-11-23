package com.moviepilot.designsystem

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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
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
import kotlin.math.roundToInt

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

/** 自适应筛选/分类胶囊按钮（对齐 iOS `NativeAdaptivePill`）。 */
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
    val activeColor = tint ?: colors.accent
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(if (selected) activeColor else colors.chipFill)
            .border(
                width = 0.7.dp,
                color = if (selected) activeColor.copy(alpha = 0.8f) else colors.chipBorder,
                shape = CircleShape,
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (selected) Color.White else colors.chipText,
                modifier = Modifier.size(14.dp),
            )
        }
        Text(
            text = title,
            color = if (selected) Color.White else colors.chipText,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
    }
}

/** 圆形原生玻璃图标按钮（顶部返回、切换服务、语言切换等）。 */
@Composable
fun CinematicCircleButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 42.dp,
) {
    val colors = LocalMoviePilotColors.current
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(if (colors.isDark) Color.White.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.65f))
            .border(
                0.8.dp,
                if (colors.isDark) Color.White.copy(alpha = 0.22f) else Color.Black.copy(alpha = 0.10f),
                CircleShape,
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = colors.textPrimary,
            modifier = Modifier.size(20.dp),
        )
    }
}

/** 页面顶部统一玻璃导航栏（带状态栏安全区避让、可选返回钮与右侧动作胶囊）。 */
@Composable
fun NativeGlassTopBar(
    title: String,
    onBack: (() -> Unit)? = null,
    trailing: (@Composable RowScope.() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = LocalMoviePilotColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            CinematicCircleButton(
                icon = Icons.AutoMirrored.Rounded.ArrowBack,
                contentDescription = "返回",
                onClick = onBack,
            )
        } else {
            Spacer(Modifier.width(42.dp))
        }
        Box(
            modifier = Modifier.weight(1f),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = title,
                color = colors.textPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (trailing != null) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
                content = trailing,
            )
        } else {
            Spacer(Modifier.width(42.dp))
        }
    }
}

/** 区块标题行（左标题 + 右侧可选“查看全部”箭头或副标签）。 */
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
            .then(if (onClickMore != null) Modifier.clickable(onClick = onClickMore) else Modifier),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = title,
            color = colors.textPrimary,
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (!subtitle.isNullOrBlank()) {
                Text(
                    text = subtitle,
                    color = colors.textSecondary,
                    fontSize = 13.sp,
                )
            }
            if (onClickMore != null) {
                Icon(
                    imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = null,
                    tint = colors.textSecondary,
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

/** 通用 2:3 竖版影视海报卡（右上角评分或绿色已入库勾标，底部标题与年份）。 */
@Composable
fun NativePosterCard(
    title: String,
    year: String,
    posterUrl: String?,
    voteAverage: Double = 0.0,
    inLibrary: Boolean = false,
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
            if (!posterUrl.isNullOrBlank()) {
                AsyncImage(
                    model = posterUrl,
                    contentDescription = title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Box(
                    modifier = Modifier.fillMaxSize().padding(10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = title,
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (inLibrary) {
                Icon(
                    imageVector = Icons.Rounded.CheckCircle,
                    contentDescription = "已入库",
                    tint = Color(0xFF34D058),
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(20.dp)
                        .clip(CircleShape)
                        .background(Color.White),
                )
            } else if (voteAverage > 0.0) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.Black.copy(alpha = 0.62f))
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
 * 可自由拖动停靠的紫色 AI 智能助手悬浮机器人（对齐 iOS `NativeAgentFloatingMascot`）：
 * 支持任意坐标平滑拖曳且不强制贴边、零拖影，点击直达 AI 智能助手对话页。
 */
@Composable
fun FloatingAgentMascot(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }

    Box(
        modifier = modifier
            .offset { IntOffset(offsetX.roundToInt(), offsetY.roundToInt()) }
            .size(56.dp)
            .shadow(10.dp, CircleShape, ambientColor = Color(0x889E7AF5), spotColor = Color(0x889E7AF5))
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    offsetX += dragAmount.x
                    offsetY += dragAmount.y
                }
            }
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.size(52.dp)) {
            val w = size.width
            val h = size.height
            // 天线
            drawLine(
                color = Color(0xFFBBA3FF),
                start = Offset(w * 0.50f, h * 0.16f),
                end = Offset(w * 0.52f, h * 0.06f),
                strokeWidth = w * 0.05f,
            )
            drawCircle(
                color = Color(0xFFD6C7FF),
                radius = w * 0.055f,
                center = Offset(w * 0.53f, h * 0.06f),
            )
            // 机器人头部
            drawRoundRect(
                brush = Brush.verticalGradient(listOf(Color(0xFF9C7BF5), Color(0xFF7252D6))),
                topLeft = Offset(w * 0.14f, h * 0.16f),
                size = Size(w * 0.72f, h * 0.48f),
                cornerRadius = CornerRadius(w * 0.18f, w * 0.18f),
            )
            // 深色面罩屏
            drawRoundRect(
                color = Color(0xFF1A162C),
                topLeft = Offset(w * 0.22f, h * 0.24f),
                size = Size(w * 0.56f, h * 0.30f),
                cornerRadius = CornerRadius(w * 0.11f, w * 0.11f),
            )
            // 柔和双眼
            drawRoundRect(
                color = Color(0xFFE7DEFF),
                topLeft = Offset(w * 0.31f, h * 0.37f),
                size = Size(w * 0.12f, h * 0.05f),
                cornerRadius = CornerRadius(4f, 4f),
            )
            drawRoundRect(
                color = Color(0xFFE7DEFF),
                topLeft = Offset(w * 0.57f, h * 0.37f),
                size = Size(w * 0.12f, h * 0.05f),
                cornerRadius = CornerRadius(4f, 4f),
            )
            // 身体 + 播放三角标识
            drawRoundRect(
                brush = Brush.verticalGradient(listOf(Color(0xFF8B6AF0), Color(0xFF6242C4))),
                topLeft = Offset(w * 0.24f, h * 0.64f),
                size = Size(w * 0.52f, h * 0.26f),
                cornerRadius = CornerRadius(w * 0.12f, w * 0.12f),
            )
            val playPath = Path().apply {
                moveTo(w * 0.45f, h * 0.71f)
                lineTo(w * 0.59f, h * 0.77f)
                lineTo(w * 0.45f, h * 0.83f)
                close()
            }
            drawPath(playPath, Color.White)
        }
    }
}
