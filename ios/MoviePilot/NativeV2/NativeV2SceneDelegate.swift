import MoviePilotCore
import SwiftUI
import UIKit

/// 独立原生窗口只承载 SwiftUI；认证失败或未迁移功能不能启动网页回退。
@MainActor
final class NativeV2SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var model: NativeAppModel?
  private var privacyCover: UIView?

  /// 复用本机地址簿，但从原生会话探测开始，不读取网页启动状态。
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
    NotificationService.shared.attach(nil)
    window.makeKeyAndVisible()
    model.start()
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

  /// 回到前台只撤掉遮盖，不自动重放密码、初始化或其它写入。
  func sceneDidBecomeActive(_ scene: UIScene) {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  /// 后台清空明文输入并取消尚未完成的认证，已登录内存会话仍可继续。
  func sceneDidEnterBackground(_ scene: UIScene) { model?.enteredBackground() }
}
