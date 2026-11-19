import Foundation
import Testing

@testable import MoviePilotPluginUI

/// 真实源码派生夹具与合成边界共同验证，不把能解析当成已能原生渲染。
struct PluginUIDecoderTests {
  /// 完整表单来自只读 AST：模型、原始响应、未知值和每个绑定字段均保留。
  @Test func readsSourceDerivedForm() throws {
    let data = try fixture("autosignin-form")
    let document = try PluginUIDecoder.decode(data, surface: .form)
    #expect(document.renderMode == .vuetify && document.isStructurallyValid)
    #expect(document.rawData == data && document.nodes.count == 1)
    #expect(document.value(forExactModelField: "enabled") == .bool(false))
    #expect(document.value(forExactModelField: "queue_cnt") == .number(try .init("5")))
    let nodes = flattened(document.nodes)
    #expect(nodes.contains { $0.component == "VSwitch" })
    #expect(nodes.flatMap(\.bindings).contains { $0.field == "sign_sites" })
    #expect(nodes.allSatisfy { $0.pointer.hasPrefix("/conf/0") })
  }

  /// 编辑器仍标记为待实现组件，modelvalue 的 value 更新语义不能丢失。
  @Test func readsEditorBindingWithoutClaimingRenderer() throws {
    let document = try PluginUIDecoder.decode(fixture("autosports-editor"), surface: .form)
    let node = try #require(document.nodes.first)
    #expect(node.family == .editor)
    #expect(node.bindings.first?.field == "competitions_config")
    #expect(node.bindings.first?.kind == .value)
    #expect(document.requirements.contains(.component("VAceEditor")))
    #expect(node.properties["theme"] == .string("monokai"))
  }

  /// 原插件的 JS 按钮仅作为数据识别，绝不尝试运行确认框/访问 API。
  @Test func diagnosesSourceScriptHandler() throws {
    let data = try fixture("certmanager-script")
    let document = try PluginUIDecoder.decode(data, surface: .form)
    #expect(document.requirements.contains(.scriptHandler))
    #expect(
      document.diagnostics.contains {
        $0.code == .scriptRequired && $0.pointer == "/conf/0/props/onclick"
      })
    #expect(document.rawData == data)
  }

  /// 实际条件表达式保持字符串，不用临时 JS 引擎把当前值猜成可见性结论。
  @Test func retainsSourceCondition() throws {
    let document = try PluginUIDecoder.decode(fixture("autosubtitle-condition"), surface: .form)
    #expect(document.requirements.contains(.expression))
    #expect(document.nodes.first?.properties["v-show"]?.string != nil)
    #expect(document.diagnostics.contains { $0.code == .expressionRequired })
  }

  /// 数据表的分页、列头和行数据完整保留，不展开为一堆丢类型的文本。
  @Test func retainsSourceTableData() throws {
    let document = try PluginUIDecoder.decode(fixture("animeupscale-table"), surface: .page)
    let node = try #require(document.nodes.first)
    #expect(node.family == .table && node.bindings.isEmpty)
    #expect(node.properties["items-per-page"] == .number(try .init("20")))
    #expect(node.properties["items"]?.array?.first?.object?["progress"] == .number(try .init("0")))
    #expect(node.properties["items"]?.array?.first?.object?["error"] == .null)
  }

  /// 请求声明保留原大小写/参数缺省和旧 GET 投影，不根据 URI 推导当前插件身份。
  @Test func retainsSourceAPIEvent() throws {
    let document = try PluginUIDecoder.decode(fixture("chatgpt-action"), surface: .page)
    let event = try #require(document.nodes.first?.events.first)
    #expect(event.name == "click" && event.declaredMethod == "get")
    #expect(event.legacyWireMethod == "GET" && event.parameters == nil)
    #expect(event.api?.contains("fixture-only-not-a-real-token") == true)
    #expect(document.requirements.contains(.apiAction))
  }

  /// 仪表板保留源/物理实例、布局、刷新配置及图表序列，不误用表单绑定规则。
  @Test func retainsSourceChartAndDashboardMetadata() throws {
    let document = try PluginUIDecoder.decode(fixture("seedstats-chart"), surface: .dashboard)
    let node = try #require(document.nodes.first)
    #expect(node.family == .chart && node.bindings.isEmpty)
    #expect(node.properties["series"]?.array?.count == 1)
    #expect(document.raw.object?["id"] == .string("SeedStats_fixture"))
    #expect(document.raw.object?["source_plugin_id"] == .string("SeedStats"))
    #expect(document.raw.object?["cols"]?.object?["md"] == .number(try .init("6")))
    #expect(document.isStructurallyValid)
  }

  /// 所有绑定别名和字段名的点号均按当前 FormRender 精确处理。
  @Test func parsesAllBindingAliasesAndImplicitReads() throws {
    let document = try decode(
      #"{"render_mode":"vuetify","model":{"a.b":false,"choices":[1],"é":2},"conf":[{"component":"VTextField","props":{"model":"a.b","v-model":"a.b","modelvalue":"a.b","model:checked":"a.b","v-model:search":"a.b","model:x:y":"a.b","items":"choices","label":"固定标签","modelValue":"choices","title":"é","text":" {{x}} ","hint":"{{a.b}}"}}]}"#
    )
    let node = try #require(document.nodes.first)
    let map = Dictionary(uniqueKeysWithValues: node.bindings.map { ($0.property, $0.kind) })
    #expect(map["model"] == .modelValue && map["v-model"] == .modelValue)
    #expect(map["modelvalue"] == .value && map["model:checked"] == .named("checked"))
    #expect(map["v-model:search"] == .named("search") && map["model:x:y"] == .named("x"))
    #expect(map["items"] == .implicitRead && map["modelValue"] == .implicitRead)
    #expect(map["label"] == nil && map["title"] == nil && map["text"] == nil)
    #expect(document.value(forExactModelField: "a.b") == .bool(false))
    #expect(document.value(forExactModelField: "e\u{301}") == nil)
    #expect(document.requirements.contains(.expression))
  }

  /// 相同节点在不同表面不能凭空获得表单表达式和 API 事件执行能力。
  @Test func distinguishesSurfaceSemantics() throws {
    let node =
      #"{"component":"VBtn","props":{"model":"enabled","v-show":"enabled","title":"{{enabled}}","onClick":"function(){}"},"events":{"click":{"api":"plugin/Source/run","method":"DELETE","params":null}}}"#
    let form = try decode(
      #"{"render_mode":"vuetify","model":{"enabled":true},"conf":["# + node + "]}")
    let page = try decode(#"{"render_mode":"vuetify","page":["# + node + "]}", surface: .page)
    let dashboard = try decode(#"{"elements":["# + node + "]}", surface: .dashboard)
    #expect(form.nodes.first?.bindings.count == 1)
    #expect(form.requirements.contains(.expression) && form.requirements.contains(.scriptHandler))
    #expect(!form.requirements.contains(.apiAction))
    #expect(page.nodes.first?.bindings.isEmpty == true && !page.requirements.contains(.expression))
    #expect(page.requirements.contains(.apiAction) && !dashboard.requirements.contains(.apiAction))
    #expect(page.nodes.first?.events.first?.declaredMethod == "DELETE")
    #expect(page.nodes.first?.events.first?.legacyWireMethod == "POST")
    #expect(page.nodes.first?.events.first?.parameters == .null)
    #expect(dashboard.diagnostics.contains { $0.code == .legacyIgnored })
  }

  /// 缺字段/非法模式与合法空界面分开，失败响应不能被误显示为“没有可配置项”。
  @Test func distinguishesEmptyInvalidRemoteAndAbsent() throws {
    let empty = try decode(#"{"render_mode":"vuetify","conf":[],"model":{}}"#)
    #expect(empty.isStructurallyValid && empty.nodes.isEmpty)
    for input in [
      "{}", #"{"render_mode":"legacy","conf":[],"model":{}}"#,
      #"{"render_mode":"vuetify","conf":null,"model":{}}"#,
      #"{"render_mode":"vuetify","conf":[],"model":[]}"#,
    ] {
      #expect(try !decode(input).isStructurallyValid)
    }
    let remote = try decode(
      #"{"render_mode":"vue","conf":null,"model":{"unknown":9007199254740993}}"#)
    #expect(remote.isStructurallyValid && remote.renderMode == .vue && remote.nodes.isEmpty)
    #expect(remote.requirements == [.remoteModule])
    #expect(try decode("null", surface: .dashboard).renderMode == .absent)
    #expect(try decode("null", surface: .page).renderMode == .invalid)
    #expect(try decode(#"{"elements":[]}"#, surface: .dashboard).renderMode == .vuetify)
    #expect(
      try !decode(#"{"render_mode":"legacy","elements":[]}"#, surface: .dashboard)
        .isStructurallyValid)
  }

  /// response envelope 不猜测；模型中的 success/data 也是普通插件配置。
  @Test func neverUnwrapsPluginOwnedFields() throws {
    let document = try decode(
      #"{"render_mode":"vuetify","conf":[],"model":{"success":false,"data":{"enabled":true}},"future":{"revision":2}}"#
    )
    #expect(document.value(forExactModelField: "success") == .bool(false))
    #expect(document.raw.object?["future"] != nil)
    let envelope = #"{"success":true,"data":{"render_mode":"vuetify","conf":[],"model":{}}}"#
    #expect(try !decode(envelope).isStructurallyValid)
    #expect(try PluginJSONReader.parse(document.raw.encoded()) == document.raw)
  }

  /// 单节点/数组槽、未知节点、HTML 与原始扩展值均有结构位置和原文。
  @Test func indexesSlotsUnknownNodesAndHTML() throws {
    let input =
      #"{"render_mode":"vuetify","model":{},"conf":[{"component":"VCard","future":3,"slots":{"a/b~c":[{"component":"ThirdPartyGrid","props":{"opaque":{"a":1}}}],"title":{"component":"span","text":"标题"}},"content":[{"component":"style","text":".x{}"},{"component":"div","html":"<b>说明</b>"}]}]}"#
    let document = try decode(input)
    let node = try #require(document.nodes.first)
    #expect(node.slots.first?.nodes.first?.pointer == "/conf/0/slots/a~1b~0c/0")
    #expect(node.children[1].html == .string("<b>说明</b>"))
    #expect(node.raw.object?["future"] == .number(try .init("3")))
    #expect(document.requirements.contains(.namedSlots) && document.requirements.contains(.html))
    #expect(document.diagnostics.contains { $0.code == .unknownComponent })
    #expect(document.diagnostics.contains { $0.code == .webComponentRequired })
    #expect(node.slots[0].nodes[0].family == .unknown)
  }

  /// 非对象节点和非法绑定/事件仍保留，但结构报告必须失败。
  @Test func reportsMalformedNodesAtExactPointers() throws {
    let input =
      #"{"render_mode":"vuetify","model":{},"conf":[null,{"props":{},"component":""},{"component":"VTextField","props":{"model":true,"model:":"x","v-if":"x"},"content":{},"slots":{"x":false},"events":{"click":{"api":4,"method":""}}}]}"#
    let document = try decode(input)
    #expect(!document.isStructurallyValid && document.nodes.count == 3)
    let paths = Set(document.diagnostics.map(\.pointer))
    for path in [
      "/conf/0", "/conf/1/component", "/conf/2/props/model", "/conf/2/props/model:",
      "/conf/2/props/v-if", "/conf/2/content", "/conf/2/slots/x", "/conf/2/events/click",
    ] {
      #expect(paths.contains(path))
    }
    #expect(document.nodes.first?.raw == .null)
  }

  /// 节点预算包括槽，越界整体抛错，不能返回看似有效的截断表单。
  @Test func boundsNodesAndChecksCancellation() async throws {
    let data = Data(
      #"{"render_mode":"vuetify","model":{},"conf":[{"component":"div","slots":{"x":{"component":"span"}}}]}"#
        .utf8)
    #expect(throws: PluginUIDecodingError.nodeLimitExceeded(pointer: "/conf/0/slots/x")) {
      try PluginUIDecoder.decode(data, surface: .form, maximumNodes: 1)
    }
    #expect(throws: PluginUIDecodingError.invalidNodeLimit) {
      try PluginUIDecoder.decode(data, surface: .form, maximumNodes: 0)
    }
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PluginUIDecoder.decode(data, surface: .form)
    }
    do {
      _ = try await task.value
      Issue.record("取消解析未生效")
    } catch is CancellationError {}
  }

  /// 兼容已有可空内容/仪表板，DOM innerHTML 不能漏过 HTML 能力诊断。
  @Test func preservesOptionalNullsAndInnerHTMLRequirements() throws {
    let page = try decode(
      #"{"render_mode":"vuetify","page":[{"component":"div","props":{"innerHTML":"<b>说明</b>"},"content":null,"events":null}]}"#,
      surface: .page)
    #expect(page.isStructurallyValid && page.nodes.first?.children.isEmpty == true)
    #expect(page.requirements.contains(.html))
    #expect(page.diagnostics.contains { $0.pointer == "/page/0/props/innerHTML" })
    let dashboard = try decode(#"{"elements":null}"#, surface: .dashboard)
    #expect(dashboard.isStructurallyValid && dashboard.nodes.isEmpty)
    #expect(dashboard.raw.object?["elements"] == .null)
    #expect(dashboard.diagnostics.first?.pointer == "/elements")
  }

  /// 有限 JSON 仍可能用长槽名前缀放大路径内存，单键/单路径/总量都须受限。
  @Test func boundsPathExpansion() throws {
    let leaf: PluginJSONValue = .object(["component": .string("div")])
    let hugeName: PluginJSONValue = .object([
      "component": .string("div"), "slots": .object([String(repeating: "s", count: 1025): leaf]),
    ])
    var deep = leaf
    for _ in 0..<5 {
      deep = .object([
        "component": .string("div"), "slots": .object([String(repeating: "s", count: 900): deep]),
      ])
    }
    let wide: PluginJSONValue = .object([
      "component": .string("div"),
      "slots": .object([
        String(repeating: "s", count: 1024): .array(Array(repeating: leaf, count: 3000))
      ]),
    ])
    for node in [hugeName, deep, wide] {
      let payload: PluginJSONValue = .object([
        "render_mode": .string("vuetify"), "model": .object([:]), "conf": .array([node]),
      ])
      #expect(throws: PluginUIDecodingError.pathLimitExceeded) {
        try PluginUIDecoder.decode(payload.encoded(), surface: .form)
      }
    }
  }

  /// 多个插件并发解码不共享模型、绑定或能力集合。
  @Test func keepsConcurrentDocumentsIndependent() async throws {
    try await withThrowingTaskGroup(of: Int.self) { group in
      for index in 0..<20 {
        group.addTask {
          let field = "field\(index)"
          let payload: PluginJSONValue = .object([
            "render_mode": .string("vuetify"), "model": .object([field: .string(String(index))]),
            "conf": .array([
              .object([
                "component": .string("VTextField"), "props": .object(["model": .string(field)]),
              ])
            ]),
          ])
          let document = try PluginUIDecoder.decode(payload.encoded(), surface: .form)
          #expect(document.value(forExactModelField: field) == .string(String(index)))
          #expect(document.nodes.first?.bindings.first?.field == field)
          #expect(document.model?.count == 1)
          return index
        }
      }
      var results = Set<Int>()
      for try await result in group { results.insert(result) }
      #expect(results.count == 20)
    }
  }

  /// 包资源不依赖其它仓库、插件宿主或真实账号。
  private func fixture(_ name: String) throws -> Data {
    try Data(
      contentsOf: #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
  }

  /// 合成协议片段仍走同一个公开入口，不注入已经归一化的成功对象。
  private func decode(_ json: String, surface: PluginUISurface = .form) throws -> PluginUIDocument {
    try PluginUIDecoder.decode(Data(json.utf8), surface: surface)
  }

  /// 测试遍历结构索引而非假设每种插件只有一层。
  private func flattened(_ nodes: [PluginUINode]) -> [PluginUINode] {
    nodes.flatMap { [$0] + flattened($0.children) + $0.slots.flatMap { flattened($0.nodes) } }
  }
}
