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
    guard !stopped, NavigationSnapshot.isImageReference(reference), let url = URL(string: reference)
    else { return nil }
    if let cached = cache.object(forKey: url as NSURL) { return cached }
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
        !self.stopped, let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(
          source, 0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300,
          ] as CFDictionary)
      else { return nil }
      let thumbnail = UIImage(cgImage: image)
      self.cache.setObject(thumbnail, forKey: url as NSURL, cost: image.width * image.height * 4)
      return thumbnail
    }
    tasks[reference] = task
    let result = await task.value
    tasks[reference] = nil
    return result
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

/// 快捷入口使用系统列表、搜索和导航，所有业务意图通过当前网页声明返回。
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
  private var headerText: String?
  private var queryTask: Task<Void, Never>?
  private var imageTasks: [Task<Void, Never>] = []

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
    NativeModalAppearance.apply(to: self)
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose() })
    navigationItem.rightBarButtonItem?.accessibilityIdentifier = "native-panel-close"
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
    updatePreferredHeight()
  }

  /// 初次呈现动画结束后再适配短内容，避免加载快照在动画中反复改变浮层几何。
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updatePreferredHeight()
  }

  /// 离开搜索页即取消尚未发送的输入，旧控制器不能把查询发给后来打开的其他面板。
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    queryTask?.cancel()
  }

  /// 只在当前面板完成过渡后量测内容；最小高度容纳导航和空状态。
  private func updatePreferredHeight() {
    guard let navigationController, navigationController.topViewController === self,
      let host = navigationController.presentingViewController,
      !navigationController.isBeingPresented, navigationController.transitionCoordinator == nil,
      !snapshot.sections.isEmpty
    else { return }
    let maximum = min(
      580,
      max(
        280,
        host.view.bounds.height - host.view.safeAreaInsets.top - host.view.safeAreaInsets.bottom
          - 170))
    let height = min(maximum, max(220, tableView.contentSize.height + 56))
    if abs(navigationController.preferredContentSize.height - height) > 2 {
      navigationController.preferredContentSize.height = height
    }
  }

  /// 搜索与分组标题属于面板内部，永远不会放在宿主渐变导航栏后方。
  func apply(_ snapshot: NativePanelSnapshot) {
    self.snapshot = snapshot
    guard isViewLoaded, renderedSnapshot != snapshot else { return }
    renderedSnapshot = snapshot
    for task in imageTasks { task.cancel() }
    imageTasks.removeAll()
    var rows = snapshot.sections.flatMap(\.items)
    var current: NativePanelItem?
    for id in path {
      current = rows.first { $0.id == id }
      rows = current?.children ?? []
    }
    title = current?.title ?? snapshot.title
    sections =
      path.isEmpty
      ? snapshot.sections.filter { !$0.items.isEmpty }.map { ($0.title, $0.items) }
      : [(nil, rows)]
    if path.isEmpty, let input = snapshot.search {
      search.placeholder = input.placeholder
      if !search.searchTextField.isFirstResponder { search.text = input.text }
    }
    configureHeader()
    configureFooter()
    tableView.reloadData()
  }

  /// 面板顶部按需要显示用户名说明和系统搜索框，宽度跟随系统列表边距。
  private func configureHeader() {
    let text = path.isEmpty ? snapshot.subtitle : nil
    let hasSearch = path.isEmpty && snapshot.search != nil
    let identity = "\(text ?? "")|\(hasSearch)"
    guard headerText != identity else { return }
    headerText = identity
    guard text != nil || hasSearch else {
      tableView.tableHeaderView = nil
      return
    }
    let height: CGFloat = (text == nil ? 0 : 38) + (hasSearch ? 58 : 0)
    let header = UIView(
      frame: CGRect(x: 0, y: 0, width: preferredContentSize.width, height: height))
    let stack = UIStackView()
    stack.axis = .vertical
    stack.translatesAutoresizingMaskIntoConstraints = false
    if let text {
      let label = UILabel()
      label.text = text
      label.textColor = .secondaryLabel
      label.font = .preferredFont(forTextStyle: .subheadline)
      label.adjustsFontForContentSizeCategory = true
      label.numberOfLines = 2
      stack.addArrangedSubview(label)
    }
    if hasSearch { stack.addArrangedSubview(search) }
    header.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -4),
    ])
    tableView.tableHeaderView = header
  }

  /// 空状态、加载和历史翻页均保留系统触点，不依赖网页无限滚动命中。
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
    if sections.allSatisfy({ $0.1.isEmpty }) && snapshot.loading != true {
      let label = UILabel()
      label.text = snapshot.emptyText ?? "暂无内容"
      label.textColor = .secondaryLabel
      label.font = .preferredFont(forTextStyle: .body)
      label.numberOfLines = 0
      label.textAlignment = .center
      footer.addArrangedSubview(label)
    }
    if path.isEmpty && snapshot.hasMore == true {
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
    footer.frame = CGRect(
      x: 0, y: 0, width: tableView.bounds.width, height: footer.arrangedSubviews.isEmpty ? 12 : 92)
    tableView.tableFooterView = footer
  }

  /// 表格只显示当前快照内的非空分组。
  override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

  /// 每组行数由当前权限投影决定。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    sections[section].1.count
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

  /// 子菜单由系统导航栈承载，业务动作只回传项目标识并由网页再次复核。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard sections.indices.contains(indexPath.section),
      sections[indexPath.section].1.indices.contains(indexPath.row)
    else { return }
    let item = sections[indexPath.section].1[indexPath.row]
    guard item.enabled != false else { return }
    tableView.endEditing(true)
    if !(item.children ?? []).isEmpty {
      let child = NativePanelController(
        snapshot: snapshot, path: path + [item.id], images: images, onEvent: onEvent,
        onClose: onClose)
      child.view.tintColor = view.tintColor
      navigationController?.pushViewController(child, animated: true)
    } else {
      onEvent("select", item.id, nil, item.keepOpen == true)
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
