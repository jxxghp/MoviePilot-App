import Foundation
import MoviePilotAPI
import Testing

@testable import MoviePilotSession

/// 通过实际 URLSession 检验原生认证，不启动网页、服务器或真实账号。
@Suite(.serialized)
struct NativeAuthenticationTests {
  /// 初始化 JSON 与登录表单不同，确认密码和 API Key 都必须只进入本次请求体。
  @Test func createsInitialAdministratorThroughTheJSONContract() async throws {
    NativeHTTPProtocol.state.prepare(
      body: Data(#"{"success":true,"message":"","data":null}"#.utf8))
    try await NativeSessionTestData.client().initialize(
      username: " fixed-admin ", password: "Fixture123!", confirmation: "Fixture123!",
      apiKey: " synthetic-key-only-123456 ")
    let captured = try #require(NativeHTTPProtocol.state.requests().first)
    let body = try #require(JSONSerialization.jsonObject(with: captured.body) as? [String: String])
    #expect(Set(body.keys) == ["username", "password", "confirm_password", "api_key"])
    #expect(body["username"] == "fixed-admin" && body["api_key"] == "synthetic-key-only-123456")
    #expect(body["password"] == "Fixture123!" && body["confirm_password"] == "Fixture123!")
    #expect(captured.request.httpMethod == "POST" && captured.request.url?.query == nil)
    #expect(
      captured.request.value(forHTTPHeaderField: "Content-Type")
        == "application/json; charset=utf-8")
    #expect(captured.request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(NativeHTTPProtocol.state.requests().count == 1)
  }

  /// 错误确认密码在发送前拒绝，服务端冲突只返回一次，不自动再次创建。
  @Test func doesNotReplayInitializationOrIgnoreConfirmation() async throws {
    NativeHTTPProtocol.state.prepare()
    await #expect(throws: NativeAuthenticationError.invalidInput) {
      try await NativeSessionTestData.client().initialize(
        username: "admin", password: "Fixture123!", confirmation: "different",
        apiKey: "synthetic-key-only-123456")
    }
    #expect(NativeHTTPProtocol.state.requests().isEmpty)
    NativeHTTPProtocol.state.prepare(status: 409)
    await #expect(throws: APIError.httpStatus(409)) {
      try await NativeSessionTestData.client().initialize(
        username: "admin", password: "Fixture123!", confirmation: "Fixture123!",
        apiKey: "synthetic-key-only-123456")
    }
    #expect(NativeHTTPProtocol.state.requests().count == 1)
  }

  /// 密码/OTP 表单独立编码，并且令牌、Cookie、旧账号头不从其它会话继承。
  @Test func logsInWithAnExplicitEncodedForm() async throws {
    NativeHTTPProtocol.state.prepare(body: NativeSessionTestData.login)
    let identity = try await NativeSessionTestData.client().login(
      username: "甲+a&b", password: "p=1&+%\n", otp: "012345")
    #expect(identity.user.id == 3 && identity.user.name == "reader")
    #expect(identity.user.level == 2 && identity.user.avatar.isEmpty)
    #expect(!identity.user.allows(PermissionRequirement(category: .admin)))
    #expect(
      !identity.user.allows(PermissionRequirement(category: .search, feature: "search.resource")))
    #expect(!String(reflecting: identity).contains("synthetic.session.token"))
    let captured = try #require(NativeHTTPProtocol.state.requests().first)
    #expect(captured.request.url?.path == "/moviepilot/api/v1/login/access-token")
    #expect(captured.request.httpMethod == "POST")
    #expect(
      captured.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix(
        "application/x-www-form-urlencoded") == true)
    #expect(captured.request.value(forHTTPHeaderField: "X-MoviePilot-Locale") == "en-US")
    #expect(captured.request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(captured.request.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(captured.request.value(forHTTPHeaderField: "X-Old-Account") == nil)
    let fields = String(decoding: captured.body, as: UTF8.self).components(separatedBy: "&")
    #expect(fields.count == 3)
    #expect(fields.contains("password=p%3D1%26%2B%25%0A"))
    #expect(fields.contains("otp_password=012345"))
    #expect(NativeHTTPProtocol.state.requests().count == 1)
  }

  /// 新旧返回形式映射相同原生身份，不通过旧网页 Store 的字段或 BridgeError。
  @Test(arguments: [false, true])
  func acceptsRawAndEnvelopeAuthentication(_ wrapped: Bool) async throws {
    let body =
      try wrapped
      ? NativeSessionTestData.envelope(NativeSessionTestData.login) : NativeSessionTestData.login
    NativeHTTPProtocol.state.prepare(body: body)
    let result = try await NativeSessionTestData.client().login(
      username: "reader", password: "synthetic-only", otp: nil)
    #expect(result.user.id == 3)
    #expect(result.accessToken == "synthetic.session.token")
  }

  /// current 的身份与权限覆盖冲突的 JWT 声明，只回退已验证令牌的展示等级。
  @Test(arguments: [false, true])
  func restoresOnlyTheServerVerifiedUser(_ wrapped: Bool) async throws {
    let token = NativeSessionTestData.token()
    let data =
      try wrapped
      ? NativeSessionTestData.envelope(NativeSessionTestData.current)
      : NativeSessionTestData.current
    NativeHTTPProtocol.state.prepare(body: data)
    let identity = try await NativeSessionTestData.client().restore(accessToken: token)
    #expect(identity.accessToken == token)
    #expect(identity.user.level == 2 && identity.user.isSuperuser == false)
    #expect(!identity.user.permissions.manage)
    #expect(
      !identity.user.allows(PermissionRequirement(category: .search, feature: "search.resource")))
    let captured = try #require(NativeHTTPProtocol.state.requests().first)
    #expect(captured.request.httpMethod == "GET" && captured.request.httpBody == nil)
    #expect(captured.request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    #expect(captured.request.url?.path == "/moviepilot/api/v1/user/current")
  }

  /// 初始化数据保留固定用户名，404 单独标为旧协议，不引导误建管理员。
  @Test func preservesInitializationStates() async throws {
    NativeHTTPProtocol.state.prepare(
      body: Data(
        #"{"success":true,"message":"","data":{"initialized":false,"configured_username":"fixed-admin"}}"#
          .utf8))
    #expect(
      try await NativeSessionTestData.client().initialization()
        == .required(configuredUsername: "fixed-admin"))
    NativeHTTPProtocol.state.prepare(
      body: Data(#"{"success":true,"data":{"initialized":true}}"#.utf8))
    #expect(try await NativeSessionTestData.client().initialization() == .ready)
    NativeHTTPProtocol.state.prepare(status: 404, headers: [:])
    #expect(try await NativeSessionTestData.client().initialization() == .legacy)
  }

  /// 多验证方式原样交给 UI 能力判断，密码不会因挑战而自动再提交。
  @Test(arguments: [["otp"], ["passkey", "otp"], ["future-method"]])
  func preservesMFAChoicesWithoutReplaying(_ methods: [String]) async throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "success": false, "data": ["mfa_methods": methods],
    ])
    NativeHTTPProtocol.state.prepare(
      status: 401, body: data,
      headers: ["Content-Type": "application/json", "X-MFA-Required": "true"])
    await #expect(throws: NativeAuthenticationError.verificationRequired(methods: methods)) {
      try await NativeSessionTestData.client().login(
        username: "reader", password: "synthetic-only", otp: nil)
    }
    #expect(NativeHTTPProtocol.state.requests().count == 1)
  }

  /// 缺失 MFA 标记不能泄露验证方式；损坏或空挑战不被当作已认证用户。
  @Test func rejectsInvalidChallengesAndPasswords() async throws {
    let data = Data(#"{"success":false,"data":{"mfa_methods":[]}}"#.utf8)
    NativeHTTPProtocol.state.prepare(
      status: 401, body: data,
      headers: ["X-MFA-Required": "true", "Content-Type": "application/json"])
    await #expect(throws: APIError.invalidResponse) {
      try await NativeSessionTestData.client().login(
        username: "reader", password: "synthetic-only", otp: nil)
    }
    NativeHTTPProtocol.state.prepare(status: 401, body: data)
    await #expect(throws: NativeAuthenticationError.credentials) {
      try await NativeSessionTestData.client().login(
        username: "reader", password: "synthetic-only", otp: nil)
    }
  }

  /// 不完整身份、未知 token_type、失败包装和停用账号不能进入成功会话。
  @Test func refusesMalformedAndInactiveIdentities() async throws {
    for (data, expected) in [
      (
        #"{"access_token":"","user_id":3,"user_name":"reader","super_user":false}"#,
        APIError.invalidCredential
      ),
      (
        #"{"access_token":"synthetic","user_id":-1,"user_name":"reader","super_user":false}"#,
        .invalidResponse
      ),
      (
        #"{"access_token":"synthetic","token_type":"basic","user_id":3,"user_name":"reader","super_user":false}"#,
        .invalidResponse
      ),
      (
        #"{"access_token":"synthetic","user_id":3,"user_name":"","super_user":false}"#,
        .invalidResponse
      ),
      (
        #"{"access_token":"synthetic","user_id":3,"user_name":"reader","super_user":1}"#,
        .invalidResponse
      ),
    ] {
      NativeHTTPProtocol.state.prepare(body: Data(data.utf8))
      await #expect(throws: expected) {
        try await NativeSessionTestData.client().login(
          username: "reader", password: "synthetic-only", otp: nil)
      }
    }
    NativeHTTPProtocol.state.prepare(body: Data(#"{"success":false,"data":null}"#.utf8))
    await #expect(throws: APIError.businessFailure) {
      try await NativeSessionTestData.client().login(
        username: "reader", password: "synthetic-only", otp: nil)
    }
    NativeHTTPProtocol.state.prepare(
      body: Data(#"{"id":3,"name":"reader","is_superuser":false,"is_active":false}"#.utf8))
    await #expect(throws: NativeAuthenticationError.inactiveAccount) {
      try await NativeSessionTestData.client().restore(accessToken: "synthetic.token")
    }
    NativeHTTPProtocol.state.prepare(
      body: Data("<html>synthetic-login-page</html>".utf8), headers: ["Content-Type": "text/html"])
    await #expect(throws: APIError.invalidResponse) {
      try await NativeSessionTestData.client().restore(accessToken: "synthetic.token")
    }
  }

  /// 不同实例与重复请求只带自己的 Bearer，服务器 Set-Cookie 不会成为后续身份。
  @Test func isolatesRestoreCredentials() async throws {
    NativeHTTPProtocol.state.prepare(
      body: NativeSessionTestData.current,
      headers: ["Content-Type": "application/json", "Set-Cookie": "other=synthetic"])
    let first = try NativeSessionTestData.client()
    let second = try NativeSessionTestData.client(address: "http://[::1]:5310/base/")
    _ = try await first.restore(accessToken: "synthetic.a")
    _ = try await second.restore(accessToken: "synthetic.b")
    _ = try await first.restore(accessToken: "synthetic.a")
    let captured = NativeHTTPProtocol.state.requests()
    #expect(
      captured.map { $0.request.value(forHTTPHeaderField: "Authorization") } == [
        "Bearer synthetic.a", "Bearer synthetic.b", "Bearer synthetic.a",
      ])
    for item in captured {
      #expect(item.request.value(forHTTPHeaderField: "Cookie") == nil)
      #expect(item.request.value(forHTTPHeaderField: "X-Old-Account") == nil)
      #expect(item.request.httpShouldHandleCookies == false)
    }
  }

  /// 401/403/限流/服务失败语义分离，错误正文不会出现在上层分类里，也不自动重发。
  @Test(arguments: [401, 403, 429, 503])
  func projectsRestoreHTTPFailures(_ status: Int) async throws {
    NativeHTTPProtocol.state.prepare(
      status: status, body: Data("synthetic-private-response".utf8), headers: ["Retry-After": "120"]
    )
    let expected: APIError =
      switch status {
      case 401: .unauthorized
      case 403: .forbidden
      case 429: .rateLimited(retryAfter: 120)
      default: .httpStatus(status)
      }
    await #expect(throws: expected) {
      try await NativeSessionTestData.client().restore(accessToken: "synthetic.token")
    }
    #expect(NativeHTTPProtocol.state.requests().count == 1)
    #expect(!String(reflecting: expected).contains("synthetic-private-response"))
  }

  /// 认证流在声明和实际读取时都限制 4 MiB，仍接受大于导航桥上限的合法内嵌头像。
  @Test func boundsAuthenticationWithoutUsingBridgeLimits() async throws {
    NativeHTTPProtocol.state.prepare(
      headers: ["Content-Type": "application/json", "Content-Length": "4194305"])
    await #expect(throws: APIError.responseTooLarge) {
      try await NativeSessionTestData.client().restore(accessToken: "synthetic.token")
    }
    NativeHTTPProtocol.state.prepare(body: Data(repeating: 32, count: 4 * 1024 * 1024 + 1))
    await #expect(throws: APIError.responseTooLarge) {
      try await NativeSessionTestData.client().restore(accessToken: "synthetic.token")
    }
    let data = try JSONSerialization.data(withJSONObject: [
      "id": 3, "name": "reader", "is_superuser": false,
      "avatar": "data:image/png;base64," + String(repeating: "A", count: 700_000),
    ])
    NativeHTTPProtocol.state.prepare(body: data)
    let result = try await NativeSessionTestData.client().restore(accessToken: "synthetic.token")
    #expect(result.user.avatar.utf8.count > 700_000)
  }

  /// 任何认证跳转都不能转发密码，包括原服务同源路径修正。
  @Test(arguments: ["https://other.test/collect", "https://example.test/other"])
  func rejectsCredentialRedirects(_ url: String) async throws {
    NativeHTTPProtocol.state.prepare(status: 307, redirect: URL(string: url))
    await #expect(throws: APIError.redirectRefused) {
      try await NativeSessionTestData.client().login(
        username: "reader", password: "synthetic-only", otp: "012345")
    }
    #expect(NativeHTTPProtocol.state.requests().count == 1)
  }

  /// 对照组证实夹具会真实产生第二跳，拒绝跳转测试不是夹具自身不跟随。
  @Test func redirectFixtureFollowsWithoutGuard() async throws {
    let target = try #require(URL(string: "https://example.test/other"))
    NativeHTTPProtocol.state.prepare(status: 307, body: Data("{}".utf8), redirect: target)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NativeHTTPProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (_, response) = try await session.data(from: URL(string: "https://example.test/start")!)
    #expect(response.url == target && NativeHTTPProtocol.state.requests().count == 2)
  }

  /// 关闭尝试或任务取消都会结束挂起认证；坏令牌在发送前拒绝。
  @Test(arguments: [false, true])
  func cancelsAuthentication(_ cancelClient: Bool) async throws {
    NativeHTTPProtocol.state.prepare(hold: true)
    let client = try NativeSessionTestData.client()
    let task = Task { try await client.restore(accessToken: "synthetic.token") }
    for _ in 0..<200 {
      if !NativeHTTPProtocol.state.requests().isEmpty { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    if cancelClient { client.cancel() } else { task.cancel() }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(NativeHTTPProtocol.state.requests().count == 1)
    NativeHTTPProtocol.state.prepare()
    await #expect(throws: APIError.invalidCredential) {
      try await NativeSessionTestData.client().restore(accessToken: "x\r\nCookie: synthetic")
    }
    #expect(NativeHTTPProtocol.state.requests().isEmpty)
  }
}
