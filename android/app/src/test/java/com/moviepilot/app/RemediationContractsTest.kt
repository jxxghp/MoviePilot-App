package com.moviepilot.app

import androidx.compose.ui.graphics.Color
import com.moviepilot.designsystem.MainTab
import com.moviepilot.designsystem.NativeAppearanceMode
import com.moviepilot.designsystem.NativeAppearanceStore
import com.moviepilot.designsystem.resolveMoviePilotColors
import com.moviepilot.designsystem.resolveSkeletonPalette
import com.moviepilot.rustbridge.MediaServerStreamTrackDto
import com.moviepilot.rustbridge.MoviePilotRepository
import com.moviepilot.rustbridge.UserIdentity
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

    @Test
    fun skeletonPaletteCalibratesAcrossDarkTonalPureBlackAndLightModes() {
        val store = NativeAppearanceStore(null)

        store.updatePureBlackDark(false)
        val darkColors = resolveMoviePilotColors(isDark = true, store = store)
        val darkPalette = resolveSkeletonPalette(colors = darkColors, isPureBlack = false)
        assertEquals(darkColors.surfaceContainerHigh.copy(alpha = 0.72f), darkPalette.tileFill)
        assertEquals(Color.White.copy(alpha = 0.07f), darkPalette.tileBorder)
        assertEquals(Color.White.copy(alpha = 0.085f), darkPalette.barFill)
        assertEquals(Color.White.copy(alpha = 0.085f), darkPalette.sweepPeak)

        store.updatePureBlackDark(true)
        val pureBlackColors = resolveMoviePilotColors(isDark = true, store = store)
        val pureBlackPalette = resolveSkeletonPalette(colors = pureBlackColors, isPureBlack = true)
        assertEquals(Color(0xFF151923), pureBlackPalette.tileFill)
        assertEquals(Color.White.copy(alpha = 0.10f), pureBlackPalette.tileBorder)
        assertEquals(Color.White.copy(alpha = 0.105f), pureBlackPalette.barFill)
        assertEquals(Color.White.copy(alpha = 0.10f), pureBlackPalette.sweepPeak)

        val lightColors = resolveMoviePilotColors(isDark = false, store = store)
        val lightPalette = resolveSkeletonPalette(colors = lightColors, isPureBlack = false)
        assertEquals(lightColors.surfaceContainerHigh.copy(alpha = 0.82f), lightPalette.tileFill)
        assertEquals(Color.Black.copy(alpha = 0.05f), lightPalette.tileBorder)
        assertEquals(lightColors.textPrimary.copy(alpha = 0.075f), lightPalette.barFill)
        assertEquals(Color.White.copy(alpha = 0.70f), lightPalette.sweepPeak)
    }

    @Test
    fun mainTabEntriesAlignWithUnifiedFourTabOrder() {
        assertEquals(
            listOf("发现", "订阅", "我的", "更多"),
            MainTab.entries.map { it.label },
        )
        assertEquals(
            listOf("discover", "subscribe", "dashboard", "workspace"),
            MainTab.entries.map { it.id },
        )
        assertEquals(1, UserIdentity().level)
    }
}
