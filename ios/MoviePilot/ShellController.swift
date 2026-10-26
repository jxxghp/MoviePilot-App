import MoviePilotCore
import UIKit
import WebKit

/// 系统菜单展开期间保留其声明和锚点，异步状态在关闭动画完成后再更新下一次菜单。
@MainActor
private final class NativeMenuButton: UIButton {
  private var pendingMenu: UIMenu?
  private var presentingMenu = false
  var onMenuClose: (() -> Void)?

  /// UIKit 已展示的二级菜单不能被新的 menu 属性赋值打断，业务选择仍会复核最新快照。
  func apply(menu: UIMenu) {
    if presentingMenu || isHeld {
      pendingMenu = menu
    } else {
      pendingMenu = nil
      self.menu = menu
    }
  }

  /// 在 UIKit 解析延迟子菜单之前锁定当前声明，避免首帧的异步结果重建菜单树。
  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    presentingMenu = true
    let configuration = super.contextMenuInteraction(
      interaction, configurationForMenuAtLocation: location)
    if configuration == nil { presentingMenu = false }
    return configuration
  }

  /// 等待系统菜单退出后消费最后一次声明，不添加定时器或改动系统转场。
  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    let update = { [weak self] in
      guard let self else { return }
      self.presentingMenu = false
      self.onMenuClose?()
      guard let menu = self.pendingMenu else { return }
      self.pendingMenu = nil
      self.menu = menu
    }
    if let animator { animator.addCompletion(update) } else { update() }
  }
}

/// 用户菜单只等待当前网页面板的一次投影，超时或文档失效时必须完成 UIKit 的延迟回调。
private struct NativeUserMenuRequest {
  let token: UUID
  let document: String
  let action: ActionSnapshot
  let completion: ([UIMenuElement]) -> Void
}

/// 顶栏只在其展示声明改变时更新，普通页面刷新不能打断正在操作的系统菜单。
private struct NativeHeaderConfiguration: Equatable {
  let session: String?
  let title: String
  let canGoBack: Bool
  let tabs: HeaderTabsSnapshot?
  let actions: [ActionSnapshot]
  let overlayOpen: Bool
}

/// 系统顶部和底部导航的呈现层，所有路由与业务动作只发送网页意图。
@MainActor
final class ShellController: UIViewController, UIPopoverPresentationControllerDelegate,
  UIGestureRecognizerDelegate
{
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
  private var edgeBackIdentity: EdgeBackIdentity?
  private let navigationPreviews = NavigationPreviewCache()
  private var edgeBackTransition: NavigationBackTransition?
  private var edgeBackTarget: String?
  private var edgeBackAnimationFinished = false
  private var edgeBackPaintPending = false
  private var edgeBackTimeout: Timer?
  private var previewCapture: DispatchWorkItem?
  private let moreMenu = MoreMenuController()
  private let bottomNavigation = BottomNavigationView()
  private var panelNavigation: UINavigationController?
  private var panelImages: NativePanelImageLoader?
  private var panelAction: ActionSnapshot?
  private var userMenuAvatar: NativeUserMenuAvatar?
  private var userMenuAvatarContext: String?
  private var userMenuRequest: NativeUserMenuRequest?
  private var userMenuAction: ActionSnapshot?
  private var userMenuTimeout: Timer?
  private var confirmationAlert: UIAlertController?
  private var confirmationSnapshot: NativeConfirmationSnapshot?
  private var answeringConfirmationID: String?
  private var webSheet: NativeWebSheetController?
  private var sheetNavigation: UINavigationController?
  private var sheetAttachedID: String?
  private var sheetDismissing = false
  private var sheetRestoreToken: UUID?
  private var preparingSheetID: String?
  private var sheetSnapshotToken: UUID?
  private var sheetPagePlaceholder: UIView?
  private var sheetExitPlaceholder: UIView?
  private var headerConfigurations: [ObjectIdentifier: NativeHeaderConfiguration] = [:]

  /// 直接使用已确认的页面主题，避免 UIKit trait 传播尚未结束时取到上一主题的浮层外观。
  private var modalInterfaceStyle: UIUserInterfaceStyle {
    overrideUserInterfaceStyle == .unspecified
      ? traitCollection.userInterfaceStyle : overrideUserInterfaceStyle
  }

  /// 容器保存协调器；协调器以弱引用回调 UI，避免脚本与视图形成环。
  init(
    coordinator: WebCoordinator,
    onConnection: @escaping () -> Void
  ) {
    self.coordinator = coordinator
    self.onConnection = onConnection
    super.init(nibName: nil, bundle: nil)
    moreMenu.onSelect = { [weak self] item in self?.coordinator.openMenuItem(item) }
  }

  /// 本地会话按实例重建，不支持 storyboard 初始化。
  required init?(coder: NSCoder) { fatalError("Use init(coordinator:onConnection:)") }

  /// 启动和底页占位期间匹配可见背景，归位后按当前明暗更新状态栏。
  override var preferredStatusBarStyle: UIStatusBarStyle {
    guard startupView == nil else { return .lightContent }
    let style = sheetPagePlaceholder?.overrideUserInterfaceStyle ?? modalInterfaceStyle
    return style == .dark ? .lightContent : .darkContent
  }

  /// 首次进入延续静态启动画面，唯一 WebView 在覆盖层后完成加载和布局。
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    installBackGesture(on: view)
    prepareDocumentHost()
  }

  /// 系统安全区改变后刷新当前布局，不修改业务路由。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    synchronizeNavigationPreviewContext()
    coordinator.layoutChanged()
  }

  /// 预览只跨同一文档、主题与窗口保留，外观或身份变化不复用旧画面。
  private func synchronizeNavigationPreviewContext() {
    let context = coordinator.navigationPreviewSession.map { session in
      [
        session, latest?.chrome.theme.rawValue ?? "", latest?.chrome.accentColor ?? "",
        latest?.chrome.backgroundColor ?? "", latest?.chrome.surfaceColor ?? "",
      ].joined(separator: "|")
    }
    navigationPreviews.synchronize(context: context, size: view.bounds.size)
  }

  /// Vue 提交路由前保存原生导航和现有正文；浮层、交接或键盘覆盖时不保存错误画面。
  func captureNavigationPreview() {
    guard nativeVisible, startupView == nil, recoveryView == nil,
      presentedViewController == nil, webSheet == nil, edgeBackTransition == nil,
      latest?.presentation?.overlayOpen != true, let path = latest?.route.fullPath
    else { return }
    synchronizeNavigationPreviewContext()
    navigationPreviews.capture(view, path: path)
  }

  /// 生命周期和会话释放时停止旧动画与延迟采样，画面不会跨账号或写入磁盘。
  func clearNavigationPreviews() {
    previewCapture?.cancel()
    previewCapture = nil
    navigationPreviews.clear()
    edgeBackTimeout?.invalidate()
    edgeBackTimeout = nil
    edgeBackTransition?.remove()
    edgeBackTransition = nil
    edgeBackIdentity = nil
    edgeBackTarget = nil
    edgeBackAnimationFinished = false
    edgeBackPaintPending = false
    userMenuAvatar?.stop()
    userMenuAvatar = nil
    userMenuAvatarContext = nil
    closeUserMenu()
  }

  /// 首屏和静止页面补充预览；正常离页由显式握手采样，避免依赖异步业务加载时序。
  private func scheduleNavigationPreview() {
    previewCapture?.cancel()
    let path = latest?.route.fullPath
    let capture = DispatchWorkItem { [weak self] in
      guard let self, self.latest?.route.fullPath == path else { return }
      self.captureNavigationPreview()
    }
    previewCapture = capture
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: capture)
  }

  /// 使用系统左边缘识别器，普通横向列表和网页自身触摸不参与返回判定。
  private func installBackGesture(on target: UIView) {
    let gesture = UIScreenEdgePanGestureRecognizer(
      target: self, action: #selector(handleBackGesture))
    gesture.edges = .left
    gesture.delegate = self
    target.addGestureRecognizer(gesture)
  }

  /// 只有可返回的当前原生页面或可关闭的业务弹窗才能开始侧滑。
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let gesture = gestureRecognizer as? UIScreenEdgePanGestureRecognizer,
      nativeVisible, recoveryView == nil, startupView == nil, !sheetDismissing,
      edgeBackTransition == nil
    else { return false }
    let sheetID: String?
    if gesture.view === sheetNavigation?.view {
      sheetID = sheetAttachedID
      guard sheetID != nil else { return false }
    } else {
      guard presentedViewController == nil else { return false }
      sheetID = nil
    }
    let velocity = gesture.velocity(in: gesture.view)
    guard velocity.x > 0, abs(velocity.x) > abs(velocity.y),
      let identity = coordinator.backGestureIdentity(sheetID: sheetID)
    else { return false }
    edgeBackIdentity = identity
    return true
  }

  /// 当前卡片连续跟手；松手后才按有效身份提交一次返回，取消只回弹。
  @objc private func handleBackGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
    guard let identity = edgeBackIdentity else { return }
    let distance = gesture.translation(in: gesture.view).x
    if gesture.state == .began, identity.sheetID == nil {
      synchronizeNavigationPreviewContext()
      edgeBackTarget = latest?.route.backTarget
      edgeBackTransition = NavigationBackTransition(
        host: view, previous: navigationPreviews.image(for: edgeBackTarget))
      edgeBackAnimationFinished = false
      edgeBackPaintPending = false
    }
    if gesture.state == .began || gesture.state == .changed {
      edgeBackTransition?.update(distance: distance)
      return
    }
    guard [.ended, .cancelled, .failed].contains(gesture.state) else { return }
    let current = coordinator.backGestureIdentity(sheetID: identity.sheetID)
    let commit = EdgeBackGesture.shouldCommit(
      distance: Double(distance),
      velocity: Double(gesture.velocity(in: gesture.view).x),
      width: Double(gesture.view?.bounds.width ?? 0),
      cancelled: gesture.state != .ended, began: identity, current: current)
    guard identity.sheetID == nil, let transition = edgeBackTransition else {
      edgeBackIdentity = nil
      if commit {
        if identity.sheetID != nil { preserveWebSheetExit() }
        coordinator.completeBackGesture(identity)
      }
      return
    }
    guard commit else {
      cancelInteractiveBack(transition)
      return
    }
    transition.animate(completed: true) { [weak self, weak transition] in
      guard let self, self.edgeBackTransition === transition else { return }
      self.edgeBackAnimationFinished = true
      self.finishInteractiveBackIfReady()
    }
    edgeBackTimeout = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) {
      [weak self, weak transition] _ in
      MainActor.assumeIsolated {
        guard let self, let transition, self.edgeBackTransition === transition else { return }
        self.cancelInteractiveBack(transition)
      }
    }
    coordinator.completeBackGesture(identity) { [weak self, weak transition] accepted in
      guard !accepted, let self, let transition, self.edgeBackTransition === transition else {
        return
      }
      self.cancelInteractiveBack(transition)
    }
  }

  /// 短滑、守卫拒绝和上下文失效都恢复当前页，不向 Router 发送第二次导航。
  private func cancelInteractiveBack(_ transition: NavigationBackTransition) {
    edgeBackTimeout?.invalidate()
    edgeBackTimeout = nil
    edgeBackTarget = nil
    transition.animate(completed: false) { [weak self, weak transition] in
      guard let self, self.edgeBackTransition === transition else { return }
      self.clearInteractiveBack()
    }
  }

  /// 动画和真实路由都完成后等待两次 Web 绘制，避免移开卡片时露出旧正文。
  private func finishInteractiveBackIfReady() {
    guard let transition = edgeBackTransition, let target = edgeBackTarget,
      edgeBackAnimationFinished, latest?.route.fullPath == target, !edgeBackPaintPending
    else { return }
    edgeBackPaintPending = true
    coordinator.command("navigation.waitForPaint", payload: .object([:])) {
      [weak self, weak transition] _ in
      guard let self, self.edgeBackTransition === transition else { return }
      self.clearInteractiveBack()
      self.scheduleNavigationPreview()
    }
  }

  /// 只释放当前交互覆盖，不销毁其他路由的有限预览。
  private func clearInteractiveBack() {
    edgeBackTimeout?.invalidate()
    edgeBackTimeout = nil
    edgeBackTransition?.remove()
    edgeBackTransition = nil
    edgeBackIdentity = nil
    edgeBackTarget = nil
    edgeBackAnimationFinished = false
    edgeBackPaintPending = false
  }

  /// 协商期间只在静态启动页后装载正文，未确认原生布局前不暴露完整网页。
  func prepareDocumentHost() {
    clearNavigationPreviews()
    clearNativeConfirmation()
    loadViewIfNeeded()
    setLoading(true)
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
    if let identity = edgeBackIdentity, edgeBackTarget != snapshot.route.fullPath,
      coordinator.backGestureIdentity(sheetID: identity.sheetID) != identity
    {
      clearInteractiveBack()
    }
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
    fulfillUserMenu()
    view.layoutIfNeeded()
    synchronizeWebSheet(snapshot)
    synchronizeNativePanel(snapshot)
    synchronizeNativeConfirmation()
    keepStartupInFront()
    if let overlay = edgeBackTransition?.overlay { view.bringSubviewToFront(overlay) }
    finishInteractiveBackIfReady()
    scheduleNavigationPreview()
  }

  /// 返回当前最终宿主的 point 几何，正文和菜单锚点使用同一坐标原点。
  func layoutPayload(revision: Int, keyboard: CGRect?) -> JSONValue {
    let sheetOwnsContent = webSheet?.contentHost === coordinator.content.parent
    let host =
      (sheetOwnsContent ? webSheet?.contentHost : nil)
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
      "consumedByNativeFrame": .bool(sheetOwnsContent),
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
    prepareDocumentHost()
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
      primaryAction: UIAction { [weak self] _ in self?.coordinator.reload() })
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
    activeContainer?.view.accessibilityElementsHidden = true
    bottomNavigation.accessibilityElementsHidden = true
    view.accessibilityElements = [panel]
    UIAccessibility.post(notification: .screenChanged, argument: title)
  }

  /// 当前快照决定正文宿主，未就绪时只使用启动页后的文档暂存容器。
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
    AccountAppearance.remember(
      snapshot.chrome, for: coordinator.instance.id, traits: traitCollection)
    setNeedsStatusBarAppearanceUpdate()
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
    let identity = ObjectIdentifier(host)
    // Sheet 自己承载关闭；页面返回状态在系统动画开始前不能因网页弹层先闪出一个箭头。
    let canGoBack =
      snapshot.presentation?.sheet == nil
      ? snapshot.route.canGoBack
      : (headerConfigurations[identity]?.canGoBack ?? snapshot.route.canGoBack)
    let configuration = NativeHeaderConfiguration(
      session: coordinator.navigationPreviewSession,
      title: snapshot.route.title, canGoBack: canGoBack,
      tabs: snapshot.headerTabs, actions: trailing,
      overlayOpen: snapshot.presentation?.overlayOpen == true)
    guard headerConfigurations[identity] != configuration else {
      configureBottomBar(host, snapshot: snapshot)
      return
    }
    headerConfigurations[identity] = configuration
    // UIViewController.title 会连带修改导航容器的 Tab 名称，详情标题只属于顶部栏。
    host.navigationItem.title = snapshot.route.title
    host.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    host.navigationItem.leftBarButtonItems =
      canGoBack
      ? [
        UIBarButtonItem(
          image: UIImage(systemName: "chevron.backward"),
          primaryAction: UIAction(title: "返回") { [weak self] _ in
            self?.coordinator.command(
              "navigation.back", payload: .object(["source": .string("button")]))
          })
      ] : nil
    host.navigationItem.leftBarButtonItems?.first?.accessibilityLabel = "返回"
    let previousMenu = host.navigationItem.rightBarButtonItems?.first
    let menu = connectionItem(
      overflow: trailing, enabled: snapshot.presentation?.overlayOpen != true, reusing: previousMenu
    )
    if menu !== previousMenu { host.navigationItem.rightBarButtonItems = [menu] }
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

  /// 系统 Sheet 直接覆盖底栏，保持底页 viewport 稳定；旧网页全屏弹层仍释放占位。
  private func configureBottomBar(_ host: ContentHostController, snapshot: NavigationSnapshot) {
    host.toolbarItems = nil
    host.navigationController?.setToolbarHidden(true, animated: false)
    let systemSheet = snapshot.presentation?.sheet != nil || webSheet != nil
    let visible =
      snapshot.chrome.bottomVisible && (systemSheet || snapshot.presentation?.fullscreen != true)
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
  private func connectionItem(
    overflow: [ActionSnapshot] = [], enabled: Bool = true, reusing item: UIBarButtonItem? = nil
  )
    -> UIBarButtonItem
  {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "ellipsis")
    let existing = item?.customView as? NativeMenuButton
    let button = existing ?? NativeMenuButton(configuration: configuration)
    button.accessibilityLabel = "操作菜单"
    button.accessibilityIdentifier = "native-top-actions"
    button.isEnabled = enabled
    if existing == nil {
      button.onMenuClose = { [weak self] in self?.closeUserMenu() }
      button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
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
      if action.actionId.hasSuffix(":global:profile"), action.panel != nil,
        action.enabled, !action.loading
      {
        return userSubmenu(action)
      }
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
            to: navigation.presentationController, style: self.modalInterfaceStyle)
          navigation.sheetPresentationController?.detents = [.medium(), .large()]
          navigation.sheetPresentationController?.prefersGrabberVisible = true
          self.present(navigation, animated: true)
        }
      ]
        + (coordinator.widgetsAvailable
          ? [
            UIAction(title: "小组件", image: UIImage(systemName: "square.grid.2x2")) { [weak self] _ in
              guard let self, self.coordinator.widgetsAvailable else { return }
              let settings = WidgetController(coordinator: self.coordinator)
              let navigation = UINavigationController(rootViewController: settings)
              navigation.overrideUserInterfaceStyle = self.overrideUserInterfaceStyle
              navigation.view.tintColor = self.view.tintColor
              NativeModalAppearance.apply(
                to: navigation.presentationController, style: self.modalInterfaceStyle)
              navigation.sheetPresentationController?.detents = [.medium(), .large()]
              navigation.sheetPresentationController?.prefersGrabberVisible = true
              self.present(navigation, animated: true)
            }
          ] : []) + [
          UIAction(title: "重新加载", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            self?.coordinator.reload()
          },
          UIAction(title: "更改服务地址", image: UIImage(systemName: "server.rack")) { [weak self] _ in
            self?.onConnection()
          },
        ])
    let user = globals.filter { $0.actionId.hasSuffix(":global:profile") }
    let common = globals.filter { !$0.actionId.hasSuffix(":global:profile") }
    var groups = [
      UIMenu(
        title: "常用入口", options: .displayInline,
        children: common.map(menuElement) + [connection] + user.map(menuElement))
    ]
    if !pages.isEmpty {
      groups.append(
        UIMenu(title: "当前页面", options: .displayInline, children: pages.map(menuElement)))
    }
    let menu = UIMenu(children: groups)
    button.apply(menu: menu)
    button.showsMenuAsPrimaryAction = true
    // 异步用户资格或状态更新只能更新菜单，不能换掉正在承载二级菜单的系统按钮。
    let item = item ?? UIBarButtonItem(customView: button)
    // UIBarButtonItem 会同步自定义按钮的启用状态，两层保持一致，避免安装时重新启用。
    item.isEnabled = enabled
    return item
  }

  /// 整个用户子菜单延迟到完整投影后再交给 UIKit，避免展开后仍沿用占位元素的高度。
  private func userSubmenu(_ action: ActionSnapshot) -> UIMenuElement {
    let document = coordinator.navigationPreviewSession
    let image = action.panel?.profile?.image
    let context = "\(document ?? "")|\(action.ownerId)|\(image ?? "")"
    if userMenuAvatarContext != context {
      userMenuAvatar?.stop()
      userMenuAvatarContext = context
      userMenuAvatar = NativeUserMenuAvatar(
        images: NativePanelImageLoader(
          store: coordinator.webView.configuration.websiteDataStore,
          origin: coordinator.instance.address.origin), reference: image)
    }
    return UIDeferredMenuElement.uncached { [weak self] completion in
      guard let self, self.nativeVisible, let document,
        self.coordinator.navigationPreviewSession == document,
        let current = self.latest?.actions.first(where: {
          $0.actionId == action.actionId && $0.ownerId == action.ownerId && $0.enabled
            && !$0.loading
        }), current.panel != nil
      else {
        completion([])
        return
      }
      self.requestUserMenu(current, document: document, completion: completion)
    }
  }

  /// 未打开的面板只有摘要，先通知原网页打开，再等它发送包含最新权限项目的快照。
  private func requestUserMenu(
    _ action: ActionSnapshot, document: String,
    completion: @escaping ([UIMenuElement]) -> Void
  ) {
    userMenuRequest?.completion([])
    userMenuTimeout?.invalidate()
    let request = NativeUserMenuRequest(
      token: UUID(), document: document, action: action, completion: completion)
    userMenuRequest = request
    userMenuAction = action
    let token = request.token
    userMenuTimeout = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard self?.userMenuRequest?.token == token else { return }
        self?.closeUserMenu()
      }
    }
    coordinator.invoke(action, panelEvent: "open")
    fulfillUserMenu()
  }

  /// UIKit 在首次完整面板到达后才显示二级菜单，不把桥接前的空摘要当作可用内容。
  private func fulfillUserMenu() {
    guard let request = userMenuRequest else { return }
    guard coordinator.navigationPreviewSession == request.document,
      let current = latest?.actions.first(where: {
        $0.actionId == request.action.actionId && $0.ownerId == request.action.ownerId && $0.enabled
          && !$0.loading
      }), let panel = current.panel
    else {
      closeUserMenu()
      return
    }
    guard !panel.sections.isEmpty else { return }
    userMenuRequest = nil
    userMenuTimeout?.invalidate()
    userMenuTimeout = nil
    let document = request.document
    let action = request.action
    request.completion(
      [
        NativeUserMenu.menu(
          title: current.title, snapshot: panel, avatar: userMenuAvatar?.image,
          fallbackImage: symbol(current.icon)
        ) { [weak self] id in
          guard let self, self.coordinator.navigationPreviewSession == document,
            let current = self.latest?.actions.first(where: {
              $0.actionId == action.actionId && $0.ownerId == action.ownerId
                && $0.enabled
            })
          else { return }
          // 网页会在选择后释放本次面板；菜单关闭回调不能抢先撤销尚待执行的选择。
          self.userMenuAction = nil
          self.coordinator.invoke(current, panelEvent: "select", itemId: id)
        }
      ])
  }

  /// 被动关闭、超时和会话释放都完成待处理回调，并归还网页原有面板状态。
  private func closeUserMenu() {
    let request = userMenuRequest
    let action = userMenuAction
    userMenuRequest = nil
    userMenuAction = nil
    userMenuTimeout?.invalidate()
    userMenuTimeout = nil
    request?.completion([])
    if let action { coordinator.invoke(action, panelEvent: "close") }
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
    var groups: [[ActionMenuItem]] = []
    for item in items {
      if let last = groups.last, last.first?.group == item.group {
        groups[groups.count - 1].append(item)
      } else {
        groups.append([item])
      }
    }
    let children = groups.flatMap { group -> [UIMenuElement] in
      let actions: [UIMenuElement] = group.map { item in
        UIAction(
          title: item.title, image: symbol(item.icon), attributes: item.enabled ? [] : [.disabled],
          state: item.selected == true ? .on : .off
        ) { [weak self] _ in
          self?.coordinator.invoke(parent, menuActionId: item.actionId)
        }
      }
      return group.first?.group == nil
        ? actions : [UIMenu(options: .displayInline, children: actions)]
    }
    return UIMenu(children: children)
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
      if sheetAttachedID != descriptor.id {
        // 同一系统 Sheet 切回父弹窗时，旧子窗的透明退出截图不能叠在新的 HTML 内容上。
        sheetExitPlaceholder?.removeFromSuperview()
        sheetExitPlaceholder = nil
      }
      sheetNavigation?.overrideUserInterfaceStyle = overrideUserInterfaceStyle
      controller.apply(descriptor, style: modalInterfaceStyle)
      if sheetAttachedID != descriptor.id {
        attachWebSheet(descriptor, controller: controller)
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

  /// 保留窗口中已经显示的底页，避免异步 WebKit 快照漏掉合成层；不将快照用作材质。
  private func preserveWebSheetPage(_ descriptor: NativeSheetSnapshot) {
    let token = UUID()
    sheetSnapshotToken = token
    preparingSheetID = descriptor.id
    if latest?.chrome.content == .menu {
      finishWebSheetPreparation(id: descriptor.id, token: token, page: nil)
      return
    }
    let page = selectedHost.view.snapshotView(afterScreenUpdates: false)
    finishWebSheetPreparation(id: descriptor.id, token: token, page: page)
  }

  /// 只接收仍属当前弹窗的准备结果，底页只驻留内存，关闭或降级后立即释放。
  private func finishWebSheetPreparation(id: String, token: UUID, page: UIView?) {
    guard sheetSnapshotToken == token, preparingSheetID == id,
      let descriptor = latest?.presentation?.sheet, descriptor.id == id,
      descriptor.backdropReady == true, nativeVisible, presentedViewController == nil
    else { return }
    sheetSnapshotToken = nil
    preparingSheetID = nil
    if let page {
      page.frame = selectedHost.view.bounds
      page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      page.accessibilityElementsHidden = true
      page.isUserInteractionEnabled = false
      page.overrideUserInterfaceStyle = modalInterfaceStyle
      selectedHost.view.addSubview(page)
      sheetPagePlaceholder = page
    }
    presentWebSheet(descriptor)
  }

  /// 标题、关闭按钮、背景和转场来自系统 Sheet，同一 Vue 文档继续持有原表单。
  private func presentWebSheet(_ descriptor: NativeSheetSnapshot) {
    guard presentedViewController == nil, webSheet == nil, nativeVisible,
      let container = activeContainer
    else { return }
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
    controller.loadViewIfNeeded()
    navigation.loadViewIfNeeded()
    installBackGesture(on: navigation.view)
    navigation.view.frame = view.bounds
    // WKWebView 必须留在窗口中才能完成 rAF；底页占位覆盖准备内容，确认后再交给系统呈现。
    addChild(navigation)
    view.insertSubview(navigation.view, belowSubview: container.view)
    navigation.didMove(toParent: self)
    controller.contentHost.attach(coordinator.content)
    coordinator.content.view.isHidden = false
    coordinator.content.view.backgroundColor = .clear
    coordinator.webView.isOpaque = false
    coordinator.webView.backgroundColor = .clear
    coordinator.webView.underPageBackgroundColor = .clear
    coordinator.webView.scrollView.backgroundColor = .clear
    controller.apply(descriptor, style: modalInterfaceStyle)
    navigation.presentationController?.delegate = controller
    navigation.view.layoutIfNeeded()
    attachWebSheet(descriptor, controller: controller)
  }

  /// 网页标题和容器布局完成绘制后才开始系统动画，嵌套切换会撤销旧层的呈现回调。
  private func attachWebSheet(
    _ descriptor: NativeSheetSnapshot, controller: NativeWebSheetController
  ) {
    sheetAttachedID = descriptor.id
    coordinator.layoutChanged()
    coordinator.command(
      "presentation.attach", payload: .object(["id": .string(descriptor.id)])
    ) { [weak self, weak controller] accepted in
      guard let self, let controller, self.webSheet === controller,
        self.sheetAttachedID == descriptor.id, !self.sheetDismissing
      else { return }
      guard accepted else {
        self.coordinator.recoverNavigation()
        return
      }
      guard let navigation = self.sheetNavigation, navigation.presentingViewController == nil,
        self.presentedViewController == nil, self.nativeVisible,
        self.latest?.presentation?.sheet?.id == descriptor.id
      else { return }
      self.removeSheetStaging(navigation)
      self.present(navigation, animated: true) { [weak self] in
        self?.coordinator.layoutChanged()
        self?.synchronizeNativeConfirmation()
      }
    }
  }

  /// 将预备阶段的可绘制子控制器交还 UIKit，取消准备时也必须移除其视图与父引用。
  private func removeSheetStaging(_ navigation: UINavigationController) {
    guard navigation.parent === self else { return }
    navigation.willMove(toParent: nil)
    navigation.view.removeFromSuperview()
    navigation.removeFromParent()
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
    if type == "presentation.dismiss" { preserveWebSheetExit() }
    coordinator.command(type, payload: .object(payload))
  }

  /// 退出动画保留最后一帧表单，唯一 WebView 可先在其后还原底页，不将快照用作材质。
  private func preserveWebSheetExit() {
    guard sheetExitPlaceholder == nil, !sheetDismissing,
      let host = webSheet?.contentHost.view,
      let placeholder = host.snapshotView(afterScreenUpdates: false)
    else { return }
    placeholder.frame = host.bounds
    placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    placeholder.isUserInteractionEnabled = false
    placeholder.accessibilityElementsHidden = true
    host.addSubview(placeholder)
    sheetExitPlaceholder = placeholder
    Task { [weak self, weak placeholder] in
      try? await Task.sleep(for: .seconds(2))
      guard let self, let placeholder, self.sheetExitPlaceholder === placeholder,
        !self.sheetDismissing
      else { return }
      // 业务拒绝关闭时恢复实时表单，不能让临时动画帧挡住后续输入。
      placeholder.removeFromSuperview()
      self.sheetExitPlaceholder = nil
    }
  }

  /// Vue 确认关闭后先归位并绘制底页，再退出系统动画，避免露出旧主题或空白页面。
  private func dismissWebSheet(animated: Bool = true) {
    preparingSheetID = nil
    sheetSnapshotToken = nil
    guard let navigation = sheetNavigation, !sheetDismissing || !nativeVisible else {
      if sheetNavigation == nil, !nativeVisible {
        sheetRestoreToken = nil
        sheetDismissing = false
        sheetPagePlaceholder?.removeFromSuperview()
        sheetPagePlaceholder = nil
      }
      return
    }
    preserveWebSheetExit()
    sheetDismissing = true
    let token = UUID()
    sheetRestoreToken = token
    let id = sheetAttachedID
    let dismiss = { [weak self] in
      guard let self, self.sheetRestoreToken == token else { return }
      self.removeSheetStaging(navigation)
      self.sheetPagePlaceholder?.removeFromSuperview()
      self.sheetPagePlaceholder = nil
      let finish = { [weak self] in
        guard let self, self.sheetRestoreToken == token else { return }
        self.finishWebSheetDismissal()
      }
      if navigation.presentingViewController != nil {
        navigation.dismiss(animated: animated, completion: finish)
      } else {
        finish()
      }
    }
    let host = nativeVisible ? selectedHost : compatibilityHost
    host.attach(coordinator.content)
    if let placeholder = sheetPagePlaceholder { host.view.bringSubviewToFront(placeholder) }
    let background = NavigationSymbols.color(latest?.chrome.backgroundColor) ?? .systemBackground
    coordinator.content.view.backgroundColor = background
    coordinator.webView.isOpaque = true
    coordinator.webView.backgroundColor = background
    coordinator.webView.underPageBackgroundColor = background
    coordinator.webView.scrollView.backgroundColor = background
    host.view.layoutIfNeeded()
    coordinator.layoutChanged()
    if let id, nativeVisible {
      coordinator.command(
        "presentation.detach", payload: .object(["id": .string(id)])
      ) { [weak self] accepted in
        guard let self, self.sheetRestoreToken == token else { return }
        if accepted { dismiss() } else { self.coordinator.recoverNavigation() }
      }
    } else {
      dismiss()
    }
  }

  /// 底页已在原 viewport 完成绘制后才揭开占位，不触发网页刷新或重新加载。
  private func finishWebSheetDismissal() {
    sheetRestoreToken = nil
    sheetDismissing = false
    webSheet = nil
    sheetNavigation = nil
    sheetAttachedID = nil
    sheetExitPlaceholder?.removeFromSuperview()
    sheetExitPlaceholder = nil
    sheetPagePlaceholder?.removeFromSuperview()
    sheetPagePlaceholder = nil
    if nativeVisible, let latest { apply(latest) }
    coordinator.layoutChanged()
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
    navigation.modalPresentationStyle = snapshot.layout == .grid ? .pageSheet : .popover
    if snapshot.layout == .grid, let sheet = navigation.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.selectedDetentIdentifier = .medium
      sheet.prefersGrabberVisible = true
      sheet.prefersScrollingExpandsWhenScrolledToEdge = true
    }
    controller.loadViewIfNeeded()
    navigation.preferredContentSize = CGSize(
      width: controller.preferredPanelWidth(maximum: controller.maximumPanelWidth(in: view)),
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
      to: navigation.presentationController, style: modalInterfaceStyle)
    panelNavigation = navigation
    present(navigation, animated: true)
    coordinator.invoke(action, panelEvent: "open")
    synchronizeNativePanel(latest)
  }

  /// 确认使用系统 alert；已有 HTML Sheet 保留唯一 WebView，在其上呈现而不重新搬运网页。
  private func synchronizeNativeConfirmation() {
    guard nativeVisible, let descriptor = latest?.presentation?.confirmation else {
      clearNativeConfirmation()
      return
    }
    if answeringConfirmationID == descriptor.id { return }
    if let alert = confirmationAlert {
      if confirmationSnapshot?.id == descriptor.id {
        alert.title = descriptor.title
        alert.message = descriptor.message
        alert.actions.first?.isEnabled = descriptor.cancelEnabled
        alert.actions.last?.isEnabled = descriptor.confirmEnabled
        confirmationSnapshot = descriptor
      } else {
        clearNativeConfirmation { [weak self] in self?.synchronizeNativeConfirmation() }
      }
      return
    }
    if panelNavigation != nil {
      dismissNativePanel(notify: false) { [weak self] in self?.synchronizeNativeConfirmation() }
      return
    }
    guard !sheetDismissing, let documentSession = coordinator.navigationPreviewSession else {
      return
    }
    let presenter: UIViewController
    if let navigation = sheetNavigation {
      guard navigation.presentingViewController != nil,
        navigation.presentedViewController == nil, !navigation.isBeingPresented
      else { return }
      presenter = navigation
    } else {
      guard presentedViewController == nil else { return }
      presenter = self
    }
    let alert = UIAlertController(
      title: descriptor.title, message: descriptor.message, preferredStyle: .alert)
    alert.overrideUserInterfaceStyle = modalInterfaceStyle
    alert.view.accessibilityIdentifier = "native-confirmation"
    /// 系统按钮只回传当前确认 ID；原 DOM 按钮最终结算业务 Promise。
    func action(_ confirmed: Bool) -> UIAlertAction {
      let action = UIAlertAction(
        title: confirmed ? descriptor.confirmText : descriptor.cancelText,
        style: confirmed ? (descriptor.destructive ? .destructive : .default) : .cancel
      ) { [weak self, weak alert] _ in
        guard let self, self.confirmationAlert === alert,
          self.coordinator.navigationPreviewSession == documentSession,
          let current = self.latest?.presentation?.confirmation, current.id == descriptor.id,
          confirmed ? current.confirmEnabled : current.cancelEnabled
        else { return }
        self.answeringConfirmationID = descriptor.id
        self.coordinator.command(
          "confirmation.respond",
          payload: .object(["id": .string(descriptor.id), "confirmed": .bool(confirmed)])
        ) { [weak self] accepted in
          if !accepted { self?.coordinator.recoverNavigation() }
        }
      }
      action.isEnabled = confirmed ? descriptor.confirmEnabled : descriptor.cancelEnabled
      return action
    }
    alert.addAction(action(false))
    alert.addAction(action(true))
    confirmationAlert = alert
    confirmationSnapshot = descriptor
    answeringConfirmationID = nil
    presenter.present(alert, animated: true)
  }

  /// 文档释放、身份变化或 Vue 关闭后撤销系统表现；不会合成确认或重复取消业务。
  private func clearNativeConfirmation(completion: (() -> Void)? = nil) {
    let alert = confirmationAlert
    confirmationAlert = nil
    confirmationSnapshot = nil
    answeringConfirmationID = nil
    if let alert, alert.presentingViewController != nil {
      alert.dismiss(animated: false, completion: completion)
    } else {
      completion?()
    }
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
        to: navigation.presentationController, style: modalInterfaceStyle)
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
    navigation.dismiss(animated: true) { [weak self] in
      completion?()
      self?.synchronizeNativeConfirmation()
    }
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
      accent: NavigationSymbols.color(snapshot.chrome.accentColor) ?? AccountAppearance.accent)
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
