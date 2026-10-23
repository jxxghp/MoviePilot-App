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
    openNotificationURLs(connectionOptions.urlContexts)
  }

  /// 主屏幕通知网页的显式链接与系统通知使用相同账号和实例校验。
  func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
    openNotificationURLs(urlContexts)
  }

  /// 仅识别声明的通知 scheme，冷启动时保留导航意图直到登录完成。
  private func openNotificationURLs(_ contexts: Set<UIOpenURLContext>) {
    for context in contexts {
      if let intent = NotificationIntent(url: context.url) {
        NotificationService.shared.receive(intent)
      }
    }
  }

  /// 恢复可交互状态后重新同步网页状态，不重放业务动作。
  func sceneDidBecomeActive(_ scene: UIScene) { coordinator?.setLifecycle("active") }

  /// 系统中断期间暂停本地协商超时，避免把后台暂停当成断链。
  func sceneWillResignActive(_ scene: UIScene) { coordinator?.setLifecycle("inactive") }

  /// 后台生命周期只通知现有网页，不承诺持续执行网页任务。
  func sceneDidEnterBackground(_ scene: UIScene) { coordinator?.setLifecycle("background") }

  /// 断开旧会话后显示实例配置，旧脚本 handler 不得继续接收命令。
  private func showConnection() {
    coordinator?.stop()
    coordinator = nil
    let controller = ConnectionController(instances: instances) { [weak self] instance in
      // 显式重新连接恢复原生登录入口；特殊认证仍可由用户再次选择网页方式。
      UserDefaults.standard.removeObject(forKey: "moviepilot.web-login.\(instance.id)")
      self?.connect(instance)
    }
    window?.rootViewController = UINavigationController(rootViewController: controller)
  }

  /// 已选择的实例先进入原生登录；用户明确选择的特殊网页登录方式单独保留。
  private func connect(_ instance: SavedInstance) {
    coordinator?.stop()
    coordinator = nil
    if UserDefaults.standard.bool(forKey: "moviepilot.web-login.\(instance.id)") {
      openWeb(instance, authentication: nil, nativeAuthentication: false)
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
      onExpired: { [weak self] in self?.tokens.remove(instance.id) },
      onAuthenticated: { [weak self] result, remember in
        guard let self else { return }
        var storageFailed = false
        if remember {
          do { try self.tokens.save(result.session.accessToken, for: instance.id) } catch {
            storageFailed = true
            self.tokens.remove(instance.id)
          }
        } else {
          self.tokens.remove(instance.id)
        }
        self.openWeb(instance, authentication: result, nativeAuthentication: true)
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
        self?.openWeb(instance, authentication: nil, nativeAuthentication: false)
      },
      onConnection: { [weak self] in self?.showConnection() })
    window?.rootViewController = UINavigationController(rootViewController: login)
  }

  /// 认证结果仅注入精确实例的首次主文档，全部业务与导航仍在唯一 WebView 中运行。
  private func openWeb(
    _ instance: SavedInstance, authentication: AuthenticationResult?, nativeAuthentication: Bool
  ) {
    coordinator?.stop()
    let coordinator = WebCoordinator(
      instance: instance, authentication: authentication,
      onAuthenticationRequired: nativeAuthentication
        ? { [weak self] in
          self?.tokens.remove(instance.id)
          self?.showLogin(instance)
        } : nil)
    let shell = ShellController(coordinator: coordinator) { [weak self] in self?.showConnection() }
    coordinator.shell = shell
    self.coordinator = coordinator
    NotificationService.shared.attach(coordinator)
    window?.rootViewController = shell
    coordinator.start()
  }
}
