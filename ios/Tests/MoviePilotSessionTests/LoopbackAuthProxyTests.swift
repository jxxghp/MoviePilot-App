import Foundation
import Testing

@testable import MoviePilotSession

/// 环回代理测试用的合成上游响应。
private struct LoopbackUpstreamReply: Sendable {
  var status = 200
  var headers: [String: String] = [:]
  var body = Data()
  var redirect: URL?
}

/// 按完整 URL 路由的合成上游；所有状态受锁保护，仅服务本测试套件。
private final class LoopbackUpstreamState: @unchecked Sendable {
  private let lock = NSLock()
  private var replies: [String: LoopbackUpstreamReply] = [:]
  private var captured: [URLRequest] = []

  func reset(_ replies: [String: LoopbackUpstreamReply]) {
    lock.withLock {
      self.replies = replies
      captured = []
    }
  }

  func answer(_ request: URLRequest) -> LoopbackUpstreamReply? {
    lock.withLock {
      captured.append(request)
      return replies[request.url?.absoluteString ?? ""]
    }
  }

  func requests(to url: String) -> [URLRequest] {
    lock.withLock { captured.filter { $0.url?.absoluteString == url } }
  }

  func allRequests() -> [URLRequest] { lock.withLock { captured } }
}

/// 拦截代理的全部上游请求，保证测试不访问外网。
private final class LoopbackUpstreamProtocol: URLProtocol, @unchecked Sendable {
  static let state = LoopbackUpstreamState()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url, let reply = Self.state.answer(request) else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
      return
    }
    if let redirect = reply.redirect,
      let response = HTTPURLResponse(
        url: url, statusCode: 302, httpVersion: "HTTP/1.1",
        headerFields: ["Location": redirect.absoluteString])
    {
      var target = request
      target.url = redirect
      client?.urlProtocol(self, wasRedirectedTo: target, redirectResponse: response)
      return
    }
    guard
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct LoopbackAuthProxyTests {
  private static let credentialHeaders = [
    "Cookie": "synthetic-resource=1",
    "Authorization": "Bearer synthetic.session.token",
    "User-Agent": "SyntheticPlayer/1.0",
  ]

  private func makeProxy(target: String) throws -> (LoopbackAuthProxy, URL) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LoopbackUpstreamProtocol.self]
    let proxy = try LoopbackAuthProxy(
      target: try #require(URL(string: target)), headers: Self.credentialHeaders,
      configuration: configuration)
    return (proxy, try proxy.start())
  }

  private func fetch(_ url: URL, headers: [String: String] = [:], method: String = "GET")
    async throws -> (Data, HTTPURLResponse)
  {
    var request = URLRequest(url: url)
    request.httpMethod = method
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
    return (data, try #require(response as? HTTPURLResponse))
  }

  @Test func rejectsUnsupportedTargetScheme() {
    #expect(throws: LoopbackAuthProxyError.unsupportedTarget) {
      _ = try LoopbackAuthProxy(target: URL(fileURLWithPath: "/tmp/synthetic.mkv"))
    }
  }

  @Test func exposesLoopbackAddressWithoutCredentials() throws {
    LoopbackUpstreamProtocol.state.reset([:])
    let (proxy, local) = try makeProxy(target: "https://example.test/api/stream.mkv?token=secret")
    defer { proxy.close() }
    #expect(local.scheme == "http")
    #expect(local.host == "127.0.0.1")
    #expect(local.pathExtension == "mkv")
    #expect(local.query == nil)
    #expect(!local.absoluteString.contains("secret"))
  }

  @Test func rejectsRequestsWithoutSessionToken() async throws {
    LoopbackUpstreamProtocol.state.reset([:])
    let (proxy, local) = try makeProxy(target: "https://example.test/stream")
    defer { proxy.close() }
    let port = try #require(local.port)
    let forged = try #require(URL(string: "http://127.0.0.1:\(port)/deadbeef/stream"))
    let (_, response) = try await fetch(forged)
    #expect(response.statusCode == 403)
    let (_, post) = try await fetch(local, method: "POST")
    #expect(post.statusCode == 405)
    #expect(LoopbackUpstreamProtocol.state.allRequests().isEmpty)
  }

  @Test func forwardsRangeAndSameOriginCredentials() async throws {
    let target = "https://example.test/stream"
    LoopbackUpstreamProtocol.state.reset([
      target: LoopbackUpstreamReply(
        status: 206,
        headers: [
          "Content-Type": "video/x-matroska", "Content-Length": "4",
          "Content-Range": "bytes 2-5/10",
        ],
        body: Data("2345".utf8))
    ])
    let (proxy, local) = try makeProxy(target: target)
    defer { proxy.close() }
    let (data, response) = try await fetch(local, headers: ["Range": "bytes=2-5"])
    #expect(response.statusCode == 206)
    #expect(String(decoding: data, as: UTF8.self) == "2345")
    #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes 2-5/10")
    #expect(response.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
    #expect(response.value(forHTTPHeaderField: "Content-Type") == "video/x-matroska")

    let upstream = try #require(LoopbackUpstreamProtocol.state.requests(to: target).first)
    #expect(upstream.value(forHTTPHeaderField: "Range") == "bytes=2-5")
    #expect(upstream.value(forHTTPHeaderField: "Cookie") == "synthetic-resource=1")
    #expect(
      upstream.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic.session.token")
    #expect(upstream.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
  }

  @Test func stripsCredentialsOnCrossOriginRedirect() async throws {
    let target = "https://example.test/stream"
    let cdn = "https://cdn.test/media/file.mkv"
    LoopbackUpstreamProtocol.state.reset([
      target: LoopbackUpstreamReply(redirect: URL(string: cdn)),
      cdn: LoopbackUpstreamReply(headers: ["Content-Length": "2"], body: Data("ok".utf8)),
    ])
    let (proxy, local) = try makeProxy(target: target)
    defer { proxy.close() }
    let (data, response) = try await fetch(local)
    #expect(response.statusCode == 200)
    #expect(String(decoding: data, as: UTF8.self) == "ok")

    let redirected = try #require(LoopbackUpstreamProtocol.state.requests(to: cdn).first)
    #expect(redirected.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(redirected.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(redirected.value(forHTTPHeaderField: "User-Agent") == "SyntheticPlayer/1.0")
  }

  @Test func rewritesPlaylistAndRoutesSegmentsThroughProxy() async throws {
    let target = "https://example.test/hls/master.m3u8"
    let sameOriginSegment = "https://example.test/hls/seg1.ts"
    let crossOriginSegment = "https://cdn.test/seg2.ts"
    let key = "https://example.test/hls/key.bin"
    let playlist = [
      "#EXTM3U",
      "#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\",IV=0x1",
      "#EXTINF:4.0,",
      "seg1.ts",
      "#EXTINF:4.0,",
      crossOriginSegment,
      "#EXT-X-ENDLIST",
    ].joined(separator: "\n")
    LoopbackUpstreamProtocol.state.reset([
      target: LoopbackUpstreamReply(
        headers: ["Content-Type": "application/vnd.apple.mpegurl"], body: Data(playlist.utf8)),
      sameOriginSegment: LoopbackUpstreamReply(body: Data("one".utf8)),
      crossOriginSegment: LoopbackUpstreamReply(body: Data("two".utf8)),
      key: LoopbackUpstreamReply(body: Data("key".utf8)),
    ])
    let (proxy, local) = try makeProxy(target: target)
    defer { proxy.close() }
    let (data, response) = try await fetch(local)
    #expect(response.statusCode == 200)
    let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
    #expect(lines.count == 7)
    #expect(response.value(forHTTPHeaderField: "Content-Length") == String(data.count))

    let prefix = "http://127.0.0.1:\(try #require(local.port))/"
    let segmentOne = try #require(URL(string: lines[3]))
    let segmentTwo = try #require(URL(string: lines[5]))
    #expect(lines[3].hasPrefix(prefix) && lines[3].hasSuffix(".ts"))
    #expect(lines[5].hasPrefix(prefix) && lines[5].hasSuffix(".ts"))
    let keyLine = lines[1]
    #expect(keyLine.hasPrefix("#EXT-X-KEY:METHOD=AES-128,URI=\"\(prefix)"))
    #expect(keyLine.hasSuffix(".bin\",IV=0x1"))
    #expect(!String(decoding: data, as: UTF8.self).contains("cdn.test"))

    let (one, _) = try await fetch(segmentOne)
    let (two, _) = try await fetch(segmentTwo)
    #expect(String(decoding: one, as: UTF8.self) == "one")
    #expect(String(decoding: two, as: UTF8.self) == "two")

    let sameOrigin = try #require(
      LoopbackUpstreamProtocol.state.requests(to: sameOriginSegment).first)
    #expect(sameOrigin.value(forHTTPHeaderField: "Cookie") == "synthetic-resource=1")
    let crossOrigin = try #require(
      LoopbackUpstreamProtocol.state.requests(to: crossOriginSegment).first)
    #expect(crossOrigin.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(crossOrigin.value(forHTTPHeaderField: "Authorization") == nil)
  }

  @Test func stopsServingAfterClose() async throws {
    LoopbackUpstreamProtocol.state.reset([
      "https://example.test/stream": LoopbackUpstreamReply(body: Data("ok".utf8))
    ])
    let (proxy, local) = try makeProxy(target: "https://example.test/stream")
    proxy.close()
    try await Task.sleep(nanoseconds: 200_000_000)
    await #expect(throws: (any Error).self) {
      _ = try await fetch(local)
    }
  }
}
