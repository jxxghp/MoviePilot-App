import Foundation
import MoviePilotCore
import MoviePilotSession
import UIKit
@preconcurrency import WebKit

/// 单个可热复用的本地联邦运行时 WebView 实例槽。
@MainActor
final class PooledPluginWebView: NSObject {
  enum State: Equatable {
    case cold
    case warming
    case warmIdle
    case active
    case disposed
  }

  let webView: WKWebView
  let schemeHandler: PluginShellSchemeHandler
  let bridge: PluginHostBridgeV2
  var state: State = .cold
  var reuseCount: Int = 0
  var isShellReady: Bool = false
  var onShellReadyCallbacks: [() -> Void] = []
  var onProcessTerminated: (() -> Void)?

  init(
    webView: WKWebView,
    schemeHandler: PluginShellSchemeHandler,
    bridge: PluginHostBridgeV2
  ) {
    self.webView = webView
    self.schemeHandler = schemeHandler
    self.bridge = bridge
    super.init()
  }

  func markShellReady() {
    guard !isShellReady else { return }
    isShellReady = true
    if state == .warming {
      state = .warmIdle
    }
    let pending = onShellReadyCallbacks
    onShellReadyCallbacks.removeAll()
    for cb in pending {
      cb()
    }
  }

  func whenShellReady(_ callback: @escaping () -> Void) {
    if isShellReady {
      callback()
    } else {
      onShellReadyCallbacks.append(callback)
    }
  }
}

/// Vue 联邦插件本地预热运行时 `WKWebView` 池（Route A）：
/// - 状态机：`COLD -> WARMING -> WARM_IDLE -> ACTIVE -> DISPOSED`；
/// - 登录后空闲 1.5s 自动后台预热 1 个透明壳实例（`mp-plugin://shell/shell/plugin-shell.html`）；
/// - 每次打开不同 Vue 插件热复用已有壳实例，单实例复用上限 15 次；
/// - 响应内存告警、WebContent 进程崩溃、退出登录/切换实例自动销毁并清理态。
@MainActor
final class PluginWebViewPool: NSObject, WKNavigationDelegate, WKUIDelegate {
  static let shared = PluginWebViewPool()

  private let maxReusesPerSlot = 15
  private var idleSlot: PooledPluginWebView?
  private weak var activeSlot: PooledPluginWebView?
  private var prewarmTask: Task<Void, Never>?
  private var memoryWarningObserver: NSObjectProtocol?

  private override init() {
    super.init()
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleMemoryWarning()
      }
    }
  }

  /// 登录后空闲 1.5 秒预热 1 个 `WKWebView` 壳，做到点开插件零冷启动延迟。
  func scheduleIdlePrewarm(delaySeconds: Double = 1.5) {
    guard idleSlot == nil else { return }
    prewarmTask?.cancel()
    prewarmTask = Task { [weak self] in
      if delaySeconds > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
      }
      guard !Task.isCancelled, let self else { return }
      if self.idleSlot == nil {
        let slot = self.createWarmingSlot()
        self.idleSlot = slot
      }
    }
  }

  /// 借出 1 个本地运行时 `WKWebView` 槽，优先复用已预热的空闲槽。
  func acquire(context: PluginShellSchemeHandler.SessionContext) -> PooledPluginWebView {
    let slot: PooledPluginWebView
    if let warm = idleSlot, warm.state == .warmIdle || warm.state == .warming {
      idleSlot = nil
      slot = warm
    } else {
      slot = createWarmingSlot()
    }
    slot.state = .active
    slot.reuseCount += 1
    slot.schemeHandler.updateSessionContext(context)
    slot.bridge.updateSessionContext(context)
    activeSlot = slot
    return slot
  }

  /// 归还 `WKWebView` 槽：先发送 `plugin.unmount` 并中断所有在途请求与会话上下文，符合配额则回池复用。
  func release(_ slot: PooledPluginWebView, forceDispose: Bool = false) {
    slot.bridge.sendUnmount()
    slot.bridge.abortAllInFlightRequests()
    slot.bridge.cleanupNativeCapabilities()
    slot.bridge.clearCallbacks()
    slot.bridge.updateSessionContext(nil)
    slot.schemeHandler.cancelAllRequests()
    slot.schemeHandler.updateSessionContext(nil)
    slot.onProcessTerminated = nil
    slot.onShellReadyCallbacks.removeAll()
    if activeSlot === slot {
      activeSlot = nil
    }

    let canRecycle =
      !forceDispose
      && slot.state != .disposed
      && slot.isShellReady
      && slot.reuseCount < maxReusesPerSlot
      && idleSlot == nil

    if canRecycle {
      slot.state = .warmIdle
      slot.webView.removeFromSuperview()
      slot.bridge.onShellReady = { [weak slot] in
        slot?.markShellReady()
      }
      idleSlot = slot
    } else {
      disposeSlot(slot)
      scheduleIdlePrewarm(delaySeconds: 1.5)
    }
  }

  /// 退出登录、令牌失效或切换服务实例时彻底销毁池中槽并清空当前上下文。
  func resetForSessionChange() {
    PluginCapsuleManager.shared.closeAndRelease()
    prewarmTask?.cancel()
    prewarmTask = nil
    if let idle = idleSlot {
      idleSlot = nil
      disposeSlot(idle)
    }
    if let active = activeSlot {
      active.bridge.abortAllInFlightRequests()
      active.bridge.cleanupNativeCapabilities()
      active.bridge.updateSessionContext(nil)
      active.schemeHandler.cancelAllRequests()
      active.schemeHandler.updateSessionContext(nil)
      active.state = .disposed
    }
  }

  private func handleMemoryWarning() {
    if let idle = idleSlot {
      idleSlot = nil
      disposeSlot(idle)
    }
  }

  private func createWarmingSlot() -> PooledPluginWebView {
    let schemeHandler = PluginShellSchemeHandler()
    let bridge = PluginHostBridgeV2()

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []
    if UIDevice.current.userInterfaceIdiom == .phone {
      config.defaultWebpagePreferences.preferredContentMode = .mobile
    }
    config.setURLSchemeHandler(schemeHandler, forURLScheme: PluginShellSchemeHandler.scheme)
    config.userContentController.add(
      WeakPluginHostBridgeV2Handler(bridge),
      name: PluginHostBridgeV2.handlerName
    )

    let initialBounds = UIScreen.main.bounds
    let initialFrame =
      initialBounds.width > 0 && initialBounds.height > 0
      ? initialBounds
      : CGRect(x: 0, y: 0, width: 390, height: 844)
    let webView = WKWebView(frame: initialFrame, configuration: config)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    // Layer 1：彻底透明背景，包括回弹露底（underPageBackgroundColor）与滚动容器，透出底层原生流光背景。
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.underPageBackgroundColor = .clear
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.scrollView.keyboardDismissMode = .interactive

    bridge.webView = webView
    let slot = PooledPluginWebView(webView: webView, schemeHandler: schemeHandler, bridge: bridge)
    slot.state = .warming
    bridge.onShellReady = { [weak slot] in
      slot?.markShellReady()
    }

    webView.load(URLRequest(url: PluginShellSchemeHandler.entryURL))
    return slot
  }

  private func disposeSlot(_ slot: PooledPluginWebView) {
    slot.state = .disposed
    slot.bridge.abortAllInFlightRequests()
    slot.bridge.cleanupNativeCapabilities()
    slot.bridge.clearCallbacks()
    slot.bridge.updateSessionContext(nil)
    slot.schemeHandler.cancelAllRequests()
    slot.schemeHandler.updateSessionContext(nil)
    slot.webView.stopLoading()
    slot.webView.configuration.userContentController.removeScriptMessageHandler(
      forName: PluginHostBridgeV2.handlerName)
    slot.webView.navigationDelegate = nil
    slot.webView.uiDelegate = nil
    slot.webView.removeFromSuperview()
  }

  // MARK: - WKUIDelegate（仅对可信虚拟源 mp-plugin:// 放行网页标准麦克风/相机捕获权限）

  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    if origin.protocol.lowercased() == PluginShellSchemeHandler.scheme {
      decisionHandler(.grant)
    } else {
      decisionHandler(.deny)
    }
  }

  // MARK: - WKNavigationDelegate

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    // 主框架仅允许加载本机虚拟源壳页，任何外链或跨源导航全部交由系统浏览器打开。
    if url.scheme?.lowercased() == PluginShellSchemeHandler.scheme {
      decisionHandler(.allow)
      return
    }
    if navigationAction.navigationType == .linkActivated,
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    {
      UIApplication.shared.open(url)
    }
    decisionHandler(.cancel)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    if let idle = idleSlot, idle.webView === webView {
      idleSlot = nil
      disposeSlot(idle)
      return
    }
    if let active = activeSlot, active.webView === webView {
      active.state = .disposed
      active.onProcessTerminated?()
    }
  }
}

/// 最小化悬浮胶囊上的单个插件快捷按钮定义。
struct PluginCapsuleActionItem: Identifiable, Equatable {
  let id: String
  let label: String
  let icon: String?
  let active: Bool
  let destructive: Bool
}

/// 联邦插件最小化胶囊实时展示模型。
struct PluginCapsuleSnapshot: Equatable {
  var pluginID: String
  var pluginName: String
  var title: String
  var subtitle: String
  var statusText: String
  var iconURL: String?
  var mode: String  // "jump" | "mini"
  var isPlaying: Bool
  var actions: [PluginCapsuleActionItem]

  var isMiniWindowMode: Bool {
    mode.lowercased() == "mini" || !actions.isEmpty
  }

  static func from(
    pluginID: String,
    fallbackName: String,
    payload: [String: Any]
  ) -> PluginCapsuleSnapshot {
    let resolvedName =
      (payload["pluginName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNil ?? (fallbackName.isEmpty ? pluginID : fallbackName)
    let resolvedTitle =
      (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNil ?? resolvedName
    let actions = parseActions(payload["actions"])
    let rawMode = (payload["mode"] as? String)?.lowercased()
    let mode: String
    if rawMode == "mini" || rawMode == "jump", let rawMode {
      mode = rawMode
    } else {
      mode = actions.isEmpty ? "jump" : "mini"
    }
    return PluginCapsuleSnapshot(
      pluginID: pluginID,
      pluginName: resolvedName,
      title: resolvedTitle,
      subtitle: (payload["subtitle"] as? String) ?? "",
      statusText: (payload["statusText"] as? String) ?? "",
      iconURL: (payload["iconUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNil,
      mode: mode,
      isPlaying: (payload["isPlaying"] as? Bool) ?? false,
      actions: actions
    )
  }

  mutating func mergePatch(_ payload: [String: Any]) {
    if let nextTitle = (payload["title"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).nonEmptyOrNil {
      title = nextTitle
    }
    if let nextSub = payload["subtitle"] as? String {
      subtitle = nextSub
    }
    if let nextStatus = payload["statusText"] as? String {
      statusText = nextStatus
    }
    if let nextIcon = (payload["iconUrl"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).nonEmptyOrNil {
      iconURL = nextIcon
    }
    if let nextMode = (payload["mode"] as? String)?.lowercased(),
      nextMode == "jump" || nextMode == "mini"
    {
      mode = nextMode
    }
    if let playing = payload["isPlaying"] as? Bool {
      isPlaying = playing
    }
    if payload["actions"] != nil {
      actions = Self.parseActions(payload["actions"])
    }
  }

  private static func parseActions(_ raw: Any?) -> [PluginCapsuleActionItem] {
    guard let list = raw as? [[String: Any]] else { return [] }
    return list.compactMap { item in
      guard
        let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
          .nonEmptyOrNil
      else { return nil }
      let label =
        (item["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        ?? (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        ?? id
      let icon = (item["icon"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        .nonEmptyOrNil
      let active = (item["active"] as? Bool) ?? false
      let destructive = (item["destructive"] as? Bool) ?? false
      return PluginCapsuleActionItem(
        id: id, label: label, icon: icon, active: active, destructive: destructive)
    }
  }
}

private extension String {
  var nonEmptyOrNil: String? {
    isEmpty ? nil : self
  }
}

/// 保活中的最小化联邦插件会话（持有未卸载的实时 `PooledPluginWebView`）。
@MainActor
final class MinimizedPluginSession: Identifiable {
  let id: String
  let pluginID: String
  let pluginName: String
  let surface: NativeVuePluginWebContainer.Surface
  let pluginHasPage: Bool
  let serverURL: URL
  let slot: PooledPluginWebView
  var snapshot: PluginCapsuleSnapshot

  init(
    pluginID: String,
    pluginName: String,
    surface: NativeVuePluginWebContainer.Surface,
    pluginHasPage: Bool,
    serverURL: URL,
    slot: PooledPluginWebView,
    snapshot: PluginCapsuleSnapshot
  ) {
    self.id = "\(pluginID):\(UUID().uuidString)"
    self.pluginID = pluginID
    self.pluginName = pluginName
    self.surface = surface
    self.pluginHasPage = pluginHasPage
    self.serverURL = serverURL
    self.slot = slot
    self.snapshot = snapshot
  }
}

/// iOS 联邦插件最小化悬浮胶囊保活管理器：
/// 最小化时不销毁 `WKWebView` 与 Vue 实例，支持全应用跨标签显示跳转胶囊或展开快捷操作小悬浮窗。
@MainActor
final class PluginCapsuleManager: ObservableObject {
  static let shared = PluginCapsuleManager()

  @Published private(set) var currentSession: MinimizedPluginSession?
  @Published var isMiniCardExpanded: Bool = false
  @Published var restoreRequestNonce: Int = 0

  private init() {}

  func isSlotParked(_ slot: PooledPluginWebView) -> Bool {
    currentSession?.slot === slot
  }

  func parkSession(_ session: MinimizedPluginSession) {
    if let existing = currentSession, existing.slot !== session.slot {
      PluginWebViewPool.shared.release(existing.slot)
    }
    session.slot.webView.removeFromSuperview()
    currentSession = session
    isMiniCardExpanded = false

    session.slot.bridge.onCapsuleUpdate = { [weak self, weak session] patch in
      guard let self, let session, self.currentSession === session else { return }
      session.snapshot.mergePatch(patch)
      self.objectWillChange.send()
    }
    session.slot.bridge.onPluginRestore = { [weak self, weak session] reqId in
      guard let self, let session, self.currentSession === session else { return }
      session.slot.bridge.sendSimpleResponse(requestId: reqId, data: ["restored": true])
      self.requestRestore()
    }
    session.slot.bridge.onPluginClose = { [weak self, weak session] in
      guard let self, let session, self.currentSession === session else { return }
      self.closeAndRelease()
    }
  }

  func updateActiveSnapshot(_ patch: [String: Any]) {
    guard let currentSession else { return }
    currentSession.snapshot.mergePatch(patch)
    objectWillChange.send()
  }

  func consumeMatchingSession(pluginID: String, serverURL: URL) -> MinimizedPluginSession? {
    guard let cur = currentSession,
      cur.pluginID.caseInsensitiveCompare(pluginID) == .orderedSame,
      cur.serverURL.absoluteString == serverURL.absoluteString
    else { return nil }
    currentSession = nil
    isMiniCardExpanded = false
    return cur
  }

  func dispatchAction(_ actionID: String) {
    currentSession?.slot.bridge.sendCapsuleAction(id: actionID)
  }

  func requestRestore() {
    guard currentSession != nil else { return }
    isMiniCardExpanded = false
    restoreRequestNonce += 1
  }

  func closeAndRelease() {
    guard let cur = currentSession else { return }
    currentSession = nil
    isMiniCardExpanded = false
    PluginWebViewPool.shared.release(cur.slot)
  }
}
