import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生影视详情页：全宽背景头图、订阅与媒体库状态操作栏、分季列表、演职员横栏与相似推荐。
@MainActor
struct NativeMediaDetailPage: View {
  let session: NativeSession
  let identity: NativeMediaIdentity

  @State private var detail: NativeMediaDetailPayload?
  @State private var status = NativeMediaStatusSnapshot()
  @State private var credits: [NativeMediaPersonItem] = []
  @State private var recommendations: [NativeMediaSummaryItem] = []
  @State private var failed = false
  @State private var attempt = 0
  @State private var isLoading = true
  @State private var synopsisExpanded = false
  @State private var mutatingSeason: Int?
  @State private var isMutatingMovie = false
  @State private var isLaunchingPlayback = false
  @State private var pendingCancelSeason: NativeSeasonCancelTarget?
  @State private var actionFeedback: NativeDetailActionFeedback?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// 按当前认证会话直接加载单部影视详情、入库/订阅状态、演职员与推荐；不借 WebView。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if let detail {
            heroSection(detail)
            VStack(alignment: .leading, spacing: 24) {
              if let actionFeedback {
                feedbackBanner(actionFeedback)
              }
              actionBar(detail)
              synopsisSection(detail)
              if isTelevision(detail), !resolvedSeasons(detail).isEmpty {
                seasonsSection(detail, seasons: resolvedSeasons(detail))
              }
              if !displayCast(detail).isEmpty {
                castSection(displayCast(detail))
              }
              if !recommendations.isEmpty {
                recommendationsSection
              }
              metadataPanel(detail)
            }
            .padding(.horizontal, CinematicStyle.margin)
            .padding(.top, 8)
            .padding(.bottom, 36)
          } else if failed {
            failureState
              .padding(.horizontal, CinematicStyle.margin)
              .padding(.top, 110)
          } else {
            ProgressView("正在载入作品详情…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 280)
              .padding(.top, 110)
          }
        }
      }
      .scrollIndicators(.hidden)
      .ignoresSafeArea(edges: .top)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-media-detail-scroll")
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task(id: attempt) { await loadAll() }
    .alert(
      "取消订阅",
      isPresented: Binding(
        get: { pendingCancelSeason != nil },
        set: { if !$0 { pendingCancelSeason = nil } }
      ),
      presenting: pendingCancelSeason
    ) { target in
      Button("取消订阅", role: .destructive) {
        Task { await performUnsubscribe(season: target.season) }
      }
      Button("保留", role: .cancel) {}
    } message: { target in
      Text(target.message)
    }
  }

  /// 当前账号具备订阅权限时才展示显式订阅动作，权限仍由后端最终校验。
  private var canSubscribe: Bool {
    session.user.allows(.init(category: .subscribe))
  }

  /// 当前账号具备 PT 资源搜索权限时展示直达资源搜索入口。
  private var canSearchResources: Bool {
    session.user.allows(.init(category: .search))
  }

  /// 全宽剧照延伸至顶部安全区，经多段柔边融入 Cinematic 底色并浮置片名与核心元数据。
  private func heroSection(_ detail: NativeMediaDetailPayload) -> some View {
    let heroHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 470 : 410
    let backdrop = Self.resolveArtwork(
      detail.backdropPath ?? detail.posterPath, source: detail.mediaSource ?? identity.source)
    return ZStack(alignment: .bottomLeading) {
      NativeMediaArtwork(
        session: session, reference: backdrop, role: .backdrop, maximumWidth: 1280
      )
      .frame(maxWidth: .infinity)
      .frame(height: heroHeight)
      .clipped()
      .overlay(alignment: .top) {
        LinearGradient(
          colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: .bottom
        )
        .frame(height: 110)
      }
      .overlay {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0.30),
            .init(
              color: Color(red: 22 / 255, green: 19 / 255, blue: 32 / 255).opacity(0.58),
              location: 0.68),
            .init(
              color: Color(red: 28 / 255, green: 24 / 255, blue: 38 / 255).opacity(0.95),
              location: 0.94),
            .init(color: .clear, location: 1.0),
          ], startPoint: .top, endPoint: .bottom)
      }
      .mask(
        LinearGradient(
          stops: [
            .init(color: .white, location: 0),
            .init(color: .white, location: 0.66),
            .init(color: .white.opacity(0.55), location: 0.88),
            .init(color: .clear, location: 1),
          ], startPoint: .top, endPoint: .bottom))
      VStack(alignment: .leading, spacing: 10) {
        Text(detail.title ?? "未命名作品")
          .font(.system(.largeTitle, design: .serif).weight(.bold))
          .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
          .accessibilityIdentifier("native-media-detail-title")
        if let tagline = detail.tagline?.trimmingCharacters(in: .whitespacesAndNewlines),
          !tagline.isEmpty
        {
          Text(tagline)
            .font(.subheadline.italic())
            .foregroundStyle(.white.opacity(0.76))
            .lineLimit(2)
        }
        let summaryParts = metadataLineParts(detail)
        if !summaryParts.isEmpty {
          Text(summaryParts.joined(separator: "  ·  "))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.84))
        }
        HStack(spacing: 10) {
          if let rating = detail.voteAverage, rating > 0 {
            Label(String(format: "%.1f", rating), systemImage: "star.fill")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.yellow)
          }
          if let server = status.server, !server.isEmpty, status.itemID != nil {
            Label("已在 \(server) 入库", systemImage: "checkmark.seal.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color(red: 0.56, green: 0.92, blue: 0.72))
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background {
                Capsule()
                  .fill(Color(red: 0.16, green: 0.36, blue: 0.28).opacity(0.55))
                  .overlay {
                    Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6)
                  }
              }
              .accessibilityIdentifier("native-media-detail-library-badge")
          }
        }
        let genres = detail.genreNames.prefix(4)
        if !genres.isEmpty {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(Array(genres), id: \.self) { genre in
                Text(genre)
                  .font(.caption.weight(.medium))
                  .foregroundStyle(.white.opacity(0.88))
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background {
                    Capsule()
                      .fill(.white.opacity(0.12))
                      .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5) }
                  }
              }
            }
          }
          .scrollIndicators(.hidden)
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
      .padding(.bottom, 16)
    }
  }

  /// 主操作区遵循 Liquid Glass 分组规范：按权限展示订阅开关、资源搜索与入库状态，不伪造未接入动作。
  @ViewBuilder
  private func actionBar(_ detail: NativeMediaDetailPayload) -> some View {
    let tv = isTelevision(detail)
    let subscribedCount = status.seasons.count
    if canSubscribe || canSearchResources || status.itemID != nil {
      CinematicGlassGroup {
        HStack(spacing: 12) {
          if let itemID = status.itemID, !itemID.isEmpty {
            CinematicPrimaryAction(
              title: isLaunchingPlayback ? "准备播放…" : "立即播放",
              symbol: "play.fill"
            ) {
              Task {
                isLaunchingPlayback = true
                let posterRaw = Self.resolveArtwork(
                  detail.posterPath ?? detail.backdropPath,
                  source: detail.mediaSource ?? identity.source)
                let artworkURL = NativeMediaPlaybackLauncher.proxiedArtworkURL(
                  session: session, raw: posterRaw)
                let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
                  session: session,
                  itemID: itemID,
                  server: status.server,
                  title: detail.title ?? "播放",
                  artworkURL: artworkURL)
                isLaunchingPlayback = false
                if let err {
                  actionFeedback = NativeDetailActionFeedback(isError: true, message: err)
                }
              }
            }
            .disabled(isLaunchingPlayback)
            .accessibilityIdentifier("native-media-detail-play")
          }
          if canSubscribe {
            if tv {
              let seasons = resolvedSeasons(detail)
              let primarySeason = seasons.first(where: { $0.seasonNumber > 0 })?.seasonNumber ?? 1
              let anySubscribed = subscribedCount > 0
              CinematicPrimaryAction(
                title: anySubscribed ? "已订阅 \(subscribedCount) 季" : "订阅第 \(primarySeason) 季",
                symbol: anySubscribed ? "bookmark.fill" : "bookmark"
              ) {
                if !anySubscribed {
                  Task { await performSubscribe(season: primarySeason) }
                } else {
                  pendingCancelSeason = NativeSeasonCancelTarget(
                    season: status.seasons.keys.sorted().first,
                    message:
                      "确认取消《\(detail.title ?? "该剧集")》第 \(status.seasons.keys.sorted().first ?? primarySeason) 季的订阅吗？"
                  )
                }
              }
              .disabled(mutatingSeason != nil)
              .accessibilityIdentifier("native-media-detail-subscribe")
            } else {
              CinematicPrimaryAction(
                title: isMutatingMovie
                  ? "正在提交…" : (status.subscribed ? "已订阅 · 取消" : "添加订阅"),
                symbol: status.subscribed ? "bookmark.fill" : "bookmark"
              ) {
                if status.subscribed {
                  pendingCancelSeason = NativeSeasonCancelTarget(
                    season: nil,
                    message: "确认取消《\(detail.title ?? "该作品")》的订阅吗？")
                } else {
                  Task { await performSubscribe(season: nil) }
                }
              }
              .disabled(isMutatingMovie)
              .accessibilityIdentifier("native-media-detail-subscribe")
            }
          }
          if canSearchResources {
            NavigationLink {
              NativeResourceSearchPage(
                session: session,
                target: .media(
                  identity: identity, title: detail.title ?? "作品资源", season: nil))
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                  .font(.subheadline.weight(.semibold))
                Text("搜索资源")
                  .font(.subheadline.weight(.semibold))
              }
              .foregroundStyle(.white)
              .padding(.horizontal, 16)
              .frame(height: 50)
              .background {
                Capsule()
                  .fill(.white.opacity(0.14))
                  .overlay { Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.7) }
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索站点资源")
            .accessibilityIdentifier("native-media-detail-search-resources")
          }
          if let server = status.server, !server.isEmpty, status.itemID != nil {
            CinematicCircleButton(title: "已入库 · \(server)", symbol: "play.tv.fill") {
              actionFeedback = NativeDetailActionFeedback(
                isError: false, message: "该作品已收录于 \(server) 媒体库。")
            }
            .accessibilityIdentifier("native-media-detail-library-action")
          }
        }
      }
    }
  }

  /// 操作反馈只显示安全摘要文本，支持点击关闭，不泄漏后端内部错误细节。
  private func feedbackBanner(_ feedback: NativeDetailActionFeedback) -> some View {
    CinematicPanel(padding: 12) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
        Text(feedback.message)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          actionFeedback = nil
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65))
            .frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭提示")
      }
    }
    .accessibilityIdentifier("native-media-detail-feedback")
  }

  /// 剧情简介默认保留优雅阅读行距，长文本提供原地展开/收起。
  @ViewBuilder
  private func synopsisSection(_ detail: NativeMediaDetailPayload) -> some View {
    if let overview = detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
      !overview.isEmpty
    {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 10) {
          Text("剧情简介")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          Text(overview)
            .font(.body)
            .lineSpacing(5)
            .foregroundStyle(.white.opacity(0.84))
            .lineLimit(synopsisExpanded ? nil : 5)
          if overview.count > 120 {
            Button(synopsisExpanded ? "收起简介" : "展开全部") {
              withAnimation(.easeInOut(duration: 0.2)) { synopsisExpanded.toggle() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  /// 剧集分季卡片展示真实海报、集数与各季独立订阅状态。
  private func seasonsSection(_ detail: NativeMediaDetailPayload, seasons: [NativeMediaSeasonItem])
    -> some View
  {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("剧集分季")
          .font(.title3.weight(.bold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Text("共 \(seasons.count) 季")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.62))
      }
      VStack(spacing: 12) {
        ForEach(seasons) { season in
          seasonRow(detail, season: season)
        }
      }
    }
  }

  /// 单季透色玻璃卡片：2:3 季海报 + 季名/年份/集数 + 独立订阅按钮。
  private func seasonRow(_ detail: NativeMediaDetailPayload, season: NativeMediaSeasonItem)
    -> some View
  {
    let isSubscribed = status.seasons[season.seasonNumber] != nil
    let isMutating = mutatingSeason == season.seasonNumber
    let poster = Self.resolveArtwork(
      season.posterPath ?? detail.posterPath, source: detail.mediaSource ?? identity.source)
    return CinematicPanel(padding: 12) {
      HStack(alignment: .top, spacing: 12) {
        NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 240)
          .frame(width: 62, height: 93)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
          }
        VStack(alignment: .leading, spacing: 5) {
          Text(season.displayTitle)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
          let meta = seasonMetadata(season)
          if !meta.isEmpty {
            Text(meta)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.66))
          }
          if let overview = season.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
            !overview.isEmpty
          {
            Text(overview)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.74))
              .lineLimit(2)
          }
          if canSubscribe {
            Button {
              if isSubscribed {
                pendingCancelSeason = NativeSeasonCancelTarget(
                  season: season.seasonNumber,
                  message: "确认取消《\(detail.title ?? "该剧集")》\(season.displayTitle)的订阅吗？")
              } else {
                Task { await performSubscribe(season: season.seasonNumber) }
              }
            } label: {
              HStack(spacing: 5) {
                if isMutating {
                  ProgressView().controlSize(.mini).tint(.white)
                } else {
                  Image(systemName: isSubscribed ? "bookmark.fill" : "plus")
                    .font(.caption2.weight(.semibold))
                }
                Text(isSubscribed ? "已订阅" : "订阅本季")
                  .font(.caption.weight(.semibold))
              }
              .foregroundStyle(.white)
              .padding(.horizontal, 11)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(
                    isSubscribed
                      ? Color(red: 0.45, green: 0.34, blue: 0.68).opacity(0.72)
                      : .white.opacity(0.14)
                  )
                  .overlay {
                    Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                  }
              }
              .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
            .disabled(mutatingSeason != nil)
            .padding(.top, 2)
            .accessibilityIdentifier("native-media-detail-season-subscribe-\(season.seasonNumber)")
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  /// 演职员采用 Cinematic 圆形头像横栏，具备 TMDB 人物 ID 时支持推入人物详情页。
  private func castSection(_ people: [NativeMediaPersonItem]) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("演职员")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          ForEach(people.prefix(18)) { person in
            if let personID = person.numericID,
              person.source?.lowercased() ?? "themoviedb" == "themoviedb"
            {
              NavigationLink {
                NativePersonDetailPage(
                  session: session, personID: personID, fallbackName: person.displayName,
                  fallbackAvatar: Self.resolveArtwork(person.artworkPath, source: person.source))
              } label: {
                personCard(person)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-media-detail-cast-\(personID)")
            } else {
              personCard(person)
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .accessibilityIdentifier("native-media-detail-cast")
  }

  /// 单个圆形演员头像与角色名卡片。
  private func personCard(_ person: NativeMediaPersonItem) -> some View {
    let avatar = Self.resolveArtwork(person.artworkPath, source: person.source ?? "themoviedb")
    return VStack(spacing: 7) {
      Group {
        if let avatar {
          NativeMediaArtwork(session: session, reference: avatar, role: .poster, maximumWidth: 200)
        } else {
          ZStack {
            Circle().fill(.white.opacity(0.10))
            Image(systemName: "person.fill").font(.title3).foregroundStyle(.white.opacity(0.55))
          }
        }
      }
      .frame(width: 72, height: 72)
      .clipShape(Circle())
      .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.6) }
      Text(person.displayName)
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .lineLimit(1)
      if let role = person.subtitle, !role.isEmpty {
        Text(role)
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.58))
          .lineLimit(1)
      }
    }
    .frame(width: 80)
    .multilineTextAlignment(.center)
  }

  /// 推荐/相似作品横向海报栏，点击后在同一原生 NavigationStack 推入下一部详情。
  private var recommendationsSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("你可能也喜欢")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 12) {
          ForEach(recommendations.prefix(16)) { item in
            if let nextIdentity = item.identity {
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: nextIdentity)
              } label: {
                recommendationCard(item)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-media-detail-recommend-\(nextIdentity.id)")
            } else {
              recommendationCard(item)
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .accessibilityIdentifier("native-media-detail-recommendations")
  }

  /// 与发现页一致的 2:3 居中海报推荐卡片。
  private func recommendationCard(_ item: NativeMediaSummaryItem) -> some View {
    let poster = Self.resolveArtwork(item.posterPath, source: item.mediaSource ?? "themoviedb")
    return VStack(spacing: 6) {
      NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 420)
        .frame(width: 108, height: 162)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
      Text(item.title ?? "未命名作品")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white)
        .lineLimit(1)
      if let year = item.year, !year.isEmpty {
        Text(year)
          .font(.caption)
          .foregroundStyle(.white.opacity(0.56))
          .lineLimit(1)
      }
    }
    .frame(width: 108)
    .multilineTextAlignment(.center)
  }

  /// 补充作品资料卡（导演、状态、地区与来源标识），采用低遮罩透色玻璃容器。
  @ViewBuilder
  private func metadataPanel(_ detail: NativeMediaDetailPayload) -> some View {
    let rows = metadataRows(detail)
    if !rows.isEmpty {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 12) {
          Text("作品资料")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            if index > 0 {
              Divider().overlay(.white.opacity(0.08))
            }
            HStack(alignment: .top, spacing: 12) {
              Text(row.label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.60))
                .frame(minWidth: 68, alignment: .leading)
              Text(row.value)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            }
          }
        }
      }
    }
  }

  /// 详情加载失败时提供清晰的重试面板，不暴露服务器内部错误文本。
  private var failureState: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 12) {
        Label("暂时无法载入作品详情", systemImage: "exclamationmark.triangle")
          .font(.headline)
        Button("重新载入") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-media-detail-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 并行读取核心详情与状态/演职员/推荐；次要区块失败不阻断核心详情呈现。
  private func loadAll() async {
    failed = false
    isLoading = true
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["media", identity.mediaID],
        query: [
          URLQueryItem(name: "media_source", value: identity.source),
          URLQueryItem(name: "type_name", value: identity.type),
        ])
      let loaded = try await session.request(
        endpoint, as: NativeMediaDetailPayload.self, requiring: .init(category: .discovery)
      ).value
      try Task.checkCancellation()
      guard loaded.title?.isEmpty == false else {
        failed = true
        return
      }
      detail = loaded

      let tmdbID = loaded.tmdbID ?? (identity.source == "themoviedb" ? Int(identity.mediaID) : nil)
      let mediaType = loaded.type ?? identity.type

      async let statusTask = loadMediaStatus(loaded)
      async let creditsTask = loadCredits(tmdbID: tmdbID, type: mediaType)
      async let recommendTask = loadRecommendations(tmdbID: tmdbID, type: mediaType)
      let (loadedStatus, loadedCredits, loadedRecommendations) = await (
        statusTask, creditsTask, recommendTask
      )
      guard !Task.isCancelled else { return }
      if let loadedStatus { status = loadedStatus }
      if !loadedCredits.isEmpty { credits = loadedCredits }
      recommendations = loadedRecommendations
    } catch is CancellationError {
      return
    } catch {
      failed = true
    }
  }

  /// 单次请求查询本地媒体库入库状态与当前账号各季订阅状态。
  private func loadMediaStatus(_ loaded: NativeMediaDetailPayload) async
    -> NativeMediaStatusSnapshot?
  {
    let payload = [
      NativeMediaStatusQuery(
        mediaSource: loaded.mediaSource ?? identity.source,
        mediaID: loaded.mediaID ?? identity.mediaID,
        mtype: loaded.type ?? identity.type,
        title: loaded.title,
        year: loaded.year)
    ]
    guard let body = try? JSONEncoder().encode(payload),
      let endpoint = try? APIEndpoint(path: ["media", "status"], method: .post, body: body)
    else { return nil }
    return try? await session.request(
      endpoint, as: [NativeMediaStatusSnapshot].self, requiring: .init(category: .discovery)
    ).value.first
  }

  /// 读取 TMDB 演职员列表，缺省时页面自动回落到详情内嵌的 actors。
  private func loadCredits(tmdbID: Int?, type: String) async -> [NativeMediaPersonItem] {
    guard let tmdbID,
      let endpoint = try? APIEndpoint(
        path: ["tmdb", "credits", String(tmdbID), type],
        query: [URLQueryItem(name: "page", value: "1")])
    else { return [] }
    return
      (try? await session.request(
        endpoint, as: [NativeMediaPersonItem].self, requiring: .init(category: .discovery)
      ).value) ?? []
  }

  /// 读取 TMDB 推荐作品；若推荐为空则尝试相似作品作为补充。
  private func loadRecommendations(tmdbID: Int?, type: String) async -> [NativeMediaSummaryItem] {
    guard let tmdbID else { return [] }
    if let recEndpoint = try? APIEndpoint(
      path: ["tmdb", "recommend", String(tmdbID), type],
      query: [URLQueryItem(name: "page", value: "1")]),
      let items = try? await session.request(
        recEndpoint, as: [NativeMediaSummaryItem].self, requiring: .init(category: .discovery)
      ).value,
      !items.isEmpty
    {
      return items
    }
    guard
      let simEndpoint = try? APIEndpoint(
        path: ["tmdb", "similar", String(tmdbID), type],
        query: [URLQueryItem(name: "page", value: "1")])
    else { return [] }
    return
      (try? await session.request(
        simEndpoint, as: [NativeMediaSummaryItem].self, requiring: .init(category: .discovery)
      ).value) ?? []
  }

  /// 显式单次提交订阅新增请求；绝不自动重试，成功后重新同步媒体状态。
  private func performSubscribe(season: Int?) async {
    guard let detail, canSubscribe else { return }
    if let season {
      mutatingSeason = season
    } else {
      isMutatingMovie = true
    }
    defer {
      mutatingSeason = nil
      isMutatingMovie = false
    }
    do {
      let body = try JSONEncoder().encode(
        NativeSubscribeCreatePayload(
          name: detail.title ?? "",
          type: detail.type ?? identity.type,
          year: detail.year ?? "",
          mediaSource: detail.mediaSource ?? identity.source,
          mediaID: detail.mediaID ?? identity.mediaID,
          season: isTelevision(detail) ? season : nil))
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      if let season {
        status.seasons[season] = "normal"
      } else {
        status.subscribed = true
      }
      if let refreshed = await loadMediaStatus(detail) {
        status = refreshed
      }
      actionFeedback = NativeDetailActionFeedback(
        isError: false,
        message: season.map { "已添加第 \($0) 季订阅。" } ?? "已添加订阅。")
    } catch is CancellationError {
      return
    } catch {
      actionFeedback = NativeDetailActionFeedback(
        isError: true, message: "订阅请求失败，请稍后重试。")
    }
  }

  /// 确认后单次提交取消订阅，不自动重试，成功后刷新状态。
  private func performUnsubscribe(season: Int?) async {
    guard let detail, canSubscribe else { return }
    if let season {
      mutatingSeason = season
    } else {
      isMutatingMovie = true
    }
    defer {
      mutatingSeason = nil
      isMutatingMovie = false
    }
    do {
      var query = [
        URLQueryItem(name: "media_source", value: detail.mediaSource ?? identity.source)
      ]
      if let season, isTelevision(detail) {
        query.append(URLQueryItem(name: "season", value: String(season)))
      }
      let endpoint = try APIEndpoint(
        path: ["subscribe", "media", detail.mediaID ?? identity.mediaID],
        method: .delete, query: query)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      if let season {
        status.seasons.removeValue(forKey: season)
      } else {
        status.subscribed = false
      }
      if let refreshed = await loadMediaStatus(detail) {
        status = refreshed
      }
      actionFeedback = NativeDetailActionFeedback(
        isError: false,
        message: season.map { "已取消第 \($0) 季订阅。" } ?? "已取消订阅。")
    } catch is CancellationError {
      return
    } catch {
      actionFeedback = NativeDetailActionFeedback(
        isError: true, message: "取消订阅失败，请稍后重试。")
    }
  }

  /// 区分电视剧与电影布局分支。
  private func isTelevision(_ detail: NativeMediaDetailPayload) -> Bool {
    (detail.type ?? identity.type) == "电视剧"
  }

  /// 优先展示正片季（季号 >= 1），特别篇（0 季）排在末尾。
  private func resolvedSeasons(_ detail: NativeMediaDetailPayload) -> [NativeMediaSeasonItem] {
    let all = detail.seasonInfo ?? []
    let regular = all.filter { $0.seasonNumber > 0 }.sorted { $0.seasonNumber < $1.seasonNumber }
    let specials = all.filter { $0.seasonNumber == 0 }
    return regular + specials
  }

  /// 优先展示 TMDB credits 接口返回的完整演员阵容，无结果时回落到详情内嵌演员。
  private func displayCast(_ detail: NativeMediaDetailPayload) -> [NativeMediaPersonItem] {
    credits.isEmpty ? (detail.actors ?? []) : credits
  }

  /// 拼装头图下方的年份、类型、时长/季数与分级摘要。
  private func metadataLineParts(_ detail: NativeMediaDetailPayload) -> [String] {
    var parts: [String] = []
    if let year = detail.year, !year.isEmpty { parts.append(year) }
    parts.append(detail.type ?? identity.type)
    if let runtime = detail.runtime, runtime > 0 {
      parts.append("\(runtime) 分钟")
    } else if let seasonsCount = detail.numberOfSeasons, seasonsCount > 0 {
      parts.append("\(seasonsCount) 季")
    }
    if let rating = detail.contentRating, !rating.isEmpty {
      parts.append(rating)
    }
    return parts
  }

  /// 拼装单季副标（首播年份与集数）。
  private func seasonMetadata(_ season: NativeMediaSeasonItem) -> String {
    var parts: [String] = []
    if let date = season.airDate, date.count >= 4 {
      parts.append(String(date.prefix(4)))
    }
    if let count = season.episodeCount, count > 0 {
      parts.append("\(count) 集")
    }
    return parts.joined(separator: " · ")
  }

  /// 构造底部资料卡的键值明细行。
  private func metadataRows(_ detail: NativeMediaDetailPayload) -> [(label: String, value: String)]
  {
    var rows: [(String, String)] = []
    if let original = detail.originalTitle, !original.isEmpty, original != detail.title {
      rows.append(("原名", original))
    }
    let directors = (detail.directors ?? []).map(\.displayName).filter { !$0.isEmpty }
    if !directors.isEmpty {
      rows.append(("导演", directors.prefix(3).joined(separator: "、")))
    }
    if let release = detail.releaseDate, !release.isEmpty {
      rows.append(("上映/首播", release))
    }
    if let statusText = detail.status, !statusText.isEmpty {
      rows.append(("状态", statusText))
    }
    let countries = (detail.productionCountries ?? []).compactMap(\.name).filter { !$0.isEmpty }
    if !countries.isEmpty {
      rows.append(("地区", countries.prefix(3).joined(separator: " / ")))
    }
    if let imdb = detail.imdbID, !imdb.isEmpty {
      rows.append(("IMDb", imdb))
    }
    return rows
  }

  /// 将后端 TMDB 相对图片路径安全补全为 HTTPS 源地址，仍经同源后端图片代理获取。
  static func resolveArtwork(_ raw: String?, source: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
      return trimmed
    }
    guard trimmed.hasPrefix("/"), !trimmed.contains(".."), !trimmed.contains(" "),
      (source ?? "themoviedb").lowercased() == "themoviedb"
    else { return nil }
    return "https://image.tmdb.org/t/p/w500" + trimmed
  }
}

/// 原生人物详情页：展示人物头像、简介与参演作品网格，可继续推入任意影视详情。
@MainActor
struct NativePersonDetailPage: View {
  let session: NativeSession
  let personID: Int
  let fallbackName: String
  let fallbackAvatar: String?

  @State private var person: NativeMediaPersonItem?
  @State private var works: [NativeMediaSummaryItem] = []
  @State private var failed = false
  @State private var attempt = 0
  @State private var bioExpanded = false
  @ScaledMetric(relativeTo: .body) private var tileWidth = 104.0

  /// 采用统一 Cinematic 连续渐变与透色卡片，不依赖任何网页视图。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          if let bio = person?.biography?.trimmingCharacters(in: .whitespacesAndNewlines),
            !bio.isEmpty
          {
            CinematicPanel {
              VStack(alignment: .leading, spacing: 10) {
                Text("人物简介").font(.headline).accessibilityAddTraits(.isHeader)
                Text(bio)
                  .font(.body)
                  .lineSpacing(5)
                  .foregroundStyle(.white.opacity(0.84))
                  .lineLimit(bioExpanded ? nil : 5)
                if bio.count > 120 {
                  Button(bioExpanded ? "收起简介" : "展开全部") {
                    withAnimation(.easeInOut(duration: 0.2)) { bioExpanded.toggle() }
                  }
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white.opacity(0.75))
                  .buttonStyle(.plain)
                }
              }
            }
          }
          if !works.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
              Text("参演作品")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 11)], spacing: 18
              ) {
                ForEach(works) { item in
                  if let identity = item.identity {
                    NavigationLink {
                      NativeMediaDetailPage(session: session, identity: identity)
                    } label: {
                      workTile(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("native-person-work-\(identity.id)")
                  } else {
                    workTile(item)
                  }
                }
              }
            }
          } else if failed {
            CinematicPanel {
              VStack(alignment: .leading, spacing: 10) {
                Label("暂时无法载入人物资料", systemImage: "exclamationmark.triangle")
                  .font(.headline)
                Button("重新载入") { attempt += 1 }
                  .frame(minHeight: 44)
                  .accessibilityIdentifier("native-person-detail-retry")
              }
            }
          }
        }
        .frame(maxWidth: 900)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-person-detail-scroll")
    }
    .navigationTitle(person?.displayName ?? fallbackName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task(id: attempt) { await load() }
  }

  /// 居中人物圆形肖像与基础履历信息。
  private var header: some View {
    let avatar =
      NativeMediaDetailPage.resolveArtwork(person?.artworkPath, source: "themoviedb")
      ?? fallbackAvatar
    return VStack(spacing: 12) {
      Group {
        if let avatar {
          NativeMediaArtwork(session: session, reference: avatar, role: .poster, maximumWidth: 320)
        } else {
          ZStack {
            Circle().fill(.white.opacity(0.10))
            Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.55))
          }
        }
      }
      .frame(width: 112, height: 112)
      .clipShape(Circle())
      .overlay { Circle().strokeBorder(.white.opacity(0.20), lineWidth: 0.8) }
      Text(person?.displayName ?? fallbackName)
        .font(.title2.weight(.bold))
        .accessibilityIdentifier("native-person-detail-name")
      let facts = [
        person?.knownForDepartment,
        person?.birthday,
        person?.placeOfBirth,
      ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      if !facts.isEmpty {
        Text(facts.joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.72))
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 人物参演作品的 2:3 居中海报单元格。
  private func workTile(_ item: NativeMediaSummaryItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.posterPath, source: item.mediaSource ?? "themoviedb")
    return VStack(spacing: 6) {
      Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
        .overlay {
          NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 420)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
      Text(item.title ?? "未命名作品").font(.footnote.weight(.medium)).lineLimit(2)
      if let year = item.year, !year.isEmpty {
        Text(year).font(.caption).foregroundStyle(.white.opacity(0.56))
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .multilineTextAlignment(.center)
  }

  /// 并行读取人物资料与参演作品列表。
  private func load() async {
    failed = false
    do {
      let personEndpoint = try APIEndpoint(path: ["tmdb", "person", String(personID)])
      let creditsEndpoint = try APIEndpoint(
        path: ["tmdb", "person", "credits", String(personID)],
        query: [URLQueryItem(name: "page", value: "1")])
      async let personTask = try? session.request(
        personEndpoint, as: NativeMediaPersonItem.self, requiring: .init(category: .discovery)
      ).value
      async let worksTask = try? session.request(
        creditsEndpoint, as: [NativeMediaSummaryItem].self, requiring: .init(category: .discovery)
      ).value
      let (loadedPerson, loadedWorks) = await (personTask, worksTask)
      guard !Task.isCancelled else { return }
      person = loadedPerson
      works = loadedWorks ?? []
      if loadedPerson == nil && works.isEmpty { failed = true }
    } catch {
      failed = true
    }
  }
}

/// 取消订阅确认弹窗的语义载体。
private struct NativeSeasonCancelTarget: Identifiable {
  let id = UUID()
  let season: Int?
  let message: String
}

/// 订阅操作的轻量结果提示。
private struct NativeDetailActionFeedback {
  let isError: Bool
  let message: String
}

/// 批量媒体状态查询请求项。
private struct NativeMediaStatusQuery: Encodable {
  let mediaSource: String
  let mediaID: String
  let mtype: String
  let title: String?
  let year: String?

  /// 匹配 `POST /api/v1/media/status` 的 snake_case 契约。
  private enum CodingKeys: String, CodingKey {
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case mtype
    case title
    case year
  }
}

/// `POST /api/v1/media/status` 返回的单条入库与订阅快照。
private struct NativeMediaStatusSnapshot: Decodable, Sendable {
  var itemID: String?
  var server: String?
  var subscribed: Bool = false
  var seasons: [Int: String] = [:]

  /// 允许缺省字段以兼容无入库/无订阅作品。
  init(
    itemID: String? = nil, server: String? = nil, subscribed: Bool = false,
    seasons: [Int: String] = [:]
  ) {
    self.itemID = itemID
    self.server = server
    self.subscribed = subscribed
    self.seasons = seasons
  }

  /// 兼容后端 seasons 字典键为字符串数字的 JSON 序列化。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let text = try? container.decodeIfPresent(String.self, forKey: .itemID) {
      itemID = text
    } else if let num = try? container.decodeIfPresent(Int64.self, forKey: .itemID) {
      itemID = String(num)
    } else {
      itemID = nil
    }
    server = try container.decodeIfPresent(String.self, forKey: .server)
    subscribed = try container.decodeIfPresent(Bool.self, forKey: .subscribed) ?? false
    let rawSeasons =
      try container.decodeIfPresent([String: String].self, forKey: .seasons) ?? [:]
    var parsed: [Int: String] = [:]
    for (key, value) in rawSeasons {
      if let number = Int(key) { parsed[number] = value }
    }
    seasons = parsed
  }

  /// 后端状态字段映射。
  private enum CodingKeys: String, CodingKey {
    case itemID = "item_id"
    case server
    case subscribed
    case seasons
  }
}

/// `POST /api/v1/subscribe/` 的显式创建载荷。
private struct NativeSubscribeCreatePayload: Encodable {
  let name: String
  let type: String
  let year: String
  let mediaSource: String
  let mediaID: String
  let season: Int?

  /// 匹配后端 `_SchemaSubscribe` 写入契约。
  private enum CodingKeys: String, CodingKey {
    case name
    case type
    case year
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case season
  }
}

/// 完整影视详情响应投影，覆盖基础信息、时长、分级、分季与内嵌演职员。
private struct NativeMediaDetailPayload: Decodable, Sendable {
  /// 后端影视风格或国家对象。
  struct NamedTag: Decodable, Sendable { let name: String? }

  let mediaSource: String?
  let mediaID: String?
  let tmdbID: Int?
  let imdbID: String?
  let type: String?
  let title: String?
  let originalTitle: String?
  let year: String?
  let releaseDate: String?
  let runtime: Int?
  let status: String?
  let tagline: String?
  let contentRating: String?
  let numberOfSeasons: Int?
  let numberOfEpisodes: Int?
  let posterPath: String?
  let backdropPath: String?
  let overview: String?
  let voteAverage: Double?
  let genres: [NamedTag]?
  let productionCountries: [NamedTag]?
  let seasonInfo: [NativeMediaSeasonItem]?
  let actors: [NativeMediaPersonItem]?
  let directors: [NativeMediaPersonItem]?

  /// 提取清洗后的风格名称列表。
  var genreNames: [String] {
    (genres ?? []).compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  /// 对应后端 `MediaInfo` 的 snake_case 字段。
  private enum CodingKeys: String, CodingKey {
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case imdbID = "imdb_id"
    case type
    case title
    case originalTitle = "original_title"
    case year
    case releaseDate = "release_date"
    case runtime
    case status
    case tagline
    case contentRating = "content_rating"
    case numberOfSeasons = "number_of_seasons"
    case numberOfEpisodes = "number_of_episodes"
    case posterPath = "poster_path"
    case backdropPath = "backdrop_path"
    case overview
    case voteAverage = "vote_average"
    case genres
    case productionCountries = "production_countries"
    case seasonInfo = "season_info"
    case actors
    case directors
  }
}

/// 剧集单季信息投影。
private struct NativeMediaSeasonItem: Decodable, Sendable, Identifiable {
  let seasonNumber: Int
  let name: String?
  let airDate: String?
  let episodeCount: Int?
  let overview: String?
  let posterPath: String?

  /// 季号作为单季列表稳定标识。
  var id: Int { seasonNumber }

  /// 后端缺省季名时使用本地第 N 季 / 特别篇标题。
  var displayTitle: String {
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    return seasonNumber == 0 ? "特别篇" : "第 \(seasonNumber) 季"
  }

  /// 兼容 `season_info` 的字段键。
  private enum CodingKeys: String, CodingKey {
    case seasonNumber = "season_number"
    case name
    case airDate = "air_date"
    case episodeCount = "episode_count"
    case overview
    case posterPath = "poster_path"
  }
}

/// 演职员与人物详情共享投影，兼容列表项与 `/tmdb/person/{id}`。
private struct NativeMediaPersonItem: Decodable, Sendable, Identifiable {
  let source: String?
  let numericID: Int?
  let name: String?
  let originalName: String?
  let character: String?
  let knownForDepartment: String?
  let profilePath: String?
  let avatar: String?
  let birthday: String?
  let placeOfBirth: String?
  let biography: String?

  /// 结合数值 ID 与姓名保证列表键唯一。
  var id: String {
    if let numericID { return "p:\(numericID)" }
    return "n:\(displayName):\(character ?? "")"
  }

  /// 优先展示本地化姓名，缺省回落原名。
  var displayName: String {
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    if let originalName = originalName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !originalName.isEmpty
    {
      return originalName
    }
    return "演职员"
  }

  /// 角色或职业副标。
  var subtitle: String? {
    if let character = character?.trimmingCharacters(in: .whitespacesAndNewlines),
      !character.isEmpty
    {
      return character
    }
    return knownForDepartment
  }

  /// 统一提取人物头像引用。
  var artworkPath: String? {
    if let profilePath, !profilePath.isEmpty { return profilePath }
    if let avatar, !avatar.isEmpty { return avatar }
    return nil
  }

  /// 兼容后端 `id` 为整型或字符串数字的格式差异。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    source = try container.decodeIfPresent(String.self, forKey: .source)
    if let intID = try? container.decodeIfPresent(Int.self, forKey: .id) {
      numericID = intID
    } else if let strID = try? container.decodeIfPresent(String.self, forKey: .id) {
      numericID = Int(strID)
    } else {
      numericID = nil
    }
    name = try container.decodeIfPresent(String.self, forKey: .name)
    originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
    character = try container.decodeIfPresent(String.self, forKey: .character)
    knownForDepartment = try container.decodeIfPresent(String.self, forKey: .knownForDepartment)
    profilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
    avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
    birthday = try container.decodeIfPresent(String.self, forKey: .birthday)
    placeOfBirth = try container.decodeIfPresent(String.self, forKey: .placeOfBirth)
    biography = try container.decodeIfPresent(String.self, forKey: .biography)
  }

  /// 匹配 `MediaPerson` 字段名。
  private enum CodingKeys: String, CodingKey {
    case source
    case id
    case name
    case originalName = "original_name"
    case character
    case knownForDepartment = "known_for_department"
    case profilePath = "profile_path"
    case avatar
    case birthday
    case placeOfBirth = "place_of_birth"
    case biography
  }
}

/// 推荐作品与人物参演作品使用的轻量摘要模型。
private struct NativeMediaSummaryItem: Decodable, Sendable, Identifiable {
  let mediaSource: String?
  let mediaID: String?
  let tmdbID: Int?
  let type: String?
  let title: String?
  let year: String?
  let posterPath: String?

  /// 优先使用规范媒体身份作为唯一键。
  var id: String {
    identity?.id ?? "\(title ?? "item")|\(year ?? "")|\(posterPath ?? "")"
  }

  /// 构造可推入详情页的规范媒体身份。
  var identity: NativeMediaIdentity? {
    let source = mediaSource ?? "themoviedb"
    let resolvedID =
      mediaID.flatMap { $0.isEmpty ? nil : $0 }
      ?? (source == "themoviedb" ? tmdbID.map(String.init) : nil)
    guard let resolvedID else { return nil }
    let resolvedType = (type == "电视剧" || type == "电影") ? (type ?? "电影") : "电影"
    return NativeMediaIdentity(source: source, mediaID: resolvedID, type: resolvedType)
  }

  /// 对应后端 `MediaInfo` 轻量字段。
  private enum CodingKeys: String, CodingKey {
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case type
    case title
    case year
    case posterPath = "poster_path"
  }
}
