import MoviePilotCore
import UIKit

/// 独立原生搜索页只呈现 Vue 的权限、来源和站点声明，所有业务动作回传当前网页。
@MainActor
final class SearchPageController: UITableViewController, UISearchBarDelegate {
  var onEvent: ((String, String?, String?) -> Void)?
  private var snapshot: NativePanelSnapshot?
  private let search = UISearchBar()
  private let scope = UISegmentedControl(items: [])
  private let types = UIStackView()
  private let queryTitle = UILabel()
  private let header = UIStackView()
  private let backdrop = UIView()
  private var glasses: [UIVisualEffectView] = []
  private var scopeIDs: [String] = []
  private var selectedScope = "media"
  private var selectedTypes: [String: String] = [:]
  /// 展示分组仅引用已验证的行，不修改跨模块快照。
  private struct Group: Equatable {
    let id: String
    let title: String?
    let items: [NativePanelItem]
  }
  private var groups: [Group] = []
  private var categories: [NativePanelItem] = []
  private var categorySignature = ""
  private var headerHeight: CGFloat = 0

  /// 分组列表沿用更多页的透明视口，让同一 WebView 持续渲染动态壁纸。
  init() { super.init(style: .insetGrouped) }

  /// 搜索依赖当前网页会话，不支持 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 原生输入、类型选择和列表共享系统字号、键盘与辅助功能。
  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.accessibilityIdentifier = "native-search-page"
    tableView.backgroundColor = .clear
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
      (controller: SearchPageController, _: UITraitCollection) in
      controller.refreshGlass()
    }
    tableView.backgroundView = backdrop
    backdrop.isUserInteractionEnabled = false
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 56
    tableView.keyboardDismissMode = .interactive
    search.searchBarStyle = .minimal
    search.delegate = self
    search.accessibilityIdentifier = "native-search-input"
    search.searchTextField.accessibilityIdentifier = "native-search-field"
    search.autocorrectionType = .no
    search.autocapitalizationType = .none
    search.returnKeyType = .search
    scope.accessibilityIdentifier = "native-search-scopes"
    scope.addAction(UIAction { [weak self] _ in self?.changeScope() }, for: .valueChanged)
    types.axis = .horizontal
    types.distribution = .fillEqually
    types.spacing = 8
    header.axis = .vertical
    header.spacing = 16
    header.isLayoutMarginsRelativeArrangement = true
    header.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 8, leading: 20, bottom: 12, trailing: 20)
    header.addArrangedSubview(search)
    header.addArrangedSubview(scope)
    header.addArrangedSubview(types)
    queryTitle.font = UIFontMetrics(forTextStyle: .title1).scaledFont(
      for: .systemFont(ofSize: 28, weight: .bold))
    queryTitle.adjustsFontForContentSizeCategory = true
    queryTitle.numberOfLines = 0
    header.addArrangedSubview(queryTitle)
    tableView.tableHeaderView = header
  }

  /// 窗口宽度、键盘和 Dynamic Type 变化后只量测原生控件，不截取或复制壁纸。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let width = tableView.bounds.width
    let height = header.systemLayoutSizeFitting(
      CGSize(width: width, height: 0), withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    if abs(height - headerHeight) > 0.5 || abs(header.frame.width - width) > 0.5 {
      headerHeight = height
      header.frame = CGRect(x: 0, y: 0, width: width, height: height)
      tableView.tableHeaderView = header
    }
    layoutGlass()
  }

  /// 滚动只移动分组材质，壁纸继续由下层网页负责轮播和主题。
  override func scrollViewDidScroll(_ scrollView: UIScrollView) { layoutGlass() }

  /// 新快照保留当前类型和输入焦点；权限撤销后收敛到仍可见的分类。
  func apply(_ snapshot: NativePanelSnapshot, accent: UIColor) {
    loadViewIfNeeded()
    self.snapshot = snapshot
    if tableView.tintColor != accent { categorySignature = "" }
    tableView.tintColor = accent
    search.tintColor = accent
    if !search.searchTextField.isFirstResponder { search.text = snapshot.search?.text }
    search.placeholder = snapshot.search?.placeholder
    let available = ["media", "resources", "local"].filter { id in
      id == "local" || snapshot.sections.contains { $0.id == id && !$0.items.isEmpty }
    }
    if available != scopeIDs {
      scopeIDs = available
      scope.removeAllSegments()
      for (index, id) in available.enumerated() {
        let title = id == "local" ? "应用" : id == "resources" ? "资源" : "媒体"
        scope.insertSegment(withTitle: title, at: index, animated: false)
      }
    }
    if !available.contains(selectedScope) { selectedScope = available.first ?? "local" }
    scope.selectedSegmentIndex = available.firstIndex(of: selectedScope) ?? 0
    rebuild()
  }

  /// 切换大类时撤销旧数据源控件，并按当前资源类型请求其独立站点目录。
  private func changeScope() {
    search.resignFirstResponder()
    guard scopeIDs.indices.contains(scope.selectedSegmentIndex) else { return }
    selectedScope = scopeIDs[scope.selectedSegmentIndex]
    categorySignature = ""
    rebuild()
    requestCategory()
  }

  /// 选择类型只更新原生展示；资源类的惰性加载仍由 Vue 回调完成。
  private func selectType(_ id: String) {
    search.resignFirstResponder()
    selectedTypes[selectedScope] = id
    categorySignature = ""
    rebuild()
    requestCategory()
  }

  /// 分类回调带 keepOpen，不能把切换类型误当成执行搜索。
  private func requestCategory() {
    guard let item = currentCategory, item.keepOpen == true else { return }
    onEvent?("select", item.id, nil)
  }

  /// 每个大类独立记住类型，切换后不复用另一类的数据源或主要按钮。
  private var currentCategory: NativePanelItem? {
    categories.first { $0.id == selectedTypes[selectedScope] } ?? categories.first
  }

  /// 按声明构造来源清单、主操作与应用内匹配；空关键词只显示近期搜索。
  private func rebuild() {
    guard let snapshot else { return }
    categories =
      selectedScope == "local"
      ? [] : snapshot.sections.first { $0.id == selectedScope }?.items ?? []
    let selected = currentCategory
    if let selected { selectedTypes[selectedScope] = selected.id }
    let signature =
      categories.map { "\($0.id)|\($0.title)" }.joined(separator: ";") + (selected?.id ?? "")
    if signature != categorySignature {
      categorySignature = signature
      for child in types.arrangedSubviews {
        types.removeArrangedSubview(child)
        child.removeFromSuperview()
      }
      for item in categories {
        var config = UIButton.Configuration.tinted()
        if #available(iOS 26.0, *) { config = .glass() }
        let labels = [
          "media-media": "影视", "media-music": "音乐", "media-collection": "合集", "media-person": "人物",
          "resource-torrent": "影视资源", "resource-music": "音乐资源", "resource-subtitle": "字幕",
        ]
        config.title = labels[item.id] ?? item.title
        config.image = item.icon.flatMap { NavigationSymbols.image($0) }
        config.imagePlacement = .top
        config.imagePadding = 8
        config.cornerStyle = .large
        config.baseForegroundColor = item.id == selected?.id ? tableView.tintColor : .label
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
          incoming in
          var attributes = incoming
          attributes.font = .preferredFont(forTextStyle: .caption1)
          return attributes
        }
        let button = UIButton(
          configuration: config,
          primaryAction: UIAction { [weak self] _ in self?.selectType(item.id) })
        button.accessibilityLabel = config.title
        button.accessibilityIdentifier = "native-search-type-\(item.id)"
        button.isSelected = item.id == selected?.id
        button.titleLabel?.numberOfLines = 2
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        types.addArrangedSubview(button)
      }
    }
    types.isHidden = categories.isEmpty
    var next: [Group] = []
    let keyword = snapshot.search?.text ?? ""
    queryTitle.text = keyword.isEmpty ? "搜索" : "搜索“\(keyword)”"
    queryTitle.isHidden = selectedScope == "local" && keyword.isEmpty
    if let selected {
      let choices = (selected.children ?? []).filter { $0.primary != true }
      let run = (selected.children ?? []).filter { $0.primary == true }
      if !choices.isEmpty {
        next.append(
          Group(
            id: "choices", title: selectedScope == "resources" ? "选择站点" : "数据源",
            items: choices))
      }
      if !run.isEmpty {
        next.append(Group(id: "submit", title: nil, items: run))
      }
    }
    let localIDs =
      selectedScope == "local" ? ["local", "menus", "subscriptions", "plugins"] : []
    for section in snapshot.sections where localIDs.contains(section.id) && !section.items.isEmpty {
      next.append(Group(id: section.id, title: section.title, items: section.items))
    }
    if keyword.isEmpty, let recent = snapshot.sections.first(where: { $0.id == "recent" }),
      !recent.items.isEmpty
    {
      next.append(Group(id: recent.id, title: recent.title, items: recent.items))
    }
    if groups != next {
      groups = next
      tableView.reloadData()
    }
    tableView.setNeedsLayout()
    layoutGlass()
  }

  /// 搜索正文来自当前投影，分组顺序不持有业务回调。
  override func numberOfSections(in tableView: UITableView) -> Int { groups.count }

  /// 行数按当前快照读取，迟到的点击在选择回调中再次校验。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    groups[section].items.count
  }

  /// 组标题使用当前资源类型的明确描述。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  { groups[section].title }

  /// 来源使用系统勾选列表；主要动作使用原生填充按钮，避免与列表项混淆。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let item = groups[indexPath.section].items[indexPath.row]
    if item.primary == true {
      let cell = UITableViewCell()
      cell.backgroundConfiguration = .clear()
      var config = UIButton.Configuration.filled()
      config.title = item.title
      config.image = UIImage(systemName: "magnifyingglass")
      config.imagePadding = 10
      config.cornerStyle = .capsule
      config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
      let button = UIButton(
        configuration: config, primaryAction: UIAction { [weak self] _ in self?.select(item) })
      button.isEnabled = item.enabled != false
      button.accessibilityIdentifier = "native-search-submit"
      button.translatesAutoresizingMaskIntoConstraints = false
      cell.contentView.addSubview(button)
      NSLayoutConstraint.activate([
        button.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
        button.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
        button.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
        button.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
      ])
      return cell
    }
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "search-choice")
      ?? UITableViewCell(style: .subtitle, reuseIdentifier: "search-choice")
    var content = cell.defaultContentConfiguration()
    content.text = item.title
    content.secondaryText = item.subtitle
    // 已选站点以摘要呈现，较多名称截为两行，完整目录在选择弹窗中查看。
    content.textProperties.numberOfLines = item.id.hasPrefix("native-sites-select-") ? 2 : 0
    content.secondaryTextProperties.numberOfLines = 0
    content.image = item.icon.flatMap { NavigationSymbols.image($0) }
    content.imageProperties.tintColor = tableView.tintColor
    cell.contentConfiguration = content
    cell.backgroundConfiguration = .clear()
    cell.accessoryType =
      item.selected == true
      ? .checkmark
      : (item.keepOpen == true && !item.id.hasPrefix("native-sites-select-")
        ? .none : .disclosureIndicator)
    cell.accessibilityIdentifier = "native-search-item-\(item.id)"
    cell.accessibilityTraits = item.selected == true ? [.button, .selected] : .button
    cell.isUserInteractionEnabled = item.enabled != false
    cell.contentView.alpha = item.enabled == false ? 0.5 : 1
    return cell
  }

  /// 点击只回传仍在当前快照中的稳定标识，原生不拼装搜索 URL。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard groups.indices.contains(indexPath.section),
      groups[indexPath.section].items.indices.contains(indexPath.row)
    else { return }
    select(groups[indexPath.section].items[indexPath.row])
  }

  /// 选择数据源时保留键盘，执行搜索或导航时收起键盘等待 Vue 路由确认。
  private func select(_ item: NativePanelItem) {
    guard item.enabled != false else { return }
    if item.keepOpen != true { search.resignFirstResponder() }
    onEvent?("select", item.id, nil)
  }

  /// 输入只更新原始搜索状态，异步匹配不会替换正在编辑的系统输入框。
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    onEvent?("query", nil, String(searchText.prefix(256)))
  }

  /// 键盘搜索键执行当前类型唯一主要动作，应用模式仅收起键盘。
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    if let item = currentCategory?.children?.first(where: { $0.primary == true }),
      item.enabled != false
    {
      select(item)
    } else {
      searchBar.resignFirstResponder()
    }
  }

  /// Sheet 归还后清除系统材质的旧采样，避免离屏分组保留切换前的深色玻璃。
  private func refreshGlass() {
    for glass in glasses { glass.removeFromSuperview() }
    glasses.removeAll()
    layoutGlass()
  }

  /// 分组共用更多页的系统材质，整组采样实时壁纸且避免行间折射接缝。
  private func layoutGlass() {
    guard isViewLoaded else { return }
    while glasses.count > groups.count { glasses.removeLast().removeFromSuperview() }
    while glasses.count < groups.count {
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
      backdrop.addSubview(glass)
      glasses.append(glass)
    }
    for (index, glass) in glasses.enumerated() {
      let count = tableView.numberOfRows(inSection: index)
      glass.isHidden = count == 0 || groups[index].id == "submit"
      if count > 0 {
        let first = tableView.rectForRow(at: IndexPath(row: 0, section: index))
        let last = tableView.rectForRow(at: IndexPath(row: count - 1, section: index))
        glass.frame = tableView.convert(first.union(last), to: backdrop)
      }
    }
  }
}
