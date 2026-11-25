import Foundation

/// 原生 API 的稳定失败分类；不携带服务器正文、地址、凭据或底层网络错误。
public enum APIError: Error, Equatable, Sendable {
  case invalidEndpoint
  case invalidCredential
  case unauthorized
  case forbidden
  case notFound
  case rateLimited(retryAfter: TimeInterval?)
  case httpStatus(Int)
  case redirectRefused
  case cloudflareAccessRequired
  case unavailable
  case timedOut
  case invalidResponse
  case responseTooLarge
  case businessFailure
}

/// 端点显式选择包装协议；不根据插件 payload 恰好出现的 success/data 键猜测。
public enum APIResponseContract: Equatable, Sendable {
  case envelope
  case payload
  case eventStream
  case plainText
}

/// 传输层支持的 HTTP 方法；即使 GET 也可能有旧接口副作用，均不自动重试。
public enum APIMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
  case head = "HEAD"
  case options = "OPTIONS"
}
