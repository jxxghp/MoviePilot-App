import AuthenticationServices
import Foundation
import MoviePilotCore
import UIKit

/// Cloudflare Access Managed OAuth（RFC 9728 / RFC 8414 / RFC 7591 / RFC 7636 PKCE）iOS 端管理器。
/// 使用 `ASWebAuthenticationSession` 完成系统安全认证，令牌仅存入本机 Keychain 并按同源边界注入。
@MainActor
final class CloudflareAccessAuthManager: NSObject {
  static let shared = CloudflareAccessAuthManager()

  enum AuthError: LocalizedError {
    case discoveryFailed
    case registrationFailed
    case cancelled
    case callbackInvalid(String)
    case tokenExchangeFailed

    var errorDescription: String? {
      switch self {
      case .discoveryFailed:
        return "未能发现 Cloudflare Access OAuth 元数据，请确认服务已开启 Cloudflare Access OAuth 认证。"
      case .registrationFailed:
        return "Cloudflare Access 动态客户端注册失败，请检查 Access 应用策略。"
      case .cancelled:
        return "已取消 Cloudflare Access 认证。"
      case .callbackInvalid(let detail):
        return detail.isEmpty ? "Cloudflare Access 回调校验失败，请重试。" : detail
      case .tokenExchangeFailed:
        return "未能换取 Cloudflare Access 访问令牌，请重试。"
      }
    }
  }

  private var activeSession: ASWebAuthenticationSession?
  private let urlSession: URLSession

  private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      completionHandler(nil)
    }
  }

  override init() {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCache = nil
    config.timeoutIntervalForRequest = 20
    config.timeoutIntervalForResource = 45
    self.urlSession = URLSession(
      configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    super.init()
  }

  /// 当前服务器是否已拥有有效的 Cloudflare Access OAuth 令牌。
  func hasSession(for address: ServerAddress) -> Bool {
    CloudflareAccessCredentialRegistry.shared.accessToken(for: address) != nil
  }

  /// 主动清除指定服务器的 Cloudflare Access 授权。
  func clearSession(for address: ServerAddress) {
    CloudflareAccessCredentialRegistry.shared.clear(for: address, persist: true)
  }

  /// 若当前保存的 Cloudflare Access 会话临近过期且存在 `refresh_token`，静默刷新并持久化。
  func refreshIfNeeded(for address: ServerAddress) async {
    guard let existing = CloudflareAccessCredentialRegistry.shared.session(for: address),
      existing.needsRefresh(),
      let refreshToken = existing.refreshToken, !refreshToken.isEmpty,
      let tokenURL = URL(string: existing.tokenEndpoint)
    else { return }

    let form = Self.formEncoded([
      ("grant_type", "refresh_token"),
      ("refresh_token", refreshToken),
      ("client_id", existing.clientId),
    ])
    var req = URLRequest(url: tokenURL)
    req.httpMethod = "POST"
    req.setValue(
      "application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = form

    guard let (data, raw) = try? await urlSession.data(for: req),
      let http = raw as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let newAccessToken = (payload["access_token"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !newAccessToken.isEmpty
    else { return }

    let nextRefresh = (payload["refresh_token"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let expiresIn = (payload["expires_in"] as? NSNumber)?.int64Value
    let expiresAtMs = expiresIn.map { Int64(Date().timeIntervalSince1970 * 1000) + $0 * 1000 }
    let updated = CloudflareAccessSession(
      serverOrigin: existing.serverOrigin,
      accessToken: newAccessToken,
      refreshToken: (nextRefresh?.isEmpty == false) ? nextRefresh : existing.refreshToken,
      expiresAtEpochMs: expiresAtMs,
      clientId: existing.clientId,
      tokenEndpoint: existing.tokenEndpoint,
      issuer: existing.issuer
    )
    CloudflareAccessCredentialRegistry.shared.store(updated, persist: true)
  }

  /// 执行完整 Cloudflare Access Managed OAuth（RFC 9728 -> RFC 8414 -> RFC 7591 DCR -> PKCE S256 + RFC 8707 resource -> Token 交换）。
  func authenticate(address: ServerAddress) async throws -> CloudflareAccessSession {
    let origin = CloudflareAccessProtocol.normalizedOriginKey(for: address)
    let resourceMetaHint = await probeResourceMetadataHint(for: address)
    let (serverMeta, discoveredResource) = try await discoverServerMetadata(
      serverURL: address.url.absoluteString, hintURL: resourceMetaHint)
    let resolvedResource =
      discoveredResource
      ?? CloudflareAccessProtocol.normalizedResourceIndicator(for: address.url.absoluteString)
      ?? origin

    let cachedClientId = CloudflareAccessCredentialRegistry.shared
      .session(for: address)
      .flatMap { $0.issuer == serverMeta.issuer && !$0.clientId.isEmpty ? $0.clientId : nil }
    let clientId: String
    if let cachedClientId {
      clientId = cachedClientId
    } else if let regEndpoint = serverMeta.registrationEndpoint {
      clientId = try await registerDynamicClient(endpoint: regEndpoint)
    } else {
      throw AuthError.registrationFailed
    }

    let pkce = CloudflareAccessProtocol.generatePKCEPair()
    let authorizeURL = try CloudflareAccessProtocol.buildAuthorizeURL(
      authorizationEndpoint: serverMeta.authorizationEndpoint,
      clientId: clientId,
      redirectURI: defaultCloudflareOAuthRedirectURI,
      codeChallenge: pkce.codeChallenge,
      state: pkce.state,
      resource: resolvedResource
    )

    let callbackURL = try await presentAuthSession(url: authorizeURL)
    let parsed = CloudflareAccessProtocol.parseCallbackURL(callbackURL, expectedState: pkce.state)
    guard parsed.valid, let code = parsed.code else {
      let detail = parsed.errorDescription ?? parsed.error ?? ""
      throw AuthError.callbackInvalid(detail)
    }

    let session = try await exchangeAuthorizationCode(
      origin: origin,
      serverMeta: serverMeta,
      clientId: clientId,
      code: code,
      codeVerifier: pkce.codeVerifier
    )
    CloudflareAccessCredentialRegistry.shared.store(session, persist: true)
    return session
  }

  // MARK: - Discovery & Registration

  private func probeResourceMetadataHint(for address: ServerAddress) async -> String? {
    let probeURL = address.url.appending(path: "api").appending(path: "v1").appending(
      path: "system"
    )
    .appending(path: "setup-status")
    var req = URLRequest(url: probeURL)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    guard let (data, raw) = try? await urlSession.data(for: req),
      let http = raw as? HTTPURLResponse
    else { return nil }
    let result = CloudflareAccessProtocol.detectChallenge(
      response: http, bodyData: data, requestURL: probeURL)
    return result.resourceMetadataUrl
  }

  private func discoverServerMetadata(serverURL: String, hintURL: String?) async throws
    -> (CloudflareOAuthServerMetadata, String?)
  {
    let candidates = CloudflareAccessProtocol.buildDiscoveryURLs(
      serverURL: serverURL, resourceMetadataURL: hintURL)
    var authServerMetadataURLs: [String] = []
    var discoveredResource: String?

    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      guard let (data, raw) = try? await fetchJSON(url: url),
        (200..<300).contains(raw.statusCode)
      else { continue }
      if let directMeta = try? CloudflareAccessProtocol.parseOAuthServerMetadata(data) {
        return (directMeta, discoveredResource)
      }
      if let prm = try? CloudflareAccessProtocol.parseProtectedResourceMetadataDetail(data) {
        if discoveredResource == nil, let res = prm.resource, !res.isEmpty {
          discoveredResource = res
        }
        for s in prm.authorizationServers where !authServerMetadataURLs.contains(s) {
          authServerMetadataURLs.append(s)
        }
      }
    }

    for metaURLStr in authServerMetadataURLs {
      guard let url = URL(string: metaURLStr) else { continue }
      if let (data, raw) = try? await fetchJSON(url: url),
        (200..<300).contains(raw.statusCode),
        let meta = try? CloudflareAccessProtocol.parseOAuthServerMetadata(data)
      {
        return (meta, discoveredResource)
      }
    }

    throw AuthError.discoveryFailed
  }

  private func registerDynamicClient(endpoint: String) async throws -> String {
    guard let url = URL(string: endpoint) else { throw AuthError.registrationFailed }
    let payload: [String: Any] = [
      "client_name": "MoviePilot iOS",
      "redirect_uris": [defaultCloudflareOAuthRedirectURI],
      "grant_types": ["authorization_code", "refresh_token"],
      "response_types": ["code"],
      "token_endpoint_auth_method": "none",
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (data, raw) = try await urlSession.data(for: req)
    guard let http = raw as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let clientId = (obj["client_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !clientId.isEmpty
    else {
      throw AuthError.registrationFailed
    }
    return clientId
  }

  private func exchangeAuthorizationCode(
    origin: String,
    serverMeta: CloudflareOAuthServerMetadata,
    clientId: String,
    code: String,
    codeVerifier: String
  ) async throws -> CloudflareAccessSession {
    guard let tokenURL = URL(string: serverMeta.tokenEndpoint) else {
      throw AuthError.tokenExchangeFailed
    }
    let body = Self.formEncoded([
      ("grant_type", "authorization_code"),
      ("code", code),
      ("redirect_uri", defaultCloudflareOAuthRedirectURI),
      ("client_id", clientId),
      ("code_verifier", codeVerifier),
    ])
    var req = URLRequest(url: tokenURL)
    req.httpMethod = "POST"
    req.setValue(
      "application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = body

    let (data, raw) = try await urlSession.data(for: req)
    guard let http = raw as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let accessToken = (obj["access_token"] as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !accessToken.isEmpty
    else {
      throw AuthError.tokenExchangeFailed
    }
    let refreshToken = (obj["refresh_token"] as? String)?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let expiresIn = (obj["expires_in"] as? NSNumber)?.int64Value
    let expiresAtMs = expiresIn.map { Int64(Date().timeIntervalSince1970 * 1000) + $0 * 1000 }
    return CloudflareAccessSession(
      serverOrigin: origin,
      accessToken: accessToken,
      refreshToken: (refreshToken?.isEmpty == false) ? refreshToken : nil,
      expiresAtEpochMs: expiresAtMs,
      clientId: clientId,
      tokenEndpoint: serverMeta.tokenEndpoint,
      issuer: serverMeta.issuer
    )
  }

  private func fetchJSON(url: URL) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, raw) = try await urlSession.data(for: req)
    guard let http = raw as? HTTPURLResponse else { throw AuthError.discoveryFailed }
    return (data, http)
  }

  // MARK: - ASWebAuthenticationSession

  private func presentAuthSession(url: URL) async throws -> URL {
    activeSession?.cancel()
    activeSession = nil
    return try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: "moviepilot"
      ) { [weak self] callbackURL, error in
        Task { @MainActor in
          self?.activeSession = nil
          if let callbackURL {
            continuation.resume(returning: callbackURL)
          } else if let asError = error as? ASWebAuthenticationSessionError,
            asError.code == .canceledLogin
          {
            continuation.resume(throwing: AuthError.cancelled)
          } else {
            continuation.resume(
              throwing: AuthError.callbackInvalid(error?.localizedDescription ?? ""))
          }
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      self.activeSession = session
      if !session.start() {
        self.activeSession = nil
        continuation.resume(throwing: AuthError.cancelled)
      }
    }
  }

  private static func formEncoded(_ pairs: [(String, String)]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let body = pairs.map { k, v in
      let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
      let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
      return "\(ek)=\(ev)"
    }.joined(separator: "&")
    return Data(body.utf8)
  }
}

extension CloudflareAccessAuthManager: ASWebAuthenticationPresentationContextProviding {
  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
    -> ASPresentationAnchor
  {
    MainActor.assumeIsolated {
      for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
          return keyWindow
        }
        if let first = windowScene.windows.first {
          return first
        }
      }
      return ASPresentationAnchor()
    }
  }
}
