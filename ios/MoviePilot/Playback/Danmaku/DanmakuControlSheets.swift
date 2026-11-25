import MoviePilotCore
import MoviePilotSession
import SwiftUI

// MARK: - 1. 播放器内弹幕设置半弹窗

@MainActor
struct DanmakuSettingsSheetView: View {
  @ObservedObject var prefs: DanmakuPreferencesStore
  let matchedSummary: String
  let totalCount: Int
  let isFromBinding: Bool
  @Binding var shiftMs: Int
  let onPreferencesChanged: () -> Void
  let onShiftChanged: (Int) -> Void
  let onSaveShiftToServer: () async -> Void
  let onOpenManualMatch: () -> Void
  let onForceRefresh: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var newKeyword = ""
  @State private var isSavingShift = false
  @State private var isRefreshing = false
  @State private var feedbackMessage: String?

  private let areaOptions: [(String, Double)] = [
    ("1/4 屏", 0.25), ("半屏", 0.5), ("3/4 屏", 0.75), ("全屏", 1.0),
  ]
  private let densityOptions: [Int] = [20, 40, 60, 100]
  private let shiftDeltas: [(String, Int)] = [
    ("-5s", -5000), ("-1s", -1000), ("-0.5s", -500),
    ("+0.5s", 500), ("+1s", 1000), ("+5s", 5000),
  ]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle(L10n.text("显示弹幕"), isOn: $prefs.enabled)
            .onChange(of: prefs.enabled) { _ in onPreferencesChanged() }

          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(matchedSummary.isEmpty ? L10n.text("未匹配到弹幕") : matchedSummary)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
              if totalCount > 0 {
                Text(
                  isFromBinding
                    ? "手动绑定 · 共 \(totalCount) 条弹幕"
                    : "自动匹配 · 共 \(totalCount) 条弹幕"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
            Spacer()
            Button(L10n.text("更换匹配")) {
              dismiss()
              onOpenManualMatch()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }

          Button {
            isRefreshing = true
            Task {
              await onForceRefresh()
              isRefreshing = false
              feedbackMessage = "已从服务端刷新最新弹幕"
            }
          } label: {
            HStack {
              Label(L10n.text("强制刷新弹幕"), systemImage: "arrow.clockwise")
              Spacer()
              if isRefreshing { ProgressView().controlSize(.small) }
            }
          }
          .disabled(isRefreshing)
        }

        Section(L10n.text("外观与布局")) {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(L10n.text("不透明度"))
              Spacer()
              Text("\(Int((prefs.opacity * 100).rounded()))%").foregroundStyle(.secondary)
            }
            Slider(value: $prefs.opacity, in: 0.2...1.0, step: 0.05)
              .onChange(of: prefs.opacity) { _ in onPreferencesChanged() }
          }

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(L10n.text("字号大小"))
              Spacer()
              Text(String(format: "%.2fx", prefs.fontScale)).foregroundStyle(.secondary)
            }
            Slider(value: $prefs.fontScale, in: 0.75...1.5, step: 0.05)
              .onChange(of: prefs.fontScale) { _ in onPreferencesChanged() }
          }

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(L10n.text("滚动速度"))
              Spacer()
              Text(String(format: "%.1fx", prefs.speed)).foregroundStyle(.secondary)
            }
            Slider(value: $prefs.speed, in: 0.6...1.6, step: 0.1)
              .onChange(of: prefs.speed) { _ in onPreferencesChanged() }
          }

          Picker(L10n.text("显示区域"), selection: $prefs.areaRatio) {
            ForEach(areaOptions, id: \.1) { option in
              Text(option.0).tag(option.1)
            }
          }
          .pickerStyle(.segmented)
          .onChange(of: prefs.areaRatio) { _ in onPreferencesChanged() }

          Picker(L10n.text("同屏上限"), selection: $prefs.maxOnScreen) {
            ForEach(densityOptions, id: \.self) { count in
              Text("\(count)").tag(count)
            }
          }
          .pickerStyle(.segmented)
          .onChange(of: prefs.maxOnScreen) { _ in onPreferencesChanged() }
        }

        Section(L10n.text("时间偏移")) {
          HStack {
            Text(L10n.text("当前偏移"))
            Spacer()
            Text(formatOffset(shiftMs))
              .font(.subheadline.monospacedDigit().weight(.semibold))
              .foregroundStyle(shiftMs == 0 ? .secondary : .primary)
            if shiftMs != 0 {
              Button("重置") {
                shiftMs = 0
                onShiftChanged(0)
              }
              .buttonStyle(.bordered)
              .controlSize(.mini)
            }
          }

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(shiftDeltas, id: \.1) { item in
                Button(item.0) {
                  let next = max(-600_000, min(600_000, shiftMs + item.1))
                  shiftMs = next
                  onShiftChanged(next)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
              }
            }
          }

          Button {
            isSavingShift = true
            Task {
              await onSaveShiftToServer()
              isSavingShift = false
              feedbackMessage = "已将当前时间偏移保存到服务端"
            }
          } label: {
            HStack {
              Label(L10n.text("保存偏移到服务端"), systemImage: "icloud.and.arrow.up")
              Spacer()
              if isSavingShift { ProgressView().controlSize(.small) }
            }
          }
          .disabled(isSavingShift)
        }

        Section(L10n.text("类型过滤")) {
          Toggle(L10n.text("滚动弹幕"), isOn: $prefs.allowScroll)
            .onChange(of: prefs.allowScroll) { _ in onPreferencesChanged() }
          Toggle(L10n.text("顶部弹幕"), isOn: $prefs.allowTop)
            .onChange(of: prefs.allowTop) { _ in onPreferencesChanged() }
          Toggle(L10n.text("底部弹幕"), isOn: $prefs.allowBottom)
            .onChange(of: prefs.allowBottom) { _ in onPreferencesChanged() }
          Toggle(L10n.text("彩色弹幕"), isOn: $prefs.allowColor)
            .onChange(of: prefs.allowColor) { _ in onPreferencesChanged() }
          Toggle(L10n.text("合并重复弹幕"), isOn: $prefs.mergeDuplicates)
            .onChange(of: prefs.mergeDuplicates) { _ in onPreferencesChanged() }
        }

        Section(L10n.text("关键词屏蔽")) {
          HStack {
            TextField(L10n.text("输入屏蔽词（支持 /正则/）"), text: $newKeyword)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .onSubmit(addKeyword)
            Button("添加", action: addKeyword)
              .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          ForEach(prefs.blockKeywords, id: \.self) { kw in
            HStack {
              Text(kw)
              Spacer()
              Button(role: .destructive) {
                prefs.removeBlockKeyword(kw)
                onPreferencesChanged()
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.plain)
            }
          }
        }

        if let feedbackMessage {
          Section {
            Text(feedbackMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle(L10n.text("弹幕设置"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("完成") { dismiss() }
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private func addKeyword() {
    let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    prefs.addBlockKeyword(trimmed)
    newKeyword = ""
    onPreferencesChanged()
  }

  private func formatOffset(_ ms: Int) -> String {
    if ms == 0 { return "0.0s" }
    let sec = Double(ms) / 1000.0
    return String(format: "%+.1fs", sec)
  }
}

// MARK: - 2. 播放器内手动搜索与选集纠偏弹窗

@MainActor
struct DanmakuManualMatchSheetView: View {
  let repository: DanmakuRepository
  let initialKeyword: String
  let initialCandidates: [DanmakuEpisodeCandidateDTO]
  let isFromBinding: Bool
  let onSelectEpisode: (DanmakuEpisodeCandidateDTO) async -> Void
  let onUnbind: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var keyword: String
  @State private var results: [DanmakuAnimeSearchItemDTO] = []
  @State private var selectedBangumi: DanmakuBangumiDTO?
  @State private var isSearching = false
  @State private var isLoadingBangumi = false
  @State private var errorMessage: String?

  init(
    repository: DanmakuRepository,
    initialKeyword: String,
    initialCandidates: [DanmakuEpisodeCandidateDTO],
    isFromBinding: Bool,
    onSelectEpisode: @escaping (DanmakuEpisodeCandidateDTO) async -> Void,
    onUnbind: @escaping () async -> Void
  ) {
    self.repository = repository
    self.initialKeyword = initialKeyword
    self.initialCandidates = initialCandidates
    self.isFromBinding = isFromBinding
    self.onSelectEpisode = onSelectEpisode
    self.onUnbind = onUnbind
    _keyword = State(initialValue: initialKeyword)
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            TextField(L10n.text("输入作品名搜索弹幕"), text: $keyword)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .onSubmit { Task { await runSearch() } }
            Button("搜索") { Task { await runSearch() } }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
              .disabled(
                isSearching || keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }

          if isFromBinding {
            Button(role: .destructive) {
              Task {
                await onUnbind()
                dismiss()
              }
            } label: {
              Label(L10n.text("解绑恢复自动匹配"), systemImage: "link.badge.minus")
            }
          }
        }

        if let errorMessage {
          Section {
            Text(errorMessage).foregroundStyle(.red).font(.caption)
          }
        }

        if let bangumi = selectedBangumi {
          Section {
            Button {
              selectedBangumi = nil
            } label: {
              Label("返回作品列表", systemImage: "chevron.left")
            }
            ForEach(bangumi.episodes) { ep in
              episodeRow(ep)
            }
          } header: {
            Text(bangumi.animeTitle)
          }
        } else if !results.isEmpty {
          Section("搜索结果") {
            ForEach(results) { anime in
              if !anime.episodes.isEmpty {
                DisclosureGroup {
                  ForEach(anime.episodes) { ep in
                    episodeRow(ep)
                  }
                } label: {
                  animeHeader(anime)
                }
              } else {
                Button {
                  Task { await loadBangumi(anime.animeId) }
                } label: {
                  HStack {
                    animeHeader(anime)
                    Spacer()
                    if isLoadingBangumi {
                      ProgressView().controlSize(.small)
                    } else {
                      Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                  }
                }
              }
            }
          }
        } else if !initialCandidates.isEmpty {
          Section("推荐候选") {
            ForEach(initialCandidates) { ep in
              episodeRow(ep)
            }
          }
        }
      }
      .navigationTitle(L10n.text("搜索弹幕剧集"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭") { dismiss() }
        }
      }
      .task {
        if initialCandidates.isEmpty && !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          await runSearch()
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private func animeHeader(_ anime: DanmakuAnimeSearchItemDTO) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(anime.animeTitle).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
      let meta = [anime.animeType, anime.episodeCount.map { "共 \($0) 集" }]
        .compactMap { $0 }
        .joined(separator: " · ")
      if !meta.isEmpty {
        Text(meta).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func episodeRow(_ ep: DanmakuEpisodeCandidateDTO) -> some View {
    Button {
      Task {
        await onSelectEpisode(ep)
        dismiss()
      }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(ep.episodeTitle.isEmpty ? "第 \(ep.episodeNumber ?? "\(ep.episodeId)") 集" : ep.episodeTitle)
          .font(.subheadline)
          .foregroundStyle(.primary)
        if !ep.animeTitle.isEmpty {
          Text(ep.animeTitle).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func runSearch() async {
    let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    isSearching = true
    errorMessage = nil
    selectedBangumi = nil
    defer { isSearching = false }
    do {
      results = try await repository.search(keyword: q)
      if results.isEmpty {
        errorMessage = "未搜索到匹配作品，请尝试简化剧名关键词"
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func loadBangumi(_ animeId: Int) async {
    isLoadingBangumi = true
    errorMessage = nil
    defer { isLoadingBangumi = false }
    do {
      selectedBangumi = try await repository.fetchBangumi(animeId: animeId)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

// MARK: - 3. 管理员后台弹幕服务配置页（设置 → 播放偏好 → 弹幕服务配置）

@MainActor
struct NativeDanmakuAdminConfigPage: View {
  let session: NativeSession

  @ObservedObject private var appearance = NativeAppearanceStore.shared

  @State private var enabled = false
  @State private var apiBaseUrl = ""
  @State private var authMode = "none"
  @State private var appId = ""
  @State private var appSecret = ""
  @State private var hasAppSecret = false
  @State private var tokenHeader = "Authorization"
  @State private var tokenPrefix = "Bearer "
  @State private var token = ""
  @State private var hasToken = false
  @State private var withRelated = true
  @State private var chConvert = 1
  @State private var cacheTtlHours = 24
  @State private var cacheMaxMb = 512
  @State private var timeoutSeconds = 10
  @State private var useProxy = false
  @State private var verifyTls = true
  @State private var cacheStats = DanmakuCacheStatsDTO(fileCount: 0, totalBytes: 0, maxMb: 512)

  @State private var isLoading = true
  @State private var isSaving = false
  @State private var isTesting = false
  @State private var isClearingCache = false
  @State private var statusBanner: (ok: Bool, text: String)?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if isLoading {
            HStack(spacing: 10) {
              ProgressView()
              Text("正在加载弹幕服务配置…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 48)
          } else {
            if let banner = statusBanner {
              HStack(spacing: 10) {
                Image(systemName: banner.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                  .foregroundStyle(banner.ok ? .green : NativeTheme.danger)
                Text(banner.text)
                  .font(.footnote)
                  .foregroundStyle(.primary)
              }
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                (banner.ok ? Color.green : NativeTheme.danger).opacity(0.14),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
              )
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                Toggle(L10n.text("启用弹幕代理服务"), isOn: $enabled)
                  .tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                VStack(alignment: .leading, spacing: 6) {
                  Text(L10n.text("自定义弹弹play 兼容 API 地址")).font(.subheadline)
                  TextField("https://danmu.example.com", text: $apiBaseUrl)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                HStack {
                  Text(L10n.text("鉴权方式")).font(.body)
                  Spacer()
                  Picker(L10n.text("鉴权方式"), selection: $authMode) {
                    Text(L10n.text("无鉴权 / 路径令牌")).tag("none")
                    Text(L10n.text("弹弹play v2 签名")).tag("dandanplay_v2")
                    Text(L10n.text("自定义请求头令牌")).tag("header_token")
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)

                if authMode == "dandanplay_v2" {
                  CinematicFormDivider()
                  HStack {
                    Text("AppId").font(.subheadline).frame(width: 90, alignment: .leading)
                    TextField("输入 AppId", text: $appId)
                      .multilineTextAlignment(.trailing)
                      .textInputAutocapitalization(.never)
                      .autocorrectionDisabled()
                  }
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  CinematicFormDivider()
                  HStack {
                    Text("AppSecret").font(.subheadline).frame(width: 90, alignment: .leading)
                    SecureField(hasAppSecret ? "已加密保存（留空不变）" : "输入 AppSecret", text: $appSecret)
                      .multilineTextAlignment(.trailing)
                  }
                  .padding(.horizontal, 16).padding(.vertical, 12)
                } else if authMode == "header_token" {
                  CinematicFormDivider()
                  HStack {
                    Text("请求头").font(.subheadline).frame(width: 90, alignment: .leading)
                    TextField("Authorization", text: $tokenHeader)
                      .multilineTextAlignment(.trailing)
                      .textInputAutocapitalization(.never)
                      .autocorrectionDisabled()
                  }
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  CinematicFormDivider()
                  HStack {
                    Text("令牌前缀").font(.subheadline).frame(width: 90, alignment: .leading)
                    TextField("Bearer ", text: $tokenPrefix)
                      .multilineTextAlignment(.trailing)
                      .textInputAutocapitalization(.never)
                      .autocorrectionDisabled()
                  }
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  CinematicFormDivider()
                  HStack {
                    Text("令牌").font(.subheadline).frame(width: 90, alignment: .leading)
                    SecureField(hasToken ? "已加密保存（留空不变）" : "输入令牌", text: $token)
                      .multilineTextAlignment(.trailing)
                  }
                  .padding(.horizontal, 16).padding(.vertical, 12)
                }
              }
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                Toggle(L10n.text("聚合关联第三方弹幕"), isOn: $withRelated)
                  .tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                HStack {
                  Text(L10n.text("简繁转换"))
                  Spacer()
                  Picker(L10n.text("简繁转换"), selection: $chConvert) {
                    Text(L10n.text("不转换")).tag(0)
                    Text(L10n.text("转简体")).tag(1)
                    Text(L10n.text("转繁体")).tag(2)
                  }
                  .pickerStyle(.segmented)
                  .frame(width: 210)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                Stepper("缓存有效期：\(cacheTtlHours) 小时", value: $cacheTtlHours, in: 1...720)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                Stepper("缓存上限：\(cacheMaxMb) MB", value: $cacheMaxMb, in: 64...4096, step: 64)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                Stepper("请求超时：\(timeoutSeconds) 秒", value: $timeoutSeconds, in: 3...60)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                Toggle("复用全局代理", isOn: $useProxy)
                  .tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                Toggle("校验 HTTPS 证书", isOn: $verifyTls)
                  .tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
              }
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                HStack {
                  VStack(alignment: .leading, spacing: 3) {
                    Text("磁盘缓存统计").font(.body)
                    Text(
                      "\(cacheStats.fileCount) 个分集 · \(ByteCountFormatter.string(fromByteCount: Int64(cacheStats.totalBytes), countStyle: .file)) / \(cacheStats.maxMb) MB"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button(role: .destructive) {
                    Task { await clearCache() }
                  } label: {
                    if isClearingCache {
                      ProgressView().controlSize(.small)
                    } else {
                      Text(L10n.text("清空弹幕缓存")).font(.subheadline.weight(.semibold))
                    }
                  }
                  .disabled(isClearingCache)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
              }
            }

            HStack(spacing: 12) {
              Button {
                Task { await testConnection() }
              } label: {
                HStack {
                  if isTesting { ProgressView().controlSize(.small) }
                  Text(L10n.text("测试连接")).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
              }
              .buttonStyle(.bordered)
              .disabled(isTesting || isSaving)

              Button {
                Task { await saveConfig() }
              } label: {
                HStack {
                  if isSaving { ProgressView().controlSize(.small) }
                  Text("保存配置").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
              }
              .buttonStyle(.borderedProminent)
              .tint(appearance.accentColor)
              .disabled(isSaving || isTesting)
            }
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle(L10n.text("弹幕服务配置"))
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .task { await loadConfig() }
  }

  private func makeRepository() throws -> DanmakuRepository {
    let auth = try session.playbackAuthorization()
    return DanmakuRepository(address: auth.address, accessToken: auth.accessToken)
  }

  private func apply(_ dto: DanmakuConfigDTO) {
    enabled = dto.enabled
    apiBaseUrl = dto.apiBaseUrl
    authMode = dto.authMode
    appId = dto.appId
    hasAppSecret = dto.hasAppSecret
    tokenHeader = dto.tokenHeader
    tokenPrefix = dto.tokenPrefix
    hasToken = dto.hasToken
    withRelated = dto.withRelated
    chConvert = dto.chConvert
    cacheTtlHours = dto.cacheTtlHours
    cacheMaxMb = dto.cacheMaxMb
    timeoutSeconds = dto.timeoutSeconds
    useProxy = dto.useProxy
    verifyTls = dto.verifyTls
    cacheStats = dto.cacheStats
  }

  private func loadConfig() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let dto = try await makeRepository().fetchAdminConfig()
      apply(dto)
    } catch {
      statusBanner = (false, error.localizedDescription)
    }
  }

  private func saveConfig() async {
    isSaving = true
    statusBanner = nil
    defer { isSaving = false }
    do {
      let payload = DanmakuConfigUpdatePayload(
        enabled: enabled,
        apiBaseUrl: apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
        authMode: authMode,
        appId: appId.trimmingCharacters(in: .whitespacesAndNewlines),
        appSecret: appSecret.isEmpty ? nil : appSecret,
        clearAppSecret: false,
        tokenHeader: tokenHeader,
        tokenPrefix: tokenPrefix,
        token: token.isEmpty ? nil : token,
        clearToken: false,
        withRelated: withRelated,
        chConvert: chConvert,
        cacheTtlHours: cacheTtlHours,
        cacheMaxMb: cacheMaxMb,
        timeoutSeconds: timeoutSeconds,
        useProxy: useProxy,
        verifyTls: verifyTls
      )
      let updated = try await makeRepository().updateAdminConfig(payload)
      apply(updated)
      appSecret = ""
      token = ""
      statusBanner = (true, "弹幕服务配置已加密保存")
    } catch {
      statusBanner = (false, error.localizedDescription)
    }
  }

  private func testConnection() async {
    isTesting = true
    statusBanner = nil
    defer { isTesting = false }
    do {
      let payload = DanmakuConfigTestPayload(
        apiBaseUrl: apiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
        authMode: authMode,
        appId: appId.trimmingCharacters(in: .whitespacesAndNewlines),
        appSecret: appSecret.isEmpty ? nil : appSecret,
        tokenHeader: tokenHeader,
        tokenPrefix: tokenPrefix,
        token: token.isEmpty ? nil : token,
        timeoutSeconds: timeoutSeconds,
        useProxy: useProxy,
        verifyTls: verifyTls
      )
      let res = try await makeRepository().testAdminConfig(payload)
      statusBanner = (res.ok, res.message)
    } catch {
      statusBanner = (false, error.localizedDescription)
    }
  }

  private func clearCache() async {
    isClearingCache = true
    statusBanner = nil
    defer { isClearingCache = false }
    do {
      let res = try await makeRepository().clearServerCache()
      let freed = ByteCountFormatter.string(fromByteCount: Int64(res.freedBytes), countStyle: .file)
      statusBanner = (true, "已清理 \(res.removedFiles) 个缓存文件（释放 \(freed)）")
      let refreshed = try await makeRepository().fetchAdminConfig()
      apply(refreshed)
    } catch {
      statusBanner = (false, error.localizedDescription)
    }
  }
}
