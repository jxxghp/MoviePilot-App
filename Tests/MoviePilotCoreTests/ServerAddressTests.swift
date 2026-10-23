import Foundation
import Testing

@testable import MoviePilotCore

/// 覆盖用户输入、精确来源与本地明文范围的边界。
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
  ])
  func rejectsUnsafeConfiguration(input: String) {
    #expect(throws: (any Error).self) { try ServerAddress(input) }
  }

  /// 本地服务可显式使用 HTTP，公网地址必须使用 HTTPS。
  @Test(arguments: [
    "127.0.0.1", "10.2.3.4", "172.16.0.1", "172.31.255.254", "192.168.1.2",
    "169.254.2.3", "moviepilot.local", "localhost", "moviepilot", "[::1]", "[fd00::1234]",
  ])
  func allowsLocalHTTP(host: String) throws {
    #expect(try ServerAddress("http://\(host):3000").origin.scheme == "http")
  }

  /// 私网判断不被相似前缀、域名后缀和越界地址绕过。
  @Test(arguments: [
    "mp.example.test", "192.168.1.2.evil.test", "172.15.1.1", "172.32.1.1", "8.8.8.8",
    "192.168.1.999", "moviepilot.local.evil.test", "[2001:db8::1]",
  ])
  func rejectsPublicHTTP(host: String) {
    #expect(throws: (any Error).self) { try ServerAddress("http://\(host)/") }
  }

  /// 从磁盘读取配置仍执行校验，不能通过 Codable 注入一个额外来源。
  @Test func validatesPersistedConfiguration() throws {
    let address = try ServerAddress("https://mp.test/base/")
    #expect(
      try JSONDecoder().decode(ServerAddress.self, from: JSONEncoder().encode(address)) == address)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(
        ServerAddress.self, from: Data("\"http://public.example.test/\"".utf8))
    }
  }
}
