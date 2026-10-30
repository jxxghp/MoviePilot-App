import Foundation
import Security
import Testing

@testable import MoviePilotCore

/// 用合成钥匙串验证账号隔离、保护级别和失败语义，不读写真实凭据。
@MainActor
struct LoginCredentialStoreTests {
  /// 内外网地址和不同实例互不回填，标准化相同的地址仍能读取。
  @Test func isolatesInstancesAndAddresses() throws {
    let calls = StubLoginCredentialCalls()
    let store = LoginCredentialStore(calls: calls)
    let first = UUID()
    let second = UUID()
    let local = try ServerAddress("http://192.168.1.2:3000")
    let remote = try ServerAddress("https://mp.example.com")
    let a = LoginCredentials(username: "local-user", password: "local-fixture")
    let b = LoginCredentials(username: "remote-user", password: "remote-fixture")
    try store.save(a, for: first, address: local)
    try store.save(b, for: second, address: remote)
    #expect(try store.read(for: first, address: local) == a)
    #expect(try store.read(for: second, address: remote) == b)
    #expect(try store.read(for: first, address: remote) == nil)
    #expect(try store.read(for: UUID(), address: local) == nil)
    #expect(
      try store.read(for: second, address: ServerAddress("https://MP.EXAMPLE.com:443/")) == b)
    try store.remove(for: first)
    #expect(try store.read(for: first, address: local) == nil)
    #expect(try store.read(for: second, address: remote) == b)
    for query in calls.queries {
      #expect(query[kSecAttrService as String] as? String == "org.moviepilot.credentials.v1")
      #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
      #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
      #expect(query[kSecAttrAccessGroup as String] == nil)
      #expect(query[kSecAttrAccount as String] as? String != nil)
    }
    #expect(
      calls.lastAttributes[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    let data = try #require(calls.lastAttributes[kSecValueData as String] as? Data)
    let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(record.keys) == ["address", "credentials"])
    let credentials = try #require(record["credentials"] as? [String: Any])
    #expect(Set(credentials.keys) == ["username", "password"])
  }

  /// 账号更新原子替换；锁定时旧值保留，不能冒充成功或绕过失败新建。
  @Test func preservesPreviousCredentialsWhenUpdateFails() throws {
    let calls = StubLoginCredentialCalls()
    let store = LoginCredentialStore(calls: calls)
    let id = UUID()
    let address = try ServerAddress("https://mp.example.com")
    let original = LoginCredentials(username: "fixture", password: "original-fixture")
    let replacement = LoginCredentials(username: "fixture", password: "replacement-fixture")
    try store.save(original, for: id, address: address)
    calls.failure = errSecInteractionNotAllowed
    #expect(throws: LoginCredentialError.unavailable) {
      try store.save(replacement, for: id, address: address)
    }
    #expect(calls.addCount == 1)
    #expect(throws: LoginCredentialError.unavailable) { try store.remove(for: id) }
    #expect(throws: LoginCredentialError.unavailable) {
      try store.read(for: id, address: address)
    }
    calls.failure = nil
    #expect(try store.read(for: id, address: address) == original)
    try store.save(replacement, for: id, address: address)
    #expect(try store.read(for: id, address: address) == replacement)
    #expect(calls.addCount == 1)
  }

  /// 缺失可正常重新输入；空值或损坏密文保持失败可见且不写入。
  @Test func rejectsEmptyAndMalformedRecords() throws {
    let calls = StubLoginCredentialCalls()
    let store = LoginCredentialStore(calls: calls)
    let id = UUID()
    let address = try ServerAddress("https://mp.example.com")
    #expect(try store.read(for: id, address: address) == nil)
    try store.remove(for: id)
    #expect(throws: LoginCredentialError.unavailable) {
      try store.save(LoginCredentials(username: "fixture", password: ""), for: id, address: address)
    }
    #expect(calls.addCount == 0)
    calls.values[id.uuidString] = Data("invalid-fixture".utf8)
    #expect(throws: LoginCredentialError.unavailable) {
      try store.read(for: id, address: address)
    }
  }
}

/// 内存字典实现单条 Security 语义，记录查询范围而不访问系统钥匙串。
@MainActor
private final class StubLoginCredentialCalls: LoginCredentialCalls {
  var values: [String: Data] = [:]
  var queries: [[String: Any]] = []
  var lastAttributes: [String: Any] = [:]
  var failure: OSStatus?
  var addCount = 0

  /// 系统失败优先，缺失返回明确的 not found。
  func read(_ query: [String: Any]) -> (OSStatus, Any?) {
    queries.append(query)
    if let failure { return (failure, nil) }
    let value = values[query[kSecAttrAccount as String] as! String]
    return (value == nil ? errSecItemNotFound : errSecSuccess, value)
  }

  /// 只更新已存在值，模拟真实 Security 的无条目状态。
  func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
    queries.append(query)
    if let failure { return failure }
    let id = query[kSecAttrAccount as String] as! String
    guard values[id] != nil else { return errSecItemNotFound }
    values[id] = attributes[kSecValueData as String] as? Data
    lastAttributes = attributes
    return errSecSuccess
  }

  /// 首次保存只写合成数据并保留保护属性供断言。
  func add(_ attributes: [String: Any]) -> OSStatus {
    queries.append(attributes)
    addCount += 1
    if let failure { return failure }
    values[attributes[kSecAttrAccount as String] as! String] =
      attributes[kSecValueData as String] as? Data
    lastAttributes = attributes
    return errSecSuccess
  }

  /// 删除严格限定到单个账号，系统拒绝时保留旧值。
  func delete(_ query: [String: Any]) -> OSStatus {
    queries.append(query)
    if let failure { return failure }
    let value = values.removeValue(forKey: query[kSecAttrAccount as String] as! String)
    return value == nil ? errSecItemNotFound : errSecSuccess
  }
}
