import MoviePilotCore
import UIKit

/// 单行底部框架：系统 Tab Bar 保持固定按钮几何，动态动作只改变整组导航的位置。
@MainActor
final class BottomNavigationView: UIView, UITabBarDelegate {
  static let height: CGFloat = 64
  static let bottomSpacing: CGFloat = 8
  private let tabBar = UITabBar()
  private let group = UIView()
  private let navigationHost = UIView()
  private let actionHost = UIView()
  private var rootIds: [String] = []
  private var selectedRoot: String?
  private var onSelect: ((String) -> Void)?
  private var actionWidth: NSLayoutConstraint!
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
      // Tab Bar 包含系统底部区域，动态按钮与整个栏的垂直中心对齐，避免比主入口高一层。
      actionHost.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
      actionHost.heightAnchor.constraint(equalToConstant: Self.height),
      actionWidth,
    ])
  }

  /// 底栏由当前实例会话创建，不支持 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 总是按“有动态动作”的可用宽度计算一次按钮间距；隐藏动作不能触发主入口重新分配。
  override func layoutSubviews() {
    let count = CGFloat(max(1, rootIds.count))
    let maximum = max(0, bounds.width - Self.height - 12)
    let width = min(maximum, count * 72 + 8)
    if abs(navigationWidth.constant - width) > 0.5 { navigationWidth.constant = width }
    super.layoutSubviews()
  }

  /// 快照确认后才更新选中项；动作控件使用与顶栏相同的 JS 回调和菜单声明。
  func apply(
    _ snapshot: NavigationSnapshot, action: UIButton?, onSelect: @escaping (String) -> Void
  ) {
    self.onSelect = onSelect
    selectedRoot = snapshot.route.rootId
    let ids = snapshot.roots.map(\.id)
    if ids != rootIds {
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
    tabBar.selectedItem = tabBar.items?.first { item in
      rootIds.indices.contains(item.tag) && rootIds[item.tag] == selectedRoot
    }
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

  /// 点击只发起路由意图；立即保留已确认选择，权限守卫通过后的快照负责真正切换。
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard rootIds.indices.contains(item.tag) else { return }
    let requested = rootIds[item.tag]
    tabBar.selectedItem = tabBar.items?.first {
      rootIds.indices.contains($0.tag) && rootIds[$0.tag] == selectedRoot
    }
    onSelect?(requested)
  }
}
