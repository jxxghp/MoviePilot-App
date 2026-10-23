import MoviePilotCore
import UIKit
import WebKit

/// 系统顶部和底部导航的呈现层，所有路由与业务动作只发送网页意图。
@MainActor
final class ShellController: UIViewController {
  private let coordinator: WebCoordinator
  private let onConnection: () -> Void
  private let compatibilityHost = ContentHostController(rootId: nil)
  private lazy var compatibilityNavigation = UINavigationController(
    rootViewController: compatibilityHost)
  private var rootNavigations: [UINavigationController] = []
  private var hosts: [ContentHostController] = []
  private var rootIds: [String] = []
  private var activeContainer: UIViewController?
  private var latest: NavigationSnapshot?
  private var recoveryView: UIView?
  private var startupView: StartupView?
  private var nativeVisible = false
  private let moreMenu = MoreMenuController()
  private let bottomNavigation = BottomNavigationView()
  private var topActionsExpanded = false

  /// 容器保存协调器；协调器以弱引用回调 UI，避免脚本与视图形成环。
  init(coordinator: WebCoordinator, onConnection: @escaping () -> Void) {
    self.coordinator = coordinator
    self.onConnection = onConnection
    super.init(nibName: nil, bundle: nil)
    moreMenu.onSelect = { [weak self] item in self?.coordinator.openMenuItem(item) }
  }

  /// 本地会话按实例重建，不支持 storyboard 初始化。
  required init?(coder: NSCoder) { fatalError("Use init(coordinator:onConnection:)") }

  /// 启动画面固定使用深色背景，交接后恢复页面主题对应的系统状态栏颜色。
  override var preferredStatusBarStyle: UIStatusBarStyle {
    startupView == nil ? .default : .lightContent
  }

  /// 首次进入延续静态启动画面，唯一 WebView 在覆盖层后完成加载和布局。
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    showWebNavigation()
    setLoading(true)
  }

  /// 系统安全区改变后刷新当前布局，不修改业务路由。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    coordinator.layoutChanged()
  }

  /// 将网页默认模式放在独立导航容器内，避免隐藏 Tab 留下不可见占位。
  func showWebNavigation() {
    loadViewIfNeeded()
    nativeVisible = false
    bottomNavigation.isHidden = true
    compatibilityHost.additionalSafeAreaInsets.bottom = 0
    removeMoreMenu()
    coordinator.content.view.isHidden = false
    latest = nil
    recoveryView?.removeFromSuperview()
    recoveryView = nil
    compatibilityHost.edgesForExtendedLayout = []
    compatibilityHost.title = "MoviePilot"
    compatibilityHost.navigationItem.leftBarButtonItems = nil
    compatibilityHost.navigationItem.rightBarButtonItems = [connectionItem()]
    compatibilityHost.navigationItem.titleView = nil
    compatibilityHost.navigationItem.searchController = nil
    compatibilityHost.attach(coordinator.content)
    install(compatibilityNavigation)
  }

  /// 在网页尚未隐藏导航时准备系统栏并量测，待确认后才显示。
  func prepare(_ snapshot: NavigationSnapshot) {
    latest = snapshot
    configureTabs(snapshot)
    if let target = nativeContainer {
      if target.parent == nil { add(target) }
      if target !== activeContainer {
        target.view.alpha = 0
        target.view.isUserInteractionEnabled = false
        view.bringSubviewToFront(compatibilityNavigation.view)
      }
      target.view.layoutIfNeeded()
    }
    keepStartupInFront()
  }

  /// 网页确认已消费同一布局后，转移唯一内容并提交原生控件。
  func apply(_ snapshot: NavigationSnapshot) {
    latest = snapshot
    configureTabs(snapshot)
    nativeVisible = true
    recoveryView?.removeFromSuperview()
    recoveryView = nil
    let host = selectedHost
    host.edgesForExtendedLayout = .all
    host.attach(coordinator.content)
    configureMoreMenu(host, snapshot: snapshot)
    if let container = nativeContainer {
      container.view.alpha = 1
      container.view.isUserInteractionEnabled = true
      install(container)
    }
    configureHeader(host, snapshot: snapshot)
    view.layoutIfNeeded()
    keepStartupInFront()
  }

  /// 返回当前最终宿主的 point 几何，正文和菜单锚点使用同一坐标原点。
  func layoutPayload(revision: Int, keyboard: CGRect?) -> JSONValue {
    let host = nativeVisible ? selectedHost : (latest == nil ? compatibilityHost : selectedHost)
    host.loadViewIfNeeded()
    let bounds = host.view.bounds
    let safe = host.view.safeAreaInsets
    let system = view.window?.safeAreaInsets ?? .zero
    let overlap = keyboard.map { host.view.convert($0, from: nil).intersection(bounds).height } ?? 0
    return .object([
      "layoutRevision": .number(Double(revision)),
      "viewportPoints": .object(["width": .number(bounds.width), "height": .number(bounds.height)]),
      "systemSafeArea": insets(system),
      "chromeOcclusion": insets(
        UIEdgeInsets(
          top: max(0, safe.top - system.top), left: safe.left,
          bottom: max(0, safe.bottom - system.bottom), right: safe.right)),
      "contentInsets": insets(safe),
      "keyboardOcclusion": .number(overlap.isFinite ? overlap : 0),
      "consumedByNativeFrame": .bool(false),
    ])
  }

  /// 静态启动页覆盖导航和 Web；只有协调器确认首屏资源及导航完成时才整体交接。
  func setLoading(_ loading: Bool) {
    loadViewIfNeeded()
    if loading {
      if startupView == nil {
        let startup = StartupView()
        startup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startup)
        NSLayoutConstraint.activate([
          startup.leadingAnchor.constraint(equalTo: view.leadingAnchor),
          startup.trailingAnchor.constraint(equalTo: view.trailingAnchor),
          startup.topAnchor.constraint(equalTo: view.topAnchor),
          startup.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        startupView = startup
      }
      keepStartupInFront()
    } else {
      startupView?.removeFromSuperview()
      startupView = nil
      activeContainer?.view.accessibilityElementsHidden = false
      bottomNavigation.accessibilityElementsHidden = false
      view.accessibilityElements = nil
    }
    setNeedsStatusBarAppearanceUpdate()
  }

  /// 布局量测和导航容器切换仍在覆盖层后执行，后台网页也不能被辅助功能提前访问。
  private func keepStartupInFront() {
    guard let startupView else { return }
    view.bringSubviewToFront(startupView)
    activeContainer?.view.accessibilityElementsHidden = true
    bottomNavigation.accessibilityElementsHidden = true
    view.accessibilityElements = [startupView]
  }

  /// 内容进程或连接失败时提供明确出口，绝不重放未确认的网页写操作。
  func showRecovery(message: String) {
    loadViewIfNeeded()
    setLoading(false)
    recoveryView?.removeFromSuperview()
    let panel = UIView()
    panel.backgroundColor = .systemBackground
    panel.translatesAutoresizingMaskIntoConstraints = false
    let title = UILabel()
    title.text = "暂时无法打开 MoviePilot"
    title.font = .preferredFont(forTextStyle: .title2)
    title.adjustsFontForContentSizeCategory = true
    title.numberOfLines = 0
    let detail = UILabel()
    detail.text = message
    detail.font = .preferredFont(forTextStyle: .body)
    detail.adjustsFontForContentSizeCategory = true
    detail.textColor = .secondaryLabel
    detail.numberOfLines = 0
    var config: UIButton.Configuration = .filled()
    if #available(iOS 26.0, *) { config = .prominentGlass() }
    config.title = "重新打开"
    let retry = UIButton(
      configuration: config,
      primaryAction: UIAction { [weak self] _ in self?.coordinator.reloadInWebMode() })
    var secondary = UIButton.Configuration.plain()
    secondary.title = "更改服务地址"
    let change = UIButton(
      configuration: secondary, primaryAction: UIAction { [weak self] _ in self?.onConnection() })
    let stack = UIStackView(arrangedSubviews: [title, detail, retry, change])
    stack.axis = .vertical
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(stack)
    view.addSubview(panel)
    NSLayoutConstraint.activate([
      panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      panel.topAnchor.constraint(equalTo: view.topAnchor),
      panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stack.centerYAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.centerYAnchor),
      stack.leadingAnchor.constraint(
        equalTo: panel.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(
        equalTo: panel.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
      change.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    recoveryView = panel
    UIAccessibility.post(notification: .screenChanged, argument: title)
  }

  /// 当前快照决定选中宿主，找不到入口时使用网页兼容宿主。
  private var selectedHost: ContentHostController {
    guard latest?.chrome.bottomVisible == true else { return compatibilityHost }
    if let id = latest?.route.rootId, let host = hosts.first(where: { $0.rootId == id }) {
      return host
    }
    return hosts.first ?? compatibilityHost
  }

  /// 没有业务底栏的页面使用单导航容器，避免伪造空白 Tab。
  private var nativeContainer: UIViewController? {
    if latest?.chrome.bottomVisible == true,
      let id = latest?.route.rootId,
      let index = rootIds.firstIndex(of: id), rootNavigations.indices.contains(index)
    {
      return rootNavigations[index]
    }
    if latest?.chrome.bottomVisible == true { return rootNavigations.first }
    return compatibilityNavigation
  }

  /// 权限目录改变才重建轻量导航宿主；全局底栏独立呈现，避免另一个隐藏 Tab 占位。
  private func configureTabs(_ snapshot: NavigationSnapshot) {
    let ids = snapshot.roots.map(\.id)
    if rootIds != ids || rootNavigations.isEmpty {
      hosts = snapshot.roots.map { ContentHostController(rootId: $0.id) }
      rootNavigations = hosts.map { UINavigationController(rootViewController: $0) }
      rootIds = ids
    }
    configureHeader(selectedHost, snapshot: snapshot)
    let style: UIUserInterfaceStyle =
      snapshot.chrome.theme == .dark
      ? .dark : (snapshot.chrome.theme == .light ? .light : .unspecified)
    overrideUserInterfaceStyle = style
    if let color = snapshot.chrome.accentColor,
      let value = UInt32(color.dropFirst(), radix: 16)
    {
      view.tintColor = UIColor(
        red: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255, alpha: 1)
    } else {
      view.tintColor = AccountAppearance.accent
    }
  }

  /// 顶栏只使用原生导航语义；动作仍回到网页注册的回调。
  private func configureHeader(_ host: ContentHostController, snapshot: NavigationSnapshot) {
    // UIViewController.title 会连带修改导航容器的 Tab 名称，详情标题只属于顶部栏。
    host.navigationItem.title = topActionsExpanded ? nil : snapshot.route.title
    host.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    host.navigationItem.leftBarButtonItems =
      snapshot.route.canGoBack
      ? [
        UIBarButtonItem(
          image: UIImage(systemName: "chevron.backward"),
          primaryAction: UIAction(title: "返回") { [weak self] _ in
            self?.coordinator.command(
              "navigation.back", payload: .object(["source": .string("button")]))
          })
      ] : nil
    host.navigationItem.leftBarButtonItems?.first?.accessibilityLabel = "返回"
    let trailing = snapshot.actions.filter { $0.position != .accessory }
    host.navigationItem.rightBarButtonItems = [
      connectionItem(overflow: trailing, enabled: snapshot.presentation?.overlayOpen != true)
    ]
    host.navigationItem.titleView = nil
    host.navigationItem.searchController = nil
    if let tabs = snapshot.headerTabs {
      let items = tabs.items.map { item in
        UIAction(title: item.title, state: item.id == tabs.selectedId ? .on : .off) {
          [weak self] _ in
          self?.coordinator.command(
            "headerTab.select",
            payload: .object(["tabId": .string(item.id), "ownerId": .string(tabs.ownerId)]))
        }
      }
      var config = UIButton.Configuration.plain()
      config.title = snapshot.route.title
      config.subtitle = tabs.items.first { $0.id == tabs.selectedId }?.title
      config.baseForegroundColor = .label
      config.titleAlignment = .center
      config.titleLineBreakMode = .byTruncatingTail
      config.subtitleLineBreakMode = .byTruncatingTail
      config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)
      config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var attributes = incoming
        attributes.font = .preferredFont(forTextStyle: .headline)
        return attributes
      }
      config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        incoming in
        var attributes = incoming
        attributes.font = .preferredFont(forTextStyle: .caption1)
        attributes.foregroundColor = .secondaryLabel
        return attributes
      }
      config.image = UIImage(systemName: "chevron.down")
      config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 12, weight: .semibold)
      config.imagePlacement = .trailing
      config.imagePadding = 6
      let button = UIButton(configuration: config)
      // 导航栏首次量测前提供单行标题的实际宽度，避免零尺寸 titleView 将中文逐字换行。
      button.titleLabel?.numberOfLines = 1
      button.sizeToFit()
      button.menu = UIMenu(children: items)
      button.showsMenuAsPrimaryAction = true
      button.isEnabled = snapshot.presentation?.overlayOpen != true
      button.accessibilityLabel = "\(snapshot.route.title)，页内分类"
      button.accessibilityValue = tabs.items.first { $0.id == tabs.selectedId }?.title
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
      button.heightAnchor.constraint(equalToConstant: 44).isActive = true
      button.alpha = topActionsExpanded ? 0 : 1
      button.accessibilityElementsHidden = topActionsExpanded
      host.navigationItem.titleView = button
    }
    configureBottomBar(host, snapshot: snapshot)
  }

  /// 单行底栏只在正文显示；HTML 弹层期间释放整行占位，让弹窗延伸至屏幕底部。
  private func configureBottomBar(_ host: ContentHostController, snapshot: NavigationSnapshot) {
    host.toolbarItems = nil
    host.navigationController?.setToolbarHidden(true, animated: false)
    let visible = snapshot.chrome.bottomVisible && snapshot.presentation?.overlayOpen != true
    host.additionalSafeAreaInsets.bottom =
      visible ? BottomNavigationView.height + BottomNavigationView.bottomSpacing : 0
    if bottomNavigation.superview == nil {
      bottomNavigation.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(bottomNavigation)
      NSLayoutConstraint.activate([
        bottomNavigation.leadingAnchor.constraint(
          equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        bottomNavigation.trailingAnchor.constraint(
          equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        // 系统 Tab Bar 自己消费 Home Indicator 区域，不能把它压进仅容纳图标的紧凑高度。
        bottomNavigation.topAnchor.constraint(
          equalTo: view.safeAreaLayoutGuide.bottomAnchor,
          constant: -(BottomNavigationView.height + BottomNavigationView.bottomSpacing)),
        bottomNavigation.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      ])
    }
    let accessory = snapshot.actions.first { $0.position == .accessory }.map { action in
      bottomActionButton(action)
    }
    bottomNavigation.apply(snapshot, action: accessory) { [weak self] rootId in
      self?.coordinator.command(
        "navigation.selectRoot", payload: .object(["rootId": .string(rootId)]))
    }
    bottomNavigation.isHidden = !nativeVisible || !visible
    if !bottomNavigation.isHidden { view.bringSubviewToFront(bottomNavigation) }
    keepStartupInFront()
  }

  /// 单入口展开系统横向操作区；HTML 弹层期间整体禁用，返回仍可关闭弹层。
  private func connectionItem(overflow: [ActionSnapshot] = [], enabled: Bool = true)
    -> UIBarButtonItem
  {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "ellipsis")
    let button = HeaderActionsButton(configuration: configuration)
    button.onMenuVisibilityChange = { [weak self] expanded in
      self?.setTopActionsExpanded(expanded)
    }
    button.accessibilityLabel = "操作菜单"
    button.accessibilityIdentifier = "native-top-actions"
    button.isEnabled = enabled
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    let actions: [UIMenuElement] = overflow.map { action in
      if let menu = action.menu, !menu.isEmpty { return actionMenu(action, items: menu) }
      return UIAction(
        title: action.title, image: symbol(action.icon),
        attributes: action.enabled && !action.loading ? [] : [.disabled]
      ) { [weak self, weak button] _ in
        guard let self else { return }
        let frame = button.map { $0.convert($0.bounds, to: self.coordinator.webView) }
        self.coordinator.invoke(action, frame: frame)
      }
    }
    let connection = UIMenu(
      title: "连接与显示", image: UIImage(systemName: "gearshape"),
      children: [
        UIAction(title: "通知", image: UIImage(systemName: "bell.badge")) { [weak self] _ in
          guard let self else { return }
          let settings = NotificationController(coordinator: self.coordinator)
          self.present(UINavigationController(rootViewController: settings), animated: true)
        },
        UIAction(title: "重新加载", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
          self?.coordinator.reloadInWebMode()
        },
        UIAction(title: "更改服务地址", image: UIImage(systemName: "server.rack")) { [weak self] _ in
          self?.onConnection()
        },
        UIAction(title: "使用网页导航", image: UIImage(systemName: "globe")) { [weak self] _ in
          self?.coordinator.releaseChrome()
        },
      ])
    let menu = UIMenu(options: .displayAsPalette, children: actions + [connection])
    menu.preferredElementSize = .large
    button.menu = menu
    button.showsMenuAsPrimaryAction = true
    let item = UIBarButtonItem(customView: button)
    // UIBarButtonItem 会同步自定义按钮的启用状态，两层保持一致，避免安装时重新启用。
    item.isEnabled = enabled
    return item
  }

  /// 通知属于其他登录身份时给出系统提示，不自动切换账号或加载外部地址。
  func showNotificationMessage(_ message: String) {
    guard presentedViewController == nil else { return }
    let alert = UIAlertController(title: "通知", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    present(alert, animated: true)
  }

  /// 横向操作临时覆盖标题区；收起时只恢复最新已确认的路由标题，不保存旧页面文案。
  private func setTopActionsExpanded(_ expanded: Bool) {
    topActionsExpanded = expanded
    let host = selectedHost
    host.navigationItem.title = expanded ? nil : (latest?.route.title ?? "MoviePilot")
    host.navigationItem.titleView?.alpha = expanded ? 0 : 1
    host.navigationItem.titleView?.accessibilityElementsHidden = expanded
  }

  /// 底部大按钮独立使用系统玻璃，并将可量测的位置提供给原 HTML 菜单。
  private func bottomActionButton(_ action: ActionSnapshot) -> UIButton {
    var configuration: UIButton.Configuration = .tinted()
    if #available(iOS 26.0, *) { configuration = .glass() }
    configuration.cornerStyle = .capsule
    configuration.preferredSymbolConfigurationForImage = NavigationSymbols.bottomConfiguration
    configuration.image = symbol(action.icon)
    configuration.showsActivityIndicator = action.loading
    let button = UIButton(configuration: configuration)
    button.accessibilityLabel = action.title
    button.isEnabled = action.enabled && !action.loading
    button.addAction(
      UIAction { [weak self, weak button] _ in
        guard let self else { return }
        let frame = button.map { $0.convert($0.bounds, to: self.coordinator.webView) }
        self.coordinator.invoke(action, frame: frame)
      }, for: .touchUpInside)
    if let menu = action.menu, !menu.isEmpty {
      button.menu = actionMenu(action, items: menu)
      button.showsMenuAsPrimaryAction = true
    }
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
  }

  /// 纯命令菜单只传稳定动作标识，回调及权限复核留在网页。
  private func actionMenu(_ parent: ActionSnapshot, items: [ActionMenuItem]) -> UIMenu {
    UIMenu(
      children: items.map { item in
        UIAction(
          title: item.title, image: symbol(item.icon), attributes: item.enabled ? [] : [.disabled]
        ) { [weak self] _ in
          self?.coordinator.invoke(parent, menuActionId: item.actionId)
        }
      })
  }

  /// 显式图标映射只决定显示，未知插件图标采用通用符号与文字标签。
  private func symbol(_ key: String) -> UIImage? {
    NavigationSymbols.image(key)
  }

  /// 更多页覆盖呈现原生菜单，唯一 WebView 留在同一会话中；HTML 弹层打开时恢复其可见性。
  private func configureMoreMenu(_ host: ContentHostController, snapshot: NavigationSnapshot) {
    let visible = snapshot.chrome.content == .menu && snapshot.presentation?.overlayOpen != true
    coordinator.content.view.isHidden = visible
    guard visible else {
      removeMoreMenu()
      host.trackContentScrollView(coordinator.webView.scrollView)
      return
    }
    moreMenu.apply(snapshot.moreMenu ?? [])
    if moreMenu.parent !== host {
      removeMoreMenu()
      host.addChild(moreMenu)
      moreMenu.view.translatesAutoresizingMaskIntoConstraints = false
      host.view.addSubview(moreMenu.view)
      NSLayoutConstraint.activate([
        moreMenu.view.topAnchor.constraint(equalTo: host.view.topAnchor),
        moreMenu.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        moreMenu.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
        moreMenu.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
      ])
      moreMenu.didMove(toParent: host)
    }
    host.trackContentScrollView(moreMenu.tableView)
  }

  /// 切换正文时解除原生菜单的标准父子关系，不销毁网页或路由状态。
  private func removeMoreMenu() {
    guard moreMenu.parent != nil else { return }
    moreMenu.endSearch()
    moreMenu.willMove(toParent: nil)
    moreMenu.view.removeFromSuperview()
    moreMenu.removeFromParent()
  }

  /// 一次只显示一个已确认的容器，控制器切换不触发任何网页 load。
  private func install(_ controller: UIViewController) {
    if controller.parent == nil { add(controller) }
    controller.view.alpha = 1
    controller.view.isUserInteractionEnabled = true
    view.bringSubviewToFront(controller.view)
    if let old = activeContainer, old !== controller { remove(old) }
    activeContainer = controller
    keepStartupInFront()
  }

  /// 标准 UIKit 子控制器安装流程。
  private func add(_ controller: UIViewController) {
    addChild(controller)
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.topAnchor.constraint(equalTo: view.topAnchor),
      controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    controller.didMove(toParent: self)
  }

  /// 标准 UIKit 子控制器卸载流程；不会销毁协调器持有的网页内容。
  private func remove(_ controller: UIViewController) {
    guard controller.parent === self else { return }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }

  /// 系统 point 边距统一序列化，网页端按真实 viewport 比例转换 CSS 像素。
  private func insets(_ value: UIEdgeInsets) -> JSONValue {
    .object([
      "top": .number(value.top), "left": .number(value.left), "bottom": .number(value.bottom),
      "right": .number(value.right),
    ])
  }
}
