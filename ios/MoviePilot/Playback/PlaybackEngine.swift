import AVFoundation
import Foundation
import MoviePilotCore
import UIKit
import VLCKit

/// 引擎错误分类：用于区分网络/鉴权故障与容器/解码不兼容，驱动「自动切核」与「回退代理」两级兜底。
enum PlaybackEngineErrorKind: Equatable, Sendable {
  case network
  case auth
  case unsupportedFormat
  case decoderFailure
  case unknown
}

/// 跨内核统一播放状态。
enum PlaybackEngineState: Equatable, Sendable {
  case idle
  case opening
  case buffering
  case playing
  case paused
  case ended
  case error(PlaybackEngineErrorKind)
}

/// 跨内核统一音轨/字幕轨道描述。
struct EngineTrack: Equatable, Sendable, Identifiable {
  let id: String
  let label: String
  let language: String?
  let isSelected: Bool
}

/// 播放引擎能力声明：UI 据此动态启用或隐藏画中画、AirPlay 视频等控件。
struct EngineCapabilities: Equatable, Sendable {
  let supportsPiP: Bool
  let supportsAirPlayVideo: Bool
  let supportsAssStyling: Bool
  let supportsSoftwareVideoDecode: Bool
  let maxRate: Float
}

/// 传递给底层引擎的媒体来源与安全鉴权上下文。
struct EngineMediaSource: Sendable {
  let url: URL
  let headers: [String: String]
  let isSameOriginInstance: Bool
  let sameOriginCookie: HTTPCookie?
  let rawExternalSafeURL: URL?
  let mimeTypeHint: String?

  init(
    url: URL,
    headers: [String: String] = [:],
    isSameOriginInstance: Bool = false,
    sameOriginCookie: HTTPCookie? = nil,
    rawExternalSafeURL: URL? = nil,
    mimeTypeHint: String? = nil
  ) {
    self.url = url
    self.headers = headers
    self.isSameOriginInstance = isSameOriginInstance
    self.sameOriginCookie = sameOriginCookie
    self.rawExternalSafeURL = rawExternalSafeURL
    self.mimeTypeHint = mimeTypeHint
  }

  /// 根据文件名提示或 URL 后缀推断无扩展名代理流的 MIME 类型，协助系统解码器即时识别容器。
  static func inferMimeType(url: URL, fileNameHint: String?) -> String? {
    let rawExt =
      !url.pathExtension.isEmpty
      ? url.pathExtension
      : ((fileNameHint ?? "") as NSString).pathExtension
    switch rawExt.lowercased() {
    case "flac": return "audio/flac"
    case "mp3": return "audio/mpeg"
    case "wav": return "audio/wav"
    case "aac": return "audio/aac"
    case "m4a", "alac": return "audio/mp4"
    case "aif", "aiff": return "audio/aiff"
    case "ogg", "oga", "opus": return "audio/ogg"
    case "mp4", "m4v": return "video/mp4"
    case "mov": return "video/quicktime"
    case "m3u8": return "application/vnd.apple.mpegurl"
    case "ts", "m2ts": return "video/mp2t"
    case "mkv": return "video/x-matroska"
    case "webm": return "video/webm"
    default: return nil
    }
  }
}

/// 传递给底层引擎的加载配置（解码模式、缓冲档位、声音与字幕增强及起播进度）。
struct EngineLoadOptions: Sendable {
  let isAudio: Bool
  let decodeMode: PlaybackDecodeMode
  let bufferProfile: PlaybackBufferProfile
  let audioNightMode: Bool
  let ignoreAssStyle: Bool
  let subtitleScale: Double
  let allowSelfSignedTls: Bool
  let startPositionMs: Int
  let aspectFill: Bool
  let rate: Float
}

/// 供 `MediaPictureInPictureController` 绑定的底层画中画输出源。
enum EnginePictureInPictureSource {
  case avPlayerLayer(AVPlayerLayer)
  case sampleBufferLayer(AVSampleBufferDisplayLayer)
  case vlcSampleBuffer(VLCMediaPlayer, UIView)
  case none
}

/// iOS 多内核统一播放引擎协议：屏蔽 `AVPlayer`、`MPVKit (libmpv)` 与 `VLCKit` 差异。
@MainActor
protocol PlaybackEngine: AnyObject {
  var kind: ResolvedPlaybackEngine { get }
  var capabilities: EngineCapabilities { get }
  var pipSource: EnginePictureInPictureSource { get }

  var isPlaying: Bool { get }
  var isSeekable: Bool { get }
  var currentTimeMs: Int { get }
  var durationMs: Int { get }
  var rate: Float { get set }

  var audioTracks: [EngineTrack] { get }
  var subtitleTracks: [EngineTrack] { get }

  var onStateChanged: ((PlaybackEngineState) -> Void)? { get set }
  var onTracksChanged: (() -> Void)? { get set }

  func attachVideoContainer(_ container: UIView)
  func detachVideoContainer()

  func load(source: EngineMediaSource, options: EngineLoadOptions) throws
  func play()
  func pause()
  func seek(toMs: Int)
  func jump(byOffsetMs deltaMs: Int, completion: (@MainActor () -> Void)?)
  func setAspectFill(_ fill: Bool)

  func selectAudioTrack(id: String)
  func selectSubtitleTrack(id: String)
  func deselectAllSubtitles()
  @discardableResult
  func addExternalSubtitle(fileURL: URL) -> Bool

  /// 通知引擎系统画中画窗口是否即将/已经接管输出（用于后台软解渲染保活与恢复前台硬解）。
  func setPictureInPictureActive(_ active: Bool)

  /// 异步释放底层解码器，严禁在 UI 主线程阻塞等待解码/渲染线程退出。
  func stopAndReleaseAsync(on queue: DispatchQueue, completion: (@Sendable () -> Void)?)
}

extension PlaybackEngine {
  func setPictureInPictureActive(_ active: Bool) {}
}

/// iOS 播放偏好统一读写入口（键名严格对齐 `docs/design/multi-engine-playback-design.md`）。
enum PlaybackEnginePreferences {
  static let videoEngineKey = "nativeV2.playback.videoEngine"
  static let decodeModeKey = "nativeV2.playback.decodeMode"
  static let bufferProfileKey = "nativeV2.playback.bufferProfile"
  static let audioNightModeKey = "nativeV2.playback.audioNightMode"
  static let ignoreAssStyleKey = "nativeV2.playback.ignoreAssStyle"
  static let subtitleScaleKey = "nativeV2.playback.subtitleScale"
  static let externalPlayerTemplateKey = "nativeV2.playback.externalPlayerTemplate"

  static var videoEngine: PlaybackEngineChoice {
    let raw = UserDefaults.standard.string(forKey: videoEngineKey) ?? "auto"
    return PlaybackEngineChoice(rawValue: raw) ?? .auto
  }

  static var decodeMode: PlaybackDecodeMode {
    let raw = UserDefaults.standard.string(forKey: decodeModeKey) ?? "hw_auto"
    return PlaybackDecodeMode(rawValue: raw) ?? .hwAuto
  }

  static var bufferProfile: PlaybackBufferProfile {
    let raw = UserDefaults.standard.string(forKey: bufferProfileKey) ?? "standard"
    return PlaybackBufferProfile(rawValue: raw) ?? .standard
  }

  static var audioNightMode: Bool {
    UserDefaults.standard.bool(forKey: audioNightModeKey)
  }

  static var ignoreAssStyle: Bool {
    UserDefaults.standard.bool(forKey: ignoreAssStyleKey)
  }

  static var subtitleScale: Double {
    let raw = UserDefaults.standard.double(forKey: subtitleScaleKey)
    return raw > 0.5 ? raw : 1.0
  }

  static var externalPlayerTemplate: String {
    (UserDefaults.standard.string(forKey: externalPlayerTemplateKey) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
