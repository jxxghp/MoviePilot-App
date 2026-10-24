import ImageIO
import MoviePilotCore
import UIKit
import WebKit

/// 系统浮层自带 Liquid Glass；清除内容实色，避免把系统材质盖住或叠加另一层玻璃。
@MainActor
enum NativeModalAppearance {
  /// 表格和分组背景保持透明，材质、圆角与阴影由系统 presentation controller 负责。
  static func apply(to controller: UITableViewController) {
    controller.tableView.backgroundColor = .clear
    controller.tableView.backgroundView = nil
    controller.navigationController?.view.backgroundColor = .clear
  }

  /// 呈现层也跟随 App 主题；材质厚度、外围压暗和转场全部使用 UIKit 默认行为。
  static func apply(to presentation: UIPresentationController?, style: UIUserInterfaceStyle) {
    presentation?.traitOverrides.userInterfaceStyle = style
  }
}

/// 海报读取只复用当前 WebView 的图片 Cookie，不接触业务令牌；关闭面板即清理内存和网络。
@MainActor
final class NativePanelImageLoader: NSObject, URLSessionTaskDelegate {
  private let store: WKWebsiteDataStore
  private let origin: WebOrigin
  private let cache = NSCache<NSURL, UIImage>()
  private var tasks: [String: Task<UIImage?, Never>] = [:]
  private var stopped = false
  private lazy var network: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 12
    configuration.timeoutIntervalForResource = 20
    return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
  }()

  /// 缓存只属于一次面板会话，不在磁盘或其他实例中共享通知图片。
  init(store: WKWebsiteDataStore, origin: WebOrigin) {
    self.store = store
    self.origin = origin
    super.init()
    cache.countLimit = 40
    cache.totalCostLimit = 8 * 1024 * 1024
  }

  /// 同一地址合并请求，Cookie 仅用于当前实例同源图片，外部海报不携带实例身份。
  func image(_ reference: String) async -> UIImage? {
    guard !stopped, NavigationSnapshot.isProfileImageReference(reference),
      let url = URL(string: reference)
    else { return nil }
    if let cached = cache.object(forKey: url as NSURL) { return cached }
    if reference.hasPrefix("data:image/jpeg;base64,") {
      guard let data = Data(base64Encoded: String(reference.dropFirst(23))),
        let image = Self.thumbnail(data)
      else { return nil }
      cache.setObject(
        image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
      return image
    }
    if let task = tasks[reference] { return await task.value }
    let task = Task { [weak self] () -> UIImage? in
      guard let self else { return nil }
      var request = URLRequest(url: url)
      if WebOrigin(url: url) == self.origin {
        let cookies = await self.store.httpCookieStore.allCookies()
        let applicable = cookies.filter { cookie in
          let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
          let host = url.host?.lowercased() ?? ""
          return (host == domain || host.hasSuffix(".\(domain)"))
            && url.path.hasPrefix(cookie.path)
            && (!cookie.isSecure || url.scheme == "https")
            && (cookie.expiresDate.map { $0 > Date() } ?? true)
        }
        for (key, value) in HTTPCookie.requestHeaderFields(with: applicable) {
          request.setValue(value, forHTTPHeaderField: key)
        }
      }
      guard !self.stopped, !Task.isCancelled,
        let data = await Self.download(request, network: self.network), !Task.isCancelled,
        !self.stopped, let thumbnail = Self.thumbnail(data)
      else { return nil }
      self.cache.setObject(
        thumbnail, forKey: url as NSURL, cost: Int(thumbnail.size.width * thumbnail.size.height * 4)
      )
      return thumbnail
    }
    tasks[reference] = task
    let result = await task.value
    tasks[reference] = nil
    return result
  }

  /// 只解码有界栅格缩略图，头像和海报共用尺寸限制，不把图片当成网页内容执行。
  private static func thumbnail(_ data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 300,
        ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
  }

  /// 按字节读取限制每张图片最多四 MiB，下载在非主 actor 执行，不阻塞列表滚动。
  nonisolated private static func download(_ request: URLRequest, network: URLSession) async
    -> Data?
  {
    do {
      let (bytes, response) = try await network.bytes(for: request)
      defer { bytes.task.cancel() }
      let maximum = 4 * 1024 * 1024
      guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
        response.mimeType?.hasPrefix("image/") == true, response.expectedContentLength <= maximum
      else { return nil }
      var data = Data()
      for try await byte in bytes {
        guard data.count < maximum, !Task.isCancelled else { return nil }
        data.append(byte)
      }
      return data
    } catch { return nil }
  }

  /// 图片重定向只允许 HTTP(S)，跨来源时明确丢弃 Cookie 与认证头。
  nonisolated func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let url = request.url, NavigationSnapshot.isImageReference(url.absoluteString) else {
      completionHandler(nil)
      return
    }
    var next = request
    if response.url.flatMap(WebOrigin.init(url:)) != WebOrigin(url: url) {
      next.setValue(nil, forHTTPHeaderField: "Cookie")
      next.setValue(nil, forHTTPHeaderField: "Authorization")
    }
    completionHandler(next)
  }

  /// 切换页面、退出或收起面板后，不再保留通知图片或迟到请求。
  func stop() {
    stopped = true
    for task in tasks.values { task.cancel() }
    tasks.removeAll()
    network.invalidateAndCancel()
    cache.removeAllObjects()
  }
}

/// 快捷入口使用系统列表或图标网格，所有业务意图通过当前网页声明返回。
@MainActor
final class NativePanelController: UITableViewController, UISearchBarDelegate {
  private var snapshot: NativePanelSnapshot
  private var renderedSnapshot: NativePanelSnapshot?
  private let path: [String]
  private let onEvent: (String, String?, String?, Bool) -> Void
  private let onClose: () -> Void
  private let images: NativePanelImageLoader
  private let search = UISearchBar()
  private let progress = UIActivityIndicatorView(style: .medium)
  private var sections: [(String?, [NativePanelItem])] = []
  private var sectionIDs: [String] = []
  private var gridColumns = 3
  private var primaryAction: NativePanelItem?
  private var contextText: String?
  private var headerText: String?
  private var measuredWidth: CGFloat?
  private var updatingPreferredSize = false
  private var profileImageTask: Task<Void, Never>?
  private var queryTask: Task<Void, Never>?
  private var imageTasks: [Task<Void, Never>] = []
  private var feedState = NativePanelFeedState()
  private var applyingSnapshot = false
  private var rowHeights:
    [String: (
      item: NativePanelItem, height: CGFloat, width: CGFloat, category: UIContentSizeCategory
    )] = [:]

  /// 网格只作用于入口层，业务动作和其他子菜单仍使用原生导航栈。
  private var usesGrid: Bool { path.isEmpty && snapshot.layout == .grid }

  /// 子菜单只保存稳定路径，更新时重新从最新快照查找内容。
  init(
    snapshot: NativePanelSnapshot, path: [String] = [], images: NativePanelImageLoader,
    onEvent: @escaping (String, String?, String?, Bool) -> Void,
    onClose: @escaping () -> Void
  ) {
    self.snapshot = snapshot
    self.path = path
    self.onEvent = onEvent
    self.onClose = onClose
    self.images = images
    super.init(style: .insetGrouped)
  }

  /// 面板绑定当前桥接会话，不从 storyboard 恢复业务状态。
  required init?(coder: NSCoder) { fatalError("Use init(snapshot:path:onEvent:onClose:)") }

  /// 系统控件提供动态字体、VoiceOver、分组滚动和原生键盘交互。
  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.accessibilityIdentifier = "native-quick-panel"
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 64
    tableView.keyboardDismissMode = .interactive
    tableView.alwaysBounceVertical = true
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
      (controller: NativePanelController, _: UITraitCollection) in
      controller.measuredWidth = nil
      controller.view.setNeedsLayout()
    }
    NativeModalAppearance.apply(to: self)
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose() })
    navigationItem.rightBarButtonItem?.accessibilityIdentifier = "native-panel-close"
    progress.accessibilityIdentifier = "native-panel-loading"
    search.delegate = self
    search.searchBarStyle = .minimal
    search.accessibilityIdentifier = "native-panel-search"
    search.searchTextField.accessibilityIdentifier = "native-panel-search-field"
    search.searchTextField.autocorrectionType = .no
    search.searchTextField.autocapitalizationType = .none
    apply(snapshot)
  }

  /// 内容较少的子菜单缩短浮层高度，长列表限制在底栏上方，避免留下大块空白。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if usesGrid {
      let columns =
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        ? 2 : min(4, max(2, Int((tableView.bounds.width - 40) / 104)))
      if gridColumns != columns {
        gridColumns = columns
        tableView.reloadData()
      }
    }
    updateHeaderHeight()
    updatePreferredSize()
    loadMoreIfNeeded()
  }

  /// 初次呈现动画结束后再适配短内容，避免加载快照在动画中反复改变浮层几何。
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updatePreferredSize()
    loadMoreIfNeeded()
  }

  /// 每层导航自行声明工具栏；返回来源列表时不会遗留上一个分类的搜索按钮。
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    configurePrimaryAction(animated: animated)
  }

  /// 离开搜索页即取消尚未发送的输入，旧控制器不能把查询发给后来打开的其他面板。
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    queryTask?.cancel()
  }

  /// 按当前可见内容量测宽度；同一次菜单不随搜索结果反复横向跳动，大字体保留可读空间。
  func preferredPanelWidth(maximum: CGFloat) -> CGFloat {
    if path.isEmpty, snapshot.width == .full { return maximum }
    if traitCollection.preferredContentSizeCategory.isAccessibilityCategory { return maximum }
    if let measuredWidth { return min(maximum, measuredWidth) }
    let rows = sections.flatMap(\.1)
    var width: CGFloat = path.isEmpty && snapshot.search != nil ? 320 : 260
    if path.isEmpty, let profile = snapshot.profile {
      width = max(
        width,
        min(
          320,
          (profile.name as NSString).size(withAttributes: [
            .font: UIFont.preferredFont(forTextStyle: .headline)
          ]).width + 112))
    }
    for row in rows {
      width = max(
        width,
        min(
          240,
          (row.title as NSString).size(withAttributes: [
            .font: UIFont.preferredFont(forTextStyle: .body)
          ]).width) + 88)
      if let detail = row.subtitle {
        width = max(
          width,
          min(
            240,
            (detail as NSString).size(withAttributes: [
              .font: UIFont.preferredFont(forTextStyle: .subheadline)
            ]).width) + 88)
      }
      if row.image != nil { width = max(width, 336) }
    }
    if !rows.isEmpty { measuredWidth = width }
    return min(maximum, width)
  }

  /// 系统设置尺寸时会同步重排浮层，赋值期间屏蔽重入，避免布局回调递归耗尽栈。
  private func updatePreferredSize() {
    guard !updatingPreferredSize, let navigationController,
      navigationController.topViewController === self,
      navigationController.modalPresentationStyle == .popover,
      let host = navigationController.presentingViewController,
      !navigationController.isBeingPresented, navigationController.transitionCoordinator == nil,
      !snapshot.sections.isEmpty
    else { return }
    updatingPreferredSize = true
    defer { updatingPreferredSize = false }
    let maximum = min(
      580,
      max(
        280,
        host.view.bounds.height - host.view.safeAreaInsets.top - host.view.safeAreaInsets.bottom
          - 170))
    let height = min(
      maximum, max(220, tableView.contentSize.height + 56 + (primaryAction == nil ? 0 : 56)))
    let width = preferredPanelWidth(maximum: maximumPanelWidth(in: host.view))
    if abs(navigationController.preferredContentSize.height - height) > 2
      || abs(navigationController.preferredContentSize.width - width) > 2
    {
      navigationController.preferredContentSize = CGSize(width: width, height: height)
    }
  }

  /// 长正文保留两侧各八点边距，普通菜单继续收窄；安全区和宽窗口各自限制可读宽度。
  func maximumPanelWidth(in host: UIView) -> CGFloat {
    let full = path.isEmpty && snapshot.width == .full
    let margins: CGFloat = full ? 16 : 40
    let safeWidth = host.bounds.width - host.safeAreaInsets.left - host.safeAreaInsets.right
    return max(0, min(full ? 600 : 430, safeWidth - margins))
  }

  /// 有界分片在当前原生列表中合并；保存首个可见行的位置，加载和新消息不把滚动位置跳回顶部。
  func apply(_ snapshot: NativePanelSnapshot) {
    self.snapshot = snapshot
    guard isViewLoaded, renderedSnapshot != snapshot else { return }
    applyingSnapshot = true
    let previousFeed = renderedSnapshot?.feed?.id
    if previousFeed != snapshot.feed?.id { rowHeights.removeAll() }
    renderedSnapshot = snapshot
    let previousSections = sections
    let previousIDs = sectionIDs
    let previousRows = sections.flatMap(\.1)
    let previousTitles = sections.map(\.0)
    let anchor = visibleAnchor()
    let incoming = path.isEmpty ? feedState.apply(snapshot) : snapshot.sections
    var rows = incoming.flatMap(\.items)
    var current: NativePanelItem?
    for id in path {
      current = rows.first { $0.id == id }
      rows = current?.children ?? []
    }
    title = current?.title ?? snapshot.title
    contextText = current?.subtitle
    primaryAction = path.isEmpty ? nil : rows.first { $0.primary == true }
    if let primaryAction { rows.removeAll { $0.id == primaryAction.id } }
    sections =
      path.isEmpty
      ? incoming.filter { !$0.items.isEmpty }.map { ($0.title, $0.items) }
      : [(nil, rows)]
    sectionIDs = path.isEmpty ? incoming.filter { !$0.items.isEmpty }.map(\.id) : ["children"]
    if path.isEmpty, let input = snapshot.search {
      search.placeholder = input.placeholder
      if !search.searchTextField.isFirstResponder { search.text = input.text }
    }
    configureHeader()
    configureFooter()
    tableView.separatorStyle = usesGrid ? .none : .singleLine
    if navigationController?.topViewController === self { configurePrimaryAction(animated: false) }
    if previousRows != sections.flatMap(\.1) || previousTitles != sections.map(\.0) {
      let continued = snapshot.feed != nil && previousFeed == snapshot.feed?.id && path.isEmpty
      let incremental = continued && applyFeedRows(from: previousSections, ids: previousIDs)
      if !incremental {
        for task in imageTasks { task.cancel() }
        imageTasks.removeAll()
        tableView.reloadData()
      }
      tableView.layoutIfNeeded()
      if let anchor,
        !incremental
          || previousRows.prefix(while: { $0.id != anchor.0 })
            != sections.flatMap(\.1).prefix(while: { $0.id != anchor.0 })
      {
        restoreVisibleAnchor(anchor)
      }
    }
    applyingSnapshot = false
    loadMoreIfNeeded()
  }

  /// 连续分片只插入新增行、更新变化行，保留 UIKit 已量测的长正文高度和正在显示的单元格。
  private func applyFeedRows(from previous: [(String?, [NativePanelItem])], ids: [String]) -> Bool {
    let oldSections = Set(ids)
    let newSections = Set(sectionIDs)
    guard
      ids.filter({ newSections.contains($0) }) == sectionIDs.filter({ oldSections.contains($0) })
    else { return false }
    var inserted: [IndexPath] = []
    var deleted: [IndexPath] = []
    var updated: [IndexPath] = []
    for (oldIndex, id) in ids.enumerated() {
      guard let newIndex = sectionIDs.firstIndex(of: id) else { continue }
      let old = previous[oldIndex].1
      let new = sections[newIndex].1
      let oldIDs = Set(old.map(\.id))
      let newIDs = Set(new.map(\.id))
      guard previous[oldIndex].0 == sections[newIndex].0,
        old.filter({ newIDs.contains($0.id) }).map(\.id)
          == new.filter({ oldIDs.contains($0.id) }).map(\.id)
      else { return false }
      let current = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0) })
      for (row, item) in old.enumerated() {
        let path = IndexPath(row: row, section: oldIndex)
        if !newIDs.contains(item.id) {
          deleted.append(path)
        } else if current[item.id] != item {
          updated.append(path)
        }
      }
      for (row, item) in new.enumerated() where !oldIDs.contains(item.id) {
        inserted.append(IndexPath(row: row, section: newIndex))
      }
    }
    let removed = IndexSet(ids.indices.filter { !newSections.contains(ids[$0]) })
    let added = IndexSet(sectionIDs.indices.filter { !oldSections.contains(sectionIDs[$0]) })
    UIView.performWithoutAnimation {
      tableView.performBatchUpdates {
        tableView.deleteSections(removed, with: .none)
        tableView.insertSections(added, with: .none)
        tableView.deleteRows(at: deleted, with: .none)
        tableView.insertRows(at: inserted, with: .none)
        tableView.reloadRows(at: updated, with: .none)
      }
    }
    return true
  }

  /// 记录的是行标识和屏幕内相对位置，不保存业务数据或依赖估算的固定行高。
  private func visibleAnchor() -> (String, CGFloat)? {
    guard path.isEmpty, snapshot.feed != nil,
      let index = tableView.indexPathsForVisibleRows?.first,
      sections.indices.contains(index.section),
      sections[index.section].1.indices.contains(index.row)
    else { return nil }
    return (
      sections[index.section].1[index.row].id,
      tableView.rectForRow(at: index).minY - tableView.contentOffset.y
    )
  }

  /// 追加历史或更新旧行后恢复原可见位置；被清理的行不再充当锚点。
  private func restoreVisibleAnchor(_ anchor: (String, CGFloat)?) {
    guard let (id, distance) = anchor else { return }
    for (section, rows) in sections.enumerated() {
      guard let row = rows.1.firstIndex(where: { $0.id == id }) else { continue }
      let target = tableView.rectForRow(at: IndexPath(row: row, section: section)).minY - distance
      let maximum = max(
        -tableView.adjustedContentInset.top,
        tableView.contentSize.height - tableView.bounds.height
          + tableView.adjustedContentInset.bottom)
      tableView.setContentOffset(
        CGPoint(x: 0, y: min(maximum, max(-tableView.adjustedContentInset.top, target))),
        animated: false)
      return
    }
  }

  /// 接近列表底部由原生发出加载意图；完成应答、失败或结束前不会重复发请求。
  private func loadMoreIfNeeded(retry: Bool = false) {
    guard !applyingSnapshot, path.isEmpty, viewIfLoaded?.window != nil,
      navigationController?.topViewController === self,
      UIApplication.shared.applicationState == .active,
      let feed = snapshot.feed
    else { return }
    let bottom =
      tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
    let contentBottom =
      tableView.contentSize.height - (tableView.tableFooterView?.frame.height ?? 0)
    guard feedState.requestMore(isNearEnd: bottom >= contentBottom - 100, retry: retry) else {
      return
    }
    onEvent("more", nil, feed.id, true)
  }

  /// UIKit 滚动位置驱动连续加载，不依赖网页中已经隐藏的无限滚动交叉观察器。
  override func scrollViewDidScroll(_ scrollView: UIScrollView) {
    loadMoreIfNeeded()
  }

  /// 主要动作固定在系统底部工具栏，来源选择滚动时按钮仍可见；回调只引用最新声明。
  private func configurePrimaryAction(animated: Bool) {
    guard let navigationController else { return }
    guard let item = primaryAction else {
      toolbarItems = nil
      navigationController.setToolbarHidden(true, animated: animated)
      return
    }
    var configuration = UIButton.Configuration.filled()
    configuration.title = item.title
    configuration.image = item.icon.flatMap { NavigationSymbols.image($0) }
    configuration.imagePadding = 8
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 10, leading: 24, bottom: 10, trailing: 24)
    let button = UIButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] _ in
        guard let self, let current = self.primaryAction, current.enabled != false else { return }
        self.tableView.endEditing(true)
        self.onEvent("select", current.id, self.snapshot.feed?.id, false)
      })
    button.tintColor = view.tintColor
    button.isEnabled = item.enabled != false && snapshot.loading != true
    button.accessibilityIdentifier = "native-panel-primary-action"
    toolbarItems = [.flexibleSpace(), UIBarButtonItem(customView: button), .flexibleSpace()]
    navigationController.setToolbarHidden(false, animated: animated)
  }

  /// 账号摘要和搜索框使用系统字体与列表边距，头像仅存在于当前面板会话。
  private func configureHeader() {
    let text = path.isEmpty ? snapshot.subtitle : contextText
    let profile = path.isEmpty ? snapshot.profile : nil
    let hasSearch = path.isEmpty && snapshot.search != nil
    let identity =
      "\(text ?? "")|\(profile?.name ?? "")|\(profile?.detail ?? "")|\(profile?.image ?? "")|\(hasSearch)"
    guard headerText != identity else { return }
    headerText = identity
    profileImageTask?.cancel()
    guard text != nil || profile != nil || hasSearch else {
      tableView.tableHeaderView = nil
      return
    }
    let header = UIView(
      frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 1))
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    if let profile { stack.addArrangedSubview(profileHeader(profile)) }
    if let text {
      let label = UILabel()
      label.text = text
      label.textColor = .secondaryLabel
      label.font = .preferredFont(forTextStyle: .subheadline)
      label.adjustsFontForContentSizeCategory = true
      label.numberOfLines = 2
      stack.addArrangedSubview(label)
    }
    if hasSearch {
      search.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
      stack.addArrangedSubview(search)
    }
    header.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
      stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
    ])
    tableView.tableHeaderView = header
    updateHeaderHeight()
  }

  /// 原生账号摘要展示头像、昵称与当前身份，不能修改账号、权限或登录状态。
  private func profileHeader(_ profile: NativePanelProfile) -> UIView {
    let avatar = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
    avatar.contentMode = .scaleAspectFill
    avatar.tintColor = .secondaryLabel
    avatar.clipsToBounds = true
    avatar.layer.cornerRadius = 28
    avatar.isAccessibilityElement = true
    avatar.accessibilityLabel = "用户头像"
    avatar.accessibilityIdentifier = "native-profile-avatar"
    avatar.accessibilityValue = "默认头像"
    NSLayoutConstraint.activate([
      avatar.widthAnchor.constraint(equalToConstant: 56),
      avatar.heightAnchor.constraint(equalToConstant: 56),
    ])
    if let image = profile.image {
      profileImageTask = Task { [weak avatar, images] in
        let loaded = await images.image(image)
        guard !Task.isCancelled, let avatar else { return }
        if let loaded {
          avatar.image = loaded
          avatar.tintColor = nil
          avatar.accessibilityValue = "头像已加载"
        }
      }
    }
    let name = UILabel()
    name.text = profile.name
    name.font = .preferredFont(forTextStyle: .headline)
    name.adjustsFontForContentSizeCategory = true
    name.numberOfLines = 2
    name.accessibilityIdentifier = "native-profile-name"
    let labels = UIStackView(arrangedSubviews: [name])
    labels.axis = .vertical
    labels.spacing = 5
    if let detail = profile.detail {
      let role = UILabel()
      role.text = detail
      role.textColor = .secondaryLabel
      role.font = .preferredFont(forTextStyle: .subheadline)
      role.adjustsFontForContentSizeCategory = true
      role.numberOfLines = 0
      role.accessibilityIdentifier = "native-profile-detail"
      labels.addArrangedSubview(role)
    }
    let stack = UIStackView(arrangedSubviews: [avatar, labels])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 14
    stack.accessibilityIdentifier = "native-profile-summary"
    return stack
  }

  /// 宽度或动态字体变化后重新量测 tableHeaderView，避免账号信息被固定高度裁切。
  private func updateHeaderHeight() {
    guard let header = tableView.tableHeaderView, tableView.bounds.width > 0 else { return }
    let width = tableView.bounds.width
    let height = header.systemLayoutSizeFitting(
      CGSize(width: width, height: 0), withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    if abs(header.frame.height - height) > 1 || abs(header.frame.width - width) > 1 {
      header.frame = CGRect(x: 0, y: 0, width: width, height: height)
      tableView.tableHeaderView = header
    }
  }

  /// 连续列表只显示加载、末尾和失败重试；旧前端仍保留既有分页兼容入口。
  private func configureFooter() {
    let footer = UIStackView()
    footer.axis = .vertical
    footer.alignment = .center
    footer.spacing = 12
    if snapshot.loading == true {
      footer.addArrangedSubview(progress)
      progress.startAnimating()
    } else {
      progress.stopAnimating()
    }
    let empty =
      snapshot.feed != nil && path.isEmpty
      ? feedState.isEmpty : sections.allSatisfy({ $0.1.isEmpty })
    if empty && snapshot.loading != true && snapshot.loadError == nil {
      let label = UILabel()
      label.text = snapshot.emptyText ?? "暂无内容"
      label.textColor = .secondaryLabel
      label.font = .preferredFont(forTextStyle: .body)
      label.numberOfLines = 0
      label.textAlignment = .center
      footer.addArrangedSubview(label)
    }
    if path.isEmpty, snapshot.feed != nil, let error = snapshot.loadError, snapshot.loading != true
    {
      var config = UIButton.Configuration.plain()
      config.title = error
      let retry = UIButton(
        configuration: config,
        primaryAction: UIAction { [weak self] _ in self?.loadMoreIfNeeded(retry: true) })
      retry.accessibilityIdentifier = "native-panel-retry"
      footer.addArrangedSubview(retry)
    }
    if path.isEmpty && snapshot.feed == nil && snapshot.hasMore == true {
      var config = UIButton.Configuration.tinted()
      config.title = "下一页"
      config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
      let more = UIButton(
        configuration: config,
        primaryAction: UIAction { [weak self] _ in
          self?.onEvent("more", nil, nil, true)
        })
      more.accessibilityIdentifier = "native-panel-more"
      more.isEnabled = snapshot.loading != true
      footer.addArrangedSubview(more)
    }
    if path.isEmpty, snapshot.feed != nil, !feedState.isEmpty, snapshot.hasMore != true,
      snapshot.loading != true
    {
      let label = UILabel()
      label.text = "已显示全部内容"
      label.font = .preferredFont(forTextStyle: .footnote)
      label.textColor = .secondaryLabel
      label.accessibilityIdentifier = "native-panel-feed-end"
      footer.addArrangedSubview(label)
    }
    footer.frame = CGRect(
      x: 0, y: 0, width: tableView.bounds.width, height: footer.arrangedSubviews.isEmpty ? 12 : 72)
    tableView.tableFooterView = footer
  }

  /// 表格只显示当前快照内的非空分组。
  override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

  /// 已经显示过的正文使用实际高度，避免历史行重新退回短行估算后将滚动位置拉回。
  override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
  {
    cachedRowHeight(at: indexPath) ?? UITableView.automaticDimension
  }

  /// UIKit 的整体内容估算同样复用实际高度，新增行仍由系统自动量测。
  override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath)
    -> CGFloat
  {
    cachedRowHeight(at: indexPath) ?? tableView.estimatedRowHeight
  }

  /// 高度缓存只用于同一内容、宽度和字体等级，不跨旋转、正文展开或系统字体变化复用。
  private func cachedRowHeight(at indexPath: IndexPath) -> CGFloat? {
    guard path.isEmpty, snapshot.feed != nil, sections.indices.contains(indexPath.section),
      sections[indexPath.section].1.indices.contains(indexPath.row)
    else { return nil }
    let item = sections[indexPath.section].1[indexPath.row]
    guard let cached = rowHeights[item.id], cached.item == item,
      abs(cached.width - tableView.bounds.width) < 1,
      cached.category == traitCollection.preferredContentSizeCategory
    else { return nil }
    return cached.height
  }

  /// 仅记录已经布局并即将展示的系统单元格，不自行计算文本或图片的排版尺寸。
  override func tableView(
    _ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath
  ) {
    guard path.isEmpty, snapshot.feed != nil, sections.indices.contains(indexPath.section),
      sections[indexPath.section].1.indices.contains(indexPath.row), cell.bounds.height > 0
    else { return }
    let item = sections[indexPath.section].1[indexPath.row]
    rowHeights[item.id] = (
      item, cell.bounds.height, tableView.bounds.width, traitCollection.preferredContentSizeCategory
    )
  }

  /// 每组行数由当前权限投影决定。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    let count = sections[section].1.count
    return usesGrid ? (count + gridColumns - 1) / gridColumns : count
  }

  /// 分组名称保留前端本地化文案。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    sections[section].0
  }

  /// 系统内容配置提供多行说明、禁用、危险动作和勾选反馈。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    if usesGrid { return gridCell(at: indexPath) }
    let item = sections[indexPath.section].1[indexPath.row]
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    var content = cell.defaultContentConfiguration()
    content.text = item.title
    content.secondaryText = item.subtitle
    content.textProperties.numberOfLines = 0
    content.secondaryTextProperties.numberOfLines = 0
    content.image = item.icon.flatMap { NavigationSymbols.image($0) }
    content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
    content.imageProperties.tintColor = item.destructive == true ? .systemRed : view.tintColor
    content.textProperties.color = item.destructive == true ? .systemRed : .label
    if let image = item.image {
      content.image = UIImage(systemName: "photo")
      content.imageProperties.maximumSize = CGSize(width: 56, height: 84)
      content.imageProperties.reservedLayoutSize = CGSize(width: 56, height: 84)
      content.imageProperties.cornerRadius = 6
      content.imageProperties.accessibilityIgnoresInvertColors = true
      cell.accessibilityValue = "海报加载中"
      imageTasks.append(
        Task { [weak cell, images] in
          let poster = await images.image(image)
          guard !Task.isCancelled, let cell else { return }
          var updated = cell.contentConfiguration as? UIListContentConfiguration
          updated?.image = poster ?? UIImage(systemName: "photo")
          if poster != nil { updated?.imageProperties.tintColor = nil }
          cell.contentConfiguration = updated
          cell.accessibilityValue = poster == nil ? "海报暂不可用" : "含海报"
        })
    }
    cell.contentConfiguration = content
    cell.backgroundConfiguration = .clear()
    cell.accessoryType =
      !(item.children ?? []).isEmpty
      ? .disclosureIndicator : (item.selected == true ? .checkmark : .none)
    cell.isUserInteractionEnabled = item.enabled != false
    cell.contentView.alpha = item.enabled == false ? 0.4 : 1
    cell.accessibilityIdentifier = "native-panel-item-\(item.id)"
    if item.selected == true { cell.accessibilityTraits.insert(.selected) }
    return cell
  }

  /// 等宽系统按钮按行排列，末行保留空位；动态字体和横屏变化会重新计算列数。
  private func gridCell(at indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.backgroundConfiguration = .clear()
    cell.selectionStyle = .none
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .fill
    stack.distribution = .fillEqually
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    let rows = sections[indexPath.section].1
    for column in 0..<gridColumns {
      let index = indexPath.row * gridColumns + column
      stack.addArrangedSubview(index < rows.count ? gridButton(rows[index]) : UIView())
    }
    cell.contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 4),
      stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -4),
      stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4),
    ])
    return cell
  }

  /// 图标与名称属于同一可访问按钮；普通点击打开功能，长按提供固定等次要动作。
  private func gridButton(_ item: NativePanelItem) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    // Sheet 展开时底页会被系统 dim，前景控件不能继承底页 tint；禁用仍由按钮自身状态表达。
    configuration.baseForegroundColor = .label
    configuration.title = item.title
    configuration.image = item.icon.flatMap {
      NavigationSymbols.image($0, configuration: UIImage.SymbolConfiguration(pointSize: 32))
    }
    configuration.imagePlacement = .top
    configuration.imagePadding = 12
    configuration.titleAlignment = .center
    configuration.titleLineBreakMode = .byWordWrapping
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 14, leading: 4, bottom: 14, trailing: 4)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      incoming in
      var attributes = incoming
      attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
      return attributes
    }
    let button = UIButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] _ in self?.selectGridItem(item.id) })
    button.tintAdjustmentMode = .normal
    button.titleLabel?.numberOfLines = 2
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.imageView?.contentMode = .scaleAspectFit
    button.imageView?.layer.cornerRadius = 10
    button.imageView?.clipsToBounds = true
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
    button.isEnabled = item.enabled != false
    button.accessibilityIdentifier = "native-panel-item-\(item.id)"
    button.accessibilityHint = item.subtitle
    if let children = item.children, !children.isEmpty {
      button.menu = UIMenu(
        children: children.map { child in
          UIAction(
            title: child.title, image: child.icon.flatMap { NavigationSymbols.image($0) },
            attributes: child.enabled == false ? .disabled : [],
            state: child.selected == true ? .on : .off
          ) { [weak self] _ in self?.selectGridItem(item.id, childID: child.id) }
        })
      button.accessibilityHint = [item.subtitle, "长按可查看操作"].compactMap { $0 }.joined(separator: "，")
    }
    if let image = item.image {
      button.accessibilityValue = "图标加载中"
      imageTasks.append(
        Task { [weak button, images] in
          let loaded = await images.image(image)
          guard !Task.isCancelled, let button else { return }
          if let thumbnail = loaded?.preparingThumbnail(of: CGSize(width: 48, height: 48)) {
            button.configuration?.image = thumbnail.withRenderingMode(.alwaysOriginal)
            button.accessibilityValue = "插件图标已加载"
          } else {
            button.accessibilityValue = "默认图标"
          }
        })
    }
    return button
  }

  /// 点击时重新查找最新声明，避免搜索、固定或权限变化后执行已失效的网格动作。
  private func selectGridItem(_ id: String, childID: String? = nil) {
    guard let item = sections.flatMap(\.1).first(where: { $0.id == id }), item.enabled != false
    else { return }
    if let childID {
      guard let child = item.children?.first(where: { $0.id == childID }), child.enabled != false
      else { return }
      onEvent("select", child.id, snapshot.feed?.id, child.keepOpen == true)
    } else if let primary = item.children?.first(where: { $0.primary == true }) {
      guard primary.enabled != false else { return }
      onEvent("select", primary.id, snapshot.feed?.id, primary.keepOpen == true)
    } else {
      select(item)
    }
  }

  /// 子菜单由系统导航栈承载，业务动作只回传项目标识并由网页再次复核。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard !usesGrid, sections.indices.contains(indexPath.section),
      sections[indexPath.section].1.indices.contains(indexPath.row)
    else { return }
    select(sections[indexPath.section].1[indexPath.row])
  }

  /// 原生只选择当前网页声明，打开详情和执行权限检查仍由原 Vue 回调负责。
  private func select(_ item: NativePanelItem) {
    guard item.enabled != false else { return }
    tableView.endEditing(true)
    if !(item.children ?? []).isEmpty {
      let child = NativePanelController(
        snapshot: snapshot, path: path + [item.id], images: images, onEvent: onEvent,
        onClose: onClose)
      child.view.tintColor = view.tintColor
      navigationController?.pushViewController(child, animated: true)
    } else {
      onEvent("select", item.id, snapshot.feed?.id, item.keepOpen == true)
    }
  }

  /// 输入经过短暂合并后同步原有搜索词，避免每个组合输入字符都触发跨进程刷新。
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    queryTask?.cancel()
    let query = String(searchText.prefix(256))
    queryTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
      self?.onEvent("query", nil, query, true)
    }
  }

  /// 搜索键只收起键盘，搜索类型和来源仍由可见结果列表选择。
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    queryTask?.cancel()
    onEvent("query", nil, String((searchBar.text ?? "").prefix(256)), true)
    searchBar.resignFirstResponder()
  }
}
