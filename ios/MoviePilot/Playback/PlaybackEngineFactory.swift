import Foundation
import MoviePilotCore

/// iOS 播放引擎工厂：调用共享 `PlaybackEngineRouter` 解析主内核与自动回退内核并实例化对应引擎。
@MainActor
enum PlaybackEngineFactory {
  /// 计算本次播放的引擎决策计划。
  static func resolvePlan(
    url: URL,
    manifest: MediaPlaybackManifest,
    isAudio: Bool,
    preferredOverride: PlaybackEngineChoice? = nil
  ) -> PlaybackEngineResolutionPlan {
    let hasAssOrPgs = manifest.subtitles.contains { sub in
      let probe = "\(sub.subtitleId) \(sub.url.path)".lowercased()
      return probe.contains(".ass") || probe.contains(".ssa") || probe.contains(".sup")
        || probe.contains(".pgs")
    }
    let rawProbe =
      url.isFileURL
      ? url.lastPathComponent
      : (!url.pathExtension.isEmpty
        ? url.absoluteString
        : (manifest.fileNameHint?.isEmpty == false ? manifest.fileNameHint! : url.absoluteString))
    let probeExt = (rawProbe as NSString).pathExtension.lowercased()
    let effectivePreferred: PlaybackEngineChoice
    if let preferredOverride {
      effectivePreferred = preferredOverride
    } else if isAudio,
      PlaybackEnginePreferences.videoEngine == .auto,
      ["ogg", "oga", "opus", "wma", "mka", "mpc", "tak", "tta"].contains(probeExt)
    {
      // iOS AVPlayer 原生不支持上述音频容器的 HTTP Range 流式解码，直接路由至 MPV 全能内核边加载边播放
      effectivePreferred = .enhanced
    } else {
      effectivePreferred = PlaybackEnginePreferences.videoEngine
    }
    let input = PlaybackEngineResolutionInput(
      platform: .ios,
      preferred: effectivePreferred,
      isAudio: isAudio,
      decodeForceSoftware: PlaybackEnginePreferences.decodeMode == .swForce,
      hasEnhancedEngine: true,
      hasLegacyEngine: true,
      urlOrFilename: rawProbe,
      hasAssOrPgsSubtitle: hasAssOrPgs,
      ignoreAssStyle: PlaybackEnginePreferences.ignoreAssStyle,
      allowSelfSignedTls: false
    )
    return PlaybackEngineRouter.resolve(input)
  }

  /// 实例化指定的具体播放引擎。
  static func makeEngine(_ kind: ResolvedPlaybackEngine) -> any PlaybackEngine {
    switch kind {
    case .native:
      return AVPlayerPlaybackEngine()
    case .enhanced:
      return MpvPlaybackEngine()
    case .legacy:
      return VlcPlaybackEngine()
    }
  }

  /// 构造当前偏好对应的加载选项。
  static func makeLoadOptions(
    isAudio: Bool,
    startPositionMs: Int,
    aspectFill: Bool,
    rate: Float
  ) -> EngineLoadOptions {
    EngineLoadOptions(
      isAudio: isAudio,
      decodeMode: PlaybackEnginePreferences.decodeMode,
      bufferProfile: PlaybackEnginePreferences.bufferProfile,
      audioNightMode: PlaybackEnginePreferences.audioNightMode,
      ignoreAssStyle: PlaybackEnginePreferences.ignoreAssStyle,
      subtitleScale: PlaybackEnginePreferences.subtitleScale,
      allowSelfSignedTls: false,
      startPositionMs: startPositionMs,
      aspectFill: aspectFill,
      rate: rate
    )
  }
}
