import MoviePilotCore
import UIKit

/// 原生更多菜单只呈现前端当前目录，选中行仍由 Vue Router 处理授权和页面加载。
@MainActor
final class MoreMenuController: UITableViewController, UITextFieldDelegate {
  private let search = UISearchTextField()
  var onSelect: ((MoreMenuItem) -> Void)?
  private var sections: [MoreMenuSection] = []

  /// 系统分组列表和搜索由 UIKit 提供，业务页面不进入此控制器。
  init() { super.init(style: .insetGrouped) }

  /// 菜单依赖当前会话的目录，不支持 storyboard 初始化。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 保留 Dynamic Type、VoiceOver、滚动和键盘的系统行为。
  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.accessibilityIdentifier = "more-menu"
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 60
    tableView.keyboardDismissMode = .onDrag
    search.delegate = self
    search.placeholder = "搜索菜单"
    search.accessibilityLabel = "搜索菜单"
    search.accessibilityIdentifier = "more-menu-search"
    search.returnKeyType = .search
    search.clearButtonMode = .whileEditing
    search.addAction(
      UIAction { [weak self] _ in self?.tableView.reloadData() }, for: .editingChanged)
    let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 60))
    header.directionalLayoutMargins = tableView.directionalLayoutMargins
    search.translatesAutoresizingMaskIntoConstraints = false
    header.addSubview(search)
    NSLayoutConstraint.activate([
      search.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
      search.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
      search.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
      search.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
    ])
    tableView.tableHeaderView = header
  }

  /// 搜索框与分组菜单共用系统列表边距，安全区或窗口宽度变化后保持两侧对齐。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    tableView.tableHeaderView?.directionalLayoutMargins = tableView.directionalLayoutMargins
  }

  /// 每次已确认快照恢复可操作状态；权限目录变化即时替换原生列表。
  func apply(_ sections: [MoreMenuSection]) {
    loadViewIfNeeded()
    tableView.isUserInteractionEnabled = true
    if self.sections != sections {
      self.sections = sections
      tableView.reloadData()
    }
  }

  /// 离开菜单时收起搜索键盘，搜索框属于列表正文，不占用第二层导航栏。
  func endSearch() {
    tableView.endEditing(true)
  }

  /// 系统搜索键结束输入，结果仍保留在当前原生列表中。
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    endSearch()
    return true
  }

  /// 根据当前搜索保留非空分组，匹配本地化菜单名称与说明。
  private var filtered: [(String, [MoreMenuItem])] {
    let query = search.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return sections.compactMap { section in
      let items =
        query.isEmpty
        ? section.items
        : section.items.filter {
          $0.title.localizedStandardContains(query)
            || ($0.subtitle?.localizedStandardContains(query) ?? false)
        }
      return items.isEmpty ? nil : (section.title, items)
    }
  }

  /// UITableView 的分组来自当前前端目录，不写死管理员或插件入口。
  override func numberOfSections(in tableView: UITableView) -> Int { filtered.count }

  /// 每组行数跟随当前搜索，过期的 indexPath 不作为导航依据。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    filtered[section].1.count
  }

  /// 分组标题保持前端本地化文案。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    filtered[section].0
  }

  /// 使用系统列表内容布局，菜单只负责显示入口名称、说明和符号。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let item = filtered[indexPath.section].1[indexPath.row]
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "entry")
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: "entry")
    var content = cell.defaultContentConfiguration()
    content.text = item.title
    content.secondaryText = item.subtitle
    content.secondaryTextProperties.numberOfLines = 0
    content.image = NavigationSymbols.image(item.icon)
    content.imageProperties.tintColor = .tintColor
    cell.contentConfiguration = content
    cell.accessoryType = .disclosureIndicator
    cell.accessibilityIdentifier = "more-entry-\(item.id)"
    return cell
  }

  /// 首次点击等待网页确认，取消或新状态通过下一快照恢复，避免连续重复导航。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let current = filtered
    guard current.indices.contains(indexPath.section),
      current[indexPath.section].1.indices.contains(indexPath.row)
    else { return }
    let item = current[indexPath.section].1[indexPath.row]
    endSearch()
    tableView.isUserInteractionEnabled = false
    onSelect?(item)
  }
}
