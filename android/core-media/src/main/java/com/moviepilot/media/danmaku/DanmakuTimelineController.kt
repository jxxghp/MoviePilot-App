package com.moviepilot.media.danmaku

import com.moviepilot.rustbridge.DanmakuItemDto
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** 屏幕上活跃渲染的单条弹幕状态（零逐帧对象分配，原地更新 x / remainingSec）。 */
class ActiveDanmakuItem(
    val item: DanmakuItemDto,
    val displayText: String,
    val trackIndex: Int,
    var x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
    val speedPxPerSec: Float,
    var remainingSec: Float,
)

/**
 * Android 端统一轨道防碰撞弹幕时间线控制器（严格对齐 `danmaku-support-design.md` §5.1 数学模型）。
 */
class DanmakuTimelineController {
    var items: List<DanmakuItemDto> = emptyList()
        private set
    val activeItems: MutableList<ActiveDanmakuItem> = ArrayList(64)

    private var nextIndex: Int = 0
    private var clockMs: Double = 0.0
    private var isPlaying: Boolean = false
    private var playbackRate: Float = 1.0f

    private var viewportWidth: Float = 0f
    private var viewportHeight: Float = 0f
    private var density: Float = 2.5f
    private var topSafePaddingPx: Float = 24f

    var opacity: Float = 0.85f
    var fontScale: Float = 1.0f
        set(value) {
            field = value.coerceIn(0.75f, 1.5f)
            recalculateTracks()
        }
    var userSpeed: Float = 1.0f
    var areaRatio: Float = 0.5f
        set(value) {
            field = value.coerceIn(0.25f, 1.0f)
            recalculateTracks()
        }
    var maxOnScreen: Int = 40

    private var scrollTrackCount: Int = 6
    private var fixedTrackCount: Int = 4
    private var rowHeightPx: Float = 64f
    private var baseTextSizePx: Float = 44f

    val effectiveTextSizePx: Float
        get() = (baseTextSizePx * fontScale).coerceIn(12f * density, 38f * density)

    fun load(newItems: List<DanmakuItemDto>, currentPositionMs: Long) {
        items = newItems
        resetTo(currentPositionMs)
    }

    fun clearAll() {
        items = emptyList()
        activeItems.clear()
        nextIndex = 0
    }

    fun updateViewport(width: Int, height: Int, screenDensity: Float, topPaddingPx: Float) {
        if (width <= 0 || height <= 0) return
        val changed = abs(width - viewportWidth) > 1f || abs(height - viewportHeight) > 1f
        viewportWidth = width.toFloat()
        viewportHeight = height.toFloat()
        density = screenDensity.coerceAtLeast(1f)
        topSafePaddingPx = max(8f * density, topPaddingPx)
        if (changed) {
            recalculateTracks()
            activeItems.removeAll { slot ->
                slot.y + slot.height > viewportHeight || slot.trackIndex >= max(scrollTrackCount, fixedTrackCount)
            }
        }
    }

    /** 同步播放器时钟；偏差大于 350ms（Seek / 卡顿恢复 / 切核）时清空在屏并二分重置游标。 */
    fun syncPlayerClock(positionMs: Long, playing: Boolean, rate: Float) {
        val targetMs = max(0L, positionMs).toDouble()
        isPlaying = playing
        playbackRate = rate.coerceIn(0.25f, 4.0f)
        if (abs(targetMs - clockMs) > DRIFT_RESET_THRESHOLD_MS) {
            resetTo(positionMs)
        }
    }

    fun resetTo(positionMs: Long) {
        val target = max(0L, positionMs)
        clockMs = target.toDouble()
        activeItems.clear()
        nextIndex = lowerBoundIndex(target)
    }

    fun step(dtSec: Float, measureWidth: (String, Float) -> Float) {
        if (!isPlaying || viewportWidth <= 0f || viewportHeight <= 0f) return
        val clampedDt = dtSec.coerceIn(0f, 0.1f)
        val scaledDt = clampedDt * playbackRate
        clockMs += scaledDt * 1000.0

        // 1. 原地推进在屏位移并反向移除过期项（零列表分配）
        var i = activeItems.size - 1
        while (i >= 0) {
            val slot = activeItems[i]
            if (slot.item.mode == MODE_SCROLL) {
                slot.x -= slot.speedPxPerSec * scaledDt
                if (slot.x + slot.width <= -8f * density) {
                    activeItems.removeAt(i)
                }
            } else {
                slot.remainingSec -= scaledDt
                if (slot.remainingSec <= 0f) {
                    activeItems.removeAt(i)
                }
            }
            i--
        }

        // 2. 发射当前时间窗口内的新弹幕
        val currentMs = clockMs.toLong()
        var spawnedThisFrame = 0
        while (nextIndex < items.size) {
            val item = items[nextIndex]
            if (item.timeMs > currentMs) break
            nextIndex++
            if (currentMs - item.timeMs > 1500L) continue
            if (activeItems.size >= maxOnScreen || spawnedThisFrame >= 8) continue
            if (spawn(item, measureWidth)) {
                spawnedThisFrame++
            }
        }
    }

    private fun spawn(item: DanmakuItemDto, measureWidth: (String, Float) -> Float): Boolean {
        val displayText = if (item.repeatCount > 1) "${item.text} ×${item.repeatCount}" else item.text
        val textSize = effectiveTextSizePx
        val width = measureWidth(displayText, textSize) + 8f * density
        val height = max(textSize * 1.25f, rowHeightPx * 0.92f)
        val horizontalGap = 24f * density

        return when (item.mode) {
            MODE_TOP -> {
                val track = findAvailableFixedTrack(MODE_TOP) ?: return false
                val y = topSafePaddingPx + track * rowHeightPx
                activeItems.add(
                    ActiveDanmakuItem(
                        item = item,
                        displayText = displayText,
                        trackIndex = track,
                        x = max(8f * density, (viewportWidth - width) * 0.5f),
                        y = y,
                        width = width,
                        height = height,
                        speedPxPerSec = 0f,
                        remainingSec = FIXED_DURATION_SEC,
                    ),
                )
                true
            }

            MODE_BOTTOM -> {
                val track = findAvailableFixedTrack(MODE_BOTTOM) ?: return false
                val bottomSafeLimit = viewportHeight * 0.86f
                val y = bottomSafeLimit - (track + 1) * rowHeightPx
                if (y < topSafePaddingPx) return false
                activeItems.add(
                    ActiveDanmakuItem(
                        item = item,
                        displayText = displayText,
                        trackIndex = track,
                        x = max(8f * density, (viewportWidth - width) * 0.5f),
                        y = y,
                        width = width,
                        height = height,
                        speedPxPerSec = 0f,
                        remainingSec = FIXED_DURATION_SEC,
                    ),
                )
                true
            }

            else -> {
                val speed = ((viewportWidth + width) / BASE_SCROLL_DURATION_SEC) * userSpeed * playbackRate
                if (speed <= 1f) return false
                val track = findAvailableScrollTrack(speed, horizontalGap) ?: return false
                val y = topSafePaddingPx + track * rowHeightPx
                activeItems.add(
                    ActiveDanmakuItem(
                        item = item,
                        displayText = displayText,
                        trackIndex = track,
                        x = viewportWidth + 4f * density,
                        y = y,
                        width = width,
                        height = height,
                        speedPxPerSec = speed,
                        remainingSec = 0f,
                    ),
                )
                true
            }
        }
    }

    /** 滚动弹幕双条件防追尾碰撞判定（入口不重叠 + 中途不追尾）。 */
    private fun findAvailableScrollTrack(candSpeed: Float, horizontalGap: Float): Int? {
        for (track in 0 until scrollTrackCount) {
            var latest: ActiveDanmakuItem? = null
            for (j in 0 until activeItems.size) {
                val slot = activeItems[j]
                if (slot.item.mode == MODE_SCROLL && slot.trackIndex == track) {
                    if (latest == null || (slot.x + slot.width) > (latest.x + latest.width)) {
                        latest = slot
                    }
                }
            }
            if (latest == null) return track
            val prevRightX = latest.x + latest.width
            if (prevRightX + horizontalGap > viewportWidth) continue
            val prevRemainSec = max(0f, prevRightX) / max(1f, latest.speedPxPerSec)
            if (candSpeed * prevRemainSec > viewportWidth - horizontalGap) continue
            return track
        }
        return null
    }

    private fun findAvailableFixedTrack(mode: Int): Int? {
        val limit = max(1, min(fixedTrackCount, scrollTrackCount))
        for (track in 0 until limit) {
            var occupied = false
            for (j in 0 until activeItems.size) {
                val slot = activeItems[j]
                if (slot.item.mode == mode && slot.trackIndex == track) {
                    occupied = true
                    break
                }
            }
            if (!occupied) return track
        }
        return null
    }

    private fun recalculateTracks() {
        val minDp = min(viewportWidth, viewportHeight) / density
        val baseSp = when {
            minDp >= 600f -> 22f
            viewportWidth > viewportHeight -> 18f
            else -> 16f
        }
        baseTextSizePx = baseSp * density
        val fontPx = effectiveTextSizePx
        rowHeightPx = max(20f * density, fontPx * 1.35f)
        if (viewportHeight <= 0f) return
        val usable = max(rowHeightPx, viewportHeight * areaRatio - topSafePaddingPx)
        scrollTrackCount = max(1, floor((usable / rowHeightPx).toDouble()).toInt())
        fixedTrackCount = max(1, min(6, scrollTrackCount))
    }

    private fun lowerBoundIndex(targetMs: Long): Int {
        var low = 0
        var high = items.size
        while (low < high) {
            val mid = (low + high) ushr 1
            if (items[mid].timeMs < targetMs) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    companion object {
        const val MODE_SCROLL = 1
        const val MODE_BOTTOM = 4
        const val MODE_TOP = 5
        private const val BASE_SCROLL_DURATION_SEC = 7.5f
        private const val FIXED_DURATION_SEC = 4.2f
        private const val DRIFT_RESET_THRESHOLD_MS = 350.0
    }
}
