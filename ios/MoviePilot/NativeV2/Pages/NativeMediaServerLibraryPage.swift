import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 媒体服务器客户端简要信息（对应 `GET /api/v1/mediaserver/clients`）。
private struct MediaServerClientSummary: Decodable, Identifiable, Hashable, Sendable {
  let name: String
  let type: String?

  var id: String { name }
}

/// 媒体服务器媒体库摘要（对应 `GET /api/v1/mediaserver/library`）。
private struct MediaServerLibrarySummary: Decodable, Identifiable, Hashable, Sendable {
  let idScalar: MediaServerFlexibleScalar?
  let itemIDScalar: MediaServerFlexibleScalar?
  let name: String?
  let type: String?
  let itemCount: Int?
  let link: String?
  let serverID: String?
  let serverType: String?

  private enum CodingKeys: String, CodingKey {
    case name, type, link
    case idScalar = "id"
    case itemIDScalar = "item_id"
    case itemCount = "item_count"
    case serverID = "server_id"
    case serverType = "server_type"
  }

  var libraryID: String { itemIDScalar?.value ?? idScalar?.value ?? "" }
  var displayName: String { name?.isEmpty == false ? name! : "媒体库" }
  var id: String { "\(libraryID):\(displayName)" }
}

/// 原生媒体服务器浏览页：与探索页视觉语言一致，支持多服务器/媒体库切换、关键词搜索、排序、风格/年份/观看状态筛选及分页网格。
@MainActor
struct NativeMediaServerLibraryPage: View {
  let session: NativeSession
  let initialServer: String
  let initialServerType: String?
  let initialLibraryID: String?
  let initialLibraryName: String
  let initialLibraryType: String?
  let externalLink: String?
  let serverID: String?

  @State private var activeServer: String
  @State private var activeServerType: String?
  @State private var activeLibraryID: String?
  @State private var activeLibraryName: String
  @State private var activeLibraryType: String?

  @State private var servers: [MediaServerClientSummary] = []
  @State private var libraries: [MediaServerLibrarySummary] = []
  @State private var filterOptions = MediaServerFilterOptionsDTO()

  @State private var selectedSort: MediaServerBrowseSort = .dateCreated
  @State private var sortOrder: String = MediaServerBrowseSort.dateCreated.defaultOrder
  @State private var selectedGenre: String = ""
  @State private var selectedYear: Int?
  @State private var playedFilter: MediaServerPlayedFilter = .all
  @State private var searchText: String = ""
  @State private var committedSearch: String = ""

  @State private var items: [MediaServerBrowseItemDTO] = []
  @State private var totalCount: Int = 0
  @State private var hasMore: Bool = false
  @State private var isLoading: Bool = true
  @State private var isLoadingMore: Bool = false
  @State private var loadFailed: Bool = false
  @State private var queryGeneration = UUID()
  @State private var searchDebounceTask: Task<Void, Never>?
  @State private var containerWidth: CGFloat = 0

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  private let pageSize = 30

  init(
    session: NativeSession,
    server: String,
    serverType: String? = nil,
    libraryID: String? = nil,
    libraryName: String,
    libraryType: String? = nil,
    externalLink: String? = nil,
    serverID: String? = nil
  ) {
    self.session = session
    self.initialServer = server
    self.initialServerType = serverType
    self.initialLibraryID = libraryID
    self.initialLibraryName = libraryName
    self.initialLibraryType = libraryType
    self.externalLink = externalLink
    self.serverID = serverID
    _activeServer = State(initialValue: server)
    _activeServerType = State(initialValue: serverType)
    _activeLibraryID = State(initialValue: libraryID)
    _activeLibraryName = State(initialValue: libraryName)
    _activeLibraryType = State(initialValue: libraryType)
  }

  private var isMusicLibrary: Bool {
    let lower = (activeLibraryType ?? "").lowercased()
    return lower == "音乐" || lower == "music" || activeServerType?.lowercased() == "navidrome"
  }

  private var hasActiveFilter: Bool {
    !selectedGenre.isEmpty || selectedYear != nil || playedFilter != .all
      || !committedSearch.isEmpty
  }

  private var gridColumns: [GridItem] {
    let count =
      containerWidth > 0
      ? NativeDeviceLayout.posterGridCount(
        for: min(containerWidth, 1240), isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
      : (horizontalSizeClass == .regular ? 5 : 3)
    return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
  }

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if servers.count > 1 || libraries.count > 1 {
            librarySwitcherBar
          }
          filterControlsBar
          summaryHeader
          contentBody
        }
        .padding(.vertical, 12)
        .frame(maxWidth: 1240, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .refreshable {
        await loadFilters()
        await reloadItems()
      }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-mediaserver-library-scroll")
    }
    .navigationTitle(activeLibraryName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .automatic),
      prompt: "搜索「\(activeLibraryName)」"
    )
    .onSubmit(of: .search) {
      searchDebounceTask?.cancel()
      committedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      Task { await reloadItems() }
    }
    .onChange(of: searchText) { newValue in
      searchDebounceTask?.cancel()
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed == committedSearch { return }
      searchDebounceTask = Task {
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        committedSearch = trimmed
        await reloadItems()
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button {
            Task {
              await loadFilters()
              await reloadItems()
            }
          } label: {
            Label("刷新内容", systemImage: "arrow.clockwise")
          }
          if let externalLink, let url = URL(string: externalLink) {
            Button {
              UIApplication.shared.open(url)
            } label: {
              Label("在外部媒体服务器打开", systemImage: "arrow.up.right.square")
            }
          }
        } label: {
          Image(systemName: "ellipsis")
        }
        .tint(.primary)
        .accessibilityLabel("媒体库菜单")
        .accessibilityIdentifier("native-mediaserver-library-menu")
      }
    }
    .task {
      async let metaTask: Void = loadServersAndLibraries()
      async let filtersTask: Void = loadFilters()
      async let itemsTask: Void = reloadItems()
      _ = await (metaTask, filtersTask, itemsTask)
    }
  }

  /// 多媒体服务器与同服务器多媒体库横向切换胶囊栏。
  private var librarySwitcherBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        if servers.count > 1 {
          Menu {
            ForEach(servers) { client in
              Button {
                guard client.name != activeServer else { return }
                activeServer = client.name
                activeServerType = client.type
                activeLibraryID = nil
                activeLibraryName = client.name
                activeLibraryType = nil
                resetFiltersForSwitch()
                Task {
                  await loadLibrariesForActiveServer(selectFirstIfMissing: true)
                  await loadFilters()
                  await reloadItems()
                }
              } label: {
                if client.name == activeServer {
                  Label(client.name, systemImage: "checkmark")
                } else {
                  Text(client.name)
                }
              }
            }
          } label: {
            filterChipLabel(
              title: activeServer,
              symbol: "server.rack",
              isActive: true
            )
          }
          .accessibilityIdentifier("native-mediaserver-server-switcher")
        }

        ForEach(libraries) { lib in
          let selected = activeLibraryID == lib.libraryID && !lib.libraryID.isEmpty
          Button {
            guard activeLibraryID != lib.libraryID else { return }
            activeLibraryID = lib.libraryID
            activeLibraryName = lib.displayName
            activeLibraryType = lib.type
            resetFiltersForSwitch()
            Task {
              await loadFilters()
              await reloadItems()
            }
          } label: {
            filterChipLabel(
              title: lib.displayName,
              symbol: nil,
              isActive: selected
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-mediaserver-lib-chip-\(lib.libraryID)")
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
    }
    .scrollIndicators(.hidden)
  }

  /// 探索风筛选与排序横向控制栏（排序、升降序、观看状态、风格、年份、清除）。
  private var filterControlsBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        Menu {
          ForEach(availableSorts) { sort in
            Button {
              if selectedSort == sort {
                sortOrder = sortOrder == "desc" ? "asc" : "desc"
              } else {
                selectedSort = sort
                sortOrder = sort.defaultOrder
              }
              Task { await reloadItems() }
            } label: {
              if selectedSort == sort {
                Label(
                  "\(sort.title)（\(sortOrder == "asc" ? "升序" : "降序")）",
                  systemImage: "checkmark"
                )
              } else {
                Text(sort.title)
              }
            }
          }
        } label: {
          filterChipLabel(
            title: selectedSort.title,
            symbol: sortOrder == "asc" ? "arrow.up" : "arrow.down",
            isActive: selectedSort != .dateCreated || sortOrder != "desc"
          )
        }
        .accessibilityIdentifier("native-mediaserver-filter-sort")

        Menu {
          ForEach(MediaServerPlayedFilter.allCases) { state in
            Button {
              playedFilter = state
              Task { await reloadItems() }
            } label: {
              if playedFilter == state {
                Label(state.title, systemImage: "checkmark")
              } else {
                Text(state.title)
              }
            }
          }
        } label: {
          filterChipLabel(
            title: playedFilter == .all ? "状态" : playedFilter.title,
            symbol: "eye",
            isActive: playedFilter != .all
          )
        }
        .accessibilityIdentifier("native-mediaserver-filter-played")

        if !filterOptions.genres.isEmpty {
          Menu {
            Button {
              selectedGenre = ""
              Task { await reloadItems() }
            } label: {
              if selectedGenre.isEmpty {
                Label("全部风格", systemImage: "checkmark")
              } else {
                Text("全部风格")
              }
            }
            ForEach(filterOptions.genres, id: \.self) { genre in
              Button {
                selectedGenre = genre
                Task { await reloadItems() }
              } label: {
                if selectedGenre == genre {
                  Label(genre, systemImage: "checkmark")
                } else {
                  Text(genre)
                }
              }
            }
          } label: {
            filterChipLabel(
              title: selectedGenre.isEmpty ? "风格" : selectedGenre,
              symbol: "tag",
              isActive: !selectedGenre.isEmpty
            )
          }
          .accessibilityIdentifier("native-mediaserver-filter-genre")
        }

        if !filterOptions.years.isEmpty {
          Menu {
            Button {
              selectedYear = nil
              Task { await reloadItems() }
            } label: {
              if selectedYear == nil {
                Label("全部年份", systemImage: "checkmark")
              } else {
                Text("全部年份")
              }
            }
            ForEach(filterOptions.years.prefix(40), id: \.self) { year in
              Button {
                selectedYear = year
                Task { await reloadItems() }
              } label: {
                if selectedYear == year {
                  Label(String(year), systemImage: "checkmark")
                } else {
                  Text(String(year))
                }
              }
            }
          } label: {
            filterChipLabel(
              title: selectedYear.map(String.init) ?? "年份",
              symbol: "calendar",
              isActive: selectedYear != nil
            )
          }
          .accessibilityIdentifier("native-mediaserver-filter-year")
        }

        if hasActiveFilter {
          Button {
            selectedGenre = ""
            selectedYear = nil
            playedFilter = .all
            searchText = ""
            committedSearch = ""
            Task { await reloadItems() }
          } label: {
            filterChipLabel(title: "重置", symbol: "xmark.circle", isActive: false)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-mediaserver-filter-reset")
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
    }
    .scrollIndicators(.hidden)
  }

  /// 当前筛选结果数量与来源服务器提示行。
  private var summaryHeader: some View {
    HStack {
      Text(totalCount > 0 ? "共 \(totalCount) 项 · \(activeServer)" : activeServer)
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary.opacity(0.62))
      Spacer(minLength: 0)
      if !committedSearch.isEmpty {
        Text("搜索：\(committedSearch)")
          .font(.caption.weight(.medium))
          .foregroundStyle(appearance.accentColor)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, CinematicStyle.margin)
  }

  /// 网格主内容区域（骨架 / 失败 / 空态 / 分页网格）。
  @ViewBuilder
  private var contentBody: some View {
    if isLoading && items.isEmpty {
      NativePosterGridSkeletonView(columns: 3, count: 9)
        .padding(.horizontal, CinematicStyle.margin)
    } else if loadFailed && items.isEmpty {
      CinematicPanel {
        VStack(spacing: 12) {
          Image(systemName: "wifi.exclamationmark")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("无法读取媒体库内容")
            .font(.headline)
          Text("请确认媒体服务器在线并检查连接设置。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("重试") {
            Task { await reloadItems() }
          }
          .buttonStyle(.borderedProminent)
          .tint(appearance.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      }
      .padding(.horizontal, CinematicStyle.margin)
    } else if items.isEmpty {
      CinematicPanel {
        VStack(spacing: 10) {
          Image(systemName: "film.stack")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text(hasActiveFilter ? "当前筛选条件下没有匹配内容" : "媒体库暂无内容")
            .font(.headline)
          if hasActiveFilter {
            Button("清除筛选") {
              selectedGenre = ""
              selectedYear = nil
              playedFilter = .all
              searchText = ""
              committedSearch = ""
              Task { await reloadItems() }
            }
            .buttonStyle(.bordered)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
      .padding(.horizontal, CinematicStyle.margin)
    } else {
      LazyVGrid(columns: gridColumns, spacing: 16) {
        ForEach(items) { item in
          NavigationLink {
            NativeMediaServerDetailPage(
              session: session,
              server: item.server ?? activeServer,
              itemID: item.itemId,
              fallbackTitle: item.title,
              fallbackItemType: item.itemType,
              fallbackPoster: item.poster ?? item.thumb
            )
          } label: {
            browseCard(item)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-mediaserver-item-\(item.itemId)")
          .onAppear {
            if item.id == items.last?.id, hasMore, !isLoadingMore {
              Task { await loadNextPage() }
            }
          }
        }
      }
      .padding(.horizontal, CinematicStyle.margin)

      if isLoadingMore {
        ProgressView()
          .tint(.primary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
      }
    }
  }

  /// 单张媒体库浏览卡片（与探索页海报卡片风格保持一致，叠加评分、已看徽章与观看进度条）。
  private func browseCard(_ item: MediaServerBrowseItemDTO) -> some View {
    let aspectRatio: CGFloat =
      isMusicLibrary || item.kind == .musicAlbum || item.kind == .audio ? 1.0 : (2.0 / 3.0)
    return VStack(alignment: .leading, spacing: 6) {
      Color.clear
        .aspectRatio(aspectRatio, contentMode: .fit)
        .overlay {
          ZStack(alignment: .bottom) {
            NativeMediaArtwork(
              session: session,
              reference: item.poster ?? item.thumb ?? item.backdrop,
              role: .poster,
              maximumWidth: 360
            )

            if let progress = item.progressFraction, progress > 0.01, item.played != true {
              GeometryReader { bar in
                ZStack(alignment: .leading) {
                  Capsule().fill(.black.opacity(0.45))
                  Capsule()
                    .fill(appearance.accentColor)
                    .frame(width: max(6, bar.size.width * progress))
                }
              }
              .frame(height: 3.5)
              .padding(.horizontal, 6)
              .padding(.bottom, 6)
            }
          }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) {
          if item.kind == .boxSet {
            Text("合集")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 2.5)
              .background(appearance.accentColor.opacity(0.88), in: Capsule())
              .padding(6)
          }
        }
        .overlay(alignment: .topTrailing) {
          if item.played == true {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white, NativeTheme.success)
              .padding(6)
          } else if let rating = item.rating, rating > 0 {
            Text(String(format: "%.1f", rating))
              .font(.caption2.weight(.bold).monospacedDigit())
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 2.5)
              .background(.black.opacity(0.62), in: Capsule())
              .padding(6)
          }
        }
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(colorScheme == .light ? 0.20 : 0.12), lineWidth: 0.6)
        }

      Text(item.title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

      if let sub = cardSubtitle(item) {
        Text(sub)
          .font(.caption2)
          .foregroundStyle(.primary.opacity(0.60))
          .lineLimit(1)
      }

      Spacer(minLength: 0)
    }
  }

  private func cardSubtitle(_ item: MediaServerBrowseItemDTO) -> String? {
    var parts: [String] = []
    if let year = item.yearText, !year.isEmpty { parts.append(year) }
    if let subtitle = item.subtitle, !subtitle.isEmpty, subtitle != item.yearText {
      parts.append(subtitle)
    } else if item.kind == .boxSet, let count = item.childCount, count > 0 {
      parts.append("共 \(count) 部")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private func filterChipLabel(title: String, symbol: String?, isActive: Bool) -> some View {
    HStack(spacing: 5) {
      if let symbol {
        Image(systemName: symbol)
          .font(.caption2.weight(.semibold))
      }
      Text(title)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(isActive ? .white : .primary.opacity(0.86))
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background {
      Capsule()
        .fill(
          isActive
            ? appearance.accentColor
            : .primary.opacity(colorScheme == .light ? 0.08 : 0.12)
        )
        .overlay {
          Capsule().strokeBorder(
            isActive ? .clear : .primary.opacity(0.16),
            lineWidth: 0.6
          )
        }
    }
  }

  private var availableSorts: [MediaServerBrowseSort] {
    let supported = filterOptions.sortOptions.compactMap(MediaServerBrowseSort.init(rawValue:))
    return supported.isEmpty ? MediaServerBrowseSort.allCases : supported
  }

  private func resetFiltersForSwitch() {
    selectedGenre = ""
    selectedYear = nil
    playedFilter = .all
    searchText = ""
    committedSearch = ""
  }

  // MARK: - Networking

  private func loadServersAndLibraries() async {
    var serverNormalized = false
    if let endpoint = try? APIEndpoint(
      path: ["mediaserver", "clients"], responseContract: .payload),
      let list = try? await session.request(
        endpoint, as: [MediaServerClientSummary].self, requiring: .init(category: .discovery)
      ).value
    {
      servers = list
      if !list.contains(where: { $0.name == activeServer }),
        let matched =
          list.first(where: { $0.name.caseInsensitiveCompare(activeServer) == .orderedSame })
          ?? list.first(where: {
            ($0.type ?? "").caseInsensitiveCompare(activeServer) == .orderedSame
          })
          ?? list.first
      {
        activeServer = matched.name
        if activeServerType == nil {
          activeServerType = matched.type
        }
        serverNormalized = true
      }
    }
    await loadLibrariesForActiveServer(selectFirstIfMissing: false)
    if serverNormalized {
      async let filtersRefresh: Void = loadFilters()
      async let itemsRefresh: Void = reloadItems()
      _ = await (filtersRefresh, itemsRefresh)
    }
  }

  private func loadLibrariesForActiveServer(selectFirstIfMissing: Bool) async {
    guard
      let endpoint = try? APIEndpoint(
        path: ["mediaserver", "library"],
        query: [URLQueryItem(name: "server", value: activeServer)],
        responseContract: .payload
      ),
      let list = try? await session.request(
        endpoint, as: [MediaServerLibrarySummary].self, requiring: .init(category: .discovery)
      ).value
    else { return }
    libraries = list
    if selectFirstIfMissing, activeLibraryID == nil, let first = list.first {
      activeLibraryID = first.libraryID
      activeLibraryName = first.displayName
      activeLibraryType = first.type
    }
  }

  private func loadFilters() async {
    var query = [URLQueryItem(name: "server", value: activeServer)]
    if let activeLibraryID, !activeLibraryID.isEmpty {
      query.append(URLQueryItem(name: "library_id", value: activeLibraryID))
    }
    guard
      let endpoint = try? APIEndpoint(path: ["mediaserver", "filters"], query: query),
      let options = try? await session.request(
        endpoint, as: MediaServerFilterOptionsDTO.self, requiring: .init(category: .discovery)
      ).value
    else { return }
    filterOptions = options
  }

  private func reloadItems() async {
    let gen = UUID()
    queryGeneration = gen
    isLoading = true
    loadFailed = false
    do {
      let page = try await fetchBrowsePage(startIndex: 0)
      guard !Task.isCancelled, queryGeneration == gen else { return }
      items = page.items
      totalCount = page.totalCount
      hasMore = page.hasMore
      isLoading = false
    } catch is CancellationError {
      return
    } catch {
      guard queryGeneration == gen else { return }
      loadFailed = true
      isLoading = false
    }
  }

  private func loadNextPage() async {
    guard !isLoadingMore, hasMore else { return }
    let gen = queryGeneration
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let page = try await fetchBrowsePage(startIndex: items.count)
      guard !Task.isCancelled, queryGeneration == gen else { return }
      let existingIDs = Set(items.map(\.id))
      let fresh = page.items.filter { !existingIDs.contains($0.id) }
      items.append(contentsOf: fresh)
      totalCount = page.totalCount
      hasMore = page.hasMore && !fresh.isEmpty
    } catch {
      hasMore = false
    }
  }

  private func fetchBrowsePage(startIndex: Int) async throws -> MediaServerBrowsePageDTO {
    var query: [URLQueryItem] = [
      URLQueryItem(name: "server", value: activeServer),
      URLQueryItem(name: "sort_by", value: selectedSort.rawValue),
      URLQueryItem(name: "sort_order", value: sortOrder),
      URLQueryItem(name: "start_index", value: String(startIndex)),
      URLQueryItem(name: "limit", value: String(pageSize)),
    ]
    if let activeLibraryID, !activeLibraryID.isEmpty {
      query.append(URLQueryItem(name: "library_id", value: activeLibraryID))
    }
    let normalizedLibType = (activeLibraryType ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    .lowercased()
    if normalizedLibType == "合集" || normalizedLibType == "boxsets"
      || normalizedLibType == "boxset" || normalizedLibType == "collections"
    {
      query.append(URLQueryItem(name: "item_type", value: "BoxSet"))
    }
    if !selectedGenre.isEmpty {
      query.append(URLQueryItem(name: "genre", value: selectedGenre))
    }
    if let selectedYear {
      query.append(URLQueryItem(name: "year", value: String(selectedYear)))
    }
    if playedFilter != .all {
      query.append(URLQueryItem(name: "played_filter", value: playedFilter.rawValue))
    }
    if !committedSearch.isEmpty {
      query.append(URLQueryItem(name: "keyword", value: committedSearch))
    }
    let endpoint = try APIEndpoint(path: ["mediaserver", "browse"], query: query)
    return try await session.request(
      endpoint, as: MediaServerBrowsePageDTO.self, requiring: .init(category: .discovery)
    ).value
  }
}
