import Foundation

/// 已由现有认证接口签发的登录会话；只生成前端已有 store 的初始数据，不保存密码。
public struct AuthenticationSession: Sendable {
  /// 用户头像可能内嵌在既有登录资料中；认证响应与 64 KiB 导航消息采用不同限制。
  public static let maximumResponseBytes = 4 * 1024 * 1024
  public let accessToken: String
  public let user: JSONValue

  /// 消费密码、OTP 或其他现有登录接口的成功响应。
  public init(loginData: Data) throws {
    let payload = try Self.payload(loginData)
    guard case .string(let token) = payload["access_token"],
      case .bool(let superUser) = payload["super_user"],
      case .number(let userId) = payload["user_id"],
      case .string(let name) = payload["user_name"]
    else { throw BridgeError.invalidMessage }
    try Self.validate(token: token, userId: userId, name: name)
    accessToken = token
    user = .object([
      "superUser": .bool(superUser), "userID": .number(userId), "userName": .string(name),
      "avatar": Self.nonNull(payload["avatar"], fallback: .string("")),
      "level": Self.nonNull(payload["level"], fallback: .number(1)),
      "permissions": Self.nonNull(payload["permissions"], fallback: .object([:])),
    ])
  }

  /// 恢复令牌前先读取当前用户，使用服务器最新权限，不从持久化快照猜测授权。
  public init(accessToken: String, currentUserData: Data) throws {
    let payload = try Self.payload(currentUserData)
    guard case .bool(let superUser) = payload["is_superuser"],
      case .number(let userId) = payload["id"], case .string(let name) = payload["name"]
    else { throw BridgeError.invalidMessage }
    try Self.validate(token: accessToken, userId: userId, name: name)
    self.accessToken = accessToken
    user = .object([
      "superUser": .bool(superUser), "userID": .number(userId), "userName": .string(name),
      "avatar": Self.nonNull(payload["avatar"], fallback: .string("")),
      "level": Self.restoredLevel(payload: payload, token: accessToken),
      "permissions": Self.nonNull(payload["permissions"], fallback: .object([:])),
    ])
  }

  /// current 不返回站点等级时沿用已由服务器验证的令牌声明，与网页登录恢复一致；不据此授予权限。
  private static func restoredLevel(payload: [String: JSONValue], token: String) -> JSONValue {
    if let level = payload["level"], case .number = level { return level }
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return .number(1) }
    var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    guard let data = Data(base64Encoded: encoded),
      case .object(let claims) = try? JSONDecoder().decode(JSONValue.self, from: data),
      case .number(let level) = claims["level"], level.isFinite, level >= 0,
      level.rounded() == level
    else { return .number(1) }
    return .number(level)
  }

  /// 与现有 Pinia 持久化字段一致；通过独立的受信启动入口交付，不进入导航消息。
  public var browserStorage: JSONValue {
    .object([
      "auth": .object([
        "token": .string(accessToken), "remember": .bool(true), "originalPath": .null,
      ]), "user": user,
    ])
  }

  /// 与网页登录的空值默认值一致，旧实例返回 null 时不破坏已有 store 的类型。
  private static func nonNull(_ value: JSONValue?, fallback: JSONValue) -> JSONValue {
    guard let value, value != .null else { return fallback }
    return value
  }

  /// 兼容当前统一 data envelope 与登录接口的原始响应，拒绝失败 envelope。
  private static func payload(_ data: Data) throws -> [String: JSONValue] {
    guard data.count <= maximumResponseBytes,
      case .object(let root) = try JSONDecoder().decode(JSONValue.self, from: data)
    else { throw BridgeError.invalidMessage }
    if let success = root["success"] {
      guard success == .bool(true), case .object(let payload) = root["data"] else {
        throw BridgeError.invalidMessage
      }
      return payload
    }
    return root
  }

  /// 限制认证响应的必要身份字段，避免把空令牌或非整数用户写入前端。
  private static func validate(token: String, userId: Double, name: String) throws {
    guard !token.isEmpty, token.utf8.count <= 8192,
      !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      userId.isFinite, userId >= 0, userId.rounded() == userId, userId <= 9_007_199_254_740_991,
      !name.isEmpty, name.utf8.count <= 512
    else { throw BridgeError.invalidMessage }
  }

  /// OAuth 表单严格编码每个值，用户名中的加号、与号及非 ASCII 字符不会改变字段。
  public static func passwordForm(username: String, password: String, otp: String?) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.formUnion(CharacterSet(charactersIn: "-._~"))
    let fields = [("username", username), ("password", password), ("otp_password", otp ?? "")]
    return Data(
      fields.map { key, value in
        "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
      }.joined(separator: "&").utf8)
  }
}
