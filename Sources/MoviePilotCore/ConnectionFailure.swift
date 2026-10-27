import Foundation

/// 原生认证与网页加载共用的网络失败分类，不输出底层 URL、响应或凭据。
public enum ConnectionFailure: Error, Equatable, LocalizedError, Sendable {
  case cancelled, offline, timedOut, hostname, certificate, secureConnection, clientCertificate,
    transportSecurity, unavailable

  /// 只识别系统 URL 错误域，避免其他错误域复用数字时误报原因或吞掉失败。
  public init(_ error: Error) {
    let error = error as NSError
    guard error.domain == NSURLErrorDomain else {
      self = .unavailable
      return
    }
    switch URLError.Code(rawValue: error.code) {
    case .cancelled: self = .cancelled
    case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed: self = .offline
    case .timedOut: self = .timedOut
    case .cannotFindHost, .dnsLookupFailed: self = .hostname
    case .serverCertificateHasBadDate, .serverCertificateUntrusted,
      .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
      self = .certificate
    case .secureConnectionFailed: self = .secureConnection
    case .clientCertificateRejected, .clientCertificateRequired: self = .clientCertificate
    case .appTransportSecurityRequiresSecureConnection: self = .transportSecurity
    default: self = .unavailable
    }
  }

  /// 仅对只读服务探测重试暂时性网络故障；证书、地址、取消及未知错误仍交给用户处理。
  public static func shouldRetryServiceProbe(_ error: Error) -> Bool {
    let error = error as NSError
    guard error.domain == NSURLErrorDomain else { return false }
    switch URLError.Code(rawValue: error.code) {
    case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
      .internationalRoamingOff, .dataNotAllowed, .timedOut, .cannotFindHost, .dnsLookupFailed:
      return true
    default: return false
    }
  }

  /// 取消无需提示；其他错误只给出用户可处理的原因，不推断局域网权限已经被拒绝。
  public var errorDescription: String? {
    switch self {
    case .cancelled: nil
    case .offline:
      "当前网络不可用。若连接局域网服务，请检查系统设置中 MoviePilot 的本地网络权限。"
    case .timedOut: "连接超时，请检查网络及服务状态后重试。"
    case .hostname: "无法解析服务地址，请检查主机名及当前网络的 DNS 设置。"
    case .certificate: "服务器的 HTTPS 证书未受系统信任或已失效。请修复证书后重试。"
    case .secureConnection: "无法建立安全的 HTTPS 连接，请检查服务器的 TLS 配置。"
    case .clientCertificate: "此实例要求客户端证书，请使用网页登录。"
    case .transportSecurity: "系统阻止了不安全连接，请使用 HTTPS 或受支持的局域网地址。"
    case .unavailable: "无法连接服务，请检查地址、端口和服务状态后重试。"
    }
  }
}
