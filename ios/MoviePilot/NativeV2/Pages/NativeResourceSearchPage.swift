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

  /// 站点资源检索的站点范围选择：区分「默认（跟随系统设置）」、「全部站点（覆盖系统设置）」与「手工指定站点」。
  private enum SiteScopeSelection: Equatable {
    case systemDefault
    case allSites
    case custom(Set<Int>)
  }

  private enum QueryMode: Equatable {
    case lastResults
    case keyword(String, scope: SiteScopeSelection)
    case siteResource(siteID: Int, siteName: String, keyword: String?)

    var isSiteResource: Bool {
      if case .siteResource = self { return true }
      return false
    }

    var isBrowseHome: Bool {
      if case .siteResource(_, _, let kw) = self {
        return kw == nil
      }
      return false
    }
  }

  let session: NativeSession
  let target: NativeResourceSearchTarget

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @State private var keyword: String
  @State private var sites: [NativeSearchSite] = []
  @State private var siteScope: SiteScopeSelection = .systemDefault
  @State private var results: [NativeResourceContext] = []

  // 9 维级联多选筛选状态（对齐 Web TorrentCardListView.vue）
  @State private var filter = NativeResourceFacetFilter()
  @State private var sortField: SortField = .defaultPriority
  @State private var sortDescending = true
  @State private var showsAllFiltersSheet = false

  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var queryMode: QueryMode
  @State private var currentPage = 0
  @State private var canLoadMore = false
  @State private var selectedForDownload: NativeResourceContext?
  @State private var feedback: NativeResourceFeedback?
  @FocusState private var searchFocused: Bool

  /// 初始化站点资源检索页，支持直达上次结果、按外部深链关键字检索或直接浏览站点首页。
  init(
    session: NativeSession,
    target: NativeResourceSearchTarget,
    initialKeyword: String? = nil,
    browseHome: Bool = false
  ) {
    self.session = session
    self.target = target
    let trimmed = initialKeyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    _keyword = State(initialValue: trimmed)
    if case .lastResults = target {
      if !trimmed.isEmpty {
        _queryMode = State(initialValue: .keyword(trimmed, scope: .systemDefault))
      } else {
        _queryMode = State(initialValue: .lastResults)
      }
    } else {
      _queryMode = State(initialValue: .lastResults)
    }
    _ = browseHome
  }

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if case .lastResults = target {
            searchInputCard
            queryContextBar
          }
          if !results.isEmpty || filter.activeCount > 0 {
            cascadingFilterBar
              .frame(minHeight: 32)
          }
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && results.isEmpty {
            VStack(spacing: 14) {
              HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.primary)
                Text(loadingMessage)
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 4)
              .frame(minHeight: 32)
              NativeCardListSkeletonView(count: 5, style: .torrentCard, spacing: 11)
            }
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
              if canLoadMore, case .lastResults = target, queryMode != .lastResults {
                loadMoreFooter
              }
            }
          }
        }
        .frame(maxWidth: NativeDeviceLayout.isIPad ? 1040 : 860)
        .padding(.horizontal, NativeDeviceLayout.isIPad ? 24 : CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable {
        await Task { @MainActor in
          await performSearch()
        }.value
      }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-resource-search-scroll")
    }
    .navigationTitle(navigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
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
        }
      }
    }
    .task {
      await loadSitesIfNeeded()
    }
    .task(id: attempt) {
      await performSearch()
    }
    .sheet(isPresented: $showsAllFiltersSheet) {
      NativeResourceAllFiltersSheet(results: results, filter: $filter)
    }
    .sheet(item: $selectedForDownload) { item in
      let siblings = sameSpecSiblings(for: item)
      NativeDownloadConfirmSheet(
        session: session,
        item: item,
        sameSpecVariants: siblings,
        targetMediaIdentity: targetIdentity
      ) { message in
        feedback = NativeResourceFeedback(isError: false, message: message)
      }
      .nativeGlassSheet()
      .nativeAdaptiveSheetSizing()
      .presentationDetents(
        verticalSizeClass == .compact ? [.large] : [.fraction(2.0 / 3.0), .large]
      )
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
      switch queryMode {
      case .lastResults:
        "正在载入上次搜索结果…"
      case .keyword(let term, _):
        "正在搜索「\(term)」…"
      case .siteResource(_, let siteName, let term):
        if let term, !term.isEmpty {
          "正在 \(siteName) 中搜索「\(term)」…"
        } else {
          "正在获取 \(siteName) 站点资源…"
        }
      }
    case .media:
      "正在检索匹配站点资源…"
    }
  }

  private static func isValidMediaIdentity(_ identity: NativeMediaIdentity) -> Bool {
    let source = identity.source.trimmingCharacters(in: .whitespacesAndNewlines)
    let mediaID = identity.mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
    return !source.isEmpty && !mediaID.isEmpty && mediaID != "0"
  }

  private var targetIdentity: NativeMediaIdentity? {
    if case .media(let identity, _, _) = target, Self.isValidMediaIdentity(identity) {
      return identity
    }
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

  /// 手工选中单个站点时返回该站点 ID；「默认」「全站」或多站均返回 nil。
  private var selectedSingleSiteID: Int? {
    if case .custom(let ids) = siteScope, ids.count == 1 {
      return ids.first
    }
    return nil
  }

  /// 仅当手工选择了单个站点时允许留空执行站点资源浏览（默认、全站或多站均禁用浏览）。
  private var canBrowseSingleSite: Bool {
    selectedSingleSiteID != nil
  }

  private func isCustomSiteSelected(_ siteID: Int) -> Bool {
    if case .custom(let ids) = siteScope {
      return ids.contains(siteID)
    }
    return false
  }

  private func toggleCustomSite(_ siteID: Int) {
    switch siteScope {
    case .systemDefault, .allSites:
      siteScope = .custom([siteID])
    case .custom(var ids):
      if ids.contains(siteID) {
        ids.remove(siteID)
        siteScope = ids.isEmpty ? .systemDefault : .custom(ids)
      } else {
        ids.insert(siteID)
        siteScope = .custom(ids)
      }
    }
  }

  /// 关键词检索输入卡：有关键词时执行站点搜索，留空时仅在单选站点时允许浏览站点资源。
  private var searchInputCard: some View {
    let hasKeyword = !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let canSubmit = hasKeyword || canBrowseSingleSite
    let isDefaultScope = siteScope == .systemDefault
    return CinematicPanel(padding: 6) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.leading, 6)
        TextField(
          canBrowseSingleSite ? "关键词搜索或直接浏览" : "搜索资源关键词",
          text: $keyword
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($searchFocused)
        .frame(minHeight: 44)
        .accessibilityIdentifier("native-resource-search-query")
        .onSubmit { submitSearch() }
        if !keyword.isEmpty {
          Button {
            keyword = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("清空关键词")
        }
        if !sites.isEmpty {
          Menu {
            Button {
              siteScope = .systemDefault
            } label: {
              if siteScope == .systemDefault {
                Label("默认（系统设置）", systemImage: "checkmark")
              } else {
                Text("默认（系统设置）")
              }
            }
            Button {
              siteScope = .allSites
            } label: {
              if siteScope == .allSites {
                Label("全部站点", systemImage: "checkmark")
              } else {
                Text("全部站点")
              }
            }
            Divider()
            ForEach(sites) { site in
              Button {
                toggleCustomSite(site.id)
              } label: {
                if isCustomSiteSelected(site.id) {
                  Label(site.name, systemImage: "checkmark")
                } else {
                  Text(site.name)
                }
              }
              .nativeKeepsMenuOpen()
              .accessibilityIdentifier("native-resource-search-site-\(site.id)")
            }
          } label: {
            HStack(spacing: 3) {
              Text(scopeLabel(for: siteScope))
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
              Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(isDefaultScope ? NativeTheme.chipText : .white)
            .padding(.horizontal, 9)
            .frame(minHeight: 32)
            .background(
              isDefaultScope ? NativeTheme.chipFill : appearance.accentColor, in: Capsule()
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .accessibilityIdentifier("native-resource-search-sites")
        }
        Button {
          submitSearch()
        } label: {
          HStack(spacing: 4) {
            if isLoading {
              ProgressView()
                .controlSize(.mini)
                .tint(hasKeyword ? .white : .primary)
            } else {
              Text(hasKeyword ? "搜索" : "浏览")
                .font(.caption.weight(.semibold))
            }
          }
          .foregroundStyle(
            hasKeyword
              ? Color.white
              : (canBrowseSingleSite ? Color.primary : Color.primary.opacity(0.45))
          )
          .padding(.horizontal, 12)
          .frame(minWidth: 48, minHeight: 32)
          .background {
            Capsule()
              .fill(
                hasKeyword
                  ? appearance.accentColor
                  : (canBrowseSingleSite ? NativeTheme.chipFill : Color.clear)
              )
              .overlay {
                if !hasKeyword {
                  Capsule().strokeBorder(
                    NativeTheme.chipBorder.opacity(canBrowseSingleSite ? 1.0 : 0.72),
                    lineWidth: 0.7)
                }
              }
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .padding(.trailing, 4)
        .buttonStyle(.plain)
        .disabled(isLoading || !canSubmit)
        .accessibilityLabel(hasKeyword ? "搜索资源" : "浏览站点资源")
        .accessibilityIdentifier("native-resource-search-submit")
      }
    }
  }

  /// 当前检索/浏览模式状态条：清晰区分上次结果、关键词搜索与站点首页浏览，并支持快速切回上次结果。
  @ViewBuilder
  private var queryContextBar: some View {
    if queryMode != .lastResults {
      HStack(spacing: 8) {
        Image(
          systemName: queryMode.isBrowseHome ? "globe" : "magnifyingglass"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Text(queryContextTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 8)
        Button {
          loadLastResults()
        } label: {
          Text("上次结果")
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(0.82))
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityIdentifier("native-resource-back-last")
      }
      .padding(.horizontal, 4)
    }
  }

  private func scopeLabel(for scope: SiteScopeSelection) -> String {
    switch scope {
    case .systemDefault:
      return "默认"
    case .allSites:
      return "全站"
    case .custom(let ids):
      if ids.isEmpty { return "默认" }
      if ids.count == 1, let id = ids.first,
        let match = sites.first(where: { $0.id == id })
      {
        return String(match.name.prefix(6))
      }
      return "\(ids.count)站"
    }
  }

  /// 将站点范围选项映射为后端 `sites` 查询参数：默认省略（使用系统设置范围），全站传递全部已启用站点 ID，指定站点传递所选站点 ID。
  private func resolvedSitesQueryValue(for scope: SiteScopeSelection) -> String? {
    switch scope {
    case .systemDefault:
      return nil
    case .allSites:
      let allIDs = sites.map(\.id).sorted()
      return allIDs.isEmpty ? nil : allIDs.map(String.init).joined(separator: ",")
    case .custom(let ids):
      let sorted = ids.sorted()
      return sorted.isEmpty ? nil : sorted.map(String.init).joined(separator: ",")
    }
  }

  private var queryContextTitle: String {
    switch queryMode {
    case .lastResults:
      return "上次搜索结果"
    case .siteResource(_, let siteName, let term):
      if let term, !term.isEmpty {
        return "单站搜索「\(term)」· \(siteName)"
      }
      return "站点资源 · \(siteName)"
    case .keyword(let term, let scope):
      return "搜索「\(term)」· \(scopeLabel(for: scope))"
    }
  }

  /// 站点首页浏览与关键词搜索分页加载按钮。
  private var loadMoreFooter: some View {
    Button {
      Task { await loadNextPage() }
    } label: {
      HStack(spacing: 8) {
        if isLoadingMore {
          ProgressView().controlSize(.small).tint(.primary)
          Text("正在加载下一页…")
        } else {
          Image(systemName: "arrow.down.circle")
          Text("加载下一页")
        }
      }
      .font(.subheadline.weight(.medium))
      .foregroundStyle(.primary.opacity(0.86))
      .frame(maxWidth: .infinity, minHeight: 44)
      .background {
        Capsule()
          .fill(NativeTheme.chipFill)
          .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
      }
    }
    .buttonStyle(.plain)
    .disabled(isLoadingMore || isLoading)
    .padding(.top, 4)
    .accessibilityIdentifier("native-resource-load-more")
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
    .accessibilityIdentifier("native-resource-facet-bar")
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
          .nativeKeepsMenuOpen()
          .accessibilityIdentifier("native-resource-facet-\(title)-\(opt)")
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
      .accessibilityIdentifier("native-resource-facet-\(title)")
    }
  }

  /// 整张卡片即可点击弹出下载确认窗（顶部标明所属识别媒体，去除卡片内部多余下载按钮）。
  private func resourceCard(_ item: NativeResourceContext) -> some View {
    let mediaHeading = item.recognizedMediaTitle ?? fallbackTargetTitle
    return Button {
      selectedForDownload = item
    } label: {
      CinematicPanel(padding: 13, cornerRadius: 20, style: .subtle) {
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
                Text(typeLabel)
                  .font(.caption2.weight(.medium))
                  .foregroundStyle(.secondary)
              }
            }
            Divider().overlay(NativeTheme.divider)
          }
          // 色彩降噪：仅「站点名」「促销」「H&R」保留语义色胶囊，分辨率/来源/编码/季集/中字收束为清晰等宽规格条。
          HStack(spacing: 6) {
            if let siteName = resolvedSiteName(for: item) {
              NativeAdaptiveBadge(siteName, tint: appearance.accentColor, filled: true)
            }
            if let promo = item.promoBadge {
              NativeAdaptiveBadge(promo, tint: NativeTheme.success)
            }
            if item.torrent.hitAndRun == true {
              NativeAdaptiveBadge("H&R", tint: NativeTheme.danger)
            }
            let specParts: [String] = [
              item.pixBadge.isEmpty ? nil : item.pixBadge,
              item.meta?.edition?.isEmpty == false ? item.meta?.edition : nil,
              item.meta?.videoEncode?.isEmpty == false ? item.meta?.videoEncode : nil,
              item.meta?.seasonEpisode?.isEmpty == false ? item.meta?.seasonEpisode : nil,
              item.hasChineseSubtitle ? "中字" : nil,
            ].compactMap { $0 }
            if !specParts.isEmpty {
              Text(specParts.joined(separator: " · "))
                .font(.caption2.monospaced().weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            Spacer(minLength: 0)
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
        } else if results.isEmpty, case .lastResults = target, queryMode == .lastResults {
          Button("浏览站点资源") {
            keyword = ""
            submitSearch()
          }
          .font(.subheadline.weight(.medium))
          .foregroundStyle(canBrowseSingleSite ? Color.primary : Color.secondary)
          .padding(.horizontal, 14)
          .frame(minHeight: 38)
          .background(
            NativeTheme.chipFill.opacity(canBrowseSingleSite ? 1.0 : 0.45), in: Capsule()
          )
          .buttonStyle(.plain)
          .disabled(!canBrowseSingleSite)
          .opacity(canBrowseSingleSite ? 1.0 : 0.65)
          if !canBrowseSingleSite {
            Text("请选择单个站点后即可浏览站点资源")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
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

  /// 查找当前检索结果中与选中种子同规格（同片名/季集/分辨率/版本/编码/制作组，且含主源）的候选站点源列表。
  private func sameSpecSiblings(for primary: NativeResourceContext) -> [NativeResourceContext] {
    func specKey(_ ctx: NativeResourceContext) -> String {
      let titleKey =
        (ctx.recognizedMediaTitle ?? ctx.torrent.title ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let season = (ctx.meta?.seasonEpisode ?? "").lowercased()
      let pix = ctx.pixBadge.lowercased()
      let edition = (ctx.meta?.edition ?? "").lowercased()
      let encode = (ctx.meta?.videoEncode ?? "").lowercased()
      let team = (ctx.meta?.resourceTeam ?? "").lowercased()
      return "\(titleKey)|\(season)|\(pix)|\(edition)|\(encode)|\(team)"
    }
    let primaryKey = specKey(primary)
    guard !primaryKey.replacingOccurrences(of: "|", with: "").isEmpty else { return [primary] }
    var out: [NativeResourceContext] = [primary]
    for candidate in displayedResults where candidate.id != primary.id {
      if specKey(candidate) == primaryKey {
        out.append(candidate)
      }
    }
    return out
  }

  /// 优先展示种子自带站点名，单站浏览缺少 `site_name` 时回退到已加载站点列表名称。
  private func resolvedSiteName(for item: NativeResourceContext) -> String? {
    if let name = item.torrent.siteName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    {
      return name
    }
    if let siteID = item.torrent.site,
      let match = sites.first(where: { $0.id == siteID })
    {
      return match.name
    }
    if case .siteResource(_, let siteName, _) = queryMode, !siteName.isEmpty {
      return siteName
    }
    return nil
  }

  /// 提交搜索或单站浏览：单选站点且具备管理权限时直连 `/api/v1/site/resource/{site_id}`；选择「默认」时遵循系统设置站点范围，选择「全站」或多站时显式传站点列表覆盖系统设置。
  private func submitSearch() {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    let nextMode: QueryMode
    if trimmed.isEmpty {
      guard let siteID = selectedSingleSiteID else { return }
      let siteName = sites.first(where: { $0.id == siteID })?.name ?? "#\(siteID)"
      nextMode = .siteResource(siteID: siteID, siteName: siteName, keyword: nil)
    } else if let siteID = selectedSingleSiteID,
      session.user.allows(.init(category: .manage))
    {
      let siteName = sites.first(where: { $0.id == siteID })?.name ?? "#\(siteID)"
      nextMode = .siteResource(siteID: siteID, siteName: siteName, keyword: trimmed)
    } else {
      nextMode = .keyword(trimmed, scope: siteScope)
    }
    searchFocused = false
    queryMode = nextMode
    results = []
    feedback = nil
    loadFailed = false
    currentPage = 0
    canLoadMore = false
    filter.clearAll()
    isLoading = true
    attempt += 1
  }

  /// 切回最近一次搜索缓存结果。
  private func loadLastResults() {
    searchFocused = false
    queryMode = .lastResults
    results = []
    feedback = nil
    loadFailed = false
    currentPage = 0
    canLoadMore = false
    filter.clearAll()
    isLoading = true
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

  private func buildSearchEndpoint(page: Int) throws -> APIEndpoint {
    switch target {
    case .lastResults:
      switch queryMode {
      case .lastResults:
        return try APIEndpoint(
          path: ["search", "last"],
          responseContract: .payload,
          maximumResponseBytes: 12 * 1024 * 1024,
          timeout: 30)
      case .keyword(let term, let scope):
        var query = [
          URLQueryItem(name: "keyword", value: term),
          URLQueryItem(name: "page", value: String(page)),
        ]
        if let siteQueryValue = resolvedSitesQueryValue(for: scope) {
          query.append(URLQueryItem(name: "sites", value: siteQueryValue))
        }
        return try APIEndpoint(
          path: ["search", "title"],
          query: query,
          responseContract: .payload,
          maximumResponseBytes: 12 * 1024 * 1024,
          timeout: 90)
      case .siteResource(let siteID, _, let term):
        var query = [URLQueryItem(name: "page", value: String(page))]
        if let term, !term.isEmpty {
          query.insert(URLQueryItem(name: "keyword", value: term), at: 0)
        }
        return try APIEndpoint(
          path: ["site", "resource", String(siteID)],
          query: query,
          responseContract: .payload,
          maximumResponseBytes: 12 * 1024 * 1024,
          timeout: 90)
      }
    case .media(let identity, let title, let season):
      let siteQueryValue = resolvedSitesQueryValue(for: siteScope)
      if !Self.isValidMediaIdentity(identity) {
        var query = [
          URLQueryItem(
            name: "keyword", value: title.trimmingCharacters(in: .whitespacesAndNewlines)),
          URLQueryItem(name: "page", value: String(page)),
        ]
        if let siteQueryValue { query.append(URLQueryItem(name: "sites", value: siteQueryValue)) }
        return try APIEndpoint(
          path: ["search", "title"],
          query: query,
          responseContract: .payload,
          maximumResponseBytes: 12 * 1024 * 1024,
          timeout: 90)
      }
      var query = [
        URLQueryItem(name: "media_source", value: identity.source),
        URLQueryItem(name: "mtype", value: identity.type),
      ]
      if let season { query.append(URLQueryItem(name: "season", value: String(season))) }
      if let siteQueryValue { query.append(URLQueryItem(name: "sites", value: siteQueryValue)) }
      return try APIEndpoint(
        path: ["search", "media", identity.mediaID],
        query: query,
        responseContract: .payload,
        maximumResponseBytes: 12 * 1024 * 1024,
        timeout: 90)
    }
  }

  private func performSearch() async {
    isLoading = true
    loadFailed = false
    currentPage = 0
    defer { isLoading = false }
    do {
      let endpoint = try buildSearchEndpoint(page: 0)
      let requirement: PermissionRequirement =
        queryMode.isSiteResource ? .init(category: .manage) : .init(category: .search)
      let envelope = try await session.request(
        endpoint, as: NativeResourceSearchEnvelope.self, requiring: requirement
      ).value
      try Task.checkCancellation()
      results = envelope.items
      canLoadMore = !envelope.items.isEmpty && queryMode != .lastResults
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
      if !results.isEmpty {
        feedback = NativeResourceFeedback(isError: true, message: "检索站点资源失败，请稍后重试。")
      }
    }
  }

  /// 分页加载下一页站点资源并按稳定键去重。
  private func loadNextPage() async {
    guard !isLoadingMore, !isLoading, canLoadMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    let nextPage = currentPage + 1
    do {
      let endpoint = try buildSearchEndpoint(page: nextPage)
      let requirement: PermissionRequirement =
        queryMode.isSiteResource ? .init(category: .manage) : .init(category: .search)
      let envelope = try await session.request(
        endpoint, as: NativeResourceSearchEnvelope.self, requiring: requirement
      ).value
      try Task.checkCancellation()
      var existing = Set(results.map(\.id))
      let additions = envelope.items.filter { existing.insert($0.id).inserted }
      if additions.isEmpty {
        canLoadMore = false
      } else {
        results.append(contentsOf: additions)
        currentPage = nextPage
      }
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeResourceFeedback(isError: true, message: "加载下一页资源失败，请稍后重试。")
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
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
      }
      .navigationTitle("全部筛选 (\(filter.activeCount))")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
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
    .nativeAdaptiveSheetSizing()
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
  let sameSpecVariants: [NativeResourceContext]
  let targetMediaIdentity: NativeMediaIdentity?
  let onAdded: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var downloaders: [String] = []
  @State private var paths: [NativeDownloadPathOption] = []
  @State private var selectedDownloader = ""
  @State private var selectedPath = ""
  @State private var selectedVariantIDs: Set<String>
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  init(
    session: NativeSession,
    item: NativeResourceContext,
    sameSpecVariants: [NativeResourceContext] = [],
    targetMediaIdentity: NativeMediaIdentity?,
    onAdded: @escaping (String) -> Void
  ) {
    self.session = session
    self.item = item
    self.sameSpecVariants = sameSpecVariants.isEmpty ? [item] : sameSpecVariants
    self.targetMediaIdentity = targetMediaIdentity
    self.onAdded = onAdded
    _selectedVariantIDs = State(initialValue: [item.id])
  }

  private var selectedVariants: [NativeResourceContext] {
    let chosen = sameSpecVariants.filter { selectedVariantIDs.contains($0.id) }
    return chosen.isEmpty ? [item] : chosen
  }

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

            // 同规格多站点源多选区（#60）
            if sameSpecVariants.count > 1 {
              VStack(alignment: .leading, spacing: 7) {
                HStack {
                  Text("选择同规格站点源（已选 \(selectedVariants.count)/\(sameSpecVariants.count)）")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                  Spacer()
                  Button(selectedVariantIDs.count == sameSpecVariants.count ? "仅选主源" : "全选") {
                    if selectedVariantIDs.count == sameSpecVariants.count {
                      selectedVariantIDs = [item.id]
                    } else {
                      selectedVariantIDs = Set(sameSpecVariants.map(\.id))
                    }
                  }
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(appearance.accentColor)
                }
                .padding(.horizontal, 6)
                CinematicPanel(padding: 0) {
                  VStack(spacing: 0) {
                    ForEach(Array(sameSpecVariants.enumerated()), id: \.element.id) {
                      idx, variant in
                      if idx > 0 { CinematicFormDivider() }
                      let checked = selectedVariantIDs.contains(variant.id)
                      Button {
                        if checked {
                          if selectedVariantIDs.count > 1 {
                            selectedVariantIDs.remove(variant.id)
                          }
                        } else {
                          selectedVariantIDs.insert(variant.id)
                        }
                      } label: {
                        HStack(spacing: 10) {
                          Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(checked ? appearance.accentColor : .secondary)
                          VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                              Text(variant.torrent.siteName ?? "未知站点")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                              if let promo = variant.promoBadge {
                                NativeAdaptiveBadge(promo, tint: NativeTheme.success)
                              }
                            }
                            Text("\(variant.sizeText) · 做种 \(variant.torrent.seeders ?? 0)")
                              .font(.caption.monospacedDigit())
                              .foregroundStyle(.secondary)
                          }
                          Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                      }
                      .buttonStyle(.plain)
                    }
                  }
                }
              }
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
                Text(
                  isSubmitting
                    ? "正在添加到下载器…"
                    : (selectedVariants.count > 1
                      ? "批量添加到下载（\(selectedVariants.count) 个源）" : "添加到下载")
                )
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
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("确认下载")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
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
    .nativeAdaptiveSheetSizing()
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
    let targets = selectedVariants
    var successCount = 0
    var lastError: Error?
    for targetItem in targets {
      do {
        let body = try JSONEncoder().encode(
          NativeDownloadAddRequest(
            torrentIn: targetItem.torrent,
            mediaSource: targetMediaIdentity?.source ?? targetItem.mediaInfo?.mediaSource
              ?? targetItem.torrent.mediaSource,
            mediaID: targetMediaIdentity?.mediaID ?? targetItem.mediaInfo?.mediaID
              ?? targetItem.torrent.mediaID,
            downloader: selectedDownloader.isEmpty ? nil : selectedDownloader,
            savePath: selectedPath.isEmpty ? nil : selectedPath))
        let endpoint = try APIEndpoint(path: ["download", "add"], method: .post, body: body)
        try await session.perform(endpoint, requiring: .init(category: .search))
        try Task.checkCancellation()
        successCount += 1
      } catch is CancellationError {
        return
      } catch {
        lastError = error
      }
    }
    if successCount == targets.count {
      onAdded(targets.count > 1 ? "已批量提交 \(successCount) 个源至下载队列。" : "已提交至下载队列。")
      dismiss()
    } else if successCount > 0 {
      onAdded("已成功提交 \(successCount)/\(targets.count) 个源，部分站点源提交失败。")
      dismiss()
    } else {
      _ = lastError
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
      meta =
        (try? c.decodeIfPresent(Meta.self, forKey: .meta))
        ?? (try? c.decodeIfPresent(Meta.self, forKey: .metaLegacy))
      mediaInfo = try? c.decodeIfPresent(MediaBrief.self, forKey: .mediaInfo)
    } else if let t = try c.decodeIfPresent(NativeTorrentPayload.self, forKey: .torrentLegacy) {
      torrent = t
      meta =
        (try? c.decodeIfPresent(Meta.self, forKey: .meta))
        ?? (try? c.decodeIfPresent(Meta.self, forKey: .metaLegacy))
      mediaInfo = try? c.decodeIfPresent(MediaBrief.self, forKey: .mediaInfo)
    } else {
      let flat = try NativeTorrentPayload(from: decoder)
      guard
        flat.title != nil || flat.enclosure != nil || flat.pageURL != nil || flat.site != nil
      else {
        throw DecodingError.dataCorrupted(
          DecodingError.Context(
            codingPath: decoder.codingPath, debugDescription: "Missing torrent payload"))
      }
      torrent = flat
      meta = nil
      mediaInfo = nil
    }
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
    if let dl = torrent.downloadVolumeFactor {
      let ul = torrent.uploadVolumeFactor ?? 1.0
      if dl == 0 && ul >= 2 { return "2X免费" }
      if dl == 0 { return "免费" }
      if dl > 0 && dl < 1 { return "\(Int((dl * 100).rounded()))%" }
    }
    if let vf = torrent.volumeFactor?.trimmingCharacters(in: .whitespacesAndNewlines),
      !vf.isEmpty, vf != "普通"
    {
      return vf
    }
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
  let siteDownloader: String?
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
  let freedateDiff: String?
  let uploadVolumeFactor: Double?
  let downloadVolumeFactor: Double?
  let hitAndRun: Bool?
  let labels: [String]?
  let priOrder: Int?
  let category: String?
  let volumeFactor: String?
  let mediaSource: String?
  let mediaID: String?

  private enum CodingKeys: String, CodingKey {
    case site, title, description, imdbid, enclosure, size, seeders, peers, grabs, pubdate,
      freedate, labels, category
    case siteName = "site_name"
    case siteCookie = "site_cookie"
    case siteUA = "site_ua"
    case siteProxy = "site_proxy"
    case siteOrder = "site_order"
    case siteDownloader = "site_downloader"
    case pageURL = "page_url"
    case dateElapsed = "date_elapsed"
    case freedateDiff = "freedate_diff"
    case uploadVolumeFactor = "uploadvolumefactor"
    case downloadVolumeFactor = "downloadvolumefactor"
    case hitAndRun = "hit_and_run"
    case priOrder = "pri_order"
    case volumeFactor = "volume_factor"
    case mediaSource = "media_source"
    case mediaID = "media_id"
  }

  /// 兼容 `/api/v1/search/*` 与 `/api/v1/site/resource/{site_id}` 返回的不同站点字段类型（数字/字符串/布尔混排）。
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func lossyInt(_ key: CodingKeys) -> Int? {
      if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
      if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
      if let s = try? c.decodeIfPresent(String.self, forKey: key) {
        return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      return nil
    }
    func lossyDouble(_ key: CodingKeys) -> Double? {
      if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
      if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(v) }
      if let s = try? c.decodeIfPresent(String.self, forKey: key) {
        return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      return nil
    }
    func lossyBool(_ key: CodingKeys) -> Bool? {
      if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v }
      if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v != 0 }
      if let s = try? c.decodeIfPresent(String.self, forKey: key) {
        switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
      }
      return nil
    }
    func lossyString(_ key: CodingKeys) -> String? {
      if let v = try? c.decodeIfPresent(String.self, forKey: key) { return v }
      if let v = try? c.decodeIfPresent(Int64.self, forKey: key) { return String(v) }
      return nil
    }

    site = lossyInt(.site)
    siteName = lossyString(.siteName)
    siteCookie = lossyString(.siteCookie)
    siteUA = lossyString(.siteUA)
    siteProxy = lossyBool(.siteProxy)
    siteOrder = lossyInt(.siteOrder)
    siteDownloader = lossyString(.siteDownloader)
    title = lossyString(.title)
    description = lossyString(.description)
    imdbid = lossyString(.imdbid)
    enclosure = lossyString(.enclosure)
    pageURL = lossyString(.pageURL)
    size = lossyDouble(.size)
    seeders = lossyInt(.seeders)
    peers = lossyInt(.peers)
    grabs = lossyInt(.grabs)
    pubdate = lossyString(.pubdate)
    dateElapsed = lossyString(.dateElapsed)
    freedate = lossyString(.freedate)
    freedateDiff = lossyString(.freedateDiff)
    uploadVolumeFactor = lossyDouble(.uploadVolumeFactor)
    downloadVolumeFactor = lossyDouble(.downloadVolumeFactor)
    hitAndRun = lossyBool(.hitAndRun)
    if let list = try? c.decodeIfPresent([String].self, forKey: .labels) {
      labels = list
    } else if let raw = try? c.decodeIfPresent(String.self, forKey: .labels), !raw.isEmpty {
      labels = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    } else {
      labels = nil
    }
    priOrder = lossyInt(.priOrder)
    category = lossyString(.category)
    volumeFactor = lossyString(.volumeFactor)
    mediaSource = lossyString(.mediaSource)
    mediaID = lossyString(.mediaID)
  }
}
