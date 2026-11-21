import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生系统设置中心：仅读取与编辑白名单非敏感系统设置项，支持显式单次保存至 `POST /api/v1/system/env`。
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

  /// 连续深色紫玫瑰渐变背景、2x2 状态概览卡、分组透色设置卡片与原生保存按钮。
  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let feedback {
            feedbackBanner(feedback)
          }
          if isLoading && !loaded.isLoaded {
            ProgressView("正在读取系统设置…")
              .tint(.white)
              .frame(maxWidth: .infinity, minHeight: 220)
          } else if loadFailed && !loaded.isLoaded {
            failureCard
          } else {
            overviewGrid
            modulesSection
            recognitionSection
            subscribeSection
            runtimeSection
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
      .accessibilityIdentifier("native-settings-scroll")
    }
    .navigationTitle("系统设置")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await save() }
        } label: {
          if isSaving {
            ProgressView().tint(.white)
          } else {
            Text("保存").fontWeight(.semibold)
          }
        }
        .disabled(!hasChanges || isSaving || !loaded.isLoaded)
        .accessibilityIdentifier("native-settings-save")
      }
    }
    .task(id: attempt) { await load() }
  }

  /// 当前草稿相对已载入快照是否存在变更。
  private var hasChanges: Bool { draft != loaded }

  /// 2x2 核心策略状态概览玻璃卡：聚焦高频核心参数（识别来源、订阅策略、新增即搜、媒体库同步）。
  private var overviewGrid: some View {
    LazyVGrid(
      columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
      spacing: 12
    ) {
      overviewTile(
        title: "主识别源",
        value: draft.recognizeSource == "douban" ? "豆瓣" : "TheMovieDb",
        symbol: "film.stack",
        active: true)
      overviewTile(
        title: "订阅策略",
        value:
          "\(draft.subscribeMode == "rss" ? "RSS 订阅" : "站点爬虫") · \(draft.subscribeRssInterval)分",
        symbol: "antenna.radiowaves.left.and.right",
        active: true)
      overviewTile(
        title: "新增订阅即搜",
        value: draft.subscribeSearch ? "自动触发搜索" : "等待定时刷新",
        symbol: "sparkle.magnifyingglass",
        active: draft.subscribeSearch)
      overviewTile(
        title: "媒体库同步",
        value: "每 \(draft.mediaServerSyncInterval) 小时",
        symbol: "arrow.triangle.2.circlepath.circle",
        active: true)
    }
  }

  /// 单张 2x2 状态概览玻璃小卡。
  private func overviewTile(title: String, value: String, symbol: String, active: Bool) -> some View
  {
    CinematicPanel(padding: 13) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: symbol)
          .font(.title3.weight(.semibold))
          .foregroundStyle(Color(red: 0.78, green: 0.66, blue: 1.0))
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
        HStack(spacing: 6) {
          Circle()
            .fill(active ? Color(red: 0.56, green: 0.92, blue: 0.72) : .white.opacity(0.40))
            .frame(width: 6, height: 6)
          Text(value)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.76))
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 八类专项设置与网络诊断直达入口分组。
  private var modulesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("专项配置与诊断").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(NativeSystemModulesPage.Domain.allCases.enumerated()), id: \.element.id) {
            index, domain in
            if index > 0 { CinematicFormDivider() }
            NavigationLink {
              NativeSystemModulesPage(session: session, initialDomain: domain)
            } label: {
              CinematicFormRow(symbol: domain.symbol) {
                HStack {
                  Text(domain.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("native-settings-domain-\(domain.rawValue)")
          }
        }
      }
    }
  }

  /// 媒体识别与搜索配置分组。
  private var recognitionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("媒体识别与搜索").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel {
        VStack(spacing: 14) {
          HStack {
            Text("主识别来源").font(.subheadline)
            Spacer()
            Picker("主识别来源", selection: $draft.recognizeSource) {
              Text("TheMovieDb").tag("themoviedb")
              Text("豆瓣").tag("douban")
            }
            .tint(.white)
            .accessibilityIdentifier("native-settings-recognize-source")
          }
          Divider().overlay(.white.opacity(0.08))
          HStack {
            Text("搜索数据源").font(.subheadline)
            Spacer()
            Picker("搜索数据源", selection: $draft.searchSource) {
              Text("TheMovieDb").tag("themoviedb")
              Text("豆瓣").tag("douban")
            }
            .tint(.white)
            .accessibilityIdentifier("native-settings-search-source")
          }
          Divider().overlay(.white.opacity(0.08))
          Toggle("刮削跟随 TMDB 语言", isOn: $draft.scrapFollowTmdb)
            .font(.subheadline)
            .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
            .accessibilityIdentifier("native-settings-scrap-follow-tmdb")
        }
      }
    }
  }

  /// 订阅与下载核心配置分组。
  private var subscribeSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("订阅与下载").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel {
        VStack(spacing: 14) {
          HStack {
            Text("订阅模式").font(.subheadline)
            Spacer()
            Picker("订阅模式", selection: $draft.subscribeMode) {
              Text("站点爬虫").tag("spider")
              Text("RSS 订阅").tag("rss")
            }
            .tint(.white)
            .accessibilityIdentifier("native-settings-subscribe-mode")
          }
          Divider().overlay(.white.opacity(0.08))
          Stepper(
            value: $draft.subscribeRssInterval, in: 5...720, step: 5
          ) {
            HStack {
              Text("刷新周期").font(.subheadline)
              Spacer()
              Text("\(draft.subscribeRssInterval) 分钟")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.78))
            }
          }
          Divider().overlay(.white.opacity(0.08))
          Toggle("新增订阅立即搜索", isOn: $draft.subscribeSearch)
            .font(.subheadline)
            .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
            .accessibilityIdentifier("native-settings-subscribe-search")
          Divider().overlay(.white.opacity(0.08))
          HStack {
            Text("种子标签").font(.subheadline)
            Spacer()
            TextField(
              "MOVIEPILOT",
              text: $draft.torrentTag,
              prompt: Text("MOVIEPILOT").foregroundColor(.white.opacity(0.45))
            )
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(maxWidth: 160)
            .accessibilityIdentifier("native-settings-torrent-tag")
          }
          Divider().overlay(.white.opacity(0.08))
          Stepper(value: $draft.mediaServerSyncInterval, in: 1...48) {
            HStack {
              Text("媒体库同步").font(.subheadline)
              Spacer()
              Text("每 \(draft.mediaServerSyncInterval) 小时")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.78))
            }
          }
        }
      }
    }
  }

  /// 系统运行与缓存配置分组。
  private var runtimeSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("系统与缓存").font(.headline).accessibilityAddTraits(.isHeader)
      CinematicPanel {
        VStack(spacing: 14) {
          Toggle("全局图片缓存", isOn: $draft.globalImageCache)
            .font(.subheadline)
            .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
            .accessibilityIdentifier("native-settings-image-cache")
          Divider().overlay(.white.opacity(0.08))
          Toggle("调试模式", isOn: $draft.debug)
            .font(.subheadline)
            .tint(Color(red: 0.60, green: 0.44, blue: 0.92))
            .accessibilityIdentifier("native-settings-debug")
          Divider().overlay(.white.opacity(0.08))
          HStack {
            Text("日志级别").font(.subheadline)
            Spacer()
            Picker("日志级别", selection: $draft.logLevel) {
              ForEach(["DEBUG", "INFO", "WARNING", "ERROR"], id: \.self) { level in
                Text(level).tag(level)
              }
            }
            .tint(.white)
            .accessibilityIdentifier("native-settings-log-level")
          }
          if !draft.timezone.isEmpty {
            Divider().overlay(.white.opacity(0.08))
            HStack {
              Text("服务端时区").font(.subheadline)
              Spacer()
              Text(draft.timezone).font(.subheadline).foregroundStyle(.white.opacity(0.68))
            }
          }
          if !draft.appVersion.isEmpty {
            Divider().overlay(.white.opacity(0.08))
            HStack {
              Text("后端版本").font(.subheadline)
              Spacer()
              Text(draft.appVersion)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.68))
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

  /// 从 `GET /api/v1/system/env` 读取受控白名单字段。
  private func load() async {
    isLoading = true
    loadFailed = false
    defer { isLoading = false }
    do {
      let endpoint = try APIEndpoint(path: ["system", "env"])
      let envelope = try await session.request(endpoint, as: NativeSystemEnvEnvelope.self).value
      try Task.checkCancellation()
      guard let raw = envelope.payload else {
        loadFailed = true
        return
      }
      let snapshot = NativeSystemEnvSnapshot(raw: raw)
      loaded = snapshot
      draft = snapshot
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
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
      value = ["true", "1", "yes", "on"].contains(
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

/// `GET /api/v1/system/env` 非敏感白名单解码结构体。
private struct NativeSystemEnvRaw: Decodable, Sendable {
  let recognizeSource: String?
  let searchSource: String?
  let scrapFollowTmdb: NativeFlexibleBool?
  let subscribeMode: String?
  let subscribeRssInterval: NativeFlexibleInt?
  let subscribeSearch: NativeFlexibleBool?
  let torrentTag: String?
  let mediaServerSyncInterval: NativeFlexibleInt?
  let globalImageCache: NativeFlexibleBool?
  let debug: NativeFlexibleBool?
  let logLevel: String?
  let timezone: String?
  let appVersion: String?

  /// 仅解码允许在移动端展示的非敏感环境键。
  private enum CodingKeys: String, CodingKey {
    case recognizeSource = "RECOGNIZE_SOURCE"
    case searchSource = "SEARCH_SOURCE"
    case scrapFollowTmdb = "SCRAP_FOLLOW_TMDB"
    case subscribeMode = "SUBSCRIBE_MODE"
    case subscribeRssInterval = "SUBSCRIBE_RSS_INTERVAL"
    case subscribeSearch = "SUBSCRIBE_SEARCH"
    case torrentTag = "TORRENT_TAG"
    case mediaServerSyncInterval = "MEDIASERVER_SYNC_INTERVAL"
    case globalImageCache = "GLOBAL_IMAGE_CACHE"
    case debug = "DEBUG"
    case logLevel = "LOG_LEVEL"
    case timezone = "TZ"
    case appVersion = "VERSION"
  }
}

/// 可对比差异的设置草稿快照。
private struct NativeSystemEnvSnapshot: Equatable {
  var isLoaded = false
  var recognizeSource = "themoviedb"
  var searchSource = "themoviedb"
  var scrapFollowTmdb = true
  var subscribeMode = "spider"
  var subscribeRssInterval = 30
  var subscribeSearch = false
  var torrentTag = "MOVIEPILOT"
  var mediaServerSyncInterval = 6
  var globalImageCache = true
  var debug = false
  var logLevel = "INFO"
  var timezone = ""
  var appVersion = ""

  /// 默认空草稿。
  init() {}

  /// 从后端非敏感字段构造已载入快照。
  init(raw: NativeSystemEnvRaw) {
    isLoaded = true
    recognizeSource = raw.recognizeSource ?? "themoviedb"
    searchSource = raw.searchSource ?? "themoviedb"
    scrapFollowTmdb = raw.scrapFollowTmdb?.value ?? true
    subscribeMode = raw.subscribeMode ?? "spider"
    subscribeRssInterval = min(max(raw.subscribeRssInterval?.value ?? 30, 5), 720)
    subscribeSearch = raw.subscribeSearch?.value ?? false
    torrentTag = raw.torrentTag ?? "MOVIEPILOT"
    mediaServerSyncInterval = min(max(raw.mediaServerSyncInterval?.value ?? 6, 1), 48)
    globalImageCache = raw.globalImageCache?.value ?? true
    debug = raw.debug?.value ?? false
    logLevel = (raw.logLevel ?? "INFO").uppercased()
    timezone = raw.timezone ?? ""
    appVersion = raw.appVersion ?? ""
  }

  /// 生成仅含用户本次变更键的增量 JSON 字典。
  func changedPayload(relativeTo baseline: Self) -> [String: Any] {
    var payload: [String: Any] = [:]
    if recognizeSource != baseline.recognizeSource { payload["RECOGNIZE_SOURCE"] = recognizeSource }
    if searchSource != baseline.searchSource { payload["SEARCH_SOURCE"] = searchSource }
    if scrapFollowTmdb != baseline.scrapFollowTmdb {
      payload["SCRAP_FOLLOW_TMDB"] = scrapFollowTmdb
    }
    if subscribeMode != baseline.subscribeMode { payload["SUBSCRIBE_MODE"] = subscribeMode }
    if subscribeRssInterval != baseline.subscribeRssInterval {
      payload["SUBSCRIBE_RSS_INTERVAL"] = subscribeRssInterval
    }
    if subscribeSearch != baseline.subscribeSearch { payload["SUBSCRIBE_SEARCH"] = subscribeSearch }
    if torrentTag != baseline.torrentTag { payload["TORRENT_TAG"] = torrentTag }
    if mediaServerSyncInterval != baseline.mediaServerSyncInterval {
      payload["MEDIASERVER_SYNC_INTERVAL"] = mediaServerSyncInterval
    }
    if globalImageCache != baseline.globalImageCache {
      payload["GLOBAL_IMAGE_CACHE"] = globalImageCache
    }
    if debug != baseline.debug { payload["DEBUG"] = debug }
    if logLevel != baseline.logLevel { payload["LOG_LEVEL"] = logLevel }
    return payload
  }
}
