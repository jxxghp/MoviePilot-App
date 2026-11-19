import Foundation
import MoviePilotCore

@testable import MoviePilotSession

/// 原生认证与会话测试共用的合成数据，不读本机凭据、配置或真实实例。
enum NativeSessionTestData {
  static let login = Data(
    #"{"access_token":"synthetic.session.token","token_type":"bearer","user_id":3,"user_name":"reader","super_user":false,"level":2,"avatar":null,"permissions":{"manage":false,"features":{"search.resource":false}}}"#
      .utf8)
  static let current = Data(
    #"{"id":3,"name":"reader","is_superuser":false,"is_active":true,"avatar":null,"permissions":{"manage":false,"features":{"search.resource":false}}}"#
      .utf8)

  /// 模拟已由 current 接口验证的令牌；冲突的角色声明用于证明客户端不采信它。
  static func token(level: Int = 2) -> String {
    let data = Data(#"{"level":\#(level),"super_user":true,"permissions":{"manage":true}}"#.utf8)
    let claims = data.base64EncodedString().replacingOccurrences(of: "=", with: "")
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return "header.\(claims).signature"
  }

  /// 保留原 payload 结构，测试旧版/新版认证响应，不借用产品解包逻辑。
  static func envelope(_ data: Data, success: Bool = true) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "success": success, "message": "", "data": JSONSerialization.jsonObject(with: data),
    ])
  }

  /// 网络只走自定义协议；故意注入旧头来验证生产认证客户端的清理。
  static func client(address: String = "https://example.test/moviepilot/") throws
    -> NativeAuthenticationClient
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NativeHTTPProtocol.self]
    configuration.httpAdditionalHeaders = [
      "Cookie": "synthetic-old-cookie", "Authorization": "Bearer synthetic-old",
      "X-Old-Account": "synthetic-old",
    ]
    return NativeAuthenticationClient(
      address: try ServerAddress(address), language: .english, configuration: configuration)
  }
}

/// 测试响应只有不可变合成字段，控制跳转、取消和流式上限。
struct NativeHTTPReply: Sendable {
  let status: Int
  let body: Data
  let headers: [String: String]
  let redirect: URL?
  let hold: Bool
  let error: URLError.Code?
}

/// 捕获真实 URLSession 请求以及转为输入流的写入字节。
struct NativeHTTPRequest: Sendable {
  let request: URLRequest
  let body: Data
}

/// 所有全局测试状态都受锁保护，串行网络测试之间显式清空。
final class NativeHTTPState: @unchecked Sendable {
  private let lock = NSLock()
  private var reply = NativeHTTPReply(
    status: 200, body: Data(), headers: [:], redirect: nil, hold: false, error: nil)
  private var captured: [NativeHTTPRequest] = []

  /// 一次只配置一个响应，避免将上一账号的捕获误当成当前测试证据。
  func prepare(
    status: Int = 200, body: Data = Data(),
    headers: [String: String] = ["Content-Type": "application/json"],
    redirect: URL? = nil, hold: Bool = false, error: URLError.Code? = nil
  ) {
    lock.withLock {
      reply = NativeHTTPReply(
        status: status, body: body, headers: headers, redirect: redirect, hold: hold, error: error)
      captured = []
    }
  }

  /// 记录原始请求；未安装拒绝代理的对照客户端会得到真实的第二跳响应。
  func answer(_ request: URLRequest, body: Data) -> NativeHTTPReply {
    lock.withLock {
      captured.append(NativeHTTPRequest(request: request, body: body))
      if request.url == reply.redirect {
        return NativeHTTPReply(
          status: 200, body: reply.body, headers: reply.headers, redirect: nil, hold: false,
          error: nil)
      }
      return reply
    }
  }

  /// 仅返回合成捕获的快照，不向产品日志输出任何请求值。
  func requests() -> [NativeHTTPRequest] { lock.withLock { captured } }
}

/// 拦截全部测试来源，即使错误实现跳往其它域名也不访问外网。
final class NativeHTTPProtocol: URLProtocol, @unchecked Sendable {
  static let state = NativeHTTPState()

  /// 接受本 session 所有请求，以捕获不该发生的第二次发送。
  override class func canInit(with request: URLRequest) -> Bool { true }

  /// 不替产品实现修复路径、身份或编码。
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  /// 通过真实协议回调交付响应，让 URLSessionTaskDelegate 决定是否接受跳转。
  override func startLoading() {
    let reply = Self.state.answer(request, body: Self.body(request))
    if let error = reply.error {
      client?.urlProtocol(self, didFailWithError: URLError(error))
      return
    }
    if reply.hold { return }
    guard let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
    else { return }
    if let redirect = reply.redirect {
      var target = request
      target.url = redirect
      client?.urlProtocol(self, wasRedirectedTo: target, redirectResponse: response)
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  /// 没有夹具自建的后台任务，挂起请求的取消由 URLSession 结束。
  override func stopLoading() {}

  /// 捕获 Foundation 可能转换为输入流的表单体；只消费测试内存数据。
  private static func body(_ request: URLRequest) -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      result.append(contentsOf: buffer.prefix(count))
    }
    return result
  }
}
