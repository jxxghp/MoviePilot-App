import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生订阅中心：分类浏览电影、电视剧与音乐订阅，支持进度展示、暂停/恢复、触发搜索与确认取消。
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

  /// 初始化订阅中心，可选按外部深链或小组件意图直接切换至电影/电视剧/音乐分类。
  init(session: NativeSession, initialFilter: Filter = .all) {
    self.session = session
    _filter = State(initialValue: initialFilter)
  }

  /// 采用统一深色紫玫瑰渐变与透色海报玻璃卡，卡片可直达原生影视详情页。
  var body: some View {
    let resolvedWidth = NativeDeviceLayout.resolvedContainerWidth(containerWidth)
    let columnCount = NativeDeviceLayout.cardGridCount(
      for: resolvedWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          filterBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && items.isEmpty {
            NativeCardListSkeletonView(
              count: columnCount * 3,
              style: .subscribeCard,
              columns: columnCount
            )
            .transition(.opacity)
          } else if loadFailed && items.isEmpty {
            failureCard
          } else if filteredItems.isEmpty {
            emptyCard
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
        .frame(maxWidth: resolvedWidth >= 740 ? 1180 : 820)
        .padding(.horizontal, NativeDeviceLayout.horizontalMargin(for: resolvedWidth))
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .refreshable { await load(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-subscriptions-scroll")
    }
    .navigationTitle("我的订阅")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .searchable(text: $searchText, prompt: "筛选订阅片名")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
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
          Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .tint(.primary)
        .accessibilityLabel("筛选与排序")
        .accessibilityIdentifier("native-subscriptions-filter-menu")

        NavigationLink {
          NativeSubscribeCommunityPage(session: session)
        } label: {
          Image(systemName: "flame.fill")
        }
        .tint(.primary)
        .accessibilityLabel("订阅广场")
        .accessibilityIdentifier("native-subscriptions-community")
      }
    }
    .task(id: attempt) { await load(forceRefresh: attempt > 0) }
    .sheet(item: $viewingFilesItem) { item in
      NativeSubscribeFilesSheet(
        session: session, subscribeID: item.id, fallbackTitle: item.displayTitle
      )
      .nativeAdaptiveSheetSizing()
    }
    .sheet(item: $editingItem) { item in
      NativeSubscribeEditorSheet(session: session, subscribeID: item.id, title: item.displayTitle) {
        feedback = NativeSubscribeFeedback(isError: false, message: "订阅规则已更新。")
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
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(Filter.allCases) { option in
          let count = countFor(option)
          let selected = filter == option
          Button {
            filter = option
          } label: {
            Text(count > 0 ? "\(option.rawValue) \(count)" : option.rawValue)
              .font(.subheadline.weight(selected ? .semibold : .regular))
              .foregroundStyle(.primary.opacity(selected ? 0.98 : 0.78))
              .padding(.horizontal, 13)
              .padding(.vertical, 7)
              .background {
                Capsule()
                  .fill(selected ? NativeTheme.brand.opacity(0.18) : NativeTheme.chipFill)
                  .overlay {
                    Capsule().strokeBorder(.primary.opacity(selected ? 0.28 : 0.14), lineWidth: 0.6)
                  }
              }
              .frame(minHeight: 38)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-subscriptions-filter-\(option.rawValue)")
        }
      }
    }
    .scrollIndicators(.hidden)
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

  /// 单条订阅透色玻璃卡片：2:3 竖版海报、状态/进度与原生上下文动作。
  private func subscribeCard(_ item: NativeSubscribeItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.poster, source: item.mediaSource ?? "themoviedb")
    let isMutating = mutatingID == item.id
    return CinematicPanel(padding: 12) {
      HStack(alignment: .top, spacing: 13) {
        Group {
          if let identity = item.detailIdentity {
            NavigationLink {
              NativeMediaDetailPage(session: session, identity: identity)
            } label: {
              posterView(poster)
            }
            .buttonStyle(.plain)
          } else {
            posterView(poster)
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 8) {
            if let identity = item.detailIdentity {
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: identity)
              } label: {
                Text(item.displayTitle)
                  .font(.headline)
                  .foregroundStyle(.primary)
                  .lineLimit(2)
                  .multilineTextAlignment(.leading)
              }
              .buttonStyle(.plain)
            } else {
              Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            }
            Spacer(minLength: 4)
            stateBadge(item)
          }
          HStack(spacing: 8) {
            if let year = item.year, !year.isEmpty {
              Text(year).font(.caption).foregroundStyle(.primary.opacity(0.66))
            }
            if let type = item.type, !type.isEmpty {
              Text(type).font(.caption).foregroundStyle(.primary.opacity(0.66))
            }
            if let vote = item.vote, vote > 0 {
              Label(String(format: "%.1f", vote), systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
            }
          }
          if let projection = item.progressProjection {
            subscribeTickStrip(projection, item: item)
              .padding(.top, 2)
          }
          HStack(spacing: 8) {
            Button {
              Task { await toggleStatus(item) }
            } label: {
              HStack(spacing: 4) {
                if isMutating {
                  ProgressView().controlSize(.mini).tint(.primary)
                } else {
                  Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption2.weight(.semibold))
                }
                Text(item.isPaused ? "恢复" : "暂停").font(.caption.weight(.semibold))
              }
              .foregroundStyle(.primary)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background {
                Capsule()
                  .fill(.primary.opacity(0.13))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6) }
              }
              .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(mutatingID != nil)
            .accessibilityIdentifier("native-subscribe-toggle-\(item.id)")

            Button {
              viewingFilesItem = item
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "doc.text.magnifyingglass")
                  .font(.caption2.weight(.semibold))
                Text("文件").font(.caption.weight(.semibold))
              }
              .foregroundStyle(.primary)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background {
                Capsule()
                  .fill(.primary.opacity(0.13))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6) }
              }
              .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看订阅文件详情")
            .accessibilityIdentifier("native-subscribe-files-\(item.id)")
            Spacer()
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
          item.isPaused ? "恢复订阅" : "暂停订阅", systemImage: item.isPaused ? "play.fill" : "pause.fill")
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

  /// 2:3 竖版海报，沿用全应用统一的 420px 内存缓存档位。
  private func posterView(_ reference: String?) -> some View {
    NativeMediaArtwork(session: session, reference: reference, role: .poster, maximumWidth: 420)
      .frame(width: 68, height: 102)
      .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
      }
  }

  /// 订阅运行状态徽标。
  private func stateBadge(_ item: NativeSubscribeItem) -> some View {
    let text = item.isPaused ? "已暂停" : (item.bestVersion == 1 ? "洗版" : "订阅中")
    let tint: Color =
      item.isPaused
      ? NativeTheme.badgeMutedText
      : (item.bestVersion == 1
        ? NativeTheme.warning
        : NativeTheme.success)
    return Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background {
        Capsule()
          .fill(.primary.opacity(0.10))
          .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.6) }
      }
  }

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

  /// 无订阅空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "bookmark")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text("暂无匹配的订阅").font(.headline)
        Text("你可以在发现页或媒体详情中一键添加订阅。")
          .font(.footnote)
          .foregroundStyle(.primary.opacity(0.65))
      }
      .frame(maxWidth: .infinity, minHeight: 150)
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

  /// 标题附带季号。
  var displayTitle: String {
    if let season, type == "电视剧" {
      return "\(name) S\(String(format: "%02d", season))"
    }
    return name
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
