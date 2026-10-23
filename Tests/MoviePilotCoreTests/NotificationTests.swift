import Foundation
import Testing

@testable import MoviePilotCore

/// 验证通知载荷与自定义链接共用的实例、账号和内部路由边界。
struct NotificationTests {
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
