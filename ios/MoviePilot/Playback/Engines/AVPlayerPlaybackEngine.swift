import AVFoundation
import Foundation
import MoviePilotCore
import UIKit

/// 基于 `AVPlayerLayer` 的系统原生渲染容器视图。
private final class AVPlayerHostView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer {
    guard let layer = self.layer as? AVPlayerLayer else {
      fatalError("Expected AVPlayerLayer")
    }
    return layer
  }
}

/// 系统原生 `AVPlayer` 播放引擎：
/// - 音频默认主力与标准 MP4/HLS 省电引擎，完整支持系统画中画与原生 AirPlay 视频直投；
/// - 仅对受控同源流或外部直链透传安全 HTTP 头，支持音轨/内封字幕切换与字号缩放规则。
@MainActor
final class AVPlayerPlaybackEngine: NSObject, PlaybackEngine {
  let kind: ResolvedPlaybackEngine = .native
  let capabilities = EngineCapabilities(
    supportsPiP: true,
    supportsAirPlayVideo: true,
    supportsAssStyling: false,
    supportsSoftwareVideoDecode: false,
    maxRate: 2.0
  )

  private let player = AVPlayer()
  private let hostView = AVPlayerHostView()
  private var itemStatusObserver: NSKeyValueObservation?
  private var timeControlObserver: NSKeyValueObservation?
  private var playbackBufferEmptyObserver: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var currentItem: AVPlayerItem?
  private var desiredRate: Float = 1.0
  private var pendingStartPositionMs: Int = 0
  private var hasAppliedStartSeek = false
  private var cachedAudioTracks: [EngineTrack] = []
  private var cachedSubtitleTracks: [EngineTrack] = []

  var onStateChanged: ((PlaybackEngineState) -> Void)?
  var onTracksChanged: (() -> Void)?

  override init() {
    super.init()
    hostView.translatesAutoresizingMaskIntoConstraints = false
    hostView.backgroundColor = .clear
    hostView.isUserInteractionEnabled = false
    hostView.playerLayer.player = player
    hostView.playerLayer.videoGravity = .resizeAspect
    player.automaticallyWaitsToMinimizeStalling = true

    timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) {
      [weak self] avPlayer, _ in
      let status = avPlayer.timeControlStatus
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch status {
        case .playing:
          self.onStateChanged?(.playing)
        case .waitingToPlayAtSpecifiedRate:
          self.onStateChanged?(.buffering)
        case .paused:
          self.onStateChanged?(.paused)
        @unknown default:
          break
        }
      }
    }
  }

  var pipSource: EnginePictureInPictureSource {
    .avPlayerLayer(hostView.playerLayer)
  }

  var isPlaying: Bool {
    player.timeControlStatus == .playing || (player.rate > 0.01 && player.error == nil)
  }

  var isSeekable: Bool {
    guard let item = currentItem, item.status == .readyToPlay else { return false }
    return !item.seekableTimeRanges.isEmpty || durationMs > 0
  }

  var currentTimeMs: Int {
    let secs = CMTimeGetSeconds(player.currentTime())
    guard secs.isFinite, secs > 0 else { return 0 }
    return Int(secs * 1000)
  }

  var durationMs: Int {
    guard let item = currentItem else { return 0 }
    let secs = CMTimeGetSeconds(item.duration)
    guard secs.isFinite, secs > 0 else { return 0 }
    return Int(secs * 1000)
  }

  var rate: Float {
    get { desiredRate }
    set {
      desiredRate = max(0.5, min(capabilities.maxRate, newValue))
      if player.timeControlStatus == .playing || player.rate > 0.01 {
        player.rate = desiredRate
      }
    }
  }

  var audioTracks: [EngineTrack] { cachedAudioTracks }
  var subtitleTracks: [EngineTrack] { cachedSubtitleTracks }

  func attachVideoContainer(_ container: UIView) {
    if hostView.superview !== container {
      hostView.removeFromSuperview()
      container.addSubview(hostView)
      NSLayoutConstraint.activate([
        hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        hostView.topAnchor.constraint(equalTo: container.topAnchor),
        hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
    }
    hostView.playerLayer.player = player
  }

  func detachVideoContainer() {
    hostView.playerLayer.player = nil
    hostView.removeFromSuperview()
  }

  func load(source: EngineMediaSource, options: EngineLoadOptions) throws {
    clearCurrentItemObservers()
    cachedAudioTracks = []
    cachedSubtitleTracks = []
    pendingStartPositionMs = max(0, options.startPositionMs)
    hasAppliedStartSeek = pendingStartPositionMs <= 0
    desiredRate = max(0.5, min(capabilities.maxRate, options.rate))
    player.allowsExternalPlayback = !options.isAudio
    hostView.playerLayer.videoGravity = options.aspectFill ? .resizeAspectFill : .resizeAspect

    var assetOptions: [String: Any] = [:]
    var requestHeaders = source.headers
    if source.isSameOriginInstance, let cookie = source.sameOriginCookie,
      requestHeaders["Cookie"] == nil
    {
      requestHeaders["Cookie"] = "\(cookie.name)=\(cookie.value)"
    }
    if !requestHeaders.isEmpty && !source.url.isFileURL {
      assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = requestHeaders
    }
    if options.isAudio && !source.url.isFileURL {
      // 网络音频禁用全文件精确时长预扫描，确保收到首片 Range 数据后立即边加载边播放
      assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = false
    }

    let asset = AVURLAsset(url: source.url, options: assetOptions.isEmpty ? nil : assetOptions)
    let item = AVPlayerItem(asset: asset)
    if options.isAudio && !source.url.isFileURL {
      item.preferredForwardBufferDuration = options.bufferProfile == .large ? 30 : 8
    } else {
      item.preferredForwardBufferDuration = options.bufferProfile == .large ? 60 : 20
    }
    if abs(options.subtitleScale - 1.0) >= 0.01 {
      let pct = Int(round(options.subtitleScale * 100))
      if let rule = AVTextStyleRule(textMarkupAttributes: [
        kCMTextMarkupAttribute_RelativeFontSize as String: pct
      ]) {
        item.textStyleRules = [rule]
      }
    }

    currentItem = item
    onStateChanged?(.opening)

    itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
      let status = observed.status
      let err = observed.error
      Task { @MainActor [weak self] in
        guard let self, self.currentItem === observed else { return }
        switch status {
        case .readyToPlay:
          if !self.hasAppliedStartSeek && self.pendingStartPositionMs > 0 {
            self.hasAppliedStartSeek = true
            self.seek(toMs: self.pendingStartPositionMs)
          }
          await self.reloadTracks(for: observed)
          if self.player.rate > 0.01 {
            self.player.rate = self.desiredRate
          }
        case .failed:
          let kind = Self.classifyError(err)
          self.onStateChanged?(.error(kind))
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }

    playbackBufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) {
      [weak self] observed, _ in
      let empty = observed.isPlaybackBufferEmpty
      Task { @MainActor [weak self] in
        guard let self, self.currentItem === observed else { return }
        if empty {
          self.onStateChanged?(.buffering)
        }
      }
    }

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.onStateChanged?(.ended)
      }
    }

    player.replaceCurrentItem(with: item)
  }

  func play() {
    player.playImmediately(atRate: desiredRate)
  }

  func pause() {
    player.pause()
  }

  func seek(toMs: Int) {
    let clamped = max(0, toMs)
    let cm = CMTime(value: CMTimeValue(clamped), timescale: 1000)
    player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
  }

  func jump(byOffsetMs deltaMs: Int, completion: (@MainActor () -> Void)?) {
    let target = max(0, min(durationMs > 0 ? durationMs : Int.max, currentTimeMs + deltaMs))
    let cm = CMTime(value: CMTimeValue(target), timescale: 1000)
    player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
      Task { @MainActor in
        completion?()
      }
    }
  }

  func setAspectFill(_ fill: Bool) {
    hostView.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
  }

  func selectAudioTrack(id: String) {
    guard let item = currentItem else { return }
    Task { @MainActor [weak self] in
      guard let self,
        let group = try? await item.asset.loadMediaSelectionGroup(for: .audible)
      else { return }
      if let idx = Int(id), group.options.indices.contains(idx) {
        item.select(group.options[idx], in: group)
        await self.reloadTracks(for: item)
      }
    }
  }

  func selectSubtitleTrack(id: String) {
    guard let item = currentItem else { return }
    Task { @MainActor [weak self] in
      guard let self,
        let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
      else { return }
      if let idx = Int(id), group.options.indices.contains(idx) {
        item.select(group.options[idx], in: group)
        await self.reloadTracks(for: item)
      }
    }
  }

  func deselectAllSubtitles() {
    guard let item = currentItem else { return }
    Task { @MainActor [weak self] in
      guard let self,
        let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
      else { return }
      item.select(nil, in: group)
      await self.reloadTracks(for: item)
    }
  }

  @discardableResult
  func addExternalSubtitle(fileURL: URL) -> Bool {
    // AVPlayer 原生不支持直接挂载本地 SRT/ASS 文件；需要外挂字幕时引导自动/手动切核至 MPV/VLC。
    _ = fileURL
    return false
  }

  func stopAndReleaseAsync(on queue: DispatchQueue, completion: (@Sendable () -> Void)?) {
    clearCurrentItemObservers()
    timeControlObserver = nil
    player.pause()
    player.replaceCurrentItem(with: nil)
    detachVideoContainer()
    currentItem = nil
    onStateChanged = nil
    onTracksChanged = nil
    queue.async {
      completion?()
    }
  }

  private func clearCurrentItemObservers() {
    itemStatusObserver = nil
    playbackBufferEmptyObserver = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
  }

  private func reloadTracks(for item: AVPlayerItem) async {
    let selection = item.currentMediaSelection
    if let audible = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
      let selected = selection.selectedMediaOption(in: audible)
      cachedAudioTracks = audible.options.enumerated().map { idx, opt in
        EngineTrack(
          id: "\(idx)",
          label: opt.displayName,
          language: opt.extendedLanguageTag,
          isSelected: opt == selected
        )
      }
    }
    if let legible = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
      let selected = selection.selectedMediaOption(in: legible)
      cachedSubtitleTracks = legible.options.enumerated().map { idx, opt in
        EngineTrack(
          id: "\(idx)",
          label: opt.displayName,
          language: opt.extendedLanguageTag,
          isSelected: opt == selected
        )
      }
    }
    onTracksChanged?()
  }

  private static func classifyError(_ error: Error?) -> PlaybackEngineErrorKind {
    guard let nsError = error as NSError? else { return .unknown }
    if nsError.domain == NSURLErrorDomain {
      if nsError.code == NSURLErrorUserAuthenticationRequired {
        return .auth
      }
      return .network
    }
    if nsError.domain == AVFoundationErrorDomain {
      let formatCodes: Set<Int> = [
        AVError.fileFormatNotRecognized.rawValue,
        AVError.fileFailedToParse.rawValue,
        AVError.formatUnsupported.rawValue,
        AVError.decoderNotFound.rawValue,
        AVError.decoderTemporarilyUnavailable.rawValue,
        AVError.noImageAtTime.rawValue,
      ]
      if formatCodes.contains(nsError.code) {
        return .unsupportedFormat
      }
      return .decoderFailure
    }
    return .unknown
  }
}
