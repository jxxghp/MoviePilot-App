import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生订阅高级规则编辑弹层：从 `GET /api/v1/subscribe/{id}` 读取完整配置，显式单次保存至 `PUT /api/v1/subscribe/`。
@MainActor
struct NativeSubscribeEditorSheet: View {
  let session: NativeSession
  let subscribeID: Int
  let title: String
  let onSaved: () -> Void

  @State private var loaded: NativeSubscribeDetailDraft?
  @State private var draft = NativeSubscribeDetailDraft()
  @State private var downloaders: [String] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @Environment(\.dismiss) private var dismiss

  /// 连续紫玫瑰深色渐变、分组透色表单卡片与原生取消/保存工具栏动作。
  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let errorMessage {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                  Text(errorMessage).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
                  Spacer(minLength: 0)
                }
              }
              .accessibilityIdentifier("native-subscribe-editor-error")
            }
            if isLoading && loaded == nil {
              ProgressView("正在读取订阅规则…")
                .tint(.primary)
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if loadFailed && loaded == nil {
              CinematicPanel {
                VStack(alignment: .leading, spacing: 10) {
                  Label("暂时无法读取订阅详情", systemImage: "exclamationmark.triangle").font(.headline)
                  Button("重试") { Task { await load() } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("native-subscribe-editor-retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            } else {
              qualitySection
              filterSection
              deliverySection
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("native-subscribe-editor-scroll")
      }
      .navigationTitle("编辑订阅 · \(title)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("取消")
          .accessibilityIdentifier("native-subscribe-editor-cancel")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await save() }
          } label: {
            Text(isSaving ? "保存中…" : "保存").fontWeight(.semibold)
          }
          .disabled(isSaving || loaded == nil || !hasChanges)
          .accessibilityIdentifier("native-subscribe-editor-save")
        }
      }
    }
    .nativeAppearanceRoot()
    .task { await load() }
  }

  /// 是否相对服务端快照有实际改动。
  private var hasChanges: Bool {
    guard let loaded else { return false }
    return draft != loaded
  }

  /// 画质、分辨率、特效与洗版分组。
  private var qualitySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("画质与洗版").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel {
        VStack(spacing: 14) {
          pickerRow("质量", selection: $draft.quality, options: Self.qualityOptions, id: "quality")
          Divider().overlay(.primary.opacity(0.08))
          pickerRow(
            "分辨率", selection: $draft.resolution, options: Self.resolutionOptions, id: "resolution")
          Divider().overlay(.primary.opacity(0.08))
          pickerRow("特效", selection: $draft.effect, options: Self.effectOptions, id: "effect")
          Divider().overlay(.primary.opacity(0.08))
          Toggle("自动洗版", isOn: $draft.bestVersion)
            .font(.subheadline)
            .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
            .accessibilityIdentifier("native-subscribe-editor-best-version")
        }
      }
    }
  }

  /// 关键词、包含/排除与自定义识别词分组。
  private var filterSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("过滤与识别规则").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel {
        VStack(spacing: 14) {
          inputRow("搜索关键字", text: $draft.keyword, placeholder: "默认使用片名", id: "keyword")
          Divider().overlay(.primary.opacity(0.08))
          inputRow("包含规则", text: $draft.include, placeholder: "正则，如 中字|简繁", id: "include")
          Divider().overlay(.primary.opacity(0.08))
          inputRow("排除规则", text: $draft.exclude, placeholder: "正则，如 枪版|CAM", id: "exclude")
          Divider().overlay(.primary.opacity(0.08))
          inputRow("自定义识别词", text: $draft.customWords, placeholder: "可选替换词", id: "custom-words")
        }
      }
    }
  }

  /// 集数范围、下载器与保存路径分组。
  private var deliverySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("下载与保存").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel {
        VStack(spacing: 14) {
          if draft.mediaType == "电视剧" {
            Stepper(value: $draft.totalEpisode, in: 0...2000) {
              HStack {
                Text("总集数").font(.subheadline)
                Spacer()
                Text(draft.totalEpisode > 0 ? "\(draft.totalEpisode) 集" : "自动")
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(.primary.opacity(0.78))
              }
            }
            Divider().overlay(.primary.opacity(0.08))
            Stepper(value: $draft.startEpisode, in: 0...2000) {
              HStack {
                Text("开始集数").font(.subheadline)
                Spacer()
                Text(draft.startEpisode > 0 ? "第 \(draft.startEpisode) 集" : "默认")
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(.primary.opacity(0.78))
              }
            }
            Divider().overlay(.primary.opacity(0.08))
          }
          if !downloaders.isEmpty {
            HStack {
              Text("下载器").font(.subheadline)
              Spacer()
              Picker("下载器", selection: $draft.downloader) {
                Text("默认").tag("")
                ForEach(downloaders, id: \.self) { client in
                  Text(client).tag(client)
                }
              }
              .tint(.primary)
              .accessibilityIdentifier("native-subscribe-editor-downloader")
            }
            Divider().overlay(.primary.opacity(0.08))
          }
          inputRow("保存路径", text: $draft.savePath, placeholder: "留空跟随系统目录", id: "save-path")
        }
      }
    }
  }

  /// 通用下拉选项行。
  private func pickerRow(
    _ label: String, selection: Binding<String>, options: [(value: String, title: String)],
    id: String
  ) -> some View {
    HStack {
      Text(label).font(.subheadline)
      Spacer()
      Picker(label, selection: selection) {
        ForEach(options, id: \.value) { item in
          Text(item.title).tag(item.value)
        }
      }
      .tint(.primary)
      .accessibilityIdentifier("native-subscribe-editor-\(id)")
    }
  }

  /// 通用单行文本输入行。
  private func inputRow(
    _ label: String, text: Binding<String>, placeholder: String, id: String
  ) -> some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline)
      Spacer(minLength: 8)
      TextField(
        placeholder,
        text: text,
        prompt: Text(placeholder).foregroundColor(.white.opacity(0.42))
      )
      .multilineTextAlignment(.trailing)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .frame(maxWidth: 200)
      .accessibilityIdentifier("native-subscribe-editor-\(id)")
    }
  }

  /// 并发读取订阅详情与可用下载器列表。
  private func load() async {
    isLoading = true
    loadFailed = false
    errorMessage = nil
    defer { isLoading = false }
    do {
      let detailEndpoint = try APIEndpoint(path: ["subscribe", String(subscribeID)])
      async let detailTask = session.request(
        detailEndpoint, as: NativeSubscribeDetailRaw.self, requiring: .init(category: .subscribe)
      ).value
      let clientsEndpoint = try APIEndpoint(path: ["download", "clients"])
      async let clientsTask = try? session.request(
        clientsEndpoint, as: [NativeSubscribeClientSummary].self
      ).value
      let (detail, clients) = try await (detailTask, clientsTask)
      try Task.checkCancellation()
      let snapshot = NativeSubscribeDetailDraft(raw: detail)
      loaded = snapshot
      draft = snapshot
      downloaders = (clients ?? []).compactMap(\.name).filter { !$0.isEmpty }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  /// 仅提交 ID 与用户修改过的公共可写字段至 `PUT /api/v1/subscribe/`，不自动重试。
  private func save() async {
    guard let baseline = loaded, hasChanges else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      let payload = draft.writePayload(id: subscribeID, relativeTo: baseline)
      let body = try JSONSerialization.data(withJSONObject: payload)
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .put, body: body, trailingSlash: true)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      try Task.checkCancellation()
      loaded = draft
      onSaved()
      dismiss()
    } catch is CancellationError {
      return
    } catch {
      errorMessage = "保存订阅规则失败，请稍后重试。"
    }
  }

  private static let qualityOptions: [(String, String)] = [
    ("", "默认"), ("蓝光原盘", "蓝光原盘"), ("REMUX", "REMUX"),
    ("BluRay", "BluRay"), ("WEB-DL", "WEB-DL"), ("HDTV", "HDTV"),
  ]

  private static let resolutionOptions: [(String, String)] = [
    ("", "默认"), ("4k", "4K"), ("1080p", "1080p"), ("720p", "720p"),
  ]

  private static let effectOptions: [(String, String)] = [
    ("", "默认"), ("杜比视界", "杜比视界"), ("HDR", "HDR"), ("HQ", "高码率 HQ"),
  ]
}

/// 下载器精简解码项。
private struct NativeSubscribeClientSummary: Decodable, Sendable {
  let name: String?
}

/// `GET /api/v1/subscribe/{id}` 完整可编辑字段解码结构体。
private struct NativeSubscribeDetailRaw: Decodable, Sendable {
  let type: String?
  let quality: String?
  let resolution: String?
  let effect: String?
  let bestVersion: Int?
  let keyword: String?
  let include: String?
  let exclude: String?
  let customWords: String?
  let totalEpisode: Int?
  let startEpisode: Int?
  let downloader: String?
  let savePath: String?

  private enum CodingKeys: String, CodingKey {
    case type, quality, resolution, effect, keyword, include, exclude, downloader
    case bestVersion = "best_version"
    case customWords = "custom_words"
    case totalEpisode = "total_episode"
    case startEpisode = "start_episode"
    case savePath = "save_path"
  }
}

/// 可比对差异的订阅编辑草稿快照。
private struct NativeSubscribeDetailDraft: Equatable {
  var mediaType = ""
  var quality = ""
  var resolution = ""
  var effect = ""
  var bestVersion = false
  var keyword = ""
  var include = ""
  var exclude = ""
  var customWords = ""
  var totalEpisode = 0
  var startEpisode = 0
  var downloader = ""
  var savePath = ""

  /// 空草稿。
  init() {}

  /// 从服务端订阅详情构造快照。
  init(raw: NativeSubscribeDetailRaw) {
    mediaType = raw.type ?? ""
    quality = raw.quality ?? ""
    resolution = raw.resolution ?? ""
    effect = raw.effect ?? ""
    bestVersion = (raw.bestVersion ?? 0) == 1
    keyword = raw.keyword ?? ""
    include = raw.include ?? ""
    exclude = raw.exclude ?? ""
    customWords = raw.customWords ?? ""
    totalEpisode = max(raw.totalEpisode ?? 0, 0)
    startEpisode = max(raw.startEpisode ?? 0, 0)
    downloader = raw.downloader ?? ""
    savePath = raw.savePath ?? ""
  }

  /// 生成仅含 `id` 及用户变更字段的更新载荷，清空项保持 `NSNull` 以显式覆盖旧值。
  func writePayload(id: Int, relativeTo baseline: Self) -> [String: Any] {
    var payload: [String: Any] = ["id": id]
    func assignOptional(_ key: String, _ current: String, _ old: String) {
      let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
      let oldTrimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed != oldTrimmed else { return }
      payload[key] = trimmed.isEmpty ? NSNull() : trimmed
    }
    assignOptional("quality", quality, baseline.quality)
    assignOptional("resolution", resolution, baseline.resolution)
    assignOptional("effect", effect, baseline.effect)
    if bestVersion != baseline.bestVersion {
      payload["best_version"] = bestVersion ? 1 : 0
    }
    assignOptional("keyword", keyword, baseline.keyword)
    assignOptional("include", include, baseline.include)
    assignOptional("exclude", exclude, baseline.exclude)
    assignOptional("custom_words", customWords, baseline.customWords)
    if mediaType == "电视剧" {
      if totalEpisode != baseline.totalEpisode { payload["total_episode"] = totalEpisode }
      if startEpisode != baseline.startEpisode { payload["start_episode"] = startEpisode }
    }
    assignOptional("downloader", downloader, baseline.downloader)
    assignOptional("save_path", savePath, baseline.savePath)
    return payload
  }
}
