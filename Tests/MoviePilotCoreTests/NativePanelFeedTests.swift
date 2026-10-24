import Foundation
import Testing

@testable import MoviePilotCore

/// 连续通知的展示状态独立于业务查询，验证追加、回看、会话撤销和加载背压。
struct NativePanelFeedTests {
  /// 历史分片追加且不重复，回看旧行的展开更新不会丢失后面的内容或恢复旧工具状态。
  @Test func accumulatesAndUpdatesRows() throws {
    var state = NativePanelFeedState()
    _ = state.apply(try panel(ids: ["a", "b"]))
    let appended = state.apply(try panel(ids: ["b", "c"], offset: 2, revision: 1))
    #expect(appended[1].items.map(\.id) == ["a", "b", "c"])
    let updated = state.apply(try panel(ids: ["a"], revision: 1, suffix: "展开"))
    #expect(updated[1].items.map(\.id) == ["a", "b", "c"])
    #expect(updated[1].items[0].title == "a展开")
    #expect(updated[0].items[0].title == "已读展开")
    #expect(state.isEmpty == false)
  }

  /// SSE 首片新消息放到顶部，其余已加载通知继续保留供向上回看。
  @Test func prependsLiveMessages() throws {
    var state = NativePanelFeedState()
    _ = state.apply(try panel(ids: ["a", "b"]))
    _ = state.apply(try panel(ids: ["c"], offset: 2, revision: 1))
    let result = state.apply(try panel(ids: ["new", "a"], revision: 1))
    #expect(result[1].items.map(\.id) == ["new", "a", "b", "c"])
  }

  /// 清理或重新打开以新会话撤销旧数据，旧版无分片声明仍完整保留原面板。
  @Test func clearsOnSessionChangeAndLegacyPanel() throws {
    var state = NativePanelFeedState()
    _ = state.apply(try panel(ids: ["a"]))
    let cleared = state.apply(try panel(ids: [], session: "next"))
    #expect(cleared[1].items.isEmpty)
    #expect(state.isEmpty)
    let legacy = try JSONDecoder().decode(
      NativePanelSnapshot.self, from: Data(#"{"title":"菜单","sections":[]}"#.utf8))
    #expect(state.apply(legacy).isEmpty)
    #expect(state.requestMore(isNearEnd: true) == false)
  }

  /// 滚动连发和无关快照不能重入同一次请求；明确完成后才能继续。
  @Test func waitsForCompletionRevision() throws {
    var state = NativePanelFeedState()
    _ = state.apply(try panel(ids: ["a"]))
    #expect(state.requestMore(isNearEnd: false) == false)
    #expect(state.requestMore(isNearEnd: true) == true)
    #expect(state.requestMore(isNearEnd: true) == false)
    _ = state.apply(try panel(ids: ["a"], loading: true))
    #expect(state.requestMore(isNearEnd: true) == false)
    _ = state.apply(try panel(ids: ["a"], suffix: "已读"))
    #expect(state.requestMore(isNearEnd: true) == false)
    _ = state.apply(try panel(ids: ["b"], offset: 1, revision: 1))
    #expect(state.requestMore(isNearEnd: true) == true)
  }

  /// 失败仅允许用户重试，加载中不连发；真实末尾和新会话不能承接旧请求。
  @Test func retriesOnlyExplicitlyAndStopsAtEnd() throws {
    var state = NativePanelFeedState()
    _ = state.apply(try panel(ids: ["a"], error: "失败"))
    #expect(state.requestMore(isNearEnd: true) == false)
    #expect(state.requestMore(isNearEnd: false, retry: true) == true)
    #expect(state.requestMore(isNearEnd: true, retry: true) == false)
    _ = state.apply(try panel(ids: ["a"], revision: 1, more: false))
    #expect(state.requestMore(isNearEnd: true, retry: true) == false)
    _ = state.apply(try panel(ids: ["new"], session: "next"))
    #expect(state.requestMore(isNearEnd: true) == true)
  }

  /// 使用实际解码协议构造最小分片，工具行与通知内容保持独立。
  private func panel(
    ids: [String], offset: Int = 0, revision: Int = 0, session: String = "current",
    loading: Bool = false, more: Bool = true, error: String? = nil, suffix: String = ""
  ) throws -> NativePanelSnapshot {
    var object: [String: Any] = [
      "title": "通知", "loading": loading, "hasMore": more,
      "feed": ["id": session, "offset": offset, "revision": revision, "sectionIds": ["messages"]],
      "sections": [
        ["id": "tools", "items": [["id": "read", "title": "已读\(suffix)"]]],
        ["id": "messages", "items": ids.map { ["id": $0, "title": $0 + suffix] }],
      ],
    ]
    object["loadError"] = error
    return try JSONDecoder().decode(
      NativePanelSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
