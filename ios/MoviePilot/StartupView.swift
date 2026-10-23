import UIKit

/// 延续系统启动页的静态品牌画面；网页资源和导航就绪前覆盖整个容器，不呈现网页加载器。
@MainActor
final class StartupView: UIView {
  /// 透明品牌图形和整屏深色背景与系统启动页一致，不附加文字或进度动画。
  init() {
    super.init(frame: .zero)
    backgroundColor = UIColor(named: "LaunchBackground")
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
  required init?(coder: NSCoder) { fatalError("Use init()") }
}
