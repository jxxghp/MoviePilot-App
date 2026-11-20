import Foundation
import MoviePilotCore

/// 原生主体的私有 JSON 客户端；一个实例/身份会话拥有一个客户端，不依赖网页状态。
public final class APIClient: Sendable {
  private let address: ServerAddress
  private let token: String?
  private let language: AppLanguage
  private let session: URLSession
  private let imageSession: URLSession
  private let resourceCookies = APIResourceCookieStore()

  /// 生产使用独立临时会话；未登录端点可省略令牌，不从全局 Cookie 或 Keychain 猜测身份。
  public convenience init(
    address: ServerAddress, token: String? = nil, language: AppLanguage = .simplifiedChinese
  ) throws {
    try self.init(
      address: address, token: token, language: language, configuration: .ephemeral)
  }

  /// 测试仅注入 URLProtocol，仍执行真实请求构造和流式边界；清理配置中的共享身份。
  init(
    address: ServerAddress, token: String?, language: AppLanguage = .simplifiedChinese,
    configuration: URLSessionConfiguration
  ) throws {
    if let token {
      guard !token.isEmpty, token.utf8.count <= 16_384,
        token.utf8.allSatisfy({ (33...126).contains($0) })
      else { throw APIError.invalidCredential }
    }
    self.address = address
    self.token = token
    self.language = language
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.httpAdditionalHeaders = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 180
    configuration.waitsForConnectivity = false
    session = URLSession(
      configuration: configuration, delegate: APIRedirectGuard(), delegateQueue: nil)
    let imageConfiguration = (configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
    imageConfiguration.httpMaximumConnectionsPerHost = 8
    imageSession = URLSession(
      configuration: imageConfiguration, delegate: APIRedirectGuard(), delegateQueue: nil)
  }

  /// 释放当前客户端拥有的任务，不影响其它实例、Widget 或插件容器的网络。
  deinit {
    resourceCookies.cancel()
    session.invalidateAndCancel()
    imageSession.invalidateAndCancel()
  }

  /// 结束会话时取消所有未完成任务；后续登录必须创建新客户端。
  public func cancel() {
    resourceCookies.cancel()
    session.invalidateAndCancel()
    imageSession.invalidateAndCancel()
  }

  /// 供保真 JSON 解析器消费原始 payload；HTTP 边界与 typed API 相同，不猜测或跳过标准包装。
  public func requestPayload(_ endpoint: APIEndpoint) async throws -> APIResult<Data> {
    guard case .payload = endpoint.responseContract else { throw APIError.invalidEndpoint }
    let response = try await receive(endpoint)
    try Task.checkCancellation()
    return APIResult(
      value: response.data, statusCode: response.statusCode, collection: response.collection)
  }

  /// 图片代理只读取短效资源 Cookie；主令牌只用于先前的同源 JSON 请求或固定的续签读取。
  public func requestImage(_ sourceURL: URL, maximumWidth: Int? = nil) async throws -> APIImage {
    guard token != nil, Self.isValidImageSource(sourceURL),
      maximumWidth.map({ (1...2048).contains($0) }) ?? true
    else { throw token == nil ? APIError.invalidCredential : APIError.invalidEndpoint }
    var query = [
      URLQueryItem(name: "imgurl", value: sourceURL.absoluteString),
      URLQueryItem(name: "cache", value: "false"),
    ]
    if let maximumWidth {
      query.append(URLQueryItem(name: "maxWidth", value: String(maximumWidth)))
    }
    let endpoint = try APIEndpoint(
      path: ["system", "img", "0"], query: query, responseContract: .payload,
      maximumResponseBytes: APIImage.maximumBytes)
    let target = try endpoint.url(for: address)
    try Task.checkCancellation()
    let refresh = try await resourceCookies.resolve(for: target) {
      let endpoint = try APIEndpoint(path: ["media", "source"])
      _ = try await self.request(endpoint, as: [JSONValue].self)
    }
    do {
      return try await receiveImage(endpoint, cookie: refresh)
    } catch APIError.unauthorized {
      resourceCookies.remove(refresh)
      throw APIError.unauthorized
    }
  }

  /// 端点必须显式选择标准 envelope 或原始 payload；保留分页头而不修改列表。
  public func request<Value: Decodable & Sendable>(
    _ endpoint: APIEndpoint, as type: Value.Type = Value.self
  ) async throws -> APIResult<Value> {
    let response = try await receive(endpoint)
    let value: Value
    do {
      switch endpoint.responseContract {
      case .envelope:
        value = try JSONDecoder().decode(APIEnvelope<Value>.self, from: response.data).value
      case .payload:
        value = try JSONDecoder().decode(type, from: response.data)
      }
    } catch let error as APIError {
      throw error
    } catch {
      throw APIError.invalidResponse
    }
    try Task.checkCancellation()
    return APIResult(
      value: value, statusCode: response.statusCode, collection: response.collection)
  }

  /// 只验证无返回值的动作已被接受；不把异步任务的 HTTP 成功视为业务执行结束。
  public func perform(_ endpoint: APIEndpoint) async throws {
    let response = try await receive(endpoint)
    try Task.checkCancellation()
    if response.statusCode == 204 || endpoint.method == .head { return }
    do {
      switch endpoint.responseContract {
      case .envelope:
        _ = try JSONDecoder().decode(APIEnvelope<JSONValue>.self, from: response.data)
      case .payload:
        _ = try JSONDecoder().decode(JSONValue.self, from: response.data)
      }
    } catch let error as APIError {
      throw error
    } catch {
      throw APIError.invalidResponse
    }
    try Task.checkCancellation()
  }

  /// 读取时限制大小；任何状态都不重试，任何重定向都不继续发送身份。
  private func receive(_ endpoint: APIEndpoint) async throws -> APIHTTPResponse {
    try Task.checkCancellation()
    let url = try endpoint.url(for: address)
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
      timeoutInterval: endpoint.timeout)
    request.httpMethod = endpoint.method.rawValue
    request.httpBody = endpoint.body
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.setValue(language.rawValue, forHTTPHeaderField: "X-MoviePilot-Locale")
    if endpoint.body != nil {
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    do {
      let (bytes, raw) = try await session.bytes(for: request)
      defer { bytes.task.cancel() }
      guard let http = raw as? HTTPURLResponse, http.url == url else {
        throw APIError.invalidResponse
      }
      try Self.checkStatus(http)
      let hasBody = http.statusCode != 204 && endpoint.method != .head
      if hasBody {
        guard let mime = http.mimeType?.lowercased(),
          mime == "application/json" || mime.hasPrefix("application/") && mime.hasSuffix("+json")
        else { throw APIError.invalidResponse }
      }
      guard http.expectedContentLength <= endpoint.maximumResponseBytes else {
        throw APIError.responseTooLarge
      }
      let collection = try APICollectionMetadata(response: http)
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < endpoint.maximumResponseBytes else { throw APIError.responseTooLarge }
        data.append(byte)
      }
      try Task.checkCancellation()
      if token != nil, endpoint.method == .get, let cookie = APIResourceCookie(response: http) {
        resourceCookies.capture(cookie)
      }
      return APIHTTPResponse(data: data, statusCode: http.statusCode, collection: collection)
    } catch let error as APIError {
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

  /// 只向已校验的 MoviePilot API 地址发请求，并以流式方式限制图片响应大小。
  private func receiveImage(_ endpoint: APIEndpoint, cookie: APIResourceCookie) async throws
    -> APIImage
  {
    try Task.checkCancellation()
    let url = try endpoint.url(for: address)
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
      timeoutInterval: endpoint.timeout)
    request.httpMethod = APIMethod.get.rawValue
    request.httpShouldHandleCookies = false
    request.setValue("image/jpeg, image/png, image/webp", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.setValue(language.rawValue, forHTTPHeaderField: "X-MoviePilot-Locale")
    request.setValue(cookie.header, forHTTPHeaderField: "Cookie")
    do {
      let (bytes, raw) = try await imageSession.bytes(for: request)
      defer { bytes.task.cancel() }
      guard let http = raw as? HTTPURLResponse, http.url == url else {
        throw APIError.invalidResponse
      }
      try Self.checkStatus(http)
      guard let mimeType = http.mimeType?.lowercased(),
        ["image/jpeg", "image/png", "image/webp"].contains(mimeType)
      else { throw APIError.invalidResponse }
      guard http.expectedContentLength <= endpoint.maximumResponseBytes else {
        throw APIError.responseTooLarge
      }
      var data = Data()
      for try await byte in bytes {
        try Task.checkCancellation()
        guard data.count < endpoint.maximumResponseBytes else { throw APIError.responseTooLarge }
        data.append(byte)
      }
      try Task.checkCancellation()
      return try APIImage(data: data, mimeType: mimeType)
    } catch let error as APIError {
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

  /// 图片源仅作为后端代理的输入，拒绝非 HTTP(S)、凭据、片段和超长 URL。
  private static func isValidImageSource(_ url: URL) -> Bool {
    guard url.absoluteString.utf8.count <= 16_384,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = components.host, !host.isEmpty,
      components.user == nil, components.password == nil, components.fragment == nil
    else { return false }
    return true
  }

  /// 只投影状态码，不保留可能含有敏感数据的错误正文或 Location。
  private static func checkStatus(_ response: HTTPURLResponse) throws {
    switch response.statusCode {
    case 200..<300: break
    case 300..<400: throw APIError.redirectRefused
    case 401: throw APIError.unauthorized
    case 403: throw APIError.forbidden
    case 404: throw APIError.notFound
    case 429:
      throw APIError.rateLimited(
        retryAfter: retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
    default: throw APIError.httpStatus(response.statusCode)
    }
  }

  /// 接受标准秒数或 HTTP 日期；只供 UI 展示等待提示，客户端从不据此自动重发。
  public static func retryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
    guard let value else { return nil }
    if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
      let seconds = Double(value), seconds.isFinite
    {
      return seconds
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
    formatter.isLenient = false
    guard let date = formatter.date(from: value) else { return nil }
    return max(0, date.timeIntervalSince(now))
  }
}

/// 资源 Cookie 只从本客户端同源响应提取，只供固定图片端点使用；服务器仍验证签名。
private struct APIResourceCookie: Equatable, Sendable {
  let header: String
  let path: String
  let expires: Date
  let secure: Bool

  /// MoviePilot 以配置的项目名签发 host-only、HttpOnly JWT；拒绝外部域和其他 Cookie。
  init?(response: HTTPURLResponse) {
    guard let url = response.url, let host = url.host?.lowercased(),
      let raw = response.value(forHTTPHeaderField: "Set-Cookie"), raw.utf8.count <= 16_384,
      !raw.split(separator: ";").dropFirst().contains(where: {
        $0.split(separator: "=", maxSplits: 1).first?
          .trimmingCharacters(in: .whitespaces).lowercased() == "domain"
      })
    else { return nil }
    let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": raw], for: url)
    guard cookies.count == 1, let cookie = cookies.first, cookie.isHTTPOnly,
      cookie.domain.lowercased() == host,
      cookie.name == "MoviePilot",
      !cookie.name.isEmpty,
      cookie.name.utf8.allSatisfy({ Self.tokenByte($0) }),
      let expiration = Self.expiration(cookie.value), expiration > Date()
    else { return nil }
    header = "\(cookie.name)=\(cookie.value)"
    path = cookie.path
    expires = min(expiration, cookie.expiresDate ?? expiration)
    secure = cookie.isSecure
  }

  /// 暂存的作用域不能超过 Set-Cookie 声明，即使反向代理重写了 Path。
  func isValid(for url: URL) -> Bool {
    expires > Date() && (!secure || url.scheme == "https")
      && (url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/"))
  }

  /// Base64URL 字节集同时用于限制项目名与 JWT，不能把任何控制字符拼入请求头。
  private static func tokenByte(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
      || byte == 45 || byte == 95
  }

  /// 用声明区分资源/登录令牌并限制缓存寿命；这里不把 JWT 当作已验证的用户身份。
  private static func expiration(_ value: String) -> Date? {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy(tokenByte) })
    else { return nil }
    var payload = parts[1].replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.utf8.count % 4) % 4)
    guard let data = Data(base64Encoded: payload),
      let claims = try? JSONDecoder().decode(Claims.self, from: data), claims.purpose == "resource",
      claims.exp.isFinite
    else { return nil }
    return Date(timeIntervalSince1970: claims.exp)
  }

  /// 只读取期限和用途，不消费服务的身份、角色或权限声明。
  private struct Claims: Decodable {
    let purpose: String
    let exp: Double
  }
}

/// 每个 APIClient 独占的内存凭据；同一时间最多一个资源 Cookie 刷新请求。
private final class APIResourceCookieStore: @unchecked Sendable {
  private let lock = NSLock()
  private var cookie: APIResourceCookie?
  private var refresh: Task<Void, any Error>?
  private var active = true

  /// 只接受仍有效的新响应，避免并行旧响应缩短缓存寿命。
  func capture(_ value: APIResourceCookie) {
    lock.withLock {
      guard active, value.expires >= (cookie?.expires ?? .distantPast) else { return }
      cookie = value
    }
  }

  /// 资源 401 只清除实际使用的 Cookie；并行新响应已经签发的 Cookie 保留。
  func remove(_ value: APIResourceCookie) {
    lock.withLock { if cookie == value { cookie = nil } }
  }

  /// 会话取消同步销毁资源 Cookie 并阻止在途响应再次写入。
  func cancel() {
    lock.withLock {
      active = false
      cookie = nil
      refresh?.cancel()
      refresh = nil
    }
  }

  /// 优先复用被动取得的 Cookie；无可用 Cookie 时合并并行图片的续签读取。
  func resolve(for url: URL, refresh operation: @escaping @Sendable () async throws -> Void)
    async throws -> APIResourceCookie
  {
    let pending = try lock.withLock { () throws -> (APIResourceCookie?, Task<Void, any Error>?) in
      guard active else { throw CancellationError() }
      if let cookie, cookie.isValid(for: url) { return (cookie, nil) }
      if let refresh { return (nil, refresh) }
      let task = Task {
        defer { finishRefresh() }
        try await operation()
      }
      refresh = task
      return (nil, task)
    }
    if let cookie = pending.0 { return cookie }
    try await pending.1?.value
    try Task.checkCancellation()
    return try lock.withLock {
      guard active else { throw CancellationError() }
      guard let cookie, cookie.isValid(for: url) else { throw APIError.unauthorized }
      return cookie
    }
  }

  /// 无论续签结果如何都释放共享任务，后续请求可按当前会话状态重新获取。
  private func finishRefresh() { lock.withLock { refresh = nil } }
}

/// 内部响应不包含 URL、认证头或所有响应头，避免错误路径意外记录身份。
private struct APIHTTPResponse {
  let data: Data
  let statusCode: Int
  let collection: APICollectionMetadata
}

/// 通用 JSON API 不需要跟随重定向；媒体流等特例由专用客户端明确处理。
private final class APIRedirectGuard: NSObject, URLSessionTaskDelegate {
  /// 同源重定向也拒绝，避免把主令牌发送到未声明的端点路径。
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
