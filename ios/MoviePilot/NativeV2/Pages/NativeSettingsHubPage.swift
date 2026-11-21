import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生设置主中心（底部「设置」标签）：融合顶部服务器存储卡、双列状态方卡、系统核心参数、4 列捷径瓷砖、分组偏好列表与右上角系统菜单（通知/小组件/语言/切换服务/退出登录）。
@MainActor
struct NativeSettingsHubPage: View {
  let session: NativeSession
  let snapshot: NativeSessionSnapshot
  let currentLanguage: AppLanguage
  let onNavigate: (NativeWorkspaceDestination) -> Void
  let onOpenModules: () -> Void
  let onOpenPlugins: () -> Void
  let onSelectLanguage: (AppLanguage) -> Void
  let onSwitchServer: () -> Void
  let onLogout: () -> Void

  @State private var storage: NativeSettingsStorageBrief?
  @State private var siteCount: Int?
  @State private var showsNotificationSettings = false
  @State private var showsWidgetSettings = false
  @State private var showsPluginMarketSources = false
  @AppStorage("nativeV2.showFloatingAssistant") private var showFloatingAssistant = true
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme

  /// 连续紫玫瑰渐变背景与清晰分组层级（不重复展示当前用户信息，会话与通知项统一收口至右上角菜单）。
  var body: some View {
    ZStack {
      CinematicBackground()
      Form {
        if let storage, storage.total > 0 {
          storageTelemetryCard(storage)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)
        }

        if snapshot.user.isSuperuser {
          primarySquareGrid
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)

          featuredSystemBanner
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
            .listRowSeparator(.hidden)

          appPreferenceTiles
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)

          quickConfigPillsGrid
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)

          mediaDirectorySection
          appearanceAndPluginsSection
        } else {
          standardUserGrid
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)
          systemIntegrationSection
        }
      }
      .scrollContentBackground(.hidden)
      .scrollIndicators(.hidden)
      .refreshable { await loadOverview(forceRefresh: true) }
      .frame(maxWidth: 740)
      .frame(maxWidth: .infinity)
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("设置")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button {
            showsNotificationSettings = true
          } label: {
            Label("通知设置", systemImage: "bell.and.waves.left.and.right")
          }
          .accessibilityIdentifier("native-settings-hub-push")

          Button {
            showsWidgetSettings = true
          } label: {
            Label("桌面小组件", systemImage: "rectangle.3.group")
          }
          .accessibilityIdentifier("native-settings-hub-widgets")

          Menu {
            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
              Button {
                onSelectLanguage(lang)
              } label: {
                if currentLanguage == lang {
                  Label(lang.title, systemImage: "checkmark")
                } else {
                  Text(lang.title)
                }
              }
            }
          } label: {
            Label("界面语言 · \(currentLanguage.title)", systemImage: "globe")
          }
          .accessibilityIdentifier("native-v2-language")

          Divider()

          Button {
            onSwitchServer()
          } label: {
            Label("切换服务", systemImage: "arrow.left.arrow.right")
          }
          .accessibilityIdentifier("native-v2-switch")

          Button(role: .destructive) {
            onLogout()
          } label: {
            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
          }
          .accessibilityIdentifier("native-v2-logout")
        } label: {
          Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多设置与账号")
        .accessibilityIdentifier("native-settings-more-menu")
      }
    }
    .sheet(isPresented: $showsNotificationSettings) {
      NativeNotificationSettingsSheet(session: session)
    }
    .sheet(isPresented: $showsWidgetSettings) {
      NativeWidgetSettingsSheet(session: session)
    }
    .sheet(isPresented: $showsPluginMarketSources) {
      NativePluginMarketSourcesSheet(session: session)
    }
    .task(id: snapshot.scope) { await loadOverview(forceRefresh: false) }
  }

  /// 第一层：简洁服务器存储容量概览卡（仅展示服务地址与真实存储空间，不重复展示当前用户信息）。
  private func storageTelemetryCard(_ storage: NativeSettingsStorageBrief) -> some View {
    let host = session.instance.address.url.host ?? session.instance.address.url.absoluteString
    let ratio = storage.usedRatio
    let percentText = "\(Int((ratio * 100).rounded()))%"
    let freeBytes = max(storage.total - storage.used, 0)
    return CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Circle()
            .fill(Color(red: 0.42, green: 0.88, blue: 0.56).opacity(0.85))
            .frame(width: 6, height: 6)
          Text(host)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 8)
          Text("\(Self.formatBytes(storage.used)) / \(Self.formatBytes(storage.total))")
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.primary.opacity(0.84))
        }
        GeometryReader { bar in
          let w = max(bar.size.width, 1)
          let usedW = max(w * min(max(ratio, 0.04), 1.0), 8)
          ZStack(alignment: .leading) {
            Capsule().fill(.primary.opacity(0.12))
            Capsule()
              .fill(
                LinearGradient(
                  colors: [
                    appearance.accentColor,
                    Color(red: 0.92, green: 0.52, blue: 0.70),
                  ],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .frame(width: usedW)
          }
        }
        .frame(height: 7)
        HStack {
          legendDot("已用 \(percentText)", color: appearance.accentColor)
          Spacer()
          Text("可用 \(Self.formatBytes(freeBytes))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  /// 第二层：双列大图标状态方卡，突出「站点管理」与「用户管理」。
  private var primarySquareGrid: some View {
    HStack(spacing: 12) {
      squareStatusCard(
        title: "站点管理",
        statusText: siteCount.map { "已启用 \($0) 个站点" } ?? "正常 · 索引同步",
        symbol: "globe",
        tint: Color(red: 0.36, green: 0.68, blue: 1.0),
        statusColor: Color(red: 0.34, green: 0.88, blue: 0.54),
        id: "native-workspace-sites"
      ) {
        onNavigate(.sites)
      }

      squareStatusCard(
        title: "用户管理",
        statusText: snapshot.user.isSuperuser ? "超级管理员" : "普通成员",
        symbol: "person.2.fill",
        tint: Color(red: 0.72, green: 0.44, blue: 0.98),
        statusColor: Color(red: 0.78, green: 0.66, blue: 1.0),
        id: "native-workspace-users"
      ) {
        onNavigate(.users)
      }
    }
  }

  /// 第三层：高级系统设置入口卡，直达网络代理、元数据域名、性能缓存与更新日志等核心高级参数。
  private var featuredSystemBanner: some View {
    CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 7) {
          Image(systemName: "slider.horizontal.3")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          Text("高级系统设置")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary.opacity(0.88))
          Spacer(minLength: 8)
          Text("代理 · 元数据 · 性能")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text("配置网络代理、DoH、TheMovieDB 域名、并发线程、图片缓存与日志级别。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button {
          onNavigate(.settings)
        } label: {
          Text("进入高级系统设置")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(
              colorScheme == .light ? .white : Color(red: 0.12, green: 0.10, blue: 0.16)
            )
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
              colorScheme == .light ? appearance.accentColor : .white.opacity(0.92), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-workspace-settings")
      }
    }
  }

  /// 第四层：4 列紧凑玻璃图标瓷砖（高频捷径与诊断：系统检查、网络测试、识别规则、实时日志）。
  private var appPreferenceTiles: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("捷径与诊断")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      HStack(spacing: 10) {
        compactTile(
          title: "系统检查", symbol: "checkmark.shield",
          id: "native-settings-hub-health"
        ) {
          onNavigate(.diagnostics(.health))
        }
        compactTile(
          title: "网络测试", symbol: "network",
          id: "native-settings-hub-nettest"
        ) {
          onNavigate(.diagnostics(.nettest))
        }
        compactTile(
          title: "识别规则", symbol: "text.magnifyingglass",
          id: "native-settings-hub-ruletest"
        ) {
          onNavigate(.diagnostics(.ruleTest))
        }
        compactTile(
          title: "实时日志", symbol: "terminal",
          id: "native-settings-hub-livelog"
        ) {
          onNavigate(.diagnostics(.liveLog))
        }
      }
    }
  }

  /// 第五层：2×2 横向紧凑玻璃胶囊卡（常用配置与快捷服务：站点范围、定时服务、下载媒体、通知渠道）。
  private var quickConfigPillsGrid: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("常用配置")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
      VStack(spacing: 10) {
        HStack(spacing: 10) {
          horizontalConfigPill(
            title: "站点范围", subtitle: "搜索 / 订阅站点", symbol: "checklist",
            tint: Color(red: 0.42, green: 0.78, blue: 1.0),
            id: "native-settings-hub-site-scope"
          ) {
            onNavigate(.systemModule(.siteScope))
          }
          horizontalConfigPill(
            title: "定时服务", subtitle: "手动触发任务", symbol: "clock.arrow.2.circlepath",
            tint: Color(red: 0.96, green: 0.68, blue: 0.36),
            id: "native-settings-hub-scheduler"
          ) {
            onNavigate(.diagnostics(.scheduler))
          }
        }
        HStack(spacing: 10) {
          horizontalConfigPill(
            title: "下载媒体", subtitle: "下载器与媒体库", symbol: "server.rack",
            tint: Color(red: 0.74, green: 0.54, blue: 0.98),
            id: "native-settings-hub-services"
          ) {
            onNavigate(.systemModule(.services))
          }
          horizontalConfigPill(
            title: "通知渠道", subtitle: "消息与推送配置", symbol: "bell.badge",
            tint: Color(red: 0.44, green: 0.88, blue: 0.66),
            id: "native-settings-hub-notifications"
          ) {
            onNavigate(.systemModule(.notifications))
          }
        }
      }
    }
  }

  /// 横向紧凑玻璃配置卡（与双列方卡、4 列图标瓷砖、原生列表形成清晰视觉节奏对比）。
  private func horizontalConfigPill(
    title: String,
    subtitle: String,
    symbol: String,
    tint: Color,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      CinematicPanel(padding: 12) {
        HStack(spacing: 10) {
          Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(
              tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.primary.opacity(0.88))
              .lineLimit(1)
            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 分组一：目录映射、规则识别与媒体刮削设置。
  private var mediaDirectorySection: some View {
    CinematicFormSection("目录与刮削") {
      nativeListRow(
        title: "目录与存储映射", symbol: "folder.badge.gearshape",
        id: "native-settings-hub-directories"
      ) {
        onNavigate(.systemModule(.directories))
      }
      CinematicFormDivider()
      nativeListRow(
        title: "规则与识别词", symbol: "line.3.horizontal.decrease.circle",
        id: "native-settings-hub-rules"
      ) {
        onNavigate(.systemModule(.rules))
      }
      CinematicFormDivider()
      nativeListRow(
        title: "刮削开关", symbol: "wand.and.stars",
        id: "native-settings-hub-scraping"
      ) {
        onNavigate(.systemModule(.scraping))
      }
    }
  }

  /// 分组二：界面外观、插件市场源配置、已安装插件配置与浮动智能助手开关。
  private var appearanceAndPluginsSection: some View {
    CinematicFormSection(
      "界面与插件",
      footer: "完整插件市场浏览可从底部弹出菜单的「插件」进入。"
    ) {
      nativeListRow(
        title: "主题与外观", subtitle: appearance.summaryText, symbol: "paintpalette.fill",
        id: "native-settings-hub-appearance"
      ) {
        onNavigate(.appearance)
      }
      CinematicFormDivider()
      nativeListRow(
        title: "插件市场", subtitle: "数据源与同步", symbol: "puzzlepiece.extension",
        id: "native-settings-hub-plugin-market-sources"
      ) {
        showsPluginMarketSources = true
      }
      CinematicFormDivider()
      nativeListRow(
        title: "已安装插件配置", symbol: "slider.horizontal.3",
        id: "native-settings-hub-plugins"
      ) {
        onOpenPlugins()
      }
      CinematicFormDivider()
      floatingAssistantToggleRow
    }
  }

  /// 普通成员外观与浮动智能助手设置分组。
  private var systemIntegrationSection: some View {
    CinematicFormSection("界面与偏好") {
      nativeListRow(
        title: "主题与外观", subtitle: appearance.summaryText, symbol: "paintpalette.fill",
        id: "native-settings-hub-appearance"
      ) {
        onNavigate(.appearance)
      }
      CinematicFormDivider()
      floatingAssistantToggleRow
    }
  }

  /// 带标准内边距的浮动智能助手开关行。
  private var floatingAssistantToggleRow: some View {
    Toggle(isOn: $showFloatingAssistant) {
      HStack(spacing: 12) {
        Image(systemName: "sparkles")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
          .frame(width: 22)
        Text("浮动智能助手")
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.86))
      }
    }
    .tint(appearance.accentColor)
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
    .frame(minHeight: 46)
    .accessibilityIdentifier("native-settings-hub-floating-assistant")
  }

  /// 普通成员可见的精简入口。
  private var standardUserGrid: some View {
    HStack(spacing: 12) {
      squareStatusCard(
        title: "主题与外观",
        statusText: appearance.summaryText,
        symbol: "paintpalette.fill",
        tint: appearance.accentColor,
        statusColor: Color(red: 0.48, green: 0.90, blue: 0.66),
        id: "native-settings-hub-appearance-card"
      ) {
        onNavigate(.appearance)
      }
      squareStatusCard(
        title: "消息中心",
        statusText: "查看通知与互动",
        symbol: "bell.fill",
        tint: Color(red: 0.92, green: 0.54, blue: 0.72),
        statusColor: Color(red: 0.84, green: 0.72, blue: 1.0),
        id: "native-workspace-messages"
      ) {
        onNavigate(.messages)
      }
    }
  }

  /// 双列大图标状态方卡。
  private func squareStatusCard(
    title: String,
    statusText: String,
    symbol: String,
    tint: Color,
    statusColor: Color,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      CinematicPanel(padding: 15) {
        VStack(alignment: .leading, spacing: 12) {
          Image(systemName: symbol)
            .font(.title2.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(
              tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          Spacer(minLength: 4)
          VStack(alignment: .leading, spacing: 3) {
            Text(title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary.opacity(0.88))
              .lineLimit(1)
            HStack(spacing: 5) {
              Circle().fill(statusColor.opacity(0.85)).frame(width: 5.5, height: 5.5)
              Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 4 列紧凑正方形图标瓷砖。
  private func compactTile(
    title: String, symbol: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      CinematicPanel(padding: 10) {
        VStack(spacing: 7) {
          Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary.opacity(0.82))
            .frame(height: 24)
          Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 原生 Form 分组列表行，带图标、可选状态副标题与右侧指示箭头。
  private func nativeListRow(
    title: String,
    subtitle: String? = nil,
    symbol: String,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
          .frame(width: 22)
        Text(title)
          .font(.subheadline)
          .foregroundStyle(.primary.opacity(0.86))
        Spacer(minLength: 8)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary.opacity(0.65))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 11)
      .frame(minHeight: 46)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 顶部容量条图例点。
  private func legendDot(_ title: String, color: Color) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(title)
        .font(.caption2)
        .foregroundStyle(.primary.opacity(0.68))
        .lineLimit(1)
    }
  }

  /// 静默拉取存储空间与站点数量供顶部概览与状态方卡展示；命中缓存时静默复用，下拉刷新强制重拉。
  private func loadOverview(forceRefresh: Bool = false) async {
    guard snapshot.user.isSuperuser else { return }
    let cacheKey = "settingsHub|overview"
    if !forceRefresh,
      let cached: (storage: NativeSettingsStorageBrief?, siteCount: Int?) =
        NativePageDataCache.shared.get(cacheKey, session: session)
    {
      if let cachedStorage = cached.storage { storage = cachedStorage }
      if let cachedCount = cached.siteCount { siteCount = cachedCount }
      return
    }
    async let storageResult: NativeSettingsStorageBrief? = {
      guard let endpoint = try? APIEndpoint(path: ["dashboard", "storage"]) else { return nil }
      return try? await session.request(
        endpoint, as: NativeSettingsStorageBrief.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    }()
    async let sitesResult: [NativeSettingsSiteBrief]? = {
      guard let endpoint = try? APIEndpoint(path: ["site"], trailingSlash: true) else { return nil }
      return try? await session.request(
        endpoint, as: [NativeSettingsSiteBrief].self,
        requiring: PermissionRequirement(category: .admin)
      ).value
    }()
    let (loadedStorage, loadedSites) = await (storageResult, sitesResult)
    guard !Task.isCancelled else { return }
    if let loadedStorage, loadedStorage.total > 0 {
      storage = loadedStorage
    }
    if let loadedSites {
      siteCount = loadedSites.filter(\.isActive).count
    }
    NativePageDataCache.shared.set(
      (storage: storage, siteCount: siteCount), for: cacheKey, session: session)
  }

  /// 格式化字节容量为易读文本。
  private static func formatBytes(_ bytes: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useGB, .useTB, .useMB]
    return formatter.string(fromByteCount: Int64(max(0, bytes)))
  }
}

/// 设置顶部存储概览解码模型。
private struct NativeSettingsStorageBrief: Decodable, Sendable {
  let total: Double
  let used: Double

  /// 已用空间比例。
  var usedRatio: Double {
    guard total > 0 else { return 0 }
    return min(max(used / total, 0), 1)
  }

  enum CodingKeys: String, CodingKey {
    case total = "total_storage"
    case used = "used_storage"
  }
}

/// 站点活跃数量轻量化解码模型。
private struct NativeSettingsSiteBrief: Decodable, Sendable {
  let isActive: Bool

  enum CodingKeys: String, CodingKey {
    case isActive = "is_active"
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isActive = (try? container.decode(Bool.self, forKey: .isActive)) ?? true
  }
}

/// 插件市场数据源配置与 Wiki 同步弹层：直连 `GET/POST /api/v1/system/setting/PLUGIN_MARKET` 与 `POST /api/v1/system/setting/PLUGIN_MARKET/sync-wiki`。
@MainActor
private struct NativePluginMarketSourcesSheet: View {
  let session: NativeSession

  @State private var repos: [String] = []
  @State private var originalRepos: [String] = []
  @State private var newRepoURL = ""
  @State private var isLoading = true
  @State private var isSaving = false
  @State private var isSyncing = false
  @State private var feedback: (isError: Bool, text: String)?
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  private var isDirty: Bool { repos != originalRepos }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let feedback {
              CinematicPanel(padding: 11) {
                HStack(spacing: 8) {
                  Image(
                    systemName: feedback.isError
                      ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                  )
                  .foregroundStyle(
                    feedback.isError ? .orange : Color(red: 0.46, green: 0.88, blue: 0.64))
                  Text(feedback.text)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.90))
                  Spacer(minLength: 0)
                }
              }
            }

            // 同步官方 Wiki 插件源
            CinematicPanel(padding: 14) {
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                  Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.body)
                    .foregroundStyle(appearance.accentColor)
                  Text("同步官方插件源")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.90))
                  Spacer()
                }
                Text("从 MoviePilot Wiki 插件目录自动合并社区插件仓库地址。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Button {
                  Task { await syncFromWiki() }
                } label: {
                  HStack(spacing: 7) {
                    if isSyncing {
                      ProgressView().controlSize(.small).tint(.white)
                    } else {
                      Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                    }
                    Text(isSyncing ? "正在同步插件源…" : "从 Wiki 同步插件源")
                      .font(.subheadline.weight(.semibold))
                  }
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, minHeight: 42)
                  .background(appearance.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSyncing || isSaving)
                .accessibilityIdentifier("native-plugin-market-sync-wiki")
              }
            }

            // 添加自定义插件仓库地址
            VStack(alignment: .leading, spacing: 8) {
              Text("添加插件源地址")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
              CinematicPanel(padding: 12) {
                HStack(spacing: 10) {
                  TextField(
                    "https://github.com/owner/repo",
                    text: $newRepoURL,
                    prompt: Text("https://github.com/owner/repo").foregroundColor(.secondary)
                  )
                  .font(.subheadline)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .keyboardType(.URL)
                  .submitLabel(.done)
                  .onSubmit { appendNewRepo() }
                  Button("添加") { appendNewRepo() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appearance.accentColor)
                    .disabled(newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
              }
            }

            // 已配置的插件源列表
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("已配置数据源")
                  .font(.footnote.weight(.medium))
                  .foregroundStyle(.secondary)
                Spacer()
                Text("\(repos.count) 个仓库")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 4)

              if isLoading && repos.isEmpty {
                ProgressView()
                  .tint(.primary)
                  .frame(maxWidth: .infinity, minHeight: 120)
              } else if repos.isEmpty {
                CinematicPanel(padding: 16) {
                  Text("暂无插件市场数据源，可点击上方同步 Wiki 或手动添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              } else {
                CinematicPanel(padding: 0) {
                  VStack(spacing: 0) {
                    ForEach(Array(repos.enumerated()), id: \.offset) { idx, repo in
                      if idx > 0 { CinematicFormDivider() }
                      HStack(spacing: 10) {
                        Image(systemName: "link")
                          .font(.caption)
                          .foregroundStyle(.secondary)
                        Text(repo)
                          .font(.caption.monospaced())
                          .foregroundStyle(.primary.opacity(0.86))
                          .lineLimit(2)
                          .frame(maxWidth: .infinity, alignment: .leading)
                      }
                      .padding(.horizontal, 14)
                      .padding(.vertical, 11)
                      .contentShape(Rectangle())
                      .contextMenu {
                        Button(role: .destructive) {
                          repos.remove(at: idx)
                        } label: {
                          Label("移除此数据源", systemImage: "trash")
                        }
                      }
                    }
                  }
                }
                Text("长按任意数据源行可将其移除，修改后点击右上角「保存」生效。")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 4)
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("插件市场数据源")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await saveRepos() }
          } label: {
            if isSaving {
              ProgressView().controlSize(.small).tint(.primary)
            } else {
              Text("保存").fontWeight(.semibold)
            }
          }
          .disabled(!isDirty || isSaving || isSyncing)
          .accessibilityIdentifier("native-plugin-market-sources-save")
        }
      }
      .task { await loadRepos() }
    }
    .nativeAppearanceRoot()
  }

  private func appendNewRepo() {
    let trimmed = newRepoURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if !repos.contains(trimmed) {
      repos.append(trimmed)
    }
    newRepoURL = ""
  }

  private static func parseRepoString(_ raw: String) -> [String] {
    var seen: Set<String> = []
    return
      raw
      .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "，" })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  private func loadRepos() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let ep = try APIEndpoint(path: ["system", "setting", "public", "PLUGIN_MARKET"])
      let payload = try await session.request(
        ep, as: NativePluginMarketSettingValue.self
      ).value
      let parsed = Self.parseRepoString(payload.value ?? "")
      repos = parsed
      originalRepos = parsed
    } catch {
      feedback = (true, "读取插件市场数据源失败，请稍后重试。")
    }
  }

  private func saveRepos() async {
    isSaving = true
    feedback = nil
    defer { isSaving = false }
    do {
      let joined = repos.joined(separator: ",")
      let body = try JSONEncoder().encode(joined)
      let ep = try APIEndpoint(
        path: ["system", "setting", "PLUGIN_MARKET"], method: .post, body: body)
      try await session.perform(ep, requiring: PermissionRequirement(category: .admin))
      originalRepos = repos
      feedback = (false, "已保存 \(repos.count) 个插件市场数据源。")
    } catch {
      feedback = (true, "保存插件市场数据源失败，请检查地址格式或权限。")
    }
  }

  private func syncFromWiki() async {
    isSyncing = true
    feedback = nil
    defer { isSyncing = false }
    do {
      let ep = try APIEndpoint(
        path: ["system", "setting", "PLUGIN_MARKET", "sync-wiki"],
        method: .post,
        body: Data("{}".utf8),
        timeout: 45)
      let reply = try await session.request(
        ep, as: NativePluginMarketWikiSyncResult.self,
        requiring: PermissionRequirement(category: .admin)
      ).value
      let updated: [String] =
        if let list = reply.repos, !list.isEmpty {
          list
        } else {
          Self.parseRepoString(reply.value ?? "")
        }
      if !updated.isEmpty {
        repos = updated
        originalRepos = updated
      }
      let added = reply.addedCount ?? 0
      feedback = (
        false,
        added > 0
          ? "已从 Wiki 同步，新增 \(added) 个插件源（共 \(repos.count) 个）。"
          : "已完成 Wiki 同步，当前共 \(repos.count) 个插件源均为最新。"
      )
    } catch {
      feedback = (true, "从 Wiki 同步插件源失败，请检查网络或代理设置。")
    }
  }
}

private struct NativePluginMarketSettingValue: Decodable, Sendable {
  let value: String?
}

private struct NativePluginMarketWikiSyncResult: Decodable, Sendable {
  let addedCount: Int?
  let totalCount: Int?
  let repos: [String]?
  let value: String?

  private enum CodingKeys: String, CodingKey {
    case addedCount = "added_count"
    case totalCount = "total_count"
    case repos, value
  }
}
