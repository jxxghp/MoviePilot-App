import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生多来源探索片库：支持 TheMovieDB / 豆瓣 / Bangumi / 音乐与扩展插件发现源的分类、排序、地区与年份筛选及自动翻页。
@MainActor
struct NativeExplorePage: View {
  let session: NativeSession
  let initialSource: NativeExploreSourceKind

  @State private var selectedSource: NativeExploreSourceKind
  @State private var extraSources: [NativeExtraDiscoverSource] = []
  @State private var selectedExtraID: String?
  @AppStorage("nativeV2.exploreSources.v1") private var storedSourcesJSON = ""
  @State private var sourceConfigs: [NativeExploreSourceConfig] =
    NativeExploreSourceConfig.defaults
  @State private var showsSourceConfigSheet = false

  // TheMovieDB 筛选状态
  @State private var tmdbSort = "popularity.desc"
  @State private var tmdbGenre = ""
  @State private var tmdbLanguage = ""

  // 豆瓣筛选状态
  @State private var doubanSort = "U"
  @State private var doubanTag = ""

  // Bangumi 筛选状态
  @State private var bangumiSort = "rank"
  @State private var bangumiCategory = ""
  @State private var bangumiYear = ""

  @State private var items: [NativeExploreItem] = []
  @State private var page = 1
  @State private var hasMore = true
  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var loadFailed = false
  @State private var queryGeneration = UUID()
  @State private var reloadToken = 0
  @State private var contextDetailIdentity: NativeMediaIdentity?
  @State private var contextResourceItem: NativeExploreItem?

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// 初始化探索页并选中指定的默认来源。
  init(
    session: NativeSession,
    initialSource: NativeExploreSourceKind = .tmdbMovies
  ) {
    self.session = session
    self.initialSource = initialSource
    _selectedSource = State(initialValue: initialSource)
  }

  /// 当前是否处于音乐探索模式。
  private var isMusicSelected: Bool {
    selectedExtraID == nil && selectedSource == .music
  }

  /// 连续紫玫瑰渐变背景、来源切换胶囊、精简筛选标签栏与自动翻页海报/专辑网格。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if isMusicSelected {
            NativeMusicExploreSection(session: session, reloadToken: reloadToken)
              .padding(.horizontal, CinematicStyle.margin)
          } else {
            if selectedExtraID == nil {
              filterControls
            }
            if isLoading && items.isEmpty {
              ProgressView("正在探索片库…")
                .tint(.primary)
                .frame(maxWidth: .infinity, minHeight: 240)
            } else if loadFailed && items.isEmpty {
              failureCard
            } else if items.isEmpty {
              emptyCard
            } else {
              posterGrid
              if isLoadingMore {
                ProgressView()
                  .tint(.primary)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 14)
              }
            }
          }
        }
        .padding(.vertical, 12)
      }
      .scrollIndicators(.hidden)
      .refreshable {
        if isMusicSelected {
          reloadToken += 1
        } else {
          await reload(forceRefresh: true)
        }
      }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-explore-scroll")
    }
    .navigationTitle(activeSourceTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        sourceSwitcherMenu
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsSourceConfigSheet = true
        } label: {
          Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("配置探索来源")
        .accessibilityIdentifier("native-explore-more")
      }
    }
    .sheet(isPresented: $showsSourceConfigSheet) {
      NativeExploreSourcesSheet(initialItems: sourceConfigs) { updated in
        sourceConfigs = updated
        saveSourceConfigs(updated)
        ensureActiveSourceEnabled()
      }
    }
    .onAppear { syncSourceConfigs() }
    .navigationDestination(
      isPresented: Binding(
        get: { contextDetailIdentity != nil },
        set: { if !$0 { contextDetailIdentity = nil } })
    ) {
      if let id = contextDetailIdentity {
        NativeMediaDetailPage(session: session, identity: id)
      }
    }
    .navigationDestination(
      isPresented: Binding(
        get: { contextResourceItem != nil },
        set: { if !$0 { contextResourceItem = nil } })
    ) {
      if let item = contextResourceItem {
        NativeResourceSearchPage(
          session: session,
          target: .media(identity: item.identity, title: item.title, season: nil))
      }
    }
    .task { await loadExtraSources() }
    .task(id: filterSignature) { await reload(forceRefresh: false) }
  }

  /// 缓存键（不含主动刷新计数），用于切换页面或切回相同来源时首帧直出缓存。
  private var cacheKey: String {
    [
      "explore",
      selectedExtraID ?? selectedSource.rawValue,
      tmdbSort, tmdbGenre, tmdbLanguage,
      doubanSort, doubanTag,
      bangumiSort, bangumiCategory, bangumiYear,
    ].joined(separator: "|")
  }

  /// 组合全部生效的来源与筛选参数作为重载触发键。
  private var filterSignature: String {
    "\(cacheKey)|\(reloadToken)"
  }

  /// 紧凑三列海报网格（iPad 宽屏自动扩展至五列）。
  private var columns: [GridItem] {
    let count = horizontalSizeClass == .regular ? 5 : 3
    return Array(repeating: GridItem(.flexible(), spacing: 11), count: count)
  }

  /// 当前选中的一级探索来源标题，显示于顶部导航栏居中位置。
  private var activeSourceTitle: String {
    if let extraID = selectedExtraID,
      let extra = extraSources.first(where: { $0.id == extraID })
    {
      return extra.name
    }
    return selectedSource.title
  }

  /// 左上角一级探索来源切换菜单（按用户配置的顺序与开关列出所有内置来源及插件扩展源）。
  private var sourceSwitcherMenu: some View {
    let enabledConfigs = sourceConfigs.filter(\.enabled)
    return Menu {
      ForEach(enabledConfigs) { config in
        if let builtIn = NativeExploreSourceKind(rawValue: config.id) {
          let active = selectedExtraID == nil && selectedSource == builtIn
          Button {
            selectedExtraID = nil
            selectedSource = builtIn
          } label: {
            if active {
              Label(builtIn.title, systemImage: "checkmark")
            } else {
              Label(builtIn.title, systemImage: builtIn.symbol)
            }
          }
          .accessibilityIdentifier("native-explore-source-\(builtIn.rawValue)")
        } else if let extra = extraSources.first(where: { "extra:\($0.id)" == config.id }) {
          let active = selectedExtraID == extra.id
          Button {
            selectedExtraID = extra.id
          } label: {
            if active {
              Label(extra.name, systemImage: "checkmark")
            } else {
              Label(extra.name, systemImage: "puzzlepiece.extension")
            }
          }
          .accessibilityIdentifier("native-explore-extra-\(extra.id)")
        }
      }
    } label: {
      Image(systemName: "square.stack.3d.up")
    }
    .accessibilityLabel("切换探索来源，当前：\(activeSourceTitle)")
    .accessibilityIdentifier("native-explore-source-switcher")
  }

  /// 同步本地已保存的探索来源顺序与开关，并与插件扩展来源合并。
  private func syncSourceConfigs() {
    var saved: [NativeExploreSourceConfig] = []
    if let data = storedSourcesJSON.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([NativeExploreSourceConfig].self, from: data)
    {
      saved = decoded
    }
    sourceConfigs = NativeExploreSourceConfig.merged(saved: saved, extras: extraSources)
    ensureActiveSourceEnabled()
  }

  /// 持久化探索来源顺序与开关。
  private func saveSourceConfigs(_ configs: [NativeExploreSourceConfig]) {
    guard let data = try? JSONEncoder().encode(configs),
      let raw = String(data: data, encoding: .utf8)
    else { return }
    storedSourcesJSON = raw
  }

  /// 若当前选中的来源已被用户关闭，自动切换到首个已开启来源。
  private func ensureActiveSourceEnabled() {
    let enabled = sourceConfigs.filter(\.enabled)
    guard !enabled.isEmpty else { return }
    let currentKey = selectedExtraID.map { "extra:\($0)" } ?? selectedSource.rawValue
    guard !enabled.contains(where: { $0.id == currentKey }) else { return }
    if let first = enabled.first {
      if let builtIn = NativeExploreSourceKind(rawValue: first.id) {
        selectedExtraID = nil
        selectedSource = builtIn
      } else if first.id.hasPrefix("extra:") {
        selectedExtraID = String(first.id.dropFirst("extra:".count))
      }
    }
  }

  /// 按当前来源渲染精简原生筛选行。
  @ViewBuilder
  private var filterControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch selectedSource {
      case .tmdbMovies, .tmdbTVs:
        chipRow(
          options: selectedSource == .tmdbMovies ? Self.tmdbMovieSorts : Self.tmdbTVSorts,
          selection: tmdbSort, prefix: "sort"
        ) { tmdbSort = $0 }
        chipRow(
          options: selectedSource == .tmdbMovies ? Self.tmdbMovieGenres : Self.tmdbTVGenres,
          selection: tmdbGenre, prefix: "genre"
        ) { tmdbGenre = $0 }
        chipRow(options: Self.tmdbLanguages, selection: tmdbLanguage, prefix: "lang") {
          tmdbLanguage = $0
        }
      case .doubanMovies, .doubanTVs:
        chipRow(options: Self.doubanSorts, selection: doubanSort, prefix: "sort") {
          doubanSort = $0
        }
        chipRow(options: Self.doubanTags, selection: doubanTag, prefix: "tag") {
          doubanTag = $0
        }
      case .bangumi:
        chipRow(options: Self.bangumiSorts, selection: bangumiSort, prefix: "sort") {
          bangumiSort = $0
        }
        chipRow(options: Self.bangumiCategories, selection: bangumiCategory, prefix: "cat") {
          bangumiCategory = $0
        }
        chipRow(options: Self.bangumiYears, selection: bangumiYear, prefix: "year") {
          bangumiYear = $0
        }
      case .music:
        EmptyView()
      }
    }
  }

  /// 单行横向筛选胶囊组。
  private func chipRow(
    options: [(value: String, label: String)],
    selection: String,
    prefix: String,
    onSelect: @escaping (String) -> Void
  ) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: 7) {
        ForEach(options, id: \.value) { option in
          let active = selection == option.value
          Button {
            onSelect(option.value)
          } label: {
            Text(option.label)
              .font(.caption.weight(active ? .semibold : .medium))
              .foregroundStyle(active ? .white : .primary.opacity(0.72))
              .padding(.horizontal, 11)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(
                    active
                      ? Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.65)
                      : .primary.opacity(0.08)
                  )
                  .overlay {
                    Capsule().strokeBorder(
                      .primary.opacity(active ? 0.28 : 0.12), lineWidth: 0.6)
                  }
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-explore-filter-\(prefix)-\(option.label)")
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
    }
    .scrollIndicators(.hidden)
  }

  /// 来源切换主胶囊按钮。
  private func filterPill(
    title: String, active: Bool, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(active ? .white : .primary.opacity(0.78))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
          Capsule()
            .fill(
              active
                ? NativeAppearanceStore.shared.accentColor
                : .primary.opacity(0.08)
            )
            .overlay {
              Capsule().strokeBorder(.primary.opacity(active ? 0.34 : 0.14), lineWidth: 0.7)
            }
        }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 海报网格，滑至底部倒数第六项自动加载下一页，点击直达原生详情页。
  private var posterGrid: some View {
    LazyVGrid(columns: columns, spacing: 16) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        NavigationLink {
          NativeMediaDetailPage(session: session, identity: item.identity)
        } label: {
          VStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .topTrailing) {
              NativeMediaArtwork(
                session: session, reference: item.posterReference, role: .poster, maximumWidth: 420
              )
              .aspectRatio(2.0 / 3.0, contentMode: .fill)
              .clipShape(.rect(cornerRadius: 13))
              .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                  .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
              }
              if let rating = item.ratingText {
                Text(rating)
                  .font(.caption2.weight(.bold).monospacedDigit())
                  .foregroundStyle(.primary)
                  .padding(.horizontal, 6)
                  .padding(.vertical, 2.5)
                  .background {
                    Capsule().fill(.black.opacity(0.62))
                  }
                  .padding(6)
              }
            }
            Text(item.title)
              .font(.footnote.weight(.medium))
              .foregroundStyle(.primary.opacity(0.95))
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .center)
            if let subtitle = item.subtitle, !subtitle.isEmpty {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.54))
                .lineLimit(1)
            }
          }
          .multilineTextAlignment(.center)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
          Button {
            contextDetailIdentity = item.identity
          } label: {
            Label("查看详情", systemImage: "info.circle")
          }
          if session.user.allows(.init(category: .search)) {
            Button {
              contextResourceItem = item
            } label: {
              Label("搜索资源", systemImage: "magnifyingglass")
            }
          }
        }
        .accessibilityIdentifier("native-explore-poster-\(item.identity.id)")
        .onAppear {
          if hasMore && !isLoadingMore && index >= max(0, items.count - 6) {
            Task { await loadMore() }
          }
        }
      }
    }
    .padding(.horizontal, CinematicStyle.margin)
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "film.stack")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text("当前筛选条件下暂无片目").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 160)
    }
    .padding(.horizontal, CinematicStyle.margin)
  }

  /// 失败重试卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入探索结果", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { reloadToken += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-explore-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, CinematicStyle.margin)
  }

  /// 拉取插件扩展发现源，失败不阻塞内置 TMDB/豆瓣/Bangumi 探索。
  private func loadExtraSources() async {
    do {
      let endpoint = try APIEndpoint(path: ["discover", "source"])
      let loaded = try await session.request(endpoint, as: [NativeExtraDiscoverSource].self).value
      try Task.checkCancellation()
      let builtInPrefixes: Set<String> = ["tmdb", "douban", "bangumi", "anilist", "music"]
      extraSources = loaded.filter { source in
        !source.apiPath.isEmpty && !builtInPrefixes.contains(source.prefix.lowercased())
      }
      syncSourceConfigs()
    } catch {
      return
    }
  }

  /// 重置分页并加载首页探索结果；命中页面缓存时静默复用，下拉刷新强制重拉。
  private func reload(forceRefresh: Bool = false) async {
    guard !isMusicSelected else { return }
    let key = cacheKey
    if !forceRefresh,
      let cached: NativeExplorePageCacheEntry = NativePageDataCache.shared.get(
        key, session: session)
    {
      items = cached.items
      page = cached.page
      hasMore = cached.hasMore
      isLoading = false
      isLoadingMore = false
      loadFailed = false
      return
    }
    let generation = UUID()
    queryGeneration = generation
    if items.isEmpty { isLoading = true }
    isLoadingMore = false
    loadFailed = false
    page = 1
    hasMore = true
    defer {
      if queryGeneration == generation { isLoading = false }
    }
    do {
      let loaded = try await fetch(page: 1)
      try Task.checkCancellation()
      guard queryGeneration == generation else { return }
      let deduped = deduplicate(loaded)
      items = deduped
      hasMore = !loaded.isEmpty
      NativePageDataCache.shared.set(
        NativeExplorePageCacheEntry(items: deduped, page: 1, hasMore: hasMore),
        for: key, session: session)
    } catch is CancellationError {
      return
    } catch {
      guard queryGeneration == generation else { return }
      if items.isEmpty { loadFailed = true }
    }
  }

  /// 自动分页加载后续页并去重，同时写回页面缓存。
  private func loadMore() async {
    guard hasMore, !isLoadingMore, !isLoading else { return }
    let generation = queryGeneration
    let key = cacheKey
    isLoadingMore = true
    defer {
      if queryGeneration == generation { isLoadingMore = false }
    }
    let nextPage = page + 1
    do {
      let loaded = try await fetch(page: nextPage)
      try Task.checkCancellation()
      guard queryGeneration == generation else { return }
      if loaded.isEmpty {
        hasMore = false
        NativePageDataCache.shared.set(
          NativeExplorePageCacheEntry(items: items, page: page, hasMore: false),
          for: key, session: session)
        return
      }
      var existing = Set(items.map(\.id))
      let appended = loaded.filter { existing.insert($0.id).inserted }
      items.append(contentsOf: appended)
      page = nextPage
      if appended.isEmpty { hasMore = false }
      NativePageDataCache.shared.set(
        NativeExplorePageCacheEntry(items: items, page: page, hasMore: hasMore),
        for: key, session: session)
    } catch {
      return
    }
  }

  /// 构造受控同源发现端点并投影媒体条目。
  private func fetch(page: Int) async throws -> [NativeExploreItem] {
    let endpoint: APIEndpoint
    let fallbackType: String
    if let extraID = selectedExtraID,
      let extra = extraSources.first(where: { $0.id == extraID })
    {
      let segments = extra.apiPath.split(separator: "/").map(String.init)
      guard !segments.isEmpty else { return [] }
      endpoint = try APIEndpoint(
        path: segments, query: [URLQueryItem(name: "page", value: String(page))])
      fallbackType = "电影"
    } else {
      var query = [URLQueryItem(name: "page", value: String(page))]
      let path: [String]
      switch selectedSource {
      case .tmdbMovies:
        path = ["discover", "tmdb_movies"]
        query.append(URLQueryItem(name: "sort_by", value: tmdbSort))
        if !tmdbGenre.isEmpty { query.append(URLQueryItem(name: "with_genres", value: tmdbGenre)) }
        if !tmdbLanguage.isEmpty {
          query.append(URLQueryItem(name: "with_original_language", value: tmdbLanguage))
        }
        fallbackType = "电影"
      case .tmdbTVs:
        path = ["discover", "tmdb_tvs"]
        query.append(URLQueryItem(name: "sort_by", value: tmdbSort))
        if !tmdbGenre.isEmpty { query.append(URLQueryItem(name: "with_genres", value: tmdbGenre)) }
        if !tmdbLanguage.isEmpty {
          query.append(URLQueryItem(name: "with_original_language", value: tmdbLanguage))
        }
        fallbackType = "电视剧"
      case .doubanMovies:
        path = ["discover", "douban_movies"]
        query.append(URLQueryItem(name: "sort", value: doubanSort))
        if !doubanTag.isEmpty { query.append(URLQueryItem(name: "tags", value: doubanTag)) }
        fallbackType = "电影"
      case .doubanTVs:
        path = ["discover", "douban_tvs"]
        query.append(URLQueryItem(name: "sort", value: doubanSort))
        if !doubanTag.isEmpty { query.append(URLQueryItem(name: "tags", value: doubanTag)) }
        fallbackType = "电视剧"
      case .bangumi:
        path = ["discover", "bangumi"]
        query.append(URLQueryItem(name: "type", value: "2"))
        query.append(URLQueryItem(name: "sort", value: bangumiSort))
        if !bangumiCategory.isEmpty {
          query.append(URLQueryItem(name: "cat", value: bangumiCategory))
        }
        if !bangumiYear.isEmpty { query.append(URLQueryItem(name: "year", value: bangumiYear)) }
        fallbackType = "电视剧"
      case .music:
        return []
      }
      endpoint = try APIEndpoint(path: path, query: query)
    }
    let rows = try await session.request(endpoint, as: [NativeExploreAPIItem].self).value
    return rows.compactMap { $0.project(fallbackType: fallbackType) }
  }

  /// 同页去重保持顺序稳定。
  private func deduplicate(_ list: [NativeExploreItem]) -> [NativeExploreItem] {
    var seen: Set<String> = []
    return list.filter { seen.insert($0.id).inserted }
  }

  // MARK: - Built-in Filter Dictionaries

  private static let tmdbMovieSorts: [(String, String)] = [
    ("popularity.desc", "热门"),
    ("release_date.desc", "最新"),
    ("vote_average.desc", "高分"),
  ]

  private static let tmdbTVSorts: [(String, String)] = [
    ("popularity.desc", "热门"),
    ("first_air_date.desc", "最新"),
    ("vote_average.desc", "高分"),
  ]

  private static let tmdbMovieGenres: [(String, String)] = [
    ("", "全部类型"), ("28", "动作"), ("878", "科幻"), ("16", "动画"),
    ("35", "喜剧"), ("18", "剧情"), ("9648", "悬疑"), ("80", "犯罪"),
  ]

  private static let tmdbTVGenres: [(String, String)] = [
    ("", "全部类型"), ("10759", "动作冒险"), ("10765", "科幻奇幻"), ("16", "动画"),
    ("35", "喜剧"), ("18", "剧情"), ("9648", "悬疑"), ("80", "犯罪"),
  ]

  private static let tmdbLanguages: [(String, String)] = [
    ("", "全部语言"), ("zh", "华语"), ("en", "英语"), ("ja", "日语"), ("ko", "韩语"),
  ]

  private static let doubanSorts: [(String, String)] = [
    ("U", "综合"), ("T", "近期热门"), ("S", "高分"), ("R", "最新上线"),
  ]

  private static let doubanTags: [(String, String)] = [
    ("", "全部标签"), ("喜剧", "喜剧"), ("动作", "动作"), ("科幻", "科幻"),
    ("动画", "动画"), ("悬疑", "悬疑"), ("华语", "华语"), ("欧美", "欧美"),
    ("日本", "日本"), ("韩国", "韩国"),
  ]

  private static let bangumiSorts: [(String, String)] = [
    ("rank", "评分排行"), ("date", "放送日期"),
  ]

  private static let bangumiCategories: [(String, String)] = [
    ("", "全部分类"), ("1", "TV"), ("3", "剧场版"), ("2", "OVA"), ("5", "WEB"),
  ]

  private static let bangumiYears: [(String, String)] = [
    ("", "全部年份"), ("2026", "2026"), ("2025", "2025"), ("2024", "2024"), ("2023", "2023"),
    ("2022", "2022"),
  ]
}

/// 内置多来源探索枚举。
enum NativeExploreSourceKind: String, CaseIterable, Identifiable, Hashable {
  case tmdbMovies = "tmdb_movies"
  case tmdbTVs = "tmdb_tvs"
  case doubanMovies = "douban_movies"
  case doubanTVs = "douban_tvs"
  case bangumi = "bangumi"
  case music = "music"

  /// 稳定标识。
  var id: String { rawValue }

  /// 中文来源展示标题。
  var title: String {
    switch self {
    case .tmdbMovies: "TheMovieDB 电影"
    case .tmdbTVs: "TheMovieDB 剧集"
    case .doubanMovies: "豆瓣电影"
    case .doubanTVs: "豆瓣剧集"
    case .bangumi: "Bangumi"
    case .music: "音乐"
    }
  }

  /// 来源菜单对应的 SF Symbol 图标。
  var symbol: String {
    switch self {
    case .tmdbMovies: "film"
    case .tmdbTVs: "tv"
    case .doubanMovies: "sparkles.tv"
    case .doubanTVs: "play.tv"
    case .bangumi: "sparkles"
    case .music: "music.note"
    }
  }
}

/// 插件注册的扩展发现源投影。
private struct NativeExtraDiscoverSource: Decodable, Sendable, Identifiable {
  let name: String
  let prefix: String
  let apiPath: String

  /// 使用前缀与路径构造稳定标识。
  var id: String { prefix.isEmpty ? apiPath : prefix }

  private enum CodingKeys: String, CodingKey {
    case name
    case prefix = "mediaid_prefix"
    case apiPath = "api_path"
  }
}

/// 探索结果条目投影。
private struct NativeExploreItem: Identifiable, Hashable {
  let identity: NativeMediaIdentity
  let title: String
  let subtitle: String?
  let posterReference: String?
  let ratingText: String?

  /// 使用受控媒体身份作为稳定标识。
  var id: String { identity.id }
}

/// 探索接口 `MediaInfo` 精简解码结构体。
private struct NativeExploreAPIItem: Decodable, Sendable {
  let mediaSource: String?
  let mediaID: String?
  let tmdbID: Int?
  let doubanID: String?
  let bangumiID: Int?
  let type: String?
  let title: String?
  let year: String?
  let posterPath: String?
  let voteAverage: Double?

  /// 投影为带受控身份的网格卡片模型。
  func project(fallbackType: String) -> NativeExploreItem? {
    let source: String
    let resolvedID: String?
    if let explicitSource = mediaSource, !explicitSource.isEmpty,
      let explicitID = mediaID, !explicitID.isEmpty
    {
      source = explicitSource
      resolvedID = explicitID
    } else if let tmdbID {
      source = "themoviedb"
      resolvedID = String(tmdbID)
    } else if let doubanID, !doubanID.isEmpty {
      source = "douban"
      resolvedID = doubanID
    } else if let bangumiID {
      source = "bangumi"
      resolvedID = String(bangumiID)
    } else {
      return nil
    }
    guard let idValue = resolvedID else { return nil }
    let identity = NativeMediaIdentity(
      source: source, mediaID: idValue, type: type ?? fallbackType)
    let ratingText = voteAverage.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
    return NativeExploreItem(
      identity: identity,
      title: title ?? "未命名作品",
      subtitle: year,
      posterReference: posterPath,
      ratingText: ratingText
    )
  }

  private enum CodingKeys: String, CodingKey {
    case type, title, year
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case doubanID = "douban_id"
    case bangumiID = "bangumi_id"
    case posterPath = "poster_path"
    case voteAverage = "vote_average"
  }
}

/// 单条可编排的探索来源显示开关与顺序配置（内置源 + 插件扩展源）。
private struct NativeExploreSourceConfig: Identifiable, Codable, Equatable, Sendable {
  let id: String
  var title: String
  var symbol: String
  var enabled: Bool

  static var defaults: [NativeExploreSourceConfig] {
    NativeExploreSourceKind.allCases.map { source in
      let symbol: String =
        switch source {
        case .tmdbMovies: "film"
        case .tmdbTVs: "tv"
        case .doubanMovies: "sparkles.tv"
        case .doubanTVs: "play.tv"
        case .bangumi: "wand.and.stars"
        case .music: "music.note"
        }
      return NativeExploreSourceConfig(
        id: source.rawValue, title: source.title, symbol: symbol, enabled: true)
    }
  }

  /// 合并已保存顺序/显隐与最新可用内置源及插件扩展源。
  static func merged(
    saved: [NativeExploreSourceConfig], extras: [NativeExtraDiscoverSource]
  ) -> [NativeExploreSourceConfig] {
    var available: [String: NativeExploreSourceConfig] = Dictionary(
      uniqueKeysWithValues: defaults.map { ($0.id, $0) })
    for extra in extras {
      let key = "extra:\(extra.id)"
      available[key] = NativeExploreSourceConfig(
        id: key, title: extra.name, symbol: "puzzlepiece.extension", enabled: true)
    }
    var seen: Set<String> = []
    var result: [NativeExploreSourceConfig] = []
    for item in saved {
      if var latest = available[item.id], seen.insert(item.id).inserted {
        latest.enabled = item.enabled
        result.append(latest)
      }
    }
    for base in defaults where seen.insert(base.id).inserted {
      result.append(base)
    }
    for extra in extras {
      let key = "extra:\(extra.id)"
      if let item = available[key], seen.insert(key).inserted {
        result.append(item)
      }
    }
    return result
  }
}

/// 探索来源开关与拖拽排序弹层。
@MainActor
private struct NativeExploreSourcesSheet: View {
  let initialItems: [NativeExploreSourceConfig]
  let onSave: ([NativeExploreSourceConfig]) -> Void

  @State private var items: [NativeExploreSourceConfig]
  @State private var editMode: EditMode = .active
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  init(
    initialItems: [NativeExploreSourceConfig],
    onSave: @escaping ([NativeExploreSourceConfig]) -> Void
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
            Text("开启或拖动调整探索来源顺序")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } footer: {
            Text("至少保留一个开启的探索来源，保存后立即同步到探索栏。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
      }
      .navigationTitle("探索来源配置")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") {
            let final = items.contains(where: \.enabled) ? items : initialItems
            onSave(final)
            dismiss()
          }
          .fontWeight(.semibold)
          .accessibilityIdentifier("native-explore-config-save")
        }
      }
    }
    .nativeAppearanceRoot()
  }
}

private struct NativeExplorePageCacheEntry {
  let items: [NativeExploreItem]
  let page: Int
  let hasMore: Bool
}
