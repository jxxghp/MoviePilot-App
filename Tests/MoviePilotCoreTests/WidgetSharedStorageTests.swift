import Foundation
import Security
import Testing

@testable import MoviePilotCore

/// 用合成 Security 回答检查平台适配，任何测试都不访问实际 Keychain。
struct WidgetSharedStorageTests {
  private let group = "group.org.moviepilot.widgets.ABCD123456"

  /// 更新和创建始终指定同组、同服务、不可同步以及锁屏所需的本机保护级别。
  @Test func scopesEveryWriteAndUsesThisDeviceOnlyProtection() throws {
    let profile = try WidgetTestData.profile()
    let calls = StubWidgetSecurity()
    let vault = try SharedWidgetKeychain(group: group, calls: calls)
    try vault.save(WidgetTestData.secret(profile), registrationId: profile.registrationId)
    let records = calls.records()
    #expect(records.map(\.operation) == ["update", "add"])
    for record in records {
      #expect(record.query[kSecAttrAccessGroup as String] as? String == group)
      #expect(
        record.query[kSecAttrService as String] as? String == "org.moviepilot.widgets.readonly.v1")
      #expect(
        record.query[kSecAttrAccount as String] as? String
          == profile.registrationId.uuidString.lowercased())
      #expect(record.query[kSecAttrSynchronizable as String] as? Bool == false)
      #expect(record.query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }
    let added = try #require(records.last)
    #expect(
      added.query[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    #expect(
      added.query[kSecValueData as String] as? Data == Data(WidgetTestData.secret(profile).utf8))
  }

  /// 不存在与系统拒绝不同，已存在值也必须匹配本次登记的格式。
  @Test func distinguishesMissingLockedAndMalformedCredentials() throws {
    let profile = try WidgetTestData.profile()
    let calls = StubWidgetSecurity()
    let vault = try SharedWidgetKeychain(group: group, calls: calls)
    #expect(try vault.read(registrationId: profile.registrationId) == nil)
    for status in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecNotAvailable] {
      calls.answerCopy(status: status)
      #expect(throws: WidgetStoreError.unavailable) {
        try vault.read(registrationId: profile.registrationId)
      }
    }
    calls.answerCopy(status: errSecSuccess, value: Data("main.jwt.token".utf8))
    #expect(throws: WidgetStoreError.unavailable) {
      try vault.read(registrationId: profile.registrationId)
    }
    calls.answerCopy(status: errSecSuccess, value: Data(WidgetTestData.secret(profile).utf8))
    #expect(
      try vault.read(registrationId: profile.registrationId) == WidgetTestData.secret(profile))
    let query = try #require(calls.records().last?.query)
    #expect(query[kSecReturnData as String] as? Bool == true)
    #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
  }

  /// 系统更新失败不能变成先删除再重建，也不能误报保存成功。
  @Test func doesNotCreateAfterUnexpectedUpdateFailure() throws {
    let profile = try WidgetTestData.profile()
    let calls = StubWidgetSecurity(update: errSecInteractionNotAllowed)
    let vault = try SharedWidgetKeychain(group: group, calls: calls)
    #expect(throws: WidgetStoreError.unavailable) {
      try vault.save(WidgetTestData.secret(profile), registrationId: profile.registrationId)
    }
    #expect(calls.records().map(\.operation) == ["update"])
  }

  /// 清理只读当前服务的属性，不扫描密钥正文，不删除仍活动的登记。
  @Test func prunesOnlyRetiredAccountsInsideTheExplicitNamespace() throws {
    let keep = UUID()
    let retired = UUID()
    let calls = StubWidgetSecurity()
    calls.answerCopy(
      status: errSecSuccess,
      value: [
        [kSecAttrAccount as String: keep.uuidString.lowercased()],
        [kSecAttrAccount as String: retired.uuidString.lowercased()],
        [kSecAttrAccount as String: "old-malformed-account"],
      ])
    let vault = try SharedWidgetKeychain(group: group, calls: calls)
    try vault.retainOnly(registrationIds: [keep])
    let records = calls.records()
    #expect(records.map(\.operation) == ["copy", "delete", "delete"])
    #expect(records[0].query[kSecReturnData as String] == nil)
    #expect(records[0].query[kSecReturnAttributes as String] as? Bool == true)
    #expect(records[0].query[kSecMatchLimit as String] as? String == kSecMatchLimitAll as String)
    for query in records.map(\.query) {
      #expect(query[kSecAttrAccessGroup as String] as? String == group)
      #expect(query[kSecAttrService as String] as? String == "org.moviepilot.widgets.readonly.v1")
    }
    #expect(
      records[1].query[kSecAttrAccount as String] as? String == retired.uuidString.lowercased())
    #expect(records[2].query[kSecAttrAccount as String] as? String == "old-malformed-account")
  }

  /// 任意组和主 JWT 在调用系统函数前被拒绝，不产生其它命名空间的副作用。
  @Test func rejectsOtherGroupsAndMainCredentialsBeforeSecurityCalls() throws {
    let calls = StubWidgetSecurity()
    for value in ["", "group.other.widgets", "group.org.moviepilot.widgets.abcd123456"] {
      #expect(throws: WidgetPlatformError.sharedStorageUnavailable) {
        try SharedWidgetKeychain(group: value, calls: calls)
      }
    }
    let profile = try WidgetTestData.profile()
    let vault = try SharedWidgetKeychain(group: group, calls: calls)
    #expect(throws: WidgetDataError.invalidData) {
      try vault.save("main.jwt.token", registrationId: profile.registrationId)
    }
    #expect(calls.records().isEmpty)
  }

  /// 属性读取或删除被系统拒绝时，清理错误保持可见，不能冒充空 Keychain。
  @Test func reportsCleanupErrorsWithoutBroadFallbacks() throws {
    let calls = StubWidgetSecurity()
    let vault = try SharedWidgetKeychain(group: group, calls: calls)
    calls.answerCopy(status: errSecInteractionNotAllowed)
    #expect(throws: WidgetStoreError.unavailable) { try vault.retainOnly(registrationIds: []) }
    #expect(calls.records().map(\.operation) == ["copy"])
    let failure = StubWidgetSecurity(delete: errSecMissingEntitlement)
    failure.answerCopy(
      status: errSecSuccess, value: [[kSecAttrAccount as String: UUID().uuidString]])
    let denied = try SharedWidgetKeychain(group: group, calls: failure)
    #expect(throws: WidgetStoreError.unavailable) { try denied.retainOnly(registrationIds: []) }
    #expect(failure.records().map(\.operation) == ["copy", "delete"])
  }
}

/// 同步 Security 事实只在此测试文件读取，不保存真实账号或系统结果。
private struct WidgetSecurityRecord {
  let operation: String
  let query: [String: Any]
}

/// 可变回答和调用记录全部受锁保护，协议接口不会逃逸到真实 Security 服务。
private final class StubWidgetSecurity: WidgetKeychainCalls, @unchecked Sendable {
  private let lock = NSLock()
  private var copyStatus = errSecItemNotFound
  private var copyValue: Any?
  private let updateStatus: OSStatus
  private let deleteStatus: OSStatus
  private var captured: [WidgetSecurityRecord] = []

  /// 默认表示尚无条目，测试可以指定拒绝更新或清理。
  init(update: OSStatus = errSecItemNotFound, delete: OSStatus = errSecSuccess) {
    updateStatus = update
    deleteStatus = delete
  }

  /// 注入一个合成回答，不与任何外部系统共享状态。
  func answerCopy(status: OSStatus, value: Any? = nil) {
    lock.withLock {
      copyStatus = status
      copyValue = value
    }
  }

  /// 保留真实查询字段并返回本测试的指定状态。
  func copy(_ query: [String: Any]) -> (OSStatus, Any?) {
    lock.withLock {
      captured.append(WidgetSecurityRecord(operation: "copy", query: query))
      return (copyStatus, copyValue)
    }
  }

  /// 更新的属性另外合并用于断言，不改变被测查询的原始字典。
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    lock.withLock {
      captured.append(
        WidgetSecurityRecord(
          operation: "update", query: query.merging(attributes) { _, new in new }))
      return updateStatus
    }
  }

  /// 新增只记录已提供的合成字段，不触碰系统。
  func add(_ attributes: [String: Any]) -> OSStatus {
    lock.withLock { captured.append(WidgetSecurityRecord(operation: "add", query: attributes)) }
    return errSecSuccess
  }

  /// 删除只报告注入状态，让测试检查没有跨组回退。
  func delete(_ query: [String: Any]) -> OSStatus {
    lock.withLock { captured.append(WidgetSecurityRecord(operation: "delete", query: query)) }
    return deleteStatus
  }

  /// 测试结束后仅在本进程读取受锁保护的副本。
  func records() -> [WidgetSecurityRecord] { lock.withLock { captured } }
}
