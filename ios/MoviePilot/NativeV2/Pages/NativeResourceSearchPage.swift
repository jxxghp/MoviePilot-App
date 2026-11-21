import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生资源搜索目标：既支持从影视详情精确检索，也支持展示最近搜索结果与按关键词检索。
enum NativeResourceSearchTarget: Hashable {
  case lastResults
  case media(identity: NativeMediaIdentity, title: String, season: Int?)
}

/// 原生站点资源搜索与下载确认页：支持站点筛选、画质/免费过滤、排序与显式单次添加下载。
@MainActor
struct NativeResourceSearchPage: View {
  /// 结果本地快捷过滤项。
  private enum QuickFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case free = "免费"
    case uhd = "4K"
    case fhd = "1080p"
    case sub = "中字"

    /// 固定中文标签作为标识。
    var id: String { rawValue }
  }

  /// 结果本地排序维度。
  private enum SortMode: String, CaseIterable, Identifiable {
    case priority = "默认优先级"
    case seeders = "做种最多"
    case sizeDesc = "体积从大到小"

    /// 固定标签标识。
    var id: String { rawValue }
  }

  let session: NativeSession
  let target: NativeResourceSearchTarget

  @State private var keyword = ""
  @State private var sites: [NativeSearchSite] = []
  @State private var selectedSiteIDs: Set<Int> = []
  @State private var results: [NativeResourceContext] = []
  @State private var quickFilter: QuickFilter = .all
  @State private var sortMode: SortMode = .priority
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var activeQueryTerm: String?
  @State private var selectedForDownload: NativeResourceContext?
  @State private var feedback: NativeResourceFeedback?
  @FocusState private var searchFocused: Bool

  /// 采用统一深色紫玫瑰渐变、单行筛选胶囊与透色资源卡，不引入任何 WebView。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if case .lastResults = target {
            searchInputCard
          }
          filterAndSortBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && results.isEmpty {
            ProgressView(loadingMessage)
              .tint(.primary)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && results.isEmpty {
            failureCard
          } else if displayedResults.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 12) {
              ForEach(displayedResults) { item in
                resourceCard(item)
              }
            }
          }
        }
        .frame(maxWidth: 860)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await performSearch() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-resource-search-scroll")
    }
    .navigationTitle(navigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          attempt += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("重新搜索资源")
        .accessibilityIdentifier("native-resource-search-refresh")
      }
    }
    .task(id: attempt) {
      await loadSitesIfNeeded()
      await performSearch()
    }
    .sheet(item: $selectedForDownload) { item in
      NativeDownloadConfirmSheet(
        session: session,
        item: item,
        targetMediaIdentity: targetIdentity
      ) { message in
        feedback = NativeResourceFeedback(isError: false, message: message)
      }
      .nativeAppearanceRoot()
      .presentationDetents([.medium, .large])
    }
  }

  /// 导航标题反映当前检索入口语义。
  private var navigationTitle: String {
    switch target {
    case .lastResults:
      "资源搜索"
    case .media(_, let title, let season):
      if let season { "\(title) S\(String(format: "%02d", season))" } else { "\(title) · 资源" }
    }
  }

  /// 加载文案区分精确检索与缓存读取。
  private var loadingMessage: String {
    switch target {
    case .lastResults:
      activeQueryTerm == nil ? "正在载入最近搜索结果…" : "正在检索站点资源…"
    case .media:
      "正在检索匹配站点资源…"
    }
  }

  /// 若由影视详情进入，向下载确认单传递规范媒体身份。
  private var targetIdentity: NativeMediaIdentity? {
    if case .media(let identity, _, _) = target { return identity }
    return nil
  }

  /// 经本地快捷过滤与排序后的可见资源列表。
  private var displayedResults: [NativeResourceContext] {
    let filtered = results.filter { item in
      switch quickFilter {
      case .all: true
      case .free: item.isFree
      case .uhd: item.pixBadge.contains("2160") || item.pixBadge.uppercased().contains("4K")
      case .fhd: item.pixBadge.contains("1080")
      case .sub: item.hasChineseSubtitle
      }
    }
    switch sortMode {
    case .priority:
      return filtered
    case .seeders:
      return filtered.sorted { ($0.torrent.seeders ?? 0) > ($1.torrent.seeders ?? 0) }
    case .sizeDesc:
      return filtered.sorted { ($0.torrent.size ?? 0) > ($1.torrent.size ?? 0) }
    }
  }

  /// 关键词检索输入卡，支持按站点多选后显式提交。
  private var searchInputCard: some View {
    CinematicPanel(padding: 12) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.primary.opacity(0.65))
        TextField(
          "输入片名或关键词检索站点资源",
          text: $keyword,
          prompt: Text("输入片名或关键词检索站点资源").foregroundColor(.white.opacity(0.45))
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($searchFocused)
        .accessibilityIdentifier("native-resource-search-query")
        .onSubmit { submitKeywordSearch() }
        if !keyword.isEmpty {
          Button {
            keyword = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.primary.opacity(0.55))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清空关键词")
        }
        Button {
          submitKeywordSearch()
        } label: {
          Image(systemName: "arrow.right.circle.fill")
            .font(.title3)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("搜索资源")
        .accessibilityIdentifier("native-resource-search-submit")
      }
    }
  }

  /// 单行快捷过滤、排序与站点多选胶囊栏。
  private var filterAndSortBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(QuickFilter.allCases) { option in
          let selected = quickFilter == option
          Button {
            quickFilter = option
          } label: {
            Text(option.rawValue)
              .font(.subheadline.weight(selected ? .semibold : .regular))
              .foregroundStyle(.primary.opacity(selected ? 0.98 : 0.80))
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .background {
                Capsule()
                  .fill(.white.opacity(selected ? 0.22 : 0.08))
                  .overlay {
                    Capsule().strokeBorder(.primary.opacity(selected ? 0.28 : 0.14), lineWidth: 0.6)
                  }
              }
              .frame(minHeight: 36)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-resource-filter-\(option.rawValue)")
        }
        Menu {
          ForEach(SortMode.allCases) { mode in
            Button {
              sortMode = mode
            } label: {
              if sortMode == mode {
                Label(mode.rawValue, systemImage: "checkmark")
              } else {
                Text(mode.rawValue)
              }
            }
          }
        } label: {
          pillMenuLabel(
            title: sortMode == .priority ? "排序" : sortMode.rawValue, active: sortMode != .priority)
        }
        .tint(.primary)
        .accessibilityIdentifier("native-resource-sort")

        if !sites.isEmpty {
          Menu {
            ForEach(sites) { site in
              let chosen = selectedSiteIDs.contains(site.id)
              Button {
                if chosen {
                  selectedSiteIDs.remove(site.id)
                } else {
                  selectedSiteIDs.insert(site.id)
                }
              } label: {
                if chosen {
                  Label(site.name, systemImage: "checkmark")
                } else {
                  Text(site.name)
                }
              }
            }
            if !selectedSiteIDs.isEmpty {
              Divider()
              Button("全部站点") { selectedSiteIDs.removeAll() }
            }
          } label: {
            pillMenuLabel(
              title: selectedSiteIDs.isEmpty ? "站点" : "站点 \(selectedSiteIDs.count)",
              active: !selectedSiteIDs.isEmpty)
          }
          .tint(.primary)
          .accessibilityIdentifier("native-resource-sites")
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  /// 排序/站点筛选菜单胶囊外观。
  private func pillMenuLabel(title: String, active: Bool) -> some View {
    HStack(spacing: 4) {
      Text(title)
      Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
    }
    .font(.subheadline.weight(active ? .semibold : .regular))
    .foregroundStyle(.primary.opacity(active ? 0.98 : 0.84))
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background {
      Capsule()
        .fill(.white.opacity(active ? 0.22 : 0.08))
        .overlay {
          Capsule().strokeBorder(.primary.opacity(active ? 0.28 : 0.14), lineWidth: 0.6)
        }
    }
    .frame(minHeight: 36)
  }

  /// 单条种子资源透色玻璃卡：站点/促销/规格徽标、标题与副标题、体积/做种统计与下载按钮。
  private func resourceCard(_ item: NativeResourceContext) -> some View {
    CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          if let siteName = item.torrent.siteName, !siteName.isEmpty {
            tagCapsule(
              siteName, fill: Color(red: 0.44, green: 0.34, blue: 0.68).opacity(0.65),
              foreground: .white)
          }
          if let promo = item.promoBadge {
            tagCapsule(
              promo, fill: Color(red: 0.16, green: 0.46, blue: 0.32).opacity(0.75),
              foreground: Color(red: 0.72, green: 0.98, blue: 0.80))
          }
          if !item.pixBadge.isEmpty {
            tagCapsule(item.pixBadge, fill: .white.opacity(0.14), foreground: .white.opacity(0.92))
          }
          if let edition = item.meta?.edition, !edition.isEmpty {
            tagCapsule(edition, fill: .white.opacity(0.10), foreground: .white.opacity(0.82))
          }
          if let seasonEp = item.meta?.seasonEpisode, !seasonEp.isEmpty {
            tagCapsule(seasonEp, fill: .white.opacity(0.10), foreground: .white.opacity(0.86))
          }
          Spacer(minLength: 0)
        }
        Text(item.torrent.title ?? "未命名种子")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(2)
        if let desc = item.torrent.description?.trimmingCharacters(in: .whitespacesAndNewlines),
          !desc.isEmpty
        {
          Text(desc)
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.66))
            .lineLimit(2)
        }
        HStack(spacing: 12) {
          Label(item.sizeText, systemImage: "internaldrive")
          Label("\(item.torrent.seeders ?? 0)", systemImage: "arrow.up")
            .foregroundStyle(Color(red: 0.56, green: 0.92, blue: 0.72))
          if let elapsed = item.torrent.dateElapsed, !elapsed.isEmpty {
            Text(elapsed).foregroundStyle(.primary.opacity(0.56))
          }
          Spacer()
          Button {
            selectedForDownload = item
          } label: {
            Label("下载", systemImage: "arrow.down.circle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(.primary.opacity(0.18))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.26), lineWidth: 0.6) }
              }
              .frame(minHeight: 34)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-resource-download-\(item.id)")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.primary.opacity(0.80))
        .padding(.top, 2)
      }
    }
  }

  /// 紧凑规格与促销标签胶囊。
  private func tagCapsule(_ text: String, fill: Color, foreground: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(foreground)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background { Capsule().fill(fill) }
      .lineLimit(1)
  }

  /// 操作结果提示条。
  private func feedbackBanner(_ feedback: NativeResourceFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
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
    .accessibilityIdentifier("native-resource-feedback")
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "tray")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text(results.isEmpty ? "未找到匹配的站点资源" : "当前筛选条件下没有资源")
          .font(.headline)
        if !results.isEmpty && quickFilter != .all {
          Button("查看全部结果") { quickFilter = .all }
            .frame(minHeight: 44)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 检索失败卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法检索站点资源", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-resource-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 显式提交关键词检索。
  private func submitKeywordSearch() {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    searchFocused = false
    activeQueryTerm = trimmed
    attempt += 1
  }

  /// 读取可用站点列表供站点多选筛选，普通用户若无站点管理权限则静默跳过。
  private func loadSitesIfNeeded() async {
    guard sites.isEmpty,
      let endpoint = try? APIEndpoint(path: ["site"], trailingSlash: true)
    else { return }
    if let loaded = try? await session.request(endpoint, as: [NativeSearchSite].self).value {
      sites = loaded.filter { $0.isActive ?? true }
    }
  }

  /// 按当前入口发起资源搜索或读取最近搜索快照。
  private func performSearch() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    let siteQueryValue =
      selectedSiteIDs.isEmpty
      ? nil : selectedSiteIDs.sorted().map(String.init).joined(separator: ",")
    do {
      let endpoint: APIEndpoint
      switch target {
      case .lastResults:
        if let term = activeQueryTerm, !term.isEmpty {
          var query = [URLQueryItem(name: "keyword", value: term)]
          if let siteQueryValue { query.append(URLQueryItem(name: "sites", value: siteQueryValue)) }
          endpoint = try APIEndpoint(path: ["search", "title"], query: query, timeout: 60)
        } else {
          endpoint = try APIEndpoint(path: ["search", "last"])
        }
      case .media(let identity, _, let season):
        var query = [
          URLQueryItem(name: "media_source", value: identity.source),
          URLQueryItem(name: "mtype", value: identity.type),
        ]
        if let season { query.append(URLQueryItem(name: "season", value: String(season))) }
        if let siteQueryValue { query.append(URLQueryItem(name: "sites", value: siteQueryValue)) }
        endpoint = try APIEndpoint(
          path: ["search", "media", identity.mediaID], query: query, timeout: 90)
      }
      let loaded = try await session.request(
        endpoint, as: [NativeResourceContext].self, requiring: .init(category: .search)
      ).value
      try Task.checkCancellation()
      results = loaded
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }
}

/// 原生下载确认弹层：选择下载器与保存路径后显式单次提交 `POST /api/v1/download/add`。
@MainActor
private struct NativeDownloadConfirmSheet: View {
  let session: NativeSession
  let item: NativeResourceContext
  let targetMediaIdentity: NativeMediaIdentity?
  let onAdded: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var downloaders: [String] = []
  @State private var paths: [NativeDownloadPathOption] = []
  @State private var selectedDownloader = ""
  @State private var selectedPath = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  /// 原生表单弹层保持 Cinematic 渐变与玻璃卡片视觉，绝不自动重试写入。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            CinematicPanel {
              VStack(alignment: .leading, spacing: 8) {
                Text(item.torrent.title ?? "种子资源")
                  .font(.headline)
                HStack(spacing: 10) {
                  if let site = item.torrent.siteName, !site.isEmpty {
                    Text(site)
                  }
                  Text(item.sizeText)
                  Text("做种 \(item.torrent.seeders ?? 0)")
                }
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.68))
              }
            }
            CinematicPanel {
              VStack(alignment: .leading, spacing: 14) {
                HStack {
                  Text("下载器").font(.subheadline.weight(.medium))
                  Spacer()
                  Picker("下载器", selection: $selectedDownloader) {
                    Text("默认下载器").tag("")
                    ForEach(downloaders, id: \.self) { name in
                      Text(name).tag(name)
                    }
                  }
                  .tint(.primary)
                  .accessibilityIdentifier("native-download-confirm-downloader")
                }
                Divider().overlay(.primary.opacity(0.10))
                HStack {
                  Text("保存目录").font(.subheadline.weight(.medium))
                  Spacer()
                  Picker("保存目录", selection: $selectedPath) {
                    Text("默认目录").tag("")
                    ForEach(paths) { option in
                      Text(option.displayLabel).tag(option.submitValue)
                    }
                  }
                  .tint(.primary)
                  .accessibilityIdentifier("native-download-confirm-path")
                }
              }
            }
            if let errorMessage {
              Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.orange)
            }
            CinematicPrimaryAction(
              title: isSubmitting ? "正在添加到下载器…" : "添加到下载",
              symbol: "arrow.down"
            ) {
              Task { await submitDownload() }
            }
            .disabled(isSubmitting)
            .accessibilityIdentifier("native-download-confirm-submit")
          }
          .padding(CinematicStyle.margin)
        }
      }
      .navigationTitle("确认下载")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .accessibilityIdentifier("native-download-confirm-cancel")
        }
      }
      .task { await loadOptions() }
    }
  }

  /// 读取当前实例已启用的下载器与下载路径选项。
  private func loadOptions() async {
    async let clientTask: [NativeConfirmDownloader]? = {
      guard let endpoint = try? APIEndpoint(path: ["download", "clients"]) else { return nil }
      return try? await session.request(endpoint, as: [NativeConfirmDownloader].self).value
    }()
    async let pathTask: [NativeDownloadPathOption]? = {
      guard let endpoint = try? APIEndpoint(path: ["download", "paths"]) else { return nil }
      return try? await session.request(endpoint, as: [NativeDownloadPathOption].self).value
    }()
    let (loadedClients, loadedPaths) = await (clientTask, pathTask)
    downloaders = (loadedClients ?? []).map(\.name)
    paths = loadedPaths ?? []
  }

  /// 显式单次提交 `POST /api/v1/download/add`，透传完整种子字段与可选媒体身份。
  private func submitDownload() async {
    isSubmitting = true
    errorMessage = nil
    defer { isSubmitting = false }
    do {
      let body = try JSONEncoder().encode(
        NativeDownloadAddRequest(
          torrentIn: item.torrent,
          mediaSource: targetMediaIdentity?.source ?? item.torrent.mediaSource,
          mediaID: targetMediaIdentity?.mediaID ?? item.torrent.mediaID,
          downloader: selectedDownloader.isEmpty ? nil : selectedDownloader,
          savePath: selectedPath.isEmpty ? nil : selectedPath))
      let endpoint = try APIEndpoint(path: ["download", "add"], method: .post, body: body)
      try await session.perform(endpoint, requiring: .init(category: .search))
      try Task.checkCancellation()
      onAdded("已提交至下载队列。")
      dismiss()
    } catch is CancellationError {
      return
    } catch {
      errorMessage = "添加下载失败，请检查下载器状态后重试。"
    }
  }
}

/// 资源页轻量提示载体。
private struct NativeResourceFeedback {
  let isError: Bool
  let message: String
}

/// 站点筛选条目投影。
private struct NativeSearchSite: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let isActive: Bool?

  /// 对应站点 `is_active` 字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case isActive = "is_active"
  }
}

/// 确认弹层内的下载器选项。
private struct NativeConfirmDownloader: Decodable, Sendable {
  let name: String
}

/// `GET /api/v1/download/paths` 路径选项。
private struct NativeDownloadPathOption: Decodable, Sendable, Identifiable {
  let name: String?
  let savePath: String?
  let downloadPath: String?

  /// 使用路径值作为稳定键。
  var id: String { submitValue }

  /// 提交给后端 `save_path` 的规范值。
  var submitValue: String {
    if let name, !name.isEmpty { return name }
    return savePath ?? downloadPath ?? ""
  }

  /// 展示给用户的可读路径名称。
  var displayLabel: String {
    if let name, !name.isEmpty { return name }
    return downloadPath ?? savePath ?? "默认目录"
  }

  /// 对应 `DownloadDirectory` 字段。
  private enum CodingKeys: String, CodingKey {
    case name
    case savePath = "save_path"
    case downloadPath = "download_path"
  }
}

/// `POST /api/v1/download/add` 写入载荷。
private struct NativeDownloadAddRequest: Encodable {
  let torrentIn: NativeTorrentPayload
  let mediaSource: String?
  let mediaID: String?
  let downloader: String?
  let savePath: String?

  /// 对应后端参数名称。
  private enum CodingKeys: String, CodingKey {
    case torrentIn = "torrent_in"
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case downloader
    case savePath = "save_path"
  }
}

/// `search/last`、`search/media` 与 `search/title` 返回的单条上下文结果。
private struct NativeResourceContext: Decodable, Sendable, Identifiable {
  /// 识别出的规格元数据。
  struct Meta: Decodable, Sendable {
    let resourcePix: String?
    let videoEncode: String?
    let audioEncode: String?
    let edition: String?
    let seasonEpisode: String?

    /// 对应 `MetaInfo` 字段。
    private enum CodingKeys: String, CodingKey {
      case resourcePix = "resource_pix"
      case videoEncode = "video_encode"
      case audioEncode = "audio_encode"
      case edition
      case seasonEpisode = "season_episode"
    }
  }

  let torrent: NativeTorrentPayload
  let meta: Meta?

  /// 对完整站点与链接/标题计算 64 位 FNV-1a 摘要，避免同站点长链接前缀碰撞导致列表折叠。
  var id: String {
    let raw =
      "\(torrent.site ?? 0)|\(torrent.enclosure ?? "")|\(torrent.pageURL ?? "")|\(torrent.title ?? "")|\(Int(torrent.size ?? 0))"
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in raw.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }

  /// 是否免费下载（下载系数为 0）。
  var isFree: Bool { (torrent.downloadVolumeFactor ?? 1.0) == 0 }

  /// 促销标签文案。
  var promoBadge: String? {
    let dl = torrent.downloadVolumeFactor ?? 1.0
    let ul = torrent.uploadVolumeFactor ?? 1.0
    if dl == 0 && ul >= 2 { return "2X免费" }
    if dl == 0 { return "免费" }
    if dl > 0 && dl < 1 { return "\(Int((dl * 100).rounded()))%" }
    return nil
  }

  /// 分辨率短标签。
  var pixBadge: String { meta?.resourcePix ?? "" }

  /// 判断是否携带中文字幕标签。
  var hasChineseSubtitle: Bool {
    if (torrent.labels ?? []).contains(where: { $0.contains("中") }) { return true }
    let text = "\(torrent.title ?? "") \(torrent.description ?? "")"
    return text.contains("中字") || text.contains("简繁")
  }

  /// 可读文件大小。
  var sizeText: String {
    guard let bytes = torrent.size, bytes > 0 else { return "未知大小" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = bytes
    var index = 0
    while value >= 1024 && index < units.count - 1 {
      value /= 1024
      index += 1
    }
    return String(format: "%.1f %@", value, units[index])
  }

  /// 对应 `_SchemaContext` 顶层字段。
  private enum CodingKeys: String, CodingKey {
    case torrent = "torrent_info"
    case meta = "meta_info"
  }
}

/// 完整种子信息模型，同时支持搜索解码与提交下载编码。
private struct NativeTorrentPayload: Codable, Sendable {
  let site: Int?
  let siteName: String?
  let siteCookie: String?
  let siteUA: String?
  let siteProxy: Bool?
  let siteOrder: Int?
  let title: String?
  let description: String?
  let imdbid: String?
  let enclosure: String?
  let pageURL: String?
  let size: Double?
  let seeders: Int?
  let peers: Int?
  let grabs: Int?
  let pubdate: String?
  let dateElapsed: String?
  let freedate: String?
  let uploadVolumeFactor: Double?
  let downloadVolumeFactor: Double?
  let hitAndRun: Bool?
  let labels: [String]?
  let priOrder: Int?
  let mediaSource: String?
  let mediaID: String?

  /// 匹配 `_SchemaTorrentInfo` snake_case 契约。
  private enum CodingKeys: String, CodingKey {
    case site
    case siteName = "site_name"
    case siteCookie = "site_cookie"
    case siteUA = "site_ua"
    case siteProxy = "site_proxy"
    case siteOrder = "site_order"
    case title
    case description
    case imdbid
    case enclosure
    case pageURL = "page_url"
    case size
    case seeders
    case peers
    case grabs
    case pubdate
    case dateElapsed = "date_elapsed"
    case freedate
    case uploadVolumeFactor = "uploadvolumefactor"
    case downloadVolumeFactor = "downloadvolumefactor"
    case hitAndRun = "hit_and_run"
    case labels
    case priOrder = "pri_order"
    case mediaSource = "media_source"
    case mediaID = "media_id"
  }
}
