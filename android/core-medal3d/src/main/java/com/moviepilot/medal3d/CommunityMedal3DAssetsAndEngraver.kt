package com.moviepilot.medal3d

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.util.LruCache
import kotlinx.serialization.json.Json
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/** 单枚勋章 3D 渲染所需的全部预处理贴图、轮廓与机械外圈拆分数据包（1:1 对齐 iOS `CommunityMedalRenderBundle`）。 */
class CommunityMedalRenderBundle(
    val frontDiffuse: Bitmap,
    val frontNormal: Bitmap?,
    val frontMetalness: Bitmap?,
    val frontOuterDiffuse: Bitmap?,
    val frontOuterNormal: Bitmap?,
    val frontOuterMetalness: Bitmap?,
    val backDiffuse: Bitmap,
    val backNormal: Bitmap?,
    val backMetalness: Bitmap?,
    val frontOutline: CommunityMedalOutline?,
    val edgeMetalRgb: FloatArray, // r, g, b in 0..1
    val toneRgb: FloatArray,
    val spinConfig: CommunityMedalOutline.SpinConfig?,
)

/** 内置 `assets/community_medals/` 贴图与轮廓加载器 + PBR 法线/金属度/背面三遍凹雕生成器。 */
object CommunityMedalAssetEngine {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val bitmapCache = object : LruCache<String, Bitmap>(32) {}
    private val outlineCache = mutableMapOf<String, CommunityMedalOutline>()
    private val bundleCache = LinkedHashMap<String, CommunityMedalRenderBundle>(8, 0.75f, true)

    fun loadWebp(context: Context, stem: String): Bitmap? {
        synchronized(bitmapCache) {
            bitmapCache.get(stem)?.let { return it }
        }
        val bmp = runCatching {
            context.assets.open("community_medals/$stem.webp").use {
                BitmapFactory.decodeStream(it)
            }
        }.getOrNull() ?: return null
        synchronized(bitmapCache) {
            bitmapCache.put(stem, bmp)
        }
        return bmp
    }

    fun loadOutline(context: Context, stem: String): CommunityMedalOutline? {
        synchronized(outlineCache) {
            outlineCache[stem]?.let { return it }
        }
        val parsed = runCatching {
            context.assets.open("community_medals/$stem.outline.json").bufferedReader().use {
                json.decodeFromString<CommunityMedalOutline>(it.readText())
            }
        }.getOrNull() ?: return null
        synchronized(outlineCache) {
            outlineCache[stem] = parsed
        }
        return parsed
    }

    fun loadFrontBitmap(context: Context, record: CommunityMedalRecord): Bitmap? =
        loadWebp(context, CommunityMedalCatalog.frontAssetStem(record))
            ?: loadWebp(context, "${record.key}-front")

    fun loadBadgeBitmap(context: Context, record: CommunityMedalRecord): Bitmap? =
        loadWebp(context, CommunityMedalCatalog.badgeAssetStem(record))
            ?: loadWebp(context, "${record.key}-badge")

    fun buildRenderBundle(
        context: Context,
        record: CommunityMedalRecord,
        login: String?,
    ): CommunityMedalRenderBundle? {
        val cacheKey = "${record.key}|${record.normalizedTier ?: 0}|${login.orEmpty()}|${record.at.orEmpty()}|${record.specialty.orEmpty()}"
        synchronized(bundleCache) {
            bundleCache[cacheKey]?.let { return it }
        }

        val frontStem = CommunityMedalCatalog.frontAssetStem(record)
        val backStem = CommunityMedalCatalog.backAssetStem(record)
        val rawFront = loadFrontBitmap(context, record) ?: return null
        val rawBack = loadWebp(context, backStem) ?: rawFront

        val frontOutline = loadOutline(context, frontStem) ?: loadOutline(context, "${record.key}-front")
        val backOutline = loadOutline(context, backStem)

        val engraving = CommunityMedalCatalog.engraving(record, login)
        val engravedBack = engraveBackPlate(rawBack, backOutline?.dial, engraving)

        val frontHeight = loadWebp(context, "$frontStem-height") ?: loadWebp(context, "${record.key}-front-height")
        val backHeight = loadWebp(context, "$backStem-height")

        val (frontNormal, frontMetal) = buildPBRMaps(frontHeight, strength = 2.5f)
        val (backNormal, backMetal) = buildPBRMaps(backHeight, strength = 2.2f)

        val toneInt = CommunityMedalCatalog.parseColorInt(record.spec?.toneHex ?: "#9b7bff")
        val toneRgb = floatArrayOf(Color.red(toneInt) / 255f, Color.green(toneInt) / 255f, Color.blue(toneInt) / 255f)
        val edgeRgb = sampleEdgeMetalColor(rawFront, frontOutline, toneRgb)

        var finalFrontDiffuse = rawFront
        var finalFrontNormal = frontNormal
        var finalFrontMetal = frontMetal
        var outerDiffuse: Bitmap? = null
        var outerNormal: Bitmap? = null
        var outerMetal: Bitmap? = null

        val spin = frontOutline?.spin
        if (spin != null) {
            val (innerD, outerD) = splitRingBitmaps(rawFront, spin)
            finalFrontDiffuse = innerD
            outerDiffuse = outerD
            if (frontNormal != null) {
                val (innerN, outerN) = splitRingBitmaps(frontNormal, spin)
                finalFrontNormal = innerN
                outerNormal = outerN
            }
            if (frontMetal != null) {
                val (innerM, outerM) = splitRingBitmaps(frontMetal, spin)
                finalFrontMetal = innerM
                outerMetal = outerM
            }
        }

        val bundle = CommunityMedalRenderBundle(
            frontDiffuse = finalFrontDiffuse,
            frontNormal = finalFrontNormal,
            frontMetalness = finalFrontMetal,
            frontOuterDiffuse = outerDiffuse,
            frontOuterNormal = outerNormal,
            frontOuterMetalness = outerMetal,
            backDiffuse = engravedBack,
            backNormal = backNormal,
            backMetalness = backMetal,
            frontOutline = frontOutline,
            edgeMetalRgb = edgeRgb,
            toneRgb = toneRgb,
            spinConfig = spin,
        )
        synchronized(bundleCache) {
            if (bundleCache.size >= 8) {
                bundleCache.remove(bundleCache.keys.first())
            }
            bundleCache[cacheKey] = bundle
        }
        return bundle
    }

    /**
     * 背面铭牌三遍凹雕（1:1 复刻 `NativeCommunityMedal3D.swift` / `communityMedalEngrave.ts`）：
     * 在实际 `-back.webp` 的 `dial` 矩形内采样金属平均 RGB，计算暗槽/阴影/受光边色板，
     * 自适应字号排布标题、档位、授予对象、日期与开放六边形 MoviePilot 品牌标记。
     */
    private fun engraveBackPlate(
        backImage: Bitmap,
        dial: CommunityMedalOutline.DialRect?,
        engraving: CommunityMedalEngraving,
    ): Bitmap {
        val w = backImage.width
        val h = backImage.height
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawBitmap(backImage, 0f, 0f, null)

        val dialRect = if (dial != null) {
            val dw = (dial.width * w).toFloat()
            val dh = (dial.height * h).toFloat()
            val dx = (dial.x * w).toFloat() - dw * 0.5f
            val dy = (dial.y * h).toFloat() - dh * 0.5f
            RectF(dx, dy, dx + dw, dy + dh)
        } else {
            RectF(w * 0.25f, h * 0.38f, w * 0.75f, h * 0.62f)
        }

        val metal = sampleAverageMetalRgb(backImage, dialRect)
        // groove = mix(metal, black, 0.58)
        val gr = metal[0] * 0.42f
        val gg = metal[1] * 0.42f
        val gb = metal[2] * 0.42f
        // shadow = mix(groove, black, 0.45)
        val sr = gr * 0.55f
        val sg = gg * 0.55f
        val sb = gb * 0.55f
        // edge = mix(metal, white, 0.38) @ 0.75
        val er = metal[0] * 0.62f + 0.38f
        val eg = metal[1] * 0.62f + 0.38f
        val eb = metal[2] * 0.62f + 0.38f

        val grooveColor = Color.argb(240, (gr * 255).toInt(), (gg * 255).toInt(), (gb * 255).toInt())
        val shadowColor = Color.argb(242, (sr * 255).toInt(), (sg * 255).toInt(), (sb * 255).toInt())
        val edgeColor = Color.argb(191, (er * 255).toInt(), (eg * 255).toInt(), (eb * 255).toInt())

        data class RowSpec(
            val kind: Int, // 0=title, 1=body, 2=mark
            val text: String,
            var fontSize: Float,
            val bold: Boolean,
            val letterSpacing: Float,
        )

        val rows = mutableListOf<RowSpec>()
        rows += RowSpec(0, engraving.title, dialRect.width() * 0.125f, true, 0.08f)
        engraving.tierLine?.takeIf { it.isNotBlank() }?.let {
            rows += RowSpec(1, it, dialRect.width() * 0.062f, false, 0.02f)
        }
        engraving.recipientLine?.takeIf { it.isNotBlank() }?.let {
            rows += RowSpec(1, it, dialRect.width() * 0.060f, false, 0.02f)
        }
        engraving.timeLine?.takeIf { it.isNotBlank() }?.let {
            rows += RowSpec(1, it, dialRect.width() * 0.058f, false, 0.02f)
        }
        rows += RowSpec(2, engraving.makerMark, dialRect.width() * 0.056f, true, 0.12f)

        val innerW = dialRect.width() * 0.90f
        val innerH = dialRect.height() * 0.90f
        val minFont = max(14f, w / 380f * 9f)
        var gapRatio = 1.24f

        val measurePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        fun rowWidth(r: RowSpec): Float {
            measurePaint.textSize = r.fontSize
            measurePaint.typeface = if (r.bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            measurePaint.letterSpacing = r.letterSpacing
            val tw = measurePaint.measureText(r.text)
            return if (r.kind == 2) tw + r.fontSize * 1.55f else tw
        }
        fun totalHeight(): Float {
            var total = 0f
            rows.forEachIndexed { idx, r ->
                total += r.fontSize * 1.18f
                if (idx < rows.size - 1) total += r.fontSize * (gapRatio - 1f)
            }
            return total
        }
        fun fits() = totalHeight() <= innerH && rows.all { rowWidth(it) <= innerW }

        if (!fits()) gapRatio = 1.14f
        var steps = 0
        while (!fits() && steps < 24) {
            steps++
            if (rows.first().fontSize > minFont * 1.7f) {
                rows.first().fontSize *= 0.94f
                continue
            }
            var shrunk = false
            rows.forEach { if (it.kind == 1 && it.fontSize > minFont) { it.fontSize *= 0.94f; shrunk = true } }
            if (shrunk) continue
            val timeIdx = rows.indexOfFirst { it.kind == 1 && it.text == engraving.timeLine }
            if (timeIdx >= 0) { rows.removeAt(timeIdx); continue }
            val recIdx = rows.indexOfFirst { it.kind == 1 && it.text == engraving.recipientLine }
            if (recIdx >= 0) { rows.removeAt(recIdx); continue }
            rows.forEach { it.fontSize *= 0.92f }
        }

        val bevel = max(1f, (w / 300f).roundToInt().toFloat())
        val totalH = totalHeight()
        var currentY = dialRect.centerY() - totalH * 0.5f
        val passes = listOf(edgeColor to bevel, shadowColor to 0f, grooveColor to bevel * 0.5f)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        rows.forEachIndexed { idx, row ->
            val rowH = row.fontSize * 1.18f
            val centerY = currentY + rowH * 0.5f
            paint.textSize = row.fontSize
            paint.typeface = if (row.bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            paint.letterSpacing = row.letterSpacing
            val fm = paint.fontMetrics
            val baselineOffset = -(fm.ascent + fm.descent) * 0.5f

            if (row.kind == 2) {
                val tw = paint.measureText(row.text)
                val iconSize = row.fontSize * 1.15f
                val gap = row.fontSize * 0.40f
                val startX = dialRect.centerX() - (iconSize + gap + tw) * 0.5f
                paint.textAlign = Paint.Align.LEFT
                for ((col, dy) in passes) {
                    drawOpenHexagonLogo(
                        canvas,
                        RectF(startX, centerY - iconSize * 0.5f + dy, startX + iconSize, centerY + iconSize * 0.5f + dy),
                        col,
                    )
                    paint.color = col
                    canvas.drawText(row.text, startX + iconSize + gap, centerY + baselineOffset + dy, paint)
                }
            } else {
                paint.textAlign = Paint.Align.CENTER
                for ((col, dy) in passes) {
                    paint.color = col
                    canvas.drawText(row.text, dialRect.centerX(), centerY + baselineOffset + dy, paint)
                }
            }

            currentY += rowH
            if (idx < rows.size - 1) currentY += row.fontSize * (gapRatio - 1f)
        }

        return out
    }

    private fun drawOpenHexagonLogo(canvas: Canvas, rect: RectF, color: Int) {
        val cx = rect.centerX()
        val cy = rect.centerY()
        val r = min(rect.width(), rect.height()) * 0.44f
        val angles = doubleArrayOf(30.0, 90.0, 150.0, 210.0, 270.0, 330.0).map { it * PI / 180.0 }
        val hexPath = Path()
        for (i in 0 until 5) {
            val px = cx + (r * cos(angles[i])).toFloat()
            val py = cy + (r * sin(angles[i])).toFloat()
            if (i == 0) hexPath.moveTo(px, py) else hexPath.lineTo(px, py)
        }
        val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = max(1.2f, rect.width() * 0.11f)
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            this.color = color
        }
        canvas.drawPath(hexPath, strokePaint)

        val triR = r * 0.44f
        val triPath = Path().apply {
            moveTo(cx - triR * 0.55f, cy - triR * 0.72f)
            lineTo(cx + triR * 0.85f, cy)
            lineTo(cx - triR * 0.55f, cy + triR * 0.72f)
            close()
        }
        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            this.color = color
        }
        canvas.drawPath(triPath, fillPaint)
    }

    private fun sampleAverageMetalRgb(bmp: Bitmap, rect: RectF): FloatArray {
        val minX = rect.left.roundToInt().coerceIn(0, bmp.width - 1)
        val maxX = rect.right.roundToInt().coerceIn(0, bmp.width - 1)
        val minY = rect.top.roundToInt().coerceIn(0, bmp.height - 1)
        val maxY = rect.bottom.roundToInt().coerceIn(0, bmp.height - 1)
        var rSum = 0.0
        var gSum = 0.0
        var bSum = 0.0
        var count = 0.0
        var y = minY
        while (y <= maxY) {
            var x = minX
            while (x <= maxX) {
                val px = bmp.getPixel(x, y)
                if (Color.alpha(px) >= 200) {
                    rSum += Color.red(px)
                    gSum += Color.green(px)
                    bSum += Color.blue(px)
                    count += 1.0
                }
                x += 4
            }
            y += 4
        }
        if (count <= 0.0) return floatArrayOf(168f / 255f, 164f / 255f, 156f / 255f)
        return floatArrayOf(
            (rSum / count / 255.0).toFloat(),
            (gSum / count / 255.0).toFloat(),
            (bSum / count / 255.0).toFloat(),
        )
    }

    /** 从灰度高度图计算 256×256 切线空间法线贴图与金属度贴图（区分金属棱线与珐琅内盘）。 */
    private fun buildPBRMaps(heightImage: Bitmap?, strength: Float): Pair<Bitmap?, Bitmap?> {
        if (heightImage == null) return null to null
        val dim = 256
        val scaled = Bitmap.createScaledBitmap(heightImage, dim, dim, true)
        val src = IntArray(dim * dim)
        scaled.getPixels(src, 0, dim, 0, 0, dim, dim)
        val gray = FloatArray(dim * dim) { i ->
            val p = src[i]
            (Color.red(p) * 0.299f + Color.green(p) * 0.587f + Color.blue(p) * 0.114f) / 255f
        }
        val normalPixels = IntArray(dim * dim)
        val metalPixels = IntArray(dim * dim)

        for (y in 0 until dim) {
            val y0 = max(0, y - 1)
            val y1 = min(dim - 1, y + 1)
            for (x in 0 until dim) {
                val x0 = max(0, x - 1)
                val x1 = min(dim - 1, x + 1)
                val hL = gray[y * dim + x0]
                val hR = gray[y * dim + x1]
                val hU = gray[y0 * dim + x]
                val hD = gray[y1 * dim + x]
                val hC = gray[y * dim + x]

                val nx = -(hR - hL) * strength
                val ny = (hD - hU) * strength
                val nz = 1.0f
                val invLen = 1.0f / sqrt(nx * nx + ny * ny + nz * nz)

                val nr = ((nx * invLen * 0.5f + 0.5f) * 255f).toInt().coerceIn(0, 255)
                val ng = ((ny * invLen * 0.5f + 0.5f) * 255f).toInt().coerceIn(0, 255)
                val nb = ((nz * invLen * 0.5f + 0.5f) * 255f).toInt().coerceIn(0, 255)
                normalPixels[y * dim + x] = Color.argb(255, nr, ng, nb)

                // 1:1 对齐 Web communityMedalRelief.ts：smoothstep(0.26, 0.45, h)，珐琅与铭牌严格为 0
                val t = ((hC - 0.26f) / (0.45f - 0.26f)).coerceIn(0f, 1f)
                val smooth = t * t * (3f - 2f * t)
                val metal = (smooth * 255f).toInt().coerceIn(0, 255)
                metalPixels[y * dim + x] = Color.argb(255, metal, metal, metal)
            }
        }
        val normalBmp = Bitmap.createBitmap(normalPixels, dim, dim, Bitmap.Config.ARGB_8888)
        val metalBmp = Bitmap.createBitmap(metalPixels, dim, dim, Bitmap.Config.ARGB_8888)
        return normalBmp to metalBmp
    }

    /** 采样正面向内 3%~5% 真实金属唇缘颜色作为 3D 挤出侧边厚度材质色。 */
    private fun sampleEdgeMetalColor(
        frontImage: Bitmap,
        outline: CommunityMedalOutline?,
        fallbackRgb: FloatArray,
    ): FloatArray {
        val pts = outline?.outline?.filter { it.size >= 2 } ?: return fallbackRgb
        if (pts.size < 8) return fallbackRgb
        var cx = 0.0
        var cy = 0.0
        pts.forEach { cx += it[0]; cy += it[1] }
        cx /= pts.size
        cy /= pts.size

        val w = frontImage.width
        val h = frontImage.height
        var rSum = 0.0
        var gSum = 0.0
        var bSum = 0.0
        var count = 0.0
        for (p in pts) {
            for (inset in doubleArrayOf(0.03, 0.05)) {
                val u = p[0] + (cx - p[0]) * inset
                val v = p[1] + (cy - p[1]) * inset
                val x = (u * w).toInt().coerceIn(0, w - 1)
                val y = (v * h).toInt().coerceIn(0, h - 1)
                val px = frontImage.getPixel(x, y)
                if (Color.alpha(px) >= 220) {
                    rSum += Color.red(px)
                    gSum += Color.green(px)
                    bSum += Color.blue(px)
                    count += 1.0
                }
            }
        }
        if (count <= 0.0) return fallbackRgb
        return floatArrayOf(
            (rSum / count / 255.0 * 0.90).toFloat(),
            (gSum / count / 255.0 * 0.90).toFloat(),
            (bSum / count / 255.0 * 0.90).toFloat(),
        )
    }

    /** 按 `spin` 圆环半径将主创勋章正面拆分为静止内盘与机械步进旋转外圈。 */
    private fun splitRingBitmaps(
        image: Bitmap,
        spin: CommunityMedalOutline.SpinConfig,
    ): Pair<Bitmap, Bitmap> {
        val w = image.width
        val h = image.height
        val cx = (spin.x * w).toFloat()
        val cy = (spin.y * h).toFloat()
        val radius = (spin.r * w).toFloat()

        val inner = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(inner).apply {
            val clipPath = Path().apply { addCircle(cx, cy, radius + 1.5f, Path.Direction.CW) }
            clipPath(clipPath)
            drawBitmap(image, 0f, 0f, null)
        }

        val outer = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(outer).apply {
            drawBitmap(image, 0f, 0f, null)
            val clearPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
            }
            drawCircle(cx, cy, max(1f, radius - 1.5f), clearPaint)
        }
        return inner to outer
    }

    /** 生成 1080×1350 社区勋章荣誉纪念分享海报（1:1 复刻 `CommunityMedalShareRenderer`）。 */
    fun renderSharePoster(
        context: Context,
        record: CommunityMedalRecord,
        login: String?,
    ): Bitmap? {
        val front = loadFrontBitmap(context, record) ?: return null
        val w = 1080
        val h = 1350
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.drawColor(Color.rgb(11, 12, 14))

        val toneInt = CommunityMedalCatalog.parseColorInt(record.spec?.toneHex ?: "#9b7bff")
        val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(
                540f, 560f, 620f,
                intArrayOf(
                    Color.argb(56, Color.red(toneInt), Color.green(toneInt), Color.blue(toneInt)),
                    Color.TRANSPARENT,
                ),
                floatArrayOf(0f, 1f),
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), glowPaint)
        canvas.drawBitmap(front, null, RectF(90f, 110f, 990f, 1010f), Paint(Paint.FILTER_BITMAP_FLAG))

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(242, 243, 245)
            textSize = 60f
            typeface = Typeface.DEFAULT_BOLD
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText(record.spec?.name ?: record.key, w * 0.5f, 1110f, titlePaint)

        val metaParts = buildList {
            CommunityMedalCatalog.tierLine(record)?.let { add(it) }
            if (!login.isNullOrBlank()) add("授予 @$login")
            CommunityMedalCatalog.timeLine(record)?.let { add(it) }
        }
        if (metaParts.isNotEmpty()) {
            val metaPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(154, 159, 166)
                textSize = 30f
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText(metaParts.joinToString(" · "), w * 0.5f, 1180f, metaPaint)
        }

        val footerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(95, 100, 107)
            textSize = 26f
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.12f
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText("MoviePilot", w * 0.5f, 1272f, footerPaint)
        return bmp
    }
}
