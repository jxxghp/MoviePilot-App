import Foundation
import Testing

@testable import MoviePilotCore

/// 快捷项只打开当前实例的固定全局面板，冷启动与登录等待不放宽文档和时间边界。
struct HomeShortcutTests {
  /// 完整类型才是入口，附加查询、路径、大小写变化或其他 bundle 的相似项都不能执行。
  @Test func acceptsOnlyThreeExactTypes() {
    #expect(HomeShortcut.allCases.count == 3)
    for shortcut in HomeShortcut.allCases {
      #expect(HomeShortcut(type: shortcut.type) == shortcut)
    }
    for type in [
      "search", "org.moviepilot.app.profile", "org.moviepilot.app.search?route=/setting",
      "org.moviepilot.app.search/", "org.moviepilot.app.Search", "other.app.search",
    ] {
      #expect(HomeShortcut(type: type) == nil)
    }
  }

  /// 当前快照的动作取代旧文档动作，标题翻译与排序不影响固定功能匹配。
  @Test func resolvesCurrentGlobalAction() throws {
    let actions = try [
      action("r8:page:search", scope: "page"),
      action("r8:global:plugins"),
      action("r8:global:search"),
      action("r8:global:notifications"),
    ]
    #expect(HomeShortcut.search.action(in: actions)?.actionId == "r8:global:search")
    #expect(HomeShortcut.notifications.action(in: actions)?.actionId == "r8:global:notifications")
    #expect(HomeShortcut.plugins.action(in: actions)?.actionId == "r8:global:plugins")
    #expect(HomeShortcut.search.action(in: [try action("r9:global:search")])?.ownerId == "r9-owner")
    #expect(HomeShortcut.search.action(in: []) == nil)
  }

  /// 同名页面动作、禁用/加载中或缺失面板的声明均不能由快捷入口绕过。
  @Test func rejectsUnavailableOrNonGlobalActions() throws {
    let actions = try [
      action("r8:global:search", scope: "page"),
      action("r8:global:search", enabled: false),
      action("r8:global:search", loading: true),
      action("r8:global:search", panel: false),
      action("r8:page-global:search"),
      action("r8:global:page:search"),
    ]
    #expect(HomeShortcut.search.action(in: actions) == nil)
  }

  /// 同实例可等待登录与弹层关闭，打开后清空使任何后续快照都不能重复消费。
  @Test func waitsForLoginAndConsumesOnce() {
    var pending = PendingHomeShortcut()
    let now = Date(timeIntervalSince1970: 1000)
    pending.receive(.search, instanceID: "instance-a", now: now)
    #expect(pending.resolve(for: "instance-a", now: now.addingTimeInterval(1)) == .search)
    #expect(pending.resolve(for: "instance-a", now: now.addingTimeInterval(299)) == .search)
    pending.clear()
    #expect(pending.resolve(for: "instance-a", now: now.addingTimeInterval(299)) == nil)
  }

  /// 第一次连接可绑定当次用户选择，绑定后不能在另一实例消费或再回旧实例重放。
  @Test func bindsFirstConnectionAndRejectsInstanceChanges() {
    var pending = PendingHomeShortcut()
    let now = Date(timeIntervalSince1970: 1000)
    pending.receive(.notifications, instanceID: nil, now: now)
    #expect(pending.resolve(for: "instance-a", now: now) == .notifications)
    #expect(pending.resolve(for: "instance-b", now: now) == nil)
    #expect(pending.resolve(for: "instance-a", now: now) == nil)
    pending.receive(.plugins, instanceID: "instance-a", now: now)
    #expect(pending.resolve(for: "instance-b", now: now) == nil)
  }

  /// 五分钟与时间倒退都撤销意图，不能在稍后登录或系统时间恢复后突然打开旧入口。
  @Test(arguments: [-1.0, 300, 301])
  func expiresWithoutReplay(age: TimeInterval) {
    var pending = PendingHomeShortcut()
    let now = Date(timeIntervalSince1970: 1000)
    pending.receive(.search, instanceID: "instance-a", now: now)
    #expect(pending.resolve(for: "instance-a", now: now.addingTimeInterval(age)) == nil)
    #expect(pending.resolve(for: "instance-a", now: now) == nil)
  }

  /// 用户再次明确选择时只保留最近一次，旧入口不排队、不在新页面迟到执行。
  @Test func newestIntentReplacesPrevious() {
    var pending = PendingHomeShortcut()
    let now = Date(timeIntervalSince1970: 1000)
    pending.receive(.search, instanceID: "instance-a", now: now)
    pending.receive(.plugins, instanceID: "instance-a", now: now.addingTimeInterval(290))
    #expect(pending.resolve(for: "instance-a", now: now.addingTimeInterval(301)) == .plugins)
  }

  /// 使用生产 Codable 声明构造候选，测试不依赖不对外开放的成员初始化器。
  private func action(
    _ id: String, scope: String? = nil, enabled: Bool = true, loading: Bool = false,
    panel: Bool = true
  ) throws -> ActionSnapshot {
    var value: [String: Any] = [
      "actionId": id, "ownerId": id.hasPrefix("r9:") ? "r9-owner" : "r8-owner",
      "title": "本地化名称", "icon": "search", "position": "trailing", "enabled": enabled,
      "loading": loading,
    ]
    if let scope { value["scope"] = scope }
    if panel { value["panel"] = ["title": "面板", "sections": []] }
    return try JSONDecoder().decode(
      ActionSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
  }
}
