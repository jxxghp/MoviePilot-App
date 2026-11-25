import Foundation
import MoviePilotCore
import Testing

@testable import MoviePilotAPI

/// 使用实际 URLSession 与受控协议检查传输边界；所有域名和凭据均为合成值。
@Suite(.serialized)
struct APIClientTests {
  /// payload Data 逐字节保留数值/空白/未知字段，不猜测与标准响应同名的业务键。
  @Test func preservesOriginalPayloadBytesAndMetadata() async throws {
    let body = Data(" {\"success\":false,\"data\":9007199254740993,\"decimal\":1.2300} \n".utf8)
    APIURLProtocol.state.prepare(
      body: body, headers: ["Content-Type": "application/json", "X-Total-Count": "5"])
    let response = try await Self.client().requestPayload(
      APIEndpoint(path: ["plugin", "form", "Example_2"], responseContract: .payload))
    #expect(response.value == body && response.statusCode == 200)
    #expect(response.collection.totalCount == 5)
    #expect(
      APIURLProtocol.state.requests().first?.request.url?.path.hasSuffix("/plugin/form/Example_2")
        == true)
  }

  /// 标准包装不能用原始字节接口绕过业务失败检查，拒绝发生在网络请求之前。
  @Test func rawProjectionRequiresExplicitPayloadContract() async throws {
    APIURLProtocol.state.prepare(body: Data())
    await #expect(throws: APIError.invalidEndpoint) {
      try await Self.client().requestPayload(APIEndpoint(path: ["plugin", "Example"]))
    }
    #expect(APIURLProtocol.state.requests().isEmpty)
  }

  /// 原始响应仍受流式上限、MIME 与 HTTP 身份失败控制，不自动重发。
  @Test func rawProjectionRetainsTransportGuards() async throws {
    let endpoint = try APIEndpoint(
      path: ["plugin"], responseContract: .payload, maximumResponseBytes: 4)
    APIURLProtocol.state.prepare(body: Data("12345".utf8))
    await #expect(throws: APIError.responseTooLarge) {
      try await Self.client().requestPayload(endpoint)
    }
    #expect(APIURLProtocol.state.requests().count == 1)
    APIURLProtocol.state.prepare(body: Data("{}".utf8), headers: ["Content-Type": "text/html"])
    await #expect(throws: APIError.invalidResponse) {
      try await Self.client().requestPayload(endpoint)
    }
    APIURLProtocol.state.prepare(status: 401, body: Data())
    await #expect(throws: APIError.unauthorized) {
      try await Self.client().requestPayload(endpoint)
    }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 原始字节请求的在途取消仍结束同一个 URLSession 任务。
  @Test func cancelsRawProjection() async throws {
    APIURLProtocol.state.prepare(body: Data(), hold: true)
    let client = try Self.client()
    let endpoint = try APIEndpoint(path: ["plugin"], responseContract: .payload)
    let task = Task { try await client.requestPayload(endpoint) }
    for _ in 0..<200 {
      if !APIURLProtocol.state.requests().isEmpty { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!APIURLProtocol.state.requests().isEmpty)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 首次取图使用固定读取取得资源 Cookie；图片代理请求仅使用该 Cookie。
  @Test func requestsAuthenticatedSameOriginImageProxy() async throws {
    let cookie = try Self.resourceCookie()
    APIURLProtocol.state.prepare(
      body: Data([0x89, 0x50]), headers: ["Content-Type": "image/png"],
      refreshCookie: "\(cookie); Path=/; HttpOnly; Secure; SameSite=Lax")
    let source = try #require(URL(string: "https://images.example/poster?q=a+b&size=2"))
    let image = try await Self.client().requestImage(source, maximumWidth: 420)
    #expect(image.data == Data([0x89, 0x50]) && image.mimeType == "image/png")
    let requests = APIURLProtocol.state.requests().map(\.request)
    let refresh = try #require(requests.first)
    let captured = try #require(requests.last)
    #expect(refresh.url?.path == "/moviepilot/api/v1/media/source")
    #expect(refresh.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic.token")
    #expect(refresh.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(captured.url?.host == "example.test")
    #expect(captured.url?.path == "/moviepilot/api/v1/system/img/0")
    let capturedURL = try #require(captured.url)
    let components = try #require(
      URLComponents(url: capturedURL, resolvingAgainstBaseURL: false))
    let query = try #require(components.queryItems)
    #expect(query.first(where: { $0.name == "imgurl" })?.value == source.absoluteString)
    #expect(query.first(where: { $0.name == "cache" })?.value == "false")
    #expect(query.first(where: { $0.name == "maxWidth" })?.value == "420")
    #expect(captured.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(captured.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    #expect(
      captured.value(forHTTPHeaderField: "Accept")
        == "image/avif, image/webp, image/apng, image/jpeg, image/png, image/*;q=0.8")
    #expect(captured.value(forHTTPHeaderField: "Cookie") == cookie)
    #expect(requests.count == 2)
  }

  /// 服务端代理返回 AVIF / GIF / HEIC 等合法图片格式时均应放行，仍严格拒绝 SVG 脚本载体与非图片类型。
  @Test func acceptsAvifAndModernImageMimeTypesWhileRejectingSvg() async throws {
    let cookie = try Self.resourceCookie()
    let source = try #require(URL(string: "https://images.example/poster.avif"))
    for (headerType, expectedMime) in [
      ("image/avif", "image/avif"),
      ("image/avif; charset=binary", "image/avif"),
      ("image/gif", "image/gif"),
      ("image/heic", "image/heic"),
      ("image/webp", "image/webp"),
    ] {
      APIURLProtocol.state.prepare(
        body: Data([0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70]),
        headers: ["Content-Type": headerType],
        refreshCookie: "\(cookie); Path=/; HttpOnly; Secure; SameSite=Lax")
      let image = try await Self.client().requestImage(source)
      #expect(image.mimeType == expectedMime)
      #expect(!image.data.isEmpty)
    }

    for rejectedType in ["image/svg+xml", "image/svg+xml; charset=utf-8", "text/html", "application/json"] {
      APIURLProtocol.state.prepare(
        body: Data("<svg></svg>".utf8),
        headers: ["Content-Type": rejectedType],
        refreshCookie: "\(cookie); Path=/; HttpOnly; Secure; SameSite=Lax")
      await #expect(throws: APIError.invalidResponse) {
        _ = try await Self.client().requestImage(source)
      }
    }
  }

  /// Foundation 可能把多行 Set-Cookie 合成一个值；两个顺序都只把资源凭据送往图片代理。
  @Test func acceptsExactlyOneResourceCookieAmongCombinedSetCookies() async throws {
    let resource = try Self.resourceCookie()
    let resourceHeader =
      "\(resource); Path=/; HttpOnly; Secure; Expires=Wed, 01 Jan 2050 00:00:00 GMT"
    let edgeHeader =
      "acw_tc=synthetic; Path=/; Domain=example.test; Expires=Wed, 01 Jan 2050 00:00:00 GMT"
    let secondEdgeHeader = "cdn_sec_tc=synthetic; Path=/; HttpOnly; Secure"
    let source = try #require(URL(string: "https://images.example/poster.png"))
    for value in [
      [resourceHeader, edgeHeader, secondEdgeHeader].joined(separator: ", "),
      [edgeHeader, secondEdgeHeader, resourceHeader].joined(separator: ","),
    ] {
      APIURLProtocol.state.prepare(
        body: Data([0x89, 0x50]), headers: ["Content-Type": "image/png"], refreshCookie: value)
      let image = try await Self.client().requestImage(source)
      let requests = APIURLProtocol.state.requests().map(\.request)
      #expect(image.data == Data([0x89, 0x50]))
      #expect(requests.count == 2)
      #expect(requests.last?.url?.path.hasSuffix("/system/img/0") == true)
      #expect(requests.last?.value(forHTTPHeaderField: "Cookie") == resource)
      #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }
  }

  /// 无精确匹配、同名重复或资源凭据声明 Domain 时均不发送图片请求。
  @Test func rejectsMissingDuplicateOrDomainResourceCookieInCombinedHeader() async throws {
    let resource = try Self.resourceCookie()
    let lowercaseResource = try Self.resourceCookie(name: "moviepilot")
    let valid = "\(resource); Path=/; HttpOnly; Secure"
    let edge = "acw_tc=synthetic; HttpOnly; Path=/"
    let source = try #require(URL(string: "https://images.example/poster.png"))
    for value in [
      "\(edge), \(lowercaseResource); Path=/; HttpOnly",
      "\(valid), \(edge), \(valid)",
      "\(valid), \(edge), \(valid); Domain=outside.test",
      "\(edge), \(valid); DoMaIn = example.test",
      "\(edge), \(resource); Path=/other; HttpOnly",
      "\(edge), \(resource); Path=/; HttpOnly; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
      "acw_tc=\"synthetic, \(valid)\"",
    ] {
      APIURLProtocol.state.prepare(body: Data(), refreshCookie: value)
      await #expect(throws: APIError.unauthorized) { try await Self.client().requestImage(source) }
      let requests = APIURLProtocol.state.requests().map(\.request)
      #expect(requests.count == 1 && requests.first?.url?.path.hasSuffix("/media/source") == true)
    }
  }

  /// 普通 GET 只读取资源 Cookie，不发送它；同源新客户端也不能复用另一个会话的 Cookie。
  @Test func scopesResourceCookieToTheClientAndImageEndpoint() async throws {
    let cookie = try Self.resourceCookie()
    let first = try await Self.clientWithResourceCookie(cookie: cookie)
    let second = try Self.client(token: "synthetic.second")
    let source = try #require(URL(string: "https://images.example/poster.png"))
    APIURLProtocol.state.prepare(
      body: Data([0x89, 0x50]), headers: ["Content-Type": "image/png"])
    _ = try await first.requestImage(source)
    let imageRequest = try #require(APIURLProtocol.state.requests().first?.request)
    #expect(imageRequest.value(forHTTPHeaderField: "Cookie") == cookie)
    #expect(APIURLProtocol.state.requests().count == 1)

    APIURLProtocol.state.prepare(body: Data(#"{"success":true,"message":"","data":[]}"#.utf8))
    _ = try await first.request(APIEndpoint(path: ["media", "source"]), as: [JSONValue].self)
    await #expect(throws: APIError.unauthorized) { try await second.requestImage(source) }
    let requests = APIURLProtocol.state.requests().map(\.request)
    #expect(requests.count == 2)
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == nil })
    #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic.second")
  }

  /// 资源 Cookie 不接受其它用途、共享域或非 HttpOnly 响应，取图失败不会发送认证令牌。
  @Test func rejectsUnscopedOrUnusableResourceCookies() async throws {
    let cookie = try Self.resourceCookie()
    let access = try Self.resourceCookie(purpose: "authentication")
    let expired = try Self.resourceCookie(expiration: 1)
    let source = try #require(URL(string: "https://images.example/poster.png"))
    for value in [
      "\(cookie); Path=/; HttpOnly; Domain=example.test",
      "\(cookie); Path=/; HttpOnly; Domain=outside.test",
      "\(cookie); Path=/",
      "\(cookie); Path=/other; HttpOnly",
      "\(access); Path=/; HttpOnly",
      "\(expired); Path=/; HttpOnly",
    ] {
      APIURLProtocol.state.prepare(body: Data(), refreshCookie: value)
      await #expect(throws: APIError.unauthorized) { try await Self.client().requestImage(source) }
      let requests = APIURLProtocol.state.requests().map(\.request)
      #expect(requests.count == 1 && requests.first?.url?.path.hasSuffix("/media/source") == true)
    }
  }

  /// 图片源与缩放参数在请求前校验，不会把令牌发给非 HTTP(S) 或含凭据来源。
  @Test func rejectsUnsafeImageSourcesBeforeRequest() async throws {
    APIURLProtocol.state.prepare(body: Data())
    for value in [
      "file:///private/poster.png", "https://reader:secret@images.example/poster.jpg",
      "https://images.example/poster.jpg#fragment",
    ] {
      let source = try #require(URL(string: value))
      await #expect(throws: APIError.invalidEndpoint) {
        try await Self.client().requestImage(source)
      }
    }
    let source = try #require(URL(string: "https://images.example/poster.jpg"))
    await #expect(throws: APIError.invalidEndpoint) {
      try await Self.client().requestImage(source, maximumWidth: 2049)
    }
    let unauthenticated = try Self.client(token: nil)
    await #expect(throws: APIError.invalidCredential) {
      try await unauthenticated.requestImage(source)
    }
    #expect(APIURLProtocol.state.requests().isEmpty)
  }

  /// 只接受明确的 JPEG、PNG、WebP 响应类型，拒绝 SVG、HTML 与伪装 JSON。
  @Test func rejectsNonRasterAndUnlistedImageMimeTypes() async throws {
    let source = try #require(URL(string: "https://images.example/poster.jpg"))
    let client = try await Self.clientWithResourceCookie()
    for mime in ["image/svg+xml", "text/html", "application/json"] {
      APIURLProtocol.state.prepare(body: Data("<svg/>".utf8), headers: ["Content-Type": mime])
      await #expect(throws: APIError.invalidResponse) {
        try await client.requestImage(source)
      }
      #expect(APIURLProtocol.state.requests().count == 1)
    }
  }

  /// 响应体超出 8 MiB 时在流式读取过程中拒绝，且不缓存或重试大图。
  @Test func enforcesImageResponseByteLimit() async throws {
    let source = try #require(URL(string: "https://images.example/poster.jpg"))
    let client = try await Self.clientWithResourceCookie()
    APIURLProtocol.state.prepare(
      body: Data(repeating: 0, count: APIImage.maximumBytes + 1),
      headers: ["Content-Type": "image/jpeg"])
    await #expect(throws: APIError.responseTooLarge) {
      try await client.requestImage(source)
    }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 图片代理的重定向被拒绝，避免将资源 Cookie 带到第二个路径或来源。
  @Test func refusesImageProxyRedirects() async throws {
    let source = try #require(URL(string: "https://images.example/poster.jpg"))
    let client = try await Self.clientWithResourceCookie()
    APIURLProtocol.state.prepare(
      status: 307, body: Data([0xFF, 0xD8]), headers: ["Content-Type": "image/jpeg"],
      redirect: URL(string: "https://redirect.example/leak"))
    await #expect(throws: APIError.redirectRefused) {
      try await client.requestImage(source)
    }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 挂起的图片请求在调用方取消时终止，响应迟到前不交付图片数据。
  @Test func cancelsImageProjection() async throws {
    let client = try await Self.clientWithResourceCookie()
    APIURLProtocol.state.prepare(body: Data(), headers: ["Content-Type": "image/png"], hold: true)
    let source = try #require(URL(string: "https://images.example/poster.png"))
    let task = Task { try await client.requestImage(source) }
    for _ in 0..<200 {
      if !APIURLProtocol.state.requests().isEmpty { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!APIURLProtocol.state.requests().isEmpty)
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 合成 JWT 只模拟后端 Cookie 的传输形状，不含真实签名或身份。
  private static func resourceCookie(
    name: String = "MoviePilot", purpose: String = "resource", expiration: Int = 4_102_444_800
  ) throws -> String {
    let payload = try JSONEncoder().encode([
      "purpose": JSONValue.string(purpose), "exp": .number(Double(expiration)),
    ])
    .base64EncodedString().replacingOccurrences(of: "=", with: "")
    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return "\(name)=test.\(payload).signature"
  }

  /// 用普通同源 API 响应引入 Cookie，不绕过产品解析或直接注入缓存。
  private static func clientWithResourceCookie(cookie: String? = nil) async throws -> APIClient {
    let header = try cookie ?? resourceCookie()
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":true,"message":"","data":[]}"#.utf8),
      headers: [
        "Content-Type": "application/json", "Set-Cookie": "\(header); Path=/; HttpOnly; Secure",
      ])
    let client = try Self.client()
    _ = try await client.request(
      APIEndpoint(path: ["discover", "tmdb_movies"]), as: [JSONValue].self)
    return client
  }

  /// 两个独立客户端只带各自令牌；配置中残留的 Cookie、附加头和凭据存储不能继承。
  @Test func isolatesIdentityAndRetainsCollectionMetadata() async throws {
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":true,"message":"","data":[1,2]}"#.utf8),
      headers: [
        "Content-Type": "application/json", "X-Total-Count": "7", "X-Result-Count": "2",
        "X-Page": "2", "X-Page-Size": "2", "Set-Cookie": "shared=must-not-be-used",
      ])
    let first = try Self.client(token: "synthetic.token.a", language: .traditionalChinese)
    let second = try Self.client(address: "https://second.test/root/", token: "synthetic.token.b")
    let endpoint = try APIEndpoint(
      path: ["plugin"], query: [URLQueryItem(name: "page", value: "2")], trailingSlash: true)
    let result = try await first.request(endpoint, as: [Int].self)
    _ = try await second.request(endpoint, as: [Int].self)
    _ = try await first.request(endpoint, as: [Int].self)
    #expect(result.value == [1, 2] && result.statusCode == 200)
    #expect(result.collection.totalCount == 7 && result.collection.resultCount == 2)
    #expect(result.collection.page == 2 && result.collection.pageSize == 2)
    let captured = APIURLProtocol.state.requests()
    #expect(captured.count == 3)
    #expect(
      captured.map { $0.request.value(forHTTPHeaderField: "Authorization") } == [
        "Bearer synthetic.token.a", "Bearer synthetic.token.b", "Bearer synthetic.token.a",
      ])
    let firstURL = try #require(captured.first?.request.url)
    // URL.path 会规范化目录尾斜杠；检查实际编码路径才能证明请求不会依赖 307 修正。
    #expect(
      URLComponents(url: firstURL, resolvingAgainstBaseURL: false)?.percentEncodedPath
        == "/moviepilot/api/v1/plugin/")
    #expect(captured[1].request.url?.host == "second.test")
    #expect(captured.first?.request.value(forHTTPHeaderField: "X-MoviePilot-Locale") == "zh-TW")
    for item in captured {
      #expect(item.request.value(forHTTPHeaderField: "Cookie") == nil)
      #expect(item.request.value(forHTTPHeaderField: "X-Old-Session") == nil)
      #expect(item.request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
      #expect(item.request.httpShouldHandleCookies == false)
    }
  }

  /// 普通写入保持原 JSON 字节并只发送一次，success=false 不会被视为已完成。
  @Test func sendsJSONAndDoesNotReplayRejectedWrites() async throws {
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":false,"message":"synthetic-private-message","data":null}"#.utf8))
    let data = Data(#"{"enabled":true,"unknown_key":[1,"2",false]}"#.utf8)
    let endpoint = try APIEndpoint(path: ["plugin", "Example_clone"], method: .put, body: data)
    await #expect(throws: APIError.businessFailure) {
      try await Self.client().perform(endpoint)
    }
    let requests = APIURLProtocol.state.requests()
    #expect(requests.count == 1)
    #expect(requests.first?.request.httpMethod == "PUT")
    #expect(
      requests.first?.request.value(forHTTPHeaderField: "Content-Type")
        == "application/json; charset=utf-8")
    #expect(requests.first?.body == data)
    #expect(!String(describing: APIError.businessFailure).contains("synthetic-private-message"))
  }

  /// 插件自有 success/data 不被误拆包或升级为宿主错误，标准契约仍要求显式 envelope。
  @Test func keepsPluginPayloadSeparateFromHostEnvelope() async throws {
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":false,"message":"plugin-defined","data":{"state":"pending"}}"#.utf8))
    let endpoint = try APIEndpoint(
      path: ["plugin", "Example", "state"], responseContract: .payload)
    let result = try await Self.client().request(endpoint, as: JSONValue.self)
    #expect(
      result.value
        == .object([
          "success": .bool(false), "message": .string("plugin-defined"),
          "data": .object(["state": .string("pending")]),
        ]))
    #expect(result.collection.totalCount == nil && result.collection.page == nil)
    APIURLProtocol.state.prepare(body: Data(#"{"id":1}"#.utf8))
    await #expect(throws: APIError.invalidResponse) {
      try await Self.client().request(APIEndpoint(path: ["user", "current"]), as: JSONValue.self)
    }
  }

  /// 业务错误先于成功数据解码，无法解析的 HTML、JSON 或错误包装均不会返回假数据。
  @Test func distinguishesBusinessAndProtocolFailures() async throws {
    let endpoint = try APIEndpoint(path: ["user", "current"])
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":false,"message":"rejected","data":["not-an-integer"]}"#.utf8))
    await #expect(throws: APIError.businessFailure) {
      try await Self.client().request(endpoint, as: Int.self)
    }
    for body in [
      "<html>login page</html>", "{}", #"{"success":1,"message":"","data":3}"#,
      #"{"success":true,"data":3}"#,
    ] {
      APIURLProtocol.state.prepare(body: Data(body.utf8))
      await #expect(throws: APIError.invalidResponse) {
        try await Self.client().request(endpoint, as: Int.self)
      }
    }
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":true,"message":"","data":null}"#.utf8))
    let result = try await Self.client().request(endpoint, as: Int?.self)
    #expect(result.value == nil)
  }

  /// 无正文动作与标准 data=null 动作分别验证；HTTP 200 的空正文不能冒充成功包装。
  @Test func validatesAcknowledgementsAndNoContent() async throws {
    let endpoint = try APIEndpoint(path: ["plugin", "Example"], method: .delete)
    APIURLProtocol.state.prepare(status: 204, body: Data(), headers: [:])
    try await Self.client().perform(endpoint)
    APIURLProtocol.state.prepare(body: Data(#"{"success":true,"message":"","data":null}"#.utf8))
    try await Self.client().perform(endpoint)
    APIURLProtocol.state.prepare(body: Data())
    await #expect(throws: APIError.invalidResponse) { try await Self.client().perform(endpoint) }
  }

  /// 声明超限和无长度的流式超限都必须拒绝；精确等于上限的正文仍可正常解码。
  @Test func boundsDeclaredAndStreamingResponses() async throws {
    let endpoint = try APIEndpoint(
      path: ["plugin"], responseContract: .payload, maximumResponseBytes: 8)
    APIURLProtocol.state.prepare(
      body: Data(), headers: ["Content-Type": "application/json", "Content-Length": "9"])
    await #expect(throws: APIError.responseTooLarge) {
      try await Self.client().request(endpoint, as: [Int].self)
    }
    APIURLProtocol.state.prepare(body: Data(repeating: 32, count: 9))
    await #expect(throws: APIError.responseTooLarge) {
      try await Self.client().request(endpoint, as: [Int].self)
    }
    APIURLProtocol.state.prepare(body: Data("[1,2]   ".utf8))
    let result = try await Self.client().request(endpoint, as: [Int].self)
    #expect(result.value == [1, 2])
    APIURLProtocol.state.prepare(
      body: Data("[]".utf8), headers: ["Content-Type": "text/html"])
    await #expect(throws: APIError.invalidResponse) {
      try await Self.client().request(endpoint, as: [Int].self)
    }
    APIURLProtocol.state.prepare(
      body: Data("<!DOCTYPE html><html><title>Sign in · Cloudflare Access</title></html>".utf8),
      headers: ["Content-Type": "text/html; charset=utf-8"])
    await #expect(throws: APIError.cloudflareAccessRequired) {
      try await Self.client().request(endpoint, as: [Int].self)
    }
  }

  /// 负页码、溢出、非整数和零窗口不能静默变成“没有更多数据”；同时兼容后端 0 基分页接口的 `X-Page: 0`。
  @Test(arguments: [
    ["X-Page": "-1"], ["X-Page-Size": "0"], ["X-Total-Count": "-1"],
    ["X-Result-Count": "2.0"], ["X-Total-Count": String(repeating: "9", count: 80)],
  ])
  func rejectsMalformedCollectionHeaders(_ fields: [String: String]) async throws {
    var headers = fields
    headers["Content-Type"] = "application/json"
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":true,"message":"","data":[]}"#.utf8), headers: headers)
    await #expect(throws: APIError.invalidResponse) {
      try await Self.client().request(APIEndpoint(path: ["plugin"]), as: [Int].self)
    }
  }

  /// 站点资源浏览与模糊搜索采用 0 基分页，后端返回 `X-Page: 0` 时应正常解析并保留集合元数据。
  @Test func acceptsZeroBasedCollectionPageHeader() async throws {
    APIURLProtocol.state.prepare(
      body: Data(#"{"success":true,"message":"","data":[1,2]}"#.utf8),
      headers: [
        "Content-Type": "application/json",
        "X-Page": "0",
        "X-Result-Count": "2",
      ])
    let result = try await Self.client().request(
      APIEndpoint(
        path: ["site", "resource", "1"], query: [URLQueryItem(name: "page", value: "0")]),
      as: [Int].self)
    #expect(result.value == [1, 2])
    #expect(result.collection.page == 0)
    #expect(result.collection.resultCount == 2)
  }

  /// HTTP 失败只投影安全分类；包括旧 GET 动作在内，收到限流或失败都不重发。
  @Test(arguments: [401, 403, 404, 409, 429, 500, 503])
  func projectsHTTPFailuresWithoutReplaying(_ status: Int) async throws {
    APIURLProtocol.state.prepare(
      status: status, body: Data("synthetic-private-error-body".utf8),
      headers: ["Retry-After": "120"])
    let expected: APIError =
      switch status {
      case 401: .unauthorized
      case 403: .forbidden
      case 404: .notFound
      case 429: .rateLimited(retryAfter: 120)
      default: .httpStatus(status)
      }
    await #expect(throws: expected) {
      try await Self.client().perform(APIEndpoint(path: ["system", "runscheduler"]))
    }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 后端重启后若旧版服务端以 HTTP 403 返回令牌校验失败，投影为 `.unauthorized` 以立即退出登录；常规权限 403 仍保持 `.forbidden`。
  @Test func classifiesTokenRejectedForbiddenAsUnauthorizedWithoutAffectingRBAC() async throws {
    APIURLProtocol.state.prepare(
      status: 403, body: Data(#"{"detail":"token校验不通过"}"#.utf8),
      headers: ["Content-Type": "application/json"])
    await #expect(throws: APIError.unauthorized) {
      try await Self.client().perform(APIEndpoint(path: ["system", "runscheduler"]))
    }

    APIURLProtocol.state.prepare(
      status: 403, body: Data(#"{"detail":"用户权限不足"}"#.utf8),
      headers: ["Content-Type": "application/json"])
    await #expect(throws: APIError.forbidden) {
      try await Self.client().perform(APIEndpoint(path: ["system", "runscheduler"]))
    }
  }

  /// 同源和跨源跳转均停在第一跳；合成协议刻意保留认证，检验的是客户端拒绝策略。
  @Test(arguments: ["https://other.test/collect", "https://example.test/other"])
  func refusesAllCredentialRedirects(_ location: String) async throws {
    APIURLProtocol.state.prepare(
      status: 307, body: Data(), headers: [:], redirect: URL(string: location))
    await #expect(throws: APIError.redirectRefused) {
      try await Self.client().perform(APIEndpoint(path: ["plugin", "Example"], method: .put))
    }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 无拒绝代理的对照会实际跟随，避免用本身不会跳转的夹具制造假通过。
  @Test func redirectFixtureActuallyFollowsWithoutGuard() async throws {
    let target = try #require(URL(string: "https://example.test/other"))
    APIURLProtocol.state.prepare(status: 307, body: Data("{}".utf8), redirect: target)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [APIURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (_, response) = try await session.data(from: URL(string: "https://example.test/start")!)
    #expect(response.url == target)
    #expect(APIURLProtocol.state.requests().count == 2)
  }

  /// 无令牌请求不会继承其它身份；非法令牌在发出任何请求前失败。
  @Test func permitsAnonymousEndpointsAndRejectsHeaderInjection() async throws {
    APIURLProtocol.state.prepare(body: Data(#"{"success":true,"message":"","data":true}"#.utf8))
    _ = try await Self.client(token: nil).request(
      APIEndpoint(path: ["login", "initialization"]), as: Bool.self)
    #expect(
      APIURLProtocol.state.requests().first?.request.value(forHTTPHeaderField: "Authorization")
        == nil)
    for token in ["", "x\r\nCookie: secret", "has space", "非ASCII令牌"] {
      #expect(throws: APIError.invalidCredential) { try Self.client(token: token) }
    }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 取消悬挂的实际 URLSession 任务，不等待超时，不产生第二次请求。
  @Test func cancelsInFlightRequest() async throws {
    APIURLProtocol.state.prepare(body: Data(), hold: true)
    let client = try Self.client()
    let endpoint = try APIEndpoint(path: ["search", "media"])
    let task = Task { try await client.request(endpoint, as: JSONValue.self) }
    for _ in 0..<200 {
      if !APIURLProtocol.state.requests().isEmpty { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 会话主动结束也会取消在途请求；新客户端不继承旧会话的取消状态。
  @Test func invalidatesOnlyTheOwningClient() async throws {
    APIURLProtocol.state.prepare(body: Data(), hold: true)
    let old = try Self.client()
    let endpoint = try APIEndpoint(path: ["user", "current"])
    let task = Task { try await old.request(endpoint, as: Int.self) }
    for _ in 0..<200 {
      if !APIURLProtocol.state.requests().isEmpty { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    old.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(APIURLProtocol.state.requests().count == 1)
    APIURLProtocol.state.prepare(body: Data(#"{"success":true,"message":"","data":7}"#.utf8))
    let result = try await Self.client().request(endpoint, as: Int.self)
    #expect(result.value == 7)
    #expect(APIURLProtocol.state.requests().count == 1)
  }

  /// 预先取消的调用不接触网络，常见网络错误只转成稳定分类。
  @Test func preservesCancellationAndSanitizesNetworkErrors() async throws {
    APIURLProtocol.state.prepare(body: Data())
    let endpoint = try APIEndpoint(path: ["user", "current"])
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await Self.client().request(endpoint, as: JSONValue.self)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(APIURLProtocol.state.requests().isEmpty)
    for (code, expected) in [
      (URLError.Code.timedOut, APIError.timedOut),
      (.notConnectedToInternet, .unavailable),
    ] {
      APIURLProtocol.state.prepare(body: Data(), error: code)
      await #expect(throws: expected) {
        try await Self.client().request(endpoint, as: JSONValue.self)
      }
      #expect(APIURLProtocol.state.requests().count == 1)
    }
  }

  /// 注入污染配置来证明客户端清理边界；不会读本机真实账号或 Cookie。
  private static func client(
    address: String = "https://example.test/moviepilot/", token: String? = "synthetic.token",
    language: AppLanguage = .simplifiedChinese
  ) throws -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [APIURLProtocol.self]
    configuration.httpAdditionalHeaders = [
      "Cookie": "must-not-leak", "Authorization": "Bearer old", "X-Old-Session": "synthetic-old",
    ]
    return try APIClient(
      address: ServerAddress(address), token: token, language: language,
      configuration: configuration)
  }
}

/// 测试响应与请求捕获受锁保护；串行测试之间显式重置，不保留合成凭据。
private final class APIURLState: @unchecked Sendable {
  private let lock = NSLock()
  private var reply = APIURLReply(
    status: 200, body: Data(), headers: [:], redirect: nil, hold: false, error: nil)
  private var captured: [APICapturedRequest] = []
  private var refreshCookie: String?

  /// 每个测试从独立响应和空捕获开始，悬挂只用于验证取消传播。
  func prepare(
    status: Int = 200, body: Data,
    headers: [String: String] = ["Content-Type": "application/json"],
    redirect: URL? = nil, hold: Bool = false, error: URLError.Code? = nil,
    refreshCookie: String? = nil
  ) {
    lock.withLock {
      reply = APIURLReply(
        status: status, body: body, headers: headers, redirect: redirect, hold: hold, error: error)
      self.refreshCookie = refreshCookie
      captured = []
    }
  }

  /// 记录到达协议边界的真实请求和请求体；对照组的第二跳返回正常响应。
  func answer(_ request: URLRequest, body: Data) -> APIURLReply {
    lock.withLock {
      captured.append(APICapturedRequest(request: request, body: body))
      if let refreshCookie, request.url?.path.hasSuffix("/media/source") == true {
        return APIURLReply(
          status: 200, body: Data(#"{"success":true,"message":"","data":[]}"#.utf8),
          headers: ["Content-Type": "application/json", "Set-Cookie": refreshCookie],
          redirect: nil, hold: false, error: nil)
      }
      if request.url == reply.redirect {
        return APIURLReply(
          status: 200, body: reply.body, headers: reply.headers, redirect: nil, hold: false,
          error: nil)
      }
      return reply
    }
  }

  /// 返回线程安全快照，只用于断言合成请求，不进入产品日志。
  func requests() -> [APICapturedRequest] { lock.withLock { captured } }
}

/// 协议状态只包含不可变的合成值，可以从 URLSession 的工作线程安全读取。
private struct APIURLReply: Sendable {
  let status: Int
  let body: Data
  let headers: [String: String]
  let redirect: URL?
  let hold: Bool
  let error: URLError.Code?
}

/// 记录方法、头和实际请求字节，避免 httpBody 转为输入流后丢失写入断言。
private struct APICapturedRequest: Sendable {
  let request: URLRequest
  let body: Data
}

/// 拦截所有测试 session URL，即使实现错误跳到外部域名也不会访问真实服务。
private final class APIURLProtocol: URLProtocol, @unchecked Sendable {
  static let state = APIURLState()

  /// 本进程处理全部来源，以便捕获错误实现造成的重定向或重复请求。
  override class func canInit(with request: URLRequest) -> Bool { true }

  /// 不替生产代码修复 URL、方法或身份，真实构造结果必须接受断言。
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  /// 用 URLSession 标准回调提供响应；跳转是否继续由被测客户端代理裁决。
  override func startLoading() {
    let reply = Self.state.answer(request, body: Self.body(request))
    if let code = reply.error {
      client?.urlProtocol(self, didFailWithError: URLError(code))
      return
    }
    if reply.hold { return }
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else {
      client?.urlProtocol(self, didFailWithError: APIError.invalidResponse)
      return
    }
    if let redirect = reply.redirect {
      var target = request
      target.url = redirect
      client?.urlProtocol(self, wasRedirectedTo: target, redirectResponse: response)
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  /// 同步夹具没有额外计时器；取消悬挂请求由 URLSession 自身结束等待。
  override func stopLoading() {}

  /// 只消费合成测试请求的内存流，记录真实写入字节而不修改请求值。
  private static func body(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(contentsOf: buffer.prefix(count))
    }
    return data
  }
}
