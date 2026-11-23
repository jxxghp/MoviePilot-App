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
  @State private var fetchedLogo: MediaServerLogoCacheEntry?
  @State private var seasons: [MediaServerBrowseItemDTO] = []
  @State private var episodes: [MediaServerBrowseItemDTO] = []
  @State private var collectionItems: [MediaServerBrowseItemDTO] = []
  @State private var selectedSeasonNumber: Int?
  @State private var selectedSourceID: String?
  @State private var trackSelection = MediaPlaybackTrackSelection()

  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isLaunchingPlayback = false
  @State private var isSubscribing = false
  @State private var isSubscribed = false
  @State private var subscribedSeasons: Set<Int> = []
  @State private var pendingCancelSubscribe: MediaServerCancelSubscribeTarget?
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

  private var activeMediaSource: MediaServerSourceDTO? {
    guard let sources = detail?.mediaSources, !sources.isEmpty else { return nil }
    if let selectedSourceID, let matched = sources.first(where: { $0.id == selectedSourceID }) {
      return matched
    }
    return sources.first
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
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if let detail {
              heroHeaderOverlay(detail, height: heroHeight, margin: margin, isWide: isWide)
                .frame(maxWidth: 1020, alignment: .center)
                .frame(maxWidth: .infinity)

              VStack(alignment: .leading, spacing: 22) {
                if let feedbackMessage {
                  feedbackBanner(feedbackMessage.text, isError: feedbackMessage.isError)
                }

                if detail.kind == .season || detail.kind == .episode {
                  hierarchyBreadcrumb(detail)
                }

                actionBar(detail)

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
                  episodesSection(detail)
                }

                if detail.kind == .episode, !episodes.isEmpty {
                  adjacentEpisodesStrip(detail)
                }

                synopsisSection(detail)

                if !detail.people.isEmpty {
                  castSection(detail.people)
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
              NativeMediaDetailSkeletonView(heroHeight: heroHeight)
            }
          }
          .frame(maxWidth: .infinity)
          .modifier(MediaServerDetailLegacyScrollProbe())
        }
        .coordinateSpace(name: "native-mediaserver-detail-scroll")
        .scrollIndicators(.hidden)
        .refreshable { await loadAll() }
        .modifier(MediaServerDetailScrollClipping())
        .ignoresSafeArea(edges: .top)
        .modifier(MediaServerDetailScrollObservation(offset: $scrollOffset))
        .accessibilityIdentifier("native-mediaserver-detail-scroll")
      }
      .navigationTitle("")
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .task(id: "\(server ?? "")|\(itemID)") {
      await loadAll()
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
    isWide: Bool = false
  ) -> some View {
    let isLight = colorScheme == .light
    let titleText = heroDisplayTitle(detail)
    let directLogo = detail.logo?.isEmpty == false ? detail.logo : nil
    let logoRef = directLogo ?? (fetchedLogo?.url.isEmpty == false ? fetchedLogo?.url : nil)
    let logoLanguage = directLogo != nil ? detail.logoLanguage : fetchedLogo?.logoLanguage
    let originalLanguage = fetchedLogo?.originalLanguage
    return VStack(alignment: .center, spacing: 10) {
      Spacer(minLength: 0)

      if let logoRef, !logoRef.isEmpty {
        NativeDiscoverLogoBanner(
          session: session,
          reference: logoRef,
          fallbackTitle: titleText,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          logoLanguage: logoLanguage,
          originalLanguage: originalLanguage,
          maxWidth: isWide ? 340 : 284,
          maxHeight: isWide ? 104 : 88,
          isWide: isWide,
          textAlignment: .center,
          fallbackColor: isLight ? Color.primary : Color.white
        )
        .accessibilityIdentifier("native-mediaserver-detail-title")
      } else {
        NativeHeroPosterTitleView(
          title: titleText,
          isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
          isWide: isWide,
          textAlignment: .center,
          color: isLight ? Color.primary : Color.white
        )
        .accessibilityIdentifier("native-mediaserver-detail-title")
      }

      let meta = metadataLineParts(detail)
      if !meta.isEmpty {
        Text(meta.joined(separator: " · "))
          .font(.subheadline.weight(.medium))
          .foregroundStyle(isLight ? Color.primary.opacity(0.82) : Color.white.opacity(0.86))
          .multilineTextAlignment(.center)
      }

      HStack(spacing: 6) {
        Text(dimensionBadgeTitle(detail))
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .padding(.vertical, 4)
          .background(appearance.accentColor.opacity(0.88), in: Capsule())

        if let serverName = resolvedServer, !serverName.isEmpty {
          Text(serverName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.84))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
              .padding(.vertical, 4)
              .background(.primary.opacity(0.10), in: Capsule())
          }
        }
      }
    }
    .padding(.horizontal, margin)
    .padding(.bottom, 16)
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

  private func actionBar(_ detail: MediaServerItemDetailDTO) -> some View {
    let hasPlayAction = canInitiatePlayback(detail)
    let subscribeTarget = detail.resolvedExternalIdentity
    let externalURL = detail.playUrl.flatMap(URL.init(string:))
    let hasOverflowActions = subscribeTarget != nil || externalURL != nil
    return VStack(spacing: 10) {
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

          if hasOverflowActions {
            overflowActionMenu(detail: detail, external: subscribeTarget, externalURL: externalURL)
          }
        }
      }

      if (canSubscribe && subscribeTarget != nil) || canSearchResources
        || (!hasPlayAction && hasOverflowActions)
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
                  Image(systemName: subscribedNow ? "bookmark.fill" : "plus")
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
              .frame(height: 46)
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
              .frame(height: 46)
              .background {
                Capsule()
                  .fill(.primary.opacity(colorScheme == .light ? 0.08 : 0.13))
                  .overlay { Capsule().strokeBorder(.primary.opacity(0.20), lineWidth: 0.7) }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-mediaserver-detail-search")
          }

          if !hasPlayAction && hasOverflowActions {
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
    if let ext = detail.resolvedExternalIdentity {
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
    let count =
      width > 0
      ? NativeDeviceLayout.posterGridCount(
        for: min(width, 1020), isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
      : (horizontalSizeClass == .regular ? 5 : 3)
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
              NativeMediaArtwork(
                session: session,
                reference: child.poster ?? child.thumb ?? child.backdrop,
                role: .poster,
                maximumWidth: 320
              )
              .frame(maxWidth: .infinity)
              .aspectRatio(2.0 / 3.0, contentMode: .fill)
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

  // MARK: - Episodes Section (Series Quick View / Season Full List / Music Album Tracks)

  private func episodesSection(_ detail: MediaServerItemDetailDTO) -> some View {
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

      VStack(spacing: 10) {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, ep in
          episodeRowCard(ep, index: index, parentDetail: detail)
        }
      }
    }
  }

  private func episodeRowCard(
    _ ep: MediaServerBrowseItemDTO, index: Int, parentDetail: MediaServerItemDetailDTO
  ) -> some View {
    let isAudioTrack = ep.kind == .audio || parentDetail.kind == .musicAlbum
    return CinematicPanel(padding: 10) {
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
            if isAudioTrack {
              Text("\(ep.episodeNumber ?? (index + 1))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.60))
                .frame(width: 26)
            } else {
              ZStack(alignment: .bottom) {
                NativeMediaArtwork(
                  session: session,
                  reference: ep.thumb ?? ep.backdrop ?? ep.poster ?? parentDetail.backdrop,
                  role: .backdrop,
                  maximumWidth: 320
                )
                .frame(width: 118, height: 68)
                .clipped()

                if let progress = ep.progressFraction, progress > 0.01, ep.played != true {
                  GeometryReader { bar in
                    ZStack(alignment: .leading) {
                      Rectangle().fill(.black.opacity(0.45))
                      Rectangle()
                        .fill(appearance.accentColor)
                        .frame(width: max(4, bar.size.width * progress))
                    }
                  }
                  .frame(height: 3)
                }
              }
              .frame(width: 118, height: 68)
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
              .overlay(alignment: .topTrailing) {
                if ep.played == true {
                  Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white, NativeTheme.success)
                    .padding(4)
                }
              }
            }

            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 5) {
                if let code = ep.episodeCode {
                  Text(code)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(appearance.accentColor)
                }
                if let dur = ep.formattedDuration {
                  Text(dur)
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.55))
                }
              }

              Text(ep.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

              if let overview = ep.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                !overview.isEmpty
              {
                Text(overview)
                  .font(.caption)
                  .foregroundStyle(.primary.opacity(0.66))
                  .lineLimit(2)
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

  /// 集详情页下方的本季分集横向速览条，方便快速切换上一集/下一集或本季其他集。
  private func adjacentEpisodesStrip(_ detail: MediaServerItemDetailDTO) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("本季更多剧集")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      ScrollView(.horizontal) {
        LazyHStack(spacing: 10) {
          ForEach(episodes) { ep in
            let isCurrent = ep.itemId == detail.itemId
            NavigationLink {
              NativeMediaServerDetailPage(
                session: session,
                server: ep.server ?? resolvedServer,
                itemID: ep.itemId,
                fallbackTitle: ep.title,
                fallbackItemType: "Episode",
                fallbackPoster: ep.thumb ?? ep.poster
              )
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                NativeMediaArtwork(
                  session: session,
                  reference: ep.thumb ?? ep.backdrop ?? ep.poster,
                  role: .backdrop,
                  maximumWidth: 280
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
      .scrollIndicators(.hidden)
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
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      if let targetSeason {
        subscribedSeasons.insert(targetSeason)
      } else {
        isSubscribed = true
      }
      await loadSubscriptionStatus(detail, external: external)
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
      } else {
        isSubscribed = false
      }
      if let detail, let ext = detail.resolvedExternalIdentity {
        await loadSubscriptionStatus(detail, external: ext)
      }
      feedbackMessage = (
        target.season.map { "已取消第 \($0) 季订阅。" } ?? "已取消订阅。",
        false
      )
    } catch {
      feedbackMessage = ("取消订阅失败，请稍后重试。", true)
    }
  }

  /// 查询当前作品在 MoviePilot 中的订阅与分季订阅状态，使「已订阅」按钮与媒体详情页保持一致并支持再次点击取消。
  private func loadSubscriptionStatus(
    _ loaded: MediaServerItemDetailDTO,
    external: (source: String, mediaID: String, type: String)
  ) async {
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
    struct StatusResponseItem: Decodable {
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
    let payload = [
      StatusQueryItem(
        mediaSource: external.source,
        mediaID: external.mediaID,
        mtype: external.type,
        title: loaded.seriesName ?? loaded.title,
        year: loaded.yearText
      )
    ]
    guard let body = try? JSONEncoder().encode(payload),
      let endpoint = try? APIEndpoint(path: ["media", "status"], method: .post, body: body),
      let snapshot = try? await session.request(
        endpoint, as: [StatusResponseItem].self, requiring: .init(category: .discovery)
      ).value.first
    else { return }
    isSubscribed = snapshot.subscribed
    subscribedSeasons = Set(snapshot.seasons.keys)
  }

  // MARK: - Data Loading

  private func loadAll() async {
    isLoading = true
    loadFailed = false
    fetchedLogo = nil
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
      let preferZh =
        UserDefaults.standard.object(forKey: "nativeV2.playback.preferChineseSub") as? Bool ?? true
      if let firstSource = loaded.mediaSources.first {
        selectedSourceID = firstSource.id
        trackSelection = MediaPlaybackTrackSelection.defaultSelection(
          for: firstSource, preferChineseSub: preferZh)
      }
      isLoading = false
      async let childrenTask: Void = loadHierarchyChildren(for: loaded)
      async let subStatusTask: Void = {
        if let ext = loaded.resolvedExternalIdentity {
          await loadSubscriptionStatus(loaded, external: ext)
        }
      }()
      async let logoTask: Void = loadLogoIfNeeded(for: loaded)
      _ = await (childrenTask, subStatusTask, logoTask)
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
      isLoading = false
    }
  }

  /// 媒体库详情未直接返回 Logo 时，利用外部媒体源编号静默拉取透明标题 Logo 并按身份缓存（携带语言元数据供中文准入过滤）。
  private func loadLogoIfNeeded(for loaded: MediaServerItemDetailDTO) async {
    if let direct = loaded.logo?.trimmingCharacters(in: .whitespacesAndNewlines), !direct.isEmpty {
      fetchedLogo = MediaServerLogoCacheEntry(
        url: direct, logoLanguage: loaded.logoLanguage, originalLanguage: nil)
      return
    }
    guard let ext = loaded.resolvedExternalIdentity else { return }
    let cacheKey = "\(session.scope.instanceID.uuidString)|\(ext.source)|\(ext.mediaID)|\(ext.type)"
    if let cached = Self.mediaLogoCache[cacheKey] {
      fetchedLogo = cached
      return
    }
    struct LogoProbe: Decodable, Sendable {
      let logoPath: String?
      let logoLanguage: String?
      let originalLanguage: String?
      private enum CodingKeys: String, CodingKey {
        case logoPath = "logo_path"
        case logoLanguage = "logo_language"
        case originalLanguage = "original_language"
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
        endpoint, as: LogoProbe.self, requiring: .init(category: .discovery)
      ).value,
      let resolved = NativeMediaDetailPage.resolveArtwork(
        probe.logoPath, source: ext.source, tmdbSize: "w500"),
      !resolved.isEmpty
    else { return }
    let entry = MediaServerLogoCacheEntry(
      url: resolved,
      logoLanguage: probe.logoLanguage,
      originalLanguage: probe.originalLanguage
    )
    Self.mediaLogoCache[cacheKey] = entry
    fetchedLogo = entry
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
    }
  }
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
