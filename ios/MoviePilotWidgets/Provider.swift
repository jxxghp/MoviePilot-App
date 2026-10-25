import Foundation
import MoviePilotCore
import WidgetKit

/// 扩展进程的唯一仓入口；不能回退到主 App 沙箱或读取主认证。
actor WidgetRepository {
  static let shared = WidgetRepository()
  private var repository: WidgetStore?

  /// 直到系统确实请求配置或时间线时才尝试打开实际共享组。
  private func store() throws -> WidgetStore {
    if let repository { return repository }
    let opened = try WidgetSharedStorage.open()
    repository = opened
    return opened
  }

  /// 资料过期清理由共享仓完成，系统配置只能看到有效索引。
  func profiles() async throws -> [WidgetProfile] { try await store().profiles() }

  /// 编辑器不引发网络登记或查询，不延长缓存与授权期限。
  func cachedSnapshot(profileId: UUID) async throws -> WidgetSnapshot? {
    try await store().cachedSnapshot(profileId: profileId)
  }

  /// 只读专用端点；近期缓存和同进程并行请求合并由共享仓管理。
  func load(profileId: UUID, refresh: Bool) async throws
    -> (WidgetProfile?, WidgetSnapshot?, WidgetRefreshOutcome)
  {
    let store = try store()
    let outcome =
      refresh
      ? await store.refresh(profileId: profileId, using: WidgetSnapshotClient()) : .cached
    let profile = try await store.profiles().first { $0.id == profileId }
    let snapshot = profile == nil ? nil : try await store.cachedSnapshot(profileId: profileId)
    return (profile, snapshot, outcome)
  }
}

/// 时间线只持有最小展示投影，原始凭据和服务器地址不交给 SwiftUI。
struct MoviePilotEntry: TimelineEntry {
  let date: Date
  let content: WidgetContent
  let display: WidgetDisplay
  var placeholder = false
  var sample = false
}

/// 系统调度只读快照；提前安排本地失效节点，不能承诺精确联网周期。
struct MoviePilotProvider: AppIntentTimelineProvider {
  /// 组件库占位只用合成数据，不访问用户资料或网络。
  func placeholder(in context: Context) -> MoviePilotEntry {
    var entry = WidgetSample.entry()
    entry.placeholder = true
    return entry
  }

  /// 组件库展示合成样例；实际已添加组件读取自己的有效缓存。
  func snapshot(for configuration: MoviePilotConfiguration, in context: Context) async
    -> MoviePilotEntry
  {
    if context.isPreview {
      return WidgetSample.entry(content: configuration.content?.content ?? .downloads)
    }
    return await entries(configuration, refresh: false).first ?? blank(at: Date())
  }

  /// 15分钟是下次请求目标，系统可能合并或推迟；已有时间节点独立负责清空过期内容。
  func timeline(for configuration: MoviePilotConfiguration, in context: Context) async -> Timeline<
    MoviePilotEntry
  > {
    let values = await entries(configuration, refresh: true)
    return Timeline(entries: values, policy: .after(Date().addingTimeInterval(900)))
  }

  /// 不自动换资料或回退到当前主账号，配置失效与共享权限失败都不展示旧数值。
  private func entries(_ configuration: MoviePilotConfiguration, refresh: Bool) async
    -> [MoviePilotEntry]
  {
    let now = Date()
    guard let account = configuration.account, let id = UUID(uuidString: account.id),
      let selection = configuration.content
    else { return [blank(at: now)] }
    do {
      let (profile, snapshot, outcome) = try await WidgetRepository.shared.load(
        profileId: id, refresh: refresh)
      let sampled = Date()
      return WidgetDisplay.timelineDates(
        profile: profile, snapshot: snapshot, content: selection.content, now: sampled
      ).map {
        MoviePilotEntry(
          date: $0, content: selection.content,
          display: WidgetDisplay(
            profile: profile, snapshot: snapshot, content: selection.content,
            showMediaNames: configuration.showMediaNames, at: $0,
            connectionFailed: outcome == .unavailable || outcome == .discarded))
      }
    } catch {
      return [blank(at: now, unavailable: true)]
    }
  }

  /// 空状态没有业务 URL；点击提示用户在主 App 启用，不嵌入外部地址。
  private func blank(at date: Date, unavailable: Bool = false) -> MoviePilotEntry {
    MoviePilotEntry(
      date: date, content: .downloads,
      display: WidgetDisplay(
        profile: nil, snapshot: nil, content: .downloads, showMediaNames: false, at: date,
        connectionFailed: unavailable))
  }
}

/// 固定合成组件库内容，不能从真实 Keychain、实例或历史快照生成预览。
enum WidgetSample {
  /// 组件库使用与后台相同的有限指标标识，预览不会读取真实服务。
  private static func metrics(content: WidgetContent) -> [[String: String]] {
    let values: [(String, String, String, String)]
    switch content {
    case .downloads:
      values = [
        ("downloadSpeed", "下载速度", "2.4 MB/s", "download"),
        ("uploadSpeed", "上传速度", "680 KB/s", "upload"),
        ("freeSpace", "剩余空间", "2.8 TB", "storage"),
        ("count", "数量", "6", "items"),
        ("statedownloading", "下载中", "4", "download"), ("statepaused", "已暂停", "2", "clock"),
      ]
    case .overview:
      values = [
        ("cpu", "CPU 占用", "24.5%", "cpu"), ("memory", "内存占用", "62.8%", "memory"),
        ("networkDownload", "网络接收", "2.4 MB/s", "download"),
        ("networkUpload", "网络发送", "680 KB/s", "upload"),
        ("memoryUsed", "已用内存", "10.0 GB", "memory"), ("memoryTotal", "总内存", "16.0 GB", "memory"),
      ]
    case .imports:
      values = [
        ("count", "数量", "3,428", "items"), ("typeMOVIE", "电影", "1,280", "movie"),
        ("typeTV", "电视剧", "2,080", "television"), ("typeMUSIC", "音乐", "68", "music"),
      ]
    default:
      values = [
        ("count", "数量", "42", "items"), ("typeMOVIE", "电影", "12", "movie"),
        ("typeTV", "电视剧", "24", "television"), ("typeMUSIC", "音乐", "6", "music"),
        ("stateN", "未开始", "6", "clock"), ("stateR", "订阅中", "28", "download"),
        ("stateS", "已暂停", "6", "clock"), ("stateP", "待定", "2", "clock"),
      ]
    }
    return values.map { ["id": $0.0, "title": $0.1, "value": $0.2, "icon": $0.3] }
  }

  /// 仅在大卡片展示示例名称和来源进度，概览没有媒体明细。
  private static func items(content: WidgetContent) -> [[String: Any]] {
    guard content != .overview else { return [] }
    let titles = ["人生切割术", "地球脉动", "星际穿越", "蓝色星球", "流浪地球 2", "随机存取记忆"]
    return titles.enumerated().map { index, title in
      var item: [String: Any] = ["id": "sample-\(index)", "title": title]
      if content == .downloads {
        item["subtitle"] = index == 0 ? "S02E07 · 1.2 MB/s · 剩余 14 分钟" : "680 KB/s · 剩余 26 分钟"
        item["progress"] = Double(index + 1) / 7
      } else if content == .imports {
        item["subtitle"] = index == 0 ? "2025 · 电视剧 · S02 · E07 · 今天 09:30" : "电影 · 今天 08:20"
      } else {
        item["subtitle"] = index < 2 ? "电视剧 · S02 · 7/10 集 · WEB-DL · 2160p" : "电影 · 2160p · 订阅中"
        if index < 2 { item["progress"] = 0.7 }
      }
      return item
    }
  }

  /// 样例沿用生产校验模型，既展示计数也包含自然百分比，不执行网络或业务动作。
  static func entry(content: WidgetContent = .downloads) -> MoviePilotEntry {
    let now = Date()
    let owner = String(repeating: "a", count: 32)
    let profile = try? WidgetProfile(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID(), instanceId: UUID(),
      owner: owner, name: "我的 MoviePilot", address: ServerAddress("https://example.invalid/"),
      registrationId: UUID(), credentialExpiresAt: now.timeIntervalSince1970 + 86_400)
    let data: [String: Any] = [
      "version": 1, "owner": owner, "generatedAt": now.timeIntervalSince1970,
      "expiresAt": now.timeIntervalSince1970 + 86_400, "availableContents": [content.rawValue],
      "sections": [
        [
          "content": content.rawValue, "state": "ready", "updatedAt": now.timeIntervalSince1970,
          "title": content.title,
          "metrics": metrics(content: content), "items": items(content: content),
        ]
      ],
    ]
    let snapshot = (try? JSONSerialization.data(withJSONObject: data)).flatMap {
      try? WidgetSnapshot.decode($0, owner: owner, now: now)
    }
    return MoviePilotEntry(
      date: now, content: content,
      display: WidgetDisplay(
        profile: profile, snapshot: snapshot, content: content, showMediaNames: true, at: now)
    )
    .asSample()
  }
}

extension MoviePilotEntry {
  /// 合成预览不含私人数据，无需叠加系统敏感内容遮盖。
  fileprivate func asSample() -> Self {
    var value = self
    value.sample = true
    return value
  }
}
