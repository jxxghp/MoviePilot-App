import Foundation

/// 原生提供的当前文档和已协商会话，不能从网页载荷中推定。
public struct WidgetBridgeContext: Equatable, Sendable {
  public let document: UUID
  public let session: String

  /// 生命周期与来源由协调器确认后才构造，用于请求等待期间的再次比对。
  public init(document: UUID, session: String) {
    self.document = document
    self.session = session
  }
}

/// 一次性 Widget 请求通道；与普通业务命令的重放、确认和缓存完全独立。
@MainActor
public final class WidgetBridgeChannel {
  private let context: () -> WidgetBridgeContext?
  private let send: (String, String, JSONValue) -> Void
  private let timeout: TimeInterval
  private var pending: Pending?

  /// 仅保留一个有界等待，超时任务弱引用通道，销毁不会延长旧文档生命周期。
  private struct Pending {
    let id: String
    let context: WidgetBridgeContext
    let operation: WidgetBridgeOperation
    let deadline: Task<Void, Never>
    let continuation: CheckedContinuation<WidgetBridgeResponse, any Error>
  }

  /// 生产固定 15 秒；获取上下文和发送方法都由当前协调器注入。
  public convenience init(
    context: @escaping () -> WidgetBridgeContext?,
    send: @escaping (String, String, JSONValue) -> Void
  ) {
    self.init(timeout: 15, context: context, send: send)
  }

  /// 测试只缩短期限，不用真实网页或系统计时器控制生命周期边界。
  init(
    timeout: TimeInterval, context: @escaping () -> WidgetBridgeContext?,
    send: @escaping (String, String, JSONValue) -> Void
  ) {
    self.timeout = min(15, max(0.001, timeout))
    self.context = context
    self.send = send
  }

  /// 每次新建随机请求 ID；取消、超时和并发请求都不能自动重放登记。
  public func request(_ operation: WidgetBridgeOperation) async throws -> WidgetBridgeResponse {
    let id = UUID().uuidString
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        guard let current = context() else {
          continuation.resume(throwing: WidgetBridgeError.unsupported)
          return
        }
        guard pending == nil else {
          continuation.resume(throwing: WidgetBridgeError.busy)
          return
        }
        let deadline = Task { [weak self, timeout] in
          do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
          self?.cancel(id: id)
        }
        pending = Pending(
          id: id, context: current, operation: operation, deadline: deadline,
          continuation: continuation)
        send("widget.request", id, operation.payload)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel(id: id) }
    }
  }

  /// 来源外壳已被协调器验证；仍须核对当前文档、会话和独立 payload.requestId。
  public func receive(_ message: BridgeEnvelope) {
    guard let value = pending, context() == value.context, message.type == "widget.result",
      message.sessionId == value.context.session, case .object(var fields) = message.payload,
      fields.removeValue(forKey: "requestId") == .string(value.id)
    else { return }
    pending = nil
    value.deadline.cancel()
    do {
      value.continuation.resume(
        returning: try WidgetBridgeResponse.decode(.object(fields), for: value.operation))
    } catch { value.continuation.resume(throwing: error) }
  }

  /// 只结束匹配的等待；旧取消任务不能取消后来请求，也不向新文档发送旧 ID。
  public func cancel(id: String? = nil) {
    guard let value = pending, id == nil || id == value.id else { return }
    pending = nil
    value.deadline.cancel()
    if context() == value.context {
      send("widget.cancel", UUID().uuidString, .object(["requestId": .string(value.id)]))
    }
    value.continuation.resume(throwing: WidgetBridgeError.cancelled)
  }
}
