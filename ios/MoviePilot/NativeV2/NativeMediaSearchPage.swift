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

/// 搜索页面所支持的后端公开 `type` 参数集合。
private enum NativeMediaSearchType: String, CaseIterable, Identifiable, Hashable, Sendable {
  case media
  case person
  case music
  case collection

  /// 页面分组顺序和 ID 均固定，不依赖响应下标。
  var id: String { rawValue }

  /// 使用用户熟悉的媒体分类标签。
  var title: String {
    switch self {
    case .media: "影视"
    case .person: "人物"
    case .music: "音乐"
    case .collection: "合集"
    }
  }
}

/// 已提交检索的完整条件；查看后续页时草稿文本和筛选变化不会影响这一快照。
private struct NativeMediaSearchQuery: Equatable {
  let term: String
  let kind: NativeMediaSearchType
  let sources: [String]
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
  @State private var query: String
  @State private var kind: NativeMediaSearchType = .media
  @State private var sources: [NativeMediaSourceOption] = []
  @State private var selections: [NativeMediaSearchType: Set<String>] = [:]
  @State private var results: [NativeMediaSearchItem] = []
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
  @FocusState private var searchFocused: Bool

  /// 搜索详情回调只传输受控来源和原生 ID，不传自由 URL。
  init(
    session: NativeSession, initialQuery: String = "",
    onSelect: @escaping (String, String?, String?) -> Void = { _, _, _ in }
  ) {
    self.session = session
    self.onSelect = onSelect
    _query = State(initialValue: initialQuery)
  }

  /// 搜索条件与结果共享 Cinematic 渐变和透色玻璃；网络错误不会切回网页或丢失筛选。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          searchControls
          if let failure {
            statusCard(failure, symbol: "exclamationmark.triangle")
            if let committedQuery {
              CinematicPrimaryAction(title: "重试搜索", symbol: "arrow.clockwise") {
                startRequest(for: committedQuery, page: loadedPage == 0 ? 1 : loadedPage + 1)
              }
              .accessibilityIdentifier("native-media-search-retry")
            }
          }
          if !results.isEmpty {
            if trimmedQuery != committedQuery?.term, let term = committedQuery?.term {
              Text("“\(term)”的搜索结果").font(.subheadline).foregroundStyle(.secondary)
            }
            resultsContent
            if isSearching, loadedPage > 0 {
              ProgressView("正在加载…")
                .frame(maxWidth: .infinity, minHeight: 44)
            }
          } else if failure == nil {
            if isSearching {
              statusCard("正在搜索…", symbol: "magnifyingglass")
            } else if loadedPage > 0 {
              statusCard("没有找到相关结果", symbol: "sparkle.magnifyingglass")
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
    .onAppear(perform: beginInitialSearchIfNeeded)
    .onDisappear(perform: cancelSearch)
    .onChange(of: query) { value in
      if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { clearResults() }
    }
  }

  /// 原生关键词、类型和来源筛选在单块低遮罩玻璃面板中保持紧凑。
  private var searchControls: some View {
    CinematicPanel(padding: 14) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
          TextField("搜索电影、剧集、人物或音乐", text: $query)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.search).focused($searchFocused)
            .onSubmit { submitSearch() }
            .accessibilityLabel("搜索关键词")
            .accessibilityIdentifier("native-media-search-query")
          if !query.isEmpty {
            Button {
              query = ""
              clearResults()
              searchFocused = true
            } label: {
              Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("清除搜索")
          }
          Button(action: submitSearch) {
            if isSearching, loadedPage == 0, committedQuery?.term == trimmedQuery {
              ProgressView().tint(.white).frame(width: 44, height: 44)
            } else {
              Image(systemName: "arrow.right.circle.fill").font(.title3).frame(
                width: 44, height: 44)
            }
          }
          .buttonStyle(.plain).disabled(trimmedQuery.isEmpty)
          .accessibilityLabel("搜索")
          .accessibilityIdentifier("native-media-search-submit")
        }

        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(NativeMediaSearchType.allCases) { option in
              Button {
                guard kind != option else { return }
                kind = option
                submitSearch()
              } label: {
                Text(option.title)
                  .font(.subheadline.weight(kind == option ? .semibold : .regular))
                  .foregroundStyle(.white.opacity(kind == option ? 0.98 : 0.80))
                  .padding(.horizontal, 14).frame(minHeight: 36)
                  .background {
                    Capsule()
                      .fill(.white.opacity(kind == option ? 0.22 : 0.08))
                      .overlay {
                        Capsule().strokeBorder(
                          .white.opacity(kind == option ? 0.28 : 0.14), lineWidth: 0.6)
                      }
                  }
                  .frame(minHeight: 44).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(kind == option ? .isSelected : [])
              .accessibilityIdentifier("native-media-search-kind-\(option.rawValue)")
            }
            sourceMenu
          }
        }
        .scrollIndicators(.hidden)
      }
    }
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
            if selectedSources.contains(source.id) {
              Label(source.name, systemImage: "checkmark")
            } else {
              Text(source.name)
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
      .foregroundStyle(.white.opacity(selectedSources.isEmpty ? 0.86 : 0.98))
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
    .tint(.white)
    .disabled(isLoadingSources)
    .accessibilityIdentifier("native-media-search-sources")
  }

  /// 每个分类独立保留来源，避免切换分类后把内置音乐来源发送给影视搜索。
  private var selectedSources: Set<String> { selections[kind] ?? [] }

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
                onSelect: item.detailIdentity.map { identity in
                  { onSelect(identity.source, identity.id, identity.type) }
                }
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

  /// 参照 Cinematic 全局搜索的人物圆形头像横栏，保留名字与角色副标。
  private func personTile(_ item: NativeMediaSearchItem) -> some View {
    VStack(spacing: 6) {
      Group {
        if let reference = item.artworkReference {
          NativeMediaArtwork(
            session: session, reference: reference, role: .poster, maximumWidth: 160)
        } else {
          ZStack {
            Circle().fill(.white.opacity(0.10))
            Image(systemName: "person.fill").font(.title2).foregroundStyle(.white.opacity(0.55))
          }
        }
      }
      .frame(width: 72, height: 72)
      .clipShape(Circle())
      .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.6) }
      Text(item.displayTitle).font(.caption.weight(.medium)).lineLimit(1)
      if let role = item.character, !role.isEmpty {
        Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
    }
    .frame(width: 78)
    .multilineTextAlignment(.center)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("native-media-search-result-\(item.id)")
  }

  /// 来源目录用于可读的标签；没有目录名称时不展示内部标识。
  private var sourceNames: [String: String] {
    Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
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

  /// 提交时同步记录关键词、类型和来源，后续页面不会混入编辑中的条件。
  private func submitSearch() {
    guard !trimmedQuery.isEmpty else { return }
    searchFocused = false
    let criteria = NativeMediaSearchQuery(
      term: trimmedQuery, kind: kind, sources: selectedSources.sorted())
    guard !isSearching || committedQuery != criteria || loadedPage > 0 else { return }
    clearResults()
    committedQuery = criteria
    startRequest(for: criteria, page: 1)
  }

  /// 清空时同时丢弃分页和错误状态，防止迟到响应再次显示旧结果。
  private func clearResults() {
    cancelSearch()
    committedQuery = nil
    results = []
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

  /// 接近结果尾部时自动续页；失败页等待明确重试，不循环发送同一请求。
  private func requestNextPageIfNeeded(afterShowing id: String) {
    guard let committedQuery, hasMore, loadedPage > 0, failure == nil,
      results.suffix(3).contains(where: { $0.id == id })
    else { return }
    startRequest(for: committedQuery, page: loadedPage + 1)
  }

  /// 获取真实来源目录；目录失败不阻止未筛选的核心搜索。
  private func loadSources() async {
    let attempt = sourceLoadAttempt
    isLoadingSources = true
    defer {
      if sourceLoadAttempt == attempt { isLoadingSources = false }
    }
    do {
      let endpoint = try APIEndpoint(path: ["media", "source"])
      let response = try await session.request(
        endpoint, as: [NativeMediaSourceOption].self, requiring: discoveryPermission)
      try session.checkActive(requiring: discoveryPermission)
      guard sourceLoadAttempt == attempt else { return }
      sources = response.value.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
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
        Image(systemName: symbol).font(.title3).foregroundStyle(.white.opacity(0.75))
        Text(title).font(.callout).foregroundStyle(.white.opacity(0.82))
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

  /// 常用字号采用海报横卡，辅助功能字号把图片与文字分行以保留阅读宽度。
  private var card: some View {
    let layout =
      usesAccessibilityLayout
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    return CinematicPanel(padding: 9) {
      layout {
        artwork
        rowText
        if onSelect != nil {
          Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            .foregroundStyle(.secondary).accessibilityHidden(true)
        }
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
        Text(overview).font(.footnote).foregroundStyle(.white.opacity(0.78))
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
      .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
    } else {
      artworkPlaceholder(symbol: symbol)
        .frame(width: artworkSize.width, height: artworkSize.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
  }

  /// 缺图只用明确占位，不将远端或演示图片冒充真实媒体海报。
  private func artworkPlaceholder(symbol: String) -> some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.36, green: 0.28, blue: 0.43),
          Color(red: 0.24, green: 0.25, blue: 0.34),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: symbol).font(.title3).foregroundStyle(.white.opacity(0.62))
    }
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
