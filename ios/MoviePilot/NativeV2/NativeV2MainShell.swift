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
  @ObservedObject private var playbackLauncher = NativeMediaPlaybackLauncher.shared
  @Environment(\.colorScheme) private var colorScheme
  @State private var selectedTab: Page = .discover
  @State private var discovery = NativeDiscoverContent(
    featured: nil, rails: [], continueWatching: [], providers: [], categories: [], isLoading: true)
  @State private var discoveryGeneration = UUID()
  @State private var discoveryAttempt = 0
  @State private var mediaIdentities: [String: NativeMediaIdentity] = [:]
  @State private var musicSeeds: [String: NativeMusicCardItem] = [:]
  @State private var pendingSearchQuery: String?
  @State private var discoverPath: [NativeMediaDestination] = []
  @State private var explorePath: [NativeWorkspaceDestination] = []
  @State private var minePath: [NativeWorkspaceDestination] = []
  @State private var settingsPath: [NativeWorkspaceDestination] = []
  @State private var searchPath: [NativeMediaIdentity] = []
  @State private var showsOverflowMenu = false
  @State private var showsAgentSheet = false
  @State private var showsMessagesSheet = false
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

  /// 主导航交给系统 TabView 和每页独立 NavigationStack，并注入跨栈动态主按钮中心、浮动智能助手形象与全局溢出菜单。
  var body: some View {
    ZStack {
      page
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      if let miniMusic = playbackLauncher.miniMusicState, !showsOverflowMenu {
        floatingMiniMusicBar(miniMusic)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(45)
      }
      if showFloatingAssistant && !showsLaunchSplash && !showsOverflowMenu && !showsAgentSheet
        && !showsShortcutsSheet && !showsMessagesSheet
      {
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
      if let banner = routeHub.bannerMessage, !showsLaunchSplash {
        systemBannerOverlay(banner)
      }
      if showsLaunchSplash {
        NativeLaunchSplashView()
          .transition(.opacity)
          .zIndex(100)
      }
    }
    .animation(.easeOut(duration: 0.28), value: showsLaunchSplash)
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
    .task(id: "\(snapshot.scope)|\(snapshot.user.avatar)") {
      userTabAvatar = await NativeUserAvatarRenderer.loadTabAvatar(
        session: session, avatar: snapshot.user.avatar)
    }
    .sheet(isPresented: $showsShortcutsSheet) {
      NativeShortcutsSheet(session: session)
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
              .accessibilityLabel("关闭")
              .accessibilityIdentifier("native-messages-sheet-close")
            }
          }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .nativeAppearanceRoot()
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

  /// 当前右下角独立按钮是否被页面动态动作接管（无动态动作时固定为全局搜索按钮）。
  private var hasTrailingCustomAction: Bool {
    dynamicActionCenter.current != nil
  }

  /// 执行右下角自定义动作（内置 180ms 防抖，防止 UIKit 代理拦截与 SwiftUI 绑定重复触发）。
  private func triggerTrailingCustomAction() {
    let now = Date()
    guard now.timeIntervalSince(lastTrailingActionAt) > 0.18 else { return }
    lastTrailingActionAt = now
    showsOverflowMenu = false
    if let dynamic = dynamicActionCenter.current {
      dynamic.handler()
    }
  }

  /// 二次点击底部 4 个主图标中的任意一个时弹出溢出菜单；切换主标签时自动清理离开标签上临时承载的溢出页面，避免跨标签堆积无关导航历史。
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
          clearOverflowDestinations(in: selectedTab)
          dynamicActionCenter.reset()
          selectedTab = next
        }
      })
  }

  /// 拦截 UIKit UITabBarController 对当前已选中标签的重复点击以及右下角动态自定义按钮的点击。
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
          Tab(t("发现"), systemImage: "sparkles.tv", value: Page.discover) {
            discoveryTab
          }
          .accessibilityIdentifier("native-v2-tab-发现")

          Tab(t("探索"), systemImage: "safari", value: Page.explore) {
            exploreTab
          }
          .accessibilityIdentifier("native-v2-tab-探索")
        }
        Tab(value: Page.mine) {
          mineTab
        } label: {
          if let userTabAvatar {
            Label {
              Text(t("我的"))
            } icon: {
              Image(uiImage: userTabAvatar)
            }
          } else {
            Label(t("我的"), systemImage: "person.crop.circle")
          }
        }
        .accessibilityIdentifier("native-v2-tab-我的")

        Tab(t("设置"), systemImage: "gearshape", value: Page.settings) {
          settingsTab
        }
        .accessibilityIdentifier("native-v2-tab-设置")

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
    } else {
      TabView(selection: tabSelection) {
        if canDiscover {
          discoveryTab
            .tag(Page.discover)
            .tabItem {
              Label(t("发现"), systemImage: "sparkles.tv")
                .accessibilityIdentifier("native-v2-tab-发现")
            }
          exploreTab
            .tag(Page.explore)
            .tabItem {
              Label(t("探索"), systemImage: "safari")
                .accessibilityIdentifier("native-v2-tab-探索")
            }
        }
        mineTab
          .tag(Page.mine)
          .tabItem {
            if let userTabAvatar {
              Label {
                Text(t("我的"))
              } icon: {
                Image(uiImage: userTabAvatar)
              }
              .accessibilityIdentifier("native-v2-tab-我的")
            } else {
              Label(t("我的"), systemImage: "person.crop.circle")
                .accessibilityIdentifier("native-v2-tab-我的")
            }
          }
        settingsTab
          .tag(Page.settings)
          .tabItem {
            Label(t("设置"), systemImage: "gearshape")
              .accessibilityIdentifier("native-v2-tab-设置")
          }
        if canDiscover {
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

  /// 我的标签：超级管理员直显原生仪表盘，普通成员展示个人概览与权限快捷卡；右上角统一提供消息中心与捷径入口。
  private var mineTab: some View {
    NavigationStack(path: $minePath) {
      Group {
        if snapshot.user.isSuperuser {
          NativeDashboardPage(
            session: session,
            onOpenMessages: { showsMessagesSheet = true },
            onOpenShortcuts: { showsShortcutsSheet = true }
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
                openFromOverflow(.subscriptions)
              }
              memberShortcutCard(title: "追剧日历", symbol: "calendar") {
                openFromOverflow(.calendar)
              }
            }
          }
          HStack(spacing: 12) {
            memberShortcutCard(title: "消息中心", symbol: "bell.fill") {
              showsMessagesSheet = true
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
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showsMessagesSheet = true
        } label: {
          Image(systemName: "bell")
        }
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
            .foregroundStyle(NativeTheme.brand)
          Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
      }
    }
    .buttonStyle(.plain)
  }

  /// 设置标签：承载设置主中心与各专项管理页。
  private var settingsTab: some View {
    NavigationStack(path: $settingsPath) {
      NativeSettingsHubPage(
        session: session,
        snapshot: snapshot,
        currentLanguage: currentLanguage,
        onNavigate: { destination in
          clearOverflowDestinations(in: .settings)
          if settingsPath.last != destination {
            settingsPath.append(destination)
          }
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
        externalSearchQuery: $pendingSearchQuery,
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
        onSearchMedia: { media in
          pendingSearchQuery = media.title
          searchPath = []
          selectedTab = .search
        },
        onSubscribeMedia: { media in
          Task { await quickSubscribeFromDiscover(media) }
        },
        onOpenMedia: { id in
          if let seed = musicSeeds[id] {
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
    case .channelAuth:
      NativeChannelAuthorizationPage(session: session, isSuperuser: snapshot.user.isSuperuser)
    case .subscribeSearchSettings:
      NativeSubscribeSearchSettingsPage(session: session)
    case .downloadersManage:
      NativeDownloadersManagePage(session: session)
    case .mediaServersManage:
      NativeMediaServersManagePage(session: session)
    case .playbackSettings:
      NativePlaybackPreferencesPage()
    }
  }

  /// 判断路由是否属于底部溢出菜单的跨标签功能页（不属于单个主标签的持久历史）。
  private func isOverflowWorkspaceDestination(_ destination: NativeWorkspaceDestination) -> Bool {
    switch destination {
    case .subscriptions, .subscribeCommunity, .calendar, .resources, .downloads, .files, .history,
      .workflows, .pluginMarket:
      true
    default:
      false
    }
  }

  /// 清理指定主标签栈中由底部溢出菜单临时推入的跨标签页面，保持各主标签导航历史纯净。
  private func clearOverflowDestinations(in page: Page) {
    switch page {
    case .discover:
      discoverPath.removeAll {
        if case .workspace = $0 { return true }
        return false
      }
    case .explore:
      explorePath.removeAll(where: isOverflowWorkspaceDestination)
    case .mine:
      minePath.removeAll(where: isOverflowWorkspaceDestination)
    case .settings:
      settingsPath.removeAll(where: isOverflowWorkspaceDestination)
      if showsPlugins { showsPlugins = false }
    case .search:
      break
    }
  }

  /// 全局清理所有主标签上残留的临时溢出页面，避免多次通过溢出菜单切换后在某标签中堆积多层无关历史。
  private func clearAllOverflowDestinations() {
    clearOverflowDestinations(in: .discover)
    clearOverflowDestinations(in: .explore)
    clearOverflowDestinations(in: .mine)
    clearOverflowDestinations(in: .settings)
  }

  /// 从全局溢出菜单选中任意功能时，单层替换跨标签临时页面（永不层层叠加无关历史），在当前标签中直接呈现。
  private func openFromOverflow(_ destination: NativeWorkspaceDestination) {
    withAnimation(.easeOut(duration: 0.2)) {
      showsOverflowMenu = false
    }
    clearAllOverflowDestinations()
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
      if canDiscover {
        clearOverflowDestinations(in: selectedTab)
        selectedTab = .discover
      }
    case .explore:
      if canDiscover {
        clearOverflowDestinations(in: selectedTab)
        selectedTab = .explore
      }
    case .dashboard:
      clearOverflowDestinations(in: selectedTab)
      selectedTab = .mine
    case .settings:
      clearOverflowDestinations(in: selectedTab)
      selectedTab = .settings
    case .search:
      if canDiscover {
        clearOverflowDestinations(in: selectedTab)
        selectedTab = .search
      }
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
        clearAllOverflowDestinations()
        selectedTab = .settings
        settingsPath = [.sites]
      }
    case .messages:
      showsMessagesSheet = true
    case .plugins:
      if snapshot.user.isSuperuser { openFromOverflow(.pluginMarket) }
    case .agent:
      showsAgentSheet = true
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
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(.white.opacity(0.18), lineWidth: 0.6)
          }

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
      .padding(.horizontal, 14)
      .padding(.bottom, 86)
    }
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
            Text(snapshot.user.isSuperuser ? t("超级管理员") : t("普通成员"))
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

      ViewThatFits(in: .vertical) {
        overflowMenuRows(
          canSubscribe: canSubscribe,
          canSearchResources: canSearchResources,
          canManageDownloads: canManageDownloads
        )
        ScrollView {
          overflowMenuRows(
            canSubscribe: canSubscribe,
            canSearchResources: canSearchResources,
            canManageDownloads: canManageDownloads
          )
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 440)
      }
      .accessibilityIdentifier("native-overflow-menu-scroll")
    }
    .frame(width: 238)
    .modifier(NativeLiquidGlassPopoverSurface(cornerRadius: 26))
    .padding(.horizontal, 16)
    .padding(.bottom, 92)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: overflowMenuAlignment)
  }

  /// 悬浮快捷菜单条目容器：优先按内容真实高度紧密包裹，仅在超长字号或小屏时退化为滚动。
  private func overflowMenuRows(
    canSubscribe: Bool,
    canSearchResources: Bool,
    canManageDownloads: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if canSubscribe || canSearchResources || canManageDownloads {
        if canSubscribe {
          overflowMenuRow(
            title: t("我的订阅"), symbol: "bookmark.fill", id: "native-workspace-subscriptions"
          ) { openFromOverflow(.subscriptions) }
          overflowMenuRow(
            title: t("订阅日历"), symbol: "calendar", id: "native-workspace-calendar"
          ) { openFromOverflow(.calendar) }
        }
        if canSearchResources {
          overflowMenuRow(
            title: t("站点资源"), symbol: "magnifyingglass.circle.fill",
            id: "native-workspace-resources"
          ) { openFromOverflow(.resources) }
        }
        if canManageDownloads {
          overflowMenuRow(
            title: t("下载"), symbol: "arrow.down.circle.fill", id: "native-workspace-downloads"
          ) { openFromOverflow(.downloads) }
        }
      }

      if canManageDownloads || snapshot.user.isSuperuser {
        Divider().overlay(.primary.opacity(0.10)).padding(.vertical, 4)
        if canManageDownloads {
          overflowMenuRow(
            title: t("文件管理"), symbol: "folder.fill", id: "native-workspace-files"
          ) { openFromOverflow(.files) }
          overflowMenuRow(
            title: t("整理历史"), symbol: "clock.arrow.circlepath", id: "native-workspace-history"
          ) { openFromOverflow(.history) }
          overflowMenuRow(
            title: t("工作流"), symbol: "flowchart", id: "native-workspace-workflows"
          ) { openFromOverflow(.workflows) }
        }
        if snapshot.user.isSuperuser {
          overflowMenuRow(
            title: t("插件"), symbol: "puzzlepiece.extension.fill",
            id: "native-overflow-plugin-market"
          ) { openFromOverflow(.pluginMarket) }
        }
      }
    }
    .padding(.vertical, 8)
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
          .foregroundStyle(NativeTheme.brand)
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

    let (doubanMusic, doubanShowing, doubanTop) = await (
      doubanMusicTask, doubanShowingTask, doubanTopTask
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
    musicSeeds = nextMusicSeeds
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
      let projected = rows.compactMap(projectLatestItem)
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
  case channelAuth
  case subscribeSearchSettings
  case downloadersManage
  case mediaServersManage
  case playbackSettings
}

/// 发现导航栈只接收已加载的分区、可验证媒体身份或受控业务页面。
private enum NativeMediaDestination: Identifiable, Hashable {
  case rail(NativeDiscoverRail)
  case media(NativeMediaIdentity)
  case music(NativeMusicCardItem)
  case explore(NativeExploreSourceKind)
  case workspace(NativeWorkspaceDestination)

  /// 区分分区网格、详情与工作台页面路由。
  var id: String {
    switch self {
    case .rail(let rail): "rail:" + rail.id
    case .media(let identity): "media:" + identity.id
    case .music(let seed): "music:" + seed.id
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

/// 「我的」页右上角捷径弹窗：集中承载系统检查、网络测试、识别与规则、词表、实时日志与定时服务，点击后直接在弹窗栈内进入工具页。
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
      symbol: "checkmark.shield", tint: NativeTheme.success),
    ShortcutEntry(
      tool: .nettest, title: "网络测试", subtitle: "自动测速与连通检测",
      symbol: "network", tint: NativeTheme.info),
    ShortcutEntry(
      tool: .ruleTest, title: "识别与规则", subtitle: "名称识别与规则验证",
      symbol: "text.magnifyingglass", tint: NativeTheme.brand),
    ShortcutEntry(
      tool: .words, title: "词表", subtitle: "识别词、屏蔽词与剧集规则",
      symbol: "character.book.closed", tint: NativeTheme.cyan),
    ShortcutEntry(
      tool: .liveLog, title: "实时日志", subtitle: "结构化查看与级别过滤",
      symbol: "terminal", tint: NativeTheme.warning),
    ShortcutEntry(
      tool: .scheduler, title: "定时服务", subtitle: "系统与插件任务手动触发",
      symbol: "clock.arrow.2.circlepath", tint: NativeTheme.pink),
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
          let endpoint = try? APIEndpoint(
            path: ["media", "status"], method: .post, body: body, responseContract: .payload)
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

/// 与 `LaunchScreen.storyboard` 像素级一致的启动屏覆层：冷启动自动连接与发现首屏加载完成前持续展示居中 Logo，加载完成后柔和淡出。
@MainActor
struct NativeLaunchSplashView: View {
  var body: some View {
    ZStack {
      Color("LaunchBackground")
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
