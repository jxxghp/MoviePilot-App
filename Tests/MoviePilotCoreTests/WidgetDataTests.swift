import Foundation
import Testing

@testable import MoviePilotCore

/// 用多源快照验证账号边界、时间语义、共享资料和固定的 Widget 入口。
struct WidgetDataTests {
  private static let owner = "0123456789abcdef0123456789abcdef"
  private static let epoch: TimeInterval = 1_790_000_000
  private static let now = Date(timeIntervalSince1970: epoch)

  /// 成功、空列表和失败来源同时存在时，保留各自的时间与状态。
  @Test func preservesIndependentSourcesAndWhitelistsPersistence() throws {
    let data = try Self.data { payload in
      payload["token"] = "never-persist-me"
      payload["sections"] = [
        Self.section(),
        Self.section(content: "imports", state: "empty", metrics: []),
        [
          "content": "overview", "state": "unavailable", "title": "实例概览",
          "metrics": [], "items": [], "message": "暂时无法读取",
        ],
      ]
      payload["availableContents"] = ["downloads", "imports", "overview"]
    }
    let snapshot = try Self.decode(data)
    #expect(snapshot.sections.map(\.state) == [.ready, .empty, .unavailable])
    #expect(snapshot.sections[2].updatedAt == nil)
    #expect(snapshot.sections[2].freshness(at: Self.now) == .expired)
    let encoded = try snapshot.encoded()
    #expect(!String(decoding: encoded, as: UTF8.self).contains("never-persist-me"))
    #expect(try Self.decode(encoded) == snapshot)
  }

  /// 根过期与源过期分别约束展示，网络请求时间不能延长采样寿命。
  @Test func tracksFreshnessWithoutRenewingOldData() throws {
    let snapshot = try Self.decode(Self.data())
    let section = snapshot.sections[0]
    #expect(section.freshness(at: Date(timeIntervalSince1970: Self.epoch + 1799)) == .fresh)
    #expect(section.freshness(at: Date(timeIntervalSince1970: Self.epoch + 1800)) == .stale)
    #expect(section.freshness(at: Date(timeIntervalSince1970: Self.epoch + 86_400)) == .expired)
    #expect(section.freshness(at: Date(timeIntervalSince1970: Self.epoch - 301)) == .expired)
    #expect(!snapshot.isExpired(at: Self.now))
    #expect(snapshot.isExpired(at: Date(timeIntervalSince1970: Self.epoch + 86_400)))
    #expect(snapshot.isExpired(at: Date(timeIntervalSince1970: Self.epoch - 301)))
    #expect(snapshot.isExpired(at: Date(timeIntervalSince1970: .infinity)))
    #expect(
      try WidgetSnapshot.decode(
        snapshot.encoded(), owner: Self.owner,
        now: Date(timeIntervalSince1970: Self.epoch + 86_401)) == snapshot)
  }

  /// 同名或同实例的其它用户不能接受当前用户的快照。
  @Test func rejectsOtherOwnersAndVersions() throws {
    #expect(throws: WidgetDataError.ownerMismatch) {
      try WidgetSnapshot.decode(
        Self.data(), owner: String(repeating: "f", count: 32), now: Self.now)
    }
    #expect(throws: WidgetDataError.invalidData) {
      try Self.decode(Self.data { $0["owner"] = "username" })
    }
    #expect(throws: WidgetDataError.unsupportedVersion) {
      try Self.decode(Self.data { $0["version"] = 2 })
    }
  }

  /// 错误类型、时间倒置、未来时间及重复数据源不能进入缓存。
  @Test func rejectsInvalidRootContract() throws {
    let invalidFields: [(String, Any)] = [
      ("generatedAt", Self.epoch + 301), ("generatedAt", -1),
      ("generatedAt", "yesterday"), ("expiresAt", Self.epoch),
      ("expiresAt", Self.epoch + 86_401), ("availableContents", ["downloads", "downloads"]),
      ("availableContents", ["downloads", "imports"]), ("availableContents", ["arbitrary"]),
      ("sections", [Self.section(), Self.section()]),
    ]
    for (key, value) in invalidFields {
      #expect(throws: WidgetDataError.invalidData) {
        try Self.decode(Self.data { $0[key] = value })
      }
    }
    #expect(throws: WidgetDataError.invalidData) {
      try WidgetSnapshot.decode(
        Self.data(), owner: Self.owner,
        now: Date(timeIntervalSince1970: .nan))
    }
    #expect(throws: WidgetDataError.invalidData) { try Self.decode(Data("{}".utf8)) }
    #expect(throws: WidgetDataError.oversizedData) {
      try Self.decode(Data(repeating: 32, count: WidgetSnapshot.maximumBytes + 1))
    }
  }

  /// 来源失败不能携带旧值或新时间，空态和就绪态也不能互相冒充。
  @Test func rejectsMisleadingSectionStates() throws {
    let changes: [(String, Any)] = [
      ("state", "unavailable"), ("updatedAt", NSNull()),
      ("updatedAt", Self.epoch + 1), ("state", "unknown"),
      ("metrics", []),
    ]
    for (key, value) in changes {
      var section = Self.section()
      section[key] = value
      #expect(throws: WidgetDataError.invalidData) {
        try Self.decode(Self.data { $0["sections"] = [section] })
      }
    }
    var emptyWithItems = Self.section(state: "empty")
    emptyWithItems["items"] = [Self.item()]
    #expect(throws: WidgetDataError.invalidData) {
      try Self.decode(Self.data { $0["sections"] = [emptyWithItems] })
    }
    let unavailable: [String: Any] = [
      "content": "downloads", "state": "unavailable", "title": "下载", "metrics": [],
      "items": [Self.item()],
    ]
    #expect(throws: WidgetDataError.invalidData) {
      try Self.decode(Self.data { $0["sections"] = [unavailable] })
    }
  }

  /// 严格限制重复标识、展示行数与字段字节，而不是只检查 JSON 可以读取。
  @Test func boundsRowsAndUTF8Fields() throws {
    let changes: [(String, Any)] = [
      ("metrics", Array(repeating: Self.metric(), count: 2)),
      ("items", Array(repeating: Self.item(), count: 2)),
      ("items", (0..<7).map { Self.item(id: "item-\($0)") }),
      ("metrics", (0..<9).map { Self.metric(id: "metric-\($0)") }),
      ("title", String(repeating: "中", count: 81)), ("title", "  "), ("title", "a\nb"),
    ]
    for (key, value) in changes {
      var section = Self.section()
      section[key] = value
      #expect(throws: WidgetDataError.invalidData) {
        try Self.decode(Self.data { $0["sections"] = [section] })
      }
    }
    var section = Self.section()
    section["title"] = "👩🏽‍💻 e\u{301} 中文"
    section["items"] = [Self.item(title: String(repeating: "中", count: 80))]
    #expect(try Self.decode(Self.data { $0["sections"] = [section] }).sections.count == 1)
  }

  /// 合并订阅可携带总数、三类与四种状态的八项指标，系统符号不影响白名单重编码。
  @Test func acceptsCombinedStatisticsAndSystemSymbols() throws {
    let metrics = (0..<8).map { index in
      [
        "id": "metric-\(index)", "title": "统计", "value": "12",
        "icon": index == 0 ? "cpu" : "memory",
      ]
    }
    var section = Self.section(content: "subscriptions")
    section["metrics"] = metrics
    let snapshot = try Self.decode(
      Self.data {
        $0["availableContents"] = ["subscriptions"]
        $0["sections"] = [section]
      })
    #expect(snapshot.sections[0].metrics.count == 8)
    #expect(snapshot.availableContents == [.subscriptions])
    #expect(try Self.decode(snapshot.encoded()) == snapshot)
  }

  /// 指标和条目不能注入路径、越界进度或未经限制的标题。
  @Test func rejectsInvalidItemAndMetricFields() throws {
    let invalidItems: [(String, Any)] = [
      ("id", "../secret"), ("title", String(repeating: "a", count: 241)),
      ("subtitle", String(repeating: "a", count: 513)), ("progress", -0.1),
      ("progress", 1.01), ("progress", "NaN"), ("timestamp", Self.epoch + 1),
    ]
    for (key, value) in invalidItems {
      var item = Self.item()
      item[key] = value
      var section = Self.section()
      section["items"] = [item]
      #expect(throws: WidgetDataError.invalidData) {
        try Self.decode(Self.data { $0["sections"] = [section] })
      }
    }
    let invalidMetrics: [(String, Any)] = [
      ("id", ""), ("title", String(repeating: "a", count: 121)),
      ("value", String(repeating: "a", count: 65)), ("icon", "custom-command"),
    ]
    for (key, value) in invalidMetrics {
      var metric = Self.metric()
      metric[key] = value
      var section = Self.section()
      section["metrics"] = [metric]
      #expect(throws: WidgetDataError.invalidData) {
        try Self.decode(Self.data { $0["sections"] = [section] })
      }
    }
  }

  /// 自定义 URL 只包含本地资料 ID 和有限内容意图，不能夹带服务端命令。
  @Test(arguments: WidgetContent.allCases)
  func roundTripsFixedLinks(content: WidgetContent) throws {
    let link = WidgetLink(profileId: UUID(), content: content)
    let url = try #require(link.url)
    #expect(WidgetLink(url: url) == link)
    #expect(url.host == "widget")
    #expect(content.route.hasPrefix("/"))
  }

  /// 冷启动链接拒绝重复参数、凭据、任意路径和未经注册的内容。
  @Test func rejectsInjectedLinks() throws {
    let profile = UUID().uuidString
    let valid = "moviepilot://widget?profile=\(profile)&content=downloads"
    let candidates = [
      valid + "&profile=\(UUID().uuidString)", valid + "&token=secret", valid + "#route",
      valid.replacingOccurrences(of: "widget?", with: "widget/path?"),
      valid.replacingOccurrences(of: "widget?", with: "user:password@widget?"),
      valid.replacingOccurrences(of: "widget?", with: "widget:443?"),
      valid.replacingOccurrences(of: "moviepilot:", with: "https:"),
      valid.replacingOccurrences(of: "widget?", with: "widget.evil.test?"),
      valid.replacingOccurrences(of: "downloads", with: "/system"),
      valid.replacingOccurrences(of: profile, with: "not-a-uuid"),
    ]
    for value in candidates {
      #expect(WidgetLink(url: try #require(URL(string: value))) == nil)
    }
  }

  /// 共享资料仅保存精确实例和不可变用户身份，不包含登录凭据。
  @Test func validatesProfilesOnCreationAndRestore() throws {
    let profile = try WidgetProfile(
      id: UUID(), instanceId: UUID(), owner: Self.owner, name: "家中 🎬",
      address: ServerAddress("https://MP.EXAMPLE.TEST:443/moviepilot"),
      registrationId: UUID(), credentialExpiresAt: Self.epoch + 3600)
    #expect(
      profile.snapshotURL.absoluteString
        == "https://mp.example.test/moviepilot/api/v1/widget/snapshot")
    let data = try JSONEncoder().encode(profile)
    #expect(try JSONDecoder().decode(WidgetProfile.self, from: data) == profile)
    let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let invalid: [(String, Any)] = [
      ("owner", "reuseable-user-name"), ("name", String(repeating: "a", count: 81)),
      ("address", "https://user:secret@mp.test"), ("address", "http://public.example.test"),
      ("address", "http://[fe80::1%25en0]:3000/"), ("credentialExpiresAt", -1),
    ]
    for (key, value) in invalid {
      var copy = fields
      copy[key] = value
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(
          WidgetProfile.self, from: JSONSerialization.data(withJSONObject: copy))
      }
    }
  }

  /// 创建一份下载、过期时间明确的现实最小快照，可独立修改受测字段。
  private static func data(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    var payload: [String: Any] = [
      "version": 1, "owner": owner, "generatedAt": epoch, "expiresAt": epoch + 86_400,
      "availableContents": ["downloads"], "sections": [section()],
    ]
    change(&payload)
    return try JSONSerialization.data(withJSONObject: payload)
  }

  /// 固定时钟和期望 owner，测试不依赖宿主实际日期。
  private static func decode(_ data: Data) throws -> WidgetSnapshot {
    try WidgetSnapshot.decode(data, owner: owner, now: now)
  }

  /// 构造已采样来源，空态可合法包含零值指标。
  private static func section(
    content: String = "downloads", state: String = "ready", metrics: [[String: Any]]? = nil
  ) -> [String: Any] {
    [
      "content": content, "state": state, "updatedAt": epoch, "title": "下载状态",
      "metrics": metrics ?? [metric()], "items": [],
    ]
  }

  /// 构造格式化指标，零值不能被误判为无法读取。
  private static func metric(id: String = "active") -> [String: Any] {
    ["id": id, "title": "正在下载", "value": "0", "icon": "download"]
  }

  /// 构造不带下载路径或资源地址的有界媒体摘要。
  private static func item(id: String = "media-1", title: String = "演示影片") -> [String: Any] {
    ["id": id, "title": title, "subtitle": "", "progress": 0.5, "timestamp": epoch]
  }
}
