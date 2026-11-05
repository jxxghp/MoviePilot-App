import MoviePilotCore
import UIKit

/// 单行底部框架：系统 Tab Bar 保持固定按钮几何，动态动作只改变整组导航的位置。
@MainActor
final class BottomNavigationView: UIView, UITabBarDelegate {
  static let height: CGFloat = 64
  /// 路由守卫取消时网页不发送失败信号，超过该时长未确认才撤销点击目标。
  private static let confirmationTimeout: TimeInterval = 2
  private let tabBar = UITabBar()
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

  /// 固定主入口和动作的空间关系，玻璃材质、选中反馈与无障碍语义交由 UIKit。
  init() {
    super.init(frame: .zero)
    accessibilityIdentifier = "native-bottom-navigation"
    tabBar.accessibilityIdentifier = "native-root-navigation"
    tabBar.delegate = self
    tabBar.itemPositioning = .fill
    tabBar.translatesAutoresizingMaskIntoConstraints = false
    navigationHost.translatesAutoresizingMaskIntoConstraints = false
    actionHost.translatesAutoresizingMaskIntoConstraints = false
    group.translatesAutoresizingMaskIntoConstraints = false
    addSubview(group)
    group.addSubview(navigationHost)
    navigationHost.addSubview(tabBar)
    group.addSubview(actionHost)
    navigationWidth = navigationHost.widthAnchor.constraint(equalToConstant: 294)
    actionWidth = actionHost.widthAnchor.constraint(equalToConstant: Self.height)
    actionHeight = actionHost.heightAnchor.constraint(equalToConstant: Self.height)
    actionSpacing = navigationHost.trailingAnchor.constraint(
      equalTo: actionHost.leadingAnchor, constant: -12)
    // 浮动 Tab Bar 自带水平透明留白；允许其在宿主两侧延伸，避免与框架边距重复挤压入口。
    let overflow: CGFloat = if #available(iOS 26, *) { 16 } else { 0 }
    NSLayoutConstraint.activate([
      group.centerXAnchor.constraint(equalTo: centerXAnchor),
      group.topAnchor.constraint(equalTo: topAnchor),
      group.bottomAnchor.constraint(equalTo: bottomAnchor),
      navigationHost.leadingAnchor.constraint(equalTo: group.leadingAnchor),
      navigationHost.topAnchor.constraint(equalTo: group.topAnchor),
      navigationHost.bottomAnchor.constraint(equalTo: group.bottomAnchor),
      tabBar.leadingAnchor.constraint(equalTo: navigationHost.leadingAnchor, constant: -overflow),
      tabBar.trailingAnchor.constraint(equalTo: navigationHost.trailingAnchor, constant: overflow),
      tabBar.topAnchor.constraint(equalTo: navigationHost.topAnchor),
      tabBar.bottomAnchor.constraint(equalTo: navigationHost.bottomAnchor),
      navigationWidth,
      actionSpacing,
      actionHost.trailingAnchor.constraint(equalTo: group.trailingAnchor),
      // 原生栏的总高度包含底部留白；独立动作对齐上方导航内容，不对齐整个栏的中心。
      actionHost.topAnchor.constraint(equalTo: tabBar.topAnchor),
      actionHeight,
      actionWidth,
    ])
  }

  /// 底栏由当前实例会话创建，不支持 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 总高度采用 UIKit 的实际量测，避免把按钮高度与 Home Indicator 区域重复计入。
  override var intrinsicContentSize: CGSize {
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
    let width = min(maximum, count * 72 + 8)
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
      tabBar.items = snapshot.roots.enumerated().map { index, root in
        let image = NavigationSymbols.image(
          root.icon, configuration: NavigationSymbols.bottomConfiguration)
        let item = UITabBarItem(title: root.title, image: image, tag: index)
        item.accessibilityIdentifier = "native-root-\(root.id)"
        return item
      }
    }
    let overlayOpen = snapshot.presentation?.overlayOpen == true
    for (index, item) in (tabBar.items ?? []).enumerated() {
      item.title = snapshot.roots[index].title
      let root = snapshot.roots[index]
      item.image = NavigationSymbols.image(
        root.icon, configuration: NavigationSymbols.bottomConfiguration)
      item.isEnabled = !overlayOpen
    }
    synchronizeSelection()
    tabBar.isUserInteractionEnabled = !overlayOpen
    tabBar.accessibilityElementsHidden = overlayOpen
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
    guard rootIds.indices.contains(item.tag) else { return }
    let requested = rootIds[item.tag]
    clearPendingRoot()
    if requested != selectedRoot {
      pendingRoot = requested
      pendingTimeout = Timer.scheduledTimer(
        withTimeInterval: Self.confirmationTimeout, repeats: false
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.cancelPendingRoot(requested) }
      }
    }
    onSelect?(requested) { [weak self] accepted in
      if !accepted { self?.cancelPendingRoot(requested) }
    }
  }

  /// 等待确认时显示点击目标；目标未变不赋值，避免干扰进行中的滑块动画。
  private func synchronizeSelection() {
    let displayed = pendingRoot ?? selectedRoot
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
