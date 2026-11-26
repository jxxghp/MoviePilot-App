import AppIntents
import Foundation
import MoviePilotCore
import WidgetKit

/// 组件配置只保存本机资料 UUID 和用户别名，不能把地址、owner 或凭据交给系统配置。
struct WidgetAccountEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "服务")
  static let defaultQuery = WidgetAccountQuery()
  let id: String
  let name: String

  /// 用户别名属于业务数据，不作为翻译资源键。
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

/// 插件桌面小组件可选择的单个卡片条目，仅携带插件标识与子键，不含服务器地址或凭据。
struct PluginWidgetSelectionEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "插件卡片")
  static let defaultQuery = PluginWidgetSelectionQuery()
  let id: String
  let pluginId: String
  let widgetKey: String
  let title: String
  let pluginName: String

  /// 使用卡片标题与所属插件名称组装清晰的编辑菜单项。
  var displayRepresentation: DisplayRepresentation {
    if title == pluginName || pluginName.isEmpty {
      return DisplayRepresentation(title: "\(title)")
    }
    return DisplayRepresentation(title: "\(title)", subtitle: "\(pluginName)")
  }

  /// 从目录描述项构造系统选择器实体。
  init(descriptor: PluginWidgetDescriptor) {
    id = descriptor.compositeKey
    pluginId = descriptor.pluginId
    widgetKey = descriptor.widgetKey
    title = descriptor.name
    pluginName = descriptor.pluginName
  }

  /// 直接从标识符恢复最小实体。
  init(id: String, pluginId: String, widgetKey: String, title: String, pluginName: String) {
    self.id = id
    self.pluginId = pluginId
    self.widgetKey = widgetKey
    self.title = title
    self.pluginName = pluginName
  }
}

/// 插件桌面小组件条目的默认实体查询器。
struct PluginWidgetSelectionQuery: EntityQuery {
  /// 不自动绑定默认插件卡片，由用户在编辑界面明确挑选。
  func defaultResult() async -> PluginWidgetSelectionEntity? { nil }

  /// 根据已持久化的复合键恢复对应实体。
  func entities(for identifiers: [String]) async throws -> [PluginWidgetSelectionEntity] {
    let all = await WidgetRepository.shared.pluginDescriptors(
      profileId: nil, refreshIfNeeded: false)
    let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.compositeKey, $0) })
    return identifiers.compactMap { rawId in
      if let found = byId[rawId] {
        return PluginWidgetSelectionEntity(descriptor: found)
      }
      if let parsed = PluginWidgetDescriptor.parseCompositeKey(rawId) {
        return PluginWidgetSelectionEntity(
          id: rawId,
          pluginId: parsed.pluginId,
          widgetKey: parsed.widgetKey,
          title: parsed.widgetKey.isEmpty ? parsed.pluginId : parsed.widgetKey,
          pluginName: parsed.pluginId
        )
      }
      return nil
    }
  }

  /// 列举本机全部已缓存或运行态推送的可绑定插件小组件。
  func suggestedEntities() async throws -> [PluginWidgetSelectionEntity] {
    await WidgetRepository.shared.pluginDescriptors(profileId: nil, refreshIfNeeded: true)
      .map(PluginWidgetSelectionEntity.init(descriptor:))
  }
}

/// 随所选服务账号动态合并后端只读插件目录与本地运行态推送目录的选项提供器。
struct PluginWidgetOptionsProvider: DynamicOptionsProvider {
  @IntentParameterDependency<MoviePilotPluginConfiguration>(\.$account) private var configuration

  /// 合并所选账号的后端 `/api/v1/widget/plugins` 目录及 `"plugin_runtime_widgets.json"` 目录。
  func results() async throws -> [PluginWidgetSelectionEntity] {
    let profileId = (configuration?.account.id).flatMap(UUID.init(uuidString:))
    return await WidgetRepository.shared.pluginDescriptors(
      profileId: profileId, refreshIfNeeded: true
    )
    .map(PluginWidgetSelectionEntity.init(descriptor:))
  }
}

/// 插件桌面小组件配置意图：支持绑定服务账号与目标插件小组件条目。
struct MoviePilotPluginConfiguration: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "MoviePilot 插件小组件"
  static let description = IntentDescription("选择已在 App 中启用的服务与插件桌面小组件。")

  @Parameter(title: "服务") var account: WidgetAccountEntity?
  @Parameter(title: "插件小组件", optionsProvider: PluginWidgetOptionsProvider())
  var widget: PluginWidgetSelectionEntity?
}

/// 正在播放桌面小组件交互式播控意图（支持播放/暂停、上一首、下一首与喜欢状态切换）。
struct NowPlayingControlIntent: AppIntent {
  static let title: LocalizedStringResource = "控制插件音频播放"
  static let description = IntentDescription("向正在运行的音频插件发送播放、切歌或喜欢指令。")

  @Parameter(title: "指令") var command: String
  @Parameter(title: "插件标识") var pluginId: String

  /// 供系统序列化的默认空构造器。
  init() {
    command = "togglePlayPause"
    pluginId = ""
  }

  /// 构造指定控制动作与目标插件的交互意图。
  init(command: String, pluginId: String) {
    self.command = command
    self.pluginId = pluginId
  }

  /// 写入待消费指令并发送 Darwin 通知，同时乐观翻转本地播放/喜欢状态以立即重绘小组件。
  func perform() async throws -> some IntentResult {
    let allowed: Set<String> = ["togglePlayPause", "previous", "next", "toggleLike"]
    guard allowed.contains(command) else { return .result() }
    PluginWidgetFileStore.applyOptimisticNowPlaying(command: command, pluginId: pluginId)
    let payload = PendingWidgetCommand(
      type: "nowPlaying", command: command, actionId: command, pluginId: pluginId)
    try? PluginWidgetFileStore.postCommand(payload)
    WidgetCenter.shared.reloadTimelines(ofKind: "MoviePilotNowPlaying")
    return .result()
  }
}

/// 插件自定义布局按钮触发的交互式动作意图。
struct PluginWidgetActionIntent: AppIntent {
  static let title: LocalizedStringResource = "触发插件小组件动作"
  static let description = IntentDescription("向目标插件派发桌面小组件自定义按钮动作。")

  @Parameter(title: "插件标识") var pluginId: String
  @Parameter(title: "小组件键") var widgetKey: String
  @Parameter(title: "动作标识") var actionId: String

  /// 供系统序列化的默认构造器。
  init() {
    pluginId = ""
    widgetKey = ""
    actionId = ""
  }

  /// 构造携带插件标识、子键与动作 ID 的按钮意图。
  init(pluginId: String, widgetKey: String, actionId: String) {
    self.pluginId = pluginId
    self.widgetKey = widgetKey
    self.actionId = actionId
  }

  /// 写入待消费插件动作并发送 Darwin 通知，随后请求刷新插件小组件时间线。
  func perform() async throws -> some IntentResult {
    guard PluginWidgetValidator.isValidPluginId(pluginId),
      PluginWidgetValidator.isValidWidgetKey(widgetKey),
      PluginWidgetValidator.isValidWidgetKey(actionId),
      !actionId.isEmpty
    else { return .result() }
    let payload = PendingWidgetCommand(
      type: "pluginAction",
      command: actionId,
      actionId: actionId,
      pluginId: pluginId,
      widgetKey: widgetKey
    )
    try? PluginWidgetFileStore.postCommand(payload)
    WidgetCenter.shared.reloadTimelines(ofKind: "MoviePilotPlugin")
    return .result()
  }
}
