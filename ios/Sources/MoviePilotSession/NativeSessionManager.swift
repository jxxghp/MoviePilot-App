import Combine
import Foundation
import MoviePilotAPI
import MoviePilotCore

/// 原生实例/身份状态的单一所有者；用尝试代次阻止旧认证、旧确认和旧令牌写回。
@MainActor
public final class NativeSessionManager: ObservableObject {
  @Published public private(set) var state: NativeSessionState = .disconnected
  public private(set) var currentSession: NativeSession?
  private let tokens: any SessionTokenStoring
  private let makeAuthentication: (NativeInstance) -> any NativeAuthenticating
  private let makeAPI: (SessionIdentity) throws -> APIClient
  private var selected: NativeInstance?
  private var attempt: Attempt?

  /// 默认适配直接认证和 API；安全存储由既有 iOS TokenStore 注入，不创建第二套库。
  public convenience init(
    tokens: any SessionTokenStoring, language: AppLanguage? = nil
  ) {
    self.init(
      tokens: tokens,
      makeAuthentication: {
        NativeAuthenticationClient(address: $0.address, language: language ?? .current)
      },
      makeAPI: {
        try APIClient(address: $0.address, token: $0.accessToken, language: language ?? .current)
      })
  }

  /// 测试只替换认证时序和受控网络，仍使用真实状态、代次和存储处理。
  init(
    tokens: any SessionTokenStoring,
    makeAuthentication: @escaping (NativeInstance) -> any NativeAuthenticating,
    makeAPI: @escaping (SessionIdentity) throws -> APIClient
  ) {
    self.tokens = tokens
    self.makeAuthentication = makeAuthentication
    self.makeAPI = makeAPI
  }

  /// 选择实例先结束旧会话；初始化确认后才尝试恢复，绝不自动提交记住的密码。
  @discardableResult
  public func connect(_ instance: NativeInstance) async throws -> NativeSession? {
    let pending = try begin(instance, connecting: true)
    do {
      let initialization = try await pending.authentication.initialization()
      try check(pending)
      if case .required(let username) = initialization {
        finish(pending)
        state = .initializationRequired(instance, configuredUsername: username)
        return nil
      }
      guard let token = tokens.read(instance.id) else {
        finish(pending)
        state = .loginRequired(instance, reason: .initial)
        return nil
      }
      let identity = try await pending.authentication.restore(accessToken: token)
      try check(pending)
      guard identity.accessToken == token else { throw NativeSessionFailure.identityMismatch }
      return try activate(identity, attempt: pending, remember: nil)
    } catch {
      try fail(error, attempt: pending, restoring: true)
    }
  }

  /// 只有显式用户提交才调用；新身份成功之前不改变旧保存记录，也不保留密码/OTP。
  @discardableResult
  public func login(
    to instance: NativeInstance, username: String, password: String, otp: String? = nil,
    remember: Bool
  ) async throws -> NativeSession {
    let pending = try begin(instance, connecting: false)
    do {
      let identity = try await pending.authentication.login(
        username: username, password: password, otp: otp)
      try check(pending)
      return try activate(identity, attempt: pending, remember: remember)
    } catch {
      try fail(error, attempt: pending, restoring: false)
    }
  }

  /// 独立探测目标实例是否已启用系统通行密钥登录，不改变当前会话状态机代次。
  public func probePasskeyEnabled(for instance: NativeInstance) async -> Bool {
    let authentication = makeAuthentication(instance)
    defer { authentication.cancel() }
    guard authentication.address == instance.address else { return false }
    return await authentication.passkeyEnabled()
  }

  /// 执行完整通行密钥登录事务（`start` -> 系统认证窗口 -> 一次性回调校验 -> `finish`），尊重尝试代次与保持登录偏好。
  @discardableResult
  public func loginWithPasskey(
    to instance: NativeInstance,
    username: String?,
    state: Data,
    remember: Bool,
    authenticateURL: @MainActor (URL) async throws -> URL
  ) async throws -> NativeSession {
    let pending = try begin(instance, connecting: false)
    do {
      var transaction = try await pending.authentication.beginPasskey(
        username: username, state: state)
      try check(pending)
      let callback = try await authenticateURL(transaction.authorizationURL)
      try check(pending)
      let finishBody = try transaction.finishBody(callback: callback, address: instance.address)
      let identity = try await pending.authentication.finishPasskey(body: finishBody)
      try check(pending)
      return try activate(identity, attempt: pending, remember: remember)
    } catch let failure as PasskeyFailure where failure == .canceled {
      guard attempt?.id == pending.id, selected == pending.instance else {
        throw NativeSessionFailure.superseded
      }
      finish(pending)
      self.state = .loginRequired(pending.instance, reason: .cancelled)
      throw failure
    } catch {
      try fail(error, attempt: pending, restoring: false)
    }
  }

  /// 创建前重新探测；只有本次成功写入才清理旧自动登录，不自动重发或自动登录。
  @discardableResult
  public func initialize(
    _ instance: NativeInstance, username: String, password: String,
    confirmation: String, apiKey: String
  ) async throws -> NativeInitializationResult {
    let pending = try begin(instance, connecting: false)
    state = .initializing(instance)
    do {
      let status = try await pending.authentication.initialization()
      try check(pending)
      guard case .required = status else {
        finish(pending)
        state = .loginRequired(instance, reason: .initial)
        return .alreadyInitialized
      }
      try await pending.authentication.initialize(
        username: username, password: password, confirmation: confirmation, apiKey: apiKey)
      try check(pending)
      guard tokens.remove(instance.id) else { throw NativeSessionFailure.storageUnavailable }
      finish(pending)
      state = .loginRequired(instance, reason: .initial)
      return .created
    } catch {
      try fail(error, attempt: pending, restoring: false)
    }
  }

  /// 只关闭当前连接，保留地址簿和用户选择的保存令牌，供实例切换与暂离使用。
  public func disconnect() {
    endCurrent()
    selected = nil
    state = .disconnected
  }

  /// 注销先终止内存/API 身份，再删除本实例令牌；清理失败明确可见，不影响其它实例。
  public func logout() throws {
    let instance = selected
    endCurrent()
    guard let instance else {
      state = .disconnected
      return
    }
    guard tokens.remove(instance.id) else {
      state = .failed(instance, .storageUnavailable)
      throw NativeSessionFailure.storageUnavailable
    }
    state = .loginRequired(instance, reason: .signedOut)
  }

  /// UI 只能取得当前仍活跃的句柄；保存旧引用的页面仍会在每个动作处再次被检查。
  public func requireSession() throws -> NativeSession {
    guard let currentSession else { throw NativeSessionFailure.notAuthenticated }
    try currentSession.checkActive()
    return currentSession
  }

  /// 尝试对象独占一个认证客户端，不能跨实例复用取消状态、Cookie 或响应。
  private struct Attempt {
    let id: UUID
    let instance: NativeInstance
    let authentication: any NativeAuthenticating
  }

  /// 新尝试在任何 await 之前替换所有者；客户端来源错误时不发送请求。
  private func begin(_ instance: NativeInstance, connecting: Bool) throws -> Attempt {
    try Task.checkCancellation()
    endCurrent()
    selected = instance
    let authentication = makeAuthentication(instance)
    guard authentication.address == instance.address else {
      authentication.cancel()
      state = .failed(instance, .identityMismatch)
      throw NativeSessionFailure.identityMismatch
    }
    let pending = Attempt(id: UUID(), instance: instance, authentication: authentication)
    attempt = pending
    state = connecting ? .connecting(instance) : .authenticating(instance)
    return pending
  }

  /// 取消首先失效代次，后续即使底层忽略取消也无法触及新令牌或新会话。
  private func endCurrent() {
    let previous = attempt
    attempt = nil
    previous?.authentication.cancel()
    currentSession?.invalidate()
    currentSession = nil
  }

  /// 每个网络返回、存储和成功交付前都验证归属；取消优先于任何写入。
  private func check(_ pending: Attempt) throws {
    guard attempt?.id == pending.id, selected == pending.instance else {
      throw NativeSessionFailure.superseded
    }
    try Task.checkCancellation()
  }

  /// 未获得身份的尝试结束后不再保留其网络客户端。
  private func finish(_ pending: Attempt) {
    guard attempt?.id == pending.id else { return }
    attempt = nil
    pending.authentication.cancel()
  }

  /// 先准备网络、再同步处理保持登录，最后一次性交付不含 credential 的观察状态。
  private func activate(
    _ identity: SessionIdentity, attempt pending: Attempt, remember: Bool?
  ) throws -> NativeSession {
    try check(pending)
    guard identity.address == pending.instance.address else {
      throw NativeSessionFailure.identityMismatch
    }
    let api = try makeAPI(identity)
    let session = NativeSession(
      instance: pending.instance, identity: identity, generation: pending.id, api: api,
      authentication: pending.authentication,
      onInvalidated: { [weak self] scope, reason in self?.expire(scope, reason: reason) },
      onUserChanged: { [weak self] scope in self?.refreshSnapshot(scope) })
    if let remember {
      guard tokens.remove(pending.instance.id) else {
        throw NativeSessionFailure.storageUnavailable
      }
      if remember {
        do {
          try tokens.save(identity.accessToken, for: pending.instance.id)
        } catch {
          _ = tokens.remove(pending.instance.id)
          throw NativeSessionFailure.storageUnavailable
        }
      }
    }
    attempt = nil
    currentSession = session
    state = .authenticated(session.snapshot)
    return session
  }

  /// 过期只处理匹配的当前代次，不能由旧账号的迟到 401 删除新账号安全记录。
  private func expire(_ scope: NativeSessionScope, reason: NativeSessionFailure) {
    guard let session = currentSession, session.scope == scope else { return }
    let instance = session.instance
    session.invalidate()
    currentSession = nil
    guard tokens.remove(instance.id) else {
      state = .failed(instance, .storageUnavailable)
      return
    }
    state =
      reason == .api(.unauthorized)
      ? .loginRequired(instance, reason: .expired) : .failed(instance, reason)
  }

  /// 服务端权限更新后只发布仍属于当前账号的快照。
  private func refreshSnapshot(_ scope: NativeSessionScope) {
    guard let session = currentSession, session.scope == scope else { return }
    state = .authenticated(session.snapshot)
  }

  /// 失败仅作用于自己的尝试；网络/403 保留令牌，恢复 401 才清理过期记录。
  private func fail(
    _ error: any Error, attempt pending: Attempt, restoring: Bool
  ) throws -> Never {
    guard attempt?.id == pending.id, selected == pending.instance else {
      throw NativeSessionFailure.superseded
    }
    finish(pending)
    if error is CancellationError {
      state = .loginRequired(pending.instance, reason: .cancelled)
      throw error
    }
    if restoring,
      (error as? APIError) == .unauthorized || (error as? APIError) == .invalidCredential
        || (error as? NativeAuthenticationError) == .inactiveAccount
    {
      guard tokens.remove(pending.instance.id) else {
        state = .failed(pending.instance, .storageUnavailable)
        throw NativeSessionFailure.storageUnavailable
      }
      state = .loginRequired(pending.instance, reason: .expired)
    } else if case .verificationRequired(let methods) = error as? NativeAuthenticationError {
      state = .verificationRequired(pending.instance, methods: methods)
    } else {
      let reason: NativeSessionFailure
      if let failure = error as? NativeSessionFailure {
        reason = failure
      } else if let authentication = error as? NativeAuthenticationError {
        reason = .authentication(authentication)
      } else {
        reason = .api(error as? APIError ?? .unavailable)
      }
      state = .failed(pending.instance, reason)
    }
    throw error
  }
}
