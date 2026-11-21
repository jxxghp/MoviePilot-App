import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 原生多来源探索片库：支持 TheMovieDB / 豆瓣 / Bangumi / 音乐与扩展插件发现源的分类、排序、地区与年份筛选及自动翻页。
@MainActor
struct NativeExplorePage: View {
  let session: NativeSession
  let initialSource: NativeExploreSourceKind

  @State private var selectedSource: NativeExploreSourceKind
  @State private var extraSources: [NativeExtraDiscoverSource] = []
  @State private var enabledBuiltInSources: Set<NativeExploreSourceKind>?
  @State private var selectedExtraID: String?
  @AppStorage("nativeV2.exploreSources.v1") private var storedSourcesJSON = ""
  @State private var sourceConfigs: [NativeExploreSourceConfig] =
    NativeExploreSourceConfig.defaults

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
          sourceCardBar
          if isMusicSelected {
            NativeMusicExploreSection(session: session, reloadToken: reloadToken)
              .padding(.horizontal, CinematicStyle.margin)
          } else {
            if selectedExtraID == nil {
              Divider()
                .overlay(.primary.opacity(0.08))
                .padding(.horizontal, CinematicStyle.margin)
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
    .navigationTitle("探索")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .onAppear {
      syncSourceConfigs()
      Task { await loadExtraSources() }
    }
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

  /// 横向带品牌 Logo 的一级来源小卡片导航：卡片形态、图标徽标与主题高亮边界，与下方紧凑筛选胶囊形成鲜明视觉层次区分。
  private var sourceCardBar: some View {
    let enabledConfigs = sourceConfigs.filter(\.enabled)
    let accent = NativeAppearanceStore.shared.accentColor
    return ScrollView(.horizontal) {
      HStack(spacing: 10) {
        ForEach(enabledConfigs) { config in
          if let builtIn = NativeExploreSourceKind(rawValue: config.id) {
            let active = selectedExtraID == nil && selectedSource == builtIn
            sourceBrandCard(
              brand: builtIn.brandName,
              category: builtIn.categoryBadge,
              logoAsset: builtIn.logoAssetName,
              fallbackSymbol: builtIn.symbol,
              brandTint: builtIn.brandTint,
              active: active,
              accent: accent,
              id: "native-explore-source-\(builtIn.rawValue)"
            ) {
              withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedExtraID = nil
                selectedSource = builtIn
              }
            }
          } else if let extra = extraSources.first(where: { "extra:\($0.id)" == config.id }) {
            let active = selectedExtraID == extra.id
            sourceBrandCard(
              brand: extra.name,
              category: "插件源",
              logoAsset: "logo-plugin",
              fallbackSymbol: "puzzlepiece.extension",
              brandTint: accent,
              active: active,
              accent: accent,
              id: "native-explore-extra-\(extra.id)"
            ) {
              withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedExtraID = extra.id
              }
            }
          }
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
      .padding(.vertical, 2)
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("native-explore-source-bar")
  }

  /// 单个带来源 Logo 的玻璃小卡片。
  private func sourceBrandCard(
    brand: String,
    category: String,
    logoAsset: String,
    fallbackSymbol: String,
    brandTint: Color,
    active: Bool,
    accent: Color,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Group {
          if let uiImage = UIImage(named: logoAsset) {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFit()
          } else {
            Image(systemName: fallbackSymbol)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(active ? brandTint : .secondary)
          }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

        VStack(alignment: .leading, spacing: 1.5) {
          Text(brand)
            .font(.caption.weight(active ? .bold : .semibold))
            .foregroundStyle(.primary.opacity(active ? 1.0 : 0.80))
            .lineLimit(1)
          Text(category)
            .font(.system(size: 10, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? accent : .secondary)
            .lineLimit(1)
        }
      }
      .padding(.leading, 8)
      .padding(.trailing, 12)
      .padding(.vertical, 8)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(
            active
              ? LinearGradient(
                colors: [accent.opacity(0.22), brandTint.opacity(0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
              : LinearGradient(
                colors: [Color.primary.opacity(0.07), Color.primary.opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(
                active ? accent.opacity(0.65) : Color.primary.opacity(0.12),
                lineWidth: active ? 1.1 : 0.6)
          }
      }
      .shadow(
        color: active ? accent.opacity(0.22) : .clear,
        radius: active ? 8 : 0, y: active ? 3 : 0
      )
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(active ? .isSelected : [])
    .accessibilityIdentifier(id)
  }

  /// 同步本地已保存的探索来源顺序与开关，并与后端已启用媒体模块及插件扩展来源合并。
  private func syncSourceConfigs() {
    var saved: [NativeExploreSourceConfig] = []
    if let data = storedSourcesJSON.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([NativeExploreSourceConfig].self, from: data)
    {
      saved = decoded
    }
    sourceConfigs = NativeExploreSourceConfig.merged(
      saved: saved, extras: extraSources, allowedBuiltIns: enabledBuiltInSources)
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

  /// 海报网格，滑至底部倒数第六项自动加载下一页，点击直达原生详情页；本地媒体库已存在时展示绿色对勾。
  private var posterGrid: some View {
    LazyVGrid(columns: columns, spacing: 16) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        NavigationLink {
          NativeMediaDetailPage(session: session, identity: item.identity)
        } label: {
          NativeExplorePosterTile(session: session, item: item)
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

  /// 并行拉取后端已启用媒体模块目录（`GET /api/v1/media/source`）与插件扩展发现源（`GET /api/v1/discover/source`），
  /// 自动隐藏后台高级设置中已关闭的内置探索来源（如 Bangumi / 豆瓣 / 音乐）。
  private func loadExtraSources() async {
    async let mediaSourcesTask: [NativeExploreMediaSourceInfo]? = {
      guard let endpoint = try? APIEndpoint(path: ["media", "source"]) else { return nil }
      return try? await session.request(endpoint, as: [NativeExploreMediaSourceInfo].self).value
    }()
    async let extrasTask: [NativeExtraDiscoverSource]? = {
      guard let endpoint = try? APIEndpoint(path: ["discover", "source"]) else { return nil }
      return try? await session.request(endpoint, as: [NativeExtraDiscoverSource].self).value
    }()
    let (loadedMediaSources, loadedExtras) = await (mediaSourcesTask, extrasTask)
    guard !Task.isCancelled else { return }

    if let loadedMediaSources {
      let sourceIDs = Set(loadedMediaSources.map { $0.mediaSource.lowercased() })
      let hasMusic = loadedMediaSources.contains(where: \.isMusicSource)
      var allowed: Set<NativeExploreSourceKind> = []
      if sourceIDs.contains("themoviedb") {
        allowed.insert(.tmdbMovies)
        allowed.insert(.tmdbTVs)
      }
      if sourceIDs.contains("douban") {
        allowed.insert(.doubanMovies)
        allowed.insert(.doubanTVs)
      }
      if sourceIDs.contains("bangumi") {
        allowed.insert(.bangumi)
      }
      if hasMusic {
        allowed.insert(.music)
      }
      enabledBuiltInSources = allowed
    }
    if let loadedExtras {
      let builtInPrefixes: Set<String> = ["tmdb", "douban", "bangumi", "anilist", "music"]
      extraSources = loadedExtras.filter { source in
        !source.apiPath.isEmpty && !builtInPrefixes.contains(source.prefix.lowercased())
      }
    }
    syncSourceConfigs()
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
        path: segments,
        query: [URLQueryItem(name: "page", value: String(page))])
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
        query.append(URLQueryItem(name: "count", value: "30"))
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
    let rows = try await session.request(endpoint, as: [NativeLossyExploreAPIItem].self).value
    return rows.compactMap { $0.value?.project(fallbackType: fallbackType) }
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
    ("", "全部分类"), ("1", "TV"), ("3", "剧场版"), ("2", "OVA"), ("5", "WEB"), ("0", "其他"),
  ]

  private static var bangumiYears: [(String, String)] {
    let current = Calendar.current.component(.year, from: Date())
    var list: [(String, String)] = [("", "全部年份")]
    for y in (max(current - 9, 2010)...current).reversed() {
      let s = String(y)
      list.append((s, s))
    }
    return list
  }
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

  /// 品牌主标题（配合子分类徽标呈现双行小卡片）。
  var brandName: String {
    switch self {
    case .tmdbMovies, .tmdbTVs: "TheMovieDB"
    case .doubanMovies, .doubanTVs: "豆瓣"
    case .bangumi: "Bangumi"
    case .music: "音乐"
    }
  }

  /// 卡片子分类标签。
  var categoryBadge: String {
    switch self {
    case .tmdbMovies, .doubanMovies: "电影"
    case .tmdbTVs, .doubanTVs: "剧集"
    case .bangumi: "番剧"
    case .music: "榜单与专辑"
    }
  }

  /// Assets.xcassets 中的来源品牌 Logo 资源名。
  var logoAssetName: String {
    switch self {
    case .tmdbMovies, .tmdbTVs: "logo-tmdb"
    case .doubanMovies, .doubanTVs: "logo-douban"
    case .bangumi: "logo-bangumi"
    case .music: "logo-musicbrainz"
    }
  }

  /// 品牌特征强调色。
  var brandTint: Color {
    switch self {
    case .tmdbMovies, .tmdbTVs: Color(red: 0.05, green: 0.71, blue: 0.88)
    case .doubanMovies, .doubanTVs: Color(red: 0.18, green: 0.75, blue: 0.36)
    case .bangumi: Color(red: 0.94, green: 0.56, blue: 0.62)
    case .music: Color(red: 0.74, green: 0.48, blue: 0.98)
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

/// `GET /api/v1/media/source` 后端已启用媒体源条目。
private struct NativeExploreMediaSourceInfo: Decodable, Sendable {
  let name: String
  let mediaSource: String
  let mediaTypes: [String]?

  var isMusicSource: Bool {
    let lower = mediaSource.lowercased()
    if ["musicbrainz", "theaudiodb", "douban_music"].contains(lower) { return true }
    return (mediaTypes ?? []).contains {
      let t = $0.lowercased()
      return t == "音乐" || t == "music"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case mediaSource = "media_source"
    case mediaTypes = "media_types"
  }
}

/// 探索页单张海报网格瓦片：本地媒体库已存在时在右上角展示绿色对勾（与 Web `MediaCard.vue` 一致）。
@MainActor
private struct NativeExplorePosterTile: View {
  let session: NativeSession
  let item: NativeExploreItem

  @State private var existsInLibrary = false

  var body: some View {
    let resolvedExists =
      existsInLibrary
      || (NativeMediaLibraryStatusStore.shared.cachedExists(
        session: session,
        source: item.identity.source,
        mediaID: item.identity.mediaID,
        title: item.title,
        year: item.subtitle,
        type: item.identity.type
      ) == true)
    return VStack(alignment: .center, spacing: 6) {
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
        if resolvedExists {
          NativeMediaExistsBadge(size: 20)
            .padding(6)
        } else if let rating = item.ratingText {
          Text(rating)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
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
    .task(id: item.id) {
      if let cached = NativeMediaLibraryStatusStore.shared.cachedExists(
        session: session,
        source: item.identity.source,
        mediaID: item.identity.mediaID,
        title: item.title,
        year: item.subtitle,
        type: item.identity.type
      ) {
        existsInLibrary = cached
        return
      }
      let result = await NativeMediaLibraryStatusStore.shared.checkExists(
        session: session,
        source: item.identity.source,
        mediaID: item.identity.mediaID,
        title: item.title,
        year: item.subtitle,
        type: item.identity.type
      )
      if !Task.isCancelled {
        existsInLibrary = result
      }
    }
  }
}

/// 探索结果单条宽容包装，避免单条数据字段异构导致整页解码失败。
private struct NativeLossyExploreAPIItem: Decodable, Sendable {
  let value: NativeExploreAPIItem?
  init(from decoder: Decoder) throws {
    value = try? NativeExploreAPIItem(from: decoder)
  }
}

/// 探索接口 `MediaInfo` 宽容解码结构体（兼容 TMDB / 豆瓣 / Bangumi 整数字段与字符串字段差异）。
private struct NativeExploreAPIItem: Decodable, Sendable {
  let mediaSource: String?
  let mediaID: String?
  let tmdbID: String?
  let doubanID: String?
  let bangumiID: String?
  let type: String?
  let title: String?
  let year: String?
  let posterPath: String?
  let voteAverage: Double?

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    mediaSource = try? c.decodeIfPresent(String.self, forKey: .mediaSource)
    mediaID = Self.decodeScalar(c, forKey: .mediaID)
    tmdbID = Self.decodeScalar(c, forKey: .tmdbID)
    doubanID = Self.decodeScalar(c, forKey: .doubanID)
    bangumiID = Self.decodeScalar(c, forKey: .bangumiID)
    type = try? c.decodeIfPresent(String.self, forKey: .type)
    title = try? c.decodeIfPresent(String.self, forKey: .title)
    year = Self.decodeScalar(c, forKey: .year)
    posterPath =
      (try? c.decodeIfPresent(String.self, forKey: .posterPath))
      ?? (try? c.decodeIfPresent(String.self, forKey: .image))
    if let d = try? c.decodeIfPresent(Double.self, forKey: .voteAverage) {
      voteAverage = d
    } else if let s = try? c.decodeIfPresent(String.self, forKey: .voteAverage), let d = Double(s) {
      voteAverage = d
    } else {
      voteAverage = nil
    }
  }

  private static func decodeScalar(
    _ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
  ) -> String? {
    if let s = try? container.decodeIfPresent(String.self, forKey: key) {
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let n = try? container.decodeIfPresent(Int64.self, forKey: key) {
      return n == 0 ? nil : String(n)
    }
    return nil
  }

  /// 投影为带受控身份的网格卡片模型。
  func project(fallbackType: String) -> NativeExploreItem? {
    let source: String
    let resolvedID: String?
    if let explicitSource = mediaSource, !explicitSource.isEmpty,
      let explicitID = mediaID, !explicitID.isEmpty
    {
      source = explicitSource
      resolvedID = explicitID
    } else if let tmdbID, !tmdbID.isEmpty {
      source = "themoviedb"
      resolvedID = tmdbID
    } else if let doubanID, !doubanID.isEmpty {
      source = "douban"
      resolvedID = doubanID
    } else if let bangumiID, !bangumiID.isEmpty {
      source = "bangumi"
      resolvedID = bangumiID
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
    case type, title, year, image
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

  /// 合并已保存顺序/显隐与后端已启用内置源及插件扩展源。
  static func merged(
    saved: [NativeExploreSourceConfig],
    extras: [NativeExtraDiscoverSource],
    allowedBuiltIns: Set<NativeExploreSourceKind>? = nil
  ) -> [NativeExploreSourceConfig] {
    let activeDefaults: [NativeExploreSourceConfig]
    if let allowedBuiltIns {
      activeDefaults = defaults.filter { item in
        guard let kind = NativeExploreSourceKind(rawValue: item.id) else { return true }
        return allowedBuiltIns.contains(kind)
      }
    } else {
      activeDefaults = defaults
    }
    var available: [String: NativeExploreSourceConfig] = Dictionary(
      uniqueKeysWithValues: activeDefaults.map { ($0.id, $0) })
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
    for base in activeDefaults where seen.insert(base.id).inserted {
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
