package com.moviepilot.medal3d

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moviepilot.designsystem.LocalMoviePilotColors
import com.moviepilot.designsystem.NativeAdaptivePill
import com.moviepilot.rustbridge.RustCoreBridge
import kotlin.math.abs

/**
 * 3D 社区勋章实时交互视图（加载共享 73 枚 WebP/Outline 资产 + Rust 金属色板 + Canvas 三遍背面铭牌凹雕）：
 * 支持手指 360° 3D 旋转翻转查看背面定制金属凹雕铭文，金属光泽随旋转角实时反光。
 */
@Composable
fun CommunityMedal3DView(
    medalId: String,
    assetBaseName: String,
    title: String,
    ownerName: String,
    earnedDate: String,
    size: Dp = 200.dp,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val colors = LocalMoviePilotColors.current
    val palette = remember(medalId) { RustCoreBridge.medalPalette(medalId) }
    val baseColor = remember(palette.baseHex) { parseHex(palette.baseHex, 0xFFD4AF37.toInt()) }
    val rimColor = remember(palette.rimHex) { parseHex(palette.rimHex, 0xFFF6E27F.toInt()) }

    val frontBitmap = remember(assetBaseName) { loadMedalWebp(context, assetBaseName) }
    val backBitmap = remember(medalId, title, ownerName, earnedDate) {
        renderEngravedBackPlate(
            baseHex = palette.baseHex,
            rimHex = palette.rimHex,
            darkHex = palette.engraveDarkHex,
            lightHex = palette.engraveLightHex,
            title = title,
            owner = ownerName,
            date = earnedDate,
        )
    }

    var rotY by remember(medalId) { mutableFloatStateOf(0f) }
    var rotX by remember(medalId) { mutableFloatStateOf(0f) }
    val animatedRotY by animateFloatAsState(
        targetValue = rotY,
        animationSpec = spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow),
        label = "medalRotY",
    )
    val animatedRotX by animateFloatAsState(
        targetValue = rotX,
        animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
        label = "medalRotX",
    )
    val normalizedY = ((animatedRotY % 360f) + 360f) % 360f
    val showingBack = normalizedY in 90f..270f
    val sheenAlpha = (1f - abs(((normalizedY % 180f) - 90f) / 90f)) * 0.28f

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .size(size)
                .pointerInput(medalId) {
                    detectDragGestures(
                        onDragEnd = { rotX = 0f },
                        onDragCancel = { rotX = 0f },
                    ) { change, drag ->
                        change.consume()
                        rotY += drag.x * 0.65f
                        rotX = (rotX - drag.y * 0.30f).coerceIn(-24f, 24f)
                    }
                }
                .graphicsLayer {
                    rotationY = animatedRotY
                    rotationX = animatedRotX
                    cameraDistance = 14f * density
                }
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        listOf(Color(rimColor), Color(baseColor), Color(0xFF1F1A2C)),
                    ),
                )
                .border(3.dp, Color(rimColor).copy(alpha = 0.85f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (!showingBack) {
                if (frontBitmap != null) {
                    Image(
                        bitmap = frontBitmap.asImageBitmap(),
                        contentDescription = title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().padding(6.dp).clip(CircleShape),
                    )
                } else {
                    Text(
                        text = title.take(4),
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 18.sp,
                    )
                }
            } else {
                // 背面铭牌做水平镜像抵消 180° Y 轴翻转，确保凹雕文字正向清晰可读
                Image(
                    bitmap = backBitmap.asImageBitmap(),
                    contentDescription = "$title 背面铭牌",
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer { scaleX = -1f }
                        .clip(CircleShape),
                )
            }

            // 随 3D 旋转角动态扫过的金属镜面高光
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.linearGradient(
                            listOf(
                                Color.White.copy(alpha = sheenAlpha),
                                Color.Transparent,
                                Color.White.copy(alpha = sheenAlpha * 0.6f),
                            ),
                        ),
                    ),
            )
        }
        Spacer(Modifier.height(10.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = if (showingBack) "背面金属三遍凹雕铭文" else "左右拖动 360° 旋转",
                color = colors.textMuted,
                fontSize = 12.sp,
            )
            NativeAdaptivePill(
                title = if (showingBack) "翻回正面" else "翻转背面",
                selected = showingBack,
                onClick = { rotY += 180f },
            )
        }
    }
}

/** 从 `assets/community_medals/` 加载共享社区勋章主正面浮雕纹理（排除 height/back 辅助贴图）。 */
fun listBundledMedalAssets(context: Context): List<String> = runCatching {
    val all = context.assets.list("community_medals")
        ?.filter { it.endsWith(".webp") && it.contains("-front") && !it.contains("-height") }
        ?.map { it.removeSuffix(".webp") }
        ?.sorted()
        ?: emptyList()
    // 将高质感主勋章排在前列
    val priority = listOf("maintainer-front", "pioneer-front", "code-front-t4", "plugin-front-t4")
    val prioritized = priority.filter { it in all }
    prioritized + all.filterNot { it in prioritized }
}.getOrDefault(emptyList())

/** 加载勋章正面缩略图供陈列墙展示。 */
fun loadMedalAssetBitmap(context: Context, baseName: String): Bitmap? = loadMedalWebp(context, baseName)

/** 将资产键名映射为可读中文勋章名称。 */
fun medalDisplayName(baseName: String): String = when (baseName) {
    "maintainer-front" -> "核心维护者"
    "pioneer-front" -> "社区先锋"
    "helper-front" -> "热心助手"
    "security-front" -> "安全守护者"
    "tester-front" -> "测试先锋"
    "code-front-t1" -> "代码贡献 I"
    "code-front-t2" -> "代码贡献 II"
    "code-front-t3" -> "代码贡献 III"
    "code-front-t4" -> "代码贡献 IV"
    "plugin-front-t1" -> "插件作者 I"
    "plugin-front-t2" -> "插件作者 II"
    "plugin-front-t3" -> "插件作者 III"
    "plugin-front-t4" -> "插件作者 IV"
    else -> baseName.replace("-", " ").replaceFirstChar { it.uppercase() }
}

private fun loadMedalWebp(context: Context, baseName: String): Bitmap? = runCatching {
    context.assets.open("community_medals/$baseName.webp").use { BitmapFactory.decodeStream(it) }
}.getOrNull()

/**
 * 原生 Android Canvas 三遍金属凹雕渲染（对齐 iOS CoreGraphics 背面雕刻算法）：
 * 1) 亮边偏移 +1.5px 模拟受光底缘；2) 暗槽偏移 -1.5px 模拟内壁阴影；3) 主体刻字层压印。
 */
private fun renderEngravedBackPlate(
    baseHex: String,
    rimHex: String,
    darkHex: String,
    lightHex: String,
    title: String,
    owner: String,
    date: String,
): Bitmap {
    val size = 512
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bmp)
    val cx = size / 2f
    val cy = size / 2f

    val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = parseHex(baseHex, 0xFFD4AF37.toInt())
    }
    canvas.drawCircle(cx, cy, size * 0.48f, bgPaint)

    val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 10f
        color = parseHex(rimHex, 0xFFF6E27F.toInt())
    }
    canvas.drawCircle(cx, cy, size * 0.41f, ringPaint)

    fun drawEngravedLine(text: String, y: Float, textSizePx: Float, bold: Boolean) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            textSize = textSizePx
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
        // Pass 1: 底部受光亮边
        paint.color = parseHex(lightHex, 0xFFFFF4C2.toInt())
        canvas.drawText(text, cx + 1.5f, y + 1.8f, paint)
        // Pass 2: 上缘内壁暗影
        paint.color = parseHex(darkHex, 0xFF5C470D.toInt())
        canvas.drawText(text, cx - 1.5f, y - 1.5f, paint)
        // Pass 3: 凹雕主槽
        paint.alpha = 220
        canvas.drawText(text, cx, y, paint)
    }

    drawEngravedLine("MOVIEPILOT COMMUNITY", cy - 92f, 24f, true)
    drawEngravedLine(title.take(16), cy - 16f, 40f, true)
    drawEngravedLine(owner.ifBlank { "MoviePilot 成员" }, cy + 52f, 30f, false)
    drawEngravedLine(date.ifBlank { "2026" }, cy + 104f, 24f, false)
    return bmp
}

private fun parseHex(hex: String, fallback: Int): Int = runCatching {
    android.graphics.Color.parseColor(hex)
}.getOrDefault(fallback)
