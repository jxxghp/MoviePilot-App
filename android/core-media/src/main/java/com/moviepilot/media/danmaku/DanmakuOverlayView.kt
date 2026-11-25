package com.moviepilot.media.danmaku

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.LruCache
import android.view.Choreographer
import android.view.View
import com.moviepilot.rustbridge.DanmakuItemDto

/**
 * 轻量原生透明弹幕叠加视图：
 * - 通过 `Choreographer` 帧回调与双通道 `Paint`（深色描边 + 填充）直接绘制，零逐帧对象分配；
 * - 使用 `LruCache<String, Float>` 缓存文字宽度，彻底避免高密度弹幕下 GC 抖动；
 * - `isClickable = false` 且不消费触摸事件，与 Media3 (`SurfaceView`/`TextureView`) 及 MPV 完全解耦。
 */
class DanmakuOverlayView(context: Context) : View(context) {
    val controller = DanmakuTimelineController()

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private val widthCache = LruCache<String, Float>(1024)
    private var choreographerRunning = false
    private var lastFrameNanos = 0L
    private var danmakuEnabled = true
    private var pipActive = false
    private var isPlayingNow = false

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!choreographerRunning) return
            val dtSec = if (lastFrameNanos == 0L) {
                1f / 60f
            } else {
                ((frameTimeNanos - lastFrameNanos) / 1_000_000_000.0).toFloat().coerceIn(0f, 0.1f)
            }
            lastFrameNanos = frameTimeNanos
            if (danmakuEnabled && !pipActive && isPlayingNow) {
                controller.step(dtSec) { text, sizePx -> measureCached(text, sizePx) }
                invalidate()
                Choreographer.getInstance().postFrameCallback(this)
            } else {
                choreographerRunning = false
                lastFrameNanos = 0L
            }
        }
    }

    init {
        isClickable = false
        isFocusable = false
        setWillNotDraw(false)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val d = resources.displayMetrics.density
        controller.updateViewport(w, h, d, maxOf(12f * d, paddingTop.toFloat()))
        widthCache.evictAll()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopLoop()
    }

    fun applyPreferences(prefs: DanmakuPreferencesStore) {
        danmakuEnabled = prefs.enabled
        controller.opacity = prefs.opacity
        if (kotlin.math.abs(controller.fontScale - prefs.fontScale) > 0.001f) {
            widthCache.evictAll()
        }
        controller.fontScale = prefs.fontScale
        controller.userSpeed = prefs.speed
        controller.areaRatio = prefs.areaRatio
        controller.maxOnScreen = prefs.maxOnScreen
        visibility = if (danmakuEnabled && !pipActive) VISIBLE else GONE
        if (!danmakuEnabled) {
            controller.activeItems.clear()
            stopLoop()
            invalidate()
        } else {
            refreshLoopState()
        }
    }

    fun loadTimeline(items: List<DanmakuItemDto>, currentPositionMs: Long) {
        controller.load(items, currentPositionMs)
        invalidate()
        refreshLoopState()
    }

    fun syncPlayback(positionMs: Long, playing: Boolean, rate: Float, inPip: Boolean) {
        isPlayingNow = playing
        if (pipActive != inPip) {
            pipActive = inPip
            visibility = if (danmakuEnabled && !pipActive) VISIBLE else GONE
            if (pipActive) {
                controller.activeItems.clear()
                stopLoop()
                invalidate()
                return
            }
        }
        controller.syncPlayerClock(positionMs, playing, rate)
        refreshLoopState()
    }

    fun stopAndClear() {
        stopLoop()
        controller.clearAll()
        invalidate()
    }

    private fun refreshLoopState() {
        val shouldRun = danmakuEnabled && !pipActive && isPlayingNow && controller.items.isNotEmpty() && isAttachedToWindow
        if (shouldRun && !choreographerRunning) {
            choreographerRunning = true
            lastFrameNanos = 0L
            Choreographer.getInstance().postFrameCallback(frameCallback)
        } else if (!shouldRun && choreographerRunning) {
            stopLoop()
        }
    }

    private fun stopLoop() {
        if (choreographerRunning) {
            choreographerRunning = false
            lastFrameNanos = 0L
            Choreographer.getInstance().removeFrameCallback(frameCallback)
        }
    }

    private fun measureCached(text: String, sizePx: Float): Float {
        val key = "${sizePx.toInt()}|$text"
        widthCache.get(key)?.let { return it }
        fillPaint.textSize = sizePx
        val w = fillPaint.measureText(text)
        widthCache.put(key, w)
        return w
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!danmakuEnabled || pipActive) return
        val active = controller.activeItems
        if (active.isEmpty()) return

        val textSize = controller.effectiveTextSizePx
        val density = resources.displayMetrics.density
        val alphaInt = (controller.opacity.coerceIn(0.2f, 1.0f) * 255f).toInt()
        strokePaint.textSize = textSize
        strokePaint.strokeWidth = (1.45f * density).coerceIn(2.2f, 5.2f)
        strokePaint.color = Color.argb((alphaInt * 0.82f).toInt(), 0, 0, 0)

        fillPaint.textSize = textSize
        val baselineOffset = -fillPaint.fontMetrics.ascent

        for (i in 0 until active.size) {
            val slot = active[i]
            val rgb = slot.item.colorRgb and 0xFFFFFF
            fillPaint.color = (alphaInt shl 24) or rgb
            val baselineY = slot.y + baselineOffset
            canvas.drawText(slot.displayText, slot.x, baselineY, strokePaint)
            canvas.drawText(slot.displayText, slot.x, baselineY, fillPaint)
        }
    }
}
