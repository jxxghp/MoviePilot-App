import Foundation
import Testing

@testable import MoviePilotCore

/// 断言元数据和事务边界测试；不将这些测试凭证作为真实签名或 Face ID 验收。
struct PasskeyTests {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)
  private let state = Data(repeating: 42, count: 32)
  private let challenge = Data(repeating: 7, count: 32)

  /// 测试编码遵循前端固定 fragment 协议，不含真实账号或生产密钥。
  private func encode(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  /// 创建当前后端已有的 start envelope，支持单项边界修改。
  private func start(options changes: [String: JSONValue] = [:], legacy: Bool = false) throws
    -> Data
  {
    var options: [String: JSONValue] = [
      "challenge": .string(encode(challenge)), "rpId": .string("example.com"),
      "timeout": .number(60_000), "userVerification": .string("preferred"),
    ]
    options.merge(changes) { _, new in new }
    let encoded = try JSONEncoder().encode(JSONValue.object(options))
    return try JSONEncoder().encode(
      JSONValue.object([
        "success": .bool(true),
        "data": .object([
          "transaction_token": .string("private-transaction-token"),
          "options": legacy ? .string(String(decoding: encoded, as: UTF8.self)) : .object(options),
        ]),
      ]))
  }

  /// 每次断言验证拥有新的事务，防止不同参数测试共享已消费的状态。
  private func transaction() throws -> PasskeyTransaction {
    try PasskeyTransaction(
      startData: start(), address: ServerAddress("https://example.com/mp/"), state: state, now: now)
  }

  /// 返回固定路径的测试断言；签名内容只用于字段边界校验，交由后端的签名验证不在此测试中。
  private func callback(
    error: String? = nil, state: String? = nil, client changes: [String: JSONValue] = [:],
    response responseChanges: [String: JSONValue] = [:],
    credential credentialChanges: [String: JSONValue] = [:]
  ) throws -> URL {
    var client: [String: JSONValue] = [
      "type": .string("webauthn.get"), "challenge": .string(encode(challenge)),
      "origin": .string("https://example.com"), "crossOrigin": .bool(false),
    ]
    client.merge(changes) { _, new in new }
    var response: [String: JSONValue] = [
      "clientDataJSON": .string(encode(try JSONEncoder().encode(JSONValue.object(client)))),
      "authenticatorData": .string(encode(Data(repeating: 0, count: 37))),
      "signature": .string(encode(Data(repeating: 1, count: 70))), "userHandle": .null,
    ]
    response.merge(responseChanges) { _, new in new }
    var credential: [String: JSONValue] = [
      "id": .string("AQID"), "rawId": .string("AQID"), "type": .string("public-key"),
      "response": .object(response),
    ]
    credential.merge(credentialChanges) { _, new in new }
    var payload: [String: JSONValue] = [
      "version": .number(1), "state": .string(state ?? encode(self.state)),
    ]
    if let error {
      payload["error"] = .string(error)
    } else {
      payload["credential"] = .object(credential)
    }
    let encoded = encode(try JSONEncoder().encode(JSONValue.object(payload)))
    return URL(string: "moviepilot://passkey/callback#result=\(encoded)")!
  }

  /// 独立入口不能包含事务令牌，旧 options 字符串与对象都生成同一协议。
  @Test(arguments: [false, true]) func separatesTransactionFromBrowser(legacy: Bool) throws {
    let address = try ServerAddress("https://example.com/mp/")
    let value = try PasskeyTransaction(
      startData: start(legacy: legacy), address: address, state: state, now: now)
    #expect(value.authorizationURL.path == "/mp/native-passkey.html")
    #expect(value.authorizationURL.query == nil)
    #expect(!value.authorizationURL.absoluteString.contains("private-transaction-token"))
    let encoded = try #require(value.authorizationURL.fragment?.dropFirst(8))
    var raw = String(encoded).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
    let data = try #require(Data(base64Encoded: raw))
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("transaction_token"))
    #expect(!text.contains("private-transaction-token"))
  }

  /// 成功后只向原 finish 提交一次，重复回调不能再次使用内存中的事务令牌。
  @Test func consumesOnlyOnce() throws {
    var value = try transaction()
    let address = try ServerAddress("https://example.com/mp/")
    let callback = try callback()
    let body = try value.finishBody(callback: callback, address: address, now: now)
    let payload = try JSONDecoder().decode(JSONValue.self, from: body)
    guard case .object(let fields) = payload else {
      Issue.record("缺少 finish 字段")
      return
    }
    #expect(Set(fields.keys) == ["credential", "transaction_token"])
    #expect(fields["transaction_token"] == .string("private-transaction-token"))
    #expect(throws: PasskeyFailure.expired) {
      try value.finishBody(callback: callback, address: address, now: now)
    }
  }

  /// 取消及浏览器固定失败码只影响当前事务，不生成可提交给 finish 的数据。
  @Test(arguments: ["canceled", "expired", "unsupported", "invalid", "failed", "private-error"])
  func rejectsErrorCallback(code: String) throws {
    var value = try transaction()
    #expect(throws: (any Error).self) {
      try value.finishBody(
        callback: callback(error: code), address: ServerAddress("https://example.com/mp/"), now: now
      )
    }
  }

  /// URL 路径、来源和查询字段不可由第三方外链替代，回调只属于当前 AS 会话。
  @Test(arguments: [
    "https://passkey/callback", "moviepilot://other/callback", "moviepilot://passkey/other",
    "moviepilot://user@passkey/callback", "moviepilot://passkey:42/callback",
    "moviepilot://passkey/callback?q=1",
  ]) func rejectsCallbackURL(base: String) throws {
    var value = try transaction()
    let fragment = try #require(callback().fragment)
    #expect(throws: PasskeyFailure.invalid) {
      try value.finishBody(
        callback: URL(string: base + "#" + fragment)!,
        address: ServerAddress("https://example.com/mp/"), now: now)
    }
  }

  /// 同一域名下不同实例、过期、时钟倒退与错 state 都不能使用旧事务。
  @Test(arguments: ["instance", "expired", "clock", "state"])
  func rejectsStaleOrDifferentTransaction(mode: String) throws {
    var value = try transaction()
    let address = try ServerAddress(
      mode == "instance" ? "https://example.com/other/" : "https://example.com/mp/")
    let date = now.addingTimeInterval(mode == "expired" ? 60 : mode == "clock" ? -1 : 0)
    #expect(throws: (any Error).self) {
      try value.finishBody(
        callback: callback(state: mode == "state" ? encode(Data(repeating: 43, count: 32)) : nil),
        address: address, now: date)
    }
  }

  /// WebAuthn 客户端元数据必须与本次挑战和精确浏览器来源一致。
  @Test(arguments: ["origin", "type", "challenge", "crossOrigin"])
  func rejectsClientTampering(field: String) throws {
    var value = try transaction()
    let replacement: JSONValue =
      field == "crossOrigin" ? .bool(true) : .string("https://evil.example")
    #expect(throws: PasskeyFailure.invalid) {
      try value.finishBody(
        callback: callback(client: [field: replacement]),
        address: ServerAddress("https://example.com/mp/"), now: now)
    }
  }

  /// 对认证字节、空用户标识和额外响应字段实施与前端相同的上限。
  @Test(arguments: ["authenticatorData", "signature", "clientDataJSON", "userHandle", "extra"])
  func rejectsMalformedResponse(field: String) throws {
    var value = try transaction()
    #expect(throws: (any Error).self) {
      try value.finishBody(
        callback: callback(response: [field: .string("")]),
        address: ServerAddress("https://example.com/mp/"), now: now)
    }
  }

  /// start 不能更换 RP、扩大协议或把非规范编码交给浏览器。
  @Test(arguments: ["rpId", "challenge", "timeout", "userVerification", "extra"])
  func rejectsStartOptions(field: String) throws {
    #expect(throws: (any Error).self) {
      try PasskeyTransaction(
        startData: start(options: [field: .string("invalid")]),
        address: ServerAddress("https://example.com/mp/"), state: state, now: now)
    }
  }

  /// 非安全私网地址仍可密码登录，但不能静默进入不支持的 WebAuthn 页面。
  @Test func requiresSecureContext() throws {
    #expect(!PasskeyTransaction.isSecure(try ServerAddress("http://192.168.1.20")))
    #expect(PasskeyTransaction.isSecure(try ServerAddress("http://localhost:5246")))
    #expect(throws: PasskeyFailure.unsupported) {
      try PasskeyTransaction(
        startData: start(), address: ServerAddress("http://192.168.1.20"), state: state, now: now)
    }
  }

  /// 当前后端统一响应与旧版裸数组都按服务端的显式开关显示入口。
  @Test(arguments: [false, true]) func acceptsProviderResponseFormats(enveloped: Bool) throws {
    for (body, enabled) in [
      (#"[{"type":"system","method":"passkey","enabled":true}]"#, true),
      (#"[{"type":"system","method":"passkey","enabled":false}]"#, false),
      (#"[{"type":"oidc","method":"passkey","enabled":true}]"#, false),
      (#"[{"type":"system","method":"passkey","enabled":"true"}]"#, false),
      ("[]", false),
    ] {
      let response = enveloped ? #"{"success":true,"message":"","data":\#(body)}"# : body
      #expect(try PasskeyTransaction.providerEnabled(Data(response.utf8)) == enabled)
    }
  }

  /// 失败或损坏的统一响应不能把其中的认证方式误当作已启用。
  @Test(arguments: [
    #"{"success":false,"data":[{"type":"system","method":"passkey","enabled":true}]}"#,
    #"{"data":[{"type":"system","method":"passkey","enabled":true}]}"#,
    #"{"success":"true","data":[]}"#, #"{"success":true,"data":{}}"#,
    #"{"success":true}"#, "null",
  ]) func rejectsInvalidProviderResponse(body: String) {
    #expect(throws: PasskeyFailure.invalid) {
      try PasskeyTransaction.providerEnabled(Data(body.utf8))
    }
  }

  /// 系统开关和静态协议必须显式匹配，不能从 HTML 或相似第三方 provider 推测。
  @Test func requiresExplicitCapabilities() throws {
    #expect(
      try PasskeyTransaction.providerEnabled(
        Data(#"[{"type":"system","method":"passkey","enabled":true}]"#.utf8)))
    #expect(
      try !PasskeyTransaction.providerEnabled(
        Data(#"[{"type":"system","method":"passkey","enabled":false}]"#.utf8)))
    #expect(
      try !PasskeyTransaction.providerEnabled(
        Data(#"[{"type":"oidc","method":"passkey","enabled":true}]"#.utf8)))
    #expect(
      PasskeyTransaction.supportsFrontend(
        Data(#"{"protocol":"moviepilot.passkey","version":1}"#.utf8)))
    #expect(
      !PasskeyTransaction.supportsFrontend(
        Data(#"{"protocol":"moviepilot.passkey","version":2}"#.utf8)))
    #expect(!PasskeyTransaction.supportsFrontend(Data("<html>login</html>".utf8)))
  }
}
