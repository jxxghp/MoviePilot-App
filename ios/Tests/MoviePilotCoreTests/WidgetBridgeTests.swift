import Foundation
import Testing

@testable import MoviePilotCore

/// 专用桥结果使用合成身份和密钥，验证相关操作的严格字段与有限授权边界。
struct WidgetBridgeTests {
  private let owner = String(repeating: "a", count: 32)
  private let installation = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
  private let registration = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  /// 出站只有固定操作与白名单参数，不包含地址、主认证或业务正文。
  @Test func sendsOnlyFiniteOperationFields() {
    #expect(WidgetBridgeOperation.context.payload == .object(["operation": .string("context")]))
    #expect(
      WidgetBridgeOperation.register(owner: owner, installationId: installation).payload
        == .object([
          "operation": .string("register"), "owner": .string(owner),
          "installationId": .string(installation.uuidString.lowercased()),
        ]))
    #expect(
      WidgetBridgeOperation.revoke(owner: owner, registrationId: registration).payload
        == .object([
          "operation": .string("revoke"), "owner": .string(owner),
          "registrationId": .string(registration.uuidString.lowercased()),
        ]))
    #expect(
      WidgetBridgeOperation.open(owner: owner, content: .downloads).payload
        == .object([
          "operation": .string("open"), "owner": .string(owner), "content": .string("downloads"),
        ]))
  }

  /// 当前身份、唯一内容以及未知字段都必须显式验证，不能宽松读取主登录对象。
  @Test func validatesContextProjection() throws {
    guard
      case .context(let value) = try WidgetBridgeResponse.decode(success(context()), for: .context)
    else {
      Issue.record("Missing context")
      return
    }
    #expect(value.owner == owner)
    #expect(value.availableContents == [.overview, .downloads])
    var invalid = context()
    for changed in [
      ["owner": JSONValue.string("42")],
      ["availableContents": .array([.string("downloads"), .string("downloads")])],
      ["availableContents": .array([.string("__proto__")])],
      ["token": .string("private-main-token")],
      ["version": .number(2)],
    ] {
      invalid = context().merging(changed) { _, replacement in replacement }
      #expect(throws: WidgetBridgeError.invalidData) {
        try WidgetBridgeResponse.decode(success(invalid), for: .context)
      }
    }
  }

  /// 同安装、同 owner、有限期专用 secret 才能保存；其它操作不能取得登记结果。
  @Test func bindsRegistrationToTheRequestedIdentityAndInstallation() throws {
    let operation = WidgetBridgeOperation.register(owner: owner, installationId: installation)
    let fields = registered()
    guard
      case .registered(let value) = try WidgetBridgeResponse.decode(
        success(fields), for: operation, now: now)
    else {
      Issue.record("Missing registration")
      return
    }
    #expect(value.registrationId == registration)
    #expect(value.context.owner == owner)
    #expect(value.expiresAt == now.timeIntervalSince1970 + 3600)
    for changed in [
      ["installationId": JSONValue.string(UUID().uuidString.lowercased())],
      ["registrationId": .string(registration.uuidString)],
      ["secret": .string("eyJ-main-JWT")],
      [
        "secret": .string(
          "mpw_\(UUID().uuidString.lowercased())." + String(repeating: "A", count: 43))
      ],
      ["expiresAt": .number(now.timeIntervalSince1970)],
      ["expiresAt": .number(now.timeIntervalSince1970 + 30 * 86_400 + 301)],
      ["availableContents": .array([])],
      ["accessToken": .string("private")],
    ] {
      #expect(throws: WidgetBridgeError.invalidData) {
        try WidgetBridgeResponse.decode(
          success(fields.merging(changed) { _, replacement in replacement }), for: operation,
          now: now)
      }
    }
    #expect(throws: WidgetBridgeError.identityChanged) {
      try WidgetBridgeResponse.decode(
        success(
          fields.merging(["owner": .string(String(repeating: "b", count: 32))]) { _, replacement in
            replacement
          }),
        for: operation, now: now)
    }
    #expect(throws: WidgetBridgeError.invalidData) {
      try WidgetBridgeResponse.decode(success(fields), for: .context, now: now)
    }
    #expect(throws: WidgetBridgeError.invalidData) {
      try WidgetBridgeResponse.decode(success(context()), for: operation, now: now)
    }
  }

  /// 只有固定错误能够跨桥；未知错误、回显正文和过大数据统一失败。
  @Test func rejectsUnexpectedErrorContentAndOversizedResults() {
    #expect(throws: WidgetBridgeError.unauthorized) {
      try WidgetBridgeResponse.decode(
        .object(["success": .bool(false), "error": .string("unauthorized")]), for: .context)
    }
    for payload in [
      JSONValue.object(["success": .bool(false), "error": .string("raw backend error")]),
      .object([
        "success": .bool(false), "error": .string("unavailable"), "body": .string("private"),
      ]),
      .object(["success": .bool(true), "data": .string(String(repeating: "a", count: 2048))]),
      .object(["success": .bool(true), "data": .null]),
      .object(["success": .number(1), "data": .object(context())]),
    ] {
      #expect(throws: WidgetBridgeError.invalidData) {
        try WidgetBridgeResponse.decode(payload, for: .context)
      }
    }
  }

  /// 跳转或撤销只确认完成，不接受额外地址、路由或凭据。
  @Test func restrictsCompletionToItsOwnOperation() throws {
    let operation = WidgetBridgeOperation.open(owner: owner, content: .overview)
    guard
      case .completed = try WidgetBridgeResponse.decode(
        success(["completed": .bool(true)]), for: operation)
    else {
      Issue.record("Missing completion")
      return
    }
    for fields in [
      ["completed": JSONValue.bool(false)],
      ["completed": .bool(true), "url": .string("https://other.invalid")],
    ] {
      #expect(throws: WidgetBridgeError.invalidData) {
        try WidgetBridgeResponse.decode(success(fields), for: operation)
      }
    }
  }

  /// 合成上下文与真实网页投影结构相同，不需要登录或访问任何后端。
  private func context() -> [String: JSONValue] {
    [
      "version": .number(1), "owner": .string(owner),
      "availableContents": .array([.string("overview"), .string("downloads")]),
    ]
  }

  /// 只创建与本测试安装和登记绑定的专用格式；不得替换成真实密钥。
  private func registered() -> [String: JSONValue] {
    context().merging([
      "registrationId": .string(registration.uuidString.lowercased()),
      "installationId": .string(installation.uuidString.lowercased()),
      "secret": .string(
        "mpw_\(registration.uuidString.lowercased())." + String(repeating: "A", count: 43)),
      "expiresAt": .number(now.timeIntervalSince1970 + 3600),
    ]) { _, replacement in replacement }
  }

  /// 成功正文独立于普通导航快照与命令结果。
  private func success(_ data: [String: JSONValue]) -> JSONValue {
    .object(["success": .bool(true), "data": .object(data)])
  }
}
