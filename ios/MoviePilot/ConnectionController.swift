import MoviePilotCore
import UIKit
import WebKit

/// 管理已保存的服务与新增地址，切换后使用各实例独立的原生认证和网页容器。
@MainActor
final class ConnectionController: UIViewController, UITextFieldDelegate {
  private let instances: InstanceStore
  private let onConnect: (SavedInstance) -> Void
  private let addressField = UITextField()
  private let errorLabel = UILabel()
  private let savedServices = UIStackView()

  /// 接收实例存储与连接结果，不把账号数据引入原生配置。
  init(instances: InstanceStore, onConnect: @escaping (SavedInstance) -> Void) {
    self.instances = instances
    self.onConnect = onConnect
    super.init(nibName: nil, bundle: nil)
  }

  /// 此控制器由代码建立，不支持 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init(instances:onConnect:)") }

  /// 历史服务可直接连接；新增地址仍走原有校验和键盘避让路径。
  override func viewDidLoad() {
    super.viewDidLoad()
    let previous = instances.selected ?? instances.instances.last
    title = "连接 MoviePilot"
    let header = AccountAppearance.header(
      title: "连接你的服务", subtitle: "选择已保存的服务，或添加新的 MoviePilot 地址。")
    savedServices.axis = .vertical
    savedServices.spacing = 12
    refreshSavedServices()
    let addressLabel = UILabel()
    addressLabel.text = "添加服务地址"
    addressLabel.font = .preferredFont(forTextStyle: .subheadline)
    addressLabel.adjustsFontForContentSizeCategory = true
    addressField.placeholder = "https://moviepilot.example.com"
    addressField.accessibilityLabel = "MoviePilot 服务地址"
    addressField.borderStyle = .none
    addressField.backgroundColor = AccountAppearance.surface(for: previous?.id)
    addressField.layer.cornerRadius = 16
    addressField.layer.cornerCurve = .continuous
    addressField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 48))
    addressField.leftViewMode = .always
    addressField.keyboardType = .URL
    addressField.textContentType = .URL
    addressField.autocorrectionType = .no
    addressField.autocapitalizationType = .none
    addressField.returnKeyType = .go
    addressField.clearButtonMode = .whileEditing
    addressField.delegate = self
    addressField.font = .preferredFont(forTextStyle: .body)
    addressField.adjustsFontForContentSizeCategory = true
    errorLabel.numberOfLines = 0
    errorLabel.textColor = .systemRed
    errorLabel.font = .preferredFont(forTextStyle: .footnote)
    errorLabel.adjustsFontForContentSizeCategory = true
    errorLabel.isHidden = true
    let configuration = AccountAppearance.primaryButton(title: "连接")
    let connect = UIButton(
      configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.submit() })
    let note = UILabel()
    note.text = "支持 HTTP 和 HTTPS。账号信息仅由你的 MoviePilot 服务处理。"
    note.font = .preferredFont(forTextStyle: .footnote)
    note.adjustsFontForContentSizeCategory = true
    note.textColor = .secondaryLabel
    note.numberOfLines = 0
    connect.accessibilityLabel = "连接"
    let field = UIStackView(arrangedSubviews: [addressLabel, addressField])
    field.axis = .vertical
    field.spacing = 10
    let stack = UIStackView(
      arrangedSubviews: [header, savedServices, field, errorLabel, connect, note])
    AccountAppearance.install(stack, in: self, instance: previous?.id)
    NSLayoutConstraint.activate([
      addressField.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
      connect.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
    ])
    if let previous {
      addressField.text = previous.address.url.absoluteString
      _ = showCompatibilityError(previous.address)
    }
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
        errorLabel.text = "地址中不要包含账号或密码。连接后再安全登录。"
      case ServerAddressError.queryOrFragmentNotAllowed:
        errorLabel.text = "请输入服务根地址，不要包含查询参数或 # 后的页面路径。"
      case is ServerAddressError:
        errorLabel.text = "请输入包含 http:// 或 https:// 的完整服务地址。"
      default:
        showStorageError()
        return
      }
      errorLabel.isHidden = false
      UIAccessibility.post(notification: .announcement, argument: errorLabel.text)
    }
  }

  /// 历史选择与手动输入共用地址校验，始终复用该地址原来的实例标识。
  private func connect(_ address: ServerAddress) throws {
    guard !showCompatibilityError(address) else { return }
    let instance = try instances.select(address)
    view.endEditing(true)
    onConnect(instance)
  }

  /// 使用可换行的原生按钮列出完整地址，端口和子路径可区分内外网或开发实例。
  private func refreshSavedServices() {
    for view in savedServices.arrangedSubviews {
      savedServices.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    let values = instances.instances
    savedServices.isHidden = values.isEmpty
    guard !values.isEmpty else { return }
    let title = UILabel()
    title.text = "已保存的服务"
    title.font = .preferredFont(forTextStyle: .headline)
    title.adjustsFontForContentSizeCategory = true
    title.accessibilityTraits = .header
    savedServices.addArrangedSubview(title)
    for instance in values.reversed() {
      let address = instance.address.url.absoluteString
      var configuration = UIButton.Configuration.tinted()
      configuration.title = address
      configuration.subtitle = instance.id == instances.selected?.id ? "当前服务" : "点按切换"
      configuration.image = UIImage(systemName: "server.rack")
      configuration.imagePadding = 12
      configuration.titleAlignment = .leading
      configuration.titleLineBreakMode = .byCharWrapping
      configuration.baseForegroundColor = AccountAppearance.accent(for: instance.id)
      configuration.background.backgroundColor = AccountAppearance.surface(for: instance.id)
      configuration.cornerStyle = .large
      configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 14, leading: 14, bottom: 14, trailing: 14)
      let button = UIButton(
        configuration: configuration,
        primaryAction: UIAction { [weak self] _ in
          guard let self else { return }
          do { try self.connect(instance.address) } catch { self.showStorageError() }
        })
      button.contentHorizontalAlignment = .leading
      button.titleLabel?.numberOfLines = 0
      button.accessibilityIdentifier = "saved-service-\(address)"
      let remove = UIButton(
        type: .system,
        primaryAction: UIAction { [weak self] _ in self?.confirmForget(instance) })
      remove.setImage(UIImage(systemName: "trash"), for: .normal)
      remove.tintColor = .secondaryLabel
      remove.accessibilityLabel = "删除服务 \(address)"
      let row = UIStackView(arrangedSubviews: [button, remove])
      row.spacing = 8
      row.alignment = .center
      NSLayoutConstraint.activate([
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        remove.widthAnchor.constraint(equalToConstant: 44),
        remove.heightAnchor.constraint(equalToConstant: 44),
      ])
      savedServices.addArrangedSubview(row)
    }
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
        self.refreshSavedServices()
      } catch { self.showStorageError() }
    }
  }

  /// 本地持久化失败不误报地址错误，也不回显底层系统信息。
  private func showStorageError() {
    errorLabel.text = "未能更新已保存的服务，请重试。"
    errorLabel.isHidden = false
    UIAccessibility.post(notification: .announcement, argument: errorLabel.text)
  }

  /// 浏览器不支持的地址停留在可编辑的配置页，不让原生 API 成功掩盖网页无法加载。
  private func showCompatibilityError(_ address: ServerAddress) -> Bool {
    guard let message = address.webCompatibilityError else { return false }
    errorLabel.text = message
    errorLabel.isHidden = false
    UIAccessibility.post(notification: .announcement, argument: message)
    return true
  }
}
