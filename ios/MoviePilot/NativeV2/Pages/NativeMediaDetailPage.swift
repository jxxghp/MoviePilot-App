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

  @State private var detail: MediaDetailPayload?
  @State private var status = NativeMediaStatusSnapshot()
  @State private var subscribedRecordIDs: [Int: Int] = [:]
  @State private var credits: [MediaPersonSummary] = []
  @State private var recommendations: [MediaSummaryItem] = []
  @State private var failed = false
  @State private var attempt = 0
  @State private var isLoading = true
  @State private var synopsisExpanded = false
  @State private var mutatingSeason: Int?
  @State private var isMutatingMovie = false
  @State private var isLaunchingPlayback = false
  @State private var playableEpisodesBySeason: [Int: [Int: String]] = [:]
  @State private var existingEpisodesBySeason: [Int: Set<Int>] = [:]
  @State private var hasLoadedEpisodeExistence = false
  @State private var selectedSeasonDetail: MediaSeasonSummary?
  @State private var pendingCancelSeason: NativeSeasonCancelTarget?
  @State private var activeFilesTarget: NativeSubscribeFilesTarget?
  @State private var activeEditorTarget: NativeMediaSubscribeEditTarget?
  @State private var actionFeedback: NativeDetailActionFeedback?
  @State private var scrollOffset: CGFloat = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  /// 按当前认证会话直接加载单部影视详情、入库/订阅状态、演职员与推荐；头图采用与发现页一致的沉浸式固定背景、下拉延展、轻视差、渐进柔焦与六段无痕溶解。
  var body: some View {
    GeometryReader { viewport in
      let viewportWidth = viewport.size.width
      let hasHorizontalInset =
        viewport.safeAreaInsets.leading > 0 || viewport.safeAreaInsets.trailing > 0
      let backdropWidth =
        hasHorizontalInset
        ? viewportWidth + viewport.safeAreaInsets.leading + viewport.safeAreaInsets.trailing
        : viewportWidth
      let margin = NativeDeviceLayout.horizontalMargin(for: viewportWidth)
      let isPortraitPhone = viewportWidth < viewport.size.height && viewportWidth < 680
      let isCompactLandscape = viewportWidth > viewport.size.height && viewport.size.height < 500
      let isWide = viewportWidth >= 680
      let heroHeight = NativeDeviceLayout.detailHeroHeight(
        width: viewportWidth,
        height: viewport.size.height,
        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
      )
      let progress = transitionProgress(height: heroHeight)
      let eased = smoothstep(progress)
      ZStack(alignment: .top) {
        ambientSurface(progress: eased).ignoresSafeArea()
        if let detail {
          if hasHorizontalInset {
            Color.clear
              .frame(width: viewportWidth, height: 1)
              .overlay(alignment: .topLeading) {
                heroBackdrop(
                  detail,
                  width: backdropWidth,
                  height: heroHeight,
                  isPortraitPhone: isPortraitPhone,
                  progress: progress,
                  eased: eased
                )
                .ignoresSafeArea(edges: [.top, .horizontal])
              }
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          } else {
            heroBackdrop(
              detail,
              width: viewportWidth,
              height: heroHeight,
              isPortraitPhone: isPortraitPhone,
              progress: progress,
              eased: eased
            )
            .ignoresSafeArea(edges: .top)
          }
        } else if !failed {
          if hasHorizontalInset {
            Color.clear
              .frame(width: viewportWidth, height: 1)
              .overlay(alignment: .topLeading) {
                loadingHeroBackdrop(
                  width: backdropWidth,
                  height: heroHeight,
                  isPortraitPhone: isPortraitPhone,
                  progress: progress,
                  eased: eased
                )
                .ignoresSafeArea(edges: [.top, .horizontal])
              }
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          } else {
            loadingHeroBackdrop(
              width: viewportWidth,
              height: heroHeight,
              isPortraitPhone: isPortraitPhone,
              progress: progress,
              eased: eased
            )
            .ignoresSafeArea(edges: .top)
          }
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if let detail {
              heroHeaderOverlay(
                detail,
                height: heroHeight,
                margin: margin,
                isWide: isWide,
                isCompactLandscape: isCompactLandscape
              )
              .frame(maxWidth: 1020, alignment: .center)
              .frame(maxWidth: .infinity)
              VStack(alignment: .leading, spacing: isCompactLandscape ? 16 : 24) {
                if let actionFeedback {
                  feedbackBanner(actionFeedback)
                }
                actionBar(
                  detail, containerWidth: viewportWidth, isCompactLandscape: isCompactLandscape)
                synopsisSection(detail)
                if isTelevision(detail), !resolvedSeasons(detail).isEmpty {
                  seasonsSection(
                    detail, seasons: resolvedSeasons(detail), containerWidth: viewportWidth)
                }
                if !displayCast(detail).isEmpty {
                  castSection(displayCast(detail))
                }
                if !recommendations.isEmpty {
                  recommendationsSection
                }
                metadataPanel(detail)
              }
              .frame(maxWidth: 1020, alignment: .leading)
              .padding(.horizontal, margin)
              .padding(.top, 8)
              .padding(.bottom, 36)
              .frame(maxWidth: .infinity)
            } else if failed {
              failureState
                .frame(maxWidth: 820)
                .padding(.horizontal, margin)
                .padding(.top, 110)
                .frame(maxWidth: .infinity)
            } else {
              NativeMediaDetailSkeletonView(
                heroHeight: heroHeight,
                horizontalMargin: margin,
                isCompactLandscape: isCompactLandscape,
                isTelevision: MediaSummaryItem.normalizeMediaType(identity.type) == "电视剧",
                seasonColumns: NativeDeviceLayout.cardGridCount(
                  for: viewportWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize),
                seedTitle: identity.seedTitle,
                rendersHeroBackdrop: false
              )
              .transition(.opacity)
            }
          }
          .frame(maxWidth: .infinity)
          .modifier(NativeDetailLegacyScrollProbe())
        }
        .coordinateSpace(name: "native-media-detail-scroll")
        .scrollIndicators(.hidden)
        .refreshable { await loadAll(forceRefresh: true) }
        .modifier(NativeDetailScrollClipping())
        .modifier(NativeSoftTopScrollEdge(isActive: eased > 0.02))
        .ignoresSafeArea(edges: .top)
        .modifier(NativeDetailScrollObservation(offset: $scrollOffset))
        .accessibilityIdentifier("native-media-detail-scroll")
      }
      .nativeHeroNavigationBar(scrollProgress: eased, scrolledTitle: detail?.title ?? "")
    }
    .navigationBarTitleDisplayMode(.inline)
    .task(id: attempt) { await loadAll(forceRefresh: attempt > 0) }
    .navigationDestination(
      isPresented: Binding(
        get: { selectedSeasonDetail != nil },
        set: { if !$0 { selectedSeasonDetail = nil } }
      )
    ) {
      if let season = selectedSeasonDetail, let detail {
        NativeMediaSeasonDetailPage(
          session: session,
          identity: identity,
          seriesDetail: detail,
          initialSeason: season,
          seriesItemID: status.itemID,
          serverName: status.server,
          initialSubscribed: status.seasons[season.seasonNumber] != nil,
          initialSubscribeID: subscribedRecordIDs[season.seasonNumber],
          initialPlayableEpisodeIDs: playableEpisodesBySeason[season.seasonNumber] ?? [:],
          initialExistingEpisodes: mergedExistingEpisodes(for: season.seasonNumber),
          onSubscriptionChanged: { isSub, subID in
            if isSub {
              status.seasons[season.seasonNumber] = status.seasons[season.seasonNumber] ?? "R"
              status.subscribed = true
              if let subID, subID > 0 {
                subscribedRecordIDs[season.seasonNumber] = subID
              }
            } else {
              status.seasons.removeValue(forKey: season.seasonNumber)
              subscribedRecordIDs.removeValue(forKey: season.seasonNumber)
              status.subscribed = !status.seasons.isEmpty
            }
            syncDetailCache()
          }
        )
      }
    }
    .sheet(item: $activeFilesTarget) { target in
      NativeSubscribeFilesSheet(session: session, target: target)
        .nativeAdaptiveSheetSizing()
    }
    .sheet(item: $activeEditorTarget) { target in
      NativeSubscribeEditorSheet(
        session: session, subscribeID: target.subscribeID, title: target.title
      ) {
        NativePageDataCache.shared.remove("subscriptions|list", session: session)
        actionFeedback = NativeDetailActionFeedback(isError: false, message: "订阅规则已更新。")
      }
      .nativeAdaptiveSheetSizing()
    }
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

  private func smoothstep(_ t: CGFloat) -> CGFloat {
    let clamped = min(max(t, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
  }

  private func transitionProgress(height: CGFloat) -> CGFloat {
    min(max(-scrollOffset / max(height * 0.62, 1), 0), 1)
  }

  @ViewBuilder
  private func ambientSurface(progress: CGFloat) -> some View {
    ZStack {
      CinematicBackground()
      if colorScheme == .dark {
        Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255)
          .opacity(max(0, 1 - Double(progress) * 1.15) * 0.55)
      }
    }
  }

  /// 详情加载期间的全幅主视觉底图：若路由携带前置卡片海报则平滑延续，否则渲染通透呼吸流光背景。
  @ViewBuilder
  private func loadingHeroBackdrop(
    width: CGFloat, height: CGFloat, isPortraitPhone: Bool, progress: CGFloat, eased: CGFloat
  ) -> some View {
    let seedRef: String? =
      if isPortraitPhone {
        Self.resolveArtwork(identity.seedPoster, source: identity.source, tmdbSize: "w780")
          ?? Self.resolveArtwork(identity.seedBackdrop, source: identity.source, tmdbSize: "w1280")
      } else {
        Self.resolveArtwork(identity.seedBackdrop, source: identity.source, tmdbSize: "w1280")
          ?? Self.resolveArtwork(identity.seedPoster, source: identity.source, tmdbSize: "w780")
      }
    let pullDown = max(scrollOffset, 0)
    let backdropHeight = height * 1.06 + pullDown
    if let seedRef {
      let scrollUp = max(-scrollOffset, 0)
      let parallax = reduceMotion ? 0 : -min(scrollUp, height) * 0.08
      let visibility = max(0, 1 - Double(eased) * 0.96)
      let isLight = colorScheme == .light
      let fadeBase =
        isLight
        ? NativeTheme.topVeilColor(for: .light, appearance: appearance)
        : Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255)
      ZStack(alignment: .bottom) {
        NativeMediaArtwork(
          session: session, reference: seedRef, role: .backdrop, maximumWidth: 1280
        )
        .frame(width: width, height: backdropHeight)
        .clipped()
        LinearGradient(
          stops: isLight
            ? [
              .init(color: .clear, location: 0.48),
              .init(color: fadeBase.opacity(0.42), location: 0.68),
              .init(color: fadeBase.opacity(0.88), location: 0.86),
              .init(color: fadeBase, location: 1),
            ]
            : [
              .init(color: .clear, location: 0.48),
              .init(color: fadeBase.opacity(0.38), location: 0.68),
              .init(color: fadeBase.opacity(0.86), location: 0.88),
              .init(color: fadeBase, location: 1),
            ], startPoint: .top, endPoint: .bottom
        )
        .frame(width: width, height: backdropHeight)
      }
      .offset(y: parallax)
      .mask(alignment: .top) {
        LinearGradient(
          stops: [
            .init(color: .white, location: 0),
            .init(color: .white, location: 0.58),
            .init(color: .white.opacity(0.86), location: 0.72),
            .init(color: .white.opacity(0.38), location: 0.86),
            .init(color: .clear, location: 1),
          ], startPoint: .top, endPoint: .bottom
        )
        .frame(height: backdropHeight)
        .offset(y: min(scrollOffset, 0) * 0.85)
      }
      .opacity(progress >= 0.99 ? 0 : visibility)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    } else {
      NativeHeroBackdropSkeletonView(width: width, height: backdropHeight)
    }
  }

  /// 详情页无遮挡沉浸式海报背景：顶部零模糊零遮罩，竖屏手机优先高分辨率竖版海报、宽屏优先电影剧照，底部平滑融入页面背景。
  private func heroBackdrop(
    _ detail: MediaDetailPayload, width: CGFloat, height: CGFloat,
    isPortraitPhone: Bool, progress: CGFloat, eased: CGFloat
  ) -> some View {
    let source = detail.mediaSource ?? identity.source
    let heroReference: String? =
      if isPortraitPhone {
        Self.resolveArtwork(detail.posterPath, source: source, tmdbSize: "w780")
          ?? Self.resolveArtwork(detail.backdropPath, source: source, tmdbSize: "w1280")
      } else {
        Self.resolveArtwork(detail.backdropPath, source: source, tmdbSize: "w1280")
          ?? Self.resolveArtwork(detail.posterPath, source: source, tmdbSize: "w780")
      }
    let scrollUp = max(-scrollOffset, 0)
    let pullDown = max(scrollOffset, 0)
    let backdropHeight = height * 1.06 + pullDown
    let parallax = reduceMotion ? 0 : -min(scrollUp, height) * 0.08
    let visibility = max(0, 1 - Double(eased) * 0.96)
    let isLight = colorScheme == .light
    let fadeBase =
      isLight
      ? NativeTheme.topVeilColor(for: .light, appearance: appearance)
      : Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255)
    return ZStack(alignment: .bottom) {
      NativeMediaArtwork(
        session: session, reference: heroReference, role: .backdrop, maximumWidth: 1280
      )
      .frame(width: width, height: backdropHeight)
      .clipped()
      // 仅底部平滑融底托起 Logo 与信息区，顶部保持 100% 纯净无遮挡。
      LinearGradient(
        stops: isLight
          ? [
            .init(color: .clear, location: 0.48),
            .init(color: fadeBase.opacity(0.42), location: 0.68),
            .init(color: fadeBase.opacity(0.88), location: 0.86),
            .init(color: fadeBase, location: 1),
          ]
          : [
            .init(color: .clear, location: 0.48),
            .init(color: fadeBase.opacity(0.38), location: 0.68),
            .init(color: fadeBase.opacity(0.86), location: 0.88),
            .init(color: fadeBase, location: 1),
          ], startPoint: .top, endPoint: .bottom
      )
      .frame(width: width, height: backdropHeight)
    }
    .offset(y: parallax)
    .mask(alignment: .top) {
      LinearGradient(
        stops: [
          .init(color: .white, location: 0),
          .init(color: .white, location: 0.58),
          .init(color: .white.opacity(0.86), location: 0.72),
          .init(color: .white.opacity(0.38), location: 0.86),
          .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .frame(height: backdropHeight)
      .offset(y: min(scrollOffset, 0) * 0.85)
    }
    .opacity(progress >= 0.99 ? 0 : visibility)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// 前景透明媒体 Logo 与居中元数据浮置在海报底部融底区，随正文自然上滚。
  private func heroHeaderOverlay(
    _ detail: MediaDetailPayload, height: CGFloat, margin: CGFloat = CinematicStyle.margin,
    isWide: Bool = false, isCompactLandscape: Bool = false
  ) -> some View {
    let isLight = colorScheme == .light
    let source = detail.mediaSource ?? identity.source
    let titleText = detail.title ?? "未命名作品"
    let logoRef = Self.resolveArtwork(detail.logoPath, source: source, tmdbSize: "w500")
    return VStack(alignment: .center, spacing: isCompactLandscape ? 5 : 10) {
      Spacer(minLength: isCompactLandscape ? 44 : 0)
      if let logoRef, !logoRef.isEmpty {
        NativeDiscoverLogoBanner(
          session: session,
          reference: logoRef,
          fallbackTitle: titleText,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          logoLanguage: detail.logoLanguage,
          originalLanguage: detail.originalLanguage,
          maxWidth: isCompactLandscape ? 228 : (isWide ? 340 : 284),
          maxHeight: isCompactLandscape ? 48 : (isWide ? 104 : 88),
          isWide: isWide,
          isCompactLandscape: isCompactLandscape,
          textAlignment: .center,
          fallbackColor: isLight ? Color.primary : Color.white
        )
        .accessibilityIdentifier("native-media-detail-title")
      } else {
        NativeHeroPosterTitleView(
          title: titleText,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          isWide: isWide,
          isCompactLandscape: isCompactLandscape,
          textAlignment: .center,
          color: isLight ? Color.primary : Color.white
        )
        .accessibilityIdentifier("native-media-detail-title")
      }
      if let tagline = detail.tagline?.trimmingCharacters(in: .whitespacesAndNewlines),
        !tagline.isEmpty, !isCompactLandscape
      {
        Text(tagline)
          .font(.subheadline.italic())
          .foregroundStyle(isLight ? Color.secondary : Color.white.opacity(0.76))
          .multilineTextAlignment(.center)
          .lineLimit(2)
      }
      let summaryParts = metadataLineParts(detail)
      if !summaryParts.isEmpty {
        Text(summaryParts.joined(separator: "  ·  "))
          .font(isCompactLandscape ? .footnote.weight(.medium) : .subheadline.weight(.medium))
          .foregroundStyle(isLight ? Color.primary.opacity(0.82) : Color.white.opacity(0.86))
          .multilineTextAlignment(.center)
          .lineLimit(isCompactLandscape ? 1 : 2)
      }
      HStack(spacing: 10) {
        if let rating = detail.voteAverage, rating > 0 {
          Label(String(format: "%.1f", rating), systemImage: "star.fill")
            .font(isCompactLandscape ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(NativeTheme.warning)
        }
        if let server = status.server, !server.isEmpty, status.itemID != nil {
          Label("已在 \(server) 入库", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(NativeTheme.success)
            .padding(.horizontal, 10)
            .padding(.vertical, isCompactLandscape ? 3.5 : 5)
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
      let genres = detail.genreNames.prefix(isWide ? 4 : 3)
      if !genres.isEmpty {
        HStack(spacing: 8) {
          ForEach(Array(genres), id: \.self) { genre in
            Text(genre)
              .font(.caption.weight(.medium))
              .lineLimit(1)
              .foregroundStyle(NativeTheme.chipText)
              .padding(.horizontal, 10)
              .padding(.vertical, isCompactLandscape ? 3.5 : 5)
              .background {
                Capsule()
                  .fill(NativeTheme.chipFill)
                  .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
              }
          }
        }
      }
    }
    .padding(.horizontal, margin)
    .padding(.bottom, isCompactLandscape ? 8 : 16)
    .frame(maxWidth: .infinity, minHeight: height, alignment: .bottom)
  }

  /// 主操作区遵循 Liquid Glass 分组规范：宽屏与紧凑横屏单行均衡排布，竖屏窄屏已入库时播放主按钮独占第一行、订阅与搜索资源并排居第二行。
  @ViewBuilder
  private func actionBar(
    _ detail: MediaDetailPayload, containerWidth: CGFloat = 0, isCompactLandscape: Bool = false
  ) -> some View {
    let tv = isTelevision(detail)
    let subscribedCount = status.seasons.count
    let hasPlay = (status.itemID?.isEmpty == false)
    let useSingleRow =
      (containerWidth >= 680 || isCompactLandscape) && !dynamicTypeSize.isAccessibilitySize
    if canSubscribe || canSearchResources || hasPlay {
      let layout =
        useSingleRow
        ? AnyLayout(HStackLayout(spacing: 10))
        : AnyLayout(VStackLayout(spacing: 10))
      layout {
        if let itemID = status.itemID, !itemID.isEmpty {
          let serverSuffix =
            (status.server?.isEmpty == false) ? " · \(status.server!)" : ""
          Button {
            Task {
              isLaunchingPlayback = true
              let err = await launchPrimaryPlayback(detail: detail, itemID: itemID)
              isLaunchingPlayback = false
              if let err {
                actionFeedback = NativeDetailActionFeedback(isError: true, message: err)
              }
            }
          } label: {
            detailCapsuleLabel(
              title: isLaunchingPlayback ? "准备播放…" : "立即播放\(serverSuffix)",
              symbol: "play.fill",
              prominent: true,
              accentFilled: false
            )
          }
          .buttonStyle(.plain)
          .disabled(isLaunchingPlayback)
          .accessibilityIdentifier("native-media-detail-play")
        }

        if canSubscribe || canSearchResources {
          HStack(spacing: 10) {
            if canSubscribe {
              if tv {
                let seasons = resolvedSeasons(detail)
                let positiveSeasons = seasons.filter { $0.seasonNumber > 0 }
                let primarySeason = positiveSeasons.first?.seasonNumber ?? 1
                let anySubscribed = subscribedCount > 0 || status.subscribed
                let allSeasonsSubscribed =
                  positiveSeasons.count > 1
                  && positiveSeasons.allSatisfy { status.seasons[$0.seasonNumber] != nil }
                let firstSubscribedSeason = status.seasons.keys.sorted().first
                let tvButtonTitle: String =
                  if mutatingSeason != nil {
                    "提交中…"
                  } else if allSeasonsSubscribed {
                    "已订阅全部季"
                  } else if subscribedCount > 0 {
                    "已订阅 \(subscribedCount) 季"
                  } else if status.subscribed {
                    "已订阅"
                  } else {
                    "订阅第 \(primarySeason) 季"
                  }
                Button {
                  if !anySubscribed {
                    Task { await performSubscribe(season: primarySeason) }
                  } else {
                    pendingCancelSeason = NativeSeasonCancelTarget(
                      season: firstSubscribedSeason,
                      message: firstSubscribedSeason.map {
                        "确认取消《\(detail.title ?? "该剧集")》第 \($0) 季的订阅吗？"
                      } ?? "确认取消《\(detail.title ?? "该剧集")》的订阅吗？"
                    )
                  }
                } label: {
                  detailCapsuleLabel(
                    title: tvButtonTitle,
                    symbol: anySubscribed ? "checkmark.circle.fill" : "bookmark",
                    prominent: !hasPlay && !anySubscribed,
                    accentFilled: anySubscribed
                  )
                }
                .buttonStyle(.plain)
                .disabled(mutatingSeason != nil)
                .contextMenu {
                  if anySubscribed {
                    let targetSeason = firstSubscribedSeason ?? primarySeason
                    Button {
                      openSubscribeFiles(detail, season: targetSeason)
                    } label: {
                      Label("订阅文件详情", systemImage: "doc.text.magnifyingglass")
                    }
                    if let subID = subscribedRecordIDs[targetSeason] ?? subscribedRecordIDs[-1],
                      subID > 0
                    {
                      Button {
                        activeEditorTarget = NativeMediaSubscribeEditTarget(
                          subscribeID: subID,
                          title: "\(detail.title ?? "剧集") S\(String(format: "%02d", targetSeason))"
                        )
                      } label: {
                        Label("编辑订阅规则", systemImage: "slider.horizontal.3")
                      }
                    }
                    Button(role: .destructive) {
                      pendingCancelSeason = NativeSeasonCancelTarget(
                        season: firstSubscribedSeason,
                        message: firstSubscribedSeason.map {
                          "确认取消《\(detail.title ?? "该剧集")》第 \($0) 季的订阅吗？"
                        } ?? "确认取消《\(detail.title ?? "该剧集")》的订阅吗？"
                      )
                    } label: {
                      Label("取消订阅", systemImage: "trash")
                    }
                  }
                }
                .accessibilityIdentifier("native-media-detail-subscribe")

                if anySubscribed {
                  subscribeFilesQuickButton {
                    openSubscribeFiles(detail, season: firstSubscribedSeason ?? primarySeason)
                  }
                }
              } else {
                Button {
                  if status.subscribed {
                    pendingCancelSeason = NativeSeasonCancelTarget(
                      season: nil,
                      message: "确认取消《\(detail.title ?? "该作品")》的订阅吗？")
                  } else {
                    Task { await performSubscribe(season: nil) }
                  }
                } label: {
                  detailCapsuleLabel(
                    title: isMutatingMovie
                      ? "提交中…" : (status.subscribed ? "已订阅" : "添加订阅"),
                    symbol: status.subscribed ? "checkmark.circle.fill" : "bookmark",
                    prominent: !hasPlay && !status.subscribed,
                    accentFilled: status.subscribed
                  )
                }
                .buttonStyle(.plain)
                .disabled(isMutatingMovie)
                .contextMenu {
                  if status.subscribed {
                    Button {
                      openSubscribeFiles(detail, season: nil)
                    } label: {
                      Label("订阅文件详情", systemImage: "doc.text.magnifyingglass")
                    }
                    if let subID = subscribedRecordIDs[-1], subID > 0 {
                      Button {
                        activeEditorTarget = NativeMediaSubscribeEditTarget(
                          subscribeID: subID, title: detail.title ?? "订阅"
                        )
                      } label: {
                        Label("编辑订阅规则", systemImage: "slider.horizontal.3")
                      }
                    }
                    Button(role: .destructive) {
                      pendingCancelSeason = NativeSeasonCancelTarget(
                        season: nil,
                        message: "确认取消《\(detail.title ?? "该作品")》的订阅吗？")
                    } label: {
                      Label("取消订阅", systemImage: "trash")
                    }
                  }
                }
                .accessibilityIdentifier("native-media-detail-subscribe")

                if status.subscribed {
                  subscribeFilesQuickButton {
                    openSubscribeFiles(detail, season: nil)
                  }
                }
              }
            }

            if canSearchResources {
              NavigationLink {
                resourceSearchDestination(detail)
              } label: {
                detailCapsuleLabel(
                  title: "搜索资源",
                  symbol: "magnifyingglass",
                  prominent: !hasPlay && !canSubscribe,
                  accentFilled: false
                )
              }
              .buttonStyle(.plain)
              .accessibilityLabel("搜索站点资源")
              .accessibilityIdentifier("native-media-detail-search-resources")
            }
          }
        }
      }
    }
  }

  /// 有明确媒体源编号时走 `/api/v1/search/media/{media_id}` 精确搜索，无有效媒体 ID 时回落 `/api/v1/search/title` 按片名搜索。
  @ViewBuilder
  private func resourceSearchDestination(_ detail: MediaDetailPayload) -> some View {
    let resolvedTitle =
      detail.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? detail.title! : "作品资源"
    let resolvedSource =
      (detail.mediaSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? detail.mediaSource! : identity.source)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedID =
      (detail.mediaID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? detail.mediaID! : identity.mediaID)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !resolvedSource.isEmpty, !resolvedID.isEmpty, resolvedID != "0" {
      NativeResourceSearchPage(
        session: session,
        target: .media(
          identity: NativeMediaIdentity(
            source: resolvedSource,
            mediaID: resolvedID,
            type: MediaSummaryItem.normalizeMediaType(detail.type) ?? identity.type
          ),
          title: resolvedTitle,
          season: nil
        )
      )
    } else {
      NativeResourceSearchPage(
        session: session,
        target: .lastResults,
        initialKeyword: detail.title ?? "",
        browseHome: false
      )
    }
  }

  /// 已订阅状态下紧邻订阅主按钮的圆形文件详情快捷入口。
  private func subscribeFilesQuickButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(NativeTheme.success)
        .frame(width: 48, height: 48)
        .background {
          Circle()
            .fill(
              Color(red: 0.24, green: 0.66, blue: 0.46).opacity(colorScheme == .light ? 0.16 : 0.24)
            )
            .overlay {
              Circle()
                .strokeBorder(
                  Color(red: 0.44, green: 0.90, blue: 0.66).opacity(0.36), lineWidth: 0.7)
            }
        }
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("订阅文件详情")
    .accessibilityIdentifier("native-media-detail-subscribe-files")
  }

  /// 打开当前作品或分季的订阅文件详情弹窗（优先使用已记录的订阅 ID，缺省时按媒体源身份实时反查）。
  private func openSubscribeFiles(_ detail: MediaDetailPayload, season: Int?) {
    let key = isTelevision(detail) ? (season ?? -1) : -1
    let knownID = subscribedRecordIDs[key] ?? (season != nil ? nil : subscribedRecordIDs[-1])
    let mediaType =
      MediaSummaryItem.normalizeMediaType(detail.type)
      ?? MediaSummaryItem.normalizeMediaType(identity.type)
      ?? "电影"
    let baseTitle = detail.title ?? "订阅文件"
    let displayTitle =
      if let season, mediaType == "电视剧" {
        "\(baseTitle) S\(String(format: "%02d", season))"
      } else {
        baseTitle
      }
    activeFilesTarget = NativeSubscribeFilesTarget(
      subscribeID: knownID,
      mediaLookup: NativeSubscribeMediaLookup(
        mediaSource: detail.mediaSource ?? identity.source,
        mediaID: detail.mediaID ?? identity.mediaID,
        type: mediaType,
        season: mediaType == "电视剧" ? season : nil,
        title: detail.title,
        year: detail.year
      ),
      fallbackTitle: displayTitle
    )
  }

  /// 详情操作栏统一 48pt 等高胶囊按钮样式（主强调 / 已订阅状态 / 次级玻璃三种清晰视觉层级）。
  private func detailCapsuleLabel(
    title: String,
    symbol: String,
    prominent: Bool,
    accentFilled: Bool
  ) -> some View {
    let accent = NativeAppearanceStore.shared.accentColor
    let fg: Color =
      if prominent {
        colorScheme == .light ? .white : Color(red: 0.08, green: 0.08, blue: 0.12)
      } else if accentFilled {
        Color(red: 0.44, green: 0.90, blue: 0.66)
      } else {
        .primary
      }
    let fill: Color =
      if prominent {
        colorScheme == .light ? accent : .white
      } else if accentFilled {
        Color(red: 0.24, green: 0.66, blue: 0.46).opacity(colorScheme == .light ? 0.18 : 0.26)
      } else {
        .primary.opacity(colorScheme == .light ? 0.08 : 0.13)
      }
    let stroke: Color =
      if prominent {
        .clear
      } else if accentFilled {
        Color(red: 0.44, green: 0.90, blue: 0.66).opacity(0.36)
      } else {
        .primary.opacity(0.20)
      }
    return HStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.subheadline.weight(.semibold))
      Text(title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.84)
    }
    .foregroundStyle(fg)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity)
    .frame(height: 48)
    .background {
      Capsule()
        .fill(fill)
        .overlay { Capsule().strokeBorder(stroke, lineWidth: 0.7) }
    }
    .contentShape(Capsule())
  }

  /// 操作反馈只显示安全摘要文本，支持点击关闭，不泄漏后端内部错误细节。
  private func feedbackBanner(_ feedback: NativeDetailActionFeedback) -> some View {
    CinematicPanel(padding: 12) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : NativeTheme.success)
        Text(feedback.message)
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          actionFeedback = nil
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.65))
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
  private func synopsisSection(_ detail: MediaDetailPayload) -> some View {
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
            .foregroundStyle(.primary.opacity(0.84))
            .lineLimit(synopsisExpanded ? nil : 5)
          if overview.count > 120 {
            Button(synopsisExpanded ? "收起简介" : "展开全部") {
              withAnimation(.easeInOut(duration: 0.2)) { synopsisExpanded.toggle() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.75))
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  /// 剧集分季卡片展示真实海报、集数与各季独立订阅状态；宽屏自动采用双列排布。
  private func seasonsSection(
    _ detail: MediaDetailPayload, seasons: [MediaSeasonSummary], containerWidth: CGFloat = 0
  ) -> some View {
    let columnCount = NativeDeviceLayout.cardGridCount(
      for: containerWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    let columns = Array(
      repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columnCount)
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("剧集分季")
          .font(.title3.weight(.bold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Text("共 \(seasons.count) 季")
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.62))
      }
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(seasons) { season in
          seasonRow(detail, season: season)
        }
      }
    }
  }

  /// 单季透色玻璃卡片：2:3 季海报 + 季名/年份/集数 + 入库状态角标 + 独立订阅按钮；点击卡片进入该季媒体与分集详情页。
  private func seasonRow(_ detail: MediaDetailPayload, season: MediaSeasonSummary)
    -> some View
  {
    let isSubscribed = status.seasons[season.seasonNumber] != nil
    let isMutating = mutatingSeason == season.seasonNumber
    let source = detail.mediaSource ?? identity.source
    let poster = [season.posterPath, detail.posterPath]
      .compactMap { Self.resolveArtwork($0, source: source) }
      .first
    let existingEps = mergedExistingEpisodes(for: season.seasonNumber)
    let totalCount = season.episodeCount ?? 0
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
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(season.displayTitle)
              .font(.subheadline.weight(.semibold))
              .lineLimit(2)
            Spacer(minLength: 4)
            seasonLibraryBadge(existingCount: existingEps.count, totalCount: totalCount)
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          let meta = seasonMetadata(season)
          if !meta.isEmpty {
            Text(meta)
              .font(.caption)
              .foregroundStyle(.primary.opacity(0.66))
          }
          if let overview = season.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
            !overview.isEmpty
          {
            Text(overview)
              .font(.caption)
              .foregroundStyle(.primary.opacity(0.74))
              .lineLimit(2)
          }
          if canSubscribe {
            HStack(spacing: 8) {
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
                    Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus")
                      .font(.caption2.weight(.semibold))
                  }
                  Text(isSubscribed ? "已订阅" : "订阅本季")
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(isSubscribed ? .white : .primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                  Capsule()
                    .fill(
                      isSubscribed
                        ? NativeAppearanceStore.shared.accentColor
                        : .primary.opacity(0.10)
                    )
                    .overlay {
                      Capsule().strokeBorder(
                        isSubscribed
                          ? Color.white.opacity(0.24)
                          : Color.primary.opacity(0.18),
                        lineWidth: 0.6
                      )
                    }
                }
                .frame(minHeight: 36)
              }
              .buttonStyle(.plain)
              .disabled(mutatingSeason != nil)
              .accessibilityIdentifier(
                "native-media-detail-season-subscribe-\(season.seasonNumber)")

              if isSubscribed {
                Button {
                  openSubscribeFiles(detail, season: season.seasonNumber)
                } label: {
                  HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                      .font(.caption2.weight(.semibold))
                    Text("文件")
                      .font(.caption.weight(.semibold))
                  }
                  .foregroundStyle(.primary.opacity(0.88))
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background {
                    Capsule()
                      .fill(NativeTheme.chipFill)
                      .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
                  }
                  .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(season.displayTitle)订阅文件详情")
                .accessibilityIdentifier(
                  "native-media-detail-season-files-\(season.seasonNumber)")
              }
            }
            .padding(.top, 2)
          }
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .onTapGesture {
        selectedSeasonDetail = season
      }
    }
    .accessibilityIdentifier("native-media-detail-season-card-\(season.seasonNumber)")
  }

  /// 分季卡片上的入库状态角标（已入库 / 已入库 X/Y / 未入库）。
  @ViewBuilder
  private func seasonLibraryBadge(existingCount: Int, totalCount: Int) -> some View {
    if existingCount > 0 {
      if totalCount > 0 && existingCount < totalCount {
        NativeAdaptiveBadge(
          "已入库 \(existingCount)/\(totalCount)",
          tint: NativeTheme.warning
        )
      } else {
        NativeAdaptiveBadge("已入库", tint: NativeTheme.success)
      }
    } else if hasLoadedEpisodeExistence {
      NativeAdaptiveBadge("未入库", tint: NativeTheme.badgeMutedText)
    }
  }

  private func mergedExistingEpisodes(for seasonNumber: Int) -> Set<Int> {
    var result = existingEpisodesBySeason[seasonNumber] ?? []
    if let playable = playableEpisodesBySeason[seasonNumber] {
      result.formUnion(playable.keys)
    }
    return result
  }

  /// 演职员采用 Cinematic 圆形头像横栏，支持 TMDB / 豆瓣 / Bangumi / AniList 推入原生人物详情页。
  private func castSection(_ people: [MediaPersonSummary]) -> some View {
    let detailSource = detail?.mediaSource ?? identity.source
    return VStack(alignment: .leading, spacing: 14) {
      Text("演职员")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          ForEach(people.prefix(18)) { person in
            let personSource = person.source ?? detailSource
            if let personID = person.resolvedPersonID,
              MediaSourceEndpoint.supportsPersonDetail(source: personSource)
            {
              NavigationLink {
                NativePersonDetailPage(
                  session: session,
                  source: personSource,
                  personID: personID,
                  fallbackName: person.displayName,
                  fallbackAvatar: Self.resolveArtwork(
                    person.artworkPath(forSource: personSource), source: personSource))
              } label: {
                personCard(person, fallbackSource: personSource)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-media-detail-cast-\(personID)")
            } else {
              personCard(person, fallbackSource: personSource)
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .accessibilityIdentifier("native-media-detail-cast")
  }

  /// 单个圆形演员头像与角色名卡片。
  private func personCard(_ person: MediaPersonSummary, fallbackSource: String) -> some View {
    let source = person.source ?? fallbackSource
    let avatar = Self.resolveArtwork(person.artworkPath(forSource: source), source: source)
    return VStack(spacing: 7) {
      Group {
        if let avatar {
          NativeMediaArtwork(session: session, reference: avatar, role: .poster, maximumWidth: 200)
        } else {
          ZStack {
            Circle().fill(.white.opacity(0.10))
            Image(systemName: "person.fill").font(.title3).foregroundStyle(.primary.opacity(0.55))
          }
        }
      }
      .frame(width: 72, height: 72)
      .clipShape(Circle())
      .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.6) }
      Text(person.displayName)
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
      if let role = person.subtitle, !role.isEmpty {
        Text(role)
          .font(.caption2)
          .foregroundStyle(.primary.opacity(0.58))
          .lineLimit(1)
      }
    }
    .frame(width: 80)
    .multilineTextAlignment(.center)
  }

  /// 推荐/相似作品横向海报栏，点击后在同一原生 NavigationStack 推入下一部详情。
  private var recommendationsSection: some View {
    let fallbackSource = detail?.mediaSource ?? identity.source
    return VStack(alignment: .leading, spacing: 14) {
      Text("你可能也喜欢")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 12) {
          ForEach(recommendations.prefix(16)) { item in
            if let resolved = item.resolvedIdentity(fallbackSource: fallbackSource) {
              let nextIdentity = NativeMediaIdentity(
                source: resolved.source,
                mediaID: resolved.mediaID,
                type: resolved.type,
                seedTitle: item.title,
                seedPoster: item.posterPath
              )
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: nextIdentity)
              } label: {
                recommendationCard(item, fallbackSource: fallbackSource)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-media-detail-recommend-\(nextIdentity.id)")
            } else {
              recommendationCard(item, fallbackSource: fallbackSource)
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .accessibilityIdentifier("native-media-detail-recommendations")
  }

  /// 与发现页一致的 2:3 居中海报推荐卡片。
  private func recommendationCard(_ item: MediaSummaryItem, fallbackSource: String) -> some View {
    let resolved = item.resolvedIdentity(fallbackSource: fallbackSource)
    let poster = Self.resolveArtwork(
      item.posterPath, source: resolved?.source ?? item.mediaSource ?? fallbackSource)
    return VStack(spacing: 6) {
      NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 420)
        .frame(width: 108, height: 162)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
        .nativeMediaExistsOverlay(
          session: session,
          source: resolved?.source,
          mediaID: resolved?.mediaID,
          title: item.title,
          year: item.year,
          type: resolved?.type ?? item.type
        )
      Text(item.title ?? "未命名作品")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
      if let year = item.year, !year.isEmpty {
        Text(year)
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.56))
          .lineLimit(1)
      }
    }
    .frame(width: 108)
    .multilineTextAlignment(.center)
  }

  /// 补充作品资料卡（导演、状态、地区与来源标识），采用低遮罩透色玻璃容器。
  @ViewBuilder
  private func metadataPanel(_ detail: MediaDetailPayload) -> some View {
    let rows = metadataRows(detail)
    if !rows.isEmpty {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 12) {
          Text("作品资料")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            if index > 0 {
              Divider().overlay(NativeTheme.divider)
            }
            HStack(alignment: .top, spacing: 12) {
              Text(row.label)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.60))
                .frame(minWidth: 68, alignment: .leading)
              Text(row.value)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.92))
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

  private var detailCacheKey: String {
    let normalizedType = MediaSummaryItem.normalizeMediaType(identity.type) ?? "电影"
    return "mediaDetail|\(identity.source)|\(identity.mediaID)|\(normalizedType)"
  }

  /// 将最新详情、订阅状态与记录编号写回页面缓存，确保返回再进入时按钮状态一致。
  private func syncDetailCache() {
    guard let detail else { return }
    NativePageDataCache.shared.set(
      (
        detail: detail,
        status: status,
        subscribedRecordIDs: subscribedRecordIDs,
        credits: credits,
        recommendations: recommendations
      ),
      for: detailCacheKey,
      session: session
    )
  }

  /// 并行读取核心详情与状态/演职员/推荐；命中作品缓存时首帧直出且静默复用，下拉刷新强制重拉。
  private func loadAll(forceRefresh: Bool = false) async {
    let normalizedType = MediaSummaryItem.normalizeMediaType(identity.type) ?? "电影"
    let cacheKey = detailCacheKey
    if !forceRefresh,
      let cached:
        (
          detail: MediaDetailPayload,
          status: NativeMediaStatusSnapshot,
          subscribedRecordIDs: [Int: Int],
          credits: [MediaPersonSummary],
          recommendations: [MediaSummaryItem]
        ) = NativePageDataCache.shared.get(cacheKey, session: session)
    {
      detail = cached.detail
      status = cached.status
      subscribedRecordIDs = cached.subscribedRecordIDs
      credits = cached.credits
      recommendations = cached.recommendations
      failed = false
      isLoading = false
      return
    }
    failed = false
    if detail == nil { isLoading = true }
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["media", identity.mediaID],
        query: [
          URLQueryItem(name: "media_source", value: identity.source),
          URLQueryItem(name: "type_name", value: normalizedType),
        ],
        timeout: 30)
      let loaded = try await session.request(
        endpoint, as: MediaDetailPayload.self, requiring: .init(category: .discovery)
      ).value
      try Task.checkCancellation()
      guard loaded.title?.isEmpty == false else {
        if detail == nil { failed = true }
        return
      }
      detail = loaded

      let mediaType = MediaSummaryItem.normalizeMediaType(loaded.type) ?? normalizedType

      async let statusTask = loadMediaStatus(loaded, fallbackType: mediaType)
      async let creditsTask = loadCredits(for: loaded, type: mediaType)
      async let recommendTask = loadRecommendations(for: loaded, type: mediaType)
      let (loadedStatus, loadedCredits, loadedRecommendations) = await (
        statusTask, creditsTask, recommendTask
      )
      guard !Task.isCancelled else { return }
      if let loadedStatus { status = loadedStatus }
      if !loadedCredits.isEmpty { credits = loadedCredits }
      recommendations = loadedRecommendations
      syncDetailCache()

      if mediaType == "电视剧" {
        await loadSeriesEpisodeAvailability(
          loaded,
          seriesItemID: loadedStatus?.itemID ?? status.itemID,
          server: loadedStatus?.server ?? status.server
        )
      }
    } catch is CancellationError {
      return
    } catch {
      if detail == nil { failed = true }
    }
  }

  /// 单次请求查询本地媒体库入库状态与当前账号各季订阅状态；当非 TMDB 媒体源映射为 TMDB 订阅导致 `media/status` 未命中时，自动回退 `GET /api/v1/subscribe/media/{id}` 投影探针。
  private func loadMediaStatus(_ loaded: MediaDetailPayload, fallbackType: String? = nil) async
    -> NativeMediaStatusSnapshot?
  {
    let resolvedSource = loaded.mediaSource ?? identity.source
    let resolvedID = loaded.mediaID ?? identity.mediaID
    let resolvedType =
      MediaSummaryItem.normalizeMediaType(loaded.type)
      ?? fallbackType
      ?? MediaSummaryItem.normalizeMediaType(identity.type)
      ?? "电影"
    let payload = [
      NativeMediaStatusQuery(
        mediaSource: resolvedSource,
        mediaID: resolvedID,
        mtype: resolvedType,
        title: loaded.title,
        year: loaded.year)
    ]
    var snapshot: NativeMediaStatusSnapshot?
    if let body = try? JSONEncoder().encode(payload),
      let endpoint = try? APIEndpoint(path: ["media", "status"], method: .post, body: body)
    {
      snapshot = try? await session.request(
        endpoint, as: [NativeMediaStatusSnapshot].self, requiring: .init(category: .discovery)
      ).value.first
    }

    let isTV = resolvedType == "电视剧"
    let needsFallbackProbe =
      canSubscribe
      && ((snapshot?.subscribed != true) || (isTV && (snapshot?.seasons.isEmpty ?? true)))
    if needsFallbackProbe,
      let fallback = await probeSubscribeByMediaIdentity(
        mediaSource: resolvedSource,
        mediaID: resolvedID,
        mtype: resolvedType,
        title: loaded.title,
        year: loaded.year
      ),
      let foundID = fallback.id, foundID > 0
    {
      var merged = snapshot ?? NativeMediaStatusSnapshot()
      merged.subscribed = true
      if isTV, let seasonNum = fallback.season {
        merged.seasons[seasonNum] = merged.seasons[seasonNum] ?? (fallback.state ?? "R")
        subscribedRecordIDs[seasonNum] = foundID
      } else {
        subscribedRecordIDs[-1] = foundID
      }
      snapshot = merged
    }
    return snapshot
  }

  /// 调用 `GET /api/v1/subscribe/media/{mediaID}` 进行跨源身份投影与片名年份兜底反查。
  private func probeSubscribeByMediaIdentity(
    mediaSource: String,
    mediaID: String,
    mtype: String,
    title: String?,
    year: String?
  ) async -> NativeSubscribeIdentityProbe? {
    guard !mediaSource.isEmpty, !mediaID.isEmpty, mediaID != "0" else { return nil }
    var query: [URLQueryItem] = [
      URLQueryItem(name: "media_source", value: mediaSource),
      URLQueryItem(name: "mtype", value: mtype),
    ]
    if let title, !title.isEmpty {
      query.append(URLQueryItem(name: "title", value: title))
    }
    if let year, !year.isEmpty {
      query.append(URLQueryItem(name: "year", value: year))
    }
    guard let endpoint = try? APIEndpoint(path: ["subscribe", "media", mediaID], query: query)
    else { return nil }
    return try? await session.request(
      endpoint, as: NativeSubscribeIdentityProbe.self, requiring: .init(category: .subscribe)
    ).value
  }

  /// 读取当前数据源演职员列表（TMDB / 豆瓣 / Bangumi / AniList），缺省时页面自动回落到详情内嵌的 actors。
  private func loadCredits(for loaded: MediaDetailPayload, type: String) async
    -> [MediaPersonSummary]
  {
    guard
      let endpoint = MediaSourceEndpoint.creditsEndpoint(
        for: loaded,
        fallbackSource: identity.source,
        fallbackMediaID: identity.mediaID,
        type: type)
    else { return [] }
    return
      (try? await session.request(
        endpoint, as: [MediaPersonSummary].self, requiring: .init(category: .discovery)
      ).value) ?? []
  }

  /// 读取当前数据源推荐作品（TMDB / 豆瓣 / Bangumi / AniList）；TMDB 推荐为空时自动回落到相似作品。
  private func loadRecommendations(for loaded: MediaDetailPayload, type: String) async
    -> [MediaSummaryItem]
  {
    let endpoints = MediaSourceEndpoint.recommendationEndpoints(
      for: loaded,
      fallbackSource: identity.source,
      fallbackMediaID: identity.mediaID,
      type: type)
    for endpoint in endpoints {
      if let items = try? await session.request(
        endpoint, as: [MediaSummaryItem].self, requiring: .init(category: .discovery)
      ).value, !items.isEmpty {
        return items
      }
    }
    return []
  }

  /// 显式单次提交订阅新增请求；采用权威乐观合并，防止豆瓣/Bangumi 等非 TMDB 来源转换身份后被滞后查询冲掉已订阅按钮状态。
  private func performSubscribe(season: Int?) async {
    guard let detail, canSubscribe else { return }
    let tv = isTelevision(detail)
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
          season: tv ? season : nil))
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      let created = try await session.request(
        endpoint, as: NativeSubscribeCreatedPayload?.self, requiring: .init(category: .subscribe)
      ).value
      try Task.checkCancellation()
      if let createdID = created?.id, createdID > 0 {
        subscribedRecordIDs[tv ? (season ?? -1) : -1] = createdID
      }

      var next = status
      next.subscribed = true
      if let season, tv {
        next.seasons[season] = next.seasons[season] ?? "R"
      }
      status = next
      syncDetailCache()
      NativePageDataCache.shared.remove("subscriptions|list", session: session)

      if let refreshed = await loadMediaStatus(detail) {
        if let itemID = refreshed.itemID, !itemID.isEmpty {
          next.itemID = itemID
        }
        if let server = refreshed.server, !server.isEmpty {
          next.server = server
        }
        for (s, stateVal) in refreshed.seasons {
          next.seasons[s] = stateVal
        }
        next.subscribed = true
        if let season, tv {
          next.seasons[season] = next.seasons[season] ?? "R"
        }
        status = next
        syncDetailCache()
      }
      actionFeedback = NativeDetailActionFeedback(
        isError: false,
        message: (tv ? season : nil).map { "已添加第 \($0) 季订阅。" } ?? "已添加订阅。")
    } catch is CancellationError {
      return
    } catch {
      actionFeedback = NativeDetailActionFeedback(
        isError: true, message: "订阅请求失败，请稍后重试。")
    }
  }

  /// 确认后单次提交取消订阅，对称权威合并状态并同步失效订阅列表缓存。
  private func performUnsubscribe(season: Int?) async {
    guard let detail, canSubscribe else { return }
    let tv = isTelevision(detail)
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
      if let season, tv {
        query.append(URLQueryItem(name: "season", value: String(season)))
      }
      let endpoint = try APIEndpoint(
        path: ["subscribe", "media", detail.mediaID ?? identity.mediaID],
        method: .delete, query: query)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()

      var next = status
      if let season, tv {
        next.seasons.removeValue(forKey: season)
        subscribedRecordIDs.removeValue(forKey: season)
        next.subscribed = !next.seasons.isEmpty
      } else {
        next.seasons.removeAll()
        subscribedRecordIDs.removeAll()
        next.subscribed = false
      }
      status = next
      syncDetailCache()
      NativePageDataCache.shared.remove("subscriptions|list", session: session)

      if let refreshed = await loadMediaStatus(detail) {
        if let itemID = refreshed.itemID, !itemID.isEmpty {
          next.itemID = itemID
        }
        if let server = refreshed.server, !server.isEmpty {
          next.server = server
        }
        if let season, tv {
          var mergedSeasons = refreshed.seasons
          mergedSeasons.removeValue(forKey: season)
          next.seasons = mergedSeasons
          next.subscribed = !mergedSeasons.isEmpty
        } else {
          next.seasons.removeAll()
          next.subscribed = false
        }
        status = next
        syncDetailCache()
      }
      actionFeedback = NativeDetailActionFeedback(
        isError: false,
        message: (tv ? season : nil).map { "已取消第 \($0) 季订阅。" } ?? "已取消订阅。")
    } catch is CancellationError {
      return
    } catch {
      actionFeedback = NativeDetailActionFeedback(
        isError: true, message: "取消订阅失败，请稍后重试。")
    }
  }

  /// 区分电视剧与电影布局分支。
  private func isTelevision(_ detail: MediaDetailPayload) -> Bool {
    (MediaSummaryItem.normalizeMediaType(detail.type)
      ?? MediaSummaryItem.normalizeMediaType(identity.type)) == "电视剧"
  }

  /// 优先展示正片季（季号 >= 1），特别篇（0 季）排在末尾；豆瓣剧集缺省 `season_info` 时从 `seasons` 自动拼装。
  private func resolvedSeasons(_ detail: MediaDetailPayload) -> [MediaSeasonSummary] {
    detail.resolvedSeasons
  }

  /// 优先展示演职员接口返回的完整演员阵容，无结果时回落到详情内嵌演员。
  private func displayCast(_ detail: MediaDetailPayload) -> [MediaPersonSummary] {
    credits.isEmpty ? (detail.actors ?? []) : credits
  }

  /// 拼装头图下方的年份、类型、时长/季数与分级摘要。
  private func metadataLineParts(_ detail: MediaDetailPayload) -> [String] {
    var parts: [String] = []
    if let year = detail.year, !year.isEmpty { parts.append(year) }
    parts.append(
      MediaSummaryItem.normalizeMediaType(detail.type)
        ?? MediaSummaryItem.normalizeMediaType(identity.type)
        ?? identity.type)
    if let runtime = detail.runtime, runtime > 0 {
      parts.append("\(runtime) 分钟")
    } else if let seasonsCount = detail.numberOfSeasons, seasonsCount > 0 {
      parts.append("\(seasonsCount) 季")
    } else if isTelevision(detail), !detail.resolvedSeasons.isEmpty {
      parts.append("\(detail.resolvedSeasons.count) 季")
    }
    if let rating = detail.contentRating, !rating.isEmpty {
      parts.append(rating)
    }
    return parts
  }

  /// 拼装单季副标（首播年份与集数）。
  private func seasonMetadata(_ season: MediaSeasonSummary) -> String {
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
  private func metadataRows(_ detail: MediaDetailPayload) -> [(label: String, value: String)] {
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
    if let doubanID = detail.doubanID, !doubanID.isEmpty {
      rows.append(("豆瓣 ID", doubanID))
    }
    if let imdb = detail.imdbID, !imdb.isEmpty {
      rows.append(("IMDb", imdb))
    }
    return rows
  }

  /// 将后端 TMDB 相对图片路径安全补全为 HTTPS 源地址，仍经同源后端图片代理获取。
  nonisolated static func resolveArtwork(
    _ raw: String?, source: String?, tmdbSize: String = "w500"
  ) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
      return trimmed
    }
    guard trimmed.hasPrefix("/"), !trimmed.contains(".."), !trimmed.contains(" "),
      (source ?? "themoviedb").lowercased() == "themoviedb"
    else { return nil }
    return "https://image.tmdb.org/t/p/\(tmdbSize)" + trimmed
  }

  /// 主操作栏播放入口：电影直接播放，电视剧自动定位首个已入库单集并附带同季连续播放队列。
  private func launchPrimaryPlayback(detail: MediaDetailPayload, itemID: String) async -> String? {
    let source = detail.mediaSource ?? identity.source
    let posterRaw = [detail.posterPath, detail.backdropPath]
      .compactMap { Self.resolveArtwork($0, source: source) }
      .first
    let artworkURL = NativeMediaPlaybackLauncher.proxiedArtworkURL(
      session: session, raw: posterRaw)

    if isTelevision(detail) {
      if playableEpisodesBySeason.isEmpty {
        await loadSeriesEpisodeAvailability(
          detail, seriesItemID: itemID, server: status.server)
      }
      let sortedSeasons = playableEpisodesBySeason.keys.sorted { lhs, rhs in
        if lhs == 0 { return false }
        if rhs == 0 { return true }
        return lhs < rhs
      }
      if let firstSeason = sortedSeasons.first(where: {
        !(playableEpisodesBySeason[$0]?.isEmpty ?? true)
      }),
        let seasonMap = playableEpisodesBySeason[firstSeason]
      {
        let sortedEps = seasonMap.keys.sorted()
        if let firstEp = sortedEps.first, let epItemID = seasonMap[firstEp] {
          let seriesTitle = detail.title ?? "播放"
          let queue = sortedEps.compactMap { epNum -> MediaPlaybackQueueItem? in
            guard let qid = seasonMap[epNum] else { return nil }
            let code = String(format: "S%02dE%02d", firstSeason, epNum)
            return MediaPlaybackQueueItem(
              itemId: qid,
              title: "\(seriesTitle) · \(code)",
              server: status.server,
              artworkURL: artworkURL?.absoluteString,
              subtitle: status.server
            )
          }
          let epCode = String(format: "S%02dE%02d", firstSeason, firstEp)
          return await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
            session: session,
            itemID: epItemID,
            server: status.server,
            title: "\(seriesTitle) · \(epCode)",
            artworkURL: artworkURL,
            queue: queue,
            queueIndex: 0
          )
        }
      }
    }

    return await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
      session: session,
      itemID: itemID,
      server: status.server,
      title: detail.title ?? "播放",
      artworkURL: artworkURL
    )
  }

  /// 拉取电视剧各季已入库单集映射（优先 `GET /api/v1/mediaserver/episodes`，补充 `POST /api/v1/mediaserver/exists_remote`）。
  private func loadSeriesEpisodeAvailability(
    _ loaded: MediaDetailPayload,
    seriesItemID: String?,
    server: String?
  ) async {
    var playableMap: [Int: [Int: String]] = [:]
    if let seriesItemID, !seriesItemID.isEmpty {
      var query = [URLQueryItem(name: "itemid", value: seriesItemID)]
      if let server, !server.isEmpty {
        query.append(URLQueryItem(name: "server", value: server))
      }
      if let epEndpoint = try? APIEndpoint(path: ["mediaserver", "episodes"], query: query),
        let decoded = try? await session.request(
          epEndpoint,
          as: NativePlayableSeriesEpisodesMap.self,
          requiring: .init(category: .discovery)
        ).value
      {
        playableMap = decoded.seasons
      }
    }

    var remoteExists: [Int: Set<Int>] = [:]
    let resolvedSource = loaded.mediaSource ?? identity.source
    let resolvedID = loaded.mediaID ?? identity.mediaID
    var remoteBody: [String: Any] = [
      "type": "电视剧",
      "title": loaded.title ?? "",
    ]
    if let year = loaded.year, !year.isEmpty { remoteBody["year"] = year }
    if !resolvedSource.isEmpty, !resolvedID.isEmpty {
      remoteBody["media_source"] = resolvedSource
      remoteBody["media_id"] = resolvedID
    }
    if let tmdbID = loaded.tmdbID, tmdbID > 0 {
      remoteBody["tmdbid"] = tmdbID
    }
    if let data = try? JSONSerialization.data(withJSONObject: remoteBody),
      let remoteEp = try? APIEndpoint(
        path: ["mediaserver", "exists_remote"], method: .post, body: data),
      let existsResp = try? await session.request(
        remoteEp,
        as: NativeRemoteExistingEpisodesMap.self,
        requiring: .init(category: .discovery)
      ).value
    {
      remoteExists = existsResp.seasons
    }

    guard !Task.isCancelled else { return }
    playableEpisodesBySeason = playableMap
    existingEpisodesBySeason = remoteExists
    hasLoadedEpisodeExistence = true
  }
}

// MARK: - 原生「季媒体与分集详情」页面

/// 点击媒体详情页的任意一季后进入的「季媒体详情页」：展示该季海报、简介、入库与订阅操作，以及带入库状态和单集直放的分集列表。
@MainActor
struct NativeMediaSeasonDetailPage: View {
  let session: NativeSession
  let identity: NativeMediaIdentity
  let seriesDetail: MediaDetailPayload
  let initialSeason: MediaSeasonSummary
  let seriesItemID: String?
  let serverName: String?
  let onSubscriptionChanged: ((_ subscribed: Bool, _ subscribeID: Int?) -> Void)?

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @State private var containerWidth: CGFloat = 0
  @State private var seasonInfo: MediaSeasonSummary
  @State private var seasonVoteAverage: Double?
  @State private var episodes: [NativeSeasonEpisodeDTO] = []
  @State private var playableEpisodeIDs: [Int: String]
  @State private var existingEpisodes: Set<Int>
  @State private var resolvedSeriesItemID: String?
  @State private var resolvedServerName: String?
  @State private var isSubscribed: Bool
  @State private var subscribeRecordID: Int?
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var reloadToken = 0
  @State private var isMutatingSubscribe = false
  @State private var playingEpisodeNumber: Int?
  @State private var synopsisExpanded = false
  @State private var showUnsubscribeConfirm = false
  @State private var activeFilesTarget: NativeSubscribeFilesTarget?
  @State private var activeEditorTarget: NativeMediaSubscribeEditTarget?
  @State private var feedback: NativeDetailActionFeedback?

  init(
    session: NativeSession,
    identity: NativeMediaIdentity,
    seriesDetail: MediaDetailPayload,
    initialSeason: MediaSeasonSummary,
    seriesItemID: String?,
    serverName: String?,
    initialSubscribed: Bool,
    initialSubscribeID: Int?,
    initialPlayableEpisodeIDs: [Int: String] = [:],
    initialExistingEpisodes: Set<Int> = [],
    onSubscriptionChanged: ((_ subscribed: Bool, _ subscribeID: Int?) -> Void)? = nil
  ) {
    self.session = session
    self.identity = identity
    self.seriesDetail = seriesDetail
    self.initialSeason = initialSeason
    self.seriesItemID = seriesItemID
    self.serverName = serverName
    self.onSubscriptionChanged = onSubscriptionChanged
    _seasonInfo = State(initialValue: initialSeason)
    _playableEpisodeIDs = State(initialValue: initialPlayableEpisodeIDs)
    _existingEpisodes = State(
      initialValue: initialExistingEpisodes.union(initialPlayableEpisodeIDs.keys))
    _resolvedSeriesItemID = State(initialValue: seriesItemID)
    _resolvedServerName = State(initialValue: serverName)
    _isSubscribed = State(initialValue: initialSubscribed)
    _subscribeRecordID = State(initialValue: initialSubscribeID)
  }

  private var canSubscribe: Bool {
    session.user.allows(.init(category: .subscribe))
  }

  private var canSearchResources: Bool {
    session.user.allows(.init(category: .search))
  }

  private var seasonNumber: Int {
    seasonInfo.seasonNumber
  }

  private var effectiveSource: String {
    seriesDetail.mediaSource ?? identity.source
  }

  private var totalExpectedEpisodes: Int {
    max(seasonInfo.episodeCount ?? 0, episodes.count)
  }

  private var inLibraryCount: Int {
    existingEpisodes.union(playableEpisodeIDs.keys).count
  }

  var body: some View {
    let resolvedWidth = NativeDeviceLayout.resolvedContainerWidth(containerWidth)
    let margin = NativeDeviceLayout.horizontalMargin(for: resolvedWidth)
    let columnCount = NativeDeviceLayout.cardGridCount(
      for: resolvedWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)

    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let feedback {
            feedbackBanner(feedback)
          }
          seasonHeaderCard(resolvedWidth: resolvedWidth)
          seasonActionBar(resolvedWidth: resolvedWidth)
          seasonOverviewSection
          episodesSection(columnCount: columnCount)
        }
        .frame(maxWidth: resolvedWidth >= 740 ? 1080 : 860, alignment: .leading)
        .padding(.horizontal, margin)
        .padding(.top, 10)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await loadSeasonAll() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-season-detail-scroll")
    }
    .nativeTrackContainerWidth($containerWidth)
    .navigationTitle("\(seriesDetail.title ?? "剧集") · \(seasonInfo.displayTitle)")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .task(id: reloadToken) {
      await loadSeasonAll()
    }
    .sheet(item: $activeFilesTarget) { target in
      NativeSubscribeFilesSheet(session: session, target: target)
        .nativeAdaptiveSheetSizing()
    }
    .sheet(item: $activeEditorTarget) { target in
      NativeSubscribeEditorSheet(
        session: session, subscribeID: target.subscribeID, title: target.title
      ) {
        NativePageDataCache.shared.remove("subscriptions|list", session: session)
        feedback = NativeDetailActionFeedback(isError: false, message: "本季订阅规则已更新。")
      }
      .nativeAdaptiveSheetSizing()
    }
    .alert("取消订阅", isPresented: $showUnsubscribeConfirm) {
      Button("取消订阅", role: .destructive) {
        Task { await unsubscribeSeason() }
      }
      Button("保留", role: .cancel) {}
    } message: {
      Text("确认取消《\(seriesDetail.title ?? "该剧集")》\(seasonInfo.displayTitle)的订阅吗？")
    }
  }

  // MARK: - 本季媒体信息头卡

  private func seasonHeaderCard(resolvedWidth: CGFloat) -> some View {
    let posterRef = [seasonInfo.posterPath, seriesDetail.posterPath]
      .compactMap { NativeMediaDetailPage.resolveArtwork($0, source: effectiveSource) }
      .first
    let vote = seasonVoteAverage ?? seriesDetail.voteAverage
    let genres = seriesDetail.genreNames.prefix(3)

    return CinematicPanel(padding: 16) {
      HStack(alignment: .top, spacing: 16) {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        NativeMediaArtwork(
          session: session, reference: posterRef, role: .poster, maximumWidth: 420
        )
        .frame(width: resolvedWidth >= 680 ? 112 : 96, height: resolvedWidth >= 680 ? 168 : 144)
        .clipShape(shape)
        .overlay {
          shape.strokeBorder(.primary.opacity(0.14), lineWidth: 0.6)
        }

        VStack(alignment: .leading, spacing: 8) {
          if let seriesTitle = seriesDetail.title, !seriesTitle.isEmpty {
            Text(seriesTitle)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Text(seasonInfo.displayTitle)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .accessibilityIdentifier("native-season-detail-title")

          HStack(spacing: 8) {
            if let airDate = seasonInfo.airDate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !airDate.isEmpty
            {
              Text(airDate)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if totalExpectedEpisodes > 0 {
              Text("共 \(totalExpectedEpisodes) 集")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            if let vote, vote > 0 {
              HStack(spacing: 3) {
                Image(systemName: "star.fill")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(NativeTheme.warning)
                Text(String(format: "%.1f", vote))
                  .font(.caption.weight(.bold).monospacedDigit())
                  .foregroundStyle(NativeTheme.warning)
              }
            }
          }

          seasonLibrarySummaryRow

          if !genres.isEmpty {
            HStack(spacing: 6) {
              ForEach(Array(genres), id: \.self) { genre in
                Text(genre)
                  .font(.caption2.weight(.medium))
                  .foregroundStyle(NativeTheme.chipText)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3.5)
                  .background {
                    Capsule()
                      .fill(NativeTheme.chipFill)
                      .overlay {
                        Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6)
                      }
                  }
              }
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private var seasonLibrarySummaryRow: some View {
    let count = inLibraryCount
    let total = totalExpectedEpisodes
    let srvSuffix =
      (resolvedServerName?.isEmpty == false) ? " · \(resolvedServerName!)" : ""
    if count > 0 {
      if total > 0 && count < total {
        NativeAdaptiveBadge(
          "部分入库 \(count)/\(total) 集\(srvSuffix)",
          tint: NativeTheme.warning
        )
      } else if total > 0 {
        NativeAdaptiveBadge(
          "已入库 \(count)/\(total) 集\(srvSuffix)",
          tint: NativeTheme.success
        )
      } else {
        NativeAdaptiveBadge(
          "已入库 \(count) 集\(srvSuffix)",
          tint: NativeTheme.success
        )
      }
    } else if !isLoading {
      NativeAdaptiveBadge("未入库", tint: NativeTheme.badgeMutedText)
    }
  }

  // MARK: - 本季操作栏

  @ViewBuilder
  private func seasonActionBar(resolvedWidth: CGFloat) -> some View {
    let hasPlayable = !playableEpisodeIDs.isEmpty
    let isWide = resolvedWidth >= 680 && !dynamicTypeSize.isAccessibilitySize
    let layout =
      isWide ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 10))

    if hasPlayable || canSubscribe || canSearchResources {
      layout {
        if hasPlayable {
          let firstEp = playableEpisodeIDs.keys.sorted().first ?? 1
          let isStartingFirst = playingEpisodeNumber == firstEp
          let srvSuffix =
            (resolvedServerName?.isEmpty == false) ? " · \(resolvedServerName!)" : ""
          Button {
            if let targetEp = episodes.first(where: { playableEpisodeIDs[$0.episodeNumber] != nil })
            {
              Task { await playEpisode(targetEp) }
            } else if let firstNum = playableEpisodeIDs.keys.sorted().first {
              let fallbackEp = NativeSeasonEpisodeDTO(
                episodeNumber: firstNum,
                name: "第 \(firstNum) 集",
                overview: nil,
                airDate: nil,
                runtime: nil,
                stillPath: nil,
                voteAverage: nil
              )
              Task { await playEpisode(fallbackEp) }
            }
          } label: {
            seasonCapsuleLabel(
              title: isStartingFirst
                ? "准备播放…" : "播放第 \(firstEp) 集\(srvSuffix)",
              symbol: "play.fill",
              prominent: true,
              accentFilled: false
            )
          }
          .buttonStyle(.plain)
          .disabled(playingEpisodeNumber != nil)
          .accessibilityIdentifier("native-season-detail-play")
        }

        if canSubscribe || canSearchResources {
          HStack(spacing: 10) {
            if canSubscribe {
              Button {
                if isSubscribed {
                  showUnsubscribeConfirm = true
                } else {
                  Task { await subscribeSeason() }
                }
              } label: {
                seasonCapsuleLabel(
                  title: isMutatingSubscribe
                    ? "提交中…" : (isSubscribed ? "本季已订阅" : "订阅本季"),
                  symbol: isSubscribed ? "checkmark.circle.fill" : "bookmark",
                  prominent: !hasPlayable && !isSubscribed,
                  accentFilled: isSubscribed
                )
              }
              .buttonStyle(.plain)
              .disabled(isMutatingSubscribe)
              .contextMenu {
                if isSubscribed {
                  Button {
                    openSeasonSubscribeFiles()
                  } label: {
                    Label("订阅文件详情", systemImage: "doc.text.magnifyingglass")
                  }
                  if let subID = subscribeRecordID, subID > 0 {
                    Button {
                      activeEditorTarget = NativeMediaSubscribeEditTarget(
                        subscribeID: subID,
                        title:
                          "\(seriesDetail.title ?? "剧集") S\(String(format: "%02d", seasonNumber))"
                      )
                    } label: {
                      Label("编辑订阅规则", systemImage: "slider.horizontal.3")
                    }
                  }
                  Button(role: .destructive) {
                    showUnsubscribeConfirm = true
                  } label: {
                    Label("取消订阅", systemImage: "trash")
                  }
                }
              }
              .accessibilityIdentifier("native-season-detail-subscribe")

              if isSubscribed {
                Button {
                  openSeasonSubscribeFiles()
                } label: {
                  Image(systemName: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NativeTheme.success)
                    .frame(width: 48, height: 48)
                    .background {
                      Circle()
                        .fill(
                          Color(red: 0.24, green: 0.66, blue: 0.46)
                            .opacity(colorScheme == .light ? 0.16 : 0.24)
                        )
                        .overlay {
                          Circle()
                            .strokeBorder(
                              Color(red: 0.44, green: 0.90, blue: 0.66).opacity(0.36),
                              lineWidth: 0.7
                            )
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("订阅文件详情")
                .accessibilityIdentifier("native-season-detail-files")
              }
            }

            if canSearchResources {
              NavigationLink {
                seasonResourceSearchDestination(episode: nil)
              } label: {
                seasonCapsuleLabel(
                  title: "搜索本季资源",
                  symbol: "magnifyingglass",
                  prominent: !hasPlayable && !canSubscribe,
                  accentFilled: false
                )
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-season-detail-search")
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var seasonOverviewSection: some View {
    let rawOverview =
      (seasonInfo.overview?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
        $0.isEmpty ? nil : $0
      }
      ?? (seriesDetail.overview?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
        $0.isEmpty ? nil : $0
      }

    if let overview = rawOverview {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 10) {
          Text("本季简介")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          Text(overview)
            .font(.body)
            .lineSpacing(5)
            .foregroundStyle(.primary.opacity(0.84))
            .lineLimit(synopsisExpanded ? nil : 4)
          if overview.count > 110 {
            Button(synopsisExpanded ? "收起简介" : "展开全部") {
              withAnimation(.easeInOut(duration: 0.2)) { synopsisExpanded.toggle() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.75))
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  // MARK: - 本季分集列表

  @ViewBuilder
  private func episodesSection(columnCount: Int) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("本季剧集")
          .font(.title3.weight(.bold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        if !episodes.isEmpty {
          Text(
            inLibraryCount > 0
              ? "已入库 \(inLibraryCount) / 共 \(episodes.count) 集"
              : "共 \(episodes.count) 集"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      if isLoading && episodes.isEmpty {
        NativeSubscriptionsHubSkeletonView(columns: columnCount)
          .transition(.opacity)
      } else if loadFailed && episodes.isEmpty {
        CinematicPanel {
          VStack(alignment: .leading, spacing: 10) {
            Label("暂时无法载入本季分集信息", systemImage: "exclamationmark.triangle")
              .font(.headline)
            Button("重试") { reloadToken += 1 }
              .frame(minHeight: 44)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else if episodes.isEmpty {
        CinematicPanel(padding: 24) {
          VStack(spacing: 8) {
            Image(systemName: "film.stack")
              .font(.title2)
              .foregroundStyle(.secondary)
            Text("暂无本季分集明细")
              .font(.headline)
            Text("数据源尚未提供该季的分集列表。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 120)
        }
      } else {
        let gridColumns = Array(
          repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
        LazyVGrid(columns: gridColumns, spacing: 12) {
          ForEach(episodes) { ep in
            episodeCard(ep)
          }
        }
      }
    }
  }

  private func episodeCard(_ ep: NativeSeasonEpisodeDTO) -> some View {
    let epItemID = playableEpisodeIDs[ep.episodeNumber]
    let inLibrary = epItemID != nil || existingEpisodes.contains(ep.episodeNumber)
    let isPlayable = epItemID != nil
    let isPlayingThis = playingEpisodeNumber == ep.episodeNumber
    let stillRef = [
      ep.stillPath, seriesDetail.backdropPath, seasonInfo.posterPath, seriesDetail.posterPath,
    ]
    .compactMap {
      NativeMediaDetailPage.resolveArtwork($0, source: effectiveSource, tmdbSize: "w780")
    }
    .first

    return CinematicPanel(padding: 12) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
          episodeThumbnail(
            reference: stillRef,
            episodeNumber: ep.episodeNumber,
            runtime: ep.runtime,
            inLibrary: inLibrary,
            isPlayable: isPlayable,
            isLoadingPlay: isPlayingThis
          )
          .onTapGesture {
            guard isPlayable, playingEpisodeNumber == nil else { return }
            Task { await playEpisode(ep) }
          }

          VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text("\(ep.episodeNumber). \(ep.displayTitle)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
              Spacer(minLength: 4)
              episodeStatusBadge(inLibrary: inLibrary, airDate: ep.airDate)
            }

            HStack(spacing: 8) {
              if let airDate = ep.airDate?.trimmingCharacters(in: .whitespacesAndNewlines),
                !airDate.isEmpty
              {
                Text(airDate)
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              if let vote = ep.voteAverage, vote > 0 {
                HStack(spacing: 2.5) {
                  Image(systemName: "star.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(NativeTheme.warning)
                  Text(String(format: "%.1f", vote))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(NativeTheme.warning)
                }
              }
            }

            if let overview = ep.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
              !overview.isEmpty
            {
              Text(overview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            }
          }
        }

        if isPlayable || canSearchResources {
          HStack(spacing: 8) {
            if isPlayable {
              Button {
                Task { await playEpisode(ep) }
              } label: {
                HStack(spacing: 5) {
                  if isPlayingThis {
                    ProgressView().controlSize(.mini).tint(.white)
                  } else {
                    Image(systemName: "play.fill")
                      .font(.caption2.weight(.bold))
                  }
                  Text(isPlayingThis ? "准备播放…" : "播放本集")
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .frame(minHeight: 34)
                .background {
                  Capsule().fill(appearance.accentColor)
                }
                .contentShape(Capsule())
              }
              .buttonStyle(.plain)
              .frame(minHeight: 40)
              .disabled(playingEpisodeNumber != nil)
              .accessibilityIdentifier(
                "native-season-episode-play-\(seasonNumber)-\(ep.episodeNumber)")
            }

            if canSearchResources && !inLibrary {
              NavigationLink {
                seasonResourceSearchDestination(episode: ep.episodeNumber)
              } label: {
                HStack(spacing: 4) {
                  Image(systemName: "magnifyingglass")
                    .font(.caption2.weight(.semibold))
                  Text("搜本集")
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary.opacity(0.88))
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background {
                  Capsule()
                    .fill(NativeTheme.chipFill)
                    .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.65) }
                }
                .contentShape(Capsule())
              }
              .buttonStyle(.plain)
              .frame(minHeight: 40)
              .accessibilityIdentifier(
                "native-season-episode-search-\(seasonNumber)-\(ep.episodeNumber)")
            }

            Spacer(minLength: 0)
          }
        }
      }
    }
    .accessibilityIdentifier("native-season-episode-card-\(seasonNumber)-\(ep.episodeNumber)")
  }

  private func episodeThumbnail(
    reference: String?,
    episodeNumber: Int,
    runtime: Int?,
    inLibrary: Bool,
    isPlayable: Bool,
    isLoadingPlay: Bool
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
    return NativeMediaArtwork(
      session: session, reference: reference, role: .backdrop, maximumWidth: 480
    )
    .frame(width: 136, height: 78)
    .clipShape(shape)
    .overlay {
      shape.strokeBorder(.primary.opacity(0.14), lineWidth: 0.6)
    }
    .overlay(alignment: .topLeading) {
      Text(String(format: "E%02d", episodeNumber))
        .font(.system(size: 10, weight: .bold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background { Capsule().fill(.black.opacity(0.68)) }
        .padding(6)
    }
    .overlay(alignment: .bottomTrailing) {
      if let runtime, runtime > 0 {
        Text("\(runtime) 分钟")
          .font(.system(size: 9.5, weight: .medium).monospacedDigit())
          .foregroundStyle(.white)
          .padding(.horizontal, 5.5)
          .padding(.vertical, 2)
          .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.black.opacity(0.66))
          }
          .padding(6)
      }
    }
    .overlay {
      if isPlayable {
        ZStack {
          Circle().fill(.black.opacity(0.46)).frame(width: 32, height: 32)
          if isLoadingPlay {
            ProgressView().controlSize(.mini).tint(.white)
          } else {
            Image(systemName: "play.fill")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(.white)
              .offset(x: 1)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func episodeStatusBadge(inLibrary: Bool, airDate: String?) -> some View {
    if inLibrary {
      NativeAdaptiveBadge("已入库", tint: NativeTheme.success)
    } else if Self.isFutureAirDate(airDate) {
      NativeAdaptiveBadge("未开播", tint: NativeTheme.info)
    } else {
      NativeAdaptiveBadge("未入库", tint: NativeTheme.badgeMutedText)
    }
  }

  private static func isFutureAirDate(_ raw: String?) -> Bool {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.count >= 10
    else { return false }
    let prefix = String(trimmed.prefix(10))
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let air = formatter.date(from: prefix) else { return false }
    return air > Date()
  }

  private func seasonCapsuleLabel(
    title: String,
    symbol: String,
    prominent: Bool,
    accentFilled: Bool
  ) -> some View {
    let accent = appearance.accentColor
    let fg: Color =
      if prominent {
        colorScheme == .light ? .white : Color(red: 0.08, green: 0.08, blue: 0.12)
      } else if accentFilled {
        Color(red: 0.44, green: 0.90, blue: 0.66)
      } else {
        .primary
      }
    let fill: Color =
      if prominent {
        colorScheme == .light ? accent : .white
      } else if accentFilled {
        Color(red: 0.24, green: 0.66, blue: 0.46).opacity(colorScheme == .light ? 0.18 : 0.26)
      } else {
        .primary.opacity(colorScheme == .light ? 0.08 : 0.13)
      }
    let stroke: Color =
      if prominent {
        .clear
      } else if accentFilled {
        Color(red: 0.44, green: 0.90, blue: 0.66).opacity(0.36)
      } else {
        .primary.opacity(0.20)
      }
    return HStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.subheadline.weight(.semibold))
      Text(title)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.84)
    }
    .foregroundStyle(fg)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity)
    .frame(height: 46)
    .background {
      Capsule()
        .fill(fill)
        .overlay { Capsule().strokeBorder(stroke, lineWidth: 0.7) }
    }
    .contentShape(Capsule())
  }

  @ViewBuilder
  private func seasonResourceSearchDestination(episode: Int?) -> some View {
    let baseTitle = seriesDetail.title ?? "作品资源"
    let resolvedSource =
      (seriesDetail.mediaSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? seriesDetail.mediaSource! : identity.source)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedID =
      (seriesDetail.mediaID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? seriesDetail.mediaID! : identity.mediaID)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if let episode {
      let keyword = "\(baseTitle) \(String(format: "S%02dE%02d", seasonNumber, episode))"
      NativeResourceSearchPage(
        session: session,
        target: .lastResults,
        initialKeyword: keyword,
        browseHome: false
      )
    } else if !resolvedSource.isEmpty, !resolvedID.isEmpty, resolvedID != "0" {
      NativeResourceSearchPage(
        session: session,
        target: .media(
          identity: NativeMediaIdentity(
            source: resolvedSource,
            mediaID: resolvedID,
            type: "电视剧"
          ),
          title: "\(baseTitle) \(seasonInfo.displayTitle)",
          season: seasonNumber
        )
      )
    } else {
      NativeResourceSearchPage(
        session: session,
        target: .lastResults,
        initialKeyword: "\(baseTitle) S\(String(format: "%02d", seasonNumber))",
        browseHome: false
      )
    }
  }

  private func openSeasonSubscribeFiles() {
    let baseTitle = seriesDetail.title ?? "订阅文件"
    activeFilesTarget = NativeSubscribeFilesTarget(
      subscribeID: subscribeRecordID,
      mediaLookup: NativeSubscribeMediaLookup(
        mediaSource: seriesDetail.mediaSource ?? identity.source,
        mediaID: seriesDetail.mediaID ?? identity.mediaID,
        type: "电视剧",
        season: seasonNumber,
        title: seriesDetail.title,
        year: seriesDetail.year
      ),
      fallbackTitle: "\(baseTitle) S\(String(format: "%02d", seasonNumber))"
    )
  }

  private func feedbackBanner(_ feedback: NativeDetailActionFeedback) -> some View {
    CinematicPanel(padding: 12) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError
            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : NativeTheme.success)
        Text(feedback.message)
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.65))
            .frame(minWidth: 36, minHeight: 36)
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - 季集数据加载与播放/订阅交互

  private func resolveTMDBID() -> Int? {
    if let tid = seriesDetail.tmdbID, tid > 0 { return tid }
    if effectiveSource.lowercased() == "themoviedb",
      let parsed = Int(seriesDetail.mediaID ?? identity.mediaID), parsed > 0
    {
      return parsed
    }
    return nil
  }

  private func loadSeasonAll() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }

    // 1. 若缺少本地媒体库条目 ID，先尝试通过 `GET /api/v1/mediaserver/exists` 定位
    if resolvedSeriesItemID == nil || resolvedSeriesItemID?.isEmpty == true {
      var query: [URLQueryItem] = [
        URLQueryItem(name: "mtype", value: "电视剧"),
        URLQueryItem(name: "season", value: String(seasonNumber)),
      ]
      if let title = seriesDetail.title, !title.isEmpty {
        query.append(URLQueryItem(name: "title", value: title))
      }
      if let year = seriesDetail.year, !year.isEmpty {
        query.append(URLQueryItem(name: "year", value: year))
      }
      let src = seriesDetail.mediaSource ?? identity.source
      let mid = seriesDetail.mediaID ?? identity.mediaID
      if !src.isEmpty, !mid.isEmpty {
        query.append(URLQueryItem(name: "media_source", value: src))
        query.append(URLQueryItem(name: "media_id", value: mid))
      }
      if let existsEp = try? APIEndpoint(path: ["mediaserver", "exists"], query: query),
        let existsResp = try? await session.request(
          existsEp,
          as: NativeMediaServerExistsPayload.self,
          requiring: .init(category: .discovery)
        ).value,
        let foundID = existsResp.item?.id, !foundID.isEmpty
      {
        resolvedSeriesItemID = foundID
        if let srv = existsResp.item?.server, !srv.isEmpty {
          resolvedServerName = srv
        }
      }
    }

    // 2. 并行拉取本季元信息补全、分集列表与媒体服务器可播放集映射
    async let seasonMetaTask = fetchSeasonMetadata()
    async let episodesTask = fetchEpisodesList()
    async let playableTask = fetchPlayableSeasonEpisodes()
    async let remoteExistsTask = fetchRemoteSeasonExistence()

    let (enrichedSeason, loadedEpisodes, loadedPlayable, loadedRemoteExists) = await (
      seasonMetaTask, episodesTask, playableTask, remoteExistsTask
    )
    guard !Task.isCancelled else { return }

    if let enrichedSeason {
      seasonInfo = MediaSeasonSummary(
        seasonNumber: seasonNumber,
        name: enrichedSeason.name ?? seasonInfo.name,
        airDate: enrichedSeason.airDate ?? seasonInfo.airDate,
        episodeCount: enrichedSeason.episodeCount ?? seasonInfo.episodeCount,
        overview: (enrichedSeason.overview?.isEmpty == false)
          ? enrichedSeason.overview : seasonInfo.overview,
        posterPath: enrichedSeason.posterPath ?? seasonInfo.posterPath
      )
      if let vote = enrichedSeason.voteAverage, vote > 0 {
        seasonVoteAverage = vote
      }
    }

    if !loadedPlayable.isEmpty {
      playableEpisodeIDs = loadedPlayable
    }
    var mergedSet = existingEpisodes
    mergedSet.formUnion(loadedRemoteExists)
    mergedSet.formUnion(playableEpisodeIDs.keys)
    existingEpisodes = mergedSet

    if !loadedEpisodes.isEmpty {
      episodes = loadedEpisodes
    } else {
      let maxKnown = max(
        seasonInfo.episodeCount ?? 0,
        mergedSet.max() ?? 0
      )
      if maxKnown > 0 {
        episodes = (1...maxKnown).map { num in
          NativeSeasonEpisodeDTO(
            episodeNumber: num,
            name: "第 \(num) 集",
            overview: nil,
            airDate: nil,
            runtime: nil,
            stillPath: nil,
            voteAverage: nil
          )
        }
      } else if seasonInfo.overview == nil && playableEpisodeIDs.isEmpty {
        loadFailed = true
      }
    }
  }

  private func fetchSeasonMetadata() async -> NativeSeasonEnrichedMetaDTO? {
    let src = seriesDetail.mediaSource ?? identity.source
    let mid = seriesDetail.mediaID ?? identity.mediaID
    guard !src.isEmpty, !mid.isEmpty else { return nil }
    let query = [
      URLQueryItem(name: "media_source", value: src),
      URLQueryItem(name: "media_id", value: mid),
      URLQueryItem(name: "season", value: String(seasonNumber)),
    ]
    guard let endpoint = try? APIEndpoint(path: ["media", "seasons"], query: query) else {
      return nil
    }
    return
      (try? await session.request(
        endpoint,
        as: [NativeSeasonEnrichedMetaDTO].self,
        requiring: .init(category: .discovery)
      ).value)?.first
  }

  private func fetchEpisodesList() async -> [NativeSeasonEpisodeDTO] {
    if let tmdbID = resolveTMDBID(),
      let ep = try? APIEndpoint(path: ["tmdb", String(tmdbID), String(seasonNumber)]),
      let list = try? await session.request(
        ep,
        as: [NativeSeasonEpisodeDTO].self,
        requiring: .init(category: .discovery)
      ).value,
      !list.isEmpty
    {
      return list.sorted { $0.episodeNumber < $1.episodeNumber }
    }

    if let itemID = resolvedSeriesItemID, !itemID.isEmpty {
      var metaQuery = [
        URLQueryItem(name: "itemid", value: itemID),
        URLQueryItem(name: "season", value: String(seasonNumber)),
      ]
      if let srv = resolvedServerName, !srv.isEmpty {
        metaQuery.append(URLQueryItem(name: "server", value: srv))
      }
      if let metaEp = try? APIEndpoint(
        path: ["mediaserver", "episode-metadata"], query: metaQuery),
        let list = try? await session.request(
          metaEp,
          as: [NativeSeasonEpisodeDTO].self,
          requiring: .init(category: .discovery)
        ).value,
        !list.isEmpty
      {
        return list.sorted { $0.episodeNumber < $1.episodeNumber }
      }
    }
    return []
  }

  private func fetchPlayableSeasonEpisodes() async -> [Int: String] {
    guard let itemID = resolvedSeriesItemID, !itemID.isEmpty else { return [:] }
    var query: [URLQueryItem] = []
    if let srv = resolvedServerName, !srv.isEmpty {
      query.append(URLQueryItem(name: "server", value: srv))
    }
    if let endpoint = try? APIEndpoint(
      path: ["mediaserver", "episodes", itemID, String(seasonNumber)],
      query: query
    ),
      let map = try? await session.request(
        endpoint,
        as: NativePlayableSeasonEpisodesMap.self,
        requiring: .init(category: .discovery)
      ).value,
      !map.episodes.isEmpty
    {
      return map.episodes
    }
    return [:]
  }

  private func fetchRemoteSeasonExistence() async -> Set<Int> {
    let src = seriesDetail.mediaSource ?? identity.source
    let mid = seriesDetail.mediaID ?? identity.mediaID
    var body: [String: Any] = [
      "type": "电视剧",
      "title": seriesDetail.title ?? "",
      "season": seasonNumber,
    ]
    if let year = seriesDetail.year, !year.isEmpty { body["year"] = year }
    if !src.isEmpty, !mid.isEmpty {
      body["media_source"] = src
      body["media_id"] = mid
    }
    if let tmdbID = resolveTMDBID() {
      body["tmdbid"] = tmdbID
    }
    guard let data = try? JSONSerialization.data(withJSONObject: body),
      let endpoint = try? APIEndpoint(
        path: ["mediaserver", "exists_remote"], method: .post, body: data),
      let resp = try? await session.request(
        endpoint,
        as: NativeRemoteExistingEpisodesMap.self,
        requiring: .init(category: .discovery)
      ).value
    else { return [] }
    return resp.seasons[seasonNumber] ?? []
  }

  /// 播放指定单集，并将本季全部已入库单集组装为连续播放队列。
  private func playEpisode(_ target: NativeSeasonEpisodeDTO) async {
    guard let epItemID = playableEpisodeIDs[target.episodeNumber], !epItemID.isEmpty else {
      feedback = NativeDetailActionFeedback(isError: true, message: "该集暂未在媒体服务器中入库。")
      return
    }
    playingEpisodeNumber = target.episodeNumber
    defer { playingEpisodeNumber = nil }

    let seriesTitle = seriesDetail.title ?? "剧集"
    let sortedPlayableNums = playableEpisodeIDs.keys.sorted()
    let epLookup = Dictionary(uniqueKeysWithValues: episodes.map { ($0.episodeNumber, $0) })

    var queue: [MediaPlaybackQueueItem] = []
    var targetQueueIndex = 0
    for (idx, epNum) in sortedPlayableNums.enumerated() {
      guard let qItemID = playableEpisodeIDs[epNum] else { continue }
      if epNum == target.episodeNumber {
        targetQueueIndex = queue.count
      }
      let meta = epLookup[epNum]
      let code = String(format: "S%02dE%02d", seasonNumber, epNum)
      let qTitle =
        if let name = meta?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
          "\(seriesTitle) · \(code) · \(name)"
        } else {
          "\(seriesTitle) · \(code)"
        }
      let artRaw = [meta?.stillPath, seasonInfo.posterPath, seriesDetail.posterPath]
        .compactMap { NativeMediaDetailPage.resolveArtwork($0, source: effectiveSource) }
        .first
      let artProxied = NativeMediaPlaybackLauncher.proxiedArtworkURL(session: session, raw: artRaw)
      queue.append(
        MediaPlaybackQueueItem(
          itemId: qItemID,
          title: qTitle,
          server: resolvedServerName,
          artworkURL: artProxied?.absoluteString,
          subtitle: resolvedServerName
        )
      )
      _ = idx
    }

    let code = String(format: "S%02dE%02d", seasonNumber, target.episodeNumber)
    let fullTitle = "\(seriesTitle) · \(code) · \(target.displayTitle)"
    let posterRaw = [target.stillPath, seasonInfo.posterPath, seriesDetail.posterPath]
      .compactMap { NativeMediaDetailPage.resolveArtwork($0, source: effectiveSource) }
      .first
    let artworkURL = NativeMediaPlaybackLauncher.proxiedArtworkURL(
      session: session, raw: posterRaw)

    let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
      session: session,
      itemID: epItemID,
      server: resolvedServerName,
      title: fullTitle,
      artworkURL: artworkURL,
      queue: queue,
      queueIndex: targetQueueIndex
    )
    if let err {
      feedback = NativeDetailActionFeedback(isError: true, message: err)
    }
  }

  private func subscribeSeason() async {
    guard canSubscribe else { return }
    isMutatingSubscribe = true
    defer { isMutatingSubscribe = false }
    do {
      let body = try JSONEncoder().encode(
        NativeSubscribeCreatePayload(
          name: seriesDetail.title ?? "",
          type: "电视剧",
          year: seriesDetail.year ?? "",
          mediaSource: seriesDetail.mediaSource ?? identity.source,
          mediaID: seriesDetail.mediaID ?? identity.mediaID,
          season: seasonNumber
        )
      )
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      let created = try await session.request(
        endpoint, as: NativeSubscribeCreatedPayload?.self, requiring: .init(category: .subscribe)
      ).value
      try Task.checkCancellation()
      isSubscribed = true
      if let cid = created?.id, cid > 0 {
        subscribeRecordID = cid
      }
      NativePageDataCache.shared.remove("subscriptions|list", session: session)
      onSubscriptionChanged?(true, subscribeRecordID)
      feedback = NativeDetailActionFeedback(
        isError: false, message: "已添加\(seasonInfo.displayTitle)订阅。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeDetailActionFeedback(isError: true, message: "订阅请求失败，请稍后重试。")
    }
  }

  private func unsubscribeSeason() async {
    guard canSubscribe else { return }
    isMutatingSubscribe = true
    defer { isMutatingSubscribe = false }
    do {
      let query = [
        URLQueryItem(name: "media_source", value: seriesDetail.mediaSource ?? identity.source),
        URLQueryItem(name: "season", value: String(seasonNumber)),
      ]
      let endpoint = try APIEndpoint(
        path: ["subscribe", "media", seriesDetail.mediaID ?? identity.mediaID],
        method: .delete,
        query: query
      )
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      isSubscribed = false
      subscribeRecordID = nil
      NativePageDataCache.shared.remove("subscriptions|list", session: session)
      onSubscriptionChanged?(false, nil)
      feedback = NativeDetailActionFeedback(
        isError: false, message: "已取消\(seasonInfo.displayTitle)订阅。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeDetailActionFeedback(isError: true, message: "取消订阅失败，请稍后重试。")
    }
  }
}

/// 单季元信息补全投影（`GET /api/v1/media/seasons`）。
private struct NativeSeasonEnrichedMetaDTO: Decodable, Sendable {
  let seasonNumber: Int?
  let name: String?
  let airDate: String?
  let episodeCount: Int?
  let overview: String?
  let posterPath: String?
  let voteAverage: Double?

  private enum CodingKeys: String, CodingKey {
    case seasonNumber = "season_number"
    case name
    case airDate = "air_date"
    case episodeCount = "episode_count"
    case overview
    case posterPath = "poster_path"
    case voteAverage = "vote_average"
  }
}

/// 单集信息模型（`GET /api/v1/tmdb/{tmdbid}/{season}` 与 `GET /api/v1/mediaserver/episode-metadata`）。
struct NativeSeasonEpisodeDTO: Decodable, Sendable, Identifiable {
  let episodeNumber: Int
  let name: String?
  let overview: String?
  let airDate: String?
  let runtime: Int?
  let stillPath: String?
  let voteAverage: Double?

  var id: Int { episodeNumber }

  var displayTitle: String {
    if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
      return trimmed
    }
    return "第 \(episodeNumber) 集"
  }

  private enum CodingKeys: String, CodingKey {
    case episodeNumber = "episode_number"
    case name
    case overview
    case airDate = "air_date"
    case runtime
    case stillPath = "still_path"
    case voteAverage = "vote_average"
  }

  init(
    episodeNumber: Int,
    name: String?,
    overview: String?,
    airDate: String?,
    runtime: Int?,
    stillPath: String?,
    voteAverage: Double?
  ) {
    self.episodeNumber = episodeNumber
    self.name = name
    self.overview = overview
    self.airDate = airDate
    self.runtime = runtime
    self.stillPath = stillPath
    self.voteAverage = voteAverage
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let num = try? c.decode(Int.self, forKey: .episodeNumber) {
      episodeNumber = num
    } else if let str = try? c.decode(String.self, forKey: .episodeNumber), let num = Int(str) {
      episodeNumber = num
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .episodeNumber, in: c, debugDescription: "Invalid episode_number")
    }
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    overview = try? c.decodeIfPresent(String.self, forKey: .overview)
    airDate = try? c.decodeIfPresent(String.self, forKey: .airDate)
    runtime = try? c.decodeIfPresent(Int.self, forKey: .runtime)
    stillPath = try? c.decodeIfPresent(String.self, forKey: .stillPath)
    voteAverage = try? c.decodeIfPresent(Double.self, forKey: .voteAverage)
  }
}

/// `GET /api/v1/mediaserver/episodes?itemid=...` 季->集->条目标识字典解码器。
private struct NativePlayableSeriesEpisodesMap: Decodable, Sendable {
  let seasons: [Int: [Int: String]]

  init(from decoder: Decoder) throws {
    let raw = try [String: [String: String]].init(from: decoder)
    var parsed: [Int: [Int: String]] = [:]
    for (sKey, epDict) in raw {
      guard let sNum = Int(sKey) else { continue }
      var inner: [Int: String] = [:]
      for (eKey, itemID) in epDict where !itemID.isEmpty {
        if let eNum = Int(eKey) {
          inner[eNum] = itemID
        }
      }
      if !inner.isEmpty {
        parsed[sNum] = inner
      }
    }
    seasons = parsed
  }
}

/// `GET /api/v1/mediaserver/episodes/{itemid}/{season}` 集->条目标识字典解码器。
private struct NativePlayableSeasonEpisodesMap: Decodable, Sendable {
  let episodes: [Int: String]

  init(from decoder: Decoder) throws {
    let raw = try [String: String].init(from: decoder)
    var parsed: [Int: String] = [:]
    for (eKey, itemID) in raw where !itemID.isEmpty {
      if let eNum = Int(eKey) {
        parsed[eNum] = itemID
      }
    }
    episodes = parsed
  }
}

/// `POST /api/v1/mediaserver/exists_remote` 季->已入库集号数组解码器。
private struct NativeRemoteExistingEpisodesMap: Decodable, Sendable {
  let seasons: [Int: Set<Int>]

  init(from decoder: Decoder) throws {
    let raw = try [String: [Int]].init(from: decoder)
    var parsed: [Int: Set<Int>] = [:]
    for (sKey, eps) in raw {
      if let sNum = Int(sKey), !eps.isEmpty {
        parsed[sNum] = Set(eps)
      }
    }
    seasons = parsed
  }
}

/// `GET /api/v1/mediaserver/exists` 本地媒体库条目查询响应。
private struct NativeMediaServerExistsPayload: Decodable, Sendable {
  struct ItemRef: Decodable, Sendable {
    let id: String?
    let server: String?
  }
  let item: ItemRef?
}

/// 原生人物详情页：展示人物头像、简介与参演作品网格，支持 TMDB / 豆瓣 / Bangumi / AniList，并可继续推入任意影视详情。
@MainActor
struct NativePersonDetailPage: View {
  let session: NativeSession
  let source: String
  let personID: Int
  let fallbackName: String
  let fallbackAvatar: String?

  @State private var person: MediaPersonSummary?
  @State private var works: [MediaSummaryItem] = []
  @State private var isLoading = true
  @State private var failed = false
  @State private var attempt = 0
  @State private var bioExpanded = false
  @State private var containerWidth: CGFloat = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var tileWidth = 104.0

  init(
    session: NativeSession,
    source: String = "themoviedb",
    personID: Int,
    fallbackName: String,
    fallbackAvatar: String?
  ) {
    self.session = session
    self.source = source
    self.personID = personID
    self.fallbackName = fallbackName
    self.fallbackAvatar = fallbackAvatar
  }

  /// 采用统一 Cinematic 连续渐变与透色卡片，不依赖任何网页视图。
  var body: some View {
    let resolvedWidth = min(NativeDeviceLayout.resolvedContainerWidth(containerWidth), 900)
    let skeletonColumns = NativeDeviceLayout.posterGridCount(
      for: resolvedWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          if isLoading && person == nil && works.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
              CinematicPanel(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                  Text("人物简介").font(.headline).accessibilityAddTraits(.isHeader)
                  NativeSkeletonBlock(height: 13, cornerRadius: 5)
                  NativeSkeletonBlock(height: 13, cornerRadius: 5)
                  NativeSkeletonBlock(width: 210, height: 13, cornerRadius: 5)
                }
              }
              .nativeSkeletonShimmer()

              VStack(alignment: .leading, spacing: 14) {
                Text("参演作品")
                  .font(.title3.weight(.bold))
                  .accessibilityAddTraits(.isHeader)
                NativePosterGridSkeletonView(
                  columns: skeletonColumns,
                  count: skeletonColumns * 2,
                  horizontalSpacing: 11,
                  verticalSpacing: 18,
                  centeredCaption: true
                )
              }
            }
            .transition(.opacity)
          } else {
            if let bio = person?.biography?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bio.isEmpty
            {
              CinematicPanel {
                VStack(alignment: .leading, spacing: 10) {
                  Text("人物简介").font(.headline).accessibilityAddTraits(.isHeader)
                  Text(bio)
                    .font(.body)
                    .lineSpacing(5)
                    .foregroundStyle(.primary.opacity(0.84))
                    .lineLimit(bioExpanded ? nil : 5)
                  if bio.count > 120 {
                    Button(bioExpanded ? "收起简介" : "展开全部") {
                      withAnimation(.easeInOut(duration: 0.2)) { bioExpanded.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
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
                    if let resolved = item.resolvedIdentity(fallbackSource: source) {
                      let nextIdentity = NativeMediaIdentity(
                        source: resolved.source,
                        mediaID: resolved.mediaID,
                        type: resolved.type,
                        seedTitle: item.title,
                        seedPoster: item.posterPath
                      )
                      NavigationLink {
                        NativeMediaDetailPage(session: session, identity: nextIdentity)
                      } label: {
                        workTile(item)
                      }
                      .buttonStyle(.plain)
                      .accessibilityIdentifier("native-person-work-\(nextIdentity.id)")
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
        }
        .frame(maxWidth: 900)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-person-detail-scroll")
    }
    .navigationTitle(person?.displayName ?? fallbackName)
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .task(id: attempt) { await load() }
  }

  /// 居中人物圆形肖像与基础履历信息。
  private var header: some View {
    let avatar =
      NativeMediaDetailPage.resolveArtwork(
        person?.artworkPath(forSource: source), source: person?.source ?? source)
      ?? fallbackAvatar
    return VStack(spacing: 12) {
      Group {
        if let avatar {
          NativeMediaArtwork(session: session, reference: avatar, role: .poster, maximumWidth: 320)
        } else {
          ZStack {
            Circle().fill(.white.opacity(0.10))
            Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(
              .primary.opacity(0.55))
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
          .foregroundStyle(.primary.opacity(0.72))
          .multilineTextAlignment(.center)
      } else if isLoading && person == nil {
        NativeSkeletonBlock(width: 168, height: 14, cornerRadius: 6)
          .nativeSkeletonShimmer()
      }
      if let aliases = person?.alsoKnownAs, !aliases.isEmpty {
        Text(aliases.prefix(4).joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.primary.opacity(0.62))
          .multilineTextAlignment(.center)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 人物参演作品的 2:3 居中海报单元格。
  private func workTile(_ item: MediaSummaryItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.posterPath, source: item.mediaSource ?? source)
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
        Text(year).font(.caption).foregroundStyle(.primary.opacity(0.56))
      }
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .multilineTextAlignment(.center)
  }

  /// 并行读取人物资料与参演作品列表（按当前来源路由至 TMDB / 豆瓣 / Bangumi / AniList）。
  private func load() async {
    isLoading = true
    failed = false
    defer { isLoading = false }
    guard
      let personEndpoint = MediaSourceEndpoint.personDetailEndpoint(
        source: source, personID: personID),
      let creditsEndpoint = MediaSourceEndpoint.personCreditsEndpoint(
        source: source, personID: personID, page: 1)
    else {
      failed = true
      return
    }
    async let personTask = try? session.request(
      personEndpoint, as: MediaPersonSummary.self, requiring: .init(category: .discovery)
    ).value
    async let worksTask = try? session.request(
      creditsEndpoint, as: [MediaSummaryItem].self, requiring: .init(category: .discovery)
    ).value
    let (loadedPerson, loadedWorks) = await (personTask, worksTask)
    guard !Task.isCancelled else { return }
    person = loadedPerson
    works = loadedWorks ?? []
    if loadedPerson == nil && works.isEmpty { failed = true }
  }
}

/// 取消订阅确认弹窗的语义载体。
private struct NativeSeasonCancelTarget: Identifiable {
  let id = UUID()
  let season: Int?
  let message: String
}

/// 从详情页直接打开订阅规则编辑器的目标载体。
private struct NativeMediaSubscribeEditTarget: Identifiable {
  let subscribeID: Int
  let title: String
  var id: Int { subscribeID }
}

/// `POST /api/v1/subscribe/` 新增成功返回的订阅主键载荷。
private struct NativeSubscribeCreatedPayload: Decodable, Sendable {
  let id: Int?
}

/// `GET /api/v1/subscribe/media/{mediaID}` 跨源投影探针返回的最小字段。
private struct NativeSubscribeIdentityProbe: Decodable, Sendable {
  let id: Int?
  let season: Int?
  let state: String?
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

private struct NativeDetailScrollOffsetKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct NativeDetailScrollClipping: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      content.scrollClipDisabled()
    } else {
      content
    }
  }
}

private struct NativeDetailScrollObservation: ViewModifier {
  @Binding var offset: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      content.onScrollGeometryChange(for: CGFloat.self) { geometry in
        let raw = -(geometry.contentOffset.y + geometry.contentInsets.top)
        let clamped = max(min(raw, 240), -720)
        return (clamped * 2).rounded() / 2
      } action: { _, value in
        if abs(offset - value) >= 0.5 { offset = value }
      }
    } else {
      content.onPreferenceChange(NativeDetailScrollOffsetKey.self) { raw in
        let clamped = max(min(raw, 240), -720)
        if abs(offset - clamped) >= 0.5 { offset = clamped }
      }
    }
  }
}

private struct NativeDetailLegacyScrollProbe: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      content
    } else {
      content.background(alignment: .top) {
        GeometryReader { proxy in
          Color.clear.preference(
            key: NativeDetailScrollOffsetKey.self,
            value: proxy.frame(in: .named("native-media-detail-scroll")).minY
          )
        }
        .frame(height: 0)
      }
    }
  }
}
