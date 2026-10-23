import MoviePilotCore
import UIKit
import UserNotifications

/// 系统通知生命周期与待处理点击；只有当前已登录实例可消费通知。
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationService()
  static let installation: String = {
    let key = "moviepilot.notification.installation"
    if let value = UserDefaults.standard.string(forKey: key) { return value }
    let value = UUID().uuidString
    UserDefaults.standard.set(value, forKey: key)
    return value
  }()
  weak var coordinator: WebCoordinator?
  private(set) var owner: String?
  private(set) var token: String?
  private(set) var registrationError: String?
  private var pending: (NotificationIntent, Date)?

  /// 默认免费签名不声明 APNs；付费签名在构建时显式选择与描述文件一致的环境。
  var environment: String? {
    let value = Bundle.main.object(forInfoDictionaryKey: "MoviePilotAPNsEnvironment") as? String
    if value == "development" { return "sandbox" }
    return value == "production" ? "production" : nil
  }

  /// 切换 WebView 立即撤销旧身份，冷启动通知等新文档完成认证后再判断。
  func attach(_ value: WebCoordinator?) {
    coordinator = value
    owner = nil
  }

  /// 登录状态从现有已认证接口确认，不能信任推送正文声称的当前用户。
  func identified(_ value: String) {
    owner = value
    consumePending()
    if enabled {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  /// 授权只在用户明确点击后申请，拒绝后保留主屏幕通知入口。
  func enable() async -> String {
    guard environment != nil else { return "当前安装使用主屏幕通知。" }
    do {
      guard
        try await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound, .badge,
        ])
      else {
        return "系统通知未开启，可前往设置允许通知。"
      }
      guard let key = preferenceKey else { return "请先登录 MoviePilot。" }
      UserDefaults.standard.set(true, forKey: key)
      registrationError = nil
      UIApplication.shared.registerForRemoteNotifications()
      return "已向系统申请推送令牌，稍后刷新查看绑定状态。"
    } catch { return "无法申请通知权限，请检查系统设置。" }
  }

  /// Apple 令牌可能随重装或恢复改变，每次回调都覆盖当前安装绑定。
  func registered(_ data: Data) {
    token = data.map { String(format: "%02x", $0) }.joined()
    registrationError = nil
    Task { [weak self] in await self?.bindToken() }
  }

  /// 签名缺少能力或系统注册失败时展示可恢复原因，不宣称收到原生推送。
  func failedRegistration() {
    registrationError = "系统未能注册 APNs。请检查签名能力，或使用主屏幕通知。"
  }

  /// 关闭只撤销当前实例账号的安装及配对网页，不影响其他设备。
  func disable() {
    if let key = preferenceKey { UserDefaults.standard.removeObject(forKey: key) }
    UIApplication.shared.unregisterForRemoteNotifications()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    pending = nil
  }

  /// 通知点击可先于 Web 认证；只在内存中短暂等待，过期后不重放。
  func receive(_ intent: NotificationIntent) {
    pending = (intent, Date())
    consumePending()
  }

  /// 前台和弹层关闭后再次检查尚未消费的点击，仍遵守五分钟有效期。
  func resumePending() { consumePending() }

  /// 前台展示也必须匹配当前账号，旧实例的通知不显示在当前会话上。
  private func accepts(_ intent: NotificationIntent) -> Bool {
    guard let coordinator, let owner else { return false }
    return intent.matches(address: coordinator.instance.address, owner: owner)
  }

  /// 已认证且网页接管后只提交一次导航意图；账号不匹配只提示，不自动切换实例。
  private func consumePending() {
    guard let (intent, created) = pending, let coordinator, let owner else { return }
    guard Date().timeIntervalSince(created) < 300 else {
      pending = nil
      return
    }
    guard intent.matches(address: coordinator.instance.address, owner: owner) else {
      pending = nil
      coordinator.shell?.showNotificationMessage("这条通知属于其他实例或账号，请切换后查看通知中心。")
      return
    }
    if coordinator.openNotification(intent) { pending = nil }
  }

  /// 配置偏好绑定完整实例入口与不可变账号身份，账号改名不影响绑定。
  private var preferenceKey: String? {
    guard let coordinator, let owner else { return nil }
    return "moviepilot.notification.enabled.\(coordinator.instance.id).\(owner)"
  }

  /// 只有用户启用过且构建声明 APNs 时才向 Apple 注册。
  private var enabled: Bool {
    guard environment != nil, let key = preferenceKey else { return false }
    return UserDefaults.standard.bool(forKey: key)
  }

  /// 令牌注册复用 Web 的现有认证；失败留在设置页供用户显式重试。
  private func bindToken() async {
    guard enabled, let token, let coordinator, let environment else { return }
    do {
      _ = try await coordinator.notificationRequest(
        "register",
        extra: [
          "token": token, "topic": Bundle.main.bundleIdentifier ?? "", "environment": environment,
        ])
    } catch { registrationError = "通知令牌尚未绑定，请检查后台渠道并重新开启。" }
  }

  /// 在系统回调线程解析不可变载荷，跨执行器只传递经过验证的值。
  nonisolated static func intent(from info: [AnyHashable: Any]) -> NotificationIntent? {
    guard let data = info["moviepilot"] as? [String: String],
      let origin = data["origin"], let route = data["route"], let owner = data["owner"]
    else { return nil }
    return NotificationIntent(origin: origin, route: route, owner: owner)
  }

  /// 前台通知遵守相同身份校验，拒绝内容不交给页面。
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    guard let intent = Self.intent(from: notification.request.content.userInfo) else { return [] }
    return await accepts(intent) ? [.banner, .list, .sound] : []
  }

  /// 系统点击和主屏幕链接共用待处理导航，冷启动不直接加载外部 URL。
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard let intent = Self.intent(from: response.notification.request.content.userInfo) else {
      return
    }
    await receive(intent)
  }
}
