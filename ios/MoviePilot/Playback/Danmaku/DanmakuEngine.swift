import CoreGraphics
import Foundation
import MoviePilotCore

/// 屏幕上正在活跃渲染的单条弹幕实例状态。
struct ActiveDanmakuSlot {
  let id: UInt64
  let item: DanmakuItem
  let displayText: String
  let trackIndex: Int
  var x: CGFloat
  let y: CGFloat
  let width: CGFloat
  let height: CGFloat
  let speedPxPerSec: CGFloat
  var remainingSec: CGFloat
}

/// 跨端统一轨道防碰撞弹幕调度器（与 `danmaku-support-design.md` §5.1 数学模型严格一致）。
@MainActor
final class DanmakuEngine {
  private(set) var items: [DanmakuItem] = []
  private(set) var activeSlots: [ActiveDanmakuSlot] = []
  private var nextIndex: Int = 0
  private var nextSlotID: UInt64 = 1

  private var clockMs: Double = 0
  private var isPlaying: Bool = false
  private var playbackRate: Double = 1.0
  private var viewportSize: CGSize = .zero
  private var topSafePadding: CGFloat = 12

  private var scrollTrackCount: Int = 6
  private var fixedTrackCount: Int = 4
  private var rowHeight: CGFloat = 28
  private var baseFontSize: CGFloat = 18

  // 渲染参数
  var opacity: Double = 0.85
  var fontScale: Double = 1.0 { didSet { recalculateTracks() } }
  var userSpeed: Double = 1.0
  var areaRatio: Double = 0.5 { didSet { recalculateTracks() } }
  var maxOnScreen: Int = 40

  private static let baseScrollDurationSec: CGFloat = 7.5
  private static let fixedDurationSec: CGFloat = 4.2
  private static let horizontalGap: CGFloat = 24
  private static let driftResetThresholdMs: Double = 350

  var effectiveFontSize: CGFloat {
    max(12, min(36, baseFontSize * CGFloat(fontScale)))
  }

  /// 替换已由离线处理器排序过滤后的弹幕时间线，并定位游标到当前播放位置。
  func load(items: [DanmakuItem], currentPositionMs: Int) {
    self.items = items
    resetTo(positionMs: currentPositionMs)
  }

  /// 清空全部时间线与在屏弹幕（用于切集或关闭）。
  func clearAll() {
    items.removeAll()
    activeSlots.removeAll()
    nextIndex = 0
  }

  /// 更新视口尺寸与顶部安全区（支持横竖屏切换、分屏与 iPad 窗口缩放）。
  func updateViewport(size: CGSize, topSafePadding: CGFloat) {
    guard size.width > 0, size.height > 0 else { return }
    let changed = abs(size.width - viewportSize.width) > 1 || abs(size.height - viewportSize.height) > 1
    viewportSize = size
    self.topSafePadding = max(8, topSafePadding)
    if changed {
      recalculateTracks()
      // 窗口尺寸剧变时丢弃可能越界的旧轨道，避免叠字
      activeSlots.removeAll { slot in
        slot.y + slot.height > size.height || slot.trackIndex >= max(scrollTrackCount, fixedTrackCount)
      }
    }
  }

  /// 同步播放器实时时钟；当偏差超过 350ms（Seek / 缓冲恢复 / 切核）时清空在屏并二分重置游标。
  func syncPlayerClock(positionMs: Int, isPlaying: Bool, playbackRate: Double) {
    let targetMs = Double(max(0, positionMs))
    self.isPlaying = isPlaying
    self.playbackRate = max(0.25, min(4.0, playbackRate))
    if abs(targetMs - clockMs) > Self.driftResetThresholdMs {
      resetTo(positionMs: positionMs)
    }
  }

  /// 强制二分重置到指定毫秒位置（Seek / 偏移变更 / 重新加载）。
  func resetTo(positionMs: Int) {
    let target = Int64(max(0, positionMs))
    clockMs = Double(target)
    activeSlots.removeAll()
    nextIndex = lowerBoundIndex(for: target)
  }

  /// 推进一帧动画：更新现有弹幕位移、淘汰离屏条目，并按防追尾碰撞规则发射到达当前时刻的新弹幕。
  func step(dt: TimeInterval, measureText: (String, CGFloat) -> CGSize) {
    guard isPlaying, viewportSize.width > 0, viewportSize.height > 0 else { return }
    let clampedDt = min(max(dt, 0), 0.1)
    let scaledDt = clampedDt * playbackRate
    clockMs += scaledDt * 1000.0

    // 1. 推进在屏弹幕并回收过期条目
    var kept: [ActiveDanmakuSlot] = []
    kept.reserveCapacity(activeSlots.count)
    for var slot in activeSlots {
      if slot.item.mode == .scroll {
        slot.x -= slot.speedPxPerSec * CGFloat(scaledDt)
        if slot.x + slot.width > -8 {
          kept.append(slot)
        }
      } else {
        slot.remainingSec -= CGFloat(scaledDt)
        if slot.remainingSec > 0 {
          kept.append(slot)
        }
      }
    }
    activeSlots = kept

    // 2. 发射到达当前时间窗口的弹幕（避免单帧积压过多）
    let currentMs = Int64(clockMs)
    var spawnedThisFrame = 0
    while nextIndex < items.count {
      let item = items[nextIndex]
      if item.timeMs > currentMs {
        break
      }
      nextIndex += 1
      // 跳过已经远滞后于当前时刻（> 1.5s）的陈旧弹幕
      if currentMs - item.timeMs > 1500 {
        continue
      }
      if activeSlots.count >= maxOnScreen || spawnedThisFrame >= 8 {
        continue
      }
      if spawn(item: item, measureText: measureText) {
        spawnedThisFrame += 1
      }
    }
  }

  private func spawn(item: DanmakuItem, measureText: (String, CGFloat) -> CGSize) -> Bool {
    let displayText = item.repeatCount > 1 ? "\(item.text) ×\(item.repeatCount)" : item.text
    let fontSize = effectiveFontSize
    let measured = measureText(displayText, fontSize)
    let width = ceil(measured.width) + 6
    let height = max(ceil(measured.height) + 4, rowHeight * 0.92)
    let vw = viewportSize.width

    switch item.mode {
    case .scroll:
      let speed =
        ((vw + width) / Self.baseScrollDurationSec) * CGFloat(userSpeed) * CGFloat(playbackRate)
      guard speed > 1 else { return false }
      guard let track = findAvailableScrollTrack(candSpeed: speed, viewportWidth: vw) else {
        return false
      }
      let y = topSafePadding + CGFloat(track) * rowHeight
      activeSlots.append(
        ActiveDanmakuSlot(
          id: allocateID(),
          item: item,
          displayText: displayText,
          trackIndex: track,
          x: vw + 4,
          y: y,
          width: width,
          height: height,
          speedPxPerSec: speed,
          remainingSec: 0
        ))
      return true

    case .top:
      guard let track = findAvailableFixedTrack(mode: .top) else { return false }
      let y = topSafePadding + CGFloat(track) * rowHeight
      activeSlots.append(
        ActiveDanmakuSlot(
          id: allocateID(),
          item: item,
          displayText: displayText,
          trackIndex: track,
          x: max(8, (vw - width) * 0.5),
          y: y,
          width: width,
          height: height,
          speedPxPerSec: 0,
          remainingSec: Self.fixedDurationSec
        ))
      return true

    case .bottom:
      guard let track = findAvailableFixedTrack(mode: .bottom) else { return false }
      // 底部固定轨道自字幕安全区上方（预留 14% 底部高度）向上排布
      let bottomSafeLimit = viewportSize.height * 0.86
      let y = bottomSafeLimit - CGFloat(track + 1) * rowHeight
      guard y >= topSafePadding else { return false }
      activeSlots.append(
        ActiveDanmakuSlot(
          id: allocateID(),
          item: item,
          displayText: displayText,
          trackIndex: track,
          x: max(8, (vw - width) * 0.5),
          y: y,
          width: width,
          height: height,
          speedPxPerSec: 0,
          remainingSec: Self.fixedDurationSec
        ))
      return true
    }
  }

  /// 滚动弹幕双条件防追尾碰撞判定（入口不重叠 + 中途不追尾）。
  private func findAvailableScrollTrack(candSpeed: CGFloat, viewportWidth: CGFloat) -> Int? {
    for track in 0..<scrollTrackCount {
      var latest: ActiveDanmakuSlot?
      for slot in activeSlots where slot.item.mode == .scroll && slot.trackIndex == track {
        if let prev = latest {
          if slot.x + slot.width > prev.x + prev.width {
            latest = slot
          }
        } else {
          latest = slot
        }
      }
      guard let prev = latest else {
        return track
      }
      let prevRightX = prev.x + prev.width
      // 条件 1：前一条尾巴已完全进入画面并留出水平间距
      if prevRightX + Self.horizontalGap > viewportWidth {
        continue
      }
      // 条件 2：新弹幕车头在前一条离屏前不会追上其车尾
      let prevRemainSec = max(0, prevRightX) / max(1, prev.speedPxPerSec)
      if candSpeed * prevRemainSec > viewportWidth - Self.horizontalGap {
        continue
      }
      return track
    }
    return nil
  }

  private func findAvailableFixedTrack(mode: DanmakuMode) -> Int? {
    let limit = max(1, min(fixedTrackCount, scrollTrackCount))
    for track in 0..<limit {
      let occupied = activeSlots.contains { $0.item.mode == mode && $0.trackIndex == track }
      if !occupied { return track }
    }
    return nil
  }

  private func recalculateTracks() {
    let minSide = min(viewportSize.width, viewportSize.height)
    baseFontSize = minSide >= 650 ? 22 : (viewportSize.width > viewportSize.height ? 18 : 16)
    let font = effectiveFontSize
    rowHeight = max(20, font * 1.35)
    guard viewportSize.height > 0 else { return }
    let usableHeight = max(rowHeight, viewportSize.height * CGFloat(areaRatio) - topSafePadding)
    scrollTrackCount = max(1, Int(floor(usableHeight / rowHeight)))
    fixedTrackCount = max(1, min(6, scrollTrackCount))
  }

  private func lowerBoundIndex(for targetMs: Int64) -> Int {
    var low = 0
    var high = items.count
    while low < high {
      let mid = (low + high) >> 1
      if items[mid].timeMs < targetMs {
        low = mid + 1
      } else {
        high = mid
      }
    }
    return low
  }

  private func allocateID() -> UInt64 {
    let current = nextSlotID
    nextSlotID &+= 1
    return current
  }
}
