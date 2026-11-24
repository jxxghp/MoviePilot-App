import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotPluginForms
import MoviePilotSession
import SwiftUI

/// 原生插件管理主页面（对标十.7、十一.3、十一.4）：
/// 默认展示已安装插件，页面内不再展示市场/已安装切换栏和状态筛选条；
/// 右上角固定展示「插件市场」图标与「筛选/排序」图标，长按卡片提供完整运维与分身菜单。
@MainActor
struct NativePluginMarketPage: View {
  /// 已安装插件状态过滤（收纳于右上角菜单）。
  enum InstalledFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case running = "运行中"
    case stopped = "未启用"
    case updatable = "有更新"
    var id: String { rawValue }
  }

  /// 插件列表排序方式。
  enum SortMode: String, CaseIterable, Identifiable {
    case defaultOrder = "默认顺序"
    case nameAsc = "名称排序"
    case installsDesc = "安装量最高"
    case ratingDesc = "评分最高"
    var id: String { rawValue }
  }

  let session: NativeSession

  @Environment(\.openURL) private var openURL
  @State private var installedFilter: InstalledFilter = .all
  @State private var sortMode: SortMode = .defaultOrder
  @State private var installedPlugins: [NativeMarketPluginRecord] = []
  @State private var installStats: [String: Int] = [:]
  @State private var ratings: [String: NativePluginRatingSummary] = [:]
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var mutatingID: String?

  @State private var showsMarketPage = false
  @State private var formSelection: FormSelection?
  @State private var dataPageSelection: NativeMarketPluginRecord?
  @State private var vueSheetTarget: VueSheetTarget?
  @State private var detailTarget: NativeMarketPluginRecord?
  @State private var versionHistoryTarget: NativeMarketPluginRecord?
  @State private var cloneTarget: NativeMarketPluginRecord?
  @State private var logTarget: NativeMarketPluginRecord?
  @State private var capabilitiesTarget: NativeMarketPluginRecord?
  @State private var dataSummaryTarget: NativeMarketPluginRecord?
  @State private var instanceManageTarget: NativeMarketPluginRecord?

  @State private var pendingInstall: NativeMarketPluginRecord?
  @State private var pendingReset: NativeMarketPluginRecord?
  @State private var pendingUninstall: NativeMarketPluginRecord?
  @State private var feedback: NativePluginMarketFeedback?
  @State private var containerWidth: CGFloat = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private struct FormSelection {
    let plugin: NativeInstalledPlugin
    let form: NativePluginForm
  }

  private struct VueSheetTarget: Identifiable {
    let plugin: NativeMarketPluginRecord
    let surface: NativeVuePluginWebContainer.Surface
    var id: String { "\(plugin.id)|\(surface == .config ? "config" : "data")" }
  }

  var body: some View {
    contentWithAlerts
  }

  private var scrollContent: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && installedPlugins.isEmpty {
            NativeCardListSkeletonView(count: 5, style: .pluginCard)
              .transition(.opacity)
          } else if loadFailed && installedPlugins.isEmpty {
            failureCard
          } else if filteredItems.isEmpty {
            emptyCard
          } else {
            let columnCount = NativeDeviceLayout.cardGridCount(
              for: containerWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            let gridColumns = Array(
              repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
            LazyVGrid(columns: gridColumns, spacing: 12) {
              ForEach(filteredItems) { plugin in
                installedPluginCard(plugin)
              }
            }
          }
        }
        .frame(maxWidth: containerWidth >= 740 ? 1180 : 820)
        .padding(.horizontal, NativeDeviceLayout.horizontalMargin(for: containerWidth))
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .refreshable { await loadInstalled(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-plugin-market-scroll")
    }
  }

  private var contentWithNavigation: some View {
    scrollContent
      .navigationTitle("插件")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .searchable(text: $searchText, prompt: "搜索已安装插件、作者或标签")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showsMarketPage = true
          } label: {
            Image(systemName: "storefront")
          }
          .tint(.primary)
          .accessibilityLabel("插件市场")
          .accessibilityIdentifier("native-plugin-open-store")
        }
        ToolbarItem(placement: .topBarTrailing) {
          filterToolbarMenu
            .tint(.primary)
        }
      }
      .navigationDestination(isPresented: $showsMarketPage) {
        NativePluginStorePage(session: session) {
          reloadToken += 1
        }
      }
      .navigationDestination(
        isPresented: Binding(
          get: { formSelection != nil }, set: { if !$0 { formSelection = nil } })
      ) {
        if let formSelection {
          NativePluginFormView(plugin: formSelection.plugin, form: formSelection.form)
            .id(formSelection.plugin.id)
        }
      }
      .navigationDestination(
        isPresented: Binding(
          get: { dataPageSelection != nil }, set: { if !$0 { dataPageSelection = nil } })
      ) {
        if let plugin = dataPageSelection {
          NativePluginDataPageView(
            session: session, pluginID: plugin.id, pluginName: plugin.displayName
          )
          .id(plugin.id)
        }
      }
      .sheet(item: $vueSheetTarget) { target in
        NativeVuePluginSheet(
          session: session,
          pluginID: target.plugin.id,
          pluginName: target.plugin.displayName,
          surface: target.surface,
          pluginHasPage: target.plugin.hasPage
        )
      }
      .task(id: reloadToken) {
        await loadInstalled(forceRefresh: reloadToken > 0)
      }
  }

  private var contentWithSheets: some View {
    contentWithNavigation
      .sheet(item: $detailTarget) { plugin in
        NativePluginMarketDetailSheet(
          session: session,
          plugin: plugin,
          downloads: resolvedDownloads(for: plugin),
          ratingSummary: resolvedRating(for: plugin),
          onOpenVersionHistory: {
            detailTarget = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
              versionHistoryTarget = plugin
            }
          }
        ) { message in
          feedback = NativePluginMarketFeedback(isError: false, message: message)
          reloadToken += 1
        }
      }
      .sheet(item: $versionHistoryTarget) { plugin in
        NativePluginVersionHistorySheet(
          session: session,
          plugin: plugin,
          actionMode: .update
        ) { message in
          feedback = NativePluginMarketFeedback(isError: false, message: message)
          reloadToken += 1
        }
      }
      .sheet(item: $cloneTarget) { plugin in
        NativePluginCloneSheet(session: session, plugin: plugin) { message in
          feedback = NativePluginMarketFeedback(isError: false, message: message)
          reloadToken += 1
        }
      }
      .sheet(item: $logTarget) { plugin in
        NativePluginLogSheet(session: session, plugin: plugin)
      }
      .sheet(item: $capabilitiesTarget) { plugin in
        NativePluginCapabilitiesSheet(session: session, plugin: plugin)
      }
      .sheet(item: $dataSummaryTarget) { plugin in
        NativePluginDataSummarySheet(session: session, plugin: plugin)
      }
      .sheet(item: $instanceManageTarget) { plugin in
        NativePluginInstanceManageSheet(
          session: session,
          plugin: plugin,
          allInstalled: installedPlugins
        ) { message in
          feedback = NativePluginMarketFeedback(isError: false, message: message)
          reloadToken += 1
        }
      }
  }

  private var contentWithAlerts: some View {
    contentWithSheets
      .alert(
        "更新插件",
        isPresented: Binding(
          get: { pendingInstall != nil }, set: { if !$0 { pendingInstall = nil } }),
        presenting: pendingInstall
      ) { plugin in
        Button("确认更新") {
          Task { await updatePlugin(plugin) }
        }
        Button("取消", role: .cancel) {}
      } message: { plugin in
        Text("确认更新「\(plugin.displayName)」至最新版本吗？")
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

  /// 右上角过滤与排序菜单（收纳状态过滤、排序与刷新）。
  private var filterToolbarMenu: some View {
    Menu {
      Section("状态过滤") {
        ForEach(InstalledFilter.allCases) { option in
          Button {
            installedFilter = option
          } label: {
            if installedFilter == option {
              Label(option.rawValue, systemImage: "checkmark")
            } else {
              Text(option.rawValue)
            }
          }
        }
      }
      Section("排序方式") {
        ForEach(SortMode.allCases) { option in
          Button {
            sortMode = option
          } label: {
            if sortMode == option {
              Label(option.rawValue, systemImage: "checkmark")
            } else {
              Text(option.rawValue)
            }
          }
        }
      }
      Divider()
      Button {
        reloadToken += 1
      } label: {
        Label("刷新列表", systemImage: "arrow.triangle.2.circlepath")
      }
    } label: {
      Image(
        systemName: installedFilter == .all
          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
    }
    .accessibilityLabel("筛选与排序")
    .accessibilityIdentifier("native-plugin-market-filter-menu")
  }

  private var filteredItems: [NativeMarketPluginRecord] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let matched = installedPlugins.filter { plugin in
      switch installedFilter {
      case .all: break
      case .running: guard plugin.isRunning else { return false }
      case .stopped: guard !plugin.isRunning else { return false }
      case .updatable: guard plugin.hasUpdate else { return false }
      }
      guard !trimmed.isEmpty else { return true }
      return plugin.displayName.lowercased().contains(trimmed)
        || plugin.id.lowercased().contains(trimmed)
        || plugin.summary.lowercased().contains(trimmed)
        || plugin.author.lowercased().contains(trimmed)
        || plugin.labels.contains(where: { $0.lowercased().contains(trimmed) })
    }
    switch sortMode {
    case .defaultOrder:
      return matched
    case .nameAsc:
      return matched.sorted {
        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
      }
    case .installsDesc:
      return matched.sorted { resolvedDownloads(for: $0) > resolvedDownloads(for: $1) }
    case .ratingDesc:
      return matched.sorted {
        (resolvedRating(for: $0)?.averageRating ?? $0.averageRating)
          > (resolvedRating(for: $1)?.averageRating ?? $1.averageRating)
      }
    }
  }

  private func resolvedDownloads(for plugin: NativeMarketPluginRecord) -> Int {
    let key = plugin.sourcePluginID ?? plugin.id
    return max(plugin.installCount, installStats[key] ?? installStats[key.lowercased()] ?? 0)
  }

  private func resolvedRating(for plugin: NativeMarketPluginRecord) -> NativePluginRatingSummary? {
    let key = plugin.sourcePluginID ?? plugin.id
    return ratings[key] ?? ratings[key.lowercased()]
  }

  /// 已安装插件卡片 + 完整长按运维菜单（含分身、关于与源绑定、日志、重载、运行能力、数据摘要、实例管理）。
  private func installedPluginCard(_ plugin: NativeMarketPluginRecord) -> some View {
    let isMutating = mutatingID == plugin.id
    let downloads = resolvedDownloads(for: plugin)
    let fetchedRating = resolvedRating(for: plugin)
    let effectiveRating = fetchedRating?.averageRating ?? plugin.averageRating
    return NativePluginCardSurface(
      session: session,
      plugin: plugin,
      isInstalledContext: true,
      isMutating: isMutating,
      downloads: downloads,
      effectiveRating: effectiveRating
    )
    .onTapGesture {
      guard mutatingID == nil else { return }
      if plugin.isVuePlugin {
        vueSheetTarget = VueSheetTarget(
          plugin: plugin, surface: plugin.hasPage ? .dataPage : .config)
      } else if plugin.hasPage {
        dataPageSelection = plugin
      } else {
        openForm(for: plugin)
      }
    }
    .contextMenu {
      if plugin.hasPage {
        Button {
          DispatchQueue.main.async {
            if plugin.isVuePlugin {
              vueSheetTarget = VueSheetTarget(plugin: plugin, surface: .dataPage)
            } else {
              dataPageSelection = plugin
            }
          }
        } label: {
          Label("查看数据", systemImage: "doc.text.magnifyingglass")
        }
      }
      Button {
        DispatchQueue.main.async {
          if plugin.isVuePlugin {
            vueSheetTarget = VueSheetTarget(plugin: plugin, surface: .config)
          } else {
            openForm(for: plugin)
          }
        }
      } label: {
        Label("设置", systemImage: "slider.horizontal.3")
      }
      Button {
        detailTarget = plugin
      } label: {
        Label("关于与源管理", systemImage: "info.circle")
      }
      if !plugin.isInstance {
        Button {
          cloneTarget = plugin
        } label: {
          Label("创建分身", systemImage: "plus.square.on.square")
        }
      }
      if plugin.hasUpdate {
        Button {
          pendingInstall = plugin
        } label: {
          Label("更新插件", systemImage: "arrow.triangle.2.circlepath")
        }
      }
      Button {
        versionHistoryTarget = plugin
      } label: {
        Label("版本历史", systemImage: "clock.arrow.circlepath")
      }
      Button {
        logTarget = plugin
      } label: {
        Label("查看日志", systemImage: "doc.plaintext")
      }
      if let homeURL = plugin.projectHomeURL {
        Button {
          openURL(homeURL)
        } label: {
          Label("项目主页", systemImage: "safari")
        }
      }

      Menu {
        Button {
          Task { await reloadPlugin(plugin) }
        } label: {
          Label("重新加载插件", systemImage: "arrow.clockwise")
        }
        Button {
          capabilitiesTarget = plugin
        } label: {
          Label("运行能力", systemImage: "cpu")
        }
        Button {
          dataSummaryTarget = plugin
        } label: {
          Label("数据摘要", systemImage: "cylinder.split.1x2")
        }
        Button {
          instanceManageTarget = plugin
        } label: {
          Label("实例管理", systemImage: "square.stack.3d.up")
        }
      } label: {
        Label("高级运维", systemImage: "wrench.and.screwdriver")
      }

      Divider()
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
    .accessibilityIdentifier("native-installed-card-\(plugin.id)")
  }

  private func feedbackBanner(_ feedback: NativePluginMarketFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary)
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.secondary).frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-plugin-market-feedback")
  }

  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 12) {
        Image(systemName: "puzzlepiece.extension")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        Text(installedPlugins.isEmpty ? "尚未安装任何插件" : "暂无匹配的已安装插件")
          .font(.headline)
        Button {
          showsMarketPage = true
        } label: {
          Label("前往插件市场探索", systemImage: "storefront")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background { Capsule().fill(NativeTheme.brand) }
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, minHeight: 170)
    }
  }

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

  private func loadInstalled(forceRefresh: Bool = false) async {
    let cacheKey = "plugins|installed"
    if !forceRefresh,
      let cached: [NativeMarketPluginRecord] = NativePageDataCache.shared.get(
        cacheKey, session: session)
    {
      installedPlugins = cached
      isLoading = false
      loadFailed = false
      return
    }
    if installedPlugins.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"],
        query: [URLQueryItem(name: "state", value: "installed")],
        maximumResponseBytes: 8 * 1024 * 1024,
        trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeMarketPluginRecord].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      try Task.checkCancellation()
      let valid = loaded.filter { !$0.id.isEmpty }
      installedPlugins = valid
      NativePageDataCache.shared.set(valid, for: cacheKey, session: session)
      Task { await loadPluginStatsAndRatings(pluginIDs: valid.map { $0.sourcePluginID ?? $0.id }) }
    } catch is CancellationError {
      return
    } catch {
      if installedPlugins.isEmpty { loadFailed = true }
    }
  }

  private func loadPluginStatsAndRatings(pluginIDs: [String]) async {
    async let statsTask: [String: Int]? = {
      guard let ep = try? APIEndpoint(path: ["plugin", "statistic"]) else { return nil }
      return try? await session.request(
        ep, as: [String: Int].self, requiring: PermissionRequirement(category: .admin)
      ).value
    }()
    let idsParam = Array(Set(pluginIDs)).prefix(80).joined(separator: ",")
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

  private func openForm(for record: NativeMarketPluginRecord) {
    do {
      let normalizedSource =
        (record.sourcePluginID?.isEmpty == true) ? nil : record.sourcePluginID
      let target = try PluginFormTarget(physicalID: record.id, sourceID: normalizedSource)
      let installed = NativeInstalledPlugin(
        target: target,
        name: record.displayName,
        summary: record.summary,
        version: record.version,
        icon: record.pluginIcon,
        author: record.pluginAuthor,
        authorURL: record.authorURL,
        state: record.state,
        hasPage: record.hasPage
      )
      let form = try NativePluginForm(
        session: session, target: installed.target, validator: NativeFormValidator())
      formSelection = FormSelection(plugin: installed, form: form)
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "无法打开该插件的配置表单。")
    }
  }

  private func updatePlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    var query = [URLQueryItem(name: "force", value: "true")]
    if let repo = plugin.repoURL, !repo.isEmpty {
      query.append(URLQueryItem(name: "repo_url", value: repo))
    }
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin", "install", plugin.id], query: query, responseContract: .payload,
        timeout: 90)
      let resp = try await session.request(
        endpoint, as: NativePluginSimpleResponse.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      if resp.success == false {
        feedback = NativePluginMarketFeedback(
          isError: true, message: resp.message ?? "更新插件失败。")
        return
      }
      feedback = NativePluginMarketFeedback(
        isError: false,
        message: resp.message?.isEmpty == false ? resp.message! : "「\(plugin.displayName)」更新已完成。")
      reloadToken += 1
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "更新插件失败，请检查仓库连通性后重试。")
    }
  }

  private func reloadPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin", "reload", plugin.id], method: .post, responseContract: .payload,
        timeout: 45)
      let resp = try await session.request(
        endpoint, as: NativePluginSimpleResponse.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      if resp.success == false {
        feedback = NativePluginMarketFeedback(
          isError: true, message: resp.message ?? "重载插件失败，请查看插件日志。")
      } else {
        feedback = NativePluginMarketFeedback(
          isError: false, message: "已重新加载「\(plugin.displayName)」。")
        reloadToken += 1
      }
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "重载插件失败，请稍后重试。")
    }
  }

  private func resetPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(path: ["plugin", "reset", plugin.id])
      try await session.perform(endpoint, requiring: PermissionRequirement(category: .admin))
      feedback = NativePluginMarketFeedback(isError: false, message: "已重置「\(plugin.displayName)」。")
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "重置插件失败，请稍后重试。")
    }
  }

  private func uninstallPlugin(_ plugin: NativeMarketPluginRecord) async {
    mutatingID = plugin.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin", plugin.id], method: .delete, responseContract: .payload)
      let resp = try await session.request(
        endpoint, as: NativePluginSimpleResponse.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      if resp.success == false {
        feedback = NativePluginMarketFeedback(
          isError: true, message: resp.message ?? "卸载失败，请先卸载关联分身。")
        return
      }
      installedPlugins.removeAll { $0.id == plugin.id }
      NativePageDataCache.shared.set(installedPlugins, for: "plugins|installed", session: session)
      feedback = NativePluginMarketFeedback(isError: false, message: "已卸载「\(plugin.displayName)」。")
    } catch {
      feedback = NativePluginMarketFeedback(isError: true, message: "卸载插件失败，请稍后重试。")
    }
  }
}

/// 独立插件市场二级页（由插件页右上角「插件市场」图标进入）：
/// 点按任意插件卡片进入详情弹窗（含源绑定、版本列表安装、评分、文档），右上角提供过滤与同步菜单。
@MainActor
private struct NativePluginStorePage: View {
  enum MarketFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case updatable = "可更新"
    case notInstalled = "未安装"
    var id: String { rawValue }
  }

  let session: NativeSession
  let onMutated: () -> Void

  @Environment(\.openURL) private var openURL
  @State private var marketFilter: MarketFilter = .all
  @State private var sortMode: NativePluginMarketPage.SortMode = .defaultOrder
  @State private var marketPlugins: [NativeMarketPluginRecord] = []
  @State private var installStats: [String: Int] = [:]
  @State private var ratings: [String: NativePluginRatingSummary] = [:]
  @State private var marketPage = 1
  @State private var marketHasMore = true
  @State private var isLoadingMore = false
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var detailTarget: NativeMarketPluginRecord?
  @State private var versionHistoryTarget: NativeMarketPluginRecord?
  @State private var feedback: NativePluginMarketFeedback?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 10) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.message).font(.subheadline).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button {
                  self.feedback = nil
                } label: {
                  Image(systemName: "xmark").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }
            }
          }
          if isLoading && marketPlugins.isEmpty {
            NativeCardListSkeletonView(count: 5, style: .pluginCard)
              .transition(.opacity)
          } else if loadFailed && marketPlugins.isEmpty {
            CinematicPanel {
              VStack(alignment: .leading, spacing: 10) {
                Label("暂时无法载入插件市场", systemImage: "exclamationmark.triangle").font(.headline)
                Button("重试") { reloadToken += 1 }.frame(minHeight: 44)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          } else if filteredItems.isEmpty {
            CinematicPanel {
              VStack(spacing: 10) {
                Image(systemName: "storefront")
                  .font(.largeTitle)
                  .foregroundStyle(.secondary)
                Text("暂无匹配的市场插件").font(.headline)
              }
              .frame(maxWidth: .infinity, minHeight: 160)
            }
          } else {
            LazyVStack(spacing: 12) {
              ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, plugin in
                let downloads = resolvedDownloads(for: plugin)
                let rating = resolvedRating(for: plugin)
                NativePluginCardSurface(
                  session: session,
                  plugin: plugin,
                  isInstalledContext: false,
                  isMutating: false,
                  downloads: downloads,
                  effectiveRating: rating?.averageRating ?? plugin.averageRating
                )
                .onTapGesture {
                  detailTarget = plugin
                }
                .contextMenu {
                  Button {
                    detailTarget = plugin
                  } label: {
                    Label(
                      plugin.installed ? (plugin.hasUpdate ? "更新插件" : "插件详情") : "安装插件",
                      systemImage: plugin.installed ? "info.circle" : "arrow.down.to.line")
                  }
                  Button {
                    versionHistoryTarget = plugin
                  } label: {
                    Label("版本历史", systemImage: "clock.arrow.circlepath")
                  }
                  if let homeURL = plugin.projectHomeURL {
                    Button {
                      openURL(homeURL)
                    } label: {
                      Label("项目主页", systemImage: "safari")
                    }
                  }
                }
                .onAppear {
                  if marketHasMore && !isLoadingMore && index >= max(0, filteredItems.count - 8) {
                    Task { await loadMore() }
                  }
                }
                .accessibilityIdentifier("native-market-card-\(plugin.id)")
              }
              if isLoadingMore {
                ProgressView().tint(.primary).padding(.vertical, 10)
              }
            }
          }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load(forceMarket: true, forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("插件市场")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .searchable(text: $searchText, prompt: "搜索插件名称、作者或标签")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Section("市场筛选") {
            ForEach(MarketFilter.allCases) { option in
              Button {
                marketFilter = option
              } label: {
                if marketFilter == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
          Section("排序方式") {
            ForEach(NativePluginMarketPage.SortMode.allCases) { option in
              Button {
                sortMode = option
              } label: {
                if sortMode == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
          Divider()
          Button {
            Task { await load(forceMarket: true, forceRefresh: true) }
          } label: {
            Label("同步最新市场索引", systemImage: "arrow.triangle.2.circlepath")
          }
        } label: {
          Image(
            systemName: marketFilter == .all
              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .tint(.primary)
        .accessibilityLabel("市场筛选与排序")
      }
    }
    .sheet(item: $detailTarget) { plugin in
      NativePluginMarketDetailSheet(
        session: session,
        plugin: plugin,
        downloads: resolvedDownloads(for: plugin),
        ratingSummary: resolvedRating(for: plugin),
        onOpenVersionHistory: {
          detailTarget = nil
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            versionHistoryTarget = plugin
          }
        }
      ) { message in
        feedback = NativePluginMarketFeedback(isError: false, message: message)
        if let idx = marketPlugins.firstIndex(where: { $0.id == plugin.id }) {
          marketPlugins[idx].installed = true
          marketPlugins[idx].hasUpdate = false
        }
        onMutated()
      }
    }
    .sheet(item: $versionHistoryTarget) { plugin in
      NativePluginVersionHistorySheet(
        session: session,
        plugin: plugin,
        actionMode: plugin.installed ? .update : .install
      ) { message in
        feedback = NativePluginMarketFeedback(isError: false, message: message)
        if let idx = marketPlugins.firstIndex(where: { $0.id == plugin.id }) {
          marketPlugins[idx].installed = true
          marketPlugins[idx].hasUpdate = false
        }
        onMutated()
      }
    }
    .task(id: reloadToken) {
      await load(forceMarket: false, forceRefresh: reloadToken > 0)
    }
  }

  private var filteredItems: [NativeMarketPluginRecord] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let matched = marketPlugins.filter { plugin in
      switch marketFilter {
      case .all: break
      case .updatable: guard plugin.hasUpdate else { return false }
      case .notInstalled: guard !plugin.installed else { return false }
      }
      guard !trimmed.isEmpty else { return true }
      return plugin.displayName.lowercased().contains(trimmed)
        || plugin.id.lowercased().contains(trimmed)
        || plugin.summary.lowercased().contains(trimmed)
        || plugin.author.lowercased().contains(trimmed)
        || plugin.labels.contains(where: { $0.lowercased().contains(trimmed) })
    }
    switch sortMode {
    case .defaultOrder: return matched
    case .nameAsc:
      return matched.sorted {
        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
      }
    case .installsDesc:
      return matched.sorted { resolvedDownloads(for: $0) > resolvedDownloads(for: $1) }
    case .ratingDesc:
      return matched.sorted {
        (resolvedRating(for: $0)?.averageRating ?? $0.averageRating)
          > (resolvedRating(for: $1)?.averageRating ?? $1.averageRating)
      }
    }
  }

  private func resolvedDownloads(for plugin: NativeMarketPluginRecord) -> Int {
    max(plugin.installCount, installStats[plugin.id] ?? installStats[plugin.id.lowercased()] ?? 0)
  }

  private func resolvedRating(for plugin: NativeMarketPluginRecord) -> NativePluginRatingSummary? {
    ratings[plugin.id] ?? ratings[plugin.id.lowercased()]
  }

  private func load(forceMarket: Bool, forceRefresh: Bool) async {
    let cacheKey = "plugins|market"
    if !forceRefresh && !forceMarket,
      let cached: [NativeMarketPluginRecord] = NativePageDataCache.shared.get(
        cacheKey, session: session)
    {
      marketPlugins = cached
      marketHasMore = cached.count >= 60
      isLoading = false
      loadFailed = false
      return
    }
    if marketPlugins.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    marketPage = 1
    marketHasMore = true
    var query = [
      URLQueryItem(name: "state", value: "market"),
      URLQueryItem(name: "page", value: "1"),
      URLQueryItem(name: "count", value: "60"),
    ]
    if forceMarket { query.append(URLQueryItem(name: "force", value: "true")) }
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"], query: query, maximumResponseBytes: 8 * 1024 * 1024, trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeMarketPluginRecord].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      let valid = loaded.filter { !$0.id.isEmpty }
      marketPlugins = valid
      marketHasMore = valid.count >= 60
      NativePageDataCache.shared.set(valid, for: cacheKey, session: session)
      Task { await loadStatsAndRatings(ids: valid.map(\.id)) }
    } catch {
      if marketPlugins.isEmpty { loadFailed = true }
    }
  }

  private func loadMore() async {
    guard marketHasMore, !isLoadingMore, !isLoading else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    let nextPage = marketPage + 1
    do {
      let endpoint = try APIEndpoint(
        path: ["plugin"],
        query: [
          URLQueryItem(name: "state", value: "market"),
          URLQueryItem(name: "page", value: String(nextPage)),
          URLQueryItem(name: "count", value: "60"),
        ],
        maximumResponseBytes: 8 * 1024 * 1024,
        trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeMarketPluginRecord].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
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

  private func loadStatsAndRatings(ids: [String]) async {
    async let statsTask: [String: Int]? = {
      guard let ep = try? APIEndpoint(path: ["plugin", "statistic"]) else { return nil }
      return try? await session.request(
        ep, as: [String: Int].self, requiring: PermissionRequirement(category: .admin)
      ).value
    }()
    let idsParam = ids.prefix(80).joined(separator: ",")
    async let ratingsTask: [String: NativePluginRatingSummary]? = {
      let query = idsParam.isEmpty ? [] : [URLQueryItem(name: "plugin_ids", value: idsParam)]
      guard let ep = try? APIEndpoint(path: ["plugin", "rating"], query: query) else { return nil }
      return try? await session.request(
        ep, as: [String: NativePluginRatingSummary].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    }()
    let (s, r) = await (statsTask, ratingsTask)
    if let s {
      var merged = installStats
      for (k, v) in s {
        merged[k] = v
        merged[k.lowercased()] = v
      }
      installStats = merged
    }
    if let r {
      var merged = ratings
      for (k, v) in r {
        merged[k] = v
        merged[k.lowercased()] = v
      }
      ratings = merged
    }
  }
}

/// 共用插件卡片渲染面（兼容浅/深色自适应主题，清晰展示分身标记、状态点、版本、简介、标签与底部作者/下载量/评分铭牌栏）。
@MainActor
private struct NativePluginCardSurface: View {
  let session: NativeSession
  let plugin: NativeMarketPluginRecord
  let isInstalledContext: Bool
  let isMutating: Bool
  let downloads: Int
  let effectiveRating: Double

  var body: some View {
    let isInactive = isInstalledContext && !plugin.isRunning
    let accent = Self.pluginAccentColor(from: plugin.pluginColor)

    return CinematicPanel(padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 6) {
            if isInstalledContext {
              Circle()
                .fill(plugin.isRunning ? NativeTheme.success : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            }
            Text(plugin.displayName)
              .font(.headline.weight(.semibold))
              .foregroundStyle(isInactive ? Color.secondary : Color.primary)
              .lineLimit(1)
            if plugin.isInstance {
              Text("分身")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NativeTheme.info)
                .padding(.horizontal, 5.5)
                .padding(.vertical, 1.5)
                .background { Capsule().fill(NativeTheme.info.opacity(0.14)) }
            }
            if !plugin.version.isEmpty {
              Text("v\(plugin.version)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isMutating {
              ProgressView().controlSize(.mini).tint(.primary)
            } else {
              statusBadge
            }
          }

          HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
              if !plugin.summary.isEmpty {
                Text(plugin.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(3)
                  .fixedSize(horizontal: false, vertical: true)
              }
              if !isInstalledContext && !plugin.labels.isEmpty {
                HStack(spacing: 5) {
                  ForEach(plugin.labels.prefix(3), id: \.self) { label in
                    Text(label)
                      .font(.caption2.weight(.medium))
                      .foregroundStyle(NativeTheme.brand)
                      .padding(.horizontal, 6.5)
                      .padding(.vertical, 2)
                      .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                          .fill(NativeTheme.brand.opacity(0.12))
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
              inactive: isInactive)
          }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .background(
          LinearGradient(
            colors: [accent.opacity(isInactive ? 0.04 : 0.13), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
        )

        Divider().overlay(NativeTheme.divider)

        HStack(spacing: 8) {
          HStack(spacing: 6) {
            NativePluginAuthorAvatarView(
              authorURL: plugin.authorURL,
              authorName: plugin.author,
              size: 20)
            Text(plugin.author.isEmpty ? "MoviePilot" : plugin.author)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
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
            .foregroundStyle(.secondary)
          }
          if effectiveRating > 0 {
            HStack(spacing: 2.5) {
              Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundStyle(NativeTheme.warning)
              Text(String(format: "%.1f", effectiveRating))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(NativeTheme.warning)
            }
          }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  @ViewBuilder
  private var statusBadge: some View {
    if plugin.hasUpdate {
      badgePill("有更新", tint: NativeTheme.warning)
    } else if !isInstalledContext && plugin.installed {
      badgePill("已安装", tint: NativeTheme.success)
    } else if isInstalledContext {
      badgePill(
        plugin.isRunning ? "运行中" : "未启用",
        tint: plugin.isRunning ? NativeTheme.success : NativeTheme.badgeMutedText)
    }
  }

  private func badgePill(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background {
        Capsule()
          .fill(tint.opacity(0.14))
          .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
      }
  }

  private static func pluginAccentColor(from hex: String?) -> Color {
    guard let hex else { return NativeTheme.brand }
    let cleaned = hex.trimmingCharacters(
      in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
    guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
      return NativeTheme.brand
    }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
  }

  static func formatInstallCount(_ count: Int) -> String {
    if count >= 10_000 { return String(format: "%.1fw", Double(count) / 10_000.0) }
    if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000.0) }
    return "\(count)"
  }
}

/// 插件详情、来源绑定/切换与评分安装弹窗（对标 Web `PluginMarketDetailDialog.vue`，与版本历史弹窗独立分离）。
@MainActor
private struct NativePluginMarketDetailSheet: View {
  let session: NativeSession
  let plugin: NativeMarketPluginRecord
  let downloads: Int
  let ratingSummary: NativePluginRatingSummary?
  var onOpenVersionHistory: (() -> Void)? = nil
  let onCompleted: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  @State private var sourceOptions: NativePluginSourceOptions?
  @State private var selectedSourceRepo: String = ""
  @State private var docURL: URL?
  @State private var liveRating: NativePluginRatingSummary?
  @State private var userStars = 0

  @State private var isLoading = true
  @State private var isInstalling = false
  @State private var isRatingSubmitting = false
  @State private var bannerMessage: String?
  @State private var bannerIsError = false

  private var sourcePluginID: String {
    plugin.sourcePluginID?.isEmpty == false ? plugin.sourcePluginID! : plugin.id
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            heroSection
            if let bannerMessage {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(
                    systemName: bannerIsError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                  )
                  .foregroundStyle(bannerIsError ? NativeTheme.warning : NativeTheme.success)
                  Text(bannerMessage).font(.caption).foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            sourceBindingSection
            ratingSection
            linksSection
          }
          .frame(maxWidth: 760)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(plugin.installed ? "插件详情" : "安装插件")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
        }
        if let onOpenVersionHistory {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              onOpenVersionHistory()
            } label: {
              Image(systemName: "clock.arrow.circlepath")
            }
            .tint(.primary)
            .accessibilityLabel("版本历史")
            .accessibilityIdentifier("native-plugin-detail-version-history")
          }
        }
      }
      .task { await bootstrap() }
    }
    .nativeGlassSheet()
  }

  private var heroSection: some View {
    CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 13) {
          NativePluginIconView(
            session: session, iconReference: plugin.pluginIcon, size: 58, cornerRadius: 14,
            inactive: false)
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              Text(plugin.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
              if !plugin.version.isEmpty {
                Text("v\(plugin.version)")
                  .font(.caption.monospacedDigit().weight(.semibold))
                  .foregroundStyle(NativeTheme.brand)
              }
            }
            Text("作者：\(plugin.author.isEmpty ? "MoviePilot" : plugin.author)")
              .font(.caption)
              .foregroundStyle(.secondary)
            HStack(spacing: 10) {
              if downloads > 0 {
                Label(
                  NativePluginCardSurface.formatInstallCount(downloads),
                  systemImage: "arrow.down.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
              let avg =
                liveRating?.averageRating ?? ratingSummary?.averageRating ?? plugin.averageRating
              let cnt = liveRating?.ratingCount ?? ratingSummary?.ratingCount ?? plugin.ratingCount
              if avg > 0 {
                Label(String(format: "%.1f (%d)", avg, cnt), systemImage: "star.fill")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(NativeTheme.warning)
              }
            }
          }
          Spacer(minLength: 0)
        }
        if !plugin.summary.isEmpty {
          Text(plugin.summary)
            .font(.subheadline)
            .foregroundStyle(.primary)
        }
        if !plugin.labels.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(plugin.labels, id: \.self) { label in
                NativeAdaptiveBadge(label, tint: NativeTheme.brand)
              }
            }
          }
        }
        Button {
          Task { await installOrUpdate(releaseVersion: nil) }
        } label: {
          HStack(spacing: 6) {
            if isInstalling {
              ProgressView().controlSize(.small).tint(.white)
            } else {
              Image(
                systemName: plugin.installed
                  ? (plugin.hasUpdate ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                  : "arrow.down.to.line")
            }
            Text(
              isInstalling
                ? "正在处理…"
                : (plugin.installed
                  ? (plugin.hasUpdate ? "更新插件" : "重新安装") : "安装插件"))
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
          .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NativeTheme.brand)
          }
        }
        .buttonStyle(.plain)
        .disabled(isInstalling)
      }
    }
  }

  /// 插件源识别、绑定与显式换源区域（`GET /plugin/source/{id}/options`, `POST /plugin/source/{id}`）。
  private var sourceBindingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("插件源与仓库绑定")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 13) {
        VStack(alignment: .leading, spacing: 10) {
          if isLoading && sourceOptions == nil {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text("正在查询可用插件源…").font(.caption).foregroundStyle(.secondary)
            }
          } else if let opts = sourceOptions {
            if let identity = opts.identity {
              HStack {
                Text("当前绑定源").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Self.cleanSourceKey(identity.trustedSourceKey ?? identity.trustedSourceType))
                  .font(.caption.monospaced().weight(.semibold))
                  .foregroundStyle(NativeTheme.brand)
              }
            }
            if !opts.selectionReason.isEmpty {
              Text(opts.selectionReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            let candidates = opts.sortedCandidates
            if !candidates.isEmpty {
              Divider().overlay(NativeTheme.divider)
              ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                let repo = candidate.repoURL ?? ""
                let isSelected = !repo.isEmpty && selectedSourceRepo == repo
                let isBound =
                  opts.identity?.trustedSourceKey != nil
                  && candidate.sourceKey == opts.identity?.trustedSourceKey
                Button {
                  selectedSourceRepo = repo
                } label: {
                  HStack(spacing: 10) {
                    Image(
                      systemName: isSelected ? "largecircle.fill.circle" : "circle"
                    )
                    .foregroundStyle(isSelected ? NativeTheme.brand : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                      HStack(spacing: 6) {
                        Text(candidate.displayLabel)
                          .font(.caption.weight(.semibold))
                          .foregroundStyle(.primary)
                          .lineLimit(1)
                        NativeAdaptiveBadge(
                          candidate.sourceTypeLabel,
                          tint: candidate.sourceType == "official"
                            ? NativeTheme.success : NativeTheme.info)
                        if isBound {
                          NativeAdaptiveBadge("已绑定", tint: NativeTheme.brand)
                        }
                      }
                      HStack(spacing: 6) {
                        Text(candidate.packageGeneration.uppercased())
                          .font(.caption2.monospaced())
                          .foregroundStyle(.secondary)
                        if let ver = candidate.pluginVersion, !ver.isEmpty {
                          Text("v\(ver)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        }
                      }
                    }
                    Spacer(minLength: 0)
                  }
                  .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
              }

              if plugin.installed, !selectedSourceRepo.isEmpty,
                !selectedSourceRepo.hasPrefix("local://")
              {
                let needsChange = opts.identity != nil
                Button {
                  Task { await applySourceSelection(isSourceChange: needsChange) }
                } label: {
                  Text(needsChange ? "切换到所选在线源" : "绑定并从所选在线源安装")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NativeTheme.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(NativeTheme.brand.opacity(0.14))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isInstalling)
              }
            }
          } else {
            Text("当前未检测到多源配置，将使用默认市场源安装。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  /// 评分查看与提交区（已安装插件可交互打分）。
  private var ratingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("社区评分")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      CinematicPanel(padding: 13) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(plugin.installed ? "为该插件打分" : "安装后可参与社区评分")
              .font(.subheadline.weight(.medium))
            if let cnt = liveRating?.ratingCount ?? ratingSummary?.ratingCount, cnt > 0 {
              Text("共 \(cnt) 次评分")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          Spacer()
          HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
              Button {
                guard plugin.installed, !isRatingSubmitting else { return }
                Task { await submitRating(star) }
              } label: {
                Image(systemName: star <= userStars ? "star.fill" : "star")
                  .font(.body)
                  .foregroundStyle(star <= userStars ? NativeTheme.warning : Color.secondary)
              }
              .buttonStyle(.plain)
              .disabled(!plugin.installed || isRatingSubmitting)
            }
          }
        }
      }
    }
  }

  /// 文档与仓库链接。
  @ViewBuilder
  private var linksSection: some View {
    let homeURL = plugin.projectHomeURL
    if docURL != nil || homeURL != nil {
      VStack(alignment: .leading, spacing: 8) {
        Text("文档与源码")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            if let docURL {
              Button {
                openURL(docURL)
              } label: {
                HStack {
                  Label("使用说明与 README", systemImage: "book")
                  Spacer()
                  Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
              }
              .buttonStyle(.plain)
            }
            if docURL != nil && homeURL != nil {
              Divider().overlay(NativeTheme.divider)
            }
            if let homeURL {
              Button {
                openURL(homeURL)
              } label: {
                HStack {
                  Label("打开项目主页", systemImage: "safari")
                  Spacer()
                  Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  private func bootstrap() async {
    isLoading = true
    defer { isLoading = false }
    selectedSourceRepo = plugin.repoURL ?? ""
    async let sourcesTask: Void = loadSourceOptions()
    async let ratingTask: Void = loadRating()
    async let docTask: Void = loadDocumentation()
    _ = await (sourcesTask, ratingTask, docTask)
  }

  private func loadSourceOptions() async {
    guard
      let ep = try? APIEndpoint(
        path: ["plugin", "source", sourcePluginID, "options"], responseContract: .payload),
      let resp = try? await session.request(
        ep, as: NativePluginEnvelope<NativePluginSourceOptions>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value,
      let data = resp.data
    else { return }
    sourceOptions = data
    if selectedSourceRepo.isEmpty, let first = data.sortedCandidates.first?.repoURL {
      selectedSourceRepo = first
    }
  }

  private func loadRating() async {
    guard let ep = try? APIEndpoint(path: ["plugin", "rating", sourcePluginID]),
      let loaded = try? await session.request(
        ep, as: NativePluginRatingSummary.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    else { return }
    liveRating = loaded
    userStars = loaded.userRating ?? 0
  }

  private func loadDocumentation() async {
    guard let repo = plugin.repoURL, !repo.isEmpty,
      let ep = try? APIEndpoint(
        path: ["plugin", "readme", sourcePluginID],
        query: [URLQueryItem(name: "repo_url", value: repo)]),
      let doc = try? await session.request(
        ep, as: NativePluginDocumentation.self,
        requiring: PermissionRequirement(category: .admin)
      ).value,
      let raw = doc.url ?? doc.readmeURL,
      let url = URL(string: raw),
      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
    else { return }
    docURL = url
  }

  private func installOrUpdate(releaseVersion: String?) async {
    isInstalling = true
    bannerMessage = nil
    defer { isInstalling = false }
    let chosenRepo = selectedSourceRepo.isEmpty ? (plugin.repoURL ?? "") : selectedSourceRepo
    do {
      if !plugin.installed, !chosenRepo.isEmpty, !chosenRepo.hasPrefix("local://"),
        (sourceOptions?.candidates.count ?? 0) > 1
      {
        let payload = NativePluginSourceInstallPayload(
          repoURL: chosenRepo, releaseVersion: releaseVersion, force: true)
        let body = try JSONEncoder().encode(payload)
        let ep = try APIEndpoint(
          path: ["plugin", "source", sourcePluginID, "install"],
          method: .post, body: body, responseContract: .payload, timeout: 90)
        let resp = try await session.request(
          ep, as: NativePluginSimpleResponse.self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        if resp.success == false {
          bannerIsError = true
          bannerMessage = resp.message ?? "安装插件失败。"
          return
        }
      } else {
        var query = [URLQueryItem(name: "force", value: "true")]
        if !chosenRepo.isEmpty { query.append(URLQueryItem(name: "repo_url", value: chosenRepo)) }
        if let releaseVersion, !releaseVersion.isEmpty {
          query.append(URLQueryItem(name: "release_version", value: releaseVersion))
        }
        let ep = try APIEndpoint(
          path: ["plugin", "install", sourcePluginID], query: query,
          responseContract: .payload, timeout: 90)
        let resp = try await session.request(
          ep, as: NativePluginSimpleResponse.self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        if resp.success == false {
          bannerIsError = true
          bannerMessage = resp.message ?? "安装插件失败。"
          return
        }
      }
      let verSuffix = releaseVersion.map { " (\($0))" } ?? ""
      onCompleted("「\(plugin.displayName)」\(verSuffix) 安装/更新已完成。")
      dismiss()
    } catch {
      bannerIsError = true
      bannerMessage = "安装/更新失败：\(error.localizedDescription)"
    }
  }

  private func applySourceSelection(isSourceChange: Bool) async {
    guard !selectedSourceRepo.isEmpty, !selectedSourceRepo.hasPrefix("local://") else { return }
    isInstalling = true
    bannerMessage = nil
    defer { isInstalling = false }
    do {
      if isSourceChange, let revision = sourceOptions?.identity?.revision {
        let payload = NativePluginSourceChangePayload(
          repoURL: selectedSourceRepo, expectedRevision: revision, releaseVersion: nil)
        let body = try JSONEncoder().encode(payload)
        let ep = try APIEndpoint(
          path: ["plugin", "source", sourcePluginID],
          method: .post, body: body, responseContract: .payload, timeout: 90)
        let resp = try await session.request(
          ep, as: NativePluginSimpleResponse.self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        if resp.success == false {
          bannerIsError = true
          bannerMessage = resp.message ?? "切换插件源失败。"
          return
        }
        onCompleted("已切换「\(plugin.displayName)」的插件源。")
        dismiss()
      } else {
        let payload = NativePluginSourceInstallPayload(
          repoURL: selectedSourceRepo, releaseVersion: nil, force: true)
        let body = try JSONEncoder().encode(payload)
        let ep = try APIEndpoint(
          path: ["plugin", "source", sourcePluginID, "install"],
          method: .post, body: body, responseContract: .payload, timeout: 90)
        let resp = try await session.request(
          ep, as: NativePluginSimpleResponse.self,
          requiring: PermissionRequirement(category: .admin)
        ).value
        if resp.success == false {
          bannerIsError = true
          bannerMessage = resp.message ?? "绑定插件源失败。"
          return
        }
        onCompleted("已为「\(plugin.displayName)」绑定在线插件源。")
        dismiss()
      }
    } catch {
      bannerIsError = true
      bannerMessage = "来源操作失败：\(error.localizedDescription)"
    }
  }

  private func submitRating(_ stars: Int) async {
    isRatingSubmitting = true
    defer { isRatingSubmitting = false }
    do {
      let body = try JSONEncoder().encode(["rating": stars])
      let ep = try APIEndpoint(
        path: ["plugin", "rating", sourcePluginID], method: .post, body: body,
        responseContract: .payload)
      let resp = try await session.request(
        ep, as: NativePluginEnvelope<NativePluginRatingSummary>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      if resp.success == false {
        bannerIsError = true
        bannerMessage = resp.message ?? "评分提交失败。"
        return
      }
      userStars = stars
      if let updated = resp.data { liveRating = updated }
      bannerIsError = false
      bannerMessage = "已提交 \(stars) 星评分。"
    } catch {
      bannerIsError = true
      bannerMessage = "评分提交失败：\(error.localizedDescription)"
    }
  }

  private static func cleanSourceKey(_ raw: String) -> String {
    raw.hasPrefix("github:") ? String(raw.dropFirst("github:".count)) : raw
  }
}

/// 独立版本历史与指定 Release 安装弹窗（对标 Web `PluginVersionHistoryDialog.vue`，与安装详情弹窗分离）。
@MainActor
private struct NativePluginVersionHistorySheet: View {
  enum ActionMode {
    case install
    case update
  }

  private struct MergedVersionRow: Identifiable {
    let versionKey: String
    let installVersion: String?
    let notes: String
    let isCurrent: Bool
    let isLatest: Bool

    var id: String { versionKey }
  }

  let session: NativeSession
  let plugin: NativeMarketPluginRecord
  let actionMode: ActionMode
  let onCompleted: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var releases: NativePluginReleaseData?
  @State private var declaredHistory: [String: String] = [:]
  @State private var isLoading = true
  @State private var isInstalling = false
  @State private var pendingVersion: String?
  @State private var bannerMessage: String?
  @State private var bannerIsError = false

  private var sourcePluginID: String {
    plugin.sourcePluginID?.isEmpty == false ? plugin.sourcePluginID! : plugin.id
  }

  private var mergedRows: [MergedVersionRow] {
    var notesByKey: [String: String] = [:]
    var releaseByKey: [String: NativePluginReleaseItem] = [:]
    for item in releases?.items ?? [] {
      let rawVer = (item.version ?? item.tagName ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard !rawVer.isEmpty else { continue }
      let key = Self.normalizeVersionKey(rawVer)
      releaseByKey[key] = item
      let body = (item.description ?? item.body ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
      notesByKey[key] = declaredHistory[key] ?? declaredHistory[rawVer] ?? body
    }
    for (ver, desc) in declaredHistory {
      let key = Self.normalizeVersionKey(ver)
      if notesByKey[key] == nil || notesByKey[key]?.isEmpty == true {
        notesByKey[key] = desc
      }
    }
    let sortedKeys = notesByKey.keys.sorted { Self.compareVersions($0, $1) > 0 }
    let currentKey = Self.normalizeVersionKey(releases?.currentVersion ?? plugin.version)
    let latestKey =
      (releases?.latestVersion).map(Self.normalizeVersionKey) ?? sortedKeys.first ?? ""
    return sortedKeys.map { key in
      let release = releaseByKey[key]
      let installVer = release?.version ?? release?.tagName
      return MergedVersionRow(
        versionKey: key,
        installVersion: installVer,
        notes: notesByKey[key] ?? "",
        isCurrent: plugin.installed && !currentKey.isEmpty && key == currentKey,
        isLatest: !latestKey.isEmpty && key == latestKey
      )
    }
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            CinematicPanel(padding: 14) {
              HStack(spacing: 12) {
                NativePluginIconView(
                  session: session, iconReference: plugin.pluginIcon, size: 46, cornerRadius: 12,
                  inactive: false)
                VStack(alignment: .leading, spacing: 3) {
                  Text(plugin.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                  HStack(spacing: 8) {
                    if !plugin.version.isEmpty {
                      Text(plugin.installed ? "当前 v\(plugin.version)" : "最新 v\(plugin.version)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(appearance.accentColor)
                    }
                    if !plugin.author.isEmpty {
                      Text(plugin.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                }
                Spacer(minLength: 0)
              }
            }

            if let bannerMessage {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(
                    systemName: bannerIsError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                  )
                  .foregroundStyle(bannerIsError ? NativeTheme.warning : NativeTheme.success)
                  Text(bannerMessage).font(.caption).foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }

            if isLoading && mergedRows.isEmpty {
              NativeCardListSkeletonView(count: 2, style: .formPanel)
                .transition(.opacity)
            } else if mergedRows.isEmpty {
              CinematicPanel(padding: 16) {
                Text("暂无版本更新历史记录")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, minHeight: 80)
              }
            } else {
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  ForEach(Array(mergedRows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 { CinematicFormDivider() }
                    VStack(alignment: .leading, spacing: 6) {
                      HStack(spacing: 8) {
                        Text(row.versionKey)
                          .font(.subheadline.monospaced().weight(.semibold))
                          .foregroundStyle(.primary)
                        if row.isCurrent {
                          NativeAdaptiveBadge("当前版本", tint: NativeTheme.success)
                        } else if row.isLatest {
                          NativeAdaptiveBadge("最新", tint: appearance.accentColor)
                        }
                        Spacer(minLength: 4)
                        if let installVer = row.installVersion, !installVer.isEmpty, !row.isCurrent
                        {
                          Button {
                            pendingVersion = installVer
                          } label: {
                            Text(actionMode == .update ? "安装此版" : "安装")
                              .font(.caption.weight(.semibold))
                              .foregroundStyle(appearance.accentColor)
                              .padding(.horizontal, 10)
                              .padding(.vertical, 5)
                              .background(appearance.accentColor.opacity(0.14), in: Capsule())
                          }
                          .buttonStyle(.plain)
                          .disabled(isInstalling)
                        }
                      }
                      if !row.notes.isEmpty {
                        Text(row.notes)
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .fixedSize(horizontal: false, vertical: true)
                      }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                  }
                }
              }
            }
          }
          .frame(maxWidth: 760)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("版本历史")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
        }
      }
      .alert(
        "安装指定版本",
        isPresented: Binding(
          get: { pendingVersion != nil }, set: { if !$0 { pendingVersion = nil } }),
        presenting: pendingVersion
      ) { version in
        Button("确认安装") {
          Task { await installRelease(version) }
        }
        Button("取消", role: .cancel) {}
      } message: { version in
        Text("确认安装「\(plugin.displayName)」的 \(version) 版本吗？")
      }
      .task { await loadVersionHistory() }
    }
    .nativeGlassSheet()
  }

  private func loadVersionHistory() async {
    isLoading = true
    defer { isLoading = false }
    if let dict = plugin.history {
      declaredHistory = dict
    }
    async let releasesTask: Void = loadReleases()
    async let historyTask: Void = loadDeclaredHistory()
    _ = await (releasesTask, historyTask)
  }

  private func loadReleases() async {
    var query: [URLQueryItem] = []
    if let repo = plugin.repoURL, !repo.isEmpty {
      query.append(URLQueryItem(name: "repo_url", value: repo))
    }
    guard let ep = try? APIEndpoint(path: ["plugin", "releases", sourcePluginID], query: query),
      let loaded = try? await session.request(
        ep, as: NativePluginReleaseData.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    else { return }
    releases = loaded
  }

  private func loadDeclaredHistory() async {
    guard
      let ep = try? APIEndpoint(
        path: ["plugin", "history", sourcePluginID],
        query: [URLQueryItem(name: "force", value: "false")]),
      let loaded = try? await session.request(
        ep, as: NativeMarketPluginRecord.self,
        requiring: PermissionRequirement(category: .admin)
      ).value,
      let dict = loaded.history, !dict.isEmpty
    else { return }
    declaredHistory = dict
  }

  private func installRelease(_ version: String) async {
    isInstalling = true
    bannerMessage = nil
    defer { isInstalling = false }
    do {
      var query = [
        URLQueryItem(name: "force", value: "true"),
        URLQueryItem(name: "release_version", value: version),
      ]
      if let repo = plugin.repoURL, !repo.isEmpty {
        query.append(URLQueryItem(name: "repo_url", value: repo))
      }
      let ep = try APIEndpoint(
        path: ["plugin", "install", sourcePluginID], query: query,
        responseContract: .payload, timeout: 90)
      let resp = try await session.request(
        ep, as: NativePluginSimpleResponse.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      if resp.success == false {
        bannerIsError = true
        bannerMessage = resp.message ?? "安装指定版本失败。"
        return
      }
      onCompleted("「\(plugin.displayName)」(\(version)) 安装已完成。")
      dismiss()
    } catch {
      bannerIsError = true
      bannerMessage = "安装失败：\(error.localizedDescription)"
    }
  }

  private static func normalizeVersionKey(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return trimmed.lowercased().hasPrefix("v") ? trimmed : "v\(trimmed)"
  }

  private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
    let lp = versionParts(lhs)
    let rp = versionParts(rhs)
    let n = max(lp.count, rp.count)
    for i in 0..<n {
      let a = i < lp.count ? lp[i] : 0
      let b = i < rp.count ? rp[i] : 0
      if a != b { return a < b ? -1 : 1 }
    }
    return 0
  }

  private static func versionParts(_ raw: String) -> [Int] {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.lowercased().hasPrefix("v") { trimmed.removeFirst() }
    return trimmed.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
  }
}

/// 创建/恢复插件分身弹窗（对标 Web `PluginCloneDialog.vue`，采用 iOS 设置分组表单风格）：
/// 自动查询 `GET /api/v1/plugin/clone/{id}/restorable` 并提交 `POST /api/v1/plugin/clone/{id}`。
@MainActor
private struct NativePluginCloneSheet: View {
  let session: NativeSession
  let plugin: NativeMarketPluginRecord
  let onCloned: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var suffix = ""
  @State private var name: String
  @State private var descriptionText: String
  @State private var iconText: String
  @State private var restorePrevious = true
  @State private var restorable: [NativeRestorableClone] = []
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  init(
    session: NativeSession,
    plugin: NativeMarketPluginRecord,
    onCloned: @escaping (String) -> Void
  ) {
    self.session = session
    self.plugin = plugin
    self.onCloned = onCloned
    _name = State(initialValue: "\(plugin.displayName) 分身")
    _descriptionText = State(initialValue: plugin.summary)
    _iconText = State(initialValue: plugin.pluginIcon ?? "")
  }

  private var suffixValidationError: String? {
    let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count > 20 { return "后缀最长 20 个字符" }
    let valid = trimmed.unicodeScalars.allSatisfy {
      ($0.value >= 48 && $0.value <= 57) || ($0.value >= 65 && $0.value <= 90)
        || ($0.value >= 97 && $0.value <= 122)
    }
    return valid ? nil : "后缀仅允许英文字母或数字（A-Z, a-z, 0-9）"
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if let errorMessage {
              CinematicPanel(padding: 12) {
                HStack(spacing: 8) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NativeTheme.danger)
                  Text(errorMessage).font(.caption).foregroundStyle(NativeTheme.danger)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }

            if !restorable.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Text("可恢复的已停用分身")
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8)
                CinematicPanel(padding: 0) {
                  VStack(spacing: 0) {
                    ForEach(Array(restorable.enumerated()), id: \.element.id) { idx, item in
                      if idx > 0 { CinematicFormDivider() }
                      let selected = suffix.lowercased() == item.suffix.lowercased()
                      Button {
                        suffix = item.suffix
                        if let oldName = item.name, !oldName.isEmpty { name = oldName }
                      } label: {
                        HStack(spacing: 10) {
                          VStack(alignment: .leading, spacing: 2) {
                            Text(item.name?.isEmpty == false ? item.name! : item.instanceID)
                              .font(.subheadline.weight(.medium))
                              .foregroundStyle(.primary)
                            Text("后缀：\(item.suffix) · \(item.instanceID)")
                              .font(.caption.monospaced())
                              .foregroundStyle(.secondary)
                          }
                          Spacer()
                          if selected {
                            Image(systemName: "checkmark")
                              .font(.subheadline.weight(.semibold))
                              .foregroundStyle(appearance.accentColor)
                          }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                      }
                      .buttonStyle(.plain)
                    }
                  }
                }
                Text("点选已有记录可快速填入对应后缀与名称。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8)
              }
            }

            VStack(alignment: .leading, spacing: 8) {
              Text("基本信息")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  settingsInputRow(
                    title: "分身后缀", placeholder: "留空自动分配，如 2 或 alt", text: $suffix)
                  CinematicFormDivider()
                  settingsInputRow(title: "分身名称", placeholder: "输入分身展示名", text: $name)
                  CinematicFormDivider()
                  settingsInputRow(title: "分身描述", placeholder: "可选", text: $descriptionText)
                  CinematicFormDivider()
                  settingsInputRow(title: "自定义图标", placeholder: "可选图标名或链接", text: $iconText)
                }
              }
              if let suffixValidationError {
                Text(suffixValidationError)
                  .font(.caption)
                  .foregroundStyle(NativeTheme.danger)
                  .padding(.horizontal, 8)
              } else {
                Text("后缀仅允许英文字母或数字（A-Z, a-z, 0-9），最长 20 位，留空自动分配。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8)
              }
            }

            VStack(alignment: .leading, spacing: 8) {
              Text("配置恢复")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
              CinematicPanel(padding: 0) {
                Toggle("恢复历史配置", isOn: $restorePrevious)
                  .font(.body)
                  .tint(appearance.accentColor)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 12)
                  .frame(minHeight: 52)
              }
              Text("若该后缀留有已停用的历史配置，创建分身时自动恢复原配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }
          }
          .frame(maxWidth: 740, alignment: .leading)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 16)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("创建插件分身")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await submitClone() }
          } label: {
            if isSubmitting {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("创建").fontWeight(.semibold)
            }
          }
          .tint(.primary)
          .disabled(isSubmitting || suffixValidationError != nil)
        }
      }
      .task { await loadRestorable() }
    }
    .nativeGlassSheet()
  }

  private func settingsInputRow(title: String, placeholder: String, text: Binding<String>)
    -> some View
  {
    HStack(spacing: 12) {
      Text(title)
        .font(.body)
        .foregroundStyle(.primary)
        .frame(width: 88, alignment: .leading)
      TextField(placeholder, text: text)
        .font(.subheadline)
        .multilineTextAlignment(.trailing)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(minHeight: 52)
  }

  private func loadRestorable() async {
    guard let ep = try? APIEndpoint(path: ["plugin", "clone", plugin.id, "restorable"]),
      let loaded = try? await session.request(
        ep, as: [NativeRestorableClone].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    else { return }
    restorable = loaded
  }

  private func submitClone() async {
    isSubmitting = true
    errorMessage = nil
    defer { isSubmitting = false }
    let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    let payload = NativePluginClonePayload(
      suffix: trimmedSuffix.isEmpty ? nil : trimmedSuffix,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
      icon: iconText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? nil : iconText.trimmingCharacters(in: .whitespacesAndNewlines),
      restorePrevious: restorePrevious)
    do {
      let body = try JSONEncoder().encode(payload)
      let ep = try APIEndpoint(
        path: ["plugin", "clone", plugin.id], method: .post, body: body,
        responseContract: .payload, timeout: 45)
      let resp = try await session.request(
        ep, as: NativePluginEnvelope<NativePluginCloneOutcome>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      if resp.success == false {
        errorMessage = resp.message ?? "创建插件分身失败。"
        return
      }
      let newID = resp.data?.instanceID ?? ""
      onCloned(newID.isEmpty ? "已成功创建「\(plugin.displayName)」的分身。" : "已创建分身：\(newID)。")
      dismiss()
    } catch {
      errorMessage = "创建插件分身失败：\(error.localizedDescription)"
    }
  }
}

/// 插件专属实时日志查看弹窗（`GET /api/v1/system/logging?length=200&logfile=plugins/{id}.log`）。
@MainActor
private struct NativePluginLogSheet: View {
  let session: NativeSession
  let plugin: NativeMarketPluginRecord

  @Environment(\.dismiss) private var dismiss
  @State private var lines: [String] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        if isLoading && lines.isEmpty {
          ScrollView {
            NativeCardListSkeletonView(count: 5, style: .messageCard)
              .padding(.horizontal, CinematicStyle.margin)
              .padding(.vertical, 12)
          }
          .scrollIndicators(.hidden)
          .transition(.opacity)
        } else if let errorMessage {
          CinematicPanel {
            VStack(spacing: 10) {
              Text(errorMessage).font(.subheadline).foregroundStyle(.secondary)
              Button("重试") { Task { await loadLogs() } }
            }
            .frame(maxWidth: .infinity)
          }
          .padding(.horizontal, CinematicStyle.margin)
        } else if lines.isEmpty {
          Text("暂无插件日志输出").font(.subheadline).foregroundStyle(.secondary)
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                  .font(.caption2.monospaced())
                  .foregroundStyle(colorForLogLine(line))
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.vertical, 12)
          }
          .refreshable { await loadLogs() }
        }
      }
      .navigationTitle("\(plugin.displayName) 日志")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await loadLogs() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .tint(.primary)
          .accessibilityLabel("刷新")
        }
      }
      .task { await loadLogs() }
    }
    .nativeGlassSheet()
  }

  private func loadLogs() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      let ep = try APIEndpoint(
        path: ["system", "logging"],
        query: [
          URLQueryItem(name: "length", value: "200"),
          URLQueryItem(name: "logfile", value: "plugins/\(plugin.id.lowercased()).log"),
        ],
        responseContract: .payload,
        timeout: 20)
      let data = try await session.requestResourcePayload(ep).value
      let rawText = String(data: data, encoding: .utf8) ?? ""
      lines = rawText.components(separatedBy: .newlines).filter {
        !$0.trimmingCharacters(in: .whitespaces).isEmpty
      }
    } catch {
      errorMessage = "读取插件日志失败：\(error.localizedDescription)"
    }
  }

  private func colorForLogLine(_ line: String) -> Color {
    let upper = line.uppercased()
    if upper.contains("ERROR") || upper.contains("CRITICAL") { return NativeTheme.danger }
    if upper.contains("WARNING") || upper.contains("WARN") { return NativeTheme.warning }
    if upper.contains("DEBUG") { return .secondary }
    return .primary
  }
}

/// 插件运行能力只读诊断弹窗（`GET /api/v1/plugin/runtime/capabilities?plugin_id={id}`）。
@MainActor
private struct NativePluginCapabilitiesSheet: View {
  let session: NativeSession
  let plugin: NativeMarketPluginRecord

  @Environment(\.dismiss) private var dismiss
  @State private var capabilities: NativePluginCapabilitiesData?
  @State private var isLoading = true

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if isLoading {
              NativeCardListSkeletonView(count: 2, style: .formPanel)
                .transition(.opacity)
            } else if let cap = capabilities {
              capabilityCard(
                title: "注册命令 (\(cap.commands.count))",
                rows: cap.commands.map { ($0.cmd, $0.desc ?? "") })
              capabilityCard(
                title: "定时服务 (\(cap.services.count))",
                rows: cap.services.map { ($0.name ?? $0.id, $0.trigger ?? "") })
              let flatActions = cap.actions.flatMap(\.actions)
              capabilityCard(
                title: "工作流动作 (\(flatActions.count))",
                rows: flatActions.map { ($0.name ?? $0.id, $0.id) })
            } else {
              Text("暂未读取到插件运行能力").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
      }
      .navigationTitle("运行能力")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
        }
      }
      .task { await load() }
    }
    .nativeGlassSheet()
  }

  private func capabilityCard(title: String, rows: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(
        .horizontal, 4)
      CinematicPanel(padding: 13) {
        if rows.isEmpty {
          Text("无").font(.caption).foregroundStyle(.secondary).frame(
            maxWidth: .infinity, alignment: .leading)
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
              if idx > 0 { Divider().overlay(NativeTheme.divider) }
              HStack {
                Text(row.0).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if !row.1.isEmpty {
                  Text(row.1).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
              }
            }
          }
        }
      }
    }
  }

  private func load() async {
    defer { isLoading = false }
    guard
      let ep = try? APIEndpoint(
        path: ["plugin", "runtime", "capabilities"],
        query: [URLQueryItem(name: "plugin_id", value: plugin.id)],
        responseContract: .payload),
      let resp = try? await session.request(
        ep, as: NativePluginEnvelope<NativePluginCapabilitiesData>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    else { return }
    capabilities = resp.data
  }
}

/// 插件持久化数据键摘要弹窗（`GET /api/v1/plugin/runtime/{id}/data/summary`，不含敏感原值）。
@MainActor
private struct NativePluginDataSummarySheet: View {
  let session: NativeSession
  let plugin: NativeMarketPluginRecord

  @Environment(\.dismiss) private var dismiss
  @State private var summary: NativePluginDataSummaryData?
  @State private var isLoading = true

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if isLoading {
              NativeCardListSkeletonView(count: 2, style: .formPanel)
                .transition(.opacity)
            } else if let s = summary {
              CinematicPanel(padding: 13) {
                HStack {
                  VStack(alignment: .leading, spacing: 3) {
                    Text("持久化键总数").font(.caption).foregroundStyle(.secondary)
                    Text("\(s.count)").font(.title3.monospacedDigit().bold())
                  }
                  Spacer()
                  VStack(alignment: .trailing, spacing: 3) {
                    Text("总字符估算").font(.caption).foregroundStyle(.secondary)
                    Text("\(s.totalChars)").font(.title3.monospacedDigit().bold())
                  }
                }
              }
              if !s.keys.isEmpty {
                CinematicPanel(padding: 13) {
                  VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(s.keys.enumerated()), id: \.offset) { idx, item in
                      if idx > 0 { Divider().overlay(NativeTheme.divider) }
                      HStack {
                        Text(item.key).font(.caption.monospaced().weight(.medium))
                        Spacer()
                        NativeAdaptiveBadge(item.valueType, tint: NativeTheme.info)
                      }
                    }
                  }
                }
              }
            } else {
              Text("暂未读取到插件数据摘要").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
      }
      .navigationTitle("数据摘要")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
        }
      }
      .task { await load() }
    }
    .nativeGlassSheet()
  }

  private func load() async {
    defer { isLoading = false }
    guard
      let ep = try? APIEndpoint(
        path: ["plugin", "runtime", plugin.id, "data", "summary"], responseContract: .payload),
      let resp = try? await session.request(
        ep, as: NativePluginEnvelope<NativePluginDataSummaryData>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    else { return }
    summary = resp.data
  }
}

/// 插件实例管理弹窗（对标 Web `PluginInstanceManageDialog.vue`）：
/// 管理本体与各分身的启停、默认调用目标及独立日志等级覆盖。
@MainActor
private struct NativePluginInstanceManageSheet: View {
  let session: NativeSession
  let plugin: NativeMarketPluginRecord
  let allInstalled: [NativeMarketPluginRecord]
  let onUpdated: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var logLevels: [String: NativePluginLogLevelItem] = [:]
  @State private var busyID: String?
  @State private var statusMessage: String?

  private var sourceID: String {
    plugin.isInstance ? (plugin.sourcePluginID ?? plugin.id) : plugin.id
  }

  private var relatedInstances: [NativeMarketPluginRecord] {
    allInstalled.filter { item in
      let sid = item.isInstance ? (item.sourcePluginID ?? item.id) : item.id
      return sid.lowercased() == sourceID.lowercased()
    }
  }

  private let levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if let statusMessage {
              CinematicPanel(padding: 11) {
                Text(statusMessage).font(.caption).foregroundStyle(.primary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            ForEach(relatedInstances) { inst in
              let levelInfo = logLevels[inst.id] ?? logLevels[inst.id.lowercased()]
              CinematicPanel(padding: 13) {
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    VStack(alignment: .leading, spacing: 2) {
                      HStack(spacing: 6) {
                        Text(inst.displayName).font(.subheadline.weight(.semibold))
                        if !inst.isInstance {
                          NativeAdaptiveBadge("本体", tint: NativeTheme.brand)
                        } else {
                          NativeAdaptiveBadge("分身", tint: NativeTheme.info)
                        }
                        if inst.isDefaultTarget {
                          NativeAdaptiveBadge("默认目标", tint: NativeTheme.success)
                        }
                      }
                      Text(inst.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if busyID == inst.id {
                      ProgressView().controlSize(.small)
                    }
                  }

                  Divider().overlay(NativeTheme.divider)

                  HStack(spacing: 10) {
                    Menu {
                      ForEach(levels, id: \.self) { level in
                        Button(level) {
                          Task { await setLogLevel(instanceID: inst.id, level: level) }
                        }
                      }
                      Divider()
                      Button("恢复全局日志等级") {
                        Task { await clearLogLevel(instanceID: inst.id) }
                      }
                    } label: {
                      Label(
                        "日志：\(levelInfo?.effectiveLevel ?? "默认")",
                        systemImage: "slider.horizontal.3"
                      )
                      .font(.caption.weight(.medium))
                      .foregroundStyle(NativeTheme.brand)
                      .padding(.horizontal, 10)
                      .padding(.vertical, 6)
                      .background { Capsule().fill(NativeTheme.brand.opacity(0.14)) }
                    }

                    if relatedInstances.count > 1 {
                      Button {
                        Task {
                          await toggleDefaultTarget(
                            instanceID: inst.id, currentlyDefault: inst.isDefaultTarget)
                        }
                      } label: {
                        Text(inst.isDefaultTarget ? "取消默认目标" : "设为默认目标")
                          .font(.caption.weight(.medium))
                          .foregroundStyle(.primary)
                          .padding(.horizontal, 10)
                          .padding(.vertical, 6)
                          .background { Capsule().fill(NativeTheme.chipFill) }
                      }
                      .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                  }
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
      }
      .navigationTitle("实例管理")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
        }
      }
      .task { await loadLogLevels() }
    }
    .nativeGlassSheet()
  }

  private func loadLogLevels() async {
    guard
      let ep = try? APIEndpoint(
        path: ["plugin", "loglevel", sourceID], responseContract: .payload),
      let resp = try? await session.request(
        ep, as: NativePluginEnvelope<NativePluginLogLevelOverview>.self,
        requiring: PermissionRequirement(category: .admin)
      ).value,
      let items = resp.data?.instances
    else { return }
    var map: [String: NativePluginLogLevelItem] = [:]
    for item in items {
      map[item.instanceID] = item
      map[item.instanceID.lowercased()] = item
    }
    logLevels = map
  }

  private func setLogLevel(instanceID: String, level: String) async {
    busyID = instanceID
    defer { busyID = nil }
    do {
      let body = try JSONEncoder().encode(["level": level])
      let ep = try APIEndpoint(
        path: ["plugin", "loglevel", sourceID, instanceID], method: .put, body: body)
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      statusMessage = "已将 \(instanceID) 日志等级设为 \(level)。"
      await loadLogLevels()
    } catch {
      statusMessage = "设置日志等级失败：\(error.localizedDescription)"
    }
  }

  private func clearLogLevel(instanceID: String) async {
    busyID = instanceID
    defer { busyID = nil }
    do {
      let ep = try APIEndpoint(
        path: ["plugin", "loglevel", sourceID, instanceID], method: .delete)
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      statusMessage = "已清除 \(instanceID) 的独立日志等级覆盖。"
      await loadLogLevels()
    } catch {
      statusMessage = "清除日志等级失败：\(error.localizedDescription)"
    }
  }

  private func toggleDefaultTarget(instanceID: String, currentlyDefault: Bool) async {
    busyID = instanceID
    defer { busyID = nil }
    do {
      let ep = try APIEndpoint(
        path: ["plugin", "instances", sourceID, instanceID, "default_target"],
        method: currentlyDefault ? .delete : .put)
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      onUpdated(currentlyDefault ? "已取消 \(instanceID) 的默认调用目标。" : "已将 \(instanceID) 设为默认调用目标。")
      dismiss()
    } catch {
      statusMessage = "更新默认调用目标失败：\(error.localizedDescription)"
    }
  }
}

// MARK: - Models

private struct NativePluginMarketFeedback {
  let isError: Bool
  let message: String
}

private struct NativePluginSimpleResponse: Decodable, Sendable {
  let success: Bool?
  let message: String?
}

private struct NativePluginEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
  let success: Bool?
  let message: String?
  let data: T?
}

private struct NativePluginRatingSummary: Decodable, Sendable {
  let averageRating: Double
  let ratingCount: Int
  let userRating: Int?

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    averageRating = (try? c.decodeIfPresent(Double.self, forKey: .averageRating)) ?? 0
    ratingCount = (try? c.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
    userRating = try? c.decodeIfPresent(Int.self, forKey: .userRating)
  }

  private enum CodingKeys: String, CodingKey {
    case averageRating = "average_rating"
    case ratingCount = "rating_count"
    case userRating = "user_rating"
  }
}

private struct NativeMarketPluginRecord: Codable, Sendable, Identifiable {
  let id: String
  let sourcePluginID: String?
  let isInstance: Bool
  let isDefaultTarget: Bool
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
  let renderMode: String?
  let state: Bool?
  let repoURL: String?
  let installCount: Int
  let averageRating: Double
  let ratingCount: Int
  let history: [String: String]?

  var isVuePlugin: Bool { renderMode?.lowercased() == "vue" }

  var displayName: String {
    if let pluginName, !pluginName.isEmpty { return pluginName }
    return id
  }

  var summary: String { pluginDesc ?? "" }
  var version: String { pluginVersion ?? "" }
  var author: String { pluginAuthor ?? "" }
  var isRunning: Bool { state ?? false }

  var labels: [String] {
    (pluginLabel ?? "")
      .split(whereSeparator: { $0 == "," || $0 == "，" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// 优先解析 GitHub 项目主页，回退至作者主页。
  var projectHomeURL: URL? {
    let candidate: String?
    if let repo = repoURL, !repo.isEmpty, !repo.hasPrefix("local://") {
      if repo.contains("raw.githubusercontent.com"), let rawURL = URL(string: repo) {
        let comps = rawURL.pathComponents.filter { $0 != "/" }
        candidate = comps.count >= 2 ? "https://github.com/\(comps[0])/\(comps[1])" : repo
      } else {
        candidate = repo
      }
    } else {
      candidate = authorURL
    }
    guard let candidate, let url = URL(string: candidate),
      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
    else { return nil }
    return url
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? ""
    sourcePluginID = try? container.decodeIfPresent(String.self, forKey: .sourcePluginID)
    isInstance = (try? container.decodeIfPresent(Bool.self, forKey: .isInstance)) ?? false
    isDefaultTarget = (try? container.decodeIfPresent(Bool.self, forKey: .isDefaultTarget)) ?? false
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
    renderMode = try? container.decodeIfPresent(String.self, forKey: .renderMode)
    state = try? container.decodeIfPresent(Bool.self, forKey: .state)
    repoURL = try? container.decodeIfPresent(String.self, forKey: .repoURL)
    installCount = (try? container.decodeIfPresent(Int.self, forKey: .installCount)) ?? 0
    averageRating = (try? container.decodeIfPresent(Double.self, forKey: .averageRating)) ?? 0
    ratingCount = (try? container.decodeIfPresent(Int.self, forKey: .ratingCount)) ?? 0
    history = try? container.decodeIfPresent([String: String].self, forKey: .history)
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case sourcePluginID = "source_plugin_id"
    case isInstance = "is_instance"
    case isDefaultTarget = "is_default_target"
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
    case renderMode = "render_mode"
    case state
    case repoURL = "repo_url"
    case installCount = "install_count"
    case averageRating = "average_rating"
    case ratingCount = "rating_count"
    case history
  }
}

private struct NativePluginSourceIdentity: Decodable, Sendable {
  let pluginID: String
  let trustedSourceType: String
  let trustedSourceKey: String?
  let revision: Int

  private enum CodingKeys: String, CodingKey {
    case pluginID = "plugin_id"
    case trustedSourceType = "trusted_source_type"
    case trustedSourceKey = "trusted_source_key"
    case revision
  }
}

private struct NativePluginSourceCandidate: Decodable, Sendable {
  let sourceType: String
  let sourceKey: String?
  let repoURL: String?
  let packageGeneration: String
  let pluginVersion: String?

  var sourceTypeLabel: String {
    switch sourceType {
    case "official": "官方源"
    case "local": "本地"
    default: "第三方源"
    }
  }

  var displayLabel: String {
    if let key = sourceKey, !key.isEmpty {
      return key.hasPrefix("github:") ? String(key.dropFirst("github:".count)) : key
    }
    return repoURL ?? sourceTypeLabel
  }

  private enum CodingKeys: String, CodingKey {
    case sourceType = "source_type"
    case sourceKey = "source_key"
    case repoURL = "repo_url"
    case packageGeneration = "package_generation"
    case pluginVersion = "plugin_version"
  }
}

private struct NativePluginSourceOptions: Decodable, Sendable {
  let pluginID: String
  let selectionStatus: String
  let selectionReason: String
  let identity: NativePluginSourceIdentity?
  let candidates: [NativePluginSourceCandidate]

  var sortedCandidates: [NativePluginSourceCandidate] {
    candidates.sorted { lhs, rhs in
      if lhs.sourceType == "official" && rhs.sourceType != "official" { return true }
      if rhs.sourceType == "official" && lhs.sourceType != "official" { return false }
      return lhs.displayLabel < rhs.displayLabel
    }
  }

  private enum CodingKeys: String, CodingKey {
    case pluginID = "plugin_id"
    case selectionStatus = "selection_status"
    case selectionReason = "selection_reason"
    case identity, candidates
  }
}

private struct NativePluginSourceInstallPayload: Encodable, Sendable {
  let repoURL: String
  let releaseVersion: String?
  let force: Bool

  private enum CodingKeys: String, CodingKey {
    case repoURL = "repo_url"
    case releaseVersion = "release_version"
    case force
  }
}

private struct NativePluginSourceChangePayload: Encodable, Sendable {
  let repoURL: String
  let expectedRevision: Int
  let releaseVersion: String?

  private enum CodingKeys: String, CodingKey {
    case repoURL = "repo_url"
    case expectedRevision = "expected_revision"
    case releaseVersion = "release_version"
  }
}

private struct NativePluginReleaseItem: Decodable, Sendable {
  let version: String?
  let tagName: String?
  let description: String?
  let body: String?

  private enum CodingKeys: String, CodingKey {
    case version
    case tagName = "tag_name"
    case description, body
  }
}

private struct NativePluginReleaseData: Decodable, Sendable {
  let releaseSupported: Bool?
  let latestVersion: String?
  let currentVersion: String?
  let items: [NativePluginReleaseItem]?

  private enum CodingKeys: String, CodingKey {
    case releaseSupported = "release_supported"
    case latestVersion = "latest_version"
    case currentVersion = "current_version"
    case items
  }
}

private struct NativePluginDocumentation: Decodable, Sendable {
  let url: String?
  let readmeURL: String?

  private enum CodingKeys: String, CodingKey {
    case url
    case readmeURL = "readme_url"
  }
}

private struct NativeRestorableClone: Decodable, Sendable, Identifiable {
  let instanceID: String
  let suffix: String
  let name: String?

  var id: String { instanceID }

  private enum CodingKeys: String, CodingKey {
    case instanceID = "instance_id"
    case suffix, name
  }
}

private struct NativePluginClonePayload: Encodable, Sendable {
  let suffix: String?
  let name: String
  let description: String
  let icon: String?
  let restorePrevious: Bool

  private enum CodingKeys: String, CodingKey {
    case suffix, name, description, icon
    case restorePrevious = "restore_previous"
  }
}

private struct NativePluginCloneOutcome: Decodable, Sendable {
  let instanceID: String?
  private enum CodingKeys: String, CodingKey {
    case instanceID = "instance_id"
  }
}

private struct NativePluginCapabilitiesData: Decodable, Sendable {
  struct CommandItem: Decodable, Sendable {
    let cmd: String
    let desc: String?
  }
  struct ActionItem: Decodable, Sendable {
    let id: String
    let name: String?
  }
  struct ActionGroup: Decodable, Sendable {
    let actions: [ActionItem]
  }
  struct ServiceItem: Decodable, Sendable {
    let id: String
    let name: String?
    let trigger: String?
  }
  let commands: [CommandItem]
  let actions: [ActionGroup]
  let services: [ServiceItem]
}

private struct NativePluginDataSummaryData: Decodable, Sendable {
  struct KeyItem: Decodable, Sendable {
    let key: String
    let valueType: String
    private enum CodingKeys: String, CodingKey {
      case key
      case valueType = "value_type"
    }
  }
  let count: Int
  let totalChars: Int
  let keys: [KeyItem]

  private enum CodingKeys: String, CodingKey {
    case count
    case totalChars = "total_chars"
    case keys
  }
}

private struct NativePluginLogLevelItem: Decodable, Sendable {
  let instanceID: String
  let configuredLevel: String?
  let effectiveLevel: String?

  private enum CodingKeys: String, CodingKey {
    case instanceID = "instance_id"
    case configuredLevel = "configured_level"
    case effectiveLevel = "effective_level"
  }
}

private struct NativePluginLogLevelOverview: Decodable, Sendable {
  let instances: [NativePluginLogLevelItem]?
}
