import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 按媒体身份反查订阅记录的辅助参数（用于尚未缓存 `subscribe_id` 的详情页直接打开订阅文件详情）。
struct NativeSubscribeMediaLookup: Hashable, Sendable {
  let mediaSource: String
  let mediaID: String
  let type: String
  let season: Int?
  let title: String?
  let year: String?
}

/// 驱动弹窗展示的订阅文件详情目标标识。
struct NativeSubscribeFilesTarget: Identifiable, Hashable, Sendable {
  let subscribeID: Int?
  let mediaLookup: NativeSubscribeMediaLookup?
  let fallbackTitle: String

  var id: String {
    if let subscribeID, subscribeID > 0 {
      return "sub-\(subscribeID)"
    }
    if let lookup = mediaLookup {
      return "media-\(lookup.mediaSource)-\(lookup.mediaID)-\(lookup.season ?? -1)"
    }
    return "fallback-\(fallbackTitle)"
  }
}

/// 原生订阅文件详情弹层：消费 `GET /api/v1/subscribe/files/{subscribe_id}`，按集展示下载种子文件与媒体库入库文件、进度统计、路径复制与一键播放。
@MainActor
struct NativeSubscribeFilesSheet: View {
  /// 文件展示维度切换。
  private enum FileMode: String, CaseIterable, Identifiable {
    case download = "下载文件"
    case library = "媒体库文件"
    var id: String { rawValue }
  }

  /// 单集覆盖状态筛选。
  private enum EpisodeFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case inLibrary = "已入库"
    case downloaded = "已下载"
    case pending = "待入库"
    var id: String { rawValue }
  }

  /// 单集覆盖状态分类。
  private enum EpisodeCoverageStatus {
    case inLibrary
    case downloaded
    case pending

    var label: String {
      switch self {
      case .inLibrary: "已入库"
      case .downloaded: "已下载"
      case .pending: "待入库"
      }
    }

    var tint: Color {
      switch self {
      case .inLibrary: NativeTheme.success
      case .downloaded: NativeTheme.info
      case .pending: NativeTheme.warning
      }
    }
  }

  let session: NativeSession
  let initialSubscribeID: Int?
  let mediaLookup: NativeSubscribeMediaLookup?
  let fallbackTitle: String

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss

  @State private var resolvedSubscribeID: Int?
  @State private var payload: NativeSubscribeFilesPayload?
  @State private var fileMode: FileMode = .download
  @State private var hasAutoSelectedMode = false
  @State private var episodeFilter: EpisodeFilter = .all
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isLaunchingPlayback = false
  @State private var bannerFeedback: (message: String, isError: Bool)?

  /// 使用已知订阅编号初始化文件详情弹窗。
  init(session: NativeSession, subscribeID: Int, fallbackTitle: String) {
    self.session = session
    self.initialSubscribeID = subscribeID
    self.mediaLookup = nil
    self.fallbackTitle = fallbackTitle
    _resolvedSubscribeID = State(initialValue: subscribeID > 0 ? subscribeID : nil)
  }

  /// 使用订阅目标（已知编号或媒体源身份回退）初始化文件详情弹窗。
  init(session: NativeSession, target: NativeSubscribeFilesTarget) {
    self.session = session
    self.initialSubscribeID = target.subscribeID
    self.mediaLookup = target.mediaLookup
    self.fallbackTitle = target.fallbackTitle
    _resolvedSubscribeID = State(
      initialValue: (target.subscribeID ?? 0) > 0 ? target.subscribeID : nil)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let bannerFeedback {
              feedbackBanner(bannerFeedback.message, isError: bannerFeedback.isError)
            }
            if isLoading && payload == nil {
              NativeCardListSkeletonView(count: 4, style: .posterRow)
                .transition(.opacity)
            } else if loadFailed && payload == nil {
              failureCard
            } else {
              summaryHeaderCard
              modeAndFilterBar
              episodesListSection
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load(force: true) }
        .modifier(NativeSoftTopScrollEdge())
        .accessibilityIdentifier("native-subscribe-files-scroll")
      }
      .navigationTitle("订阅文件详情")
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
          .accessibilityIdentifier("native-subscribe-files-close")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await load(force: true) }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .tint(.primary)
          .disabled(isLoading)
          .accessibilityLabel("刷新文件详情")
          .accessibilityIdentifier("native-subscribe-files-refresh")
        }
      }
    }
    .nativeGlassSheet()
    .task { await load(force: false) }
  }

  // MARK: - 派生统计与排序列表

  private var sortedEpisodes: [(number: Int, info: NativeSubscribeEpisodeFilesDTO)] {
    (payload?.episodes ?? [:])
      .map { ($0.key, $0.value) }
      .sorted { $0.0 < $1.0 }
  }

  private func coverageStatus(for info: NativeSubscribeEpisodeFilesDTO) -> EpisodeCoverageStatus {
    if !info.library.isEmpty { return .inLibrary }
    if !info.download.isEmpty { return .downloaded }
    return .pending
  }

  private var filteredEpisodes: [(number: Int, info: NativeSubscribeEpisodeFilesDTO)] {
    sortedEpisodes.filter { entry in
      let st = coverageStatus(for: entry.info)
      switch episodeFilter {
      case .all: return true
      case .inLibrary: return st == .inLibrary
      case .downloaded: return st == .downloaded || !entry.info.download.isEmpty
      case .pending: return st == .pending
      }
    }
  }

  private var totalDownloadFileCount: Int {
    sortedEpisodes.reduce(0) { $0 + $1.info.download.count }
  }

  private var totalLibraryFileCount: Int {
    sortedEpisodes.reduce(0) { $0 + $1.info.library.count }
  }

  private var isMovieSubscription: Bool {
    if let subType = payload?.subscribe?.type, subType == "电影" { return true }
    if let lookupType = mediaLookup?.type, lookupType == "电影" { return true }
    return sortedEpisodes.count == 1 && sortedEpisodes.first?.number == 0
  }

  // MARK: - 1. 顶部订阅摘要与进度统计卡片

  private var summaryHeaderCard: some View {
    let sub = payload?.subscribe
    let mediaSource = sub?.mediaSource ?? mediaLookup?.mediaSource ?? "themoviedb"
    let posterRef = Self.resolveMediaArtwork(sub?.poster, source: mediaSource, tmdbSize: "w500")
    let backdropRef =
      Self.resolveMediaArtwork(sub?.backdrop, source: mediaSource, tmdbSize: "w780") ?? posterRef
    let displayTitle =
      (sub?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      ? sub!.name!
      : fallbackTitle

    let episodeTotal = max(
      sortedEpisodes.count,
      sub?.totalEpisode ?? (isMovieSubscription ? 1 : sortedEpisodes.count),
      1
    )
    let downloadedCount = sortedEpisodes.filter {
      !$0.info.download.isEmpty || !$0.info.library.isEmpty
    }.count
    let libraryCount = sortedEpisodes.filter { !$0.info.library.isEmpty }.count
    let missingCount: Int = {
      if let lack = sub?.lackEpisode, lack >= 0, sortedEpisodes.isEmpty {
        return lack
      }
      return max(episodeTotal - libraryCount, 0)
    }()

    return CinematicPanel(padding: 0) {
      ZStack(alignment: .top) {
        if let backdropRef {
          NativeMediaArtwork(
            session: session, reference: backdropRef, role: .backdrop, maximumWidth: 720
          )
          .frame(height: 120)
          .frame(maxWidth: .infinity)
          .clipped()
          .blur(radius: 18)
          .opacity(colorScheme == .light ? 0.24 : 0.30)
          .mask(
            LinearGradient(
              colors: [.white, .white.opacity(0.45), .clear],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .allowsHitTesting(false)
        }

        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top, spacing: 13) {
            NativeMediaArtwork(
              session: session, reference: posterRef, role: .poster, maximumWidth: 320
            )
            .frame(width: 66, height: 99)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.primary.opacity(0.14), lineWidth: 0.6)
            }

            VStack(alignment: .leading, spacing: 7) {
              Text(displayTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .accessibilityIdentifier("native-subscribe-files-title")

              HStack(spacing: 6) {
                if let season = sub?.season ?? mediaLookup?.season, !isMovieSubscription {
                  NativeAdaptiveBadge(String(format: "S%02d", season), tint: appearance.accentColor)
                }
                if let year = sub?.year ?? mediaLookup?.year, !year.isEmpty {
                  NativeAdaptiveBadge(year)
                }
                let stateMeta = stateDisplay(sub?.state)
                NativeAdaptiveBadge(stateMeta.title, tint: stateMeta.tint)
                if sub?.bestVersion == 1 {
                  NativeAdaptiveBadge("洗版", tint: NativeTheme.warning)
                }
              }
            }
            Spacer(minLength: 0)
          }

          HStack(spacing: 8) {
            progressStatTile(
              label: "已下载",
              valueText: "\(downloadedCount)/\(episodeTotal)",
              fraction: Double(downloadedCount) / Double(max(episodeTotal, 1)),
              tint: NativeTheme.info
            )
            progressStatTile(
              label: "已入库",
              valueText: "\(libraryCount)/\(episodeTotal)",
              fraction: Double(libraryCount) / Double(max(episodeTotal, 1)),
              tint: NativeTheme.success
            )
            progressStatTile(
              label: "缺失",
              valueText: "\(missingCount)",
              fraction: Double(missingCount) / Double(max(episodeTotal, 1)),
              tint: missingCount > 0 ? NativeTheme.warning : NativeTheme.badgeMutedText
            )
          }
        }
        .padding(15)
      }
    }
  }

  private func progressStatTile(
    label: String, valueText: String, fraction: Double, tint: Color
  ) -> some View {
    let clamped = min(max(fraction, 0), 1)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(label)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
        Spacer(minLength: 2)
        Text(valueText)
          .font(.caption.weight(.bold).monospacedDigit())
          .foregroundStyle(.primary)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(.primary.opacity(colorScheme == .light ? 0.08 : 0.12))
          Capsule()
            .fill(tint)
            .frame(width: max(clamped > 0 ? 5 : 0, proxy.size.width * clamped))
        }
      }
      .frame(height: 5)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(NativeTheme.chipFill)
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6)
        }
    }
  }

  private func stateDisplay(_ raw: String?) -> (title: String, tint: Color) {
    switch (raw ?? "R").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "R": return ("订阅中", NativeTheme.success)
    case "P": return ("待处理", NativeTheme.info)
    case "S": return ("已暂停", NativeTheme.badgeMutedText)
    case "N": return ("新订阅", NativeTheme.brand)
    default: return ("订阅中", NativeTheme.success)
    }
  }

  // MARK: - 2. 模式切换与分集筛选

  private var modeAndFilterBar: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        ForEach(FileMode.allCases) { mode in
          let selected = fileMode == mode
          let count = mode == .download ? totalDownloadFileCount : totalLibraryFileCount
          Button {
            withAnimation(.easeInOut(duration: 0.18)) {
              fileMode = mode
            }
          } label: {
            HStack(spacing: 5) {
              Image(
                systemName: mode == .download
                  ? "arrow.down.circle" : "play.tv"
              )
              .font(.caption.weight(.semibold))
              Text("\(mode.rawValue) (\(count))")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : .primary.opacity(0.84))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
              if selected {
                Capsule().fill(appearance.accentColor)
              } else {
                Capsule()
                  .fill(NativeTheme.chipFill)
                  .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier(
            mode == .download
              ? "native-subscribe-files-mode-download"
              : "native-subscribe-files-mode-library"
          )
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(EpisodeFilter.allCases) { option in
            Button {
              episodeFilter = option
            } label: {
              NativeAdaptivePill(option.rawValue, isSelected: episodeFilter == option)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-subscribe-files-filter-\(option.rawValue)")
          }
        }
      }
    }
  }

  // MARK: - 3. 分集文件卡片列表

  @ViewBuilder
  private var episodesListSection: some View {
    if sortedEpisodes.isEmpty {
      CinematicPanel {
        VStack(spacing: 8) {
          Image(systemName: "doc.text.magnifyingglass")
            .font(.title2)
            .foregroundStyle(.secondary)
          Text("暂无文件覆盖记录")
            .font(.subheadline.weight(.semibold))
          Text("订阅触发下载或入库整理后，将在此处按集展示关联文件。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
      }
    } else if filteredEpisodes.isEmpty {
      CinematicPanel {
        VStack(spacing: 8) {
          Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.title3)
            .foregroundStyle(.secondary)
          Text("当前筛选条件下暂无匹配集数")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
      }
    } else {
      LazyVStack(spacing: 12) {
        ForEach(filteredEpisodes, id: \.number) { entry in
          episodeFileCard(number: entry.number, info: entry.info)
        }
      }
    }
  }

  private func episodeFileCard(number: Int, info: NativeSubscribeEpisodeFilesDTO) -> some View {
    let codeLabel = number == 0 ? "电影" : String(format: "E%02d", number)
    let rawTitle = info.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let episodeTitle =
      !rawTitle.isEmpty
      ? rawTitle
      : (number == 0 ? fallbackTitle : "第 \(number) 集")
    let status = coverageStatus(for: info)
    let source = payload?.subscribe?.mediaSource ?? mediaLookup?.mediaSource ?? "themoviedb"
    let backdropRef = Self.resolveMediaArtwork(info.backdrop, source: source, tmdbSize: "w500")

    return CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .center, spacing: 10) {
          if let backdropRef {
            NativeMediaArtwork(
              session: session, reference: backdropRef, role: .backdrop, maximumWidth: 280
            )
            .frame(width: 72, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            }
          }

          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(codeLabel)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(appearance.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(appearance.accentColor.opacity(0.14), in: Capsule())

              Text(episodeTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            }
            if let desc = info.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !desc.isEmpty
            {
              Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          Spacer(minLength: 6)
          NativeAdaptiveBadge(status.label, tint: status.tint)
        }

        Divider().overlay(NativeTheme.divider)

        if fileMode == .download {
          if info.download.isEmpty {
            Text("暂无下载种子文件记录")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.vertical, 2)
          } else {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(Array(info.download.enumerated()), id: \.offset) { idx, dl in
                if idx > 0 { Divider().overlay(NativeTheme.divider.opacity(0.65)) }
                downloadEntryView(dl)
              }
            }
          }
        } else {
          if info.library.isEmpty {
            Text("暂无已入库媒体文件")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.vertical, 2)
          } else {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(Array(info.library.enumerated()), id: \.offset) { idx, lib in
                if idx > 0 { Divider().overlay(NativeTheme.divider.opacity(0.65)) }
                libraryEntryView(
                  lib, episodeTitle: "\(codeLabel) · \(episodeTitle)", backdrop: backdropRef)
              }
            }
          }
        }
      }
    }
    .accessibilityIdentifier("native-subscribe-files-ep-\(number)")
  }

  private func downloadEntryView(_ item: NativeSubscribeDownloadFileDTO) -> some View {
    let resolution = Self.extractResolution(from: [item.torrentTitle, item.filePath])
    return VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        if let resolution {
          NativeAdaptiveBadge(resolution, tint: appearance.accentColor)
        }
        if let site = item.siteName?.trimmingCharacters(in: .whitespacesAndNewlines), !site.isEmpty
        {
          NativeAdaptiveBadge(site, tint: NativeTheme.cyan)
        }
        if let downloader = item.downloader?.trimmingCharacters(in: .whitespacesAndNewlines),
          !downloader.isEmpty
        {
          HStack(spacing: 4) {
            NativeBrandIcon(kind: .downloader, type: downloader, size: 16, cornerRadius: 4)
            Text(downloader)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.primary.opacity(0.84))
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(NativeTheme.chipFill, in: Capsule())
        }
        Spacer(minLength: 0)
      }

      if let torrent = item.torrentTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
        !torrent.isEmpty
      {
        Text(torrent)
          .font(.caption.weight(.medium))
          .foregroundStyle(.primary.opacity(0.90))
          .lineLimit(2)
      }

      if let hash = item.hash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
        Text("HASH · \(hash)")
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      if let path = item.filePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
        pathRow(path)
      }
    }
  }

  private func libraryEntryView(
    _ item: NativeSubscribeLibraryFileDTO, episodeTitle: String, backdrop: String?
  ) -> some View {
    let resolution = Self.extractResolution(from: [item.filePath])
    let storageLabel =
      (item.storage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
      ? item.storage! : "local"
    let serverName = item.server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let itemID = item.itemID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let canDirectPlay = !serverName.isEmpty && !itemID.isEmpty
    let path = item.filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let webLink: URL? = {
      guard path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") else {
        return nil
      }
      return URL(string: path)
    }()

    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 7) {
        if let resolution {
          NativeAdaptiveBadge(resolution, tint: appearance.accentColor)
        }
        if !serverName.isEmpty {
          HStack(spacing: 4) {
            NativeBrandIcon(
              kind: .mediaServer, type: item.serverType ?? serverName, size: 16, cornerRadius: 4)
            Text(serverName)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.primary.opacity(0.86))
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(NativeTheme.chipFill, in: Capsule())
        }
        HStack(spacing: 4) {
          NativeBrandIcon(kind: .storage, type: storageLabel, size: 16, cornerRadius: 4)
          Text(storageLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary.opacity(0.84))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(NativeTheme.chipFill, in: Capsule())
        Spacer(minLength: 0)
      }

      if !path.isEmpty {
        Text(path)
          .font(.caption2.monospaced())
          .foregroundStyle(.primary.opacity(0.86))
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(NativeTheme.fieldFill)
              .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.6)
              }
          }
      }

      HStack(spacing: 8) {
        if !path.isEmpty {
          copyPathButton(path)
        }
        if let webLink {
          Button {
            UIApplication.shared.open(webLink)
          } label: {
            Label("打开链接", systemImage: "arrow.up.right.square")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(NativeTheme.chipFill)
                  .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
              }
          }
          .buttonStyle(.plain)
        }
        Spacer(minLength: 0)
        if canDirectPlay {
          Button {
            Task {
              isLaunchingPlayback = true
              let artworkURL = NativeMediaPlaybackLauncher.proxiedArtworkURL(
                session: session, raw: backdrop)
              let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
                session: session,
                itemID: itemID,
                server: serverName,
                title: episodeTitle,
                artworkURL: artworkURL
              )
              isLaunchingPlayback = false
              if let err {
                bannerFeedback = (err, true)
              }
            }
          } label: {
            HStack(spacing: 4) {
              if isLaunchingPlayback {
                ProgressView().controlSize(.mini).tint(.white)
              } else {
                Image(systemName: "play.fill").font(.caption2.weight(.bold))
              }
              Text("立即播放").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(appearance.accentColor, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(isLaunchingPlayback)
          .accessibilityIdentifier("native-subscribe-files-play-\(itemID)")
        }
      }
    }
  }

  private func pathRow(_ path: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(path)
        .font(.caption2.monospaced())
        .foregroundStyle(.primary.opacity(0.86))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(NativeTheme.fieldFill)
            .overlay {
              RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(NativeTheme.fieldBorder, lineWidth: 0.6)
            }
        }
      HStack {
        copyPathButton(path)
        Spacer(minLength: 0)
      }
    }
  }

  private func copyPathButton(_ path: String) -> some View {
    Button {
      UIPasteboard.general.string = path
      bannerFeedback = ("已复制文件路径。", false)
    } label: {
      Label("复制路径", systemImage: "doc.on.doc")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .background {
          Capsule()
            .fill(NativeTheme.chipFill)
            .overlay { Capsule().strokeBorder(NativeTheme.chipBorder, lineWidth: 0.6) }
        }
    }
    .buttonStyle(.plain)
  }

  private func feedbackBanner(_ text: String, isError: Bool) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 8) {
        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
          .foregroundStyle(isError ? NativeTheme.warning : NativeTheme.success)
        Text(text)
          .font(.footnote)
          .foregroundStyle(.primary)
        Spacer(minLength: 0)
        Button {
          bannerFeedback = nil
        } label: {
          Image(systemName: "xmark")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-subscribe-files-feedback")
  }

  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法读取订阅文件详情", systemImage: "exclamationmark.triangle")
          .font(.headline)
        Button("重试") {
          Task { await load(force: true) }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("native-subscribe-files-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - 网络请求与解析工具

  private func load(force: Bool) async {
    if payload == nil || force {
      isLoading = true
    }
    loadFailed = false
    defer { isLoading = false }

    do {
      var targetID = resolvedSubscribeID ?? initialSubscribeID ?? 0
      if targetID <= 0, let lookup = mediaLookup {
        targetID = try await lookupSubscribeID(lookup) ?? 0
        if targetID > 0 {
          resolvedSubscribeID = targetID
        }
      }
      guard targetID > 0 else {
        loadFailed = true
        return
      }
      let endpoint = try APIEndpoint(path: ["subscribe", "files", String(targetID)])
      let loaded = try await session.request(
        endpoint, as: NativeSubscribeFilesPayload.self, requiring: .init(category: .subscribe)
      ).value
      try Task.checkCancellation()
      payload = loaded
      if !hasAutoSelectedMode {
        hasAutoSelectedMode = true
        let dlCount = loaded.episodes.values.reduce(0) { $0 + $1.download.count }
        let libCount = loaded.episodes.values.reduce(0) { $0 + $1.library.count }
        if dlCount == 0 && libCount > 0 {
          fileMode = .library
        }
      }
    } catch is CancellationError {
      return
    } catch {
      if payload == nil {
        loadFailed = true
      } else {
        bannerFeedback = ("刷新文件详情失败，请稍后重试。", true)
      }
    }
  }

  private func lookupSubscribeID(_ lookup: NativeSubscribeMediaLookup) async throws -> Int? {
    struct LookupRecord: Decodable, Sendable {
      let id: Int?
    }
    var query: [URLQueryItem] = [
      URLQueryItem(name: "media_source", value: lookup.mediaSource)
    ]
    if let season = lookup.season, lookup.type == "电视剧" {
      query.append(URLQueryItem(name: "season", value: String(season)))
    }
    if let title = lookup.title, !title.isEmpty {
      query.append(URLQueryItem(name: "title", value: title))
    }
    if let year = lookup.year, !year.isEmpty {
      query.append(URLQueryItem(name: "year", value: year))
    }
    if !lookup.type.isEmpty {
      query.append(URLQueryItem(name: "mtype", value: lookup.type))
    }
    let endpoint = try APIEndpoint(path: ["subscribe", "media", lookup.mediaID], query: query)
    let record = try await session.request(
      endpoint, as: LookupRecord.self, requiring: .init(category: .subscribe)
    ).value
    return (record.id ?? 0) > 0 ? record.id : nil
  }

  nonisolated private static func extractResolution(from candidates: [String?]) -> String? {
    let joined = candidates.compactMap { $0 }.joined(separator: " ").uppercased()
    guard !joined.isEmpty else { return nil }
    if joined.contains("2160P") || joined.contains("4K") || joined.contains("UHD") {
      return "4K"
    }
    if joined.contains("1080P") || joined.contains("1080I") {
      return "1080P"
    }
    if joined.contains("720P") {
      return "720P"
    }
    if joined.contains("480P") || joined.contains("576P") {
      return "SD"
    }
    return nil
  }

  nonisolated private static func resolveMediaArtwork(
    _ raw: String?, source: String?, tmdbSize: String
  ) -> String? {
    NativeMediaDetailPage.resolveArtwork(raw, source: source, tmdbSize: tmdbSize)
  }
}

// MARK: - 解码 DTO

private struct NativeSubscribeFilesPayload: Decodable, Sendable {
  let subscribe: NativeSubscribeFilesHeaderDTO?
  let episodes: [Int: NativeSubscribeEpisodeFilesDTO]

  private enum CodingKeys: String, CodingKey {
    case subscribe, episodes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    subscribe = try? container.decodeIfPresent(
      NativeSubscribeFilesHeaderDTO.self, forKey: .subscribe)
    let rawDict =
      (try? container.decodeIfPresent(
        [String: NativeSubscribeEpisodeFilesDTO].self, forKey: .episodes)) ?? [:]
    var parsed: [Int: NativeSubscribeEpisodeFilesDTO] = [:]
    for (key, value) in rawDict {
      if let ep = Int(key) {
        parsed[ep] = value
      }
    }
    episodes = parsed
  }
}

private struct NativeSubscribeFilesHeaderDTO: Decodable, Sendable {
  let id: Int?
  let name: String?
  let year: String?
  let type: String?
  let season: Int?
  let poster: String?
  let backdrop: String?
  let mediaSource: String?
  let mediaID: String?
  let state: String?
  let totalEpisode: Int?
  let lackEpisode: Int?
  let completedEpisode: Int?
  let bestVersion: Int?

  private enum CodingKeys: String, CodingKey {
    case id, name, year, type, season, poster, backdrop, state
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case totalEpisode = "total_episode"
    case lackEpisode = "lack_episode"
    case completedEpisode = "completed_episode"
    case bestVersion = "best_version"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try? c.decodeIfPresent(Int.self, forKey: .id)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    year = try? c.decodeIfPresent(String.self, forKey: .year)
    type = try? c.decodeIfPresent(String.self, forKey: .type)
    season = try? c.decodeIfPresent(Int.self, forKey: .season)
    poster = try? c.decodeIfPresent(String.self, forKey: .poster)
    backdrop = try? c.decodeIfPresent(String.self, forKey: .backdrop)
    mediaSource = try? c.decodeIfPresent(String.self, forKey: .mediaSource)
    mediaID = try? c.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .mediaID)?.value
    state = try? c.decodeIfPresent(String.self, forKey: .state)
    totalEpisode = try? c.decodeIfPresent(Int.self, forKey: .totalEpisode)
    lackEpisode = try? c.decodeIfPresent(Int.self, forKey: .lackEpisode)
    completedEpisode = try? c.decodeIfPresent(Int.self, forKey: .completedEpisode)
    bestVersion =
      (try? c.decodeIfPresent(Int.self, forKey: .bestVersion))
      ?? ((try? c.decodeIfPresent(Bool.self, forKey: .bestVersion)) == true ? 1 : 0)
  }
}

private struct NativeSubscribeEpisodeFilesDTO: Decodable, Sendable {
  let title: String?
  let description: String?
  let backdrop: String?
  let download: [NativeSubscribeDownloadFileDTO]
  let library: [NativeSubscribeLibraryFileDTO]

  private enum CodingKeys: String, CodingKey {
    case title, description, backdrop, download, library
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try? c.decodeIfPresent(String.self, forKey: .title)
    description = try? c.decodeIfPresent(String.self, forKey: .description)
    backdrop = try? c.decodeIfPresent(String.self, forKey: .backdrop)
    download =
      (try? c.decodeIfPresent([NativeSubscribeDownloadFileDTO].self, forKey: .download)) ?? []
    library =
      (try? c.decodeIfPresent([NativeSubscribeLibraryFileDTO].self, forKey: .library)) ?? []
  }
}

private struct NativeSubscribeDownloadFileDTO: Decodable, Sendable {
  let torrentTitle: String?
  let siteName: String?
  let downloader: String?
  let hash: String?
  let filePath: String?

  private enum CodingKeys: String, CodingKey {
    case downloader, hash
    case torrentTitle = "torrent_title"
    case siteName = "site_name"
    case filePath = "file_path"
  }
}

private struct NativeSubscribeLibraryFileDTO: Decodable, Sendable {
  let storage: String?
  let filePath: String?
  let server: String?
  let serverType: String?
  let itemID: String?

  private enum CodingKeys: String, CodingKey {
    case storage, server
    case filePath = "file_path"
    case serverType = "server_type"
    case itemID = "itemid"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    storage = try? c.decodeIfPresent(String.self, forKey: .storage)
    filePath = try? c.decodeIfPresent(String.self, forKey: .filePath)
    server = try? c.decodeIfPresent(String.self, forKey: .server)
    serverType = try? c.decodeIfPresent(String.self, forKey: .serverType)
    itemID = try? c.decodeIfPresent(MediaServerFlexibleScalar.self, forKey: .itemID)?.value
  }
}
