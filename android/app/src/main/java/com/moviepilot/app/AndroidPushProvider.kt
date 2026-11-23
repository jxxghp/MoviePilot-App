package com.moviepilot.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * ADR-06 Android 推送通知提供者抽象：
 * 建立系统原生通知渠道，按统一多端注册契约（`platform = "android"`）向后端上报设备令牌。
 */
object AndroidPushProvider {
    const val CHANNEL_ID_GENERAL = "moviepilot_general"
    const val CHANNEL_ID_DOWNLOAD = "moviepilot_downloads"

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
}
