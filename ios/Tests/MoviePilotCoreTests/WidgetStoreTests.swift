import Darwin
import Foundation
import Testing

@testable import MoviePilotCore

/// 在真实隔离文件目录验证共享仓，不访问真实 Keychain、账号或网络。
struct WidgetStoreTests {
  /// 两个仓实例读取同一安装标识，并且原始凭据从未进入任何 JSON。
  @Test func sharesInstallationAndPersistsOnlyWhitelistedData() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let peer = try WidgetStore(container: h.root, vault: h.vault, clock: { h.now })
    #expect(try await h.store.installationId() == peer.installationId())
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    #expect(try await peer.profiles() == [profile])
    let snapshot = try WidgetTestData.snapshot(profile, at: h.now)
    let result = await h.store.refresh(
      profileId: profile.id, using: ImmediateWidgetReader(snapshot))
    #expect(result == .updated)
    #expect(try await peer.cachedSnapshot(profileId: profile.id) == snapshot)
    for url in try FileManager.default.contentsOfDirectory(
      at: h.root.appendingPathComponent("MoviePilotWidgets-v1"), includingPropertiesForKeys: nil)
    where url.pathExtension == "json" {
      let text = try String(contentsOf: url, encoding: .utf8)
      #expect(!text.contains(WidgetTestData.secret(profile)))
      #expect(!text.contains("synthetic-main-token"))
    }
  }

  /// 并行的独立仓提交不能覆盖另一进程可见的索引条目。
  @Test func mergesConcurrentIndependentStoresAndBoundsCapacity() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let peer = try WidgetStore(container: h.root, vault: h.vault, clock: { h.now })
    let values = try (0..<10).map { _ in try WidgetTestData.profile(now: h.now) }
    try await withThrowingTaskGroup(of: Void.self) { tasks in
      for (index, profile) in values.enumerated() {
        tasks.addTask {
          try await (index.isMultiple(of: 2) ? h.store : peer).install(
            profile, credential: WidgetTestData.secret(profile))
        }
      }
      try await tasks.waitForAll()
    }
    #expect(Set(try await h.store.profiles().map(\.id)) == Set(values.map(\.id)))
    let extra = try WidgetTestData.profile(now: h.now)
    await #expect(throws: WidgetStoreError.capacityReached) {
      try await h.store.install(extra, credential: WidgetTestData.secret(extra))
    }
    #expect(h.vault.ids() == Set(values.map(\.registrationId)))
  }

  /// 暂停的外部持锁者不会令组件永久阻塞，释放后同一仓仍可正常读取。
  @Test func boundsWaitingForAnotherProcessLock() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let path = h.root.appendingPathComponent("MoviePilotWidgets-v1/store.lock").path
    let descriptor = open(path, O_CREAT | O_RDWR, 0o600)
    #expect(descriptor >= 0)
    defer { close(descriptor) }
    #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
    let start = ContinuousClock.now
    await #expect(throws: WidgetStoreError.unavailable) { try await h.store.profiles() }
    #expect(start.duration(to: .now) < .seconds(2))
    _ = flock(descriptor, LOCK_UN)
    #expect(try await h.store.profiles().isEmpty)
  }

  /// 已提交删除后，即使模拟服务器无视取消并返回旧快照也不能复活资料。
  @Test func discardsLateSnapshotAfterRemoval() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    let reader = GatedWidgetReader()
    let work = Task { await h.store.refresh(profileId: profile.id, using: reader) }
    try await reader.waitForStart()
    try await h.store.remove(instanceId: profile.instanceId)
    await reader.resolve(try WidgetTestData.snapshot(profile, at: h.now))
    #expect(await work.value == .discarded)
    #expect(try await h.store.profiles().isEmpty)
    #expect(try await h.store.cachedSnapshot(profileId: profile.id) == nil)
    #expect(h.vault.ids().isEmpty)
  }

  /// 另一仓轮换同一资料后，旧任务不能覆盖新登记的快照或删除新凭据。
  @Test func discardsLateSnapshotAfterCrossStoreRotation() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let peer = try WidgetStore(container: h.root, vault: h.vault, clock: { h.now })
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    let reader = GatedWidgetReader()
    let work = Task { await h.store.refresh(profileId: profile.id, using: reader) }
    try await reader.waitForStart()
    let rotated = try WidgetTestData.profile(
      id: profile.id, instanceId: profile.instanceId, now: h.now)
    try await peer.install(rotated, credential: WidgetTestData.secret(rotated))
    let current = try WidgetTestData.snapshot(rotated, at: h.now, value: "2")
    #expect(
      await peer.refresh(profileId: profile.id, using: ImmediateWidgetReader(current)) == .updated)
    await reader.resolve(try WidgetTestData.snapshot(profile, at: h.now, value: "old"))
    #expect(await work.value == .discarded)
    #expect(try await h.store.cachedSnapshot(profileId: profile.id) == current)
    #expect(h.vault.ids() == [rotated.registrationId])
  }

  /// 登记尚未保存资料时发生注销，也必须使迟到的新授权提交失效。
  @Test func invalidatesRegistrationTicketBeforeFirstProfileExists() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    let ticket = try await h.store.prepareRegistration(
      instanceId: profile.instanceId, owner: profile.owner)
    try await h.store.remove(instanceId: profile.instanceId)
    await #expect(throws: WidgetStoreError.staleRegistration) {
      try await h.store.install(profile, credential: WidgetTestData.secret(profile), ticket: ticket)
    }
    #expect(try await h.store.profiles().isEmpty)
    #expect(h.vault.ids().isEmpty)
  }

  /// 新操作或取消会使旧代次失效，一次性票据不能再次轮换凭据。
  @Test func replacesCancelsAndConsumesRegistrationTickets() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    let old = try await h.store.prepareRegistration(
      instanceId: profile.instanceId, owner: profile.owner)
    let current = try await h.store.prepareRegistration(
      instanceId: profile.instanceId, owner: profile.owner)
    await #expect(throws: WidgetStoreError.staleRegistration) {
      try await h.store.install(profile, credential: WidgetTestData.secret(profile), ticket: old)
    }
    try await h.store.cancelRegistration(current)
    await #expect(throws: WidgetStoreError.staleRegistration) {
      try await h.store.install(
        profile, credential: WidgetTestData.secret(profile), ticket: current)
    }
    let allowed = try await h.store.prepareRegistration(
      instanceId: profile.instanceId, owner: profile.owner)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile), ticket: allowed)
    await #expect(throws: WidgetStoreError.staleRegistration) {
      try await h.store.install(
        profile, credential: WidgetTestData.secret(profile), ticket: allowed)
    }
    #expect(try await h.store.profiles() == [profile])
  }

  /// 前一登记迟到的 401/403 只能清理前一登记，不能删除已轮换的新账号资料。
  @Test(arguments: [WidgetClientError.unauthorized, .forbidden])
  func ignoresLateRejectionAfterRotation(_ error: WidgetClientError) async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let peer = try WidgetStore(container: h.root, vault: h.vault, clock: { h.now })
    let old = try WidgetTestData.profile(now: h.now)
    try await h.store.install(old, credential: WidgetTestData.secret(old))
    let reader = GatedWidgetReader()
    let work = Task { await h.store.refresh(profileId: old.id, using: reader) }
    try await reader.waitForStart()
    let current = try WidgetTestData.profile(id: old.id, instanceId: old.instanceId, now: h.now)
    try await peer.install(current, credential: WidgetTestData.secret(current))
    await reader.fail(error)
    #expect(await work.value == .discarded)
    #expect(try await h.store.profiles() == [current])
    #expect(h.vault.ids() == [current.registrationId])
  }

  /// 多个组件共用在途读取，近期缓存避免重复联网，强制刷新仍可绕过缓存期限。
  @Test func coalescesInFlightAndRecentReads() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    let reader = GatedWidgetReader()
    let first = Task { await h.store.refresh(profileId: profile.id, using: reader) }
    try await reader.waitForStart()
    let second = Task { await h.store.refresh(profileId: profile.id, using: reader) }
    await Task.yield()
    await reader.resolve(try WidgetTestData.snapshot(profile, at: h.now))
    #expect(await first.value == .updated)
    let secondResult = await second.value
    #expect(secondResult == .updated || secondResult == .cached)
    #expect(await reader.count() == 1)
    #expect(await h.store.refresh(profileId: profile.id, using: reader) == .cached)
    let value = try WidgetTestData.snapshot(profile, at: h.now, value: "new")
    #expect(
      await h.store.refresh(profileId: profile.id, using: ImmediateWidgetReader(value), force: true)
        == .updated)
    #expect(try await h.store.cachedSnapshot(profileId: profile.id) == value)
  }

  /// 改别名不改变授权身份，也不能让同登记迟到的鉴权失败逃过清理。
  @Test func keepsRegistrationChecksIndependentOfDisplayName() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    let success = GatedWidgetReader()
    let first = Task { await h.store.refresh(profileId: profile.id, using: success) }
    try await success.waitForStart()
    try await h.store.rename(profileId: profile.id, name: "新别名")
    await success.resolve(try WidgetTestData.snapshot(profile, at: h.now))
    #expect(await first.value == .updated)
    #expect(try await h.store.profiles().first?.name == "新别名")
    let rejected = GatedWidgetReader()
    let second = Task { await h.store.refresh(profileId: profile.id, using: rejected, force: true) }
    try await rejected.waitForStart()
    try await h.store.rename(profileId: profile.id, name: "再次改名")
    await rejected.fail(.forbidden)
    #expect(await second.value == .removed)
    #expect(try await h.store.profiles().isEmpty)
  }

  /// 缓存期限和凭据期限独立受检，时钟前进后不能把旧样本标为新鲜。
  @Test func expiresSnapshotsAndCredentialsWithoutExtendingTime() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let clock = MutableWidgetClock(h.now)
    let store = try WidgetStore(container: h.root, vault: h.vault, clock: { clock.now() })
    let profile = try WidgetTestData.profile(now: h.now)
    try await store.install(profile, credential: WidgetTestData.secret(profile))
    let snapshot = try WidgetTestData.snapshot(profile, at: h.now)
    #expect(
      await store.refresh(profileId: profile.id, using: ImmediateWidgetReader(snapshot)) == .updated
    )
    clock.advance(1801)
    #expect(
      try await store.cachedSnapshot(profileId: profile.id)?.sections.first?.freshness(
        at: clock.now()) == .stale)
    clock.advance(1800)
    #expect(try await store.cachedSnapshot(profileId: profile.id) == nil)
    #expect(try await store.profiles().count == 1)
    clock.advance(86_400)
    #expect(try await store.profiles().isEmpty)
    #expect(h.vault.ids().isEmpty)
  }

  /// 网络失败保留原时间；凭据被拒绝立即清除，不能退回旧缓存继续展示。
  @Test func preservesCacheOnNetworkFailureButClearsRejectedGrants() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    let snapshot = try WidgetTestData.snapshot(profile, at: h.now)
    #expect(
      await h.store.refresh(profileId: profile.id, using: ImmediateWidgetReader(snapshot))
        == .updated)
    #expect(
      await h.store.refresh(
        profileId: profile.id, using: FailingWidgetReader(.unavailable), force: true)
        == .unavailable)
    #expect(
      try await h.store.cachedSnapshot(profileId: profile.id)?.generatedAt == snapshot.generatedAt)
    #expect(
      await h.store.refresh(
        profileId: profile.id, using: FailingWidgetReader(.unauthorized), force: true) == .removed)
    #expect(try await h.store.profiles().isEmpty)
    #expect(try await h.store.cachedSnapshot(profileId: profile.id) == nil)
  }

  /// 系统 Keychain 锁定不等于用户注销；本地移除仍马上生效，解锁后回收孤立密钥。
  @Test func handlesLockedKeychainWithoutRestoringRemovedData() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    h.vault.setLocked(true)
    #expect(
      await h.store.refresh(profileId: profile.id, using: FailingWidgetReader(.unavailable))
        == .unavailable)
    await #expect(throws: WidgetStoreError.unavailable) { try await h.store.profiles() }
    try await h.store.remove(profileId: profile.id)
    #expect(try await h.store.cachedSnapshot(profileId: profile.id) == nil)
    h.vault.setLocked(false)
    #expect(try await h.store.profiles().isEmpty)
    #expect(h.vault.ids().isEmpty)
  }

  /// 自撤销等待开始前本地已移除，离线失败也不能恢复资料或占着文件锁。
  @Test func removesLocallyBeforeBestEffortSelfRevocation() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    let probe = WidgetRevocationProbe(store: h.store)
    try await h.store.remove(profileId: profile.id, revokeWith: probe)
    #expect(await probe.count() == 1)
    #expect(try await h.store.profiles().isEmpty)
    #expect(h.vault.ids().isEmpty)
  }

  /// 账号不符不是普通网络失败，已有缓存也必须随旧资料一起清除。
  @Test func clearsForeignSnapshotInsteadOfKeepingOldCache() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let profile = try WidgetTestData.profile(now: h.now)
    try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    let value = try WidgetTestData.snapshot(profile, at: h.now)
    #expect(
      await h.store.refresh(profileId: profile.id, using: ImmediateWidgetReader(value)) == .updated)
    let foreign = try WidgetTestData.profile(owner: String(repeating: "b", count: 32), now: h.now)
    let incorrect = try WidgetTestData.snapshot(foreign, at: h.now)
    #expect(
      await h.store.refresh(
        profileId: profile.id, using: ImmediateWidgetReader(incorrect), force: true) == .removed)
    #expect(try await h.store.profiles().isEmpty)
    #expect(try await h.store.cachedSnapshot(profileId: profile.id) == nil)
  }

  /// 单个实例退出不清理另一个实例；重用资料 UUID 给另一身份会明确失败。
  @Test func isolatesInstancesAndOwnersAndRenamesWithoutRotation() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    let first = try WidgetTestData.profile(now: h.now)
    let second = try WidgetTestData.profile(now: h.now)
    for profile in [first, second] {
      try await h.store.install(profile, credential: WidgetTestData.secret(profile))
    }
    let imposter = try WidgetTestData.profile(
      id: first.id, instanceId: first.instanceId, owner: String(repeating: "b", count: 32),
      now: h.now)
    await #expect(throws: WidgetDataError.ownerMismatch) {
      try await h.store.install(imposter, credential: WidgetTestData.secret(imposter))
    }
    try await h.store.rename(profileId: second.id, name: "家庭影院")
    try await h.store.remove(instanceId: first.instanceId)
    let kept = try #require(await h.store.profiles().first)
    #expect(kept.id == second.id && kept.name == "家庭影院")
    #expect(kept.registrationId == second.registrationId)
    #expect(h.vault.ids() == [second.registrationId])
  }

  /// 超大或损坏索引必须报错；不能返回空集合掩盖未清理的实际凭据。
  @Test func rejectsOversizedCorruptAndDuplicateIndexes() async throws {
    let h = try WidgetStoreHarness()
    defer { h.cleanup() }
    _ = try await h.store.installationId()
    let url = h.root.appendingPathComponent("MoviePilotWidgets-v1/index.json")
    try Data(repeating: 32, count: 64 * 1024 + 1).write(to: url)
    await #expect(throws: WidgetDataError.oversizedData) { try await h.store.profiles() }
    try Data("{}".utf8).write(to: url)
    await #expect(throws: (any Error).self) { try await h.store.profiles() }
    let profile = try WidgetTestData.profile(now: h.now)
    let encoded = try JSONEncoder().encode(profile)
    let object = try JSONSerialization.jsonObject(with: encoded)
    try JSONSerialization.data(withJSONObject: [
      "version": 1, "installationId": UUID().uuidString, "profiles": [object, object],
      "pending": [],
    ]).write(to: url)
    await #expect(throws: WidgetDataError.invalidData) { try await h.store.profiles() }
  }
}

/// 固定时钟与临时文件根由单个测试拥有，不对共享环境产生副作用。
private struct WidgetStoreHarness: Sendable {
  let root: URL
  let now: Date
  let vault: MemoryWidgetVault
  let store: WidgetStore

  /// 创建真实目录并注入无平台副作用的凭据仓。
  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    now = Date()
    vault = MemoryWidgetVault()
    let date = now
    store = try WidgetStore(container: root, vault: vault, clock: { date })
  }

  /// 每个测试结束后只删除自己创建的临时根。
  func cleanup() { try? FileManager.default.removeItem(at: root) }
}

/// 测试时钟的所有状态都在锁内更新，不需要真实等待半小时或一天。
private final class MutableWidgetClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date
  /// 保存本测试独有的初始 UTC 时间。
  init(_ value: Date) { self.value = value }
  /// 原子读取时间，不向并行测试共享可变日期。
  func now() -> Date { lock.withLock { value } }
  /// 前进到过期边界以验证原始时间未被网络请求延长。
  func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

/// 测试凭据的可变状态全部受 NSLock 保护，支持两个独立仓并行调用。
private final class MemoryWidgetVault: WidgetCredentialVault, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [UUID: String] = [:]
  private var locked = false

  /// 以明确错误模拟系统尚未解锁，不能返回 nil。
  func read(registrationId: UUID) throws -> String? {
    try lock.withLock {
      if locked { throw WidgetStoreError.unavailable }
      return values[registrationId]
    }
  }

  /// 内存字典仅用于测试，遵守与共享 Keychain 相同的登记键。
  func save(_ credential: String, registrationId: UUID) throws {
    try lock.withLock {
      if locked { throw WidgetStoreError.unavailable }
      values[registrationId] = credential
    }
  }

  /// 回收不会误删仍然有效的其它实例条目。
  func retainOnly(registrationIds: Set<UUID>) throws {
    try lock.withLock {
      if locked { throw WidgetStoreError.unavailable }
      values = values.filter { registrationIds.contains($0.key) }
    }
  }

  /// 锁定状态按测试需要切换，方法本身不暴露密钥。
  func setLocked(_ value: Bool) { lock.withLock { locked = value } }

  /// 断言仅检查登记标识，不把凭据放进失败输出。
  func ids() -> Set<UUID> { lock.withLock { Set(values.keys) } }
}

/// 无网络的成功读取，实际快照仍走白名单编码与提交校验。
private struct ImmediateWidgetReader: WidgetSnapshotReading {
  let value: WidgetSnapshot
  /// 为异步协议提供固定的合成快照。
  init(_ value: WidgetSnapshot) { self.value = value }
  /// 立即返回值，便于检查缓存与强制刷新。
  func snapshot(profile: WidgetProfile, credential: String) async throws -> WidgetSnapshot { value }
}

/// 固定失败不会包含内部异常正文或真实主登录信息。
private struct FailingWidgetReader: WidgetSnapshotReading {
  let error: WidgetClientError
  /// 保留本测试指定的 HTTP 语义。
  init(_ error: WidgetClientError) { self.error = error }
  /// 模拟失败读取，不依赖系统网络。
  func snapshot(profile: WidgetProfile, credential: String) async throws -> WidgetSnapshot {
    throw error
  }
}

/// 撤销回调中再次读同一仓，验证本地删除和文件锁释放已完成。
private actor WidgetRevocationProbe: WidgetGrantRevoking {
  let store: WidgetStore
  private var calls = 0
  /// 本测试只持有自己的临时仓，不访问系统服务。
  init(store: WidgetStore) { self.store = store }
  /// 故意模拟离线，自撤销失败不能逆转逻辑删除。
  func revoke(profile: WidgetProfile, credential: String) async throws {
    calls += 1
    #expect(try await store.profiles().isEmpty)
    #expect(try await store.cachedSnapshot(profileId: profile.id) == nil)
    #expect(credential == WidgetTestData.secret(profile))
    throw WidgetClientError.unavailable
  }
  /// 无凭据的调用计数证明尽力撤销确实执行过。
  func count() -> Int { calls }
}

/// 故意忽略取消的迟到服务器，用于验证最终提交不能依赖传输取消成功。
private actor GatedWidgetReader: WidgetSnapshotReading {
  private var calls = 0
  private var continuation: CheckedContinuation<WidgetSnapshot, any Error>?

  /// 暂停真实读取点，让另一个仓在等待中删除或轮换登记。
  func snapshot(profile: WidgetProfile, credential: String) async throws -> WidgetSnapshot {
    calls += 1
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  /// 仅异步等待最多五秒，错误实现不会令测试无限挂起。
  func waitForStart() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while calls == 0 {
      guard ContinuousClock.now < deadline else { throw WidgetStoreError.unavailable }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  /// 提交一个不受取消影响的响应，必须由仓再次校验身份和登记。
  func resolve(_ value: WidgetSnapshot) {
    continuation?.resume(returning: value)
    continuation = nil
  }

  /// 迟到鉴权拒绝与迟到成功采用相同提交代次检查。
  func fail(_ error: WidgetClientError) {
    continuation?.resume(throwing: error)
    continuation = nil
  }

  /// 只暴露调用数，避免测试输出捕获到凭据。
  func count() -> Int { calls }
}

/// 用真实预留接口简化测试设置，不伪造或绕过提交代次。
extension WidgetStore {
  /// 通用用例在联网前预留；竞态用例直接调用带 ticket 的生产方法。
  fileprivate func install(_ profile: WidgetProfile, credential: String) async throws {
    let ticket = try prepareRegistration(instanceId: profile.instanceId, owner: profile.owner)
    try install(profile, credential: credential, ticket: ticket)
  }
}

/// 两类边界测试共用的虚构协议数据，不读取运行中的 MoviePilot。
enum WidgetTestData {
  static let owner = String(repeating: "a", count: 32)

  /// 构造合法的独立实例资料，所有身份和凭据均为随机合成值。
  static func profile(
    id: UUID = UUID(), instanceId: UUID = UUID(), owner: String = owner, now: Date = Date()
  ) throws -> WidgetProfile {
    try WidgetProfile(
      id: id, instanceId: instanceId, owner: owner, name: "测试实例",
      address: ServerAddress("https://example.test/moviepilot/"), registrationId: UUID(),
      credentialExpiresAt: now.timeIntervalSince1970 + 86_400)
  }

  /// 形状与服务器一致，但没有任何可用的真实授权。
  static func secret(_ profile: WidgetProfile) -> String {
    "mpw_\(profile.registrationId.uuidString.lowercased()).\(String(repeating: "A", count: 43))"
  }

  /// 带额外字段的输入检验白名单重新编码，未知字段不能写回共享文件。
  static func data(_ profile: WidgetProfile, at now: Date, value: String = "1") throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "version": 1, "owner": profile.owner, "generatedAt": now.timeIntervalSince1970,
      "expiresAt": now.timeIntervalSince1970 + 3600, "availableContents": ["downloads"],
      "token": "synthetic-main-token",
      "sections": [
        [
          "content": "downloads", "state": "ready", "updatedAt": now.timeIntervalSince1970,
          "title": "下载",
          "metrics": [["id": "tasks", "title": "任务", "value": value, "icon": "download"]],
          "items": [],
        ]
      ],
    ])
  }

  /// 通过生产解码入口创建测试快照，而非绕过模型约束。
  static func snapshot(_ profile: WidgetProfile, at now: Date, value: String = "1") throws
    -> WidgetSnapshot
  {
    try WidgetSnapshot.decode(data(profile, at: now, value: value), owner: profile.owner, now: now)
  }
}
