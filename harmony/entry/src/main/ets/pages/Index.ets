import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { connection } from '@kit.NetworkKit';
import {
  CinematicAmbientGradient,
  HarmonyBottomNavBar,
  HarmonySideNavRail,
  FloatingAiMascotButton,
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  HarmonyMainTab,
  HarmonySkeletonHost,
  HarmonySkeletonBlock,
  PlaybackPreferencesStore,
  mpPrimaryText,
  clearEntityLogoCache
} from '@moviepilot/design_system';
import {
  AudioStateListener,
  FloatingMiniMusicBar,
  HarmonyAudioSession,
  HarmonyPlaybackRequest,
  NativeMediaPlayerView,
  resolveLocalStrmFile,
  buildPlaybackRequestFromStreamInfo
} from '@moviepilot/media_player';
import {
  RustCoreBridge,
  NativeHuksStore,
  SavedServerEntry,
  PersistedAuthSession,
  MpImageLoader,
  MpMediaItem,
  MpCastMember,
  MpSeasonInfo,
  MoviePilotRepository,
  HarmonyUsageReporter
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
  HarmonyMediaSeasonDetailPage,
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
import {
  HarmonyGlobalVuePluginOverlay,
  HarmonyPluginCapsuleManager,
  HarmonyPluginFloatingCapsule
} from '@moviepilot/plugin_host';

import EntryAbility from '../entryability/EntryAbility';

const MAIN_TAB_ORDER: HarmonyMainTab[] = ['discover', 'subscribe', 'dashboard', 'more'];

/**
 * MoviePilot HarmonyOS NEXT / HarmonyOS 7 主入口页面：
 * - 启动时自动恢复 HUKS 安全凭据会话、已保存服务器与主题外观快照，401/令牌失效自动全局登出；
 * - 4 大主导航（发现 · 订阅 · 我的 · 更多）常驻挂载于隐藏标签栏的 `Tabs` 容器，搭配独立悬浮搜索圆钮，二级页面叠加于上方并保留滚动位置；
 * - 联动 `HarmonyAudioSession` 迷你音乐条无缝续播、可拖拽紫色机器人吉祥物避让及深度链接分发。
 */
@Entry
@Component
struct Index {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) @Watch('onDarkChanged') isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
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
  @State private userLevel: number = 1;
  @State private savedServers: SavedServerEntry[] = [];
  @State private selectedTab: HarmonyMainTab = 'discover';
  @State private routeStack: string[] = [];
  @State private exploreSource: string = 'tmdb_movies';
  @State private activeLibraryId: string = '';
  @State private activeLibraryServer: string = '';
  @State private resourceSearchKeyword: string = '';
  @State private subscribeHistoryType: string = '电影';
  @State private selectedMedia: MpMediaItem | null = null;
  @State private selectedSeasonSeries: MpMediaItem | null = null;
  @State private selectedSeasonInfo: MpSeasonInfo = {
    seasonNumber: 1, name: '第 1 季', episodeCount: 0, airDate: '', posterUrl: '', overview: ''
  };
  @State private selectedSeasonSeriesItemId: string = '';
  @State private selectedSeasonServer: string = '';
  @State private selectedPerson: MpCastMember | null = null;
  @State private activePlayer: HarmonyPlaybackRequest | null = null;
  @State private miniMusic: HarmonyPlaybackRequest | null = null;
  private tabsController: TabsController = new TabsController();
  private lastUsageLookupMs: number = 0;
  private audioSyncListener: AudioStateListener = () => {
    const sess = HarmonyAudioSession.shared();
    const cur = sess.currentRequest();
    if (cur && this.miniMusic) {
      this.miniMusic = cur;
    } else if (!cur && this.miniMusic && !this.activePlayer) {
      this.miniMusic = null;
    }
  };

  private onDarkChanged(): void {
    EntryAbility.syncWindowAppearance(this.isDark);
  }

  aboutToAppear(): void {
    HarmonyAudioSession.shared().subscribe(this.audioSyncListener);
    MoviePilotRepository.shared().setOnSessionExpired(() => {
      this.handleLogout(true);
    });
    this.bootstrapSessionAndAppearance();
  }

  aboutToDisappear(): void {
    HarmonyAudioSession.shared().unsubscribe(this.audioSyncListener);
  }

  onPageShow(): void {
    if (this.authStage === 'main' && this.isSuperuser) {
      this.triggerUsageReportIfAdmin(false);
    }
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
        this.userLevel = activeSess.userLevel ?? MoviePilotRepository.parseJwtLevel(activeSess.token) ?? 1;
        this.allowSelfSigned = activeSess.allowSelfSigned;
        const repo = MoviePilotRepository.shared();
        repo.configureServer(activeSess.serverUrl, activeSess.allowSelfSigned);
        repo.setAuthToken(activeSess.token);
        repo.userLevel = this.userLevel;
        repo.hydrateSession().catch(() => {});
        this.authStage = 'main';
        this.triggerUsageReportIfAdmin();
        this.consumePendingIntents();
      } else if (this.savedServers.length > 0) {
        this.serverUrl = this.savedServers[0].url;
        this.allowSelfSigned = Boolean(this.savedServers[0].allowSelfSigned);
      }
    } catch {
      // fallback to connect stage
    }
    this.hydratingSession = false;
    this.consumePendingIntents();
  }

  /** 仅在超级管理员会话下检查实例统计开关，若开启则异步执行 24 小时节流匿名版本上报；回前台时自动重试此前失败的上报。 */
  private triggerUsageReportIfAdmin(forceLookup: boolean = true): void {
    if (!this.isSuperuser) { return; }
    const nowMs = Date.now();
    if (!forceLookup && nowMs - this.lastUsageLookupMs < 60_000) { return; }
    this.lastUsageLookupMs = nowMs;
    MoviePilotRepository.shared().fetchUsageReportingConfig().then((cfg) => {
      if (cfg && cfg.enabled) {
        HarmonyUsageReporter.shared().report(true, cfg.serverHost).catch(() => {});
      }
    }).catch(() => {});
  }

  onPendingDeepLinkChanged(): void {
    this.consumePendingIntents();
  }

  onPendingMediaUriChanged(): void {
    this.consumePendingIntents();
  }

  private static normalizeServerOrigin(rawUrl: string): string {
    const trimmed = rawUrl.trim().replace(/\/+$/, '');
    if (trimmed.length === 0) { return ''; }
    return trimmed
      .replace(/^HTTPS:\/\//i, 'https://')
      .replace(/^HTTP:\/\//i, 'http://')
      .replace(/^(https:\/\/[^/:]+):443(?=\/|$)/i, '$1')
      .replace(/^(http:\/\/[^/:]+):80(?=\/|$)/i, '$1')
      .toLowerCase();
  }

  private consumePendingIntents(): void {
    // 1. 外部文件关联（want.uri）无需登录会话即可直接本地播放
    const rawMedia = AppStorage.get<string>('mp_pending_media_uri') ?? '';
    if (rawMedia.length > 0) {
      AppStorage.setOrCreate('mp_pending_media_uri', '');
      const kind = RustCoreBridge.detectPlayableMediaKind(rawMedia, true);
      const rawName = rawMedia.substring(rawMedia.lastIndexOf('/') + 1);
      let title = '本地媒体';
      try {
        title = decodeURIComponent(rawName) || '本地媒体';
      } catch {
        title = rawName || '本地媒体';
      }
      const isLocalUri = rawMedia.startsWith('file://') || rawMedia.startsWith('/');
      this.playMedia({
        url: rawMedia,
        fdPath: isLocalUri ? rawMedia : undefined,
        title: title,
        subtitle: isLocalUri ? '本地媒体文件' : '外部直链媒体',
        isAudio: kind === 'audio',
        isSessionBound: false
      });
    }

    const rawDl = AppStorage.get<string>('mp_pending_deeplink') ?? '';
    if (rawDl.length === 0) {
      return;
    }

    // 2. 公开直链播放（moviepilot://play?url=...）不依赖实例登录态
    try {
      const peek = JSON.parse(rawDl) as Record<string, Object>;
      if (String(peek['kind'] ?? '') === 'playDirect') {
        AppStorage.setOrCreate('mp_pending_deeplink', '');
        AppStorage.setOrCreate('mp_pending_deeplink_origin', '');
        this.applyDeepLinkJson(rawDl);
        return;
      }
    } catch {
      // fall through
    }

    if (this.authStage !== 'main') {
      return;
    }

    const rawOrigin = AppStorage.get<string>('mp_pending_deeplink_origin') ?? '';
    AppStorage.setOrCreate('mp_pending_deeplink', '');
    AppStorage.setOrCreate('mp_pending_deeplink_origin', '');
    if (rawOrigin.length > 0) {
      const expected = Index.normalizeServerOrigin(rawOrigin);
      const current = Index.normalizeServerOrigin(this.serverUrl);
      if (expected.length === 0 || expected !== current) {
        return;
      }
    }
    if (this.serverSwitchReturnStage === 'main') {
      this.serverSwitchReturnStage = '';
    }
    this.applyDeepLinkJson(rawDl);
  }

  private applyDeepLinkJson(rawJson: string): void {
    try {
      const obj = JSON.parse(rawJson) as Record<string, Object>;
      const kind = String(obj['kind'] ?? 'discover');
      if (kind === 'discover') {
        this.switchTab('discover');
      } else if (kind === 'explore') {
        const src = String(obj['source'] ?? '');
        if (src.length > 0) {
          this.exploreSource = src;
        }
        this.routeStack = ['explore'];
      } else if (kind === 'subscriptions') {
        this.switchTab('subscribe');
      } else if (kind === 'subscribeCommunity') {
        this.routeStack = ['subscribe_square'];
      } else if (kind === 'calendar') {
        this.routeStack = ['calendar'];
      } else if (kind === 'dashboard') {
        this.routeStack = [];
        this.switchTab('dashboard');
      } else if (kind === 'messages') {
        this.routeStack = [];
        this.switchTab('dashboard');
        const nextRev = (AppStorage.get<number>('mp_open_messages_revision') ?? 0) + 1;
        AppStorage.setOrCreate('mp_open_messages_revision', nextRev);
      } else if (kind === 'search') {
        this.routeStack = ['search'];
      } else if (kind === 'resources') {
        this.resourceSearchKeyword = String(obj['keyword'] ?? obj['query'] ?? '');
        this.routeStack = ['resources'];
      } else if (kind === 'downloads') {
        this.routeStack = ['downloads'];
      } else if (kind === 'files') {
        this.routeStack = ['files'];
      } else if (kind === 'history') {
        this.routeStack = ['history'];
      } else if (kind === 'workflows') {
        this.routeStack = ['workflows'];
      } else if (kind === 'sites') {
        this.routeStack = ['sites'];
      } else if (kind === 'plugins') {
        this.routeStack = ['plugins'];
      } else if (kind === 'pluginDetail') {
        const pid = String(obj['plugin_id'] ?? '').trim();
        const surf = String(obj['surface'] ?? '').toLowerCase() === 'config' ? 'config' : 'dataPage';
        if (pid.length > 0) {
          this.routeStack = ['plugins'];
          MoviePilotRepository.shared().fetchPlugins('installed').then((list) => {
            const found = list.find((p) => p.id.toLowerCase() === pid.toLowerCase());
            if (found && found.renderMode.toLowerCase() === 'vue') {
              HarmonyPluginCapsuleManager.shared().openPlugin(found.id, found.pluginName, surf, found.hasPage, found.iconUrl ?? '');
            } else {
              AppStorage.setOrCreate('mp_pending_open_plugin_id', `${pid}|${surf}`);
            }
          }).catch(() => {
            AppStorage.setOrCreate('mp_pending_open_plugin_id', `${pid}|${surf}`);
          });
        }
      } else if (kind === 'agent') {
        this.routeStack = ['agent'];
      } else if (kind === 'music') {
        this.exploreSource = 'music';
        this.routeStack = ['explore'];
      } else if (kind === 'playbackSettings') {
        AppStorage.setOrCreate('mp_open_settings_sheet', 'playback');
        this.routeStack = ['settings'];
      } else if (kind === 'appearance') {
        AppStorage.setOrCreate('mp_open_settings_sheet', 'appearance');
        this.routeStack = ['settings'];
      } else if (kind === 'users') {
        AppStorage.setOrCreate('mp_open_settings_sheet', 'users');
        this.routeStack = ['settings'];
      } else if (kind === 'settings' || kind === 'systemSettings') {
        this.routeStack = ['settings'];
      } else if (kind === 'playDirect') {
        const directUrl = String(obj['direct_url'] ?? '').trim();
        if (directUrl.length > 0) {
          const rawTitle = obj['title'] !== null && obj['title'] !== undefined ? String(obj['title']).trim() : '';
          const mediaKind = String(obj['media_kind'] ?? 'video');
          this.playMedia({
            url: directUrl,
            title: rawTitle.length > 0 ? rawTitle : '外部直链媒体',
            subtitle: '外部直链媒体',
            isAudio: mediaKind === 'audio',
            isSessionBound: false
          });
        }
      } else if (kind === 'playMediaServerItem') {
        const itemId = String(obj['item_id'] ?? '').trim();
        const server = obj['server'] !== null && obj['server'] !== undefined ? String(obj['server']).trim() : '';
        if (itemId.length > 0) {
          this.playServerItemById(itemId, server, '媒体库播放');
        }
      } else if (kind === 'playStorageFile') {
        const storage = String(obj['storage'] ?? 'local').trim() || 'local';
        const filePath = String(obj['path'] ?? '').trim();
        if (filePath.length > 0) {
          this.playStorageFileByPath(storage, filePath, '');
        }
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

  private isOnCellularNetwork(): boolean {
    try {
      const net = connection.getDefaultNetSync();
      const caps = connection.getNetCapabilitiesSync(net);
      if (caps && Array.isArray(caps.bearerTypes)) {
        const hasCellular = caps.bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR);
        const hasWifiOrEth = caps.bearerTypes.includes(connection.NetBearType.BEARER_WIFI) ||
          caps.bearerTypes.includes(connection.NetBearType.BEARER_ETHERNET);
        return hasCellular && !hasWifiOrEth;
      }
    } catch {
      // ignore when network capability query is restricted
    }
    return false;
  }

  private commitPlayMedia(req: HarmonyPlaybackRequest): void {
    this.activePlayer = req;
    if (req.isAudio) {
      this.miniMusic = req;
    }
  }

  private playMedia(req: HarmonyPlaybackRequest): void {
    const isRemoteHttp = (req.fdPath ?? '').trim().length === 0 && /^https?:\/\//i.test(req.url.trim());
    if (isRemoteHttp && PlaybackPreferencesStore.getCellularWarn() && this.isOnCellularNetwork()) {
      try {
        this.getUIContext().showAlertDialog({
          title: '移动网络播放提醒',
          message: '当前正使用移动数据网络，在线播放音视频可能消耗较多流量，是否继续播放？',
          autoCancel: true,
          primaryButton: {
            value: '取消',
            action: () => {}
          },
          secondaryButton: {
            value: '继续播放',
            fontColor: this.accentHex,
            action: () => {
              this.commitPlayMedia(req);
            }
          }
        });
        return;
      } catch {
        // fallback directly if dialog context unavailable
      }
    }
    this.commitPlayMedia(req);
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
        this.playMedia(buildPlaybackRequestFromStreamInfo(
          info,
          fallbackTitle,
          server || '媒体库播放'
        ));
      }
    } catch {
      // ignore stream lookup error
    }
  }

  private async playStorageFileByPath(storage: string, filePath: string, fallbackTitle: string): Promise<void> {
    const cleanPath = filePath.trim();
    const cleanStorage = (storage || 'local').trim();
    if (!cleanPath) {
      return;
    }
    const fileName = cleanPath.substring(cleanPath.lastIndexOf('/') + 1) || fallbackTitle || '存储媒体';
    const displayTitle = fallbackTitle.trim().length > 0 ? fallbackTitle : fileName;
    const kind = RustCoreBridge.detectPlayableMediaKind(fileName.includes('.') ? fileName : cleanPath) || 'video';
    const repo = MoviePilotRepository.shared();

    try {
      const isStrm = RustCoreBridge.isStrmPath(fileName) || RustCoreBridge.isStrmPath(cleanPath);
      const shouldTryTicket = cleanStorage === 'local' || !isStrm;
      if (shouldTryTicket) {
        const ticketId = await repo.createStorageStreamTicket(cleanStorage, cleanPath, fileName, kind === 'audio' ? 'audio' : 'video');
        if (ticketId.length > 0) {
          const stream = await repo.fetchVideoStreamInfo(ticketId, '');
          if (stream && stream.contentUrl.length > 0) {
            this.playMedia(buildPlaybackRequestFromStreamInfo(stream, displayTitle, cleanStorage));
            return;
          }
        }
      }

      // 严禁对真实音视频文件回退 storage/download 整文件下载，仅允许远端轻量 .strm 指针文件解析直链
      if (!isStrm) {
        return;
      }

      const dotIdx = fileName.lastIndexOf('.');
      const ext = dotIdx >= 0 ? fileName.substring(dotIdx) : '';
      const hostCtx = this.getUIContext().getHostContext();
      const cacheDir = hostCtx ? hostCtx.cacheDir : '';
      if (!cacheDir) {
        return;
      }
      const cachedPath = await repo.downloadStorageFileToCache(cleanStorage, cleanPath, fileName, ext, cacheDir);
      if (cachedPath.length > 0) {
        const strmSpec = resolveLocalStrmFile(cachedPath, true);
        if (strmSpec) {
          this.playMedia({
            url: strmSpec.url,
            headers: strmSpec.headers,
            title: displayTitle.replace(/\.strm$/i, '') || displayTitle,
            subtitle: cleanStorage,
            isAudio: strmSpec.mediaKind === 'audio',
            isSessionBound: false
          });
        }
      }
    } catch {
      // ignore storage playback lookup error
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
      HarmonyPluginCapsuleManager.shared().closeAndDestroy();
      if (HarmonyAudioSession.shared().stopIfSessionBound()) {
        this.miniMusic = null;
      }
      if (this.activePlayer && this.activePlayer.isSessionBound !== false) {
        this.activePlayer = null;
      }
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
    HarmonyPluginCapsuleManager.shared().closeAndDestroy();
    if (HarmonyAudioSession.shared().stopIfSessionBound()) {
      this.miniMusic = null;
    }
    if (this.activePlayer && this.activePlayer.isSessionBound !== false) {
      this.activePlayer = null;
    }
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

  private dismissAudioPlayerRespectingPreference(): void {
    if (PlaybackPreferencesStore.getKeepMiniBar()) {
      this.miniMusic = HarmonyAudioSession.shared().currentRequest() ?? this.activePlayer;
    } else {
      HarmonyAudioSession.shared().stopAndRelease();
      this.miniMusic = null;
    }
    this.activePlayer = null;
  }

  onBackPress(): boolean {
    if (this.activePlayer) {
      if (this.activePlayer.isAudio) {
        this.dismissAudioPlayerRespectingPreference();
      } else {
        this.activePlayer = null;
      }
      return true;
    }
    if (this.authStage === 'main' && HarmonyPluginCapsuleManager.shared().handleSystemBackPress()) {
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
            this.pushRoute('explore');
          },
          onOpenLibrary: (libId: string, srv: string) => {
            this.activeLibraryId = libId;
            this.activeLibraryServer = srv;
            this.pushRoute('media_library');
          },
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
        })
      }

      TabContent() {
        HarmonySubscriptionsPage({
          showBack: false,
          initialMode: 'mine',
          onOpenCalendar: () => {
            this.pushRoute('calendar');
          },
          onOpenSquare: () => {
            this.pushRoute('subscribe_square');
          },
          onOpenHistory: (mtype: string) => {
            this.subscribeHistoryType = mtype;
            this.pushRoute('subscribe_history');
          },
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onPlayServerItem: (itemId: string, server: string, title: string) => {
            this.playServerItemById(itemId, server, title);
          },
          onPlayStorageFile: (storage: string, filePath: string, title: string) => {
            this.playStorageFileByPath(storage, filePath, title);
          }
        })
      }

      TabContent() {
        HarmonyDashboardPage({
          userName: this.userName,
          userAvatar: this.userAvatar,
          isSuperuser: this.isSuperuser,
          userLevel: this.userLevel,
          serverUrl: this.serverUrl,
          onOpenShortcutRoute: (routeId: string) => this.pushRoute(routeId),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it)
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
          }
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
      } else if (this.currentRoute() === 'explore') {
        HarmonyExplorePage({
          initialSource: this.exploreSource,
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
        })
      } else if (this.currentRoute() === 'search') {
        HarmonyGlobalSearchPage({
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onOpenPerson: (person: MpCastMember) => {
            this.selectedPerson = person;
            this.pushRoute('person');
          },
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
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
          onOpenSeasonDetail: (series: MpMediaItem, season: MpSeasonInfo, seriesItemId: string, srv: string) => {
            this.selectedSeasonSeries = series;
            this.selectedSeasonInfo = season;
            this.selectedSeasonSeriesItemId = seriesItemId;
            this.selectedSeasonServer = srv;
            this.pushRoute('season_detail');
          },
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
        })
      } else if (this.currentRoute() === 'season_detail' && this.selectedSeasonSeries) {
        HarmonyMediaSeasonDetailPage({
          seriesItem: this.selectedSeasonSeries,
          initialSeason: this.selectedSeasonInfo,
          initialSeriesItemId: this.selectedSeasonSeriesItemId,
          initialServer: this.selectedSeasonServer,
          onBack: () => this.popRoute(),
          onSearchResource: (kw: string) => {
            this.resourceSearchKeyword = kw;
            this.pushRoute('resources');
          },
          onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
        })
      } else if (this.currentRoute() === 'person' && this.selectedPerson) {
        HarmonyPersonDetailPage({
          person: this.selectedPerson,
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it)
        })
      } else if (
        this.currentRoute() === 'calendar' ||
        this.currentRoute() === 'subscribe_square' ||
        this.currentRoute() === 'subscribe_history'
      ) {
        HarmonySubscriptionsPage({
          showBack: true,
          initialTitle: this.currentRoute() === 'calendar'
            ? '追剧日历'
            : (this.currentRoute() === 'subscribe_square' ? '订阅广场' : '订阅历史'),
          initialMode: this.currentRoute() === 'calendar'
            ? 'calendar'
            : (this.currentRoute() === 'subscribe_square' ? 'square' : 'history'),
          initialHistoryType: this.subscribeHistoryType,
          onBack: () => this.popRoute(),
          onOpenMedia: (it: MpMediaItem) => this.openMediaSmart(it),
          onPlayServerItem: (itemId: string, server: string, title: string) => {
            this.playServerItemById(itemId, server, title);
          },
          onPlayStorageFile: (storage: string, filePath: string, title: string) => {
            this.playStorageFileByPath(storage, filePath, title);
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
          isSuperuser: this.isSuperuser,
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
        HarmonySkeletonHost({ loadingLabel: '正在恢复 MoviePilot 会话', fillHeight: true }) {
          Column({ space: 14 }) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(68)
                .height(68)
                .borderRadius(20)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '32' : '1E'))
                .border({
                  width: 1,
                  color: HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '66' : '40'),
                  radius: 20
                })
                .shadow({
                  radius: 20,
                  color: HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '44' : '22'),
                  offsetY: 6
                })
              SymbolGlyph($r('sys.symbol.TV_tv_fill'))
                .fontSize(30)
                .fontColor([this.accentHex])
            }

            Text('MoviePilot')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))

            Column({ space: 7 }) {
              HarmonySkeletonBlock({
                blockWidth: 136,
                blockHeight: 10,
                cornerRadius: 5,
                shimmerSweep: true
              })
              HarmonySkeletonBlock({
                blockWidth: 88,
                blockHeight: 8,
                cornerRadius: 4,
                tone: 'subtle'
              })
            }
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
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
          onLoginSuccess: (token: string, name: string, isSu: boolean, avatar: string, keepLogin: boolean, userLv?: number) => {
            const resolvedLevel = userLv ?? MoviePilotRepository.parseJwtLevel(token) ?? 1;
            this.userName = name;
            this.isSuperuser = isSu;
            this.userAvatar = avatar;
            this.userLevel = resolvedLevel;
            const sess: PersistedAuthSession = {
              serverUrl: this.serverUrl,
              token: token,
              userName: name,
              isSuperuser: isSu,
              userAvatar: avatar,
              keepLogin: keepLogin,
              allowSelfSigned: this.allowSelfSigned,
              userLevel: resolvedLevel
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
            this.triggerUsageReportIfAdmin();
            this.consumePendingIntents();
          }
        })
      } else if (this.isWideLayout()) {
        Row() {
          HarmonySideNavRail({
            selectedTab: this.selectedTab,
            userInitial: this.userName.substring(0, 1).toUpperCase(),
            userAvatar: MoviePilotRepository.shared().resolveImageUrl(this.userAvatar),
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
                baseBottom: (this.windowHeightVp > 0 && this.windowHeightVp < 480 ? 70 : 80) + Math.max(10, this.safeBottomVp),
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
                userAvatar: MoviePilotRepository.shared().resolveImageUrl(this.userAvatar),
                onTabClick: (tab: HarmonyMainTab) => this.switchTab(tab),
                onSearchClick: () => this.pushRoute('search')
              })
            }
          } else if (this.miniMusic && this.currentRoute() !== 'agent') {
            FloatingMiniMusicBar({
              request: this.miniMusic,
              isPlaying: this.audioIsPlaying,
              onTogglePlay: () => { HarmonyAudioSession.shared().togglePlayPause(); },
              onExpand: () => { this.activePlayer = HarmonyAudioSession.shared().currentRequest() ?? this.miniMusic; },
              onClose: () => {
                HarmonyAudioSession.shared().stopAndRelease();
                this.miniMusic = null;
              }
            })
              .margin({ bottom: Math.max(12, this.safeBottomVp + 6) })
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

      if (!this.hydratingSession && this.authStage !== 'main' && this.miniMusic && !this.activePlayer) {
        FloatingMiniMusicBar({
          request: this.miniMusic,
          isPlaying: this.audioIsPlaying,
          onTogglePlay: () => { HarmonyAudioSession.shared().togglePlayPause(); },
          onExpand: () => { this.activePlayer = HarmonyAudioSession.shared().currentRequest() ?? this.miniMusic; },
          onClose: () => {
            HarmonyAudioSession.shared().stopAndRelease();
            this.miniMusic = null;
          }
        })
          .margin({ bottom: Math.max(16, this.safeBottomVp + 8) })
      }

      if (!this.hydratingSession && this.authStage === 'main' && !this.activePlayer) {
        HarmonyPluginFloatingCapsule({
          bottomClearanceVp: (this.routeStack.length === 0 && !this.isWideLayout() ? 94 : 24)
        })

        HarmonyGlobalVuePluginOverlay({
          serverUrl: this.serverUrl,
          authToken: MoviePilotRepository.shared().token,
          userName: this.userName,
          userAvatar: this.userAvatar,
          isSuperuser: this.isSuperuser,
          onFallbackToLegacy: (_pid: string, _surf: string) => {
            this.routeStack = ['plugins'];
          }
        })
      }

      if (this.activePlayer) {
        NativeMediaPlayerView({
          request: this.activePlayer,
          isLandscape: this.windowWidthVp > this.windowHeightVp,
          onClose: () => { this.activePlayer = null; },
          onMinimizeToMiniBar: () => {
            this.dismissAudioPlayerRespectingPreference();
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
