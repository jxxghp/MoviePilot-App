import UIKit

/// 连接与登录共享的品牌层级；正文使用系统语义颜色，材质交给当前 iOS。
@MainActor
enum AccountAppearance {
  static let accent = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.72, green: 0.57, blue: 1, alpha: 1)
      : UIColor(red: 0.47, green: 0.25, blue: 0.84, alpha: 1)
  }

  /// 使用现有品牌图标与系统动态字体，横屏和大字体时由外层滚动布局承载。
  static func header(title: String, subtitle: String) -> UIView {
    let icon = UIImageView(image: UIImage(named: "BrandMark"))
    icon.contentMode = .scaleAspectFit
    icon.layer.cornerRadius = 18
    icon.layer.cornerCurve = .continuous
    icon.clipsToBounds = true
    icon.isAccessibilityElement = false
    let name = UILabel()
    name.text = "MoviePilot"
    name.font = UIFont.preferredFont(forTextStyle: .title2).withTraits(.traitBold)
    name.adjustsFontForContentSizeCategory = true
    let caption = UILabel()
    caption.text = "你的媒体世界，随时连接。"
    caption.font = .preferredFont(forTextStyle: .subheadline)
    caption.adjustsFontForContentSizeCategory = true
    caption.textColor = .secondaryLabel
    caption.numberOfLines = 0
    let brandText = UIStackView(arrangedSubviews: [name, caption])
    brandText.axis = .vertical
    brandText.spacing = 6
    let brand = UIStackView(arrangedSubviews: [icon, brandText])
    brand.alignment = .center
    brand.spacing = 16
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 68),
      icon.heightAnchor.constraint(equalToConstant: 68),
    ])
    let heading = UILabel()
    heading.text = title
    heading.font = UIFont.preferredFont(forTextStyle: .largeTitle).withTraits(.traitBold)
    heading.adjustsFontForContentSizeCategory = true
    heading.numberOfLines = 0
    heading.accessibilityTraits = .header
    let detail = UILabel()
    detail.text = subtitle
    detail.font = .preferredFont(forTextStyle: .body)
    detail.adjustsFontForContentSizeCategory = true
    detail.textColor = .secondaryLabel
    detail.numberOfLines = 0
    let stack = UIStackView(arrangedSubviews: [brand, heading, detail])
    stack.axis = .vertical
    stack.spacing = 10
    stack.setCustomSpacing(32, after: brand)
    return stack
  }

  /// 主按钮使用系统玻璃配置，前期系统沿用其标准填充按钮。
  static func primaryButton(title: String) -> UIButton.Configuration {
    var configuration: UIButton.Configuration = .filled()
    if #available(iOS 26.0, *) { configuration = .prominentGlass() }
    configuration.title = title
    configuration.buttonSize = .large
    configuration.image = UIImage(systemName: "arrow.right")
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 10
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark ? .black : .white
    }
    return configuration
  }

  /// 表单限宽并跟随系统键盘收缩；滚动容器在旋转后仍保持当前输入可见。
  static func install(_ stack: UIStackView, in controller: UIViewController) {
    let view = controller.view!
    view.backgroundColor = .systemGroupedBackground
    view.tintColor = accent
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    let scroll = AccountFormScrollView()
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.keyboardDismissMode = .interactive
    if #available(iOS 26.0, *) { scroll.topEdgeEffect.style = .soft }
    controller.setContentScrollView(scroll, for: .top)
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    scroll.addSubview(stack)
    let preferredWidth = stack.widthAnchor.constraint(
      equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scroll.contentLayoutGuide.widthAnchor.constraint(
        equalTo: scroll.frameLayoutGuide.widthAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
      stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
      preferredWidth,
      stack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
      stack.widthAnchor.constraint(
        lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
    ])
  }
}

/// 连接与登录共用的滚动表单；键盘和旋转改变视口后，将焦点输入框保持在可见范围内。
@MainActor
private final class AccountFormScrollView: UIScrollView {
  private weak var activeField: UITextField?

  /// 只观察本滚动容器内的输入焦点，不持有控制器或账号内容。
  init() {
    super.init(frame: .zero)
    NotificationCenter.default.addObserver(
      self, selector: #selector(editingBegan), name: UITextField.textDidBeginEditingNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(editingEnded), name: UITextField.textDidEndEditingNotification,
      object: nil)
  }

  /// 账户容器只通过代码创建，不从归档恢复输入状态。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 容器销毁时撤销观察，避免旧实例响应下一次登录的焦点变化。
  deinit { NotificationCenter.default.removeObserver(self) }

  /// 系统键盘布局指南完成尺寸更新后，再按实际可见区域滚动，不叠加键盘高度。
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let field = activeField, field.isFirstResponder, bounds.height > 0 else { return }
    let target = convert(field.bounds, from: field).insetBy(dx: 0, dy: -8)
    if !bounds.contains(target) { scrollRectToVisible(target, animated: false) }
  }

  /// 输入框切换与验证码展开都走同一可见性处理，忽略其他窗口的编辑通知。
  @objc private func editingBegan(_ notification: Notification) {
    guard let field = notification.object as? UITextField, field.isDescendant(of: self) else {
      return
    }
    activeField = field
    setNeedsLayout()
  }

  /// 编辑结束后释放弱引用，普通浏览和交互收键盘不触发额外滚动。
  @objc private func editingEnded(_ notification: Notification) {
    if notification.object as? UITextField === activeField { activeField = nil }
  }
}

extension UIFont {
  /// 在保留 Dynamic Type 点数的同时为标题添加系统粗体，不锁死字号。
  fileprivate func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
