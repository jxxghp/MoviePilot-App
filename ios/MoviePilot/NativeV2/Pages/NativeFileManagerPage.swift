import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生多存储文件浏览器：支持存储切换、目录钻取、面包屑返回、新建文件夹、长按整理/智能重命名与二次确认删除。
@MainActor
struct NativeFileManagerPage: View {
  private enum FileFilter: String, CaseIterable, Identifiable {
    case all = "全部项目"
    case directories = "仅文件夹"
    case files = "仅文件"
    var id: String { rawValue }
  }

  private enum FileSort: String, CaseIterable, Identifiable {
    case nameAsc = "名称（A → Z）"
    case nameDesc = "名称（Z → A）"
    case typeAsc = "类型（按扩展名）"
    case sizeDesc = "大小（从大到小）"
    case sizeAsc = "大小（从小到大）"
    case timeDesc = "修改时间（最新优先）"
    case timeAsc = "修改时间（最早优先）"

    var id: String { rawValue }

    var shortLabel: String {
      switch self {
      case .nameAsc: "名称 ↑"
      case .nameDesc: "名称 ↓"
      case .typeAsc: "类型"
      case .sizeDesc: "大小 ↓"
      case .sizeAsc: "大小 ↑"
      case .timeDesc: "时间 ↓"
      case .timeAsc: "时间 ↑"
      }
    }
  }

  let session: NativeSession

  @State private var storages: [NativeStorageOption] = [
    NativeStorageOption(value: "local", title: "本地")
  ]
  @State private var activeStorage: String
  @State private var pathStack: [NativeFileItem]
  @State private var items: [NativeFileItem] = []
  @State private var fileFilter: FileFilter = .all
  @State private var fileSort: FileSort = .nameAsc
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var showingNewFolder = false
  @State private var newFolderName = ""
  @State private var pendingDelete: NativeFileItem?
  @State private var pendingRename: NativeFileItem?
  @State private var pendingTransfer: NativeFileItem?
  @State private var playingFilePath: String?
  @State private var feedback: NativeFileFeedback?

  /// 初始化文件管理器，支持通过 `moviepilot://files?storage=...&path=...` 直接落位至指定存储与目录。
  init(session: NativeSession, initialStorage: String? = nil, initialPath: String? = nil) {
    self.session = session
    let storage =
      initialStorage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? initialStorage!.trimmingCharacters(in: .whitespacesAndNewlines)
      : "local"
    _activeStorage = State(initialValue: storage)
    var stack = [NativeFileItem(storage: storage, type: "dir", path: "/", name: "根目录")]
    if let rawPath = initialPath?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawPath.isEmpty, rawPath != "/"
    {
      let segments = rawPath.split(separator: "/").map(String.init)
      var currentPath = ""
      for segment in segments {
        currentPath += "/\(segment)"
        stack.append(
          NativeFileItem(storage: storage, type: "dir", path: currentPath + "/", name: segment))
      }
    }
    _pathStack = State(initialValue: stack)
  }

  /// 连续语义背景、一体化存储切换与面包屑地址栏、目录/文件玻璃列表。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          breadcrumbBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && items.isEmpty {
            NativeCardListSkeletonView(count: 6, style: .fileRow)
              .transition(.opacity)
          } else if loadFailed && items.isEmpty {
            failureCard
          } else if items.isEmpty {
            emptyCard
          } else {
            LazyVStack(spacing: 10) {
              ForEach(sortedItems) { item in
                fileRow(item)
              }
            }
          }
        }
        .frame(maxWidth: 860)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await loadCurrentDirectory(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-files-scroll")
    }
    .navigationTitle("文件管理")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          if canManage {
            Button {
              newFolderName = ""
              showingNewFolder = true
            } label: {
              Label("新建文件夹", systemImage: "folder.badge.plus")
            }
          }
          Section("筛选") {
            ForEach(FileFilter.allCases) { option in
              Button {
                fileFilter = option
              } label: {
                if fileFilter == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
          Section("排序") {
            ForEach(FileSort.allCases) { option in
              Button {
                fileSort = option
              } label: {
                if fileSort == option {
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
        .accessibilityLabel("筛选、排序与文件操作")
        .accessibilityIdentifier("native-files-filter-menu")
      }
    }
    .task { await loadStorages() }
    .task(id: "\(activeStorage)|\(currentDirectory.path)|\(attempt)") {
      await loadCurrentDirectory(forceRefresh: attempt > 0)
    }
    .sheet(item: $pendingTransfer) { item in
      NativeManualTransferSheet(
        session: session,
        fileItem: item,
        initialStorages: storages
      ) { message in
        feedback = NativeFileFeedback(isError: false, message: message)
        Task { await loadCurrentDirectory(forceRefresh: true) }
      }
    }
    .sheet(item: $pendingRename) { item in
      NativeFileRenameSheet(session: session, item: item) { message in
        feedback = NativeFileFeedback(isError: false, message: message)
        Task { await loadCurrentDirectory(forceRefresh: true) }
      }
    }
    .alert("新建文件夹", isPresented: $showingNewFolder) {
      TextField("文件夹名称", text: $newFolderName)
      Button("创建") {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task { await createFolder(named: name) }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("将在 \(currentDirectory.path) 下创建新目录。")
    }
    .alert(
      "删除项目",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { item in
      Button("确认删除", role: .destructive) {
        Task { await deleteItem(item) }
      }
      Button("取消", role: .cancel) {}
    } message: { item in
      Text("确认删除「\(item.displayName)」吗？此操作无法撤销。")
    }
  }

  /// 当前用户具备管理权限时允许新建目录、整理、重命名与删除文件。
  private var canManage: Bool {
    session.user.isSuperuser || session.user.allows(.init(category: .manage))
  }

  /// 当前处于栈顶的目录节点。
  private var currentDirectory: NativeFileItem {
    pathStack.last
      ?? NativeFileItem(storage: activeStorage, type: "dir", path: "/", name: "根目录")
  }

  /// 按当前筛选与排序条件整理目录与文件列表（文件夹始终置前，名称采用自然数字序对比）。
  private var sortedItems: [NativeFileItem] {
    let filtered = items.filter { item in
      switch fileFilter {
      case .all: true
      case .directories: item.isDirectory
      case .files: !item.isDirectory
      }
    }
    return filtered.sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
      switch fileSort {
      case .nameAsc:
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      case .nameDesc:
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedDescending
      case .typeAsc:
        let extCmp = lhs.normalizedExtension.localizedStandardCompare(rhs.normalizedExtension)
        if extCmp != .orderedSame { return extCmp == .orderedAscending }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      case .sizeDesc:
        let lSize = lhs.size ?? 0
        let rSize = rhs.size ?? 0
        if lSize != rSize { return lSize > rSize }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      case .sizeAsc:
        let lSize = lhs.size ?? 0
        let rSize = rhs.size ?? 0
        if lSize != rSize { return lSize < rSize }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      case .timeDesc:
        let lTime = lhs.modifyTime ?? 0
        let rTime = rhs.modifyTime ?? 0
        if lTime != rTime { return lTime > rTime }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      case .timeAsc:
        let lTime = lhs.modifyTime ?? 0
        let rTime = rhs.modifyTime ?? 0
        if lTime != rTime { return lTime < rTime }
        return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
      }
    }
  }

  /// 当前选中存储器的展示名称。
  private var activeStorageTitle: String {
    storages.first(where: { $0.value == activeStorage })?.title ?? activeStorage
  }

  /// 一体化文件管理器地址栏：首项为存储器下拉切换菜单，后续拼接可点击跳转的横向滚动路径面包屑。
  private var breadcrumbBar: some View {
    CinematicPanel(padding: 8) {
      HStack(spacing: 8) {
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
              Menu {
                ForEach(storages) { storage in
                  Button {
                    if storage.value == activeStorage {
                      if pathStack.count > 1 {
                        pathStack = Array(pathStack.prefix(1))
                      }
                    } else {
                      switchStorage(to: storage.value)
                    }
                  } label: {
                    if storage.value == activeStorage {
                      Label(storage.title, systemImage: "checkmark")
                    } else {
                      Text(storage.title)
                    }
                  }
                }
              } label: {
                HStack(spacing: 5) {
                  NativeBrandIcon(
                    kind: .storage, type: activeStorage, size: 18, cornerRadius: 5)
                  Text(activeStorageTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                  Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background {
                  RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NativeTheme.brand.opacity(0.18))
                    .overlay {
                      RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(NativeTheme.brand.opacity(0.32), lineWidth: 0.6)
                    }
                }
              }
              .accessibilityLabel("切换存储器 \(activeStorageTitle)")
              .accessibilityIdentifier("native-files-storage-menu")

              ForEach(Array(pathStack.enumerated()), id: \.offset) { index, segment in
                let isLast = index == pathStack.count - 1
                let isImmediateParent = pathStack.count > 1 && index == pathStack.count - 2
                let title = index == 0 ? "根目录" : segment.displayName

                Image(systemName: "chevron.right")
                  .font(.system(size: 9.5, weight: .semibold))
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 1)

                if isLast {
                  Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                      RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NativeTheme.chipFill)
                    }
                    .id("crumb-\(index)")
                } else {
                  Button {
                    pathStack = Array(pathStack.prefix(index + 1))
                  } label: {
                    Text(title)
                      .font(.caption.weight(.medium))
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                      .padding(.horizontal, 7)
                      .padding(.vertical, 5)
                      .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                          .fill(NativeTheme.chipFill.opacity(0.6))
                      }
                  }
                  .buttonStyle(.plain)
                  .id("crumb-\(index)")
                  .accessibilityIdentifier(
                    isImmediateParent ? "native-files-up" : "native-files-crumb-\(index)")
                }
              }
            }
            .padding(.horizontal, 2)
          }
          .onChange(of: pathStack.count) { count in
            withAnimation(.easeOut(duration: 0.2)) {
              proxy.scrollTo("crumb-\(max(count - 1, 0))", anchor: .trailing)
            }
          }
        }

        Menu {
          Section("排列顺序") {
            ForEach(FileSort.allCases) { option in
              Button {
                fileSort = option
              } label: {
                if fileSort == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
          Section("筛选") {
            ForEach(FileFilter.allCases) { option in
              Button {
                fileFilter = option
              } label: {
                if fileFilter == option {
                  Label(option.rawValue, systemImage: "checkmark")
                } else {
                  Text(option.rawValue)
                }
              }
            }
          }
        } label: {
          HStack(spacing: 3) {
            Text(fileSort.shortLabel)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.primary)
            Image(systemName: "chevron.down")
              .font(.system(size: 8.5, weight: .bold))
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 5)
          .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(NativeTheme.chipFill)
          }
        }
        .accessibilityLabel("文件排列顺序 \(fileSort.rawValue)")
        .accessibilityIdentifier("native-files-sort-menu")

        Text("\(sortedItems.count) 项")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .padding(.trailing, 4)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("native-files-address-bar")
  }

  /// 单个目录或文件玻璃行；可播放音视频支持一键拉起原生本地播放器及完整长按菜单（整理/重命名/删除）。
  private func fileRow(_ item: NativeFileItem) -> some View {
    let playable =
      !item.isDirectory
      && NativeMediaPlaybackLauncher.isPlayableMediaExtension(item.fileExtension)
    let isOpeningPlay = playingFilePath == item.path
    return CinematicPanel(padding: 12) {
      HStack(spacing: 12) {
        Button {
          if item.isDirectory {
            pathStack.append(item)
          } else if playable {
            Task { await playLocalFile(item) }
          }
        } label: {
          HStack(spacing: 12) {
            Group {
              if isOpeningPlay {
                ProgressView().controlSize(.mini).tint(.primary)
              } else {
                Image(systemName: item.symbolName)
                  .font(.title3.weight(.medium))
                  .foregroundStyle(item.isDirectory ? NativeTheme.brand : .primary)
              }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
              Text(item.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
              if let meta = item.metadataSummary {
                Text(meta)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer(minLength: 4)
            if item.isDirectory {
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            } else if playable {
              Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(NativeTheme.brand)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-file-open-\(item.safeIdentifier)")
      }
    }
    .contextMenu {
      if playable {
        Button {
          Task { await playLocalFile(item) }
        } label: {
          Label("本地播放", systemImage: "play.fill")
        }
      }
      if item.isDirectory {
        Button {
          pathStack.append(item)
        } label: {
          Label("打开目录", systemImage: "folder")
        }
      }
      if canManage {
        Button {
          pendingTransfer = item
        } label: {
          Label("整理", systemImage: "tray.and.arrow.down")
        }
        Button {
          pendingRename = item
        } label: {
          Label("重命名", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
          pendingDelete = item
        } label: {
          Label("删除", systemImage: "trash")
        }
      }
    }
  }

  /// 通过当前实例存储流接口下载并拉起原生本地播放器播放该文件。
  private func playLocalFile(_ item: NativeFileItem) async {
    guard playingFilePath == nil else { return }
    playingFilePath = item.path
    defer { playingFilePath = nil }
    let error = await NativeMediaPlaybackLauncher.shared.playStorageFile(
      session: session,
      storage: item.storage,
      path: item.path,
      fileName: item.displayName)
    if let error {
      feedback = NativeFileFeedback(isError: true, message: error)
    }
  }

  /// 轻量操作反馈条。
  private func feedbackBanner(_ feedback: NativeFileFeedback) -> some View {
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
    .accessibilityIdentifier("native-files-feedback")
  }

  /// 空目录状态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "folder")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
        Text("当前目录为空").font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    }
  }

  /// 载入失败卡片。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法读取目录列表", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-files-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 切换存储源并重置面包屑到根目录。
  private func switchStorage(to storage: String) {
    guard storage != activeStorage else { return }
    activeStorage = storage
    pathStack = [NativeFileItem(storage: storage, type: "dir", path: "/", name: "根目录")]
    items = []
  }

  /// 读取可用存储选项（`GET /api/v1/storage/options`）。
  private func loadStorages() async {
    guard let endpoint = try? APIEndpoint(path: ["storage", "options"]),
      let loaded = try? await session.request(endpoint, as: [NativeStorageOption].self).value,
      !loaded.isEmpty
    else { return }
    storages = loaded
    if !loaded.contains(where: { $0.value == activeStorage }), let first = loaded.first {
      switchStorage(to: first.value)
    }
  }

  /// 请求当前目录内容（`POST /api/v1/storage/list`）；命中目录缓存时静默复用，下拉刷新强制重拉。
  private func loadCurrentDirectory(forceRefresh: Bool = false) async {
    let cacheKey = "files|\(activeStorage)|\(currentDirectory.path)"
    if !forceRefresh,
      let cached: [NativeFileItem] = NativePageDataCache.shared.get(cacheKey, session: session)
    {
      items = cached
      isLoading = false
      loadFailed = false
      return
    }
    if items.isEmpty { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let body = try JSONEncoder().encode(currentDirectory)
      let endpoint = try APIEndpoint(
        path: ["storage", "list"], method: .post, body: body, timeout: 30)
      let loaded = try await session.request(endpoint, as: [NativeFileItem].self).value
      try Task.checkCancellation()
      items = loaded
      NativePageDataCache.shared.set(loaded, for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if items.isEmpty { loadFailed = true }
    }
  }

  /// 单次提交创建子目录（`POST /api/v1/storage/mkdir?name=...`）。
  private func createFolder(named name: String) async {
    guard canManage else { return }
    do {
      let body = try JSONEncoder().encode(currentDirectory)
      let endpoint = try APIEndpoint(
        path: ["storage", "mkdir"],
        method: .post,
        query: [URLQueryItem(name: "name", value: name)],
        body: body)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      feedback = NativeFileFeedback(isError: false, message: "已创建文件夹「\(name)」。")
      await loadCurrentDirectory(forceRefresh: true)
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeFileFeedback(isError: true, message: "创建文件夹失败，请检查权限或路径。")
    }
  }

  /// 二次确认后单次删除文件或目录（`POST /api/v1/storage/delete`）。
  private func deleteItem(_ item: NativeFileItem) async {
    guard canManage else { return }
    do {
      let body = try JSONEncoder().encode(item)
      let endpoint = try APIEndpoint(path: ["storage", "delete"], method: .post, body: body)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      items.removeAll { $0.id == item.id }
      NativePageDataCache.shared.set(
        items, for: "files|\(activeStorage)|\(currentDirectory.path)", session: session)
      feedback = NativeFileFeedback(isError: false, message: "已删除「\(item.displayName)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeFileFeedback(isError: true, message: "删除失败，请稍后重试。")
    }
  }
}

/// 智能重命名弹窗：支持一键识别推荐命名（`GET /api/v1/transfer/name`）及目录递归重命名（`POST /api/v1/storage/rename`）。
@MainActor
private struct NativeFileRenameSheet: View {
  let session: NativeSession
  let item: NativeFileItem
  let onRenamed: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var newName: String
  @State private var recursive = false
  @State private var isRecommending = false
  @State private var isSubmitting = false
  @State private var statusMessage: String?
  @State private var statusIsError = false

  init(session: NativeSession, item: NativeFileItem, onRenamed: @escaping (String) -> Void) {
    self.session = session
    self.item = item
    self.onRenamed = onRenamed
    _newName = State(initialValue: item.displayName)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            CinematicPanel(padding: 14) {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                  Image(systemName: item.symbolName)
                    .foregroundStyle(NativeTheme.brand)
                  Text(item.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 6) {
                  Text("新名称")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                  TextField("输入新的文件名或目录名", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                      RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(NativeTheme.chipFill)
                        .overlay {
                          RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(NativeTheme.chipBorder, lineWidth: 0.7)
                        }
                    }
                }

                Button {
                  Task { await recommendName() }
                } label: {
                  HStack(spacing: 6) {
                    if isRecommending {
                      ProgressView().controlSize(.small)
                    } else {
                      Image(systemName: "text.viewfinder")
                    }
                    Text(isRecommending ? "正在智能识别命名…" : "智能识别推荐命名")
                  }
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(NativeTheme.brand)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 9)
                  .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                      .fill(NativeTheme.brand.opacity(0.14))
                  }
                }
                .buttonStyle(.plain)
                .disabled(isRecommending || isSubmitting)

                if item.isDirectory {
                  Toggle(isOn: $recursive) {
                    VStack(alignment: .leading, spacing: 2) {
                      Text("递归智能重命名目录内媒体")
                        .font(.subheadline)
                      Text("按当前命名规则同步识别并重命名目录内音视频与字幕文件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                  }
                  .tint(NativeTheme.brand)
                }
              }
            }

            if let statusMessage {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(
                    systemName: statusIsError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                  )
                  .foregroundStyle(statusIsError ? NativeTheme.warning : NativeTheme.success)
                  Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
      }
      .navigationTitle("重命名")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await submitRename() }
          } label: {
            if isSubmitting {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("确认")
                .fontWeight(.semibold)
            }
          }
          .tint(.primary)
          .disabled(
            isSubmitting || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .nativeGlassSheet()
  }

  private func recommendName() async {
    isRecommending = true
    statusMessage = nil
    defer { isRecommending = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["transfer", "name"],
        query: [
          URLQueryItem(name: "path", value: item.path),
          URLQueryItem(name: "filetype", value: item.isDirectory ? "dir" : "file"),
        ],
        responseContract: .payload,
        timeout: 30)
      let resp = try await session.request(
        endpoint, as: NativeRecommendNameResponse.self
      ).value
      if resp.success == true, let recommended = resp.data?.name, !recommended.isEmpty {
        newName = recommended
        statusIsError = false
        statusMessage = "已填充智能识别命名。"
      } else {
        statusIsError = true
        statusMessage = resp.message?.isEmpty == false ? resp.message! : "未识别到可用推荐名称。"
      }
    } catch {
      statusIsError = true
      statusMessage = "智能识别命名失败：\(error.localizedDescription)"
    }
  }

  private func submitRename() async {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    isSubmitting = true
    statusMessage = nil
    defer { isSubmitting = false }
    do {
      let body = try JSONEncoder().encode(item)
      var query = [URLQueryItem(name: "new_name", value: trimmed)]
      if item.isDirectory && recursive {
        query.append(URLQueryItem(name: "recursive", value: "true"))
      }
      let endpoint = try APIEndpoint(
        path: ["storage", "rename"],
        method: .post,
        query: query,
        body: body,
        responseContract: .payload,
        timeout: recursive ? 120 : 30)
      let resp = try await session.request(
        endpoint, as: NativeManualTransferEnvelope<JSONValue>.self
      ).value
      if resp.success == false {
        statusIsError = true
        statusMessage = resp.message?.isEmpty == false ? resp.message! : "重命名失败。"
        return
      }
      onRenamed("已重命名为「\(trimmed)」。")
      dismiss()
    } catch {
      statusIsError = true
      statusMessage = "重命名失败：\(error.localizedDescription)"
    }
  }
}

/// 跨页面共用的手动整理弹窗（对标 Web `ReorganizeDialog.vue`）：
/// 支持从文件管理（`fileItem`）或整理历史（`historyLogID`）拉起，自动匹配目标目录、检测历史记录、预览结果与提交整理。
@MainActor
struct NativeManualTransferSheet: View {
  private enum TriStateChoice: String, CaseIterable, Identifiable {
    case auto = "跟随目录设置"
    case enabled = "开启"
    case disabled = "关闭"
    var id: String { rawValue }
    var boolValue: Bool? {
      switch self {
      case .auto: nil
      case .enabled: true
      case .disabled: false
      }
    }
  }

  let session: NativeSession
  let fileItem: NativeFileItem?
  let historyLogID: Int?
  let sourceTitleHint: String
  let sourcePathHint: String
  let sourceStorageHint: String
  let onCompleted: (String) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var storages: [NativeStorageOption]
  @State private var libraryDirectories: [NativeTransferDirectoryOption] = []
  @State private var targetStorage: String
  @State private var targetPath: String = ""
  @State private var matchedTargetHint: String?
  @State private var matchedHistoryCount = 0
  @State private var skipSuccess = false
  @State private var reorganize = false

  @State private var transferType: String = ""
  @State private var overwriteMode: String = "never"
  @State private var mediaType: String = ""
  @State private var mediaSource: String = ""
  @State private var mediaID: String = ""
  @State private var selectedMediaTitle: String?
  @State private var seasonText: String = ""
  @State private var episodeDetail: String = ""
  @State private var episodeOffset: String = ""
  @State private var episodePart: String = ""
  @State private var episodeFormat: String = ""
  @State private var episodeGroup: String = ""
  @State private var musicType: String = ""
  @State private var musicTrackMatch: String = "strict"
  @State private var minFilesizeText: String = "0"

  @State private var scrapeChoice: TriStateChoice = .auto
  @State private var typeFolderChoice: TriStateChoice = .auto
  @State private var categoryFolderChoice: TriStateChoice = .auto
  @State private var fromHistory: Bool
  @State private var runInBackground = true

  @State private var showingMediaPicker = false
  @State private var showingAdvancedOptions = false
  @State private var isLoadingMetadata = false
  @State private var isPreviewing = false
  @State private var isSubmitting = false
  @State private var previewItems: [NativeManualTransferPreviewItem] = []
  @State private var previewError: String?
  @State private var submitFeedback: String?
  @State private var submitIsError = false

  private let transferTypes: [(label: String, value: String)] = [
    ("自动（跟随目录配置）", ""),
    ("硬链接", "link"),
    ("软链接", "softlink"),
    ("复制", "copy"),
    ("移动", "move"),
    ("Rclone 复制", "rclone_copy"),
    ("Rclone 移动", "rclone_move"),
  ]

  private let overwriteModes: [(label: String, value: String)] = [
    ("从不覆盖", "never"),
    ("按文件大小覆盖", "size"),
    ("总是覆盖", "always"),
    ("仅保留最新版本", "latest"),
  ]

  private let mediaTypes: [(label: String, value: String)] = [
    ("自动识别", ""),
    ("电影", "电影"),
    ("电视剧", "电视剧"),
    ("音乐", "音乐"),
  ]

  private let mediaSources: [(label: String, value: String)] = [
    ("自动", ""),
    ("TheMovieDB", "themoviedb"),
    ("豆瓣", "douban"),
    ("Bangumi", "bangumi"),
    ("MusicBrainz", "musicbrainz"),
  ]

  /// 从文件管理页拉起手动整理。
  init(
    session: NativeSession,
    fileItem: NativeFileItem,
    initialStorages: [NativeStorageOption] = [],
    onCompleted: @escaping (String) -> Void
  ) {
    self.session = session
    self.fileItem = fileItem
    self.historyLogID = nil
    self.sourceTitleHint = fileItem.displayName
    self.sourcePathHint = fileItem.path
    self.sourceStorageHint = fileItem.storage
    self.onCompleted = onCompleted
    _storages = State(
      initialValue: initialStorages.isEmpty
        ? [NativeStorageOption(value: "local", title: "本地")] : initialStorages)
    _targetStorage = State(initialValue: fileItem.storage)
    _fromHistory = State(initialValue: false)
  }

  /// 从整理历史页拉起重新整理。
  init(
    session: NativeSession,
    historyLogID: Int,
    sourceHint: String?,
    titleHint: String,
    defaultTargetStorage: String?,
    defaultMediaType: String?,
    defaultMediaSource: String?,
    defaultMediaID: String?,
    onCompleted: @escaping (String) -> Void
  ) {
    self.session = session
    self.fileItem = nil
    self.historyLogID = historyLogID
    self.sourceTitleHint = titleHint
    self.sourcePathHint = sourceHint ?? "历史记录 #\(historyLogID)"
    self.sourceStorageHint = defaultTargetStorage ?? "local"
    self.onCompleted = onCompleted
    _storages = State(initialValue: [NativeStorageOption(value: "local", title: "本地")])
    _targetStorage = State(initialValue: defaultTargetStorage ?? "local")
    _mediaType = State(initialValue: defaultMediaType ?? "")
    _mediaSource = State(initialValue: defaultMediaSource ?? "")
    _mediaID = State(initialValue: defaultMediaID ?? "")
    _fromHistory = State(initialValue: true)
    _reorganize = State(initialValue: true)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            sourceSummaryCard
            if matchedHistoryCount > 0 {
              historyMatchBanner
            }
            targetSection
            mediaOverrideSection
            behaviorSection
            if !previewItems.isEmpty || previewError != nil {
              previewSection
            }
            if let submitFeedback {
              CinematicPanel(padding: 12) {
                HStack(spacing: 8) {
                  Image(
                    systemName: submitIsError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                  )
                  .foregroundStyle(submitIsError ? NativeTheme.warning : NativeTheme.success)
                  Text(submitFeedback)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            actionFooter
          }
          .frame(maxWidth: 760)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(historyLogID != nil ? "重新整理" : "手动整理")
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
        }
      }
      .task { await bootstrap() }
      .sheet(isPresented: $showingMediaPicker) {
        NativeManualTransferMediaPickerSheet(
          session: session,
          initialKeyword: sourceTitleHint,
          preferMusic: mediaType == "音乐"
        ) { picked in
          mediaSource = picked.source
          mediaID = picked.mediaID
          selectedMediaTitle = picked.displayTitle
          if let pickedType = picked.mediaType, !pickedType.isEmpty {
            mediaType = pickedType
          }
          if let pickedMusicType = picked.musicType, !pickedMusicType.isEmpty {
            musicType = pickedMusicType
          }
        }
      }
    }
    .nativeGlassSheet()
  }

  /// 源文件摘要卡片。
  private var sourceSummaryCard: some View {
    CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Image(
            systemName: historyLogID != nil
              ? "arrow.clockwise.circle.fill"
              : (fileItem?.symbolName ?? "doc.fill")
          )
          .font(.title3)
          .foregroundStyle(NativeTheme.brand)
          VStack(alignment: .leading, spacing: 2) {
            Text(sourceTitleHint)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(2)
            Text(sourcePathHint)
              .font(.caption2.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .truncationMode(.head)
          }
          Spacer(minLength: 0)
        }
        if let matchedTargetHint, !matchedTargetHint.isEmpty {
          HStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
              .font(.caption2)
              .foregroundStyle(NativeTheme.success)
            Text("已自动匹配目录：\(matchedTargetHint)")
              .font(.caption2)
              .foregroundStyle(NativeTheme.success)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        } else if isLoadingMetadata {
          HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("正在匹配目标目录配置…")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  /// 已存在成功历史提示条。
  private var historyMatchBanner: some View {
    CinematicPanel(padding: 12) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: "clock.badge.checkmark")
            .foregroundStyle(NativeTheme.warning)
          Text("检测到 \(matchedHistoryCount) 条已成功的整理历史")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
        }
        Toggle("跳过已成功记录", isOn: $skipSuccess)
          .font(.subheadline)
          .tint(NativeTheme.brand)
        if !skipSuccess {
          Toggle("清理旧目标并重新整理", isOn: $reorganize)
            .font(.subheadline)
            .tint(NativeTheme.brand)
        }
      }
    }
  }

  /// 分组 1：目标存储、目标目录、整理方式与覆盖模式。
  private var targetSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionHeader("目标存储与方式")
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 12) {
          groupedPickerRow(title: "目标存储") {
            Menu {
              ForEach(storages) { storage in
                Button {
                  targetStorage = storage.value
                  Task { await matchTargetPath() }
                } label: {
                  if storage.value == targetStorage {
                    Label(storage.title, systemImage: "checkmark")
                  } else {
                    Text(storage.title)
                  }
                }
              }
            } label: {
              menuValueLabel(
                storages.first(where: { $0.value == targetStorage })?.title ?? targetStorage)
            }
          }

          Divider().overlay(NativeTheme.chipBorder)

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("目标目录")
                .font(.subheadline)
                .foregroundStyle(.primary)
              Spacer()
              if !filteredLibraryDirectories.isEmpty {
                Menu {
                  Button("自动按规则匹配") { targetPath = "" }
                  Divider()
                  ForEach(filteredLibraryDirectories) { dir in
                    Button {
                      targetPath = dir.libraryPath
                      if let mode = dir.transferType, !mode.isEmpty {
                        transferType = mode
                      }
                    } label: {
                      Text(dir.displayLabel)
                    }
                  }
                } label: {
                  Label("选择媒体库目录", systemImage: "folder.badge.gearshape")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NativeTheme.brand)
                }
              }
            }
            TextField("留空按目录设置自动匹配", text: $targetPath)
              .textFieldStyle(.plain)
              .font(.caption.monospaced())
              .autocorrectionDisabled()
              .textInputAutocapitalization(.never)
              .padding(.horizontal, 10)
              .padding(.vertical, 9)
              .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(NativeTheme.chipFill)
              }
          }

          Divider().overlay(NativeTheme.chipBorder)

          groupedPickerRow(title: "整理方式") {
            Menu {
              ForEach(transferTypes, id: \.value) { option in
                Button {
                  transferType = option.value
                } label: {
                  if transferType == option.value {
                    Label(option.label, systemImage: "checkmark")
                  } else {
                    Text(option.label)
                  }
                }
              }
            } label: {
              menuValueLabel(
                transferTypes.first(where: { $0.value == transferType })?.label ?? "自动")
            }
          }

          Divider().overlay(NativeTheme.chipBorder)

          groupedPickerRow(title: "覆盖模式") {
            Menu {
              ForEach(overwriteModes, id: \.value) { option in
                Button {
                  overwriteMode = option.value
                } label: {
                  if overwriteMode == option.value {
                    Label(option.label, systemImage: "checkmark")
                  } else {
                    Text(option.label)
                  }
                }
              }
            } label: {
              menuValueLabel(
                overwriteModes.first(where: { $0.value == overwriteMode })?.label ?? "从不覆盖")
            }
          }
        }
      }
    }
  }

  /// 分组 2：媒体识别覆写（类型、数据源、媒体 ID 搜索、季集/音乐参数）。
  private var mediaOverrideSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionHeader("媒体识别与定位（可选）")
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 12) {
          groupedPickerRow(title: "媒体类型") {
            Menu {
              ForEach(mediaTypes, id: \.value) { option in
                Button {
                  mediaType = option.value
                } label: {
                  if mediaType == option.value {
                    Label(option.label, systemImage: "checkmark")
                  } else {
                    Text(option.label)
                  }
                }
              }
            } label: {
              menuValueLabel(
                mediaTypes.first(where: { $0.value == mediaType })?.label ?? "自动识别")
            }
          }

          Divider().overlay(NativeTheme.chipBorder)

          groupedPickerRow(title: "识别数据源") {
            Menu {
              ForEach(mediaSources, id: \.value) { option in
                Button {
                  mediaSource = option.value
                } label: {
                  if mediaSource == option.value {
                    Label(option.label, systemImage: "checkmark")
                  } else {
                    Text(option.label)
                  }
                }
              }
            } label: {
              menuValueLabel(
                mediaSources.first(where: { $0.value == mediaSource })?.label ?? "自动")
            }
          }

          Divider().overlay(NativeTheme.chipBorder)

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("指定媒体 ID")
                .font(.subheadline)
                .foregroundStyle(.primary)
              Spacer()
              Button {
                showingMediaPicker = true
              } label: {
                Label("搜索媒体", systemImage: "magnifyingglass")
                  .font(.caption.weight(.medium))
                  .foregroundStyle(NativeTheme.brand)
              }
              .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
              TextField("留空自动识别，或输入 TMDB / 豆瓣 / BGM / MBID", text: $mediaID)
                .textFieldStyle(.plain)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NativeTheme.chipFill)
                }
              if !mediaID.isEmpty {
                Button {
                  mediaID = ""
                  selectedMediaTitle = nil
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
              }
            }
            if let selectedMediaTitle {
              Text("已选：\(selectedMediaTitle)")
                .font(.caption2)
                .foregroundStyle(NativeTheme.brand)
            }
          }

          if mediaType == "电视剧" || mediaType.isEmpty {
            Divider().overlay(NativeTheme.chipBorder)
            HStack(spacing: 10) {
              compactField(title: "指定季号", placeholder: "如 1", text: $seasonText, numeric: true)
              compactField(title: "指定集数", placeholder: "如 1-12", text: $episodeDetail)
              compactField(title: "集数偏移", placeholder: "如 EP+12", text: $episodeOffset)
            }
          }

          if mediaType == "音乐" {
            Divider().overlay(NativeTheme.chipBorder)
            groupedPickerRow(title: "音乐实体类型") {
              Menu {
                Button("自动") { musicType = "" }
                Button("专辑 (album)") { musicType = "album" }
                Button("单曲 (recording)") { musicType = "recording" }
              } label: {
                menuValueLabel(
                  musicType == "album"
                    ? "专辑" : (musicType == "recording" ? "单曲" : "自动"))
              }
            }
            if musicType == "album" {
              groupedPickerRow(title: "曲目对齐方式") {
                Menu {
                  Button("严格校验 (strict)") { musicTrackMatch = "strict" }
                  Button("忽略时长 (ignore_duration)") { musicTrackMatch = "ignore_duration" }
                  Button("按路径顺序 (sequential)") { musicTrackMatch = "sequential" }
                } label: {
                  menuValueLabel(musicTrackMatch)
                }
              }
            }
          }
        }
      }
    }
  }

  /// 分组 3：整理行为与高级开关。
  private var behaviorSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionHeader("执行选项")
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 12) {
          Toggle("后台异步执行", isOn: $runInBackground)
            .font(.subheadline)
            .tint(NativeTheme.brand)

          if historyLogID != nil {
            Divider().overlay(NativeTheme.chipBorder)
            Toggle("复用历史识别信息", isOn: $fromHistory)
              .font(.subheadline)
              .tint(NativeTheme.brand)
          }

          Divider().overlay(NativeTheme.chipBorder)
          DisclosureGroup("更多高级参数", isExpanded: $showingAdvancedOptions) {
            VStack(alignment: .leading, spacing: 11) {
              triStatePicker(title: "刮削元数据", selection: $scrapeChoice)
              triStatePicker(title: "按类型分类子目录", selection: $typeFolderChoice)
              triStatePicker(title: "按二级分类子目录", selection: $categoryFolderChoice)
              compactField(
                title: "最低文件大小阈值 (MiB)", placeholder: "0 表示不限制",
                text: $minFilesizeText, numeric: true)
              if mediaType != "音乐" {
                Divider().overlay(NativeTheme.chipBorder)
                compactField(
                  title: "自定义剧集识别格式", placeholder: "留空使用默认", text: $episodeFormat)
                Divider().overlay(NativeTheme.chipBorder)
                compactField(title: "指定 PART", placeholder: "如 part1", text: $episodePart)
                Divider().overlay(NativeTheme.chipBorder)
                compactField(title: "剧集组 ID", placeholder: "可选", text: $episodeGroup)
              }
            }
            .padding(.top, 10)
          }
          .font(.subheadline.weight(.medium))
          .tint(NativeTheme.brand)
        }
      }
    }
  }

  /// 手动整理预览结果展示区。
  private var previewSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionHeader("整理预览（\(previewItems.count) 项）")
      CinematicPanel(padding: 13) {
        VStack(alignment: .leading, spacing: 10) {
          if let previewError {
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NativeTheme.warning)
              Text(previewError)
                .font(.caption)
                .foregroundStyle(.primary)
            }
          }
          ForEach(Array(previewItems.enumerated()), id: \.offset) { index, entry in
            if index > 0 { Divider().overlay(NativeTheme.chipBorder) }
            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 6) {
                Image(
                  systemName: entry.success == false
                    ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(
                  entry.success == false ? NativeTheme.danger : NativeTheme.success)
                Text(entry.displayTitle)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                Spacer(minLength: 4)
                if let type = entry.type, !type.isEmpty {
                  Text(type)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
              if let src = entry.source, !src.isEmpty {
                Text("源：\((src as NSString).lastPathComponent)")
                  .font(.caption2.monospaced())
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              if let target = entry.target, !target.isEmpty {
                Text("至：\(target)")
                  .font(.caption2.monospaced())
                  .foregroundStyle(NativeTheme.brand)
                  .lineLimit(2)
              }
              if let message = entry.message, !message.isEmpty, entry.success == false {
                Text(message)
                  .font(.caption2)
                  .foregroundStyle(NativeTheme.warning)
              }
            }
          }
        }
      }
    }
  }

  /// 底部双按钮：预览与提交整理。
  private var actionFooter: some View {
    HStack(spacing: 12) {
      Button {
        Task { await executeTransfer(preview: true) }
      } label: {
        HStack(spacing: 6) {
          if isPreviewing {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "eye")
          }
          Text(isPreviewing ? "预览中…" : "预览整理")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(NativeTheme.chipFill)
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(NativeTheme.chipBorder, lineWidth: 0.7)
            }
        }
      }
      .buttonStyle(.plain)
      .disabled(isPreviewing || isSubmitting)

      Button {
        Task { await executeTransfer(preview: false) }
      } label: {
        HStack(spacing: 6) {
          if isSubmitting {
            ProgressView().controlSize(.small).tint(.white)
          } else {
            Image(systemName: "tray.and.arrow.down")
          }
          Text(isSubmitting ? "正在整理…" : "开始整理")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(NativeTheme.brand)
        }
      }
      .buttonStyle(.plain)
      .disabled(isPreviewing || isSubmitting)
    }
    .padding(.top, 4)
  }

  private var filteredLibraryDirectories: [NativeTransferDirectoryOption] {
    libraryDirectories.filter { dir in
      guard !dir.libraryPath.isEmpty else { return false }
      return dir.libraryStorage.isEmpty || dir.libraryStorage == targetStorage
    }
  }

  private func sectionHeader(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
  }

  private func groupedPickerRow<Content: View>(
    title: String,
    @ViewBuilder trailing: () -> Content
  ) -> some View {
    HStack {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.primary)
      Spacer(minLength: 10)
      trailing()
    }
  }

  private func menuValueLabel(_ value: String) -> some View {
    HStack(spacing: 4) {
      Text(value)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
  }

  private func triStatePicker(title: String, selection: Binding<TriStateChoice>) -> some View {
    groupedPickerRow(title: title) {
      Menu {
        ForEach(TriStateChoice.allCases) { option in
          Button {
            selection.wrappedValue = option
          } label: {
            if selection.wrappedValue == option {
              Label(option.rawValue, systemImage: "checkmark")
            } else {
              Text(option.rawValue)
            }
          }
        }
      } label: {
        menuValueLabel(selection.wrappedValue.rawValue)
      }
    }
  }

  private func compactField(
    title: String,
    placeholder: String,
    text: Binding<String>,
    numeric: Bool = false
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .layoutPriority(1)
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.trailing)
        .keyboardType(numeric ? .numberPad : .default)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
    .padding(.vertical, 2)
  }

  /// 初始化存储列表、媒体库目录、自动目的路径与已有整理历史检测。
  private func bootstrap() async {
    isLoadingMetadata = true
    defer { isLoadingMetadata = false }
    async let storagesTask: Void = loadStoragesIfNeeded()
    async let dirsTask: Void = loadLibraryDirectories()
    async let matchTask: Void = matchTargetPath()
    async let historyTask: Void = checkExistingHistory()
    _ = await (storagesTask, dirsTask, matchTask, historyTask)
  }

  private func loadStoragesIfNeeded() async {
    guard let endpoint = try? APIEndpoint(path: ["storage", "options"]),
      let loaded = try? await session.request(endpoint, as: [NativeStorageOption].self).value,
      !loaded.isEmpty
    else { return }
    storages = loaded
    if !loaded.contains(where: { $0.value == targetStorage }), let first = loaded.first {
      targetStorage = first.value
    }
  }

  private func loadLibraryDirectories() async {
    guard
      let endpoint = try? APIEndpoint(
        path: ["storage", "directories"],
        query: [URLQueryItem(name: "directory_type", value: "library")]),
      let loaded = try? await session.request(
        endpoint, as: [NativeTransferDirectoryOption].self
      ).value
    else { return }
    libraryDirectories = loaded
  }

  private func matchTargetPath() async {
    let payload = buildRequestPayload(preview: false, onlyForMatch: true)
    guard let body = try? JSONEncoder().encode(payload),
      let endpoint = try? APIEndpoint(
        path: ["transfer", "manual", "target-path"], method: .post, body: body,
        responseContract: .payload, timeout: 20),
      let resp = try? await session.request(
        endpoint, as: NativeManualTransferEnvelope<NativeManualTargetPathData>.self
      ).value,
      let data = resp.data
    else { return }
    if let matchedStorage = data.targetStorage, !matchedStorage.isEmpty {
      targetStorage = matchedStorage
    }
    if let matchedPath = data.targetPath, !matchedPath.isEmpty {
      matchedTargetHint = matchedPath
      if targetPath.isEmpty {
        targetPath = matchedPath
      }
    }
    if transferType.isEmpty, let mode = data.transferType, !mode.isEmpty {
      transferType = mode
    }
  }

  private func checkExistingHistory() async {
    guard fileItem != nil else { return }
    let payload = buildRequestPayload(preview: false, onlyForMatch: true)
    guard let body = try? JSONEncoder().encode(payload),
      let endpoint = try? APIEndpoint(
        path: ["transfer", "manual", "history"], method: .post, body: body,
        responseContract: .payload, timeout: 15),
      let resp = try? await session.request(
        endpoint, as: NativeManualTransferEnvelope<NativeManualHistoryInfo>.self
      ).value,
      let data = resp.data
    else { return }
    matchedHistoryCount = data.historyCount ?? 0
    if data.reorganize == true {
      reorganize = true
    }
  }

  private func buildRequestPayload(preview: Bool, onlyForMatch: Bool = false)
    -> NativeManualTransferPayload
  {
    let trimmedTargetPath = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedMediaID = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
    let parsedSeason = Int(seasonText.trimmingCharacters(in: .whitespacesAndNewlines))
    let parsedMinSize = Int(minFilesizeText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    let cleanedDetail = episodeDetail.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanedOffset = episodeOffset.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanedPart = episodePart.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanedFormat = episodeFormat.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanedGroup = episodeGroup.trimmingCharacters(in: .whitespacesAndNewlines)

    return NativeManualTransferPayload(
      fileitem: fileItem,
      logid: historyLogID,
      targetStorage: targetStorage.isEmpty ? nil : targetStorage,
      targetPath: onlyForMatch || trimmedTargetPath.isEmpty ? nil : trimmedTargetPath,
      mediaSource: mediaSource.isEmpty ? nil : mediaSource,
      mediaID: trimmedMediaID.isEmpty ? nil : trimmedMediaID,
      musicType: (mediaType == "音乐" && !musicType.isEmpty) ? musicType : nil,
      musicTrackMatch: (mediaType == "音乐" && musicType == "album") ? musicTrackMatch : "strict",
      typeName: mediaType.isEmpty ? nil : mediaType,
      season: parsedSeason,
      transferType: transferType.isEmpty ? nil : transferType,
      episodeFormat: cleanedFormat.isEmpty ? nil : cleanedFormat,
      episodeDetail: cleanedDetail.isEmpty ? nil : cleanedDetail,
      episodePart: cleanedPart.isEmpty ? nil : cleanedPart,
      episodeOffset: cleanedOffset.isEmpty ? nil : cleanedOffset,
      minFilesize: max(0, parsedMinSize),
      scrape: scrapeChoice.boolValue,
      libraryTypeFolder: typeFolderChoice.boolValue,
      libraryCategoryFolder: categoryFolderChoice.boolValue,
      fromHistory: fromHistory,
      episodeGroup: cleanedGroup.isEmpty ? nil : cleanedGroup,
      preview: preview,
      reorganize: skipSuccess ? false : reorganize,
      skipSuccess: skipSuccess)
  }

  /// 执行整理预览或正式整理提交（`POST /api/v1/transfer/manual?background=...`）。
  private func executeTransfer(preview: Bool) async {
    if preview {
      isPreviewing = true
      previewError = nil
    } else {
      isSubmitting = true
      submitFeedback = nil
    }
    defer {
      if preview { isPreviewing = false } else { isSubmitting = false }
    }
    do {
      let payload = buildRequestPayload(preview: preview)
      let body = try JSONEncoder().encode(payload)
      let endpoint = try APIEndpoint(
        path: ["transfer", "manual"],
        method: .post,
        query: [
          URLQueryItem(
            name: "background", value: preview ? "false" : (runInBackground ? "true" : "false"))
        ],
        body: body,
        responseContract: .payload,
        timeout: preview ? 60 : (runInBackground ? 30 : 120))
      let resp = try await session.request(
        endpoint, as: NativeManualTransferEnvelope<NativeManualTransferResultPayload>.self
      ).value
      if preview {
        previewItems = resp.data?.items ?? []
        if resp.success == false || previewItems.isEmpty {
          previewError =
            resp.message?.isEmpty == false
            ? resp.message! : (resp.data?.message ?? "未生成可预览的整理项。")
        }
      } else {
        if resp.success == false {
          submitIsError = true
          submitFeedback =
            resp.message?.isEmpty == false
            ? resp.message! : (resp.data?.message ?? "整理提交失败，请检查参数后重试。")
          return
        }
        let message =
          resp.message?.isEmpty == false
          ? resp.message!
          : (runInBackground ? "已提交后台整理任务「\(sourceTitleHint)」。" : "整理已完成「\(sourceTitleHint)」。")
        onCompleted(message)
        dismiss()
      }
    } catch {
      if preview {
        previewError = "预览失败：\(error.localizedDescription)"
      } else {
        submitIsError = true
        submitFeedback = "整理请求失败：\(error.localizedDescription)"
      }
    }
  }
}

/// 手动整理内的媒体快速搜索选择器（`GET /api/v1/media/search`）。
@MainActor
private struct NativeManualTransferMediaPickerSheet: View {
  struct PickedMedia {
    let source: String
    let mediaID: String
    let displayTitle: String
    let mediaType: String?
    let musicType: String?
  }

  let session: NativeSession
  let preferMusic: Bool
  let onPicked: (PickedMedia) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var keyword: String
  @State private var searchScope: String
  @State private var results: [NativeManualMediaCandidate] = []
  @State private var isSearching = false
  @State private var errorMessage: String?

  init(
    session: NativeSession,
    initialKeyword: String,
    preferMusic: Bool,
    onPicked: @escaping (PickedMedia) -> Void
  ) {
    self.session = session
    self.preferMusic = preferMusic
    self.onPicked = onPicked
    _keyword = State(initialValue: initialKeyword)
    _searchScope = State(initialValue: preferMusic ? "music" : "media")
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        VStack(spacing: 10) {
          HStack(spacing: 8) {
            TextField("输入片名、剧名或专辑名搜索", text: $keyword)
              .textFieldStyle(.plain)
              .font(.subheadline)
              .submitLabel(.search)
              .onSubmit { Task { await runSearch() } }
            Button("搜索") { Task { await runSearch() } }
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(NativeTheme.brand)
          }
          .padding(.horizontal, 13)
          .padding(.vertical, 10)
          .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
              .fill(NativeTheme.chipFill)
          }
          .padding(.horizontal, CinematicStyle.margin)

          Picker("范围", selection: $searchScope) {
            Text("影视").tag("media")
            Text("音乐").tag("music")
          }
          .pickerStyle(.segmented)
          .padding(.horizontal, CinematicStyle.margin)
          .onChange(of: searchScope) { _ in
            if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Task { await runSearch() }
            }
          }

          if isSearching {
            ScrollView {
              VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                  CinematicPanel(padding: 10) {
                    HStack(spacing: 11) {
                      NativeSkeletonBlock(width: 44, height: 64, cornerRadius: 8)
                      VStack(alignment: .leading, spacing: 5) {
                        NativeSkeletonBlock(height: 15, cornerRadius: 5)
                        HStack(spacing: 6) {
                          NativeSkeletonBlock(width: 34, height: 12, cornerRadius: 4)
                          NativeSkeletonBlock(width: 112, height: 11, cornerRadius: 4)
                        }
                      }
                      Spacer(minLength: 0)
                    }
                  }
                }
              }
              .nativeSkeletonShimmer()
              .padding(.horizontal, CinematicStyle.margin)
              .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .transition(.opacity)
          } else if let errorMessage {
            Text(errorMessage)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if results.isEmpty {
            Text("输入关键词搜索并点选目标媒体以自动填入 ID")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .padding()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollView {
              LazyVStack(spacing: 10) {
                ForEach(results) { item in
                  Button {
                    onPicked(
                      PickedMedia(
                        source: item.resolvedSource,
                        mediaID: item.resolvedMediaID,
                        displayTitle: item.displayTitle,
                        mediaType: item.type,
                        musicType: item.musicType))
                    dismiss()
                  } label: {
                    CinematicPanel(padding: 10) {
                      HStack(spacing: 11) {
                        NativeMediaArtwork(
                          session: session,
                          reference: NativeMediaDetailPage.resolveArtwork(
                            item.posterPath, source: item.resolvedSource),
                          role: .poster,
                          maximumWidth: 240
                        )
                        .frame(width: 44, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                          Text(item.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                          HStack(spacing: 6) {
                            if let type = item.type, !type.isEmpty {
                              Text(type)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(NativeTheme.brand)
                            }
                            Text("\(item.resolvedSource) · \(item.resolvedMediaID)")
                              .font(.caption2.monospaced())
                              .foregroundStyle(.secondary)
                              .lineLimit(1)
                          }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                          .font(.caption2)
                          .foregroundStyle(.tertiary)
                      }
                    }
                  }
                  .buttonStyle(.plain)
                }
              }
              .padding(.horizontal, CinematicStyle.margin)
              .padding(.bottom, 16)
            }
          }
        }
        .padding(.top, 10)
      }
      .navigationTitle("选择识别媒体")
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
        }
      }
      .task {
        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          await runSearch()
        }
      }
    }
    .nativeGlassSheet()
  }

  private func runSearch() async {
    let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    isSearching = true
    errorMessage = nil
    defer { isSearching = false }
    do {
      let endpoint = try APIEndpoint(
        path: ["media", "search"],
        query: [
          URLQueryItem(name: "title", value: trimmed),
          URLQueryItem(name: "type", value: searchScope),
          URLQueryItem(name: "page", value: "1"),
          URLQueryItem(name: "count", value: "20"),
        ],
        timeout: 25)
      let loaded = try await session.request(endpoint, as: [NativeManualMediaCandidate].self).value
      results = loaded.filter { !$0.resolvedMediaID.isEmpty }
      if results.isEmpty {
        errorMessage = "未找到匹配的媒体结果，请简化关键词重试。"
      }
    } catch {
      errorMessage = "搜索失败：\(error.localizedDescription)"
    }
  }
}

/// 文件操作提示载体。
private struct NativeFileFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/storage/options` 存储源选项，兼容后端 `type`/`name` 与 `value`/`title` 两种键名。
struct NativeStorageOption: Decodable, Sendable, Identifiable {
  let value: String
  let title: String

  var id: String { value }

  init(value: String, title: String) {
    self.value = value
    self.title = title
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let resolvedValue =
      try container.decodeIfPresent(String.self, forKey: .type)
      ?? container.decodeIfPresent(String.self, forKey: .value)
      ?? ""
    let resolvedTitle =
      try container.decodeIfPresent(String.self, forKey: .name)
      ?? container.decodeIfPresent(String.self, forKey: .title)
      ?? resolvedValue
    guard !resolvedValue.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container, debugDescription: "存储选项缺少有效类型标识")
    }
    value = resolvedValue
    title = resolvedTitle
  }

  private enum CodingKeys: String, CodingKey {
    case type, name, value, title
  }
}

/// `POST /api/v1/storage/list`、`/mkdir`、`/rename`、`/delete` 与 `/transfer/manual` 共用的文件项模型。
struct NativeFileItem: Codable, Sendable, Identifiable {
  let storage: String
  let type: String
  let path: String
  let name: String?
  let basename: String?
  let fileExtension: String?
  let size: Int64?
  let modifyTime: Double?
  let fileid: String?
  let parentFileid: String?

  init(
    storage: String, type: String, path: String, name: String? = nil, basename: String? = nil,
    fileExtension: String? = nil, size: Int64? = nil, modifyTime: Double? = nil,
    fileid: String? = nil, parentFileid: String? = nil
  ) {
    self.storage = storage
    self.type = type
    self.path = path
    self.name = name
    self.basename = basename
    self.fileExtension = fileExtension
    self.size = size
    self.modifyTime = modifyTime
    self.fileid = fileid
    self.parentFileid = parentFileid
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    storage = (try? c.decodeIfPresent(String.self, forKey: .storage)) ?? "local"
    type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "file"
    path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? "/"
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    basename = try? c.decodeIfPresent(String.self, forKey: .basename)
    fileExtension = try? c.decodeIfPresent(String.self, forKey: .fileExtension)
    size = try? c.decodeIfPresent(Int64.self, forKey: .size)
    if let ts = try? c.decodeIfPresent(Double.self, forKey: .modifyTime) {
      modifyTime = ts
    } else if let tsStr = try? c.decodeIfPresent(String.self, forKey: .modifyTime),
      let parsed = Double(tsStr)
    {
      modifyTime = parsed
    } else {
      modifyTime = nil
    }
    fileid = try? c.decodeIfPresent(String.self, forKey: .fileid)
    parentFileid = try? c.decodeIfPresent(String.self, forKey: .parentFileid)
  }

  var id: String { "\(storage)|\(type)|\(fileid ?? path)" }

  var normalizedExtension: String {
    let raw = fileExtension ?? URL(fileURLWithPath: path).pathExtension
    return raw.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
  }

  var safeIdentifier: String {
    let raw = displayName
    let clean = raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(24)
    return clean.isEmpty ? "item" : String(String.UnicodeScalarView(clean))
  }

  var isDirectory: Bool { type.lowercased() == "dir" }

  var displayName: String {
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    return URL(fileURLWithPath: path).lastPathComponent
  }

  var symbolName: String {
    if isDirectory { return "folder.fill" }
    let ext = (fileExtension ?? URL(fileURLWithPath: path).pathExtension).lowercased()
    if ["mkv", "mp4", "avi", "mov", "ts", "iso", "strm"].contains(ext) { return "film" }
    if ["flac", "mp3", "m4a", "wav", "aac", "alac", "ape", "dsf"].contains(ext) {
      return "music.note"
    }
    if ["srt", "ass", "ssa", "vtt", "sub"].contains(ext) { return "captions.bubble" }
    if ["jpg", "jpeg", "png", "webp"].contains(ext) { return "photo" }
    return "doc"
  }

  var metadataSummary: String? {
    if isDirectory { return "文件夹" }
    var parts: [String] = []
    if let size, size > 0 { parts.append(Self.formatBytes(Double(size))) }
    let ext = (fileExtension ?? URL(fileURLWithPath: path).pathExtension).uppercased()
    if !ext.isEmpty { parts.append(ext) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

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

  private enum CodingKeys: String, CodingKey {
    case storage
    case type
    case path
    case name
    case basename
    case fileExtension = "extension"
    case size
    case modifyTime = "modify_time"
    case fileid
    case parentFileid = "parent_fileid"
  }
}

/// 智能推荐命名接口响应载荷。
private struct NativeRecommendNameResponse: Decodable, Sendable {
  struct NamePayload: Decodable, Sendable {
    let name: String?
  }
  let success: Bool?
  let message: String?
  let data: NamePayload?
}

/// 通用 `_SchemaResponse` 信封。
private struct NativeManualTransferEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
  let success: Bool?
  let message: String?
  let data: T?
}

/// `GET /api/v1/storage/directories` 目录选项。
private struct NativeTransferDirectoryOption: Decodable, Sendable, Identifiable {
  let name: String?
  let libraryStorage: String
  let libraryPath: String
  let mediaType: String?
  let transferType: String?

  var id: String { "\(libraryStorage)|\(libraryPath)|\(name ?? "")" }

  var displayLabel: String {
    let prefix = (name?.isEmpty == false) ? "\(name!) · " : ""
    return "\(prefix)\(libraryPath)"
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case libraryStorage = "library_storage"
    case libraryPath = "library_path"
    case mediaType = "media_type"
    case transferType = "transfer_type"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    libraryStorage = (try? c.decodeIfPresent(String.self, forKey: .libraryStorage)) ?? "local"
    libraryPath = (try? c.decodeIfPresent(String.self, forKey: .libraryPath)) ?? ""
    mediaType = try? c.decodeIfPresent(String.self, forKey: .mediaType)
    transferType = try? c.decodeIfPresent(String.self, forKey: .transferType)
  }
}

/// `POST /api/v1/transfer/manual/target-path` 响应数据。
private struct NativeManualTargetPathData: Decodable, Sendable {
  let targetStorage: String?
  let targetPath: String?
  let transferType: String?
  let scrape: Bool?

  private enum CodingKeys: String, CodingKey {
    case targetStorage = "target_storage"
    case targetPath = "target_path"
    case transferType = "transfer_type"
    case scrape
  }
}

/// `POST /api/v1/transfer/manual/history` 响应数据。
private struct NativeManualHistoryInfo: Decodable, Sendable {
  let reorganize: Bool?
  let historyCount: Int?

  private enum CodingKeys: String, CodingKey {
    case reorganize
    case historyCount = "history_count"
  }
}

/// `POST /api/v1/transfer/manual` 请求体（严格匹配 `ManualTransferItem`）。
private struct NativeManualTransferPayload: Encodable, Sendable {
  let fileitem: NativeFileItem?
  let logid: Int?
  let targetStorage: String?
  let targetPath: String?
  let mediaSource: String?
  let mediaID: String?
  let musicType: String?
  let musicTrackMatch: String
  let typeName: String?
  let season: Int?
  let transferType: String?
  let episodeFormat: String?
  let episodeDetail: String?
  let episodePart: String?
  let episodeOffset: String?
  let minFilesize: Int
  let scrape: Bool?
  let libraryTypeFolder: Bool?
  let libraryCategoryFolder: Bool?
  let fromHistory: Bool
  let episodeGroup: String?
  let preview: Bool
  let reorganize: Bool
  let skipSuccess: Bool

  private enum CodingKeys: String, CodingKey {
    case fileitem
    case logid
    case targetStorage = "target_storage"
    case targetPath = "target_path"
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case musicType = "music_type"
    case musicTrackMatch = "music_track_match"
    case typeName = "type_name"
    case season
    case transferType = "transfer_type"
    case episodeFormat = "episode_format"
    case episodeDetail = "episode_detail"
    case episodePart = "episode_part"
    case episodeOffset = "episode_offset"
    case minFilesize = "min_filesize"
    case scrape
    case libraryTypeFolder = "library_type_folder"
    case libraryCategoryFolder = "library_category_folder"
    case fromHistory = "from_history"
    case episodeGroup = "episode_group"
    case preview
    case reorganize
    case skipSuccess = "skip_success"
  }
}

/// 手动整理预览/提交结果数据载荷。
private struct NativeManualTransferResultPayload: Decodable, Sendable {
  let items: [NativeManualTransferPreviewItem]?
  let message: String?
}

/// 单项手动整理预览条目。
private struct NativeManualTransferPreviewItem: Decodable, Sendable {
  let source: String?
  let target: String?
  let success: Bool?
  let message: String?
  let type: String?
  let title: String?
  let season: Int?
  let episode: Int?

  var displayTitle: String {
    let base =
      (title?.isEmpty == false) ? title! : ((source as NSString?)?.lastPathComponent ?? "媒体项")
    if let season, let episode {
      return String(format: "%@ S%02dE%02d", base, season, episode)
    } else if let season {
      return String(format: "%@ S%02d", base, season)
    }
    return base
  }
}

/// 手动整理搜索媒体候选项。
private struct NativeManualMediaCandidate: Decodable, Sendable, Identifiable {
  let title: String?
  let year: String?
  let type: String?
  let mediaSource: String?
  let mediaID: String?
  let musicType: String?
  let posterPath: String?

  var id: String { "\(resolvedSource)|\(resolvedMediaID)|\(title ?? "")" }

  var resolvedSource: String {
    mediaSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? mediaSource! : "themoviedb"
  }

  var resolvedMediaID: String {
    mediaID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  var displayTitle: String {
    let base = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知媒体"
    if let year, !year.isEmpty { return "\(base) (\(year))" }
    return base
  }

  private enum CodingKeys: String, CodingKey {
    case title, year, type
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case musicType = "music_type"
    case posterPath = "poster_path"
  }
}
