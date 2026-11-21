import Foundation
import MoviePilotAPI
import MoviePilotCore

/// 单次已认证原生会话；所有请求和确认操作都受同一个不可复用的代次约束。
@MainActor
public final class NativeSession {
  public let instance: NativeInstance
  public let scope: NativeSessionScope
  public private(set) var user: SessionUser
  private let api: APIClient
  private let authentication: any NativeAuthenticating
  private let accessToken: String
  private let onInvalidated: (NativeSessionScope, NativeSessionFailure) -> Void
  private let onUserChanged: (NativeSessionScope) -> Void
  private var active = true
  private var latestUserRefresh: UUID?

  /// 只能由协调器在地址/身份/持久化全部通过后交付，测试可注入隔离的真实 API 客户端。
  init(
    instance: NativeInstance, identity: SessionIdentity, generation: UUID, api: APIClient,
    authentication: any NativeAuthenticating,
    onInvalidated: @escaping (NativeSessionScope, NativeSessionFailure) -> Void,
    onUserChanged: @escaping (NativeSessionScope) -> Void
  ) {
    self.instance = instance
    scope = NativeSessionScope(
      instanceID: instance.id, userID: identity.user.id, generation: generation)
    user = identity.user
    accessToken = identity.accessToken
    self.api = api
    self.authentication = authentication
    self.onInvalidated = onInvalidated
    self.onUserChanged = onUserChanged
  }

  /// 释放未交付的候选会话也要结束自己的网络，不影响其它实例。
  deinit {
    api.cancel()
    authentication.cancel()
  }

  /// 快照不暴露 credential，已取得的快照不能代替后续动作的存活检查。
  public var snapshot: NativeSessionSnapshot {
    NativeSessionSnapshot(instance: instance, scope: scope, user: user)
  }

  /// 仅在活跃会话存活校验通过后，为原生本地播放器提供当前实例同源流授权信息。
  public func playbackAuthorization() throws -> (address: ServerAddress, accessToken: String) {
    try checkActive()
    return (instance.address, accessToken)
  }

  /// 弹窗确认后及异步回写前都可显式调用；旧实例句柄不能继续操作新会话。
  public func checkActive(requiring permission: PermissionRequirement? = nil) throws {
    guard active else { throw NativeSessionFailure.invalidated }
    try Task.checkCancellation()
    if let permission, !user.allows(permission) { throw NativeSessionFailure.permissionDenied }
  }

  /// 读取前后都验证存活和权限，API 层负责真实后端授权；本地判断不替代服务器。
  public func request<Value: Decodable & Sendable>(
    _ endpoint: APIEndpoint, as type: Value.Type = Value.self,
    requiring permission: PermissionRequirement? = nil
  ) async throws -> APIResult<Value> {
    try checkActive(requiring: permission)
    do {
      let value = try await api.request(endpoint, as: type)
      try checkActive(requiring: permission)
      return value
    } catch {
      try fail(error)
    }
  }

  /// 保真 payload 也必须通过同一会话的前后权限/存活检查与 401 失效处理。
  public func requestPayload(
    _ endpoint: APIEndpoint, requiring permission: PermissionRequirement? = nil
  ) async throws -> APIResult<Data> {
    try checkActive(requiring: permission)
    do {
      let value = try await api.requestPayload(endpoint)
      try checkActive(requiring: permission)
      return value
    } catch {
      try fail(error)
    }
  }

  /// 图片权限失败只影响图片；JSON 业务请求或账号刷新仍负责确认登录过期。
  public func requestImage(_ sourceURL: URL, maximumWidth: Int? = nil) async throws -> APIImage {
    try checkActive()
    do {
      let image = try await api.requestImage(sourceURL, maximumWidth: maximumWidth)
      try checkActive()
      return image
    } catch {
      try checkActive()
      throw error
    }
  }

  /// 资源 Cookie 鉴权读取（如实时日志），资源令牌失效只影响当前读取，绝不触发主登录会话强制退出。
  public func requestResourcePayload(
    _ endpoint: APIEndpoint, requiring permission: PermissionRequirement? = nil
  ) async throws -> APIResult<Data> {
    try checkActive(requiring: permission)
    do {
      let value = try await api.requestResourcePayload(endpoint)
      try checkActive(requiring: permission)
      return value
    } catch {
      try checkActive(requiring: permission)
      throw error
    }
  }

  /// 写入只发一次；返回只说明端点接受动作，不能自动重试或推断后台任务已结束。
  public func perform(
    _ endpoint: APIEndpoint, requiring permission: PermissionRequirement? = nil
  ) async throws {
    try checkActive(requiring: permission)
    do {
      try await api.perform(endpoint)
      try checkActive(requiring: permission)
    } catch {
      try fail(error)
    }
  }

  /// 服务器权限更新覆盖当前快照，账号或来源不符则关闭原会话，不悄悄换成另一个人。
  public func refreshUser() async throws -> SessionUser {
    try checkActive()
    let refresh = UUID()
    latestUserRefresh = refresh
    do {
      let identity = try await authentication.restore(accessToken: accessToken)
      try checkUserRefresh(refresh)
      guard identity.address == instance.address, identity.user.id == scope.userID,
        identity.accessToken == accessToken
      else {
        onInvalidated(scope, .identityMismatch)
        throw NativeSessionFailure.identityMismatch
      }
      user = identity.user
      onUserChanged(scope)
      return user
    } catch {
      if !(error is NativeSessionFailure) { try checkUserRefresh(refresh) }
      try fail(error)
    }
  }

  /// 协调器先使内存句柄失效再取消网络，保证迟到回调不能在新账号下继续提交。
  func invalidate() {
    guard active else { return }
    active = false
    latestUserRefresh = nil
    api.cancel()
    authentication.cancel()
  }

  /// 同代次的较旧刷新也不能覆盖最后发起的确认；旧 401 同样不再清理当前记录。
  private func checkUserRefresh(_ refresh: UUID) throws {
    try checkActive()
    guard latestUserRefresh == refresh else { throw NativeSessionFailure.superseded }
  }

  /// 401 只通知本代次过期；失效后的迟到错误和 403 不清理新会话的安全存储。
  private func fail(_ error: any Error) throws -> Never {
    if let failure = error as? NativeSessionFailure { throw failure }
    try checkActive()
    if (error as? APIError) == .unauthorized
      || (error as? NativeAuthenticationError) == .inactiveAccount
    {
      onInvalidated(scope, .api(.unauthorized))
    }
    throw error
  }
}
