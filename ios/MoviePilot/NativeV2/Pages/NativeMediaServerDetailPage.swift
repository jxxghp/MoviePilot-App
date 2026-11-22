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
  @State private var seasons: [MediaServerBrowseItemDTO] = []
  @State private var episodes: [MediaServerBrowseItemDTO] = []
  @State private var selectedSeasonNumber: Int?
  @State private var selectedSourceID: String?
  @State private var trackSelection = MediaPlaybackTrackSelection()

  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isLaunchingPlayback = false
  @State private var isSubscribing = false
  @State private var isSubscribed = false
  @State private var synopsisExpanded = false
  @State private var feedbackMessage: (text: String, isError: Bool)?
  @State private var scrollOffset: CGFloat = 0

  @Environment(\.colorScheme) private var colorScheme
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
      let heroHeight = resolvedHeroHeight(viewportHeight: viewport.size.height)
      let progress = min(max(-scrollOffset / max(heroHeight * 0.62, 1), 0), 1)
      let eased = progress * progress * (3 - 2 * progress)

      ZStack(alignment: .top) {
        ambientSurface(progress: eased).ignoresSafeArea()
        if let detail {
          heroBackdrop(detail, width: viewport.size.width, height: heroHeight, eased: eased)
            .ignoresSafeArea(edges: .top)
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if let detail {
              heroHeaderOverlay(detail, height: heroHeight)

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
              .padding(.horizontal, CinematicStyle.margin)
              .padding(.top, 8)
              .padding(.bottom, 40)
            } else if loadFailed {
              failureCard
                .padding(.horizontal, CinematicStyle.margin)
                .padding(.top, 110)
            } else {
              NativeMediaDetailSkeletonView(heroHeight: heroHeight)
            }
          }
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable { await loadAll() }
        .modifier(NativeSoftTopScrollEdge())
        .ignoresSafeArea(edges: .top)
        .modifier(MediaServerDetailScrollObservation(offset: $scrollOffset))
        .accessibilityIdentifier("native-mediaserver-detail-scroll")

        topSafeAreaVeil(progress: eased, height: max(viewport.safeAreaInsets.top, 48) + 42)
      }
      .navigationTitle(progress > 0.72 ? (detail?.title ?? fallbackTitle ?? "") : "")
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      if let playUrl = detail?.playUrl, let url = URL(string: playUrl) {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            if let ext = detail?.resolvedExternalIdentity {
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
            Button {
              UIApplication.shared.open(url)
            } label: {
              Label("在外部媒体服务器打开", systemImage: "arrow.up.right.square")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityLabel("更多选项")
          .accessibilityIdentifier("native-mediaserver-detail-menu")
        }
      }
    }
    .task(id: "\(server ?? "")|\(itemID)") {
      await loadAll()
    }
  }

  // MARK: - Hero

  private func resolvedHeroHeight(viewportHeight: CGFloat) -> CGFloat {
    if dynamicTypeSize.isAccessibilitySize {
      return max(480, viewportHeight * 0.62)
    }
    let kind = detail?.kind ?? MediaServerItemKind(rawItemType: fallbackItemType)
    if kind == .episode {
      return min(max(viewportHeight * 0.44, 330), 420)
    }
    return min(max(viewportHeight * 0.54, 390), 510)
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

  private func heroBackdrop(
    _ detail: MediaServerItemDetailDTO, width: CGFloat, height: CGFloat, eased: CGFloat
  ) -> some View {
    let ref: String? =
      if detail.kind == .episode {
        detail.thumb ?? detail.backdrop ?? detail.poster
      } else {
        detail.backdrop ?? detail.poster ?? detail.thumb
      }
    let scrollUp = max(-scrollOffset, 0)
    let pullDown = max(scrollOffset, 0)
    let backdropHeight = height * 1.08 + pullDown
    let parallax = reduceMotion ? 0 : -min(scrollUp, height) * 0.07
    let blurRadius: CGFloat = (reduceMotion || reduceTransparency) ? 0 : eased * 18
    let visibility = max(0, 1 - Double(eased) * 0.94)
    let fadeBase =
      colorScheme == .light
      ? NativeTheme.topVeilColor(for: .light, appearance: appearance)
      : Color(red: 10 / 255, green: 10 / 255, blue: 22 / 255)

    return ZStack(alignment: .bottom) {
      NativeMediaArtwork(session: session, reference: ref, role: .backdrop, maximumWidth: 1280)
        .frame(width: width, height: backdropHeight)
        .clipped()
        .blur(radius: blurRadius)
        .offset(y: parallax)
        .opacity(visibility)

      LinearGradient(
        stops: [
          .init(color: fadeBase.opacity(0.0), location: 0.0),
          .init(color: fadeBase.opacity(0.08), location: 0.34),
          .init(color: fadeBase.opacity(0.32), location: 0.56),
          .init(color: fadeBase.opacity(0.68), location: 0.76),
          .init(color: fadeBase.opacity(0.92), location: 0.90),
          .init(color: fadeBase, location: 1.0),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(width: width, height: backdropHeight)
    }
    .frame(width: width, height: backdropHeight)
    .clipped()
    .allowsHitTesting(false)
  }

  private func topSafeAreaVeil(progress: CGFloat, height: CGFloat) -> some View {
    let base = NativeTheme.topVeilColor(for: colorScheme, appearance: appearance)
    return LinearGradient(
      colors: [base.opacity(Double(progress) * 0.88), base.opacity(0)],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(height: height)
    .ignoresSafeArea(edges: .top)
    .allowsHitTesting(false)
  }

  private func heroHeaderOverlay(_ detail: MediaServerItemDetailDTO, height: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Spacer(minLength: 0)

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

      Text(heroDisplayTitle(detail))
        .font(.system(.title, design: .serif).weight(.bold))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("native-mediaserver-detail-title")

      let meta = metadataLineParts(detail)
      if !meta.isEmpty {
        Text(meta.joined(separator: " · "))
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary.opacity(0.76))
      }

      if !detail.genres.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 6) {
            ForEach(detail.genres.prefix(6), id: \.self) { genre in
              Text(genre)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary.opacity(0.82))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.10), in: Capsule())
            }
          }
        }
        .scrollIndicators(.hidden)
      }
    }
    .padding(.horizontal, CinematicStyle.margin)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
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
    return VStack(spacing: 10) {
      if hasPlayAction {
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
      }

      if (canSubscribe && subscribeTarget != nil) || canSearchResources {
        HStack(spacing: 10) {
          if canSubscribe, let ext = subscribeTarget {
            Button {
              Task { await performSubscribe(detail, external: ext) }
            } label: {
              HStack(spacing: 6) {
                if isSubscribing {
                  ProgressView().controlSize(.mini).tint(.primary)
                } else {
                  Image(systemName: isSubscribed ? "bookmark.fill" : "plus")
                    .font(.subheadline.weight(.semibold))
                }
                Text(subscribeButtonTitle(detail))
                  .font(.subheadline.weight(.semibold))
                  .lineLimit(1)
              }
              .foregroundStyle(
                isSubscribed ? Color(red: 0.44, green: 0.90, blue: 0.66) : .primary
              )
              .frame(maxWidth: .infinity)
              .frame(height: 46)
              .background {
                Capsule()
                  .fill(
                    isSubscribed
                      ? Color(red: 0.24, green: 0.66, blue: 0.46).opacity(0.24)
                      : .primary.opacity(colorScheme == .light ? 0.08 : 0.13)
                  )
                  .overlay {
                    Capsule().strokeBorder(
                      isSubscribed
                        ? Color(red: 0.44, green: 0.90, blue: 0.66).opacity(0.36)
                        : .primary.opacity(0.20),
                      lineWidth: 0.7
                    )
                  }
              }
            }
            .buttonStyle(.plain)
            .disabled(isSubscribing || isSubscribed)
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
        }
      }
    }
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

  private func subscribeButtonTitle(_ detail: MediaServerItemDetailDTO) -> String {
    if isSubscribed { return "已订阅" }
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
      let body = try JSONEncoder().encode(
        SubscribeBody(
          name: detail.seriesName ?? detail.title,
          type: external.type,
          year: detail.yearText ?? "",
          mediaSource: external.source,
          mediaID: external.mediaID,
          season: external.type == "电视剧" ? (detail.seasonNumber ?? selectedSeasonNumber ?? 1) : nil
        )
      )
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      isSubscribed = true
      feedbackMessage = ("已成功添加订阅。", false)
    } catch {
      feedbackMessage = ("添加订阅失败，可能已存在或暂无权限。", true)
    }
  }

  // MARK: - Data Loading

  private func loadAll() async {
    isLoading = true
    loadFailed = false
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
      await loadHierarchyChildren(for: loaded)
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
      isLoading = false
    }
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

/// iOS 18+ 原生滚动偏移观察器（用于详情页 Hero 视差与标题渐显）。
private struct MediaServerDetailScrollObservation: ViewModifier {
  @Binding var offset: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      content.onScrollGeometryChange(for: CGFloat.self) { geometry in
        let raw = -(geometry.contentOffset.y + geometry.contentInsets.top)
        return max(min(raw, 200), -640)
      } action: { _, value in
        if abs(offset - value) >= 0.5 { offset = value }
      }
    } else {
      content
    }
  }
}
