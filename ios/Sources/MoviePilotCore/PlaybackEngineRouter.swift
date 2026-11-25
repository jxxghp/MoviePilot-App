import Foundation

/// 客户端平台类型（与 Rust `mp_core_model::PlatformKind` 1:1 对齐）。
public enum PlaybackPlatformKind: String, Codable, Sendable, Equatable {
  case ios
  case android
  case harmony
}

/// 用户在播放偏好中选择的多内核模式。
public enum PlaybackEngineChoice: String, Codable, Sendable, Equatable, CaseIterable {
  case auto
  case native
  case enhanced
  case legacy

  /// iOS 设置页展示标签键。
  public var settingsLabelKey: String {
    switch self {
    case .auto: return "自动选择（推荐）"
    case .native: return "系统原生内核"
    case .enhanced: return "全能增强内核"
    case .legacy: return "兼容内核（VLCKit）"
    }
  }
}

/// 路由决策后的实际生效内核。
public enum ResolvedPlaybackEngine: String, Codable, Sendable, Equatable, CaseIterable {
  case native
  case enhanced
  case legacy

  /// 面向 iOS 界面展示的当前内核短名称。
  public func displayLabelKey(platform: PlaybackPlatformKind = .ios) -> String {
    switch (platform, self) {
    case (.ios, .native): return "AVPlayer 原生"
    case (.ios, .enhanced): return "MPV 全能"
    case (.ios, .legacy): return "VLCKit 兼容"
    case (.android, .native): return "Media3 原生"
    case (.android, .enhanced): return "MPV 全能"
    case (.android, .legacy): return "Media3 原生"
    case (.harmony, .native): return "AVPlayer 原生"
    case (.harmony, .enhanced): return "IJK 增强"
    case (.harmony, .legacy): return "AVPlayer 原生"
    }
  }
}

/// 解码模式。
public enum PlaybackDecodeMode: String, Codable, Sendable, Equatable, CaseIterable {
  case hwAuto = "hw_auto"
  case swForce = "sw_force"

  public var labelKey: String {
    switch self {
    case .hwAuto: return "硬件解码优先"
    case .swForce: return "强制软件解码"
    }
  }
}

/// 网络缓冲档位。
public enum PlaybackBufferProfile: String, Codable, Sendable, Equatable, CaseIterable {
  case standard
  case large

  public var labelKey: String {
    switch self {
    case .standard: return "标准缓冲"
    case .large: return "大缓冲（4K / STRM）"
    }
  }
}

/// 选核决策输入模型。
public struct PlaybackEngineResolutionInput: Codable, Sendable, Equatable {
  public let platform: PlaybackPlatformKind
  public let preferred: PlaybackEngineChoice
  public let isAudio: Bool
  public let decodeForceSoftware: Bool
  public let hasEnhancedEngine: Bool
  public let hasLegacyEngine: Bool
  public let urlOrFilename: String
  public let containerHint: String?
  public let audioCodecHint: String?
  public let videoCodecHint: String?
  public let hasAssOrPgsSubtitle: Bool
  public let ignoreAssStyle: Bool
  public let allowSelfSignedTls: Bool

  public init(
    platform: PlaybackPlatformKind = .ios,
    preferred: PlaybackEngineChoice = .auto,
    isAudio: Bool = false,
    decodeForceSoftware: Bool = false,
    hasEnhancedEngine: Bool = true,
    hasLegacyEngine: Bool = true,
    urlOrFilename: String = "",
    containerHint: String? = nil,
    audioCodecHint: String? = nil,
    videoCodecHint: String? = nil,
    hasAssOrPgsSubtitle: Bool = false,
    ignoreAssStyle: Bool = false,
    allowSelfSignedTls: Bool = false
  ) {
    self.platform = platform
    self.preferred = preferred
    self.isAudio = isAudio
    self.decodeForceSoftware = decodeForceSoftware
    self.hasEnhancedEngine = hasEnhancedEngine
    self.hasLegacyEngine = hasLegacyEngine
    self.urlOrFilename = urlOrFilename
    self.containerHint = containerHint
    self.audioCodecHint = audioCodecHint
    self.videoCodecHint = videoCodecHint
    self.hasAssOrPgsSubtitle = hasAssOrPgsSubtitle
    self.ignoreAssStyle = ignoreAssStyle
    self.allowSelfSignedTls = allowSelfSignedTls
  }
}

/// 选核决策结果。
public struct PlaybackEngineResolutionPlan: Codable, Sendable, Equatable {
  public let primary: ResolvedPlaybackEngine
  public let fallback: ResolvedPlaybackEngine?
  public let reasonCode: String
  public let engineLabelKey: String

  public init(
    primary: ResolvedPlaybackEngine,
    fallback: ResolvedPlaybackEngine?,
    reasonCode: String,
    engineLabelKey: String
  ) {
    self.primary = primary
    self.fallback = fallback
    self.reasonCode = reasonCode
    self.engineLabelKey = engineLabelKey
  }
}

/// 跨端同构无状态播放内核路由器（与 Rust `mp_core_model::PlaybackEngineRouter` 完全一致）。
public enum PlaybackEngineRouter {
  /// 依据平台能力、用户偏好与媒体特征确定主播放内核与自动降级备选内核。
  public static func resolve(_ input: PlaybackEngineResolutionInput)
    -> PlaybackEngineResolutionPlan
  {
    func isAvailable(_ engine: ResolvedPlaybackEngine) -> Bool {
      switch engine {
      case .native: return true
      case .enhanced: return input.hasEnhancedEngine
      case .legacy: return input.platform == .ios && input.hasLegacyEngine
      }
    }

    func makePlan(
      primary: ResolvedPlaybackEngine,
      fallback: ResolvedPlaybackEngine?,
      reason: String
    ) -> PlaybackEngineResolutionPlan {
      let effPrimary = isAvailable(primary) ? primary : .native
      let effFallback = fallback.flatMap { fb in
        (fb != effPrimary && isAvailable(fb)) ? fb : nil
      }
      return PlaybackEngineResolutionPlan(
        primary: effPrimary,
        fallback: effFallback,
        reasonCode: reason,
        engineLabelKey: effPrimary.displayLabelKey(platform: input.platform)
      )
    }

    switch input.preferred {
    case .native:
      let fb: ResolvedPlaybackEngine? =
        input.hasEnhancedEngine ? .enhanced : (isAvailable(.legacy) ? .legacy : nil)
      return makePlan(primary: .native, fallback: fb, reason: "user_pinned_native")
    case .enhanced:
      if input.hasEnhancedEngine {
        let fb: ResolvedPlaybackEngine = isAvailable(.legacy) ? .legacy : .native
        return makePlan(primary: .enhanced, fallback: fb, reason: "user_pinned_enhanced")
      }
      return makePlan(primary: .native, fallback: nil, reason: "enhanced_unavailable")
    case .legacy:
      if isAvailable(.legacy) {
        let fb: ResolvedPlaybackEngine = input.hasEnhancedEngine ? .enhanced : .native
        return makePlan(primary: .legacy, fallback: fb, reason: "user_pinned_legacy")
      }
      let next: ResolvedPlaybackEngine = input.hasEnhancedEngine ? .enhanced : .native
      return makePlan(primary: next, fallback: .native, reason: "legacy_unavailable")
    case .auto:
      break
    }

    if input.isAudio {
      let ext = extractExtension(input.urlOrFilename)
      let codec = normalizeHint(input.audioCodecHint)
      let exoticExts: Set<String> = ["ape", "wv", "dsf", "dff", "dts", "ac3", "eac3", "mlp", "thd"]
      let exoticCodecs: Set<String> = [
        "ape", "wavpack", "dsd", "dts", "dca", "ac3", "eac3", "truehd",
      ]
      if (exoticExts.contains(ext) || exoticCodecs.contains(codec)) && input.hasEnhancedEngine {
        return makePlan(primary: .enhanced, fallback: .native, reason: "audio_exotic_enhanced")
      }
      let fb: ResolvedPlaybackEngine? =
        input.hasEnhancedEngine ? .enhanced : (isAvailable(.legacy) ? .legacy : nil)
      return makePlan(primary: .native, fallback: fb, reason: "audio_native")
    }

    if input.decodeForceSoftware && input.hasEnhancedEngine {
      return makePlan(primary: .enhanced, fallback: .native, reason: "force_software_decode")
    }

    let container = resolveContainer(input)
    let audioCodec = normalizeHint(input.audioCodecHint)
    let videoCodec = normalizeHint(input.videoCodecHint)
    let needsRichSubtitle = input.hasAssOrPgsSubtitle && !input.ignoreAssStyle

    switch input.platform {
    case .ios:
      let standardNative: Set<String> = ["mp4", "m4v", "mov", "m3u8", "hls"]
      let unsupportedAudio: Set<String> = ["dts", "dca", "truehd", "mlp"]
      let unsupportedVideo: Set<String> = [
        "av1", "vc1", "mpeg2", "mpeg2video", "vp9", "hi10p", "rv40",
      ]
      if standardNative.contains(container)
        && !unsupportedAudio.contains(audioCodec)
        && !unsupportedVideo.contains(videoCodec)
        && !needsRichSubtitle
        && !input.allowSelfSignedTls
      {
        let fb: ResolvedPlaybackEngine? =
          input.hasEnhancedEngine ? .enhanced : (isAvailable(.legacy) ? .legacy : nil)
        return makePlan(primary: .native, fallback: fb, reason: "ios_native_standard")
      }
      if input.hasEnhancedEngine {
        let fb: ResolvedPlaybackEngine = isAvailable(.legacy) ? .legacy : .native
        let reason =
          needsRichSubtitle
          ? "mkv_or_ass_enhanced"
          : (input.allowSelfSignedTls
            ? "ios_self_signed_tls_enhanced" : "ios_container_or_codec_enhanced")
        return makePlan(primary: .enhanced, fallback: fb, reason: reason)
      }
      if isAvailable(.legacy) {
        return makePlan(primary: .legacy, fallback: .native, reason: "ios_legacy_fallback")
      }
      return makePlan(primary: .native, fallback: nil, reason: "ios_native_only")

    case .android:
      let hardVideo: Set<String> = ["vc1", "mpeg2", "mpeg2video", "hi10p", "rv40", "wmv3"]
      let hardContainer: Set<String> = ["rmvb", "rm", "avi", "wmv"]
      if (needsRichSubtitle || hardVideo.contains(videoCodec) || hardContainer.contains(container))
        && input.hasEnhancedEngine
      {
        return makePlan(
          primary: .enhanced,
          fallback: .native,
          reason: needsRichSubtitle ? "android_ass_or_pgs_enhanced" : "android_codec_enhanced"
        )
      }
      return makePlan(
        primary: .native,
        fallback: input.hasEnhancedEngine ? .enhanced : nil,
        reason: "android_media3_default"
      )

    case .harmony:
      let standardNative: Set<String> = ["mp4", "m4v", "mov", "m3u8", "hls"]
      let enhancedContainers: Set<String> = [
        "mkv", "ts", "m2ts", "flv", "rmvb", "avi", "wmv", "webm",
      ]
      let enhancedAudio: Set<String> = ["dts", "dca", "truehd", "ac3", "eac3", "mlp"]
      if input.hasEnhancedEngine
        && (enhancedContainers.contains(container)
          || enhancedAudio.contains(audioCodec)
          || input.allowSelfSignedTls
          || needsRichSubtitle
          || (!container.isEmpty && !standardNative.contains(container)))
      {
        let reason =
          input.allowSelfSignedTls
          ? "harmony_self_signed_tls"
          : (enhancedAudio.contains(audioCodec)
            ? "harmony_audio_codec_enhanced" : "harmony_container_enhanced")
        return makePlan(primary: .enhanced, fallback: .native, reason: reason)
      }
      return makePlan(
        primary: .native,
        fallback: input.hasEnhancedEngine ? .enhanced : nil,
        reason: "harmony_avplayer_default"
      )
    }
  }

  /// 安全校验并渲染自定义外部播放器 URL 模板（拒绝危险协议与内嵌凭据链接）。
  public static func buildExternalPlayerURL(
    template: String,
    mediaURL: String,
    title: String
  ) -> URL? {
    let cleanTpl = template.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanMedia = mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTpl.isEmpty,
      let mediaComps = URLComponents(string: cleanMedia),
      let mediaScheme = mediaComps.scheme?.lowercased(),
      mediaScheme == "http" || mediaScheme == "https",
      let host = mediaComps.host, !host.isEmpty,
      mediaComps.user == nil, mediaComps.password == nil,
      let schemeRange = cleanTpl.range(of: "://")
    else {
      return nil
    }
    let scheme = cleanTpl[..<schemeRange.lowerBound]
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let blockedSchemes: Set<String> = [
      "javascript", "vbscript", "data", "file", "about", "blob", "tel", "sms",
    ]
    guard !scheme.isEmpty,
      !blockedSchemes.contains(scheme),
      scheme.first?.isLetter == true,
      scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
    else {
      return nil
    }

    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.~")
    let encodedURL = cleanMedia.addingPercentEncoding(withAllowedCharacters: allowed) ?? cleanMedia
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let encodedTitle =
      cleanTitle.addingPercentEncoding(withAllowedCharacters: allowed) ?? cleanTitle

    let rendered: String
    if cleanTpl.contains("{url}") || cleanTpl.contains("{raw_url}") {
      rendered = cleanTpl
        .replacingOccurrences(of: "{url}", with: encodedURL)
        .replacingOccurrences(of: "{raw_url}", with: cleanMedia)
        .replacingOccurrences(of: "{title}", with: encodedTitle)
    } else {
      rendered = cleanTpl + encodedURL
    }
    return URL(string: rendered)
  }

  private static func normalizeHint(_ raw: String?) -> String {
    (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func extractExtension(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let pathPart: String
    if let url = URL(string: trimmed), url.scheme != nil {
      pathPart = url.path
    } else {
      pathPart = trimmed.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
    }
    let fileName = pathPart.split(separator: "/").last.map(String.init) ?? ""
    guard let dotIdx = fileName.lastIndex(of: ".") else { return "" }
    return String(fileName[fileName.index(after: dotIdx)...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  private static func resolveContainer(_ input: PlaybackEngineResolutionInput) -> String {
    let hint = normalizeHint(input.containerHint)
    if !hint.isEmpty { return hint }
    return extractExtension(input.urlOrFilename)
  }
}
