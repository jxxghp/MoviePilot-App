import Foundation

/// 后端集合头的原始语义；缺少精确总数时保留 nil，不把本页条数冒充全集大小。
public struct APICollectionMetadata: Equatable, Sendable {
  public let totalCount: Int?
  public let resultCount: Int?
  public let page: Int?
  public let pageSize: Int?

  /// 已提供但不合法的分页头是协议错误，不能静默丢弃后误判列表已完整；兼容 0 基分页端点（如站点资源/标题搜索的 `X-Page: 0`）。
  init(response: HTTPURLResponse) throws {
    totalCount = try Self.integer("X-Total-Count", response: response, minimum: 0)
    resultCount = try Self.integer("X-Result-Count", response: response, minimum: 0)
    page = try Self.integer("X-Page", response: response, minimum: 0)
    pageSize = try Self.integer("X-Page-Size", response: response, minimum: 1)
  }

  /// 只接收 ASCII 十进制整数，拒绝负数、溢出和其它含混的窗口声明。
  private static func integer(
    _ name: String, response: HTTPURLResponse, minimum: Int
  ) throws -> Int? {
    guard let value = response.value(forHTTPHeaderField: name) else { return nil }
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
      let result = Int(value), result >= minimum
    else { throw APIError.invalidResponse }
    return result
  }
}

/// 一次已验证的 JSON 响应；保留业务值、HTTP 状态与独立分页元数据。
public struct APIResult<Value: Sendable>: Sendable {
  public let value: Value
  public let statusCode: Int
  public let collection: APICollectionMetadata
}

/// 普通 MoviePilot 响应的显式解码；业务失败在解码预期数据类型前传播。
struct APIEnvelope<Value: Decodable>: Decodable {
  let value: Value

  /// 固定的服务端响应字段；允许未来添加其它元数据，但不猜测原始插件 payload。
  private enum CodingKeys: String, CodingKey {
    case success, message, data
  }

  /// success=false 不能因为 data 类型与成功模型不同而被误报为 JSON 损坏。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let success = try container.decode(Bool.self, forKey: .success)
    _ = try container.decode(String.self, forKey: .message)
    guard success else { throw APIError.businessFailure }
    value = try container.decode(Value.self, forKey: .data)
  }
}
