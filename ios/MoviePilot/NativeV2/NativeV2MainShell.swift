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
  @State private var userTabAvatar: UIImage?
  @AppStorage("nativeV2.showFloatingAssistant") private var showFloatingAssistant = true
  @State private var discoverModules = NativeDiscoverModuleItem.defaults
  @State private var showsModuleSheet = false
  @State private var pendingModuleRefetch = false

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
      if showFloatingAssistant && !showsOverflowMenu && !showsAgentSheet {
        NativeAgentFloatingMascot(
          onOpen: { showsAgentSheet = true },
          onHide: { showFloatingAssistant = false }
        )
      }
      if showsOverflowMenu {
        overflowMenuOverlay
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
      if canDiscover { await loadDiscovery() }
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

  /// 二次点击底部 4 个主图标中的任意一个时，弹出不在底栏中的其余全部功能菜单；点击右侧 +1 按钮优先执行当前页动态主动作，否则进入全局搜索。
  private var tabSelection: Binding<Page> {
    Binding(
      get: { selectedTab },
      set: { next in
        if next == .search, let dynamic = dynamicActionCenter.current {
          showsOverflowMenu = false
          dynamic.handler()
          return
        }
        if next == selectedTab && next != .search {
          let opening = !showsOverflowMenu
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          withAnimation(
            opening
              ? .spring(response: 0.36, dampingFraction: 0.68, blendDuration: 0.12)
              : .spring(response: 0.24, dampingFraction: 0.88)
          ) {
            showsOverflowMenu = opening
          }
        } else {
          if showsOverflowMenu {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
              showsOverflowMenu = false
            }
          }
          dynamicActionCenter.reset()
          selectedTab = next
        }
      })
  }

  /// 右侧 +1 圆形按钮标题：当前页声明动态动作时显示页面动作，否则回退全局搜索。
  private var trailingButtonTitle: String {
    dynamicActionCenter.current?.title ?? "搜索"
  }

  /// 右侧 +1 圆形按钮图标：当前页声明动态动作时显示页面图标，否则回退放大镜。
  private var trailingButtonSymbol: String {
    dynamicActionCenter.current?.symbol ?? "magnifyingglass"
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

        if canDiscover || dynamicActionCenter.current != nil {
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
        onSwitchServer: onSwitchServer,
        onLogout: onLogout
      )
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        workspaceDestinationView(destination)
      }
      .navigationDestination(isPresented: $showsPlugins) {
        pluginDestination()
      }
    }
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

  /// 高透液态玻璃悬浮菜单：顶部展示当前用户头像与信息，下方集中承载订阅、日历、资源、下载、文件、历史、工作流、插件与通知中心入口，带弹性水动弹出过渡。
  private var overflowMenuOverlay: some View {
    ZStack(alignment: .bottomLeading) {
      Color.black.opacity(colorScheme == .light ? 0.10 : 0.16)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
          withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            showsOverflowMenu = false
          }
        }
        .transition(.opacity)
        .accessibilityIdentifier("native-overflow-menu-backdrop")
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
      .padding(.leading, 16)
      .padding(.bottom, 92)
      .transition(
        .asymmetric(
          insertion: .scale(scale: 0.72, anchor: .bottomLeading)
            .combined(with: .offset(y: 26))
            .combined(with: .opacity),
          removal: .scale(scale: 0.86, anchor: .bottomLeading)
            .combined(with: .offset(y: 14))
            .combined(with: .opacity)
        )
      )
    }
    .zIndex(50)
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

  /// 从 MoviePilot 发现、推荐与媒体服务器端点读取真实海报与进度，失败不注入演示数据。
  private func loadDiscovery() async {
    let generation = UUID()
    discoveryGeneration = generation
    discovery = NativeDiscoverContent(
      featuredItems: discovery.featuredItems, rails: discovery.rails,
      continueWatching: discovery.continueWatching, providers: discovery.providers,
      categories: discovery.categories,
      moduleOrder: discoverModules.filter(\.enabled).map(\.id),
      isLoading: true, loadFailed: discovery.loadFailed
    )

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
      async let playingTask = try? requestMediaServerPlaying(server: server)
      async let latestTask = try? requestMediaServerLatest(server: server)
      async let libraryTask = try? requestMediaServerLibraries(server: server)
      let (playingRows, latestRows, libraryRows) = await (playingTask, latestTask, libraryTask)
      guard !Task.isCancelled, discoveryGeneration == generation else { return }
      continueWatching = (playingRows ?? []).compactMap {
        projectContinueWatching($0, server: server)
      }
      latestItems = (latestRows ?? []).compactMap(projectLatestItem)
      providers = (libraryRows ?? []).compactMap(projectLibraryProvider)
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
      rails.append(NativeDiscoverRail(id: "latest", title: "最新入库", items: latestItems))
    }

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

  /// 读取媒体服务器最新入库条目，以标准海报栏呈现。
  private func requestMediaServerLatest(server: String) async throws -> [NativeMediaServerPlayItem]
  {
    let endpoint = try APIEndpoint(
      path: ["mediaserver", "latest"],
      query: [
        URLQueryItem(name: "server", value: server),
        URLQueryItem(name: "count", value: "16"),
      ])
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

  /// 分区只允许映射到已声明的后端接口，未呈现的接口不能从界面任意构造。
  private func loadRailPage(_ railID: String, page: Int) async throws
    -> (items: [NativeDiscoverMedia], hasMore: Bool)
  {
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

/// 搜索结果和发现海报显示后端提供的 HTTPS 图片，并交由当前 MoviePilot 实例代理。
@MainActor
struct NativeMediaArtwork: View {
  let session: NativeSession
  let reference: String?
  let role: NativeDiscoverArtworkRole
  let maximumWidth: Int
  @State private var image: UIImage?

  /// 未验证图片或加载失败时保留 Cinematic 紫玫瑰色海报占位。
  var body: some View {
    GeometryReader { bounds in
      Group {
        if let image {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          placeholder
        }
      }
      .frame(width: bounds.size.width, height: bounds.size.height)
      .clipped()
    }
    .task(id: cacheKey) { await load() }
    .accessibilityHidden(true)
  }

  /// 只把经过校验的 HTTP(S) 图片地址交给同源后端图片代理，剥离前端附加片段且绝不透传主令牌。
  private func load() async {
    image = nil
    guard let reference, reference.utf8.count <= 16_384,
      var components = URLComponents(string: reference),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      components.host?.isEmpty == false,
      components.user == nil, components.password == nil
    else { return }
    components.fragment = nil
    if components.path.hasPrefix("/t/p/original/") {
      let bucket = maximumWidth <= 500 ? "w500" : (maximumWidth <= 800 ? "w780" : "w1280")
      components.path =
        "/t/p/\(bucket)/" + components.path.dropFirst("/t/p/original/".count)
    }
    guard let url = components.url else { return }
    let key = cacheKey
    guard (try? session.checkActive()) != nil else { return }
    if let cached = NativeMediaArtworkCache.shared.image(for: key) {
      image = cached
      return
    }
    do {
      let response = try await session.requestImage(url, maximumWidth: maximumWidth)
      try Task.checkCancellation()
      guard let decoded = Self.thumbnail(response.data, limit: maximumWidth) else { return }
      NativeMediaArtworkCache.shared.store(decoded, for: key)
      image = decoded
    } catch { return }
  }

  /// 在分配显示位图前缩放源图，避免大尺寸原图直接解码进滚动列表。
  private static func thumbnail(_ data: Data, limit: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: limit,
        ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
  }

  /// 缓存键覆盖服务、用户和登录代次，避免同一 URL 跨认证会话复用。
  private var cacheKey: String {
    [
      session.scope.instanceID.uuidString,
      String(session.scope.userID),
      session.scope.generation.uuidString,
      String(maximumWidth),
      reference ?? "",
    ].joined(separator: "|")
  }

  /// 轻盈通透的毛玻璃占位层，海报加载前不出现厚重暗块。
  private var placeholder: some View {
    ZStack {
      Rectangle()
        .fill(.ultraThinMaterial)
      LinearGradient(
        colors: [
          Color.white.opacity(0.14),
          Color.white.opacity(0.05),
          Color.clear,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Image(systemName: symbol)
        .font(.system(size: role == .backdrop ? 38 : 22, weight: .ultraLight))
        .foregroundStyle(.primary.opacity(0.32))
    }
  }

  /// 图片占位符按海报/横幅/平台/观看记录使用系统符号。
  private var symbol: String {
    switch role {
    case .backdrop: "sparkles.tv"
    case .poster: "film"
    case .provider: "play.rectangle.on.rectangle"
    case .continueWatching: "play.rectangle"
    case .logo: "textformat"
    }
  }
}

/// 仅在进程内暂存受控海报，登出代次通过缓存键隔离且没有磁盘持久化。
@MainActor
private final class NativeMediaArtworkCache {
  static let shared = NativeMediaArtworkCache()
  private let images = NSCache<NSString, UIImage>()

  /// 限制页面滚动带来的图像驻留体积，系统内存压力下允许回收。
  private init() { images.totalCostLimit = 48 * 1024 * 1024 }

  /// 返回同一服务和登录代次已加载的海报。
  func image(for key: String) -> UIImage? { images.object(forKey: key as NSString) }

  /// 存放解码图片并以位图尺寸计入缓存成本。
  func store(_ image: UIImage, for key: String) {
    let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
    images.setObject(image, forKey: key as NSString, cost: cost)
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
