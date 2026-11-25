import Foundation
import MoviePilotCore
import Testing

struct PlaybackProgressSyncTests {
  @Test func emitsStartThenTenSecondHeartbeats() {
    var state = PlaybackSyncState(playSessionId: "sid-1")
    let d1 = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(trigger: .start, nowMs: 1_000, positionMs: 0, durationMs: 3_600_000))
    #expect(d1.shouldReport)
    #expect(d1.state == "started")
    #expect(d1.eventName == "Start")
    #expect(d1.seq == 1)
    state = d1.nextState

    let d2 = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(trigger: .tick, nowMs: 6_000, positionMs: 5_000, durationMs: 3_600_000))
    #expect(!d2.shouldReport)
    #expect(d2.playbackTimeMs == 5_000)
    state = d2.nextState

    let d3 = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(trigger: .tick, nowMs: 11_000, positionMs: 10_000, durationMs: 3_600_000))
    #expect(d3.shouldReport)
    #expect(d3.state == "playing")
    #expect(d3.eventName == "TimeUpdate")
    #expect(d3.playbackTimeMs == 10_000)
    #expect(d3.seq == 2)
  }

  @Test func pausedKeepaliveAndAutoStopThenReactivate() {
    var state = PlaybackProgressPlanner.step(
      PlaybackSyncState(),
      input: PlaybackSyncInput(trigger: .start, nowMs: 1_000, positionMs: 0, durationMs: 3_600_000)
    ).nextState

    let dPause = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(
        trigger: .pause, nowMs: 10_000, positionMs: 9_000, durationMs: 3_600_000, isPaused: true))
    #expect(dPause.shouldReport)
    #expect(dPause.state == "paused")
    state = dPause.nextState

    let dKeepalive = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(
        trigger: .tick, nowMs: 22_000, positionMs: 9_000, durationMs: 3_600_000, isPaused: true))
    #expect(dKeepalive.shouldReport)
    #expect(dKeepalive.state == "paused")
    state = dKeepalive.nextState

    let dAutoStop = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(
        trigger: .tick,
        nowMs: 10_000 + PlaybackProgressPlanner.pausedAutoStopMs,
        positionMs: 9_000,
        durationMs: 3_600_000,
        isPaused: true))
    #expect(dAutoStop.shouldReport)
    #expect(dAutoStop.state == "stopped")
    #expect(dAutoStop.nextState.stoppedSent)
    state = dAutoStop.nextState

    let dResume = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(
        trigger: .resume,
        nowMs: 10_000 + PlaybackProgressPlanner.pausedAutoStopMs + 10_000,
        positionMs: 9_000,
        durationMs: 3_600_000,
        isPaused: false))
    #expect(dResume.shouldReport)
    #expect(dResume.state == "started")
    #expect(dResume.eventName == "Start")
  }

  @Test func backwardSeekReplacesLastPositionAndNormalizesPendingStops() {
    var state = PlaybackSyncState(startedSent: true, lastPositionMs: 120_000)
    let d1 = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(trigger: .seek, nowMs: 5_000, positionMs: 30_000))
    #expect(d1.shouldReport)
    #expect(d1.positionMs == 30_000)
    state = d1.nextState

    let d2 = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(trigger: .seek, nowMs: 5_100, positionMs: 15_000))
    #expect(!d2.shouldReport)
    #expect(d2.nextState.lastPositionMs == 15_000)
    state = d2.nextState

    let dStop = PlaybackProgressPlanner.step(
      state,
      input: PlaybackSyncInput(trigger: .stop, nowMs: 6_000, positionMs: 0))
    #expect(dStop.shouldReport)
    #expect(dStop.positionMs == 15_000)

    let now: Int64 = 1_000_000_000_000
    let normalized = PlaybackProgressPlanner.normalizePendingStops(
      [
        PendingPlaybackStop(server: "Emby", itemId: "1", positionMs: 10_000, updatedAtMs: now - 5_000),
        PendingPlaybackStop(server: "Emby", itemId: "1", positionMs: 42_000, updatedAtMs: now - 1_000),
        PendingPlaybackStop(
          server: "Emby", itemId: "old", positionMs: 5_000,
          updatedAtMs: now - PlaybackProgressPlanner.pendingStopTtlMs - 10),
      ],
      nowEpochMs: now
    )
    #expect(normalized.count == 1)
    #expect(normalized[0].positionMs == 42_000)
  }
}
