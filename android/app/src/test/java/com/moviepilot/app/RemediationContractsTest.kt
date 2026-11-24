package com.moviepilot.app

import com.moviepilot.designsystem.NativeAppearanceMode
import com.moviepilot.designsystem.NativeAppearanceStore
import com.moviepilot.rustbridge.MediaServerStreamTrackDto
import com.moviepilot.rustbridge.MoviePilotRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 覆盖订阅身份规范化、媒体类型稳定性、媒体服务器轨道技术规格格式化与深色启动模式的回归单测。
 */
class RemediationContractsTest {

    @Test
    fun canonicalMediaIdentityStripsPrefixesAndNormalizesExploreSources() {
        assertEquals(
            "themoviedb" to "12345",
            MoviePilotRepository.normalizeCanonicalMediaIdentity("tmdb_movies", "tmdb:12345"),
        )
        assertEquals(
            "douban" to "35209731",
            MoviePilotRepository.normalizeCanonicalMediaIdentity("douban_showing", null, doubanId = "35209731"),
        )
        assertEquals(
            "bangumi" to "400602",
            MoviePilotRepository.normalizeCanonicalMediaIdentity("bgm", null, bangumiId = 400602),
        )
        assertEquals(
            "themoviedb" to "99887",
            MoviePilotRepository.normalizeCanonicalMediaIdentity("Emby", "item-abc", tmdbId = 99887),
        )
        assertNull(
            MoviePilotRepository.normalizeCanonicalMediaIdentity("Emby", "item-only-no-external-id"),
        )
        assertNull(
            MoviePilotRepository.normalizeCanonicalMediaIdentity("themoviedb", "0"),
        )
    }

    @Test
    fun tvTypeClassificationRemainsStableAcrossEnglishAndChineseLabels() {
        listOf("电视剧", "tv", "Series", "Season", "Episode", "番剧").forEach { raw ->
            assertTrue("Expected TV type for $raw", MoviePilotRepository.isTvType(raw))
            assertEquals("电视剧", MoviePilotRepository.canonicalMediaType(raw))
        }
        listOf("电影", "movie", "Movie").forEach { raw ->
            assertFalse("Expected non-TV type for $raw", MoviePilotRepository.isTvType(raw))
            assertEquals("电影", MoviePilotRepository.canonicalMediaType(raw))
        }
    }

    @Test
    fun streamTrackFormattingMatchesReferenceSpec() {
        val videoTrack = MediaServerStreamTrackDto(
            type = "video",
            codec = "h264",
            width = 1920,
            height = 1080,
            bitrate = 14_300_000L,
        )
        assertEquals("1920x1080", videoTrack.formattedResolution)
        assertEquals("16:9", videoTrack.inferredAspectRatio)
        assertEquals("14.3mbps", videoTrack.formattedBitrate)

        val audioTrack = MediaServerStreamTrackDto(
            type = "audio",
            codec = "eac3",
            channels = 6,
            channelLayout = "5.1",
            bitrate = 1_000_000L,
            sampleRate = 48_000,
        )
        assertEquals("1000kbps", audioTrack.formattedBitrate)
    }

    @Test
    fun appearanceStoreResolvesDarkAndLightModesDeterministically() {
        val store = NativeAppearanceStore(null)
        store.updateMode(NativeAppearanceMode.Dark)
        assertTrue(store.resolveIsDark(systemDark = false))
        assertTrue(store.resolveIsDark(systemDark = true))

        store.updateMode(NativeAppearanceMode.Light)
        assertFalse(store.resolveIsDark(systemDark = true))
        assertFalse(store.resolveIsDark(systemDark = false))

        store.updateMode(NativeAppearanceMode.System)
        assertTrue(store.resolveIsDark(systemDark = true))
        assertFalse(store.resolveIsDark(systemDark = false))
    }
}
