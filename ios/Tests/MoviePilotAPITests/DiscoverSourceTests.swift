import Foundation
import Testing

@testable import MoviePilotAPI

/// 发现源 endpoint 的同源路径、分页和动态 JSON 参数边界测试。
struct DiscoverSourceTests {
  /// 来源列表固定在 /api/v1/discover/source，使用标准 envelope 合同。
  @Test
  func sourceListUsesNativeEndpoint() throws {
    let endpoint = try DiscoverSourceEndpoint.list()
    #expect(endpoint.path == ["discover", "source"])
    #expect(endpoint.responseContract == .envelope)
  }

  /// 插件 query、数组筛选和分页都保留在受控相对 endpoint 中。
  @Test
  func mediaEndpointPreservesFiltersAndPage() throws {
    let source = try source(
      """
      {"name":"IMDb","media_source":"imdb","mediaid_prefix":"imdb","api_path":"plugin/IMDbSource/imdb_discover?apikey=test-value&page=99","filter_params":{"mtype":"movies","country":["US","CN"],"enabled":true},"filter_ui":[]}
      """
    )
    let endpoint = try DiscoverSourceEndpoint.media(from: source, page: 3)
    #expect(endpoint.path == ["plugin", "IMDbSource", "imdb_discover"])
    #expect(endpoint.query.contains(URLQueryItem(name: "apikey", value: "test-value")))
    #expect(endpoint.query.contains(URLQueryItem(name: "country[]", value: "US")))
    #expect(endpoint.query.contains(URLQueryItem(name: "country[]", value: "CN")))
    #expect(endpoint.query.filter { $0.name == "page" } == [URLQueryItem(name: "page", value: "3")])
  }

  /// 外站绝对 URL、路径逃逸和含片段地址必须拒绝，不能把认证请求交给插件来源。
  @Test(arguments: [
    "https://evil.example/media",
    "/api/v1/discover",
    "plugin/../admin",
    "plugin/source#fragment",
  ])
  func mediaEndpointRejectsUnsafePath(_ apiPath: String) throws {
    let source = DiscoverSource(
      name: "unsafe", mediaSource: nil, mediaIDPrefix: "unsafe", apiPath: apiPath,
      filterParameters: nil, filterUI: nil, depends: nil)
    #expect(throws: DiscoverSourceEndpointError.invalidSourcePath) {
      try DiscoverSourceEndpoint.media(from: source, page: 1)
    }
  }

  /// 解码未知 filter_ui 节点时保留原始 JSON，避免前端生态字段被静默删除。
  @Test
  func sourceDecodesDynamicUIWithoutExecutingIt() throws {
    let source = try source(
      """
      {"name":"Source","media_source":"source","mediaid_prefix":"source","api_path":"plugin/Source/list","filter_params":{"kind":"movie"},"filter_ui":[{"component":"VChipGroup","props":{"model":"kind"},"content":[{"component":"VChip","props":{"value":"movie"},"text":"电影"}]}],"depends":{"year":["kind"]}}
      """
    )
    guard case .object(let firstUI)? = source.filterUI?.first else {
      Issue.record("filter_ui node must be retained as a JSON object")
      return
    }
    #expect(firstUI["component"] == .string("VChipGroup"))
    #expect(source.depends == ["year": ["kind"]])
  }

  /// 测试夹具只包含合成来源，避免将真实后端地址、令牌或用户筛选写入仓库。
  private func source(_ json: String) throws -> DiscoverSource {
    try JSONDecoder().decode(DiscoverSource.self, from: Data(json.utf8))
  }

  /// 插件动态推荐榜单来源列表固定走 `/api/v1/recommend/source`。
  @Test
  func recommendSourceListUsesExpectedPath() throws {
    let endpoint = try RecommendSourceEndpoint.list()
    #expect(endpoint.path == ["recommend", "source"])
    #expect(endpoint.responseContract == .payload)
  }

  /// 插件推荐榜单支持带查询参数的相对路径与翻页覆盖，且首页保留原查询参数。
  @Test
  func recommendSourceMediaEndpointSupportsPluginPathAndPagination() throws {
    let decoded = try JSONDecoder().decode(
      RecommendSource.self,
      from: Data(
        #"{"name":"IMDb Sci-Fi","api_path":"plugin/ImdbSource/trending?interest=Sci-Fi","type":"Rankings"}"#
          .utf8)
    )
    #expect(decoded.name == "IMDb Sci-Fi")
    #expect(decoded.type == "Rankings")

    let firstPage = try RecommendSourceEndpoint.media(apiPath: decoded.apiPath)
    #expect(firstPage.path == ["plugin", "ImdbSource", "trending"])
    #expect(firstPage.query == [URLQueryItem(name: "interest", value: "Sci-Fi")])

    let secondPage = try RecommendSourceEndpoint.media(apiPath: decoded.apiPath, page: 2)
    #expect(secondPage.path == ["plugin", "ImdbSource", "trending"])
    #expect(
      secondPage.query == [
        URLQueryItem(name: "interest", value: "Sci-Fi"),
        URLQueryItem(name: "page", value: "2"),
      ])
  }

  /// 外部域名、协议相对路径、锚点与目录穿越一律拒绝。
  @Test(arguments: [
    "https://evil.example/recommend",
    "//evil.example/recommend",
    "plugin/../system/env",
    "plugin/ImdbSource/trending#frag",
  ])
  func recommendSourceMediaRejectsUnsafePaths(_ unsafePath: String) throws {
    #expect(throws: DiscoverSourceEndpointError.invalidSourcePath) {
      try RecommendSourceEndpoint.media(apiPath: unsafePath, page: 1)
    }
  }
}
