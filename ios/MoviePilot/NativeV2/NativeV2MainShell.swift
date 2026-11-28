import CryptoKit
import ImageIO
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 已认证 MoviePilot 的原生主导航：统一 4+1 主架构（发现 / 订阅 / 我的 / 更多 + 右侧独立动态或全局搜索按钮），跨 iPhone、iPad 与 iPhone Duo 自适应呈现。
@MainActor
struct NativeV2MainShell<PluginDestination: View>: View {
  /// 主导航目的地：iPhone 为 4+1 底部架构，iPad 额外扩展侧栏工作台直达入口，iPhone Duo 通过系统竖向侧边操作区切换。
  private enum Page: Hashable {
    case discover
    case subscriptions
    case mine
    case more
    case search
    case sidebarWorkspace(NativeWorkspaceDestination)
  }

  let session: NativeSession
  let snapshot: NativeSessionSnapshot
  @Binding var showsPlugins: Bool
  let currentLanguage: AppLanguage
  let onSelectLanguage: (AppLanguage) -> Void
  let onSwitchServer: () -> Void
  let onLogout: () -> Void
  let pluginDestination: () -> PluginDestination

  @StateObject private var dynamicActionCenter = NativeDynamicActionCenter()
  @ObservedObject private var routeHub = NativeSystemRouteHub.shared
  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @ObservedObject private var playbackLauncher = NativeMediaPlaybackLauncher.shared
  @ObservedObject private var pluginCapsuleManager = PluginCapsuleManager.shared
  @Environment(\.verticalSizeClass) private var verticalSizeClass
  @Environment(\.nativeVerticalBarEdge) private var verticalBarEdge
  @State private var selectedTab: Page = .discover
  @State private var discovery = NativeDiscoverContent(
    featured: nil, rails: [], continueWatching: [], providers: [], categories: [], isLoading: true)
  @State private var discoveryGeneration = UUID()
  @State private var discoveryAttempt = 0
  @State private var mediaIdentities: [String: NativeMediaIdentity] = [:]
  @State private var musicSeeds: [String: NativeMusicCardItem] = [:]
  @State private var mediaServerItems: [String: MediaServerNavigationTarget] = [:]
  @State private var pendingSearchQuery: String?
  @State private var pendingSearchKind: String?
  @State private var pendingSubscriptionFilter: NativeSubscriptionsPage.Filter?
  @State private var pendingAgentPrompt = ""
  @State private var discoverPath: [NativeMediaDestination] = []
  @State private var subscriptionsPath: [NativeWorkspaceDestination] = []
  @State private var minePath: [NativeWorkspaceDestination] = []
  @State private var morePath: [NativeWorkspaceDestination] = []
  @State private var searchPath: [NativeMediaIdentity] = []
  private struct DeepLinkPluginTarget: Identifiable {
    let id = UUID()
    let pluginID: String
    let surface: String?
  }

  @State private var showsAgentSheet = false
  @State private var showsPetPickerSheet = false
  @State private var showsMessagesSheet = false
  @State private var restoredCapsuleSheetTarget: MinimizedPluginSession?
  @State private var deepLinkPluginTarget: DeepLinkPluginTarget?
  @State private var userTabAvatar: UIImage?
  @State private var userTabAvatarInactive: UIImage?
  @AppStorage("nativeV2.showFloatingAssistant") private var showFloatingAssistant = true
  @State private var discoverModules = NativeDiscoverModuleItem.defaults
  @State private var extraRecommendSources: [RecommendSource] = []
  @State private var showsModuleSheet = false
  @State private var pendingModuleRefetch = false
  @State private var latestServerName: String?
  @State private var railNextPage: [String: Int] = [:]
  @State private var loadingRailIDs: Set<String> = []
  @State private var lastTrailingActionAt: Date = .distantPast
  @State private var hasLoadedDiscoveryOnce = false
  @State private var launchSplashTimedOut = false

  /// 首次进入发现页前保持与系统 LaunchScreen 一致的居中 Logo 启动屏，彻底消除首屏加载空窗与浮动控件闪烁。
  private var showsLaunchSplash: Bool {
    canDiscover && !hasLoadedDiscoveryOnce && !launchSplashTimedOut
  }

  /// 按当前界面语言实时解析文案。
  private func t(_ key: String) -> String {
    L10n.text(key, language: currentLanguage)
  }

  /// 保留 root 原有账号动作与插件路由，主导航由系统 TabView 承载各标签独立栈。
  init(
    session: NativeSession, snapshot: NativeSessionSnapshot,
    showsPlugins: Binding<Bool>,
    currentLanguage: AppLanguage,
    onSelectLanguage: @escaping (AppLanguage) -> Void,
    onSwitchServer: @escaping () -> Void,
    onLogout: @escaping () -> Void,
    @ViewBuilder pluginDestination: @escaping () -> PluginDestination
  ) {
    self.session = session
    self.snapshot = snapshot
    _showsPlugins = showsPlugins
    self.currentLanguage = currentLanguage
    self.onSelectLanguage = onSelectLanguage
    self.onSwitchServer = onSwitchServer
    self.onLogout = onLogout
    self.pluginDestination = pluginDestination
    _selectedTab = State(
      initialValue: snapshot.user.allows(.init(category: .discovery)) ? .discover : .mine)
  }

  /// 主导航交给系统 TabView 和每页独立 NavigationStack，并注入跨栈动态主按钮中心与浮动智能助手形象。
  var body: some View {
    ZStack {
      if showsLaunchSplash {
        NativeLaunchSplashView()
          .transition(.opacity)
          .zIndex(100)
      } else {
        page
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
        if usesLegacyFloatingTabBar {
          legacyFloatingTabBarOverlay
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .zIndex(40)
        }
        if let miniMusic = playbackLauncher.miniMusicState {
          floatingMiniMusicBar(miniMusic)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(45)
        }
        if pluginCapsuleManager.currentSession != nil && restoredCapsuleSheetTarget == nil {
          NativePluginFloatingCapsuleOverlay(manager: pluginCapsuleManager) { sessionToRestore in
            restoredCapsuleSheetTarget = sessionToRestore
          }
          .zIndex(46)
        }
        // 全界面 Agent 助手形象宿主（独立穿透 UIWindow 覆盖主 Tab 与全部二级子页面；底部安全边界恒定不随子页跳动，任意弹窗弹出自动避让并在关闭后 0ms 恢复）
        if showFloatingAssistant && !usesDuoSideOperationBar && !playbackLauncher.hasActivePlayer {
          NativeAgentPetOverlayHost(
            session: session,
            petStore: NativeAgentPetStore.shared(for: session),
            isVisible: !showsMessagesSheet && !showsPetPickerSheet && !showsModuleSheet && restoredCapsuleSheetTarget == nil && deepLinkPluginTarget == nil,
            panelOpen: showsAgentSheet,
            dockVisible: !NativeDeviceLayout.isIPad && !usesDuoSideOperationBar,
            thinking: NativeAgentChatStore.shared(for: session).isSending,
            onOpenAgent: { draft in
              if let draft, !draft.isEmpty {
                pendingAgentPrompt = draft
              }
              showsAgentSheet = true
            },
            onCloseAgent: {
              showsAgentSheet = false
            },
            onOpenPetPicker: {
              showsPetPickerSheet = true
            },
            onHideFloating: {
              showFloatingAssistant = false
            }
          )
          .zIndex(48)
        }
        if let banner = routeHub.bannerMessage {
          systemBannerOverlay(banner)
        }
      }
    }
    .animation(.easeOut(duration: 0.24), value: showsLaunchSplash)
    .task {
      guard canDiscover else { return }
      try? await Task.sleep(for: .seconds(8))
      if !Task.isCancelled {
        launchSplashTimedOut = true
      }
    }
    .onChange(of: currentLanguage) { _ in
      if canDiscover {
        discoveryAttempt += 1
      }
    }
    .environmentObject(dynamicActionCenter)
    .onAppear { consumeSystemRouteIfNeeded() }
    .onChange(of: routeHub.pendingTarget) { _ in consumeSystemRouteIfNeeded() }
    .onChange(of: pluginCapsuleManager.restoreRequestNonce) { _ in
      if let target = pluginCapsuleManager.currentSession {
        restoredCapsuleSheetTarget = target
      }
    }
    .sheet(isPresented: $showsPetPickerSheet) {
      NativeAgentPetPickerSheet(
        session: session,
        petStore: NativeAgentPetStore.shared(for: session)
      )
    }
    .sheet(item: $restoredCapsuleSheetTarget) { restored in
      NativeVuePluginSheet(
        session: session,
        pluginID: restored.pluginID,
        pluginName: restored.pluginName,
        surface: restored.surface,
        pluginHasPage: restored.pluginHasPage
      )
    }
    .sheet(item: $deepLinkPluginTarget) { target in
      if target.surface?.lowercased() == "config" {
        NativeVuePluginSheet(
          session: session,
          pluginID: target.pluginID,
          pluginName: target.pluginID,
          surface: .config,
          pluginHasPage: true
        )
      } else {
        NavigationStack {
          NativePluginDataPageView(
            session: session,
            pluginID: target.pluginID,
            pluginName: target.pluginID
          )
        }
      }
    }
    .task(id: "\(snapshot.scope)|\(snapshot.user.avatar)") {
      let pair = await NativeUserAvatarRenderer.loadTabAvatarPair(
        session: session, avatar: snapshot.user.avatar)
      userTabAvatar = pair?.active
      userTabAvatarInactive = pair?.inactive
    }
    .sheet(isPresented: $showsMessagesSheet) {
      NavigationStack {
        NativeMessagesPage(session: session)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button {
                showsMessagesSheet = false
              } label: {
                Image(systemName: "xmark")
              }
              .tint(.primary)
              .accessibilityLabel("关闭")
              .accessibilityIdentifier("native-messages-sheet-close")
            }
          }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .nativeAdaptiveSheetSizing()
      .nativeGlassSheet()
    }
    .sheet(
      isPresented: $showsAgentSheet,
      onDismiss: { pendingAgentPrompt = "" }
    ) {
      NavigationStack {
        NativeAgentChatPage(session: session, initialPrompt: pendingAgentPrompt)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button {
                showsAgentSheet = false
              } label: {
                Image(systemName: "xmark")
              }
              .tint(.primary)
              .accessibilityLabel("关闭")
              .accessibilityIdentifier("native-agent-sheet-close")
            }
          }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .nativeAdaptiveSheetSizing()
      .nativeGlassSheet()
    }
    .sheet(
      isPresented: $showsModuleSheet,
      onDismiss: {
        if pendingModuleRefetch {
          pendingModuleRefetch = false
          discoveryAttempt += 1
        }
      }
    ) {
      NativeDiscoverModulesSheet(initialModules: discoverModules) { updated in
        await saveDiscoverModules(updated)
      }
      .nativeAdaptiveSheetSizing()
    }
    .task(id: canDiscover ? discoveryAttempt : nil) {
      if canDiscover {
        await loadDiscovery(forceRefresh: discoveryAttempt > 0)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .moviePilotPlaybackDidStop)) { _ in
      guard canDiscover else { return }
      Task { await loadDiscovery(forceRefresh: true) }
    }
    .onChange(of: snapshot.user.permissions) { _ in
      if !canDiscover {
        discovery = NativeDiscoverContent(
          featured: nil, rails: [], continueWatching: [], providers: [], categories: [])
        mediaIdentities = [:]
        discoverPath = []
        searchPath = []
        if selectedTab == .discover || selectedTab == .search {
          selectedTab = .mine
        }
      }
      if !canSubscribe {
        subscriptionsPath = []
        if selectedTab == .subscriptions {
          selectedTab = .mine
        }
      }
    }
  }

  /// 仅在一级根 Tab 停留时展示浮动助手，推入详情、设置、插件或工作流画布后自动隐藏以免遮挡内容与按钮。
  private var isAtRootNavigationLevel: Bool {
    switch selectedTab {
    case .discover: discoverPath.isEmpty
    case .subscriptions: subscriptionsPath.isEmpty
    case .mine: minePath.isEmpty
    case .more: morePath.isEmpty && !showsPlugins
    case .search: searchPath.isEmpty
    case .sidebarWorkspace: false
    }
  }

  /// 当前「我的」底栏显示头像：未选中态轻度降饱和融入单色图标群，选中态呈现全彩高亮。
  private var displayedMineTabAvatar: UIImage? {
    selectedTab == .mine ? userTabAvatar : (userTabAvatarInactive ?? userTabAvatar)
  }

  /// 影视发现、探索、媒体搜索与详情沿用现有发现权限，PT 资源搜索属于单独的权限。
  private var canDiscover: Bool { snapshot.user.allows(.init(category: .discovery)) }

  /// 订阅管理与追剧日历遵循订阅权限门禁。
  private var canSubscribe: Bool { snapshot.user.allows(.init(category: .subscribe)) }

  /// PT 站点资源搜索遵循独立搜索权限门禁。
  private var canSearchResources: Bool { snapshot.user.allows(.init(category: .search)) }

  /// 下载任务管理遵循管理员或管理权限门禁。
  private var canManageDownloads: Bool {
    snapshot.user.isSuperuser || snapshot.user.allows(.init(category: .manage))
  }

  /// 当前右下角独立按钮是否被页面动态动作接管（无动态动作时固定为全局搜索按钮）。
  private var hasTrailingCustomAction: Bool {
    dynamicActionCenter.current != nil
  }

  /// 执行右下角自定义动作（内置 180ms 防抖，防止 UIKit 代理拦截与 SwiftUI 绑定重复触发）。
  private func triggerTrailingCustomAction() {
    let now = Date()
    guard now.timeIntervalSince(lastTrailingActionAt) > 0.18 else { return }
    lastTrailingActionAt = now
    if let dynamic = dynamicActionCenter.current {
      dynamic.handler()
    }
  }

  /// 是否启用 iPhone Duo 系统竖向侧边操作区（替代传统底部导航栏，并在硬件折叠或退出竖向模式时自动平滑回退）。
  private var usesDuoSideOperationBar: Bool {
    NativeDeviceLayout.isIPhoneDuoHardware && verticalBarEdge.isActive
  }

  /// iPhone 在 iOS 26 以下使用自定义 4+1 悬浮毛玻璃胶囊底部栏替代扁平系统标签栏。
  private var usesLegacyFloatingTabBar: Bool {
    if #available(iOS 26, *) {
      return false
    }
    return !NativeDeviceLayout.isIPad && !usesDuoSideOperationBar
  }

  /// 自定义悬浮胶囊底栏为滚动内容预留的底部安全余量。
  private var legacyTabBarReservedHeight: CGFloat {
    isCompactPhoneLandscape ? 58 : 72
  }

  /// 构造 iOS 26 以下 iPhone 的 4+1 悬浮毛玻璃胶囊底部栏覆盖层（发现 / 订阅 / 我的 / 更多 + 搜索）。
  private var legacyFloatingTabBarOverlay: some View {
    var items: [NativeLegacyFloatingTabItem] = []
    if canDiscover {
      items.append(
        NativeLegacyFloatingTabItem(
          id: "discover",
          title: t("发现"),
          symbol: "DiscoverCardsOutline",
          activeSymbol: "DiscoverCards",
          isAssetImage: true,
          isAvatar: false,
          accessibilityID: "native-v2-tab-发现",
          isSelected: selectedTab == .discover,
          action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
              tabSelection.wrappedValue = .discover
            }
          }
        )
      )
    }
    if canSubscribe {
      items.append(
        NativeLegacyFloatingTabItem(
          id: "subscriptions",
          title: t("订阅"),
          symbol: "bookmark",
          activeSymbol: "bookmark.fill",
          isAvatar: false,
          accessibilityID: "native-v2-tab-订阅",
          isSelected: selectedTab == .subscriptions,
          action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
              tabSelection.wrappedValue = .subscriptions
            }
          }
        )
      )
    }
    items.append(
      NativeLegacyFloatingTabItem(
        id: "mine",
        title: t("我的"),
        symbol: "person.crop.circle",
        activeSymbol: "person.crop.circle.fill",
        isAvatar: true,
        accessibilityID: "native-v2-tab-我的",
        isSelected: selectedTab == .mine,
        action: {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            tabSelection.wrappedValue = .mine
          }
        }
      )
    )
    items.append(
      NativeLegacyFloatingTabItem(
        id: "more",
        title: t("更多"),
        symbol: "square.grid.2x2",
        activeSymbol: "square.grid.2x2.fill",
        isAvatar: false,
        accessibilityID: "native-v2-tab-更多",
        isSelected: selectedTab == .more,
        action: {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            tabSelection.wrappedValue = .more
          }
        }
      )
    )
    return NativeLegacyFloatingTabBar(
      items: items,
      userTabAvatar: displayedMineTabAvatar,
      showsTrailingButton: canDiscover || hasTrailingCustomAction,
      trailingTitle: hasTrailingCustomAction ? trailingButtonTitle : t("搜索"),
      trailingSymbol: trailingButtonSymbol,
      isTrailingActive: selectedTab == .search || hasTrailingCustomAction,
      isCompactLandscape: isCompactPhoneLandscape,
      onTrailingAction: {
        if hasTrailingCustomAction {
          triggerTrailingCustomAction()
        } else {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            tabSelection.wrappedValue = .search
          }
        }
      }
    )
  }

  /// 主标签选择绑定：切换主标签时重置跨栈动态主按钮，二次点击当前标签退回栈根。
  private var tabSelection: Binding<Page> {
    Binding(
      get: { selectedTab },
      set: { next in
        if next == .search, hasTrailingCustomAction {
          triggerTrailingCustomAction()
          return
        }
        if next == selectedTab {
          dynamicActionCenter.reset()
          switch next {
          case .discover:
            discoverPath = []
          case .subscriptions:
            subscriptionsPath = []
          case .mine:
            minePath = []
          case .more:
            morePath = []
            showsPlugins = false
          case .search:
            searchPath = []
          case .sidebarWorkspace:
            break
          }
        } else {
          dynamicActionCenter.reset()
          selectedTab = next
        }
      })
  }

  /// 拦截 iPhone 上右下角动态自定义按钮的点击；不再拦截重复点击主标签，iOS 26 以下同步隐藏系统灰底标签栏。
  @ViewBuilder
  private var tabReselectInterceptor: some View {
    if !usesDuoSideOperationBar && !NativeDeviceLayout.isIPad {
      NativeTabBarReselectInterceptor(
        hidesSystemTabBar: usesLegacyFloatingTabBar,
        shouldInterceptReselect: { false },
        onReselect: {},
        shouldInterceptTrailingTab: { hasTrailingCustomAction },
        onSelectTrailingTab: { triggerTrailingCustomAction() }
      )
      .frame(width: 0, height: 0)
      .allowsHitTesting(false)
    }
  }

  /// 右侧 +1 圆形按钮标题：页面动态动作 > 全局搜索。
  private var trailingButtonTitle: String {
    if let dynamic = dynamicActionCenter.current { return dynamic.title }
    return "搜索"
  }

  /// 右侧 +1 圆形按钮图标：页面动态动作 > 放大镜。
  private var trailingButtonSymbol: String {
    if let dynamic = dynamicActionCenter.current { return dynamic.symbol }
    return "magnifyingglass"
  }

  /// 右侧独立圆形按钮角色：Xcode 27+（Swift 6.4+ / iOS 27+）使用 `.prominent` 确保始终与主导航胶囊分离成独立圆形玻璃键，旧 SDK 与 iOS 18-26 沿用 `.search`。
  @available(iOS 18, *)
  private var trailingTabRole: TabRole {
    #if compiler(>=6.4)
      if #available(iOS 27.0, *) {
        return .prominent
      }
    #endif
    return .search
  }

  /// 跨形态主导航：iPhone Duo 使用系统竖向侧边操作区壳层；iPad 使用 iPadOS 18+ `sidebarAdaptable` 顶部浮动栏 + 可展开侧边工作台；iPhone 保持 4+1 底部玻璃胶囊架构。
  @ViewBuilder private var page: some View {
    if usesDuoSideOperationBar {
      duoSideOperationShell
    } else if #available(iOS 18, *), NativeDeviceLayout.isIPad {
      iPadSidebarAdaptableShell
    } else if #available(iOS 18, *) {
      iPhoneModernTabShell
    } else {
      legacyTabShell
    }
  }

  /// iPhone Duo 专属壳层：移除底部/顶部标签栏，由各根页面的系统竖向侧边操作区直接承载 4+1 主导航、智能助手与上下文动态主动作。
  @ViewBuilder private var duoSideOperationShell: some View {
    switch selectedTab {
    case .discover:
      if canDiscover {
        discoveryTab
      } else {
        mineTab
      }
    case .subscriptions:
      if canSubscribe {
        subscriptionsTab
      } else {
        mineTab
      }
    case .mine:
      mineTab
    case .more:
      moreTab
    case .search:
      if canDiscover {
        searchTab
      } else {
        mineTab
      }
    case .sidebarWorkspace(let destination):
      sidebarWorkspaceTab(destination)
    }
  }

  /// iPhone Duo 根页面竖向侧边操作栏：充分利用侧边纵向空间集中放置发现、订阅、我的、更多、智能助手与底部动态动作/全局搜索。
  @ToolbarContentBuilder
  private var duoSideOperationToolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .bottomBar) {
      if canDiscover {
        // 发现入口使用素材目录中的模板矢量图（DiscoverCards），与底栏其他入口一样选中实心、未选中描边。
        Button {
          selectDuoRootTab(.discover)
        } label: {
          Label(t("发现"), image: selectedTab == .discover ? "DiscoverCards" : "DiscoverCardsOutline")
        }
        .tint(selectedTab == .discover ? appearance.accentColor : .primary)
        .accessibilityLabel(t("发现"))
        .accessibilityAddTraits(selectedTab == .discover ? .isSelected : [])
        .accessibilityIdentifier("native-v2-tab-发现")
      }
      if canSubscribe {
        duoNavToolbarButton(
          title: t("订阅"),
          symbol: selectedTab == .subscriptions ? "bookmark.fill" : "bookmark",
          isSelected: selectedTab == .subscriptions,
          id: "native-v2-tab-订阅"
        ) {
          selectDuoRootTab(.subscriptions)
        }
      }
      Button {
        selectDuoRootTab(.mine)
      } label: {
        if let avatar = displayedMineTabAvatar {
          Label {
            Text(t("我的"))
          } icon: {
            Image(uiImage: avatar)
          }
        } else {
          Label(
            t("我的"),
            systemImage: selectedTab == .mine ? "person.crop.circle.fill" : "person.crop.circle")
        }
      }
      .tint(selectedTab == .mine ? appearance.accentColor : .primary)
      .accessibilityLabel(t("我的"))
      .accessibilityAddTraits(selectedTab == .mine ? .isSelected : [])
      .accessibilityIdentifier("native-v2-tab-我的")

      duoNavToolbarButton(
        title: t("更多"),
        symbol: selectedTab == .more ? "square.grid.2x2.fill" : "square.grid.2x2",
        isSelected: selectedTab == .more,
        id: "native-v2-tab-更多"
      ) {
        selectDuoRootTab(.more)
      }

      duoNavToolbarButton(
        title: t("助手"),
        symbol: "text.bubble",
        isSelected: showsAgentSheet,
        id: "native-duo-agent"
      ) {
        showsAgentSheet = true
      }

      if canDiscover || hasTrailingCustomAction {
        Spacer()
        duoNavToolbarButton(
          title: hasTrailingCustomAction ? trailingButtonTitle : t("搜索"),
          symbol: trailingButtonSymbol,
          isSelected: hasTrailingCustomAction || selectedTab == .search,
          id: "native-v2-search-tab-item"
        ) {
          if hasTrailingCustomAction {
            triggerTrailingCustomAction()
          } else {
            selectDuoRootTab(.search)
          }
        }
      }
    }
    .nativeDuoVerticalPreferred()
  }

  /// iPhone Duo 侧边操作区单个导航/工具按钮：选中态自动以主题强调色高亮，提供完整可访问性标签与标识。
  private func duoNavToolbarButton(
    title: String,
    symbol: String,
    isSelected: Bool,
    id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
    }
    .tint(isSelected ? appearance.accentColor : .primary)
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier(id)
  }

  /// iPhone Duo 侧边操作区切换根入口：再次点击当前已激活入口时重置其导航栈，不弹出任何溢出菜单。
  private func selectDuoRootTab(_ target: Page) {
    dynamicActionCenter.reset()
    if target == selectedTab {
      switch target {
      case .discover:
        discoverPath = []
      case .subscriptions:
        subscriptionsPath = []
      case .mine:
        minePath = []
      case .more:
        morePath = []
        showsPlugins = false
      case .search:
        searchPath = []
      case .sidebarWorkspace:
        break
      }
      return
    }
    selectedTab = target
  }

  /// iPhone Duo 子页面底部动态动作栏：当推入的子页面注册了动态主动作（如新增、搜索）时，将其直接呈现在侧边操作区中。
  @ToolbarContentBuilder
  private var duoPushedDynamicActionToolbar: some ToolbarContent {
    if let dynamic = dynamicActionCenter.current {
      ToolbarItemGroup(placement: .bottomBar) {
        Spacer()
        duoNavToolbarButton(
          title: dynamic.title,
          symbol: dynamic.symbol,
          isSelected: true,
          id: "native-v2-search-tab-item"
        ) {
          triggerTrailingCustomAction()
        }
      }
      .nativeDuoVerticalPreferred()
    }
  }

  /// iPadOS 18+ 原生自适应侧边栏壳层：顶部浮动胶囊统一呈现「发现 / 订阅 / 我的 / 更多 + 搜索」，展开左侧边栏可一键直达工作台与快捷工具。
  @available(iOS 18, *)
  private var iPadSidebarAdaptableShell: some View {
    TabView(selection: tabSelection) {
      if canDiscover {
        Tab(t("发现"), image: "DiscoverCards", value: Page.discover) {
          discoveryTab
        }
        .accessibilityIdentifier("native-v2-tab-发现")
      }
      if canSubscribe {
        Tab(t("订阅"), systemImage: "bookmark", value: Page.subscriptions) {
          subscriptionsTab
        }
        .accessibilityIdentifier("native-v2-tab-订阅")
      }
      Tab(value: Page.mine) {
        mineTab
      } label: {
        if let avatar = displayedMineTabAvatar {
          Label {
            Text(t("我的"))
          } icon: {
            Image(uiImage: avatar)
          }
        } else {
          Label(t("我的"), systemImage: "person.crop.circle")
        }
      }
      .accessibilityIdentifier("native-v2-tab-我的")

      Tab(t("更多"), systemImage: "square.grid.2x2", value: Page.more) {
        moreTab
      }
      .accessibilityIdentifier("native-v2-tab-更多")

      if canDiscover || hasTrailingCustomAction {
        Tab(
          hasTrailingCustomAction ? trailingButtonTitle : t("搜索"),
          systemImage: trailingButtonSymbol,
          value: Page.search,
          role: trailingTabRole
        ) {
          searchTab
        }
        .accessibilityIdentifier("native-v2-search-tab-item")
      }

      if canSubscribe || canSearchResources || canManageDownloads || snapshot.user.isSuperuser {
        TabSection(t("工作台")) {
          if canSubscribe {
            Tab(
              t("我的订阅"), systemImage: "bookmark.fill",
              value: Page.sidebarWorkspace(.subscriptions)
            ) {
              sidebarWorkspaceTab(.subscriptions)
            }
            .accessibilityIdentifier("native-sidebar-subscriptions")

            Tab(
              t("订阅日历"), systemImage: "calendar",
              value: Page.sidebarWorkspace(.calendar)
            ) {
              sidebarWorkspaceTab(.calendar)
            }
            .accessibilityIdentifier("native-sidebar-calendar")
          }
          if canSearchResources {
            Tab(
              t("站点资源"), systemImage: "magnifyingglass.circle.fill",
              value: Page.sidebarWorkspace(.resources)
            ) {
              sidebarWorkspaceTab(.resources)
            }
            .accessibilityIdentifier("native-sidebar-resources")
          }
          if canManageDownloads {
            Tab(
              t("下载"), systemImage: "arrow.down.circle.fill",
              value: Page.sidebarWorkspace(.downloads)
            ) {
              sidebarWorkspaceTab(.downloads)
            }
            .accessibilityIdentifier("native-sidebar-downloads")

            Tab(
              t("文件管理"), systemImage: "folder.fill",
              value: Page.sidebarWorkspace(.files)
            ) {
              sidebarWorkspaceTab(.files)
            }
            .accessibilityIdentifier("native-sidebar-files")

            Tab(
              t("整理历史"), systemImage: "clock.arrow.circlepath",
              value: Page.sidebarWorkspace(.history)
            ) {
              sidebarWorkspaceTab(.history)
            }
            .accessibilityIdentifier("native-sidebar-history")

            Tab(
              t("工作流"), systemImage: "flowchart",
              value: Page.sidebarWorkspace(.workflows)
            ) {
              sidebarWorkspaceTab(.workflows)
            }
            .accessibilityIdentifier("native-sidebar-workflows")
          }
          if snapshot.user.isSuperuser {
            Tab(
              t("插件"), systemImage: "puzzlepiece.extension.fill",
              value: Page.sidebarWorkspace(.pluginMarket)
            ) {
              sidebarWorkspaceTab(.pluginMarket)
            }
            .accessibilityIdentifier("native-sidebar-plugins")
          }
        }
        .tabPlacement(.sidebarOnly)
      }

      TabSection(t("快捷工具")) {
        if canDiscover {
          Tab(t("音乐"), systemImage: "music.note.list", value: Page.sidebarWorkspace(.music)) {
            sidebarWorkspaceTab(.music)
          }
          .accessibilityIdentifier("native-sidebar-music")
        }
        Tab(t("消息中心"), systemImage: "bell.fill", value: Page.sidebarWorkspace(.messages)) {
          sidebarWorkspaceTab(.messages)
        }
        .accessibilityIdentifier("native-sidebar-messages")

        Tab(t("智能助手"), systemImage: "text.bubble", value: Page.sidebarWorkspace(.agent)) {
          sidebarWorkspaceTab(.agent)
        }
        .accessibilityIdentifier("native-sidebar-agent")
      }
      .tabPlacement(.sidebarOnly)
    }
    .tabViewStyle(.sidebarAdaptable)
  }

  /// iPad 侧栏工作台项独立导航栈容器。
  private func sidebarWorkspaceTab(_ destination: NativeWorkspaceDestination) -> some View {
    NavigationStack {
      workspaceDestinationView(destination)
        .navigationDestination(for: NativeWorkspaceDestination.self) { next in
          workspaceDestinationView(next)
        }
    }
  }

  /// iPhone iOS 18+ 原生 4+1 TabView：前 4 项为发现、订阅、我的（仪表盘）、更多，第 +1 项为右侧动态主按钮/全局搜索。
  @available(iOS 18, *)
  private var iPhoneModernTabShell: some View {
    TabView(selection: tabSelection) {
      if canDiscover {
        Tab(t("发现"), image: "DiscoverCards", value: Page.discover) {
          discoveryTab
        }
        .accessibilityIdentifier("native-v2-tab-发现")
      }
      if canSubscribe {
        Tab(t("订阅"), systemImage: "bookmark", value: Page.subscriptions) {
          subscriptionsTab
        }
        .accessibilityIdentifier("native-v2-tab-订阅")
      }
      Tab(value: Page.mine) {
        mineTab
      } label: {
        if let avatar = displayedMineTabAvatar {
          Label {
            Text(t("我的"))
          } icon: {
            Image(uiImage: avatar)
          }
        } else {
          Label(t("我的"), systemImage: "person.crop.circle")
        }
      }
      .accessibilityIdentifier("native-v2-tab-我的")

      Tab(t("更多"), systemImage: "square.grid.2x2", value: Page.more) {
        moreTab
      }
      .accessibilityIdentifier("native-v2-tab-更多")

      if canDiscover || hasTrailingCustomAction {
        Tab(
          hasTrailingCustomAction ? trailingButtonTitle : t("搜索"),
          systemImage: trailingButtonSymbol,
          value: Page.search,
          role: trailingTabRole
        ) {
          searchTab
        }
        .accessibilityIdentifier("native-v2-search-tab-item")
      }
    }
  }

  /// iOS 16–17 兼容 TabView 壳层。
  private var legacyTabShell: some View {
    TabView(selection: tabSelection) {
      if canDiscover {
        discoveryTab
          .tag(Page.discover)
          .tabItem {
            Label(t("发现"), image: "DiscoverCards")
              .accessibilityIdentifier("native-v2-tab-发现")
          }
      }
      if canSubscribe {
        subscriptionsTab
          .tag(Page.subscriptions)
          .tabItem {
            Label(t("订阅"), systemImage: "bookmark")
              .accessibilityIdentifier("native-v2-tab-订阅")
          }
      }
      mineTab
        .tag(Page.mine)
        .tabItem {
          if let avatar = displayedMineTabAvatar {
            Label {
              Text(t("我的"))
            } icon: {
              Image(uiImage: avatar)
            }
            .accessibilityIdentifier("native-v2-tab-我的")
          } else {
            Label(t("我的"), systemImage: "person.crop.circle")
              .accessibilityIdentifier("native-v2-tab-我的")
          }
        }
      moreTab
        .tag(Page.more)
        .tabItem {
          Label(t("更多"), systemImage: "square.grid.2x2")
            .accessibilityIdentifier("native-v2-tab-更多")
        }
      if canDiscover || hasTrailingCustomAction {
        searchTab
          .tag(Page.search)
          .tabItem {
            Label(
              hasTrailingCustomAction ? trailingButtonTitle : t("搜索"),
              systemImage: trailingButtonSymbol)
          }
      }
    }
  }

  /// 订阅主标签：呈现「我的订阅」全景卡片与列表，右上角通过图标直达追剧日历与订阅广场。
  private var subscriptionsTab: some View {
    NavigationStack(path: $subscriptionsPath) {
      NativeSubscriptionsPage(
        session: session,
        isRootTab: true,
        requestedFilter: $pendingSubscriptionFilter,
        onOpenGlobalSearch: canDiscover ? { selectedTab = .search } : nil
      )
      .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      .nativeDuoPrefersToolbarItems()
      .toolbar {
        if usesDuoSideOperationBar {
          duoSideOperationToolbar
        }
      }
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        workspaceDestinationView(destination)
          .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
          .toolbar {
            if usesDuoSideOperationBar {
              duoPushedDynamicActionToolbar
            }
          }
      }
    }
    .modifier(
      NativeLegacyBottomClearanceModifier(
        enabled: usesLegacyFloatingTabBar, height: legacyTabBarReservedHeight)
    )
    .background(tabReselectInterceptor)
  }

  /// 我的标签：超级管理员直显原生仪表盘，普通成员展示个人概览与权限快捷卡；顶部统一呈现用户身份卡，右上角仅保留消息中心入口。
  private var mineTab: some View {
    NavigationStack(path: $minePath) {
      Group {
        if snapshot.user.isSuperuser {
          NativeDashboardPage(
            session: session,
            snapshot: snapshot,
            currentLanguage: currentLanguage,
            onOpenMessages: { showsMessagesSheet = true }
          )
        } else {
          memberDashboardView
        }
      }
      .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      .nativeDuoPrefersToolbarItems()
      .toolbar {
        if usesDuoSideOperationBar {
          duoSideOperationToolbar
        }
      }
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        workspaceDestinationView(destination)
          .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
          .toolbar {
            if usesDuoSideOperationBar {
              duoPushedDynamicActionToolbar
            }
          }
      }
    }
    .modifier(
      NativeLegacyBottomClearanceModifier(
        enabled: usesLegacyFloatingTabBar, height: legacyTabBarReservedHeight)
    )
    .background(tabReselectInterceptor)
  }

  /// 非超级管理员进入「我的」时的个人概览卡片页，顶部统一渲染用户头像与角色卡片，避免调用管理员统计接口。
  private var memberDashboardView: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          NativeDashboardUserProfileCard(
            session: session,
            user: snapshot.user,
            currentLanguage: currentLanguage
          )

          if canSubscribe {
            HStack(spacing: 12) {
              memberShortcutCard(title: t("我的订阅"), symbol: "bookmark.fill") {
                subscriptionsPath = []
                selectedTab = .subscriptions
              }
              memberShortcutCard(title: t("追剧日历"), symbol: "calendar") {
                selectedTab = .subscriptions
                subscriptionsPath = [.calendar]
              }
            }
          }

          HStack(spacing: 12) {
            memberShortcutCard(title: "消息中心", symbol: "bell.fill") {
              showsMessagesSheet = true
            }
            memberShortcutCard(title: t("智能助手"), symbol: "text.bubble") {
              showsAgentSheet = true
            }
          }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, CinematicStyle.margin)
        .padding(.top, 8)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .modifier(NativeSoftTopScrollEdge())
    }
    .navigationTitle(t("我的"))
    .navigationBarTitleDisplayMode(.inline)
    .nativeTopNavigationBar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsMessagesSheet = true
        } label: {
          Image(systemName: "bell")
        }
        .tint(.primary)
        .accessibilityLabel("消息中心")
        .accessibilityIdentifier("native-dashboard-messages-btn")
      }
    }
  }

  /// 普通成员「我的」快捷玻璃卡片。
  private func memberShortcutCard(
    title: String, symbol: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      CinematicPanel(padding: 14) {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: symbol)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.primary)
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
  }

  /// 更多标签：承载四大分组全功能入口卡片，右上角齿轮按钮推入设置中心。
  private var moreTab: some View {
    NavigationStack(path: $morePath) {
      NativeMoreHubPage(
        snapshot: snapshot,
        currentLanguage: currentLanguage,
        onNavigate: { destination in
          if morePath.last != destination {
            morePath.append(destination)
          }
        },
        onOpenSettings: {
          if morePath.last != .settingsHub {
            morePath.append(.settingsHub)
          }
        }
      )
      .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      .nativeDuoPrefersToolbarItems()
      .toolbar {
        if usesDuoSideOperationBar {
          duoSideOperationToolbar
        }
      }
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        workspaceDestinationView(destination)
          .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
          .toolbar {
            if usesDuoSideOperationBar {
              duoPushedDynamicActionToolbar
            }
          }
      }
      .navigationDestination(isPresented: $showsPlugins) {
        pluginDestination()
          .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      }
    }
    .modifier(
      NativeLegacyBottomClearanceModifier(
        enabled: usesLegacyFloatingTabBar, height: legacyTabBarReservedHeight)
    )
    .background(tabReselectInterceptor)
  }

  /// 媒体搜索在自身导航栈内推入详情页，不通过遮罩弹窗打断检索上下文。
  private var searchTab: some View {
    NavigationStack(path: $searchPath) {
      NativeMediaSearchPage(
        session: session,
        externalSearchQuery: $pendingSearchQuery,
        externalSearchKind: $pendingSearchKind,
        onSelect: { source, id, type in
          guard let id, let type else { return }
          searchPath.append(NativeMediaIdentity(source: source, mediaID: id, type: type))
        }
      )
      .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      .nativeDuoPrefersToolbarItems()
      .toolbar {
        if usesDuoSideOperationBar {
          duoSideOperationToolbar
        }
      }
      .navigationDestination(for: NativeMediaIdentity.self) { identity in
        NativeMediaDetailPage(session: session, identity: identity)
          .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      }
    }
    .modifier(
      NativeLegacyBottomClearanceModifier(
        enabled: usesLegacyFloatingTabBar, height: legacyTabBarReservedHeight)
    )
    .background(tabReselectInterceptor)
  }

  /// 发现页用原生导航推入全部海报网格与媒体详情，主视觉顶部无多余遮挡按钮。
  private var discoveryTab: some View {
    NavigationStack(path: $discoverPath) {
      NativeDiscoverPage(
        session: session,
        content: discovery,
        artwork: { reference, role in
          AnyView(
            NativeMediaArtwork(
              session: session, reference: reference, role: role,
              maximumWidth: role == .backdrop
                ? 1280 : (role == .continueWatching || role == .provider ? 720 : 420)))
        },
        onOpenSearch: { selectedTab = .search },
        onSearchMedia: { media in
          pendingSearchQuery = media.title
          searchPath = []
          selectedTab = .search
        },
        onSubscribeMedia: { media in
          Task { await quickSubscribeFromDiscover(media) }
        },
        onOpenMedia: { id in
          if let msTarget = mediaServerItems[id] {
            discoverPath.append(.mediaServer(msTarget))
          } else if let seed = musicSeeds[id] {
            discoverPath.append(.music(seed))
          } else if let identity = mediaIdentities[id] {
            discoverPath.append(.media(identity))
          }
        },
        onOpenRail: { id in
          if let rail = discovery.rails.first(where: { $0.id == id }) {
            discoverPath.append(.rail(rail))
          }
        },
        onOpenProvider: { providerID in
          if let provider = discovery.providers.first(where: { $0.id == providerID }) {
            let serverName = provider.server ?? latestServerName ?? ""
            if !serverName.isEmpty {
              discoverPath.append(
                .mediaServer(
                  .library(
                    server: serverName,
                    serverType: provider.serverType,
                    libraryID: provider.itemID,
                    libraryName: provider.name,
                    libraryType: provider.libraryType,
                    externalLink: provider.link,
                    serverID: provider.serverID
                  )
                )
              )
            } else {
              NativeMediaServerAppLauncher.openLibrary(provider)
            }
          }
        },
        onOpenCategory: { categoryID in
          let source = NativeExploreSourceKind(rawValue: categoryID) ?? .tmdbMovies
          discoverPath.append(.explore(source))
        },
        onPlayContinueWatching: { item in
          guard let itemID = item.itemID else {
            if let identity = mediaIdentities[item.media.id] {
              discoverPath.append(.media(identity))
            }
            return
          }
          let artworkURL = NativeMediaPlaybackLauncher.proxiedArtworkURL(
            session: session, raw: item.media.posterReference)
          Task {
            _ = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
              session: session,
              itemID: itemID,
              server: item.server,
              title: item.media.title,
              artworkURL: artworkURL
            )
          }
        },
        onOpenContinueWatchingDetail: { item in
          if let itemID = item.itemID, !itemID.isEmpty {
            discoverPath.append(
              .mediaServer(
                .detail(
                  server: item.server ?? latestServerName,
                  itemID: itemID,
                  fallbackTitle: item.media.title,
                  fallbackItemType: item.media.mediaServerItemType,
                  fallbackPoster: item.media.posterReference
                )
              )
            )
          } else if let identity = mediaIdentities[item.media.id] {
            discoverPath.append(.media(identity))
          }
        },
        onManageModules: { showsModuleSheet = true },
        onLoadMoreRail: { railID in
          Task { await loadMoreDiscoverRail(railID) }
        },
        loadingRailIDs: loadingRailIDs,
        onRefresh: { await loadDiscovery(forceRefresh: true) },
        onRetry: { discoveryAttempt += 1 }
      )
      .toolbarBackground(.hidden, for: .navigationBar)
      .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      .nativeDuoPrefersToolbarItems()
      .toolbar {
        if usesDuoSideOperationBar {
          duoSideOperationToolbar
        }
      }
      .navigationDestination(for: NativeMediaDestination.self) { destination in
        Group {
          switch destination {
          case .media(let identity):
            NativeMediaDetailPage(session: session, identity: identity)
          case .music(let seed):
            NativeMusicAlbumDetailPage(session: session, seed: seed)
          case .rail(let rail):
            NativeDiscoverRailGrid(session: session, rail: rail) { page in
              try await loadRailPage(rail.id, page: page)
            } destination: { identity in
              if identity.type == "音乐",
                let seed = musicSeeds["\(identity.source)|\(identity.mediaID)"]
              {
                NativeMusicAlbumDetailPage(session: session, seed: seed)
              } else {
                NativeMediaDetailPage(session: session, identity: identity)
              }
            }
          case .workspace(let dest):
            workspaceDestinationView(dest)
              .toolbar {
                if usesDuoSideOperationBar {
                  duoPushedDynamicActionToolbar
                }
              }
          case .explore(let source):
            NativeExplorePage(session: session, initialSource: source)
          case .mediaServer(let target):
            switch target {
            case .library(
              let server, let serverType, let libraryID, let libraryName, let libraryType,
              let externalLink, let serverID):
              NativeMediaServerLibraryPage(
                session: session,
                server: server,
                serverType: serverType,
                libraryID: libraryID,
                libraryName: libraryName,
                libraryType: libraryType,
                externalLink: externalLink,
                serverID: serverID
              )
            case .detail(
              let server, let itemID, let fallbackTitle, let fallbackItemType, let fallbackPoster):
              NativeMediaServerDetailPage(
                session: session,
                server: server,
                itemID: itemID,
                fallbackTitle: fallbackTitle,
                fallbackItemType: fallbackItemType,
                fallbackPoster: fallbackPoster
              )
            }
          }
        }
        .modifier(NativeLegacyHideSystemTabBarModifier(isHidden: usesLegacyFloatingTabBar))
      }
    }
    .modifier(
      NativeLegacyBottomClearanceModifier(
        enabled: usesLegacyFloatingTabBar, height: legacyTabBarReservedHeight)
    )
    .background(tabReselectInterceptor)
  }

  /// 统一将工作台路由映射到对应原生业务页面，供全部主标签与侧边工作台复用。
  @ViewBuilder
  private func workspaceDestinationView(_ destination: NativeWorkspaceDestination) -> some View {
    switch destination {
    case .explore(let source):
      NativeExplorePage(session: session, initialSource: source)
    case .music:
      NativeMusicPage(session: session)
    case .subscriptions:
      NativeSubscriptionsPage(
        session: session,
        isRootTab: false,
        onOpenGlobalSearch: canDiscover ? { selectedTab = .search } : nil
      )
    case .subscriptionsFiltered(let filter):
      NativeSubscriptionsPage(
        session: session,
        initialFilter: filter,
        isRootTab: false,
        onOpenGlobalSearch: canDiscover ? { selectedTab = .search } : nil
      )
    case .subscribeCommunity:
      NativeSubscribeCommunityPage(session: session)
    case .downloads:
      NativeDownloadsPage(session: session)
    case .calendar:
      NativeCalendarPage(session: session)
    case .resources:
      NativeResourceSearchPage(session: session, target: .lastResults)
    case .resourcesQuery(let keyword, let browseHome):
      NativeResourceSearchPage(
        session: session, target: .lastResults, initialKeyword: keyword, browseHome: browseHome)
    case .history:
      NativeTransferHistoryPage(session: session)
    case .historyQuery(let search):
      NativeTransferHistoryPage(session: session, initialSearch: search)
    case .sites:
      NativeSitesPage(session: session)
    case .messages:
      NativeMessagesPage(session: session)
    case .agent:
      NativeAgentChatPage(session: session)
    case .files:
      NativeFileManagerPage(session: session)
    case .filesTarget(let storage, let path):
      NativeFileManagerPage(session: session, initialStorage: storage, initialPath: path)
    case .workflows:
      NativeWorkflowsPage(session: session)
    case .settingsHub:
      NativeSettingsHubPage(
        session: session,
        snapshot: snapshot,
        currentLanguage: currentLanguage,
        onNavigate: { next in
          if selectedTab != .more {
            selectedTab = .more
            morePath = [.settingsHub, next]
          } else if morePath.last != next {
            morePath.append(next)
          }
        },
        onOpenModules: { showsModuleSheet = true },
        onOpenPlugins: {
          selectedTab = .more
          morePath = []
          showsPlugins = true
        },
        onSelectLanguage: onSelectLanguage,
        onSwitchServer: onSwitchServer,
        onLogout: onLogout
      )
    case .settings:
      NativeSystemSettingsPage(session: session)
    case .systemModule(let domain):
      NativeSystemModulesPage(session: session, initialDomain: domain)
    case .diagnostics(let tool):
      NativeDiagnosticsToolsPage(session: session, initialTool: tool)
    case .users:
      NativeUsersPage(session: session)
    case .pluginMarket:
      NativePluginMarketPage(session: session)
    case .appearance:
      NativeAppearanceSettingsPage()
    case .channelAuth:
      NativeChannelAuthorizationPage(session: session, isSuperuser: snapshot.user.isSuperuser)
    case .subscribeSearchSettings:
      NativeSubscribeSearchSettingsPage(session: session)
    case .mediaSourceSettings:
      NativeMediaSourceSettingsPage(session: session)
    case .downloadersManage:
      NativeDownloadersManagePage(session: session)
    case .mediaServersManage:
      NativeMediaServersManagePage(session: session)
    case .mediaServerBindings:
      NativeMediaServerAccountBindingsPage(session: session)
    case .playbackSettings:
      NativePlaybackPreferencesPage(session: session)
    }
  }

  /// 在「更多 → 设置中心」导航栈下打开专项设置子页面。
  private func openSettingsDestination(_ destination: NativeWorkspaceDestination) {
    showsPlugins = false
    selectedTab = .more
    morePath = [.settingsHub, destination]
  }

  /// 判断目标路由是否需要在宿主根控制器上弹出模态面板。
  private static func requiresRootSheetPresentation(_ target: AppDeepLink) -> Bool {
    switch target {
    case .messages, .agent:
      true
    default:
      false
    }
  }

  /// 查找当前前台窗口中仍挂载着模态控制器的根视图控制器，避免新模态弹出被 UIKit 拒绝丢弃。
  private static func activeRootViewControllerWithPresentedModal(
    dismissAllForSheetTarget: Bool
  ) -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where !window.isHidden {
        guard let rootVC = window.rootViewController,
          let presented = rootVC.presentedViewController
        else { continue }
        if !dismissAllForSheetTarget,
          let player = presented as? MediaPlaybackViewController,
          !player.isSessionBound
        {
          continue
        }
        return rootVC
      }
    }
    return nil
  }

  /// 若顶层已打开子页面弹窗（如推送设置页、订阅编辑页等），先无动画收起待窗口空闲后再执行目标路由；无弹窗时零延迟同步执行。
  private func runAfterModalDismissal(
    for target: AppDeepLink,
    action: @escaping @MainActor () -> Void
  ) {
    let needsSheet = Self.requiresRootSheetPresentation(target)
    guard
      let rootVC = Self.activeRootViewControllerWithPresentedModal(
        dismissAllForSheetTarget: needsSheet)
    else {
      action()
      return
    }
    if let presented = rootVC.presentedViewController, !presented.isBeingDismissed {
      rootVC.dismiss(animated: false) {
        Task { @MainActor in
          await waitUntilRootModalCleared(dismissAllForSheetTarget: needsSheet, attemptsLeft: 15)
          action()
        }
      }
    } else {
      Task { @MainActor in
        await waitUntilRootModalCleared(dismissAllForSheetTarget: needsSheet, attemptsLeft: 15)
        action()
      }
    }
  }

  /// 等待根控制器上正在退场的 UIKit 模态完全释放。
  private func waitUntilRootModalCleared(
    dismissAllForSheetTarget: Bool,
    attemptsLeft: Int
  ) async {
    var remaining = attemptsLeft
    while remaining > 0 {
      guard
        let rootVC = Self.activeRootViewControllerWithPresentedModal(
          dismissAllForSheetTarget: dismissAllForSheetTarget)
      else { return }
      if let presented = rootVC.presentedViewController, !presented.isBeingDismissed {
        rootVC.dismiss(animated: false)
      }
      remaining -= 1
      try? await Task.sleep(for: .milliseconds(25))
    }
  }

  /// 消费来自 APNs 通知、桌面小组件、主屏幕快捷方式与 `moviepilot://` 联动链接的受限路由意图，严格遵循当前账号权限门禁。
  private func consumeSystemRouteIfNeeded() {
    guard let target = routeHub.consumeTarget() else { return }
    if target != .discover {
      launchSplashTimedOut = true
    }
    if target == .messages {
      NativePageDataCache.shared.remove("messages|list", session: session)
      if showsMessagesSheet {
        NativeMediaPlaybackLauncher.shared.dismissFullScreenPlayerIfNeeded(animated: false)
        for scene in UIApplication.shared.connectedScenes {
          guard let windowScene = scene as? UIWindowScene else { continue }
          for window in windowScene.windows where !window.isHidden {
            if let messagesSheetVC = window.rootViewController?.presentedViewController,
              messagesSheetVC.presentedViewController != nil
            {
              messagesSheetVC.dismiss(animated: false)
            }
          }
        }
        return
      }
    }
    showsMessagesSheet = false
    showsAgentSheet = false
    showsModuleSheet = false
    switch target {
    case .playMediaServerItem, .playStorageFile, .playExternalURL, .playLocalFile:
      break
    default:
      NativeMediaPlaybackLauncher.shared.dismissFullScreenPlayerIfNeeded(animated: false)
    }
    runAfterModalDismissal(for: target) {
      applySystemRouteTarget(target)
    }
  }

  /// 在窗口无遮挡模态后应用具体的原生标签、导航栈或模态路由。
  private func applySystemRouteTarget(_ target: AppDeepLink) {
    switch target {
    case .discover:
      guard canDiscover else {
        routeHub.postBanner(t("当前账号没有访问发现页的权限。"))
        return
      }
      discoverPath = []
      selectedTab = .discover

    case .explore(let rawSource):
      guard canDiscover else {
        routeHub.postBanner(t("当前账号没有访问探索页的权限。"))
        return
      }
      let source = rawSource.flatMap(NativeExploreSourceKind.init(rawValue:)) ?? .tmdbMovies
      selectedTab = .discover
      discoverPath = [.explore(source)]

    case .dashboard:
      minePath = []
      selectedTab = .mine

    case .settings:
      showsPlugins = false
      selectedTab = .more
      morePath = [.settingsHub]

    case .search(let query, let kind):
      guard canDiscover else {
        routeHub.postBanner(t("当前账号没有访问搜索页的权限。"))
        return
      }
      searchPath = []
      pendingSearchQuery = query
      pendingSearchKind = kind
      selectedTab = .search

    case .mediaDetail(let source, let mediaID, let mediaType):
      guard canDiscover else {
        routeHub.postBanner(t("当前账号没有访问影视详情的权限。"))
        return
      }
      selectedTab = .discover
      discoverPath = [
        .media(NativeMediaIdentity(source: source, mediaID: mediaID, type: mediaType))
      ]

    case .subscriptions(let category):
      guard canSubscribe else {
        routeHub.postBanner(t("当前账号没有访问订阅中心的权限。"))
        return
      }
      let filter: NativeSubscriptionsPage.Filter =
        switch category {
        case "movie": .movie
        case "tv": .tv
        case "music": .music
        default: .all
        }
      pendingSubscriptionFilter = filter
      subscriptionsPath = []
      selectedTab = .subscriptions

    case .subscribeCommunity:
      guard canSubscribe else {
        routeHub.postBanner(t("当前账号没有访问订阅分享的权限。"))
        return
      }
      selectedTab = .subscriptions
      subscriptionsPath = [.subscribeCommunity]

    case .calendar:
      guard canSubscribe else {
        routeHub.postBanner(t("当前账号没有访问订阅日历的权限。"))
        return
      }
      selectedTab = .subscriptions
      subscriptionsPath = [.calendar]

    case .resources(let keyword, let browseHome):
      guard canSearchResources else {
        routeHub.postBanner(t("当前账号没有搜索站点资源的权限。"))
        return
      }
      showsPlugins = false
      selectedTab = .more
      if keyword == nil && !browseHome {
        morePath = [.resources]
      } else {
        morePath = [.resourcesQuery(keyword: keyword, browseHome: browseHome)]
      }

    case .downloads:
      guard canManageDownloads else {
        routeHub.postBanner(t("当前账号没有访问下载管理的权限。"))
        return
      }
      showsPlugins = false
      selectedTab = .more
      morePath = [.downloads]

    case .files(let storage, let path):
      guard canManageDownloads else {
        routeHub.postBanner(t("当前账号没有访问文件管理的权限。"))
        return
      }
      showsPlugins = false
      selectedTab = .more
      if storage == nil && path == nil {
        morePath = [.files]
      } else {
        morePath = [.filesTarget(storage: storage, path: path)]
      }

    case .history(let search):
      guard canManageDownloads else {
        routeHub.postBanner(t("当前账号没有访问整理历史的权限。"))
        return
      }
      showsPlugins = false
      selectedTab = .more
      if let search, !search.isEmpty {
        morePath = [.historyQuery(search)]
      } else {
        morePath = [.history]
      }

    case .workflows:
      guard canManageDownloads else {
        routeHub.postBanner(t("当前账号没有访问工作流的权限。"))
        return
      }
      showsPlugins = false
      selectedTab = .more
      morePath = [.workflows]

    case .sites:
      guard canManageDownloads else {
        routeHub.postBanner(t("当前账号没有访问站点管理的权限。"))
        return
      }
      openSettingsDestination(.sites)

    case .messages:
      showsMessagesSheet = true

    case .plugins(let installedOnly):
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问插件中心。"))
        return
      }
      if installedOnly {
        selectedTab = .more
        morePath = []
        showsPlugins = true
      } else {
        showsPlugins = false
        selectedTab = .more
        morePath = [.pluginMarket]
      }

    case .pluginDetail(let pluginID, let surface):
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问插件中心。"))
        return
      }
      deepLinkPluginTarget = DeepLinkPluginTarget(pluginID: pluginID, surface: surface)

    case .agent(let prompt):
      pendingAgentPrompt = prompt ?? ""
      showsAgentSheet = true

    case .music:
      guard canDiscover else {
        routeHub.postBanner(t("当前账号没有访问音乐中心的权限。"))
        return
      }
      showsPlugins = false
      selectedTab = .more
      morePath = [.music]

    case .shortcuts:
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问系统诊断工具。"))
        return
      }
      showsPlugins = false
      selectedTab = .more
      morePath = []

    case .users:
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问用户管理。"))
        return
      }
      openSettingsDestination(.users)

    case .appearance:
      openSettingsDestination(.appearance)

    case .systemSettings:
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问系统设置。"))
        return
      }
      openSettingsDestination(.settings)

    case .systemModule(let rawDomain):
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问系统模块设置。"))
        return
      }
      guard let domain = Self.systemModuleDomain(for: rawDomain) else { return }
      openSettingsDestination(.systemModule(domain))

    case .diagnostics(let rawTool):
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问系统诊断工具。"))
        return
      }
      guard let tool = Self.diagnosticsTool(for: rawTool) else { return }
      showsPlugins = false
      selectedTab = .more
      morePath = [.diagnostics(tool)]

    case .channelAuth:
      openSettingsDestination(.channelAuth)

    case .subscribeSearchSettings:
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问订阅与搜索设置。"))
        return
      }
      openSettingsDestination(.subscribeSearchSettings)

    case .mediaSourceSettings:
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问媒体源设置。"))
        return
      }
      openSettingsDestination(.mediaSourceSettings)

    case .downloadersManage:
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问下载器管理。"))
        return
      }
      openSettingsDestination(.downloadersManage)

    case .mediaServersManage:
      guard snapshot.user.isSuperuser else {
        routeHub.postBanner(t("仅管理员可访问媒体服务器管理。"))
        return
      }
      openSettingsDestination(.mediaServersManage)

    case .playbackSettings:
      openSettingsDestination(.playbackSettings)

    case .playMediaServerItem(let itemID, let server, let title):
      guard canDiscover else {
        routeHub.postBanner(t("当前账号没有播放媒体库条目的权限。"))
        return
      }
      Task {
        if let err = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
          session: session, itemID: itemID, server: server, title: title ?? "")
        {
          routeHub.postBanner(err)
        }
      }

    case .playStorageFile(let storage, let path, let fileName):
      guard canManageDownloads else {
        routeHub.postBanner(t("当前账号没有播放存储文件的权限。"))
        return
      }
      let resolvedName =
        fileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? fileName!
        : (path as NSString).lastPathComponent
      Task {
        if let err = await NativeMediaPlaybackLauncher.shared.playStorageFile(
          session: session, storage: storage, path: path, fileName: resolvedName)
        {
          routeHub.postBanner(err)
        }
      }

    case .playExternalURL(let url, let title, let kind):
      NativeMediaPlaybackLauncher.shared.enqueueOrPlayExternalURL(
        url: url, title: title, kind: kind)

    case .playLocalFile:
      break
    }
  }

  /// 将深度链接系统模块标识映射为原生设置模块枚举。
  private static func systemModuleDomain(for raw: String) -> NativeSystemModulesPage.Domain? {
    switch raw {
    case "site_scope": .siteScope
    case "directories": .directories
    case "services": .services
    case "notifications": .notifications
    case "rules": .rules
    case "scraping": .scraping
    case "nettest": .nettest
    default: nil
    }
  }

  /// 将深度链接诊断工具标识映射为原生工具枚举。
  private static func diagnosticsTool(for raw: String) -> NativeDiagnosticsToolsPage.Tool? {
    switch raw {
    case "health": .health
    case "nettest": .nettest
    case "rule_test": .ruleTest
    case "words": .words
    case "live_log": .liveLog
    case "scheduler": .scheduler
    default: nil
    }
  }

  /// 最小化音乐悬浮迷你播放条：悬浮于底部导航栏上方，支持封面展示、实时进度线、播放/暂停、下一首、关闭与点按还原全屏播放页。
  private func floatingMiniMusicBar(_ state: NativeMiniMusicState) -> some View {
    let accent = appearance.accentColor
    return VStack {
      Spacer(minLength: 0)
      VStack(spacing: 0) {
        HStack(spacing: 11) {
          Group {
            if let artwork = state.artwork {
              Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
            } else {
              ZStack {
                LinearGradient(
                  colors: [accent.opacity(0.68), accent.opacity(0.32)],
                  startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.white)
              }
            }
          }
          .frame(width: 40, height: 40)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

          VStack(alignment: .leading, spacing: 2) {
            Text(state.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
            if !state.subtitle.isEmpty {
              Text(state.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          HStack(spacing: 4) {
            Button {
              playbackLauncher.toggleMinimizedPlayPause()
            } label: {
              Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("native-mini-music-playpause")

            if state.hasNext {
              Button {
                playbackLauncher.skipNextMinimizedTrack()
              } label: {
                Image(systemName: "forward.fill")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary.opacity(0.85))
                  .frame(width: 34, height: 36)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("下一首")
              .accessibilityIdentifier("native-mini-music-next")
            }

            Button {
              withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                playbackLauncher.stopMinimizedAudio()
              }
            } label: {
              Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭音乐播放")
            .accessibilityIdentifier("native-mini-music-close")
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
          playbackLauncher.expandMinimizedAudio()
        }

        GeometryReader { bar in
          let width = max(bar.size.width * min(max(state.progress, 0), 1), 0)
          ZStack(alignment: .leading) {
            Rectangle().fill(.primary.opacity(0.08))
            Rectangle().fill(accent).frame(width: width)
          }
        }
        .frame(height: 2.2)
      }
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .modifier(NativeLiquidGlassPopoverSurface(cornerRadius: 18))
      .frame(maxWidth: 520)
      .padding(.horizontal, 14)
      .padding(
        .bottom,
        usesDuoSideOperationBar
          ? 16
          : (NativeDeviceLayout.isIPad
            ? 24
            : ((verticalSizeClass == .compact && !NativeDeviceLayout.isIPad) ? 56 : 86)))
    }
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier("native-mini-music-bar")
  }

  /// 跨账号或失效小组件触发时展示顶部安全提示条（不自动切换实例或账号）。
  private func systemBannerOverlay(_ message: String) -> some View {
    VStack {
      CinematicPanel(padding: 12) {
        HStack(spacing: 10) {
          Image(systemName: "info.circle.fill")
            .foregroundStyle(NativeTheme.brand)
          Text(message)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(0.92))
            .frame(maxWidth: .infinity, alignment: .leading)
          Button {
            routeHub.bannerMessage = nil
          } label: {
            Image(systemName: "xmark")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.primary.opacity(0.70))
              .frame(width: 28, height: 28)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("关闭提示")
        }
      }
      .padding(.horizontal, CinematicStyle.margin)
      .padding(.top, 12)
      Spacer()
    }
    .transition(.move(edge: .top).combined(with: .opacity))
    .accessibilityIdentifier("native-system-route-banner")
  }

  /// 当前是否处于普通 iPhone 横屏紧凑高度形态（底部标签栏压缩、垂直可用高度约 354–393pt）。
  private var isCompactPhoneLandscape: Bool {
    verticalSizeClass == .compact && !NativeDeviceLayout.isIPad && !usesDuoSideOperationBar
  }

  /// 从 MoviePilot 发现、推荐与媒体服务器端点读取真实海报与进度，已加载过则静默复用缓存，仅显式刷新时重拉。
  private func loadDiscovery(forceRefresh: Bool = false) async {
    if !forceRefresh && hasLoadedDiscoveryOnce && !discovery.rails.isEmpty {
      return
    }
    let generation = UUID()
    discoveryGeneration = generation
    let showLoading = discovery.rails.isEmpty && discovery.featuredItems.isEmpty
    if showLoading {
      discovery = NativeDiscoverContent(
        featuredItems: discovery.featuredItems, rails: discovery.rails,
        continueWatching: discovery.continueWatching, providers: discovery.providers,
        categories: discovery.categories,
        moduleOrder: discoverModules.filter(\.enabled).map(\.id),
        isLoading: true, loadFailed: discovery.loadFailed
      )
    }

    async let modulesTask = try? requestDiscoverModules()
    async let extraSourcesTask = requestRecommendSources()
    async let moviesTask = try? requestDiscoverMedia("tmdb_movies", page: 1)
    async let tvTask = try? requestDiscoverMedia("tmdb_tvs", page: 1)
    async let trendingTask = try? requestRecommendMedia("tmdb_trending", page: 1)
    async let clientsTask = try? requestMediaServerClients()
    let (loadedModules, loadedExtraSources, movies, television, trending, clients) = await (
      modulesTask, extraSourcesTask, moviesTask, tvTask, trendingTask, clientsTask
    )
    guard !Task.isCancelled, discoveryGeneration == generation else { return }

    extraRecommendSources = loadedExtraSources
    let resolvedModules = NativeDiscoverModuleItem.merged(
      saved: loadedModules ?? discoverModules,
      extraSources: loadedExtraSources
    )
    discoverModules = resolvedModules
    let enabledSet = Set(resolvedModules.filter(\.enabled).map(\.id))

    let enabledPluginSources: [(NativeDiscoverModuleID, RecommendSource)] =
      loadedExtraSources
      .compactMap { src in
        let modID = NativeDiscoverModuleID.pluginRecommend(src.apiPath)
        return enabledSet.contains(modID) ? (modID, src) : nil
      }
    async let pluginRailsTask = fetchEnabledPluginRecommendRails(enabledPluginSources)

    async let doubanMusicTask: [NativeDiscoverMusicItem]? =
      enabledSet.contains(.doubanMusic)
      ? (try? requestRecommendMusic("music_douban", page: 1)) : nil
    async let doubanShowingTask: [NativeDiscoverAPIItem]? =
      enabledSet.contains(.doubanShowing)
      ? (try? requestRecommendMedia("douban_showing", page: 1)) : nil
    async let doubanTopTask: [NativeDiscoverAPIItem]? =
      enabledSet.contains(.doubanTop250)
      ? (try? requestRecommendMedia("douban_movie_top250", page: 1)) : nil

    var continueWatching: [NativeDiscoverProgress] = []
    var latestItems: [NativeDiscoverMedia] = []
    var providers: [NativeDiscoverProvider] = []
    var nextMediaServerItems: [String: MediaServerNavigationTarget] = [:]
    if let server = clients?.first?.name, !server.isEmpty {
      latestServerName = server
      async let playingTask = try? requestMediaServerPlaying(server: server)
      async let latestTask = try? requestMediaServerLatest(server: server, count: 20, page: 1)
      async let libraryTask = try? requestMediaServerLibraries(server: server)
      let (playingRows, latestRows, libraryRows) = await (playingTask, latestTask, libraryTask)
      guard !Task.isCancelled, discoveryGeneration == generation else { return }
      continueWatching = (playingRows ?? []).compactMap {
        projectContinueWatching($0, server: server)
      }
      for progress in continueWatching {
        if let itemID = progress.itemID, !itemID.isEmpty {
          nextMediaServerItems[progress.media.id] = .detail(
            server: progress.server ?? server,
            itemID: itemID,
            fallbackTitle: progress.media.title,
            fallbackItemType: progress.media.mediaServerItemType,
            fallbackPoster: progress.media.posterReference
          )
        }
      }
      latestItems = (latestRows ?? []).compactMap { projectLatestItem($0, server: server) }
      for media in latestItems {
        if let itemID = media.mediaServerItemID, !itemID.isEmpty {
          nextMediaServerItems[media.id] = .detail(
            server: media.mediaServerName ?? server,
            itemID: itemID,
            fallbackTitle: media.title,
            fallbackItemType: media.mediaServerItemType,
            fallbackPoster: media.posterReference
          )
        }
      }
      let defaultType = clients?.first?.type
      providers = (libraryRows ?? []).compactMap {
        projectLibraryProvider($0, server: server, defaultServerType: defaultType)
      }
    } else {
      latestServerName = nil
    }

    let (doubanMusic, doubanShowing, doubanTop, loadedPluginRails) = await (
      doubanMusicTask, doubanShowingTask, doubanTopTask, pluginRailsTask
    )
    guard !Task.isCancelled, discoveryGeneration == generation else { return }

    var rails: [NativeDiscoverRail] = []
    var identities: [String: NativeMediaIdentity] = [:]
    var nextMusicSeeds: [String: NativeMusicCardItem] = [:]
    let projectedMovies = movies.map {
      projectPage($0, fallbackType: "电影", identities: &identities)
    }
    let projectedTVs = television.map {
      projectPage($0, fallbackType: "电视剧", identities: &identities)
    }
    if let projectedMovies {
      rails.append(
        NativeDiscoverRail(
          id: "movies", title: "热门电影",
          items: projectedMovies,
          hasMore: !projectedMovies.isEmpty))
    }
    if let projectedTVs {
      rails.append(
        NativeDiscoverRail(
          id: "television", title: "热门剧集",
          items: projectedTVs,
          hasMore: !projectedTVs.isEmpty))
    }
    if let trending, !trending.isEmpty {
      rails.append(
        NativeDiscoverRail(
          id: "trending", title: "本周趋势",
          items: projectPage(trending, fallbackType: "电影", identities: &identities),
          hasMore: true, style: .backdrop))
    }
    if let doubanMusic, !doubanMusic.isEmpty {
      let projectedMusic = projectMusicPage(
        doubanMusic, identities: &identities, seeds: &nextMusicSeeds)
      if !projectedMusic.isEmpty {
        rails.append(
          NativeDiscoverRail(
            id: "doubanMusic", title: "热门音乐",
            items: projectedMusic,
            hasMore: true, style: .square))
      }
    }
    if let doubanShowing, !doubanShowing.isEmpty {
      rails.append(
        NativeDiscoverRail(
          id: "doubanShowing", title: "豆瓣热映",
          items: projectPage(doubanShowing, fallbackType: "电影", identities: &identities),
          hasMore: true))
    }
    if let doubanTop, !doubanTop.isEmpty {
      rails.append(
        NativeDiscoverRail(
          id: "doubanTop250", title: "豆瓣 Top250",
          items: projectPage(doubanTop, fallbackType: "电影", identities: &identities),
          hasMore: true))
    }
    if !latestItems.isEmpty {
      rails.append(
        NativeDiscoverRail(
          id: "latest", title: "最新入库", items: latestItems, hasMore: latestItems.count >= 20))
    }
    for entry in loadedPluginRails where !entry.rail.items.isEmpty {
      rails.append(entry.rail)
      for (k, v) in entry.identities { identities[k] = v }
      for (k, v) in entry.musicSeeds { nextMusicSeeds[k] = v }
    }
    musicSeeds = nextMusicSeeds
    mediaServerItems = nextMediaServerItems
    railNextPage = [:]
    loadingRailIDs = []

    let exploreCategories: [NativeDiscoverCategory] = [
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.tmdbMovies.rawValue, title: "TheMovieDB 电影",
        posterReference: projectedMovies?.first?.posterReference),
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.tmdbTVs.rawValue, title: "TheMovieDB 剧集",
        posterReference: projectedTVs?.first?.posterReference),
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.doubanMovies.rawValue, title: "豆瓣电影",
        posterReference: doubanShowing?.first?.posterPath
          ?? projectedMovies?.dropFirst().first?.posterReference),
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.doubanTVs.rawValue, title: "豆瓣剧集",
        posterReference: projectedTVs?.dropFirst().first?.posterReference),
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.bangumi.rawValue, title: "Bangumi 番剧",
        posterReference: projectedTVs?.dropFirst(2).first?.posterReference),
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.music.rawValue, title: "音乐探索",
        posterReference: doubanMusic?.first?.coverURL
          ?? doubanMusic?.first?.posterPath
          ?? projectedMovies?.dropFirst(2).first?.posterReference),
    ]

    let heroPool: [(NativeDiscoverAPIItem, String)] =
      (trending?.isEmpty == false
        ? (trending ?? []).prefix(6).map { ($0, $0.type ?? "电影") }
        : (movies ?? []).prefix(4).map { ($0, "电影") }
          + (television ?? []).prefix(2).map { ($0, "电视剧") })
    var featuredSeen: Set<String> = []
    let featuredItems: [NativeDiscoverFeature] = heroPool.compactMap { item, fallback in
      guard let media = project(item, fallbackType: fallback),
        featuredSeen.insert(media.id).inserted
      else { return nil }
      if let identity = media.identity { identities[media.id] = identity }
      let genreText = item.genreNames.prefix(3).joined(separator: " ")
      let dateText = item.releaseDate?.isEmpty == false ? item.releaseDate : media.year
      let subtitle = [
        genreText.isEmpty ? media.identity?.type : genreText,
        dateText,
      ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
      let seedRatings = NativeMediaRatingsStore.seedBadges(
        source: item.mediaSource ?? media.identity?.source ?? "themoviedb",
        voteAverage: item.voteAverage
      )
      return NativeDiscoverFeature(
        id: media.id,
        title: media.title,
        subtitle: subtitle,
        synopsis: item.overview ?? "",
        rating: item.voteAverage.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
        ratings: seedRatings,
        backdropReference: item.backdropPath ?? item.posterPath,
        logoReference: item.logoPath,
        logoLanguage: item.logoLanguage,
        originalLanguage: item.originalLanguage
      )
    }
    discovery = NativeDiscoverContent(
      featuredItems: featuredItems, rails: rails, continueWatching: continueWatching,
      providers: providers, categories: exploreCategories,
      moduleOrder: resolvedModules.filter(\.enabled).map(\.id),
      loadFailed: movies == nil || television == nil)
    mediaIdentities = identities
    hasLoadedDiscoveryOnce = true

    // 异步补拉主视觉透明标题 Logo、风格摘要与免配置多源评分，不阻塞发现首屏呈现。
    Task {
      await NativeMediaLanguageStore.shared.refresh(using: session, force: forceRefresh)
      await enrichFeaturedLogos(
        generation: generation, items: featuredItems, identities: identities)
    }
  }

  /// 为主视觉条目异步补拉 `GET /api/v1/media/{id}` 透明标题 Logo 与免配置多元评分（IMDb / TMDB / 豆瓣 / Bangumi）。
  private func enrichFeaturedLogos(
    generation: UUID, items: [NativeDiscoverFeature], identities: [String: NativeMediaIdentity]
  ) async {
    var updated = items
    var changed = false
    for index in updated.indices.prefix(6) {
      guard !Task.isCancelled, discoveryGeneration == generation else { return }
      guard let identity = identities[updated[index].id] else {
        continue
      }
      do {
        let endpoint = try APIEndpoint(
          path: ["media", identity.mediaID],
          query: [
            URLQueryItem(name: "media_source", value: identity.source),
            URLQueryItem(name: "type_name", value: identity.type),
          ])
        let detail = try await session.request(
          endpoint, as: NativeDiscoverAPIItem.self, requiring: .init(category: .discovery)
        ).value
        let preferredMediaLanguage = NativeMediaLanguageStore.shared.preferredMediaLanguage(
          for: session)
        let current = updated[index]
        let acceptedLogo: String?
        if let existingLogo = current.logoReference, !existingLogo.isEmpty {
          acceptedLogo = existingLogo
        } else {
          let logoDecision = NativeMediaLogoLanguagePolicy.metadataDecision(
            logoLanguage: detail.logoLanguage,
            preferredMediaLanguage: preferredMediaLanguage
          )
          if let logo = detail.logoPath, !logo.isEmpty, logoDecision != .confirmedMismatch {
            acceptedLogo = logo
          } else {
            acceptedLogo = nil
          }
        }
        let enrichedRatings = await NativeMediaRatingsStore.shared.resolveRatings(
          session: session,
          query: NativeMediaRatingsQuery(
            source: detail.mediaSource ?? identity.source,
            mediaID: detail.mediaID ?? identity.mediaID,
            type: detail.type ?? identity.type,
            title: detail.title ?? current.title,
            year: detail.year,
            tmdbID: detail.tmdbID.map(String.init),
            imdbID: detail.imdbID,
            doubanID: detail.doubanID,
            bangumiID: detail.bangumiID.map(String.init),
            anilistID: detail.anilistID.map(String.init),
            seedVote: detail.voteAverage,
            genres: detail.genreNames,
            originalLanguage: detail.originalLanguage ?? current.originalLanguage,
            alreadyLoadedPrimarySource: true
          )
        )
        guard !Task.isCancelled, discoveryGeneration == generation else { return }
        let genreText = detail.genreNames.prefix(3).joined(separator: " ")
        let dateText = detail.releaseDate?.isEmpty == false ? detail.releaseDate : detail.year
        let richSubtitle = [genreText, dateText].compactMap { $0 }.filter { !$0.isEmpty }
          .joined(separator: " · ")
        let nextFeature = NativeDiscoverFeature(
          id: current.id,
          title: current.title,
          subtitle: richSubtitle.isEmpty ? current.subtitle : richSubtitle,
          synopsis: current.synopsis.isEmpty ? (detail.overview ?? "") : current.synopsis,
          rating: current.rating,
          ratings: enrichedRatings.isEmpty ? current.ratings : enrichedRatings,
          backdropReference: current.backdropReference ?? detail.backdropPath,
          logoReference: acceptedLogo,
          logoLanguage: acceptedLogo != nil ? (current.logoLanguage ?? detail.logoLanguage) : nil,
          originalLanguage: detail.originalLanguage ?? current.originalLanguage
        )
        if nextFeature != current {
          updated[index] = nextFeature
          changed = true
          // 首个或任一主视觉拿到中文 Logo 或多源评分后立即刷新，不等其余精选条目全部串行返回。
          discovery = NativeDiscoverContent(
            featuredItems: updated,
            rails: discovery.rails,
            continueWatching: discovery.continueWatching,
            providers: discovery.providers,
            categories: discovery.categories,
            moduleOrder: discovery.moduleOrder,
            isLoading: discovery.isLoading,
            loadFailed: discovery.loadFailed
          )
        }
      } catch {
        continue
      }
    }
    guard changed, !Task.isCancelled, discoveryGeneration == generation else { return }
    discovery = NativeDiscoverContent(
      featuredItems: updated,
      rails: discovery.rails,
      continueWatching: discovery.continueWatching,
      providers: discovery.providers,
      categories: discovery.categories,
      moduleOrder: discovery.moduleOrder,
      isLoading: discovery.isLoading,
      loadFailed: discovery.loadFailed
    )
  }

  /// 读取当前用户持久化的发现模块显隐与顺序配置。
  private func requestDiscoverModules() async throws -> [NativeDiscoverModuleItem]? {
    let endpoint = try APIEndpoint(path: ["user", "config", "NativeDiscoverModules"])
    let wrapper = try await session.request(
      endpoint, as: NativeUserConfigValue<[NativeDiscoverModuleItem]>.self
    ).value
    return wrapper.value
  }

  /// 兼容裸数组 `[T]` 与 `{"success": true, "message": String?, "data": [T]}` 的弹性解码器。
  private struct FlexibleRecommendEnvelope<Element: Decodable>: Decodable {
    let items: [Element]

    private enum CodingKeys: String, CodingKey {
      case success, data
    }

    init(from decoder: Decoder) throws {
      if let direct = try? [Element](from: decoder) {
        self.items = direct
        return
      }
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let ok = try container.decodeIfPresent(Bool.self, forKey: .success), !ok {
        self.items = []
        return
      }
      self.items = (try? container.decode([Element].self, forKey: .data)) ?? []
    }
  }

  private struct LoadedPluginRecommendRail {
    let rail: NativeDiscoverRail
    let identities: [String: NativeMediaIdentity]
    let musicSeeds: [String: NativeMusicCardItem]
  }

  /// 读取插件通过 `ChainEventType.RecommendSource` 动态注册的发现页推荐榜单（`GET /api/v1/recommend/source`）。
  private func requestRecommendSources() async -> [RecommendSource] {
    guard let endpoint = try? RecommendSourceEndpoint.list(),
      let raw = try? await session.requestPayload(
        endpoint, requiring: .init(category: .discovery)
      ).value,
      let decoded = try? JSONDecoder().decode(
        FlexibleRecommendEnvelope<RecommendSource>.self, from: raw)
    else { return [] }
    var seen: Set<String> = []
    return decoded.items.filter { src in
      let cleanName = src.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanName.isEmpty,
        (try? RecommendSourceEndpoint.media(apiPath: src.apiPath)) != nil
      else { return false }
      return seen.insert(src.apiPath).inserted
    }
  }

  /// 并发拉取所有已启用的插件动态推荐榜单首页内容，单条失败互不影响。
  private func fetchEnabledPluginRecommendRails(
    _ sources: [(NativeDiscoverModuleID, RecommendSource)]
  ) async -> [LoadedPluginRecommendRail] {
    guard !sources.isEmpty else { return [] }
    return await withTaskGroup(of: (Int, LoadedPluginRecommendRail?).self) { group in
      for (index, pair) in sources.enumerated() {
        let (modID, source) = pair
        group.addTask {
          guard let pageResult = try? await self.requestPluginRecommendPage(source, page: 1),
            !pageResult.items.isEmpty
          else {
            return (index, nil)
          }
          let rail = NativeDiscoverRail(
            id: modID.rawValue,
            title: source.name,
            items: pageResult.items,
            hasMore: pageResult.hasMore,
            style: pageResult.style
          )
          return (
            index,
            LoadedPluginRecommendRail(
              rail: rail,
              identities: pageResult.identities,
              musicSeeds: pageResult.musicSeeds
            )
          )
        }
      }
      var ordered: [(Int, LoadedPluginRecommendRail)] = []
      for await (idx, loaded) in group {
        if let loaded { ordered.append((idx, loaded)) }
      }
      return ordered.sorted { $0.0 < $1.0 }.map(\.1)
    }
  }

  /// 按插件声明的受控相对 `api_path` 请求单页推荐数据，自动兼容影视海报与音乐专辑两种载荷。
  private func requestPluginRecommendPage(_ source: RecommendSource, page: Int) async throws -> (
    items: [NativeDiscoverMedia],
    hasMore: Bool,
    style: NativeDiscoverRail.Style,
    identities: [String: NativeMediaIdentity],
    musicSeeds: [String: NativeMusicCardItem]
  ) {
    let endpoint = try RecommendSourceEndpoint.media(
      apiPath: source.apiPath, page: page > 1 ? page : nil)
    let raw = try await session.requestPayload(
      endpoint, requiring: .init(category: .discovery)
    ).value
    let lowerType = source.type.lowercased()
    let prefersMusic = lowerType.contains("music") || source.type.contains("音乐")
    if prefersMusic,
      let musicEnv = try? JSONDecoder().decode(
        FlexibleRecommendEnvelope<NativeDiscoverMusicItem>.self, from: raw),
      !musicEnv.items.isEmpty
    {
      var identities: [String: NativeMediaIdentity] = [:]
      var seeds: [String: NativeMusicCardItem] = [:]
      let projected = projectMusicPage(musicEnv.items, identities: &identities, seeds: &seeds)
      return (projected, !musicEnv.items.isEmpty, .square, identities, seeds)
    }
    let decoded = try JSONDecoder().decode(
      FlexibleRecommendEnvelope<NativeDiscoverAPIItem>.self, from: raw)
    let fallbackType: String =
      if lowerType.contains("tv") || source.type.contains("剧")
        || lowerType.contains("anime") || source.type.contains("番")
      {
        "电视剧"
      } else {
        "电影"
      }
    var identities: [String: NativeMediaIdentity] = [:]
    let projected = projectPage(
      decoded.items, fallbackType: fallbackType, identities: &identities)
    return (projected, !decoded.items.isEmpty, .poster, identities, [:])
  }

  /// 单次持久化发现模块显隐与排序，并在需要时重新拉取新启用的豆瓣榜单。
  private func saveDiscoverModules(_ updated: [NativeDiscoverModuleItem]) async -> Bool {
    do {
      let body = try JSONEncoder().encode(updated)
      let endpoint = try APIEndpoint(
        path: ["user", "config", "NativeDiscoverModules"], method: .post, body: body)
      try await session.perform(endpoint)
      let needsRefetch = updated.contains { item in
        item.enabled
          && (item.id == .doubanShowing || item.id == .doubanTop250 || item.id.isPluginRecommend)
          && !discovery.rails.contains(where: { $0.id == item.id.rawValue })
      }
      discoverModules = updated
      if needsRefetch {
        pendingModuleRefetch = true
      } else {
        discovery = NativeDiscoverContent(
          featuredItems: discovery.featuredItems, rails: discovery.rails,
          continueWatching: discovery.continueWatching, providers: discovery.providers,
          categories: discovery.categories,
          moduleOrder: updated.filter(\.enabled).map(\.id),
          isLoading: discovery.isLoading, loadFailed: discovery.loadFailed)
      }
      return true
    } catch {
      return false
    }
  }

  /// 后端发现没有总页数，以空页结束，单条失败不会阻止另一条轨道展示。
  private func requestDiscoverMedia(_ name: String, page: Int) async throws
    -> [NativeDiscoverAPIItem]
  {
    let endpoint = try APIEndpoint(
      path: ["discover", name], query: [URLQueryItem(name: "page", value: String(page))])
    return try await session.request(
      endpoint, as: [NativeDiscoverAPIItem].self, requiring: .init(category: .discovery)
    ).value
  }

  /// 推荐榜单接口用于本周趋势与主视觉轮播，缺省失败不阻断核心发现栏。
  private func requestRecommendMedia(_ name: String, page: Int) async throws
    -> [NativeDiscoverAPIItem]
  {
    let endpoint = try APIEndpoint(
      path: ["recommend", name], query: [URLQueryItem(name: "page", value: String(page))])
    return try await session.request(
      endpoint, as: [NativeDiscoverAPIItem].self, requiring: .init(category: .discovery)
    ).value
  }

  /// 查询当前实例已启用的媒体服务器，用于在发现页呈现真实在看与媒体库。
  private func requestMediaServerClients() async throws -> [NativeMediaServerClient] {
    let endpoint = try APIEndpoint(path: ["mediaserver", "clients"])
    return try await session.request(
      endpoint, as: [NativeMediaServerClient].self, requiring: .init(category: .discovery)
    ).value
  }

  /// 读取媒体服务器正在观看列表，映射为发现页横向继续观看卡片。
  private func requestMediaServerPlaying(server: String) async throws
    -> [NativeMediaServerPlayItem]
  {
    let endpoint = try APIEndpoint(
      path: ["mediaserver", "playing"],
      query: [
        URLQueryItem(name: "server", value: server),
        URLQueryItem(name: "count", value: "12"),
      ])
    return try await session.request(
      endpoint, as: [NativeMediaServerPlayItem].self, requiring: .init(category: .discovery)
    ).value
  }

  /// 读取媒体服务器最新入库条目，支持 `page` 与 `count` 分页滚动加载。
  private func requestMediaServerLatest(
    server: String, count: Int = 20, page: Int? = nil
  ) async throws -> [NativeMediaServerPlayItem] {
    var query = [
      URLQueryItem(name: "server", value: server),
      URLQueryItem(name: "count", value: String(count)),
    ]
    if let page {
      query.append(URLQueryItem(name: "page", value: String(page)))
    }
    let endpoint = try APIEndpoint(path: ["mediaserver", "latest"], query: query)
    return try await session.request(
      endpoint, as: [NativeMediaServerPlayItem].self, requiring: .init(category: .discovery)
    ).value
  }

  /// 读取媒体服务器分类媒体库，展示库名、数量与封面。
  private func requestMediaServerLibraries(server: String) async throws
    -> [NativeMediaServerLibrary]
  {
    let endpoint = try APIEndpoint(
      path: ["mediaserver", "library"], query: [URLQueryItem(name: "server", value: server)])
    return try await session.request(
      endpoint, as: [NativeMediaServerLibrary].self, requiring: .init(category: .discovery)
    ).value
  }

  /// 发现页横向轨道滑到末尾时静默追加下一页，支持最新入库与各推荐栏无限横滑。
  private func loadMoreDiscoverRail(_ railID: String) async {
    guard !loadingRailIDs.contains(railID),
      let railIndex = discovery.rails.firstIndex(where: { $0.id == railID }),
      discovery.rails[railIndex].hasMore
    else { return }
    let nextPage = railNextPage[railID] ?? 2
    let generation = discoveryGeneration
    loadingRailIDs.insert(railID)
    defer { loadingRailIDs.remove(railID) }
    do {
      let result = try await loadRailPage(railID, page: nextPage)
      guard !Task.isCancelled, discoveryGeneration == generation,
        let idx = discovery.rails.firstIndex(where: { $0.id == railID })
      else { return }
      var existing = Set(discovery.rails[idx].items.map(\.id))
      let additions = result.items.filter { existing.insert($0.id).inserted }
      for item in additions {
        if let identity = item.identity {
          mediaIdentities[item.id] = identity
        }
        if let msItemID = item.mediaServerItemID, !msItemID.isEmpty {
          mediaServerItems[item.id] = .detail(
            server: item.mediaServerName ?? latestServerName,
            itemID: msItemID,
            fallbackTitle: item.title,
            fallbackItemType: item.mediaServerItemType,
            fallbackPoster: item.posterReference
          )
        }
      }
      var updatedRails = discovery.rails
      let old = updatedRails[idx]
      updatedRails[idx] = NativeDiscoverRail(
        id: old.id, title: old.title, items: old.items + additions,
        hasMore: result.hasMore && !additions.isEmpty, style: old.style)
      railNextPage[railID] = nextPage + 1
      discovery = NativeDiscoverContent(
        featuredItems: discovery.featuredItems,
        rails: updatedRails,
        continueWatching: discovery.continueWatching,
        providers: discovery.providers,
        categories: discovery.categories,
        moduleOrder: discovery.moduleOrder,
        isLoading: discovery.isLoading,
        loadFailed: discovery.loadFailed)
    } catch {
      return
    }
  }

  /// 从发现卡片右键快捷订阅媒体（自动兼容影视与音乐类型）。
  private func quickSubscribeFromDiscover(_ media: NativeDiscoverMedia) async {
    guard canSubscribe else {
      routeHub.postBanner("当前账号无订阅权限。")
      return
    }
    guard let identity = media.identity else { return }
    var payload: [String: Any] = [
      "name": media.title,
      "type": identity.type,
      "media_source": identity.source,
      "media_id": identity.mediaID,
    ]
    if let year = media.year, !year.isEmpty {
      payload["year"] = year
    }
    if identity.source == "themoviedb", let tmdbID = Int(identity.mediaID) {
      payload["tmdbid"] = tmdbID
    } else if identity.source == "douban" || identity.source == "doubanmusic" {
      payload["doubanid"] = identity.mediaID
    }
    if identity.type == "电视剧" {
      payload["season"] = 1
    }
    do {
      let body = try JSONSerialization.data(withJSONObject: payload)
      let endpoint = try APIEndpoint(
        path: ["subscribe"], method: .post, body: body, trailingSlash: true)
      try await session.perform(endpoint, requiring: .init(category: .subscribe))
      NativePageDataCache.shared.remove("subscriptions|list", session: session)
      routeHub.postBanner("已添加订阅「\(media.title)」。")
    } catch {
      routeHub.postBanner("添加订阅「\(media.title)」失败，请稍后重试。")
    }
  }

  /// 拉取豆瓣等推荐音乐榜单（`GET /api/v1/recommend/{source}?page={page}`）。
  private func requestRecommendMusic(
    _ source: String, page: Int
  ) async throws -> [NativeDiscoverMusicItem] {
    let endpoint = try APIEndpoint(
      path: ["recommend", source], query: [URLQueryItem(name: "page", value: String(page))])
    return try await session.request(
      endpoint, as: [NativeDiscoverMusicItem].self, requiring: .init(category: .discovery)
    ).value
  }

  /// 将豆瓣音乐条目投影为 1:1 发现方卡并同步注册详情种子。
  private func projectMusicPage(
    _ items: [NativeDiscoverMusicItem],
    identities: inout [String: NativeMediaIdentity],
    seeds: inout [String: NativeMusicCardItem]
  ) -> [NativeDiscoverMedia] {
    var seen: Set<String> = []
    return items.compactMap { row in
      guard let card = row.toMusicCardItem(), seen.insert(card.id).inserted else { return nil }
      let identity = NativeMediaIdentity(
        source: card.mediaSource, mediaID: card.mediaID, type: "音乐")
      identities[card.id] = identity
      seeds[card.id] = card
      return NativeDiscoverMedia(
        id: card.id,
        title: card.title,
        year: card.yearText,
        detail: card.artist,
        posterReference: card.coverReference,
        backdropReference: nil,
        identity: identity
      )
    }
  }

  /// 分区只允许映射到已声明的后端接口，未呈现的接口不能从界面任意构造。
  private func loadRailPage(_ railID: String, page: Int) async throws
    -> (items: [NativeDiscoverMedia], hasMore: Bool)
  {
    if railID == "latest" {
      guard let server = latestServerName, !server.isEmpty else { return ([], false) }
      let rows = try await requestMediaServerLatest(server: server, count: 20, page: page)
      let projected = rows.compactMap { projectLatestItem($0, server: server) }
      return (projected, rows.count >= 20)
    }
    if railID == "doubanMusic" {
      let rows = try await requestRecommendMusic("music_douban", page: page)
      var identities: [String: NativeMediaIdentity] = [:]
      var seeds: [String: NativeMusicCardItem] = [:]
      let projected = projectMusicPage(rows, identities: &identities, seeds: &seeds)
      for (k, v) in identities { mediaIdentities[k] = v }
      for (k, v) in seeds { musicSeeds[k] = v }
      return (projected, !rows.isEmpty)
    }
    if let apiPath = NativeDiscoverModuleID(rawValue: railID).pluginAPIPath {
      let source =
        extraRecommendSources.first(where: { $0.apiPath == apiPath })
        ?? RecommendSource(name: apiPath, apiPath: apiPath, type: "")
      let loaded = try await requestPluginRecommendPage(source, page: page)
      for (k, v) in loaded.identities { mediaIdentities[k] = v }
      for (k, v) in loaded.musicSeeds { musicSeeds[k] = v }
      return (loaded.items, loaded.hasMore)
    }
    let rows: [NativeDiscoverAPIItem]
    let fallbackType: String
    switch railID {
    case "movies":
      rows = try await requestDiscoverMedia("tmdb_movies", page: page)
      fallbackType = "电影"
    case "television":
      rows = try await requestDiscoverMedia("tmdb_tvs", page: page)
      fallbackType = "电视剧"
    case "trending":
      rows = try await requestRecommendMedia("tmdb_trending", page: page)
      fallbackType = "电影"
    case "doubanShowing":
      rows = try await requestRecommendMedia("douban_showing", page: page)
      fallbackType = "电影"
    case "doubanTop250":
      rows = try await requestRecommendMedia("douban_movie_top250", page: page)
      fallbackType = "电影"
    default: throw APIError.invalidEndpoint
    }
    var identities: [String: NativeMediaIdentity] = [:]
    return (projectPage(rows, fallbackType: fallbackType, identities: &identities), !rows.isEmpty)
  }

  /// 媒体服务器继续观看条目保留后端标题、集数副标、服务器名、条目 ID 和实际播放进度百分比。
  private func projectContinueWatching(_ item: NativeMediaServerPlayItem, server: String)
    -> NativeDiscoverProgress?
  {
    guard let title = item.title, !title.isEmpty else { return nil }
    let rawItemID = item.itemID?.value ?? item.id?.value
    let identifier = rawItemID ?? title
    let resolvedServer = !server.isEmpty ? server : (item.server ?? server)
    let rawPercent = item.percent ?? 0
    let normalized = rawPercent > 1 ? rawPercent / 100.0 : rawPercent
    let label =
      rawPercent > 0
      ? "看到 \(Int(min(max(normalized * 100, 0), 100).rounded()))%" : (item.subtitle ?? "继续观看")
    let media = NativeDiscoverMedia(
      id: "playing|\(identifier)",
      title: title,
      year: item.year?.value,
      detail: item.subtitle,
      posterReference: item.image,
      mediaServerItemID: rawItemID,
      mediaServerName: resolvedServer,
      mediaServerItemType: item.type
    )
    return NativeDiscoverProgress(
      media: media, progress: normalized, progressLabel: label,
      itemID: rawItemID, server: resolvedServer)
  }

  /// 媒体服务器最新入库条目保留真实海报、年份/副标与媒体服务器条目标识，点击进入原生媒体服务器详情页。
  private func projectLatestItem(_ item: NativeMediaServerPlayItem, server: String)
    -> NativeDiscoverMedia?
  {
    guard let title = item.title, !title.isEmpty else { return nil }
    let rawItemID = item.itemID?.value ?? item.id?.value
    let identifier = rawItemID ?? title
    let resolvedServer = !server.isEmpty ? server : (item.server ?? server)
    return NativeDiscoverMedia(
      id: "latest|\(identifier)",
      title: title,
      year: item.year?.value ?? item.subtitle,
      posterReference: item.image,
      mediaServerItemID: rawItemID,
      mediaServerName: resolvedServer,
      mediaServerItemType: item.type
    )
  }

  /// 媒体库卡片按服务端库名、数量与主图投影，点击进入应用内原生媒体库浏览页；始终使用已配置的真实服务器实例名而非模块返回的小写类型名。
  private func projectLibraryProvider(
    _ item: NativeMediaServerLibrary, server: String, defaultServerType: String?
  ) -> NativeDiscoverProvider? {
    guard let name = item.name, !name.isEmpty else { return nil }
    let identifier = item.itemID?.value ?? item.id?.value ?? name
    return NativeDiscoverProvider(
      id: "library|\(identifier)",
      name: name,
      itemCount: item.itemCount,
      artworkReference: item.image ?? item.imageList?.first,
      server: !server.isEmpty ? server : (item.server ?? server),
      serverType: item.serverType ?? defaultServerType,
      serverID: item.serverID?.value,
      itemID: item.itemID?.value ?? item.id?.value,
      libraryType: item.type,
      link: item.link
    )
  }

  /// 同页重复身份只保留第一条，SwiftUI 海报键与详情路由保持一一对应。
  private func projectPage(
    _ items: [NativeDiscoverAPIItem], fallbackType: String,
    identities: inout [String: NativeMediaIdentity]
  ) -> [NativeDiscoverMedia] {
    var seen: Set<String> = []
    return items.compactMap { item in
      guard let media = project(item, fallbackType: fallbackType),
        let identity = media.identity, seen.insert(identity.id).inserted
      else { return nil }
      identities[media.id] = identity
      return media
    }
  }

  /// 卡片须有真实原生 ID（兼容 TMDB / 豆瓣 / Bangumi / AniList），缺失身份时不把标题当作后端 ID 提交。
  private func project(_ item: NativeDiscoverAPIItem, fallbackType: String) -> NativeDiscoverMedia?
  {
    let resolvedSource: String
    let resolvedID: String?
    if let explicitSource = item.mediaSource, !explicitSource.isEmpty,
      let explicitID = item.mediaID, !explicitID.isEmpty, explicitID != "0"
    {
      resolvedSource = explicitSource
      resolvedID = explicitID
    } else if let tmdbID = item.tmdbID, tmdbID > 0 {
      resolvedSource = "themoviedb"
      resolvedID = String(tmdbID)
    } else if let doubanID = item.doubanID, !doubanID.isEmpty, doubanID != "0" {
      resolvedSource = "douban"
      resolvedID = doubanID
    } else if let bangumiID = item.bangumiID, bangumiID > 0 {
      resolvedSource = "bangumi"
      resolvedID = String(bangumiID)
    } else if let anilistID = item.anilistID, anilistID > 0 {
      resolvedSource = "anilist"
      resolvedID = String(anilistID)
    } else {
      return nil
    }
    guard let mediaID = resolvedID else { return nil }
    let resolvedType = MediaSummaryItem.normalizeMediaType(item.type) ?? fallbackType
    let identity = NativeMediaIdentity(
      source: resolvedSource,
      mediaID: mediaID,
      type: resolvedType,
      seedTitle: item.title,
      seedPoster: item.posterPath,
      seedBackdrop: item.backdropPath
    )
    let genresSummary = item.genreNames.prefix(2).joined(separator: " / ")
    return NativeDiscoverMedia(
      id: identity.id,
      title: item.title ?? "未命名作品",
      year: item.year,
      detail: genresSummary.isEmpty
        ? item.voteAverage.flatMap { $0 > 0 ? "评分 \(String(format: "%.1f", $0))" : nil }
        : genresSummary,
      posterReference: item.posterPath,
      backdropReference: item.backdropPath,
      identity: identity
    )
  }
}

/// 媒体详情的受控来源、后端 ID 与影视类型，可选携带首帧过渡标题与海报种子，不包含任意详情 URL。
struct NativeMediaIdentity: Identifiable, Hashable, Sendable {
  let source: String
  let mediaID: String
  let type: String
  var seedTitle: String? = nil
  var seedPoster: String? = nil
  var seedBackdrop: String? = nil

  /// 路由身份覆盖主来源、媒体原生 ID 和媒体类别，避免跨轨道出现错误复用。
  var id: String { [source, mediaID, type].joined(separator: "|") }

  static func == (lhs: NativeMediaIdentity, rhs: NativeMediaIdentity) -> Bool {
    lhs.source == rhs.source && lhs.mediaID == rhs.mediaID && lhs.type == rhs.type
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(source)
    hasher.combine(mediaID)
    hasher.combine(type)
  }
}

/// 跨标签与侧边工作台可推入的受控业务路由。
enum NativeWorkspaceDestination: Hashable {
  case explore(NativeExploreSourceKind)
  case music
  case subscriptions
  case subscriptionsFiltered(NativeSubscriptionsPage.Filter)
  case subscribeCommunity
  case downloads
  case calendar
  case resources
  case resourcesQuery(keyword: String?, browseHome: Bool)
  case history
  case historyQuery(String)
  case sites
  case messages
  case agent
  case files
  case filesTarget(storage: String?, path: String?)
  case workflows
  case settingsHub
  case settings
  case systemModule(NativeSystemModulesPage.Domain)
  case diagnostics(NativeDiagnosticsToolsPage.Tool)
  case users
  case pluginMarket
  case appearance
  case channelAuth
  case subscribeSearchSettings
  case mediaSourceSettings
  case downloadersManage
  case mediaServersManage
  case mediaServerBindings
  case playbackSettings
}

/// 发现导航栈只接收已加载的分区、可验证媒体身份、媒体服务器目标或受控业务页面。
private enum NativeMediaDestination: Identifiable, Hashable {
  case rail(NativeDiscoverRail)
  case media(NativeMediaIdentity)
  case music(NativeMusicCardItem)
  case explore(NativeExploreSourceKind)
  case workspace(NativeWorkspaceDestination)
  case mediaServer(MediaServerNavigationTarget)

  /// 区分分区网格、详情、媒体服务器浏览与工作台页面路由。
  var id: String {
    switch self {
    case .rail(let rail): "rail:" + rail.id
    case .media(let identity): "media:" + identity.id
    case .music(let seed): "music:" + seed.id
    case .explore(let source): "explore:" + source.rawValue
    case .workspace(let dest): "workspace:\(dest.hashValue)"
    case .mediaServer(let target): "mediaserver:\(target.hashValue)"
    }
  }
}

/// `GET /api/v1/user/config/{key}` 统一返回值解码包装。
private struct NativeUserConfigValue<Value: Decodable & Sendable>: Decodable, Sendable {
  let value: Value?
}

/// 按实例同步并持久化后端 `/api/v1/system/global?token=moviepilot` 中的全局图片缓存开关与自定义图源域名。
@MainActor
final class NativeGlobalImageSettingsStore {
  static let shared = NativeGlobalImageSettingsStore()

  private var loadedGenerations: Set<UUID> = []
  private var inFlightTasks: [UUID: Task<APIImageSettings, Never>] = [:]
  private var cachedByInstance: [UUID: APIImageSettings] = [:]

  private init() {}

  private func defaultsKey(for instanceID: UUID) -> String {
    "mp.native.globalImageSettings.\(instanceID.uuidString)"
  }

  /// 读取当前实例已知的图片配置（优先内存，其次本地持久化快照）。
  func currentSettings(for session: NativeSession) -> APIImageSettings {
    let instanceID = session.scope.instanceID
    if let cached = cachedByInstance[instanceID] {
      if session.imageSettings != cached {
        session.updateImageSettings(cached)
      }
      return cached
    }
    if let data = UserDefaults.standard.data(forKey: defaultsKey(for: instanceID)),
      let decoded = try? JSONDecoder().decode(APIImageSettings.self, from: data)
    {
      cachedByInstance[instanceID] = decoded
      session.updateImageSettings(decoded)
      return decoded
    }
    return session.imageSettings
  }

  private func persist(_ settings: APIImageSettings, for session: NativeSession) {
    let instanceID = session.scope.instanceID
    cachedByInstance[instanceID] = settings
    session.updateImageSettings(settings)
    if let data = try? JSONEncoder().encode(settings) {
      UserDefaults.standard.set(data, forKey: defaultsKey(for: instanceID))
    }
  }

  /// 确保当前会话代次至少向后端同步一次全局图片配置；并发图片请求自动合并等待同一次查询。
  @discardableResult
  func ensureLoaded(using session: NativeSession, force: Bool = false) async -> APIImageSettings {
    let baseline = currentSettings(for: session)
    let generation = session.scope.generation
    if !force && loadedGenerations.contains(generation) {
      return baseline
    }
    if !force, let running = inFlightTasks[generation] {
      return await running.value
    }
    let task = Task<APIImageSettings, Never> { @MainActor in
      defer { self.inFlightTasks.removeValue(forKey: generation) }
      guard
        let endpoint = try? APIEndpoint(
          path: ["system", "global"],
          query: [URLQueryItem(name: "token", value: "moviepilot")]
        )
      else {
        return baseline
      }
      struct GlobalPayload: Decodable, Sendable {
        let globalImageCache: Bool?
        let tmdbImageDomain: String?
        let bangumiProxyEnable: Bool?
        let bangumiImageDomain: String?

        private enum CodingKeys: String, CodingKey {
          case globalImageCache = "GLOBAL_IMAGE_CACHE"
          case tmdbImageDomain = "TMDB_IMAGE_DOMAIN"
          case bangumiProxyEnable = "BANGUMI_PROXY_ENABLE"
          case bangumiImageDomain = "BANGUMI_IMAGE_DOMAIN"
        }
      }
      do {
        let payload = try await session.request(endpoint, as: GlobalPayload.self).value
        let updated = APIImageSettings(
          globalImageCache: payload.globalImageCache ?? baseline.globalImageCache,
          tmdbImageDomain: payload.tmdbImageDomain ?? baseline.tmdbImageDomain,
          bangumiProxyEnable: payload.bangumiProxyEnable ?? baseline.bangumiProxyEnable,
          bangumiImageDomain: payload.bangumiImageDomain ?? baseline.bangumiImageDomain
        )
        self.loadedGenerations.insert(generation)
        self.persist(updated, for: session)
        return updated
      } catch {
        // 旧版后端或管理员实例可回退读取 `/system/env`
        if session.user.isSuperuser,
          let envEndpoint = try? APIEndpoint(path: ["system", "env"]),
          let payload = try? await session.request(envEndpoint, as: GlobalPayload.self).value
        {
          let updated = APIImageSettings(
            globalImageCache: payload.globalImageCache ?? baseline.globalImageCache,
            tmdbImageDomain: payload.tmdbImageDomain ?? baseline.tmdbImageDomain,
            bangumiProxyEnable: payload.bangumiProxyEnable ?? baseline.bangumiProxyEnable,
            bangumiImageDomain: payload.bangumiImageDomain ?? baseline.bangumiImageDomain
          )
          self.loadedGenerations.insert(generation)
          self.persist(updated, for: session)
          return updated
        }
        self.loadedGenerations.insert(generation)
        return baseline
      }
    }
    inFlightTasks[generation] = task
    return await task.value
  }

  /// 在系统设置页保存成功后立即同步最新全局图片缓存开关与图源域名，并后台刷新一次 `/system/global`。
  func applySystemEnvUpdate(
    globalImageCache: Bool,
    tmdbImageDomain: String,
    bangumiProxyEnable: Bool,
    for session: NativeSession
  ) {
    var next = currentSettings(for: session)
    next.globalImageCache = globalImageCache
    next.tmdbImageDomain = APIImageSettings.normalizeTMDBDomain(tmdbImageDomain)
    next.bangumiProxyEnable = bangumiProxyEnable
    persist(next, for: session)
    Task { @MainActor in
      _ = await self.ensureLoaded(using: session, force: true)
    }
  }
}

/// 搜索结果和发现海报显示后端提供的 HTTPS 图片，优先命中同步内存缓存与本地磁盘缓存，无闪烁回显。
@MainActor
struct NativeMediaArtwork: View {
  let session: NativeSession
  let reference: String?
  let role: NativeDiscoverArtworkRole
  let maximumWidth: Int
  var useCookies: Bool = false
  var onImageResolved: ((UIImage) -> Void)? = nil
  @Environment(\.colorScheme) private var colorScheme
  @State private var image: UIImage?
  @State private var loadedKey: String?

  /// 首帧同步读取内存缓存，命中时直接呈现海报，避免返回页面或切换标签时闪烁占位图。
  var body: some View {
    let key = cacheKey
    let resolvedImage: UIImage? =
      if loadedKey == key, let image {
        image
      } else {
        NativeMediaArtworkCache.shared.memoryImage(for: key)
      }
    return GeometryReader { bounds in
      Group {
        if let resolvedImage {
          Image(uiImage: resolvedImage).resizable().scaledToFill()
        } else {
          placeholder
        }
      }
      .frame(width: bounds.size.width, height: bounds.size.height)
      .clipped()
    }
    .task(id: key) { await load(for: key) }
    .accessibilityHidden(true)
  }

  /// 规范化图片地址并构造持久化缓存键（按服务器实例、用户与尺寸隔离）。
  private func normalizedURL(using settings: APIImageSettings) -> URL? {
    guard let raw = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty, raw.utf8.count <= 16_384
    else { return nil }
    if raw.hasPrefix("/"), !raw.hasPrefix("/api/"), !raw.contains(".."), !raw.contains(" ") {
      let bucket = maximumWidth <= 500 ? "w500" : (maximumWidth <= 800 ? "w780" : "w1280")
      let domain = APIImageSettings.normalizeTMDBDomain(settings.tmdbImageDomain)
      return URL(string: "https://\(domain)/t/p/\(bucket)\(raw)")
    }
    guard var components = URLComponents(string: raw),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      components.host?.isEmpty == false,
      components.user == nil, components.password == nil
    else { return nil }
    components.fragment = nil
    if components.path.hasPrefix("/t/p/original/") {
      let bucket = maximumWidth <= 500 ? "w500" : (maximumWidth <= 800 ? "w780" : "w1280")
      components.path =
        "/t/p/\(bucket)/" + components.path.dropFirst("/t/p/original/".count)
    }
    return components.url
  }

  /// 二级缓存加载：L1 内存命中直出 → L2 本地磁盘后台解码 → 按全局图片缓存策略拉取并落盘。
  private func load(for key: String) async {
    guard (try? session.checkActive()) != nil else { return }
    if let cached = NativeMediaArtworkCache.shared.memoryImage(for: key) {
      image = cached
      loadedKey = key
      onImageResolved?(cached)
      return
    }
    if loadedKey != key {
      image = nil
    }
    let scopeDir = NativeMediaArtworkCache.scopeDirectoryName(for: session)
    let limit = maximumWidth
    if let diskImage = await NativeMediaArtworkCache.shared.diskImage(
      for: key, scopeDir: scopeDir, limit: limit)
    {
      guard !Task.isCancelled else { return }
      image = diskImage
      loadedKey = key
      onImageResolved?(diskImage)
      return
    }
    let settings = await NativeGlobalImageSettingsStore.shared.ensureLoaded(using: session)
    guard !Task.isCancelled, let url = normalizedURL(using: settings) else { return }
    let cookiesFlag = useCookies
    let decoded = await NativeMediaArtworkCache.shared.fetchAndCache(
      key: key, scopeDir: scopeDir, limit: limit
    ) {
      let response = try await session.requestDisplayImage(
        url, maximumWidth: limit, useCookies: cookiesFlag)
      return response.data
    }
    guard !Task.isCancelled, let decoded else { return }
    image = decoded
    loadedKey = key
    onImageResolved?(decoded)
  }

  /// 缓存键覆盖服务器实例、用户 ID、尺寸与规范化 URL，跨冷启动复用本地磁盘缓存，登出时按作用域清理。
  private var cacheKey: String {
    let settings = NativeGlobalImageSettingsStore.shared.currentSettings(for: session)
    return [
      session.scope.instanceID.uuidString,
      String(session.scope.userID),
      String(maximumWidth),
      normalizedURL(using: settings)?.absoluteString ?? reference ?? "",
    ].joined(separator: "|")
  }

  /// 图片加载前的透明玻璃占位面：仅以中性微光透出页面背景，不叠实色灰底或默认占位图。
  private var placeholder: some View {
    let isLight = colorScheme == .light
    return Rectangle()
      .fill(
        LinearGradient(
          colors: isLight
            ? [Color.white.opacity(0.32), Color.white.opacity(0.10), Color.white.opacity(0.20)]
            : [Color.white.opacity(0.08), Color.white.opacity(0.018), Color.white.opacity(0.045)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
  }
}

/// 二级图片缓存（L1 128MB 内存 + L2 250MB 本地 Caches 磁盘 + 并发请求合并），按实例与用户隔离存储。
@MainActor
final class NativeMediaArtworkCache {
  static let shared = NativeMediaArtworkCache()

  private let images = NSCache<NSString, UIImage>()
  private var inFlight: [String: Task<UIImage?, Never>] = [:]
  private var writesSincePrune = 0
  nonisolated private static let maxDiskBytes: Int64 = 250 * 1024 * 1024
  nonisolated private static let targetDiskBytes: Int64 = 180 * 1024 * 1024

  private init() {
    images.totalCostLimit = 128 * 1024 * 1024
    images.countLimit = 600
  }

  /// 按当前实例与用户生成隔离的磁盘缓存子目录名。
  static func scopeDirectoryName(for session: NativeSession) -> String {
    "\(session.scope.instanceID.uuidString)_\(session.scope.userID)"
  }

  /// 同步读取 L1 内存缓存。
  func memoryImage(for key: String) -> UIImage? {
    images.object(forKey: key as NSString)
  }

  /// 写入 L1 内存缓存。
  func storeMemory(_ image: UIImage, for key: String) {
    let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
    images.setObject(image, forKey: key as NSString, cost: max(cost, 4096))
  }

  /// 后台线程读取 L2 磁盘缓存并解码缩略图，命中后同步回填 L1 内存缓存。
  func diskImage(for key: String, scopeDir: String, limit: Int) async -> UIImage? {
    let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
      guard let fileURL = Self.diskFileURL(for: key, scopeDir: scopeDir),
        let data = try? Data(contentsOf: fileURL), !data.isEmpty
      else { return nil }
      // 更新访问时间用于 LRU 淘汰
      try? FileManager.default.setAttributes(
        [.modificationDate: Date()], ofItemAtPath: fileURL.path)
      return Self.decodeThumbnail(data, limit: limit)
    }.value
    if let decoded {
      storeMemory(decoded, for: key)
    }
    return decoded
  }

  /// 合并同一缓存键的并发网络请求，成功后后台落盘并写入 L1 内存缓存。
  func fetchAndCache(
    key: String,
    scopeDir: String,
    limit: Int,
    fetcher: @escaping @Sendable () async throws -> Data
  ) async -> UIImage? {
    if let cached = memoryImage(for: key) { return cached }
    if let existing = inFlight[key] {
      return await existing.value
    }
    let task = Task<UIImage?, Never> {
      do {
        let data = try await fetcher()
        guard !data.isEmpty else { return nil }
        let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
          if let fileURL = Self.diskFileURL(for: key, scopeDir: scopeDir) {
            let dir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
          }
          return Self.decodeThumbnail(data, limit: limit)
        }.value
        if let decoded {
          self.storeMemory(decoded, for: key)
          self.schedulePruneIfNeeded(scopeDir: scopeDir)
        }
        return decoded
      } catch {
        return nil
      }
    }
    inFlight[key] = task
    let result = await task.value
    inFlight.removeValue(forKey: key)
    return result
  }

  /// 仅清空内存缓存（切换服务器时使用）。
  func clearMemory() {
    images.removeAllObjects()
    for task in inFlight.values { task.cancel() }
    inFlight.removeAll()
  }

  /// 退出登录或手动清理时移除当前用户对应的内存与本地磁盘图片缓存。
  func clearSession(_ session: NativeSession) {
    clearMemory()
    let scopeDir = Self.scopeDirectoryName(for: session)
    Task.detached(priority: .utility) {
      if let dir = Self.cacheDirectory(scopeDir: scopeDir) {
        try? FileManager.default.removeItem(at: dir)
      }
    }
  }

  /// 统计当前用户本地磁盘图片缓存占用字节数，供设置页「本地缓存清理」展示。
  func diskCacheSizeBytes(for session: NativeSession) async -> Int64 {
    let scopeDir = Self.scopeDirectoryName(for: session)
    return await Task.detached(priority: .utility) {
      guard let dir = Self.cacheDirectory(scopeDir: scopeDir),
        let urls = try? FileManager.default.contentsOfDirectory(
          at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
      else { return 0 }
      var total: Int64 = 0
      for url in urls {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          total += Int64(size)
        }
      }
      return total
    }.value
  }

  /// 定期在后台裁剪超出 250MB 上限的旧磁盘图片缓存。
  private func schedulePruneIfNeeded(scopeDir: String) {
    writesSincePrune += 1
    guard writesSincePrune >= 40 else { return }
    writesSincePrune = 0
    Task.detached(priority: .utility) {
      Self.pruneDiskCache(scopeDir: scopeDir)
    }
  }

  nonisolated private static func cacheDirectory(scopeDir: String) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("MoviePilotImageCache", isDirectory: true)
      .appendingPathComponent(scopeDir, isDirectory: true)
  }

  nonisolated private static func diskFileURL(for key: String, scopeDir: String) -> URL? {
    guard let dir = cacheDirectory(scopeDir: scopeDir) else { return nil }
    let digest = SHA256.hash(data: Data(key.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return dir.appendingPathComponent("\(hex).img")
  }

  nonisolated static func decodeThumbnail(_ data: Data, limit: Int) -> UIImage? {
    let rawImage: UIImage?
    if limit > 0,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: limit,
        ] as CFDictionary)
    {
      rawImage = UIImage(cgImage: cgImage)
    } else {
      rawImage = UIImage(data: data)
    }
    guard let rawImage else { return nil }
    // 在后台线程提前完成位图解压，避免 ProMotion 高刷滚动首帧在主线程同步解码 JPEG/PNG
    return rawImage.preparingForDisplay() ?? rawImage
  }

  nonisolated private static func pruneDiskCache(scopeDir: String) {
    guard let dir = cacheDirectory(scopeDir: scopeDir),
      let urls = try? FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: .skipsHiddenFiles)
    else { return }
    var totalSize: Int64 = 0
    var records: [(url: URL, date: Date, size: Int64)] = []
    for url in urls {
      guard
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
      else { continue }
      let size = Int64(values.fileSize ?? 0)
      totalSize += size
      records.append((url, values.contentModificationDate ?? .distantPast, size))
    }
    guard totalSize > maxDiskBytes else { return }
    records.sort { $0.date < $1.date }
    for item in records {
      try? FileManager.default.removeItem(at: item.url)
      totalSize -= item.size
      if totalSize <= targetDiskBytes { break }
    }
  }
}

/// 会话级页面数据缓存：页面切换与再次进入时首帧直出缓存并静默跳过加载过程，下拉刷新可强制重拉。
@MainActor
final class NativePageDataCache {
  static let shared = NativePageDataCache()

  private struct Entry {
    let value: Any
    let storedAt: Date
  }

  private var entries: [String: Entry] = [:]
  private var activeOwner: String?

  private init() {}

  private func ensureOwner(for session: NativeSession) {
    let owner = "\(session.scope.instanceID.uuidString)|\(session.scope.userID)"
    if activeOwner != owner {
      entries.removeAll()
      activeOwner = owner
    }
  }

  /// 读取当前实例与账号作用域内的缓存快照。
  func get<T>(_ key: String, session: NativeSession) -> T? {
    ensureOwner(for: session)
    return entries[key]?.value as? T
  }

  /// 缓存是否存在且仍在保鲜窗口内（默认 5 分钟）。
  func isFresh(_ key: String, session: NativeSession, maxAge: TimeInterval = 300) -> Bool {
    ensureOwner(for: session)
    guard let entry = entries[key] else { return false }
    return Date().timeIntervalSince(entry.storedAt) < maxAge
  }

  /// 写入当前实例与账号作用域内的缓存快照。
  func set<T>(_ value: T, for key: String, session: NativeSession) {
    ensureOwner(for: session)
    entries[key] = Entry(value: value, storedAt: Date())
  }

  /// 移除指定缓存键。
  func remove(_ key: String, session: NativeSession) {
    ensureOwner(for: session)
    entries.removeValue(forKey: key)
  }

  /// 切换服务器或退出登录时清空全部页面缓存。
  func clearAll() {
    entries.removeAll()
    activeOwner = nil
  }
}

/// 通过代理包装底层 UITabBarController，在重复点击已激活标签或点击右下角动态自定义按钮时返回 `false`，并在 iOS 26 以下 iPhone 彻底隐藏系统灰底 `UITabBar`。
private struct NativeTabBarReselectInterceptor: UIViewControllerRepresentable {
  let hidesSystemTabBar: Bool
  let shouldInterceptReselect: () -> Bool
  let onReselect: () -> Void
  let shouldInterceptTrailingTab: () -> Bool
  let onSelectTrailingTab: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      hidesSystemTabBar: hidesSystemTabBar,
      shouldInterceptReselect: shouldInterceptReselect,
      onReselect: onReselect,
      shouldInterceptTrailingTab: shouldInterceptTrailingTab,
      onSelectTrailingTab: onSelectTrailingTab
    )
  }

  func makeUIViewController(context: Context) -> InterceptorHostController {
    let controller = InterceptorHostController()
    controller.onAttach = { [weak coordinator = context.coordinator] tabBarController in
      coordinator?.attach(to: tabBarController)
    }
    return controller
  }

  func updateUIViewController(_ uiViewController: InterceptorHostController, context: Context) {
    context.coordinator.hidesSystemTabBar = hidesSystemTabBar
    context.coordinator.shouldInterceptReselect = shouldInterceptReselect
    context.coordinator.onReselect = onReselect
    context.coordinator.shouldInterceptTrailingTab = shouldInterceptTrailingTab
    context.coordinator.onSelectTrailingTab = onSelectTrailingTab
    if let tabBarController = uiViewController.findTabBarController() {
      context.coordinator.attach(to: tabBarController)
    }
  }

  final class InterceptorHostController: UIViewController {
    var onAttach: ((UITabBarController) -> Void)?

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      attachIfPossible()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      attachIfPossible()
    }

    override func viewWillLayoutSubviews() {
      super.viewWillLayoutSubviews()
      attachIfPossible()
    }

    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      attachIfPossible()
    }

    func findTabBarController() -> UITabBarController? {
      if let direct = tabBarController { return direct }
      var cursor: UIViewController? = parent
      while let current = cursor {
        if let tab = current as? UITabBarController { return tab }
        if let tab = current.tabBarController { return tab }
        cursor = current.parent
      }
      return nil
    }

    private func attachIfPossible() {
      if let tabBarController = findTabBarController() {
        onAttach?(tabBarController)
      }
    }
  }

  @MainActor
  final class Coordinator: NSObject, UITabBarControllerDelegate {
    var hidesSystemTabBar: Bool
    var shouldInterceptReselect: () -> Bool
    var onReselect: () -> Void
    var shouldInterceptTrailingTab: () -> Bool
    var onSelectTrailingTab: () -> Void
    private weak var observedTabBarController: UITabBarController?
    private weak var originalDelegate: (any UITabBarControllerDelegate)?
    private var hiddenObservation: NSKeyValueObservation?

    init(
      hidesSystemTabBar: Bool,
      shouldInterceptReselect: @escaping () -> Bool,
      onReselect: @escaping () -> Void,
      shouldInterceptTrailingTab: @escaping () -> Bool,
      onSelectTrailingTab: @escaping () -> Void
    ) {
      self.hidesSystemTabBar = hidesSystemTabBar
      self.shouldInterceptReselect = shouldInterceptReselect
      self.onReselect = onReselect
      self.shouldInterceptTrailingTab = shouldInterceptTrailingTab
      self.onSelectTrailingTab = onSelectTrailingTab
    }

    private static func enforceHiddenTabBar(_ tabBar: UITabBar) {
      if !tabBar.isHidden { tabBar.isHidden = true }
      if tabBar.alpha != 0 { tabBar.alpha = 0 }
      if tabBar.isUserInteractionEnabled { tabBar.isUserInteractionEnabled = false }
      if !tabBar.accessibilityElementsHidden { tabBar.accessibilityElementsHidden = true }
    }

    func attach(to tabBarController: UITabBarController) {
      if hidesSystemTabBar {
        Self.enforceHiddenTabBar(tabBarController.tabBar)
        if observedTabBarController !== tabBarController || hiddenObservation == nil {
          hiddenObservation = tabBarController.tabBar.observe(\.isHidden, options: [.new]) {
            tabBar, _ in
            MainActor.assumeIsolated {
              if !tabBar.isHidden {
                Self.enforceHiddenTabBar(tabBar)
              }
            }
          }
        }
      } else {
        hiddenObservation = nil
      }

      if let existing = tabBarController.delegate as? Coordinator {
        // 复用已挂载的代理实例并就地刷新回调，绝不在多标签切换期间反复改写 delegate，彻底杜绝 iPad sidebarAdaptable 下的重布局乒乓死循环。
        existing.hidesSystemTabBar = hidesSystemTabBar
        existing.shouldInterceptReselect = shouldInterceptReselect
        existing.onReselect = onReselect
        existing.shouldInterceptTrailingTab = shouldInterceptTrailingTab
        existing.onSelectTrailingTab = onSelectTrailingTab
        observedTabBarController = tabBarController
        return
      }
      if let existing = tabBarController.delegate {
        originalDelegate = existing
      }
      observedTabBarController = tabBarController
      tabBarController.delegate = self
    }

    func tabBarController(
      _ tabBarController: UITabBarController,
      shouldSelect viewController: UIViewController
    ) -> Bool {
      if viewController === tabBarController.selectedViewController,
        shouldInterceptReselect()
      {
        onReselect()
        return false
      }
      if shouldInterceptTrailingTab() {
        let isSearchTrailingItem =
          viewController.tabBarItem.accessibilityIdentifier == "native-v2-search-tab-item"
          || (!NativeDeviceLayout.isIPad
            && viewController === tabBarController.viewControllers?.last)
        if isSearchTrailingItem {
          onSelectTrailingTab()
          return false
        }
      }
      return originalDelegate?.tabBarController?(tabBarController, shouldSelect: viewController)
        ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
      if super.responds(to: aSelector) { return true }
      return originalDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
      if let originalDelegate, originalDelegate.responds(to: aSelector) {
        return originalDelegate
      }
      return super.forwardingTarget(for: aSelector)
    }
  }
}

/// 发现页豆瓣热门音乐推荐解码投影。
private struct NativeDiscoverMusicItem: Decodable, Sendable {
  let mediaSource: String?
  let mediaID: String?
  let albumID: String?
  let releaseID: String?
  let title: String?
  let artist: String?
  let artists: [String]?
  let artistIDs: [String]?
  let year: NativeMediaServerScalar?
  let coverURL: String?
  let posterPath: String?
  let rating: Double?
  let voteAverage: Double?

  func toMusicCardItem() -> NativeMusicCardItem? {
    guard let title, !title.isEmpty else { return nil }
    let source = mediaSource?.isEmpty == false ? mediaSource! : "doubanmusic"
    let primaryID = mediaID?.isEmpty == false ? mediaID! : (albumID ?? "")
    let lookupID = albumID?.isEmpty == false ? albumID! : primaryID
    guard !primaryID.isEmpty else { return nil }
    let score = (rating ?? 0) > 0 ? rating : voteAverage
    return NativeMusicCardItem(
      id: "\(source)|\(primaryID)",
      mediaSource: source,
      mediaID: primaryID,
      albumLookupID: lookupID,
      releaseID: releaseID,
      title: title,
      artist: artist ?? artists?.first,
      artistID: artistIDs?.first,
      yearText: year?.value,
      coverReference: coverURL ?? posterPath,
      ratingText: score.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil }
    )
  }

  private enum CodingKeys: String, CodingKey {
    case title, artist, artists, year, rating
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case albumID = "album_id"
    case releaseID = "musicbrainz_release_id"
    case artistIDs = "artist_ids"
    case coverURL = "cover_url"
    case posterPath = "poster_path"
    case voteAverage = "vote_average"
  }
}

/// 发现接口只反序列化详情首屏需要的字段，不将完整外部 JSON 塞进 SwiftUI。
private struct NativeDiscoverAPIItem: Decodable, Sendable {
  let mediaSource: String?
  let mediaID: String?
  let tmdbID: Int?
  let imdbID: String?
  let doubanID: String?
  let bangumiID: Int?
  let anilistID: Int?
  let type: String?
  let title: String?
  let year: String?
  let releaseDate: String?
  let posterPath: String?
  let backdropPath: String?
  let logoPath: String?
  let logoLanguage: String?
  let originalLanguage: String?
  let overview: String?
  let voteAverage: Double?
  let genres: [MediaNamedTag]?

  /// 提取可读风格名称用于主视觉与趋势横卡副标。
  var genreNames: [String] {
    (genres ?? []).compactMap(\.name).filter { !$0.isEmpty }
  }

  /// 映射 MoviePilot MediaInfo 的稳定后端字段。
  private enum CodingKeys: String, CodingKey {
    case type, title, year, overview, genres
    case mediaSource = "media_source"
    case mediaID = "media_id"
    case tmdbID = "tmdb_id"
    case imdbID = "imdb_id"
    case doubanID = "douban_id"
    case bangumiID = "bangumi_id"
    case anilistID = "anilist_id"
    case releaseDate = "release_date"
    case posterPath = "poster_path"
    case backdropPath = "backdrop_path"
    case logoPath = "logo_path"
    case logoLanguage = "logo_language"
    case originalLanguage = "original_language"
    case voteAverage = "vote_average"
  }
}

/// 媒体服务器标量兼容字符串与整数 ID，避免不同服务器类型解码失败。
private struct NativeMediaServerScalar: Decodable, Sendable {
  let value: String

  /// 仅接受字符串或整数标量，拒绝嵌套结构。
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) {
      value = text
    } else {
      value = try String(container.decode(Int64.self))
    }
  }
}

/// 媒体服务器名称与类型摘要。
private struct NativeMediaServerClient: Decodable, Sendable {
  let name: String?
  let type: String?
}

/// 媒体服务器继续观看与最新入库条目的精简投影。
private struct NativeMediaServerPlayItem: Decodable, Sendable {
  let id: NativeMediaServerScalar?
  let itemID: NativeMediaServerScalar?
  let server: String?
  let type: String?
  let title: String?
  let subtitle: String?
  let year: NativeMediaServerScalar?
  let image: String?
  let percent: Double?

  /// 映射 MediaServerPlayItem 的稳定字段。
  private enum CodingKeys: String, CodingKey {
    case id, server, type, title, subtitle, year, image, percent
    case itemID = "item_id"
  }
}

/// 媒体服务器媒体库摘要投影。
private struct NativeMediaServerLibrary: Decodable, Sendable {
  let id: NativeMediaServerScalar?
  let itemID: NativeMediaServerScalar?
  let server: String?
  let name: String?
  let type: String?
  let itemCount: Int?
  let image: String?
  let imageList: [String]?
  let link: String?
  let serverType: String?
  let serverID: NativeMediaServerScalar?

  /// 映射 MediaServerLibrary 的稳定字段。
  private enum CodingKeys: String, CodingKey {
    case id, server, name, type, image, link
    case itemID = "item_id"
    case itemCount = "item_count"
    case imageList = "image_list"
    case serverType = "server_type"
    case serverID = "server_id"
  }
}

/// 发现页媒体库深度链接跳转器（对标 Web `appDeepLink.ts`：优先拉起 Emby / Jellyfin / Plex / 飞牛影视等 iOS 客户端 App，未安装时自动回退网页链接）。
@MainActor
private enum NativeMediaServerAppLauncher {
  static func openLibrary(_ provider: NativeDiscoverProvider) {
    let playURLString = normalizedPlayURL(for: provider)
    let detectedType = detectServerType(serverType: provider.serverType, playURL: playURLString)
    let deepLinkString = buildDeepLink(
      serverType: detectedType, playURL: playURLString, provider: provider)

    if let deepLinkString, let deepLinkURL = URL(string: deepLinkString) {
      UIApplication.shared.open(deepLinkURL, options: [:]) { opened in
        if !opened, let playURLString, let webURL = URL(string: playURLString) {
          UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
        }
      }
      return
    }
    if let playURLString, let webURL = URL(string: playURLString) {
      UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
    }
  }

  private static func validValue(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    let lower = trimmed.lowercased()
    if ["none", "null", "undefined"].contains(lower) { return nil }
    return trimmed
  }

  private static func detectServerType(serverType: String?, playURL: String?) -> String? {
    if let raw = validValue(serverType)?.lowercased() {
      if ["plex", "jellyfin", "emby", "zspace", "trimemedia"].contains(raw) {
        return raw
      }
    }
    guard let lower = playURL?.lowercased() else { return nil }
    if lower.contains("plex") || lower.contains("plex.tv") { return "plex" }
    if lower.contains("jellyfin") { return "jellyfin" }
    if lower.contains("emby") { return "emby" }
    if lower.contains("zspace") { return "zspace" }
    if lower.contains("trimemedia") { return "trimemedia" }
    return nil
  }

  private static func normalizedPlayURL(for provider: NativeDiscoverProvider) -> String? {
    guard let rawLink = validValue(provider.link) else { return nil }
    let lowerType = validValue(provider.serverType)?.lowercased()
    guard lowerType == "emby" || lowerType == "zspace" else { return rawLink }
    guard let hashIdx = rawLink.firstIndex(of: "#") else { return rawLink }
    let basePart = String(rawLink[..<hashIdx])
    let hashPart = String(rawLink[rawLink.index(after: hashIdx)...])
    guard let qIdx = hashPart.firstIndex(of: "?") else { return rawLink }
    let hashPath = String(hashPart[..<qIdx])
    let queryString = String(hashPart[hashPart.index(after: qIdx)...])
    var components = URLComponents()
    components.percentEncodedQuery = queryString
    var items = components.queryItems ?? []

    func setParam(_ name: String, _ value: String) {
      if let i = items.firstIndex(where: { $0.name == name }) {
        items[i].value = value
      } else {
        items.append(URLQueryItem(name: name, value: value))
      }
    }

    if let itemID = validValue(provider.itemID) {
      if hashPath.contains("/item") || items.contains(where: { $0.name == "id" }) {
        setParam("id", itemID)
      }
      if hashPath.contains("/videos") || items.contains(where: { $0.name == "parentId" }) {
        setParam("parentId", itemID)
      }
    }
    if let serverID = validValue(provider.serverID) {
      setParam("serverId", serverID)
    } else {
      items.removeAll { $0.name == "serverId" && validValue($0.value) == nil }
    }
    components.queryItems = items
    let updatedQuery = components.percentEncodedQuery ?? queryString
    return "\(basePart)#\(hashPath)?\(updatedQuery)"
  }

  private static func buildDeepLink(
    serverType: String?, playURL: String?, provider: NativeDiscoverProvider
  ) -> String? {
    guard let serverType else { return nil }
    switch serverType {
    case "emby", "zspace":
      return buildEmbyDeepLink(playURL: playURL, provider: provider)
    case "jellyfin":
      return buildJellyfinDeepLink(playURL: playURL, provider: provider)
    case "plex":
      return buildPlexDeepLink(playURL: playURL)
    case "trimemedia":
      return buildTrimemediaDeepLink(playURL: playURL, provider: provider)
    default:
      return nil
    }
  }

  private static func hostPort(from playURL: String?) -> String? {
    guard let playURL, let url = URL(string: playURL), let host = url.host else { return nil }
    if let port = url.port { return "\(host):\(port)" }
    return host
  }

  private static func firstCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    guard
      let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
      match.numberOfRanges >= 2
    else { return nil }
    let r = match.range(at: 1)
    guard r.location != NSNotFound else { return nil }
    return validValue(ns.substring(with: r))
  }

  /// iOS Emby 官方深度链接格式：`emby://items?serverId={SERVER_ID}&itemId={ITEM_ID}`
  private static func buildEmbyDeepLink(
    playURL: String?, provider: NativeDiscoverProvider
  ) -> String {
    var mediaID = validValue(provider.itemID)
    var serverID = validValue(provider.serverID)
    if let playURL {
      if mediaID == nil {
        mediaID =
          firstCapture(#"[?&]parentId=([^&#]+)"#, in: playURL)
          ?? firstCapture(#"[?&]id=([^&#]+)"#, in: playURL)
          ?? firstCapture(#"/items?/([^/?#]+)"#, in: playURL)
      }
      if serverID == nil {
        serverID = firstCapture(#"[?&]serverId=([^&#]+)"#, in: playURL)
      }
    }
    if let mediaID {
      let encodedMedia =
        mediaID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mediaID
      if let serverID {
        let encodedServer =
          serverID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? serverID
        return "emby://items?serverId=\(encodedServer)&itemId=\(encodedMedia)"
      }
      return "emby://items?itemId=\(encodedMedia)"
    }
    if let host = hostPort(from: playURL) { return "emby://\(host)" }
    return "emby://"
  }

  /// Jellyfin 深度链接格式：`jellyfin://{host}/library/{libraryId}` 或 `jellyfin://{host}/item/{mediaId}`
  private static func buildJellyfinDeepLink(
    playURL: String?, provider: NativeDiscoverProvider
  ) -> String {
    let host = hostPort(from: playURL) ?? ""
    var libraryID = validValue(provider.itemID)
    var mediaID: String?
    var serverID = validValue(provider.serverID)
    if let playURL {
      if let libMatch = firstCapture(#"[?&]topParentId=([^&#]+)"#, in: playURL) {
        libraryID = libMatch
      }
      if let detailID = firstCapture(#"/details\?id=([^&#]+)"#, in: playURL) {
        mediaID = detailID
      }
      if serverID == nil {
        serverID = firstCapture(#"[?&]serverId=([^&#]+)"#, in: playURL)
      }
    }
    if let mediaID, !host.isEmpty {
      var link = "jellyfin://\(host)/item/\(mediaID)"
      if let serverID { link += "?serverId=\(serverID)" }
      return link
    }
    if let libraryID, !host.isEmpty {
      return "jellyfin://\(host)/library/\(libraryID)"
    }
    return host.isEmpty ? "jellyfin://" : "jellyfin://\(host)"
  }

  /// Plex 深度链接格式：`plex://library/sections/{sectionId}/all` 或 `plex://play/?metadataKey=...`
  private static func buildPlexDeepLink(playURL: String?) -> String {
    guard let playURL else { return "plex://" }
    let token = firstCapture(#"X-Plex-Token=([^&#]+)"#, in: playURL)
    if let sectionMatch = firstCapture(#"source=[^&#]*section%2F(\d+)"#, in: playURL)
      ?? firstCapture(#"source=[^&#]*section/(\d+)"#, in: playURL)
      ?? firstCapture(#"source=(\d+)"#, in: playURL)
    {
      var link = "plex://library/sections/\(sectionMatch)/all"
      if let token { link += "?X-Plex-Token=\(token)" }
      return link
    }
    if let serverID = firstCapture(#"/server/([^/]+)/details"#, in: playURL),
      let keyVal = firstCapture(#"[?&]key=([^&#]+)"#, in: playURL)
    {
      let mediaID = firstCapture(#"/library/metadata/(\d+)"#, in: keyVal) ?? keyVal
      var link = "plex://play/?metadataKey=/library/metadata/\(mediaID)&server=\(serverID)"
      if let token { link += "&X-Plex-Token=\(token)" }
      return link
    }
    var fallback = "plex://library/sections"
    if let token { fallback += "?X-Plex-Token=\(token)" }
    return fallback
  }

  /// 飞牛影视深度链接格式：`trimemedia://{host}/item/{mediaId}` 或 `trimemedia://{host}`
  private static func buildTrimemediaDeepLink(
    playURL: String?, provider: NativeDiscoverProvider
  ) -> String {
    let host = hostPort(from: playURL) ?? ""
    let mediaID =
      playURL.flatMap {
        firstCapture(#"/item/([^/?#]+)"#, in: $0) ?? firstCapture(#"[?&]id=([^&#]+)"#, in: $0)
      } ?? validValue(provider.itemID)
    if let mediaID, !host.isEmpty {
      return "trimemedia://\(host)/item/\(mediaID)"
    }
    return host.isEmpty ? "trimemedia://" : "trimemedia://\(host)"
  }
}

// MARK: - 媒体库入库状态批量查询与绿色对勾角标（对齐 Web `POST /api/v1/media/status` + `ExistIcon.vue`）

/// 本地媒体库入库状态批量查询与缓存中心：将同一屏可见海报卡片在 30ms 窗口内自动合并为最多 50 项的单次 `POST /api/v1/media/status` 请求。
@MainActor
final class NativeMediaLibraryStatusStore {
  static let shared = NativeMediaLibraryStatusStore()

  private struct QueryPayload: Encodable, Sendable {
    let mediaSource: String?
    let mediaID: String?
    let title: String?
    let year: String?
    let mtype: String?

    private enum CodingKeys: String, CodingKey {
      case title, year, mtype
      case mediaSource = "media_source"
      case mediaID = "media_id"
    }
  }

  private struct StatusResult: Decodable, Sendable {
    let itemID: String?
    private enum CodingKeys: String, CodingKey { case itemID = "item_id" }
  }

  private struct CacheEntry {
    let exists: Bool
    let expiresAt: Date
  }

  private struct PendingItem {
    let key: String
    let payload: QueryPayload
    let continuation: CheckedContinuation<Bool, Never>
  }

  private var cache: [String: CacheEntry] = [:]
  private var pendingByScope: [String: (session: NativeSession, items: [PendingItem])] = [:]
  private var flushTasks: [String: Task<Void, Never>] = [:]

  private init() {}

  /// 同步读取未过期的本地入库状态缓存（避免卡片滑动复用闪烁）。
  func cachedExists(
    session: NativeSession,
    source: String?,
    mediaID: String?,
    title: String?,
    year: String?,
    type: String?
  ) -> Bool? {
    let normalized = Self.normalizeQuery(
      source: source, mediaID: mediaID, title: title, year: year, type: type)
    guard let key = Self.cacheKey(session: session, payload: normalized) else { return false }
    guard let entry = cache[key], entry.expiresAt > Date() else { return nil }
    return entry.exists
  }

  /// 查询单张媒体卡片是否已存在于本地媒体库（自动合并同帧卡片并按会话缓存 3 分钟）。
  func checkExists(
    session: NativeSession,
    source: String?,
    mediaID: String?,
    title: String?,
    year: String?,
    type: String?
  ) async -> Bool {
    let rawType = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if rawType == "音乐" || rawType.lowercased() == "music" { return false }
    let payload = Self.normalizeQuery(
      source: source, mediaID: mediaID, title: title, year: year, type: type)
    guard let key = Self.cacheKey(session: session, payload: payload) else { return false }
    if let entry = cache[key], entry.expiresAt > Date() {
      return entry.exists
    }
    let scopeKey = "\(session.scope.instanceID.uuidString)|\(session.scope.userID)"
    return await withCheckedContinuation { continuation in
      var bucket = pendingByScope[scopeKey] ?? (session: session, items: [])
      bucket.items.append(PendingItem(key: key, payload: payload, continuation: continuation))
      pendingByScope[scopeKey] = bucket
      if flushTasks[scopeKey] == nil {
        flushTasks[scopeKey] = Task { @MainActor [weak self] in
          try? await Task.sleep(for: .milliseconds(35))
          await self?.flush(scopeKey: scopeKey)
        }
      }
    }
  }

  /// 清空入库状态缓存（切换实例、退出登录或刷新数据后调用）。
  func clearAll() {
    cache.removeAll()
  }

  private func flush(scopeKey: String) async {
    flushTasks.removeValue(forKey: scopeKey)
    while let bucket = pendingByScope.removeValue(forKey: scopeKey), !bucket.items.isEmpty {
      var groupedByKey:
        [String: (payload: QueryPayload, continuations: [CheckedContinuation<Bool, Never>])] = [:]
      var orderedKeys: [String] = []
      for item in bucket.items {
        if var existing = groupedByKey[item.key] {
          existing.continuations.append(item.continuation)
          groupedByKey[item.key] = existing
        } else {
          orderedKeys.append(item.key)
          groupedByKey[item.key] = (item.payload, [item.continuation])
        }
      }

      var cursor = 0
      while cursor < orderedKeys.count {
        let end = min(cursor + 50, orderedKeys.count)
        let sliceKeys = Array(orderedKeys[cursor..<end])
        cursor = end
        let payloads = sliceKeys.compactMap { groupedByKey[$0]?.payload }
        var resolved: [String: Bool] = [:]
        if let body = try? JSONEncoder().encode(payloads),
          let endpoint = try? APIEndpoint(path: ["media", "status"], method: .post, body: body)
        {
          if let results = try? await bucket.session.request(endpoint, as: [StatusResult].self)
            .value,
            results.count == sliceKeys.count
          {
            let expires = Date().addingTimeInterval(180)
            for (idx, key) in sliceKeys.enumerated() {
              let exists = !(results[idx].itemID ?? "").isEmpty
              resolved[key] = exists
              cache[key] = CacheEntry(exists: exists, expiresAt: expires)
            }
          }
        }
        for key in sliceKeys {
          let exists = resolved[key] ?? false
          for cont in groupedByKey[key]?.continuations ?? [] {
            cont.resume(returning: exists)
          }
        }
      }
    }
  }

  private static func normalizeQuery(
    source: String?, mediaID: String?, title: String?, year: String?, type: String?
  ) -> QueryPayload {
    let trimmedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let trimmedID = mediaID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasPair = !trimmedSource.isEmpty && !trimmedID.isEmpty && trimmedID != "0"
    let normalizedType: String?
    switch (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "电影", "movie": normalizedType = "电影"
    case "电视剧", "tv": normalizedType = "电视剧"
    default: normalizedType = nil
    }
    let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanYear = year?.trimmingCharacters(in: .whitespacesAndNewlines)
    return QueryPayload(
      mediaSource: hasPair ? trimmedSource : nil,
      mediaID: hasPair ? trimmedID : nil,
      title: cleanTitle?.isEmpty == false ? cleanTitle : nil,
      year: cleanYear?.isEmpty == false ? cleanYear : nil,
      mtype: normalizedType
    )
  }

  private static func cacheKey(session: NativeSession, payload: QueryPayload) -> String? {
    if payload.mediaSource == nil && payload.title == nil { return nil }
    return [
      session.scope.instanceID.uuidString,
      String(session.scope.userID),
      payload.mediaSource ?? "",
      payload.mediaID ?? "",
      payload.title ?? "",
      payload.year ?? "",
      payload.mtype ?? "",
    ].joined(separator: "|")
  }
}

/// 媒体库已存在绿色对勾徽标（与 Web `ExistIcon.vue` 视觉语义一致）。
@MainActor
struct NativeMediaExistsBadge: View {
  var size: CGFloat = 20

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.92))
        .overlay {
          Circle().strokeBorder(Color(red: 0.52, green: 0.94, blue: 0.67), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
      Image(systemName: "checkmark")
        .font(.system(size: size * 0.52, weight: .bold))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
    .accessibilityLabel("媒体库已存在")
  }
}

/// 海报卡片右上角媒体库已存在徽标修饰器，按需批量查询入库状态。
private struct NativeMediaExistsOverlayModifier: ViewModifier {
  let session: NativeSession
  let source: String?
  let mediaID: String?
  let title: String?
  let year: String?
  let type: String?
  let enabled: Bool
  let badgeSize: CGFloat
  let inset: CGFloat

  @State private var exists = false

  private var taskKey: String {
    "\(enabled)|\(source ?? "")|\(mediaID ?? "")|\(title ?? "")|\(year ?? "")|\(type ?? "")"
  }

  func body(content: Content) -> some View {
    let displayExists =
      enabled
      && (exists
        || (NativeMediaLibraryStatusStore.shared.cachedExists(
          session: session, source: source, mediaID: mediaID, title: title, year: year, type: type)
          == true))
    return
      content
      .overlay(alignment: .topTrailing) {
        if displayExists {
          NativeMediaExistsBadge(size: badgeSize)
            .padding(inset)
        }
      }
      .task(id: taskKey) {
        guard enabled else {
          exists = false
          return
        }
        if let cached = NativeMediaLibraryStatusStore.shared.cachedExists(
          session: session, source: source, mediaID: mediaID, title: title, year: year, type: type)
        {
          exists = cached
          return
        }
        let result = await NativeMediaLibraryStatusStore.shared.checkExists(
          session: session, source: source, mediaID: mediaID, title: title, year: year, type: type)
        if !Task.isCancelled {
          exists = result
        }
      }
  }
}

extension View {
  func nativeMediaExistsOverlay(
    session: NativeSession,
    source: String?,
    mediaID: String?,
    title: String?,
    year: String?,
    type: String?,
    enabled: Bool = true,
    badgeSize: CGFloat = 20,
    inset: CGFloat = 6
  ) -> some View {
    modifier(
      NativeMediaExistsOverlayModifier(
        session: session,
        source: source,
        mediaID: mediaID,
        title: title,
        year: year,
        type: type,
        enabled: enabled,
        badgeSize: badgeSize,
        inset: inset
      ))
  }
}

/// iOS 26 以下 iPhone 隐藏系统底栏修饰器。
private struct NativeLegacyHideSystemTabBarModifier: ViewModifier {
  let isHidden: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if isHidden {
      content.toolbar(.hidden, for: .tabBar)
    } else {
      content
    }
  }
}

/// iOS 26 以下 iPhone 为自定义悬浮胶囊底栏预留页面滚动安全高度，保证滚到底部时内容不被遮挡且滑动时透过毛玻璃。
private struct NativeLegacyBottomClearanceModifier: ViewModifier {
  let enabled: Bool
  let height: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if enabled {
      content.safeAreaInset(edge: .bottom, spacing: 0) {
        Color.clear
          .frame(height: height)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    } else {
      content
    }
  }
}

/// 自定义 4+1 悬浮胶囊底栏的单个主标签描述。
private struct NativeLegacyFloatingTabItem: Identifiable {
  let id: String
  let title: String
  let symbol: String
  let activeSymbol: String
  /// 为 true 时按素材目录模板图名称渲染（如 DiscoverCards），否则按 SF Symbols 名称渲染。
  var isAssetImage: Bool = false
  let isAvatar: Bool
  let accessibilityID: String
  let isSelected: Bool
  let action: () -> Void
}

/// iOS 26 以下 iPhone 专属 4+1 悬浮毛玻璃胶囊导航栏：左侧 4 项通透毛玻璃胶囊 + 弹性滑动高亮底座，右侧独立圆形搜索/上下文动作按钮。
@MainActor
private struct NativeLegacyFloatingTabBar: View {
  let items: [NativeLegacyFloatingTabItem]
  let userTabAvatar: UIImage?
  let showsTrailingButton: Bool
  let trailingTitle: String
  let trailingSymbol: String
  let isTrailingActive: Bool
  let isCompactLandscape: Bool
  let onTrailingAction: () -> Void

  @ObservedObject private var appearance = NativeAppearanceStore.shared
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Namespace private var activePillNamespace

  var body: some View {
    let isLight = colorScheme == .light
    let barHeight: CGFloat = isCompactLandscape ? 48 : 58
    let accent = appearance.accentColor
    HStack(spacing: isCompactLandscape ? 10 : 12) {
      HStack(spacing: 2) {
        ForEach(items) { item in
          Button(action: item.action) {
            VStack(spacing: isCompactLandscape ? 1.5 : 3) {
              Group {
                if item.isAvatar, let avatar = userTabAvatar {
                  Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
                    .frame(
                      width: isCompactLandscape ? 19 : 22,
                      height: isCompactLandscape ? 19 : 22
                    )
                    .clipShape(Circle())
                    .overlay {
                      Circle()
                        .strokeBorder(
                          item.isSelected ? accent : Color.primary.opacity(0.22),
                          lineWidth: item.isSelected ? 1.5 : 0.7
                        )
                    }
                } else if item.isAssetImage {
                  Image(item.isSelected ? item.activeSymbol : item.symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(
                      width: isCompactLandscape ? 18 : 20,
                      height: isCompactLandscape ? 18 : 20
                    )
                    .frame(height: isCompactLandscape ? 19 : 22)
                } else {
                  Image(systemName: item.isSelected ? item.activeSymbol : item.symbol)
                    .font(
                      .system(
                        size: isCompactLandscape ? 15.5 : 18,
                        weight: item.isSelected ? .semibold : .medium
                      )
                    )
                    .frame(height: isCompactLandscape ? 19 : 22)
                }
              }
              Text(item.title)
                .font(.system(size: 10, weight: item.isSelected ? .semibold : .medium))
                .lineLimit(1)
            }
            .foregroundStyle(
              item.isSelected
                ? accent
                : Color.primary.opacity(isLight ? 0.72 : 0.78)
            )
            .frame(maxWidth: .infinity)
            .frame(height: barHeight - 8)
            .background {
              if item.isSelected {
                Capsule()
                  .fill(accent.opacity(isLight ? 0.15 : 0.22))
                  .overlay {
                    Capsule()
                      .strokeBorder(accent.opacity(isLight ? 0.28 : 0.36), lineWidth: 0.6)
                  }
                  .matchedGeometryEffect(id: "legacy-floating-tab-pill", in: activePillNamespace)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(item.title)
          .accessibilityAddTraits(item.isSelected ? .isSelected : [])
          .accessibilityIdentifier(item.accessibilityID)
        }
      }
      .padding(.horizontal, 5)
      .frame(maxWidth: .infinity)
      .frame(height: barHeight)
      .background {
        capsuleGlassSurface(isLight: isLight, accent: accent)
      }

      if showsTrailingButton {
        Button(action: onTrailingAction) {
          Image(systemName: trailingSymbol)
            .font(.system(size: isCompactLandscape ? 17 : 19, weight: .semibold))
            .foregroundStyle(
              isTrailingActive
                ? accent
                : Color.primary.opacity(isLight ? 0.84 : 0.88)
            )
            .frame(width: barHeight, height: barHeight)
            .background {
              circleGlassSurface(isLight: isLight, accent: accent, active: isTrailingActive)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trailingTitle)
        .accessibilityAddTraits(isTrailingActive ? .isSelected : [])
        .accessibilityIdentifier("native-v2-search-tab-item")
      }
    }
    .frame(maxWidth: 460)
    .padding(.horizontal, isCompactLandscape ? 20 : 18)
    .padding(.bottom, isCompactLandscape ? 4 : 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }

  @ViewBuilder
  private func capsuleGlassSurface(isLight: Bool, accent: Color) -> some View {
    if reduceTransparency {
      Capsule()
        .fill(isLight ? Color.white.opacity(0.96) : CinematicStyle.solidSurface)
        .overlay {
          Capsule()
            .strokeBorder(
              isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(isLight ? 0.10 : 0.28), radius: 12, y: 6)
    } else {
      Capsule()
        .fill(.ultraThinMaterial)
        .overlay {
          Capsule()
            .fill(
              LinearGradient(
                colors: [
                  Color.white.opacity(isLight ? 0.48 : 0.14),
                  Color.white.opacity(isLight ? 0.14 : 0.03),
                  .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
        }
        .overlay {
          Capsule()
            .strokeBorder(
              LinearGradient(
                colors: [
                  Color.white.opacity(isLight ? 0.78 : 0.32),
                  Color.white.opacity(isLight ? 0.22 : 0.08),
                  accent.opacity(isLight ? 0.16 : 0.20),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 0.8
            )
        }
        .shadow(color: .black.opacity(isLight ? 0.12 : 0.34), radius: 16, y: 8)
    }
  }

  @ViewBuilder
  private func circleGlassSurface(isLight: Bool, accent: Color, active: Bool) -> some View {
    if reduceTransparency {
      Circle()
        .fill(isLight ? Color.white.opacity(0.96) : CinematicStyle.solidSurface)
        .overlay {
          Circle()
            .strokeBorder(
              active
                ? accent.opacity(0.45)
                : (isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.18)),
              lineWidth: 0.8
            )
        }
        .shadow(color: .black.opacity(isLight ? 0.10 : 0.28), radius: 12, y: 6)
    } else {
      Circle()
        .fill(.ultraThinMaterial)
        .overlay {
          if active {
            Circle().fill(accent.opacity(isLight ? 0.15 : 0.24))
          }
        }
        .overlay {
          Circle()
            .fill(
              LinearGradient(
                colors: [
                  Color.white.opacity(isLight ? 0.48 : 0.15),
                  Color.white.opacity(isLight ? 0.12 : 0.03),
                  .clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
        }
        .overlay {
          Circle()
            .strokeBorder(
              LinearGradient(
                colors: [
                  active ? accent.opacity(0.55) : Color.white.opacity(isLight ? 0.78 : 0.34),
                  Color.white.opacity(isLight ? 0.22 : 0.08),
                  accent.opacity(active ? 0.32 : 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 0.8
            )
        }
        .shadow(color: .black.opacity(isLight ? 0.12 : 0.34), radius: 16, y: 8)
    }
  }
}

/// 与 `LaunchScreen.storyboard` 像素级一致的启动屏覆层：深色主题下采用纯黑 `#000000` 背景，冷启动自动连接与发现首屏加载完成前持续展示居中 Logo，加载完成后柔和淡出。
@MainActor
struct NativeLaunchSplashView: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      (colorScheme == .dark ? Color.black : Color("LaunchBackground"))
        .ignoresSafeArea()
      Image("LaunchMark")
        .resizable()
        .scaledToFit()
        .frame(width: 128, height: 128)
        .accessibilityHidden(true)
    }
    .ignoresSafeArea()
    .accessibilityIdentifier("native-launch-splash")
  }
}
