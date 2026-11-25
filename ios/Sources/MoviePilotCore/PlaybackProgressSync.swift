import Foundation

/// 跨端统一的播放进度同步触发事件（与 Rust `mp_core_model::PlaybackSyncTrigger` 保持 1:1 语义一致）。
public enum PlaybackSyncTrigger: String, Codable, Sendable, Equatable {
  case start
  case tick
  case pause
  case resume
  case seek
  case trackChange = "track_change"
  case background
  case stop
  case finish
}

/// 单个播放会话在客户端维护的状态机快照。
public struct PlaybackSyncState: Codable, Sendable, Equatable {
  public var playSessionId: String
  public var startedSent: Bool
  public var stoppedSent: Bool
  public var pausedSinceMs: Int64?
  public var lastReportAtMs: Int64?
  public var lastPlayingTickAtMs: Int64?
  public var lastSeekAtMs: Int64?
  public var cumulativePlaybackTimeMs: Int64
  public var seq: UInt64
  public var lastPositionMs: Int64
  public var lastAudioStreamIndex: Int?
  public var lastSubtitleStreamIndex: Int?

  public init(
    playSessionId: String = "",
    startedSent: Bool = false,
    stoppedSent: Bool = false,
    pausedSinceMs: Int64? = nil,
    lastReportAtMs: Int64? = nil,
    lastPlayingTickAtMs: Int64? = nil,
    lastSeekAtMs: Int64? = nil,
    cumulativePlaybackTimeMs: Int64 = 0,
    seq: UInt64 = 0,
    lastPositionMs: Int64 = 0,
    lastAudioStreamIndex: Int? = nil,
    lastSubtitleStreamIndex: Int? = nil
  ) {
    self.playSessionId = playSessionId
    self.startedSent = startedSent
    self.stoppedSent = stoppedSent
    self.pausedSinceMs = pausedSinceMs
    self.lastReportAtMs = lastReportAtMs
    self.lastPlayingTickAtMs = lastPlayingTickAtMs
    self.lastSeekAtMs = lastSeekAtMs
    self.cumulativePlaybackTimeMs = cumulativePlaybackTimeMs
    self.seq = seq
    self.lastPositionMs = lastPositionMs
    self.lastAudioStreamIndex = lastAudioStreamIndex
    self.lastSubtitleStreamIndex = lastSubtitleStreamIndex
  }
}

/// 单步推演输入采样。
public struct PlaybackSyncInput: Codable, Sendable, Equatable {
  public let trigger: PlaybackSyncTrigger
  public let nowMs: Int64
  public let positionMs: Int64
  public let durationMs: Int64?
  public let isPaused: Bool
  public let audioStreamIndex: Int?
  public let subtitleStreamIndex: Int?

  public init(
    trigger: PlaybackSyncTrigger,
    nowMs: Int64,
    positionMs: Int64,
    durationMs: Int64? = nil,
    isPaused: Bool = false,
    audioStreamIndex: Int? = nil,
    subtitleStreamIndex: Int? = nil
  ) {
    self.trigger = trigger
    self.nowMs = nowMs
    self.positionMs = positionMs
    self.durationMs = durationMs
    self.isPaused = isPaused
    self.audioStreamIndex = audioStreamIndex
    self.subtitleStreamIndex = subtitleStreamIndex
  }
}

/// 单步推演输出决策。
public struct PlaybackSyncDecision: Codable, Sendable, Equatable {
  public let shouldReport: Bool
  public let state: String
  public let eventName: String?
  public let isPaused: Bool
  public let positionMs: Int64
  public let playbackTimeMs: Int64
  public let seq: UInt64
  public let nextState: PlaybackSyncState
}

/// 离线失败时落盘等待重连补报的 `stopped` 终态记录。
public struct PendingPlaybackStop: Codable, Sendable, Equatable {
  public let server: String
  public let itemId: String
  public let mediaSourceId: String?
  public let positionMs: Int64
  public let durationMs: Int64?
  public let playSessionId: String?
  public let playbackTimeMs: Int64?
  public let seq: UInt64?
  public let updatedAtMs: Int64

  public init(
    server: String,
    itemId: String,
    mediaSourceId: String? = nil,
    positionMs: Int64,
    durationMs: Int64? = nil,
    playSessionId: String? = nil,
    playbackTimeMs: Int64? = nil,
    seq: UInt64? = nil,
    updatedAtMs: Int64
  ) {
    self.server = server
    self.itemId = itemId
    self.mediaSourceId = mediaSourceId
    self.positionMs = positionMs
    self.durationMs = durationMs
    self.playSessionId = playSessionId
    self.playbackTimeMs = playbackTimeMs
    self.seq = seq
    self.updatedAtMs = updatedAtMs
  }
}

/// 跨端共享算法同构实现：起播 `Start`、10s 播放心跳、12s 暂停保活（15 分钟自动释放）、300ms Seek 防抖与离线补报去重。
public enum PlaybackProgressPlanner {
  public static let playingHeartbeatIntervalMs: Int64 = 10_000
  public static let pausedHeartbeatIntervalMs: Int64 = 12_000
  public static let pausedAutoStopMs: Int64 = 15 * 60 * 1_000
  public static let seekDebounceMs: Int64 = 300
  public static let pendingStopTtlMs: Int64 = 7 * 24 * 60 * 60 * 1_000
  public static let maxPendingStops: Int = 30
  private static let maxPlaybackDeltaMs: Int64 = 60_000

  /// 计算当前播放事件是否应上报以及更新后的状态机快照。
  public static func step(
    _ current: PlaybackSyncState,
    input: PlaybackSyncInput
  ) -> PlaybackSyncDecision {
    var next = current
    let now = max(0, input.nowMs)

    if !input.isPaused && input.trigger != .pause && input.trigger != .background {
      if let prevTick = next.lastPlayingTickAtMs {
        let delta = now - prevTick
        if delta > 0 {
          next.cumulativePlaybackTimeMs += min(delta, maxPlaybackDeltaMs)
        }
      }
      next.lastPlayingTickAtMs = now
    } else {
      next.lastPlayingTickAtMs = nil
    }

    let resolvedPos: Int64
    switch input.trigger {
    case .seek:
      resolvedPos = max(0, input.positionMs)
    case .finish:
      if let dur = input.durationMs, dur > 0 {
        resolvedPos = dur
      } else {
        resolvedPos = max(0, max(input.positionMs, next.lastPositionMs))
      }
    default:
      if input.positionMs > 0 {
        resolvedPos = input.positionMs
      } else if next.lastPositionMs > 0
        && (input.trigger == .stop || input.trigger == .pause || input.trigger == .background)
      {
        resolvedPos = next.lastPositionMs
      } else {
        resolvedPos = max(0, input.positionMs)
      }
    }
    next.lastPositionMs = resolvedPos

    if next.stoppedSent {
      let allowReactivate =
        input.trigger == .start
        || input.trigger == .resume
        || (input.trigger == .tick && !input.isPaused)
      if !allowReactivate {
        return noReport(next, state: "stopped", isPaused: true, positionMs: resolvedPos)
      }
      next.stoppedSent = false
      next.startedSent = false
      next.pausedSinceMs = nil
    }

    switch input.trigger {
    case .stop, .finish:
      next.stoppedSent = true
      next.pausedSinceMs = nil
      next.lastPlayingTickAtMs = nil
      return emit(next, nowMs: now, state: "stopped", eventName: nil, isPaused: true, positionMs: resolvedPos)
    case .start:
      next.startedSent = true
      next.stoppedSent = false
      next.pausedSinceMs = nil
      next.lastAudioStreamIndex = input.audioStreamIndex
      next.lastSubtitleStreamIndex = input.subtitleStreamIndex
      return emit(next, nowMs: now, state: "started", eventName: "Start", isPaused: false, positionMs: resolvedPos)
    case .pause, .background:
      if next.pausedSinceMs == nil {
        next.pausedSinceMs = now
      }
      return emit(next, nowMs: now, state: "paused", eventName: "Pause", isPaused: true, positionMs: resolvedPos)
    case .resume:
      next.pausedSinceMs = nil
      if !next.startedSent {
        next.startedSent = true
        return emit(next, nowMs: now, state: "started", eventName: "Start", isPaused: false, positionMs: resolvedPos)
      }
      return emit(next, nowMs: now, state: "playing", eventName: "Unpause", isPaused: false, positionMs: resolvedPos)
    case .seek:
      let withinDebounce = next.lastSeekAtMs.map { now - $0 < seekDebounceMs } ?? false
      next.lastSeekAtMs = now
      let stateStr = input.isPaused ? "paused" : "playing"
      if withinDebounce {
        return noReport(next, state: stateStr, isPaused: input.isPaused, positionMs: resolvedPos)
      }
      return emit(next, nowMs: now, state: stateStr, eventName: "TimeUpdate", isPaused: input.isPaused, positionMs: resolvedPos)
    case .trackChange:
      let eventName: String
      if input.audioStreamIndex != next.lastAudioStreamIndex {
        eventName = "AudioTrackChange"
      } else if input.subtitleStreamIndex != next.lastSubtitleStreamIndex {
        eventName = "SubtitleTrackChange"
      } else {
        eventName = "TimeUpdate"
      }
      next.lastAudioStreamIndex = input.audioStreamIndex
      next.lastSubtitleStreamIndex = input.subtitleStreamIndex
      let stateStr = input.isPaused ? "paused" : "playing"
      return emit(next, nowMs: now, state: stateStr, eventName: eventName, isPaused: input.isPaused, positionMs: resolvedPos)
    case .tick:
      if !input.isPaused && !next.startedSent {
        next.startedSent = true
        next.pausedSinceMs = nil
        return emit(next, nowMs: now, state: "started", eventName: "Start", isPaused: false, positionMs: resolvedPos)
      }
      if input.isPaused {
        let pausedSince = next.pausedSinceMs ?? now
        next.pausedSinceMs = pausedSince
        if now - pausedSince >= pausedAutoStopMs {
          next.stoppedSent = true
          next.pausedSinceMs = nil
          return emit(next, nowMs: now, state: "stopped", eventName: nil, isPaused: true, positionMs: resolvedPos)
        }
        let due = next.lastReportAtMs.map { now - $0 >= pausedHeartbeatIntervalMs } ?? true
        if due {
          return emit(next, nowMs: now, state: "paused", eventName: "Pause", isPaused: true, positionMs: resolvedPos)
        }
        return noReport(next, state: "paused", isPaused: true, positionMs: resolvedPos)
      } else {
        next.pausedSinceMs = nil
        let due = next.lastReportAtMs.map { now - $0 >= playingHeartbeatIntervalMs } ?? true
        if due {
          return emit(next, nowMs: now, state: "playing", eventName: "TimeUpdate", isPaused: false, positionMs: resolvedPos)
        }
        return noReport(next, state: "playing", isPaused: false, positionMs: resolvedPos)
      }
    }
  }

  /// 按 `(server, itemId)` 去重保留最新记录，清理 7 天过期项并裁剪至上限。
  public static func normalizePendingStops(
    _ entries: [PendingPlaybackStop],
    nowEpochMs: Int64
  ) -> [PendingPlaybackStop] {
    var latestByKey: [String: PendingPlaybackStop] = [:]
    for entry in entries {
      let server = entry.server.trimmingCharacters(in: .whitespacesAndNewlines)
      let itemId = entry.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !server.isEmpty, !itemId.isEmpty else { continue }
      if nowEpochMs > 0 && entry.updatedAtMs > 0 && (nowEpochMs - entry.updatedAtMs) > pendingStopTtlMs {
        continue
      }
      let normalized = PendingPlaybackStop(
        server: server,
        itemId: itemId,
        mediaSourceId: entry.mediaSourceId,
        positionMs: max(0, entry.positionMs),
        durationMs: entry.durationMs,
        playSessionId: entry.playSessionId,
        playbackTimeMs: entry.playbackTimeMs,
        seq: entry.seq,
        updatedAtMs: entry.updatedAtMs
      )
      let key = "\(server)\u{0000}\(itemId)"
      if let existing = latestByKey[key], existing.updatedAtMs > normalized.updatedAtMs {
        continue
      }
      latestByKey[key] = normalized
    }
    let sorted = latestByKey.values.sorted { lhs, rhs in
      if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
      if lhs.server != rhs.server { return lhs.server < rhs.server }
      return lhs.itemId < rhs.itemId
    }
    return Array(sorted.prefix(maxPendingStops))
  }

  private static func emit(
    _ stateValue: PlaybackSyncState,
    nowMs: Int64,
    state: String,
    eventName: String?,
    isPaused: Bool,
    positionMs: Int64
  ) -> PlaybackSyncDecision {
    var next = stateValue
    next.seq &+= 1
    next.lastReportAtMs = nowMs
    return PlaybackSyncDecision(
      shouldReport: true,
      state: state,
      eventName: eventName,
      isPaused: isPaused,
      positionMs: positionMs,
      playbackTimeMs: next.cumulativePlaybackTimeMs,
      seq: next.seq,
      nextState: next
    )
  }

  private static func noReport(
    _ stateValue: PlaybackSyncState,
    state: String,
    isPaused: Bool,
    positionMs: Int64
  ) -> PlaybackSyncDecision {
    PlaybackSyncDecision(
      shouldReport: false,
      state: state,
      eventName: nil,
      isPaused: isPaused,
      positionMs: positionMs,
      playbackTimeMs: stateValue.cumulativePlaybackTimeMs,
      seq: stateValue.seq,
      nextState: stateValue
    )
  }
}

/// 当前用户在单个媒体服务器实例上的脱敏账号绑定与播放同步能力模型。
public struct MediaServerAccountBindingDTO: Decodable, Identifiable, Hashable, Sendable {
  public let server: String
  public let serverType: String
  public let syncMode: String
  public let supportsBinding: Bool
  public let bound: Bool
  public let status: String
  public let remoteUsername: String?
  public let source: String?
  public let updatedAt: Int?

  public var id: String { server }

  private enum CodingKeys: String, CodingKey {
    case server
    case serverType = "server_type"
    case syncMode = "sync_mode"
    case supportsBinding = "supports_binding"
    case bound
    case status
    case remoteUsername = "remote_username"
    case source
    case updatedAt = "updated_at"
  }
}

/// 媒体服务器播放进度上报结构化回执模型。
public struct MediaServerProgressReportResultDTO: Decodable, Hashable, Sendable {
  public let reported: Bool
  public let mode: String
  public let playSessionId: String?
  public let needsAccountBind: Bool
  public let detail: String?

  private enum CodingKeys: String, CodingKey {
    case reported
    case mode
    case playSessionId = "play_session_id"
    case needsAccountBind = "needs_account_bind"
    case detail
  }
}
