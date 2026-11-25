import Foundation

/// 社区勋章档案状态，对应后端 `GithubCommunityProfile.state`。
public enum CommunityProfileState: String, Decodable, Equatable, Sendable {
  case disabled
  case unconfigured
  case ready
  case unavailable
  case unknown

  public init(from decoder: Decoder) throws {
    let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
    self = CommunityProfileState(rawValue: raw) ?? .unknown
  }
}

/// 编剧勋章单个官方仓库的采纳证据；展示时按 `max(commits, mergedPRs)` 计算。
public struct CommunityCodeRepoFact: Decodable, Equatable, Sendable, Identifiable {
  public let repository: String
  public let area: String?
  public let commits: Int
  public let mergedPRs: Int

  public var id: String { repository }

  /// 单仓按 PR 与提交两者较大值计入，不重复相加。
  public var effectiveCount: Int { max(commits, mergedPRs) }

  private enum CodingKeys: String, CodingKey {
    case repository
    case area
    case commits
    case mergedPRs = "merged_prs"
  }

  public init(repository: String, area: String?, commits: Int, mergedPRs: Int) {
    self.repository = repository
    self.area = area
    self.commits = commits
    self.mergedPRs = mergedPRs
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    repository = (try? c.decode(String.self, forKey: .repository)) ?? ""
    area = try? c.decodeIfPresent(String.self, forKey: .area)
    commits = (try? c.decodeIfPresent(Int.self, forKey: .commits)) ?? 0
    mergedPRs = (try? c.decodeIfPresent(Int.self, forKey: .mergedPRs)) ?? 0
  }
}

/// 布景勋章单个插件的安装量事实。
public struct CommunityPluginFact: Decodable, Equatable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let market: String?
  public let installs: Int

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case market
    case installs
  }

  public init(id: String, name: String, market: String?, installs: Int) {
    self.id = id
    self.name = name
    self.market = market
    self.installs = installs
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? id
    market = try? c.decodeIfPresent(String.self, forKey: .market)
    installs = (try? c.decodeIfPresent(Int.self, forKey: .installs)) ?? 0
  }
}

/// 阶梯勋章的认定事实（编剧贡献仓或布景插件安装量）。
public struct CommunityMedalFacts: Decodable, Equatable, Sendable {
  public let total: Int?
  public let repositories: [CommunityCodeRepoFact]
  public let installs: Int?
  public let plugins: [CommunityPluginFact]

  private enum CodingKeys: String, CodingKey {
    case total
    case repositories
    case installs
    case plugins
  }

  public init(
    total: Int? = nil,
    repositories: [CommunityCodeRepoFact] = [],
    installs: Int? = nil,
    plugins: [CommunityPluginFact] = []
  ) {
    self.total = total
    self.repositories = repositories
    self.installs = installs
    self.plugins = plugins
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    total = try? c.decodeIfPresent(Int.self, forKey: .total)
    repositories =
      (try? c.decodeIfPresent([CommunityCodeRepoFact].self, forKey: .repositories)) ?? []
    installs = try? c.decodeIfPresent(Int.self, forKey: .installs)
    plugins = (try? c.decodeIfPresent([CommunityPluginFact].self, forKey: .plugins)) ?? []
  }
}

/// 单枚社区勋章记录，对应 `/api/v1/github/community` 中 `medals[]` 元素。
public struct CommunityMedalRecord: Decodable, Equatable, Sendable, Identifiable {
  public let key: String
  public let tier: Int?
  public let specialty: String?
  public let at: String?
  public let basis: String?
  public let note: String?
  public let serial: String?
  public let facts: CommunityMedalFacts?

  public var id: String { key }

  /// 已读追踪令牌（阶梯勋章带档位，升级后重新触发未读提示）。
  public var seenToken: String {
    if let tier, CommunityMedalCatalog.spec(for: key)?.isLadder == true {
      return "\(key):t\(tier)"
    }
    return key
  }

  /// 对应的规范目录定义；未知键返回 `nil`。
  public var spec: CommunityMedalSpec? {
    CommunityMedalCatalog.spec(for: key)
  }

  /// 规范化档位（1...4），仅阶梯勋章有效。
  public var normalizedTier: Int? {
    guard spec?.isLadder == true, let tier, (1...4).contains(tier) else { return nil }
    return tier
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case tier
    case specialty
    case at
    case basis
    case note
    case serial
    case facts
  }

  public init(
    key: String,
    tier: Int? = nil,
    specialty: String? = nil,
    at: String? = nil,
    basis: String? = nil,
    note: String? = nil,
    serial: String? = nil,
    facts: CommunityMedalFacts? = nil
  ) {
    self.key = key
    self.tier = tier
    self.specialty = specialty
    self.at = at
    self.basis = basis
    self.note = note
    self.serial = serial
    self.facts = facts
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    key = try c.decode(String.self, forKey: .key)
    tier = try? c.decodeIfPresent(Int.self, forKey: .tier)
    specialty = try? c.decodeIfPresent(String.self, forKey: .specialty)
    at = try? c.decodeIfPresent(String.self, forKey: .at)
    basis = try? c.decodeIfPresent(String.self, forKey: .basis)
    note = try? c.decodeIfPresent(String.self, forKey: .note)
    if let str = try? c.decodeIfPresent(String.self, forKey: .serial) {
      serial = str
    } else if let num = try? c.decodeIfPresent(Int.self, forKey: .serial) {
      serial = String(num)
    } else {
      serial = nil
    }
    facts = try? c.decodeIfPresent(CommunityMedalFacts.self, forKey: .facts)
  }
}

/// 后端 `GET /api/v1/github/community` 响应载荷。
public struct CommunityProfile: Decodable, Equatable, Sendable {
  public let state: CommunityProfileState
  public let login: String?
  public let userID: Int?
  public let medals: [CommunityMedalRecord]
  public let generatedAt: String?
  public let checkedAt: Int?
  public let stale: Bool
  public let refreshing: Bool

  /// 按官方目录顺序过滤并排序后的已获已知勋章。
  public var orderedKnownMedals: [CommunityMedalRecord] {
    let order = CommunityMedalCatalog.orderedKeys
    let known = medals.filter { CommunityMedalCatalog.spec(for: $0.key) != nil }
    return known.sorted { lhs, rhs in
      let li = order.firstIndex(of: lhs.key) ?? Int.max
      let ri = order.firstIndex(of: rhs.key) ?? Int.max
      return li < ri
    }
  }

  /// 是否存在可展示的已获社区勋章。
  public var hasEarnedMedals: Bool {
    state == .ready && !orderedKnownMedals.isEmpty
  }

  private enum CodingKeys: String, CodingKey {
    case state
    case login
    case userID = "user_id"
    case medals
    case generatedAt = "generated_at"
    case checkedAt = "checked_at"
    case stale
    case refreshing
  }

  public init(
    state: CommunityProfileState,
    login: String? = nil,
    userID: Int? = nil,
    medals: [CommunityMedalRecord] = [],
    generatedAt: String? = nil,
    checkedAt: Int? = nil,
    stale: Bool = false,
    refreshing: Bool = false
  ) {
    self.state = state
    self.login = login
    self.userID = userID
    self.medals = medals
    self.generatedAt = generatedAt
    self.checkedAt = checkedAt
    self.stale = stale
    self.refreshing = refreshing
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    state = (try? c.decode(CommunityProfileState.self, forKey: .state)) ?? .unknown
    login = try? c.decodeIfPresent(String.self, forKey: .login)
    userID = try? c.decodeIfPresent(Int.self, forKey: .userID)
    medals = (try? c.decodeIfPresent([CommunityMedalRecord].self, forKey: .medals)) ?? []
    generatedAt = try? c.decodeIfPresent(String.self, forKey: .generatedAt)
    checkedAt = try? c.decodeIfPresent(Int.self, forKey: .checkedAt)
    stale = (try? c.decodeIfPresent(Bool.self, forKey: .stale)) ?? false
    refreshing = (try? c.decodeIfPresent(Bool.self, forKey: .refreshing)) ?? false
  }
}

/// 单枚社区勋章的官方目录规格。
public struct CommunityMedalSpec: Equatable, Sendable, Identifiable {
  public let key: String
  public let name: String
  public let isLadder: Bool
  public let isAutomatic: Bool
  public let toneHex: String
  public let enamelCenterHex: String
  public let enamelEdgeHex: String
  public let inkHex: String
  public let summary: String
  public let rule: String
  public let thresholds: [Int]
  public let thresholdLabels: [String]

  public var id: String { key }

  /// 授予方式标签。
  public var howLabel: String { isAutomatic ? "自动认定" : "维护团队颁发" }
}

/// 阶梯勋章金属铭牌配色。
public struct CommunityTierStyle: Equatable, Sendable {
  public let tier: Int
  public let name: String
  public let metalHex: String
  public let darkInkHex: String
  public let lightInkHex: String
  public let isObsidianGold: Bool
}

/// 阶梯勋章档位进度计算结果。
public struct CommunityMedalTierProgress: Equatable, Sendable {
  public let currentTier: Int
  public let nextTier: Int?
  public let currentValue: Int
  public let fromThreshold: Int
  public let toThreshold: Int?
  public let fractionToNext: Double
  public let trackFill: Double
  public let statusText: String
}

/// 背面铭牌动态雕刻文本内容。
public struct CommunityMedalEngraving: Equatable, Sendable {
  public let title: String
  public let tierLine: String?
  public let recipientLine: String?
  public let timeLine: String?
  public let makerMark: String
}

/// 轮廓 JSON 结构（对应 `*.outline.json`）。
public struct CommunityMedalOutline: Decodable, Equatable, Sendable {
  /// 背面铭牌归一化矩形（以中心点 `x, y` 与宽高 `width, height` 表示）。
  public struct DialRect: Decodable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
  }

  /// 外圈机械旋转配置（目前用于主创勋章擒纵步进旋转）。
  public struct SpinConfig: Decodable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let r: Double
    public let period: Double?
    public let mode: String?
    public let step: Double?
    public let interval: Double?
  }

  public let outline: [[Double]]
  public let dial: DialRect?
  public let spin: SpinConfig?
}

/// 社区勋章官方目录、文案、档位进度、雕刻文本与资源命名辅助器。
public enum CommunityMedalCatalog {
  /// 官方勋章固定展示顺序（自动阶梯勋章在前）。
  public static let orderedKeys = [
    "code", "plugin", "maintainer", "helper", "security", "tester", "pioneer",
  ]

  /// 九个官方仓库白名单（仅对这些仓库拼接 GitHub 证据链接）。
  public static let officialRepositories: Set<String> = [
    "MoviePilot", "MoviePilot-Frontend", "MoviePilot-Plugins",
    "MoviePilot-Rust", "MoviePilot-Resources", "MoviePilot-Server",
    "MoviePilot-OCR", "MoviePilot-Web", "MoviePilot-Wiki",
  ]

  /// 全部 7 枚官方社区勋章规格。
  public static let allSpecs: [CommunityMedalSpec] = [
    CommunityMedalSpec(
      key: "code",
      name: "编剧",
      isLadder: true,
      isAutomatic: true,
      toneHex: "#3fc4c9",
      enamelCenterHex: "#0f5560",
      enamelEdgeHex: "#041b20",
      inkHex: "#d2f1ef",
      summary: "致敬为 MoviePilot 写下代码与文档的贡献者。",
      rule: "向 MoviePilot 官方仓库提交并被采纳的贡献累计满 1、10、50、200 次，依次获得初光、共建、卓越、核心。",
      thresholds: [1, 10, 50, 200],
      thresholdLabels: ["1 次", "10 次", "50 次", "200 次"]
    ),
    CommunityMedalSpec(
      key: "plugin",
      name: "布景",
      isLadder: true,
      isAutomatic: true,
      toneHex: "#e08a4c",
      enamelCenterHex: "#7d4321",
      enamelEdgeHex: "#211009",
      inkHex: "#f3cb9c",
      summary: "致敬为 MoviePilot 开发插件的作者。",
      rule: "发布首个插件即获得初光；插件累计安装满 1 万、10 万、100 万次，依次获得共建、卓越、核心。",
      thresholds: [1, 10_000, 100_000, 1_000_000],
      thresholdLabels: ["首个上架", "1 万次", "10 万次", "100 万次"]
    ),
    CommunityMedalSpec(
      key: "maintainer",
      name: "主创",
      isLadder: false,
      isAutomatic: false,
      toneHex: "#9b7bff",
      enamelCenterHex: "#3d2380",
      enamelEdgeHex: "#120828",
      inkHex: "#e0d6ff",
      summary: "致敬 MoviePilot 的维护者与核心团队。",
      rule: "由维护团队颁发给项目的维护者与核心成员。",
      thresholds: [],
      thresholdLabels: []
    ),
    CommunityMedalSpec(
      key: "helper",
      name: "掌灯",
      isLadder: false,
      isAutomatic: false,
      toneHex: "#e6b04a",
      enamelCenterHex: "#6e4a12",
      enamelEdgeHex: "#1f1304",
      inkHex: "#f7dca0",
      summary: "致敬在社群里为他人答疑解惑的热心人。",
      rule: "由维护团队颁发给长期在社群中帮助他人的用户。",
      thresholds: [],
      thresholdLabels: []
    ),
    CommunityMedalSpec(
      key: "security",
      name: "守夜",
      isLadder: false,
      isAutomatic: false,
      toneHex: "#6f8dff",
      enamelCenterHex: "#1d2f7a",
      enamelEdgeHex: "#070c2e",
      inkHex: "#d8e0fb",
      summary: "致敬守护 MoviePilot 安全的人。",
      rule: "由维护团队颁发给负责任地报告安全问题，并协助完成修复的用户。",
      thresholds: [],
      thresholdLabels: []
    ),
    CommunityMedalSpec(
      key: "tester",
      name: "试映",
      isLadder: false,
      isAutomatic: false,
      toneHex: "#ff86b0",
      enamelCenterHex: "#6e1735",
      enamelEdgeHex: "#22050f",
      inkHex: "#ffd3e2",
      summary: "致敬抢先体验并帮助打磨新版本的测试者。",
      rule: "由维护团队颁发给参与测试版本，并提交有效问题反馈的用户。",
      thresholds: [],
      thresholdLabels: []
    ),
    CommunityMedalSpec(
      key: "pioneer",
      name: "启幕",
      isLadder: false,
      isAutomatic: false,
      toneHex: "#e0524a",
      enamelCenterHex: "#6e1414",
      enamelEdgeHex: "#200404",
      inkHex: "#ffd2c4",
      summary: "致敬在 MoviePilot 早期给予支持的人。",
      rule: "由维护团队颁发给项目早期的赞助者与贡献者。",
      thresholds: [],
      thresholdLabels: []
    ),
  ]

  /// 按 `key` 查询目录规格。
  public static func spec(for key: String) -> CommunityMedalSpec? {
    allSpecs.first { $0.key == key }
  }

  /// 阶梯档位金属铭牌规格（1=青铜初光、2=白银共建、3=流金卓越、4=黑金核心）。
  public static func tierStyle(for tier: Int) -> CommunityTierStyle {
    switch tier {
    case 1:
      return CommunityTierStyle(
        tier: 1, name: "初光", metalHex: "#bd926c", darkInkHex: "#cfad8e",
        lightInkHex: "#785333", isObsidianGold: false)
    case 2:
      return CommunityTierStyle(
        tier: 2, name: "共建", metalHex: "#a6b6c8", darkInkHex: "#bcc9d8",
        lightInkHex: "#536579", isObsidianGold: false)
    case 3:
      return CommunityTierStyle(
        tier: 3, name: "卓越", metalHex: "#c6a45d", darkInkHex: "#d7bc81",
        lightInkHex: "#7d6129", isObsidianGold: false)
    default:
      return CommunityTierStyle(
        tier: 4, name: "核心", metalHex: "#bda16e", darkInkHex: "#dfcba1",
        lightInkHex: "#6d5835", isObsidianGold: true)
    }
  }

  /// 编剧领域称号本地化文案。
  public static func specialtyName(for specialty: String?) -> String? {
    guard let specialty else { return nil }
    switch specialty {
    case "backend": return "主程序共建者"
    case "frontend": return "界面共建者"
    case "plugins": return "官方插件共建者"
    case "performance": return "扩展共建者"
    case "resources": return "资源共建者"
    case "services": return "服务共建者"
    case "website": return "官网共建者"
    case "docs": return "文档共建者"
    case "ecosystem": return "生态共建者"
    default: return nil
    }
  }

  /// 仓库领域名称。
  public static func areaName(for area: String?) -> String? {
    guard let area else { return nil }
    switch area {
    case "backend": return "主程序"
    case "frontend": return "前端界面"
    case "plugins": return "官方插件"
    case "performance": return "Rust 扩展"
    case "resources": return "构建与资源"
    case "services": return "外围服务"
    case "website": return "官方网站"
    case "docs": return "社区文档"
    default: return nil
    }
  }

  /// 生成阶梯勋章的等级与称号行（如 `"核心 · 生态共建者"` 或 `"核心"`）。
  public static func tierLine(for record: CommunityMedalRecord) -> String? {
    guard let tier = record.normalizedTier else { return nil }
    let tierName = tierStyle(for: tier).name
    if record.key == "code", let specialty = specialtyName(for: record.specialty) {
      return "\(tierName) · \(specialty)"
    }
    return tierName
  }

  /// 生成获得时间行（如 `"达成 2023.06.10"`、`"认定 2026.10.15"` 或 `"2026.10.16"`）。
  public static func timeLine(for record: CommunityMedalRecord) -> String? {
    guard let raw = record.at?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }
    let dotted = raw.replacingOccurrences(of: "-", with: ".")
    switch record.basis {
    case "reached":
      return "达成 \(dotted)"
    case "recognized":
      return "认定 \(dotted)"
    default:
      return dotted
    }
  }

  /// 生成背面铭牌完整雕刻文案。
  public static func engraving(
    for record: CommunityMedalRecord,
    login: String?
  ) -> CommunityMedalEngraving {
    let title = record.spec?.name ?? record.key
    let recipient: String? = {
      guard let login = login?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty
      else { return nil }
      return "授予 @\(login)"
    }()
    return CommunityMedalEngraving(
      title: title,
      tierLine: tierLine(for: record),
      recipientLine: recipient,
      timeLine: timeLine(for: record),
      makerMark: "MoviePilot"
    )
  }

  /// 计算阶梯勋章的四档进度条投影。
  public static func tierProgress(for record: CommunityMedalRecord) -> CommunityMedalTierProgress? {
    guard let spec = record.spec, spec.isLadder, spec.thresholds.count == 4 else { return nil }
    let value: Int
    if record.key == "code" {
      value = record.facts?.total ?? 0
    } else if record.key == "plugin" {
      value = record.facts?.installs ?? 0
    } else {
      return nil
    }

    let tier: Int
    if let explicit = record.normalizedTier {
      tier = explicit
    } else {
      var computed = 0
      for (idx, threshold) in spec.thresholds.enumerated() where value >= threshold {
        computed = idx + 1
      }
      tier = max(computed, 1)
    }

    let fromThreshold = spec.thresholds[max(tier - 1, 0)]
    if tier >= 4 {
      return CommunityMedalTierProgress(
        currentTier: 4,
        nextTier: nil,
        currentValue: value,
        fromThreshold: fromThreshold,
        toThreshold: nil,
        fractionToNext: 1,
        trackFill: 1,
        statusText: "已达最高档"
      )
    }

    let nextTier = tier + 1
    let toThreshold = spec.thresholds[nextTier - 1]
    let span = max(toThreshold - fromThreshold, 1)
    let fraction = min(max(Double(value - fromThreshold) / Double(span), 0), 1)
    let trackFill = min(1, max(0, (Double(tier - 1) + fraction) / 3.0))
    let remaining = max(toThreshold - value, 0)
    let nextName = tierStyle(for: nextTier).name
    let statusText: String
    if record.key == "code" {
      statusText = "距\(nextName)还差 \(formatCount(remaining)) 次贡献"
    } else {
      statusText = "距\(nextName)还差 \(formatCount(remaining)) 次安装"
    }

    return CommunityMedalTierProgress(
      currentTier: tier,
      nextTier: nextTier,
      currentValue: value,
      fromThreshold: fromThreshold,
      toThreshold: toThreshold,
      fractionToNext: fraction,
      trackFill: trackFill,
      statusText: statusText
    )
  }

  /// 构造内置 `CommunityMedals` 目录中的资源文件名（不含扩展名）。
  public static func frontAssetStem(for record: CommunityMedalRecord) -> String {
    if let tier = record.normalizedTier {
      return "\(record.key)-front-t\(tier)"
    }
    return "\(record.key)-front"
  }

  public static func backAssetStem(for record: CommunityMedalRecord) -> String {
    "\(record.key)-back"
  }

  public static func badgeAssetStem(for record: CommunityMedalRecord) -> String {
    if let tier = record.normalizedTier {
      return "\(record.key)-badge-t\(tier)"
    }
    return "\(record.key)-badge"
  }

  /// 仅对白名单官方仓库生成 GitHub 已合并 PR 证据链接。
  public static func officialRepoPRsURL(repository: String, login: String?) -> URL? {
    guard officialRepositories.contains(repository),
      let login = login?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty
    else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/jxxghp/\(repository)/pulls"
    components.queryItems = [URLQueryItem(name: "q", value: "is:pr is:merged author:\(login)")]
    return components.url
  }

  /// 仅对白名单官方仓库生成 GitHub 作者提交证据链接。
  public static func officialRepoCommitsURL(repository: String, login: String?) -> URL? {
    guard officialRepositories.contains(repository),
      let login = login?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty
    else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "github.com"
    components.path = "/jxxghp/\(repository)/commits"
    components.queryItems = [URLQueryItem(name: "author", value: login)]
    return components.url
  }

  /// 格式化整数计数（带千分位分隔符）。
  public static func formatCount(_ count: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "zh_CN")
    return formatter.string(from: NSNumber(value: count)) ?? String(count)
  }
}
