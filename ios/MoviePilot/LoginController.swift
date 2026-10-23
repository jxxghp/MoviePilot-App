import MoviePilotCore
import UIKit

/// 原生框架登录表单，只复用现有认证 API；业务页面与特殊认证继续使用原网页。
@MainActor
final class LoginController: UIViewController, UITextFieldDelegate {
  private let instance: SavedInstance
  private let client: AuthenticationClient
  private let savedToken: String?
  private let onExpired: () -> Void
  private let onAuthenticated: (AuthenticationResult, Bool) -> Void
  private let onWebLogin: () -> Void
  private let onConnection: () -> Void
  private let username = UITextField()
  private let password = UITextField()
  private let otp = UITextField()
  private let remember = UISwitch()
  private let message = UILabel()
  private let login = UIButton()
  private let webLogin = UIButton()
  private var task: Task<Void, Never>?
  private var retryAt: Date?
  private var retryTimer: Timer?
  private var initialized = true

  /// 回调只交付认证结果，不将密码传给 Scene、导航桥或持久化层。
  init(
    instance: SavedInstance, savedToken: String?, onExpired: @escaping () -> Void,
    onAuthenticated: @escaping (AuthenticationResult, Bool) -> Void,
    onWebLogin: @escaping () -> Void, onConnection: @escaping () -> Void
  ) {
    self.instance = instance
    self.savedToken = savedToken
    self.onExpired = onExpired
    self.onAuthenticated = onAuthenticated
    self.onWebLogin = onWebLogin
    self.onConnection = onConnection
    client = AuthenticationClient(address: instance.address)
    super.init(nibName: nil, bundle: nil)
  }

  /// 登录表单由当前实例生成，不使用 storyboard 或输入状态恢复。
  required init?(coder: NSCoder) { fatalError("Use init(instance:...)") }

  /// 系统输入、密码自动填充、OTP 和键盘避让保持原生可访问语义。
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "登录"
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "更改地址", primaryAction: UIAction { [weak self] _ in self?.onConnection() })
    let header = AccountAppearance.header(title: "欢迎回来", subtitle: "登录你的服务，继续管理订阅与媒体。")
    let serverIcon = UIImageView(image: UIImage(systemName: "server.rack"))
    serverIcon.tintColor = AccountAppearance.accent
    serverIcon.contentMode = .scaleAspectFit
    serverIcon.widthAnchor.constraint(equalToConstant: 20).isActive = true
    let address = UILabel()
    address.text = instance.address.url.absoluteString
    address.font = .preferredFont(forTextStyle: .footnote)
    address.adjustsFontForContentSizeCategory = true
    address.textColor = .secondaryLabel
    address.numberOfLines = 0
    let server = UIStackView(arrangedSubviews: [serverIcon, address])
    server.spacing = 10
    server.alignment = .center
    configure(username, label: "用户名", contentType: .username, symbol: "person")
    configure(password, label: "密码", contentType: .password, symbol: "lock")
    password.isSecureTextEntry = true
    var visibility = UIButton.Configuration.plain()
    visibility.image = UIImage(systemName: "eye")
    let reveal = UIButton(configuration: visibility)
    reveal.accessibilityLabel = "显示密码"
    reveal.frame.size = CGSize(width: 48, height: 48)
    reveal.addAction(
      UIAction { [weak self, weak reveal] _ in
        guard let self, let reveal else { return }
        self.password.isSecureTextEntry.toggle()
        reveal.configuration?.image = UIImage(
          systemName: self.password.isSecureTextEntry ? "eye" : "eye.slash")
        reveal.accessibilityLabel = self.password.isSecureTextEntry ? "显示密码" : "隐藏密码"
      }, for: .touchUpInside)
    password.rightView = reveal
    password.rightViewMode = .always
    configure(otp, label: "身份验证器验证码", contentType: .oneTimeCode, symbol: "number.shield")
    otp.keyboardType = .numberPad
    otp.isHidden = true
    let divider = UIView()
    divider.backgroundColor = .separator
    divider.heightAnchor.constraint(equalToConstant: 1 / traitCollection.displayScale).isActive =
      true
    let fields = UIStackView(arrangedSubviews: [username, divider, password, otp])
    fields.axis = .vertical
    fields.backgroundColor = .secondarySystemGroupedBackground
    fields.layer.cornerRadius = 20
    fields.layer.cornerCurve = .continuous
    fields.clipsToBounds = true
    remember.isOn = true
    remember.onTintColor = AccountAppearance.accent
    remember.accessibilityLabel = "保持登录"
    let rememberLabel = UILabel()
    rememberLabel.text = "保持登录"
    rememberLabel.font = .preferredFont(forTextStyle: .subheadline)
    rememberLabel.adjustsFontForContentSizeCategory = true
    let rememberRow = UIStackView(arrangedSubviews: [rememberLabel, remember])
    rememberRow.distribution = .equalSpacing
    rememberRow.alignment = .center
    message.font = .preferredFont(forTextStyle: .footnote)
    message.adjustsFontForContentSizeCategory = true
    message.numberOfLines = 0
    message.isHidden = true
    login.configuration = AccountAppearance.primaryButton(title: "登录")
    login.accessibilityLabel = "登录"
    login.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
    webLogin.configuration = .plain()
    webLogin.configuration?.title = "使用网页登录"
    webLogin.addAction(UIAction { [weak self] _ in self?.openWebLogin() }, for: .touchUpInside)
    let note = UILabel()
    note.text = "账号信息仅发送到当前 MoviePilot 服务。"
    note.font = .preferredFont(forTextStyle: .footnote)
    note.adjustsFontForContentSizeCategory = true
    note.textColor = .secondaryLabel
    note.textAlignment = .center
    note.numberOfLines = 0
    let form = UIStackView(arrangedSubviews: [fields, rememberRow, message, login, webLogin])
    form.axis = .vertical
    form.spacing = 16
    let stack = UIStackView(arrangedSubviews: [header, server, form, note])
    AccountAppearance.install(stack, in: self)
    NSLayoutConstraint.activate([
      username.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
      password.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
      otp.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
      login.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
      webLogin.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    prepare()
  }

  /// 离开后取消所有请求并擦除密码，迟到响应不得打开另一个实例。
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    task?.cancel()
    task = nil
    retryTimer?.invalidate()
    client.cancel()
    password.text = nil
    otp.text = nil
  }

  /// 用户名回车移到密码，密码和验证码回车只提交一次当前登录。
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if textField === username { password.becomeFirstResponder() } else { submit() }
    return false
  }

  /// 输入框保留系统自动填充及动态字号，不自行模拟安全文本控件。
  private func configure(
    _ field: UITextField, label: String, contentType: UITextContentType, symbol: String
  ) {
    field.placeholder = label
    field.accessibilityLabel = label
    field.textContentType = contentType
    field.autocapitalizationType = .none
    field.autocorrectionType = .no
    field.borderStyle = .none
    let icon = UIImageView(image: UIImage(systemName: symbol))
    icon.tintColor = .secondaryLabel
    icon.contentMode = .scaleAspectFit
    icon.frame = CGRect(x: 16, y: 0, width: 20, height: 52)
    let leading = UIView(frame: CGRect(x: 0, y: 0, width: 48, height: 52))
    leading.addSubview(icon)
    field.leftView = leading
    field.leftViewMode = .always
    field.font = .preferredFont(forTextStyle: .body)
    field.adjustsFontForContentSizeCategory = true
    field.returnKeyType = field === username ? .next : .go
    field.delegate = self
  }

  /// 初始化与令牌恢复只执行一次，服务器状态不明时保留明确重试/网页出口。
  private func prepare() {
    setBusy(true)
    setMessage("正在连接你的实例…")
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        self.setBusy(false)
        self.task = nil
      }
      do {
        self.initialized = try await self.client.isInitialized()
        guard !Task.isCancelled else { return }
        guard self.initialized else {
          self.show(AuthenticationError.notInitialized)
          self.login.configuration?.title = "在网页初始化"
          return
        }
        if let token = self.savedToken {
          do {
            let result = try await self.client.restore(token: token)
            guard !Task.isCancelled else { return }
            self.onAuthenticated(result, true)
            return
          } catch AuthenticationError.credentials { self.onExpired() }
        }
        self.setMessage(nil)
      } catch { if !Task.isCancelled { self.show(error) } }
    }
  }

  /// 用户明确提交后调用既有认证接口，OTP 挑战只展开输入，不自动重发密码。
  private func submit() {
    guard task == nil, retryAt.map({ $0 <= Date() }) ?? true else { return }
    if !initialized {
      openWebLogin()
      return
    }
    let name = username.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let secret = password.text ?? ""
    guard !name.isEmpty, !secret.isEmpty else {
      setMessage("请输入用户名和密码。", error: true)
      return
    }
    let code = otp.isHidden ? nil : otp.text
    setBusy(true)
    setMessage(nil)
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        self.setBusy(false)
        self.task = nil
      }
      do {
        let result = try await self.client.login(username: name, password: secret, otp: code)
        guard !Task.isCancelled else { return }
        self.password.text = nil
        self.otp.text = nil
        self.view.endEditing(true)
        self.onAuthenticated(result, self.remember.isOn)
      } catch AuthenticationError.otpRequired {
        self.otp.isHidden = false
        self.otp.becomeFirstResponder()
        self.show(AuthenticationError.otpRequired)
      } catch AuthenticationError.throttled(let seconds) {
        self.retryAt = Date().addingTimeInterval(Double(seconds))
        self.show(AuthenticationError.throttled(seconds))
        self.retryTimer?.invalidate()
        self.retryTimer = Timer.scheduledTimer(withTimeInterval: Double(seconds), repeats: false) {
          [weak self] _ in
          MainActor.assumeIsolated {
            self?.retryAt = nil
            self?.setBusy(false)
          }
        }
      } catch { if !Task.isCancelled { self.show(error) } }
    }
  }

  /// 特殊认证交给同一实例网页，不将密码复制到网页表单或重新发送。
  private func openWebLogin() {
    password.text = nil
    otp.text = nil
    view.endEditing(true)
    onWebLogin()
  }

  /// 请求期间限制重复提交，系统加载状态与可访问状态保持一致。
  private func setBusy(_ busy: Bool) {
    login.configuration?.showsActivityIndicator = busy
    login.isEnabled = !busy && (retryAt.map { $0 <= Date() } ?? true)
    username.isEnabled = !busy
    password.isEnabled = !busy
    otp.isEnabled = !busy
    remember.isEnabled = !busy
  }

  /// 已知失败保持准确文案，未知网络错误不泄露服务器原文。
  private func show(_ error: Error) {
    setMessage(
      (error as? AuthenticationError)?.errorDescription
        ?? AuthenticationError.unavailable.errorDescription, error: true)
    UIAccessibility.post(notification: .announcement, argument: message.text)
  }

  /// 空提示不占表单间距，失败后重新提交恢复正常语义颜色。
  private func setMessage(_ text: String?, error: Bool = false) {
    message.text = text
    message.isHidden = text == nil
    message.textColor = error ? .systemRed : .secondaryLabel
  }
}
