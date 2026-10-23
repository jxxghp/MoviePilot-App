import Foundation

/// 桥接消息的受限 JSON 值，避免让业务对象或可执行代码穿过消息边界。
public enum JSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  /// 逐种类型解码 JSON；深度与消息大小由入站校验器限制。
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      self = .array(try container.decode([JSONValue].self))
    }
  }

  /// 只编码标准 JSON 值，禁止使用任意对象描述作为消息内容。
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

/// 原生与网页共享的消息外壳；会话是关联标识，不是认证凭据。
public struct BridgeEnvelope: Codable, Equatable, Sendable {
  public let `protocol`: String
  public let major: Int
  public let type: String
  public let requestId: String
  public let sessionId: String?
  public let routeRevision: Int?
  public let stateRevision: Int?
  public let payload: JSONValue

  /// 构造 v1 消息；网页就绪之外的消息必须由接收端验证会话。
  public init(
    type: String, requestId: String, sessionId: String? = nil,
    routeRevision: Int? = nil, stateRevision: Int? = nil, payload: JSONValue
  ) {
    self.protocol = "moviepilot.chrome"
    self.major = 1
    self.type = type
    self.requestId = requestId
    self.sessionId = sessionId
    self.routeRevision = routeRevision
    self.stateRevision = stateRevision
    self.payload = payload
  }

  /// 使用明确的 Codable 模型解码消息正文。
  public func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(payload))
  }
}

/// 协议错误不会携带服务器地址、业务正文或用户认证数据。
public enum BridgeError: String, Error, Codable, Sendable {
  case invalidMessage = "invalid_message"
  case unsupportedVersion = "unsupported_version"
  case unsupportedCapability = "unsupported_capability"
  case untrustedFrame = "untrusted_frame"
  case staleSession = "stale_session"
  case staleRoute = "stale_route"
  case actionNotAvailable = "action_not_available"
  case busy
}

/// 来源信息由 WKScriptMessage 的 frame 与实际 WebView 提供，不能从消息正文读取。
public struct BridgeSource: Sendable {
  public let isMainFrame: Bool
  public let isCurrentWebView: Bool
  public let origin: WebOrigin?

  /// 保存容器已经核实的来源信息。
  public init(isMainFrame: Bool, isCurrentWebView: Bool, origin: WebOrigin?) {
    self.isMainFrame = isMainFrame
    self.isCurrentWebView = isCurrentWebView
    self.origin = origin
  }
}

/// 所有网页入站消息共同使用的边界检查，先校验大小与来源再进行 JSON 解码。
public struct BridgeValidator: Sendable {
  public static let maximumMessageBytes = 65_536
  public let origin: WebOrigin

  /// 将校验器绑定到当前用户配置的精确来源。
  public init(origin: WebOrigin) { self.origin = origin }

  /// 检查主 frame、来源、版本、会话、标识与嵌套深度。
  public func decode(_ data: Data, source: BridgeSource, sessionId: String?) throws
    -> BridgeEnvelope
  {
    guard source.isMainFrame, source.isCurrentWebView, source.origin == origin else {
      throw BridgeError.untrustedFrame
    }
    guard data.count <= Self.maximumMessageBytes, Self.isBoundedJSON(data),
      let message = try? JSONDecoder().decode(BridgeEnvelope.self, from: data),
      message.protocol == "moviepilot.chrome", !message.type.isEmpty,
      Self.isIdentifier(message.requestId),
      message.routeRevision.map({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }) ?? true,
      message.stateRevision.map({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }) ?? true
    else {
      throw BridgeError.invalidMessage
    }
    guard message.major == 1 else { throw BridgeError.unsupportedVersion }
    if message.type != "web.ready" {
      guard let sessionId, message.sessionId == sessionId else { throw BridgeError.staleSession }
    }
    return message
  }

  /// 标识限制为可打印的短字符串，阻止日志与注册表被无界标识污染。
  public static func isIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 128
      && value.unicodeScalars.allSatisfy { $0.value >= 0x21 && $0.value <= 0x7E }
  }

  /// 解码前扫描结构深度；引号内的括号不影响深度，JSON 语法仍交给系统解码器。
  private static func isBoundedJSON(_ data: Data) -> Bool {
    var depth = 0
    var quoted = false
    var escaped = false
    for byte in data {
      if quoted {
        if escaped {
          escaped = false
        } else if byte == 92 {
          escaped = true
        } else if byte == 34 {
          quoted = false
        }
      } else if byte == 34 {
        quoted = true
      } else if byte == 123 || byte == 91 {
        depth += 1
        if depth > 16 { return false }
      } else if byte == 125 || byte == 93 {
        depth -= 1
      }
    }
    return depth == 0 && !quoted
  }
}
