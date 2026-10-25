import Foundation
import Security

/// 当前安装不具备可用共享区域时保持失败关闭，不猜测个人团队或其它应用的权限。
public enum WidgetPlatformError: Error, Equatable, Sendable {
  case sharedStorageUnavailable
}

/// 主 App 与扩展分别打开自己的实际签名共享组，服务端和网页不能提供组名。
public enum WidgetSharedStorage {
  /// 签名解析只用于找组；containerURL 和后续 Keychain 操作才验证实际系统授权。
  public static func open() throws -> WidgetStore {
    guard let executable = Bundle.main.executableURL,
      let size = try? executable.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size > 0, size <= 256 * 1024 * 1024,
      let data = try? Data(contentsOf: executable, options: .mappedIfSafe),
      let group = try? WidgetAppGroup.resolve(in: data),
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { throw WidgetPlatformError.sharedStorageUnavailable }
    return try WidgetStore(container: container, vault: SharedWidgetKeychain(group: group))
  }
}

/// 同步 Security 边界便于用合成响应检查范围，不在测试中读写真实系统 Keychain。
protocol WidgetKeychainCalls: Sendable {
  /// 查询只能返回当前共享服务的值或属性。
  func copy(_ query: [String: Any]) -> (OSStatus, Any?)
  /// 更新只作用于调用方已经绑定的精确登记。
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
  /// 创建同组、同服务、不可同步的专用密钥。
  func add(_ attributes: [String: Any]) -> OSStatus
  /// 垃圾回收只删除该共享服务内的已退役项。
  func delete(_ query: [String: Any]) -> OSStatus
}

/// 系统函数没有自有可变状态，也不会回显底层错误正文或认证数据。
private struct SystemWidgetKeychain: WidgetKeychainCalls {
  /// 保留原 Security 状态，让上层区分不存在与系统暂时不可用。
  func copy(_ query: [String: Any]) -> (OSStatus, Any?) {
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &value)
    return (status, value)
  }

  /// 原子更新已经存在的登记，不采用先删后加的窗口。
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

  /// 仅在确定不存在后创建，系统错误由调用方保持失败可见。
  func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }

  /// 不扩展搜索范围，不触碰主 App 的认证服务。
  func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// 所有查询显式限定实际 App Group 和独立 service；只保存专用只读 secret。
final class SharedWidgetKeychain: WidgetCredentialVault, Sendable {
  private let group: String
  private let calls: any WidgetKeychainCalls
  private let service = "org.moviepilot.widgets.readonly.v1"

  /// 生产只由签名工厂调用；测试可替换同步 Security 接口而不获取任何真实凭据。
  init(group: String, calls: (any WidgetKeychainCalls)? = nil) throws {
    guard WidgetAppGroup.acceptsIdentifier(group) else {
      throw WidgetPlatformError.sharedStorageUnavailable
    }
    self.group = group
    self.calls = calls ?? SystemWidgetKeychain()
  }

  /// 系统锁定或缺失共享权限不能被解释为已经注销。
  func read(registrationId: UUID) throws -> String? {
    var query = key(registrationId)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    let (status, value) = calls.copy(query)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = value as? Data, data.count == 84,
      let text = String(data: data, encoding: .utf8),
      WidgetStore.validCredential(text, registrationId: registrationId)
    else { throw WidgetStoreError.unavailable }
    return text
  }

  /// 首次解锁后允许锁屏组件读取，永不同步至 iCloud，也不保存网页主 token。
  func save(_ credential: String, registrationId: UUID) throws {
    guard WidgetStore.validCredential(credential, registrationId: registrationId) else {
      throw WidgetDataError.invalidData
    }
    let query = key(registrationId)
    let attributes: [String: Any] = [
      kSecValueData as String: Data(credential.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = calls.update(query, attributes: attributes)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound,
      calls.add(query.merging(attributes) { _, value in value }) == errSecSuccess
    else { throw WidgetStoreError.unavailable }
  }

  /// 查询仅返回属性，清理已退出、失败提交或轮换后的孤立密钥。
  func retainOnly(registrationIds: Set<UUID>) throws {
    var query = base()
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    let (status, value) = calls.copy(query)
    if status == errSecItemNotFound { return }
    guard status == errSecSuccess, let values = value as? [[String: Any]] else {
      throw WidgetStoreError.unavailable
    }
    for item in values {
      guard let account = item[kSecAttrAccount as String] as? String, account.utf8.count <= 128
      else {
        throw WidgetStoreError.unavailable
      }
      if let id = UUID(uuidString: account), registrationIds.contains(id) { continue }
      var retired = base()
      retired[kSecAttrAccount as String] = account
      let deleted = calls.delete(retired)
      guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
        throw WidgetStoreError.unavailable
      }
    }
  }

  /// 单条操作以随机登记 UUID 隔离，不使用用户名、地址或网页提供的 Keychain 键。
  private func key(_ registrationId: UUID) -> [String: Any] {
    var query = base()
    query[kSecAttrAccount as String] = registrationId.uuidString.lowercased()
    return query
  }

  /// 精确 accessGroup 阻止默认搜索跨越主登录和其它应用；macOS 也明确使用保护型 Keychain。
  private func base() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccessGroup as String: group, kSecAttrSynchronizable as String: false,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }
}
