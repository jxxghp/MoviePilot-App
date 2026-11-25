package com.moviepilot.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.Uri
import android.os.Build

/**
 * ADR-06 Android 推送通知提供者抽象：
 * 建立系统原生通知渠道，按统一多端注册契约（`platform = "android"`）向后端上报设备令牌，并校验同源通知跳转。
 */
object AndroidPushProvider {
    const val CHANNEL_ID_GENERAL = "moviepilot_general"
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
}
