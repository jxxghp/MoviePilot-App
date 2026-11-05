import MoviePilotCore
import UIKit

/// 原生更多菜单只呈现前端当前目录，选中行仍由 Vue Router 处理授权和页面加载。
@MainActor
final class MoreMenuController: UITableViewController {
  var onSelect: ((MoreMenuItem) -> Void)?
  private var sections: [MoreMenuSection] = []
  private var accent: UIColor = .tintColor
  private let backdrop = UIView()
  private var sectionGlass: [UIVisualEffectView] = []

  /// 目录使用系统分组列表，业务页面不进入此控制器。
  init() { super.init(style: .insetGrouped) }

  /// 菜单依赖当前会话的目录，不支持 storyboard 初始化。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 保留 Dynamic Type、VoiceOver、滚动和键盘的系统行为。
  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 17.0, *) {
      registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
        (controller: MoreMenuController, _: UITraitCollection) in
        controller.refreshGlass()
      }
    }
    tableView.accessibilityIdentifier = "more-menu"
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 60
    backdrop.isUserInteractionEnabled = false
    tableView.backgroundView = backdrop
  }

  /// 旧系统通过传统 trait 回调刷新材质，保持更多页与系统明暗一致。
  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if #unavailable(iOS 17.0),
      previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
    {
      refreshGlass()
    }
  }

  /// 分组玻璃随实际行高与滚动位置布局；整组共用一块材质，避免行间产生折射接缝。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutSectionGlass()
  }

  /// backgroundView 固定在视口内，滚动时将分组的内容坐标转换到背景坐标。
  override func scrollViewDidScroll(_ scrollView: UIScrollView) {
    layoutSectionGlass()
  }

  /// 透明目录直接透出同一 WebView 的实时壁纸，明暗、轮播与渐变继续由前端统一渲染。
  func apply(_ sections: [MoreMenuSection], accent: UIColor) {
    loadViewIfNeeded()
    tableView.backgroundColor = .clear
    self.accent = accent
    tableView.tintColor = accent
    // 内容配置会保存创建时的颜色；目录不变时也刷新已显示行，避免复用产生两套主题色。
    for cell in tableView.visibleCells {
      cell.backgroundConfiguration = .clear()
      if var content = cell.contentConfiguration as? UIListContentConfiguration {
        content.imageProperties.tintColor = accent
        cell.contentConfiguration = content
      }
    }
    tableView.isUserInteractionEnabled = true
    let available = sections.filter { !$0.items.isEmpty }
    if self.sections != available {
      self.sections = available
      tableView.reloadData()
    }
    layoutSectionGlass()
  }

  /// 点击主导航重新进入目录时从首组开始，逻辑返回仍保留原列表位置。
  func scrollToBeginning() {
    loadViewIfNeeded()
    tableView.setContentOffset(
      CGPoint(x: -tableView.adjustedContentInset.left, y: -tableView.adjustedContentInset.top),
      animated: false)
  }

  /// UITableView 的分组来自当前前端目录，不写死管理员或插件入口。
  override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

  /// 每组行数来自当前已授权目录，过期的 indexPath 不作为导航依据。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    sections[section].items.count
  }

  /// 分组标题保持前端本地化文案。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    sections[section].title
  }

  /// 使用系统列表内容布局，菜单只负责显示入口名称、说明和符号。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let item = sections[indexPath.section].items[indexPath.row]
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "entry")
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: "entry")
    var content = cell.defaultContentConfiguration()
    content.text = item.title
    content.secondaryText = item.subtitle
    content.secondaryTextProperties.numberOfLines = 0
    content.image = NavigationSymbols.image(item.icon)
    content.imageProperties.tintColor = accent
    cell.contentConfiguration = content
    cell.backgroundColor = .clear
    cell.backgroundConfiguration = .clear()
    cell.accessoryType = .disclosureIndicator
    cell.accessibilityIdentifier = "more-entry-\(item.id)"
    return cell
  }

  /// 明暗切换重新创建材质，防止离屏分组在 Sheet 归还后继续显示旧主题采样。
  private func refreshGlass() {
    for glass in sectionGlass { glass.removeFromSuperview() }
    sectionGlass.removeAll()
    layoutSectionGlass()
  }

  /// 系统玻璃实时采样下方壁纸，旧版 iOS 使用系统超薄材质，均遵循辅助功能设置。
  private func makeSectionGlass() -> UIVisualEffectView {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      effect = UIGlassEffect(style: .regular)
    } else {
      effect = UIBlurEffect(style: .systemUltraThinMaterial)
    }
    let glass = UIVisualEffectView(effect: effect)
    glass.layer.cornerRadius = 26
    glass.clipsToBounds = true
    glass.isUserInteractionEnabled = false
    return glass
  }

  /// 只维护当前目录所需的分组材质，不为复用单元格反复创建或叠加玻璃层。
  private func layoutSectionGlass() {
    guard isViewLoaded else { return }
    while sectionGlass.count > sections.count { sectionGlass.removeLast().removeFromSuperview() }
    while sectionGlass.count < sections.count {
      let glass = makeSectionGlass()
      backdrop.addSubview(glass)
      sectionGlass.append(glass)
    }
    for (section, glass) in sectionGlass.enumerated() {
      let count = tableView.numberOfRows(inSection: section)
      guard count > 0 else {
        glass.isHidden = true
        continue
      }
      glass.isHidden = false
      let first = tableView.rectForRow(at: IndexPath(row: 0, section: section))
      let last = tableView.rectForRow(at: IndexPath(row: count - 1, section: section))
      glass.frame = tableView.convert(first.union(last), to: backdrop)
    }
  }

  /// 首次点击等待网页确认，取消或新状态通过下一快照恢复，避免连续重复导航。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let current = sections
    guard current.indices.contains(indexPath.section),
      current[indexPath.section].items.indices.contains(indexPath.row)
    else { return }
    let item = current[indexPath.section].items[indexPath.row]
    tableView.isUserInteractionEnabled = false
    onSelect?(item)
  }
}
