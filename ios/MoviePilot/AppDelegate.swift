import UIKit
import UserNotifications

/// 应用入口只负责系统生命周期注册，业务内容始终留在网页。
@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
  /// 使用声明式 Scene 配置建立单窗口会话。
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = NotificationService.shared
    return true
  }

  /// 系统注册成功后把当前令牌交给通知生命周期管理，不保存到公开配置。
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NotificationService.shared.registered(deviceToken)
  }

  /// 免费签名缺少能力等注册错误转为可操作提示，主屏幕通知仍可使用。
  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationService.shared.failedRegistration()
  }
}
