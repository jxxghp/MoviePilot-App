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
