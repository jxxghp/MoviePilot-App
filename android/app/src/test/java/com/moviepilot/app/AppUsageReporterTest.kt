package com.moviepilot.app

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/** Android 匿名安装版本统计上报单测（对齐 iOS 隐私边界、24h 节流与升级即报契约）。 */
class AppUsageReporterTest {

    private class MemoryStore : UsageReportStore {
        private val strings = mutableMapOf<String, String>()
        private val longs = mutableMapOf<String, Long>()
        override fun getString(key: String): String? = strings[key]
        override fun putString(key: String, value: String) { strings[key] = value }
        override fun getLong(key: String): Long = longs[key] ?: 0L
        override fun putLong(key: String, value: Long) { longs[key] = value }
    }

    @Test
    fun normalizeHttpsBaseRejectsInsecureOrMalformedHosts() {
        assertEquals("https://movie-pilot.org", AppUsageReporter.normalizeHttpsBase("https://movie-pilot.org/"))
        assertEquals("https://stats.example.com:8443/sub", AppUsageReporter.normalizeHttpsBase("https://Stats.Example.com:8443/sub/"))
        assertNull(AppUsageReporter.normalizeHttpsBase("http://movie-pilot.org"))
        assertNull(AppUsageReporter.normalizeHttpsBase("https://user:pass@movie-pilot.org"))
        assertNull(AppUsageReporter.normalizeHttpsBase("https://movie-pilot.org?a=1"))
        assertNull(AppUsageReporter.normalizeHttpsBase("https://movie-pilot.org#frag"))
        assertNull(AppUsageReporter.normalizeHttpsBase(" "))
    }

    @Test
    fun reportThrottlesPerHostAndVersionAndReReportsOnUpgradeOrFailure() = runBlocking {
        val store = MemoryStore()
        val sent = mutableListOf<Pair<String, String>>()
        var shouldSucceed = true
        val reporter = AppUsageReporter(store = store) { endpoint, payload ->
            sent += endpoint to payload
            shouldSucceed
        }

        // 未开启开关不发送
        assertFalse(reporter.report(enabled = false, host = "https://movie-pilot.org", version = "2.0.3", nowMs = 1_000L))
        assertTrue(sent.isEmpty())

        // 首次成功上报
        assertTrue(reporter.report(enabled = true, host = "https://movie-pilot.org/", version = "2.0.3", nowMs = 1_000L))
        assertEquals(1, sent.size)
        assertEquals("https://movie-pilot.org/usage/android/report", sent[0].first)
        val firstPayload = sent[0].second
        assertTrue(firstPayload.contains("\"version\":\"2.0.3\""))
        val uuidMatch = Regex(""""installation_id":"([^"]+)"""").find(firstPayload)
        assertNotNull(uuidMatch)
        val installationId = uuidMatch!!.groupValues[1]
        UUID.fromString(installationId)

        // 24 小时内同服务同版本节流
        assertFalse(reporter.report(enabled = true, host = "https://movie-pilot.org", version = "2.0.3", nowMs = 1_000L + 3_600_000L))
        assertEquals(1, sent.size)

        // 升级版本立即重报，复用同一匿名 installation_id；若失败则不写节流标记
        shouldSucceed = false
        assertFalse(reporter.report(enabled = true, host = "https://movie-pilot.org", version = "2.0.4", nowMs = 1_000L + 7_200_000L))
        assertEquals(2, sent.size)
        assertTrue(sent[1].second.contains("\"installation_id\":\"$installationId\""))
        assertTrue(sent[1].second.contains("\"version\":\"2.0.4\""))

        // 失败后重试立即放行并成功写入节流
        shouldSucceed = true
        assertTrue(reporter.report(enabled = true, host = "https://movie-pilot.org", version = "2.0.4", nowMs = 1_000L + 7_205_000L))
        assertEquals(3, sent.size)

        // 超过 24 小时后允许再次上报
        assertTrue(
            reporter.report(
                enabled = true,
                host = "https://movie-pilot.org",
                version = "2.0.4",
                nowMs = 1_000L + 7_205_000L + AppUsageReporter.THROTTLE_WINDOW_MS + 1L,
            ),
        )
        assertEquals(4, sent.size)
    }
}
