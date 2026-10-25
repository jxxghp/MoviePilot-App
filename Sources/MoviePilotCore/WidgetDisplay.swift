import Foundation

/// 系统时间线的展示状态；失效和读取失败不能冒充成功的零计数。
public enum WidgetDisplayState: Sendable {
  case unconfigured, unavailable, empty, ready, stale, expired
}

/// 主屏与锁屏共用的纯展示投影，不联网、不扩大权限、不包含凭据或实例地址。
public struct WidgetDisplay: Sendable {
  public let state: WidgetDisplayState
  public let name: String
  public let title: String
  public let message: String?
  public let updatedAt: Date?
  public let metrics: [WidgetMetric]
  public let items: [WidgetItem]
  public let link: URL?

  /// 每一个未来时间线节点重新核对身份、授权和内容期限，避免 App 不运行时继续暴露旧内容。
  public init(
    profile: WidgetProfile?, snapshot: WidgetSnapshot?, content: WidgetContent,
    showMediaNames: Bool, at now: Date, connectionFailed: Bool = false
  ) {
    name = profile?.name ?? "MoviePilot"
    title = content.title
    let validProfile = profile.map { $0.credentialExpiresAt > now.timeIntervalSince1970 } ?? false
    link =
      validProfile ? profile.flatMap { WidgetLink(profileId: $0.id, content: content).url } : nil
    var displayState: WidgetDisplayState = .unconfigured
    var note: String? = "在 App 中启用小组件，再长按选择服务和内容"
    if profile == nil && connectionFailed {
      displayState = .unavailable
      note = "暂时无法读取小组件资料，请在 App 中检查"
    }
    var date: Date?
    var shownMetrics: [WidgetMetric] = []
    var shownItems: [WidgetItem] = []
    if let profile {
      if !validProfile {
        displayState = .expired
        note = "请在 App 中重新启用"
      } else if let snapshot, snapshot.owner == profile.owner {
        if snapshot.isExpired(at: now) {
          displayState = .expired
          note = "数据已过期，请打开 App 刷新"
        } else if let section = snapshot.sections.first(where: { $0.content == content }),
          snapshot.availableContents.contains(content)
        {
          let freshness = section.freshness(at: now)
          if section.state == .unavailable {
            displayState = .unavailable
            note = section.message ?? "暂时无法读取"
          } else if freshness == .expired {
            displayState = .expired
            note = "数据已过期，请打开 App 刷新"
          } else {
            displayState =
              freshness == .stale ? .stale : (section.state == .empty ? .empty : .ready)
            note = connectionFailed ? "暂时无法连接" : (freshness == .stale ? "数据待更新" : nil)
            date = section.updatedAt.map { Date(timeIntervalSince1970: $0) }
            shownMetrics = section.metrics
            shownItems =
              showMediaNames
              ? section.items
              : section.items.enumerated().map { index, item in
                WidgetItem(
                  id: item.id, title: "项目 \(index + 1)", subtitle: nil, progress: item.progress,
                  timestamp: nil)
              }
          }
        } else {
          displayState = .unavailable
          note = "此账号暂不可显示所选内容"
        }
      } else {
        displayState = .unavailable
        note = "请在 App 中刷新小组件资料"
      }
    }
    state = displayState
    message = note
    updatedAt = date
    metrics = shownMetrics
    items = shownItems
  }

  /// 明暗、着色和锁屏共用相同过期节点；系统网络预算不影响本地到期时隐藏内容。
  public static func timelineDates(
    profile: WidgetProfile?, snapshot: WidgetSnapshot?, content: WidgetContent, now: Date
  ) -> [Date] {
    var dates = [now]
    if let profile {
      dates.append(Date(timeIntervalSince1970: profile.credentialExpiresAt))
    }
    if let snapshot {
      dates.append(Date(timeIntervalSince1970: snapshot.expiresAt))
      if let updatedAt = snapshot.sections.first(where: { $0.content == content })?.updatedAt {
        dates.append(Date(timeIntervalSince1970: updatedAt + 1800))
        dates.append(Date(timeIntervalSince1970: updatedAt + 86_400))
      }
    }
    return Array(Set(dates.filter { $0 >= now && $0 <= now.addingTimeInterval(86_400) })).sorted()
  }
}

extension WidgetContent {
  /// 配置项和视图只翻译有限内容枚举，不把业务路由或接口暴露为配置。
  public var title: String {
    switch self {
    case .overview: "实例概览"
    case .downloads: "下载状态"
    case .imports: "近期入库"
    case .movieSubscriptions: "电影订阅"
    case .tvSubscriptions: "剧集订阅"
    case .musicSubscriptions: "音乐订阅"
    }
  }

  /// 使用系统符号表达当前内容，不依赖网页图标字体或外部图片。
  public var symbol: String {
    switch self {
    case .overview: "chart.bar.xaxis"
    case .downloads: "arrow.down.circle"
    case .imports: "tray.and.arrow.down"
    case .movieSubscriptions: "film"
    case .tvSubscriptions: "tv"
    case .musicSubscriptions: "music.note"
    }
  }
}

extension WidgetMetricIcon {
  /// 快照图标枚举的唯一映射，未知任意字符串无法进入系统符号加载。
  public var symbol: String {
    switch self {
    case .movie: "film"
    case .television: "tv"
    case .episodes: "rectangle.stack"
    case .music: "music.note"
    case .download: "arrow.down"
    case .upload: "arrow.up"
    case .storage: "internaldrive"
    case .items: "square.stack.3d.up"
    case .clock: "clock"
    }
  }
}
