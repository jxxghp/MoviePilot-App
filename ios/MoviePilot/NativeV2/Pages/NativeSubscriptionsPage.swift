import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生「订阅」旗舰主页面：顶部呈现追剧全景英雄卡、分类与状态排序过滤、离散胶片刻度进度及三键快捷操控，右上角提供追剧日历与订阅广场图标入口。
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

  /// 主体使用连续渐变底色，直接呈现我的订阅全景列表，右上角通过图标进入追剧日历与订阅广场。
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
      ToolbarItemGroup(placement: .topBarTrailing) {
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

  /// 单条订阅高质感透色玻璃卡片：`76×114pt` 2:3 海报（含角标评分）、季号胶囊、语义状态角标、离散胶片刻度与三键内联动作栏。
  private func subscribeCard(_ item: NativeSubscribeItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.poster, source: item.mediaSource ?? "themoviedb")
    let isMutating = mutatingID == item.id
    return CinematicPanel(padding: 13) {
      HStack(alignment: .top, spacing: 13) {
        Group {
          if let identity = item.detailIdentity {
            NavigationLink {
              NativeMediaDetailPage(session: session, identity: identity)
            } label: {
              posterView(poster, vote: item.vote)
            }
            .buttonStyle(.plain)
          } else {
            posterView(poster, vote: item.vote)
          }
        }

        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              if let identity = item.detailIdentity {
                NavigationLink {
                  NativeMediaDetailPage(session: session, identity: identity)
                } label: {
                  Text(item.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
              } else {
                Text(item.name)
                  .font(.headline)
                  .foregroundStyle(.primary)
                  .lineLimit(2)
              }

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
    .contextMenu {
      Button {
        viewingFilesItem = item
      } label: {
        Label("文件详情", systemImage: "doc.text.magnifyingglass")
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

  /// 订阅卡片底部统一 34pt 胶囊操作按钮。
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
          .font(.caption.weight(.semibold))
          .lineLimit(1)
      }
      .foregroundStyle(.primary.opacity(0.92))
      .padding(.horizontal, 10)
      .frame(minHeight: 34)
      .background {
        Capsule()
          .fill(NativeTheme.chipFill)
          .overlay {
            Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.65)
          }
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
