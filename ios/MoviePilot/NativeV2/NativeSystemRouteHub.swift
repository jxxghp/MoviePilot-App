import Combine
import Foundation
import MoviePilotCore

/// 原生系统集成路由中枢：统一承接 APNs 通知、桌面小组件与主屏幕快捷项的受限内部导航意图，严格按白名单映射且一次性消费。
@MainActor
final class NativeSystemRouteHub: ObservableObject {
  static let shared = NativeSystemRouteHub()

  /// 经过白名单校验后的原生业务目标，绝不执行任意 URL 或写命令。
  enum RouteTarget: Equatable, Sendable {
    case discover
    case explore
    case dashboard
    case settings
    case search
    case subscriptions
    case calendar
    case resources
    case downloads
    case files
    case history
    case workflows
    case sites
    case messages
    case plugins
    case agent
  }

  /// 当前待由 `NativeV2MainShell` 消费的一次性导航意图。
  @Published private(set) var pendingTarget: RouteTarget?
  /// 跨账号/权限不匹配时的安全提示横幅（不自动切换实例或账号）。
  @Published var bannerMessage: String?

  private var pendingShortcut = PendingHomeShortcut()

  private init() {}

  /// 将后端通知路径严格映射至已知原生目的地，未收录路径一律拒绝。
  static func target(forRoute rawRoute: String) -> RouteTarget? {
    let trimmed = rawRoute.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/"), !trimmed.hasPrefix("//") else { return nil }
    let path = trimmed.split(separator: "?", maxSplits: 1).first.map(String.init) ?? trimmed
    let normalized = path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    switch normalized {
    case "", "discover", "recommend":
      return .discover
    case "explore":
      return .explore
    case "dashboard":
      return .dashboard
    case "setting", "settings":
      return .settings
    case "search":
      return .search
    case "subscribe", "subscribe/movie", "subscribe/tv", "subscribe/music", "subscribe/share":
      return .subscriptions
    case "calendar":
      return .calendar
    case "resource":
      return .resources
    case "downloading", "downloads":
      return .downloads
    case "filemanager", "files":
      return .files
    case "history", "transfer":
      return .history
    case "workflow", "workflows":
      return .workflows
    case "site", "sites":
      return .sites
    case "message", "messages", "notification", "notifications":
      return .messages
    case "plugins", "plugin":
      return .plugins
    case "agent":
      return .agent
    default:
      return nil
    }
  }

  /// 小组件固定内容类型到原生目的地的白名单映射。
  static func target(forWidgetContent content: WidgetContent) -> RouteTarget {
    switch content {
    case .overview: .dashboard
    case .downloads: .downloads
    case .imports: .history
    case .subscriptions, .movieSubscriptions, .tvSubscriptions, .musicSubscriptions: .subscriptions
    }
  }

  /// 主屏幕快捷方式到原生目的地的白名单映射。
  static func target(forShortcut shortcut: HomeShortcut) -> RouteTarget {
    switch shortcut {
    case .search: .search
    case .notifications: .messages
    case .plugins: .plugins
    }
  }

  /// 提交一次经过身份核验的内部路径导航请求；未匹配白名单返回 false。
  @discardableResult
  func open(route: String) -> Bool {
    guard let mapped = Self.target(forRoute: route) else { return false }
    pendingTarget = mapped
    return true
  }

  /// 提交一次经过小组件身份核验的内容跳转。
  func open(widgetContent: WidgetContent) {
    pendingTarget = Self.target(forWidgetContent: widgetContent)
  }

  /// 记录冷/热启动主屏幕快捷方式，绑定当前实例并受 5 分钟有效期约束。
  func receiveShortcut(_ shortcut: HomeShortcut, instanceID: String?) {
    pendingShortcut.receive(shortcut, instanceID: instanceID)
  }

  /// 已认证实例就绪后解析并一次性消费主屏幕快捷方式。
  func resolveShortcut(for instanceID: String) {
    guard let shortcut = pendingShortcut.resolve(for: instanceID) else { return }
    pendingShortcut.clear()
    pendingTarget = Self.target(forShortcut: shortcut)
  }

  /// 切换实例或退出登录时立即清空未消费意图，防止跨实例迟到重放。
  func clearPending() {
    pendingTarget = nil
    pendingShortcut.clear()
  }

  /// 主界面消费后立即清空目标，确保每次系统触发至多导航一次。
  func consumeTarget() -> RouteTarget? {
    let value = pendingTarget
    pendingTarget = nil
    return value
  }

  /// 展示系统集成安全提示（如通知属于其他账号或小组件已失效）。
  func postBanner(_ message: String) {
    bannerMessage = message
  }
}
