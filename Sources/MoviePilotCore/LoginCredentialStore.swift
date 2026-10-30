import Foundation
import Security

/// 用户明确选择记住的登录输入；不包含令牌、Cookie 或一次性验证码。
public struct LoginCredentials: Codable, Equatable, Sendable {
  public let username: String
  public let password: String

  /// 只接收已成功完成密码认证的账号，保存时再绑定具体服务地址。
  public init(username: String, password: String) {
    self.username = username
    self.password = password
  }
}

/// 系统锁定、权限不足和损坏条目均不能被当作保存或删除成功。
public enum LoginCredentialError: Error, Equatable {
  case unavailable
}

/// 隔离同步 Security 调用，让存储边界测试不接触用户的真实钥匙串。
@MainActor
protocol LoginCredentialCalls {
  /// 仅查询指定实例的单个条目。
  func read(_ query: [String: Any]) -> (OSStatus, Any?)
  /// 原子替换既有账号，不先删除旧条目。
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
  /// 仅在条目不存在时建立本机凭据。
  func add(_ attributes: [String: Any]) -> OSStatus
  /// 只清除明确指定的实例账号。
  func delete(_ query: [String: Any]) -> OSStatus
}

/// 生产适配只转交 Security 状态，不记录凭据或错误正文。
private struct SystemLoginCredentialCalls: LoginCredentialCalls {
  /// 保留不存在与暂时无法读取的区别。
  func read(_ query: [String: Any]) -> (OSStatus, Any?) {
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &value)
    return (status, value)
  }

  /// 更新限定到当前服务及实例 UUID。
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

  /// 创建时使用调用方指定的本机保护级别。
  func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }

  /// 删除不扩大至其它实例、令牌或小组件命名空间。
  func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// 按实例 UUID 和标准服务地址隔离密码，仅在解锁的本机钥匙串保存，不同步到 iCloud。
@MainActor
public final class LoginCredentialStore {
  /// 地址随密文一起校验，不能仅凭另一个实例的 UUID 回填账号。
  private struct Record: Codable {
    let address: ServerAddress
    let credentials: LoginCredentials
  }

  private let calls: any LoginCredentialCalls

  /// App 使用独立的私有服务，不加入小组件共享组。
  public init() { calls = SystemLoginCredentialCalls() }

  /// 测试只注入合成系统响应，不读取实际钥匙串。
  init(calls: any LoginCredentialCalls) { self.calls = calls }

  /// 只回填当前地址已保存的输入，不发起认证或恢复其它实例的账号。
  public func read(for instanceID: UUID, address: ServerAddress) throws -> LoginCredentials? {
    var query = key(instanceID)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, value) = calls.read(query)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = value as? Data, data.count <= 65536,
      let record = try? JSONDecoder().decode(Record.self, from: data),
      !record.credentials.username.isEmpty, !record.credentials.password.isEmpty
    else { throw LoginCredentialError.unavailable }
    return record.address == address ? record.credentials : nil
  }

  /// 成功登录并选择记住后才写入；系统拒绝更新时不删除或新建绕过失败。
  public func save(
    _ credentials: LoginCredentials, for instanceID: UUID, address: ServerAddress
  ) throws {
    let data = try JSONEncoder().encode(Record(address: address, credentials: credentials))
    guard !credentials.username.isEmpty, !credentials.password.isEmpty, data.count <= 65536 else {
      throw LoginCredentialError.unavailable
    }
    let query = key(instanceID)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = calls.update(query, attributes: attributes)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound,
      calls.add(query.merging(attributes) { _, value in value }) == errSecSuccess
    else { throw LoginCredentialError.unavailable }
  }

  /// 关闭记忆或删除服务立即移除密码，不影响其它实例的条目。
  public func remove(for instanceID: UUID) throws {
    let status = calls.delete(key(instanceID))
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw LoginCredentialError.unavailable
    }
  }

  /// 查询始终限定在私有密码服务内，账号键不使用地址或用户名。
  private func key(_ instanceID: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "org.moviepilot.credentials.v1",
      kSecAttrAccount as String: instanceID.uuidString,
      kSecAttrSynchronizable as String: false,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }
}
