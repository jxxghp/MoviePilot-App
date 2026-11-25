import Combine
import MoviePilotCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// 独立原生窗口只承载 SwiftUI；系统深链、`moviepilot://` 联动路径、系统音视频文件打开、小组件与快捷项全部经由原生路由中枢与原生播放器处理。
@MainActor
final class NativeV2SceneDelegate: UIResponder, UIWindowSceneDelegate {
  private enum IncomingURLOutcome {
    case ignored
    case handled
    case widgetLaunch
  }

  var window: UIWindow?
  private var model: NativeAppModel?
  private var appearanceCancellable: AnyCancellable?

  /// 复用本机地址簿，从原生会话探测开始，并承接冷启动 URL 深链、音视频文件打开与主屏幕快捷项。
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    let model = NativeAppModel()
    let window = UIWindow(windowScene: scene)
    let hosting = UIHostingController(rootView: NativeV2RootView(model: model))
    self.model = model
    self.window = window
    Self.applyWindowAppearance(
      mode: NativeAppearanceStore.shared.mode, to: window, hostingView: hosting.view)
    appearanceCancellable = NativeAppearanceStore.shared.$mode
      .receive(on: RunLoop.main)
      .sink { [weak window] mode in
        guard let window else { return }
        Self.applyWindowAppearance(
          mode: mode, to: window, hostingView: window.rootViewController?.view)
      }
    if let response = connectionOptions.notificationResponse,
      response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let intent = NotificationService.intent(from: response.notification.request.content.userInfo)
    {
      NotificationService.shared.receive(
        intent, notificationID: response.notification.request.identifier)
    }
    if let item = connectionOptions.shortcutItem {
      _ = receiveHomeShortcut(item)
    }
    var handledWidgetLaunch = false
    for context in connectionOptions.urlContexts {
      let outcome = handleIncomingContext(context)
      if outcome == .widgetLaunch {
        handledWidgetLaunch = true
        break
      }
      if outcome == .handled {
        break
      }
    }
    if !handledWidgetLaunch {
      model.start()
    }
    window.rootViewController = hosting
    window.makeKeyAndVisible()
    DispatchQueue.main.async {
      NativeMediaPlaybackLauncher.shared.presentPendingExternalPlaybackIfNeeded()
    }
  }

  /// 热启动接收通知深链、桌面小组件深链、`moviepilot://` 联动链接或系统移交的本地音视频文件。
  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    for context in urlContexts {
      if handleIncomingContext(context) != .ignored { break }
    }
  }

  /// 主屏幕长按快捷方式直接写入原生路由中枢并尝试消费。
  func windowScene(
    _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(receiveHomeShortcut(shortcutItem))
  }

  /// 退至后台前仅收起键盘，不再用纯色遮罩盖住全屏，确保 iOS 多任务切换器保留真实界面内容缩略图。
  func sceneWillResignActive(_ scene: UIScene) {
    window?.endEditing(true)
  }

  /// 回到前台复查待消费的通知/小组件/快捷项/深度链接意图与排队的外部播放请求。
  func sceneDidBecomeActive(_ scene: UIScene) {
    model?.resumeSystemIntegrations()
    NativeMediaPlaybackLauncher.shared.presentPendingExternalPlaybackIfNeeded()
  }

  /// 后台清空明文输入并取消尚未完成的认证，已登录内存会话仍可继续。
  func sceneDidEnterBackground(_ scene: UIScene) { model?.enteredBackground() }

  /// 统一分流通知深链、小组件深链、系统音视频文件（`file://`）以及 `moviepilot://` 功能联动链接。
  @discardableResult
  private func handleIncomingContext(_ context: UIOpenURLContext) -> IncomingURLOutcome {
    let url = context.url
    if let intent = NotificationIntent(url: url) {
      NotificationService.shared.receive(intent)
      return .handled
    }
    if let widgetLink = WidgetLink(url: url) {
      model?.openWidgetLink(widgetLink)
      return .widgetLaunch
    }
    if url.isFileURL {
      return handleIncomingLocalFile(url, openInPlace: context.options.openInPlace)
    }
    if let deepLink = AppDeepLink(url: url) {
      switch deepLink {
      case .playExternalURL(let streamURL, let title, let kind):
        NativeMediaPlaybackLauncher.shared.enqueueOrPlayExternalURL(
          url: streamURL, title: title, kind: kind)
      case .playLocalFile:
        break
      default:
        NativeSystemRouteHub.shared.receiveDeepLink(
          deepLink, instanceID: model?.selected?.id.uuidString)
        model?.resumeSystemIntegrations()
        if model?.manager.currentSession == nil, model?.selected == nil {
          NativeSystemRouteHub.shared.postBanner(
            L10n.text("请先连接并登录 MoviePilot 服务，登录后将自动前往目标页面。"))
        }
      }
      return .handled
    }
    if url.scheme?.lowercased() == "moviepilot",
      url.host?.lowercased() != "passkey"
    {
      NativeSystemRouteHub.shared.postBanner(L10n.text("无法识别该 MoviePilot 链接路径，请检查链接格式。"))
      return .handled
    }
    return .ignored
  }

  /// 接收系统文件菜单或共享面板移交的本地音视频文件，立即申请安全作用域并拉起原生播放器。
  private func handleIncomingLocalFile(_ url: URL, openInPlace: Bool) -> IncomingURLOutcome {
    let lease = SecurityScopedResourceLease(url: url)
    let isInboxCopy = !openInPlace && NativeMediaPlaybackLauncher.isInsideDocumentsInbox(url)
    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    guard !isDirectory else {
      lease.release()
      if isInboxCopy { try? FileManager.default.removeItem(at: url) }
      NativeSystemRouteHub.shared.postBanner(L10n.text("暂不支持打开文件夹，请选择具体的音视频文件。"))
      return .handled
    }
    let fallbackKind = Self.resolveLocalMediaKind(for: url)
    guard
      case .playLocalFile(let fileURL, let title, let kind) = AppDeepLink(
        url: url, fallbackLocalMediaKind: fallbackKind)
    else {
      lease.release()
      if isInboxCopy { try? FileManager.default.removeItem(at: url) }
      NativeSystemRouteHub.shared.postBanner(L10n.text("暂不支持打开此文件格式，仅支持音视频文件播放。"))
      return .handled
    }
    NativeMediaPlaybackLauncher.shared.enqueueOrPlayLocalFile(
      url: fileURL,
      title: title,
      kind: kind,
      securityScopeLease: lease,
      deleteAfterClose: isInboxCopy
    )
    return .handled
  }

  /// 通过系统 `UTType` 辅助判断缺少扩展名或自定义扩展名的本地文件是否属于音频或视频。
  private static func resolveLocalMediaKind(for url: URL) -> PlayableMediaKind? {
    if let byExt = PlayableMediaFormat.kind(
      forExtension: url.pathExtension, includeStreaming: false)
    {
      return byExt
    }
    guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
      return nil
    }
    if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
      return .video
    }
    if contentType.conforms(to: .audio) {
      return .audio
    }
    if contentType.conforms(to: .audiovisualContent) {
      return .video
    }
    return nil
  }

  /// 校验并登记主屏幕快捷项，若当前已有已认证原生会话则立即路由。
  private func receiveHomeShortcut(_ item: UIApplicationShortcutItem) -> Bool {
    guard let shortcut = HomeShortcut(type: item.type) else { return false }
    NativeSystemRouteHub.shared.receiveShortcut(
      shortcut, instanceID: model?.selected?.id.uuidString)
    model?.resumeSystemIntegrations()
    return true
  }

  /// 按当前外观模式同步窗口与宿主根视图背景色，确保深色模式下冷启动零非黑闪帧。
  private static func applyWindowAppearance(
    mode: NativeAppearanceMode, to window: UIWindow, hostingView: UIView?
  ) {
    window.overrideUserInterfaceStyle = mode.uiInterfaceStyle
    let isDark =
      mode == .dark
      || (mode == .system && window.traitCollection.userInterfaceStyle == .dark)
    let background: UIColor =
      isDark
      ? .black
      : (UIColor(named: "LaunchBackground")
        ?? UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1))
    window.backgroundColor = background
    hostingView?.backgroundColor = background
  }
}
