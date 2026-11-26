package com.moviepilot.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.Uri
import android.os.Build
import com.moviepilot.rustbridge.SentNotificationItemDto

/** 单实例单账号通知增量水位快照。 */
data class NotificationWatermark(
    val initialized: Boolean = false,
    val maxNumericId: Long = 0L,
    val seenKeys: Set<String> = emptySet(),
)

/** 通知增量比对输出（按时间升序排列的待投递列表 + 更新后水位）。 */
data class IncrementalNotificationBatch(
    val toDeliver: List<SentNotificationItemDto>,
    val nextWatermark: NotificationWatermark,
)

/**
 * ADR-06 Android 推送与系统通知栏投递契约：
 * 建立系统原生通知渠道（媒体订阅、插件与系统消息、下载进度），校验同源通知跳转，并计算无重复增量投递集合。
 */
object AndroidPushProvider {
    const val CHANNEL_ID_GENERAL = "moviepilot_general"
    const val CHANNEL_ID_PLUGIN = "moviepilot_plugins"
    const val CHANNEL_ID_DOWNLOAD = "moviepilot_downloads"
    const val EXTRA_NOTIFICATION_ROUTE = "moviepilot_route"
    const val EXTRA_NOTIFICATION_ORIGIN = "moviepilot_origin"

    /** 初始化 Android O+ 系统通知渠道。 */
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID_GENERAL, "媒体库与订阅通知", NotificationManager.IMPORTANCE_DEFAULT),
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID_PLUGIN, "插件与系统通知", NotificationManager.IMPORTANCE_DEFAULT),
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID_DOWNLOAD, "下载与整理进度", NotificationManager.IMPORTANCE_LOW),
        )
    }

    /** 构造对齐后端多端契约的设备注册请求 JSON。 */
    fun buildRegistrationPayload(deviceToken: String, appVersion: String): String =
        """{"platform":"android","token":"$deviceToken","app_version":"$appVersion"}"""

    /** 规范化实例入口（scheme + host + 显式非默认端口 + 子路径，去尾斜杠）用于通知同源比对。 */
    fun normalizeOrigin(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val uri = runCatching { java.net.URI(trimmed) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null
        val host = uri.host?.lowercase()?.takeIf { it.isNotBlank() } ?: return null
        val defaultPort = if (scheme == "https") 443 else 80
        val portPart = if (uri.port > 0 && uri.port != defaultPort) ":${uri.port}" else ""
        val cleanPath = (uri.path ?: "").trimEnd('/')
        return "$scheme://$host$portPart$cleanPath"
    }

    /** 判断通知声明的实例入口是否与当前已认证会话一致。 */
    fun matchesServerOrigin(notificationOrigin: String?, activeServerUrl: String): Boolean {
        if (notificationOrigin.isNullOrBlank()) return true
        val expected = normalizeOrigin(notificationOrigin) ?: return false
        val current = normalizeOrigin(activeServerUrl) ?: return false
        return expected == current
    }

    /** 提取 `moviepilot-app://notification` 链接中的 `origin` 参数。 */
    fun extractNotificationOrigin(deepLink: String): String? {
        if (!deepLink.startsWith("moviepilot-app://", ignoreCase = true)) return null
        return runCatching { Uri.parse(deepLink).getQueryParameter("origin") }.getOrNull()
    }

    /** 判断一条服务端通知是否归属插件消息（`mtype` 含「插件」或 `plugin`）。 */
    fun isPluginNotification(item: SentNotificationItemDto): Boolean {
        val cat = item.category.lowercase()
        val src = item.source.lowercase()
        return cat.contains("插件") || cat.contains("plugin") || src.startsWith("plugin:")
    }

    /** 根据通知分类选择对应的 Android 系统通知渠道。 */
    fun selectChannelForNotification(item: SentNotificationItemDto): String {
        val cat = item.category.lowercase()
        return when {
            cat.contains("下载") || cat.contains("download") -> CHANNEL_ID_DOWNLOAD
            isPluginNotification(item) || cat.contains("系统") || cat.contains("站点") || cat.contains("手动") -> CHANNEL_ID_PLUGIN
            else -> CHANNEL_ID_GENERAL
        }
    }

    /**
     * 计算增量待投递通知：
     * - 首次同步仅建立水位基线，绝不把历史旧消息刷屏推送到手机通知栏；
     * - 后续仅投递严格晚于水位的插件与 MP 系统通知，并按时间从旧到新排列（单批最多 `maxDeliverCount` 条）。
     */
    fun computeIncrementalNotifications(
        fetchedNewestFirst: List<SentNotificationItemDto>,
        current: NotificationWatermark,
        activeUserName: String,
        includePlugin: Boolean = true,
        includeSystem: Boolean = true,
        maxDeliverCount: Int = 5,
    ): IncrementalNotificationBatch {
        val maxIdInBatch = fetchedNewestFirst.mapNotNull { it.numericId }.maxOrNull() ?: 0L
        val mergedMaxId = maxOf(current.maxNumericId, maxIdInBatch)
        val mergedKeys = (fetchedNewestFirst.map { it.stableKey } + current.seenKeys)
            .filter { it.isNotBlank() }
            .distinct()
            .take(80)
            .toSet()
        val nextWatermark = NotificationWatermark(
            initialized = true,
            maxNumericId = mergedMaxId,
            seenKeys = mergedKeys,
        )
        if (!current.initialized) {
            return IncrementalNotificationBatch(toDeliver = emptyList(), nextWatermark = nextWatermark)
        }

        val unseenNewestFirst = fetchedNewestFirst.filter { item ->
            val numId = item.numericId
            val isNew = if (numId != null && current.maxNumericId > 0L) {
                numId > current.maxNumericId
            } else {
                item.stableKey !in current.seenKeys
            }
            if (!isNew) return@filter false
            val targetUser = item.userid.trim()
            if (targetUser.isNotEmpty() &&
                !targetUser.equals("all", ignoreCase = true) &&
                activeUserName.isNotBlank() &&
                !targetUser.equals(activeUserName, ignoreCase = true)
            ) {
                return@filter false
            }
            val isPlugin = isPluginNotification(item)
            if (isPlugin) includePlugin else includeSystem
        }

        val chronological = unseenNewestFirst.asReversed().takeLast(maxDeliverCount.coerceAtLeast(1))
        return IncrementalNotificationBatch(
            toDeliver = chronological,
            nextWatermark = nextWatermark,
        )
    }
}
