package com.moviepilot.media.danmaku

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.moviepilot.rustbridge.DanmakuFilterOptionsDto
import org.json.JSONArray

/** Android 端弹幕本地渲染偏好存储（键义与默认值严格对齐 `danmaku-support-design.md` §4.1）。 */
class DanmakuPreferencesStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        "moviepilot_danmaku_prefs",
        Context.MODE_PRIVATE,
    )

    var enabled by mutableStateOf(prefs.getBoolean(KEY_ENABLED, true))
        private set
    var opacity by mutableFloatStateOf(prefs.getFloat(KEY_OPACITY, 0.85f).coerceIn(0.2f, 1.0f))
        private set
    var fontScale by mutableFloatStateOf(prefs.getFloat(KEY_FONT_SCALE, 1.0f).coerceIn(0.75f, 1.5f))
        private set
    var speed by mutableFloatStateOf(prefs.getFloat(KEY_SPEED, 1.0f).coerceIn(0.6f, 1.6f))
        private set
    var areaRatio by mutableFloatStateOf(prefs.getFloat(KEY_AREA_RATIO, 0.5f).coerceIn(0.25f, 1.0f))
        private set
    var maxOnScreen by mutableIntStateOf(prefs.getInt(KEY_MAX_ON_SCREEN, 40).coerceIn(20, 100))
        private set
    var allowScroll by mutableStateOf(prefs.getBoolean(KEY_ALLOW_SCROLL, true))
        private set
    var allowTop by mutableStateOf(prefs.getBoolean(KEY_ALLOW_TOP, true))
        private set
    var allowBottom by mutableStateOf(prefs.getBoolean(KEY_ALLOW_BOTTOM, true))
        private set
    var allowColor by mutableStateOf(prefs.getBoolean(KEY_ALLOW_COLOR, true))
        private set
    var mergeDuplicates by mutableStateOf(prefs.getBoolean(KEY_MERGE_DUPLICATES, true))
        private set
    var blockKeywords by mutableStateOf(readKeywords())
        private set

    fun updateEnabled(v: Boolean) {
        enabled = v
        prefs.edit().putBoolean(KEY_ENABLED, v).apply()
    }

    fun updateOpacity(v: Float) {
        val clamped = v.coerceIn(0.2f, 1.0f)
        opacity = clamped
        prefs.edit().putFloat(KEY_OPACITY, clamped).apply()
    }

    fun updateFontScale(v: Float) {
        val clamped = v.coerceIn(0.75f, 1.5f)
        fontScale = clamped
        prefs.edit().putFloat(KEY_FONT_SCALE, clamped).apply()
    }

    fun updateSpeed(v: Float) {
        val clamped = v.coerceIn(0.6f, 1.6f)
        speed = clamped
        prefs.edit().putFloat(KEY_SPEED, clamped).apply()
    }

    fun updateAreaRatio(v: Float) {
        val clamped = v.coerceIn(0.25f, 1.0f)
        areaRatio = clamped
        prefs.edit().putFloat(KEY_AREA_RATIO, clamped).apply()
    }

    fun updateMaxOnScreen(v: Int) {
        val clamped = v.coerceIn(20, 100)
        maxOnScreen = clamped
        prefs.edit().putInt(KEY_MAX_ON_SCREEN, clamped).apply()
    }

    fun updateAllowScroll(v: Boolean) {
        allowScroll = v
        prefs.edit().putBoolean(KEY_ALLOW_SCROLL, v).apply()
    }

    fun updateAllowTop(v: Boolean) {
        allowTop = v
        prefs.edit().putBoolean(KEY_ALLOW_TOP, v).apply()
    }

    fun updateAllowBottom(v: Boolean) {
        allowBottom = v
        prefs.edit().putBoolean(KEY_ALLOW_BOTTOM, v).apply()
    }

    fun updateAllowColor(v: Boolean) {
        allowColor = v
        prefs.edit().putBoolean(KEY_ALLOW_COLOR, v).apply()
    }

    fun updateMergeDuplicates(v: Boolean) {
        mergeDuplicates = v
        prefs.edit().putBoolean(KEY_MERGE_DUPLICATES, v).apply()
    }

    fun addBlockKeyword(raw: String) {
        val cleaned = raw.trim()
        if (cleaned.isEmpty() || cleaned in blockKeywords) return
        val next = blockKeywords + cleaned
        blockKeywords = next
        saveKeywords(next)
    }

    fun removeBlockKeyword(keyword: String) {
        val next = blockKeywords.filterNot { it == keyword }
        blockKeywords = next
        saveKeywords(next)
    }

    fun toFilterOptions(offsetMs: Long): DanmakuFilterOptionsDto = DanmakuFilterOptionsDto(
        allowScroll = allowScroll,
        allowTop = allowTop,
        allowBottom = allowBottom,
        allowColor = allowColor,
        mergeDuplicates = mergeDuplicates,
        mergeWindowMs = 3000L,
        maxPerSecond = 12,
        blockKeywords = blockKeywords,
        offsetMs = offsetMs,
    )

    private fun readKeywords(): List<String> {
        val raw = prefs.getString(KEY_BLOCK_KEYWORDS, null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val s = arr.optString(i).trim()
                    if (s.isNotEmpty()) add(s)
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun saveKeywords(list: List<String>) {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        prefs.edit().putString(KEY_BLOCK_KEYWORDS, arr.toString()).apply()
    }

    companion object {
        private const val KEY_ENABLED = "danmaku_enabled"
        private const val KEY_OPACITY = "danmaku_opacity"
        private const val KEY_FONT_SCALE = "danmaku_font_scale"
        private const val KEY_SPEED = "danmaku_speed"
        private const val KEY_AREA_RATIO = "danmaku_area_ratio"
        private const val KEY_MAX_ON_SCREEN = "danmaku_max_on_screen"
        private const val KEY_ALLOW_SCROLL = "danmaku_allow_scroll"
        private const val KEY_ALLOW_TOP = "danmaku_allow_top"
        private const val KEY_ALLOW_BOTTOM = "danmaku_allow_bottom"
        private const val KEY_ALLOW_COLOR = "danmaku_allow_color"
        private const val KEY_MERGE_DUPLICATES = "danmaku_merge_duplicates"
        private const val KEY_BLOCK_KEYWORDS = "danmaku_block_keywords"
    }
}
