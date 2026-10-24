import UIKit
import WebKit

/// 单一网页内容控制器，在系统导航宿主之间转移时保留同一文档与 JS 应用。
@MainActor
final class WebContentController: UIViewController {
  let webView: WKWebView
  var onLayout: (() -> Void)?

  /// 使用协调器唯一持有的 WebView，不在导航切换时创建新实例。
  init(webView: WKWebView) {
    self.webView = webView
    super.init(nibName: nil, bundle: nil)
  }

  /// 内容会话只能通过指定 WebView 建立。
  required init?(coder: NSCoder) { fatalError("Use init(webView:)") }

  /// 页面背景可延伸至系统导航后方，正文避让统一交给协商布局。
  override func loadView() {
    let view = UIView()
    view.backgroundColor = .systemBackground
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: view.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    self.view = view
  }

  /// 旋转和系统栏尺寸改变后通知协调器重新量测。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }
}

/// 每个底部入口的轻量宿主；没有第二份 WKWebView 或业务历史栈。
@MainActor
final class ContentHostController: UIViewController {
  let rootId: String?

  /// rootId 仅用于与网页确认的主入口对应。
  init(rootId: String?) {
    self.rootId = rootId
    super.init(nibName: nil, bundle: nil)
  }

  /// 宿主在每次完整导航快照中恢复，不使用 storyboard。
  required init?(coder: NSCoder) { fatalError("Use init(rootId:)") }

  /// 默认让背景延伸至系统栏后方，兼容网页模式由上层关闭延伸。
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    definesPresentationContext = true
  }

  /// 正确解除旧父子关系，再将同一内容控制器归属到当前入口。
  func attach(_ content: WebContentController) {
    guard content.parent !== self else { return }
    // 先解除旧导航容器的滚动跟踪，避免同一 WKScrollView 同时驱动两份系统导航栏。
    (content.parent as? ContentHostController)?.setContentScrollView(nil, for: .all)
    content.willMove(toParent: nil)
    content.view.removeFromSuperview()
    content.removeFromParent()
    addChild(content)
    content.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content.view)
    NSLayoutConstraint.activate([
      content.view.topAnchor.constraint(equalTo: view.topAnchor),
      content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    content.didMove(toParent: self)
    trackContentScrollView(content.webView.scrollView)
  }

  /// 由 UIKit 根据真实滚动内容绘制柔和渐变边缘，避免给顶栏叠加固定色块或自制材质。
  func trackContentScrollView(_ scrollView: UIScrollView) {
    if #available(iOS 26.0, *) { scrollView.topEdgeEffect.style = .soft }
    setContentScrollView(scrollView, for: .all)
  }
}

/// 离页预览只在当前会话内存中保留，不存储网页、认证或业务历史；Vue 仍决定返回目标。
@MainActor
final class NavigationPreviewCache {
  private var context: String?
  private var size = CGSize.zero
  private var images: [String: Data] = [:]
  private var order: [String] = []
  private var bytes = 0

  /// 会话、主题或窗口变化后丢弃全部旧画面，避免跨账号或错误几何的预览。
  func synchronize(context: String?, size: CGSize) {
    guard self.context != context || self.size != size else { return }
    clear()
    self.context = context
    self.size = size
  }

  /// 仅保存当前可见的原生和 Web 合成画面；有界 JPEG 数据不会占用多个 WebView。
  func capture(_ host: UIView, path: String) {
    guard context != nil, host.window != nil, host.bounds.size == size,
      size.width > 0, size.height > 0
    else { return }
    let format = UIGraphicsImageRendererFormat()
    format.scale = min(2, host.window?.screen.scale ?? 2)
    format.opaque = true
    var painted = false
    let image = UIGraphicsImageRenderer(bounds: host.bounds, format: format).image { _ in
      painted = host.drawHierarchy(in: host.bounds, afterScreenUpdates: false)
    }
    guard painted, let data = image.jpegData(compressionQuality: 0.88),
      data.count <= 4 * 1024 * 1024
    else { return }
    if let previous = images[path] { bytes -= previous.count }
    images[path] = data
    order.removeAll { $0 == path }
    order.append(path)
    bytes += data.count
    while bytes > 24 * 1024 * 1024 || order.count > 128, let first = order.first {
      order.removeFirst()
      bytes -= images.removeValue(forKey: first)?.count ?? 0
    }
  }

  /// 只按网页明确给出的精确 backTarget 查询，不猜测或另建业务栈。
  func image(for path: String?) -> UIImage? {
    guard let path, let data = images[path] else { return nil }
    return UIImage(data: data)
  }

  /// 后台、身份切换、内存压力与接管释放时统一清理敏感画面。
  func clear() {
    images.removeAll()
    order.removeAll()
    bytes = 0
    context = nil
    size = .zero
  }
}

/// UIKit 交互卡片只承载转场画面；手指松开前不改变实际路由、WebView 或业务组件。
@MainActor
final class NavigationBackTransition {
  let overlay: UIView
  private let previous: UIImageView
  private let shade = UIView()
  private let card = UIView()
  private let clipping = UIView()
  private var animator: UIViewPropertyAnimator?

  /// 前景使用当前系统视图快照，背景来自同一会话的已访问页面，不模拟玻璃材质。
  init?(host: UIView, previous image: UIImage?) {
    guard let current = host.snapshotView(afterScreenUpdates: false) else { return nil }
    overlay = UIView(frame: host.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.accessibilityIdentifier = "native-back-transition"
    overlay.backgroundColor = .systemBackground
    previous = UIImageView(frame: overlay.bounds)
    previous.image = image
    previous.contentMode = .scaleToFill
    previous.accessibilityIdentifier = "native-back-previous"
    previous.isAccessibilityElement = true
    previous.accessibilityLabel = "上一页预览"
    overlay.addSubview(previous)
    shade.frame = overlay.bounds
    shade.backgroundColor = .black
    overlay.addSubview(shade)
    card.frame = overlay.bounds
    card.accessibilityIdentifier = "native-back-card"
    card.isAccessibilityElement = true
    card.accessibilityLabel = "返回中的当前页面"
    card.layer.shadowColor = UIColor.black.cgColor
    card.layer.shadowOpacity = 0.2
    card.layer.shadowRadius = 14
    card.layer.shadowOffset = CGSize(width: -3, height: 0)
    clipping.frame = card.bounds
    clipping.backgroundColor = .systemBackground
    clipping.layer.cornerCurve = .continuous
    clipping.clipsToBounds = true
    current.frame = clipping.bounds
    clipping.addSubview(current)
    card.addSubview(clipping)
    overlay.addSubview(card)
    host.addSubview(overlay)
    update(distance: 0)
  }

  /// 连续位移直接跟随手指，上一页保留系统导航常见的轻微视差与遮阴。
  func update(distance: CGFloat) {
    let width = max(1, overlay.bounds.width)
    let x = min(width, max(0, distance))
    let progress = x / width
    card.transform = CGAffineTransform(translationX: x, y: 0)
    clipping.layer.cornerRadius = min(28, x * 0.3)
    previous.transform = CGAffineTransform(
      translationX: UIAccessibility.isReduceMotionEnabled ? 0 : -width * 0.25 * (1 - progress), y: 0
    )
    shade.alpha = 0.16 * (1 - progress)
  }

  /// 取消回弹、完成移出都由 UIKit 动画接续当前手指位置，不重新开始一段网页转场。
  func animate(completed: Bool, completion: @escaping () -> Void) {
    animator?.stopAnimation(true)
    let animation = UIViewPropertyAnimator(
      duration: UIAccessibility.isReduceMotionEnabled ? 0.12 : 0.28, dampingRatio: 1
    ) {
      self.update(distance: completed ? self.overlay.bounds.width : 0)
    }
    animator = animation
    animation.addCompletion { _ in completion() }
    animation.startAnimation()
  }

  /// 只有网页确认绘制或取消完成后才移除覆盖层，期间不揭开尚未更新的正文。
  func remove() {
    animator?.stopAnimation(true)
    animator = nil
    overlay.removeFromSuperview()
  }
}
