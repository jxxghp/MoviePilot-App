import Foundation

/// 三种既有 JSON 响应的显式入口，不猜测响应包装，也不启动渲染或动作。
public enum PluginUIDecoder {
  /// 原文和未知值随文档保留；结构错误形成诊断，资源越界/取消则整体失败。
  public static func decode(
    _ data: Data, surface: PluginUISurface, limits: PluginJSONLimits = .standard,
    maximumNodes: Int = 10_000
  ) throws -> PluginUIDocument {
    guard (1...50_000).contains(maximumNodes) else {
      throw PluginUIDecodingError.invalidNodeLimit
    }
    let raw = try PluginJSONReader.parse(data, limits: limits)
    var projection = PluginUIProjection(surface: surface, maximumNodes: maximumNodes)
    let fields = raw.object
    let mode: PluginUIRenderMode
    if surface == .dashboard, raw == .null {
      mode = .absent
    } else if let fields {
      mode = projection.mode(fields["render_mode"])
    } else {
      mode = .invalid
      projection.issue(.invalidRoot, .error, "")
    }
    let model = fields?["model"]?.object
    if surface == .form, fields != nil, model == nil {
      projection.issue(.invalidField, .error, "/model")
    }
    projection.model = model ?? [:]
    var nodes: [PluginUINode] = []
    if mode == .vuetify, let fields {
      let key = surface == .form ? "conf" : surface == .page ? "page" : "elements"
      if let items = fields[key]?.array {
        nodes = try projection.nodes(items, pointer: "/" + key)
      } else if surface == .dashboard, fields[key] == .null {
        projection.issue(.legacyIgnored, .information, "/" + key)
      } else {
        projection.issue(.invalidField, .error, "/" + key)
      }
      if surface == .dashboard {
        for key in ["attrs", "cols"] where fields[key] != nil && fields[key]?.object == nil {
          projection.issue(.invalidField, .error, "/" + key)
        }
      }
    } else if mode == .vue {
      projection.requirements.insert(.remoteModule)
      projection.issue(.remoteRequired, .information, "/render_mode")
    }
    return PluginUIDocument(
      surface: surface, renderMode: mode, rawData: data, raw: raw, model: model,
      nodes: nodes, diagnostics: projection.diagnostics, requirements: projection.requirements)
  }
}

/// 一次解码的局部状态，不能跨插件/实例共享模型、诊断或节点计数。
struct PluginUIProjection {
  let surface: PluginUISurface
  let maximumNodes: Int
  var model: [String: PluginJSONValue] = [:]
  var diagnostics: [PluginUIDiagnostic] = []
  var requirements: Set<PluginUIRequirement> = []
  private var nodeCount = 0
  private var pathBytes = 0

  /// 状态完全归属本次解析，避免多个插件并发解析时串用字段。
  init(surface: PluginUISurface, maximumNodes: Int) {
    self.surface = surface
    self.maximumNodes = maximumNodes
  }

  /// 只有仪表板沿用前端缺模式时的默认；表单/数据页必须有明确合法模式。
  mutating func mode(_ raw: PluginJSONValue?) -> PluginUIRenderMode {
    if surface == .dashboard, raw == nil || raw == .null || raw == .string("") {
      return .vuetify
    }
    if raw == .string("vuetify") { return .vuetify }
    if raw == .string("vue") { return .vue }
    issue(.invalidRenderMode, .error, "/render_mode")
    return .invalid
  }

  /// 原数组次序即节点索引次序，错误节点仍保留原始值。
  mutating func nodes(_ values: [PluginJSONValue], pointer: String) throws -> [PluginUINode] {
    try values.enumerated().map { index, value in
      try node(value, pointer: path(String(index), to: pointer))
    }
  }

  /// 提取结构索引而不解释条件/HTML/脚本；实际可见性和槽优先级不在这里求值。
  private mutating func node(_ raw: PluginJSONValue, pointer: String) throws -> PluginUINode {
    try Task.checkCancellation()
    nodeCount += 1
    guard nodeCount <= maximumNodes else {
      throw PluginUIDecodingError.nodeLimitExceeded(pointer: pointer)
    }
    let fields = raw.object ?? [:]
    if raw.object == nil { issue(.invalidField, .error, pointer) }
    let component = fields["component"]?.string
    let componentPointer = try path("component", to: pointer)
    let family = component.map(PluginComponentCatalog.family(for:)) ?? .unknown
    if let component, !component.isEmpty {
      requirements.insert(.component(component))
      if family == .unknown { issue(.unknownComponent, .warning, componentPointer) }
      if family == .web { issue(.webComponentRequired, .warning, componentPointer) }
    } else {
      issue(.missingComponent, .error, componentPointer)
    }
    var properties: [String: PluginJSONValue] = [:]
    let propsPointer = try path("props", to: pointer)
    if let props = fields["props"] {
      if let object = props.object {
        properties = object
      } else if props != .null || surface == .form {
        issue(.invalidField, .error, propsPointer)
      }
    }
    let bindings = try bindings(properties, component: component ?? "", pointer: propsPointer)
    var children: [PluginUINode] = []
    if let content = fields["content"] {
      let p = try path("content", to: pointer)
      if let values = content.array {
        children = try nodes(values, pointer: p)
      } else if content != .null {
        issue(.invalidField, .error, p)
      }
    }
    var slots: [PluginUISlot] = []
    if let rawSlots = fields["slots"] {
      let p = try path("slots", to: pointer)
      if let values = rawSlots.object {
        if !values.isEmpty { requirements.insert(.namedSlots) }
        if surface == .page { issue(.legacyIgnored, .information, p) }
        for key in values.keys.sorted() {
          try Task.checkCancellation()
          guard let value = values[key] else { continue }
          let slotPointer = try path(key, to: p)
          let inner: [PluginUINode]
          if let array = value.array {
            inner = try nodes(array, pointer: slotPointer)
          } else if value.object != nil {
            inner = [try node(value, pointer: slotPointer)]
            if surface != .form { issue(.legacyIgnored, .warning, slotPointer) }
          } else {
            inner = []
            issue(.invalidField, .error, slotPointer)
          }
          slots.append(.init(name: key, pointer: slotPointer, nodes: inner, raw: value))
        }
      } else if rawSlots != .null || surface == .form {
        issue(.invalidField, .error, p)
      }
    }
    if let html = fields["html"], html != .null, html != .string("") {
      requirements.insert(.html)
      issue(.htmlRequired, .warning, try path("html", to: pointer))
    }
    let events = try events(fields["events"], pointer: path("events", to: pointer))
    return PluginUINode(
      pointer: pointer, component: component, family: family, properties: properties,
      children: children, slots: slots, bindings: bindings, events: events, raw: raw)
  }

  /// 严格遵循 FormRender 的分支顺序；绑定键值不拆路径、不进行隐式类型转换。
  private mutating func bindings(
    _ properties: [String: PluginJSONValue], component: String, pointer: String
  ) throws -> [PluginUIBinding] {
    var result: [PluginUIBinding] = []
    for key in properties.keys.sorted() {
      try Task.checkCancellation()
      guard let value = properties[key] else { continue }
      requirements.insert(.property(component: component, name: key))
      let p = try path(key, to: pointer)
      if key == "innerHTML" {
        requirements.insert(.html)
        issue(.htmlRequired, .warning, p)
      }
      guard surface == .form else {
        if key.hasPrefix("v-") || key.hasPrefix(":") {
          issue(.unsupportedDirective, .warning, p)
        }
        continue
      }
      let bindingKind: PluginUIBindingKind?
      if key == "modelvalue" {
        bindingKind = .value
      } else if key == "model" || key == "v-model" {
        bindingKind = .modelValue
      } else if key.hasPrefix("model:") || key.hasPrefix("v-model:") {
        let suffix = String(key.split(separator: ":", omittingEmptySubsequences: false)[1])
        bindingKind = suffix.isEmpty ? nil : .named(suffix)
        if suffix.isEmpty {
          issue(.invalidBinding, .error, p)
          continue
        }
      } else {
        bindingKind = nil
      }
      if let bindingKind {
        guard let field = value.string else {
          issue(.invalidBinding, .error, p)
          continue
        }
        result.append(.init(property: key, field: field, kind: bindingKind, pointer: p))
        requirements.insert(.modelBinding)
      } else if key == "show" || key == "v-show" {
        if value.string == nil { issue(.invalidField, .error, p) }
        requirements.insert(.expression)
        issue(.expressionRequired, .information, p)
      } else if key.hasPrefix("on") {
        if value.string != nil {
          requirements.insert(.scriptHandler)
          issue(.scriptRequired, .warning, p)
        } else {
          issue(.legacyIgnored, .information, p)
        }
      } else if let string = value.string, string.hasPrefix("{{"), string.hasSuffix("}}") {
        requirements.insert(.expression)
        issue(.expressionRequired, .information, p)
      } else if let field = value.string, PluginJSONValue.object(model)[exactKey: field] != nil {
        result.append(.init(property: key, field: field, kind: .implicitRead, pointer: p))
        requirements.insert(.modelBinding)
      } else if key.hasPrefix("v-") || key.hasPrefix(":") {
        issue(.unsupportedDirective, .warning, p)
      }
    }
    return result
  }

  /// API 事件始终保留；只有数据页解释器真正使用该字段，不能为其它表面凭空启用。
  private mutating func events(_ raw: PluginJSONValue?, pointer: String) throws -> [PluginUIEvent] {
    guard let raw else { return [] }
    if raw == .null { return [] }
    guard let values = raw.object else {
      issue(.invalidEvent, .error, pointer)
      return []
    }
    if surface == .page, !values.isEmpty {
      requirements.insert(.apiAction)
    } else if !values.isEmpty {
      issue(.legacyIgnored, .information, pointer)
    }
    return try values.keys.sorted().compactMap { name in
      try Task.checkCancellation()
      guard let value = values[name] else { return nil }
      let p = try path(name, to: pointer)
      let fields = value.object
      let api = fields?["api"]?.string
      let method = fields?["method"]?.string
      if api?.isEmpty != false || method?.isEmpty != false { issue(.invalidEvent, .error, p) }
      return PluginUIEvent(
        name: name, api: api, declaredMethod: method, parameters: fields?["params"],
        pointer: p, raw: value)
    }
  }

  /// 限制结构键、单条路径及路径总量，防止长前缀在大量后代节点中被成倍复制。
  private mutating func path(_ key: String, to parent: String) throws -> String {
    guard key.utf8.count <= 1024 else { throw PluginUIDecodingError.pathLimitExceeded }
    let result = PluginJSONPointer.appending(key, to: parent)
    let count = result.utf8.count
    guard count <= 4096, pathBytes <= 4 * 1024 * 1024 - count else {
      throw PluginUIDecodingError.pathLimitExceeded
    }
    pathBytes += count
    return result
  }

  /// 固定诊断码和位置，不复制原始属性内容；调用方不能自动把路径写入公开日志。
  mutating func issue(
    _ code: PluginUIDiagnosticCode, _ severity: PluginUIDiagnosticSeverity, _ pointer: String
  ) {
    diagnostics.append(.init(code: code, severity: severity, pointer: pointer))
  }
}
