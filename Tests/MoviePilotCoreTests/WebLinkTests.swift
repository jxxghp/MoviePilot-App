import Foundation
import Testing

@testable import MoviePilotCore

/// 外部打开只接受已有功能的协议，播放器参数完整留给系统与目标 App。
struct WebLinkTests {
  /// 覆盖前端所有播放器和现有系统协议，不依赖浏览器的 linkActivated 标记。
  @Test(arguments: [
    "plex://play/?metadataKey=/library/metadata/123&server=456",
    "jellyfin://media.example.test/item/123?serverId=456",
    "emby://items?serverId=server-456&itemId=item-123",
    "trimemedia://media.example.test/item/123", "douban:///search?q=Movie%202026",
    "mailto:demo@example.test", "tel:123456", "magnet:?xt=urn:btih:fixture", "thunder://fixture",
  ])
  func acceptsSupportedApplications(raw: String) throws {
    let url = try #require(URL(string: raw))
    #expect(WebLink.destination(for: url) == .application)
    #expect(url.absoluteString == raw)
  }

  /// 回退网页仍交给独立浏览器，不把播放器网页载入主业务文档。
  @Test(arguments: ["https://media.example.test/web/#/item?id=123", "http://localhost:8096/"])
  func acceptsWebFallback(raw: String) throws {
    #expect(WebLink.destination(for: try #require(URL(string: raw))) == .browser)
  }

  /// 任意协议、脚本、文件和 URL 内凭据不能通过外部打开入口。
  @Test(arguments: [
    "javascript:alert(1)", "data:text/html,fixture", "file:///tmp/fixture", "unknown://fixture",
    "https://user:secret@media.example.test/", "emby://user:secret@media.example.test/item/123",
  ])
  func rejectsUnsupportedTargets(raw: String) throws {
    #expect(WebLink.destination(for: try #require(URL(string: raw))) == nil)
  }
}
