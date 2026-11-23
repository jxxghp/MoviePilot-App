import Foundation

/// 一次边缘手势绑定当前文档、路由及弹窗，完成时不得作用于后来打开的页面。
public struct EdgeBackIdentity: Equatable, Sendable {
  public let sessionID: String
  public let routeRevision: Int
  public let sheetID: String?

  /// 身份由已确认的桥接快照提供，不建立另一份业务返回栈。
  public init(sessionID: String, routeRevision: Int, sheetID: String? = nil) {
    self.sessionID = sessionID
    self.routeRevision = routeRevision
    self.sheetID = sheetID
  }
}

/// UIKit 左边缘连续手势仅在有效完成后提交返回，短滑、取消或上下文变化均保持原页。
public enum EdgeBackGesture {
  /// 位移门槛适配窗口宽度，明确向右的快速滑动仍需最小位移以避免边缘误触。
  public static func shouldCommit(
    distance: Double, velocity: Double, width: Double, cancelled: Bool,
    began: EdgeBackIdentity, current: EdgeBackIdentity?
  ) -> Bool {
    guard !cancelled, began == current, distance.isFinite, velocity.isFinite, width.isFinite,
      width > 0, distance > 0
    else { return false }
    return distance >= max(72, width * 0.28) || (distance >= 36 && velocity >= 650)
  }
}
