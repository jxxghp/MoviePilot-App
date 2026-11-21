import CryptoKit
import ImageIO
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 已认证 MoviePilot 的原生主导航：4+1 底部架构（发现 / 探索 / 我的 / 设置 + 动态上下文或全局搜索按钮），二次点击任意主标签弹出其余全部功能菜单。
@MainActor
struct NativeV2MainShell<PluginDestination: View>: View {
  /// 4+1 底栏标签定义：发现、探索、我的（仪表盘）、设置 + 右侧独立动态按钮/全局搜索。
  private enum Page: Hashable {
    case discover
    case explore
    case mine
    case settings
    case search
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
  @Environment(\.colorScheme) private var colorScheme
  @State private var selectedTab: Page = .discover
  @State private var discovery = NativeDiscoverContent(
    featured: nil, rails: [], continueWatching: [], providers: [], categories: [], isLoading: true)
  @State private var discoveryGeneration = UUID()
  @State private var discoveryAttempt = 0
  @State private var mediaIdentities: [String: NativeMediaIdentity] = [:]
  @State private var discoverPath: [NativeMediaDestination] = []
  @State private var explorePath: [NativeWorkspaceDestination] = []
  @State private var minePath: [NativeWorkspaceDestination] = []
  @State private var settingsPath: [NativeWorkspaceDestination] = []
  @State private var searchPath: [NativeMediaIdentity] = []
  @State private var showsOverflowMenu = false
  @State private var showsAgentSheet = false
  @State private var showsShortcutsSheet = false
  @State private var userTabAvatar: UIImage?
  @AppStorage("nativeV2.showFloatingAssistant") private var showFloatingAssistant = true
  @State private var discoverModules = NativeDiscoverModuleItem.defaults
  @State private var showsModuleSheet = false
  @State private var pendingModuleRefetch = false
  @State private var latestServerName: String?
  @State private var railNextPage: [String: Int] = [:]
  @State private var loadingRailIDs: Set<String> = []
  @State private var lastOverflowToggleAt: Date = .distantPast
  @State private var lastTrailingActionAt: Date = .distantPast
  @State private var hasLoadedDiscoveryOnce = false

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

  /// 主导航交给系统 TabView 和每页独立 NavigationStack，并注入跨栈动态主按钮中心、浮动智能助手形象与全局溢出菜单。
  var body: some View {
    ZStack {
      page
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      if showFloatingAssistant && !showsOverflowMenu && !showsAgentSheet && !showsShortcutsSheet {
        NativeAgentFloatingMascot(
          onOpen: { showsAgentSheet = true },
          onHide: { showFloatingAssistant = false }
        )
      }
      if showsOverflowMenu {
        overflowMenuBackdrop
          .transition(.opacity)
          .zIndex(49)
      }
      if showsOverflowMenu {
        overflowMenuCard
          .transition(overflowMenuTransition)
          .zIndex(50)
      }
      if let banner = routeHub.bannerMessage {
        systemBannerOverlay(banner)
      }
    }
    .environmentObject(dynamicActionCenter)
    .onAppear { consumeSystemRouteIfNeeded() }
    .onChange(of: routeHub.pendingTarget) { _ in consumeSystemRouteIfNeeded() }
    .task(id: "\(snapshot.scope)|\(snapshot.user.avatar)") {
      userTabAvatar = await NativeUserAvatarRenderer.loadTabAvatar(
        session: session, avatar: snapshot.user.avatar)
    }
    .sheet(isPresented: $showsShortcutsSheet) {
      NativeShortcutsSheet(session: session)
    }
    .sheet(isPresented: $showsAgentSheet) {
      NavigationStack {
        NativeAgentChatPage(session: session)
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button {
                showsAgentSheet = false
              } label: {
                Image(systemName: "xmark")
              }
              .accessibilityLabel("关闭")
              .accessibilityIdentifier("native-agent-sheet-close")
            }
          }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .nativeAppearanceRoot()
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
    }
    .task(id: canDiscover ? discoveryAttempt : nil) {
      if canDiscover {
        await loadDiscovery(forceRefresh: discoveryAttempt > 0)
      }
    }
    .onChange(of: snapshot.user.permissions) { _ in
      if !canDiscover {
        discovery = NativeDiscoverContent(
          featured: nil, rails: [], continueWatching: [], providers: [], categories: [])
        mediaIdentities = [:]
        discoverPath = []
        explorePath = []
        searchPath = []
        if selectedTab == .discover || selectedTab == .explore || selectedTab == .search {
          selectedTab = .mine
        }
      }
    }
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

  /// 统一切换底部溢出菜单状态（内置 180ms 防抖，避免 UIKit 拦截代理与 SwiftUI 绑定重复触发）。
  private func toggleOverflowMenu() {
    let now = Date()
    guard now.timeIntervalSince(lastOverflowToggleAt) > 0.18 else { return }
    lastOverflowToggleAt = now
    let opening = !showsOverflowMenu
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    withAnimation(
      opening
        ? .spring(response: 0.36, dampingFraction: 0.64, blendDuration: 0.08)
        : .spring(response: 0.22, dampingFraction: 0.90)
    ) {
      showsOverflowMenu = opening
    }
  }

  /// 当前是否处于「我的」页且管理员身份（右下角搜索按钮自动切换为捷径弹窗入口）。
  private var isMineShortcutsButtonActive: Bool {
    selectedTab == .mine && snapshot.user.isSuperuser && dynamicActionCenter.current == nil
  }

  /// 当前右下角独立按钮是否被自定义动作（页面动态动作或「我的」页捷径弹窗）接管。
  private var hasTrailingCustomAction: Bool {
    dynamicActionCenter.current != nil || isMineShortcutsButtonActive
  }

  /// 执行右下角自定义动作（内置 180ms 防抖，防止 UIKit 代理拦截与 SwiftUI 绑定重复触发）。
  private func triggerTrailingCustomAction() {
    let now = Date()
    guard now.timeIntervalSince(lastTrailingActionAt) > 0.18 else { return }
    lastTrailingActionAt = now
    showsOverflowMenu = false
    if let dynamic = dynamicActionCenter.current {
      dynamic.handler()
    } else if isMineShortcutsButtonActive {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      showsShortcutsSheet = true
    }
  }

  /// 二次点击底部 4 个主图标中的任意一个时，直接弹出菜单而不滚动回顶部或触发返回；点击右侧 +1 按钮优先执行当前页动态主动作或「我的」页捷径弹窗，否则进入全局搜索。
  private var tabSelection: Binding<Page> {
    Binding(
      get: { selectedTab },
      set: { next in
        if next == .search, hasTrailingCustomAction {
          triggerTrailingCustomAction()
          return
        }
        if next == selectedTab && next != .search {
          toggleOverflowMenu()
        } else {
          if showsOverflowMenu {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.90)) {
              showsOverflowMenu = false
            }
          }
          dynamicActionCenter.reset()
          selectedTab = next
        }
      })
  }

  /// 拦截 UIKit UITabBarController 对当前已选中标签的重复点击以及右下角自定义按钮（如「我的」页捷径弹窗）的点击。
  private var tabReselectInterceptor: some View {
    NativeTabBarReselectInterceptor(
      shouldInterceptReselect: { selectedTab != .search },
      onReselect: { toggleOverflowMenu() },
      shouldInterceptTrailingTab: { hasTrailingCustomAction },
      onSelectTrailingTab: { triggerTrailingCustomAction() }
    )
    .frame(width: 0, height: 0)
    .allowsHitTesting(false)
  }

  /// 右侧 +1 圆形按钮标题：页面动态动作 > 「我的」页捷径 > 全局搜索。
  private var trailingButtonTitle: String {
    if let dynamic = dynamicActionCenter.current { return dynamic.title }
    if isMineShortcutsButtonActive { return "捷径" }
    return "搜索"
  }

  /// 右侧 +1 圆形按钮图标：页面动态动作 > 「我的」页捷径图标 > 放大镜。
  private var trailingButtonSymbol: String {
    if let dynamic = dynamicActionCenter.current { return dynamic.symbol }
    if isMineShortcutsButtonActive { return "bolt.fill" }
    return "magnifyingglass"
  }

  /// 右侧独立圆形按钮角色：iOS 27+ 使用 `.prominent` 确保始终与主导航胶囊分离成独立圆形玻璃键，iOS 18-26 沿用 `.search`。
  @available(iOS 18, *)
  private var trailingTabRole: TabRole {
    if #available(iOS 27.0, *) {
      return .prominent
    } else {
      return .search
    }
  }

  /// 原生 4+1 TabView：前 4 项为发现、探索、我的（仪表盘）、设置，第 +1 项为右侧动态主按钮/全局搜索。
  @ViewBuilder private var page: some View {
    if #available(iOS 18, *) {
      TabView(selection: tabSelection) {
        if canDiscover {
          Tab("发现", systemImage: "sparkles.tv", value: Page.discover) {
            discoveryTab
          }
          .accessibilityIdentifier("native-v2-tab-发现")

          Tab("探索", systemImage: "safari", value: Page.explore) {
            exploreTab
          }
          .accessibilityIdentifier("native-v2-tab-探索")
        }
        Tab(value: Page.mine) {
          mineTab
        } label: {
          if let userTabAvatar {
            Label {
              Text("我的")
            } icon: {
              Image(uiImage: userTabAvatar)
            }
          } else {
            Label("我的", systemImage: "person.crop.circle")
          }
        }
        .accessibilityIdentifier("native-v2-tab-我的")

        Tab("设置", systemImage: "gearshape", value: Page.settings) {
          settingsTab
        }
        .accessibilityIdentifier("native-v2-tab-设置")

        if canDiscover || hasTrailingCustomAction {
          Tab(
            trailingButtonTitle,
            systemImage: trailingButtonSymbol,
            value: Page.search,
            role: trailingTabRole
          ) {
            searchTab
          }
          .accessibilityIdentifier("native-v2-search-tab-item")
        }
      }
    } else {
      TabView(selection: tabSelection) {
        if canDiscover {
          discoveryTab
            .tag(Page.discover)
            .tabItem {
              Label("发现", systemImage: "sparkles.tv")
                .accessibilityIdentifier("native-v2-tab-发现")
            }
          exploreTab
            .tag(Page.explore)
            .tabItem {
              Label("探索", systemImage: "safari")
                .accessibilityIdentifier("native-v2-tab-探索")
            }
        }
        mineTab
          .tag(Page.mine)
          .tabItem {
            if let userTabAvatar {
              Label {
                Text("我的")
              } icon: {
                Image(uiImage: userTabAvatar)
              }
              .accessibilityIdentifier("native-v2-tab-我的")
            } else {
              Label("我的", systemImage: "person.crop.circle")
                .accessibilityIdentifier("native-v2-tab-我的")
            }
          }
        settingsTab
          .tag(Page.settings)
          .tabItem {
            Label("设置", systemImage: "gearshape")
              .accessibilityIdentifier("native-v2-tab-设置")
          }
        if canDiscover {
          searchTab
            .tag(Page.search)
            .tabItem { Label(trailingButtonTitle, systemImage: trailingButtonSymbol) }
        }
      }
    }
  }

  /// 探索标签：承载原生多来源影视与音乐探索片库，并支持从全局溢出菜单推入任意业务页。
  private var exploreTab: some View {
    NavigationStack(path: $explorePath) {
      NativeExplorePage(
        session: session,
        initialSource: .tmdbMovies
      )
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        workspaceDestinationView(destination)
      }
    }
    .background(tabReselectInterceptor)
  }

  /// 我的标签：超级管理员直显原生仪表盘，普通成员展示个人概览与权限快捷卡。
  private var mineTab: some View {
    NavigationStack(path: $minePath) {
      Group {
        if snapshot.user.isSuperuser {
          NativeDashboardPage(
            session: session,
            onOpenMessages: { minePath.append(.messages) }
          )
        } else {
          memberDashboardView
        }
      }
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        workspaceDestinationView(destination)
      }
    }
    .background(tabReselectInterceptor)
  }

  /// 非超级管理员进入「我的」时的个人概览卡片页，避免调用管理员统计接口。
  private var memberDashboardView: some View {
    ZStack {
      CinematicBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
            Text("我的")
              .font(.largeTitle.bold())
              .foregroundStyle(.primary)
              .accessibilityAddTraits(.isHeader)
          }
          .padding(.horizontal, 2)

          CinematicPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
              Text("欢迎回来，\(snapshot.user.name)")
                .font(.headline)
                .foregroundStyle(.primary)
              Text("再次点击底部任意标签图标，可随时展开全部功能菜单。")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }

          HStack(spacing: 12) {
            if canSubscribe {
              memberShortcutCard(title: "我的订阅", symbol: "bookmark.fill") {
                minePath.append(.subscriptions)
              }
              memberShortcutCard(title: "追剧日历", symbol: "calendar") {
                minePath.append(.calendar)
              }
            }
          }
          HStack(spacing: 12) {
            memberShortcutCard(title: "消息中心", symbol: "bell.fill") {
              minePath.append(.messages)
            }
            memberShortcutCard(title: "智能助手", symbol: "sparkles") {
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
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
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
            .foregroundStyle(Color(red: 0.78, green: 0.66, blue: 1.0))
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
  }

  /// 设置标签：承载卡片式设置主中心、全部系统/专项设置与右上角系统菜单（通知/小组件/语言/切换服务/退出登录）。
  private var settingsTab: some View {
    NavigationStack(path: $settingsPath) {
      NativeSettingsHubPage(
        session: session,
        snapshot: snapshot,
        currentLanguage: currentLanguage,
        onNavigate: { destination in
          settingsPath.append(destination)
        },
        onOpenModules: { showsModuleSheet = true },
        onOpenPlugins: { showsPlugins = true },
        onSelectLanguage: onSelectLanguage,
        onSwitchServer: {
          NativePageDataCache.shared.clearAll()
          NativeMediaArtworkCache.shared.clearMemory()
          onSwitchServer()
        },
        onLogout: {
          NativePageDataCache.shared.clearAll()
          NativeMediaArtworkCache.shared.clearSession(session)
          NativeEntityIconCache.shared.clearSession(session)
          onLogout()
        }
      )
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        workspaceDestinationView(destination)
      }
      .navigationDestination(isPresented: $showsPlugins) {
        pluginDestination()
      }
    }
    .background(tabReselectInterceptor)
  }

  /// 媒体搜索在自身导航栈内推入详情页，不通过遮罩弹窗打断检索上下文。
  private var searchTab: some View {
    NavigationStack(path: $searchPath) {
      NativeMediaSearchPage(
        session: session,
        onSelect: { source, id, type in
          guard let id, let type else { return }
          searchPath.append(NativeMediaIdentity(source: source, mediaID: id, type: type))
        }
      )
      .navigationDestination(for: NativeMediaIdentity.self) { identity in
        NativeMediaDetailPage(session: session, identity: identity)
      }
    }
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
        onOpenMedia: { id in
          if let identity = mediaIdentities[id] {
            discoverPath.append(.media(identity))
          }
        },
        onOpenRail: { id in
          if let rail = discovery.rails.first(where: { $0.id == id }) {
            discoverPath.append(.rail(rail))
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
          Task {
            _ = await NativeMediaPlaybackLauncher.shared.playMediaServerItem(
              session: session, itemID: itemID, server: item.server, title: item.media.title)
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
      .navigationDestination(for: NativeMediaDestination.self) { destination in
        switch destination {
        case .media(let identity):
          NativeMediaDetailPage(session: session, identity: identity)
        case .rail(let rail):
          NativeDiscoverRailGrid(session: session, rail: rail) { page in
            try await loadRailPage(rail.id, page: page)
          } destination: { identity in
            NativeMediaDetailPage(session: session, identity: identity)
          }
        case .workspace(let dest):
          workspaceDestinationView(dest)
        case .explore(let source):
          NativeExplorePage(session: session, initialSource: source)
        }
      }
    }
    .background(tabReselectInterceptor)
  }

  /// 统一将工作台路由映射到对应原生业务页面，供全部 4 个主标签与全局溢出菜单复用。
  @ViewBuilder
  private func workspaceDestinationView(_ destination: NativeWorkspaceDestination) -> some View {
    switch destination {
    case .explore(let source):
      NativeExplorePage(session: session, initialSource: source)
    case .music:
      NativeMusicPage(session: session)
    case .subscriptions:
      NativeSubscriptionsPage(session: session)
    case .subscribeCommunity:
      NativeSubscribeCommunityPage(session: session)
    case .downloads:
      NativeDownloadsPage(session: session)
    case .calendar:
      NativeCalendarPage(session: session)
    case .resources:
      NativeResourceSearchPage(session: session, target: .lastResults)
    case .history:
      NativeTransferHistoryPage(session: session)
    case .sites:
      NativeSitesPage(session: session)
    case .messages:
      NativeMessagesPage(session: session)
    case .agent:
      NativeAgentChatPage(session: session)
    case .files:
      NativeFileManagerPage(session: session)
    case .workflows:
      NativeWorkflowsPage(session: session)
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
    }
  }

  /// 从全局溢出菜单选中任意功能时，在当前激活标签的原生导航栈中平滑推入对应页面。
  private func openFromOverflow(_ destination: NativeWorkspaceDestination) {
    withAnimation(.easeOut(duration: 0.2)) {
      showsOverflowMenu = false
    }
    switch selectedTab {
    case .discover:
      discoverPath.append(.workspace(destination))
    case .explore:
      explorePath.append(destination)
    case .mine:
      minePath.append(destination)
    case .settings:
      settingsPath.append(destination)
    case .search:
      selectedTab = .mine
      minePath.append(destination)
    }
  }

  /// 消费来自 APNs 通知、桌面小组件与主屏幕快捷方式的受限路由意图，严格遵循当前账号权限门禁。
  private func consumeSystemRouteIfNeeded() {
    guard let target = routeHub.consumeTarget() else { return }
    showsOverflowMenu = false
    switch target {
    case .discover:
      if canDiscover { selectedTab = .discover }
    case .explore:
      if canDiscover { selectedTab = .explore }
    case .dashboard:
      selectedTab = .mine
    case .settings:
      selectedTab = .settings
    case .search:
      if canDiscover { selectedTab = .search }
    case .subscriptions:
      if canSubscribe { openFromOverflow(.subscriptions) }
    case .calendar:
      if canSubscribe { openFromOverflow(.calendar) }
    case .resources:
      if canSearchResources { openFromOverflow(.resources) }
    case .downloads:
      if canManageDownloads { openFromOverflow(.downloads) }
    case .files:
      if canManageDownloads { openFromOverflow(.files) }
    case .history:
      if canManageDownloads { openFromOverflow(.history) }
    case .workflows:
      if canManageDownloads { openFromOverflow(.workflows) }
    case .sites:
      if canManageDownloads {
        selectedTab = .settings
        settingsPath.append(.sites)
      }
    case .messages:
      selectedTab = .mine
      minePath.append(.messages)
    case .plugins:
      if snapshot.user.isSuperuser { openFromOverflow(.pluginMarket) }
    case .agent:
      showsAgentSheet = true
    }
  }

  /// 跨账号或失效小组件触发时展示顶部安全提示条（不自动切换实例或账号）。
  private func systemBannerOverlay(_ message: String) -> some View {
    VStack {
      CinematicPanel(padding: 12) {
        HStack(spacing: 10) {
          Image(systemName: "info.circle.fill")
            .foregroundStyle(Color(red: 0.78, green: 0.68, blue: 1.0))
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

  /// 溢出菜单弹出锚点：跟随当前激活的底部标签，呈现从对应图标处弹性绽放的原生动画。
  private var overflowMenuAnchor: UnitPoint {
    switch selectedTab {
    case .discover: .bottomLeading
    case .explore: UnitPoint(x: 0.34, y: 1.0)
    case .mine: UnitPoint(x: 0.66, y: 1.0)
    case .settings: .bottomTrailing
    case .search: .bottomLeading
    }
  }

  /// 溢出菜单屏幕停靠位置：左半区标签靠左对齐，右半区标签靠右对齐。
  private var overflowMenuAlignment: Alignment {
    switch selectedTab {
    case .mine, .settings: .bottomTrailing
    default: .bottomLeading
    }
  }

  /// 溢出菜单动态非对称弹性绽放过渡（直接挂在条件渲染卡片节点上，确保每次弹出都有明显缩放、位移与回弹）。
  private var overflowMenuTransition: AnyTransition {
    let anchor = overflowMenuAnchor
    return .asymmetric(
      insertion: .scale(scale: 0.28, anchor: anchor)
        .combined(with: .offset(y: 48))
        .combined(with: .opacity),
      removal: .scale(scale: 0.64, anchor: anchor)
        .combined(with: .offset(y: 26))
        .combined(with: .opacity)
    )
  }

  /// 溢出菜单点击关闭透明遮罩层（独立条件节点，仅淡入淡出不吞掉卡片弹性动画）。
  private var overflowMenuBackdrop: some View {
    Color.black.opacity(colorScheme == .light ? 0.10 : 0.16)
      .ignoresSafeArea()
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.90)) {
          showsOverflowMenu = false
        }
      }
      .accessibilityIdentifier("native-overflow-menu-backdrop")
  }

  /// 高透液态玻璃悬浮菜单卡片：顶部展示当前用户头像与信息，下方集中承载全部次级功能入口。
  private var overflowMenuCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 11) {
        NativeUserAvatarView(
          session: session,
          avatar: snapshot.user.avatar,
          name: snapshot.user.name,
          isSuperuser: snapshot.user.isSuperuser,
          size: 38
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(snapshot.user.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          HStack(spacing: 5) {
            Circle()
              .fill(Color(red: 0.42, green: 0.88, blue: 0.56))
              .frame(width: 6, height: 6)
            Text(snapshot.user.isSuperuser ? "超级管理员" : "普通成员")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.primary.opacity(0.68))
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("native-overflow-user-header")

      Divider().overlay(.primary.opacity(0.12))

      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          if canSubscribe || canSearchResources || canManageDownloads {
            if canSubscribe {
              overflowMenuRow(
                title: "订阅", symbol: "bookmark.fill", id: "native-workspace-subscriptions"
              ) { openFromOverflow(.subscriptions) }
              overflowMenuRow(
                title: "日历", symbol: "calendar", id: "native-workspace-calendar"
              ) { openFromOverflow(.calendar) }
            }
            if canSearchResources {
              overflowMenuRow(
                title: "资源", symbol: "magnifyingglass.circle.fill",
                id: "native-workspace-resources"
              ) { openFromOverflow(.resources) }
            }
            if canManageDownloads {
              overflowMenuRow(
                title: "下载", symbol: "arrow.down.circle.fill", id: "native-workspace-downloads"
              ) { openFromOverflow(.downloads) }
            }
          }

          if canManageDownloads || snapshot.user.isSuperuser {
            Divider().overlay(.primary.opacity(0.10)).padding(.vertical, 4)
            if canManageDownloads {
              overflowMenuRow(
                title: "文件", symbol: "folder.fill", id: "native-workspace-files"
              ) { openFromOverflow(.files) }
              overflowMenuRow(
                title: "历史", symbol: "clock.arrow.circlepath", id: "native-workspace-history"
              ) { openFromOverflow(.history) }
              overflowMenuRow(
                title: "工作流", symbol: "flowchart", id: "native-workspace-workflows"
              ) { openFromOverflow(.workflows) }
            }
            if snapshot.user.isSuperuser {
              overflowMenuRow(
                title: "插件", symbol: "puzzlepiece.extension.fill",
                id: "native-overflow-plugin-market"
              ) { openFromOverflow(.pluginMarket) }
            }
          }

          Divider().overlay(.primary.opacity(0.10)).padding(.vertical, 4)
          overflowMenuRow(
            title: "通知", symbol: "bell.fill", id: "native-overflow-messages"
          ) { openFromOverflow(.messages) }
        }
        .padding(.vertical, 8)
      }
      .scrollIndicators(.hidden)
      .frame(maxHeight: 440)
      .accessibilityIdentifier("native-overflow-menu-scroll")
    }
    .frame(width: 238)
    .modifier(NativeLiquidGlassPopoverSurface(cornerRadius: 26))
    .padding(.horizontal, 16)
    .padding(.bottom, 92)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: overflowMenuAlignment)
  }

  /// 悬浮快捷菜单中的单个原生入口行。
  private func overflowMenuRow(
    title: String, symbol: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.body.weight(.medium))
          .frame(width: 22)
          .foregroundStyle(Color(red: 0.84, green: 0.74, blue: 1.0))
        Text(title)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary)
        Spacer()
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 42)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
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
    async let moviesTask = try? requestDiscoverMedia("tmdb_movies", page: 1)
    async let tvTask = try? requestDiscoverMedia("tmdb_tvs", page: 1)
    async let trendingTask = try? requestRecommendMedia("tmdb_trending", page: 1)
    async let clientsTask = try? requestMediaServerClients()
    let (loadedModules, movies, television, trending, clients) = await (
      modulesTask, moviesTask, tvTask, trendingTask, clientsTask
    )
    guard !Task.isCancelled, discoveryGeneration == generation else { return }

    let resolvedModules = NativeDiscoverModuleItem.normalized(loadedModules ?? discoverModules)
    discoverModules = resolvedModules
    let enabledSet = Set(resolvedModules.filter(\.enabled).map(\.id))

    async let doubanShowingTask: [NativeDiscoverAPIItem]? =
      enabledSet.contains(.doubanShowing)
      ? (try? requestRecommendMedia("douban_showing", page: 1)) : nil
    async let doubanTopTask: [NativeDiscoverAPIItem]? =
      enabledSet.contains(.doubanTop250)
      ? (try? requestRecommendMedia("douban_movie_top250", page: 1)) : nil

    var continueWatching: [NativeDiscoverProgress] = []
    var latestItems: [NativeDiscoverMedia] = []
    var providers: [NativeDiscoverProvider] = []
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
      latestItems = (latestRows ?? []).compactMap(projectLatestItem)
      providers = (libraryRows ?? []).compactMap(projectLibraryProvider)
    } else {
      latestServerName = nil
    }

    let (doubanShowing, doubanTop) = await (doubanShowingTask, doubanTopTask)
    guard !Task.isCancelled, discoveryGeneration == generation else { return }

    var rails: [NativeDiscoverRail] = []
    var identities: [String: NativeMediaIdentity] = [:]
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
        id: NativeExploreSourceKind.doubanMovies.rawValue, title: "豆瓣片库",
        posterReference: projectedMovies?.dropFirst().first?.posterReference),
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.bangumi.rawValue, title: "Bangumi 番剧",
        posterReference: projectedTVs?.dropFirst().first?.posterReference),
      NativeDiscoverCategory(
        id: NativeExploreSourceKind.music.rawValue, title: "音乐探索",
        posterReference: projectedMovies?.dropFirst(2).first?.posterReference),
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
      return NativeDiscoverFeature(
        id: media.id,
        title: media.title,
        subtitle: subtitle,
        synopsis: item.overview ?? "",
        rating: item.voteAverage.flatMap { $0 > 0 ? String(format: "%.1f", $0) : nil },
        backdropReference: item.backdropPath ?? item.posterPath,
        logoReference: item.logoPath
      )
    }
    discovery = NativeDiscoverContent(
      featuredItems: featuredItems, rails: rails, continueWatching: continueWatching,
      providers: providers, categories: exploreCategories,
      moduleOrder: resolvedModules.filter(\.enabled).map(\.id),
      loadFailed: movies == nil || television == nil)
    mediaIdentities = identities
    hasLoadedDiscoveryOnce = true

    // 异步补拉主视觉透明标题 Logo 与风格摘要，不阻塞发现首屏呈现。
    Task {
      await enrichFeaturedLogos(
        generation: generation, items: featuredItems, identities: identities)
    }
  }

  /// 为缺少 `logo_path` 的主视觉条目异步补拉 `GET /api/v1/media/{id}` 透明标题 Logo。
  private func enrichFeaturedLogos(
    generation: UUID, items: [NativeDiscoverFeature], identities: [String: NativeMediaIdentity]
  ) async {
    var updated = items
    var changed = false
    for index in updated.indices.prefix(5) {
      guard !Task.isCancelled, discoveryGeneration == generation else { return }
      guard updated[index].logoReference == nil, let identity = identities[updated[index].id] else {
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
        if let logo = detail.logoPath, !logo.isEmpty {
          let current = updated[index]
          let genreText = detail.genreNames.prefix(3).joined(separator: " ")
          let dateText = detail.releaseDate?.isEmpty == false ? detail.releaseDate : detail.year
          let richSubtitle = [genreText, dateText].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
          updated[index] = NativeDiscoverFeature(
            id: current.id,
            title: current.title,
            subtitle: richSubtitle.isEmpty ? current.subtitle : richSubtitle,
            synopsis: current.synopsis.isEmpty ? (detail.overview ?? "") : current.synopsis,
            rating: current.rating,
            backdropReference: current.backdropReference ?? detail.backdropPath,
            logoReference: logo
          )
          changed = true
          // 首个或任一主视觉拿到 Logo 后立即刷新，不等其余精选条目全部串行返回。
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

  /// 单次持久化发现模块显隐与排序，并在需要时重新拉取新启用的豆瓣榜单。
  private func saveDiscoverModules(_ updated: [NativeDiscoverModuleItem]) async -> Bool {
    do {
      let body = try JSONEncoder().encode(updated)
      let endpoint = try APIEndpoint(
        path: ["user", "config", "NativeDiscoverModules"], method: .post, body: body)
      try await session.perform(endpoint)
      let needsRefetch = updated.contains { item in
        item.enabled
          && (item.id == .doubanShowing || item.id == .doubanTop250)
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

  /// 分区只允许映射到已声明的后端接口，未呈现的接口不能从界面任意构造。
  private func loadRailPage(_ railID: String, page: Int) async throws
    -> (items: [NativeDiscoverMedia], hasMore: Bool)
  {
    if railID == "latest" {
      guard let server = latestServerName, !server.isEmpty else { return ([], false) }
      let rows = try await requestMediaServerLatest(server: server, count: 20, page: page)
      let projected = rows.compactMap(projectLatestItem)
      return (projected, rows.count >= 20)
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
    let identifier = item.itemID?.value ?? item.id?.value ?? title
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
      posterReference: item.image
    )
    return NativeDiscoverProgress(
      media: media, progress: normalized, progressLabel: label,
      itemID: item.itemID?.value ?? item.id?.value, server: server)
  }

  /// 媒体服务器最新入库条目展示真实海报和年份/副标，不虚构外部 TMDB 详情身份。
  private func projectLatestItem(_ item: NativeMediaServerPlayItem) -> NativeDiscoverMedia? {
    guard let title = item.title, !title.isEmpty else { return nil }
    let identifier = item.itemID?.value ?? item.id?.value ?? title
    return NativeDiscoverMedia(
      id: "latest|\(identifier)",
      title: title,
      year: item.year?.value ?? item.subtitle,
      posterReference: item.image
    )
  }

  /// 媒体库卡片按服务端库名、数量与主图投影。
  private func projectLibraryProvider(_ item: NativeMediaServerLibrary) -> NativeDiscoverProvider? {
    guard let name = item.name, !name.isEmpty else { return nil }
    let identifier = item.itemID?.value ?? item.id?.value ?? name
    return NativeDiscoverProvider(
      id: "library|\(identifier)",
      name: name,
      itemCount: item.itemCount,
      artworkReference: item.image ?? item.imageList?.first
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

  /// TMDB 卡片须有真实原生 ID，缺失身份时不把标题当作后端 ID 提交。
  private func project(_ item: NativeDiscoverAPIItem, fallbackType: String) -> NativeDiscoverMedia?
  {
    let source = item.mediaSource ?? "themoviedb"
    let mediaID =
      item.mediaID.flatMap { $0.isEmpty ? nil : $0 }
      ?? (source == "themoviedb" ? item.tmdbID.map(String.init) : nil)
    guard let mediaID else { return nil }
    let identity = NativeMediaIdentity(
      source: source, mediaID: mediaID, type: item.type ?? fallbackType)
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

/// 媒体详情的受控来源、后端 ID 与影视类型，不包含任意详情 URL。
struct NativeMediaIdentity: Identifiable, Hashable {
  let source: String
  let mediaID: String
  let type: String

  /// 路由身份覆盖主来源、媒体原生 ID 和媒体类别，避免跨轨道出现错误复用。
  var id: String { [source, mediaID, type].joined(separator: "|") }
}

/// 跨标签与全局溢出菜单可推入的受控业务路由。
enum NativeWorkspaceDestination: Hashable {
  case explore(NativeExploreSourceKind)
  case music
  case subscriptions
  case subscribeCommunity
  case downloads
  case calendar
  case resources
  case history
  case sites
  case messages
  case agent
  case files
  case workflows
  case settings
  case systemModule(NativeSystemModulesPage.Domain)
  case diagnostics(NativeDiagnosticsToolsPage.Tool)
  case users
  case pluginMarket
  case appearance
}

/// 发现导航栈只接收已加载的分区、可验证媒体身份或受控业务页面。
private enum NativeMediaDestination: Identifiable, Hashable {
  case rail(NativeDiscoverRail)
  case media(NativeMediaIdentity)
  case explore(NativeExploreSourceKind)
  case workspace(NativeWorkspaceDestination)

  /// 区分分区网格、详情与工作台页面路由。
  var id: String {
    switch self {
    case .rail(let rail): "rail:" + rail.id
    case .media(let identity): "media:" + identity.id
    case .explore(let source): "explore:" + source.rawValue
    case .workspace(let dest): "workspace:\(dest.hashValue)"
    }
  }
}

/// `GET /api/v1/user/config/{key}` 统一返回值解码包装。
private struct NativeUserConfigValue<Value: Decodable & Sendable>: Decodable, Sendable {
  let value: Value?
}

/// 搜索结果和发现海报显示后端提供的 HTTPS 图片，优先命中同步内存缓存与本地磁盘缓存，无闪烁回显。
@MainActor
struct NativeMediaArtwork: View {
  let session: NativeSession
  let reference: String?
  let role: NativeDiscoverArtworkRole
  let maximumWidth: Int
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
  private var normalizedURL: URL? {
    guard let reference, reference.utf8.count <= 16_384,
      var components = URLComponents(string: reference),
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

  /// 二级缓存加载：L1 内存命中直出 → L2 本地磁盘后台解码 → 合并同 URL 并发请求拉取并落盘。
  private func load(for key: String) async {
    guard (try? session.checkActive()) != nil else { return }
    if let cached = NativeMediaArtworkCache.shared.memoryImage(for: key) {
      image = cached
      loadedKey = key
      return
    }
    if loadedKey != key {
      image = nil
    }
    guard let url = normalizedURL else { return }
    let scopeDir = NativeMediaArtworkCache.scopeDirectoryName(for: session)
    let limit = maximumWidth
    if let diskImage = await NativeMediaArtworkCache.shared.diskImage(
      for: key, scopeDir: scopeDir, limit: limit)
    {
      guard !Task.isCancelled else { return }
      image = diskImage
      loadedKey = key
      return
    }
    let decoded = await NativeMediaArtworkCache.shared.fetchAndCache(
      key: key, scopeDir: scopeDir, limit: limit
    ) {
      let response = try await session.requestImage(url, maximumWidth: limit)
      return response.data
    }
    guard !Task.isCancelled, let decoded else { return }
    image = decoded
    loadedKey = key
  }

  /// 缓存键覆盖服务器实例、用户 ID、尺寸与规范化 URL，跨冷启动复用本地磁盘缓存，登出时按作用域清理。
  private var cacheKey: String {
    [
      session.scope.instanceID.uuidString,
      String(session.scope.userID),
      String(maximumWidth),
      normalizedURL?.absoluteString ?? reference ?? "",
    ].joined(separator: "|")
  }

  /// 图片加载前的极简空白占位框（不显示占位背景图或图标）。
  private var placeholder: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.05))
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

  /// 退出登录时清理当前用户对应的内存与本地磁盘图片缓存。
  func clearSession(_ session: NativeSession) {
    clearMemory()
    let scopeDir = Self.scopeDirectoryName(for: session)
    Task.detached(priority: .utility) {
      if let dir = Self.cacheDirectory(scopeDir: scopeDir) {
        try? FileManager.default.removeItem(at: dir)
      }
    }
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
      return UIImage(cgImage: cgImage)
    }
    return UIImage(data: data)
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

/// 通过代理包装底层 UITabBarController，在重复点击已激活标签或点击右下角动态自定义按钮时返回 `false`，阻止滚回顶部、退回根页或闪烁切换标签。
private struct NativeTabBarReselectInterceptor: UIViewControllerRepresentable {
  let shouldInterceptReselect: () -> Bool
  let onReselect: () -> Void
  let shouldInterceptTrailingTab: () -> Bool
  let onSelectTrailingTab: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
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

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
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

  final class Coordinator: NSObject, UITabBarControllerDelegate {
    var shouldInterceptReselect: () -> Bool
    var onReselect: () -> Void
    var shouldInterceptTrailingTab: () -> Bool
    var onSelectTrailingTab: () -> Void
    private weak var observedTabBarController: UITabBarController?
    private weak var originalDelegate: (any UITabBarControllerDelegate)?

    init(
      shouldInterceptReselect: @escaping () -> Bool,
      onReselect: @escaping () -> Void,
      shouldInterceptTrailingTab: @escaping () -> Bool,
      onSelectTrailingTab: @escaping () -> Void
    ) {
      self.shouldInterceptReselect = shouldInterceptReselect
      self.onReselect = onReselect
      self.shouldInterceptTrailingTab = shouldInterceptTrailingTab
      self.onSelectTrailingTab = onSelectTrailingTab
    }

    func attach(to tabBarController: UITabBarController) {
      if observedTabBarController === tabBarController, tabBarController.delegate === self {
        return
      }
      if let existing = tabBarController.delegate, existing !== self {
        // 如果已挂过另一个同类代理，保持其底层原始 delegate，避免嵌套死循环
        if let other = existing as? Coordinator {
          originalDelegate = other.originalDelegate
        } else {
          originalDelegate = existing
        }
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
      if let last = tabBarController.viewControllers?.last,
        viewController === last,
        shouldInterceptTrailingTab()
      {
        onSelectTrailingTab()
        return false
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

/// 「我的」页右下角捷径弹窗：集中承载系统检查、网络测试、识别规则、实时日志与定时服务，点击后直接在弹窗栈内进入工具页。
@MainActor
private struct NativeShortcutsSheet: View {
  let session: NativeSession

  @Environment(\.dismiss) private var dismiss
  @State private var selectedTool: NativeDiagnosticsToolsPage.Tool?
  @State private var detent: PresentationDetent = .medium

  private struct ShortcutEntry: Identifiable {
    let tool: NativeDiagnosticsToolsPage.Tool
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var id: String { tool.rawValue }
  }

  private let entries: [ShortcutEntry] = [
    ShortcutEntry(
      tool: .health, title: "系统检查", subtitle: "组件健康与运行状态",
      symbol: "checkmark.shield", tint: Color(red: 0.44, green: 0.88, blue: 0.66)),
    ShortcutEntry(
      tool: .nettest, title: "网络测试", subtitle: "自动测速与连通检测",
      symbol: "network", tint: Color(red: 0.38, green: 0.72, blue: 1.0)),
    ShortcutEntry(
      tool: .ruleTest, title: "识别规则", subtitle: "名称识别与规则验证",
      symbol: "text.magnifyingglass", tint: Color(red: 0.74, green: 0.56, blue: 0.98)),
    ShortcutEntry(
      tool: .liveLog, title: "实时日志", subtitle: "查看服务端运行日志",
      symbol: "terminal", tint: Color(red: 0.96, green: 0.68, blue: 0.36)),
    ShortcutEntry(
      tool: .scheduler, title: "定时服务", subtitle: "手动触发后台任务",
      symbol: "clock.arrow.2.circlepath", tint: Color(red: 0.94, green: 0.52, blue: 0.68)),
  ]

  var body: some View {
    NavigationStack {
      ZStack {
        CinematicBackground()
        ScrollView {
          LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
          ) {
            ForEach(entries) { entry in
              Button {
                detent = .large
                selectedTool = entry.tool
              } label: {
                CinematicPanel(padding: 14) {
                  VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: entry.symbol)
                      .font(.title3.weight(.semibold))
                      .foregroundStyle(entry.tint)
                      .frame(width: 36, height: 36)
                      .background(
                        entry.tint.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                      Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.92))
                      Text(entry.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-shortcut-\(entry.tool.rawValue)")
            }
          }
          .padding(.horizontal, CinematicStyle.margin)
          .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle("捷径")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel("关闭")
          .accessibilityIdentifier("native-shortcuts-close")
        }
      }
      .navigationDestination(
        isPresented: Binding(
          get: { selectedTool != nil },
          set: { if !$0 { selectedTool = nil } })
      ) {
        if let tool = selectedTool {
          NativeDiagnosticsToolsPage(session: session, initialTool: tool)
        }
      }
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
    .nativeAppearanceRoot()
  }
}

/// 发现接口只反序列化详情首屏需要的字段，不将完整外部 JSON 塞进 SwiftUI。
private struct NativeDiscoverAPIItem: Decodable, Sendable {
  /// 后端影视风格可为对象数组。
  struct Genre: Decodable, Sendable { let name: String? }

  let mediaSource: String?
  let mediaID: String?
  let tmdbID: Int?
  let type: String?
  let title: String?
  let year: String?
  let releaseDate: String?
  let posterPath: String?
  let backdropPath: String?
  let logoPath: String?
  let overview: String?
  let voteAverage: Double?
  let genres: [Genre]?

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
    case releaseDate = "release_date"
    case posterPath = "poster_path"
    case backdropPath = "backdrop_path"
    case logoPath = "logo_path"
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
  let title: String?
  let subtitle: String?
  let year: NativeMediaServerScalar?
  let image: String?
  let percent: Double?

  /// 映射 MediaServerPlayItem 的稳定字段。
  private enum CodingKeys: String, CodingKey {
    case id, title, subtitle, year, image, percent
    case itemID = "item_id"
  }
}

/// 媒体服务器媒体库摘要投影。
private struct NativeMediaServerLibrary: Decodable, Sendable {
  let id: NativeMediaServerScalar?
  let itemID: NativeMediaServerScalar?
  let name: String?
  let itemCount: Int?
  let image: String?
  let imageList: [String]?

  /// 映射 MediaServerLibrary 的稳定字段。
  private enum CodingKeys: String, CodingKey {
    case id, name, image
    case itemID = "item_id"
    case itemCount = "item_count"
    case imageList = "image_list"
  }
}
