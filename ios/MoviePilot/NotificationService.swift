import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import UIKit
import UserNotifications

/// 系统通知生命周期与待处理点击；只有当前已登录原生实例可消费通知。
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
  static let shared = NotificationService()
  static let installation: String = {
    let key = "moviepilot.notification.installation"
    if let value = UserDefaults.standard.string(forKey: key) { return value }
    let value = UUID().uuidString
    UserDefaults.standard.set(value, forKey: key)
    return value
  }()
  private(set) weak var nativeSession: NativeSession?
  private(set) var owner: String?
  private(set) var token: String?
  private(set) var registrationError: String?
  private var pending: (NotificationIntent, Date)?
  private var identityProbe: Task<Void, Never>?
  private var identityProbeID = UUID()
  private var lastHandledNotificationID: String?

  /// 发布包默认生产 APNs；开发签名须在构建时选择与描述文件一致的环境。
  var environment: String? {
    let value = Bundle.main.object(forInfoDictionaryKey: "MoviePilotAPNsEnvironment") as? String
    if value == "development" { return "sandbox" }
    return value == "production" ? "production" : nil
  }

  /// 按当前实例 UUID 与已验证用户 ID 构造不可变通知 owner 的本地缓存键，防止跨实例或跨账号串用。
  private static func ownerCacheKey(for session: NativeSession) -> String {
    "moviepilot.notification.owner.\(session.instance.id).\(session.user.id)"
  }

  /// 校验服务端返回的不可变 owner 格式。
  private static func isValidOwner(_ value: String) -> Bool {
    value.range(of: "^[a-zA-Z0-9_-]{16,64}$", options: .regularExpression) != nil
  }

  /// 删除已保存服务时同步清理该实例关联的本机通知身份与开关记录。
  func clearStoredState(for instanceID: UUID) {
    let defaults = UserDefaults.standard
    let ownerPrefix = "moviepilot.notification.owner.\(instanceID)."
    let enabledPrefix = "moviepilot.notification.enabled.\(instanceID)."
    for key in defaults.dictionaryRepresentation().keys
    where key.hasPrefix(ownerPrefix) || key.hasPrefix(enabledPrefix) {
      defaults.removeObject(forKey: key)
    }
  }

  /// 原生会话接入系统通知生命周期：立即撤销旧身份，优先恢复同实例同用户已验证的不可变 owner，并在后台复核远端状态。
  func attachNative(_ session: NativeSession?) {
    identityProbe?.cancel()
    identityProbe = nil
    nativeSession = session
    owner = nil
    guard let session else { return }
    if let cachedOwner = UserDefaults.standard.string(forKey: Self.ownerCacheKey(for: session)),
      Self.isValidOwner(cachedOwner)
    {
      owner = cachedOwner
      consumePending()
      if enabled {
        UIApplication.shared.registerForRemoteNotifications()
      }
    }
    let hasPending = pending != nil
    let prefix = "moviepilot.notification.enabled.\(session.instance.id)."
    let hasSavedPref = UserDefaults.standard.dictionaryRepresentation().keys.contains {
      $0.hasPrefix(prefix) && UserDefaults.standard.bool(forKey: $0)
    }
    guard hasPending || hasSavedPref || owner != nil else { return }
    let probeID = UUID()
    identityProbeID = probeID
    identityProbe = Task { [weak self, weak session] in
      defer {
        if let self, self.identityProbeID == probeID {
          self.identityProbe = nil
        }
      }
      guard let self, let session else { return }
      let retryDelays: [Duration] = [.zero, .milliseconds(900), .seconds(2)]
      for (index, delay) in retryDelays.enumerated() {
        if index > 0 {
          guard !Task.isCancelled, self.nativeSession === session,
            self.pending != nil, self.owner == nil
          else { return }
          try? await Task.sleep(for: delay)
        }
        guard !Task.isCancelled, self.nativeSession === session else { return }
        do {
          let data = try await self.nativeRequest(session: session, action: "status")
          guard !Task.isCancelled, self.nativeSession === session else { return }
          if case .string(let resolvedOwner) = data["owner"], Self.isValidOwner(resolvedOwner) {
            self.identified(resolvedOwner)
          }
          return
        } catch {
          // 锁屏唤醒瞬间网络切换可能短暂失败；若仍有待消费点击且尚未拿到 owner 则按退避重试，否则静默结束。
        }
      }
    }
  }

  /// 原生直连 `POST /api/v1/notification/app`。
  func nativeRequest(
    session: NativeSession, action: String, extra: [String: String] = [:]
  ) async throws -> [String: JSONValue] {
    guard ["status", "pair", "register", "unregister", "test"].contains(action) else {
      throw NotificationFailure(message: L10n.text("不支持的通知操作。"))
    }
    var payload = extra
    payload["action"] = action
    payload["installation"] = Self.installation
    payload["origin"] = String(session.instance.address.url.absoluteString.dropLast())
    let body = try JSONEncoder().encode(payload)
    let endpoint = try APIEndpoint(path: ["notification", "app"], method: .post, body: body)
    return try await session.request(endpoint, as: [String: JSONValue].self).value
  }

  /// 登录状态从现有已认证接口确认，不能信任推送正文声称的当前用户。
  func identified(_ value: String) {
    owner = value
    if let session = nativeSession, Self.isValidOwner(value) {
      UserDefaults.standard.set(value, forKey: Self.ownerCacheKey(for: session))
    }
    consumePending()
    if enabled {
      UIApplication.shared.registerForRemoteNotifications()
    }
  }

  /// 显式开启时先复查渠道与账号，再申请权限；配置失败不能误报未登录或消耗系统授权。
  func enable() async -> String {
    guard environment != nil else { return L10n.text("当前安装使用主屏幕通知。") }
    guard let session = nativeSession else { return L10n.text("请先完成服务登录。") }
    do {
      let data = try await nativeRequest(session: session, action: "status")
      guard case .string(let resolvedOwner) = data["owner"], !resolvedOwner.isEmpty else {
        return L10n.text("通知服务未返回账号身份，请更新 MoviePilot 后端后重试。")
      }
      identified(resolvedOwner)
      guard let key = preferenceKey else { return L10n.text("登录状态已改变，请重新打开通知设置。") }
      guard
        try await UNUserNotificationCenter.current().requestAuthorization(options: [
          .alert, .sound, .badge,
        ])
      else {
        return L10n.text("系统通知未开启，可前往设置允许通知。")
      }
      guard self.nativeSession === session, preferenceKey == key else {
        return L10n.text("登录状态已改变，请重新打开通知设置。")
      }
      UserDefaults.standard.set(true, forKey: key)
      registrationError = nil
      UIApplication.shared.registerForRemoteNotifications()
      return L10n.text("已向系统申请推送令牌，稍后刷新查看绑定状态。")
    } catch let error as NotificationFailure {
      return error.localizedDescription
    } catch { return L10n.text("无法开启系统通知，请检查通知服务与系统设置。") }
  }

  /// Apple 令牌可能随重装或恢复改变，每次回调都覆盖当前安装绑定。
  func registered(_ data: Data) {
    token = data.map { String(format: "%02x", $0) }.joined()
    registrationError = nil
    Task { [weak self] in await self?.bindToken() }
  }

  /// 签名缺少能力或系统注册失败时展示可恢复原因，不宣称收到原生推送。
  func failedRegistration() {
    registrationError = L10n.text("系统未能注册 APNs。请检查签名能力，或使用主屏幕通知。")
  }

  /// 关闭只撤销当前实例账号的本机安装绑定，不影响其他设备。
  func disable() {
    if let key = preferenceKey { UserDefaults.standard.removeObject(forKey: key) }
    UIApplication.shared.unregisterForRemoteNotifications()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    pending = nil
  }

  /// 通知点击可先于认证到达；只在内存中短暂等待，过期后不重放，并对同一通知请求 ID 去重。
  func receive(_ intent: NotificationIntent, notificationID: String? = nil) {
    if let notificationID, !notificationID.isEmpty {
      guard lastHandledNotificationID != notificationID else { return }
      lastHandledNotificationID = notificationID
    }
    pending = (intent, Date())
    consumePending()
  }

  /// 前台恢复后再次检查尚未消费的点击，仍遵守五分钟有效期。
  func resumePending() { consumePending() }

  /// 前台展示也必须匹配当前账号，旧实例的通知不显示在当前会话上。
  private func accepts(_ intent: NotificationIntent) -> Bool {
    guard let nativeSession, let owner else { return false }
    return intent.matches(address: nativeSession.instance.address, owner: owner)
  }

  /// 已认证后只提交一次导航意图；账号不匹配只提示，不自动切换实例。
  private func consumePending() {
    guard let (intent, created) = pending, let nativeSession else { return }
    guard Date().timeIntervalSince(created) < 300 else {
      pending = nil
      return
    }
    guard let owner else {
      if identityProbe == nil { attachNative(nativeSession) }
      return
    }
    guard intent.matches(address: nativeSession.instance.address, owner: owner) else {
      pending = nil
      NativeSystemRouteHub.shared.postBanner(L10n.text("这条通知属于其他实例或账号，请切换后查看通知中心。"))
      return
    }
    if NativeSystemRouteHub.shared.open(route: intent.route) {
      pending = nil
    }
  }

  /// 配置偏好绑定完整实例入口与不可变账号身份，账号改名不影响绑定。
  private var preferenceKey: String? {
    guard let nativeSession, let owner else { return nil }
    return "moviepilot.notification.enabled.\(nativeSession.instance.id).\(owner)"
  }

  /// 只有用户启用过且构建声明 APNs 时才向 Apple 注册。
  private var enabled: Bool {
    guard environment != nil, let key = preferenceKey else { return false }
    return UserDefaults.standard.bool(forKey: key)
  }

  /// 令牌注册直连后端接口；失败留在设置页供用户显式重试。
  private func bindToken() async {
    guard enabled, let token, let nativeSession, let environment else { return }
    let extra = [
      "token": token,
      "topic": Bundle.main.bundleIdentifier ?? "",
      "environment": environment,
    ]
    do {
      _ = try await nativeRequest(session: nativeSession, action: "register", extra: extra)
    } catch {
      registrationError = L10n.text("通知令牌尚未绑定，请检查后台渠道并重新开启。")
    }
  }

  /// 在系统回调线程解析不可变载荷，跨执行器只传递经过验证的值。
  nonisolated static func intent(from info: [AnyHashable: Any]) -> NotificationIntent? {
    guard let data = info["moviepilot"] as? [String: String],
      let origin = data["origin"], let route = data["route"], let owner = data["owner"]
    else { return nil }
    return NotificationIntent(origin: origin, route: route, owner: owner)
  }

  /// 使用显式完成回调，身份校验与系统完成通知均在主线程执行。
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    let intent = Self.intent(from: notification.request.content.userInfo)
    Task { @MainActor [weak self] in
      let accepted = intent.map { self?.accepts($0) == true } ?? false
      completionHandler(accepted ? [.banner, .list, .sound] : [])
    }
  }

  /// UIKit 的通知完成回调会更新状态恢复，必须留在主线程，不能使用非隔离 async 桥接。
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping @Sendable () -> Void
  ) {
    let isDefaultTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
    let requestID = response.notification.request.identifier
    let intent =
      isDefaultTap ? Self.intent(from: response.notification.request.content.userInfo) : nil
    Task { @MainActor [weak self] in
      defer { completionHandler() }
      if let intent { self?.receive(intent, notificationID: requestID) }
    }
  }
}
