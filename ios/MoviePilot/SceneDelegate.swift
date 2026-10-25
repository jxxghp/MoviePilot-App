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

  /// 创建窗口后恢复实例；没有配置时直接显示可操作的连接页。
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    self.window = window
    if let instance = instances.selected { connect(instance) } else { showConnection() }
    window.makeKeyAndVisible()
    if let response = connectionOptions.notificationResponse,
      let intent = NotificationService.intent(from: response.notification.request.content.userInfo)
    {
      NotificationService.shared.receive(intent)
    }
    openIncomingURLs(connectionOptions.urlContexts)
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
  }

  /// 系统中断期间暂停本地协商超时，避免把后台暂停当成断链。
  func sceneWillResignActive(_ scene: UIScene) { coordinator?.setLifecycle("inactive") }

  /// 后台生命周期只通知现有网页，不承诺持续执行网页任务。
  func sceneDidEnterBackground(_ scene: UIScene) { coordinator?.setLifecycle("background") }

  /// 断开旧会话后显示实例配置，旧脚本 handler 不得继续接收命令。
  private func showConnection() {
    widgetLinkTask?.cancel()
    widgetLinkTask = nil
    WidgetService.shared.cancelOpen()
    coordinator?.stop()
    coordinator = nil
    let controller = ConnectionController(instances: instances) { [weak self] instance in
      // 显式重新连接恢复原生登录入口；特殊认证仍可由用户再次选择网页方式。
      UserDefaults.standard.removeObject(forKey: "moviepilot.web-login.\(instance.id)")
      self?.connect(instance)
    }
    window?.rootViewController = AccountAppearance.navigationController(
      root: controller, instance: (instances.selected ?? instances.instances.last)?.id)
  }

  /// 恢复有效网页会话；旧网页登录选择不能让失效会话永久绕过原生登录。
  private func connect(_ instance: SavedInstance) {
    coordinator?.stop()
    coordinator = nil
    guard instance.address.webCompatibilityError == nil else {
      showConnection()
      return
    }
    if UserDefaults.standard.bool(forKey: "moviepilot.web-login.\(instance.id)") {
      openWeb(instance, authentication: nil)
      return
    }
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
      onAuthenticated: { [weak self] result, remember in
        guard let self else { return }
        UserDefaults.standard.removeObject(forKey: "moviepilot.web-login.\(instance.id)")
        var storageFailed = false
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
            title: "已登录", message: "此设备未能安全保存登录状态，下次打开需要重新登录。", preferredStyle: .alert)
          alert.addAction(UIAlertAction(title: "好", style: .default))
          self.window?.rootViewController?.present(alert, animated: true)
        }
      },
      onWebLogin: { [weak self] in
        self?.tokens.remove(instance.id)
        UserDefaults.standard.set(true, forKey: "moviepilot.web-login.\(instance.id)")
        self?.openWeb(instance, authentication: nil, allowsWebLogin: true)
      },
      onConnection: { [weak self] in self?.showConnection() })
    window?.rootViewController = AccountAppearance.navigationController(
      root: login, instance: instance.id)
  }

  /// 仅当前明确选择的网页尝试保留 HTML 登录；恢复到登录路由时重新交给原生表单。
  private func openWeb(
    _ instance: SavedInstance, authentication: AuthenticationResult?, allowsWebLogin: Bool = false
  ) {
    coordinator?.stop()
    let coordinator = WebCoordinator(
      instance: instance, authentication: authentication,
      onAuthenticationRequired: allowsWebLogin
        ? nil
        : { [weak self] in
          self?.tokens.remove(instance.id)
          self?.showLogin(instance)
        })
    let shell = ShellController(
      coordinator: coordinator,
      onNativeLogin: allowsWebLogin
        ? { [weak self] in
          UserDefaults.standard.removeObject(forKey: "moviepilot.web-login.\(instance.id)")
          self?.showLogin(instance)
        } : nil,
      onConnection: { [weak self] in self?.showConnection() })
    coordinator.shell = shell
    self.coordinator = coordinator
    NotificationService.shared.attach(coordinator)
    window?.rootViewController = shell
    coordinator.start()
  }
}
