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

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if snapshot.user.isSuperuser {
            if let storage, storage.total > 0 {
              storageTelemetryCard(storage)
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
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.top, 10)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .refreshable { await loadOverview(forceRefresh: true) }
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-settings-scroll")
    }
    .navigationTitle("设置")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .sheet(isPresented: $showsNotificationSettings) {
      NativeNotificationSettingsSheet(session: session)
    }
    .sheet(isPresented: $showsWidgetSettings) {
      NativeWidgetSettingsSheet(session: session)
    }
    .alert("清理本地缓存", isPresented: $showsClearCacheConfirm) {
      Button("清理", role: .destructive) {
        NativeMediaArtworkCache.shared.clearSession(session)
        NativePageDataCache.shared.clearAll()
        cacheBytes = 0
        cacheClearedNotice = true
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("将清空本机已缓存的海报图片与页面快照，不会影响服务器数据。")
    }
    .alert("退出登录", isPresented: $showsLogoutConfirm) {
      Button("退出登录", role: .destructive) { onLogout() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("退出后需要重新输入账号密码或凭据登录当前 MoviePilot 服务。")
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

  private func storageTelemetryCard(_ storage: NativeSettingsStorageBrief) -> some View {
    let host = session.instance.address.url.host ?? session.instance.address.url.absoluteString
    let ratio = storage.usedRatio
    let percentText = "\(Int((ratio * 100).rounded()))%"
    let freeBytes = max(storage.total - storage.used, 0)
    return CinematicPanel(padding: 15) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Circle()
            .fill(NativeTheme.success)
            .frame(width: 6.5, height: 6.5)
          Text(host)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 8)
          Text("\(Self.formatBytes(storage.used)) / \(Self.formatBytes(storage.total))")
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.primary.opacity(0.86))
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
        .frame(height: 7)
        HStack {
          HStack(spacing: 4) {
            Circle().fill(appearance.accentColor).frame(width: 6, height: 6)
            Text("已用 \(percentText)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text("可用 \(Self.formatBytes(freeBytes))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  /// 第二行 3 列紧凑状态卡：站点管理、用户管理、渠道授权。
  private var adminTopStatusGrid: some View {
    HStack(spacing: 10) {
      compactStatusCard(
        title: "站点管理",
        statusText: siteCount.map { "\($0) 启用" } ?? "索引与流量",
        symbol: "globe",
        tint: NativeTheme.info,
        statusTint: NativeTheme.success,
        id: "native-workspace-sites"
      ) { onNavigate(.sites) }

      compactStatusCard(
        title: "用户管理",
        statusText: userCount.map { "\($0) 位成员" } ?? "权限角色",
        symbol: "person.2.fill",
        tint: NativeTheme.brand,
        statusTint: NativeTheme.brand,
        id: "native-workspace-users"
      ) { onNavigate(.users) }

      compactStatusCard(
        title: "渠道授权",
        statusText: pendingAuthCount > 0 ? "\(pendingAuthCount) 待审批" : "已授 \(approvedAuthCount)",
        symbol: "person.badge.key.fill",
        tint: NativeTheme.pink,
        statusTint: pendingAuthCount > 0 ? NativeTheme.warning : NativeTheme.success,
        id: "native-workspace-channel-auth"
      ) { onNavigate(.channelAuth) }
    }
  }

  private func compactStatusCard(
    title: String,
    statusText: String,
    symbol: String,
    tint: Color,
    statusTint: Color,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      CinematicPanel(padding: 12) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(
              tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          VStack(alignment: .leading, spacing: 3) {
            Text(title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
            HStack(spacing: 4) {
              Circle().fill(statusTint).frame(width: 5, height: 5)
              Text(statusText)
                .font(.caption2)
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
      CinematicPanel(padding: 15) {
        HStack(spacing: 12) {
          iconBadge("person.badge.key.fill", tint: NativeTheme.pink)
          VStack(alignment: .leading, spacing: 2) {
            Text("渠道授权与绑定")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
            Text("生成 5 分钟渠道关联绑定码")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.6))
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("native-workspace-channel-auth")
  }

  // MARK: - 2. 分组一：核心业务

  private var coreWorkflowSection: some View {
    settingsGroup("核心业务", footer: "底层代理、并发与高级系统参数请在 Web 管理台配置。") {
      navRow(
        title: "订阅与搜索", subtitle: "站点范围 · 规则组", symbol: "magnifyingglass.circle.fill",
        tint: NativeTheme.info, id: "native-settings-subscribe-search"
      ) { onNavigate(.subscribeSearchSettings) }
      CinematicFormDivider()
      navRow(
        title: "下载器", subtitle: downloaderCount.map { "\($0) 个" } ?? "新增与管理",
        symbol: "arrow.down.circle.fill", tint: NativeTheme.success,
        id: "native-settings-downloaders"
      ) { onNavigate(.downloadersManage) }
      CinematicFormDivider()
      navRow(
        title: "媒体服务器", subtitle: mediaServerCount.map { "\($0) 个" } ?? "新增与管理",
        symbol: "server.rack", tint: NativeTheme.brand,
        id: "native-settings-mediaservers"
      ) { onNavigate(.mediaServersManage) }
      CinematicFormDivider()
      navRow(
        title: "整理与目录", subtitle: "目录映射与刮削", symbol: "folder.badge.gearshape.fill",
        tint: NativeTheme.warning, id: "native-settings-hub-directories"
      ) { onNavigate(.systemModule(.directories)) }
      CinematicFormDivider()
      navRow(
        title: "播放偏好", subtitle: playbackSummaryText, symbol: "play.rectangle.fill",
        tint: NativeTheme.pink, id: "native-settings-playback"
      ) { onNavigate(.playbackSettings) }
    }
  }

  private var memberPlaybackSection: some View {
    settingsGroup("播放") {
      navRow(
        title: "播放偏好", subtitle: playbackSummaryText, symbol: "play.rectangle.fill",
        tint: NativeTheme.pink, id: "native-settings-playback"
      ) { onNavigate(.playbackSettings) }
    }
  }

  private var playbackSummaryText: String {
    let fill = playbackAspectFill ? "铺满" : "自适应"
    let rate = playbackDefaultRate == 1.0 ? "1.0x" : String(format: "%.2gx", playbackDefaultRate)
    return "\(fill) · \(rate)"
  }

  // MARK: - 3. 分组二：通知与智能

  private var notificationAndAssistantSection: some View {
    settingsGroup("通知与智能") {
      navRow(
        title: "本机推送通知", subtitle: "APNs 提醒", symbol: "bell.and.waves.left.and.right",
        tint: NativeTheme.danger, id: "native-settings-hub-push"
      ) { showsNotificationSettings = true }
      if snapshot.user.isSuperuser {
        CinematicFormDivider()
        navRow(
          title: "服务端通知渠道", subtitle: "消息推送配置", symbol: "bell.badge.fill",
          tint: NativeTheme.success, id: "native-settings-hub-notifications"
        ) { onNavigate(.systemModule(.notifications)) }
      }
      CinematicFormDivider()
      HStack(spacing: 12) {
        iconBadge("sparkles", tint: NativeTheme.brand)
        Text("悬浮智能助手")
          .font(.subheadline)
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        Toggle("", isOn: $showFloatingAssistant)
          .labelsHidden()
          .tint(appearance.accentColor)
      }
      .padding(.horizontal, 15)
      .padding(.vertical, 9)
      .frame(minHeight: 48)
      .accessibilityIdentifier("native-settings-hub-floating-assistant")
    }
  }

  // MARK: - 4. 分组三：外观与本机

  private var appearanceAndDeviceSection: some View {
    settingsGroup("外观与本机") {
      navRow(
        title: "主题与外观", subtitle: appearance.summaryText, symbol: "paintpalette.fill",
        tint: appearance.accentColor, id: "native-settings-hub-appearance"
      ) { onNavigate(.appearance) }
      CinematicFormDivider()
      navRow(
        title: "桌面小组件", subtitle: "实例与刷新", symbol: "rectangle.3.group.fill",
        tint: NativeTheme.cyan, id: "native-settings-hub-widgets"
      ) { showsWidgetSettings = true }
      CinematicFormDivider()
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
        HStack(spacing: 12) {
          iconBadge("globe", tint: NativeTheme.info)
          Text("界面语言")
            .font(.subheadline)
            .foregroundStyle(.primary)
          Spacer(minLength: 8)
          Text(currentLanguage.title)
            .font(.caption)
            .foregroundStyle(.secondary)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary.opacity(0.65))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-v2-language")
      CinematicFormDivider()
      navRow(
        title: "本地缓存清理",
        subtitle: cacheClearedNotice ? "已清理" : Self.formatBytes(Double(cacheBytes)),
        symbol: "internaldrive.fill", tint: NativeTheme.warning,
        id: "native-settings-clear-cache"
      ) { showsClearCacheConfirm = true }
    }
  }

  // MARK: - 5. 分组四：服务与账号

  private var accountAndServerSection: some View {
    let host = session.instance.address.url.host ?? session.instance.address.url.absoluteString
    return settingsGroup("服务与账号") {
      navRow(
        title: "切换服务", subtitle: host, symbol: "arrow.left.arrow.right.circle.fill",
        tint: NativeTheme.info, id: "native-v2-switch"
      ) { onSwitchServer() }
      CinematicFormDivider()
      Button {
        showsLogoutConfirm = true
      } label: {
        HStack(spacing: 12) {
          iconBadge("rectangle.portrait.and.arrow.right", tint: NativeTheme.danger)
          Text("退出登录")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(NativeTheme.danger)
          Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("native-v2-logout")
    }
  }

  // MARK: - 原生分组列表基础组件

  private func settingsGroup<Content: View>(
    _ title: String,
    footer: String? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
      CinematicPanel(padding: 0) {
        VStack(spacing: 0) { content() }
      }
      if let footer, !footer.isEmpty {
        Text(footer)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
      }
    }
  }

  private func iconBadge(_ symbol: String, tint: Color) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: 28, height: 28)
      .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func navRow(
    title: String,
    subtitle: String? = nil,
    symbol: String,
    tint: Color,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        iconBadge(symbol, tint: tint)
        Text(title)
          .font(.subheadline)
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary.opacity(0.55))
      }
      .padding(.horizontal, 15)
      .padding(.vertical, 10)
      .frame(minHeight: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  // MARK: - 概览数据加载

  private func loadOverview(forceRefresh: Bool = false) async {
    cacheBytes = await NativeMediaArtworkCache.shared.diskCacheSizeBytes(for: session)
    guard snapshot.user.isSuperuser else { return }
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
      return
    }
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
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      if isSuperuser {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showsCreateSheet = true
          } label: {
            Image(systemName: "plus")
          }
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
        ProgressView("正在载入渠道授权记录…")
          .tint(.primary)
          .frame(maxWidth: .infinity, minHeight: 140)
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
                HStack(spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                      Text(member.displayName.isEmpty ? member.senderID : member.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                      NativeAdaptiveBadge(
                        member.role == "admin" ? "管理员" : "普通成员",
                        tint: member.role == "admin" ? NativeTheme.brand : NativeTheme.info)
                    }
                    Text("\(member.source) · \(member.senderID)")
                      .font(.caption2.monospaced())
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.55))
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
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
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                HStack {
                  Text("通知渠道").font(.subheadline)
                  Spacer()
                  Picker("通知渠道", selection: $notificationID) {
                    ForEach(channels) { ch in
                      Text("\(ch.name) (\(ch.type))").tag(ch.id)
                    }
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                inlineInputRow("发送者 ID", placeholder: "Telegram/企微用户 ID", text: $senderID)
                CinematicFormDivider()
                inlineInputRow("显示昵称", placeholder: "便于核对的昵称", text: $displayName)
                CinematicFormDivider()
                HStack {
                  Text("授权角色").font(.subheadline)
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
      .navigationTitle("新增渠道授权")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button("授权") { Task { await submit() } }
            .fontWeight(.semibold)
            .disabled(
              isSubmitting || notificationID.isEmpty
                || senderID.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear {
        if notificationID.isEmpty, let first = channels.first { notificationID = first.id }
      }
    }
    .nativeAppearanceRoot()
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
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button("保存") {
            if role == "admin" && member.role != "admin" {
              showsAdminConfirm = true
            } else {
              Task { await submit() }
            }
          }
          .fontWeight(.semibold)
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
    .nativeAppearanceRoot()
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

// MARK: - 2. 订阅与搜索设置页（站点范围 + 规则组 + 搜索来源 + 订阅模式）

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
  @State private var searchSources: Set<String> = ["themoviedb", "douban"]
  @State private var isLoading = true
  @State private var isSaving = false
  @State private var feedback: (isError: Bool, text: String)?

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
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

          if isLoading {
            ProgressView("正在读取订阅与搜索设置…")
              .tint(.primary)
              .frame(maxWidth: .infinity, minHeight: 200)
          } else {
            // 站点范围
            VStack(alignment: .leading, spacing: 7) {
              Text("站点范围").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  NavigationLink {
                    NativeSiteScopePickerView(
                      title: "订阅站点范围", sites: allSites, selection: $rssSites)
                  } label: {
                    pickerRow(
                      "订阅站点", value: rssSites.isEmpty ? "全部启用站点" : "已选 \(rssSites.count) 站")
                  }
                  .buttonStyle(.plain)
                  CinematicFormDivider()
                  NavigationLink {
                    NativeSiteScopePickerView(
                      title: "搜索站点范围", sites: allSites, selection: $indexerSites)
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
            VStack(alignment: .leading, spacing: 7) {
              Text("优先级规则组").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
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

            // 模式与数据源
            VStack(alignment: .leading, spacing: 7) {
              Text("模式与数据源").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
              CinematicPanel(padding: 0) {
                VStack(spacing: 0) {
                  HStack {
                    Text("订阅刷新模式").font(.subheadline)
                    Spacer()
                    Picker("订阅模式", selection: $subscribeMode) {
                      Text("自动").tag("auto")
                      Text("站点抓取").tag("spider")
                      Text("RSS 订阅").tag("rss")
                    }
                    .pickerStyle(.menu)
                    .tint(appearance.accentColor)
                  }
                  .padding(.horizontal, 15).padding(.vertical, 10)
                  CinematicFormDivider()
                  NavigationLink {
                    NativeStringMultiPickerView(
                      title: "媒体搜索数据源",
                      options: ["themoviedb", "douban", "bangumi", "musicbrainz"],
                      selection: $searchSources)
                  } label: {
                    pickerRow(
                      "搜索数据源",
                      value: searchSources.isEmpty ? "默认" : "\(searchSources.count) 个来源")
                  }
                  .buttonStyle(.plain)
                }
              }
            }
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("订阅与搜索")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await saveAll() }
        } label: {
          if isSaving {
            ProgressView().controlSize(.small)
          } else {
            Text("保存").fontWeight(.semibold)
          }
        }
        .disabled(isSaving || isLoading)
      }
    }
    .task { await loadAll() }
  }

  private func pickerRow(_ title: String, value: String) -> some View {
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

  private func loadAll() async {
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
    async let srcTask: String? = readSetting("SEARCH_SOURCE", as: String.self)
    async let envTask: [String: JSONValue]? = {
      guard let ep = try? APIEndpoint(path: ["system", "env"]) else { return nil }
      return try? await session.request(
        ep, as: [String: JSONValue].self, requiring: .init(category: .admin)
      ).value
    }()

    let (sites, groups, rss, idx, sg, bg, scg, src, env) = await (
      sitesTask, groupsTask, rssTask, idxTask, subGrpTask, bestGrpTask, schGrpTask, srcTask, envTask
    )
    if let sites { allSites = sites.filter(\.isActive) }
    if let groups { allRuleGroups = groups }
    if let rss { rssSites = Set(rss) }
    if let idx { indexerSites = Set(idx) }
    if let sg { subscribeRuleGroups = Set(sg) }
    if let bg { bestVersionRuleGroups = Set(bg) }
    if let scg { searchRuleGroups = Set(scg) }
    if let src, !src.isEmpty {
      searchSources = Set(src.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }
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
      try await postSetting(
        "SEARCH_SOURCE", value: Array(searchSources).sorted().joined(separator: ","))
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

@MainActor
private struct NativeSiteScopePickerView: View {
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
                  HStack {
                    Text(site.name).font(.subheadline).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(site.id) {
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
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
      }
      .scrollIndicators(.hidden)
    }
    .navigationTitle(title)
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
    .toolbarBackground(.hidden, for: .navigationBar)
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
            ProgressView("正在读取下载器列表…").tint(.primary)
              .frame(maxWidth: .infinity, minHeight: 180)
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
                    HStack(spacing: 12) {
                      NativeBrandIcon(
                        kind: .downloader, type: item.type, size: 36, cornerRadius: 10)
                      VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                          Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(
                            .primary)
                          if item.isDefault {
                            NativeAdaptiveBadge("默认", tint: NativeTheme.brand)
                          }
                        }
                        Text("\(item.type) · \(item.hostSummary)")
                          .font(.caption2.monospaced())
                          .foregroundStyle(.secondary)
                          .lineLimit(1)
                      }
                      Spacer()
                      NativeAdaptiveBadge(
                        item.enabled ? "已启用" : "停用",
                        tint: item.enabled ? NativeTheme.success : nil)
                      Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.55))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
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
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "plus")
        }
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

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("名称", placeholder: "例如：qBittorrent", text: $name)
                CinematicFormDivider()
                HStack {
                  Text("类型").font(.subheadline)
                  Spacer()
                  Picker("类型", selection: $type) {
                    Text("qBittorrent").tag("qbittorrent")
                    Text("Transmission").tag("transmission")
                  }
                  .pickerStyle(.segmented)
                  .frame(width: 210)
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Toggle("启用下载器", isOn: $enabled)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Toggle("设为默认下载器", isOn: $isDefault)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
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
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
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
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .nativeAppearanceRoot()
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
            ProgressView("正在读取媒体服务器列表…").tint(.primary)
              .frame(maxWidth: .infinity, minHeight: 180)
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
                    HStack(spacing: 12) {
                      NativeBrandIcon(
                        kind: .mediaServer, type: item.type, size: 36, cornerRadius: 10)
                      VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(
                          .primary)
                        Text("\(item.type) · \(item.hostSummary)")
                          .font(.caption2.monospaced())
                          .foregroundStyle(.secondary)
                          .lineLimit(1)
                      }
                      Spacer()
                      NativeAdaptiveBadge(
                        item.enabled ? "已启用" : "停用",
                        tint: item.enabled ? NativeTheme.success : nil)
                      Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.55))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
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
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsCreateSheet = true
        } label: {
          Image(systemName: "plus")
        }
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
  private static let serverTypes: [(id: String, title: String)] = [
    ("emby", "Emby"), ("jellyfin", "Jellyfin"), ("plex", "Plex"),
    ("trimemedia", "飞牛影视"), ("ugreen", "绿联影视"), ("zspace", "极空间"),
    ("navidrome", "Navidrome"), ("mediavault", "MediaVault"),
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
          VStack(alignment: .leading, spacing: 16) {
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                rowField("名称", placeholder: "例如：客厅 Emby", text: $name)
                CinematicFormDivider()
                HStack {
                  Text("类型").font(.subheadline)
                  Spacer()
                  Picker("类型", selection: $type) {
                    ForEach(Self.serverTypes, id: \.id) { item in
                      Text(item.title).tag(item.id)
                    }
                  }
                  .pickerStyle(.menu)
                  .tint(appearance.accentColor)
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Toggle("启用服务器", isOn: $enabled)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
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
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
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
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .nativeAppearanceRoot()
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

// MARK: - 5. 播放偏好设置页（本机高频偏好）

@MainActor
struct NativePlaybackPreferencesPage: View {
  @AppStorage("nativeV2.playback.aspectFill") private var aspectFill = false
  @AppStorage("nativeV2.playback.defaultRate") private var defaultRate = 1.0
  @AppStorage("nativeV2.playback.preferChineseSub") private var preferChineseSub = true
  @AppStorage("nativeV2.playback.cellularWarn") private var cellularWarn = false
  @AppStorage("nativeV2.playback.keepMusicMiniBar") private var keepMusicMiniBar = true
  @ObservedObject private var appearance = NativeAppearanceStore.shared

  var body: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 7) {
            Text("视频播放").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
              .padding(.horizontal, 6)
            CinematicPanel(padding: 0) {
              VStack(spacing: 0) {
                HStack {
                  Text("默认画面模式").font(.subheadline)
                  Spacer()
                  Picker("画面模式", selection: $aspectFill) {
                    Text("自适应").tag(false)
                    Text("铺满屏幕").tag(true)
                  }
                  .pickerStyle(.segmented)
                  .frame(width: 170)
                }
                .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                HStack {
                  Text("默认播放倍速").font(.subheadline)
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
                .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Toggle("优先选择中文字幕", isOn: $preferChineseSub)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
                CinematicFormDivider()
                Toggle("移动网络播放前提醒", isOn: $cellularWarn)
                  .font(.subheadline).tint(appearance.accentColor)
                  .padding(.horizontal, 15).padding(.vertical, 10)
              }
            }
          }

          VStack(alignment: .leading, spacing: 7) {
            Text("音乐播放").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
              .padding(.horizontal, 6)
            CinematicPanel(padding: 0) {
              Toggle("返回时收起为悬浮迷你播放条", isOn: $keepMusicMiniBar)
                .font(.subheadline).tint(appearance.accentColor)
                .padding(.horizontal, 15).padding(.vertical, 10)
            }
          }
        }
        .frame(maxWidth: 740, alignment: .leading)
        .padding(.horizontal, CinematicStyle.margin).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("播放偏好")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
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
}

private struct NativeAuthChannel: Decodable, Sendable, Identifiable {
  let id: String
  let name: String
  let type: String
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
