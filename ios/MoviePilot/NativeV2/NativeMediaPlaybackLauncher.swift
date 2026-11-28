import AVFoundation
import Combine
import Foundation
import ImageIO
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import UIKit

/// 最小化悬浮音乐迷你播放条的实时状态快照。
struct NativeMiniMusicState {
  let title: String
  let subtitle: String
  let artwork: UIImage?
  let isPlaying: Bool
  let progress: Double
  let hasNext: Bool
}

/// 原生媒体播放调度器：脱离 WebCoordinator 直接拉起 `MediaPlaybackViewController`（VLCKit/AVKit/PiP），支持媒体服务器流、音乐队列、存储文件、系统打开的本地音视频文件与外部直链播放，以及可最小化悬浮音乐迷你条。
@MainActor
final class NativeMediaPlaybackLauncher: ObservableObject {
  static let shared = NativeMediaPlaybackLauncher()

  /// 冷启动尚未完成窗口挂载时暂存的外部播放请求（本地文件或直链流）。
  private enum PendingExternalPlayback {
    case localFile(
      url: URL,
      title: String,
      kind: PlayableMediaKind,
      lease: SecurityScopedResourceLease,
      deleteAfterClose: Bool
    )
    case externalURL(url: URL, title: String?, kind: PlayableMediaKind)
  }

  /// 本地音频文件提取到的内嵌展示元数据。
  private struct LocalAudioMetadata: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
  }

  @Published private(set) var miniMusicState: NativeMiniMusicState?

  private var activePlayer: MediaPlaybackViewController?
  private var minimizedPlayer: MediaPlaybackViewController?
  var hasActivePlayer: Bool { activePlayer != nil }
  private var pendingExternalPlayback: PendingExternalPlayback?
  private var externalLaunchTask: Task<Void, Never>?

  private init() {}

  /// 判断文件扩展名是否支持使用原生播放器直接播放。
  static func isPlayableMediaExtension(_ rawExt: String?) -> Bool {
    PlayableMediaFormat.isPlayableExtension(rawExt)
  }

  /// 判断是否为音频扩展名。
  static func isAudioExtension(_ rawExt: String?) -> Bool {
    PlayableMediaFormat.isAudioExtension(rawExt)
  }

  /// 判断 URL 是否位于应用沙箱 `Documents/Inbox/` 临时移交目录内（仅此类副本在关闭后清理，绝不删除原位用户文件）。
  static func isInsideDocumentsInbox(_ url: URL) -> Bool {
    guard url.isFileURL,
      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return false }
    let inboxPath = docs.appendingPathComponent("Inbox", isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath().path
    let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path
    let prefix = inboxPath.hasSuffix("/") ? inboxPath : inboxPath + "/"
    return filePath.hasPrefix(prefix)
  }

  /// 将封面原始地址转换为当前实例受信任的图片代理或缓存地址，供原生播放器加载封面与锁屏海报。
  static func proxiedArtworkURL(session: NativeSession, raw: String?) -> URL? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
      let source = URL(string: trimmed),
      let scheme = source.scheme?.lowercased(), ["http", "https"].contains(scheme),
      source.host != nil
    else { return nil }
    let settings = NativeGlobalImageSettingsStore.shared.currentSettings(for: session)
    let rewritten = APIImageSettings.rewriteImageSourceURL(
      source, settings: settings, maximumWidth: 720)
    let isBangumiProxied =
      settings.bangumiProxyEnable && APIImageSettings.isBangumiImageURL(source)
    if settings.globalImageCache && !isBangumiProxied
      && !APIImageSettings.isMediaServerImageURL(rewritten)
    {
      var components = URLComponents(
        url: session.instance.address.url.appending(path: "api/v1/system/cache/image"),
        resolvingAgainstBaseURL: false)
      components?.queryItems = [URLQueryItem(name: "url", value: rewritten.absoluteString)]
      return components?.url
    }
    let useProxy =
      !APIImageSettings.isDoubanImageURL(rewritten)
      && !APIImageSettings.isInternalOrSameHost(
        rewritten, serverHost: session.instance.address.url.host)
    var components = URLComponents(
      url: session.instance.address.url.appending(
        path: useProxy ? "api/v1/system/img/1" : "api/v1/system/img/0"),
      resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "imgurl", value: rewritten.absoluteString),
      URLQueryItem(name: "cache", value: settings.globalImageCache ? "true" : "false"),
    ]
    return components?.url
  }

  /// 播放媒体服务器已入库条目（全媒体服务器统一接口），支持播前指定版本/音轨/字幕以及连续剧分集队列。
  func playMediaServerItem(
    session: NativeSession,
    itemID: String,
    server: String?,
    title: String,
    artworkURL: URL? = nil,
    queue: [MediaPlaybackQueueItem] = [],
    queueIndex: Int = 0,
    trackSelection: MediaPlaybackTrackSelection? = nil
  ) async -> String? {
    do {
      let auth = try session.playbackAuthorization()
      let client = MediaPlaybackClient(
        address: auth.address, accessToken: auth.accessToken, accountID: session.user.id)
      let manifest = try await client.loadManifest(
        itemId: itemID, server: server, mediaSourceId: trackSelection?.mediaSourceID)
      return present(
        manifest: manifest, client: client, instanceID: session.instance.id,
        itemID: itemID, title: title.isEmpty ? manifest.title : title, artworkURL: artworkURL,
        queue: queue, queueIndex: queueIndex, initialTrackSelection: trackSelection)
    } catch MediaPlaybackError.unauthorized {
      session.handleExternalUnauthorized()
      return "登录已过期，请重新登录。"
    } catch {
      return "无法读取媒体服务器播放流，请确认影片仍在媒体库中并检查后台连接。"
    }
  }

  /// 播放音乐单曲，直连 `POST /api/v1/mediaserver/stream-info/music`，可选携带专辑队列支持切歌。
  func playMusicTrack(
    session: NativeSession,
    title: String,
    artist: String?,
    album: String?,
    artworkURL: URL? = nil,
    queue: [MediaPlaybackQueueItem] = [],
    queueIndex: Int = 0
  ) async -> String? {
    do {
      let auth = try session.playbackAuthorization()
      let client = MediaPlaybackClient(
        address: auth.address, accessToken: auth.accessToken, accountID: session.user.id)
      let manifest = try await client.loadMusicManifest(
        title: title, artist: artist, album: album)
      return present(
        manifest: manifest, client: client, instanceID: session.instance.id,
        itemID: manifest.itemId, title: title, artworkURL: artworkURL,
        queue: queue, queueIndex: queueIndex)
    } catch MediaPlaybackError.unauthorized {
      session.handleExternalUnauthorized()
      return "登录已过期，请重新登录。"
    } catch {
      return "当前曲目未在媒体服务器中匹配到可播放音频文件。"
    }
  }

  /// 播放本地或云盘存储中的可播放音视频文件：
  /// 本地存储优先签发短期流票据走 HTTP Range 边加载边播放；云盘或旧版后端自动回退至临时缓存并在关闭时清理。
  func playStorageFile(
    session: NativeSession,
    storage: String,
    path: String,
    fileName: String
  ) async -> String? {
    do {
      let auth = try session.playbackAuthorization()
      let client = MediaPlaybackClient(
        address: auth.address, accessToken: auth.accessToken, accountID: session.user.id)
      let isAudio = Self.isAudioExtension((fileName as NSString).pathExtension)
      let manifest = try await client.loadStorageFileManifest(
        storage: storage, path: path, fileName: fileName, isAudio: isAudio)
      return present(
        manifest: manifest, client: client, instanceID: session.instance.id,
        itemID: manifest.itemId, title: fileName, artworkURL: nil,
        queue: [], queueIndex: 0,
        deleteContentFileOnClose: manifest.contentUrl.isFileURL)
    } catch MediaPlaybackError.unauthorized {
      session.handleExternalUnauthorized()
      return "登录已过期，请重新登录。"
    } catch MediaPlaybackError.streamingUnsupported {
      return "当前存储或后端版本暂不支持在线流式播放，请升级 MoviePilot 后端或检查存储配置。"
    } catch {
      return "无法读取该存储文件的媒体内容，请检查存储挂载状态与权限。"
    }
  }

  /// 接收系统文件菜单 / 共享面板打开的本机音视频文件；若窗口尚未挂载则自动排队至首帧展示。
  func enqueueOrPlayLocalFile(
    url: URL,
    title: String,
    kind: PlayableMediaKind,
    securityScopeLease: SecurityScopedResourceLease,
    deleteAfterClose: Bool
  ) {
    let shouldDelete = deleteAfterClose && Self.isInsideDocumentsInbox(url)
    let request = PendingExternalPlayback.localFile(
      url: url, title: title, kind: kind, lease: securityScopeLease, deleteAfterClose: shouldDelete)
    if Self.topViewController() == nil {
      pendingExternalPlayback = request
      return
    }
    pendingExternalPlayback = nil
    launchExternalPlayback(request)
  }

  /// 接收 `moviepilot://play?url=...` 外部直链流；无需登录 MoviePilot 且不附带任何账号凭据。
  func enqueueOrPlayExternalURL(
    url: URL,
    title: String?,
    kind: PlayableMediaKind
  ) {
    let request = PendingExternalPlayback.externalURL(url: url, title: title, kind: kind)
    if Self.topViewController() == nil {
      pendingExternalPlayback = request
      return
    }
    pendingExternalPlayback = nil
    launchExternalPlayback(request)
  }

  /// 窗口完成挂载并可见后消费冷启动期间排队的本地文件或外部直链播放请求。
  func presentPendingExternalPlaybackIfNeeded() {
    guard let pending = pendingExternalPlayback, Self.topViewController() != nil else { return }
    pendingExternalPlayback = nil
    launchExternalPlayback(pending)
  }

  /// 仅关闭绑定到 MoviePilot 服务会话的播放器；独立本地文件与外部直链播放不受切换服务或会话刷新影响。
  func dismissSessionBoundPlayer(animated: Bool = true) {
    if let player = activePlayer, player.isSessionBound {
      activePlayer = nil
      dismissController(player, animated: animated)
    }
    if let mini = minimizedPlayer, mini.isSessionBound {
      minimizedPlayer = nil
      miniMusicState = nil
      dismissController(mini, animated: animated)
    }
  }

  /// 仅收起全屏呈现中的播放器（保留最小化悬浮音乐条），用于响应外部页面跳转深链。
  func dismissFullScreenPlayerIfNeeded(animated: Bool = false) {
    guard let player = activePlayer else { return }
    activePlayer = nil
    dismissController(player, animated: animated)
  }

  /// 强制关闭当前活跃或最小化的播放器（新起播替换或手动停止时调用）。
  func dismissActivePlayer(animated: Bool = true) {
    miniMusicState = nil
    if let player = activePlayer {
      activePlayer = nil
      dismissController(player, animated: animated)
    }
    if let mini = minimizedPlayer {
      minimizedPlayer = nil
      dismissController(mini, animated: animated)
    }
  }

  /// 点击悬浮音乐迷你播放条，将持续播放中的音乐控制器平滑还原为全屏播放界面。
  func expandMinimizedAudio() {
    guard let mini = minimizedPlayer else { return }
    miniMusicState = nil
    minimizedPlayer = nil
    activePlayer = mini
    mini.restoreFromMinimizedAudio()
    if mini.presentingViewController == nil, let top = Self.topViewController(), top !== mini {
      top.present(mini, animated: true)
    }
  }

  /// 在悬浮音乐迷你播放条上直接切换播放/暂停。
  func toggleMinimizedPlayPause() {
    minimizedPlayer?.togglePlaybackFromShell()
  }

  /// 在悬浮音乐迷你播放条上切到下一首。
  func skipNextMinimizedTrack() {
    minimizedPlayer?.nextTrackFromShell()
  }

  /// 点击悬浮音乐迷你播放条关闭按钮，彻底停止音乐播放。
  func stopMinimizedAudio() {
    dismissActivePlayer(animated: false)
  }

  /// 异步准备并拉起本地音视频文件或外部直链播放器，自动提取本地音频内嵌标题/艺人/专辑/封面。
  private func launchExternalPlayback(_ request: PendingExternalPlayback) {
    externalLaunchTask?.cancel()
    externalLaunchTask = Task { [weak self] in
      guard let self else { return }
      switch request {
      case .localFile(let url, let title, let kind, let lease, let deleteAfterClose):
        guard FileManager.default.isReadableFile(atPath: url.path) else {
          lease.release()
          if deleteAfterClose { try? FileManager.default.removeItem(at: url) }
          NativeSystemRouteHub.shared.postBanner(L10n.text("无法读取该本地音视频文件，请确认文件已下载到本机。"))
          return
        }
        if PlayableMediaFormat.isStrmExtension(url.pathExtension) {
          let strmData = try? Data(contentsOf: url, options: .mappedIfSafe)
          lease.release()
          if deleteAfterClose { try? FileManager.default.removeItem(at: url) }
          guard
            let strmData,
            let spec = PlayableMediaFormat.parseStrmData(
              strmData, fallbackFileName: url.lastPathComponent)
          else {
            NativeSystemRouteHub.shared.postBanner(
              L10n.text("无法解析 STRM 文件中的有效 HTTP/HTTPS 播放直链。"))
            return
          }
          let itemID = "external:\(spec.url.absoluteString)"
          let manifest = MediaPlaybackManifest(
            itemId: itemID,
            server: nil,
            title: title,
            contentUrl: spec.url,
            strmUrl: spec.url,
            customHeaders: spec.headers,
            mediaType: spec.kind.rawValue,
            artist: nil,
            album: nil,
            subtitles: [],
            lyricsUrl: nil
          )
          if let error = present(
            manifest: manifest,
            client: nil,
            instanceID: MediaPlaybackViewController.externalPlaybackNamespace,
            itemID: itemID,
            title: title,
            artworkURL: nil,
            initialArtwork: nil,
            queue: [],
            queueIndex: 0,
            deleteContentFileOnClose: false,
            securityScopeLease: nil
          ) {
            NativeSystemRouteHub.shared.postBanner(error)
          }
          return
        }
        let fileSize =
          (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(String.init) ?? "0"
        let itemID = "local:\(url.lastPathComponent):\(fileSize)"
        let manifest = MediaPlaybackManifest(
          itemId: itemID,
          server: nil,
          title: title,
          contentUrl: url,
          mediaType: kind.rawValue,
          artist: nil,
          album: nil,
          subtitles: [],
          lyricsUrl: nil,
          fileNameHint: url.lastPathComponent
        )
        if let error = present(
          manifest: manifest,
          client: nil,
          instanceID: MediaPlaybackViewController.externalPlaybackNamespace,
          itemID: itemID,
          title: title,
          artworkURL: nil,
          initialArtwork: nil,
          queue: [],
          queueIndex: 0,
          deleteContentFileOnClose: deleteAfterClose,
          securityScopeLease: lease
        ) {
          lease.release()
          if deleteAfterClose { try? FileManager.default.removeItem(at: url) }
          NativeSystemRouteHub.shared.postBanner(error)
        } else if kind == .audio {
          // 立即起播后在后台异步提取内嵌标题/艺人/专辑与封面，避免大文件或网盘挂载文件阻塞首帧起播
          let presentedPlayer = activePlayer
          Task { [weak presentedPlayer] in
            let metadata = await Self.extractLocalAudioMetadata(from: url)
            guard !Task.isCancelled, let presentedPlayer else { return }
            let artwork = metadata.artworkData.flatMap(Self.decodeBoundedArtwork)
            presentedPlayer.applyLocalAudioMetadata(
              expectedItemID: itemID,
              title: metadata.title,
              artist: metadata.artist,
              album: metadata.album,
              artwork: artwork
            )
          }
        }

      case .externalURL(let url, let title, let kind):
        let fallbackName = url.deletingPathExtension().lastPathComponent
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle =
          title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
          ?? (fallbackName.isEmpty || fallbackName == "/" ? nil : fallbackName)
          ?? url.host
          ?? L10n.text("在线媒体")
        let itemID = "external:\(url.absoluteString)"
        let manifest = MediaPlaybackManifest(
          itemId: itemID,
          server: nil,
          title: resolvedTitle,
          contentUrl: url,
          mediaType: kind.rawValue,
          artist: nil,
          album: nil,
          subtitles: [],
          lyricsUrl: nil
        )
        if let error = present(
          manifest: manifest,
          client: nil,
          instanceID: MediaPlaybackViewController.externalPlaybackNamespace,
          itemID: itemID,
          title: resolvedTitle,
          artworkURL: nil,
          initialArtwork: nil,
          queue: [],
          queueIndex: 0,
          deleteContentFileOnClose: false,
          securityScopeLease: nil
        ) {
          NativeSystemRouteHub.shared.postBanner(error)
        }
      }
    }
  }

  /// 在后台读取本地音频内嵌标签与限长封面，读取失败静默降级为文件名与默认占位封面。
  nonisolated private static func extractLocalAudioMetadata(from url: URL) async
    -> LocalAudioMetadata
  {
    let asset = AVURLAsset(url: url)
    guard let items = try? await asset.load(.commonMetadata) else {
      return LocalAudioMetadata(title: nil, artist: nil, album: nil, artworkData: nil)
    }
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
    for item in items {
      guard let commonKey = item.commonKey else { continue }
      switch commonKey {
      case .commonKeyTitle where title == nil:
        title = (try? await item.load(.stringValue))?.trimmingCharacters(
          in: .whitespacesAndNewlines)
      case .commonKeyArtist where artist == nil:
        artist = (try? await item.load(.stringValue))?
          .trimmingCharacters(in: .whitespacesAndNewlines)
      case .commonKeyAlbumName where album == nil:
        album = (try? await item.load(.stringValue))?
          .trimmingCharacters(in: .whitespacesAndNewlines)
      case .commonKeyArtwork where artworkData == nil:
        if let data = try? await item.load(.dataValue), !data.isEmpty, data.count <= 8 * 1024 * 1024
        {
          artworkData = data
        }
      default:
        break
      }
    }
    return LocalAudioMetadata(title: title, artist: artist, album: album, artworkData: artworkData)
  }

  /// 将内嵌封面数据按最大 960px 限尺寸安全解码，防止超大封面图触发内存峰值。
  private static func decodeBoundedArtwork(_ data: Data) -> UIImage? {
    guard !data.isEmpty, data.count <= 8 * 1024 * 1024,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 960,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
  }

  /// 关闭单个播放器实例并清理其呈现状态。
  private func dismissController(_ controller: MediaPlaybackViewController, animated: Bool) {
    let wasPresented = controller.presentingViewController != nil && !controller.isBeingDismissed
    if !animated, wasPresented {
      controller.dismiss(animated: false)
    }
    controller.closeFromShell()
  }

  /// 查找前台活跃窗口顶层控制器并全屏呈现原生播放器。
  private func present(
    manifest: MediaPlaybackManifest,
    client: MediaPlaybackClient?,
    instanceID: UUID,
    itemID: String,
    title: String,
    artworkURL: URL?,
    initialArtwork: UIImage? = nil,
    queue: [MediaPlaybackQueueItem],
    queueIndex: Int,
    initialTrackSelection: MediaPlaybackTrackSelection? = nil,
    deleteContentFileOnClose: Bool = false,
    securityScopeLease: SecurityScopedResourceLease? = nil
  ) -> String? {
    dismissActivePlayer(animated: false)
    guard let presenter = Self.topViewController() else {
      return "当前界面暂不支持拉起播放器。"
    }
    let player = MediaPlaybackViewController(
      manifest: manifest,
      client: client,
      instanceId: instanceID,
      itemId: itemID,
      displayTitle: title,
      artworkURL: artworkURL,
      initialArtwork: initialArtwork,
      queue: queue,
      queueIndex: queueIndex,
      initialTrackSelection: initialTrackSelection,
      deleteContentFileOnClose: deleteContentFileOnClose,
      securityScopeLease: securityScopeLease,
      onMinimize: { [weak self] vc in
        guard let self else { return }
        self.minimizedPlayer = vc
        if self.activePlayer === vc { self.activePlayer = nil }
        if vc.isAudioMiniMode {
          self.miniMusicState = vc.currentMiniMusicState()
        }
        if vc.presentingViewController != nil {
          vc.dismiss(animated: true)
        }
      },
      onExpand: { [weak self] vc in
        guard let self else { return }
        self.miniMusicState = nil
        self.minimizedPlayer = nil
        self.activePlayer = vc
        if vc.presentingViewController == nil, let top = Self.topViewController(), top !== vc {
          top.present(vc, animated: true)
        }
      },
      onClosePlayback: { [weak self] vc in
        if self?.activePlayer === vc { self?.activePlayer = nil }
        if self?.minimizedPlayer === vc {
          self?.minimizedPlayer = nil
          self?.miniMusicState = nil
        }
        if vc.presentingViewController != nil, !vc.isBeingDismissed {
          vc.dismiss(animated: true)
        }
      }
    )
    player.onAudioMiniStateChanged = { [weak self, weak player] state in
      guard let self, let player, self.minimizedPlayer === player else { return }
      self.miniMusicState = state
    }
    player.modalPresentationStyle = .fullScreen
    activePlayer = player
    if presenter.presentedViewController != nil {
      DispatchQueue.main.async { [weak self, weak presenter, weak player] in
        guard let self, let presenter, let player, self.activePlayer === player,
          player.presentingViewController == nil
        else { return }
        presenter.present(player, animated: true)
      }
    } else {
      presenter.present(player, animated: true)
    }
    return nil
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow =
      scenes.flatMap(\.windows).first(where: \.isKeyWindow)
      ?? scenes.flatMap(\.windows).first
    var current = keyWindow?.rootViewController
    while let presented = current?.presentedViewController {
      if presented.isBeingDismissed { break }
      current = presented
    }
    return current
  }
}

extension String {
  /// 空白字符串转为 nil，方便链式回退标题展示。
  fileprivate var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
