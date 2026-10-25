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
  private var pendingProcessRecovery = false
  private var automaticRecoveryAttempted = false
  private var lastConfirmedURL: URL?
  private var pendingCommands: [String: Timer] = [:]
  private var commandCompletions: [String: (Bool) -> Void] = [:]
  private var downloads: [ObjectIdentifier: URL] = [:]
  private var downloadReferences: [ObjectIdentifier: WKDownload] = [:]
  private var authentication: AuthenticationResult?
  private let onAuthenticationRequired: (() -> Void)?
  private var notificationLookupStarted = false
  private var notificationNavigationAvailable = false
  private var widgetsNegotiated = false
  private var widgetContextChecked = false
  private lazy var widgetChannel = WidgetBridgeChannel(
    context: { [weak self] in
      guard let self, self.widgetsAvailable, let id = self.session.sessionId else { return nil }
      return WidgetBridgeContext(document: self.documentID, session: id)
    },
    send: { [weak self] type, request, payload in
      self?.send(type, requestId: request, payload: payload)
    })

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
        WKUserScript(
          source: script.replacingOccurrences(
            of: "__MOVIEPILOT_INSTALLATION__", with: NotificationService.installation
          ).replacingOccurrences(
            of: "/*__MOVIEPILOT_WIDGETS_CAPABILITY__*/",
            with: WidgetFeature.isEnabled ? "widgetsVersion: 1," : ""),
          injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
    if NotificationService.shared.coordinator === self { NotificationService.shared.attach(nil) }
    timeout?.invalidate()
    startupTimeout?.invalidate()
    startupPending = false
    pendingProcessRecovery = false
    documentID = UUID()
    WidgetService.shared.endSession(instanceId: instance.id, clear: false)
    cancelCommands()
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
    lastConfirmedURL = nil
    relay.owner = nil
    content.onLayout = nil
    for download in downloadReferences.values { download.cancel { _ in } }
    downloadReferences.removeAll()
    downloads.removeAll()
    session.beginDocument(allowTakeover: false)
  }

  /// 重试只 GET 当前同源文档并重新协商原生导航，绝不重发旧 POST 或未确认的业务命令。
  func reload(automatically: Bool = false) {
    let target = lastConfirmedURL ?? instance.address.recoveryURL(currentDocument: webView.url)
    documentID = UUID()
    WidgetService.shared.endSession(instanceId: instance.id, clear: false)
    timeout?.invalidate()
    startupTimeout?.invalidate()
    cancelCommands()
    pendingProcessRecovery = false
    automaticRecoveryAttempted = automatically
    contentReady = false
    startupPending = true
    session.beginDocument()
    shell?.showWebNavigation()
    shell?.setLoading(true)
    armStartupTimeout()
    webView.stopLoading()
    webView.load(URLRequest(url: target, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
  }

  /// 系统回收文档时撤销旧代次；后台只记待恢复，前台周期最多自动载入一次。
  private func recoverContentProcess() {
    guard relay.owner != nil, !pendingProcessRecovery else { return }
    documentID = UUID()
    WidgetService.shared.endSession(instanceId: instance.id, clear: false)
    timeout?.invalidate()
    startupTimeout?.invalidate()
    cancelCommands()
    session.failed()
    pendingProcessRecovery = true
    if lifecycle == "active" { resumeContentRecovery() }
  }

  /// 自动恢复失败保留明确重试出口，不能形成反复加载或业务操作重放。
  private func resumeContentRecovery() {
    guard pendingProcessRecovery else { return }
    pendingProcessRecovery = false
    guard !automaticRecoveryAttempted else {
      fail("页面暂时无法恢复，请检查连接后重新打开。未确认的操作不会自动重试。")
      return
    }
    reload(automatically: true)
  }

  /// 系统生命周期只同步给当前文档，后台暂停期间不进行超时恢复。
  func setLifecycle(_ value: String) {
    if value != "active" {
      shell?.clearNavigationPreviews()
      cancelWidgetRequest()
    } else if lifecycle != "active" {
      widgetContextChecked = false
    }
    if value == "background", lifecycle != value { automaticRecoveryAttempted = false }
    lifecycle = value
    timeout?.invalidate()
    startupTimeout?.invalidate()
    if value == "active", pendingProcessRecovery {
      resumeContentRecovery()
      return
    }
    if value == "active", startupPending { armStartupTimeout() }
    for timer in pendingCommands.values { timer.invalidate() }
    if value == "active" {
      for request in Array(pendingCommands.keys) {
        pendingCommands[request] = commandTimer(request)
      }
    }
    if session.sessionId != nil {
      send("host.lifecycle", payload: .object(["state": .string(value)]))
      if value == "active" {
        NotificationService.shared.resumePending()
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
  func invoke(
    _ action: ActionSnapshot, menuActionId: String? = nil, frame: CGRect? = nil,
    panelEvent: String? = nil, itemId: String? = nil, value: String? = nil
  ) {
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
      if let panelEvent { payload["panelEvent"] = .string(panelEvent) }
      if let itemId { payload["itemId"] = .string(itemId) }
      if let value { payload["value"] = .string(value) }
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

  /// 可选完成回调用于绘制交接；命令始终只执行一次，超时按既有路径释放导航。
  func command(_ type: String, payload: JSONValue, completion: ((Bool) -> Void)? = nil) {
    guard session.phase == .nativeNavigation, pendingCommands.count < 16, lifecycle == "active"
    else {
      completion?(false)
      return
    }
    let request = UUID().uuidString
    pendingCommands[request] = commandTimer(request)
    commandCompletions[request] = completion
    send(type, requestId: request, payload: payload)
  }

  /// 后台只暂停确认期限，恢复后重新计时，不重发可能已执行的业务命令。
  private func commandTimer(_ request: String) -> Timer {
    Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.pendingCommands.removeValue(forKey: request)
        self.commandCompletions.removeValue(forKey: request)?(false)
        self.releaseChrome()
      }
    }
  }

  /// 文档、身份或宿主失效后静默撤销旧视图回调，后续 UI 由会话释放流程统一恢复。
  private func cancelCommands() {
    cancelWidgetRequest()
    for timer in pendingCommands.values { timer.invalidate() }
    pendingCommands.removeAll()
    commandCompletions.removeAll()
  }

  /// 只有产品开关及双方能力协商都成功后才提供设置和固定小组件意图。
  var widgetsAvailable: Bool {
    WidgetFeature.isEnabled && widgetsNegotiated && lifecycle == "active"
      && session.phase == .nativeNavigation && relay.owner != nil
  }

  /// 小组件导航等待原有网页和原生弹层关闭，不将私有会话对象交给系统集成服务。
  var widgetNavigationReady: Bool {
    widgetsAvailable && session.snapshot?.presentation?.overlayOpen != true
      && shell?.presentedViewController == nil
  }

  /// 专用请求最多一个在途，取消只作用于自己的 ID，绝不重发登记或保存普通命令结果。
  func widgetRequest(_ operation: WidgetBridgeOperation) async throws -> WidgetBridgeResponse {
    try await widgetChannel.request(operation)
  }

  /// 所有失效路径都结束同一等待，旧文档和后台不能收到专用结果。
  private func cancelWidgetRequest() { widgetChannel.cancel() }

  /// WK 来源与会话校验后，独立通道再核对相关 ID、文档及有界结果。
  private func receiveWidgetResult(_ message: BridgeEnvelope) { widgetChannel.receive(message) }

  /// 只在已有本机启用资料的文档或前台周期复核一次，不为普通浏览新增业务查询。
  private func refreshWidgetContext() {
    guard widgetsAvailable, !widgetContextChecked else { return }
    widgetContextChecked = true
    WidgetService.shared.reconcile(with: self)
  }

  /// 手势只绑定已接管的当前路由；HTML 弹窗优先使用原关闭回调。
  func backGestureIdentity(sheetID: String? = nil) -> EdgeBackIdentity? {
    guard lifecycle == "active", session.phase == .nativeNavigation,
      let id = session.sessionId, let snapshot = session.snapshot
    else { return nil }
    if let sheetID {
      guard snapshot.presentation?.sheet?.id == sheetID,
        snapshot.presentation?.sheet?.canDismiss == true
      else { return nil }
    } else {
      guard snapshot.route.canGoBack, snapshot.presentation?.sheet == nil,
        snapshot.presentation?.overlayOpen != true,
        keyboardFrame.map({
          webView.convert($0, from: nil).intersection(webView.bounds).height <= 0
        }) ?? true
      else { return nil }
    }
    return EdgeBackIdentity(sessionID: id, routeRevision: session.routeRevision, sheetID: sheetID)
  }

  /// 完成时重新核对会话和路由，只发送一次原有返回或弹窗关闭意图。
  func completeBackGesture(_ identity: EdgeBackIdentity, completion: ((Bool) -> Void)? = nil) {
    guard backGestureIdentity(sheetID: identity.sheetID) == identity else {
      completion?(false)
      return
    }
    if let sheetID = identity.sheetID {
      command("presentation.dismiss", payload: .object(["id": .string(sheetID)]))
    } else {
      command(
        "navigation.back", payload: .object(["source": .string("gesture")]), completion: completion)
    }
  }

  /// 预览与当前已确认的文档会话绑定，不把关联标识用作认证或持久缓存。
  var navigationPreviewSession: String? {
    lifecycle == "active" && session.phase == .nativeNavigation ? session.sessionId : nil
  }

  /// 固定通知端点复用当前 Web 认证，不向原生暴露 token 或提供通用网络代理。
  func notificationRequest(_ action: String, extra: [String: String] = [:]) async throws -> [String:
    JSONValue]
  {
    guard ["status", "pair", "register", "unregister", "test"].contains(action),
      relay.owner != nil, let url = webView.url, instance.address.contains(url),
      session.phase == .nativeNavigation
    else { throw NotificationFailure(message: "请等待页面登录并完成加载。") }
    let document = documentID
    let identitySession = session.sessionId
    let endpoint = instance.address.url.appendingPathComponent("api/v1/notification/app")
      .absoluteString
    var body = extra
    body["action"] = action
    body["installation"] = NotificationService.installation
    body["origin"] = String(instance.address.url.absoluteString.dropLast())
    let script = """
      if (location.origin !== new URL(endpoint).origin) throw new Error('origin');
      const auth = JSON.parse(localStorage.getItem('auth') || 'null');
      if (!auth?.token) throw new Error('authentication');
      const response = await fetch(endpoint, {
        method: 'POST', credentials: 'same-origin', cache: 'no-store',
        headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + auth.token},
        body: JSON.stringify(body), signal: AbortSignal.timeout(65000)
      });
      if (!response.ok) return JSON.stringify({success:false, message:'通知服务暂不可用，请检查后台版本与渠道配置。'});
      return JSON.stringify(await response.json());
      """
    let raw: String = try await withCheckedThrowingContinuation { continuation in
      webView.callAsyncJavaScript(
        script, arguments: ["endpoint": endpoint, "body": body], in: nil, in: .page
      ) { result in
        switch result {
        case .success(let value):
          if let value = value as? String {
            continuation.resume(returning: value)
          } else {
            continuation.resume(throwing: NotificationFailure(message: "通知服务响应无效。"))
          }
        case .failure:
          continuation.resume(throwing: NotificationFailure(message: "无法连接通知服务，请检查网络与登录状态。"))
        }
      }
    }
    guard document == documentID, identitySession == session.sessionId, relay.owner != nil else {
      throw NotificationFailure(message: "登录状态已改变，请重新打开通知设置。")
    }
    let reply = try JSONDecoder().decode(NotificationReply.self, from: Data(raw.utf8))
    guard reply.success else {
      throw NotificationFailure(message: reply.message ?? "请先配置并启用 AppPush 通知渠道。")
    }
    return reply.data ?? [:]
  }

  /// 绑定状态查询只在每次已认证文档中尝试一次，旧后端不会被不断重试。
  private func refreshNotificationContext() {
    guard !notificationLookupStarted else { return }
    notificationLookupStarted = true
    Task { [weak self] in
      guard let self, let data = try? await self.notificationRequest("status"),
        case .string(let owner) = data["owner"]
      else { return }
      NotificationService.shared.identified(owner)
    }
  }

  /// 仅提交已经匹配实例与账号的内部导航，网页仍复核权限和弹层状态。
  func openNotification(_ intent: NotificationIntent) -> Bool {
    guard session.phase == .nativeNavigation, lifecycle == "active",
      intent.matches(address: instance.address, owner: NotificationService.shared.owner ?? ""),
      session.snapshot?.presentation?.overlayOpen != true
    else { return false }
    guard notificationNavigationAvailable else {
      shell?.showNotificationMessage("请更新兼容前端后，在通知中心查看这条消息。")
      return true
    }
    command("notification.open", payload: .object(["path": .string(intent.route)]))
    return true
  }

  /// 释放事务先要求网页恢复布局，收到确认后才移除系统业务栏。
  func releaseChrome() {
    guard session.sessionId != nil, session.phase != .releasing else { return }
    cancelCommands()
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
        body["version"] as? Int == 1, body["type"] as? String == "required"
      else { return }
      NotificationService.shared.disable()
      NotificationService.shared.attach(nil)
      cancelWidgetRequest()
      WidgetService.shared.endSession(instanceId: instance.id, clear: true)
      onAuthenticationRequired?()
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
      notificationNavigationAvailable = ready.capabilities.contains("notifications.v1")
      widgetsNegotiated = WidgetFeature.isEnabled && ready.capabilities.contains("widgets.v1")
      let id = try session.negotiate(majors: ready.majors, capabilities: Set(ready.capabilities))
      lastLayout = nil
      send(
        "host.configure",
        payload: .object([
          "sessionId": .string(id), "major": .number(1),
          "instanceId": .string(instance.id.uuidString),
          "capabilities": .array(
            (ChromeSession.requiredCapabilities.sorted()
              + (widgetsNegotiated ? ["widgets.v1"] : []))
              .map(JSONValue.string)),
        ]))
      armTimeout()
    case "navigation.state":
      guard let route = message.routeRevision, let state = message.stateRevision else {
        throw BridgeError.invalidMessage
      }
      let snapshot = try message.decodePayload(NavigationSnapshot.self)
      try session.receive(snapshot, routeRevision: route, stateRevision: state)
      lastConfirmedURL = instance.address.recoveryURL(
        currentDocument: webView.url, confirmedRoute: snapshot.route.fullPath)
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
        refreshNotificationContext()
        refreshWidgetContext()
        WidgetService.shared.resumePending(with: self)
        NotificationService.shared.resumePending()
      }
    case "navigation.departing":
      guard session.phase == .nativeNavigation, lifecycle == "active",
        message.routeRevision == session.routeRevision,
        case .object(let payload) = message.payload,
        case .string(let id) = payload["id"], BridgeValidator.isIdentifier(id)
      else { return }
      shell?.captureNavigationPreview()
      send("navigation.previewed", payload: .object(["id": .string(id)]))
    case "chrome.accepted":
      let accepted = try message.decodePayload(LayoutAcknowledgement.self)
      try session.accept(layoutRevision: accepted.layoutRevision)
      timeout?.invalidate()
      if let snapshot = session.snapshot { shell?.apply(snapshot) }
      layoutChanged()
      completeStartupIfReady()
      refreshNotificationContext()
      refreshWidgetContext()
      WidgetService.shared.resumePending(with: self)
    case "chrome.released":
      guard session.phase == .releasing else { throw BridgeError.busy }
      timeout?.invalidate()
      session.released()
      cancelCommands()
      shell?.showWebNavigation()
      completeStartupIfReady()
    case "command.result":
      let result = try message.decodePayload(CommandResult.self)
      guard let timer = pendingCommands.removeValue(forKey: result.requestId) else { return }
      timer.invalidate()
      let completion = commandCompletions.removeValue(forKey: result.requestId)
      completion?(result.accepted)
      if !result.accepted, completion != nil { releaseChrome() }
    case "session.state":
      widgetContextChecked = false
      WidgetService.shared.endSession(instanceId: instance.id, clear: true)
      shell?.clearNavigationPreviews()
      lastConfirmedURL = nil
      notificationLookupStarted = false
      NotificationService.shared.attach(self)
      let interruptedHandoff = !commandCompletions.isEmpty
      cancelCommands()
      if interruptedHandoff {
        // 身份变化不能继续呈现旧账号尚未绘制完成的弹窗，恢复网页后由原权限逻辑处理。
        releaseChrome()
      } else if session.phase == .nativeNavigation, let previousId = session.sessionId {
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
    case "widget.result":
      receiveWidgetResult(message)
    case "widget.logout":
      guard widgetsNegotiated, message.payload == .object([:]) else { return }
      cancelWidgetRequest()
      WidgetService.shared.endSession(instanceId: instance.id, clear: true)
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
    let currentDocument = documentID
    webView.callAsyncJavaScript(
      "window.dispatchEvent(new CustomEvent('moviepilot:native-message', {detail: message})); return true;",
      arguments: ["message": object], in: nil, in: .page
    ) { [weak self] result in
      guard let self, self.documentID == currentDocument, self.relay.owner != nil else { return }
      if case .failure = result, self.session.phase == .nativeNavigation {
        self.recoverContentProcess()
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
    documentID = UUID()
    WidgetService.shared.endSession(instanceId: instance.id, clear: false)
    pendingProcessRecovery = false
    timeout?.invalidate()
    startupTimeout?.invalidate()
    startupPending = false
    cancelCommands()
    session.failed()
    shell?.setLoading(false)
    shell?.showRecovery(message: message)
  }

  /// 顶层文档导航与 hash 路由区分；新文档总会撤销旧动作和会话。
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    timeout?.invalidate()
    lastConfirmedURL = nil
    documentID = UUID()
    WidgetService.shared.endSession(instanceId: instance.id, clear: false)
    contentReady = false
    notificationLookupStarted = false
    notificationNavigationAvailable = false
    widgetsNegotiated = false
    widgetContextChecked = false
    NotificationService.shared.attach(self)
    startupPending = true
    cancelCommands()
    session.beginDocument()
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
    if let message = ConnectionFailure(error).errorDescription { fail(message) }
  }

  /// 已提交文档的加载错误同样进入可操作的恢复状态。
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if let message = ConnectionFailure(error).errorDescription { fail(message) }
  }

  /// 内容进程在后台被系统回收后，回到前台重新载入文档并恢复原生接管。
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    recoverContentProcess()
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
