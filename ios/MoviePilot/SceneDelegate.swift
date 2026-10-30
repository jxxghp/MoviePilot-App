import MoviePilotCore
import UIKit
import WebKit

/// 持有窗口、当前单 WebView 会话与实例切换，避免旧容器残留在新实例下。
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private let instances = InstanceStore()
  private let tokens = TokenStore()
  private var coordinator: WebCoordinator?
  private var widgetLinkTask: Task<Void, Never>?
  private var homeShortcut = PendingHomeShortcut()

  /// 创建窗口后恢复实例；没有配置时直接显示可操作的连接页。
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    self.window = window
    if let item = connectionOptions.shortcutItem { _ = receiveHomeShortcut(item) }
    if let instance = instances.selected { connect(instance) } else { showConnection() }
    window.makeKeyAndVisible()
    if let response = connectionOptions.notificationResponse,
      let intent = NotificationService.intent(from: response.notification.request.content.userInfo)
    {
      NotificationService.shared.receive(intent)
    }
    openIncomingURLs(connectionOptions.urlContexts)
  }

  /// 运行中的图标快捷项与冷启动共用白名单和待处理意图，不跳过当前认证。
  func windowScene(
    _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(receiveHomeShortcut(shortcutItem))
  }

  /// 系统载荷只决定固定入口，实例来自用户当前选择，未知类型不能替换旧意图。
  private func receiveHomeShortcut(_ item: UIApplicationShortcutItem) -> Bool {
    guard let value = HomeShortcut(type: item.type) else { return false }
    homeShortcut.receive(value, instanceID: instances.selected?.id.uuidString)
    resumeHomeShortcut()
    return true
  }

  /// 当前原生导航及面板已经可用才消费，成功一次后立即清空内存意图。
  private func resumeHomeShortcut() {
    guard let coordinator,
      let shortcut = homeShortcut.resolve(for: coordinator.instance.id.uuidString),
      coordinator.openHomeShortcut(shortcut)
    else { return }
    homeShortcut.clear()
  }

  /// 主屏幕通知网页的显式链接与系统通知使用相同账号和实例校验。
  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    openIncomingURLs(urlContexts)
  }

  /// 仅识别通知与本机小组件白名单，外部 URL 不能选择服务器、凭据或任意网页路由。
  private func openIncomingURLs(_ contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      if let link = WidgetLink(url: context.url), WidgetFeature.isEnabled {
        openWidget(link)
      } else if let intent = NotificationIntent(url: context.url) {
        NotificationService.shared.receive(intent)
      }
    }
  }

  /// 冷热启动都先找到资料原来的 SavedInstance，再用该实例既有登录流程恢复身份。
  private func openWidget(_ link: WidgetLink) {
    widgetLinkTask?.cancel()
    widgetLinkTask = Task { [weak self] in
      guard let self else { return }
      do {
        let profile = try await WidgetService.shared.receive(link)
        try Task.checkCancellation()
        guard
          let instance = self.instances.instances.first(where: {
            $0.id == profile.instanceId && $0.address == profile.address
          })
        else { throw WidgetBridgeError.invalidRequest }
        if self.coordinator?.instance.id != instance.id {
          _ = try self.instances.select(instance.address)
          self.connect(instance)
        }
        if let coordinator = self.coordinator {
          WidgetService.shared.resumePending(with: coordinator)
        }
      } catch {
        guard !Task.isCancelled else { return }
        WidgetService.shared.cancelOpen()
        let alert = UIAlertController(
          title: "小组件资料不可用", message: "请在对应服务登录后，重新启用小组件资料。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        self.window?.rootViewController?.present(alert, animated: true)
      }
    }
  }

  /// 恢复可交互状态后重新同步网页状态，不重放业务动作。
  func sceneDidBecomeActive(_ scene: UIScene) {
    coordinator?.setLifecycle("active")
    if let coordinator { WidgetService.shared.resumePending(with: coordinator) }
    resumeHomeShortcut()
  }

  /// 系统中断期间暂停本地协商超时，避免把后台暂停当成断链。
  func sceneWillResignActive(_ scene: UIScene) { coordinator?.setLifecycle("inactive") }

  /// 后台生命周期只通知现有网页，不承诺持续执行网页任务。
  func sceneDidEnterBackground(_ scene: UIScene) { coordinator?.setLifecycle("background") }

  /// 断开旧会话后显示实例配置，旧脚本 handler 不得继续接收命令。
  private func showConnection() {
    if instances.selected != nil { homeShortcut.clear() }
    widgetLinkTask?.cancel()
    widgetLinkTask = nil
    WidgetService.shared.cancelOpen()
    coordinator?.stop()
    coordinator = nil
    let controller = ConnectionController(instances: instances) { [weak self] instance in
      // 清除旧版本的网页偏好，重新连接始终走原生认证。
      UserDefaults.standard.removeObject(forKey: "moviepilot.web-login.\(instance.id)")
      self?.connect(instance)
    }
    window?.rootViewController = AccountAppearance.navigationController(
      root: controller, instance: (instances.selected ?? instances.instances.last)?.id)
  }

  /// 旧版本网页偏好不再参与连接；每次恢复都先由原生认证校验当前实例令牌。
  private func connect(_ instance: SavedInstance) {
    coordinator?.stop()
    coordinator = nil
    guard instance.address.webCompatibilityError == nil else {
      showConnection()
      return
    }
    UserDefaults.standard.removeObject(forKey: "moviepilot.web-login.\(instance.id)")
    showLogin(instance)
  }

  /// 登录与令牌恢复只有当前实例的控制器能提交，换实例立即撤销旧网络。
  private func showLogin(_ instance: SavedInstance) {
    coordinator?.stop()
    coordinator = nil
    let login = LoginController(
      instance: instance, savedToken: tokens.read(instance.id),
      onExpired: { [weak self] in
        self?.tokens.remove(instance.id)
        WidgetService.shared.endSession(instanceId: instance.id, clear: true)
      },
      onAuthenticated: { [weak self] result, remember, credentialsFailed in
        guard let self else { return }
        UserDefaults.standard.removeObject(forKey: "moviepilot.web-login.\(instance.id)")
        var storageFailed = credentialsFailed
        if remember {
          do { try self.tokens.save(result.session.accessToken, for: instance.id) } catch {
            storageFailed = true
            self.tokens.remove(instance.id)
          }
        } else {
          self.tokens.remove(instance.id)
        }
        self.openWeb(instance, authentication: result)
        if storageFailed {
          let alert = UIAlertController(
            title: "已登录", message: "此设备未能安全保存部分登录信息，下次可能需要重新输入。", preferredStyle: .alert)
          alert.addAction(UIAlertAction(title: "好", style: .default))
          self.window?.rootViewController?.present(alert, animated: true)
        }
      },
      onConnection: { [weak self] in self?.showConnection() })
    window?.rootViewController = AccountAppearance.navigationController(
      root: login, instance: instance.id)
  }

  /// 业务网页只在原生认证后创建；运行中失效通知始终撤销令牌并回到原生登录。
  private func openWeb(
    _ instance: SavedInstance, authentication: AuthenticationResult
  ) {
    coordinator?.stop()
    let coordinator = WebCoordinator(
      instance: instance, authentication: authentication,
      onAuthenticationRequired: { [weak self] in
        self?.tokens.remove(instance.id)
        self?.showLogin(instance)
      })
    let shell = ShellController(
      coordinator: coordinator,
      onConnection: { [weak self] in self?.showConnection() })
    coordinator.shell = shell
    coordinator.onNavigationReady = { [weak self, weak coordinator] in
      guard let self, self.coordinator === coordinator else { return }
      self.resumeHomeShortcut()
    }
    self.coordinator = coordinator
    NotificationService.shared.attach(coordinator)
    window?.rootViewController = shell
    coordinator.start()
  }
}
