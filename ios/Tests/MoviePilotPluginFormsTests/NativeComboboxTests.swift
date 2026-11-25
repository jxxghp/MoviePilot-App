import Foundation
import MoviePilotPluginUI
import Testing

@testable import MoviePilotPluginForms

/// 组合框使用实际计划/共享草稿验收，不能把对象预设降格为只有标题的普通选择。
@Suite @MainActor
struct NativeComboboxTests {
  /// 独立语料直接来自实际 Vuetify 3.7.3 模块，避免 Swift 自己的预期重复实现错误。
  @Test func matchesPinnedVuetifyValueCorpus() throws {
    let url = try #require(
      Bundle.module.url(
        forResource: "combobox-vuetify-3.7.3", withExtension: "json", subdirectory: "Fixtures"))
    let corpus = try PluginJSONReader.parse(Data(contentsOf: url))
    let cases = try #require(corpus[exactKey: "cases"]?.array)
    #expect(cases.count == 365)
    for (index, entry) in cases.enumerated() {
      let properties = try #require(entry[exactKey: "properties"]?.object)
      var draft = try NativeComboboxDraft(properties: properties, value: entry[exactKey: "current"])
      #expect(
        draft.selected.map(\.title)
          == entry[exactKey: "initialTitles"]?.array?.compactMap(\.string), "initial \(index)")
      for operation in entry[exactKey: "operations"]?.array ?? [] {
        let item = Int(operation[exactKey: "index"].flatMap(NativeFormExpression.text) ?? "") ?? 0
        switch operation[exactKey: "kind"]?.string {
        case "choose": draft.choose(item)
        case "custom": draft.addCustom(operation[exactKey: "text"]?.string ?? "")
        case "remove": draft.remove(at: item)
        case "clear": draft.clear()
        default: Issue.record("未知语料动作")
        }
      }
      #expect(draft.value == entry[exactKey: "expected"], "value \(index)")
      #expect(draft.hasChanges == (entry[exactKey: "changed"] == .bool(true)), "changes \(index)")
      #expect(
        draft.selected.map(\.title) == entry[exactKey: "finalTitles"]?.array?.compactMap(\.string),
        "titles \(index)")
    }
  }

  /// 两个真实节点完整进入原生 UI；证书管理完整表单仍因 JS 按钮明确禁存。
  @Test func plansRealSourceNodesWithoutWeakeningWholeFormGate() throws {
    for name in ["certmanager-combobox-node", "libraryintegrity-combobox-node"] {
      let document = try source(name)
      let model = try PluginFormDraft(document: document)
      let original = try model.encodedModel()
      let plan = try NativeFormPlan(document: document, draft: model)
      #expect(plan.issues.isEmpty)
      #expect(try NativeFormValidator().validate(document: document, draft: model).isEmpty)
      guard case .combobox(_, let combo) = plan.groups.first?.elements.first?.control else {
        Issue.record("缺少真实原生组合框")
        return
      }
      #expect(!combo.hasChanges)
      #expect(try model.encodedModel() == original)
      if name.hasPrefix("certmanager") {
        #expect(combo.options.count == 14)
        #expect(!combo.multiple)
      } else {
        #expect(combo.options.isEmpty)
        #expect(combo.multiple && combo.clearable)
      }
    }
    let document = try source("certmanager-form")
    let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
    #expect(
      plan.groups.flatMap(\.elements).contains {
        if case .combobox = $0.control { true } else { false }
      })
    #expect(plan.issues.contains { $0.code == .unsupported && $0.pointer.hasSuffix("/onclick") })
  }

  /// 默认选择保存完整对象；显式关闭 returnObject 才输出 value，标题不决定数据类型。
  @Test(arguments: [true, false])
  func preservesPresetAndCustomOutputTypes(_ returnsObject: Bool) throws {
    let object = item(
      "Cloudflare", .string("dns_cf"), extra: ["future": number("9007199254740993")])
    var draft = try NativeComboboxDraft(
      properties: ["items": .array([object]), "return-object": .bool(returnsObject)], value: .null)
    draft.choose(0)
    #expect(draft.value == (returnsObject ? object : .string("dns_cf")))
    draft.addCustom("Cloudflare")
    #expect(draft.value == .string("Cloudflare"))
    draft.addCustom(" dns_custom \n")
    #expect(draft.value == .string(" dns_custom \n"))
  }

  /// 无操作的 null/缺失/旧标量/旧对象/数组保持确切结构；打开后不能自动归一化。
  @Test(arguments: [false, true])
  func leavesOriginalShapesUntouched(_ multiple: Bool) throws {
    let values: [PluginJSONValue?] = [
      nil, .null, .string("old"), number("6"), .bool(false),
      item("旧对象", .string("legacy"), extra: ["unknown": number("9007199254740993")]),
      .array([.string("old"), .null, number("1e3")]),
    ]
    for value in values {
      let draft = try NativeComboboxDraft(properties: ["multiple": .bool(multiple)], value: value)
      #expect(!draft.hasChanges)
      #expect(draft.value == value)
    }
  }

  /// returnObject=true 的原始字符串不反查同值预设；false 时遵循预设的显示投影。
  @Test(arguments: [true, false])
  func distinguishesCustomStringsFromObjectPresets(_ returnsObject: Bool) throws {
    let preset = item("阿里云", .string("dns_ali"))
    let draft = try NativeComboboxDraft(
      properties: ["returnObject": .bool(returnsObject), "items": .array([preset])],
      value: .string("dns_ali"))
    #expect(draft.selected.first?.title == (returnsObject ? "dns_ali" : "阿里云"))
    #expect(draft.isSelected(draft.options[0]))
    #expect(draft.value == .string("dns_ali"))
  }

  /// 多选仅按实际值切换，保留无关旧对象/精确数字；新增重复自定义值替换并移至末尾。
  @Test func editsMultiSelectionAndUnknownValuesWithoutLosingTypes() throws {
    let old = item("历史对象", .string("legacy"), extra: ["future": number("9007199254740993")])
    var draft = try NativeComboboxDraft(
      properties: ["multiple": .bool(true), "items": .array([.string("A"), .string("B")])],
      value: .array([old, .string("A"), number("9007199254740993")]))
    draft.choose(0)
    #expect(draft.value == .array([old, number("9007199254740993")]))
    draft.addCustom("B")
    draft.addCustom("B")
    #expect(draft.value == .array([old, number("9007199254740993"), .string("B")]))
    draft.remove(at: 0)
    #expect(draft.value == .array([number("9007199254740993"), .string("B")]))
    draft.remove(at: 999)
    #expect(draft.selected.count == 2)
  }

  /// 数字与字符串不同，数值等价可匹配，Unicode 规范等价字符串仍是独立值。
  @Test func comparesExactTypesNumbersAndUnicode() throws {
    var draft = try NativeComboboxDraft(
      properties: [
        "multiple": .bool(true),
        "items": .array([number("1"), .string("1"), .string("é"), .string("e\u{301}")]),
      ], value: .array([number("1.0"), .string("e\u{301}")]))
    #expect(draft.isSelected(draft.options[0]))
    #expect(!draft.isSelected(draft.options[1]))
    #expect(!draft.isSelected(draft.options[2]))
    #expect(draft.isSelected(draft.options[3]))
    draft.choose(1)
    #expect(draft.value?.array?.count == 3)
    draft.choose(2)
    #expect(draft.value?.array?.count == 4)
  }

  /// 直接完整键优先于点路径；方括号和路径数组均按 JSON 结构读取。
  @Test func supportsLiteralDottedAndArrayItemPaths() throws {
    let raw: PluginJSONValue = .object([
      "meta.title": .string("完整键"),
      "meta": .object(["title": .string("嵌套"), "ids": .array([number("42")])]),
    ])
    var draft = try NativeComboboxDraft(
      properties: [
        "items": .array([raw]), "item-title": .string("meta.title"),
        "item-value": .string("meta.ids[0]"), "return-object": .bool(false),
      ], value: nil)
    #expect(draft.options[0].title == "完整键")
    draft.choose(0)
    #expect(draft.value == number("42"))
    draft = try NativeComboboxDraft(
      properties: [
        "items": .array([raw]), "itemTitle": .array([.string("meta"), .string("title")]),
        "itemValue": .array([.string("meta"), .string("ids"), number("0")]),
        "returnObject": .bool(false),
      ], value: nil)
    #expect(draft.options[0].title == "嵌套")
    draft.choose(0)
    #expect(draft.value == number("42"))
  }

  /// 项目 props 标题/值覆盖及 disabled 都作用于真实 UI 和输出，不执行其它项目行为。
  @Test func honorsStandardItemPropsAndDisabled() throws {
    let overridden = item(
      "旧名", .string("old"),
      extra: ["props": .object(["title": .string("新名"), "value": .string("new")])])
    let disabled = item(
      "停用", .string("locked"), extra: ["props": .object(["disabled": .bool(true)])])
    var draft = try NativeComboboxDraft(
      properties: ["return-object": .bool(false), "items": .array([overridden, disabled])],
      value: nil)
    #expect(draft.options[0].title == "新名")
    #expect(draft.options[1].disabled)
    draft.choose(1)
    #expect(!draft.hasChanges)
    draft.choose(0)
    #expect(draft.value == .string("new"))
    draft = try NativeComboboxDraft(properties: ["items": .array([disabled])], value: disabled)
    draft.remove(at: 0)
    #expect(!draft.hasChanges)
  }

  /// 明确清空遵守 clearable，多选 [] 与单选 null 不相混淆。
  @Test(arguments: [true, false])
  func honorsClearabilityAndOutputShape(_ multiple: Bool) throws {
    for clearable in [false, true] {
      var draft = try NativeComboboxDraft(
        properties: ["multiple": .bool(multiple), "clearable": .bool(clearable)],
        value: .string("old"))
      draft.clear()
      #expect(draft.value == (clearable ? (multiple ? .array([]) : .null) : .string("old")))
    }
  }

  /// 默认值缺失字段和完整键按原草稿写入；未来字段及数值词法不受组合框影响。
  @Test func appliesToOnlyExactFieldAndRetainsUnknownWholeModel() throws {
    let document = try make(value: nil, field: "a.b")
    var parent = try PluginFormDraft(document: document)
    try parent.setValue(.object(["integer": number("9007199254740993")]), forExactField: "future")
    let plan = try NativeFormPlan(document: document, draft: parent)
    guard case .combobox(let field, var draft) = plan.groups.first?.elements.first?.control else {
      Issue.record("缺少组合框")
      return
    }
    draft.addCustom("new")
    try parent.setValue(try #require(draft.value), forExactField: field.key)
    #expect(parent.value(forExactField: "a.b") == .string("new"))
    #expect(parent.value(forExactField: "a") == nil)
    #expect(String(decoding: try parent.encodedModel(), as: UTF8.self).contains("9007199254740993"))
    #expect(try NativeFormValidator().validate(document: document, draft: parent).isEmpty)
  }

  /// 必填仍可通过真实输入修复，readonly/disabled 继续体现在实际控件状态。
  @Test func sharesRequiredAndDisabledValidationWithActualPlan() throws {
    let document = try make(value: .null, props: ["required": .bool(true)])
    var draft = try PluginFormDraft(document: document)
    #expect(
      try NativeFormPlan(document: document, draft: draft).issues.contains {
        $0.code == .requiredValue
      })
    try draft.setValue(.string("custom"), forExactField: "value")
    #expect(try NativeFormValidator().validate(document: document, draft: draft).isEmpty)
    for key in ["readonly", "disabled"] {
      let document = try make(value: .null, props: ["required": .bool(true), key: .bool(true)])
      let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
      #expect(plan.issues.isEmpty)
      guard case .combobox(let field, _) = plan.groups.first?.elements.first?.control else {
        continue
      }
      #expect(field.disabled)
    }
  }

  /// 未支持的事件/规则/分隔表达式/比较器，即使控件被隐藏也不能开放局部保存。
  @Test(arguments: [
    "rules", "onChange", "delimiters", "value-comparator", "auto-select-first", "item-props",
  ])
  func blocksHiddenUnsupportedBehavior(_ property: String) throws {
    let document = try make(
      value: .string("old"), props: ["v-show": .string("false"), property: .string("custom")])
    let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
    #expect(plan.groups.isEmpty)
    #expect(plan.issues.contains { $0.code == .unsupported })
  }

  /// 错误 items/别名/路径/项行为明确诊断，限制候选数而非悄悄截断配置。
  @Test func rejectsMalformedOrUnsupportedItemDefinitions() throws {
    #expect(throws: NativeComboboxError.self) {
      try NativeComboboxDraft(
        properties: [:], value: .array(Array(repeating: .string("x"), count: 1001)))
    }
    let properties: [[String: PluginJSONValue]] = [
      ["items": .null], ["items": .array(Array(repeating: .string("x"), count: 1001))],
      ["multiple": .string("false")], ["item-title": .object([:])],
      ["return-object": .bool(true), "returnObject": .bool(false)],
      [
        "items": .array([
          item("x", .string("x"), extra: ["props": .object(["onclick": .string("code")])])
        ])
      ],
      [
        "items": .array([item("x", .string("x"), extra: ["children": .array([.string("nested")])])])
      ],
    ]
    for props in properties {
      let document = try make(value: .string("old"), props: props)
      let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
      #expect(plan.issues.contains { $0.code == .unsupported })
    }
  }

  /// 达到重读上限时仍可替换和删除，新增失败不会污染草稿或丢失已选项。
  @Test func preservesEditableDraftAtSelectionLimit() throws {
    let old: PluginJSONValue = .array((0..<1000).map { .string("old-\($0)") })
    let properties: [String: PluginJSONValue] = [
      "multiple": .bool(true), "items": .array([.string("new"), .string("old-1")]),
    ]
    var draft = try NativeComboboxDraft(properties: properties, value: old)
    let presetAtLimit = draft.choose(0)
    let customAtLimit = draft.addCustom("new")
    #expect(!presetAtLimit)
    #expect(!customAtLimit)
    #expect(!draft.hasChanges)
    #expect(draft.value == old)
    let replacesOld = draft.addCustom("old-0")
    #expect(replacesOld)
    #expect(draft.selected.last?.title == "old-0")
    let removesPreset = draft.choose(1)
    let addsAfterRemoval = draft.addCustom("new")
    #expect(removesPreset)
    #expect(addsAfterRemoval)
    let reloaded = try NativeComboboxDraft(properties: properties, value: draft.value)
    #expect(reloaded.selected.count == 1000)
    #expect(reloaded.selected.last?.title == "new")
  }

  /// 单选投影为数组时，同样不能生成下一次无法展开的配置。
  @Test func preventsOversizedSinglePresetOutput() throws {
    let oversized = PluginJSONValue.array(Array(repeating: .string("x"), count: 1001))
    let preset = item("数组预设", oversized)
    var draft = try NativeComboboxDraft(
      properties: ["items": .array([preset]), "return-object": .bool(false)], value: .string("old"))
    let oversizedChoice = draft.choose(0)
    #expect(!oversizedChoice)
    #expect(draft.value == .string("old"))
    let replacesWithCustom = draft.addCustom("new")
    #expect(replacesWithCustom)
    #expect(draft.value == .string("new"))
  }

  /// 夹具从固定来源派生，路径按源码文件定位而不访问用户实例。
  private func source(_ name: String) throws -> PluginUIDocument {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("MoviePilotPluginUITests/Fixtures/\(name).json")
    return try PluginUIDecoder.decode(Data(contentsOf: url), surface: .form)
  }

  /// 用保真 JSON 建立实际计划的最小文档，nil 表示键不存在。
  private func make(
    value: PluginJSONValue?, field: String = "value", props: [String: PluginJSONValue] = [:]
  ) throws -> PluginUIDocument {
    let props = ["model": PluginJSONValue.string(field), "label": .string("组合框")].merging(props) {
      _, new in new
    }
    return try PluginUIDecoder.decode(
      PluginJSONValue.object([
        "render_mode": .string("vuetify"),
        "conf": .array([.object(["component": .string("VCombobox"), "props": .object(props)])]),
        "model": .object(value.map { [field: $0] } ?? [:]),
      ]).encoded(), surface: .form)
  }

  /// 预设对象允许额外未知数据，借此检查 returnObject 的真实完整载荷。
  private func item(
    _ title: String, _ value: PluginJSONValue, extra: [String: PluginJSONValue] = [:]
  ) -> PluginJSONValue {
    .object(["title": .string(title), "value": value].merging(extra) { _, new in new })
  }

  /// 测试数字直接使用合法 JSON 词法，禁止先经过浮点转换。
  private func number(_ raw: String) -> PluginJSONValue {
    .number(try! PluginJSONNumber(raw))
  }
}
