import Foundation
import MoviePilotPluginUI
import Testing

@testable import MoviePilotPluginForms

/// 真实渲染计划的组件/绑定/校验边界，不以测试专用空验证器放行。
@Suite @MainActor
struct NativeFormPlanTests {
  /// 整个官方 get_form 原样进入原生计划，包含所有九个字段和六个分组。
  @Test func plansCompleteCommittedMediaDirWatcherForm() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("MoviePilotPluginUITests/Fixtures/mediadirwatcher-form.json")
    let document = try PluginUIDecoder.decode(Data(contentsOf: fixture), surface: .form)
    let draft = try PluginFormDraft(document: document)
    let plan = try NativeFormPlan(document: document, draft: draft)
    #expect(plan.issues.isEmpty)
    #expect(plan.groups.count == 6)
    #expect(plan.groups.flatMap(\.elements).count == 10)
    #expect(try NativeFormValidator().validate(document: document, draft: draft).isEmpty)
    let controls = plan.groups.flatMap(\.elements).map(\.control)
    #expect(controls.filter { if case .toggle = $0 { true } else { false } }.count == 4)
    #expect(controls.filter { if case .select = $0 { true } else { false } }.count == 2)
    #expect(draft.value(forExactField: "scan_interval") == .number(try PluginJSONNumber("5")))
  }

  /// 条件与隐式属性读取响应草稿，隐藏字段未被删掉；数字词法不受计划影响。
  @Test func reevaluatesVisibilityLabelsAndRetainsUnknownModel() throws {
    let nodes: [[String: Any]] = [
      ["component": "VSwitch", "props": ["model": "enabled", "label": "启用"]],
      [
        "component": "VTextField",
        "props": [
          "model": "path.with.dot", "label": "name", "v-show": "{{enabled && mode === 'custom'}}",
        ],
      ],
    ]
    let document = try decode(
      nodes,
      model: [
        "enabled": false, "mode": "custom", "name": "目录", "path.with.dot": "old",
        "hidden": ["future": 42],
      ])
    var draft = try PluginFormDraft(document: document)
    #expect(
      try NativeFormPlan(document: document, draft: draft).groups.flatMap(\.elements).count == 1)
    try draft.setValue(.bool(true), forExactField: "enabled")
    let plan = try NativeFormPlan(document: document, draft: draft)
    #expect(plan.issues.isEmpty)
    guard case .input(let field, _) = plan.groups.flatMap(\.elements).last?.control else {
      Issue.record("缺少原生文本组件")
      return
    }
    #expect(field.key == "path.with.dot")
    #expect(field.label == "目录")
    #expect(
      draft.value(forExactField: "hidden")
        == .object(["future": .number(try PluginJSONNumber("42"))]))
  }

  /// 未支持脚本/槽/HTML/规则/自定义组件在隐藏父节点下仍阻断保存。
  @Test(arguments: [
    "script", "slot", "html", "rules", "component", "style", "class", "named", "layout-binding",
    "expression",
  ])
  func blocksUnsupportedHiddenCapabilities(_ mode: String) throws {
    var child: [String: Any] = [
      "component": "VTextField", "props": ["model": "value", "label": "值"],
    ]
    var props = child["props"] as! [String: Any]
    switch mode {
    case "script": props["onUpdate:modelValue"] = "function(v) { model.x = v }"
    case "slot": child["slots"] = ["append": ["component": "span", "text": "x"]]
    case "html": child["html"] = "<b>x</b>"
    case "rules": props["rules"] = ["required"]
    case "component": child["component"] = "VAceEditor"
    case "style": props["style"] = "display:none"
    case "class": props["class"] = "d-none"
    case "named":
      props.removeValue(forKey: "model")
      props["model:search"] = "value"
    case "expression": props["hint"] = "{{value.includes('x')}}"
    default: break
    }
    child["props"] = props
    var parent: [String: Any] = [
      "component": "VRow", "props": ["v-show": "false"], "content": [child],
    ]
    if mode == "layout-binding" { parent["props"] = ["v-show": "false", "model": "value"] }
    let document = try decode([parent], model: ["value": "unchanged"])
    let draft = try PluginFormDraft(document: document)
    let plan = try NativeFormPlan(document: document, draft: draft)
    #expect(plan.groups.isEmpty)
    #expect(plan.issues.contains { $0.code == .unsupported })
    #expect(try NativeFormValidator().validate(document: document, draft: draft) == plan.issues)
  }

  /// 原始绑定名、旧 modelvalue/value 别名与显式命名值绑定都能编辑完整键。
  @Test(arguments: ["model", "v-model", "modelvalue", "model:value", "v-model:modelValue"])
  func acceptsValueBindingAliases(_ alias: String) throws {
    let document = try decode(
      [["component": "VTextField", "props": [alias: "a.b", "label": "值"]]], model: ["a.b": "ok"])
    let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
    #expect(plan.issues.isEmpty)
    guard case .input(let field, _) = plan.groups.first?.elements.first?.control else {
      Issue.record("缺少输入框")
      return
    }
    #expect(field.key == "a.b")
    #expect(field.text == "ok")
  }

  /// 非法/多个绑定与无可读标签不能伪装为可保存的控件。
  @Test(arguments: [
    ["label": "x"], ["model": "a", "v-model": "b", "label": "x"],
    ["model": "a", "label": ""],
  ])
  func blocksAmbiguousBindings(_ props: [String: String]) throws {
    let document = try decode(
      [["component": "VSwitch", "props": props]], model: ["a": true, "b": false])
    #expect(
      try !NativeFormPlan(document: document, draft: PluginFormDraft(document: document)).issues
        .isEmpty)
  }

  /// 结构层已拒绝的空命名绑定不能绕过解码器建立草稿。
  @Test func rejectsStructurallyInvalidNamedBinding() throws {
    let document = try decode(
      [["component": "VTextField", "props": ["model:": "a", "label": "值"]]], model: ["a": "ok"])
    #expect(!document.isStructurallyValid)
    #expect(throws: PluginFormDraftError.invalidDocument) {
      try PluginFormDraft(document: document)
    }
  }

  /// 旧属性覆盖顺序和非字符串 text 的隐式模型访问尚未实现时必须明确阻断。
  @Test func blocksUnimplementedTextAndVisibilityPrecedence() throws {
    let document = try decode(
      [
        ["component": "VRow", "props": ["show": "true", "v-show": "false"], "content": []],
        ["component": "span", "text": true],
      ], model: [:])
    let plan = try NativeFormPlan(document: document, draft: PluginFormDraft(document: document))
    #expect(plan.issues.contains { $0.pointer == "/conf/0/props/show" })
    #expect(plan.issues.contains { $0.pointer == "/conf/1/text" })
  }

  /// 旧隐式属性读取可能使 type=password 变成模型密码；未知类型不能明文回退。
  @Test(arguments: [PluginJSONValue.string("fixture-only-private"), .bool(false)])
  func neverDisplaysValueForUnconfirmedInputType(_ value: PluginJSONValue) throws {
    let document = try decode(
      [
        [
          "component": "VTextField",
          "props": ["model": "password", "label": "密码", "type": "password"],
        ]
      ], model: ["password": "temporary"])
    var draft = try PluginFormDraft(document: document)
    try draft.setValue(value, forExactField: "password")
    let plan = try NativeFormPlan(document: document, draft: draft)
    #expect(plan.issues.contains { $0.code == .unsupported })
    guard case .unsupported = plan.groups.first?.elements.first?.control else {
      Issue.record("未知类型不应生成明文输入框")
      return
    }
  }

  /// 数字比较不会把 2^53 以上邻接整数舍入为同一个值，编辑后仍为字符串。
  @Test func validatesExactNumericBoundsAndKeepsEditedType() throws {
    let document = try decode(
      [
        [
          "component": "VTextField",
          "props": [
            "model": "n", "label": "数量", "type": "number", "min": "9007199254740993",
            "max": "9007199254740994",
          ],
        ]
      ], model: ["n": "9007199254740992"])
    var draft = try PluginFormDraft(document: document)
    #expect(
      try NativeFormPlan(document: document, draft: draft).issues.contains {
        $0.code == .invalidValue
      })
    try draft.setValue(.string("9007199254740993"), forExactField: "n")
    #expect(try NativeFormPlan(document: document, draft: draft).issues.isEmpty)
    #expect(draft.value(forExactField: "n") == .string("9007199254740993"))
    try draft.setValue(.string("not-a-number"), forExactField: "n")
    #expect(try !NativeFormPlan(document: document, draft: draft).issues.isEmpty)
  }

  /// 必填、UTF-16 长度、控件类型错误可被当前用户修正，旧 v-if 不变成显示指令。
  @Test func validatesRequiredLengthAndTypesWithoutInventingVIf() throws {
    let document = try decode(
      [
        [
          "component": "VTextField",
          "props": [
            "model": "name", "label": "名称", "required": true, "maxlength": 2, "v-if": false,
          ],
        ],
        ["component": "VSwitch", "props": ["model": "enabled", "label": "启用"]],
      ], model: ["name": "", "enabled": "bad"])
    var draft = try PluginFormDraft(document: document)
    let initial = try NativeFormPlan(document: document, draft: draft)
    #expect(initial.groups.flatMap(\.elements).count == 2)
    #expect(initial.issues.count == 2)
    try draft.setValue(.string("😀"), forExactField: "name")
    try draft.setValue(.bool(true), forExactField: "enabled")
    #expect(try NativeFormPlan(document: document, draft: draft).issues.isEmpty)
    try draft.setValue(.string("😀a"), forExactField: "name")
    #expect(try NativeFormPlan(document: document, draft: draft).issues.count == 1)
  }

  /// 选项保留数字/布尔/字符串/null 类型，多选不擅自过滤旧的未知值。
  @Test func preservesTypedAndOrphanSelectionValues() throws {
    let document = try decode(
      [
        [
          "component": "VSelect",
          "props": [
            "model": "chosen", "label": "来源", "multiple": true,
            "items": [
              ["title": "一", "value": 1], ["title": "字符串", "value": "1"],
              ["title": "空", "value": NSNull()],
            ],
          ],
        ]
      ], model: ["chosen": ["old", 1]])
    let draft = try PluginFormDraft(document: document)
    let plan = try NativeFormPlan(document: document, draft: draft)
    #expect(plan.issues.isEmpty)
    guard
      case .select(let field, let options, let multiple, _) = plan.groups.first?.elements.first?
        .control
    else {
      Issue.record("缺少选择器")
      return
    }
    #expect(multiple)
    #expect(field.value?.array?.count == 2)
    #expect(options[0].matches(.number(try PluginJSONNumber("1.0"))))
    #expect(!options[0].matches(.string("1")))
    #expect(options[2].matches(.null))
    #expect(!options.contains { $0.matches(.string("old")) })
  }

  /// JSON 选择比较不能把规范等价 Unicode 或不同 JSON 类型合并。
  @Test func comparesSelectionWithoutCanonicalUnicodeOrTypeCoercion() throws {
    #expect(!NativeFormValues.equal(.string("é"), .string("e\u{301}")))
    #expect(!NativeFormValues.equal(.bool(true), .number(try PluginJSONNumber("1"))))
    #expect(
      NativeFormValues.equal(
        .object(["x": .array([.number(try PluginJSONNumber("1e2"))])]),
        .object(["x": .array([.number(try PluginJSONNumber("100"))])])))
  }

  /// 清单解码保留物理分身，错误安装状态/路径不能被当成合法入口。
  @Test func decodesPhysicalPluginRecordsAndRejectsInvalidTargets() throws {
    let data = Data(
      #"{"id":"Clone_2","source_plugin_id":"Source","installed":true,"plugin_name":"分身"}"#.utf8)
    let record = try JSONDecoder().decode(NativeInstalledPlugin.self, from: data)
    #expect(record.id == "Clone_2")
    #expect(record.target.sourceID == "Source")
    #expect(record.name == "分身")
    for json in [
      #"{"id":"../Source","installed":true}"#, #"{"id":"Source","installed":false}"#,
      #"{"id":"Source"}"#,
    ] {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(NativeInstalledPlugin.self, from: Data(json.utf8))
      }
    }
  }

  /// 构造完整协议响应，只接受测试数据，不绕过实际解码器。
  private func decode(_ nodes: [[String: Any]], model: [String: Any]) throws -> PluginUIDocument {
    try PluginUIDecoder.decode(
      JSONSerialization.data(withJSONObject: [
        "render_mode": "vuetify", "conf": nodes, "model": model,
      ]), surface: .form)
  }
}
