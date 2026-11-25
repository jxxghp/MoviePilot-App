import Foundation
import MoviePilotCore
import Testing

@testable import MoviePilotAPI

/// 固定实例与端点的 URL 边界，避免代理子路径、动态标识和查询相互污染。
struct APIEndpointTests {
  /// 查询中的 URL 特殊字符只能作为值出现，重复参数与实例部署前缀都保持原样。
  @Test func preservesDeploymentPrefixAndQueryValues() throws {
    let address = try ServerAddress("https://EXAMPLE.test:443/moviepilot/")
    let query = [
      URLQueryItem(name: "keyword", value: "甲 +&?=#/"),
      URLQueryItem(name: "site", value: "1"), URLQueryItem(name: "site", value: "2"),
    ]
    let endpoint = try APIEndpoint(path: ["search", "media"], query: query)
    let url = try endpoint.url(for: address)
    #expect(url.path == "/moviepilot/api/v1/search/media")
    #expect(url.host == "example.test" && url.fragment == nil && url.user == nil)
    let encoded = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
    #expect(encoded.contains("%2B") && !encoded.contains("+"))
    // 独立按服务端查询的 form 解码顺序检查，不能只做 URLComponents 自身往返。
    let received = encoded.components(separatedBy: "&").compactMap { field -> URLQueryItem? in
      let pair = field.components(separatedBy: "=")
      guard pair.count == 2,
        let name = pair[0].replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
        let value = pair[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding
      else { return nil }
      return URLQueryItem(name: name, value: value)
    }
    #expect(received == query)
  }

  /// IPv6 与 Unicode 标识不依赖绝对 URL，也不需要重定向修正集合尾斜杠。
  @Test func handlesIPv6IdentifiersAndTrailingSlash() throws {
    let address = try ServerAddress("http://[::1]:5301/base")
    let identifier = try APIEndpoint(path: ["plugin", "工具_clone-1"])
    #expect(try identifier.url(for: address).path == "/base/api/v1/plugin/工具_clone-1")
    let collection = try APIEndpoint(path: ["plugin"], trailingSlash: true)
    #expect(
      try collection.url(for: address).absoluteString == "http://[::1]:5301/base/api/v1/plugin/")
  }

  /// 双重转义、分隔符和完整 URL 都不能成为路径段，禁止绕出 api/v1。
  @Test(arguments: [
    "", ".", "..", "../user", "/user", "//other.test", "https://other.test/path",
    "%2e%2e", "%252f", "a\\b", "a?token=x", "a#x", "a;b", "a\u{0}b",
  ])
  func rejectsEscapingPathSegments(_ segment: String) {
    #expect(throws: APIError.invalidEndpoint) { try APIEndpoint(path: ["plugin", segment]) }
  }

  /// 不允许给 GET/HEAD 夹带 JSON 或通过非有限超时、无界响应配置绕过传输限制。
  @Test func rejectsInvalidRequestConfiguration() {
    #expect(throws: APIError.invalidEndpoint) { try APIEndpoint(path: []) }
    #expect(throws: APIError.invalidEndpoint) {
      try APIEndpoint(path: ["user"], body: Data("{}".utf8))
    }
    #expect(throws: APIError.invalidEndpoint) {
      try APIEndpoint(path: ["user"], method: .head, body: Data("{}".utf8))
    }
    #expect(throws: APIError.invalidEndpoint) {
      try APIEndpoint(path: ["user"], maximumResponseBytes: 0)
    }
    #expect(throws: APIError.invalidEndpoint) {
      try APIEndpoint(path: ["user"], maximumResponseBytes: 16 * 1024 * 1024 + 1)
    }
    #expect(throws: APIError.invalidEndpoint) {
      try APIEndpoint(path: ["user"], timeout: .infinity)
    }
  }

  /// Retry-After 日期与整数均保留等待语义，无效值不被猜成可以立即重发。
  @Test func parsesRetryAfterWithoutSchedulingRetries() {
    let reference = Date(timeIntervalSince1970: 784_111_777)
    #expect(APIClient.retryAfter("120", now: reference) == 120)
    #expect(APIClient.retryAfter("Sun, 06 Nov 1994 08:51:37 GMT", now: reference) == 120)
    #expect(APIClient.retryAfter("Sun, 06 Nov 1994 08:47:37 GMT", now: reference) == 0)
    #expect(APIClient.retryAfter("-1", now: reference) == nil)
    #expect(APIClient.retryAfter("soon", now: reference) == nil)
    #expect(APIClient.retryAfter(nil, now: reference) == nil)
  }
}
