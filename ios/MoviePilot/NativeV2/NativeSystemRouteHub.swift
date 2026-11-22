import Combine
import Foundation
import MoviePilotCore

/// 原生系统集成路由中枢：统一承接 APNs 通知、桌面小组件、主屏幕快捷项与 `moviepilot://` 外部深度链接的受限导航意图，严格按白名单映射且一次性消费。
@MainActor
final class NativeSystemRouteHub: ObservableObject {
  static let shared = NativeSystemRouteHub()

  /// 当前待由 `NativeV2MainShell` 消费的一次性导航意图。
  @Published private(set) var pendingTarget: AppDeepLink?
  /// 跨账号、权限不匹配或无效链接/文件时的安全提示横幅（不自动切换实例或账号）。
  @Published var bannerMessage: String?

  private var pendingShortcut = PendingHomeShortcut()
  private var pendingDeepLink = PendingAppDeepLink()

  private init() {}

  /// 将后端通知路径严格映射至已知原生目的地，未收录路径及播放动作一律拒绝。
  static func target(forRoute rawRoute: String) -> AppDeepLink? {
    AppDeepLink(route: rawRoute)
  }

  /// 小组件固定内容类型到原生目的地的白名单映射。
  static func target(forWidgetContent content: WidgetContent) -> AppDeepLink {
    switch content {
    case .overview: .dashboard
    case .downloads: .downloads
    case .imports: .history(search: nil)
    case .subscriptions: .subscriptions(category: nil)
    case .movieSubscriptions: .subscriptions(category: "movie")
    case .tvSubscriptions: .subscriptions(category: "tv")
    case .musicSubscriptions: .subscriptions(category: "music")
    }
  }

  /// 主屏幕快捷方式到原生目的地的白名单映射。
  static func target(forShortcut shortcut: HomeShortcut) -> AppDeepLink {
    switch shortcut {
    case .search: .search(query: nil, kind: nil)
    case .notifications: .messages
    case .plugins: .plugins(installedOnly: false)
    }
  }

  /// 提交一次经过身份核验的内部路径导航请求；未匹配白名单返回 false。
  @discardableResult
  func open(route: String) -> Bool {
    guard let mapped = Self.target(forRoute: route) else { return false }
    pendingShortcut.clear()
    pendingDeepLink.clear()
    pendingTarget = mapped
    return true
  }

  /// 提交一次经过小组件身份核验的内容跳转。
  func open(widgetContent: WidgetContent) {
    pendingShortcut.clear()
    pendingDeepLink.clear()
    pendingTarget = Self.target(forWidgetContent: widgetContent)
  }

  /// 记录冷/热启动主屏幕快捷方式，绑定当前实例并受 5 分钟有效期约束。
  func receiveShortcut(_ shortcut: HomeShortcut, instanceID: String?) {
    pendingDeepLink.clear()
    pendingShortcut.receive(shortcut, instanceID: instanceID)
  }

  /// 记录外部 `moviepilot://` 功能联动链接，在冷启动或登录完成后一次性跳转至目标页面。
  func receiveDeepLink(_ link: AppDeepLink, instanceID: String?) {
    pendingShortcut.clear()
    pendingDeepLink.receive(link, instanceID: instanceID)
  }

  /// 已认证实例就绪后解析并一次性消费待处理的深度链接或主屏幕快捷方式。
  func resolvePending(for instanceID: String) {
    if let deepLink = pendingDeepLink.resolve(for: instanceID) {
      pendingDeepLink.clear()
      pendingTarget = deepLink
      return
    }
    if let shortcut = pendingShortcut.resolve(for: instanceID) {
      pendingShortcut.clear()
      pendingTarget = Self.target(forShortcut: shortcut)
    }
  }

  /// 切换实例或退出登录时立即清空未消费意图，防止跨实例迟到重放。
  func clearPending() {
    pendingTarget = nil
    pendingShortcut.clear()
    pendingDeepLink.clear()
  }

  /// 主界面消费后立即清空目标，确保每次系统触发至多导航一次。
  func consumeTarget() -> AppDeepLink? {
    let value = pendingTarget
    pendingTarget = nil
    return value
  }

  /// 展示系统集成安全提示（如通知属于其他账号、小组件已失效或文件/链接不受支持）。
  func postBanner(_ message: String) {
    bannerMessage = message
  }
}
