import MoviePilotCore
import SafariServices
import UIKit
import WebKit

/// 脚本 handler 只弱引用协调器，WebKit 持有 handler 时不会保活整个旧实例。
@MainActor
private final class ScriptRelay: NSObject, WKScriptMessageHandler {
  weak var owner: WebCoordinator?

  /// 来源校验与分派统一委托给当前实例协调器。
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    owner?.receive(message)
  }
}

/// 一个实例的一份 WebView、桥接会话和系统交接；不处理 MoviePilot 业务 API。
@MainActor
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
  let instance: SavedInstance
  let webView: WKWebView
  let content: WebContentController
  weak var shell: ShellController?
  private let relay: ScriptRelay
  private var session = ChromeSession()
  private var timeout: Timer?
  private var startupTimeout: Timer?
  private var documentID = UUID()
  private var contentReady = false
  private var startupPending = true
  private var lifecycle = "active"
  private var layoutRevision = 0
  private var lastLayout: JSONValue?
  private var layoutScheduled = false
  private var keyboardFrame: CGRect?
  private var keyboardObserver: NSObjectProtocol?
  private var disableNextTakeover = false
  private var pendingCommands: [String: Timer] = [:]
  private var downloads: [ObjectIdentifier: URL] = [:]
  private var downloadReferences: [ObjectIdentifier: WKDownload] = [:]
  private var authentication: AuthenticationResult?
  private let onAuthenticationRequired: (() -> Void)?

  /// 数据容器按实例 UUID 隔离；不将 Safari 或其他实例 Cookie 导入此会话。
  init(
    instance: SavedInstance, authentication: AuthenticationResult? = nil,
    onAuthenticationRequired: (() -> Void)? = nil
  ) {
    self.instance = instance
    self.authentication = authentication
    self.onAuthenticationRequired = onAuthenticationRequired
    relay = ScriptRelay()
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: instance.id)
    configuration.allowsInlineMediaPlayback = true
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.userContentController.add(relay, name: "moviepilotChrome")
    configuration.userContentController.add(relay, name: "moviepilotAuthentication")
    if let path = Bundle.main.url(forResource: "BridgeBootstrap", withExtension: "js"),
      let script = try? String(contentsOf: path, encoding: .utf8)
    {
      configuration.userContentController.addUserScript(
        WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    if let authentication,
      let data = try? JSONEncoder().encode(authentication.session.browserStorage),
      let raw = String(data: data, encoding: .utf8),
      let literalData = try? JSONEncoder().encode(raw),
      let literal = String(data: literalData, encoding: .utf8),
      let urlData = try? JSONEncoder().encode(instance.address.url.absoluteString),
      let urlLiteral = String(data: urlData, encoding: .utf8)
    {
      let marker = "moviepilot.native.authentication.\(UUID().uuidString)"
      let script = """
        (() => {
          if (window.top !== window || location.origin !== new URL(\(urlLiteral)).origin || sessionStorage.getItem('\(marker)')) return;
          const initial = JSON.parse(\(literal));
          localStorage.setItem('auth', JSON.stringify(initial.auth));
          localStorage.setItem('user', JSON.stringify(initial.user));
          sessionStorage.setItem('\(marker)', '1');
        })();
        """
      configuration.userContentController.addUserScript(
        WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    webView = WKWebView(frame: .zero, configuration: configuration)
    content = WebContentController(webView: webView)
    super.init()
    relay.owner = self
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.scrollView.keyboardDismissMode = .interactive
    if #available(iOS 16.4, *) { webView.isInspectable = _isDebugAssertConfiguration() }
    content.onLayout = { [weak self] in self?.layoutChanged() }
    keyboardObserver = NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
    ) { [weak self] notification in
      let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
      MainActor.assumeIsolated {
        self?.keyboardFrame = frame
        self?.layoutChanged()
      }
    }
  }

  /// 开始唯一顶层导航，页面内部 hash 路由不调用此方法。
  func start() {
    shell?.setLoading(true)
    armStartupTimeout()
    let cookies = authentication?.cookies ?? []
    authentication = nil
    Task { [weak self] in
      guard let self else { return }
      for cookie in cookies {
        await self.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
      }
      guard self.relay.owner != nil else { return }
      self.webView.load(
        URLRequest(
          url: self.instance.address.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
      )
    }
  }

  /// 切换实例时显式解绑脚本、计时器与通知，不让旧文档继续发送动作。
  func stop() {
    timeout?.invalidate()
    startupTimeout?.invalidate()
    startupPending = false
    documentID = UUID()
    for timer in pendingCommands.values { timer.invalidate() }
    pendingCommands.removeAll()
    if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
    keyboardObserver = nil
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "moviepilotChrome")
    webView.configuration.userContentController.removeScriptMessageHandler(
      forName: "moviepilotAuthentication")
    webView.configuration.userContentController.removeAllUserScripts()
    authentication = nil
    relay.owner = nil
    content.onLayout = nil
    for download in downloadReferences.values { download.cancel { _ in } }
    downloadReferences.removeAll()
    downloads.removeAll()
    session.beginDocument(allowTakeover: false)
  }

  /// 恢复失败文档时只重载网页导航，不重放动作或未完成业务请求。
  func reloadInWebMode() {
    disableNextTakeover = true
    session.beginDocument(allowTakeover: false)
    shell?.showWebNavigation()
    start()
  }

  /// 系统生命周期只同步给当前文档，后台暂停期间不进行超时恢复。
  func setLifecycle(_ value: String) {
    lifecycle = value
    timeout?.invalidate()
    startupTimeout?.invalidate()
    if value == "active", startupPending { armStartupTimeout() }
    for timer in pendingCommands.values { timer.invalidate() }
    pendingCommands.removeAll()
    if session.sessionId != nil {
      send("host.lifecycle", payload: .object(["state": .string(value)]))
      if value == "active" {
        if session.phase == .nativeNavigation {
          command("state.request", payload: .object(["reason": .string("foreground")]))
        } else if session.phase != .webNavigation {
          armTimeout()
        }
        layoutChanged()
      }
    }
  }

  /// 原生控件只能分派当前已确认动作，旧菜单对象也要在这里再次复核。
  func invoke(_ action: ActionSnapshot, menuActionId: String? = nil, frame: CGRect? = nil) {
    guard let id = session.sessionId else { return }
    let actionId = menuActionId ?? action.actionId
    do {
      try session.validateAction(
        sessionId: id, routeRevision: session.routeRevision, actionId: actionId,
        ownerId: action.ownerId)
      var payload: [String: JSONValue] = [
        "actionId": .string(actionId), "ownerId": .string(action.ownerId),
        "layoutRevision": .number(Double(layoutRevision)),
      ]
      if let frame {
        payload["framePoints"] = .object([
          "x": .number(frame.minX), "y": .number(frame.minY), "width": .number(frame.width),
          "height": .number(frame.height),
        ])
      }
      command("action.invoke", payload: .object(payload))
    } catch { command("state.request", payload: .object(["reason": .string("stale_action")])) }
  }

  /// 更多菜单的入口在当前快照中再次匹配，网页还会执行现有权限与 Router 守卫。
  func openMenuItem(_ item: MoreMenuItem) {
    guard session.phase == .nativeNavigation, session.snapshot?.chrome.content == .menu,
      session.snapshot?.moreMenu?.flatMap(\.items).contains(where: {
        $0.id == item.id && $0.path == item.path
      }) == true
    else { return }
    command(
      "navigation.open", payload: .object(["itemId": .string(item.id), "path": .string(item.path)]))
  }

  /// 命令只等待本地分派确认；超时释放导航，绝不自动重复点击。
  func command(_ type: String, payload: JSONValue) {
    guard session.phase == .nativeNavigation, pendingCommands.count < 16, lifecycle == "active"
    else { return }
    let request = UUID().uuidString
    let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.pendingCommands.removeValue(forKey: request)
        self.releaseChrome()
      }
    }
    pendingCommands[request] = timer
    send(type, requestId: request, payload: payload)
  }

  /// 释放事务先要求网页恢复布局，收到确认后才移除系统业务栏。
  func releaseChrome() {
    guard session.sessionId != nil else { return }
    for timer in pendingCommands.values { timer.invalidate() }
    pendingCommands.removeAll()
    session.requestRelease()
    send("chrome.release", payload: .object(["reason": .string("host_request")]))
    armTimeout()
  }

  /// 合并同一轮多次 UIKit 布局回调，只发送改变后的可见几何。
  func layoutChanged() {
    guard session.phase == .nativeNavigation, !layoutScheduled else { return }
    layoutScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.layoutScheduled = false
      guard self.session.phase == .nativeNavigation, let shell = self.shell else { return }
      let candidate = shell.layoutPayload(revision: 0, keyboard: self.keyboardFrame)
      guard candidate != self.lastLayout else { return }
      self.lastLayout = candidate
      self.layoutRevision += 1
      self.send(
        "host.layout",
        payload: shell.layoutPayload(revision: self.layoutRevision, keyboard: self.keyboardFrame))
    }
  }

  /// 严格使用 WK 提供的来源，消息正文无法声称自己是受信主文档。
  fileprivate func receive(_ message: WKScriptMessage) {
    let security = message.frameInfo.securityOrigin
    let source = BridgeSource(
      isMainFrame: message.frameInfo.isMainFrame, isCurrentWebView: message.webView === webView,
      origin: WebOrigin(scheme: security.protocol, host: security.host, port: security.port))
    if message.name == "moviepilotAuthentication" {
      guard source.isMainFrame, source.isCurrentWebView, source.origin == instance.address.origin,
        let body = message.body as? [String: Any], body.count == 2,
        body["version"] as? Int == 1, body["type"] as? String == "required",
        let onAuthenticationRequired
      else { return }
      onAuthenticationRequired()
      return
    }
    guard JSONSerialization.isValidJSONObject(message.body),
      let data = try? JSONSerialization.data(withJSONObject: message.body)
    else { return }
    do {
      let envelope = try BridgeValidator(origin: instance.address.origin).decode(
        data, source: source, sessionId: session.sessionId)
      do {
        try handle(envelope)
      } catch {
        // 当前主文档的快照失配时释放接管，不能让旧标题和控件留在已经切换的 HTML 上。
        if envelope.type == "navigation.state", session.sessionId != nil { releaseChrome() }
      }
    } catch {
      // 拒绝无效、过期或不受信消息，不回显正文、地址和认证信息。
    }
  }

  /// 消息采用封闭分派表，未知消息不会成为通用原生调用入口。
  private func handle(_ message: BridgeEnvelope) throws {
    switch message.type {
    case "web.ready":
      let ready = try message.decodePayload(ReadyPayload.self)
      let id = try session.negotiate(majors: ready.majors, capabilities: Set(ready.capabilities))
      lastLayout = nil
      send(
        "host.configure",
        payload: .object([
          "sessionId": .string(id), "major": .number(1),
          "instanceId": .string(instance.id.uuidString),
          "capabilities": .array(ChromeSession.requiredCapabilities.sorted().map(JSONValue.string)),
        ]))
      armTimeout()
    case "navigation.state":
      guard let route = message.routeRevision, let state = message.stateRevision else {
        throw BridgeError.invalidMessage
      }
      let snapshot = try message.decodePayload(NavigationSnapshot.self)
      try session.receive(snapshot, routeRevision: route, stateRevision: state)
      if session.phase == .negotiating {
        shell?.prepare(snapshot)
        shell?.view.layoutIfNeeded()
        layoutRevision += 1
        try session.prepare(layoutRevision: layoutRevision)
        send(
          "chrome.prepare",
          payload: shell?.layoutPayload(revision: layoutRevision, keyboard: keyboardFrame)
            ?? .object([:]))
        armTimeout()
      } else if session.phase == .nativeNavigation {
        timeout?.invalidate()
        shell?.apply(snapshot)
        layoutChanged()
      }
    case "chrome.accepted":
      let accepted = try message.decodePayload(LayoutAcknowledgement.self)
      try session.accept(layoutRevision: accepted.layoutRevision)
      timeout?.invalidate()
      if let snapshot = session.snapshot { shell?.apply(snapshot) }
      layoutChanged()
      completeStartupIfReady()
    case "chrome.released":
      guard session.phase == .releasing else { throw BridgeError.busy }
      timeout?.invalidate()
      session.released()
      for timer in pendingCommands.values { timer.invalidate() }
      pendingCommands.removeAll()
      shell?.showWebNavigation()
      completeStartupIfReady()
    case "command.result":
      let result = try message.decodePayload(CommandResult.self)
      pendingCommands.removeValue(forKey: result.requestId)?.invalidate()
    case "session.state":
      for timer in pendingCommands.values { timer.invalidate() }
      pendingCommands.removeAll()
      if session.phase == .nativeNavigation, let previousId = session.sessionId {
        let nextId = try session.rotateIdentity()
        send(
          "host.rekey", payload: .object(["sessionId": .string(nextId)]),
          sessionOverride: previousId)
        armTimeout()
      } else {
        releaseChrome()
      }
    case "chrome.failed":
      releaseChrome()
    case "presentation.state":
      break  // v1 返回由网页优先关闭其顶层弹层，原生不猜测 DOM 栈。
    default: throw BridgeError.invalidMessage
    }
  }

  /// 固定 JS 入口使用参数传递，不把用户路径或载荷拼接为可执行代码。
  private func send(
    _ type: String, requestId: String = UUID().uuidString, payload: JSONValue,
    sessionOverride: String? = nil
  ) {
    guard let id = sessionOverride ?? session.sessionId else { return }
    let envelope = BridgeEnvelope(
      type: type, requestId: requestId, sessionId: id,
      routeRevision: max(0, session.routeRevision), stateRevision: max(0, session.stateRevision),
      payload: payload)
    guard let data = try? JSONEncoder().encode(envelope),
      data.count <= BridgeValidator.maximumMessageBytes,
      let object = try? JSONSerialization.jsonObject(with: data)
    else { return }
    webView.callAsyncJavaScript(
      "window.dispatchEvent(new CustomEvent('moviepilot:native-message', {detail: message})); return true;",
      arguments: ["message": object], in: nil, in: .page
    ) { [weak self] result in
      if case .failure = result, let self, self.session.phase == .nativeNavigation {
        self.fail("页面通信已中断。请重新打开，未确认的操作不会自动重试。")
      }
    }
  }

  /// 本地协商按前台活动计时，释放无确认时转到原生恢复出口。
  private func armTimeout() {
    timeout?.invalidate()
    guard lifecycle == "active" else { return }
    timeout = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if self.session.phase == .releasing {
          self.fail("页面没有确认恢复导航。请重新打开网页模式。")
        } else {
          self.releaseChrome()
        }
      }
    }
  }

  /// 失去文档响应后不声称已恢复网页，直接展示独立恢复界面。
  private func fail(_ message: String) {
    timeout?.invalidate()
    startupTimeout?.invalidate()
    startupPending = false
    for timer in pendingCommands.values { timer.invalidate() }
    pendingCommands.removeAll()
    session.failed()
    shell?.setLoading(false)
    shell?.showRecovery(message: message)
  }

  /// 顶层文档导航与 hash 路由区分；新文档总会撤销旧动作和会话。
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    timeout?.invalidate()
    documentID = UUID()
    contentReady = false
    startupPending = true
    for timer in pendingCommands.values { timer.invalidate() }
    pendingCommands.removeAll()
    session.beginDocument(allowTakeover: !disableNextTakeover)
    disableNextTakeover = false
    shell?.showWebNavigation()
    shell?.setLoading(true)
    armStartupTimeout()
  }

  /// 文档下载完成后继续等待原前端首屏资源门、字体与最终绘制，不能提前透出 HTML 加载器。
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let currentDocument = documentID
    webView.callAsyncJavaScript(
      """
      await new Promise(resolve => {
        const observer = new MutationObserver(check);
        function check() {
          if (document.documentElement.getAttribute('data-launch-loading') === 'true' || document.getElementById('loading-bg')) return;
          observer.disconnect();
          resolve(true);
        }
        observer.observe(document.documentElement, {childList: true, subtree: true, attributes: true, attributeFilter: ['data-launch-loading']});
        check();
      });
      if (document.fonts?.ready) await document.fonts.ready;
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      return true;
      """,
      arguments: [:], in: nil, in: .page
    ) { [weak self] result in
      guard let self, self.documentID == currentDocument, self.startupPending else { return }
      if case .success = result {
        self.contentReady = true
        self.completeStartupIfReady()
      } else {
        self.fail("页面资源未能完成加载，请检查连接后重试。")
      }
    }
  }

  /// 同一文档的资源完成且原生接管或网页兼容导航稳定后，才结束启动页。
  private func completeStartupIfReady() {
    guard startupPending, contentReady,
      session.phase == .nativeNavigation || session.phase == .webNavigation
    else { return }
    startupPending = false
    startupTimeout?.invalidate()
    shell?.setLoading(false)
  }

  /// 只累计本次前台启动的等待，加载失败保留明确出口，不让静态画面永久遮住应用。
  private func armStartupTimeout() {
    startupTimeout?.invalidate()
    guard lifecycle == "active", startupPending else { return }
    startupTimeout = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.startupPending else { return }
        self.fail("页面资源加载超时，请检查网络和服务状态后重试。")
      }
    }
  }

  /// 连接失败不输出底层 URL 或用户数据，保留重试与配置出口。
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    if (error as NSError).code != NSURLErrorCancelled {
      fail("请检查服务地址、网络连接和局域网访问权限；HTTPS 证书需要受系统信任。")
    }
  }

  /// 已提交文档的加载错误同样进入可操作的恢复状态。
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if (error as NSError).code != NSURLErrorCancelled { fail("页面加载中断，请检查连接后重试。") }
  }

  /// 系统回收内容进程后让用户明确恢复，避免重放进行中的写操作。
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    fail("系统已回收此页面。重新打开后会恢复网页，正在进行的操作请先核对结果。")
  }

  /// 只在配置的精确来源中加载应用，外部网页交给系统浏览器且不注入桥接。
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    if navigationAction.shouldPerformDownload {
      decisionHandler(.download)
      return
    }
    if url.scheme == "blob",
      navigationAction.sourceFrame.securityOrigin.host == instance.address.origin.host
    {
      decisionHandler(.allow)
      return
    }
    if instance.address.contains(url) {
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
        decisionHandler(.cancel)
      } else {
        decisionHandler(.allow)
      }
    } else if navigationAction.targetFrame?.isMainFrame == false {
      decisionHandler(.allow)  // 远程 HTML/插件 frame 无法通过主 frame 桥接校验。
    } else {
      decisionHandler(.cancel)
      if navigationAction.navigationType == .linkActivated { openExternal(url) }
    }
  }

  /// 不可内嵌显示的响应使用 WebKit 自带下载，保留鉴权 Cookie 和 blob 支持。
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
  ) {
    let disposition =
      (navigationResponse.response as? HTTPURLResponse)?.value(
        forHTTPHeaderField: "Content-Disposition") ?? ""
    decisionHandler(
      !navigationResponse.canShowMIMEType || disposition.lowercased().hasPrefix("attachment")
        ? .download : .allow)
  }

  /// 同源新窗口沿用当前文档容器；外链使用独立系统浏览器。
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if let url = navigationAction.request.url {
      if instance.address.contains(url) {
        webView.load(navigationAction.request)
      } else {
        openExternal(url)
      }
    }
    return nil
  }

  /// 原页面的 JS alert 使用系统可访问弹窗，完成回调只执行一次。
  func webView(
    _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable () -> Void
  ) {
    guard let shell, shell.presentedViewController == nil else {
      completionHandler()
      return
    }
    let alert = UIAlertController(title: "MoviePilot", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
    shell.present(alert, animated: true)
  }

  /// 原页面的确认框保留取消语义，后台或已有弹窗时默认不确认。
  func webView(
    _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
  ) {
    guard let shell, shell.presentedViewController == nil, lifecycle == "active" else {
      completionHandler(false)
      return
    }
    let alert = UIAlertController(title: "MoviePilot", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
    alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
    shell.present(alert, animated: true)
  }

  /// 原页面的 prompt 仍由网页消费文本，原生不保存输入内容。
  func webView(
    _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor @Sendable (String?) -> Void
  ) {
    guard let shell, shell.presentedViewController == nil, lifecycle == "active" else {
      completionHandler(nil)
      return
    }
    let alert = UIAlertController(title: "MoviePilot", message: prompt, preferredStyle: .alert)
    alert.addTextField { $0.text = defaultText }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
    alert.addAction(
      UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
        completionHandler(alert?.textFields?.first?.text)
      })
    shell.present(alert, animated: true)
  }

  /// 用户触发的网页或系统协议才交给操作系统，禁止任意脚本静默启动外部应用。
  private func openExternal(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(), let shell else { return }
    if ["http", "https"].contains(scheme), url.user == nil, url.password == nil {
      shell.present(SFSafariViewController(url: url), animated: true)
    } else if ["mailto", "tel", "magnet", "thunder"].contains(scheme) {
      UIApplication.shared.open(url, options: [:])
    }
  }

  /// 导航动作转下载后保留下载对象至结束。
  func webView(
    _ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload
  ) { begin(download) }

  /// 响应头触发的下载与链接下载采用相同生命周期。
  func webView(
    _ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload
  ) { begin(download) }

  /// 绑定系统下载代理，不另写 URLSession 业务请求或复制认证状态。
  private func begin(_ download: WKDownload) {
    download.delegate = self
    downloadReferences[ObjectIdentifier(download)] = download
  }

  /// 每次下载使用独立临时目录，文件名只能是末段，避免路径穿越和覆盖文件。
  func download(
    _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
    completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
  ) {
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "MoviePilot-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let filename = (suggestedFilename as NSString).lastPathComponent
      let url = directory.appendingPathComponent(
        filename.isEmpty || filename == "." || filename == ".." ? "download" : filename)
      downloads[ObjectIdentifier(download)] = url
      completionHandler(url)
    } catch { completionHandler(nil) }
  }

  /// 下载后交给系统分享/存储面板；不将临时文件或分享目标上传到其他服务。
  func downloadDidFinish(_ download: WKDownload) {
    let key = ObjectIdentifier(download)
    downloadReferences.removeValue(forKey: key)
    guard let url = downloads.removeValue(forKey: key), let shell else { return }
    let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    share.popoverPresentationController?.sourceView = shell.view
    share.popoverPresentationController?.sourceRect = CGRect(
      x: shell.view.bounds.midX, y: shell.view.bounds.midY, width: 1, height: 1)
    share.completionWithItemsHandler = { _, _, _, _ in
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    shell.present(share, animated: true)
  }

  /// 下载失败只释放此次临时文件，不自动恢复写入或重复下载。
  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    let key = ObjectIdentifier(download)
    downloadReferences.removeValue(forKey: key)
    if let url = downloads.removeValue(forKey: key) {
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    guard let shell, shell.presentedViewController == nil else { return }
    let alert = UIAlertController(
      title: "下载未完成", message: "请检查网络后，在原页面重新选择下载。", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "好", style: .default))
    shell.present(alert, animated: true)
  }
}

/// 就绪只包含能力声明，不能携带网页凭据。
private struct ReadyPayload: Decodable {
  let majors: [Int]
  let capabilities: [String]
}

/// 网页确认的布局代次与原生准备阶段必须一致。
private struct LayoutAcknowledgement: Decodable { let layoutRevision: Int }

/// 命令分派确认关联原请求；不表示后端业务已经完成。
private struct CommandResult: Decodable {
  let requestId: String
  let accepted: Bool
}
