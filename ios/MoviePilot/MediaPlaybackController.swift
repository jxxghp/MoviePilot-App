import AVFoundation
import CryptoKit
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
}

/// 网络错误使用固定文案，不回显 URL、令牌、云盘地址或服务器响应正文。
private enum MediaPlaybackError: LocalizedError {
  case unavailable
  case subtitleUnavailable
  case lyricsUnavailable

  /// 返回不包含认证信息和上游来源的操作提示。
  var errorDescription: String? {
    switch self {
    case .unavailable: "无法读取播放信息，请确认影片仍在媒体库中并检查后台连接。"
    case .subtitleUnavailable: "字幕读取失败，请选择其他字幕或检查后台连接。"
    case .lyricsUnavailable: "无法读取本地歌词。"
    }
  }
}

/// 使用原生 UIKit 控件驱动 VLCKit，支持常见容器、内嵌音轨、字幕和远程控制。
@MainActor
final class MediaPlaybackViewController: UIViewController {
  private let manifest: MediaPlaybackManifest
  private let client: MediaPlaybackClient
  private let instanceId: UUID
  private let itemId: String
  private let displayTitle: String
  private let player = VLCMediaPlayer()
  private let videoView = UIView()
  private let musicStage = UIView()
  private let musicArtwork = UIView()
  private let lyricsScroll = UIScrollView()
  private let lyricsStack = UIStackView()
  private let musicArtistLabel = UILabel()
  private let musicAlbumLabel = UILabel()
  private let controls = UIView()
  private let transport = UIStackView()
  private let loading = UIActivityIndicatorView(style: .large)
  private let titleLabel = UILabel()
  private let playButton = UIButton(type: .system)
  private let subtitleButton = UIButton(type: .system)
  private let audioButton = UIButton(type: .system)
  private let speedButton = UIButton(type: .system)
  private let positionSlider = UISlider()
  private var updateTimer: Timer?
  private var hideControlsTask: Task<Void, Never>?
  private var subtitleTask: Task<Void, Never>?
  private var lyricsTask: Task<Void, Never>?
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
  private var closed = false

  /// 清单显式声明音频时展示音乐播放器；兼容旧服务响应仍按视频处理。
  private var isAudioPlayback: Bool { manifest.mediaType == "audio" }

  /// 建立單條目播放器，進度按服務實例和媒體條目隔離在本機保存。
  init(
    manifest: MediaPlaybackManifest,
    client: MediaPlaybackClient,
    instanceId: UUID,
    itemId: String,
    displayTitle: String
  ) {
    self.manifest = manifest
    self.client = client
    self.instanceId = instanceId
    self.itemId = itemId
    self.displayTitle = displayTitle
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
    if isAudioPlayback { loadLyrics() }
    scheduleControlsHide()
  }

  /// 全屏视频允许设备旋转，布局始终保持画面等比显示。
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

  /// 播放结束或控制器关闭时停止计时、声音会话、远程命令和临时字幕。
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || isMovingFromParent || view.window == nil { closePlayback() }
  }

  /// 创建视频画布或音乐舞台、顶部标题和底部播放控制区。
  private func configureViews() {
    videoView.translatesAutoresizingMaskIntoConstraints = false
    videoView.backgroundColor = .black
    videoView.accessibilityLabel = "视频画面"
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

    titleLabel.text = displayTitle
    titleLabel.textColor = .white
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 2
    titleLabel.isHidden = isAudioPlayback
    let closeButton = makeButton(title: nil, symbol: "chevron.down", accessibility: "关闭播放器")
    closeButton.addAction(
      UIAction { [weak self] _ in self?.dismissPlayback() }, for: .touchUpInside)
    let topBar = UIStackView(arrangedSubviews: [closeButton, titleLabel])
    topBar.axis = .horizontal
    topBar.alignment = .center
    topBar.spacing = 12
    topBar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(topBar)
    NSLayoutConstraint.activate([
      topBar.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      topBar.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),
    ])

    configureControls()
    if isAudioPlayback { configureMusicStage(below: topBar) }
  }

  /// 创建不占视频布局空间的中央传输键和底部图标控制层。
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
    positionSlider.accessibilityLabel = "播放进度"
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

    let skipBack = makeButton(title: nil, symbol: "gobackward.15", accessibility: "后退 15 秒")
    skipBack.addAction(UIAction { [weak self] _ in self?.skip(seconds: -15) }, for: .touchUpInside)
    playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
    playButton.accessibilityLabel = "暂停"
    playButton.tintColor = .black
    playButton.backgroundColor = .white
    playButton.layer.cornerRadius = 38
    playButton.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold), forImageIn: .normal)
    playButton.addAction(UIAction { [weak self] _ in self?.togglePlayback() }, for: .touchUpInside)
    let skipForward = makeButton(title: nil, symbol: "goforward.15", accessibility: "前进 15 秒")
    skipForward.addAction(
      UIAction { [weak self] _ in self?.skip(seconds: 15) }, for: .touchUpInside)
    transport.axis = .horizontal
    transport.alignment = .center
    transport.distribution = .equalCentering
    transport.spacing = 38
    transport.addArrangedSubview(skipBack)
    transport.addArrangedSubview(playButton)
    transport.addArrangedSubview(skipForward)
    for button in [skipBack, skipForward] {
      button.tintColor = .white
      button.backgroundColor = UIColor.black.withAlphaComponent(0.42)
      button.layer.cornerRadius = 34
      button.setPreferredSymbolConfiguration(
        UIImage.SymbolConfiguration(pointSize: 24, weight: .medium), forImageIn: .normal)
      button.widthAnchor.constraint(equalToConstant: 68).isActive = true
      button.heightAnchor.constraint(equalToConstant: 68).isActive = true
    }
    playButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
    playButton.heightAnchor.constraint(equalToConstant: 76).isActive = true
    if !isAudioPlayback {
      transport.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(transport)
      NSLayoutConstraint.activate([
        transport.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        transport.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      ])
    }

    subtitleButton.setImage(UIImage(systemName: "captions.bubble"), for: .normal)
    subtitleButton.accessibilityLabel = "选择字幕"
    subtitleButton.addAction(
      UIAction { [weak self] _ in self?.showSubtitleMenu() }, for: .touchUpInside)
    audioButton.setImage(UIImage(systemName: "waveform"), for: .normal)
    audioButton.accessibilityLabel = "选择音轨"
    audioButton.addAction(UIAction { [weak self] _ in self?.showAudioMenu() }, for: .touchUpInside)
    speedButton.setImage(UIImage(systemName: "speedometer"), for: .normal)
    speedButton.accessibilityLabel = "播放速度"
    speedButton.addAction(UIAction { [weak self] _ in self?.showSpeedMenu() }, for: .touchUpInside)
    for button in [subtitleButton, audioButton, speedButton] {
      button.tintColor = .white
      button.backgroundColor = UIColor.black.withAlphaComponent(0.42)
      button.layer.cornerRadius = 22
      button.setPreferredSymbolConfiguration(
        UIImage.SymbolConfiguration(pointSize: 18, weight: .medium), forImageIn: .normal)
      button.widthAnchor.constraint(equalToConstant: 44).isActive = true
      button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    if isAudioPlayback {
      subtitleButton.isHidden = true
      audioButton.isHidden = true
      speedButton.isHidden = true
    }
    let options = UIStackView(arrangedSubviews: [subtitleButton, audioButton, speedButton])
    options.axis = .horizontal
    options.alignment = .center
    options.distribution = .equalCentering
    options.spacing = 16

    let stack = UIStackView(
      arrangedSubviews: isAudioPlayback
        ? [positionSlider, transport, options]
        : [positionSlider, options])
    stack.axis = .vertical
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    controls.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
      stack.topAnchor.constraint(equalTo: controls.topAnchor),
      stack.bottomAnchor.constraint(equalTo: controls.bottomAnchor),
      positionSlider.heightAnchor.constraint(equalToConstant: 26),
    ])

    let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
    videoView.addGestureRecognizer(tap)
  }

  /// 显示本地音频的原生封面占位、曲目信息与可滚动同步歌词。
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
    musicArtwork.accessibilityLabel = "专辑封面"
    musicArtwork.isAccessibilityElement = true
    musicArtwork.backgroundColor = UIColor.secondarySystemBackground
    musicArtwork.layer.cornerRadius = 12
    let note = UIImageView(image: UIImage(systemName: "music.note"))
    note.translatesAutoresizingMaskIntoConstraints = false
    note.tintColor = .systemPink
    note.contentMode = .scaleAspectFit
    musicArtwork.addSubview(note)
    NSLayoutConstraint.activate([
      note.centerXAnchor.constraint(equalTo: musicArtwork.centerXAnchor),
      note.centerYAnchor.constraint(equalTo: musicArtwork.centerYAnchor),
      note.widthAnchor.constraint(equalToConstant: 70),
      note.heightAnchor.constraint(equalToConstant: 82),
    ])

    let title = UILabel()
    title.text = displayTitle
    title.font = .preferredFont(forTextStyle: .title2)
    title.adjustsFontForContentSizeCategory = true
    title.textColor = .label
    title.textAlignment = .center
    title.numberOfLines = 2
    title.accessibilityIdentifier = "music-playback-title"
    musicArtistLabel.text = manifest.artist ?? "未知艺人"
    musicArtistLabel.font = .preferredFont(forTextStyle: .subheadline)
    musicArtistLabel.textColor = .secondaryLabel
    musicArtistLabel.textAlignment = .center
    musicAlbumLabel.text = manifest.album
    musicAlbumLabel.font = .preferredFont(forTextStyle: .caption1)
    musicAlbumLabel.textColor = .tertiaryLabel
    musicAlbumLabel.textAlignment = .center
    let metadata = UIStackView(arrangedSubviews: [title, musicArtistLabel, musicAlbumLabel])
    metadata.axis = .vertical
    metadata.alignment = .fill
    metadata.spacing = 4

    lyricsScroll.translatesAutoresizingMaskIntoConstraints = false
    lyricsScroll.showsVerticalScrollIndicator = false
    lyricsScroll.accessibilityIdentifier = "music-playback-lyrics"
    lyricsStack.axis = .vertical
    lyricsStack.alignment = .fill
    lyricsStack.spacing = 14
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
    appendLyricPlaceholder("正在读取歌词…")

    let artworkRow = UIView()
    artworkRow.translatesAutoresizingMaskIntoConstraints = false
    artworkRow.addSubview(musicArtwork)

    let content = UIStackView(arrangedSubviews: [artworkRow, metadata, lyricsScroll])
    content.axis = .vertical
    content.alignment = .fill
    content.spacing = 14
    content.translatesAutoresizingMaskIntoConstraints = false
    musicStage.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: musicStage.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: musicStage.trailingAnchor),
      content.centerYAnchor.constraint(equalTo: musicStage.centerYAnchor),
      content.topAnchor.constraint(greaterThanOrEqualTo: musicStage.topAnchor),
      content.bottomAnchor.constraint(lessThanOrEqualTo: musicStage.bottomAnchor),
      artworkRow.heightAnchor.constraint(equalTo: musicArtwork.heightAnchor),
      musicArtwork.centerXAnchor.constraint(equalTo: artworkRow.centerXAnchor),
      musicArtwork.centerYAnchor.constraint(equalTo: artworkRow.centerYAnchor),
      musicArtwork.widthAnchor.constraint(equalTo: musicStage.widthAnchor, multiplier: 0.58),
      musicArtwork.heightAnchor.constraint(equalTo: musicArtwork.widthAnchor),
      musicArtwork.heightAnchor.constraint(lessThanOrEqualToConstant: 220),
      lyricsScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 128),
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
      appendLyricPlaceholder("暂无同名 LRC 歌词")
      return
    }
    for (index, cue) in cues.enumerated() {
      let button = UIButton(type: .system)
      button.setTitle(cue.text, for: .normal)
      button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
      button.titleLabel?.adjustsFontForContentSizeCategory = true
      button.titleLabel?.numberOfLines = 0
      button.titleLabel?.textAlignment = .center
      button.tintColor = .white
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
      button.alpha = active ? 1 : 0.48
      button.accessibilityValue = active ? "当前播放" : nil
      button.titleLabel?.font = .preferredFont(forTextStyle: active ? .headline : .subheadline)
      button.titleLabel?.font = UIFont.systemFont(
        ofSize: UIFont.preferredFont(forTextStyle: active ? .headline : .subheadline).pointSize,
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
      showError("无法启动系统音频会话，请检查设备声音设置。")
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
          showError("无法恢复系统音频会话，请手动继续播放。")
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
    center.skipForwardCommand.preferredIntervals = [15]
    center.skipForwardCommand.addTarget(self, action: #selector(remoteForward))
    center.skipBackwardCommand.preferredIntervals = [15]
    center.skipBackwardCommand.addTarget(self, action: #selector(remoteBackward))
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.changePlaybackPositionCommand.isEnabled = true
    center.skipForwardCommand.isEnabled = true
    center.skipBackwardCommand.isEnabled = true
    refreshNowPlayingInfo()
  }

  /// 创建采用 SF Symbols 的原生控制按钮。
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
    playButton.setImage(
      UIImage(systemName: player.isPlaying ? "pause.fill" : "play.fill"), for: .normal)
    playButton.accessibilityLabel = player.isPlaying ? "暂停" : "播放"
    if player.isPlaying { loading.stopAnimating() }
    let subtitleTracks = player.textTracks
    let audioTracks = player.audioTracks
    subtitleButton.isHidden = manifest.subtitles.isEmpty && subtitleTracks.isEmpty
    audioButton.isHidden = audioTracks.count <= 1
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
      title: isAudioPlayback ? "继续收听？" : "继续观看？",
      message: "上次播放到 \(Self.format(milliseconds: saved))。", preferredStyle: .alert)
    alert.addAction(
      UIAlertAction(title: isAudioPlayback ? "继续收听" : "继续播放", style: .default) { [weak self] _ in
        guard let self else { return }
        self.player.time = VLCTime(int: Int32(clamping: saved))
        self.savedProgress = nil
        self.resumeDecisionPending = false
        self.player.play()
      })
    alert.addAction(
      UIAlertAction(title: "从头开始", style: .cancel) { [weak self] _ in
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

  /// 在视频画面上轻点时显示或隐藏控制栏。
  @objc private func toggleControls() {
    controlsVisible ? hideControls() : showControls()
  }

  /// 显示控制栏并在短暂停留后自动淡出。
  private func showControls() {
    controlsVisible = true
    hideControlsTask?.cancel()
    UIView.animate(withDuration: 0.18) { self.controls.alpha = 1 }
    UIView.animate(withDuration: 0.18) { self.transport.alpha = 1 }
    scheduleControlsHide()
  }

  /// 在视频播放且没有系统弹窗时隐藏控制栏。
  private func hideControls() {
    controlsVisible = false
    UIView.animate(withDuration: 0.25) { self.controls.alpha = 0 }
    UIView.animate(withDuration: 0.25) { self.transport.alpha = 0 }
  }

  /// 为活动播放安排控制栏自动隐藏。
  private func scheduleControlsHide() {
    hideControlsTask?.cancel()
    guard player.isPlaying, !isAudioPlayback, !isScrubbing else { return }
    hideControlsTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      guard !Task.isCancelled, let self, self.presentedViewController == nil else { return }
      self.hideControls()
    }
  }

  /// 显示内嵌和同名外挂字幕选项。
  private func showSubtitleMenu() {
    let alert = UIAlertController(title: "字幕", message: nil, preferredStyle: .actionSheet)
    alert.addAction(
      UIAlertAction(title: "关闭字幕", style: .default) { [weak self] _ in
        self?.player.deselectAllTextTracks()
      })
    let tracks = player.textTracks
    for track in tracks {
      let name = track.trackName.isEmpty ? (track.trackDescription ?? "字幕") : track.trackName
      alert.addAction(
        UIAlertAction(title: "内嵌 · \(name)", style: .default) { _ in
          track.isSelectedExclusively = true
        })
    }
    for subtitle in manifest.subtitles {
      alert.addAction(
        UIAlertAction(title: "\(subtitle.language ?? "外挂") · \(subtitle.title)", style: .default) {
          [weak self] _ in
          self?.loadSubtitle(subtitle)
        })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
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
    let alert = UIAlertController(title: "音轨", message: nil, preferredStyle: .actionSheet)
    for track in tracks {
      let name = track.trackName.isEmpty ? (track.trackDescription ?? "音轨") : track.trackName
      let action = UIAlertAction(title: name, style: .default) { _ in
        track.isSelectedExclusively = true
      }
      alert.addAction(action)
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    presentActionSheet(alert, from: audioButton)
  }

  /// 显示常用播放速度并更新解码器和无文字图标的辅助标签。
  private func showSpeedMenu() {
    let alert = UIAlertController(title: "播放速度", message: nil, preferredStyle: .actionSheet)
    for rate: Float in [0.5, 0.75, 1, 1.25, 1.5, 2] {
      let label = rate == 1 ? "正常速度" : "\(rate.formatted())x"
      alert.addAction(
        UIAlertAction(title: label, style: .default) { [weak self] _ in
          guard let self else { return }
          self.player.rate = rate
          self.speedButton.accessibilityValue = "\(rate.formatted()) 倍"
        })
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    presentActionSheet(alert, from: speedButton)
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
    let alert = UIAlertController(title: "播放暂不可用", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  /// 停止当前播放并关闭播放器控制器。
  private func dismissPlayback() {
    closePlayback()
    dismiss(animated: true)
  }

  /// 释放解码器、远程命令和本次会话下载的字幕文件。
  private func closePlayback() {
    guard !closed else { return }
    closed = true
    updateTimer?.invalidate()
    updateTimer = nil
    subtitleTask?.cancel()
    lyricsTask?.cancel()
    hideControlsTask?.cancel()
    NotificationCenter.default.removeObserver(self)
    player.stop()
    player.media = nil
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.removeTarget(self)
    center.pauseCommand.removeTarget(self)
    center.togglePlayPauseCommand.removeTarget(self)
    center.changePlaybackPositionCommand.removeTarget(self)
    center.skipForwardCommand.removeTarget(self)
    center.skipBackwardCommand.removeTarget(self)
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

  /// 耳机前进命令跳过 15 秒。
  @objc private func remoteForward() -> MPRemoteCommandHandlerStatus {
    skip(seconds: 15)
    return .success
  }

  /// 耳机后退命令回退 15 秒。
  @objc private func remoteBackward() -> MPRemoteCommandHandlerStatus {
    skip(seconds: -15)
    return .success
  }
}

/// 后端统一 envelope 只在成功响应中提供清单。
private struct MediaPlaybackEnvelope<Value: Decodable>: Decodable {
  let success: Bool
  let data: Value?
}
