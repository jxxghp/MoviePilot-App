import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生高级系统设置页：对应原 Web 核心与高级系统参数（网络代理、元数据域名、性能缓存与更新日志），支持单次增量保存至 `POST /api/v1/system/env`。
@MainActor
struct NativeSystemSettingsPage: View {
  let session: NativeSession

  @State private var loaded = NativeSystemEnvSnapshot()
  @State private var draft = NativeSystemEnvSnapshot()
  @State private var isLoading = true
  @State private var loadFailed = false
  @State private var isSaving = false
  @State private var attempt = 0
  @State private var feedback: NativeSettingsFeedback?

  /// 连续渐变背景、弱化层次分组玻璃卡（网络与代理、媒体与元数据、性能订阅、更新与日志）与原生保存按钮。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && !loaded.isLoaded {
            systemSettingsSkeleton
              .transition(.opacity)
          } else if loadFailed && !loaded.isLoaded {
            failureCard
          } else {
            networkSection
            recognitionSection
            performanceAndSubscribeSection
            runtimeSection
          }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-settings-scroll")
    }
    .navigationTitle("高级系统设置")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await save() }
        } label: {
          if isSaving {
            ProgressView().tint(.primary)
          } else {
            Text("保存").fontWeight(.semibold)
          }
        }
        .tint(.primary)
        .disabled(!hasChanges || isSaving || !loaded.isLoaded)
        .accessibilityIdentifier("native-settings-save")
      }
    }
    .task(id: attempt) { await load(forceRefresh: attempt > 0) }
  }

  /// 当前草稿相对已载入快照是否存在变更。
  private var hasChanges: Bool { draft != loaded }

  /// 高级系统设置加载期间与 4 大分组垂直输入框节奏 1:1 对齐的占位骨架。
  private var systemSettingsSkeleton: some View {
    let sections: [(title: String, fieldRows: Int, toggleRows: Int)] = [
      ("网络与代理", 4, 1),
      ("媒体与元数据", 3, 1),
      ("性能与订阅", 2, 2),
      ("更新与日志", 2, 2),
    ]
    return VStack(alignment: .leading, spacing: 20) {
      ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
        VStack(alignment: .leading, spacing: 8) {
          mutedSectionHeader(section.title)
          CinematicPanel {
            VStack(spacing: 14) {
              ForEach(0..<section.fieldRows, id: \.self) { idx in
                if idx > 0 { rowDivider }
                VStack(alignment: .leading, spacing: 6) {
                  NativeSkeletonBlock(width: 96, height: 13, cornerRadius: 4)
                  NativeSkeletonBlock(height: 36, cornerRadius: 10)
                }
              }
              ForEach(0..<section.toggleRows, id: \.self) { _ in
                rowDivider
                HStack {
                  NativeSkeletonBlock(width: 136, height: 15, cornerRadius: 5)
                  Spacer()
                  NativeSkeletonBlock(width: 48, height: 28, cornerRadius: 14)
                }
              }
            }
          }
        }
      }
    }
    .nativeSkeletonShimmer()
  }

  /// 弱化后的统一设置分区标题。
  private func mutedSectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.footnote.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
      .accessibilityAddTraits(.isHeader)
  }

  /// 弱化行内分隔线。
  private var rowDivider: some View {
    Divider().overlay(.primary.opacity(0.08))
  }

  /// 统一文本输入配置行（无内嵌边框，与设置页分组列表 1:1 对齐）。
  private func textSettingRow(
    title: String,
    placeholder: String,
    text: Binding<String>,
    isURL: Bool = true,
    id: String
  ) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.body)
        .foregroundStyle(.primary)
        .layoutPriority(1)
      Spacer(minLength: 8)
      TextField(
        placeholder,
        text: text,
        prompt: Text(placeholder).foregroundColor(.secondary.opacity(0.7))
      )
      .textFieldStyle(.plain)
      .font(.subheadline)
      .foregroundStyle(.primary)
      .multilineTextAlignment(.trailing)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .keyboardType(isURL ? .URL : .default)
      .accessibilityIdentifier(id)
    }
    .frame(minHeight: 30)
  }

  /// 统一下拉菜单配置行（无边框，带 `.buttonStyle(.plain)` 保持高清晰文字对比度）。
  private func menuSettingRow(
    title: String,
    value: String,
    options: [(value: String, label: String)],
    selection: Binding<String>,
    id: String
  ) -> some View {
    Menu {
      ForEach(options, id: \.value) { item in
        Button {
          selection.wrappedValue = item.value
        } label: {
          if selection.wrappedValue == item.value {
            Label(item.label, systemImage: "checkmark")
          } else {
            Text(item.label)
          }
        }
      }
    } label: {
      HStack(spacing: 10) {
        Text(title)
          .font(.body)
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        Text(value)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary.opacity(0.65))
      }
      .frame(minHeight: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 统一切换开关行。
  private func toggleSettingRow(
    _ title: String,
    isOn: Binding<Bool>,
    id: String
  ) -> some View {
    Toggle(title, isOn: isOn)
      .font(.body)
      .foregroundStyle(.primary)
      .tint(NativeAppearanceStore.shared.accentColor)
      .accessibilityIdentifier(id)
  }

  /// 1. 网络与代理高级配置（对应原高级设置「网络」）。
  private var networkSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      mutedSectionHeader("网络与代理")
      CinematicPanel {
        VStack(spacing: 14) {
          textSettingRow(
            title: "网络代理服务器",
            placeholder: "http://127.0.0.1:7890",
            text: $draft.proxyHost,
            id: "native-settings-proxy-host"
          )
          rowDivider
          textSettingRow(
            title: "GitHub 加速代理",
            placeholder: "https://gh-proxy.com/",
            text: $draft.githubProxy,
            id: "native-settings-github-proxy"
          )
          rowDivider
          textSettingRow(
            title: "PIP 镜像源",
            placeholder: "https://pypi.tuna.tsinghua.edu.cn/simple",
            text: $draft.pipProxy,
            id: "native-settings-pip-proxy"
          )
          rowDivider
          textSettingRow(
            title: "外网访问域名",
            placeholder: "https://mp.example.com",
            text: $draft.appDomain,
            id: "native-settings-app-domain"
          )
          rowDivider
          toggleSettingRow("启用 DoH 域名解析", isOn: $draft.dohEnable, id: "native-settings-doh-enable")
          if draft.dohEnable {
            rowDivider
            textSettingRow(
              title: "DoH 解析服务器",
              placeholder: "1.0.0.1,1.1.1.1,9.9.9.9",
              text: $draft.dohResolvers,
              isURL: false,
              id: "native-settings-doh-resolvers"
            )
            rowDivider
            textSettingRow(
              title: "DoH 生效域名",
              placeholder: "api.themoviedb.org,api.github.com",
              text: $draft.dohDomains,
              isURL: false,
              id: "native-settings-doh-domains"
            )
          }
        }
      }
    }
  }

  /// 2. 媒体识别与元数据高级配置（对应原高级设置「媒体」）。
  private var recognitionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      mutedSectionHeader("媒体与元数据")
      CinematicPanel {
        VStack(spacing: 14) {
          menuSettingRow(
            title: "主识别来源",
            value: draft.recognizeSource == "douban" ? "豆瓣" : "TheMovieDB",
            options: [("themoviedb", "TheMovieDB"), ("douban", "豆瓣")],
            selection: $draft.recognizeSource,
            id: "native-settings-recognize-source"
          )
          rowDivider
          menuSettingRow(
            title: "搜索数据源",
            value: draft.searchSource == "douban" ? "豆瓣" : "TheMovieDB",
            options: [("themoviedb", "TheMovieDB"), ("douban", "豆瓣")],
            selection: $draft.searchSource,
            id: "native-settings-search-source"
          )
          rowDivider
          textSettingRow(
            title: "TheMovieDB API 域名",
            placeholder: "api.themoviedb.org",
            text: $draft.tmdbApiDomain,
            id: "native-settings-tmdb-api-domain"
          )
          rowDivider
          textSettingRow(
            title: "TheMovieDB 图片域名",
            placeholder: "image.tmdb.org",
            text: $draft.tmdbImageDomain,
            id: "native-settings-tmdb-image-domain"
          )
          rowDivider
          toggleSettingRow(
            "刮削跟随 TheMovieDB 语言",
            isOn: $draft.scrapFollowTmdb,
            id: "native-settings-scrap-follow-tmdb"
          )
          rowDivider
          toggleSettingRow(
            "优先使用识别插件",
            isOn: $draft.recognizePluginFirst,
            id: "native-settings-recognize-plugin-first"
          )
          rowDivider
          toggleSettingRow(
            "启用 Fanart 扩展图片",
            isOn: $draft.fanartEnable,
            id: "native-settings-fanart-enable"
          )
          rowDivider
          toggleSettingRow(
            "Bangumi 数据与图片代理",
            isOn: $draft.bangumiProxyEnable,
            id: "native-settings-bangumi-proxy"
          )
          rowDivider
          toggleSettingRow(
            "共享媒体识别缓存",
            isOn: $draft.mediaRecognizeShare,
            id: "native-settings-recognize-share"
          )
        }
      }
    }
  }

  /// 3. 性能、订阅与同步高级参数。
  private var performanceAndSubscribeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      mutedSectionHeader("性能、订阅与同步")
      CinematicPanel {
        VStack(spacing: 14) {
          menuSettingRow(
            title: "订阅模式",
            value: draft.subscribeMode == "rss" ? "RSS 订阅" : "站点爬虫",
            options: [("spider", "站点爬虫"), ("rss", "RSS 订阅")],
            selection: $draft.subscribeMode,
            id: "native-settings-subscribe-mode"
          )
          rowDivider
          Stepper(value: $draft.subscribeRssInterval, in: 5...720, step: 5) {
            HStack {
              Text("订阅刷新周期").font(.subheadline).foregroundStyle(.primary.opacity(0.84))
              Spacer()
              Text("\(draft.subscribeRssInterval) 分钟")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
          rowDivider
          Stepper(value: $draft.mediaServerSyncInterval, in: 1...48) {
            HStack {
              Text("媒体库同步周期").font(.subheadline).foregroundStyle(.primary.opacity(0.84))
              Spacer()
              Text("每 \(draft.mediaServerSyncInterval) 小时")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
          rowDivider
          HStack {
            Text("种子标签").font(.subheadline).foregroundStyle(.primary.opacity(0.84))
            Spacer()
            TextField(
              "MOVIEPILOT",
              text: $draft.torrentTag,
              prompt: Text("MOVIEPILOT").foregroundColor(.secondary)
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(maxWidth: 160)
            .accessibilityIdentifier("native-settings-torrent-tag")
          }
          rowDivider
          Stepper(value: $draft.transferThreads, in: 1...16) {
            HStack {
              Text("文件整理并发线程").font(.subheadline).foregroundStyle(.primary.opacity(0.84))
              Spacer()
              Text("\(draft.transferThreads) 线程")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
          rowDivider
          toggleSettingRow(
            "大内存模式",
            isOn: $draft.bigMemoryMode,
            id: "native-settings-big-memory"
          )
          rowDivider
          toggleSettingRow(
            "全局图片缓存",
            isOn: $draft.globalImageCache,
            id: "native-settings-image-cache"
          )
          rowDivider
          toggleSettingRow(
            "数据库 WAL 模式",
            isOn: $draft.dbWalEnable,
            id: "native-settings-db-wal"
          )
        }
      }
    }
  }

  /// 4. 更新、日志与服务端信息。
  private var runtimeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      mutedSectionHeader("更新与日志")
      CinematicPanel {
        VStack(spacing: 14) {
          toggleSettingRow(
            "自动检查站点资源更新",
            isOn: $draft.autoUpdateResource,
            id: "native-settings-auto-update-resource"
          )
          rowDivider
          toggleSettingRow(
            "自动检查主程序版本更新",
            isOn: $draft.moviePilotAutoUpdate,
            id: "native-settings-auto-update-app"
          )
          rowDivider
          toggleSettingRow("调试模式", isOn: $draft.debug, id: "native-settings-debug")
          rowDivider
          menuSettingRow(
            title: "日志级别",
            value: draft.logLevel,
            options: ["DEBUG", "INFO", "WARNING", "ERROR"].map { ($0, $0) },
            selection: $draft.logLevel,
            id: "native-settings-log-level"
          )
          if !draft.timezone.isEmpty {
            rowDivider
            HStack {
              Text("服务端时区").font(.subheadline).foregroundStyle(.primary.opacity(0.84))
              Spacer()
              Text(draft.timezone).font(.caption).foregroundStyle(.secondary)
            }
          }
          if !draft.appVersion.isEmpty {
            rowDivider
            HStack {
              Text("后端版本").font(.subheadline).foregroundStyle(.primary.opacity(0.84))
              Spacer()
              Text(draft.appVersion)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  /// 操作反馈提示条。
  private func feedbackBanner(_ feedback: NativeSettingsFeedback) -> some View {
    CinematicPanel(padding: 11) {
      HStack(spacing: 10) {
        Image(
          systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        )
        .foregroundStyle(feedback.isError ? .orange : NativeTheme.success)
        Text(feedback.message).font(.subheadline).foregroundStyle(.primary.opacity(0.92))
        Spacer(minLength: 0)
        Button {
          self.feedback = nil
        } label: {
          Image(systemName: "xmark").font(.caption.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.65)).frame(minWidth: 32, minHeight: 32)
        }
        .buttonStyle(.plain)
      }
    }
    .accessibilityIdentifier("native-settings-feedback")
  }

  /// 载入失败重试卡。
  private var failureCard: some View {
    CinematicPanel {
      VStack(alignment: .leading, spacing: 10) {
        Label("暂时无法读取系统设置", systemImage: "exclamationmark.triangle").font(.headline)
        Button("重试") { attempt += 1 }
          .frame(minHeight: 44)
          .accessibilityIdentifier("native-settings-retry")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 从 `GET /api/v1/system/env` 读取受控白名单字段；命中页面缓存时静默复用，下拉刷新强制重拉。
  private func load(forceRefresh: Bool = false) async {
    let cacheKey = "systemSettings|env"
    if !forceRefresh,
      let cached: NativeSystemEnvSnapshot = NativePageDataCache.shared.get(
        cacheKey, session: session)
    {
      loaded = cached
      draft = cached
      isLoading = false
      loadFailed = false
      return
    }
    if !loaded.isLoaded { isLoading = true }
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["system", "env"])
      let envelope = try await session.request(endpoint, as: NativeSystemEnvEnvelope.self).value
      try Task.checkCancellation()
      guard let raw = envelope.payload else {
        if !loaded.isLoaded { loadFailed = true }
        return
      }
      let snapshot = NativeSystemEnvSnapshot(raw: raw)
      loaded = snapshot
      draft = snapshot
      NativePageDataCache.shared.set(snapshot, for: cacheKey, session: session)
    } catch is CancellationError {
      return
    } catch {
      if !loaded.isLoaded { loadFailed = true }
    }
  }

  /// 仅将已修改的白名单字段单次提交到 `POST /api/v1/system/env`，不自动重试。
  private func save() async {
    guard hasChanges else { return }
    isSaving = true
    defer { isSaving = false }
    let delta = draft.changedPayload(relativeTo: loaded)
    guard !delta.isEmpty else { return }
    do {
      let body = try JSONSerialization.data(withJSONObject: delta)
      let endpoint = try APIEndpoint(path: ["system", "env"], method: .post, body: body)
      try await session.perform(endpoint)
      try Task.checkCancellation()
      loaded = draft
      NativePageDataCache.shared.set(draft, for: "systemSettings|env", session: session)
      NativeGlobalImageSettingsStore.shared.applySystemEnvUpdate(
        globalImageCache: draft.globalImageCache,
        tmdbImageDomain: draft.tmdbImageDomain,
        bangumiProxyEnable: draft.bangumiProxyEnable,
        for: session
      )
      feedback = NativeSettingsFeedback(isError: false, message: "系统设置已保存。")
    } catch is CancellationError {
      return
    } catch {
      feedback = NativeSettingsFeedback(isError: true, message: "保存系统设置失败，请稍后重试。")
    }
  }
}

/// 设置保存反馈载体。
private struct NativeSettingsFeedback {
  let isError: Bool
  let message: String
}

/// `GET /api/v1/system/env` 响应包装，兼容 `{success, data}` 包装与已解包对象格式。
private struct NativeSystemEnvEnvelope: Decodable, Sendable {
  let payload: NativeSystemEnvRaw?

  /// 优先解码标准 `data` 负载，兼容历史扁平对象格式。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.data) {
      payload = try container.decodeIfPresent(NativeSystemEnvRaw.self, forKey: .data)
    } else {
      payload = try NativeSystemEnvRaw(from: decoder)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case data
  }
}

/// 兼容后端环境配置可能以布尔或字符串返回的宽容解码辅助。
private struct NativeFlexibleBool: Decodable, Sendable {
  let value: Bool

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let flag = try? container.decode(Bool.self) {
      value = flag
    } else if let text = try? container.decode(String.self) {
      value = ["true", "1", "yes", "on", "release", "dev"].contains(
        text.trimmingCharacters(in: .whitespaces).lowercased())
    } else if let number = try? container.decode(Int.self) {
      value = number != 0
    } else {
      value = false
    }
  }
}

/// 兼容后端环境配置可能以整数、浮点或数字字符串返回的宽容解码辅助。
private struct NativeFlexibleInt: Decodable, Sendable {
  let value: Int

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int.self) {
      value = number
    } else if let double = try? container.decode(Double.self) {
      value = Int(double.rounded())
    } else if let text = try? container.decode(String.self),
      let parsed = Int(text.trimmingCharacters(in: .whitespaces))
    {
      value = parsed
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "无法解析整型设置项")
    }
  }
}

/// `GET /api/v1/system/env` 非敏感白名单解码结构体（覆盖网络代理、元数据、性能缓存与更新日志）。
private struct NativeSystemEnvRaw: Decodable, Sendable {
  // 网络与代理
  let proxyHost: String?
  let githubProxy: String?
  let pipProxy: String?
  let appDomain: String?
  let dohEnable: NativeFlexibleBool?
  let dohResolvers: String?
  let dohDomains: String?

  // 媒体与元数据
  let recognizeSource: String?
  let searchSource: String?
  let tmdbApiDomain: String?
  let tmdbImageDomain: String?
  let scrapFollowTmdb: NativeFlexibleBool?
  let recognizePluginFirst: NativeFlexibleBool?
  let fanartEnable: NativeFlexibleBool?
  let bangumiProxyEnable: NativeFlexibleBool?
  let mediaRecognizeShare: NativeFlexibleBool?

  // 性能、订阅与同步
  let subscribeMode: String?
  let subscribeRssInterval: NativeFlexibleInt?
  let torrentTag: String?
  let mediaServerSyncInterval: NativeFlexibleInt?
  let transferThreads: NativeFlexibleInt?
  let bigMemoryMode: NativeFlexibleBool?
  let globalImageCache: NativeFlexibleBool?
  let dbWalEnable: NativeFlexibleBool?

  // 更新与日志
  let autoUpdateResource: NativeFlexibleBool?
  let moviePilotAutoUpdate: NativeFlexibleBool?
  let debug: NativeFlexibleBool?
  let logLevel: String?
  let timezone: String?
  let appVersion: String?

  /// 仅解码允许在移动端展示的非敏感环境键。
  private enum CodingKeys: String, CodingKey {
    case proxyHost = "PROXY_HOST"
    case githubProxy = "GITHUB_PROXY"
    case pipProxy = "PIP_PROXY"
    case appDomain = "APP_DOMAIN"
    case dohEnable = "DOH_ENABLE"
    case dohResolvers = "DOH_RESOLVERS"
    case dohDomains = "DOH_DOMAINS"

    case recognizeSource = "RECOGNIZE_SOURCE"
    case searchSource = "SEARCH_SOURCE"
    case tmdbApiDomain = "TMDB_API_DOMAIN"
    case tmdbImageDomain = "TMDB_IMAGE_DOMAIN"
    case scrapFollowTmdb = "SCRAP_FOLLOW_TMDB"
    case recognizePluginFirst = "RECOGNIZE_PLUGIN_FIRST"
    case fanartEnable = "FANART_ENABLE"
    case bangumiProxyEnable = "BANGUMI_PROXY_ENABLE"
    case mediaRecognizeShare = "MEDIA_RECOGNIZE_SHARE"

    case subscribeMode = "SUBSCRIBE_MODE"
    case subscribeRssInterval = "SUBSCRIBE_RSS_INTERVAL"
    case torrentTag = "TORRENT_TAG"
    case mediaServerSyncInterval = "MEDIASERVER_SYNC_INTERVAL"
    case transferThreads = "TRANSFER_THREADS"
    case bigMemoryMode = "BIG_MEMORY_MODE"
    case globalImageCache = "GLOBAL_IMAGE_CACHE"
    case dbWalEnable = "DB_WAL_ENABLE"

    case autoUpdateResource = "AUTO_UPDATE_RESOURCE"
    case moviePilotAutoUpdate = "MOVIEPILOT_AUTO_UPDATE"
    case debug = "DEBUG"
    case logLevel = "LOG_LEVEL"
    case timezone = "TZ"
    case appVersion = "VERSION"
  }
}

/// 可对比差异的设置草稿快照。
private struct NativeSystemEnvSnapshot: Equatable {
  var isLoaded = false

  // 网络与代理
  var proxyHost = ""
  var githubProxy = ""
  var pipProxy = ""
  var appDomain = ""
  var dohEnable = false
  var dohResolvers = ""
  var dohDomains = ""

  // 媒体与元数据
  var recognizeSource = "themoviedb"
  var searchSource = "themoviedb"
  var tmdbApiDomain = "api.themoviedb.org"
  var tmdbImageDomain = "image.tmdb.org"
  var scrapFollowTmdb = true
  var recognizePluginFirst = false
  var fanartEnable = false
  var bangumiProxyEnable = false
  var mediaRecognizeShare = true

  // 性能、订阅与同步
  var subscribeMode = "spider"
  var subscribeRssInterval = 30
  var torrentTag = "MOVIEPILOT"
  var mediaServerSyncInterval = 6
  var transferThreads = 1
  var bigMemoryMode = false
  var globalImageCache = true
  var dbWalEnable = false

  // 更新与日志
  var autoUpdateResource = true
  var moviePilotAutoUpdate = false
  var debug = false
  var logLevel = "INFO"
  var timezone = ""
  var appVersion = ""

  /// 默认空草稿。
  init() {}

  /// 从后端非敏感字段构造已载入快照。
  init(raw: NativeSystemEnvRaw) {
    isLoaded = true

    proxyHost = raw.proxyHost ?? ""
    githubProxy = raw.githubProxy ?? ""
    pipProxy = raw.pipProxy ?? ""
    appDomain = raw.appDomain ?? ""
    dohEnable = raw.dohEnable?.value ?? false
    dohResolvers = raw.dohResolvers ?? ""
    dohDomains = raw.dohDomains ?? ""

    recognizeSource = raw.recognizeSource ?? "themoviedb"
    searchSource = raw.searchSource ?? "themoviedb"
    tmdbApiDomain = raw.tmdbApiDomain ?? "api.themoviedb.org"
    tmdbImageDomain = raw.tmdbImageDomain ?? "image.tmdb.org"
    scrapFollowTmdb = raw.scrapFollowTmdb?.value ?? true
    recognizePluginFirst = raw.recognizePluginFirst?.value ?? false
    fanartEnable = raw.fanartEnable?.value ?? false
    bangumiProxyEnable = raw.bangumiProxyEnable?.value ?? false
    mediaRecognizeShare = raw.mediaRecognizeShare?.value ?? true

    subscribeMode = raw.subscribeMode ?? "spider"
    subscribeRssInterval = min(max(raw.subscribeRssInterval?.value ?? 30, 5), 720)
    torrentTag = raw.torrentTag ?? "MOVIEPILOT"
    mediaServerSyncInterval = min(max(raw.mediaServerSyncInterval?.value ?? 6, 1), 48)
    transferThreads = min(max(raw.transferThreads?.value ?? 1, 1), 16)
    bigMemoryMode = raw.bigMemoryMode?.value ?? false
    globalImageCache = raw.globalImageCache?.value ?? true
    dbWalEnable = raw.dbWalEnable?.value ?? false

    autoUpdateResource = raw.autoUpdateResource?.value ?? true
    moviePilotAutoUpdate = raw.moviePilotAutoUpdate?.value ?? false
    debug = raw.debug?.value ?? false
    logLevel = (raw.logLevel ?? "INFO").uppercased()
    timezone = raw.timezone ?? ""
    appVersion = raw.appVersion ?? ""
  }

  /// 生成仅含用户本次变更键的增量 JSON 字典。
  func changedPayload(relativeTo baseline: Self) -> [String: Any] {
    var payload: [String: Any] = [:]

    if proxyHost != baseline.proxyHost {
      payload["PROXY_HOST"] = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if githubProxy != baseline.githubProxy {
      payload["GITHUB_PROXY"] = githubProxy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if pipProxy != baseline.pipProxy {
      payload["PIP_PROXY"] = pipProxy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if appDomain != baseline.appDomain {
      payload["APP_DOMAIN"] = appDomain.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if dohEnable != baseline.dohEnable { payload["DOH_ENABLE"] = dohEnable }
    if dohResolvers != baseline.dohResolvers {
      payload["DOH_RESOLVERS"] = dohResolvers.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if dohDomains != baseline.dohDomains {
      payload["DOH_DOMAINS"] = dohDomains.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if recognizeSource != baseline.recognizeSource { payload["RECOGNIZE_SOURCE"] = recognizeSource }
    if searchSource != baseline.searchSource { payload["SEARCH_SOURCE"] = searchSource }
    if tmdbApiDomain != baseline.tmdbApiDomain {
      payload["TMDB_API_DOMAIN"] = tmdbApiDomain.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if tmdbImageDomain != baseline.tmdbImageDomain {
      payload["TMDB_IMAGE_DOMAIN"] = tmdbImageDomain.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if scrapFollowTmdb != baseline.scrapFollowTmdb {
      payload["SCRAP_FOLLOW_TMDB"] = scrapFollowTmdb
    }
    if recognizePluginFirst != baseline.recognizePluginFirst {
      payload["RECOGNIZE_PLUGIN_FIRST"] = recognizePluginFirst
    }
    if fanartEnable != baseline.fanartEnable { payload["FANART_ENABLE"] = fanartEnable }
    if bangumiProxyEnable != baseline.bangumiProxyEnable {
      payload["BANGUMI_PROXY_ENABLE"] = bangumiProxyEnable
    }
    if mediaRecognizeShare != baseline.mediaRecognizeShare {
      payload["MEDIA_RECOGNIZE_SHARE"] = mediaRecognizeShare
    }

    if subscribeMode != baseline.subscribeMode { payload["SUBSCRIBE_MODE"] = subscribeMode }
    if subscribeRssInterval != baseline.subscribeRssInterval {
      payload["SUBSCRIBE_RSS_INTERVAL"] = subscribeRssInterval
    }
    if torrentTag != baseline.torrentTag {
      payload["TORRENT_TAG"] = torrentTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if mediaServerSyncInterval != baseline.mediaServerSyncInterval {
      payload["MEDIASERVER_SYNC_INTERVAL"] = mediaServerSyncInterval
    }
    if transferThreads != baseline.transferThreads {
      payload["TRANSFER_THREADS"] = transferThreads
    }
    if bigMemoryMode != baseline.bigMemoryMode { payload["BIG_MEMORY_MODE"] = bigMemoryMode }
    if globalImageCache != baseline.globalImageCache {
      payload["GLOBAL_IMAGE_CACHE"] = globalImageCache
    }
    if dbWalEnable != baseline.dbWalEnable { payload["DB_WAL_ENABLE"] = dbWalEnable }

    if autoUpdateResource != baseline.autoUpdateResource {
      payload["AUTO_UPDATE_RESOURCE"] = autoUpdateResource
    }
    if moviePilotAutoUpdate != baseline.moviePilotAutoUpdate {
      payload["MOVIEPILOT_AUTO_UPDATE"] = moviePilotAutoUpdate
    }
    if debug != baseline.debug { payload["DEBUG"] = debug }
    if logLevel != baseline.logLevel { payload["LOG_LEVEL"] = logLevel }
    return payload
  }
}
