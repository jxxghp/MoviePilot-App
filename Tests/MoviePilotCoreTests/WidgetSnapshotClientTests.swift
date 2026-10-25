import Foundation
import Testing

@testable import MoviePilotCore

/// 通过真正 URLSession 和协议适配检验请求、响应边界；不访问外部网络。
@Suite(.serialized)
struct WidgetSnapshotClientTests {
  /// 配置中的旧头、Cookie 和主登录不应进入专用请求，路径保留实例基目录。
  @Test func usesOnlyDedicatedBearerAndFixedEndpoint() async throws {
    let profile = try WidgetTestData.profile()
    let data = try WidgetTestData.data(profile, at: Date())
    WidgetURLProtocol.state.prepare(body: data)
    let client = Self.client()
    let result = try await client.snapshot(
      profile: profile, credential: WidgetTestData.secret(profile))
    #expect(result.owner == profile.owner)
    let request = try #require(WidgetURLProtocol.state.requests().first)
    #expect(request.url == profile.snapshotURL)
    #expect(request.httpMethod == "GET")
    #expect(
      request.value(forHTTPHeaderField: "Authorization")
        == "Bearer \(WidgetTestData.secret(profile))")
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(request.value(forHTTPHeaderField: "X-Old-Session") == nil)
    #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    #expect(request.url?.query == nil && request.httpBody == nil)
    #expect(!String(decoding: try result.encoded(), as: UTF8.self).contains("synthetic-main-token"))
  }

  /// 身份不符的合法 JSON 也必须拒绝，不能把其它账号的快照保存下来。
  @Test func rejectsMismatchedOwner() async throws {
    let profile = try WidgetTestData.profile()
    let other = try WidgetTestData.profile(owner: String(repeating: "b", count: 32))
    WidgetURLProtocol.state.prepare(body: try WidgetTestData.data(other, at: Date()))
    await #expect(throws: WidgetDataError.ownerMismatch) {
      try await Self.client().snapshot(profile: profile, credential: WidgetTestData.secret(profile))
    }
  }

  /// 声明超限和无 Content-Length 的流式超限都在解码前失败。
  @Test func boundsDeclaredAndStreamedResponses() async throws {
    let profile = try WidgetTestData.profile()
    let secret = WidgetTestData.secret(profile)
    WidgetURLProtocol.state.prepare(
      body: Data(), headers: ["Content-Type": "application/json", "Content-Length": "32769"])
    await #expect(throws: WidgetDataError.oversizedData) {
      try await Self.client().snapshot(profile: profile, credential: secret)
    }
    WidgetURLProtocol.state.prepare(body: Data(repeating: 32, count: 32 * 1024 + 1))
    await #expect(throws: WidgetDataError.oversizedData) {
      try await Self.client().snapshot(profile: profile, credential: secret)
    }
    WidgetURLProtocol.state.prepare(
      body: Data("<html>secret</html>".utf8), headers: ["Content-Type": "text/html"])
    await #expect(throws: WidgetClientError.invalidData) {
      try await Self.client().snapshot(profile: profile, credential: secret)
    }
  }

  /// 有效 HTTP 失败映射为固定原因，不回显正文中的任何内容。
  @Test(arguments: [401, 403, 404, 405, 500])
  func projectsHTTPFailures(_ status: Int) async throws {
    let profile = try WidgetTestData.profile()
    WidgetURLProtocol.state.prepare(status: status, body: Data("private-error-body".utf8))
    let expected: WidgetClientError =
      status == 401
      ? .unauthorized
      : status == 403 ? .forbidden : [404, 405].contains(status) ? .unsupported : .unavailable
    await #expect(throws: expected) {
      try await Self.client().snapshot(profile: profile, credential: WidgetTestData.secret(profile))
    }
  }

  /// 任意主 JWT 或已经到期的资料在请求发出前被拒绝。
  @Test func rejectsWrongAndExpiredCredentialsBeforeNetworking() async throws {
    let profile = try WidgetTestData.profile()
    WidgetURLProtocol.state.prepare(body: Data())
    await #expect(throws: WidgetClientError.unauthorized) {
      try await Self.client().snapshot(profile: profile, credential: "main.jwt.token")
    }
    let old = try WidgetTestData.profile(now: Date().addingTimeInterval(-86_401))
    await #expect(throws: WidgetClientError.unauthorized) {
      try await Self.client().snapshot(profile: old, credential: WidgetTestData.secret(old))
    }
    #expect(WidgetURLProtocol.state.requests().isEmpty)
  }

  /// 自撤销仅访问单数固定资源，既不携带登记 ID，也不续期或调用普通 API。
  @Test func revokesOnlyItsOwnCredential() async throws {
    let profile = try WidgetTestData.profile()
    WidgetURLProtocol.state.prepare(status: 204, body: Data())
    try await Self.client().revoke(profile: profile, credential: WidgetTestData.secret(profile))
    let request = try #require(WidgetURLProtocol.state.requests().first)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path == "/moviepilot/api/v1/widget/registration")
    #expect(request.url?.query == nil && request.httpBody == nil)
  }

  /// 同源或跨源跳转都必须停在原响应，不能把凭据带到另一路径。
  @Test(arguments: ["https://other.example.test/target", "https://example.test/other"])
  func rejectsCredentialRedirects(_ destination: String) async throws {
    let profile = try WidgetTestData.profile()
    WidgetURLProtocol.state.prepare(status: 302, body: Data(), redirect: URL(string: destination))
    await #expect(throws: WidgetClientError.unavailable) {
      try await Self.client().snapshot(profile: profile, credential: WidgetTestData.secret(profile))
    }
    #expect(WidgetURLProtocol.state.requests().count == 1)
    #expect(WidgetURLProtocol.state.requests().first?.url == profile.snapshotURL)
  }

  /// 对照组证明协议夹具会真实跟随跳转，拒绝测试不是因为假响应自行终止。
  @Test func protocolFixtureFollowsRedirectWithoutTheGuard() async throws {
    let destination = try #require(URL(string: "https://example.test/other"))
    WidgetURLProtocol.state.prepare(
      status: 302, body: Data("synthetic".utf8), redirect: destination)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WidgetURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (_, response) = try await session.data(from: URL(string: "https://example.test/start")!)
    #expect(response.url == destination)
    #expect(WidgetURLProtocol.state.requests().count == 2)
  }

  /// 注入协议适配和故意污染的旧配置，生产客户端仍须清理所有共享状态。
  private static func client() -> WidgetSnapshotClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WidgetURLProtocol.self]
    configuration.httpAdditionalHeaders = ["Cookie": "old-session", "X-Old-Session": "main-token"]
    return WidgetSnapshotClient(configuration: configuration)
  }
}

/// 合成响应状态与请求记录全部受锁保护，串行测试之间不会保留授权头。
private final class WidgetURLState: @unchecked Sendable {
  private let lock = NSLock()
  private var reply = WidgetURLReply(status: 200, body: Data(), headers: [:], redirect: nil)
  private var captured: [URLRequest] = []

  /// 每个用例重置响应和全部捕获；只使用虚构域名及凭据。
  func prepare(
    status: Int = 200, body: Data, headers: [String: String] = ["Content-Type": "application/json"],
    redirect: URL? = nil
  ) {
    lock.withLock {
      reply = WidgetURLReply(status: status, body: body, headers: headers, redirect: redirect)
      captured = []
    }
  }

  /// URLSession 工作线程取得一致响应，并在同一临界区记录请求事实。
  func answer(_ request: URLRequest) -> WidgetURLReply {
    lock.withLock {
      captured.append(request)
      if request.url == reply.redirect {
        return WidgetURLReply(status: 200, body: reply.body, headers: reply.headers, redirect: nil)
      }
      return reply
    }
  }

  /// 仅供本序列化测试检查，不将这些合成请求写到产品日志。
  func requests() -> [URLRequest] { lock.withLock { captured } }
}

/// 合成协议回答没有异步共享可变字段。
private struct WidgetURLReply: Sendable {
  let status: Int
  let body: Data
  let headers: [String: String]
  let redirect: URL?
}

/// 拦截测试 session 的所有请求，错误实现也不会访问真实外网。
private final class WidgetURLProtocol: URLProtocol, @unchecked Sendable {
  static let state = WidgetURLState()

  /// 所有测试来源都在本进程处理，以便发现意外的第二次跳转。
  override class func canInit(with request: URLRequest) -> Bool { true }

  /// 保留真实生产 URL 和请求头，不在测试适配中修正实现。
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  /// 通过系统协议回调交付响应，重定向仍交给 URLSessionTaskDelegate 裁决。
  override func startLoading() {
    let reply = Self.state.answer(request)
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else {
      client?.urlProtocol(self, didFailWithError: WidgetClientError.invalidData)
      return
    }
    if let redirect = reply.redirect {
      var target = request
      target.url = redirect
      client?.urlProtocol(self, wasRedirectedTo: target, redirectResponse: response)
    }
    // 跳转被 delegate 拒绝后，原响应仍须结束；只发 wasRedirectedTo 会制造悬空的假请求。
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  /// 回答同步完成，取消不拥有其它计时器或脱离测试的任务。
  override func stopLoading() {}
}
