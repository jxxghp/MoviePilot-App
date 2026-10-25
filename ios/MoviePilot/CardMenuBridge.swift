import MoviePilotCore
import UIKit
import WebKit

/// 卡片菜单只在同一个文档、身份会话和已确认路由范围内有效。
struct CardMenuContext: Equatable {
  let document: UUID
  let session: String
  let route: Int
}

/// 网页几何来自当次触摸，按当前 viewport 宽度换算为 WebView point。
private struct CardMenuPreparation: Decodable {
  /// CSS 位置不携带 DOM、业务主键或任意原生调用参数。
  struct Rect: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
  }
  /// 当前触摸必须位于卡片和可见 WebView 内部。
  struct Point: Decodable {
    let x: Double
    let y: Double
  }
  /// 不用过期的原生屏幕宽度猜测网页缩放比例。
  struct Viewport: Decodable {
    let width: Double
    let height: Double
  }
  let menu: OperationMenuSnapshot
  let rect: Rect
  let point: Point
  let viewport: Viewport
}

/// 系统手势、辅助操作与桥接之间的窄通道；不保存认证、业务 API 或 JS 闭包。
@MainActor
final class CardMenuBridge {
  private weak var webView: WKWebView?
  private let context: () -> CardMenuContext?
  private let presenter: () -> UIViewController?
  private let send: (String, JSONValue) -> Void
  private var preparedContext: CardMenuContext?
  private var current: OperationMenuSnapshot?
  private var accessibleMenu: OperationMenuController?
  private var interaction: CardMenuInteraction?
  var accent: UIColor = .systemBlue {
    didSet {
      interaction?.accent = accent
      accessibleMenu?.accent = accent
    }
  }

  /// 宿主提供当前状态读取器，每次选择都复核，不依赖最初快照中的权限。
  init(
    webView: WKWebView, context: @escaping () -> CardMenuContext?,
    presenter: @escaping () -> UIViewController?, send: @escaping (String, JSONValue) -> Void
  ) {
    self.webView = webView
    self.context = context
    self.presenter = presenter
    self.send = send
  }

  /// WebView 的交互在页面开始接管时建立，不能等触摸后才注册手势识别器。
  func start() {
    guard interaction == nil, let webView else { return }
    interaction = CardMenuInteraction(
      webView: webView,
      select: { [weak self] menu, item in self?.select(menu, item: item) },
      dismiss: { [weak self] id in self?.dismissed(id) },
      opened: { [weak self] id in self?.opened(id) })
    interaction?.accent = accent
  }

  /// 导航和身份变化同步撤销旧票据；普通进度刷新不打断同一菜单。
  func synchronize() {
    if let preparedContext, preparedContext != context() { invalidate() }
  }

  /// 封闭消息分派与上下文复核共同保护原生展示，不提供任意 selector 或脚本执行。
  func receive(_ message: BridgeEnvelope) throws {
    guard let scope = context(), scope.session == message.sessionId,
      scope.route == message.routeRevision,
      let webView, let interaction
    else { throw BridgeError.actionNotAvailable }
    switch message.type {
    case "cardMenu.prepare", "cardMenu.accessible":
      let payload = try message.decodePayload(CardMenuPreparation.self)
      try payload.menu.validate()
      guard payload.menu.kind == .card, payload.viewport.width.isFinite,
        payload.viewport.height.isFinite, payload.viewport.width > 0, payload.viewport.height > 0
      else { throw BridgeError.invalidMessage }
      invalidate()
      preparedContext = scope
      current = payload.menu
      let scale = webView.bounds.width / payload.viewport.width
      let rect = CGRect(
        x: payload.rect.x * scale, y: payload.rect.y * scale,
        width: payload.rect.width * scale, height: payload.rect.height * scale)
      let point = CGPoint(x: payload.point.x * scale, y: payload.point.y * scale)
      if message.type == "cardMenu.accessible" {
        do {
          try showAccessible(payload.menu)
        } catch {
          invalidate()
          throw error
        }
      } else {
        do {
          try interaction.prepare(menu: payload.menu, rect: rect, point: point)
        } catch {
          invalidate()
          throw error
        }
      }
    case "cardMenu.invalidate":
      guard case .object(let payload) = message.payload,
        case .string(let id) = payload["presentationId"], current?.presentationId == id
      else { return }
      invalidate()
    case "cardMenu.refresh":
      let payload = try message.decodePayload(Refresh.self)
      try payload.menu.validate()
      guard preparedContext == scope, let previous = current,
        previous.ownerId == payload.menu.ownerId, previous.menuId == payload.menu.menuId,
        previous.kind == payload.menu.kind, previous.presentationId != payload.menu.presentationId
      else { throw BridgeError.actionNotAvailable }
      do {
        if let accessibleMenu {
          accessibleMenu.refresh(payload.menu)
        } else {
          try interaction.refresh(menu: payload.menu)
        }
        current = payload.menu
      } catch {
        invalidate()
        throw error
      }
    default: throw BridgeError.invalidMessage
    }
  }

  /// 停止或切换实例时清除交互，不能让旧 WebView 保留菜单和系统预览。
  func stop() {
    invalidate()
    interaction?.stop()
    interaction = nil
    webView = nil
  }

  /// 上下文失效先封闭选择，再结束两个系统承载器；旧关闭回调不清除新票据。
  func invalidate() {
    if let current, preparedContext == context() {
      send("cardMenu.dismissed", .object(["presentationId": .string(current.presentationId)]))
    }
    current = nil
    preparedContext = nil
    let accessible = accessibleMenu
    accessibleMenu = nil
    accessible?.invalidate()
    interaction?.invalidate()
  }

  /// 新票据只替换已有保留菜单，不接受另一份业务声明切换当前来源。
  private struct Refresh: Decodable {
    let menu: OperationMenuSnapshot
  }

  /// VoiceOver 与键盘使用同样的原生动作及单次票据，避免隐藏三点后只剩长按手势。
  private func showAccessible(_ menu: OperationMenuSnapshot) throws {
    guard let host = presenter(), !host.isBeingDismissed else {
      throw BridgeError.actionNotAvailable
    }
    let controller = OperationMenuController(
      menu: menu, choose: { [weak self] menu, item in self?.select(menu, item: item) },
      cancel: { [weak self] id in self?.dismissed(id) })
    controller.accent = accent
    let navigation = UINavigationController(rootViewController: controller)
    navigation.overrideUserInterfaceStyle = host.traitCollection.userInterfaceStyle
    controller.configureSheet(navigation)
    accessibleMenu = controller
    host.present(navigation, animated: true) { [weak self] in self?.opened(menu.presentationId) }
  }

  /// 只有当前系统展示确实开始后才取消网页准备阶段的短超时。
  private func opened(_ id: String) {
    guard current?.presentationId == id, preparedContext == context() else { return }
    send("cardMenu.opened", .object(["presentationId": .string(id)]))
  }

  /// 正常动作由 UIKit 动画完成回调触发，发给网页之前再次核对完整原生状态。
  private func select(_ menu: OperationMenuSnapshot, item: String) {
    guard preparedContext == context(), let current, current == menu,
      current.availableAction(id: item) != nil
    else { return }
    send(
      "cardMenu.select",
      .object([
        "presentationId": .string(menu.presentationId), "itemId": .string(item),
      ]))
    if current.availableAction(id: item)?.keepOpen != true {
      self.current = nil
      accessibleMenu = nil
      preparedContext = nil
    }
  }

  /// 迟到的关闭只结算自己的展示，不会取消下一张卡片或新身份的菜单。
  private func dismissed(_ id: String) {
    guard current?.presentationId == id else { return }
    if preparedContext == context() {
      send("cardMenu.dismissed", .object(["presentationId": .string(id)]))
    }
    current = nil
    accessibleMenu = nil
    preparedContext = nil
  }
}
