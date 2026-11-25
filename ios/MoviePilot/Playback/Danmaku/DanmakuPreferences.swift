import Foundation
import MoviePilotCore

/// iOS 端弹幕本地渲染偏好存储（与跨端 `danmaku-support-design.md` §4.1 键义和默认值完全一致）。
@MainActor
final class DanmakuPreferencesStore: ObservableObject {
  static let shared = DanmakuPreferencesStore()

  private enum Keys {
    static let enabled = "nativeV2.playback.danmaku.enabled"
    static let opacity = "nativeV2.playback.danmaku.opacity"
    static let fontScale = "nativeV2.playback.danmaku.fontScale"
    static let speed = "nativeV2.playback.danmaku.speed"
    static let areaRatio = "nativeV2.playback.danmaku.areaRatio"
    static let maxOnScreen = "nativeV2.playback.danmaku.maxOnScreen"
    static let allowScroll = "nativeV2.playback.danmaku.allowScroll"
    static let allowTop = "nativeV2.playback.danmaku.allowTop"
    static let allowBottom = "nativeV2.playback.danmaku.allowBottom"
    static let allowColor = "nativeV2.playback.danmaku.allowColor"
    static let mergeDuplicates = "nativeV2.playback.danmaku.mergeDuplicates"
    static let blockKeywords = "nativeV2.playback.danmaku.blockKeywords"
  }

  private let defaults: UserDefaults

  @Published var enabled: Bool {
    didSet { defaults.set(enabled, forKey: Keys.enabled) }
  }
  @Published var opacity: Double {
    didSet { defaults.set(opacity, forKey: Keys.opacity) }
  }
  @Published var fontScale: Double {
    didSet { defaults.set(fontScale, forKey: Keys.fontScale) }
  }
  @Published var speed: Double {
    didSet { defaults.set(speed, forKey: Keys.speed) }
  }
  @Published var areaRatio: Double {
    didSet { defaults.set(areaRatio, forKey: Keys.areaRatio) }
  }
  @Published var maxOnScreen: Int {
    didSet { defaults.set(maxOnScreen, forKey: Keys.maxOnScreen) }
  }
  @Published var allowScroll: Bool {
    didSet { defaults.set(allowScroll, forKey: Keys.allowScroll) }
  }
  @Published var allowTop: Bool {
    didSet { defaults.set(allowTop, forKey: Keys.allowTop) }
  }
  @Published var allowBottom: Bool {
    didSet { defaults.set(allowBottom, forKey: Keys.allowBottom) }
  }
  @Published var allowColor: Bool {
    didSet { defaults.set(allowColor, forKey: Keys.allowColor) }
  }
  @Published var mergeDuplicates: Bool {
    didSet { defaults.set(mergeDuplicates, forKey: Keys.mergeDuplicates) }
  }
  @Published var blockKeywords: [String] {
    didSet { defaults.set(blockKeywords, forKey: Keys.blockKeywords) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
    let savedOpacity = defaults.object(forKey: Keys.opacity) as? Double ?? 0.85
    self.opacity = min(1.0, max(0.2, savedOpacity))
    let savedFontScale = defaults.object(forKey: Keys.fontScale) as? Double ?? 1.0
    self.fontScale = min(1.5, max(0.75, savedFontScale))
    let savedSpeed = defaults.object(forKey: Keys.speed) as? Double ?? 1.0
    self.speed = min(1.6, max(0.6, savedSpeed))
    let savedArea = defaults.object(forKey: Keys.areaRatio) as? Double ?? 0.5
    self.areaRatio = [0.25, 0.5, 0.75, 1.0].contains(savedArea) ? savedArea : 0.5
    let savedMax = defaults.object(forKey: Keys.maxOnScreen) as? Int ?? 40
    self.maxOnScreen = [20, 40, 60, 100].contains(savedMax) ? savedMax : 40
    self.allowScroll = defaults.object(forKey: Keys.allowScroll) as? Bool ?? true
    self.allowTop = defaults.object(forKey: Keys.allowTop) as? Bool ?? true
    self.allowBottom = defaults.object(forKey: Keys.allowBottom) as? Bool ?? true
    self.allowColor = defaults.object(forKey: Keys.allowColor) as? Bool ?? true
    self.mergeDuplicates = defaults.object(forKey: Keys.mergeDuplicates) as? Bool ?? true
    self.blockKeywords = defaults.stringArray(forKey: Keys.blockKeywords) ?? []
  }

  func makeFilterOptions(offsetMs: Int64) -> DanmakuFilterOptions {
    DanmakuFilterOptions(
      allowScroll: allowScroll,
      allowTop: allowTop,
      allowBottom: allowBottom,
      allowColor: allowColor,
      mergeDuplicates: mergeDuplicates,
      mergeWindowMs: 3000,
      maxPerSecond: 12,
      blockKeywords: blockKeywords,
      offsetMs: offsetMs
    )
  }

  func addBlockKeyword(_ keyword: String) {
    let cleaned = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty, !blockKeywords.contains(cleaned) else { return }
    blockKeywords.append(cleaned)
  }

  func removeBlockKeyword(_ keyword: String) {
    blockKeywords.removeAll { $0 == keyword }
  }
}
