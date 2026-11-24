import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 原生整理历史页：分页查询整理记录、Web 风格源→目标紧凑路径卡片、长按重新整理与四选一安全删除弹窗。
@MainActor
struct NativeTransferHistoryPage: View {
  /// 整理记录状态筛选。
  private enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case success = "成功"
    case failed = "失败"

    var id: String { rawValue }
  }

  let session: NativeSession

  @State private var records: [NativeTransferRecord] = []
  @State private var storageNames: [String: String] = [:]
  @State private var total = 0
  @State private var nextPage = 1
  @State private var hasMore = false
  @State private var filter: StatusFilter = .all
  @State private var sortAscending = false
  @State private var searchText: String
  @State private var expandedIDs: Set<Int> = []
  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var loadFailed = false
  @State private var referenceDate = Date()
  @State private var attempt = 0
  @State private var pendingDelete: NativeTransferRecord?
  @State private var pendingReorganize: NativeTransferRecord?
  @State private var isDeleting = false
  @State private var showsQueueSheet = false
  @State private var feedback: NativeHistoryFeedback?

  /// 初始化整理历史页，支持由 `moviepilot://history?search=...` 预填筛选关键词。
  init(session: NativeSession, initialSearch: String = "") {
    self.session = session
    _searchText = State(initialValue: initialSearch)
  }

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          topSearchBar
          filterBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && records.isEmpty {
            NativeCardListSkeletonView(count: 5, style: .posterRow)
              .transition(.opacity)
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
                ProgressView()
                  .tint(.primary)
                  .frame(maxWidth: .infinity)
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
      .refreshable { await reload(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-history-scroll")
    }
    .navigationTitle(total > 0 ? "整理历史 (\(total))" : "整理历史")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsQueueSheet = true
        } label: {
          Image(systemName: "tray.full")
        }
        .tint(.primary)
        .accessibilityLabel("整理队列")
        .accessibilityIdentifier("native-history-queue")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Section("整理状态") {
            ForEach(StatusFilter.allCases) { option in
              Button {
                filter = option
              } label: {
                if filter == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
          Section("排序方式") {
            Button {
              sortAscending = false
            } label: {
              if !sortAscending {
                Label("最新优先", systemImage: "checkmark")
              } else {
                Text("最新优先")
              }
            }
            Button {
              sortAscending = true
            } label: {
              if sortAscending {
                Label("最早优先", systemImage: "checkmark")
              } else {
                Text("最早优先")
              }
            }
          }
        } label: {
          Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .tint(.primary)
        .accessibilityLabel("筛选与排序")
        .accessibilityIdentifier("native-history-filter-menu")
      }
    }
    .sheet(isPresented: $showsQueueSheet) {
      NativeTransferQueueSheet(session: session, canManage: canManage)
    }
    .sheet(item: $pendingReorganize) { record in
      NativeManualTransferSheet(
        session: session,
        historyLogID: record.id,
        sourceHint: record.src,
        titleHint: record.displayTitle,
        defaultTargetStorage: record.destStorage ?? record.srcStorage,
        defaultMediaType: record.type,
        defaultMediaSource: record.mediaSource,
        defaultMediaID: record.mediaID
      ) { message in
        feedback = NativeHistoryFeedback(isError: false, message: message)
        Task { await reload(forceRefresh: true) }
      }
    }
    .sheet(item: $pendingDelete) { record in
      NativeTransferDeleteSheet(
        record: record,
        isDeleting: isDeleting
      ) { deleteSrc, deleteDest in
        Task { await deleteRecord(record, deleteSrc: deleteSrc, deleteDest: deleteDest) }
      }
      .presentationDetents([.height(340), .medium])
      .presentationDragIndicator(.visible)
    }
    .task { await loadStorageNames() }
    .task(id: attempt) { await reload(forceRefresh: attempt > 0) }
  }

  /// 当前用户具备管理权限时允许重新整理与删除记录。
  private var canManage: Bool {
    session.user.isSuperuser || session.user.allows(.init(category: .manage))
  }

  /// 经本地状态、关键词与时间排序后的可见列表。
  private var displayedRecords: [NativeTransferRecord] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let matched = records.filter { record in
      let statusMatches: Bool =
        switch filter {
        case .all: true
        case .success: record.status == true
        case .failed: record.status == false
        }
      guard statusMatches else { return false }
      guard !trimmed.isEmpty else { return true }
      return record.displayTitle.lowercased().contains(trimmed)
        || (record.src?.lowercased().contains(trimmed) ?? false)
        || (record.dest?.lowercased().contains(trimmed) ?? false)
    }
    return sortAscending ? matched.reversed() : matched
  }

  /// 顶部常驻玻璃搜索框：输入实时筛选，回车触发后端片名检索。
  private var topSearchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
      TextField("搜索片名或路径", text: $searchText)
        .textFieldStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .submitLabel(.search)
        .onSubmit { attempt += 1 }
        .accessibilityIdentifier("native-history-search-field")
      if !searchText.isEmpty {
        Button {
          searchText = ""
          attempt += 1
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清空搜索")
      }
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(NativeTheme.chipFill)
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(NativeTheme.chipBorder, lineWidth: 0.7)
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
            .foregroundStyle(selected ? NativeTheme.brand : .secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
              Capsule()
                .fill(selected ? NativeTheme.brand.opacity(0.18) : NativeTheme.chipFill)
                .overlay {
                  Capsule().strokeBorder(
                    selected ? NativeTheme.brand.opacity(0.42) : NativeTheme.chipBorder,
                    lineWidth: 0.6)
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

  /// 单条整理记录玻璃卡片：海报、状态徽标、方式/体积/时间、Web 风格链式路径视图与完整长按菜单。
  private func recordCard(_ record: NativeTransferRecord) -> some View {
    let poster = NativeMediaDetailPage.resolveArtwork(
      record.image, source: record.mediaSource ?? "themoviedb")
    let expanded = expandedIDs.contains(record.id)
    return CinematicPanel(padding: 12) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 11) {
          NativeMediaArtwork(session: session, reference: poster, role: .poster, maximumWidth: 360)
            .frame(width: 50, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(NativeTheme.chipBorder, lineWidth: 0.5)
            }
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
              if let identity = record.detailIdentity {
                NavigationLink {
                  NativeMediaDetailPage(session: session, identity: identity)
                } label: {
                  Text(record.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
              } else {
                Text(record.displayTitle)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                  .lineLimit(2)
              }
              Spacer(minLength: 4)
              statusBadge(record.status == true)
            }

            HStack(spacing: 6) {
              if let mode = record.modeLabel {
                Text(mode)
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(NativeTheme.brand)
                  .padding(.horizontal, 7)
                  .padding(.vertical, 2)
                  .background {
                    Capsule().fill(NativeTheme.brand.opacity(0.14))
                  }
              }
              if let sizeText = record.formattedSize {
                Text(sizeText)
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              if let relativeDate = record.formattedRelativeDate(now: referenceDate) {
                if record.formattedSize != nil {
                  Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Text(relativeDate)
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .accessibilityValue(record.date ?? relativeDate)
              }
            }
          }
        }

        // Web 风格源→目标链式路径块：点击切换紧凑单行 / 完整换行展示
        if (record.src?.isEmpty == false) || (record.dest?.isEmpty == false) {
          Button {
            withAnimation(.easeInOut(duration: 0.18)) {
              if expanded {
                expandedIDs.remove(record.id)
              } else {
                expandedIDs.insert(record.id)
              }
            }
          } label: {
            linkedPathView(record: record, expanded: expanded)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-history-expand-\(record.id)")
        }

        if let errmsg = record.errmsg, !errmsg.isEmpty {
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
              .font(.caption)
              .foregroundStyle(NativeTheme.warning)
              .padding(.top, 1)
            Text(errmsg)
              .font(.caption)
              .foregroundStyle(NativeTheme.warning)
              .lineLimit(expanded ? nil : 2)
          }
        }
      }
    }
    .contextMenu {
      if record.status == true, let dest = record.dest, !dest.isEmpty {
        let fileName = (dest as NSString).lastPathComponent
        if NativeMediaPlaybackLauncher.isPlayableMediaExtension(
          (fileName as NSString).pathExtension)
        {
          Button {
            Task {
              let err = await NativeMediaPlaybackLauncher.shared.playStorageFile(
                session: session,
                storage: record.destStorage ?? "local",
                path: dest,
                fileName: fileName)
              if let err {
                feedback = NativeHistoryFeedback(isError: true, message: err)
              }
            }
          } label: {
            Label("本地播放", systemImage: "play.fill")
          }
        }
      }
      if canManage {
        Button {
          pendingReorganize = record
        } label: {
          Label("整理", systemImage: "wand.and.stars")
        }
      }
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          if expandedIDs.contains(record.id) {
            expandedIDs.remove(record.id)
          } else {
            expandedIDs.insert(record.id)
          }
        }
      } label: {
        Label(
          expandedIDs.contains(record.id) ? "收起完整路径" : "展开完整路径",
          systemImage: expandedIDs.contains(record.id)
            ? "chevron.up" : "arrow.up.left.and.arrow.down.right")
      }
      if let dest = record.dest, !dest.isEmpty {
        Button {
          UIPasteboard.general.string = dest
          feedback = NativeHistoryFeedback(isError: false, message: "已复制目标路径。")
        } label: {
          Label("复制目标路径", systemImage: "doc.on.doc")
        }
      } else if let src = record.src, !src.isEmpty {
        Button {
          UIPasteboard.general.string = src
          feedback = NativeHistoryFeedback(isError: false, message: "已复制源路径。")
        } label: {
          Label("复制源路径", systemImage: "doc.on.doc")
        }
      }
      if canManage {
        Divider()
        Button(role: .destructive) {
          pendingDelete = record
        } label: {
          Label("删除整理记录", systemImage: "trash")
        }
      }
    }
  }

  /// 对标 Web `TransferHistoryView` 的链式源/目标路径块：
  /// 左侧源节点(空心圆)与目标节点(实心主题圆)由细线连接，存储徽标 + 弱化目录 + 高亮文件名，点击平滑展开完整路径。
  private func linkedPathView(record: NativeTransferRecord, expanded: Bool) -> some View {
    let hasDest = record.dest?.isEmpty == false
    return VStack(alignment: .leading, spacing: 6) {
      if let src = record.src, !src.isEmpty {
        pathRow(
          path: src,
          storageLabel: displayStorageName(record.srcStorage),
          isDestination: false,
          linkedToNext: hasDest,
          expanded: expanded)
      }
      if let dest = record.dest, !dest.isEmpty {
        pathRow(
          path: dest,
          storageLabel: displayStorageName(record.destStorage),
          isDestination: true,
          linkedToNext: false,
          expanded: expanded)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(NativeTheme.chipFill.opacity(0.85))
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(NativeTheme.chipBorder, lineWidth: 0.5)
        }
    }
  }

  /// 链式路径单行（节点圆点 + 存储短标 + 目录/文件名分段样式）。
  private func pathRow(
    path: String,
    storageLabel: String,
    isDestination: Bool,
    linkedToNext: Bool,
    expanded: Bool
  ) -> some View {
    let parts = splitPath(path)
    return HStack(alignment: expanded ? .top : .center, spacing: 7) {
      VStack(spacing: 0) {
        Circle()
          .fill(isDestination ? NativeTheme.brand : Color.clear)
          .overlay {
            Circle().strokeBorder(
              isDestination ? NativeTheme.brand : Color.secondary.opacity(0.65),
              lineWidth: 1.5)
          }
          .frame(width: 7, height: 7)
          .padding(.top, expanded ? 4 : 0)
        if linkedToNext {
          Rectangle()
            .fill(Color.secondary.opacity(0.28))
            .frame(width: 1, height: expanded ? 14 : 10)
            .padding(.top, 2)
        }
      }
      .frame(width: 9)

      Text(storageLabel)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(isDestination ? NativeTheme.brand : .secondary)
        .padding(.horizontal, 5.5)
        .padding(.vertical, 2)
        .background {
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isDestination ? NativeTheme.brand.opacity(0.14) : NativeTheme.chipFill)
        }
        .fixedSize()

      if expanded {
        (Text(parts.directory)
          .foregroundColor(.secondary)
          + Text(parts.filename)
          .foregroundColor(.primary)
          .fontWeight(.medium))
          .font(.caption2.monospaced())
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
      } else {
        HStack(spacing: 0) {
          if !parts.compactParent.isEmpty {
            Text(parts.compactParent)
              .font(.caption2.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.head)
              .layoutPriority(0)
          }
          Text(parts.filename)
            .font(.caption2.monospaced().weight(.medium))
            .foregroundStyle(Color.primary.opacity(isDestination ? 1.0 : 0.86))
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
        }
      }
      Spacer(minLength: 0)
    }
  }

  /// 将路径切分为目录前缀、紧凑父目录名与文件名，供折叠态优先保留文件名展示。
  private func splitPath(_ raw: String) -> (
    directory: String, compactParent: String, filename: String
  ) {
    let ns = raw as NSString
    let filename = ns.lastPathComponent
    let dir = ns.deletingLastPathComponent
    guard !dir.isEmpty && dir != "/" else {
      return (dir == "/" ? "/" : "", "", filename)
    }
    let parentName = (dir as NSString).lastPathComponent
    let compactParent = parentName.isEmpty ? "" : "…/\(parentName)/"
    return ("\(dir)/", compactParent, filename)
  }

  private func displayStorageName(_ storage: String?) -> String {
    let key = (storage ?? "local").trimmingCharacters(in: .whitespacesAndNewlines)
    if let mapped = storageNames[key], !mapped.isEmpty { return mapped }
    switch key.lowercased() {
    case "local", "": return "本地"
    case "alipan": return "阿里云盘"
    case "u115": return "115网盘"
    case "rclone": return "RClone"
    case "alist": return "OpenList"
    case "alistgo": return "AList"
    case "smb": return "SMB"
    default: return key
    }
  }

  /// 成功/失败状态胶囊。
  private func statusBadge(_ succeeded: Bool) -> some View {
    let tint: Color = succeeded ? NativeTheme.success : NativeTheme.danger
    return Text(succeeded ? "成功" : "失败")
      .font(.caption2.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background {
        Capsule()
          .fill(tint.opacity(0.14))
          .overlay { Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 0.6) }
      }
  }

  /// 操作结果提示条。
  private func feedbackBanner(_ feedback: NativeHistoryFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary)
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.secondary).frame(minWidth: 32, minHeight: 32)
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
          .foregroundStyle(.secondary)
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

  private func loadStorageNames() async {
    guard let endpoint = try? APIEndpoint(path: ["storage", "options"]),
      let loaded = try? await session.request(endpoint, as: [NativeStorageOption].self).value
    else { return }
    storageNames = Dictionary(uniqueKeysWithValues: loaded.map { ($0.value, $0.title) })
  }

  /// 从第一页重新拉取整理历史；命中页面缓存时静默复用，下拉刷新强制重拉。
  private func reload(forceRefresh: Bool = false) async {
    referenceDate = Date()
    let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let cacheKey = "history|\(keyword)"
    if !forceRefresh,
      let cached: (records: [NativeTransferRecord], total: Int, nextPage: Int, hasMore: Bool) =
        NativePageDataCache.shared.get(cacheKey, session: session)
    {
      records = cached.records
      total = cached.total
      nextPage = cached.nextPage
      hasMore = cached.hasMore
      isLoading = false
      loadFailed = false
      return
    }
    if records.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let page = try await fetchPage(1)
      try Task.checkCancellation()
      records = page.list ?? []
      total = page.total ?? records.count
      nextPage = 2
      hasMore = records.count < total && !(page.list ?? []).isEmpty
      NativePageDataCache.shared.set(
        (records: records, total: total, nextPage: nextPage, hasMore: hasMore),
        for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if records.isEmpty { loadFailed = true }
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

  /// 按用户选择的范围删除整理记录及可选的源文件/目标媒体库文件（`DELETE /api/v1/history/transfer?deletesrc=...&deletedest=...`）。
  private func deleteRecord(
    _ record: NativeTransferRecord,
    deleteSrc: Bool,
    deleteDest: Bool
  ) async {
    guard canManage, !isDeleting else { return }
    isDeleting = true
    defer { isDeleting = false }
    do {
      let body = try JSONEncoder().encode(["id": record.id])
      let endpoint = try APIEndpoint(
        path: ["history", "transfer"],
        method: .delete,
        query: [
          URLQueryItem(name: "deletesrc", value: deleteSrc ? "true" : "false"),
          URLQueryItem(name: "deletedest", value: deleteDest ? "true" : "false"),
        ],
        body: body,
        timeout: 45)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      pendingDelete = nil
      records.removeAll { $0.id == record.id }
      total = max(total - 1, 0)
      let scopeDesc: String =
        switch (deleteSrc, deleteDest) {
        case (false, false): "已仅删除整理记录。"
        case (true, false): "已删除整理记录及源文件。"
        case (false, true): "已删除整理记录及媒体库文件。"
        case (true, true): "已删除整理记录、源文件及媒体库文件。"
        }
      feedback = NativeHistoryFeedback(isError: false, message: scopeDesc)
    } catch is CancellationError {
      return
    } catch {
      pendingDelete = nil
      feedback = NativeHistoryFeedback(isError: true, message: "删除整理记录失败，请稍后重试。")
    }
  }
}

/// 整理历史四选一删除确认弹窗（对标 Web `TransferHistoryDeleteDialog.vue`）。
@MainActor
private struct NativeTransferDeleteSheet: View {
  let record: NativeTransferRecord
  let isDeleting: Bool
  let onSelect: (Bool, Bool) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        VStack(alignment: .leading, spacing: 12) {
          Text("确认删除「\(record.displayTitle)」？请选择需要同步清理的文件范围：")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)

          VStack(spacing: 9) {
            deleteOptionButton(
              title: "仅删除记录",
              subtitle: "保留磁盘上的源文件与媒体库文件",
              icon: "doc.badge.minus",
              tint: NativeTheme.brand
            ) { onSelect(false, false) }

            deleteOptionButton(
              title: "删除记录和源文件",
              subtitle: "同时删除源下载文件，保留媒体库文件",
              icon: "arrow.down.doc",
              tint: NativeTheme.warning
            ) { onSelect(true, false) }

            deleteOptionButton(
              title: "删除记录和媒体库文件",
              subtitle: "同时删除整理后的目标文件，保留源文件",
              icon: "film.stack",
              tint: NativeTheme.info
            ) { onSelect(false, true) }

            deleteOptionButton(
              title: "删除记录、源文件和媒体库文件",
              subtitle: "彻底移除记录与两端文件，操作不可恢复",
              icon: "trash.fill",
              tint: NativeTheme.danger
            ) { onSelect(true, true) }
          }
          .disabled(isDeleting)

          Spacer(minLength: 0)
        }
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.top, 8)
        .padding(.bottom, 14)
      }
      .navigationTitle("删除整理记录")
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
          .disabled(isDeleting)
        }
      }
    }
    .nativeGlassSheet()
  }

  private func deleteOptionButton(
    title: String,
    subtitle: String,
    icon: String,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 11) {
        Image(systemName: icon)
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(tint)
          .frame(width: 24, height: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint == NativeTheme.danger ? tint : .primary)
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if isDeleting {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .fill(NativeTheme.chipFill)
          .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .strokeBorder(tint.opacity(0.24), lineWidth: 0.7)
          }
      }
    }
    .buttonStyle(.plain)
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
  struct FileSnapshot: Decodable, Sendable {
    let size: Int64?
  }

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
  let srcStorage: String?
  let destStorage: String?
  let srcFileitem: FileSnapshot?
  let image: String?
  let mediaSource: String?
  let mediaID: String?

  var displayTitle: String {
    let base = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "整理任务 #\(id)"
    let suffix = [seasons, episodes]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return suffix.isEmpty ? base : "\(base) \(suffix)"
  }

  /// 将整理时间格式化为相对当前时间的中文倒计文本（xx秒/分/时/天/月/年前）。
  func formattedRelativeDate(now: Date = Date()) -> String? {
    RelativeTimeFormatter.format(date, now: now)
  }

  var formattedSize: String? {
    guard let size = srcFileitem?.size, size > 0 else { return nil }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(size)
    var index = 0
    while value >= 1024 && index < units.count - 1 {
      value /= 1024
      index += 1
    }
    return String(format: "%.2f %@", value, units[index])
  }

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

  var detailIdentity: NativeMediaIdentity? {
    guard let type, ["电影", "电视剧"].contains(type),
      let source = mediaSource, !source.isEmpty,
      let mediaID, !mediaID.isEmpty
    else { return nil }
    return NativeMediaIdentity(source: source, mediaID: mediaID, type: type)
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, type, year, seasons, episodes, status, mode, date, errmsg, src, dest, image
    case srcStorage = "src_storage"
    case destStorage = "dest_storage"
    case srcFileitem = "src_fileitem"
    case mediaSource = "media_source"
    case mediaID = "media_id"
  }
}

/// 整理队列弹窗：读取 `GET /api/v1/transfer/queue` 并支持长按移除等待中的任务。
@MainActor
private struct NativeTransferQueueSheet: View {
  let session: NativeSession
  let canManage: Bool

  @Environment(\.dismiss) private var dismiss
  @State private var jobs: [NativeTransferQueueJob] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var feedback: String?

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if let feedback {
              CinematicPanel(padding: 11) {
                Text(feedback)
                  .font(.caption)
                  .foregroundStyle(.primary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            if isLoading && jobs.isEmpty {
              NativeCardListSkeletonView(count: 4, style: .iconRow)
                .transition(.opacity)
            } else if loadFailed && jobs.isEmpty {
              CinematicPanel {
                VStack(spacing: 10) {
                  Text("暂时无法读取整理队列").font(.headline)
                  Button("重试") { Task { await load() } }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
              }
            } else if jobs.isEmpty {
              CinematicPanel {
                VStack(spacing: 10) {
                  Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                  Text("当前整理队列为空")
                    .font(.headline)
                  Text("新的待整理任务将自动显示在此处。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
              }
            } else {
              ForEach(jobs) { job in
                jobCard(job)
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
        .refreshable { await load() }
        .accessibilityIdentifier("native-transfer-queue-scroll")
      }
      .navigationTitle("整理队列")
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
          .accessibilityIdentifier("native-transfer-queue-close")
        }
      }
      .task { await load() }
    }
    .nativeGlassSheet()
  }

  private func jobCard(_ job: NativeTransferQueueJob) -> some View {
    CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(job.displayTitle)
            .font(.headline)
            .foregroundStyle(.primary)
          Spacer()
          Text("\(job.tasks.count) 项")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        ForEach(job.tasks) { task in
          Divider().overlay(NativeTheme.chipBorder)
          HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
              Text(task.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
              if let path = task.fileitem?.path, !path.isEmpty {
                Text(path)
                  .font(.caption2.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .truncationMode(.head)
              }
            }
            Spacer(minLength: 4)
            Text(task.stateLabel)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(NativeTheme.brand)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background { Capsule().fill(NativeTheme.brand.opacity(0.14)) }
          }
          .contextMenu {
            if canManage, let file = task.fileitem {
              Button(role: .destructive) {
                Task { await removeFromQueue(file) }
              } label: {
                Label("从队列移除", systemImage: "trash")
              }
            }
          }
        }
      }
    }
  }

  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["transfer", "queue"])
      jobs = try await session.request(endpoint, as: [NativeTransferQueueJob].self).value
    } catch {
      loadFailed = true
    }
  }

  private func removeFromQueue(_ file: NativeTransferQueueFileItem) async {
    do {
      let body = try JSONEncoder().encode(file)
      let endpoint = try APIEndpoint(path: ["transfer", "queue"], method: .delete, body: body)
      _ = try await session.request(
        endpoint, as: JSONValue.self, requiring: PermissionRequirement(category: .manage))
      feedback = "已从整理队列移除「\(file.name ?? file.path ?? "任务")」。"
      await load()
    } catch {
      feedback = "移出整理队列失败，请稍后重试。"
    }
  }
}

/// 整理队列单个作业解码模型。
private struct NativeTransferQueueJob: Decodable, Sendable, Identifiable {
  let id: String
  let mediaTitle: String?
  let season: Int?
  let tasks: [NativeTransferQueueTask]

  var displayTitle: String {
    let base = mediaTitle?.isEmpty == false ? mediaTitle! : "待整理媒体"
    if let season { return "\(base) S\(String(format: "%02d", season))" }
    return base
  }

  private enum CodingKeys: String, CodingKey {
    case media, season, tasks
  }

  private struct MediaBrief: Decodable {
    let title: String?
    let titleYear: String?
    private enum CodingKeys: String, CodingKey {
      case title
      case titleYear = "title_year"
    }
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let brief = try? c.decodeIfPresent(MediaBrief.self, forKey: .media)
    mediaTitle = brief?.titleYear ?? brief?.title
    season = try? c.decodeIfPresent(Int.self, forKey: .season)
    tasks = (try? c.decodeIfPresent([NativeTransferQueueTask].self, forKey: .tasks)) ?? []
    id = "\(mediaTitle ?? "job")|\(season ?? -1)|\(tasks.first?.id ?? UUID().uuidString)"
  }
}

/// 整理队列单项文件任务解码模型。
private struct NativeTransferQueueTask: Decodable, Sendable, Identifiable {
  let id: String
  let fileitem: NativeTransferQueueFileItem?
  let state: String?

  var displayName: String {
    fileitem?.name ?? fileitem?.path ?? "未知文件"
  }

  var stateLabel: String {
    switch (state ?? "").lowercased() {
    case "running": "整理中"
    case "completed": "已完成"
    case "failed": "失败"
    case "cancelled": "已取消"
    default: "等待中"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case fileitem, state
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    fileitem = try? c.decodeIfPresent(NativeTransferQueueFileItem.self, forKey: .fileitem)
    state = try? c.decodeIfPresent(String.self, forKey: .state)
    id = fileitem?.path ?? UUID().uuidString
  }
}

/// 整理队列文件条目编解码模型。
private struct NativeTransferQueueFileItem: Codable, Sendable {
  let storage: String?
  let type: String?
  let path: String?
  let name: String?
}
