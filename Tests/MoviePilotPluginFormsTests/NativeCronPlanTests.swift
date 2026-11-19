import Foundation
import MoviePilotPluginUI
import Testing

@testable import MoviePilotPluginForms

/// Cron 支持必须落到同一个实际 UI/保存计划，不能只增加组件分类。
@Suite @MainActor struct NativeCronPlanTests {
  /// 四个完整官方 get_form 在不删除字段/提示/其它控件的情况下均进入真实原生计划。
  @Test(arguments: ["libraryscraper", "doubanrank", "rsssubscribe", "autoclean"])
  func rendersCompleteCommittedCronForms(_ name: String) throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("MoviePilotPluginUITests/Fixtures/" + name + "-form.json")
    let document = try PluginUIDecoder.decode(Data(contentsOf: url), surface: .form)
    let draft = try PluginFormDraft(document: document)
    let before = try draft.encodedModel()
    let plan = try NativeFormPlan(document: document, draft: draft)
    #expect(plan.issues.isEmpty)
    let cron = plan.groups.flatMap(\.elements).filter {
      if case .cron = $0.control { true } else { false }
    }
    #expect(cron.count == 1)
    #expect(try NativeFormValidator().validate(document: document, draft: draft).isEmpty)
    #expect(try draft.encodedModel() == before)
  }

  /// 数字/空值/缺失值/自定义字符串原样保留，不能把插件间隔统一变成标准 Cron。
  @Test func retainsScalarTypesAndAllowsPluginSpecificValues() throws {
    for value in [
      PluginJSONValue.number(try PluginJSONNumber("6")), .null, .string("6.5"), .string("@daily"),
      .string("0 0 ? * *"),
    ] {
      let document = try decode(value: value)
      let draft = try PluginFormDraft(document: document)
      let before = try draft.encodedModel()
      let plan = try NativeFormPlan(document: document, draft: draft)
      #expect(plan.issues.isEmpty)
      guard case .cron(let field) = plan.groups.first?.elements.first?.control else {
        Issue.record("缺少真实 Cron 控件")
        return
      }
      #expect(field.value == value)
      #expect(field.clearable)
      #expect(try draft.encodedModel() == before)
      #expect(!draft.hasChanges)
    }
    let missing = try decode(value: nil)
    let draft = try PluginFormDraft(document: missing)
    #expect(try NativeFormPlan(document: missing, draft: draft).issues.isEmpty)
    #expect(draft.model.isEmpty)
  }

  /// clearable 默认 true，显式 false/disabled/readonly 与实际控件状态一致。
  @Test func honorsClearableDisabledAndReadonly() throws {
    for property in ["disabled", "readonly"] {
      let document = try decode(
        value: .string("0 9 * * *"), extra: [property: .bool(true), "clearable": .bool(false)])
      let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
      #expect(plan.issues.isEmpty)
      guard case .cron(let field) = plan.groups.first?.elements.first?.control else {
        Issue.record("缺少 Cron 字段")
        return
      }
      #expect(field.disabled)
      #expect(!field.clearable)
    }
  }

  /// 输入结构/必填/长度仍是实际保存门禁，纯字符串方言不会被误报成结构错误。
  @Test func validatesEditableStructureAndRequiredLength() throws {
    for value in [PluginJSONValue.array([]), .object([:])] {
      let document = try decode(value: value)
      #expect(
        try NativeFormPlan(document: document, draft: PluginFormDraft(document: document)).issues
          .contains { $0.code == .invalidValue })
    }
    let required = try decode(value: .null, extra: ["required": .bool(true)])
    #expect(
      try NativeFormPlan(document: required, draft: PluginFormDraft(document: required)).issues
        .contains { $0.code == .requiredValue })
    let limited = try decode(
      value: .string("123"), extra: ["maxlength": .number(try PluginJSONNumber("2"))])
    #expect(
      try NativeFormPlan(document: limited, draft: PluginFormDraft(document: limited)).issues
        .contains { $0.code == .invalidValue })
  }

  /// 未实现行为或不明确输入类型不能因为 Cron 已有 UI 就被忽略并开放保存。
  @Test(arguments: ["onChange", "rules", "type", "unknownBehavior"])
  func blocksUnsupportedCronBehavior(_ key: String) throws {
    let document = try decode(
      value: .string("6"), extra: [key: .string(key == "type" ? "password" : "function() {}")])
    let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
    #expect(plan.issues.contains { $0.code == .unsupported })
    if key == "type" {
      guard case .unsupported = plan.groups.first?.elements.first?.control else {
        Issue.record("不能回退明文输入")
        return
      }
    }
  }

  /// 原始绑定键含点号时仍是一个字段；清除只改变该值，不删掉隐藏/未知配置。
  @Test func clearsOnlyExactBoundFieldAndKeepsFullDraft() throws {
    let document = try decode(value: .string("0 9 * * *"), field: "nested.cron")
    var draft = try PluginFormDraft(document: document)
    try draft.setValue(
      .object(["value": .number(try PluginJSONNumber("9007199254740993"))]), forExactField: "future"
    )
    try draft.setValue(.null, forExactField: "nested.cron")
    #expect(try NativeFormPlan(document: document, draft: draft).issues.isEmpty)
    #expect(draft.value(forExactField: "nested.cron") == .null)
    #expect(draft.value(forExactField: "nested") == nil)
    #expect(
      draft.value(forExactField: "future")?[exactKey: "value"]
        == .number(try PluginJSONNumber("9007199254740993")))
  }

  /// 构造响应仍经过保真编码/实际协议解码，没有为测试直接初始化渲染计划节点。
  private func decode(
    value: PluginJSONValue?, field: String = "cron", extra: [String: PluginJSONValue] = [:]
  ) throws -> PluginUIDocument {
    var props: [String: PluginJSONValue] = ["model": .string(field), "label": .string("执行周期")]
    props.merge(extra) { _, value in value }
    let raw = PluginJSONValue.object([
      "render_mode": .string("vuetify"),
      "conf": .array([.object(["component": .string("VCronField"), "props": .object(props)])]),
      "model": .object(value.map { [field: $0] } ?? [:]),
    ])
    return try PluginUIDecoder.decode(raw.encoded(), surface: .form)
  }
}
