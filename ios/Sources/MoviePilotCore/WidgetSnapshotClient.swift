import Foundation

/// 固定失败原因不携带 HTTP 正文、服务器地址或任何凭据。
public enum WidgetClientError: Error, Equatable, Sendable {
  case unauthorized, forbidden, unsupported, unavailable, invalidData
}

/// 专用只读网络客户端，生命周期独立于主 App 的登录会话和网页 Cookie。
public final class WidgetSnapshotClient: WidgetSnapshotReading, WidgetGrantRevoking, Sendable {
  private let session: URLSession

  /// 生产始终采用私有 ephemeral 配置，扩展不读取系统凭据和 URLCache。
  public convenience init() { self.init(configuration: .ephemeral) }

  /// 测试只替换 HTTP 协议适配，保留实际请求构造、流式上限和身份校验。
  init(configuration: URLSessionConfiguration) {
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.httpAdditionalHeaders = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    configuration.waitsForConnectivity = false
    session = URLSession(
      configuration: configuration, delegate: WidgetRedirectGuard(), delegateQueue: nil)
  }

  /// 客户端销毁时取消本客户端拥有的请求，不影响网页及其它系统连接。
  deinit { session.invalidateAndCancel() }

  /// 只访问资料内固定 snapshot 端点，返回前按当前 owner 再次检查白名单模型。
  public func snapshot(profile: WidgetProfile, credential: String) async throws -> WidgetSnapshot {
    let data = try await request(
      profile: profile, credential: credential, method: "GET", endpoint: "snapshot",
      maximum: WidgetSnapshot.maximumBytes)
    return try WidgetSnapshot.decode(data, owner: profile.owner)
  }

  /// 使用同一专用 Bearer 撤销自身，没有登记 ID、主登录或续期入口。
  public func revoke(profile: WidgetProfile, credential: String) async throws {
    _ = try await request(
      profile: profile, credential: credential, method: "DELETE", endpoint: "registration",
      maximum: 2048)
  }

  /// 拒绝所有重定向，并在读取响应时限制大小；错误正文不离开本方法。
  private func request(
    profile: WidgetProfile, credential: String, method: String, endpoint: String, maximum: Int
  ) async throws -> Data {
    guard WidgetStore.validCredential(credential, registrationId: profile.registrationId),
      profile.credentialExpiresAt > Date().timeIntervalSince1970
    else { throw WidgetClientError.unauthorized }
    var request = URLRequest(
      url: profile.address.url.appendingPathComponent("api/v1/widget/\(endpoint)"),
      cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
    request.httpMethod = method
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpShouldHandleCookies = false
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let http = response as? HTTPURLResponse, http.url == request.url else {
      throw WidgetClientError.invalidData
    }
    switch http.statusCode {
    case 200, 204: break
    case 401: throw WidgetClientError.unauthorized
    case 403: throw WidgetClientError.forbidden
    case 404, 405: throw WidgetClientError.unsupported
    default: throw WidgetClientError.unavailable
    }
    guard response.expectedContentLength <= maximum else { throw WidgetDataError.oversizedData }
    if method == "GET", http.mimeType != "application/json" { throw WidgetClientError.invalidData }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximum else { throw WidgetDataError.oversizedData }
      data.append(byte)
    }
    return data
  }
}

/// 只拒绝跳转，不覆盖 TLS、证书或本地网络的系统安全判断。
private final class WidgetRedirectGuard: NSObject, URLSessionTaskDelegate {
  /// 即使同源重定向也不转发专用凭据到另一个路径或目的地。
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
