package com.moviepilot.pluginhost.runtime

import android.media.session.PlaybackState
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PluginCapsuleAndAudioBufferingTest {
    private val sampleBounds = CapsuleSafeBounds(
        viewportWidthPx = 1080,
        viewportHeightPx = 2400,
        insetLeftPx = 0,
        insetTopPx = 96,
        insetRightPx = 0,
        insetBottomPx = 144,
        horizontalMarginPx = 36,
        verticalMarginPx = 24,
    )

    @Test
    fun clampDuringDragPreventsDraggingOffScreenOrIntoSystemBars() {
        val (clampedLeftX, clampedTopY) = PluginCapsuleLayoutCalculator.clampDuringDrag(
            rawX = -600,
            rawY = -200,
            itemWidthPx = 520,
            itemHeightPx = 110,
            bounds = sampleBounds,
        )
        assertEquals(0, clampedLeftX)
        assertEquals(120, clampedTopY) // insetTop(96) + verticalMargin(24)

        val (clampedRightX, clampedBottomY) = PluginCapsuleLayoutCalculator.clampDuringDrag(
            rawX = 2000,
            rawY = 5000,
            itemWidthPx = 520,
            itemHeightPx = 110,
            bounds = sampleBounds,
        )
        assertEquals(1080 - 520, clampedRightX)
        assertEquals(2400 - 144 - 24 - 110, clampedBottomY)
    }

    @Test
    fun settleAfterDragSnapsToLeftOrRightSuperMinimizedAndRestoresInsideSafeBounds() {
        val snapThresholdPx = 72 // 24dp @ 3x density

        // 拖至距左边缘 18px (< 72px) 松手 -> 自动贴左边缘进入超级最小化
        val dockedLeft = PluginCapsuleLayoutCalculator.settleAfterDrag(
            rawX = 18,
            rawY = 900,
            itemWidthPx = 520,
            itemHeightPx = 110,
            bounds = sampleBounds,
            snapThresholdPx = snapThresholdPx,
        )
        assertEquals(CapsuleDockedEdge.LEFT, dockedLeft.dockedEdge)
        assertTrue(dockedLeft.isSuperMinimized)
        val (leftSuperX, _) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
            placement = dockedLeft,
            itemWidthPx = 126,
            itemHeightPx = 110,
            bounds = sampleBounds,
        )
        assertEquals(0, leftSuperX)

        // 点击半圆恢复完整单行胶囊 -> 自动内缩至安全留白 (horizontalMarginPx = 36)
        val restoredFromLeft = PluginCapsuleLayoutCalculator.expandFromDocked(dockedLeft)
        assertFalse(restoredFromLeft.isSuperMinimized)
        val (restoredLeftX, _) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
            placement = restoredFromLeft,
            itemWidthPx = 520,
            itemHeightPx = 110,
            bounds = sampleBounds,
        )
        assertEquals(36, restoredLeftX)

        // 拖至距右边缘 20px (< 72px) 松手 -> 自动贴右边缘进入超级最小化
        val dockedRight = PluginCapsuleLayoutCalculator.settleAfterDrag(
            rawX = 1080 - 520 - 20,
            rawY = 1200,
            itemWidthPx = 520,
            itemHeightPx = 110,
            bounds = sampleBounds,
            snapThresholdPx = snapThresholdPx,
        )
        assertEquals(CapsuleDockedEdge.RIGHT, dockedRight.dockedEdge)
        val (rightSuperX, _) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
            placement = dockedRight,
            itemWidthPx = 126,
            itemHeightPx = 110,
            bounds = sampleBounds,
        )
        assertEquals(1080 - 126, rightSuperX)

        val restoredFromRight = PluginCapsuleLayoutCalculator.expandFromDocked(dockedRight)
        val (restoredRightX, _) = PluginCapsuleLayoutCalculator.resolveTopLeftPx(
            placement = restoredFromRight,
            itemWidthPx = 520,
            itemHeightPx = 110,
            bounds = sampleBounds,
        )
        assertEquals(1080 - 36 - 520, restoredRightX)
    }

    @Test
    fun snapshotParsesConfigurableEdgeSnapThresholdDp() {
        val snap = PluginCapsuleSnapshot.fromMinimizePayload(
            pluginId = "MusicPlayer",
            fallbackName = "音乐播放器",
            payload = buildJsonObject {
                put("title", JsonPrimitive("晴天"))
                put("edgeSnapThresholdDp", JsonPrimitive(32))
            },
        )
        assertEquals(32, snap.edgeSnapThresholdDp)

        val patched = snap.mergePatch(
            buildJsonObject {
                put("edgeSnapThresholdDp", JsonPrimitive(120))
            },
        )
        assertEquals(PluginCapsuleLayoutCalculator.MAX_EDGE_SNAP_THRESHOLD_DP, patched.edgeSnapThresholdDp)
    }

    @Test
    fun capsuleShortFieldsTakePrecedenceAndRemainStableAcrossSameTrackNowPlayingUpdates() {
        val snap = PluginCapsuleSnapshot.fromMinimizePayload(
            pluginId = "MusicPlayer",
            fallbackName = "音乐播放器",
            payload = buildJsonObject {
                put("title", JsonPrimitive("超级长的现场版歌曲名称 (Live)"))
                put("subtitle", JsonPrimitive("周杰伦 / 合唱嘉宾"))
                put("capsuleTitle", JsonPrimitive("超级长的现"))
                put("capsuleArtist", JsonPrimitive("周杰伦"))
            },
        )
        assertEquals("超级长的现", snap.displayTitle)
        assertEquals("周杰伦", snap.displaySubtitle)

        // 同一首歌推进歌词或播放状态时，setNowPlaying 的完整 title/artist 不会覆盖专用短字段
        val syncedSameTrack = snap.applyAudioSync(
            isPlaying = true,
            title = "超级长的现场版歌曲名称 (Live)",
            subtitle = "周杰伦 / 合唱嘉宾",
        )
        assertEquals("超级长的现", syncedSameTrack.displayTitle)
        assertEquals("周杰伦", syncedSameTrack.displaySubtitle)

        // 切换到下一首歌且未传短字段时，自动清理旧曲目的短字段并展示新曲目信息
        val nextTrack = syncedSameTrack.applyAudioSync(
            isPlaying = true,
            title = "七里香",
            subtitle = "周杰伦",
        )
        assertEquals("七里香", nextTrack.displayTitle)
        assertEquals("周杰伦", nextTrack.displaySubtitle)
    }

    @Test
    fun mediaSessionFreezesSpeedDuringBufferingAndAdvancesOnlyWhenPlaying() {
        // 原生播放处于 buffering 时，即使插件切歌乐观传入 requestedIsPlaying=true，也必须钉住 STATE_BUFFERING + 0f 倍速
        val (bufState, bufSpeed) = buildResolvedMediaSessionStateParams(
            playbackState = "buffering",
            hasInlineSession = true,
            explicitBuffering = false,
            requestedIsPlaying = true,
            rate = 1.25f,
        )
        assertEquals(PlaybackState.STATE_BUFFERING, bufState)
        assertEquals(0f, bufSpeed, 0.0001f)

        // 真正出声进入 playing 后，恢复 STATE_PLAYING 与真实倍速
        val (playState, playSpeed) = buildResolvedMediaSessionStateParams(
            playbackState = "playing",
            hasInlineSession = true,
            explicitBuffering = false,
            requestedIsPlaying = true,
            rate = 1.25f,
        )
        assertEquals(PlaybackState.STATE_PLAYING, playState)
        assertEquals(1.25f, playSpeed, 0.0001f)

        // 暂停态保持 STATE_PAUSED 与 0f 倍速
        val (pauseState, pauseSpeed) = buildResolvedMediaSessionStateParams(
            playbackState = "paused",
            hasInlineSession = true,
            explicitBuffering = false,
            requestedIsPlaying = false,
            rate = 1.0f,
        )
        assertEquals(PlaybackState.STATE_PAUSED, pauseState)
        assertEquals(0f, pauseSpeed, 0.0001f)
    }
}
