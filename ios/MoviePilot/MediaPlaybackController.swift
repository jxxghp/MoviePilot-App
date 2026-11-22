import AVFoundation
import AVKit
import CryptoKit
import ImageIO
import MediaPlayer
import MoviePilotCore
import UIKit
import VLCKit
import os

/// 已由当前 MoviePilot 实例授权的媒体清单，不包含访问令牌。
struct MediaPlaybackManifest: Decodable, Sendable {
  let itemId: String
  let server: String?
  let title: String
  let contentUrl: URL
  let mediaType: String?
  let artist: String?
  let album: String?
  let subtitles: [MediaPlaybackSubtitle]
  let lyricsUrl: URL?
  let mediaSourceId: String?
  let resumePositionMs: Int?
  let durationMs: Int?

  init(
    itemId: String,
    server: String?,
    title: String,
    contentUrl: URL,
    mediaType: String?,
    artist: String?,
    album: String?,
    subtitles: [MediaPlaybackSubtitle],
    lyricsUrl: URL?,
    mediaSourceId: String? = nil,
    resumePositionMs: Int? = nil,
    durationMs: Int? = nil
  ) {
    self.itemId = itemId
    self.server = server
    self.title = title
    self.contentUrl = contentUrl
    self.mediaType = mediaType
    self.artist = artist
    self.album = album
    self.subtitles = subtitles
    self.lyricsUrl = lyricsUrl
    self.mediaSourceId = mediaSourceId
    self.resumePositionMs = resumePositionMs
    self.durationMs = durationMs
  }
}

/// 后端发现的一条同名外挂字幕；内嵌字幕由 VLCKit 读取。
struct MediaPlaybackSubtitle: Decodable, Sendable {
  let subtitleId: String
  let title: String
  let language: String?
  let url: URL
}

/// 播放队列中的单集或单曲信息（兼容视频连续剧分集与音乐专辑曲目）。
struct MediaPlaybackQueueItem: Decodable, Sendable {
  let itemId: String
  let title: String
  let server: String?
  let artworkURL: String?
  let artist: String?
  let album: String?
  let subtitle: String?
  let mediaSourceId: String?

  init(
    itemId: String,
    title: String,
    server: String? = nil,
    artworkURL: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    subtitle: String? = nil,
    mediaSourceId: String? = nil
  ) {
    self.itemId = itemId
    self.title = title
    self.server = server
    self.artworkURL = artworkURL
    self.artist = artist
    self.album = album
    self.subtitle = subtitle
    self.mediaSourceId = mediaSourceId
  }
}

/// LRC 中带播放起始秒数的歌词行。
private struct MediaPlaybackLyricCue: Sendable {
  let time: Double
  let text: String
}

/// 流媒体服务端点和媒体 URL 均限定到当前实例来源。
@MainActor
final class MediaPlaybackClient {
  private let address: ServerAddress
  private let accessToken: String
  private let session: URLSession
  private var resourceCookie: HTTPCookie?
  private var selectedServer: String?

  /// 以短生命周期、无 Cookie 的网络会话访问当前实例播放接口。
  init(address: ServerAddress, accessToken: String) {
    self.address = address
    self.accessToken = accessToken
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 60
    session = URLSession(configuration: configuration)
  }

  /// 使用当前实例访问令牌读取已入库条目、流地址和外挂字幕清单，支持指定多版本媒体源。
  func loadManifest(itemId: String, server: String? = nil, mediaSourceId: String? = nil)
    async throws -> MediaPlaybackManifest
  {
    selectedServer = server
    var queryItems = [URLQueryItem(name: "itemid", value: itemId)]
    if let server { queryItems.append(URLQueryItem(name: "server", value: server)) }
    if let mediaSourceId, !mediaSourceId.isEmpty {
      queryItems.append(URLQueryItem(name: "media_source_id", value: mediaSourceId))
    }
    let url = endpoint(
      ["api", "v1", "mediaserver", "stream-info"],
      queryItems: queryItems)
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      let cookieHeader = response.value(forHTTPHeaderField: "Set-Cookie"),
      let cookie = HTTPCookie.cookies(
        withResponseHeaderFields: ["Set-Cookie": cookieHeader], for: url
      ).first,
      data.count <= 1_048_576
    else { throw MediaPlaybackError.unavailable }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard
      let envelope = try? decoder.decode(
        MediaPlaybackEnvelope<MediaPlaybackManifest>.self, from: data),
      envelope.success, let manifest = envelope.data,
      manifest.itemId == itemId,
      manifest.mediaType == nil || manifest.mediaType == "video" || manifest.mediaType == "audio",
      isTrustedMediaURL(
        manifest.contentUrl, itemId: itemId, server: server, mediaSourceId: mediaSourceId)
    else { throw MediaPlaybackError.unavailable }
    resourceCookie = cookie
    guard
      manifest.subtitles.allSatisfy({
        isTrustedSubtitleURL($0.url, itemId: itemId, server: server)
      })
    else {
      throw MediaPlaybackError.unavailable
    }
    if let lyricsURL = manifest.lyricsUrl,
      !isTrustedLyricsURL(lyricsURL, itemId: itemId, server: server)
    {
      throw MediaPlaybackError.unavailable
    }
    return manifest
  }

  /// 尽力将当前播放位置和状态异步回传给媒体服务器（不阻塞交互、失败静默忽略）。
  func reportProgress(
    itemId: String,
    server: String?,
    mediaSourceId: String?,
    positionMs: Int,
    durationMs: Int?,
    isPaused: Bool,
    state: String
  ) async {
    guard let server, !server.isEmpty, !itemId.isEmpty, !itemId.hasPrefix("file.") else { return }
    let url = endpoint(["api", "v1", "mediaserver", "progress"])
    var payload: [String: Any] = [
      "item_id": itemId,
      "server": server,
      "position_ms": max(0, positionMs),
      "is_paused": isPaused,
      "state": state,
    ]
    if let mediaSourceId, !mediaSourceId.isEmpty { payload["media_source_id"] = mediaSourceId }
    if let durationMs, durationMs > 0 { payload["duration_ms"] = durationMs }
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    _ = try? await session.data(for: request)
  }

  /// 下载所选外挂字幕到 App 临时目录，避免把账号令牌放进播放器 URL。
  func download(_ subtitle: MediaPlaybackSubtitle, itemId: String) async throws -> URL {
    guard isTrustedSubtitleURL(subtitle.url, itemId: itemId, server: selectedServer) else {
      throw MediaPlaybackError.unavailable
    }
    var request = URLRequest(url: subtitle.url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      response.expectedContentLength <= 16 * 1024 * 1024
    else { throw MediaPlaybackError.subtitleUnavailable }
    var data = Data()
    data.reserveCapacity(Int(max(0, response.expectedContentLength)))
    for try await byte in bytes {
      guard data.count < 16 * 1024 * 1024 else { throw MediaPlaybackError.subtitleUnavailable }
      data.append(byte)
    }
    guard !data.isEmpty else { throw MediaPlaybackError.subtitleUnavailable }
    let idExt = (subtitle.subtitleId as NSString).pathExtension.lowercased()
    let urlExt = subtitle.url.pathExtension.lowercased()
    let allowedExts: Set<String> = ["srt", "ass", "ssa", "vtt", "smi", "sub"]
    let ext = allowedExts.contains(idExt) ? idExt : (allowedExts.contains(urlExt) ? urlExt : "srt")
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("moviepilot-\(UUID().uuidString)")
      .appendingPathExtension(ext)
    try data.write(to: fileURL, options: .atomic)
    return fileURL
  }

  /// 下载当前音频的同源 LRC 文本，并限制大小和字符集以控制内存使用。
  func downloadLyrics(_ url: URL, itemId: String) async throws -> String {
    guard isTrustedLyricsURL(url, itemId: itemId, server: selectedServer) else {
      throw MediaPlaybackError.lyricsUnavailable
    }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      !data.isEmpty, data.count <= 2 * 1024 * 1024
    else { throw MediaPlaybackError.lyricsUnavailable }
    if let text = String(data: data, encoding: .utf8) { return text }
    if let text = String(data: data, encoding: .utf16) { return text }
    throw MediaPlaybackError.lyricsUnavailable
  }

  /// 仅从当前实例图片代理读取限长封面，并缩小解码以适配原生 Now Playing 视图。
  func downloadArtwork(_ url: URL) async throws -> UIImage {
    guard isTrustedArtworkURL(url) else { throw MediaPlaybackError.artworkUnavailable }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("image/avif,image/webp,image/png,image/jpeg", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      let responseURL = response.url, isTrustedArtworkURL(responseURL),
      response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true,
      !data.isEmpty, data.count <= 8 * 1024 * 1024,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width <= 16_384, height <= 16_384, width * height <= 80_000_000,
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 960,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    else { throw MediaPlaybackError.artworkUnavailable }
    return UIImage(cgImage: image)
  }

  /// 通过音乐曲目元数据匹配媒体服务器音频流与 LRC 歌词。
  func loadMusicManifest(title: String, artist: String?, album: String?) async throws
    -> MediaPlaybackManifest
  {
    let url = endpoint(["api", "v1", "mediaserver", "stream-info", "music"])
    var payload: [String: String] = ["title": title]
    if let artist, !artist.isEmpty { payload["artist"] = artist }
    if let album, !album.isEmpty { payload["album"] = album }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      let cookieHeader = response.value(forHTTPHeaderField: "Set-Cookie"),
      let cookie = HTTPCookie.cookies(
        withResponseHeaderFields: ["Set-Cookie": cookieHeader], for: url
      ).first,
      data.count <= 1_048_576
    else { throw MediaPlaybackError.unavailable }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard
      let envelope = try? decoder.decode(
        MediaPlaybackEnvelope<MediaPlaybackManifest>.self, from: data),
      envelope.success, let manifest = envelope.data,
      isTrustedMediaURL(manifest.contentUrl, itemId: manifest.itemId, server: manifest.server)
    else { throw MediaPlaybackError.unavailable }
    selectedServer = manifest.server
    resourceCookie = cookie
    return manifest
  }

  /// 通过当前实例已鉴权的存储下载接口拉取本地或云盘音视频文件至受管临时缓存并构造本地播放清单。
  func loadStorageFileManifest(
    storage: String, path: String, fileName: String, isAudio: Bool
  ) async throws -> MediaPlaybackManifest {
    let url = endpoint(["api", "v1", "storage", "download"])
    let ext = (fileName as NSString).pathExtension
    let payload: [String: String] = [
      "storage": storage,
      "type": "file",
      "path": path,
      "name": fileName,
      "extension": ext,
    ]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)
    let (tempURL, response) = try await session.download(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw MediaPlaybackError.unavailable
    }
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("moviepilot-play-\(UUID().uuidString)")
      .appendingPathExtension(ext.isEmpty ? (isAudio ? "mp3" : "mp4") : ext)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: tempURL, to: destination)
    return MediaPlaybackManifest(
      itemId: "file:\(storage):\(path)",
      server: nil,
      title: fileName,
      contentUrl: destination,
      mediaType: isAudio ? "audio" : "video",
      artist: nil,
      album: nil,
      subtitles: [],
      lyricsUrl: nil
    )
  }

  /// 为解码器构造媒体对象，本地受管文件直接播放，流媒体 URL 将资源 Cookie 限制到当前实例路径。
  func makeMedia(url: URL) throws -> VLCMedia {
    if url.isFileURL {
      guard let media = VLCMedia(url: url) else { throw MediaPlaybackError.unavailable }
      return media
    }
    guard let media = VLCMedia(url: url), let cookie = resourceCookie, let host = url.host,
      media.storeCookie(
        "\(cookie.name)=\(cookie.value)", forHost: host,
        path: url.deletingLastPathComponent().path + "/") == 0
    else { throw MediaPlaybackError.unavailable }
    media.addOption(":network-caching=1500")
    return media
  }

  /// 返回当前实例下指定路径片段对应的 API URL。
  private func endpoint(_ components: [String], queryItems: [URLQueryItem] = []) -> URL {
    let url = components.reduce(address.url) { $0.appending(path: $1) }
    return url.appending(queryItems: queryItems)
  }

  /// 校验媒体地址同源且精确对应所选条目的流接口。
  private func isTrustedMediaURL(
    _ url: URL, itemId: String, server: String?, mediaSourceId: String? = nil
  ) -> Bool {
    guard address.contains(url), url.user == nil, url.password == nil, url.fragment == nil,
      url.path == endpoint(["api", "v1", "mediaserver", "stream"]).path,
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return false }
    let allowedNames: Set<String> = ["itemid", "server", "media_source_id"]
    guard queryItems.allSatisfy({ allowedNames.contains($0.name) }),
      Set(queryItems.map(\.name)).count == queryItems.count,
      queryItems.first(where: { $0.name == "itemid" })?.value == itemId,
      server == nil || queryItems.first(where: { $0.name == "server" })?.value == server,
      mediaSourceId == nil
        || queryItems.first(where: { $0.name == "media_source_id" })?.value == mediaSourceId
    else { return false }
    return true
  }

  /// 校验字幕地址同源且位于当前条目的字幕接口路径下。
  private func isTrustedSubtitleURL(_ url: URL, itemId: String, server: String?) -> Bool {
    guard address.contains(url), url.user == nil, url.password == nil, url.fragment == nil,
      url.path == endpoint(["api", "v1", "mediaserver", "stream-subtitle"]).path,
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return false }
    return queryItems.count == (server == nil ? 2 : 3)
      && queryItems.first(where: { $0.name == "itemid" })?.value == itemId
      && queryItems.first(where: { $0.name == "subtitle_id" })?.value != nil
      && (server == nil || queryItems.first(where: { $0.name == "server" })?.value == server)
  }

  /// 校验歌词地址同源且只指向当前条目的 LRC 歌词路由。
  private func isTrustedLyricsURL(_ url: URL, itemId: String, server: String?) -> Bool {
    guard address.contains(url), url.user == nil, url.password == nil, url.fragment == nil,
      url.path == endpoint(["api", "v1", "mediaserver", "stream-lyrics"]).path,
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return false }
    return queryItems.count == (server == nil ? 1 : 2)
      && queryItems.first(where: { $0.name == "itemid" })?.value == itemId
      && (server == nil || queryItems.first(where: { $0.name == "server" })?.value == server)
  }

  /// 封面只能经当前实例图片代理；源站访问和 DNS 安全校验由后端负责。
  private func isTrustedArtworkURL(_ url: URL) -> Bool {
    guard address.contains(url), url.user == nil, url.password == nil, url.fragment == nil,
      url.path == endpoint(["api", "v1", "system", "img", "0"]).path,
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      (1...5).contains(queryItems.count),
      queryItems.allSatisfy({
        ["imgurl", "cache", "use_cookies", "maxWidth", "quality"].contains($0.name)
      }),
      Set(queryItems.map(\.name)).count == queryItems.count,
      let sourceValue = queryItems.first(where: { $0.name == "imgurl" })?.value,
      let source = URL(string: sourceValue),
      ["http", "https"].contains(source.scheme?.lowercased() ?? ""),
      source.host != nil, source.user == nil, source.password == nil, source.fragment == nil
    else { return false }
    return true
  }
}

/// 网络错误使用固定文案，不回显 URL、令牌、云盘地址或服务器响应正文。
private enum MediaPlaybackError: LocalizedError {
  case unavailable
  case subtitleUnavailable
  case lyricsUnavailable
  case artworkUnavailable

  /// 返回不包含认证信息和上游来源的操作提示。
  var errorDescription: String? {
    switch self {
    case .unavailable: L10n.text("无法读取播放信息，请确认影片仍在媒体库中并检查后台连接。")
    case .subtitleUnavailable: L10n.text("字幕读取失败，请选择其他字幕或检查后台连接。")
    case .lyricsUnavailable: L10n.text("无法读取本地歌词。")
    case .artworkUnavailable: L10n.text("无法读取专辑封面。")
    }
  }
}

/// 托管来自系统文件菜单的安全作用域文件租约，确保播放器解码停止后且至多一次释放权限。
final class SecurityScopedResourceLease: @unchecked Sendable {
  private struct State {
    var active: Bool
  }

  private let url: URL
  private let state: OSAllocatedUnfairLock<State>

  /// 立即申请安全作用域访问权限；非安全作用域文件（如 Inbox 副本）也能安全构造为空租约。
  init(url: URL) {
    self.url = url
    let granted = url.isFileURL ? url.startAccessingSecurityScopedResource() : false
    self.state = OSAllocatedUnfairLock(initialState: State(active: granted))
  }

  /// 幂等释放安全作用域；可在后台解码停止完成后安全调用。
  func release() {
    let shouldStop = state.withLock { state -> Bool in
      guard state.active else { return false }
      state.active = false
      return true
    }
    if shouldStop {
      url.stopAccessingSecurityScopedResource()
    }
  }

  deinit {
    release()
  }
}

/// 使用原生 UIKit 控件驱动 VLCKit，提供影院级视频播放与 Apple Music 质感音乐播放体验，并在独立后台队列安全释放解码器避免返回卡死。
@MainActor
final class MediaPlaybackViewController: UIViewController, UIGestureRecognizerDelegate,
  VLCMediaPlayerDelegate
{
  /// 非实例绑定播放（本地音视频文件与外部直链流）的固定本地进度命名空间。
  static let externalPlaybackNamespace = UUID(
    uuidString: "A7B56C10-5E6F-4C8B-9F72-3F2189D7C001")!
  /// 专用串行后台释放队列，彻底避免 `VLCMediaPlayer.stop()` 与 libVLC vout 线程在主线程互相死锁。
  private static let teardownQueue = DispatchQueue(
    label: "com.moviepilot.playback.teardown", qos: .userInitiated)
  /// 当前活跃播放器数量，防止前一个播放器异步释放时误关闭新开播放器的系统音频会话。
  private static let activeAudioSessions = OSAllocatedUnfairLock(initialState: 0)

  private var manifest: MediaPlaybackManifest
  private let client: MediaPlaybackClient?
  private let instanceId: UUID
  private var itemId: String
  private var displayTitle: String
  private var artworkURL: URL?
  private let initialArtwork: UIImage?
  private let deleteContentFileOnClose: Bool
  private let securityScopeLease: SecurityScopedResourceLease?
  /// 当前播放是否绑定 MoviePilot 服务会话；本地文件与外部直链不随服务切换或登出而中断。
  let isSessionBound: Bool
  private let queue: [MediaPlaybackQueueItem]
  private var queueIndex: Int
  private let player = VLCMediaPlayer(options: ["--no-mouse-events", "--no-keyboard-events"])

  // MARK: - Video Surfaces & Overlays
  private let videoView = UIView()
  private let topScrimView = UIView()
  private let bottomScrimView = UIView()
  private let topScrimLayer = CAGradientLayer()
  private let bottomScrimLayer = CAGradientLayer()
  private let seekHudLabel = UILabel()

  // MARK: - Music Surfaces & Stages
  private let musicAmbientGradient = CAGradientLayer()
  private let musicBackdropImageView = UIImageView()
  private let musicBackdropBlur = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let musicBackdropShade = UIView()
  private let musicGrabber = UIView()
  private let musicStage = UIView()
  private let musicCoverStage = UIView()
  private let musicArtworkShadowView = UIView()
  private let musicArtwork = UIImageView()
  private let musicArtworkPlaceholder = UIImageView(image: UIImage(systemName: "music.note"))
  private let musicTitleLabel = UILabel()
  private let musicArtistLabel = UILabel()
  private let musicAlbumLabel = UILabel()
  private let musicLyricPreviewButton = UIButton(type: .system)

  private let musicLyricsStage = UIView()
  private let musicMiniHeader = UIButton(type: .custom)
  private let musicMiniArtwork = UIImageView()
  private let musicMiniTitleLabel = UILabel()
  private let musicMiniSubtitleLabel = UILabel()
  private let lyricsContainer = UIView()
  private let lyricsFadeMask = CAGradientLayer()
  private let lyricsScroll = UIScrollView()
  private let lyricsStack = UIStackView()

  // MARK: - Shared Controls
  private let controls = UIView()
  private let transport = UIStackView()
  private let topBar = UIStackView()
  private let progressPanel = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let elapsedLabel = UILabel()
  private let durationLabel = UILabel()
  private let loading = UIActivityIndicatorView(style: .large)
  private let titleLabel = UILabel()
  private let playButton = UIButton(type: .system)
  private let skipBackButton = UIButton(type: .system)
  private let skipForwardButton = UIButton(type: .system)

  // Video toolbar & utility buttons
  private let pipTopButton = UIButton(type: .system)
  private let lockTopButton = UIButton(type: .system)
  private let speedButton = UIButton(type: .system)
  private let aspectButton = UIButton(type: .system)
  private let subtitleButton = UIButton(type: .system)
  private let audioButton = UIButton(type: .system)
  private let episodeListButton = UIButton(type: .system)
  private let prevEpisodeButton = UIButton(type: .system)
  private let nextEpisodeButton = UIButton(type: .system)
  private weak var playbackMenuButton: UIButton?

  // Auto-play-next glass countdown card (video episode queue)
  private let upNextOverlay = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let upNextHeaderLabel = UILabel()
  private let upNextTitleLabel = UILabel()
  private let upNextCountdownLabel = UILabel()
  private let upNextPlayButton = UIButton(type: .system)
  private let upNextCancelButton = UIButton(type: .system)
  private var upNextTask: Task<Void, Never>?
  private var upNextDismissedForCurrentItem = false

  // Track preference & progress reporting state
  private var pendingTrackSelection: MediaPlaybackTrackSelection?
  private var appliedAudioSelection = false
  private var appliedSubtitleSelection = false
  private var appliedDefaultRate = false
  private var activeExternalSubtitleID: String?
  private var lastObservedPositionMs = 0
  private var lastObservedDurationMs = 0
  private var hasPlayedCurrentItem = false
  private var lastProgressReportAt: Date = .distantPast
  private var progressReportTask: Task<Void, Never>?

  // Music utility bar buttons
  private let lyricsToggleButton = UIButton(type: .system)
  private let musicQueueButton = UIButton(type: .system)

  private let positionSlider = UISlider()

  // MARK: - State
  private var pictureInPictureAvailable = false
  private var isLocked = false
  private var isAspectFill = UserDefaults.standard.bool(forKey: "nativeV2.playback.aspectFill")
  private var isMinimizedAudio = false
  private var showRemainingTime = false
  private var showsFullLyrics = false
  private var audioSessionClaimed = false
  private var currentPlaybackRate: Float = {
    let saved = UserDefaults.standard.double(forKey: "nativeV2.playback.defaultRate")
    return saved > 0 ? Float(saved) : 1.0
  }()
  private var lastKnownProgress: Double = 0
  private var currentMiniArtworkImage: UIImage?
  var onAudioMiniStateChanged: ((NativeMiniMusicState) -> Void)?
  var isAudioMiniMode: Bool { isAudioPlayback && isMinimizedAudio }
  private let onMinimize: (MediaPlaybackViewController) -> Void
  private let onExpand: (MediaPlaybackViewController) -> Void
  private let onClosePlayback: (MediaPlaybackViewController) -> Void
  private var updateTimer: Timer?
  private var hideControlsTask: Task<Void, Never>?
  private var seekHudTask: Task<Void, Never>?
  private var subtitleTask: Task<Void, Never>?
  private var lyricsTask: Task<Void, Never>?
  private var artworkTask: Task<Void, Never>?
  private var trackSwitchTask: Task<Void, Never>?
  private var nowPlayingArtwork: MPMediaItemArtwork?
  private var subtitleFiles: [URL] = []
  private var activeSubtitleFile: URL?
  private var lyricCues: [MediaPlaybackLyricCue] = []
  private var lyricButtons: [UIButton] = []
  private var activeLyricIndex: Int?
  private var savedProgress: Int?
  private var resumeDecisionPending = false
  private var interruption = PlaybackInterruptionState()
  private var resumePromptShown = false
  private var isScrubbing = false
  private var controlsVisible = true
  private var playbackDidAppear = false
  private var closed = false
  private var lastArtworkScalePlaying: Bool?

  /// 系统画中画复用当前采样层；只有进入成功后才让调度器最小化全屏容器。
  private lazy var pictureInPicture = MediaPictureInPictureController(
    player: player, videoView: videoView,
    onStart: { [weak self] in
      guard let self, !self.closed else { return }
      self.hideControlsTask?.cancel()
      self.onMinimize(self)
    },
    onRestore: { [weak self] in
      guard let self, !self.closed else { return }
      self.onExpand(self)
      self.showControls()
    },
    onStop: { [weak self] restored in
      guard let self, !self.closed else { return }
      if restored { self.showControls() } else { self.closeFromShell() }
    },
    onAvailability: { [weak self] available in
      self?.updatePictureInPictureAvailability(available)
    },
    onFailure: { [weak self] in
      self?.showError(L10n.text("暂时无法开启画中画，请等待视频开始播放后重试。"))
    })

  /// 清单显式声明音频时展示音乐播放器；兼容旧服务响应仍按视频处理。
  private var isAudioPlayback: Bool { manifest.mediaType == "audio" }

  /// 建立单条目、队列或独立本地/外部流播放器，进度按服务实例和媒体条目隔离在本机保存。
  init(
    manifest: MediaPlaybackManifest,
    client: MediaPlaybackClient?,
    instanceId: UUID,
    itemId: String,
    displayTitle: String,
    artworkURL: URL? = nil,
    initialArtwork: UIImage? = nil,
    queue: [MediaPlaybackQueueItem] = [],
    queueIndex: Int = 0,
    initialTrackSelection: MediaPlaybackTrackSelection? = nil,
    deleteContentFileOnClose: Bool = false,
    securityScopeLease: SecurityScopedResourceLease? = nil,
    onMinimize: @escaping (MediaPlaybackViewController) -> Void,
    onExpand: @escaping (MediaPlaybackViewController) -> Void,
    onClosePlayback: @escaping (MediaPlaybackViewController) -> Void
  ) {
    self.manifest = manifest
    self.client = client
    self.isSessionBound = client != nil
    self.instanceId = instanceId
    self.itemId = itemId
    self.displayTitle = displayTitle
    self.artworkURL = artworkURL
    self.initialArtwork = initialArtwork
    self.deleteContentFileOnClose = deleteContentFileOnClose
    self.securityScopeLease = securityScopeLease
    self.queue = queue
    self.queueIndex = queue.indices.contains(queueIndex) ? queueIndex : 0
    self.pendingTrackSelection = initialTrackSelection
    self.onMinimize = onMinimize
    self.onExpand = onExpand
    self.onClosePlayback = onClosePlayback
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  /// 播放器只由原生控制器创建，不支持 storyboard 解码。
  required init?(coder: NSCoder) {
    fatalError("Use init(manifest:client:instanceId:itemId:displayTitle:)")
  }

  /// 当前页面进入全屏播放并创建系统控制与播放会话。
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    showRemainingTime = isAudioPlayback
    configureViews()
    guard configurePlayer() else { return }
    configureAudioSession()
    configureRemoteCommands()
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshPlaybackState() }
    }
    player.play()
    if isAudioPlayback {
      if let initialArtwork {
        applyResolvedArtwork(initialArtwork, animated: false)
      }
      loadLyrics()
      loadArtwork()
    }
  }

  /// 同步渐变遮罩、背景渐变、歌词羽化蒙版与横屏锁屏按钮可见性。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if isAudioPlayback {
      musicAmbientGradient.frame = view.bounds
      lyricsFadeMask.frame = lyricsContainer.bounds
    } else {
      topScrimLayer.frame = topScrimView.bounds
      bottomScrimLayer.frame = bottomScrimView.bounds
      if isAspectFill { applyAspectMode() }
      updateLockButtonVisibilityForOrientation()
    }
  }

  /// 恢复全屏后重新启用视频控制栏自动隐藏。
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    playbackDidAppear = true
    scheduleControlsHide()
  }

  /// 音乐优先竖屏沉浸、全屏视频支持横竖屏自由旋转。
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

  /// 沉浸播放页始终使用浅色状态栏图标。
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  /// 全屏视频隐藏控制栏时一并隐藏状态栏，获得真正影院沉浸感。
  override var prefersStatusBarHidden: Bool { !isAudioPlayback && !controlsVisible }

  /// 全屏视频播放时自动弱化底部 Home 指示条。
  override var prefersHomeIndicatorAutoHidden: Bool { !isAudioPlayback }

  /// 控制器真正脱离窗口时（且非画中画保活及非音乐最小化收起）安全释放资源。
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isMovingFromParent
      || (view.window == nil && !pictureInPicture.keepsPlaybackAlive && !isMinimizedAudio)
    {
      closePlayback()
    }
  }

  // MARK: - View Hierarchy Setup

  /// 创建视频画布或音乐沉浸舞台、顶栏、底部控制坞与交互手势。
  private func configureViews() {
    if isAudioPlayback {
      configureMusicBackdrop()
    } else {
      configureVideoSurfaceAndScrims()
    }

    loading.translatesAutoresizingMaskIntoConstraints = false
    loading.color = .white
    loading.hidesWhenStopped = true
    view.addSubview(loading)
    if isAudioPlayback {
      NSLayoutConstraint.activate([
        loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        loading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 62),
      ])
      loading.style = .medium
    } else {
      NSLayoutConstraint.activate([
        loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
    }
    loading.startAnimating()

    configureTopBar()
    configureControls()

    if isAudioPlayback {
      configureMusicStage(below: topBar)
      let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
      swipeDown.direction = .down
      swipeDown.delegate = self
      view.addGestureRecognizer(swipeDown)
    } else {
      configureVideoGesturesAndHud()
    }
  }

  /// 视频渲染层及上下边缘柔和渐暗遮罩（保障亮画面下的控制可读性）。
  private func configureVideoSurfaceAndScrims() {
    videoView.translatesAutoresizingMaskIntoConstraints = false
    videoView.backgroundColor = .black
    videoView.isUserInteractionEnabled = false
    videoView.accessibilityLabel = L10n.text("视频画面")
    videoView.isAccessibilityElement = true
    view.addSubview(videoView)

    topScrimView.translatesAutoresizingMaskIntoConstraints = false
    topScrimView.isUserInteractionEnabled = false
    topScrimLayer.colors = [
      UIColor.black.withAlphaComponent(0.72).cgColor,
      UIColor.black.withAlphaComponent(0.24).cgColor,
      UIColor.clear.cgColor,
    ]
    topScrimLayer.locations = [0, 0.65, 1]
    topScrimView.layer.addSublayer(topScrimLayer)
    view.addSubview(topScrimView)

    bottomScrimView.translatesAutoresizingMaskIntoConstraints = false
    bottomScrimView.isUserInteractionEnabled = false
    bottomScrimLayer.colors = [
      UIColor.clear.cgColor,
      UIColor.black.withAlphaComponent(0.32).cgColor,
      UIColor.black.withAlphaComponent(0.80).cgColor,
    ]
    bottomScrimLayer.locations = [0, 0.42, 1]
    bottomScrimView.layer.addSublayer(bottomScrimLayer)
    view.addSubview(bottomScrimView)

    NSLayoutConstraint.activate([
      videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      videoView.topAnchor.constraint(equalTo: view.topAnchor),
      videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      topScrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      topScrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      topScrimView.topAnchor.constraint(equalTo: view.topAnchor),
      topScrimView.heightAnchor.constraint(equalToConstant: 132),

      bottomScrimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottomScrimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottomScrimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      bottomScrimView.heightAnchor.constraint(equalToConstant: 124),
    ])
  }

  /// 顶栏：返回键、片名/正在播放标题，以及视频画中画/锁屏/更多菜单或音乐队列菜单。
  private func configureTopBar() {
    if isAudioPlayback {
      musicGrabber.translatesAutoresizingMaskIntoConstraints = false
      musicGrabber.backgroundColor = UIColor.white.withAlphaComponent(0.28)
      musicGrabber.layer.cornerRadius = 2.5
      view.addSubview(musicGrabber)
      NSLayoutConstraint.activate([
        musicGrabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        musicGrabber.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
        musicGrabber.widthAnchor.constraint(equalToConstant: 38),
        musicGrabber.heightAnchor.constraint(equalToConstant: 5),
      ])
    }

    titleLabel.textColor = .white
    titleLabel.font =
      isAudioPlayback
      ? .systemFont(ofSize: 13, weight: .semibold)
      : .systemFont(ofSize: 17, weight: .semibold)
    titleLabel.numberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.textAlignment = isAudioPlayback ? .center : .left
    titleLabel.text =
      isAudioPlayback
      ? ((manifest.album?.isEmpty == false ? manifest.album : nil) ?? L10n.text("正在播放"))
      : displayTitle
    titleLabel.alpha = isAudioPlayback ? 0.78 : 1.0
    titleLabel.layer.shadowColor = UIColor.black.cgColor
    titleLabel.layer.shadowOpacity = isAudioPlayback ? 0 : 0.55
    titleLabel.layer.shadowRadius = 4
    titleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
    titleLabel.accessibilityIdentifier = "playback-title"

    let closeButton = UIButton(type: .system)
    if isAudioPlayback {
      configureMusicCircleButton(
        closeButton, symbol: "chevron.down", accessibility: L10n.text("收起到迷你播放条"), diameter: 40,
        pointSize: 16, primary: false)
      closeButton.accessibilityIdentifier = "music-playback-close"
      closeButton.addAction(
        UIAction { [weak self] _ in self?.minimizeAudioPlayback() }, for: .touchUpInside)
    } else {
      configureGlassButton(
        closeButton, symbol: "chevron.left", accessibility: L10n.text("关闭播放器"), diameter: 42,
        pointSize: 17)
      closeButton.accessibilityIdentifier = "video-playback-close"
      closeButton.addAction(
        UIAction { [weak self] _ in self?.dismissPlayback() }, for: .touchUpInside)
    }

    topBar.axis = .horizontal
    topBar.alignment = .center
    topBar.distribution = .fill
    topBar.spacing = 10
    topBar.translatesAutoresizingMaskIntoConstraints = false

    topBar.addArrangedSubview(fixedSquareControl(closeButton, diameter: isAudioPlayback ? 40 : 42))
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    topBar.addArrangedSubview(titleLabel)

    if isAudioPlayback {
      let moreButton = UIButton(type: .system)
      configureMusicCircleButton(
        moreButton, symbol: "ellipsis", accessibility: L10n.text("更多播放选项"), diameter: 40,
        pointSize: 16, primary: false)
      moreButton.showsMenuAsPrimaryAction = true
      playbackMenuButton = moreButton
      moreButton.menu = makeMusicMenu()
      topBar.addArrangedSubview(fixedSquareControl(moreButton, diameter: 40))
    } else {
      // 视频模式右上角一排统一收纳全部功能按钮：字幕、音轨、画面比例、倍速、小窗画中画
      let topButtonDiameter: CGFloat = 38
      let topButtonPointSize: CGFloat = 15

      configureGlassButton(
        episodeListButton, symbol: "list.bullet", accessibility: L10n.text("选集"),
        diameter: topButtonDiameter, pointSize: topButtonPointSize)
      episodeListButton.accessibilityIdentifier = "video-playback-episodes"
      episodeListButton.isHidden = queue.count <= 1
      episodeListButton.addAction(
        UIAction { [weak self] _ in self?.showQueueMenu() }, for: .touchUpInside)

      configureGlassButton(
        subtitleButton, symbol: "captions.bubble", accessibility: L10n.text("选择字幕"),
        diameter: topButtonDiameter, pointSize: topButtonPointSize)
      subtitleButton.addAction(
        UIAction { [weak self] _ in self?.showSubtitleMenu() }, for: .touchUpInside)

      configureGlassButton(
        audioButton, symbol: "waveform", accessibility: L10n.text("选择音轨"),
        diameter: topButtonDiameter, pointSize: topButtonPointSize)
      audioButton.addAction(
        UIAction { [weak self] _ in self?.showAudioMenu() }, for: .touchUpInside)

      configureGlassButton(
        aspectButton,
        symbol: isAspectFill
          ? "arrow.down.right.and.arrow.up.left"
          : "arrow.up.left.and.arrow.down.right",
        accessibility: L10n.text("切换画面比例"),
        diameter: topButtonDiameter, pointSize: topButtonPointSize)
      aspectButton.addAction(
        UIAction { [weak self] _ in self?.toggleAspectMode() }, for: .touchUpInside)

      configureGlassButton(
        speedButton, symbol: "gauge.with.dots.needle.67percent",
        accessibility: L10n.text("播放速度"),
        diameter: topButtonDiameter, pointSize: topButtonPointSize)
      speedButton.addAction(
        UIAction { [weak self] _ in self?.showSpeedMenu() }, for: .touchUpInside)

      configureGlassButton(
        pipTopButton, symbol: "pip.enter", accessibility: L10n.text("小窗播放"),
        diameter: topButtonDiameter, pointSize: topButtonPointSize)
      pipTopButton.isHidden = !pictureInPictureAvailable
      pipTopButton.addAction(
        UIAction { [weak self] _ in self?.minimizePlayback() }, for: .touchUpInside)

      let topActionsStack = UIStackView(arrangedSubviews: [
        episodeListButton, subtitleButton, audioButton, aspectButton, speedButton, pipTopButton,
      ])
      topActionsStack.axis = .horizontal
      topActionsStack.alignment = .center
      topActionsStack.spacing = 8
      topActionsStack.setContentHuggingPriority(.required, for: .horizontal)
      topActionsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
      topBar.addArrangedSubview(topActionsStack)
    }

    view.addSubview(topBar)
    NSLayoutConstraint.activate([
      topBar.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      topBar.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      topBar.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor, constant: isAudioPlayback ? 18 : 10),
    ])
  }

  /// 视频播放器双点快进/快退手势、单点显隐控制栏与锁屏解锁胶囊。
  private func configureVideoGesturesAndHud() {
    seekHudLabel.translatesAutoresizingMaskIntoConstraints = false
    seekHudLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    seekHudLabel.textColor = .white
    seekHudLabel.textAlignment = .center
    seekHudLabel.backgroundColor = UIColor.black.withAlphaComponent(0.62)
    seekHudLabel.layer.cornerRadius = 18
    seekHudLabel.layer.cornerCurve = .continuous
    seekHudLabel.layer.borderWidth = 0.7
    seekHudLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.20).cgColor
    seekHudLabel.clipsToBounds = true
    seekHudLabel.alpha = 0
    seekHudLabel.isUserInteractionEnabled = false
    view.addSubview(seekHudLabel)
    NSLayoutConstraint.activate([
      seekHudLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      seekHudLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 22),
      seekHudLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
      seekHudLabel.heightAnchor.constraint(equalToConstant: 36),
    ])

    // 仅横屏显示于右侧居中的纯图标锁屏/解锁按钮（锁定与解锁复用同一位置，无任何文字）
    configureGlassButton(
      lockTopButton, symbol: "lock.open", accessibility: L10n.text("锁定屏幕"), diameter: 44,
      pointSize: 16)
    lockTopButton.translatesAutoresizingMaskIntoConstraints = false
    lockTopButton.isHidden = true
    lockTopButton.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        self.setLocked(!self.isLocked)
      }, for: .touchUpInside)
    view.addSubview(lockTopButton)
    NSLayoutConstraint.activate([
      lockTopButton.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      lockTopButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])

    let doubleTap = UITapGestureRecognizer(
      target: self, action: #selector(handleVideoDoubleTap(_:)))
    doubleTap.numberOfTapsRequired = 2
    doubleTap.delegate = self
    view.addGestureRecognizer(doubleTap)

    let singleTap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
    singleTap.numberOfTapsRequired = 1
    singleTap.delegate = self
    singleTap.cancelsTouchesInView = false
    singleTap.require(toFail: doubleTap)
    view.addGestureRecognizer(singleTap)
  }

  /// 将小窗、字幕、音轨、画面比例和倍速操作集中放在视频右上角菜单。
  private func makePlaybackMenu() -> UIMenu {
    let pipAction = UIAction(
      title: L10n.text("小窗播放"), image: UIImage(systemName: "pip.enter"),
      attributes: pictureInPictureAvailable ? [] : .disabled
    ) { [weak self] _ in
      self?.minimizePlayback()
    }
    let aspectAction = UIAction(
      title: isAspectFill ? L10n.text("画面适应") : L10n.text("画面填充"),
      image: UIImage(
        systemName: isAspectFill
          ? "arrow.down.right.and.arrow.up.left"
          : "arrow.up.left.and.arrow.down.right")
    ) { [weak self] _ in self?.toggleAspectMode() }
    let subtitlesAction = UIAction(
      title: L10n.text("选择字幕"), image: UIImage(systemName: "captions.bubble")
    ) { [weak self] _ in self?.showSubtitleMenu() }
    let audioAction = UIAction(
      title: L10n.text("选择音轨"), image: UIImage(systemName: "waveform")
    ) { [weak self] _ in self?.showAudioMenu() }
    let speedAction = UIAction(
      title: L10n.text("播放速度"), image: UIImage(systemName: "speedometer")
    ) { [weak self] _ in self?.showSpeedMenu() }
    return UIMenu(children: [pipAction, aspectAction, subtitlesAction, audioAction, speedAction])
  }

  /// 音乐右上角菜单：倍速播放与切换剩余时间展示。
  private func makeMusicMenu() -> UIMenu {
    let speedAction = UIAction(
      title: L10n.text("播放速度"), image: UIImage(systemName: "speedometer")
    ) { [weak self] _ in self?.showSpeedMenu() }
    let lyricsAction = UIAction(
      title: showsFullLyrics ? L10n.text("返回封面视图") : L10n.text("全屏歌词视图"),
      image: UIImage(systemName: showsFullLyrics ? "photo" : "quote.bubble")
    ) { [weak self] _ in self?.toggleLyricsMode() }
    let stopAction = UIAction(
      title: L10n.text("停止并关闭"), image: UIImage(systemName: "stop.circle"),
      attributes: .destructive
    ) { [weak self] _ in self?.dismissPlayback() }
    var children: [UIMenuElement] = [lyricsAction, speedAction, stopAction]
    if queue.count > 1 {
      let queueAction = UIAction(
        title: L10n.text("播放队列"), image: UIImage(systemName: "list.bullet")
      ) { [weak self] _ in self?.showQueueMenu() }
      children.insert(queueAction, at: 0)
    }
    return UIMenu(children: children)
  }

  /// 画中画准备好后启用菜单及顶栏快捷按钮。
  private func updatePictureInPictureAvailability(_ available: Bool) {
    guard pictureInPictureAvailable != available else { return }
    pictureInPictureAvailable = available
    pipTopButton.isHidden = !available
    playbackMenuButton?.menu = isAudioPlayback ? makeMusicMenu() : makePlaybackMenu()
  }

  /// 将播放控制固定在正方形触控槽内，阻止玻璃按钮在水平布局里被拉宽。
  private func fixedSquareControl(_ control: UIView, diameter: CGFloat) -> UIView {
    let slot = UIView()
    slot.translatesAutoresizingMaskIntoConstraints = false
    slot.addSubview(control)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([
      slot.widthAnchor.constraint(equalToConstant: diameter),
      slot.heightAnchor.constraint(equalToConstant: diameter),
      control.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
      control.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
      control.topAnchor.constraint(equalTo: slot.topAnchor),
      control.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
    ])
    return slot
  }

  /// 配置音乐页的主播放圆键和玻璃辅助圆键。
  private func configureMusicCircleButton(
    _ button: UIButton, symbol: String, accessibility: String, diameter: CGFloat,
    pointSize: CGFloat, primary: Bool
  ) {
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    if !primary {
      if #available(iOS 26.0, *) {
        configuration = .glass()
      } else {
        configuration = .plain()
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = diameter / 2
        button.layer.borderWidth = 0.7
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
      }
    }
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = primary ? .black : .white
    if primary { configuration.baseBackgroundColor = .white }
    configuration.image = UIImage(systemName: symbol)
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: pointSize, weight: .semibold)
    button.configuration = configuration
    button.accessibilityLabel = accessibility
    button.tintColor = primary ? .black : .white
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: diameter),
      button.heightAnchor.constraint(equalToConstant: diameter),
    ])
  }

  /// 正确更新 iOS 16–26 `UIButton.Configuration` 主播放键图标，避免旧版 `setImage` 丢失字重与着色。
  private func updatePlayButtonSymbol(isPlaying: Bool) {
    let symbol = isPlaying ? "pause.fill" : "play.fill"
    let label = isPlaying ? L10n.text("暂停") : L10n.text("播放")
    playButton.accessibilityLabel = label
    if var config = playButton.configuration {
      config.image = UIImage(systemName: symbol)
      playButton.configuration = config
    } else {
      playButton.setImage(
        UIImage(systemName: symbol)?.withConfiguration(
          UIImage.SymbolConfiguration(pointSize: isAudioPlayback ? 26 : 28, weight: .semibold)),
        for: .normal)
    }
  }

  /// 创建影院控制底栏或 Apple Music 质感播放控制区。
  private func configureControls() {
    controls.translatesAutoresizingMaskIntoConstraints = false
    controls.backgroundColor = .clear
    view.addSubview(controls)
    NSLayoutConstraint.activate([
      controls.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: isAudioPlayback ? 26 : 18),
      controls.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: isAudioPlayback ? -26 : -18),
      controls.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: isAudioPlayback ? -14 : -10),
    ])

    positionSlider.minimumValue = 0
    positionSlider.maximumValue = 1
    positionSlider.accessibilityLabel = L10n.text("播放进度")
    positionSlider.accessibilityIdentifier = "playback-progress"
    positionSlider.minimumTrackTintColor = .white
    positionSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
    positionSlider.setThumbImage(
      UIImage(systemName: "circle.fill")?.withConfiguration(
        UIImage.SymbolConfiguration(pointSize: isAudioPlayback ? 11 : 13, weight: .regular)),
      for: .normal)
    positionSlider.addTarget(self, action: #selector(beginScrubbing), for: .touchDown)
    positionSlider.addTarget(self, action: #selector(scrubbingChanged), for: .valueChanged)
    positionSlider.addTarget(
      self, action: #selector(endScrubbing), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    positionSlider.heightAnchor.constraint(equalToConstant: 26).isActive = true

    elapsedLabel.text = Self.format(milliseconds: 0)
    durationLabel.text = Self.format(milliseconds: 0)
    for label in [elapsedLabel, durationLabel] {
      label.textColor = UIColor.white.withAlphaComponent(0.84)
      label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
      label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    durationLabel.isUserInteractionEnabled = true
    durationLabel.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(toggleRemainingTime)))

    if isAudioPlayback {
      configureAudioControlsLayout()
    } else {
      configureVideoControlsLayout()
    }
    refreshQueueControls(current: 0)
  }

  /// Apple Music 风格音频控制区：纤细进度条 + 下方双侧时间 + 三键主控 + 底部歌词/AirPlay/队列工具栏。
  private func configureAudioControlsLayout() {
    let timeRow = UIStackView(arrangedSubviews: [elapsedLabel, UIView(), durationLabel])
    timeRow.axis = .horizontal
    timeRow.alignment = .center

    let progressStack = UIStackView(arrangedSubviews: [positionSlider, timeRow])
    progressStack.axis = .vertical
    progressStack.spacing = 4
    progressStack.translatesAutoresizingMaskIntoConstraints = false

    configureMusicCircleButton(
      skipBackButton, symbol: "backward.fill", accessibility: L10n.text("上一首"),
      diameter: 50, pointSize: 20, primary: false)
    skipBackButton.accessibilityIdentifier = "music-playback-back"
    configureMusicCircleButton(
      playButton, symbol: "pause.fill", accessibility: L10n.text("暂停"),
      diameter: 70, pointSize: 26, primary: true)
    playButton.accessibilityIdentifier = "music-playback-toggle"
    configureMusicCircleButton(
      skipForwardButton, symbol: "forward.fill", accessibility: L10n.text("下一首"),
      diameter: 50, pointSize: 20, primary: false)
    skipForwardButton.accessibilityIdentifier = "music-playback-forward"

    skipBackButton.addAction(
      UIAction { [weak self] _ in self?.playPreviousTrack() }, for: .touchUpInside)
    playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
    skipForwardButton.addAction(
      UIAction { [weak self] _ in self?.playNextTrack() }, for: .touchUpInside)

    transport.axis = .horizontal
    transport.alignment = .center
    transport.distribution = .equalSpacing
    transport.spacing = 30
    transport.translatesAutoresizingMaskIntoConstraints = false
    transport.addArrangedSubview(fixedSquareControl(skipBackButton, diameter: 50))
    transport.addArrangedSubview(fixedSquareControl(playButton, diameter: 70))
    transport.addArrangedSubview(fixedSquareControl(skipForwardButton, diameter: 50))

    // 底部三联实用按钮：歌词视图切换、AirPlay 输出、队列/倍速
    configureMusicUtilityButton(
      lyricsToggleButton, symbol: "quote.bubble", accessibility: L10n.text("切换全屏歌词"))
    lyricsToggleButton.accessibilityIdentifier = "music-playback-lyrics-toggle"
    lyricsToggleButton.addAction(
      UIAction { [weak self] _ in self?.toggleLyricsMode() }, for: .touchUpInside)

    let routePicker = AVRoutePickerView()
    routePicker.activeTintColor = .white
    routePicker.tintColor = UIColor.white.withAlphaComponent(0.78)
    routePicker.accessibilityIdentifier = "music-playback-output"

    configureMusicUtilityButton(
      musicQueueButton,
      symbol: queue.count > 1 ? "list.bullet" : "speedometer",
      accessibility: queue.count > 1 ? L10n.text("播放队列") : L10n.text("播放速度"))
    musicQueueButton.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        if self.queue.count > 1 { self.showQueueMenu() } else { self.showSpeedMenu() }
      }, for: .touchUpInside)

    let utilityBar = UIStackView(arrangedSubviews: [
      fixedSquareControl(lyricsToggleButton, diameter: 42),
      UIView(),
      fixedSquareControl(routePicker, diameter: 42),
      UIView(),
      fixedSquareControl(musicQueueButton, diameter: 42),
    ])
    utilityBar.axis = .horizontal
    utilityBar.alignment = .center

    let rootStack = UIStackView(arrangedSubviews: [progressStack, transport, utilityBar])
    rootStack.axis = .vertical
    rootStack.alignment = .center
    rootStack.spacing = 20
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    controls.addSubview(rootStack)
    NSLayoutConstraint.activate([
      rootStack.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: controls.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: controls.bottomAnchor),
      progressStack.widthAnchor.constraint(equalTo: controls.widthAnchor),
      utilityBar.widthAnchor.constraint(equalTo: controls.widthAnchor, multiplier: 0.78),
    ])
  }

  /// 影院视频控制布局：居中平衡三键 + 底部统一玻璃进度与功能坞（倍速/比例/字幕/音轨）。
  private func configureVideoControlsLayout() {
    configureGlassButton(
      prevEpisodeButton, symbol: "backward.end.fill", accessibility: L10n.text("上一集"),
      diameter: 46, pointSize: 17)
    prevEpisodeButton.accessibilityIdentifier = "video-playback-prev-episode"
    configureGlassButton(
      skipBackButton, symbol: "gobackward.10", accessibility: L10n.text("后退 10 秒"),
      diameter: 54, pointSize: 20)
    configureGlassButton(
      playButton, symbol: "pause.fill", accessibility: L10n.text("暂停"),
      diameter: 68, pointSize: 27)
    configureGlassButton(
      skipForwardButton, symbol: "goforward.10", accessibility: L10n.text("前进 10 秒"),
      diameter: 54, pointSize: 20)
    configureGlassButton(
      nextEpisodeButton, symbol: "forward.end.fill", accessibility: L10n.text("下一集"),
      diameter: 46, pointSize: 17)
    nextEpisodeButton.accessibilityIdentifier = "video-playback-next-episode"

    prevEpisodeButton.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        self.switchTrack(at: self.queueIndex - 1)
      }, for: .touchUpInside)
    skipBackButton.addAction(
      UIAction { [weak self] _ in self?.skip(seconds: -10, showHud: true) }, for: .touchUpInside)
    playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
    skipForwardButton.addAction(
      UIAction { [weak self] _ in self?.skip(seconds: 10, showHud: true) }, for: .touchUpInside)
    nextEpisodeButton.addAction(
      UIAction { [weak self] _ in self?.playNextTrack() }, for: .touchUpInside)

    transport.axis = .horizontal
    transport.alignment = .center
    transport.distribution = .fill
    transport.spacing = queue.count > 1 ? 18 : 28
    transport.translatesAutoresizingMaskIntoConstraints = false
    if queue.count > 1 {
      transport.addArrangedSubview(fixedSquareControl(prevEpisodeButton, diameter: 46))
    }
    transport.addArrangedSubview(fixedSquareControl(skipBackButton, diameter: 54))
    transport.addArrangedSubview(fixedSquareControl(playButton, diameter: 68))
    transport.addArrangedSubview(fixedSquareControl(skipForwardButton, diameter: 54))
    if queue.count > 1 {
      transport.addArrangedSubview(fixedSquareControl(nextEpisodeButton, diameter: 46))
    }
    view.addSubview(transport)
    NSLayoutConstraint.activate([
      transport.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      transport.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])

    configureUpNextOverlay()

    let progressRow = UIStackView(arrangedSubviews: [elapsedLabel, positionSlider, durationLabel])
    progressRow.axis = .horizontal
    progressRow.alignment = .center
    progressRow.spacing = 10
    progressRow.translatesAutoresizingMaskIntoConstraints = false

    // 底部极简：仅保留单行玻璃进度条，功能按钮全部收纳在右上角一排
    progressPanel.layer.cornerRadius = 22
    progressPanel.layer.cornerCurve = .continuous
    progressPanel.layer.borderWidth = 0.7
    progressPanel.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
    progressPanel.clipsToBounds = true
    progressPanel.translatesAutoresizingMaskIntoConstraints = false
    progressPanel.contentView.addSubview(progressRow)
    controls.addSubview(progressPanel)

    NSLayoutConstraint.activate([
      progressRow.leadingAnchor.constraint(
        equalTo: progressPanel.contentView.leadingAnchor, constant: 14),
      progressRow.trailingAnchor.constraint(
        equalTo: progressPanel.contentView.trailingAnchor, constant: -14),
      progressRow.topAnchor.constraint(equalTo: progressPanel.contentView.topAnchor, constant: 10),
      progressRow.bottomAnchor.constraint(
        equalTo: progressPanel.contentView.bottomAnchor, constant: -10),
      progressPanel.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
      progressPanel.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
      progressPanel.topAnchor.constraint(equalTo: controls.topAnchor),
      progressPanel.bottomAnchor.constraint(equalTo: controls.bottomAnchor),
    ])
  }

  /// 极简视频底部纯图标按钮（无文字标签，保持画面通透克制）。
  private func configureVideoIconDockButton(
    _ button: UIButton, symbol: String, accessibility: String
  ) {
    var config = UIButton.Configuration.plain()
    config.baseForegroundColor = UIColor.white.withAlphaComponent(0.90)
    config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
    config.image = UIImage(
      systemName: symbol,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
    button.configuration = config
    button.accessibilityLabel = accessibility
  }

  /// 音乐底部实用图标键（歌词/队列/倍速）。
  private func configureMusicUtilityButton(
    _ button: UIButton, symbol: String, accessibility: String
  ) {
    var config = UIButton.Configuration.plain()
    config.baseForegroundColor = UIColor.white.withAlphaComponent(0.76)
    config.image = UIImage(
      systemName: symbol,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium))
    button.configuration = config
    button.accessibilityLabel = accessibility
  }

  /// 为音乐播放页铺设深紫蓝大气基底、封面模糊氛围背景与柔和暗化层。
  private func configureMusicBackdrop() {
    musicAmbientGradient.colors = [
      UIColor(red: 0.16, green: 0.13, blue: 0.28, alpha: 1).cgColor,
      UIColor(red: 0.10, green: 0.11, blue: 0.20, alpha: 1).cgColor,
      UIColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1).cgColor,
    ]
    musicAmbientGradient.startPoint = CGPoint(x: 0.1, y: 0)
    musicAmbientGradient.endPoint = CGPoint(x: 0.9, y: 1)
    view.layer.addSublayer(musicAmbientGradient)

    musicBackdropImageView.translatesAutoresizingMaskIntoConstraints = false
    musicBackdropImageView.contentMode = .scaleAspectFill
    musicBackdropImageView.clipsToBounds = true
    musicBackdropImageView.alpha = 0
    musicBackdropImageView.accessibilityIdentifier = "music-playback-backdrop"
    view.addSubview(musicBackdropImageView)

    musicBackdropBlur.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(musicBackdropBlur)

    musicBackdropShade.translatesAutoresizingMaskIntoConstraints = false
    musicBackdropShade.backgroundColor = UIColor.black.withAlphaComponent(0.36)
    view.addSubview(musicBackdropShade)

    NSLayoutConstraint.activate([
      musicBackdropImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      musicBackdropImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      musicBackdropImageView.topAnchor.constraint(equalTo: view.topAnchor),
      musicBackdropImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      musicBackdropBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      musicBackdropBlur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      musicBackdropBlur.topAnchor.constraint(equalTo: view.topAnchor),
      musicBackdropBlur.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      musicBackdropShade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      musicBackdropShade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      musicBackdropShade.topAnchor.constraint(equalTo: view.topAnchor),
      musicBackdropShade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  /// 双模式音乐主舞台：默认展示高质感悬浮专辑大封面 + 曲目信息 + 单行动态歌词预览；一键平滑切入全屏同步歌词滚动舞台。
  private func configureMusicStage(below topBar: UIView) {
    musicStage.translatesAutoresizingMaskIntoConstraints = false
    musicStage.accessibilityIdentifier = "music-playback-stage"
    view.addSubview(musicStage)
    NSLayoutConstraint.activate([
      musicStage.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
      musicStage.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
      musicStage.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
      musicStage.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -14),
    ])

    // MARK: 封面主舞台
    musicCoverStage.translatesAutoresizingMaskIntoConstraints = false
    musicStage.addSubview(musicCoverStage)

    musicArtworkShadowView.translatesAutoresizingMaskIntoConstraints = false
    musicArtworkShadowView.layer.shadowColor = UIColor.black.cgColor
    musicArtworkShadowView.layer.shadowOpacity = 0.52
    musicArtworkShadowView.layer.shadowRadius = 26
    musicArtworkShadowView.layer.shadowOffset = CGSize(width: 0, height: 14)

    musicArtwork.translatesAutoresizingMaskIntoConstraints = false
    musicArtwork.accessibilityIdentifier = "music-playback-artwork"
    musicArtwork.accessibilityLabel = L10n.text("专辑封面")
    musicArtwork.isAccessibilityElement = true
    musicArtwork.accessibilityValue = L10n.text("专辑封面加载中")
    musicArtwork.backgroundColor = UIColor.white.withAlphaComponent(0.11)
    musicArtwork.contentMode = .scaleAspectFill
    musicArtwork.clipsToBounds = true
    musicArtwork.layer.cornerRadius = 20
    musicArtwork.layer.cornerCurve = .continuous
    musicArtwork.layer.borderWidth = 0.7
    musicArtwork.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
    musicArtworkShadowView.addSubview(musicArtwork)

    musicArtworkPlaceholder.translatesAutoresizingMaskIntoConstraints = false
    musicArtworkPlaceholder.tintColor = UIColor.white.withAlphaComponent(0.68)
    musicArtworkPlaceholder.contentMode = .scaleAspectFit
    musicArtwork.addSubview(musicArtworkPlaceholder)

    musicTitleLabel.text = displayTitle
    musicTitleLabel.font = .systemFont(ofSize: 23, weight: .bold)
    musicTitleLabel.textColor = .white
    musicTitleLabel.textAlignment = .left
    musicTitleLabel.numberOfLines = 2
    musicTitleLabel.accessibilityIdentifier = "music-playback-title"

    let subtitleText = [manifest.artist, manifest.album]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " — ")
    musicArtistLabel.text = subtitleText.isEmpty ? L10n.text("未知艺人") : subtitleText
    musicArtistLabel.font = .systemFont(ofSize: 16, weight: .medium)
    musicArtistLabel.textColor = UIColor.white.withAlphaComponent(0.72)
    musicArtistLabel.textAlignment = .left
    musicArtistLabel.numberOfLines = 1

    musicAlbumLabel.isHidden = true

    var previewConfig = UIButton.Configuration.plain()
    previewConfig.baseForegroundColor = UIColor.white.withAlphaComponent(0.84)
    previewConfig.contentInsets = NSDirectionalEdgeInsets(
      top: 7, leading: 12, bottom: 7, trailing: 12)
    musicLyricPreviewButton.configuration = previewConfig
    musicLyricPreviewButton.backgroundColor = UIColor.white.withAlphaComponent(0.09)
    musicLyricPreviewButton.layer.cornerRadius = 12
    musicLyricPreviewButton.layer.cornerCurve = .continuous
    musicLyricPreviewButton.contentHorizontalAlignment = .leading
    musicLyricPreviewButton.isHidden = true
    musicLyricPreviewButton.addAction(
      UIAction { [weak self] _ in self?.toggleLyricsMode() }, for: .touchUpInside)

    let metadataStack = UIStackView(arrangedSubviews: [
      musicTitleLabel, musicArtistLabel, musicLyricPreviewButton,
    ])
    metadataStack.axis = .vertical
    metadataStack.alignment = .fill
    metadataStack.spacing = 6
    metadataStack.setCustomSpacing(12, after: musicArtistLabel)
    metadataStack.translatesAutoresizingMaskIntoConstraints = false

    let artworkContainer = UIView()
    artworkContainer.translatesAutoresizingMaskIntoConstraints = false
    artworkContainer.addSubview(musicArtworkShadowView)

    musicCoverStage.addSubview(artworkContainer)
    musicCoverStage.addSubview(metadataStack)

    let preferredArtWidth = musicArtworkShadowView.widthAnchor.constraint(
      equalTo: artworkContainer.widthAnchor, multiplier: 0.92)
    preferredArtWidth.priority = .defaultHigh

    NSLayoutConstraint.activate([
      musicCoverStage.leadingAnchor.constraint(equalTo: musicStage.leadingAnchor),
      musicCoverStage.trailingAnchor.constraint(equalTo: musicStage.trailingAnchor),
      musicCoverStage.topAnchor.constraint(equalTo: musicStage.topAnchor),
      musicCoverStage.bottomAnchor.constraint(equalTo: musicStage.bottomAnchor),

      artworkContainer.leadingAnchor.constraint(equalTo: musicCoverStage.leadingAnchor),
      artworkContainer.trailingAnchor.constraint(equalTo: musicCoverStage.trailingAnchor),
      artworkContainer.topAnchor.constraint(equalTo: musicCoverStage.topAnchor, constant: 6),
      artworkContainer.bottomAnchor.constraint(equalTo: metadataStack.topAnchor, constant: -20),

      musicArtworkShadowView.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
      musicArtworkShadowView.centerYAnchor.constraint(equalTo: artworkContainer.centerYAnchor),
      preferredArtWidth,
      musicArtworkShadowView.widthAnchor.constraint(lessThanOrEqualToConstant: 316),
      musicArtworkShadowView.heightAnchor.constraint(equalTo: musicArtworkShadowView.widthAnchor),
      musicArtworkShadowView.heightAnchor.constraint(
        lessThanOrEqualTo: artworkContainer.heightAnchor),

      musicArtwork.leadingAnchor.constraint(equalTo: musicArtworkShadowView.leadingAnchor),
      musicArtwork.trailingAnchor.constraint(equalTo: musicArtworkShadowView.trailingAnchor),
      musicArtwork.topAnchor.constraint(equalTo: musicArtworkShadowView.topAnchor),
      musicArtwork.bottomAnchor.constraint(equalTo: musicArtworkShadowView.bottomAnchor),

      musicArtworkPlaceholder.centerXAnchor.constraint(equalTo: musicArtwork.centerXAnchor),
      musicArtworkPlaceholder.centerYAnchor.constraint(equalTo: musicArtwork.centerYAnchor),
      musicArtworkPlaceholder.widthAnchor.constraint(equalToConstant: 64),
      musicArtworkPlaceholder.heightAnchor.constraint(equalToConstant: 72),

      metadataStack.leadingAnchor.constraint(equalTo: musicCoverStage.leadingAnchor),
      metadataStack.trailingAnchor.constraint(equalTo: musicCoverStage.trailingAnchor),
      metadataStack.bottomAnchor.constraint(equalTo: musicCoverStage.bottomAnchor, constant: -4),
    ])

    // MARK: 全屏歌词舞台（默认隐藏，点击歌词图标或单行预览平滑切换）
    musicLyricsStage.translatesAutoresizingMaskIntoConstraints = false
    musicLyricsStage.alpha = 0
    musicLyricsStage.isHidden = true
    musicStage.addSubview(musicLyricsStage)

    musicMiniArtwork.translatesAutoresizingMaskIntoConstraints = false
    musicMiniArtwork.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    musicMiniArtwork.contentMode = .scaleAspectFill
    musicMiniArtwork.clipsToBounds = true
    musicMiniArtwork.layer.cornerRadius = 10
    musicMiniArtwork.layer.cornerCurve = .continuous

    musicMiniTitleLabel.text = displayTitle
    musicMiniTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    musicMiniTitleLabel.textColor = .white
    musicMiniTitleLabel.numberOfLines = 1

    musicMiniSubtitleLabel.text = musicArtistLabel.text
    musicMiniSubtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
    musicMiniSubtitleLabel.textColor = UIColor.white.withAlphaComponent(0.68)
    musicMiniSubtitleLabel.numberOfLines = 1

    let miniTextStack = UIStackView(arrangedSubviews: [musicMiniTitleLabel, musicMiniSubtitleLabel])
    miniTextStack.axis = .vertical
    miniTextStack.spacing = 2
    miniTextStack.isUserInteractionEnabled = false

    let miniRow = UIStackView(arrangedSubviews: [musicMiniArtwork, miniTextStack])
    miniRow.axis = .horizontal
    miniRow.alignment = .center
    miniRow.spacing = 12
    miniRow.translatesAutoresizingMaskIntoConstraints = false
    miniRow.isUserInteractionEnabled = false

    musicMiniHeader.translatesAutoresizingMaskIntoConstraints = false
    musicMiniHeader.addSubview(miniRow)
    musicMiniHeader.addAction(
      UIAction { [weak self] _ in self?.toggleLyricsMode() }, for: .touchUpInside)

    lyricsContainer.translatesAutoresizingMaskIntoConstraints = false
    lyricsFadeMask.colors = [
      UIColor.clear.cgColor,
      UIColor.white.cgColor,
      UIColor.white.cgColor,
      UIColor.clear.cgColor,
    ]
    lyricsFadeMask.locations = [0, 0.10, 0.88, 1]
    lyricsContainer.layer.mask = lyricsFadeMask

    lyricsScroll.translatesAutoresizingMaskIntoConstraints = false
    lyricsScroll.showsVerticalScrollIndicator = false
    lyricsScroll.accessibilityIdentifier = "music-playback-lyrics"
    lyricsStack.axis = .vertical
    lyricsStack.alignment = .fill
    lyricsStack.spacing = 16
    lyricsStack.translatesAutoresizingMaskIntoConstraints = false
    lyricsScroll.addSubview(lyricsStack)
    lyricsContainer.addSubview(lyricsScroll)

    musicLyricsStage.addSubview(musicMiniHeader)
    musicLyricsStage.addSubview(lyricsContainer)

    NSLayoutConstraint.activate([
      musicLyricsStage.leadingAnchor.constraint(equalTo: musicStage.leadingAnchor),
      musicLyricsStage.trailingAnchor.constraint(equalTo: musicStage.trailingAnchor),
      musicLyricsStage.topAnchor.constraint(equalTo: musicStage.topAnchor),
      musicLyricsStage.bottomAnchor.constraint(equalTo: musicStage.bottomAnchor),

      musicMiniHeader.leadingAnchor.constraint(equalTo: musicLyricsStage.leadingAnchor),
      musicMiniHeader.trailingAnchor.constraint(equalTo: musicLyricsStage.trailingAnchor),
      musicMiniHeader.topAnchor.constraint(equalTo: musicLyricsStage.topAnchor, constant: 4),
      musicMiniArtwork.widthAnchor.constraint(equalToConstant: 48),
      musicMiniArtwork.heightAnchor.constraint(equalToConstant: 48),
      miniRow.leadingAnchor.constraint(equalTo: musicMiniHeader.leadingAnchor),
      miniRow.trailingAnchor.constraint(equalTo: musicMiniHeader.trailingAnchor),
      miniRow.topAnchor.constraint(equalTo: musicMiniHeader.topAnchor),
      miniRow.bottomAnchor.constraint(equalTo: musicMiniHeader.bottomAnchor),

      lyricsContainer.leadingAnchor.constraint(equalTo: musicLyricsStage.leadingAnchor),
      lyricsContainer.trailingAnchor.constraint(equalTo: musicLyricsStage.trailingAnchor),
      lyricsContainer.topAnchor.constraint(equalTo: musicMiniHeader.bottomAnchor, constant: 14),
      lyricsContainer.bottomAnchor.constraint(equalTo: musicLyricsStage.bottomAnchor),

      lyricsScroll.leadingAnchor.constraint(equalTo: lyricsContainer.leadingAnchor),
      lyricsScroll.trailingAnchor.constraint(equalTo: lyricsContainer.trailingAnchor),
      lyricsScroll.topAnchor.constraint(equalTo: lyricsContainer.topAnchor),
      lyricsScroll.bottomAnchor.constraint(equalTo: lyricsContainer.bottomAnchor),

      lyricsStack.leadingAnchor.constraint(equalTo: lyricsScroll.contentLayoutGuide.leadingAnchor),
      lyricsStack.trailingAnchor.constraint(
        equalTo: lyricsScroll.contentLayoutGuide.trailingAnchor),
      lyricsStack.topAnchor.constraint(
        equalTo: lyricsScroll.contentLayoutGuide.topAnchor, constant: 28),
      lyricsStack.bottomAnchor.constraint(
        equalTo: lyricsScroll.contentLayoutGuide.bottomAnchor, constant: -48),
      lyricsStack.widthAnchor.constraint(equalTo: lyricsScroll.frameLayoutGuide.widthAnchor),
    ])
    appendLyricPlaceholder(L10n.text("正在读取歌词…"))
  }

  /// 在封面主舞台与全屏同步歌词舞台之间平滑切换。
  private func toggleLyricsMode() {
    guard isAudioPlayback else { return }
    showsFullLyrics.toggle()
    let showLyrics = showsFullLyrics
    musicLyricsStage.isHidden = false
    musicCoverStage.isHidden = false
    var config = lyricsToggleButton.configuration
    config?.image = UIImage(
      systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium))
    config?.baseForegroundColor = showLyrics ? .white : UIColor.white.withAlphaComponent(0.76)
    lyricsToggleButton.configuration = config
    playbackMenuButton?.menu = makeMusicMenu()

    UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut]) {
      self.musicCoverStage.alpha = showLyrics ? 0 : 1
      self.musicLyricsStage.alpha = showLyrics ? 1 : 0
    } completion: { _ in
      self.musicCoverStage.isHidden = showLyrics
      self.musicLyricsStage.isHidden = !showLyrics
    }
  }

  /// 随播放/暂停为音乐封面增加苹果音乐同款弹性缩放反馈。
  private func updateMusicArtworkScale(isPlaying: Bool) {
    guard isAudioPlayback, lastArtworkScalePlaying != isPlaying else { return }
    lastArtworkScalePlaying = isPlaying
    let scale: CGFloat = isPlaying ? 1.0 : 0.88
    UIView.animate(
      withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.4
    ) {
      self.musicArtworkShadowView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
  }

  /// 在没有 LRC 文本或读取期间显示柔和白色占位。
  private func appendLyricPlaceholder(_ text: String) {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.textColor = UIColor.white.withAlphaComponent(0.55)
    label.textAlignment = .center
    label.numberOfLines = 2
    lyricsStack.addArrangedSubview(label)
  }

  /// 初始化解码器并绑定受控媒体流或独立无凭据本地/外部音视频源。
  private func configurePlayer() -> Bool {
    player.delegate = self
    player.drawable = isAudioPlayback ? nil : videoView
    do {
      player.media = try makePlaybackMedia(url: manifest.contentUrl)
    } catch {
      showError(error.localizedDescription)
      return false
    }
    let localSaved = UserDefaults.standard.integer(forKey: progressKey)
    let serverSaved = manifest.resumePositionMs ?? 0
    let bestSaved = max(localSaved, serverSaved)
    savedProgress = bestSaved > 30_000 ? bestSaved : nil
    return true
  }

  /// 创建片尾自动播放下一集悬浮玻璃倒计时浮层（仅视频剧集队列使用）。
  private func configureUpNextOverlay() {
    upNextOverlay.translatesAutoresizingMaskIntoConstraints = false
    upNextOverlay.layer.cornerRadius = 20
    upNextOverlay.layer.cornerCurve = .continuous
    upNextOverlay.layer.borderWidth = 0.8
    upNextOverlay.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
    upNextOverlay.clipsToBounds = true
    upNextOverlay.alpha = 0
    upNextOverlay.isHidden = true
    upNextOverlay.accessibilityIdentifier = "video-playback-up-next"

    upNextHeaderLabel.text = L10n.text("即将播放下一集")
    upNextHeaderLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    upNextHeaderLabel.textColor = UIColor.white.withAlphaComponent(0.72)

    upNextTitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    upNextTitleLabel.textColor = .white
    upNextTitleLabel.numberOfLines = 2

    upNextCountdownLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    upNextCountdownLabel.textColor = UIColor.white.withAlphaComponent(0.76)

    var playConfig = UIButton.Configuration.filled()
    playConfig.baseBackgroundColor = .white
    playConfig.baseForegroundColor = .black
    playConfig.cornerStyle = .capsule
    playConfig.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
    playConfig.title = L10n.text("立即播放")
    playConfig.image = UIImage(systemName: "play.fill")
    playConfig.imagePadding = 6
    playConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 11, weight: .semibold)
    upNextPlayButton.configuration = playConfig
    upNextPlayButton.accessibilityIdentifier = "video-playback-up-next-play"
    upNextPlayButton.addAction(
      UIAction { [weak self] _ in
        guard let self else { return }
        self.cancelUpNextCountdown(markDismissed: false)
        self.playNextTrack()
      }, for: .touchUpInside)

    var cancelConfig = UIButton.Configuration.plain()
    cancelConfig.baseForegroundColor = UIColor.white.withAlphaComponent(0.86)
    cancelConfig.contentInsets = NSDirectionalEdgeInsets(
      top: 7, leading: 12, bottom: 7, trailing: 12)
    cancelConfig.title = L10n.text("取消")
    upNextCancelButton.configuration = cancelConfig
    upNextCancelButton.accessibilityIdentifier = "video-playback-up-next-cancel"
    upNextCancelButton.addAction(
      UIAction { [weak self] _ in self?.cancelUpNextCountdown(markDismissed: true) },
      for: .touchUpInside)

    let buttonsRow = UIStackView(arrangedSubviews: [upNextPlayButton, upNextCancelButton])
    buttonsRow.axis = .horizontal
    buttonsRow.alignment = .center
    buttonsRow.spacing = 8

    let contentStack = UIStackView(arrangedSubviews: [
      upNextHeaderLabel, upNextTitleLabel, upNextCountdownLabel, buttonsRow,
    ])
    contentStack.axis = .vertical
    contentStack.alignment = .leading
    contentStack.spacing = 6
    contentStack.setCustomSpacing(10, after: upNextCountdownLabel)
    contentStack.translatesAutoresizingMaskIntoConstraints = false

    upNextOverlay.contentView.addSubview(contentStack)
    view.addSubview(upNextOverlay)
    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(
        equalTo: upNextOverlay.contentView.leadingAnchor, constant: 16),
      contentStack.trailingAnchor.constraint(
        equalTo: upNextOverlay.contentView.trailingAnchor, constant: -16),
      contentStack.topAnchor.constraint(equalTo: upNextOverlay.contentView.topAnchor, constant: 14),
      contentStack.bottomAnchor.constraint(
        equalTo: upNextOverlay.contentView.bottomAnchor, constant: -14),
      upNextOverlay.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      upNextOverlay.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -16),
      upNextOverlay.widthAnchor.constraint(lessThanOrEqualToConstant: 290),
    ])
  }

  /// 展示 5 秒自动连播下一集倒计时浮层，倒计时结束自动切入下一集。
  private func presentUpNextCountdownIfNeeded() {
    guard !closed, !isAudioPlayback, !upNextDismissedForCurrentItem,
      upNextTask == nil, trackSwitchTask == nil,
      queue.indices.contains(queueIndex + 1)
    else { return }
    let nextItem = queue[queueIndex + 1]
    upNextTitleLabel.text =
      nextItem.subtitle.map { "\($0) · \(nextItem.title)" } ?? nextItem.title
    upNextCountdownLabel.text = L10n.format("%d 秒后自动播放", 5)
    upNextOverlay.isHidden = false
    UIView.animate(withDuration: 0.24) { self.upNextOverlay.alpha = 1 }

    upNextTask = Task { [weak self] in
      for remaining in stride(from: 5, through: 1, by: -1) {
        guard let self, !Task.isCancelled, !self.closed else { return }
        self.upNextCountdownLabel.text = L10n.format("%d 秒后自动播放", remaining)
        try? await Task.sleep(for: .seconds(1))
      }
      guard let self, !Task.isCancelled, !self.closed else { return }
      self.upNextTask = nil
      self.hideUpNextOverlay()
      self.playNextTrack()
    }
  }

  /// 取消自动连播倒计时并隐藏浮层。
  private func cancelUpNextCountdown(markDismissed: Bool) {
    upNextTask?.cancel()
    upNextTask = nil
    if markDismissed { upNextDismissedForCurrentItem = true }
    hideUpNextOverlay()
  }

  /// 隐藏下一集倒计时浮层。
  private func hideUpNextOverlay() {
    guard !upNextOverlay.isHidden else { return }
    UIView.animate(withDuration: 0.18) {
      self.upNextOverlay.alpha = 0
    } completion: { _ in
      self.upNextOverlay.isHidden = true
    }
  }

  // MARK: - VLCMediaPlayerDelegate

  /// VLCKit 4.x 状态回调：监听自然播完以触发视频连播倒计时或音乐自动下一首。
  nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
    Task { @MainActor [weak self] in
      guard let self, !self.closed else { return }
      if newState == .playing {
        self.hasPlayedCurrentItem = true
        self.applyDefaultRateIfNeeded()
        self.applyTrackPreferencesIfReady()
      } else if newState == .stopping || newState == .stopped {
        self.handlePossiblePlaybackCompletion()
      }
    }
  }

  /// VLCKit 4.x 轨道就绪回调：收到音轨或字幕轨道后立即应用播前选择。
  nonisolated func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
    _ = trackId
    _ = trackType
    Task { @MainActor [weak self] in
      guard let self, !self.closed else { return }
      self.applyTrackPreferencesIfReady()
    }
  }

  /// 判定是否已播至片尾并触发视频自动下一集倒计时或音乐自动切歌。
  private func handlePossiblePlaybackCompletion() {
    guard hasPlayedCurrentItem, trackSwitchTask == nil, !resumeDecisionPending else { return }
    let duration = max(lastObservedDurationMs, Int(player.media?.length.intValue ?? 0))
    let position = max(lastObservedPositionMs, Int(player.time.intValue))
    let nearEnd =
      duration > 5_000
      && (position >= duration * 93 / 100 || (duration - position) <= 3_500)
    guard nearEnd else { return }
    reportPlaybackProgress(state: "stopped", force: true)
    guard queue.indices.contains(queueIndex + 1) else { return }
    if isAudioPlayback {
      playNextTrack()
    } else {
      presentUpNextCountdownIfNeeded()
    }
  }

  /// 首次进入播放态时同步用户设置的默认倍速。
  private func applyDefaultRateIfNeeded() {
    guard !appliedDefaultRate, player.isPlaying else { return }
    appliedDefaultRate = true
    if abs(currentPlaybackRate - 1.0) >= 0.01 {
      player.rate = currentPlaybackRate
    }
  }

  /// 当 VLC 轨道就绪时自动应用用户在详情页播前选择的音轨与字幕（或系统默认中文字幕偏好）。
  private func applyTrackPreferencesIfReady() {
    guard !isAudioPlayback, !closed else { return }

    if !appliedAudioSelection {
      let audioTracks = player.audioTracks
      if !audioTracks.isEmpty {
        if let selection = pendingTrackSelection {
          if let ordinal = selection.audioOrdinal, audioTracks.indices.contains(ordinal) {
            audioTracks[ordinal].isSelectedExclusively = true
            appliedAudioSelection = true
          } else if let lang = selection.audioLanguage?.lowercased(),
            let matched = audioTracks.first(where: { track in
              let hay = "\(track.language ?? "") \(track.trackName) \(track.trackDescription ?? "")"
                .lowercased()
              return hay.contains(lang)
            })
          {
            matched.isSelectedExclusively = true
            appliedAudioSelection = true
          } else {
            appliedAudioSelection = true
          }
        } else {
          appliedAudioSelection = true
        }
      }
    }

    if !appliedSubtitleSelection {
      let textTracks = player.textTracks
      if let selection = pendingTrackSelection {
        if selection.subtitleDisabled {
          player.deselectAllTextTracks()
          appliedSubtitleSelection = true
        } else if let extID = selection.subtitleExternalID,
          let matchedSub = manifest.subtitles.first(where: { $0.subtitleId == extID })
        {
          appliedSubtitleSelection = true
          loadSubtitle(matchedSub)
        } else if !textTracks.isEmpty {
          if let ordinal = selection.subtitleOrdinal, textTracks.indices.contains(ordinal) {
            textTracks[ordinal].isSelectedExclusively = true
            appliedSubtitleSelection = true
          } else if let lang = selection.subtitleLanguage?.lowercased(),
            let matched = textTracks.first(where: { track in
              let hay = "\(track.language ?? "") \(track.trackName) \(track.trackDescription ?? "")"
                .lowercased()
              return hay.contains(lang)
            })
          {
            matched.isSelectedExclusively = true
            appliedSubtitleSelection = true
          }
        }
      } else {
        let preferChinese =
          UserDefaults.standard.object(forKey: "nativeV2.playback.preferChineseSub") as? Bool
          ?? true
        guard preferChinese else {
          appliedSubtitleSelection = true
          return
        }
        let chineseKeywords = ["zh", "chi", "zho", "cmn", "chs", "cht", "中文", "简体", "繁体", "中字"]
        if let matchedEmbedded = textTracks.first(where: { track in
          let hay = "\(track.language ?? "") \(track.trackName) \(track.trackDescription ?? "")"
            .lowercased()
          return chineseKeywords.contains { hay.contains($0) }
        }) {
          matchedEmbedded.isSelectedExclusively = true
          appliedSubtitleSelection = true
        } else if let matchedExternal = manifest.subtitles.first(where: { sub in
          let hay = "\(sub.language ?? "") \(sub.title)".lowercased()
          return chineseKeywords.contains { hay.contains($0) }
        }) {
          appliedSubtitleSelection = true
          loadSubtitle(matchedExternal)
        }
      }
    }
  }

  /// 向源媒体服务器异步回传播放进度（每 15 秒节流，暂停/停止立即发送）。
  private func reportPlaybackProgress(state: String, force: Bool = false) {
    guard let client, let server = manifest.server, !server.isEmpty else { return }
    let now = Date()
    if !force && now.timeIntervalSince(lastProgressReportAt) < 15 { return }
    lastProgressReportAt = now
    let position = max(lastObservedPositionMs, Int(player.time.intValue))
    let duration = max(lastObservedDurationMs, Int(player.media?.length.intValue ?? 0))
    let paused = state == "paused" || !player.isPlaying
    let itemId = self.itemId
    let mediaSourceId = manifest.mediaSourceId
    progressReportTask?.cancel()
    progressReportTask = Task {
      await client.reportProgress(
        itemId: itemId,
        server: server,
        mediaSourceId: mediaSourceId,
        positionMs: position,
        durationMs: duration > 0 ? duration : nil,
        isPaused: paused,
        state: state
      )
    }
  }

  /// 构造解码器媒体对象；独立播放模式下不附加任何 MoviePilot Cookie 或认证头。
  private func makePlaybackMedia(url: URL) throws -> VLCMedia {
    if let client {
      return try client.makeMedia(url: url)
    }
    if url.isFileURL {
      guard let media = VLCMedia(url: url) else { throw MediaPlaybackError.unavailable }
      return media
    }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let media = VLCMedia(url: url)
    else { throw MediaPlaybackError.unavailable }
    media.addOption(":network-caching=1500")
    return media
  }

  /// 通过授权歌词地址下载 LRC 并将时间轴绑定到当前播放器。
  private func loadLyrics() {
    guard let lyricsURL = manifest.lyricsUrl, let client else {
      replaceLyrics(with: [])
      return
    }
    lyricsTask?.cancel()
    lyricsTask = Task { [weak self] in
      guard let self else { return }
      do {
        let text = try await client.downloadLyrics(lyricsURL, itemId: self.itemId)
        guard !Task.isCancelled, !self.closed else { return }
        self.replaceLyrics(with: Self.parseLyrics(text))
      } catch {
        guard !Task.isCancelled, !self.closed else { return }
        self.replaceLyrics(with: [])
      }
    }
  }

  /// 下载后端图片代理的单曲封面，并同步更新主封面、迷你头图、氛围背景与锁屏信息。
  private func loadArtwork() {
    guard let artworkURL, let client else { return }
    artworkTask?.cancel()
    artworkTask = Task { [weak self] in
      guard let self, let image = try? await client.downloadArtwork(artworkURL),
        !Task.isCancelled, !self.closed
      else { return }
      self.applyResolvedArtwork(image, animated: true)
    }
  }

  /// 将已解码的封面图统一应用至主封面、迷你头图、氛围背景与锁屏媒体信息。
  private func applyResolvedArtwork(_ image: UIImage, animated: Bool) {
    musicArtwork.image = image
    musicMiniArtwork.image = image
    musicArtwork.accessibilityValue = L10n.text("专辑封面已加载")
    musicArtworkPlaceholder.isHidden = true
    musicBackdropImageView.image = image
    if animated {
      UIView.animate(withDuration: 0.45) {
        self.musicBackdropImageView.alpha = 1
      }
    } else {
      musicBackdropImageView.alpha = 1
    }
    currentMiniArtworkImage = image
    nowPlayingArtwork = Self.makeNowPlayingArtwork(image)
    notifyMiniMusicStateIfNeeded()
    refreshNowPlayingInfo()
  }

  /// 锁屏服务会在后台队列请求同一张不可变封面图，避免闭包继承界面主线程隔离。
  nonisolated private static func makeNowPlayingArtwork(_ image: UIImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
  }

  /// 解析 UTF-8/UTF-16 LRC 时间戳，支持同一歌词行的多个起始时间。
  private static func parseLyrics(_ text: String) -> [MediaPlaybackLyricCue] {
    guard
      let expression = try? NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    else { return [] }
    var cues: [MediaPlaybackLyricCue] = []
    for line in text.components(separatedBy: .newlines) {
      let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
      let matches = expression.matches(in: line, range: fullRange)
      guard !matches.isEmpty, let lastMatch = matches.last,
        let textRange = Range(
          NSRange(
            location: lastMatch.range.location + lastMatch.range.length,
            length: fullRange.length - lastMatch.range.location - lastMatch.range.length), in: line)
      else { continue }
      let lyric = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !lyric.isEmpty else { continue }
      for match in matches {
        guard let minuteRange = Range(match.range(at: 1), in: line),
          let secondRange = Range(match.range(at: 2), in: line),
          let minutes = Double(line[minuteRange]), let seconds = Double(line[secondRange])
        else { continue }
        let fraction: Double
        if let fractionRange = Range(match.range(at: 3), in: line) {
          fraction = Double("0.\(line[fractionRange])") ?? 0
        } else {
          fraction = 0
        }
        cues.append(MediaPlaybackLyricCue(time: minutes * 60 + seconds + fraction, text: lyric))
      }
    }
    return cues.sorted { $0.time < $1.time }
  }

  /// 用可点按歌词行替换加载状态，并按时间顺序重置高亮位置。
  private func replaceLyrics(with cues: [MediaPlaybackLyricCue]) {
    for arranged in lyricsStack.arrangedSubviews {
      lyricsStack.removeArrangedSubview(arranged)
      arranged.removeFromSuperview()
    }
    lyricCues = cues
    lyricButtons.removeAll()
    activeLyricIndex = nil
    guard !cues.isEmpty else {
      musicLyricPreviewButton.isHidden = true
      appendLyricPlaceholder(L10n.text("暂无同名 LRC 歌词"))
      return
    }
    musicLyricPreviewButton.isHidden = false
    updateLyricPreview(cues.first?.text ?? "")
    for (index, cue) in cues.enumerated() {
      let button = UIButton(type: .system)
      button.setTitle(cue.text, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
      button.titleLabel?.numberOfLines = 0
      button.titleLabel?.textAlignment = .left
      button.contentHorizontalAlignment = .leading
      button.tintColor = .white
      button.setTitleColor(UIColor.white.withAlphaComponent(0.42), for: .normal)
      button.accessibilityIdentifier = "playback-lyric-line-\(index)"
      button.accessibilityLabel = cue.text
      button.addAction(UIAction { [weak self] _ in self?.seekToLyric(index) }, for: .touchUpInside)
      lyricsStack.addArrangedSubview(button)
      lyricButtons.append(button)
    }
    refreshLyrics(currentMilliseconds: Int(player.time.intValue))
  }

  /// 更新封面模式下的单行动态歌词预览胶囊。
  private func updateLyricPreview(_ text: String) {
    guard var config = musicLyricPreviewButton.configuration else { return }
    var attrs = AttributeContainer()
    attrs.font = .systemFont(ofSize: 13.5, weight: .medium)
    config.attributedTitle = AttributedString(text, attributes: attrs)
    config.titleLineBreakMode = .byTruncatingTail
    musicLyricPreviewButton.configuration = config
  }

  /// 按播放时间高亮当前歌词，同步更新封面模式预览条并将活跃行平滑滚动到歌词舞台中上方。
  private func refreshLyrics(currentMilliseconds: Int) {
    guard isAudioPlayback, !lyricCues.isEmpty else { return }
    let seconds = Double(max(0, currentMilliseconds)) / 1000
    let nextIndex = lyricCues.lastIndex { $0.time <= seconds }
    guard nextIndex != activeLyricIndex else { return }
    activeLyricIndex = nextIndex
    if let nextIndex, lyricCues.indices.contains(nextIndex) {
      updateLyricPreview(lyricCues[nextIndex].text)
    }
    for (index, button) in lyricButtons.enumerated() {
      let active = index == nextIndex
      button.alpha = active ? 1.0 : 0.55
      button.accessibilityValue = active ? L10n.text("当前播放") : nil
      button.setTitleColor(active ? .white : UIColor.white.withAlphaComponent(0.60), for: .normal)
      button.titleLabel?.font = .systemFont(
        ofSize: active ? 23 : 18,
        weight: active ? .bold : .medium)
    }
    guard showsFullLyrics, let nextIndex, lyricButtons.indices.contains(nextIndex) else { return }
    lyricsScroll.layoutIfNeeded()
    let button = lyricButtons[nextIndex]
    let maxOffset = max(0, lyricsScroll.contentSize.height - lyricsScroll.bounds.height)
    let targetY = min(maxOffset, max(0, button.frame.midY - lyricsScroll.bounds.height * 0.36))
    lyricsScroll.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
  }

  /// 用户点选歌词时跳转到该句的 LRC 时间戳。
  private func seekToLyric(_ index: Int) {
    guard lyricCues.indices.contains(index), player.isSeekable else { return }
    player.time = VLCTime(int: Int32(clamping: Int(lyricCues[index].time * 1000)))
    refreshLyrics(currentMilliseconds: Int(player.time.intValue))
    refreshPlaybackState()
  }

  /// 按媒体类型选择系统音乐或电影音频会话，支持锁屏后继续播放。
  private func configureAudioSession() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance())
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance())
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback, mode: isAudioPlayback ? .default : .moviePlayback, options: [.allowAirPlay])
      try AVAudioSession.sharedInstance().setActive(true)
      if !audioSessionClaimed {
        audioSessionClaimed = true
        Self.activeAudioSessions.withLock { $0 += 1 }
      }
    } catch {
      showError(L10n.text("无法启动系统音频会话，请检查设备声音设置。"))
    }
  }

  /// 系统音频会话中断时暂停，并仅在系统允许恢复时接续原播放状态。
  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: rawType)
    else { return }
    switch type {
    case .began:
      interruption.begin(wasPlaying: player.isPlaying)
      player.pause()
      showControls()
    case .ended:
      let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      if interruption.end(systemAllowsResume: options.contains(.shouldResume)), !closed {
        do {
          try AVAudioSession.sharedInstance().setActive(true)
          player.play()
        } catch {
          showError(L10n.text("无法恢复系统音频会话，请手动继续播放。"))
        }
      }
    @unknown default:
      _ = interruption.end(systemAllowsResume: false)
    }
  }

  /// 耳机等当前输出设备拔出时暂停，避免声音意外切换到扬声器继续播放。
  @objc private func handleAudioRouteChange(_ notification: Notification) {
    guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable
    else { return }
    interruption.cancelResume()
    player.pause()
    showControls()
  }

  /// 将播放、暂停和拖动命令接入 iOS 锁屏及耳机控制。
  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget(self, action: #selector(remotePlay))
    center.pauseCommand.addTarget(self, action: #selector(remotePause))
    center.togglePlayPauseCommand.addTarget(self, action: #selector(remoteToggle))
    center.changePlaybackPositionCommand.addTarget(self, action: #selector(remoteSeek(_:)))
    center.skipForwardCommand.preferredIntervals = [10]
    center.skipForwardCommand.addTarget(self, action: #selector(remoteForward))
    center.skipBackwardCommand.preferredIntervals = [10]
    center.skipBackwardCommand.addTarget(self, action: #selector(remoteBackward))
    center.nextTrackCommand.addTarget(self, action: #selector(remoteNextTrack))
    center.previousTrackCommand.addTarget(self, action: #selector(remotePreviousTrack))
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.changePlaybackPositionCommand.isEnabled = true
    center.skipForwardCommand.isEnabled = !isAudioPlayback
    center.skipBackwardCommand.isEnabled = !isAudioPlayback
    center.nextTrackCommand.isEnabled = queue.indices.contains(queueIndex + 1)
    center.previousTrackCommand.isEnabled = queueIndex > 0
    refreshNowPlayingInfo()
  }

  /// 创建采用系统材质、轻描边和 SF Symbols 的圆形玻璃控制键。
  private func makeGlassButton(
    symbol: String, accessibility: String, diameter: CGFloat, pointSize: CGFloat
  ) -> UIButton {
    let button = UIButton(type: .system)
    configureGlassButton(
      button, symbol: symbol, accessibility: accessibility, diameter: diameter,
      pointSize: pointSize)
    return button
  }

  /// 为指定控件设置磨砂玻璃背景、边线、图标尺寸和固定触控区域。
  private func configureGlassButton(
    _ button: UIButton, symbol: String, accessibility: String, diameter: CGFloat,
    pointSize: CGFloat
  ) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(
      UIImage(systemName: symbol)?.withConfiguration(
        UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)), for: .normal)
    button.accessibilityLabel = accessibility
    styleAsGlassButton(button, diameter: diameter, pointSize: pointSize)
  }

  /// 对齐系统画中画的圆形玻璃按钮；新系统使用原生玻璃，旧系统回退到磨砂材质。
  private func styleAsGlassButton(_ button: UIButton, diameter: CGFloat, pointSize: CGFloat) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = .white
    if #available(iOS 26.0, *) {
      var configuration = UIButton.Configuration.glass()
      configuration.cornerStyle = .capsule
      configuration.baseForegroundColor = .white
      configuration.image = button.image(for: .normal)
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: pointSize, weight: .semibold)
      button.configuration = configuration
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: diameter),
        button.heightAnchor.constraint(equalToConstant: diameter),
      ])
      return
    }
    button.backgroundColor = UIColor.black.withAlphaComponent(0.24)
    button.layer.cornerRadius = diameter / 2
    button.layer.cornerCurve = .continuous
    button.layer.borderWidth = 0.8
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
    button.clipsToBounds = true
    button.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold), forImageIn: .normal)

    let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    material.isUserInteractionEnabled = false
    material.translatesAutoresizingMaskIntoConstraints = false
    button.insertSubview(material, at: 0)
    if let imageView = button.imageView { button.bringSubviewToFront(imageView) }
    if let titleLabel = button.titleLabel { button.bringSubviewToFront(titleLabel) }
    NSLayoutConstraint.activate([
      material.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      material.trailingAnchor.constraint(equalTo: button.trailingAnchor),
      material.topAnchor.constraint(equalTo: button.topAnchor),
      material.bottomAnchor.constraint(equalTo: button.bottomAnchor),
      button.widthAnchor.constraint(equalToConstant: diameter),
      button.heightAnchor.constraint(equalToConstant: diameter),
    ])
  }

  /// 以当前解码状态更新进度、可用轨道、锁屏信息和本地续播点。
  private func refreshPlaybackState() {
    guard !closed else { return }
    let current = max(0, Int(player.time.intValue))
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    let isPlaying = player.isPlaying

    if !isScrubbing {
      positionSlider.isEnabled = player.isSeekable && duration > 0
      let progressValue = duration > 0 ? min(1, Double(current) / Double(duration)) : 0
      lastKnownProgress = progressValue
      positionSlider.value = Float(progressValue)
      updateTimeLabels(current: current, duration: duration)
    }

    updatePlayButtonSymbol(isPlaying: isPlaying)
    if isAudioPlayback {
      updateMusicArtworkScale(isPlaying: isPlaying)
      notifyMiniMusicStateIfNeeded()
    } else {
      pictureInPicture.refresh()
    }
    if isPlaying || current > 0 { loading.stopAnimating() }
    if current > 0 { lastObservedPositionMs = current }
    if duration > 0 { lastObservedDurationMs = duration }
    if isPlaying {
      hasPlayedCurrentItem = true
      applyDefaultRateIfNeeded()
      applyTrackPreferencesIfReady()
      reportPlaybackProgress(state: "playing")
    }

    if !isAudioPlayback {
      let subtitleTracks = player.textTracks
      let audioTracks = player.audioTracks
      subtitleButton.isHidden = manifest.subtitles.isEmpty && subtitleTracks.isEmpty
      audioButton.isHidden = audioTracks.count <= 1
      episodeListButton.isHidden = queue.count <= 1
      if !isPlaying && hasPlayedCurrentItem && duration > 5_000
        && (current >= duration - 1_500) && queue.indices.contains(queueIndex + 1)
      {
        presentUpNextCountdownIfNeeded()
      }
    }

    refreshQueueControls(current: current)
    refreshNowPlayingInfo(current: current, duration: duration)
    if isAudioPlayback { refreshLyrics(currentMilliseconds: current) }
    offerResumeIfNeeded(duration: duration)

    if isPlaying {
      if controlsVisible, !isLocked, hideControlsTask == nil { scheduleControlsHide() }
    } else {
      hideControlsTask?.cancel()
      hideControlsTask = nil
    }

    if !resumeDecisionPending, savedProgress == nil {
      if current > 0, duration > 0, current < duration * 95 / 100 {
        UserDefaults.standard.set(current, forKey: progressKey)
      } else if duration > 0, current >= duration * 95 / 100 {
        UserDefaults.standard.removeObject(forKey: progressKey)
      }
    }
  }

  /// 更新已播时长与总时长/剩余时长标签。
  private func updateTimeLabels(current: Int, duration: Int) {
    elapsedLabel.text = Self.format(milliseconds: current)
    if showRemainingTime && duration > 0 {
      durationLabel.text = "-\(Self.format(milliseconds: max(0, duration - current)))"
    } else {
      durationLabel.text = Self.format(milliseconds: duration)
    }
  }

  /// 点按右侧时长标签切换显示「总时长」或「剩余时长」。
  @objc private func toggleRemainingTime() {
    showRemainingTime.toggle()
    let current = max(0, Int(player.time.intValue))
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    updateTimeLabels(current: current, duration: duration)
  }

  /// 在已有续播点时由用户选择继续观看或从头播放。
  private func offerResumeIfNeeded(duration: Int) {
    guard !resumePromptShown, duration > 0, let saved = savedProgress else { return }
    guard saved < duration * 95 / 100 else {
      savedProgress = nil
      UserDefaults.standard.removeObject(forKey: progressKey)
      return
    }
    resumePromptShown = true
    resumeDecisionPending = true
    player.pause()
    let alert = UIAlertController(
      title: isAudioPlayback ? L10n.text("继续收听？") : L10n.text("继续观看？"),
      message: L10n.format("上次播放到 %@。", Self.format(milliseconds: saved)), preferredStyle: .alert)
    alert.addAction(
      UIAlertAction(
        title: isAudioPlayback ? L10n.text("继续收听") : L10n.text("继续播放"), style: .default
      ) { [weak self] _ in
        guard let self else { return }
        self.player.time = VLCTime(int: Int32(clamping: saved))
        self.savedProgress = nil
        self.resumeDecisionPending = false
        self.player.play()
      })
    alert.addAction(
      UIAlertAction(title: L10n.text("从头开始"), style: .cancel) { [weak self] _ in
        guard let self else { return }
        UserDefaults.standard.removeObject(forKey: self.progressKey)
        self.savedProgress = nil
        self.resumeDecisionPending = false
        self.player.time = VLCTime(int: 0)
        self.player.play()
      })
    present(alert, animated: true)
  }

  /// 根据当前播放状态更新锁屏标题、时长、进度和播放按钮状态。
  private func refreshNowPlayingInfo(current: Int? = nil, duration: Int? = nil) {
    let current = current ?? max(0, Int(player.time.intValue))
    let duration = duration ?? max(0, Int(player.media?.length.intValue ?? 0))
    var information: [String: Any] = [
      MPMediaItemPropertyTitle: displayTitle,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(current) / 1000,
      MPMediaItemPropertyPlaybackDuration: Double(duration) / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? player.rate : 0,
      MPNowPlayingInfoPropertyMediaType:
        (isAudioPlayback ? MPNowPlayingInfoMediaType.audio : .video).rawValue,
    ]
    if isAudioPlayback {
      information[MPMediaItemPropertyArtist] = manifest.artist
      information[MPMediaItemPropertyAlbumTitle] = manifest.album
      if let nowPlayingArtwork { information[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = information
    MPNowPlayingInfoCenter.default().playbackState = player.isPlaying ? .playing : .paused
  }

  /// 用户点击主播放按钮时切换播放状态并恢复控制栏。
  private func togglePlayback() {
    interruption.cancelResume()
    guard !interruption.isInterrupted else {
      showControls()
      return
    }
    if player.isPlaying {
      player.pause()
      reportPlaybackProgress(state: "paused", force: true)
    } else {
      cancelUpNextCountdown(markDismissed: false)
      player.play()
    }
    refreshPlaybackState()
    if !isAudioPlayback { showControls() }
  }

  /// 在可 seek 的媒体中按秒数跳转，并可选展示双点/按钮快进退 HUD 胶囊。
  private func skip(seconds: Int, showHud: Bool = false) {
    guard player.isSeekable else { return }
    let current = Int(player.time.intValue)
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    let target = min(duration, max(0, current + seconds * 1000))
    player.time = VLCTime(int: Int32(clamping: target))
    if showHud && !isAudioPlayback {
      presentSeekHud(seconds < 0 ? "« \(abs(seconds)) 秒" : "\(seconds) 秒 »")
    }
    if !isAudioPlayback && !isLocked { showControls() }
  }

  /// 展示短暂的快进/快退悬浮反馈胶囊。
  private func presentSeekHud(_ text: String) {
    seekHudTask?.cancel()
    seekHudLabel.text = "  \(text)  "
    UIView.animate(withDuration: 0.14) { self.seekHudLabel.alpha = 1 }
    seekHudTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(750))
      guard !Task.isCancelled, let self else { return }
      UIView.animate(withDuration: 0.25) { self.seekHudLabel.alpha = 0 }
    }
  }

  /// 双击视频左半屏后退 10 秒，双击右半屏前进 10 秒。
  @objc private func handleVideoDoubleTap(_ gesture: UITapGestureRecognizer) {
    guard !isAudioPlayback, !isLocked else { return }
    let location = gesture.location(in: view)
    skip(seconds: location.x < view.bounds.midX ? -10 : 10, showHud: true)
  }

  /// 下滑手势将音乐播放器收起为悬浮迷你播放条，持续后台播放不中断。
  @objc private func handleSwipeDown() {
    guard isAudioPlayback else { return }
    minimizeAudioPlayback()
  }

  /// 切换视频画面「适应」与「填充」模式（纯图标更新，无文字）。
  private func toggleAspectMode() {
    isAspectFill.toggle()
    applyAspectMode()
    if var config = aspectButton.configuration {
      config.image = UIImage(
        systemName: isAspectFill
          ? "arrow.down.right.and.arrow.up.left"
          : "arrow.up.left.and.arrow.down.right")
      aspectButton.configuration = config
    } else {
      aspectButton.setImage(
        UIImage(
          systemName: isAspectFill
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right",
          withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)),
        for: .normal)
    }
    presentSeekHud(isAspectFill ? L10n.text("画面已填充") : L10n.text("画面已适应"))
  }

  /// 应用当前比例设置至 VLC 视频适配模式（适应 / 满屏填充）。
  private func applyAspectMode() {
    guard !isAudioPlayback else { return }
    player.videoFitMode = isAspectFill ? .larger : .smaller
  }

  /// 当前视频是否处于横屏状态（锁定图标仅横屏展示）。
  private var isVideoLandscape: Bool {
    !isAudioPlayback && view.bounds.width > view.bounds.height
  }

  /// 根据横竖屏方向自动显隐右侧居中锁定按钮；切回竖屏时自动解除锁屏防止用户被卡住。
  private func updateLockButtonVisibilityForOrientation() {
    guard !isAudioPlayback else { return }
    if isVideoLandscape {
      lockTopButton.isHidden = false
      lockTopButton.alpha = (controlsVisible || isLocked) ? 1 : 0
    } else {
      if isLocked {
        isLocked = false
        updateLockButtonSymbol(locked: false)
      }
      lockTopButton.isHidden = true
      lockTopButton.alpha = 0
    }
  }

  /// 刷新右侧居中锁定/解锁纯图标按钮样式（锁定与解锁复用同一位置，无任何文字）。
  private func updateLockButtonSymbol(locked: Bool) {
    let symbol = locked ? "lock.fill" : "lock.open"
    let accessibility = locked ? L10n.text("解锁屏幕") : L10n.text("锁定屏幕")
    lockTopButton.accessibilityLabel = accessibility
    let image = UIImage(
      systemName: symbol,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
    if var config = lockTopButton.configuration {
      config.image = image
      lockTopButton.configuration = config
    } else {
      lockTopButton.setImage(image, for: .normal)
    }
  }

  /// 切换视频防误触锁屏状态（仅横屏生效，锁屏与解锁复用右侧居中纯图标按钮）。
  private func setLocked(_ locked: Bool) {
    guard !isAudioPlayback else { return }
    if locked && !isVideoLandscape { return }
    isLocked = locked
    updateLockButtonSymbol(locked: locked)
    hideControlsTask?.cancel()
    hideControlsTask = nil
    if locked {
      controlsVisible = false
      lockTopButton.isHidden = false
      UIView.animate(withDuration: 0.22) {
        self.topBar.alpha = 0
        self.topScrimView.alpha = 0
        self.controls.alpha = 0
        self.bottomScrimView.alpha = 0
        self.transport.alpha = 0
        self.lockTopButton.alpha = 1
      }
      scheduleLockedButtonHide()
      setNeedsStatusBarAppearanceUpdate()
    } else {
      showControls()
    }
  }

  /// 锁屏状态下右侧居中纯图标按钮短暂停留后淡出，轻触画面可随时再次呼出解锁。
  private func scheduleLockedButtonHide() {
    hideControlsTask?.cancel()
    guard isLocked else { return }
    hideControlsTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled, let self, self.isLocked else { return }
      UIView.animate(withDuration: 0.22) { self.lockTopButton.alpha = 0 }
    }
  }

  /// 在首曲播放不足三秒时切到上一首，否则从头重播当前歌曲。
  private func playPreviousTrack() {
    let current = max(0, Int(player.time.intValue))
    guard current > 3_000 || queueIndex > 0 else { return }
    if current > 3_000 {
      player.time = VLCTime(int: 0)
      refreshPlaybackState()
    } else {
      switchTrack(at: queueIndex - 1)
    }
  }

  /// 播放当前队列中的下一首歌曲。
  private func playNextTrack() {
    switchTrack(at: queueIndex + 1)
  }

  /// 加载队列中的另一首单曲或另一集视频，非阻塞切换媒体并清理上一集外挂字幕缓存。
  private func switchTrack(at index: Int) {
    guard trackSwitchTask == nil, queue.indices.contains(index),
      index != queueIndex, let client
    else { return }
    cancelUpNextCountdown(markDismissed: false)
    reportPlaybackProgress(state: "stopped", force: true)
    let item = queue[index]
    let wasAudio = isAudioPlayback
    if wasAudio {
      skipBackButton.isEnabled = false
      skipForwardButton.isEnabled = false
    } else {
      prevEpisodeButton.isEnabled = false
      nextEpisodeButton.isEnabled = false
    }
    MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
    MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
    loading.startAnimating()
    trackSwitchTask = Task { [weak self] in
      guard let self else { return }
      do {
        let nextManifest: MediaPlaybackManifest
        if !item.itemId.isEmpty {
          nextManifest = try await client.loadManifest(
            itemId: item.itemId, server: item.server ?? self.manifest.server,
            mediaSourceId: item.mediaSourceId)
        } else {
          nextManifest = try await client.loadMusicManifest(
            title: item.title, artist: item.artist, album: item.album)
        }
        guard !Task.isCancelled, !self.closed else { return }
        let media = try client.makeMedia(url: nextManifest.contentUrl)
        self.player.pause()
        self.cleanupTemporarySubtitles()
        self.player.media = media
        self.manifest = nextManifest
        self.itemId = nextManifest.itemId
        self.displayTitle =
          (!wasAudio && item.subtitle != nil)
          ? "\(item.subtitle!) · \(item.title)"
          : item.title
        self.titleLabel.text =
          wasAudio
          ? ((nextManifest.album?.isEmpty == false ? nextManifest.album : nil)
            ?? L10n.text("正在播放"))
          : self.displayTitle

        if wasAudio {
          self.musicTitleLabel.text = item.title
          self.musicMiniTitleLabel.text = item.title
          let subtitle = [nextManifest.artist ?? item.artist, nextManifest.album ?? item.album]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
          self.musicArtistLabel.text = subtitle.isEmpty ? L10n.text("未知艺人") : subtitle
          self.musicMiniSubtitleLabel.text = self.musicArtistLabel.text
          let nextArtwork = item.artworkURL.flatMap(URL.init(string:))
          if nextArtwork != self.artworkURL {
            self.artworkURL = nextArtwork
            self.musicArtwork.image = nil
            self.musicMiniArtwork.image = nil
            self.musicArtworkPlaceholder.isHidden = false
            self.musicBackdropImageView.image = nil
            self.musicBackdropImageView.alpha = 0
            self.nowPlayingArtwork = nil
            self.loadArtwork()
          }
          self.lyricsTask?.cancel()
          self.replaceLyrics(with: [])
          self.loadLyrics()
          self.savedProgress = nil
          self.resumePromptShown = true
        } else {
          // 切集保留语言/关闭字幕偏好，但清除上一集专属的媒体源与外挂字幕 ID
          if let prev = self.pendingTrackSelection {
            self.pendingTrackSelection = MediaPlaybackTrackSelection(
              mediaSourceID: nil,
              audioOrdinal: prev.audioOrdinal,
              audioLanguage: prev.audioLanguage,
              audioDisplayTitle: prev.audioDisplayTitle,
              subtitleDisabled: prev.subtitleDisabled,
              subtitleOrdinal: nil,
              subtitleExternalID: nil,
              subtitleLanguage: prev.subtitleLanguage,
              subtitleDisplayTitle: prev.subtitleDisplayTitle
            )
          }
          self.appliedAudioSelection = false
          self.appliedSubtitleSelection = false
          self.appliedDefaultRate = false
          self.activeExternalSubtitleID = nil
          self.upNextDismissedForCurrentItem = false
          let localSaved = UserDefaults.standard.integer(forKey: self.progressKey)
          let serverSaved = nextManifest.resumePositionMs ?? 0
          let bestSaved = max(localSaved, serverSaved)
          self.savedProgress = bestSaved > 30_000 ? bestSaved : nil
          self.resumePromptShown = false
        }

        self.lastObservedPositionMs = 0
        self.lastObservedDurationMs = 0
        self.hasPlayedCurrentItem = false
        self.queueIndex = index
        self.player.time = VLCTime(int: 0)
        self.player.play()
        self.trackSwitchTask = nil
        self.refreshPlaybackState()
        if !wasAudio {
          self.presentSeekHud(item.subtitle ?? item.title)
        }
      } catch {
        guard !Task.isCancelled, !self.closed else { return }
        self.loading.stopAnimating()
        self.trackSwitchTask = nil
        self.refreshQueueControls(current: Int(self.player.time.intValue))
        self.showError(error.localizedDescription)
      }
    }
  }

  /// 清理已下载的上一集外挂字幕临时文件，避免缓存堆积。
  private func cleanupTemporarySubtitles() {
    subtitleTask?.cancel()
    subtitleTask = nil
    let oldFiles = subtitleFiles
    subtitleFiles.removeAll()
    activeSubtitleFile = nil
    activeExternalSubtitleID = nil
    guard !oldFiles.isEmpty else { return }
    Self.teardownQueue.async {
      for file in oldFiles {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  /// 展示当前剧集选集列表或专辑播放队列，支持直接点选切集/切歌。
  private func showQueueMenu() {
    guard queue.count > 1 else { return }
    let alert = UIAlertController(
      title: isAudioPlayback ? L10n.text("播放队列") : L10n.text("选集"),
      message: nil, preferredStyle: .actionSheet)
    for (index, item) in queue.prefix(50).enumerated() {
      let prefix = index == queueIndex ? "▶ " : ""
      let label: String
      if let sub = item.subtitle, !sub.isEmpty {
        label = "\(prefix)\(sub) · \(item.title)"
      } else {
        label = "\(prefix)\(index + 1). \(item.title)"
      }
      alert.addAction(
        UIAlertAction(title: label, style: .default) { [weak self] _ in
          self?.switchTrack(at: index)
        })
    }
    alert.addAction(UIAlertAction(title: L10n.text("取消"), style: .cancel))
    presentActionSheet(alert, from: isAudioPlayback ? musicQueueButton : episodeListButton)
  }

  /// 根据队列位置更新界面按钮及锁屏上一首/上一集、下一首/下一集命令的可用状态。
  private func refreshQueueControls(current: Int) {
    let center = MPRemoteCommandCenter.shared()
    if isAudioPlayback {
      skipBackButton.isEnabled = queueIndex > 0 || current > 3_000
      skipForwardButton.isEnabled = queue.indices.contains(queueIndex + 1)
      center.previousTrackCommand.isEnabled = skipBackButton.isEnabled
      center.nextTrackCommand.isEnabled = skipForwardButton.isEnabled
    } else {
      let hasPrev = queueIndex > 0
      let hasNext = queue.indices.contains(queueIndex + 1)
      prevEpisodeButton.isEnabled = hasPrev
      prevEpisodeButton.alpha = hasPrev ? 1.0 : 0.42
      nextEpisodeButton.isEnabled = hasNext
      nextEpisodeButton.alpha = hasNext ? 1.0 : 0.42
      center.previousTrackCommand.isEnabled = hasPrev
      center.nextTrackCommand.isEnabled = hasNext
    }
  }

  /// 按毫秒格式化已播放或总时长。
  private static func format(milliseconds: Int) -> String {
    let seconds = max(0, milliseconds / 1000)
    let hours = seconds / 3600
    let minutes = seconds / 60 % 60
    let remainder = seconds % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
      : String(format: "%02d:%02d", minutes, remainder)
  }

  /// 用户开始拖动时暂缓计时器覆盖滑块位置。
  @objc private func beginScrubbing() {
    isScrubbing = true
    hideControlsTask?.cancel()
    hideControlsTask = nil
  }

  /// 拖动滑块时实时刷新时间戳显示，提供即拖即看的进度反馈。
  @objc private func scrubbingChanged() {
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    guard duration > 0 else { return }
    let previewCurrent = Int(Float(duration) * positionSlider.value)
    updateTimeLabels(current: previewCurrent, duration: duration)
  }

  /// 用户松开滑块时将比例位置交给解码器并恢复进度同步。
  @objc private func endScrubbing() {
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    guard player.isSeekable, duration > 0 else {
      isScrubbing = false
      return
    }
    let target = Int(Float(duration) * positionSlider.value)
    player.time = VLCTime(int: Int32(clamping: target))
    isScrubbing = false
    updateTimeLabels(current: target, duration: duration)
    if !isAudioPlayback { showControls() }
  }

  /// 视频画面轻点切换控制栏可见性；锁屏时仅闪烁解锁提示胶囊。
  @objc private func toggleControls() {
    if isLocked {
      guard isVideoLandscape else { return }
      lockTopButton.isHidden = false
      let reveal = lockTopButton.alpha < 0.5
      UIView.animate(withDuration: 0.16) { self.lockTopButton.alpha = reveal ? 1 : 0 }
      if reveal { scheduleLockedButtonHide() }
      return
    }
    controlsVisible ? hideControls() : showControls()
  }

  /// 进度条、菜单和播放按钮自行接收点击，避免一次点击同时执行两个动作。
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
    -> Bool
  {
    if isAudioPlayback {
      if showsFullLyrics, touch.view?.isDescendant(of: lyricsScroll) == true { return false }
      return !(touch.view is UISlider)
    }
    var target = touch.view
    while let current = target, current !== view {
      if current is UIControl || current is UIScrollView { return false }
      target = current.superview
    }
    return true
  }

  /// 请求 iOS 原生画中画接管窗口，保留同一解码器、字幕和播放进度。
  private func minimizePlayback() {
    guard !closed, !isAudioPlayback else { return }
    pictureInPicture.start()
  }

  /// 立即安全停止播放器并通知调度器关闭模态页面（零主线程阻塞）。
  func closeFromShell() {
    isMinimizedAudio = false
    closePlayback()
    onClosePlayback(self)
  }

  /// 将音乐播放器最小化收起为悬浮迷你条，保持音频在后台持续播放不中断。
  private func minimizeAudioPlayback() {
    guard isAudioPlayback, !closed else {
      dismissPlayback()
      return
    }
    isMinimizedAudio = true
    onMinimize(self)
    notifyMiniMusicStateIfNeeded()
  }

  /// 从悬浮迷你条还原全屏音乐播放界面。
  func restoreFromMinimizedAudio() {
    isMinimizedAudio = false
  }

  /// 供悬浮迷你条直接控制播放/暂停。
  func togglePlaybackFromShell() {
    togglePlayback()
    notifyMiniMusicStateIfNeeded()
  }

  /// 供悬浮迷你条直接切到下一首。
  func nextTrackFromShell() {
    playNextTrack()
  }

  /// 构造当前曲目的迷你播放条状态快照。
  func currentMiniMusicState() -> NativeMiniMusicState {
    let subtitleParts = [manifest.artist, manifest.album]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return NativeMiniMusicState(
      title: displayTitle,
      subtitle: subtitleParts.joined(separator: " · "),
      artwork: currentMiniArtworkImage,
      isPlaying: player.isPlaying,
      progress: lastKnownProgress,
      hasNext: queue.count > 1 && queueIndex + 1 < queue.count
    )
  }

  /// 仅当处于音乐最小化状态时向宿主推送迷你条最新状态。
  private func notifyMiniMusicStateIfNeeded() {
    guard isAudioPlayback, isMinimizedAudio, !closed else { return }
    onAudioMiniStateChanged?(currentMiniMusicState())
  }

  /// 显示视频控制栏与渐变遮罩并在短暂停留后自动淡出。
  private func showControls() {
    guard !isAudioPlayback, !isLocked, !pictureInPicture.keepsPlaybackAlive else { return }
    controlsVisible = true
    hideControlsTask?.cancel()
    UIView.animate(withDuration: 0.18) {
      self.topBar.alpha = 1
      self.topScrimView.alpha = 1
      self.controls.alpha = 1
      self.bottomScrimView.alpha = 1
      self.transport.alpha = 1
      if self.isVideoLandscape {
        self.lockTopButton.isHidden = false
        self.lockTopButton.alpha = 1
      }
    }
    setNeedsStatusBarAppearanceUpdate()
    scheduleControlsHide()
  }

  /// 在视频播放且没有系统弹窗时隐藏控制栏与渐变遮罩。
  private func hideControls() {
    guard !isAudioPlayback, !pictureInPicture.keepsPlaybackAlive else { return }
    controlsVisible = false
    UIView.animate(withDuration: 0.25) {
      self.topBar.alpha = 0
      self.topScrimView.alpha = 0
      self.controls.alpha = 0
      self.bottomScrimView.alpha = 0
      self.transport.alpha = 0
      if !self.isLocked {
        self.lockTopButton.alpha = 0
      }
    }
    setNeedsStatusBarAppearanceUpdate()
  }

  /// 为活动视频播放安排控制栏自动隐藏。
  private func scheduleControlsHide() {
    hideControlsTask?.cancel()
    guard playbackDidAppear, player.isPlaying, !isAudioPlayback, !isScrubbing, !isLocked,
      !pictureInPicture.keepsPlaybackAlive
    else {
      return
    }
    hideControlsTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled, let self else { return }
      self.hideControlsTask = nil
      guard self.presentedViewController == nil else { return }
      self.hideControls()
    }
  }

  /// 显示内嵌和外挂字幕选项并标记当前激活轨道。
  private func showSubtitleMenu() {
    let alert = UIAlertController(
      title: L10n.text("字幕"), message: nil, preferredStyle: .actionSheet)
    let tracks = player.textTracks
    let anySelected = tracks.contains(where: \.isSelected) || activeExternalSubtitleID != nil
    alert.addAction(
      UIAlertAction(title: "\(anySelected ? "" : "✓ ")\(L10n.text("关闭字幕"))", style: .default) {
        [weak self] _ in
        guard let self else { return }
        self.activeExternalSubtitleID = nil
        self.player.deselectAllTextTracks()
      })
    for track in tracks {
      let name =
        track.trackName.isEmpty ? (track.trackDescription ?? L10n.text("字幕")) : track.trackName
      let prefix = (track.isSelected && activeExternalSubtitleID == nil) ? "✓ " : ""
      alert.addAction(
        UIAlertAction(title: "\(prefix)\(L10n.format("内嵌 · %@", name))", style: .default) {
          [weak self] _ in
          self?.activeExternalSubtitleID = nil
          track.isSelectedExclusively = true
        })
    }
    for subtitle in manifest.subtitles {
      let prefix = activeExternalSubtitleID == subtitle.subtitleId ? "✓ " : ""
      alert.addAction(
        UIAlertAction(
          title: "\(prefix)\(subtitle.language ?? L10n.text("外挂")) · \(subtitle.title)",
          style: .default
        ) { [weak self] _ in
          self?.loadSubtitle(subtitle)
        })
    }
    alert.addAction(UIAlertAction(title: L10n.text("取消"), style: .cancel))
    presentActionSheet(alert, from: subtitleButton.isHidden ? topBar : subtitleButton)
  }

  /// 通过当前授权下载用户所选外挂字幕并挂载到当前解码会话（避免重复加载同一外挂字幕）。
  private func loadSubtitle(_ subtitle: MediaPlaybackSubtitle) {
    guard let client else { return }
    guard activeExternalSubtitleID != subtitle.subtitleId else { return }
    subtitleTask?.cancel()
    subtitleTask = Task { [weak self] in
      guard let self else { return }
      do {
        let fileURL = try await client.download(subtitle, itemId: self.itemId)
        guard !Task.isCancelled, !self.closed else {
          try? FileManager.default.removeItem(at: fileURL)
          return
        }
        self.subtitleFiles.append(fileURL)
        self.activeSubtitleFile = fileURL
        self.activeExternalSubtitleID = subtitle.subtitleId
        _ = self.player.addPlaybackSlave(fileURL, type: .subtitle, enforce: true)
        self.showControls()
      } catch {
        guard !Task.isCancelled else { return }
        self.showError(error.localizedDescription)
      }
    }
  }

  /// 显示当前内嵌音轨并标记正在播放的音轨。
  private func showAudioMenu() {
    let tracks = player.audioTracks
    let alert = UIAlertController(
      title: L10n.text("音轨"), message: nil, preferredStyle: .actionSheet)
    for track in tracks {
      let name =
        track.trackName.isEmpty ? (track.trackDescription ?? L10n.text("音轨")) : track.trackName
      let prefix = track.isSelected ? "✓ " : ""
      alert.addAction(
        UIAlertAction(title: "\(prefix)\(name)", style: .default) { _ in
          track.isSelectedExclusively = true
        })
    }
    alert.addAction(UIAlertAction(title: L10n.text("取消"), style: .cancel))
    presentActionSheet(alert, from: audioButton.isHidden ? topBar : audioButton)
  }

  /// 显示常用播放速度并实时更新底坞倍速徽标。
  private func showSpeedMenu() {
    let alert = UIAlertController(
      title: L10n.text("播放速度"), message: nil, preferredStyle: .actionSheet)
    for rate: Float in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
      let label = rate == 1.0 ? L10n.text("正常速度 (1.0x)") : "\(rate.formatted())x"
      let prefix = abs(rate - currentPlaybackRate) < 0.01 ? "✓ " : ""
      alert.addAction(
        UIAlertAction(title: "\(prefix)\(label)", style: .default) { [weak self] _ in
          guard let self else { return }
          self.currentPlaybackRate = rate
          self.player.rate = rate
          self.playButton.accessibilityValue = L10n.format("%@ 倍", rate.formatted())
          if var config = self.speedButton.configuration {
            config.baseForegroundColor =
              abs(rate - 1.0) < 0.01
              ? UIColor.white.withAlphaComponent(0.90)
              : UIColor(red: 0.84, green: 0.72, blue: 1.0, alpha: 1.0)
            self.speedButton.configuration = config
          }
          if !self.isAudioPlayback {
            self.presentSeekHud("\(rate.formatted())x")
          }
        })
    }
    alert.addAction(UIAlertAction(title: L10n.text("取消"), style: .cancel))
    presentActionSheet(alert, from: isAudioPlayback ? topBar : speedButton)
  }

  /// 为 iPad 弹出菜单设置安全锚点，iPhone 仍显示系统操作面板。
  private func presentActionSheet(_ alert: UIAlertController, from source: UIView) {
    if let popover = alert.popoverPresentationController {
      popover.sourceView = source
      popover.sourceRect = source.bounds
    }
    present(alert, animated: true)
  }

  /// 以固定提示显示网络或播放错误，不展示上游 URL 和敏感响应正文。
  private func showError(_ message: String) {
    guard view.window != nil else { return }
    let alert = UIAlertController(
      title: L10n.text("播放暂不可用"), message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: L10n.text("好"), style: .default))
    present(alert, animated: true)
  }

  /// 停止当前播放并立即关闭播放器控制器（不等待后台解码线程同步 join）。
  private func dismissPlayback() {
    closeFromShell()
  }

  /// 立即解除 UI/定时/画中画绑定，并将 `VLCMediaPlayer.stop()`、音频会话释放与临时文件清理全部移交后台串行队列，彻底根除点返回主线程死锁。
  private func closePlayback() {
    guard !closed else { return }
    if hasPlayedCurrentItem {
      reportPlaybackProgress(state: "stopped", force: true)
    }
    closed = true
    updateTimer?.invalidate()
    updateTimer = nil
    upNextTask?.cancel()
    upNextTask = nil
    subtitleTask?.cancel()
    lyricsTask?.cancel()
    artworkTask?.cancel()
    trackSwitchTask?.cancel()
    hideControlsTask?.cancel()
    seekHudTask?.cancel()
    NotificationCenter.default.removeObserver(self)
    pictureInPicture.stop()

    let center = MPRemoteCommandCenter.shared()
    center.playCommand.removeTarget(self)
    center.pauseCommand.removeTarget(self)
    center.togglePlayPauseCommand.removeTarget(self)
    center.changePlaybackPositionCommand.removeTarget(self)
    center.skipForwardCommand.removeTarget(self)
    center.skipBackwardCommand.removeTarget(self)
    center.nextTrackCommand.removeTarget(self)
    center.previousTrackCommand.removeTarget(self)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped

    // 立即解绑渲染表面与代理并异步停止 libVLC，避免 vout 与主线程死锁导致界面卡死。
    player.delegate = nil
    player.drawable = nil
    let playerToStop = player
    if audioSessionClaimed {
      audioSessionClaimed = false
      Self.activeAudioSessions.withLock { $0 = max(0, $0 - 1) }
    }
    var filesToClean = subtitleFiles
    if manifest.contentUrl.isFileURL,
      manifest.contentUrl.lastPathComponent.hasPrefix("moviepilot-play-")
        || deleteContentFileOnClose
    {
      filesToClean.append(manifest.contentUrl)
    }
    let filesSnapshot = filesToClean
    let leaseToRelease = securityScopeLease
    subtitleFiles.removeAll()
    activeSubtitleFile = nil

    Self.teardownQueue.async {
      playerToStop.stop()
      playerToStop.media = nil
      if Self.activeAudioSessions.withLock({ $0 == 0 }) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      }
      for file in filesSnapshot {
        try? FileManager.default.removeItem(at: file)
      }
      leaseToRelease?.release()
    }
  }

  /// 返回实例与媒体条目隔离的本地播放进度键。
  private var progressKey: String {
    let value = Data("\(instanceId.uuidString):\(manifest.server ?? ""):\(itemId)".utf8)
    return
      "moviepilot.playback.\(SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined())"
  }

  /// 锁屏播放命令恢复解码器。
  @objc private func remotePlay() -> MPRemoteCommandHandlerStatus {
    guard !interruption.isInterrupted else { return .commandFailed }
    player.play()
    return .success
  }

  /// 锁屏暂停命令暂停解码器。
  @objc private func remotePause() -> MPRemoteCommandHandlerStatus {
    interruption.cancelResume()
    player.pause()
    showControls()
    return .success
  }

  /// 锁屏播放/暂停命令切换当前解码器状态。
  @objc private func remoteToggle() -> MPRemoteCommandHandlerStatus {
    togglePlayback()
    return .success
  }

  /// 锁屏位置拖动命令跳转到指定秒数。
  @objc private func remoteSeek(_ event: MPChangePlaybackPositionCommandEvent)
    -> MPRemoteCommandHandlerStatus
  {
    let milliseconds = Int(max(0, event.positionTime) * 1000)
    player.time = VLCTime(int: Int32(clamping: milliseconds))
    return .success
  }

  /// 耳机前进命令跳过 10 秒。
  @objc private func remoteForward() -> MPRemoteCommandHandlerStatus {
    skip(seconds: 10)
    return .success
  }

  /// 耳机后退命令回退 10 秒。
  @objc private func remoteBackward() -> MPRemoteCommandHandlerStatus {
    skip(seconds: -10)
    return .success
  }

  /// 锁屏上一首命令沿用界面按钮的三秒重播规则。
  @objc private func remotePreviousTrack() -> MPRemoteCommandHandlerStatus {
    playPreviousTrack()
    return .success
  }

  /// 锁屏下一首命令切到队列中的下一项。
  @objc private func remoteNextTrack() -> MPRemoteCommandHandlerStatus {
    playNextTrack()
    return .success
  }
}

/// 后端统一 envelope 只在成功响应中提供清单。
private struct MediaPlaybackEnvelope<Value: Decodable>: Decodable {
  let success: Bool
  let data: Value?
}
