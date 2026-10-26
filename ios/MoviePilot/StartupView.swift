import UIKit

/// 延续系统启动页的静态品牌画面；网页资源和导航就绪前覆盖整个容器，不呈现网页加载器。
@MainActor
final class StartupView: UIView {
  /// 图形始终来自本地资源；首帧按实例偏好选择底色，无历史时跟随系统明暗。
  init(instance: UUID) {
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
}
