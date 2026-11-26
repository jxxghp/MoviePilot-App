import Foundation
import MoviePilotCore
import UIKit
@preconcurrency import VLCKit

/// 过渡期兼容播放引擎（安全封装 `VLCMediaPlayer`）：
/// - 为每次会话分配独立子渲染视图 `renderView`，避免与其他内核争抢共享 `videoView`；
/// - 仅在真正进入 `.playing` 视频输出就绪后应用 `videoFitMode` 与轨道枚举，杜绝起播期 vout 未就绪崩溃；
/// - 异步停止与 `VLCMediaPlayer` 析构严格在独立后台线程完成（规避 `libvlc_media_player_release` 与 iOS vout `dispatch_sync(main)` 互锁），同时强持有 `renderView` 直至底层解码器完全销毁后再交回主线程释放。
@MainActor
final class VlcPlaybackEngine: NSObject, PlaybackEngine, VLCMediaPlayerDelegate {
  let kind: ResolvedPlaybackEngine = .legacy
  let capabilities = EngineCapabilities(
    supportsPiP: true,
    supportsAirPlayVideo: false,
    supportsAssStyling: true,
    supportsSoftwareVideoDecode: true,
    maxRate: 2.0
  )

  private var player: VLCMediaPlayer? = VLCMediaPlayer(
    options: ["--no-mouse-events", "--no-keyboard-events"]
  )
  private let renderView: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.backgroundColor = .clear
    v.isUserInteractionEnabled = false
    return v
  }()
  private weak var attachedContainer: UIView?
  private var currentRate: Float = 1.0
  private var aspectFillEnabled = false
  private var hasEnteredPlayingState = false
  private var isStopping = false
  private var cachedIsPlaying = false
  private var cachedTimeMs: Int = 0
  private var cachedDurationMs: Int = 0
  private var pendingStartPositionMs: Int = 0
  private var hasAppliedStartSeek = false

  var onStateChanged: ((PlaybackEngineState) -> Void)?
  var onTracksChanged: (() -> Void)?

  override init() {
    super.init()
    player?.delegate = self
  }

  deinit {
    nonisolated(unsafe) let leftoverPlayer = player
    let viewToKeep = renderView
    guard leftoverPlayer != nil else { return }
    DispatchQueue.global(qos: .utility).async {
      autoreleasepool {
        var localPlayer: VLCMediaPlayer? = leftoverPlayer
        if let p = localPlayer {
          p.delegate = nil
          p.stop()
          var polls = 0
          while p.state != .stopped && p.state != .error && polls < 200 {
            Thread.sleep(forTimeInterval: 0.025)
            polls += 1
          }
          p.media = nil
        }
        localPlayer = nil
      }
      DispatchQueue.main.async {
        _ = viewToKeep
      }
    }
  }

  var pipSource: EnginePictureInPictureSource {
    guard !isStopping, attachedContainer != nil, let player else { return .none }
    return .vlcSampleBuffer(player, renderView)
  }

  var isPlaying: Bool { !isStopping && cachedIsPlaying }
  var isSeekable: Bool { !isStopping && hasEnteredPlayingState && (player?.isSeekable == true) }
  var currentTimeMs: Int { cachedTimeMs }
  var durationMs: Int {
    if cachedDurationMs > 0 { return cachedDurationMs }
    guard !isStopping else { return 0 }
    return max(0, Int(player?.media?.length.intValue ?? 0))
  }

  var rate: Float {
    get { currentRate }
    set {
      let clamped = max(0.5, min(capabilities.maxRate, newValue))
      currentRate = clamped
      if !isStopping, hasEnteredPlayingState {
        player?.rate = clamped
      }
    }
  }

  var audioTracks: [EngineTrack] {
    guard !isStopping, hasEnteredPlayingState, let player else { return [] }
    return player.audioTracks.enumerated().map { idx, track in
      let name =
        track.trackName.isEmpty ? (track.trackDescription ?? L10n.text("音轨")) : track.trackName
      return EngineTrack(
        id: "\(idx)",
        label: name,
        language: track.language,
        isSelected: track.isSelected
      )
    }
  }

  var subtitleTracks: [EngineTrack] {
    guard !isStopping, hasEnteredPlayingState, let player else { return [] }
    return player.textTracks.enumerated().map { idx, track in
      let name =
        track.trackName.isEmpty ? (track.trackDescription ?? L10n.text("字幕")) : track.trackName
      return EngineTrack(
        id: "\(idx)",
        label: name,
        language: track.language,
        isSelected: track.isSelected
      )
    }
  }

  func attachVideoContainer(_ container: UIView) {
    guard !isStopping else { return }
    attachedContainer = container
    if renderView.superview !== container {
      renderView.removeFromSuperview()
      container.addSubview(renderView)
      NSLayoutConstraint.activate([
        renderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        renderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        renderView.topAnchor.constraint(equalTo: container.topAnchor),
        renderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      ])
      container.layoutIfNeeded()
    }
    player?.drawable = renderView
  }

  func detachVideoContainer() {
    renderView.removeFromSuperview()
    attachedContainer = nil
  }

  func load(source: EngineMediaSource, options: EngineLoadOptions) throws {
    guard !isStopping, let player else {
      throw MediaPlaybackError.unavailable
    }
    hasEnteredPlayingState = false
    cachedIsPlaying = false
    cachedTimeMs = max(0, options.startPositionMs)
    cachedDurationMs = 0
    aspectFillEnabled = options.aspectFill
    player.delegate = self
    player.drawable = options.isAudio ? nil : renderView
    currentRate = max(0.5, min(capabilities.maxRate, options.rate))
    pendingStartPositionMs = max(0, options.startPositionMs)
    hasAppliedStartSeek = pendingStartPositionMs <= 0

    let media: VLCMedia
    if source.url.isFileURL {
      guard let fileMedia = VLCMedia(url: source.url) else {
        throw MediaPlaybackError.unavailable
      }
      media = fileMedia
    } else {
      guard let scheme = source.url.scheme?.lowercased(), scheme == "http" || scheme == "https",
        let remoteMedia = VLCMedia(url: source.url)
      else {
        throw MediaPlaybackError.unavailable
      }
      if source.isSameOriginInstance {
        guard let cookie = source.sameOriginCookie, let host = source.url.host,
          remoteMedia.storeCookie(
            "\(cookie.name)=\(cookie.value)",
            forHost: host,
            path: source.url.deletingLastPathComponent().path + "/"
          ) == 0
        else {
          throw MediaPlaybackError.unavailable
        }
      } else {
        MediaPlaybackClient.applyExternalStreamHeaders(
          source.headers, to: remoteMedia, url: source.url)
      }
      media = remoteMedia
    }

    let cacheMs = options.bufferProfile == .large ? 6000 : 2000
    media.addOption(":network-caching=\(cacheMs)")
    if options.decodeMode == .swForce {
      media.addOption(":avcodec-hw=none")
    }
    if abs(options.subtitleScale - 1.0) >= 0.01 {
      let relSize = max(10, min(24, Int(round(16.0 / options.subtitleScale))))
      media.addOption(":freetype-rel-fontsize=\(relSize)")
    }

    player.media = media
    onStateChanged?(.opening)
  }

  func play() {
    guard !isStopping else { return }
    player?.play()
  }

  func pause() {
    guard !isStopping else { return }
    cachedIsPlaying = false
    player?.pause()
  }

  func seek(toMs: Int) {
    let clamped = max(0, toMs)
    cachedTimeMs = clamped
    guard !isStopping, hasEnteredPlayingState, let player else {
      pendingStartPositionMs = clamped
      hasAppliedStartSeek = false
      return
    }
    player.time = VLCTime(int: Int32(clamping: clamped))
  }

  func jump(byOffsetMs deltaMs: Int, completion: (@MainActor () -> Void)?) {
    guard !isStopping, hasEnteredPlayingState, let player, player.isSeekable else {
      completion?()
      return
    }
    let started = player.jump(withOffset: Int32(clamping: deltaMs)) {
      Task { @MainActor in
        completion?()
      }
    }
    if !started {
      completion?()
    }
  }

  func setAspectFill(_ fill: Bool) {
    aspectFillEnabled = fill
    guard !isStopping, hasEnteredPlayingState, let player else { return }
    player.videoFitMode = fill ? .larger : .smaller
  }

  func selectAudioTrack(id: String) {
    guard !isStopping, hasEnteredPlayingState, let player else { return }
    let tracks = player.audioTracks
    guard let idx = Int(id), tracks.indices.contains(idx) else { return }
    tracks[idx].isSelectedExclusively = true
    onTracksChanged?()
  }

  func selectSubtitleTrack(id: String) {
    guard !isStopping, hasEnteredPlayingState, let player else { return }
    let tracks = player.textTracks
    guard let idx = Int(id), tracks.indices.contains(idx) else { return }
    tracks[idx].isSelectedExclusively = true
    onTracksChanged?()
  }

  func deselectAllSubtitles() {
    guard !isStopping, hasEnteredPlayingState, let player else { return }
    player.deselectAllTextTracks()
    onTracksChanged?()
  }

  @discardableResult
  func addExternalSubtitle(fileURL: URL) -> Bool {
    guard !isStopping, let player else { return false }
    return player.addPlaybackSlave(fileURL, type: .subtitle, enforce: true) != 0
  }

  func stopAndReleaseAsync(on queue: DispatchQueue, completion: (@Sendable () -> Void)?) {
    isStopping = true
    hasEnteredPlayingState = false
    cachedIsPlaying = false
    renderView.removeFromSuperview()
    attachedContainer = nil
    onStateChanged = nil
    onTracksChanged = nil
    nonisolated(unsafe) let capturedPlayer = player
    player = nil
    capturedPlayer?.delegate = nil
    let viewToKeep = renderView
    guard capturedPlayer != nil else {
      if let completion { queue.async(execute: completion) }
      return
    }
    let vlcDisposeQueue = DispatchQueue(
      label: "com.moviepilot.playback.vlc.dispose.\(UUID().uuidString)",
      qos: .utility
    )
    vlcDisposeQueue.async {
      autoreleasepool {
        var localPlayer: VLCMediaPlayer? = capturedPlayer
        if let p = localPlayer {
          p.stop()
          var polls = 0
          while p.state != .stopped && p.state != .error && polls < 200 {
            Thread.sleep(forTimeInterval: 0.025)
            polls += 1
          }
          p.media = nil
        }
        localPlayer = nil
      }
      DispatchQueue.main.async {
        _ = viewToKeep
      }
      if let completion {
        queue.async(execute: completion)
      }
    }
  }

  // MARK: - VLCMediaPlayerDelegate

  nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
    Task { @MainActor [weak self] in
      guard let self, !self.isStopping, let player = self.player else { return }
      self.cachedTimeMs = max(0, Int(player.time.intValue))
      let dur = Int(player.media?.length.intValue ?? 0)
      if dur > 0 {
        self.cachedDurationMs = dur
      }
    }
  }

  nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
    Task { @MainActor [weak self] in
      guard let self, !self.isStopping, let player = self.player else { return }
      switch newState {
      case .nothingSpecial:
        break
      case .opening:
        self.onStateChanged?(.opening)
      case .playing:
        let firstPlaying = !self.hasEnteredPlayingState
        self.hasEnteredPlayingState = true
        self.cachedIsPlaying = true
        let dur = Int(player.media?.length.intValue ?? 0)
        if dur > 0 {
          self.cachedDurationMs = dur
        }
        if self.aspectFillEnabled || !firstPlaying {
          player.videoFitMode = self.aspectFillEnabled ? .larger : .smaller
        }
        if !self.hasAppliedStartSeek && self.pendingStartPositionMs > 0 {
          self.hasAppliedStartSeek = true
          player.time = VLCTime(int: Int32(clamping: self.pendingStartPositionMs))
        }
        if abs(self.currentRate - 1.0) >= 0.01 {
          player.rate = self.currentRate
        }
        self.onStateChanged?(.playing)
        if firstPlaying {
          self.onTracksChanged?()
        }
      case .paused:
        self.cachedIsPlaying = false
        self.onStateChanged?(.paused)
      case .stopping, .stopped:
        self.cachedIsPlaying = false
        self.onStateChanged?(.ended)
      case .error:
        self.cachedIsPlaying = false
        self.onStateChanged?(.error(.unknown))
      @unknown default:
        break
      }
    }
  }

  nonisolated func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
    _ = trackId
    _ = trackType
    Task { @MainActor [weak self] in
      guard let self, !self.isStopping, self.hasEnteredPlayingState else { return }
      self.onTracksChanged?()
    }
  }
}
