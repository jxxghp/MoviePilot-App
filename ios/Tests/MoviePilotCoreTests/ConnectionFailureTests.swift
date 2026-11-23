import Foundation
import Testing

@testable import MoviePilotCore

/// 网络错误必须给出正确恢复方向，并避免携带底层地址或认证信息。
struct ConnectionFailureTests {
  /// 原生请求与 WebKit 返回的系统错误使用相同分类，取消只在正确错误域中忽略。
  @Test(arguments: [
    (URLError.cancelled, ConnectionFailure.cancelled),
    (.notConnectedToInternet, .offline), (.dataNotAllowed, .offline),
    (.timedOut, .timedOut), (.cannotFindHost, .hostname), (.dnsLookupFailed, .hostname),
    (.serverCertificateUntrusted, .certificate), (.serverCertificateHasBadDate, .certificate),
    (.serverCertificateHasUnknownRoot, .certificate),
    (.serverCertificateNotYetValid, .certificate), (.secureConnectionFailed, .secureConnection),
    (.clientCertificateRequired, .clientCertificate),
    (.appTransportSecurityRequiresSecureConnection, .transportSecurity),
    (.cannotConnectToHost, .unavailable),
  ])
  func classifiesSystemErrors(code: URLError.Code, expected: ConnectionFailure) {
    let error = NSError(
      domain: NSURLErrorDomain, code: code.rawValue,
      userInfo: [
        NSLocalizedDescriptionKey: "secret-response",
        NSURLErrorFailingURLStringErrorKey:
          "https://user:secret-password@example.test/?token=secret-token",
      ])
    let failure = ConnectionFailure(error)
    #expect(failure == expected)
    #expect(!(failure.errorDescription ?? "").contains("secret"))
    #expect(!(failure.errorDescription ?? "").contains("example.test"))
    #expect((failure.errorDescription == nil) == (expected == .cancelled))
  }

  /// 业务错误与相同数字的非 URL 错误不能被当作网络取消静默丢弃。
  @Test func preservesUnknownErrors() {
    #expect(
      ConnectionFailure(NSError(domain: "MoviePilot", code: NSURLErrorCancelled)) == .unavailable)
    #expect(ConnectionFailure(NSError(domain: NSURLErrorDomain, code: -12345)) == .unavailable)
  }

  /// 自动探测仅重试可恢复网络错误，不把证书、取消或错误地址伪装成服务启动。
  @Test(arguments: [
    (URLError.cannotConnectToHost, true), (.networkConnectionLost, true),
    (.notConnectedToInternet, true), (.internationalRoamingOff, true), (.dataNotAllowed, true),
    (.timedOut, true), (.cannotFindHost, true), (.dnsLookupFailed, true),
    (.cancelled, false), (.badURL, false), (.unsupportedURL, false),
    (.serverCertificateUntrusted, false), (.secureConnectionFailed, false),
    (.clientCertificateRequired, false), (.appTransportSecurityRequiresSecureConnection, false),
  ])
  func limitsServiceProbeRetries(code: URLError.Code, expected: Bool) {
    #expect(ConnectionFailure.shouldRetryServiceProbe(URLError(code)) == expected)
  }

  /// 业务错误和未知系统错误没有自动重试授权，即使复用了连接失败的数字也不得重试。
  @Test func rejectsUnknownServiceProbeErrors() {
    #expect(!ConnectionFailure.shouldRetryServiceProbe(NSError(domain: "MoviePilot", code: -1004)))
    #expect(
      !ConnectionFailure.shouldRetryServiceProbe(NSError(domain: NSURLErrorDomain, code: -12345)))
  }
}
