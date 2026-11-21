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

/// 原生站点资源搜索页（十.3）：对标 Web 9 维级联多选筛选（站点/季集/来源/字幕/优惠/编码/版本/分辨率/制作组）、多字段升降序排序；移除卡片内下载按钮，点击整张卡片弹出重构后的满宽下载确认窗。
@MainActor
struct NativeResourceSearchPage: View {
  private enum SortField: String, CaseIterable, Identifiable {
    case defaultPriority = "默认优先级"
    case site = "站点"
    case size = "体积"
    case seeder = "做种"
    case pubdate = "发布时间"
    var id: String { rawValue }
  }

  let session: NativeSession
  let target: NativeResourceSearchTarget

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var keyword = ""
  @State private var sites: [NativeSearchSite] = []
  @State private var querySiteIDs: Set<Int> = []
  @State private var results: [NativeResourceContext] = []

  // 9 维级联多选筛选状态（对齐 Web TorrentCardListView.vue）
  @State private var filter = NativeResourceFacetFilter()
  @State private var sortField: SortField = .defaultPriority
  @State private var sortDescending = true
  @State private var showsAllFiltersSheet = false

  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var activeQueryTerm: String?
  @State private var selectedForDownload: NativeResourceContext?
  @State private var feedback: NativeResourceFeedback?
  @FocusState private var searchFocused: Bool

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if case .lastResults = target {
            searchInputCard
          }
          if !results.isEmpty || filter.activeCount > 0 {
            cascadingFilterBar
          }
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && results.isEmpty {
            NativeCardListSkeletonView(count: 5, style: .posterRow)
              .transition(.opacity)
          } else if loadFailed && results.isEmpty {
            failureCard
          } else if displayedResults.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 11) {
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
      ToolbarItemGroup(placement: .topBarTrailing) {
        if !results.isEmpty {
          Menu {
            Section("排序依据") {
              ForEach(SortField.allCases) { field in
                Button {
                  sortField = field
                } label: {
                  if sortField == field {
                    Label(field.rawValue, systemImage: "checkmark")
                  } else {
                    Text(field.rawValue)
                  }
                }
              }
            }
            Section("排序方向") {
              Button {
                sortDescending = true
              } label: {
                if sortDescending { Label("降序", systemImage: "checkmark") } else { Text("降序") }
              }
              Button {
                sortDescending = false
              } label: {
                if !sortDescending { Label("升序", systemImage: "checkmark") } else { Text("升序") }
              }
            }
          } label: {
            Image(
              systemName: sortField == .defaultPriority && sortDescending
                ? "arrow.up.arrow.down.circle" : "arrow.up.arrow.down.circle.fill")
          }
          .tint(.primary)
          .accessibilityLabel("排序方式")
          .accessibilityIdentifier("native-resource-search-sort-menu")

          Button {
            showsAllFiltersSheet = true
          } label: {
            Image(
              systemName: filter.activeCount > 0
                ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
          }
          .tint(.primary)
          .accessibilityLabel("全部筛选条件")
          .accessibilityIdentifier("native-resource-search-filter-menu")
        }
      }
    }
    .task(id: attempt) {
      await loadSitesIfNeeded()
      await performSearch()
    }
    .sheet(isPresented: $showsAllFiltersSheet) {
      NativeResourceAllFiltersSheet(results: results, filter: $filter)
    }
    .sheet(item: $selectedForDownload) { item in
      NativeDownloadConfirmSheet(
        session: session,
        item: item,
        targetMediaIdentity: targetIdentity
      ) { message in
        feedback = NativeResourceFeedback(isError: false, message: message)
      }
      .nativeGlassSheet()
      .presentationDetents([.fraction(2.0 / 3.0), .large])
      .presentationDragIndicator(.visible)
    }
  }

  private var navigationTitle: String {
    switch target {
    case .lastResults:
      results.isEmpty ? "站点资源" : "站点资源 (\(displayedResults.count))"
    case .media(_, let title, let season):
      if let season { "\(title) S\(String(format: "%02d", season))" } else { "\(title) · 资源" }
    }
  }

  private var loadingMessage: String {
    switch target {
    case .lastResults:
      activeQueryTerm == nil ? "正在载入最近搜索结果…" : "正在检索站点资源…"
    case .media:
      "正在检索匹配站点资源…"
    }
  }

  private var targetIdentity: NativeMediaIdentity? {
    if case .media(let identity, _, _) = target { return identity }
    return nil
  }

  private var fallbackTargetTitle: String? {
    if case .media(_, let title, _) = target, !title.isEmpty { return title }
    return nil
  }

  private var displayedResults: [NativeResourceContext] {
    let filtered = results.filter { filter.matches($0) }
    switch sortField {
    case .defaultPriority:
      return sortDescending ? filtered : filtered.reversed()
    case .site:
      return filtered.sorted { lhs, rhs in
        let l = lhs.torrent.siteName ?? ""
        let r = rhs.torrent.siteName ?? ""
        return sortDescending ? l < r : l > r
      }
    case .size:
      return filtered.sorted { lhs, rhs in
        let l = lhs.torrent.size ?? 0
        let r = rhs.torrent.size ?? 0
        return sortDescending ? l > r : l < r
      }
    case .seeder:
      return filtered.sorted { lhs, rhs in
        let l = lhs.torrent.seeders ?? 0
        let r = rhs.torrent.seeders ?? 0
        return sortDescending ? l > r : l < r
      }
    case .pubdate:
      return filtered.sorted { lhs, rhs in
        let l = lhs.torrent.pubdate ?? ""
        let r = rhs.torrent.pubdate ?? ""
        return sortDescending ? l > r : l < r
      }
    }
  }

  /// 关键词检索输入卡，支持指定检索站点范围。
  private var searchInputCard: some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("输入片名或关键词检索站点资源", text: $keyword)
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
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
        if !sites.isEmpty {
          Menu {
            ForEach(sites) { site in
              Button {
                if querySiteIDs.contains(site.id) {
                  querySiteIDs.remove(site.id)
                } else {
                  querySiteIDs.insert(site.id)
                }
              } label: {
                if querySiteIDs.contains(site.id) {
                  Label(site.name, systemImage: "checkmark")
                } else {
                  Text(site.name)
                }
              }
            }
            if !querySiteIDs.isEmpty {
              Divider()
              Button("全部站点") { querySiteIDs.removeAll() }
            }
          } label: {
            Text(querySiteIDs.isEmpty ? "全站" : "\(querySiteIDs.count)站")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(querySiteIDs.isEmpty ? NativeTheme.chipText : .white)
              .padding(.horizontal, 8).padding(.vertical, 4)
              .background(
                querySiteIDs.isEmpty ? NativeTheme.chipFill : appearance.accentColor, in: Capsule())
          }
        }
        Button {
          submitKeywordSearch()
        } label: {
          Image(systemName: "arrow.right.circle.fill")
            .font(.title3)
            .foregroundStyle(
              keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .secondary.opacity(0.4) : appearance.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("native-resource-search-submit")
      }
    }
  }

  /// 对标 Web 9 维级联多选过滤条：全部筛选入口 + 站点/优惠/分辨率/字幕/版本/编码/季集/来源/制作组（排序已置于右上角工具栏）。
  private var cascadingFilterBar: some View {
    let facets = NativeResourceFacetOptions(from: results, currentFilter: filter)
    return ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 7) {
        Button {
          showsAllFiltersSheet = true
        } label: {
          NativeAdaptivePill(
            filter.activeCount > 0 ? "筛选 (\(filter.activeCount))" : "全部筛选",
            symbol: "slider.horizontal.3",
            isSelected: filter.activeCount > 0
          )
        }
        .buttonStyle(.plain)

        if filter.activeCount > 0 {
          Button {
            filter.clearAll()
          } label: {
            NativeAdaptivePill("重置", symbol: "xmark", isSelected: false, tint: NativeTheme.danger)
          }
          .buttonStyle(.plain)
        }

        facetMenuPill(title: "站点", options: facets.sites, selection: $filter.sites)
        facetMenuPill(title: "促销", options: facets.freeStates, selection: $filter.freeStates)
        facetMenuPill(title: "分辨率", options: facets.resolutions, selection: $filter.resolutions)
        facetMenuPill(title: "字幕", options: facets.subtitles, selection: $filter.subtitles)
        facetMenuPill(title: "版本", options: facets.editions, selection: $filter.editions)
        facetMenuPill(title: "编码", options: facets.videoCodes, selection: $filter.videoCodes)
        facetMenuPill(title: "季集", options: facets.seasons, selection: $filter.seasons)
        facetMenuPill(title: "来源", options: facets.webSources, selection: $filter.webSources)
        facetMenuPill(title: "制作组", options: facets.releaseGroups, selection: $filter.releaseGroups)
      }
      .padding(.vertical, 2)
    }
  }

  @ViewBuilder
  private func facetMenuPill(
    title: String, options: [String], selection: Binding<Set<String>>
  ) -> some View {
    if !options.isEmpty {
      let count = selection.wrappedValue.count
      Menu {
        ForEach(options, id: \.self) { opt in
          let chosen = selection.wrappedValue.contains(opt)
          Button {
            if chosen {
              selection.wrappedValue.remove(opt)
            } else {
              selection.wrappedValue.insert(opt)
            }
          } label: {
            if chosen { Label(opt, systemImage: "checkmark") } else { Text(opt) }
          }
        }
        if count > 0 {
          Divider()
          Button("清空\(title)") { selection.wrappedValue.removeAll() }
        }
      } label: {
        NativeAdaptivePill(
          count > 0 ? "\(title) \(count)" : title,
          isSelected: count > 0
        )
      }
    }
  }

  /// 整张卡片即可点击弹出下载确认窗（顶部标明所属识别媒体，去除卡片内部多余下载按钮）。
  private func resourceCard(_ item: NativeResourceContext) -> some View {
    let mediaHeading = item.recognizedMediaTitle ?? fallbackTargetTitle
    return Button {
      selectedForDownload = item
    } label: {
      CinematicPanel(padding: 13) {
        VStack(alignment: .leading, spacing: 8) {
          if let mediaHeading, !mediaHeading.isEmpty {
            HStack(spacing: 8) {
              if let poster = item.recognizedPosterReference {
                NativeMediaArtwork(
                  session: session, reference: poster, role: .poster, maximumWidth: 120
                )
                .frame(width: 24, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
              } else {
                Image(systemName: item.recognizedMediaSymbol)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(appearance.accentColor)
                  .frame(width: 24, height: 24)
              }
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(mediaHeading)
                  .font(.footnote.weight(.semibold))
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                if let year = item.recognizedMediaYear, !year.isEmpty {
                  Text(year)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
              }
              Spacer(minLength: 4)
              if let typeLabel = item.recognizedMediaType, !typeLabel.isEmpty {
                NativeAdaptiveBadge(typeLabel, tint: NativeTheme.brand)
              }
            }
            Divider().overlay(NativeTheme.divider)
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              if let siteName = item.torrent.siteName, !siteName.isEmpty {
                NativeAdaptiveBadge(siteName, tint: appearance.accentColor, filled: true)
              }
              if let promo = item.promoBadge {
                NativeAdaptiveBadge(promo, tint: NativeTheme.success)
              }
              if item.torrent.hitAndRun == true {
                NativeAdaptiveBadge("H&R", tint: NativeTheme.danger)
              }
              if !item.pixBadge.isEmpty {
                NativeAdaptiveBadge(item.pixBadge, tint: NativeTheme.info)
              }
              if let edition = item.meta?.edition, !edition.isEmpty {
                NativeAdaptiveBadge(edition)
              }
              if let codec = item.meta?.videoEncode, !codec.isEmpty {
                NativeAdaptiveBadge(codec)
              }
              if let seasonEp = item.meta?.seasonEpisode, !seasonEp.isEmpty {
                NativeAdaptiveBadge(seasonEp, tint: NativeTheme.brand)
              }
              if item.hasChineseSubtitle {
                NativeAdaptiveBadge("中字", tint: NativeTheme.warning)
              }
            }
          }
          Text(item.torrent.title ?? "未命名种子")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
          if let desc = item.torrent.description?.trimmingCharacters(in: .whitespacesAndNewlines),
            !desc.isEmpty
          {
            Text(desc)
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.leading)
              .lineLimit(2)
          }
          HStack(spacing: 14) {
            Label(item.sizeText, systemImage: "internaldrive")
            Label("\(item.torrent.seeders ?? 0)", systemImage: "arrow.up")
              .foregroundStyle(NativeTheme.success)
            if let peers = item.torrent.peers, peers > 0 {
              Label("\(peers)", systemImage: "arrow.down")
                .foregroundStyle(NativeTheme.pink)
            }
            if let elapsed = item.torrent.dateElapsed, !elapsed.isEmpty {
              Text(elapsed).foregroundStyle(.secondary)
            }
            Spacer()
            if let team = item.meta?.resourceTeam, !team.isEmpty {
              Text(team)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-resource-download-\(item.id)")
  }

  private func feedbackBanner(_ feedback: NativeResourceFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary)
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-resource-feedback")
  }

  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
        Text(results.isEmpty ? "未找到匹配的站点资源" : "当前筛选条件下没有资源").font(.headline)
        if !results.isEmpty && filter.activeCount > 0 {
          Button("清空筛选条件") { filter.clearAll() }.frame(minHeight: 40)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法检索站点资源", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }.frame(minHeight: 44)
          .accessibilityIdentifier("native-resource-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func submitKeywordSearch() {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    searchFocused = false
    activeQueryTerm = trimmed
    filter.clearAll()
    attempt += 1
  }

  private func loadSitesIfNeeded() async {
    guard sites.isEmpty,
      let endpoint = try? APIEndpoint(path: ["site"], trailingSlash: true)
    else { return }
    if let loaded = try? await session.request(endpoint, as: [NativeSearchSite].self).value {
      sites = loaded.filter { $0.isActive ?? true }
    }
  }

  private func performSearch() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    let siteQueryValue =
      querySiteIDs.isEmpty ? nil : querySiteIDs.sorted().map(String.init).joined(separator: ",")
    do {
      let endpoint: APIEndpoint
      switch target {
      case .lastResults:
        if let term = activeQueryTerm, !term.isEmpty {
          var query = [URLQueryItem(name: "keyword", value: term)]
          if let siteQueryValue { query.append(URLQueryItem(name: "sites", value: siteQueryValue)) }
          endpoint = try APIEndpoint(
            path: ["search", "title"], query: query, maximumResponseBytes: 12 * 1024 * 1024,
            timeout: 90)
        } else {
          endpoint = try APIEndpoint(
            path: ["search", "last"], maximumResponseBytes: 12 * 1024 * 1024, timeout: 30)
        }
      case .media(let identity, _, let season):
        var query = [
          URLQueryItem(name: "media_source", value: identity.source),
          URLQueryItem(name: "mtype", value: identity.type),
        ]
        if let season { query.append(URLQueryItem(name: "season", value: String(season))) }
        if let siteQueryValue { query.append(URLQueryItem(name: "sites", value: siteQueryValue)) }
        endpoint = try APIEndpoint(
          path: ["search", "media", identity.mediaID], query: query,
          maximumResponseBytes: 12 * 1024 * 1024, timeout: 90)
      }
      let envelope = try await session.request(
        endpoint, as: NativeResourceSearchEnvelope.self, requiring: .init(category: .search)
      ).value
      try Task.checkCancellation()
      results = envelope.items
      if envelope.items.isEmpty, let msg = envelope.message, !msg.isEmpty, envelope.success == false
      {
        feedback = NativeResourceFeedback(isError: false, message: msg)
      }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }
}

// MARK: - 9 维全量筛选弹层

@MainActor
private struct NativeResourceAllFiltersSheet: View {
  let results: [NativeResourceContext]
  @Binding var filter: NativeResourceFacetFilter
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let facets = NativeResourceFacetOptions(from: results, currentFilter: filter)
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            facetGroup("站点", options: facets.sites, selection: $filter.sites)
            facetGroup("促销优惠", options: facets.freeStates, selection: $filter.freeStates)
            facetGroup("分辨率", options: facets.resolutions, selection: $filter.resolutions)
            facetGroup("字幕", options: facets.subtitles, selection: $filter.subtitles)
            facetGroup("质量版本", options: facets.editions, selection: $filter.editions)
            facetGroup("视频编码", options: facets.videoCodes, selection: $filter.videoCodes)
            facetGroup("季集", options: facets.seasons, selection: $filter.seasons)
            facetGroup("流媒体来源", options: facets.webSources, selection: $filter.webSources)
            facetGroup("制作组", options: facets.releaseGroups, selection: $filter.releaseGroups)
          }
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        }
      }
      .navigationTitle("全部筛选 (\(filter.activeCount))")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("重置") { filter.clearAll() }
            .tint(.primary)
            .disabled(filter.activeCount == 0)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("完成") { dismiss() }
            .fontWeight(.semibold)
            .tint(.primary)
        }
      }
    }
    .nativeGlassSheet()
  }

  @ViewBuilder
  private func facetGroup(
    _ title: String, options: [String], selection: Binding<Set<String>>
  ) -> some View {
    if !options.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.footnote.weight(.medium)).foregroundStyle(.secondary).padding(
          .horizontal, 4)
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8
        ) {
          ForEach(options, id: \.self) { opt in
            let chosen = selection.wrappedValue.contains(opt)
            Button {
              if chosen {
                selection.wrappedValue.remove(opt)
              } else {
                selection.wrappedValue.insert(opt)
              }
            } label: {
              NativeAdaptivePill(opt, isSelected: chosen)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

// MARK: - 重构后的满宽下载确认弹层（对标 Web AddDownloadDialog.vue）

@MainActor
private struct NativeDownloadConfirmSheet: View {
  let session: NativeSession
  let item: NativeResourceContext
  let targetMediaIdentity: NativeMediaIdentity?
  let onAdded: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var downloaders: [String] = []
  @State private var paths: [NativeDownloadPathOption] = []
  @State private var selectedDownloader = ""
  @State private var selectedPath = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            // 满宽种子详情摘要卡片
            CinematicPanel(padding: 15) {
              VStack(alignment: .leading, spacing: 10) {
                if let mediaTitle = item.recognizedMediaTitle, !mediaTitle.isEmpty {
                  HStack(spacing: 10) {
                    if let poster = item.recognizedPosterReference {
                      NativeMediaArtwork(
                        session: session, reference: poster, role: .poster, maximumWidth: 160
                      )
                      .frame(width: 34, height: 48)
                      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                      Image(systemName: item.recognizedMediaSymbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(appearance.accentColor)
                        .frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                      Text(mediaTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                      let metaParts = [
                        item.recognizedMediaType, item.recognizedMediaYear,
                        item.meta?.seasonEpisode,
                      ].compactMap { $0 }.filter { !$0.isEmpty }
                      if !metaParts.isEmpty {
                        Text(metaParts.joined(separator: " · "))
                          .font(.caption)
                          .foregroundStyle(.secondary)
                      }
                    }
                    Spacer(minLength: 0)
                  }
                  Divider().overlay(NativeTheme.divider)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 6) {
                    if let site = item.torrent.siteName, !site.isEmpty {
                      NativeAdaptiveBadge(site, tint: appearance.accentColor, filled: true)
                    }
                    if let promo = item.promoBadge {
                      NativeAdaptiveBadge(promo, tint: NativeTheme.success)
                    }
                    if !item.pixBadge.isEmpty {
                      NativeAdaptiveBadge(item.pixBadge, tint: NativeTheme.info)
                    }
                    if let edition = item.meta?.edition, !edition.isEmpty {
                      NativeAdaptiveBadge(edition)
                    }
                    if let codec = item.meta?.videoEncode, !codec.isEmpty {
                      NativeAdaptiveBadge(codec)
                    }
                    if item.hasChineseSubtitle {
                      NativeAdaptiveBadge("中字", tint: NativeTheme.warning)
                    }
                  }
                }

                Text(item.torrent.title ?? "种子资源")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                  .fixedSize(horizontal: false, vertical: true)

                if let desc = item.torrent.description?.trimmingCharacters(
                  in: .whitespacesAndNewlines),
                  !desc.isEmpty
                {
                  Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                }

                Divider().overlay(NativeTheme.divider)

                HStack(spacing: 14) {
                  Label(item.sizeText, systemImage: "internaldrive")
                  Label("做种 \(item.torrent.seeders ?? 0)", systemImage: "arrow.up")
                    .foregroundStyle(NativeTheme.success)
                  if let elapsed = item.torrent.dateElapsed, !elapsed.isEmpty {
                    Text(elapsed).foregroundStyle(.secondary)
                  }
                  Spacer()
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }

            // iOS 原生分组选择下载器与保存目录（单行不换行）
            VStack(alignment: .leading, spacing: 7) {
              Text("下载配置")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  HStack(spacing: 12) {
                    Label("下载器", systemImage: "arrow.down.circle")
                      .font(.subheadline)
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    Menu {
                      Button {
                        selectedDownloader = ""
                      } label: {
                        if selectedDownloader.isEmpty {
                          Label("默认下载器", systemImage: "checkmark")
                        } else {
                          Text("默认下载器")
                        }
                      }
                      ForEach(downloaders, id: \.self) { name in
                        Button {
                          selectedDownloader = name
                        } label: {
                          if selectedDownloader == name {
                            Label(name, systemImage: "checkmark")
                          } else {
                            Text(name)
                          }
                        }
                      }
                    } label: {
                      HStack(spacing: 5) {
                        Text(selectedDownloader.isEmpty ? "默认下载器" : selectedDownloader)
                          .font(.subheadline)
                          .lineLimit(1)
                          .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                          .font(.caption2.weight(.semibold))
                      }
                      .foregroundStyle(appearance.accentColor)
                    }
                    .accessibilityIdentifier("native-download-confirm-downloader")
                  }
                  .padding(.horizontal, 15)
                  .frame(minHeight: 50)
                  CinematicFormDivider()
                  HStack(spacing: 12) {
                    Label("保存目录", systemImage: "folder")
                      .font(.subheadline)
                      .foregroundStyle(.primary)
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    Menu {
                      Button {
                        selectedPath = ""
                      } label: {
                        if selectedPath.isEmpty {
                          Label("自动匹配", systemImage: "checkmark")
                        } else {
                          Text("自动匹配")
                        }
                      }
                      ForEach(paths) { option in
                        Button {
                          selectedPath = option.submitValue
                        } label: {
                          if selectedPath == option.submitValue {
                            Label(option.displayLabel, systemImage: "checkmark")
                          } else {
                            Text(option.displayLabel)
                          }
                        }
                      }
                    } label: {
                      let currentPathLabel =
                        paths.first(where: { $0.submitValue == selectedPath })?.displayLabel
                        ?? (selectedPath.isEmpty ? "自动匹配" : selectedPath)
                      HStack(spacing: 5) {
                        Text(currentPathLabel)
                          .font(.subheadline)
                          .lineLimit(1)
                          .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                          .font(.caption2.weight(.semibold))
                      }
                      .foregroundStyle(appearance.accentColor)
                    }
                    .accessibilityIdentifier("native-download-confirm-path")
                  }
                  .padding(.horizontal, 15)
                  .frame(minHeight: 50)
                }
              }
            }

            if let errorMessage {
              CinematicPanel(padding: 11) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption).foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }

            Button {
              Task { await submitDownload() }
            } label: {
              HStack(spacing: 8) {
                if isSubmitting {
                  ProgressView().controlSize(.small).tint(.white)
                } else {
                  Image(systemName: "arrow.down.circle.fill").font(.body.weight(.semibold))
                }
                Text(isSubmitting ? "正在添加到下载器…" : "添加到下载")
                  .font(.subheadline.weight(.bold))
              }
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity, minHeight: 48)
              .background(appearance.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityIdentifier("native-download-confirm-submit")
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("确认下载")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .tint(.primary)
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-download-confirm-cancel")
        }
      }
      .task { await loadOptions() }
    }
  }

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

  private func submitDownload() async {
    isSubmitting = true
    errorMessage = nil
    defer { isSubmitting = false }
    do {
      let body = try JSONEncoder().encode(
        NativeDownloadAddRequest(
          torrentIn: item.torrent,
          mediaSource: targetMediaIdentity?.source ?? item.mediaInfo?.mediaSource
            ?? item.torrent.mediaSource,
          mediaID: targetMediaIdentity?.mediaID ?? item.mediaInfo?.mediaID ?? item.torrent.mediaID,
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

// MARK: - 9 维级联筛选引擎与模型

private struct NativeResourceFacetFilter: Equatable {
  var sites: Set<String> = []
  var seasons: Set<String> = []
  var webSources: Set<String> = []
  var subtitles: Set<String> = []
  var freeStates: Set<String> = []
  var videoCodes: Set<String> = []
  var editions: Set<String> = []
  var resolutions: Set<String> = []
  var releaseGroups: Set<String> = []

  var activeCount: Int {
    sites.count + seasons.count + webSources.count + subtitles.count + freeStates.count
      + videoCodes.count + editions.count + resolutions.count + releaseGroups.count
  }

  mutating func clearAll() {
    sites.removeAll()
    seasons.removeAll()
    webSources.removeAll()
    subtitles.removeAll()
    freeStates.removeAll()
    videoCodes.removeAll()
    editions.removeAll()
    resolutions.removeAll()
    releaseGroups.removeAll()
  }

  func matches(_ item: NativeResourceContext, excluding: String? = nil) -> Bool {
    if excluding != "site", !sites.isEmpty {
      guard let s = item.torrent.siteName, sites.contains(s) else { return false }
    }
    if excluding != "season", !seasons.isEmpty {
      guard let s = item.meta?.seasonEpisode, !s.isEmpty, seasons.contains(s) else { return false }
    }
    if excluding != "webSource", !webSources.isEmpty {
      guard let w = item.meta?.webSource, !w.isEmpty, webSources.contains(w) else { return false }
    }
    if excluding != "subtitle", !subtitles.isEmpty {
      let subs = item.subtitleTags
      guard !subs.isDisjoint(with: subtitles) else { return false }
    }
    if excluding != "freeState", !freeStates.isEmpty {
      guard let f = item.freeStateLabel, freeStates.contains(f) else { return false }
    }
    if excluding != "videoCode", !videoCodes.isEmpty {
      guard let v = item.meta?.videoEncode, !v.isEmpty, videoCodes.contains(v) else { return false }
    }
    if excluding != "edition", !editions.isEmpty {
      guard let e = item.meta?.edition, !e.isEmpty, editions.contains(e) else { return false }
    }
    if excluding != "resolution", !resolutions.isEmpty {
      guard !item.pixBadge.isEmpty, resolutions.contains(item.pixBadge) else { return false }
    }
    if excluding != "releaseGroup", !releaseGroups.isEmpty {
      guard let g = item.meta?.resourceTeam, !g.isEmpty, releaseGroups.contains(g) else {
        return false
      }
    }
    return true
  }
}

private struct NativeResourceFacetOptions {
  let sites: [String]
  let seasons: [String]
  let webSources: [String]
  let subtitles: [String]
  let freeStates: [String]
  let videoCodes: [String]
  let editions: [String]
  let resolutions: [String]
  let releaseGroups: [String]

  init(from items: [NativeResourceContext], currentFilter: NativeResourceFacetFilter) {
    func uniqueSorted(_ key: String, extractor: (NativeResourceContext) -> [String]) -> [String] {
      let pool = items.filter { currentFilter.matches($0, excluding: key) }
      var set: Set<String> = []
      for item in pool {
        for v in extractor(item) where !v.isEmpty { set.insert(v) }
      }
      return set.sorted()
    }
    sites = uniqueSorted("site") { [$0.torrent.siteName ?? ""] }
    seasons = uniqueSorted("season") { [$0.meta?.seasonEpisode ?? ""] }
    webSources = uniqueSorted("webSource") { [$0.meta?.webSource ?? ""] }
    subtitles = uniqueSorted("subtitle") { Array($0.subtitleTags) }
    freeStates = uniqueSorted("freeState") { [$0.freeStateLabel ?? ""] }
    videoCodes = uniqueSorted("videoCode") { [$0.meta?.videoEncode ?? ""] }
    editions = uniqueSorted("edition") { [$0.meta?.edition ?? ""] }
    resolutions = uniqueSorted("resolution") { [$0.pixBadge] }
    releaseGroups = uniqueSorted("releaseGroup") { [$0.meta?.resourceTeam ?? ""] }
  }
}

private struct NativeResourceFeedback {
  let isError: Bool
  let message: String
}

private struct NativeSearchSite: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let isActive: Bool?
  private enum CodingKeys: String, CodingKey {
    case id, name
    case isActive = "is_active"
  }
}

private struct NativeConfirmDownloader: Decodable, Sendable { let name: String }

private struct NativeDownloadPathOption: Decodable, Sendable, Identifiable {
  let name: String?
  let savePath: String?
  let downloadPath: String?
  var id: String { submitValue }
  var submitValue: String {
    if let name, !name.isEmpty { return name }
    return savePath ?? downloadPath ?? ""
  }
  var displayLabel: String {
    if let name, !name.isEmpty { return name }
    return downloadPath ?? savePath ?? "默认目录"
  }
  private enum CodingKeys: String, CodingKey {
    case name
    case savePath = "save_path"
    case downloadPath = "download_path"
  }
}

private struct NativeDownloadAddRequest: Encodable {
  let torrentIn: NativeTorrentPayload
  let mediaSource: String?
  let mediaID: String?
  let downloader: String?
  let savePath: String?
  private enum CodingKeys: String, CodingKey {
    case torrentIn = "torrent_in"
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case downloader
    case savePath = "save_path"
  }
}

private struct NativeResourceSearchEnvelope: Decodable, Sendable {
  let success: Bool?
  let message: String?
  let items: [NativeResourceContext]

  private enum CodingKeys: String, CodingKey { case success, message, data }
  private struct LossyContext: Decodable, Sendable {
    let value: NativeResourceContext?
    init(from decoder: Decoder) throws { value = try? NativeResourceContext(from: decoder) }
  }

  init(from decoder: Decoder) throws {
    if let container = try? decoder.container(keyedBy: CodingKeys.self),
      container.contains(.success) || container.contains(.data)
    {
      success = try? container.decodeIfPresent(Bool.self, forKey: .success)
      message = try? container.decodeIfPresent(String.self, forKey: .message)
      let raw = (try? container.decodeIfPresent([LossyContext].self, forKey: .data)) ?? []
      items = raw.compactMap(\.value)
      return
    }
    let single = try decoder.singleValueContainer()
    let raw = (try? single.decode([LossyContext].self)) ?? []
    success = true
    message = nil
    items = raw.compactMap(\.value)
  }
}

private struct NativeResourceContext: Decodable, Sendable, Identifiable {
  struct MediaBrief: Decodable, Sendable {
    let title: String?
    let enTitle: String?
    let year: String?
    let type: String?
    let posterPath: String?
    let mediaSource: String?
    let mediaID: String?

    var displayTitle: String? {
      if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
      if let e = enTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { return e }
      return nil
    }

    private enum CodingKeys: String, CodingKey {
      case title, year, type, cover
      case enTitle = "en_title"
      case posterPath = "poster_path"
      case mediaSource = "media_source"
      case mediaID = "media_id"
      case source
      case tmdbID = "tmdb_id"
      case doubanID = "douban_id"
      case bangumiID = "bangumi_id"
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      title = try? c.decodeIfPresent(String.self, forKey: .title)
      enTitle = try? c.decodeIfPresent(String.self, forKey: .enTitle)
      if let yStr = try? c.decodeIfPresent(String.self, forKey: .year) {
        year = yStr
      } else if let yInt = try? c.decodeIfPresent(Int.self, forKey: .year) {
        year = String(yInt)
      } else {
        year = nil
      }
      type = try? c.decodeIfPresent(String.self, forKey: .type)
      posterPath =
        (try? c.decodeIfPresent(String.self, forKey: .posterPath))
        ?? (try? c.decodeIfPresent(String.self, forKey: .cover))
      let rawSource =
        (try? c.decodeIfPresent(String.self, forKey: .mediaSource))
        ?? (try? c.decodeIfPresent(String.self, forKey: .source))
      mediaSource = rawSource
      if let s = try? c.decodeIfPresent(String.self, forKey: .mediaID), !s.isEmpty {
        mediaID = s
      } else if let n = try? c.decodeIfPresent(Int64.self, forKey: .mediaID) {
        mediaID = String(n)
      } else if let n = try? c.decodeIfPresent(Int64.self, forKey: .tmdbID) {
        mediaID = String(n)
      } else if let s = try? c.decodeIfPresent(String.self, forKey: .doubanID), !s.isEmpty {
        mediaID = s
      } else if let n = try? c.decodeIfPresent(Int64.self, forKey: .bangumiID) {
        mediaID = String(n)
      } else {
        mediaID = nil
      }
    }
  }

  struct Meta: Decodable, Sendable {
    let name: String?
    let cnName: String?
    let enName: String?
    let year: String?
    let type: String?
    let resourcePix: String?
    let videoEncode: String?
    let audioEncode: String?
    let edition: String?
    let seasonEpisode: String?
    let webSource: String?
    let resourceTeam: String?

    var displayName: String? {
      for candidate in [cnName, name, enName] {
        if let v = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
          return v
        }
      }
      return nil
    }

    private enum CodingKeys: String, CodingKey {
      case name, year, type, edition
      case cnName = "cn_name"
      case enName = "en_name"
      case resourcePix = "resource_pix"
      case videoEncode = "video_encode"
      case audioEncode = "audio_encode"
      case seasonEpisode = "season_episode"
      case webSource = "web_source"
      case resourceTeam = "resource_team"
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      name = try? c.decodeIfPresent(String.self, forKey: .name)
      cnName = try? c.decodeIfPresent(String.self, forKey: .cnName)
      enName = try? c.decodeIfPresent(String.self, forKey: .enName)
      if let yStr = try? c.decodeIfPresent(String.self, forKey: .year) {
        year = yStr
      } else if let yInt = try? c.decodeIfPresent(Int.self, forKey: .year) {
        year = String(yInt)
      } else {
        year = nil
      }
      type = try? c.decodeIfPresent(String.self, forKey: .type)
      resourcePix = try? c.decodeIfPresent(String.self, forKey: .resourcePix)
      videoEncode = try? c.decodeIfPresent(String.self, forKey: .videoEncode)
      audioEncode = try? c.decodeIfPresent(String.self, forKey: .audioEncode)
      edition = try? c.decodeIfPresent(String.self, forKey: .edition)
      seasonEpisode = try? c.decodeIfPresent(String.self, forKey: .seasonEpisode)
      webSource = try? c.decodeIfPresent(String.self, forKey: .webSource)
      resourceTeam = try? c.decodeIfPresent(String.self, forKey: .resourceTeam)
    }
  }

  let torrent: NativeTorrentPayload
  let meta: Meta?
  let mediaInfo: MediaBrief?

  private enum CodingKeys: String, CodingKey {
    case torrent = "torrent_info"
    case torrentLegacy = "torrent"
    case meta = "meta_info"
    case metaLegacy = "meta"
    case mediaInfo = "media_info"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let t = try c.decodeIfPresent(NativeTorrentPayload.self, forKey: .torrent) {
      torrent = t
    } else {
      torrent = try c.decode(NativeTorrentPayload.self, forKey: .torrentLegacy)
    }
    meta =
      (try? c.decodeIfPresent(Meta.self, forKey: .meta))
      ?? (try? c.decodeIfPresent(Meta.self, forKey: .metaLegacy))
    mediaInfo = try? c.decodeIfPresent(MediaBrief.self, forKey: .mediaInfo)
  }

  var recognizedMediaTitle: String? {
    mediaInfo?.displayTitle ?? meta?.displayName
  }

  var recognizedMediaYear: String? {
    let raw = mediaInfo?.year ?? meta?.year
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  var recognizedMediaType: String? {
    let raw = (mediaInfo?.type ?? meta?.type)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if raw.isEmpty { return nil }
    switch raw.lowercased() {
    case "movie", "电影": return "电影"
    case "tv", "电视剧": return "电视剧"
    case "music", "音乐": return "音乐"
    default: return raw
    }
  }

  var recognizedMediaSymbol: String {
    switch recognizedMediaType {
    case "电视剧": "tv.fill"
    case "音乐": "music.note"
    default: "film.fill"
    }
  }

  @MainActor
  var recognizedPosterReference: String? {
    guard let raw = mediaInfo?.posterPath?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty
    else { return nil }
    return NativeMediaDetailPage.resolveArtwork(
      raw, source: mediaInfo?.mediaSource ?? "themoviedb")
  }

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

  var promoBadge: String? {
    let dl = torrent.downloadVolumeFactor ?? 1.0
    let ul = torrent.uploadVolumeFactor ?? 1.0
    if dl == 0 && ul >= 2 { return "2X免费" }
    if dl == 0 { return "免费" }
    if dl > 0 && dl < 1 { return "\(Int((dl * 100).rounded()))%" }
    return nil
  }

  var freeStateLabel: String? {
    if torrent.hitAndRun == true { return "H&R" }
    return promoBadge
  }

  var pixBadge: String { meta?.resourcePix ?? "" }

  var hasChineseSubtitle: Bool {
    if (torrent.labels ?? []).contains(where: { $0.contains("中") }) { return true }
    let text = "\(torrent.title ?? "") \(torrent.description ?? "")"
    return text.contains("中字") || text.contains("简繁") || text.contains("国语")
  }

  var subtitleTags: Set<String> {
    var tags: Set<String> = []
    if hasChineseSubtitle { tags.insert("中字") }
    let text =
      "\(torrent.title ?? "") \(torrent.description ?? "") \((torrent.labels ?? []).joined(separator: " "))"
    if text.contains("特效") { tags.insert("特效字幕") }
    if text.contains("杜比") || text.localizedCaseInsensitiveContains("Dolby") || text.contains("HDR")
    {
      tags.insert("HDR/杜比")
    }
    return tags
  }

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
}

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

  private enum CodingKeys: String, CodingKey {
    case site, title, description, imdbid, enclosure, size, seeders, peers, grabs, pubdate,
      freedate,
      labels
    case siteName = "site_name"
    case siteCookie = "site_cookie"
    case siteUA = "site_ua"
    case siteProxy = "site_proxy"
    case siteOrder = "site_order"
    case pageURL = "page_url"
    case dateElapsed = "date_elapsed"
    case uploadVolumeFactor = "uploadvolumefactor"
    case downloadVolumeFactor = "downloadvolumefactor"
    case hitAndRun = "hit_and_run"
    case priOrder = "pri_order"
    case mediaSource = "media_source"
    case mediaID = "media_id"
  }
}
