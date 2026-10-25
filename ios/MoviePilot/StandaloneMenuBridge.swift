import MoviePilotCore
import UIKit

/// 独立菜单使用系统有界操作列表，原生只回传当前展示和动作标识。
@MainActor
final class StandaloneMenuBridge {
  /// 无几何、路径、认证或可执行脚本的完整菜单声明。
  private struct Payload: Decodable {
    let menu: OperationMenuSnapshot
  }

  private let context: () -> OperationMenuContext?
  private let presenter: () -> UIViewController?
  private let send: (String, JSONValue) -> Void
  private var scope: OperationMenuContext?
  private var current: OperationMenuSnapshot?
  private var controller: OperationMenuController?
  private var closing = false
  private var awaitingRefresh = false
  var accent: UIColor = .systemBlue {
    didSet { controller?.accent = accent }
  }

  /// 每次展示和选择都读取宿主当前范围，不保存最初快照中的身份或权限。
  init(
    context: @escaping () -> OperationMenuContext?,
    presenter: @escaping () -> UIViewController?, send: @escaping (String, JSONValue) -> Void
  ) {
    self.context = context
    self.presenter = presenter
    self.send = send
  }

  /// 导航、身份或生命周期改变时关闭旧列表，不保留可点击的旧来源。
  func synchronize() {
    if let scope, scope != context() { invalidate() }
  }

  /// 只接受双方已协商的当前主文档消息，菜单完整校验后才交给 UIKit。
  func receive(_ message: BridgeEnvelope) throws {
    guard let context = context(), context.session == message.sessionId,
      context.route == message.routeRevision
    else { throw BridgeError.actionNotAvailable }
    switch message.type {
    case "standaloneMenu.open":
      let payload = try message.decodePayload(Payload.self)
      try payload.menu.validate()
      guard payload.menu.kind == .standalone, current == nil, !closing else {
        throw BridgeError.actionNotAvailable
      }
      try present(payload.menu, scope: context)
    case "standaloneMenu.refresh":
      let payload = try message.decodePayload(Payload.self)
      try payload.menu.validate()
      guard scope == context, awaitingRefresh, let previous = current,
        payload.menu.kind == .standalone, previous.ownerId == payload.menu.ownerId,
        previous.menuId == payload.menu.menuId,
        previous.presentationId != payload.menu.presentationId, let controller
      else { throw BridgeError.actionNotAvailable }
      current = payload.menu
      awaitingRefresh = false
      controller.refresh(payload.menu)
    case "standaloneMenu.invalidate":
      guard case .object(let payload) = message.payload,
        case .string(let id) = payload["presentationId"], current?.presentationId == id
      else { return }
      invalidate()
    default: throw BridgeError.invalidMessage
    }
  }

  /// 撤销先封闭选择，再等待系统控制器退出；动画中不能叠加下一张列表。
  func invalidate() {
    if let current, scope == context() {
      send("standaloneMenu.dismissed", .object(["presentationId": .string(current.presentationId)]))
    }
    current = nil
    scope = nil
    awaitingRefresh = false
    guard let active = controller else { return }
    controller = nil
    closing = true
    active.invalidate { [weak self] in self?.closing = false }
  }

  /// 材质、标题栏与关闭操作使用系统行为，实际内容高度由共享列表量测。
  private func present(_ menu: OperationMenuSnapshot, scope: OperationMenuContext) throws {
    guard let host = presenter(), !host.isBeingDismissed,
      host.presentedViewController == nil,
      !(host is UIAlertController),
      !((host as? UINavigationController)?.topViewController is OperationMenuController)
    else { throw BridgeError.actionNotAvailable }
    let content = OperationMenuController(
      menu: menu,
      choose: { [weak self] menu, item in self?.select(menu, item: item) },
      cancel: { [weak self] id in self?.dismissed(id) })
    content.accent = accent
    let navigation = UINavigationController(rootViewController: content)
    navigation.overrideUserInterfaceStyle = host.traitCollection.userInterfaceStyle
    content.configureSheet(navigation, presentingView: host.view)
    current = menu
    self.scope = scope
    controller = content
    host.present(navigation, animated: true) { [weak self] in
      guard let self, self.current?.presentationId == menu.presentationId,
        self.scope == self.context()
      else { return }
      self.send("standaloneMenu.opened", .object(["presentationId": .string(menu.presentationId)]))
    }
  }

  /// 正常选择由系统退出动画完成回调触发，保持展开动作等待网页的新单次票据。
  private func select(_ menu: OperationMenuSnapshot, item: String) {
    guard scope == context(), let current, current == menu, !awaitingRefresh,
      let action = current.availableAction(id: item)
    else { return }
    awaitingRefresh = action.keepOpen == true
    send(
      "standaloneMenu.select",
      .object([
        "presentationId": .string(menu.presentationId), "itemId": .string(item),
      ]))
    if !awaitingRefresh {
      self.current = nil
      scope = nil
      controller = nil
    }
  }

  /// 关闭只结算自己的展示，迟到回调不能清除下一份菜单或新身份。
  private func dismissed(_ id: String) {
    guard current?.presentationId == id else { return }
    if scope == context() {
      send("standaloneMenu.dismissed", .object(["presentationId": .string(id)]))
    }
    current = nil
    scope = nil
    controller = nil
    awaitingRefresh = false
  }
}
