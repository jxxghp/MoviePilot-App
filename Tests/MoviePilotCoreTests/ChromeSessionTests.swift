import Foundation
import Testing

@testable import MoviePilotCore

/// 检查接管事务和旧动作作废等跨消息行为。
struct ChromeSessionTests {
  /// 生成代表已授权页面的完整快照。
  private func snapshot(enabled: Bool = true) throws -> NavigationSnapshot {
    let json = """
      {"route":{"fullPath":"/dashboard","rootId":"dashboard","title":"仪表板","canGoBack":false},
       "roots":[{"id":"dashboard","path":"/dashboard","title":"仪表板","icon":"dashboard"}],
       "actions":[{"actionId":"a1","ownerId":"page1","title":"刷新","icon":"refresh",
       "position":"trailing","enabled":\(enabled),"loading":false}],
       "chrome":{"topVisible":true,"bottomVisible":true,"theme":"system"}}
      """
    return try JSONDecoder().decode(NavigationSnapshot.self, from: Data(json.utf8))
  }

  /// 事务不能跳过快照或确认；退出必须等网页已恢复后再隐藏原生导航。
  @Test func takeoverAndReleaseAreTransactional() throws {
    var session = ChromeSession()
    _ = try session.negotiate(majors: [1], capabilities: ChromeSession.requiredCapabilities)
    #expect(throws: BridgeError.busy) { try session.prepare(layoutRevision: 1) }
    try session.receive(snapshot(), routeRevision: 0, stateRevision: 1)
    try session.prepare(layoutRevision: 2)
    #expect(throws: BridgeError.invalidMessage) { try session.accept(layoutRevision: 1) }
    #expect(session.phase == .prepared)
    try session.accept(layoutRevision: 2)
    session.requestRelease()
    #expect(session.phase == .releasing)
    #expect(session.snapshot != nil)
    session.released()
    #expect(session.phase == .webNavigation)
    #expect(session.sessionId == nil)
    #expect(!session.takeoverAllowed)
  }

  /// 主题强调色只接受封闭的六位色值，不能将 CSS 或额外指令透传 UIKit。
  @Test func validatesOptionalAccentColor() throws {
    let base = try JSONEncoder().encode(snapshot())
    var object = try JSONSerialization.jsonObject(with: base) as! [String: Any]
    var chrome = object["chrome"] as! [String: Any]
    for color in ["#8D51F9", "#00aaff", "red", "#123456;display:none", "#12345678", "#123456\n"] {
      chrome["accentColor"] = color
      object["chrome"] = chrome
      let value = try JSONDecoder().decode(
        NavigationSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
      if color == "#8D51F9" || color == "#00aaff" {
        try value.validate()
      } else {
        #expect(throws: BridgeError.invalidMessage) { try value.validate() }
      }
    }
  }

  /// 路由代次、动作权限与文档会话变化均能撤销一次旧点击。
  @Test func invalidatesOldActionsAndSnapshots() throws {
    var session = ChromeSession()
    let id = try session.negotiate(majors: [1], capabilities: ChromeSession.requiredCapabilities)
    try session.receive(snapshot(), routeRevision: 1, stateRevision: 1)
    try session.prepare(layoutRevision: 1)
    try session.accept(layoutRevision: 1)
    try session.validateAction(sessionId: id, routeRevision: 1, actionId: "a1", ownerId: "page1")
    try session.receive(snapshot(enabled: false), routeRevision: 1, stateRevision: 2)
    #expect(throws: BridgeError.actionNotAvailable) {
      try session.validateAction(sessionId: id, routeRevision: 1, actionId: "a1", ownerId: "page1")
    }
    #expect(throws: BridgeError.staleRoute) {
      try session.receive(snapshot(), routeRevision: 0, stateRevision: 3)
    }
    #expect(throws: BridgeError.staleRoute) {
      try session.receive(snapshot(), routeRevision: 1, stateRevision: 2)
    }
    session.beginDocument()
    #expect(throws: BridgeError.staleSession) {
      try session.validateAction(sessionId: id, routeRevision: 1, actionId: "a1", ownerId: "page1")
    }
    #expect(
      try session.negotiate(majors: [1], capabilities: ChromeSession.requiredCapabilities) != id)
  }

  /// 崩溃不能冒充网页恢复，禁用接管也不能被重复就绪消息重开。
  @Test func processFailureRequiresRecovery() throws {
    var session = ChromeSession()
    session.failed()
    #expect(session.phase == .recovery)
    session.released()
    #expect(session.phase == .recovery)
    session.beginDocument(allowTakeover: false)
    #expect(throws: BridgeError.busy) {
      try session.negotiate(majors: [1], capabilities: ChromeSession.requiredCapabilities)
    }
  }

  /// 恢复文档必须允许重新接管，并拒绝被系统回收文档的会话和旧点击。
  @Test func recoveredDocumentCanTakeOverWithFreshIdentity() throws {
    var session = ChromeSession()
    let old = try session.negotiate(majors: [1], capabilities: ChromeSession.requiredCapabilities)
    try session.receive(snapshot(), routeRevision: 2, stateRevision: 3)
    try session.prepare(layoutRevision: 1)
    try session.accept(layoutRevision: 1)
    session.failed()
    session.beginDocument()
    let current = try session.negotiate(
      majors: [1], capabilities: ChromeSession.requiredCapabilities)
    #expect(current != old)
    #expect(session.snapshot == nil)
    try session.receive(snapshot(), routeRevision: 0, stateRevision: 1)
    try session.prepare(layoutRevision: 0)
    try session.accept(layoutRevision: 0)
    #expect(session.phase == .nativeNavigation)
    #expect(throws: BridgeError.staleSession) {
      try session.validateAction(sessionId: old, routeRevision: 2, actionId: "a1", ownerId: "page1")
    }
    try session.validateAction(
      sessionId: current, routeRevision: 0, actionId: "a1", ownerId: "page1")
  }

  /// 同文档换账号也必须拒绝旧会话，并在新快照到达前阻止旧按钮执行。
  @Test func identityRotationRevokesOldDocumentActions() throws {
    var session = ChromeSession()
    let old = try session.negotiate(majors: [1], capabilities: ChromeSession.requiredCapabilities)
    try session.receive(snapshot(), routeRevision: 1, stateRevision: 1)
    try session.prepare(layoutRevision: 1)
    try session.accept(layoutRevision: 1)
    let current = try session.rotateIdentity()
    #expect(current != old)
    #expect(session.snapshot == nil)
    #expect(throws: BridgeError.staleSession) {
      try session.validateAction(sessionId: old, routeRevision: 1, actionId: "a1", ownerId: "page1")
    }
    #expect(throws: BridgeError.staleRoute) {
      try session.validateAction(
        sessionId: current, routeRevision: 1, actionId: "a1", ownerId: "page1")
    }
    try session.receive(snapshot(), routeRevision: 2, stateRevision: 1)
    try session.validateAction(
      sessionId: current, routeRevision: 2, actionId: "a1", ownerId: "page1")
  }

  /// 去重缓存受限且文档切换清空；不宣称跨进程只执行一次。
  @Test func duplicateDispatchIsBoundedToDocument() {
    var session = ChromeSession()
    let first = session.markProcessed("a")
    let duplicate = session.markProcessed("a")
    #expect(first)
    #expect(!duplicate)
    for index in 0..<256 {
      let inserted = session.markProcessed("r\(index)")
      #expect(inserted)
    }
    let evicted = session.markProcessed("a")
    #expect(evicted)
    session.beginDocument()
    let nextDocument = session.markProcessed("a")
    #expect(nextDocument)
  }

  /// 不允许外链被当成内部 Vue 路由执行。
  @Test(arguments: [
    "//evil.test/", "https://evil.test/", "javascript:alert(1)", "/\\evil", "/path\nnext",
  ])
  func rejectsExternalRoute(path: String) {
    #expect(!NavigationSnapshot.isRoute(path))
  }
}
