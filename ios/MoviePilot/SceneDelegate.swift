import UIKit

/// 应用默认场景代理：统一承载原生 SwiftUI v2 客户端，主流程不再初始化旧网页协调器。
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var driver: NativeV2SceneDelegate?

  /// 默认冷启动直接进入原生 v2 驱动并接管窗口、深链与快捷项生命周期。
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    let native = NativeV2SceneDelegate()
    driver = native
    native.scene(scene, willConnectTo: session, options: connectionOptions)
    window = native.window
  }

  /// 主屏幕快捷方式直接转发给原生驱动。
  func windowScene(
    _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    guard let driver else {
      completionHandler(false)
      return
    }
    driver.windowScene(
      windowScene, performActionFor: shortcutItem, completionHandler: completionHandler)
  }

  /// 自定义深链统一由原生路由中枢校验和消费。
  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    driver?.scene(scene, openURLContexts: urlContexts)
  }

  /// 前台恢复通知原生驱动撤除隐私遮罩并恢复待处理系统意图。
  func sceneDidBecomeActive(_ scene: UIScene) { driver?.sceneDidBecomeActive(scene) }

  /// 系统中断前隐藏敏感输入。
  func sceneWillResignActive(_ scene: UIScene) { driver?.sceneWillResignActive(scene) }

  /// 后台清理明文认证草稿并取消未完成的认证请求。
  func sceneDidEnterBackground(_ scene: UIScene) { driver?.sceneDidEnterBackground(scene) }
}
