import Foundation
import MoviePilotCore

/// 后端发现源声明；动态筛选 JSON 原样保留供独立原生 UI 计划消费。
public struct DiscoverSource: Decodable, Equatable, Sendable, CustomDebugStringConvertible {
  public let name: String
  public let mediaSource: String?
  public let mediaIDPrefix: String
  public let apiPath: String
  public let filterParameters: [String: JSONValue]?
  public let filterUI: [JSONValue]?
  public let depends: [String: [String]]?

  /// API 地址和参数可能带服务凭据；调试描述只显示公开展示名与字段名。
  public var debugDescription: String {
    "DiscoverSource(name: \(String(reflecting: name)), filterKeys: \(filterParameters?.keys.sorted() ?? []))"
  }

  /// 使用后端 snake_case 响应字段解码，不推断媒体来源或筛选默认值。
  enum CodingKeys: String, CodingKey {
    case name
    case mediaSource = "media_source"
    case mediaIDPrefix = "mediaid_prefix"
    case apiPath = "api_path"
    case filterParameters = "filter_params"
    case filterUI = "filter_ui"
    case depends
  }
}

/// 构造同一服务 API 的发现源请求；插件提供的地址永远不能成为外站 URL。
public enum DiscoverSourceEndpoint {
  /// 后端返回已安装插件贡献的来源列表，使用标准 MoviePilot 响应封装。
  public static func list() throws -> APIEndpoint {
    try APIEndpoint(path: ["discover", "source"], responseContract: .envelope)
  }

  /// 来源和筛选只可生成同源 api/v1 相对路径，不接受重定向/自由 URL。
  public static func media(
    from source: DiscoverSource, page: Int, filters: [String: JSONValue]? = nil
  ) throws -> APIEndpoint {
    guard (1...10_000).contains(page), source.apiPath.utf8.count <= 16_384,
      !source.apiPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }
      ),
      let components = URLComponents(string: source.apiPath),
      components.scheme == nil, components.host == nil, components.user == nil,
      components.password == nil, components.port == nil, components.fragment == nil,
      !components.percentEncodedPath.isEmpty, !components.percentEncodedPath.hasPrefix("/"),
      !components.percentEncodedPath.contains("\\")
    else { throw DiscoverSourceEndpointError.invalidSourcePath }

    guard !components.percentEncodedPath.contains("//") else {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }
    let trailingSlash = components.percentEncodedPath.hasSuffix("/")
    let encodedSegments = components.percentEncodedPath.split(separator: "/")
    guard (1...64).contains(encodedSegments.count) else {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }
    let path = try encodedSegments.map { encoded -> String in
      guard let segment = String(encoded).removingPercentEncoding,
        !segment.isEmpty, segment != ".", segment != "..", !segment.contains("/"),
        !segment.contains("\\"), !segment.contains("%"),
        !segment.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { throw DiscoverSourceEndpointError.invalidSourcePath }
      return segment
    }

    let staticQuery = components.queryItems ?? []
    guard staticQuery.count <= 128,
      staticQuery.allSatisfy({ item in
        item.name.utf8.count <= 1024 && (item.value?.utf8.count ?? 0) <= 4096
          && !item.name.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
          })
          && !(item.value ?? "").unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
          })
      })
    else { throw DiscoverSourceEndpointError.invalidSourcePath }

    let filterValues = filters ?? source.filterParameters ?? [:]
    guard filterValues.count <= 256 else {
      throw DiscoverSourceEndpointError.tooManyFilterParameters
    }
    let unindexedArrays =
      filterValues["media_source"].map {
        if case .array = $0 { return true }
        return false
      } ?? false
    // URL 中的静态页码不能和分页器的动态页码并存，否则后端参数解析会因顺序而异。
    var query = staticQuery.filter { $0.name != "page" }
    for key in filterValues.keys.sorted() where key != "page" {
      guard let value = filterValues[key] else { continue }
      try append(value, name: key, unindexedArrays: unindexedArrays, to: &query)
    }
    // 与现有 discover 列表一致，当前分页器覆盖初始 page 参数。
    query.append(URLQueryItem(name: "page", value: String(page)))
    guard query.count <= 512 else { throw DiscoverSourceEndpointError.tooManyFilterParameters }
    do {
      return try APIEndpoint(
        path: path, query: query, responseContract: .envelope, trailingSlash: trailingSlash)
    } catch {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }
  }

  /// Axios 风格数组展开为 key[]，对象编码成 JSON；null 与前端一致省略。
  private static func append(
    _ value: JSONValue, name: String, unindexedArrays: Bool, to query: inout [URLQueryItem]
  ) throws {
    guard name.utf8.count <= 1024,
      !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw DiscoverSourceEndpointError.unsupportedFilterValue }
    switch value {
    case .null:
      return
    case .string(let string):
      guard string.utf8.count <= 16_384 else {
        throw DiscoverSourceEndpointError.unsupportedFilterValue
      }
      query.append(URLQueryItem(name: name, value: string))
    case .number(let number):
      guard number.isFinite else { throw DiscoverSourceEndpointError.unsupportedFilterValue }
      query.append(URLQueryItem(name: name, value: String(number)))
    case .bool(let flag):
      query.append(URLQueryItem(name: name, value: flag ? "true" : "false"))
    case .array(let values):
      guard values.count <= 256 else { throw DiscoverSourceEndpointError.tooManyFilterParameters }
      let arrayName = unindexedArrays ? name : name + "[]"
      for item in values {
        try append(item, name: arrayName, unindexedArrays: unindexedArrays, to: &query)
      }
    case .object:
      let data = try JSONEncoder().encode(value)
      guard data.count <= 16_384, let json = String(data: data, encoding: .utf8) else {
        throw DiscoverSourceEndpointError.unsupportedFilterValue
      }
      query.append(URLQueryItem(name: name, value: json))
    }
  }
}

/// 端点构造错误不携带用户筛选值、来源 URL 或 query 凭据。
public enum DiscoverSourceEndpointError: Error, Equatable, Sendable {
  case invalidSourcePath
  case tooManyFilterParameters
  case unsupportedFilterValue
}

/// 插件通过 `ChainEventType.RecommendSource` 动态注册的推荐榜单来源（`GET /api/v1/recommend/source`）。
public struct RecommendSource: Codable, Equatable, Hashable, Sendable, CustomDebugStringConvertible
{
  public let name: String
  public let apiPath: String
  public let type: String

  public init(name: String, apiPath: String, type: String = "") {
    self.name = name
    self.apiPath = apiPath
    self.type = type
  }

  public var debugDescription: String {
    "RecommendSource(name: \(String(reflecting: name)), type: \(String(reflecting: type)))"
  }

  enum CodingKeys: String, CodingKey {
    case name
    case apiPath = "api_path"
    case type
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.name = try container.decode(String.self, forKey: .name)
    self.apiPath = try container.decode(String.self, forKey: .apiPath)
    self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
  }
}

/// 构造同一服务 API 的插件推荐榜单请求；严格校验相对路径并拒绝任意外部 URL 或目录穿越。
public enum RecommendSourceEndpoint {
  /// 读取当前实例已启用插件贡献的动态推荐榜单列表（`GET /api/v1/recommend/source`）。
  public static func list() throws -> APIEndpoint {
    try APIEndpoint(path: ["recommend", "source"], responseContract: .payload)
  }

  /// 将插件声明的 `api_path` 解析为受控的同源 `/api/v1/` 请求端点。
  public static func media(apiPath: String, page: Int? = nil) throws -> APIEndpoint {
    if let page, !(1...10_000).contains(page) {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }
    let trimmed = apiPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.utf8.count <= 16_384,
      !trimmed.contains("://"), !trimmed.hasPrefix("//"), !trimmed.contains("\\"),
      !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }

    let normalizedInput: String
    if trimmed.hasPrefix("/api/v1/") {
      normalizedInput = String(trimmed.dropFirst("/api/v1/".count))
    } else if trimmed.hasPrefix("api/v1/") {
      normalizedInput = String(trimmed.dropFirst("api/v1/".count))
    } else if trimmed.hasPrefix("/") {
      normalizedInput = String(trimmed.dropFirst())
    } else {
      normalizedInput = trimmed
    }

    guard let components = URLComponents(string: normalizedInput),
      components.scheme == nil, components.host == nil, components.user == nil,
      components.password == nil, components.port == nil, components.fragment == nil,
      !components.percentEncodedPath.isEmpty, !components.percentEncodedPath.hasPrefix("/"),
      !components.percentEncodedPath.contains("//"), !components.percentEncodedPath.contains("\\")
    else {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }

    let trailingSlash = components.percentEncodedPath.hasSuffix("/")
    let encodedSegments = components.percentEncodedPath.split(separator: "/")
    guard (1...64).contains(encodedSegments.count) else {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }
    let path = try encodedSegments.map { encoded -> String in
      guard let segment = String(encoded).removingPercentEncoding,
        !segment.isEmpty, segment != ".", segment != "..",
        !segment.contains("/"), !segment.contains("\\"),
        !segment.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else {
        throw DiscoverSourceEndpointError.invalidSourcePath
      }
      return segment
    }

    let staticQuery = components.queryItems ?? []
    guard staticQuery.count <= 128,
      staticQuery.allSatisfy({ item in
        item.name.utf8.count <= 1024 && (item.value?.utf8.count ?? 0) <= 4096
          && !item.name.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
          })
          && !(item.value ?? "").unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
          })
      })
    else {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }

    var query: [URLQueryItem]
    if let page, page > 1 {
      query = staticQuery.filter { $0.name != "page" }
      query.append(URLQueryItem(name: "page", value: String(page)))
    } else {
      query = staticQuery
    }

    do {
      return try APIEndpoint(
        path: path, query: query, responseContract: .payload, trailingSlash: trailingSlash)
    } catch {
      throw DiscoverSourceEndpointError.invalidSourcePath
    }
  }
}
