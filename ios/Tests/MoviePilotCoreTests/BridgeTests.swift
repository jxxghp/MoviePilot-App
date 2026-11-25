import Foundation
import Testing

@testable import MoviePilotCore

/// 验证消息来源、载荷上限与会话失效，避免仅测试 Codable 自身。
struct BridgeTests {
  private let origin = WebOrigin(scheme: "https", host: "mp.test", port: 443)!

  /// 构造没有业务信息的协议消息。
  private func message(type: String = "navigation.state", session: String? = "current") throws
    -> Data
  {
    try JSONEncoder().encode(
      BridgeEnvelope(type: type, requestId: "web-1", sessionId: session, payload: .object([:])))
  }

  /// 子 frame、其他 WebView 与伪造消息中的 origin 均不具有宿主权限。
  @Test func rejectsUntrustedFrames() throws {
    let validator = BridgeValidator(origin: origin)
    for source in [
      BridgeSource(isMainFrame: false, isCurrentWebView: true, origin: origin),
      BridgeSource(isMainFrame: true, isCurrentWebView: false, origin: origin),
      BridgeSource(
        isMainFrame: true, isCurrentWebView: true,
        origin: WebOrigin(scheme: "https", host: "evil.test", port: 443)),
    ] {
      #expect(throws: BridgeError.untrustedFrame) {
        try validator.decode(message(), source: source, sessionId: "current")
      }
    }
  }

  /// 就绪消息不依赖会话，其余消息不能引用上一文档会话。
  @Test func enforcesDocumentSession() throws {
    let validator = BridgeValidator(origin: origin)
    let source = BridgeSource(isMainFrame: true, isCurrentWebView: true, origin: origin)
    #expect(
      try validator.decode(message(type: "web.ready", session: nil), source: source, sessionId: nil)
        .type == "web.ready")
    #expect(throws: BridgeError.staleSession) {
      try validator.decode(message(session: "old"), source: source, sessionId: "current")
    }
    #expect(throws: BridgeError.staleSession) {
      try validator.decode(message(), source: source, sessionId: nil)
    }
  }

  /// 大消息和恶意深层嵌套在递归解码之前被拒绝。
  @Test func boundsPayloadAndDepth() throws {
    let validator = BridgeValidator(origin: origin)
    let source = BridgeSource(isMainFrame: true, isCurrentWebView: true, origin: origin)
    for data in [
      Data(repeating: 32, count: 65_537),
      Data(
        (String(repeating: "[", count: 32)
          + String(repeating: "]", count: 32)).utf8),
    ] {
      #expect(throws: BridgeError.invalidMessage) {
        try validator.decode(data, source: source, sessionId: "current")
      }
    }
    let unsupported = String(decoding: try message(), as: UTF8.self).replacingOccurrences(
      of: "\"major\":1", with: "\"major\":2")
    #expect(throws: BridgeError.unsupportedVersion) {
      try validator.decode(Data(unsupported.utf8), source: source, sessionId: "current")
    }
  }

  /// 原生菜单只能消费内部入口；外链、重复身份和缺失目录不能成为可点击列表。
  @Test func rejectsInvalidMenuCatalog() throws {
    let fixture =
      #"{"route":{"fullPath":"/apps","rootId":"apps","title":"更多","canGoBack":false},"roots":[{"id":"apps","path":"/apps","title":"更多","icon":"mdi-apps"}],"actions":[],"chrome":{"topVisible":true,"bottomVisible":true,"theme":"system","content":"menu"},"moreMenu":[{"id":"manage","title":"管理","items":[{"id":"plugins","path":"/plugins","title":"插件","icon":"mdi-puzzle"}]}]}"#
    let valid = try JSONDecoder().decode(NavigationSnapshot.self, from: Data(fixture.utf8))
    try valid.validate()
    for value in ["https://untrusted.example/plugins", "//untrusted.example/plugins"] {
      let invalid = try JSONDecoder().decode(
        NavigationSnapshot.self,
        from: Data(fixture.replacingOccurrences(of: "\"/plugins\"", with: "\"\(value)\"").utf8))
      #expect(throws: BridgeError.invalidMessage) { try invalid.validate() }
    }
    let item = #"{"id":"plugins","path":"/plugins","title":"插件","icon":"mdi-puzzle"}"#
    let duplicate = try JSONDecoder().decode(
      NavigationSnapshot.self,
      from: Data(fixture.replacingOccurrences(of: item, with: "\(item),\(item)").utf8))
    #expect(throws: BridgeError.invalidMessage) { try duplicate.validate() }
  }
}
