import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生订阅广场：支持浏览热门电影/剧集订阅排行及社区分享订阅，支持关键词检索与显式确认复用。
@MainActor
struct NativeSubscribeCommunityPage: View {
  /// 订阅广场三大分区。
  enum Tab: String, CaseIterable, Identifiable {
    case popularMovies = "热门电影"
    case popularTVs = "热门剧集"
    case shares = "社区分享"

    /// 稳定分区键。
    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var selectedTab: Tab = .popularMovies
  @State private var popularItems: [NativePopularSubscribeItem] = []
  @State private var shareItems: [NativeSubscribeShareItem] = []
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var pendingFork: NativeSubscribeShareItem?
  @State private var forkingID: Int?
  @State private var feedback: NativeCommunityFeedback?

  @State private var containerWidth: CGFloat = 0
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// 连续深色紫玫瑰渐变、分区切换胶囊、热门海报网格与分享订阅卡片列表。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          tabSelector
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && isCurrentEmpty {
            if selectedTab == .shares {
              NativeCardListSkeletonView(count: 4, style: .posterRow)
                .transition(.opacity)
            } else {
              NativePosterGridSkeletonView(columns: columns.count, count: columns.count * 3)
                .transition(.opacity)
            }
          } else if loadFailed && isCurrentEmpty {
            failureCard
          } else if selectedTab == .shares {
            sharesContent
          } else {
            popularGrid
          }
        }
        .frame(maxWidth: 1200)
        .padding(.horizontal, NativeDeviceLayout.horizontalMargin(for: containerWidth))
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-community-scroll")
    }
    .navigationTitle("订阅广场")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(text: $searchText, prompt: "筛选片名或分享标题")
    .onSubmit(of: .search) { reloadToken += 1 }
    .task(id: "\(selectedTab.rawValue)|\(reloadToken)") { await load() }
    .alert(
      "复用订阅",
      isPresented: Binding(
        get: { pendingFork != nil },
        set: { if !$0 { pendingFork = nil } }
      ),
      presenting: pendingFork
    ) { item in
      Button("确认复用") {
        Task { await forkShare(item) }
      }
      Button("取消", role: .cancel) {}
    } message: { item in
      Text("将「\(item.displayTitle)」的过滤规则添加到我的订阅列表吗？")
    }
  }

  /// 当前分区是否为空。
  private var isCurrentEmpty: Bool {
    selectedTab == .shares ? shareItems.isEmpty : popularItems.isEmpty
  }

  /// 随实时容器宽度自适应 3~6 列海报网格。
  private var columns: [GridItem] {
    let count =
      containerWidth > 0
      ? NativeDeviceLayout.posterGridCount(
        for: min(containerWidth, 1200), isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
      : (horizontalSizeClass == .regular ? 5 : 3)
    return Array(repeating: GridItem(.flexible(), spacing: 11, alignment: .top), count: count)
  }

  /// 顶部分区切换胶囊栏。
  private var tabSelector: some View {
    HStack(spacing: 8) {
      ForEach(Tab.allCases) { tab in
        let active = selectedTab == tab
        Button {
          selectedTab = tab
        } label: {
          Text(tab.rawValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? Color.white : NativeTheme.chipText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
              Capsule()
                .fill(
                  active
                    ? Color(red: 0.58, green: 0.42, blue: 0.88).opacity(0.78)
                    : NativeTheme.chipFill
                )
                .overlay {
                  Capsule().strokeBorder(.primary.opacity(active ? 0.32 : 0.14), lineWidth: 0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-community-tab-\(tab.rawValue)")
      }
      Spacer(minLength: 0)
    }
  }

  /// 热门订阅三列海报网格，带热度人数徽标与详情跳转。
  @ViewBuilder
  private var popularGrid: some View {
    let items = filteredPopular
    if items.isEmpty {
      emptyCard(title: "暂无热门订阅数据", subtitle: "稍后下拉刷新或切换其他分区查看。")
    } else {
      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(items) { item in
          Group {
            if let identity = item.identity {
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: identity)
              } label: {
                popularPosterCard(item)
              }
              .buttonStyle(.plain)
            } else {
              popularPosterCard(item)
            }
          }
          .accessibilityIdentifier("native-community-popular-\(item.id)")
        }
      }
    }
  }

  /// 单张热门订阅海报卡。
  private func popularPosterCard(_ item: NativePopularSubscribeItem) -> some View {
    VStack(alignment: .center, spacing: 6) {
      Color.clear
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .overlay {
          NativeMediaArtwork(
            session: session, reference: item.posterReference, role: .poster, maximumWidth: 420
          )
        }
        .clipped()
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        }
        .overlay(alignment: .bottomLeading) {
          if let hotText = item.hotLabel {
            HStack(spacing: 3) {
              Image(systemName: "flame.fill").font(.system(size: 9))
              Text(hotText).font(.caption2.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.48))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background { Capsule().fill(.black.opacity(0.68)) }
            .padding(6)
          }
        }
        .nativeMediaExistsOverlay(
          session: session,
          source: item.identity?.source,
          mediaID: item.identity?.mediaID,
          title: item.title,
          year: item.year,
          type: item.identity?.type,
          badgeSize: 18,
          inset: 5
        )
      Text(item.title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.primary.opacity(0.95))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
      if let year = item.year, !year.isEmpty {
        Text(year)
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.54))
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .multilineTextAlignment(.center)
    .contentShape(Rectangle())
  }

  /// 社区分享订阅卡片清单，展示分享者、复用次数、过滤标签与一键复用动作。
  @ViewBuilder
  private var sharesContent: some View {
    let items = filteredShares
    if items.isEmpty {
      emptyCard(title: "暂无匹配的订阅分享", subtitle: "尝试修改搜索关键词或下拉刷新。")
    } else {
      LazyVStack(spacing: 12) {
        ForEach(items) { share in
          shareCard(share)
        }
      }
    }
  }

  /// 单条分享订阅透色玻璃卡片。
  private func shareCard(_ item: NativeSubscribeShareItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.poster, source: item.mediaSource ?? "themoviedb")
    let isForking = forkingID == item.id
    return CinematicPanel(padding: 12) {
      HStack(alignment: .top, spacing: 12) {
        NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 420)
          .frame(width: 66, height: 99)
          .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
          }
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 8) {
            Text(item.displayTitle)
              .font(.headline)
              .foregroundStyle(.primary)
              .lineLimit(2)
            Spacer(minLength: 4)
            if let count = item.count, count > 0 {
              Text("复用 \(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(NativeTheme.brand)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                  Capsule()
                    .fill(.primary.opacity(0.10))
                    .overlay {
                      Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6)
                    }
                }
            }
          }
          if let user = item.shareUser, !user.isEmpty {
            Text("分享者：\(user)")
              .font(.caption)
              .foregroundStyle(.primary.opacity(0.64))
          }
          if let comment = item.shareComment, !comment.isEmpty {
            Text(comment)
              .font(.caption)
              .foregroundStyle(.primary.opacity(0.78))
              .lineLimit(2)
          }
          let ruleChips = item.ruleSummaryChips
          if !ruleChips.isEmpty {
            HStack(spacing: 6) {
              ForEach(ruleChips, id: \.self) { chip in
                Text(chip)
                  .font(.caption2.weight(.medium))
                  .foregroundStyle(.primary.opacity(0.86))
                  .padding(.horizontal, 7)
                  .padding(.vertical, 2.5)
                  .background {
                    Capsule().fill(.primary.opacity(0.10))
                  }
              }
            }
          }
          HStack(spacing: 10) {
            Button {
              pendingFork = item
            } label: {
              HStack(spacing: 5) {
                if isForking {
                  ProgressView().controlSize(.mini).tint(.primary)
                } else {
                  Image(systemName: "arrow.triangle.branch").font(.caption2.weight(.semibold))
                }
                Text("复用订阅").font(.caption.weight(.semibold))
              }
              .foregroundStyle(.primary)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.70))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.24), lineWidth: 0.6) }
              }
              .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(forkingID != nil)
            .accessibilityIdentifier("native-share-fork-\(item.id)")
            Spacer()
          }
          .padding(.top, 2)
        }
      }
    }
  }

  /// 过滤后的热门订阅列表。
  private var filteredPopular: [NativePopularSubscribeItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return popularItems }
    return popularItems.filter { $0.title.lowercased().contains(trimmed) }
  }

  /// 过滤后的社区分享列表。
  private var filteredShares: [NativeSubscribeShareItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return shareItems }
    return shareItems.filter {
      $0.displayTitle.lowercased().contains(trimmed)
        || ($0.shareComment ?? "").lowercased().contains(trimmed)
        || ($0.shareUser ?? "").lowercased().contains(trimmed)
    }
  }

  /// 操作结果横幅。
  private func feedbackBanner(_ feedback: NativeCommunityFeedback) -> some View {
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
    .accessibilityIdentifier("native-community-feedback")
  }

  /// 空态卡。
  private func emptyCard(title: String, subtitle: String) -> some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "sparkles.rectangle.stack")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text(title).font(.headline)
        Text(subtitle).font(.footnote).foregroundStyle(.primary.opacity(0.65))
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 失败重试卡。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入订阅广场", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { reloadToken += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-community-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 按当前分区拉取热门订阅或社区分享列表。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      if selectedTab == .shares {
        var query = [
          URLQueryItem(name: "page", value: "1"),
          URLQueryItem(name: "count", value: "30"),
        ]
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { query.append(URLQueryItem(name: "name", value: trimmed)) }
        let endpoint = try APIEndpoint(path: ["subscribe", "shares"], query: query)
        let loaded = try await session.request(
          endpoint, as: [NativeSubscribeShareItem].self, requiring: .init(category: .subscribe)
        ).value
        try Task.checkCancellation()
        shareItems = loaded
      } else {
        let stype = selectedTab == .popularMovies ? "电影" : "电视剧"
        let endpoint = try APIEndpoint(
          path: ["subscribe", "popular"],
          query: [
            URLQueryItem(name: "stype", value: stype),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "count", value: "30"),
          ])
        let loaded = try await session.request(
          endpoint, as: [NativePopularSubscribeRaw].self, requiring: .init(category: .subscribe)
        ).value
        try Task.checkCancellation()
        popularItems = loaded.compactMap { $0.project(fallbackType: stype) }
      }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 显式二次确认后单次提交复用分享订阅（`POST /api/v1/subscribe/fork`）。
  private func forkShare(_ item: NativeSubscribeShareItem) async {
    forkingID = item.id
    defer { forkingID = nil }
    do {
      let body = try JSONEncoder().encode(item)
      let endpoint = try APIEndpoint(path: ["subscribe", "fork"], method: .post, body: body)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      feedback = NativeCommunityFeedback(isError: false, message: "已复用「\(item.displayTitle)」到我的订阅。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeCommunityFeedback(isError: true, message: "复用订阅失败，可能已存在相同订阅或网络异常。")
    }
  }
}

/// 社区操作提示载体。
private struct NativeCommunityFeedback {
  let isError: Bool
  let message: String
}

/// 热门订阅展示模型。
private struct NativePopularSubscribeItem: Identifiable, Hashable {
  let id: String
  let title: String
  let year: String?
  let posterReference: String?
  let hotLabel: String?
  let identity: NativeMediaIdentity?
}

/// `GET /api/v1/subscribe/popular` 解码结构。
private struct NativePopularSubscribeRaw: Decodable, Sendable {
  let mediaSource: String?
  let mediaID: String?
  let tmdbID: Int?
  let doubanID: String?
  let type: String?
  let title: String?
  let year: String?
  let posterPath: String?
  let voteAverage: Double?
  let popularity: Double?

  /// 投影为网格海报项。
  @MainActor
  func project(fallbackType: String) -> NativePopularSubscribeItem? {
    guard let title, !title.isEmpty else { return nil }
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
    } else {
      source = "themoviedb"
      resolvedID = nil
    }
    let identity = resolvedID.map {
      NativeMediaIdentity(source: source, mediaID: $0, type: type ?? fallbackType)
    }
    let hotLabel: String? =
      popularity.flatMap { value in
        let count = Int(value.rounded())
        guard count > 0 else { return nil }
        return count >= 1000 ? String(format: "%.1fk", Double(count) / 1000.0) : "\(count)"
      } ?? voteAverage.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
    let id = identity?.id ?? "\(fallbackType)|\(title)|\(year ?? "")"
    return NativePopularSubscribeItem(
      id: id,
      title: title,
      year: year,
      posterReference: NativeMediaDetailPage.resolveArtwork(posterPath, source: source),
      hotLabel: hotLabel,
      identity: identity
    )
  }

  private enum CodingKeys: String, CodingKey {
    case type, title, year, popularity
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case doubanID = "douban_id"
    case posterPath = "poster_path"
    case voteAverage = "vote_average"
  }
}

/// `GET /api/v1/subscribe/shares` 与 `POST /api/v1/subscribe/fork` 双向编解码模型。
private struct NativeSubscribeShareItem: Codable, Sendable, Identifiable {
  let id: Int
  let subscribeID: Int?
  let shareTitle: String?
  let shareComment: String?
  let shareUser: String?
  let shareUID: String?
  let name: String?
  let year: String?
  let type: String?
  let keyword: String?
  let mediaSource: String?
  let mediaID: String?
  let season: Int?
  let poster: String?
  let vote: Double?
  let include: String?
  let exclude: String?
  let quality: String?
  let resolution: String?
  let effect: String?
  let totalEpisode: Int?
  let customWords: String?
  let count: Int?

  /// 优先展示分享标题，缺省回退片名与季号。
  var displayTitle: String {
    if let shareTitle, !shareTitle.isEmpty { return shareTitle }
    let base = name ?? "未命名分享"
    if let season, type == "电视剧" {
      return "\(base) S\(String(format: "%02d", season))"
    }
    return base
  }

  /// 规则摘要胶囊（画质/分辨率/特效/过滤）。
  var ruleSummaryChips: [String] {
    [quality, resolution, effect]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, year, type, keyword, season, poster, vote, include, exclude
    case quality, resolution, effect, count
    case subscribeID = "subscribe_id"
    case shareTitle = "share_title"
    case shareComment = "share_comment"
    case shareUser = "share_user"
    case shareUID = "share_uid"
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case totalEpisode = "total_episode"
    case customWords = "custom_words"
  }
}
