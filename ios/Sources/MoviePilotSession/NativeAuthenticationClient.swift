import Foundation
import MoviePilotAPI
import MoviePilotCore

/// 认证交互的稳定原因；不保存输入、服务端正文或认证令牌。
public enum NativeAuthenticationError: Error, Equatable, Sendable {
  case credentials
  case verificationRequired(methods: [String])
  case inactiveAccount
  case invalidInput
}

/// 初始化探测保留旧实例缺少接口的区别，不能把 404 当成新建管理员指令。
public enum NativeInitialization: Equatable, Sendable {
  case ready
  case required(configuredUsername: String?)
  case legacy
}

/// 创建结果区分本次真实写入和探测时发现已经就绪，避免界面误报创建成功。
public enum NativeInitializationResult: Equatable, Sendable {
  case created, alreadyInitialized
}

/// 会话只依赖原生认证协议，便于 Passkey 等后续适配复用同一生命周期。
public protocol NativeAuthenticating: Sendable {
  var address: ServerAddress { get }

  /// 匿名读取初始化状态，不加载前端或据此自动创建管理员。
  func initialization() async throws -> NativeInitialization

  /// 明确提交首次管理员与 API Key，不能自动重试或顺带登录。
  func initialize(
    username: String, password: String, confirmation: String, apiKey: String
  ) async throws

  /// 明确提交一次密码/OTP，不自动重放或持久化输入。
  func login(username: String, password: String, otp: String?) async throws -> SessionIdentity

  /// 通过服务器 current 验证原令牌并取得最新身份；不隐式换发另一个 credential。
  func restore(accessToken: String) async throws -> SessionIdentity

  /// 使本次认证网络失效，不能影响其它实例的客户端。
  func cancel()
}

/// 只访问固定认证端点的临时会话，不探测前端文件，也不创建或注入任何网页状态。
public final class NativeAuthenticationClient: NativeAuthenticating {
  public let address: ServerAddress
  private let language: AppLanguage
  private let session: URLSession
  private static let maximumBytes = 4 * 1024 * 1024

  /// 生产网络独属于一次认证尝试；Cookie、缓存和系统凭据不能跨实例继承。
  public convenience init(
    address: ServerAddress, language: AppLanguage = .simplifiedChinese
  ) {
    self.init(address: address, language: language, configuration: .ephemeral)
  }

  /// 测试只替换 HTTP 协议适配，不绕过请求编码、身份校验和取消。
  init(address: ServerAddress, language: AppLanguage, configuration: URLSessionConfiguration) {
    self.address = address
    self.language = language
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.httpAdditionalHeaders = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    configuration.waitsForConnectivity = false
    session = URLSession(
      configuration: configuration, delegate: NativeAuthRedirectGuard(), delegateQueue: nil)
  }

  /// 不让遗留的认证请求在所有者释放后继续持有连接。
  deinit { session.invalidateAndCancel() }

  /// 当前尝试结束后禁止复用，重试由用户动作创建新尝试，不自动重发密码。
  public func cancel() { session.invalidateAndCancel() }

  /// 匿名探测不返回已初始化实例的配置用户名，旧接口缺失时仍可继续原有登录。
  public func initialization() async throws -> NativeInitialization {
    let (data, response) = try await request(.initialization)
    try Task.checkCancellation()
    if response.statusCode == 404 { return .legacy }
    let payload = try Self.decode(InitializationPayload.self, data: data)
    try Task.checkCancellation()
    return payload.initialized ? .ready : .required(configuredUsername: payload.configuredUsername)
  }

  /// 使用既有 JSON 创建协议，密码与 API Key 只保留到这次明确提交结束。
  public func initialize(
    username: String, password: String, confirmation: String, apiKey: String
  ) async throws {
    let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...50).contains(name.count), (6...50).contains(password.count),
      password == confirmation, (16...256).contains(key.count)
    else { throw NativeAuthenticationError.invalidInput }
    let payload = InitializationForm(
      username: name, password: password, confirmPassword: confirmation, apiKey: key)
    let (data, _) = try await request(.initialize, body: JSONEncoder().encode(payload))
    _ = try Self.decode(JSONValue.self, data: data)
    try Task.checkCancellation()
  }

  /// 密码与 OTP 只在明确调用中发送一次，挑战不记为登录成功，也不自动选择验证方式。
  public func login(username: String, password: String, otp: String?) async throws
    -> SessionIdentity
  {
    guard username.utf8.count <= 512, password.utf8.count <= 65_536,
      (otp?.utf8.count ?? 0) <= 512
    else { throw NativeAuthenticationError.invalidInput }
    let body = Self.passwordForm(username: username, password: password, otp: otp)
    let (data, response) = try await request(.login, body: body)
    if response.statusCode == 401 {
      do {
        let challenge = try JSONDecoder().decode(MFAEnvelope.self, from: data)
        guard !challenge.success, !challenge.data.methods.isEmpty,
          challenge.data.methods.count <= 16,
          challenge.data.methods.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 })
        else { throw APIError.invalidResponse }
        throw NativeAuthenticationError.verificationRequired(methods: challenge.data.methods)
      } catch let error as NativeAuthenticationError {
        throw error
      } catch {
        throw APIError.invalidResponse
      }
    }
    let result = try Self.decode(LoginPayload.self, data: data).identity(address: address)
    try Task.checkCancellation()
    return result
  }

  /// 保存令牌必须向 user/current 验证，不能只凭本地 JWT 恢复用户和权限。
  public func restore(accessToken: String) async throws -> SessionIdentity {
    guard SessionIdentity.validToken(accessToken) else { throw APIError.invalidCredential }
    let (data, _) = try await request(.current, accessToken: accessToken)
    let payload = try Self.decode(CurrentUserPayload.self, data: data)
    let result = try SessionIdentity(
      address: address, user: payload.user(verifiedAccessToken: accessToken),
      accessToken: accessToken)
    try Task.checkCancellation()
    return result
  }

  /// 认证原始响应与历史包装响应仅在封闭的认证端点兼容，不影响插件 payload 规则。
  private static func decode<Value: Decodable>(_ type: Value.Type, data: Data) throws -> Value {
    do {
      let fields = try JSONDecoder().decode([String: JSONValue].self, from: data)
      if fields["success"] != nil {
        return try JSONDecoder().decode(NativeAuthEnvelope<Value>.self, from: data).value
      }
      return try JSONDecoder().decode(type, from: data)
    } catch let error as APIError {
      throw error
    } catch {
      throw APIError.invalidResponse
    }
  }

  /// 路径由封闭枚举决定；认证请求不成为可携带凭据的通用 URL 代理。
  private func request(
    _ endpoint: NativeAuthEndpoint, body: Data? = nil, accessToken: String? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    try Task.checkCancellation()
    let url = try APIEndpoint(path: endpoint.path).url(for: address)
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
    request.timeoutInterval = 20
    request.httpMethod = body == nil ? "GET" : "POST"
    request.httpBody = body
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.setValue(language.rawValue, forHTTPHeaderField: "X-MoviePilot-Locale")
    if body != nil {
      request.setValue(
        endpoint == .initialize
          ? "application/json; charset=utf-8"
          : "application/x-www-form-urlencoded; charset=utf-8",
        forHTTPHeaderField: "Content-Type")
    }
    if let accessToken {
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
    CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &request, for: address)
    do {
      let (bytes, raw) = try await session.bytes(for: request)
      defer { bytes.task.cancel() }
      guard let response = raw as? HTTPURLResponse, response.url == url else {
        throw APIError.invalidResponse
      }
      if CloudflareAccessProtocol.detectChallenge(response: response, requestURL: url).isChallenge {
        throw APIError.cloudflareAccessRequired
      }
      switch response.statusCode {
      case 200: break
      case 401
      where endpoint == .login
        && response.value(forHTTPHeaderField: "X-MFA-Required")?.lowercased() == "true":
        break
      case 401:
        if endpoint == .login { throw NativeAuthenticationError.credentials }
        throw APIError.unauthorized
      case 403:
        var prefix = Data()
        prefix.reserveCapacity(512)
        do {
          for try await byte in bytes {
            if prefix.count >= 4_096 { break }
            prefix.append(byte)
          }
        } catch {}
        if CloudflareAccessProtocol.detectChallenge(
          response: response, bodyData: prefix, requestURL: url
        ).isChallenge {
          throw APIError.cloudflareAccessRequired
        }
        if APIClient.isTokenInvalidForbiddenBody(prefix) {
          throw APIError.unauthorized
        }
        throw APIError.forbidden
      case let status where endpoint == .initialize && [400, 422].contains(status):
        throw NativeAuthenticationError.invalidInput
      case 404 where endpoint == .initialization: return (Data(), response)
      case 429:
        throw APIError.rateLimited(
          retryAfter: APIClient.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
      case 300..<400: throw APIError.redirectRefused
      default: throw APIError.httpStatus(response.statusCode)
      }
      if response.mimeType?.lowercased() != "application/json" {
        var htmlPrefix = Data()
        htmlPrefix.reserveCapacity(1_024)
        do {
          for try await byte in bytes {
            if htmlPrefix.count >= 4_096 { break }
            htmlPrefix.append(byte)
          }
        } catch {}
        if CloudflareAccessProtocol.detectChallenge(
          response: response, bodyData: htmlPrefix, requestURL: url
        ).isChallenge {
          throw APIError.cloudflareAccessRequired
        }
        throw APIError.invalidResponse
      }
      guard response.expectedContentLength <= Self.maximumBytes else {
        throw APIError.responseTooLarge
      }
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < Self.maximumBytes else { throw APIError.responseTooLarge }
        data.append(byte)
      }
      try Task.checkCancellation()
      return (data, response)
    } catch let error as APIError {
      throw error
    } catch let error as NativeAuthenticationError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw error.code == .timedOut ? APIError.timedOut : APIError.unavailable
    } catch {
      throw APIError.unavailable
    }
  }

  /// 每个字段独立按 OAuth 表单编码，保留加号、换行、非 ASCII 字符与 OTP 前导零。
  private static func passwordForm(username: String, password: String, otp: String?) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let fields = [("username", username), ("password", password), ("otp_password", otp ?? "")]
    return Data(
      fields.map { key, value in
        "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
      }.joined(separator: "&").utf8)
  }
}

/// 认证白名单不包含前端探测、任意插件接口或 URL 重写。
private enum NativeAuthEndpoint {
  case initialization, initialize, login, current

  /// 所有路径均相对实例 api/v1，代理子路径由 APIEndpoint 保留。
  var path: [String] {
    switch self {
    case .initialization, .initialize: ["login", "initialization"]
    case .login: ["login", "access-token"]
    case .current: ["user", "current"]
    }
  }
}

/// 一次性初始化请求不实现日志描述或持久化接口，编码键严格跟随后端。
private struct InitializationForm: Encodable {
  let username: String
  let password: String
  let confirmPassword: String
  let apiKey: String

  /// 确认密码不能省略，API Key 不放入 URL、认证头或本地默认值。
  private enum CodingKeys: String, CodingKey {
    case username, password
    case confirmPassword = "confirm_password"
    case apiKey = "api_key"
  }
}

/// 初始化响应保持部署固定用户名，但不从其它接口推断是否可以创建管理员。
private struct InitializationPayload: Decodable {
  let initialized: Bool
  let configuredUsername: String?

  /// 与既有匿名初始化接口一致。
  private enum CodingKeys: String, CodingKey {
    case initialized
    case configuredUsername = "configured_username"
  }
}

/// MFA 失败响应里的方法清单只描述可选验证方式，不包含成功身份。
private struct MFAEnvelope: Decodable {
  let success: Bool
  let data: Methods

  /// 不丢弃未知方法，后续 UI 可按能力明确显示不支持的验证入口。
  struct Methods: Decodable {
    let methods: [String]

    /// 服务端返回 mfa_methods，避免错误读取网页中的临时状态字段。
    private enum CodingKeys: String, CodingKey { case methods = "mfa_methods" }
  }
}

/// 认证历史包装格式；失败响应不能被解包成看似成功的用户。
private struct NativeAuthEnvelope<Value: Decodable>: Decodable {
  let value: Value

  /// 只解析当前认证协议声明字段，原始响应由专用调用点选择。
  private enum CodingKeys: String, CodingKey { case success, data }

  /// 先检查服务端成功标志，再解码完整身份。
  init(from decoder: Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    guard try fields.decode(Bool.self, forKey: .success) else { throw APIError.businessFailure }
    value = try fields.decode(Value.self, forKey: .data)
  }
}

/// 密码及 Bearer 不跟随任何跳转，路径修正必须由固定端点定义解决。
private final class NativeAuthRedirectGuard: NSObject, URLSessionTaskDelegate {
  /// 同源跳转也拒绝，避免认证表单被转发到未声明路径。
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
