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
  /// 不同内容使用自己的合成指标，不把上传速度与空间套用到订阅或入库。
  private static func metrics(content: WidgetContent) -> [[String: String]] {
    if content == .downloads {
      return [
        ["id": "downloadSpeed", "title": "下载速度", "value": "2.4 MB/s", "icon": "download"],
        ["id": "uploadSpeed", "title": "上传速度", "value": "680 KB/s", "icon": "upload"],
        ["id": "freeSpace", "title": "剩余空间", "value": "2.8 TB", "icon": "storage"],
        ["id": "count", "title": "数量", "value": "6", "icon": "items"],
      ]
    }
    if content == .overview {
      return [
        ["id": "movies", "title": "电影", "value": "128", "icon": "movie"],
        ["id": "tv", "title": "电视剧", "value": "64", "icon": "television"],
        ["id": "episodes", "title": "单集", "value": "936", "icon": "episodes"],
        ["id": "music", "title": "音乐", "value": "210", "icon": "music"],
        ["id": "used", "title": "已用空间", "value": "12 TB", "icon": "storage"],
        ["id": "total", "title": "总空间", "value": "16 TB", "icon": "storage"],
      ]
    }
    return [["id": "count", "title": "数量", "value": "128", "icon": "items"]]
  }

  /// 概览没有媒体行；只有下载样例含自然进度，其他内容保留对应的纯文字摘要。
  private static func items(content: WidgetContent) -> [[String: Any]] {
    guard content != .overview else { return [] }
    return (1...6).map { index in
      var item: [String: Any] = [
        "id": "sample-\(index)", "title": "示例媒体 \(index)", "subtitle": "仅用于组件预览",
      ]
      if content == .downloads { item["progress"] = Double(index) / 7 }
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
