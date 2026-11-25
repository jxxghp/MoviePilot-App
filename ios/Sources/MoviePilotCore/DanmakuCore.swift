import Foundation

/// 弹幕显示模式（与后端及 Rust `mp-core-model::DanmakuMode` 1:1 对齐）。
public enum DanmakuMode: Int, Codable, Sendable, Equatable, Hashable {
  case scroll = 1
  case bottom = 4
  case top = 5

  public init(code: Int) {
    switch code {
    case 4: self = .bottom
    case 5: self = .top
    default: self = .scroll
    }
  }
}

/// 经过滤、去重与排序后的单条可渲染弹幕。
public struct DanmakuItem: Codable, Sendable, Equatable {
  public let timeMs: Int64
  public let mode: DanmakuMode
  public let colorRgb: UInt32
  public let text: String
  public var repeatCount: UInt32

  public init(
    timeMs: Int64,
    mode: DanmakuMode,
    colorRgb: UInt32,
    text: String,
    repeatCount: UInt32 = 1
  ) {
    self.timeMs = timeMs
    self.mode = mode
    self.colorRgb = colorRgb
    self.text = text
    self.repeatCount = repeatCount
  }

  private enum CodingKeys: String, CodingKey {
    case timeMs = "time_ms"
    case mode
    case colorRgb = "color_rgb"
    case text
    case repeatCount = "repeat_count"
  }
}

/// 跨端统一的弹幕过滤与限流参数（与 Rust `DanmakuFilterOptions` 字段一致）。
public struct DanmakuFilterOptions: Codable, Sendable, Equatable {
  public var allowScroll: Bool
  public var allowTop: Bool
  public var allowBottom: Bool
  public var allowColor: Bool
  public var mergeDuplicates: Bool
  public var mergeWindowMs: Int64
  public var maxPerSecond: UInt32
  public var blockKeywords: [String]
  public var offsetMs: Int64

  public init(
    allowScroll: Bool = true,
    allowTop: Bool = true,
    allowBottom: Bool = true,
    allowColor: Bool = true,
    mergeDuplicates: Bool = true,
    mergeWindowMs: Int64 = 3000,
    maxPerSecond: UInt32 = 12,
    blockKeywords: [String] = [],
    offsetMs: Int64 = 0
  ) {
    self.allowScroll = allowScroll
    self.allowTop = allowTop
    self.allowBottom = allowBottom
    self.allowColor = allowColor
    self.mergeDuplicates = mergeDuplicates
    self.mergeWindowMs = mergeWindowMs
    self.maxPerSecond = maxPerSecond
    self.blockKeywords = blockKeywords
    self.offsetMs = offsetMs
  }

  private enum CodingKeys: String, CodingKey {
    case allowScroll = "allow_scroll"
    case allowTop = "allow_top"
    case allowBottom = "allow_bottom"
    case allowColor = "allow_color"
    case mergeDuplicates = "merge_duplicates"
    case mergeWindowMs = "merge_window_ms"
    case maxPerSecond = "max_per_second"
    case blockKeywords = "block_keywords"
    case offsetMs = "offset_ms"
  }
}

/// 离线批处理后的弹幕时间线与统计摘要。
public struct PreparedDanmakuTimeline: Codable, Sendable, Equatable {
  public let rawCount: Int
  public let filteredCount: Int
  public let items: [DanmakuItem]

  public init(rawCount: Int, filteredCount: Int, items: [DanmakuItem]) {
    self.rawCount = rawCount
    self.filteredCount = filteredCount
    self.items = items
  }

  private enum CodingKeys: String, CodingKey {
    case rawCount = "raw_count"
    case filteredCount = "filtered_count"
    case items
  }
}

/// 跨端同构的纯 Swift 弹幕离线解析、过滤、短窗重复合并、每秒限流与标题规范化内核。
public enum DanmakuTimelineProcessor {
  private static let whiteRGB: UInt32 = 0x00FF_FFFF
  private static let maxPatternChars = 128
  private static let maxTextChars = 300

  private struct RawEntry {
    let timeMs: Int64
    let mode: DanmakuMode
    let colorRgb: UInt32
    let text: String
  }

  private enum BlockRule {
    case substring(String)
    case safePattern([PatternBranch])

    static func parse(_ raw: String) -> BlockRule? {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      let limited = String(trimmed.prefix(maxPatternChars))
      if limited.count >= 2, limited.hasPrefix("/"), limited.hasSuffix("/") {
        let inner = String(limited.dropFirst().dropLast())
        guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let branches: [PatternBranch] = inner.split(separator: "|").compactMap { rawBranch in
          var body = rawBranch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          guard !body.isEmpty else { return nil }
          let anchorStart = body.hasPrefix("^")
          if anchorStart { body.removeFirst() }
          let anchorEnd = body.hasSuffix("$")
          if anchorEnd, !body.isEmpty { body.removeLast() }
          let normalized = body.replacingOccurrences(of: ".*", with: "*")
          let segments = normalized.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
          guard segments.contains(where: { !$0.isEmpty }) else { return nil }
          return PatternBranch(anchorStart: anchorStart, anchorEnd: anchorEnd, segments: segments)
        }
        return branches.isEmpty ? nil : .safePattern(branches)
      }
      return .substring(limited.lowercased())
    }

    func matches(_ lowerText: String) -> Bool {
      switch self {
      case .substring(let needle):
        return lowerText.contains(needle)
      case .safePattern(let branches):
        return branches.contains { $0.matches(lowerText) }
      }
    }
  }

  private struct PatternBranch {
    let anchorStart: Bool
    let anchorEnd: Bool
    let segments: [String]

    func matches(_ text: String) -> Bool {
      if segments.count == 1 {
        let seg = segments[0]
        switch (anchorStart, anchorEnd) {
        case (true, true): return text == seg
        case (true, false): return text.hasPrefix(seg)
        case (false, true): return text.hasSuffix(seg)
        case (false, false): return text.contains(seg)
        }
      }
      var cursor = text.startIndex
      let lastIdx = segments.count - 1
      for (idx, seg) in segments.enumerated() where !seg.isEmpty {
        if idx == 0 && anchorStart {
          guard text.hasPrefix(seg) else { return false }
          cursor = text.index(text.startIndex, offsetBy: seg.count)
        } else if idx == lastIdx && anchorEnd {
          guard text[cursor...].hasSuffix(seg) else { return false }
          cursor = text.endIndex
        } else if let range = text[cursor...].range(of: seg) {
          cursor = range.upperBound
        } else {
          return false
        }
      }
      return true
    }
  }

  /// 解析紧凑 JSON / 弹弹play 原始 JSON / B 站 XML 并应用过滤、短窗重复合并与每秒限流。
  public static func prepare(
    rawPayload: String,
    options: DanmakuFilterOptions = DanmakuFilterOptions()
  ) -> PreparedDanmakuTimeline {
    let trimmed = rawPayload
      .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return PreparedDanmakuTimeline(rawCount: 0, filteredCount: 0, items: [])
    }
    let rawEntries: [RawEntry] =
      trimmed.hasPrefix("<") ? parseXMLEntries(trimmed) : parseJSONEntries(trimmed)
    let rawCount = rawEntries.count
    let rules = options.blockKeywords.compactMap(BlockRule.parse)

    var filtered: [DanmakuItem] = []
    filtered.reserveCapacity(rawCount)
    for entry in rawEntries {
      let adjustedTime = entry.timeMs &+ options.offsetMs
      guard adjustedTime >= 0 else { continue }
      let allowed: Bool
      switch entry.mode {
      case .scroll: allowed = options.allowScroll
      case .top: allowed = options.allowTop
      case .bottom: allowed = options.allowBottom
      }
      guard allowed else { continue }
      if !rules.isEmpty {
        let lower = entry.text.lowercased()
        if rules.contains(where: { $0.matches(lower) }) { continue }
      }
      filtered.append(
        DanmakuItem(
          timeMs: adjustedTime,
          mode: entry.mode,
          colorRgb: options.allowColor ? entry.colorRgb : whiteRGB,
          text: entry.text,
          repeatCount: 1
        )
      )
    }

    // 稳定排序（保留同毫秒原始顺序）
    let sorted = filtered.enumerated().sorted { lhs, rhs in
      if lhs.element.timeMs != rhs.element.timeMs {
        return lhs.element.timeMs < rhs.element.timeMs
      }
      return lhs.offset < rhs.offset
    }.map(\.element)

    let merged: [DanmakuItem]
    if options.mergeDuplicates && options.mergeWindowMs > 0 {
      merged = mergeShortWindowDuplicates(sorted, windowMs: options.mergeWindowMs)
    } else {
      merged = sorted
    }

    let throttled: [DanmakuItem]
    if options.maxPerSecond > 0 {
      throttled = throttlePerSecond(merged, maxPerSecond: Int(options.maxPerSecond))
    } else {
      throttled = merged
    }

    return PreparedDanmakuTimeline(
      rawCount: rawCount,
      filteredCount: throttled.count,
      items: throttled
    )
  }

  /// 跨端统一规范化手动搜索弹幕的默认关键词。
  public static func normalizeQueryTitle(
    seriesName: String?,
    title: String?,
    season: Int?,
    episode: Int?,
    fileName: String?
  ) -> String {
    _ = episode
    if let series = seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !series.isEmpty {
      let base = stripFilenameNoise(series)
      if !base.isEmpty {
        if let season, season > 1,
          !base.contains("第\(season)季"),
          !base.lowercased().contains("season \(season)")
        {
          return "\(base) 第\(season)季"
        }
        return base
      }
    }
    if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
      let cleaned = stripFilenameNoise(title)
      if !cleaned.isEmpty { return cleaned }
    }
    if let fileName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !fileName.isEmpty {
      let basename = fileName.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? fileName
      let cleaned = stripFilenameNoise(basename)
      if !cleaned.isEmpty { return cleaned }
    }
    return ""
  }

  private struct MergeKey: Hashable {
    let lowerText: String
    let mode: DanmakuMode
  }

  private static func mergeShortWindowDuplicates(_ items: [DanmakuItem], windowMs: Int64)
    -> [DanmakuItem]
  {
    var out: [DanmakuItem] = []
    out.reserveCapacity(items.count)
    var lastSeen: [MergeKey: Int] = [:]
    for item in items {
      let key = MergeKey(lowerText: item.text.lowercased(), mode: item.mode)
      if let idx = lastSeen[key], item.timeMs - out[idx].timeMs <= windowMs {
        out[idx].repeatCount = out[idx].repeatCount &+ 1
        continue
      }
      lastSeen[key] = out.count
      out.append(item)
    }
    return out
  }

  private static func throttlePerSecond(_ items: [DanmakuItem], maxPerSecond: Int) -> [DanmakuItem] {
    guard !items.isEmpty, maxPerSecond > 0 else { return items }
    var out: [DanmakuItem] = []
    out.reserveCapacity(items.count)
    var start = 0
    while start < items.count {
      let secBucket = items[start].timeMs / 1000
      var end = start + 1
      while end < items.count && items[end].timeMs / 1000 == secBucket {
        end += 1
      }
      if end - start <= maxPerSecond {
        out.append(contentsOf: items[start..<end])
      } else {
        var indices = Array(start..<end)
        indices.sort { a, b in
          if items[a].repeatCount != items[b].repeatCount {
            return items[a].repeatCount > items[b].repeatCount
          }
          return a < b
        }
        let kept = indices.prefix(maxPerSecond).sorted()
        for idx in kept {
          out.append(items[idx])
        }
      }
      start = end
    }
    return out
  }

  private static func cleanText(_ raw: String) -> String {
    var out = ""
    out.reserveCapacity(min(raw.count, maxTextChars))
    for scalar in raw.unicodeScalars {
      if scalar == "\r" || scalar == "\n" || scalar == "\t" {
        out.append(" ")
      } else if scalar.value >= 0x20 && scalar.value != 0x7F {
        out.unicodeScalars.append(scalar)
      }
      if out.count >= maxTextChars { break }
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizeColor(_ raw: Int) -> UInt32 {
    (0...Int(whiteRGB)).contains(raw) ? UInt32(raw) : whiteRGB
  }

  private static func parseJSONEntries(_ raw: String) -> [RawEntry] {
    guard let data = raw.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data)
    else { return [] }
    let list: [Any]
    if let arr = json as? [Any] {
      list = arr
    } else if let dict = json as? [String: Any] {
      if let dataDict = dict["data"] as? [String: Any], let items = dataDict["items"] as? [Any] {
        list = items
      } else if let items = dict["items"] as? [Any] {
        list = items
      } else if let comments = dict["comments"] as? [Any] {
        list = comments
      } else {
        return []
      }
    } else {
      return []
    }

    var entries: [RawEntry] = []
    entries.reserveCapacity(list.count)
    for element in list {
      if let arr = element as? [Any], arr.count >= 4,
        let timeMs = int64Value(arr[0]),
        let textRaw = arr[3] as? String
      {
        let text = cleanText(textRaw)
        guard !text.isEmpty else { continue }
        let modeCode = intValue(arr[1]) ?? 1
        let colorVal = intValue(arr[2]) ?? Int(whiteRGB)
        entries.append(
          RawEntry(
            timeMs: timeMs,
            mode: DanmakuMode(code: modeCode),
            colorRgb: normalizeColor(colorVal),
            text: text
          ))
      } else if let obj = element as? [String: Any] {
        if let pStr = obj["p"] as? String,
          let mStr = (obj["m"] as? String) ?? (obj["text"] as? String)
        {
          let parts = pStr.split(separator: ",")
          guard parts.count >= 3,
            let sec = Double(parts[0].trimmingCharacters(in: .whitespaces)), sec.isFinite,
            let modeVal = Double(parts[1].trimmingCharacters(in: .whitespaces)),
            let colorVal = Double(parts[2].trimmingCharacters(in: .whitespaces))
          else { continue }
          let text = cleanText(mStr)
          guard !text.isEmpty else { continue }
          entries.append(
            RawEntry(
              timeMs: Int64((sec * 1000.0).rounded()),
              mode: DanmakuMode(code: Int(modeVal)),
              colorRgb: normalizeColor(Int(colorVal)),
              text: text
            ))
        } else if let timeMs = int64Value(obj["time_ms"]),
          let rawText = obj["text"] as? String
        {
          let text = cleanText(rawText)
          guard !text.isEmpty else { continue }
          let modeCode = intValue(obj["mode"]) ?? 1
          let colorVal = intValue(obj["color_rgb"]) ?? Int(whiteRGB)
          entries.append(
            RawEntry(
              timeMs: timeMs,
              mode: DanmakuMode(code: modeCode),
              colorRgb: normalizeColor(colorVal),
              text: text
            ))
        }
      }
    }
    return entries
  }

  private static func parseXMLEntries(_ raw: String) -> [RawEntry] {
    guard
      let regex = try? NSRegularExpression(
        pattern: #"<d\s+[^>]*p=["']([^"']+)["'][^>]*>(.*?)</d>"#,
        options: [.dotMatchesLineSeparators, .caseInsensitive]
      )
    else { return [] }
    let ns = raw as NSString
    let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
    var entries: [RawEntry] = []
    entries.reserveCapacity(matches.count)
    for match in matches where match.numberOfRanges >= 3 {
      let pAttr = ns.substring(with: match.range(at: 1))
      let bodyRaw = decodeXMLEntities(ns.substring(with: match.range(at: 2)))
      let text = cleanText(bodyRaw)
      guard !text.isEmpty else { continue }
      let parts = pAttr.split(separator: ",")
      guard parts.count >= 4,
        let sec = Double(parts[0].trimmingCharacters(in: .whitespaces)), sec.isFinite,
        let modeVal = Double(parts[1].trimmingCharacters(in: .whitespaces)),
        let colorVal = Double(parts[3].trimmingCharacters(in: .whitespaces))
      else { continue }
      entries.append(
        RawEntry(
          timeMs: Int64((sec * 1000.0).rounded()),
          mode: DanmakuMode(code: Int(modeVal)),
          colorRgb: normalizeColor(Int(colorVal)),
          text: text
        ))
    }
    return entries
  }

  private static func decodeXMLEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    return text
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&amp;", with: "&")
  }

  private static func intValue(_ any: Any?) -> Int? {
    if let v = any as? Int { return v }
    if let v = any as? Int64 { return Int(v) }
    if let v = any as? Double, v.isFinite { return Int(v.rounded()) }
    if let v = any as? NSNumber { return v.intValue }
    return nil
  }

  private static func int64Value(_ any: Any?) -> Int64? {
    if let v = any as? Int64 { return v }
    if let v = any as? Int { return Int64(v) }
    if let v = any as? Double, v.isFinite { return Int64(v.rounded()) }
    if let v = any as? NSNumber { return v.int64Value }
    return nil
  }

  private static func stripFilenameNoise(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let exts = [".mkv", ".mp4", ".avi", ".mov", ".m4v", ".ts", ".m2ts", ".flv", ".webm", ".strm", ".iso"]
    for ext in exts where s.count > ext.count && s.lowercased().hasSuffix(ext) {
      s = String(s.dropLast(ext.count))
      break
    }
    var noBrackets = ""
    var depthSq = 0
    var depthFull = 0
    for ch in s {
      switch ch {
      case "[": depthSq += 1
      case "]": depthSq = max(0, depthSq - 1)
      case "【": depthFull += 1
      case "】": depthFull = max(0, depthFull - 1)
      default:
        if depthSq == 0 && depthFull == 0 { noBrackets.append(ch) }
      }
    }
    let replaced = noBrackets
      .replacingOccurrences(of: ".", with: " ")
      .replacingOccurrences(of: "_", with: " ")
    let releaseTokens: Set<String> = [
      "1080P", "2160P", "720P", "4K", "UHD", "HDR", "HDR10", "DV",
      "BLURAY", "BDRIP", "WEB-DL", "WEBDL", "WEBRIP", "REMUX",
      "X264", "X265", "H264", "H265", "HEVC", "AV1", "AAC", "FLAC", "DDP",
    ]
    var kept: [String] = []
    for rawTok in replaced.split(whereSeparator: \.isWhitespace) {
      let tok = String(rawTok)
      let upper = tok.uppercased()
      let isSeasonEp =
        upper.hasPrefix("S")
        && upper.contains("E")
        && upper.dropFirst().split(separator: "E").count == 2
        && upper.dropFirst().split(separator: "E").allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
      if releaseTokens.contains(upper) || isSeasonEp {
        if !kept.isEmpty { break }
        continue
      }
      kept.append(tok)
    }
    let joined = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return joined.isEmpty ? s.trimmingCharacters(in: .whitespacesAndNewlines) : joined
  }
}
