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
    guard !PluginRuntimePreferences.useLegacyWebContainer else { return }
    guard idleSlot == nil else { return }
    prewarmTask?.cancel()
    prewarmTask = Task { [weak self] in
      if delaySeconds > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
      }
      guard !Task.isCancelled, let self else { return }
      guard !PluginRuntimePreferences.useLegacyWebContainer else { return }
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
      && !PluginRuntimePreferences.useLegacyWebContainer

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
    config.setURLSchemeHandler(schemeHandler, forURLScheme: PluginShellSchemeHandler.scheme)
    config.userContentController.add(
      WeakPluginHostBridgeV2Handler(bridge),
      name: PluginHostBridgeV2.handlerName
    )

    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
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
