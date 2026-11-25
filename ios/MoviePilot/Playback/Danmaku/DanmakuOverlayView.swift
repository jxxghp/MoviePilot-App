import MoviePilotCore
import QuartzCore
import UIKit

/// 独立透明原生弹幕叠加层：基于 `CADisplayLink`（支持 ProMotion 120Hz）与 `CATextLayer` 复用池渲染，
/// `isUserInteractionEnabled = false` 绝不拦截播放器手势，且完全与底层视频解码内核解耦。
@MainActor
final class DanmakuOverlayView: UIView {
  let engine = DanmakuEngine()

  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval = 0
  private var activeLayers: [UInt64: CATextLayer] = [:]
  private var recycledLayers: [CATextLayer] = []
  private var widthCache: [String: CGSize] = [:]
  private var isRenderingPausedForPiP = false
  private var isDanmakuVisible = true

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    clipsToBounds = true
    accessibilityElementsHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    engine.updateViewport(size: bounds.size, topSafePadding: max(10, safeAreaInsets.top + 6))
  }

  /// 应用用户弹幕渲染偏好（不透明度、字号、速度、区域、上限）。
  func applyPreferences(_ prefs: DanmakuPreferencesStore) {
    isDanmakuVisible = prefs.enabled
    isHidden = !isDanmakuVisible || isRenderingPausedForPiP
    engine.opacity = prefs.opacity
    if abs(engine.fontScale - prefs.fontScale) > 0.001 {
      widthCache.removeAll(keepingCapacity: true)
    }
    engine.fontScale = prefs.fontScale
    engine.userSpeed = prefs.speed
    engine.areaRatio = prefs.areaRatio
    engine.maxOnScreen = prefs.maxOnScreen
    if !isDanmakuVisible {
      recycleAllActiveLayers()
      stopDisplayLink()
    } else if !isRenderingPausedForPiP && !engine.items.isEmpty {
      startDisplayLinkIfNeeded()
    }
  }

  /// 加载离线处理完成的弹幕时间线并启动帧调度。
  func load(timeline: PreparedDanmakuTimeline, currentPositionMs: Int) {
    recycleAllActiveLayers()
    engine.load(items: timeline.items, currentPositionMs: currentPositionMs)
    if isDanmakuVisible && !isRenderingPausedForPiP && !timeline.items.isEmpty {
      startDisplayLinkIfNeeded()
    } else {
      stopDisplayLink()
    }
  }

  /// 同步播放器时间轴、播放/暂停与倍速状态。
  func syncPlayback(positionMs: Int, isPlaying: Bool, playbackRate: Double) {
    engine.syncPlayerClock(positionMs: positionMs, isPlaying: isPlaying, playbackRate: playbackRate)
    if !isDanmakuVisible || isRenderingPausedForPiP || engine.items.isEmpty {
      stopDisplayLink()
      return
    }
    if isPlaying {
      startDisplayLinkIfNeeded()
    }
  }

  /// 画中画（PiP）期间暂停渲染并隐藏弹幕层降低功耗。
  func setPictureInPictureActive(_ active: Bool) {
    isRenderingPausedForPiP = active
    isHidden = !isDanmakuVisible || active
    if active {
      recycleAllActiveLayers()
      stopDisplayLink()
    } else if isDanmakuVisible && !engine.items.isEmpty {
      startDisplayLinkIfNeeded()
    }
  }

  /// 彻底清空并停止帧循环（用于切集或销毁播放器）。
  func stopAndClear() {
    stopDisplayLink()
    engine.clearAll()
    recycleAllActiveLayers()
    widthCache.removeAll()
  }

  private func startDisplayLinkIfNeeded() {
    guard displayLink == nil else { return }
    lastTimestamp = 0
    let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
    lastTimestamp = 0
  }

  @objc private func handleFrame(_ link: CADisplayLink) {
    guard !isHidden, isDanmakuVisible, !isRenderingPausedForPiP else { return }
    let dt: TimeInterval
    if lastTimestamp == 0 {
      dt = 1.0 / 60.0
    } else {
      dt = max(0, link.timestamp - lastTimestamp)
    }
    lastTimestamp = link.timestamp

    engine.step(dt: dt) { [weak self] text, fontSize in
      self?.measureText(text, fontSize: fontSize) ?? CGSize(width: 80, height: fontSize * 1.3)
    }
    syncLayersWithActiveSlots()
  }

  private func measureText(_ text: String, fontSize: CGFloat) -> CGSize {
    let key = "\(Int(fontSize.rounded()))|\(text)"
    if let cached = widthCache[key] {
      return cached
    }
    let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    let size = (text as NSString).size(withAttributes: [.font: font])
    if widthCache.count > 1024 {
      widthCache.removeAll(keepingCapacity: true)
    }
    widthCache[key] = size
    return size
  }

  private func syncLayersWithActiveSlots() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let activeIDs = Set(engine.activeSlots.map(\.id))
    for (id, layer) in activeLayers where !activeIDs.contains(id) {
      layer.removeFromSuperlayer()
      activeLayers.removeValue(forKey: id)
      if recycledLayers.count < 80 {
        recycledLayers.append(layer)
      }
    }

    let fontSize = engine.effectiveFontSize
    let opacityFloat = Float(engine.opacity)
    for slot in engine.activeSlots {
      let textLayer: CATextLayer
      if let existing = activeLayers[slot.id] {
        textLayer = existing
      } else {
        textLayer = dequeueTextLayer()
        textLayer.string = makeAttributedText(
          slot.displayText, colorRgb: slot.item.colorRgb, fontSize: fontSize)
        layer.addSublayer(textLayer)
        activeLayers[slot.id] = textLayer
      }
      textLayer.opacity = opacityFloat
      textLayer.frame = CGRect(x: slot.x, y: slot.y, width: slot.width, height: slot.height)
    }

    CATransaction.commit()
  }

  private func dequeueTextLayer() -> CATextLayer {
    if let reused = recycledLayers.popLast() {
      return reused
    }
    let textLayer = CATextLayer()
    textLayer.contentsScale = window?.screen.scale ?? 3.0
    textLayer.alignmentMode = .left
    textLayer.isWrapped = false
    textLayer.truncationMode = .none
    return textLayer
  }

  private func makeAttributedText(_ text: String, colorRgb: UInt32, fontSize: CGFloat)
    -> NSAttributedString
  {
    let r = CGFloat((colorRgb >> 16) & 0xFF) / 255.0
    let g = CGFloat((colorRgb >> 8) & 0xFF) / 255.0
    let b = CGFloat(colorRgb & 0xFF) / 255.0
    let fillColor = UIColor(red: r, green: g, blue: b, alpha: 1.0)
    let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
    let shadow = NSShadow()
    shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
    shadow.shadowOffset = CGSize(width: 0, height: 1)
    shadow.shadowBlurRadius = 2.0
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: fillColor,
      .strokeColor: UIColor.black.withAlphaComponent(0.82),
      .strokeWidth: -2.6,
      .shadow: shadow,
    ]
    return NSAttributedString(string: text, attributes: attrs)
  }

  private func recycleAllActiveLayers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (_, layer) in activeLayers {
      layer.removeFromSuperlayer()
      if recycledLayers.count < 80 {
        recycledLayers.append(layer)
      }
    }
    activeLayers.removeAll(keepingCapacity: true)
    CATransaction.commit()
  }
}
