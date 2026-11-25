import CryptoKit
import Foundation
import Security

/// Cloudflare Access Managed OAuth 默认跨端回调 URI。
public let defaultCloudflareOAuthRedirectURI = "moviepilot://oauth/callback"

/// Cloudflare Access 拦截探测结果（与 Rust `mp-core-model::CloudflareChallengeResult` 1:1 对齐）。
public struct CloudflareChallengeResult: Codable, Equatable, Sendable {
  public let isChallenge: Bool
  public let reason: String
  public let resourceMetadataUrl: String?
  public let loginUrl: String?

  public init(
    isChallenge: Bool,
    reason: String,
    resourceMetadataUrl: String? = nil,
    loginUrl: String? = nil
  ) {
    self.isChallenge = isChallenge
    self.reason = reason
    self.resourceMetadataUrl = resourceMetadataUrl
    self.loginUrl = loginUrl
  }
}

/// RFC 7636 PKCE `S256` 校验对与防 CSRF `state`。
public struct CloudflarePKCEPair: Codable, Equatable, Sendable {
  public let codeVerifier: String
  public let codeChallenge: String
  public let codeChallengeMethod: String
  public let state: String

  public init(
    codeVerifier: String,
    codeChallenge: String,
    codeChallengeMethod: String = "S256",
    state: String
  ) {
    self.codeVerifier = codeVerifier
    self.codeChallenge = codeChallenge
    self.codeChallengeMethod = codeChallengeMethod
    self.state = state
  }
}

/// RFC 8414 OAuth 授权服务器元数据。
public struct CloudflareOAuthServerMetadata: Codable, Equatable, Sendable {
  public let issuer: String
  public let authorizationEndpoint: String
  public let tokenEndpoint: String
  public let registrationEndpoint: String?

  public init(
    issuer: String,
    authorizationEndpoint: String,
    tokenEndpoint: String,
    registrationEndpoint: String? = nil
  ) {
    self.issuer = issuer
    self.authorizationEndpoint = authorizationEndpoint
    self.tokenEndpoint = tokenEndpoint
    self.registrationEndpoint = registrationEndpoint
  }
}

/// OAuth 回调解析与 `state` 校验结果。
public struct CloudflareOAuthCallbackResult: Codable, Equatable, Sendable {
  public let valid: Bool
  public let stateMatched: Bool
  public let code: String?
  public let error: String?
  public let errorDescription: String?

  public init(
    valid: Bool,
    stateMatched: Bool,
    code: String? = nil,
    error: String? = nil,
    errorDescription: String? = nil
  ) {
    self.valid = valid
    self.stateMatched = stateMatched
    self.code = code
    self.error = error
    self.errorDescription = errorDescription
  }
}

/// 按规范化服务器源隔离保存的 Cloudflare Access OAuth 会话凭据。
public struct CloudflareAccessSession: Codable, Equatable, Sendable {
  public let serverOrigin: String
  public let accessToken: String
  public let refreshToken: String?
  public let expiresAtEpochMs: Int64?
  public let clientId: String
  public let tokenEndpoint: String
  public let issuer: String

  public init(
    serverOrigin: String,
    accessToken: String,
    refreshToken: String? = nil,
    expiresAtEpochMs: Int64? = nil,
    clientId: String,
    tokenEndpoint: String,
    issuer: String = ""
  ) {
    self.serverOrigin = serverOrigin
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAtEpochMs = expiresAtEpochMs
    self.clientId = clientId
    self.tokenEndpoint = tokenEndpoint
    self.issuer = issuer
  }

  /// 是否已过期或在指定提前刷新窗口（默认 120 秒）内即将过期。
  public func needsRefresh(nowEpochMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000), leewayMs: Int64 = 120_000) -> Bool {
    guard let expiresAtEpochMs, expiresAtEpochMs > 0 else { return false }
    return nowEpochMs + leewayMs >= expiresAtEpochMs
  }
}

public enum CloudflareOAuthProtocolError: Error, Equatable, Sendable {
  case invalidMetadata(String)
  case invalidAuthorizationEndpoint(String)
  case emptyClientId
}

/// 跨端同构的纯 Swift Cloudflare Access Managed OAuth 协议内核（与 Rust `mp-core-model::cloudflare_oauth` 1:1 对齐）。
public enum CloudflareAccessProtocol {

  /// 计算用于隔离持久化与同源匹配的规范化源键（`scheme://host[:port]`）。
  public static func normalizedOriginKey(for address: ServerAddress) -> String {
    let origin = address.origin
    let defaultPort = origin.scheme == "https" ? 443 : 80
    if origin.port == defaultPort {
      return "\(origin.scheme)://\(origin.host)"
    }
    return "\(origin.scheme)://\(origin.host):\(origin.port)"
  }

  /// 计算任意 URL 字符串对应的规范化源键。
  public static func normalizedOriginKey(for rawURL: String) -> String? {
    guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      let origin = WebOrigin(url: url)
    else { return nil }
    let defaultPort = origin.scheme == "https" ? 443 : 80
    if origin.port == defaultPort {
      return "\(origin.scheme)://\(origin.host)"
    }
    return "\(origin.scheme)://\(origin.host):\(origin.port)"
  }

  /// 检测 HTTP 响应是否被 Cloudflare Access 拦截。
  public static func detectChallenge(
    statusCode: Int,
    headers: [String: String],
    bodyPrefix: String = "",
    requestURL: String
  ) -> CloudflareChallengeResult {
    var lowerHeaders: [String: String] = [:]
    lowerHeaders.reserveCapacity(headers.count)
    for (k, v) in headers {
      lowerHeaders[k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = v
    }

    if (300..<400).contains(statusCode), let location = lowerHeaders["location"] {
      let locLower = location.lowercased()
      if locLower.contains("cloudflareaccess.com") || locLower.contains("/cdn-cgi/access/login") {
        let resolved = resolveRelativeURL(base: requestURL, candidate: location)
        return CloudflareChallengeResult(
          isChallenge: true,
          reason: "redirect_to_cloudflare_access",
          resourceMetadataUrl: nil,
          loginUrl: resolved
        )
      }
    }

    if (statusCode == 401 || statusCode == 403), let wwwAuth = lowerHeaders["www-authenticate"] {
      if let metaURL = extractWWWAuthenticateParam(header: wwwAuth, key: "resource_metadata") {
        return CloudflareChallengeResult(
          isChallenge: true,
          reason: "www_authenticate_resource_metadata",
          resourceMetadataUrl: resolveRelativeURL(base: requestURL, candidate: metaURL),
          loginUrl: nil
        )
      }
      let authLower = wwwAuth.lowercased()
      let hasCFHeader =
        lowerHeaders["cf-ray"] != nil
        || (lowerHeaders["server"]?.lowercased().contains("cloudflare") == true)
      if hasCFHeader
        && (authLower.contains("cloudflareaccess") || authLower.contains("cf-access")
          || authLower.contains("oauth"))
      {
        return CloudflareChallengeResult(
          isChallenge: true,
          reason: "www_authenticate_cloudflare",
          resourceMetadataUrl: nil,
          loginUrl: nil
        )
      }
    }

    let prefix = String(bodyPrefix.prefix(8_192)).lowercased()
    let looksHTML =
      (lowerHeaders["content-type"]?.lowercased().contains("text/html") == true)
      || prefix.contains("<!doctype html") || prefix.contains("<html")
    if looksHTML
      && (prefix.contains("cloudflareaccess.com") || prefix.contains("/cdn-cgi/access/login")
        || (prefix.contains("cloudflare access") && prefix.contains("sign in")))
    {
      return CloudflareChallengeResult(
        isChallenge: true,
        reason: "html_cloudflare_access_gate",
        resourceMetadataUrl: nil,
        loginUrl: nil
      )
    }

    return CloudflareChallengeResult(isChallenge: false, reason: "")
  }

  /// 便捷重载：直接从 `HTTPURLResponse` 提取小写响应头字典并检测 Cloudflare Access 拦截。
  public static func detectChallenge(
    response: HTTPURLResponse,
    bodyData: Data? = nil,
    requestURL: URL
  ) -> CloudflareChallengeResult {
    var headers: [String: String] = [:]
    for (k, v) in response.allHeaderFields {
      headers[String(describing: k)] = String(describing: v)
    }
    let bodyPrefix: String
    if let bodyData, !bodyData.isEmpty {
      bodyPrefix = String(decoding: bodyData.prefix(8_192), as: UTF8.self)
    } else {
      bodyPrefix = ""
    }
    return detectChallenge(
      statusCode: response.statusCode,
      headers: headers,
      bodyPrefix: bodyPrefix,
      requestURL: requestURL.absoluteString
    )
  }

  /// 生成高熵 RFC 7636 PKCE `S256` 校验对与防 CSRF `state`。
  public static func generatePKCEPair() -> CloudflarePKCEPair {
    let verifierBytes = randomBytes(count: 48)
    let stateBytes = randomBytes(count: 24)
    let verifier = base64URLEncode(verifierBytes)
    let challenge = computePKCES256Challenge(codeVerifier: verifier)
    let state = base64URLEncode(stateBytes)
    return CloudflarePKCEPair(
      codeVerifier: verifier,
      codeChallenge: challenge,
      codeChallengeMethod: "S256",
      state: state
    )
  }

  /// 根据 RFC 7636 计算 `BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))`。
  public static func computePKCES256Challenge(codeVerifier: String) -> String {
    let digest = SHA256.hash(data: Data(codeVerifier.utf8))
    return base64URLEncode(Data(digest))
  }

  /// 构造按 RFC 9728 -> RFC 8414 优先顺序排列的元数据探测 URL 列表。
  public static func buildDiscoveryURLs(
    serverURL: String,
    resourceMetadataURL: String? = nil
  ) -> [String] {
    var urls: [String] = []
    if let meta = resourceMetadataURL?.trimmingCharacters(in: .whitespacesAndNewlines),
      !meta.isEmpty, isValidHTTPURL(meta)
    {
      urls.append(meta)
    }
    if let origin = normalizedOriginKey(for: serverURL) {
      let prm = "\(origin)/.well-known/oauth-protected-resource"
      if !urls.contains(prm) { urls.append(prm) }
      let asMeta = "\(origin)/.well-known/oauth-authorization-server"
      if !urls.contains(asMeta) { urls.append(asMeta) }
    }
    return urls
  }

  /// 解析 RFC 9728 Protected Resource Metadata，返回授权服务器元数据地址列表。
  public static func parseProtectedResourceMetadata(_ data: Data) throws -> [String] {
    guard
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let servers = obj["authorization_servers"] as? [Any]
    else {
      throw CloudflareOAuthProtocolError.invalidMetadata("Missing authorization_servers array")
    }
    var out: [String] = []
    for entry in servers {
      guard let raw = (entry as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty, isValidHTTPURL(raw)
      else { continue }
      let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
      if trimmed.contains("/.well-known/") {
        out.append(trimmed)
      } else {
        out.append("\(trimmed)/.well-known/oauth-authorization-server")
      }
    }
    guard !out.isEmpty else {
      throw CloudflareOAuthProtocolError.invalidMetadata("No valid authorization server URL found")
    }
    return out
  }

  /// 解析 RFC 8414 Authorization Server Metadata 并校验端点协议安全性。
  public static func parseOAuthServerMetadata(_ data: Data) throws -> CloudflareOAuthServerMetadata {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CloudflareOAuthProtocolError.invalidMetadata("Invalid OAuth server metadata JSON")
    }
    guard
      let authEP = (obj["authorization_endpoint"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      isValidHTTPURL(authEP)
    else {
      throw CloudflareOAuthProtocolError.invalidMetadata("Missing or invalid authorization_endpoint")
    }
    guard
      let tokenEP = (obj["token_endpoint"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      isValidHTTPURL(tokenEP)
    else {
      throw CloudflareOAuthProtocolError.invalidMetadata("Missing or invalid token_endpoint")
    }
    let regEP = (obj["registration_endpoint"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let validRegEP = regEP.flatMap { isValidHTTPURL($0) ? $0 : nil }
    let issuer = (obj["issuer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return CloudflareOAuthServerMetadata(
      issuer: issuer,
      authorizationEndpoint: authEP,
      tokenEndpoint: tokenEP,
      registrationEndpoint: validRegEP
    )
  }

  /// 构造标准 OAuth 2.0 + PKCE (`S256`) 授权跳转 URL。
  public static func buildAuthorizeURL(
    authorizationEndpoint: String,
    clientId: String,
    redirectURI: String = defaultCloudflareOAuthRedirectURI,
    codeChallenge: String,
    state: String,
    scope: String = "openid email profile offline_access"
  ) throws -> URL {
    let cleanEndpoint = authorizationEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidHTTPURL(cleanEndpoint),
      var components = URLComponents(string: cleanEndpoint)
    else {
      throw CloudflareOAuthProtocolError.invalidAuthorizationEndpoint(cleanEndpoint)
    }
    let cleanClient = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanClient.isEmpty else {
      throw CloudflareOAuthProtocolError.emptyClientId
    }
    let cleanRedirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalRedirect = cleanRedirect.isEmpty ? defaultCloudflareOAuthRedirectURI : cleanRedirect

    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: "response_type", value: "code"))
    items.append(URLQueryItem(name: "client_id", value: cleanClient))
    items.append(URLQueryItem(name: "redirect_uri", value: finalRedirect))
    items.append(
      URLQueryItem(
        name: "code_challenge",
        value: codeChallenge.trimmingCharacters(in: .whitespacesAndNewlines)
      ))
    items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
    items.append(
      URLQueryItem(name: "state", value: state.trimmingCharacters(in: .whitespacesAndNewlines)))
    let cleanScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleanScope.isEmpty {
      items.append(URLQueryItem(name: "scope", value: cleanScope))
    }
    components.queryItems = items
    guard let url = components.url else {
      throw CloudflareOAuthProtocolError.invalidAuthorizationEndpoint(cleanEndpoint)
    }
    return url
  }

  /// 解析并严格比对 `moviepilot://oauth/callback?code=...&state=...` 回调 URL。
  public static func parseCallbackURL(
    _ callbackURL: URL,
    expectedState: String
  ) -> CloudflareOAuthCallbackResult {
    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
      return CloudflareOAuthCallbackResult(
        valid: false, stateMatched: false, error: "invalid_callback_url")
    }
    var code: String?
    var state: String?
    var error: String?
    var errorDescription: String?
    for item in components.queryItems ?? [] {
      guard let val = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty
      else { continue }
      switch item.name {
      case "code": code = val
      case "state": state = val
      case "error": error = val
      case "error_description": errorDescription = val
      default: break
      }
    }
    let cleanExpected = expectedState.trimmingCharacters(in: .whitespacesAndNewlines)
    let stateMatched = !cleanExpected.isEmpty && state == cleanExpected
    let valid = stateMatched && error == nil && code != nil
    return CloudflareOAuthCallbackResult(
      valid: valid,
      stateMatched: stateMatched,
      code: stateMatched ? code : nil,
      error: error,
      errorDescription: errorDescription
    )
  }

  /// 将 `CF_Authorization=<token>` 安全合并到现有 `Cookie` 请求头中，保留 `resource_token` 等同源 Cookie。
  public static func mergeCookieHeader(existing: String?, cfToken: String) -> String {
    let cleanToken = cfToken.trimmingCharacters(in: .whitespacesAndNewlines)
    var parts: [String] = []
    if let existing, !existing.isEmpty {
      for rawSegment in existing.split(separator: ";") {
        let segment = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { continue }
        let name = segment.split(separator: "=", maxSplits: 1).first?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.caseInsensitiveCompare("CF_Authorization") == .orderedSame {
          continue
        }
        parts.append(segment)
      }
    }
    if !cleanToken.isEmpty {
      parts.append("CF_Authorization=\(cleanToken)")
    }
    return parts.joined(separator: "; ")
  }

  // MARK: - Helpers

  private static func isValidHTTPURL(_ raw: String) -> Bool {
    guard let url = URL(string: raw),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      let host = url.host, !host.isEmpty
    else { return false }
    return true
  }

  private static func resolveRelativeURL(base: String, candidate: String) -> String {
    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    if isValidHTTPURL(trimmed) { return trimmed }
    if let baseURL = URL(string: base), let resolved = URL(string: trimmed, relativeTo: baseURL) {
      return resolved.absoluteURL.absoluteString
    }
    return trimmed
  }

  private static func extractWWWAuthenticateParam(header: String, key: String) -> String? {
    let lower = header.lowercased()
    let needle = "\(key.lowercased())="
    guard let range = lower.range(of: needle) else { return nil }
    let restStart = header.index(header.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
    let rest = header[restStart...].drop(while: { $0.isWhitespace })
    if rest.first == "\"" {
      let afterQuote = rest.dropFirst()
      guard let endQuote = afterQuote.firstIndex(of: "\"") else { return nil }
      let val = afterQuote[..<endQuote].trimmingCharacters(in: .whitespacesAndNewlines)
      return val.isEmpty ? nil : val
    }
    let token = rest.prefix(while: { $0 != "," && !$0.isWhitespace })
    let val = token.trimmingCharacters(in: .whitespacesAndNewlines)
    return val.isEmpty ? nil : val
  }

  private static func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func randomBytes(count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    if status != errSecSuccess {
      for i in 0..<count { bytes[i] = UInt8.random(in: 0...255) }
    }
    return Data(bytes)
  }
}

/// 进程内线程安全 + 本机 Keychain 持久化的 Cloudflare Access 令牌注册表。
/// 严格按规范化同源边界（`scheme://host[:port]`）查询与注入，绝不覆盖 `Authorization: Bearer`。
public final class CloudflareAccessCredentialRegistry: @unchecked Sendable {
  public static let shared = CloudflareAccessCredentialRegistry()

  private let lock = NSLock()
  private var sessionsByOrigin: [String: CloudflareAccessSession] = [:]
  private let keychainService = "org.moviepilot.cfaccess.v1"

  public init() {}

  /// 读取指定实例源的内存/Keychain Cloudflare Access 会话。
  public func session(for address: ServerAddress, loadFromKeychain: Bool = true)
    -> CloudflareAccessSession?
  {
    let origin = CloudflareAccessProtocol.normalizedOriginKey(for: address)
    return session(forOrigin: origin, loadFromKeychain: loadFromKeychain)
  }

  /// 读取指定源键的会话。
  public func session(forOrigin origin: String, loadFromKeychain: Bool = true)
    -> CloudflareAccessSession?
  {
    let cached: CloudflareAccessSession? = lock.withLock { sessionsByOrigin[origin] }
    if let cached { return cached }
    guard loadFromKeychain else { return nil }
    if let loaded = readKeychain(origin: origin) {
      lock.withLock { sessionsByOrigin[origin] = loaded }
      return loaded
    }
    return nil
  }

  /// 读取指定实例可用的 CF Access 令牌（仅当非空时返回）。
  public func accessToken(for address: ServerAddress) -> String? {
    guard let token = session(for: address)?.accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
      !token.isEmpty
    else { return nil }
    return token
  }

  /// 缓存并可选持久化指定实例的 Cloudflare Access 会话（`persist = false` 适用于无 Keychain 单测）。
  public func store(_ session: CloudflareAccessSession, persist: Bool = true) {
    let cleanOrigin =
      CloudflareAccessProtocol.normalizedOriginKey(for: session.serverOrigin) ?? session.serverOrigin
    let normalized = CloudflareAccessSession(
      serverOrigin: cleanOrigin,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresAtEpochMs: session.expiresAtEpochMs,
      clientId: session.clientId,
      tokenEndpoint: session.tokenEndpoint,
      issuer: session.issuer
    )
    lock.withLock { sessionsByOrigin[cleanOrigin] = normalized }
    if persist {
      writeKeychain(normalized, origin: cleanOrigin)
    }
  }

  /// 清除指定实例的 Cloudflare Access 会话与 Keychain 记录。
  public func clear(for address: ServerAddress, persist: Bool = true) {
    let origin = CloudflareAccessProtocol.normalizedOriginKey(for: address)
    clear(forOrigin: origin, persist: persist)
  }

  /// 清除指定源键的 Cloudflare Access 会话。
  public func clear(forOrigin origin: String, persist: Bool = true) {
    lock.withLock { _ = sessionsByOrigin.removeValue(forKey: origin) }
    if persist {
      deleteKeychain(origin: origin)
    }
  }

  /// 为严格同源的 `URLRequest` 安全附加 `Cookie: CF_Authorization=...`（保留现有 `resource_token`）与 `cf-access-token` 请求头；
  /// 绝不触碰 `Authorization`，且绝不向跨源 URL 注入任何凭据。
  public func applyHeaders(to request: inout URLRequest, for address: ServerAddress) {
    guard let url = request.url, address.contains(url),
      let cfToken = accessToken(for: address)
    else { return }
    let existingCookie = request.value(forHTTPHeaderField: "Cookie")
    let mergedCookie = CloudflareAccessProtocol.mergeCookieHeader(
      existing: existingCookie, cfToken: cfToken)
    if !mergedCookie.isEmpty {
      request.setValue(mergedCookie, forHTTPHeaderField: "Cookie")
    }
    request.setValue(cfToken, forHTTPHeaderField: "cf-access-token")
  }

  /// 将当前实例的 `CF_Authorization` 合并入同源 Cookie 请求头字符串（用于播放器/WebView 场景）。
  public func mergedCookieHeader(existing: String?, for address: ServerAddress) -> String? {
    guard let cfToken = accessToken(for: address) else { return existing }
    let merged = CloudflareAccessProtocol.mergeCookieHeader(existing: existing, cfToken: cfToken)
    return merged.isEmpty ? existing : merged
  }

  // MARK: - Keychain Persistence

  private func keychainKey(origin: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: origin,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private func readKeychain(origin: String) -> CloudflareAccessSession? {
    var query = keychainKey(origin: origin)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(CloudflareAccessSession.self, from: data)
  }

  private func writeKeychain(_ session: CloudflareAccessSession, origin: String) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    let query = keychainKey(origin: origin)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess { return }
    if status == errSecItemNotFound {
      var item = query.merging(attributes) { _, new in new }
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      _ = SecItemAdd(item as CFDictionary, nil)
    }
  }

  private func deleteKeychain(origin: String) {
    _ = SecItemDelete(keychainKey(origin: origin) as CFDictionary)
  }
}
