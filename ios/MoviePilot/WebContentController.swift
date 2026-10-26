import UIKit
import WebKit

/// 单一网页内容控制器，在系统导航宿主之间转移时保留同一文档与 JS 应用。
@MainActor
final class WebContentController: UIViewController {
  let webView: WKWebView
  private let instanceID: UUID
  var onLayout: (() -> Void)?
  private var resumePreview: UIImageView?
  private var resumeContext: String?
  private var resumeSize = CGSize.zero
  private var resumePaintTimeout: Timer?
  private(set) var resumePreviewToken: UUID?

  /// 使用唯一 WebView，并以当前实例主题提供无位图恢复占位。
  init(webView: WKWebView, instanceID: UUID) {
    self.webView = webView
    self.instanceID = instanceID
    super.init(nibName: nil, bundle: nil)
  }

  /// 内容会话只能通过指定 WebView 建立。
  required init?(coder: NSCoder) { fatalError("Use init(webView:instanceID:)") }

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
    if resumePreview != nil, resumeSize != view.bounds.size { clearResumePreview() }
    onLayout?()
  }

  /// WebKit 暂停前只保留一张当前正文的内存画面，原 DOM、滚动和表单继续由同一 WebView 持有。
  func preserveResumePreview(context: String) {
    if resumePreview != nil, resumeContext == context {
      // 连续中断复用同一张图，但上一轮 WebKit 回调和期限不能移除下一轮的保护画面。
      resumePaintTimeout?.invalidate()
      resumePaintTimeout = nil
      resumePreviewToken = UUID()
      return
    }
    clearResumePreview()
    guard isViewLoaded, view.window != nil, !view.isHidden,
      view.bounds.width > 0, view.bounds.height > 0
    else { return }
    let format = UIGraphicsImageRendererFormat()
    // 单张画面最多三百万像素，不随系统分辨率或多次前后台循环累积。
    format.scale = min(2, sqrt(3_000_000 / (view.bounds.width * view.bounds.height)))
    format.opaque = true
    var painted = false
    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
      painted = view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
    }
    installResumePreview(image: painted ? image : nil, context: context)
  }

  /// 内存回收或系统未能留下快照时，以当前主题的本地启动画面保护尚未重绘的正文。
  func ensureResumePreview(context: String) {
    synchronizeResumePreview(context: context)
    guard resumePreview == nil, isViewLoaded, view.window != nil, !view.isHidden else { return }
    installResumePreview(image: nil, context: context)
  }

  /// 同一张受限快照与无位图占位共用交接代次和触摸隔离，不另建 WebView。
  private func installResumePreview(image: UIImage?, context: String) {
    let preview = UIImageView(image: image)
    preview.frame = view.bounds
    preview.contentMode = .scaleToFill
    preview.isUserInteractionEnabled = true
    preview.isAccessibilityElement = true
    preview.accessibilityIdentifier = "native-resume-preview"
    preview.accessibilityLabel = "正在恢复页面"
    resumeContext = context
    resumeSize = view.bounds.size
    resumePreviewToken = UUID()
    resumePreview = preview
    if image == nil { addResumePlaceholder(to: preview) }
    webView.accessibilityElementsHidden = true
    view.addSubview(preview)
  }

  /// 只使用内置主题启动视图，画面不可用时不会露出黑色的 WebKit 表面。
  private func addResumePlaceholder(to preview: UIImageView) {
    guard preview.subviews.isEmpty else { return }
    let placeholder = StartupView(instance: instanceID)
    placeholder.frame = preview.bounds
    placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    placeholder.accessibilityElementsHidden = true
    preview.addSubview(placeholder)
  }

  /// 后台期间路由、主题或身份改变时不把旧正文盖在新的页面上。
  func synchronizeResumePreview(context: String?) {
    if resumeContext != context { clearResumePreview() }
  }

  /// Vue 绘制后仍须等 WebKit 成功提交画面；超时交给明确恢复出口，不提前暴露未绘制正文。
  func completeResumePreview(token: UUID, onFailure: @escaping @MainActor @Sendable () -> Void) {
    guard resumePreviewToken == token else { return }
    resumePaintTimeout?.invalidate()
    resumePaintTimeout = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard self?.resumePreviewToken == token else { return }
        onFailure()
      }
    }
    requestResumeSnapshot(token: token)
  }

  /// 解锁时暂不可用的渲染结果不会被视为成功；只在本轮有界期限内重试只读快照。
  private func requestResumeSnapshot(token: UUID) {
    guard resumePreviewToken == token, resumePaintTimeout != nil else { return }
    let configuration = WKSnapshotConfiguration()
    configuration.afterScreenUpdates = true
    configuration.snapshotWidth = NSNumber(value: 1)
    webView.takeSnapshot(with: configuration) { [weak self] image, error in
      guard let self, self.resumePreviewToken == token else { return }
      if image != nil, error == nil {
        self.clearResumePreview(token: token)
      } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.requestResumeSnapshot(token: token)
        }
      }
    }
  }

  /// 新文档、错误、内存压力和取消恢复均释放图像；旧异步完成不能移除下一次恢复的画面。
  func clearResumePreview(token: UUID? = nil) {
    if let token, token != resumePreviewToken { return }
    resumePaintTimeout?.invalidate()
    resumePaintTimeout = nil
    resumePreview?.removeFromSuperview()
    resumePreview = nil
    resumePreviewToken = nil
    resumeContext = nil
    resumeSize = .zero
    webView.accessibilityElementsHidden = false
  }

  /// 系统内存警告立即释放位图，轻量主题占位继续保护未完成的同一轮绘制。
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    if let preview = resumePreview {
      preview.image = nil
      addResumePlaceholder(to: preview)
    }
  }
}

/// 每个底部入口的轻量宿主；没有第二份 WKWebView 或业务历史栈。
@MainActor
final class ContentHostController: UIViewController {
  let rootId: String?
  private let headerFade = NavigationHeaderFadeView()

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
    guard rootId != nil else { return }
    headerFade.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(headerFade)
    NSLayoutConstraint.activate([
      headerFade.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -12),
      headerFade.heightAnchor.constraint(equalToConstant: 32),
      headerFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      headerFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  /// 只将顶部材质向正文延伸 20pt，不改变安全区、导航栏高度或底栏几何。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if headerFade.superview != nil { view.bringSubviewToFront(headerFade) }
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
    if headerFade.superview != nil { view.bringSubviewToFront(headerFade) }
  }
}

/// 系统薄材质的短渐变尾部；不额外叠加色块，也不接收正文或导航手势。
@MainActor
private final class NavigationHeaderFadeView: UIVisualEffectView {
  private let fade = CAGradientLayer()

  /// 使用系统动态材质保留明暗与辅助功能适配，渐变只控制向下延伸的范围。
  init() {
    super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    fade.colors = [
      UIColor.clear.cgColor,
      UIColor.black.withAlphaComponent(0.40).cgColor,
      UIColor.clear.cgColor,
    ]
    fade.locations = [0, 0.375, 1]
    layer.mask = fade
  }

  /// 材质随宿主创建，不从归档恢复额外布局。
  required init?(coder: NSCoder) { fatalError("Use init()") }

  /// 横竖屏只更新渐变遮罩尺寸，避免隐式动画留下旧的边界。
  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fade.frame = bounds
    CATransaction.commit()
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

/// UIKit 交互卡片只承载转场画面；缺少上一页预览时保留当前页，直到目标完成绘制。
@MainActor
final class NavigationBackTransition {
  let overlay: UIView
  private let previous: UIImageView
  private let shade = UIView()
  private let card = UIView()
  private let clipping = UIView()
  private var animator: UIViewPropertyAnimator?

  /// 前景使用当前系统视图快照；只有同一会话的目标预览存在时才允许滑开前景。
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
    shade.isHidden = image == nil
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

  /// 有目标预览时连续跟手；后台清理或未采样时保持本页全幅，避免露出空背景。
  func update(distance: CGFloat) {
    guard previous.image != nil else { return }
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

  /// 目标预览存在时接续跟手动画；缺失时交由原路由与绘制握手完成静止交接。
  func animate(completed: Bool, completion: @escaping () -> Void) {
    guard previous.image != nil else {
      completion()
      return
    }
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
