import Foundation
import MoviePilotCore
import Security

/// 认证失败只向 UI 暴露可操作原因，不回显服务器响应、令牌或输入。
enum AuthenticationError: LocalizedError {
  case credentials, otpRequired, unsupportedVerification, notInitialized, unavailable,
    invalidResponse, passkeyFrontendRequired
  case throttled(Int)

  /// 登录界面的错误文案不包含凭据或调试信息。
  var errorDescription: String? {
    switch self {
    case .credentials: "用户名、密码或验证码不正确。"
    case .otpRequired: "请输入身份验证器中的 6 位验证码。"
    case .unsupportedVerification: "当前 App 尚不支持此实例要求的验证方式，请检查账户验证设置。"
    case .notInitialized: "此实例尚未初始化，请先在浏览器中创建管理员，再返回 App 重新检查。"
    case .unavailable: "无法连接此实例，请检查地址、网络和服务状态。"
    case .invalidResponse: "认证接口返回了不支持的数据，请更新实例或检查服务后重试。"
    case .passkeyFrontendRequired: "请更新实例的前端资源后，再使用 App 通行密钥登录。"
    case .throttled(let seconds): "登录尝试过于频繁，请在 \(seconds) 秒后重试。"
    }
  }
}

/// 一次认证交接包含既有用户数据和服务签发的 Cookie，不包含用户密码。
struct AuthenticationResult {
  let session: AuthenticationSession
  let cookies: [HTTPCookie]
}

/// 仅访问当前实例的既有认证接口；禁止跨来源重定向携带表单或令牌。
@MainActor
final class AuthenticationClient: NSObject, URLSessionTaskDelegate {
  private let address: ServerAddress
  nonisolated private let origin: WebOrigin
  private lazy var network: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    configuration.urlCache = nil
    return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
  }()

  /// 网络会话独属于一次实例登录，不共享全局 Cookie 存储。
  init(address: ServerAddress) {
    self.address = address
    origin = address.origin
  }

  /// 首次连接探测现有初始化接口；没有该接口的旧实例仍可尝试原有登录。
  func isInitialized() async throws -> Bool {
    let (data, response) = try await request("login/initialization")
    if response.statusCode == 404 { return true }
    guard response.statusCode == 200,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let payload = root["data"] as? [String: Any], let value = payload["initialized"] as? Bool
    else { throw AuthenticationError.invalidResponse }
    return value
  }

  /// 此客户端只在内存中发送密码与 OTP，不记录或自动重试；密码记忆由表单单独管理。
  func login(username: String, password: String, otp: String?) async throws -> AuthenticationResult
  {
    let body = AuthenticationSession.passwordForm(username: username, password: password, otp: otp)
    let (data, response) = try await request("login/access-token", body: body)
    if response.statusCode == 401 {
      if response.value(forHTTPHeaderField: "X-MFA-Required")?.lowercased() == "true" {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let methods = (root?["data"] as? [String: Any])?["mfa_methods"] as? [String] ?? []
        throw methods == ["otp"]
          ? AuthenticationError.otpRequired : AuthenticationError.unsupportedVerification
      }
      throw AuthenticationError.credentials
    }
    guard response.statusCode == 200 else { throw AuthenticationError.invalidResponse }
    guard let session = try? AuthenticationSession(loginData: data) else {
      throw AuthenticationError.invalidResponse
    }
    return AuthenticationResult(session: session, cookies: cookies(response))
  }

  /// Keychain 中的令牌必须通过现有 current 接口验证后才交给页面。
  func restore(token: String) async throws -> AuthenticationResult {
    let (data, response) = try await request("user/current", token: token)
    if response.statusCode == 401 || response.statusCode == 403 {
      throw AuthenticationError.credentials
    }
    guard response.statusCode == 200,
      let session = try? AuthenticationSession(accessToken: token, currentUserData: data)
    else { throw AuthenticationError.invalidResponse }
    return AuthenticationResult(session: session, cookies: cookies(response))
  }

  /// 服务端开关决定登录入口；不支持该接口的旧实例保留原来的密码登录。
  func passkeyEnabled() async throws -> Bool {
    let (data, response) = try await request("auth/providers", timeout: 5)
    if response.statusCode == 404 { return false }
    guard response.statusCode == 200 else { throw AuthenticationError.invalidResponse }
    return try PasskeyTransaction.providerEnabled(data)
  }

  /// 先核对专用前端入口，再请求一次性挑战；事务令牌始终只留在 App 内存。
  func beginPasskey(username: String) async throws -> PasskeyTransaction {
    guard PasskeyTransaction.isSecure(address) else { throw PasskeyFailure.unsupported }
    let (marker, probe) = try await send(
      to: address.url.appendingPathComponent("native-passkey.json"), timeout: 5)
    guard probe.statusCode == 200, PasskeyTransaction.supportsFrontend(marker) else {
      throw AuthenticationError.passkeyFrontendRequired
    }
    let body = try JSONSerialization.data(
      withJSONObject: username.isEmpty ? [:] : ["username": username])
    let (data, response) = try await request(
      "mfa/passkey/authenticate/start", body: body, contentType: "application/json")
    guard response.statusCode == 200 else { throw PasskeyFailure.failed }
    var state = Data(count: 32)
    let status = state.withUnsafeMutableBytes { bytes in
      SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
    }
    guard status == errSecSuccess else { throw PasskeyFailure.failed }
    return try PasskeyTransaction(startData: data, address: address, state: state)
  }

  /// 验证后的断言仅交回既有 finish，复用原来的身份、权限、Cookie 和会话映射。
  func finishPasskey(body: Data) async throws -> AuthenticationResult {
    let (data, response) = try await request(
      "mfa/passkey/authenticate/finish", body: body, contentType: "application/json")
    guard response.statusCode == 200,
      let session = try? AuthenticationSession(loginData: data)
    else { throw PasskeyFailure.failed }
    return AuthenticationResult(session: session, cookies: cookies(response))
  }

  /// 离开登录控制器时取消网络，不让迟到响应切换新实例。
  func cancel() { network.invalidateAndCancel() }

  /// 认证接口采用固定相对路径和封闭方法，不成为通用网络代理。
  private func request(
    _ path: String, body: Data? = nil, token: String? = nil,
    contentType: String = "application/x-www-form-urlencoded; charset=utf-8", timeout: Double = 20
  ) async throws -> (
    Data, HTTPURLResponse
  ) {
    try await send(
      to: address.url.appendingPathComponent("api/v1/\(path)"), body: body, token: token,
      contentType: contentType, timeout: timeout)
  }

  /// 仅供上面的固定认证和兼容性路径共用传输边界，不接受来自网页的任意 URL。
  private func send(
    to url: URL, body: Data? = nil, token: String? = nil,
    contentType: String = "application/json", timeout: Double = 20
  ) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("zh-CN", forHTTPHeaderField: "X-MoviePilot-Locale")
    if let body {
      request.httpMethod = "POST"
      request.httpBody = body
      request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, raw) = try await network.data(for: request)
    guard let response = raw as? HTTPURLResponse,
      data.count <= AuthenticationSession.maximumResponseBytes
    else {
      throw AuthenticationError.invalidResponse
    }
    if response.statusCode == 429 {
      let seconds = Int(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
      throw AuthenticationError.throttled(max(1, min(seconds, 3600)))
    }
    if response.statusCode >= 500 { throw AuthenticationError.unavailable }
    return (data, response)
  }

  /// Cookie 只交给同一实例的数据容器，不复制到全局 Safari 或其他实例。
  private func cookies(_ response: HTTPURLResponse) -> [HTTPCookie] {
    let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
      if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
    }
    return HTTPCookie.cookies(withResponseHeaderFields: headers, for: address.url)
  }

  /// 认证请求的重定向仍必须保持精确 scheme/host/port，不能把密码转发到其他来源。
  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let url = request.url, url.user == nil, url.password == nil,
      WebOrigin(url: url) == origin
    else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}
