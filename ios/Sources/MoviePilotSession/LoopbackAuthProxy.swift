import Foundation
import Network

/// `LoopbackAuthProxy` 启动与运行期错误。
public enum LoopbackAuthProxyError: Error, Equatable, Sendable {
  /// 目标地址不是 `http` / `https`。
  case unsupportedTarget
  /// 本机环回端口未能在限定时间内进入监听状态。
  case listenerUnavailable
  /// 代理已关闭。
  case closed
}

/// 面向 `libmpv` 的单会话一次性令牌本地环回代理（仅绑定 `127.0.0.1` 随机端口），与 Android 端 `LoopbackAuthProxy` 对称：
/// 1. 上游请求统一走 `URLSession`，复用系统根证书与用户安装的受信 CA，`libmpv` 自带的 TLS 栈不再直接出网；
/// 2. 强制要求路径携带 128-bit 随机一次性会话令牌，拒绝任何未登记路径，杜绝被当作开放代理；
/// 3. 仅对与初始目标同源的请求附加实例凭据，跨源 302 与跨源 HLS 分片一律剥离 Cookie / Authorization 等敏感请求头；
/// 4. 主媒体流支持 `GET` / `HEAD` 与 `Range` 字节区间透传；HLS 播放列表会被改写，使变体、分片、密钥地址同样经由本代理拉取；
/// 5. `close()` 时立即停止监听并取消全部上游请求。
public final class LoopbackAuthProxy: NSObject, @unchecked Sendable {
  /// 单次客户端连接与其上游请求的配对状态；仅在 `queue` 内读写。
  private final class Exchange: @unchecked Sendable {
    let connection: NWConnection
    var task: URLSessionDataTask?
    var isHead = false
    var headSent = false
    var pendingBytes = 0
    var upstreamSuspended = false
    var playlistBuffer: Data?
    var playlistBaseURL: URL?
    var playlistContentType: String?
    var finished = false

    init(connection: NWConnection) {
      self.connection = connection
    }
  }

  private static let maxRequestHeadBytes = 64 * 1024
  private static let maxPlaylistBytes = 8 * 1024 * 1024
  private static let maxRouteCount = 16_384
  private static let sendHighWatermark = 4 * 1024 * 1024
  private static let sendLowWatermark = 1 * 1024 * 1024
  /// 跨源请求允许保留的非敏感请求头（小写）。
  private static let crossOriginHeaderAllowlist: Set<String> = ["user-agent"]

  private let target: URL
  private let credentialHeaders: [String: String]
  private let sessionToken: String
  private let queue: DispatchQueue
  private let configuration: URLSessionConfiguration

  // 以下状态仅在 `queue` 内读写
  private var session: URLSession?
  private var listener: NWListener?
  private var boundPort: UInt16 = 0
  private var closed = false
  private var exchanges: [ObjectIdentifier: Exchange] = [:]
  private var exchangesByTask: [Int: Exchange] = [:]
  private var routes: [String: URL] = [:]
  private var routeKeys: [URL: String] = [:]
  private var routeOrder: [String] = []
  private var routeCounter = 0

  /// 创建代理。
  /// - Parameters:
  ///   - target: 主媒体流的真实远端地址（`http` / `https`）。
  ///   - headers: 仅附加给与 `target` 同源请求的请求头（实例 Cookie、Bearer、STRM 附加头等）。
  ///   - configuration: 上游 `URLSession` 配置；缺省使用不落盘、不带 Cookie 存储的临时配置，测试可注入自定义协议。
  public init(
    target: URL,
    headers: [String: String] = [:],
    configuration: URLSessionConfiguration? = nil
  ) throws {
    guard let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https",
      target.host?.isEmpty == false
    else {
      throw LoopbackAuthProxyError.unsupportedTarget
    }
    self.target = target
    self.credentialHeaders = headers.filter { !$0.key.isEmpty && !$0.value.isEmpty }
    self.sessionToken = Self.makeSessionToken()
    self.queue = DispatchQueue(label: "com.moviepilot.playback.loopback-proxy")
    let config = configuration ?? Self.defaultConfiguration()
    self.configuration = config
    super.init()
  }

  /// 启动监听并返回供 `libmpv` 加载的本机环回地址（含单会话随机令牌，不含任何实例凭据）。
  /// 会阻塞当前线程直至端口就绪，禁止在主线程调用。
  public func start(timeout: TimeInterval = 5) throws -> URL {
    let ready = DispatchSemaphore(value: 0)
    let alreadyClosed = queue.sync { () -> Bool in
      if closed { return true }
      if session == nil {
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.underlyingQueue = queue
        session = URLSession(
          configuration: configuration, delegate: self, delegateQueue: delegateQueue)
      }
      startListener(onReady: { ready.signal() })
      return false
    }
    if alreadyClosed { throw LoopbackAuthProxyError.closed }
    _ = ready.wait(timeout: .now() + timeout)
    let port = queue.sync { boundPort }
    guard port != 0 else {
      close()
      throw LoopbackAuthProxyError.listenerUnavailable
    }
    guard let url = URL(string: Self.localURLString(port: port, token: sessionToken, target: target))
    else {
      close()
      throw LoopbackAuthProxyError.listenerUnavailable
    }
    return url
  }

  /// 停止监听并取消全部进行中的上游请求；可重复调用。
  public func close() {
    queue.async { [self] in
      guard !closed else { return }
      closed = true
      listener?.cancel()
      listener = nil
      for exchange in Array(exchanges.values) {
        finish(exchange)
      }
      session?.invalidateAndCancel()
      session = nil
      routes.removeAll()
      routeKeys.removeAll()
      routeOrder.removeAll()
    }
  }

  // MARK: - 监听

  private func startListener(onReady: (@Sendable () -> Void)?) {
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    parameters.acceptLocalOnly = true
    let port = NWEndpoint.Port(rawValue: boundPort) ?? .any
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
    guard let created = try? NWListener(using: parameters) else {
      onReady?()
      return
    }
    listener = created
    created.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    created.stateUpdateHandler = { [weak self, weak created] state in
      guard let self, let created, self.listener === created else { return }
      switch state {
      case .ready:
        if let port = created.port?.rawValue, port != 0 {
          self.boundPort = port
        }
        onReady?()
      case .failed:
        // 系统回收监听套接字（如长时间挂起）后在原端口重建，保持已交给 `libmpv` 的地址继续可用。
        created.cancel()
        self.listener = nil
        if self.boundPort == 0 {
          onReady?()
        } else if !self.closed {
          self.queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.closed, self.listener == nil else { return }
            self.startListener(onReady: nil)
          }
        }
      default:
        break
      }
    }
    created.start(queue: queue)
  }

  private func accept(_ connection: NWConnection) {
    guard !closed else {
      connection.cancel()
      return
    }
    let exchange = Exchange(connection: connection)
    exchanges[ObjectIdentifier(exchange)] = exchange
    connection.stateUpdateHandler = { [weak self, weak exchange] state in
      guard let self, let exchange else { return }
      switch state {
      case .failed, .cancelled:
        self.finish(exchange)
      default:
        break
      }
    }
    connection.start(queue: queue)
    readRequestHead(exchange, buffered: Data())
  }

  // MARK: - 请求解析

  private func readRequestHead(_ exchange: Exchange, buffered: Data) {
    exchange.connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
      [weak self, weak exchange] data, _, isComplete, error in
      guard let self, let exchange, !exchange.finished else { return }
      var buffer = buffered
      if let data { buffer.append(data) }
      if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
        self.handleRequestHead(exchange, head: buffer.subdata(in: buffer.startIndex..<end.lowerBound))
        return
      }
      if buffer.count > Self.maxRequestHeadBytes {
        self.respondSimple(exchange, status: 431)
        return
      }
      if isComplete || error != nil {
        self.finish(exchange)
        return
      }
      self.readRequestHead(exchange, buffered: buffer)
    }
  }

  private func handleRequestHead(_ exchange: Exchange, head: Data) {
    guard let text = String(data: head, encoding: .isoLatin1) else {
      respondSimple(exchange, status: 400)
      return
    }
    let lines = text.components(separatedBy: "\r\n")
    let requestParts = (lines.first ?? "").split(separator: " ")
    guard requestParts.count >= 2 else {
      respondSimple(exchange, status: 400)
      return
    }
    let method = requestParts[0].uppercased()
    guard method == "GET" || method == "HEAD" else {
      respondSimple(exchange, status: 405)
      return
    }
    let rawPath = String(requestParts[1].split(separator: "?", maxSplits: 1).first ?? "")
    guard let remoteURL = resolveRemoteURL(path: rawPath) else {
      respondSimple(exchange, status: 403)
      return
    }
    var range: String?
    var ifRange: String?
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      if name == "range" {
        range = value
      } else if name == "if-range" {
        ifRange = value
      }
    }
    guard let session else {
      respondSimple(exchange, status: 502)
      return
    }
    var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData)
    request.httpMethod = method
    request.httpShouldHandleCookies = false
    applyOutboundHeaders(to: &request, for: remoteURL)
    // 关闭传输压缩，保证回写的 `Content-Length` / `Content-Range` 与实际字节一致
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    if let range, !range.isEmpty { request.setValue(range, forHTTPHeaderField: "Range") }
    if let ifRange, !ifRange.isEmpty { request.setValue(ifRange, forHTTPHeaderField: "If-Range") }

    exchange.isHead = method == "HEAD"
    let task = session.dataTask(with: request)
    exchange.task = task
    exchangesByTask[task.taskIdentifier] = exchange
    task.resume()
    watchClientClose(exchange)
  }

  /// 响应期间持续监听客户端半关闭/断开（`libmpv` 拖动进度时会直接断开旧连接），及时取消上游请求。
  private func watchClientClose(_ exchange: Exchange) {
    exchange.connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) {
      [weak self, weak exchange] _, _, isComplete, error in
      guard let self, let exchange, !exchange.finished else { return }
      if isComplete || error != nil {
        self.finish(exchange)
      } else {
        self.watchClientClose(exchange)
      }
    }
  }

  private func resolveRemoteURL(path: String) -> URL? {
    let prefix = "/\(sessionToken)/"
    guard path.hasPrefix(prefix) else { return nil }
    let remainder = String(path.dropFirst(prefix.count))
    let name = remainder.split(separator: ".", maxSplits: 1).first.map(String.init) ?? remainder
    if name == "stream" {
      return target
    }
    if name.hasPrefix("r/") {
      return routes[String(name.dropFirst(2))]
    }
    return nil
  }

  // MARK: - 凭据边界

  /// 按同源边界重建出站请求头：同源附加完整凭据，跨源仅保留白名单内的非敏感请求头。
  private func applyOutboundHeaders(to request: inout URLRequest, for url: URL) {
    let sameOrigin = Self.isSameOrigin(url, target)
    for (name, value) in credentialHeaders {
      if sameOrigin || Self.crossOriginHeaderAllowlist.contains(name.lowercased()) {
        request.setValue(value, forHTTPHeaderField: name)
      } else {
        request.setValue(nil, forHTTPHeaderField: name)
      }
    }
    if !sameOrigin {
      request.setValue(nil, forHTTPHeaderField: "Cookie")
      request.setValue(nil, forHTTPHeaderField: "Authorization")
      request.setValue(nil, forHTTPHeaderField: "Proxy-Authorization")
    }
  }

  static func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
    func origin(_ url: URL) -> (String, String, Int)? {
      guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
        return nil
      }
      return (scheme, host, url.port ?? (scheme == "https" ? 443 : 80))
    }
    guard let left = origin(lhs), let right = origin(rhs) else { return false }
    return left == right
  }

  // MARK: - 响应回写

  private func respondSimple(_ exchange: Exchange, status: Int) {
    guard !exchange.finished, !exchange.headSent else {
      finish(exchange)
      return
    }
    exchange.headSent = true
    let head =
      "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    exchange.connection.send(
      content: Data(head.utf8), contentContext: .finalMessage, isComplete: true,
      completion: .contentProcessed { [weak self, weak exchange] _ in
        guard let self, let exchange else { return }
        self.finish(exchange)
      })
  }

  private func sendHead(_ exchange: Exchange, response: HTTPURLResponse) {
    exchange.headSent = true
    let status = response.statusCode
    var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(status))\r\n"
    if let type = response.value(forHTTPHeaderField: "Content-Type"), Self.isSafeHeaderValue(type) {
      head += "Content-Type: \(type)\r\n"
    }
    // 上游仍返回压缩内容时 `URLSession` 已透明解压，原始长度不再可信，改由连接关闭界定正文结束
    let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased() ?? ""
    if encoding.isEmpty || encoding == "identity",
      let length = response.value(forHTTPHeaderField: "Content-Length"),
      Int64(length) != nil
    {
      head += "Content-Length: \(length)\r\n"
    }
    if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
      Self.isSafeHeaderValue(contentRange)
    {
      head += "Content-Range: \(contentRange)\r\n"
    }
    if let acceptRanges = response.value(forHTTPHeaderField: "Accept-Ranges"),
      !acceptRanges.isEmpty, Self.isSafeHeaderValue(acceptRanges)
    {
      head += "Accept-Ranges: \(acceptRanges)\r\n"
    } else if status == 206 {
      head += "Accept-Ranges: bytes\r\n"
    }
    head += "Connection: close\r\n\r\n"
    sendBody(exchange, data: Data(head.utf8))
  }

  /// 回写正文并做背压：客户端消费跟不上时挂起上游任务，避免高码率流在内存中无限堆积。
  private func sendBody(_ exchange: Exchange, data: Data) {
    guard !exchange.finished, !data.isEmpty else { return }
    let count = data.count
    exchange.pendingBytes += count
    if exchange.pendingBytes > Self.sendHighWatermark, !exchange.upstreamSuspended {
      exchange.upstreamSuspended = true
      exchange.task?.suspend()
    }
    exchange.connection.send(
      content: data,
      completion: .contentProcessed { [weak self, weak exchange] error in
        guard let self, let exchange, !exchange.finished else { return }
        exchange.pendingBytes -= count
        if error != nil {
          self.finish(exchange)
          return
        }
        if exchange.upstreamSuspended, exchange.pendingBytes < Self.sendLowWatermark {
          exchange.upstreamSuspended = false
          exchange.task?.resume()
        }
      })
  }

  private func completeBody(_ exchange: Exchange) {
    guard !exchange.finished else { return }
    exchange.connection.send(
      content: nil, contentContext: .finalMessage, isComplete: true,
      completion: .contentProcessed { [weak self, weak exchange] _ in
        guard let self, let exchange else { return }
        self.finish(exchange)
      })
  }

  private func finish(_ exchange: Exchange) {
    guard !exchange.finished else { return }
    exchange.finished = true
    exchanges[ObjectIdentifier(exchange)] = nil
    if let task = exchange.task {
      exchangesByTask[task.taskIdentifier] = nil
      if exchange.upstreamSuspended { task.resume() }
      task.cancel()
    }
    exchange.task = nil
    exchange.playlistBuffer = nil
    exchange.connection.cancel()
  }

  // MARK: - HLS 播放列表改写

  private static func isPlaylistResponse(_ response: HTTPURLResponse) -> Bool {
    let mime = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
    if mime.contains("mpegurl") { return true }
    let ext = response.url?.pathExtension.lowercased() ?? ""
    return ext == "m3u8" || ext == "m3u"
  }

  /// 仅当上游返回完整正文（`200`，或从 0 起覆盖全长的 `206`）时才改写，区间片段保持原样透传。
  private static func coversWholeBody(_ response: HTTPURLResponse) -> Bool {
    if response.statusCode == 200 { return true }
    guard response.statusCode == 206,
      let contentRange = response.value(forHTTPHeaderField: "Content-Range")?.lowercased(),
      contentRange.hasPrefix("bytes ")
    else { return false }
    let spec = contentRange.dropFirst("bytes ".count).trimmingCharacters(in: .whitespaces)
    let parts = spec.split(separator: "/")
    guard parts.count == 2, let total = Int64(parts[1]) else { return false }
    let bounds = parts[0].split(separator: "-")
    guard bounds.count == 2, let first = Int64(bounds[0]), let last = Int64(bounds[1]) else {
      return false
    }
    return first == 0 && last == total - 1
  }

  /// 将播放列表内的变体、分片、密钥与初始化段地址登记为本代理路由并替换为本机环回地址。
  /// 非 UTF-8 或缺少 `#EXTM3U` 头的内容返回 `nil`，由调用方原样透传。
  private func rewritePlaylist(_ data: Data, baseURL: URL) -> Data? {
    guard let text = String(data: data, encoding: .utf8),
      text.drop(while: { $0 == "\u{FEFF}" || $0.isWhitespace }).hasPrefix("#EXTM3U")
    else { return nil }
    let rewritten = text.components(separatedBy: "\n").map { rawLine -> String in
      let hasCarriageReturn = rawLine.hasSuffix("\r")
      let line = hasCarriageReturn ? String(rawLine.dropLast()) : rawLine
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let output: String
      if trimmed.isEmpty {
        output = line
      } else if trimmed.hasPrefix("#") {
        output = rewriteAttributeURIs(in: line, baseURL: baseURL)
      } else {
        output = localRoute(for: trimmed, baseURL: baseURL) ?? line
      }
      return hasCarriageReturn ? output + "\r" : output
    }
    return Data(rewritten.joined(separator: "\n").utf8)
  }

  private func rewriteAttributeURIs(in line: String, baseURL: URL) -> String {
    var result = ""
    var remainder = Substring(line)
    while let marker = remainder.range(of: "URI=\"") {
      result += remainder[..<marker.upperBound]
      let afterMarker = remainder[marker.upperBound...]
      guard let closing = afterMarker.firstIndex(of: "\"") else {
        remainder = afterMarker
        break
      }
      let original = String(afterMarker[..<closing])
      result += localRoute(for: original, baseURL: baseURL) ?? original
      remainder = afterMarker[closing...]
    }
    return result + remainder
  }

  private func localRoute(for reference: String, baseURL: URL) -> String? {
    guard let resolved = URL(string: reference, relativeTo: baseURL)?.absoluteURL,
      let scheme = resolved.scheme?.lowercased(), scheme == "http" || scheme == "https",
      resolved.host?.isEmpty == false
    else { return nil }
    let key = registerRoute(resolved)
    return Self.localURLString(
      port: boundPort, token: sessionToken, target: resolved, name: "r/\(key)")
  }

  private func registerRoute(_ url: URL) -> String {
    if let existing = routeKeys[url] { return existing }
    routeCounter += 1
    let key = String(routeCounter, radix: 36)
    routes[key] = url
    routeKeys[url] = key
    routeOrder.append(key)
    if routeOrder.count > Self.maxRouteCount {
      let evicted = routeOrder.removeFirst()
      if let old = routes.removeValue(forKey: evicted) {
        routeKeys[old] = nil
      }
    }
    return key
  }

  // MARK: - 工具

  /// 生成本机环回地址；保留远端路径的扩展名，满足 FFmpeg HLS 解复用器对分片扩展名的校验。
  private static func localURLString(
    port: UInt16, token: String, target: URL, name: String = "stream"
  ) -> String {
    let ext = target.pathExtension.lowercased()
    let isPlainExtension =
      !ext.isEmpty && ext.count <= 8 && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    let suffix = isPlainExtension ? ".\(ext)" : ""
    return "http://127.0.0.1:\(port)/\(token)/\(name)\(suffix)"
  }

  private static func makeSessionToken() -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<16).map { _ in
      String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator))
    }.joined()
  }

  private static func defaultConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 30
    config.waitsForConnectivity = false
    return config
  }

  private static func isSafeHeaderValue(_ value: String) -> Bool {
    !value.contains("\r") && !value.contains("\n")
  }

  private static func reasonPhrase(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 206: return "Partial Content"
    case 301: return "Moved Permanently"
    case 302: return "Found"
    case 304: return "Not Modified"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 403: return "Forbidden"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 416: return "Range Not Satisfiable"
    case 431: return "Request Header Fields Too Large"
    case 502: return "Bad Gateway"
    default: return status < 400 ? "OK" : "Error"
    }
  }
}

extension LoopbackAuthProxy: URLSessionDataDelegate {
  /// 每一跳重定向都按同源边界重建请求头：跳往其它源时剥离实例凭据，跳回同源时恢复。
  public func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let url = request.url, let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      completionHandler(nil)
      return
    }
    var redirected = request
    redirected.httpShouldHandleCookies = false
    applyOutboundHeaders(to: &redirected, for: url)
    completionHandler(redirected)
  }

  public func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let exchange = exchangesByTask[dataTask.taskIdentifier], !exchange.finished,
      let http = response as? HTTPURLResponse
    else {
      completionHandler(.cancel)
      return
    }
    if !exchange.isHead, Self.isPlaylistResponse(http), Self.coversWholeBody(http) {
      exchange.playlistBuffer = Data()
      exchange.playlistBaseURL = http.url ?? dataTask.currentRequest?.url
      exchange.playlistContentType = http.value(forHTTPHeaderField: "Content-Type")
    } else {
      sendHead(exchange, response: http)
    }
    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
  {
    guard let exchange = exchangesByTask[dataTask.taskIdentifier], !exchange.finished else {
      return
    }
    if exchange.playlistBuffer != nil {
      exchange.playlistBuffer?.append(data)
      if (exchange.playlistBuffer?.count ?? 0) > Self.maxPlaylistBytes {
        respondSimple(exchange, status: 502)
      }
      return
    }
    if !exchange.isHead {
      sendBody(exchange, data: data)
    }
  }

  public func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    guard let exchange = exchangesByTask[task.taskIdentifier], !exchange.finished else { return }
    exchangesByTask[task.taskIdentifier] = nil
    exchange.task = nil
    if error != nil {
      if exchange.headSent {
        finish(exchange)
      } else {
        respondSimple(exchange, status: 502)
      }
      return
    }
    if let buffer = exchange.playlistBuffer, let http = task.response as? HTTPURLResponse {
      let baseURL = exchange.playlistBaseURL ?? target
      let body = rewritePlaylist(buffer, baseURL: baseURL) ?? buffer
      exchange.playlistBuffer = nil
      exchange.headSent = true
      var head = "HTTP/1.1 200 OK\r\n"
      if let type = exchange.playlistContentType ?? http.value(forHTTPHeaderField: "Content-Type"),
        Self.isSafeHeaderValue(type)
      {
        head += "Content-Type: \(type)\r\n"
      }
      head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
      sendBody(exchange, data: Data(head.utf8) + body)
    } else if !exchange.headSent {
      respondSimple(exchange, status: 502)
      return
    }
    completeBody(exchange)
  }
}
