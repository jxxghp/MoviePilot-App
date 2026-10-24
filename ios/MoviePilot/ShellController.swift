import MoviePilotCore
import UIKit
import WebKit

/// 顶栏只在其展示声明改变时更新，普通页面刷新不能打断正在操作的系统菜单。
private struct NativeHeaderConfiguration: Equatable {
  let title: String
  let canGoBack: Bool
  let tabs: HeaderTabsSnapshot?
  let actions: [ActionSnapshot]
  let overlayOpen: Bool
}

/// 系统顶部和底部导航的呈现层，所有路由与业务动作只发送网页意图。
@MainActor
final class ShellController: UIViewController, UIPopoverPresentationControllerDelegate {
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
  private var panelNavigation: UINavigationController?
  private var panelImages: NativePanelImageLoader?
  private var panelAction: ActionSnapshot?
  private var webSheet: NativeWebSheetController?
  private var sheetNavigation: UINavigationController?
  private var sheetAttachedID: String?
  private var sheetDismissing = false
  private var preparingSheetID: String?
  private var sheetSnapshotToken: UUID?
  private var sheetPagePlaceholder: UIImageView?
  private var headerConfigurations: [ObjectIdentifier: NativeHeaderConfiguration] = [:]

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
    headerConfigurations.removeAll()
    dismissNativePanel(notify: false)
    nativeVisible = false
    latest = nil
    dismissWebSheet(animated: false)
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
    if webSheet == nil { host.attach(coordinator.content) }
    configureMoreMenu(host, snapshot: snapshot)
    if let container = nativeContainer {
      container.view.alpha = 1
      container.view.isUserInteractionEnabled = true
      install(container)
    }
    configureHeader(host, snapshot: snapshot)
    view.layoutIfNeeded()
    synchronizeWebSheet(snapshot)
    synchronizeNativePanel(snapshot)
    keepStartupInFront()
  }

  /// 返回当前最终宿主的 point 几何，正文和菜单锚点使用同一坐标原点。
  func layoutPayload(revision: Int, keyboard: CGRect?) -> JSONValue {
    let host =
      webSheet?.contentHost
      ?? (nativeVisible ? selectedHost : (latest == nil ? compatibilityHost : selectedHost))
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
      "consumedByNativeFrame": .bool(webSheet != nil),
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
      headerConfigurations.removeAll()
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
    let trailing = snapshot.actions.filter { $0.position != .accessory }
    let configuration = NativeHeaderConfiguration(
      title: snapshot.route.title, canGoBack: snapshot.route.canGoBack,
      tabs: snapshot.headerTabs, actions: trailing,
      overlayOpen: snapshot.presentation?.overlayOpen == true)
    let identity = ObjectIdentifier(host)
    guard headerConfigurations[identity] != configuration else {
      configureBottomBar(host, snapshot: snapshot)
      return
    }
    headerConfigurations[identity] = configuration
    // UIViewController.title 会连带修改导航容器的 Tab 名称，详情标题只属于顶部栏。
    host.navigationItem.title = snapshot.route.title
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
      host.navigationItem.titleView = button
    }
    configureBottomBar(host, snapshot: snapshot)
  }

  /// 普通菜单保留底栏，只有网页明确声明的全屏弹窗释放整行占位。
  private func configureBottomBar(_ host: ContentHostController, snapshot: NavigationSnapshot) {
    host.toolbarItems = nil
    host.navigationController?.setToolbarHidden(true, animated: false)
    let visible = snapshot.chrome.bottomVisible && snapshot.presentation?.fullscreen != true
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
      if self?.latest?.roots.first(where: { $0.id == rootId })?.path == "/apps" {
        self?.moreMenu.resetSearch()
      }
      self?.coordinator.command(
        "navigation.selectRoot", payload: .object(["rootId": .string(rootId)]))
    }
    bottomNavigation.isHidden = !nativeVisible || !visible
    if !bottomNavigation.isHidden { view.bringSubviewToFront(bottomNavigation) }
    keepStartupInFront()
  }

  /// 常用入口与页面注册动作使用带标题的独立系统分组；HTML 弹层期间禁用。
  private func connectionItem(overflow: [ActionSnapshot] = [], enabled: Bool = true)
    -> UIBarButtonItem
  {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "ellipsis")
    let button = UIButton(configuration: configuration)
    button.accessibilityLabel = "操作菜单"
    button.accessibilityIdentifier = "native-top-actions"
    button.isEnabled = enabled
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    let globalOrder = ["search", "shortcuts", "notifications", "plugins", "profile"]
    let globals = overflow.enumerated().filter { $0.element.isGlobal }.sorted { left, right in
      let leftRank =
        globalOrder.firstIndex(of: String(left.element.actionId.split(separator: ":").last ?? ""))
        ?? globalOrder.count
      let rightRank =
        globalOrder.firstIndex(of: String(right.element.actionId.split(separator: ":").last ?? ""))
        ?? globalOrder.count
      return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
    }.map(\.element)
    let pages = overflow.filter { !$0.isGlobal }
    /// 继续引用原网页动作，不因菜单分组复制业务或绕过禁用状态。
    func menuElement(_ action: ActionSnapshot) -> UIMenuElement {
      if let menu = action.menu, !menu.isEmpty {
        return UIMenu(
          title: action.title, image: symbol(action.icon),
          children: actionMenu(action, items: menu).children)
      }
      return UIAction(
        title: action.title, image: symbol(action.icon),
        attributes: action.enabled && !action.loading ? [] : [.disabled]
      ) { [weak self, weak button] _ in
        guard let self else { return }
        if action.panel != nil {
          self.openNativePanel(action)
          return
        }
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
          let navigation = UINavigationController(rootViewController: settings)
          navigation.overrideUserInterfaceStyle = self.overrideUserInterfaceStyle
          navigation.view.tintColor = self.view.tintColor
          NativeModalAppearance.apply(
            to: navigation.presentationController, style: self.traitCollection.userInterfaceStyle)
          navigation.sheetPresentationController?.detents = [.medium(), .large()]
          navigation.sheetPresentationController?.prefersGrabberVisible = true
          self.present(navigation, animated: true)
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
    var groups = [
      UIMenu(
        title: "常用入口", options: .displayInline, children: globals.map(menuElement) + [connection])
    ]
    if !pages.isEmpty {
      groups.append(
        UIMenu(title: "当前页面", options: .displayInline, children: pages.map(menuElement)))
    }
    let menu = UIMenu(children: groups)
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

  /// 业务弹窗搬入系统 Sheet；同一个文档继续负责表单、插件和嵌套弹窗状态。
  private func synchronizeWebSheet(_ snapshot: NavigationSnapshot) {
    guard !sheetDismissing else { return }
    guard let descriptor = snapshot.presentation?.sheet else {
      dismissWebSheet()
      return
    }
    if let panelNavigation {
      if !panelNavigation.isBeingDismissed {
        dismissNativePanel(notify: false) { [weak self] in
          guard let self, let latest = self.latest else { return }
          self.synchronizeWebSheet(latest)
        }
      }
      return
    }
    if let controller = webSheet {
      sheetNavigation?.overrideUserInterfaceStyle = overrideUserInterfaceStyle
      controller.apply(descriptor, style: traitCollection.userInterfaceStyle)
      if sheetAttachedID != descriptor.id {
        sheetAttachedID = descriptor.id
        coordinator.command("presentation.attach", payload: .object(["id": .string(descriptor.id)]))
      }
      return
    }
    guard presentedViewController == nil, nativeVisible else { return }
    if let ready = descriptor.backdropReady {
      if !ready {
        if preparingSheetID != descriptor.id {
          preparingSheetID = descriptor.id
          sheetSnapshotToken = nil
          coordinator.command(
            "presentation.prepare", payload: .object(["id": .string(descriptor.id)]))
        }
      } else if sheetSnapshotToken == nil {
        preserveWebSheetPage(descriptor)
      }
      return
    }
    presentWebSheet(descriptor)
  }

  /// 唯一 WebView 搬走前保留底页，仅作为系统转场下的页面上下文，不绘制玻璃或模糊材质。
  private func preserveWebSheetPage(_ descriptor: NativeSheetSnapshot) {
    let token = UUID()
    sheetSnapshotToken = token
    preparingSheetID = descriptor.id
    if latest?.chrome.content == .menu {
      finishWebSheetPreparation(id: descriptor.id, token: token, image: nil)
      return
    }
    let configuration = WKSnapshotConfiguration()
    configuration.rect = coordinator.webView.bounds
    configuration.afterScreenUpdates = true
    coordinator.webView.takeSnapshot(with: configuration) { [weak self] image, _ in
      self?.finishWebSheetPreparation(id: descriptor.id, token: token, image: image)
    }
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      // 页面快照失败或进程挂起不能让业务弹窗一直等待，也不重复执行业务动作。
      self?.finishWebSheetPreparation(id: descriptor.id, token: token, image: nil)
    }
  }

  /// 只接收仍属当前弹窗的准备结果，底页只驻留内存，关闭或降级后立即释放。
  private func finishWebSheetPreparation(id: String, token: UUID, image: UIImage?) {
    guard sheetSnapshotToken == token, preparingSheetID == id,
      let descriptor = latest?.presentation?.sheet, descriptor.id == id,
      descriptor.backdropReady == true, nativeVisible, presentedViewController == nil
    else { return }
    sheetSnapshotToken = nil
    preparingSheetID = nil
    if let image {
      let page = UIImageView(image: image)
      page.frame = selectedHost.view.bounds
      page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      page.contentMode = .scaleToFill
      page.accessibilityElementsHidden = true
      page.isUserInteractionEnabled = false
      selectedHost.view.addSubview(page)
      sheetPagePlaceholder = page
    }
    presentWebSheet(descriptor)
  }

  /// 标题、关闭按钮、背景和转场来自系统 Sheet，同一 Vue 文档继续持有原表单。
  private func presentWebSheet(_ descriptor: NativeSheetSnapshot) {
    guard presentedViewController == nil, webSheet == nil, nativeVisible else { return }
    let controller = NativeWebSheetController(snapshot: descriptor) { [weak self] type, action in
      self?.invokeWebSheetCommand(type, action: action)
    }
    controller.onLayout = { [weak self] in self?.coordinator.layoutChanged() }
    let navigation = UINavigationController(rootViewController: controller)
    navigation.overrideUserInterfaceStyle = overrideUserInterfaceStyle
    navigation.view.backgroundColor = .clear
    navigation.view.tintColor = view.tintColor
    navigation.modalPresentationStyle = .pageSheet
    webSheet = controller
    sheetNavigation = navigation
    sheetAttachedID = descriptor.id
    controller.loadViewIfNeeded()
    controller.contentHost.attach(coordinator.content)
    coordinator.content.view.isHidden = false
    coordinator.content.view.backgroundColor = .clear
    coordinator.webView.isOpaque = false
    coordinator.webView.backgroundColor = .clear
    coordinator.webView.underPageBackgroundColor = .clear
    coordinator.webView.scrollView.backgroundColor = .clear
    controller.apply(descriptor, style: traitCollection.userInterfaceStyle)
    navigation.presentationController?.delegate = controller
    coordinator.command("presentation.attach", payload: .object(["id": .string(descriptor.id)]))
    present(navigation, animated: true) { [weak self] in self?.coordinator.layoutChanged() }
  }

  /// 原生栏只接受最新弹窗的关闭和标题栏动作，嵌套后旧标识不能再次执行。
  private func invokeWebSheetCommand(_ type: String, action: String?) {
    guard !sheetDismissing, let descriptor = latest?.presentation?.sheet,
      descriptor.id == sheetAttachedID,
      (type == "presentation.dismiss" && descriptor.canDismiss)
        || (type == "presentation.action"
          && descriptor.actions.contains(where: { $0.id == action && $0.enabled }))
    else { return }
    var payload: [String: JSONValue] = ["id": .string(descriptor.id)]
    if let action { payload["actionId"] = .string(action) }
    coordinator.command(type, payload: .object(payload))
  }

  /// Vue 确认关闭后再退出系统动画，交还原宿主；外围背景由系统同步恢复。
  private func dismissWebSheet(animated: Bool = true) {
    preparingSheetID = nil
    sheetSnapshotToken = nil
    guard let navigation = sheetNavigation, !sheetDismissing else {
      if sheetNavigation == nil {
        sheetPagePlaceholder?.removeFromSuperview()
        sheetPagePlaceholder = nil
      }
      return
    }
    sheetDismissing = true
    let id = sheetAttachedID
    navigation.dismiss(animated: animated) { [weak self] in
      guard let self else { return }
      self.webSheet = nil
      self.sheetNavigation = nil
      self.sheetAttachedID = nil
      self.sheetDismissing = false
      let host = self.nativeVisible ? self.selectedHost : self.compatibilityHost
      host.attach(self.coordinator.content)
      self.coordinator.content.view.backgroundColor = .systemBackground
      self.coordinator.webView.isOpaque = true
      self.coordinator.webView.backgroundColor = .systemBackground
      self.coordinator.webView.underPageBackgroundColor = .systemBackground
      self.coordinator.webView.scrollView.backgroundColor = .systemBackground
      self.sheetPagePlaceholder?.removeFromSuperview()
      self.sheetPagePlaceholder = nil
      if let id {
        self.coordinator.command("presentation.detach", payload: .object(["id": .string(id)]))
      }
      if self.nativeVisible, let latest = self.latest { self.apply(latest) }
      self.coordinator.layoutChanged()
    }
  }

  /// 快捷入口在系统浮层内使用独立导航，锚点位于宿主顶栏下方，底部导航继续显示。
  private func openNativePanel(_ action: ActionSnapshot) {
    guard panelNavigation == nil, presentedViewController == nil, let snapshot = action.panel,
      action.enabled, !action.loading, nativeVisible
    else { return }
    panelAction = action
    let images = NativePanelImageLoader(
      store: coordinator.webView.configuration.websiteDataStore,
      origin: coordinator.instance.address.origin)
    panelImages = images
    let controller = NativePanelController(
      snapshot: snapshot, images: images,
      onEvent: { [weak self] event, item, value, keepOpen in
        guard let self, self.panelAction?.actionId == action.actionId,
          self.panelAction?.ownerId == action.ownerId
        else { return }
        self.invokePanelEvent(event, item: item, value: value, keepOpen: keepOpen)
      }, onClose: { [weak self] in self?.dismissNativePanel() })
    let navigation = UINavigationController(rootViewController: controller)
    navigation.overrideUserInterfaceStyle = overrideUserInterfaceStyle
    navigation.view.tintColor = view.tintColor
    navigation.modalPresentationStyle = .popover
    controller.loadViewIfNeeded()
    navigation.preferredContentSize = CGSize(
      width: controller.preferredPanelWidth(maximum: min(view.bounds.width - 40, 430)),
      height: min(
        580,
        max(280, view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 170)))
    if let popover = navigation.popoverPresentationController {
      popover.delegate = self
      popover.sourceView = view
      popover.sourceRect = CGRect(
        x: view.bounds.maxX - 38, y: view.safeAreaInsets.top + 44, width: 1, height: 1)
      popover.permittedArrowDirections = .up
      popover.passthroughViews = nil
    }
    navigation.presentationController?.delegate = self
    NativeModalAppearance.apply(
      to: navigation.presentationController, style: traitCollection.userInterfaceStyle)
    panelNavigation = navigation
    present(navigation, animated: true)
    coordinator.invoke(action, panelEvent: "open")
    synchronizeNativePanel(latest)
  }

  /// 输入和勾选留在面板中，打开业务页面或 HTML 弹窗前先完成系统浮层关闭。
  private func invokePanelEvent(_ event: String, item: String?, value: String?, keepOpen: Bool) {
    guard let previous = panelAction,
      let action = latest?.actions.first(where: {
        $0.actionId == previous.actionId && $0.ownerId == previous.ownerId
      })
    else {
      dismissNativePanel(notify: false)
      return
    }
    if keepOpen {
      coordinator.invoke(action, panelEvent: event, itemId: item, value: value)
    } else {
      dismissNativePanel(notify: false) { [weak self] in
        self?.coordinator.invoke(action, panelEvent: event, itemId: item, value: value)
      }
    }
  }

  /// 只更新同一 owner 的面板；切换身份、业务路由、权限或打开网页弹窗立即撤销旧面板。
  private func synchronizeNativePanel(_ snapshot: NavigationSnapshot?) {
    guard let snapshot else { return }
    if let navigation = panelNavigation, let previous = panelAction {
      guard
        let action = snapshot.actions.first(where: {
          $0.actionId == previous.actionId && $0.ownerId == previous.ownerId && $0.enabled
        }), let panel = action.panel, snapshot.presentation?.overlayOpen != true
      else {
        dismissNativePanel(notify: false)
        return
      }
      panelAction = action
      navigation.overrideUserInterfaceStyle = overrideUserInterfaceStyle
      navigation.view.tintColor = view.tintColor
      NativeModalAppearance.apply(
        to: navigation.presentationController, style: traitCollection.userInterfaceStyle)
      for case let controller as NativePanelController in navigation.viewControllers {
        controller.apply(panel)
      }
      // 普通浮层保留原页面和底栏，玻璃与阴影仅由系统浮层本体提供。
      view.bringSubviewToFront(bottomNavigation)
    } else if let requested = snapshot.presentation?.requestedPanel,
      let action = snapshot.actions.first(where: {
        $0.actionId.hasSuffix(":global:\(requested)") && $0.panel != nil
      })
    {
      openNativePanel(action)
    }
  }

  /// 关闭后释放临时面板，取消命令只发送给仍有效的当前父动作。
  private func dismissNativePanel(notify: Bool = true, completion: (() -> Void)? = nil) {
    let navigation = panelNavigation
    let action = panelAction
    panelNavigation = nil
    panelAction = nil
    panelImages?.stop()
    panelImages = nil
    if notify, let action { coordinator.invoke(action, panelEvent: "close") }
    guard let navigation else {
      completion?()
      return
    }
    navigation.dismiss(animated: true, completion: completion)
  }

  /// iPhone 上也保留真正的系统浮层，避免自适应为遮住底栏的整页菜单。
  func adaptivePresentationStyle(for controller: UIPresentationController)
    -> UIModalPresentationStyle
  { .none }

  /// 横竖屏 trait 改变时同样保持浮层语义。
  func adaptivePresentationStyle(
    for controller: UIPresentationController, traitCollection: UITraitCollection
  ) -> UIModalPresentationStyle { .none }

  /// 点浮层外部关闭时同步网页状态，避免保留不可见的搜索面板会话。
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === panelNavigation else { return }
    dismissNativePanel()
  }

  /// 更多目录在 Sheet 下保留真实原生视图，唯一 WebView 进入弹窗后仍保持可见。
  private func configureMoreMenu(_ host: ContentHostController, snapshot: NavigationSnapshot) {
    let visible = snapshot.chrome.content == .menu
    coordinator.content.view.isHidden = visible && webSheet == nil
    guard visible else {
      removeMoreMenu()
      host.trackContentScrollView(coordinator.webView.scrollView)
      return
    }
    moreMenu.apply(
      snapshot.moreMenu ?? [],
      background: NavigationSymbols.color(snapshot.chrome.backgroundColor)
        ?? .systemGroupedBackground,
      surface: NavigationSymbols.color(snapshot.chrome.surfaceColor)
        ?? .secondarySystemGroupedBackground)
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
