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
  private let progressHost = UIStackView()
  private let progressLabel = UILabel()
  private let progressSpinner = UIActivityIndicatorView(style: .medium)
  private let progressBar = UIProgressView(progressViewStyle: .default)
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
    configureProgressView()
    apply(
      snapshot,
      style: navigationController?.overrideUserInterfaceStyle ?? traitCollection.userInterfaceStyle)
  }

  /// 半屏展开、旋转和键盘改变后用当前内容框架重新计算网页 viewport。
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }

  /// 只创建系统状态控件，业务请求和完成条件仍由原网页持有。
  private func configureProgressView() {
    progressHost.axis = .vertical
    progressHost.spacing = 20
    progressHost.alignment = .fill
    progressHost.translatesAutoresizingMaskIntoConstraints = false
    progressHost.accessibilityIdentifier = "native-progress-status"
    progressLabel.font = .preferredFont(forTextStyle: .body)
    progressLabel.adjustsFontForContentSizeCategory = true
    progressLabel.textColor = .secondaryLabel
    progressLabel.textAlignment = .center
    progressLabel.numberOfLines = 4
    progressLabel.accessibilityIdentifier = "native-progress-message"
    progressSpinner.accessibilityIdentifier = "native-progress-spinner"
    progressBar.accessibilityIdentifier = "native-progress-value"
    for child in [progressLabel, progressSpinner, progressBar] {
      progressHost.addArrangedSubview(child)
    }
    view.addSubview(progressHost)
    NSLayoutConstraint.activate([
      progressHost.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      progressHost.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      progressHost.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
    ])
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
      // 处理完成后恢复正常内容高度，不能把结果卡片留在紧凑进度弹层里。
      let sheet = navigationController?.sheetPresentationController
    {
      updateDetents(sheet, snapshot: snapshot)
    } else if (renderedSnapshot?.progress == nil) != (snapshot.progress == nil),
      let sheet = navigationController?.sheetPresentationController
    {
      updateDetents(sheet, snapshot: snapshot)
    }
    guard renderedSnapshot != snapshot else { return }
    renderedSnapshot = snapshot
    progressHost.isHidden = snapshot.progress == nil
    contentHost.view.accessibilityElementsHidden = snapshot.progress != nil
    if let progress = snapshot.progress {
      progressLabel.text = progress.message
      progressBar.isHidden = progress.value == nil
      progressSpinner.isHidden = progress.value != nil
      if let value = progress.value {
        progressSpinner.stopAnimating()
        progressBar.setProgress(Float(value / 100), animated: false)
        progressBar.accessibilityValue = "\(Int(value))%"
      } else {
        progressSpinner.startAnimating()
      }
    } else {
      progressSpinner.stopAnimating()
    }
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

  /// 处理中使用不可下拉关闭的小型系统 Sheet，完成时恢复原声明的半屏或全屏。
  private func updateDetents(_ sheet: UISheetPresentationController, snapshot: NativeSheetSnapshot)
  {
    if snapshot.progress != nil {
      sheet.detents = [.custom(identifier: .init("progress")) { min(260, $0.maximumDetentValue) }]
      sheet.selectedDetentIdentifier = .init("progress")
    } else {
      sheet.detents =
        snapshot.fullscreen
        ? [.large()]
        : snapshot.prefersMediumDetent == true
          ? [.medium(), .large()]
          : [.custom(identifier: .init("content")) { $0.maximumDetentValue * 0.78 }, .large()]
      if renderedSnapshot?.progress != nil || snapshot.prefersMediumDetent == true {
        sheet.selectedDetentIdentifier =
          snapshot.fullscreen
          ? .large : snapshot.prefersMediumDetent == true ? .medium : .init("content")
      }
    }
    sheet.prefersGrabberVisible = snapshot.canDismiss
    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
  }

  /// 下拉关闭也先交给 Vue 的关闭按钮，不能绕过业务中的持久弹窗或禁用状态。
  func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController)
  {
    if snapshot.canDismiss { onCommand("presentation.dismiss", nil) }
  }
}
