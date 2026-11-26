package com.moviepilot.rustbridge

import java.security.MessageDigest

/** 离线进度只属于一个规范化实例和账号，不持久化访问令牌。 */
object PlaybackQueueScope {
    /** 派生固定长度且不冲突的账号桶，保留部署子路径边界。 */
    fun storageKey(serverUrl: String, accountID: String): String {
        require(accountID.toLongOrNull()?.let { it > 0 } == true) { "播放队列缺少账号身份" }
        val normalized = RustCoreBridge.normalizeAddress(serverUrl).getOrThrow()
        val bytes = "$normalized\u0000$accountID".toByteArray(Charsets.UTF_8)
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        return "pending_stops_v2_$digest"
    }
}
