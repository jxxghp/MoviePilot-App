import Foundation
import MoviePilotPluginUI

/// 组合框的一项保留显示名、比较值与原对象；不能把自定义字符串隐式变成预设对象。
public struct NativeComboboxItem: Sendable, Identifiable {
  public let id: Int
  public let title: String
  public let disabled: Bool
  let value: PluginJSONValue
  let raw: PluginJSONValue
}

/// 组合框尚未实现的属性保留路径诊断，不能以普通选择器静默代替。
enum NativeComboboxError: Error { case unsupported(String) }

/// Sheet 内的独立选择草稿；取消/无修改应用不归一化原始值，也不触发表单写入。
public struct NativeComboboxDraft: Sendable {
  private static let maximumItems = 1000
  public let options: [NativeComboboxItem]
  public let multiple: Bool
  public let clearable: Bool
  public private(set) var selected: [NativeComboboxItem]
  private let returnsObject: Bool
  private let original: PluginJSONValue?
  private var edited = false

  /// 只由实际渲染计划创建，属性/当前项未知行为在开放保存前即被拒绝。
  init(properties: [String: PluginJSONValue], value: PluginJSONValue?) throws {
    multiple = try Self.flag(properties, "multiple", default: false)
    clearable = try Self.flag(properties, "clearable", default: false)
    returnsObject = try Self.flag(properties, "return-object", alias: "returnObject", default: true)
    let titlePath = try ComboboxProperty(
      properties, key: "item-title", alias: "itemTitle", fallback: "title")
    let valuePath = try ComboboxProperty(
      properties, key: "item-value", alias: "itemValue", fallback: "value")
    let values: [PluginJSONValue]
    if let items = properties["items"] {
      guard let array = items.array, array.count <= Self.maximumItems else {
        throw NativeComboboxError.unsupported("items")
      }
      values = array
    } else {
      values = []
    }
    options = try values.enumerated().map { index, raw in
      try Self.item(
        raw, id: index, titlePath: titlePath, valuePath: valuePath, pointer: "items/\(index)")
    }
    original = value
    selected = []
    // wrapInArray 把顶层 null 视为空；数组中的 null 仅在存在 null 选项时显示。
    let current = value == .null ? [] : value?.array ?? value.map { [$0] } ?? []
    guard current.count <= Self.maximumItems else { throw NativeComboboxError.unsupported("model") }
    let hasNull = options.contains { $0.value == .null }
    for (index, raw) in current.enumerated() where raw != .null || hasNull {
      if !(returnsObject && raw.string != nil),
        let option = options.first(where: { NativeFormValues.equal(raw, $0.value) })
      {
        selected.append(option)
      } else {
        selected.append(
          try Self.item(
            raw, id: index, titlePath: titlePath, valuePath: valuePath, pointer: "model"))
      }
    }
  }

  /// 未编辑时返回完整原值；有明确编辑后才执行旧组件的 returnObject 输出投影。
  public var value: PluginJSONValue? {
    guard edited else { return original }
    let values = selected.map(output)
    return multiple ? .array(values) : values.first ?? .null
  }

  /// 缺失和 null 不等价；数值/字符串比较沿用整个原生表单的精确规则。
  public var hasChanges: Bool {
    switch (original, value) {
    case (nil, nil): false
    case (.some(let before), .some(let after)): !NativeFormValues.equal(before, after)
    default: true
    }
  }

  /// 预设行勾选比较投影值，而非显示标题或 Swift 的 Unicode 规范等价。
  public func isSelected(_ option: NativeComboboxItem) -> Bool {
    selected.contains { NativeFormValues.equal($0.value, option.value) }
  }

  /// 单选替换、多选切换；达到上限时返回 false，不改写本地选择。
  @discardableResult
  public mutating func choose(_ id: Int) -> Bool {
    guard options.indices.contains(id), !options[id].disabled else { return true }
    return select(options[id], replacingMatch: false)
  }

  /// 回车/添加/应用中的新输入均保留原字符串；与同值项冲突时按旧组件替换并移到末尾。
  @discardableResult
  public mutating func addCustom(_ text: String) -> Bool {
    guard !text.isEmpty else { return true }
    let item = NativeComboboxItem(
      id: -1, title: text, disabled: false, value: .string(text), raw: .string(text))
    return select(item, replacingMatch: true)
  }

  /// 选择后的模型必须能被同一计划重读；满额仍可移除或替换已有项。
  private mutating func select(_ item: NativeComboboxItem, replacingMatch: Bool) -> Bool {
    if multiple {
      if let index = selected.firstIndex(where: { NativeFormValues.equal($0.value, item.value) }) {
        selected.remove(at: index)
        if replacingMatch { selected.append(item) }
      } else {
        guard selected.count < Self.maximumItems else { return false }
        selected.append(item)
      }
    } else {
      guard (output(item).array?.count ?? 0) <= Self.maximumItems else { return false }
      selected = [item]
    }
    edited = true
    return true
  }

  /// 保存投影与容量检查使用同一值，以免单选数组绕过重读边界。
  private func output(_ item: NativeComboboxItem) -> PluginJSONValue {
    returnsObject ? item.raw : item.value
  }

  /// 删除由原生明确动作触发；不因搜索过滤而丢失当前项。
  public mutating func remove(at index: Int) {
    guard selected.indices.contains(index), !selected[index].disabled else { return }
    selected.remove(at: index)
    edited = true
  }

  /// clearable 是清空入口的实际门禁，单选输出 null，多选输出空数组。
  public mutating func clear() {
    guard clearable else { return }
    selected = []
    edited = true
  }

  /// Boolean 属性仅接受已实现的 JSON 类型，别把字符串 false 错当成真正的 false。
  private static func flag(
    _ props: [String: PluginJSONValue], _ key: String, alias: String? = nil, default fallback: Bool
  ) throws -> Bool {
    if let alias, props[key] != nil, props[alias] != nil {
      throw NativeComboboxError.unsupported(key)
    }
    guard let value = props[key] ?? alias.flatMap({ props[$0] }) else { return fallback }
    switch value {
    case .bool(let value): return value
    case .null: return false
    default: throw NativeComboboxError.unsupported(key)
    }
  }

  /// 标准 item props 只实现实际 title/value/disabled；事件、样式行为和嵌套选项不假装兼容。
  private static func item(
    _ raw: PluginJSONValue, id: Int, titlePath: ComboboxProperty, valuePath: ComboboxProperty,
    pointer: String
  ) throws -> NativeComboboxItem {
    var title = titlePath.read(raw) ?? raw
    var value = valuePath.read(raw) ?? title
    var disabled = false
    if let children = raw[exactKey: "children"], children.array?.isEmpty == false {
      throw NativeComboboxError.unsupported(pointer + "/children")
    }
    if let props = raw[exactKey: "props"], props != .null {
      guard case .object(let fields) = props,
        Set(fields.keys).isSubset(of: ["title", "value", "disabled"])
      else { throw NativeComboboxError.unsupported(pointer + "/props") }
      if let replacement = props[exactKey: "title"] { title = replacement }
      if let replacement = props[exactKey: "value"] { value = replacement }
      disabled = try flag(fields, "disabled", default: false)
    }
    return .init(id: id, title: display(title), disabled: disabled, value: value, raw: raw)
  }

  /// 标量/数组标题采用原生展示；数字保留词法，不能为模拟 JS 浮点展示而先丢失精度。
  private static func display(_ value: PluginJSONValue) -> String {
    switch value {
    case .null: ""
    case .string(let value): value
    case .number(let value): value.rawValue
    case .bool(let value): value ? "true" : "false"
    case .array(let values): values.map(display).joined(separator: ",")
    case .object: "[object Object]"
    }
  }
}

/// Vuetify JSON 属性路径投影：完整直接键优先，随后才解析点/方括号或显式路径数组。
private struct ComboboxProperty: Sendable {
  private let selector: PluginJSONValue

  /// 只接受数据路径，不执行函数或任意表达式；重复别名明确诊断。
  init(_ props: [String: PluginJSONValue], key: String, alias: String, fallback: String) throws {
    if props[key] != nil, props[alias] != nil { throw NativeComboboxError.unsupported(key) }
    selector = props[key] ?? props[alias] ?? .string(fallback)
    switch selector {
    case .string, .bool, .null: break
    case .array(let parts):
      guard parts.count <= 64,
        parts.allSatisfy({ part in
          if case .string = part { return true }
          if case .number(let number) = part { return Int(number.rawValue) != nil }
          return false
        })
      else { throw NativeComboboxError.unsupported(key) }
    default: throw NativeComboboxError.unsupported(key)
    }
  }

  /// 原始标量使用调用方 fallback；布尔 true 表示整个项目本身。
  func read(_ raw: PluginJSONValue) -> PluginJSONValue? {
    if selector == .bool(true) { return raw }
    if selector == .bool(false) || selector == .null { return nil }
    guard raw.array != nil || raw.object != nil else { return nil }
    let parts: [String]
    if let path = selector.string {
      guard !path.isEmpty else { return nil }
      if let direct = member(raw, key: path) { return direct }
      var normalized = path.replacingOccurrences(
        of: "\\[([A-Za-z0-9_]+)\\]", with: ".$1", options: .regularExpression)
      if normalized.hasPrefix(".") { normalized.removeFirst() }
      parts = normalized.components(separatedBy: ".")
    } else if let path = selector.array {
      parts = path.map { $0.string ?? NativeFormField.text(from: $0) }
    } else {
      return nil
    }
    var current = raw
    for part in parts {
      guard let next = member(current, key: part) else { return nil }
      current = next
    }
    return current
  }

  /// 只访问实际 JSON 成员，不暴露 JS 原型或宿主对象。
  private func member(_ value: PluginJSONValue, key: String) -> PluginJSONValue? {
    if let member = value[exactKey: key] { return member }
    if let array = value.array, let index = Int(key), String(index) == key,
      array.indices.contains(index)
    {
      return array[index]
    }
    return nil
  }
}
