import MoviePilotCore
import UIKit

/// 原生更多菜单只呈现前端当前目录，选中行仍由 Vue Router 处理授权和页面加载。
@MainActor
final class MoreMenuController: UITableViewController {
  // 深色使用与搜索控件接近的柔和灰填充，让网页底色自然透入；浅色保留清晰的系统白色分组。
  private let rowBackground = UIColor { traits in
    let fill: UIColor =
      traits.userInterfaceStyle == .dark
      ? .secondarySystemFill : .secondarySystemGroupedBackground
    return fill.resolvedColor(with: traits)
  }
  var onSelect: ((MoreMenuItem) -> Void)?
  private var sections: [MoreMenuSection] = []
  private var accent: UIColor = .tintColor

  /// 目录使用系统分组列表，业务页面不进入此控制器。
  init() { super.init(style: .insetGrouped) }

  /// 菜单依赖当前会话的目录，不支持 storyboard 初始化。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 保留 Dynamic Type、VoiceOver、滚动和键盘的系统行为。
  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.accessibilityIdentifier = "more-menu"
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 60
  }

  /// 外页跟随网页皮肤；分组填充接近系统搜索框，避免暗色出现独立的黑色卡片。
  func apply(_ sections: [MoreMenuSection], background: UIColor, accent: UIColor) {
    loadViewIfNeeded()
    tableView.backgroundColor = background
    self.accent = accent
    tableView.tintColor = accent
    // 内容配置会保存创建时的颜色；目录不变时也刷新已显示行，避免复用产生两套主题色。
    for cell in tableView.visibleCells {
      cell.backgroundColor = rowBackground
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
    cell.backgroundColor = rowBackground
    cell.accessoryType = .disclosureIndicator
    cell.accessibilityIdentifier = "more-entry-\(item.id)"
    return cell
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
