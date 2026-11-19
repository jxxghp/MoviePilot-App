import Foundation
import MoviePilotCore
import Testing

@testable import MoviePilotAPI
@testable import MoviePilotSession

/// 仅保存合成令牌的主线程存储，记录 UUID 归属和可控的 Keychain 失败。
@MainActor
final class SessionTestTokenStore: SessionTokenStoring {
  var values: [UUID: String] = [:]
  var readIDs: [UUID] = []
  var removedIDs: [UUID] = []
  var savedIDs: [UUID] = []
  var failingRemoval: Set<UUID> = []
  var failsSaving = false

  /// 读取只按 UUID，不从另一个实例或地址键回退。
  func read(_ instanceID: UUID) -> String? {
    readIDs.append(instanceID)
    return values[instanceID]
  }

  /// 失败发生在写入之前，用于检查新身份不会背后保留旧自动登录。
  func save(_ token: String, for instanceID: UUID) throws {
    savedIDs.append(instanceID)
    if failsSaving { throw NativeSessionFailure.storageUnavailable }
    values[instanceID] = token
  }

  /// 模拟系统拒绝清理时保留记录，调用方必须明确失败。
  func remove(_ instanceID: UUID) -> Bool {
    removedIDs.append(instanceID)
    if failingRemoval.contains(instanceID) { return false }
    values.removeValue(forKey: instanceID)
    return true
  }
}

/// 故意忽略 cancel 的认证适配器，验证状态机不能只依靠底层取消保证正确性。
final class ControlledAuthentication: NativeAuthenticating, @unchecked Sendable {
  let address: ServerAddress
  private let lock = NSLock()
  private var response: Result<SessionIdentity, any Error>
  private var initializationResult: Result<NativeInitialization, any Error> = .success(.ready)
  private var initializationHeld = false
  private var initializationWaiters: [CheckedContinuation<NativeInitialization, any Error>] = []
  private var held = false
  private var waiting: [CheckedContinuation<SessionIdentity, any Error>] = []
  private var loginInvocations = 0
  private var restored: [String] = []
  private var cancelled = 0

  /// 每个测试客户端固定一个地址，不允许配置响应时偷偷改掉来源。
  init(instance: NativeInstance, userID: Int = 3, token: String = "synthetic.session") throws {
    address = instance.address
    let user = try SessionUser(id: userID, name: "reader-\(userID)", isSuperuser: false)
    response = .success(try SessionIdentity(address: address, user: user, accessToken: token))
  }

  /// 初始化不运行网络，可显式配置未初始化、旧接口或失败。
  func initialization() async throws -> NativeInitialization {
    try await withCheckedThrowingContinuation { continuation in
      let value: Result<NativeInitialization, any Error>? = lock.withLock {
        if initializationHeld {
          initializationWaiters.append(continuation)
          return nil
        }
        return initializationResult
      }
      if let value { continuation.resume(with: value) }
    }
  }

  /// 只记录提交次数，不保存用户名、密码或 OTP，延迟结果由测试显式结算。
  func login(username: String, password: String, otp: String?) async throws -> SessionIdentity {
    lock.withLock { loginInvocations += 1 }
    return try await answer()
  }

  /// 保存的合成令牌用于归属断言，不参与自行解码或构造用户。
  func restore(accessToken: String) async throws -> SessionIdentity {
    lock.withLock { restored.append(accessToken) }
    let value = try await answer()
    return try SessionIdentity(address: value.address, user: value.user, accessToken: accessToken)
  }

  /// 有意不结束 continuation，模拟取消失效后仍到达的旧成功或旧 401。
  func cancel() { lock.withLock { cancelled += 1 } }

  /// 配置接下来的认证结果，不改变已经挂起的调用。
  func configure(
    _ value: Result<SessionIdentity, any Error>, hold: Bool = false,
    initialization: Result<NativeInitialization, any Error> = .success(.ready)
  ) {
    lock.withLock {
      response = value
      held = hold
      initializationResult = initialization
    }
  }

  /// 返回锁保护的观测值，不能因为 mock 自己的竞态误判状态机。
  var loginCount: Int { lock.withLock { loginInvocations } }
  var restoreTokens: [String] { lock.withLock { restored } }
  var cancellationCount: Int { lock.withLock { cancelled } }
  var pendingCount: Int { lock.withLock { waiting.count } }
  var pendingInitializationCount: Int { lock.withLock { initializationWaiters.count } }

  /// 初始化探测也可忽略取消，用于验证读取保存令牌之前的代次门槛。
  func holdInitialization() { lock.withLock { initializationHeld = true } }

  /// 结算挂起的初始化，不代替产品代码执行任何状态修改。
  func resolveInitialization(_ value: Result<NativeInitialization, any Error>) {
    let callbacks = lock.withLock {
      let callbacks = initializationWaiters
      initializationWaiters = []
      return callbacks
    }
    for callback in callbacks { callback.resume(with: value) }
  }

  /// 结算全部挂起请求，测试即使提前失败也可用 defer 释放 continuation。
  func resolve(_ value: Result<SessionIdentity, any Error>) {
    let callbacks = lock.withLock {
      let callbacks = waiting
      waiting = []
      return callbacks
    }
    for callback in callbacks { callback.resume(with: value) }
  }

  /// 可乱序返回同一会话的权限刷新，验证旧成功或旧 401 都不能覆盖新确认结果。
  func resolveOne(_ value: Result<SessionIdentity, any Error>, newest: Bool = false) {
    let callback = lock.withLock {
      guard !waiting.isEmpty else {
        return Optional<CheckedContinuation<SessionIdentity, any Error>>.none
      }
      return newest ? waiting.removeLast() : waiting.removeFirst()
    }
    callback?.resume(with: value)
  }

  /// 有界等待明确的 mock 句柄出现，不用固定长 sleep 猜测执行顺序。
  func waitUntilPending(_ count: Int = 1) async throws {
    for _ in 0..<200 {
      if pendingCount >= count { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw SessionFixtureError.requestNotStarted
  }

  /// 初始化只在句柄确实挂起后才允许切换实例，不用超时假装请求已开始。
  func waitUntilInitializing() async throws {
    for _ in 0..<200 {
      if pendingInitializationCount > 0 { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw SessionFixtureError.requestNotStarted
  }

  /// 所有响应都穿过同一个可控时序边界，立即返回与忽略取消的返回都可验证。
  private func answer() async throws -> SessionIdentity {
    try await withCheckedThrowingContinuation { continuation in
      let value: Result<SessionIdentity, any Error>? = lock.withLock {
        if held {
          waiting.append(continuation)
          return nil
        }
        return response
      }
      if let value { continuation.resume(with: value) }
    }
  }
}

/// 夹具等待有明确上界，不把观察超时当作产品已完成。
enum SessionFixtureError: Error { case requestNotStarted }

/// 生命周期测试的协议状态独立于认证测试，两个 suite 并行时不会互相覆盖。
final class LifecycleHTTPProtocol: URLProtocol, @unchecked Sendable {
  static let state = NativeHTTPState()
  private static let held = HeldRequests()

  /// 任何错误目标都留在本进程，不让测试访问真实网络。
  override class func canInit(with request: URLRequest) -> Bool { true }

  /// 保留被测实际路径和身份，不在夹具里纠正它们。
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  /// 可挂起真正 URLSession 请求，以覆盖权限刷新或实例切换发生在网络返回之前。
  override func startLoading() {
    let reply = Self.state.answer(request, body: request.httpBody ?? Data())
    if reply.hold {
      Self.held.insert(self)
    } else {
      deliver(reply)
    }
  }

  /// URLSession 取消后不再持有协议实例，也不向已停止的任务追加假响应。
  override func stopLoading() { Self.held.remove(self) }

  /// 只释放当前仍挂起的合成请求，调用方必须先验证它确实已开始。
  static func completeHeld(body: Data) {
    let reply = NativeHTTPReply(
      status: 200, body: body, headers: ["Content-Type": "application/json"],
      redirect: nil, hold: false, error: nil)
    for request in held.takeAll() { request.deliver(reply) }
  }

  /// 有界等待网络请求到达，供取消和权限变更测试建立真实先后关系。
  static func waitUntilRequested() async throws {
    for _ in 0..<200 {
      if !state.requests().isEmpty, held.hasRequests { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw SessionFixtureError.requestNotStarted
  }

  /// 通过系统协议回调交付完整响应，不直接注入 NativeSession 的成功状态。
  private func deliver(_ reply: NativeHTTPReply) {
    if let error = reply.error {
      client?.urlProtocol(self, didFailWithError: URLError(error))
      return
    }
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  /// 协议实例的持有/取消也受锁保护，避免清理时回调已停止的请求。
  private final class HeldRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ObjectIdentifier: LifecycleHTTPProtocol] = [:]

    /// 先等协议已被保留，再允许测试改变权限或触发返回，避免微小时序窗口。
    var hasRequests: Bool { lock.withLock { !values.isEmpty } }

    /// 保留尚未返回的协议请求，不记录凭据或其它实例状态。
    func insert(_ value: LifecycleHTTPProtocol) {
      lock.withLock { values[ObjectIdentifier(value)] = value }
    }

    /// 停止后移除该请求，后续 completeHeld 不再看到它。
    func remove(_ value: LifecycleHTTPProtocol) {
      _ = lock.withLock { values.removeValue(forKey: ObjectIdentifier(value)) }
    }

    /// 原子取出所有可交付请求，清空后避免重复返回。
    func takeAll() -> [LifecycleHTTPProtocol] {
      lock.withLock {
        let result = Array(values.values)
        values = [:]
        return result
      }
    }
  }
}

/// 共用构造器保持测试使用真实 APIClient，只有网络与认证时序由夹具替代。
@MainActor
enum SessionLifecycleTestData {
  /// 实例 ID 显式固定，证明归属不是从 URL 字符串临时生成的。
  static func instance(_ host: String = "a.test", id: UUID = UUID()) throws -> NativeInstance {
    NativeInstance(id: id, address: try ServerAddress("https://\(host)/moviepilot/"))
  }

  /// 合成响应与当前用户地址绑定，令牌只用于此测试。
  static func identity(
    _ instance: NativeInstance, id: Int = 3, token: String = "synthetic.session",
    permissions: NativePermissions = NativePermissions()
  ) throws -> SessionIdentity {
    try SessionIdentity(
      address: instance.address,
      user: SessionUser(id: id, name: "reader-\(id)", isSuperuser: false, permissions: permissions),
      accessToken: token)
  }

  /// 每个尝试从明确队列取得新认证客户端；意外重试会被记录为失败。
  static func manager(
    tokens: SessionTestTokenStore, clients: [ControlledAuthentication]
  ) -> NativeSessionManager {
    var queue = clients
    let fallback = clients[0]
    return NativeSessionManager(
      tokens: tokens,
      makeAuthentication: { _ in
        guard !queue.isEmpty else {
          Issue.record("认证客户端创建次数超出明确的用户动作")
          return fallback
        }
        return queue.removeFirst()
      },
      makeAPI: { identity in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifecycleHTTPProtocol.self]
        return try APIClient(
          address: identity.address, token: identity.accessToken, configuration: configuration)
      })
  }
}
