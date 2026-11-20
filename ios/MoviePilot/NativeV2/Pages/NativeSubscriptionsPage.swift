import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生订阅中心：分类浏览电影、电视剧与音乐订阅，支持进度展示、暂停/恢复、触发搜索与确认取消。
@MainActor
struct NativeSubscriptionsPage: View {
  /// 订阅列表的分类筛选维度。
  private enum Filter: String, CaseIterable, Identifiable {
    case all = "全部"
    case movie = "电影"
    case tv = "电视剧"
    case music = "音乐"

    /// 使用固定中文标签作为标识。
    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var items: [NativeSubscribeItem] = []
  @State private var filter: Filter = .all
  @State private var searchText = ""
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var mutatingID: Int?
  @State private var pendingDelete: NativeSubscribeItem?
  @State private var feedback: NativeSubscribeFeedback?

  /// 采用统一深色紫玫瑰渐变与透色海报玻璃卡，卡片可直达原生影视详情页。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          filterBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && items.isEmpty {
            ProgressView("正在载入订阅列表…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && items.isEmpty {
            failureCard
          } else if filteredItems.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 12) {
              ForEach(filteredItems) { item in
                subscribeCard(item)
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
      .accessibilityIdentifier("native-subscriptions-scroll")
    }
    .navigationTitle("我的订阅")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(text: $searchText, prompt: "筛选订阅片名")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          attempt += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("刷新订阅")
        .accessibilityIdentifier("native-subscriptions-refresh")
      }
    }
    .task(id: attempt) { await load() }
    .alert(
      "取消订阅",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { item in
      Button("取消订阅", role: .destructive) {
        Task { await deleteSubscribe(item) }
      }
      Button("保留", role: .cancel) {}
    } message: { item in
      Text("确认删除「\(item.displayTitle)」订阅吗？")
    }
  }

  /// 按所选类型与关键字过滤后的订阅列表。
  private var filteredItems: [NativeSubscribeItem] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return items.filter { item in
      let matchesKind: Bool =
        switch filter {
        case .all: true
        case .movie: item.type == "电影"
        case .tv: item.type == "电视剧"
        case .music: item.type == "音乐"
        }
      guard matchesKind else { return false }
      guard !trimmed.isEmpty else { return true }
      return item.displayTitle.lowercased().contains(trimmed)
    }
  }

  /// 顶部分类胶囊筛选栏，同时展示各分类真实条数。
  private var filterBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(Filter.allCases) { option in
          let count = countFor(option)
          let selected = filter == option
          Button {
            filter = option
          } label: {
            Text(count > 0 ? "\(option.rawValue) \(count)" : option.rawValue)
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
          .accessibilityIdentifier("native-subscriptions-filter-\(option.rawValue)")
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  /// 统计单个分类下的真实订阅条目数。
  private func countFor(_ option: Filter) -> Int {
    switch option {
    case .all: items.count
    case .movie: items.filter { $0.type == "电影" }.count
    case .tv: items.filter { $0.type == "电视剧" }.count
    case .music: items.filter { $0.type == "音乐" }.count
    }
  }

  /// 单条订阅透色玻璃卡片：2:3 竖版海报、状态/进度与原生上下文动作。
  private func subscribeCard(_ item: NativeSubscribeItem) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      item.poster, source: item.mediaSource ?? "themoviedb")
    let isMutating = mutatingID == item.id
    return CinematicPanel(padding: 12) {
      HStack(alignment: .top, spacing: 13) {
        Group {
          if let identity = item.detailIdentity {
            NavigationLink {
              NativeMediaDetailPage(session: session, identity: identity)
            } label: {
              posterView(poster)
            }
            .buttonStyle(.plain)
          } else {
            posterView(poster)
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 8) {
            if let identity = item.detailIdentity {
              NavigationLink {
                NativeMediaDetailPage(session: session, identity: identity)
              } label: {
                Text(item.displayTitle)
                  .font(.headline)
                  .foregroundStyle(.white)
                  .lineLimit(2)
                  .multilineTextAlignment(.leading)
              }
              .buttonStyle(.plain)
            } else {
              Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            }
            Spacer(minLength: 4)
            stateBadge(item)
          }
          HStack(spacing: 8) {
            if let year = item.year, !year.isEmpty {
              Text(year).font(.caption).foregroundStyle(.white.opacity(0.66))
            }
            if let type = item.type, !type.isEmpty {
              Text(type).font(.caption).foregroundStyle(.white.opacity(0.66))
            }
            if let vote = item.vote, vote > 0 {
              Label(String(format: "%.1f", vote), systemImage: "star.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
            }
          }
          if let progress = item.episodeProgress {
            VStack(alignment: .leading, spacing: 4) {
              Text("已更新 \(progress.completed) / \(progress.total) 集")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.80))
              GeometryReader { bar in
                ZStack(alignment: .leading) {
                  Capsule().fill(.white.opacity(0.16))
                  Capsule()
                    .fill(Color(red: 0.72, green: 0.56, blue: 0.96))
                    .frame(width: max(bar.size.width * progress.fraction, 4))
                }
              }
              .frame(height: 3.5)
            }
            .padding(.top, 2)
          }
          HStack(spacing: 10) {
            Button {
              Task { await toggleStatus(item) }
            } label: {
              HStack(spacing: 4) {
                if isMutating {
                  ProgressView().controlSize(.mini).tint(.white)
                } else {
                  Image(systemName: item.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption2.weight(.semibold))
                }
                Text(item.isPaused ? "恢复" : "暂停").font(.caption.weight(.semibold))
              }
              .foregroundStyle(.white)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background {
                Capsule()
                  .fill(.white.opacity(0.13))
                  .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6) }
              }
              .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(mutatingID != nil)
            .accessibilityIdentifier("native-subscribe-toggle-\(item.id)")

            Button(role: .destructive) {
              pendingDelete = item
            } label: {
              Image(systemName: "trash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.58))
                .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(mutatingID != nil)
            .accessibilityLabel("删除订阅 \(item.displayTitle)")
            .accessibilityIdentifier("native-subscribe-delete-\(item.id)")
            Spacer()
          }
          .padding(.top, 2)
        }
      }
    }
  }

  /// 2:3 竖版海报，沿用全应用统一的 420px 内存缓存档位。
  private func posterView(_ reference: String?) -> some View {
    NativeMediaArtwork(session: session, reference: reference, role: .poster, maximumWidth: 420)
      .frame(width: 68, height: 102)
      .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
      }
  }

  /// 订阅运行状态徽标。
  private func stateBadge(_ item: NativeSubscribeItem) -> some View {
    let text = item.isPaused ? "已暂停" : (item.bestVersion == 1 ? "洗版" : "订阅中")
    let tint: Color =
      item.isPaused
      ? Color.white.opacity(0.55)
      : (item.bestVersion == 1
        ? Color(red: 0.96, green: 0.78, blue: 0.45)
        : Color(red: 0.56, green: 0.92, blue: 0.72))
    return Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background {
        Capsule()
          .fill(.white.opacity(0.10))
          .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.6) }
      }
  }

  /// 轻量反馈提示条。
  private func feedbackBanner(_ feedback: NativeSubscribeFeedback) -> some View {
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
    .accessibilityIdentifier("native-subscriptions-feedback")
  }

  /// 无订阅空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "bookmark")
          .font(.largeTitle)
          .foregroundStyle(.white.opacity(0.55))
        Text("暂无匹配的订阅").font(.headline)
        Text("你可以在发现页或媒体详情中一键添加订阅。")
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.65))
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 载入失败重试卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入订阅列表", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-subscriptions-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 从 `GET /api/v1/subscribe/` 拉取当前用户可见的全部订阅。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["subscribe"], trailingSlash: true)
      let loaded = try await session.request(
        endpoint, as: [NativeSubscribeItem].self, requiring: .init(category: .subscribe)
      ).value
      try Task.checkCancellation()
      items = loaded
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 单次切换订阅暂停/恢复状态（`PUT /api/v1/subscribe/status/{id}?state=S|R`）。
  private func toggleStatus(_ item: NativeSubscribeItem) async {
    mutatingID = item.id
    defer { mutatingID = nil }
    let nextState = item.isPaused ? "R" : "S"
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", "status", String(item.id)],
        method: .put,
        query: [URLQueryItem(name: "state", value: nextState)])
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      if let index = items.firstIndex(where: { $0.id == item.id }) {
        items[index].state = nextState
      }
      feedback = NativeSubscribeFeedback(
        isError: false, message: nextState == "S" ? "已暂停订阅。" : "已恢复订阅。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeSubscribeFeedback(isError: true, message: "更新订阅状态失败，请稍后重试。")
    }
  }

  /// 二次确认后单次删除订阅（`DELETE /api/v1/subscribe/{id}`）。
  private func deleteSubscribe(_ item: NativeSubscribeItem) async {
    mutatingID = item.id
    defer { mutatingID = nil }
    do {
      let endpoint = try APIEndpoint(
        path: ["subscribe", String(item.id)], method: .delete)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      items.removeAll { $0.id == item.id }
      feedback = NativeSubscribeFeedback(isError: false, message: "已取消订阅。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeSubscribeFeedback(isError: true, message: "取消订阅失败，请稍后重试。")
    }
  }
}

/// 订阅操作结果提示。
private struct NativeSubscribeFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/subscribe/` 单条订阅投影。
private struct NativeSubscribeItem: Decodable, Sendable, Identifiable {
  /// 剧集更新进度结构。
  struct EpisodeProgress {
    let completed: Int
    let total: Int
    /// 0...1 进度比例。
    var fraction: Double { total > 0 ? min(max(Double(completed) / Double(total), 0), 1) : 0 }
  }

  let id: Int
  let name: String
  let year: String?
  let type: String?
  let season: Int?
  let poster: String?
  let mediaSource: String?
  let mediaID: String?
  var state: String?
  let vote: Double?
  let totalEpisode: Int?
  let lackEpisode: Int?
  let completedEpisode: Int?
  let bestVersion: Int?

  /// 标题附带季号。
  var displayTitle: String {
    if let season, type == "电视剧" {
      return "\(name) S\(String(format: "%02d", season))"
    }
    return name
  }

  /// `S` 表示暂停。
  var isPaused: Bool { (state ?? "R").uppercased() == "S" }

  /// 剧集集数进度（优先使用后端派生 `completed_episode`）。
  var episodeProgress: EpisodeProgress? {
    guard type == "电视剧", let total = totalEpisode, total > 0 else { return nil }
    let completed = completedEpisode ?? max(total - (lackEpisode ?? 0), 0)
    return EpisodeProgress(completed: completed, total: total)
  }

  /// 具备规范影视身份时允许直接进入原生详情页。
  var detailIdentity: NativeMediaIdentity? {
    guard let type, ["电影", "电视剧"].contains(type),
      let source = mediaSource, !source.isEmpty,
      let mediaID, !mediaID.isEmpty
    else { return nil }
    return NativeMediaIdentity(source: source, mediaID: mediaID, type: type)
  }

  /// 对应 `_SchemaSubscribe` 字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case year
    case type
    case season
    case poster
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case state
    case vote
    case totalEpisode = "total_episode"
    case lackEpisode = "lack_episode"
    case completedEpisode = "completed_episode"
    case bestVersion = "best_version"
  }
}
