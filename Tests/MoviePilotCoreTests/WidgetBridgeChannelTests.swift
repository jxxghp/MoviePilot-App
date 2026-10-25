import Foundation
import Testing

@testable import MoviePilotCore

/// 真实 async continuation 和取消任务验证桥接关联，不启动 WebView 或真实后端。
@MainActor
struct WidgetBridgeChannelTests {
  /// 无能力不发送、并发不重放，取消只结束原请求一次。
  @Test func requiresActiveContextAndOneFlight() async throws {
    let host = WidgetChannelHost()
    let channel = host.channel()
    host.context = nil
    do {
      _ = try await channel.request(.context)
      Issue.record("Inactive request was accepted")
    } catch { #expect(error as? WidgetBridgeError == .unsupported) }
    #expect(host.sent.isEmpty)
    host.context = WidgetBridgeContext(document: UUID(), session: "current")
    let first = Task { try await channel.request(.context) }
    try await host.waitForRequests(1)
    do {
      _ = try await channel.request(.context)
      Issue.record("Concurrent request was accepted")
    } catch { #expect(error as? WidgetBridgeError == .busy) }
    #expect(host.sent.count == 1)
    channel.cancel()
    channel.cancel()
    await expectCancelled(first)
    #expect(host.sent.map(\.0) == ["widget.request", "widget.cancel"])
    #expect(host.sent[1].2 == .object(["requestId": .string(host.sent[0].1)]))
  }

  /// 外壳 ID 不代替专用相关 ID；错误会话和重复结果不能完成另一个等待。
  @Test func correlatesResultToTheCurrentRequestOnly() async throws {
    let host = WidgetChannelHost()
    let channel = host.channel()
    let first = Task { try await channel.request(.context) }
    try await host.waitForRequests(1)
    let id = host.sent[0].1
    channel.receive(host.reply(id: "wrong"))
    channel.receive(host.reply(id: id, session: "stale"))
    channel.receive(host.reply(id: id, type: "command.result"))
    channel.receive(host.reply(id: id))
    guard case .context(let context) = try await first.value else {
      Issue.record("Missing context")
      return
    }
    #expect(context.availableContents == [.overview])
    channel.receive(host.reply(id: id))
    let second = Task { try await channel.request(.context) }
    try await host.waitForRequests(2)
    #expect(host.sent[1].1 != id)
    channel.receive(host.reply(id: id))
    channel.cancel(id: id)
    channel.receive(host.reply(id: host.sent[1].1))
    guard case .context = try await second.value else {
      Issue.record("Missing second context")
      return
    }
    #expect(host.sent.count == 2)
  }

  /// 文档更换和后台先使上下文失效，旧结果及取消不会流入新文档。
  @Test func dropsOldDocumentAndBackgroundResults() async throws {
    let host = WidgetChannelHost()
    let channel = host.channel()
    let first = Task { try await channel.request(.context) }
    try await host.waitForRequests(1)
    let id = host.sent[0].1
    host.context = WidgetBridgeContext(document: UUID(), session: "current")
    channel.receive(host.reply(id: id))
    channel.cancel()
    await expectCancelled(first)
    #expect(host.sent.count == 1)
    let second = Task { try await channel.request(.context) }
    try await host.waitForRequests(2)
    host.context = nil
    channel.receive(host.reply(id: host.sent[1].1))
    channel.cancel()
    await expectCancelled(second)
    #expect(host.sent.count == 2)
  }

  /// 调用方取消及真实截止任务均只通知一次，之后还能发送新的独立请求。
  @Test func cancelsFromTheCallerAndDeadline() async throws {
    let host = WidgetChannelHost()
    let channel = host.channel(timeout: 0.03)
    let first = Task { try await channel.request(.context) }
    try await host.waitForRequests(1)
    first.cancel()
    await expectCancelled(first)
    let second = Task { try await channel.request(.context) }
    try await host.waitForRequests(2)
    await expectCancelled(second)
    #expect(
      host.sent.map(\.0) == ["widget.request", "widget.cancel", "widget.request", "widget.cancel"])
    let third = Task { try await channel.request(.context) }
    try await host.waitForRequests(3)
    channel.receive(host.reply(id: host.sent.last!.1, invalid: true))
    do {
      _ = try await third.value
      Issue.record("Invalid result was accepted")
    } catch { #expect(error as? WidgetBridgeError == .invalidData) }
  }

  /// 取消必须结束 continuation，不能只丢弃结果后让调用方永久等待。
  private func expectCancelled(_ task: Task<WidgetBridgeResponse, any Error>) async {
    do {
      _ = try await task.value
      Issue.record("Cancelled request succeeded")
    } catch { #expect(error as? WidgetBridgeError == .cancelled) }
  }
}

/// 可控的原生上下文与发送记录，仅含合成标识，不模拟或绕过来源校验。
@MainActor
private final class WidgetChannelHost {
  var context: WidgetBridgeContext? = WidgetBridgeContext(document: UUID(), session: "current")
  var sent: [(String, String, JSONValue)] = []

  /// 用真实通道与短期限驱动任务，发送记录没有普通命令缓存。
  func channel(timeout: TimeInterval = 1) -> WidgetBridgeChannel {
    WidgetBridgeChannel(
      timeout: timeout, context: { self.context }, send: { self.sent.append(($0, $1, $2)) })
  }

  /// 最多等待一秒让真实主 actor 任务开始，失败不能无限挂住测试进程。
  func waitForRequests(_ count: Int) async throws {
    let deadline = ContinuousClock.now + .seconds(1)
    while sent.filter({ $0.0 == "widget.request" }).count < count, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    try #require(sent.filter { $0.0 == "widget.request" }.count == count)
  }

  /// 网页外壳 ID 独立生成；相关请求 ID 明确位于 payload 中。
  func reply(
    id: String, session: String = "current", type: String = "widget.result", invalid: Bool = false
  ) -> BridgeEnvelope {
    BridgeEnvelope(
      type: type, requestId: UUID().uuidString, sessionId: session,
      payload: .object([
        "requestId": .string(id), "success": .bool(true),
        "data": invalid
          ? .null
          : .object([
            "version": .number(1), "owner": .string(String(repeating: "a", count: 32)),
            "availableContents": .array([.string("overview")]),
          ]),
      ]))
  }
}
