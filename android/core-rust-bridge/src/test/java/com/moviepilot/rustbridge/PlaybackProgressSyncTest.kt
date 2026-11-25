package com.moviepilot.rustbridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackProgressSyncTest {
    @Test
    fun `start playing heartbeat paused keepalive and auto stop`() {
        val tracker = PlaybackSyncSessionTracker(playSessionId = "ps-android-1")

        val start = tracker.step("start", positionMs = 0L, durationMs = 3_600_000L, isPaused = false, nowMs = 1_000L)
        assertTrue(start.shouldReport)
        assertEquals("started", start.state)
        assertEquals(1L, start.seq)

        val earlyTick = tracker.step("tick", positionMs = 5_000L, durationMs = 3_600_000L, isPaused = false, nowMs = 6_000L)
        assertFalse(earlyTick.shouldReport)

        val playTick = tracker.step("tick", positionMs = 10_000L, durationMs = 3_600_000L, isPaused = false, nowMs = 11_000L)
        assertTrue(playTick.shouldReport)
        assertEquals("playing", playTick.state)
        assertEquals("timeupdate", playTick.eventName)
        assertEquals(10_000L, playTick.playbackTimeMs)
        assertEquals(2L, playTick.seq)

        val pause = tracker.step("pause", positionMs = 12_000L, durationMs = 3_600_000L, isPaused = true, nowMs = 13_000L)
        assertTrue(pause.shouldReport)
        assertEquals("paused", pause.state)
        assertEquals("pause", pause.eventName)

        val keepalive = tracker.step("tick", positionMs = 12_000L, durationMs = 3_600_000L, isPaused = true, nowMs = 25_000L)
        assertTrue(keepalive.shouldReport)
        assertEquals("paused", keepalive.state)
        assertEquals("timeupdate", keepalive.eventName)

        // 15 分钟后自动释放会话
        val autoStop = tracker.step("tick", positionMs = 12_000L, durationMs = 3_600_000L, isPaused = true, nowMs = 13_000L + 15L * 60_000L)
        assertTrue(autoStop.shouldReport)
        assertEquals("stopped", autoStop.state)
        assertTrue(tracker.isStopped())

        // 重复 stop 幂等跳过
        val dupStop = tracker.step("stop", positionMs = 12_000L, durationMs = 3_600_000L, isPaused = true, nowMs = 13_000L + 15L * 60_000L + 500L)
        assertFalse(dupStop.shouldReport)

        // 恢复播放自动重开会话
        val resumed = tracker.step("resume", positionMs = 12_000L, durationMs = 3_600_000L, isPaused = false, nowMs = 13_000L + 16L * 60_000L)
        assertTrue(resumed.shouldReport)
        assertEquals("started", resumed.state)
    }

    @Test
    fun `seek backward to zero is preserved and pending stops normalize`() {
        val tracker = PlaybackSyncSessionTracker(playSessionId = "ps-seek")
        tracker.step("start", positionMs = 120_000L, durationMs = 600_000L, isPaused = false, nowMs = 1_000L)
        val seekZero = tracker.step("seek", positionMs = 0L, durationMs = 600_000L, isPaused = false, nowMs = 2_000L)
        assertTrue(seekZero.shouldReport)
        assertEquals(0L, seekZero.positionMs)

        val now = 10_000_000_000L
        val stale = now - 8L * 24L * 3600L * 1000L
        val normalized = RustCoreBridge.normalizePendingPlaybackStops(
            listOf(
                PendingPlaybackStopDto("Emby", "ep-1", positionMs = 10_000L, updatedAtMs = now - 10_000L),
                PendingPlaybackStopDto("Emby", "ep-1", positionMs = 25_000L, updatedAtMs = now - 1_000L),
                PendingPlaybackStopDto("Plex", "old", positionMs = 5_000L, updatedAtMs = stale),
            ),
            nowEpochMs = now,
        )
        assertEquals(1, normalized.size)
        assertEquals(25_000L, normalized.first().positionMs)
    }
}
