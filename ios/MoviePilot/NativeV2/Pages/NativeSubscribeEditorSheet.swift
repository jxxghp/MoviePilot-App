import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生订阅完整规则编辑弹层（十.1）：对齐 Web `SubscribeEditDialog.vue`，修正画质/分辨率/特效正则，补全站点、间隔、洗版完整集数、IMDB 搜索、规则组、季数、剧集组、分类、目录建议、音乐 5 项音质参数与删除订阅。
@MainActor
struct NativeSubscribeEditorSheet: View {
  let session: NativeSession
  let subscribeID: Int
  let title: String
  let onSaved: () -> Void

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var loaded: NativeSubscribeDetailDraft?
  @State private var draft = NativeSubscribeDetailDraft()
  @State private var downloaders: [String] = []
  @State private var sites: [NativeSubSiteOption] = []
  @State private var ruleGroups: [String] = []
  @State private var pathSuggestions: [String] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isSaving = false
  @State private var isDeleting = false
  @State private var showsDeleteConfirm = false
  @State private var errorMessage: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let errorMessage {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(
                    NativeTheme.danger)
                  Text(errorMessage).font(.caption).foregroundStyle(.primary)
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
              if draft.mediaType == "音乐" {
                musicQualitySection
              } else {
                videoQualitySection
              }
              scopeAndRuleSection
              filterSection
              deliverySection
              deleteSection
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
      .alert("删除订阅", isPresented: $showsDeleteConfirm) {
        Button("确认删除", role: .destructive) { Task { await deleteSubscribe() } }
        Button("取消", role: .cancel) {}
      } message: {
        Text("确认删除「\(title)」的订阅吗？")
      }
    }
    .nativeAppearanceRoot()
    .task { await load() }
  }

  private var hasChanges: Bool {
    guard let loaded else { return false }
    return draft != loaded
  }

  // MARK: - 1. 影视画质与洗版 / 音乐音质分组

  private var videoQualitySection: some View {
    groupedSection("画质与洗版") {
      pickerRow("质量", selection: $draft.quality, options: Self.qualityOptions, id: "quality")
      CinematicFormDivider()
      pickerRow(
        "分辨率", selection: $draft.resolution, options: Self.resolutionOptions, id: "resolution")
      CinematicFormDivider()
      pickerRow("特效", selection: $draft.effect, options: Self.effectOptions, id: "effect")
      CinematicFormDivider()
      toggleRow("自动洗版", isOn: $draft.bestVersion, id: "best-version")
      if draft.bestVersion && draft.mediaType == "电视剧" {
        CinematicFormDivider()
        toggleRow("仅洗版完整季合集", isOn: $draft.bestVersionFull, id: "best-version-full")
      }
    }
  }

  private var musicQualitySection: some View {
    groupedSection("音乐音质要求") {
      pickerRow(
        "音质等级", selection: $draft.audioQuality, options: Self.audioQualityOptions,
        id: "audio-quality")
      CinematicFormDivider()
      pickerRow(
        "音频格式", selection: $draft.audioFormat, options: Self.audioFormatOptions, id: "audio-format")
      CinematicFormDivider()
      intPickerRow("最低码率", selection: $draft.minBitrate, options: Self.audioBitrateOptions)
      CinematicFormDivider()
      intPickerRow("最低位深", selection: $draft.minBitDepth, options: Self.audioBitDepthOptions)
      CinematicFormDivider()
      intPickerRow("最低采样率", selection: $draft.minSampleRate, options: Self.audioSampleRateOptions)
      CinematicFormDivider()
      toggleRow("自动洗版", isOn: $draft.bestVersion, id: "best-version")
    }
  }

  // MARK: - 2. 站点范围、规则组与搜索策略

  private var scopeAndRuleSection: some View {
    groupedSection("站点与优先级规则") {
      NavigationLink {
        NativeSubSiteSelectorView(session: session, sites: sites, selection: $draft.sites)
      } label: {
        disclosureRow("订阅站点", value: draft.sites.isEmpty ? "跟随系统设置" : "已选 \(draft.sites.count) 站")
      }
      .buttonStyle(.plain)
      CinematicFormDivider()
      NavigationLink {
        NativeSubRuleGroupSelectorView(options: ruleGroups, selection: $draft.filterGroups)
      } label: {
        disclosureRow(
          "优先级规则组",
          value: draft.filterGroups.isEmpty ? "跟随系统设置" : "已选 \(draft.filterGroups.count) 组")
      }
      .buttonStyle(.plain)
      CinematicFormDivider()
      toggleRow("使用 IMDB ID 精确搜索", isOn: $draft.searchImdbID, id: "search-imdb")
      CinematicFormDivider()
      HStack {
        Text("搜索间隔").font(.subheadline)
        Spacer()
        Stepper(
          draft.searchInterval > 0 ? "\(draft.searchInterval) 分钟" : "默认",
          value: $draft.searchInterval, in: 0...1440, step: 30
        )
        .font(.subheadline.monospacedDigit())
        .fixedSize()
      }
      .padding(.horizontal, 15).padding(.vertical, 9)
    }
  }

  // MARK: - 3. 过滤与识别规则

  private var filterSection: some View {
    groupedSection("过滤与识别规则") {
      inputRow("搜索关键字", text: $draft.keyword, placeholder: "默认使用片名", id: "keyword")
      CinematicFormDivider()
      inputRow("包含规则", text: $draft.include, placeholder: "正则，如 中字|简繁", id: "include")
      CinematicFormDivider()
      inputRow("排除规则", text: $draft.exclude, placeholder: "正则，如 枪版|CAM", id: "exclude")
      CinematicFormDivider()
      inputRow("媒体分类", text: $draft.mediaCategory, placeholder: "自定义二级分类", id: "media-category")
      CinematicFormDivider()
      inputRow("自定义识别词", text: $draft.customWords, placeholder: "可选替换词", id: "custom-words")
    }
  }

  // MARK: - 4. 集数范围、下载器与保存目录

  private var deliverySection: some View {
    groupedSection("集数与下载保存") {
      if draft.mediaType == "电视剧" {
        HStack {
          Text("订阅季数").font(.subheadline)
          Spacer()
          Stepper(
            draft.season > 0 ? "第 \(draft.season) 季" : "默认",
            value: $draft.season, in: 0...99
          )
          .font(.subheadline.monospacedDigit())
          .fixedSize()
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        CinematicFormDivider()
        HStack {
          Text("总集数").font(.subheadline)
          Spacer()
          Stepper(
            draft.totalEpisode > 0 ? "\(draft.totalEpisode) 集" : "自动",
            value: $draft.totalEpisode, in: 0...2000
          )
          .font(.subheadline.monospacedDigit())
          .fixedSize()
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        CinematicFormDivider()
        HStack {
          Text("开始集数").font(.subheadline)
          Spacer()
          Stepper(
            draft.startEpisode > 0 ? "第 \(draft.startEpisode) 集" : "默认",
            value: $draft.startEpisode, in: 0...2000
          )
          .font(.subheadline.monospacedDigit())
          .fixedSize()
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        CinematicFormDivider()
        inputRow(
          "剧集组 ID", text: $draft.episodeGroup, placeholder: "TMDB Episode Group",
          id: "episode-group")
        CinematicFormDivider()
      }
      if !downloaders.isEmpty {
        HStack {
          Text("下载器").font(.subheadline)
          Spacer()
          Picker("下载器", selection: $draft.downloader) {
            Text("默认").tag("")
            ForEach(downloaders, id: \.self) { client in Text(client).tag(client) }
          }
          .tint(appearance.accentColor)
          .accessibilityIdentifier("native-subscribe-editor-downloader")
        }
        .padding(.horizontal, 15).padding(.vertical, 10)
        CinematicFormDivider()
      }
      HStack(spacing: 8) {
        Text("保存目录").font(.subheadline)
        Spacer(minLength: 6)
        TextField("留空跟随系统目录", text: $draft.savePath)
          .font(.subheadline)
          .multilineTextAlignment(.trailing)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("native-subscribe-editor-save-path")
        if !pathSuggestions.isEmpty {
          Menu {
            Button("清空（跟随系统）") { draft.savePath = "" }
            Divider()
            ForEach(pathSuggestions, id: \.self) { p in
              Button(p) { draft.savePath = p }
            }
          } label: {
            Image(systemName: "folder.badge.plus")
              .font(.subheadline)
              .foregroundStyle(appearance.accentColor)
          }
        }
      }
      .padding(.horizontal, 15).padding(.vertical, 11)
    }
  }

  private var deleteSection: some View {
    CinematicPanel(padding: 0) {
      Button(role: .destructive) {
        showsDeleteConfirm = true
      } label: {
        HStack(spacing: 6) {
          if isDeleting { ProgressView().controlSize(.small).tint(NativeTheme.danger) }
          Text("删除此订阅")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NativeTheme.danger)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
      }
      .buttonStyle(.plain)
      .disabled(isDeleting)
      .accessibilityIdentifier("native-subscribe-editor-delete")
    }
  }

  // MARK: - 通用分组列表行

  private func groupedSection<Content: View>(
    _ header: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(header)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) { content() }
      }
    }
  }

  private func disclosureRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title).font(.subheadline).foregroundStyle(.primary)
      Spacer()
      Text(value).font(.caption).foregroundStyle(.secondary)
      Image(systemName: "chevron.right")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary.opacity(0.55))
    }
    .padding(.horizontal, 15).padding(.vertical, 12)
    .contentShape(Rectangle())
  }

  private func toggleRow(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
    Toggle(title, isOn: isOn)
      .font(.subheadline)
      .tint(appearance.accentColor)
      .padding(.horizontal, 15).padding(.vertical, 10)
      .accessibilityIdentifier("native-subscribe-editor-\(id)")
  }

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
        if !selection.wrappedValue.isEmpty,
          !options.contains(where: { $0.value == selection.wrappedValue })
        {
          Text("自定义 (\(selection.wrappedValue))").tag(selection.wrappedValue)
        }
      }
      .tint(appearance.accentColor)
      .accessibilityIdentifier("native-subscribe-editor-\(id)")
    }
    .padding(.horizontal, 15).padding(.vertical, 10)
  }

  private func intPickerRow(
    _ label: String, selection: Binding<Int>, options: [(value: Int, title: String)]
  ) -> some View {
    HStack {
      Text(label).font(.subheadline)
      Spacer()
      Picker(label, selection: selection) {
        ForEach(options, id: \.value) { item in
          Text(item.title).tag(item.value)
        }
      }
      .tint(appearance.accentColor)
    }
    .padding(.horizontal, 15).padding(.vertical, 10)
  }

  private func inputRow(
    _ label: String, text: Binding<String>, placeholder: String, id: String
  ) -> some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline)
      Spacer(minLength: 8)
      TextField(placeholder, text: text)
        .font(.subheadline)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .frame(maxWidth: 210)
        .accessibilityIdentifier("native-subscribe-editor-\(id)")
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }

  // MARK: - 网络加载与保存

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
      async let clientsTask: [NativeSubscribeClientSummary]? = {
        guard let ep = try? APIEndpoint(path: ["download", "clients"]) else { return nil }
        return try? await session.request(ep, as: [NativeSubscribeClientSummary].self).value
      }()
      async let sitesTask: [NativeSubSiteOption]? = {
        guard let ep = try? APIEndpoint(path: ["site"], trailingSlash: true) else { return nil }
        return try? await session.request(ep, as: [NativeSubSiteOption].self).value
      }()
      async let groupsTask: [String]? = {
        guard
          let ep = try? APIEndpoint(
            path: ["rule", "groups"], query: [URLQueryItem(name: "include_usage", value: "false")])
        else { return nil }
        return try? await session.request(ep, as: NativeSubRuleGroupsBox.self).value.names
      }()
      async let pathsTask: [String]? = {
        guard let ep = try? APIEndpoint(path: ["download", "paths"]) else { return nil }
        let list = try? await session.request(ep, as: [NativeSubPathBrief].self).value
        return list?.compactMap { $0.downloadPath ?? $0.savePath }.filter { !$0.isEmpty }
      }()

      let (detail, clients, loadedSites, loadedGroups, loadedPaths) = await (
        try detailTask, clientsTask, sitesTask, groupsTask, pathsTask
      )
      try Task.checkCancellation()
      let snapshot = NativeSubscribeDetailDraft(raw: detail)
      loaded = snapshot
      draft = snapshot
      downloaders = (clients ?? []).compactMap(\.name).filter { !$0.isEmpty }
      sites = (loadedSites ?? []).filter(\.isActive)
      ruleGroups = loadedGroups ?? []
      pathSuggestions = Array(Set(loadedPaths ?? [])).sorted()
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

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

  private func deleteSubscribe() async {
    isDeleting = true
    defer { isDeleting = false }
    do {
      let ep = try APIEndpoint(path: ["subscribe", String(subscribeID)], method: .delete)
      try await session.perform(ep, requiring: .init(category: .subscribe))
      onSaved()
      dismiss()
    } catch {
      errorMessage = "删除订阅失败，请稍后重试。"
    }
  }

  // 对齐 Web `constants.ts` 真实正则映射
  private static let qualityOptions: [(String, String)] = [
    ("", "全部"),
    ("Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD", "蓝光原盘"),
    ("Remux", "REMUX"),
    ("Blu-?Ray", "BluRay"),
    ("UHD|UltraHD", "UHD"),
    ("WEB-?DL|WEB-?RIP", "WEB-DL"),
    ("HDTV", "HDTV"),
    ("[Hx].?265|HEVC", "H.265"),
    ("[Hx].?264|AVC", "H.264"),
  ]

  private static let resolutionOptions: [(String, String)] = [
    ("", "全部"),
    ("4K|2160p|x2160", "4K"),
    ("1080[pi]|x1080", "1080p"),
    ("720[pi]|x720", "720p"),
  ]

  private static let effectOptions: [(String, String)] = [
    ("", "全部"),
    ("Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+", "杜比视界"),
    ("Dolby[\\s.]*\\+?Atmos|Atmos", "杜比全景声"),
    ("[\\s.]+HDR[\\s.]+|HDR10|HDR10\\+", "HDR"),
    ("[\\s.]+SDR[\\s.]+", "SDR"),
  ]

  private static let audioQualityOptions: [(String, String)] = [
    ("", "全部"), ("hires", "Hi-Res"), ("hires|lossless", "无损及以上"), ("lossy", "有损"),
  ]

  private static let audioFormatOptions: [(String, String)] = [
    ("", "全部"),
    ("DSD|FLAC|ALAC|APE|WAV|AIFF|PCM", "无损格式"),
    ("FLAC", "FLAC"), ("DSD", "DSD"), ("ALAC", "ALAC"), ("WAV", "WAV"),
    ("MP3", "MP3"), ("AAC", "AAC"), ("OGG", "OGG"), ("OPUS", "OPUS"),
  ]

  private static let audioBitrateOptions: [(Int, String)] = [
    (0, "不限"), (128000, "128 kbps"), (192000, "192 kbps"), (256000, "256 kbps"),
    (320000, "320 kbps"),
  ]

  private static let audioBitDepthOptions: [(Int, String)] = [
    (0, "不限"), (16, "16-bit"), (24, "24-bit"), (32, "32-bit"),
  ]

  private static let audioSampleRateOptions: [(Int, String)] = [
    (0, "不限"), (44100, "44.1 kHz"), (48000, "48 kHz"), (96000, "96 kHz"), (192000, "192 kHz"),
  ]
}

// MARK: - 站点与规则组子选择页

@MainActor
private struct NativeSubSiteSelectorView: View {
  let session: NativeSession
  let sites: [NativeSubSiteOption]
  @Binding var selection: Set<Int>
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(sites.enumerated()), id: \.element.id) { idx, site in
              if idx > 0 { CinematicFormDivider() }
              Button {
                if selection.contains(site.id) {
                  selection.remove(site.id)
                } else {
                  selection.insert(site.id)
                }
              } label: {
                HStack(spacing: 12) {
                  NativeSiteIconView(session: session, siteID: site.id, size: 28, active: true)
                  Text(site.name).font(.subheadline).foregroundStyle(.primary)
                  Spacer()
                  if selection.contains(site.id) {
                    Image(systemName: "checkmark").font(.subheadline.weight(.semibold))
                      .foregroundStyle(appearance.accentColor)
                  }
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
      }
    }
    .navigationTitle("订阅站点")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(selection.isEmpty ? "全选" : "清空") {
          if selection.isEmpty { selection = Set(sites.map(\.id)) } else { selection.removeAll() }
        }
      }
    }
  }
}

@MainActor
private struct NativeSubRuleGroupSelectorView: View {
  let options: [String]
  @Binding var selection: Set<String>
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { idx, name in
              if idx > 0 { CinematicFormDivider() }
              Button {
                if selection.contains(name) {
                  selection.remove(name)
                } else {
                  selection.insert(name)
                }
              } label: {
                HStack {
                  Text(name).font(.subheadline).foregroundStyle(.primary)
                  Spacer()
                  if selection.contains(name) {
                    Image(systemName: "checkmark").font(.subheadline.weight(.semibold))
                      .foregroundStyle(appearance.accentColor)
                  }
                }
                .padding(.horizontal, 15).padding(.vertical, 12)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
      }
    }
    .navigationTitle("优先级规则组")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
  }
}

// MARK: - 解码与草稿模型

private struct NativeSubscribeClientSummary: Decodable, Sendable { let name: String? }

private struct NativeSubSiteOption: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let isActive: Bool
  private enum CodingKeys: String, CodingKey {
    case id, name
    case isActive = "is_active"
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(Int.self, forKey: .id)
    name = (try? c.decode(String.self, forKey: .name)) ?? "站点 #\(id)"
    isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
  }
}

private struct NativeSubRuleGroupsBox: Decodable, Sendable {
  struct Group: Decodable, Sendable { let name: String? }
  let ruleGroups: [Group]?
  var names: [String] { (ruleGroups ?? []).compactMap(\.name).filter { !$0.isEmpty } }
  private enum CodingKeys: String, CodingKey { case ruleGroups = "rule_groups" }
}

private struct NativeSubPathBrief: Decodable, Sendable {
  let savePath: String?
  let downloadPath: String?
  private enum CodingKeys: String, CodingKey {
    case savePath = "save_path"
    case downloadPath = "download_path"
  }
}

private struct NativeSubscribeDetailRaw: Decodable, Sendable {
  let type: String?
  let quality: String?
  let resolution: String?
  let effect: String?
  let bestVersion: Int?
  let bestVersionFull: Bool?
  let searchImdbID: Int?
  let searchInterval: Int?
  let sites: [Int]?
  let filterGroups: [String]?
  let keyword: String?
  let include: String?
  let exclude: String?
  let customWords: String?
  let mediaCategory: String?
  let episodeGroup: String?
  let season: Int?
  let totalEpisode: Int?
  let startEpisode: Int?
  let downloader: String?
  let savePath: String?
  let audioQuality: String?
  let audioFormat: String?
  let minBitrate: Int?
  let minBitDepth: Int?
  let minSampleRate: Int?

  private enum CodingKeys: String, CodingKey {
    case type, quality, resolution, effect, sites, keyword, include, exclude, season, downloader
    case bestVersion = "best_version"
    case bestVersionFull = "best_version_full"
    case searchImdbID = "search_imdbid"
    case searchInterval = "search_interval"
    case filterGroups = "filter_groups"
    case customWords = "custom_words"
    case mediaCategory = "media_category"
    case episodeGroup = "episode_group"
    case totalEpisode = "total_episode"
    case startEpisode = "start_episode"
    case savePath = "save_path"
    case audioQuality = "audio_quality"
    case audioFormat = "audio_format"
    case minBitrate = "min_bitrate"
    case minBitDepth = "min_bit_depth"
    case minSampleRate = "min_sample_rate"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    type = try? c.decode(String.self, forKey: .type)
    quality = try? c.decode(String.self, forKey: .quality)
    resolution = try? c.decode(String.self, forKey: .resolution)
    effect = try? c.decode(String.self, forKey: .effect)
    bestVersion =
      (try? c.decode(Int.self, forKey: .bestVersion))
      ?? ((try? c.decode(Bool.self, forKey: .bestVersion)) == true ? 1 : 0)
    bestVersionFull =
      (try? c.decode(Bool.self, forKey: .bestVersionFull))
      ?? ((try? c.decode(Int.self, forKey: .bestVersionFull)) == 1)
    searchImdbID =
      (try? c.decode(Int.self, forKey: .searchImdbID))
      ?? ((try? c.decode(Bool.self, forKey: .searchImdbID)) == true ? 1 : 0)
    searchInterval = try? c.decode(Int.self, forKey: .searchInterval)
    sites = try? c.decode([Int].self, forKey: .sites)
    filterGroups = try? c.decode([String].self, forKey: .filterGroups)
    keyword = try? c.decode(String.self, forKey: .keyword)
    include = try? c.decode(String.self, forKey: .include)
    exclude = try? c.decode(String.self, forKey: .exclude)
    customWords = try? c.decode(String.self, forKey: .customWords)
    mediaCategory = try? c.decode(String.self, forKey: .mediaCategory)
    episodeGroup = try? c.decode(String.self, forKey: .episodeGroup)
    season = try? c.decode(Int.self, forKey: .season)
    totalEpisode = try? c.decode(Int.self, forKey: .totalEpisode)
    startEpisode = try? c.decode(Int.self, forKey: .startEpisode)
    downloader = try? c.decode(String.self, forKey: .downloader)
    savePath = try? c.decode(String.self, forKey: .savePath)
    audioQuality = try? c.decode(String.self, forKey: .audioQuality)
    audioFormat = try? c.decode(String.self, forKey: .audioFormat)
    minBitrate = try? c.decode(Int.self, forKey: .minBitrate)
    minBitDepth = try? c.decode(Int.self, forKey: .minBitDepth)
    minSampleRate = try? c.decode(Int.self, forKey: .minSampleRate)
  }
}

private struct NativeSubscribeDetailDraft: Equatable {
  var mediaType = ""
  var quality = ""
  var resolution = ""
  var effect = ""
  var bestVersion = false
  var bestVersionFull = false
  var searchImdbID = false
  var searchInterval = 0
  var sites: Set<Int> = []
  var filterGroups: Set<String> = []
  var keyword = ""
  var include = ""
  var exclude = ""
  var customWords = ""
  var mediaCategory = ""
  var episodeGroup = ""
  var season = 0
  var totalEpisode = 0
  var startEpisode = 0
  var downloader = ""
  var savePath = ""
  var audioQuality = ""
  var audioFormat = ""
  var minBitrate = 0
  var minBitDepth = 0
  var minSampleRate = 0

  init() {}

  init(raw: NativeSubscribeDetailRaw) {
    mediaType = raw.type ?? ""
    quality = raw.quality ?? ""
    resolution = raw.resolution ?? ""
    effect = raw.effect ?? ""
    bestVersion = (raw.bestVersion ?? 0) == 1
    bestVersionFull = raw.bestVersionFull ?? false
    searchImdbID = (raw.searchImdbID ?? 0) == 1
    searchInterval = max(raw.searchInterval ?? 0, 0)
    sites = Set(raw.sites ?? [])
    filterGroups = Set(raw.filterGroups ?? [])
    keyword = raw.keyword ?? ""
    include = raw.include ?? ""
    exclude = raw.exclude ?? ""
    customWords = raw.customWords ?? ""
    mediaCategory = raw.mediaCategory ?? ""
    episodeGroup = raw.episodeGroup ?? ""
    season = max(raw.season ?? 0, 0)
    totalEpisode = max(raw.totalEpisode ?? 0, 0)
    startEpisode = max(raw.startEpisode ?? 0, 0)
    downloader = raw.downloader ?? ""
    savePath = raw.savePath ?? ""
    audioQuality = raw.audioQuality ?? ""
    audioFormat = raw.audioFormat ?? ""
    minBitrate = max(raw.minBitrate ?? 0, 0)
    minBitDepth = max(raw.minBitDepth ?? 0, 0)
    minSampleRate = max(raw.minSampleRate ?? 0, 0)
  }

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
    if bestVersion != baseline.bestVersion { payload["best_version"] = bestVersion ? 1 : 0 }
    if bestVersionFull != baseline.bestVersionFull {
      payload["best_version_full"] = bestVersionFull
    }
    if searchImdbID != baseline.searchImdbID { payload["search_imdbid"] = searchImdbID ? 1 : 0 }
    if searchInterval != baseline.searchInterval {
      payload["search_interval"] = searchInterval > 0 ? searchInterval : NSNull()
    }
    if sites != baseline.sites { payload["sites"] = Array(sites).sorted() }
    if filterGroups != baseline.filterGroups {
      payload["filter_groups"] = Array(filterGroups).sorted()
    }
    assignOptional("keyword", keyword, baseline.keyword)
    assignOptional("include", include, baseline.include)
    assignOptional("exclude", exclude, baseline.exclude)
    assignOptional("custom_words", customWords, baseline.customWords)
    assignOptional("media_category", mediaCategory, baseline.mediaCategory)
    assignOptional("episode_group", episodeGroup, baseline.episodeGroup)
    if mediaType == "电视剧" {
      if season != baseline.season { payload["season"] = season > 0 ? season : NSNull() }
      if totalEpisode != baseline.totalEpisode { payload["total_episode"] = totalEpisode }
      if startEpisode != baseline.startEpisode { payload["start_episode"] = startEpisode }
    }
    if mediaType == "音乐" {
      assignOptional("audio_quality", audioQuality, baseline.audioQuality)
      assignOptional("audio_format", audioFormat, baseline.audioFormat)
      if minBitrate != baseline.minBitrate {
        payload["min_bitrate"] = minBitrate > 0 ? minBitrate : NSNull()
      }
      if minBitDepth != baseline.minBitDepth {
        payload["min_bit_depth"] = minBitDepth > 0 ? minBitDepth : NSNull()
      }
      if minSampleRate != baseline.minSampleRate {
        payload["min_sample_rate"] = minSampleRate > 0 ? minSampleRate : NSNull()
      }
    }
    assignOptional("downloader", downloader, baseline.downloader)
    assignOptional("save_path", savePath, baseline.savePath)
    return payload
  }
}
