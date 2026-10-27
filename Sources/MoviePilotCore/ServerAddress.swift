import Foundation

/// 实例地址输入错误；只描述配置问题，不包含用户输入或凭据。
public enum ServerAddressError: Error, Equatable, Sendable {
  case invalidURL
  case unsupportedScheme
  case credentialsNotAllowed
  case queryOrFragmentNotAllowed
  case insecureRemoteServer
}

/// 标准化后的同源边界，忽略默认端口差异并统一主机名大小写。
public struct WebOrigin: Codable, Equatable, Sendable {
  public let scheme: String
  public let host: String
  public let port: Int

  /// 根据 URL 提取浏览器同源比较需要的协议、主机和有效端口。
  public init?(url: URL) {
    guard let scheme = url.scheme, let host = url.host else { return nil }
    self.init(scheme: scheme, host: host, port: url.port ?? 0)
  }

  /// 接收 WebKit 安全来源；端口 0 表示当前协议的默认端口。
  public init?(scheme: String, host: String, port: Int) {
    let scheme = scheme.lowercased()
    guard ["https", "http"].contains(scheme), !host.isEmpty,
      (0...65535).contains(port)
    else { return nil }
    self.scheme = scheme
    self.host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    self.port = port == 0 ? (scheme == "https" ? 443 : 80) : port
  }
}

/// 用户配置的 MoviePilot 入口；业务路径与认证仍由此地址的网页处理。
public struct ServerAddress: Codable, Equatable, Sendable {
  public let url: URL
  public let origin: WebOrigin

  /// 解析完整 HTTP 或 HTTPS 服务地址，禁止 URL 内嵌凭据、查询串和页面片段。
  public init(_ input: String) throws {
    let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.contains(where: { $0.isWhitespace || $0.isNewline }),
      var components = URLComponents(string: input),
      let scheme = components.scheme?.lowercased()
    else {
      throw ServerAddressError.invalidURL
    }
    guard ["http", "https"].contains(scheme) else { throw ServerAddressError.unsupportedScheme }
    guard components.user == nil, components.password == nil else {
      throw ServerAddressError.credentialsNotAllowed
    }
    guard components.query == nil, components.fragment == nil else {
      throw ServerAddressError.queryOrFragmentNotAllowed
    }
    guard let host = components.host, !host.isEmpty,
      components.port.map({ (1...65535).contains($0) }) ?? true
    else {
      throw ServerAddressError.invalidURL
    }
    components.scheme = scheme
    components.host = host.lowercased()
    if components.port == (scheme == "https" ? 443 : 80) { components.port = nil }
    if !components.path.hasSuffix("/") { components.path += "/" }
    guard let url = components.url, let origin = WebOrigin(url: url) else {
      throw ServerAddressError.invalidURL
    }
    self.url = url
    self.origin = origin
  }

  /// 解码时重新执行地址校验，避免持久化文件绕过构造约束。
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(container.decode(String.self))
  }

  /// 持久化唯一标准地址；不保存 token 或 Cookie。
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(url.absoluteString)
  }

  /// 精确比较浏览器来源，子域、不同协议或非默认端口均属于另一来源。
  public func contains(_ candidate: URL) -> Bool { WebOrigin(url: candidate) == origin }

  /// 进程恢复只 GET 当前同源文档；Vue 确认的 hash 路由不会改写来源、文档路径或查询串。
  public func recoveryURL(currentDocument: URL?, confirmedRoute: String? = nil) -> URL {
    let document =
      currentDocument.flatMap { candidate in
        contains(candidate) && candidate.user == nil && candidate.password == nil ? candidate : nil
      } ?? url
    guard let confirmedRoute, NavigationSnapshot.isRoute(confirmedRoute) else { return document }
    var base = URLComponents(url: document, resolvingAgainstBaseURL: true)
    base?.fragment = nil
    guard let reference = base?.url?.absoluteString,
      let target = URL(string: "\(reference)#\(confirmedRoute)", encodingInvalidCharacters: false),
      contains(target)
    else { return document }
    return target
  }

  /// Foundation 可保存带网卡标识的 IPv6，但浏览器 URL 不支持；保留旧配置身份并阻止连接。
  public var webCompatibilityError: String? {
    guard origin.host.contains(":"), origin.host.contains("%") else { return nil }
    return "此 IPv6 地址包含网卡标识，网页无法使用。请改用 .local 主机名或其他可访问的地址。"
  }

  /// 判断主机是否属于私网、链路本地、回环或本地 DNS。
  public static func isLocalHost(_ host: String) -> Bool {
    let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if host == "localhost" || host.hasSuffix(".local") { return true }
    if host == "::1" || host.hasPrefix("fc") && host.contains(":")
      || host.hasPrefix("fd") && host.contains(":")
      || ["fe8", "fe9", "fea", "feb"].contains(where: { host.hasPrefix($0) }) && host.contains(":")
    {
      return true
    }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
      let a = Int(parts[0]), let b = Int(parts[1]),
      parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false })
    {
      return a == 10 || a == 127 || a == 192 && b == 168
        || a == 172 && (16...31).contains(b) || a == 169 && b == 254
    }
    return !host.contains(".") && !host.contains(":")
      && host.contains(where: \.isLetter)
      && host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
  }
}
