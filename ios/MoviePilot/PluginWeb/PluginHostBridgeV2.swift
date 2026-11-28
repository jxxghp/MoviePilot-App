import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import UIKit
@preconcurrency import WebKit

/// 弱引用消息代理，防止 `WKUserContentController` 与 `PluginHostBridgeV2` 形成强引用环。
final class WeakPluginHostBridgeV2Handler: NSObject, WKScriptMessageHandler {
  weak var target: (any WKScriptMessageHandler)?
  init(_ target: any WKScriptMessageHandler) { self.target = target }
  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}

/// `moviepilot.pluginHost` v2 双向桥接宿主（iOS）：
/// - 鉴权隔离：所有 `api.request` 经原生 `URLSession` 携带 Bearer Token 代发，WebView 零令牌暴露；
/// - 严格遵循 `{ protocol: "moviepilot.pluginHost", major: 2, type, payload }` 信封与 `bridge.response` 回传约定。
@MainActor
final class PluginHostBridgeV2: NSObject, WKScriptMessageHandler {
  static let handlerName = "mpPluginHostV2"
  static let protocolName = "moviepilot.pluginHost"
  static let protocolMajor = 2

  weak var webView: WKWebView?
  weak var nativeSession: NativeSession?
  private var sessionContext: PluginShellSchemeHandler.SessionContext?
  private var inFlightTasks: [String: Task<Void, Never>] = [:]
  private let urlSession: URLSession
  private lazy var capabilitiesService: PluginNativeCapabilitiesService = {
    PluginNativeCapabilitiesService(
      urlSession: self.urlSession,
      sendResponse: { [weak self] requestId, ok, data, error in
        guard let self else { return }
        if ok {
          self.sendToWeb(
            type: "bridge.response",
            payload: [
              "requestId": requestId,
              "ok": true,
              "data": data ?? [:],
            ]
          )
        } else {
          self.sendAPIError(
            requestId: requestId,
            status: error?.status ?? 500,
            code: error?.code ?? "NATIVE_ERROR",
            message: error?.message ?? "Native capability failed"
          )
        }
      },
      sendDeviceEvent: { [weak self] event, data in
        self?.sendToWeb(
          type: "device.event",
          payload: [
            "event": event,
            "data": data,
          ]
        )
      },
      sessionContextProvider: { [weak self] in self?.sessionContext },
      nativeSessionProvider: { [weak self] in self?.nativeSession }
    )
  }()

  var onShellReady: (() -> Void)?
  var onPluginMounted: ((_ mountId: String, _ title: String) -> Void)?
  var onPluginError: ((_ stage: String, _ message: String, _ recoverable: Bool) -> Void)?
  var onPluginClose: (() -> Void)?
  var onPluginMinimize: ((_ requestId: String, _ payload: [String: Any]) -> Void)?
  var onCapsuleUpdate: ((_ payload: [String: Any]) -> Void)?
  var onPluginRestore: ((_ requestId: String) -> Void)?
  var onNavBackResult: ((_ handled: Bool) -> Void)?
  var onPluginAction: ((_ payload: [String: Any]) -> Void)?
  var onHeaderUpdate: ((_ title: String, _ actions: [NativeVueSheetAction]) -> Void)?
  var onToast: ((_ toast: PluginToastPayload) -> Void)?
  var onConfirm: ((_ confirmation: NativeVueSheetConfirmation) -> Void)?
  var onOpenRoute: ((_ path: String) -> Void)?
  var onAgentOpen: ((_ draft: String?) -> Void)?
  var onAgentClose: (() -> Void)?
  var onAgentEmit: ((_ name: String, _ data: [String: Any]) -> Void)?
  var onAgentPetAnchor: ((_ rect: CGRect?) -> Void)?
  var onAgentPetInteracting: ((_ active: Bool) -> Void)?
  var onAgentPetSay: ((_ text: String, _ durationMs: Int) -> Void)?

  override init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    config.httpCookieAcceptPolicy = .never
    config.httpShouldSetCookies = false
    self.urlSession = URLSession(configuration: config)
    super.init()
  }

  func updateSessionContext(_ context: PluginShellSchemeHandler.SessionContext?) {
    sessionContext = context
  }

  func clearCallbacks() {
    onShellReady = nil
    onPluginMounted = nil
    onPluginError = nil
    onPluginClose = nil
    onPluginMinimize = nil
    onCapsuleUpdate = nil
    onPluginRestore = nil
    onNavBackResult = nil
    onPluginAction = nil
    onHeaderUpdate = nil
    onToast = nil
    onConfirm = nil
    onOpenRoute = nil
    onAgentOpen = nil
    onAgentClose = nil
    onAgentEmit = nil
    onAgentPetAnchor = nil
    onAgentPetInteracting = nil
    onAgentPetSay = nil
  }

  func abortAllInFlightRequests() {
    for task in inFlightTasks.values {
      task.cancel()
    }
    inFlightTasks.removeAll()
  }

  func cleanupNativeCapabilities() {
    capabilitiesService.cleanup()
    nativeSession = nil
  }

  // MARK: - Host -> Web

  func sendToWeb(type: String, payload: [String: Any] = [:]) {
    guard let webView else { return }
    let envelope: [String: Any] = [
      "protocol": Self.protocolName,
      "major": Self.protocolMajor,
      "type": type,
      "payload": payload,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: envelope),
      let json = String(data: data, encoding: .utf8)
    else { return }
    let script = "window.__mpPluginHostReceive && window.__mpPluginHostReceive(\(json));"
    webView.evaluateJavaScript(script, completionHandler: nil)
  }

  func sendVisualTokens(_ tokens: PluginVisualTokensSnapshot) {
    guard let data = try? JSONEncoder().encode(tokens),
      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return }
    sendToWeb(type: "theme.update", payload: ["visualTokens": obj])
  }

  func sendLocale(_ locale: String) {
    sendToWeb(type: "locale.update", payload: ["locale": locale])
  }

    /// 将原生 Agent 状态快照发送到当前插件 WebView。
  func sendAgentState(_ state: [String: Any]) {
    sendToWeb(type: "agent.state", payload: state)
  }

    /// 向插件发送带有附加数据的 Agent 交互事件。
  func sendAgentEvent(name: String, data: [String: Any] = [:]) {
    sendToWeb(
      type: "agent.event",
      payload: [
        "name": name,
        "source": "host",
        "data": data,
        "at": Int(Date().timeIntervalSince1970 * 1000),
      ]
    )
  }

  func sendSafeArea(top: CGFloat, bottom: CGFloat, left: CGFloat = 0, right: CGFloat = 0) {
    sendToWeb(
      type: "safeArea.update",
      payload: [
        "top": Double(top),
        "bottom": Double(bottom),
        "left": Double(left),
        "right": Double(right),
      ]
    )
  }

  func sendHostAction(id: String) {
    sendToWeb(type: "host.action", payload: ["actionId": id])
  }

  func sendCapsuleAction(id: String) {
    sendToWeb(type: "capsule.action", payload: ["actionId": id])
  }

  func sendSimpleResponse(requestId: String, data: [String: Any]) {
    guard !requestId.isEmpty else { return }
    sendToWeb(
      type: "bridge.response",
      payload: [
        "requestId": requestId,
        "ok": true,
        "data": data,
      ]
    )
  }

  func sendConfirmResult(id: String, confirmed: Bool) {
    sendToWeb(
      type: "bridge.response",
      payload: [
        "requestId": id,
        "ok": true,
        "data": ["confirmed": confirmed],
      ]
    )
  }

  func sendUnmount(mountId: String? = nil) {
    if let mountId {
      sendToWeb(type: "plugin.unmount", payload: ["mountId": mountId])
    } else {
      sendToWeb(type: "plugin.unmount")
    }
  }

  func sendNavBack(mountId: String? = nil) {
    if let mountId {
      sendToWeb(type: "nav.back", payload: ["mountId": mountId])
    } else {
      sendToWeb(type: "nav.back")
    }
  }

  // MARK: - Web -> Host

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.name == Self.handlerName else { return }
    let envelope: [String: Any]
    if let dict = message.body as? [String: Any] {
      envelope = dict
    } else if let raw = message.body as? String,
      let data = raw.data(using: .utf8),
      let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    {
      envelope = dict
    } else {
      return
    }

    guard (envelope["protocol"] as? String) == Self.protocolName,
      let type = envelope["type"] as? String
    else { return }
    let payload = (envelope["payload"] as? [String: Any]) ?? [:]

    switch type {
    case "shell.ready":
      onShellReady?()

    case "plugin.mounted":
      let mountId = payload["mountId"] as? String ?? ""
      let title = payload["title"] as? String ?? ""
      onPluginMounted?(mountId, title)

    case "plugin.error":
      let stage = payload["stage"] as? String ?? "load"
      let msg = payload["message"] as? String ?? "插件加载失败"
      let recoverable = (payload["recoverable"] as? Bool) ?? true
      onPluginError?(stage, msg, recoverable)

    case "plugin.close":
      onPluginClose?()

    case "plugin.minimize":
      let reqId = payload["requestId"] as? String ?? ""
      if let onPluginMinimize {
        onPluginMinimize(reqId, payload)
      } else {
        sendSimpleResponse(requestId: reqId, data: ["minimized": false])
      }

    case "plugin.capsule.update":
      onCapsuleUpdate?(payload)

    case "plugin.restore":
      let reqId = payload["requestId"] as? String ?? ""
      if let onPluginRestore {
        onPluginRestore(reqId)
      } else {
        sendSimpleResponse(requestId: reqId, data: ["restored": true])
      }

    case "nav.backResult":
      let handled = (payload["handled"] as? Bool) ?? false
      onNavBackResult?(handled)

    case "plugin.action":
      onPluginAction?(payload)

    case "agent.open":
      onAgentOpen?(payload["draft"] as? String)

    case "agent.close":
      onAgentClose?()

    case "agent.emit":
      let name = payload["name"] as? String ?? ""
      let data = payload["data"] as? [String: Any] ?? [:]
      if !name.isEmpty {
        onAgentEmit?(name, data)
      }

    case "agent.pet.anchor":
      if let dict = payload["rect"] as? [String: Any],
        let x = (dict["x"] as? NSNumber)?.doubleValue,
        let y = (dict["y"] as? NSNumber)?.doubleValue,
        let w = (dict["width"] as? NSNumber)?.doubleValue,
        let h = (dict["height"] as? NSNumber)?.doubleValue,
        w > 0, h > 0
      {
        onAgentPetAnchor?(CGRect(x: x, y: y, width: w, height: h))
      } else {
        onAgentPetAnchor?(nil)
      }

    case "agent.pet.interacting":
      let active = (payload["active"] as? Bool) ?? false
      onAgentPetInteracting?(active)

    case "agent.pet.say":
      let text = (payload["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let duration = (payload["duration"] as? NSNumber)?.intValue ?? 3500
      if !text.isEmpty {
        onAgentPetSay?(text, min(6000, max(1500, duration)))
      }

    case "api.request":
      guard let requestId = payload["requestId"] as? String, !requestId.isEmpty else { return }
      handleAPIRequest(requestId: requestId, payload: payload)

    case "api.abort":
      if let targetId = payload["requestId"] as? String {
        inFlightTasks.removeValue(forKey: targetId)?.cancel()
      }

    case "ui.toast":
      let level = payload["level"] as? String ?? "info"
      let msg = payload["message"] as? String ?? ""
      if !msg.isEmpty {
        onToast?(PluginToastPayload(level: level, message: msg))
      }

    case "ui.confirm":
      guard let confirmId = payload["requestId"] as? String, !confirmId.isEmpty else { return }
      let title = payload["title"] as? String ?? ""
      let msg = payload["message"] as? String ?? ""
      let confirmText = (payload["confirmText"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.text("确定")
      let cancelText = (payload["cancelText"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.text("取消")
      let destructive = (payload["destructive"] as? Bool) ?? false
      let item = NativeVueSheetConfirmation(
        id: confirmId,
        title: title.isEmpty ? L10n.text("请确认") : title,
        message: msg,
        confirmText: confirmText,
        cancelText: cancelText,
        confirmEnabled: true,
        cancelEnabled: true,
        destructive: destructive
      )
      if let onConfirm {
        onConfirm(item)
      } else {
        sendConfirmResult(id: confirmId, confirmed: false)
      }

    case "ui.header":
      let title = payload["title"] as? String ?? ""
      let rawActions = payload["actions"] as? [[String: Any]] ?? []
      let actions: [NativeVueSheetAction] = rawActions.compactMap { dict in
        guard let aid = dict["id"] as? String, !aid.isEmpty else { return nil }
        let atitle = (dict["label"] as? String) ?? (dict["title"] as? String) ?? aid
        let icon = dict["icon"] as? String
        let disabled = (dict["disabled"] as? Bool) ?? false
        return NativeVueSheetAction(id: aid, title: atitle, icon: icon, enabled: !disabled)
      }
      onHeaderUpdate?(title, actions)

    case "nav.openRoute":
      let route = (payload["deepLink"] as? String) ?? (payload["path"] as? String) ?? ""
      if !route.isEmpty {
        onOpenRoute?(route)
      }

    case "nav.openExternal":
      if let raw = payload["url"] as? String,
        let url = URL(string: raw),
        let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https"
      {
        UIApplication.shared.open(url)
      }

    case "device.haptic":
      triggerHaptic(style: payload["style"] as? String ?? "light")

    case "device.clipboard":
      if let text = payload["text"] as? String {
        UIPasteboard.general.string = text
        if let reqId = payload["requestId"] as? String, !reqId.isEmpty {
          sendToWeb(
            type: "bridge.response",
            payload: ["requestId": reqId, "ok": true, "data": ["copied": true]]
          )
        }
      }

    default:
      let requestId = (payload["requestId"] as? String) ?? ""
      _ = capabilitiesService.handle(type: type, requestId: requestId, payload: payload)
    }
  }

  // MARK: - Authenticated Native API Proxy

  /// 校验插件 API 路径后，经原生实例与网关鉴权代发请求。
  private func handleAPIRequest(requestId: String, payload: [String: Any]) {
    guard let rawPath = payload["path"] as? String else {
      sendAPIError(requestId: requestId, status: 400, code: "INVALID_PATH", message: "Missing request path")
      return
    }
    guard let normalizedPath = try? PluginRemoteRuntime.validateAPIPath(rawPath) else {
      sendAPIError(requestId: requestId, status: 403, code: "FORBIDDEN_PATH", message: "Blocked unsafe API path")
      return
    }
    guard let context = sessionContext else {
      sendAPIError(requestId: requestId, status: 401, code: "NO_SESSION", message: "No active MoviePilot session")
      return
    }

    let method = (payload["method"] as? String ?? "GET").uppercased()
    let allowedMethods: Set<String> = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"]
    guard allowedMethods.contains(method) else {
      sendAPIError(requestId: requestId, status: 405, code: "METHOD_NOT_ALLOWED", message: "Unsupported HTTP method")
      return
    }

    let queryDict = payload["query"] as? [String: Any]
    guard
      let upstreamURL = buildAPIURL(
        address: context.address,
        normalizedPath: normalizedPath,
        extraQuery: queryDict
      )
    else {
      sendAPIError(requestId: requestId, status: 400, code: "INVALID_URL", message: "Failed to build upstream URL")
      return
    }

    var request = URLRequest(url: upstreamURL)
    request.httpMethod = method
    request.timeoutInterval = min(max((payload["timeoutMs"] as? Double ?? 30_000) / 1000.0, 3), 120)

    if let customHeaders = payload["headers"] as? [String: String] {
      for (k, v) in customHeaders {
        let lower = k.lowercased()
        if lower == "authorization" || lower == "cookie" || lower == "host" {
          continue
        }
        request.setValue(v, forHTTPHeaderField: k)
      }
    }

    request.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(context.locale, forHTTPHeaderField: "Accept-Language")
    request.setValue(context.locale, forHTTPHeaderField: "X-MoviePilot-Locale")
    if let cookie = context.resourceCookie {
      request.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
    }
    // 与原生 API 和插件资源通道保持相同网关鉴权，注册表会保留资源 Cookie。
    CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &request, for: context.address)

    let bodyEncoding = (payload["bodyEncoding"] as? String) ?? ""
    switch bodyEncoding {
    case "json":
      if let body = payload["body"] {
        if let serialized = try? JSONSerialization.data(withJSONObject: body) {
          request.httpBody = serialized
        } else if let str = body as? String {
          request.httpBody = Data(str.utf8)
        }
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
          request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
      }
    case "text":
      if let text = payload["body"] as? String {
        request.httpBody = Data(text.utf8)
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
          request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
      }
    case "base64":
      if let b64 = payload["body"] as? String, let bytes = Data(base64Encoded: b64) {
        request.httpBody = bytes
      }
    case "multipart":
      if let parts = payload["body"] as? [[String: Any]] {
        let boundary = "MoviePilotBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = encodeMultipart(parts: parts, boundary: boundary)
      }
    default:
      break
    }

    let responseType = (payload["responseType"] as? String) ?? "json"
    let task = Task { [weak self] in
      guard let self else { return }
      defer { self.inFlightTasks.removeValue(forKey: requestId) }
      do {
        let (data, response) = try await self.urlSession.data(for: request)
        guard !Task.isCancelled else { return }
        guard let http = response as? HTTPURLResponse else {
          self.sendAPIError(requestId: requestId, status: 502, code: "BAD_GATEWAY", message: "Invalid HTTP response")
          return
        }
        var responseHeaders: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
          let key = String(describing: k).lowercased()
          if key == "set-cookie" || key == "authorization" { continue }
          responseHeaders[key] = String(describing: v)
        }
        let bodyValue: Any
        let outEncoding: String
        if responseType == "blob" || responseType == "arraybuffer" {
          bodyValue = data.base64EncodedString()
          outEncoding = "base64"
        } else if responseType == "text" {
          bodyValue = String(data: data, encoding: .utf8) ?? ""
          outEncoding = "text"
        } else {
          if data.isEmpty {
            bodyValue = NSNull()
            outEncoding = "json"
          } else if let jsonObj = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed])
          {
            bodyValue = jsonObj
            outEncoding = "json"
          } else {
            bodyValue = String(data: data, encoding: .utf8) ?? ""
            outEncoding = "text"
          }
        }
        if (200..<300).contains(http.statusCode) {
          self.sendToWeb(
            type: "bridge.response",
            payload: [
              "requestId": requestId,
              "ok": true,
              "data": [
                "status": http.statusCode,
                "headers": responseHeaders,
                "bodyEncoding": outEncoding,
                "body": bodyValue,
              ],
            ]
          )
        } else {
          let errMsg =
            (bodyValue as? [String: Any])?["message"] as? String
            ?? (bodyValue as? [String: Any])?["detail"] as? String
            ?? "HTTP \(http.statusCode)"
          self.sendToWeb(
            type: "bridge.response",
            payload: [
              "requestId": requestId,
              "ok": false,
              "error": [
                "code": "HTTP_\(http.statusCode)",
                "status": http.statusCode,
                "message": errMsg,
                "data": bodyValue,
              ],
            ]
          )
        }
      } catch is CancellationError {
        return
      } catch {
        self.sendAPIError(requestId: requestId, status: 0, code: "NETWORK_ERROR", message: error.localizedDescription)
      }
    }
    inFlightTasks[requestId] = task
  }

  private func sendAPIError(requestId: String, status: Int, code: String, message: String) {
    sendToWeb(
      type: "bridge.response",
      payload: [
        "requestId": requestId,
        "ok": false,
        "error": [
          "code": code,
          "status": status,
          "message": message,
        ],
      ]
    )
  }

  private func buildAPIURL(
    address: ServerAddress,
    normalizedPath: String,
    extraQuery: [String: Any]?
  ) -> URL? {
    var base = address.url.absoluteString
    while base.hasSuffix("/") { base.removeLast() }
    guard var components = URLComponents(string: base + normalizedPath) else { return nil }
    if let extraQuery, !extraQuery.isEmpty {
      var items = components.queryItems ?? []
      for (key, value) in extraQuery.sorted(by: { $0.key < $1.key }) {
        if value is NSNull { continue }
        if let array = value as? [Any] {
          for element in array {
            items.append(URLQueryItem(name: key, value: "\(element)"))
          }
        } else {
          items.append(URLQueryItem(name: key, value: "\(value)"))
        }
      }
      components.queryItems = items
    }
    guard let url = components.url, address.contains(url) else { return nil }
    return url
  }

  private func encodeMultipart(parts: [[String: Any]], boundary: String) -> Data {
    var body = Data()
    for part in parts {
      guard let name = part["name"] as? String else { continue }
      body.append(Data("--\(boundary)\r\n".utf8))
      if let b64 = part["base64"] as? String {
        let filename = (part["filename"] as? String) ?? "upload.bin"
        let contentType = (part["contentType"] as? String) ?? "application/octet-stream"
        body.append(
          Data(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        if let fileData = Data(base64Encoded: b64) {
          body.append(fileData)
        }
        body.append(Data("\r\n".utf8))
      } else {
        let value = (part["value"] as? String) ?? ""
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
      }
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    return body
  }

  private func triggerHaptic(style: String) {
    switch style {
    case "medium":
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case "heavy":
      UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    case "success":
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    case "warning":
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case "error":
      UINotificationFeedbackGenerator().notificationOccurred(.error)
    case "selection":
      UISelectionFeedbackGenerator().selectionChanged()
    default:
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
  }
}
