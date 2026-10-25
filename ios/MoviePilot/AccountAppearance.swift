import MoviePilotCore
import UIKit

/// 连接与登录复用当前实例的玻璃主题；正文与导航材质仍使用系统语义。
@MainActor
enum AccountAppearance {
  /// 只保存有界的外观值，不包含实例地址、账号或认证数据。
  private struct Preferences: Codable, Equatable {
    var theme: ChromeTheme = .system
    var accent: String?
    var lightBackground = "#F2F2F7"
    var darkBackground = "#0B1322"
    var lightSurface = "#FFFFFF"
    var darkSurface = "#182235"
  }

  static let accent = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.72, green: 0.57, blue: 1, alpha: 1)
      : UIColor(red: 0.47, green: 0.25, blue: 0.84, alpha: 1)
  }

  /// 已确认的网页主题按实例保存；跟随系统保留两套底色，避免冷启动锁定旧的明暗。
  static func remember(_ chrome: ChromeSnapshot, for instance: UUID, traits: UITraitCollection) {
    let previous = preferences(for: instance)
    var value = previous
    value.theme = chrome.theme
    value.accent = NavigationSymbols.color(chrome.accentColor) == nil ? nil : chrome.accentColor
    let dark =
      chrome.theme == .dark
      || (chrome.theme == .system && traits.userInterfaceStyle == .dark)
    if let background = chrome.backgroundColor, NavigationSymbols.color(background) != nil {
      if dark { value.darkBackground = background } else { value.lightBackground = background }
    }
    if let surface = chrome.surfaceColor, NavigationSymbols.color(surface) != nil {
      if dark { value.darkSurface = surface } else { value.lightSurface = surface }
    }
    guard value != previous, let data = try? JSONEncoder().encode(value) else { return }
    UserDefaults.standard.set(data, forKey: key(instance))
  }

  /// 忘记实例时同步移除其外观，其他实例的主题不受影响。
  static func forget(_ instance: UUID) {
    UserDefaults.standard.removeObject(forKey: key(instance))
  }

  /// 在首帧之前设置整个导航容器的明暗，表单、状态栏和导航按钮共同继承。
  static func navigationController(
    root: UIViewController, instance: UUID?
  ) -> UINavigationController {
    let value = preferences(for: instance)
    let navigation = UINavigationController(rootViewController: root)
    navigation.overrideUserInterfaceStyle =
      value.theme == .dark ? .dark : (value.theme == .light ? .light : .unspecified)
    navigation.view.backgroundColor = background(value)
    navigation.view.tintColor = NavigationSymbols.color(value.accent) ?? accent
    return navigation
  }

  /// 输入面板与网页的 surface 色一致，不把系统黑色卡片放在深蓝背景上。
  static func surface(for instance: UUID?) -> UIColor {
    let value = preferences(for: instance)
    let light = NavigationSymbols.color(value.lightSurface) ?? .secondarySystemGroupedBackground
    let dark = NavigationSymbols.color(value.darkSurface) ?? .secondarySystemGroupedBackground
    return UIColor { traits in
      traits.userInterfaceStyle == .dark ? dark : light
    }
  }

  /// 表单强调色沿用网页最近选择，尚未连接时使用品牌动态色。
  static func accent(for instance: UUID?) -> UIColor {
    NavigationSymbols.color(preferences(for: instance).accent) ?? accent
  }

  /// 无历史外观时采用现有玻璃主题的明暗底色，之后使用网页实际投影的颜色。
  private static func background(_ value: Preferences) -> UIColor {
    let light = NavigationSymbols.color(value.lightBackground) ?? .systemGroupedBackground
    let dark = NavigationSymbols.color(value.darkBackground) ?? .systemGroupedBackground
    return UIColor { traits in
      traits.userInterfaceStyle == .dark ? dark : light
    }
  }

  /// 损坏或超长的展示偏好回到默认玻璃主题，不影响实例和认证恢复。
  private static func preferences(for instance: UUID?) -> Preferences {
    guard let instance, let data = UserDefaults.standard.data(forKey: key(instance)),
      data.count <= 2048, let value = try? JSONDecoder().decode(Preferences.self, from: data)
    else { return Preferences() }
    return value
  }

  /// 外观仅以本地实例 UUID 隔离，用户输入和服务地址不进入键名。
  private static func key(_ instance: UUID) -> String {
    "moviepilot.appearance.\(instance.uuidString).v1"
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
  static func install(
    _ stack: UIStackView, in controller: UIViewController, instance: UUID?
  ) {
    let view = controller.view!
    view.backgroundColor = background(preferences(for: instance))
    view.tintColor = accent(for: instance)
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
  private var previousViewportSize: CGSize = .zero
  private var previousInputRect: CGRect?

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

  /// 仅在视口或输入布局改变时定位；普通滚动不抢回焦点，也不叠加键盘高度。
  override func layoutSubviews() {
    super.layoutSubviews()
    let resized = previousViewportSize != bounds.size
    previousViewportSize = bounds.size
    guard let field = activeField, field.isFirstResponder, bounds.height > 0 else {
      previousInputRect = nil
      return
    }
    let target = convert(field.bounds, from: field).insetBy(dx: 0, dy: -8)
    let changed = resized || previousInputRect != target
    previousInputRect = target
    guard changed, !isTracking, !isDecelerating else { return }
    if !bounds.contains(target) { scrollRectToVisible(target, animated: false) }
  }

  /// 输入框切换与验证码展开都走同一可见性处理，忽略其他窗口的编辑通知。
  @objc private func editingBegan(_ notification: Notification) {
    guard let field = notification.object as? UITextField, field.isDescendant(of: self) else {
      return
    }
    activeField = field
    previousInputRect = nil
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
