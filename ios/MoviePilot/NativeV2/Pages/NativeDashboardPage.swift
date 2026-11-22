import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 登录后的原生「我的」仪表盘：右上角提供消息中心（左）与捷径（右），底部提供编辑仪表盘组件，完整呈现媒体库、存储、最近入库、下载器、CPU/内存/网络实时监控、7 天整理趋势、后台服务、系统信息与插件 JSON 动态卡片。
@MainActor
struct NativeDashboardPage: View {
  let session: NativeSession
  let onOpenMessages: (() -> Void)?
  let onOpenShortcuts: (() -> Void)?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @AppStorage("nativeV2.dashboardWidgets.v2") private var storedWidgetsJSON = ""
  @State private var reloadID = UUID()
  @State private var statistics: NativeDashboardStatistics?
  @State private var storage: NativeDashboardStorage?
  @State private var recentImports: [NativeDashboardRecentImport] = []
  @State private var downloader: NativeDashboardDownloaderInfo?
  @State private var activeDownloads: [NativeDashboardDownloadTask] = []
  @State private var cpuSamples: [Double] = []
  @State private var memory: NativeDashboardMemoryInfo?
  @State private var networkSamples: [(up: Double, down: Double)] = []
  @State private var transferTrend: [Int] = []
  @State private var schedules: [NativeDashboardSchedule]?
  @State private var systemInfo: NativeDashboardSystemInfo?
  @State private var pluginWidgets: [NativeDashboardPluginWidget] = []
  @State private var communityProfile: CommunityProfile?
  @State private var presentedMedalKey: PresentedCommunityMedalKey?
  @State private var widgetItems: [NativeDashboardWidgetConfig] =
    NativeDashboardWidgetConfig.defaults
  @State private var showsWidgetEditor = false
  @State private var loading = false
  @State private var hasLoadedOnce = false
  @State private var failedSections: [String] = []
  @State private var isPageVisible = false

  /// 优先从会话级缓存同步恢复数据，避免切换标签时闪烁加载态。
  init(
    session: NativeSession,
    onOpenMessages: (() -> Void)? = nil,
    onOpenShortcuts: (() -> Void)? = nil
  ) {
    self.session = session
    self.onOpenMessages = onOpenMessages
    self.onOpenShortcuts = onOpenShortcuts
    if let cached: NativeDashboardCacheSnapshot = NativePageDataCache.shared.get(
      "dashboard|overview.v3", session: session)
    {
      _statistics = State(initialValue: cached.statistics)
      _storage = State(initialValue: cached.storage)
      _recentImports = State(initialValue: cached.recentImports)
      _downloader = State(initialValue: cached.downloader)
      _activeDownloads = State(initialValue: cached.activeDownloads)
      _cpuSamples = State(initialValue: cached.cpuSamples)
      _memory = State(initialValue: cached.memory)
      _networkSamples = State(initialValue: cached.networkSamples)
      _transferTrend = State(initialValue: cached.transferTrend)
      _schedules = State(initialValue: cached.schedules)
      _systemInfo = State(initialValue: cached.systemInfo)
      _pluginWidgets = State(initialValue: cached.pluginWidgets)
      _communityProfile = State(initialValue: cached.communityProfile)
      _hasLoadedOnce = State(initialValue: true)
    }
  }

  /// 是否已有任意已载入的仪表盘数据块。
  private var hasAnyContent: Bool {
    statistics != nil || storage != nil || !recentImports.isEmpty || downloader != nil
      || !activeDownloads.isEmpty || !cpuSamples.isEmpty || memory != nil
      || !networkSamples.isEmpty || !transferTrend.isEmpty || schedules != nil
      || systemInfo != nil || !pluginWidgets.isEmpty
      || (communityProfile?.hasEarnedMedals == true)
  }

  /// 首次进入且尚未完成初次载入时仅展示纯粹的居中加载动画，不露出空卡片或底部编辑按钮。
  private var isInitialLoading: Bool {
    !hasLoadedOnce && !hasAnyContent
  }

  /// 主体使用连续渐变底色，所有已启用仪表盘组件依次流式呈现，底部提供「编辑仪表盘组件」胶囊入口。
  var body: some View {
    ZStack {
      CinematicBackground()
      if isInitialLoading {
        NativeDashboardSkeletonView()
          .transition(.opacity)
          .accessibilityIdentifier("native-dashboard-loading")
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if loading { loadingIndicator }
            if !failedSections.isEmpty { errorPanel }
            ForEach(widgetItems.filter(\.enabled)) { item in
              dashboardWidgetView(for: item)
            }

            HStack {
              Spacer()
              Button {
                showsWidgetEditor = true
              } label: {
                Label("编辑仪表盘组件", systemImage: "slider.horizontal.3")
                  .font(.footnote.weight(.medium))
                  .foregroundStyle(NativeTheme.chipText)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 10)
                  .background {
                    Capsule()
                      .fill(NativeTheme.chipFill)
                      .overlay {
                        Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.7)
                      }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-dashboard-edit-widgets")
              Spacer()
            }
            .padding(.top, 4)
          }
          .frame(maxWidth: 820, alignment: .leading)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.top, 8)
          .padding(.bottom, 36)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .modifier(NativeSoftTopScrollEdge())
        .refreshable { await load(forceRefresh: true) }
        .accessibilityIdentifier("native-dashboard-scroll")
      }
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .onAppear {
      isPageVisible = true
      syncWidgetsFromStorage()
    }
    .onDisappear { isPageVisible = false }
    .task(id: reloadID) { await load(forceRefresh: false) }
    .task(id: isPageVisible) {
      guard isPageVisible else { return }
      var tick = 0
      while !Task.isCancelled && isPageVisible {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled && isPageVisible else { break }
        tick += 1
        await pollRealtimeMetrics(includeMemory: tick % 2 == 0)
      }
    }
    .sheet(isPresented: $showsWidgetEditor) {
      NativeDashboardWidgetsSheet(initialItems: widgetItems) { updated in
        widgetItems = updated
        saveWidgetsToStorage(updated)
      }
    }
    .fullScreenCover(item: $presentedMedalKey) { selected in
      if let binding = Binding($communityProfile) {
        NativeCommunityMedalShowcaseView(
          profile: binding,
          initialKey: selected.key,
          session: session
        )
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        if let onOpenMessages {
          Button(action: onOpenMessages) {
            Image(systemName: "bell")
          }
          .tint(.primary)
          .accessibilityLabel("消息中心")
          .accessibilityIdentifier("native-dashboard-messages-btn")
        }
        if let onOpenShortcuts {
          Button(action: onOpenShortcuts) {
            Image(systemName: "bolt.fill")
          }
          .tint(.primary)
          .accessibilityLabel("捷径")
          .accessibilityIdentifier("native-dashboard-shortcuts-btn")
        }
      }
    }
  }

  /// 按当前已启用的组件配置顺序渲染对应仪表盘卡片。
  @ViewBuilder
  private func dashboardWidgetView(for item: NativeDashboardWidgetConfig) -> some View {
    switch item.id {
    case "communityMedals":
      if let profile = communityProfile, profile.hasEarnedMedals {
        NativeCommunityMedalsWidget(profile: profile) { record in
          presentedMedalKey = PresentedCommunityMedalKey(key: record.key)
        }
      }
    case "statistics":
      if let statistics { librarySummary(statistics) }
    case "storage":
      if let storage { storageSummary(storage) }
    case "recentImports":
      recentImportsSummary
    case "downloader":
      if downloader != nil || !activeDownloads.isEmpty { downloaderSummary }
    case "cpu":
      if !cpuSamples.isEmpty { cpuSummary }
    case "memory":
      if let memory { memorySummary(memory) }
    case "network":
      if !networkSamples.isEmpty { networkSummary }
    case "transferTrend":
      if !transferTrend.isEmpty { transferTrendSummary }
    case "schedules":
      if let schedules { serviceSummary(schedules) }
    case "systemInfo":
      if let systemInfo { systemInfoSummary(systemInfo) }
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

  // MARK: - 1. 媒体库统计

  private func librarySummary(_ values: NativeDashboardStatistics) -> some View {
    let columns = Array(
      repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
      count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle("媒体库统计", detail: "本月入库")
      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        metricCard(
          title: "电影", count: values.movieCount, added: values.movieCountMonth,
          symbol: "film", tint: NativeTheme.warning,
          accessibilityIdentifier: "native-dashboard-metric-movies")
        metricCard(
          title: "剧集", count: values.tvCount, added: values.tvCountMonth, symbol: "tv",
          tint: NativeTheme.brand,
          accessibilityIdentifier: "native-dashboard-metric-tv")
        metricCard(
          title: "剧集单集", count: values.episodeCount, added: values.episodeCountMonth,
          symbol: "rectangle.stack", tint: NativeTheme.cyan,
          accessibilityIdentifier: "native-dashboard-metric-episodes")
        metricCard(
          title: "音乐", count: values.musicCount, added: values.musicCountMonth,
          symbol: "music.note", tint: NativeTheme.pink,
          accessibilityIdentifier: "native-dashboard-metric-music")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-dashboard-library")
  }

  private func metricCard(
    title: String, count: Int?, added: Int, symbol: String, tint: Color,
    accessibilityIdentifier: String
  ) -> some View {
    CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            Text(count.map { $0.formatted(.number) } ?? "未获取")
              .font(
                count == nil
                  ? .system(.title3, design: .rounded).weight(.semibold)
                  : .system(.title, design: .rounded).weight(.bold)
              )
              .minimumScaleFactor(0.72)
              .lineLimit(1)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
          }
          Spacer(minLength: 6)
          Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
        }
        Spacer(minLength: 0)
        NativeAdaptiveBadge("本月 +\(added.formatted(.number))", tint: tint)
      }
      .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(
      count.map { "共 \($0.formatted(.number))，本月新增 \(added.formatted(.number))" }
        ?? "总量暂未获取，本月新增 \(added.formatted(.number))"
    )
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  // MARK: - 2. 存储空间

  private func storageSummary(_ value: NativeDashboardStorage) -> some View {
    let percentage = value.usage.formatted(.percent.precision(.fractionLength(0...1)))
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle("存储空间", detail: "服务器")
      CinematicPanel(padding: 16) {
        layout {
          ZStack {
            Circle().stroke(NativeTheme.divider, lineWidth: 8)
            Circle()
              .trim(from: 0, to: value.usage)
              .stroke(
                AngularGradient(
                  colors: [appearance.accentColor, NativeTheme.pink],
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
          .frame(width: 70, height: 70)
          .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 5) {
            Text(Self.storageSize(value.usedStorage) + " / " + Self.storageSize(value.totalStorage))
              .font(.headline.monospacedDigit())
            Text("已用 / 总容量").font(.caption).foregroundStyle(.secondary)
            Text("剩余 \(Self.storageSize(max(0, value.totalStorage - value.usedStorage)))")
              .font(.caption.weight(.medium)).foregroundStyle(NativeTheme.success)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityElement(children: .combine)
      .accessibilityValue("已使用 \(percentage)")
      .accessibilityIdentifier("native-dashboard-storage")
    }
  }

  // MARK: - 3. 最近入库

  private var recentImportsSummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("最近入库", detail: recentImports.isEmpty ? "暂无记录" : "\(recentImports.count) 条")
      if recentImports.isEmpty {
        CinematicPanel(padding: 14) {
          Label("近期暂无整理入库记录", systemImage: "tray")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        CinematicPanel(padding: 0) {
          LazyVStack(spacing: 0) {
            ForEach(Array(recentImports.prefix(6).enumerated()), id: \.element.id) { index, item in
              if index > 0 { CinematicFormDivider() }
              HStack(spacing: 12) {
                NativeMediaArtwork(
                  session: session, reference: item.image, role: .poster, maximumWidth: 160
                )
                .frame(width: 36, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                  HStack(spacing: 6) {
                    Text(item.displayTitle)
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                    if !item.seasonEpisodeText.isEmpty {
                      NativeAdaptiveBadge(item.seasonEpisodeText, tint: NativeTheme.brand)
                    }
                  }
                  HStack(spacing: 8) {
                    if let mode = item.modeLabel {
                      Text(mode)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(NativeTheme.info)
                    }
                    if let date = item.date, !date.isEmpty {
                      Text(date)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                }
                Spacer(minLength: 4)
                NativeAdaptiveBadge(
                  item.status == false ? "失败" : "已入库",
                  tint: item.status == false ? NativeTheme.danger : NativeTheme.success
                )
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
            }
          }
        }
      }
    }
    .accessibilityIdentifier("native-dashboard-recent-imports")
  }

  // MARK: - 4. 下载器速率与活跃任务

  private var downloaderSummary: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle(
        "下载器",
        detail: activeDownloads.isEmpty ? "空闲" : "\(activeDownloads.count) 个任务"
      )
      CinematicPanel(padding: 15) {
        VStack(alignment: .leading, spacing: 12) {
          if let dl = downloader {
            HStack(spacing: 12) {
              speedTile(
                title: "实时下载", value: Self.speedText(dl.downloadSpeed),
                symbol: "arrow.down.circle.fill", tint: NativeTheme.success)
              speedTile(
                title: "实时上传", value: Self.speedText(dl.uploadSpeed),
                symbol: "arrow.up.circle.fill", tint: NativeTheme.info)
            }
            HStack(spacing: 10) {
              Label(
                "累计下载 \(Self.storageSize(dl.downloadSize))", systemImage: "tray.and.arrow.down"
              )
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
              Spacer(minLength: 6)
              if dl.freeSpace > 0 {
                Text("可用 \(Self.storageSize(dl.freeSpace))")
                  .font(.caption2.monospacedDigit().weight(.medium))
                  .foregroundStyle(NativeTheme.brand)
              }
            }
          }
          if !activeDownloads.isEmpty {
            Divider().overlay(NativeTheme.divider)
            VStack(alignment: .leading, spacing: 9) {
              ForEach(activeDownloads.prefix(4)) { task in
                VStack(alignment: .leading, spacing: 4) {
                  HStack(spacing: 6) {
                    Text(task.displayTitle)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Int(task.normalizedProgress * 100))%")
                      .font(.caption2.monospacedDigit().weight(.semibold))
                      .foregroundStyle(appearance.accentColor)
                  }
                  ProgressView(value: task.normalizedProgress)
                    .tint(appearance.accentColor)
                  HStack(spacing: 8) {
                    if let speed = task.dlspeed, !speed.isEmpty {
                      Text("↓ \(speed)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(NativeTheme.success)
                    }
                    if let left = task.leftTime, !left.isEmpty {
                      Text("剩余 \(left)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let state = task.state, !state.isEmpty {
                      Text(state)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    .accessibilityIdentifier("native-dashboard-downloader")
  }

  private func speedTile(title: String, value: String, symbol: String, tint: Color) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.subheadline.monospacedDigit().weight(.bold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(title)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  // MARK: - 6. CPU 占用（实时折线 + 1m/5m/15m 均值）

  private var cpuSummary: some View {
    let current = cpuSamples.last ?? 0
    let avg1m = Self.average(cpuSamples.suffix(12))
    let avg5m = Self.average(cpuSamples.suffix(60))
    let avg15m = Self.average(cpuSamples)
    let cpuColor =
      current >= 85 ? NativeTheme.danger : (current >= 60 ? NativeTheme.warning : NativeTheme.info)
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle("CPU 占用", detail: "每 5 秒刷新")
      CinematicPanel(padding: 15) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            Text(String(format: "%.1f%%", current))
              .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
              .foregroundStyle(cpuColor)
            Spacer()
            HStack(spacing: 10) {
              miniStat("1m", value: String(format: "%.0f%%", avg1m))
              miniStat("5m", value: String(format: "%.0f%%", avg5m))
              miniStat("15m", value: String(format: "%.0f%%", avg15m))
            }
          }
          NativeSparklineChart(
            values: cpuSamples, maxScale: 100, lineColor: cpuColor
          )
          .frame(height: 54)
        }
      }
    }
    .accessibilityIdentifier("native-dashboard-cpu")
  }

  private func miniStat(_ label: String, value: String) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.primary)
    }
  }

  // MARK: - 7. 内存占用

  private func memorySummary(_ mem: NativeDashboardMemoryInfo) -> some View {
    let ratio = mem.usageRatio
    let cacheRatio =
      mem.total > 0 ? min(max(Double(mem.cached) / Double(mem.total), 0), 1 - ratio) : 0
    let memColor =
      ratio >= 0.85 ? NativeTheme.danger : (ratio >= 0.65 ? NativeTheme.warning : NativeTheme.brand)
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle("内存占用", detail: "总计 \(Self.storageSize(Double(mem.total)))")
      CinematicPanel(padding: 15) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            Text(String(format: "%.1f%%", ratio * 100))
              .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
              .foregroundStyle(memColor)
            Spacer()
            Text("进程 \(Self.storageSize(Double(mem.used)))")
              .font(.caption.monospacedDigit().weight(.medium))
              .foregroundStyle(.primary)
          }
          GeometryReader { bar in
            let w = max(bar.size.width, 1)
            ZStack(alignment: .leading) {
              Capsule().fill(NativeTheme.chipFill)
              HStack(spacing: 0) {
                Rectangle().fill(memColor).frame(width: w * ratio)
                if cacheRatio > 0.005 {
                  Rectangle().fill(NativeTheme.cyan.opacity(0.65)).frame(width: w * cacheRatio)
                }
              }
              .clipShape(Capsule())
            }
          }
          .frame(height: 9)
          HStack(spacing: 12) {
            legendItem("已用 \(Self.storageSize(Double(mem.used)))", color: memColor)
            if mem.cached > 0 {
              legendItem("缓存 \(Self.storageSize(Double(mem.cached)))", color: NativeTheme.cyan)
            }
            Spacer()
            Text("可用 \(Self.storageSize(Double(mem.available)))")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .accessibilityIdentifier("native-dashboard-memory")
  }

  private func legendItem(_ text: String, color: Color) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(text).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
  }

  // MARK: - 8. 实时网络

  private var networkSummary: some View {
    let latest = networkSamples.last ?? (0, 0)
    let peak = max(
      networkSamples.map { max($0.up, $0.down) }.max() ?? 1024,
      1024
    )
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle("实时网络", detail: "主机吞吐")
      CinematicPanel(padding: 15) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 12) {
            speedTile(
              title: "下行速率", value: Self.speedText(latest.down),
              symbol: "arrow.down.circle.fill", tint: NativeTheme.success)
            speedTile(
              title: "上行速率", value: Self.speedText(latest.up),
              symbol: "arrow.up.circle.fill", tint: NativeTheme.info)
          }
          ZStack {
            NativeSparklineChart(
              values: networkSamples.map(\.down), maxScale: peak, lineColor: NativeTheme.success)
            NativeSparklineChart(
              values: networkSamples.map(\.up), maxScale: peak, lineColor: NativeTheme.info,
              showFill: false)
          }
          .frame(height: 50)
        }
      }
    }
    .accessibilityIdentifier("native-dashboard-network")
  }

  // MARK: - 9. 7 天整理趋势

  private var transferTrendSummary: some View {
    let total = transferTrend.reduce(0, +)
    let peak = max(transferTrend.max() ?? 1, 1)
    let labels = Self.lastDayLabels(count: transferTrend.count)
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle("整理趋势", detail: "近 \(transferTrend.count) 天共 \(total) 项")
      CinematicPanel(padding: 15) {
        HStack(alignment: .bottom, spacing: 8) {
          ForEach(Array(transferTrend.enumerated()), id: \.offset) { idx, count in
            VStack(spacing: 5) {
              Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(count > 0 ? .primary : .secondary)
              GeometryReader { geo in
                let ratio = CGFloat(count) / CGFloat(peak)
                let h = max(geo.size.height * ratio, count > 0 ? 8 : 3)
                VStack {
                  Spacer(minLength: 0)
                  RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                      count > 0
                        ? LinearGradient(
                          colors: [appearance.accentColor, NativeTheme.pink.opacity(0.85)],
                          startPoint: .top, endPoint: .bottom)
                        : LinearGradient(
                          colors: [NativeTheme.chipFill, NativeTheme.chipFill],
                          startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: h)
                }
              }
              .frame(height: 68)
              Text(labels.indices.contains(idx) ? labels[idx] : "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
          }
        }
      }
    }
    .accessibilityIdentifier("native-dashboard-transfer-trend")
  }

  // MARK: - 10. 后台服务

  private func serviceSummary(_ values: [NativeDashboardSchedule]) -> some View {
    let ordered = values.filter(\.isRunning) + values.filter { !$0.isRunning }
    return VStack(alignment: .leading, spacing: 10) {
      sectionTitle(
        "后台服务", detail: ordered.count > 4 ? "\(values.count) 项 · 可滚动" : "\(values.count) 项")
      if values.isEmpty {
        CinematicPanel(padding: 14) {
          Label("暂时没有后台服务", systemImage: "checkmark.circle")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
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
            .frame(height: 276)
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

  private func serviceRow(_ service: NativeDashboardSchedule) -> some View {
    let visual = NativeSchedulerVisualResolver.resolve(
      id: service.id ?? "", name: service.name ?? "", provider: service.provider ?? "")
    return HStack(spacing: 12) {
      Image(systemName: service.isRunning ? "arrow.triangle.2.circlepath" : visual.symbol)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(service.isRunning ? NativeTheme.success : visual.tint)
        .frame(width: 26, height: 26)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(service.nameI18n ?? service.name ?? "后台服务")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          if let providerLabel = visual.providerBadge {
            NativeAdaptiveBadge(providerLabel, tint: visual.tint)
          }
        }
        Text(service.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let fraction = service.runningFraction {
          ProgressView(value: fraction)
            .tint(appearance.accentColor)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  // MARK: - 11. 系统信息

  private func systemInfoSummary(_ info: NativeDashboardSystemInfo) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("系统信息", detail: info.version)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          infoRow("主机名称", value: info.hostname, symbol: "desktopcomputer")
          CinematicFormDivider()
          infoRow("操作系统", value: info.operatingSystem, symbol: "cpu")
          CinematicFormDivider()
          infoRow("运行时间", value: Self.formatRuntime(info.runtime), symbol: "timer")
          CinematicFormDivider()
          infoRow("后端版本", value: info.version, symbol: "tag")
        }
      }
    }
    .accessibilityIdentifier("native-dashboard-system-info")
  }

  private func infoRow(_ label: String, value: String, symbol: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(width: 22)
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(value)
        .font(.subheadline.weight(.medium).monospacedDigit())
        .foregroundStyle(.primary)
        .lineLimit(1)
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 11)
  }

  // MARK: - 12. 插件 JSON 动态仪表盘卡片

  private func pluginDashboardCard(_ widget: NativeDashboardPluginWidget) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if widget.showBorder {
        sectionTitle(widget.displayTitle, detail: widget.subtitle ?? "插件组件")
      }
      if widget.isVueRemote {
        CinematicPanel(padding: 13) {
          HStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension.fill")
              .foregroundStyle(NativeTheme.brand)
            Text("「\(widget.displayTitle)」为 Vue 远程仪表板组件，可从底部菜单「插件」查看完整页面。")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      } else if widget.showBorder {
        CinematicPanel(padding: 14) {
          NativePluginJSONRenderer(session: session, nodes: widget.nodes)
        }
      } else {
        NativePluginJSONRenderer(session: session, nodes: widget.nodes)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-dashboard-plugin-\(widget.pluginID)")
  }

  // MARK: - 辅助组件

  private var errorPanel: some View {
    CinematicPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 8) {
        Label("部分仪表盘数据无法更新", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(NativeTheme.warning)
        Text(failedSections.formatted(.list(type: .and)))
          .font(.caption)
          .foregroundStyle(.secondary)
        Button(action: refresh) {
          Label("重新载入", systemImage: "arrow.clockwise").frame(minHeight: 38)
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

  private var loadingIndicator: some View {
    HStack(spacing: 10) {
      ProgressView().tint(.primary)
      Text("正在更新仪表盘…").font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("native-dashboard-loading")
  }

  // MARK: - 网络请求与实时轮询

  private func load(forceRefresh: Bool = false) async {
    guard !loading, !Task.isCancelled else { return }
    guard session.user.isSuperuser else {
      hasLoadedOnce = true
      return
    }
    let cacheKey = "dashboard|overview.v3"
    if !forceRefresh,
      let cached: NativeDashboardCacheSnapshot = NativePageDataCache.shared.get(
        cacheKey, session: session)
    {
      statistics = cached.statistics
      storage = cached.storage
      recentImports = cached.recentImports
      downloader = cached.downloader
      activeDownloads = cached.activeDownloads
      cpuSamples = cached.cpuSamples
      memory = cached.memory
      networkSamples = cached.networkSamples
      transferTrend = cached.transferTrend
      schedules = cached.schedules
      systemInfo = cached.systemInfo
      pluginWidgets = cached.pluginWidgets
      communityProfile = cached.communityProfile
      hasLoadedOnce = true
      syncWidgetsFromStorage()
      await pollRealtimeMetrics(includeMemory: true)
      if communityProfile == nil {
        if let loadedMedals = await loadCommunityProfile() {
          communityProfile = loadedMedals
          saveCache(cacheKey)
        }
      }
      return
    }
    let hadContent = hasAnyContent
    loading = true
    defer { loading = false }

    async let statsTask = readDashboard("statistic", as: NativeDashboardStatistics.self)
    async let storageTask = readDashboard("storage", as: NativeDashboardStorage.self)
    async let recentTask = loadRecentImports()
    async let downloaderTask = readDashboard("downloader", as: NativeDashboardDownloaderInfo.self)
    async let downloadsTask = loadActiveDownloads()
    async let cpuTask = readDashboard("cpu", as: Double.self)
    async let memTask = readDashboard("memory", as: NativeDashboardMemoryInfo.self)
    async let netTask = readDashboard("network", as: [Double].self)
    async let trendTask = loadTransferTrend()
    async let jobsTask = readDashboard("schedule", as: [NativeDashboardSchedule].self)
    async let sysTask = readDashboard("system", as: NativeDashboardSystemInfo.self)
    async let widgetsTask = loadPluginWidgets()
    async let medalsTask = loadCommunityProfile()

    let (
      newStats, newStorage, newRecent, newDownloader, newDownloads,
      newCPU, newMem, newNet, newTrend, newSchedules, newSys, newWidgets, newMedals
    ) = await (
      statsTask, storageTask, recentTask, downloaderTask, downloadsTask,
      cpuTask, memTask, netTask, trendTask, jobsTask, sysTask, widgetsTask, medalsTask
    )

    guard session.user.isSuperuser, !Task.isCancelled else { return }
    guard (try? session.checkActive()) != nil else { return }

    failedSections = []
    if let newStats { statistics = newStats } else if !hadContent { failedSections.append("媒体库统计") }
    if let newStorage { storage = newStorage } else if !hadContent { failedSections.append("存储空间") }
    if let newRecent { recentImports = newRecent }
    if let newDownloader { downloader = newDownloader }
    if let newDownloads { activeDownloads = newDownloads }
    if let newCPU { appendCPUSample(newCPU) }
    if let newMem { memory = newMem }
    if let newNet, newNet.count >= 2 { appendNetworkSample(up: newNet[0], down: newNet[1]) }
    if let newTrend { transferTrend = newTrend }
    if let newSchedules { schedules = newSchedules }
    if let newSys { systemInfo = newSys }
    if let newWidgets { pluginWidgets = newWidgets }
    if let newMedals { communityProfile = newMedals }
    hasLoadedOnce = true
    syncWidgetsFromStorage()
    saveCache(cacheKey)
  }

  /// 轻量轮询实时遥测（仅对当前启用的组件发起请求，节省电量与流量）。
  private func pollRealtimeMetrics(includeMemory: Bool) async {
    guard session.user.isSuperuser, !Task.isCancelled else { return }
    let enabledIDs = Set(widgetItems.filter(\.enabled).map(\.id))
    let needCPU = enabledIDs.contains("cpu")
    let needNet = enabledIDs.contains("network")
    let needDL = enabledIDs.contains("downloader")
    let needMem = includeMemory && enabledIDs.contains("memory")
    guard needCPU || needNet || needDL || needMem else { return }

    async let cpuVal: Double? = needCPU ? readDashboard("cpu", as: Double.self) : nil
    async let netVal: [Double]? = needNet ? readDashboard("network", as: [Double].self) : nil
    async let dlVal: NativeDashboardDownloaderInfo? =
      needDL ? readDashboard("downloader", as: NativeDashboardDownloaderInfo.self) : nil
    async let memVal: NativeDashboardMemoryInfo? =
      needMem ? readDashboard("memory", as: NativeDashboardMemoryInfo.self) : nil

    let (cpu, net, dl, mem) = await (cpuVal, netVal, dlVal, memVal)
    guard !Task.isCancelled else { return }
    if let cpu { appendCPUSample(cpu) }
    if let net, net.count >= 2 { appendNetworkSample(up: net[0], down: net[1]) }
    if let dl { downloader = dl }
    if let mem { memory = mem }
  }

  private func appendCPUSample(_ value: Double) {
    let clamped = min(max(value, 0), 100)
    cpuSamples.append(clamped)
    if cpuSamples.count > 30 { cpuSamples.removeFirst(cpuSamples.count - 30) }
  }

  private func appendNetworkSample(up: Double, down: Double) {
    networkSamples.append((max(up, 0), max(down, 0)))
    if networkSamples.count > 24 { networkSamples.removeFirst(networkSamples.count - 24) }
  }

  private func saveCache(_ cacheKey: String) {
    guard statistics != nil || storage != nil || schedules != nil else { return }
    NativePageDataCache.shared.set(
      NativeDashboardCacheSnapshot(
        statistics: statistics, storage: storage, recentImports: recentImports,
        downloader: downloader, activeDownloads: activeDownloads,
        cpuSamples: cpuSamples, memory: memory, networkSamples: networkSamples,
        transferTrend: transferTrend, schedules: schedules, systemInfo: systemInfo,
        pluginWidgets: pluginWidgets, communityProfile: communityProfile),
      for: cacheKey, session: session)
  }

  /// 拉取超级管理员关联的 GitHub 社区勋章档案（兼容旧版后端与未启用场景，静默回退不报错）。
  private func loadCommunityProfile() async -> CommunityProfile? {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      let endpoint = try APIEndpoint(path: ["github", "community"])
      return try await session.request(
        endpoint, as: CommunityProfile.self,
        requiring: .init(category: .admin)
      ).value
    } catch {
      return nil
    }
  }

  private func readDashboard<Value: Decodable & Sendable>(
    _ path: String, as type: Value.Type
  ) async -> Value? {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      return try await session.request(
        try APIEndpoint(path: ["dashboard", path]), as: type, requiring: .init(category: .admin)
      ).value
    } catch {
      return nil
    }
  }

  private func loadTransferTrend() async -> [Int]? {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      let ep = try APIEndpoint(
        path: ["dashboard", "transfer"], query: [URLQueryItem(name: "days", value: "7")])
      return try await session.request(
        ep, as: [Int].self, requiring: .init(category: .admin)
      ).value
    } catch {
      return nil
    }
  }

  private func loadRecentImports() async -> [NativeDashboardRecentImport]? {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      let ep = try APIEndpoint(
        path: ["history", "transfer"],
        query: [
          URLQueryItem(name: "page", value: "1"),
          URLQueryItem(name: "count", value: "8"),
          URLQueryItem(name: "status", value: "true"),
        ])
      let wrapper = try await session.request(
        ep, as: NativeDashboardRecentImportsResponse.self, requiring: .init(category: .admin)
      ).value
      return wrapper.list ?? []
    } catch {
      return nil
    }
  }

  private func loadActiveDownloads() async -> [NativeDashboardDownloadTask]? {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      let ep = try APIEndpoint(path: ["download"], trailingSlash: true)
      return try await session.request(
        ep, as: [NativeDashboardDownloadTask].self, requiring: .init(category: .admin)
      ).value
    } catch {
      return nil
    }
  }

  /// 读取全部插件仪表板元信息并逐项解析 JSON 节点与 `attrs`（border/title/subtitle）。
  private func loadPluginWidgets() async -> [NativeDashboardPluginWidget]? {
    guard session.user.isSuperuser, !Task.isCancelled else { return nil }
    do {
      let metaEndpoint = try APIEndpoint(path: ["plugin", "dashboard", "meta"])
      let metas = try await session.request(
        metaEndpoint, as: [NativeDashboardPluginMeta].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      var loaded: [NativeDashboardPluginWidget] = []
      for meta in metas.prefix(16) where !meta.id.isEmpty {
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
        var budget = 1200
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
            attrTitle: payload.attrs?.title,
            subtitle: payload.attrs?.subtitle,
            showBorder: payload.attrs?.border ?? true,
            isVueRemote: isVue,
            nodes: nodes
          ))
      }
      return loaded
    } catch {
      return nil
    }
  }

  private func refresh() {
    guard !loading else { return }
    reloadID = UUID()
  }

  private static func average<C: Collection>(_ values: C) -> Double where C.Element == Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
  }

  private static func storageSize(_ bytes: Double) -> String {
    let value = Int64(exactly: max(0, bytes).rounded(.towardZero)) ?? .max
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
  }

  private static func speedText(_ bytesPerSecond: Double) -> String {
    let clamped = max(0, bytesPerSecond)
    if clamped < 1024 { return String(format: "%.0f B/s", clamped) }
    if clamped < 1024 * 1024 { return String(format: "%.1f KB/s", clamped / 1024) }
    if clamped < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", clamped / (1024 * 1024)) }
    return String(format: "%.2f GB/s", clamped / (1024 * 1024 * 1024))
  }

  private static func formatRuntime(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let days = s / 86400
    let hours = (s % 86400) / 3600
    let minutes = (s % 3600) / 60
    if days > 0 { return "\(days) 天 \(hours) 小时 \(minutes) 分" }
    if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
    return "\(max(1, minutes)) 分钟"
  }

  private static func lastDayLabels(count: Int) -> [String] {
    let cal = Calendar.current
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d"
    return (0..<count).map { offset in
      let daysAgo = count - 1 - offset
      let date = cal.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
      return daysAgo == 0 ? "今天" : formatter.string(from: date)
    }
  }
}

// MARK: - 实时折线微图

private struct NativeSparklineChart: View {
  let values: [Double]
  let maxScale: Double
  let lineColor: Color
  var showFill: Bool = true

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let safeMax = max(maxScale, 1)
      let pts: [CGPoint] =
        if values.count <= 1 {
          [
            CGPoint(x: 0, y: h - CGFloat((values.first ?? 0) / safeMax) * h),
            CGPoint(x: w, y: h - CGFloat((values.first ?? 0) / safeMax) * h),
          ]
        } else {
          values.enumerated().map { idx, val in
            let x = w * CGFloat(idx) / CGFloat(values.count - 1)
            let y = h - CGFloat(min(max(val / safeMax, 0), 1)) * (h - 6) - 3
            return CGPoint(x: x, y: y)
          }
        }
      ZStack {
        if showFill, let first = pts.first, let last = pts.last {
          Path { path in
            path.move(to: CGPoint(x: first.x, y: h))
            for pt in pts { path.addLine(to: pt) }
            path.addLine(to: CGPoint(x: last.x, y: h))
            path.closeSubpath()
          }
          .fill(
            LinearGradient(
              colors: [lineColor.opacity(0.28), lineColor.opacity(0.02)],
              startPoint: .top, endPoint: .bottom)
          )
        }
        Path { path in
          for (idx, pt) in pts.enumerated() {
            if idx == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
          }
        }
        .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
      }
    }
  }
}

// MARK: - 定时任务视觉映射（对齐 Web schedulerVisual.ts，供仪表盘与捷径定时服务共享）

struct NativeSchedulerVisual {
  let symbol: String
  let tint: Color
  let category: Category
  let providerBadge: String?

  enum Category: String {
    case system = "系统任务"
    case agent = "智能助手"
    case workflow = "工作流"
    case plugin = "插件任务"
  }
}

enum NativeSchedulerVisualResolver {
  static func resolve(id: String, name: String, provider: String) -> NativeSchedulerVisual {
    let rawID = id.lowercased()
    let rawName = name.lowercased()
    let rawProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)

    let category: NativeSchedulerVisual.Category
    let badge: String?
    if rawProvider.contains("系统") || rawProvider.isEmpty {
      category = .system
      badge = "系统"
    } else if rawProvider.lowercased().contains("agent") || rawProvider.contains("助手") {
      category = .agent
      badge = "Agent"
    } else if rawProvider.contains("工作流") || rawProvider.lowercased().contains("workflow") {
      category = .workflow
      badge = "工作流"
    } else {
      category = .plugin
      badge = rawProvider.replacingOccurrences(of: "[", with: "").replacingOccurrences(
        of: "]", with: "")
    }

    let key = "\(rawID) \(rawName)"
    if key.contains("cookiecloud") || key.contains("cookie") {
      return .init(
        symbol: "icloud.and.arrow.down", tint: NativeTheme.info, category: category,
        providerBadge: badge)
    }
    if key.contains("mediaserver") || key.contains("媒体服务器") || key.contains("媒体库") {
      return .init(
        symbol: "server.rack", tint: NativeTheme.brand, category: category, providerBadge: badge)
    }
    if key.contains("subscribe_calendar") || key.contains("日历") {
      return .init(
        symbol: "calendar", tint: NativeTheme.pink, category: category, providerBadge: badge)
    }
    if key.contains("subscribe_search") || key.contains("订阅搜索") {
      return .init(
        symbol: "magnifyingglass.circle", tint: NativeTheme.info, category: category,
        providerBadge: badge)
    }
    if key.contains("subscribe") || key.contains("订阅") {
      return .init(
        symbol: "bookmark.fill", tint: NativeTheme.warning, category: category, providerBadge: badge
      )
    }
    if key.contains("transfer") || key.contains("整理") {
      return .init(
        symbol: "folder.badge.gearshape", tint: NativeTheme.success, category: category,
        providerBadge: badge)
    }
    if key.contains("wallpager") || key.contains("wallpaper") || key.contains("壁纸") {
      return .init(
        symbol: "photo.on.rectangle", tint: NativeTheme.pink, category: category,
        providerBadge: badge)
    }
    if key.contains("clear_cache") || key.contains("cleanup") || key.contains("清理")
      || key.contains("gc")
    {
      return .init(
        symbol: "sparkles", tint: NativeTheme.cyan, category: category, providerBadge: badge)
    }
    if key.contains("sitedata") || key.contains("站点") {
      return .init(
        symbol: "globe", tint: NativeTheme.info, category: category, providerBadge: badge)
    }
    if key.contains("recommend") || key.contains("推荐") {
      return .init(
        symbol: "flame.fill", tint: NativeTheme.warning, category: category, providerBadge: badge)
    }
    if key.contains("plugin") || key.contains("插件") {
      return .init(
        symbol: "puzzlepiece.extension.fill", tint: NativeTheme.brand, category: category,
        providerBadge: badge)
    }
    if key.contains("user_auth") || key.contains("认证") {
      return .init(
        symbol: "person.badge.shield.checkmark", tint: NativeTheme.success, category: category,
        providerBadge: badge)
    }
    if category == .agent || key.contains("agent") {
      return .init(
        symbol: "brain.head.profile", tint: NativeTheme.brand, category: category,
        providerBadge: badge)
    }
    if category == .workflow || key.contains("workflow") {
      return .init(
        symbol: "flowchart", tint: NativeTheme.cyan, category: category, providerBadge: badge)
    }
    if category == .plugin {
      return .init(
        symbol: "puzzlepiece.extension", tint: NativeTheme.brand, category: category,
        providerBadge: badge)
    }
    return .init(
      symbol: "clock.arrow.2.circlepath", tint: NativeTheme.info, category: category,
      providerBadge: badge)
  }
}

// MARK: - 解码模型

private struct NativeDashboardStatistics: Decodable, Sendable {
  let movieCountValue: Int?
  let tvCountValue: Int?
  let episodeCountValue: Int?
  let musicCountValue: Int?
  let movieCountMonthValue: Int?
  let tvCountMonthValue: Int?
  let episodeCountMonthValue: Int?
  let musicCountMonthValue: Int?

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

  var movieCount: Int { max(0, movieCountValue ?? 0) }
  var tvCount: Int { max(0, tvCountValue ?? 0) }
  var episodeCount: Int? { episodeCountValue.map { max(0, $0) } }
  var musicCount: Int { max(0, musicCountValue ?? 0) }
  var movieCountMonth: Int { max(0, movieCountMonthValue ?? 0) }
  var tvCountMonth: Int { max(0, tvCountMonthValue ?? 0) }
  var episodeCountMonth: Int { max(0, episodeCountMonthValue ?? 0) }
  var musicCountMonth: Int { max(0, musicCountMonthValue ?? 0) }
}

private struct NativeDashboardStorage: Decodable, Sendable {
  let totalStorageValue: Double?
  let usedStorageValue: Double?

  private enum CodingKeys: String, CodingKey {
    case totalStorageValue = "total_storage"
    case usedStorageValue = "used_storage"
  }

  var totalStorage: Double { max(0, totalStorageValue ?? 0) }
  var usedStorage: Double { max(0, usedStorageValue ?? 0) }
  var usage: Double {
    guard totalStorage > 0, usedStorage.isFinite else { return 0 }
    return min(1, max(0, usedStorage / totalStorage))
  }
}

private struct NativeDashboardRecentImportsResponse: Decodable, Sendable {
  let list: [NativeDashboardRecentImport]?
}

private struct NativeDashboardRecentImport: Decodable, Sendable, Identifiable {
  let id: Int
  let title: String?
  let seasons: String?
  let episodes: String?
  let mode: String?
  let status: Bool?
  let date: String?
  let image: String?

  var displayTitle: String {
    if let title, !title.isEmpty { return title }
    return "记录 #\(id)"
  }

  var seasonEpisodeText: String {
    [seasons, episodes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
  }

  var modeLabel: String? {
    switch (mode ?? "").lowercased() {
    case "link": "硬链接"
    case "softlink": "软链接"
    case "copy": "复制"
    case "move": "移动"
    case "rclone_copy": "Rclone 复制"
    case "rclone_move": "Rclone 移动"
    case "": nil
    default: mode
    }
  }
}

private struct NativeDashboardDownloaderInfo: Decodable, Sendable {
  let downloadSpeedValue: Double?
  let uploadSpeedValue: Double?
  let downloadSizeValue: Double?
  let uploadSizeValue: Double?
  let freeSpaceValue: Double?

  var downloadSpeed: Double { max(0, downloadSpeedValue ?? 0) }
  var uploadSpeed: Double { max(0, uploadSpeedValue ?? 0) }
  var downloadSize: Double { max(0, downloadSizeValue ?? 0) }
  var uploadSize: Double { max(0, uploadSizeValue ?? 0) }
  var freeSpace: Double { max(0, freeSpaceValue ?? 0) }

  private enum CodingKeys: String, CodingKey {
    case downloadSpeedValue = "download_speed"
    case uploadSpeedValue = "upload_speed"
    case downloadSizeValue = "download_size"
    case uploadSizeValue = "upload_size"
    case freeSpaceValue = "free_space"
  }
}

private struct NativeDashboardDownloadTask: Decodable, Sendable, Identifiable {
  let hash: String?
  let title: String?
  let name: String?
  let progress: Double?
  let state: String?
  let dlspeed: String?
  let leftTime: String?

  var id: String { hash ?? title ?? name ?? UUID().uuidString }
  var displayTitle: String {
    if let title, !title.isEmpty { return title }
    if let name, !name.isEmpty { return name }
    return "下载任务"
  }
  var normalizedProgress: Double {
    let raw = progress ?? 0
    if raw > 1 { return min(max(raw / 100.0, 0), 1) }
    return min(max(raw, 0), 1)
  }

  private enum CodingKeys: String, CodingKey {
    case hash, title, name, progress, state, dlspeed
    case leftTime = "left_time"
  }
}

private struct NativeDashboardMemoryInfo: Decodable, Sendable {
  let total: Int64
  let used: Int64
  let cached: Int64
  let available: Int64
  let usage: Double?

  var usageRatio: Double {
    if let usage, usage.isFinite {
      return min(max(usage > 1 ? usage / 100.0 : usage, 0), 1)
    }
    guard total > 0 else { return 0 }
    return min(max(Double(used) / Double(total), 0), 1)
  }

  private enum CodingKeys: String, CodingKey {
    case total, used, cached, available, usage
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    total = (try? c.decode(Int64.self, forKey: .total)) ?? 0
    used = (try? c.decode(Int64.self, forKey: .used)) ?? 0
    cached = (try? c.decode(Int64.self, forKey: .cached)) ?? 0
    available = (try? c.decode(Int64.self, forKey: .available)) ?? 0
    usage = try? c.decode(Double.self, forKey: .usage)
  }
}

private struct NativeDashboardSystemInfo: Decodable, Sendable {
  let hostname: String
  let operatingSystem: String
  let runtime: Int
  let version: String

  private enum CodingKeys: String, CodingKey {
    case hostname, runtime, version
    case operatingSystem = "operating_system"
  }
}

private struct NativeDashboardSchedule: Decodable, Sendable {
  let id: String?
  let name: String?
  let nameI18n: String?
  let provider: String?
  let status: String?
  let statusI18n: String?
  let nextRun: String?
  let nextRunI18n: String?
  let progress: Double?
  let progressText: String?
  let progressTextI18n: String?
  let progressEnable: Bool?
  let progressDetail: ProgressDetail?

  private enum CodingKeys: String, CodingKey {
    case id, name, provider, status, progress
    case nameI18n = "name_i18n"
    case statusI18n = "status_i18n"
    case nextRun = "next_run"
    case nextRunI18n = "next_run_i18n"
    case progressText = "progress_text"
    case progressTextI18n = "progress_text_i18n"
    case progressEnable = "progress_enable"
    case progressDetail = "progress_detail"
  }

  var isRunning: Bool {
    status == "正在运行" || progressEnable == true
      || progressDetail?.enable == true || progressDetail?.status == "running"
  }

  var runningFraction: Double? {
    guard isRunning, let value = progressDetail?.value ?? progress, value.isFinite else {
      return nil
    }
    return min(100, max(0, value)) / 100
  }

  var summary: String {
    if isRunning {
      return progressDetail?.textI18n ?? progressDetail?.text ?? progressTextI18n ?? progressText
        ?? statusI18n ?? status ?? "正在运行"
    }
    return nextRunI18n ?? nextRun ?? statusI18n ?? status ?? "等待下次运行"
  }

  struct ProgressDetail: Decodable, Sendable {
    let enable: Bool?
    let status: String?
    let value: Double?
    let text: String?
    let textI18n: String?

    private enum CodingKeys: String, CodingKey {
      case enable, status, value, text
      case textI18n = "text_i18n"
    }
  }
}

private struct NativeDashboardPluginMeta: Decodable, Sendable {
  let id: String
  let name: String?
  let key: String?
}

private struct NativeDashboardPluginPayload: Decodable, Sendable {
  struct Attrs: Decodable, Sendable {
    let border: Bool?
    let title: String?
    let subtitle: String?
    let refresh: Int?
  }

  let name: String?
  let renderMode: String?
  let attrs: Attrs?
  let elements: [JSONValue]?

  private enum CodingKeys: String, CodingKey {
    case name, attrs, elements
    case renderMode = "render_mode"
  }
}

private struct NativeDashboardPluginWidget: Identifiable, Sendable {
  let id: String
  let pluginID: String
  let title: String
  let attrTitle: String?
  let subtitle: String?
  let showBorder: Bool
  let isVueRemote: Bool
  let nodes: [NativePluginJSONNode]

  var displayTitle: String {
    if let attrTitle, !attrTitle.isEmpty { return attrTitle }
    return title
  }
}

/// 可编排的仪表盘组件配置（全量覆盖内置监控组件及所有插件注册的 JSON 仪表板组件）。
private struct NativeDashboardWidgetConfig: Identifiable, Codable, Equatable, Sendable {
  let id: String
  var title: String
  var symbol: String
  var enabled: Bool

  static let defaults: [NativeDashboardWidgetConfig] = [
    NativeDashboardWidgetConfig(
      id: "communityMedals", title: "社区勋章", symbol: "medal.fill", enabled: true),
    NativeDashboardWidgetConfig(
      id: "statistics", title: "媒体库统计", symbol: "film.stack", enabled: true),
    NativeDashboardWidgetConfig(
      id: "storage", title: "存储空间", symbol: "externaldrive", enabled: true),
    NativeDashboardWidgetConfig(
      id: "downloader", title: "下载器", symbol: "arrow.down.circle", enabled: true),
    NativeDashboardWidgetConfig(
      id: "recentImports", title: "最近入库", symbol: "tray.and.arrow.down", enabled: true),
    NativeDashboardWidgetConfig(
      id: "cpu", title: "CPU 占用", symbol: "cpu", enabled: true),
    NativeDashboardWidgetConfig(
      id: "memory", title: "内存占用", symbol: "memorychip", enabled: true),
    NativeDashboardWidgetConfig(
      id: "network", title: "实时网络", symbol: "network", enabled: true),
    NativeDashboardWidgetConfig(
      id: "transferTrend", title: "整理趋势", symbol: "chart.bar.fill", enabled: true),
    NativeDashboardWidgetConfig(
      id: "schedules", title: "后台服务", symbol: "clock.arrow.2.circlepath", enabled: true),
    NativeDashboardWidgetConfig(
      id: "systemInfo", title: "系统信息", symbol: "info.circle", enabled: false),
  ]

  static func merged(
    saved: [NativeDashboardWidgetConfig], plugins: [NativeDashboardPluginWidget]
  ) -> [NativeDashboardWidgetConfig] {
    var available: [String: NativeDashboardWidgetConfig] = Dictionary(
      uniqueKeysWithValues: defaults.map { ($0.id, $0) })
    for plugin in plugins {
      let key = "plugin:\(plugin.id)"
      available[key] = NativeDashboardWidgetConfig(
        id: key, title: plugin.displayTitle, symbol: "puzzlepiece.extension", enabled: true)
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
      if base.id == "communityMedals" {
        result.insert(base, at: 0)
      } else {
        result.append(base)
      }
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

/// 仪表盘组件编排弹层：支持开关显隐与拖拽排序。
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
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") {
            onSave(items)
            dismiss()
          }
          .fontWeight(.semibold)
          .tint(.primary)
          .accessibilityIdentifier("native-dashboard-widgets-save")
        }
      }
    }
    .nativeGlassSheet()
  }
}

private struct PresentedCommunityMedalKey: Identifiable {
  let key: String
  var id: String { key }
}

private struct NativeDashboardCacheSnapshot {
  let statistics: NativeDashboardStatistics?
  let storage: NativeDashboardStorage?
  let recentImports: [NativeDashboardRecentImport]
  let downloader: NativeDashboardDownloaderInfo?
  let activeDownloads: [NativeDashboardDownloadTask]
  let cpuSamples: [Double]
  let memory: NativeDashboardMemoryInfo?
  let networkSamples: [(up: Double, down: Double)]
  let transferTrend: [Int]
  let schedules: [NativeDashboardSchedule]?
  let systemInfo: NativeDashboardSystemInfo?
  let pluginWidgets: [NativeDashboardPluginWidget]
  let communityProfile: CommunityProfile?
}
