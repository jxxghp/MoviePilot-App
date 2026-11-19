import UIKit

/// 每次场景连接都选择独立驱动，避免系统恢复旧场景时绕过调试入口选择。
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var driver: (any UIWindowSceneDelegate)?

  /// 原生模式默认关闭，Release 不接受测试参数切换尚未完成的客户端。
  private var usesNativeEntry: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--native-v2")
    #else
      false
    #endif
  }

  /// 驱动各自拥有窗口和生命周期，原生链不初始化旧网页协调器。
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if usesNativeEntry {
      let native = NativeV2SceneDelegate()
      driver = native
      native.scene(scene, willConnectTo: session, options: connectionOptions)
      window = native.window
    } else {
      let legacy = LegacyWebSceneDelegate()
      driver = legacy
      legacy.scene(scene, willConnectTo: session, options: connectionOptions)
      window = legacy.window
    }
  }

  /// 快捷项只交给当前驱动；原生未实现的业务入口明确返回未处理。
  func windowScene(
    _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    guard let legacy = driver as? LegacyWebSceneDelegate else {
      completionHandler(false)
      return
    }
    legacy.windowScene(
      windowScene, performActionFor: shortcutItem, completionHandler: completionHandler)
  }

  /// 深链由当前实现解释，不从原生入口跨回旧网页。
  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    driver?.scene?(scene, openURLContexts: urlContexts)
  }

  /// 前台恢复仅通知已经选定的驱动。
  func sceneDidBecomeActive(_ scene: UIScene) { driver?.sceneDidBecomeActive?(scene) }

  /// 系统中断转发给当前驱动，用于隐藏认证输入。
  func sceneWillResignActive(_ scene: UIScene) { driver?.sceneWillResignActive?(scene) }

  /// 后台取消语义由各驱动负责，不在路由层重新建立会话。
  func sceneDidEnterBackground(_ scene: UIScene) { driver?.sceneDidEnterBackground?(scene) }
}
