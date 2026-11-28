import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生「订阅」旗舰主页面：顶部呈现追剧全景英雄卡、分类与状态排序过滤、离散胶片刻度进度及三键快捷操控，左上角提供追剧日历与订阅广场入口，右上角提供订阅历史入口。
@MainActor
struct NativeSubscriptionsPage: View {
  /// 订阅列表的分类筛选维度。
  enum Filter: String, CaseIterable, Identifiable, Hashable {
    case all = "全部"
    case movie = "电影"
    case tv = "电视剧"
    case music = "音乐"

    /// 使用固定中文标签作为标识。
    var id: String { rawValue }
  }

  /// 订阅排序方式。
  private enum SortMode: String, CaseIterable, Identifiable {
    case defaultOrder = "默认顺序"
    case titleAsc = "名称排序"
    case progressDesc = "完成进度"
    case dateDesc = "最近更新"
    var id: String { rawValue }
  }

  /// 订阅状态过滤。
  private enum StateFilter: String, CaseIterable, Identifiable {
    case all = "全部状态"
    case running = "仅启用"
    case paused = "仅暂停"
    var id: String { rawValue }
  }

  let session: NativeSession
  let isRootTab: Bool
  @Binding private var requestedFilter: Filter?
  let onOpenGlobalSearch: (() -> Void)?

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var containerWidth: CGFloat = 0
  @State private var items: [NativeSubscribeItem] = []
  @State private var filter: Filter
  @State private var stateFilter: StateFilter = .all
  @State private var sortMode: SortMode = .defaultOrder
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var mutatingID: Int?
  @State private var viewingFilesItem: NativeSubscribeItem?
  @State private var detailDestination: NativeMediaIdentity?
  @State private var editingItem: NativeSubscribeItem?
  @State private var pendingDelete: NativeSubscribeItem?
  @State private var feedback: NativeSubscribeFeedback?

  /// 初始化订阅主页面，支持作为主标签挂载或按指定初始分类推入，并响应外部深链切换请求。
  init(
    session: NativeSession,
    initialFilter: Filter = .all,
    isRootTab: Bool = true,
    requestedFilter: Binding<Filter?> = .constant(nil),
    onOpenGlobalSearch: (() -> Void)? = nil
  ) {
    self.session = session
    self.isRootTab = isRootTab
    _requestedFilter = requestedFilter
    self.onOpenGlobalSearch = onOpenGlobalSearch
    _filter = State(initialValue: initialFilter)
    if let cached: [NativeSubscribeItem] = NativePageDataCache.shared.get(
      "subscriptions|list", session: session)
    {
      _items = State(initialValue: cached)
      _isLoading = State(initialValue: false)
    }
  }

  /// 主体使用连续渐变底色，直接呈现我的订阅全景列表，左上角通过图标进入追剧日历与订阅广场，右上角进入订阅历史。
  var body: some View {
    let resolvedWidth = NativeDeviceLayout.resolvedContainerWidth(containerWidth)
    let margin = NativeDeviceLayout.horizontalMargin(for: resolvedWidth)
    ZStack {
      CinematicBackground()
      mineSubscriptionsScroll(resolvedWidth: resolvedWidth, margin: margin)
    }
    .nativeTrackContainerWidth($containerWidth)
    .navigationTitle(isRootTab ? L10n.text("订阅") : L10n.text("我的订阅"))
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItemGroup(placement: .topBarLeading) {
        NavigationLink {
          NativeCalendarPage(session: session)
        } label: {
          Image(systemName: "calendar")
        }
        .tint(.primary)
        .accessibilityLabel(L10n.text("追剧日历"))
        .accessibilityIdentifier("native-subscriptions-calendar")

        NavigationLink {
          NativeSubscribeCommunityPage(
            session: session,
            onSubscribed: {
              NativePageDataCache.shared.remove("subscriptions|list", session: session)
              attempt += 1
            }
          )
        } label: {
          Image(systemName: "flame.fill")
        }
        .tint(.primary)
        .accessibilityLabel(L10n.text("订阅广场"))
        .accessibilityIdentifier("native-subscriptions-community")
      }

      ToolbarItemGroup(placement: .topBarTrailing) {
        NavigationLink {
          NativeSubscribeHistoryPage(
            session: session,
            initialType: historyInitialType,
            onReSubscribed: {
              NativePageDataCache.shared.remove("subscriptions|list", session: session)
              attempt += 1
            }
          )
        } label: {
          Image(systemName: "clock.arrow.circlepath")
        }
        .tint(.primary)
        .accessibilityLabel(L10n.text("订阅历史"))
        .accessibilityIdentifier("native-subscriptions-history")
      }
    }
    .onAppear {
      consumeExternalRequestsIfNeeded()
    }
    .onChange(of: requestedFilter) { _ in
      consumeExternalRequestsIfNeeded()
    }
    .task(id: attempt) {
      await load(forceRefresh: attempt > 0)
    }
    .navigationDestination(
      isPresented: Binding(
        get: { detailDestination != nil },
        set: { if !$0 { detailDestination = nil } }
      )
    ) {
      if let identity = detailDestination {
        NativeMediaDetailPage(session: session, identity: identity)
      }
    }
    .sheet(item: $viewingFilesItem) { item in
      NativeSubscribeFilesSheet(
        session: session, subscribeID: item.id, fallbackTitle: item.displayTitle
      )
      .nativeAdaptiveSheetSizing()
    }
    .sheet(item: $editingItem) { item in
      NativeSubscribeEditorSheet(session: session, subscribeID: item.id, title: item.displayTitle) {
        feedback = NativeSubscribeFeedback(isError: false, message: "订阅规则已更新。")
        NativePageDataCache.shared.remove("subscriptions|list", session: session)
        attempt += 1
      }
      .nativeAdaptiveSheetSizing()
    }
    .alert(
      "取消订阅",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { item in
      Button("取消订阅", role: .destructive) {
        Task { await deleteSubscribe(item) }
      }
      Button("保留", role: .cancel) {}
    } message: { item in
      Text("确认删除「\(item.displayTitle)」订阅吗？")
    }
  }

  /// 消费来自深链或小组件的分类筛选请求。
  private func consumeExternalRequestsIfNeeded() {
    if let targetFilter = requestedFilter {
      filter = targetFilter
      requestedFilter = nil
    }
  }

  /// 根据当前分类筛选推导订阅历史默认选中的媒体类型。
  private var historyInitialType: NativeSubscribeHistoryPage.MediaType {
    switch filter {
    case .tv: .tv
    case .music: .music
    case .all, .movie: .movie
    }
  }

  // MARK: - 「我的订阅」主视图与全景总览卡

  private func mineSubscriptionsScroll(resolvedWidth: CGFloat, margin: CGFloat) -> some View {
    let columnCount = NativeDeviceLayout.cardGridCount(
      for: resolvedWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    return ScrollView {
      VStack(alignment: .leading, spacing: 15) {
        if let feedback {
          feedbackBanner(feedback)
        }
        if isLoading && items.isEmpty {
          NativeSubscriptionsHubSkeletonView(columns: columnCount)
            .transition(.opacity)
        } else if loadFailed && items.isEmpty {
          failureCard
        } else if items.isEmpty {
          welcomingEmptyCard
        } else {
          subscriptionHeroCard
          filterAndSearchControls(resolvedWidth: resolvedWidth)
          if filteredItems.isEmpty {
            filteredEmptyCard
          } else {
            let gridColumns = Array(
              repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
            LazyVGrid(columns: gridColumns, spacing: 12) {
              ForEach(filteredItems) { item in
                subscribeCard(item)
              }
            }
          }
        }
      }
      .frame(maxWidth: resolvedWidth >= 740 ? 1180 : 860, alignment: .leading)
      .padding(.horizontal, margin)
      .padding(.top, 8)
      .padding(.bottom, 34)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.hidden)
    .refreshable { await load(forceRefresh: true) }
    .modifier(NativeSoftTopScrollEdge())
    .accessibilityIdentifier("native-subscriptions-scroll")
  }

  /// 真实订阅统计指标汇总。
  private var overviewStats:
    (
      activeCount: Int, pausedCount: Int, washingCount: Int,
      totalEpisodes: Int, completedEpisodes: Int, lackEpisodes: Int
    )
  {
    let activeCount = items.filter { !$0.isPaused }.count
    let pausedCount = items.filter(\.isPaused).count
    let washingCount = items.filter { !$0.isPaused && $0.bestVersion == 1 }.count
    let episodeProjections = items.compactMap(\.progressProjection).filter { $0.unit == .episode }
    let totalEpisodes = episodeProjections.reduce(0) { $0 + $1.total }
    let completedEpisodes = episodeProjections.reduce(0) { $0 + $1.completed }
    let lackEpisodes = max(totalEpisodes - completedEpisodes, 0)
    return (activeCount, pausedCount, washingCount, totalEpisodes, completedEpisodes, lackEpisodes)
  }

  /// 追剧总览英雄玻璃卡：基于真实订阅数据展示在追部数与总体集数完成进度（分类筛选由下方筛选栏承载，追剧日历与订阅广场由右上角导航图标进入）。
  private var subscriptionHeroCard: some View {
    let stats = overviewStats
    let accent = appearance.accentColor
    let episodeFraction: Double =
      stats.totalEpisodes > 0
      ? min(max(Double(stats.completedEpisodes) / Double(stats.totalEpisodes), 0), 1)
      : 0
    let completionPercent = Int((episodeFraction * 100).rounded())

    return CinematicPanel(padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text("\(stats.activeCount)")
                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
              Text("部在追")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
              if stats.pausedCount > 0 {
                NativeAdaptiveBadge("已暂停 \(stats.pausedCount)", tint: NativeTheme.badgeMutedText)
              }
              if stats.washingCount > 0 {
                NativeAdaptiveBadge("洗版 \(stats.washingCount) 部", tint: NativeTheme.warning)
              }
              if stateFilter != .all || sortMode != .defaultOrder {
                NativeAdaptiveBadge(
                  stateFilter != .all ? stateFilter.rawValue : sortMode.rawValue,
                  tint: NativeTheme.info
                )
              }
            }

            if stats.totalEpisodes > 0 {
              Text(
                "已完成 \(stats.completedEpisodes)/\(stats.totalEpisodes) 集 · 待更 \(stats.lackEpisodes) 集"
              )
              .font(.caption.monospacedDigit().weight(.medium))
              .foregroundStyle(.secondary)
            } else {
              Text("自动追踪站点更新并匹配最佳资源")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 6)

          if stats.totalEpisodes > 0 {
            VStack(alignment: .trailing, spacing: 2) {
              Text("\(completionPercent)%")
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent)
              Text("集数进度")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
          }
        }

        if stats.totalEpisodes > 0 {
          GeometryReader { proxy in
            let fullWidth = max(proxy.size.width, 1)
            let filledWidth =
              stats.completedEpisodes > 0
              ? max(fullWidth * episodeFraction, 8)
              : 0
            ZStack(alignment: .leading) {
              Capsule()
                .fill(NativeTheme.chipFill)
              if filledWidth > 0 {
                Capsule()
                  .fill(
                    LinearGradient(
                      colors: [accent, NativeTheme.pink],
                      startPoint: .leading,
                      endPoint: .trailing
                    )
                  )
                  .frame(width: filledWidth)
              }
            }
          }
          .frame(height: 6.5)
          .accessibilityHidden(true)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-subscriptions-overview")
  }

  /// 分类筛选胶囊栏 + 紧凑片名快速过滤框与状态排序菜单（宽屏单行并排，窄屏上下排布防挤压）。
  @ViewBuilder
  private func filterAndSearchControls(resolvedWidth: CGFloat) -> some View {
    if resolvedWidth >= 640 && !dynamicTypeSize.isAccessibilitySize {
      HStack(spacing: 10) {
        filterBar
        Spacer(minLength: 4)
        searchAndSortRow
          .frame(width: 284)
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        filterBar
        searchAndSortRow
      }
    }
  }

  /// 内联搜索框 + 右侧状态与排序下拉胶囊按钮。
  private var searchAndSortRow: some View {
    HStack(spacing: 8) {
      inlineSearchField
      Menu {
        Section("订阅状态") {
          ForEach(StateFilter.allCases) { option in
            Button {
              stateFilter = option
            } label: {
              if stateFilter == option {
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
      } label: {
        let hasActiveSortOrState = stateFilter != .all || sortMode != .defaultOrder
        Image(systemName: "line.3.horizontal.decrease")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(hasActiveSortOrState ? appearance.accentColor : .primary.opacity(0.82))
          .frame(width: 36, height: 36)
          .background {
            Circle()
              .fill(
                hasActiveSortOrState
                  ? appearance.accentColor.opacity(colorScheme == .light ? 0.14 : 0.20)
                  : NativeTheme.fieldFill
              )
              .overlay {
                Circle()
                  .strokeBorder(
                    hasActiveSortOrState
                      ? appearance.accentColor.opacity(0.36)
                      : NativeTheme.fieldBorder,
                    lineWidth: 0.7
                  )
              }
          }
      }
      .accessibilityLabel("筛选与排序")
      .accessibilityIdentifier("native-subscriptions-filter-menu")
    }
  }

  /// 紧凑内联片名筛选框（替代系统 UISearchController，避免推挤顶部分区栏）。
  private var inlineSearchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      TextField("筛选已订阅片名…", text: $searchText)
        .font(.subheadline)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .accessibilityIdentifier("native-subscriptions-search")
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清除筛选关键词")
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 36)
    .background {
      Capsule()
        .fill(NativeTheme.fieldFill)
        .overlay {
          Capsule().strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.7)
        }
    }
  }

  /// 按所选类型、状态、关键字与排序整理后的订阅列表。
  private var filteredItems: [NativeSubscribeItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let matched = items.filter { item in
      let matchesKind: Bool =
        switch filter {
        case .all: true
        case .movie: item.type == "电影"
        case .tv: item.type == "电视剧"
        case .music: item.type == "音乐"
        }
      guard matchesKind else { return false }
      let matchesState: Bool =
        switch stateFilter {
        case .all: true
        case .running: !item.isPaused
        case .paused: item.isPaused
        }
      guard matchesState else { return false }
      guard !trimmed.isEmpty else { return true }
      return item.displayTitle.lowercased().contains(trimmed)
    }
    switch sortMode {
    case .defaultOrder:
      return matched
    case .titleAsc:
      return matched.sorted {
        $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
      }
    case .progressDesc:
      return matched.sorted {
        ($0.progressProjection?.fraction ?? 0) > ($1.progressProjection?.fraction ?? 0)
      }
    case .dateDesc:
      return matched.sorted { $0.id > $1.id }
    }
  }

  /// 顶部分类胶囊筛选栏，同时展示各分类真实条数。
  private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Filter.allCases) { option in
          let count = countFor(option)
          let selected = filter == option
          Button {
            withAnimation(.easeOut(duration: 0.18)) {
              filter = option
            }
          } label: {
            Text(count > 0 ? "\(option.rawValue) \(count)" : option.rawValue)
              .font(.subheadline.weight(selected ? .semibold : .regular))
              .foregroundStyle(.primary.opacity(selected ? 0.98 : 0.78))
              .padding(.horizontal, 13)
              .padding(.vertical, 7)
              .background {
                Capsule()
                  .fill(
                    selected
                      ? appearance.accentColor.opacity(colorScheme == .light ? 0.16 : 0.22)
                      : NativeTheme.chipFill
                  )
                  .overlay {
                    Capsule()
                      .strokeBorder(
                        selected ? appearance.accentColor.opacity(0.42) : NativeTheme.chipBorder,
                        lineWidth: 0.7
                      )
                  }
              }
              .frame(minHeight: 36)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-subscriptions-filter-\(option.rawValue)")
        }
      }
    }
  }

  /// 统计单个分类下的真实订阅条目数。
  private func countFor(_ option: Filter) -> Int {
    switch option {
    case .all: items.count
    case .movie: items.filter { $0.type == "电影" }.count
    case .tv: items.filter { $0.type == "电视剧" }.count
    case .music: items.filter { $0.type == "音乐" }.count
    }
  }

  // MARK: - 单条订阅卡片

  /// 单条订阅高质感轻量玻璃卡片：`76×114pt` 2:3 海报（含角标评分）、季号胶囊、语义状态角标、离散胶片刻度与轻量操作栏。
  private func subscribeCard(_ item: NativeSubscribeItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.poster, source: item.mediaSource ?? "themoviedb")
    let isMutating = mutatingID == item.id
    return CinematicPanel(padding: 13, cornerRadius: 20, style: .subtle) {
      HStack(alignment: .top, spacing: 13) {
        posterView(poster, vote: item.vote)

        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(item.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

              if let seasonTag = item.seasonTag {
                NativeAdaptiveBadge(seasonTag, tint: appearance.accentColor)
              }
            }

            Spacer(minLength: 4)
            stateBadge(item)
          }

          HStack(spacing: 8) {
            if let year = item.year, !year.isEmpty {
              Text(year)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if let type = item.type, !type.isEmpty {
              Text(type)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if item.type == "电影" {
              Text(item.bestVersion == 1 ? "持续匹配更优洗版资源" : "等待高优先级资源命中")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }

          if let projection = item.progressProjection {
            subscribeTickStrip(projection, item: item)
              .padding(.top, 1)
          }

          HStack(spacing: 8) {
            cardActionButton(
              title: item.isPaused ? "恢复" : "暂停",
              symbol: item.isPaused ? "play.fill" : "pause.fill",
              isLoading: isMutating,
              disabled: mutatingID != nil,
              accessibilityLabel: item.isPaused ? "恢复订阅" : "暂停订阅",
              accessibilityID: "native-subscribe-toggle-\(item.id)"
            ) {
              Task { await toggleStatus(item) }
            }

            cardActionButton(
              title: "规则",
              symbol: "slider.horizontal.3",
              accessibilityLabel: "编辑订阅规则",
              accessibilityID: "native-subscribe-edit-\(item.id)"
            ) {
              editingItem = item
            }

            cardActionButton(
              title: "文件",
              symbol: "doc.text.magnifyingglass",
              accessibilityLabel: "查看订阅文件详情",
              accessibilityID: "native-subscribe-files-\(item.id)"
            ) {
              viewingFilesItem = item
            }

            Spacer(minLength: 0)
          }
          .padding(.top, 2)
        }
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .onTapGesture {
      viewingFilesItem = item
    }
    .contextMenu {
      Button {
        viewingFilesItem = item
      } label: {
        Label("文件详情", systemImage: "doc.text.magnifyingglass")
      }
      if let identity = item.detailIdentity {
        Button {
          detailDestination = identity
        } label: {
          Label("媒体详情", systemImage: "film")
        }
      }
      Button {
        editingItem = item
      } label: {
        Label("编辑订阅规则", systemImage: "slider.horizontal.3")
      }
      Button {
        Task { await toggleStatus(item) }
      } label: {
        Label(
          item.isPaused ? "恢复订阅" : "暂停订阅",
          systemImage: item.isPaused ? "play.fill" : "pause.fill"
        )
      }
      Button(role: .destructive) {
        pendingDelete = item
      } label: {
        Label("取消订阅", systemImage: "trash")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-subscribe-card-\(item.id)")
  }

  /// 订阅卡片底部轻量无厚边框操作按钮：降低列表重复描边噪音，保留清晰点击态与 32pt 易触区。
  private func cardActionButton(
    title: String,
    symbol: String,
    isLoading: Bool = false,
    disabled: Bool = false,
    accessibilityLabel: String,
    accessibilityID: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if isLoading {
          ProgressView().controlSize(.mini).tint(.primary)
        } else {
          Image(systemName: symbol)
            .font(.caption2.weight(.semibold))
        }
        Text(title)
          .font(.caption.weight(.medium))
          .lineLimit(1)
      }
      .foregroundStyle(.primary.opacity(0.84))
      .padding(.horizontal, 9)
      .frame(minHeight: 32)
      .background {
        Capsule()
          .fill(
            colorScheme == .light
              ? Color.black.opacity(0.045)
              : Color.white.opacity(0.065)
          )
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier(accessibilityID)
  }

  /// 离散剧集/曲目胶片刻度格：以独立分格替代下载式连续进度条，支持逐集缺口与洗版三态呈现。
  private func subscribeTickStrip(
    _ projection: SubscribeProgressProjection,
    item: NativeSubscribeItem
  ) -> some View {
    let activeTint: Color =
      item.isPaused
      ? NativeTheme.badgeMutedText
      : (projection.isBestVersion ? NativeTheme.warning : appearance.accentColor)
    let tickCount = projection.ticks.count
    let spacing: CGFloat = tickCount <= 10 ? 4 : (tickCount <= 18 ? 3.5 : 2.5)
    let compactFixedWidth = tickCount <= 10

    return VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(projection.summaryText)
          .font(.caption.weight(.medium).monospacedDigit())
          .foregroundStyle(
            .primary.opacity(projection.completed > 0 || projection.acquired > 0 ? 0.88 : 0.68)
          )
          .lineLimit(1)
        Spacer(minLength: 4)
        if let detail = projection.detailText {
          Text(detail)
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(
              projection.missingNumbers.isEmpty
                ? Color.primary.opacity(0.62)
                : activeTint.opacity(colorScheme == .dark ? 0.92 : 0.88)
            )
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      HStack(spacing: spacing) {
        ForEach(Array(projection.ticks.enumerated()), id: \.offset) { _, state in
          subscribeTickCell(state: state, tint: activeTint, fixedCompactWidth: compactFixedWidth)
        }
        if compactFixedWidth {
          Spacer(minLength: 0)
        }
      }
      .frame(height: 8)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(projection.accessibilitySummary)
    .accessibilityIdentifier("native-subscribe-ticks-\(item.id)")
  }

  /// 单个胶片刻度格：已收齐为发光实格、部分/初版为半透描边格、未获取为凹陷空槽。
  private func subscribeTickCell(
    state: SubscribeTickState,
    tint: Color,
    fixedCompactWidth: Bool
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
    return Group {
      switch state {
      case .complete:
        shape
          .fill(
            LinearGradient(
              colors: [tint.opacity(0.96), tint.opacity(0.76)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .overlay {
            shape.strokeBorder(
              Color.white.opacity(colorScheme == .dark ? 0.24 : 0.34),
              lineWidth: 0.5
            )
          }
      case .partial:
        shape
          .fill(tint.opacity(colorScheme == .dark ? 0.34 : 0.28))
          .overlay {
            shape.strokeBorder(
              tint.opacity(colorScheme == .dark ? 0.78 : 0.68),
              lineWidth: 0.8
            )
          }
      case .empty:
        shape
          .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
          .overlay {
            shape.strokeBorder(
              Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.16),
              lineWidth: 0.6
            )
          }
      }
    }
    .frame(width: fixedCompactWidth ? 16 : nil, height: 8)
    .frame(maxWidth: fixedCompactWidth ? nil : .infinity)
  }

  /// `76×114pt` 2:3 竖版海报，带微光玻璃描边与左下角评分徽标。
  private func posterView(_ reference: String?, vote: Double?) -> some View {
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    return NativeMediaArtwork(
      session: session, reference: reference, role: .poster, maximumWidth: 420
    )
    .frame(width: 76, height: 114)
    .clipShape(shape)
    .overlay {
      shape.strokeBorder(.primary.opacity(0.14), lineWidth: 0.6)
    }
    .overlay(alignment: .bottomLeading) {
      if let vote, vote > 0 {
        HStack(spacing: 2.5) {
          Image(systemName: "star.fill")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.yellow)
          Text(String(format: "%.1f", vote))
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 5.5)
        .padding(.vertical, 2.5)
        .background {
          Capsule().fill(.black.opacity(0.68))
        }
        .padding(5)
      }
    }
  }

  /// 订阅运行状态徽标。
  private func stateBadge(_ item: NativeSubscribeItem) -> some View {
    let text = item.isPaused ? "已暂停" : (item.bestVersion == 1 ? "洗版" : "订阅中")
    let tint: Color =
      item.isPaused
      ? NativeTheme.badgeMutedText
      : (item.bestVersion == 1 ? NativeTheme.warning : NativeTheme.success)
    return Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background {
        Capsule()
          .fill(tint.opacity(0.13))
          .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
      }
  }

  // MARK: - 提示条与空/错态

  /// 轻量反馈提示条。
  private func feedbackBanner(_ feedback: NativeSubscribeFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : NativeTheme.success)
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
    .accessibilityIdentifier("native-subscriptions-feedback")
  }

  /// 尚无任何订阅时的引导空态卡片：一键前往订阅广场或打开全局搜索。
  private var welcomingEmptyCard: some View {
    let accent = appearance.accentColor
    return CinematicPanel(padding: 24) {
      VStack(spacing: 14) {
        ZStack {
          Circle()
            .fill(accent.opacity(colorScheme == .light ? 0.12 : 0.18))
            .frame(width: 60, height: 60)
          Image(systemName: "bookmark.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(accent)
        }
        VStack(spacing: 6) {
          Text("还没有正在追踪的订阅")
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
          Text("去订阅广场发现热门榜单与社区规则，或直接搜索想看的电影与剧集。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        HStack(spacing: 10) {
          NavigationLink {
            NativeSubscribeCommunityPage(
              session: session,
              onSubscribed: {
                NativePageDataCache.shared.remove("subscriptions|list", session: session)
                attempt += 1
              }
            )
          } label: {
            Label("逛逛订阅广场", systemImage: "flame.fill")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 16)
              .frame(minHeight: 40)
              .background {
                Capsule().fill(accent)
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-subscriptions-empty-community")

          if let onOpenGlobalSearch {
            Button(action: onOpenGlobalSearch) {
              Label("全局搜索", systemImage: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background {
                  Capsule()
                    .fill(NativeTheme.chipFill)
                    .overlay {
                      Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.7)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-subscriptions-empty-search")
          }
        }
        .padding(.top, 2)
      }
      .frame(maxWidth: .infinity, minHeight: 200)
    }
    .accessibilityIdentifier("native-subscriptions-empty")
  }

  /// 当前筛选条件下无匹配项的空态卡片。
  private var filteredEmptyCard: some View {
    CinematicPanel(padding: 20) {
      VStack(spacing: 10) {
        Image(systemName: "line.3.horizontal.decrease.circle")
          .font(.title)
          .foregroundStyle(.secondary)
        Text("暂无匹配的订阅")
          .font(.headline)
        Text("尝试切换上方分类、状态过滤或清空搜索关键词。")
          .font(.footnote)
          .foregroundStyle(.secondary)
        if filter != .all || stateFilter != .all || !searchText.isEmpty {
          Button {
            withAnimation(.easeOut(duration: 0.18)) {
              filter = .all
              stateFilter = .all
              searchText = ""
            }
          } label: {
            Text("重置筛选条件")
              .font(.caption.weight(.semibold))
              .foregroundStyle(appearance.accentColor)
              .padding(.horizontal, 14)
              .frame(minHeight: 34)
              .background {
                Capsule()
                  .fill(appearance.accentColor.opacity(0.14))
              }
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 140)
    }
  }

  /// 载入失败重试卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入订阅列表", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-subscriptions-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - 数据请求与状态变更

  /// 从 `GET /api/v1/subscribe/` 拉取当前用户可见的全部订阅；命中缓存时静默复用，下拉刷新强制重拉。
  private func load(forceRefresh: Bool = false) async {
    let cacheKey = "subscriptions|list"
    if !forceRefresh,
      let cached: [NativeSubscribeItem] = NativePageDataCache.shared.get(cacheKey, session: session)
    {
      items = cached
      isLoading = false
      loadFailed = false
      return
    }
    if items.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["subscribe"], trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeSubscribeItem].self, requiring: .init(category: .subscribe)
      ).value
      try Task.checkCancellation()
      items = loaded
      NativePageDataCache.shared.set(loaded, for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if items.isEmpty { loadFailed = true }
    }
  }

  /// 单次切换订阅暂停/恢复状态（`PUT /api/v1/subscribe/status/{id}?state=S|R`）。
  private func toggleStatus(_ item: NativeSubscribeItem) async {
    mutatingID = item.id
    defer { mutatingID = nil }
    let nextState = item.isPaused ? "R" : "S"
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", "status", String(item.id)],
        method: .put,
        query: [URLQueryItem(name: "state", value: nextState)])
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      if let index = items.firstIndex(where: { $0.id == item.id }) {
        items[index].state = nextState
        NativePageDataCache.shared.set(items, for: "subscriptions|list", session: session)
      }
      feedback = NativeSubscribeFeedback(
        isError: false, message: nextState == "S" ? "已暂停订阅。" : "已恢复订阅。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeSubscribeFeedback(isError: true, message: "更新订阅状态失败，请稍后重试。")
    }
  }

  /// 二次确认后单次删除订阅（`DELETE /api/v1/subscribe/{id}`）。
  private func deleteSubscribe(_ item: NativeSubscribeItem) async {
    mutatingID = item.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", String(item.id)], method: .delete)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      items.removeAll { $0.id == item.id }
      NativePageDataCache.shared.set(items, for: "subscriptions|list", session: session)
      feedback = NativeSubscribeFeedback(isError: false, message: "已取消订阅。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeSubscribeFeedback(isError: true, message: "取消订阅失败，请稍后重试。")
    }
  }
}

/// 订阅操作结果提示。
private struct NativeSubscribeFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/subscribe/` 单条订阅投影。
private struct NativeSubscribeItem: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let year: String?
  let type: String?
  let musicType: String?
  let season: Int?
  let poster: String?
  let mediaSource: String?
  let mediaID: String?
  var state: String?
  let vote: Double?
  let totalEpisode: Int?
  let startEpisode: Int?
  let lackEpisode: Int?
  let completedEpisode: Int?
  let note: [Int]?
  let bestVersion: Int?
  let bestVersionFull: Int?
  let currentPriority: Int?
  let episodePriority: [String: Int]?
  let totalTracks: Int?
  let completedTracks: Int?

  /// 标题附带季号（供搜索过滤与编辑弹窗标题使用）。
  var displayTitle: String {
    if let seasonTag {
      return "\(name) \(seasonTag)"
    }
    return name
  }

  /// 电视剧季号标签（如 `S01`）。
  var seasonTag: String? {
    guard type == "电视剧", let season else { return nil }
    return "S\(String(format: "%02d", season))"
  }

  /// `S` 表示暂停。
  var isPaused: Bool { (state ?? "R").uppercased() == "S" }

  /// 剧集与音乐专辑的离散胶片刻度投影。
  var progressProjection: SubscribeProgressProjection? {
    SubscribeProgressProjection.make(
      type: type,
      musicType: musicType,
      totalEpisode: totalEpisode,
      startEpisode: startEpisode,
      lackEpisode: lackEpisode,
      completedEpisode: completedEpisode,
      note: note,
      bestVersion: bestVersion,
      bestVersionFull: bestVersionFull,
      currentPriority: currentPriority,
      episodePriority: episodePriority,
      totalTracks: totalTracks,
      completedTracks: completedTracks
    )
  }

  /// 具备规范影视身份时允许直接进入原生详情页。
  var detailIdentity: NativeMediaIdentity? {
    guard let type, ["电影", "电视剧"].contains(type),
      let source = mediaSource, !source.isEmpty,
      let mediaID, !mediaID.isEmpty
    else { return nil }
    return NativeMediaIdentity(
      source: source,
      mediaID: mediaID,
      type: type,
      seedTitle: name,
      seedPoster: poster
    )
  }

  /// 容错解码后端扩展字段（如历史字符串型 `note` 或不同版本缺失字段）。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    year = try? container.decodeIfPresent(String.self, forKey: .year)
    type = try? container.decodeIfPresent(String.self, forKey: .type)
    musicType = try? container.decodeIfPresent(String.self, forKey: .musicType)
    season = try? container.decodeIfPresent(Int.self, forKey: .season)
    poster = try? container.decodeIfPresent(String.self, forKey: .poster)
    mediaSource = try? container.decodeIfPresent(String.self, forKey: .mediaSource)
    mediaID = try? container.decodeIfPresent(String.self, forKey: .mediaID)
    state = try? container.decodeIfPresent(String.self, forKey: .state)
    vote = try? container.decodeIfPresent(Double.self, forKey: .vote)
    totalEpisode = try? container.decodeIfPresent(Int.self, forKey: .totalEpisode)
    startEpisode = try? container.decodeIfPresent(Int.self, forKey: .startEpisode)
    lackEpisode = try? container.decodeIfPresent(Int.self, forKey: .lackEpisode)
    completedEpisode = try? container.decodeIfPresent(Int.self, forKey: .completedEpisode)
    note = try? container.decodeIfPresent([Int].self, forKey: .note)
    bestVersion = try? container.decodeIfPresent(Int.self, forKey: .bestVersion)
    bestVersionFull = try? container.decodeIfPresent(Int.self, forKey: .bestVersionFull)
    currentPriority = try? container.decodeIfPresent(Int.self, forKey: .currentPriority)
    episodePriority = try? container.decodeIfPresent([String: Int].self, forKey: .episodePriority)
    totalTracks = try? container.decodeIfPresent(Int.self, forKey: .totalTracks)
    completedTracks = try? container.decodeIfPresent(Int.self, forKey: .completedTracks)
  }

  /// 对应 `_SchemaSubscribe` 字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case year
    case type
    case musicType = "music_type"
    case season
    case poster
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case state
    case vote
    case totalEpisode = "total_episode"
    case startEpisode = "start_episode"
    case lackEpisode = "lack_episode"
    case completedEpisode = "completed_episode"
    case note
    case bestVersion = "best_version"
    case bestVersionFull = "best_version_full"
    case currentPriority = "current_priority"
    case episodePriority = "episode_priority"
    case totalTracks = "total_tracks"
    case completedTracks = "completed_tracks"
  }
}

// MARK: - 原生「订阅历史」页面

/// 原生「订阅历史」页面：对齐 Web `SubscribeHistoryDialog`，按「电影 / 电视剧 / 音乐」分页浏览已完成订阅记录，支持查看详情、重新订阅与删除记录。
@MainActor
struct NativeSubscribeHistoryPage: View {
  /// 后端 `GET /api/v1/subscribe/history/{mtype}` 支持的媒体类型分类。
  enum MediaType: String, CaseIterable, Identifiable, Hashable {
    case movie = "电影"
    case tv = "电视剧"
    case music = "音乐"

    var id: String { rawValue }
  }

  let session: NativeSession
  let onReSubscribed: (() -> Void)?

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var containerWidth: CGFloat = 0
  @State private var selectedType: MediaType
  @State private var items: [NativeSubscribeHistoryItem] = []
  @State private var currentPage = 1
  @State private var hasMore = false
  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var loadGeneration = 0
  @State private var reSubscribingID: Int?
  @State private var deletingID: Int?
  @State private var pendingDelete: NativeSubscribeHistoryItem?
  @State private var detailDestination: NativeMediaIdentity?
  @State private var feedback: NativeSubscribeFeedback?

  private let pageSize = 30

  init(
    session: NativeSession,
    initialType: MediaType = .movie,
    onReSubscribed: (() -> Void)? = nil
  ) {
    self.session = session
    self.onReSubscribed = onReSubscribed
    _selectedType = State(initialValue: initialType)
  }

  var body: some View {
    let resolvedWidth = NativeDeviceLayout.resolvedContainerWidth(containerWidth)
    let margin = NativeDeviceLayout.horizontalMargin(for: resolvedWidth)
    let columnCount = NativeDeviceLayout.cardGridCount(
      for: resolvedWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          typeSwitcher
          if let feedback {
            historyFeedbackBanner(feedback)
          }
          if isLoading && items.isEmpty {
            NativeSubscriptionsHubSkeletonView(
              columns: columnCount,
              includesOverviewHeader: false
            )
            .transition(.opacity)
          } else if loadFailed && items.isEmpty {
            failureCard
          } else if items.isEmpty {
            emptyCard
          } else {
            let gridColumns = Array(
              repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
            LazyVGrid(columns: gridColumns, spacing: 12) {
              ForEach(items) { item in
                historyCard(item)
                  .onAppear {
                    if item.id == items.last?.id {
                      Task { await loadMoreIfNeeded() }
                    }
                  }
              }
            }
            if isLoadingMore {
              HStack {
                Spacer()
                ProgressView()
                  .controlSize(.small)
                  .padding(.vertical, 8)
                Spacer()
              }
            }
          }
        }
        .frame(maxWidth: resolvedWidth >= 740 ? 1180 : 860, alignment: .leading)
        .padding(.horizontal, margin)
        .padding(.top, 8)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await reloadFromFirstPage() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-subscribe-history-scroll")
    }
    .nativeTrackContainerWidth($containerWidth)
    .navigationTitle(L10n.text("订阅历史"))
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .task(id: "\(selectedType.rawValue)|\(reloadToken)") {
      await reloadFromFirstPage()
    }
    .navigationDestination(
      isPresented: Binding(
        get: { detailDestination != nil },
        set: { if !$0 { detailDestination = nil } }
      )
    ) {
      if let identity = detailDestination {
        NativeMediaDetailPage(session: session, identity: identity)
      }
    }
    .alert(
      L10n.text("删除订阅历史"),
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { item in
      Button(L10n.text("删除"), role: .destructive) {
        Task { await deleteHistoryItem(item) }
      }
      Button(L10n.text("取消"), role: .cancel) {}
    } message: { item in
      Text("确认删除「\(item.displayTitle)」的订阅历史记录吗？")
    }
  }

  /// 顶部媒体类型胶囊切换栏（电影 / 电视剧 / 音乐）。
  private var typeSwitcher: some View {
    HStack(spacing: 8) {
      ForEach(MediaType.allCases) { option in
        let selected = selectedType == option
        Button {
          guard selectedType != option else { return }
          withAnimation(.easeOut(duration: 0.18)) {
            selectedType = option
          }
        } label: {
          Text(L10n.text(option.rawValue))
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(.primary.opacity(selected ? 0.98 : 0.78))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
              Capsule()
                .fill(
                  selected
                    ? appearance.accentColor.opacity(colorScheme == .light ? 0.16 : 0.24)
                    : NativeTheme.chipFill
                )
                .overlay {
                  Capsule()
                    .strokeBorder(
                      selected ? appearance.accentColor.opacity(0.45) : NativeTheme.chipBorder,
                      lineWidth: 0.7
                    )
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityIdentifier("native-subscribe-history-tab-\(option.rawValue)")
      }
    }
  }

  /// 单条订阅历史卡片：海报（音乐 1:1 / 影视 2:3）、标题与季号、完成时间、简介及「重新订阅 / 删除」动作。
  private func historyCard(_ item: NativeSubscribeHistoryItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.poster, source: item.mediaSource ?? "themoviedb")
    let isReSubscribing = reSubscribingID == item.id
    let isDeleting = deletingID == item.id
    let isBusy = reSubscribingID != nil || deletingID != nil

    return CinematicPanel(padding: 13) {
      HStack(alignment: .top, spacing: 13) {
        historyArtwork(poster, isMusic: item.isMusic, vote: item.vote)

        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.name)
              .font(.headline)
              .foregroundStyle(.primary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)

            if let seasonLabel = item.seasonLabel {
              NativeAdaptiveBadge(seasonLabel, tint: appearance.accentColor)
            }
            Spacer(minLength: 0)
          }

          let metaLine = item.metadataSummary
          if !metaLine.isEmpty {
            Text(metaLine)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          if let desc = item.description?.trimmingCharacters(in: .whitespacesAndNewlines),
            !desc.isEmpty
          {
            Text(desc)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }

          HStack(spacing: 8) {
            Button {
              Task { await reSubscribe(item) }
            } label: {
              HStack(spacing: 5) {
                if isReSubscribing {
                  ProgressView().controlSize(.mini).tint(.primary)
                } else {
                  Image(systemName: "arrow.clockwise")
                    .font(.caption2.weight(.semibold))
                }
                Text(L10n.text("重新订阅"))
                  .font(.caption.weight(.semibold))
                  .lineLimit(1)
              }
              .foregroundStyle(.primary.opacity(0.94))
              .padding(.horizontal, 12)
              .frame(minHeight: 34)
              .background {
                Capsule()
                  .fill(appearance.accentColor.opacity(colorScheme == .light ? 0.16 : 0.22))
                  .overlay {
                    Capsule()
                      .strokeBorder(appearance.accentColor.opacity(0.42), lineWidth: 0.65)
                  }
              }
              .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .disabled(isBusy)
            .accessibilityLabel("\(L10n.text("重新订阅")) \(item.displayTitle)")
            .accessibilityIdentifier("native-subscribe-history-resubscribe-\(item.id)")

            Spacer(minLength: 4)

            if isDeleting {
              ProgressView()
                .controlSize(.small)
                .tint(NativeTheme.danger)
            }
          }
          .padding(.top, 2)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .onTapGesture {
        if let identity = item.detailIdentity {
          detailDestination = identity
        }
      }
    }
    .contextMenu {
      Button {
        Task { await reSubscribe(item) }
      } label: {
        Label(L10n.text("重新订阅"), systemImage: "arrow.clockwise")
      }
      .disabled(isBusy)

      Button(role: .destructive) {
        pendingDelete = item
      } label: {
        Label(L10n.text("删除订阅历史"), systemImage: "trash")
      }
      .disabled(isBusy)
    }
    .accessibilityIdentifier("native-subscribe-history-card-\(item.id)")
  }

  /// 历史封面（音乐 68×68pt 正方形，电影/电视剧 68×102pt 竖版海报）。
  private func historyArtwork(_ reference: String?, isMusic: Bool, vote: Double?) -> some View {
    let width: CGFloat = 68
    let height: CGFloat = isMusic ? 68 : 102
    let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
    return NativeMediaArtwork(
      session: session, reference: reference, role: .poster, maximumWidth: 360
    )
    .frame(width: width, height: height)
    .clipShape(shape)
    .overlay {
      shape.strokeBorder(.primary.opacity(0.14), lineWidth: 0.6)
    }
    .overlay(alignment: .bottomLeading) {
      if let vote, vote > 0 {
        HStack(spacing: 2) {
          Image(systemName: "star.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.yellow)
          Text(String(format: "%.1f", vote))
            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background { Capsule().fill(.black.opacity(0.68)) }
        .padding(4)
      }
    }
  }

  private func historyFeedbackBanner(_ feedback: NativeSubscribeFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError
            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : NativeTheme.success)
        Text(feedback.message)
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.65))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("关闭"))
      }
    }
    .accessibilityIdentifier("native-subscribe-history-feedback")
  }

  private var emptyCard: some View {
    CinematicPanel(padding: 28) {
      VStack(spacing: 12) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.system(size: 32, weight: .medium))
          .foregroundStyle(.secondary)
        Text(L10n.text("没有已完成的订阅"))
          .font(.headline)
          .foregroundStyle(.primary)
        Text(L10n.text("完成的订阅会显示在这里"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, minHeight: 170)
    }
    .accessibilityIdentifier("native-subscribe-history-empty")
  }

  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入订阅历史", systemImage: "exclamationmark.triangle")
          .font(.headline)
        Button(L10n.text("重试")) { reloadToken += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-subscribe-history-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - 订阅历史 API 请求

  private func reloadFromFirstPage() async {
    loadGeneration += 1
    let generation = loadGeneration
    let targetType = selectedType
    isLoading = true
    isLoadingMore = false
    loadFailed = false
    currentPage = 1
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", "history", targetType.rawValue],
        query: [
          URLQueryItem(name: "page", value: "1"),
          URLQueryItem(name: "count", value: String(pageSize)),
        ]
      )
      let result = try await session.request(
        endpoint,
        as: [NativeSubscribeHistoryItem].self,
        requiring: .init(category: .subscribe)
      )
      try Task.checkCancellation()
      guard generation == loadGeneration else { return }
      items = result.value
      currentPage = 2
      if let total = result.collection.totalCount {
        hasMore = items.count < total && !result.value.isEmpty
      } else {
        hasMore = result.value.count >= pageSize
      }
      isLoading = false
    } catch is CancellationError {
      return
    } catch {
      guard generation == loadGeneration else { return }
      items = []
      hasMore = false
      loadFailed = true
      isLoading = false
    }
  }

  private func loadMoreIfNeeded() async {
    guard hasMore, !isLoading, !isLoadingMore else { return }
    let generation = loadGeneration
    let targetType = selectedType
    let nextPage = currentPage
    isLoadingMore = true
    defer {
      if generation == loadGeneration { isLoadingMore = false }
    }
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", "history", targetType.rawValue],
        query: [
          URLQueryItem(name: "page", value: String(nextPage)),
          URLQueryItem(name: "count", value: String(pageSize)),
        ]
      )
      let result = try await session.request(
        endpoint,
        as: [NativeSubscribeHistoryItem].self,
        requiring: .init(category: .subscribe)
      )
      try Task.checkCancellation()
      guard generation == loadGeneration else { return }
      if result.value.isEmpty {
        hasMore = false
        return
      }
      let existingIDs = Set(items.map(\.id))
      let appended = result.value.filter { !existingIDs.contains($0.id) }
      items.append(contentsOf: appended)
      currentPage = nextPage + 1
      if let total = result.collection.totalCount {
        hasMore = items.count < total && !appended.isEmpty
      } else {
        hasMore = result.value.count >= pageSize
      }
    } catch {
      // 加载下一页失败时保留已展示数据，上滑或下拉可继续重试。
    }
  }

  /// 对齐 Web `reSubscribe`：将历史订阅配置提交至 `POST /api/v1/subscribe/`。
  private func reSubscribe(_ item: NativeSubscribeHistoryItem) async {
    reSubscribingID = item.id
    defer { reSubscribingID = nil }
    do {
      let payload = item.reSubscribeWritePayload(fallbackType: selectedType.rawValue)
      let body = try JSONSerialization.data(withJSONObject: payload)
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      NativePageDataCache.shared.remove("subscriptions|list", session: session)
      onReSubscribed?()
      feedback = NativeSubscribeFeedback(
        isError: false, message: "已重新订阅「\(item.displayTitle)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeSubscribeFeedback(
        isError: true, message: "重新订阅失败，请稍后重试。")
    }
  }

  /// 删除单条订阅历史（`DELETE /api/v1/subscribe/history/{history_id}`）。
  private func deleteHistoryItem(_ item: NativeSubscribeHistoryItem) async {
    deletingID = item.id
    defer { deletingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", "history", String(item.id)], method: .delete)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      items.removeAll { $0.id == item.id }
      loadGeneration += 1
      currentPage = (items.count / pageSize) + 1
      feedback = NativeSubscribeFeedback(
        isError: false, message: "已删除「\(item.displayTitle)」的订阅历史记录。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeSubscribeFeedback(
        isError: true, message: "删除订阅历史失败，请稍后重试。")
    }
  }
}

/// `GET /api/v1/subscribe/history/{mtype}` 单条订阅历史模型（保留重订阅所需规则字段）。
private struct NativeSubscribeHistoryItem: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let year: String?
  let type: String?
  let musicType: String?
  let totalTracks: Int?
  let season: Int?
  let poster: String?
  let vote: Double?
  let description: String?
  let date: String?
  let mediaSource: String?
  let mediaID: String?
  let tmdbID: Int?
  let doubanID: String?
  let bangumiID: Int?
  let totalEpisode: Int?
  let startEpisode: Int?
  let quality: String?
  let resolution: String?
  let effect: String?
  let audioQuality: String?
  let audioFormat: String?
  let minBitrate: Int?
  let minBitDepth: Int?
  let minSampleRate: Int?
  let bestVersion: Int?
  let bestVersionFull: Int?
  let sites: [Int]?
  let filterGroups: [String]?
  let downloader: String?
  let savePath: String?
  let keyword: String?
  let filter: String?
  let include: String?
  let exclude: String?
  let customWords: String?
  let episodeGroup: String?
  let mediaCategory: String?
  let mediaCategoryID: String?
  let searchImdbID: Int?
  let searchInterval: Int?

  var isMusic: Bool { type == "音乐" }

  var seasonLabel: String? {
    guard type == "电视剧", let season, season > 0 else { return nil }
    return "第 \(season) 季"
  }

  var displayTitle: String {
    if let seasonLabel {
      return "\(name) \(seasonLabel)"
    }
    return name
  }

  var metadataSummary: String {
    var parts: [String] = []
    if let date = date?.trimmingCharacters(in: .whitespacesAndNewlines), !date.isEmpty {
      parts.append(date)
    }
    if let year = year?.trimmingCharacters(in: .whitespacesAndNewlines), !year.isEmpty {
      parts.append(year)
    }
    return parts.joined(separator: " · ")
  }

  var detailIdentity: NativeMediaIdentity? {
    let resolvedType = type ?? "电影"
    guard ["电影", "电视剧"].contains(resolvedType) else { return nil }
    if let source = mediaSource, !source.isEmpty, let mediaID, !mediaID.isEmpty {
      return NativeMediaIdentity(
        source: source,
        mediaID: mediaID,
        type: resolvedType,
        seedTitle: name,
        seedPoster: poster
      )
    }
    if let tmdbID, tmdbID > 0 {
      return NativeMediaIdentity(
        source: "themoviedb",
        mediaID: String(tmdbID),
        type: resolvedType,
        seedTitle: name,
        seedPoster: poster
      )
    }
    if let doubanID, !doubanID.isEmpty {
      return NativeMediaIdentity(
        source: "douban",
        mediaID: doubanID,
        type: resolvedType,
        seedTitle: name,
        seedPoster: poster
      )
    }
    return nil
  }

  /// 构造 `POST /api/v1/subscribe/` 重订阅写入字典，剔除只读运行字段并完整保留原订阅规则。
  func reSubscribeWritePayload(fallbackType: String) -> [String: Any] {
    let resolvedType =
      (type?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
        $0.isEmpty ? nil : $0
      } ?? fallbackType
    var payload: [String: Any] = [
      "name": name,
      "type": resolvedType,
    ]
    if let year = year?.trimmingCharacters(in: .whitespacesAndNewlines), !year.isEmpty {
      payload["year"] = year
    }
    if let source = mediaSource?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty,
      let mid = mediaID?.trimmingCharacters(in: .whitespacesAndNewlines), !mid.isEmpty
    {
      payload["media_source"] = source
      payload["media_id"] = mid
    } else if let tmdbID, tmdbID > 0 {
      payload["media_source"] = "themoviedb"
      payload["media_id"] = String(tmdbID)
    } else if let doubanID = doubanID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !doubanID.isEmpty
    {
      payload["media_source"] = "douban"
      payload["media_id"] = doubanID
    } else if let bangumiID, bangumiID > 0 {
      payload["media_source"] = "bangumi"
      payload["media_id"] = String(bangumiID)
    }
    if resolvedType == "电视剧", let season, season > 0 {
      payload["season"] = season
    }
    if let musicType, !musicType.isEmpty { payload["music_type"] = musicType }
    if let totalTracks, totalTracks > 0 { payload["total_tracks"] = totalTracks }
    if let totalEpisode, totalEpisode > 0 { payload["total_episode"] = totalEpisode }
    if let startEpisode, startEpisode > 0 { payload["start_episode"] = startEpisode }
    if let quality, !quality.isEmpty { payload["quality"] = quality }
    if let resolution, !resolution.isEmpty { payload["resolution"] = resolution }
    if let effect, !effect.isEmpty { payload["effect"] = effect }
    if let audioQuality, !audioQuality.isEmpty { payload["audio_quality"] = audioQuality }
    if let audioFormat, !audioFormat.isEmpty { payload["audio_format"] = audioFormat }
    if let minBitrate, minBitrate > 0 { payload["min_bitrate"] = minBitrate }
    if let minBitDepth, minBitDepth > 0 { payload["min_bit_depth"] = minBitDepth }
    if let minSampleRate, minSampleRate > 0 { payload["min_sample_rate"] = minSampleRate }
    if let bestVersion { payload["best_version"] = bestVersion }
    if let bestVersionFull { payload["best_version_full"] = bestVersionFull }
    if let sites, !sites.isEmpty { payload["sites"] = sites }
    if let filterGroups, !filterGroups.isEmpty { payload["filter_groups"] = filterGroups }
    if let downloader, !downloader.isEmpty { payload["downloader"] = downloader }
    if let savePath, !savePath.isEmpty { payload["save_path"] = savePath }
    if let keyword, !keyword.isEmpty { payload["keyword"] = keyword }
    if let filter, !filter.isEmpty { payload["filter"] = filter }
    if let include, !include.isEmpty { payload["include"] = include }
    if let exclude, !exclude.isEmpty { payload["exclude"] = exclude }
    if let customWords, !customWords.isEmpty { payload["custom_words"] = customWords }
    if let episodeGroup, !episodeGroup.isEmpty { payload["episode_group"] = episodeGroup }
    if let mediaCategory, !mediaCategory.isEmpty { payload["media_category"] = mediaCategory }
    if let mediaCategoryID, !mediaCategoryID.isEmpty {
      payload["media_category_id"] = mediaCategoryID
    }
    if let searchImdbID { payload["search_imdbid"] = searchImdbID }
    if let searchInterval, searchInterval > 0 { payload["search_interval"] = searchInterval }
    return payload
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, year, type, season, poster, vote, description, date, sites, downloader
    case quality, resolution, effect, keyword, filter, include, exclude
    case musicType = "music_type"
    case totalTracks = "total_tracks"
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdbid"
    case doubanID = "doubanid"
    case bangumiID = "bangumiid"
    case totalEpisode = "total_episode"
    case startEpisode = "start_episode"
    case audioQuality = "audio_quality"
    case audioFormat = "audio_format"
    case minBitrate = "min_bitrate"
    case minBitDepth = "min_bit_depth"
    case minSampleRate = "min_sample_rate"
    case bestVersion = "best_version"
    case bestVersionFull = "best_version_full"
    case filterGroups = "filter_groups"
    case savePath = "save_path"
    case customWords = "custom_words"
    case episodeGroup = "episode_group"
    case mediaCategory = "media_category"
    case mediaCategoryID = "media_category_id"
    case searchImdbID = "search_imdbid"
    case searchInterval = "search_interval"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(Int.self, forKey: .id)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    year = try? c.decodeIfPresent(String.self, forKey: .year)
    type = try? c.decodeIfPresent(String.self, forKey: .type)
    musicType = try? c.decodeIfPresent(String.self, forKey: .musicType)
    totalTracks = try? c.decodeIfPresent(Int.self, forKey: .totalTracks)
    season = try? c.decodeIfPresent(Int.self, forKey: .season)
    poster = try? c.decodeIfPresent(String.self, forKey: .poster)
    vote = try? c.decodeIfPresent(Double.self, forKey: .vote)
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    date = try? c.decodeIfPresent(String.self, forKey: .date)
    mediaSource = try? c.decodeIfPresent(String.self, forKey: .mediaSource)
    mediaID = try? c.decodeIfPresent(String.self, forKey: .mediaID)
    tmdbID = try? c.decodeIfPresent(Int.self, forKey: .tmdbID)
    doubanID = try? c.decodeIfPresent(String.self, forKey: .doubanID)
    bangumiID = try? c.decodeIfPresent(Int.self, forKey: .bangumiID)
    totalEpisode = try? c.decodeIfPresent(Int.self, forKey: .totalEpisode)
    startEpisode = try? c.decodeIfPresent(Int.self, forKey: .startEpisode)
    quality = try? c.decodeIfPresent(String.self, forKey: .quality)
    resolution = try? c.decodeIfPresent(String.self, forKey: .resolution)
    effect = try? c.decodeIfPresent(String.self, forKey: .effect)
    audioQuality = try? c.decodeIfPresent(String.self, forKey: .audioQuality)
    audioFormat = try? c.decodeIfPresent(String.self, forKey: .audioFormat)
    minBitrate = try? c.decodeIfPresent(Int.self, forKey: .minBitrate)
    minBitDepth = try? c.decodeIfPresent(Int.self, forKey: .minBitDepth)
    minSampleRate = try? c.decodeIfPresent(Int.self, forKey: .minSampleRate)
    bestVersion =
      (try? c.decodeIfPresent(Int.self, forKey: .bestVersion))
      ?? ((try? c.decodeIfPresent(Bool.self, forKey: .bestVersion)).map { $0 ? 1 : 0 })
    bestVersionFull =
      (try? c.decodeIfPresent(Int.self, forKey: .bestVersionFull))
      ?? ((try? c.decodeIfPresent(Bool.self, forKey: .bestVersionFull)).map { $0 ? 1 : 0 })
    sites = try? c.decodeIfPresent([Int].self, forKey: .sites)
    filterGroups = try? c.decodeIfPresent([String].self, forKey: .filterGroups)
    downloader = try? c.decodeIfPresent(String.self, forKey: .downloader)
    savePath = try? c.decodeIfPresent(String.self, forKey: .savePath)
    keyword = try? c.decodeIfPresent(String.self, forKey: .keyword)
    filter = try? c.decodeIfPresent(String.self, forKey: .filter)
    include = try? c.decodeIfPresent(String.self, forKey: .include)
    exclude = try? c.decodeIfPresent(String.self, forKey: .exclude)
    customWords = try? c.decodeIfPresent(String.self, forKey: .customWords)
    episodeGroup = try? c.decodeIfPresent(String.self, forKey: .episodeGroup)
    mediaCategory = try? c.decodeIfPresent(String.self, forKey: .mediaCategory)
    mediaCategoryID = try? c.decodeIfPresent(String.self, forKey: .mediaCategoryID)
    searchImdbID =
      (try? c.decodeIfPresent(Int.self, forKey: .searchImdbID))
      ?? ((try? c.decodeIfPresent(Bool.self, forKey: .searchImdbID)).map { $0 ? 1 : 0 })
    searchInterval = try? c.decodeIfPresent(Int.self, forKey: .searchInterval)
  }
}
