import Foundation

/// 只允许有限的小组件意图；原生不能指定 API、URL、主令牌或任意网页命令。
public enum WidgetBridgeOperation: Equatable, Sendable {
  case context
  case register(owner: String, installationId: UUID)
  case revoke(owner: String, registrationId: UUID)
  case open(owner: String, content: WidgetContent)

  /// 出站字段与前端白名单一致，UUID 统一为小写，不包含可执行文本。
  public var payload: JSONValue {
    switch self {
    case .context: return .object(["operation": .string("context")])
    case .register(let owner, let id):
      return .object([
        "operation": .string("register"), "owner": .string(owner),
        "installationId": .string(id.uuidString.lowercased()),
      ])
    case .revoke(let owner, let id):
      return .object([
        "operation": .string("revoke"), "owner": .string(owner),
        "registrationId": .string(id.uuidString.lowercased()),
      ])
    case .open(let owner, let content):
      return .object([
        "operation": .string("open"), "owner": .string(owner), "content": .string(content.rawValue),
      ])
    }
  }
}

/// 错误只表达固定原因，禁止把后端响应正文或私密载荷用于错误信息。
public enum WidgetBridgeError: String, Error, Sendable {
  case unsupported, unavailable, unauthorized, forbidden
  case identityChanged = "identity_changed"
  case invalidRequest = "invalid_request"
  case invalidData = "invalid_data"
  case cancelled, busy
  case staleRequest = "stale_request"
  case requestLimit = "request_limit"
}

/// 当前网页主登录的不可变身份，不能用用户名或数字用户 ID 替代。
public struct WidgetAccountContext: Equatable, Sendable {
  public let owner: String
  public let availableContents: [WidgetContent]

  /// 有界白名单解码同时验证重复内容与 owner 格式，未知字段不进入原生状态。
  fileprivate init(_ fields: [String: JSONValue]) throws {
    guard fields["version"] == .number(1), case .string(let owner) = fields["owner"],
      owner.utf8.count == 32,
      owner.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
      case .array(let values) = fields["availableContents"], values.count <= 6
    else { throw WidgetBridgeError.invalidData }
    let contents = values.compactMap { value -> WidgetContent? in
      guard case .string(let raw) = value else { return nil }
      return WidgetContent(rawValue: raw)
    }
    guard contents.count == values.count, Set(contents).count == contents.count else {
      throw WidgetBridgeError.invalidData
    }
    self.owner = owner
    availableContents = contents
  }
}

/// 登记只在相关请求中暂存；secret 不能写入快照、路由、日志或展示模型。
public struct WidgetRegistrationReply: Sendable {
  public let context: WidgetAccountContext
  public let registrationId: UUID
  public let secret: String
  public let expiresAt: TimeInterval
}

/// 专用的一次性结果；不加入通用 command.result 或命令重放缓存。
public enum WidgetBridgeResponse: Sendable {
  case context(WidgetAccountContext)
  case registered(WidgetRegistrationReply)
  case completed

  /// 关联标识由协调器验证；这里只接受该操作的精确字段和最多 2 KiB 的正文。
  public static func decode(
    _ payload: JSONValue, for operation: WidgetBridgeOperation, now: Date = Date()
  ) throws -> WidgetBridgeResponse {
    guard let encoded = try? JSONEncoder().encode(payload), encoded.count <= 2048,
      case .object(let result) = payload
    else { throw WidgetBridgeError.invalidData }
    if result["success"] == .bool(false) {
      guard Set(result.keys) == ["success", "error"], case .string(let raw) = result["error"],
        let error = WidgetBridgeError(rawValue: raw)
      else { throw WidgetBridgeError.invalidData }
      throw error
    }
    guard Set(result.keys) == ["success", "data"], result["success"] == .bool(true),
      case .object(let fields) = result["data"]
    else { throw WidgetBridgeError.invalidData }
    switch operation {
    case .context:
      guard Set(fields.keys) == ["version", "owner", "availableContents"] else {
        throw WidgetBridgeError.invalidData
      }
      return .context(try WidgetAccountContext(fields))
    case .register(let owner, let installationId):
      guard
        Set(fields.keys) == [
          "version", "owner", "availableContents", "registrationId", "installationId", "secret",
          "expiresAt",
        ]
      else { throw WidgetBridgeError.invalidData }
      let context = try WidgetAccountContext(fields)
      guard context.owner == owner else { throw WidgetBridgeError.identityChanged }
      guard !context.availableContents.isEmpty,
        case .string(let rawId) = fields["registrationId"], let id = UUID(uuidString: rawId),
        rawId == id.uuidString.lowercased(),
        fields["installationId"] == .string(installationId.uuidString.lowercased()),
        case .string(let secret) = fields["secret"],
        WidgetStore.validCredential(secret, registrationId: id),
        case .number(let expiry) = fields["expiresAt"], expiry.isFinite,
        now.timeIntervalSince1970.isFinite, expiry > now.timeIntervalSince1970,
        expiry <= now.timeIntervalSince1970 + 30 * 86_400 + 300
      else { throw WidgetBridgeError.invalidData }
      return .registered(
        WidgetRegistrationReply(
          context: context, registrationId: id, secret: secret, expiresAt: expiry))
    case .revoke, .open:
      guard fields == ["completed": .bool(true)] else { throw WidgetBridgeError.invalidData }
      return .completed
    }
  }
}
