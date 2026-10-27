import Foundation
import Testing

@testable import MoviePilotCore

/// 覆盖 HTTP/HTTPS 输入、持久化配置与精确来源的边界。
struct ServerAddressTests {
  /// 同一来源可使用默认端口表示法，但子域和协议不能混淆。
  @Test func normalizesOriginAndBasePath() throws {
    let server = try ServerAddress("  HTTPS://MP.EXAMPLE.TEST:443/moviepilot  ")
    #expect(server.url.absoluteString == "https://mp.example.test/moviepilot/")
    #expect(server.contains(URL(string: "https://mp.example.test:443/other/#/login")!))
    #expect(!server.contains(URL(string: "https://mp.example.test.evil.test/")!))
    #expect(!server.contains(URL(string: "http://mp.example.test/")!))
    #expect(!server.contains(URL(string: "https://mp.example.test:8443/")!))
  }

  /// 不接受嵌入凭据、会话查询参数、可执行协议及错误地址。
  @Test(arguments: [
    "https://u:p@mp.test/", "https://mp.test/?token=secret", "https://mp.test/#/login",
    "javascript:alert(1)", "file:///tmp/a", "mp.test", "https://", "https://mp.test:0",
    "https://mp.test:70000", "https://mp .test/", "https://mp.test/\nother",
    "http://u:p@mp.test/", "http://mp.test/?token=secret", "http://mp.test/#/login",
  ])
  func rejectsUnsafeConfiguration(input: String) {
    #expect(throws: (any Error).self) { try ServerAddress(input) }
  }

  /// 域名、IPv4 和 IPv6 的本地及公网服务均可显式使用 HTTP。
  @Test(arguments: [
    "127.0.0.1", "10.2.3.4", "172.16.0.1", "172.31.255.254", "192.168.1.2",
    "169.254.2.3", "moviepilot.local", "localhost", "moviepilot", "[::1]", "[fd00::1234]",
    "mp.example.test", "172.15.1.1", "172.32.1.1", "8.8.8.8", "[2001:db8::1]",
  ])
  func allowsHTTP(host: String) throws {
    #expect(try ServerAddress("http://\(host):3000").origin.scheme == "http")
  }

  /// HTTP 标准化后仍只信任精确来源，不将 HTTPS、子域或另一端口视为同一实例。
  @Test func publicHTTPPreservesOrigin() throws {
    let server = try ServerAddress("  HTTP://MP.EXAMPLE.TEST:80/moviepilot  ")
    #expect(server.url.absoluteString == "http://mp.example.test/moviepilot/")
    #expect(server.contains(URL(string: "http://mp.example.test:80/other/")!))
    #expect(!server.contains(URL(string: "https://mp.example.test/")!))
    #expect(!server.contains(URL(string: "http://mp.example.test.evil.test/")!))
    #expect(!server.contains(URL(string: "http://mp.example.test:3000/")!))
  }

  /// 网卡标识不能剥离后伪装成另一来源；旧记录仍可解码，连接前给出浏览器兼容提示。
  @Test(arguments: [
    "http://[fe80::1%25en0]:3000/", "https://[fe80::1%25en0]/",
    "http://[fe80::1%251]:3000/",
  ])
  func identifiesUnsupportedIPv6Scope(input: String) throws {
    let address = try ServerAddress(input)
    #expect(address.webCompatibilityError != nil)
    #expect(address.url.absoluteString == input)
    #expect(!address.contains(URL(string: "http://[fe80::1]:3000/")!))
    #expect(
      try JSONDecoder().decode(ServerAddress.self, from: JSONEncoder().encode(address)) == address)
    #expect(try ServerAddress("http://[fd00::1234]:3000/").webCompatibilityError == nil)
    #expect(try ServerAddress("http://[::1]:3000/").webCompatibilityError == nil)
  }

  /// 从磁盘读取配置仍执行校验，不能通过 Codable 注入一个额外来源。
  @Test(arguments: ["http", "https"])
  func validatesPersistedConfiguration(scheme: String) throws {
    let address = try ServerAddress("\(scheme)://mp.test/base/")
    #expect(
      try JSONDecoder().decode(ServerAddress.self, from: JSONEncoder().encode(address)) == address)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        ServerAddress.self, from: Data("\"\(scheme)://user:password@mp.test/\"".utf8))
    }
  }

  /// 真实回收后 WebKit 可能只返回文档入口，仍须恢复 Vue 最后确认的编码路由。
  @Test func restoresConfirmedHashWithoutChangingDocument() throws {
    let server = try ServerAddress("https://mp.test/base/")
    let document = URL(string: "https://mp.test/base/index.html?theme=dark#/old")!
    let route = "/search?q=%E7%94%B5%E5%BD%B1%2Ftest&source=tmdb"
    let target = server.recoveryURL(currentDocument: document, confirmedRoute: route)
    #expect(target.absoluteString == "https://mp.test/base/index.html?theme=dark#\(route)")
    #expect(server.recoveryURL(currentDocument: document) == document)
    #expect(
      server.recoveryURL(currentDocument: nil, confirmedRoute: "/recommend").absoluteString
        == "https://mp.test/base/#/recommend")
  }

  /// 非同源和含凭据的文档不能成为恢复入口，非法路由不能替换原有 hash。
  @Test func rejectsUnsafeRecoveryTargets() throws {
    let server = try ServerAddress("https://mp.test/base/")
    for reference in [
      "https://evil.test/base/", "http://mp.test/base/", "https://mp.test:8443/",
      "https://user:secret@mp.test/base/", "file:///tmp/index.html",
    ] {
      #expect(server.recoveryURL(currentDocument: URL(string: reference)) == server.url)
    }
    let document = URL(string: "https://mp.test/base/#/recommend")!
    for route in ["//evil.test/path", "https://evil.test/", "/bad\\path", "/bad\npath", "/bad%GG"] {
      #expect(server.recoveryURL(currentDocument: document, confirmedRoute: route) == document)
    }
  }
}
