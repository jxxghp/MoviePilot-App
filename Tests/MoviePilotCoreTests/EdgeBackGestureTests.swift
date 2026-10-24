import Foundation
import Testing

@testable import MoviePilotCore

/// 验证连续侧滑的提交边界与跨文档、路由及弹窗的过期保护。
struct EdgeBackGestureTests {
  private let identity = EdgeBackIdentity(sessionID: "document-a", routeRevision: 3)

  /// 满足位移或明确快速滑动才返回；取消、短滑和反向移动均不执行。
  @Test func commitsOnlyIntentionalCompletedSwipes() {
    for (distance, velocity, cancelled, expected) in [
      (150.0, 100.0, false, true), (40, 700, false, true),
      (30, 900, false, false), (80, 100, false, false),
      (-120, 700, false, false), (150, 100, true, false),
    ] {
      #expect(
        EdgeBackGesture.shouldCommit(
          distance: distance, velocity: velocity, width: 402, cancelled: cancelled,
          began: identity, current: identity) == expected)
    }
  }

  /// 滑动期间换文档、跳路由、关闭弹窗或失去接管时不得执行旧返回。
  @Test func rejectsChangedNavigationIdentity() {
    for current in [
      nil,
      EdgeBackIdentity(sessionID: "document-b", routeRevision: 3),
      EdgeBackIdentity(sessionID: "document-a", routeRevision: 4),
      EdgeBackIdentity(sessionID: "document-a", routeRevision: 3, sheetID: "sheet-1"),
    ] {
      #expect(
        !EdgeBackGesture.shouldCommit(
          distance: 240, velocity: 800, width: 402, cancelled: false,
          began: identity, current: current))
    }
  }

  /// 非法几何不参与判定，宽窗口的位移门槛不能沿用手机上的固定距离。
  @Test func validatesGeometryAndAdaptsToWidth() {
    for width in [0, -1, Double.infinity, Double.nan, 1024] {
      #expect(
        !EdgeBackGesture.shouldCommit(
          distance: 150, velocity: 100, width: width, cancelled: false,
          began: identity, current: identity))
    }
  }
}
