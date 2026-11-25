import Foundation
import Testing

@testable import MoviePilotPluginUI

/// AppPage 只解析现有导航/模块声明，不把远程 Vue 谎报为 JSON 原生内容。
struct PluginNavigationTests {
  /// 候选名称匹配既有 federationLoader 的大小写、空白和分隔规则。
  @Test(arguments: [
    ("main", ["AppPage", "Page"]), (" MAIN ", ["AppPage", "Page"]),
    ("", ["AppPage", "Page"]), ("settings", ["AppPageSettings", "AppPage", "Page"]),
    (" my_TOOL-test ", ["AppPageMyToolTest", "AppPage", "Page"]),
    ("---", ["AppPage", "Page"]),
  ])
  func preservesAppPageCandidateOrder(_ key: String, _ expected: [String]) throws {
    let input = PluginJSONValue.array([
      .object([
        "plugin_id": .string("Source_fixture"), "nav_key": .string(key), "title": .string("页面"),
        "permission": .string("manage"), "section": .string("future"), "future": .bool(true),
      ])
    ])
    let doc = try PluginNavigationDecoder.appPages(input.encoded())
    let item = try #require(doc.items.first)
    #expect(item.pluginID == "Source_fixture" && item.navigationKey == key)
    #expect(item.remoteComponentCandidates == expected)
    #expect(item.permission == .string("manage"))
    #expect(
      item.raw.object?["section"] == .string("future") && item.raw.object?["future"] == .bool(true))
    #expect(doc.diagnostics.isEmpty)
  }

  /// 非法条目不消失，未知权限保留供权限层拒绝，不能在解析时补授管理员权限。
  @Test func retainsMalformedAndUnknownNavigation() throws {
    let doc = try PluginNavigationDecoder.appPages(
      Data(
        #"[false,{"plugin_id":"Clone","nav_key":"main","title":"页","permission":{"future":true}}]"#
          .utf8))
    #expect(doc.items.count == 2 && doc.items.first?.raw == .bool(false))
    #expect(doc.items[1].permission == .object(["future": .bool(true)]))
    #expect(doc.diagnostics.contains { $0.pointer == "/0/plugin_id" })
    let invalid = try PluginNavigationDecoder.appPages(Data(#"{"success":true,"data":[]}"#.utf8))
    #expect(invalid.diagnostics.first?.code == .invalidRoot)
  }

  /// 元信息的 id 是物理实例，空 key 合法；未知字段和错误项均保留。
  @Test func retainsDashboardIndex() throws {
    let doc = try PluginNavigationDecoder.dashboards(
      Data(
        #"[{"id":"Source_fixture","key":"","name":"统计","source_plugin_id":"Source"},{"key":3}]"#
          .utf8))
    #expect(doc.items.count == 2)
    #expect(doc.items[0].pluginID == "Source_fixture" && doc.items[0].key == "")
    #expect(doc.items[0].raw.object?["source_plugin_id"] == .string("Source"))
    #expect(doc.diagnostics.contains { $0.pointer == "/1/key" })
    #expect(try PluginNavigationDecoder.dashboards(Data("[]".utf8)).items.isEmpty)
    #expect(
      try PluginNavigationDecoder.dashboards(Data("null".utf8)).diagnostics.first?.code
        == .invalidRoot)
  }
}
