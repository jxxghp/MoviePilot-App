package com.moviepilot.media

import android.content.Context
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * 本地播放断点续播存储（`SharedPreferences("mp_local_playback_resume")`）：
 * - 统一为媒体服务器条目、远程存储缓存文件与本机文件提供毫秒级断点记忆；
 * - 键名采用 `SHA-256(instanceUrl|server|itemId_or_uri)` 隔离不同服务实例；
 * - 仅在 `positionMs > 30_000L` 且进度 `< 95%` 时持久化，播放达 `>= 95%` 自动清除断点。
 */
class LocalPlaybackHistoryStore(context: Context? = null) {
    private val prefs = context?.applicationContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val memoryFallback = ConcurrentHashMap<String, Long>()

    /** 读取本地已保存的续播毫秒位置（无记录返回 `0L`）。 */
    fun readResumePositionMs(
        instanceUrl: String,
        server: String,
        itemIdOrUri: String,
    ): Long {
        if (itemIdOrUri.isBlank()) return 0L
        val key = computeResumeKey(instanceUrl, server, itemIdOrUri)
        val raw = prefs?.getLong(key, 0L) ?: memoryFallback[key] ?: 0L
        return raw.coerceAtLeast(0L)
    }

    /** 按阈值规则更新或清除本地断点续播位置。 */
    fun recordPlaybackProgress(
        instanceUrl: String,
        server: String,
        itemIdOrUri: String,
        positionMs: Long,
        durationMs: Long,
    ) {
        if (itemIdOrUri.isBlank()) return
        val key = computeResumeKey(instanceUrl, server, itemIdOrUri)
        when {
            shouldClearProgress(positionMs, durationMs) -> removeByKey(key)
            shouldPersistProgress(positionMs, durationMs) -> putByKey(key, positionMs)
        }
    }

    /** 显式清除指定条目的本地续播断点（例如用户点击「从头开始」或单集自然播完）。 */
    fun clearResumePosition(
        instanceUrl: String,
        server: String,
        itemIdOrUri: String,
    ) {
        if (itemIdOrUri.isBlank()) return
        removeByKey(computeResumeKey(instanceUrl, server, itemIdOrUri))
    }

    private fun putByKey(key: String, positionMs: Long) {
        if (prefs != null) {
            prefs.edit().putLong(key, positionMs).apply()
        } else {
            memoryFallback[key] = positionMs
        }
    }

    private fun removeByKey(key: String) {
        if (prefs != null) {
            prefs.edit().remove(key).apply()
        } else {
            memoryFallback.remove(key)
        }
    }

    companion object {
        const val PREFS_NAME = "mp_local_playback_resume"
        const val MIN_RESUME_POSITION_MS = 30_000L
        const val COMPLETE_THRESHOLD = 0.95f

        /** 计算 `SHA-256(instanceUrl|server|itemId_or_uri)` 小写十六进制摘要键。 */
        fun computeResumeKey(
            instanceUrl: String,
            server: String,
            itemIdOrUri: String,
        ): String {
            val normalized = buildString {
                append(instanceUrl.trim().trimEnd('/').lowercase())
                append('|')
                append(server.trim().lowercase())
                append('|')
                append(itemIdOrUri.trim())
            }
            val digest = MessageDigest.getInstance("SHA-256").digest(normalized.toByteArray(Charsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }

        /** 判断当前播放位置是否满足写入本地断点的阈值条件（`> 30s` 且 `< 95%`）。 */
        fun shouldPersistProgress(positionMs: Long, durationMs: Long): Boolean {
            if (positionMs <= MIN_RESUME_POSITION_MS) return false
            if (durationMs > 1_000L) {
                val ratio = positionMs.toFloat() / durationMs.toFloat()
                if (ratio >= COMPLETE_THRESHOLD) return false
            }
            return true
        }

        /** 判断当前播放进度是否已接近片尾（`>= 95%`），应清除历史断点。 */
        fun shouldClearProgress(positionMs: Long, durationMs: Long): Boolean {
            if (durationMs <= 1_000L) return false
            val ratio = positionMs.toFloat() / durationMs.toFloat()
            return ratio >= COMPLETE_THRESHOLD
        }

        /** 综合本地断点与媒体服务器返回断点，取更靠后的有效续播点。 */
        fun resolveBestResumeMs(localSavedMs: Long, serverResumeMs: Long): Long =
            maxOf(localSavedMs.coerceAtLeast(0L), serverResumeMs.coerceAtLeast(0L))
    }
}
