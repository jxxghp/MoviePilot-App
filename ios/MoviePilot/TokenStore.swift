import Foundation
import Security

/// 每个实例仅在本机 Keychain 保存已签发令牌；可选密码使用独立存储，OTP 不持久化。
@MainActor
final class TokenStore {
  private let service = "org.moviepilot.authentication.v1"

  /// 读取指定实例令牌；设备锁定或条目不存在时回到可操作的登录页。
  func read(_ instanceId: UUID) -> String? {
    var query = key(instanceId)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// 只在用户选择保持登录时写入；无法安全保存时向调用方报告真实失败。
  func save(_ token: String, for instanceId: UUID) throws {
    let query = key(instanceId)
    let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
    let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(update))
    }
    var item = query.merging(attributes) { _, new in new }
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }

  /// 退出或会话过期时撤销当前实例令牌，不影响其他实例。
  @discardableResult
  func remove(_ instanceId: UUID) -> Bool {
    let status = SecItemDelete(key(instanceId) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  /// Keychain 键只由稳定实例 UUID 组成，不使用用户输入作为访问组或共享标识。
  private func key(_ instanceId: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: instanceId.uuidString, kSecAttrSynchronizable as String: false,
    ]
  }
}
