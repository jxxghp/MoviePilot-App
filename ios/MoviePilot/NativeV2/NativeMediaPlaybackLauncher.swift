import Combine
import Foundation
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

/// 原生媒体播放调度器：脱离 WebCoordinator 直接拉起 `MediaPlaybackViewController`（VLCKit/AVKit/PiP），支持媒体服务器流、音乐队列、存储本地文件播放与可最小化悬浮音乐迷你条。
@MainActor
final class NativeMediaPlaybackLauncher: ObservableObject {
  static let shared = NativeMediaPlaybackLauncher()

  @Published private(set) var miniMusicState: NativeMiniMusicState?

  private var activePlayer: MediaPlaybackViewController?
  private var minimizedPlayer: MediaPlaybackViewController?

  private init() {}

  /// 判断文件扩展名是否支持使用原生播放器直接播放。
  static func isPlayableMediaExtension(_ rawExt: String?) -> Bool {
    guard let ext = rawExt?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    else { return false }
    return videoExtensions.contains(ext) || audioExtensions.contains(ext)
  }

  /// 判断是否为音频扩展名。
  static func isAudioExtension(_ rawExt: String?) -> Bool {
    guard let ext = rawExt?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    else { return false }
    return audioExtensions.contains(ext)
  }

  /// 将封面原始地址转换为当前实例受信任的图片代理地址，供原生播放器加载封面与锁屏海报。
  static func proxiedArtworkURL(session: NativeSession, raw: String?) -> URL? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
      let source = URL(string: trimmed),
      let scheme = source.scheme?.lowercased(), ["http", "https"].contains(scheme),
      source.host != nil
    else { return nil }
    var components = URLComponents(
      url: session.instance.address.url.appending(path: "api/v1/system/img/0"),
      resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "imgurl", value: trimmed),
      URLQueryItem(name: "cache", value: "true"),
    ]
    return components?.url
  }

  /// 播放媒体服务器已入库条目（Emby / Jellyfin / Plex），直连 `GET /api/v1/mediaserver/stream-info`。
  func playMediaServerItem(
    session: NativeSession,
    itemID: String,
    server: String?,
    title: String,
    artworkURL: URL? = nil,
    queue: [MediaPlaybackQueueItem] = [],
    queueIndex: Int = 0
  ) async -> String? {
    do {
      let auth = try session.playbackAuthorization()
      let client = MediaPlaybackClient(address: auth.address, accessToken: auth.accessToken)
      let manifest = try await client.loadManifest(itemId: itemID, server: server)
      return present(
        manifest: manifest, client: client, instanceID: session.instance.id,
        itemID: itemID, title: title, artworkURL: artworkURL,
        queue: queue, queueIndex: queueIndex)
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
      let client = MediaPlaybackClient(address: auth.address, accessToken: auth.accessToken)
      let manifest = try await client.loadMusicManifest(
        title: title, artist: artist, album: album)
      return present(
        manifest: manifest, client: client, instanceID: session.instance.id,
        itemID: manifest.itemId, title: title, artworkURL: artworkURL,
        queue: queue, queueIndex: queueIndex)
    } catch {
      return "当前曲目未在媒体服务器中匹配到可播放音频文件。"
    }
  }

  /// 播放本地或云盘存储中的可播放音视频文件，经鉴权流下载至临时目录后拉起原生播放器。
  func playStorageFile(
    session: NativeSession,
    storage: String,
    path: String,
    fileName: String
  ) async -> String? {
    do {
      let auth = try session.playbackAuthorization()
      let client = MediaPlaybackClient(address: auth.address, accessToken: auth.accessToken)
      let isAudio = Self.isAudioExtension((fileName as NSString).pathExtension)
      let manifest = try await client.loadStorageFileManifest(
        storage: storage, path: path, fileName: fileName, isAudio: isAudio)
      return present(
        manifest: manifest, client: client, instanceID: session.instance.id,
        itemID: manifest.itemId, title: fileName, artworkURL: nil,
        queue: [], queueIndex: 0)
    } catch {
      return "无法读取该存储文件的媒体内容，请检查存储挂载状态与权限。"
    }
  }

  /// 强制关闭当前活跃或最小化的播放器（实例切换、退出登录或新起播替换时调用）。
  func dismissActivePlayer(animated: Bool = true) {
    miniMusicState = nil
    if let player = activePlayer {
      activePlayer = nil
      let wasPresented = player.presentingViewController != nil && !player.isBeingDismissed
      if !animated, wasPresented {
        player.dismiss(animated: false)
      }
      player.closeFromShell()
    }
    if let mini = minimizedPlayer {
      minimizedPlayer = nil
      let wasPresented = mini.presentingViewController != nil && !mini.isBeingDismissed
      if !animated, wasPresented {
        mini.dismiss(animated: false)
      }
      mini.closeFromShell()
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

  /// 查找前台活跃窗口顶层控制器并全屏呈现原生播放器。
  private func present(
    manifest: MediaPlaybackManifest,
    client: MediaPlaybackClient,
    instanceID: UUID,
    itemID: String,
    title: String,
    artworkURL: URL?,
    queue: [MediaPlaybackQueueItem],
    queueIndex: Int
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
      queue: queue,
      queueIndex: queueIndex,
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
    presenter.present(player, animated: true)
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

  private static let videoExtensions: Set<String> = [
    "mp4", "mkv", "mov", "m4v", "avi", "ts", "m2ts", "webm", "flv", "wmv", "rmvb",
  ]
  private static let audioExtensions: Set<String> = [
    "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus", "alac", "ape",
  ]
}
