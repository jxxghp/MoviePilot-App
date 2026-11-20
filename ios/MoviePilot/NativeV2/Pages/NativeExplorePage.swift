import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生多来源探索片库：支持 TMDB / 豆瓣 / Bangumi 与扩展插件发现源的分类、排序、地区与年份筛选及自动翻页。
@MainActor
struct NativeExplorePage: View {
  let session: NativeSession
  let initialSource: NativeExploreSourceKind

  @State private var selectedSource: NativeExploreSourceKind
  @State private var extraSources: [NativeExtraDiscoverSource] = []
  @State private var selectedExtraID: String?

  // TMDB 筛选状态
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

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// 初始化探索页并选中指定的默认来源。
  init(session: NativeSession, initialSource: NativeExploreSourceKind = .tmdbMovies) {
    self.session = session
    self.initialSource = initialSource
    _selectedSource = State(initialValue: initialSource)
  }

  /// 连续紫玫瑰渐变背景、来源切换胶囊、精简筛选标签栏与自动翻页海报网格。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          sourceBar
          if selectedExtraID == nil {
            filterControls
          }
          if isLoading && items.isEmpty {
            ProgressView("正在探索片库…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 240)
          } else if loadFailed && items.isEmpty {
            failureCard
          } else if items.isEmpty {
            emptyCard
          } else {
            posterGrid
            if isLoadingMore {
              ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
          }
        }
        .padding(.vertical, 12)
      }
      .scrollIndicators(.hidden)
      .refreshable { await reload() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-explore-scroll")
    }
    .navigationTitle("探索片库")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task { await loadExtraSources() }
    .task(id: filterSignature) { await reload() }
  }

  /// 组合全部生效的来源与筛选参数作为重载触发键。
  private var filterSignature: String {
    [
      selectedExtraID ?? selectedSource.rawValue,
      tmdbSort, tmdbGenre, tmdbLanguage,
      doubanSort, doubanTag,
      bangumiSort, bangumiCategory, bangumiYear,
      String(reloadToken),
    ].joined(separator: "|")
  }

  /// 紧凑三列海报网格（iPad 宽屏自动扩展至五列）。
  private var columns: [GridItem] {
    let count = horizontalSizeClass == .regular ? 5 : 3
    return Array(repeating: GridItem(.flexible(), spacing: 11), count: count)
  }

  /// 顶部多来源切换胶囊栏。
  private var sourceBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(NativeExploreSourceKind.allCases) { source in
          let active = selectedExtraID == nil && selectedSource == source
          filterPill(
            title: source.title, active: active, id: "native-explore-source-\(source.rawValue)"
          ) {
            selectedExtraID = nil
            selectedSource = source
          }
        }
        ForEach(extraSources) { extra in
          let active = selectedExtraID == extra.id
          filterPill(title: extra.name, active: active, id: "native-explore-extra-\(extra.id)") {
            selectedExtraID = extra.id
          }
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("native-explore-source-bar")
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
              .foregroundStyle(active ? .white : .white.opacity(0.70))
              .padding(.horizontal, 11)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(
                    active
                      ? Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.65)
                      : .white.opacity(0.08)
                  )
                  .overlay {
                    Capsule().strokeBorder(
                      .white.opacity(active ? 0.28 : 0.12), lineWidth: 0.6)
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
        .foregroundStyle(active ? .white : .white.opacity(0.76))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
          Capsule()
            .fill(
              active
                ? Color(red: 0.58, green: 0.42, blue: 0.88).opacity(0.78)
                : Color(red: 36 / 255, green: 30 / 255, blue: 52 / 255).opacity(0.68)
            )
            .overlay {
              Capsule().strokeBorder(.white.opacity(active ? 0.34 : 0.14), lineWidth: 0.7)
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
                  .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
              }
              if let rating = item.ratingText {
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
              .foregroundStyle(.white.opacity(0.95))
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .center)
            if let subtitle = item.subtitle, !subtitle.isEmpty {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
            }
          }
          .multilineTextAlignment(.center)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
          .foregroundStyle(.white.opacity(0.55))
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
    } catch {
      return
    }
  }

  /// 重置分页并加载首页探索结果。
  private func reload() async {
    let generation = UUID()
    queryGeneration = generation
    isLoading = true
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
      items = deduplicate(loaded)
      hasMore = !loaded.isEmpty
    } catch is CancellationError {
      return
    } catch {
      guard queryGeneration == generation else { return }
      items = []
      loadFailed = true
    }
  }

  /// 自动分页加载后续页并去重。
  private func loadMore() async {
    guard hasMore, !isLoadingMore, !isLoading else { return }
    let generation = queryGeneration
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
        return
      }
      var existing = Set(items.map(\.id))
      let appended = loaded.filter { existing.insert($0.id).inserted }
      items.append(contentsOf: appended)
      page = nextPage
      if appended.isEmpty { hasMore = false }
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

  /// 稳定标识。
  var id: String { rawValue }

  /// 中文来源展示标题。
  var title: String {
    switch self {
    case .tmdbMovies: "TMDB 电影"
    case .tmdbTVs: "TMDB 剧集"
    case .doubanMovies: "豆瓣电影"
    case .doubanTVs: "豆瓣剧集"
    case .bangumi: "Bangumi"
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
