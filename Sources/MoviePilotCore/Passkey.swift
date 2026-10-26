import Foundation

/// 系统验证只返回固定错误类型，不将浏览器异常或认证数据展示给用户。
public enum PasskeyFailure: String, Error, LocalizedError, Sendable {
  case canceled, expired, unsupported, invalid, failed

  /// 原生登录页保留明确的重新尝试入口，不显示服务器或系统内部信息。
  public var errorDescription: String? {
    switch self {
    case .canceled: nil
    case .expired: "通行密钥验证已过期，请重新尝试。"
    case .unsupported: "当前连接或系统不支持通行密钥，请使用 HTTPS 地址和支持的系统。"
    case .invalid: "通行密钥验证结果无效，请重新尝试。"
    case .failed: "未能完成通行密钥验证，请重新尝试。"
    }
  }
}

/// 当前实例的一次性通行密钥事务；只交接公开挑战，事务令牌不进入认证窗口 URL。
public struct PasskeyTransaction: Sendable {
  public let authorizationURL: URL
  private let address: ServerAddress
  private let state: String
  private let challenge: String
  private let createdAt: Date
  private let expiresAt: Date
  private var token: String?

  /// 消费现有 start 响应，限制挑战来源和体积；兼容历史 JSON 字符串 options。
  public init(startData: Data, address: ServerAddress, state: Data, now: Date = Date()) throws {
    guard Self.isSecure(address), state.count == 32 else { throw PasskeyFailure.unsupported }
    let root = try Self.object(startData, maximum: 131_072)
    guard root["success"] == .bool(true), case .object(let data) = root["data"],
      case .string(let token) = data["transaction_token"], !token.isEmpty,
      token.utf8.count <= 8192,
      !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw PasskeyFailure.failed }
    let options: [String: JSONValue]
    if case .string(let serialized) = data["options"] {
      options = try Self.object(Data(serialized.utf8), maximum: 24_576)
    } else if case .object(let value) = data["options"] {
      options = value
    } else {
      throw PasskeyFailure.invalid
    }
    let timeout = try Self.validate(options: options, address: address)
    guard case .string(let challenge) = options["challenge"] else { throw PasskeyFailure.invalid }
    let state = Self.encode(state)
    let payload = try JSONEncoder().encode(
      JSONValue.object([
        "version": .number(1), "state": .string(state), "options": .object(options),
      ]))
    let encoded = Self.encode(payload)
    guard encoded.utf8.count <= 32_768,
      var url = URLComponents(
        url: address.url.appendingPathComponent("native-passkey.html"),
        resolvingAgainstBaseURL: false)
    else { throw PasskeyFailure.invalid }
    url.fragment = "request=\(encoded)"
    guard let target = url.url else { throw PasskeyFailure.invalid }
    authorizationURL = target
    self.address = address
    self.state = state
    self.challenge = challenge
    self.token = token
    createdAt = now
    expiresAt = now.addingTimeInterval(timeout)
  }

  /// 回调仅供发起的 AS 会话消费一次；最终凭证签名和账户权限仍由既有 finish 验证。
  public mutating func finishBody(
    callback: URL, address: ServerAddress, now: Date = Date()
  ) throws -> Data {
    guard let token else { throw PasskeyFailure.expired }
    self.token = nil
    guard address == self.address, now >= createdAt, now < expiresAt else {
      throw PasskeyFailure.expired
    }
    guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
      parts.scheme == "moviepilot", parts.host == "passkey", parts.path == "/callback",
      parts.port == nil, parts.user == nil, parts.password == nil, parts.query == nil,
      let fragment = parts.fragment, fragment == parts.percentEncodedFragment,
      fragment.hasPrefix("result="), fragment.utf8.count <= 32_775
    else { throw PasskeyFailure.invalid }
    let bytes = try Self.decode(String(fragment.dropFirst(7)), minimum: 1, maximum: 24_576)
    let result = try Self.object(bytes, maximum: 24_576)
    guard result["version"] == .number(1), result["state"] == .string(state) else {
      throw PasskeyFailure.invalid
    }
    if case .string(let error) = result["error"] {
      guard Set(result.keys) == ["version", "state", "error"],
        let failure = PasskeyFailure(rawValue: error)
      else { throw PasskeyFailure.invalid }
      throw failure
    }
    guard Set(result.keys) == ["version", "state", "credential"],
      case .object(let credential) = result["credential"]
    else { throw PasskeyFailure.invalid }
    try validate(credential: credential)
    return try JSONEncoder().encode(
      JSONValue.object([
        "credential": .object(credential), "transaction_token": .string(token),
      ]))
  }

  /// 只有既有服务明确启用的系统通行密钥方式才能显示原生入口。
  public static func providerEnabled(_ data: Data) throws -> Bool {
    guard data.count <= 65_536,
      case .array(let providers) = try JSONDecoder().decode(JSONValue.self, from: data),
      providers.count <= 128
    else { throw PasskeyFailure.invalid }
    return providers.contains { provider in
      guard case .object(let value) = provider else { return false }
      return value["type"] == .string("system") && value["method"] == .string("passkey")
        && value["enabled"] == .bool(true)
    }
  }

  /// 静态标记只声明专用页协议，不从旧 HTML 登录或任意重定向猜测兼容性。
  public static func supportsFrontend(_ data: Data) -> Bool {
    guard let value = try? object(data, maximum: 1024) else { return false }
    return value == ["protocol": .string("moviepilot.passkey"), "version": .number(1)]
  }

  /// WebAuthn 需要安全来源；HTTP 只允许系统浏览器认可的回环开发地址。
  public static func isSecure(_ address: ServerAddress) -> Bool {
    address.origin.scheme == "https"
      || ["localhost", "127.0.0.1", "::1"].contains(address.origin.host)
  }

  /// 与独立前端协议保持相同选项边界，拒绝错域、未知字段和超大凭证列表。
  private static func validate(options: [String: JSONValue], address: ServerAddress) throws
    -> Double
  {
    guard
      Set(options.keys).isSubset(of: [
        "challenge", "rpId", "timeout", "allowCredentials", "userVerification",
      ]), case .string(let challenge) = options["challenge"]
    else { throw PasskeyFailure.invalid }
    _ = try decode(challenge, minimum: 16, maximum: 1024)
    if let rp = options["rpId"] {
      guard case .string(let value) = rp, !value.isEmpty, value.utf8.count <= 253,
        value == value.lowercased(),
        value == address.origin.host
          || (address.origin.host.contains(":") && value == "[\(address.origin.host)]")
          || (value.contains(".") && !value.contains(":")
            && address.origin.host.hasSuffix(".\(value)"))
      else { throw PasskeyFailure.invalid }
    }
    var timeout = 120.0
    if let value = options["timeout"] {
      guard case .number(let milliseconds) = value, milliseconds.isFinite, milliseconds >= 1 else {
        throw PasskeyFailure.invalid
      }
      timeout = min(milliseconds / 1000, timeout)
    }
    if let value = options["userVerification"] {
      guard case .string(let preference) = value,
        ["required", "preferred", "discouraged"].contains(preference)
      else { throw PasskeyFailure.invalid }
    }
    if let value = options["allowCredentials"] {
      guard case .array(let credentials) = value, credentials.count <= 64 else {
        throw PasskeyFailure.invalid
      }
      for item in credentials {
        guard case .object(let credential) = item,
          Set(credential.keys).isSubset(of: ["id", "type", "transports"]),
          credential["type"] == .string("public-key"), case .string(let id) = credential["id"]
        else { throw PasskeyFailure.invalid }
        _ = try decode(id, minimum: 1, maximum: 1024)
        if let value = credential["transports"] {
          guard case .array(let transports) = value, transports.count <= 8,
            transports.allSatisfy({ item in
              guard case .string(let name) = item else { return false }
              return ["ble", "hybrid", "internal", "nfc", "usb", "smart-card"].contains(name)
            })
          else { throw PasskeyFailure.invalid }
        }
      }
    }
    return timeout
  }

  /// 身份、challenge 和来源必须对应当前事务；不信任普通 App 外链携带的认证数据。
  private func validate(credential: [String: JSONValue]) throws {
    guard Set(credential.keys) == ["id", "rawId", "type", "response"],
      credential["type"] == .string("public-key"), case .string(let id) = credential["id"],
      credential["rawId"] == .string(id), case .object(let response) = credential["response"],
      Set(response.keys) == ["authenticatorData", "clientDataJSON", "signature", "userHandle"],
      case .string(let auth) = response["authenticatorData"],
      case .string(let client) = response["clientDataJSON"],
      case .string(let signature) = response["signature"]
    else { throw PasskeyFailure.invalid }
    _ = try Self.decode(id, minimum: 1, maximum: 1024)
    _ = try Self.decode(auth, minimum: 37, maximum: 2048)
    _ = try Self.decode(signature, minimum: 1, maximum: 2048)
    let clientData = try Self.object(
      Self.decode(client, minimum: 1, maximum: 4096), maximum: 4096)
    guard clientData["type"] == .string("webauthn.get"),
      clientData["challenge"] == .string(challenge),
      clientData["crossOrigin"] == nil || clientData["crossOrigin"] == .bool(false),
      case .string(let origin) = clientData["origin"],
      let url = URLComponents(string: origin), url.path.isEmpty, url.query == nil,
      url.fragment == nil, url.user == nil, url.password == nil, let target = url.url,
      address.contains(target)
    else { throw PasskeyFailure.invalid }
    if case .string(let user) = response["userHandle"] {
      _ = try Self.decode(user, minimum: 1, maximum: 256)
    } else if response["userHandle"] != .null {
      throw PasskeyFailure.invalid
    }
  }

  /// JSON 边界独立于用户资料的大响应限额，拒绝数组和无界字典。
  private static func object(_ data: Data, maximum: Int) throws -> [String: JSONValue] {
    guard data.count <= maximum,
      case .object(let value) = try JSONDecoder().decode(JSONValue.self, from: data)
    else { throw PasskeyFailure.invalid }
    return value
  }

  /// 规范无填充 Base64URL 编码只用于公开挑战、状态和一次性断言。
  private static func encode(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  /// 解码前限制字符与体积，解码后复核规范形式，防止宽松 Foundation 解码扩大输入范围。
  private static func decode(_ value: String, minimum: Int, maximum: Int) throws -> Data {
    guard !value.isEmpty, value.utf8.count <= (maximum * 4 + 2) / 3,
      value.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0)
          || (48...57).contains($0) || $0 == 45 || $0 == 95
      })
    else { throw PasskeyFailure.invalid }
    var raw = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
    guard let data = Data(base64Encoded: raw), (minimum...maximum).contains(data.count),
      encode(data) == value
    else { throw PasskeyFailure.invalid }
    return data
  }
}
