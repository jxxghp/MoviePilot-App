import AppIntents
import Foundation
import MoviePilotCore

/// 组件配置只保存本机资料 UUID 和用户别名，不能把地址、owner 或凭据交给系统配置。
struct WidgetAccountEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "服务")
  static let defaultQuery = WidgetAccountQuery()
  let id: String
  let name: String

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// 系统编辑器只列举明确启用且未过期的资料，不默认选择主 App 当前账号。
struct WidgetAccountQuery: EntityQuery {
  /// 系统图库不能自动绑定第一个真实账号；用户必须在编辑组件时明确选择。
  func defaultResult() async -> WidgetAccountEntity? { nil }

  /// 旧配置只按其原 UUID 恢复，资料移除后不替换成另一账号。
  func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
    try await suggestedEntities().filter { identifiers.contains($0.id) }
  }

  /// 不联网或读取主登录，只访问扩展实际签名允许的最小共享索引。
  func suggestedEntities() async throws -> [WidgetAccountEntity] {
    try await WidgetRepository.shared.profiles().map {
      WidgetAccountEntity(id: $0.id.uuidString, name: $0.name)
    }
  }
}

/// 系统参数使用稳定有限枚举，展示名称与现有业务内容保持一致。
enum WidgetSelectionContent: String, AppEnum {
  case overview, downloads, imports, subscriptions, movieSubscriptions, tvSubscriptions,
    musicSubscriptions

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "内容")
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .overview: "系统概览", .downloads: "下载状态", .imports: "近期入库", .subscriptions: "订阅",
    .movieSubscriptions: "电影订阅", .tvSubscriptions: "剧集订阅", .musicSubscriptions: "音乐订阅",
  ]

  /// 旧分类配置迁移到合并订阅；权限与全量计数继续由当前服务快照决定。
  var content: WidgetContent {
    switch self {
    case .overview: .overview
    case .downloads: .downloads
    case .imports: .imports
    case .subscriptions, .movieSubscriptions, .tvSubscriptions, .musicSubscriptions: .subscriptions
    }
  }
}

/// 内容选项随所选资料的有效快照权限收窄；空或失效资料不列出其它账号的内容。
struct WidgetContentOptions: DynamicOptionsProvider {
  @IntentParameterDependency<MoviePilotConfiguration>(\.$account) private var configuration

  /// 仅使用已授权缓存的白名单，实际每次读取仍由后台重新校验权限。
  func results() async throws -> [WidgetSelectionContent] {
    guard let value = configuration?.account, let id = UUID(uuidString: value.id),
      let snapshot = try await WidgetRepository.shared.cachedSnapshot(profileId: id)
    else { return [] }
    return [WidgetSelectionContent.overview, .downloads, .subscriptions, .imports].filter {
      snapshot.availableContents.contains($0.content)
    }
  }
}

/// 桌面和锁屏均需显式选择资料；默认显示媒体名称，用户可主动关闭。
struct MoviePilotConfiguration: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "MoviePilot 小组件"
  static let description = IntentDescription("选择已在 App 中启用的服务与只读内容。")

  @Parameter(title: "服务") var account: WidgetAccountEntity?
  @Parameter(title: "内容", optionsProvider: WidgetContentOptions()) var content:
    WidgetSelectionContent?
  @Parameter(title: "显示媒体名称", default: true) var showMediaNames: Bool
}
