import UIKit

/// 应用入口只负责系统生命周期注册，业务内容始终留在网页。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  /// 使用声明式 Scene 配置建立单窗口会话。
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    true
  }
}
