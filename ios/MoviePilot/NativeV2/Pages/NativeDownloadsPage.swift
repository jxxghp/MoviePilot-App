import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生下载管理页：参照深色渐变玻璃任务横卡，直连 MoviePilot 下载器查询与启停删控制。
@MainActor
struct NativeDownloadsPage: View {
  let session: NativeSession

  @State private var clients: [NativeDownloaderClient] = []
  @State private var selectedClient: String?
  @State private var tasks: [NativeDownloadTask] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var mutatingHash: String?
  @State private var pendingDelete: NativeDownloadTask?
  @State private var feedback: NativeDownloadFeedback?

  /// 连续紫玫瑰渐变背景、下载器筛选胶囊、16:9 缩略图进度玻璃卡与原生刷新工具栏。
  var body: some View {
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
            ProgressView("正在读取下载队列…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && tasks.isEmpty {
            failureCard
          } else if tasks.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 14) {
              ForEach(tasks) { task in
                downloadRow(task)
              }
            }
          }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-downloads-scroll")
    }
    .navigationTitle("正在下载")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          attempt += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("刷新下载任务")
        .accessibilityIdentifier("native-downloads-refresh")
      }
    }
    .task(id: "\(attempt)|\(selectedClient ?? "")") { await load() }
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
        .foregroundStyle(.white.opacity(selected ? 0.98 : 0.78))
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background {
          Capsule()
            .fill(.white.opacity(selected ? 0.22 : 0.08))
            .overlay {
              Capsule().strokeBorder(.white.opacity(selected ? 0.28 : 0.14), lineWidth: 0.6)
            }
        }
        .frame(minHeight: 38)
    }
    .buttonStyle(.plain)
  }

  /// 下载任务玻璃横卡：左侧 16:9 媒体画面与进度覆层，右侧片名、速度/剩余时间、进度条与控制动作。
  private func downloadRow(_ task: NativeDownloadTask) -> some View {
    let artworkURL = NativeMediaDetailPage.resolveArtwork(
      task.media?.backdrop ?? task.media?.image ?? task.media?.poster,
      source: task.media?.mediaSource ?? "themoviedb")
    let isMutating = mutatingHash == task.hash
    return CinematicPanel(padding: 12) {
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .top, spacing: 12) {
          thumbnail(url: artworkURL, progress: task.clampedProgress, isPaused: task.isPaused)
          VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              if let identity = task.detailIdentity {
                NavigationLink {
                  NativeMediaDetailPage(session: session, identity: identity)
                } label: {
                  Text(task.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
              } else {
                Text(task.displayTitle)
                  .font(.headline)
                  .foregroundStyle(.white)
                  .lineLimit(1)
              }
              Spacer(minLength: 4)
              if let downloader = task.downloader, !downloader.isEmpty {
                Text(downloader)
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.white.opacity(0.82))
                  .padding(.horizontal, 7)
                  .padding(.vertical, 3)
                  .background {
                    Capsule().fill(.white.opacity(0.12))
                  }
              }
            }
            Text(task.subtitleLine)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.66))
              .lineLimit(1)
            Text(task.speedLine)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.white.opacity(0.84))
              .lineLimit(1)
            GeometryReader { bar in
              ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                  .fill(
                    task.isPaused
                      ? Color.white.opacity(0.45) : Color.white.opacity(0.92)
                  )
                  .frame(width: max(bar.size.width * task.clampedProgress, 4))
              }
            }
            .frame(height: 3.5)
            .padding(.top, 2)
          }
        }
        if canManage {
          HStack(spacing: 10) {
            Button {
              Task { await toggleTaskState(task) }
            } label: {
              HStack(spacing: 5) {
                if isMutating {
                  ProgressView().controlSize(.mini).tint(.white)
                } else {
                  Image(systemName: task.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption2.weight(.semibold))
                }
                Text(task.isPaused ? "继续" : "暂停")
                  .font(.caption.weight(.semibold))
              }
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background {
                Capsule()
                  .fill(.white.opacity(0.14))
                  .overlay { Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.6) }
              }
              .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .disabled(mutatingHash != nil)
            .accessibilityIdentifier("native-download-toggle-\(task.hash)")
            Spacer()
            Button(role: .destructive) {
              pendingDelete = task
            } label: {
              Label("删除", systemImage: "trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.58))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
            .disabled(mutatingHash != nil)
            .accessibilityIdentifier("native-download-delete-\(task.hash)")
          }
        }
      }
    }
  }

  /// 16:9 媒体缩略图带底部柔和渐暗与百分比进度条覆层。
  private func thumbnail(url: String?, progress: Double, isPaused: Bool) -> some View {
    ZStack(alignment: .bottomLeading) {
      NativeMediaArtwork(
        session: session, reference: url, role: .continueWatching, maximumWidth: 360
      )
      .frame(width: 126, height: 74)
      .clipped()
      LinearGradient(
        colors: [.clear, .black.opacity(0.74)], startPoint: .center, endPoint: .bottom)
      HStack(spacing: 4) {
        Image(systemName: isPaused ? "pause.fill" : "arrow.down")
          .font(.system(size: 8, weight: .bold))
        Text(String(format: "%.1f%%", progress * 100))
          .font(.system(size: 11, weight: .semibold).monospacedDigit())
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 7)
      .padding(.bottom, 5)
    }
    .frame(width: 126, height: 74)
    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
    }
  }

  /// 操作结果轻量提示条。
  private func feedbackBanner(_ feedback: NativeDownloadFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : Color(red: 0.56, green: 0.92, blue: 0.72))
        Text(feedback.message).font(.subheadline).foregroundStyle(.white.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.65)).frame(minWidth: 32, minHeight: 32)
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
          .foregroundStyle(.white.opacity(0.55))
        Text("当前没有正在下载的任务").font(.headline)
        Text("新添加的种子或订阅下载会实时显示在这里。")
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.65))
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

  /// 并行拉取已启用下载器清单与活跃任务列表。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let clientsEndpoint = try APIEndpoint(path: ["download", "clients"])
      let query = selectedClient.map { [URLQueryItem(name: "name", value: $0)] } ?? []
      let tasksEndpoint = try APIEndpoint(path: ["download"], query: query, trailingSlash: true)
      async let loadedClients = try? session.request(
        clientsEndpoint, as: [NativeDownloaderClient].self
      ).value
      let loadedTasks = try await session.request(tasksEndpoint, as: [NativeDownloadTask].self)
        .value
      let resolvedClients = await loadedClients
      try Task.checkCancellation()
      if let resolvedClients { clients = resolvedClients }
      tasks = loadedTasks
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
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
      await load()
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

/// `GET /api/v1/download/` 单条任务投影。
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

  /// 副标展示站点、总大小与剩余时间。
  var subtitleLine: String {
    var parts: [String] = []
    if let siteName, !siteName.isEmpty { parts.append(siteName) }
    if let size, size > 0 { parts.append(Self.formatBytes(size)) }
    if let leftTime, !leftTime.isEmpty { parts.append("剩余 \(leftTime)") }
    return parts.isEmpty ? (title ?? "队列中") : parts.joined(separator: " · ")
  }

  /// 速率与实时状态文本。
  var speedLine: String {
    if isPaused { return "已暂停" }
    let down = dlspeed?.isEmpty == false ? dlspeed! : "0B"
    let up = upspeed?.isEmpty == false ? upspeed! : "0B"
    return "↓ \(down)/s   ↑ \(up)/s"
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
