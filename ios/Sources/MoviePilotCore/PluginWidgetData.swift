import CoreFoundation
import Darwin
import Foundation

/// 插件桌面小组件的预设模板或声明式自定义布局形态。
public enum PluginWidgetKind: String, Codable, CaseIterable, Sendable {
  case metrics
  case list
  case poster
  case nowPlaying
  case custom
  case pluginLaunch = "plugin_launch"

  /// 对未知未来枚举平滑回退至指标网格，避免单个插件升级阻断目录解析。
  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: raw) ?? .metrics
  }
}

/// 插件桌面小组件目录条目的声明来源。
public enum PluginWidgetSource: String, Codable, Sendable {
  case widget
  case dashboard
  case runtime

  /// 对未知来源标记统一归类为专属小组件来源。
  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: raw) ?? .widget
  }
}

/// 已启用插件或本地运行态可供桌面绑定的单个小组件描述。
public struct PluginWidgetDescriptor: Codable, Equatable, Hashable, Sendable {
  public let pluginId: String
  public let pluginName: String
  public let widgetKey: String
  public let name: String
  public let description: String?
  public let kind: PluginWidgetKind
  public let source: PluginWidgetSource
  public let hasPage: Bool

  /// 构造插件桌面小组件目录描述项。
  public init(
    pluginId: String,
    pluginName: String,
    widgetKey: String = "",
    name: String,
    description: String? = nil,
    kind: PluginWidgetKind = .metrics,
    source: PluginWidgetSource = .widget,
    hasPage: Bool = false
  ) {
    self.pluginId = pluginId
    self.pluginName = pluginName
    self.widgetKey = widgetKey
    self.name = name
    self.description = description
    self.kind = kind
    self.source = source
    self.hasPage = hasPage
  }

  /// 组合插件标识与子键的稳定唯一定位键（`"\(pluginId)::\(widgetKey)"`）。
  public var compositeKey: String {
    Self.makeCompositeKey(pluginId: pluginId, widgetKey: widgetKey)
  }

  /// 生成跨目录与运行态缓存统一的复合键。
  public static func makeCompositeKey(pluginId: String, widgetKey: String) -> String {
    "\(pluginId.trimmingCharacters(in: .whitespacesAndNewlines))::\(widgetKey.trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  /// 从复合键拆分 `(pluginId, widgetKey)`，格式非法时返回 `nil`。
  public static func parseCompositeKey(_ raw: String) -> (pluginId: String, widgetKey: String)? {
    let parts = raw.components(separatedBy: "::")
    guard parts.count == 2 else { return nil }
    let pid = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let key = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard PluginWidgetValidator.isValidPluginId(pid),
      PluginWidgetValidator.isValidWidgetKey(key)
    else { return nil }
    return (pid, key)
  }

  /// 校验插件标识、小组件子键与展示文本长度边界。
  fileprivate func validate() throws {
    guard PluginWidgetValidator.isValidPluginId(pluginId),
      PluginWidgetValidator.isValidWidgetKey(widgetKey)
    else { throw WidgetDataError.invalidData }
    try PluginWidgetValidator.text(pluginName, maximum: 120)
    try PluginWidgetValidator.text(name, maximum: 120)
    if let description {
      try PluginWidgetValidator.text(description, maximum: 240, allowEmpty: true)
    }
  }
}

/// 专用只读凭据拉取的已启用插件桌面小组件目录。
public struct PluginWidgetCatalog: Codable, Equatable, Sendable {
  public static let maximumBytes = 32 * 1024
  public let version: Int
  public let owner: String
  public let generatedAt: TimeInterval
  public let expiresAt: TimeInterval
  public let widgets: [PluginWidgetDescriptor]

  /// 构造经校验的插件桌面小组件目录。
  public init(
    version: Int = 1,
    owner: String,
    generatedAt: TimeInterval,
    expiresAt: TimeInterval,
    widgets: [PluginWidgetDescriptor]
  ) throws {
    self.version = version
    self.owner = owner
    self.generatedAt = generatedAt
    self.expiresAt = expiresAt
    self.widgets = widgets
    try validate()
  }

  private enum CodingKeys: String, CodingKey {
    case version, owner, generatedAt, expiresAt, widgets
  }

  /// 解码时强制核验协议版本、身份格式、时间窗口与数量上限。
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      version: container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
      owner: container.decode(String.self, forKey: .owner),
      generatedAt: container.decode(TimeInterval.self, forKey: .generatedAt),
      expiresAt: container.decode(TimeInterval.self, forKey: .expiresAt),
      widgets: container.decodeIfPresent([PluginWidgetDescriptor].self, forKey: .widgets) ?? []
    )
  }

  /// 按字节上限、当前账号身份与时钟窗口解码目录响应。
  public static func decode(_ data: Data, owner: String, now: Date = Date()) throws
    -> PluginWidgetCatalog
  {
    guard data.count <= maximumBytes else { throw WidgetDataError.oversizedData }
    let catalog: PluginWidgetCatalog
    do {
      catalog = try JSONDecoder().decode(Self.self, from: data)
    } catch let error as WidgetDataError {
      throw error
    } catch {
      throw WidgetDataError.invalidData
    }
    guard catalog.owner == owner else { throw WidgetDataError.ownerMismatch }
    guard now.timeIntervalSince1970.isFinite,
      catalog.generatedAt <= now.timeIntervalSince1970 + 300
    else { throw WidgetDataError.invalidData }
    return catalog
  }

  /// 重新编码白名单字段，剥离任何未知附加属性。
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(self)
    guard data.count <= Self.maximumBytes else { throw WidgetDataError.oversizedData }
    return data
  }

  /// 判断目录在给定时间点是否已过期。
  public func isExpired(at now: Date) -> Bool {
    let ts = now.timeIntervalSince1970
    return !ts.isFinite || ts < generatedAt - 300 || ts >= expiresAt
  }

  private func validate() throws {
    guard version == 1 else { throw WidgetDataError.unsupportedVersion }
    try PluginWidgetValidator.owner(owner)
    try PluginWidgetValidator.timestamp(generatedAt)
    try PluginWidgetValidator.timestamp(expiresAt)
    guard expiresAt > generatedAt, expiresAt - generatedAt <= 86_400, widgets.count <= 64 else {
      throw WidgetDataError.invalidData
    }
    for item in widgets { try item.validate() }
  }
}

/// 插件小组件预设模板中的单项指标。
public struct PluginWidgetMetricItem: Codable, Equatable, Sendable {
  public let id: String
  public let label: String
  public let value: String
  public let subValue: String?
  public let icon: String?
  public let tone: String?

  /// 构造插件预设指标项。
  public init(
    id: String,
    label: String,
    value: String,
    subValue: String? = nil,
    icon: String? = nil,
    tone: String? = nil
  ) {
    self.id = id
    self.label = label
    self.value = value
    self.subValue = subValue
    self.icon = icon
    self.tone = tone
  }
}

/// 插件小组件预设列表模板中的单行条目。
public struct PluginWidgetListItem: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let trailing: String?
  public let progress: Double?

  /// 构造插件预设列表条目，自动将非法进度裁剪或置空。
  public init(
    id: String,
    title: String,
    subtitle: String? = nil,
    trailing: String? = nil,
    progress: Double? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.trailing = trailing
    if let progress, progress.isFinite, (0...1).contains(progress) {
      self.progress = progress
    } else {
      self.progress = nil
    }
  }
}

/// 自定义布局按钮声明的受限交互动作。
public struct PluginWidgetAction: Codable, Equatable, Sendable {
  public let type: String
  public let surface: String?
  public let route: String?
  public let actionId: String?

  /// 构造按钮交互动作。
  public init(
    type: String = "openPlugin",
    surface: String? = "data",
    route: String? = nil,
    actionId: String? = nil
  ) {
    self.type = type
    self.surface = surface
    self.route = route
    self.actionId = actionId
  }
}

/// 声明式自定义插件小组件布局树节点（最大递归深度 5 层，单卡片总节点不超过 40 个）。
public struct PluginWidgetNode: Codable, Equatable, Sendable {
  public static let maxDepth = 5
  public static let maxNodes = 40

  public let type: String
  public let text: String?
  public let label: String?
  public let valueText: String?
  public let subValue: String?
  public let name: String?
  public let size: String?
  public let weight: String?
  public let align: String?
  public let justify: String?
  public let style: String?
  public let tone: String?
  public let gap: Double?
  public let padding: Double?
  public let cornerRadius: Double?
  public let width: Double?
  public let height: Double?
  public let flex: Double?
  public let maxLines: Int?
  public let progressValue: Double?
  public let minLength: Double?
  public let monospace: Bool?
  public let scrim: Bool?
  public let filled: Bool?
  public let url: String?
  public let backgroundUrl: String?
  public let action: PluginWidgetAction?
  public let children: [PluginWidgetNode]?

  /// 构造单个声明式自定义布局节点。
  public init(
    type: String,
    text: String? = nil,
    label: String? = nil,
    valueText: String? = nil,
    subValue: String? = nil,
    name: String? = nil,
    size: String? = nil,
    weight: String? = nil,
    align: String? = nil,
    justify: String? = nil,
    style: String? = nil,
    tone: String? = nil,
    gap: Double? = nil,
    padding: Double? = nil,
    cornerRadius: Double? = nil,
    width: Double? = nil,
    height: Double? = nil,
    flex: Double? = nil,
    maxLines: Int? = nil,
    progressValue: Double? = nil,
    minLength: Double? = nil,
    monospace: Bool? = nil,
    scrim: Bool? = nil,
    filled: Bool? = nil,
    url: String? = nil,
    backgroundUrl: String? = nil,
    action: PluginWidgetAction? = nil,
    children: [PluginWidgetNode]? = nil
  ) {
    self.type = type
    self.text = text
    self.label = label
    self.valueText = valueText
    self.subValue = subValue
    self.name = name
    self.size = size
    self.weight = weight
    self.align = align
    self.justify = justify
    self.style = style
    self.tone = tone
    self.gap = gap
    self.padding = padding
    self.cornerRadius = cornerRadius
    self.width = width
    self.height = height
    self.flex = flex
    self.maxLines = maxLines
    self.progressValue = progressValue
    self.minLength = minLength
    self.monospace = monospace
    self.scrim = scrim
    self.filled = filled
    self.url = url
    self.backgroundUrl = backgroundUrl
    self.action = action
    self.children = children
  }

  private enum CodingKeys: String, CodingKey {
    case type, text, label, value, valueText, subValue, name, size, weight, align, justify, style
    case tone, gap, padding, radius, cornerRadius, width, height, flex, maxLines, minLength
    case monospace, tabularNums, scrim, filled, url, backgroundUrl, action, children
  }

  /// 兼容 `metric.value`（字符串）与 `progress.value`（`0...1` 浮点）的双形态解码。
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
    text = try c.decodeIfPresent(String.self, forKey: .text)
    label = try c.decodeIfPresent(String.self, forKey: .label)
    subValue = try c.decodeIfPresent(String.self, forKey: .subValue)
    name = try c.decodeIfPresent(String.self, forKey: .name)
    size = try c.decodeIfPresent(String.self, forKey: .size)
    weight = try c.decodeIfPresent(String.self, forKey: .weight)
    align = try c.decodeIfPresent(String.self, forKey: .align)
    justify = try c.decodeIfPresent(String.self, forKey: .justify)
    style = try c.decodeIfPresent(String.self, forKey: .style)
    tone = try c.decodeIfPresent(String.self, forKey: .tone)
    gap = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .gap), low: 0, high: 32)
    padding = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .padding), low: 0, high: 32)
    let rawCorner =
      try c.decodeIfPresent(Double.self, forKey: .cornerRadius)
      ?? c.decodeIfPresent(Double.self, forKey: .radius)
    cornerRadius = Self.clamp(rawCorner, low: 0, high: 32)
    width = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .width), low: 8, high: 360)
    height = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .height), low: 8, high: 360)
    flex = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .flex), low: 0, high: 10)
    if let rawMax = try c.decodeIfPresent(Int.self, forKey: .maxLines) {
      maxLines = min(max(rawMax, 1), 6)
    } else {
      maxLines = nil
    }
    minLength = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .minLength), low: 0, high: 64)
    let mono =
      try c.decodeIfPresent(Bool.self, forKey: .monospace)
      ?? c.decodeIfPresent(Bool.self, forKey: .tabularNums)
    monospace = mono
    scrim = try c.decodeIfPresent(Bool.self, forKey: .scrim)
    let explicitFilled = try c.decodeIfPresent(Bool.self, forKey: .filled)
    filled = explicitFilled ?? (style == "filled" ? true : nil)
    url = try c.decodeIfPresent(String.self, forKey: .url)
    backgroundUrl = try c.decodeIfPresent(String.self, forKey: .backgroundUrl)
    action = try c.decodeIfPresent(PluginWidgetAction.self, forKey: .action)
    children = try c.decodeIfPresent([PluginWidgetNode].self, forKey: .children)

    let explicitValueText = try c.decodeIfPresent(String.self, forKey: .valueText)
    if let numericValue = try? c.decodeIfPresent(Double.self, forKey: .value),
      numericValue.isFinite
    {
      if type == "progress" {
        progressValue = min(max(numericValue, 0), 1)
        valueText = explicitValueText
      } else {
        progressValue = (0...1).contains(numericValue) ? numericValue : nil
        valueText = explicitValueText ?? String(numericValue)
      }
    } else if let strValue = try? c.decodeIfPresent(String.self, forKey: .value) {
      valueText = explicitValueText ?? strValue
      if type == "progress", let parsed = Double(strValue), parsed.isFinite {
        progressValue = min(max(parsed, 0), 1)
      } else {
        progressValue = nil
      }
    } else {
      valueText = explicitValueText
      progressValue = nil
    }
  }

  /// 编码回标准 JSON 结构，保持磁盘缓存可再次无损解码。
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(type, forKey: .type)
    try c.encodeIfPresent(text, forKey: .text)
    try c.encodeIfPresent(label, forKey: .label)
    if type == "progress" {
      try c.encodeIfPresent(progressValue, forKey: .value)
      try c.encodeIfPresent(valueText, forKey: .valueText)
    } else {
      try c.encodeIfPresent(valueText, forKey: .value)
      if let progressValue { try c.encode(progressValue, forKey: .value) }
    }
    try c.encodeIfPresent(subValue, forKey: .subValue)
    try c.encodeIfPresent(name, forKey: .name)
    try c.encodeIfPresent(size, forKey: .size)
    try c.encodeIfPresent(weight, forKey: .weight)
    try c.encodeIfPresent(align, forKey: .align)
    try c.encodeIfPresent(justify, forKey: .justify)
    try c.encodeIfPresent(style, forKey: .style)
    try c.encodeIfPresent(tone, forKey: .tone)
    try c.encodeIfPresent(gap, forKey: .gap)
    try c.encodeIfPresent(padding, forKey: .padding)
    try c.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
    try c.encodeIfPresent(width, forKey: .width)
    try c.encodeIfPresent(height, forKey: .height)
    try c.encodeIfPresent(flex, forKey: .flex)
    try c.encodeIfPresent(maxLines, forKey: .maxLines)
    try c.encodeIfPresent(minLength, forKey: .minLength)
    try c.encodeIfPresent(monospace, forKey: .monospace)
    try c.encodeIfPresent(scrim, forKey: .scrim)
    try c.encodeIfPresent(filled, forKey: .filled)
    try c.encodeIfPresent(url, forKey: .url)
    try c.encodeIfPresent(backgroundUrl, forKey: .backgroundUrl)
    try c.encodeIfPresent(action, forKey: .action)
    try c.encodeIfPresent(children, forKey: .children)
  }

  /// 对递归节点树执行最大深度 5 层、最大节点数 40 个的白名单裁剪。
  public func sanitized() -> PluginWidgetNode? {
    var budget = Self.maxNodes
    return Self.sanitizeNode(self, depth: 0, budget: &budget)
  }

  private static let allowedTypes: Set<String> = [
    "column", "row", "stack", "box", "text", "metric", "icon", "image",
    "progress", "badge", "button", "spacer", "divider",
  ]

  private static func sanitizeNode(
    _ node: PluginWidgetNode, depth: Int, budget: inout Int
  ) -> PluginWidgetNode? {
    guard depth <= maxDepth, budget > 0, allowedTypes.contains(node.type) else { return nil }
    budget -= 1
    var cleanChildren: [PluginWidgetNode]?
    if ["column", "row", "stack", "box"].contains(node.type), depth < maxDepth,
      let rawChildren = node.children
    {
      var built: [PluginWidgetNode] = []
      for child in rawChildren.prefix(16) {
        guard budget > 0 else { break }
        if let valid = sanitizeNode(child, depth: depth + 1, budget: &budget) {
          built.append(valid)
        }
      }
      cleanChildren = built
    }
    return PluginWidgetNode(
      type: node.type,
      text: node.text,
      label: node.label,
      valueText: node.valueText,
      subValue: node.subValue,
      name: node.name,
      size: node.size,
      weight: node.weight,
      align: node.align,
      justify: node.justify,
      style: node.style,
      tone: node.tone,
      gap: node.gap,
      padding: node.padding,
      cornerRadius: node.cornerRadius,
      width: node.width,
      height: node.height,
      flex: node.flex,
      maxLines: node.maxLines,
      progressValue: node.progressValue,
      minLength: node.minLength,
      monospace: node.monospace,
      scrim: node.scrim,
      filled: node.filled,
      url: node.url,
      backgroundUrl: node.backgroundUrl,
      action: node.action,
      children: cleanChildren
    )
  }

  private static func clamp(_ value: Double?, low: Double, high: Double) -> Double? {
    guard let value, value.isFinite else { return nil }
    return min(max(value, low), high)
  }
}

/// 单个插件桌面小组件的有界只读快照（同时兼容后端只读端点与前端运行态推送缓存）。
public struct PluginWidgetSnapshot: Codable, Equatable, Sendable {
  public static let maximumBytes = 32 * 1024

  public let version: Int
  public let owner: String
  public let generatedAt: TimeInterval
  public let expiresAt: TimeInterval
  public let pluginId: String
  public let pluginName: String
  public let widgetKey: String
  public let state: WidgetSectionState
  public let updatedAt: TimeInterval?
  public let kind: PluginWidgetKind
  public let title: String
  public let subtitle: String?
  public let accentHex: String?
  public let artworkFileName: String?
  public let imageUrl: String?
  public let metrics: [PluginWidgetMetricItem]
  public let items: [PluginWidgetListItem]
  public let layout: PluginWidgetNode?
  public let layouts: [String: PluginWidgetNode]?
  public let message: String?

  /// 构造插件小组件快照并自动清洗自定义节点树边界。
  public init(
    version: Int = 1,
    owner: String = "",
    generatedAt: TimeInterval = Date().timeIntervalSince1970,
    expiresAt: TimeInterval = Date().timeIntervalSince1970 + 86_400,
    pluginId: String,
    pluginName: String,
    widgetKey: String = "",
    state: WidgetSectionState = .ready,
    updatedAt: TimeInterval? = Date().timeIntervalSince1970,
    kind: PluginWidgetKind = .metrics,
    title: String,
    subtitle: String? = nil,
    accentHex: String? = nil,
    artworkFileName: String? = nil,
    imageUrl: String? = nil,
    metrics: [PluginWidgetMetricItem] = [],
    items: [PluginWidgetListItem] = [],
    layout: PluginWidgetNode? = nil,
    layouts: [String: PluginWidgetNode]? = nil,
    message: String? = nil
  ) {
    self.version = version
    self.owner = owner
    self.generatedAt = generatedAt
    self.expiresAt = expiresAt
    self.pluginId = pluginId
    self.pluginName = pluginName
    self.widgetKey = widgetKey
    self.state = state
    self.updatedAt = updatedAt
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
    self.accentHex = accentHex
    self.artworkFileName = artworkFileName
    self.imageUrl = imageUrl
    self.metrics = Array(metrics.prefix(8))
    self.items = Array(items.prefix(6))
    self.layout = layout?.sanitized()
    if let layouts {
      var cleaned: [String: PluginWidgetNode] = [:]
      for key in ["small", "medium", "large"] {
        if let tree = layouts[key]?.sanitized() {
          cleaned[key] = tree
        }
      }
      self.layouts = cleaned.isEmpty ? nil : cleaned
    } else {
      self.layouts = nil
    }
    self.message = message
  }

  private enum CodingKeys: String, CodingKey {
    case version, owner, generatedAt, expiresAt, pluginId, pluginName, widgetKey, state, updatedAt
    case kind, title, subtitle, accentHex, artworkFileName, imageUrl, metrics, items, layout
    case layouts, message
  }

  /// 支持后端严格响应与本地运行态推送快照的统一解码。
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let nowTs = Date().timeIntervalSince1970
    let pid = try c.decode(String.self, forKey: .pluginId)
    let pname = try c.decodeIfPresent(String.self, forKey: .pluginName) ?? pid
    let gen = try c.decodeIfPresent(TimeInterval.self, forKey: .generatedAt) ?? nowTs
    let exp = try c.decodeIfPresent(TimeInterval.self, forKey: .expiresAt) ?? (gen + 86_400)
    let upd = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt)
    self.init(
      version: try c.decodeIfPresent(Int.self, forKey: .version) ?? 1,
      owner: try c.decodeIfPresent(String.self, forKey: .owner) ?? "",
      generatedAt: gen,
      expiresAt: exp,
      pluginId: pid,
      pluginName: pname,
      widgetKey: try c.decodeIfPresent(String.self, forKey: .widgetKey) ?? "",
      state: try c.decodeIfPresent(WidgetSectionState.self, forKey: .state) ?? .ready,
      updatedAt: upd,
      kind: try c.decodeIfPresent(PluginWidgetKind.self, forKey: .kind) ?? .metrics,
      title: try c.decodeIfPresent(String.self, forKey: .title) ?? pname,
      subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
      accentHex: try c.decodeIfPresent(String.self, forKey: .accentHex),
      artworkFileName: try c.decodeIfPresent(String.self, forKey: .artworkFileName),
      imageUrl: try c.decodeIfPresent(String.self, forKey: .imageUrl),
      metrics: try c.decodeIfPresent([PluginWidgetMetricItem].self, forKey: .metrics) ?? [],
      items: try c.decodeIfPresent([PluginWidgetListItem].self, forKey: .items) ?? [],
      layout: try c.decodeIfPresent(PluginWidgetNode.self, forKey: .layout),
      layouts: try c.decodeIfPresent([String: PluginWidgetNode].self, forKey: .layouts),
      message: try c.decodeIfPresent(String.self, forKey: .message)
    )
  }

  /// 针对专用只读服务端响应执行严格的账号归属、体积与有效期核验。
  public static func decode(_ data: Data, owner: String, now: Date = Date()) throws
    -> PluginWidgetSnapshot
  {
    guard data.count <= maximumBytes else { throw WidgetDataError.oversizedData }
    let snapshot: PluginWidgetSnapshot
    do {
      snapshot = try JSONDecoder().decode(Self.self, from: data)
    } catch let error as WidgetDataError {
      throw error
    } catch {
      throw WidgetDataError.invalidData
    }
    guard snapshot.version == 1 else { throw WidgetDataError.unsupportedVersion }
    try PluginWidgetValidator.owner(snapshot.owner)
    guard snapshot.owner == owner else { throw WidgetDataError.ownerMismatch }
    try PluginWidgetValidator.timestamp(snapshot.generatedAt)
    try PluginWidgetValidator.timestamp(snapshot.expiresAt)
    guard PluginWidgetValidator.isValidPluginId(snapshot.pluginId),
      PluginWidgetValidator.isValidWidgetKey(snapshot.widgetKey),
      snapshot.expiresAt > snapshot.generatedAt,
      snapshot.expiresAt - snapshot.generatedAt <= 86_400,
      now.timeIntervalSince1970.isFinite,
      snapshot.generatedAt <= now.timeIntervalSince1970 + 300
    else { throw WidgetDataError.invalidData }
    return snapshot
  }

  /// 重新编码白名单结构并限制最大 32 KiB。
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(self)
    guard data.count <= Self.maximumBytes else { throw WidgetDataError.oversizedData }
    return data
  }

  /// 检查快照是否超出展示上限。
  public func isExpired(at now: Date) -> Bool {
    let ts = now.timeIntervalSince1970
    return !ts.isFinite || ts < generatedAt - 300 || ts >= expiresAt
  }

  /// 按桌面组件尺寸键（`"small"` / `"medium"` / `"large"`）选取匹配的自定义布局树。
  public func resolvedLayout(forSizeKey sizeKey: String) -> PluginWidgetNode? {
    layouts?[sizeKey] ?? layout
  }

  /// 有效新鲜度比较时间戳。
  public var effectiveTimestamp: TimeInterval {
    updatedAt ?? generatedAt
  }
}

/// 主 App 写入 App Group `"now_playing.json"` 的插件音频正在播放快照。
public struct NowPlayingWidgetSnapshot: Codable, Equatable, Sendable {
  public var active: Bool
  public var pluginId: String
  public var pluginName: String
  public var title: String
  public var artist: String
  public var album: String
  public var lyrics: String
  public var artworkFileName: String
  public var isPlaying: Bool
  public var liked: Bool
  public var hasLike: Bool
  public var canNext: Bool
  public var canPrevious: Bool
  public var durationMs: Int
  public var positionMs: Int
  public var updatedAt: TimeInterval

  /// 构造正在播放小组件快照。
  public init(
    active: Bool = false,
    pluginId: String = "",
    pluginName: String = "",
    title: String = "",
    artist: String = "",
    album: String = "",
    lyrics: String = "",
    artworkFileName: String = "",
    isPlaying: Bool = false,
    liked: Bool = false,
    hasLike: Bool = false,
    canNext: Bool = true,
    canPrevious: Bool = true,
    durationMs: Int = 0,
    positionMs: Int = 0,
    updatedAt: TimeInterval = 0
  ) {
    self.active = active
    self.pluginId = pluginId
    self.pluginName = pluginName
    self.title = title
    self.artist = artist
    self.album = album
    self.lyrics = lyrics
    self.artworkFileName = artworkFileName
    self.isPlaying = isPlaying
    self.liked = liked
    self.hasLike = hasLike
    self.canNext = canNext
    self.canPrevious = canPrevious
    self.durationMs = max(0, durationMs)
    self.positionMs = max(0, positionMs)
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case active, pluginId, pluginName, title, artist, album, lyrics, artworkFileName
    case isPlaying, liked, hasLike, canNext, canPrevious, durationMs, positionMs, updatedAt
  }

  /// 容错解码 `"now_playing.json"`，缺省字段平滑回退。
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      active: try c.decodeIfPresent(Bool.self, forKey: .active) ?? false,
      pluginId: try c.decodeIfPresent(String.self, forKey: .pluginId) ?? "",
      pluginName: try c.decodeIfPresent(String.self, forKey: .pluginName) ?? "",
      title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
      artist: try c.decodeIfPresent(String.self, forKey: .artist) ?? "",
      album: try c.decodeIfPresent(String.self, forKey: .album) ?? "",
      lyrics: try c.decodeIfPresent(String.self, forKey: .lyrics) ?? "",
      artworkFileName: try c.decodeIfPresent(String.self, forKey: .artworkFileName) ?? "",
      isPlaying: try c.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false,
      liked: try c.decodeIfPresent(Bool.self, forKey: .liked) ?? false,
      hasLike: try c.decodeIfPresent(Bool.self, forKey: .hasLike) ?? false,
      canNext: try c.decodeIfPresent(Bool.self, forKey: .canNext) ?? true,
      canPrevious: try c.decodeIfPresent(Bool.self, forKey: .canPrevious) ?? true,
      durationMs: try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0,
      positionMs: try c.decodeIfPresent(Int.self, forKey: .positionMs) ?? 0,
      updatedAt: try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
    )
  }

  /// 空闲默认态快照。
  public static let idle = NowPlayingWidgetSnapshot(active: false)
}

/// 桌面交互式小组件写入 `"pending_widget_command.json"` 并经由 Darwin 通知唤醒宿主的指令载荷。
public struct PendingWidgetCommand: Codable, Equatable, Sendable {
  public let id: String
  public let type: String
  public let command: String
  public let actionId: String
  public let pluginId: String
  public let widgetKey: String
  public let createdAt: TimeInterval
  public let updatedAt: TimeInterval

  /// 构造待由主 App 插件宿主消费的桌面小组件控制指令。
  public init(
    id: String = UUID().uuidString,
    type: String = "nowPlaying",
    command: String,
    actionId: String = "",
    pluginId: String,
    widgetKey: String = "",
    createdAt: TimeInterval = Date().timeIntervalSince1970
  ) {
    self.id = id
    self.type = type
    self.command = command
    self.actionId = actionId.isEmpty ? command : actionId
    self.pluginId = pluginId
    self.widgetKey = widgetKey
    self.createdAt = createdAt
    self.updatedAt = createdAt
  }
}

/// App Group `"MoviePilotWidgets-v1/"` 下正在播放与运行态插件小组件文件的跨进程读写工具。
public enum PluginWidgetFileStore {
  public static let darwinCommandNotificationName = "org.moviepilot.widgets.command"
  private static let maxRuntimeBytes = 256 * 1024
  private static let maxArtworkBytes = 2 * 1024 * 1024

  /// 解析当前已签名可执行文件授权的 App Group 容器根目录。
  public static func sharedContainerURL() -> URL? {
    guard let group = WidgetSharedStorage.groupIdentifier else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  }

  /// 返回 `"MoviePilotWidgets-v1"` 共享工作目录。
  public static func rootDirectory(in container: URL) -> URL {
    container.appendingPathComponent("MoviePilotWidgets-v1", isDirectory: true)
  }

  /// 读取 `"now_playing.json"`，文件不存在或已损坏时返回空闲态。
  public static func readNowPlaying(in container: URL? = sharedContainerURL())
    -> NowPlayingWidgetSnapshot
  {
    guard let container else { return .idle }
    let url = rootDirectory(in: container).appendingPathComponent("now_playing.json")
    guard let data = try? readBounded(url, maximum: 64 * 1024),
      let decoded = try? JSONDecoder().decode(NowPlayingWidgetSnapshot.self, from: data)
    else { return .idle }
    return decoded
  }

  /// 原子写入 `"now_playing.json"`。
  public static func writeNowPlaying(
    _ snapshot: NowPlayingWidgetSnapshot, in container: URL? = sharedContainerURL()
  ) throws {
    guard let container else { throw WidgetPlatformError.sharedStorageUnavailable }
    let dir = rootDirectory(in: container)
    try ensureDirectory(dir)
    let data = try JSONEncoder().encode(snapshot)
    try writeAtomic(data, to: dir.appendingPathComponent("now_playing.json"))
  }

  /// 安全解析 `"MoviePilotWidgets-v1/media/<fileName>"` 本地缓存封面数据，拒绝任何路径穿越。
  public static func readArtworkData(
    fileName: String, in container: URL? = sharedContainerURL()
  ) -> Data? {
    guard let container else { return nil }
    let clean = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !clean.contains("/"), !clean.contains("\\"), !clean.contains(".."),
      clean.utf8.count <= 128
    else { return nil }
    let mediaURL = rootDirectory(in: container)
      .appendingPathComponent("media", isDirectory: true)
      .appendingPathComponent(clean)
    return try? readBounded(mediaURL, maximum: maxArtworkBytes)
  }

  /// 从同源相对路径或文件名中解析已缓存在 `"MoviePilotWidgets-v1/media/"` 下的图片字节。
  public static func readCachedPluginImageData(
    rawPathOrName: String?, in container: URL? = sharedContainerURL()
  ) -> Data? {
    guard let raw = rawPathOrName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
    else { return nil }
    let baseName = (raw as NSString).lastPathComponent
    return readArtworkData(fileName: baseName, in: container)
  }

  /// 读取 `"plugin_runtime_widgets.json"` 中由前端运行态实时推送的插件小组件快照字典。
  public static func readRuntimeWidgets(
    in container: URL? = sharedContainerURL()
  ) -> [String: PluginWidgetSnapshot] {
    guard let container else { return [:] }
    let url = rootDirectory(in: container).appendingPathComponent("plugin_runtime_widgets.json")
    guard let data = try? readBounded(url, maximum: maxRuntimeBytes),
      let map = try? JSONDecoder().decode([String: PluginWidgetSnapshot].self, from: data)
    else { return [:] }
    return map
  }

  /// 读取指定 `pluginId` 与 `widgetKey` 对应的运行态推送快照。
  public static func readRuntimeWidget(
    pluginId: String, widgetKey: String, in container: URL? = sharedContainerURL()
  ) -> PluginWidgetSnapshot? {
    let map = readRuntimeWidgets(in: container)
    let exactKey = PluginWidgetDescriptor.makeCompositeKey(pluginId: pluginId, widgetKey: widgetKey)
    if let found = map[exactKey] { return found }
    if widgetKey.isEmpty,
      let fallback = map[
        PluginWidgetDescriptor.makeCompositeKey(pluginId: pluginId, widgetKey: "default")]
    {
      return fallback
    }
    return nil
  }

  /// 将运行态已推送快照投影为可供小组件编辑器选择的目录描述列表。
  public static func runtimeDescriptors(
    in container: URL? = sharedContainerURL()
  ) -> [PluginWidgetDescriptor] {
    readRuntimeWidgets(in: container).values
      .filter { PluginWidgetValidator.isValidPluginId($0.pluginId) }
      .sorted {
        ($0.pluginName, $0.title, $0.widgetKey) < ($1.pluginName, $1.title, $1.widgetKey)
      }
      .map { snap in
        PluginWidgetDescriptor(
          pluginId: snap.pluginId,
          pluginName: snap.pluginName,
          widgetKey: snap.widgetKey,
          name: snap.title,
          description: snap.subtitle,
          kind: snap.kind,
          source: .runtime,
          hasPage: true
        )
      }
  }

  /// 对 `"now_playing.json"` 执行乐观状态翻转（播放/暂停或喜欢状态），令小组件点击后零延迟反馈。
  public static func applyOptimisticNowPlaying(
    command: String, pluginId: String, in container: URL? = sharedContainerURL()
  ) {
    guard let container else { return }
    var current = readNowPlaying(in: container)
    guard current.active else { return }
    if !pluginId.isEmpty && !current.pluginId.isEmpty && current.pluginId != pluginId {
      return
    }
    switch command {
    case "togglePlayPause":
      current.isPlaying.toggle()
    case "toggleLike":
      if current.hasLike { current.liked.toggle() }
    default:
      break
    }
    current.updatedAt = Date().timeIntervalSince1970
    try? writeNowPlaying(current, in: container)
  }

  /// 写入 `"pending_widget_command.json"` 并向主 App 发送 `"org.moviepilot.widgets.command"` Darwin 通知。
  public static func postCommand(
    _ command: PendingWidgetCommand, in container: URL? = sharedContainerURL()
  ) throws {
    guard let container else { throw WidgetPlatformError.sharedStorageUnavailable }
    let dir = rootDirectory(in: container)
    try ensureDirectory(dir)
    let data = try JSONEncoder().encode(command)
    try writeAtomic(data, to: dir.appendingPathComponent("pending_widget_command.json"))
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(
      center,
      CFNotificationName(darwinCommandNotificationName as CFString),
      nil,
      nil,
      true
    )
  }

  /// 读取并清空待处理的桌面小组件指令（供主 App 宿主在收到 Darwin 通知或回到前台时消费）。
  public static func consumePendingCommand(
    in container: URL? = sharedContainerURL()
  ) -> PendingWidgetCommand? {
    guard let container else { return nil }
    let url = rootDirectory(in: container).appendingPathComponent("pending_widget_command.json")
    guard let data = try? readBounded(url, maximum: 16 * 1024),
      let cmd = try? JSONDecoder().decode(PendingWidgetCommand.self, from: data)
    else { return nil }
    try? FileManager.default.removeItem(at: url)
    return cmd
  }

  /// 融合运行态推送快照与后端只读快照，优先返回更新时间更新的一方。
  public static func fuseSnapshots(
    runtime: PluginWidgetSnapshot?, remote: PluginWidgetSnapshot?
  ) -> PluginWidgetSnapshot? {
    switch (runtime, remote) {
    case (let .some(rt), let .some(rm)):
      return rt.effectiveTimestamp >= rm.effectiveTimestamp ? rt : rm
    case (let .some(rt), .none):
      return rt
    case (.none, let .some(rm)):
      return rm
    case (.none, .none):
      return nil
    }
  }

  private static func ensureDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  }

  private static func readBounded(_ url: URL, maximum: Int) throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximum + 1) ?? Data()
    guard data.count <= maximum else { throw WidgetDataError.oversizedData }
    return data
  }

  private static func writeAtomic(_ data: Data, to url: URL) throws {
    var options: Data.WritingOptions = [.atomic]
    #if os(iOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    try data.write(to: url, options: options)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

/// 插件小组件标识符与协议基础字段校验器。
public enum PluginWidgetValidator {
  /// 校验插件标识格式（首字符字母，仅含字母数字下划线，最长 128 字节）。
  public static func isValidPluginId(_ value: String) -> Bool {
    guard let first = value.utf8.first, (1...128).contains(value.utf8.count) else { return false }
    let validFirst = (65...90).contains(first) || (97...122).contains(first)
    guard validFirst else { return false }
    return value.utf8.allSatisfy {
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
    }
  }

  /// 校验插件内小组件子键（允许为空或仅含字母数字下划线连字符，最长 64 字节）。
  public static func isValidWidgetKey(_ value: String) -> Bool {
    guard value.utf8.count <= 64 else { return false }
    return value.utf8.allSatisfy {
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        || $0 == 45 || $0 == 95
    }
  }

  /// 校验 32 位小写十六进制不可变账号身份。
  static func owner(_ value: String) throws {
    guard value.utf8.count == 32,
      value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw WidgetDataError.invalidData }
  }

  /// 校验 UTF-8 字节上限与控制字符过滤。
  static func text(_ value: String, maximum: Int, allowEmpty: Bool = false) throws {
    guard allowEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.utf8.count <= maximum,
      !value.unicodeScalars.contains(where: {
        [.control, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
      })
    else { throw WidgetDataError.invalidData }
  }

  /// 校验合理的 UTC Unix 秒时间戳。
  static func timestamp(_ value: TimeInterval) throws {
    guard value.isFinite, (0...253_402_300_799).contains(value) else {
      throw WidgetDataError.invalidData
    }
  }
}
