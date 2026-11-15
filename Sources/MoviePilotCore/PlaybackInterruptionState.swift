/// 保留系统音频中断前的播放意图，避免已暂停或已拔出耳机的媒体意外自动恢复。
public struct PlaybackInterruptionState: Sendable {
  /// 当前仍处于系统中断期间，用户播放命令应等待中断结束。
  public private(set) var isInterrupted = false
  private var resumeRequested = false

  /// 创建没有待恢复播放意图的状态。
  public init() {}

  /// 首次中断保存原播放状态；重复的开始通知不覆盖已保存的意图。
  public mutating func begin(wasPlaying: Bool) {
    guard !isInterrupted else { return }
    isInterrupted = true
    resumeRequested = wasPlaying
  }

  /// 用户暂停或耳机断开后取消自动恢复，保留系统仍在中断的事实。
  public mutating func cancelResume() {
    resumeRequested = false
  }

  /// 仅在确有中断、原本在播放且系统允许时恢复；消费一次后不重复启动。
  public mutating func end(systemAllowsResume: Bool) -> Bool {
    let shouldResume = isInterrupted && resumeRequested && systemAllowsResume
    isInterrupted = false
    resumeRequested = false
    return shouldResume
  }
}
