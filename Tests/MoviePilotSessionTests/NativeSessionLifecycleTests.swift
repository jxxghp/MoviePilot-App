import Foundation
import MoviePilotAPI
import Testing

@testable import MoviePilotSession

/// 时序测试刻意让旧认证忽略取消，网络测试仍使用真实 URLSession。
@Suite(.serialized)
@MainActor
struct NativeSessionLifecycleTests {
  /// 未初始化不读取或发送旧令牌，无保存令牌时显示原生登录状态。
  @Test func separatesInitializationAndLoginRequirements() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    store.values[instance.id] = "synthetic.old"
    let required = try ControlledAuthentication(instance: instance)
    required.configure(
      .failure(APIError.unauthorized),
      initialization: .success(.required(configuredUsername: "fixed-admin")))
    let ready = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [required, ready])
    #expect(try await manager.connect(instance) == nil)
    #expect(manager.state == .initializationRequired(instance, configuredUsername: "fixed-admin"))
    #expect(store.readIDs.isEmpty && required.restoreTokens.isEmpty)
    store.values = [:]
    #expect(try await manager.connect(instance) == nil)
    #expect(manager.state == .loginRequired(instance, reason: .initial))
    #expect(ready.loginCount == 0 && ready.restoreTokens.isEmpty)
  }

  /// 只有服务器身份成功后才写保持登录，稳定实例 UUID 不由地址重新生成。
  @Test func authenticatesAndUsesTheExistingUUIDSlot() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let other = UUID()
    let store = SessionTestTokenStore()
    store.values = [instance.id: "synthetic.old-user", other: "synthetic.other"]
    let auth = try ControlledAuthentication(instance: instance, token: "synthetic.new-user")
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try await manager.login(
      to: instance, username: "reader", password: "synthetic-only", remember: true)
    #expect(session.scope.instanceID == instance.id && session.scope.userID == 3)
    #expect(manager.state == .authenticated(session.snapshot))
    #expect(store.values == [instance.id: "synthetic.new-user", other: "synthetic.other"])
    #expect(store.removedIDs == [instance.id] && store.savedIDs == [instance.id])
    #expect(auth.loginCount == 1)
  }

  /// A→B→A 全部恢复后，保存记录独立且旧会话句柄与确认无法复用。
  @Test func switchesBetweenInstancesWithNewGenerations() async throws {
    let a = try SessionLifecycleTestData.instance()
    let b = try SessionLifecycleTestData.instance("b.test")
    let store = SessionTestTokenStore()
    store.values = [a.id: "synthetic.a", b.id: "synthetic.b"]
    let firstA = try ControlledAuthentication(instance: a, token: "synthetic.a")
    let firstB = try ControlledAuthentication(instance: b, userID: 4, token: "synthetic.b")
    let secondA = try ControlledAuthentication(instance: a, token: "synthetic.a")
    let manager = SessionLifecycleTestData.manager(
      tokens: store, clients: [firstA, firstB, secondA])
    let oldA = try #require(try await manager.connect(a))
    let sessionB = try #require(try await manager.connect(b))
    #expect(throws: NativeSessionFailure.invalidated) { try oldA.checkActive() }
    let newA = try #require(try await manager.connect(a))
    #expect(throws: NativeSessionFailure.invalidated) { try sessionB.checkActive() }
    #expect(newA.scope.generation != oldA.scope.generation)
    #expect(newA.scope.instanceID == oldA.scope.instanceID)
    #expect(manager.currentSession === newA)
    #expect(firstA.restoreTokens == ["synthetic.a"] && firstB.restoreTokens == ["synthetic.b"])
    #expect(store.values == [a.id: "synthetic.a", b.id: "synthetic.b"])
    #expect(store.removedIDs.isEmpty && store.savedIDs.isEmpty)
  }

  /// 同实例 B 登录迟到时，不能覆盖随后 C 的身份或删除 C 已保存的令牌。
  @Test func ignoresSupersededLoginEvenWhenCancellationIsIgnored() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    let b = try ControlledAuthentication(instance: instance, userID: 4, token: "synthetic.b")
    let c = try ControlledAuthentication(instance: instance, userID: 5, token: "synthetic.c")
    let identityB = try SessionLifecycleTestData.identity(instance, id: 4, token: "synthetic.b")
    b.configure(.success(identityB), hold: true)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [b, c])
    let lateB = Task {
      try await manager.login(
        to: instance, username: "b", password: "synthetic-only", remember: true)
    }
    defer { b.resolve(.failure(CancellationError())) }
    try await b.waitUntilPending()
    let currentC = try await manager.login(
      to: instance, username: "c", password: "synthetic-only", remember: true)
    b.resolve(.success(identityB))
    await #expect(throws: NativeSessionFailure.superseded) { try await lateB.value }
    #expect(manager.currentSession === currentC && currentC.user.id == 5)
    #expect(store.values[instance.id] == "synthetic.c")
    #expect(store.savedIDs == [instance.id] && store.removedIDs == [instance.id])
    #expect(b.cancellationCount > 0)
  }

  /// 注销发生在成功响应之前时，忽略取消的旧成功也不能重新建立会话。
  @Test func logoutWinsAgainstLateAuthentication() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let other = UUID()
    let store = SessionTestTokenStore()
    store.values = [instance.id: "synthetic.old", other: "synthetic.other"]
    let auth = try ControlledAuthentication(instance: instance)
    let identity = try SessionLifecycleTestData.identity(instance)
    auth.configure(.success(identity), hold: true)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let task = Task {
      try await manager.login(
        to: instance, username: "reader", password: "synthetic-only", remember: true)
    }
    defer { auth.resolve(.failure(CancellationError())) }
    try await auth.waitUntilPending()
    try manager.logout()
    auth.resolve(.success(identity))
    await #expect(throws: NativeSessionFailure.superseded) { try await task.value }
    #expect(manager.state == .loginRequired(instance, reason: .signedOut))
    #expect(manager.currentSession == nil && store.values == [other: "synthetic.other"])
    #expect(store.savedIDs.isEmpty)
  }

  /// 调用任务取消后即使收到了成功，也不写 Keychain 或发布已认证状态。
  @Test func callerCancellationPreventsPersistence() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    let auth = try ControlledAuthentication(instance: instance)
    let identity = try SessionLifecycleTestData.identity(instance)
    auth.configure(.success(identity), hold: true)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let task = Task {
      try await manager.login(
        to: instance, username: "reader", password: "synthetic-only", remember: true)
    }
    defer { auth.resolve(.failure(CancellationError())) }
    try await auth.waitUntilPending()
    task.cancel()
    auth.resolve(.success(identity))
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(manager.state == .loginRequired(instance, reason: .cancelled))
    #expect(store.values.isEmpty && store.savedIDs.isEmpty && store.removedIDs.isEmpty)
  }

  /// 早已取消的旧页面任务不能在进入协调器时结束当前仍有效的实例。
  @Test func preCancelledTaskDoesNotReplaceTheCurrentSession() async throws {
    let a = try SessionLifecycleTestData.instance()
    let b = try SessionLifecycleTestData.instance("b.test")
    let store = SessionTestTokenStore()
    store.values[a.id] = "synthetic.a"
    let authA = try ControlledAuthentication(instance: a)
    let authB = try ControlledAuthentication(instance: b)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [authA, authB])
    let sessionA = try #require(try await manager.connect(a))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await manager.connect(b)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(
      manager.currentSession === sessionA && manager.state == .authenticated(sessionA.snapshot))
    #expect(authA.cancellationCount == 0 && authB.restoreTokens.isEmpty)
    #expect(store.values == [a.id: "synthetic.a"] && store.removedIDs.isEmpty)
  }

  /// 恢复 401 才清理过期记录；离线和 403 保留保存令牌且不自动重试。
  @Test(arguments: [APIError.unauthorized, .forbidden, .unavailable])
  func separatesRestoreFailureAndRevocation(_ error: APIError) async throws {
    let instance = try SessionLifecycleTestData.instance()
    let other = UUID()
    let store = SessionTestTokenStore()
    store.values = [instance.id: "synthetic.saved", other: "synthetic.other"]
    let auth = try ControlledAuthentication(instance: instance)
    auth.configure(.failure(error))
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    await #expect(throws: error) { try await manager.connect(instance) }
    if error == .unauthorized {
      #expect(manager.state == .loginRequired(instance, reason: .expired))
      #expect(store.values[instance.id] == nil && store.removedIDs == [instance.id])
    } else {
      #expect(manager.state == .failed(instance, .api(error)))
      #expect(store.values[instance.id] == "synthetic.saved" && store.removedIDs.isEmpty)
    }
    #expect(store.values[other] == "synthetic.other" && auth.restoreTokens.count == 1)
  }

  /// 不保持登录必须真正移除旧账号记录，断开连接不顺带删除其它实例。
  @Test func clearsOldCredentialsWhenRememberIsDisabled() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let other = UUID()
    let store = SessionTestTokenStore()
    store.values = [instance.id: "synthetic.old-account", other: "synthetic.other"]
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try await manager.login(
      to: instance, username: "reader", password: "synthetic-only", remember: false)
    #expect(store.values == [other: "synthetic.other"] && store.savedIDs.isEmpty)
    manager.disconnect()
    #expect(manager.state == .disconnected)
    #expect(throws: NativeSessionFailure.invalidated) { try session.checkActive() }
    #expect(store.values == [other: "synthetic.other"])
  }

  /// 清理失败不能背后继续用旧账号保持登录；写入失败也不发布新身份。
  @Test(arguments: [false, true])
  func failsClosedWhenSecureStorageFails(_ failsSaving: Bool) async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    store.values[instance.id] = "synthetic.old-account"
    if failsSaving { store.failsSaving = true } else { store.failingRemoval.insert(instance.id) }
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    await #expect(throws: NativeSessionFailure.storageUnavailable) {
      try await manager.login(
        to: instance, username: "reader", password: "synthetic-only", remember: true)
    }
    #expect(
      manager.currentSession == nil && manager.state == .failed(instance, .storageUnavailable))
    #expect(throws: NativeSessionFailure.notAuthenticated) { try manager.requireSession() }
    if failsSaving {
      #expect(store.values[instance.id] == nil)
    } else {
      #expect(store.values[instance.id] == "synthetic.old-account" && store.savedIDs.isEmpty)
    }
  }

  /// 退出清理失败时，旧内存句柄仍立即失效，不能因 Keychain 错误继续操作。
  @Test func invalidatesMemoryEvenWhenLogoutStorageFails() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    store.values[instance.id] = "synthetic.saved"
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try #require(try await manager.connect(instance))
    store.failingRemoval.insert(instance.id)
    #expect(throws: NativeSessionFailure.storageUnavailable) { try manager.logout() }
    #expect(throws: NativeSessionFailure.invalidated) { try session.checkActive() }
    #expect(
      manager.currentSession == nil && manager.state == .failed(instance, .storageUnavailable))
  }

  /// 多验证方式只改变等待用户输入的状态，不保存令牌或继续发出密码请求。
  @Test func exposesMFAWithoutSavingAnIdentity() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    let auth = try ControlledAuthentication(instance: instance)
    let challenge = NativeAuthenticationError.verificationRequired(methods: ["otp", "passkey"])
    auth.configure(.failure(challenge))
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    await #expect(throws: challenge) {
      try await manager.login(
        to: instance, username: "reader", password: "synthetic-only", remember: true)
    }
    #expect(manager.state == .verificationRequired(instance, methods: ["otp", "passkey"]))
    #expect(store.savedIDs.isEmpty && store.removedIDs.isEmpty && auth.loginCount == 1)
  }

  /// 当前 API 403 保留会话，401 只终止本代次与对应实例记录。
  @Test(arguments: [403, 401])
  func handlesAPIAuthenticationFailuresPerSession(_ status: Int) async throws {
    let instance = try SessionLifecycleTestData.instance()
    let other = UUID()
    let store = SessionTestTokenStore()
    store.values = [instance.id: "synthetic.saved", other: "synthetic.other"]
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try #require(try await manager.connect(instance))
    LifecycleHTTPProtocol.state.prepare(status: status)
    await #expect(throws: status == 401 ? APIError.unauthorized : .forbidden) {
      try await session.request(APIEndpoint(path: ["media", "search"]), as: Int.self)
    }
    if status == 401 {
      #expect(manager.currentSession == nil && store.values[instance.id] == nil)
      #expect(manager.state == .loginRequired(instance, reason: .expired))
    } else {
      #expect(manager.currentSession === session && store.values[instance.id] == "synthetic.saved")
    }
    #expect(store.values[other] == "synthetic.other")
    #expect(LifecycleHTTPProtocol.state.requests().count == 1)
  }

  /// 权限刷新后，旧确认句柄不能在发出新请求时继续使用原权限。
  @Test func rechecksPermissionsAfterConfirmation() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    store.values[instance.id] = "synthetic.saved"
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try #require(try await manager.connect(instance))
    let permission = PermissionRequirement(category: .search, feature: "search.resource")
    try session.checkActive(requiring: permission)
    let revoked = try SessionLifecycleTestData.identity(
      instance, permissions: NativePermissions(features: ["search.resource": false]))
    auth.configure(.success(revoked))
    _ = try await session.refreshUser()
    LifecycleHTTPProtocol.state.prepare()
    await #expect(throws: NativeSessionFailure.permissionDenied) {
      try await session.perform(
        APIEndpoint(path: ["download"], method: .post), requiring: permission)
    }
    #expect(LifecycleHTTPProtocol.state.requests().isEmpty)
    #expect(manager.state == .authenticated(session.snapshot))
    #expect(!session.user.allows(permission))
  }

  /// 权限在网络等待中收窄时，返回结果也不能交付给已无权的原生页面。
  @Test func rechecksPermissionsWhenARequestReturns() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    store.values[instance.id] = "synthetic.saved"
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try #require(try await manager.connect(instance))
    let permission = PermissionRequirement(category: .search)
    LifecycleHTTPProtocol.state.prepare(hold: true)
    let task = Task {
      try await session.request(APIEndpoint(path: ["search"]), as: Int.self, requiring: permission)
    }
    defer { task.cancel() }
    try await LifecycleHTTPProtocol.waitUntilRequested()
    auth.configure(
      .success(
        try SessionLifecycleTestData.identity(
          instance, permissions: NativePermissions(search: false))))
    _ = try await session.refreshUser()
    LifecycleHTTPProtocol.completeHeld(body: Data(#"{"success":true,"message":"","data":1}"#.utf8))
    await #expect(throws: NativeSessionFailure.permissionDenied) { try await task.value }
    #expect(manager.currentSession === session && LifecycleHTTPProtocol.state.requests().count == 1)
  }

  /// 实例切换取消旧的实际 API 请求，新实例不接收旧成功或取消回写。
  @Test func cancelsOnlyTheOldInstancesAPIRequests() async throws {
    let a = try SessionLifecycleTestData.instance()
    let b = try SessionLifecycleTestData.instance("b.test")
    let store = SessionTestTokenStore()
    store.values = [a.id: "synthetic.a", b.id: "synthetic.b"]
    let authA = try ControlledAuthentication(instance: a)
    let authB = try ControlledAuthentication(instance: b, userID: 4)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [authA, authB])
    let sessionA = try #require(try await manager.connect(a))
    LifecycleHTTPProtocol.state.prepare(hold: true)
    let task = Task { try await sessionA.request(APIEndpoint(path: ["search"]), as: Int.self) }
    defer { task.cancel() }
    try await LifecycleHTTPProtocol.waitUntilRequested()
    let sessionB = try #require(try await manager.connect(b))
    await #expect(throws: NativeSessionFailure.invalidated) { try await task.value }
    #expect(manager.currentSession === sessionB && sessionB.user.id == 4)
    #expect(store.values == [a.id: "synthetic.a", b.id: "synthetic.b"])
  }

  /// 旧权限刷新忽略取消后返回 401，也不能清理新账号的保存记录。
  @Test func ignoresLate401FromAnOldGeneration() async throws {
    let a = try SessionLifecycleTestData.instance()
    let b = try SessionLifecycleTestData.instance("b.test")
    let store = SessionTestTokenStore()
    store.values = [a.id: "synthetic.a", b.id: "synthetic.b"]
    let authA = try ControlledAuthentication(instance: a)
    let authB = try ControlledAuthentication(instance: b, userID: 4)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [authA, authB])
    let sessionA = try #require(try await manager.connect(a))
    authA.configure(.failure(APIError.unauthorized), hold: true)
    let task = Task { try await sessionA.refreshUser() }
    defer { authA.resolve(.failure(CancellationError())) }
    try await authA.waitUntilPending()
    let sessionB = try #require(try await manager.connect(b))
    authA.resolve(.failure(APIError.unauthorized))
    await #expect(throws: NativeSessionFailure.invalidated) { try await task.value }
    #expect(manager.currentSession === sessionB && store.values[b.id] == "synthetic.b")
    #expect(store.removedIDs.isEmpty)
  }

  /// 同代次的权限刷新乱序也必须以最后发起的确认为准，不能恢复旧权限或误注销。
  @Test(arguments: [false, true])
  func discardsSupersededPermissionRefresh(_ oldUnauthorized: Bool) async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    store.values[instance.id] = "synthetic.saved"
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try #require(try await manager.connect(instance))
    let oldIdentity = try SessionLifecycleTestData.identity(instance)
    let revoked = try SessionLifecycleTestData.identity(
      instance, permissions: NativePermissions(search: false))
    auth.configure(.success(oldIdentity), hold: true)
    let older = Task { try await session.refreshUser() }
    defer { auth.resolve(.failure(CancellationError())) }
    try await auth.waitUntilPending()
    let newer = Task { try await session.refreshUser() }
    try await auth.waitUntilPending(2)
    auth.resolveOne(.success(revoked), newest: true)
    #expect(try await newer.value.permissions.search == false)
    auth.resolveOne(oldUnauthorized ? .failure(APIError.unauthorized) : .success(oldIdentity))
    await #expect(throws: NativeSessionFailure.superseded) { try await older.value }
    #expect(manager.currentSession === session && !session.user.permissions.search)
    #expect(store.values[instance.id] == "synthetic.saved" && store.removedIDs.isEmpty)
  }

  /// 旧初始化返回后不能读取旧令牌，更不能在新实例下面继续认证。
  @Test func rejectsLateInitializationBeforeReadingCredentials() async throws {
    let a = try SessionLifecycleTestData.instance()
    let b = try SessionLifecycleTestData.instance("b.test")
    let store = SessionTestTokenStore()
    store.values = [a.id: "synthetic.a", b.id: "synthetic.b"]
    let authA = try ControlledAuthentication(instance: a)
    let authB = try ControlledAuthentication(instance: b, userID: 4)
    authA.holdInitialization()
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [authA, authB])
    let old = Task { try await manager.connect(a) }
    defer { authA.resolveInitialization(.failure(CancellationError())) }
    try await authA.waitUntilInitializing()
    let current = try #require(try await manager.connect(b))
    authA.resolveInitialization(.success(.ready))
    await #expect(throws: NativeSessionFailure.superseded) { try await old.value }
    #expect(manager.currentSession === current && authA.restoreTokens.isEmpty)
    #expect(store.readIDs == [b.id] && store.removedIDs.isEmpty)
  }

  /// 旧保存令牌的成功恢复迟到时不替换新实例的成功身份。
  @Test func ignoresLateSavedTokenRestore() async throws {
    let a = try SessionLifecycleTestData.instance()
    let b = try SessionLifecycleTestData.instance("b.test")
    let store = SessionTestTokenStore()
    store.values = [a.id: "synthetic.a", b.id: "synthetic.b"]
    let authA = try ControlledAuthentication(instance: a)
    let authB = try ControlledAuthentication(instance: b, userID: 4)
    let identity = try SessionLifecycleTestData.identity(a)
    authA.configure(.success(identity), hold: true)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [authA, authB])
    let old = Task { try await manager.connect(a) }
    defer { authA.resolve(.failure(CancellationError())) }
    try await authA.waitUntilPending()
    let current = try #require(try await manager.connect(b))
    authA.resolve(.success(identity))
    await #expect(throws: NativeSessionFailure.superseded) { try await old.value }
    #expect(manager.currentSession === current && manager.state == .authenticated(current.snapshot))
    #expect(store.values == [a.id: "synthetic.a", b.id: "synthetic.b"])
    #expect(store.removedIDs.isEmpty && store.savedIDs.isEmpty)
  }

  /// 用户或地址漂移必须要求重新认证，不在原会话中静默替换身份。
  @Test func rejectsIdentityDrift() async throws {
    let instance = try SessionLifecycleTestData.instance()
    let store = SessionTestTokenStore()
    store.values[instance.id] = "synthetic.saved"
    let auth = try ControlledAuthentication(instance: instance)
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    let session = try #require(try await manager.connect(instance))
    auth.configure(.success(try SessionLifecycleTestData.identity(instance, id: 4)))
    await #expect(throws: NativeSessionFailure.identityMismatch) { try await session.refreshUser() }
    #expect(manager.currentSession == nil && store.values[instance.id] == nil)
    #expect(manager.state == .failed(instance, .identityMismatch) && session.user.id == 3)
  }

  /// 客户端或认证结果来源不符时，不读取/改写其它实例的令牌。
  @Test(arguments: [false, true])
  func refusesMismatchedAuthenticationOrigins(_ wrongResult: Bool) async throws {
    let a = try SessionLifecycleTestData.instance()
    let b = try SessionLifecycleTestData.instance("b.test")
    let store = SessionTestTokenStore()
    let auth = try ControlledAuthentication(instance: wrongResult ? a : b)
    if wrongResult { auth.configure(.success(try SessionLifecycleTestData.identity(b))) }
    let manager = SessionLifecycleTestData.manager(tokens: store, clients: [auth])
    await #expect(throws: NativeSessionFailure.identityMismatch) {
      try await manager.login(to: a, username: "reader", password: "synthetic-only", remember: true)
    }
    #expect(manager.currentSession == nil && store.savedIDs.isEmpty && store.removedIDs.isEmpty)
  }
}
