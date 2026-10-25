import MoviePilotCore
import UIKit
import WidgetKit

/// 已配套只读扩展的产品能力开关；网页无法通过桥消息改变此配置。
@MainActor
enum WidgetFeature {
  /// 由受版本管理的 App 配置控制，缺失字段保持默认关闭。
  static var isEnabled: Bool {
    Bundle.main.object(forInfoDictionaryKey: "MoviePilotWidgetsEnabled") as? Bool == true
  }
}

/// 设置只展示当前主登录的身份与本机启用资料，不携带专用 secret。
struct WidgetSettingsState {
  let context: WidgetAccountContext
  let profile: WidgetProfile?
  let generatedAt: Date?
}

/// 主 App 的系统集成服务；登记仍通过当前 Vue 身份，扩展只读取独立只读凭据。
@MainActor
final class WidgetService {
  static let shared = WidgetService()
  private var repository: WidgetStore?
  private lazy var client = WidgetSnapshotClient()
  private var epochs: [UUID: Int] = [:]
  private var cleanups: [UUID: Task<Void, Never>] = [:]
  private var cleanupFailures: Set<UUID> = []
  private var probes: [UUID: Task<Void, Never>] = [:]
  private var pendingOpen: PendingOpen?
  private var opening: Task<Void, Never>?
  private var openAttempt: UUID?

  /// 外部链接只短暂保留本机资料和有限内容，不能携带认证或跨账号继承。
  private struct PendingOpen {
    let id = UUID()
    let profile: WidgetProfile
    let content: WidgetContent
    let created = Date()
  }

  /// 普通启动不读取共享区域，也不为未启用用户发送任何新增请求。
  private init() {}

  /// 真实平台授权失败时明确不可用，不回退到主 App 沙箱或主认证 Keychain。
  private func store() throws -> WidgetStore {
    guard WidgetFeature.isEnabled else { throw WidgetBridgeError.unsupported }
    if let repository { return repository }
    let opened = try WidgetSharedStorage.open()
    repository = opened
    return opened
  }

  /// 取消旧代次；普通实例切换保留已启用资料，账号失效则先移除本机资料再尽力自撤销。
  func endSession(instanceId: UUID, clear: Bool) {
    guard WidgetFeature.isEnabled else { return }
    epochs[instanceId, default: 0] += 1
    probes.removeValue(forKey: instanceId)?.cancel()
    if pendingOpen?.profile.instanceId == instanceId {
      opening?.cancel()
      opening = nil
      openAttempt = nil
      if clear { pendingOpen = nil }
    }
    guard clear else { return }
    let previous = cleanups[instanceId]
    cleanups[instanceId] = Task { [weak self] in
      await previous?.value
      guard let self else { return }
      do {
        let repository = try self.store()
        try await repository.remove(instanceId: instanceId, revokeWith: self.client)
        self.cleanupFailures.remove(instanceId)
      } catch { self.cleanupFailures.insert(instanceId) }
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  /// 同实例的新操作等待既有清理结束，旧注销任务不能在新登记后反过来删除新资料。
  private func prepare(_ coordinator: WebCoordinator, epoch: Int) async throws -> WidgetStore {
    await cleanups[coordinator.instance.id]?.value
    try check(coordinator, epoch: epoch)
    guard !cleanupFailures.contains(coordinator.instance.id) else {
      throw WidgetBridgeError.unavailable
    }
    return try store()
  }

  /// 每个等待边界后复核同一主文档的服务代次和能力，避免切号、后台和旧视图继续提交。
  private func check(_ coordinator: WebCoordinator, epoch: Int) throws {
    try Task.checkCancellation()
    guard coordinator.widgetsAvailable, epochs[coordinator.instance.id, default: 0] == epoch else {
      throw WidgetBridgeError.cancelled
    }
  }

  /// 显式打开设置才读取当前上下文；旧账号资料不能显示为当前账号已启用。
  func settings(_ coordinator: WebCoordinator) async throws -> WidgetSettingsState {
    let epoch = epochs[coordinator.instance.id, default: 0]
    let repository = try await prepare(coordinator, epoch: epoch)
    let profiles = try await repository.profiles()
    try check(coordinator, epoch: epoch)
    let response: WidgetBridgeResponse
    do { response = try await coordinator.widgetRequest(.context) } catch {
      clearIfUnauthorized(error, instanceId: coordinator.instance.id)
      throw error
    }
    try check(coordinator, epoch: epoch)
    guard case .context(let context) = response else { throw WidgetBridgeError.invalidData }
    var profile = profiles.first { $0.instanceId == coordinator.instance.id }
    if let old = profile, old.owner != context.owner || context.availableContents.isEmpty {
      try await repository.remove(profileId: old.id, revokeWith: client)
      try check(coordinator, epoch: epoch)
      profile = nil
      WidgetCenter.shared.reloadAllTimelines()
    }
    let snapshot: WidgetSnapshot?
    if let profile {
      snapshot = try await repository.cachedSnapshot(profileId: profile.id)
    } else {
      snapshot = nil
    }
    try check(coordinator, epoch: epoch)
    return WidgetSettingsState(
      context: context, profile: profile,
      generatedAt: snapshot.map { Date(timeIntervalSince1970: $0.generatedAt) })
  }

  /// 只为已启用资料在前台复核身份；未启用实例、旧网页与普通路由切换不产生网络请求。
  func reconcile(with coordinator: WebCoordinator) {
    guard coordinator.widgetsAvailable, probes[coordinator.instance.id] == nil else { return }
    let instanceId = coordinator.instance.id
    let epoch = epochs[instanceId, default: 0]
    probes[instanceId] = Task { [weak self, weak coordinator] in
      guard let self, let coordinator else { return }
      defer {
        if self.epochs[instanceId, default: 0] == epoch {
          self.probes[instanceId] = nil
          self.resumePending(with: coordinator)
        }
      }
      do {
        let repository = try await self.prepare(coordinator, epoch: epoch)
        guard try await repository.profiles().contains(where: { $0.instanceId == instanceId })
        else { return }
        let state = try await self.settings(coordinator)
        if let profile = state.profile {
          try self.check(coordinator, epoch: epoch)
          let result = await repository.refresh(profileId: profile.id, using: self.client)
          if result == .updated || result == .removed { WidgetCenter.shared.reloadAllTimelines() }
        }
      } catch {
        // 网络或系统锁定不伪造成功；设置页保留明确重试入口。
      }
    }
  }

  /// 用户明确启用或续期才登记；一次性持久化 ticket 阻止注销后迟到响应复活。
  func enable(_ coordinator: WebCoordinator, name: String) async throws {
    let trimmed = try displayName(name)
    let epoch = epochs[coordinator.instance.id, default: 0]
    let state = try await settings(coordinator)
    guard !state.context.availableContents.isEmpty else { throw WidgetBridgeError.forbidden }
    let repository = try await prepare(coordinator, epoch: epoch)
    let installation = try await repository.installationId()
    try check(coordinator, epoch: epoch)
    let ticket = try await repository.prepareRegistration(
      instanceId: coordinator.instance.id, owner: state.context.owner)
    var received: (WidgetProfile, String)?
    do {
      try check(coordinator, epoch: epoch)
      let response = try await coordinator.widgetRequest(
        .register(owner: state.context.owner, installationId: installation))
      try check(coordinator, epoch: epoch)
      guard case .registered(let reply) = response else { throw WidgetBridgeError.invalidData }
      let profile = try WidgetProfile(
        id: state.profile?.id ?? UUID(), instanceId: coordinator.instance.id,
        owner: reply.context.owner,
        name: trimmed, address: coordinator.instance.address, registrationId: reply.registrationId,
        credentialExpiresAt: reply.expiresAt)
      received = (profile, reply.secret)
      try await repository.install(profile, credential: reply.secret, ticket: ticket)
      received = nil
      try check(coordinator, epoch: epoch)
      _ = await repository.refresh(profileId: profile.id, using: client, force: true)
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      try? await repository.cancelRegistration(ticket)
      if let (profile, secret) = received {
        try? await client.revoke(profile: profile, credential: secret)
      }
      clearIfUnauthorized(error, instanceId: coordinator.instance.id)
      throw error
    }
  }

  /// 改名只作用于本机显示；不发送业务更新，也不延长只读凭据有效期。
  func rename(_ coordinator: WebCoordinator, profile: WidgetProfile, name: String) async throws {
    let trimmed = try displayName(name)
    let epoch = epochs[coordinator.instance.id, default: 0]
    let repository = try await prepare(coordinator, epoch: epoch)
    guard profile.instanceId == coordinator.instance.id else {
      throw WidgetBridgeError.invalidRequest
    }
    try await repository.rename(profileId: profile.id, name: trimmed)
    WidgetCenter.shared.reloadAllTimelines()
  }

  /// 手动刷新跳过近期缓存；失败不会把上次采样时间改成当前时间。
  func refresh(_ coordinator: WebCoordinator, profile: WidgetProfile) async throws
    -> WidgetRefreshOutcome
  {
    let epoch = epochs[coordinator.instance.id, default: 0]
    let repository = try await prepare(coordinator, epoch: epoch)
    guard profile.instanceId == coordinator.instance.id else {
      throw WidgetBridgeError.invalidRequest
    }
    let outcome = await repository.refresh(profileId: profile.id, using: client, force: true)
    WidgetCenter.shared.reloadAllTimelines()
    return outcome
  }

  /// 先在同一主循环撤销服务代次，再等待本机删除和有限的尽力自撤销。
  func disable(_ coordinator: WebCoordinator) async throws {
    endSession(instanceId: coordinator.instance.id, clear: true)
    await cleanups[coordinator.instance.id]?.value
    if cleanupFailures.contains(coordinator.instance.id) { throw WidgetBridgeError.unavailable }
  }

  /// 先从实际共享仓查找链接原资料，不按 UUID 猜测服务器，也不替换成当前账号。
  func receive(_ link: WidgetLink) async throws -> WidgetProfile {
    cancelOpen()
    let repository = try store()
    guard let profile = try await repository.profiles().first(where: { $0.id == link.profileId })
    else { throw WidgetBridgeError.invalidRequest }
    try Task.checkCancellation()
    pendingOpen = PendingOpen(profile: profile, content: link.content)
    return profile
  }

  /// 用户主动切换连接或忘记实例时停止接续，旧链接不能在后来登录后突然生效。
  func cancelOpen() {
    pendingOpen = nil
    opening?.cancel()
    opening = nil
    openAttempt = nil
  }

  /// 冷热启动均等当前主登录、桥和弹层就绪；前置身份查询可取消，实际路由意图至多发送一次。
  func resumePending(with coordinator: WebCoordinator) {
    guard let pending = pendingOpen, opening == nil,
      coordinator.instance.id == pending.profile.instanceId,
      coordinator.instance.address == pending.profile.address
    else { return }
    guard Date().timeIntervalSince(pending.created) < 300 else {
      cancelOpen()
      return
    }
    guard coordinator.widgetNavigationReady, probes[coordinator.instance.id] == nil
    else { return }
    let attempt = UUID()
    let epoch = epochs[coordinator.instance.id, default: 0]
    openAttempt = attempt
    opening = Task { [weak self, weak coordinator] in
      guard let self, let coordinator else { return }
      defer {
        if self.openAttempt == attempt {
          self.openAttempt = nil
          self.opening = nil
        }
      }
      do {
        let repository = try await self.prepare(coordinator, epoch: epoch)
        guard
          let profile = try await repository.profiles().first(where: {
            $0.id == pending.profile.id && $0.instanceId == pending.profile.instanceId
              && $0.owner == pending.profile.owner && $0.address == pending.profile.address
          })
        else { throw WidgetBridgeError.identityChanged }
        try self.check(coordinator, epoch: epoch)
        guard self.pendingOpen?.id == pending.id else { return }
        let response = try await coordinator.widgetRequest(.context)
        try self.check(coordinator, epoch: epoch)
        guard self.pendingOpen?.id == pending.id else { return }
        guard case .context(let context) = response, context.owner == profile.owner else {
          throw WidgetBridgeError.identityChanged
        }
        guard context.availableContents.contains(pending.content) else {
          throw WidgetBridgeError.forbidden
        }
        // 先消费再发送；后台或文档变化发生在路由提交后时，不能再次重放该点击。
        self.pendingOpen = nil
        _ = try await coordinator.widgetRequest(
          .open(owner: profile.owner, content: pending.content))
      } catch {
        guard self.openAttempt == attempt else { return }
        if Task.isCancelled || (error as? WidgetBridgeError) == .cancelled { return }
        if self.pendingOpen?.id == pending.id { self.pendingOpen = nil }
        if let failure = error as? WidgetBridgeError,
          [.unauthorized, .forbidden, .identityChanged].contains(failure),
          let repository = try? self.store(),
          let profile = try? await repository.profiles().first(where: {
            $0.id == pending.profile.id && $0.owner == pending.profile.owner
          })
        {
          try? await repository.remove(profileId: profile.id, revokeWith: self.client)
          WidgetCenter.shared.reloadAllTimelines()
        }
        coordinator.shell?.showNotificationMessage("无法打开此小组件，请检查当前账号权限或重新启用资料。")
      }
    }
  }

  /// 明确的身份或权限失败立即清理；断网、取消和不支持不冒充注销。
  private func clearIfUnauthorized(_ error: any Error, instanceId: UUID) {
    if let error = error as? WidgetBridgeError,
      error == .unauthorized || error == .forbidden || error == .identityChanged
    {
      endSession(instanceId: instanceId, clear: true)
    }
  }

  /// 登记前就校验本机显示名称，输入错误不能产生服务端凭据或改变已有资料。
  private func displayName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.utf8.count <= 80,
      !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw WidgetBridgeError.invalidRequest }
    return trimmed
  }
}
