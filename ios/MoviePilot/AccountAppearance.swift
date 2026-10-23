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

  /// 账户表单居中限宽并完全位于系统安全区与键盘之间，缩短横屏长行。
  static func install(_ stack: UIStackView, in controller: UIViewController) {
    let view = controller.view!
    view.backgroundColor = .systemGroupedBackground
    view.tintColor = accent
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    let scroll = UIScrollView()
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

extension UIFont {
  /// 在保留 Dynamic Type 点数的同时为标题添加系统粗体，不锁死字号。
  fileprivate func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
    return UIFont(descriptor: descriptor, size: pointSize)
  }
}
