import Foundation

/// 操作菜单的来源决定系统承载方式，不携带业务 API 或网页回调。
public enum OperationMenuKind: String, Codable, Sendable { case card, standalone }

/// 菜单按原顺序保留动作、嵌套、分组和独立分隔条。
public enum OperationMenuItemKind: String, Codable, Sendable {
  case action, submenu, group, separator
}

/// 仅接收网页契约定义的语义色，系统材质不使用任意网页颜色覆盖。
public enum OperationMenuColor: String, Codable, Sendable {
  case primary, secondary, success, info, warning, error
}

/// 原菜单的启用状态或数量徽标独立保留，不把状态拼入主标题。
public struct OperationMenuBadge: Codable, Equatable, Sendable {
  public let title: String
  public let color: OperationMenuColor?
}

/// 单项只描述原菜单的外观和状态；选择时仍由网页复核并执行原业务方法。
public struct OperationMenuItem: Codable, Equatable, Sendable {
  public let id: String
  public let kind: OperationMenuItemKind
  public let title: String?
  public let subtitle: String?
  public let icon: String?
  public let color: OperationMenuColor?
  public let badge: OperationMenuBadge?
  public let enabled: Bool?
  public let selected: Bool?
  public let loading: Bool?
  public let destructive: Bool?
  public let keepOpen: Bool?
  public let items: [OperationMenuItem]?
}

/// 与前端共享的有界展示票据，独立于导航快照；原生不能从标题或数组位置推断动作。
public struct OperationMenuSnapshot: Codable, Equatable, Sendable {
  public let ownerId: String
  public let menuId: String
  public let presentationId: String
  public let kind: OperationMenuKind
  public let title: String?
  public let items: [OperationMenuItem]

  /// 完整校验后才能交给 UIKit；坏声明整体拒绝，不能只取可解码的前半份菜单。
  public func validate() throws {
    guard BridgeValidator.isIdentifier(ownerId), BridgeValidator.isIdentifier(menuId),
      BridgeValidator.isIdentifier(presentationId)
    else { throw BridgeError.invalidMessage }
    try Self.validateText(title)
    var identifiers = Set<String>()
    var count = 0
    var actions = 0

    /// 三层、96 项与前端投影相同；父层状态在最终动作查询中继续生效。
    func validateItems(_ rows: [OperationMenuItem], depth: Int) throws {
      guard depth < 3 else { throw BridgeError.invalidMessage }
      for row in rows {
        count += 1
        guard count <= 96, BridgeValidator.isIdentifier(row.id),
          identifiers.insert(row.id).inserted
        else { throw BridgeError.invalidMessage }
        if row.kind == .separator {
          guard row.title == nil, row.subtitle == nil, row.icon == nil, row.color == nil,
            row.badge == nil,
            row.enabled == nil, row.selected == nil, row.loading == nil,
            row.destructive == nil, row.keepOpen == nil, row.items == nil
          else { throw BridgeError.invalidMessage }
          continue
        }
        try Self.validateText(row.title, required: row.kind != .group)
        try Self.validateText(row.subtitle)
        try Self.validateText(row.icon, maximumBytes: 256)
        if let badge = row.badge {
          try Self.validateText(badge.title, required: true, maximumBytes: 256)
        }
        if row.kind == .action {
          guard row.items == nil else { throw BridgeError.invalidMessage }
          actions += 1
        } else {
          guard let children = row.items, children.contains(where: { $0.kind != .separator })
          else { throw BridgeError.invalidMessage }
          try validateItems(children, depth: depth + 1)
        }
      }
    }

    try validateItems(items, depth: 0)
    guard actions > 0 else { throw BridgeError.invalidMessage }
    // 前端的 24 KB 限制针对展示内容，单次 presentationId 在投影之后才加入。
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard
      var object = try JSONSerialization.jsonObject(with: encoder.encode(self)) as? [String: Any]
    else { throw BridgeError.invalidMessage }
    object.removeValue(forKey: "presentationId")
    let data = try JSONSerialization.data(
      withJSONObject: object, options: [.withoutEscapingSlashes])
    guard data.count <= 24_000 else { throw BridgeError.invalidMessage }
  }

  /// UIKit 只能选择当前已校验树中的可用动作，不能绕过禁用或加载中的父菜单。
  public func availableAction(id: String) -> OperationMenuItem? {
    /// 每层继承父项状态，不将分组或子菜单本身当成业务动作执行。
    func find(_ rows: [OperationMenuItem], parentEnabled: Bool, depth: Int) -> OperationMenuItem? {
      guard depth < 3 else { return nil }
      for row in rows {
        let enabled = parentEnabled && row.enabled != false && row.loading != true
        if row.id == id { return row.kind == .action && enabled ? row : nil }
        if let children = row.items,
          let action = find(children, parentEnabled: enabled, depth: depth + 1)
        {
          return action
        }
      }
      return nil
    }
    return find(items, parentEnabled: true, depth: 0)
  }

  /// 文案按 UTF-8 限额且拒绝控制/格式字符，与网页完整投影的规则保持一致。
  private static func validateText(
    _ value: String?, required: Bool = false, maximumBytes: Int = 2048
  ) throws {
    guard let value else {
      if required { throw BridgeError.invalidMessage }
      return
    }
    guard value.utf8.count <= maximumBytes,
      !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.unicodeScalars.allSatisfy({
        $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
      })
    else { throw BridgeError.invalidMessage }
  }
}
