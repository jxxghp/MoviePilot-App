import Foundation

/// 单格订阅胶片刻度的状态。
public enum SubscribeTickState: String, Equatable, Sendable {
  /// 尚未获取（空槽）。
  case empty
  /// 大集数聚合段部分收齐，或洗版模式下已有初版但尚未洗版达标。
  case partial
  /// 已收齐（普通模式已下载/入库，洗版模式已达到目标优先级）。
  case complete
}

/// 订阅离散刻度投影，用胶片式集数/曲目刻度格替代下载式连续进度条。
public struct SubscribeProgressProjection: Equatable, Sendable {
  /// 进度统计单位。
  public enum Unit: String, Equatable, Sendable {
    case episode
    case track

    /// 中文单位后缀。
    public var suffix: String {
      switch self {
      case .episode:
        return "集"
      case .track:
        return "首"
      }
    }
  }

  /// 逐集 1:1 显示的最大集数上限；超过此值后自动聚合成紧凑刻度段。
  public static let maxExactTickCount = 24
  /// 超过上限时的默认聚合刻度段数。
  public static let defaultBucketCount = 20

  /// 是否处于洗版模式。
  public let isBestVersion: Bool
  /// 进度单位（集 / 首）。
  public let unit: Unit
  /// 目标总集数或总曲目数。
  public let total: Int
  /// 已完成数（普通模式为已收齐数，洗版模式为已达标数）。
  public let completed: Int
  /// 已获取数（洗版模式下可大于 `completed`，表示含尚未洗版达标的初版数量）。
  public let acquired: Int
  /// 离散刻度格状态列表。
  public let ticks: [SubscribeTickState]
  /// 是否为 1:1 逐集映射（未做分段聚合）。
  public let isExactPerUnit: Bool
  /// 可确切定位的缺失集号（1-based 升序；非精确映射或非剧集时为空）。
  public let missingNumbers: [Int]
  /// 主状态文案（如 `"已收 8 / 12 集"`、`"待更新 · 共 36 集"`、`"洗版 6 / 12 集"`）。
  public let summaryText: String
  /// 右侧缺集或初版补充文案（如 `"缺 E04, E12"`、`"缺 4 集"`、`"已有 10 集"`）。
  public let detailText: String?

  /// 0...1 完成比例，用于按进度排序及辅助功能朗读。
  public var fraction: Double {
    guard total > 0 else { return 0 }
    return min(max(Double(completed) / Double(total), 0), 1)
  }

  /// 无障碍朗读摘要。
  public var accessibilitySummary: String {
    if let detailText, !detailText.isEmpty {
      return "\(summaryText)，\(detailText)"
    }
    return summaryText
  }

  /// 根据订阅快照构建电视剧集或音乐专辑的离散刻度投影；电影或缺少总数时返回 `nil`。
  public static func make(
    type: String?,
    musicType: String? = nil,
    totalEpisode: Int? = nil,
    startEpisode: Int? = nil,
    lackEpisode: Int? = nil,
    completedEpisode: Int? = nil,
    note: [Int]? = nil,
    bestVersion: Int? = nil,
    bestVersionFull: Int? = nil,
    currentPriority: Int? = nil,
    episodePriority: [String: Int]? = nil,
    totalTracks: Int? = nil,
    completedTracks: Int? = nil
  ) -> SubscribeProgressProjection? {
    if type == "电视剧", let total = totalEpisode, total > 0 {
      return makeEpisodeProjection(
        total: total,
        startEpisode: startEpisode,
        lackEpisode: lackEpisode,
        completedEpisode: completedEpisode,
        note: note,
        isBestVersion: bestVersion == 1,
        isBestVersionFull: bestVersionFull == 1,
        currentPriority: currentPriority,
        episodePriority: episodePriority
      )
    }

    if type == "音乐", let total = totalTracks, total > 0 {
      if let musicType, !musicType.isEmpty, musicType.lowercased() != "album" {
        return nil
      }
      return makeTrackProjection(total: total, completedTracks: completedTracks)
    }

    return nil
  }

  /// 构建电视剧订阅的离散集数刻度投影。
  private static func makeEpisodeProjection(
    total: Int,
    startEpisode: Int?,
    lackEpisode: Int?,
    completedEpisode: Int?,
    note: [Int]?,
    isBestVersion: Bool,
    isBestVersionFull: Bool,
    currentPriority: Int?,
    episodePriority: [String: Int]?
  ) -> SubscribeProgressProjection {
    let clampedStart = min(max(startEpisode ?? 1, 1), total + 1)
    let preStartSet = Set(1..<clampedStart)
    let validNoteSet = Set((note ?? []).filter { $0 >= 1 && $0 <= total })
    let lack = max(lackEpisode ?? 0, 0)
    let acquiredFromLack = min(max(total - lack, 0), total)

    if isBestVersion {
      let completed = min(max(completedEpisode ?? 0, 0), total)
      let acquired = min(max(max(acquiredFromLack, completed), 0), total)
      let rawStates = buildWashEpisodeStates(
        total: total,
        completed: completed,
        acquired: acquired,
        preStartSet: preStartSet,
        noteSet: validNoteSet,
        isBestVersionFull: isBestVersionFull,
        currentPriority: currentPriority,
        episodePriority: episodePriority
      )
      let (ticks, isExact) = foldTicks(rawStates)
      let summary: String
      let detail: String?
      if completed >= total {
        summary = "洗版完成 \(total) / \(total) 集"
        detail = nil
      } else if completed == 0 && acquired == 0 {
        summary = "待洗版 · 共 \(total) 集"
        detail = nil
      } else {
        summary = "洗版 \(completed) / \(total) 集"
        if acquired > completed {
          detail = "已有 \(acquired) 集"
        } else {
          detail = "待洗 \(total - completed) 集"
        }
      }
      return SubscribeProgressProjection(
        isBestVersion: true,
        unit: .episode,
        total: total,
        completed: completed,
        acquired: acquired,
        ticks: ticks,
        isExactPerUnit: isExact,
        missingNumbers: [],
        summaryText: summary,
        detailText: detail
      )
    }

    let completed = min(max(completedEpisode ?? acquiredFromLack, 0), total)
    let knownCollected = preStartSet.union(validNoteSet)
    let exactDistribution = (knownCollected.count == completed)
    let rawStates = buildOrdinaryEpisodeStates(
      total: total,
      completed: completed,
      knownCollected: knownCollected,
      exactDistribution: exactDistribution
    )
    let missingNumbers: [Int]
    if exactDistribution && completed > 0 && completed < total {
      missingNumbers = (1...total).filter { !knownCollected.contains($0) }
    } else {
      missingNumbers = []
    }
    let (ticks, isExact) = foldTicks(rawStates)

    let summary: String
    let detail: String?
    if completed == 0 {
      summary = "待更新 · 共 \(total) 集"
      detail = nil
    } else if completed >= total {
      summary = "已收齐 \(total) / \(total) 集"
      detail = nil
    } else {
      summary = "已收 \(completed) / \(total) 集"
      detail = formatMissingDetail(
        missingCount: total - completed,
        missingNumbers: missingNumbers,
        highestCollected: knownCollected.max()
      )
    }

    return SubscribeProgressProjection(
      isBestVersion: false,
      unit: .episode,
      total: total,
      completed: completed,
      acquired: completed,
      ticks: ticks,
      isExactPerUnit: isExact,
      missingNumbers: missingNumbers,
      summaryText: summary,
      detailText: detail
    )
  }

  /// 构建音乐专辑订阅的离散曲目刻度投影。
  private static func makeTrackProjection(
    total: Int,
    completedTracks: Int?
  ) -> SubscribeProgressProjection {
    let completed = min(max(completedTracks ?? 0, 0), total)
    let rawStates = (1...total).map { index in
      index <= completed ? SubscribeTickState.complete : .empty
    }
    let (ticks, isExact) = foldTicks(rawStates)
    let summary: String
    let detail: String?
    if completed == 0 {
      summary = "待更新 · 共 \(total) 首"
      detail = nil
    } else if completed >= total {
      summary = "已收齐 \(total) / \(total) 首"
      detail = nil
    } else {
      summary = "已收 \(completed) / \(total) 首"
      detail = "缺 \(total - completed) 首"
    }
    return SubscribeProgressProjection(
      isBestVersion: false,
      unit: .track,
      total: total,
      completed: completed,
      acquired: completed,
      ticks: ticks,
      isExactPerUnit: isExact,
      missingNumbers: [],
      summaryText: summary,
      detailText: detail
    )
  }

  /// 为普通电视剧构建逐集状态：精确命中 `note` 时保留跳集缺口，否则按顺序补足库内既有集。
  private static func buildOrdinaryEpisodeStates(
    total: Int,
    completed: Int,
    knownCollected: Set<Int>,
    exactDistribution: Bool
  ) -> [SubscribeTickState] {
    guard completed > 0 else {
      return Array(repeating: .empty, count: total)
    }
    if completed >= total {
      return Array(repeating: .complete, count: total)
    }
    if exactDistribution {
      return (1...total).map { knownCollected.contains($0) ? .complete : .empty }
    }
    if knownCollected.count < completed {
      var filled = knownCollected
      var remaining = completed - filled.count
      for episode in 1...total where remaining > 0 {
        if filled.insert(episode).inserted {
          remaining -= 1
        }
      }
      return (1...total).map { filled.contains($0) ? .complete : .empty }
    }
    return (1...total).map { $0 <= completed ? .complete : .empty }
  }

  /// 为洗版电视剧构建逐集状态（已达标 `.complete`、已有初版 `.partial`、未获取 `.empty`）。
  private static func buildWashEpisodeStates(
    total: Int,
    completed: Int,
    acquired: Int,
    preStartSet: Set<Int>,
    noteSet: Set<Int>,
    isBestVersionFull: Bool,
    currentPriority: Int?,
    episodePriority: [String: Int]?
  ) -> [SubscribeTickState] {
    var parsedPriority: [Int: Int] = [:]
    if let episodePriority {
      for (key, value) in episodePriority {
        if let ep = Int(key), ep >= 1, ep <= total {
          parsedPriority[ep] = value
        }
      }
    }

    var upgradedCandidates = preStartSet
    if isBestVersionFull && currentPriority == 100 {
      upgradedCandidates = Set(1...total)
    } else {
      for (ep, priority) in parsedPriority where priority == 100 {
        upgradedCandidates.insert(ep)
      }
    }

    var states = Array(repeating: SubscribeTickState.empty, count: total)
    if completed >= total {
      return Array(repeating: .complete, count: total)
    }
    if completed > 0 {
      if upgradedCandidates.count == completed {
        for ep in upgradedCandidates {
          states[ep - 1] = .complete
        }
      } else {
        for ep in 1...completed {
          states[ep - 1] = .complete
        }
      }
    }

    var needPartial = max(acquired - completed, 0)
    if needPartial > 0 {
      var partialCandidates = Set(parsedPriority.keys).union(noteSet)
      partialCandidates = partialCandidates.filter { states[$0 - 1] == .empty }
      for ep in partialCandidates.sorted() where needPartial > 0 {
        states[ep - 1] = .partial
        needPartial -= 1
      }
      for ep in 1...total where needPartial > 0 {
        if states[ep - 1] == .empty {
          states[ep - 1] = .partial
          needPartial -= 1
        }
      }
    }

    return states
  }

  /// 集数不超过 24 时保持 1:1 逐集刻度；超过 24 时按等比区间聚合，同时保留区间内部分进度。
  private static func foldTicks(_ rawStates: [SubscribeTickState]) -> ([SubscribeTickState], Bool) {
    let total = rawStates.count
    guard total > maxExactTickCount else {
      return (rawStates, true)
    }
    let bucketCount: Int
    if total <= 40 && total.isMultiple(of: 2) {
      bucketCount = total / 2
    } else {
      bucketCount = defaultBucketCount
    }
    var folded: [SubscribeTickState] = []
    folded.reserveCapacity(bucketCount)
    for bucket in 0..<bucketCount {
      let start = bucket * total / bucketCount
      let end = max(start + 1, (bucket + 1) * total / bucketCount)
      let slice = rawStates[start..<min(end, total)]
      if slice.allSatisfy({ $0 == .complete }) {
        folded.append(.complete)
      } else if slice.allSatisfy({ $0 == .empty }) {
        folded.append(.empty)
      } else {
        folded.append(.partial)
      }
    }
    return (folded, false)
  }

  /// 生成右侧缺集提示文案：少量精确缺集直接列集号，存在跳集漏缺时点出漏集。
  private static func formatMissingDetail(
    missingCount: Int,
    missingNumbers: [Int],
    highestCollected: Int?
  ) -> String? {
    guard missingCount > 0 else { return nil }
    if !missingNumbers.isEmpty {
      if missingNumbers.count <= 3 {
        let joined = missingNumbers.map(formatEpisodeCode).joined(separator: ", ")
        return "缺 \(joined)"
      }
      if let highestCollected {
        let internalGaps = missingNumbers.filter { $0 < highestCollected }
        if !internalGaps.isEmpty {
          let preview = internalGaps.prefix(2).map(formatEpisodeCode).joined(separator: ", ")
          return "缺 \(preview) 等 \(missingCount) 集"
        }
      }
    }
    return "缺 \(missingCount) 集"
  }

  /// 格式化单集短码（如 `E04`、`E12`、`E108`）。
  private static func formatEpisodeCode(_ episode: Int) -> String {
    episode < 100 ? String(format: "E%02d", episode) : "E\(episode)"
  }
}
