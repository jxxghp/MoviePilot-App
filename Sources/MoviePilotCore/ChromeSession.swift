import Foundation

/// 接管事务状态；恢复状态必须由容器展示可操作的恢复界面。
public enum ChromePhase: String, Sendable {
  case webNavigation, negotiating, prepared, nativeNavigation, releasing, recovery
}

/// 单个顶层文档的导航会话；所有写入由 UI 主线程上的协调器串行驱动。
public struct ChromeSession: Sendable {
  public private(set) var phase: ChromePhase = .webNavigation
  public private(set) var sessionId: String?
  public private(set) var snapshot: NavigationSnapshot?
  public private(set) var routeRevision = -1
  public private(set) var stateRevision = -1
  public private(set) var layoutRevision = -1
  public private(set) var takeoverAllowed = true
  private var completedRequests: Set<String> = []
  private var requestOrder: [String] = []
  public static let requiredCapabilities: Set<String> = [
    "navigation.v1", "actions.v1", "layout.v1", "menu.v1",
  ]

  /// 创建尚未协商的文档会话。
  public init() {}

  /// 顶层文档更换时清理所有显示与命令；恢复重载可以禁用本次原生接管。
  public mutating func beginDocument(allowTakeover: Bool = true) {
    self = ChromeSession()
    takeoverAllowed = allowTakeover
  }

  /// 双方能力匹配后建立新关联会话，旧文档消息不能沿用此会话。
  @discardableResult
  public mutating func negotiate(majors: [Int], capabilities: Set<String>) throws -> String {
    guard phase == .webNavigation, takeoverAllowed else { throw BridgeError.busy }
    guard majors.contains(1) else { throw BridgeError.unsupportedVersion }
    guard Self.requiredCapabilities.isSubset(of: capabilities) else {
      throw BridgeError.unsupportedCapability
    }
    let id = UUID().uuidString
    sessionId = id
    phase = .negotiating
    return id
  }

  /// 只接受递增的完整快照；路由代次不能倒退，业务返回也产生新的代次。
  public mutating func receive(_ value: NavigationSnapshot, routeRevision: Int, stateRevision: Int)
    throws
  {
    guard [.negotiating, .prepared, .nativeNavigation].contains(phase) else {
      throw BridgeError.busy
    }
    guard routeRevision >= self.routeRevision, stateRevision > self.stateRevision,
      routeRevision >= 0, stateRevision >= 0
    else { throw BridgeError.staleRoute }
    try value.validate()
    snapshot = value
    self.routeRevision = routeRevision
    self.stateRevision = stateRevision
  }

  /// 原生完成可用布局量测后进入准备阶段，等待网页恢复布局的确认。
  public mutating func prepare(layoutRevision: Int) throws {
    guard phase == .negotiating, snapshot != nil, layoutRevision >= 0 else {
      throw BridgeError.busy
    }
    self.layoutRevision = layoutRevision
    phase = .prepared
  }

  /// 网页必须确认同一份布局后原生才能显示业务导航。
  public mutating func accept(layoutRevision: Int) throws {
    guard phase == .prepared, layoutRevision == self.layoutRevision else {
      throw BridgeError.invalidMessage
    }
    phase = .nativeNavigation
  }

  /// 先请求网页恢复导航；确认到达前仍保留当前原生出口。
  public mutating func requestRelease() {
    guard phase == .nativeNavigation || phase == .prepared || phase == .negotiating else { return }
    phase = .releasing
  }

  /// 网页确认恢复后撤销所有会话引用与过期动作。
  public mutating func released() {
    guard phase == .releasing else { return }
    beginDocument(allowTakeover: false)
  }

  /// 无法确认 JS 存活时保留恢复状态；不能假设此时网页导航已经恢复。
  public mutating func failed() {
    phase = .recovery
    snapshot = nil
    sessionId = nil
    completedRequests.removeAll()
    requestOrder.removeAll()
  }

  /// 同一文档身份改变后更换会话并撤销旧动作，保留导航外壳直到新快照确认。
  @discardableResult
  public mutating func rotateIdentity() throws -> String {
    guard phase == .nativeNavigation else { throw BridgeError.busy }
    let id = UUID().uuidString
    sessionId = id
    snapshot = nil
    routeRevision = -1
    stateRevision = -1
    completedRequests.removeAll()
    requestOrder.removeAll()
    return id
  }

  /// 用户点击时复核当前会话、路由和动作，较新的展示修订不会自动重放旧命令。
  public func validateAction(
    sessionId: String, routeRevision: Int, actionId: String, ownerId: String
  ) throws {
    guard self.sessionId == sessionId else { throw BridgeError.staleSession }
    guard phase == .nativeNavigation, self.routeRevision == routeRevision else {
      throw BridgeError.staleRoute
    }
    let available =
      snapshot?.actions.contains { action in
        guard action.ownerId == ownerId, action.enabled, !action.loading else { return false }
        return action.actionId == actionId
          || action.menu?.contains { $0.actionId == actionId && $0.enabled } == true
      } == true
    guard available else { throw BridgeError.actionNotAvailable }
  }

  /// 在当前会话内标记已处理消息，有限缓存只负责短期重复分派防护。
  public mutating func markProcessed(_ requestId: String) -> Bool {
    guard BridgeValidator.isIdentifier(requestId), completedRequests.insert(requestId).inserted
    else { return false }
    requestOrder.append(requestId)
    if requestOrder.count > 256 { completedRequests.remove(requestOrder.removeFirst()) }
    return true
  }
}
