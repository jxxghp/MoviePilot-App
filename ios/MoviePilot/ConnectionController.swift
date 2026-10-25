import MoviePilotCore
import UIKit

/// 配置实例地址后进入原生登录框架，全部业务表单仍使用现有网页。
@MainActor
final class ConnectionController: UIViewController, UITextFieldDelegate {
  private let instances: InstanceStore
  private let onConnect: (SavedInstance) -> Void
  private let addressField = UITextField()
  private let errorLabel = UILabel()

  /// 接收实例存储与连接结果，不把账号数据引入原生配置。
  init(instances: InstanceStore, onConnect: @escaping (SavedInstance) -> Void) {
    self.instances = instances
    self.onConnect = onConnect
    super.init(nibName: nil, bundle: nil)
  }

  /// 此控制器由代码建立，不支持 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init(instances:onConnect:)") }

  /// 建立支持动态字体和键盘避让的简洁连接表单。
  override func viewDidLoad() {
    super.viewDidLoad()
    let previous = instances.selected ?? instances.instances.last
    title = "连接 MoviePilot"
    let header = AccountAppearance.header(
      title: "连接你的服务", subtitle: "输入 MoviePilot 地址，开启熟悉的媒体管理体验。")
    let addressLabel = UILabel()
    addressLabel.text = "服务地址"
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
    note.text = "推荐使用 HTTPS；局域网地址也支持 HTTP。账号信息仅由你的 MoviePilot 服务处理。"
    note.font = .preferredFont(forTextStyle: .footnote)
    note.adjustsFontForContentSizeCategory = true
    note.textColor = .secondaryLabel
    note.numberOfLines = 0
    connect.accessibilityLabel = "连接"
    let field = UIStackView(arrangedSubviews: [addressLabel, addressField])
    field.axis = .vertical
    field.spacing = 10
    let stack = UIStackView(arrangedSubviews: [header, field, errorLabel, connect, note])
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
      guard !showCompatibilityError(address) else { return }
      let instance = try instances.select(address)
      view.endEditing(true)
      onConnect(instance)
    } catch {
      switch error {
      case ServerAddressError.insecureRemoteServer:
        errorLabel.text = "外网连接请使用 HTTPS。HTTP 仅用于局域网或本机服务。"
      case ServerAddressError.credentialsNotAllowed:
        errorLabel.text = "地址中不要包含账号或密码。连接后再安全登录。"
      case ServerAddressError.queryOrFragmentNotAllowed:
        errorLabel.text = "请输入服务根地址，不要包含查询参数或 # 后的页面路径。"
      default: errorLabel.text = "请输入完整有效的服务地址，例如 https://moviepilot.example.com。"
      }
      errorLabel.isHidden = false
      UIAccessibility.post(notification: .announcement, argument: errorLabel.text)
    }
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
