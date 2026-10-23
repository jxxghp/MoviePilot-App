import Foundation

/// 通知只能请求当前实例的内部导航，不携带认证数据或自动执行业务动作。
public struct NotificationIntent: Equatable, Sendable {
  public let address: ServerAddress
  public let route: String
  public let owner: String

  /// 验证服务端载荷；账号身份必须来自通知绑定，导航仍交由网页守卫处理。
  public init?(origin: String, route: String, owner: String) {
    guard let address = try? ServerAddress(origin),
      route.hasPrefix("/"), !route.hasPrefix("//"), !route.contains("\\"),
      route.utf8.count <= 2048,
      !route.unicodeScalars.contains(where: {
        CharacterSet.controlCharacters.contains($0) || CharacterSet.illegalCharacters.contains($0)
          || $0.properties.generalCategory == .format
      }),
      owner.range(of: "^[a-zA-Z0-9_-]{16,64}$", options: .regularExpression) != nil
    else { return nil }
    self.address = address
    self.route = route
    self.owner = owner
  }

  /// 主屏幕通知网页通过明确的自定义链接交接，重复参数及外站链接一律拒绝。
  public init?(url: URL) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "moviepilot-app", parts.host == "notification",
      parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
      parts.path.isEmpty || parts.path == "/", let items = parts.queryItems, items.count == 3,
      Set(items.map(\.name)) == Set(["origin", "route", "owner"]),
      let origin = items.first(where: { $0.name == "origin" })?.value,
      let route = items.first(where: { $0.name == "route" })?.value,
      let owner = items.first(where: { $0.name == "owner" })?.value
    else { return nil }
    self.init(origin: origin, route: route, owner: owner)
  }

  /// 当前登录身份与完整实例入口均匹配后才能消费，不能仅比较主机名。
  public func matches(address: ServerAddress, owner: String) -> Bool {
    self.address == address && self.owner == owner
  }
}
