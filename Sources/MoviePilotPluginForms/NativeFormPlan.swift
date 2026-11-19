import Foundation
import MoviePilotPluginUI

/// 真正由 SwiftUI 穷尽渲染的控件集合；增加能力必须同时增加渲染与验收。
public enum NativeFormControl: Sendable {
  case toggle(NativeFormField)
  case input(NativeFormField, NativeFormInputKind)
  case cron(NativeFormField)
  case select(NativeFormField, options: [NativeFormOption], multiple: Bool, clearable: Bool)
  case notice(title: String, text: String, kind: NativeFormNoticeKind)
  case text(String)
  case divider
  case unsupported
}

/// 输入值保持旧组件的字符串编辑语义，数字仅在验证时作精确比较。
public enum NativeFormInputKind: Equatable, Sendable { case text, password, number, multiline }

/// 通知类型映射到原生符号与语义，不执行 HTML 或链接脚本。
public enum NativeFormNoticeKind: String, Sendable { case info, success, warning, error }

/// 一个完整原始键的编辑投影；没有点路径赋值或过滤保存模型。
public struct NativeFormField: Sendable {
  public let key: String
  public let label: String
  public let hint: String
  public let placeholder: String
  public let suffix: String
  public let value: PluginJSONValue?
  public let disabled: Bool
  public let clearable: Bool

  /// 标量显示不经过浮点；无值时才显示空输入。
  public var text: String { Self.text(from: value) }

  /// 输入绑定可直接读取最新草稿；不能把上一帧的值快照当作持续编辑的真值。
  public static func text(from value: PluginJSONValue?) -> String {
    NativeFormExpression.text(value) ?? ""
  }

  /// 开关仅把布尔 true 显示为开启；类型异常由同一计划报告。
  public var isOn: Bool { value == .bool(true) }
}

/// 选项 ID 只用于当前 UI 顺序，真正模型值保留 JSON 类型。
public struct NativeFormOption: Sendable, Identifiable {
  public let id: Int
  public let title: String
  public let value: PluginJSONValue

  /// 保持数值等价与 Unicode 原始序列；不把数字/字符串当作同一选项。
  public func matches(_ candidate: PluginJSONValue) -> Bool {
    NativeFormValues.equal(value, candidate)
  }
}

/// 重排为阅读宽度内的玻璃分组，元素顺序与原始文档一致。
public struct NativeFormGroup: Sendable, Identifiable {
  public let id: String
  public let elements: [NativeFormElement]
}

/// 节点路径同时用于界面身份和无敏感值的校验定位。
public struct NativeFormElement: Sendable, Identifiable {
  public let id: String
  public let control: NativeFormControl
}

/// UI 与保存共享完整的实际渲染计划，隐藏节点也接受能力检查。
public struct NativeFormPlan: Sendable {
  public let groups: [NativeFormGroup]
  public let issues: [PluginFormValidationIssue]

  /// 每次草稿变化重新求值绑定/条件；失败不会被当成空表单成功。
  public init(document: PluginUIDocument, draft: PluginFormDraft) throws {
    var builder = NativeFormPlanBuilder(model: draft.model)
    if document.surface != .form || document.renderMode != .vuetify || !document.isStructurallyValid
    {
      builder.issue(.unsupported, "/conf")
    }
    for node in document.nodes { try builder.visit(node) }
    builder.flush()
    groups = builder.groups
    issues = builder.issues
  }
}

/// 只有实际采用 NativeFormControl 的界面注入此验证器；默认未渲染策略仍保留。
public struct NativeFormValidator: PluginFormValidating {
  /// 验证器不保存任何跨插件模型或闭包。
  public init() {}

  /// 和界面调用同一计划器，不另维护一份虚假的支持组件白名单。
  public func validate(document: PluginUIDocument, draft: PluginFormDraft) throws
    -> [PluginFormValidationIssue]
  {
    try NativeFormPlan(document: document, draft: draft).issues
  }
}

/// JSON 选择值的精确比较；对象键和字符串不用 Swift 的规范等价语义。
enum NativeFormValues {
  /// 不改变模型，只比较结构/类型以及有界数字的十进制值。
  static func equal(_ a: PluginJSONValue, _ b: PluginJSONValue) -> Bool {
    switch (a, b) {
    case (.string(let x), .string(let y)): return x.utf8.elementsEqual(y.utf8)
    case (.number(let x), .number(let y)):
      if x.rawValue == y.rawValue { return true }
      guard let x = ExactFormNumber(x.rawValue), let y = ExactFormNumber(y.rawValue) else {
        return false
      }
      return x.compare(y) == 0
    case (.bool(let x), .bool(let y)): return x == y
    case (.null, .null): return true
    case (.array(let x), .array(let y)): return x.count == y.count && zip(x, y).allSatisfy(equal)
    case (.object(let x), .object(let y)):
      return x.count == y.count
        && x.allSatisfy { key, value in
          guard let other = PluginJSONValue.object(y)[exactKey: key] else { return false }
          return equal(value, other)
        }
    default: return false
    }
  }
}

/// 一次计划的局部遍历状态；未知行为永远阻止保存，不依赖当前是否可见。
private struct NativeFormPlanBuilder {
  let model: [String: PluginJSONValue]
  var groups: [NativeFormGroup] = []
  var issues: [PluginFormValidationIssue] = []
  private var current: [NativeFormElement] = []
  private var issueKeys: Set<String> = []
  private static let layouts: Set<String> = [
    "VForm", "VContainer", "VRow", "VCol", "VCard", "VCardText", "div",
  ]
  private static let toggles: Set<String> = ["VSwitch", "VCheckbox", "VCheckboxBtn"]
  private static let inputs: Set<String> = ["VTextField", "VTextarea"]
  // 桌面排版属性交给统一原生布局/材质，行为属性必须在下面明确实现。
  private static let presentation: Set<String> = [
    "cols", "sm", "md", "lg", "xl", "xxl", "offset", "dense", "density", "variant",
    "color", "base-color", "bg-color", "border", "border-color", "rounded", "elevation",
    "persistent-hint", "persistentHint", "hide-details", "hideDetails", "chips", "closable-chips",
    "auto-grow", "rows", "hide-spin-buttons", "v-if",
  ]

  /// 遍历状态仅绑定本次完整草稿。
  init(model: [String: PluginJSONValue]) { self.model = model }

  /// 分组边界不产生空玻璃卡片，路径作为稳定 ID。
  mutating func flush() {
    guard let first = current.first else { return }
    groups.append(.init(id: first.id, elements: current))
    current = []
  }

  /// 重复诊断合并；位置来自协议路径，绝不拼接模型值。
  mutating func issue(_ code: PluginFormValidationCode, _ pointer: String) {
    let issue = PluginFormValidationIssue(code: code, pointer: pointer)
    if issueKeys.insert(code.rawValue + ":" + pointer).inserted { issues.append(issue) }
  }

  /// 显示条件与能力检查分离；父节点隐藏不能藏住未知脚本或控件。
  mutating func visit(
    _ node: PluginUINode, visible parentVisible: Bool = true, disabled parentDisabled: Bool = false
  ) throws {
    try Task.checkCancellation()
    let component = node.component ?? ""
    if node.properties["show"] != nil && node.properties["v-show"] != nil {
      issue(.unsupported, node.pointer + "/props/show")
    }
    if let text = node.text, NativeFormExpression.truth(text), text.string == nil {
      issue(.unsupported, node.pointer + "/text")
    }
    let layout = Self.layouts.contains(component)
    if layout
      || !(Self.toggles.contains(component) || Self.inputs.contains(component)
        || component == "VSelect" || component == "VCronField")
    {
      for binding in node.bindings where binding.kind != .implicitRead {
        issue(.unsupported, binding.pointer)
      }
    }
    if component == "VRow" || component == "VCard" { flush() }
    var props: [String: PluginJSONValue] = [:]
    var visible = parentVisible
    for key in node.properties.keys.sorted() {
      guard let raw = node.properties[key] else { continue }
      if isBinding(key) { continue }
      let pointer =
        node.pointer + "/props/"
        + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
      if key.hasPrefix("on") {
        if raw.string != nil { issue(.unsupported, pointer) }
        continue  // 旧解释器也不执行非字符串事件。
      }
      do {
        let value: PluginJSONValue?
        if key == "show" || key == "v-show" {
          guard let expression = raw.string else { throw NativeExpressionError.unsupported }
          value = try NativeFormExpression.evaluate(expression, model: model)
          visible = visible && NativeFormExpression.truth(value)
        } else if let text = raw.string, text.hasPrefix("{{"), text.hasSuffix("}}") {
          value = try NativeFormExpression.evaluate(text, model: model)
        } else if let text = raw.string, let found = PluginJSONValue.object(model)[exactKey: text] {
          value = found
        } else {
          value = raw
        }
        props[key] = value
      } catch is CancellationError { throw CancellationError() } catch {
        issue(.unsupported, pointer)
      }
    }
    let allowed: Set<String>
    if layout {
      allowed = []
    } else if Self.toggles.contains(component) {
      allowed = ["label", "hint", "disabled", "readonly", "required"]
    } else if Self.inputs.contains(component) {
      allowed = [
        "label", "hint", "placeholder", "disabled", "readonly", "required", "type", "min", "max",
        "step", "suffix", "maxlength", "clearable",
      ]
    } else if component == "VCronField" {
      allowed = [
        "label", "hint", "placeholder", "disabled", "readonly", "required", "clearable", "type",
        "maxlength", "suffix",
      ]
    } else if component == "VSelect" {
      allowed = [
        "label", "hint", "placeholder", "disabled", "readonly", "required", "items", "multiple",
        "clearable", "item-title", "item-value", "itemTitle", "itemValue",
      ]
    } else if component == "VAlert" {
      allowed = ["title", "text", "type"]
    } else {
      allowed = []
    }
    for key in node.properties.keys
    where !isBinding(key) && key != "show" && key != "v-show" && !key.hasPrefix("on") {
      if key == "class" {
        // 仅接受常见排版类；隐藏/未知 CSS 类不能假装兼容。
        let tokens = props[key]?.string?.split(whereSeparator: \.isWhitespace) ?? []
        if props[key]?.string == nil || tokens.contains(where: { !Self.layoutClass(String($0)) }) {
          issue(.unsupported, node.pointer + "/props/class")
        }
      } else if !allowed.contains(key) && !Self.presentation.contains(key) {
        issue(.unsupported, node.pointer + "/props/" + key)
      }
    }
    if !node.slots.isEmpty { issue(.unsupported, node.pointer + "/slots") }
    if let html = node.html, NativeFormExpression.truth(html) {
      issue(.unsupported, node.pointer + "/html")
    }
    let disabled =
      parentDisabled || NativeFormExpression.truth(props["disabled"])
      || NativeFormExpression.truth(props["readonly"])
    let rawText = node.text.flatMap {
      NativeFormExpression.truth($0) ? NativeFormExpression.text($0) : nil
    }
    if layout {
      if visible, let rawText { current.append(.init(id: node.pointer, control: .text(rawText))) }
    } else {
      let control = try control(
        node, component: component, props: props, visible: visible, disabled: disabled)
      if visible { current.append(.init(id: node.pointer, control: control)) }
    }
    // text 优先级与旧解释器一致；不可见子树仍检查能力，但不生成可见控件。
    for child in node.children {
      try visit(child, visible: visible && rawText == nil && layout, disabled: disabled)
    }
    if !layout, !node.children.isEmpty { issue(.unsupported, node.pointer + "/content") }
    if component == "VRow" || component == "VCard" { flush() }
  }

  /// 每个可编辑控件要求唯一值绑定，未知命名属性不能误当普通 modelValue。
  private mutating func field(
    _ node: PluginUINode, props: [String: PluginJSONValue], disabled: Bool
  ) -> NativeFormField? {
    let bindings = node.bindings.filter { $0.kind != .implicitRead }
    guard bindings.count == 1, let binding = bindings.first else {
      issue(.unsupported, node.pointer + "/props/model")
      return nil
    }
    if case .named(let property) = binding.kind, property != "modelValue" && property != "value" {
      issue(.unsupported, binding.pointer)
      return nil
    }
    let label = NativeFormExpression.text(props["label"]) ?? ""
    guard !label.isEmpty else {
      issue(.unsupported, node.pointer + "/props/label")
      return nil
    }
    return .init(
      key: binding.field, label: label, hint: NativeFormExpression.text(props["hint"]) ?? "",
      placeholder: NativeFormExpression.text(props["placeholder"]) ?? "",
      suffix: NativeFormExpression.text(props["suffix"]) ?? "",
      value: PluginJSONValue.object(model)[exactKey: binding.field], disabled: disabled,
      clearable: props["clearable"].map { NativeFormExpression.truth($0) }
        ?? (node.component == "VCronField"))
  }

  /// 所有实际控件与值验证集中在同一分支，避免界面和保存支持度漂移。
  private mutating func control(
    _ node: PluginUINode, component: String, props: [String: PluginJSONValue], visible: Bool,
    disabled: Bool
  ) throws -> NativeFormControl {
    let editable =
      Self.toggles.contains(component) || Self.inputs.contains(component) || component == "VSelect"
      || component == "VCronField"
    if editable {
      guard let field = field(node, props: props, disabled: disabled) else { return .unsupported }
      if visible && !disabled && NativeFormExpression.truth(props["required"])
        && Self.empty(field.value)
      {
        issue(.requiredValue, node.pointer)
      }
      if component == "VCronField" {
        // 原控件允许插件方言（例如数字小时间隔）；只检验可编辑结构，不替代插件调度规则。
        if let rawType = node.properties["type"], rawType != .null, props["type"] != .string("text")
        {
          issue(.unsupported, node.pointer + "/props/type")
          return .unsupported
        }
        if visible, NativeFormExpression.text(field.value) == nil {
          issue(.invalidValue, node.pointer)
        }
        if let raw = props["maxlength"] {
          if let max = NativeFormExpression.text(raw).flatMap(Int.init), max >= 0 {
            if visible && field.text.utf16.count > max { issue(.invalidValue, node.pointer) }
          } else {
            issue(.unsupported, node.pointer + "/props/maxlength")
          }
        }
        return .cron(field)
      }
      if Self.toggles.contains(component) {
        if visible, let value = field.value, value != .null, value != .bool(true),
          value != .bool(false)
        {
          issue(.invalidValue, node.pointer)
        }
        return .toggle(field)
      }
      if component == "VSelect" {
        let multiple = NativeFormExpression.truth(props["multiple"])
        let options = options(props, pointer: node.pointer)
        if visible, multiple, let value = field.value, value != .null, value.array == nil {
          issue(.invalidValue, node.pointer)
        }
        return .select(
          field, options: options, multiple: multiple,
          clearable: NativeFormExpression.truth(props["clearable"]))
      }
      let kind: NativeFormInputKind
      if component == "VTextarea" {
        kind = .multiline
      } else {
        if node.properties["type"] != nil, props["type"]?.string == nil {
          issue(.unsupported, node.pointer + "/props/type")
          return .unsupported
        }
        switch props["type"]?.string ?? "text" {
        case "text": kind = .text
        case "password": kind = .password
        case "number": kind = .number
        default:
          issue(.unsupported, node.pointer + "/props/type")
          return .unsupported  // 未确认的输入类型绝不以明文展示可能的秘密值。
        }
      }
      if visible {
        if NativeFormExpression.text(field.value) == nil { issue(.invalidValue, node.pointer) }
        if let raw = props["maxlength"] {
          if let max = NativeFormExpression.text(raw).flatMap(Int.init), max >= 0 {
            if field.text.utf16.count > max { issue(.invalidValue, node.pointer) }
          } else {
            issue(.unsupported, node.pointer + "/props/maxlength")
          }
        }
        if case .number = kind, !field.text.isEmpty {
          if let value = ExactFormNumber(field.text) {
            for (key, minimum) in [("min", true), ("max", false)] {
              if let bound = props[key].flatMap(NativeFormExpression.text) {
                if let number = ExactFormNumber(bound) {
                  let order = value.compare(number)
                  if minimum ? order < 0 : order > 0 { issue(.invalidValue, node.pointer) }
                } else {
                  issue(.unsupported, node.pointer + "/props/" + key)
                }
              }
            }
          } else {
            issue(.invalidValue, node.pointer)
          }
        }
      }
      // 显式步长约束在下一组件叶子完成；只有 any 没有待实现的整除规则。
      if let step = props["step"], step != .string("any") {
        issue(.unsupported, node.pointer + "/props/step")
      }
      return .input(field, kind)
    }
    if component == "VAlert" {
      let type = props["type"]?.string ?? "info"
      guard let kind = NativeFormNoticeKind(rawValue: type) else {
        issue(.unsupported, node.pointer + "/props/type")
        return .unsupported
      }
      return .notice(
        title: NativeFormExpression.text(props["title"]) ?? "",
        text: node.text?.string ?? NativeFormExpression.text(props["text"]) ?? "", kind: kind)
    }
    if component == "VDivider" { return .divider }
    if ["span", "p", "VLabel", "VCardTitle", "VCardSubtitle"].contains(component),
      let text = node.text?.string
    {
      return .text(text)
    }
    issue(.unsupported, node.pointer + "/component")
    return .unsupported
  }

  /// 标准 title/value 对象和标量选项保留值类型；复杂自定义槽/对象属性仍明确阻断。
  private mutating func options(_ props: [String: PluginJSONValue], pointer: String)
    -> [NativeFormOption]
  {
    guard let values = props["items"]?.array, values.count <= 1000 else {
      issue(.unsupported, pointer + "/props/items")
      return []
    }
    let titleKey = props["item-title"]?.string ?? props["itemTitle"]?.string ?? "title"
    let valueKey = props["item-value"]?.string ?? props["itemValue"]?.string ?? "value"
    var result: [NativeFormOption] = []
    for (index, value) in values.enumerated() {
      let title: String?
      let payload: PluginJSONValue
      if case .object = value {
        title = NativeFormExpression.text(value[exactKey: titleKey])
        payload = value[exactKey: valueKey] ?? .null
        if value[exactKey: valueKey] == nil || value[exactKey: "props"] != nil {
          issue(.unsupported, pointer + "/props/items/" + String(index))
        }
      } else {
        title = NativeFormExpression.text(value)
        payload = value
      }
      guard let title else {
        issue(.unsupported, pointer + "/props/items/" + String(index))
        continue
      }
      result.append(.init(id: index, title: title, value: payload))
    }
    return result
  }

  /// 旧解释器只把这些属性变成双向绑定，原始字段不按点拆分。
  private func isBinding(_ key: String) -> Bool {
    key == "model" || key == "v-model" || key == "modelvalue" || key.hasPrefix("model:")
      || key.hasPrefix("v-model:")
  }

  /// 必填保持非空值语义，不擅自修剪或修改字符串。
  private static func empty(_ value: PluginJSONValue?) -> Bool {
    switch value {
    case nil, .null: true
    case .string(let text): text.isEmpty
    case .array(let values): values.isEmpty
    default: false
    }
  }

  /// 常见间距/字体/对齐类由原生设计系统替代，不接受隐藏或未知自定义类。
  private static func layoutClass(_ token: String) -> Bool {
    let fixed: Set<String> = [
      "d-flex", "flex-column", "flex-wrap", "align-center", "align-start", "justify-center",
      "justify-space-between", "text-center", "text-start", "text-left", "text-right", "w-100",
    ]
    return fixed.contains(token)
      || token.range(
        of:
          "^(m[atrblxy]?|p[atrblxy]?)-[0-9]{1,2}$|^text-(caption|body-1|body-2|subtitle-1|subtitle-2|h[1-6]|primary|secondary|warning|error|info|success)$",
        options: .regularExpression) != nil
  }
}
