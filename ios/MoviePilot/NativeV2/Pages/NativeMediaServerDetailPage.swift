import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 媒体服务器详情页：与 `NativeMediaDetailPage` 视觉风格保持一致，完整支持电影、剧集（Series）、季（Season）、集（Episode）与音乐专辑/单曲多层下钻、播前版本/音轨/字幕选择、分集连续播放、订阅与站点资源搜索。
@MainActor
struct NativeMediaServerDetailPage: View {
  let session: NativeSession
  let server: String?
  let itemID: String
  let fallbackTitle: String?
  let fallbackItemType: String?
  let fallbackPoster: String?

  @State private var detail: MediaServerItemDetailDTO?
  @State private var parentSeriesDetail: MediaServerItemDetailDTO?
  @State private var fetchedLogo: MediaServerLogoCacheEntry?
  @State private var enrichedIDs = MediaServerEnrichedIDs()
  @State private var seasons: [MediaServerBrowseItemDTO] = []
  @State private var episodes: [MediaServerBrowseItemDTO] = []
  @State private var collectionItems: [MediaServerBrowseItemDTO] = []
  @State private var similarItems: [MediaServerSimilarCardItem] = []
  @State private var sampleEpisodeSource: MediaServerSourceDTO?
  @State private var selectedSeasonNumber: Int?
  @State private var selectedSourceID: String?
  @State private var trackSelection = MediaPlaybackTrackSelection()

  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isLaunchingPlayback = false
  @State private var isSubscribing = false
  @State private var isSubscribed = false
  @State private var subscribedSeasons: Set<Int> = []
  @State private var subscribedRecordIDs: [Int: Int] = [:]
  @State private var pendingCancelSubscribe: MediaServerCancelSubscribeTarget?
  @State private var activeFilesTarget: NativeSubscribeFilesTarget?
  @State private var synopsisExpanded = false
  @State private var feedbackMessage: (text: String, isError: Bool)?
  @State private var scrollOffset: CGFloat = 0

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  init(
    session: NativeSession,
    server: String?,
    itemID: String,
    fallbackTitle: String? = nil,
    fallbackItemType: String? = nil,
    fallbackPoster: String? = nil
  ) {
    self.session = session
    self.server = server
    self.itemID = itemID
    self.fallbackTitle = fallbackTitle
    self.fallbackItemType = fallbackItemType
    self.fallbackPoster = fallbackPoster
  }

  private struct MediaServerLogoCacheEntry: Sendable {
    let url: String
    let logoLanguage: String?
    let originalLanguage: String?
  }

  private static var mediaLogoCache: [String: MediaServerLogoCacheEntry] = [:]

  private var canSubscribe: Bool { session.user.allows(.init(category: .subscribe)) }
  private var canSearchResources: Bool { session.user.allows(.init(category: .search)) }
  private var resolvedServer: String? { detail?.server ?? server }

  private var effectiveExternalIdentity: (source: String, mediaID: String, type: String)? {
    detail?.resolvedExternalIdentity ?? parentSeriesDetail?.resolvedExternalIdentity
  }

  private var activeMediaSource: MediaServerSourceDTO? {
    guard let sources = detail?.mediaSources, !sources.isEmpty else { return nil }
    if let selectedSourceID, let matched = sources.first(where: { $0.id == selectedSourceID }) {
      return matched
    }
    return sources.first
  }

  private var displayInfoMediaSource: MediaServerSourceDTO? {
    activeMediaSource ?? sampleEpisodeSource
  }

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
      let progress = min(max(-scrollOffset / max(heroHeight * 0.62, 1), 0), 1)
      let eased = progress * progress * (3 - 2 * progress)

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
        } else if !loadFailed {
          if hasHorizontalInset {
            Color.clear
              .frame(width: viewportWidth, height: 1)
              .overlay(alignment: .topLeading) {
                loadingHeroBackdrop(
                  width: backdropWidth,
                  height: heroHeight,
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

              VStack(alignment: .leading, spacing: isCompactLandscape ? 16 : 22) {
                if let feedbackMessage {
                  feedbackBanner(feedbackMessage.text, isError: feedbackMessage.isError)
                }

                if detail.kind == .season || detail.kind == .episode {
                  hierarchyBreadcrumb(detail)
                }

                actionBar(detail, isCompactLandscape: isCompactLandscape)

                if detail.kind.isDirectlyPlayable, let source = activeMediaSource {
                  prePlayTrackSelectorCard(detail: detail, source: source)
                }

                if detail.kind == .boxSet, !collectionItems.isEmpty {
                  collectionItemsSection(detail, containerWidth: viewportWidth)
                }

                if detail.kind == .series, !seasons.isEmpty {
                  seasonsSection(detail)
                }

                if detail.kind == .series || detail.kind == .season || detail.kind == .musicAlbum,
                  !episodes.isEmpty
                {
                  episodesSection(detail, isWide: isWide)
                }

                if detail.kind == .episode, !episodes.isEmpty {
                  adjacentEpisodesStrip(detail)
                }

                synopsisSection(detail)

                if !detail.people.isEmpty {
                  castSection(detail.people)
                }

                if !similarItems.isEmpty {
                  similarWorksSection(detail)
                }

                let links = resolvedExternalLinks(detail)
                if !links.isEmpty {
                  externalLinksSection(links)
                }

                if let infoSource = displayInfoMediaSource, !infoSource.streams.isEmpty {
                  mediaStreamsInfoSection(infoSource)
                }

                metadataCard(detail)
              }
              .frame(maxWidth: 1020, alignment: .leading)
              .padding(.horizontal, margin)
              .padding(.top, 8)
              .padding(.bottom, 40)
              .frame(maxWidth: .infinity)
            } else if loadFailed {
              failureCard
                .frame(maxWidth: 820)
                .padding(.horizontal, margin)
                .padding(.top, 110)
                .frame(maxWidth: .infinity)
            } else {
              NativeMediaServerDetailSkeletonView(
                heroHeight: heroHeight,
                viewportWidth: viewportWidth,
                horizontalMargin: margin,
                isWide: isWide,
                isCompactLandscape: isCompactLandscape,
                fallbackTitle: fallbackTitle,
                fallbackItemType: fallbackItemType,
                canSubscribe: canSubscribe,
                canSearchResources: canSearchResources
              )
              .transition(.opacity)
            }
          }
          .frame(maxWidth: .infinity)
          .modifier(MediaServerDetailLegacyScrollProbe())
        }
        .coordinateSpace(name: "native-mediaserver-detail-scroll")
        .scrollIndicators(.hidden)
        .refreshable { await loadAll() }
        .modifier(MediaServerDetailScrollClipping())
        .modifier(NativeSoftTopScrollEdge(isActive: eased > 0.02))
        .ignoresSafeArea(edges: .top)
        .modifier(MediaServerDetailScrollObservation(offset: $scrollOffset))
        .accessibilityIdentifier("native-mediaserver-detail-scroll")
      }
      .nativeHeroNavigationBar(
        scrollProgress: eased,
        scrolledTitle: detail.map(heroDisplayTitle) ?? ""
      )
    }
    .navigationBarTitleDisplayMode(.inline)
    .task(id: "\(server ?? "")|\(itemID)") {
      await loadAll()
    }
    .onReceive(NotificationCenter.default.publisher(for: .moviePilotPlaybackDidStop)) { _ in
      Task { await loadAll() }
    }
    .sheet(item: $activeFilesTarget) { target in
      NativeSubscribeFilesSheet(session: session, target: target)
        .nativeAdaptiveSheetSizing()
    }
    .alert(
      "取消订阅",
      isPresented: Binding(
        get: { pendingCancelSubscribe != nil },
        set: { if !$0 { pendingCancelSubscribe = nil } }
      ),
      presenting: pendingCancelSubscribe
    ) { target in
      Button("取消订阅", role: .destructive) {
        Task { await performUnsubscribe(target) }
      }
      Button("保留", role: .cancel) {}
    } message: { target in
      Text(target.message)
    }
  }

  // MARK: - Hero

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

  /// 详情加载期间的全幅背景图：若已携带列表海报/剧照则无缝铺底，否则渲染通透呼吸流光背景。
  @ViewBuilder
  private func loadingHeroBackdrop(
    width: CGFloat, height: CGFloat, progress: CGFloat, eased: CGFloat
  ) -> some View {
    let pullDown = max(scrollOffset, 0)
    let backdropHeight = height * 1.06 + pullDown
    if let fallbackPoster, !fallbackPoster.isEmpty {
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
          session: session, reference: fallbackPoster, role: .backdrop, maximumWidth: 1280
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
            ],
          startPoint: .top,
          endPoint: .bottom
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
          ],
          startPoint: .top,
          endPoint: .bottom
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

  /// 无遮挡沉浸式海报背景：顶部零模糊零遮罩，竖屏手机优先竖版海报、宽屏/分集优先横版剧照，底部平滑融入页面背景。
  private func heroBackdrop(
    _ detail: MediaServerItemDetailDTO, width: CGFloat, height: CGFloat,
    isPortraitPhone: Bool, progress: CGFloat, eased: CGFloat
  ) -> some View {
    let ref: String? =
      if detail.kind == .episode {
        detail.thumb ?? detail.backdrop ?? detail.poster
      } else if isPortraitPhone {
        detail.poster ?? detail.backdrop ?? detail.thumb
      } else {
        detail.backdrop ?? detail.poster ?? detail.thumb
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
      NativeMediaArtwork(session: session, reference: ref, role: .backdrop, maximumWidth: 1280)
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
          ],
        startPoint: .top,
        endPoint: .bottom
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
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: backdropHeight)
      .offset(y: min(scrollOffset, 0) * 0.85)
    }
    .opacity(progress >= 0.99 ? 0 : visibility)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func heroHeaderOverlay(
    _ detail: MediaServerItemDetailDTO, height: CGFloat, margin: CGFloat = CinematicStyle.margin,
    isWide: Bool = false, isCompactLandscape: Bool = false
  ) -> some View {
    let isLight = colorScheme == .light
    let titleText = heroDisplayTitle(detail)
    let directLogo = detail.logo?.isEmpty == false ? detail.logo : nil
    let logoRef = directLogo ?? (fetchedLogo?.url.isEmpty == false ? fetchedLogo?.url : nil)
    let logoLanguage = directLogo != nil ? detail.logoLanguage : fetchedLogo?.logoLanguage
    let originalLanguage = fetchedLogo?.originalLanguage
    return VStack(alignment: .center, spacing: isCompactLandscape ? 5 : 10) {
      Spacer(minLength: isCompactLandscape ? 44 : 0)

      if let logoRef, !logoRef.isEmpty {
        NativeDiscoverLogoBanner(
          session: session,
          reference: logoRef,
          fallbackTitle: titleText,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          logoLanguage: logoLanguage,
          originalLanguage: originalLanguage,
          maxWidth: isCompactLandscape ? 228 : (isWide ? 340 : 284),
          maxHeight: isCompactLandscape ? 48 : (isWide ? 104 : 88),
          isWide: isWide,
          isCompactLandscape: isCompactLandscape,
          textAlignment: .center,
          fallbackColor: isLight ? Color.primary : Color.white
        )
        .accessibilityIdentifier("native-mediaserver-detail-title")
      } else {
        NativeHeroPosterTitleView(
          title: titleText,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          isWide: isWide,
          isCompactLandscape: isCompactLandscape,
          textAlignment: .center,
          color: isLight ? Color.primary : Color.white
        )
        .accessibilityIdentifier("native-mediaserver-detail-title")
      }

      let meta = metadataLineParts(detail)
      if !meta.isEmpty {
        Text(meta.joined(separator: " · "))
          .font(isCompactLandscape ? .footnote.weight(.medium) : .subheadline.weight(.medium))
          .foregroundStyle(isLight ? Color.primary.opacity(0.82) : Color.white.opacity(0.86))
          .multilineTextAlignment(.center)
          .lineLimit(isCompactLandscape ? 1 : 2)
      }

      HStack(spacing: 6) {
        Text(dimensionBadgeTitle(detail))
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .padding(.vertical, isCompactLandscape ? 3 : 4)
          .background(appearance.accentColor.opacity(0.88), in: Capsule())

        if let serverName = resolvedServer, !serverName.isEmpty {
          Text(serverName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.84))
            .padding(.horizontal, 8)
            .padding(.vertical, isCompactLandscape ? 3 : 4)
            .background(.primary.opacity(0.12), in: Capsule())
        }

        if detail.played == true {
          Label("已看", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NativeTheme.success)
        } else if let pct = detail.playedPercentage, pct > 1 {
          Text("已观看 \(Int(pct.rounded()))%")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(appearance.accentColor)
        }
      }

      if !detail.genres.isEmpty {
        HStack(spacing: 6) {
          ForEach(detail.genres.prefix(isWide ? 4 : 3), id: \.self) { genre in
            Text(genre)
              .font(.caption2.weight(.medium))
              .lineLimit(1)
              .foregroundStyle(.primary.opacity(0.82))
              .padding(.horizontal, 9)
              .padding(.vertical, isCompactLandscape ? 3 : 4)
              .background(.primary.opacity(0.10), in: Capsule())
          }
        }
      }
    }
    .padding(.horizontal, margin)
    .padding(.bottom, isCompactLandscape ? 8 : 16)
    .frame(maxWidth: .infinity, minHeight: height, alignment: .bottom)
  }

  // MARK: - Breadcrumb (3-Tier Navigation)

  private func hierarchyBreadcrumb(_ detail: MediaServerItemDetailDTO) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        if let seriesID = detail.seriesId, !seriesID.isEmpty {
          NavigationLink {
            NativeMediaServerDetailPage(
              session: session,
              server: resolvedServer,
              itemID: seriesID,
              fallbackTitle: detail.seriesName,
              fallbackItemType: "Series"
            )
          } label: {
            breadcrumbPill(
              title: detail.seriesName ?? "返回剧集",
              symbol: "tv"
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-mediaserver-breadcrumb-series")
        }

        if detail.kind == .episode, let seasonID = detail.seasonId, !seasonID.isEmpty {
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

          NavigationLink {
            NativeMediaServerDetailPage(
              session: session,
              server: resolvedServer,
              itemID: seasonID,
              fallbackTitle: detail.seasonName
                ?? detail.seasonNumber.map { $0 == 0 ? "特别篇" : "第 \($0) 季" },
              fallbackItemType: "Season"
            )
          } label: {
            breadcrumbPill(
              title: detail.seasonName
                ?? detail.seasonNumber.map { $0 == 0 ? "特别篇" : "第 \($0) 季" }
                ?? "所属季",
              symbol: "rectangle.stack"
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-mediaserver-breadcrumb-season")
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  private func breadcrumbPill(title: String, symbol: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.caption2.weight(.semibold))
      Text(title)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(.primary.opacity(0.88))
    .padding(.horizontal, 11)
    .padding(.vertical, 6)
    .background {
      Capsule()
        .fill(.primary.opacity(colorScheme == .light ? 0.08 : 0.12))
        .overlay { Capsule().strokeBorder(.primary.opacity(0.16), lineWidth: 0.6) }
    }
  }

  // MARK: - Action Bar (Play / Subscribe / Search)

  private func actionBar(
    _ detail: MediaServerItemDetailDTO, isCompactLandscape: Bool = false
  ) -> some View {
    let hasPlayAction = canInitiatePlayback(detail)
    let subscribeTarget = effectiveExternalIdentity
    let externalURL = detail.playUrl.flatMap(URL.init(string:))
    let hasOverflowActions = subscribeTarget != nil || externalURL != nil
    let useSingleRow = isCompactLandscape && !dynamicTypeSize.isAccessibilitySize
    let layout =
      useSingleRow
      ? AnyLayout(HStackLayout(spacing: 10))
      : AnyLayout(VStackLayout(spacing: 10))
    return layout {
      if hasPlayAction {
        HStack(spacing: 10) {
          Button {
            Task { await triggerPrimaryPlay(detail) }
          } label: {
            HStack(spacing: 8) {
              if isLaunchingPlayback {
                ProgressView()
                  .controlSize(.small)
                  .tint(colorScheme == .light ? .white : .black)
              } else {
                Image(systemName: "play.fill")
                  .font(.subheadline.weight(.bold))
              }
              Text(primaryPlayLabel(detail))
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            }
            .foregroundStyle(
              colorScheme == .light ? .white : Color(red: 0.08, green: 0.08, blue: 0.12)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
              Capsule().fill(colorScheme == .light ? appearance.accentColor : .white)
            }
          }
          .buttonStyle(.plain)
          .disabled(isLaunchingPlayback)
          .accessibilityIdentifier("native-mediaserver-detail-play")

          if hasOverflowActions && !useSingleRow {
            overflowActionMenu(detail: detail, external: subscribeTarget, externalURL: externalURL)
          }
        }
      }

      if (canSubscribe && subscribeTarget != nil) || canSearchResources
        || ((!hasPlayAction || useSingleRow) && hasOverflowActions)
      {
        HStack(spacing: 10) {
          if canSubscribe, let ext = subscribeTarget {
            let subscribedNow = isCurrentlySubscribed(detail, external: ext)
            Button {
              if subscribedNow {
                let targetSeason = resolveCancelSeason(detail, external: ext)
                let titleText = detail.seriesName ?? detail.title
                let message =
                  targetSeason.map { "确认取消《\(titleText)》第 \($0) 季的订阅吗？" }
                  ?? "确认取消《\(titleText)》的订阅吗？"
                pendingCancelSubscribe = MediaServerCancelSubscribeTarget(
                  source: ext.source,
                  mediaID: ext.mediaID,
                  type: ext.type,
                  season: targetSeason,
                  message: message
                )
              } else {
                Task { await performSubscribe(detail, external: ext) }
              }
            } label: {
              HStack(spacing: 6) {
                if isSubscribing {
                  ProgressView().controlSize(.mini).tint(.primary)
                } else {
                  Image(systemName: subscribedNow ? "checkmark.circle.fill" : "plus")
                    .font(.subheadline.weight(.semibold))
                }
                Text(subscribeButtonTitle(detail, subscribed: subscribedNow))
                  .font(.subheadline.weight(.semibold))
                  .lineLimit(1)
              }
              .foregroundStyle(
                subscribedNow ? Color(red: 0.44, green: 0.90, blue: 0.66) : .primary
              )
              .frame(maxWidth: .infinity)
              .frame(height: useSingleRow ? 48 : 46)
              .background {
                Capsule()
                  .fill(
                    subscribedNow
                      ? Color(red: 0.24, green: 0.66, blue: 0.46).opacity(0.24)
                      : .primary.opacity(colorScheme == .light ? 0.08 : 0.13)
                  )
                  .overlay {
                    Capsule().strokeBorder(
                      subscribedNow
                        ? Color(red: 0.44, green: 0.90, blue: 0.66).opacity(0.36)
                        : .primary.opacity(0.20),
                      lineWidth: 0.7
                    )
                  }
              }
            }
            .buttonStyle(.plain)
            .disabled(isSubscribing)
            .contextMenu {
              if subscribedNow {
                Button {
                  openSubscribeFiles(detail, external: ext)
                } label: {
                  Label("订阅文件详情", systemImage: "doc.text.magnifyingglass")
                }
              }
            }
            .accessibilityIdentifier("native-mediaserver-detail-subscribe")
          }

          if canSearchResources {
            NavigationLink {
              resourceSearchDestination(detail)
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                  .font(.subheadline.weight(.semibold))
                Text("搜索资源")
                  .font(.subheadline.weight(.semibold))
                  .lineLimit(1)
              }
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity)
              .frame(height: useSingleRow ? 48 : 46)
              .background {
                Capsule()
                  .fill(.primary.opacity(colorScheme == .light ? 0.08 : 0.13))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.20), lineWidth: 0.7) }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-mediaserver-detail-search")
          }

          if (!hasPlayAction || useSingleRow) && hasOverflowActions {
            overflowActionMenu(detail: detail, external: subscribeTarget, externalURL: externalURL)
          }
        }
      }
    }
  }

  /// 将原先右上角的更多选项收拢至操作栏圆形「…」玻璃菜单，保持顶部海报区域纯净无多余按钮。
  private func overflowActionMenu(
    detail: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)?,
    externalURL: URL?
  ) -> some View {
    Menu {
      if let ext = external {
        NavigationLink {
          NativeMediaDetailPage(
            session: session,
            identity: NativeMediaIdentity(
              source: ext.source, mediaID: ext.mediaID, type: ext.type)
          )
        } label: {
          Label("查看刮削元数据详情", systemImage: "info.circle")
        }
        if canSubscribe && isCurrentlySubscribed(detail, external: ext) {
          Button {
            openSubscribeFiles(detail, external: ext)
          } label: {
            Label("订阅文件详情", systemImage: "doc.text.magnifyingglass")
          }
        }
      }
      if let url = externalURL {
        Button {
          UIApplication.shared.open(url)
        } label: {
          Label("在外部媒体服务器打开", systemImage: "arrow.up.right.square")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(width: 48, height: 48)
        .background {
          Circle()
            .fill(.primary.opacity(colorScheme == .light ? 0.08 : 0.13))
            .overlay { Circle().strokeBorder(.primary.opacity(0.20), lineWidth: 0.7) }
        }
        .contentShape(Circle())
    }
    .accessibilityLabel("更多选项")
    .accessibilityIdentifier("native-mediaserver-detail-menu")
  }

  @ViewBuilder
  private func resourceSearchDestination(_ detail: MediaServerItemDetailDTO) -> some View {
    let searchTitle = detail.seriesName ?? detail.title
    if let ext = effectiveExternalIdentity {
      NativeResourceSearchPage(
        session: session,
        target: .media(
          identity: NativeMediaIdentity(source: ext.source, mediaID: ext.mediaID, type: ext.type),
          title: searchTitle,
          season: detail.seasonNumber
        )
      )
    } else {
      NativeResourceSearchPage(
        session: session,
        target: .lastResults,
        initialKeyword: searchTitle,
        browseHome: false
      )
    }
  }

  // MARK: - Pre-Play Version / Audio / Subtitle Selector (Requirement #4)

  private func prePlayTrackSelectorCard(
    detail: MediaServerItemDetailDTO, source: MediaServerSourceDTO
  ) -> some View {
    CinematicPanel(padding: 0) {
      VStack(spacing: 0) {
        // 1. 版本 / 媒体规格行
        if detail.mediaSources.count > 1 {
          Menu {
            ForEach(detail.mediaSources) { candidate in
              Button {
                selectedSourceID = candidate.id
                let preferZh =
                  UserDefaults.standard.object(forKey: "nativeV2.playback.preferChineseSub")
                  as? Bool
                  ?? true
                trackSelection = MediaPlaybackTrackSelection.defaultSelection(
                  for: candidate, preferChineseSub: preferZh)
              } label: {
                if candidate.id == source.id {
                  Label(candidate.specSummary, systemImage: "checkmark")
                } else {
                  Text(candidate.specSummary)
                }
              }
            }
          } label: {
            selectorRow(label: "版本", value: source.specSummary, showChevron: true)
          }
          .accessibilityIdentifier("native-mediaserver-preplay-source")
        } else {
          selectorRow(label: "视频", value: source.specSummary, showChevron: false)
        }

        // 2. 音轨选择行
        if !source.audioStreams.isEmpty {
          Divider().overlay(.primary.opacity(0.10)).padding(.leading, 16)
          Menu {
            ForEach(Array(source.audioStreams.enumerated()), id: \.element.id) { idx, stream in
              Button {
                trackSelection = trackSelection.selectingAudio(stream, in: source)
              } label: {
                let isSelected = trackSelection.audioOrdinal == idx
                if isSelected {
                  Label(stream.resolvedLabel, systemImage: "checkmark")
                } else {
                  Text(stream.resolvedLabel)
                }
              }
            }
          } label: {
            selectorRow(
              label: "音轨",
              value: trackSelection.audioDisplayTitle
                ?? source.audioStreams.first?.resolvedLabel
                ?? "默认音轨",
              showChevron: source.audioStreams.count > 1
            )
          }
          .accessibilityIdentifier("native-mediaserver-preplay-audio")
        }

        // 3. 字幕选择行
        if !source.subtitleStreams.isEmpty {
          Divider().overlay(.primary.opacity(0.10)).padding(.leading, 16)
          Menu {
            Button {
              trackSelection = trackSelection.selectingSubtitle(nil, in: source)
            } label: {
              if trackSelection.subtitleDisabled {
                Label("关闭字幕", systemImage: "checkmark")
              } else {
                Text("关闭字幕")
              }
            }
            ForEach(source.subtitleStreams) { stream in
              let isSelected = isSubtitleStreamSelected(stream, in: source)
              let tag = stream.isExternal ? "外挂" : "内嵌"
              Button {
                trackSelection = trackSelection.selectingSubtitle(stream, in: source)
              } label: {
                if isSelected {
                  Label("\(tag) · \(stream.resolvedLabel)", systemImage: "checkmark")
                } else {
                  Text("\(tag) · \(stream.resolvedLabel)")
                }
              }
            }
          } label: {
            selectorRow(
              label: "字幕",
              value: trackSelection.subtitleDisabled
                ? "关闭字幕"
                : (trackSelection.subtitleDisplayTitle ?? "默认字幕"),
              showChevron: true
            )
          }
          .accessibilityIdentifier("native-mediaserver-preplay-subtitle")
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-mediaserver-preplay-selector")
  }

  /// iOS 设置风「左参数名 / 右参数值」选择行，视觉统一克制。
  private func selectorRow(label: String, value: String, showChevron: Bool) -> some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary.opacity(0.76))
      Spacer(minLength: 12)
      Text(value)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .multilineTextAlignment(.trailing)
      if showChevron {
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.primary.opacity(0.45))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
    .contentShape(Rectangle())
  }

  private func isSubtitleStreamSelected(
    _ stream: MediaServerStreamDTO, in source: MediaServerSourceDTO
  ) -> Bool {
    guard !trackSelection.subtitleDisabled else { return false }
    if let extID = stream.subtitleId, !extID.isEmpty {
      return trackSelection.subtitleExternalID == extID
    }
    let embedded = source.subtitleStreams.filter { !$0.isExternal && $0.subtitleId == nil }
    guard let ordinal = embedded.firstIndex(where: { $0.id == stream.id }) else { return false }
    return trackSelection.subtitleExternalID == nil && trackSelection.subtitleOrdinal == ordinal
  }

  // MARK: - Collection Items Section (BoxSet -> Child Items)

  private func collectionGridColumns(for width: CGFloat) -> [GridItem] {
    let resolved = NativeDeviceLayout.resolvedContainerWidth(width)
    let count = NativeDeviceLayout.posterGridCount(
      for: min(resolved, 1020), isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
  }

  /// 合集详情页内嵌的子作品海报网格，点击后进入对应电影或剧集的原生媒体库详情页。
  private func collectionItemsSection(
    _ detail: MediaServerItemDetailDTO, containerWidth: CGFloat = 0
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("合集内容")
          .font(.title3.weight(.bold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Text("共 \(collectionItems.count) 部")
          .font(.caption.weight(.medium))
          .foregroundStyle(.primary.opacity(0.60))
      }

      LazyVGrid(columns: collectionGridColumns(for: containerWidth), spacing: 16) {
        ForEach(collectionItems) { child in
          NavigationLink {
            NativeMediaServerDetailPage(
              session: session,
              server: child.server ?? resolvedServer,
              itemID: child.itemId,
              fallbackTitle: child.title,
              fallbackItemType: child.itemType,
              fallbackPoster: child.poster ?? child.thumb
            )
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                  NativeMediaArtwork(
                    session: session,
                    reference: child.poster ?? child.thumb ?? child.backdrop,
                    role: .poster,
                    maximumWidth: 320
                  )
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                  if child.played == true {
                    Image(systemName: "checkmark.circle.fill")
                      .font(.system(size: 16, weight: .semibold))
                      .foregroundStyle(.white, NativeTheme.success)
                      .padding(6)
                  } else if let rating = child.rating, rating > 0 {
                    Text(String(format: "%.1f", rating))
                      .font(.caption2.weight(.bold).monospacedDigit())
                      .foregroundStyle(.white)
                      .padding(.horizontal, 6)
                      .padding(.vertical, 2.5)
                      .background(.black.opacity(0.62), in: Capsule())
                      .padding(6)
                  }
                }
                .overlay {
                  RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
                }

              Text(child.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

              if let year = child.yearText, !year.isEmpty {
                Text(year)
                  .font(.caption2)
                  .foregroundStyle(.primary.opacity(0.60))
                  .lineLimit(1)
              }

              Spacer(minLength: 0)
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-mediaserver-collection-item-\(child.itemId)")
        }
      }
    }
  }

  // MARK: - Seasons Section (Series -> Seasons)

  private func seasonsSection(_ detail: MediaServerItemDetailDTO) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("分季")
          .font(.title3.weight(.bold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Text("共 \(seasons.count) 季")
          .font(.caption.weight(.medium))
          .foregroundStyle(.primary.opacity(0.60))
      }

      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 12) {
          ForEach(seasons) { season in
            NavigationLink {
              NativeMediaServerDetailPage(
                session: session,
                server: season.server ?? resolvedServer,
                itemID: season.itemId,
                fallbackTitle: season.title,
                fallbackItemType: "Season",
                fallbackPoster: season.poster ?? detail.poster
              )
            } label: {
              seasonCard(season, fallbackPoster: detail.poster)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-mediaserver-season-\(season.itemId)")
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private func seasonCard(_ season: MediaServerBrowseItemDTO, fallbackPoster: String?) -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      NativeMediaArtwork(
        session: session,
        reference: season.poster ?? fallbackPoster,
        role: .poster,
        maximumWidth: 300
      )
      .frame(width: 112, height: 168)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(alignment: .topTrailing) {
        if season.played == true {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white, NativeTheme.success)
            .padding(6)
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
      }

      Text(season.title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      if let count = season.childCount, count > 0 {
        Text("\(count) 集")
          .font(.caption2)
          .foregroundStyle(.primary.opacity(0.60))
      }
    }
    .frame(width: 112, alignment: .leading)
  }

  // MARK: - Episodes Section (Series & Season 16:9 Horizontal Strip / Music Album Vertical Tracks)

  private func episodesSection(_ detail: MediaServerItemDetailDTO, isWide: Bool = false)
    -> some View
  {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(detail.kind == .musicAlbum ? "曲目列表" : "剧集列表")
          .font(.title3.weight(.bold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        if detail.kind == .series, seasons.count > 1 {
          Menu {
            ForEach(seasons) { s in
              Button {
                selectedSeasonNumber = s.seasonNumber
                Task { await loadEpisodesForSeason(seriesID: detail.itemId, season: s) }
              } label: {
                if selectedSeasonNumber == s.seasonNumber {
                  Label(s.title, systemImage: "checkmark")
                } else {
                  Text(s.title)
                }
              }
            }
          } label: {
            HStack(spacing: 4) {
              Text(
                seasons.first(where: { $0.seasonNumber == selectedSeasonNumber })?.title
                  ?? seasons.first?.title ?? "选择季"
              )
              .font(.caption.weight(.semibold))
              Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(appearance.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(appearance.accentColor.opacity(0.14), in: Capsule())
          }
          .accessibilityIdentifier("native-mediaserver-series-season-picker")
        } else {
          Text("共 \(episodes.count) \(detail.kind == .musicAlbum ? "首" : "集")")
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(0.60))
        }
      }

      if detail.kind == .musicAlbum {
        VStack(spacing: 10) {
          ForEach(Array(episodes.enumerated()), id: \.element.id) { index, ep in
            audioTrackRowCard(ep, index: index, parentDetail: detail)
          }
        }
      } else {
        let cardWidth: CGFloat = isWide ? 252 : 224
        let cardHeight: CGFloat = isWide ? 142 : 126
        ScrollViewReader { scrollProxy in
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
              ForEach(Array(episodes.enumerated()), id: \.element.id) { index, ep in
                landscapeEpisodeCard(
                  ep,
                  index: index,
                  parentDetail: detail,
                  cardWidth: cardWidth,
                  thumbHeight: cardHeight
                )
                .id(ep.id)
              }
            }
          }
          .onAppear {
            if let nextIdx = nextPlayableEpisodeIndex(),
              nextIdx > 0,
              episodes.indices.contains(nextIdx)
            {
              scrollProxy.scrollTo(episodes[nextIdx].id, anchor: .leading)
            }
          }
          .onChange(of: episodes.first?.id) { _ in
            if let nextIdx = nextPlayableEpisodeIndex(),
              episodes.indices.contains(nextIdx)
            {
              withAnimation(.easeOut(duration: 0.22)) {
                scrollProxy.scrollTo(episodes[nextIdx].id, anchor: .leading)
              }
            }
          }
        }
      }
    }
  }

  /// 剧集/分季 16:9 横版剧照卡片：优先读取单集横版截图 `thumb` / `backdrop`，左上角集号、右上角已看、底部进度与快速播放。
  private func landscapeEpisodeCard(
    _ ep: MediaServerBrowseItemDTO,
    index: Int,
    parentDetail: MediaServerItemDetailDTO,
    cardWidth: CGFloat,
    thumbHeight: CGFloat
  ) -> some View {
    let artworkRef = ep.thumb ?? ep.backdrop ?? parentDetail.backdrop ?? ep.poster
    let codeLabel = ep.episodeCode ?? String(format: "E%02d", ep.episodeNumber ?? (index + 1))

    return ZStack(alignment: .topLeading) {
      NavigationLink {
        NativeMediaServerDetailPage(
          session: session,
          server: ep.server ?? resolvedServer,
          itemID: ep.itemId,
          fallbackTitle: ep.title,
          fallbackItemType: ep.itemType,
          fallbackPoster: artworkRef
        )
      } label: {
        VStack(alignment: .leading, spacing: 7) {
          ZStack(alignment: .bottom) {
            NativeMediaArtwork(
              session: session,
              reference: artworkRef,
              role: .backdrop,
              maximumWidth: 520
            )
            .frame(width: cardWidth, height: thumbHeight)
            .clipped()

            LinearGradient(
              colors: [.clear, .black.opacity(0.62)],
              startPoint: .center,
              endPoint: .bottom
            )
            .frame(height: thumbHeight * 0.52)

            if let progress = ep.progressFraction, progress > 0.01, ep.played != true {
              GeometryReader { bar in
                ZStack(alignment: .leading) {
                  Rectangle().fill(.black.opacity(0.45))
                  Rectangle()
                    .fill(appearance.accentColor)
                    .frame(width: max(6, bar.size.width * progress))
                }
              }
              .frame(height: 3)
            }
          }
          .frame(width: cardWidth, height: thumbHeight)
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
          .overlay(alignment: .topLeading) {
            Text(codeLabel)
              .font(.caption2.weight(.bold).monospacedDigit())
              .foregroundStyle(.white)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(.black.opacity(0.62), in: Capsule())
              .padding(8)
          }
          .overlay(alignment: .topTrailing) {
            if ep.played == true {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white, NativeTheme.success)
                .padding(8)
            }
          }
          .overlay(alignment: .bottomLeading) {
            if let dur = ep.formattedDuration {
              Text(dur)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.leading, 8)
                .padding(.bottom, 8)
            }
          }
          .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
          }

          Text(ep.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)

          if let overview = ep.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
            !overview.isEmpty
          {
            Text(overview)
              .font(.caption)
              .foregroundStyle(.primary.opacity(0.64))
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
        .frame(width: cardWidth, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-mediaserver-episode-row-\(ep.itemId)")

      Button {
        Task { await playEpisodeAt(index: index) }
      } label: {
        ZStack {
          Circle()
            .fill(.ultraThinMaterial)
            .overlay {
              Circle().strokeBorder(.white.opacity(0.32), lineWidth: 0.7)
            }
          Image(systemName: "play.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: 1)
        }
        .frame(width: 34, height: 34)
        .shadow(color: .black.opacity(0.32), radius: 5, y: 2)
      }
      .buttonStyle(.plain)
      .disabled(isLaunchingPlayback)
      .offset(x: cardWidth - 42, y: thumbHeight - 42)
      .accessibilityLabel("播放 \(ep.title)")
      .accessibilityIdentifier("native-mediaserver-episode-play-\(ep.itemId)")
    }
  }

  /// 音乐专辑曲目纵向行卡片。
  private func audioTrackRowCard(
    _ ep: MediaServerBrowseItemDTO, index: Int, parentDetail: MediaServerItemDetailDTO
  ) -> some View {
    CinematicPanel(padding: 10) {
      HStack(alignment: .center, spacing: 12) {
        NavigationLink {
          NativeMediaServerDetailPage(
            session: session,
            server: ep.server ?? resolvedServer,
            itemID: ep.itemId,
            fallbackTitle: ep.title,
            fallbackItemType: ep.itemType,
            fallbackPoster: ep.thumb ?? ep.poster ?? parentDetail.backdrop
          )
        } label: {
          HStack(alignment: .center, spacing: 12) {
            Text("\(ep.episodeNumber ?? (index + 1))")
              .font(.subheadline.weight(.semibold).monospacedDigit())
              .foregroundStyle(.primary.opacity(0.60))
              .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
              Text(ep.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
              if let dur = ep.formattedDuration {
                Text(dur)
                  .font(.caption2)
                  .foregroundStyle(.primary.opacity(0.55))
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-mediaserver-episode-row-\(ep.itemId)")

        Button {
          Task { await playEpisodeAt(index: index) }
        } label: {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 30))
            .foregroundStyle(appearance.accentColor)
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .disabled(isLaunchingPlayback)
        .accessibilityLabel("播放 \(ep.title)")
        .accessibilityIdentifier("native-mediaserver-episode-play-\(ep.itemId)")
      }
    }
  }

  /// 集详情页下方的本季分集横向速览条，优先使用单集横版截图。
  private func adjacentEpisodesStrip(_ detail: MediaServerItemDetailDTO) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("本季更多剧集")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 10) {
          ForEach(episodes) { ep in
            let isCurrent = ep.itemId == detail.itemId
            let epArtwork = ep.thumb ?? ep.backdrop ?? detail.backdrop ?? ep.poster
            NavigationLink {
              NativeMediaServerDetailPage(
                session: session,
                server: ep.server ?? resolvedServer,
                itemID: ep.itemId,
                fallbackTitle: ep.title,
                fallbackItemType: "Episode",
                fallbackPoster: epArtwork
              )
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                NativeMediaArtwork(
                  session: session,
                  reference: epArtwork,
                  role: .backdrop,
                  maximumWidth: 320
                )
                .frame(width: 146, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                      isCurrent ? appearance.accentColor : .white.opacity(0.14),
                      lineWidth: isCurrent ? 2 : 0.6
                    )
                }
                Text(ep.episodeCode.map { "\($0) · \(ep.title)" } ?? ep.title)
                  .font(.caption.weight(isCurrent ? .bold : .medium))
                  .foregroundStyle(isCurrent ? appearance.accentColor : .primary)
                  .lineLimit(1)
              }
              .frame(width: 146, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)
          }
        }
      }
    }
  }

  // MARK: - Synopsis / Cast / Metadata

  @ViewBuilder
  private func synopsisSection(_ detail: MediaServerItemDetailDTO) -> some View {
    if let overview = detail.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
      !overview.isEmpty
    {
      CinematicPanel {
        VStack(alignment: .leading, spacing: 8) {
          Text("剧情简介")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          Text(overview)
            .font(.subheadline)
            .foregroundStyle(.primary.opacity(0.84))
            .lineSpacing(4)
            .lineLimit(synopsisExpanded ? nil : 4)
          if overview.count > 100 {
            Button(synopsisExpanded ? "收起" : "展开全部") {
              withAnimation(.easeInOut(duration: 0.2)) { synopsisExpanded.toggle() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(appearance.accentColor)
          }
        }
      }
    }
  }

  private func castSection(_ people: [MediaServerPersonDTO]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("演职员")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          ForEach(people.prefix(18), id: \.stableID) { person in
            VStack(spacing: 6) {
              Group {
                if let image = person.image, !image.isEmpty {
                  NativeMediaArtwork(
                    session: session, reference: image, role: .poster, maximumWidth: 180)
                } else {
                  ZStack {
                    Circle().fill(.white.opacity(0.10))
                    Image(systemName: "person.fill")
                      .font(.title3)
                      .foregroundStyle(.primary.opacity(0.55))
                  }
                }
              }
              .frame(width: 68, height: 68)
              .clipShape(Circle())
              .overlay { Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.6) }

              Text(person.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
              if let role = person.role ?? person.type, !role.isEmpty {
                Text(role)
                  .font(.caption2)
                  .foregroundStyle(.primary.opacity(0.58))
                  .lineLimit(1)
              }
            }
            .frame(width: 76)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private func metadataCard(_ detail: MediaServerItemDetailDTO) -> some View {
    let rows = metadataRows(detail)
    return Group {
      if !rows.isEmpty {
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
              if idx > 0 {
                Divider().overlay(.primary.opacity(0.10)).padding(.leading, 16)
              }
              HStack(spacing: 12) {
                Text(row.0)
                  .font(.subheadline)
                  .foregroundStyle(.primary.opacity(0.68))
                Spacer(minLength: 12)
                Text(row.1)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(.primary)
                  .multilineTextAlignment(.trailing)
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 11)
            }
          }
        }
      }
    }
  }

  // MARK: - 类似作品 / 链接 / 媒体信息（横向流式卡片）

  /// 类似作品横向竖版海报栏：2:3 海报 + 右下角暗色半透评分胶囊 + 标题 + 年份。
  private func similarWorksSection(_ detail: MediaServerItemDetailDTO) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("类似作品")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 12) {
          ForEach(similarItems.prefix(16)) { item in
            switch item.destination {
            case .externalMedia(let identity):
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: identity)
              } label: {
                similarWorkPosterTile(item)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-mediaserver-similar-\(item.id)")

            case .libraryItem(let srv, let targetID, let itemType):
              NavigationLink {
                NativeMediaServerDetailPage(
                  session: session,
                  server: srv ?? resolvedServer,
                  itemID: targetID,
                  fallbackTitle: item.title,
                  fallbackItemType: itemType,
                  fallbackPoster: item.poster
                )
              } label: {
                similarWorkPosterTile(item)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-mediaserver-similar-\(item.id)")

            case .none:
              similarWorkPosterTile(item)
            }
          }
        }
      }
    }
    .accessibilityIdentifier("native-mediaserver-similar-section")
  }

  private func similarWorkPosterTile(_ item: MediaServerSimilarCardItem) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      NativeMediaArtwork(
        session: session,
        reference: item.poster,
        role: .poster,
        maximumWidth: 360
      )
      .frame(width: 114, height: 171)
      .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        if let rating = item.rating, rating > 0 {
          Text(String(format: "%.1f", rating))
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6.5)
            .padding(.vertical, 2.5)
            .background(.black.opacity(0.68), in: Capsule())
            .padding(6)
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
      }

      Text(item.title)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)

      if let year = item.year, !year.isEmpty {
        Text(year)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(width: 114, alignment: .leading)
  }

  /// 外部资料站链接胶囊横栏（豆瓣、IMDb、TheMovieDb、Trakt、TheTVDB 等）。
  private func externalLinksSection(_ links: [MediaServerExternalLinkChip]) -> some View {
    let isLight = colorScheme == .light
    return VStack(alignment: .leading, spacing: 12) {
      Text("链接")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(links) { link in
            Button {
              UIApplication.shared.open(link.url)
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "link")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                Text(link.title)
                  .font(.footnote.weight(.medium))
                  .foregroundStyle(.primary.opacity(0.90))
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 8.5)
              .background {
                Capsule()
                  .fill(isLight ? Color.black.opacity(0.045) : Color.white.opacity(0.055))
                  .overlay {
                    Capsule()
                      .strokeBorder(
                        isLight ? Color.black.opacity(0.14) : Color.white.opacity(0.16),
                        lineWidth: 0.8
                      )
                  }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-mediaserver-link-\(link.id)")
          }
        }
      }
    }
    .accessibilityIdentifier("native-mediaserver-links-section")
  }

  /// 解析当前作品可用的全部外部站点链接。
  private func resolvedExternalLinks(
    _ detail: MediaServerItemDetailDTO
  ) -> [MediaServerExternalLinkChip] {
    let isTV = detail.kind.isTelevisionHierarchy || detail.mediaType == "电视剧"
    let doubanID = Self.cleanExternalID(
      enrichedIDs.doubanID ?? detail.doubanId ?? parentSeriesDetail?.doubanId)
    let imdbID = Self.cleanExternalID(
      enrichedIDs.imdbID ?? detail.imdbId ?? parentSeriesDetail?.imdbId)
    let tmdbID = Self.cleanExternalID(
      enrichedIDs.tmdbID ?? detail.tmdbId ?? parentSeriesDetail?.tmdbId)
    let tvdbID = Self.cleanExternalID(
      enrichedIDs.tvdbID ?? detail.tvdbId ?? parentSeriesDetail?.tvdbId)
    let bangumiID = Self.cleanExternalID(enrichedIDs.bangumiID)

    var items: [MediaServerExternalLinkChip] = []
    if let doubanID, let url = URL(string: "https://movie.douban.com/subject/\(doubanID)/") {
      items.append(MediaServerExternalLinkChip(id: "douban", title: "豆瓣", url: url))
    }
    if let imdbID, let url = URL(string: "https://www.imdb.com/title/\(imdbID)/") {
      items.append(MediaServerExternalLinkChip(id: "imdb", title: "IMDb", url: url))
    }
    if let tmdbID,
      let url = URL(string: "https://www.themoviedb.org/\(isTV ? "tv" : "movie")/\(tmdbID)")
    {
      items.append(MediaServerExternalLinkChip(id: "tmdb", title: "TheMovieDb", url: url))
    }
    if let imdbID,
      let encoded = imdbID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(string: "https://trakt.tv/search/imdb?query=\(encoded)")
    {
      items.append(MediaServerExternalLinkChip(id: "trakt", title: "Trakt", url: url))
    } else if let tmdbID,
      let encoded = tmdbID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
      let url = URL(
        string: "https://trakt.tv/search/tmdb/\(encoded)?id_type=\(isTV ? "show" : "movie")")
    {
      items.append(MediaServerExternalLinkChip(id: "trakt", title: "Trakt", url: url))
    }
    if let tvdbID,
      let url = URL(
        string: "https://www.thetvdb.com/dereferrer/\(isTV ? "series" : "movie")/\(tvdbID)")
    {
      items.append(MediaServerExternalLinkChip(id: "tvdb", title: "TheTVDB", url: url))
    }
    if let bangumiID, let url = URL(string: "https://bgm.tv/subject/\(bangumiID)") {
      items.append(MediaServerExternalLinkChip(id: "bangumi", title: "Bangumi", url: url))
    }
    if let playURLText = detail.playUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
      !playURLText.isEmpty,
      let webURL = URL(string: playURLText),
      let scheme = webURL.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    {
      items.append(
        MediaServerExternalLinkChip(
          id: "server-web",
          title: resolvedServer ?? "媒体库网页",
          url: webURL
        )
      )
    }
    return items
  }

  /// 媒体信息横向流式轨道参数卡片（视频 / 音频 / 字幕）。
  private func mediaStreamsInfoSection(_ source: MediaServerSourceDTO) -> some View {
    let summaryParts: [String] = {
      var parts: [String] = []
      if let container = source.container?.trimmingCharacters(in: .whitespacesAndNewlines),
        !container.isEmpty
      {
        parts.append(container.uppercased())
      }
      if let size = source.size, size > 0 {
        parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
      }
      return parts
    }()

    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("媒体信息")
          .font(.title3.weight(.bold))
          .accessibilityAddTraits(.isHeader)
        Spacer()
        if !summaryParts.isEmpty {
          Text(summaryParts.joined(separator: " · "))
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(Array(source.videoStreams.enumerated()), id: \.element.id) { idx, stream in
            mediaStreamInfoCard(
              symbol: "video",
              title: "视频",
              isSelected: source.videoStreams.count > 1 && idx == 0,
              rows: videoStreamRows(stream, sourceBitrate: source.bitrate)
            )
          }

          ForEach(Array(source.audioStreams.enumerated()), id: \.element.id) { idx, stream in
            let selected =
              trackSelection.audioOrdinal != nil
              ? trackSelection.audioOrdinal == idx
              : stream.isDefault
            mediaStreamInfoCard(
              symbol: "speaker.wave.2",
              title: "音频",
              isSelected: selected,
              rows: audioStreamRows(stream)
            )
          }

          ForEach(source.subtitleStreams) { stream in
            let selected =
              isSubtitleStreamSelected(stream, in: source)
              || (trackSelection.subtitleOrdinal == nil
                && trackSelection.subtitleExternalID == nil
                && !trackSelection.subtitleDisabled
                && stream.isDefault)
            mediaStreamInfoCard(
              symbol: "captions.bubble",
              title: "字幕",
              isSelected: selected,
              rows: subtitleStreamRows(stream)
            )
          }
        }
      }
    }
    .accessibilityIdentifier("native-mediaserver-mediainfo-section")
  }

  private func mediaStreamInfoCard(
    symbol: String,
    title: String,
    isSelected: Bool,
    rows: [(String, String)]
  ) -> some View {
    let isLight = colorScheme == .light
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary.opacity(0.88))
        Text(title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(.primary)
        if isSelected {
          Image(systemName: "checkmark")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.primary)
        }
        Spacer(minLength: 0)
      }
      .padding(.bottom, 2)

      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.0)
              .font(.footnote)
              .foregroundStyle(.primary.opacity(0.84))
            Text(row.1)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
        }
      }
    }
    .padding(16)
    .frame(width: 248, alignment: .topLeading)
    .background {
      shape
        .fill(isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.045))
        .overlay {
          shape.strokeBorder(
            isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.14),
            lineWidth: 0.8
          )
        }
    }
  }

  private func videoStreamRows(
    _ stream: MediaServerStreamDTO, sourceBitrate: Int?
  ) -> [(String, String)] {
    var rows: [(String, String)] = []
    func appendIfPresent(_ key: String, _ raw: String?) {
      guard let val = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty else {
        return
      }
      rows.append((key, val))
    }
    appendIfPresent("标题", stream.displayTitle ?? stream.resolvedLabel)
    appendIfPresent("内嵌标题", stream.title)
    appendIfPresent("编码", stream.codec)
    appendIfPresent("分辨率", stream.formattedResolution)
    appendIfPresent("帧率", stream.frameRate)
    let fallbackBitrate: String? = {
      if let formatted = stream.formattedBitrate { return formatted }
      guard let sb = sourceBitrate, sb > 0 else { return nil }
      return sb >= 2_000_000
        ? String(format: "%.1fmbps", Double(sb) / 1_000_000.0)
        : "\(Int((Double(sb) / 1_000.0).rounded()))kbps"
    }()
    appendIfPresent("比特率", fallbackBitrate)
    appendIfPresent("动态范围", stream.videoRange)
    appendIfPresent("配置", stream.profile)
    appendIfPresent("等级", stream.level)
    appendIfPresent("长宽比", stream.inferredAspectRatio)
    if let interlaced = stream.isInterlaced {
      rows.append(("交错", interlaced ? "是" : "否"))
    }
    appendIfPresent("基色", stream.colorPrimaries)
    appendIfPresent("色域", stream.colorSpace)
    if let depth = stream.bitDepth, depth > 0 {
      rows.append(("位深", String(depth)))
    }
    return rows
  }

  private func audioStreamRows(_ stream: MediaServerStreamDTO) -> [(String, String)] {
    var rows: [(String, String)] = []
    func appendIfPresent(_ key: String, _ raw: String?) {
      guard let val = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty else {
        return
      }
      rows.append((key, val))
    }
    appendIfPresent("标题", stream.displayTitle ?? stream.resolvedLabel)
    appendIfPresent("内嵌标题", stream.title)
    appendIfPresent("语言", stream.language)
    appendIfPresent("布局", stream.channelLayout)
    if let ch = stream.channels, ch > 0 {
      rows.append(("声道", String(ch)))
    }
    appendIfPresent("编码", stream.codec)
    appendIfPresent("比特率", stream.formattedBitrate)
    appendIfPresent("采样率", stream.formattedSampleRate)
    rows.append(("外部", stream.isExternal ? "是" : "否"))
    rows.append(("默认", stream.isDefault ? "是" : "否"))
    return rows
  }

  private func subtitleStreamRows(_ stream: MediaServerStreamDTO) -> [(String, String)] {
    var rows: [(String, String)] = []
    func appendIfPresent(_ key: String, _ raw: String?) {
      guard let val = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty else {
        return
      }
      rows.append((key, val))
    }
    appendIfPresent("标题", stream.displayTitle ?? stream.resolvedLabel)
    appendIfPresent("内嵌标题", stream.title)
    appendIfPresent("语言", stream.language)
    appendIfPresent("编码", stream.codec)
    rows.append(("强制", stream.isForced ? "是" : "否"))
    rows.append(("外部", stream.isExternal ? "是" : "否"))
    rows.append(("默认", stream.isDefault ? "是" : "否"))
    return rows
  }

  nonisolated private static func cleanExternalID(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty,
      trimmed != "0",
      trimmed.lowercased() != "none",
      trimmed.lowercased() != "null"
    else { return nil }
    return trimmed
  }

  private func feedbackBanner(_ text: String, isError: Bool) -> some View {
    CinematicPanel(padding: 12) {
      HStack(spacing: 10) {
        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .foregroundStyle(isError ? .orange : NativeTheme.success)
        Text(text)
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          feedbackMessage = nil
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.60))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var failureCard: some View {
    CinematicPanel {
      VStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle")
          .font(.title2)
          .foregroundStyle(.orange)
        Text("无法读取媒体详情")
          .font(.headline)
        Button("重试") {
          Task { await loadAll() }
        }
        .buttonStyle(.borderedProminent)
        .tint(appearance.accentColor)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
    }
  }

  // MARK: - Formatting Helpers

  private func dimensionBadgeTitle(_ detail: MediaServerItemDetailDTO) -> String {
    switch detail.kind {
    case .movie: "电影"
    case .series: "剧集"
    case .season: "分季"
    case .episode:
      if let s = detail.seasonNumber, let e = detail.episodeNumber {
        String(format: "S%02dE%02d", s, e)
      } else {
        "单集"
      }
    case .musicAlbum: "专辑"
    case .audio: "音乐"
    case .boxSet: "合集"
    default: detail.mediaType ?? "媒体"
    }
  }

  private func heroDisplayTitle(_ detail: MediaServerItemDetailDTO) -> String {
    if detail.kind == .season, let series = detail.seriesName, !series.isEmpty {
      return "\(series) · \(detail.title)"
    }
    return detail.title
  }

  private func metadataLineParts(_ detail: MediaServerItemDetailDTO) -> [String] {
    var parts: [String] = []
    if let year = detail.yearText, !year.isEmpty { parts.append(year) }
    if let dur = detail.formattedDuration { parts.append(dur) }
    if detail.kind == .series {
      if let sc = detail.seasonCount, sc > 0 { parts.append("共 \(sc) 季") }
      if let ec = detail.episodeCount, ec > 0 { parts.append("\(ec) 集") }
    } else if detail.kind == .season, let ec = detail.episodeCount ?? detail.childCount, ec > 0 {
      parts.append("共 \(ec) 集")
    } else if detail.kind == .boxSet,
      let count = detail.childCount ?? (collectionItems.isEmpty ? nil : collectionItems.count),
      count > 0
    {
      parts.append("共 \(count) 部")
    }
    if let rating = detail.rating, rating > 0 {
      parts.append(String(format: "★ %.1f", rating))
    }
    if let official = detail.officialRating, !official.isEmpty {
      parts.append(official)
    }
    return parts
  }

  private func metadataRows(_ detail: MediaServerItemDetailDTO) -> [(String, String)] {
    var rows: [(String, String)] = []
    if let orig = detail.originalTitle, !orig.isEmpty, orig != detail.title {
      rows.append(("原名", orig))
    }
    if let premiere = detail.premiereDate, !premiere.isEmpty {
      rows.append(("首播/发行", premiere))
    }
    if !detail.studios.isEmpty {
      rows.append(("制作/发行", detail.studios.prefix(3).joined(separator: "、")))
    }
    if let tmdb = detail.tmdbId, !tmdb.isEmpty { rows.append(("TMDB", tmdb)) }
    if let imdb = detail.imdbId, !imdb.isEmpty { rows.append(("IMDb", imdb)) }
    if let douban = detail.doubanId, !douban.isEmpty { rows.append(("豆瓣", douban)) }
    return rows
  }

  private func canInitiatePlayback(_ detail: MediaServerItemDetailDTO) -> Bool {
    if detail.kind.isDirectlyPlayable || detail.canPlay { return true }
    if detail.kind == .series || detail.kind == .season || detail.kind == .musicAlbum,
      !episodes.isEmpty
    {
      return true
    }
    return false
  }

  private func primaryPlayLabel(_ detail: MediaServerItemDetailDTO) -> String {
    if detail.kind.isDirectlyPlayable {
      if let resume = detail.resumePositionMs, resume > 30_000 {
        return "继续播放"
      }
      return "立即播放"
    }
    if detail.kind == .series || detail.kind == .season {
      if let target = nextPlayableEpisodeIndex(), episodes.indices.contains(target) {
        let ep = episodes[target]
        if let code = ep.episodeCode {
          return (ep.resumePositionMs ?? 0) > 30_000 ? "继续播放 \(code)" : "播放 \(code)"
        }
      }
      return detail.kind == .season ? "播放本季" : "开始播放"
    }
    if detail.kind == .musicAlbum { return "播放全部" }
    return "立即播放"
  }

  private func isCurrentlySubscribed(
    _ detail: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)
  ) -> Bool {
    if external.type == "电视剧" {
      if let season = detail.seasonNumber {
        return subscribedSeasons.contains(season) || isSubscribed
      }
      return !subscribedSeasons.isEmpty || isSubscribed
    }
    return isSubscribed
  }

  private func resolveCancelSeason(
    _ detail: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)
  ) -> Int? {
    guard external.type == "电视剧" else { return nil }
    if let season = detail.seasonNumber {
      return season
    }
    if let selectedSeasonNumber, subscribedSeasons.contains(selectedSeasonNumber) {
      return selectedSeasonNumber
    }
    return subscribedSeasons.sorted().first
  }

  private func subscribeButtonTitle(
    _ detail: MediaServerItemDetailDTO, subscribed: Bool
  ) -> String {
    if subscribed {
      if detail.kind == .series, subscribedSeasons.count > 0 {
        return "已订阅 \(subscribedSeasons.count) 季"
      }
      return "已订阅"
    }
    if detail.kind == .season || detail.kind == .episode { return "订阅本季" }
    return "订阅"
  }

  private func nextPlayableEpisodeIndex() -> Int? {
    if let resumeIdx = episodes.firstIndex(where: {
      ($0.resumePositionMs ?? 0) > 30_000 && $0.played != true
    }) {
      return resumeIdx
    }
    if let unplayedIdx = episodes.firstIndex(where: { $0.played != true }) {
      return unplayedIdx
    }
    return episodes.isEmpty ? nil : 0
  }

  // MARK: - Playback & Subscribe Actions

  private func makeEpisodeQueue() -> [MediaPlaybackQueueItem] {
    episodes.map { ep in
      MediaPlaybackQueueItem(
        itemId: ep.itemId,
        title: ep.title,
        server: ep.server ?? resolvedServer,
        artworkURL: NativeMediaPlaybackLauncher.proxiedArtworkURL(
          session: session, raw: ep.thumb ?? ep.poster
        )?.absoluteString,
        subtitle: ep.episodeCode
      )
    }
  }

  private func triggerPrimaryPlay(_ detail: MediaServerItemDetailDTO) async {
    if detail.kind.isDirectlyPlayable {
      isLaunchingPlayback = true
      defer { isLaunchingPlayback = false }
      let queue = detail.kind == .episode ? makeEpisodeQueue() : []
      let queueIndex = queue.firstIndex(where: { $0.itemId == detail.itemId }) ?? 0
      let playTitle: String =
        if detail.kind == .episode, let s = detail.seasonNumber, let e = detail.episodeNumber {
          String(format: "S%02dE%02d · %@", s, e, detail.title)
        } else {
          detail.title
        }
      let artwork = NativeMediaPlaybackLauncher.proxiedArtworkURL(
        session: session, raw: detail.poster ?? detail.thumb)
      if let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
        session: session,
        itemID: detail.itemId,
        server: resolvedServer,
        title: playTitle,
        artworkURL: artwork,
        queue: queue,
        queueIndex: queueIndex,
        trackSelection: trackSelection
      ) {
        feedbackMessage = (err, true)
      }
      return
    }

    if let targetIndex = nextPlayableEpisodeIndex() {
      await playEpisodeAt(index: targetIndex)
    }
  }

  private func playEpisodeAt(index: Int) async {
    guard episodes.indices.contains(index) else { return }
    isLaunchingPlayback = true
    defer { isLaunchingPlayback = false }
    let ep = episodes[index]
    let queue = makeEpisodeQueue()
    let title = ep.episodeCode.map { "\($0) · \(ep.title)" } ?? ep.title
    let artwork = NativeMediaPlaybackLauncher.proxiedArtworkURL(
      session: session, raw: ep.thumb ?? ep.poster ?? detail?.poster)
    if let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
      session: session,
      itemID: ep.itemId,
      server: ep.server ?? resolvedServer,
      title: title,
      artworkURL: artwork,
      queue: queue,
      queueIndex: index
    ) {
      feedbackMessage = (err, true)
    }
  }

  /// 打开当前媒体库作品的订阅文件详情弹窗。
  private func openSubscribeFiles(
    _ detail: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)
  ) {
    let season = resolveCancelSeason(detail, external: external)
    let key = external.type == "电视剧" ? (season ?? -1) : -1
    let knownID = subscribedRecordIDs[key] ?? subscribedRecordIDs[-1]
    let baseTitle = detail.seriesName ?? detail.title
    let displayTitle =
      if let season, external.type == "电视剧" {
        "\(baseTitle) S\(String(format: "%02d", season))"
      } else {
        baseTitle
      }
    activeFilesTarget = NativeSubscribeFilesTarget(
      subscribeID: knownID,
      mediaLookup: NativeSubscribeMediaLookup(
        mediaSource: external.source,
        mediaID: external.mediaID,
        type: external.type,
        season: external.type == "电视剧" ? season : nil,
        title: baseTitle,
        year: detail.yearText
      ),
      fallbackTitle: displayTitle
    )
  }

  private func performSubscribe(
    _ detail: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)
  ) async {
    isSubscribing = true
    defer { isSubscribing = false }
    struct SubscribeBody: Encodable {
      let name: String
      let type: String
      let year: String
      let mediaSource: String
      let mediaID: String
      let season: Int?

      private enum CodingKeys: String, CodingKey {
        case name, type, year, season
        case mediaSource = "media_source"
        case mediaID = "media_id"
      }
    }
    struct SubscribeCreatedPayload: Decodable, Sendable {
      let id: Int?
    }
    do {
      let targetSeason =
        external.type == "电视剧" ? (detail.seasonNumber ?? selectedSeasonNumber ?? 1) : nil
      let body = try JSONEncoder().encode(
        SubscribeBody(
          name: detail.seriesName ?? detail.title,
          type: external.type,
          year: detail.yearText ?? "",
          mediaSource: external.source,
          mediaID: external.mediaID,
          season: targetSeason
        )
      )
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      let created = try await session.request(
        endpoint, as: SubscribeCreatedPayload?.self, requiring: .init(category: .subscribe)
      ).value
      if let createdID = created?.id, createdID > 0 {
        subscribedRecordIDs[targetSeason ?? -1] = createdID
      }

      isSubscribed = true
      if let targetSeason {
        subscribedSeasons.insert(targetSeason)
      }
      NativePageDataCache.shared.remove("subscriptions|list", session: session)

      if let snapshot = await fetchSubscriptionSnapshot(detail, external: external) {
        isSubscribed = true
        subscribedSeasons.formUnion(snapshot.seasons)
        if let targetSeason {
          subscribedSeasons.insert(targetSeason)
        }
      }
      feedbackMessage = ("已成功添加订阅。", false)
    } catch {
      feedbackMessage = ("添加订阅失败，可能已存在或暂无权限。", true)
    }
  }

  private func performUnsubscribe(_ target: MediaServerCancelSubscribeTarget) async {
    guard canSubscribe else { return }
    isSubscribing = true
    defer { isSubscribing = false }
    do {
      var query = [URLQueryItem(name: "media_source", value: target.source)]
      if let season = target.season, target.type == "电视剧" {
        query.append(URLQueryItem(name: "season", value: String(season)))
      }
      let endpoint = try APIEndpoint(
        path: ["subscribe", "media", target.mediaID],
        method: .delete,
        query: query
      )
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      if let season = target.season {
        subscribedSeasons.remove(season)
        subscribedRecordIDs.removeValue(forKey: season)
        isSubscribed = !subscribedSeasons.isEmpty
      } else {
        subscribedSeasons.removeAll()
        subscribedRecordIDs.removeAll()
        isSubscribed = false
      }
      NativePageDataCache.shared.remove("subscriptions|list", session: session)

      if let detail, let ext = effectiveExternalIdentity,
        let snapshot = await fetchSubscriptionSnapshot(detail, external: ext)
      {
        if let season = target.season {
          var remaining = snapshot.seasons
          remaining.remove(season)
          subscribedSeasons = remaining
          isSubscribed = !remaining.isEmpty
        } else {
          subscribedSeasons.removeAll()
          isSubscribed = false
        }
      }
      feedbackMessage = (
        target.season.map { "已取消第 \($0) 季订阅。" } ?? "已取消订阅。",
        false
      )
    } catch {
      feedbackMessage = ("取消订阅失败，请稍后重试。", true)
    }
  }

  /// 查询当前作品在 MoviePilot 中的订阅与分季状态，附带 `GET /api/v1/subscribe/media/{id}` 跨源投影兜底。
  private func loadSubscriptionStatus(
    _ loaded: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)
  ) async {
    guard let snapshot = await fetchSubscriptionSnapshot(loaded, external: external) else { return }
    isSubscribed = snapshot.subscribed
    subscribedSeasons = snapshot.seasons
  }

  private func fetchSubscriptionSnapshot(
    _ loaded: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)
  ) async -> (subscribed: Bool, seasons: Set<Int>)? {
    struct StatusQueryItem: Encodable {
      let mediaSource: String
      let mediaID: String
      let mtype: String
      let title: String?
      let year: String?

      private enum CodingKeys: String, CodingKey {
        case mtype, title, year
        case mediaSource = "media_source"
        case mediaID = "media_id"
      }
    }
    struct StatusResponseItem: Decodable, Sendable {
      let subscribed: Bool
      let seasons: [Int: String]

      private enum CodingKeys: String, CodingKey {
        case subscribed, seasons
      }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscribed = try container.decodeIfPresent(Bool.self, forKey: .subscribed) ?? false
        let rawSeasons =
          try container.decodeIfPresent([String: String].self, forKey: .seasons) ?? [:]
        var parsed: [Int: String] = [:]
        for (key, value) in rawSeasons {
          if let number = Int(key) { parsed[number] = value }
        }
        seasons = parsed
      }
    }
    struct IdentityProbe: Decodable, Sendable {
      let id: Int?
      let season: Int?
    }

    let queryTitle = loaded.seriesName ?? loaded.title
    let queryYear = loaded.yearText ?? parentSeriesDetail?.yearText
    let payload = [
      StatusQueryItem(
        mediaSource: external.source,
        mediaID: external.mediaID,
        mtype: external.type,
        title: queryTitle,
        year: queryYear
      )
    ]
    var subscribedFlag = false
    var seasonSet: Set<Int> = []
    if let body = try? JSONEncoder().encode(payload),
      let endpoint = try? APIEndpoint(path: ["media", "status"], method: .post, body: body),
      let snapshot = try? await session.request(
        endpoint, as: [StatusResponseItem].self, requiring: .init(category: .discovery)
      ).value.first
    {
      subscribedFlag = snapshot.subscribed
      seasonSet = Set(snapshot.seasons.keys)
    }

    let isTV = external.type == "电视剧"
    if canSubscribe && (!subscribedFlag || (isTV && seasonSet.isEmpty)) {
      var probeQuery: [URLQueryItem] = [
        URLQueryItem(name: "media_source", value: external.source),
        URLQueryItem(name: "mtype", value: external.type),
      ]
      if !queryTitle.isEmpty {
        probeQuery.append(URLQueryItem(name: "title", value: queryTitle))
      }
      if let queryYear, !queryYear.isEmpty {
        probeQuery.append(URLQueryItem(name: "year", value: queryYear))
      }
      if let endpoint = try? APIEndpoint(
        path: ["subscribe", "media", external.mediaID], query: probeQuery),
        let probe = try? await session.request(
          endpoint, as: IdentityProbe.self, requiring: .init(category: .subscribe)
        ).value,
        let probeID = probe.id, probeID > 0
      {
        subscribedFlag = true
        if isTV, let s = probe.season {
          seasonSet.insert(s)
          subscribedRecordIDs[s] = probeID
        } else {
          subscribedRecordIDs[-1] = probeID
        }
      }
    }
    return (subscribedFlag, seasonSet)
  }

  // MARK: - Data Loading

  private func loadAll() async {
    isLoading = true
    loadFailed = false
    fetchedLogo = nil
    parentSeriesDetail = nil
    enrichedIDs = MediaServerEnrichedIDs()
    similarItems = []
    sampleEpisodeSource = nil
    var query = [URLQueryItem(name: "itemid", value: itemID)]
    if let server, !server.isEmpty {
      query.append(URLQueryItem(name: "server", value: server))
    }
    do {
      let endpoint = try APIEndpoint(path: ["mediaserver", "detail"], query: query)
      let loaded = try await session.request(
        endpoint, as: MediaServerItemDetailDTO.self, requiring: .init(category: .discovery)
      ).value
      detail = loaded
      enrichedIDs = MediaServerEnrichedIDs(
        doubanID: Self.cleanExternalID(loaded.doubanId),
        imdbID: Self.cleanExternalID(loaded.imdbId),
        tmdbID: Self.cleanExternalID(loaded.tmdbId),
        tvdbID: Self.cleanExternalID(loaded.tvdbId),
        bangumiID: nil
      )
      let preferZh =
        UserDefaults.standard.object(forKey: "nativeV2.playback.preferChineseSub") as? Bool ?? true
      if let firstSource = loaded.mediaSources.first {
        selectedSourceID = firstSource.id
        trackSelection = MediaPlaybackTrackSelection.defaultSelection(
          for: firstSource, preferChineseSub: preferZh)
      }
      isLoading = false

      if loaded.kind == .season || loaded.kind == .episode,
        let seriesID = loaded.seriesId, !seriesID.isEmpty,
        loaded.resolvedExternalIdentity == nil
      {
        var seriesQuery = [URLQueryItem(name: "itemid", value: seriesID)]
        if let srv = loaded.server ?? server, !srv.isEmpty {
          seriesQuery.append(URLQueryItem(name: "server", value: srv))
        }
        if let seriesEP = try? APIEndpoint(path: ["mediaserver", "detail"], query: seriesQuery),
          let loadedSeries = try? await session.request(
            seriesEP, as: MediaServerItemDetailDTO.self, requiring: .init(category: .discovery)
          ).value
        {
          parentSeriesDetail = loadedSeries
          enrichedIDs.merge(from: loadedSeries)
        }
      }

      let resolvedExt =
        loaded.resolvedExternalIdentity ?? parentSeriesDetail?.resolvedExternalIdentity
      async let childrenTask: Void = loadHierarchyChildren(for: loaded)
      async let subStatusTask: Void = {
        if let ext = resolvedExt {
          await loadSubscriptionStatus(loaded, external: ext)
        }
      }()
      async let logoAndIDsTask: Void = loadLogoAndExternalMetadata(
        for: loaded, external: resolvedExt)
      async let similarTask: Void = loadSimilarWorks(for: loaded, external: resolvedExt)
      _ = await (childrenTask, subStatusTask, logoAndIDsTask, similarTask)
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
      isLoading = false
    }
  }

  /// 拉取透明标题 Logo 并补齐外部站点编号（豆瓣 / IMDb / TMDB / TVDB / Bangumi），即使媒体服务器仅存储了单一编号也能展示完整链接。
  private func loadLogoAndExternalMetadata(
    for loaded: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)?
  ) async {
    if let direct = loaded.logo?.trimmingCharacters(in: .whitespacesAndNewlines), !direct.isEmpty {
      fetchedLogo = MediaServerLogoCacheEntry(
        url: direct, logoLanguage: loaded.logoLanguage, originalLanguage: nil)
    }
    guard let ext = external else { return }
    struct ExternalMediaProbe: Decodable, Sendable {
      let logoPath: String?
      let logoLanguage: String?
      let originalLanguage: String?
      let doubanID: String?
      let imdbID: String?
      let tmdbID: String?
      let tvdbID: String?
      let bangumiID: String?

      private enum CodingKeys: String, CodingKey {
        case logoPath = "logo_path"
        case logoLanguage = "logo_language"
        case originalLanguage = "original_language"
        case doubanID = "douban_id"
        case imdbID = "imdb_id"
        case tmdbID = "tmdb_id"
        case tvdbID = "tvdb_id"
        case bangumiID = "bangumi_id"
      }

      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logoPath = try? c.decodeIfPresent(String.self, forKey: .logoPath)
        logoLanguage = try? c.decodeIfPresent(String.self, forKey: .logoLanguage)
        originalLanguage = try? c.decodeIfPresent(String.self, forKey: .originalLanguage)
        doubanID = try? c.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .doubanID)?.value
        imdbID = try? c.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .imdbID)?.value
        tmdbID = try? c.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .tmdbID)?.value
        tvdbID = try? c.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .tvdbID)?.value
        bangumiID =
          try? c.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .bangumiID)?.value
      }
    }

    guard
      let endpoint = try? APIEndpoint(
        path: ["media", ext.mediaID],
        query: [
          URLQueryItem(name: "media_source", value: ext.source),
          URLQueryItem(name: "type_name", value: ext.type),
        ]),
      let probe = try? await session.request(
        endpoint, as: ExternalMediaProbe.self, requiring: .init(category: .discovery)
      ).value
    else { return }

    if let v = Self.cleanExternalID(probe.doubanID), enrichedIDs.doubanID == nil {
      enrichedIDs.doubanID = v
    }
    if let v = Self.cleanExternalID(probe.imdbID), enrichedIDs.imdbID == nil {
      enrichedIDs.imdbID = v
    }
    if let v = Self.cleanExternalID(probe.tmdbID), enrichedIDs.tmdbID == nil {
      enrichedIDs.tmdbID = v
    }
    if let v = Self.cleanExternalID(probe.tvdbID), enrichedIDs.tvdbID == nil {
      enrichedIDs.tvdbID = v
    }
    if let v = Self.cleanExternalID(probe.bangumiID), enrichedIDs.bangumiID == nil {
      enrichedIDs.bangumiID = v
    }

    if fetchedLogo == nil {
      let cacheKey =
        "\(session.scope.instanceID.uuidString)|\(ext.source)|\(ext.mediaID)|\(ext.type)"
      if let cached = Self.mediaLogoCache[cacheKey] {
        fetchedLogo = cached
      } else if let resolved = NativeMediaDetailPage.resolveArtwork(
        probe.logoPath, source: ext.source, tmdbSize: "w500"),
        !resolved.isEmpty
      {
        let entry = MediaServerLogoCacheEntry(
          url: resolved,
          logoLanguage: probe.logoLanguage,
          originalLanguage: probe.originalLanguage
        )
        Self.mediaLogoCache[cacheKey] = entry
        fetchedLogo = entry
      }
    }
  }

  /// 加载类似作品：优先按外部身份请求相似/推荐列表，缺省时按首个类型标签回退同媒体库高分作品。
  private func loadSimilarWorks(
    for loaded: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)?
  ) async {
    guard loaded.kind == .movie || loaded.kind.isTelevisionHierarchy else { return }
    if let ext = external {
      var candidateEndpoints: [APIEndpoint] = []
      let normalizedType = ext.type
      switch ext.source.lowercased() {
      case "themoviedb", "tmdb":
        if let sim = try? APIEndpoint(
          path: ["tmdb", "similar", ext.mediaID, normalizedType],
          query: [URLQueryItem(name: "page", value: "1")])
        {
          candidateEndpoints.append(sim)
        }
        if let rec = try? APIEndpoint(
          path: ["tmdb", "recommend", ext.mediaID, normalizedType],
          query: [URLQueryItem(name: "page", value: "1")])
        {
          candidateEndpoints.append(rec)
        }
      case "douban":
        if let rec = try? APIEndpoint(
          path: ["douban", "recommend", ext.mediaID, normalizedType],
          query: [URLQueryItem(name: "page", value: "1")])
        {
          candidateEndpoints.append(rec)
        }
      case "bangumi":
        if let rec = try? APIEndpoint(
          path: ["bangumi", "recommend", ext.mediaID],
          query: [URLQueryItem(name: "page", value: "1")])
        {
          candidateEndpoints.append(rec)
        }
      case "anilist":
        if let rec = try? APIEndpoint(
          path: ["anilist", "recommend", ext.mediaID],
          query: [URLQueryItem(name: "page", value: "1")])
        {
          candidateEndpoints.append(rec)
        }
      default:
        break
      }

      for endpoint in candidateEndpoints {
        if let list = try? await session.request(
          endpoint, as: [MediaSummaryItem].self, requiring: .init(category: .discovery)
        ).value, !list.isEmpty {
          let cards: [MediaServerSimilarCardItem] = list.compactMap { item in
            guard let title = item.title, !title.isEmpty else { return nil }
            let resolved = item.resolvedIdentity(fallbackSource: ext.source)
            let poster = NativeMediaDetailPage.resolveArtwork(
              item.posterPath,
              source: resolved?.source ?? item.mediaSource ?? ext.source
            )
            let dest: MediaServerSimilarCardItem.Destination =
              if let resolved {
                .externalMedia(
                  NativeMediaIdentity(
                    source: resolved.source, mediaID: resolved.mediaID, type: resolved.type))
              } else {
                .none
              }
            return MediaServerSimilarCardItem(
              id: resolved.map { "\($0.source)|\($0.mediaID)" } ?? item.id,
              title: title,
              year: item.year,
              rating: item.voteAverage,
              poster: poster,
              destination: dest
            )
          }
          if !cards.isEmpty {
            similarItems = cards
            return
          }
        }
      }
    }

    // 媒体库同流派高分回退
    let genres = loaded.genres.isEmpty ? (parentSeriesDetail?.genres ?? []) : loaded.genres
    guard let primaryGenre = genres.first,
      let srv = loaded.server ?? server, !srv.isEmpty,
      let browseEP = try? APIEndpoint(
        path: ["mediaserver", "browse"],
        query: [
          URLQueryItem(name: "server", value: srv),
          URLQueryItem(name: "genre", value: primaryGenre),
          URLQueryItem(name: "sort_by", value: "rating"),
          URLQueryItem(name: "sort_order", value: "desc"),
          URLQueryItem(name: "limit", value: "18"),
        ]),
      let page = try? await session.request(
        browseEP, as: MediaServerBrowsePageDTO.self, requiring: .init(category: .discovery)
      ).value
    else { return }

    let excludedIDs: Set<String> = Set([loaded.itemId, loaded.seriesId].compactMap { $0 })
    similarItems = page.items
      .filter { !excludedIDs.contains($0.itemId) }
      .map { child in
        MediaServerSimilarCardItem(
          id: "ms|\(child.id)",
          title: child.title,
          year: child.yearText,
          rating: child.rating,
          poster: child.poster ?? child.thumb ?? child.backdrop,
          destination: .libraryItem(
            server: child.server ?? srv,
            itemID: child.itemId,
            itemType: child.itemType
          )
        )
      }
  }

  /// 当剧集/分季容器自身无 `mediaSources` 时，静默拉取首集/待看集的详情以展示完整 `媒体信息`。
  private func loadSampleEpisodeMediaSourceIfNeeded(
    parentDetail: MediaServerItemDetailDTO,
    episodeList: [MediaServerBrowseItemDTO]
  ) async {
    guard parentDetail.mediaSources.isEmpty, !episodeList.isEmpty else { return }
    let targetIdx = nextPlayableEpisodeIndex() ?? 0
    guard episodeList.indices.contains(targetIdx) else { return }
    let sampleEp = episodeList[targetIdx]
    var query = [URLQueryItem(name: "itemid", value: sampleEp.itemId)]
    if let srv = sampleEp.server ?? resolvedServer, !srv.isEmpty {
      query.append(URLQueryItem(name: "server", value: srv))
    }
    guard let epEndpoint = try? APIEndpoint(path: ["mediaserver", "detail"], query: query),
      let epDetail = try? await session.request(
        epEndpoint, as: MediaServerItemDetailDTO.self, requiring: .init(category: .discovery)
      ).value,
      let firstSource = epDetail.mediaSources.first
    else { return }
    sampleEpisodeSource = firstSource
    let preferZh =
      UserDefaults.standard.object(forKey: "nativeV2.playback.preferChineseSub") as? Bool ?? true
    trackSelection = MediaPlaybackTrackSelection.defaultSelection(
      for: firstSource, preferChineseSub: preferZh)
  }

  private func loadHierarchyChildren(for loaded: MediaServerItemDetailDTO) async {
    guard let srv = loaded.server ?? server, !srv.isEmpty else { return }
    switch loaded.kind {
    case .series:
      if let endpoint = try? APIEndpoint(
        path: ["mediaserver", "seasons"],
        query: [
          URLQueryItem(name: "itemid", value: loaded.itemId),
          URLQueryItem(name: "server", value: srv),
        ]
      ),
        let seasonList = try? await session.request(
          endpoint, as: [MediaServerBrowseItemDTO].self, requiring: .init(category: .discovery)
        ).value
      {
        seasons = seasonList
        let defaultSeason =
          seasonList.first(where: { ($0.seasonNumber ?? 0) >= 1 }) ?? seasonList.first
        if let defaultSeason {
          selectedSeasonNumber = defaultSeason.seasonNumber
          await loadEpisodesForSeason(seriesID: loaded.itemId, season: defaultSeason)
        }
      }

    case .season:
      let targetSeriesID = loaded.seriesId ?? loaded.parentId ?? loaded.itemId
      var query = [
        URLQueryItem(name: "itemid", value: targetSeriesID),
        URLQueryItem(name: "server", value: srv),
        URLQueryItem(name: "season_id", value: loaded.itemId),
      ]
      if let seasonNum = loaded.seasonNumber {
        query.append(URLQueryItem(name: "season", value: String(seasonNum)))
      }
      if let endpoint = try? APIEndpoint(path: ["mediaserver", "season-episodes"], query: query),
        let epList = try? await session.request(
          endpoint, as: [MediaServerBrowseItemDTO].self, requiring: .init(category: .discovery)
        ).value
      {
        episodes = epList
        await loadSampleEpisodeMediaSourceIfNeeded(parentDetail: loaded, episodeList: epList)
      }

    case .episode:
      guard let seriesID = loaded.seriesId, !seriesID.isEmpty else { return }
      var query = [
        URLQueryItem(name: "itemid", value: seriesID),
        URLQueryItem(name: "server", value: srv),
      ]
      if let seasonID = loaded.seasonId, !seasonID.isEmpty {
        query.append(URLQueryItem(name: "season_id", value: seasonID))
      } else if let seasonNum = loaded.seasonNumber {
        query.append(URLQueryItem(name: "season", value: String(seasonNum)))
      }
      if let endpoint = try? APIEndpoint(path: ["mediaserver", "season-episodes"], query: query),
        let epList = try? await session.request(
          endpoint, as: [MediaServerBrowseItemDTO].self, requiring: .init(category: .discovery)
        ).value
      {
        episodes = epList
        await loadSampleEpisodeMediaSourceIfNeeded(parentDetail: loaded, episodeList: epList)
      }

    case .musicAlbum:
      if let endpoint = try? APIEndpoint(
        path: ["mediaserver", "season-episodes"],
        query: [
          URLQueryItem(name: "itemid", value: loaded.itemId),
          URLQueryItem(name: "server", value: srv),
        ]
      ),
        let tracks = try? await session.request(
          endpoint, as: [MediaServerBrowseItemDTO].self, requiring: .init(category: .discovery)
        ).value
      {
        episodes = tracks
      }

    case .boxSet:
      if let endpoint = try? APIEndpoint(
        path: ["mediaserver", "browse"],
        query: [
          URLQueryItem(name: "server", value: srv),
          URLQueryItem(name: "parent_id", value: loaded.itemId),
          URLQueryItem(name: "limit", value: "100"),
        ]
      ),
        let page = try? await session.request(
          endpoint, as: MediaServerBrowsePageDTO.self, requiring: .init(category: .discovery)
        ).value
      {
        collectionItems = page.items
      }

    default:
      break
    }
  }

  private func loadEpisodesForSeason(seriesID: String, season: MediaServerBrowseItemDTO) async {
    guard let srv = resolvedServer, !srv.isEmpty else { return }
    var query = [
      URLQueryItem(name: "itemid", value: seriesID),
      URLQueryItem(name: "server", value: srv),
      URLQueryItem(name: "season_id", value: season.itemId),
    ]
    if let seasonNum = season.seasonNumber {
      query.append(URLQueryItem(name: "season", value: String(seasonNum)))
    }
    if let endpoint = try? APIEndpoint(path: ["mediaserver", "season-episodes"], query: query),
      let epList = try? await session.request(
        endpoint, as: [MediaServerBrowseItemDTO].self, requiring: .init(category: .discovery)
      ).value
    {
      episodes = epList
      if let detail {
        await loadSampleEpisodeMediaSourceIfNeeded(parentDetail: detail, episodeList: epList)
      }
    }
  }
}

/// 媒体库详情页聚合的多来源外部编号。
private struct MediaServerEnrichedIDs: Sendable {
  var doubanID: String?
  var imdbID: String?
  var tmdbID: String?
  var tvdbID: String?
  var bangumiID: String?

  mutating func merge(from other: MediaServerItemDetailDTO) {
    if doubanID == nil, let v = other.doubanId, !v.isEmpty, v != "0" { doubanID = v }
    if imdbID == nil, let v = other.imdbId, !v.isEmpty, v != "0" { imdbID = v }
    if tmdbID == nil, let v = other.tmdbId, !v.isEmpty, v != "0" { tmdbID = v }
    if tvdbID == nil, let v = other.tvdbId, !v.isEmpty, v != "0" { tvdbID = v }
  }
}

/// 媒体库详情页「类似作品」卡片数据。
private struct MediaServerSimilarCardItem: Identifiable, Sendable {
  enum Destination: Sendable {
    case externalMedia(NativeMediaIdentity)
    case libraryItem(server: String?, itemID: String, itemType: String)
    case none
  }

  let id: String
  let title: String
  let year: String?
  let rating: Double?
  let poster: String?
  let destination: Destination
}

/// 媒体库详情页「链接」胶囊项。
private struct MediaServerExternalLinkChip: Identifiable, Sendable {
  let id: String
  let title: String
  let url: URL
}

/// 待确认取消订阅的目标参数。
private struct MediaServerCancelSubscribeTarget: Identifiable {
  let id = UUID()
  let source: String
  let mediaID: String
  let type: String
  let season: Int?
  let message: String
}

private struct MediaServerDetailScrollOffsetKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct MediaServerDetailScrollClipping: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 17, *) {
      content.scrollClipDisabled()
    } else {
      content
    }
  }
}

/// iOS 18+ 原生滚动偏移观察器（用于详情页 Hero 视差、模糊与标题渐显）。
private struct MediaServerDetailScrollObservation: ViewModifier {
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
      content.onPreferenceChange(MediaServerDetailScrollOffsetKey.self) { raw in
        let clamped = max(min(raw, 240), -720)
        if abs(offset - clamped) >= 0.5 { offset = clamped }
      }
    }
  }
}

private struct MediaServerDetailLegacyScrollProbe: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      content
    } else {
      content.background(alignment: .top) {
        GeometryReader { proxy in
          Color.clear.preference(
            key: MediaServerDetailScrollOffsetKey.self,
            value: proxy.frame(in: .named("native-mediaserver-detail-scroll")).minY
          )
        }
        .frame(height: 0)
      }
    }
  }
}

/// 媒体服务器详情页专属占位骨架布局：按 `fallbackItemType` 1:1 匹配电影/剧集/季/集/合集/音乐专辑的头图信息区、双行或紧凑单行操作栏、播前轨道选择器、16:9 横版分集剧照、简介、演职员、类似作品、外部链接、媒体流信息与元数据面板。
@MainActor
struct NativeMediaServerDetailSkeletonView: View {
  let heroHeight: CGFloat
  let viewportWidth: CGFloat
  let horizontalMargin: CGFloat
  let isWide: Bool
  let isCompactLandscape: Bool
  let fallbackTitle: String?
  let fallbackItemType: String?
  let canSubscribe: Bool
  let canSearchResources: Bool

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var kind: MediaServerItemKind {
    let parsed = MediaServerItemKind(rawItemType: fallbackItemType)
    if case .other(let raw) = parsed, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .movie
    }
    return parsed
  }

  var body: some View {
    let isLight = colorScheme == .light
    let useSingleActionRow = isCompactLandscape && !dynamicTypeSize.isAccessibilitySize
    let supportsExternalActions =
      (kind == .movie || kind.isTelevisionHierarchy) && (canSubscribe || canSearchResources)

    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .center, spacing: isCompactLandscape ? 5 : 10) {
        Spacer(minLength: isCompactLandscape ? 44 : 0)

        if let fallbackTitle,
          !fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          NativeHeroPosterTitleView(
            title: fallbackTitle,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isWide: isWide,
            isCompactLandscape: isCompactLandscape,
            textAlignment: .center,
            color: isLight ? Color.primary : Color.white
          )
        } else {
          NativeSkeletonBlock(
            width: isCompactLandscape ? 180 : 220,
            height: isCompactLandscape ? 32 : 46,
            cornerRadius: 10
          )
        }

        NativeSkeletonBlock(width: 176, height: 14, cornerRadius: 6)

        HStack(spacing: 6) {
          NativeSkeletonBlock(width: 44, height: 20, cornerRadius: 10)
          NativeSkeletonBlock(width: 58, height: 20, cornerRadius: 10)
        }

        HStack(spacing: 6) {
          ForEach(0..<3, id: \.self) { _ in
            NativeSkeletonBlock(width: 48, height: 20, cornerRadius: 10)
          }
        }
      }
      .padding(.horizontal, horizontalMargin)
      .padding(.bottom, isCompactLandscape ? 8 : 16)
      .frame(maxWidth: 1020, minHeight: heroHeight, alignment: .bottom)
      .frame(maxWidth: .infinity)

      VStack(alignment: .leading, spacing: isCompactLandscape ? 16 : 22) {
        if kind == .season || kind == .episode {
          HStack(spacing: 8) {
            NativeSkeletonBlock(width: 96, height: 28, cornerRadius: 14)
            if kind == .episode {
              NativeSkeletonBlock(width: 8, height: 12, cornerRadius: 4)
              NativeSkeletonBlock(width: 78, height: 28, cornerRadius: 14)
            }
          }
        }

        if useSingleActionRow {
          HStack(spacing: 10) {
            NativeSkeletonBlock(height: 48, cornerRadius: 24)
            if supportsExternalActions {
              if canSubscribe {
                NativeSkeletonBlock(height: 48, cornerRadius: 24)
              }
              if canSearchResources {
                NativeSkeletonBlock(height: 48, cornerRadius: 24)
              }
            }
            NativeSkeletonBlock(width: 48, height: 48, cornerRadius: 24)
          }
        } else {
          VStack(spacing: 10) {
            HStack(spacing: 10) {
              NativeSkeletonBlock(height: 48, cornerRadius: 24)
              NativeSkeletonBlock(width: 48, height: 48, cornerRadius: 24)
            }
            if supportsExternalActions {
              HStack(spacing: 10) {
                if canSubscribe {
                  NativeSkeletonBlock(height: 46, cornerRadius: 23)
                }
                if canSearchResources {
                  NativeSkeletonBlock(height: 46, cornerRadius: 23)
                }
              }
            }
          }
        }

        if kind.isDirectlyPlayable {
          prePlaySelectorSkeleton
        }

        middleKindSection

        CinematicPanel(padding: 18) {
          VStack(alignment: .leading, spacing: 8) {
            Text("剧情简介")
              .font(.headline)
            NativeSkeletonBlock(height: 13, cornerRadius: 5)
            NativeSkeletonBlock(height: 13, cornerRadius: 5)
            NativeSkeletonBlock(width: 210, height: 13, cornerRadius: 5)
          }
        }

        if kind != .audio {
          castSectionSkeleton
        }

        if kind == .movie || kind == .series {
          similarWorksSkeleton
        }

        externalLinksSkeleton

        if kind != .boxSet && kind != .folder {
          mediaStreamsSkeleton
        }

        metadataCardSkeleton
      }
      .frame(maxWidth: 1020, alignment: .leading)
      .padding(.horizontal, horizontalMargin)
      .padding(.top, 8)
      .padding(.bottom, 40)
      .frame(maxWidth: .infinity)
    }
    .nativeSkeletonShimmer()
  }

  private var prePlaySelectorSkeleton: some View {
    let rowLabels = kind == .audio ? ["音频", "音轨"] : ["视频", "音轨", "字幕"]
    return CinematicPanel(padding: 0) {
      VStack(spacing: 0) {
        ForEach(Array(rowLabels.enumerated()), id: \.offset) { idx, label in
          if idx > 0 {
            Divider().overlay(.primary.opacity(0.10)).padding(.leading, 16)
          }
          HStack(spacing: 12) {
            Text(label)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.primary.opacity(0.76))
            Spacer(minLength: 12)
            NativeSkeletonBlock(width: idx == 0 ? 156 : 112, height: 14, cornerRadius: 5)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 13)
        }
      }
    }
  }

  @ViewBuilder
  private var middleKindSection: some View {
    switch kind {
    case .series:
      seasonsStripSkeleton
      landscapeEpisodesSkeleton
    case .season:
      landscapeEpisodesSkeleton
    case .episode:
      adjacentEpisodesSkeleton
    case .boxSet:
      let cols = NativeDeviceLayout.posterGridCount(
        for: min(max(viewportWidth, 320), 1020),
        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
      )
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("合集内容")
            .font(.title3.weight(.bold))
          Spacer()
          NativeSkeletonBlock(width: 48, height: 12, cornerRadius: 5)
        }
        NativePosterGridSkeletonView(
          columns: cols,
          count: cols * 2,
          cornerRadius: 12
        )
      }
    case .musicAlbum:
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("曲目列表")
            .font(.title3.weight(.bold))
          Spacer()
          NativeSkeletonBlock(width: 48, height: 12, cornerRadius: 5)
        }
        NativeCardListSkeletonView(count: 6, style: .trackList)
      }
    default:
      EmptyView()
    }
  }

  private var seasonsStripSkeleton: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("分季")
          .font(.title3.weight(.bold))
        Spacer()
        NativeSkeletonBlock(width: 48, height: 12, cornerRadius: 5)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(0..<4, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 6) {
              NativeSkeletonBlock(width: 112, height: 168, cornerRadius: 12)
              NativeSkeletonBlock(width: 72, height: 12, cornerRadius: 5)
              NativeSkeletonBlock(width: 38, height: 10, cornerRadius: 4)
            }
            .frame(width: 112, alignment: .leading)
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  private var landscapeEpisodesSkeleton: some View {
    let cardWidth: CGFloat = isWide ? 252 : 224
    let thumbHeight: CGFloat = isWide ? 142 : 126
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("剧集列表")
          .font(.title3.weight(.bold))
        Spacer()
        NativeSkeletonBlock(width: 58, height: 22, cornerRadius: 11)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(0..<4, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 7) {
              NativeSkeletonBlock(width: cardWidth, height: thumbHeight, cornerRadius: 13)
              NativeSkeletonBlock(width: cardWidth * 0.64, height: 14, cornerRadius: 5)
              NativeSkeletonBlock(width: cardWidth * 0.90, height: 11, cornerRadius: 4)
              NativeSkeletonBlock(width: cardWidth * 0.70, height: 11, cornerRadius: 4)
            }
            .frame(width: cardWidth, alignment: .leading)
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  private var adjacentEpisodesSkeleton: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("本季更多剧集")
        .font(.headline)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 10) {
          ForEach(0..<5, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 5) {
              NativeSkeletonBlock(width: 146, height: 82, cornerRadius: 10)
              NativeSkeletonBlock(width: 110, height: 12, cornerRadius: 5)
            }
            .frame(width: 146, alignment: .leading)
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  private var castSectionSkeleton: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("演职员")
        .font(.title3.weight(.bold))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 14) {
          ForEach(0..<8, id: \.self) { _ in
            VStack(spacing: 6) {
              NativeSkeletonBlock(width: 68, height: 68, cornerRadius: 34)
              NativeSkeletonBlock(width: 54, height: 11, cornerRadius: 5)
              NativeSkeletonBlock(width: 40, height: 10, cornerRadius: 4)
            }
            .frame(width: 76)
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  private var similarWorksSkeleton: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("类似作品")
        .font(.title3.weight(.bold))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(0..<7, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 6) {
              NativeSkeletonBlock(width: 114, height: 171, cornerRadius: 13)
              NativeSkeletonBlock(width: 84, height: 12, cornerRadius: 5)
              NativeSkeletonBlock(width: 42, height: 10, cornerRadius: 4)
            }
            .frame(width: 114, alignment: .leading)
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  private var externalLinksSkeleton: some View {
    let widths: [CGFloat] = [74, 78, 108, 82]
    return VStack(alignment: .leading, spacing: 12) {
      Text("链接")
        .font(.title3.weight(.bold))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
            NativeSkeletonBlock(width: width, height: 35, cornerRadius: 17.5)
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  private var mediaStreamsSkeleton: some View {
    let cards: [(symbol: String, title: String)] = [
      ("video", "视频"),
      ("speaker.wave.2", "音频"),
      ("captions.bubble", "字幕"),
    ]
    let isLight = colorScheme == .light
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("媒体信息")
          .font(.title3.weight(.bold))
        Spacer()
        NativeSkeletonBlock(width: 84, height: 12, cornerRadius: 5)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(Array(cards.enumerated()), id: \.offset) { _, item in
            VStack(alignment: .leading, spacing: 10) {
              HStack(spacing: 8) {
                Image(systemName: item.symbol)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(.primary.opacity(0.75))
                Text(item.title)
                  .font(.callout.weight(.semibold))
                  .foregroundStyle(.primary)
                Spacer(minLength: 0)
              }
              .padding(.bottom, 2)

              VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4, id: \.self) { row in
                  HStack(spacing: 10) {
                    NativeSkeletonBlock(width: 44, height: 12, cornerRadius: 4)
                    NativeSkeletonBlock(width: row == 0 ? 128 : 96, height: 12, cornerRadius: 4)
                  }
                }
              }
            }
            .padding(16)
            .frame(width: 248, alignment: .topLeading)
            .background {
              shape
                .fill(isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.045))
                .overlay {
                  shape.strokeBorder(
                    isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.14),
                    lineWidth: 0.8
                  )
                }
            }
          }
        }
      }
      .allowsHitTesting(false)
    }
  }

  private var metadataCardSkeleton: some View {
    CinematicPanel(padding: 0) {
      VStack(spacing: 0) {
        ForEach(0..<4, id: \.self) { idx in
          if idx > 0 {
            Divider().overlay(.primary.opacity(0.10)).padding(.leading, 16)
          }
          HStack(spacing: 12) {
            NativeSkeletonBlock(width: 68, height: 14, cornerRadius: 5)
            Spacer(minLength: 12)
            NativeSkeletonBlock(width: idx == 0 ? 132 : 96, height: 14, cornerRadius: 5)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 11)
        }
      }
    }
  }
}
