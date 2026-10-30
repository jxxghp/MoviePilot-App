import MoviePilotCore
import UIKit
import WebKit

/// 用原生分组列表管理服务，切换后使用各实例独立的认证和网页容器。
@MainActor
final class ConnectionController: UITableViewController, UITextFieldDelegate {
  private let instances: InstanceStore
  private let onConnect: (SavedInstance) -> Void
  private let addressField = UITextField()
  private var savedInstances: [SavedInstance] = []
  private let errorLabel = UILabel()
  /// 有历史记录时将添加表单置于服务分组之后。
  private var addressSection: Int { savedInstances.isEmpty ? 0 : 1 }

  /// 接收实例存储与连接结果，不把账号数据引入原生配置。
  init(instances: InstanceStore, onConnect: @escaping (SavedInstance) -> Void) {
    self.instances = instances
    self.onConnect = onConnect
    super.init(style: .insetGrouped)
  }

  /// 此控制器由代码建立，不支持 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init(instances:onConnect:)") }

  /// 服务、输入与连接均使用系统列表布局，键盘和大字体由表格滚动承载。
  override func viewDidLoad() {
    super.viewDidLoad()
    let previous = instances.selected ?? instances.instances.last
    savedInstances = Array(instances.instances.reversed())
    title = "连接服务"
    navigationController?.navigationBar.prefersLargeTitles = false
    navigationItem.largeTitleDisplayMode = .never
    tableView.accessibilityIdentifier = "server-connections"
    tableView.backgroundColor = AccountAppearance.background(for: previous?.id)
    tableView.tintColor = AccountAppearance.accent(for: previous?.id)
    tableView.keyboardDismissMode = .interactive
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 64
    tableView.sectionHeaderTopPadding = 8
    addressField.placeholder = "https://moviepilot.example.com"
    addressField.accessibilityLabel = "MoviePilot 服务地址"
    addressField.keyboardType = .URL
    addressField.textContentType = .URL
    addressField.autocorrectionType = .no
    addressField.autocapitalizationType = .none
    addressField.returnKeyType = .go
    addressField.clearButtonMode = .whileEditing
    addressField.delegate = self
    addressField.font = .preferredFont(forTextStyle: .body)
    addressField.adjustsFontForContentSizeCategory = true
    installConnectionFooter()
    if let previous {
      addressField.text = previous.address.url.absoluteString
      _ = showCompatibilityError(previous.address)
    }
  }

  /// 尚无历史时仅展示添加服务，已有记录时在上方增加服务分组。
  override func numberOfSections(in tableView: UITableView) -> Int { addressSection + 1 }

  /// 添加地址使用单独输入行，已保存服务保持整行可点选。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == addressSection ? 1 : savedInstances.count
  }

  /// 使用系统分组标题，避免重复品牌和大段介绍挤占服务列表。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    section == addressSection ? "添加服务" : "已保存的服务"
  }

  /// 手势提示随列表分组显示，输入说明集中在独立的连接按钮下方。
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    section == addressSection ? nil : "点按切换 · 左滑删除"
  }

  /// 表格页尾按实际宽度和动态字号测量，横屏与键盘出现后仍可滚动访问。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    guard let footer = tableView.tableFooterView else { return }
    footer.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 16, leading: max(20, tableView.layoutMargins.left), bottom: 28,
      trailing: max(20, tableView.layoutMargins.right))
    let width = tableView.bounds.width
    let height = footer.systemLayoutSizeFitting(
      CGSize(width: width, height: 0), withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    ).height
    guard abs(footer.frame.width - width) > 0.5 || abs(footer.frame.height - height) > 0.5 else {
      return
    }
    footer.frame.size = CGSize(width: width, height: height)
    tableView.tableFooterView = footer
  }

  /// 将连接操作与地址输入分开，保留原生胶囊按钮和可完整换行的反馈说明。
  private func installConnectionFooter() {
    let connect = UIButton(
      configuration: AccountAppearance.primaryButton(title: "连接"),
      primaryAction: UIAction { [weak self] _ in self?.submit() })
    connect.accessibilityLabel = "连接"
    errorLabel.textColor = .systemRed
    errorLabel.font = .preferredFont(forTextStyle: .footnote)
    errorLabel.adjustsFontForContentSizeCategory = true
    errorLabel.numberOfLines = 0
    errorLabel.isHidden = true
    let note = UILabel()
    note.text = "支持 HTTP 和 HTTPS。登录信息按服务分别保存。"
    note.font = .preferredFont(forTextStyle: .footnote)
    note.adjustsFontForContentSizeCategory = true
    note.textColor = .secondaryLabel
    note.numberOfLines = 0
    note.textAlignment = .center
    let stack = UIStackView(arrangedSubviews: [errorLabel, connect, note])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    let footer = UIView()
    footer.addSubview(stack)
    let margins = footer.layoutMarginsGuide
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      stack.topAnchor.constraint(equalTo: margins.topAnchor),
      stack.bottomAnchor.constraint(equalTo: margins.bottomAnchor),
      connect.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
    ])
    tableView.tableFooterView = footer
  }

  /// 列表统一沿用当前服务的外观；完整 URL 和勾选标记清楚区分各地址。
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    let previous = instances.selected ?? instances.instances.last
    cell.backgroundColor = AccountAppearance.surface(for: previous?.id)
    if indexPath.section != addressSection {
      let instance = savedInstances[indexPath.row]
      var content = cell.defaultContentConfiguration()
      content.text = instance.address.url.absoluteString
      content.textProperties.font = .preferredFont(forTextStyle: .callout)
      content.textProperties.numberOfLines = 0
      content.textProperties.lineBreakMode = .byCharWrapping
      content.image = UIImage(
        systemName: "server.rack", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19))
      content.imageProperties.tintColor = tableView.tintColor
      if instance.id == instances.selected?.id {
        content.secondaryText = "当前服务"
        cell.accessoryType = .checkmark
      } else {
        cell.accessoryType = .disclosureIndicator
      }
      cell.contentConfiguration = content
      cell.accessibilityIdentifier = "saved-service-\(instance.address.url.absoluteString)"
      cell.accessibilityCustomActions = [
        UIAccessibilityCustomAction(name: "删除服务") { [weak self] _ in
          self?.confirmForget(instance)
          return self != nil
        }
      ]
      return cell
    }
    cell.selectionStyle = .none
    addressField.translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.addSubview(addressField)
    let margins = cell.contentView.layoutMarginsGuide
    NSLayoutConstraint.activate([
      addressField.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
      addressField.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      addressField.topAnchor.constraint(equalTo: margins.topAnchor, constant: 4),
      addressField.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -4),
      addressField.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
    ])
    return cell
  }

  /// 点选历史地址与手动输入共用校验，始终复用该地址原来的实例标识。
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard indexPath.section != addressSection else { return }
    do { try connect(savedInstances[indexPath.row].address) } catch { showStorageError() }
  }

  /// 只有已保存服务提供编辑手势，输入表单不出现删除操作。
  override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    indexPath.section != addressSection
  }

  /// 透明动作背景搭配双色圆形系统图标，保留系统左滑、读屏和删除确认。
  override func tableView(
    _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    guard indexPath.section != addressSection else { return nil }
    let instance = savedInstances[indexPath.row]
    let remove = UIContextualAction(style: .destructive, title: nil) {
      [weak self] _, _, complete in
      guard let self else {
        complete(false)
        return
      }
      complete(true)
      self.confirmForget(instance)
    }
    let symbol = UIImage.SymbolConfiguration(pointSize: 44).applying(
      UIImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
    let image = UIImage(systemName: "trash.circle.fill", withConfiguration: symbol)?
      .withRenderingMode(.alwaysOriginal)
    image?.accessibilityLabel = "删除"
    remove.image = image
    remove.backgroundColor = .clear
    let configuration = UISwipeActionsConfiguration(actions: [remove])
    configuration.performsFirstActionWithFullSwipe = false
    return configuration
  }

  /// URL 键盘的前往键与连接按钮采用相同校验路径。
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    submit()
    return false
  }

  /// 在本地校验地址后移交容器；网络失败在容器内提供重试与更改地址。
  private func submit() {
    do {
      let address = try ServerAddress(addressField.text ?? "")
      try connect(address)
    } catch {
      switch error {
      case ServerAddressError.credentialsNotAllowed:
        showError("地址中不要包含账号或密码。连接后再安全登录。")
      case ServerAddressError.queryOrFragmentNotAllowed:
        showError("请输入服务根地址，不要包含查询参数或 # 后的页面路径。")
      case is ServerAddressError:
        showError("请输入包含 http:// 或 https:// 的完整服务地址。")
      default:
        showStorageError()
      }
    }
  }

  /// 历史选择与手动输入使用同一入口，确认可展示网页后才保存选择。
  private func connect(_ address: ServerAddress) throws {
    guard !showCompatibilityError(address) else { return }
    let instance = try instances.select(address)
    view.endEditing(true)
    onConnect(instance)
  }

  /// 删除需明确确认，避免切换服务时误清除该地址的账号与会话。
  private func confirmForget(_ instance: SavedInstance) {
    view.endEditing(true)
    let alert = UIAlertController(
      title: "删除已保存的服务？",
      message: "\(instance.address.url.absoluteString)\n将清除此服务保存的账号密码、登录状态和网页数据。",
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(
      UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
        self?.forget(instance)
      })
    present(alert, animated: true)
  }

  /// 清空独立数据仓后移除凭据与配置；实例清理接口也支持尚未创建 WebView 的冷启动。
  private func forget(_ instance: SavedInstance) {
    view.isUserInteractionEnabled = false
    Task { [weak self] in
      guard let self else { return }
      defer { self.view.isUserInteractionEnabled = true }
      do {
        let store = WKWebsiteDataStore(forIdentifier: instance.id)
        await store.removeData(
          ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        try self.instances.forget(instance)
        if (try? ServerAddress(self.addressField.text ?? "")) == instance.address {
          self.addressField.text = nil
        }
        self.errorLabel.isHidden = true
        self.savedInstances = Array(self.instances.instances.reversed())
        self.tableView.reloadData()
      } catch { self.showStorageError() }
    }
  }

  /// 本地持久化失败不误报地址错误，也不回显底层系统信息。
  private func showStorageError() {
    showError("未能更新已保存的服务，请重试。")
  }

  /// 页脚保持输入值，更新错误后为 VoiceOver 朗读具体原因。
  private func showError(_ message: String) {
    errorLabel.text = message
    errorLabel.isHidden = false
    view.endEditing(true)
    view.setNeedsLayout()
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  /// 浏览器不支持的地址停留在可编辑的配置页，不让原生 API 成功掩盖网页无法加载。
  private func showCompatibilityError(_ address: ServerAddress) -> Bool {
    guard let message = address.webCompatibilityError else { return false }
    showError(message)
    return true
  }
}
