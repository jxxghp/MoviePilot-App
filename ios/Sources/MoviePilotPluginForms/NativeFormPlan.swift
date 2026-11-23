import Foundation
import MoviePilotPluginUI

/// 真正由 SwiftUI 穷尽渲染的控件集合；增加能力必须同时增加渲染与验收。
public enum NativeFormControl: Sendable {
  case toggle(NativeFormField)
  /// 多值复选框（如 `VCheckbox` 带 `value` 属性并绑定数组模型字段）。
  case toggleValue(NativeFormField, itemValue: PluginJSONValue)
  case input(NativeFormField, NativeFormInputKind)
  case codeEditor(NativeFormField, language: String)
  case cron(NativeFormField)
  case colorPicker(NativeFormField)
  case select(NativeFormField, options: [NativeFormOption], multiple: Bool, clearable: Bool)
  case combobox(NativeFormField, NativeComboboxDraft)
  case slider(NativeFormField, min: Double, max: Double, step: Double)
  case rangeSlider(NativeFormField, min: Double, max: Double, step: Double)
  case chipGroup(NativeFormField, options: [NativeFormOption], multiple: Bool)
  case expansion(title: String, elements: [NativeFormElement])
  case notice(title: String, text: String, kind: NativeFormNoticeKind)
  case link(label: String, url: URL)
  case button(label: String, api: String?, method: String?, color: String?, webOnly: Bool)
  case chip(text: String, color: String?)
  /// 快捷预设胶囊（如 `VChip` 的 `onClick: "refresh_cron = '0 */1 * * *'"`），纯原生写入草稿字段，不执行脚本。
  case presetChip(text: String, color: String?, field: String, value: PluginJSONValue)
  case table(headers: [String], rows: [[String]])
  case text(String)
  case divider
  case unsupported
}

/// 输入值保持旧组件的字符串编辑语义，数字仅在验证时作精确比较。
public enum NativeFormInputKind: Equatable, Sendable {
  case text, password, number, multiline, url, email
}

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

  /// 容器型排版组件：递归展开子节点。
  private static let layouts: Set<String> = [
    "VForm", "VContainer", "VRow", "VCol", "VCard", "VCardText", "VCardItem", "VCardActions",
    "VSheet", "VTabs", "VTab", "VWindow", "VWindowItem", "VList", "VListItem", "VMenu",
    "VExpansionPanels", "div",
  ]
  /// 可忽略的无交互视觉占位组件。
  private static let ignoredVisuals: Set<String> = [
    "VSpacer", "VDialogCloseBtn", "VIcon", "v-icon", "VImg", "img", "VAvatar", "br", "style",
    "VScrollToTopBtn",
  ]
  private static let toggles: Set<String> = ["VSwitch", "VCheckbox", "VCheckboxBtn"]
  private static let inputs: Set<String> = ["VTextField", "VTextarea", "VPathField"]
  private static let crons: Set<String> = ["VCronField", "VCronVuetify"]
  private static let selects: Set<String> = ["VSelect", "VAutocomplete"]
  private static let textNodes: Set<String> = [
    "span", "p", "VLabel", "VCardTitle", "VCardSubtitle", "VListItemTitle", "VListItemSubtitle",
    "VListSubheader", "VPageContentTitle", "u", "b", "strong", "em", "i", "small", "code", "pre",
    "h1", "h2", "h3", "h4", "h5", "h6",
  ]

  // 桌面排版/装饰属性交给统一原生布局/材质，行为属性必须在下面明确实现。
  private static let presentation: Set<String> = [
    "cols", "sm", "md", "lg", "xl", "xxl", "offset", "offset-sm", "offset-md", "offset-lg",
    "dense", "density", "variant", "color", "base-color", "baseColor", "bg-color", "bgColor",
    "border", "border-color", "borderColor",
    "rounded", "elevation", "persistent-hint", "persistentHint", "hide-details", "hideDetails",
    "chips", "closable-chips", "closableChips", "small-chips", "smallChips", "deletable-chips",
    "deletableChips", "auto-grow", "autoGrow", "rows", "max-rows", "maxRows", "no-resize",
    "noResize", "hide-spin-buttons", "v-if", "prepend-icon", "prependIcon", "prepend-inner-icon",
    "prependInnerIcon", "append-icon", "appendIcon", "append-inner-icon", "appendInnerIcon",
    "icon", "icon-color", "size", "width", "height", "max-width", "maxWidth", "min-width",
    "minWidth", "max-height", "maxHeight", "min-height", "minHeight", "flat", "tile", "outlined",
    "tonal", "block", "stacked", "plain", "ripple", "inset", "inline", "counter", "prefix",
    "single-line", "singleLine", "shaped", "solo", "filled", "underlined", "autofocus", "loading",
    "popout", "closable", "prominent", "align", "justify", "no-gutters", "noGutters", "order",
    "align-self", "alignSelf", "overlay-class", "content-class", "persistent", "scrollable",
    "fullscreen", "eager", "transition", "lang", "language", "theme", "options", "min-lines",
    "max-lines", "autocomplete", "name", "id", "key", "ref", "aria-label", "tag", "target", "rel",
    "lines", "nav", "slim", "open-strategy", "selected-class", "selectedClass", "active-class",
    "activeClass", "show-arrows", "showArrows", "center-active", "centerActive", "column",
    "filter", "mandatory", "thumb-label", "thumbLabel", "ticks", "show-ticks", "tick-size",
    "strict", "title", "subtitle", "text", "src", "alt", "cover", "aspect-ratio", "multiple",
    "indeterminate", "true-value", "false-value", "value", "hover", "fixed-header",
    "items-per-page", "no-data-text",
    "active", "active-color", "activeColor", "fixed-tabs", "fixedTabs", "grow", "divided",
    "align-tabs", "alignTabs", "slider-color", "sliderColor",
    "persistent-placeholder", "persistentPlaceholder", "start", "end",
    "storage", "root", "change", "clear-icon", "clearIcon",
    "hide-no-data", "hideNoData", "menu-props", "menuProps",
    "mode", "modes", "swatches", "hide-canvas", "hideCanvas", "hide-inputs", "hideInputs",
    "show-swatches", "showSwatches", "hide-sliders", "hideSliders", "hide-mode-switch",
    "hideModeSwitch", "canvas-height", "canvasHeight", "focused", "location", "position",
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

    // 1. 特殊复合容器：VExpansionPanel -> 折叠分组
    if component == "VExpansionPanel" {
      try visitExpansionPanel(node, visible: parentVisible, disabled: parentDisabled)
      return
    }
    // 2. 特殊复合容器：VDialog -> 按绑定的布尔字段（或标题折叠组）渲染内部控件
    if component == "VDialog" {
      try visitDialog(node, visible: parentVisible, disabled: parentDisabled)
      return
    }
    // 3. 表格容器：VTable / VDataTable / VDataTableVirtual
    if ["VTable", "VDataTable", "VDataTableVirtual"].contains(component) {
      if parentVisible {
        let parsed = extractTable(from: node)
        if !parsed.headers.isEmpty || !parsed.rows.isEmpty {
          current.append(
            .init(id: node.pointer, control: .table(headers: parsed.headers, rows: parsed.rows)))
        }
      }
      return
    }
    // 4. 忽略无交互装饰节点
    if Self.ignoredVisuals.contains(component) {
      return
    }

    let isEditableComponent =
      Self.toggles.contains(component) || Self.inputs.contains(component)
      || Self.selects.contains(component) || component == "VCombobox"
      || Self.crons.contains(component) || component == "VAceEditor" || component == "VSlider"
      || component == "VRangeSlider" || component == "VChipGroup" || component == "VRadioGroup"
      || component == "VBtnToggle" || component == "VColorPicker"
    let layout = Self.layouts.contains(component)
    let allowsLayoutTabBinding = component == "VTabs" || component == "VWindow"
    if (layout && !allowsLayoutTabBinding) || (!layout && !isEditableComponent) {
      for binding in node.bindings where binding.kind != .implicitRead {
        issue(.unsupported, binding.pointer)
      }
    }
    if component == "VRow" || component == "VCard" { flush() }

    let (props, visible) = try evaluateProps(node, parentVisible: parentVisible)

    let allowed = allowedProps(for: component, layout: layout)
    validateProps(node, component: component, props: props, allowed: allowed)

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
      if visible {
        if component == "VCard", let cardTitle = NativeFormExpression.text(props["title"]),
          !cardTitle.isEmpty
        {
          current.append(.init(id: node.pointer + "/title", control: .text(cardTitle)))
        }
        if let rawText {
          current.append(.init(id: node.pointer, control: .text(rawText)))
        } else if let innerHTML = props["innerHTML"]?.string, !innerHTML.isEmpty {
          let stripped = Self.stripHTML(innerHTML)
          if !stripped.isEmpty {
            current.append(.init(id: node.pointer, control: .text(stripped)))
          }
        }
      }
      for child in node.children {
        try visit(child, visible: visible && rawText == nil, disabled: disabled)
      }
    } else if component == "VChipGroup" || component == "VRadioGroup" || component == "VBtnToggle" {
      let ctrl = try groupChoiceControl(
        node, component: component, props: props, visible: visible, disabled: disabled)
      if visible { current.append(.init(id: node.pointer, control: ctrl)) }
    } else if component == "VAlert" {
      let ctrl = alertControl(node, props: props)
      if visible { current.append(.init(id: node.pointer, control: ctrl)) }
      // 递归提取 VAlert 内嵌链接（如 <a href="...">）
      if visible {
        appendInlineLinks(from: node.children)
      }
    } else if component == "a" {
      if visible {
        let label = Self.combinedPlainText(from: node)
        if let href = props["href"]?.string, let url = Self.safeExternalURL(href) {
          current.append(
            .init(id: node.pointer, control: .link(label: label.isEmpty ? href : label, url: url)))
        } else if !label.isEmpty {
          current.append(.init(id: node.pointer, control: .text(label)))
        }
      }
    } else if component == "VBtn" {
      let ctrl = buttonControl(node, props: props)
      if visible { current.append(.init(id: node.pointer, control: ctrl)) }
    } else if component == "VChip" {
      if visible {
        let label = Self.combinedPlainText(from: node)
        if !label.isEmpty {
          let rawClick = node.properties["onClick"]?.string ?? node.properties["onclick"]?.string
          if let rawClick, let assignment = Self.parseSimpleFieldAssignment(rawClick, model: model)
          {
            current.append(
              .init(
                id: node.pointer,
                control: .presetChip(
                  text: label, color: props["color"]?.string,
                  field: assignment.field, value: assignment.value)))
          } else {
            current.append(
              .init(id: node.pointer, control: .chip(text: label, color: props["color"]?.string)))
          }
        }
      }
    } else if Self.textNodes.contains(component) {
      if visible {
        let text = Self.combinedPlainText(from: node, evaluatedProps: props)
        if !text.isEmpty {
          current.append(.init(id: node.pointer, control: .text(text)))
        }
        appendInlineLinks(from: node.children)
      }
    } else {
      let ctrl = try control(
        node, component: component, props: props, visible: visible, disabled: disabled)
      if visible { current.append(.init(id: node.pointer, control: ctrl)) }
      if !node.children.isEmpty {
        issue(.unsupported, node.pointer + "/content")
      }
    }

    if component == "VRow" || component == "VCard" { flush() }
  }

  /// 解析 `VExpansionPanel` 为原生折叠组 `DisclosureGroup`。
  private mutating func visitExpansionPanel(
    _ node: PluginUINode, visible parentVisible: Bool, disabled parentDisabled: Bool
  ) throws {
    let (props, visible) = try evaluateProps(node, parentVisible: parentVisible)
    let disabled =
      parentDisabled || NativeFormExpression.truth(props["disabled"])
      || NativeFormExpression.truth(props["readonly"])

    var title = NativeFormExpression.text(props["title"]) ?? ""
    var bodyNodes: [PluginUINode] = []
    var leadingTexts: [(String, String)] = []
    for child in node.children {
      switch child.component {
      case "VExpansionPanelTitle":
        let t = Self.combinedPlainText(from: child)
        if !t.isEmpty { title = t }
      case "VExpansionPanelText":
        if let txt = child.text?.string, !txt.isEmpty {
          leadingTexts.append((child.pointer + "/text", txt))
        }
        bodyNodes.append(contentsOf: child.children)
      default:
        bodyNodes.append(child)
      }
    }

    var subBuilder = NativeFormPlanBuilder(model: model)
    if visible {
      for (ptr, txt) in leadingTexts {
        subBuilder.current.append(.init(id: ptr, control: .text(txt)))
      }
    }
    for child in bodyNodes {
      try subBuilder.visit(child, visible: visible, disabled: disabled)
    }
    subBuilder.flush()
    for subIssue in subBuilder.issues {
      issue(subIssue.code, subIssue.pointer)
    }
    let flattened = subBuilder.groups.flatMap(\.elements)
    if visible, !flattened.isEmpty {
      flush()
      current.append(
        .init(
          id: node.pointer,
          control: .expansion(title: title.isEmpty ? "更多设置" : title, elements: flattened)))
      flush()
    }
  }

  /// 解析 `VDialog`：若内部含实际表单项（如 `VAceEditor`），以原生折叠区呈现，支持查看与编辑保存。
  private mutating func visitDialog(
    _ node: PluginUINode, visible parentVisible: Bool, disabled parentDisabled: Bool
  ) throws {
    let (props, visible) = try evaluateProps(node, parentVisible: parentVisible)
    let disabled = parentDisabled || NativeFormExpression.truth(props["disabled"])

    var dialogTitle = ""
    if let card = node.children.first(where: { $0.component == "VCard" }) {
      dialogTitle = card.properties["title"]?.string ?? ""
    }
    var subBuilder = NativeFormPlanBuilder(model: model)
    for child in node.children {
      try subBuilder.visit(child, visible: visible, disabled: disabled)
    }
    subBuilder.flush()
    for subIssue in subBuilder.issues {
      issue(subIssue.code, subIssue.pointer)
    }
    let flattened = subBuilder.groups.flatMap(\.elements)
    if visible, !flattened.isEmpty {
      flush()
      current.append(
        .init(
          id: node.pointer,
          control: .expansion(
            title: dialogTitle.isEmpty ? "高级编辑" : dialogTitle, elements: flattened)))
      flush()
    }
  }

  /// 计算节点属性求值与可见性。
  private mutating func evaluateProps(_ node: PluginUINode, parentVisible: Bool) throws -> (
    [String: PluginJSONValue], Bool
  ) {
    var props: [String: PluginJSONValue] = [:]
    var visible = parentVisible
    let component = node.component ?? ""
    for key in node.properties.keys.sorted() {
      guard let raw = node.properties[key] else { continue }
      if isBinding(key) { continue }
      let pointer =
        node.pointer + "/props/"
        + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
      if key.hasPrefix("on") {
        let lower = key.lowercased()
        // 允许纯按键拦截（如阻止输入负号）与 VChip 单字段常量预设赋值；其它 JS 事件处理仍严格阻断保存。
        if lower == "onkeydown", Self.inputs.contains(component) {
          continue
        }
        if lower == "onclick", component == "VChip",
          let script = raw.string, Self.parseSimpleFieldAssignment(script, model: model) != nil
        {
          continue
        }
        if raw.string != nil { issue(.unsupported, pointer) }
        continue
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
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        issue(.unsupported, pointer)
      }
    }
    return (props, visible)
  }

  private func allowedProps(for component: String, layout: Bool) -> Set<String> {
    if layout {
      return ["innerHTML", "title", "subtitle"]
    }
    if Self.toggles.contains(component) {
      return ["label", "hint", "disabled", "readonly", "required", "value"]
    }
    if Self.inputs.contains(component) {
      return [
        "label", "hint", "placeholder", "disabled", "readonly", "required", "type", "min", "max",
        "step", "suffix", "maxlength", "clearable",
      ]
    }
    if component == "VAceEditor" {
      return ["label", "hint", "placeholder", "disabled", "readonly", "required", "lang", "theme"]
    }
    if Self.crons.contains(component) {
      return [
        "label", "hint", "placeholder", "disabled", "readonly", "required", "clearable", "type",
        "maxlength", "suffix",
      ]
    }
    if component == "VColorPicker" {
      return ["label", "hint", "disabled", "readonly", "required"]
    }
    if Self.selects.contains(component) {
      return [
        "label", "hint", "placeholder", "disabled", "readonly", "required", "items", "multiple",
        "clearable", "item-title", "item-value", "itemTitle", "itemValue", "return-object",
        "returnObject",
      ]
    }
    if component == "VCombobox" {
      return [
        "label", "hint", "placeholder", "disabled", "readonly", "required", "items", "multiple",
        "clearable", "item-title", "item-value", "itemTitle", "itemValue", "return-object",
        "returnObject",
      ]
    }
    if component == "VSlider" || component == "VRangeSlider" {
      return ["label", "hint", "disabled", "readonly", "required", "min", "max", "step"]
    }
    if component == "VChipGroup" || component == "VRadioGroup" || component == "VBtnToggle" {
      return ["label", "hint", "disabled", "readonly", "required", "multiple", "inline"]
    }
    if component == "VAlert" {
      return ["title", "text", "type", "innerHTML"]
    }
    if component == "VBtn" || component == "a" {
      return ["href", "target", "rel", "text", "title", "disabled", "color", "variant"]
    }
    if Self.textNodes.contains(component) {
      return ["innerHTML", "text", "title"]
    }
    return []
  }

  /// 检查属性白名单、CSS 类与内联样式；严格阻止隐藏类/样式与未实现规则。
  private mutating func validateProps(
    _ node: PluginUINode, component: String, props: [String: PluginJSONValue], allowed: Set<String>
  ) {
    for key in node.properties.keys
    where !isBinding(key) && key != "show" && key != "v-show" && !key.hasPrefix("on") {
      if key == "class" {
        let tokens = props[key]?.string?.split(whereSeparator: \.isWhitespace) ?? []
        if props[key]?.string == nil
          || tokens.contains(where: { Self.isHidingClass(String($0)) })
        {
          issue(.unsupported, node.pointer + "/props/class")
        }
      } else if key == "style" {
        if let styleText = props[key]?.string {
          if Self.isHidingStyle(styleText) {
            issue(.unsupported, node.pointer + "/props/style")
          }
        } else if props[key] != nil, props[key] != .null {
          // 对象形式的 style 同样检查 display: none / visibility: hidden
          if case .object(let dict) = props[key] {
            let display = dict["display"]?.string?.lowercased().trimmingCharacters(in: .whitespaces)
            let vis = dict["visibility"]?.string?.lowercased().trimmingCharacters(in: .whitespaces)
            if display == "none" || vis == "hidden" {
              issue(.unsupported, node.pointer + "/props/style")
            }
          }
        }
      } else if !allowed.contains(key) && !Self.presentation.contains(key) {
        issue(.unsupported, node.pointer + "/props/" + key)
      }
    }
  }

  /// 每个可编辑控件要求唯一值绑定，未知命名属性不能误当普通 modelValue。
  private mutating func field(
    _ node: PluginUINode, props: [String: PluginJSONValue], disabled: Bool,
    allowFallbackLabel: Bool = false
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
    var label = NativeFormExpression.text(props["label"]) ?? ""
    if label.isEmpty && allowFallbackLabel {
      let placeholder = NativeFormExpression.text(props["placeholder"]) ?? ""
      label = !placeholder.isEmpty ? placeholder : binding.field
    }
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
        ?? Self.crons.contains(node.component ?? ""))
  }

  /// 处理 `VChipGroup`、`VBtnToggle` 和 `VRadioGroup` 的选项提取与模型绑定。
  private mutating func groupChoiceControl(
    _ node: PluginUINode, component: String, props: [String: PluginJSONValue], visible: Bool,
    disabled: Bool
  ) throws -> NativeFormControl {
    guard
      let field = field(node, props: props, disabled: disabled, allowFallbackLabel: true)
    else {
      return .unsupported
    }
    if visible && !disabled && NativeFormExpression.truth(props["required"])
      && Self.empty(field.value)
    {
      issue(.requiredValue, node.pointer)
    }
    var opts: [NativeFormOption] = []
    for (idx, child) in node.children.enumerated() {
      let childLabel =
        child.properties["label"]?.string
        ?? child.properties["text"]?.string
        ?? Self.combinedPlainText(from: child)
      let childVal =
        child.properties["value"] ?? (childLabel.isEmpty ? nil : .string(childLabel))
      guard let childVal else { continue }
      let title = childLabel.isEmpty ? (NativeFormExpression.text(childVal) ?? "") : childLabel
      opts.append(.init(id: idx, title: title, value: childVal))
    }
    if component == "VChipGroup" || component == "VBtnToggle" {
      let multiple = NativeFormExpression.truth(props["multiple"])
      return .chipGroup(field, options: opts, multiple: multiple)
    }
    return .select(field, options: opts, multiple: false, clearable: false)
  }

  /// 处理 `VAlert`（支持 `title`/`text`/`node.text`/`innerHTML` 与嵌套子文本）。
  private mutating func alertControl(
    _ node: PluginUINode, props: [String: PluginJSONValue]
  ) -> NativeFormControl {
    let type = props["type"]?.string ?? "info"
    guard let kind = NativeFormNoticeKind(rawValue: type) else {
      issue(.unsupported, node.pointer + "/props/type")
      return .unsupported
    }
    let title = props["title"].flatMap(NativeFormExpression.text) ?? ""
    let directText =
      [
        node.text?.string,
        props["text"].flatMap(NativeFormExpression.text),
        props["innerHTML"]?.string.map(Self.stripHTML),
        Self.combinedPlainText(from: node),
      ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
    return .notice(title: title, text: directText, kind: kind)
  }

  /// 处理 `VBtn`（优先外链 href，其次声明的 API 事件，再次 Web 端脚本提示按钮）。
  private func buttonControl(
    _ node: PluginUINode, props: [String: PluginJSONValue]
  ) -> NativeFormControl {
    let label =
      Self.combinedPlainText(from: node).isEmpty
      ? (props["text"]?.string ?? props["title"]?.string ?? "执行")
      : Self.combinedPlainText(from: node)
    if let href = props["href"]?.string, let url = Self.safeExternalURL(href) {
      return .link(label: label, url: url)
    }
    if let clickEvent = node.events.first(where: { $0.name == "click" }),
      let api = clickEvent.api, !api.isEmpty
    {
      return .button(
        label: label, api: api, method: clickEvent.declaredMethod,
        color: props["color"]?.string, webOnly: false)
    }
    return .button(
      label: label, api: nil, method: nil, color: props["color"]?.string,
      webOnly: props["onclick"] != nil)
  }

  /// 提取子节点中的外链 `<a href="...">` 以便用户可直接点击打开。
  private mutating func appendInlineLinks(from nodes: [PluginUINode]) {
    for child in nodes {
      if child.component == "a", let href = child.properties["href"]?.string,
        let url = Self.safeExternalURL(href)
      {
        let label = Self.combinedPlainText(from: child)
        current.append(
          .init(id: child.pointer, control: .link(label: label.isEmpty ? href : label, url: url)))
      } else if !child.children.isEmpty {
        appendInlineLinks(from: child.children)
      }
    }
  }

  /// 所有实际控件与值验证集中在同一分支，避免界面和保存支持度漂移。
  private mutating func control(
    _ node: PluginUINode, component: String, props: [String: PluginJSONValue], visible: Bool,
    disabled: Bool
  ) throws -> NativeFormControl {
    let editable =
      Self.toggles.contains(component) || Self.inputs.contains(component)
      || Self.selects.contains(component) || component == "VCombobox"
      || Self.crons.contains(component) || component == "VAceEditor" || component == "VSlider"
      || component == "VRangeSlider" || component == "VColorPicker"
    if editable {
      let allowFallback =
        component == "VAceEditor" || component == "VSlider" || component == "VRangeSlider"
        || component == "VColorPicker"
      guard
        let field = field(
          node, props: props, disabled: disabled, allowFallbackLabel: allowFallback)
      else { return .unsupported }
      if visible && !disabled && NativeFormExpression.truth(props["required"])
        && Self.empty(field.value)
      {
        issue(.requiredValue, node.pointer)
      }
      if component == "VColorPicker" {
        return .colorPicker(field)
      }
      if component == "VAceEditor" {
        let lang = props["lang"]?.string ?? props["language"]?.string ?? "text"
        return .codeEditor(field, language: lang)
      }
      if component == "VSlider" || component == "VRangeSlider" {
        let minVal = Self.doubleValue(props["min"]) ?? 0
        let maxVal = Self.doubleValue(props["max"]) ?? 100
        let stepVal = max(Self.doubleValue(props["step"]) ?? 1, 0.001)
        return component == "VRangeSlider"
          ? .rangeSlider(field, min: minVal, max: maxVal, step: stepVal)
          : .slider(field, min: minVal, max: maxVal, step: stepVal)
      }
      if Self.crons.contains(component) {
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
        // 多值复选框：`VCheckbox` / `VCheckboxBtn` 携带 `value` 属性绑定到数组模型字段（如 imdbsource）
        if let itemValue = props["value"], itemValue != .null,
          field.value == nil || field.value == .null || field.value?.array != nil
        {
          return .toggleValue(field, itemValue: itemValue)
        }
        if visible, let value = field.value, value != .null, value != .bool(true),
          value != .bool(false)
        {
          issue(.invalidValue, node.pointer)
        }
        return .toggle(field)
      }
      if component == "VCombobox" {
        do {
          return .combobox(field, try NativeComboboxDraft(properties: props, value: field.value))
        } catch NativeComboboxError.unsupported(let property) {
          issue(.unsupported, node.pointer + "/props/" + property)
          return .unsupported
        }
      }
      if Self.selects.contains(component) {
        let multiple = NativeFormExpression.truth(props["multiple"])
        let options = options(props, pointer: node.pointer)
        if visible, multiple, let value = field.value, value != .null, value != .string(""),
          value.array == nil
        {
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
        switch (props["type"]?.string ?? "text").lowercased() {
        case "text", "search", "tel", "date", "time": kind = .text
        case "url": kind = .url
        case "email": kind = .email
        case "password": kind = .password
        case "number": kind = .number
        default:
          issue(.unsupported, node.pointer + "/props/type")
          return .unsupported
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
      // 允许数字或 "any" 形式的 step 属性（例如 step: 1 / step: "0.5"）。
      if let step = props["step"], step != .string("any"),
        NativeFormExpression.text(step).flatMap(ExactFormNumber.init) == nil
      {
        issue(.unsupported, node.pointer + "/props/step")
      }
      return .input(field, kind)
    }
    if component == "VDivider" { return .divider }
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
        let resolvedValue =
          value[exactKey: valueKey]
          ?? (valueKey == "value" ? value[exactKey: "vale"] : nil)
        payload = resolvedValue ?? .null
        if resolvedValue == nil {
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

  /// 从 `VTable`/`VDataTable`/`VDataTableVirtual` 提取只读表头和行数据。
  private func extractTable(from node: PluginUINode) -> (headers: [String], rows: [[String]]) {
    if let rawHeaders = node.properties["headers"]?.array,
      let rawItems = node.properties["items"]?.array
    {
      let cols: [(title: String, key: String)] = rawHeaders.compactMap { item in
        guard case .object = item else { return nil }
        let key = item[exactKey: "key"]?.string ?? item[exactKey: "value"]?.string ?? ""
        let title = item[exactKey: "title"]?.string ?? item[exactKey: "text"]?.string ?? key
        return key.isEmpty ? nil : (title, key)
      }
      let rows: [[String]] = rawItems.compactMap { row in
        guard case .object = row else { return nil }
        return cols.map { NativeFormExpression.text(row[exactKey: $0.key]) ?? "" }
      }
      return (cols.map(\.title), rows)
    }
    var headers: [String] = []
    var rows: [[String]] = []
    func walk(_ n: PluginUINode, inHead: Bool) {
      let name = (n.component ?? "").lowercased()
      if name == "thead" {
        for c in n.children { walk(c, inHead: true) }
      } else if name == "tbody" {
        for c in n.children { walk(c, inHead: false) }
      } else if name == "tr" {
        let cells = n.children.map { Self.combinedPlainText(from: $0) }
        if inHead || n.children.allSatisfy({ ($0.component ?? "").lowercased() == "th" }) {
          if headers.isEmpty { headers = cells }
        } else if !cells.isEmpty {
          rows.append(cells)
        }
      } else {
        for c in n.children { walk(c, inHead: inHead) }
      }
    }
    walk(node, inHead: false)
    return (headers, rows)
  }

  /// 递归拼接节点及其子树的纯文本（含安全剥离 HTML 标签后的 `innerHTML`）。
  private static func combinedPlainText(
    from node: PluginUINode, evaluatedProps: [String: PluginJSONValue]? = nil
  ) -> String {
    var parts: [String] = []
    if let txt = node.text?.string, !txt.isEmpty {
      parts.append(txt)
    }
    let innerHTML = evaluatedProps?["innerHTML"]?.string ?? node.properties["innerHTML"]?.string
    if let innerHTML, !innerHTML.isEmpty {
      let stripped = stripHTML(innerHTML)
      if !stripped.isEmpty { parts.append(stripped) }
    }
    for child in node.children {
      if child.component == "br" {
        parts.append("\n")
      } else {
        let sub = combinedPlainText(from: child)
        if !sub.isEmpty { parts.append(sub) }
      }
    }
    return parts.joined(separator: "").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 纯 Swift 安全去除 HTML 标签并解码常见实体，不调用任何 WebView 或脚本引擎。
  private static func stripHTML(_ html: String) -> String {
    var text =
      html
      .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities: [(String, String)] = [
      ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
      ("&quot;", "\""), ("&#39;", "'"),
    ]
    for (k, v) in entities { text = text.replacingOccurrences(of: k, with: v) }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func safeExternalURL(_ raw: String) -> URL? {
    guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else { return nil }
    return url
  }

  private static func doubleValue(_ value: PluginJSONValue?) -> Double? {
    guard let str = NativeFormExpression.text(value) else { return nil }
    return Double(str)
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

  /// 显式隐藏节点的 CSS 类不能假装兼容；普通排版/间距/自定义样式类交由原生设计系统承载。
  private static func isHidingClass(_ token: String) -> Bool {
    let lower = token.lowercased()
    return lower == "d-none" || lower == "invisible" || lower == "v-hidden"
      || lower == "hidden" || lower.hasPrefix("d-") && lower.hasSuffix("-none")
  }

  /// 仅解析已知模型字段的纯字面量预设赋值（例如 `refresh_cron = '0 */1 * * *'`），拒绝任何函数调用或复合语句。
  private static func parseSimpleFieldAssignment(
    _ raw: String, model: [String: PluginJSONValue]
  ) -> (field: String, value: PluginJSONValue)? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.utf8.count <= 256, !trimmed.contains(";"), !trimmed.contains("\n") else {
      return nil
    }
    guard let eqIndex = trimmed.firstIndex(of: "=") else { return nil }
    let lhsRaw = trimmed[..<eqIndex]
    let rhsRaw = trimmed[trimmed.index(after: eqIndex)...]
    guard lhsRaw.last != "!", lhsRaw.last != "<", lhsRaw.last != ">", lhsRaw.last != "=",
      rhsRaw.first != "="
    else { return nil }
    let field = lhsRaw.trimmingCharacters(in: .whitespaces)
    guard !field.isEmpty,
      let firstByte = field.utf8.first,
      (65...90).contains(firstByte) || (97...122).contains(firstByte) || firstByte == 95,
      field.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
      }),
      PluginJSONValue.object(model)[exactKey: field] != nil
    else { return nil }

    let rhs = rhsRaw.trimmingCharacters(in: .whitespaces)
    guard !rhs.isEmpty else { return nil }
    if (rhs.hasPrefix("'") && rhs.hasSuffix("'")) || (rhs.hasPrefix("\"") && rhs.hasSuffix("\"")),
      rhs.count >= 2
    {
      let quote = rhs.first!
      let inner = String(rhs.dropFirst().dropLast())
      guard !inner.contains("\\"), !inner.contains(quote) else { return nil }
      return (field, .string(inner))
    }
    if rhs == "true" { return (field, .bool(true)) }
    if rhs == "false" { return (field, .bool(false)) }
    if rhs == "null" { return (field, .null) }
    if let number = try? PluginJSONNumber(rhs) {
      return (field, .number(number))
    }
    return nil
  }

  /// 检查内联样式是否包含隐藏声明。
  private static func isHidingStyle(_ style: String) -> Bool {
    let compact = style.lowercased().replacingOccurrences(
      of: "\\s+", with: "", options: .regularExpression)
    return compact.contains("display:none") || compact.contains("visibility:hidden")
  }
}
