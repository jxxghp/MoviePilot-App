import Foundation
import MoviePilotCore
import UIKit
@preconcurrency import VLCKit

/// 过渡期兼容播放引擎（封装既有 `VLCMediaPlayer`）：
/// - 放开标准/大缓冲 `:network-caching` 档位与软硬解选项；
/// - 保留既有 `AVSampleBufferDisplayLayer` 原生画中画能力与后台串行释放队列。
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

  private let player = VLCMediaPlayer(options: ["--no-mouse-events", "--no-keyboard-events"])
  private weak var videoContainer: UIView?
  private var currentRate: Float = 1.0
  private var pendingStartPositionMs: Int = 0
  private var hasAppliedStartSeek = false

  var onStateChanged: ((PlaybackEngineState) -> Void)?
  var onTracksChanged: (() -> Void)?

  override init() {
    super.init()
    player.delegate = self
  }

  var pipSource: EnginePictureInPictureSource {
    guard let videoContainer else { return .none }
    return .vlcSampleBuffer(player, videoContainer)
  }

  var isPlaying: Bool { player.isPlaying }
  var isSeekable: Bool { player.isSeekable }
  var currentTimeMs: Int { max(0, Int(player.time.intValue)) }
  var durationMs: Int { max(0, Int(player.media?.length.intValue ?? 0)) }

  var rate: Float {
    get { currentRate }
    set {
      let clamped = max(0.5, min(capabilities.maxRate, newValue))
      currentRate = clamped
      player.rate = clamped
    }
  }

  var audioTracks: [EngineTrack] {
    player.audioTracks.enumerated().map { idx, track in
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
    player.textTracks.enumerated().map { idx, track in
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
    videoContainer = container
    player.drawable = container
  }

  func detachVideoContainer() {
    player.drawable = nil
    videoContainer = nil
  }

  func load(source: EngineMediaSource, options: EngineLoadOptions) throws {
    player.delegate = self
    player.drawable = options.isAudio ? nil : videoContainer
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
      // libVLC freetype-rel-fontsize 数值越小字体越大（默认 16）
      let relSize = max(10, min(24, Int(round(16.0 / options.subtitleScale))))
      media.addOption(":freetype-rel-fontsize=\(relSize)")
    }

    player.videoFitMode = options.aspectFill ? .larger : .smaller
    player.media = media
    onStateChanged?(.opening)
  }

  func play() {
    player.play()
  }

  func pause() {
    player.pause()
  }

  func seek(toMs: Int) {
    player.time = VLCTime(int: Int32(clamping: max(0, toMs)))
  }

  func jump(byOffsetMs deltaMs: Int, completion: (@MainActor () -> Void)?) {
    guard player.isSeekable else {
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
    player.videoFitMode = fill ? .larger : .smaller
  }

  func selectAudioTrack(id: String) {
    let tracks = player.audioTracks
    guard let idx = Int(id), tracks.indices.contains(idx) else { return }
    tracks[idx].isSelectedExclusively = true
    onTracksChanged?()
  }

  func selectSubtitleTrack(id: String) {
    let tracks = player.textTracks
    guard let idx = Int(id), tracks.indices.contains(idx) else { return }
    tracks[idx].isSelectedExclusively = true
    onTracksChanged?()
  }

  func deselectAllSubtitles() {
    player.deselectAllTextTracks()
    onTracksChanged?()
  }

  @discardableResult
  func addExternalSubtitle(fileURL: URL) -> Bool {
    player.addPlaybackSlave(fileURL, type: .subtitle, enforce: true) != 0
  }

  func stopAndReleaseAsync(on queue: DispatchQueue, completion: (@Sendable () -> Void)?) {
    player.delegate = nil
    player.drawable = nil
    videoContainer = nil
    onStateChanged = nil
    onTracksChanged = nil
    nonisolated(unsafe) let playerToStop = player
    queue.async {
      playerToStop.stop()
      playerToStop.media = nil
      completion?()
    }
  }

  // MARK: - VLCMediaPlayerDelegate

  nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      switch newState {
      case .nothingSpecial:
        break
      case .opening:
        self.onStateChanged?(.opening)
      case .playing:
        if !self.hasAppliedStartSeek && self.pendingStartPositionMs > 0 {
          self.hasAppliedStartSeek = true
          self.seek(toMs: self.pendingStartPositionMs)
        }
        if abs(self.currentRate - 1.0) >= 0.01 {
          self.player.rate = self.currentRate
        }
        self.onStateChanged?(.playing)
      case .paused:
        self.onStateChanged?(.paused)
      case .stopping, .stopped:
        self.onStateChanged?(.ended)
      case .error:
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
      self?.onTracksChanged?()
    }
  }
}
