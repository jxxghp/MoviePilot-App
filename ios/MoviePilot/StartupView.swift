import UIKit

/// 延续系统启动页的品牌画面；服务未就绪时提供原生等待与恢复入口。
@MainActor
final class StartupView: UIView {
  private let instance: UUID
  private var serviceMessage: UILabel?

  /// 图形始终来自本地资源；首帧按实例偏好选择底色，无历史时跟随系统明暗。
  init(instance: UUID) {
    self.instance = instance
    super.init(frame: .zero)
    overrideUserInterfaceStyle = AccountAppearance.interfaceStyle(for: instance)
    backgroundColor = AccountAppearance.background(for: instance)
    accessibilityIdentifier = "native-startup-screen"
    isAccessibilityElement = true
    accessibilityLabel = "MoviePilot 正在准备页面"
    let icon = UIImageView(image: UIImage(named: "LaunchMark"))
    icon.contentMode = .scaleAspectFit
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.isAccessibilityElement = false
    addSubview(icon)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 128),
      icon.heightAnchor.constraint(equalToConstant: 128),
      icon.centerXAnchor.constraint(equalTo: centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  /// 此视图仅由原生宿主创建，系统启动页使用独立的静态 storyboard。
  required init?(coder: NSCoder) { fatalError("Use init(instance:)") }

  /// 仅在暂时性服务故障后展开等待卡片；轮询更新文案时保留原有按钮与辅助功能焦点。
  func showServiceWait(
    message: String, retry: @escaping () -> Void, changeAddress: @escaping () -> Void
  ) {
    if let serviceMessage {
      serviceMessage.text = message
      return
    }
    for view in subviews { view.removeFromSuperview() }
    isAccessibilityElement = false
    let scroll = UIScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroll)
    let content = UIView()
    content.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(content)
    let card = UIView()
    card.accessibilityIdentifier = "native-service-status"
    card.backgroundColor = AccountAppearance.surface(for: instance)
    card.layer.cornerRadius = 28
    card.layer.cornerCurve = .continuous
    card.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(card)
    let icon = UIImageView(image: UIImage(named: "LaunchMark"))
    icon.contentMode = .scaleAspectFit
    icon.isAccessibilityElement = false
    let mark = UIView()
    icon.translatesAutoresizingMaskIntoConstraints = false
    mark.addSubview(icon)
    let kicker = label("服务状态", style: .caption1)
    kicker.textColor = AccountAppearance.accent(for: instance)
    let heading = label("正在等待 MoviePilot", style: .title2)
    if let descriptor = heading.font.fontDescriptor.withSymbolicTraits(.traitBold) {
      heading.font = UIFont(descriptor: descriptor, size: 0)
    }
    heading.accessibilityTraits = .header
    let detail = label("后端服务就绪后，将自动继续登录或进入首页。", style: .body)
    detail.textColor = .secondaryLabel
    let status = label(message, style: .footnote)
    status.textAlignment = .natural
    status.accessibilityIdentifier = "native-service-status-message"
    serviceMessage = status
    let spinner = UIActivityIndicatorView(style: .medium)
    spinner.color = AccountAppearance.accent(for: instance)
    spinner.startAnimating()
    spinner.setContentHuggingPriority(.required, for: .horizontal)
    let progress = UIStackView(arrangedSubviews: [spinner, status])
    progress.spacing = 12
    progress.alignment = .center
    let again = UIButton(configuration: AccountAppearance.primaryButton(title: "立即重试"))
    again.accessibilityIdentifier = "native-service-retry"
    again.addAction(UIAction { _ in retry() }, for: .touchUpInside)
    var changeStyle = UIButton.Configuration.plain()
    changeStyle.title = "更改地址"
    changeStyle.baseForegroundColor = AccountAppearance.accent(for: instance)
    let change = UIButton(configuration: changeStyle)
    change.accessibilityIdentifier = "native-service-change-address"
    change.addAction(UIAction { _ in changeAddress() }, for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [
      mark, kicker, heading, detail, progress, again, change,
    ])
    stack.axis = .vertical
    stack.spacing = 16
    stack.setCustomSpacing(24, after: detail)
    stack.setCustomSpacing(24, after: progress)
    stack.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(stack)
    let width = card.widthAnchor.constraint(equalToConstant: 460)
    width.priority = .defaultHigh
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      content.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
      card.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      card.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 24),
      card.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
      card.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -40), width,
      stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
      stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
      stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
      mark.heightAnchor.constraint(equalToConstant: 88),
      icon.widthAnchor.constraint(equalToConstant: 80),
      icon.heightAnchor.constraint(equalToConstant: 80),
      icon.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
      again.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
      change.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
    ])
    UIAccessibility.post(notification: .screenChanged, argument: heading)
  }

  /// 等待页文字使用系统动态字号并允许换行，横屏与辅助功能字号由外层滚动承载。
  private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: style)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textAlignment = .center
    return label
  }
}
