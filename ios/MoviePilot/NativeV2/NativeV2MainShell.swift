import ImageIO
import MoviePilotAPI
import MoviePilotCore
import MoviePilotSession
import SwiftUI
import UIKit

/// 已认证 MoviePilot 的原生主导航；每个标签拥有独立原生 NavigationStack，共享同一实例会话。
@MainActor
struct NativeV2MainShell<AccountContent: View, PluginDestination: View>: View {
  /// 底栏只包含当前版本已经接入的页面。
  private enum Page: Hashable {
    case discover
    case dashboard
    case account
    case search
  }

  let session: NativeSession
  let snapshot: NativeSessionSnapshot
  @Binding var showsPlugins: Bool
  let accountContent: AccountContent
  let pluginDestination: () -> PluginDestination

  @State private var selectedTab: Page = .discover
  @State private var discovery = NativeDiscoverContent(
    featured: nil, rails: [], continueWatching: [], providers: [], categories: [], isLoading: true)
  @State private var discoveryGeneration = UUID()
  @State private var discoveryAttempt = 0
  @State private var mediaIdentities: [String: NativeMediaIdentity] = [:]
  @State private var discoverPath: [NativeMediaDestination] = []
  @State private var accountPath: [NativeWorkspaceDestination] = []
  @State private var searchPath: [NativeMediaIdentity] = []
  @State private var showsDiscoverQuickMenu = false

  /// 保留 root 原有账号动作与插件路由，主导航由系统 TabView 承载各标签独立栈。
  init(
    session: NativeSession, snapshot: NativeSessionSnapshot,
    showsPlugins: Binding<Bool>,
    accountContent: AccountContent,
    @ViewBuilder pluginDestination: @escaping () -> PluginDestination
  ) {
    self.session = session
    self.snapshot = snapshot
    _showsPlugins = showsPlugins
    self.accountContent = accountContent
    self.pluginDestination = pluginDestination
    _selectedTab = State(
      initialValue: snapshot.user.allows(.init(category: .discovery)) ? .discover : .account)
  }

  /// 主导航交给系统 TabView 和每页独立 NavigationStack，保留 iOS 原生标签栏与返回手势。
  var body: some View {
    page
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .task(id: canDiscover ? discoveryAttempt : nil) {
        if canDiscover { await loadDiscovery() }
      }
      .onChange(of: snapshot.user.permissions) { _ in
        if !canDiscover {
          discovery = NativeDiscoverContent(
            featured: nil, rails: [], continueWatching: [], providers: [], categories: [])
          mediaIdentities = [:]
          discoverPath = []
          searchPath = []
          if selectedTab == .discover || selectedTab == .search { selectedTab = .account }
        }
      }
  }

  /// 影视发现、媒体搜索与详情沿用现有发现权限，PT 资源搜索属于单独的权限。
  private var canDiscover: Bool { snapshot.user.allows(.init(category: .discovery)) }

  /// 订阅管理与追剧日历遵循订阅权限门禁。
  private var canSubscribe: Bool { snapshot.user.allows(.init(category: .subscribe)) }

  /// PT 站点资源搜索遵循独立搜索权限门禁。
  private var canSearchResources: Bool { snapshot.user.allows(.init(category: .search)) }

  /// 下载任务管理遵循管理员或管理权限门禁。
  private var canManageDownloads: Bool {
    snapshot.user.isSuperuser || snapshot.user.allows(.init(category: .manage))
  }

  /// 重复点击当前“发现”标签时弹出深色透色快捷菜单（参照视觉参考 09）。
  private var tabSelection: Binding<Page> {
    Binding(
      get: { selectedTab },
      set: { next in
        if next == .discover && selectedTab == .discover && discoverPath.isEmpty {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            showsDiscoverQuickMenu.toggle()
          }
        } else {
          showsDiscoverQuickMenu = false
          selectedTab = next
        }
      })
  }

  /// 原生 TabView 管理页面切换与底部标签栏，不另绘胶囊或缩窄系统按钮。
  @ViewBuilder private var page: some View {
    if #available(iOS 18, *) {
      TabView(selection: tabSelection) {
        if canDiscover {
          Tab("发现", systemImage: "sparkles.tv", value: Page.discover) {
            discoveryTab
          }
          .accessibilityIdentifier("native-v2-tab-发现")
        }
        Tab("我的", systemImage: "person.crop.circle", value: Page.account) { accountTab }
          .accessibilityIdentifier("native-v2-tab-我的")
        if snapshot.user.isSuperuser {
          Tab("仪表盘", systemImage: "chart.bar.xaxis", value: Page.dashboard) {
            dashboardTab
          }
          .accessibilityIdentifier("native-v2-tab-仪表盘")
        }
        if canDiscover {
          Tab("搜索", systemImage: "magnifyingglass", value: Page.search, role: .search) {
            searchTab
          }
          .accessibilityIdentifier("native-v2-search-tab-item")
        }
      }
    } else {
      TabView(selection: $selectedTab) {
        if canDiscover {
          discoveryTab
            .tag(Page.discover)
            .tabItem {
              Label("发现", systemImage: "sparkles.tv")
                .accessibilityIdentifier("native-v2-tab-发现")
            }
        }
        accountTab
          .tag(Page.account)
          .tabItem {
            Label("我的", systemImage: "person.crop.circle")
              .accessibilityIdentifier("native-v2-tab-我的")
          }
        if snapshot.user.isSuperuser {
          dashboardTab
            .tag(Page.dashboard)
            .tabItem {
              Label("仪表盘", systemImage: "chart.bar.xaxis")
                .accessibilityIdentifier("native-v2-tab-仪表盘")
            }
        }
        if canDiscover {
          searchTab
            .tag(Page.search)
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }
        }
      }
    }
  }

  /// 仪表盘拥有独立导航栈，保证系统工具栏刷新按钮与 Cinematic 渐变正常显示。
  private var dashboardTab: some View {
    NavigationStack {
      NativeDashboardPage(session: session)
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
        case .subscriptions:
          NativeSubscriptionsPage(session: session)
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
        case .files:
          NativeFileManagerPage(session: session)
        case .workflows:
          NativeWorkflowsPage(session: session)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if showsDiscoverQuickMenu && discoverPath.isEmpty {
          discoverQuickMenuOverlay
        }
      }
    }
  }

  /// 参照视觉参考 09 的深色透色悬浮快捷菜单，直达订阅、下载、日历与仪表盘。
  private var discoverQuickMenuOverlay: some View {
    ZStack(alignment: .bottomLeading) {
      Color.black.opacity(0.28)
        .ignoresSafeArea()
        .onTapGesture {
          withAnimation(.easeOut(duration: 0.2)) { showsDiscoverQuickMenu = false }
        }
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "server.rack")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 0.78, green: 0.66, blue: 1.0))
            .frame(width: 28, height: 28)
            .background { Circle().fill(.white.opacity(0.12)) }
          Text(snapshot.instance.address.url.host ?? "MoviePilot")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        Divider().overlay(.white.opacity(0.10))
        Text("打开")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.50))
          .padding(.horizontal, 16)
          .padding(.top, 10)
          .padding(.bottom, 4)
        if canSubscribe {
          quickMenuRow(title: "我的订阅", symbol: "bookmark.fill", id: "native-quick-subscriptions") {
            showsDiscoverQuickMenu = false
            discoverPath.append(.subscriptions)
          }
        }
        if canManageDownloads {
          quickMenuRow(
            title: "正在下载", symbol: "arrow.down.circle.fill", id: "native-quick-downloads"
          ) {
            showsDiscoverQuickMenu = false
            discoverPath.append(.downloads)
          }
        }
        if canSubscribe {
          quickMenuRow(title: "追剧日历", symbol: "calendar", id: "native-quick-calendar") {
            showsDiscoverQuickMenu = false
            discoverPath.append(.calendar)
          }
        }
        if canSearchResources {
          quickMenuRow(
            title: "资源搜索", symbol: "magnifyingglass.circle.fill", id: "native-quick-resources"
          ) {
            showsDiscoverQuickMenu = false
            discoverPath.append(.resources)
          }
        }
        if snapshot.user.isSuperuser {
          quickMenuRow(title: "仪表盘", symbol: "chart.bar.xaxis", id: "native-quick-dashboard") {
            showsDiscoverQuickMenu = false
            selectedTab = .dashboard
          }
        }
      }
      .padding(.bottom, 8)
      .frame(width: 256)
      .background {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(.ultraThinMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .fill(Color(red: 28 / 255, green: 24 / 255, blue: 38 / 255).opacity(0.72))
          }
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
          }
      }
      .shadow(color: .black.opacity(0.42), radius: 22, y: 10)
      .padding(.leading, 18)
      .padding(.bottom, 16)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    .accessibilityIdentifier("native-discover-quick-menu")
  }

  /// 悬浮快捷菜单中的单个原生入口行。
  private func quickMenuRow(
    title: String, symbol: String, id: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.body.weight(.medium))
          .frame(width: 22)
          .foregroundStyle(.white.opacity(0.92))
        Text(title)
          .font(.body.weight(.medium))
          .foregroundStyle(.white)
        Spacer()
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 46)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id)
  }

  /// 账号页与插件管理位于同一独立导航栈，底层保留连续 Cinematic 紫玫瑰渐变。
  private var accountTab: some View {
    NavigationStack(path: $accountPath) {
      ZStack {
        CinematicBackground()
        Form {
          Text("我的").font(.largeTitle.bold())
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            .accessibilityAddTraits(.isHeader)
          if canSubscribe || canManageDownloads || canSearchResources {
            CinematicFormSection("媒体工作台") {
              if canSubscribe {
                Button {
                  accountPath.append(.subscriptions)
                } label: {
                  CinematicFormRow(symbol: "bookmark.fill") {
                    Text("我的订阅")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-subscriptions")
              }
              if canSearchResources {
                if canSubscribe { CinematicFormDivider() }
                Button {
                  accountPath.append(.resources)
                } label: {
                  CinematicFormRow(symbol: "magnifyingglass.circle.fill") {
                    Text("资源搜索")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-resources")
              }
              if canManageDownloads {
                if canSubscribe || canSearchResources { CinematicFormDivider() }
                Button {
                  accountPath.append(.downloads)
                } label: {
                  CinematicFormRow(symbol: "arrow.down.circle.fill") {
                    Text("正在下载")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-downloads")
              }
              if canSubscribe {
                CinematicFormDivider()
                Button {
                  accountPath.append(.calendar)
                } label: {
                  CinematicFormRow(symbol: "calendar") {
                    Text("追剧日历")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-calendar")
              }
              if canManageDownloads {
                CinematicFormDivider()
                Button {
                  accountPath.append(.history)
                } label: {
                  CinematicFormRow(symbol: "clock.arrow.circlepath") {
                    Text("整理历史")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-history")
                CinematicFormDivider()
                Button {
                  accountPath.append(.sites)
                } label: {
                  CinematicFormRow(symbol: "globe") {
                    Text("站点管理")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-sites")
                CinematicFormDivider()
                Button {
                  accountPath.append(.files)
                } label: {
                  CinematicFormRow(symbol: "folder.fill") {
                    Text("文件管理")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-files")
                CinematicFormDivider()
                Button {
                  accountPath.append(.workflows)
                } label: {
                  CinematicFormRow(symbol: "flowchart") {
                    Text("工作流")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                      .foregroundStyle(.white.opacity(0.45))
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("native-workspace-workflows")
              }
              CinematicFormDivider()
              Button {
                accountPath.append(.messages)
              } label: {
                CinematicFormRow(symbol: "bell.fill") {
                  Text("消息中心")
                  Spacer()
                  Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("native-workspace-messages")
            }
          }
          accountContent
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
      }
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationDestination(for: NativeWorkspaceDestination.self) { destination in
        switch destination {
        case .subscriptions:
          NativeSubscriptionsPage(session: session)
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
        case .files:
          NativeFileManagerPage(session: session)
        case .workflows:
          NativeWorkflowsPage(session: session)
        }
      }
      .navigationDestination(isPresented: $showsPlugins) {
        pluginDestination()
      }
    }
  }

  /// 从 MoviePilot 发现、推荐与媒体服务器端点读取真实海报与进度，失败不注入演示数据。
  private func loadDiscovery() async {
    let generation = UUID()
    discoveryGeneration = generation
    discovery = NativeDiscoverContent(
      featuredItems: discovery.featuredItems, rails: discovery.rails,
      continueWatching: discovery.continueWatching, providers: discovery.providers,
      categories: discovery.categories, isLoading: true, loadFailed: discovery.loadFailed
    )

    async let moviesTask = try? requestDiscoverMedia("tmdb_movies", page: 1)
    async let tvTask = try? requestDiscoverMedia("tmdb_tvs", page: 1)
    async let trendingTask = try? requestRecommendMedia("tmdb_trending", page: 1)
    async let clientsTask = try? requestMediaServerClients()
    let (movies, television, trending, clients) = await (
      moviesTask, tvTask, trendingTask, clientsTask
    )
    guard !Task.isCancelled, discoveryGeneration == generation else { return }

    var continueWatching: [NativeDiscoverProgress] = []
    var latestItems: [NativeDiscoverMedia] = []
    var providers: [NativeDiscoverProvider] = []
    if let server = clients?.first?.name, !server.isEmpty {
      async let playingTask = try? requestMediaServerPlaying(server: server)
      async let latestTask = try? requestMediaServerLatest(server: server)
      async let libraryTask = try? requestMediaServerLibraries(server: server)
      let (playingRows, latestRows, libraryRows) = await (playingTask, latestTask, libraryTask)
      guard !Task.isCancelled, discoveryGeneration == generation else { return }
      continueWatching = (playingRows ?? []).compactMap(projectContinueWatching)
      latestItems = (latestRows ?? []).compactMap(projectLatestItem)
      providers = (libraryRows ?? []).compactMap(projectLibraryProvider)
    }

    var rails: [NativeDiscoverRail] = []
    var identities: [String: NativeMediaIdentity] = [:]
    if let movies {
      rails.append(
        NativeDiscoverRail(
          id: "movies", title: "热门电影",
          items: projectPage(movies, fallbackType: "电影", identities: &identities),
          hasMore: !movies.isEmpty))
    }
    if let television {
      rails.append(
        NativeDiscoverRail(
          id: "television", title: "热门剧集",
          items: projectPage(television, fallbackType: "电视剧", identities: &identities),
          hasMore: !television.isEmpty))
    }
    if let trending, !trending.isEmpty {
      rails.append(
        NativeDiscoverRail(
          id: "trending", title: "本周趋势",
          items: projectPage(trending, fallbackType: "电影", identities: &identities),
          hasMore: true, style: .backdrop))
    }
    if !latestItems.isEmpty {
      rails.append(NativeDiscoverRail(id: "latest", title: "最新入库", items: latestItems))
    }

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
        backdropReference: item.backdropPath ?? item.posterPath
      )
    }
    discovery = NativeDiscoverContent(
      featuredItems: featuredItems, rails: rails, continueWatching: continueWatching,
      providers: providers, categories: [], loadFailed: movies == nil || television == nil)
    mediaIdentities = identities
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
    default: throw APIError.invalidEndpoint
    }
    var identities: [String: NativeMediaIdentity] = [:]
    return (projectPage(rows, fallbackType: fallbackType, identities: &identities), !rows.isEmpty)
  }

  /// 媒体服务器继续观看条目保留后端标题、集数副标和实际播放进度百分比。
  private func projectContinueWatching(_ item: NativeMediaServerPlayItem) -> NativeDiscoverProgress?
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
    return NativeDiscoverProgress(media: media, progress: normalized, progressLabel: label)
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

/// 账号页媒体工作台可推入的受控业务路由。
private enum NativeWorkspaceDestination: Hashable {
  case subscriptions
  case downloads
  case calendar
  case resources
  case history
  case sites
  case messages
  case files
  case workflows
}

/// 发现导航栈只接收已加载的分区、可验证媒体身份或受控业务页面。
private enum NativeMediaDestination: Identifiable, Hashable {
  case rail(NativeDiscoverRail)
  case media(NativeMediaIdentity)
  case subscriptions
  case downloads
  case calendar
  case resources
  case history
  case sites
  case messages
  case files
  case workflows

  /// 区分分区网格、详情与工作台页面路由。
  var id: String {
    switch self {
    case .rail(let rail): "rail:" + rail.id
    case .media(let identity): "media:" + identity.id
    case .subscriptions: "subscriptions"
    case .downloads: "downloads"
    case .calendar: "calendar"
    case .resources: "resources"
    case .history: "history"
    case .sites: "sites"
    case .messages: "messages"
    case .files: "files"
    case .workflows: "workflows"
    }
  }
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

  /// 占位只表示图像暂缺，不伪造作品或来源平台图标。
  private var placeholder: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.34, green: 0.27, blue: 0.43),
          Color(red: 0.28, green: 0.22, blue: 0.36),
          Color(red: 0.19, green: 0.19, blue: 0.29),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
      Image(systemName: symbol).font(.system(size: role == .backdrop ? 42 : 24, weight: .light))
        .foregroundStyle(.white.opacity(0.48))
    }
  }

  /// 图片占位符按海报/横幅/平台/观看记录使用系统符号。
  private var symbol: String {
    switch role {
    case .backdrop: "sparkles.tv"
    case .poster: "film"
    case .provider: "play.rectangle.on.rectangle"
    case .continueWatching: "play.rectangle"
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
