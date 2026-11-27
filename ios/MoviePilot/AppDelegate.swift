import UIKit
import UserNotifications

/// 应用入口只负责系统生命周期注册，场景驱动选择独立原生入口或既有实现。
@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
  /// 使用声明式 Scene 配置建立单窗口会话。
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = NotificationService.shared
    LanguageSettings.refreshShortcuts()
    Task.detached(priority: .utility) {
      MpvSubtitleFontResolver.prewarm()
    }
    return true
  }

  /// 系统注册成功后把当前令牌交给通知生命周期管理，不保存到公开配置。
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NotificationService.shared.registered(deviceToken)
  }

  /// 系统 APNs 注册失败时记录可恢复原因，并在推送设置页展示给用户。
  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NotificationService.shared.failedRegistration(error)
  }
}
