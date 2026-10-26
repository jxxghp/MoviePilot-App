import Foundation

/// 主屏幕图标只接受三个固定入口，不把系统快捷项转换成任意路由或业务命令。
public enum HomeShortcut: String, CaseIterable, Sendable {
  case search, notifications, plugins

  /// 与静态 Info.plist 项使用相同的完整类型，拒绝相似前缀或附加参数。
  public init?(type: String) {
    guard let value = Self.allCases.first(where: { $0.type == type }) else { return nil }
    self = value
  }

  /// 快捷项类型不携带实例、账号、令牌或可执行内容。
  public var type: String { "org.moviepilot.app.\(rawValue)" }

  /// 每次打开都重新匹配当前全局登记，不沿用上一文档或已失去权限的动作。
  public func action(in actions: [ActionSnapshot]) -> ActionSnapshot? {
    actions.first { action in
      let parts = action.actionId.split(separator: ":", omittingEmptySubsequences: false)
      return action.isGlobal && parts.count == 3 && parts[1] == "global"
        && parts[2] == rawValue && action.enabled && !action.loading && action.panel != nil
    }
  }
}

/// 在内存中短暂等待连接、登录及导航接管；切实例或过期后禁止迟到重放。
public struct PendingHomeShortcut: Sendable {
  private var shortcut: HomeShortcut?
  private var instanceID: String?
  private var createdAt: Date?

  /// 新窗口没有待处理动作，不从磁盘恢复旧快捷意图。
  public init() {}

  /// 最新一次用户选择替换尚未消费的入口，首次未配置实例时允许稍后绑定。
  public mutating func receive(
    _ value: HomeShortcut, instanceID: String?, now: Date = .now
  ) {
    shortcut = value
    self.instanceID = instanceID
    createdAt = now
  }

  /// 同实例在五分钟内可等待登录和弹层关闭；首次绑定后不能迁移到其他实例。
  public mutating func resolve(for currentInstanceID: String, now: Date = .now) -> HomeShortcut? {
    guard let shortcut, let createdAt else { return nil }
    let age = now.timeIntervalSince(createdAt)
    guard age >= 0, age < 300, instanceID == nil || instanceID == currentInstanceID else {
      clear()
      return nil
    }
    instanceID = currentInstanceID
    return shortcut
  }

  /// 成功打开或用户主动更换连接后清理，不让后续状态快照再次打开面板。
  public mutating func clear() {
    shortcut = nil
    instanceID = nil
    createdAt = nil
  }
}
