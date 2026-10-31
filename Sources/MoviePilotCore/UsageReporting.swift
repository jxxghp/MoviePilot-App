import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// iOS 安装统计独立于账号和推送标识，只在实例明确允许时向统计服务发送最小载荷。
@MainActor
public final class UsageReporting {
  public static let shared = UsageReporting()
  private let defaults: UserDefaults
  private var sending = false

  /// 注入独立偏好域供测试使用，生产使用应用私有偏好。
  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  /// 每个服务和版本每天最多成功上报一次；失败不写节流标记，升级立即重报。
  public func report(
    enabled: Bool, host: String, version: String, now: Date = Date(),
    send: (URLRequest) async throws -> Bool = { request in
      let session = URLSession(configuration: .ephemeral)
      defer { session.finishTasksAndInvalidate() }
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200,
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return false }
      return (body["code"] as? Int) == 0
    }
  ) async {
    guard enabled, !sending, !version.isEmpty, let base = URL(string: host),
      base.scheme == "https", base.host != nil, base.user == nil, base.password == nil,
      base.query == nil, base.fragment == nil
    else { return }
    let key = "moviepilot.usage.success.\(base.absoluteString).\(version)"
    if let previous = defaults.object(forKey: key) as? Date,
      now.timeIntervalSince(previous) < 86400
    {
      return
    }
    let installationKey = "moviepilot.usage.installation"
    let installation = defaults.string(forKey: installationKey) ?? UUID().uuidString
    defaults.set(installation, forKey: installationKey)
    var request = URLRequest(url: base.appendingPathComponent("usage/ios/report"))
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "installation_id": installation, "version": version,
    ])
    sending = true
    defer { sending = false }
    if (try? await send(request)) == true { defaults.set(now, forKey: key) }
  }
}
