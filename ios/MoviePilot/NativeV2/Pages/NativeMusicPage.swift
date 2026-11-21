import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生音乐探索页：支持热门专辑、近期新发、豆瓣音乐与本周榜单多来源浏览，直达专辑曲目与艺术家详情。
@MainActor
struct NativeMusicPage: View {
  /// 音乐探索分区来源。
  enum Feed: String, CaseIterable, Identifiable {
    case douban = "豆瓣音乐"
    case weekly = "本周榜单"
    case chartAlbums = "热门专辑"
    case freshReleases = "近期新发"

    /// 稳定分区键。
    var id: String { rawValue }
  }

  let session: NativeSession
  @State private var searchText = ""
  @State private var reloadToken = 0

  /// 深色紫玫瑰渐变背景与可复用音乐探索内容视图。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        NativeMusicExploreSection(
          session: session,
          searchText: searchText,
          reloadToken: reloadToken
        )
        .frame(maxWidth: 880)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { reloadToken += 1 }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-music-scroll")
    }
    .navigationTitle("音乐探索")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(text: $searchText, prompt: "筛选专辑或艺人名称")
  }
}

/// 可嵌入「探索」页或独立「音乐探索」页的音乐榜单与专辑网格组件。
@MainActor
struct NativeMusicExploreSection: View {
  let session: NativeSession
  var searchText: String = ""
  var reloadToken: Int = 0

  @State private var selectedFeed: NativeMusicPage.Feed = .douban
  @State private var items: [NativeMusicCardItem] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var localReloadToken = 0

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      feedBar
      if isLoading && items.isEmpty {
        ProgressView("正在载入音乐榜单…")
          .tint(.primary)
          .frame(maxWidth: .infinity, minHeight: 240)
      } else if loadFailed && items.isEmpty {
        failureCard
      } else if filteredItems.isEmpty {
        emptyCard
      } else {
        LazyVGrid(columns: columns, spacing: 14) {
          ForEach(filteredItems) { item in
            NavigationLink {
              NativeMusicAlbumDetailPage(session: session, seed: item)
            } label: {
              albumCard(item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-music-card-\(item.id)")
          }
        }
      }
    }
    .task(id: "\(selectedFeed.rawValue)|\(reloadToken)|\(localReloadToken)") { await load() }
  }

  /// 两列方形封面网格（iPad 宽屏四列）。
  private var columns: [GridItem] {
    let count = horizontalSizeClass == .regular ? 4 : 2
    return Array(repeating: GridItem(.flexible(), spacing: 13), count: count)
  }

  /// 按关键字过滤后的音乐条目。
  private var filteredItems: [NativeMusicCardItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return items }
    return items.filter {
      $0.title.lowercased().contains(trimmed)
        || ($0.artist ?? "").lowercased().contains(trimmed)
    }
  }

  /// 顶部音乐来源胶囊切换栏。
  private var feedBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(NativeMusicPage.Feed.allCases) { feed in
          let active = selectedFeed == feed
          Button {
            selectedFeed = feed
          } label: {
            Text(feed.rawValue)
              .font(.caption.weight(active ? .semibold : .medium))
              .foregroundStyle(active ? .white : .primary.opacity(0.75))
              .padding(.horizontal, 12)
              .padding(.vertical, 6.5)
              .background {
                Capsule()
                  .fill(
                    active
                      ? Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.72)
                      : .primary.opacity(0.08)
                  )
                  .overlay {
                    Capsule().strokeBorder(.primary.opacity(active ? 0.28 : 0.12), lineWidth: 0.6)
                  }
              }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-music-feed-\(feed.rawValue)")
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  /// 1:1 方形封面玻璃专辑卡。
  private func albumCard(_ item: NativeMusicCardItem) -> some View {
    CinematicPanel(padding: 10) {
      VStack(alignment: .leading, spacing: 8) {
        ZStack(alignment: .topTrailing) {
          NativeMediaArtwork(
            session: session, reference: item.coverReference, role: .poster, maximumWidth: 420
          )
          .aspectRatio(1.0, contentMode: .fill)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
          }
          if let rating = item.ratingText {
            Text(rating)
              .font(.caption2.weight(.bold).monospacedDigit())
              .foregroundStyle(.primary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2.5)
              .background { Capsule().fill(.black.opacity(0.64)) }
              .padding(6)
          }
        }
        Text(item.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        HStack(spacing: 6) {
          if let artist = item.artist, !artist.isEmpty {
            Text(artist)
              .font(.caption)
              .foregroundStyle(.primary.opacity(0.68))
              .lineLimit(1)
          }
          Spacer(minLength: 0)
          if let year = item.yearText {
            Text(year)
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.primary.opacity(0.50))
          }
        }
      }
    }
  }

  /// 空态卡。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "music.note.list")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text("暂无音乐条目").font(.headline)
        Text("可切换其他音乐榜单或下拉刷新。").font(.footnote).foregroundStyle(.primary.opacity(0.65))
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 载入失败卡。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入音乐榜单", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { localReloadToken += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-music-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 拉取当前所选音乐榜单。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint: APIEndpoint
      switch selectedFeed {
      case .douban:
        endpoint = try APIEndpoint(
          path: ["recommend", "music_douban"], query: [URLQueryItem(name: "page", value: "1")])
      case .weekly:
        endpoint = try APIEndpoint(
          path: ["recommend", "music_weekly"], query: [URLQueryItem(name: "page", value: "1")])
      case .chartAlbums:
        endpoint = try APIEndpoint(
          path: ["music", "explore"],
          query: [
            URLQueryItem(name: "mode", value: "chart"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "range_name", value: "this_month"),
            URLQueryItem(name: "media_source", value: "musicbrainz"),
            URLQueryItem(name: "count", value: "30"),
            URLQueryItem(name: "page", value: "1"),
          ])
      case .freshReleases:
        endpoint = try APIEndpoint(
          path: ["music", "explore"],
          query: [
            URLQueryItem(name: "mode", value: "fresh"),
            URLQueryItem(name: "days", value: "30"),
            URLQueryItem(name: "media_source", value: "musicbrainz"),
            URLQueryItem(name: "count", value: "30"),
            URLQueryItem(name: "page", value: "1"),
          ])
      }
      let rows = try await session.request(
        endpoint, as: [NativeMusicInfoRaw].self, requiring: .init(category: .discovery)
      ).value
      try Task.checkCancellation()
      var seen: Set<String> = []
      items = rows.compactMap { $0.toCardItem() }.filter { seen.insert($0.id).inserted }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }
}

/// 原生音乐专辑详情页：呈现 1:1 封面、艺人跳转、流派标签、音乐订阅操作与完整曲目列表。
@MainActor
struct NativeMusicAlbumDetailPage: View {
  let session: NativeSession
  let seed: NativeMusicCardItem

  @State private var detail: NativeMusicAlbumRaw?
  @State private var isLoading = true
  @State private var isSubscribed = false
  @State private var isMutatingSubscribe = false
  @State private var showsCancelConfirm = false
  @State private var feedback: NativeMusicFeedback?

  /// 是否允许订阅。
  private var canSubscribe: Bool { session.user.allows(.init(category: .subscribe)) }

  /// 连续深色渐变、居中专辑封面、艺人入口、订阅/搜索操作与曲目玻璃面板。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          headerBlock
          actionBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && detail == nil {
            ProgressView("正在载入专辑曲目…")
              .tint(.primary)
              .frame(maxWidth: .infinity, minHeight: 120)
          } else {
            if let overview = resolvedOverview, !overview.isEmpty {
              CinematicPanel {
                VStack(alignment: .leading, spacing: 8) {
                  Text("简介").font(.headline)
                  Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.82))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            if let tracks = detail?.tracks, !tracks.isEmpty {
              tracksSection(tracks)
            }
          }
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-music-album-scroll")
    }
    .navigationTitle("专辑详情")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task { await load() }
    .alert("取消音乐订阅", isPresented: $showsCancelConfirm) {
      Button("取消订阅", role: .destructive) { Task { await cancelSubscribe() } }
      Button("保留", role: .cancel) {}
    } message: {
      Text("确认取消订阅专辑「\(resolvedTitle)」吗？")
    }
  }

  /// 专辑标题。
  private var resolvedTitle: String { detail?.title ?? seed.title }

  /// 艺人显示名。
  private var resolvedArtist: String? {
    detail?.artist ?? detail?.artists?.first ?? seed.artist
  }

  /// 首位艺术家 ID。
  private var primaryArtistID: String? {
    detail?.artistIDs?.first ?? seed.artistID
  }

  /// 封面 URL。
  private var resolvedCover: String? {
    detail?.coverURL ?? detail?.posterPath ?? seed.coverReference
  }

  /// 简介文本。
  private var resolvedOverview: String? { detail?.overview }

  /// 顶部居中封面、标题、可点击艺人入口与元信息胶囊。
  private var headerBlock: some View {
    VStack(spacing: 14) {
      NativeMediaArtwork(
        session: session, reference: resolvedCover, role: .poster, maximumWidth: 420
      )
      .frame(width: 210, height: 210)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(.primary.opacity(0.18), lineWidth: 0.7)
      }
      .shadow(color: .black.opacity(0.45), radius: 22, y: 10)

      VStack(spacing: 6) {
        Text(resolvedTitle)
          .font(.title2.bold())
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
          .accessibilityIdentifier("native-music-album-title")
        if let artist = resolvedArtist, !artist.isEmpty {
          if let artistID = primaryArtistID, !artistID.isEmpty {
            NavigationLink {
              NativeMusicArtistDetailPage(
                session: session, artistID: artistID, artistName: artist, source: seed.mediaSource)
            } label: {
              HStack(spacing: 5) {
                Text(artist).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
              }
              .foregroundStyle(Color(red: 0.84, green: 0.72, blue: 1.0))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-music-album-artist")
          } else {
            Text(artist)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.primary.opacity(0.76))
          }
        }
        HStack(spacing: 8) {
          if let year = detail?.year.map(String.init) ?? seed.yearText {
            metaChip(year)
          }
          if let kind = detail?.albumType, !kind.isEmpty {
            metaChip(kind)
          }
          if let trackCount = detail?.totalTracks ?? detail?.tracks?.count, trackCount > 0 {
            metaChip("\(trackCount) 首曲目")
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 订阅操作条。
  @ViewBuilder
  private var actionBar: some View {
    if canSubscribe && !seed.mediaID.isEmpty {
      HStack(spacing: 12) {
        Button {
          if isSubscribed {
            showsCancelConfirm = true
          } else {
            Task { await subscribeAlbum() }
          }
        } label: {
          HStack(spacing: 8) {
            if isMutatingSubscribe {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
            }
            Text(isSubscribed ? "已订阅专辑" : "订阅专辑").font(.headline)
          }
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, minHeight: 48)
          .background {
            Capsule()
              .fill(
                isSubscribed
                  ? Color(red: 0.28, green: 0.62, blue: 0.48).opacity(0.75)
                  : Color(red: 0.56, green: 0.40, blue: 0.86).opacity(0.84)
              )
              .overlay { Capsule().strokeBorder(.primary.opacity(0.24), lineWidth: 0.7) }
          }
        }
        .buttonStyle(.plain)
        .disabled(isMutatingSubscribe)
        .accessibilityIdentifier("native-music-album-subscribe")
      }
    }
  }

  /// 专辑曲目清单卡片。
  private func tracksSection(_ tracks: [NativeMusicInfoRaw]) -> some View {
    let artworkProxy = NativeMediaPlaybackLauncher.proxiedArtworkURL(
      session: session, raw: resolvedCover)
    let musicQueue: [MediaPlaybackQueueItem] = tracks.map { item in
      MediaPlaybackQueueItem(
        itemId: "",
        title: item.title ?? "未命名曲目",
        server: nil,
        artworkURL: artworkProxy?.absoluteString,
        artist: item.artist ?? resolvedArtist,
        album: resolvedTitle
      )
    }
    return VStack(alignment: .leading, spacing: 10) {
      Text("曲目列表").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
            Button {
              Task {
                let err = await NativeMediaPlaybackLauncher.shared.playMusicTrack(
                  session: session,
                  title: track.title ?? "未命名曲目",
                  artist: track.artist ?? resolvedArtist,
                  album: resolvedTitle,
                  artworkURL: artworkProxy,
                  queue: musicQueue,
                  queueIndex: index)
                if let err {
                  feedback = NativeMusicFeedback(isError: true, message: err)
                }
              }
            } label: {
              HStack(spacing: 12) {
                Text("\(track.trackNumber ?? (index + 1))")
                  .font(.caption.monospacedDigit().weight(.semibold))
                  .foregroundStyle(.primary.opacity(0.48))
                  .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                  Text(track.title ?? "未命名曲目")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  if let artist = track.artist, !artist.isEmpty, artist != resolvedArtist {
                    Text(artist)
                      .font(.caption)
                      .foregroundStyle(.primary.opacity(0.58))
                      .lineLimit(1)
                  }
                }
                Spacer(minLength: 8)
                if let duration = track.duration, duration > 0 {
                  Text(formatDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.56))
                }
                Image(systemName: "play.circle")
                  .font(.subheadline)
                  .foregroundStyle(Color(red: 0.80, green: 0.68, blue: 1.0))
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 11)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
              Button {
                Task {
                  let err = await NativeMediaPlaybackLauncher.shared.playMusicTrack(
                    session: session,
                    title: track.title ?? "未命名曲目",
                    artist: track.artist ?? resolvedArtist,
                    album: resolvedTitle,
                    artworkURL: artworkProxy,
                    queue: musicQueue,
                    queueIndex: index)
                  if let err {
                    feedback = NativeMusicFeedback(isError: true, message: err)
                  }
                }
              } label: {
                Label("播放此曲目", systemImage: "play.fill")
              }
            }
            if index < tracks.count - 1 {
              Divider().overlay(.primary.opacity(0.08)).padding(.leading, 48)
            }
          }
        }
      }
    }
  }

  /// 元信息胶囊。
  private func metaChip(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.medium))
      .foregroundStyle(.primary.opacity(0.82))
      .padding(.horizontal, 9)
      .padding(.vertical, 3.5)
      .background {
        Capsule()
          .fill(.primary.opacity(0.10))
          .overlay { Capsule().strokeBorder(.primary.opacity(0.14), lineWidth: 0.6) }
      }
  }

  /// 反馈提示条。
  private func feedbackBanner(_ feedback: NativeMusicFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 8) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
      }
    }
    .accessibilityIdentifier("native-music-album-feedback")
  }

  /// 将秒数格式化为 `m:ss`。
  private func formatDuration(_ seconds: Int) -> String {
    let mins = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", mins, secs)
  }

  /// 拉取专辑详情并同步当前订阅状态。
  private func load() async {
    isLoading = true
    defer { isLoading = false }
    guard !seed.albumLookupID.isEmpty else { return }
    var query = [URLQueryItem(name: "media_source", value: seed.mediaSource)]
    if let releaseID = seed.releaseID, !releaseID.isEmpty {
      query.append(URLQueryItem(name: "musicbrainz_release_id", value: releaseID))
    }
    do {
      let endpoint = try APIEndpoint(path: ["music", "album", seed.albumLookupID], query: query)
      detail = try await session.request(
        endpoint, as: NativeMusicAlbumRaw.self, requiring: .init(category: .discovery)
      ).value
    } catch {
      detail = nil
    }
    if canSubscribe && !seed.mediaID.isEmpty {
      await refreshSubscribeStatus()
    }
  }

  /// 查询当前专辑是否已在订阅列表中。
  private func refreshSubscribeStatus() async {
    do {
      let payload: [[String: Any]] = [
        [
          "media_source": seed.mediaSource,
          "media_id": seed.mediaID,
          "mtype": "音乐",
        ]
      ]
      let body = try JSONSerialization.data(withJSONObject: payload)
      let endpoint = try APIEndpoint(path: ["media", "status"], method: .post, body: body)
      let statuses = try await session.request(
        endpoint, as: [NativeMusicMediaStatus].self, requiring: .init(category: .discovery)
      ).value
      isSubscribed = statuses.first?.subscribed ?? false
    } catch {
      return
    }
  }

  /// 单次提交专辑订阅至 `POST /api/v1/subscribe/`。
  private func subscribeAlbum() async {
    isMutatingSubscribe = true
    defer { isMutatingSubscribe = false }
    var payload: [String: Any] = [
      "name": resolvedTitle,
      "type": "音乐",
      "music_type": "album",
      "media_source": seed.mediaSource,
      "media_id": seed.mediaID,
    ]
    if let year = detail?.year.map(String.init) ?? seed.yearText { payload["year"] = year }
    if let total = detail?.totalTracks ?? detail?.tracks?.count, total > 0 {
      payload["total_tracks"] = total
    }
    do {
      let body = try JSONSerialization.data(withJSONObject: payload)
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      isSubscribed = true
      feedback = NativeMusicFeedback(isError: false, message: "已添加专辑订阅。")
    } catch {
      feedback = NativeMusicFeedback(isError: true, message: "添加音乐订阅失败，请稍后重试。")
    }
  }

  /// 确认后单次取消专辑订阅。
  private func cancelSubscribe() async {
    isMutatingSubscribe = true
    defer { isMutatingSubscribe = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", "media", seed.mediaID],
        method: .delete,
        query: [
          URLQueryItem(name: "media_source", value: seed.mediaSource),
          URLQueryItem(name: "mtype", value: "音乐"),
        ])
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      isSubscribed = false
      feedback = NativeMusicFeedback(isError: false, message: "已取消专辑订阅。")
    } catch {
      feedback = NativeMusicFeedback(isError: true, message: "取消音乐订阅失败，请稍后重试。")
    }
  }
}

/// 原生音乐艺术家详情页：展示圆形头像、地区与活跃年代、简介及专辑作品网格。
@MainActor
struct NativeMusicArtistDetailPage: View {
  let session: NativeSession
  let artistID: String
  let artistName: String
  let source: String

  @State private var artist: NativeMusicArtistRaw?
  @State private var albums: [NativeMusicCardItem] = []
  @State private var isLoading = true

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// 统一深色紫玫瑰渐变、艺术家头图区与作品专辑网格。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          if isLoading && artist == nil && albums.isEmpty {
            ProgressView("正在载入艺术家资料…")
              .tint(.primary)
              .frame(maxWidth: .infinity, minHeight: 160)
          } else {
            if let overview = artist?.overview, !overview.isEmpty {
              CinematicPanel {
                VStack(alignment: .leading, spacing: 8) {
                  Text("艺人简介").font(.headline)
                  Text(overview).font(.subheadline).foregroundStyle(.primary.opacity(0.82))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            if !albums.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text("专辑作品 (\(albums.count))").font(.headline).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: columns, spacing: 12) {
                  ForEach(albums) { item in
                    NavigationLink {
                      NativeMusicAlbumDetailPage(session: session, seed: item)
                    } label: {
                      VStack(alignment: .leading, spacing: 6) {
                        NativeMediaArtwork(
                          session: session, reference: item.coverReference, role: .poster,
                          maximumWidth: 420
                        )
                        .aspectRatio(1.0, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(item.title)
                          .font(.footnote.weight(.semibold))
                          .foregroundStyle(.primary)
                          .lineLimit(1)
                        if let year = item.yearText {
                          Text(year).font(.caption2).foregroundStyle(.primary.opacity(0.56))
                        }
                      }
                    }
                    .buttonStyle(.plain)
                  }
                }
              }
            }
          }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-music-artist-scroll")
    }
    .navigationTitle(artist?.displayName ?? artistName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task { await load() }
  }

  /// 两列或四列专辑网格。
  private var columns: [GridItem] {
    let count = horizontalSizeClass == .regular ? 4 : 2
    return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
  }

  /// 圆形艺人头像与摘要信息。
  private var header: some View {
    VStack(spacing: 12) {
      NativeMediaArtwork(
        session: session, reference: artist?.imageURL ?? artist?.posterPath, role: .poster,
        maximumWidth: 420
      )
      .frame(width: 112, height: 112)
      .clipShape(Circle())
      .overlay { Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 1) }

      Text(artist?.displayName ?? artistName)
        .font(.title2.bold())
        .foregroundStyle(.primary)
        .accessibilityIdentifier("native-music-artist-name")

      let meta = [artist?.area ?? artist?.country, artist?.lifeSpan]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
      if !meta.isEmpty {
        Text(meta).font(.caption).foregroundStyle(.primary.opacity(0.68))
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 并发拉取艺术家资料与其专辑作品列表。
  private func load() async {
    isLoading = true
    defer { isLoading = false }
    let query = [URLQueryItem(name: "media_source", value: source)]
    do {
      let infoEndpoint = try APIEndpoint(path: ["music", "artist", artistID], query: query)
      let albumsEndpoint = try APIEndpoint(
        path: ["music", "artist", artistID, "albums"], query: query)
      async let infoTask = try? session.request(
        infoEndpoint, as: NativeMusicArtistRaw.self, requiring: .init(category: .discovery)
      ).value
      async let albumsTask = try? session.request(
        albumsEndpoint, as: [NativeMusicInfoRaw].self, requiring: .init(category: .discovery)
      ).value
      let (loadedArtist, loadedAlbums) = await (infoTask, albumsTask)
      artist = loadedArtist
      var seen: Set<String> = []
      albums = (loadedAlbums ?? []).compactMap { $0.toCardItem() }.filter {
        seen.insert($0.id).inserted
      }
    } catch {
      return
    }
  }
}

/// 音乐详情操作提示。
private struct NativeMusicFeedback {
  let isError: Bool
  let message: String
}

/// 媒体入库/订阅状态精简解码项。
private struct NativeMusicMediaStatus: Decodable, Sendable {
  let subscribed: Bool?
}

/// 跨音乐列表/详情/艺人页传递的轻量专辑种子模型。
struct NativeMusicCardItem: Identifiable, Hashable, Sendable {
  let id: String
  let mediaSource: String
  let mediaID: String
  let albumLookupID: String
  let releaseID: String?
  let title: String
  let artist: String?
  let artistID: String?
  let yearText: String?
  let coverReference: String?
  let ratingText: String?
}

/// 兼容字符串或整型的年份解码器。
private struct NativeMusicYearValue: Decodable, Sendable {
  let text: String

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int.self) {
      text = String(number)
    } else {
      text = try container.decode(String.self)
    }
  }
}

/// `MusicInfo` 精简解码结构。
private struct NativeMusicInfoRaw: Decodable, Sendable {
  let mediaSource: String?
  let mediaID: String?
  let albumID: String?
  let releaseID: String?
  let title: String?
  let artist: String?
  let artists: [String]?
  let artistIDs: [String]?
  let year: NativeMusicYearValue?
  let coverURL: String?
  let posterPath: String?
  let rating: Double?
  let voteAverage: Double?
  let trackNumber: Int?
  let duration: Int?

  /// 投影为音乐探索卡片模型。
  func toCardItem() -> NativeMusicCardItem? {
    guard let title, !title.isEmpty else { return nil }
    let source = mediaSource?.isEmpty == false ? mediaSource! : "musicbrainz"
    let primaryID = mediaID?.isEmpty == false ? mediaID! : (albumID ?? "")
    let lookupID = albumID?.isEmpty == false ? albumID! : primaryID
    let resolvedID = primaryID.isEmpty ? "\(source)|\(title)" : "\(source)|\(primaryID)"
    let score = (rating ?? 0) > 0 ? rating : voteAverage
    let ratingText = score.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
    return NativeMusicCardItem(
      id: resolvedID,
      mediaSource: source,
      mediaID: primaryID,
      albumLookupID: lookupID,
      releaseID: releaseID,
      title: title,
      artist: artist ?? artists?.first,
      artistID: artistIDs?.first,
      yearText: year?.text,
      coverReference: coverURL ?? posterPath,
      ratingText: ratingText
    )
  }

  private enum CodingKeys: String, CodingKey {
    case title, artist, artists, year, rating, duration
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case albumID = "album_id"
    case releaseID = "musicbrainz_release_id"
    case artistIDs = "artist_ids"
    case coverURL = "cover_url"
    case posterPath = "poster_path"
    case voteAverage = "vote_average"
    case trackNumber = "track_number"
  }
}

/// `GET /api/v1/music/album/{id}` 解码结构。
private struct NativeMusicAlbumRaw: Decodable, Sendable {
  let title: String?
  let artist: String?
  let artists: [String]?
  let artistIDs: [String]?
  let albumType: String?
  let year: Int?
  let totalTracks: Int?
  let coverURL: String?
  let posterPath: String?
  let overview: String?
  let tracks: [NativeMusicInfoRaw]?

  private enum CodingKeys: String, CodingKey {
    case title, artist, artists, year, overview, tracks
    case artistIDs = "artist_ids"
    case albumType = "album_type"
    case totalTracks = "total_tracks"
    case coverURL = "cover_url"
    case posterPath = "poster_path"
  }
}

/// `GET /api/v1/music/artist/{id}` 解码结构。
private struct NativeMusicArtistRaw: Decodable, Sendable {
  let name: String?
  let title: String?
  let country: String?
  let area: String?
  let lifeSpan: String?
  let imageURL: String?
  let posterPath: String?
  let overview: String?

  /// 优先显示规范艺人名称。
  var displayName: String? { name ?? title }

  private enum CodingKeys: String, CodingKey {
    case name, title, country, area, overview
    case lifeSpan = "life_span"
    case imageURL = "image_url"
    case posterPath = "poster_path"
  }
}
