import Foundation

/// 通知服务中心的非敏感地址；只生成主屏幕网页入口，不持有中转凭据。
public struct NotificationCenterAddress: Equatable, Sendable {
  public static let defaultAddress = "https://movie-pilot.org"
  public let url: URL

  /// 内置中心使用部署好的公开 HTTPS 地址，个人配置不影响其他实例。
  public static var defaultValue: Self { try! Self(defaultAddress) }

  /// 复用实例 URL 校验，并限制 Web Push 所需的安全来源；兼容粘贴完整通知网页地址。
  public init(_ input: String) throws {
    var address = try ServerAddress(input)
    guard
      address.origin.scheme == "https"
        || ["localhost", "127.0.0.1", "::1"].contains(address.origin.host)
    else { throw ServerAddressError.insecureRemoteServer }
    guard address.webCompatibilityError == nil else { throw ServerAddressError.invalidURL }
    if address.url.absoluteString.hasSuffix("/push/app/") {
      address = try ServerAddress(
        address.url.deletingLastPathComponent().deletingLastPathComponent().absoluteString)
    }
    url = address.url
  }

  /// 后台响应必须为规范通知网页入口，不能把其他 URL 自动采纳为服务中心。
  public init?(notificationPage: String) {
    guard let value = try? Self(notificationPage),
      let page = try? ServerAddress(notificationPage), page.url == value.pageURL
    else { return nil }
    self = value
  }

  /// 设置页显示中心基址，末尾路径斜杠由内部统一管理。
  public var displayURL: String { String(url.absoluteString.dropLast()) }

  /// 一次性绑定码仍由 MoviePilot 后台签发，App 只打开对应中心的既有网页。
  public var pageURL: URL { url.appendingPathComponent("push/app", isDirectory: true) }
}
