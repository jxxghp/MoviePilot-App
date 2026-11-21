import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotSession
import SwiftUI

/// 原生插件市场与生命周期管理页：支持市场检索/筛选/安装/更新与已安装插件的配置、重置和卸载，仅超级管理员可见。
@MainActor
struct NativePluginMarketPage: View {
  /// 顶部两大视图模式。
  enum Mode: String, CaseIterable, Identifiable {
    case market = "插件市场"
    case installed = "已安装管理"

    /// 稳定模式标识。
    var id: String { rawValue }
  }

  /// 市场子筛选。
  enum MarketFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case updatable = "可更新"
    case notInstalled = "未安装"

    /// 稳定筛选标识。
    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var mode: Mode = .market
  @State private var marketFilter: MarketFilter = .all
  @State private var marketPlugins: [NativeMarketPluginRecord] = []
  @State private var installedPlugins: [NativeMarketPluginRecord] = []
  @State private var installStats: [String: Int] = [:]
  @State private var ratings: [String: NativePluginRatingSummary] = [:]
  @State private var marketPage = 1
  @State private var marketHasMore = true
  @State private var isLoadingMore = false
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var mutatingID: String?
  @State private var pendingInstall: NativeMarketPluginRecord?
  @State private var pendingReset: NativeMarketPluginRecord?
  @State private var pendingUninstall: NativeMarketPluginRecord?
  @State private var feedback: NativePluginMarketFeedback?
  @State private var formSelection: FormSelection?
  @State private var dataPageSelection: NativeMarketPluginRecord?

  /// 复用既有 `NativePluginFormView` 打开已安装插件配置。
  private struct FormSelection {
    let plugin: NativeInstalledPlugin
    let form: NativePluginForm
  }

  /// 连续紫玫瑰深色渐变、模式切换胶囊、筛选条与插件玻璃卡片列表。
  var body: some View {
    contentWithNavigation
      .alert(
        pendingInstall?.hasUpdate == true ? "更新插件" : "安装插件",
        isPresented: Binding(
          get: { pendingInstall != nil }, set: { if !$0 { pendingInstall = nil } }),
        presenting: pendingInstall
      ) { plugin in
        Button(plugin.hasUpdate ? "确认更新" : "确认安装") {
          Task { await installPlugin(plugin) }
        }
        Button("取消", role: .cancel) {}
      } message: { plugin in
        Text("确认从插件仓库安装「\(plugin.displayName)」v\(plugin.version) 吗？")
      }
      .alert(
        "重置插件",
        isPresented: Binding(get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } }),
        presenting: pendingReset
      ) { plugin in
        Button("确认重置", role: .destructive) {
          Task { await resetPlugin(plugin) }
        }
        Button("取消", role: .cancel) {}
      } message: { plugin in
        Text("重置将清空「\(plugin.displayName)」的配置与本地数据，确认继续吗？")
      }
      .alert(
        "卸载插件",
        isPresented: Binding(
          get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
        presenting: pendingUninstall
      ) { plugin in
        Button("确认卸载", role: .destructive) {
          Task { await uninstallPlugin(plugin) }
        }
        Button("取消", role: .cancel) {}
      } message: { plugin in
        Text("确认卸载插件「\(plugin.displayName)」吗？卸载后将停止相关后台任务。")
      }
  }

  /// 主体与导航栏、工具栏、搜索和表单路由修饰。
  private var contentWithNavigation: some View {
    mainContent
      .navigationTitle(mode == .market ? "插件市场" : "插件管理")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .searchable(text: $searchText, prompt: "搜索插件名称、作者或标签")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          moreToolbarMenu
        }
      }
      .navigationDestination(
        isPresented: Binding(
          get: { formSelection != nil }, set: { if !$0 { formSelection = nil } })
      ) {
        if let formSelection {
          NativePluginFormView(plugin: formSelection.plugin, form: formSelection.form)
        }
      }
      .navigationDestination(
        isPresented: Binding(
          get: { dataPageSelection != nil }, set: { if !$0 { dataPageSelection = nil } })
      ) {
        if let plugin = dataPageSelection {
          NativePluginDataPageView(
            session: session, pluginID: plugin.id, pluginName: plugin.displayName)
        }
      }
      .task(id: "\(mode.rawValue)|\(reloadToken)") { await load(forceMarket: false) }
  }

  /// 右上角更多操作菜单。
  private var moreToolbarMenu: some View {
    Menu {
      Button {
        Task { await load(forceMarket: true) }
      } label: {
        Label("同步最新市场数据", systemImage: "arrow.triangle.2.circlepath")
      }
      Button {
        reloadToken += 1
      } label: {
        Label("刷新当前列表", systemImage: "arrow.clockwise")
      }
    } label: {
      Image(systemName: "ellipsis")
    }
    .accessibilityLabel("更多插件操作")
    .accessibilityIdentifier("native-plugin-market-refresh")
  }

  /// 主滚动内容区。
  private var mainContent: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          modeBar
          if mode == .market {
            marketFilterBar
          }
          if let feedback {
            feedbackBanner(feedback)
          }
          listSection
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load(forceMarket: mode == .market) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-plugin-market-scroll")
    }
  }

  /// 加载态、失败态、空态或插件卡片列表。
  @ViewBuilder
  private var listSection: some View {
    if isLoading && activeItems.isEmpty {
      ProgressView(mode == .market ? "正在载入插件市场…" : "正在载入已安装插件…")
        .tint(.primary)
        .frame(maxWidth: .infinity, minHeight: 220)
    } else if loadFailed && activeItems.isEmpty {
      failureCard
    } else if filteredItems.isEmpty {
      emptyCard
    } else {
      LazyVStack(spacing: 12) {
        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, plugin in
          pluginCard(plugin)
            .onAppear {
              if mode == .market && marketHasMore && !isLoadingMore
                && index >= max(0, filteredItems.count - 8)
              {
                Task { await loadMoreMarket() }
              }
            }
        }
        if mode == .market && isLoadingMore {
          ProgressView().tint(.primary).padding(.vertical, 10)
        }
      }
    }
  }

  /// 当前视图对应的全量插件数组。
  private var activeItems: [NativeMarketPluginRecord] {
    mode == .market ? marketPlugins : installedPlugins
  }

  /// 按筛选与关键词过滤后的插件列表。
  private var filteredItems: [NativeMarketPluginRecord] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return activeItems.filter { plugin in
      if mode == .market {
        switch marketFilter {
        case .all: break
        case .updatable: guard plugin.hasUpdate else { return false }
        case .notInstalled: guard !plugin.installed else { return false }
        }
      }
      guard !trimmed.isEmpty else { return true }
      return plugin.displayName.lowercased().contains(trimmed)
        || plugin.summary.lowercased().contains(trimmed)
        || plugin.author.lowercased().contains(trimmed)
        || plugin.labels.contains(where: { $0.lowercased().contains(trimmed) })
    }
  }

  /// 顶部模式切换胶囊。
  private var modeBar: some View {
    HStack(spacing: 8) {
      ForEach(Mode.allCases) { option in
        let active = mode == option
        Button {
          mode = option
        } label: {
          Text(option.rawValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? .white : .white.opacity(0.75))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
              Capsule()
                .fill(
                  active
                    ? Color(red: 0.58, green: 0.42, blue: 0.88).opacity(0.78)
                    : .white.opacity(0.08)
                )
                .overlay {
                  Capsule().strokeBorder(.primary.opacity(active ? 0.32 : 0.14), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-plugin-mode-\(option.rawValue)")
      }
      Spacer(minLength: 0)
    }
  }

  /// 插件市场状态过滤胶囊。
  private var marketFilterBar: some View {
    HStack(spacing: 8) {
      ForEach(MarketFilter.allCases) { option in
        let active = marketFilter == option
        Button {
          marketFilter = option
        } label: {
          Text(option.rawValue)
            .font(.caption.weight(active ? .semibold : .medium))
            .foregroundStyle(active ? .white : .white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
              Capsule()
                .fill(.white.opacity(active ? 0.20 : 0.08))
                .overlay {
                  Capsule().strokeBorder(.primary.opacity(active ? 0.28 : 0.12), lineWidth: 0.6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-plugin-market-filter-\(option.rawValue)")
      }
      Spacer(minLength: 0)
    }
  }

  /// 单张插件玻璃卡片：还原网页版 `PluginCard`/`PluginAppCard` 上下双段布局（顶部标题+简介+右侧真实图标，底部创作者头像/署名/下载量/星级铭牌栏），管理动作统一收纳进点按与长按菜单。
  private func pluginCard(_ plugin: NativeMarketPluginRecord) -> some View {
    let isMutating = mutatingID == plugin.id
    let isInactive = mode == .installed && !plugin.isRunning
    let lowerID = plugin.id.lowercased()
    let downloads = max(
      plugin.installCount, installStats[plugin.id] ?? installStats[lowerID] ?? 0)
    let fetchedRating = ratings[plugin.id] ?? ratings[lowerID]
    let effectiveRating = fetchedRating?.averageRating ?? plugin.averageRating
    let accent = Self.pluginAccentColor(from: plugin.pluginColor)

    return CinematicPanel(padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        // 上段横幅：状态点 + 标题 + 版本 + 状态胶囊 / 左侧简介与标签 + 右侧 44×44 真实插件图标
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 6) {
            if mode == .installed {
              Circle()
                .fill(
                  plugin.isRunning
                    ? Color(red: 0.42, green: 0.90, blue: 0.62)
                    : .white.opacity(0.32)
                )
                .frame(width: 7, height: 7)
            }
            Text(plugin.displayName)
              .font(.headline.weight(.semibold))
              .foregroundStyle(.primary.opacity(isInactive ? 0.80 : 0.98))
              .lineLimit(1)
            if !plugin.version.isEmpty {
              Text("v\(plugin.version)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary.opacity(0.56))
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isMutating {
              ProgressView().controlSize(.mini).tint(.primary)
            } else {
              statusBadge(plugin)
            }
          }

          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
              if !plugin.summary.isEmpty {
                Text(plugin.summary)
                  .font(.caption)
                  .foregroundStyle(.primary.opacity(0.76))
                  .lineLimit(3)
                  .fixedSize(horizontal: false, vertical: true)
              }
              if mode == .market && !plugin.labels.isEmpty {
                HStack(spacing: 5) {
                  ForEach(plugin.labels.prefix(3), id: \.self) { label in
                    Text(label)
                      .font(.caption2.weight(.medium))
                      .foregroundStyle(Color(red: 0.84, green: 0.76, blue: 1.0))
                      .padding(.horizontal, 6.5)
                      .padding(.vertical, 2)
                      .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                          .fill(Color(red: 0.54, green: 0.44, blue: 0.92).opacity(0.16))
                          .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                              .strokeBorder(
                                Color(red: 0.74, green: 0.64, blue: 1.0).opacity(0.22),
                                lineWidth: 0.5)
                          }
                      }
                      .lineLimit(1)
                  }
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NativePluginIconView(
              session: session,
              iconReference: plugin.pluginIcon,
              size: 46,
              cornerRadius: 12,
              inactive: isInactive
            )
          }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(
          LinearGradient(
            colors: [accent.opacity(isInactive ? 0.04 : 0.14), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
        )

        Divider().overlay(.primary.opacity(0.08))

        // 下段创作者生态铭牌栏：左作者头像+署名，右下载量+星级评分
        HStack(spacing: 8) {
          HStack(spacing: 6) {
            NativePluginAuthorAvatarView(
              authorURL: plugin.authorURL,
              authorName: plugin.author,
              size: 20
            )
            Text(plugin.author.isEmpty ? "MoviePilot" : plugin.author)
              .font(.caption.weight(.medium))
              .foregroundStyle(.primary.opacity(0.72))
              .lineLimit(1)
          }
          Spacer(minLength: 8)
          if downloads > 0 {
            HStack(spacing: 3) {
              Image(systemName: "arrow.down.circle")
                .font(.system(size: 11, weight: .medium))
              Text(Self.formatInstallCount(downloads))
                .font(.caption2.monospacedDigit().weight(.medium))
            }
            .foregroundStyle(.primary.opacity(0.70))
          }
          if effectiveRating > 0 {
            HStack(spacing: 2.5) {
              Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.34))
              Text(String(format: "%.1f", effectiveRating))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color(red: 0.98, green: 0.84, blue: 0.48))
            }
          }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(.white.opacity(0.035))
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onTapGesture {
      guard mutatingID == nil else { return }
      if mode == .market {
        if !plugin.installed || plugin.hasUpdate {
          pendingInstall = plugin
        } else {
          openForm(for: plugin)
        }
      } else {
        if plugin.hasPage {
          dataPageSelection = plugin
        } else {
          openForm(for: plugin)
        }
      }
    }
    .contextMenu {
      if mode == .market {
        if !plugin.installed || plugin.hasUpdate {
          Button {
            pendingInstall = plugin
          } label: {
            Label(
              plugin.hasUpdate ? "更新插件" : "安装插件",
              systemImage: plugin.hasUpdate
                ? "arrow.triangle.2.circlepath" : "arrow.down.to.line")
          }
        } else {
          Button {
            openForm(for: plugin)
          } label: {
            Label("打开插件配置", systemImage: "slider.horizontal.3")
          }
        }
      } else {
        if plugin.hasPage {
          Button {
            dataPageSelection = plugin
          } label: {
            Label("查看数据页", systemImage: "doc.text.magnifyingglass")
          }
        }
        Button {
          openForm(for: plugin)
        } label: {
          Label("插件配置", systemImage: "slider.horizontal.3")
        }
        if plugin.hasUpdate {
          Button {
            pendingInstall = plugin
          } label: {
            Label("更新插件", systemImage: "arrow.triangle.2.circlepath")
          }
        }
        Button {
          pendingReset = plugin
        } label: {
          Label("重置插件", systemImage: "arrow.counterclockwise")
        }
        Button(role: .destructive) {
          pendingUninstall = plugin
        } label: {
          Label("卸载插件", systemImage: "trash")
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(
      mode == .market ? "native-market-card-\(plugin.id)" : "native-installed-card-\(plugin.id)")
  }

  /// 解析插件主题色十六进制字符串为温和卡片高光色。
  private static func pluginAccentColor(from hex: String?) -> Color {
    guard let hex else { return Color(red: 0.56, green: 0.44, blue: 0.92) }
    let cleaned = hex.trimmingCharacters(
      in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
      return Color(red: 0.56, green: 0.44, blue: 0.92)
    }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
  }

  /// 紧凑格式化插件累计安装/下载次数。
  private static func formatInstallCount(_ count: Int) -> String {
    if count >= 10_000 {
      return String(format: "%.1fw", Double(count) / 10_000.0)
    }
    if count >= 1_000 {
      return String(format: "%.1fk", Double(count) / 1_000.0)
    }
    return "\(count)"
  }

  /// 插件安装/更新/运行状态徽标。
  @ViewBuilder
  private func statusBadge(_ plugin: NativeMarketPluginRecord) -> some View {
    if plugin.hasUpdate {
      badgePill("有更新", tint: Color(red: 0.98, green: 0.78, blue: 0.44))
    } else if mode == .market && plugin.installed {
      badgePill("已安装", tint: Color(red: 0.56, green: 0.92, blue: 0.72))
    } else if mode == .installed {
      badgePill(
        plugin.isRunning ? "运行中" : "未启用",
        tint: plugin.isRunning ? Color(red: 0.56, green: 0.92, blue: 0.72) : .white.opacity(0.58))
    }
  }

  /// 紧凑胶囊徽标。
  private func badgePill(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background {
        Capsule()
          .fill(.primary.opacity(0.10))
          .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
      }
  }

  /// 操作反馈横幅。
  private func feedbackBanner(_ feedback: NativePluginMarketFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.65)).frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-plugin-market-feedback")
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "puzzlepiece.extension")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text("暂无匹配的插件").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 失败重试卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入插件列表", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { reloadToken += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-plugin-market-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 按模式读取 `GET /api/v1/plugin/?state=market|installed`；市场分页拉取每页 60 条提升首屏速度。
  private func load(forceMarket: Bool) async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    let stateValue = mode == .market ? "market" : "installed"
    var query = [URLQueryItem(name: "state", value: stateValue)]
    if mode == .market {
      marketPage = 1
      marketHasMore = true
      query.append(URLQueryItem(name: "page", value: "1"))
      query.append(URLQueryItem(name: "count", value: "60"))
      if forceMarket { query.append(URLQueryItem(name: "force", value: "true")) }
    }
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"],
        query: query,
        maximumResponseBytes: 8 * 1024 * 1024,
        trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeMarketPluginRecord].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      try Task.checkCancellation()
      let valid = loaded.filter { !$0.id.isEmpty }
      if mode == .market {
        marketPlugins = valid
        marketHasMore = valid.count >= 60
      } else {
        installedPlugins = valid
      }
      Task { await loadPluginStatsAndRatings(pluginIDs: valid.map(\.id)) }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 后台静默补齐插件安装量统计与评分映射（`GET /api/v1/plugin/statistic` + `GET /api/v1/plugin/rating`），兼容大小写插件 ID。
  private func loadPluginStatsAndRatings(pluginIDs: [String]) async {
    async let statsTask: [String: Int]? = {
      guard let ep = try? APIEndpoint(path: ["plugin", "statistic"]) else { return nil }
      return try? await session.request(
        ep, as: [String: Int].self, requiring: PermissionRequirement(category: .admin)
      ).value
    }()
    let idsParam = pluginIDs.prefix(80).joined(separator: ",")
    async let ratingsTask: [String: NativePluginRatingSummary]? = {
      let query = idsParam.isEmpty ? [] : [URLQueryItem(name: "plugin_ids", value: idsParam)]
      guard let ep = try? APIEndpoint(path: ["plugin", "rating"], query: query) else { return nil }
      return try? await session.request(
        ep, as: [String: NativePluginRatingSummary].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    }()
    let (loadedStats, loadedRatings) = await (statsTask, ratingsTask)
    guard !Task.isCancelled else { return }
    if let loadedStats, !loadedStats.isEmpty {
      var merged = installStats
      for (key, value) in loadedStats {
        merged[key] = value
        merged[key.lowercased()] = value
      }
      installStats = merged
    }
    if let loadedRatings, !loadedRatings.isEmpty {
      var merged = ratings
      for (key, value) in loadedRatings {
        merged[key] = value
        merged[key.lowercased()] = value
      }
      ratings = merged
    }
  }

  /// 滚动至市场底部时自动加载下一页插件。
  private func loadMoreMarket() async {
    guard mode == .market, marketHasMore, !isLoadingMore, !isLoading else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    let nextPage = marketPage + 1
    let query = [
      URLQueryItem(name: "state", value: "market"),
      URLQueryItem(name: "page", value: String(nextPage)),
      URLQueryItem(name: "count", value: "60"),
    ]
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"], query: query, maximumResponseBytes: 8 * 1024 * 1024, trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeMarketPluginRecord].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      try Task.checkCancellation()
      let valid = loaded.filter { !$0.id.isEmpty }
      if valid.isEmpty {
        marketHasMore = false
        return
      }
      var seen = Set(marketPlugins.map(\.id))
      let appended = valid.filter { seen.insert($0.id).inserted }
      marketPlugins.append(contentsOf: appended)
      marketPage = nextPage
      marketHasMore = valid.count >= 60 && !appended.isEmpty
    } catch {
      return
    }
  }

  /// 打开现有原生 JSON 插件配置表单。
  private func openForm(for record: NativeMarketPluginRecord) {
    do {
      let payload = try JSONEncoder().encode(record)
      let installed = try JSONDecoder().decode(NativeInstalledPlugin.self, from: payload)
      let form = try NativePluginForm(
        session: session, target: installed.target, validator: NativeFormValidator())
      formSelection = FormSelection(plugin: installed, form: form)
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "无法打开该插件的原生配置。")
    }
  }

  /// 单次请求安装或更新插件（`GET /api/v1/plugin/install/{id}`）。
  private func installPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    var query = [URLQueryItem(name: "force", value: "true")]
    if let repo = plugin.repoURL, !repo.isEmpty {
      query.append(URLQueryItem(name: "repo_url", value: repo))
    }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", "install", plugin.id], query: query)
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      if let idx = marketPlugins.firstIndex(where: { $0.id == plugin.id }) {
        marketPlugins[idx].installed = true
        marketPlugins[idx].hasUpdate = false
      }
      feedback = NativePluginMarketFeedback(
        isError: false, message: "「\(plugin.displayName)」安装/更新已完成。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "安装插件失败，请检查仓库连通性后重试。")
    }
  }

  /// 确认后单次重置插件配置及数据（`GET /api/v1/plugin/reset/{id}`）。
  private func resetPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", "reset", plugin.id])
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      feedback = NativePluginMarketFeedback(isError: false, message: "已重置「\(plugin.displayName)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "重置插件失败，请稍后重试。")
    }
  }

  /// 确认后单次卸载插件（`DELETE /api/v1/plugin/{id}`）。
  private func uninstallPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", plugin.id], method: .delete)
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      try Task.checkCancellation()
      installedPlugins.removeAll { $0.id == plugin.id }
      feedback = NativePluginMarketFeedback(isError: false, message: "已卸载「\(plugin.displayName)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "卸载插件失败，请先移除关联分身或稍后重试。")
    }
  }
}

/// 插件市场操作提示载体。
private struct NativePluginMarketFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/plugin/rating` 单插件平均分与评分人数投影。
private struct NativePluginRatingSummary: Decodable, Sendable {
  let averageRating: Double
  let ratingCount: Int

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    averageRating = (try? c.decodeIfPresent(Double.self, forKey: .averageRating)) ?? 0
    ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case averageRating = "average_rating"
    case ratingCount = "rating_count"
  }
}

/// 插件市场与已安装插件统一编解码模型。
private struct NativeMarketPluginRecord: Codable, Sendable, Identifiable {
  let id: String
  let pluginName: String?
  let pluginDesc: String?
  let pluginIcon: String?
  let pluginColor: String?
  let pluginVersion: String?
  let pluginLabel: String?
  let pluginAuthor: String?
  let authorURL: String?
  var installed: Bool
  var hasUpdate: Bool
  let hasPage: Bool
  let state: Bool?
  let repoURL: String?
  let installCount: Int
  let averageRating: Double
  let ratingCount: Int

  /// 显示名称回退至插件 ID。
  var displayName: String {
    if let pluginName, !pluginName.isEmpty { return pluginName }
    return id
  }

  /// 插件简介。
  var summary: String { pluginDesc ?? "" }

  /// 插件版本。
  var version: String { pluginVersion ?? "" }

  /// 作者名。
  var author: String { pluginAuthor ?? "" }

  /// 运行状态。
  var isRunning: Bool { state ?? false }

  /// 拆分逗号分隔标签。
  var labels: [String] {
    (pluginLabel ?? "")
      .split(whereSeparator: { $0 == "," || $0 == "，" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// 解码后端 `_SchemaPlugin` 非敏感元数据。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
    pluginName = try? container.decodeIfPresent(String.self, forKey: .pluginName)
    pluginDesc = try? container.decodeIfPresent(String.self, forKey: .pluginDesc)
    pluginIcon = try? container.decodeIfPresent(String.self, forKey: .pluginIcon)
    pluginColor = try? container.decodeIfPresent(String.self, forKey: .pluginColor)
    pluginVersion = try? container.decodeIfPresent(String.self, forKey: .pluginVersion)
    pluginLabel = try? container.decodeIfPresent(String.self, forKey: .pluginLabel)
    pluginAuthor = try? container.decodeIfPresent(String.self, forKey: .pluginAuthor)
    authorURL = try? container.decodeIfPresent(String.self, forKey: .authorURL)
    installed = (try? container.decodeIfPresent(Bool.self, forKey: .installed)) ?? false
    hasUpdate = (try? container.decodeIfPresent(Bool.self, forKey: .hasUpdate)) ?? false
    hasPage = (try? container.decodeIfPresent(Bool.self, forKey: .hasPage)) ?? false
    state = try? container.decodeIfPresent(Bool.self, forKey: .state)
    repoURL = try? container.decodeIfPresent(String.self, forKey: .repoURL)
    installCount = (try? container.decodeIfPresent(Int.self, forKey: .installCount)) ?? 0
    averageRating = (try? container.decodeIfPresent(Double.self, forKey: .averageRating)) ?? 0
    ratingCount = (try? container.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case pluginName = "plugin_name"
    case pluginDesc = "plugin_desc"
    case pluginIcon = "plugin_icon"
    case pluginColor = "plugin_color"
    case pluginVersion = "plugin_version"
    case pluginLabel = "plugin_label"
    case pluginAuthor = "plugin_author"
    case authorURL = "author_url"
    case installed
    case hasUpdate = "has_update"
    case hasPage = "has_page"
    case state
    case repoURL = "repo_url"
    case installCount = "install_count"
    case averageRating = "average_rating"
    case ratingCount = "rating_count"
  }
}
