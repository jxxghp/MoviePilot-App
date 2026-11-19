import Foundation
import MoviePilotAPI
import MoviePilotCore

/// 沿用地址簿的实例 UUID；地址是已校验的记录内容，不能临时替换为插件传入的 URL。
public struct NativeInstance: Equatable, Sendable {
  public let id: UUID
  public let address: ServerAddress

  /// 从既有 SavedInstance 映射，不生成新 ID 或更改安全存储归属。
  public init(id: UUID, address: ServerAddress) {
    self.id = id
    self.address = address
  }
}

/// 一次不可复用的认证代次；同实例同用户重新登录也会取得不同 generation。
public struct NativeSessionScope: Equatable, Sendable {
  public let instanceID: UUID
  public let userID: Int
  public let generation: UUID
}

/// 可供原生 UI 观察的非敏感快照，不携带 API 客户端、密码或令牌。
public struct NativeSessionSnapshot: Equatable, Sendable {
  public let instance: NativeInstance
  public let scope: NativeSessionScope
  public let user: SessionUser
}

/// 会话本地失败只保留安全分类；原始认证和 API 错误仍在调用处抛出。
public enum NativeSessionFailure: Error, Equatable, Sendable {
  case notAuthenticated
  case invalidated
  case permissionDenied
  case superseded
  case identityMismatch
  case storageUnavailable
  case api(APIError)
  case authentication(NativeAuthenticationError)
}

/// 登录提示区分首次进入、过期、主动退出和取消，不把取消提示为密码错误。
public enum NativeLoginReason: Equatable, Sendable {
  case initial, expired, signedOut, cancelled
}

/// 原生启动/认证状态的唯一 UI 来源；网页存储和桥状态不参与此状态机。
public enum NativeSessionState: Equatable, Sendable {
  case disconnected
  case connecting(NativeInstance)
  case initializationRequired(NativeInstance, configuredUsername: String?)
  case loginRequired(NativeInstance, reason: NativeLoginReason)
  case authenticating(NativeInstance)
  case verificationRequired(NativeInstance, methods: [String])
  case authenticated(NativeSessionSnapshot)
  case failed(NativeInstance, NativeSessionFailure)
}

/// 平台 TokenStore 的最小接口；保持既有 UUID 键和同步 Keychain 操作语义。
@MainActor
public protocol SessionTokenStoring: AnyObject {
  /// 读取指定实例的安全令牌；旧平台读不到时仍返回 nil，不查询其它账号。
  func read(_ instanceID: UUID) -> String?

  /// 用户选择保持登录后才写入，失败必须向调用方传播。
  func save(_ token: String, for instanceID: UUID) throws

  /// 删除指定实例，false 表示系统未能安全清理，不能假装已经退出。
  @discardableResult func remove(_ instanceID: UUID) -> Bool
}
