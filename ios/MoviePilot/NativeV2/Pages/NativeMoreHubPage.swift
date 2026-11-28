import MoviePilotCore
import MoviePilotSession
import SwiftUI

/// 原生「更多」功能总枢纽：按三大业务分组承载资源媒体流转、插件与工作流以及紧凑长方形快捷诊断工具，右上角提供设置入口。
@MainActor
struct NativeMoreHubPage: View {
  let snapshot: NativeSessionSnapshot
  let currentLanguage: AppLanguage
  let onNavigate: (NativeWorkspaceDestination) -> Void
  let onOpenSettings: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var containerWidth: CGFloat = 0

  /// 单个更多入口磁贴描述。
  private struct HubTile: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void
  }

  /// 分组卡片集合描述。
  private struct HubSection: Identifiable {
    let id: String
    let title: String
    let isCompactDiagnostics: Bool
    let tiles: [HubTile]
  }

  /// 按当前界面语言解析固定文案。
  private func t(_ key: String) -> String {
    L10n.text(key, language: currentLanguage)
  }

  /// 媒体发现与识别权限。
  private var canDiscover: Bool {
    snapshot.user.allows(.init(category: .discovery))
  }

  /// 站点种子资源检索权限。
  private var canSearchResources: Bool {
    snapshot.user.allows(.init(category: .search))
  }

  /// 下载、文件、整理历史、站点与工作流管理权限。
  private var canManageDownloads: Bool {
    snapshot.user.isSuperuser || snapshot.user.allows(.init(category: .manage))
  }

  /// 自适应 2 / 3 / 4 列分组磁贴布局，顶部栏仅保留右侧齿轮设置入口。
  var body: some View {
    let resolvedWidth = NativeDeviceLayout.resolvedContainerWidth(containerWidth)
    let columnCount: Int =
      dynamicTypeSize.isAccessibilitySize
      ? 1
      : (resolvedWidth >= 980 ? 4 : (resolvedWidth >= 680 ? 3 : 2))
    let gridColumns = Array(
      repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
      count: columnCount
    )
    let compactDiagColumns = Array(
      repeating: GridItem(.flexible(), spacing: 9, alignment: .center),
      count: columnCount
    )
    let maxCanvasWidth: CGFloat =
      resolvedWidth >= 980 ? 1220 : (resolvedWidth >= 680 ? 960 : 760)

    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          ForEach(visibleSections) { section in
            VStack(alignment: .leading, spacing: 11) {
              Text(t(section.title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

              if section.isCompactDiagnostics {
                CinematicPanel(padding: 12, showsShadow: false) {
                  LazyVGrid(columns: compactDiagColumns, alignment: .leading, spacing: 9) {
                    ForEach(section.tiles) { tile in
                      diagnosticQuickPillButton(tile)
                    }
                  }
                }
              } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                  ForEach(section.tiles) { tile in
                    tileButton(tile)
                  }
                }
              }
            }
          }
        }
        .frame(maxWidth: maxCanvasWidth, alignment: .leading)
        .padding(.horizontal, NativeDeviceLayout.horizontalMargin(for: resolvedWidth))
        .padding(.top, 12)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
      }
      .nativeTrackContainerWidth($containerWidth)
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
      .accessibilityIdentifier("native-more-scroll")
    }
    .navigationTitle(t("更多"))
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onOpenSettings) {
          Image(systemName: "gearshape")
        }
        .tint(.primary)
        .accessibilityLabel(t("设置"))
        .accessibilityIdentifier("native-more-settings-btn")
      }
    }
  }

  /// 严格遵循 RBAC 门禁构建可见的三大业务分组。
  private var visibleSections: [HubSection] {
    var sections: [HubSection] = []

    // 1. 资源与媒体流转（冷静蓝青同系收束，视觉更像系统工作台而非杂色工具箱）
    var mediaFlowTiles: [HubTile] = []
    if canSearchResources {
      mediaFlowTiles.append(
        HubTile(
          id: "native-workspace-resources",
          title: "站点资源",
          subtitle: "多站搜索与精细筛选",
          symbol: "magnifyingglass.circle.fill",
          tint: NativeTheme.info
        ) { onNavigate(.resources) }
      )
    }
    if canManageDownloads {
      mediaFlowTiles.append(
        HubTile(
          id: "native-workspace-downloads",
          title: "下载管理",
          subtitle: "队列监控与限速控制",
          symbol: "arrow.down.circle.fill",
          tint: NativeTheme.cyan
        ) { onNavigate(.downloads) }
      )
      mediaFlowTiles.append(
        HubTile(
          id: "native-workspace-files",
          title: "文件管理",
          subtitle: "多存储浏览与整理播放",
          symbol: "folder.fill",
          tint: NativeTheme.info
        ) { onNavigate(.files) }
      )
      mediaFlowTiles.append(
        HubTile(
          id: "native-workspace-history",
          title: "整理历史",
          subtitle: "入库记录与手动重整理",
          symbol: "clock.arrow.circlepath",
          tint: NativeTheme.cyan
        ) { onNavigate(.history) }
      )
    }
    if !mediaFlowTiles.isEmpty {
      sections.append(
        HubSection(
          id: "media-flow",
          title: "资源与媒体流转",
          isCompactDiagnostics: false,
          tiles: mediaFlowTiles
        )
      )
    }

    // 2. 插件与工作流（单插件入口默认显示已安装插件，右上角切换插件市场）
    var automationTiles: [HubTile] = []
    if snapshot.user.isSuperuser {
      automationTiles.append(
        HubTile(
          id: "native-overflow-plugin-market",
          title: "插件中心",
          subtitle: "已安装管理与插件商店",
          symbol: "puzzlepiece.extension.fill",
          tint: NativeTheme.brand
        ) { onNavigate(.pluginMarket) }
      )
    }
    if canManageDownloads {
      automationTiles.append(
        HubTile(
          id: "native-workspace-workflows",
          title: "工作流",
          subtitle: "自动化流程与节点画布",
          symbol: "flowchart.fill",
          tint: NativeTheme.brand
        ) { onNavigate(.workflows) }
      )
    }
    if !automationTiles.isEmpty {
      sections.append(
        HubSection(
          id: "automation",
          title: "插件与工作流",
          isCompactDiagnostics: false,
          tiles: automationTiles
        )
      )
    }

    // 3. 快捷工具与系统诊断（克制中性与冷青收束，对齐系统诊断工具台）
    var diagTiles: [HubTile] = []
    if snapshot.user.isSuperuser {
      diagTiles.append(
        HubTile(
          id: "native-shortcut-系统检查",
          title: "系统检查",
          subtitle: "组件健康与运行状态",
          symbol: "checkmark.shield.fill",
          tint: NativeTheme.success
        ) { onNavigate(.diagnostics(.health)) }
      )
      diagTiles.append(
        HubTile(
          id: "native-shortcut-定时服务",
          title: "定时服务",
          subtitle: "后台任务查看与触发",
          symbol: "clock.arrow.2.circlepath",
          tint: NativeTheme.info
        ) { onNavigate(.diagnostics(.scheduler)) }
      )
      diagTiles.append(
        HubTile(
          id: "native-shortcut-实时日志",
          title: "实时日志",
          subtitle: "结构化查看与级别过滤",
          symbol: "terminal.fill",
          tint: NativeTheme.cyan
        ) { onNavigate(.diagnostics(.liveLog)) }
      )
      diagTiles.append(
        HubTile(
          id: "native-shortcut-词表",
          title: "词表管理",
          subtitle: "识别词、屏蔽词与规则",
          symbol: "character.book.closed.fill",
          tint: NativeTheme.brand
        ) { onNavigate(.diagnostics(.words)) }
      )
    }
    if canDiscover || snapshot.user.isSuperuser {
      diagTiles.append(
        HubTile(
          id: "native-shortcut-识别与规则",
          title: "识别与规则",
          subtitle: "名称识别与规则验证",
          symbol: "text.magnifyingglass",
          tint: NativeTheme.info
        ) { onNavigate(.diagnostics(.ruleTest)) }
      )
    }
    if snapshot.user.isSuperuser {
      diagTiles.append(
        HubTile(
          id: "native-shortcut-网络测试",
          title: "网络测试",
          subtitle: "自动测速与连通检测",
          symbol: "network",
          tint: NativeTheme.cyan
        ) { onNavigate(.diagnostics(.nettest)) }
      )
    }
    if !diagTiles.isEmpty {
      sections.append(
        HubSection(
          id: "diagnostics",
          title: "快捷工具与系统诊断",
          isCompactDiagnostics: true,
          tiles: diagTiles
        )
      )
    }

    return sections
  }

  /// 常规业务分组的透色毛玻璃磁贴卡片：克制低噪边、同心圆角图标徽章 + 加粗标题 + 单行次级摘要。
  private func tileButton(_ tile: HubTile) -> some View {
    let isLight = colorScheme == .light
    return Button(action: tile.action) {
      CinematicPanel(padding: 14, cornerRadius: 20, style: .subtle) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .center) {
            ZStack {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tile.tint.opacity(isLight ? 0.13 : 0.16))
                .overlay {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tile.tint.opacity(isLight ? 0.22 : 0.26), lineWidth: 0.6)
                }
              Image(systemName: tile.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tile.tint)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary.opacity(0.45))
              .accessibilityHidden(true)
          }

          VStack(alignment: .leading, spacing: 3) {
            Text(t(tile.title))
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.88)

            Text(t(tile.subtitle))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
      }
      .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(t(tile.title))，\(t(tile.subtitle))")
    .accessibilityIdentifier(tile.id)
  }

  /// 快捷诊断工具紧凑横向长方形卡片（对齐 Android `DiagnosticQuickPill` 扁平矩形布局）。
  private func diagnosticQuickPillButton(_ tile: HubTile) -> some View {
    let isLight = colorScheme == .light
    return Button(action: tile.action) {
      HStack(spacing: 9) {
        Image(systemName: tile.symbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(tile.tint)
          .frame(width: 22, height: 22)
          .accessibilityHidden(true)

        Text(t(tile.title))
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.86)

        Spacer(minLength: 2)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(
            isLight
              ? Color.black.opacity(0.045)
              : Color.white.opacity(0.065)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(
                isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.09),
                lineWidth: 0.6
              )
          }
      }
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(t(tile.title))，\(t(tile.subtitle))")
    .accessibilityIdentifier(tile.id)
  }
}
