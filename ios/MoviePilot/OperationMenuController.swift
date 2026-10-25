import MoviePilotCore
import UIKit

/// 独立菜单与卡片辅助入口共用系统列表；操作、分组与子菜单全部沿用网页声明。
@MainActor
final class OperationMenuController: UITableViewController, UISheetPresentationControllerDelegate {
  /// 原生分组只描述表格布局，不保存或复制业务行为。
  private struct Section {
    var title: String?
    var rows: [(item: OperationMenuItem, enabled: Bool)] = []
  }

  private var snapshot: OperationMenuSnapshot
  private var path: [String] = []
  private var sections: [Section] = []
  private var ending = false
  private var selecting = false
  private var measuredHeight: CGFloat = 0
  private var dismissalCompletions: [() -> Void] = []
  private let choose: (OperationMenuSnapshot, String) -> Void
  private let cancel: (String) -> Void
  var accent: UIColor = .systemBlue

  /// 宿主负责当前文档校验；此控制器只传回展示与动作标识。
  init(
    menu: OperationMenuSnapshot, choose: @escaping (OperationMenuSnapshot, String) -> Void,
    cancel: @escaping (String) -> Void
  ) {
    snapshot = menu
    self.choose = choose
    self.cancel = cancel
    super.init(style: .insetGrouped)
  }

  /// 操作菜单不接受脱离网页会话的 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init(menu:choose:cancel:)") }

  /// 系统负责材质、字体、分隔条及关闭按钮，不增加网页卡片底色。
  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 54
    tableView.accessibilityIdentifier = "nativeOperationMenu"
    NativeModalAppearance.apply(to: self)
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.end() })
    navigationItem.rightBarButtonItem?.accessibilityIdentifier = "native-operation-menu-close"
    rebuild()
  }

  /// 字号、宽度和子菜单变化时重新量测，只保留一个最高 2/3 可用屏幕的 detent。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let height =
      tableView.contentSize.height + (navigationController?.navigationBar.frame.height ?? 44)
      + view.safeAreaInsets.bottom + 12
    guard abs(height - measuredHeight) > 1 else { return }
    measuredHeight = height
    navigationController?.sheetPresentationController?.invalidateDetents()
  }

  /// 短菜单贴合内容，长菜单在系统表格内滚动，禁止拖到全屏。
  func configureSheet(_ navigation: UINavigationController, presentingView: UIView) {
    navigation.modalPresentationStyle = .pageSheet
    navigation.view.accessibilityIdentifier = "native-operation-menu-sheet"
    guard let sheet = navigation.sheetPresentationController else { return }
    sheet.detents = [
      .custom(identifier: .init("operation-content")) { [weak self, weak presentingView] context in
        // UIKit 会在 detent 之外加底部安全区，先限制总高度再扣回这部分。
        let bottom =
          presentingView?.window?.safeAreaInsets.bottom ?? presentingView?.safeAreaInsets.bottom
          ?? 0
        let maximum = (context.maximumDetentValue + bottom) * 2 / 3
        return max(1, min(maximum, max(100, self?.measuredHeight ?? 240)) - bottom)
      }
    ]
    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    sheet.prefersEdgeAttachedInCompactHeight = true
    sheet.prefersGrabberVisible = true
    sheet.delegate = self
  }

  /// keepOpen 动作以新单次票据刷新，保留仍存在的子菜单路径。
  func refresh(_ menu: OperationMenuSnapshot) {
    snapshot = menu
    selecting = false
    tableView.isUserInteractionEnabled = true
    rebuild()
  }

  /// 文档、权限或来源失效时先禁止选择，再结束系统弹窗。
  func invalidate(completion: (() -> Void)? = nil) {
    if let completion { dismissalCompletions.append(completion) }
    end()
  }

  /// 手动下拉结束只撤销当前票据，不执行业务。
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard !ending else { return }
    ending = true
    finishDismissal { cancel(snapshot.presentationId) }
  }

  /// 表格按原菜单分组、分隔条和顺序呈现，不重排危险动作。
  override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

  /// 每层只展示当前菜单，子菜单通过原生返回按钮回到上一层。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    sections[section].rows.count
  }

  /// 无标题分组仍保留系统分隔空间。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    sections[section].title
  }

  /// 原标题、副标题、勾选、图标、禁用与危险语义均来自同一声明。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let record = sections[indexPath.section].rows[indexPath.row]
    let row = record.item
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    var content = cell.defaultContentConfiguration()
    content.text = row.title
    content.secondaryText = row.subtitle
    content.textProperties.numberOfLines = 0
    content.secondaryTextProperties.numberOfLines = 0
    content.image = NavigationSymbols.operationImage(row.icon)
    let enabled = record.enabled && !selecting
    let color: UIColor =
      row.destructive == true || row.color == .error
      ? .systemRed : row.color.map { NavigationSymbols.operationTint($0, accent: accent) } ?? .label
    content.textProperties.color = enabled ? color : .tertiaryLabel
    content.imageProperties.tintColor =
      enabled
      ? NavigationSymbols.operationTint(
        row.destructive == true ? .error : row.color, accent: accent)
      : .tertiaryLabel
    cell.contentConfiguration = content
    cell.accessoryType =
      row.kind == .submenu ? .disclosureIndicator : row.selected == true ? .checkmark : .none
    cell.accessoryView = statusAccessory(row, enabled: enabled)
    cell.accessibilityValue = row.badge?.title
    cell.selectionStyle = enabled ? .default : .none
    cell.isUserInteractionEnabled = enabled
    cell.accessibilityIdentifier = "operation-\(row.id)"
    if !enabled { cell.accessibilityTraits.insert(.notEnabled) }
    if row.selected == true { cell.accessibilityTraits.insert(.selected) }
    return cell
  }

  /// 状态徽标、加载和勾选/子菜单指示可同时存在，不让自定义徽标覆盖系统语义。
  private func statusAccessory(_ row: OperationMenuItem, enabled: Bool) -> UIView? {
    guard row.badge != nil || row.loading == true else { return nil }
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    if let badge = row.badge {
      let label = UILabel()
      label.text = badge.title
      label.font = .preferredFont(forTextStyle: .caption1)
      label.adjustsFontForContentSizeCategory = true
      label.textColor =
        enabled ? NavigationSymbols.operationTint(badge.color, accent: accent) : .tertiaryLabel
      label.numberOfLines = 0
      label.textAlignment = .right
      label.accessibilityIdentifier = "operation-badge-\(row.id)"
      let maximum = max(60, tableView.bounds.width / 3)
      label.preferredMaxLayoutWidth = maximum
      label.widthAnchor.constraint(lessThanOrEqualToConstant: maximum).isActive = true
      stack.addArrangedSubview(label)
    }
    if row.loading == true {
      let progress = UIActivityIndicatorView(style: .medium)
      progress.startAnimating()
      stack.addArrangedSubview(progress)
    }
    if row.kind == .submenu || row.selected == true {
      let icon = UIImageView(
        image: UIImage(systemName: row.kind == .submenu ? "chevron.right" : "checkmark"))
      icon.tintColor = enabled ? accent : .tertiaryLabel
      icon.contentMode = .scaleAspectFit
      icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
      icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
      stack.addArrangedSubview(icon)
    }
    stack.frame.size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    return stack
  }

  /// 正常动作等系统退出动画完成再回传；保留菜单动作等待网页的新票据。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard !ending, !selecting else { return }
    let record = sections[indexPath.section].rows[indexPath.row]
    let row = record.item
    guard record.enabled else { return }
    if row.kind == .submenu {
      path.append(row.id)
      rebuild()
    } else if snapshot.availableAction(id: row.id) != nil {
      selecting = true
      tableView.isUserInteractionEnabled = false
      if row.keepOpen == true {
        choose(snapshot, row.id)
      } else {
        ending = true
        let menu = snapshot
        navigationController?.dismiss(animated: true) { [weak self] in
          self?.finishDismissal { self?.choose(menu, row.id) }
        }
      }
    }
  }

  /// 分组展开仅影响原生表格，父层禁用状态已由完整菜单投影继承。
  private func rebuild() {
    var rows = snapshot.items
    var title = snapshot.title
    var validPath: [String] = []
    for id in path {
      guard let submenu = find(id, in: rows), submenu.kind == .submenu else { break }
      validPath.append(id)
      rows = submenu.items ?? []
      title = submenu.title
    }
    path = validPath
    navigationItem.title = title ?? "操作"
    navigationItem.leftBarButtonItem =
      path.isEmpty
      ? nil
      : UIBarButtonItem(
        image: UIImage(systemName: "chevron.left"), style: .plain,
        target: self, action: #selector(back))
    navigationItem.leftBarButtonItem?.accessibilityLabel = "返回上一级菜单"
    sections = [Section()]
    append(rows)
    sections.removeAll { $0.rows.isEmpty }
    tableView.reloadData()
    tableView.setNeedsLayout()
  }

  /// 分隔符和内联分组分别转为系统节，不丢失尾部动作或嵌套分组。
  private func append(_ rows: [OperationMenuItem], enabled: Bool = true) {
    for row in rows {
      if row.kind == .separator {
        if !sections[sections.count - 1].rows.isEmpty { sections.append(Section()) }
      } else if row.kind == .group {
        if !sections[sections.count - 1].rows.isEmpty { sections.append(Section()) }
        sections[sections.count - 1].title = row.title
        append(row.items ?? [], enabled: enabled && row.enabled != false && row.loading != true)
        sections.append(Section())
      } else {
        sections[sections.count - 1].rows.append(
          (row, enabled && row.enabled != false && row.loading != true))
      }
    }
  }

  /// 查找稳定的子菜单 ID，不通过可见行下标关联网页业务。
  private func find(_ id: String, in rows: [OperationMenuItem], enabled: Bool = true)
    -> OperationMenuItem?
  {
    for row in rows {
      let allowed = enabled && row.enabled != false && row.loading != true
      if row.id == id { return allowed ? row : nil }
      if row.kind == .group, let match = find(id, in: row.items ?? [], enabled: allowed) {
        return match
      }
    }
    return nil
  }

  /// 系统返回只改变当前显示层，不创建新的业务展示票据。
  @objc private func back() {
    guard !path.isEmpty else { return }
    path.removeLast()
    rebuild()
  }

  /// 关闭和来源撤销共用一次完成路径，回调在退出动画完成后发出。
  private func end() {
    guard !ending else { return }
    ending = true
    let id = snapshot.presentationId
    guard let navigation = navigationController, navigation.presentingViewController != nil else {
      finishDismissal { cancel(id) }
      return
    }
    navigation.dismiss(animated: true) { [weak self] in
      self?.finishDismissal { self?.cancel(id) }
    }
  }

  /// 撤销与正常选择共享动画完成点，避免新列表在旧控制器尚未退出时呈现。
  private func finishDismissal(_ action: () -> Void) {
    let completions = dismissalCompletions
    dismissalCompletions.removeAll()
    for completion in completions { completion() }
    action()
  }
}
