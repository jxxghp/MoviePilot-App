import Foundation

/// Widget 展示数据、共享组和链接的拒绝原因；错误不包含原始内容或凭据。
public enum WidgetDataError: Error, Equatable, Sendable {
  case invalidData
  case oversizedData
  case unsupportedVersion
  case ownerMismatch
  case invalidSignature
  case ambiguousAppGroup
}

/// 可选的只读内容；业务目的地固定，实际访问仍经过网页路由与后端授权。
public enum WidgetContent: String, Codable, CaseIterable, Sendable {
  case overview, downloads, imports, subscriptions
  // 保留旧值读取已有配置和缓存，新配置只提供一个合并的订阅入口。
  case movieSubscriptions, tvSubscriptions, musicSubscriptions

  /// 返回既有 HTML 页面路径，不接受服务器传入任意命令或 URL。
  public var route: String {
    switch self {
    case .overview: "/dashboard"
    case .downloads: "/downloading"
    case .imports: "/history"
    case .subscriptions: "/subscribe"
    case .movieSubscriptions: "/subscribe/movie"
    case .tvSubscriptions: "/subscribe/tv"
    case .musicSubscriptions: "/subscribe/music"
    }
  }
}

/// 图标使用有限的展示语义，由 WidgetKit 视图映射为系统符号。
public enum WidgetMetricIcon: String, Codable, Sendable {
  case movie, television, episodes, music, download, upload, storage, items, clock, cpu, memory
}

/// 单个数据源的读取结果；空列表与读取失败不能互相冒充。
public enum WidgetSectionState: String, Codable, Sendable {
  case ready, empty, unavailable
}

/// 新鲜度只表示采样时间，系统调度和下载速度均不承诺实时。
public enum WidgetFreshness: Sendable {
  case fresh, stale, expired
}

/// 后端已格式化的展示指标，原生不派生另一套计数或权限逻辑。
public struct WidgetMetric: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let value: String
  public let icon: WidgetMetricIcon

  /// 限制指标文字和标识；具体数值与单位由业务所有者负责。
  fileprivate func validate() throws {
    try WidgetField.identifier(id)
    try WidgetField.text(title, maximum: 120)
    try WidgetField.text(value, maximum: 64)
  }
}

/// 有界媒体摘要，不含下载路径、hash、资源地址、用户列表或业务动作。
public struct WidgetItem: Codable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let progress: Double?
  public let timestamp: TimeInterval?

  /// 保留完整 UTF-8 文本并拒绝非法进度，不静默截断或修正服务端数据。
  fileprivate func validate(generatedAt: TimeInterval) throws {
    try WidgetField.identifier(id)
    try WidgetField.text(title, maximum: 240)
    if let subtitle { try WidgetField.text(subtitle, maximum: 512, empty: true) }
    if let progress, !progress.isFinite || !(0...1).contains(progress) {
      throw WidgetDataError.invalidData
    }
    if let timestamp {
      try WidgetField.timestamp(timestamp)
      guard timestamp <= generatedAt else { throw WidgetDataError.invalidData }
    }
  }
}

/// 独立数据源的展示快照；失败不能刷新旧数据的采样时间。
public struct WidgetSection: Codable, Equatable, Sendable {
  public let content: WidgetContent
  public let state: WidgetSectionState
  public let updatedAt: TimeInterval?
  public let title: String
  public let metrics: [WidgetMetric]
  public let items: [WidgetItem]
  public let message: String?

  /// 逐项验证文本、唯一标识、数量和状态与数据的一致性。
  fileprivate func validate(generatedAt: TimeInterval) throws {
    try WidgetField.text(title, maximum: 240)
    if let message { try WidgetField.text(message, maximum: 240, empty: true) }
    guard metrics.count <= 8, items.count <= 6,
      Set(metrics.map(\.id)).count == metrics.count,
      Set(items.map(\.id)).count == items.count
    else { throw WidgetDataError.invalidData }
    for metric in metrics { try metric.validate() }
    for item in items { try item.validate(generatedAt: generatedAt) }
    if state == .unavailable {
      guard updatedAt == nil, metrics.isEmpty, items.isEmpty else {
        throw WidgetDataError.invalidData
      }
    } else {
      guard let updatedAt else { throw WidgetDataError.invalidData }
      try WidgetField.timestamp(updatedAt)
      guard updatedAt <= generatedAt,
        state != .empty || items.isEmpty,
        state != .ready || !metrics.isEmpty || !items.isEmpty
      else { throw WidgetDataError.invalidData }
    }
  }

  /// 30 分钟后标旧，24 小时或明显时钟错位后隐藏具体内容。
  public func freshness(at now: Date) -> WidgetFreshness {
    guard let updatedAt, now.timeIntervalSince1970.isFinite else { return .expired }
    let age = now.timeIntervalSince1970 - updatedAt
    guard age >= -300, age < 86_400 else { return .expired }
    return age >= 1800 ? .stale : .fresh
  }
}

/// 协议 v1 的最小 Widget 数据；只在匹配的本机资料下保存重新编码后的模型。
public struct WidgetSnapshot: Codable, Equatable, Sendable {
  public static let maximumBytes = 32 * 1024
  public let version: Int
  public let owner: String
  public let generatedAt: TimeInterval
  public let expiresAt: TimeInterval
  public let availableContents: [WidgetContent]
  public let sections: [WidgetSection]

  /// 保持 Unix 秒字段稳定，避免 Foundation 日期编解码策略产生不同协议。
  private enum CodingKeys: String, CodingKey {
    case version, owner, generatedAt, expiresAt, availableContents, sections
  }

  /// 直接 Codable 读取也执行结构校验；网络和磁盘入口还应使用有界 decode。
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = try values.decode(Int.self, forKey: .version)
    owner = try values.decode(String.self, forKey: .owner)
    generatedAt = try values.decode(TimeInterval.self, forKey: .generatedAt)
    expiresAt = try values.decode(TimeInterval.self, forKey: .expiresAt)
    availableContents = try values.decode([WidgetContent].self, forKey: .availableContents)
    sections = try values.decode([WidgetSection].self, forKey: .sections)
    guard version == 1 else { throw WidgetDataError.unsupportedVersion }
    try WidgetField.owner(owner)
    try WidgetField.timestamp(generatedAt)
    try WidgetField.timestamp(expiresAt)
    guard expiresAt > generatedAt, expiresAt - generatedAt <= 86_400,
      availableContents.count <= WidgetContent.allCases.count,
      Set(availableContents).count == availableContents.count,
      sections.count == availableContents.count,
      Set(sections.map(\.content)) == Set(availableContents)
    else { throw WidgetDataError.invalidData }
    for section in sections { try section.validate(generatedAt: generatedAt) }
  }

  /// 限制原始包、当前 owner 和未来时间；过期缓存仍可解析以展示明确失效状态。
  public static func decode(_ data: Data, owner: String, now: Date = Date()) throws
    -> WidgetSnapshot
  {
    guard data.count <= maximumBytes else { throw WidgetDataError.oversizedData }
    let snapshot: WidgetSnapshot
    do {
      snapshot = try JSONDecoder().decode(Self.self, from: data)
    } catch let error as WidgetDataError {
      throw error
    } catch {
      throw WidgetDataError.invalidData
    }
    guard snapshot.owner == owner else { throw WidgetDataError.ownerMismatch }
    guard now.timeIntervalSince1970.isFinite,
      snapshot.generatedAt <= now.timeIntervalSince1970 + 300
    else { throw WidgetDataError.invalidData }
    return snapshot
  }

  /// 重新编码白名单字段，未知原始字段不得进入共享文件。
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(self)
    guard data.count <= Self.maximumBytes else { throw WidgetDataError.oversizedData }
    return data
  }

  /// 根有效期是内容显示的额外上限，不能用新的请求时间延长旧快照寿命。
  public func isExpired(at now: Date) -> Bool {
    let timestamp = now.timeIntervalSince1970
    return !timestamp.isFinite || timestamp < generatedAt - 300 || timestamp >= expiresAt
  }
}

/// 用户明确启用的实例账号资料；专用 secret 仅在 Keychain，不在该 Codable 模型内。
public struct WidgetProfile: Codable, Equatable, Sendable {
  public let id: UUID
  public let instanceId: UUID
  public let owner: String
  public let name: String
  public let address: ServerAddress
  public let registrationId: UUID
  public let credentialExpiresAt: TimeInterval

  /// 原生登记完成后构造资料，地址继续复用现有容器的安全边界。
  public init(
    id: UUID, instanceId: UUID, owner: String, name: String, address: ServerAddress,
    registrationId: UUID, credentialExpiresAt: TimeInterval
  ) throws {
    self.id = id
    self.instanceId = instanceId
    self.owner = owner
    self.name = name
    self.address = address
    self.registrationId = registrationId
    self.credentialExpiresAt = credentialExpiresAt
    try validate()
  }

  /// 资料字段不允许增加认证信息，保持主 App 与扩展使用相同隔离键。
  private enum CodingKeys: String, CodingKey {
    case id, instanceId, owner, name, address, registrationId, credentialExpiresAt
  }

  /// 恢复共享资料也执行校验，不能通过编辑 JSON 绕过地址或身份限制。
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(UUID.self, forKey: .id),
      instanceId: values.decode(UUID.self, forKey: .instanceId),
      owner: values.decode(String.self, forKey: .owner),
      name: values.decode(String.self, forKey: .name),
      address: values.decode(ServerAddress.self, forKey: .address),
      registrationId: values.decode(UUID.self, forKey: .registrationId),
      credentialExpiresAt: values.decode(TimeInterval.self, forKey: .credentialExpiresAt))
  }

  /// 端点固定在已选实例下，不允许通过服务器响应选择外部地址。
  public var snapshotURL: URL { address.url.appendingPathComponent("api/v1/widget/snapshot") }

  /// 拒绝非法身份、别名和过期格式；实际 Keychain/容器授权另由平台确认。
  private func validate() throws {
    try WidgetField.owner(owner)
    try WidgetField.text(name, maximum: 80)
    try WidgetField.timestamp(credentialExpiresAt)
    guard address.webCompatibilityError == nil else { throw WidgetDataError.invalidData }
  }
}

/// Widget 链接仅携带本机资料和内容意图，不是登录凭据或访问授权。
public struct WidgetLink: Equatable, Sendable {
  public let profileId: UUID
  public let content: WidgetContent

  /// 创建固定内容意图，实例与账号仍从本机登记解析。
  public init(profileId: UUID, content: WidgetContent) {
    self.profileId = profileId
    self.content = content
  }

  /// 对冷启动/热启动采用同一白名单，拒绝重复查询、外部来源与任意路由。
  public init?(url: URL) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme?.lowercased() == "moviepilot", parts.host?.lowercased() == "widget",
      parts.user == nil, parts.password == nil, parts.port == nil, parts.path.isEmpty,
      parts.fragment == nil, let query = parts.queryItems, query.count == 2,
      Set(query.map(\.name)) == ["profile", "content"],
      let rawProfile = query.first(where: { $0.name == "profile" })?.value,
      let profileId = UUID(uuidString: rawProfile),
      let rawContent = query.first(where: { $0.name == "content" })?.value,
      let content = WidgetContent(rawValue: rawContent)
    else { return nil }
    self.init(profileId: profileId, content: content)
  }

  /// URL 内没有服务器地址、owner 或 token，缺失登记无法据此访问任何实例。
  public var url: URL? {
    var parts = URLComponents()
    parts.scheme = "moviepilot"
    parts.host = "widget"
    parts.queryItems = [
      URLQueryItem(name: "profile", value: profileId.uuidString),
      URLQueryItem(name: "content", value: content.rawValue),
    ]
    return parts.url
  }
}

/// Widget 文本与时间的无 I/O 校验，不能承担业务授权或修改输入值。
private enum WidgetField {
  /// 本地账号的不变身份采用既有 notification_identity 格式。
  static func owner(_ value: String) throws {
    guard value.utf8.count == 32,
      value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw WidgetDataError.invalidData }
  }

  /// 稳定展示标识不允许控制字符、路径或可执行命令语法。
  static func identifier(_ value: String) throws {
    guard (1...128).contains(value.utf8.count),
      value.utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || [45, 46, 58, 95].contains($0)
      })
    else { throw WidgetDataError.invalidData }
  }

  /// 按真实 UTF-8 字节预算限制文本，同时保留 emoji 连接符及多语言组合字符。
  static func text(_ value: String, maximum: Int, empty: Bool = false) throws {
    guard empty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.utf8.count <= maximum,
      !value.unicodeScalars.contains(where: {
        [.control, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
      })
    else { throw WidgetDataError.invalidData }
  }

  /// 有限 Unix 秒只接受公元 1970…9999，防止日期转换溢出或异常浮点值。
  static func timestamp(_ value: TimeInterval) throws {
    guard value.isFinite, (0...253_402_300_799).contains(value) else {
      throw WidgetDataError.invalidData
    }
  }
}
