import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生消息中心：直连 `GET /api/v1/message/web` 展示系统/订阅/整理/下载通知时间线。
@MainActor
struct NativeMessagesPage: View {
  /// 消息类型快捷过滤。
  private enum Category: String, CaseIterable, Identifiable {
    case all = "全部"
    case subscribe = "订阅"
    case transfer = "整理"
    case download = "下载"
    case site = "站点"

    /// 固定分类标签作为标识。
    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var messages: [NativeMessageItem] = []
  @State private var category: Category = .all
  @State private var page = 1
  @State private var hasMore = false
  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var loadFailed = false
  @State private var attempt = 0

  /// 统一深色紫玫瑰渐变背景、分类筛选胶囊与带配图的透色通知卡片。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          categoryBar
          if isLoading && messages.isEmpty {
            ProgressView("正在载入消息通知…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && messages.isEmpty {
            failureCard
          } else if filteredMessages.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 12) {
              ForEach(Array(filteredMessages.enumerated()), id: \.element.id) { index, item in
                messageCard(item)
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
      .accessibilityIdentifier("native-messages-scroll")
    }
    .navigationTitle("消息中心")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          attempt += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("刷新消息中心")
        .accessibilityIdentifier("native-messages-refresh")
      }
    }
    .task(id: attempt) { await reload() }
  }

  /// 经分类过滤后的消息列表。
  private var filteredMessages: [NativeMessageItem] {
    guard category != .all else { return messages }
    return messages.filter { ($0.mtype ?? "").contains(category.rawValue) }
  }

  /// 顶部分类胶囊栏。
  private var categoryBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(Category.allCases) { option in
          let selected = category == option
          Button {
            category = option
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
          .accessibilityIdentifier("native-messages-filter-\(option.rawValue)")
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  /// 单条通知玻璃卡片：分类徽标、时间戳、标题、正文与可选媒体配图。
  private func messageCard(_ item: NativeMessageItem) -> some View {
    let artworkURL = NativeMediaDetailPage.resolveArtwork(
      item.image ?? item.poster, source: "themoviedb")
    return CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          if let mtype = item.mtype, !mtype.isEmpty {
            Text(mtype)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background {
                Capsule().fill(Color(red: 0.44, green: 0.34, blue: 0.68).opacity(0.65))
              }
          }
          Spacer()
          if let time = item.regTime, !time.isEmpty {
            Text(time)
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.white.opacity(0.58))
          }
        }
        if let title = item.title, !title.isEmpty {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
        }
        if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
          Text(text)
            .font(.footnote)
            .lineSpacing(3)
            .foregroundStyle(.white.opacity(0.76))
        }
        if let artworkURL {
          NativeMediaArtwork(
            session: session, reference: artworkURL, role: .continueWatching, maximumWidth: 720
          )
          .frame(maxWidth: .infinity)
          .frame(height: 148)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
          }
        }
      }
    }
  }

  /// 空态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "bell")
          .font(.largeTitle)
          .foregroundStyle(.white.opacity(0.55))
        Text("暂无通知消息").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 失败回退卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法载入消息中心", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-messages-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 重新加载第一页消息。
  private func reload() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let loaded = try await fetchPage(1)
      try Task.checkCancellation()
      messages = loaded
      page = 2
      hasMore = loaded.count >= 20
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 触底加载下一页消息。
  private func loadMoreIfNeeded(at index: Int) {
    guard hasMore, !isLoadingMore, index >= max(filteredMessages.count - 3, 0) else { return }
    Task {
      isLoadingMore = true
      defer { isLoadingMore = false }
      do {
        let loaded = try await fetchPage(page)
        try Task.checkCancellation()
        var existing = Set(messages.map(\.id))
        let unique = loaded.filter { existing.insert($0.id).inserted }
        messages.append(contentsOf: unique)
        page += 1
        hasMore = loaded.count >= 20 && !unique.isEmpty
      } catch {
        hasMore = false
      }
    }
  }

  /// 请求指定页的 Web 消息接口。
  private func fetchPage(_ pageNumber: Int) async throws -> [NativeMessageItem] {
    let endpoint = try APIEndpoint(
      path: ["message", "web"],
      query: [
        URLQueryItem(name: "page", value: String(pageNumber)),
        URLQueryItem(name: "size", value: "20"),
      ])
    return try await session.request(endpoint, as: [NativeMessageItem].self).value
  }
}

/// `GET /api/v1/message/web` 单条消息投影。
private struct NativeMessageItem: Decodable, Sendable, Identifiable {
  let id: Int
  let mtype: String?
  let title: String?
  let text: String?
  let image: String?
  let poster: String?
  let regTime: String?

  /// 对应后端消息时间线字段。
  private enum CodingKeys: String, CodingKey {
    case id
    case mtype
    case title
    case text
    case image
    case poster
    case regTime = "reg_time"
  }
}
