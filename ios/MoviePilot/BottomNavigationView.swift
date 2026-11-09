import Darwin
import MoviePilotCore
import UIKit

/// 单行底部框架：主入口与动态动作同高，底部安全区独立占位，隐藏动作只移动整组导航。
@MainActor
final class BottomNavigationView: UIView, UITabBarDelegate {
  static let height: CGFloat = 64
  private static let duoModelIdentifiers: Set<String> = ["iPhone19,4"]

  /// 只识别 Apple iPhone Duo 型号；其它 iPhone、iPad 和 Mac 保持原底部导航。
  static var isIPhoneDuo: Bool {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
    let model =
      ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
      ?? machineIdentifier()
    return duoModelIdentifiers.contains(model)
  }

  /// 读取真机硬件标识；模拟器优先使用 Xcode 注入的型号标识。
  private static func machineIdentifier() -> String {
    var size: size_t = 0
    guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var machine = [CChar](repeating: 0, count: Int(size))
    guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return "" }
    return String(
      decoding: machine.map { UInt8(bitPattern: $0) }.prefix { $0 != 0 }, as: UTF8.self)
  }

  /// 路由守卫取消时网页不发送失败信号，超过该时长未确认才撤销点击目标。
  private static let confirmationTimeout: TimeInterval = 2
  private let tabBar = UITabBar()
  private let capsuleNavigation: CapsuleNavigationView? = {
    // 独立 UITabBar 在 iPad 和旧系统中仅绘制 49pt 内容，拉高外框无法改变可见栏体。
    if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom != .pad { return nil }
    return CapsuleNavigationView()
  }()
  private let group = UIView()
  private let navigationHost = UIView()
  private let actionHost = UIView()
  private var rootIds: [String] = []
  private var selectedRoot: String?
  private var pendingRoot: String?
  private var pendingTimeout: Timer?
  private var onSelect: ((String, @escaping (Bool) -> Void) -> Void)?
  private var actionWidth: NSLayoutConstraint!
  private var actionHeight: NSLayoutConstraint!
  private var actionSpacing: NSLayoutConstraint!
  private var navigationWidth: NSLayoutConstraint!

  /// 当前设备使用的入口控件；普通 iOS 26+ iPhone 保留原有系统 Tab Bar。
  private var rootNavigation: UIView { capsuleNavigation ?? tabBar }

  /// 固定主入口和动作的空间关系，材质与按钮反馈仍使用公开 UIKit 控件。
  init() {
    super.init(frame: .zero)
    accessibilityIdentifier = "native-bottom-navigation"
    rootNavigation.accessibilityIdentifier = "native-root-navigation"
    tabBar.delegate = self
    tabBar.itemPositioning = .fill
    rootNavigation.translatesAutoresizingMaskIntoConstraints = false
    navigationHost.translatesAutoresizingMaskIntoConstraints = false
    actionHost.translatesAutoresizingMaskIntoConstraints = false
    group.translatesAutoresizingMaskIntoConstraints = false
    addSubview(group)
    group.addSubview(navigationHost)
    navigationHost.addSubview(rootNavigation)
    group.addSubview(actionHost)
    navigationWidth = navigationHost.widthAnchor.constraint(equalToConstant: 294)
    actionWidth = actionHost.widthAnchor.constraint(equalToConstant: Self.height)
    actionHeight = actionHost.heightAnchor.constraint(equalToConstant: Self.height)
    actionSpacing = navigationHost.trailingAnchor.constraint(
      equalTo: actionHost.leadingAnchor, constant: -12)
    // 浮动 Tab Bar 自带水平透明留白；允许其在宿主两侧延伸，避免与框架边距重复挤压入口。
    let overflow: CGFloat = capsuleNavigation == nil ? 16 : 0
    NSLayoutConstraint.activate([
      group.centerXAnchor.constraint(equalTo: centerXAnchor),
      group.topAnchor.constraint(equalTo: topAnchor),
      group.bottomAnchor.constraint(equalTo: bottomAnchor),
      navigationHost.leadingAnchor.constraint(equalTo: group.leadingAnchor),
      navigationHost.topAnchor.constraint(equalTo: group.topAnchor),
      navigationHost.bottomAnchor.constraint(equalTo: group.bottomAnchor),
      rootNavigation.leadingAnchor.constraint(
        equalTo: navigationHost.leadingAnchor, constant: -overflow),
      rootNavigation.trailingAnchor.constraint(
        equalTo: navigationHost.trailingAnchor, constant: overflow),
      rootNavigation.topAnchor.constraint(equalTo: navigationHost.topAnchor),
      navigationWidth,
      actionSpacing,
      actionHost.trailingAnchor.constraint(equalTo: group.trailingAnchor),
      // 原生栏的总高度包含底部留白；独立动作对齐上方导航内容，不对齐整个栏的中心。
      actionHost.topAnchor.constraint(equalTo: rootNavigation.topAnchor),
      actionHeight,
      actionWidth,
    ])
    if capsuleNavigation != nil {
      rootNavigation.heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    } else {
      rootNavigation.bottomAnchor.constraint(equalTo: navigationHost.bottomAnchor).isActive = true
    }
  }

  /// 底栏由当前实例会话创建，不支持 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 总高度采用 UIKit 的实际量测，避免把按钮高度与 Home Indicator 区域重复计入。
  override var intrinsicContentSize: CGSize {
    if capsuleNavigation != nil {
      // Home 键机型和窄窗口可能没有底部安全区，仍为浮动胶囊留出最小边距。
      return CGSize(
        width: UIView.noIntrinsicMetric, height: Self.height + max(8, safeAreaInsets.bottom))
    }
    let measured = tabBar.sizeThatFits(
      CGSize(width: max(0, bounds.width), height: CGFloat.greatestFiniteMagnitude)
    ).height
    return CGSize(width: UIView.noIntrinsicMetric, height: measured)
  }

  /// 入窗或旋转会改变系统栏的安全区和推荐高度，重新交给 Auto Layout 量测。
  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    invalidateIntrinsicContentSize()
  }

  /// 总是按“有动态动作”的可用宽度计算一次按钮间距；隐藏动作不能触发主入口重新分配。
  override func layoutSubviews() {
    actionHeight.constant = min(Self.height, intrinsicContentSize.height)
    let count = CGFloat(max(1, rootIds.count))
    let maximum = max(0, bounds.width - Self.height - 12)
    // iPad 的独立底栏有足够空间容纳完整文案，窄窗口仍由实际可用宽度限制。
    let itemWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 100 : 72
    let width = min(maximum, count * itemWidth + 8)
    if abs(navigationWidth.constant - width) > 0.5 { navigationWidth.constant = width }
    super.layoutSubviews()
  }

  /// 选中项以快照确认的入口为准；动作控件使用与顶栏相同的 JS 回调和菜单声明。
  func apply(
    _ snapshot: NavigationSnapshot, action: UIButton?,
    onSelect: @escaping (String, @escaping (Bool) -> Void) -> Void
  ) {
    self.onSelect = onSelect
    // 已确认入口变化即结束等待；守卫重定向到其他入口时同样以快照为准。
    if snapshot.route.rootId != selectedRoot { clearPendingRoot() }
    selectedRoot = snapshot.route.rootId
    let ids = snapshot.roots.map(\.id)
    if ids != rootIds {
      clearPendingRoot()
      rootIds = ids
      if capsuleNavigation == nil {
        tabBar.items = snapshot.roots.enumerated().map { index, root in
          let image = NavigationSymbols.image(
            root.icon, configuration: NavigationSymbols.bottomConfiguration)
          let item = UITabBarItem(title: root.title, image: image, tag: index)
          item.accessibilityIdentifier = "native-root-\(root.id)"
          return item
        }
      }
    }
    let overlayOpen = snapshot.presentation?.overlayOpen == true
    capsuleNavigation?.apply(snapshot.roots, enabled: !overlayOpen) { [weak self] index in
      self?.selectRoot(at: index)
    }
    for (index, item) in (tabBar.items ?? []).enumerated() {
      item.title = snapshot.roots[index].title
      let root = snapshot.roots[index]
      item.image = NavigationSymbols.image(
        root.icon, configuration: NavigationSymbols.bottomConfiguration)
      item.isEnabled = !overlayOpen
    }
    synchronizeSelection()
    rootNavigation.isUserInteractionEnabled = !overlayOpen
    rootNavigation.accessibilityElementsHidden = overlayOpen
    for view in actionHost.subviews { view.removeFromSuperview() }
    actionHost.isHidden = action == nil
    actionWidth.constant = action == nil ? 0 : Self.height
    actionSpacing.constant = action == nil ? 0 : -12
    if let action {
      action.accessibilityIdentifier = "native-bottom-action"
      action.translatesAutoresizingMaskIntoConstraints = false
      actionHost.addSubview(action)
      NSLayoutConstraint.activate([
        action.leadingAnchor.constraint(equalTo: actionHost.leadingAnchor),
        action.trailingAnchor.constraint(equalTo: actionHost.trailingAnchor),
        action.topAnchor.constraint(equalTo: actionHost.topAnchor),
        action.bottomAnchor.constraint(equalTo: actionHost.bottomAnchor),
      ])
    }
  }

  /// 系统滑块在回调前已开始移动，这里只发起路由意图并保留点击目标，避免改回旧值造成往返。
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    selectRoot(at: item.tag)
  }

  /// 两种原生入口共享路由确认与超时撤销，不能让拒绝或迟到的网页回调留下错误选中态。
  private func selectRoot(at index: Int) {
    guard rootIds.indices.contains(index) else { return }
    let requested = rootIds[index]
    clearPendingRoot()
    if requested != selectedRoot {
      pendingRoot = requested
      pendingTimeout = Timer.scheduledTimer(
        withTimeInterval: Self.confirmationTimeout, repeats: false
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.cancelPendingRoot(requested) }
      }
    }
    if capsuleNavigation != nil { synchronizeSelection() }
    onSelect?(requested) { [weak self] accepted in
      if !accepted { self?.cancelPendingRoot(requested) }
    }
  }

  /// 等待确认时显示点击目标；目标未变不赋值，避免干扰进行中的滑块动画。
  private func synchronizeSelection() {
    let displayed = pendingRoot ?? selectedRoot
    if let capsuleNavigation {
      capsuleNavigation.select(rootId: displayed)
      return
    }
    let target = tabBar.items?.first {
      rootIds.indices.contains($0.tag) && rootIds[$0.tag] == displayed
    }
    if tabBar.selectedItem !== target { tabBar.selectedItem = target }
  }

  /// 导航被拒绝或长时间未确认时撤销对应点击，后续点击不受迟到结果影响。
  private func cancelPendingRoot(_ rootId: String) {
    guard pendingRoot == rootId else { return }
    clearPendingRoot()
    synchronizeSelection()
  }

  /// 结束当前等待；选中项由调用方按确认状态同步。
  private func clearPendingRoot() {
    pendingTimeout?.invalidate()
    pendingTimeout = nil
    pendingRoot = nil
  }
}

/// iPad 与 iOS 16–25 的原生胶囊入口，64pt 可见材质不包含 Home Indicator 留白。
@MainActor
private final class CapsuleNavigationView: UIView {
  private let stack = UIStackView()
  private var rootIds: [String] = []
  private var buttons: [UIButton] = []
  private var onSelect: ((Int) -> Void)?

  /// 材质铺满栏体，按钮上下各内缩 4pt；主导航按语义分组，选中状态由 UIButton 提供。
  init() {
    super.init(frame: .zero)
    isAccessibilityElement = false
    accessibilityContainerType = .semanticGroup
    accessibilityLabel = "主导航"
    let effect: UIVisualEffect
    if #available(iOS 26, *) {
      effect = UIGlassEffect(style: .regular)
    } else {
      // 旧系统使用超薄材质，保留底页壁纸的颜色和明暗变化。
      effect = UIBlurEffect(style: .systemUltraThinMaterial)
    }
    let material = UIVisualEffectView(effect: effect)
    if #available(iOS 26, *) { material.cornerConfiguration = .capsule() }
    material.layer.cornerRadius = BottomNavigationView.height / 2
    material.clipsToBounds = true
    material.isUserInteractionEnabled = false
    material.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(material)
    addSubview(stack)
    NSLayoutConstraint.activate([
      material.leadingAnchor.constraint(equalTo: leadingAnchor),
      material.trailingAnchor.constraint(equalTo: trailingAnchor),
      material.topAnchor.constraint(equalTo: topAnchor),
      material.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
    ])
  }

  /// 此控件由底栏创建，不接收 storyboard 状态。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 只投影网页授权的入口；按钮使用原 SF Symbol、完整标题与相同路由回调。
  func apply(_ roots: [RootSnapshot], enabled: Bool, onSelect: @escaping (Int) -> Void) {
    self.onSelect = onSelect
    let ids = roots.map(\.id)
    if ids != rootIds {
      for button in buttons { button.removeFromSuperview() }
      rootIds = ids
      buttons = roots.indices.map { index in
        let button = UIButton(configuration: .plain())
        button.accessibilityIdentifier = "native-root-\(roots[index].id)"
        // 每个入口只暴露一个按钮，避免配置标题再次被系统提升成嵌套标签按钮。
        button.isAccessibilityElement = true
        button.accessibilityElements = []
        button.isPointerInteractionEnabled = true
        button.configurationUpdateHandler = { button in
          var configuration = button.configuration
          configuration?.baseForegroundColor = button.isSelected ? button.tintColor : .label
          configuration?.background.backgroundColor =
            button.isSelected ? .tertiarySystemFill : .clear
          button.configuration = configuration
        }
        button.addAction(
          UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
        stack.addArrangedSubview(button)
        return button
      }
      accessibilityElements = buttons
    }
    for (index, root) in roots.enumerated() {
      let button = buttons[index]
      var configuration = button.configuration ?? .plain()
      configuration.title = root.title
      configuration.image = NavigationSymbols.image(
        root.icon, configuration: NavigationSymbols.bottomConfiguration)
      configuration.imagePlacement = .top
      configuration.imagePadding = 2
      configuration.contentInsets = .zero
      configuration.cornerStyle = .capsule
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        incoming in
        var attributes = incoming
        attributes.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        return attributes
      }
      button.configuration = configuration
      button.titleLabel?.isAccessibilityElement = false
      button.imageView?.isAccessibilityElement = false
      button.accessibilityLabel = root.title
      button.isEnabled = enabled
    }
  }

  /// 选中状态只接受底栏的已确认或等待确认目标，UIButton 同步 VoiceOver 与系统反馈。
  func select(rootId: String?) {
    for (index, button) in buttons.enumerated() {
      button.isSelected = rootIds[index] == rootId
    }
  }
}
