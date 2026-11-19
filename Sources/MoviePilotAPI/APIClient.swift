import Foundation
import MoviePilotCore

/// 原生主体的私有 JSON 客户端；一个实例/身份会话拥有一个客户端，不依赖网页状态。
public final class APIClient: Sendable {
  private let address: ServerAddress
  private let token: String?
  private let language: AppLanguage
  private let session: URLSession

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
  }

  /// 释放当前客户端拥有的任务，不影响其它实例、Widget 或插件容器的网络。
  deinit { session.invalidateAndCancel() }

  /// 结束会话时取消所有未完成任务；后续登录必须创建新客户端。
  public func cancel() { session.invalidateAndCancel() }

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
