import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import {
  CinematicAmbientGradient,
  HarmonyBottomNavBar,
  HarmonySideNavRail,
  FloatingAiMascotButton,
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  HarmonyMainTab,
  clearEntityLogoCache
} from '@moviepilot/design_system';
import {
  FloatingMiniMusicBar,
  HarmonyAudioSession,
  HarmonyPlaybackRequest,
  NativeMediaPlayerView
} from '@moviepilot/media_player';
import {
  RustCoreBridge,
  NativeHuksStore,
  SavedServerEntry,
  PersistedAuthSession,
  MpImageLoader,
  MpMediaItem,
  MpCastMember,
  MoviePilotRepository
} from '@moviepilot/core_rust_bridge';
import { HarmonyServerConnectionPage, HarmonyLoginPage } from '@moviepilot/auth';
import {
  HarmonyDiscoverPage,
  HarmonyMediaServerLibraryPage,
  HarmonyExplorePage,
  HarmonyGlobalSearchPage
} from '@moviepilot/discover';
import {
  HarmonyMediaDetailPage,
  HarmonyMediaServerDetailPage,
  HarmonyPersonDetailPage
} from '@moviepilot/media';
import { HarmonySubscriptionsPage } from '@moviepilot/subscribe';
import { HarmonyResourceSearchPage, HarmonyDownloadsPage } from '@moviepilot/download';
import { HarmonyLibraryPage } from '@moviepilot/library';
import { HarmonyDashboardPage, HarmonyDiagnosticsPage, HarmonyMoreHubPage } from '@moviepilot/dashboard';
import { HarmonyWorkflowCanvasPage, HarmonySitesPage } from '@moviepilot/automation';
import { HarmonyAgentChatPage } from '@moviepilot/agent';
import { HarmonySettingsHubPage, HarmonyPluginsPage } from '@moviepilot/settings';

import EntryAbility from '../entryability/EntryAbility';

const MAIN_TAB_ORDER: HarmonyMainTab[] = ['discover', 'explore', 'subscribe', 'more', 'dashboard'];

/**
 * MoviePilot HarmonyOS NEXT / HarmonyOS 7 主入口页面：
 * - 启动时自动恢复 HUKS 安全凭据会话、已保存服务器与主题外观快照，401/令牌失效自动全局登出；
 * - 5 大主导航常驻挂载于隐藏标签栏的 `Tabs` 容器，二级页面叠加于上方，返回时 100% 保留滚动位置；
 * - 联动 `HarmonyAudioSession` 迷你音乐条无缝续播、可拖拽紫色机器人吉祥物避让及深度链接分发。
 */
@Entry
@Component
struct Index {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) @Watch('onDarkChanged') isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_BREAKPOINT) breakpoint: string = 'sm';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP) safeLeftVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_RIGHT_VP) safeRightVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_SHOW_AI_MASCOT) showAiMascot: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ALLOW_SELF_SIGNED) allowSelfSigned: boolean = false;
  @StorageProp('mp_pending_deeplink') @Watch('onPendingDeepLinkChanged') pendingDeepLink: string = '';
  @StorageProp('mp_pending_media_uri') @Watch('onPendingMediaUriChanged') pendingMediaUri: string = '';
  @StorageProp('mp_audio_is_playing') audioIsPlaying: boolean = false;

  @State private hydratingSession: boolean = true;
  @State private authStage: string = 'connect'; // 'connect' | 'login' | 'main'
  @State private serverSwitchReturnStage: string = ''; // '' | 'main' | 'login'
  @State private serverUrl: string = '';
  @State private userName: string = 'admin';
  @State private userAvatar: string = '';
  @State private isSuperuser: boolean = true;
  @State private savedServers: SavedServerEntry[] = [];
  @State private selectedTab: HarmonyMainTab = 'discover';
  @State private routeStack: string[] = [];
  @State private exploreSource: string = 'tmdb_movies';
  @State private activeLibraryId: string = '';
  @State private activeLibraryServer: string = '';
  @State private resourceSearchKeyword: string = '';
  @State private selectedMedia: MpMediaItem | null = null;
  @State private selectedPerson: MpCastMember | null = null;
  @State private activePlayer: HarmonyPlaybackRequest | null = null;
  @State private miniMusic: HarmonyPlaybackRequest | null = null;
  private tabsController: TabsController = new TabsController();

  private onDarkChanged(): void {
    EntryAbility.syncWindowAppearance(this.isDark);
  }

  aboutToAppear(): void {
    MoviePilotRepository.shared().setOnSessionExpired(() => {
      this.handleLogout(true);
    });
    this.bootstrapSessionAndAppearance();
  }

  private async bootstrapSessionAndAppearance(): Promise<void> {
    const store = NativeHuksStore.shared();
    try {
      if (EntryAbility.storeInitPromise) {
        await EntryAbility.storeInitPromise;
      } else {
        const hostCtx = this.getUIContext().getHostContext();
        if (hostCtx) {
          await store.init(hostCtx as common.Context);
        }
      }

      const appearanceJson = await store.loadAppearanceJson();
      if (appearanceJson.length > 2) {
        HarmonyAppearanceStore.importSnapshot(appearanceJson);
        EntryAbility.syncWindowAppearance(AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true);
      }

      this.savedServers = await store.loadServersList();
      const activeSess = await store.loadActiveSession();
      if (activeSess && activeSess.serverUrl.length > 0 && activeSess.token.length > 0 && activeSess.keepLogin) {
        this.serverUrl = activeSess.serverUrl;
        this.userName = activeSess.userName || 'admin';
        this.isSuperuser = activeSess.isSuperuser;
        this.userAvatar = activeSess.userAvatar || '';
        this.allowSelfSigned = activeSess.allowSelfSigned;
        const repo = MoviePilotRepository.shared();
        repo.configureServer(activeSess.serverUrl, activeSess.allowSelfSigned);
        repo.setAuthToken(activeSess.token);
        this.authStage = 'main';
        this.consumePendingIntents();
      } else if (this.savedServers.length > 0) {
        this.serverUrl = this.savedServers[0].url;
        this.allowSelfSigned = Boolean(this.savedServers[0].allowSelfSigned);
      }
    } catch {
      // fallback to connect stage
    }
    this.hydratingSession = false;
  }

  onPendingDeepLinkChanged(): void {
    this.consumePendingIntents();
  }

  onPendingMediaUriChanged(): void {
    this.consumePendingIntents();
  }

  private consumePendingIntents(): void {
    if (this.authStage !== 'main') {
      return;
    }
    const rawDl = AppStorage.get<string>('mp_pending_deeplink') ?? '';
    if (rawDl.length > 0) {
      AppStorage.setOrCreate('mp_pending_deeplink', '');
      this.applyDeepLinkJson(rawDl);
    }
    const rawMedia = AppStorage.get<string>('mp_pending_media_uri') ?? '';
    if (rawMedia.length > 0) {
      AppStorage.setOrCreate('mp_pending_media_uri', '');
      const kind = RustCoreBridge.detectPlayableMediaKind(rawMedia, true);
      const title = decodeURIComponent(rawMedia.substring(rawMedia.lastIndexOf('/') + 1)) || '外部媒体';
      this.playMedia({
        url: rawMedia,
        title: title,
        subtitle: '外部直放媒体流',
        isAudio: kind === 'audio'
      });
    }
  }

  private applyDeepLinkJson(rawJson: string): void {
    try {
      const obj = JSON.parse(rawJson) as Record<string, Object>;
      const kind = String(obj['kind'] ?? 'discover');
      if (kind === 'discover') {
        this.switchTab('discover');
      } else if (kind === 'explore') {
        const src = String(obj['source'] ?? '');
        if (src.length > 0) { this.exploreSource = src; }
        this.switchTab('explore');
      } else if (kind === 'subscriptions') {
        this.switchTab('subscribe');
      } else if (kind === 'subscribeCommunity') {
        this.routeStack = ['subscribe_square'];
      } else if (kind === 'dashboard') {
        this.switchTab('dashboard');
      } else if (kind === 'search') {
        this.routeStack = ['search'];
      } else if (kind === 'resources') {
        this.resourceSearchKeyword = String(obj['query'] ?? '');
        this.routeStack = ['resources'];
      } else if (kind === 'downloads') {
        this.routeStack = ['downloads'];
      } else if (kind === 'files') {
        this.routeStack = ['files'];
      } else if (kind === 'history') {
        this.routeStack = ['history'];
      } else if (kind === 'workflows') {
        this.routeStack = ['workflows'];
      } else if (kind === 'plugins') {
        this.routeStack = ['plugins'];
      } else if (kind === 'agent') {
        this.routeStack = ['agent'];
      } else if (kind === 'settings' || kind === 'appearance' || kind === 'users' || kind === 'systemSettings') {
        this.routeStack = ['settings'];
      } else if (kind === 'diagnostics') {
        const sec = String(obj['section'] ?? 'check');
        this.routeStack = [`diag_${sec}`];
      } else if (kind === 'mediaDetail') {
        const mediaId = String(obj['media_id'] ?? obj['id'] ?? '');
        if (mediaId.length > 0) {
          this.selectedMedia = {
            id: mediaId,
            mediaId: mediaId,
            tmdbId: /^\d+$/.test(mediaId) ? mediaId : '',
            doubanId: '',
            title: String(obj['title'] ?? '媒体详情'),
            enTitle: '',
            year: String(obj['year'] ?? ''),
            type: String(obj['media_type'] ?? '电影'),
            overview: '',
            vote: 0,
            posterUrl: '',
            backdropUrl: '',
            logoUrl: '',
            source: 'themoviedb',
            inLibrary: false,
            subtitle: '',
            percent: 0,
            serverName: '',
            playUrl: ''
          };
          this.routeStack = ['detail'];
        }
      }
    } catch {
      // ignore malformed deeplink
    }
  }

  private currentRoute(): string {
    return this.routeStack.length > 0 ? this.routeStack[this.routeStack.length - 1] : 'tab';
  }

  private activeMainTabIndex(): number {
    const idx = MAIN_TAB_ORDER.indexOf(this.selectedTab);
    return idx >= 0 ? idx : 0;
  }

  private pushRoute(route: string): void {
    this.routeStack = [...this.routeStack, route];
  }

  private popRoute(): void {
    if (this.routeStack.length > 0) {
      this.routeStack = this.routeStack.slice(0, this.routeStack.length - 1);
    }
  }

  private switchTab(tab: HarmonyMainTab): void {
    this.selectedTab = tab;
    this.routeStack = [];
    const idx = MAIN_TAB_ORDER.indexOf(tab);
    if (idx >= 0) {
      this.tabsController.changeIndex(idx);
    }
  }

  private playMedia(req: HarmonyPlaybackRequest): void {
    this.activePlayer = req;
    if (req.isAudio) {
      this.miniMusic = req;
    }
  }

  private openMediaSmart(it: MpMediaItem): void {
    this.selectedMedia = it;
    const isMediaServerCard = it.source === 'mediaserver' || it.source === 'library' ||
      (Boolean(it.serverItemId && it.serverItemId.length > 0) && it.serverName.length > 0 && it.mediaId.length === 0);
    this.pushRoute(isMediaServerCard ? 'mediaserver_detail' : 'detail');
  }

  private async playServerItemById(itemId: string, server: string, fallbackTitle: string): Promise<void> {
    try {
      const info = await MoviePilotRepository.shared().fetchVideoStreamInfo(itemId, server);
      if (info && info.contentUrl.length > 0) {
        this.playMedia({
          url: info.contentUrl,
          title: info.title || fallbackTitle,
          subtitle: server,
          isAudio: info.mediaType === 'audio'
        });
      }
    } catch {
      // ignore stream lookup error
    }
  }

  private restoreFromServerSwitch(): void {
    const prev = this.serverSwitchReturnStage;
    this.serverSwitchReturnStage = '';
    if (prev === 'login') {
      this.authStage = 'login';
    } else if (prev === 'main') {
      this.authStage = 'main';
    }
  }

  private commitConnectedServer(url: string, selfSigned: boolean): void {
    const returningFromMain = this.serverSwitchReturnStage === 'main';
    const sameAuthenticatedServer = returningFromMain &&
      url === this.serverUrl &&
      MoviePilotRepository.shared().token.length > 0;

    if (sameAuthenticatedServer) {
      this.allowSelfSigned = selfSigned;
      MoviePilotRepository.shared().configureServer(url, selfSigned);
      this.serverSwitchReturnStage = '';
      this.authStage = 'main';
      return;
    }

    if (returningFromMain && url !== this.serverUrl) {
      HarmonyAudioSession.shared().stopAndRelease();
      this.activePlayer = null;
      this.miniMusic = null;
      MoviePilotRepository.shared().clearSession();
      NativeHuksStore.shared().clearActiveSession().catch(() => {});
      MpImageLoader.clearCache();
      clearEntityLogoCache();
      try {
        webview.WebCookieManager.clearAllCookiesSync();
      } catch {
        // ignore cookie cleanup error
      }
      try {
        webview.WebStorage.deleteAllData();
      } catch {
        // ignore web domStorage cleanup error
      }
      this.routeStack = [];
      this.selectedTab = 'discover';
    }

    this.serverUrl = url;
    this.allowSelfSigned = selfSigned;
    MoviePilotRepository.shared().configureServer(url, selfSigned);
    this.serverSwitchReturnStage = '';
    this.authStage = 'login';
  }

  private handleLogout(_fromSessionExpired: boolean = false): void {
    if (this.authStage !== 'main' && _fromSessionExpired) {
      return;
    }
    this.serverSwitchReturnStage = '';
    HarmonyAudioSession.shared().stopAndRelease();
    this.activePlayer = null;
    this.miniMusic = null;
    MoviePilotRepository.shared().clearSession();
    NativeHuksStore.shared().clearActiveSession().catch(() => {});
    MpImageLoader.clearCache();
    clearEntityLogoCache();
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch {
      // ignore cookie cleanup error
    }
    try {
      webview.WebStorage.deleteAllData();
    } catch {
      // ignore web domStorage cleanup error
    }
    this.routeStack = [];
    this.selectedTab = 'discover';
    this.authStage = this.serverUrl.length > 0 ? 'login' : 'connect';
  }

  onBackPress(): boolean {
    if (this.activePlayer) {
      if (this.activePlayer.isAudio) {
        this.miniMusic = this.activePlayer;
      }
      this.activePlayer = null;
      return true;
    }
    if (this.serverSwitchReturnStage.length > 0) {
      this.restoreFromServerSwitch();
      return true;
    }
    if (this.authStage === 'login') {
      this.authStage = 'connect';
      return true;
    }
    if (this.authStage === 'main') {
      if (this.currentRoute() === 'plugins' && (AppStorage.get<boolean>('mp_plugin_detail_open') ?? false)) {
        const curReq = AppStorage.get<number>('mp_plugin_detail_close_req') ?? 0;
        AppStorage.setOrCreate('mp_plugin_detail_close_req', curReq + 1);
        return true;
      }
      if (this.currentRoute() === 'files' && (AppStorage.get<boolean>('mp_file_can_navigate_up') ?? false)) {
        const curNav = AppStorage.get<number>('mp_file_navigate_up_req') ?? 0;
        AppStorage.setOrCreate('mp_file_navigate_up_req', curNav + 1);
        return true;
      }
      if (this.routeStack.length > 0) {
        this.popRoute();
        return true;
      }
    }
    return false;
  }

  private isWideLayout(): boolean {
    return this.breakpoint === 'md' || this.breakpoint === 'lg';
  }

  private diagSectionFromRoute(route: string): string {
    if (route === 'diag_check') { return 'check'; }
    if (route === 'diag_logs') { return 'logs'; }
    if (route === 'diag_words') { return 'words'; }
    if (route === 'diag_recognize') { return 'recognize'; }
    if (route === 'diag_network') { return 'network'; }
    return 'schedulers';
  }

  @Builder
  preservedTabsBuilder() {
    Tabs({ index: this.activeMainTabIndex(), controller: this.tabsController }) {
      TabContent() {
        HarmonyDiscoverPage({
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onOpenExplore: (src: string) => {
            this.exploreSource = src;
            this.switchTab('explore');
          },
          onOpenSearch: () => this.pushRoute('search'),
          onOpenLibrary: (libId: string, srv: string) => {
            this.activeLibraryId = libId;
            this.activeLibraryServer = srv;
            this.pushRoute('media_library');
          },
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
        })
      }

      TabContent() {
        HarmonyExplorePage({
          initialSource: this.exploreSource,
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onOpenSearch: () => this.pushRoute('search')
        })
      }

      TabContent() {
        HarmonySubscriptionsPage({
          showBack: false,
          initialMode: 'mine',
          onOpenSearch: () => this.pushRoute('search'),
          onOpenCalendar: () => this.pushRoute('calendar'),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onPlayServerItem: (itemId: string, server: string, title: string) => {
            this.playServerItemById(itemId, server, title);
          }
        })
      }

      TabContent() {
        HarmonyMoreHubPage({
          onSelectRoute: (routeId: string) => {
            if (routeId === 'media_library') {
              this.activeLibraryId = '';
              this.activeLibraryServer = '';
            }
            if (routeId === 'resources') {
              this.resourceSearchKeyword = '';
            }
            this.pushRoute(routeId);
          },
          onOpenSearch: () => this.pushRoute('search')
        })
      }

      TabContent() {
        HarmonyDashboardPage({
          userName: this.userName,
          serverUrl: this.serverUrl,
          onOpenShortcutRoute: (routeId: string) => this.pushRoute(routeId),
          onOpenSettings: () => this.pushRoute('settings'),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it)
        })
      }
    }
    .barHeight(0)
    .scrollable(false)
    .animationDuration(0)
    .width('100%')
    .height('100%')
  }

  @Builder
  subRouteOverlayBuilder() {
    Column() {
      if (this.currentRoute() === 'media_library') {
        HarmonyMediaServerLibraryPage({
          initialLibraryId: this.activeLibraryId,
          initialServerName: this.activeLibraryServer,
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onOpenPerson: (person: MpCastMember) => {
            this.selectedPerson = person;
            this.pushRoute('person');
          }
        })
      } else if (this.currentRoute() === 'search') {
        HarmonyGlobalSearchPage({
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onOpenPerson: (person: MpCastMember) => {
            this.selectedPerson = person;
            this.pushRoute('person');
          }
        })
      } else if (this.currentRoute() === 'mediaserver_detail' && this.selectedMedia) {
        HarmonyMediaServerDetailPage({
          item: this.selectedMedia,
          onBack: () => this.popRoute(),
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onOpenPerson: (person: MpCastMember) => {
            this.selectedPerson = person;
            this.pushRoute('person');
          },
          onSearchResource: (kw: string) => {
            this.resourceSearchKeyword = kw;
            this.pushRoute('resources');
          }
        })
      } else if (this.currentRoute() === 'detail' && this.selectedMedia) {
        HarmonyMediaDetailPage({
          item: this.selectedMedia,
          onBack: () => this.popRoute(),
          onSearchResource: (kw: string) => {
            this.resourceSearchKeyword = kw;
            this.pushRoute('resources');
          },
          onOpenPerson: (person: MpCastMember) => {
            this.selectedPerson = person;
            this.pushRoute('person');
          },
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
        })
      } else if (this.currentRoute() === 'person' && this.selectedPerson) {
        HarmonyPersonDetailPage({
          person: this.selectedPerson,
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it)
        })
      } else if (this.currentRoute() === 'calendar' || this.currentRoute() === 'subscribe_square') {
        HarmonySubscriptionsPage({
          showBack: true,
          initialTitle: this.currentRoute() === 'calendar' ? '追剧日历' : '订阅广场',
          initialMode: this.currentRoute() === 'calendar' ? 'calendar' : 'square',
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onPlayServerItem: (itemId: string, server: string, title: string) => {
            this.playServerItemById(itemId, server, title);
          }
        })
      } else if (this.currentRoute() === 'resources') {
        HarmonyResourceSearchPage({
          initialKeyword: this.resourceSearchKeyword,
          onBack: () => this.popRoute()
        })
      } else if (this.currentRoute() === 'downloads') {
        HarmonyDownloadsPage({ onBack: () => this.popRoute() })
      } else if (this.currentRoute() === 'files' || this.currentRoute() === 'history') {
        HarmonyLibraryPage({
          initialMode: this.currentRoute(),
          onBack: () => this.popRoute(),
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
        })
      } else if (this.currentRoute() === 'workflows') {
        HarmonyWorkflowCanvasPage({ onBack: () => this.popRoute() })
      } else if (this.currentRoute() === 'sites') {
        HarmonySitesPage({ onBack: () => this.popRoute() })
      } else if (this.currentRoute().startsWith('diag_') || this.currentRoute() === 'diagnostics') {
        HarmonyDiagnosticsPage({
          initialSection: this.diagSectionFromRoute(this.currentRoute()),
          onBack: () => this.popRoute()
        })
      } else if (this.currentRoute() === 'agent') {
        HarmonyAgentChatPage({ onBack: () => this.popRoute() })
      } else if (this.currentRoute() === 'plugins') {
        HarmonyPluginsPage({
          serverUrl: this.serverUrl,
          userName: this.userName,
          userAvatar: this.userAvatar,
          isSuperuser: this.isSuperuser,
          onBack: () => this.popRoute()
        })
      } else {
        HarmonySettingsHubPage({
          serverUrl: this.serverUrl,
          userName: this.userName,
          onBack: () => this.popRoute(),
          onOpenSites: () => this.pushRoute('sites'),
          onSwitchServer: () => {
            this.serverSwitchReturnStage = 'main';
          },
          onLogout: () => this.handleLogout(false)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HarmonyThemeColors.canvas(this.isDark, this.paletteId, this.pureBlack))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      CinematicAmbientGradient()

      if (this.hydratingSession) {
        Column() {
          LoadingProgress().width(34).height(34)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.authStage === 'connect' || this.serverSwitchReturnStage === 'main') {
        HarmonyServerConnectionPage({
          savedServers: this.savedServers,
          canGoBack: this.serverSwitchReturnStage.length > 0,
          onBack: () => this.restoreFromServerSwitch(),
          onConnectSuccess: (url: string, selfSigned: boolean) => {
            const existing = this.savedServers.find((s: SavedServerEntry) => s.url === url);
            const entry: SavedServerEntry = {
              id: url,
              name: url.replace(/^https?:\/\//, '').split('/')[0],
              url: url,
              username: existing ? existing.username : '',
              lastUsedMs: Date.now(),
              allowSelfSigned: selfSigned
            };
            const nextList = [entry, ...this.savedServers.filter((s: SavedServerEntry) => s.url !== url)];
            this.savedServers = nextList;
            NativeHuksStore.shared().saveServersList(nextList).catch(() => {});
            this.commitConnectedServer(url, selfSigned);
          },
          onSelectSaved: (entry: SavedServerEntry) => {
            this.commitConnectedServer(entry.url, Boolean(entry.allowSelfSigned));
          },
          onDeleteSaved: (entry: SavedServerEntry) => {
            this.savedServers = this.savedServers.filter((s: SavedServerEntry) => s.url !== entry.url);
            NativeHuksStore.shared().removeSavedServer(entry.url).catch(() => {});
          }
        })
      } else if (this.authStage === 'login') {
        HarmonyLoginPage({
          serverUrl: this.serverUrl,
          onSwitchServer: () => {
            this.serverSwitchReturnStage = 'login';
            this.authStage = 'connect';
          },
          onLoginSuccess: (token: string, name: string, isSu: boolean, avatar: string, keepLogin: boolean) => {
            this.userName = name;
            this.isSuperuser = isSu;
            this.userAvatar = avatar;
            const sess: PersistedAuthSession = {
              serverUrl: this.serverUrl,
              token: token,
              userName: name,
              isSuperuser: isSu,
              userAvatar: avatar,
              keepLogin: keepLogin,
              allowSelfSigned: this.allowSelfSigned
            };
            NativeHuksStore.shared().saveActiveSession(sess).catch(() => {});
            const updatedServers = this.savedServers.map((s: SavedServerEntry): SavedServerEntry => {
              if (s.url === this.serverUrl) {
                return {
                  id: s.id,
                  name: s.name,
                  url: s.url,
                  username: name,
                  lastUsedMs: Date.now(),
                  allowSelfSigned: this.allowSelfSigned
                };
              }
              return s;
            });
            this.savedServers = updatedServers;
            NativeHuksStore.shared().saveServersList(updatedServers).catch(() => {});
            this.serverSwitchReturnStage = '';
            this.authStage = 'main';
            this.consumePendingIntents();
          }
        })
      } else if (this.isWideLayout()) {
        Row() {
          HarmonySideNavRail({
            selectedTab: this.selectedTab,
            userInitial: this.userName.substring(0, 1).toUpperCase(),
            userAvatar: this.userAvatar,
            onTabClick: (tab: HarmonyMainTab) => this.switchTab(tab),
            onSearchClick: () => this.pushRoute('search')
          })

          Stack({ alignContent: Alignment.Bottom }) {
            this.preservedTabsBuilder()

            if (this.routeStack.length > 0) {
              this.subRouteOverlayBuilder()
            }

            if (this.routeStack.length === 0 && this.showAiMascot) {
              FloatingAiMascotButton({
                miniMusicVisible: this.miniMusic !== null,
                baseRight: 22,
                baseBottom: Math.max(20, this.safeBottomVp + 10),
                onTap: () => this.pushRoute('agent')
              })
            }

            if (this.miniMusic && this.currentRoute() !== 'agent') {
              FloatingMiniMusicBar({
                request: this.miniMusic,
                isPlaying: this.audioIsPlaying,
                onTogglePlay: () => { HarmonyAudioSession.shared().togglePlayPause(); },
                onExpand: () => { this.activePlayer = this.miniMusic; },
                onClose: () => {
                  HarmonyAudioSession.shared().stopAndRelease();
                  this.miniMusic = null;
                }
              })
                .margin({ bottom: Math.max(12, this.safeBottomVp + 4) })
            }
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ right: this.safeRightVp })
          .expandSafeArea(
            [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
          )
        }
        .width('100%')
        .height('100%')
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
        )
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          this.preservedTabsBuilder()

          if (this.routeStack.length > 0) {
            this.subRouteOverlayBuilder()
          }

          if (this.routeStack.length === 0) {
            if (this.showAiMascot) {
              FloatingAiMascotButton({
                miniMusicVisible: this.miniMusic !== null,
                baseRight: 14,
                baseBottom: (this.windowHeightVp > 0 && this.windowHeightVp < 480 ? 68 : 76) + Math.max(10, this.safeBottomVp),
                onTap: () => this.pushRoute('agent')
              })
            }

            Column({ space: 8 }) {
              if (this.miniMusic) {
                FloatingMiniMusicBar({
                  request: this.miniMusic,
                  isPlaying: this.audioIsPlaying,
                  onTogglePlay: () => { HarmonyAudioSession.shared().togglePlayPause(); },
                  onExpand: () => { this.activePlayer = this.miniMusic; },
                  onClose: () => {
                    HarmonyAudioSession.shared().stopAndRelease();
                    this.miniMusic = null;
                  }
                })
              }
              HarmonyBottomNavBar({
                selectedTab: this.selectedTab,
                userInitial: this.userName.substring(0, 1).toUpperCase(),
                userAvatar: this.userAvatar,
                onTabClick: (tab: HarmonyMainTab) => this.switchTab(tab)
              })
            }
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.safeLeftVp, right: this.safeRightVp })
        .expandSafeArea(
          [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
          [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
        )
      }

      if (this.activePlayer) {
        NativeMediaPlayerView({
          request: this.activePlayer,
          isLandscape: this.windowWidthVp > this.windowHeightVp,
          onClose: () => { this.activePlayer = null; },
          onMinimizeToMiniBar: () => {
            this.miniMusic = this.activePlayer;
            this.activePlayer = null;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
    )
  }
}
