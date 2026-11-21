import Foundation
import MoviePilotAPI
import MoviePilotSession
import SwiftUI

/// 按后端统一搜索响应保留可展示字段；未知 discriminator 字段不影响其它条目。
private struct NativeMediaSearchItem: Decodable, Sendable, Identifiable {
  let publicID: Scalar?
  let type: Scalar?
  let musicType: String?
  let mediaSource: String?
  let mediaID: String?
  let title: String?
  let name: String?
  let originalTitle: String?
  let year: Scalar?
  let releaseDate: String?
  let voteAverage: Double?
  let overview: String?
  let posterPath: String?
  let profilePath: String?
  let imageURL: String?
  let coverURL: String?
  let releaseTrackID: String?
  let albumID: String?
  let collectionID: Scalar?
  let source: String?
  let character: String?
  let artist: String?
  let artists: [String]?
  let album: String?
  let genres: [NativeMediaSearchGenre]?

  /// 人物的公共 id 允许整数/字符串，因此使用受限 JSON 投影而非强制一种类型。
  private enum CodingKeys: String, CodingKey {
    case type, title, name, source, character, artist, genres, overview
    case publicID = "id"
    case musicType = "music_type"
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case originalTitle = "original_title"
    case year
    case releaseDate = "release_date"
    case voteAverage = "vote_average"
    case posterPath = "poster_path"
    case profilePath = "profile_path"
    case imageURL = "image_url"
    case coverURL = "cover_url"
    case releaseTrackID = "musicbrainz_release_track_id"
    case albumID = "album_id"
    case collectionID = "collection_id"
    case artists, album
  }

  /// 人物 ID、年份和类型可能以整数或字符串传递，保留整数精度及原始文本。
  struct Scalar: Decodable, Sendable {
    let value: String

    /// DTO 不接受布尔、数组或对象冒充文本与整数标识。
    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let text = try? container.decode(String.self) {
        value = text
      } else {
        value = try String(container.decode(Int64.self))
      }
    }
  }

  /// 同一来源的不同影视类别或音乐实体即使原生 ID 相同也能分别显示。
  var id: String {
    let kind = musicType ?? (resultKind == .media ? type?.value : nil) ?? resultKind.rawValue
    let identity =
      mediaID ?? collectionID?.value ?? publicID?.value ?? releaseTrackID ?? albumID
      ?? [displayTitle, displayYear ?? ""].joined(separator: ":")
    return [kind, mediaSource ?? source ?? "", identity].joined(separator: ":")
  }

  /// 后端 discriminator 与 `MediaSearchResult` 联合类型一致。
  var resultKind: NativeMediaSearchResultKind {
    if musicType == "artist" { return .artist }
    if type?.value == "系列" || type?.value == "合集" { return .collection }
    if type?.value == "音乐" || musicType != nil { return .music }
    if mediaSource == nil, source != nil { return .person }
    return .media
  }

  /// 统一结果的主标题，优先级依照人员/媒体/音乐 DTO 的展示字段。
  var displayTitle: String {
    for value in [name, title, originalTitle] {
      if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
    }
    return "未命名结果"
  }

  /// 从后端图像字段选择第一个可代理的 HTTPS 地址，跳过空值或无效首选图。
  var artworkReference: String? {
    let candidates: [String?]
    switch resultKind {
    case .person: candidates = [profilePath, imageURL]
    case .music: candidates = [coverURL, posterPath, imageURL]
    case .artist: candidates = [imageURL, posterPath, coverURL, profilePath]
    case .media, .collection: candidates = [posterPath, imageURL]
    }
    for case let candidate? in candidates {
      if candidate.utf8.count <= 8_192, let components = URLComponents(string: candidate),
        components.scheme == "https", components.host?.isEmpty == false,
        components.user == nil, components.password == nil, components.fragment == nil,
        components.port == nil || components.port == 443, let url = components.url
      {
        return url.absoluteString
      }
    }
    return nil
  }

  /// 年份优先采用后端 year，缺少时再读规范日期前四位。
  var displayYear: String? {
    if let year = year?.value, !year.isEmpty { return year }
    guard let releaseDate, releaseDate.count >= 4 else { return nil }
    let prefix = String(releaseDate.prefix(4))
    return prefix.allSatisfy(\.isNumber) ? prefix : nil
  }

  /// 影视详情只接收成对的规范主身份，不将人物/音乐/系列或辅助 ID 导向影视页。
  var detailIdentity: (source: String, id: String, type: String)? {
    guard resultKind == .media, let type = type?.value, ["电影", "电视剧"].contains(type),
      let source = mediaSource?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      source.range(of: #"\A[a-z][a-z0-9._-]{0,63}\z"#, options: .regularExpression) != nil,
      let id = mediaID?.trimmingCharacters(in: .whitespacesAndNewlines), id != "0",
      (try? APIEndpoint(path: ["media", id])) != nil
    else { return nil }
    return (source, id, type)
  }
}

/// 后端影视风格可为带名称对象，音乐风格则为字符串列表。
private struct NativeMediaSearchGenre: Decodable, Sendable {
  let name: String?

  /// 同时兼容媒体和音乐搜索返回的两种现有风格格式。
  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let name = try? value.decode(String.self) {
      self.name = name
      return
    }
    let details = try decoder.container(keyedBy: CodingKeys.self)
    name = try details.decodeIfPresent(String.self, forKey: .name)
  }

  /// 后端 `MediaGenre` 以对象形式暴露风格名称。
  private enum CodingKeys: String, CodingKey {
    case name
  }
}

/// 后端媒体主来源目录只用于筛选名称，保留插件扩展来源原值。
private struct NativeMediaSourceOption: Decodable, Sendable, Identifiable {
  let name: String
  let mediaSource: String
  let mediaTypes: [String]?

  /// 唯一键直接使用后端来源值，不在客户端拼接或归一化别名。
  var id: String { mediaSource }

  /// 解码现有媒体来源目录的 snake_case API 字段。
  private enum CodingKeys: String, CodingKey {
    case name
    case mediaSource = "media_source"
    case mediaTypes = "media_types"
  }

  /// 类型选择与现有入口一致，合集和人物只开放已由宿主声明的搜索来源。
  func supports(_ kind: NativeMediaSearchType) -> Bool {
    let source = mediaSource.lowercased()
    if kind == .collection { return source == "themoviedb" }
    if kind == .person {
      return ["themoviedb", "douban", "musicbrainz"].contains(source)
    }
    let types = (mediaTypes ?? ["电影", "电视剧"]).map { $0.lowercased() }
    if kind == .music { return types.contains("音乐") || types.contains("music") }
    return types.contains { ["电影", "电视剧", "movie", "tv"].contains($0) }
  }
}

/// 搜索页面所支持的分类集合：覆盖影视、媒体库（本地/远程 Emby/Jellyfin/Plex）、人物、音乐与合集。
private enum NativeMediaSearchType: String, CaseIterable, Identifiable, Hashable, Sendable {
  case media
  case library
  case person
  case music
  case collection

  /// 页面分组顺序和 ID 均固定，不依赖响应下标。
  var id: String { rawValue }

  /// 使用用户熟悉的媒体分类标签。
  var title: String {
    switch self {
    case .media: "影视"
    case .library: "媒体库"
    case .person: "人物"
    case .music: "音乐"
    case .collection: "合集"
    }
  }
}

/// 媒体库搜索可选的类型筛选。
private enum NativeLibrarySearchFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
  case all = "全部"
  case movie = "电影"
  case tv = "电视剧"
  case music = "音乐"

  var id: String { rawValue }

  var queryTypes: [String] {
    switch self {
    case .all: ["电影", "电视剧", "音乐"]
    case .movie: ["电影"]
    case .tv: ["电视剧"]
    case .music: ["音乐"]
    }
  }
}

/// 媒体服务器搜索结果条目（对应 `GET /api/v1/mediaserver/search` 返回的 `MediaServerPlayItem`）。
private struct NativeLibrarySearchItem: Decodable, Sendable, Identifiable, Hashable {
  let idScalar: NativeMediaSearchItem.Scalar?
  let itemIDScalar: NativeMediaSearchItem.Scalar?
  let server: String?
  let serverType: String?
  let title: String?
  let subtitle: String?
  let yearScalar: NativeMediaSearchItem.Scalar?
  let type: String?
  let image: String?
  let percent: Double?

  private enum CodingKeys: String, CodingKey {
    case server, title, subtitle, type, image, percent
    case idScalar = "id"
    case itemIDScalar = "item_id"
    case serverType = "server_type"
    case yearScalar = "year"
  }

  var playableItemID: String { itemIDScalar?.value ?? idScalar?.value ?? "" }
  var displayTitle: String {
    let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "未命名条目" : trimmed
  }
  var yearText: String? {
    let raw = yearScalar?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return raw.isEmpty ? nil : raw
  }
  var isMusic: Bool { type == "音乐" || type?.lowercased() == "audio" }
  var isSeries: Bool { type == "电视剧" || type?.lowercased() == "series" }
  var id: String { "\(server ?? "srv"):\(playableItemID):\(displayTitle)" }

  func resolvedImageReference(baseURL: URL) -> String? {
    guard let raw = image?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      return raw
    }
    if raw.hasPrefix("/") {
      var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
      components?.path = ""
      components?.query = nil
      components?.fragment = nil
      if let origin = components?.url?.absoluteString.trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))
      {
        return origin + raw
      }
    }
    return nil
  }

  static func == (lhs: NativeLibrarySearchItem, rhs: NativeLibrarySearchItem) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

/// 兼容标准 `{ "success": true, "data": [...] }` 包装与裸数组的媒体库搜索解码器。
private struct NativeLibrarySearchEnvelope: Decodable, Sendable {
  let items: [NativeLibrarySearchItem]

  private enum CodingKeys: String, CodingKey { case data }

  init(from decoder: Decoder) throws {
    if let container = try? decoder.container(keyedBy: CodingKeys.self),
      let list = try? container.decode([NativeLibrarySearchItem].self, forKey: .data)
    {
      items = list
      return
    }
    let single = try decoder.singleValueContainer()
    items = (try? single.decode([NativeLibrarySearchItem].self)) ?? []
  }
}

/// 兼容标准响应包装与裸字典的电视剧季集映射解码器。
private struct NativeLibraryEpisodesEnvelope: Decodable, Sendable {
  let map: [Int: [Int: String]]

  private enum CodingKeys: String, CodingKey { case data }

  init(from decoder: Decoder) throws {
    let raw: [String: [String: String]]
    if let container = try? decoder.container(keyedBy: CodingKeys.self),
      let wrapped = try? container.decode([String: [String: String]].self, forKey: .data)
    {
      raw = wrapped
    } else {
      let single = try decoder.singleValueContainer()
      raw = (try? single.decode([String: [String: String]].self)) ?? [:]
    }
    var parsed: [Int: [Int: String]] = [:]
    for (seasonKey, episodes) in raw {
      guard let season = Int(seasonKey) else { continue }
      var epMap: [Int: String] = [:]
      for (epKey, epItemID) in episodes {
        if let epNum = Int(epKey), !epItemID.isEmpty {
          epMap[epNum] = epItemID
        }
      }
      if !epMap.isEmpty { parsed[season] = epMap }
    }
    map = parsed
  }
}

/// 已提交检索的完整条件；查看后续页时草稿文本和筛选变化不会影响这一快照。
private struct NativeMediaSearchQuery: Equatable {
  let term: String
  let kind: NativeMediaSearchType
  let sources: [String]
  let libraryFilter: NativeLibrarySearchFilter
}

/// 四个实际搜索 type 之外再表达后端单独返回的音乐艺术家 discriminator。
private enum NativeMediaSearchResultKind: String, CaseIterable, Sendable {
  case media
  case person
  case music
  case artist
  case collection

  /// 搜索结果分区标题使用与媒体类型一致的本地名称。
  var title: String {
    switch self {
    case .media: "影片"
    case .person: "人物"
    case .music: "音乐"
    case .artist: "音乐人"
    case .collection: "合集"
    }
  }
}

/// Cinematic 原生媒体搜索页，直接请求当前账号实例的搜索与来源 API。
@MainActor
struct NativeMediaSearchPage: View {
  let session: NativeSession
  let onSelect: (String, String?, String?) -> Void
  @Binding var externalSearchQuery: String?
  @State private var query: String
  @State private var kind: NativeMediaSearchType = .media
  @State private var sources: [NativeMediaSourceOption] = []
  @State private var selections: [NativeMediaSearchType: Set<String>] = [:]
  @State private var results: [NativeMediaSearchItem] = []
  @State private var libraryResults: [NativeLibrarySearchItem] = []
  @State private var libraryFilter: NativeLibrarySearchFilter = .all
  @State private var librarySeriesPicker: NativeLibrarySeriesPickerTarget?
  @State private var libraryPlaybackFeedback: String?
  @State private var launchingLibraryItemID: String?
  @State private var selectedMusicAlbum: NativeMusicCardItem?
  @State private var selectedMusicArtist: (id: String, name: String, source: String)?
  @State private var committedQuery: NativeMediaSearchQuery?
  @State private var didStartInitialSearch = false
  @State private var loadedPage = 0
  @State private var hasMore = false
  @State private var isLoadingSources = false
  @State private var isSearching = false
  @State private var failure: String?
  @State private var sourceFailure = false
  @State private var sourceLoadAttempt = UUID()
  @State private var searchTask: Task<Void, Never>?
  @State private var searchGeneration = UUID()
  @State private var recentQueries: [String] = []
  @FocusState private var searchFocused: Bool

  /// 搜索详情回调只传输受控来源和原生 ID，不传自由 URL。
  init(
    session: NativeSession, initialQuery: String = "",
    externalSearchQuery: Binding<String?> = .constant(nil),
    onSelect: @escaping (String, String?, String?) -> Void = { _, _, _ in }
  ) {
    self.session = session
    _externalSearchQuery = externalSearchQuery
    self.onSelect = onSelect
    _query = State(initialValue: initialQuery)
    _recentQueries = State(initialValue: Self.loadRecentQueries(for: session))
  }

  /// 搜索条件与结果共享 Cinematic 渐变和透色玻璃；网络错误不会切回网页或丢失筛选。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          searchControls
          if let libraryPlaybackFeedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(libraryPlaybackFeedback).font(.caption).foregroundStyle(.primary.opacity(0.90))
                Spacer(minLength: 0)
                Button {
                  self.libraryPlaybackFeedback = nil
                } label: {
                  Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }
            }
          }
          if let failure {
            statusCard(failure, symbol: "exclamationmark.triangle")
            if let committedQuery {
              CinematicPrimaryAction(title: "重试搜索", symbol: "arrow.clockwise") {
                startRequest(for: committedQuery, page: loadedPage == 0 ? 1 : loadedPage + 1)
              }
              .accessibilityIdentifier("native-media-search-retry")
            }
          }
          if !libraryResults.isEmpty || !results.isEmpty {
            if trimmedQuery != committedQuery?.term, let term = committedQuery?.term {
              Text("“\(term)”的搜索结果").font(.subheadline).foregroundStyle(.secondary)
            }
            if !libraryResults.isEmpty {
              libraryResultsSection
            }
            if !results.isEmpty {
              resultsContent
            }
            if isSearching, loadedPage > 0 {
              ProgressView()
                .tint(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
          } else if failure == nil {
            if isSearching {
              statusCard("正在搜索…", symbol: "magnifyingglass")
            } else if loadedPage > 0 {
              statusCard(
                committedQuery?.kind == .library ? "媒体库中未找到相关内容" : "没有找到相关结果",
                symbol: "sparkle.magnifyingglass")
            } else if !recentQueries.isEmpty {
              recentSearchesSection
            }
          }
        }
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.top, 14).padding(.bottom, 30)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-media-search-scroll")
    }
    .navigationTitle("搜索")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task(id: sourceLoadAttempt) { await loadSources() }
    .onAppear {
      consumeExternalSearchIfNeeded()
      beginInitialSearchIfNeeded()
      if !isLoadingSources { sourceLoadAttempt = UUID() }
    }
    .onChange(of: externalSearchQuery) { _ in
      consumeExternalSearchIfNeeded()
    }
    .onDisappear(perform: cancelSearch)
    .onChange(of: query) { value in
      if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { clearResults() }
    }
    .sheet(item: $librarySeriesPicker) { target in
      NativeLibraryEpisodesSheet(session: session, target: target)
    }
    .navigationDestination(
      isPresented: Binding(
        get: { selectedMusicAlbum != nil },
        set: { if !$0 { selectedMusicAlbum = nil } })
    ) {
      if let seed = selectedMusicAlbum {
        NativeMusicAlbumDetailPage(session: session, seed: seed)
      }
    }
    .navigationDestination(
      isPresented: Binding(
        get: { selectedMusicArtist != nil },
        set: { if !$0 { selectedMusicArtist = nil } })
    ) {
      if let artist = selectedMusicArtist {
        NativeMusicArtistDetailPage(
          session: session, artistID: artist.id, artistName: artist.name, source: artist.source)
      }
    }
  }

  /// 极简通透的独立液态玻璃搜索框与高辨识度分类筛选栏（聚焦态带主题强调色微光边界）。
  private var searchControls: some View {
    let accent = NativeAppearanceStore.shared.accentColor
    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(searchFocused ? accent : .secondary)
          .accessibilityHidden(true)
        TextField("搜索影视、媒体库、人物或音乐", text: $query)
          .font(.subheadline)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .focused($searchFocused)
          .onSubmit { submitSearch() }
          .accessibilityLabel("搜索关键词")
          .accessibilityIdentifier("native-media-search-query")
        if !query.isEmpty {
          Button {
            query = ""
            clearResults()
            searchFocused = true
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.subheadline)
              .foregroundStyle(.secondary.opacity(0.82))
              .frame(width: 30, height: 30)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清除搜索")
        }
        Button(action: submitSearch) {
          Group {
            if isSearching, loadedPage == 0, committedQuery?.term == trimmedQuery {
              ProgressView().controlSize(.small).tint(.white)
            } else {
              Image(systemName: "arrow.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            }
          }
          .frame(width: 32, height: 32)
          .background(
            trimmedQuery.isEmpty ? Color.primary.opacity(0.14) : accent,
            in: Circle()
          )
        }
        .buttonStyle(.plain)
        .disabled(trimmedQuery.isEmpty)
        .accessibilityLabel("搜索")
        .accessibilityIdentifier("native-media-search-submit")
      }
      .padding(.leading, 14)
      .padding(.trailing, 8)
      .frame(minHeight: 48)
      .background {
        Capsule()
          .fill(.ultraThinMaterial)
          .overlay {
            Capsule()
              .fill(Color.primary.opacity(searchFocused ? 0.06 : 0.04))
          }
          .overlay {
            Capsule()
              .strokeBorder(
                searchFocused ? accent.opacity(0.75) : Color.primary.opacity(0.14),
                lineWidth: searchFocused ? 1.2 : 0.7)
          }
      }
      .shadow(
        color: searchFocused ? accent.opacity(0.18) : .black.opacity(0.08),
        radius: searchFocused ? 10 : 6, y: 3)

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(availableKinds) { option in
            let selected = kind == option
            Button {
              guard kind != option else { return }
              withAnimation(.spring(response: 0.25, dampingFraction: 0.84)) {
                kind = option
              }
              submitSearch()
            } label: {
              Text(option.title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : .primary.opacity(0.76))
                .padding(.horizontal, 15)
                .frame(minHeight: 34)
                .background {
                  if selected {
                    Capsule()
                      .fill(
                        LinearGradient(
                          colors: [accent, accent.opacity(0.78)],
                          startPoint: .topLeading, endPoint: .bottomTrailing)
                      )
                      .shadow(color: accent.opacity(0.32), radius: 6, y: 2)
                  } else {
                    Capsule()
                      .fill(.primary.opacity(0.07))
                      .overlay {
                        Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.6)
                      }
                  }
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("native-media-search-kind-\(option.rawValue)")
          }
          if kind == .library {
            libraryFilterMenu
          } else {
            sourceMenu
          }
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
    }
  }

  /// 媒体库分类筛选菜单（全部 / 电视剧 / 音乐）。
  private var libraryFilterMenu: some View {
    Menu {
      ForEach(NativeLibrarySearchFilter.allCases) { option in
        Button {
          guard libraryFilter != option else { return }
          libraryFilter = option
          submitSearch()
        } label: {
          if libraryFilter == option {
            Label(option.rawValue, systemImage: "checkmark")
          } else {
            Text(option.rawValue)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(libraryFilter == .all ? "类型" : libraryFilter.rawValue)
        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
      }
      .font(.subheadline.weight(libraryFilter == .all ? .regular : .semibold))
      .foregroundStyle(.primary.opacity(libraryFilter == .all ? 0.86 : 0.98))
      .padding(.horizontal, 12).frame(minHeight: 36)
      .background {
        Capsule()
          .fill(.primary.opacity(libraryFilter == .all ? 0.08 : 0.22))
          .overlay {
            Capsule().strokeBorder(
              .primary.opacity(libraryFilter == .all ? 0.14 : 0.28), lineWidth: 0.6)
          }
      }
      .frame(minHeight: 44).contentShape(Rectangle())
    }
    .tint(.primary)
    .accessibilityIdentifier("native-media-search-library-filter")
  }

  /// 后端动态来源筛选可多选，选择改变后重置页码并取消之前请求。
  private var sourceMenu: some View {
    let options = sources.filter { $0.supports(kind) }
    return Menu {
      if sourceFailure {
        Button {
          sourceLoadAttempt = UUID()
        } label: {
          Label("重试加载来源", systemImage: "arrow.clockwise")
        }
      }
      if options.isEmpty {
        if !sourceFailure { Text(isLoadingSources ? "正在加载来源…" : "没有可用来源") }
      } else {
        ForEach(options) { source in
          Button {
            if selectedSources.contains(source.id) {
              selections[kind, default: []].remove(source.id)
            } else {
              selections[kind, default: []].insert(source.id)
            }
            submitSearch()
          } label: {
            let displayName = Self.normalizedSourceDisplayName(source.name)
            if selectedSources.contains(source.id) {
              Label(displayName, systemImage: "checkmark")
            } else {
              Text(displayName)
            }
          }
          .accessibilityIdentifier("native-media-search-source-\(source.id)")
        }
        if !selectedSources.isEmpty {
          Button {
            selections[kind] = []
            submitSearch()
          } label: {
            Label("清除来源筛选", systemImage: "xmark.circle")
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(selectedSources.isEmpty ? "来源" : "来源 \(selectedSources.count)")
        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
      }
      .font(.subheadline.weight(selectedSources.isEmpty ? .regular : .semibold))
      .foregroundStyle(.primary.opacity(selectedSources.isEmpty ? 0.86 : 0.98))
      .padding(.horizontal, 12).frame(minHeight: 36)
      .background {
        Capsule()
          .fill(.white.opacity(selectedSources.isEmpty ? 0.08 : 0.22))
          .overlay {
            Capsule().strokeBorder(
              .white.opacity(selectedSources.isEmpty ? 0.14 : 0.28), lineWidth: 0.6)
          }
      }
      .frame(minHeight: 44).contentShape(Rectangle())
    }
    .tint(.primary)
    .disabled(isLoadingSources)
    .accessibilityIdentifier("native-media-search-sources")
  }

  /// 按后端已启用媒体模块过滤可用的搜索分类；模块列表尚未返回时先展示全部避免闪烁。
  private var availableKinds: [NativeMediaSearchType] {
    guard !sources.isEmpty else { return NativeMediaSearchType.allCases }
    return NativeMediaSearchType.allCases.filter { candidate in
      if candidate == .library { return true }
      return sources.contains { $0.supports(candidate) }
    }
  }

  /// 每个分类独立保留来源，避免切换分类后把内置音乐来源发送给影视搜索。
  private var selectedSources: Set<String> { selections[kind] ?? [] }

  /// 已入库媒体服务器搜索结果分组（支持直接播放单曲/影片或选择剧集季集播放）。
  private var libraryResultsSection: some View {
    Section {
      ForEach(libraryResults) { item in
        Button {
          Task { await openLibraryItem(item) }
        } label: {
          CinematicPanel(padding: 9) {
            HStack(alignment: .center, spacing: 12) {
              let shape = RoundedRectangle(cornerRadius: item.isMusic ? 12 : 11, style: .continuous)
              let thumbSize =
                item.isMusic ? CGSize(width: 60, height: 60) : CGSize(width: 64, height: 92)
              if let ref = item.resolvedImageReference(baseURL: session.instance.address.url) {
                NativeMediaArtwork(
                  session: session, reference: ref, role: .poster,
                  maximumWidth: Int(thumbSize.width * 2)
                )
                .frame(width: thumbSize.width, height: thumbSize.height)
                .clipShape(shape)
                .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
              } else {
                Rectangle()
                  .fill(Color.primary.opacity(0.05))
                  .frame(width: thumbSize.width, height: thumbSize.height)
                  .clipShape(shape)
                  .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
              }

              VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                  .lineLimit(2)
                HStack(spacing: 6) {
                  if let type = item.type, !type.isEmpty {
                    Text(type)
                      .font(.caption2.weight(.medium))
                      .foregroundStyle(NativeAppearanceStore.shared.accentColor)
                      .padding(.horizontal, 6)
                      .padding(.vertical, 2)
                      .background(
                        NativeAppearanceStore.shared.accentColor.opacity(0.14), in: Capsule())
                  }
                  if let server = item.server, !server.isEmpty {
                    Text(server)
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  if let year = item.yearText {
                    Text(year)
                      .font(.caption2.monospacedDigit())
                      .foregroundStyle(.secondary)
                  }
                }
                if let sub = item.subtitle, !sub.isEmpty {
                  Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)

              if launchingLibraryItemID == item.id {
                ProgressView().controlSize(.small).tint(.primary)
              }
            }
            .contentShape(Rectangle())
          }
        }
        .buttonStyle(.plain)
        .disabled(launchingLibraryItemID != nil)
        .accessibilityIdentifier("native-media-search-library-\(item.playableItemID)")
      }
    } header: {
      HStack {
        Text("我的媒体库")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Text("\(libraryResults.count) 项")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// 点击媒体库结果：音乐/电影直接拉起原生播放器，电视剧查询季集后弹出选集列表播放。
  private func openLibraryItem(_ item: NativeLibrarySearchItem) async {
    guard !item.playableItemID.isEmpty else { return }
    libraryPlaybackFeedback = nil
    launchingLibraryItemID = item.id
    defer { launchingLibraryItemID = nil }

    let artworkURL = NativeMediaPlaybackLauncher.proxiedArtworkURL(
      session: session,
      raw: item.resolvedImageReference(baseURL: session.instance.address.url))

    if item.isSeries {
      var queryItems = [URLQueryItem(name: "itemid", value: item.playableItemID)]
      if let server = item.server, !server.isEmpty {
        queryItems.append(URLQueryItem(name: "server", value: server))
      }
      if let endpoint = try? APIEndpoint(path: ["mediaserver", "episodes"], query: queryItems),
        let envelope = try? await session.request(
          endpoint, as: NativeLibraryEpisodesEnvelope.self, requiring: discoveryPermission
        ).value,
        !envelope.map.isEmpty
      {
        librarySeriesPicker = NativeLibrarySeriesPickerTarget(
          title: item.displayTitle,
          server: item.server,
          artworkURL: artworkURL,
          episodesBySeason: envelope.map
        )
        return
      }
    }

    var queue: [MediaPlaybackQueueItem] = []
    var queueIndex = 0
    if item.isMusic {
      let musicItems = libraryResults.filter(\.isMusic)
      queue = musicItems.map { track in
        MediaPlaybackQueueItem(
          itemId: track.playableItemID,
          title: track.displayTitle,
          server: track.server,
          artworkURL: NativeMediaPlaybackLauncher.proxiedArtworkURL(
            session: session,
            raw: track.resolvedImageReference(baseURL: session.instance.address.url)
          )?.absoluteString,
          artist: track.subtitle,
          album: nil
        )
      }
      queueIndex = musicItems.firstIndex(where: { $0.id == item.id }) ?? 0
    }

    let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
      session: session,
      itemID: item.playableItemID,
      server: item.server,
      title: item.displayTitle,
      artworkURL: artworkURL,
      queue: queue,
      queueIndex: queueIndex)
    if let err {
      libraryPlaybackFeedback = err
    }
  }

  /// 人物结果沿用 Cinematic 圆形头像横栏，影片/音乐/合集采用透色玻璃海报横卡。
  @ViewBuilder
  private var resultsContent: some View {
    ForEach(NativeMediaSearchResultKind.allCases, id: \.rawValue) { section in
      let matching = results.filter { $0.resultKind == section }
      if !matching.isEmpty {
        Section {
          if section == .person {
            ScrollView(.horizontal) {
              LazyHStack(alignment: .top, spacing: 14) {
                ForEach(matching) { item in
                  personTile(item)
                    .onAppear { requestNextPageIfNeeded(afterShowing: item.id) }
                }
              }
            }
            .scrollIndicators(.hidden)
          } else {
            ForEach(matching) { item in
              NativeMediaSearchRow(
                item: item, sourceNames: sourceNames, session: session,
                onSelect: selectionAction(for: item)
              )
              .onAppear { requestNextPageIfNeeded(afterShowing: item.id) }
            }
          }
        } header: {
          Text(section.title).font(.headline)
            .accessibilityAddTraits(.isHeader)
        }
      }
    }
  }

  /// 根据条目类型分发点击动作：影视进入作品详情，音乐专辑/单曲进入音乐专辑详情，艺人进入音乐人详情。
  private func selectionAction(for item: NativeMediaSearchItem) -> (() -> Void)? {
    if let identity = item.detailIdentity {
      return { onSelect(identity.source, identity.id, identity.type) }
    }
    if item.resultKind == .music {
      let source = item.mediaSource ?? item.source ?? "musicbrainz"
      let primaryID =
        item.mediaID ?? item.albumID ?? item.publicID?.value ?? item.releaseTrackID ?? ""
      let lookupID = item.albumID ?? primaryID
      guard !primaryID.isEmpty else { return nil }
      let seed = NativeMusicCardItem(
        id: "\(source)|\(primaryID)",
        mediaSource: source,
        mediaID: primaryID,
        albumLookupID: lookupID,
        releaseID: nil,
        title: item.displayTitle,
        artist: item.artist ?? item.artists?.first,
        artistID: nil,
        yearText: item.displayYear,
        coverReference: item.artworkReference,
        ratingText: item.voteAverage.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
      )
      return { selectedMusicAlbum = seed }
    }
    if item.resultKind == .artist {
      let source = item.mediaSource ?? item.source ?? "musicbrainz"
      guard let artistID = item.mediaID ?? item.publicID?.value, !artistID.isEmpty else {
        return nil
      }
      return { selectedMusicArtist = (id: artistID, name: item.displayTitle, source: source) }
    }
    return nil
  }

  /// 消费从发现卡片右键「搜索」等外部入口传入的关键词并立即触发检索。
  private func consumeExternalSearchIfNeeded() {
    guard let pending = externalSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
      !pending.isEmpty
    else { return }
    externalSearchQuery = nil
    query = pending
    if kind == .library { kind = .media }
    submitSearch()
  }

  /// 参照 Cinematic 全局搜索的人物圆形头像横栏，支持推入原生人物详情页。
  @ViewBuilder
  private func personTile(_ item: NativeMediaSearchItem) -> some View {
    let resolvedAvatar = NativeMediaDetailPage.resolveArtwork(
      item.artworkReference, source: item.mediaSource ?? "themoviedb")
    let content = VStack(spacing: 6) {
      Group {
        if let reference = resolvedAvatar {
          NativeMediaArtwork(
            session: session, reference: reference, role: .poster, maximumWidth: 160)
        } else {
          ZStack {
            Circle().fill(.primary.opacity(0.10))
            Image(systemName: "person.fill").font(.title2).foregroundStyle(.primary.opacity(0.55))
          }
        }
      }
      .frame(width: 72, height: 72)
      .clipShape(Circle())
      .overlay { Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6) }
      Text(item.displayTitle).font(.caption.weight(.medium)).lineLimit(1)
      if let role = item.character, !role.isEmpty {
        Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .frame(width: 78)
    .multilineTextAlignment(.center)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("native-media-search-result-\(item.id)")

    if let personID = item.mediaID.flatMap(Int.init),
      (item.mediaSource?.lowercased() ?? "themoviedb") == "themoviedb"
    {
      NavigationLink {
        NativePersonDetailPage(
          session: session, personID: personID, fallbackName: item.displayTitle,
          fallbackAvatar: resolvedAvatar)
      } label: {
        content
      }
      .buttonStyle(.plain)
    } else {
      content
    }
  }

  /// 来源目录用于可读的标签；统一将 TMDB / TheMovieDb 规范展示为 TheMovieDB。
  private var sourceNames: [String: String] {
    Dictionary(
      sources.map { ($0.id, Self.normalizedSourceDisplayName($0.name)) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  /// 规范化来源显示名，确保统一展示全称 `TheMovieDB`。
  private static func normalizedSourceDisplayName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    if lower == "tmdb" || lower == "themoviedb" { return "TheMovieDB" }
    return trimmed
  }

  /// 请求固定页大小；没有精确总数时用满页判断是否还能继续。
  private let pageSize = 8

  /// 和搜索入口使用同一权限，在请求往返时重新校验当前账号。
  private let discoveryPermission = PermissionRequirement(category: .discovery)

  /// 空白词和清除状态使用相同的判断。
  private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// 初始关键词立即检索，不等待来源目录；返回本页时仅恢复未完成的首页。
  private func beginInitialSearchIfNeeded() {
    if !didStartInitialSearch {
      didStartInitialSearch = true
      if !trimmedQuery.isEmpty { submitSearch() }
    } else if let committedQuery, loadedPage == 0, failure == nil, !isSearching {
      startRequest(for: committedQuery, page: 1)
    }
  }

  /// 最近搜索词卡片区：支持点击快速重搜、单条删除与一键清空。
  private var recentSearchesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("最近搜索")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button("清空") {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            clearAllRecentQueries()
          }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-media-search-clear-recent")
      }
      .padding(.horizontal, 4)

      NativeSearchChipsFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
        ForEach(recentQueries, id: \.self) { term in
          HStack(spacing: 5) {
            Button {
              query = term
              submitSearch()
            } label: {
              HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                Text(term)
                  .font(.subheadline)
                  .foregroundStyle(.primary.opacity(0.88))
                  .lineLimit(1)
              }
              .padding(.leading, 11)
              .padding(.vertical, 7)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-media-search-recent-\(term)")

            Button {
              withAnimation(.spring(response: 0.26, dampingFraction: 0.85)) {
                removeRecentQuery(term)
              }
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.85))
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .accessibilityLabel("删除搜索词 \(term)")
            .accessibilityIdentifier("native-media-search-delete-recent-\(term)")
          }
          .background {
            Capsule()
              .fill(.primary.opacity(0.08))
              .overlay {
                Capsule().strokeBorder(.primary.opacity(0.14), lineWidth: 0.6)
              }
          }
        }
      }
    }
    .accessibilityIdentifier("native-media-search-recent-section")
  }

  /// 提交时同步记录关键词、类型和来源，后续页面不会混入编辑中的条件。
  private func submitSearch() {
    guard !trimmedQuery.isEmpty else { return }
    searchFocused = false
    recordRecentQuery(trimmedQuery)
    let criteria = NativeMediaSearchQuery(
      term: trimmedQuery, kind: kind, sources: selectedSources.sorted(),
      libraryFilter: libraryFilter)
    guard !isSearching || committedQuery != criteria || loadedPage > 0 else { return }
    clearResults()
    committedQuery = criteria
    startRequest(for: criteria, page: 1)
  }

  /// 本地最近搜索存储键（按当前服务器实例与账号隔离）。
  private static func recentStorageKey(for session: NativeSession) -> String {
    "nativeV2.recentSearches.\(session.scope.instanceID.uuidString).\(session.scope.userID)"
  }

  /// 从本地 UserDefaults 读取最近搜索词列表。
  private static func loadRecentQueries(for session: NativeSession) -> [String] {
    guard let data = UserDefaults.standard.data(forKey: recentStorageKey(for: session)),
      let decoded = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return decoded
  }

  /// 持久化当前最近搜索词列表。
  private func saveRecentQueries(_ list: [String]) {
    guard let data = try? JSONEncoder().encode(list) else { return }
    UserDefaults.standard.set(data, forKey: Self.recentStorageKey(for: session))
  }

  /// 记录新搜索词到最前并去重，最多保留 16 条。
  private func recordRecentQuery(_ term: String) {
    let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return }
    var updated = recentQueries.filter { $0.caseInsensitiveCompare(cleaned) != .orderedSame }
    updated.insert(cleaned, at: 0)
    if updated.count > 16 { updated = Array(updated.prefix(16)) }
    recentQueries = updated
    saveRecentQueries(updated)
  }

  /// 删除单条最近搜索词。
  private func removeRecentQuery(_ term: String) {
    recentQueries.removeAll { $0 == term }
    saveRecentQueries(recentQueries)
  }

  /// 清空全部最近搜索词。
  private func clearAllRecentQueries() {
    recentQueries = []
    UserDefaults.standard.removeObject(forKey: Self.recentStorageKey(for: session))
  }

  /// 清空时同时丢弃分页和错误状态，防止迟到响应再次显示旧结果。
  private func clearResults() {
    cancelSearch()
    committedQuery = nil
    results = []
    libraryResults = []
    libraryPlaybackFeedback = nil
    loadedPage = 0
    hasMore = false
    failure = nil
  }

  /// 失效代次先于底层取消，已完成但尚未返回页面的请求同样无法回填。
  private func cancelSearch() {
    searchGeneration = UUID()
    searchTask?.cancel()
    searchTask = nil
    isSearching = false
  }

  /// 同步占用加载状态再启动请求，同一页不能被连续点击重复发出。
  private func startRequest(for criteria: NativeMediaSearchQuery, page: Int) {
    guard committedQuery == criteria, !isSearching else { return }
    let generation = UUID()
    searchGeneration = generation
    isSearching = true
    failure = nil
    searchTask = Task {
      defer {
        if searchGeneration == generation {
          isSearching = false
          searchTask = nil
        }
      }
      do {
        if criteria.kind == .library {
          let loadedLibrary = try await fetchLibraryResults(
            term: criteria.term, types: criteria.libraryFilter.queryTypes, limit: 40)
          try session.checkActive(requiring: discoveryPermission)
          guard searchGeneration == generation, committedQuery == criteria else { return }
          libraryResults = loadedLibrary
          loadedPage = 1
          hasMore = false
          return
        }

        var queryItems = [
          URLQueryItem(name: "title", value: criteria.term),
          URLQueryItem(name: "type", value: criteria.kind.rawValue),
          URLQueryItem(name: "page", value: String(page)),
          URLQueryItem(name: "count", value: String(pageSize)),
        ]
        queryItems += criteria.sources.map { URLQueryItem(name: "media_source", value: $0) }
        let endpoint = try APIEndpoint(path: ["media", "search"], query: queryItems)
        let response = try await session.request(
          endpoint, as: [NativeMediaSearchItem].self, requiring: discoveryPermission)
        try session.checkActive(requiring: discoveryPermission)
        guard searchGeneration == generation, committedQuery == criteria else { return }
        let values = response.value
        var existing = Set(results.map(\.id))
        let additions = values.filter { existing.insert($0.id).inserted }
        results += additions
        loadedPage = page
        if let total = response.collection.totalCount {
          hasMore = !additions.isEmpty && page * pageSize < total
        } else {
          hasMore = !additions.isEmpty && values.count == pageSize
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, searchGeneration == generation, committedQuery == criteria else {
          return
        }
        failure = Self.safeFailure(error)
      }
    }
  }

  /// 调用 `GET /api/v1/mediaserver/search` 检索已配置媒体服务器中的已入库内容。
  private func fetchLibraryResults(
    term: String, types: [String], limit: Int
  ) async throws -> [NativeLibrarySearchItem] {
    var queryItems = [
      URLQueryItem(name: "keyword", value: term),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    for type in types {
      queryItems.append(URLQueryItem(name: "type", value: type))
    }
    let endpoint = try APIEndpoint(path: ["mediaserver", "search"], query: queryItems)
    let envelope = try await session.request(
      endpoint, as: NativeLibrarySearchEnvelope.self, requiring: discoveryPermission
    ).value
    return envelope.items
  }

  /// 接近结果尾部时自动续页；失败页等待明确重试，不循环发送同一请求。
  private func requestNextPageIfNeeded(afterShowing id: String) {
    guard let committedQuery, hasMore, loadedPage > 0, failure == nil,
      results.suffix(3).contains(where: { $0.id == id })
    else { return }
    startRequest(for: committedQuery, page: loadedPage + 1)
  }

  /// 获取真实来源目录并自动剪除后台高级设置中已关闭的模块；目录失败不阻止未筛选的核心搜索。
  private func loadSources() async {
    let attempt = sourceLoadAttempt
    isLoadingSources = true
    defer {
      if sourceLoadAttempt == attempt { isLoadingSources = false }
    }
    do {
      let endpoint = try APIEndpoint(path: ["media", "source"], responseContract: .payload)
      let response = try await session.request(
        endpoint, as: [NativeMediaSourceOption].self, requiring: discoveryPermission)
      try session.checkActive(requiring: discoveryPermission)
      guard sourceLoadAttempt == attempt else { return }
      let loaded = response.value.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      sources = loaded
      // 剔除后台已停用的模块来源，防止残留无效筛选条件
      for searchKind in NativeMediaSearchType.allCases {
        let validIDs = Set(loaded.filter { $0.supports(searchKind) }.map(\.id))
        if let existing = selections[searchKind] {
          selections[searchKind] = existing.intersection(validIDs)
        }
      }
      if !availableKinds.contains(kind), let fallback = availableKinds.first {
        kind = fallback
      }
      sourceFailure = false
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled, sourceLoadAttempt == attempt else { return }
      sourceFailure = true
    }
  }

  /// 错误文案不携带令牌、主机地址或任意后端响应正文。
  private static func safeFailure(_ error: Error) -> String {
    switch error {
    case APIError.unauthorized: "登录已过期，请重新登录。"
    case APIError.forbidden, NativeSessionFailure.permissionDenied: "当前账号无法搜索媒体。"
    case APIError.timedOut: "搜索超时，请稍后重试。"
    default: "暂时无法搜索媒体，请检查连接后重试。"
    }
  }

  /// 同一 Cinematic 卡片负责加载/空/错误状态，避免全页切换为网页或纯灰色背景。
  private func statusCard(_ title: String, symbol: String) -> some View {
    CinematicPanel {
      HStack(spacing: 12) {
        Image(systemName: symbol).font(.title3).foregroundStyle(.primary.opacity(0.75))
        Text(title).font(.callout).foregroundStyle(.primary.opacity(0.82))
      }
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .accessibilityElement(children: .combine)
    }
  }
}

/// 搜索结果按媒体类型用海报、人物头像或专辑图呈现，没有图片时显示原生空占位。
@MainActor
private struct NativeMediaSearchRow: View {
  let item: NativeMediaSearchItem
  let sourceNames: [String: String]
  let session: NativeSession
  let onSelect: (() -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// 用最低部署版本支持的比较判断辅助功能动态字号范围。
  private var usesAccessibilityLayout: Bool { dynamicTypeSize >= .accessibility1 }

  /// 有原生详情的结果才呈现可点击行；其余条目保留正常可读性。
  var body: some View {
    Group {
      if let onSelect {
        Button(action: onSelect) { card }.buttonStyle(.plain)
      } else {
        card.accessibilityElement(children: .combine)
      }
    }
    .accessibilityIdentifier("native-media-search-result-\(item.id)")
  }

  /// 常用字号采用海报横卡，不显示右侧冗余箭头按钮，辅助功能字号把图片与文字分行以保留阅读宽度。
  private var card: some View {
    let layout =
      usesAccessibilityLayout
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    return CinematicPanel(padding: 9) {
      layout {
        artwork
        rowText
      }
      .contentShape(Rectangle())
    }
  }

  /// 以标题、元数据、简介、评分的顺序阅读，不用评分抢占标题宽度。
  private var rowText: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(item.displayTitle).font(.headline)
        .lineLimit(usesAccessibilityLayout ? nil : 2)
      if !metadata.isEmpty {
        Text(metadata).font(.caption).foregroundStyle(.secondary)
          .lineLimit(usesAccessibilityLayout ? nil : 1)
      }
      if let overview = item.overview, !overview.isEmpty {
        Text(overview).font(.footnote).foregroundStyle(.primary.opacity(0.78))
          .lineLimit(usesAccessibilityLayout ? nil : 2).multilineTextAlignment(.leading)
      }
      if let rating = item.voteAverage, rating > 0 {
        let score = rating.formatted(.number.precision(.fractionLength(1)))
        Label(score, systemImage: "star.fill")
          .font(.caption.weight(.semibold)).foregroundStyle(.yellow)
          .accessibilityLabel("评分 \(score)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 只显示用户能识别的来源名称，不重复列出接口原始来源与编号。
  private var metadata: String {
    [
      item.displayYear, item.character ?? item.artist,
      (item.mediaSource ?? item.source).flatMap { sourceNames[$0] },
      item.album,
      item.artists?.joined(separator: "、"),
      item.genres.map {
        $0.compactMap(\.name).filter { !$0.isEmpty }.prefix(3).joined(separator: "、")
      },
    ]
    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
  }

  /// 电影/剧集使用 2:3 海报，人物使用圆角头像，音乐采用方形封面比例。
  @ViewBuilder private var artwork: some View {
    let shape = RoundedRectangle(
      cornerRadius: item.resultKind == .person ? 35 : 12, style: .continuous)
    if let reference = item.artworkReference {
      NativeMediaArtwork(
        session: session, reference: reference, role: .poster,
        maximumWidth: Int(artworkSize.width * 2)
      )
      .frame(width: artworkSize.width, height: artworkSize.height)
      .clipShape(shape)
      .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
      .nativeMediaExistsOverlay(
        session: session,
        source: item.detailIdentity?.source ?? item.mediaSource,
        mediaID: item.detailIdentity?.id ?? item.mediaID,
        title: item.displayTitle,
        year: item.displayYear,
        type: item.type?.value,
        enabled: item.resultKind == .media,
        badgeSize: 18,
        inset: 4
      )
    } else {
      artworkPlaceholder(symbol: symbol)
        .frame(width: artworkSize.width, height: artworkSize.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
        .nativeMediaExistsOverlay(
          session: session,
          source: item.detailIdentity?.source ?? item.mediaSource,
          mediaID: item.detailIdentity?.id ?? item.mediaID,
          title: item.displayTitle,
          year: item.displayYear,
          type: item.type?.value,
          enabled: item.resultKind == .media,
          badgeSize: 18,
          inset: 4
        )
        .accessibilityHidden(true)
    }
  }

  /// 极简空白占位框，海报加载前不显示额外背景图与图标。
  private func artworkPlaceholder(symbol: String) -> some View {
    Rectangle()
      .fill(Color.primary.opacity(0.05))
  }

  /// 海报语义由后端 discriminator 决定。
  private var symbol: String {
    switch item.resultKind {
    case .media, .collection: "film"
    case .person: "person.crop.square"
    case .music, .artist: "music.note"
    }
  }

  /// 人物头像/专辑封面方形显示，影视与合集保持参考中的 2:3 海报比例。
  private var artworkSize: CGSize {
    item.resultKind == .person || item.resultKind == .music || item.resultKind == .artist
      ? CGSize(width: 64, height: 64) : CGSize(width: 68, height: 102)
  }
}

/// 媒体库剧集选集播放目标。
private struct NativeLibrarySeriesPickerTarget: Identifiable {
  let id = UUID()
  let title: String
  let server: String?
  let artworkURL: URL?
  let episodesBySeason: [Int: [Int: String]]
}

/// 媒体库电视剧季/集选择播放弹层。
@MainActor
private struct NativeLibraryEpisodesSheet: View {
  let session: NativeSession
  let target: NativeLibrarySeriesPickerTarget

  @State private var selectedSeason: Int
  @State private var launchingEpisodeID: String?
  @State private var feedback: String?
  @Environment(\.dismiss) private var dismiss

  private var seasons: [Int] {
    target.episodesBySeason.keys.sorted { lhs, rhs in
      if lhs == 0 { return false }
      if rhs == 0 { return true }
      return lhs < rhs
    }
  }

  private var episodes: [(number: Int, itemID: String)] {
    (target.episodesBySeason[selectedSeason] ?? [:])
      .map { ($0.key, $0.value) }
      .sorted { $0.number < $1.number }
  }

  init(session: NativeSession, target: NativeLibrarySeriesPickerTarget) {
    self.session = session
    self.target = target
    let sorted = target.episodesBySeason.keys.sorted { lhs, rhs in
      if lhs == 0 { return false }
      if rhs == 0 { return true }
      return lhs < rhs
    }
    _selectedSeason = State(initialValue: sorted.first ?? 1)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            if let feedback {
              CinematicPanel(padding: 10) {
                Text(feedback).font(.caption).foregroundStyle(.orange)
              }
            }
            if seasons.count > 1 {
              ScrollView(.horizontal) {
                HStack(spacing: 8) {
                  ForEach(seasons, id: \.self) { season in
                    let active = selectedSeason == season
                    Button {
                      selectedSeason = season
                    } label: {
                      Text(season == 0 ? "特别篇" : "第 \(season) 季")
                        .font(.caption.weight(active ? .semibold : .medium))
                        .foregroundStyle(active ? .white : .primary.opacity(0.76))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                          Capsule()
                            .fill(
                              active
                                ? NativeAppearanceStore.shared.accentColor
                                : .primary.opacity(0.08))
                        }
                    }
                    .buttonStyle(.plain)
                  }
                }
              }
              .scrollIndicators(.hidden)
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                ForEach(Array(episodes.enumerated()), id: \.element.number) { idx, ep in
                  if idx > 0 { CinematicFormDivider() }
                  Button {
                    Task { await playEpisode(ep) }
                  } label: {
                    HStack(spacing: 12) {
                      Text(String(format: "E%02d", ep.number))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(NativeAppearanceStore.shared.accentColor)
                        .frame(width: 44, alignment: .leading)
                      Text("第 \(ep.number) 集")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                      Spacer()
                      if launchingEpisodeID == ep.itemID {
                        ProgressView().controlSize(.small).tint(.primary)
                      } else {
                        Image(systemName: "play.circle.fill")
                          .font(.title3)
                          .foregroundStyle(NativeAppearanceStore.shared.accentColor)
                      }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .disabled(launchingEpisodeID != nil)
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(target.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .nativeAppearanceRoot()
  }

  private func playEpisode(_ ep: (number: Int, itemID: String)) async {
    launchingEpisodeID = ep.itemID
    feedback = nil
    let seasonPrefix = selectedSeason == 0 ? "S00" : String(format: "S%02d", selectedSeason)
    let epTitle = "\(target.title) \(seasonPrefix)\(String(format: "E%02d", ep.number))"
    dismiss()
    try? await Task.sleep(nanoseconds: 280_000_000)
    let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
      session: session,
      itemID: ep.itemID,
      server: target.server,
      title: epTitle,
      artworkURL: target.artworkURL)
    launchingEpisodeID = nil
    if let err { feedback = err }
  }
}

/// 自动换行的搜索标签流式布局：按可用宽度逐行排布最近搜索词胶囊。
private struct NativeSearchChipsFlowLayout: Layout {
  var horizontalSpacing: CGFloat = 8
  var verticalSpacing: CGFloat = 8

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var totalWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + verticalSpacing
        rowHeight = 0
      }
      x += size.width + horizontalSpacing
      rowHeight = max(rowHeight, size.height)
      totalWidth = max(totalWidth, x - horizontalSpacing)
    }
    return CGSize(
      width: maxWidth.isFinite ? maxWidth : totalWidth,
      height: subviews.isEmpty ? 0 : y + rowHeight
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + verticalSpacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + horizontalSpacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
