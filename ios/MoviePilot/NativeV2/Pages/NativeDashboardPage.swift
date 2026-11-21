import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 登录后的原生仪表盘概览；媒体数量、存储和后台服务全部来自所选会话的管理员 API，支持右上角自由开关与编排组件顺序。
@MainActor
struct NativeDashboardPage: View {
  let session: NativeSession
  let onOpenMessages: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @AppStorage("nativeV2.dashboardWidgets.v1") private var storedWidgetsJSON = ""
  @State private var reloadID = UUID()
  @State private var statistics: NativeDashboardStatistics?
  @State private var storage: NativeDashboardStorage?
  @State private var schedules: [NativeDashboardSchedule]?
  @State private var pluginWidgets: [NativeDashboardPluginWidget] = []
  @State private var widgetItems: [NativeDashboardWidgetConfig] =
    NativeDashboardWidgetConfig.defaults
  @State private var showsWidgetEditor = false
  @State private var loading = false
  @State private var failedSections: [String] = []

  /// 只注入当前会话，不接触全局 token、实例 ID 或共享网络客户端。
  init(
    session: NativeSession,
    onOpenMessages: (() -> Void)? = nil
  ) {
    self.session = session
    self.onOpenMessages = onOpenMessages
  }

  /// 页面自带 Cinematic 全局紫玫瑰渐变背景，保证透色玻璃卡片与顶部原生工具栏层级清晰。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if loading { loadingIndicator }
          if !failedSections.isEmpty { errorPanel }
          ForEach(widgetItems.filter(\.enabled)) { item in
            dashboardWidgetView(for: item)
          }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.top, 8)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
      .refreshable { await load() }
      .accessibilityIdentifier("native-dashboard-scroll")
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .onAppear { syncWidgetsFromStorage() }
    .task(id: reloadID) { await load() }
    .sheet(isPresented: $showsWidgetEditor) {
      NativeDashboardWidgetsSheet(initialItems: widgetItems) { updated in
        widgetItems = updated
        saveWidgetsToStorage(updated)
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          showsWidgetEditor = true
        } label: {
          Image(systemName: "square.grid.2x2")
        }
        .accessibilityLabel("编辑仪表盘组件")
        .accessibilityIdentifier("native-dashboard-edit-widgets")
      }
    }
  }

  /// 按当前已启用的组件配置顺序渲染对应仪表盘卡片。
  @ViewBuilder
  private func dashboardWidgetView(for item: NativeDashboardWidgetConfig) -> some View {
    switch item.id {
    case "statistics":
      if let statistics { librarySummary(statistics) }
    case "storage":
      if let storage { storageSummary(storage) }
    case "schedules":
      if let schedules { serviceSummary(schedules) }
    default:
      if let widget = pluginWidgets.first(where: { "plugin:\($0.id)" == item.id }) {
        pluginDashboardCard(widget)
      }
    }
  }

  /// 从本地配置恢复组件顺序与显隐，并与最新加载的插件仪表板组件合并。
  private func syncWidgetsFromStorage() {
    var decoded: [NativeDashboardWidgetConfig] = []
    if let data = storedWidgetsJSON.data(using: .utf8),
      let list = try? JSONDecoder().decode([NativeDashboardWidgetConfig].self, from: data)
    {
      decoded = list
    }
    widgetItems = NativeDashboardWidgetConfig.merged(saved: decoded, plugins: pluginWidgets)
  }

  /// 持久化仪表盘组件显隐与排序。
  private func saveWidgetsToStorage(_ items: [NativeDashboardWidgetConfig]) {
    guard let data = try? JSONEncoder().encode(items),
      let raw = String(data: data, encoding: .utf8)
    else { return }
    storedWidgetsJSON = raw
  }

  /// 只列出拉取失败的分区；已有的成功值继续可读。
  private var errorPanel: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 8) {
        Label("仪表盘数据无法更新", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(.orange)
        Text(failedSections.formatted(.list(type: .and)))
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button(action: refresh) {
          Label("重新载入", systemImage: "arrow.clockwise").frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .disabled(loading)
        .accessibilityIdentifier("native-dashboard-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-dashboard-error")
  }

  /// 作品总量与本月新增来自同一统计响应，辅助字号使用单列卡片。
  private func librarySummary(_ values: NativeDashboardStatistics) -> some View {
    let columns = Array(
      repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
      count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    return VStack(alignment: .leading, spacing: 12) {
      sectionTitle("媒体库统计", detail: "本月入库")
      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        metricCard(
          title: "电影", count: values.movieCount, added: values.movieCountMonth,
          symbol: "film", tint: Color(red: 0.93, green: 0.53, blue: 0.35),
          accessibilityIdentifier: "native-dashboard-metric-movies")
        metricCard(
          title: "剧集", count: values.tvCount, added: values.tvCountMonth, symbol: "tv",
          tint: Color(red: 0.63, green: 0.65, blue: 0.97),
          accessibilityIdentifier: "native-dashboard-metric-tv")
        metricCard(
          title: "剧集单集", count: values.episodeCount, added: values.episodeCountMonth,
          symbol: "rectangle.stack", tint: Color(red: 0.50, green: 0.79, blue: 0.80),
          accessibilityIdentifier: "native-dashboard-metric-episodes")
        metricCard(
          title: "音乐", count: values.musicCount, added: values.musicCountMonth,
          symbol: "music.note", tint: Color(red: 0.92, green: 0.56, blue: 0.73),
          accessibilityIdentifier: "native-dashboard-metric-music")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-dashboard-library")
  }

  /// 参照 Cinematic 概览卡片：大字号数字居左上、柔和图标徽标与本月增量保持低噪层次。
  private func metricCard(
    title: String, count: Int?, added: Int, symbol: String, tint: Color,
    accessibilityIdentifier: String
  ) -> some View {
    CinematicPanel(padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(count.map { $0.formatted(.number) } ?? "未获取")
              .font(
                count == nil
                  ? .system(.title2, design: .rounded).weight(.semibold)
                  : .system(.largeTitle, design: .rounded).weight(.bold)
              )
              .minimumScaleFactor(0.72)
              .lineLimit(1)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary.opacity(0.76))
          }
          Spacer(minLength: 8)
          Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
        }
        Spacer(minLength: 0)
        Text("本月 +\(added, format: .number)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(tint)
          .padding(.horizontal, 9)
          .padding(.vertical, 4)
          .background(tint.opacity(0.14), in: Capsule())
      }
      .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(
      count.map { "共 \($0.formatted(.number))，本月新增 \(added.formatted(.number))" }
        ?? "总量暂未获取，本月新增 \(added.formatted(.number))"
    )
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  /// 存储卡仅将后端字节字段转换成人类可读单位，并用原生环形进度展示比例。
  private func storageSummary(_ value: NativeDashboardStorage) -> some View {
    let percentage = value.usage.formatted(.percent.precision(.fractionLength(0...1)))
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
    return VStack(alignment: .leading, spacing: 12) {
      sectionTitle("存储空间", detail: "服务器")
      CinematicPanel {
        layout {
          ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 8)
            Circle()
              .trim(from: 0, to: value.usage)
              .stroke(
                AngularGradient(
                  colors: [
                    Color(red: 0.70, green: 0.59, blue: 0.94),
                    Color(red: 0.91, green: 0.54, blue: 0.71),
                  ],
                  center: .center),
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
              )
              .rotationEffect(.degrees(-90))
            if !dynamicTypeSize.isAccessibilitySize {
              Text(percentage)
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .padding(.horizontal, 5)
                .minimumScaleFactor(0.8)
            }
          }
          .frame(width: 74, height: 74)
          .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 6) {
            Text(Self.storageSize(value.usedStorage) + " / " + Self.storageSize(value.totalStorage))
              .font(.headline.monospacedDigit())
            Text("已用 / 总容量").font(.caption).foregroundStyle(.secondary)
            Text("剩余 \(Self.storageSize(max(0, value.totalStorage - value.usedStorage)))")
              .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
              Text("已使用 \(percentage)").font(.subheadline)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityElement(children: .combine)
      .accessibilityValue("已使用 \(percentage)")
      .accessibilityIdentifier("native-dashboard-storage")
    }
  }

  /// 同前端一样优先展示运行中的服务；条目较多时限制卡片高度并支持内部滚动，避免仪表盘无限拉长。
  private func serviceSummary(_ values: [NativeDashboardSchedule]) -> some View {
    let ordered = values.filter(\.isRunning) + values.filter { !$0.isRunning }
    return VStack(alignment: .leading, spacing: 12) {
      sectionTitle(
        "后台服务", detail: ordered.count > 4 ? "\(values.count) 项 · 可滚动" : "\(values.count) 项")
      if values.isEmpty {
        CinematicPanel {
          Label("暂时没有后台服务", systemImage: "checkmark.circle")
            .foregroundStyle(.primary.opacity(0.82))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
      } else {
        CinematicPanel(padding: 0) {
          if ordered.count > 4 {
            ScrollView(.vertical) {
              LazyVStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { index, service in
                  if index > 0 { CinematicFormDivider() }
                  serviceRow(service)
                }
              }
            }
            .scrollIndicators(.visible)
            .frame(height: 280)
          } else {
            LazyVStack(spacing: 0) {
              ForEach(Array(ordered.enumerated()), id: \.offset) { index, service in
                if index > 0 { CinematicFormDivider() }
                serviceRow(service)
              }
            }
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-dashboard-services")
  }

  /// 服务行朗读当前状态和进度，等待中的服务展示下次执行时间。
  private func serviceRow(_ service: NativeDashboardSchedule) -> some View {
    CinematicFormRow(symbol: service.isRunning ? "arrow.triangle.2.circlepath" : "clock") {
      VStack(alignment: .leading, spacing: 5) {
        Text(service.nameI18n ?? service.name ?? "后台服务")
          .font(.subheadline.weight(.semibold))
        Text(service.summary)
          .font(.caption).foregroundStyle(.secondary)
        if let fraction = service.runningFraction {
          ProgressView(value: fraction) {
            Text(fraction, format: .percent.precision(.fractionLength(0...1)))
              .font(.caption.monospacedDigit())
          }
          .tint(Color(red: 0.75, green: 0.65, blue: 0.98))
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// 单张插件仪表板动态卡片：无缝融入仪表盘流，并支持在组件编辑中单独控制显隐与排序。
  private func pluginDashboardCard(_ widget: NativeDashboardPluginWidget) -> some View {
    Group {
      if widget.isVueRemote {
        CinematicPanel(padding: 12) {
          Label("「\(widget.title)」为远程组件卡片，请从插件管理打开兼容页查看", systemImage: "puzzlepiece.extension")
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        NativePluginJSONRenderer(session: session, nodes: widget.nodes)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-dashboard-plugin-\(widget.pluginID)")
  }

  /// 大字允许标题和数量纵向排列，分区标题可通过 VoiceOver 快速导航。
  private func sectionTitle(_ title: String, detail: String) -> some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    return layout {
      Text(title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
      if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
      Text(detail).font(.caption).foregroundStyle(.secondary)
    }
    .padding(.horizontal, 2)
  }

  /// 刷新时保留上一次真实数据，加载提示在首屏可见。
  private var loadingIndicator: some View {
    HStack(spacing: 10) {
      ProgressView().tint(.primary)
      Text("正在更新仪表盘…").font(.caption).foregroundStyle(.primary.opacity(0.75))
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("native-dashboard-loading")
  }

  /// 并行读取三个独立分区，失败和取消均不覆盖当前会话中已读到的数据。
  private func load() async {
    guard !loading, !Task.isCancelled, session.user.isSuperuser else { return }
    loading = true
    defer { loading = false }

    async let stats = read("statistic", as: NativeDashboardStatistics.self)
    async let disk = read("storage", as: NativeDashboardStorage.self)
    async let jobs = read("schedule", as: [NativeDashboardSchedule].self)
    async let widgets = loadPluginWidgets()
    let (newStatistics, newStorage, newSchedules, newWidgets) = await (stats, disk, jobs, widgets)
    guard session.user.isSuperuser else { return }
    do {
      try session.checkActive()
    } catch {
      return
    }

    failedSections = []
    if let newStatistics { statistics = newStatistics } else { failedSections.append("媒体库统计") }
    if let newStorage { storage = newStorage } else { failedSections.append("存储空间") }
    if let newSchedules { schedules = newSchedules } else { failedSections.append("后台服务") }
    if let newWidgets { pluginWidgets = newWidgets }
    syncWidgetsFromStorage()
  }

  /// 读取插件仪表板元信息并逐项有界解析 JSON 节点，失败时静默降级以免阻塞核心仪表盘分区。
  private func loadPluginWidgets() async -> [NativeDashboardPluginWidget]? {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      let metaEndpoint = try APIEndpoint(path: ["plugin", "dashboard", "meta"])
      let metas = try await session.request(
        metaEndpoint, as: [NativeDashboardPluginMeta].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      var loaded: [NativeDashboardPluginWidget] = []
      for meta in metas.prefix(6) where !meta.id.isEmpty {
        try Task.checkCancellation()
        let path: [String] =
          if let key = meta.key, !key.isEmpty {
            ["plugin", "dashboard", meta.id, key]
          } else {
            ["plugin", "dashboard", meta.id]
          }
        let endpoint = try APIEndpoint(path: path)
        guard
          let payload = try? await session.request(
            endpoint, as: NativeDashboardPluginPayload.self,
            requiring: PermissionRequirement(category: .admin)
          ).value
        else { continue }
        var budget = 600
        let nodes = NativePluginJSONNode.parseArray(
          payload.elements ?? [], depth: 0, budget: &budget)
        let isVue = (payload.renderMode ?? "vuetify").lowercased() == "vue"
        guard isVue || !nodes.isEmpty else { continue }
        let title =
          if let name = payload.name, !name.isEmpty {
            name
          } else if let metaName = meta.name, !metaName.isEmpty {
            metaName
          } else {
            meta.id
          }
        loaded.append(
          NativeDashboardPluginWidget(
            id: "\(meta.id)-\(meta.key ?? "")",
            pluginID: meta.id,
            title: title,
            isVueRemote: isVue,
            nodes: nodes
          ))
      }
      return loaded
    } catch {
      return nil
    }
  }

  /// 同时检查超级用户身份和会话权限，服务端仍执行实际 API 授权。
  private func read<Value: Decodable & Sendable>(_ path: String, as type: Value.Type) async
    -> Value?
  {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      return try await session.request(
        try APIEndpoint(path: ["dashboard", path]), as: type, requiring: .init(category: .admin)
      ).value
    } catch {
      return nil
    }
  }

  /// 按钮只触发页面持有的任务，切换页面时请求随任务取消。
  private func refresh() {
    guard !loading else { return }
    reloadID = UUID()
  }

  /// 使用系统二进制字节单位，大容量仍能按当前语言选取合适单位。
  private static func storageSize(_ bytes: Double) -> String {
    let value = Int64(exactly: bytes.rounded(.towardZero)) ?? .max
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
  }
}

/// 媒体统计只解码后端 dashboard/statistic 响应已有字段。
private struct NativeDashboardStatistics: Decodable, Sendable {
  let movieCountValue: Int?
  let tvCountValue: Int?
  let episodeCountValue: Int?
  let musicCountValue: Int?
  let movieCountMonthValue: Int?
  let tvCountMonthValue: Int?
  let episodeCountMonthValue: Int?
  let musicCountMonthValue: Int?

  /// 后端统计保持 snake_case，UI 内部命名遵循 Swift 驼峰格式。
  private enum CodingKeys: String, CodingKey {
    case movieCountValue = "movie_count"
    case tvCountValue = "tv_count"
    case episodeCountValue = "episode_count"
    case musicCountValue = "music_count"
    case movieCountMonthValue = "movie_count_month"
    case tvCountMonthValue = "tv_count_month"
    case episodeCountMonthValue = "episode_count_month"
    case musicCountMonthValue = "music_count_month"
  }

  /// 普通计数沿用后端零值；无法获得的单集数保留 nil，不把未知伪装为零。
  var movieCount: Int { max(0, movieCountValue ?? 0) }
  var tvCount: Int { max(0, tvCountValue ?? 0) }
  /// 部分媒体库不提供单集总量；保留“未获取”状态，仅校正服务端异常负数。
  var episodeCount: Int? { episodeCountValue.map { max(0, $0) } }
  var musicCount: Int { max(0, musicCountValue ?? 0) }
  var movieCountMonth: Int { max(0, movieCountMonthValue ?? 0) }
  var tvCountMonth: Int { max(0, tvCountMonthValue ?? 0) }
  var episodeCountMonth: Int { max(0, episodeCountMonthValue ?? 0) }
  var musicCountMonth: Int { max(0, musicCountMonthValue ?? 0) }
}

/// 存储模型严格对应 dashboard/storage 的字节字段。
private struct NativeDashboardStorage: Decodable, Sendable {
  let totalStorageValue: Double?
  let usedStorageValue: Double?

  /// 后端存储保持 snake_case，显示层只暴露 camelCase 字段。
  private enum CodingKeys: String, CodingKey {
    case totalStorageValue = "total_storage"
    case usedStorageValue = "used_storage"
  }

  /// 服务器未报告总量时沿用接口模型默认值。
  var totalStorage: Double { max(0, totalStorageValue ?? 0) }
  /// 服务器未报告使用量时沿用接口模型默认值。
  var usedStorage: Double { max(0, usedStorageValue ?? 0) }
  /// 存储条限制在有效区间，磁盘统计异常时仍保留原始用量和总量。
  var usage: Double {
    guard totalStorage > 0, usedStorage.isFinite else { return 0 }
    return min(1, max(0, usedStorage / totalStorage))
  }
}

/// 后台任务仅解码 schedule 接口稳定展示字段，不带出内部进度 payload。
private struct NativeDashboardSchedule: Decodable, Sendable {
  let name: String?
  let nameI18n: String?
  let status: String?
  let statusI18n: String?
  let nextRun: String?
  let nextRunI18n: String?
  let progress: Double?
  let progressText: String?
  let progressTextI18n: String?
  let progressEnable: Bool?
  let progressDetail: ProgressDetail?

  /// 后端 i18n 字段按显式键名映射，UI 不启用全局 snake_case 策略。
  private enum CodingKeys: String, CodingKey {
    case name, status, progress
    case nameI18n = "name_i18n"
    case statusI18n = "status_i18n"
    case nextRun = "next_run"
    case nextRunI18n = "next_run_i18n"
    case progressText = "progress_text"
    case progressTextI18n = "progress_text_i18n"
    case progressEnable = "progress_enable"
    case progressDetail = "progress_detail"
  }

  /// 与现有仪表盘一致，兼容列表与详情两种运行信号。
  var isRunning: Bool {
    status == "正在运行" || progressEnable == true
      || progressDetail?.enable == true || progressDetail?.status == "running"
  }

  /// 优先使用进度详情的数值，列表百分比作为旧服务兼容字段。
  var runningFraction: Double? {
    guard isRunning, let value = progressDetail?.value ?? progress, value.isFinite else {
      return nil
    }
    return min(100, max(0, value)) / 100
  }

  /// 正在运行时使用进度提示，闲置时说明下次运行或调度器状态。
  var summary: String {
    if isRunning {
      return progressDetail?.textI18n ?? progressDetail?.text ?? progressTextI18n ?? progressText
        ?? statusI18n ?? status ?? "正在运行"
    }
    return nextRunI18n ?? nextRun ?? statusI18n ?? status ?? "等待下次运行"
  }

  /// 进度详情只保留呈现所需字段。
  struct ProgressDetail: Decodable, Sendable {
    let enable: Bool?
    let status: String?
    let value: Double?
    let text: String?
    let textI18n: String?

    /// 进度文本优先读取当前语言的后端投影。
    private enum CodingKeys: String, CodingKey {
      case enable, status, value, text
      case textI18n = "text_i18n"
    }
  }
}

/// 插件仪表板元信息条目（`GET /api/v1/plugin/dashboard/meta`）。
private struct NativeDashboardPluginMeta: Decodable, Sendable {
  let id: String
  let name: String?
  let key: String?
}

/// 插件仪表板内容载体（`GET /api/v1/plugin/dashboard/{id}[/{key}]`）。
private struct NativeDashboardPluginPayload: Decodable, Sendable {
  let name: String?
  let renderMode: String?
  let elements: [JSONValue]?

  private enum CodingKeys: String, CodingKey {
    case name
    case renderMode = "render_mode"
    case elements
  }
}

/// 已解析的原生插件仪表板卡片模型。
private struct NativeDashboardPluginWidget: Identifiable, Sendable {
  let id: String
  let pluginID: String
  let title: String
  let isVueRemote: Bool
  let nodes: [NativePluginJSONNode]
}

/// 单条可编排的仪表盘组件配置（覆盖内置统计/存储/后台服务及已安装的插件仪表板组件）。
private struct NativeDashboardWidgetConfig: Identifiable, Codable, Equatable, Sendable {
  let id: String
  var title: String
  var symbol: String
  var enabled: Bool

  static let defaults: [NativeDashboardWidgetConfig] = [
    NativeDashboardWidgetConfig(
      id: "statistics", title: "媒体库统计", symbol: "film.stack", enabled: true),
    NativeDashboardWidgetConfig(
      id: "storage", title: "存储空间", symbol: "externaldrive", enabled: true),
    NativeDashboardWidgetConfig(
      id: "schedules", title: "后台服务", symbol: "clock.arrow.2.circlepath", enabled: true),
  ]

  /// 合并已保存组件排序/显隐与最新内置及插件组件列表。
  static func merged(
    saved: [NativeDashboardWidgetConfig], plugins: [NativeDashboardPluginWidget]
  ) -> [NativeDashboardWidgetConfig] {
    var available: [String: NativeDashboardWidgetConfig] = Dictionary(
      uniqueKeysWithValues: defaults.map { ($0.id, $0) })
    for plugin in plugins {
      let key = "plugin:\(plugin.id)"
      available[key] = NativeDashboardWidgetConfig(
        id: key, title: plugin.title, symbol: "puzzlepiece.extension", enabled: true)
    }
    var seen: Set<String> = []
    var result: [NativeDashboardWidgetConfig] = []
    for item in saved {
      if var latest = available[item.id], seen.insert(item.id).inserted {
        latest.enabled = item.enabled
        result.append(latest)
      }
    }
    for base in defaults where seen.insert(base.id).inserted {
      result.append(base)
    }
    for plugin in plugins {
      let key = "plugin:\(plugin.id)"
      if let item = available[key], seen.insert(key).inserted {
        result.append(item)
      }
    }
    return result
  }
}

/// 仪表盘组件编排弹层：支持开关显隐、长按拖拽排序与恢复默认顺序。
@MainActor
private struct NativeDashboardWidgetsSheet: View {
  let initialItems: [NativeDashboardWidgetConfig]
  let onSave: ([NativeDashboardWidgetConfig]) -> Void

  @State private var items: [NativeDashboardWidgetConfig]
  @State private var editMode: EditMode = .active
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  init(
    initialItems: [NativeDashboardWidgetConfig],
    onSave: @escaping ([NativeDashboardWidgetConfig]) -> Void
  ) {
    self.initialItems = initialItems
    self.onSave = onSave
    _items = State(initialValue: initialItems)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        List {
          Section {
            ForEach($items) { $item in
              HStack(spacing: 12) {
                Image(systemName: item.symbol)
                  .font(.body.weight(.medium))
                  .foregroundStyle(appearance.accentColor)
                  .frame(width: 24)
                Text(item.title)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Toggle("", isOn: $item.enabled)
                  .labelsHidden()
                  .tint(appearance.accentColor)
              }
              .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
              items.move(fromOffsets: source, toOffset: destination)
            }
          } header: {
            Text("开启或拖动调整组件顺序")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } footer: {
            Text("隐藏的组件不会在「我的」仪表盘中显示，可随时重新开启。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
      }
      .navigationTitle("编辑仪表盘组件")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") {
            onSave(items)
            dismiss()
          }
          .fontWeight(.semibold)
          .accessibilityIdentifier("native-dashboard-widgets-save")
        }
      }
    }
    .nativeAppearanceRoot()
  }
}
