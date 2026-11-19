import AVFoundation
import AVKit
import CryptoKit
import ImageIO
import MediaPlayer
import MoviePilotCore
import UIKit
import VLCKit

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
}

/// 后端发现的一条同名外挂字幕；内嵌字幕由 VLCKit 读取。
struct MediaPlaybackSubtitle: Decodable, Sendable {
  let subtitleId: String
  let title: String
  let language: String?
  let url: URL
}

/// 网页已按曲序映射到媒体服务器的单曲信息。
struct MediaPlaybackQueueItem: Decodable, Sendable {
  let itemId: String
  let title: String
  let server: String?
  let artworkURL: String?
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

  /// 使用当前实例访问令牌读取已入库条目、流地址和外挂字幕清单。
  func loadManifest(itemId: String, server: String? = nil) async throws -> MediaPlaybackManifest {
    selectedServer = server
    var queryItems = [URLQueryItem(name: "itemid", value: itemId)]
    if let server { queryItems.append(URLQueryItem(name: "server", value: server)) }
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
      isTrustedMediaURL(manifest.contentUrl, itemId: itemId, server: server)
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
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("moviepilot-\(UUID().uuidString)")
      .appendingPathExtension(
        subtitle.url.pathExtension.isEmpty ? "srt" : subtitle.url.pathExtension)
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

  /// 为解码器构造媒体对象，并将资源 Cookie 限制到当前实例的媒体流路径。
  func makeMedia(url: URL) throws -> VLCMedia {
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
  private func isTrustedMediaURL(_ url: URL, itemId: String, server: String?) -> Bool {
    guard address.contains(url), url.user == nil, url.password == nil, url.fragment == nil,
      url.path == endpoint(["api", "v1", "mediaserver", "stream"]).path,
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return false }
    return queryItems.count == (server == nil ? 1 : 2)
      && queryItems.first(where: { $0.name == "itemid" })?.value == itemId
      && (server == nil || queryItems.first(where: { $0.name == "server" })?.value == server)
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

/// 使用原生 UIKit 控件驱动 VLCKit，支持常见容器、内嵌音轨、字幕和远程控制。
@MainActor
final class MediaPlaybackViewController: UIViewController, UIGestureRecognizerDelegate {
  private var manifest: MediaPlaybackManifest
  private let client: MediaPlaybackClient
  private let instanceId: UUID
  private var itemId: String
  private var displayTitle: String
  private var artworkURL: URL?
  private let queue: [MediaPlaybackQueueItem]
  private var queueIndex: Int
  private let player = VLCMediaPlayer(options: ["--no-mouse-events", "--no-keyboard-events"])
  private let videoView = UIView()
  private let musicBackdropImageView = UIImageView()
  private let musicBackdropBlur = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let musicBackdropShade = UIView()
  private let musicStage = UIView()
  private let musicArtwork = UIImageView()
  private let musicArtworkPlaceholder = UIImageView(image: UIImage(systemName: "music.note"))
  private let lyricsScroll = UIScrollView()
  private let lyricsStack = UIStackView()
  private let musicArtistLabel = UILabel()
  private let musicAlbumLabel = UILabel()
  private let controls = UIView()
  private let transport = UIStackView()
  private let topBar = UIStackView()
  private let progressPanel = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let elapsedLabel = UILabel()
  private let durationLabel = UILabel()
  private let loading = UIActivityIndicatorView(style: .large)
  private let titleLabel = UILabel()
  private let musicTitleLabel = UILabel()
  private let playButton = UIButton(type: .system)
  private let skipBackButton = UIButton(type: .system)
  private let skipForwardButton = UIButton(type: .system)
  private let subtitleButton = UIButton(type: .system)
  private let audioButton = UIButton(type: .system)
  private let trackOptionsPill = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
  private let positionSlider = UISlider()
  private weak var playbackMenuButton: UIButton?
  private var pictureInPictureAvailable = false
  private let onMinimize: (MediaPlaybackViewController) -> Void
  private let onExpand: (MediaPlaybackViewController) -> Void
  private let onClosePlayback: (MediaPlaybackViewController) -> Void
  private var updateTimer: Timer?
  private var hideControlsTask: Task<Void, Never>?
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

  /// 系统画中画复用当前采样层；只有进入成功后才让 Shell 隐藏全屏容器。
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

  /// 建立單條目播放器，進度按服務實例和媒體條目隔離在本機保存。
  init(
    manifest: MediaPlaybackManifest,
    client: MediaPlaybackClient,
    instanceId: UUID,
    itemId: String,
    displayTitle: String,
    artworkURL: URL? = nil,
    queue: [MediaPlaybackQueueItem] = [],
    queueIndex: Int = 0,
    onMinimize: @escaping (MediaPlaybackViewController) -> Void,
    onExpand: @escaping (MediaPlaybackViewController) -> Void,
    onClosePlayback: @escaping (MediaPlaybackViewController) -> Void
  ) {
    self.manifest = manifest
    self.client = client
    self.instanceId = instanceId
    self.itemId = itemId
    self.displayTitle = displayTitle
    self.artworkURL = artworkURL
    self.queue = queue
    self.queueIndex = queue.indices.contains(queueIndex) ? queueIndex : 0
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
    configureViews()
    guard configurePlayer() else { return }
    configureAudioSession()
    configureRemoteCommands()
    updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshPlaybackState() }
    }
    player.play()
    if isAudioPlayback {
      loadLyrics()
      loadArtwork()
    }
  }

  /// 恢复全屏后重新启用控制栏自动隐藏。
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    playbackDidAppear = true
    scheduleControlsHide()
  }

  /// 全屏视频允许设备旋转，布局始终保持画面等比显示。
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

  /// 黑色沉浸播放页始终使用浅色状态栏图标。
  override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

  /// 播放结束或控制器关闭时停止计时、声音会话、远程命令和临时字幕。
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isMovingFromParent || (view.window == nil && !pictureInPicture.keepsPlaybackAlive) {
      closePlayback()
    }
  }

  /// 创建视频画布、系统玻璃顶栏与独立控制区。
  private func configureViews() {
    if isAudioPlayback { configureMusicBackdrop() }
    videoView.translatesAutoresizingMaskIntoConstraints = false
    videoView.backgroundColor = .black
    // VLC 的 DVD 鼠标手势不参与 App 控制，触摸统一交给外层控制器。
    videoView.isUserInteractionEnabled = false
    videoView.accessibilityLabel = L10n.text("视频画面")
    videoView.isAccessibilityElement = true
    videoView.isHidden = isAudioPlayback
    view.addSubview(videoView)
    NSLayoutConstraint.activate([
      videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      videoView.topAnchor.constraint(equalTo: view.topAnchor),
      videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    loading.translatesAutoresizingMaskIntoConstraints = false
    loading.color = .white
    view.addSubview(loading)
    NSLayoutConstraint.activate([
      loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    loading.startAnimating()

    titleLabel.textColor = .white
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 1
    titleLabel.textAlignment = .center
    titleLabel.text = isAudioPlayback ? L10n.text("正在播放") : displayTitle
    titleLabel.isHidden = false
    titleLabel.accessibilityIdentifier = "playback-title"
    let closeButton: UIButton
    if isAudioPlayback {
      closeButton = UIButton(type: .system)
      configureMusicCircleButton(
        closeButton, symbol: "chevron.down", accessibility: L10n.text("关闭播放器"), diameter: 44,
        pointSize: 18, primary: false)
      closeButton.accessibilityIdentifier = "music-playback-close"
    } else {
      closeButton = makeGlassButton(
        symbol: "chevron.left", accessibility: L10n.text("关闭播放器"), diameter: 44, pointSize: 18)
    }
    closeButton.addAction(
      UIAction { [weak self] _ in self?.dismissPlayback() }, for: .touchUpInside)
    let moreButton = makeGlassButton(
      symbol: "ellipsis", accessibility: L10n.text("更多播放选项"), diameter: 44, pointSize: 18)
    moreButton.isHidden = isAudioPlayback
    moreButton.showsMenuAsPrimaryAction = true
    playbackMenuButton = moreButton
    moreButton.menu = makePlaybackMenu()
    topBar.addArrangedSubview(fixedSquareControl(closeButton, diameter: 44))
    topBar.addArrangedSubview(titleLabel)
    if isAudioPlayback {
      let routePicker = AVRoutePickerView()
      routePicker.activeTintColor = .white
      routePicker.tintColor = UIColor.white.withAlphaComponent(0.82)
      routePicker.accessibilityIdentifier = "music-playback-output"
      topBar.addArrangedSubview(fixedSquareControl(routePicker, diameter: 44))
    } else {
      topBar.addArrangedSubview(fixedSquareControl(moreButton, diameter: 44))
    }
    topBar.axis = .horizontal
    topBar.alignment = .center
    topBar.distribution = isAudioPlayback ? .equalSpacing : .fill
    topBar.spacing = 12
    topBar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(topBar)
    NSLayoutConstraint.activate([
      topBar.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      topBar.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
    ])

    configureControls()
    if isAudioPlayback { configureMusicStage(below: topBar) }
  }

  /// 将小窗、字幕、音轨和倍速操作集中放在右上角菜单。
  private func makePlaybackMenu() -> UIMenu {
    let pipAction = UIAction(
      title: L10n.text("小窗播放"), image: UIImage(systemName: "pip.enter"),
      attributes: pictureInPictureAvailable ? [] : .disabled
    ) { [weak self] _ in
      self?.minimizePlayback()
    }
    let subtitlesAction = UIAction(
      title: L10n.text("选择字幕"), image: UIImage(systemName: "captions.bubble")
    ) { [weak self] _ in self?.showSubtitleMenu() }
    let audioAction = UIAction(
      title: L10n.text("选择音轨"), image: UIImage(systemName: "waveform")
    ) { [weak self] _ in self?.showAudioMenu() }
    let speedAction = UIAction(
      title: L10n.text("播放速度"), image: UIImage(systemName: "speedometer")
    ) { [weak self] _ in self?.showSpeedMenu() }
    return UIMenu(children: [pipAction, subtitlesAction, audioAction, speedAction])
  }

  /// 画中画准备好后启用菜单项目，等待视频首帧期间保持禁用。
  private func updatePictureInPictureAvailability(_ available: Bool) {
    guard pictureInPictureAvailable != available else { return }
    pictureInPictureAvailable = available
    playbackMenuButton?.menu = makePlaybackMenu()
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

  /// 配置音乐页的主播放圆键和玻璃跳转键。
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
        button.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        button.layer.cornerRadius = diameter / 2
        button.layer.borderWidth = 0.8
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
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

  /// 创建三枚玻璃拟态传输键、磨砂进度胶囊和仅含字幕音轨的底栏。
  private func configureControls() {
    controls.translatesAutoresizingMaskIntoConstraints = false
    controls.backgroundColor = .clear
    view.addSubview(controls)
    NSLayoutConstraint.activate([
      controls.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 22),
      controls.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -22),
      controls.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
    ])

    positionSlider.minimumValue = 0
    positionSlider.maximumValue = 1
    positionSlider.accessibilityLabel = L10n.text("播放进度")
    positionSlider.accessibilityIdentifier = "playback-progress"
    positionSlider.minimumTrackTintColor = .white
    positionSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
    positionSlider.setThumbImage(
      UIImage(systemName: "circle.fill")?.withConfiguration(
        UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)),
      for: .normal)
    positionSlider.addTarget(self, action: #selector(beginScrubbing), for: .touchDown)
    positionSlider.addTarget(
      self, action: #selector(endScrubbing), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    positionSlider.heightAnchor.constraint(equalToConstant: 28).isActive = true

    elapsedLabel.text = Self.format(milliseconds: 0)
    durationLabel.text = Self.format(milliseconds: 0)
    for label in [elapsedLabel, durationLabel] {
      label.textColor = .white
      label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
      label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    let progressRow = UIStackView(arrangedSubviews: [elapsedLabel, positionSlider, durationLabel])
    progressRow.axis = .horizontal
    progressRow.alignment = .center
    progressRow.spacing = 8
    progressRow.translatesAutoresizingMaskIntoConstraints = false
    progressPanel.layer.cornerRadius = 18
    progressPanel.layer.cornerCurve = .continuous
    progressPanel.layer.borderWidth = isAudioPlayback ? 0 : 0.8
    progressPanel.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
    progressPanel.clipsToBounds = !isAudioPlayback
    if isAudioPlayback {
      progressPanel.backgroundColor = .clear
      progressPanel.effect = nil
    }
    progressPanel.translatesAutoresizingMaskIntoConstraints = false
    progressPanel.contentView.addSubview(progressRow)
    NSLayoutConstraint.activate([
      progressRow.leadingAnchor.constraint(
        equalTo: progressPanel.contentView.leadingAnchor, constant: isAudioPlayback ? 0 : 12),
      progressRow.trailingAnchor.constraint(
        equalTo: progressPanel.contentView.trailingAnchor, constant: isAudioPlayback ? 0 : -12),
      progressRow.topAnchor.constraint(
        equalTo: progressPanel.contentView.topAnchor, constant: isAudioPlayback ? 0 : 6),
      progressRow.bottomAnchor.constraint(
        equalTo: progressPanel.contentView.bottomAnchor, constant: isAudioPlayback ? 0 : -6),
      progressPanel.heightAnchor.constraint(equalToConstant: 50),
    ])

    if isAudioPlayback {
      configureMusicCircleButton(
        skipBackButton, symbol: "backward.end.fill", accessibility: L10n.text("上一首"),
        diameter: 54, pointSize: 21, primary: false)
      skipBackButton.accessibilityIdentifier = "music-playback-back"
      configureMusicCircleButton(
        playButton, symbol: "pause.fill", accessibility: L10n.text("暂停"), diameter: 76,
        pointSize: 28, primary: true)
      playButton.accessibilityIdentifier = "music-playback-toggle"
      configureMusicCircleButton(
        skipForwardButton, symbol: "forward.end.fill", accessibility: L10n.text("下一首"),
        diameter: 54, pointSize: 21, primary: false)
      skipForwardButton.accessibilityIdentifier = "music-playback-forward"
    } else {
      configureGlassButton(
        skipBackButton, symbol: "gobackward.10", accessibility: L10n.text("后退 10 秒"),
        diameter: 62, pointSize: 22)
      configureGlassButton(
        playButton, symbol: "pause.fill", accessibility: L10n.text("暂停"), diameter: 88,
        pointSize: 30)
      configureGlassButton(
        skipForwardButton, symbol: "goforward.10", accessibility: L10n.text("前进 10 秒"),
        diameter: 62, pointSize: 22)
    }
    skipBackButton.addAction(
      UIAction { [weak self] _ in
        if self?.isAudioPlayback == true {
          self?.playPreviousTrack()
        } else {
          self?.skip(seconds: -10)
        }
      }, for: .touchUpInside)
    playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
    playButton.accessibilityLabel = L10n.text("暂停")
    if !isAudioPlayback {
      playButton.setPreferredSymbolConfiguration(
        UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold), forImageIn: .normal)
    }
    playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
    skipForwardButton.addAction(
      UIAction { [weak self] _ in
        if self?.isAudioPlayback == true { self?.playNextTrack() } else { self?.skip(seconds: 10) }
      }, for: .touchUpInside)
    transport.axis = .horizontal
    transport.alignment = .center
    transport.distribution = isAudioPlayback ? .equalSpacing : .fill
    transport.spacing = isAudioPlayback ? 0 : 24
    transport.translatesAutoresizingMaskIntoConstraints = false
    if isAudioPlayback {
      transport.addArrangedSubview(fixedSquareControl(skipBackButton, diameter: 54))
      transport.addArrangedSubview(fixedSquareControl(playButton, diameter: 76))
      transport.addArrangedSubview(fixedSquareControl(skipForwardButton, diameter: 54))
      transport.widthAnchor.constraint(equalToConstant: 228).isActive = true
      transport.heightAnchor.constraint(equalToConstant: 76).isActive = true
    } else {
      transport.addArrangedSubview(skipBackButton)
      transport.addArrangedSubview(playButton)
      transport.addArrangedSubview(skipForwardButton)
      view.addSubview(transport)
      NSLayoutConstraint.activate([
        transport.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        transport.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
    }

    subtitleButton.setImage(UIImage(systemName: "captions.bubble"), for: .normal)
    subtitleButton.accessibilityLabel = L10n.text("选择字幕")
    subtitleButton.addAction(
      UIAction { [weak self] _ in self?.showSubtitleMenu() }, for: .touchUpInside)
    audioButton.setImage(UIImage(systemName: "waveform"), for: .normal)
    audioButton.accessibilityLabel = L10n.text("选择音轨")
    audioButton.addAction(UIAction { [weak self] _ in self?.showAudioMenu() }, for: .touchUpInside)
    for button in [subtitleButton, audioButton] {
      button.tintColor = .white
      button.backgroundColor = .clear
      button.setPreferredSymbolConfiguration(
        UIImage.SymbolConfiguration(pointSize: 18, weight: .medium), forImageIn: .normal)
      button.widthAnchor.constraint(equalToConstant: 44).isActive = true
      button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    if isAudioPlayback {
      subtitleButton.isHidden = true
      audioButton.isHidden = true
    }
    trackOptionsPill.accessibilityIdentifier = "playback-track-options"
    trackOptionsPill.isHidden = subtitleButton.isHidden && audioButton.isHidden
    trackOptionsPill.layer.cornerRadius = 22
    trackOptionsPill.layer.cornerCurve = .continuous
    trackOptionsPill.layer.borderWidth = 0.8
    trackOptionsPill.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
    trackOptionsPill.clipsToBounds = true
    trackOptionsPill.translatesAutoresizingMaskIntoConstraints = false
    let options = UIStackView(arrangedSubviews: [subtitleButton, audioButton])
    options.axis = .horizontal
    options.alignment = .center
    options.distribution = .fill
    options.spacing = 2
    options.translatesAutoresizingMaskIntoConstraints = false
    trackOptionsPill.contentView.addSubview(options)
    NSLayoutConstraint.activate([
      options.leadingAnchor.constraint(
        equalTo: trackOptionsPill.contentView.leadingAnchor, constant: 4),
      options.trailingAnchor.constraint(
        equalTo: trackOptionsPill.contentView.trailingAnchor, constant: -4),
      options.topAnchor.constraint(equalTo: trackOptionsPill.contentView.topAnchor),
      options.bottomAnchor.constraint(equalTo: trackOptionsPill.contentView.bottomAnchor),
      trackOptionsPill.heightAnchor.constraint(equalToConstant: 44),
    ])

    let spacer = UIView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let footer = UIStackView(arrangedSubviews: [spacer, trackOptionsPill])
    footer.axis = .horizontal
    footer.alignment = .center
    footer.spacing = 8

    trackOptionsPill.isHidden = isAudioPlayback || (subtitleButton.isHidden && audioButton.isHidden)
    let stack = UIStackView(arrangedSubviews: [progressPanel, isAudioPlayback ? transport : footer])
    stack.axis = .vertical
    stack.alignment = isAudioPlayback ? .center : .fill
    stack.spacing = isAudioPlayback ? 14 : 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    controls.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
      stack.topAnchor.constraint(equalTo: controls.topAnchor),
      stack.bottomAnchor.constraint(equalTo: controls.bottomAnchor),
    ])
    if isAudioPlayback {
      progressPanel.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
    }
    refreshQueueControls(current: 0)

    let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
    tap.delegate = self
    tap.cancelsTouchesInView = false
    view.addGestureRecognizer(tap)
  }

  /// 为 Now Playing 页面铺设封面取色背景、暗化与模糊层。
  private func configureMusicBackdrop() {
    musicBackdropImageView.translatesAutoresizingMaskIntoConstraints = false
    musicBackdropImageView.contentMode = .scaleAspectFill
    musicBackdropImageView.clipsToBounds = true
    musicBackdropImageView.accessibilityIdentifier = "music-playback-backdrop"
    view.addSubview(musicBackdropImageView)
    musicBackdropBlur.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(musicBackdropBlur)
    musicBackdropShade.translatesAutoresizingMaskIntoConstraints = false
    musicBackdropShade.backgroundColor = UIColor.black.withAlphaComponent(0.38)
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

  /// 显示封面、曲目信息与同步歌词，沿用 Apple Music Now Playing 的层次。
  private func configureMusicStage(below topBar: UIView) {
    musicStage.translatesAutoresizingMaskIntoConstraints = false
    musicStage.accessibilityIdentifier = "music-playback-stage"
    view.addSubview(musicStage)
    NSLayoutConstraint.activate([
      musicStage.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 26),
      musicStage.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -26),
      musicStage.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
      musicStage.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -14),
    ])

    musicArtwork.translatesAutoresizingMaskIntoConstraints = false
    musicArtwork.accessibilityIdentifier = "music-playback-artwork"
    musicArtwork.accessibilityLabel = L10n.text("专辑封面")
    musicArtwork.isAccessibilityElement = true
    musicArtwork.accessibilityValue = L10n.text("专辑封面加载中")
    musicArtwork.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    musicArtwork.contentMode = .scaleAspectFill
    musicArtwork.clipsToBounds = true
    musicArtwork.layer.cornerRadius = 18
    musicArtwork.layer.cornerCurve = .continuous
    musicArtworkPlaceholder.translatesAutoresizingMaskIntoConstraints = false
    musicArtworkPlaceholder.tintColor = UIColor.white.withAlphaComponent(0.82)
    musicArtworkPlaceholder.contentMode = .scaleAspectFit
    musicArtwork.addSubview(musicArtworkPlaceholder)
    NSLayoutConstraint.activate([
      musicArtworkPlaceholder.centerXAnchor.constraint(equalTo: musicArtwork.centerXAnchor),
      musicArtworkPlaceholder.centerYAnchor.constraint(equalTo: musicArtwork.centerYAnchor),
      musicArtworkPlaceholder.widthAnchor.constraint(equalToConstant: 52),
      musicArtworkPlaceholder.heightAnchor.constraint(equalToConstant: 62),
    ])

    musicTitleLabel.text = displayTitle
    musicTitleLabel.font = .preferredFont(forTextStyle: .title1)
    musicTitleLabel.adjustsFontForContentSizeCategory = true
    musicTitleLabel.textColor = .white
    musicTitleLabel.textAlignment = .center
    musicTitleLabel.numberOfLines = 2
    musicTitleLabel.accessibilityIdentifier = "music-playback-title"
    musicArtistLabel.text = manifest.artist ?? L10n.text("未知艺人")
    musicArtistLabel.font = .preferredFont(forTextStyle: .headline)
    musicArtistLabel.textColor = UIColor.white.withAlphaComponent(0.84)
    musicArtistLabel.textAlignment = .center
    musicArtistLabel.isHidden = manifest.artist?.isEmpty ?? true
    musicAlbumLabel.text = manifest.album
    musicAlbumLabel.font = .preferredFont(forTextStyle: .subheadline)
    musicAlbumLabel.textColor = UIColor.white.withAlphaComponent(0.62)
    musicAlbumLabel.textAlignment = .center
    musicAlbumLabel.isHidden = manifest.album?.isEmpty ?? true
    let metadata = UIStackView(arrangedSubviews: [
      musicTitleLabel, musicArtistLabel, musicAlbumLabel,
    ])
    metadata.axis = .vertical
    metadata.alignment = .fill
    metadata.spacing = 4

    lyricsScroll.translatesAutoresizingMaskIntoConstraints = false
    lyricsScroll.showsVerticalScrollIndicator = false
    lyricsScroll.accessibilityIdentifier = "music-playback-lyrics"
    lyricsStack.axis = .vertical
    lyricsStack.alignment = .fill
    lyricsStack.spacing = 12
    lyricsStack.translatesAutoresizingMaskIntoConstraints = false
    lyricsScroll.addSubview(lyricsStack)
    NSLayoutConstraint.activate([
      lyricsStack.leadingAnchor.constraint(equalTo: lyricsScroll.contentLayoutGuide.leadingAnchor),
      lyricsStack.trailingAnchor.constraint(
        equalTo: lyricsScroll.contentLayoutGuide.trailingAnchor),
      lyricsStack.topAnchor.constraint(
        equalTo: lyricsScroll.contentLayoutGuide.topAnchor, constant: 8),
      lyricsStack.bottomAnchor.constraint(
        equalTo: lyricsScroll.contentLayoutGuide.bottomAnchor, constant: -8),
      lyricsStack.widthAnchor.constraint(equalTo: lyricsScroll.frameLayoutGuide.widthAnchor),
    ])
    appendLyricPlaceholder(L10n.text("正在读取歌词…"))

    let artworkRow = UIView()
    artworkRow.translatesAutoresizingMaskIntoConstraints = false
    artworkRow.addSubview(musicArtwork)

    let content = UIStackView(arrangedSubviews: [artworkRow, metadata, lyricsScroll])
    content.axis = .vertical
    content.alignment = .fill
    content.spacing = 14
    content.translatesAutoresizingMaskIntoConstraints = false
    musicStage.addSubview(content)
    let preferredArtworkWidth = musicArtwork.widthAnchor.constraint(
      equalTo: musicStage.widthAnchor, multiplier: 0.68)
    preferredArtworkWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: musicStage.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: musicStage.trailingAnchor),
      content.topAnchor.constraint(equalTo: musicStage.topAnchor, constant: 12),
      content.bottomAnchor.constraint(lessThanOrEqualTo: musicStage.bottomAnchor),
      artworkRow.heightAnchor.constraint(equalTo: musicArtwork.heightAnchor),
      musicArtwork.centerXAnchor.constraint(equalTo: artworkRow.centerXAnchor),
      musicArtwork.centerYAnchor.constraint(equalTo: artworkRow.centerYAnchor),
      preferredArtworkWidth,
      musicArtwork.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
      musicArtwork.heightAnchor.constraint(equalTo: musicArtwork.widthAnchor),
      musicArtwork.heightAnchor.constraint(
        lessThanOrEqualTo: musicStage.heightAnchor, multiplier: 0.4),
      lyricsScroll.heightAnchor.constraint(equalToConstant: 152),
    ])
  }

  /// 在没有 LRC 文本或读取期间显示单行播放器状态。
  private func appendLyricPlaceholder(_ text: String) {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 2
    lyricsStack.addArrangedSubview(label)
  }

  /// 初始化解码器并绑定后端返回的同源媒体流。
  private func configurePlayer() -> Bool {
    player.drawable = videoView
    do {
      player.media = try client.makeMedia(url: manifest.contentUrl)
    } catch {
      showError(error.localizedDescription)
      return false
    }
    let saved = UserDefaults.standard.integer(forKey: progressKey)
    savedProgress = saved > 30_000 ? saved : nil
    return true
  }

  /// 通过授权歌词地址下载 LRC 并将时间轴绑定到当前播放器。
  private func loadLyrics() {
    guard let lyricsURL = manifest.lyricsUrl else {
      replaceLyrics(with: [])
      return
    }
    lyricsTask?.cancel()
    lyricsTask = Task { [weak self] in
      guard let self else { return }
      do {
        let text = try await self.client.downloadLyrics(lyricsURL, itemId: self.itemId)
        guard !Task.isCancelled, !self.closed else { return }
        self.replaceLyrics(with: Self.parseLyrics(text))
      } catch {
        guard !Task.isCancelled, !self.closed else { return }
        self.replaceLyrics(with: [])
      }
    }
  }

  /// 下载后端图片代理的单曲封面，并同步更新播放器背景与锁屏信息。
  private func loadArtwork() {
    guard let artworkURL else { return }
    artworkTask?.cancel()
    artworkTask = Task { [weak self] in
      guard let self, let image = try? await self.client.downloadArtwork(artworkURL),
        !Task.isCancelled, !self.closed
      else { return }
      self.musicArtwork.image = image
      self.musicArtwork.accessibilityValue = L10n.text("专辑封面已加载")
      self.musicArtworkPlaceholder.isHidden = true
      self.musicBackdropImageView.image = image
      self.nowPlayingArtwork = Self.makeNowPlayingArtwork(image)
      self.refreshNowPlayingInfo()
    }
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
      appendLyricPlaceholder(L10n.text("暂无同名 LRC 歌词"))
      return
    }
    for (index, cue) in cues.enumerated() {
      let button = UIButton(type: .system)
      button.setTitle(cue.text, for: .normal)
      button.titleLabel?.font = .preferredFont(forTextStyle: .title3)
      button.titleLabel?.adjustsFontForContentSizeCategory = true
      button.titleLabel?.numberOfLines = 0
      button.titleLabel?.textAlignment = .left
      button.tintColor = .white
      button.setTitleColor(UIColor.white.withAlphaComponent(0.58), for: .normal)
      button.accessibilityIdentifier = "playback-lyric-line-\(index)"
      button.accessibilityLabel = cue.text
      button.addAction(UIAction { [weak self] _ in self?.seekToLyric(index) }, for: .touchUpInside)
      lyricsStack.addArrangedSubview(button)
      lyricButtons.append(button)
    }
    refreshLyrics(currentMilliseconds: Int(player.time.intValue))
  }

  /// 按播放时间高亮当前歌词，并将变化后的行平滑滚动到视图中央。
  private func refreshLyrics(currentMilliseconds: Int) {
    guard isAudioPlayback, !lyricCues.isEmpty else { return }
    let seconds = Double(max(0, currentMilliseconds)) / 1000
    let nextIndex = lyricCues.lastIndex { $0.time <= seconds }
    guard nextIndex != activeLyricIndex else { return }
    activeLyricIndex = nextIndex
    for (index, button) in lyricButtons.enumerated() {
      let active = index == nextIndex
      button.alpha = active ? 1 : 0.7
      button.accessibilityValue = active ? L10n.text("当前播放") : nil
      button.setTitleColor(active ? .white : UIColor.white.withAlphaComponent(0.58), for: .normal)
      button.titleLabel?.font = .preferredFont(forTextStyle: active ? .title3 : .subheadline)
      button.titleLabel?.font = UIFont.systemFont(
        ofSize: UIFont.preferredFont(forTextStyle: active ? .title3 : .subheadline).pointSize,
        weight: active ? .semibold : .regular)
    }
    guard let nextIndex, lyricButtons.indices.contains(nextIndex) else { return }
    lyricsScroll.layoutIfNeeded()
    let button = lyricButtons[nextIndex]
    let targetY = max(0, button.frame.midY - lyricsScroll.bounds.height / 2)
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
    center.skipForwardCommand.isEnabled = true
    center.skipBackwardCommand.isEnabled = true
    center.nextTrackCommand.isEnabled = isAudioPlayback && queue.indices.contains(queueIndex + 1)
    center.previousTrackCommand.isEnabled = isAudioPlayback && queueIndex > 0
    if isAudioPlayback {
      center.skipForwardCommand.isEnabled = false
      center.skipBackwardCommand.isEnabled = false
    }
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
        pointSize: pointSize, weight: .medium)
      button.configuration = configuration
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: diameter),
        button.heightAnchor.constraint(equalToConstant: diameter),
      ])
      return
    }
    button.backgroundColor = UIColor.black.withAlphaComponent(0.16)
    button.layer.cornerRadius = diameter / 2
    button.layer.cornerCurve = .continuous
    button.layer.borderWidth = 0.8
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
    button.clipsToBounds = true
    button.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium), forImageIn: .normal)

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

  /// 创建采用 SF Symbols 的普通菜单按钮。
  private func makeButton(title: String?, symbol: String, accessibility: String) -> UIButton {
    let button = UIButton(type: .system)
    button.tintColor = .white
    button.setImage(UIImage(systemName: symbol), for: .normal)
    if let title { button.setTitle(title, for: .normal) }
    button.accessibilityLabel = accessibility
    return button
  }

  /// 以当前解码状态更新进度、可用轨道、锁屏信息和本地续播点。
  private func refreshPlaybackState() {
    guard !closed else { return }
    let current = max(0, Int(player.time.intValue))
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    if !isScrubbing {
      positionSlider.isEnabled = player.isSeekable && duration > 0
      positionSlider.value = duration > 0 ? min(1, Float(current) / Float(duration)) : 0
    }
    elapsedLabel.text = Self.format(milliseconds: current)
    durationLabel.text = Self.format(milliseconds: duration)
    playButton.setImage(
      UIImage(systemName: player.isPlaying ? "pause.fill" : "play.fill"), for: .normal)
    playButton.accessibilityLabel = player.isPlaying ? L10n.text("暂停") : L10n.text("播放")
    if !isAudioPlayback { pictureInPicture.refresh() }
    if player.isPlaying { loading.stopAnimating() }
    let subtitleTracks = player.textTracks
    let audioTracks = player.audioTracks
    if isAudioPlayback {
      subtitleButton.isHidden = true
      audioButton.isHidden = true
    } else {
      subtitleButton.isHidden = manifest.subtitles.isEmpty && subtitleTracks.isEmpty
      audioButton.isHidden = audioTracks.count <= 1
    }
    trackOptionsPill.isHidden = subtitleButton.isHidden && audioButton.isHidden
    refreshQueueControls(current: current)
    refreshNowPlayingInfo(current: current, duration: duration)
    if isAudioPlayback { refreshLyrics(currentMilliseconds: current) }
    offerResumeIfNeeded(duration: duration)
    if player.isPlaying {
      if controlsVisible, hideControlsTask == nil { scheduleControlsHide() }
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
      UIAlertAction(title: isAudioPlayback ? L10n.text("继续收听") : L10n.text("继续播放"), style: .default)
      { [weak self] _ in
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
    if player.isPlaying { player.pause() } else { player.play() }
    refreshPlaybackState()
    showControls()
  }

  /// 在可 seek 的媒体中按秒数跳转并刷新显示。
  private func skip(seconds: Int) {
    guard player.isSeekable else { return }
    let current = Int(player.time.intValue)
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    let target = min(duration, max(0, current + seconds * 1000))
    player.time = VLCTime(int: Int32(clamping: target))
    showControls()
  }

  /// 在首曲播放不足三秒时切到上一首，否则从头重播当前歌曲。
  private func playPreviousTrack() {
    let current = max(0, Int(player.time.intValue))
    guard current > 3_000 || queueIndex > 0 else { return }
    if current > 3_000 {
      player.time = VLCTime(int: 0)
      showControls()
    } else {
      switchTrack(at: queueIndex - 1)
    }
  }

  /// 播放当前队列中的下一首歌曲。
  private func playNextTrack() {
    switchTrack(at: queueIndex + 1)
  }

  /// 加载下一条媒体服务器流并同步更新曲目信息、封面和歌词。
  private func switchTrack(at index: Int) {
    guard isAudioPlayback, trackSwitchTask == nil, queue.indices.contains(index),
      index != queueIndex
    else { return }
    let item = queue[index]
    skipBackButton.isEnabled = false
    skipForwardButton.isEnabled = false
    MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
    MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
    trackSwitchTask = Task { [weak self] in
      guard let self else { return }
      do {
        let manifest = try await self.client.loadManifest(itemId: item.itemId, server: item.server)
        guard !Task.isCancelled, !self.closed else { return }
        let media = try self.client.makeMedia(url: manifest.contentUrl)
        self.player.stop()
        self.player.media = media
        self.manifest = manifest
        self.itemId = item.itemId
        self.displayTitle = item.title
        self.musicTitleLabel.text = item.title
        self.musicArtistLabel.text = manifest.artist
        self.musicArtistLabel.isHidden = manifest.artist?.isEmpty ?? true
        self.musicAlbumLabel.text = manifest.album
        self.musicAlbumLabel.isHidden = manifest.album?.isEmpty ?? true
        self.artworkURL = item.artworkURL.flatMap(URL.init(string:))
        self.musicArtwork.image = nil
        self.musicArtworkPlaceholder.isHidden = false
        self.musicArtwork.accessibilityValue = L10n.text("专辑封面加载中")
        self.musicBackdropImageView.image = nil
        self.nowPlayingArtwork = nil
        self.queueIndex = index
        self.savedProgress = nil
        self.resumePromptShown = true
        self.lyricsTask?.cancel()
        self.artworkTask?.cancel()
        self.replaceLyrics(with: [])
        self.loadLyrics()
        self.loadArtwork()
        self.player.time = VLCTime(int: 0)
        self.player.play()
        self.trackSwitchTask = nil
        self.refreshPlaybackState()
        self.showControls()
      } catch {
        guard !Task.isCancelled, !self.closed else { return }
        self.trackSwitchTask = nil
        self.refreshQueueControls(current: Int(self.player.time.intValue))
        self.showError(error.localizedDescription)
      }
    }
  }

  /// 根据队列位置更新界面按钮及锁屏上一首、下一首命令的可用状态。
  private func refreshQueueControls(current: Int) {
    guard isAudioPlayback else { return }
    skipBackButton.isEnabled = queueIndex > 0 || current > 3_000
    skipForwardButton.isEnabled = queue.indices.contains(queueIndex + 1)
    let center = MPRemoteCommandCenter.shared()
    center.previousTrackCommand.isEnabled = skipBackButton.isEnabled
    center.nextTrackCommand.isEnabled = skipForwardButton.isEnabled
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

  /// 用户松开滑块时将比例位置交给解码器并恢复进度同步。
  @objc private func endScrubbing() {
    let duration = max(0, Int(player.media?.length.intValue ?? 0))
    guard player.isSeekable, duration > 0 else {
      isScrubbing = false
      return
    }
    player.time = VLCTime(int: Int32(clamping: Int(Float(duration) * positionSlider.value)))
    isScrubbing = false
    showControls()
  }

  /// 画面轻点只改变控制栏可见性，播放状态只能由对应按钮或系统命令改变。
  @objc private func toggleControls() {
    controlsVisible ? hideControls() : showControls()
  }

  /// 进度条、菜单和播放按钮自行接收点击，避免一次点击同时执行两个动作。
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
    -> Bool
  {
    guard !isAudioPlayback else { return false }
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

  /// 关闭播放器并请求 Shell 移除当前控制器。
  func closeFromShell() {
    closePlayback()
    onClosePlayback(self)
  }

  /// 显示控制栏并在短暂停留后自动淡出。
  private func showControls() {
    guard !pictureInPicture.keepsPlaybackAlive else { return }
    controlsVisible = true
    hideControlsTask?.cancel()
    UIView.animate(withDuration: 0.18) { self.topBar.alpha = 1 }
    UIView.animate(withDuration: 0.18) { self.controls.alpha = 1 }
    UIView.animate(withDuration: 0.18) { self.transport.alpha = 1 }
    scheduleControlsHide()
  }

  /// 在视频播放且没有系统弹窗时隐藏控制栏。
  private func hideControls() {
    guard !pictureInPicture.keepsPlaybackAlive else { return }
    controlsVisible = false
    UIView.animate(withDuration: 0.25) { self.topBar.alpha = 0 }
    UIView.animate(withDuration: 0.25) { self.controls.alpha = 0 }
    UIView.animate(withDuration: 0.25) { self.transport.alpha = 0 }
  }

  /// 为活动播放安排控制栏自动隐藏。
  private func scheduleControlsHide() {
    hideControlsTask?.cancel()
    guard playbackDidAppear, player.isPlaying, !isAudioPlayback, !isScrubbing,
      !pictureInPicture.keepsPlaybackAlive
    else {
      return
    }
    hideControlsTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, let self else { return }
      // 弹窗阻止隐藏后也要释放已结束的任务，让后续播放状态刷新重新计时。
      self.hideControlsTask = nil
      guard self.presentedViewController == nil else { return }
      self.hideControls()
    }
  }

  /// 显示内嵌和同名外挂字幕选项。
  private func showSubtitleMenu() {
    let alert = UIAlertController(
      title: L10n.text("字幕"), message: nil, preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: L10n.text("关闭字幕"), style: .default) { [weak self] _ in
        self?.player.deselectAllTextTracks()
      })
    let tracks = player.textTracks
    for track in tracks {
      let name =
        track.trackName.isEmpty ? (track.trackDescription ?? L10n.text("字幕")) : track.trackName
      alert.addAction(
        UIAlertAction(title: L10n.format("内嵌 · %@", name), style: .default) { _ in
          track.isSelectedExclusively = true
        })
    }
    for subtitle in manifest.subtitles {
      alert.addAction(
        UIAlertAction(
          title: "\(subtitle.language ?? L10n.text("外挂")) · \(subtitle.title)", style: .default
        ) {
          [weak self] _ in
          self?.loadSubtitle(subtitle)
        })
    }
    alert.addAction(UIAlertAction(title: L10n.text("取消"), style: .cancel))
    presentActionSheet(alert, from: subtitleButton)
  }

  /// 通过当前授权下载用户所选外挂字幕并挂载到当前解码会话。
  private func loadSubtitle(_ subtitle: MediaPlaybackSubtitle) {
    subtitleTask?.cancel()
    subtitleTask = Task { [weak self] in
      guard let self else { return }
      do {
        let fileURL = try await self.client.download(subtitle, itemId: self.itemId)
        guard !Task.isCancelled, !self.closed else {
          try? FileManager.default.removeItem(at: fileURL)
          return
        }
        self.subtitleFiles.append(fileURL)
        self.activeSubtitleFile = fileURL
        _ = self.player.addPlaybackSlave(fileURL, type: .subtitle, enforce: true)
        self.showControls()
      } catch {
        guard !Task.isCancelled else { return }
        self.showError(error.localizedDescription)
      }
    }
  }

  /// 显示当前内嵌音轨并允许切换语言或描述。
  private func showAudioMenu() {
    let tracks = player.audioTracks
    let alert = UIAlertController(
      title: L10n.text("音轨"), message: nil, preferredStyle: .actionSheet)
    for track in tracks {
      let name =
        track.trackName.isEmpty ? (track.trackDescription ?? L10n.text("音轨")) : track.trackName
      let action = UIAlertAction(title: name, style: .default) { _ in
        track.isSelectedExclusively = true
      }
      alert.addAction(action)
    }
    alert.addAction(UIAlertAction(title: L10n.text("取消"), style: .cancel))
    presentActionSheet(alert, from: audioButton)
  }

  /// 显示常用播放速度并更新解码器和播放按钮的辅助标签。
  private func showSpeedMenu() {
    let alert = UIAlertController(
      title: L10n.text("播放速度"), message: nil, preferredStyle: .actionSheet)
    for rate: Float in [0.5, 0.75, 1, 1.25, 1.5, 2] {
      let label = rate == 1 ? L10n.text("正常速度") : "\(rate.formatted())x"
      alert.addAction(
        UIAlertAction(title: label, style: .default) { [weak self] _ in
          guard let self else { return }
          self.player.rate = rate
          self.playButton.accessibilityValue = L10n.format("%@ 倍", rate.formatted())
        })
    }
    alert.addAction(UIAlertAction(title: L10n.text("取消"), style: .cancel))
    presentActionSheet(alert, from: topBar)
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

  /// 停止当前播放并关闭播放器控制器。
  private func dismissPlayback() {
    closeFromShell()
  }

  /// 释放解码器、远程命令和本次会话下载的字幕文件。
  private func closePlayback() {
    guard !closed else { return }
    closed = true
    updateTimer?.invalidate()
    updateTimer = nil
    subtitleTask?.cancel()
    lyricsTask?.cancel()
    artworkTask?.cancel()
    trackSwitchTask?.cancel()
    hideControlsTask?.cancel()
    NotificationCenter.default.removeObserver(self)
    pictureInPicture.stop()
    player.stop()
    player.media = nil
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
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    for file in subtitleFiles {
      try? FileManager.default.removeItem(at: file)
    }
    subtitleFiles.removeAll()
    activeSubtitleFile = nil
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
