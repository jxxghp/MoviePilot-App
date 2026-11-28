import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit
@preconcurrency import WebKit

/// 专用于 Agent 助手插件形象（`stage` / `renderer`）的独立透明 `WKWebView` 控制器：
/// - 与普通插件页面共享池完全隔离，打开任意插件页面/设置弹窗绝不会驱逐悬浮宠物；
/// - `stage` 模式支持通过 `pet.setBubbleAnchor(rect)` 与 `pet.setInteracting(bool)` 进行像素级原生触摸穿透；
/// - 发生加载超时、脚本异常或 WebContent 进程被回收时自动触发回退回调，无缝退回原生内置机器人。
@MainActor
final class NativeAgentPetWebController: NSObject, ObservableObject, WKNavigationDelegate,
  UIScrollViewDelegate
{
  @Published private(set) var isMounted = false
  @Published private(set) var anchorRect: CGRect? = nil
  @Published private(set) var isInteracting = false
  @Published private(set) var speechBubbleText: String? = nil

  let webView: WKWebView
  let schemeHandler: PluginShellSchemeHandler
  let bridge: PluginHostBridgeV2

  private var isShellReady = false
  private var pendingMountPayload: [String: Any]?
  private var latestAgentState: [String: Any]?
  private var latestVisualTokens: PluginVisualTokensSnapshot?
  private var mountedPetID: String?
  private var lastValidAnchorRect: CGRect?
  private var loadTimeoutTask: Task<Void, Never>?
  private var bubbleDismissTask: Task<Void, Never>?
  private var isDisposed = false

  var onOpenAgent: ((_ draft: String?) -> Void)?
  var onCloseAgent: (() -> Void)?
  var onFailed: ((_ reason: String) -> Void)?

  /// 创建与普通插件页面隔离的透明渲染器，并在整个形象生命周期内保留桥接。
  override init() {
    let handler = PluginShellSchemeHandler()
    let hostBridge = PluginHostBridgeV2()
    self.schemeHandler = handler
    self.bridge = hostBridge

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []
    if UIDevice.current.userInterfaceIdiom == .phone {
      config.defaultWebpagePreferences.preferredContentMode = .mobile
    }
    config.setURLSchemeHandler(handler, forURLScheme: PluginShellSchemeHandler.scheme)
    config.userContentController.add(
      WeakPluginHostBridgeV2Handler(hostBridge),
      name: PluginHostBridgeV2.handlerName
    )

    let initialBounds = UIScreen.main.bounds
    let frame =
      initialBounds.width > 0 ? initialBounds : CGRect(x: 0, y: 0, width: 390, height: 844)
    let wv = WKWebView(frame: frame, configuration: config)
    wv.isOpaque = false
    wv.backgroundColor = .clear
    wv.underPageBackgroundColor = .clear
    wv.scrollView.isScrollEnabled = false
    wv.scrollView.bounces = false
    wv.scrollView.delaysContentTouches = false
    wv.scrollView.canCancelContentTouches = false
    wv.scrollView.panGestureRecognizer.isEnabled = false
    wv.scrollView.pinchGestureRecognizer?.isEnabled = false
    wv.scrollView.backgroundColor = .clear
    wv.scrollView.contentInsetAdjustmentBehavior = .never
    wv.scrollView.showsVerticalScrollIndicator = false
    wv.scrollView.showsHorizontalScrollIndicator = false
    self.webView = wv

    super.init()

    wv.navigationDelegate = self
    wv.scrollView.delegate = self
    Self.disableSystemDragInteractions(in: wv)
    hostBridge.webView = wv
    bindBridge()
    wv.load(URLRequest(url: PluginShellSchemeHandler.entryURL))
  }

  /// 仅在形象控制器真正释放时拆除运行时，避免临时视图退场使其永久失效。
  isolated deinit {
    dispose()
  }

  /// 关闭系统对 WebView 手势的抢占以保留原生拖动行为。
  private static func disableSystemDragInteractions(in rootView: UIView) {
    for interaction in rootView.interactions {
      if let drag = interaction as? UIDragInteraction {
        drag.isEnabled = false
      }
    }
    for subview in rootView.subviews {
      disableSystemDragInteractions(in: subview)
    }
  }

  /// 绑定插件消息桥并接收 Agent 状态与交互事件。
  private func bindBridge() {
    bridge.onShellReady = { [weak self] in
      guard let self, !self.isDisposed else { return }
      self.isShellReady = true
      if var payload = self.pendingMountPayload {
        self.pendingMountPayload = nil
        if let latest = self.latestAgentState {
          payload["agentHostState"] = latest
        }
        self.bridge.sendToWeb(type: "plugin.mount", payload: payload)
      }
    }
    bridge.onPluginMounted = { [weak self] _, _ in
      guard let self, !self.isDisposed else { return }
      self.loadTimeoutTask?.cancel()
      self.loadTimeoutTask = nil
      Self.disableSystemDragInteractions(in: self.webView)
      self.isMounted = true
      if let latest = self.latestAgentState {
        self.bridge.sendAgentState(latest)
      }
    }
    bridge.onPluginError = { [weak self] _, message, _ in
      guard let self, !self.isDisposed else { return }
      self.loadTimeoutTask?.cancel()
      self.loadTimeoutTask = nil
      self.isMounted = false
      self.onFailed?(message.isEmpty ? "插件组件运行出错" : message)
    }
    bridge.onAgentOpen = { [weak self] draft in
      // 延后到下一主线程循环再弹起聊天 Sheet，确保 WKContentView 完整结束当前触摸/点击抬手周期，避免二次点击手势卡死
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isDisposed else { return }
        self.isInteracting = false
        self.onOpenAgent?(draft)
      }
    }
    bridge.onAgentClose = { [weak self] in
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.isDisposed else { return }
        self.onCloseAgent?()
      }
    }
    bridge.onAgentPetAnchor = { [weak self] rect in
      guard let self, !self.isDisposed else { return }
      if let rect, rect.width > 0, rect.height > 0 {
        self.lastValidAnchorRect = rect
        self.anchorRect = rect
      } else {
        // 插件在面板打开期间可能调用 setBubbleAnchor(null)，保留上一次有效角色位置供关闭面板后立即恢复点击热区
        self.anchorRect = self.lastValidAnchorRect
      }
    }
    bridge.onAgentPetInteracting = { [weak self] active in
      self?.isInteracting = active
    }
    bridge.onAgentPetSay = { [weak self] text, durationMs in
      self?.showSpeechBubble(text: text, durationMs: durationMs)
    }
  }

  /// 展示助手说话内容并按指定时长自动收起。
  func showSpeechBubble(text: String, durationMs: Int) {
    bubbleDismissTask?.cancel()
    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
      speechBubbleText = text
    }
    bubbleDismissTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(durationMs))
      guard !Task.isCancelled, let self else { return }
      withAnimation(.easeOut(duration: 0.2)) {
        self.speechBubbleText = nil
      }
    }
  }

  /// 挂载插件入口、注入宿主能力并开始加载助手界面。
  func mount(
    pet: NativeAgentPetDeclaration,
    session: NativeSession,
    visualTokens: PluginVisualTokensSnapshot,
    initialAgentState: [String: Any],
    safeArea: EdgeInsets
  ) async {
    guard !isDisposed else { return }
    if mountedPetID == pet.id && isMounted {
      pushAgentState(initialAgentState)
      return
    }

    mountedPetID = pet.id
    latestAgentState = initialAgentState
    isMounted = false
    anchorRect = nil
    lastValidAnchorRect = nil
    isInteracting = false
    speechBubbleText = nil
    loadTimeoutTask?.cancel()

    do {
      let auth = try session.playbackAuthorization()
      let cookie = try? await session.resolveResourceCookie()
      guard !Task.isCancelled, !isDisposed else { return }
      let locale = AppLanguage.current.rawValue
      let ctx = PluginShellSchemeHandler.SessionContext(
        address: auth.address,
        accessToken: auth.accessToken,
        resourceCookie: cookie,
        locale: locale
      )
      schemeHandler.updateSessionContext(ctx)
      schemeHandler.nativeSession = session
      bridge.updateSessionContext(ctx)
      bridge.nativeSession = session

      let rawRemoteURL: String
      if let declared = pet.remoteURL, !declared.isEmpty {
        rawRemoteURL = declared
      } else {
        rawRemoteURL = try await discoverRemoteURL(for: pet.pluginID, session: session)
      }
      guard !Task.isCancelled, !isDisposed else { return }

      let entryPlan = try PluginRemoteRuntime.normalizeRemoteEntry(
        pluginId: pet.resolvedSourcePluginID,
        versionOrHash: pet.pluginVersion ?? "",
        rawRemoteURL: rawRemoteURL
      )
      let virtualEntryURL = "\(PluginShellSchemeHandler.origin)\(entryPlan.virtualEntryPath)"

      let visualTokensObj: [String: Any]
      if let encoded = try? JSONEncoder().encode(visualTokens),
        let obj = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any]
      {
        visualTokensObj = obj
      } else {
        visualTokensObj = [:]
      }

      let user = session.user
      let mountPayload: [String: Any] = [
        "mountId": "pet-\(UUID().uuidString)",
        "pluginId": pet.pluginID,
        "sourcePluginId": pet.resolvedSourcePluginID,
        "pluginName": pet.resolvedPluginName,
        "pluginVersion": pet.pluginVersion ?? "",
        "surface": "agentPet",
        "exposeComponent": pet.resolvedComponent,
        "agentPet": [
          "key": pet.key,
          "mode": pet.mode,
          "bubbles": pet.bubbles ?? "host",
          "name": pet.name,
        ],
        "agentHostState": latestAgentState ?? initialAgentState,
        "remoteEntryUrl": virtualEntryURL,
        "locale": locale,
        "visualTokens": visualTokensObj,
        "safeArea": [
          "top": Double(safeArea.top),
          "bottom": Double(safeArea.bottom),
          "left": Double(safeArea.leading),
          "right": Double(safeArea.trailing),
        ],
        "user": [
          "id": user.id,
          "superUser": user.isSuperuser,
          "userName": user.name,
          "avatar": user.avatar,
          "level": user.level,
          "permissions": [
            "discovery": user.allows(.init(category: .discovery)),
            "search": user.allows(.init(category: .search)),
            "subscribe": user.allows(.init(category: .subscribe)),
            "manage": user.allows(.init(category: .manage)),
            "admin": user.allows(.init(category: .admin)),
          ],
        ],
      ]

      loadTimeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(10))
        guard !Task.isCancelled, let self, !self.isMounted else { return }
        self.onFailed?("加载超时")
      }

      if isShellReady {
        bridge.sendToWeb(type: "plugin.mount", payload: mountPayload)
      } else {
        pendingMountPayload = mountPayload
      }
    } catch {
      onFailed?(error.localizedDescription.isEmpty ? "无法解析联邦入口" : error.localizedDescription)
    }
  }

  /// 从服务端插件信息解析当前助手的远程资源入口。
  private func discoverRemoteURL(for pluginID: String, session: NativeSession) async throws
    -> String
  {
    let ep = try APIEndpoint(
      path: ["plugin", "remotes"],
      query: [URLQueryItem(name: "token", value: "moviepilot")],
      responseContract: .payload
    )
    let raw = try await session.requestPayload(ep).value
    let decoder = JSONDecoder()
    let list: [PluginRemoteDescriptor]
    if let direct = try? decoder.decode([PluginRemoteDescriptor].self, from: raw) {
      list = direct
    } else {
      /// 解码插件远程入口查询接口的负载。
      struct Envelope: Decodable { let data: [PluginRemoteDescriptor]? }
      list = (try? decoder.decode(Envelope.self, from: raw))?.data ?? []
    }
    guard let match = list.first(where: { $0.id.caseInsensitiveCompare(pluginID) == .orderedSame })
    else {
      throw NSError(
        domain: "AgentPet", code: -1, userInfo: [NSLocalizedDescriptionKey: "未找到插件联邦入口"])
    }
    return match.url
  }

  /// 将最新 Agent 会话状态推送给插件运行时。
  func pushAgentState(_ patch: [String: Any]) {
    if let latestAgentState, NSDictionary(dictionary: latestAgentState).isEqual(to: patch) {
      return
    }
    latestAgentState = patch
    if var pending = pendingMountPayload {
      pending["agentHostState"] = patch
      pendingMountPayload = pending
    }
    guard isShellReady else { return }
    bridge.sendAgentState(patch)
  }

  /// 将原生主题视觉令牌同步给插件界面。
  func pushVisualTokens(_ tokens: PluginVisualTokensSnapshot) {
    guard isShellReady, latestVisualTokens != tokens else { return }
    latestVisualTokens = tokens
    bridge.sendVisualTokens(tokens)
  }

  /// 通知插件宿主 Agent 面板的展开状态发生变化。
  func notifyPanelChanged(panelOpen: Bool) {
    if panelOpen {
      isInteracting = false
    } else if anchorRect == nil, let fallback = lastValidAnchorRect {
      anchorRect = fallback
    }
    guard isShellReady else { return }
    bridge.sendAgentEvent(name: panelOpen ? "agent.panel.open" : "agent.panel.close")
  }

  /// 拆除桥接、计时器和 WebView 资源以结束运行。
  func dispose() {
    guard !isDisposed else { return }
    isDisposed = true
    lastValidAnchorRect = nil
    loadTimeoutTask?.cancel()
    loadTimeoutTask = nil
    bubbleDismissTask?.cancel()
    bubbleDismissTask = nil
    bridge.sendUnmount()
    bridge.abortAllInFlightRequests()
    bridge.cleanupNativeCapabilities()
    bridge.clearCallbacks()
    schemeHandler.cancelAllRequests()
    schemeHandler.updateSessionContext(nil)
    webView.scrollView.delegate = nil
    webView.navigationDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: PluginHostBridgeV2.handlerName)
  }

  /// 同步滚动变化，维持浮层内容与宿主页面的布局关系。
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    // 防止聊天面板弹起系统键盘时把底层宠物透明 WebView 的内容偏移顶歪，保证坐标始终 1:1 对齐屏幕
    if scrollView.contentOffset != .zero {
      scrollView.setContentOffset(.zero, animated: false)
    }
  }

  /// 主文档加载完成后同步插件运行时状态。
  nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      Self.disableSystemDragInteractions(in: webView)
    }
  }

  /// Web 内容进程退出时清理当前宠物运行状态。
  nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    Task { @MainActor [weak self] in
      guard let self, !self.isDisposed else { return }
      self.isMounted = false
      self.onFailed?("渲染进程中断")
    }
  }
}

/// 支持像素级热区触摸穿透的透明舞台宿主视图（iOS `UIView.hitTest`）：
/// - `passthroughEnabled == false`（如 `renderer` 模式或 `isInteracting == true`）时正常响应触摸；
/// - `passthroughEnabled == true`（`stage` 全屏舞台）时仅在角色 `anchorRect`（含 ±16pt 手指容差）内接管触摸，
///   其余全屏空白区域直接返回 `nil`，100% 穿透给底层任意原生页面（滚动、点击、右滑返回全无阻挡）。
final class NativeAgentPetPassthroughContainer: UIView {
  var isCaptureEnabled: Bool = true
  var passthroughEnabled: Bool = false
  var interactiveRect: CGRect? = nil
  var forceCaptureAll: Bool = false
  var onAccessibilityOpen: (() -> Void)?

  /// 无障碍焦点跟随插件角色上报的热区，不覆盖全屏透明舞台。
  override var accessibilityFrame: CGRect {
    get {
      guard passthroughEnabled, let interactiveRect else { return super.accessibilityFrame }
      return UIAccessibility.convertToScreenCoordinates(interactiveRect, in: self)
    }
    set { super.accessibilityFrame = newValue }
  }

  /// 允许 VoiceOver 用户直接打开当前插件助手。
  override func accessibilityActivate() -> Bool {
    guard isCaptureEnabled, let onAccessibilityOpen else { return false }
    onAccessibilityOpen()
    return true
  }

  /// 判断触点是否落入当前插件助手的可交互区域。
  private func shouldCapture(point: CGPoint) -> Bool {
    guard isCaptureEnabled, !isHidden, alpha > 0.01 else { return false }
    if !passthroughEnabled {
      return bounds.contains(point)
    }
    if forceCaptureAll {
      return bounds.contains(point)
    }
    guard let rect = interactiveRect, rect.width > 0, rect.height > 0 else {
      return false
    }
    return rect.insetBy(dx: -24, dy: -24).contains(point)
  }

  /// 在不命中助手交互区域时让触摸穿透到下层窗口。
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    shouldCapture(point: point)
  }

  /// 把命中测试限制到助手实际可交互的视图范围。
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard shouldCapture(point: point) else {
      return nil
    }
    return super.hitTest(point, with: event)
  }
}

/// 将宠物 WebView 控制器接入 SwiftUI 生命周期。
private struct NativeAgentPetWebViewRepresentable: UIViewRepresentable {
  let webView: WKWebView
  let preferDark: Bool
  let isCaptureEnabled: Bool
  let passthroughEnabled: Bool
  let interactiveRect: CGRect?
  let forceCaptureAll: Bool
  var onRuntimeUpdate: (() -> Void)? = nil
  var accessibilityName: String? = nil
  var onAccessibilityOpen: (() -> Void)? = nil

  /// 创建用于承载透明插件 WebView 的 UIKit 容器。
  func makeUIView(context: Context) -> NativeAgentPetPassthroughContainer {
    let container = NativeAgentPetPassthroughContainer(frame: .zero)
    container.backgroundColor = .clear
    container.isOpaque = false
    attachWebView(into: container)
    return container
  }

  /// 根据 SwiftUI 状态更新容器及其 WebView 内容。
  func updateUIView(_ container: NativeAgentPetPassthroughContainer, context: Context) {
    if webView.superview !== container {
      attachWebView(into: container)
    }
    container.isCaptureEnabled = isCaptureEnabled
    container.passthroughEnabled = passthroughEnabled
    container.interactiveRect = interactiveRect
    container.forceCaptureAll = forceCaptureAll
    container.isAccessibilityElement =
      accessibilityName != nil && isCaptureEnabled && interactiveRect != nil
    container.accessibilityLabel = accessibilityName
    container.accessibilityIdentifier =
      accessibilityName == nil ? nil : "native-agent-plugin-pet-stage"
    container.accessibilityTraits = .button
    container.onAccessibilityOpen = onAccessibilityOpen
    // 始终保持 WKWebView 自身交互与可见态激活，仅由外层 NativeAgentPetPassthroughContainer.hitTest 控制穿透，
    // 避免 WebKit 因 UIKit alpha=0 / isUserInteractionEnabled=false 触发页面休眠而导致关闭对话弹窗后数秒内点击无响应
    webView.isUserInteractionEnabled = true
    webView.overrideUserInterfaceStyle = preferDark ? .dark : .light
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.underPageBackgroundColor = .clear
    onRuntimeUpdate?()
  }

  /// 把控制器管理的 WebView 接入透明宿主容器。
  private func attachWebView(into container: NativeAgentPetPassthroughContainer) {
    webView.removeFromSuperview()
    webView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: container.topAnchor),
      webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
  }
}

/// 独立于主 `UITabBarController` / `NavigationStack` 视图树的透明穿透悬浮窗：
/// - 挂载在 `UIWindow.Level.normal + 1`，彻底杜绝任何 `.sheet` 模态弹出/收起后 `TabView` 视图层级上浮盖住助手形象或吞掉点击；
/// - `canBecomeKey == false` 不抢占主窗口输入焦点或键盘；
/// - 仅在角色真实热区（或拖拽手势中）捕获触摸，其余全屏区域在 `UIWindow.hitTest` 层直接返回 `nil`，100% 穿透给主窗口。
@MainActor
final class NativeAgentPetPassthroughWindow: UIWindow {
  var isCaptureEnabled: Bool = false
  var forceFullCapture: Bool = false
  var interactiveRect: CGRect? = nil

  override var canBecomeKey: Bool { false }

  /// 判断触点是否落入当前插件助手的可交互区域。
  private func shouldCapture(point: CGPoint) -> Bool {
    guard !isHidden, alpha > 0.01 else { return false }
    if let rootVC = rootViewController, rootVC.presentedViewController != nil {
      return bounds.contains(point)
    }
    guard isCaptureEnabled else { return false }
    if forceFullCapture {
      return bounds.contains(point)
    }
    guard let rect = interactiveRect, rect.width > 0, rect.height > 0 else {
      return false
    }
    return rect.insetBy(dx: -24, dy: -24).contains(point)
  }

  /// 在不命中助手交互区域时让触摸穿透到下层窗口。
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    shouldCapture(point: point)
  }

  /// 把命中测试限制到助手实际可交互的视图范围。
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard shouldCapture(point: point) else {
      return nil
    }
    return super.hitTest(point, with: event)
  }
}

/// 维护全界面 Agent 助手独立穿透 `UIWindow` 及主窗口任意弹窗（`.sheet` / `.alert` / `.fullScreenCover`）实时遮挡状态。
@MainActor
final class NativeAgentPetWindowState: ObservableObject {
  @Published var isModalOccluded: Bool = false
  @Published var isSceneActive: Bool = false
  @Published var hardwareSafeArea: EdgeInsets = .init(top: 59, leading: 0, bottom: 34, trailing: 0)
  @Published var presentation = NativeAgentPetPresentationState()
}

/// 主窗口交付的助手展示快照；独立窗口持续观察，避免替换根视图遗失状态变化。
struct NativeAgentPetPresentationState: Equatable {
  var isVisible = false
  var panelOpen = false
  var dockVisible = true
  var thinking = false
  var verticalBarEdge: NativeDeviceLayout.VerticalBarEdge = .none
}

@MainActor
/// 协调宠物悬浮窗口挂载、命中区域和模态状态。
final class NativeAgentPetWindowCoordinator {
  static let shared = NativeAgentPetWindowCoordinator()

  private var overlayWindow: NativeAgentPetPassthroughWindow?
  private var hostingController: UIHostingController<AnyView>?
  private weak var hostMainWindow: UIWindow?
  private weak var anchorView: UIView?
  private var modalWatchTimer: Timer?
  private var desiredCaptureEnabled: Bool = false
  private var desiredInteractiveRect: CGRect? = nil
  private var desiredForceFullCapture: Bool = false
  private var isContextMenuVisible = false
  let windowState = NativeAgentPetWindowState()

  /// 保持全应用唯一的助手窗口协调器。
  private init() {}

  /// 更新浮层窗口接收触摸的区域和全屏捕获策略。
  func updateHitRegion(isCaptureEnabled: Bool, interactiveRect: CGRect?, forceFullCapture: Bool) {
    desiredCaptureEnabled = isCaptureEnabled
    desiredInteractiveRect = interactiveRect
    desiredForceFullCapture = forceFullCapture
    applyDesiredHitRegion()
  }

  /// 原生快捷菜单超出角色热区时，由助手窗口接收菜单按钮点击。
  func setContextMenuVisible(_ visible: Bool) {
    isContextMenuVisible = visible
    applyDesiredHitRegion()
  }

  /// 系统弹窗关闭后重新读取主窗口状态，及时恢复助手浮层。
  func refreshAfterModalDismissal() {
    Task { @MainActor [weak self] in
      await Task.yield()
      self?.syncSafeAreaAndModalState()
    }
  }

  /// 把当前命中区域配置应用到实际悬浮窗口。
  private func applyDesiredHitRegion() {
    guard let overlayWindow else { return }
    let occluded = windowState.isModalOccluded
    overlayWindow.isCaptureEnabled = (desiredCaptureEnabled || isContextMenuVisible) && !occluded
    overlayWindow.interactiveRect = desiredInteractiveRect
    overlayWindow.forceFullCapture = (desiredForceFullCapture || isContextMenuVisible) && !occluded
  }

  /// 挂载或更新与锚点关联的助手浮层窗口。
  func attachOrUpdate<Content: View>(
    anchor: UIView,
    presentation: NativeAgentPetPresentationState,
    @ViewBuilder content: () -> Content
  ) {
    let sameAnchor = self.anchorView === anchor
    self.anchorView = anchor
    guard let mainWindow = anchor.window, let scene = mainWindow.windowScene else {
      return
    }
    self.hostMainWindow = mainWindow
    syncSafeAreaAndModalState()

    if let existingWindow = overlayWindow, existingWindow.windowScene === scene,
      hostingController != nil, sameAnchor
    {
      if existingWindow.frame != scene.screen.bounds {
        existingWindow.frame = scene.screen.bounds
      }
      existingWindow.isHidden = false
    } else {
      detachWindowOnly()
      let win = NativeAgentPetPassthroughWindow(windowScene: scene)
      win.frame = scene.screen.bounds
      win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
      win.backgroundColor = .clear
      win.isOpaque = false

      let hc = UIHostingController(rootView: AnyView(content()))
      hc.view.backgroundColor = .clear
      hc.view.isOpaque = false
      if #available(iOS 16.4, *) {
        hc.safeAreaRegions = []
      }
      win.rootViewController = hc
      win.isHidden = false
      self.overlayWindow = win
      self.hostingController = hc
    }
    // UIViewRepresentable 更新期间不发布 SwiftUI 状态；按主线程顺序交付最新快照。
    DispatchQueue.main.async { [weak self, weak anchor] in
      guard let self, let anchor, self.anchorView === anchor else { return }
      if self.windowState.presentation != presentation {
        self.windowState.presentation = presentation
      }
    }
    startModalWatchTimerIfNeeded()
  }

  /// 按锚点身份拆除关联的助手浮层窗口。
  func detach(matching anchor: UIView? = nil) {
    if let anchor, let current = self.anchorView, anchor !== current {
      return
    }
    self.anchorView = nil
    self.hostMainWindow = nil
    isContextMenuVisible = false
    modalWatchTimer?.invalidate()
    modalWatchTimer = nil
    detachWindowOnly()
  }

  /// 释放窗口实例并清理其状态观察关系。
  private func detachWindowOnly() {
    overlayWindow?.isHidden = true
    overlayWindow?.rootViewController = nil
    overlayWindow = nil
    hostingController = nil
  }

  /// 在需要时启动模态呈现状态轮询。
  private func startModalWatchTimerIfNeeded() {
    guard modalWatchTimer == nil else { return }
    let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.syncSafeAreaAndModalState()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    modalWatchTimer = timer
  }

  /// 同步安全区并在系统模态出现时隐藏悬浮层。
  func syncSafeAreaAndModalState() {
    guard let anchor = anchorView, let mainWindow = anchor.window ?? hostMainWindow else {
      if !windowState.isModalOccluded {
        windowState.isModalOccluded = true
      }
      overlayWindow?.isCaptureEnabled = false
      return
    }
    let sceneActive = mainWindow.windowScene?.activationState == .foregroundActive
    if windowState.isSceneActive != sceneActive {
      windowState.isSceneActive = sceneActive
    }
    if let overlayWindow, let scene = mainWindow.windowScene,
      overlayWindow.frame != scene.screen.bounds
    {
      overlayWindow.frame = scene.screen.bounds
    }
    let ui = mainWindow.safeAreaInsets
    let nextSafe = EdgeInsets(top: ui.top, leading: ui.left, bottom: ui.bottom, trailing: ui.right)
    if windowState.hardwareSafeArea != nextSafe {
      windowState.hardwareSafeArea = nextSafe
    }

    // 锚点是零尺寸的 SwiftUI 探针，系统可在弹窗转场后隐藏该视图。
    // 它只负责确定所属窗口，不能用它的可见性决定独立悬浮窗口是否显示。
    let modalPresented: Bool = {
      guard let rootVC = mainWindow.rootViewController else { return false }
      return Self.hasPresentedModal(in: rootVC)
    }()
    let nextOccluded = mainWindow.isHidden || modalPresented
    if windowState.isModalOccluded != nextOccluded {
      windowState.isModalOccluded = nextOccluded
    }
    applyDesiredHitRegion()
  }

  /// 依据展示状态和实际窗口附着检查控制器层级中的系统模态界面。
  private static func hasPresentedModal(in vc: UIViewController) -> Bool {
    if let presented = vc.presentedViewController {
      let transition = presented.transitionCoordinator
      if presented.isBeingDismissed {
        // 交互式下拉若被取消，视图会继续留在窗口中，下一轮轮询会保持遮挡。
        if transition?.isInteractive == true || presented.viewIfLoaded?.window != nil {
          return true
        }
      } else if presented.isBeingPresented || presented.viewIfLoaded?.window != nil {
        return true
      }
    }
    for child in vc.children {
      if hasPresentedModal(in: child) {
        return true
      }
    }
    return false
  }
}

/// 将 SwiftUI 宿主视图锚定到 UIKit 浮层窗口。
private struct NativeAgentPetWindowAnchor<OverlayContent: View>: UIViewRepresentable {
  let content: OverlayContent
  let presentation: NativeAgentPetPresentationState

  /// 保存独立窗口内容；探针自身不参与浮层可见性判断。
  init(
    presentation: NativeAgentPetPresentationState, @ViewBuilder content: () -> OverlayContent
  ) {
    self.content = content()
    self.presentation = presentation
  }

  /// 创建仅用于识别主窗口的零尺寸探针。
  func makeUIView(context: Context) -> UIView {
    let view = NativeAgentPetWindowMountProbeView()
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    let captured = content
    let snapshot = presentation
    view.onWindowChanged = { [weak view] in
      guard let view, view.window != nil else { return }
      NativeAgentPetWindowCoordinator.shared.attachOrUpdate(anchor: view, presentation: snapshot) {
        captured
      }
    }
    return view
  }

  /// 在 SwiftUI 状态变化时更新独立窗口内容与挂载回调。
  func updateUIView(_ uiView: UIView, context: Context) {
    let captured = content
    let snapshot = presentation
    if let probe = uiView as? NativeAgentPetWindowMountProbeView {
      probe.onWindowChanged = { [weak probe] in
        guard let probe, probe.window != nil else { return }
        NativeAgentPetWindowCoordinator.shared.attachOrUpdate(anchor: probe, presentation: snapshot)
        {
          captured
        }
      }
    }
    if uiView.window != nil {
      NativeAgentPetWindowCoordinator.shared.attachOrUpdate(anchor: uiView, presentation: snapshot)
      {
        captured
      }
    }
  }

  /// 在 SwiftUI 销毁锚点时通知协调器解除挂载。
  static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
    NativeAgentPetWindowCoordinator.shared.detach(matching: uiView)
  }
}

/// 在宿主视图接入窗口后通知协调器完成挂载。
private final class NativeAgentPetWindowMountProbeView: UIView {
  var onWindowChanged: (() -> Void)?

  /// 在探针接入窗口后触发浮层挂载检查。
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      onWindowChanged?()
    } else {
      NativeAgentPetWindowCoordinator.shared.syncSafeAreaAndModalState()
    }
  }
}

/// iOS 全界面 Agent 助手形象统一宿主入口（通过独立穿透 `UIWindow` 挂载在全 APP 最上层，免疫任意弹窗层级遮挡与子页面布局跳动）：
/// - 未选中插件形象（或加载失败）时：展示零 WebView 内存占用的原生 `NativeAgentFloatingMascot`；
/// - 选中 `renderer` 插件形象（如放映猫）时：原生可拖拽悬浮盒 + 透明 `plugin-shell` 远程组件；
/// - 选中 `stage` 插件形象（如小映 / 奶龙 / 助手 / 天照）时：全屏透明舞台 + 窗口级像素穿透 + 恒定底栏安全边界 + 原生台词气泡！
@MainActor
struct NativeAgentPetOverlayHost: View {
  let session: NativeSession
  @ObservedObject var petStore: NativeAgentPetStore
  let isVisible: Bool
  let panelOpen: Bool
  let dockVisible: Bool
  let thinking: Bool
  let onOpenAgent: (_ draft: String?) -> Void
  let onCloseAgent: () -> Void
  let onOpenPetPicker: () -> Void
  let onHideFloating: () -> Void

  @Environment(\.nativeVerticalBarEdge) private var verticalBarEdge

  var body: some View {
    NativeAgentPetWindowAnchor(
      presentation: NativeAgentPetPresentationState(
        isVisible: isVisible, panelOpen: panelOpen, dockVisible: dockVisible,
        thinking: thinking, verticalBarEdge: verticalBarEdge)
    ) {
      NativeAgentPetWindowRootView(
        session: session,
        petStore: petStore,
        onOpenAgent: onOpenAgent,
        onCloseAgent: onCloseAgent,
        onOpenPetPicker: onOpenPetPicker,
        onHideFloating: onHideFloating
      )
    }
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
    .onAppear {
      petStore.bootstrapIfNeeded()
    }
  }
}

@MainActor
/// 在独立透明窗口中渲染插件助手内容。
private struct NativeAgentPetWindowRootView: View {
  let session: NativeSession
  @ObservedObject var petStore: NativeAgentPetStore
  let onOpenAgent: (_ draft: String?) -> Void
  let onCloseAgent: () -> Void
  let onOpenPetPicker: () -> Void
  let onHideFloating: () -> Void

  @ObservedObject private var windowState = NativeAgentPetWindowCoordinator.shared.windowState
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var mascotHitRect: CGRect = .zero
  @State private var isDraggingMascot: Bool = false

  private var isVisible: Bool { windowState.presentation.isVisible }
  private var panelOpen: Bool { windowState.presentation.panelOpen }
  private var dockVisible: Bool { windowState.presentation.dockVisible }
  private var thinking: Bool { windowState.presentation.thinking }
  private var verticalBarEdge: NativeDeviceLayout.VerticalBarEdge {
    windowState.presentation.verticalBarEdge
  }

  private var effectiveVisible: Bool {
    isVisible && !panelOpen && !windowState.isModalOccluded
  }

  var body: some View {
    Group {
      if let pet = petStore.effectivePet {
        NativePluginAgentPetRuntimeOverlay(
          session: session,
          pet: pet,
          petStore: petStore,
          isVisible: effectiveVisible,
          panelOpen: panelOpen || windowState.isModalOccluded,
          dockVisible: dockVisible,
          thinking: thinking,
          motionActive: effectiveVisible && windowState.isSceneActive && !reduceMotion,
          hardwareSafeArea: windowState.hardwareSafeArea,
          onOpenAgent: onOpenAgent,
          onCloseAgent: onCloseAgent,
          onOpenPetPicker: onOpenPetPicker,
          onHideFloating: onHideFloating
        )
        .environment(\.nativeVerticalBarEdge, verticalBarEdge)
        .id(pet.id)
      } else {
        NativeAgentFloatingMascot(
          onOpen: { onOpenAgent(nil) },
          onHide: onHideFloating,
          onSelectPet: onOpenPetPicker,
          onContextMenuVisibilityChange: NativeAgentPetWindowCoordinator.shared
            .setContextMenuVisible,
          thinking: thinking,
          motionActive: effectiveVisible && windowState.isSceneActive,
          dockVisible: dockVisible,
          onInteractiveFrameChange: { rect, dragging in
            mascotHitRect = rect
            isDraggingMascot = dragging
            NativeAgentPetWindowCoordinator.shared.updateHitRegion(
              isCaptureEnabled: effectiveVisible,
              interactiveRect: rect,
              forceFullCapture: dragging
            )
          }
        )
        .environment(\.nativeVerticalBarEdge, verticalBarEdge)
        .opacity(effectiveVisible ? 1 : 0)
        .allowsHitTesting(effectiveVisible)
        .onAppear {
          NativeAgentPetWindowCoordinator.shared.updateHitRegion(
            isCaptureEnabled: effectiveVisible,
            interactiveRect: mascotHitRect,
            forceFullCapture: isDraggingMascot
          )
        }
        .onChange(of: effectiveVisible) { vis in
          NativeAgentPetWindowCoordinator.shared.updateHitRegion(
            isCaptureEnabled: vis,
            interactiveRect: mascotHitRect,
            forceFullCapture: isDraggingMascot
          )
        }
      }
    }
    .preferredColorScheme(
      appearance.mode == .dark ? .dark : (appearance.mode == .light ? .light : nil)
    )
  }
}

@MainActor
/// 组织插件舞台、渲染层、气泡与拖动状态。
private struct NativePluginAgentPetRuntimeOverlay: View {
  let session: NativeSession
  let pet: NativeAgentPetDeclaration
  @ObservedObject var petStore: NativeAgentPetStore
  let isVisible: Bool
  let panelOpen: Bool
  let dockVisible: Bool
  let thinking: Bool
  let motionActive: Bool
  let hardwareSafeArea: EdgeInsets
  let onOpenAgent: (_ draft: String?) -> Void
  let onCloseAgent: () -> Void
  let onOpenPetPicker: () -> Void
  let onHideFloating: () -> Void

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.nativeVerticalBarEdge) private var verticalBarEdge
  @Environment(\.verticalSizeClass) private var verticalSizeClass

  @StateObject private var controller = NativeAgentPetWebController()

  // renderer 模式悬浮拖拽位置
  @AppStorage("nativeV2.mascot.x") private var normalizedX: Double = 0.94
  @AppStorage("nativeV2.mascot.y") private var normalizedY: Double = 0.74
  @State private var dragTranslation: CGSize = .zero
  @State private var isDraggingRenderer = false
  @State private var rendererAction: String? = nil
  @State private var fallbackMascotRect: CGRect = .zero
  @State private var isDraggingFallbackMascot = false

  private var preferDark: Bool {
    switch appearance.mode {
    case .dark: return true
    case .light: return false
    case .system: return colorScheme == .dark
    }
  }

  /// 构造提供给插件舞台的贴边与安全区布局数据。
  private func buildDockPayload(size: CGSize, safeArea: EdgeInsets) -> Any {
    guard dockVisible, !NativeDeviceLayout.isIPad, !verticalBarEdge.isActive else {
      return NSNull()
    }
    let dockHeight: CGFloat = 58
    let bottomPad = max(safeArea.bottom, 12)
    let dockY = max(0, size.height - bottomPad - dockHeight)
    let dockWidth = min(max(size.width - 32, 220), 420)
    let dockX = (size.width - dockWidth) * 0.5
    let bounds: [String: Double] = [
      "x": Double(dockX),
      "y": Double(dockY),
      "width": Double(dockWidth),
      "height": Double(dockHeight),
    ]
    return ["bounds": bounds, "items": [bounds]]
  }

  /// 构造当前助手状态并合并页面可见性信息。
  private func buildStatePatch(size: CGSize, safeArea: EdgeInsets) -> [String: Any] {
    var patch: [String: Any] = [
      "available": true,
      "panelOpen": panelOpen,
      "thinking": thinking,
      "phase": thinking ? "thinking" : "idle",
      "pageVisible": isVisible && !panelOpen,
      "motionAllowed": motionActive,
      "reducedMotion": !motionActive,
      "theme": preferDark ? "dark" : "light",
      "isMobile": size.width < 960,
      "dock": buildDockPayload(size: size, safeArea: safeArea),
      "viewport": [
        "width": Double(size.width),
        "height": Double(size.height),
        "keyboardInset": 0,
        "safeArea": [
          "top": Double(safeArea.top),
          "right": Double(safeArea.trailing),
          "bottom": Double(safeArea.bottom),
          "left": Double(safeArea.leading),
        ],
      ],
    ]
    if !pet.isStageMode {
      patch["action"] = rendererAction ?? NSNull()
      patch["intent"] = thinking ? "thinking" : "idle"
      patch["motionActive"] = motionActive
    }
    return patch
  }

  /// 计算插件渲染器在屏幕坐标中的交互区域。
  private func currentRendererHitRect(size: CGSize, safeArea: EdgeInsets) -> CGRect {
    let boxW: CGFloat = 86
    let boxH: CGFloat = 96
    let leadingClearance: CGFloat = verticalBarEdge == .leading ? 76 : 6
    let trailingClearance: CGFloat = verticalBarEdge == .trailing ? 76 : 6
    let topClearance: CGFloat = max(safeArea.top + 10, 52)
    let bottomClearance: CGFloat =
      dockVisible ? max(safeArea.bottom + 72, 96) : max(safeArea.bottom + 18, 28)
    let safeLeft = leadingClearance + boxW / 2
    let safeRight = max(size.width - trailingClearance - boxW / 2, safeLeft + 1)
    let safeTop = topClearance + boxH / 2
    let safeBottom = max(size.height - bottomClearance - boxH / 2, safeTop + 1)
    let usableW = max(safeRight - safeLeft, 1)
    let usableH = max(safeBottom - safeTop, 1)
    let baseX = safeLeft + usableW * min(max(CGFloat(normalizedX), 0), 1)
    let baseY = safeTop + usableH * min(max(CGFloat(normalizedY), 0), 1)
    let cx = min(max(baseX + dragTranslation.width, safeLeft), safeRight)
    let cy = min(max(baseY + dragTranslation.height, safeTop), safeBottom)
    return CGRect(x: cx - boxW * 0.5, y: cy - boxH * 0.5, width: boxW, height: boxH)
  }

  /// 依据插件渲染器区域刷新窗口触摸命中范围。
  private func syncWindowHitRegion(size: CGSize, safeArea: EdgeInsets) {
    let activeNow = isVisible && !panelOpen
    if !controller.isMounted {
      NativeAgentPetWindowCoordinator.shared.updateHitRegion(
        isCaptureEnabled: activeNow,
        interactiveRect: fallbackMascotRect,
        forceFullCapture: isDraggingFallbackMascot
      )
      return
    }
    if pet.isStageMode {
      NativeAgentPetWindowCoordinator.shared.updateHitRegion(
        isCaptureEnabled: activeNow,
        interactiveRect: controller.anchorRect,
        forceFullCapture: controller.isInteracting
      )
    } else {
      NativeAgentPetWindowCoordinator.shared.updateHitRegion(
        isCaptureEnabled: activeNow,
        interactiveRect: currentRendererHitRect(size: size, safeArea: safeArea),
        forceFullCapture: isDraggingRenderer
      )
    }
  }

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let safeArea = hardwareSafeArea
      ZStack(alignment: .topLeading) {
        if pet.isStageMode {
          stageLayer(size: size, safeArea: safeArea)
        } else {
          rendererLayer(size: size, safeArea: safeArea)
        }

        // 挂载完成前或失败过渡期间不闪烁空白，无感用原生机器人托底
        if !controller.isMounted && isVisible && !panelOpen {
          NativeAgentFloatingMascot(
            onOpen: { onOpenAgent(nil) },
            onHide: onHideFloating,
            onSelectPet: onOpenPetPicker,
            onContextMenuVisibilityChange: NativeAgentPetWindowCoordinator.shared
              .setContextMenuVisible,
            thinking: thinking,
            motionActive: motionActive,
            dockVisible: dockVisible,
            onInteractiveFrameChange: { rect, dragging in
              fallbackMascotRect = rect
              isDraggingFallbackMascot = dragging
              syncWindowHitRegion(size: size, safeArea: safeArea)
            }
          )
          .opacity(0.95)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .task(id: pet.id) {
        controller.onOpenAgent = onOpenAgent
        controller.onCloseAgent = onCloseAgent
        controller.onFailed = { reason in
          petStore.markFailed(pet, reason: reason)
        }
        let tokens = PluginVisualTokensSnapshot.make(from: appearance, colorScheme: colorScheme)
        await controller.mount(
          pet: pet,
          session: session,
          visualTokens: tokens,
          initialAgentState: buildStatePatch(size: size, safeArea: safeArea),
          safeArea: safeArea
        )
        syncWindowHitRegion(size: size, safeArea: safeArea)
      }
      .onAppear {
        controller.pushAgentState(buildStatePatch(size: size, safeArea: safeArea))
        syncWindowHitRegion(size: size, safeArea: safeArea)
      }
      .onChange(of: panelOpen) { open in
        controller.pushAgentState(buildStatePatch(size: size, safeArea: safeArea))
        controller.notifyPanelChanged(panelOpen: open)
        if !open {
          controller.webView.setNeedsLayout()
        }
      }
      .onChange(of: controller.isMounted) { _ in
        syncWindowHitRegion(size: size, safeArea: safeArea)
      }
      .onChange(of: controller.anchorRect) { _ in
        syncWindowHitRegion(size: size, safeArea: safeArea)
      }
      .onChange(of: controller.isInteracting) { _ in
        syncWindowHitRegion(size: size, safeArea: safeArea)
      }
      .onChange(
        of:
          "\(Int(normalizedX * 1000))|\(Int(normalizedY * 1000))|\(Int(dragTranslation.width))|\(Int(dragTranslation.height))|\(isDraggingRenderer)"
      ) { _ in
        if !pet.isStageMode {
          syncWindowHitRegion(size: size, safeArea: safeArea)
        }
      }
      .onChange(of: rendererAction) { _ in
        if !pet.isStageMode {
          controller.pushAgentState(buildStatePatch(size: size, safeArea: safeArea))
        }
      }
      .task(id: "\(pet.id)|\(motionActive)|\(pet.isStageMode)") {
        // renderer 模式随机动作调度（支持插件声明的 random_actions 池）
        guard !pet.isStageMode, motionActive else { return }
        let pool = pet.randomActions ?? NativeAgentPetAction.randomIdlePool.map(\.rawValue)
        guard !pool.isEmpty else { return }
        var last: String? = nil
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(Double.random(in: 12.0...22.0)))
          guard !Task.isCancelled, !isDraggingRenderer, !thinking else { continue }
          let candidates = pool.filter { $0 != last }
          let next = candidates.randomElement() ?? pool.first
          last = next
          rendererAction = next
          let dur = NativeAgentPetAction(rawValue: next ?? "")?.durationSeconds ?? 3.2
          try? await Task.sleep(for: .seconds(dur))
          if !Task.isCancelled && rendererAction == next {
            rendererAction = nil
          }
        }
      }
    }
    .ignoresSafeArea()
  }

  /// 在 UIKit 实际应用当前视图输入时同步桥接，避免模态转场遗漏 SwiftUI 变化回调。
  private func synchronizeRuntime(size: CGSize, safeArea: EdgeInsets) {
    controller.pushAgentState(buildStatePatch(size: size, safeArea: safeArea))
    controller.pushVisualTokens(
      PluginVisualTokensSnapshot.make(from: appearance, colorScheme: colorScheme))
    syncWindowHitRegion(size: size, safeArea: safeArea)
  }

  @ViewBuilder
  /// 构建覆盖页面的插件舞台 Web 层。
  private func stageLayer(size: CGSize, safeArea: EdgeInsets) -> some View {
    let stageActive = isVisible && !panelOpen && controller.isMounted
    ZStack(alignment: .topLeading) {
      NativeAgentPetWebViewRepresentable(
        webView: controller.webView,
        preferDark: preferDark,
        isCaptureEnabled: stageActive,
        passthroughEnabled: true,
        interactiveRect: stageActive ? controller.anchorRect : nil,
        forceCaptureAll: stageActive && controller.isInteracting,
        onRuntimeUpdate: { synchronizeRuntime(size: size, safeArea: safeArea) },
        accessibilityName: pet.name,
        onAccessibilityOpen: { onOpenAgent(nil) }
      )
      .frame(width: size.width, height: size.height)
      .opacity(controller.isMounted ? 1 : 0)

      if stageActive, let bubble = controller.speechBubbleText, let anchor = controller.anchorRect {
        speechBubbleView(text: bubble)
          .position(
            x: min(max(anchor.midX, 110), max(110, size.width - 110)),
            y: max(safeArea.top + 36, anchor.minY - 26)
          )
          .allowsHitTesting(false)
          .transition(.scale(scale: 0.88).combined(with: .opacity))
      }
    }
  }

  @ViewBuilder
  /// 构建只在助手渲染区域接收输入的插件层。
  private func rendererLayer(size: CGSize, safeArea: EdgeInsets) -> some View {
    let rendererInteractive = isVisible && !panelOpen && controller.isMounted
    let boxW: CGFloat = 86
    let boxH: CGFloat = 96
    let leadingClearance: CGFloat = verticalBarEdge == .leading ? 76 : 6
    let trailingClearance: CGFloat = verticalBarEdge == .trailing ? 76 : 6
    let topClearance: CGFloat = max(safeArea.top + 10, 52)
    let bottomClearance: CGFloat =
      dockVisible ? max(safeArea.bottom + 72, 96) : max(safeArea.bottom + 18, 28)
    let safeLeft = leadingClearance + boxW / 2
    let safeRight = max(size.width - trailingClearance - boxW / 2, safeLeft + 1)
    let safeTop = topClearance + boxH / 2
    let safeBottom = max(size.height - bottomClearance - boxH / 2, safeTop + 1)
    let usableW = max(safeRight - safeLeft, 1)
    let usableH = max(safeBottom - safeTop, 1)
    let baseX = safeLeft + usableW * min(max(CGFloat(normalizedX), 0), 1)
    let baseY = safeTop + usableH * min(max(CGFloat(normalizedY), 0), 1)
    let currentX = min(max(baseX + dragTranslation.width, safeLeft), safeRight)
    let currentY = min(max(baseY + dragTranslation.height, safeTop), safeBottom)

    ZStack(alignment: .topLeading) {
      ZStack {
        NativeAgentPetWebViewRepresentable(
          webView: controller.webView,
          preferDark: preferDark,
          isCaptureEnabled: false,
          passthroughEnabled: false,
          interactiveRect: nil,
          forceCaptureAll: false,
          onRuntimeUpdate: { synchronizeRuntime(size: size, safeArea: safeArea) }
        )
        .allowsHitTesting(false)
        Color.white.opacity(0.001)
      }
      .frame(width: boxW, height: boxH)
      .opacity(
        controller.isMounted && isVisible && !panelOpen ? 1 : (controller.isMounted ? 0.015 : 0)
      )
      .allowsHitTesting(rendererInteractive)
      .scaleEffect(isDraggingRenderer ? 1.06 : 1.0)
      .contentShape(Rectangle().inset(by: -8))
      .onTapGesture {
        onOpenAgent(nil)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(pet.name)
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier("native-agent-plugin-pet-renderer")
      .contextMenu {
        Button {
          onOpenAgent(nil)
        } label: {
          Label("打开智能助手", systemImage: "text.bubble")
        }
        .onAppear { NativeAgentPetWindowCoordinator.shared.setContextMenuVisible(true) }
        .onDisappear { NativeAgentPetWindowCoordinator.shared.setContextMenuVisible(false) }
        Button {
          onOpenPetPicker()
        } label: {
          Label("更换助手形象", systemImage: "sparkles")
        }
        Button {
          withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            normalizedX = 0.94
            normalizedY = 0.74
          }
        } label: {
          Label("重置默认位置", systemImage: "arrow.uturn.backward")
        }
        Button(role: .destructive) {
          onHideFloating()
        } label: {
          Label("隐藏浮动助手", systemImage: "eye.slash")
        }
      }
      .gesture(
        DragGesture(minimumDistance: 4, coordinateSpace: .named("agent-pet-renderer-space"))
          .onChanged { value in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
              isDraggingRenderer = true
              dragTranslation = value.translation
            }
          }
          .onEnded { value in
            let endX = min(max(baseX + value.translation.width, safeLeft), safeRight)
            let endY = min(max(baseY + value.translation.height, safeTop), safeBottom)
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
              normalizedX = Double((endX - safeLeft) / usableW)
              normalizedY = Double((endY - safeTop) / usableH)
              dragTranslation = .zero
              isDraggingRenderer = false
            }
            rendererAction = "nod"
          }
      )
      .position(x: currentX, y: currentY)
      .transaction { transaction in
        if isDraggingRenderer { transaction.animation = nil }
      }

      if rendererInteractive, let bubble = controller.speechBubbleText {
        speechBubbleView(text: bubble)
          .position(
            x: min(max(currentX, 110), max(110, size.width - 110)),
            y: max(safeArea.top + 36, currentY - boxH * 0.5 - 24)
          )
          .allowsHitTesting(false)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .coordinateSpace(name: "agent-pet-renderer-space")
  }

  /// 绘制与当前插件助手消息关联的原生气泡。
  private func speechBubbleView(text: String) -> some View {
    Text(text)
      .font(.caption.weight(.medium))
      .foregroundStyle(.primary)
      .lineLimit(2)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .frame(maxWidth: 220)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
      )
      .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
  }
}
