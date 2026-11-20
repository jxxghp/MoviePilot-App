import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生整理历史页：分页查询整理记录、按状态/片名筛选、查看源/目标路径与失败原因、确认删除记录。
@MainActor
struct NativeTransferHistoryPage: View {
  /// 整理记录状态筛选。
  private enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case success = "成功"
    case failed = "失败"

    /// 固定中文标签作为标识。
    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var records: [NativeTransferRecord] = []
  @State private var total = 0
  @State private var nextPage = 1
  @State private var hasMore = false
  @State private var filter: StatusFilter = .all
  @State private var searchText = ""
  @State private var expandedIDs: Set<Int> = []
  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var pendingDelete: NativeTransferRecord?
  @State private var feedback: NativeHistoryFeedback?

  /// 连续紫玫瑰渐变背景、状态筛选胶囊、带海报的透色记录卡与自动翻页。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          filterBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && records.isEmpty {
            ProgressView("正在载入整理记录…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && records.isEmpty {
            failureCard
          } else if displayedRecords.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 12) {
              ForEach(Array(displayedRecords.enumerated()), id: \.element.id) { index, record in
                recordCard(record)
                  .onAppear { loadMoreIfNeeded(at: index) }
              }
              if isLoadingMore {
                ProgressView("正在载入更多…")
                  .tint(.white)
                  .padding(.vertical, 12)
              }
            }
          }
        }
        .frame(maxWidth: 840)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await reload() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-history-scroll")
    }
    .navigationTitle(total > 0 ? "整理历史 (\(total))" : "整理历史")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .searchable(text: $searchText, prompt: "按片名筛选整理记录")
    .onSubmit(of: .search) { attempt += 1 }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          attempt += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("刷新整理历史")
        .accessibilityIdentifier("native-history-refresh")
      }
    }
    .task(id: attempt) { await reload() }
    .alert(
      "删除整理记录",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { record in
      Button("仅删除记录", role: .destructive) {
        Task { await deleteRecord(record) }
      }
      Button("取消", role: .cancel) {}
    } message: { record in
      Text("确认删除「\(record.displayTitle)」的整理记录吗？（不会删除磁盘上的源文件和媒体库文件）")
    }
  }

  /// 当前用户具备管理权限时允许删除整理记录。
  private var canManage: Bool {
    session.user.isSuperuser || session.user.allows(.init(category: .manage))
  }

  /// 经本地状态过滤后的可见列表。
  private var displayedRecords: [NativeTransferRecord] {
    records.filter { record in
      switch filter {
      case .all: true
      case .success: record.status == true
      case .failed: record.status == false
      }
    }
  }

  /// 状态筛选胶囊栏。
  private var filterBar: some View {
    HStack(spacing: 8) {
      ForEach(StatusFilter.allCases) { option in
        let selected = filter == option
        Button {
          filter = option
        } label: {
          Text(option.rawValue)
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
            .frame(minHeight: 36)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-history-filter-\(option.rawValue)")
      }
      Spacer()
    }
  }

  /// 单条整理记录玻璃卡片：海报、状态徽标、整理方式/时间、可展开路径详情与安全删除按钮。
  private func recordCard(_ record: NativeTransferRecord) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      record.image, source: record.mediaSource ?? "themoviedb")
    let expanded = expandedIDs.contains(record.id)
    return CinematicPanel(padding: 12) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
          NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 420)
            .frame(width: 56, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
          VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
              if let identity = record.detailIdentity {
                NavigationLink {
                  NativeMediaDetailPage(session: session, identity: identity)
                } label: {
                  Text(record.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
              } else {
                Text(record.displayTitle)
                  .font(.headline)
                  .foregroundStyle(.white)
                  .lineLimit(2)
              }
              Spacer(minLength: 4)
              statusBadge(record.status == true)
            }
            HStack(spacing: 8) {
              if let mode = record.modeLabel {
                Text(mode)
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.white.opacity(0.82))
                  .padding(.horizontal, 7)
                  .padding(.vertical, 2.5)
                  .background { Capsule().fill(.white.opacity(0.12)) }
              }
              if let date = record.date, !date.isEmpty {
                Text(date)
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.white.opacity(0.62))
                  .lineLimit(1)
              }
            }
            if let errmsg = record.errmsg, !errmsg.isEmpty {
              Text(errmsg)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(expanded ? nil : 2)
            }
            HStack(spacing: 12) {
              Button {
                if expanded {
                  expandedIDs.remove(record.id)
                } else {
                  expandedIDs.insert(record.id)
                }
              } label: {
                Label(
                  expanded ? "收起路径" : "查看路径",
                  systemImage: expanded ? "chevron.up" : "folder"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .frame(minHeight: 30)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-history-expand-\(record.id)")
              Spacer()
              if canManage {
                Button(role: .destructive) {
                  pendingDelete = record
                } label: {
                  Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.58))
                    .frame(minWidth: 32, minHeight: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除整理记录 \(record.displayTitle)")
                .accessibilityIdentifier("native-history-delete-\(record.id)")
              }
            }
          }
        }
        if expanded {
          Divider().overlay(.white.opacity(0.08))
          VStack(alignment: .leading, spacing: 6) {
            if let src = record.src, !src.isEmpty {
              Text("源路径：\(src)")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.68))
            }
            if let dest = record.dest, !dest.isEmpty {
              Text("目标路径：\(dest)")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.78))
            }
          }
        }
      }
    }
  }

  /// 成功/失败状态胶囊。
  private func statusBadge(_ succeeded: Bool) -> some View {
    let tint: Color =
      succeeded
      ? Color(red: 0.56, green: 0.92, blue: 0.72) : Color(red: 1.0, green: 0.52, blue: 0.52)
    return Text(succeeded ? "成功" : "失败")
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 3.5)
      .background {
        Capsule()
          .fill(.white.opacity(0.10))
          .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.6) }
      }
  }

  /// 操作结果提示条。
  private func feedbackBanner(_ feedback: NativeHistoryFeedback) -> some View {
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
    .accessibilityIdentifier("native-history-feedback")
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "clock.arrow.circlepath")
          .font(.largeTitle)
          .foregroundStyle(.white.opacity(0.55))
        Text("暂无匹配的整理记录").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 载入失败卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入整理历史", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-history-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 从第一页重新拉取整理历史。
  private func reload() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let page = try await fetchPage(1)
      try Task.checkCancellation()
      records = page.list ?? []
      total = page.total ?? records.count
      nextPage = 2
      hasMore = records.count < total && !(page.list ?? []).isEmpty
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 接近列表底部时自动拉取下一页。
  private func loadMoreIfNeeded(at index: Int) {
    guard hasMore, !isLoadingMore, index >= max(displayedRecords.count - 3, 0) else { return }
    Task {
      isLoadingMore = true
      defer { isLoadingMore = false }
      do {
        let page = try await fetchPage(nextPage)
        try Task.checkCancellation()
        let incoming = page.list ?? []
        var existing = Set(records.map(\.id))
        let unique = incoming.filter { existing.insert($0.id).inserted }
        records.append(contentsOf: unique)
        total = page.total ?? records.count
        nextPage += 1
        hasMore = records.count < total && !unique.isEmpty
      } catch {
        hasMore = false
      }
    }
  }

  /// 请求指定页的整理历史接口。
  private func fetchPage(_ page: Int) async throws -> NativeTransferHistoryPagePayload {
    var query = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "count", value: "30"),
    ]
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { query.append(URLQueryItem(name: "title", value: trimmed)) }
    let endpoint = try APIEndpoint(path: ["history", "transfer"], query: query)
    return try await session.request(endpoint, as: NativeTransferHistoryPagePayload.self).value
  }

  /// 显式单次删除单条整理记录（不删除源文件或目标媒体库文件）。
  private func deleteRecord(_ record: NativeTransferRecord) async {
    guard canManage else { return }
    do {
      let body = try JSONEncoder().encode(["id": record.id])
      let endpoint = try APIEndpoint(
        path: ["history", "transfer"],
        method: .delete,
        query: [
          URLQueryItem(name: "deletesrc", value: "false"),
          URLQueryItem(name: "deletedest", value: "false"),
        ],
        body: body)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      records.removeAll { $0.id == record.id }
      total = max(total - 1, 0)
      feedback = NativeHistoryFeedback(isError: false, message: "已删除整理记录。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeHistoryFeedback(isError: true, message: "删除整理记录失败，请稍后重试。")
    }
  }
}

/// 历史页提示载体。
private struct NativeHistoryFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/history/transfer` 分页结构。
private struct NativeTransferHistoryPagePayload: Decodable, Sendable {
  let list: [NativeTransferRecord]?
  let total: Int?
}

/// 单条整理历史记录投影。
private struct NativeTransferRecord: Decodable, Sendable, Identifiable {
  let id: Int
  let title: String?
  let type: String?
  let year: String?
  let seasons: String?
  let episodes: String?
  let status: Bool?
  let mode: String?
  let date: String?
  let errmsg: String?
  let src: String?
  let dest: String?
  let image: String?
  let mediaSource: String?
  let mediaID: String?

  /// 拼接片名与季集标识。
  var displayTitle: String {
    let base = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "整理任务 #\(id)"
    let suffix = [seasons, episodes]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return suffix.isEmpty ? base : "\(base) \(suffix)"
  }

  /// 本地化整理方式标签。
  var modeLabel: String? {
    switch (mode ?? "").lowercased() {
    case "copy": "复制"
    case "move": "移动"
    case "link": "硬链接"
    case "softlink": "软链接"
    case "rclone_copy": "Rclone 复制"
    case "rclone_move": "Rclone 移动"
    case "": nil
    default: mode
    }
  }

  /// 具备有效影视身份时允许直接进入原生详情页。
  var detailIdentity: NativeMediaIdentity? {
    guard let type, ["电影", "电视剧"].contains(type),
      let source = mediaSource, !source.isEmpty,
      let mediaID, !mediaID.isEmpty
    else { return nil }
    return NativeMediaIdentity(source: source, mediaID: mediaID, type: type)
  }

  /// 对应后端 `_SchemaTransferHistory` 字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case type
    case year
    case seasons
    case episodes
    case status
    case mode
    case date
    case errmsg
    case src
    case dest
    case image
    case mediaSource = "media_source"
    case mediaID = "media_id"
  }
}
