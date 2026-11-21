import Foundation
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生设置主中心（底部「设置」标签）：融合顶部空间概览卡、双列状态方卡（站点管理/用户管理）、高亮横幅入口卡、4 列图标瓷砖与原生分组列表，保持多样化视觉层次。
@MainActor
struct NativeSettingsHubPage<AccountContent: View>: View {
  let session: NativeSession
  let snapshot: NativeSessionSnapshot
  let onNavigate: (NativeWorkspaceDestination) -> Void
  let onOpenModules: () -> Void
  let onOpenPlugins: () -> Void
  let accountContent: AccountContent

  @State private var storage: NativeSettingsStorageBrief?
  @State private var siteCount: Int?
  @State private var showsNotificationSettings = false
  @State private var showsWidgetSettings = false

  /// 连续紫玫瑰渐变背景与多样化层级布局：概览条卡 → 双列状态方卡 → 高亮横幅卡 → 4 列图标瓷砖 → 原生分组列表 → 账号管理。
  var body: some View {
    ZStack {
      CinematicBackground()
      Form {
        headerTitle
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 8, trailing: 2))
          .listRowSeparator(.hidden)

        storageTelemetryCard
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
          .listRowSeparator(.hidden)

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

          systemListSection
        } else {
          standardUserGrid
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)
          systemIntegrationSection
        }

        accountContent
      }
      .scrollContentBackground(.hidden)
      .scrollIndicators(.hidden)
      .frame(maxWidth: 740)
      .frame(maxWidth: .infinity)
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .sheet(isPresented: $showsNotificationSettings) {
      NativeNotificationSettingsSheet(session: session)
    }
    .sheet(isPresented: $showsWidgetSettings) {
      NativeWidgetSettingsSheet(session: session)
    }
    .task(id: snapshot.scope) { await loadOverview() }
  }

  /// 顶部浮于渐变之上的大号「设置」标题。
  private var headerTitle: some View {
    Text("设置")
      .font(.largeTitle.bold())
      .foregroundStyle(.white)
      .padding(.horizontal, 2)
      .accessibilityAddTraits(.isHeader)
  }

  /// 第一层：顶部全宽空间与实例概览条卡（分段彩色容量条 + 状态图例）。
  private var storageTelemetryCard: some View {
    let usedRatio = storage?.usedRatio ?? 0.64
    let host = session.instance.address.url.host ?? session.instance.address.url.absoluteString
    return CinematicPanel(padding: 16) {
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .firstTextBaseline) {
          Text(storage != nil ? "存储空间" : "当前服务实例")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.68))
          Spacer(minLength: 8)
          if let storage {
            Text("\(Self.formatBytes(storage.used)) / \(Self.formatBytes(storage.total))")
              .font(.subheadline.monospacedDigit().weight(.semibold))
              .foregroundStyle(.white)
          } else {
            HStack(spacing: 5) {
              Circle()
                .fill(Color(red: 0.42, green: 0.88, blue: 0.56))
                .frame(width: 7, height: 7)
              Text(host)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
            }
          }
        }

        GeometryReader { bar in
          let w = max(bar.size.width, 1)
          let primary = min(max(usedRatio, 0.14), 0.82)
          let secondary = min(0.08, max(0.03, (1 - primary) * 0.22))
          let tertiary = min(0.05, max(0.02, (1 - primary) * 0.14))
          HStack(spacing: 2.5) {
            Capsule()
              .fill(
                LinearGradient(
                  colors: [
                    Color(red: 0.98, green: 0.58, blue: 0.24),
                    Color(red: 0.95, green: 0.48, blue: 0.34),
                  ],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .frame(width: w * primary)
            Capsule()
              .fill(Color(red: 0.30, green: 0.64, blue: 0.98))
              .frame(width: w * secondary)
            Capsule()
              .fill(Color(red: 0.32, green: 0.82, blue: 0.56))
              .frame(width: w * tertiary)
            Capsule()
              .fill(.white.opacity(0.18))
          }
        }
        .frame(height: 12)

        HStack(spacing: 14) {
          legendDot("媒体已用", color: Color(red: 0.98, green: 0.56, blue: 0.26))
          legendDot("索引与缓存", color: Color(red: 0.30, green: 0.64, blue: 0.98))
          legendDot("服务在线", color: Color(red: 0.32, green: 0.82, blue: 0.56))
          Spacer(minLength: 0)
          Text(snapshot.user.name)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
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

  /// 第三层：高亮横幅入口卡（高对比度白色胶囊按钮），集中承接核心系统设置。
  private var featuredSystemBanner: some View {
    CinematicPanel(padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 8) {
          Image(systemName: "sparkles")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
          Text("系统核心参数")
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
          Spacer(minLength: 8)
          Text("高级项见 Web 后台")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
        Text("快速调整媒体识别、订阅策略与定时缓存，保持移动端轻量高效。")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.76))
          .fixedSize(horizontal: false, vertical: true)

        Button {
          onNavigate(.settings)
        } label: {
          Text("进入系统设置")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.16))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("native-workspace-settings")
      }
    }
  }

  /// 第四层：4 列紧凑玻璃图标瓷砖（高频捷径与诊断：系统检查、网络测试、识别规则、实时日志）。
  private var appPreferenceTiles: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("捷径与诊断")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white.opacity(0.68))
        .padding(.horizontal, 2)
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
    VStack(alignment: .leading, spacing: 10) {
      Text("常用配置")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white.opacity(0.68))
        .padding(.horizontal, 2)
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
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white)
              .lineLimit(1)
            Text(subtitle)
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.62))
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

  /// 第五层：原生分组列表项（与上方卡片和瓷砖形成层次对比，平滑衔接到账号设置列表）。
  private var systemListSection: some View {
    CinematicFormSection(
      "使用偏好与目录",
      footer: "复杂过滤规则与底层高级参数可随时在 MoviePilot Web 管理界面中调整。"
    ) {
      nativeListRow(
        title: "目录与存储映射", symbol: "folder.badge.gearshape",
        id: "native-settings-hub-directories"
      ) {
        onNavigate(.systemModule(.directories))
      }
      nativeListRow(
        title: "刮削开关", symbol: "wand.and.stars",
        id: "native-settings-hub-scraping"
      ) {
        onNavigate(.systemModule(.scraping))
      }
      nativeListRow(
        title: "发现模块顺序", symbol: "square.grid.2x2",
        id: "native-settings-hub-modules"
      ) {
        onOpenModules()
      }
      nativeListRow(
        title: "插件市场", symbol: "puzzlepiece.extension",
        id: "native-workspace-plugin-market"
      ) {
        onNavigate(.pluginMarket)
      }
      nativeListRow(
        title: "已安装插件配置", symbol: "slider.horizontal.3",
        id: "native-settings-hub-plugins"
      ) {
        onOpenPlugins()
      }
      nativeListRow(
        title: "系统推送通知", symbol: "bell.and.waves.left.and.right",
        id: "native-settings-hub-push"
      ) {
        showsNotificationSettings = true
      }
      nativeListRow(
        title: "桌面小组件", symbol: "rectangle.3.group",
        id: "native-settings-hub-widgets"
      ) {
        showsWidgetSettings = true
      }
    }
  }

  /// 普通成员系统集成列表（推送通知与桌面小组件）。
  private var systemIntegrationSection: some View {
    CinematicFormSection("系统集成") {
      nativeListRow(
        title: "系统推送通知", symbol: "bell.and.waves.left.and.right",
        id: "native-settings-hub-push"
      ) {
        showsNotificationSettings = true
      }
      nativeListRow(
        title: "桌面小组件", symbol: "rectangle.3.group",
        id: "native-settings-hub-widgets"
      ) {
        showsWidgetSettings = true
      }
    }
  }

  /// 普通成员可见的精简入口。
  private var standardUserGrid: some View {
    HStack(spacing: 12) {
      squareStatusCard(
        title: "发现模块",
        statusText: "首页顺序与显隐",
        symbol: "square.grid.2x2.fill",
        tint: Color(red: 0.62, green: 0.50, blue: 0.96),
        statusColor: Color(red: 0.48, green: 0.90, blue: 0.66),
        id: "native-settings-hub-modules"
      ) {
        onOpenModules()
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
          VStack(alignment: .leading, spacing: 4) {
            Text(title)
              .font(.headline)
              .foregroundStyle(.white)
              .lineLimit(1)
            HStack(spacing: 5) {
              Circle().fill(statusColor).frame(width: 6, height: 6)
              Text(statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
            }
          }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
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
        VStack(spacing: 8) {
          Image(systemName: symbol)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white.opacity(0.92))
            .frame(height: 26)
          Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 68)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 原生 Form 分组列表行，带图标与右侧指示箭头。
  private func nativeListRow(
    title: String, symbol: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.body.weight(.medium))
          .foregroundStyle(.white.opacity(0.86))
          .frame(width: 24)
        Text(title)
          .font(.body)
          .foregroundStyle(.white)
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.38))
      }
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
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
    }
  }

  /// 静默拉取存储空间与站点数量供顶部概览与状态方卡展示，失败时不干扰设置入口交互。
  private func loadOverview() async {
    guard snapshot.user.isSuperuser else { return }
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
