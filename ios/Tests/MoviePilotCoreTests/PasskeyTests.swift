import Foundation
import Testing

@testable import MoviePilotCore

/// 断言元数据、事务边界与反代外挂字幕地址重绑测试。
struct PasskeyTests {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)
  private let state = Data(repeating: 42, count: 32)
  private let challenge = Data(repeating: 7, count: 32)

  private func encode(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

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

  private func transaction() throws -> PasskeyTransaction {
    try PasskeyTransaction(
      startData: start(), address: ServerAddress("https://example.com/mp/"), state: state, now: now)
  }

  private func callback(
    error: String? = nil, state: String? = nil, client changes: [String: JSONValue] = [:],
    response responseChanges: [String: JSONValue] = [:]
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
    let credential: [String: JSONValue] = [
      "id": .string("AQID"), "rawId": .string("AQID"), "type": .string("public-key"),
      "response": .object(response),
    ]
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

  @Test(arguments: [false, true]) func separatesTransactionFromBrowser(legacy: Bool) throws {
    let address = try ServerAddress("https://example.com/mp/")
    let value = try PasskeyTransaction(
      startData: start(legacy: legacy), address: address, state: state, now: now)
    #expect(value.authorizationURL.path == "/mp/native-passkey.html")
    #expect(value.authorizationURL.query == nil)
    #expect(!value.authorizationURL.absoluteString.contains("private-transaction-token"))
  }

  @Test func consumesOnlyOnce() throws {
    var value = try transaction()
    let address = try ServerAddress("https://example.com/mp/")
    let cb = try callback()
    let body = try value.finishBody(callback: cb, address: address, now: now)
    let payload = try JSONDecoder().decode(JSONValue.self, from: body)
    guard case .object(let fields) = payload else {
      Issue.record("缺少 finish 字段")
      return
    }
    #expect(fields["transaction_token"] == .string("private-transaction-token"))
    #expect(throws: PasskeyFailure.expired) {
      try value.finishBody(callback: cb, address: address, now: now)
    }
  }

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

  @Test func rebasesReverseProxySubtitleAndStreamURLs() throws {
    let httpsRoot = try ServerAddress("https://mp.example.com:8443")
    let rawSub = URL(
      string:
        "http://mp.example.com:8443/api/v1/mediaserver/stream-subtitle?itemid=%2Flibrary%2F1&subtitle_id=ms%3A1%3A2.ass&server=Emby"
    )!
    #expect(
      httpsRoot.rebasingInstanceAPIURL(rawSub).absoluteString
        == "https://mp.example.com:8443/api/v1/mediaserver/stream-subtitle?itemid=%2Flibrary%2F1&subtitle_id=ms%3A1%3A2.ass&server=Emby"
    )

    let subpath = try ServerAddress("https://nas.example.com/mp/")
    let internalSub = URL(
      string: "http://172.17.0.3:3001/api/v1/mediaserver/stream-subtitle?itemid=9&subtitle_id=a.ass"
    )!
    #expect(
      subpath.rebasingInstanceAPIURL(internalSub).absoluteString
        == "https://nas.example.com/mp/api/v1/mediaserver/stream-subtitle?itemid=9&subtitle_id=a.ass"
    )

    let externalCDN = URL(string: "https://cdn.example.net/d/movie.mkv?sign=xyz")!
    #expect(httpsRoot.rebasingInstanceAPIURL(externalCDN) == externalCDN)
  }
}
