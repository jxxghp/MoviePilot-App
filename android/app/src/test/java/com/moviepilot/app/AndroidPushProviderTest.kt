package com.moviepilot.app

import org.junit.Assert.assertTrue
import org.junit.Test

/** 验证 Android 多端推送契约与基础配置常量。 */
class AndroidPushProviderTest {
    @Test
    fun registrationPayloadContainsAndroidPlatformAndToken() {
        val payload = AndroidPushProvider.buildRegistrationPayload("synthetic-fcm-token", "2.0.2")
        assertTrue(payload.contains("\"platform\":\"android\""))
        assertTrue(payload.contains("synthetic-fcm-token"))
        assertTrue(payload.contains("2.0.2"))
    }
}
