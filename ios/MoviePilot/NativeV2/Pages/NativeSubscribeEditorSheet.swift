import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生订阅完整规则编辑弹层：1:1 对齐 Web `SubscribeEditDialog.vue`，覆盖单条订阅编辑与全局默认订阅规则维护。
/// - 置顶展示搜索关键词、剧集总集数与开始集数（支持数字键盘直输 + 步进微调）；
/// - 画质/分辨率/特效支持预设选择与自定义正则输入；音乐订阅专属展示 5 项音质参数；
/// - 搜索间隔严格采用后端「小时（1–8760）」契约并支持「跟随系统 / 自定义」切换；
/// - 支持自动洗版与剧集「全集洗版」联动、TMDB 剧集组接口实时拉取、第 0 季（特别篇）~ 第 100 季、二级分类快选及多行自定义识别词。
@MainActor
struct NativeSubscribeEditorSheet: View {
    /// 区分新增订阅、编辑订阅与编辑默认规则的表单模式。
  enum Mode: Equatable {
    case subscribe(id: Int, title: String)
    case defaultRule(mediaType: String)
  }

  let session: NativeSession
  let mode: Mode
  let onSaved: () -> Void

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var loaded: NativeSubscribeDetailDraft?
  @State private var draft = NativeSubscribeDetailDraft()
  @State private var downloaders: [String] = []
  @State private var sites: [NativeSubSiteOption] = []
  @State private var ruleGroups: [String] = []
  @State private var pathOptions: [NativeSubPathBrief] = []
  @State private var episodeGroups: [NativeSubEpisodeGroupOption] = []
  @State private var categorySuggestions: [String] = []
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isSaving = false
  @State private var isDeleting = false
  @State private var showsDeleteConfirm = false
  @State private var showsFilesSheet = false
  @State private var errorMessage: String?

  // 自定义输入弹窗状态（避免长输入框破坏表单行节奏）
  @State private var activeCustomPrompt: CustomInputTarget?
  @State private var customInputBuffer = ""

  @Environment(\.dismiss) private var dismiss

    /// 标识自定义输入弹窗当前编辑的订阅字段。
  private enum CustomInputTarget: Identifiable {
    case quality
    case resolution
    case effect
    case savePath
    case episodeGroup
    case season
    case mediaCategory

    var id: String {
      switch self {
      case .quality: "quality"
      case .resolution: "resolution"
      case .effect: "effect"
      case .savePath: "savePath"
      case .episodeGroup: "episodeGroup"
      case .season: "season"
      case .mediaCategory: "mediaCategory"
      }
    }

    var title: String {
      switch self {
      case .quality: "自定义质量正则"
      case .resolution: "自定义分辨率正则"
      case .effect: "自定义特效正则"
      case .savePath: "自定义保存路径"
      case .episodeGroup: "指定剧集组 ID"
      case .season: "输入指定季号"
      case .mediaCategory: "自定义媒体类别"
      }
    }

    var placeholder: String {
      switch self {
      case .quality: "如 Blu-?Ray|REMUX"
      case .resolution: "如 2160p|1080p"
      case .effect: "如 DV|HDR10\\+"
      case .savePath: "留空跟随系统下载目录"
      case .episodeGroup: "TMDB Episode Group ID"
      case .season: "0（特别篇）~ 100"
      case .mediaCategory: "留空自动按规则分类"
      }
    }
  }

  /// 编辑指定订阅记录。
  init(
    session: NativeSession,
    subscribeID: Int,
    title: String,
    onSaved: @escaping () -> Void
  ) {
    self.session = session
    self.mode = .subscribe(id: subscribeID, title: title)
    self.onSaved = onSaved
  }

  /// 编辑全局默认订阅规则（电影 / 电视剧 / 音乐）。
  init(
    session: NativeSession,
    defaultMediaType: String,
    onSaved: @escaping () -> Void
  ) {
    self.session = session
    self.mode = .defaultRule(mediaType: defaultMediaType)
    self.onSaved = onSaved
  }

  private var isDefaultMode: Bool {
    if case .defaultRule = mode { return true }
    return false
  }

  private var subscribeID: Int? {
    if case .subscribe(let id, _) = mode { return id }
    return nil
  }

  private var navigationHeading: String {
    switch mode {
    case .subscribe(_, let title):
      return "编辑订阅 · \(title)"
    case .defaultRule(let mediaType):
      return "默认订阅规则 · \(mediaType)"
    }
  }

  private var isTvSubscribe: Bool {
    let lower = draft.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lower == "电视剧" || lower == "tv" || lower == "series"
  }

  private var isMusicSubscribe: Bool {
    let lower = draft.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lower == "音乐" || lower == "music"
  }

  private var isSearchIntervalValid: Bool {
    guard let hours = draft.searchInterval else { return true }
    return (1...8760).contains(hours)
  }

  private var hasChanges: Bool {
    guard let loaded else { return false }
    return draft != loaded
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let errorMessage {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NativeTheme.danger)
                  Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.primary)
                  Spacer(minLength: 0)
                }
              }
              .accessibilityIdentifier("native-subscribe-editor-error")
            }
            if isLoading && loaded == nil {
              if !isDefaultMode {
                filesEntrySection
              }
              NativeCardListSkeletonView(count: 3, style: .formPanel)
                .transition(.opacity)
            } else if loadFailed && loaded == nil {
              CinematicPanel {
                VStack(alignment: .leading, spacing: 10) {
                  Label("暂时无法读取订阅规则", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                  Button("重试") { Task { await load() } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("native-subscribe-editor-retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            } else {
              if !isDefaultMode {
                filesEntrySection
                basicIdentityAndEpisodesSection
              }
              if isMusicSubscribe {
                musicQualitySection
              } else {
                videoQualitySection
              }
              scopeAndDeliverySection
              advancedRulesSection
              if !isDefaultMode {
                deleteSection
              }
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
          .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("native-subscribe-editor-scroll")
      }
      .navigationTitle(navigationHeading)
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") {
            dismiss()
          }
          .tint(.primary)
          .accessibilityIdentifier("native-subscribe-editor-cancel")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await save() }
          } label: {
            Text(isSaving ? "保存中…" : "保存").fontWeight(.semibold)
          }
          .tint(.primary)
          .disabled(isSaving || loaded == nil || !hasChanges || !isSearchIntervalValid)
          .accessibilityIdentifier("native-subscribe-editor-save")
        }
      }
      .alert("取消订阅", isPresented: $showsDeleteConfirm) {
        Button("确认取消订阅", role: .destructive) { Task { await deleteSubscribe() } }
        Button("保留", role: .cancel) {}
      } message: {
        if case .subscribe(_, let subTitle) = mode {
          Text("确认取消并删除「\(subTitle)」的订阅吗？")
        }
      }
      .alert(
        activeCustomPrompt?.title ?? "自定义设置",
        isPresented: Binding(
          get: { activeCustomPrompt != nil },
          set: { if !$0 { activeCustomPrompt = nil } }
        ),
        presenting: activeCustomPrompt
      ) { prompt in
        TextField(prompt.placeholder, text: $customInputBuffer)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("确定") {
          applyCustomPrompt(prompt, value: customInputBuffer)
          activeCustomPrompt = nil
        }
        Button("取消", role: .cancel) {
          activeCustomPrompt = nil
        }
      }
      .sheet(isPresented: $showsFilesSheet) {
        if case .subscribe(let id, let subTitle) = mode {
          NativeSubscribeFilesSheet(
            session: session, subscribeID: id, fallbackTitle: subTitle
          )
          .nativeAdaptiveSheetSizing()
        }
      }
      .onChange(of: draft.bestVersion) { enabled in
        if !enabled && draft.bestVersionFull {
          draft.bestVersionFull = false
        }
      }
    }
    .nativeGlassSheet()
    .task { await load() }
  }

  // MARK: - 0. 关联文件入口

  private var filesEntrySection: some View {
    CinematicPanel(padding: 0) {
      Button {
        showsFilesSheet = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "doc.text.magnifyingglass")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(appearance.accentColor)
          Text("查看订阅文件详情")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.65))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-subscribe-editor-open-files")
    }
  }

  // MARK: - 1. 基础首屏：搜索关键词、总集数、开始集数（对齐 Web 基础页首行）

  private var basicIdentityAndEpisodesSection: some View {
    groupedSection(isTvSubscribe ? "搜索与集数范围" : "搜索关键词") {
      inputRow(
        "搜索关键词",
        text: $draft.keyword,
        placeholder: "默认使用片名",
        id: "keyword"
      )
      if isTvSubscribe {
        CinematicFormDivider()
        episodeNumberRow(
          label: "总集数",
          value: $draft.totalEpisode,
          emptyPlaceholder: "自动获取",
          unitSuffix: "集",
          id: "total-episode"
        )
        CinematicFormDivider()
        episodeNumberRow(
          label: "开始集数",
          value: $draft.startEpisode,
          emptyPlaceholder: "从第 1 集起",
          unitSuffix: "集",
          id: "start-episode"
        )
      }
    }
  }

  // MARK: - 2. 影视画质与洗版 / 音乐音质与洗版

  private var videoQualitySection: some View {
    groupedSection("画质与洗版") {
      presetOrCustomMenuRow(
        "质量",
        selection: $draft.quality,
        options: Self.qualityOptions,
        customTarget: .quality,
        id: "quality"
      )
      CinematicFormDivider()
      presetOrCustomMenuRow(
        "分辨率",
        selection: $draft.resolution,
        options: Self.resolutionOptions,
        customTarget: .resolution,
        id: "resolution"
      )
      CinematicFormDivider()
      presetOrCustomMenuRow(
        "特效",
        selection: $draft.effect,
        options: Self.effectOptions,
        customTarget: .effect,
        id: "effect"
      )
      CinematicFormDivider()
      toggleRow("自动洗版", isOn: $draft.bestVersion, id: "best-version")
      if draft.bestVersion && isTvSubscribe {
        CinematicFormDivider()
        toggleRow("全集洗版（仅整季合集包）", isOn: $draft.bestVersionFull, id: "best-version-full")
      }
      CinematicFormDivider()
      toggleRow("使用 IMDB ID 精确搜索", isOn: $draft.searchImdbID, id: "search-imdb")
      if isDefaultMode {
        CinematicFormDivider()
        toggleRow("订阅时弹出更多规则编辑框", isOn: $draft.showEditDialog, id: "show-edit-dialog")
      }
    }
  }

  private var musicQualitySection: some View {
    groupedSection("音乐音质与洗版") {
      presetMenuRow(
        "音质等级",
        selection: $draft.audioQuality,
        options: Self.audioQualityOptions,
        id: "audio-quality"
      )
      CinematicFormDivider()
      presetMenuRow(
        "音频格式",
        selection: $draft.audioFormat,
        options: Self.audioFormatOptions,
        id: "audio-format"
      )
      CinematicFormDivider()
      intMenuRow("最低码率", selection: $draft.minBitrate, options: Self.audioBitrateOptions)
      CinematicFormDivider()
      intMenuRow("最低位深", selection: $draft.minBitDepth, options: Self.audioBitDepthOptions)
      CinematicFormDivider()
      intMenuRow("最低采样率", selection: $draft.minSampleRate, options: Self.audioSampleRateOptions)
      CinematicFormDivider()
      toggleRow("自动洗版（升级更高音质）", isOn: $draft.bestVersion, id: "best-version")
      if isDefaultMode {
        CinematicFormDivider()
        toggleRow("订阅时弹出更多规则编辑框", isOn: $draft.showEditDialog, id: "show-edit-dialog")
      }
    }
  }

  // MARK: - 3. 订阅站点、定时搜索间隔（小时）与下载保存

  private var scopeAndDeliverySection: some View {
    groupedSection("站点、周期与下载保存") {
      NavigationLink {
        NativeSubSiteSelectorView(session: session, sites: sites, selection: $draft.sites)
      } label: {
        disclosureRow("订阅站点", value: draft.sites.isEmpty ? "跟随系统设置" : "已选 \(draft.sites.count) 站")
      }
      .buttonStyle(.plain)

      CinematicFormDivider()

      // 搜索间隔（对齐 Web：跟随系统 null vs 自定义 1–8760 小时）
      Menu {
        Button {
          draft.searchInterval = nil
        } label: {
          if draft.searchInterval == nil {
            Label("跟随系统设置", systemImage: "checkmark")
          } else {
            Text("跟随系统设置")
          }
        }
        Divider()
        ForEach([6, 12, 24, 48, 72, 168], id: \.self) { hours in
          Button {
            draft.searchInterval = hours
          } label: {
            if draft.searchInterval == hours {
              Label("每 \(hours) 小时", systemImage: "checkmark")
            } else {
              Text("每 \(hours) 小时")
            }
          }
        }
        if draft.searchInterval == nil {
          Button("自定义小时数…") {
            draft.searchInterval = 24
          }
        }
      } label: {
        menuRowLabel(
          "搜索间隔",
          value: draft.searchInterval.map { "自定义 · \($0) 小时" } ?? "跟随系统"
        )
      }
      .buttonStyle(.plain)

      if draft.searchInterval != nil {
        CinematicFormDivider()
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text("搜索间隔（小时）").font(.body).foregroundStyle(.primary)
            if !isSearchIntervalValid {
              Text("请输入 1–8760 的整数小时")
                .font(.caption2)
                .foregroundStyle(NativeTheme.danger)
            }
          }
          Spacer(minLength: 8)
          TextField(
            "1–8760",
            text: Binding(
              get: { draft.searchInterval.map(String.init) ?? "" },
              set: { raw in
                let digits = raw.filter(\.isNumber)
                draft.searchInterval = Int(digits) ?? 0
              }
            )
          )
          .textFieldStyle(.plain)
          .keyboardType(.numberPad)
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(isSearchIntervalValid ? .primary : NativeTheme.danger)
          .multilineTextAlignment(.trailing)
          .frame(width: 96)
          Text("小时")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 52)
      }

      CinematicFormDivider()

      // 下载器
      Menu {
        Button {
          draft.downloader = ""
        } label: {
          if draft.downloader.isEmpty {
            Label("默认", systemImage: "checkmark")
          } else {
            Text("默认")
          }
        }
        ForEach(downloaders, id: \.self) { client in
          Button {
            draft.downloader = client
          } label: {
            if draft.downloader == client {
              Label(client, systemImage: "checkmark")
            } else {
              Text(client)
            }
          }
        }
      } label: {
        menuRowLabel("下载器", value: draft.downloader.isEmpty ? "默认" : draft.downloader)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-subscribe-editor-downloader")

      CinematicFormDivider()

      // 保存路径（单行无边框选择 + 手动输入支持）
      HStack(spacing: 8) {
        Menu {
          Button {
            draft.savePath = ""
          } label: {
            if draft.savePath.isEmpty {
              Label("跟随系统下载目录", systemImage: "checkmark")
            } else {
              Text("跟随系统下载目录")
            }
          }
          if !uniqueSavePathSuggestions.isEmpty {
            Divider()
            ForEach(uniqueSavePathSuggestions, id: \.path) { option in
              Button {
                draft.savePath = option.path
              } label: {
                if draft.savePath == option.path {
                  Label(option.displayTitle, systemImage: "checkmark")
                } else {
                  Text(option.displayTitle)
                }
              }
            }
          }
          Divider()
          Button {
            openCustomPrompt(.savePath, initial: draft.savePath)
          } label: {
            Label("手动输入路径…", systemImage: "pencil")
          }
        } label: {
          HStack(spacing: 10) {
            Text("保存路径").font(.body).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(draft.savePath.isEmpty ? "跟随系统目录" : draft.savePath)
              .font(!draft.savePath.isEmpty ? .caption.monospaced() : .subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary.opacity(0.65))
          }
          .padding(.vertical, 13)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-subscribe-editor-save-path")

        if !draft.savePath.isEmpty {
          clearValueButton { draft.savePath = "" }
        }
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 52)
    }
  }

  // MARK: - 4. 进阶过滤与识别规则（对齐 Web `advance` 页全字段）

  private var advancedRulesSection: some View {
    groupedSection("进阶过滤与识别规则") {
      inputRow("包含规则", text: $draft.include, placeholder: "关键词或正则，如 中字|简繁", id: "include")
      CinematicFormDivider()
      inputRow("排除规则", text: $draft.exclude, placeholder: "关键词或正则，如 枪版|CAM", id: "exclude")
      CinematicFormDivider()
      NavigationLink {
        NativeSubRuleGroupSelectorView(options: ruleGroups, selection: $draft.filterGroups)
      } label: {
        disclosureRow(
          "优先级规则组",
          value: draft.filterGroups.isEmpty ? "跟随系统设置" : "已选 \(draft.filterGroups.count) 组"
        )
      }
      .buttonStyle(.plain)

      if !isDefaultMode && isTvSubscribe {
        CinematicFormDivider()
        episodeGroupRow
        CinematicFormDivider()
        seasonSelectorRow
      }

      if !isDefaultMode {
        CinematicFormDivider()
        mediaCategoryRow
      }

      if !isDefaultMode && !isMusicSubscribe {
        CinematicFormDivider()
        customWordsRow
      }
    }
  }

  private var episodeGroupRow: some View {
    HStack(spacing: 8) {
      Menu {
        Button {
          draft.episodeGroup = ""
        } label: {
          if draft.episodeGroup.isEmpty {
            Label("不指定（默认季集）", systemImage: "checkmark")
          } else {
            Text("不指定（默认季集）")
          }
        }
        if !episodeGroups.isEmpty {
          Divider()
          ForEach(episodeGroups) { group in
            Button {
              draft.episodeGroup = group.id
            } label: {
              let labelText = "\(group.name)（\(group.groupCount) 季 · \(group.episodeCount) 集）"
              if draft.episodeGroup == group.id {
                Label(labelText, systemImage: "checkmark")
              } else {
                Text(labelText)
              }
            }
          }
        }
        Divider()
        Button {
          openCustomPrompt(.episodeGroup, initial: draft.episodeGroup)
        } label: {
          Label("手动填写剧集组 ID…", systemImage: "pencil")
        }
      } label: {
        let matchedName = episodeGroups.first(where: { $0.id == draft.episodeGroup })?.name
        HStack(spacing: 10) {
          Text("指定剧集组").font(.body).foregroundStyle(.primary)
          Spacer(minLength: 8)
          Text(draft.episodeGroup.isEmpty ? "不指定" : (matchedName ?? draft.episodeGroup))
            .font(matchedName == nil && !draft.episodeGroup.isEmpty ? .caption.monospaced() : .subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary.opacity(0.65))
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-subscribe-editor-episode-group")

      if !draft.episodeGroup.isEmpty {
        clearValueButton { draft.episodeGroup = "" }
      }
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 52)
  }

  private var seasonSelectorRow: some View {
    Menu {
      Button {
        draft.season = nil
      } label: {
        if draft.season == nil {
          Label("默认（不覆盖）", systemImage: "checkmark")
        } else {
          Text("默认（不覆盖）")
        }
      }
      Divider()
      Button {
        draft.season = 0
      } label: {
        if draft.season == 0 {
          Label("第 0 季（特别篇 / Specials）", systemImage: "checkmark")
        } else {
          Text("第 0 季（特别篇 / Specials）")
        }
      }
      ForEach(1...30, id: \.self) { s in
        Button {
          draft.season = s
        } label: {
          if draft.season == s {
            Label("第 \(s) 季", systemImage: "checkmark")
          } else {
            Text("第 \(s) 季")
          }
        }
      }
      Divider()
      Button {
        openCustomPrompt(.season, initial: draft.season.map(String.init) ?? "")
      } label: {
        Label("手动输入季号（0–100）…", systemImage: "number")
      }
    } label: {
      menuRowLabel(
        "指定季",
        value: draft.season.map { $0 == 0 ? "第 0 季（特别篇）" : "第 \($0) 季" } ?? "默认"
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-subscribe-editor-season")
  }

  private var mediaCategoryRow: some View {
    HStack(spacing: 8) {
      if !categorySuggestions.isEmpty {
        Menu {
          Button {
            draft.mediaCategory = ""
          } label: {
            if draft.mediaCategory.isEmpty {
              Label("自动识别", systemImage: "checkmark")
            } else {
              Text("自动识别")
            }
          }
          Divider()
          ForEach(categorySuggestions, id: \.self) { cat in
            Button {
              draft.mediaCategory = cat
            } label: {
              if draft.mediaCategory == cat {
                Label(cat, systemImage: "checkmark")
              } else {
                Text(cat)
              }
            }
          }
          Divider()
          Button {
            openCustomPrompt(.mediaCategory, initial: draft.mediaCategory)
          } label: {
            Label("手动输入类别…", systemImage: "pencil")
          }
        } label: {
          HStack(spacing: 10) {
            Text("自定义类别").font(.body).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(draft.mediaCategory.isEmpty ? "自动识别" : draft.mediaCategory)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary.opacity(0.65))
          }
          .padding(.vertical, 13)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-subscribe-editor-media-category")

        if !draft.mediaCategory.isEmpty {
          clearValueButton { draft.mediaCategory = "" }
        }
      } else {
        Text("自定义类别").font(.body).foregroundStyle(.primary)
        Spacer(minLength: 8)
        TextField("留空自动识别", text: $draft.mediaCategory)
          .textFieldStyle(.plain)
          .font(.subheadline)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.trailing)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .frame(maxWidth: 210)
          .accessibilityIdentifier("native-subscribe-editor-media-category")
        if !draft.mediaCategory.isEmpty {
          clearValueButton { draft.mediaCategory = "" }
        }
      }
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 52)
  }

  private var customWordsRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("自定义识别词")
          .font(.body)
          .foregroundStyle(.primary)
        Spacer()
        if !draft.customWords.isEmpty {
          clearValueButton { draft.customWords = "" }
        }
      }
      TextField(
        "每行一条：屏蔽词、被替换词 => 替换词，或单独一行 @global 引入全局词",
        text: $draft.customWords,
        axis: .vertical
      )
      .textFieldStyle(.plain)
      .lineLimit(2...6)
      .font(.subheadline.monospaced())
      .foregroundStyle(.primary)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .accessibilityIdentifier("native-subscribe-editor-custom-words")
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
  }

  private var deleteSection: some View {
    CinematicPanel(padding: 0) {
      Button(role: .destructive) {
        showsDeleteConfirm = true
      } label: {
        HStack(spacing: 6) {
          if isDeleting { ProgressView().controlSize(.small).tint(NativeTheme.danger) }
          Text("取消此订阅")
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

  // MARK: - 通用高对比分组表单控件

  private func groupedSection<Content: View>(
    _ header: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(header)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) { content() }
      }
    }
  }

    /// 生成显示字段标题与当前值的统一菜单标签。
  private func menuRowLabel(_ title: String, value: String, monospaced: Bool = false) -> some View {
    HStack(spacing: 10) {
      Text(title)
        .font(.body)
        .foregroundStyle(.primary)
      Spacer(minLength: 8)
      Text(value)
        .font(monospaced ? .caption.monospaced() : .subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
      Image(systemName: "chevron.up.chevron.down")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary.opacity(0.65))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
    .frame(minHeight: 52)
    .contentShape(Rectangle())
  }

    /// 生成清除当前可选订阅值的快捷按钮。
  private func clearValueButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: "xmark.circle.fill")
        .font(.subheadline)
        .foregroundStyle(Color.secondary.opacity(0.8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("清空")
  }

  private func disclosureRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title).font(.body).foregroundStyle(.primary)
      Spacer()
      Text(value)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary.opacity(0.55))
    }
    .padding(.horizontal, 16).padding(.vertical, 13)
    .frame(minHeight: 52)
    .contentShape(Rectangle())
  }

  private func toggleRow(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
    Toggle(title, isOn: isOn)
      .font(.body)
      .foregroundStyle(.primary)
      .tint(appearance.accentColor)
      .padding(.horizontal, 16).padding(.vertical, 12)
      .frame(minHeight: 52)
      .accessibilityIdentifier("native-subscribe-editor-\(id)")
  }

    /// 构建同时支持预设选项和自定义值的菜单行。
  private func presetOrCustomMenuRow(
    _ label: String,
    selection: Binding<String>,
    options: [(value: String, title: String)],
    customTarget: CustomInputTarget,
    id: String
  ) -> some View {
    let matchedTitle = options.first(where: { $0.value == selection.wrappedValue })?.title
    let displayTitle = matchedTitle ?? "自定义 (\(selection.wrappedValue))"
    return Menu {
      ForEach(options, id: \.value) { item in
        Button {
          selection.wrappedValue = item.value
        } label: {
          if selection.wrappedValue == item.value {
            Label(item.title, systemImage: "checkmark")
          } else {
            Text(item.title)
          }
        }
      }
      Divider()
      Button {
        openCustomPrompt(customTarget, initial: selection.wrappedValue)
      } label: {
        Label("自定义正则…", systemImage: "pencil")
      }
    } label: {
      menuRowLabel(label, value: displayTitle)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-subscribe-editor-\(id)")
  }

    /// 构建仅从预设列表中选择值的菜单行。
  private func presetMenuRow(
    _ label: String,
    selection: Binding<String>,
    options: [(value: String, title: String)],
    id: String
  ) -> some View {
    let matchedTitle = options.first(where: { $0.value == selection.wrappedValue })?.title
    let displayTitle = matchedTitle ?? (selection.wrappedValue.isEmpty ? "全部" : selection.wrappedValue)
    return Menu {
      ForEach(options, id: \.value) { item in
        Button {
          selection.wrappedValue = item.value
        } label: {
          if selection.wrappedValue == item.value {
            Label(item.title, systemImage: "checkmark")
          } else {
            Text(item.title)
          }
        }
      }
    } label: {
      menuRowLabel(label, value: displayTitle)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-subscribe-editor-\(id)")
  }

    /// 构建带整数选项及自定义入口的参数菜单。
  private func intMenuRow(
    _ label: String,
    selection: Binding<Int>,
    options: [(value: Int, title: String)]
  ) -> some View {
    let displayTitle = options.first(where: { $0.value == selection.wrappedValue })?.title ?? "\(selection.wrappedValue)"
    return Menu {
      ForEach(options, id: \.value) { item in
        Button {
          selection.wrappedValue = item.value
        } label: {
          if selection.wrappedValue == item.value {
            Label(item.title, systemImage: "checkmark")
          } else {
            Text(item.title)
          }
        }
      }
    } label: {
      menuRowLabel(label, value: displayTitle)
    }
    .buttonStyle(.plain)
  }

    /// 构建剧集序号输入行并统一过滤非数字字符。
  private func episodeNumberRow(
    label: String,
    value: Binding<Int>,
    emptyPlaceholder: String,
    unitSuffix: String,
    id: String
  ) -> some View {
    HStack(spacing: 8) {
      Text(label).font(.body).foregroundStyle(.primary)
      Spacer(minLength: 8)
      TextField(
        emptyPlaceholder,
        text: Binding(
          get: { value.wrappedValue > 0 ? String(value.wrappedValue) : "" },
          set: { raw in
            let digits = raw.filter(\.isNumber)
            value.wrappedValue = min(max(Int(digits) ?? 0, 0), 9999)
          }
        )
      )
      .textFieldStyle(.plain)
      .keyboardType(.numberPad)
      .font(.subheadline.monospacedDigit())
      .foregroundStyle(.primary)
      .multilineTextAlignment(.trailing)
      .frame(maxWidth: 110)
      .accessibilityIdentifier("native-subscribe-editor-\(id)")

      if value.wrappedValue > 0 {
        Text(unitSuffix)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Stepper(
        "",
        value: Binding(
          get: { value.wrappedValue },
          set: { value.wrappedValue = min(max($0, 0), 9999) }
        ),
        in: 0...9999
      )
      .labelsHidden()
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
    .frame(minHeight: 52)
  }

  private func inputRow(
    _ label: String, text: Binding<String>, placeholder: String, id: String
  ) -> some View {
    HStack(spacing: 8) {
      Text(label).font(.body).foregroundStyle(.primary)
      Spacer(minLength: 8)
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .frame(maxWidth: 220)
        .accessibilityIdentifier("native-subscribe-editor-\(id)")
      if !text.wrappedValue.isEmpty {
        clearValueButton { text.wrappedValue = "" }
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .frame(minHeight: 52)
  }

  private var uniqueSavePathSuggestions: [(path: String, displayTitle: String)] {
    var seen = Set<String>()
    var out: [(String, String)] = []
    for item in pathOptions {
      guard let raw = item.downloadPath ?? item.savePath else { continue }
      let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !path.isEmpty, seen.insert(path).inserted else { continue }
      if let alias = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty {
        out.append((path, "\(alias) · \(path)"))
      } else {
        out.append((path, path))
      }
    }
    return out
  }

    /// 打开指定字段的自定义值编辑弹窗。
  private func openCustomPrompt(_ target: CustomInputTarget, initial: String) {
    customInputBuffer = initial
    activeCustomPrompt = target
  }

    /// 校验并把弹窗输入写回对应的订阅草稿字段。
  private func applyCustomPrompt(_ target: CustomInputTarget, value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch target {
    case .quality:
      draft.quality = trimmed
    case .resolution:
      draft.resolution = trimmed
    case .effect:
      draft.effect = trimmed
    case .savePath:
      draft.savePath = trimmed
    case .episodeGroup:
      draft.episodeGroup = trimmed
    case .season:
      if trimmed.isEmpty {
        draft.season = nil
      } else if let num = Int(trimmed), (0...100).contains(num) {
        draft.season = num
      }
    case .mediaCategory:
      draft.mediaCategory = trimmed
    }
  }

  // MARK: - 网络加载与保存

    /// 根据媒体类型选择后端默认订阅配置键。
  private static func defaultConfigSettingKey(for mediaType: String) -> String {
    switch mediaType {
    case "电影": return "DefaultMovieSubscribeConfig"
    case "电视剧": return "DefaultTvSubscribeConfig"
    default: return "DefaultMusicSubscribeConfig"
    }
  }

  private func load() async {
    isLoading = true
    loadFailed = false
    errorMessage = nil
    defer { isLoading = false }
    do {
      async let clientsTask: [NativeSubscribeClientSummary]? = {
        guard let ep = try? APIEndpoint(path: ["download", "clients"]) else { return nil }
        return try? await session.request(ep, as: [NativeSubscribeClientSummary].self).value
      }()
      async let sitesTask: [NativeSubSiteOption]? = {
        if let rssEp = try? APIEndpoint(path: ["site", "rss"]),
          let rssList = try? await session.request(rssEp, as: [NativeSubSiteOption].self).value
        {
          return rssList
        }
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
      async let pathsTask: [NativeSubPathBrief]? = {
        guard let ep = try? APIEndpoint(path: ["download", "paths"]) else { return nil }
        return try? await session.request(ep, as: [NativeSubPathBrief].self).value
      }()
      async let categoriesTask: [String: [String]]? = loadMediaCategoryMap()

      let snapshot: NativeSubscribeDetailDraft
      switch mode {
      case .subscribe(let subID, _):
        let detailEndpoint = try APIEndpoint(path: ["subscribe", String(subID)])
        let detail = try await session.request(
          detailEndpoint, as: NativeSubscribeDetailRaw.self, requiring: .init(category: .subscribe)
        ).value
        snapshot = NativeSubscribeDetailDraft(raw: detail).normalizedFilterOptions()
      case .defaultRule(let mediaType):
        let key = Self.defaultConfigSettingKey(for: mediaType)
        let ep = try APIEndpoint(path: ["system", "setting", "public", key], responseContract: .payload)
        let rawData = try await session.requestPayload(ep).value
        snapshot = NativeSubscribeDetailDraft.fromDefaultSettingPayload(
          rawData, fallbackMediaType: mediaType
        ).normalizedFilterOptions()
      }

      let (clients, loadedSites, loadedGroups, loadedPaths, catMap) = await (
        clientsTask, sitesTask, groupsTask, pathsTask, categoriesTask
      )
      try Task.checkCancellation()

      loaded = snapshot
      draft = snapshot
      downloaders = (clients ?? []).compactMap(\.name).filter { !$0.isEmpty }
      sites = (loadedSites ?? []).filter(\.isActive)
      ruleGroups = loadedGroups ?? []
      pathOptions = loadedPaths ?? []
      categorySuggestions = catMap?[snapshot.mediaType] ?? []

      // 电视剧 + TMDB 来源时自动拉取剧集组（对齐 Web `getEpisodeGroups`）
      if !isDefaultMode,
        snapshot.mediaSource == "themoviedb",
        !snapshot.mediaID.isEmpty,
        (snapshot.mediaType == "电视剧" || snapshot.mediaType.lowercased() == "tv")
      {
        if let ep = try? APIEndpoint(path: ["media", "groups", snapshot.mediaID]),
          let groups = try? await session.request(ep, as: [NativeSubEpisodeGroupOption].self).value
        {
          episodeGroups = groups
        }
      }
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

    /// 读取影视类别与服务端分类名称的映射表。
  private func loadMediaCategoryMap() async -> [String: [String]]? {
    guard let ep = try? APIEndpoint(path: ["media", "category"], responseContract: .payload),
      let data = try? await session.requestPayload(ep).value,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let container = (root["data"] as? [String: Any]) ?? root
    var result: [String: [String]] = [:]
    for (typeKey, rawVal) in container {
      if let arr = rawVal as? [String] {
        result[typeKey] = arr.filter { !$0.isEmpty }
      } else if let dict = rawVal as? [String: Any] {
        result[typeKey] = dict.keys.filter { !$0.isEmpty }.sorted()
      }
    }
    return result
  }

  private func save() async {
    guard let baseline = loaded, hasChanges, isSearchIntervalValid else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      switch mode {
      case .subscribe(let subID, _):
        let payload = draft.writePayload(id: subID, relativeTo: baseline)
        let body = try JSONSerialization.data(withJSONObject: payload)
        let endpoint = try APIEndpoint(
          path: ["subscribe"], method: .put, body: body, trailingSlash: true)
        try await session.perform(endpoint, requiring: .init(category: .subscribe))
      case .defaultRule(let mediaType):
        let key = Self.defaultConfigSettingKey(for: mediaType)
        let payload = draft.defaultRuleWritePayload(mediaType: mediaType)
        let body = try JSONSerialization.data(withJSONObject: payload)
        let endpoint = try APIEndpoint(
          path: ["system", "setting", key],
          method: .post,
          body: body,
          responseContract: .payload
        )
        _ = try await session.requestPayload(endpoint)
      }
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
    guard let subID = subscribeID else { return }
    isDeleting = true
    defer { isDeleting = false }
    do {
      let ep = try APIEndpoint(path: ["subscribe", String(subID)], method: .delete)
      try await session.perform(ep, requiring: .init(category: .subscribe))
      onSaved()
      dismiss()
    } catch {
      errorMessage = "取消订阅失败，请稍后重试。"
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
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(selection.isEmpty ? "全选" : "清空") {
          if selection.isEmpty { selection = Set(sites.map(\.id)) } else { selection.removeAll() }
        }
        .tint(.primary)
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
    .nativeTopNavigationBar()
  }
}

// MARK: - 解码与草稿模型

private struct NativeSubscribeClientSummary: Decodable, Sendable { let name: String? }

private struct NativeSubSiteOption: Decodable, Sendable, Identifiable {
  let id: Int
  let name: String
  let isActive: Bool
    /// 映射剧集分组接口字段及其兼容命名。
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
  let name: String?
  let savePath: String?
  let downloadPath: String?
    /// 映射剧集分组接口字段及其兼容命名。
  private enum CodingKeys: String, CodingKey {
    case name
    case savePath = "save_path"
    case downloadPath = "download_path"
  }
}

/// 表示可供订阅规则选择的剧集分组。
private struct NativeSubEpisodeGroupOption: Decodable, Sendable, Identifiable {
  let id: String
  let name: String
  let groupCount: Int
  let episodeCount: Int

    /// 映射剧集分组接口字段及其兼容命名。
  private enum CodingKeys: String, CodingKey {
    case id, name
    case groupCount = "group_count"
    case episodeCount = "episode_count"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let strID = try? c.decode(String.self, forKey: .id) {
      id = strID
    } else if let intID = try? c.decode(Int.self, forKey: .id) {
      id = String(intID)
    } else {
      id = UUID().uuidString
    }
    name = (try? c.decode(String.self, forKey: .name)) ?? id
    groupCount = (try? c.decode(Int.self, forKey: .groupCount)) ?? 0
    episodeCount = (try? c.decode(Int.self, forKey: .episodeCount)) ?? 0
  }
}

private struct NativeSubscribeDetailRaw: Decodable, Sendable {
  let type: String?
  let mediaSource: String?
  let mediaID: String?
  let quality: String?
  let resolution: String?
  let effect: String?
  let bestVersion: Int?
  let bestVersionFull: Bool?
  let searchImdbID: Int?
  let searchInterval: Int?
  let showEditDialog: Bool?
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

    /// 映射剧集分组接口字段及其兼容命名。
  private enum CodingKeys: String, CodingKey {
    case type, quality, resolution, effect, sites, keyword, include, exclude, season, downloader
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case bestVersion = "best_version"
    case bestVersionFull = "best_version_full"
    case searchImdbID = "search_imdbid"
    case searchInterval = "search_interval"
    case showEditDialog = "show_edit_dialog"
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
    mediaSource = try? c.decode(String.self, forKey: .mediaSource)
    if let strMid = try? c.decode(String.self, forKey: .mediaID) {
      mediaID = strMid
    } else if let intMid = try? c.decode(Int.self, forKey: .mediaID) {
      mediaID = String(intMid)
    } else {
      mediaID = nil
    }
    quality = try? c.decode(String.self, forKey: .quality)
    resolution = try? c.decode(String.self, forKey: .resolution)
    effect = try? c.decode(String.self, forKey: .effect)
    bestVersion =
      (try? c.decode(Int.self, forKey: .bestVersion))
      ?? ((try? c.decode(Bool.self, forKey: .bestVersion)) == true ? 1 : 0)
    if let intFull = try? c.decode(Int.self, forKey: .bestVersionFull) {
      bestVersionFull = intFull == 1
    } else {
      bestVersionFull = (try? c.decode(Bool.self, forKey: .bestVersionFull)) ?? false
    }
    searchImdbID =
      (try? c.decode(Int.self, forKey: .searchImdbID))
      ?? ((try? c.decode(Bool.self, forKey: .searchImdbID)) == true ? 1 : 0)
    searchInterval = try? c.decode(Int.self, forKey: .searchInterval)
    if let boolDialog = try? c.decode(Bool.self, forKey: .showEditDialog) {
      showEditDialog = boolDialog
    } else if let intDialog = try? c.decode(Int.self, forKey: .showEditDialog) {
      showEditDialog = intDialog == 1
    } else {
      showEditDialog = nil
    }
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
  var mediaSource = ""
  var mediaID = ""
  var quality = ""
  var resolution = ""
  var effect = ""
  var bestVersion = false
  var bestVersionFull = false
  var searchImdbID = false
  var showEditDialog = false
  var searchInterval: Int? = nil
  var sites: Set<Int> = []
  var filterGroups: Set<String> = []
  var keyword = ""
  var include = ""
  var exclude = ""
  var customWords = ""
  var mediaCategory = ""
  var episodeGroup = ""
  var season: Int? = nil
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
    mediaSource = raw.mediaSource ?? ""
    mediaID = raw.mediaID ?? ""
    quality = raw.quality ?? ""
    resolution = raw.resolution ?? ""
    effect = raw.effect ?? ""
    bestVersion = (raw.bestVersion ?? 0) == 1
    bestVersionFull = bestVersion && (raw.bestVersionFull ?? false)
    searchImdbID = (raw.searchImdbID ?? 0) == 1
    showEditDialog = raw.showEditDialog ?? false
    if let interval = raw.searchInterval, interval > 0 {
      searchInterval = interval
    } else {
      searchInterval = nil
    }
    sites = Set(raw.sites ?? [])
    filterGroups = Set(raw.filterGroups ?? [])
    keyword = raw.keyword ?? ""
    include = raw.include ?? ""
    exclude = raw.exclude ?? ""
    customWords = raw.customWords ?? ""
    mediaCategory = raw.mediaCategory ?? ""
    episodeGroup = raw.episodeGroup ?? ""
    season = raw.season
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

    /// 从默认设置负载构造编辑草稿，并使用媒体类型补全缺省值。
  static func fromDefaultSettingPayload(_ data: Data, fallbackMediaType: String) -> Self {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      var empty = Self()
      empty.mediaType = fallbackMediaType
      return empty
    }
    let outer = (json["data"] as? [String: Any]) ?? json
    let valueDict = (outer["value"] as? [String: Any]) ?? [:]
    if let valueData = try? JSONSerialization.data(withJSONObject: valueDict),
      let decoded = try? JSONDecoder().decode(NativeSubscribeDetailRaw.self, from: valueData)
    {
      var built = Self(raw: decoded)
      built.mediaType = fallbackMediaType
      return built
    }
    var empty = Self()
    empty.mediaType = fallbackMediaType
    return empty
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
    let effectiveFull = bestVersion && bestVersionFull
    let baselineFull = baseline.bestVersion && baseline.bestVersionFull
    if effectiveFull != baselineFull {
      payload["best_version_full"] = effectiveFull ? 1 : 0
    }
    if searchImdbID != baseline.searchImdbID { payload["search_imdbid"] = searchImdbID ? 1 : 0 }
    if searchInterval != baseline.searchInterval {
      if let hours = searchInterval, hours > 0 {
        payload["search_interval"] = hours
      } else {
        payload["search_interval"] = NSNull()
      }
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

    let lowerType = mediaType.lowercased()
    if lowerType == "电视剧" || lowerType == "tv" || lowerType == "series" {
      if season != baseline.season {
        payload["season"] = season ?? NSNull()
      }
      if totalEpisode != baseline.totalEpisode { payload["total_episode"] = totalEpisode }
      if startEpisode != baseline.startEpisode { payload["start_episode"] = startEpisode }
    }
    if lowerType == "音乐" || lowerType == "music" {
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

    /// 生成写回指定媒体类型默认订阅规则的请求负载。
  func defaultRuleWritePayload(mediaType: String) -> [String: Any] {
    var payload: [String: Any] = [
      "type": mediaType,
      "sites": Array(sites).sorted(),
      "filter_groups": Array(filterGroups).sorted(),
      "best_version": bestVersion,
      "best_version_full": bestVersion && bestVersionFull,
      "search_imdbid": searchImdbID,
      "show_edit_dialog": showEditDialog,
      "downloader": downloader.trimmingCharacters(in: .whitespacesAndNewlines),
      "save_path": savePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? NSNull() : savePath.trimmingCharacters(in: .whitespacesAndNewlines),
      "search_interval": (searchInterval ?? 0) > 0 ? searchInterval! : NSNull(),
      "include": include.trimmingCharacters(in: .whitespacesAndNewlines),
      "exclude": exclude.trimmingCharacters(in: .whitespacesAndNewlines),
    ]
    if mediaType == "音乐" {
      payload["audio_quality"] = audioQuality.isEmpty ? NSNull() : audioQuality
      payload["audio_format"] = audioFormat.isEmpty ? NSNull() : audioFormat
      payload["min_bitrate"] = minBitrate > 0 ? minBitrate : NSNull()
      payload["min_bit_depth"] = minBitDepth > 0 ? minBitDepth : NSNull()
      payload["min_sample_rate"] = minSampleRate > 0 ? minSampleRate : NSNull()
    } else {
      payload["quality"] = quality
      payload["resolution"] = resolution
      payload["effect"] = effect
    }
    return payload
  }

  /// 将历史遗留或跨端写入的短标签规范化为与 Web 一致的等价正则，自定义正则原样保留。
  func normalizedFilterOptions() -> Self {
    var copy = self
    copy.quality = Self.normalizeFilterOption(field: "quality", raw: quality)
    copy.resolution = Self.normalizeFilterOption(field: "resolution", raw: resolution)
    copy.effect = Self.normalizeFilterOption(field: "effect", raw: effect)
    return copy
  }

  /// 将单字段界面短标签转换为等价正则表达式。
  static func normalizeFilterOption(field: String, raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }
    let lower = trimmed.lowercased()
    if lower == "全部" || lower == "all" { return "" }
    switch field {
    case "quality":
      switch lower {
      case "蓝光原盘", "藍光原盤", "blu-ray original", "bluray original":
        return "Blu-?Ray.+VC-?1|Blu-?Ray.+AVC|UHD.+blu-?ray.+HEVC|MiniBD"
      case "remux": return "Remux"
      case "bluray", "blu-ray": return "Blu-?Ray"
      case "uhd": return "UHD|UltraHD"
      case "web-dl", "webdl": return "WEB-?DL|WEB-?RIP"
      case "hdtv": return "HDTV"
      case "h265", "h.265", "hevc": return "[Hx].?265|HEVC"
      case "h264", "h.264", "avc": return "[Hx].?264|AVC"
      default: return raw
      }
    case "resolution":
      switch lower {
      case "4k": return "4K|2160p|x2160"
      case "1080p": return "1080[pi]|x1080"
      case "720p": return "720[pi]|x720"
      default: return raw
      }
    case "effect":
      switch lower {
      case "杜比视界", "杜比視界", "dolby vision", "dovi", "dv":
        return "Dolby[\\s.]+Vision|DOVI|[\\s.]+DV[\\s.]+"
      case "杜比全景声", "杜比全景聲", "dolby atmos", "atmos":
        return "Dolby[\\s.]*\\+?Atmos|Atmos"
      case "hdr": return "[\\s.]+HDR[\\s.]+|HDR10|HDR10\\+"
      case "sdr": return "[\\s.]+SDR[\\s.]+"
      default: return raw
      }
    default:
      return raw
    }
  }
}
