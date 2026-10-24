import Foundation
import Testing

@testable import MoviePilotCore

/// 验证通知载荷与自定义链接共用的实例、账号和内部路由边界。
struct NotificationTests {
  /// 默认公开中心和反向代理子路径均生成规范入口，旧后台配置可继续使用。
  @Test func notificationCenterNormalizesPageAndBase() throws {
    #expect(NotificationCenterAddress.defaultValue.displayURL == "https://movie-pilot.org")
    #expect(
      NotificationCenterAddress.defaultValue.pageURL.absoluteString
        == "https://movie-pilot.org/push/app/")
    let base = try NotificationCenterAddress("https://CENTER.test:443/base")
    #expect(
      NotificationCenterAddress(notificationPage: "https://center.test/base/push/app/") == base)
    #expect(try NotificationCenterAddress("https://center.test/base/push/app") == base)
    #expect(NotificationCenterAddress(notificationPage: "https://center.test/other") == nil)
    #expect(base != NotificationCenterAddress.defaultValue)
  }

  /// 网页绑定只允许安全来源，不采纳携带凭据或查询参数的后台地址。
  @Test func notificationCenterRejectsUnsafeAddresses() {
    for value in [
      "http://center.test", "http://192.168.1.2", "javascript:alert(1)",
      "https://user:secret@center.test", "https://center.test/?token=secret",
      "https://center.test/#fragment",
    ] {
      #expect(throws: (any Error).self) { try NotificationCenterAddress(value) }
      #expect(NotificationCenterAddress(notificationPage: value) == nil)
    }
    #expect(
      NotificationCenterAddress(notificationPage: "http://127.0.0.1:3301/push/app/") != nil)
  }

  /// 规范地址允许冷启动后匹配，子目录、端口和账号改变均不能继承通知。
  @Test func matchesOnlyBoundAccountAndInstance() throws {
    let intent = try #require(
      NotificationIntent(
        origin: "https://mp.test/base", route: "/history", owner: String(repeating: "a", count: 32))
    )
    #expect(
      intent.matches(
        address: try ServerAddress("https://mp.test/base/"),
        owner: String(repeating: "a", count: 32)))
    #expect(!intent.matches(address: try ServerAddress("https://mp.test/"), owner: intent.owner))
    #expect(
      !intent.matches(address: try ServerAddress("https://mp.test:8443/base/"), owner: intent.owner)
    )
    #expect(!intent.matches(address: intent.address, owner: String(repeating: "b", count: 32)))
  }

  /// 跳转参数必须完整、唯一；通知文本不能升级为外站导航或脚本。
  @Test func rejectsExternalRoutesAndAmbiguousLinks() throws {
    for route in [
      "https://foreign.test", "//foreign.test", "/\\foreign", "/\nredirect", "/\u{202E}redirect",
    ] {
      #expect(
        NotificationIntent(
          origin: "https://mp.test", route: route, owner: String(repeating: "a", count: 32)) == nil)
    }
    var parts = URLComponents(string: "moviepilot-app://notification")!
    parts.queryItems = [
      URLQueryItem(name: "origin", value: "https://mp.test"),
      URLQueryItem(name: "route", value: "/?shotcut=message"),
      URLQueryItem(name: "owner", value: String(repeating: "a", count: 32)),
    ]
    #expect(NotificationIntent(url: try #require(parts.url))?.route == "/?shotcut=message")
    parts.queryItems?.append(URLQueryItem(name: "owner", value: String(repeating: "b", count: 32)))
    #expect(NotificationIntent(url: try #require(parts.url)) == nil)
  }
}
