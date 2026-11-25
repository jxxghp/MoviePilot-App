package com.moviepilot.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 验证 Android 多端推送契约与通知同源边界。 */
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
}
