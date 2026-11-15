import XCTest

@testable import MoviePilotCore

/// 验证中断、用户意图和音频路由变化交错发生时的自动恢复边界。
final class PlaybackInterruptionStateTests: XCTestCase {
  /// 播放中的系统中断只在允许恢复时消费一次恢复意图。
  func testResumesPlayingMediaOnlyOnce() {
    var state = PlaybackInterruptionState()
    state.begin(wasPlaying: true)
    XCTAssertTrue(state.isInterrupted)
    XCTAssertTrue(state.end(systemAllowsResume: true))
    XCTAssertFalse(state.isInterrupted)
    XCTAssertFalse(state.end(systemAllowsResume: true))
  }

  /// 已暂停的媒体或系统禁止恢复的中断均不得自动播放。
  func testPreservesPauseAndSystemRestrictions() {
    var state = PlaybackInterruptionState()
    state.begin(wasPlaying: false)
    XCTAssertFalse(state.end(systemAllowsResume: true))
    state.begin(wasPlaying: true)
    XCTAssertFalse(state.end(systemAllowsResume: false))
    XCTAssertFalse(state.end(systemAllowsResume: true))
  }

  /// 重复开始通知不能把真实播放意图替换为暂停后的解码状态。
  func testRepeatedBeginKeepsOriginalIntent() {
    var state = PlaybackInterruptionState()
    state.begin(wasPlaying: true)
    state.begin(wasPlaying: false)
    XCTAssertTrue(state.end(systemAllowsResume: true))
  }

  /// 来电期间拔出耳机或明确暂停后，结束通知不能从扬声器自动播放。
  func testUserPauseOrRouteLossCancelsResume() {
    var state = PlaybackInterruptionState()
    state.begin(wasPlaying: true)
    state.cancelResume()
    XCTAssertTrue(state.isInterrupted)
    state.begin(wasPlaying: false)
    XCTAssertFalse(state.end(systemAllowsResume: true))
    state.begin(wasPlaying: true)
    XCTAssertTrue(state.end(systemAllowsResume: true))
  }
}
