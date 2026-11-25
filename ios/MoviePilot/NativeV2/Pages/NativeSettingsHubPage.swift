import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 原生设置主中心（底部「设置」标签）：围绕主链路与移动端高频需求精简重组，全部采用 ScrollView + iOS 原生分组列表卡片，彻底消除阴影裁切，右上角无任何多余按钮。
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
  @State private var userCount: Int?
  @State private var pendingAuthCount: Int = 0
  @State private var approvedAuthCount: Int = 0
  @State private var downloaderCount: Int?
  @State private var mediaServerCount: Int?
  @State private var isOverviewLoading: Bool
  @State private var cacheBytes: Int64 = 0
  @State private var showsNotificationSettings = false
  @State private var showsWidgetSettings = false
  @State private var showsClearCacheConfirm = false
  @State private var showsLogoutConfirm = false
  @State private var cacheClearedNotice = false
  @AppStorage("nativeV2.showFloatingAssistant") private var showFloatingAssistant = true
  @AppStorage("nativeV2.playback.aspectFill") private var playbackAspectFill = false
  @AppStorage("nativeV2.playback.defaultRate") private var playbackDefaultRate = 1.0
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  init(
    session: NativeSession,
    snapshot: NativeSessionSnapshot,
    currentLanguage: AppLanguage,
    onNavigate: @escaping (NativeWorkspaceDestination) -> Void,
    onOpenModules: @escaping () -> Void,
    onOpenPlugins: @escaping () -> Void,
    onSelectLanguage: @escaping (AppLanguage) -> Void,
    onSwitchServer: @escaping () -> Void,
    onLogout: @escaping () -> Void
  ) {
    self.session = session
    self.snapshot = snapshot
    self.currentLanguage = currentLanguage
    self.onNavigate = onNavigate
    self.onOpenModules = onOpenModules
    self.onOpenPlugins = onOpenPlugins
    self.onSelectLanguage = onSelectLanguage
    self.onSwitchServer = onSwitchServer
    self.onLogout = onLogout
    if snapshot.user.isSuperuser,
      let cached: NativeSettingsHubOverviewCache = NativePageDataCache.shared.get(
        "settingsHub|overview.v2", session: session)
    {
      _storage = State(initialValue: cached.storage)
      _siteCount = State(initialValue: cached.siteCount)
      _userCount = State(initialValue: cached.userCount)
      _pendingAuthCount = State(initialValue: cached.pendingAuthCount)
      _approvedAuthCount = State(initialValue: cached.approvedAuthCount)
      _downloaderCount = State(initialValue: cached.downloaderCount)
      _mediaServerCount = State(initialValue: cached.mediaServerCount)
      _isOverviewLoading = State(initialValue: false)
    } else {
      _isOverviewLoading = State(initialValue: snapshot.user.isSuperuser)
    }
  }

  private func t(_ key: String) -> String {
    L10n.text(key, language: currentLanguage)
  }

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if snapshot.user.isSuperuser {
            if let storage, storage.total > 0 {
              storageTelemetryCard(storage)
            } else if isOverviewLoading && storage == nil {
              storageTelemetrySkeletonCard
            }
            adminTopStatusGrid
            coreWorkflowSection
          } else {
            memberTopAuthCard
            memberPlaybackSection
          }

          notificationAndAssistantSection
          appearanceAndDeviceSection
          accountAndServerSection
          appVersionFooter
        }
        .frame(maxWidth: NativeDeviceLayout.isIPad ? 840 : 740, alignment: .leading)
        .padding(.horizontal, NativeDeviceLayout.isIPad ? 24 : CinematicStyle.margin)
        .padding(.top, 14)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await loadOverview(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-settings-scroll")
    }
    .navigationTitle(t("设置"))
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .sheet(isPresented: $showsNotificationSettings) {
      NativeNotificationSettingsSheet(session: session)
        .nativeAdaptiveSheetSizing()
    }
    .sheet(isPresented: $showsWidgetSettings) {
      NativeWidgetSettingsSheet(session: session)
        .nativeAdaptiveSheetSizing()
    }
    .alert(t("清理本地缓存"), isPresented: $showsClearCacheConfirm) {
      Button(t("清理"), role: .destructive) {
        NativeMediaArtworkCache.shared.clearSession(session)
        NativePageDataCache.shared.clearAll()
        NativeMediaLibraryStatusStore.shared.clearAll()
        cacheBytes = 0
        cacheClearedNotice = true
      }
      Button(t("取消"), role: .cancel) {}
    } message: {
      Text(t("将清空本机已缓存的海报图片与页面快照，不会影响服务器数据。"))
    }
    .alert(t("退出登录"), isPresented: $showsLogoutConfirm) {
      Button(t("退出登录"), role: .destructive) { onLogout() }
      Button(t("取消"), role: .cancel) {}
    } message: {
      Text(t("退出后需要重新输入账号密码或凭据登录当前 MoviePilot 服务。"))
    }
    .task(id: snapshot.scope) {
      await loadOverview(forceRefresh: false)
    }
    .onAppear {
      Task {
        cacheBytes = await NativeMediaArtworkCache.shared.diskCacheSizeBytes(for: session)
      }
    }
  }

  // MARK: - 1. 顶部概览与快捷状态卡

  /// 概览加载期间预留与 `storageTelemetryCard` 完全等高（~96pt）的存储卡片占位骨架，防止设置页首帧下沉跳动。
  private var storageTelemetrySkeletonCard: some View {
    let host = session.instance.address.url.host ?? session.instance.address.url.absoluteString
    return CinematicPanel(padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Circle()
            .fill(NativeTheme.success)
            .frame(width: 7, height: 7)
          Text(host)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 8)
          NativeSkeletonBlock(width: 108, height: 13, cornerRadius: 5)
        }
        NativeSkeletonBlock(height: 8, cornerRadius: 4)
        HStack {
          NativeSkeletonBlock(width: 76, height: 12, cornerRadius: 5)
          Spacer()
          NativeSkeletonBlock(width: 86, height: 12, cornerRadius: 5)
        }
      }
      .frame(minHeight: 64)
    }
    .nativeSkeletonShimmer()
  }

  private func storageTelemetryCard(_ storage: NativeSettingsStorageBrief) -> some View {
    let host = session.instance.address.url.host ?? session.instance.address.url.absoluteString
    let ratio = storage.usedRatio
    let percentText = "\(Int((ratio * 100).rounded()))%"
    let freeBytes = max(storage.total - storage.used, 0)
    return CinematicPanel(padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Circle()
            .fill(NativeTheme.success)
            .frame(width: 7, height: 7)
          Text(host)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 8)
          Text("\(Self.formatBytes(storage.used)) / \(Self.formatBytes(storage.total))")
            .font(.footnote.monospacedDigit().weight(.medium))
            .foregroundStyle(.primary.opacity(0.88))
        }
        GeometryReader { bar in
          let w = max(bar.size.width, 1)
          let usedW = max(w * min(max(ratio, 0.04), 1.0), 8)
          ZStack(alignment: .leading) {
            Capsule().fill(NativeTheme.chipFill)
            Capsule()
              .fill(
                LinearGradient(
                  colors: [appearance.accentColor, NativeTheme.pink],
                  startPoint: .leading, endPoint: .trailing)
              )
              .frame(width: usedW)
          }
        }
        .frame(height: 8)
        HStack {
          HStack(spacing: 5) {
            Circle().fill(appearance.accentColor).frame(width: 6.5, height: 6.5)
            Text("\(t("已用")) \(percentText)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(t("可用")) \(Self.formatBytes(freeBytes))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  /// 第二行 3 列舒朗状态卡：站点管理、用户管理、渠道授权。
  private var adminTopStatusGrid: some View {
    HStack(spacing: 12) {
      compactStatusCard(
        title: t("站点管理"),
        statusText: siteCount.map { "\($0) \(t("启用"))" } ?? t("索引与流量"),
        symbol: "globe",
        statusTint: NativeTheme.success,
        id: "native-workspace-sites"
      ) { onNavigate(.sites) }

      compactStatusCard(
        title: t("用户管理"),
        statusText: userCount.map { "\($0) \(t("位成员"))" } ?? t("权限角色"),
        symbol: "person.2",
        statusTint: NativeTheme.brand,
        id: "native-workspace-users"
      ) { onNavigate(.users) }

      compactStatusCard(
        title: t("渠道授权"),
        statusText: pendingAuthCount > 0
          ? "\(pendingAuthCount) \(t("待审批"))" : "\(t("已授")) \(approvedAuthCount)",
        symbol: "person.badge.key",
        statusTint: pendingAuthCount > 0 ? NativeTheme.warning : NativeTheme.success,
        id: "native-workspace-channel-auth"
      ) { onNavigate(.channelAuth) }
    }
  }

  private func compactStatusCard(
    title: String,
    statusText: String,
    symbol: String,
    statusTint: Color,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 12) {
          Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 26, height: 26, alignment: .leading)
          VStack(alignment: .leading, spacing: 4) {
            Text(title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
            HStack(spacing: 4) {
              Circle().fill(statusTint).frame(width: 5.5, height: 5.5)
              Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            }
          }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  private var memberTopAuthCard: some View {
    Button {
      onNavigate(.channelAuth)
    } label: {
      CinematicPanel(padding: 16) {
        HStack(spacing: 14) {
          iconBadge("person.badge.key.fill")
          VStack(alignment: .leading, spacing: 3) {
            Text(t("渠道授权与绑定"))
              .font(.body.weight(.semibold))
              .foregroundStyle(.primary)
            Text(t("生成 5 分钟渠道关联绑定码"))
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.55))
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-workspace-channel-auth")
  }

  // MARK: - 2. 分组一：基础

  private var coreWorkflowSection: some View {
    let unit = t("个")
    let countFmt: (Int) -> String = { count in
      unit.isEmpty ? "\(count)" : "\(count) \(unit)"
    }
    return settingsGroup(t("基础"), footer: t("底层代理、并发与高级系统参数请在 Web 管理台配置。")) {
      navRow(
        title: t("订阅与搜索"), subtitle: t("站点范围 · 规则组"), symbol: "magnifyingglass.circle",
        id: "native-settings-subscribe-search"
      ) { onNavigate(.subscribeSearchSettings) }
      settingsRowDivider
      navRow(
        title: t("媒体数据源"), subtitle: t("搜索与元数据来源"), symbol: "globe.asia.australia",
        id: "native-settings-media-sources"
      ) { onNavigate(.mediaSourceSettings) }
      settingsRowDivider
      navRow(
        title: t("下载器"), subtitle: downloaderCount.map(countFmt) ?? t("新增与管理"),
        symbol: "arrow.down.circle",
        id: "native-settings-downloaders"
      ) { onNavigate(.downloadersManage) }
      settingsRowDivider
      navRow(
        title: t("媒体服务器"), subtitle: mediaServerCount.map(countFmt) ?? t("新增与管理"),
        symbol: "server.rack",
        id: "native-settings-mediaservers"
      ) { onNavigate(.mediaServersManage) }
      settingsRowDivider
      navRow(
        title: t("整理与目录"), subtitle: t("目录映射与刮削"), symbol: "folder.badge.gearshape",
        id: "native-settings-hub-directories"
      ) { onNavigate(.systemModule(.directories)) }
      settingsRowDivider
      navRow(
        title: t("播放偏好"), subtitle: playbackSummaryText, symbol: "play.rectangle",
        id: "native-settings-playback"
      ) { onNavigate(.playbackSettings) }
    }
  }

  private var memberPlaybackSection: some View {
    settingsGroup(t("播放")) {
      navRow(
        title: t("播放偏好"), subtitle: playbackSummaryText, symbol: "play.rectangle",
        id: "native-settings-playback"
      ) { onNavigate(.playbackSettings) }
    }
  }

  private var playbackSummaryText: String {
    let fill = playbackAspectFill ? t("铺满") : t("自适应")
    let rate = playbackDefaultRate == 1.0 ? "1.0x" : String(format: "%.2gx", playbackDefaultRate)
    return "\(fill) · \(rate)"
  }

  // MARK: - 3. 分组二：通知与智能

  private var notificationAndAssistantSection: some View {
    settingsGroup(t("通知与智能")) {
      navRow(
        title: t("本机推送通知"), subtitle: t("APNs 提醒"), symbol: "bell.and.waves.left.and.right",
        id: "native-settings-hub-push"
      ) { showsNotificationSettings = true }
      if snapshot.user.isSuperuser {
        settingsRowDivider
        navRow(
          title: t("服务端通知渠道"), subtitle: t("消息推送配置"), symbol: "bell.badge",
          id: "native-settings-hub-notifications"
        ) { onNavigate(.systemModule(.notifications)) }
      }
      settingsRowDivider
      HStack(spacing: 14) {
        iconBadge("text.bubble")
        Text(t("悬浮智能助手"))
          .font(.body)
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        Toggle("", isOn: $showFloatingAssistant)
          .labelsHidden()
          .tint(appearance.accentColor)
          .frame(minHeight: 44)
          .accessibilityLabel(t("悬浮智能助手"))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 56)
      .accessibilityIdentifier("native-settings-hub-floating-assistant")
    }
  }

  // MARK: - 4. 分组三：外观与本机

  private var appearanceAndDeviceSection: some View {
    settingsGroup(t("外观与本机")) {
      navRow(
        title: t("主题与外观"), subtitle: appearance.summaryText, symbol: "paintpalette",
        id: "native-settings-hub-appearance"
      ) { onNavigate(.appearance) }
      settingsRowDivider
      navRow(
        title: t("桌面小组件"), subtitle: t("实例与刷新"), symbol: "rectangle.3.group",
        id: "native-settings-hub-widgets"
      ) { showsWidgetSettings = true }
      settingsRowDivider
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
        HStack(spacing: 14) {
          iconBadge("globe")
          Text(t("界面语言"))
            .font(.body)
            .foregroundStyle(.primary)
          Spacer(minLength: 8)
          Text(currentLanguage.title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary.opacity(0.65))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-v2-language")
      settingsRowDivider
      navRow(
        title: t("本地缓存清理"),
        subtitle: cacheClearedNotice ? t("已清理") : Self.formatBytes(Double(cacheBytes)),
        symbol: "internaldrive",
        id: "native-settings-clear-cache"
      ) { showsClearCacheConfirm = true }
    }
  }

  // MARK: - 5. 分组四：服务与账号

  private var accountAndServerSection: some View {
    let host = session.instance.address.url.host ?? session.instance.address.url.absoluteString
    return settingsGroup(t("服务与账号")) {
      navRow(
        title: t("切换服务"), subtitle: host, symbol: "arrow.left.arrow.right.circle",
        id: "native-v2-switch"
      ) { onSwitchServer() }
      settingsRowDivider
      Button {
        showsLogoutConfirm = true
      } label: {
        HStack(spacing: 14) {
          iconBadge("rectangle.portrait.and.arrow.right", foreground: NativeTheme.danger)
          Text(t("退出登录"))
            .font(.body.weight(.medium))
            .foregroundStyle(NativeTheme.danger)
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-v2-logout")
    }
  }

  /// 设置页底部展示当前原生 App 版本号（兼容 iPhone / iPad / iPhone Duo 三端居中留白）。
  private var appVersionFooter: some View {
    let shortVersion =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let buildNumber =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let versionText: String = {
      guard !shortVersion.isEmpty else { return "MoviePilot" }
      if !buildNumber.isEmpty && buildNumber != shortVersion {
        return "MoviePilot v\(shortVersion) (\(buildNumber))"
      }
      return "MoviePilot v\(shortVersion)"
    }()
    return Text(versionText)
      .font(.footnote.monospacedDigit())
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.top, 4)
      .accessibilityIdentifier("native-settings-app-version")
  }

  // MARK: - 原生舒朗分组列表基础组件

  private func settingsGroup<Content: View>(
    _ title: String,
    footer: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) { content() }
      }
      if let footer, !footer.isEmpty {
        Text(footer)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.top, 2)
      }
    }
  }

  private var settingsRowDivider: some View {
    Divider()
      .overlay(NativeTheme.divider)
      .padding(.leading, 54)
  }

  private func iconBadge(_ symbol: String, foreground: Color = .primary) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 18, weight: .medium))
      .foregroundStyle(foreground)
      .frame(width: 24, height: 24)
  }

  private func navRow(
    title: String,
    subtitle: String? = nil,
    symbol: String,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        iconBadge(symbol)
        Text(title)
          .font(.body)
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary.opacity(0.55))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(minHeight: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  // MARK: - 概览数据加载

  private func loadOverview(forceRefresh: Bool = false) async {
    cacheBytes = await NativeMediaArtworkCache.shared.diskCacheSizeBytes(for: session)
    guard snapshot.user.isSuperuser else {
      isOverviewLoading = false
      return
    }
    let cacheKey = "settingsHub|overview.v2"
    if !forceRefresh,
      let cached: NativeSettingsHubOverviewCache = NativePageDataCache.shared.get(
        cacheKey, session: session)
    {
      storage = cached.storage
      siteCount = cached.siteCount
      userCount = cached.userCount
      pendingAuthCount = cached.pendingAuthCount
      approvedAuthCount = cached.approvedAuthCount
      downloaderCount = cached.downloaderCount
      mediaServerCount = cached.mediaServerCount
      isOverviewLoading = false
      return
    }
    if storage == nil {
      isOverviewLoading = true
    }
    defer { isOverviewLoading = false }
    async let storageTask: NativeSettingsStorageBrief? = {
      guard let ep = try? APIEndpoint(path: ["dashboard", "storage"]) else { return nil }
      return try? await session.request(
        ep, as: NativeSettingsStorageBrief.self, requiring: .init(category: .admin)
      ).value
    }()
    async let sitesTask: [NativeSettingsSiteBrief]? = {
      guard let ep = try? APIEndpoint(path: ["site"], trailingSlash: true) else { return nil }
      return try? await session.request(
        ep, as: [NativeSettingsSiteBrief].self, requiring: .init(category: .admin)
      ).value
    }()
    async let usersTask: [NativeSettingsIDBrief]? = {
      guard let ep = try? APIEndpoint(path: ["user"], trailingSlash: true) else { return nil }
      return try? await session.request(
        ep, as: [NativeSettingsIDBrief].self, requiring: .init(category: .admin)
      ).value
    }()
    async let authTask: NativeChannelAuthListData? = {
      guard let ep = try? APIEndpoint(path: ["authorization"], trailingSlash: true) else {
        return nil
      }
      return try? await session.request(
        ep, as: NativeChannelAuthListData.self, requiring: .init(category: .admin)
      ).value
    }()
    async let dlTask: [NativeDownloaderConf]? = {
      guard let ep = try? APIEndpoint(path: ["system", "setting", "Downloaders"]) else {
        return nil
      }
      return try? await session.request(
        ep, as: NativeSettingBox<[NativeDownloaderConf]>.self, requiring: .init(category: .admin)
      ).value.value
    }()
    async let msTask: [NativeMediaServerConf]? = {
      guard let ep = try? APIEndpoint(path: ["system", "setting", "MediaServers"]) else {
        return nil
      }
      return try? await session.request(
        ep, as: NativeSettingBox<[NativeMediaServerConf]>.self, requiring: .init(category: .admin)
      ).value.value
    }()

    let (s, sites, users, auth, dls, mss) = await (
      storageTask, sitesTask, usersTask, authTask, dlTask, msTask
    )
    guard !Task.isCancelled else { return }
    if let s, s.total > 0 { storage = s }
    if let sites { siteCount = sites.filter(\.isActive).count }
    if let users { userCount = users.count }
    if let auth {
      pendingAuthCount = auth.members.filter { $0.status == "pending" }.count
      approvedAuthCount = auth.members.filter { $0.status == "approved" }.count
    }
    if let dls { downloaderCount = dls.count }
    if let mss { mediaServerCount = mss.count }

    NativePageDataCache.shared.set(
      NativeSettingsHubOverviewCache(
        storage: storage, siteCount: siteCount, userCount: userCount,
        pendingAuthCount: pendingAuthCount, approvedAuthCount: approvedAuthCount,
        downloaderCount: downloaderCount, mediaServerCount: mediaServerCount),
      for: cacheKey, session: session)
  }

  private static func formatBytes(_ bytes: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useGB, .useTB, .useMB, .useKB]
    return formatter.string(fromByteCount: Int64(max(0, bytes)))
  }
}

// MARK: - 1. 渠道授权页（五.1 对标 Web 渠道授权审批 + 普通用户绑定码）

@MainActor
struct NativeChannelAuthorizationPage: View {
  private enum Filter: String, CaseIterable, Identifiable {
    case pending = "待审批"
    case approved = "已授权"
    case disabled = "已停用"
    var id: String { rawValue }
  }

  let session: NativeSession
  let isSuperuser: Bool

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var members: [NativeChannelMember] = []
  @State private var channels: [NativeAuthChannel] = []
  @State private var filter: Filter = .pending
  @State private var isLoading = false
  @State private var bindingCode: String?
  @State private var bindingExpiresAt: Double?
  @State private var isGeneratingCode = false
  @State private var showsCreateSheet = false
  @State private var editingMember: NativeChannelMember?
  @State private var feedback: (isError: Bool, text: String)?

  var body: some View {
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
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text).font(.caption.weight(.medium))
                Spacer()
              }
            }
          }

          // 当前用户渠道绑定码卡片（所有登录用户可用）
          bindingCodeSection

          if isSuperuser {
            adminMembersSection
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { if isSuperuser { await loadAuthorizations() } }
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("渠道授权")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      if isSuperuser {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showsCreateSheet = true
          } label: {
            Image(systemName: "plus")
          }
          .tint(.primary)
          .disabled(channels.isEmpty)
          .accessibilityLabel("新增渠道授权")
          .accessibilityIdentifier("native-auth-add")
        }
      }
    }
    .sheet(isPresented: $showsCreateSheet) {
      NativeChannelAuthCreateSheet(session: session, channels: channels) { msg in
        feedback = (false, msg)
        Task { await loadAuthorizations() }
      }
    }
    .sheet(item: $editingMember) { member in
      NativeChannelAuthEditSheet(session: session, member: member) { msg in
        feedback = (false, msg)
        Task { await loadAuthorizations() }
      }
    }
    .task {
      if isSuperuser { await loadAuthorizations() }
    }
  }

  private var bindingCodeSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text("绑定个人消息渠道")
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
      CinematicPanel(padding: 15) {
        VStack(alignment: .leading, spacing: 10) {
          Text("在 Telegram、企业微信等机器人会话中发送绑定码，将渠道身份与当前 MoviePilot 账号安全关联。")
            .font(.caption)
            .foregroundStyle(.secondary)
          if let code = bindingCode {
            HStack(spacing: 10) {
              Text(code)
                .font(.title3.monospaced().weight(.bold))
                .foregroundStyle(appearance.accentColor)
                .textSelection(.enabled)
              Spacer()
              Button {
                UIPasteboard.general.string = code
                feedback = (false, "已复制绑定码，5 分钟内有效。")
              } label: {
                Label("复制", systemImage: "doc.on.doc")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 6)
                  .background(appearance.accentColor, in: Capsule())
              }
              .buttonStyle(.plain)
            }
            .padding(11)
            .background(
              NativeTheme.chipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          Button {
            Task { await generateBindingCode() }
          } label: {
            HStack(spacing: 7) {
              if isGeneratingCode {
                ProgressView().controlSize(.small).tint(.white)
              } else {
                Image(systemName: "key.fill").font(.caption.weight(.semibold))
              }
              Text(bindingCode == nil ? "生成 5 分钟绑定码" : "重新生成绑定码")
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(appearance.accentColor, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(isGeneratingCode)
        }
      }
    }
  }

  private var filteredMembers: [NativeChannelMember] {
    members.filter { m in
      switch filter {
      case .pending: m.status == "pending"
      case .approved: m.status == "approved"
      case .disabled: m.status == "disabled" || m.status == "rejected"
      }
    }
  }

  private var adminMembersSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 7) {
        ForEach(Filter.allCases) { option in
          let count = members.filter { m in
            switch option {
            case .pending: m.status == "pending"
            case .approved: m.status == "approved"
            case .disabled: m.status == "disabled" || m.status == "rejected"
            }
          }.count
          Button {
            filter = option
          } label: {
            NativeAdaptivePill(
              count > 0 ? "\(option.rawValue) \(count)" : option.rawValue,
              isSelected: filter == option
            )
          }
          .buttonStyle(.plain)
        }
        Spacer()
      }

      if isLoading && members.isEmpty {
        NativeCardListSkeletonView(count: 4, style: .groupedIconList)
          .transition(.opacity)
      } else if filteredMembers.isEmpty {
        CinematicPanel(padding: 16) {
          Text("当前分类下暂无渠道授权成员")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 68)
        }
      } else {
        CinematicPanel(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(filteredMembers.enumerated()), id: \.element.id) { idx, member in
              if idx > 0 { CinematicFormDivider() }
              Button {
                editingMember = member
              } label: {
                HStack(spacing: 13) {
                  NativeBrandIcon(
                    kind: .notification, type: member.channel, size: 38, cornerRadius: 10)
                  VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                      Text(member.displayName.isEmpty ? member.senderID : member.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                      NativeAdaptiveBadge(
                        member.role == "admin" ? "管理员" : "普通成员",
                        tint: member.role == "admin" ? NativeTheme.brand : NativeTheme.info)
                    }
                    Text("\(member.source) · \(member.senderID)")
                      .font(.caption.monospaced())
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                    if !member.scopes.isEmpty {
                      Text(member.scopes.map(Self.scopeTitle).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(NativeTheme.brand)
                    }
                  }
                  Spacer()
                  Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.55))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  private func loadAuthorizations() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let ep = try APIEndpoint(path: ["authorization"], trailingSlash: true)
      let data = try await session.request(
        ep, as: NativeChannelAuthListData.self, requiring: .init(category: .admin)
      ).value
      members = data.members
      channels = data.channels
      if filter == .pending && !members.contains(where: { $0.status == "pending" }) {
        filter = .approved
      }
    } catch {
      feedback = (true, "读取渠道授权列表失败。")
    }
  }

  private func generateBindingCode() async {
    isGeneratingCode = true
    defer { isGeneratingCode = false }
    do {
      let ep = try APIEndpoint(path: ["authorization", "binding"], method: .post)
      let res = try await session.request(ep, as: NativeBindingCodeData.self).value
      bindingCode = res.code
      bindingExpiresAt = res.expiresAt
    } catch {
      feedback = (true, "生成绑定码失败，请稍后重试。")
    }
  }

  static func scopeTitle(_ scope: String) -> String {
    switch scope {
    case "search": "搜索"
    case "subscribe": "订阅"
    case "download": "下载"
    case "schedule": "定时任务"
    default: scope
    }
  }
}

@MainActor
private struct NativeChannelAuthCreateSheet: View {
  let session: NativeSession
  let channels: [NativeAuthChannel]
  let onSaved: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var notificationID = ""
  @State private var senderID = ""
  @State private var displayName = ""
  @State private var role = "member"
  @State private var scopes: Set<String> = ["search", "subscribe", "download"]
  @State private var isSubmitting = false
  @State private var errorMsg: String?

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let errorMsg {
              CinematicPanel(padding: 11) {
                Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption)
                  .foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            if !channels.isEmpty {
              VStack(alignment: .leading, spacing: 10) {
                Text("选择通知渠道")
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 6)
                NativeBrandOptionGrid(
                  kind: .notification,
                  items: channels.map {
                    NativeBrandChoiceItem(
                      id: $0.id, title: $0.name, subtitle: $0.type, iconType: $0.type)
                  },
                  selection: $notificationID,
                  columns: channels.count <= 2 ? 2 : 3
                )
              }
            }
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                inlineInputRow("发送者 ID", placeholder: "Telegram/企微用户 ID", text: $senderID)
                CinematicFormDivider()
                inlineInputRow("显示昵称", placeholder: "便于核对的昵称", text: $displayName)
                CinematicFormDivider()
                HStack {
                  Text("授权角色").font(.body)
                  Spacer()
                  Picker("角色", selection: $role) {
                    Text("普通成员").tag("member")
                    Text("管理员").tag("admin")
                  }
                  .pickerStyle(.segmented)
                  .frame(width: 176)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
              }
            }

            if role != "admin" {
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  ForEach(["search", "subscribe", "download", "schedule"], id: \.self) { scope in
                    if scope != "search" { CinematicFormDivider() }
                    Toggle(
                      NativeChannelAuthorizationPage.scopeTitle(scope),
                      isOn: Binding(
                        get: { scopes.contains(scope) },
                        set: { if $0 { scopes.insert(scope) } else { scopes.remove(scope) } }
                      )
                    )
                    .font(.subheadline)
                    .tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                  }
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
      }
      .navigationTitle("新增渠道授权")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("授权") { Task { await submit() } }
            .fontWeight(.semibold)
            .tint(.primary)
            .disabled(
              isSubmitting || notificationID.isEmpty
                || senderID.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear {
        if notificationID.isEmpty, let first = channels.first { notificationID = first.id }
      }
    }
    .nativeGlassSheet()
  }

  private func inlineInputRow(_ label: String, placeholder: String, text: Binding<String>)
    -> some View
  {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).frame(width: 84, alignment: .leading)
      TextField(placeholder, text: text)
        .font(.subheadline)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }

  private func submit() async {
    isSubmitting = true
    errorMsg = nil
    defer { isSubmitting = false }
    let effectiveScopes =
      role == "admin" ? ["search", "subscribe", "download", "schedule"] : Array(scopes).sorted()
    let payload: [String: JSONValue] = [
      "notification_id": .string(notificationID),
      "sender_id": .string(senderID.trimmingCharacters(in: .whitespacesAndNewlines)),
      "display_name": .string(displayName.trimmingCharacters(in: .whitespacesAndNewlines)),
      "status": .string("approved"),
      "role": .string(role),
      "scopes": .array(effectiveScopes.map(JSONValue.string)),
    ]
    do {
      let body = try JSONEncoder().encode(payload)
      let ep = try APIEndpoint(
        path: ["authorization"], method: .post, body: body, trailingSlash: true)
      try await session.perform(ep, requiring: .init(category: .admin))
      onSaved("已添加渠道授权。")
      dismiss()
    } catch {
      errorMsg = "添加渠道授权失败，请检查发送者 ID。"
    }
  }
}

@MainActor
private struct NativeChannelAuthEditSheet: View {
  let session: NativeSession
  let member: NativeChannelMember
  let onSaved: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var status: String
  @State private var role: String
  @State private var scopes: Set<String>
  @State private var isSubmitting = false
  @State private var showsAdminConfirm = false
  @State private var errorMsg: String?

  init(session: NativeSession, member: NativeChannelMember, onSaved: @escaping (String) -> Void) {
    self.session = session
    self.member = member
    self.onSaved = onSaved
    _status = State(initialValue: member.status == "pending" ? "approved" : member.status)
    _role = State(initialValue: member.role)
    _scopes = State(initialValue: Set(member.scopes))
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            if let errorMsg {
              CinematicPanel(padding: 11) {
                Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                  .font(.caption)
                  .foregroundStyle(NativeTheme.danger)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                infoRow("成员昵称", value: member.displayName.isEmpty ? "-" : member.displayName)
                CinematicFormDivider()
                infoRow("通知渠道", value: member.source)
                CinematicFormDivider()
                infoRow("发送者 ID", value: member.senderID)
                if let linked = member.linkedUsername, !linked.isEmpty {
                  CinematicFormDivider()
                  infoRow("已绑定账号", value: linked)
                }
              }
            }
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                HStack {
                  Text("审批状态").font(.subheadline)
                  Spacer()
                  Picker("状态", selection: $status) {
                    Text("批准/启用").tag("approved")
                    Text("停用").tag("disabled")
                    Text("拒绝").tag("rejected")
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                HStack {
                  Text("角色").font(.subheadline)
                  Spacer()
                  Picker("角色", selection: $role) {
                    Text("普通成员").tag("member")
                    Text("管理员").tag("admin")
                  }
                  .pickerStyle(.segmented)
                  .frame(width: 170)
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
              }
            }
            if role != "admin" {
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  ForEach(["search", "subscribe", "download", "schedule"], id: \.self) { scope in
                    if scope != "search" { CinematicFormDivider() }
                    Toggle(
                      NativeChannelAuthorizationPage.scopeTitle(scope),
                      isOn: Binding(
                        get: { scopes.contains(scope) },
                        set: { if $0 { scopes.insert(scope) } else { scopes.remove(scope) } }
                      )
                    )
                    .font(.subheadline)
                    .tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                  }
                }
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
      }
      .navigationTitle("审批与权限")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") {
            if role == "admin" && member.role != "admin" {
              showsAdminConfirm = true
            } else {
              Task { await submit() }
            }
          }
          .fontWeight(.semibold)
          .tint(.primary)
          .disabled(isSubmitting)
        }
      }
      .alert("确认授予管理员权限", isPresented: $showsAdminConfirm) {
        Button("确认授权", role: .destructive) { Task { await submit() } }
        Button("取消", role: .cancel) {}
      } message: {
        Text("授予管理员角色后，该渠道成员将拥有搜索、订阅、下载与定时任务的全部权限。")
      }
    }
    .nativeGlassSheet()
  }

  private func infoRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label).font(.subheadline).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(.subheadline.monospaced()).foregroundStyle(.primary).lineLimit(1)
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }

  private func submit() async {
    isSubmitting = true
    errorMsg = nil
    defer { isSubmitting = false }
    let effectiveScopes =
      role == "admin" ? ["search", "subscribe", "download", "schedule"] : Array(scopes).sorted()
    let payload: [String: JSONValue] = [
      "status": .string(status),
      "role": .string(role),
      "scopes": .array(effectiveScopes.map(JSONValue.string)),
    ]
    do {
      let body = try JSONEncoder().encode(payload)
      let ep = try APIEndpoint(path: ["authorization", member.id], method: .put, body: body)
      try await session.perform(ep, requiring: .init(category: .admin))
      onSaved("已更新渠道成员授权状态。")
      dismiss()
    } catch {
      errorMsg = "更新授权失败，请稍后重试。"
    }
  }
}

// MARK: - 2. 订阅与搜索设置页（站点范围 + 规则组 + 订阅模式）

@MainActor
struct NativeSubscribeSearchSettingsPage: View {
  let session: NativeSession

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var allSites: [NativeSimpleSiteOption] = []
  @State private var allRuleGroups: [String] = []
  @State private var rssSites: Set<Int> = []
  @State private var indexerSites: Set<Int> = []
  @State private var subscribeRuleGroups: Set<String> = []
  @State private var bestVersionRuleGroups: Set<String> = []
  @State private var searchRuleGroups: Set<String> = []
  @State private var subscribeMode = "auto"
  @State private var isLoading = true
  @State private var hasLoaded = false
  @State private var isSaving = false
  @State private var feedback: (isError: Bool, text: String)?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if let feedback {
            CinematicPanel(padding: 12) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text).font(.subheadline.weight(.medium))
                Spacer()
              }
            }
          }

          if isLoading {
            NativeCardListSkeletonView(count: 3, style: .formPanel)
              .transition(.opacity)
          } else {
            // 站点范围
            VStack(alignment: .leading, spacing: 10) {
              Text("站点范围").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  NavigationLink {
                    NativeSiteScopePickerView(
                      session: session, title: "订阅站点范围", sites: allSites, selection: $rssSites)
                  } label: {
                    pickerRow(
                      "订阅站点", value: rssSites.isEmpty ? "全部启用站点" : "已选 \(rssSites.count) 站")
                  }
                  .buttonStyle(.plain)
                  CinematicFormDivider()
                  NavigationLink {
                    NativeSiteScopePickerView(
                      session: session, title: "搜索站点范围", sites: allSites,
                      selection: $indexerSites)
                  } label: {
                    pickerRow(
                      "搜索站点",
                      value: indexerSites.isEmpty ? "全部启用站点" : "已选 \(indexerSites.count) 站")
                  }
                  .buttonStyle(.plain)
                }
              }
            }

            // 优先级规则组
            VStack(alignment: .leading, spacing: 10) {
              Text("优先级规则组").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  NavigationLink {
                    NativeStringMultiPickerView(
                      title: "订阅规则组", options: allRuleGroups, selection: $subscribeRuleGroups)
                  } label: {
                    pickerRow(
                      "订阅优先级规则",
                      value: subscribeRuleGroups.isEmpty ? "默认" : "\(subscribeRuleGroups.count) 组")
                  }
                  .buttonStyle(.plain)
                  CinematicFormDivider()
                  NavigationLink {
                    NativeStringMultiPickerView(
                      title: "洗版规则组", options: allRuleGroups, selection: $bestVersionRuleGroups)
                  } label: {
                    pickerRow(
                      "洗版优先级规则",
                      value: bestVersionRuleGroups.isEmpty
                        ? "默认" : "\(bestVersionRuleGroups.count) 组")
                  }
                  .buttonStyle(.plain)
                  CinematicFormDivider()
                  NavigationLink {
                    NativeStringMultiPickerView(
                      title: "搜索规则组", options: allRuleGroups, selection: $searchRuleGroups)
                  } label: {
                    pickerRow(
                      "搜索优先级规则",
                      value: searchRuleGroups.isEmpty ? "默认" : "\(searchRuleGroups.count) 组")
                  }
                  .buttonStyle(.plain)
                }
              }
            }

            // 订阅模式
            VStack(alignment: .leading, spacing: 10) {
              Text("订阅刷新模式").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
              CinematicPanel(padding: 0) {
                HStack {
                  Text("订阅模式").font(.body)
                  Spacer()
                  Picker("订阅模式", selection: $subscribeMode) {
                    Text("自动").tag("auto")
                    Text("站点抓取").tag("spider")
                    Text("RSS 订阅").tag("rss")
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
              }
            }
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await loadAll(force: true) }
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("订阅与搜索")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await saveAll() }
        } label: {
          if isSaving {
            ProgressView().controlSize(.small).tint(.primary)
          } else {
            Text("保存").fontWeight(.semibold)
          }
        }
        .tint(.primary)
        .disabled(isSaving || isLoading)
      }
    }
    .task { await loadAll(force: false) }
  }

  private func pickerRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title).font(.body).foregroundStyle(.primary)
      Spacer()
      Text(value).font(.subheadline).foregroundStyle(.secondary)
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary.opacity(0.55))
    }
    .padding(.horizontal, 16).padding(.vertical, 14)
    .frame(minHeight: 56)
    .contentShape(Rectangle())
  }

  /// 仅在首次进入或用户显式下拉刷新时拉取后端配置，防止从子选择页返回时 `.task` 重跑覆盖尚未保存的新选择。
  private func loadAll(force: Bool) async {
    guard force || !hasLoaded else { return }
    hasLoaded = true
    isLoading = true
    defer { isLoading = false }
    async let sitesTask: [NativeSimpleSiteOption]? = {
      guard let ep = try? APIEndpoint(path: ["site"], trailingSlash: true) else { return nil }
      return try? await session.request(
        ep, as: [NativeSimpleSiteOption].self, requiring: .init(category: .admin)
      ).value
    }()
    async let groupsTask: [String]? = {
      guard
        let ep = try? APIEndpoint(
          path: ["rule", "groups"], query: [URLQueryItem(name: "include_usage", value: "false")])
      else { return nil }
      return try? await session.request(
        ep, as: NativeRuleGroupNamesBox.self, requiring: .init(category: .discovery)
      ).value.names
    }()
    async let rssTask: [Int]? = readSetting("RssSites", as: [Int].self)
    async let idxTask: [Int]? = readSetting("IndexerSites", as: [Int].self)
    async let subGrpTask: [String]? = readSetting("SubscribeFilterRuleGroups", as: [String].self)
    async let bestGrpTask: [String]? = readSetting("BestVersionFilterRuleGroups", as: [String].self)
    async let schGrpTask: [String]? = readSetting("SearchFilterRuleGroups", as: [String].self)
    async let envTask: [String: JSONValue]? = {
      guard let ep = try? APIEndpoint(path: ["system", "env"]) else { return nil }
      return try? await session.request(
        ep, as: [String: JSONValue].self, requiring: .init(category: .admin)
      ).value
    }()

    let (sites, groups, rss, idx, sg, bg, scg, env) = await (
      sitesTask, groupsTask, rssTask, idxTask, subGrpTask, bestGrpTask, schGrpTask, envTask
    )
    if let sites { allSites = sites.filter(\.isActive) }
    if let groups { allRuleGroups = groups }
    if let rss { rssSites = Set(rss) }
    if let idx { indexerSites = Set(idx) }
    if let sg { subscribeRuleGroups = Set(sg) }
    if let bg { bestVersionRuleGroups = Set(bg) }
    if let scg { searchRuleGroups = Set(scg) }
    if let env, case .string(let mode) = env["SUBSCRIBE_MODE"], !mode.isEmpty {
      subscribeMode = mode
    }
  }

  private func readSetting<T: Decodable & Sendable>(_ key: String, as type: T.Type) async -> T? {
    guard let ep = try? APIEndpoint(path: ["system", "setting", key]) else { return nil }
    return try? await session.request(
      ep, as: NativeSettingBox<T>.self, requiring: .init(category: .admin)
    ).value.value
  }

  private func saveAll() async {
    isSaving = true
    defer { isSaving = false }
    do {
      try await postSetting("RssSites", value: Array(rssSites).sorted())
      try await postSetting("IndexerSites", value: Array(indexerSites).sorted())
      try await postSetting("SubscribeFilterRuleGroups", value: Array(subscribeRuleGroups).sorted())
      try await postSetting(
        "BestVersionFilterRuleGroups", value: Array(bestVersionRuleGroups).sorted())
      try await postSetting("SearchFilterRuleGroups", value: Array(searchRuleGroups).sorted())
      let envBody = try JSONEncoder().encode(["SUBSCRIBE_MODE": subscribeMode])
      let envEp = try APIEndpoint(path: ["system", "env"], method: .post, body: envBody)
      try await session.perform(envEp, requiring: .init(category: .admin))
      feedback = (false, "已保存订阅与搜索设置。")
    } catch {
      feedback = (true, "保存部分设置失败，请稍后重试。")
    }
  }

  private func postSetting<T: Encodable>(_ key: String, value: T) async throws {
    let body = try JSONEncoder().encode(value)
    let ep = try APIEndpoint(path: ["system", "setting", key], method: .post, body: body)
    try await session.perform(ep, requiring: .init(category: .admin))
  }
}

// MARK: - 2.5 独立媒体数据源设置页（动态读取后端已启用数据源 + 优先级排序）

@MainActor
struct NativeMediaSourceSettingsPage: View {
  let session: NativeSession

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var availableChoices: [NativeBrandChoiceItem] = Self.defaultChoices
  @State private var orderedSelection: [String] = []
  @State private var isLoading = true
  @State private var isSaving = false
  @State private var feedback: (isError: Bool, text: String)?

  private struct BackendMediaSourceRecord: Decodable, Sendable {
    let name: String?
    let mediaSource: String
    let mediaTypes: [String]?
    private enum CodingKeys: String, CodingKey {
      case name
      case mediaSource = "media_source"
      case mediaTypes = "media_types"
    }
  }

  private static let defaultChoices: [NativeBrandChoiceItem] = [
    NativeBrandChoiceItem(id: "themoviedb", title: "TheMovieDb", subtitle: "全球影视元数据"),
    NativeBrandChoiceItem(id: "douban", title: "豆瓣", subtitle: "中文影评与榜单"),
    NativeBrandChoiceItem(id: "bangumi", title: "Bangumi", subtitle: "番剧与动画索引"),
    NativeBrandChoiceItem(id: "musicbrainz", title: "MusicBrainz", subtitle: "音乐专辑与曲目"),
  ]

  private static let builtInPresets: [String: NativeBrandChoiceItem] = Dictionary(
    uniqueKeysWithValues: [
      NativeBrandChoiceItem(id: "themoviedb", title: "TheMovieDb", subtitle: "全球影视元数据"),
      NativeBrandChoiceItem(id: "douban", title: "豆瓣", subtitle: "中文影评与榜单"),
      NativeBrandChoiceItem(id: "bangumi", title: "Bangumi", subtitle: "番剧与动画索引"),
      NativeBrandChoiceItem(id: "anilist", title: "AniList", subtitle: "全球番剧与动画数据"),
      NativeBrandChoiceItem(id: "imdb", title: "IMDb", subtitle: "全球影视评分与资料"),
      NativeBrandChoiceItem(id: "tvdb", title: "TVDB", subtitle: "剧集分集与元数据"),
      NativeBrandChoiceItem(id: "musicbrainz", title: "MusicBrainz", subtitle: "音乐专辑与曲目"),
      NativeBrandChoiceItem(id: "theaudiodb", title: "TheAudioDB", subtitle: "音乐艺人、专辑与封面"),
      NativeBrandChoiceItem(id: "doubanmusic", title: "豆瓣音乐", subtitle: "中文音乐专辑与评分"),
    ].map { ($0.id, $0) })

  private var selectionSetBinding: Binding<Set<String>> {
    Binding(
      get: { Set(orderedSelection) },
      set: { nextSet in
        var updated = orderedSelection.filter { nextSet.contains($0) }
        for choice in availableChoices
        where nextSet.contains(choice.id) && !updated.contains(choice.id) {
          updated.append(choice.id)
        }
        orderedSelection = updated
      }
    )
  }

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let feedback {
            CinematicPanel(padding: 12) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text).font(.subheadline.weight(.medium))
                Spacer()
              }
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("媒体搜索数据源")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
              Spacer()
              if isLoading {
                NativeSkeletonBlock(width: 52, height: 12, cornerRadius: 5)
                  .nativeSkeletonShimmer()
              } else {
                Text(orderedSelection.isEmpty ? "未选择" : "已选 \(orderedSelection.count) 个")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(.horizontal, 8)

            if isLoading {
              NativeCardListSkeletonView(count: 4, style: .iconRow, spacing: 10)
                .transition(.opacity)
            } else {
              NativeBrandMultiOptionGrid(
                kind: .mediaSource,
                items: availableChoices,
                selection: selectionSetBinding,
                columns: 1
              )
            }

            Text("仅展示后端已启用的媒体数据源模块；关闭或启用内置模块请在 Web 高级设置中调整。")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 8)
          }

          if !isLoading && orderedSelection.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
              Text("搜索优先级顺序")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  ForEach(Array(orderedSelection.enumerated()), id: \.element) { idx, sourceID in
                    if idx > 0 { CinematicFormDivider() }
                    let title =
                      availableChoices.first(where: { $0.id == sourceID })?.title ?? sourceID
                    HStack(spacing: 12) {
                      Text("\(idx + 1)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(appearance.accentColor)
                        .frame(width: 22, height: 22)
                        .background(appearance.accentColor.opacity(0.14), in: Circle())
                      NativeBrandIcon(
                        kind: .mediaSource, type: sourceID, size: 28, cornerRadius: 8)
                      Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                      Spacer()
                      HStack(spacing: 4) {
                        Button {
                          guard idx > 0 else { return }
                          orderedSelection.swapAt(idx, idx - 1)
                        } label: {
                          Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(idx > 0 ? Color.primary : Color.secondary.opacity(0.3))
                        .disabled(idx == 0)

                        Button {
                          guard idx < orderedSelection.count - 1 else { return }
                          orderedSelection.swapAt(idx, idx + 1)
                        } label: {
                          Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                          idx < orderedSelection.count - 1
                            ? Color.primary : Color.secondary.opacity(0.3)
                        )
                        .disabled(idx >= orderedSelection.count - 1)
                      }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                  }
                }
              }
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
    .navigationTitle("媒体数据源")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await save() }
        } label: {
          if isSaving {
            ProgressView().controlSize(.small).tint(.primary)
          } else {
            Text("保存").fontWeight(.semibold)
          }
        }
        .tint(.primary)
        .disabled(isSaving || isLoading)
      }
    }
    .task { await load() }
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    async let activeTask: [BackendMediaSourceRecord]? = {
      guard let ep = try? APIEndpoint(path: ["media", "source"]) else { return nil }
      return try? await session.request(ep, as: [BackendMediaSourceRecord].self).value
    }()
    async let settingTask: String? = {
      guard let ep = try? APIEndpoint(path: ["system", "setting", "SEARCH_SOURCE"]) else {
        return nil
      }
      return try? await session.request(
        ep, as: NativeSettingBox<String>.self, requiring: .init(category: .admin)
      ).value.value
    }()

    let (activeSources, rawSetting) = await (activeTask, settingTask)
    if let activeSources, !activeSources.isEmpty {
      var seen: Set<String> = []
      var resolved: [NativeBrandChoiceItem] = []
      for record in activeSources {
        let id = record.mediaSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty, seen.insert(id).inserted else { continue }
        let preset = Self.builtInPresets[id]
        let backendName = record.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = !backendName.isEmpty ? backendName : (preset?.title ?? id)
        let types = (record.mediaTypes ?? []).filter { !$0.isEmpty }.joined(separator: " · ")
        let subtitle = preset?.subtitle ?? (types.isEmpty ? "扩展数据源" : types)
        resolved.append(NativeBrandChoiceItem(id: id, title: title, subtitle: subtitle))
      }
      if !resolved.isEmpty {
        availableChoices = resolved
      }
    }

    let validIDs = Set(availableChoices.map(\.id))
    let parsed = (rawSetting ?? "")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty && validIDs.contains($0) }
    var unique: [String] = []
    for item in parsed where !unique.contains(item) {
      unique.append(item)
    }
    orderedSelection = unique
  }

  private func save() async {
    isSaving = true
    defer { isSaving = false }
    do {
      let value = orderedSelection.joined(separator: ",")
      let body = try JSONEncoder().encode(value)
      let ep = try APIEndpoint(
        path: ["system", "setting", "SEARCH_SOURCE"], method: .post, body: body)
      try await session.perform(ep, requiring: .init(category: .admin))
      NativePageDataCache.shared.clearAll()
      feedback = (false, "已保存媒体数据源设置。")
    } catch {
      feedback = (true, "保存媒体数据源失败，请稍后重试。")
    }
  }
}

@MainActor
private struct NativeSiteScopePickerView: View {
  let session: NativeSession
  let title: String
  let sites: [NativeSimpleSiteOption]
  @Binding var selection: Set<Int>
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
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
                      Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
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
        }
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
      }
      .scrollIndicators(.hidden)
    }
    .navigationTitle(title)
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
private struct NativeStringMultiPickerView: View {
  let title: String
  let options: [String]
  @Binding var selection: Set<String>
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if options.isEmpty {
            CinematicPanel(padding: 16) {
              Text("暂无可选项").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 70)
            }
          } else {
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { idx, item in
                  if idx > 0 { CinematicFormDivider() }
                  Button {
                    if selection.contains(item) {
                      selection.remove(item)
                    } else {
                      selection.insert(item)
                    }
                  } label: {
                    HStack {
                      Text(item).font(.subheadline).foregroundStyle(.primary)
                      Spacer()
                      if selection.contains(item) {
                        Image(systemName: "checkmark")
                          .font(.subheadline.weight(.semibold))
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
          }
        }
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
      }
      .scrollIndicators(.hidden)
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
  }
}

// MARK: - 3. 下载器管理页（全量增删改，iOS 原生分组列表风格）

@MainActor
struct NativeDownloadersManagePage: View {
  let session: NativeSession

  @State private var items: [NativeDownloaderConf] = []
  @State private var isLoading = true
  @State private var editingIndex: Int?
  @State private var showsCreateSheet = false
  @State private var pendingDeleteIndex: Int?
  @State private var feedback: (isError: Bool, text: String)?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text).font(.caption.weight(.medium))
                Spacer()
              }
            }
          }
          if isLoading && items.isEmpty {
            NativeCardListSkeletonView(count: 3, style: .groupedIconList)
              .transition(.opacity)
          } else if items.isEmpty {
            CinematicPanel(padding: 16) {
              Text("暂无下载器，点击右上角「+」新增 qBittorrent 或 Transmission。")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
            }
          } else {
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                  if idx > 0 { CinematicFormDivider() }
                  Button {
                    editingIndex = idx
                  } label: {
                    HStack(spacing: 13) {
                      NativeBrandIcon(
                        kind: .downloader, type: item.type, size: 40, cornerRadius: 11)
                      VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                          Text(item.name).font(.body.weight(.semibold)).foregroundStyle(
                            .primary)
                          if item.isDefault {
                            NativeAdaptiveBadge("默认", tint: NativeTheme.brand)
                          }
                        }
                        Text("\(item.type) · \(item.hostSummary)")
                          .font(.caption.monospaced())
                          .foregroundStyle(.secondary)
                          .lineLimit(1)
                      }
                      Spacer()
                      NativeAdaptiveBadge(
                        item.enabled ? "已启用" : "停用",
                        tint: item.enabled ? NativeTheme.success : nil)
                      Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.55))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .contextMenu {
                    Button {
                      editingIndex = idx
                    } label: {
                      Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                      pendingDeleteIndex = idx
                    } label: {
                      Label("删除下载器", systemImage: "trash")
                    }
                  }
                }
              }
            }
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("下载器")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .tint(.primary)
        .accessibilityLabel("新增下载器")
      }
    }
    .sheet(isPresented: $showsCreateSheet) {
      NativeDownloaderEditorSheet(initial: nil) { created in
        Task { await saveAddingOrUpdating(created, replaceAt: nil) }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { editingIndex != nil },
        set: { if !$0 { editingIndex = nil } })
    ) {
      if let idx = editingIndex, items.indices.contains(idx) {
        NativeDownloaderEditorSheet(
          initial: items[idx],
          onDelete: {
            editingIndex = nil
            pendingDeleteIndex = idx
          }
        ) { updated in
          Task { await saveAddingOrUpdating(updated, replaceAt: idx) }
        }
      }
    }
    .alert(
      "删除下载器",
      isPresented: Binding(
        get: { pendingDeleteIndex != nil },
        set: { if !$0 { pendingDeleteIndex = nil } })
    ) {
      Button("删除", role: .destructive) {
        if let idx = pendingDeleteIndex, items.indices.contains(idx) {
          Task { await deleteAt(idx) }
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("确认删除该下载器配置吗？")
    }
    .task { await load() }
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let ep = try APIEndpoint(path: ["system", "setting", "Downloaders"])
      items =
        try await session.request(
          ep, as: NativeSettingBox<[NativeDownloaderConf]>.self, requiring: .init(category: .admin)
        ).value.value ?? []
    } catch {
      feedback = (true, "读取下载器列表失败。")
    }
  }

  private func saveAddingOrUpdating(_ item: NativeDownloaderConf, replaceAt index: Int?) async {
    var next = items
    if item.isDefault {
      for i in next.indices { next[i].isDefault = false }
    }
    if let index, next.indices.contains(index) {
      next[index] = item
    } else {
      next.append(item)
    }
    // 确保启用列表中至多且至少有一个默认下载器
    if !next.contains(where: { $0.isDefault && $0.enabled }),
      let firstEnabled = next.firstIndex(where: \.enabled)
    {
      next[firstEnabled].isDefault = true
    }
    await persist(
      next, successMessage: index == nil ? "已新增下载器「\(item.name)」。" : "已保存下载器「\(item.name)」。")
  }

  private func deleteAt(_ idx: Int) async {
    var next = items
    let removed = next.remove(at: idx)
    await persist(next, successMessage: "已删除下载器「\(removed.name)」。")
  }

  private func persist(_ next: [NativeDownloaderConf], successMessage: String) async {
    do {
      let body = try JSONEncoder().encode(next)
      let ep = try APIEndpoint(
        path: ["system", "setting", "Downloaders"], method: .post, body: body)
      try await session.perform(ep, requiring: .init(category: .admin))
      items = next
      NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
      feedback = (false, successMessage)
    } catch {
      feedback = (true, "保存下载器配置失败。")
    }
  }
}

@MainActor
private struct NativeDownloaderEditorSheet: View {
  let initial: NativeDownloaderConf?
  var onDelete: (() -> Void)? = nil
  let onSave: (NativeDownloaderConf) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var name: String
  @State private var type: String
  @State private var enabled: Bool
  @State private var isDefault: Bool
  @State private var host: String
  @State private var username: String
  @State private var password: String
  @State private var category: Bool
  @State private var sequentail: Bool
  @State private var forceResume: Bool
  @State private var firstLastPiece: Bool
  @State private var pathMappingText: String

  init(
    initial: NativeDownloaderConf?,
    onDelete: (() -> Void)? = nil,
    onSave: @escaping (NativeDownloaderConf) -> Void
  ) {
    self.initial = initial
    self.onDelete = onDelete
    self.onSave = onSave
    _name = State(initialValue: initial?.name ?? "")
    _type = State(initialValue: initial?.type ?? "qbittorrent")
    _enabled = State(initialValue: initial?.enabled ?? true)
    _isDefault = State(initialValue: initial?.isDefault ?? false)
    _host = State(initialValue: initial?.configString("host") ?? "")
    _username = State(initialValue: initial?.configString("username") ?? "")
    _password = State(initialValue: initial?.configString("password") ?? "")
    _category = State(initialValue: initial?.configBool("category") ?? false)
    _sequentail = State(initialValue: initial?.configBool("sequentail") ?? false)
    _forceResume = State(initialValue: initial?.configBool("force_resume") ?? false)
    _firstLastPiece = State(initialValue: initial?.configBool("first_last_piece") ?? false)
    _pathMappingText = State(
      initialValue: (initial?.pathMapping ?? []).map { $0.joined(separator: ":") }.joined(
        separator: "\n"))
  }

  private static let downloaderChoices: [NativeBrandChoiceItem] = [
    NativeBrandChoiceItem(id: "qbittorrent", title: "qBittorrent"),
    NativeBrandChoiceItem(id: "transmission", title: "Transmission"),
    NativeBrandChoiceItem(id: "rtorrent", title: "rTorrent"),
  ]

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
              Text("下载器类型")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
              NativeBrandOptionGrid(
                kind: .downloader,
                items: Self.downloaderChoices,
                selection: $type,
                columns: 3
              )
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("名称", placeholder: "例如：qBittorrent", text: $name)
                CinematicFormDivider()
                Toggle("启用下载器", isOn: $enabled)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                CinematicFormDivider()
                Toggle("设为默认下载器", isOn: $isDefault)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
              }
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("服务地址", placeholder: "http://192.168.1.2:8080", text: $host)
                CinematicFormDivider()
                rowField("用户名", placeholder: "可选", text: $username)
                CinematicFormDivider()
                HStack(spacing: 12) {
                  Text("密码").font(.subheadline).frame(width: 82, alignment: .leading)
                  SecureField("可选", text: $password)
                    .font(.subheadline).multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
              }
            }

            if type == "qbittorrent" {
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  Toggle("自动分类管理", isOn: $category)
                    .font(.subheadline).tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                  CinematicFormDivider()
                  Toggle("顺序下载", isOn: $sequentail)
                    .font(.subheadline).tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                  CinematicFormDivider()
                  Toggle("强制继续", isOn: $forceResume)
                    .font(.subheadline).tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                  CinematicFormDivider()
                  Toggle("优先首尾文件块", isOn: $firstLastPiece)
                    .font(.subheadline).tint(appearance.accentColor)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                }
              }
            }

            if let onDelete {
              CinematicPanel(padding: 0) {
                Button(role: .destructive) {
                  onDelete()
                } label: {
                  Text("删除此下载器")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NativeTheme.danger)
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        }
      }
      .navigationTitle(initial == nil ? "新增下载器" : "编辑下载器")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") {
            var config = initial?.config ?? [:]
            config["host"] = .string(host.trimmingCharacters(in: .whitespacesAndNewlines))
            config["username"] = .string(username.trimmingCharacters(in: .whitespacesAndNewlines))
            config["password"] = .string(password)
            if type == "qbittorrent" {
              config["category"] = .bool(category)
              config["sequentail"] = .bool(sequentail)
              config["force_resume"] = .bool(forceResume)
              config["first_last_piece"] = .bool(firstLastPiece)
            }
            let updated = NativeDownloaderConf(
              name: name.trimmingCharacters(in: .whitespacesAndNewlines),
              type: type,
              isDefault: isDefault,
              enabled: enabled,
              config: config,
              pathMapping: initial?.pathMapping
            )
            onSave(updated)
            dismiss()
          }
          .fontWeight(.semibold)
          .tint(.primary)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .nativeGlassSheet()
  }

  private func rowField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).frame(width: 82, alignment: .leading)
      TextField(placeholder, text: text)
        .font(.subheadline)
        .multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }
}

// MARK: - 4. 媒体服务器管理页（全量增删改，iOS 原生分组列表风格）

@MainActor
struct NativeMediaServersManagePage: View {
  let session: NativeSession

  @State private var items: [NativeMediaServerConf] = []
  @State private var isLoading = true
  @State private var editingIndex: Int?
  @State private var showsCreateSheet = false
  @State private var pendingDeleteIndex: Int?
  @State private var feedback: (isError: Bool, text: String)?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let feedback {
            CinematicPanel(padding: 11) {
              HStack(spacing: 8) {
                Image(
                  systemName: feedback.isError
                    ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(feedback.isError ? NativeTheme.warning : NativeTheme.success)
                Text(feedback.text).font(.caption.weight(.medium))
                Spacer()
              }
            }
          }
          if isLoading && items.isEmpty {
            NativeCardListSkeletonView(count: 3, style: .groupedIconList)
              .transition(.opacity)
          } else if items.isEmpty {
            CinematicPanel(padding: 16) {
              Text("暂无媒体服务器，点击右上角「+」新增 Emby、Jellyfin、Plex 或飞牛等服务。")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
            }
          } else {
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                  if idx > 0 { CinematicFormDivider() }
                  Button {
                    editingIndex = idx
                  } label: {
                    HStack(spacing: 13) {
                      NativeBrandIcon(
                        kind: .mediaServer, type: item.type, size: 40, cornerRadius: 11)
                      VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.body.weight(.semibold)).foregroundStyle(
                          .primary)
                        Text("\(item.type) · \(item.hostSummary)")
                          .font(.caption.monospaced())
                          .foregroundStyle(.secondary)
                          .lineLimit(1)
                      }
                      Spacer()
                      NativeAdaptiveBadge(
                        item.enabled ? "已启用" : "停用",
                        tint: item.enabled ? NativeTheme.success : nil)
                      Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.55))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .contextMenu {
                    Button {
                      editingIndex = idx
                    } label: {
                      Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                      pendingDeleteIndex = idx
                    } label: {
                      Label("删除媒体服务器", systemImage: "trash")
                    }
                  }
                }
              }
            }
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await load() }
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("媒体服务器")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "plus")
        }
        .tint(.primary)
        .accessibilityLabel("新增媒体服务器")
      }
    }
    .sheet(isPresented: $showsCreateSheet) {
      NativeMediaServerEditorSheet(initial: nil) { created in
        Task { await saveItem(created, replaceAt: nil) }
      }
    }
    .sheet(
      isPresented: Binding(
        get: { editingIndex != nil },
        set: { if !$0 { editingIndex = nil } })
    ) {
      if let idx = editingIndex, items.indices.contains(idx) {
        NativeMediaServerEditorSheet(
          initial: items[idx],
          onDelete: {
            editingIndex = nil
            pendingDeleteIndex = idx
          }
        ) { updated in
          Task { await saveItem(updated, replaceAt: idx) }
        }
      }
    }
    .alert(
      "删除媒体服务器",
      isPresented: Binding(
        get: { pendingDeleteIndex != nil },
        set: { if !$0 { pendingDeleteIndex = nil } })
    ) {
      Button("删除", role: .destructive) {
        if let idx = pendingDeleteIndex, items.indices.contains(idx) {
          Task { await deleteAt(idx) }
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("确认删除该媒体服务器配置吗？")
    }
    .task { await load() }
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let ep = try APIEndpoint(path: ["system", "setting", "MediaServers"])
      items =
        try await session.request(
          ep, as: NativeSettingBox<[NativeMediaServerConf]>.self, requiring: .init(category: .admin)
        ).value.value ?? []
    } catch {
      feedback = (true, "读取媒体服务器列表失败。")
    }
  }

  private func saveItem(_ item: NativeMediaServerConf, replaceAt idx: Int?) async {
    var next = items
    if let idx, next.indices.contains(idx) { next[idx] = item } else { next.append(item) }
    await persist(
      next, successMessage: idx == nil ? "已新增媒体服务器「\(item.name)」。" : "已保存媒体服务器「\(item.name)」。")
  }

  private func deleteAt(_ idx: Int) async {
    var next = items
    let removed = next.remove(at: idx)
    await persist(next, successMessage: "已删除媒体服务器「\(removed.name)」。")
  }

  private func persist(_ next: [NativeMediaServerConf], successMessage: String) async {
    do {
      let body = try JSONEncoder().encode(next)
      let ep = try APIEndpoint(
        path: ["system", "setting", "MediaServers"], method: .post, body: body)
      try await session.perform(ep, requiring: .init(category: .admin))
      items = next
      NativePageDataCache.shared.remove("settingsHub|overview.v2", session: session)
      feedback = (false, successMessage)
    } catch {
      feedback = (true, "保存媒体服务器配置失败。")
    }
  }
}

@MainActor
private struct NativeMediaServerEditorSheet: View {
  private static let serverTypes: [NativeBrandChoiceItem] = [
    NativeBrandChoiceItem(id: "emby", title: "Emby"),
    NativeBrandChoiceItem(id: "jellyfin", title: "Jellyfin"),
    NativeBrandChoiceItem(id: "plex", title: "Plex"),
    NativeBrandChoiceItem(id: "trimemedia", title: "飞牛影视"),
    NativeBrandChoiceItem(id: "ugreen", title: "绿联影视"),
    NativeBrandChoiceItem(id: "zspace", title: "极空间"),
    NativeBrandChoiceItem(id: "navidrome", title: "Navidrome"),
    NativeBrandChoiceItem(id: "mediavault", title: "MediaVault"),
  ]

  let initial: NativeMediaServerConf?
  var onDelete: (() -> Void)? = nil
  let onSave: (NativeMediaServerConf) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @State private var name: String
  @State private var type: String
  @State private var enabled: Bool
  @State private var host: String
  @State private var playHost: String
  @State private var apiKey: String
  @State private var username: String
  @State private var password: String
  @State private var token: String

  init(
    initial: NativeMediaServerConf?,
    onDelete: (() -> Void)? = nil,
    onSave: @escaping (NativeMediaServerConf) -> Void
  ) {
    self.initial = initial
    self.onDelete = onDelete
    self.onSave = onSave
    _name = State(initialValue: initial?.name ?? "")
    _type = State(initialValue: initial?.type ?? "emby")
    _enabled = State(initialValue: initial?.enabled ?? true)
    _host = State(initialValue: initial?.configString("host") ?? "")
    _playHost = State(initialValue: initial?.configString("play_host") ?? "")
    _apiKey = State(initialValue: initial?.configString("apikey") ?? "")
    _username = State(initialValue: initial?.configString("username") ?? "")
    _password = State(initialValue: initial?.configString("password") ?? "")
    _token = State(initialValue: initial?.configString("token") ?? "")
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
              Text("媒体服务器类型")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
              NativeBrandOptionGrid(
                kind: .mediaServer,
                items: Self.serverTypes,
                selection: $type,
                columns: 3
              )
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("名称", placeholder: "例如：客厅 Emby", text: $name)
                CinematicFormDivider()
                Toggle("启用服务器", isOn: $enabled)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
              }
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("服务地址", placeholder: "http://192.168.1.2:8096", text: $host)
                CinematicFormDivider()
                rowField("外网地址", placeholder: "可选播放地址", text: $playHost)
                if type == "emby" || type == "jellyfin" {
                  CinematicFormDivider()
                  rowSecureField("API Key", placeholder: "密钥", text: $apiKey)
                } else if type == "plex" {
                  CinematicFormDivider()
                  rowSecureField("Token", placeholder: "X-Plex-Token", text: $token)
                } else {
                  CinematicFormDivider()
                  rowField("用户名", placeholder: "登录账号", text: $username)
                  CinematicFormDivider()
                  rowSecureField("密码", placeholder: "登录密码", text: $password)
                }
              }
            }

            if let onDelete {
              CinematicPanel(padding: 0) {
                Button(role: .destructive) {
                  onDelete()
                } label: {
                  Text("删除此媒体服务器")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NativeTheme.danger)
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
              }
            }
          }
          .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        }
      }
      .navigationTitle(initial == nil ? "新增媒体服务器" : "编辑媒体服务器")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") {
            var config = initial?.config ?? [:]
            config["host"] = .string(host.trimmingCharacters(in: .whitespacesAndNewlines))
            if !playHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              config["play_host"] = .string(
                playHost.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if type == "emby" || type == "jellyfin" {
              config["apikey"] = .string(apiKey)
            } else if type == "plex" {
              config["token"] = .string(token)
            } else {
              config["username"] = .string(username)
              config["password"] = .string(password)
            }
            let updated = NativeMediaServerConf(
              name: name.trimmingCharacters(in: .whitespacesAndNewlines),
              type: type,
              enabled: enabled,
              syncLibraries: initial?.syncLibraries ?? ["all"],
              syncInterval: initial?.syncInterval,
              config: config
            )
            onSave(updated)
            dismiss()
          }
          .fontWeight(.semibold)
          .tint(.primary)
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .nativeGlassSheet()
  }

  private func rowField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).frame(width: 82, alignment: .leading)
      TextField(placeholder, text: text)
        .font(.subheadline).multilineTextAlignment(.trailing)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }

  private func rowSecureField(_ label: String, placeholder: String, text: Binding<String>)
    -> some View
  {
    HStack(spacing: 12) {
      Text(label).font(.subheadline).frame(width: 82, alignment: .leading)
      SecureField(placeholder, text: text)
        .font(.subheadline).multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 15).padding(.vertical, 11)
  }
}

// MARK: - 5. 播放偏好设置页（本机高频偏好 + 媒体服务器进度同步账号绑定）

@MainActor
struct NativePlaybackPreferencesPage: View {
  let session: NativeSession

  @AppStorage("nativeV2.playback.aspectFill") private var aspectFill = false
  @AppStorage("nativeV2.playback.defaultRate") private var defaultRate = 1.0
  @AppStorage("nativeV2.playback.preferChineseSub") private var preferChineseSub = true
  @AppStorage("nativeV2.playback.strmDirectPlay") private var strmDirectPlay = true
  @AppStorage("nativeV2.playback.directPlay") private var directPlay = true
  @AppStorage("nativeV2.playback.cellularWarn") private var cellularWarn = false
  @AppStorage("nativeV2.playback.keepMusicMiniBar") private var keepMusicMiniBar = true
  @AppStorage("nativeV2.playback.videoEngine") private var videoEngine = "auto"
  @AppStorage("nativeV2.playback.decodeMode") private var decodeMode = "hw_auto"
  @AppStorage("nativeV2.playback.bufferProfile") private var bufferProfile = "standard"
  @AppStorage("nativeV2.playback.audioNightMode") private var audioNightMode = false
  @AppStorage("nativeV2.playback.ignoreAssStyle") private var ignoreAssStyle = false
  @AppStorage("nativeV2.playback.subtitleScale") private var subtitleScale = 1.0
  @AppStorage("nativeV2.playback.externalPlayerTemplate") private var externalPlayerTemplate = ""
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  @State private var accountBindings: [MediaServerAccountBindingDTO] = []
  @State private var isLoadingBindings = true
  @State private var bindingsError: String?
  @State private var bindingSheetTarget: MediaServerAccountBindingDTO?
  @State private var unbindConfirmTarget: MediaServerAccountBindingDTO?
  @State private var isUnbinding = false

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 10) {
            Text("播放内核与解码").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
              .padding(.horizontal, 8)
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                  HStack(alignment: .center, spacing: 8) {
                    Text("播放内核")
                      .font(.body)
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    Picker("播放内核", selection: $videoEngine) {
                      Text("自动选择（推荐）").tag("auto")
                      Text("系统原生内核").tag("native")
                      Text("全能增强内核").tag("enhanced")
                      Text("兼容内核（VLCKit）").tag("legacy")
                    }
                    .pickerStyle(.menu)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .tint(appearance.accentColor)
                    .accessibilityIdentifier("native-playback-video-engine")
                  }
                  Text("常规影片与音乐走系统原生内核省电秒开；MKV、多声道原盘或特效字幕自动切至全能内核")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
                CinematicFormDivider()
                VStack(alignment: .leading, spacing: 6) {
                  HStack {
                    Text("解码模式").font(.body)
                    Spacer()
                    Picker("解码模式", selection: $decodeMode) {
                      Text("硬件解码优先").tag("hw_auto")
                      Text("强制软件解码").tag("sw_force")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                    .accessibilityIdentifier("native-playback-decode-mode")
                  }
                  if videoEngine == "native" && decodeMode == "sw_force" {
                    Text("仅全能增强内核支持视频强制软解，系统原生内核仅支持硬解或音频软解")
                      .font(.caption)
                      .foregroundStyle(.orange)
                  }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
                CinematicFormDivider()
                HStack {
                  Text("网络缓冲").font(.body)
                  Spacer()
                  Picker("网络缓冲", selection: $bufferProfile) {
                    Text("标准缓冲").tag("standard")
                    Text("大缓冲（4K / STRM）").tag("large")
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                  .accessibilityIdentifier("native-playback-buffer-profile")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
                CinematicFormDivider()
                Toggle("夜间模式 / 人声增强", isOn: $audioNightMode)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  .frame(minHeight: 54)
                  .accessibilityIdentifier("native-playback-audio-night-mode")
                CinematicFormDivider()
                Toggle("忽略 ASS 字幕特效样式", isOn: $ignoreAssStyle)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  .frame(minHeight: 54)
                  .accessibilityIdentifier("native-playback-ignore-ass-style")
                CinematicFormDivider()
                HStack {
                  Text("字幕字号").font(.body)
                  Spacer()
                  Picker("字幕字号", selection: $subtitleScale) {
                    Text("小 (0.85x)").tag(0.85)
                    Text("标准 (1.0x)").tag(1.0)
                    Text("大 (1.15x)").tag(1.15)
                    Text("特大 (1.3x)").tag(1.3)
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                  .accessibilityIdentifier("native-playback-subtitle-scale")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
                CinematicFormDivider()
                VStack(alignment: .leading, spacing: 6) {
                  Text("外部播放器 URL 模板").font(.body)
                  TextField("scheme://play?url={url}&title={title}", text: $externalPlayerTemplate)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("native-playback-external-template")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
              }
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("视频播放").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
              .padding(.horizontal, 8)
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                HStack {
                  Text("默认画面模式").font(.body)
                  Spacer()
                  Picker("画面模式", selection: $aspectFill) {
                    Text("自适应").tag(false)
                    Text("铺满屏幕").tag(true)
                  }
                  .pickerStyle(.segmented)
                  .frame(width: 176)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
                CinematicFormDivider()
                HStack {
                  Text("默认播放倍速").font(.body)
                  Spacer()
                  Picker("倍速", selection: $defaultRate) {
                    Text("1.0x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                    Text("2.0x").tag(2.0)
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
                CinematicFormDivider()
                Toggle("STRM 直链播放", isOn: $strmDirectPlay)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  .frame(minHeight: 54)
                  .accessibilityIdentifier("native-playback-strm-direct")
                CinematicFormDivider()
                VStack(alignment: .leading, spacing: 4) {
                  Toggle("媒体服务器直连优先", isOn: $directPlay)
                    .font(.body).tint(appearance.accentColor)
                    .accessibilityIdentifier("native-playback-server-direct")
                  Text("已绑定个人账号的 Emby / Jellyfin / Plex 在直连可达时优先直连播放，不可达或失败时自动回退后台中转")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
                CinematicFormDivider()
                Toggle("优先选择中文字幕", isOn: $preferChineseSub)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  .frame(minHeight: 54)
                CinematicFormDivider()
                Toggle("移动网络播放前提醒", isOn: $cellularWarn)
                  .font(.body).tint(appearance.accentColor)
                  .padding(.horizontal, 16).padding(.vertical, 12)
                  .frame(minHeight: 54)
              }
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("音乐播放").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
              .padding(.horizontal, 8)
            CinematicPanel(padding: 0) {
              Toggle("返回时收起为悬浮迷你播放条", isOn: $keepMusicMiniBar)
                .font(.body).tint(appearance.accentColor)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 54)
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("媒体服务器进度同步")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
              Spacer()
              if !isLoadingBindings {
                Button {
                  Task { await loadBindings() }
                } label: {
                  Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("刷新媒体服务器绑定状态")
              }
            }
            .padding(.horizontal, 8)

            CinematicPanel(padding: 0) {
              if isLoadingBindings && accountBindings.isEmpty {
                HStack(spacing: 10) {
                  ProgressView().controlSize(.small)
                  Text("正在加载媒体服务器同步状态…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
              } else if let bindingsError, accountBindings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                  Text(bindingsError)
                    .font(.subheadline)
                    .foregroundStyle(NativeTheme.danger)
                  Button("重试") {
                    Task { await loadBindings() }
                  }
                  .font(.subheadline.weight(.semibold))
                  .tint(appearance.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
              } else if accountBindings.isEmpty {
                Text("暂无已启用的媒体服务器")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(16)
              } else {
                VStack(spacing: 0) {
                  ForEach(Array(accountBindings.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                      CinematicFormDivider()
                    }
                    bindingRow(item)
                  }
                }
              }
            }

            Text("绑定 Emby、Jellyfin 或 Plex 个人账号后，播放进度将实时显示在媒体服务器「正在播放」仪表盘中；密码仅用于一次性换取令牌，绝不保存在本地。")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 8)
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("播放偏好")
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .task {
      await loadBindings()
    }
    .sheet(item: $bindingSheetTarget) { target in
      NativeMediaServerAccountBindSheet(session: session, target: target) { updated in
        if let idx = accountBindings.firstIndex(where: { $0.server == updated.server }) {
          accountBindings[idx] = updated
        } else {
          Task { await loadBindings() }
        }
      }
    }
    .confirmationDialog(
      "解除账号绑定？",
      isPresented: Binding(
        get: { unbindConfirmTarget != nil },
        set: { if !$0 { unbindConfirmTarget = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let target = unbindConfirmTarget {
        Button("解绑 \(target.server)", role: .destructive) {
          unbindConfirmTarget = nil
          Task { await performUnbind(target) }
        }
      }
      Button("取消", role: .cancel) { unbindConfirmTarget = nil }
    } message: {
      if let target = unbindConfirmTarget {
        Text("解绑后将清除 \(target.server) 的个人同步令牌，恢复为服务器默认进度同步模式。")
      }
    }
  }

  @ViewBuilder
  private func bindingRow(_ item: MediaServerAccountBindingDTO) -> some View {
    let badge = syncBadge(for: item)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(item.server)
            .font(.body.weight(.medium))
            .lineLimit(1)
          Text(badge.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(badge.tint.opacity(0.14), in: Capsule())
        }
        Text(bindingSubtitle(for: item))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      if item.supportsBinding {
        HStack(spacing: 8) {
          if item.bound {
            Button("解绑") {
              unbindConfirmTarget = item
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(NativeTheme.danger)
            .buttonStyle(.plain)
            .disabled(isUnbinding)
          }
          Button(item.bound || item.status == "invalid" ? "重绑" : "绑定") {
            bindingSheetTarget = item
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(appearance.accentColor)
          .padding(.horizontal, 11)
          .padding(.vertical, 6)
          .background(appearance.accentColor.opacity(0.14), in: Capsule())
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
  }

  private func syncBadge(for item: MediaServerAccountBindingDTO) -> (label: String, tint: Color) {
    if item.status == "invalid" {
      return ("凭据已失效", NativeTheme.danger)
    }
    switch item.syncMode {
    case "session":
      return ("实时会话同步", Color.green)
    case "userdata":
      return ("仅进度同步", Color.orange)
    case "scrobble":
      return ("音乐记录", Color.blue)
    default:
      return ("暂不支持", Color.secondary)
    }
  }

  private func bindingSubtitle(for item: MediaServerAccountBindingDTO) -> String {
    let typeName = item.serverType.uppercased()
    if item.status == "invalid" {
      return "\(typeName) · 已保存的令牌失效，请重新绑定以恢复实时播放会话"
    }
    if item.bound, let remote = item.remoteUsername, !remote.isEmpty {
      return "\(typeName) · 已绑定账号 \(remote)"
    }
    if item.status == "builtin" {
      return "\(typeName) · 已内置启用同步，无需单独绑定"
    }
    if item.supportsBinding {
      return item.syncMode == "session"
        ? "\(typeName) · 当前走服务端共享身份，绑定个人账号可归属到本人"
        : "\(typeName) · 绑定个人账号后可升级为实时「正在播放」会话"
    }
    return "\(typeName) · 当前媒体服务器不支持播放进度回写"
  }

  private func loadBindings() async {
    isLoadingBindings = true
    bindingsError = nil
    defer { isLoadingBindings = false }
    do {
      accountBindings = try await MediaServerAccountBindingClient.listBindings(session: session)
    } catch {
      bindingsError = error.localizedDescription
    }
  }

  private func performUnbind(_ target: MediaServerAccountBindingDTO) async {
    isUnbinding = true
    defer { isUnbinding = false }
    do {
      try await MediaServerAccountBindingClient.unbind(session: session, server: target.server)
      await loadBindings()
    } catch {
      bindingsError = error.localizedDescription
    }
  }
}

/// 媒体服务器个人账号一次性绑定弹窗（密码仅用于向媒体服务器换取个人令牌，绝不保存在本地）。
@MainActor
private struct NativeMediaServerAccountBindSheet: View {
  let session: NativeSession
  let target: MediaServerAccountBindingDTO
  let onBound: (MediaServerAccountBindingDTO) -> Void

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  @State private var usePlexToken = false
  @State private var username: String
  @State private var password = ""
  @State private var plexToken = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  init(
    session: NativeSession,
    target: MediaServerAccountBindingDTO,
    onBound: @escaping (MediaServerAccountBindingDTO) -> Void
  ) {
    self.session = session
    self.target = target
    self.onBound = onBound
    _username = State(initialValue: target.remoteUsername ?? session.user.name)
  }

  private var isPlex: Bool {
    target.serverType.lowercased() == "plex"
  }

  private var canSubmit: Bool {
    guard !isSubmitting else { return false }
    if isPlex && usePlexToken {
      return !plexToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
  }

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if isPlex {
              Picker("认证方式", selection: $usePlexToken) {
                Text("账号密码").tag(false)
                Text("Plex Token").tag(true)
              }
              .pickerStyle(.segmented)
            }

            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                if isPlex && usePlexToken {
                  HStack(spacing: 12) {
                    Text("Token").font(.subheadline).frame(width: 72, alignment: .leading)
                    SecureField("粘贴 X-Plex-Token", text: $plexToken)
                      .font(.subheadline)
                      .multilineTextAlignment(.trailing)
                      .textInputAutocapitalization(.never)
                      .autocorrectionDisabled()
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                } else {
                  HStack(spacing: 12) {
                    Text("用户名").font(.subheadline).frame(width: 72, alignment: .leading)
                    TextField("媒体服务器登录用户名", text: $username)
                      .font(.subheadline)
                      .multilineTextAlignment(.trailing)
                      .textInputAutocapitalization(.never)
                      .autocorrectionDisabled()
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                  CinematicFormDivider()
                  HStack(spacing: 12) {
                    Text("密码").font(.subheadline).frame(width: 72, alignment: .leading)
                    SecureField("媒体服务器登录密码", text: $password)
                      .font(.subheadline)
                      .multilineTextAlignment(.trailing)
                  }
                  .padding(.horizontal, 15).padding(.vertical, 12)
                }
              }
            }

            if let errorMessage, !errorMessage.isEmpty {
              Text(errorMessage)
                .font(.caption)
                .foregroundStyle(NativeTheme.danger)
                .padding(.horizontal, 6)
            }

            Text(
              isPlex && usePlexToken
                ? "开启两步验证（2FA）的 Plex 账号请直接粘贴个人 X-Plex-Token 完成绑定。"
                : "账号密码仅提交给 MoviePilot 后台向 \(target.server) 一次性换取加密个人令牌，不会在设备或服务端明文保留密码。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 16)
        }
      }
      .navigationTitle("绑定 \(target.server)")
      .navigationBarTitleDisplayMode(.inline)
      .nativeTopNavigationBar()
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("取消") { dismiss() }
            .tint(.primary)
            .disabled(isSubmitting)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await submit() }
          } label: {
            if isSubmitting {
              ProgressView().controlSize(.small)
            } else {
              Text("绑定").fontWeight(.semibold)
            }
          }
          .tint(appearance.accentColor)
          .disabled(!canSubmit)
        }
      }
    }
    .nativeGlassSheet()
  }

  private func submit() async {
    isSubmitting = true
    errorMessage = nil
    defer {
      isSubmitting = false
      password = ""
      plexToken = ""
    }
    do {
      let updated = try await MediaServerAccountBindingClient.bind(
        session: session,
        server: target.server,
        username: usePlexToken ? nil : username,
        password: usePlexToken ? nil : password,
        token: usePlexToken ? plexToken : nil
      )
      onBound(updated)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

// MARK: - 解码模型

private struct NativeSettingsHubOverviewCache {
  let storage: NativeSettingsStorageBrief?
  let siteCount: Int?
  let userCount: Int?
  let pendingAuthCount: Int
  let approvedAuthCount: Int
  let downloaderCount: Int?
  let mediaServerCount: Int?
}

private struct NativeSettingsStorageBrief: Decodable, Sendable {
  let total: Double
  let used: Double

  var usedRatio: Double {
    guard total > 0 else { return 0 }
    return min(max(used / total, 0), 1)
  }

  enum CodingKeys: String, CodingKey {
    case total = "total_storage"
    case used = "used_storage"
  }
}

private struct NativeSettingsSiteBrief: Decodable, Sendable {
  let isActive: Bool
  enum CodingKeys: String, CodingKey { case isActive = "is_active" }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    isActive = (try? c.decode(Bool.self, forKey: .isActive)) ?? true
  }
}

private struct NativeSettingsIDBrief: Decodable, Sendable {
  let id: Int
}

private struct NativeSettingBox<Value: Decodable & Sendable>: Decodable, Sendable {
  let value: Value?
}

private struct NativeSimpleSiteOption: Decodable, Sendable, Identifiable {
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

private struct NativeRuleGroupNamesBox: Decodable, Sendable {
  struct GroupItem: Decodable, Sendable { let name: String? }
  let ruleGroups: [GroupItem]?
  var names: [String] { (ruleGroups ?? []).compactMap(\.name).filter { !$0.isEmpty } }
  private enum CodingKeys: String, CodingKey { case ruleGroups = "rule_groups" }
}

private struct NativeChannelAuthListData: Decodable, Sendable {
  let members: [NativeChannelMember]
  let channels: [NativeAuthChannel]

  private enum CodingKeys: String, CodingKey {
    case members, channels
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    members = (try? c.decodeIfPresent([NativeChannelMember].self, forKey: .members)) ?? []
    channels = (try? c.decodeIfPresent([NativeAuthChannel].self, forKey: .channels)) ?? []
  }
}

private struct NativeChannelMember: Decodable, Sendable, Identifiable {
  let id: String
  let notificationID: String
  let channel: String
  let source: String
  let senderID: String
  let displayName: String
  let status: String
  let role: String
  let scopes: [String]
  let linkedUsername: String?

  private enum CodingKeys: String, CodingKey {
    case id, channel, source, status, role, scopes
    case notificationID = "notification_id"
    case senderID = "sender_id"
    case displayName = "display_name"
    case linkedUsername = "linked_username"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
    notificationID = (try? c.decodeIfPresent(String.self, forKey: .notificationID)) ?? ""
    channel = (try? c.decodeIfPresent(String.self, forKey: .channel)) ?? ""
    source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? channel
    senderID = (try? c.decodeIfPresent(String.self, forKey: .senderID)) ?? ""
    displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? ""
    status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
    role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "member"
    scopes = (try? c.decodeIfPresent([String].self, forKey: .scopes)) ?? []
    linkedUsername = try? c.decodeIfPresent(String.self, forKey: .linkedUsername)
  }
}

private struct NativeAuthChannel: Decodable, Sendable, Identifiable {
  let id: String
  let name: String
  let channel: String
  let enabled: Bool

  var type: String { channel }

  private enum CodingKeys: String, CodingKey {
    case id, name, channel, type, enabled
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    channel =
      (try? c.decodeIfPresent(String.self, forKey: .channel))
      ?? (try? c.decodeIfPresent(String.self, forKey: .type))
      ?? ""
    enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
  }
}

private struct NativeBindingCodeData: Decodable, Sendable {
  let code: String
  let expiresAt: Double?
  private enum CodingKeys: String, CodingKey {
    case code
    case expiresAt = "expires_at"
  }
}

private struct NativeDownloaderConf: Codable, Sendable {
  var name: String
  var type: String
  var isDefault: Bool
  var enabled: Bool
  var config: [String: JSONValue]
  var pathMapping: [[String]]?

  var hostSummary: String {
    let h = configString("host")
    return h.isEmpty ? "未配置地址" : h
  }

  func configString(_ key: String) -> String {
    if case .string(let s) = config[key] { return s }
    return ""
  }

  func configBool(_ key: String) -> Bool {
    if case .bool(let b) = config[key] { return b }
    return false
  }

  private enum CodingKeys: String, CodingKey {
    case name, type, enabled, config
    case isDefault = "default"
    case pathMapping = "path_mapping"
  }

  init(
    name: String, type: String, isDefault: Bool, enabled: Bool, config: [String: JSONValue],
    pathMapping: [[String]]?
  ) {
    self.name = name
    self.type = type
    self.isDefault = isDefault
    self.enabled = enabled
    self.config = config
    self.pathMapping = pathMapping
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    type = (try? c.decode(String.self, forKey: .type)) ?? "qbittorrent"
    isDefault = (try? c.decode(Bool.self, forKey: .isDefault)) ?? false
    enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    config = (try? c.decode([String: JSONValue].self, forKey: .config)) ?? [:]
    pathMapping = try? c.decode([[String]].self, forKey: .pathMapping)
  }
}

private struct NativeMediaServerConf: Codable, Sendable {
  var name: String
  var type: String
  var enabled: Bool
  var syncLibraries: [String]?
  var syncInterval: Int?
  var config: [String: JSONValue]

  var hostSummary: String {
    let h = configString("host")
    return h.isEmpty ? "未配置地址" : h
  }

  func configString(_ key: String) -> String {
    if case .string(let s) = config[key] { return s }
    return ""
  }

  private enum CodingKeys: String, CodingKey {
    case name, type, enabled, config
    case syncLibraries = "sync_libraries"
    case syncInterval = "sync_interval"
  }

  init(
    name: String, type: String, enabled: Bool, syncLibraries: [String]?, syncInterval: Int?,
    config: [String: JSONValue]
  ) {
    self.name = name
    self.type = type
    self.enabled = enabled
    self.syncLibraries = syncLibraries
    self.syncInterval = syncInterval
    self.config = config
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decode(String.self, forKey: .name)) ?? ""
    type = (try? c.decode(String.self, forKey: .type)) ?? "emby"
    enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
    syncLibraries = try? c.decode([String].self, forKey: .syncLibraries)
    syncInterval = try? c.decode(Int.self, forKey: .syncInterval)
    config = (try? c.decode([String: JSONValue].self, forKey: .config)) ?? [:]
  }
}
