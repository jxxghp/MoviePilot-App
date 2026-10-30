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
  private var errorMessage: String?
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
    navigationController?.navigationBar.prefersLargeTitles = true
    navigationItem.largeTitleDisplayMode = .always
    tableView.accessibilityIdentifier = "server-connections"
    tableView.backgroundColor = AccountAppearance.background(for: previous?.id)
    tableView.tintColor = AccountAppearance.accent(for: previous?.id)
    tableView.keyboardDismissMode = .interactive
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 64
    tableView.sectionHeaderTopPadding = 12
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
    if let previous {
      addressField.text = previous.address.url.absoluteString
      _ = showCompatibilityError(previous.address)
    }
  }

  /// 尚无历史时仅展示添加服务，已有记录时在上方增加服务分组。
  override func numberOfSections(in tableView: UITableView) -> Int { addressSection + 1 }

  /// 地址输入和连接操作各占一行，已保存服务保持整行可点选。
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == addressSection ? 2 : savedInstances.count
  }

  /// 使用系统分组标题，避免重复品牌和大段介绍挤占服务列表。
  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    section == addressSection ? "添加服务" : "已保存的服务"
  }

  /// 手势提示与地址反馈跟随各自分组，大字体时可完整换行。
  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    if section != addressSection { return "点按服务切换，向左滑动可删除。" }
    return errorMessage ?? "支持 HTTP 和 HTTPS。账号信息仅由你的 MoviePilot 服务处理。"
  }

  /// 地址校验错误沿用系统页脚布局，以颜色和朗读同时反馈。
  override func tableView(
    _ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int
  ) {
    guard let footer = view as? UITableViewHeaderFooterView else { return }
    footer.textLabel?.textColor =
      section == addressSection && errorMessage != nil ? .systemRed : .secondaryLabel
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
      content.textProperties.numberOfLines = 0
      content.textProperties.lineBreakMode = .byCharWrapping
      content.image = UIImage(systemName: "server.rack")
      content.imageProperties.tintColor = tableView.tintColor
      if instance.id == instances.selected?.id {
        content.secondaryText = "当前服务"
        cell.accessoryType = .checkmark
      } else {
        cell.accessoryType = .disclosureIndicator
      }
      cell.contentConfiguration = content
      cell.accessibilityIdentifier = "saved-service-\(instance.address.url.absoluteString)"
      return cell
    }
    cell.selectionStyle = .none
    let control: UIView
    if indexPath.row == 0 {
      control = addressField
    } else {
      var configuration = UIButton.Configuration.plain()
      configuration.title = "连接"
      configuration.image = UIImage(systemName: "arrow.right")
      configuration.imagePlacement = .trailing
      configuration.imagePadding = 8
      let button = UIButton(
        configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.submit() })
      button.accessibilityLabel = "连接"
      control = button
    }
    control.translatesAutoresizingMaskIntoConstraints = false
    cell.contentView.addSubview(control)
    let margins = cell.contentView.layoutMarginsGuide
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
      control.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      control.topAnchor.constraint(equalTo: margins.topAnchor, constant: 4),
      control.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: -4),
      control.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
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

  /// 左滑才显示系统删除按钮；禁用整行滑到底即执行，仍需明确确认清理。
  override func tableView(
    _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
  ) -> UISwipeActionsConfiguration? {
    guard indexPath.section != addressSection else { return nil }
    let instance = savedInstances[indexPath.row]
    let remove = UIContextualAction(style: .destructive, title: "删除") {
      [weak self] _, _, complete in
      guard let self else {
        complete(false)
        return
      }
      complete(true)
      self.confirmForget(instance)
    }
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
        self.errorMessage = nil
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
    errorMessage = message
    tableView.reloadSections(IndexSet(integer: addressSection), with: .none)
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  /// 浏览器不支持的地址停留在可编辑的配置页，不让原生 API 成功掩盖网页无法加载。
  private func showCompatibilityError(_ address: ServerAddress) -> Bool {
    guard let message = address.webCompatibilityError else { return false }
    showError(message)
    return true
  }
}
