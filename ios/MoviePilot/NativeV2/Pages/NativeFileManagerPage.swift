import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生多存储文件浏览器：支持存储切换、目录钻取、面包屑返回、新建文件夹与二次确认删除。
@MainActor
struct NativeFileManagerPage: View {
  let session: NativeSession

  @State private var storages: [NativeStorageOption] = [
    NativeStorageOption(value: "local", title: "本地")
  ]
  @State private var activeStorage = "local"
  @State private var pathStack: [NativeFileItem] = [
    NativeFileItem(storage: "local", type: "dir", path: "/", name: "根目录")
  ]
  @State private var items: [NativeFileItem] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var attempt = 0
  @State private var showingNewFolder = false
  @State private var newFolderName = ""
  @State private var pendingDelete: NativeFileItem?
  @State private var feedback: NativeFileFeedback?

  /// 连续深色紫玫瑰渐变背景、存储切换胶囊、当前路径面包屑与目录/文件玻璃列表。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if storages.count > 1 {
            storagePickerBar
          }
          breadcrumbBar
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && items.isEmpty {
            ProgressView("正在读取目录内容…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 220)
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
      .refreshable { await loadCurrentDirectory() }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-files-scroll")
    }
    .navigationTitle("文件管理")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      if canManage {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            newFolderName = ""
            showingNewFolder = true
          } label: {
            Image(systemName: "folder.badge.plus")
          }
          .accessibilityLabel("新建文件夹")
          .accessibilityIdentifier("native-files-mkdir")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          attempt += 1
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("刷新目录")
        .accessibilityIdentifier("native-files-refresh")
      }
    }
    .task { await loadStorages() }
    .task(id: "\(activeStorage)|\(currentDirectory.path)|\(attempt)") {
      await loadCurrentDirectory()
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

  /// 当前用户具备管理权限时允许新建目录和删除文件。
  private var canManage: Bool {
    session.user.isSuperuser || session.user.allows(.init(category: .manage))
  }

  /// 当前处于栈顶的目录节点。
  private var currentDirectory: NativeFileItem {
    pathStack.last
      ?? NativeFileItem(storage: activeStorage, type: "dir", path: "/", name: "根目录")
  }

  /// 文件夹优先排列，其次按名称排序。
  private var sortedItems: [NativeFileItem] {
    items.sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
  }

  /// 多存储切换胶囊栏。
  private var storagePickerBar: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(storages) { storage in
          let selected = activeStorage == storage.value
          Button {
            switchStorage(to: storage.value)
          } label: {
            Text(storage.title)
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
          .accessibilityIdentifier("native-files-storage-\(storage.value)")
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  /// 当前路径与返回上级目录栏。
  private var breadcrumbBar: some View {
    CinematicPanel(padding: 10) {
      HStack(spacing: 10) {
        if pathStack.count > 1 {
          Button {
            pathStack.removeLast()
          } label: {
            Label("上级", systemImage: "arrow.uturn.backward")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background { Capsule().fill(.white.opacity(0.14)) }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("native-files-up")
        }
        Text(currentDirectory.path)
          .font(.caption.monospaced())
          .foregroundStyle(.white.opacity(0.84))
          .lineLimit(1)
          .truncationMode(.head)
        Spacer(minLength: 0)
        Text("\(items.count) 项")
          .font(.caption2)
          .foregroundStyle(.white.opacity(0.55))
      }
    }
  }

  /// 单个目录或文件玻璃行。
  private func fileRow(_ item: NativeFileItem) -> some View {
    CinematicPanel(padding: 12) {
      HStack(spacing: 12) {
        Button {
          if item.isDirectory {
            pathStack.append(item)
          }
        } label: {
          HStack(spacing: 12) {
            ZStack {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                  item.isDirectory
                    ? Color(red: 0.48, green: 0.36, blue: 0.72).opacity(0.50)
                    : .white.opacity(0.10))
              Image(systemName: item.symbolName)
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
              Text(item.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
              if let meta = item.metadataSummary {
                Text(meta)
                  .font(.caption2)
                  .foregroundStyle(.white.opacity(0.60))
              }
            }
            Spacer(minLength: 4)
            if item.isDirectory {
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-file-open-\(item.safeIdentifier)")

        if canManage {
          Button(role: .destructive) {
            pendingDelete = item
          } label: {
            Image(systemName: "trash")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.58))
              .frame(minWidth: 34, minHeight: 34)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("删除 \(item.displayName)")
          .accessibilityIdentifier("native-file-delete-\(item.safeIdentifier)")
        }
      }
    }
  }

  /// 轻量操作反馈条。
  private func feedbackBanner(_ feedback: NativeFileFeedback) -> some View {
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
    .accessibilityIdentifier("native-files-feedback")
  }

  /// 空目录状态卡片。
  private var emptyCard: some View {
    CinematicPanel {
      VStack(spacing: 10) {
        Image(systemName: "folder")
          .font(.largeTitle)
          .foregroundStyle(.white.opacity(0.55))
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

  /// 请求当前目录内容（`POST /api/v1/storage/list`）。
  private func loadCurrentDirectory() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let body = try JSONEncoder().encode(currentDirectory)
      let endpoint = try APIEndpoint(
        path: ["storage", "list"], method: .post, body: body, timeout: 30)
      let loaded = try await session.request(endpoint, as: [NativeFileItem].self).value
      try Task.checkCancellation()
      items = loaded
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
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
      await loadCurrentDirectory()
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
      feedback = NativeFileFeedback(isError: false, message: "已删除「\(item.displayName)」。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeFileFeedback(isError: true, message: "删除失败，请稍后重试。")
    }
  }
}

/// 文件操作提示载体。
private struct NativeFileFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/storage/options` 存储源选项，兼容后端 `type`/`name` 与 `value`/`title` 两种键名。
private struct NativeStorageOption: Decodable, Sendable, Identifiable {
  let value: String
  let title: String

  /// 存储标识作为唯一键。
  var id: String { value }

  /// 直接构造默认本地存储回退项。
  init(value: String, title: String) {
    self.value = value
    self.title = title
  }

  /// 优先解码 MoviePilot v3 的 `type`/`name` 字段，兼顾 `value`/`title`。
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

  /// 兼容两种存储选项键名。
  private enum CodingKeys: String, CodingKey {
    case type
    case name
    case value
    case title
  }
}

/// `POST /api/v1/storage/list`、`/mkdir` 与 `/delete` 共用的文件项模型。
private struct NativeFileItem: Codable, Sendable, Identifiable {
  let storage: String
  let type: String
  let path: String
  let name: String?
  let basename: String?
  let fileExtension: String?
  let size: Int64?
  let fileid: String?
  let parentFileid: String?

  /// 构造目录查询请求项。
  init(
    storage: String, type: String, path: String, name: String? = nil, basename: String? = nil,
    fileExtension: String? = nil, size: Int64? = nil, fileid: String? = nil,
    parentFileid: String? = nil
  ) {
    self.storage = storage
    self.type = type
    self.path = path
    self.name = name
    self.basename = basename
    self.fileExtension = fileExtension
    self.size = size
    self.fileid = fileid
    self.parentFileid = parentFileid
  }

  /// 唯一列表键。
  var id: String { "\(storage)|\(type)|\(fileid ?? path)" }

  /// 用于 UI 测试的安全字母数字键。
  var safeIdentifier: String {
    let raw = displayName
    let clean = raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(24)
    return clean.isEmpty ? "item" : String(String.UnicodeScalarView(clean))
  }

  /// 是否为目录节点。
  var isDirectory: Bool { type.lowercased() == "dir" }

  /// 展示名称。
  var displayName: String {
    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      return name
    }
    return URL(fileURLWithPath: path).lastPathComponent
  }

  /// 按目录与常见视频/音频/字幕扩展名选择原生 SF Symbol。
  var symbolName: String {
    if isDirectory { return "folder.fill" }
    let ext = (fileExtension ?? URL(fileURLWithPath: path).pathExtension).lowercased()
    if ["mkv", "mp4", "avi", "mov", "ts", "iso", "strm"].contains(ext) { return "film" }
    if ["flac", "mp3", "m4a", "wav", "aac"].contains(ext) { return "music.note" }
    if ["srt", "ass", "ssa", "vtt", "sub"].contains(ext) { return "captions.bubble" }
    if ["jpg", "jpeg", "png", "webp"].contains(ext) { return "photo" }
    return "doc"
  }

  /// 文件副标展示大小与扩展名。
  var metadataSummary: String? {
    if isDirectory { return "文件夹" }
    var parts: [String] = []
    if let size, size > 0 { parts.append(Self.formatBytes(Double(size))) }
    let ext = (fileExtension ?? URL(fileURLWithPath: path).pathExtension).uppercased()
    if !ext.isEmpty { parts.append(ext) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

  /// 对应后端 `_SchemaFileItem` 字段。
  private enum CodingKeys: String, CodingKey {
    case storage
    case type
    case path
    case name
    case basename
    case fileExtension = "extension"
    case size
    case fileid
    case parentFileid = "parent_fileid"
  }
}
