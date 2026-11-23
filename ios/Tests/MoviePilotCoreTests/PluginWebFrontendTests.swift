import Foundation
import Testing

@testable import MoviePilotCore

/// 覆盖联邦插件兼容宿主寻找 Web 前端入口的候选顺序与入口文档识别。
struct PluginWebFrontendTests {
  /// 连接后端 API 端口时，先试当前地址，再试同主机前端端口，最后试访问域名。
  @Test func ordersCurrentAddressFrontendPortAndDomain() throws {
    let api = try ServerAddress("http://127.0.0.1:3001")
    let result = PluginWebFrontend.candidates(
      api: api, frontendPort: 3000, appDomain: "https://mp.example.test")
    #expect(
      result.map(\.url.absoluteString) == [
        "http://127.0.0.1:3001/", "http://127.0.0.1:3000/", "https://mp.example.test/",
      ])
  }

  /// 已经连接前端端口或域名与当前地址同源时不重复探测；子路径部署保留路径前缀。
  @Test func deduplicatesAndKeepsBasePath() throws {
    let api = try ServerAddress("https://mp.example.test/moviepilot")
    let result = PluginWebFrontend.candidates(
      api: api, frontendPort: 443, appDomain: "mp.example.test")
    #expect(result.map(\.url.absoluteString) == ["https://mp.example.test/moviepilot/"])
  }

  /// HTTPS 连接不会降级到明文访问域名；非法端口被忽略。
  @Test func rejectsDowngradeAndInvalidPort() throws {
    let api = try ServerAddress("https://api.example.test:3001")
    let result = PluginWebFrontend.candidates(
      api: api, frontendPort: 70000, appDomain: "http://mp.example.test")
    #expect(result.map(\.url.absoluteString) == ["https://api.example.test:3001/"])
  }

  /// 只有返回 HTML 且包含 Vue 挂载点的响应才视为前端；后端 404 JSON 被排除。
  @Test func recognizesFrontendDocumentOnly() {
    let html = Data("<!doctype html><html><body><div id=\"app\"></div></body></html>".utf8)
    #expect(
      PluginWebFrontend.isFrontendDocument(
        statusCode: 200, contentType: "text/html; charset=UTF-8", body: html))
    #expect(
      !PluginWebFrontend.isFrontendDocument(
        statusCode: 404, contentType: "application/json",
        body: Data("{\"success\":false,\"message\":\"Not Found\"}".utf8)))
    #expect(
      !PluginWebFrontend.isFrontendDocument(
        statusCode: 200, contentType: "text/html", body: Data("<html>nginx</html>".utf8)))
  }
}
