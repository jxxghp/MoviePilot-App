import Darwin
import Foundation

/// 平台共享 Keychain 的窄接口；主登录凭据不得使用此命名空间。
public protocol WidgetCredentialVault: Sendable {
  /// 只有确实不存在才返回 nil；首次解锁前等系统限制应抛错，不冒充注销。
  func read(registrationId: UUID) throws -> String?
  /// 值仅在当前登记内有效，平台实现必须使用 ThisDeviceOnly 且禁止 iCloud 同步。
  func save(_ credential: String, registrationId: UUID) throws
  /// 清理已删除或中断提交留下的孤立登记，不能触碰主 App 的其它 Keychain 服务。
  func retainOnly(registrationIds: Set<UUID>) throws
}

/// 扩展只读取固定快照；HTTP 实现不得共享网页 Cookie 或主 token。
public protocol WidgetSnapshotReading: Sendable {
  /// 每次读取仍由后端复核最新身份和权限，返回有界的白名单模型。
  func snapshot(profile: WidgetProfile, credential: String) async throws -> WidgetSnapshot
}

/// 本地移除完成后的尽力自撤销，不接受他人的登记标识。
public protocol WidgetGrantRevoking: Sendable {
  /// 网络失败不阻止资料从本地索引和界面消失。
  func revoke(profile: WidgetProfile, credential: String) async throws
}

/// 磁盘和 Keychain 暂不可用时保持失败可见，不伪造空资料或成功计数。
public enum WidgetStoreError: Error, Equatable, Sendable {
  case unavailable, capacityReached, staleRegistration
}

/// 主 App 在联网登记前取得的一次性提交代次；不是访问凭据，也不进入链接。
public struct WidgetRegistrationTicket: Codable, Equatable, Sendable {
  fileprivate let id: UUID
  fileprivate let instanceId: UUID
  fileprivate let owner: String

  /// 预留和持久化恢复共用当前不可变身份的有限格式。
  fileprivate static func validOwner(_ value: String) -> Bool {
    value.utf8.count == 32
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

/// 刷新结果与快照时间分别保存；使用缓存不能把旧数据变成刚刚采样。
public enum WidgetRefreshOutcome: Equatable, Sendable {
  case updated, cached, unavailable, removed, discarded
}

/// App 和扩展共用的有界资料仓；actor 管本进程，flock 管跨进程提交。
public actor WidgetStore {
  private let directory: URL
  private let vault: any WidgetCredentialVault
  private let clock: @Sendable () -> Date
  private var refreshes: [UUID: Task<WidgetRefreshOutcome, Never>] = [:]
  private static let maximumIndexBytes = 64 * 1024

  /// 只接受平台已确认授权的共享容器；本类型不会猜测组名或申请系统权限。
  public init(
    container: URL, vault: any WidgetCredentialVault,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    guard container.isFileURL else { throw WidgetDataError.invalidData }
    directory = container.appendingPathComponent("MoviePilotWidgets-v1", isDirectory: true)
    self.vault = vault
    self.clock = clock
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }

  /// 本机随机安装标识与索引一起原子保存，不依赖账号名或可重用数字 ID。
  public func installationId() throws -> UUID {
    try locked {
      let index = try readIndex()
      if !FileManager.default.fileExists(atPath: indexURL.path) { try writeIndex(index) }
      return index.installationId
    }
  }

  /// 过期登记立即从可配置集合移除；Keychain 锁定的错误不伪装成没有资料。
  public func profiles() throws -> [WidgetProfile] {
    try locked {
      var index = try readIndex()
      let expired = index.profiles.filter { !valid($0, at: clock()) }
      if !expired.isEmpty {
        index.profiles.removeAll { expired.contains($0) }
        try writeIndex(index)
        for profile in expired {
          retire(profile)
          refreshes[profile.registrationId]?.cancel()
        }
      }
      try vault.retainOnly(registrationIds: Set(index.profiles.map(\.registrationId)))
      return index.profiles
    }
  }

  /// 登记前先预留代次；注销即使发生在第一个资料保存前也能使旧响应失效。
  public func prepareRegistration(instanceId: UUID, owner: String) throws
    -> WidgetRegistrationTicket
  {
    guard WidgetRegistrationTicket.validOwner(owner) else { throw WidgetDataError.invalidData }
    return try locked {
      var index = try readIndex()
      index.pending.removeAll { $0.instanceId == instanceId }
      guard index.pending.count < 10 else { throw WidgetStoreError.capacityReached }
      let ticket = WidgetRegistrationTicket(id: UUID(), instanceId: instanceId, owner: owner)
      index.pending.append(ticket)
      try writeIndex(index)
      return ticket
    }
  }

  /// 关闭设置或取消登记仅撤销该代次，不删除已发布的其它资料。
  public func cancelRegistration(_ ticket: WidgetRegistrationTicket) throws {
    try locked {
      var index = try readIndex()
      index.pending.removeAll { $0 == ticket }
      try writeIndex(index)
    }
  }

  /// 登记先落 Keychain 再原子发布资料；失效代次不能发布迟到的凭据。
  public func install(
    _ profile: WidgetProfile, credential: String, ticket: WidgetRegistrationTicket
  ) throws {
    guard valid(profile, at: clock()),
      profile.credentialExpiresAt <= clock().timeIntervalSince1970 + 30 * 86_400 + 300,
      Self.validCredential(credential, registrationId: profile.registrationId)
    else { throw WidgetDataError.invalidData }
    try locked {
      var index = try readIndex()
      guard index.pending.contains(ticket), ticket.instanceId == profile.instanceId,
        ticket.owner == profile.owner
      else { throw WidgetStoreError.staleRegistration }
      guard
        !index.profiles.contains(where: {
          ($0.id == profile.id
            && ($0.instanceId != profile.instanceId || $0.owner != profile.owner))
            || ($0.registrationId == profile.registrationId && $0.id != profile.id)
        })
      else { throw WidgetDataError.ownerMismatch }
      let previous = index.profiles.filter { $0.instanceId == profile.instanceId }
      let retained = index.profiles.filter { $0.instanceId != profile.instanceId }
      guard retained.count < 10 else { throw WidgetStoreError.capacityReached }
      let previousIds = Set(index.profiles.map(\.registrationId))
      try vault.save(credential, registrationId: profile.registrationId)
      index.profiles = retained + [profile]
      index.pending.removeAll { $0 == ticket }
      do {
        try writeIndex(index)
      } catch {
        try? vault.retainOnly(registrationIds: previousIds)
        throw error
      }
      for old in previous where old != profile { retire(old) }
      try? vault.retainOnly(registrationIds: Set(index.profiles.map(\.registrationId)))
    }
  }

  /// 别名只更新展示资料，不轮换凭据，也不扩大所选账号的内容权限。
  public func rename(profileId: UUID, name: String) throws {
    try locked {
      var index = try readIndex()
      guard let position = index.profiles.firstIndex(where: { $0.id == profileId }) else { return }
      let old = index.profiles[position]
      index.profiles[position] = try WidgetProfile(
        id: old.id, instanceId: old.instanceId, owner: old.owner, name: name, address: old.address,
        registrationId: old.registrationId, credentialExpiresAt: old.credentialExpiresAt)
      try writeIndex(index)
    }
  }

  /// 仅返回该资料未过期的白名单快照，不因断网或新请求而延长旧时间。
  public func cachedSnapshot(profileId: UUID) throws -> WidgetSnapshot? {
    try locked {
      guard let profile = try readIndex().profiles.first(where: { $0.id == profileId }),
        valid(profile, at: clock())
      else { return nil }
      return try cached(profile)
    }
  }

  /// 同资料的请求共用一个有界任务；跨进程仍在最终提交前重新核对登记。
  public func refresh(
    profileId: UUID, using reader: any WidgetSnapshotReading, force: Bool = false
  ) async -> WidgetRefreshOutcome {
    let lease: WidgetLease
    do {
      guard let value = try locked({ try loadLease(profileId) }) else { return .removed }
      lease = value
      if !force, let cached = try locked({ try cached(lease.profile) }),
        clock().timeIntervalSince1970 - cached.generatedAt < 900
      {
        return .cached
      }
    } catch { return .unavailable }
    if let task = refreshes[lease.profile.registrationId] { return await task.value }
    let task = Task { await performRefresh(lease, using: reader) }
    refreshes[lease.profile.registrationId] = task
    let result = await task.value
    refreshes[lease.profile.registrationId] = nil
    return result
  }

  /// 先从索引删除，再尽力自撤销；迟到刷新无法复活已经移除的资料。
  public func remove(profileId: UUID, revokeWith revoker: (any WidgetGrantRevoking)? = nil)
    async throws
  {
    let removed = try locked {
      let instanceId = try readIndex().profiles.first(where: { $0.id == profileId })?.instanceId
      return try erase(where: { $0.id == profileId }, pendingInstanceId: instanceId)
    }
    for lease in removed {
      if let revoker {
        try? await revoker.revoke(profile: lease.profile, credential: lease.credential)
      }
    }
  }

  /// 注销或忘记实例只清理该独立 WebKit 容器的资料，不影响其它已启用实例。
  public func remove(instanceId: UUID, revokeWith revoker: (any WidgetGrantRevoking)? = nil)
    async throws
  {
    let removed = try locked {
      try erase(where: { $0.instanceId == instanceId }, pendingInstanceId: instanceId)
    }
    for lease in removed {
      if let revoker {
        try? await revoker.revoke(profile: lease.profile, credential: lease.credential)
      }
    }
  }

  /// 快照读取不持有文件锁；提交时核对当前资料、凭据期限和取消状态。
  private func performRefresh(_ lease: WidgetLease, using reader: any WidgetSnapshotReading) async
    -> WidgetRefreshOutcome
  {
    do {
      let value = try await reader.snapshot(profile: lease.profile, credential: lease.credential)
      guard !Task.isCancelled else { return .discarded }
      return try locked {
        guard try readIndex().profiles.contains(where: { sameRegistration($0, lease.profile) }),
          valid(lease.profile, at: clock())
        else { return .discarded }
        let data = try value.encoded()
        let checked = try WidgetSnapshot.decode(data, owner: lease.profile.owner, now: clock())
        guard !checked.isExpired(at: clock()),
          checked.expiresAt <= lease.profile.credentialExpiresAt
        else { throw WidgetDataError.invalidData }
        try write(data, to: snapshotURL(lease.profile.id))
        return .updated
      }
    } catch WidgetClientError.unauthorized, WidgetClientError.forbidden, WidgetDataError
      .ownerMismatch
    {
      return
        (try? locked {
          guard try readIndex().profiles.contains(where: { sameRegistration($0, lease.profile) })
          else {
            return WidgetRefreshOutcome.discarded
          }
          _ = try erase { sameRegistration($0, lease.profile) }
          return WidgetRefreshOutcome.removed
        }) ?? .unavailable
    } catch { return Task.isCancelled ? .discarded : .unavailable }
  }

  /// 索引发布前取得临时读取票据，系统 Keychain 锁定与真正缺失采用不同路径。
  private func loadLease(_ profileId: UUID) throws -> WidgetLease? {
    guard let profile = try readIndex().profiles.first(where: { $0.id == profileId }) else {
      return nil
    }
    guard valid(profile, at: clock()) else {
      _ = try erase { $0.id == profileId }
      return nil
    }
    guard let credential = try vault.read(registrationId: profile.registrationId),
      Self.validCredential(credential, registrationId: profile.registrationId)
    else {
      _ = try erase { $0.id == profileId }
      return nil
    }
    return WidgetLease(profile: profile, credential: credential)
  }

  /// 逻辑删除优先于磁盘/Keychain垃圾回收，后续访问会再次清理孤立凭据。
  private func erase(
    where matches: (WidgetProfile) -> Bool, pendingInstanceId: UUID? = nil
  ) throws -> [WidgetLease] {
    var index = try readIndex()
    let removed = index.profiles.filter(matches)
    let previousPendingCount = index.pending.count
    if let pendingInstanceId { index.pending.removeAll { $0.instanceId == pendingInstanceId } }
    guard !removed.isEmpty || index.pending.count != previousPendingCount else { return [] }
    let leases = removed.compactMap { profile -> WidgetLease? in
      guard let value = try? vault.read(registrationId: profile.registrationId),
        Self.validCredential(value, registrationId: profile.registrationId)
      else { return nil }
      return WidgetLease(profile: profile, credential: value)
    }
    index.profiles.removeAll(where: matches)
    try writeIndex(index)
    for profile in removed {
      retire(profile)
      refreshes[profile.registrationId]?.cancel()
    }
    try? vault.retainOnly(registrationIds: Set(index.profiles.map(\.registrationId)))
    return leases
  }

  /// 缓存内容必须仍属于当前资料；文件损坏不能被格式化成成功的零。
  private func cached(_ profile: WidgetProfile) throws -> WidgetSnapshot? {
    guard let data = try read(snapshotURL(profile.id), maximum: WidgetSnapshot.maximumBytes) else {
      return nil
    }
    let value = try WidgetSnapshot.decode(data, owner: profile.owner, now: clock())
    guard !value.isExpired(at: clock()), value.expiresAt <= profile.credentialExpiresAt else {
      retire(profile)
      return nil
    }
    return value
  }

  /// 只删除固定 UUID 对应的快照；物理清理失败也不能恢复已删除的索引引用。
  private func retire(_ profile: WidgetProfile) {
    try? FileManager.default.removeItem(at: snapshotURL(profile.id))
  }

  /// 后台和冷启动采用相同凭据期限，不依赖网页最后一次连接状态。
  private func valid(_ profile: WidgetProfile, at now: Date) -> Bool {
    now.timeIntervalSince1970.isFinite && profile.credentialExpiresAt > now.timeIntervalSince1970
  }

  /// 别名变化不属于授权轮换；账号、实例、地址、登记和期限必须仍一致。
  private func sameRegistration(_ current: WidgetProfile, _ expected: WidgetProfile) -> Bool {
    current.id == expected.id && current.instanceId == expected.instanceId
      && current.owner == expected.owner && current.address == expected.address
      && current.registrationId == expected.registrationId
      && current.credentialExpiresAt == expected.credentialExpiresAt
  }

  /// 凭据必须绑定本登记，不能把普通 JWT、Cookie 或任意字符串发往扩展端点。
  static func validCredential(_ value: String, registrationId: UUID) -> Bool {
    let prefix = "mpw_\(registrationId.uuidString.lowercased())."
    guard value.hasPrefix(prefix) else { return false }
    let suffix = value.dropFirst(prefix.count).utf8
    return suffix.count == 43
      && suffix.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || $0 == 45 || $0 == 95
      }
  }

  /// 文件名完全来自本地 UUID；外部载荷不能选择任意路径。
  private func snapshotURL(_ id: UUID) -> URL {
    directory.appendingPathComponent("\(id.uuidString).json")
  }

  /// 小索引与快照共用同一文件锁，避免两个扩展进程覆盖各自的资料变化。
  private var indexURL: URL { directory.appendingPathComponent("index.json") }

  /// 解码及再次验证持久化索引的基数、版本和唯一身份。
  private func readIndex() throws -> WidgetStoreIndex {
    guard let data = try read(indexURL, maximum: Self.maximumIndexBytes) else {
      return WidgetStoreIndex(installationId: UUID(), profiles: [])
    }
    let value = try JSONDecoder().decode(WidgetStoreIndex.self, from: data)
    guard value.version == 1, value.profiles.count <= 10,
      Set(value.profiles.map(\.id)).count == value.profiles.count,
      Set(value.profiles.map(\.instanceId)).count == value.profiles.count,
      Set(value.profiles.map(\.registrationId)).count == value.profiles.count,
      value.pending.count <= 10,
      Set(value.pending.map(\.id)).count == value.pending.count,
      Set(value.pending.map(\.instanceId)).count == value.pending.count,
      value.pending.allSatisfy({ WidgetRegistrationTicket.validOwner($0.owner) })
    else { throw WidgetDataError.invalidData }
    return value
  }

  /// 编码只含声明字段，未知原始 JSON 不进入下一次共享写入。
  private func writeIndex(_ value: WidgetStoreIndex) throws {
    let data = try JSONEncoder().encode(value)
    guard data.count <= Self.maximumIndexBytes else { throw WidgetDataError.oversizedData }
    try write(data, to: indexURL)
  }

  /// 先限制读取量再解码，损坏的大文件不会被整包映射进扩展内存。
  private func read(_ url: URL, maximum: Int) throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximum + 1) ?? Data()
    guard data.count <= maximum else { throw WidgetDataError.oversizedData }
    return data
  }

  /// iOS 文件采用首次解锁后保护；锁屏组件不会通过明文文件共享任何凭据。
  private func write(_ data: Data, to url: URL) throws {
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    try data.write(to: url, options: options)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  /// 临界区不联网或 await；其它进程被系统暂停时，最多等待 250ms 后明确失败。
  private func locked<T>(_ operation: () throws -> T) throws -> T {
    let lockURL = directory.appendingPathComponent("store.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw WidgetStoreError.unavailable }
    defer { close(descriptor) }
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(250))
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      guard errno == EWOULDBLOCK || errno == EINTR, ContinuousClock.now < deadline else {
        throw WidgetStoreError.unavailable
      }
      usleep(10_000)
    }
    defer { _ = flock(descriptor, LOCK_UN) }
    return try operation()
  }
}

/// 私有索引没有凭据，数量和文本在恢复时再次受检。
private struct WidgetStoreIndex: Codable {
  var version = 1
  let installationId: UUID
  var profiles: [WidgetProfile]
  var pending: [WidgetRegistrationTicket] = []
}

/// 仅在一次在途任务内持有的 Keychain 副本，不能编码、缓存或输出调试正文。
private struct WidgetLease: Sendable, CustomDebugStringConvertible {
  let profile: WidgetProfile
  let credential: String
  var debugDescription: String { "WidgetLease(<redacted>)" }
}
