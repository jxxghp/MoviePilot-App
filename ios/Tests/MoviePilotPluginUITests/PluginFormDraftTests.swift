import Foundation
import Testing

@testable import MoviePilotPluginUI

/// 草稿验证完整模型/精确字段与原子编辑，不把动态 UI 尚未实现的能力当作可保存。
struct PluginFormDraftTests {
  /// 固定官方源码派生表单的全部默认/隐藏配置进入草稿，编辑不缩减真实模型。
  @Test func preservesSourceDerivedConfiguration() throws {
    let url = try #require(
      Bundle.module.url(
        forResource: "autosignin-form", withExtension: "json", subdirectory: "Fixtures"))
    let document = try PluginUIDecoder.decode(Data(contentsOf: url), surface: .form)
    var draft = try PluginFormDraft(document: document)
    let original = try #require(document.model)
    try draft.setValue(.bool(true), forExactField: "enabled")
    let saved = try #require(PluginJSONReader.parse(draft.encodedModel()).object)
    for (key, value) in original where key != "enabled" {
      #expect(saved[key] == value)
    }
    #expect(saved.count >= original.count)
  }
  /// 后端返回的隐藏项、未知嵌套值与大数在编辑一个开关后仍保持原始类型和数字词法。
  @Test func preservesTheWholeModelDuringEdits() throws {
    var draft = try make(
      #"{"nested.key":false,"hidden":{"v":null},"big":9007199254740993,"ratio":1.2300,"items":[true,"a",-0]}"#
    )
    try draft.setValue(.bool(true), forExactField: "nested.key")
    let result = try PluginJSONReader.parse(draft.encodedModel())
    #expect(result[exactKey: "nested.key"] == .bool(true))
    #expect(result[exactKey: "nested"] == nil)
    #expect(result[exactKey: "big"] == .number(try PluginJSONNumber("9007199254740993")))
    #expect(result[exactKey: "ratio"] == .number(try PluginJSONNumber("1.2300")))
    #expect(result[exactKey: "hidden"] == .object(["v": .null]))
    #expect(draft.hasChanges)
    draft.markSaved()
    #expect(!draft.hasChanges)
    try draft.setValue(.string("changed"), forExactField: "nested.key")
    draft.reset()
    #expect(draft.value(forExactField: "nested.key") == .bool(true) && !draft.hasChanges)
  }

  /// Swift 规范等价键不能覆盖另一原始键，字符串值的字节变化则必须被识别为修改。
  @Test func handlesUnicodeKeysAndValuesExactly() throws {
    var draft = try make("{\"é\":1,\"name\":\"é\"}")
    let revision = draft.revision
    #expect(draft.value(forExactField: "e\u{301}") == nil)
    #expect(throws: PluginFormDraftError.conflictingField) {
      try draft.setValue(.bool(true), forExactField: "e\u{301}")
    }
    #expect(draft.revision == revision && !draft.hasChanges)
    try draft.setValue(.string("e\u{301}"), forExactField: "name")
    #expect(draft.hasChanges && draft.revision != revision)
    let data = try draft.encodedModel()
    #expect(data.range(of: Data("e\u{301}".utf8)) != nil)
    draft.reset()
    #expect(!draft.hasChanges)
  }

  /// 相同输入不生成假修改；缺省键可显式补入，null/布尔/字符串和数组仍不自动转型。
  @Test func keepsTypeAndMissingValueSemantics() throws {
    var draft = try make(#"{"flag":false,"empty":null}"#)
    let revision = draft.revision
    try draft.setValue(.bool(false), forExactField: "flag")
    #expect(!draft.hasChanges && draft.revision == revision)
    try draft.setValue(.string("false"), forExactField: "flag")
    try draft.setValue(.array([.null, .bool(false)]), forExactField: "")
    #expect(draft.value(forExactField: "flag") == .string("false"))
    #expect(draft.value(forExactField: "") == .array([.null, .bool(false)]))
    #expect(draft.value(forExactField: "empty") == .null)
  }

  /// 越界更新不能留下半个模型或推进代次，调用方仍可继续编辑原草稿。
  @Test func rollsBackOversizedCandidates() throws {
    let limits = try PluginJSONLimits(
      maximumBytes: 64, maximumDepth: 4, maximumValues: 10, maximumStringBytes: 48,
      maximumNumberBytes: 8)
    let document = try PluginUIDecoder.decode(
      Data(#"{"render_mode":"vuetify","conf":[],"model":{"value":"ok"}}"#.utf8), surface: .form)
    var draft = try PluginFormDraft(document: document, limits: limits)
    let data = try draft.encodedModel()
    let revision = draft.revision
    #expect(throws: PluginJSONError.self) {
      try draft.setValue(.string(String(repeating: "x", count: 49)), forExactField: "value")
    }
    #expect(throws: PluginFormDraftError.invalidField) {
      try draft.setValue(.null, forExactField: String(repeating: "x", count: 1025))
    }
    #expect(try draft.encodedModel() == data && draft.revision == revision && !draft.hasChanges)
  }

  /// Vue、其它表面与缺失模型不能成为可编辑的空配置；描述也不会输出秘密值。
  @Test func rejectsInvalidDocumentsAndRedactsDraftDescriptions() throws {
    for raw in [
      #"{"render_mode":"vue","model":{}}"#, #"{"render_mode":"vuetify","conf":[]}"#, #"{}"#,
    ] {
      let document = try PluginUIDecoder.decode(Data(raw.utf8), surface: .form)
      #expect(throws: PluginFormDraftError.invalidDocument) {
        try PluginFormDraft(document: document)
      }
    }
    let page = try PluginUIDecoder.decode(
      Data(#"{"render_mode":"vuetify","page":[]}"#.utf8), surface: .page)
    #expect(throws: PluginFormDraftError.invalidDocument) { try PluginFormDraft(document: page) }
    let draft = try make(#"{"token":"synthetic-private-value"}"#)
    #expect(!String(describing: draft).contains("synthetic-private-value"))
    #expect(!String(reflecting: draft).contains("synthetic-private-value"))
  }

  /// 已取消编辑/编码不能再生成可发送的模型。
  @Test func observesCancellation() async throws {
    let original = try make(#"{"flag":false}"#)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      var draft = original
      #expect(throws: CancellationError.self) {
        try draft.setValue(.bool(true), forExactField: "flag")
      }
      #expect(throws: CancellationError.self) { try draft.encodedModel() }
      #expect(!draft.hasChanges)
    }
    await task.value
  }

  /// 独立构造合法原生文档，不用产品 JSON 编码器生成输入来镜像自身实现。
  private func make(_ model: String) throws -> PluginFormDraft {
    try PluginFormDraft(
      document: PluginUIDecoder.decode(
        Data("{\"render_mode\":\"vuetify\",\"conf\":[],\"model\":\(model)}".utf8), surface: .form))
  }
}
