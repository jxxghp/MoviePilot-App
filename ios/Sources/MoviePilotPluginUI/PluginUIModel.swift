import Foundation

/// 表面决定旧解释器的语义；不能把表单表达式套用于静态数据页/仪表板。
public enum PluginUISurface: String, Equatable, Sendable { case form, page, dashboard }

/// absent 仅用于仪表板合法的 null 响应；invalid 不能成为空配置成功页。
public enum PluginUIRenderMode: String, Equatable, Sendable {
  case vuetify, vue, absent, invalid
}

/// 组件分类只描述需要哪类原生适配，不表示已经实现对应控件。
public enum PluginUIComponentFamily: String, Equatable, Sendable {
  case layout, input, display, table, chart, image, icon, navigation, editor, web, unknown
}

/// 有位置的结构/能力诊断；不附带可能含凭据的属性值或正文。
public struct PluginUIDiagnostic: Equatable, Sendable {
  public let code: PluginUIDiagnosticCode
  public let severity: PluginUIDiagnosticSeverity
  public let pointer: String
}

/// 错误类型供本机 UI 显示受控文案，不拼接原始载荷。
public enum PluginUIDiagnosticCode: String, Equatable, Sendable {
  case invalidRoot, invalidField, invalidRenderMode, missingComponent, unknownComponent
  case invalidBinding, invalidEvent, unsupportedDirective, legacyIgnored
  case expressionRequired, scriptRequired, htmlRequired, webComponentRequired, remoteRequired
}

/// 结构错误与延期能力分开记录；警告不是完成原生渲染的许可。
public enum PluginUIDiagnosticSeverity: String, Equatable, Sendable {
  case information, warning, error
}

/// 下游渲染器必须逐项实现的能力；本模块不提供 canSave/canRender 的假成功开关。
public enum PluginUIRequirement: Equatable, Hashable, Sendable {
  case component(String)
  case property(component: String, name: String)
  case modelBinding, expression, scriptHandler, html, namedSlots, apiAction, remoteModule
}

/// 旧 FormRender 的绑定别名；field 是完整原始键，不按点号拆分。
public struct PluginUIBinding: Equatable, Sendable {
  public let property: String
  public let field: String
  public let kind: PluginUIBindingKind
  public let pointer: String
}

/// modelvalue 更新 value，其它默认绑定更新 modelValue；普通属性只读。
public enum PluginUIBindingKind: Equatable, Sendable {
  case modelValue, value
  case named(String)
  case implicitRead
}

/// 声明式 API 动作仅保存协议，不执行请求，也不据此推导实例身份。
public struct PluginUIEvent: Equatable, Sendable {
  public let name: String
  public let api: String?
  public let declaredMethod: String?
  public let parameters: PluginJSONValue?
  public let pointer: String
  public let raw: PluginJSONValue

  /// 显式暴露旧 PageRender 的方法投影，避免以后把 DELETE 声明误执行为 DELETE。
  public var legacyWireMethod: String? {
    guard let method = declaredMethod, !method.isEmpty else { return nil }
    return method.uppercased() == "GET" ? "GET" : "POST"
  }
}

/// 槽同时保留原结构和递归索引；消费者仍须按所属表面的旧渲染规则决定有效性。
public struct PluginUISlot: Equatable, Sendable {
  public let name: String
  public let pointer: String
  public let nodes: [PluginUINode]
  public let raw: PluginJSONValue
}

/// 无损文档中的结构索引，不是已经求值的可见性/布局/保存计划。
public struct PluginUINode: Equatable, Sendable {
  public let pointer: String
  public let component: String?
  public let family: PluginUIComponentFamily
  public let properties: [String: PluginJSONValue]
  public let children: [PluginUINode]
  public let slots: [PluginUISlot]
  public let bindings: [PluginUIBinding]
  public let events: [PluginUIEvent]
  public let raw: PluginJSONValue

  /// 缺失、空值与文本原样区分；内容优先级由对应表面渲染器实现。
  public var text: PluginJSONValue? { raw.object?["text"] }

  /// HTML 仅作为数据保存，不能直接交给主程序的网页或脚本运行时。
  public var html: PluginJSONValue? { raw.object?["html"] }
}

/// 保留原始响应、完整模型与节点诊断；未知数据不能在保存时被过滤。
public struct PluginUIDocument: Equatable, Sendable {
  public let surface: PluginUISurface
  public let renderMode: PluginUIRenderMode
  public let rawData: Data
  public let raw: PluginJSONValue
  public let model: [String: PluginJSONValue]?
  public let nodes: [PluginUINode]
  public let diagnostics: [PluginUIDiagnostic]
  public let requirements: Set<PluginUIRequirement>

  /// 只反映结构是否有错误，不能代替实际组件、表达式、权限和保存门禁。
  public var isStructurallyValid: Bool { !diagnostics.contains { $0.severity == .error } }

  /// 绑定读取必须使用原始键，字段名含点号或组合 Unicode 时也不能误读其它字段。
  public func value(forExactModelField field: String) -> PluginJSONValue? {
    guard let model else { return nil }
    return PluginJSONValue.object(model)[exactKey: field]
  }
}

/// 节点预算独立于 JSON 值预算，阻止大量很小的组件消耗 UI 资源。
public enum PluginUIDecodingError: Error, Equatable, Sendable {
  case invalidNodeLimit
  case invalidResponseEnvelope
  case nodeLimitExceeded(pointer: String)
  case pathLimitExceeded
}

/// JSON Pointer 编码集中处理，键里的斜线/波浪号不会造成定位歧义。
enum PluginJSONPointer {
  /// root 为空字符串；每次追加真实的对象键或数组索引。
  static func appending(_ key: String, to pointer: String) -> String {
    pointer + "/"
      + key.replacingOccurrences(of: "~", with: "~0")
      .replacingOccurrences(of: "/", with: "~1")
  }
}
