import Foundation
import Testing

@testable import MoviePilotCore

/// 统计上报使用隔离偏好域和内存传输，验证隐私开关、节流及升级。
@MainActor
struct UsageReportingTests {
  /// 只有允许分享时发送，重连去重而升级及跨天允许更新。
  @Test func consentDeduplicationAndUpgrade() async throws {
    let domain = "UsageReportingTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let reporter = UsageReporting(defaults: defaults)
    var bodies: [[String: String]] = []
    let now = Date()
    /// 捕获实际网络边界的最小载荷，模拟服务确认成功。
    func send(_ request: URLRequest) async throws -> Bool {
      #expect(request.url?.absoluteString == "https://example.org/usage/ios/report")
      #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
      bodies.append(
        try JSONDecoder().decode([String: String].self, from: #require(request.httpBody)))
      return true
    }
    await reporter.report(enabled: false, host: "https://example.org", version: "1.0.5", send: send)
    #expect(bodies.isEmpty)
    await reporter.report(enabled: true, host: "http://example.org", version: "1.0.5", send: send)
    #expect(bodies.isEmpty)
    await reporter.report(
      enabled: true, host: "https://example.org", version: "1.0.5", now: now, send: send)
    await reporter.report(
      enabled: true, host: "https://example.org", version: "1.0.5", now: now, send: send)
    #expect(bodies.count == 1)
    await reporter.report(
      enabled: true, host: "https://example.org", version: "1.0.6", now: now, send: send)
    await reporter.report(
      enabled: true, host: "https://example.org", version: "1.0.6",
      now: now.addingTimeInterval(86401), send: send)
    #expect(bodies.count == 3)
    #expect(Set(bodies.compactMap { $0["installation_id"] }).count == 1)
    #expect(bodies.allSatisfy { Set($0.keys) == ["installation_id", "version"] })
  }

  /// 服务拒绝或网络失败后，下次连接允许重试。
  @Test func failureDoesNotThrottle() async throws {
    let domain = "UsageReportingTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let reporter = UsageReporting(defaults: defaults)
    var calls = 0
    for _ in 0..<2 {
      await reporter.report(enabled: true, host: "https://example.org", version: "1.0.5") { _ in
        calls += 1
        return false
      }
    }
    #expect(calls == 2)
  }
}
