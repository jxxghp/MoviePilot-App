import MoviePilotCore
import UIKit

/// 系统 Sheet 的标题栏和安全区宿主；业务内容始终是协调器持有的唯一 WebView。
@MainActor
final class NativeWebSheetController: UIViewController, UIAdaptivePresentationControllerDelegate {
  let contentHost = ContentHostController(rootId: nil)
  private var snapshot: NativeSheetSnapshot
  private var renderedSnapshot: NativeSheetSnapshot?
  private var renderedStyle: UIUserInterfaceStyle?
  private let onCommand: (String, String?) -> Void
  var onLayout: (() -> Void)?

  /// 声明只决定系统栏，关闭与其他动作交回当前 Vue 弹窗的实际按钮。
  init(snapshot: NativeSheetSnapshot, onCommand: @escaping (String, String?) -> Void) {
    self.snapshot = snapshot
    self.onCommand = onCommand
    super.init(nibName: nil, bundle: nil)
  }

  /// 原生弹窗按文档会话创建，不从 storyboard 恢复业务状态。
  required init?(coder: NSCoder) { fatalError("Use init(snapshot:onCommand:)") }

  /// 内容框架消费系统栏与 Home Indicator 安全区，网页不再重复添加原页面边距。
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.accessibilityIdentifier = "native-web-sheet"
    addChild(contentHost)
    contentHost.view.translatesAutoresizingMaskIntoConstraints = false
    contentHost.view.backgroundColor = .clear
    view.addSubview(contentHost.view)
    NSLayoutConstraint.activate([
      contentHost.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      contentHost.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      contentHost.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      contentHost.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
    ])
    contentHost.didMove(toParent: self)
    apply(
      snapshot,
      style: navigationController?.overrideUserInterfaceStyle ?? traitCollection.userInterfaceStyle)
  }

  /// 半屏展开、旋转和键盘改变后用当前内容框架重新计算网页 viewport。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }

  /// 嵌套弹窗只更新同一 Sheet 的栏位，不复制 WebView 或 Vue 的弹窗栈。
  func apply(_ snapshot: NativeSheetSnapshot, style: UIUserInterfaceStyle) {
    self.snapshot = snapshot
    // 呈现层不属于内容导航控制器，单独同步主题，保留 UIKit 默认材质与外围处理。
    if renderedStyle != style {
      NativeModalAppearance.apply(to: navigationController?.presentationController, style: style)
      renderedStyle = style
    }
    if renderedSnapshot?.fullscreen != snapshot.fullscreen
      || renderedSnapshot?.prefersMediumDetent != snapshot.prefersMediumDetent
      || renderedSnapshot?.canDismiss != snapshot.canDismiss,
      let sheet = navigationController?.sheetPresentationController
    {
      let detents: [UISheetPresentationController.Detent] =
        snapshot.fullscreen
        ? [.large()]
        : snapshot.prefersMediumDetent == true
          ? [.medium(), .large()]
          : [.custom(identifier: .init("content")) { $0.maximumDetentValue * 0.78 }, .large()]
      sheet.detents = detents
      if snapshot.prefersMediumDetent == true,
        renderedSnapshot?.prefersMediumDetent != snapshot.prefersMediumDetent
      {
        sheet.selectedDetentIdentifier = .medium
      }
      sheet.prefersGrabberVisible = snapshot.canDismiss
      sheet.prefersScrollingExpandsWhenScrolledToEdge = true
    }
    guard renderedSnapshot != snapshot else { return }
    renderedSnapshot = snapshot
    title = snapshot.title
    edgesForExtendedLayout = .all
    navigationItem.largeTitleDisplayMode = .never
    isModalInPresentation = true
    navigationController?.isModalInPresentation = true
    navigationItem.leftBarButtonItem = nil
    navigationItem.rightBarButtonItems = nil
    if snapshot.canDismiss {
      let close = UIBarButtonItem(
        image: UIImage(systemName: "xmark"),
        primaryAction: UIAction { [weak self] _ in
          self?.onCommand("presentation.dismiss", nil)
        })
      close.accessibilityLabel = "关闭"
      close.accessibilityIdentifier = "native-sheet-close"
      navigationItem.rightBarButtonItem = close
    }
    if !snapshot.actions.isEmpty {
      let actions = snapshot.actions.map { action in
        UIAction(
          title: action.title, image: action.icon.flatMap { NavigationSymbols.image($0) },
          attributes: action.enabled ? [] : .disabled
        ) {
          [weak self] _ in self?.onCommand("presentation.action", action.id)
        }
      }
      let more = UIBarButtonItem(
        image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: actions))
      more.accessibilityLabel = "弹窗操作"
      more.accessibilityIdentifier = "native-sheet-menu"
      navigationItem.leftBarButtonItem = more
    }
  }

  /// 下拉关闭也先交给 Vue 的关闭按钮，不能绕过业务中的持久弹窗或禁用状态。
  func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController)
  {
    if snapshot.canDismiss { onCommand("presentation.dismiss", nil) }
  }
}
