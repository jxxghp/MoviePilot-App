import MoviePilotCore
import SwiftUI
import UIKit

/// 独立原生窗口只承载 SwiftUI；认证失败或未迁移功能不能启动网页回退，系统深链/小组件/快捷项全部经由原生路由中枢处理。
@MainActor
final class NativeV2SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var model: NativeAppModel?
  private var privacyCover: UIView?

  /// 复用本机地址簿，从原生会话探测开始，并承接冷启动 URL 深链与主屏幕快捷项。
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    let model = NativeAppModel()
    let window = UIWindow(windowScene: scene)
    self.model = model
    self.window = window
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = UIHostingController(rootView: NativeV2RootView(model: model))
    NotificationService.shared.attachNative(nil)
    window.makeKeyAndVisible()

    if let item = connectionOptions.shortcutItem {
      _ = receiveHomeShortcut(item)
    }
    var handledWidgetLaunch = false
    for context in connectionOptions.urlContexts {
      if handleIncomingURL(context.url) {
        handledWidgetLaunch = true
        break
      }
    }
    if !handledWidgetLaunch {
      model.start()
    }
  }

  /// 热启动接收通知自定义深链或桌面小组件深链。
  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    for context in urlContexts {
      if handleIncomingURL(context.url) { break }
    }
  }

  /// 主屏幕长按快捷方式直接写入原生路由中枢并尝试消费。
  func windowScene(
    _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(receiveHomeShortcut(shortcutItem))
  }

  /// 系统快照前用不透明材质遮盖认证草稿和账号资料。
  func sceneWillResignActive(_ scene: UIScene) {
    guard let window, privacyCover == nil else { return }
    window.endEditing(true)
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = UIColor(CinematicStyle.background)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  /// 回到前台撤掉遮盖并复查待消费的通知/小组件/快捷项意图。
  func sceneDidBecomeActive(_ scene: UIScene) {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
    model?.resumeSystemIntegrations()
  }

  /// 后台清空明文输入并取消尚未完成的认证，已登录内存会话仍可继续。
  func sceneDidEnterBackground(_ scene: UIScene) { model?.enteredBackground() }

  /// 解析白名单深链：仅接受 `moviepilot-app://notification` 与 `moviepilot://widget`。
  @discardableResult
  private func handleIncomingURL(_ url: URL) -> Bool {
    if let intent = NotificationIntent(url: url) {
      NotificationService.shared.receive(intent)
      return false
    }
    if let widgetLink = WidgetLink(url: url) {
      model?.openWidgetLink(widgetLink)
      return true
    }
    return false
  }

  /// 校验并登记主屏幕快捷项，若当前已有已认证原生会话则立即路由。
  private func receiveHomeShortcut(_ item: UIApplicationShortcutItem) -> Bool {
    guard let shortcut = HomeShortcut(type: item.type) else { return false }
    NativeSystemRouteHub.shared.receiveShortcut(
      shortcut, instanceID: model?.selected?.id.uuidString)
    model?.resumeSystemIntegrations()
    return true
  }
}
