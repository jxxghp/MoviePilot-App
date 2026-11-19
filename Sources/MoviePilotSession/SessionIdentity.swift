import Foundation
import MoviePilotAPI
import MoviePilotCore

/// 已由服务器投影的当前用户，不包含令牌或任何浏览器持久化字段。
public struct SessionUser: Equatable, Sendable {
  public let id: Int
  public let name: String
  public let isSuperuser: Bool
  public let avatar: String
  public let level: Int
  public let permissions: NativePermissions

  /// 保持现有非负用户 ID 与等级语义，拒绝缺失身份，避免生成半有效会话。
  public init(
    id: Int, name: String, isSuperuser: Bool, avatar: String = "", level: Int = 1,
    permissions: NativePermissions = NativePermissions()
  ) throws {
    guard id >= 0, !name.isEmpty, name.utf8.count <= 512, level >= 0 else {
      throw APIError.invalidResponse
    }
    self.id = id
    self.name = name
    self.isSuperuser = isSuperuser
    self.avatar = avatar
    self.level = level
    self.permissions = permissions
  }

  /// 超级管理员覆盖所有入口；普通账号必须同时满足分类与细分功能要求。
  public func allows(_ requirement: PermissionRequirement) -> Bool {
    if isSuperuser { return true }
    if let category = requirement.category, !permissions.allows(category) { return false }
    return permissions.allowsFeature(requirement.feature)
  }
}

/// 认证服务交付的内存身份；绑定来源地址，令牌不进入 UI 快照或调试描述。
public struct SessionIdentity: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
  public let address: ServerAddress
  public let user: SessionUser
  let accessToken: String

  /// 只有已完成真实认证的适配器应构造此值；初始化本身不代替服务器验证。
  public init(address: ServerAddress, user: SessionUser, accessToken: String) throws {
    guard Self.validToken(accessToken) else { throw APIError.invalidCredential }
    self.address = address
    self.user = user
    self.accessToken = accessToken
  }

  /// 通用日志不输出用户名、服务地址或令牌。
  public var description: String { "SessionIdentity(<redacted>)" }

  /// 反射式字符串输出同样不能意外包含认证载荷。
  public var debugDescription: String { description }

  /// 写入 Authorization 之前拒绝空值、空白、控制字符和过大输入。
  static func validToken(_ token: String) -> Bool {
    !token.isEmpty && token.utf8.count <= 16_384
      && token.utf8.allSatisfy { (33...126).contains($0) }
  }
}

/// 当前用户响应仅用于服务器验证后的投影，不使用 JWT 中的角色或权限替代它。
struct CurrentUserPayload: Decodable {
  let id: Int
  let name: String
  let isSuperuser: Bool
  let avatar: String?
  let isActive: Bool?
  let level: Int?
  let permissions: NativePermissions?

  /// 对齐 user/current 现有字段名；不存在 level 时保留显式缺省。
  private enum CodingKeys: String, CodingKey {
    case id, name, avatar, level, permissions
    case isSuperuser = "is_superuser"
    case isActive = "is_active"
  }

  /// 仅从已验证令牌回退展示等级；权限、账号和角色始终取本次服务器结果。
  func user(verifiedAccessToken: String) throws -> SessionUser {
    guard isActive != false else { throw NativeAuthenticationError.inactiveAccount }
    return try SessionUser(
      id: id, name: name, isSuperuser: isSuperuser, avatar: avatar ?? "",
      level: level ?? Self.verifiedLevel(verifiedAccessToken),
      permissions: permissions ?? NativePermissions())
  }

  /// current 已验证后才调用，忽略 JWT 中任何其它字段，损坏或非法等级回退为 1。
  private static func verifiedLevel(_ token: String) -> Int {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return 1 }
    var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded),
      let claims = try? JSONDecoder().decode(LevelClaim.self, from: data), claims.level >= 0
    else { return 1 }
    return claims.level
  }

  /// 有意只解码展示等级，不能把声明中的权限或超级用户用于授权。
  private struct LevelClaim: Decodable {
    let level: Int
  }
}

/// 密码登录的既有原始返回格式，与普通 API envelope 的契约分开。
struct LoginPayload: Decodable {
  let accessToken: String
  let tokenType: String?
  let userID: Int
  let userName: String
  let superUser: Bool
  let avatar: String?
  let level: Int?
  let permissions: NativePermissions?

  /// 保留服务端稳定字段，不复用旧网页 Store 的驼峰命名。
  private enum CodingKeys: String, CodingKey {
    case avatar, level, permissions
    case accessToken = "access_token"
    case tokenType = "token_type"
    case userID = "user_id"
    case userName = "user_name"
    case superUser = "super_user"
  }

  /// 兼容历史省略 token_type 的响应，未知认证方案不能当作 Bearer 使用。
  func identity(address: ServerAddress) throws -> SessionIdentity {
    guard tokenType == nil || tokenType?.lowercased() == "bearer" else {
      throw APIError.invalidResponse
    }
    let user = try SessionUser(
      id: userID, name: userName, isSuperuser: superUser, avatar: avatar ?? "",
      level: level ?? 1, permissions: permissions ?? NativePermissions())
    return try SessionIdentity(address: address, user: user, accessToken: accessToken)
  }
}
