import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
@preconcurrency import WebKit

/// 自定义本地虚拟源 `mp-plugin://shell/` 协议处理器：
/// - `/shell/*` 直接零网络读取应用包内 `PluginShell/` 静态运行时资产；
/// - `/plugin-remote/{pluginId}/{version}/*` 优先命中实例隔离磁盘缓存，未命中时原生鉴权拉取 `/api/v1/plugin/file/...` 并落盘；
/// - `/api/v1/*` 仅允许被动 `GET` 资源（图片、图标、插件静态资源）经原生鉴权代拉，绝不向 WebView 暴露 Bearer Token。
@MainActor
final class PluginShellSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "mp-plugin"
  static let host = "shell"
  static let origin = "mp-plugin://shell"
  static let entryURL = URL(string: "mp-plugin://shell/shell/plugin-shell.html")!

  /// 资源容器绑定的实例身份；Cookie 快照只供没有原生会话的调用兼容使用。
  struct SessionContext: Sendable {
    let address: ServerAddress
    let accessToken: String
    let resourceCookie: APIExportedResourceCookie?
    let locale: String
  }

  private var sessionContext: SessionContext?
  weak var nativeSession: NativeSession?
  private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
  private let urlSession: URLSession

  /// 禁止资源回源自动跳转，避免实例凭据被转发到其他来源。
  override init() {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 25
    config.timeoutIntervalForResource = 60
    config.httpCookieAcceptPolicy = .never
    config.httpShouldSetCookies = false
    self.urlSession = URLSession(
      configuration: config, delegate: PluginResourceRedirectGuard(), delegateQueue: nil)
    super.init()
  }

  /// 切换或释放容器身份，清除旧会话引用。
  func updateSessionContext(_ context: SessionContext?) {
    sessionContext = context
    if context == nil { nativeSession = nil }
  }

  /// 中断已移除的 WebView 请求，防止向失效的 scheme task 回调。
  func cancelAllRequests() {
    for task in activeTasks.values {
      task.cancel()
    }
    activeTasks.removeAll()
  }

  /// 按受控虚拟源路径分派本地资源、远程模块和被动 API 资源。
  func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    let taskID = ObjectIdentifier(urlSchemeTask)
    guard let url = urlSchemeTask.request.url else {
      respondError(urlSchemeTask, status: 400, message: "Missing URL")
      return
    }
    let path = url.path
    if path.hasPrefix("/shell/") {
      serveLocalShellAsset(url: url, task: urlSchemeTask)
      return
    }
    if path.hasPrefix("/plugin-remote/") {
      let context = sessionContext
      let fetchTask = Task { [weak self] in
        guard let self else { return }
        await self.serveRemotePluginAsset(
          url: url,
          taskID: taskID,
          task: urlSchemeTask,
          context: context
        )
      }
      activeTasks[taskID] = fetchTask
      return
    }
    if path.hasPrefix("/api/v1/") {
      let method = (urlSchemeTask.request.httpMethod ?? "GET").uppercased()
      guard method == "GET" || method == "HEAD" else {
        respondError(
          urlSchemeTask, status: 405, message: "Only passive GET allowed on virtual origin")
        return
      }
      let context = sessionContext
      let fetchTask = Task { [weak self] in
        guard let self else { return }
        await self.servePassiveAPIResource(
          url: url,
          method: method,
          taskID: taskID,
          task: urlSchemeTask,
          context: context
        )
      }
      activeTasks[taskID] = fetchTask
      return
    }
    respondError(urlSchemeTask, status: 404, message: "Not Found")
  }

  /// WebKit 停止读取时同步取消原生网络任务。
  func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
    let taskID = ObjectIdentifier(urlSchemeTask)
    activeTasks.removeValue(forKey: taskID)?.cancel()
  }

  // MARK: - 1. 包内极简联邦运行时壳静态文件

  /// 从包内读取经过路径校验的运行时文件。
  private func serveLocalShellAsset(url: URL, task: any WKURLSchemeTask) {
    guard let relPath = try? PluginRemoteRuntime.validateShellAssetPath(url.path),
      let shellRoot = Bundle.main.url(forResource: "PluginShell", withExtension: nil)
    else {
      respondError(task, status: 404, message: "PluginShell bundle resource not found")
      return
    }
    let baseDir = shellRoot.standardizedFileURL
    let fileURL = baseDir.appendingPathComponent(relPath, isDirectory: false).standardizedFileURL
    guard fileURL.path.hasPrefix(baseDir.path + "/"),
      let data = try? Data(contentsOf: fileURL)
    else {
      respondError(task, status: 404, message: "Shell asset not found: \(relPath)")
      return
    }
    let mime = PluginRemoteRuntime.mimeType(forPath: relPath)
    respondData(
      task,
      url: url,
      status: 200,
      contentType: mime,
      data: data,
      cacheControl: "no-cache"
    )
  }

  // MARK: - 2. 联邦插件远程分片（磁盘缓存优先 + 原生鉴权回源）

  /// 在实例隔离缓存未命中时携带当前资源 Cookie 读取插件模块。
  private func serveRemotePluginAsset(
    url: URL,
    taskID: ObjectIdentifier,
    task: any WKURLSchemeTask,
    context: SessionContext?
  ) async {
    defer { activeTasks.removeValue(forKey: taskID) }
    guard let target = try? PluginRemoteRuntime.resolveUpstreamPath(url.path) else {
      if !Task.isCancelled {
        respondError(task, status: 400, message: "Invalid plugin remote path")
      }
      return
    }
    guard let context else {
      if !Task.isCancelled {
        respondError(task, status: 401, message: "No active MoviePilot session")
      }
      return
    }

    let originKey = context.address.url.absoluteString
    if let cached = await PluginRemoteDiskCache.shared.read(
      instanceOrigin: originKey,
      pluginId: target.pluginId,
      versionTag: target.versionTag,
      assetRelPath: target.assetRelPath
    ) {
      if !Task.isCancelled && activeTasks[taskID] != nil {
        respondData(
          task,
          url: url,
          status: 200,
          contentType: cached.contentType,
          data: cached.data,
          cacheControl: "public, max-age=31536000, immutable"
        )
      }
      return
    }

    guard
      let upstreamURL = buildUpstreamURL(address: context.address, apiPath: target.upstreamApiPath)
    else {
      if !Task.isCancelled && activeTasks[taskID] != nil {
        respondError(task, status: 400, message: "Invalid upstream URL")
      }
      return
    }

    do {
      let (data, response) = try await fetchResource(
        url: upstreamURL, method: "GET", context: context)
      guard !Task.isCancelled, activeTasks[taskID] != nil else { return }
      guard let http = response as? HTTPURLResponse else {
        respondError(task, status: 502, message: "Invalid upstream response")
        return
      }
      let mime =
        normalizedContentType(
          http.value(forHTTPHeaderField: "Content-Type"), fallbackPath: target.assetRelPath)
      if (200..<300).contains(http.statusCode) {
        await PluginRemoteDiskCache.shared.write(
          data: data,
          contentType: mime,
          instanceOrigin: originKey,
          pluginId: target.pluginId,
          versionTag: target.versionTag,
          assetRelPath: target.assetRelPath
        )
      }
      guard !Task.isCancelled, activeTasks[taskID] != nil else { return }
      respondData(
        task,
        url: url,
        status: http.statusCode,
        contentType: mime,
        data: data,
        cacheControl: (200..<300).contains(http.statusCode)
          ? "public, max-age=31536000, immutable"
          : "no-store"
      )
    } catch {
      guard !Task.isCancelled, activeTasks[taskID] != nil else { return }
      respondError(task, status: 502, message: error.localizedDescription)
    }
  }

  // MARK: - 3. 被动静态资源代理（图片/图标/插件附件 GET /api/v1/*）

  /// 代理受同源边界约束的图片、附件及其他被动读取。
  private func servePassiveAPIResource(
    url: URL,
    method: String,
    taskID: ObjectIdentifier,
    task: any WKURLSchemeTask,
    context: SessionContext?
  ) async {
    defer { activeTasks.removeValue(forKey: taskID) }
    let fullPathWithQuery: String
    if let query = url.query, !query.isEmpty {
      fullPathWithQuery = "\(url.path)?\(query)"
    } else {
      fullPathWithQuery = url.path
    }
    guard let normalizedPath = try? PluginRemoteRuntime.validateAPIPath(fullPathWithQuery) else {
      if !Task.isCancelled && activeTasks[taskID] != nil {
        respondError(task, status: 400, message: "Invalid API path")
      }
      return
    }
    guard let context else {
      if !Task.isCancelled && activeTasks[taskID] != nil {
        respondError(task, status: 401, message: "No active session")
      }
      return
    }
    guard let upstreamURL = buildUpstreamURL(address: context.address, apiPath: normalizedPath)
    else {
      if !Task.isCancelled && activeTasks[taskID] != nil {
        respondError(task, status: 400, message: "Invalid upstream URL")
      }
      return
    }

    do {
      let (data, response) = try await fetchResource(
        url: upstreamURL, method: method, context: context)
      guard !Task.isCancelled, activeTasks[taskID] != nil else { return }
      guard let http = response as? HTTPURLResponse else {
        respondError(task, status: 502, message: "Invalid upstream response")
        return
      }
      let mime = normalizedContentType(
        http.value(forHTTPHeaderField: "Content-Type"),
        fallbackPath: url.path
      )
      respondData(
        task,
        url: url,
        status: http.statusCode,
        contentType: mime,
        data: data,
        cacheControl: (200..<300).contains(http.statusCode) ? "private, max-age=300" : "no-store"
      )
    } catch {
      guard !Task.isCancelled, activeTasks[taskID] != nil else { return }
      respondError(task, status: 502, message: error.localizedDescription)
    }
  }

  // MARK: - Helpers

  /// 每次分块加载读取最新 Cookie；资源 401 只续签重试一次，不销毁主登录态。
  private func fetchResource(
    url: URL, method: String, context: SessionContext
  ) async throws -> (Data, URLResponse) {
    let owner = nativeSession
    var cookie = context.resourceCookie
    if let owner { cookie = try await owner.resolveResourceCookie() }
    try validateOwner(owner, context: context)
    for attempt in 0...1 {
      var request = URLRequest(url: url)
      request.httpMethod = method
      applyAuthHeaders(to: &request, context: context, cookie: cookie)
      let response = try await urlSession.data(for: request)
      try validateOwner(owner, context: context)
      guard (response.1 as? HTTPURLResponse)?.statusCode == 401, attempt == 0,
        let owner
      else { return response }
      let refresh = try APIEndpoint(path: ["media", "source"])
      _ = try await owner.request(refresh, as: [JSONValue].self)
      cookie = try await owner.resolveResourceCookie()
      try validateOwner(owner, context: context)
    }
    throw URLError(.userAuthenticationRequired)
  }

  /// 请求前后都核对容器归属，禁止旧容器借用切换后的账号凭据。
  private func validateOwner(_ owner: NativeSession?, context: SessionContext) throws {
    try Task.checkCancellation()
    guard sessionContext?.address == context.address,
      sessionContext?.accessToken == context.accessToken, nativeSession === owner
    else { throw CancellationError() }
    if let owner {
      let auth = try owner.playbackAuthorization()
      guard auth.address == context.address, auth.accessToken == context.accessToken else {
        throw CancellationError()
      }
    }
  }

  /// 构造并校验资源所属实例的上游地址。
  private func buildUpstreamURL(address: ServerAddress, apiPath: String) -> URL? {
    var base = address.url.absoluteString
    while base.hasSuffix("/") { base.removeLast() }
    let joined = base + (apiPath.hasPrefix("/") ? apiPath : "/\(apiPath)")
    guard let target = URL(string: joined), address.contains(target) else { return nil }
    return target
  }

  /// 仅在原生请求中附加身份，不向插件 JavaScript 暴露凭据。
  private func applyAuthHeaders(
    to request: inout URLRequest, context: SessionContext, cookie: APIExportedResourceCookie?
  ) {
    request.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue(context.locale, forHTTPHeaderField: "Accept-Language")
    request.setValue(context.locale, forHTTPHeaderField: "X-MoviePilot-Locale")
    if let cookie {
      request.setValue("\(cookie.name)=\(cookie.value)", forHTTPHeaderField: "Cookie")
    }
    CloudflareAccessCredentialRegistry.shared.applyHeaders(to: &request, for: context.address)
  }

  /// 缺失或泛型 MIME 使用已知静态文件类型，保留服务器给出的明确类型。
  private func normalizedContentType(_ raw: String?, fallbackPath: String) -> String {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty || trimmed.lowercased().hasPrefix("application/octet-stream") {
      return PluginRemoteRuntime.mimeType(forPath: fallbackPath)
    }
    return trimmed
  }

  /// 把资源响应交付给仍存活的 WebKit scheme task。
  private func respondData(
    _ task: any WKURLSchemeTask,
    url: URL,
    status: Int,
    contentType: String,
    data: Data,
    cacheControl: String
  ) {
    let headers: [String: String] = [
      "Content-Type": contentType,
      "Content-Length": "\(data.count)",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
      "Cache-Control": cacheControl,
    ]
    if let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    ) {
      task.didReceive(response)
      task.didReceive(data)
      task.didFinish()
    } else {
      task.didFailWithError(URLError(.cannotDecodeContentData))
    }
  }

  /// 错误响应禁止缓存，允许用户重试后重新鉴权加载。
  private func respondError(_ task: any WKURLSchemeTask, status: Int, message: String) {
    let url = task.request.url ?? Self.entryURL
    let body = Data(message.utf8)
    respondData(
      task,
      url: url,
      status: status,
      contentType: "text/plain; charset=utf-8",
      data: body,
      cacheControl: "no-store"
    )
  }
}

/// 插件资源只允许读取声明的同源地址，不自动跟随重定向。
private final class PluginResourceRedirectGuard: NSObject, URLSessionTaskDelegate {
  /// 即使上游返回重定向，也保留原状态供插件显示加载失败。
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
