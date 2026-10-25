import MoviePilotCore
import UIKit
import WebKit

/// 单次系统预览持有当前卡片的展示副本；不缓存页面、认证或业务闭包。
@MainActor
private final class CardMenuCandidate {
  var menu: OperationMenuSnapshot
  let rect: CGRect
  let viewport: CGRect
  let point: CGPoint
  let created = ProcessInfo.processInfo.systemUptime
  var image: UIImage?
  var mirror: UIView?
  var selection: String?
  var selectionDispatched = false
  var cancelled = false

  /// 原生只接收已校验的菜单与同一次触摸量测，不用列表下标寻找卡片。
  init(menu: OperationMenuSnapshot, rect: CGRect, viewport: CGRect, point: CGPoint) {
    self.menu = menu
    self.rect = rect
    self.viewport = viewport
    self.point = point
  }
}

/// 真实 WK 内容仅作为系统上下文菜单的预览，不绘制或模拟系统玻璃材质。
@MainActor
private final class CardMenuPreviewController: UIViewController {
  /// 预览尺寸沿用当前可见卡片，系统负责抬升、缩放和菜单承载。
  init(preview: UIView, size: CGSize) {
    super.init(nibName: nil, bundle: nil)
    view = preview
    preferredContentSize = size
  }

  /// 预览只能由当前卡片取样建立，不接受 storyboard 恢复。
  required init?(coder: NSCoder) { fatalError("Use init(preview:size:)") }
}

/// 可选原生卡片长按承载器；只有完整能力协商后才由宿主建立，不执行业务 API。
@MainActor
final class CardMenuInteraction: NSObject, UIContextMenuInteractionDelegate {
  private weak var webView: WKWebView?
  private var candidate: CardMenuCandidate?
  private var presented: CardMenuCandidate?
  private var interaction: UIContextMenuInteraction!
  private let select: (OperationMenuSnapshot, String) -> Void
  private let dismiss: (String) -> Void
  private let opened: (String) -> Void
  var accent: UIColor = .systemBlue

  /// 选择与取消通过窄回调回到协调器，回调发出前再次检查当前原生展示代次。
  init(
    webView: WKWebView, select: @escaping (OperationMenuSnapshot, String) -> Void,
    dismiss: @escaping (String) -> Void, opened: @escaping (String) -> Void
  ) {
    self.webView = webView
    self.select = select
    self.dismiss = dismiss
    self.opened = opened
    super.init()
    interaction = UIContextMenuInteraction(delegate: self)
    webView.addInteraction(interaction)
  }

  /// 触摸准备时取样；不同候选、滚动、路由或布局变化均由宿主撤销旧代次。
  func prepare(menu: OperationMenuSnapshot, rect: CGRect, point: CGPoint) throws {
    try menu.validate()
    guard menu.kind == .card, let webView, webView.window != nil,
      [rect.minX, rect.minY, rect.width, rect.height, point.x, point.y].allSatisfy(\.isFinite),
      rect.width > 0, rect.height > 0, rect.contains(point), webView.bounds.contains(point)
    else { throw BridgeError.invalidMessage }
    invalidate()
    let visible = rect.intersection(webView.bounds)
    guard !visible.isEmpty, !visible.isNull else { throw BridgeError.invalidMessage }
    let next = CardMenuCandidate(menu: menu, rect: visible, viewport: webView.bounds, point: point)
    candidate = next
    let configuration = WKSnapshotConfiguration()
    configuration.rect = visible
    configuration.snapshotWidth = NSNumber(value: Double(visible.width))
    configuration.afterScreenUpdates = false
    webView.takeSnapshot(with: configuration) { [weak self, weak next] image, _ in
      guard let self, let next, self.candidate === next, !next.cancelled,
        self.webView?.bounds == next.viewport
      else { return }
      next.image = image
    }
  }

  /// 保留菜单的原动作完成后只能用新票据替换，同一来源之外的刷新取消当前菜单。
  func refresh(menu: OperationMenuSnapshot) throws {
    try menu.validate()
    guard let current = presented, candidate === current, !current.cancelled,
      current.menu.ownerId == menu.ownerId, current.menu.menuId == menu.menuId,
      current.menu.kind == menu.kind
    else { throw BridgeError.actionNotAvailable }
    current.menu = menu
    current.selection = nil
    current.selectionDispatched = false
    interaction.updateVisibleMenu { [weak self, weak current] visible in
      guard let self, let current else { return visible }
      let root = self.menu(current)
      return self.findMenu(visible.identifier, in: root) ?? root
    }
  }

  /// 生命周期或来源失效先封闭业务选择，再让 UIKit 完成其取消动画。
  func invalidate() {
    let previous = candidate
    candidate = nil
    previous?.cancelled = true
    if let previous, previous !== presented {
      previous.mirror?.removeFromSuperview()
      dismiss(previous.menu.presentationId)
    }
    if let presented {
      presented.cancelled = true
      interaction.dismissMenu()
    }
  }

  /// 宿主释放 WebView 前移除交互，不能让旧实例保留系统菜单或镜像。
  func stop() {
    invalidate()
    presented?.mirror?.removeFromSuperview()
    presented = nil
    webView?.removeInteraction(interaction)
    webView = nil
  }

  /// 系统同步询问时只使用当前短寿命候选；没有完整来源或预览时不启动假菜单。
  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let current = candidate, !current.cancelled, presented == nil,
      let webView, webView.bounds == current.viewport, current.rect.contains(location),
      abs(location.x - current.point.x) < 20, abs(location.y - current.point.y) < 20,
      ProcessInfo.processInfo.systemUptime - current.created < 2,
      let mirror = preview(current)
    else { return nil }
    current.mirror = mirror
    mirror.frame = current.rect
    mirror.isUserInteractionEnabled = false
    webView.addSubview(mirror)
    presented = current
    let configuration = UIContextMenuConfiguration(
      identifier: current.menu.presentationId as NSString,
      previewProvider: { [weak self, weak current] in
        guard let self, let current, !current.cancelled, let preview = self.preview(current)
        else { return nil }
        return CardMenuPreviewController(preview: preview, size: current.rect.size)
      },
      actionProvider: { [weak self, weak current] _ in
        guard let self, let current, !current.cancelled else { return nil }
        return self.menu(current)
      })
    configuration.preferredMenuElementOrder = .fixed
    return configuration
  }

  /// 系统确实开始展示后确认票据，网页才取消短寿命准备超时。
  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willDisplayMenuFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    guard let current = presented, candidate === current, !current.cancelled else { return }
    opened(current.menu.presentationId)
  }

  /// 抬升目标仅为当前卡片的可见区域，不让系统把整个 WebView 当作预览抬起。
  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
  ) -> UITargetedPreview? { targetedPreview() }

  /// 正常收起回到同一个卡片位置；来源已经失效时交给系统淡出。
  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
  ) -> UITargetedPreview? { targetedPreview() }

  /// 系统结束动画后才交接已选动作，取消和选择分开，避免旧菜单残留到业务弹窗后面。
  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration,
    animator: (any UIContextMenuInteractionAnimating)?
  ) {
    guard let current = presented else { return }
    let completion = { [weak self, current] in
      current.mirror?.removeFromSuperview()
      guard let self, self.presented === current else { return }
      self.presented = nil
      if self.candidate === current { self.candidate = nil }
      if !current.cancelled, !current.selectionDispatched,
        let id = current.selection, current.menu.availableAction(id: id) != nil
      {
        current.selectionDispatched = true
        self.select(current.menu, id)
      } else {
        self.dismiss(current.menu.presentationId)
      }
    }
    if let animator { animator.addCompletion(completion) } else { completion() }
  }

  /// 取样失败可使用 UIKit 的同步内容副本，仍不改变网页或自绘背景材质。
  private func preview(_ current: CardMenuCandidate) -> UIView? {
    if let image = current.image {
      let view = UIImageView(image: image)
      view.contentMode = .scaleToFill
      return view
    }
    return webView?.resizableSnapshotView(
      from: current.rect, afterScreenUpdates: false, withCapInsets: .zero)
  }

  /// targeted preview 的宿主必须仍在窗口中，背景、圆角与动画由系统处理。
  private func targetedPreview() -> UITargetedPreview? {
    guard let current = presented, !current.cancelled, let view = current.mirror,
      let webView, webView.window != nil, webView.bounds == current.viewport
    else { return nil }
    let parameters = UIPreviewParameters()
    parameters.backgroundColor = .clear
    return UITargetedPreview(view: view, parameters: parameters)
  }

  /// 分隔条转换为系统内联分组，递归保持名称、语义图标、顺序和危险/禁用状态。
  private func menu(_ current: CardMenuCandidate) -> UIMenu {
    let snapshot = current.menu
    let choose: (String, Bool) -> Void = { [weak self, weak current] id, keepOpen in
      guard let self, let current, self.candidate === current, !current.cancelled,
        current.menu.presentationId == snapshot.presentationId, current.selection == nil,
        current.menu.availableAction(id: id) != nil
      else { return }
      current.selection = id
      if keepOpen {
        current.selectionDispatched = true
        self.select(snapshot, id)
      }
    }
    return UIMenu(
      title: snapshot.title ?? "", identifier: UIMenu.Identifier("root"),
      children: elements(snapshot.items, enabled: true, choose: choose))
  }

  /// 单个菜单层按分隔符拆分而非排序，禁用或加载的父项同时禁用其全部后代。
  private func elements(
    _ rows: [OperationMenuItem], enabled: Bool, choose: @escaping (String, Bool) -> Void
  ) -> [UIMenuElement] {
    var groups: [[UIMenuElement]] = [[]]
    for row in rows {
      if row.kind == .separator {
        groups.append([])
        continue
      }
      let allowed = enabled && row.enabled != false && row.loading != true
      let image = NavigationSymbols.operationImage(row.icon)
      let element: UIMenuElement
      if row.kind == .action || (row.kind == .submenu && !allowed) {
        var attributes: UIMenuElement.Attributes = allowed ? [] : [.disabled]
        if row.destructive == true || row.color == .error { attributes.insert(.destructive) }
        if row.keepOpen == true { attributes.insert(.keepsMenuPresented) }
        let action = UIAction(
          title: row.title ?? "", image: tinted(image, color: row.color),
          identifier: UIAction.Identifier(row.id), attributes: attributes,
          state: row.selected == true ? .on : .off
        ) { _ in choose(row.id, row.keepOpen == true) }
        action.subtitle = row.subtitle
        element = action
      } else {
        element = UIMenu(
          title: row.title ?? "", image: tinted(image, color: row.color),
          identifier: UIMenu.Identifier(row.id),
          options: row.kind == .group ? [.displayInline] : [],
          children: elements(row.items ?? [], enabled: allowed, choose: choose))
      }
      groups[groups.count - 1].append(element)
    }
    if groups.count == 1 { return groups[0] }
    return groups.filter { !$0.isEmpty }.map { UIMenu(options: .displayInline, children: $0) }
  }

  /// 只对图标应用原语义色，菜单文字和背景仍使用 UIKit 系统样式。
  private func tinted(_ image: UIImage?, color: OperationMenuColor?) -> UIImage? {
    guard let color else { return image }
    let tint = NavigationSymbols.operationTint(color, accent: accent)
    return image?.withTintColor(tint, renderingMode: .alwaysOriginal)
  }

  /// 更新保留菜单时按稳定菜单标识找到原子菜单，不跳回列表第一层。
  private func findMenu(_ id: UIMenu.Identifier, in menu: UIMenu) -> UIMenu? {
    if menu.identifier == id { return menu }
    for child in menu.children {
      if let child = child as? UIMenu, let match = findMenu(id, in: child) { return match }
    }
    return nil
  }
}
