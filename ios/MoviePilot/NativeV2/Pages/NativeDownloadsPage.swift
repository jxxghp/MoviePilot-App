import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生下载管理页：参照深色渐变玻璃任务横卡，直连 MoviePilot 下载器查询与启停删控制。
@MainActor
struct NativeDownloadsPage: View {
  private enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "全部任务"
    case active = "进行中"
    case paused = "已暂停"
    var id: String { rawValue }
  }

  private enum SortMode: String, CaseIterable, Identifiable {
    case defaultOrder = "默认顺序"
    case progressDesc = "进度从高到低"
    case sizeDesc = "体积从大到小"
    case titleAsc = "名称排序"
    var id: String { rawValue }
  }

  let session: NativeSession

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @State private var clients: [NativeDownloaderClient] = []
  @State private var selectedClient: String?
  @State private var tasks: [NativeDownloadTask] = []
  @State private var statusFilter: StatusFilter = .all
  @State private var sortMode: SortMode = .defaultOrder
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var mutatingHash: String?
  @State private var pendingDelete: NativeDownloadTask?
  @State private var feedback: NativeDownloadFeedback?
  @State private var containerWidth: CGFloat = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// 连续紫玫瑰渐变背景、下载器筛选胶囊、16:9 缩略图进度玻璃卡与原生刷新工具栏。
  var body: some View {
    let resolvedWidth = NativeDeviceLayout.resolvedContainerWidth(containerWidth)
    let columnCount = NativeDeviceLayout.cardGridCount(
      for: resolvedWidth, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if clients.count > 1 {
            clientFilterBar
          }
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && tasks.isEmpty {
            NativeCardListSkeletonView(
              count: columnCount * 3,
              style: .downloadCard,
              columns: columnCount,
              spacing: 14
            )
            .transition(.opacity)
          } else if loadFailed && tasks.isEmpty {
            failureCard
          } else if displayedTasks.isEmpty {
            emptyCard
          } else {
            let gridColumns = Array(
              repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
            LazyVGrid(columns: gridColumns, spacing: 14) {
              ForEach(displayedTasks) { task in
                downloadRow(task)
              }
            }
          }
        }
        .frame(maxWidth: resolvedWidth >= 740 ? 1180 : 820)
        .padding(.horizontal, NativeDeviceLayout.horizontalMargin(for: resolvedWidth))
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .refreshable { await load(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-downloads-scroll")
    }
    .navigationTitle("正在下载")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Section("任务状态") {
            ForEach(StatusFilter.allCases) { option in
              Button {
                statusFilter = option
              } label: {
                if statusFilter == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
          Section("排序方式") {
            ForEach(SortMode.allCases) { option in
              Button {
                sortMode = option
              } label: {
                if sortMode == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
        } label: {
          Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .tint(.primary)
        .accessibilityLabel("筛选与排序")
        .accessibilityIdentifier("native-downloads-filter-menu")
      }
    }
    .task(id: "\(attempt)|\(selectedClient ?? "")") {
      await load(forceRefresh: true)
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled else { break }
        await load(forceRefresh: true, silent: true)
      }
    }
    .alert(
      "删除下载任务",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { task in
      Button("删除任务与文件", role: .destructive) {
        Task { await deleteTask(task) }
      }
      Button("取消", role: .cancel) {}
    } message: { task in
      Text("确认删除「\(task.displayTitle)」及其下载文件吗？此操作无法撤销。")
    }
  }

  /// 按所选状态筛选与排序后的下载任务列表。
  private var displayedTasks: [NativeDownloadTask] {
    let filtered = tasks.filter { task in
      switch statusFilter {
      case .all: true
      case .active: !task.isPaused
      case .paused: task.isPaused
      }
    }
    switch sortMode {
    case .defaultOrder:
      return filtered
    case .progressDesc:
      return filtered.sorted { ($0.progress ?? 0) > ($1.progress ?? 0) }
    case .sizeDesc:
      return filtered.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    case .titleAsc:
      return filtered.sorted {
        $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
      }
    }
  }

  /// 当前用户具备管理权限时开放下载任务启停与删除操作。
  private var canManage: Bool {
    session.user.isSuperuser || session.user.allows(.init(category: .manage))
  }

  /// 多下载器横向筛选胶囊。
  private var clientFilterBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        filterChip(title: "全部下载器", selected: selectedClient == nil) {
          selectedClient = nil
        }
        ForEach(clients) { client in
          filterChip(title: client.name, selected: selectedClient == client.name) {
            selectedClient = client.name
          }
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  /// 单枚半透明筛选胶囊。
  private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View
  {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .foregroundStyle(.primary.opacity(selected ? 0.98 : 0.78))
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background {
          Capsule()
            .fill(selected ? NativeTheme.brand.opacity(0.18) : NativeTheme.chipFill)
            .overlay {
              Capsule().strokeBorder(.primary.opacity(selected ? 0.28 : 0.14), lineWidth: 0.6)
            }
        }
        .frame(minHeight: 38)
    }
    .buttonStyle(.plain)
  }

  /// 下载任务玻璃横卡：上方缩略图与完整标题/下载器信息，中部全宽速率与流光进度条，底部体积/剩余时间与快捷控制。
  private func downloadRow(_ task: NativeDownloadTask) -> some View {
    let artworkURL = NativeMediaDetailPage.resolveArtwork(
      task.media?.backdrop ?? task.media?.image ?? task.media?.poster,
      source: task.media?.mediaSource ?? "themoviedb")
    let isMutating = mutatingHash == task.hash
    let progressTint: Color = task.isPaused ? NativeTheme.badgeMutedText : appearance.accentColor
    return CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .top, spacing: 12) {
          Group {
            if let identity = task.detailIdentity {
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: identity)
              } label: {
                thumbnail(url: artworkURL, isPaused: task.isPaused)
              }
              .buttonStyle(.plain)
            } else {
              thumbnail(url: artworkURL, isPaused: task.isPaused)
            }
          }
          VStack(alignment: .leading, spacing: 6) {
            if let identity = task.detailIdentity {
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: identity)
              } label: {
                Text(task.displayTitle)
                  .font(.headline)
                  .foregroundStyle(.primary)
                  .lineLimit(2)
                  .multilineTextAlignment(.leading)
              }
              .buttonStyle(.plain)
            } else {
              Text(task.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
              if let downloader = task.downloader, !downloader.isEmpty {
                HStack(spacing: 4) {
                  NativeBrandIcon(
                    kind: .downloader, type: downloader, size: 14, cornerRadius: 3.5)
                  Text(downloader)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.86))
                    .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                  Capsule()
                    .fill(.primary.opacity(colorScheme == .dark ? 0.11 : 0.08))
                    .overlay {
                      Capsule().strokeBorder(.primary.opacity(0.14), lineWidth: 0.5)
                    }
                }
              }
              if let sourceLabel = task.sourceSummary {
                Text(sourceLabel)
                  .font(.caption)
                  .foregroundStyle(.primary.opacity(0.64))
                  .lineLimit(1)
                  .truncationMode(.tail)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            if task.isPaused {
              HStack(spacing: 4) {
                Image(systemName: "pause.circle.fill")
                  .font(.caption)
                Text("已暂停")
                  .font(.caption.weight(.medium))
              }
              .foregroundStyle(NativeTheme.badgeMutedText)
            } else {
              HStack(spacing: 10) {
                HStack(spacing: 3) {
                  Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(appearance.accentColor)
                  Text(task.formattedDownSpeed)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.90))
                }
                HStack(spacing: 3) {
                  Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.46))
                  Text(task.formattedUpSpeed)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.58))
                }
              }
              .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(task.percentText)
              .font(.subheadline.weight(.semibold).monospacedDigit())
              .foregroundStyle(.primary.opacity(task.isPaused ? 0.58 : 0.94))
          }

          GeometryReader { bar in
            let fillWidth =
              task.clampedProgress > 0
              ? max(bar.size.width * task.clampedProgress, 6)
              : 0
            ZStack(alignment: .leading) {
              Capsule()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10))
              if fillWidth > 0 {
                Capsule()
                  .fill(
                    LinearGradient(
                      colors: [progressTint.opacity(0.74), progressTint],
                      startPoint: .leading,
                      endPoint: .trailing
                    )
                  )
                  .frame(width: min(fillWidth, bar.size.width))
              }
            }
          }
          .frame(height: 5.5)
        }

        HStack(alignment: .center, spacing: 8) {
          Text(task.footerMetaLine)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.primary.opacity(0.62))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 6)
          if canManage {
            HStack(spacing: 8) {
              Button {
                Task { await toggleTaskState(task) }
              } label: {
                HStack(spacing: 4) {
                  if isMutating {
                    ProgressView().controlSize(.mini).tint(.primary)
                  } else {
                    Image(systemName: task.isPaused ? "play.fill" : "pause.fill")
                      .font(.caption2.weight(.semibold))
                  }
                  Text(task.isPaused ? "继续" : "暂停")
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background {
                  Capsule()
                    .fill(.primary.opacity(colorScheme == .dark ? 0.14 : 0.09))
                    .overlay {
                      Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6)
                    }
                }
                .frame(minHeight: 32)
              }
              .buttonStyle(.plain)
              .disabled(mutatingHash != nil)
              .accessibilityIdentifier("native-download-toggle-\(task.hash)")

              Button {
                pendingDelete = task
              } label: {
                Image(systemName: "trash")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.primary.opacity(0.72))
                  .frame(width: 32, height: 32)
                  .background {
                    Circle()
                      .fill(.primary.opacity(colorScheme == .dark ? 0.11 : 0.07))
                      .overlay {
                        Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.6)
                      }
                  }
              }
              .buttonStyle(.plain)
              .disabled(mutatingHash != nil)
              .accessibilityLabel("删除任务")
              .accessibilityIdentifier("native-download-delete-\(task.hash)")
            }
          }
        }
      }
    }
    .contextMenu {
      Button {
        Task { await toggleTaskState(task) }
      } label: {
        Label(
          task.isPaused ? "恢复下载" : "暂停下载", systemImage: task.isPaused ? "play.fill" : "pause.fill")
      }
      Button(role: .destructive) {
        pendingDelete = task
      } label: {
        Label("删除任务", systemImage: "trash")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-download-card-\(task.hash)")
  }

  /// 16:9 紧凑剧照缩略图，避免挤压标题区域，仅在暂停态展示柔和居中状态徽章。
  private func thumbnail(url: String?, isPaused: Bool) -> some View {
    ZStack {
      NativeMediaArtwork(
        session: session, reference: url, role: .continueWatching, maximumWidth: 320
      )
      .frame(width: 92, height: 56)
      .clipped()
      if isPaused {
        Color.black.opacity(0.38)
        Image(systemName: "pause.fill")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white.opacity(0.92))
          .padding(7)
          .background(.black.opacity(0.45), in: Circle())
      }
    }
    .frame(width: 92, height: 56)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(.primary.opacity(0.14), lineWidth: 0.6)
    }
  }

  /// 操作结果轻量提示条。
  private func feedbackBanner(_ feedback: NativeDownloadFeedback) -> some View {
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
    .accessibilityIdentifier("native-downloads-feedback")
  }

  /// 当前无活跃下载时的空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "arrow.down.circle")
          .font(.largeTitle)
          .foregroundStyle(.primary.opacity(0.55))
        Text("当前没有正在下载的任务").font(.headline)
        Text("新添加的种子或订阅下载会实时显示在这里。")
          .font(.footnote)
          .foregroundStyle(.primary.opacity(0.65))
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
    .accessibilityIdentifier("native-downloads-empty")
  }

  /// 读取失败回退卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法读取下载任务", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-downloads-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 并行拉取已启用下载器清单与活跃任务列表；先展示缓存快照消除闪烁，同时始终拉取最新实时下载队列。
  private func load(forceRefresh: Bool = false, silent: Bool = false) async {
    let cacheKey = "downloads|\(selectedClient ?? "all")"
    if tasks.isEmpty,
      let cached: (clients: [NativeDownloaderClient], tasks: [NativeDownloadTask]) =
        NativePageDataCache.shared.get(cacheKey, session: session)
    {
      clients = cached.clients
      tasks = cached.tasks
      isLoading = false
      loadFailed = false
    }
    if tasks.isEmpty && !silent { isLoading = true }
    if !silent { loadFailed = false }
    defer { if !silent { isLoading = false } }
    do {
      let clientsEndpoint = try APIEndpoint(path: ["download", "clients"])
      let query = selectedClient.map { [URLQueryItem(name: "name", value: $0)] } ?? []
      let tasksEndpoint = try APIEndpoint(path: ["download"], query: query, trailingSlash: true)
      async let loadedClients = try? session.request(
        clientsEndpoint, as: [NativeDownloaderClient].self
      ).value
      let loadedTasks = try await session.request(
        tasksEndpoint, as: [NativeLossyDownloadTask].self
      ).value.compactMap(\.value)
      let resolvedClients = await loadedClients
      try Task.checkCancellation()
      if let resolvedClients { clients = resolvedClients }
      tasks = loadedTasks
      loadFailed = false
      NativePageDataCache.shared.set(
        (clients: clients, tasks: loadedTasks), for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if tasks.isEmpty && !silent { loadFailed = true }
    }
  }

  /// 显式执行单次启动或暂停请求，完成后重新拉取任务快照。
  private func toggleTaskState(_ task: NativeDownloadTask) async {
    guard canManage else { return }
    mutatingHash = task.hash
    defer { mutatingHash = nil }
    let action = task.isPaused ? "start" : "stop"
    do {
      let query = task.downloader.map { [URLQueryItem(name: "name", value: $0)] } ?? []
      let endpoint = try APIEndpoint(path: ["download", action, task.hash], query: query)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      feedback = NativeDownloadFeedback(
        isError: false, message: task.isPaused ? "已发送继续下载指令。" : "已发送暂停下载指令。")
      await load(forceRefresh: true)
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeDownloadFeedback(isError: true, message: "更新任务状态失败，请稍后重试。")
    }
  }

  /// 二次确认后单次提交删除任务。
  private func deleteTask(_ task: NativeDownloadTask) async {
    guard canManage else { return }
    mutatingHash = task.hash
    defer { mutatingHash = nil }
    do {
      let query = task.downloader.map { [URLQueryItem(name: "name", value: $0)] } ?? []
      let endpoint = try APIEndpoint(
        path: ["download", task.hash], method: .delete, query: query)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      tasks.removeAll { $0.hash == task.hash }
      feedback = NativeDownloadFeedback(isError: false, message: "已删除下载任务。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeDownloadFeedback(isError: true, message: "删除下载任务失败，请稍后重试。")
    }
  }
}

/// 下载操作提示载体。
private struct NativeDownloadFeedback {
  let isError: Bool
  let message: String
}

/// 下载器客户端基础投影。
private struct NativeDownloaderClient: Decodable, Sendable, Identifiable {
  let name: String
  let type: String?

  /// 下载器名称作为筛选标识。
  var id: String { name }
}

/// 宽容列表元素包装，避免单条任务字段异构导致整个下载列表解码失败。
private struct NativeLossyDownloadTask: Decodable, Sendable {
  let value: NativeDownloadTask?
  init(from decoder: Decoder) throws {
    value = try? NativeDownloadTask(from: decoder)
  }
}

/// `GET /api/v1/download/` 单条任务投影（宽容解码后端 `int | list[int] | str` 混合季集与数值字段）。
private struct NativeDownloadTask: Decodable, Sendable, Identifiable {
  /// 任务绑定的媒体摘要信息。
  struct Media: Decodable, Sendable {
    let type: String?
    let title: String?
    let season: String?
    let episode: String?
    let image: String?
    let poster: String?
    let backdrop: String?
    let mediaSource: String?
    let mediaID: String?

    /// 对应 `DownloaderTorrent.media` 字段。
    private enum CodingKeys: String, CodingKey {
      case type
      case title
      case season
      case episode
      case image
      case poster
      case backdrop
      case mediaSource = "media_source"
      case mediaID = "media_id"
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      type = try? c.decodeIfPresent(String.self, forKey: .type)
      title = try? c.decodeIfPresent(String.self, forKey: .title)
      season = Self.decodeSeasonEpisode(c, forKey: .season, prefix: "S")
      episode = Self.decodeSeasonEpisode(c, forKey: .episode, prefix: "E")
      image = try? c.decodeIfPresent(String.self, forKey: .image)
      poster = try? c.decodeIfPresent(String.self, forKey: .poster)
      backdrop = try? c.decodeIfPresent(String.self, forKey: .backdrop)
      mediaSource = try? c.decodeIfPresent(String.self, forKey: .mediaSource)
      if let s = try? c.decodeIfPresent(String.self, forKey: .mediaID) {
        mediaID = s
      } else if let n = try? c.decodeIfPresent(Int64.self, forKey: .mediaID) {
        mediaID = String(n)
      } else {
        mediaID = nil
      }
    }

    private static func decodeSeasonEpisode(
      _ container: KeyedDecodingContainer<CodingKeys>,
      forKey key: CodingKeys,
      prefix: String
    ) -> String? {
      if let text = try? container.decodeIfPresent(String.self, forKey: key) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
      if let num = try? container.decodeIfPresent(Int.self, forKey: key) {
        return String(format: "%@%02d", prefix, num)
      }
      if let list = try? container.decodeIfPresent([Int].self, forKey: key), !list.isEmpty {
        let sorted = list.sorted()
        if sorted.count == 1 {
          return String(format: "%@%02d", prefix, sorted[0])
        }
        return String(format: "%@%02d-%@%02d", prefix, sorted.first!, prefix, sorted.last!)
      }
      if let strList = try? container.decodeIfPresent([String].self, forKey: key) {
        let joined = strList.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .joined(separator: ",")
        return joined.isEmpty ? nil : joined
      }
      return nil
    }
  }

  let downloader: String?
  let hash: String
  let title: String?
  let name: String?
  let year: String?
  let seasonEpisode: String?
  let siteName: String?
  let size: Double?
  let progress: Double?
  let state: String?
  let upspeed: String?
  let dlspeed: String?
  let leftTime: String?
  let media: Media?

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    downloader = try? c.decodeIfPresent(String.self, forKey: .downloader)
    title = try? c.decodeIfPresent(String.self, forKey: .title)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    let rawHash = (try? c.decodeIfPresent(String.self, forKey: .hash))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let rawHash, !rawHash.isEmpty {
      hash = rawHash
    } else {
      hash = "\(downloader ?? "")|\(title ?? name ?? UUID().uuidString)"
    }
    if let y = try? c.decodeIfPresent(String.self, forKey: .year) {
      year = y
    } else if let yInt = try? c.decodeIfPresent(Int.self, forKey: .year) {
      year = String(yInt)
    } else {
      year = nil
    }
    seasonEpisode = try? c.decodeIfPresent(String.self, forKey: .seasonEpisode)
    siteName = try? c.decodeIfPresent(String.self, forKey: .siteName)
    if let s = try? c.decodeIfPresent(Double.self, forKey: .size) {
      size = s
    } else if let sStr = try? c.decodeIfPresent(String.self, forKey: .size), let s = Double(sStr) {
      size = s
    } else {
      size = nil
    }
    if let p = try? c.decodeIfPresent(Double.self, forKey: .progress) {
      progress = p
    } else if let pStr = try? c.decodeIfPresent(String.self, forKey: .progress),
      let p = Double(pStr)
    {
      progress = p
    } else {
      progress = nil
    }
    state = try? c.decodeIfPresent(String.self, forKey: .state)
    upspeed = Self.decodeSpeedString(c, forKey: .upspeed)
    dlspeed = Self.decodeSpeedString(c, forKey: .dlspeed)
    leftTime = try? c.decodeIfPresent(String.self, forKey: .leftTime)
    media = try? c.decodeIfPresent(Media.self, forKey: .media)
  }

  private static func decodeSpeedString(
    _ container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) -> String? {
    if let text = try? container.decodeIfPresent(String.self, forKey: key) {
      return text
    }
    if let bytesPerSec = try? container.decodeIfPresent(Double.self, forKey: key) {
      return bytesPerSec <= 0 ? "0B" : Self.formatBytes(bytesPerSec)
    }
    return nil
  }

  /// 种子哈希作为唯一行标识。
  var id: String { hash }

  /// 是否处于暂停状态。
  var isPaused: Bool {
    let normalized = (state ?? "").lowercased()
    return normalized == "unavailable" || normalized.contains("pause")
      || normalized.contains("stop")
  }

  /// 0...1 范围内的进度值。
  var clampedProgress: Double {
    let raw = progress ?? 0
    let fraction = raw > 1 ? raw / 100.0 : raw
    return min(max(fraction, 0), 1)
  }

  /// 优先展示识别后的作品名与季集。
  var displayTitle: String {
    let base =
      media?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? name?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? title?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? "下载任务"
    let suffix = [media?.season ?? seasonEpisode, media?.episode]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return suffix.isEmpty ? base : "\(base) \(suffix)"
  }

  /// 标题下方的站点与年份补充摘要。
  var sourceSummary: String? {
    var parts: [String] = []
    if let siteName, !siteName.isEmpty { parts.append(siteName) }
    if let year, !year.isEmpty { parts.append(year) }
    if parts.isEmpty, let rawTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawTitle.isEmpty, rawTitle != displayTitle
    {
      return rawTitle
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// 右侧进度百分比文案。
  var percentText: String {
    String(format: "%.1f%%", clampedProgress * 100)
  }

  /// 底部体积与剩余时间汇总（展示已下 / 总大小及预计剩余时间）。
  var footerMetaLine: String {
    var parts: [String] = []
    if let size, size > 0 {
      let downloaded = size * clampedProgress
      parts.append("\(Self.formatBytes(downloaded)) / \(Self.formatBytes(size))")
    }
    if !isPaused, let leftTime, !leftTime.isEmpty {
      parts.append("剩余 \(leftTime)")
    }
    if parts.isEmpty {
      return isPaused ? "已暂停" : "队列中"
    }
    return parts.joined(separator: " · ")
  }

  /// 格式化下载速率（兼容已带 `/s` 后缀的字符串）。
  var formattedDownSpeed: String {
    Self.normalizeRate(dlspeed)
  }

  /// 格式化上传速率（兼容已带 `/s` 后缀的字符串）。
  var formattedUpSpeed: String {
    Self.normalizeRate(upspeed)
  }

  private static func normalizeRate(_ raw: String?) -> String {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "0B/s" }
    if trimmed.lowercased().hasSuffix("/s") {
      return trimmed
    }
    return "\(trimmed)/s"
  }

  /// 仅当任务绑定有效影视主身份时提供详情跳转。
  var detailIdentity: NativeMediaIdentity? {
    guard let media, let source = media.mediaSource, !source.isEmpty,
      let mediaID = media.mediaID, !mediaID.isEmpty,
      let type = media.type, ["电影", "电视剧"].contains(type)
    else { return nil }
    return NativeMediaIdentity(source: source, mediaID: mediaID, type: type)
  }

  /// 格式化字节数为人类可读体积。
  private static func formatBytes(_ bytes: Double) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = bytes
    var index = 0
    while value >= 1024 && index < units.count - 1 {
      value /= 1024
      index += 1
    }
    return String(format: "%.1f %@", value, units[index])
  }

  /// 对应后端 `DownloaderTorrent` 字段。
  private enum CodingKeys: String, CodingKey {
    case downloader
    case hash
    case title
    case name
    case year
    case seasonEpisode = "season_episode"
    case siteName = "site_name"
    case size
    case progress
    case state
    case upspeed
    case dlspeed
    case leftTime = "left_time"
    case media
  }
}
