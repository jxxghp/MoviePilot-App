import Foundation
import MoviePilotCore

/// 仅描述实例 api/v1 下的相对端点；路径段和查询值各自编码，不能接受任意 URL。
public struct APIEndpoint: Sendable {
  public let path: [String]
  public let method: APIMethod
  public let query: [URLQueryItem]
  public let body: Data?
  public let responseContract: APIResponseContract
  public let maximumResponseBytes: Int
  public let timeout: TimeInterval
  public let trailingSlash: Bool

  /// 限制路径、JSON 请求体、超时和响应上限；文件、媒体和 SSE 应使用专用传输。
  public init(
    path: [String], method: APIMethod = .get, query: [URLQueryItem] = [],
    body: Data? = nil, responseContract: APIResponseContract = .envelope,
    maximumResponseBytes: Int = 4 * 1024 * 1024, timeout: TimeInterval = 20,
    trailingSlash: Bool = false
  ) throws {
    guard !path.isEmpty, path.count <= 64, path.allSatisfy(Self.validSegment),
      (1...16 * 1024 * 1024).contains(maximumResponseBytes),
      timeout.isFinite, timeout > 0, timeout <= 120,
      body.map({ $0.count <= 16 * 1024 * 1024 }) ?? true,
      body == nil || method != .get && method != .head
    else { throw APIError.invalidEndpoint }
    self.path = path
    self.method = method
    self.query = query
    self.body = body
    self.responseContract = responseContract
    self.maximumResponseBytes = maximumResponseBytes
    self.timeout = timeout
    self.trailingSlash = trailingSlash
  }

  /// 保留反向代理部署前缀及显式尾斜杠，不依赖携带认证的重定向修正路径。
  public func url(for address: ServerAddress) throws -> URL {
    var url = address.url.appendingPathComponent("api", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true)
    for segment in path { url.appendPathComponent(segment, isDirectory: false) }
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw APIError.invalidEndpoint
    }
    if trailingSlash { components.percentEncodedPath += "/" }
    components.queryItems = query.isEmpty ? nil : query
    // URLComponents 允许查询值保留 "+"，但后端表单式查询解码会把它当空格。
    if let encoded = components.percentEncodedQuery {
      components.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
    }
    guard let result = components.url, address.contains(result) else {
      throw APIError.invalidEndpoint
    }
    return result
  }

  /// 路径只容纳普通标识符；拒绝 URL、分隔符和二次解码，文件路径与自由文本用查询或 JSON。
  private static func validSegment(_ value: String) -> Bool {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return !value.isEmpty && value.utf8.count <= 1024 && value != "." && value != ".."
      && value.unicodeScalars.allSatisfy { allowed.contains($0) }
  }
}
