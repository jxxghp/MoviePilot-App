import Combine
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import Security
import UIKit

/// 原生入口的非身份表单状态；账号和权限始终来自 NativeSessionManager。
@MainActor
final class NativeAppModel: ObservableObject {
  /// 网络失败仍保留当前表单，不能把初始化错误变成普通登录。
  enum Form: Equatable { case connection, login, initialization }

  let manager: NativeSessionManager
  @Published private(set) var saved: [SavedInstance] = []
  @Published private(set) var selected: SavedInstance?
  @Published private(set) var form: Form = .connection
  @Published private(set) var busy = false
  @Published private(set) var messageKey: String?
  @Published private(set) var fixedUsername = false
  @Published private(set) var language = AppLanguage.current
  @Published var address = ""
  @Published var username = ""
  @Published var password = ""
  @Published var otp = ""
  @Published var confirmation = ""
  @Published var apiKey = ""
  @Published var rememberSession = true
  @Published var rememberCredentials = false
  @Published var needsOTP = false
  private let instances: InstanceStore
  private let credentials = LoginCredentialStore()
  private var task: Task<Void, Never>?
  private var operationID = UUID()
  private var lastSessionValidationAt: Date = .distantPast

  /// 依赖仍是既有地址簿/Keychain；原生模式不创建独立迁移副本。
  init() {
    let instances = InstanceStore()
    self.instances = instances
    selected = instances.selected
    saved = instances.instances
    manager = NativeSessionManager(tokens: TokenStore())
  }

  /// 冷启动只尝试恢复上次实例令牌，绝不自动提交可选的已保存密码，同时保留冷启动携带的系统深链与快捷项意图。
  func start() {
    if let selected { connect(selected, preserveSystemLaunchIntent: true) }
  }

  /// 地址校验失败保留原输入，成功则沿用相同标准地址的 UUID。
  func connectAddress() {
    do {
      let instance = try instances.select(ServerAddress(address))
      connect(instance)
    } catch {
      messageKey = "请输入包含 http:// 或 https:// 的完整服务地址。"
    }
  }

  /// 新实例先取消旧尝试和草稿，只有本次返回可以更新界面与回填凭据；冷启动/小组件发起的连接保留系统跳转意图。
  func connect(_ instance: SavedInstance, preserveSystemLaunchIntent: Bool = false) {
    resetSessionState(clearSystemIntents: !preserveSystemLaunchIntent)
    do {
      selected = try instances.select(instance.address)
      saved = instances.instances
      LanguagePreferences(defaults: .standard).activate(instance.id)
      language = .current
      LanguageSettings.refreshShortcuts()
      address = instance.address.url.absoluteString
      form = .login
      execute { [self] id in
        _ = try await manager.connect(instance.nativeInstance)
        try check(id)
        switch manager.state {
        case .initializationRequired(_, let configured):
          form = .initialization
          username = configured ?? ""
          fixedUsername = configured != nil
          regenerateKey()
        case .loginRequired:
          loadCredentials(instance)
        default: break
        }
      }
    } catch { messageKey = Self.errorKey(error) }
  }

  /// 退出连接页不注销已保存令牌；旧网络、通知绑定、快捷项与临时 Widget 代次必须先停止。
  func changeServer() {
    resetSessionState(clearSystemIntents: true)
  }

  /// 清理旧实例网络任务与界面草稿；独立本地文件与外部直链播放不随服务会话重置而中断。
  private func resetSessionState(clearSystemIntents: Bool) {
    operationID = UUID()
    task?.cancel()
    task = nil
    busy = false
    if let selected { WidgetService.shared.endSession(instanceId: selected.id, clear: false) }
    if clearSystemIntents {
      WidgetService.shared.cancelOpen()
      NativeSystemRouteHub.shared.clearPending()
    }
    manager.disconnect()
    NativeMediaPlaybackLauncher.shared.dismissSessionBoundPlayer(animated: false)
    NotificationService.shared.attachNative(nil)
    clearSecrets()
    username = ""
    rememberSession = true
    rememberCredentials = false
    needsOTP = false
    fixedUsername = false
    messageKey = nil
    form = .connection
    saved = instances.instances
  }

  /// 一次明确登录只提交一次；保存密码失败可见，但不撤销已成功确认的内存身份。
  func login() {
    guard let selected else { return }
    let input = LoginCredentials(username: username, password: password)
    let code = otp
    let savePassword = rememberCredentials
    let keepSession = rememberSession
    execute { [self] id in
      _ = try await manager.login(
        to: selected.nativeInstance, username: input.username, password: input.password,
        otp: code.isEmpty ? nil : code, remember: keepSession)
      try check(id)
      do {
        if savePassword {
          try credentials.save(input, for: selected.id, address: selected.address)
        } else {
          try credentials.remove(for: selected.id)
        }
      } catch { messageKey = "此设备未能安全保存部分登录信息，下次可能需要重新输入。" }
      clearSecrets()
    }
  }

  /// 初始化提交不自动登录，不把生成的 API Key 持久化到设备或剪贴板。
  func initialize() {
    guard let selected else { return }
    let name = username
    let secret = password
    let confirmed = confirmation
    let key = apiKey
    guard secret == confirmed else {
      messageKey = "两次输入的密码不一致。"
      return
    }
    execute { [self] id in
      let result = try await manager.initialize(
        selected.nativeInstance, username: name, password: secret,
        confirmation: confirmed, apiKey: key)
      try check(id)
      clearSecrets()
      form = .login
      fixedUsername = false
      messageKey = result == .created ? "管理员已创建，请登录。" : "服务已初始化，请登录。"
    }
  }

  /// 关闭密码记忆立即删除本实例记录，系统拒绝时回滚开关并明确提示。
  func setRememberCredentials(_ enabled: Bool) {
    guard !enabled, let selected else {
      rememberCredentials = enabled
      return
    }
    do {
      try credentials.remove(for: selected.id)
      rememberCredentials = false
    } catch { messageKey = Self.errorKey(LoginCredentialError.unavailable) }
  }

  /// 注销只影响当前实例；不能顺带删除其它服务账号或全局通知偏好。
  func logout() {
    guard let selected else { return }
    do {
      try manager.logout()
      NativeMediaPlaybackLauncher.shared.dismissSessionBoundPlayer(animated: false)
      WidgetService.shared.endSession(instanceId: selected.id, clear: true)
      WidgetService.shared.cancelOpen()
      NativeSystemRouteHub.shared.clearPending()
      NotificationService.shared.attachNative(nil)
      clearSecrets()
      form = .login
      loadCredentials(selected)
    } catch { messageKey = Self.errorKey(error) }
  }

  /// 当前账号刷新通过真实 user/current，权限更新和过期仍由会话所有者处理。
  func refreshIdentity() {
    execute { [self] _ in _ = try await manager.requireSession().refreshUser() }
  }

  /// 观察状态变迁：已认证时挂载原生系统集成；过期时立即清理本实例集成资料。
  func received(_ state: NativeSessionState) {
    if case .authenticated = state, let session = manager.currentSession {
      NotificationService.shared.attachNative(session)
      WidgetService.shared.reconcile(native: session)
      NativeSystemRouteHub.shared.resolvePending(for: session.instance.id.uuidString)
      return
    }
    if case .loginRequired(_, .expired) = state, let selected {
      NativeMediaPlaybackLauncher.shared.dismissSessionBoundPlayer(animated: false)
      NativePageDataCache.shared.clearAll()
      NativeMediaArtworkCache.shared.clearMemory()
      Self.dismissPresentedModals()
      WidgetService.shared.endSession(instanceId: selected.id, clear: true)
      WidgetService.shared.cancelOpen()
      NativeSystemRouteHub.shared.clearPending()
      NotificationService.shared.attachNative(nil)
      clearSecrets()
      form = .login
      loadCredentials(selected)
      messageKey = "登录已过期，请重新登录。"
    }
    if case .verificationRequired(_, let methods) = state {
      needsOTP = methods.contains("otp")
      if !needsOTP { messageKey = "此账号需要尚未接入的验证方式。" }
    }
  }

  /// 回到前台或深链/快捷项触发时，先校验令牌有效性（超时自动退出登录），再恢复未消费的系统集成。
  func resumeSystemIntegrations() {
    guard let session = manager.currentSession else { return }
    if session.isTokenExpired() {
      Task { _ = try? await session.refreshUser() }
      return
    }
    let now = Date()
    if now.timeIntervalSince(lastSessionValidationAt) > 30 {
      lastSessionValidationAt = now
      Task { [weak self] in
        guard let self, let active = self.manager.currentSession,
          active.scope == session.scope
        else { return }
        _ = try? await active.refreshUser()
      }
    }
    NotificationService.shared.resumePending()
    WidgetService.shared.resumePending(native: session)
    NativeSystemRouteHub.shared.resolvePending(for: session.instance.id.uuidString)
  }

  /// 会话过期自动退出时收起可能仍盖在顶层的会话关联播放器或 UIKit 弹窗，保留独立本地/外部媒体播放。
  private static func dismissPresentedModals() {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where window.isKeyWindow {
        if let presented = window.rootViewController?.presentedViewController {
          if let player = presented as? MediaPlaybackViewController, !player.isSessionBound {
            continue
          }
          window.rootViewController?.dismiss(animated: false)
        }
      }
    }
  }

  /// 解析桌面小组件深链：从本机共享仓查找资料并定位到对应已保存实例，绝不跨账号自动登录。
  func openWidgetLink(_ link: WidgetLink) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let profile = try await WidgetService.shared.receive(link)
        if let active = manager.currentSession, active.instance.id == profile.instanceId,
          active.instance.address == profile.address
        {
          WidgetService.shared.resumePending(native: active)
          return
        }
        guard
          let savedTarget = instances.instances.first(where: {
            $0.id == profile.instanceId && $0.address == profile.address
          })
        else {
          WidgetService.shared.cancelOpen()
          NativeSystemRouteHub.shared.postBanner(L10n.text("无法打开此小组件，请检查当前账号权限或重新启用资料。"))
          if manager.currentSession == nil { start() }
          return
        }
        connect(savedTarget, preserveSystemLaunchIntent: true)
      } catch {
        NativeSystemRouteHub.shared.postBanner(L10n.text("无法打开此小组件，请检查当前账号权限或重新启用资料。"))
        if manager.currentSession == nil { start() }
      }
    }
  }

  /// 只在确认删除后执行；先清理旧网页存储与小组件授权，再交由既有地址簿清理安全记录。
  func forget(_ instance: SavedInstance) {
    execute { [self] id in
      WidgetService.shared.endSession(instanceId: instance.id, clear: true)
      await LegacyWebsiteStorage.erase(for: instance.id)
      try check(id)
      try instances.forget(instance)
      saved = instances.instances
      if selected?.id == instance.id { selected = nil }
    }
  }

  /// 语言更新立即作用于本机文案、活跃会话 `X-MoviePilot-Locale` 请求头并清空陈旧语言快照缓存。
  func selectLanguage(_ value: AppLanguage) {
    LanguagePreferences(defaults: .standard).select(value, instanceID: selected?.id)
    language = value
    manager.currentSession?.updateLanguage(value)
    NativePageDataCache.shared.clearAll()
    NativeMediaLibraryStatusStore.shared.clearAll()
    LanguageSettings.refreshShortcuts()
  }

  /// 生成 32 字节随机值对应的十六进制 API Key，不使用弱随机数或固定示例。
  func regenerateKey() {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      apiKey = ""
      messageKey = "无法生成安全密钥，请重试。"
      return
    }
    apiKey = bytes.map { String(format: "%02x", $0) }.joined()
  }

  /// 后台取消未完成的认证，保留活跃会话；密码、确认值、OTP 与 API Key 全部清空。
  func enteredBackground() {
    if busy {
      operationID = UUID()
      task?.cancel()
      task = nil
      if manager.currentSession == nil { manager.disconnect() }
      busy = false
    }
    clearSecrets()
  }

  /// 已保存的密码仅回填当前地址，不隐式开启另一个实例的记忆或提交认证。
  private func loadCredentials(_ instance: SavedInstance) {
    do {
      if let value = try credentials.read(for: instance.id, address: instance.address) {
        username = value.username
        password = value.password
        rememberCredentials = true
      }
    } catch { messageKey = Self.errorKey(LoginCredentialError.unavailable) }
  }

  /// 撤销可编辑的明文副本；已选择记住的记录仍由系统 Keychain 独立保护。
  private func clearSecrets() {
    password = ""
    otp = ""
    confirmation = ""
    apiKey = ""
  }

  /// 一个操作独占忙碌状态；迟到错误不能覆盖新实例表单或显示旧账号信息。
  private func execute(_ operation: @escaping @MainActor (UUID) async throws -> Void) {
    task?.cancel()
    let id = UUID()
    operationID = id
    messageKey = nil
    busy = true
    task = Task { [weak self] in
      guard let self else { return }
      do { try await operation(id) } catch {
        guard operationID == id, !Task.isCancelled else { return }
        messageKey = Self.errorKey(error)
      }
      guard operationID == id else { return }
      busy = false
      task = nil
    }
  }

  /// 存储、草稿回填等非会话副作用也必须属于当前操作，不能只依赖网络取消。
  private func check(_ id: UUID) throws {
    try Task.checkCancellation()
    guard operationID == id else { throw CancellationError() }
  }

  /// 仅展示固定安全分类，不把服务端正文、URL 查询或密码带进错误标签。
  private static func errorKey(_ error: any Error) -> String {
    let key: String
    switch error {
    case NativeAuthenticationError.credentials: key = "用户名、密码或验证码不正确。"
    case NativeAuthenticationError.verificationRequired: key = "请输入身份验证器验证码。"
    case NativeAuthenticationError.invalidInput: key = "请检查用户名、密码和 API Key。"
    case NativeAuthenticationError.inactiveAccount: key = "账号未启用，请联系管理员。"
    case NativeSessionFailure.storageUnavailable, is LoginCredentialError:
      key = "无法访问安全存储，请解锁设备后重试。"
    case APIError.unauthorized: key = "登录已过期，请重新登录。"
    case APIError.forbidden: key = "当前账号没有此操作权限。"
    case APIError.rateLimited: key = "请求过于频繁，请稍后再试。"
    case APIError.httpStatus(409): key = "服务状态已改变，请重试以重新检查。"
    case APIError.redirectRefused: key = "服务返回了重定向，请检查完整服务地址。"
    case APIError.invalidResponse, APIError.responseTooLarge:
      key = "服务响应无法解析，请检查后端版本和地址。"
    case APIError.timedOut: key = "连接超时，请重试或更改地址。"
    default: key = "无法连接服务，请重试或更改地址。"
    }
    return key
  }
}
