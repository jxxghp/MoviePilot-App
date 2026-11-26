package com.moviepilot.app

import com.moviepilot.rustbridge.SentNotificationItemDto
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 验证 Android 多端推送契约、通知同源边界以及插件/系统消息状态栏增量投递逻辑。 */
class AndroidPushProviderTest {
    @Test
    fun registrationPayloadContainsAndroidPlatformAndToken() {
        val payload = AndroidPushProvider.buildRegistrationPayload("synthetic-fcm-token", "2.0.2")
        assertTrue(payload.contains("\"platform\":\"android\""))
        assertTrue(payload.contains("synthetic-fcm-token"))
        assertTrue(payload.contains("2.0.2"))
    }

    @Test
    fun matchesServerOriginHonorsDefaultPortsAndSubpaths() {
        assertTrue(AndroidPushProvider.matchesServerOrigin("https://mp.test:443/base", "https://MP.test/base/"))
        assertFalse(AndroidPushProvider.matchesServerOrigin("https://mp.test/base", "https://mp.test/"))
        assertFalse(AndroidPushProvider.matchesServerOrigin("https://mp.test:8443", "https://mp.test"))
    }

    @Test
    fun firstSyncInitializesBaselineWithoutFloodingAndSubsequentSyncDeliversPluginAndSystemMessages() {
        val historical = listOf(
            SentNotificationItemDto(numericId = 12L, stableKey = "12", title = "旧订阅通知", text = "已添加订阅", category = "订阅"),
            SentNotificationItemDto(numericId = 11L, stableKey = "11", title = "旧插件消息", text = "签到完成", category = "插件"),
        )
        val initialBatch = AndroidPushProvider.computeIncrementalNotifications(
            fetchedNewestFirst = historical,
            current = NotificationWatermark(initialized = false),
            activeUserName = "admin",
        )
        assertTrue(initialBatch.toDeliver.isEmpty())
        assertTrue(initialBatch.nextWatermark.initialized)
        assertEquals(12L, initialBatch.nextWatermark.maxNumericId)

        val nextPollNewestFirst = listOf(
            SentNotificationItemDto(numericId = 15L, stableKey = "15", title = "他人专属通知", text = "仅 bob 可见", category = "系统", userid = "bob"),
            SentNotificationItemDto(numericId = 14L, stableKey = "14", title = "站点签到插件", text = "今日全部站点签到成功", category = "插件"),
            SentNotificationItemDto(numericId = 13L, stableKey = "13", title = "整理入库完成", text = "电影已入库", category = "媒体入库"),
            SentNotificationItemDto(numericId = 12L, stableKey = "12", title = "旧订阅通知", text = "已添加订阅", category = "订阅"),
        )
        val secondBatch = AndroidPushProvider.computeIncrementalNotifications(
            fetchedNewestFirst = nextPollNewestFirst,
            current = initialBatch.nextWatermark,
            activeUserName = "admin",
        )
        assertEquals(listOf(13L, 14L), secondBatch.toDeliver.map { it.numericId })
        assertEquals(AndroidPushProvider.CHANNEL_ID_GENERAL, AndroidPushProvider.selectChannelForNotification(secondBatch.toDeliver[0]))
        assertEquals(AndroidPushProvider.CHANNEL_ID_PLUGIN, AndroidPushProvider.selectChannelForNotification(secondBatch.toDeliver[1]))
        assertEquals(15L, secondBatch.nextWatermark.maxNumericId)
    }
}
