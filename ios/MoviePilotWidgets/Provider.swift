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

  /// 合并后端 `/api/v1/widget/plugins` 目录与本机 `"plugin_runtime_widgets.json"` 运行态目录。
  func pluginDescriptors(profileId: UUID?, refreshIfNeeded: Bool) async -> [PluginWidgetDescriptor]
  {
    var merged: [String: PluginWidgetDescriptor] = [:]
    for rt in PluginWidgetFileStore.runtimeDescriptors() {
      merged[rt.compositeKey] = rt
    }
    guard let store = try? store(), let profiles = try? await store.profiles() else {
      return Array(merged.values).sorted { ($0.pluginName, $0.name) < ($1.pluginName, $1.name) }
    }
    let targets = profileId.map { id in profiles.filter { $0.id == id } } ?? profiles
    let client = WidgetSnapshotClient()
    for profile in targets {
      var catalog = try? await store.cachedPluginCatalog(profileId: profile.id)
      if catalog == nil && refreshIfNeeded {
        _ = await store.refreshPluginCatalog(profileId: profile.id, using: client)
        catalog = try? await store.cachedPluginCatalog(profileId: profile.id)
      }
      for descriptor in catalog?.widgets ?? [] {
        merged[descriptor.compositeKey] = descriptor
      }
    }
    return Array(merged.values).sorted {
      ($0.pluginName, $0.name, $0.widgetKey) < ($1.pluginName, $1.name, $1.widgetKey)
    }
  }

  /// 双通道融合读取插件小组件快照：优先对比本地运行态新鲜快照与后端只读接口。
  func loadPluginSnapshot(
    profileId: UUID?, pluginId: String, widgetKey: String, refresh: Bool
  ) async -> (WidgetProfile?, PluginWidgetSnapshot?, WidgetRefreshOutcome) {
    let runtimeSnap = PluginWidgetFileStore.readRuntimeWidget(
      pluginId: pluginId, widgetKey: widgetKey)
    guard let store = try? store(), let profiles = try? await store.profiles() else {
      return (nil, runtimeSnap, runtimeSnap == nil ? .unavailable : .cached)
    }
    let resolvedProfile =
      profileId.flatMap { id in profiles.first { $0.id == id } } ?? profiles.first
    guard let profile = resolvedProfile else {
      return (nil, runtimeSnap, runtimeSnap == nil ? .removed : .cached)
    }
    var outcome: WidgetRefreshOutcome = .cached
    if refresh {
      outcome = await store.refreshPluginSnapshot(
        profileId: profile.id, pluginId: pluginId, widgetKey: widgetKey,
        using: WidgetSnapshotClient())
    }
    let remoteSnap = try? await store.cachedPluginSnapshot(
      profileId: profile.id, pluginId: pluginId, widgetKey: widgetKey)
    let fused = PluginWidgetFileStore.fuseSnapshots(runtime: runtimeSnap, remote: remoteSnap)
    return (profile, fused, outcome)
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

/// 正在播放桌面小组件的时间线条目。
struct NowPlayingWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: NowPlayingWidgetSnapshot
  let artworkData: Data?
  var placeholder = false
  var sample = false
}

/// 正在播放桌面小组件的时间线提供器，直接消费 App Group `"now_playing.json"` 与本地缓存封面。
struct MoviePilotNowPlayingProvider: TimelineProvider {
  /// 组件库占位视图使用固定合成曲目。
  func placeholder(in context: Context) -> NowPlayingWidgetEntry {
    var entry = NowPlayingWidgetSample.entry()
    entry.placeholder = true
    return entry
  }

  /// 组件库预览展示合成样例；已放置组件读取真实本地状态。
  func getSnapshot(in context: Context, completion: @escaping (NowPlayingWidgetEntry) -> Void) {
    if context.isPreview {
      completion(NowPlayingWidgetSample.entry())
    } else {
      completion(loadCurrentEntry())
    }
  }

  /// 生成当前播控状态时间线，空闲或播放变更均由宿主及交互 Intent 主动触发即时刷新。
  func getTimeline(
    in context: Context, completion: @escaping (Timeline<NowPlayingWidgetEntry>) -> Void
  ) {
    let entry = loadCurrentEntry()
    let nextDate = Date().addingTimeInterval(entry.snapshot.active ? 300 : 1800)
    completion(Timeline(entries: [entry], policy: .after(nextDate)))
  }

  private func loadCurrentEntry() -> NowPlayingWidgetEntry {
    let snap = PluginWidgetFileStore.readNowPlaying()
    let art =
      snap.active && !snap.artworkFileName.isEmpty
      ? PluginWidgetFileStore.readArtworkData(fileName: snap.artworkFileName) : nil
    return NowPlayingWidgetEntry(date: Date(), snapshot: snap, artworkData: art)
  }
}

/// 正在播放组件库预览的合成样例数据。
enum NowPlayingWidgetSample {
  /// 生成不依赖网络或真实音频会话的预览条目。
  static func entry() -> NowPlayingWidgetEntry {
    let snap = NowPlayingWidgetSnapshot(
      active: true,
      pluginId: "MusicPlayer",
      pluginName: "云音播控",
      title: "星河漫游指南",
      artist: "MoviePilot Studio",
      album: "Midnight Odyssey",
      lyrics: "穿过静谧星海，听见光年的回响\n在夜色尽头点亮下一段航程\n每一帧旋律都与光影同行",
      artworkFileName: "",
      isPlaying: true,
      liked: true,
      hasLike: true,
      canNext: true,
      canPrevious: true,
      durationMs: 248_000,
      positionMs: 96_000,
      updatedAt: Date().timeIntervalSince1970
    )
    return NowPlayingWidgetEntry(date: Date(), snapshot: snap, artworkData: nil, sample: true)
  }
}

/// 插件桌面小组件的时间线条目。
struct PluginWidgetEntry: TimelineEntry {
  let date: Date
  let profileName: String
  let pluginId: String
  let widgetKey: String
  let snapshot: PluginWidgetSnapshot?
  let artworkData: Data?
  let connectionFailed: Bool
  var placeholder = false
  var sample = false
}

/// 插件桌面小组件时间线提供器，支持预设卡片与 `PluginWidgetNode` 声明式布局树。
struct MoviePilotPluginProvider: AppIntentTimelineProvider {
  /// 组件库占位视图。
  func placeholder(in context: Context) -> PluginWidgetEntry {
    var entry = PluginWidgetSample.entry()
    entry.placeholder = true
    return entry
  }

  /// 组件库预览展示合成插件指标，真实组件读取缓存快照。
  func snapshot(
    for configuration: MoviePilotPluginConfiguration, in context: Context
  ) async -> PluginWidgetEntry {
    if context.isPreview {
      return PluginWidgetSample.entry()
    }
    return await loadEntry(for: configuration, refresh: false)
  }

  /// 周期性调度只读刷新，并融合运行态最新推送。
  func timeline(
    for configuration: MoviePilotPluginConfiguration, in context: Context
  ) async -> Timeline<PluginWidgetEntry> {
    let entry = await loadEntry(for: configuration, refresh: true)
    return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
  }

  private func loadEntry(
    for configuration: MoviePilotPluginConfiguration, refresh: Bool
  ) async -> PluginWidgetEntry {
    let now = Date()
    guard let selected = configuration.widget else {
      return PluginWidgetEntry(
        date: now,
        profileName: configuration.account?.name ?? "MoviePilot",
        pluginId: "",
        widgetKey: "",
        snapshot: nil,
        artworkData: nil,
        connectionFailed: false
      )
    }
    let profileId = configuration.account.flatMap { UUID(uuidString: $0.id) }
    let (profile, snapshot, outcome) = await WidgetRepository.shared.loadPluginSnapshot(
      profileId: profileId,
      pluginId: selected.pluginId,
      widgetKey: selected.widgetKey,
      refresh: refresh
    )
    let artData =
      PluginWidgetFileStore.readCachedPluginImageData(rawPathOrName: snapshot?.artworkFileName)
      ?? PluginWidgetFileStore.readCachedPluginImageData(rawPathOrName: snapshot?.imageUrl)
    return PluginWidgetEntry(
      date: now,
      profileName: profile?.name ?? configuration.account?.name ?? "MoviePilot",
      pluginId: selected.pluginId,
      widgetKey: selected.widgetKey,
      snapshot: snapshot,
      artworkData: artData,
      connectionFailed: outcome == .unavailable || outcome == .discarded
    )
  }
}

/// 插件小组件预览样例生成工具。
enum PluginWidgetSample {
  /// 返回组件库预览用的合成插件卡片条目。
  static func entry() -> PluginWidgetEntry {
    let now = Date()
    let snap = PluginWidgetSnapshot(
      pluginId: "SiteStatistic",
      pluginName: "站点数据统计",
      widgetKey: "main",
      state: .ready,
      updatedAt: now.timeIntervalSince1970,
      kind: .metrics,
      title: "今日流量概览",
      subtitle: "做种活跃 · 自动保种正常",
      metrics: [
        PluginWidgetMetricItem(id: "up", label: "今日上传", value: "128.4 GB", tone: "success"),
        PluginWidgetMetricItem(id: "dl", label: "今日下载", value: "36.2 GB", tone: "accent"),
        PluginWidgetMetricItem(id: "seed", label: "做种体积", value: "18.6 TB", tone: "default"),
        PluginWidgetMetricItem(id: "bonus", label: "时魔收益", value: "+1,420", tone: "warning"),
      ],
      items: [
        PluginWidgetListItem(
          id: "s1", title: "主力站点 A", subtitle: "分享率 6.42 · 做种 186", trailing: "正常",
          progress: 0.88),
        PluginWidgetListItem(
          id: "s2", title: "高清影院 B", subtitle: "分享率 4.15 · 做种 94", trailing: "正常",
          progress: 0.72),
      ]
    )
    return PluginWidgetEntry(
      date: now,
      profileName: "我的 MoviePilot",
      pluginId: snap.pluginId,
      widgetKey: snap.widgetKey,
      snapshot: snap,
      artworkData: nil,
      connectionFailed: false,
      sample: true
    )
  }
}
