import Foundation
import MoviePilotCore

/// 沿用现有用户的四类业务权限与管理员入口；管理员授权只取决于服务端身份。
public enum NativePermission: String, CaseIterable, Sendable {
  case discovery, search, subscribe, manage, admin
}

/// 页面或动作声明的权限要求；功能键继续兼容现有 features 和插件导航约定。
public struct PermissionRequirement: Equatable, Sendable {
  public let category: NativePermission?
  public let feature: String?

  /// 可只声明功能项；分类与功能同时存在时必须同时满足。
  public init(category: NativePermission? = nil, feature: String? = nil) {
    self.category = category
    self.feature = feature
  }

  /// 物理插件实例和导航项保持独立，不能把克隆实例权限映射成源插件权限。
  public static func plugin(
    id: String, navigationKey: String = "main", category: NativePermission? = nil
  ) -> Self {
    Self(category: category, feature: "plugin.\(id).\(navigationKey)")
  }
}

/// 服务器用户权限的值投影；缺省行为与现有前端一致，不使用 permissions.admin 提权。
public struct NativePermissions: Decodable, Equatable, Sendable {
  public let discovery: Bool
  public let search: Bool
  public let subscribe: Bool
  public let manage: Bool
  public let features: [String: Bool]

  /// 兼容历史用户没有 features 或未显式收窄分类权限的情况。
  public init(
    discovery: Bool = true, search: Bool = true, subscribe: Bool = true, manage: Bool = false,
    features: [String: Bool] = [:]
  ) {
    self.discovery = discovery
    self.search = search
    self.subscribe = subscribe
    self.manage = manage
    self.features = features
  }

  /// 非布尔分类值不能授予权限；features 只保留布尔项，与既有规整规则一致。
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode([String: JSONValue].self)
    discovery = Self.flag(value["discovery"], default: true)
    search = Self.flag(value["search"], default: true)
    subscribe = Self.flag(value["subscribe"], default: true)
    manage = Self.flag(value["manage"], default: false)
    if case .object(let values) = value["features"] {
      features = values.reduce(into: [:]) { result, item in
        if case .bool(let flag) = item.value { result[item.key] = flag }
      }
    } else {
      features = [:]
    }
  }

  /// 此方法只判断普通账号分类；超级管理员的统一覆盖由 SessionUser 执行。
  public func allows(_ category: NativePermission) -> Bool {
    switch category {
    case .discovery: discovery
    case .search: search
    case .subscribe: subscribe
    case .manage: manage
    case .admin: false
    }
  }

  /// 缺省功能继承所属分类；未知键保持兼容，明确 false 才收窄。
  public func allowsFeature(_ key: String?) -> Bool {
    guard let key, !key.isEmpty else { return true }
    return features[key] != false
  }

  /// null/缺省使用历史默认值，存在但类型不对时不以 truthy 语义放行。
  private static func flag(_ value: JSONValue?, default fallback: Bool) -> Bool {
    guard let value, value != .null else { return fallback }
    if case .bool(let flag) = value { return flag }
    return false
  }
}
