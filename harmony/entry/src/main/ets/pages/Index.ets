import {
  CinematicAmbientGradient,
  HarmonyBottomNavBar,
  HarmonySideNavRail,
  FloatingAiMascotButton,
  HarmonyAppearanceStore,
  HarmonyMainTab
} from '@moviepilot/design_system';
import {
  FloatingMiniMusicBar,
  HarmonyPlaybackRequest,
  NativeMediaPlayerView
} from '@moviepilot/media_player';
import {
  SavedServerEntry,
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
import { HarmonyMediaDetailPage, HarmonyPersonDetailPage } from '@moviepilot/media';
import { HarmonySubscriptionsPage } from '@moviepilot/subscribe';
import { HarmonyResourceSearchPage, HarmonyDownloadsPage } from '@moviepilot/download';
import { HarmonyLibraryPage } from '@moviepilot/library';
import { HarmonyDashboardPage, HarmonyDiagnosticsPage, HarmonyMoreHubPage } from '@moviepilot/dashboard';
import { HarmonyWorkflowCanvasPage, HarmonySitesPage } from '@moviepilot/automation';
import { HarmonyAgentChatPage } from '@moviepilot/agent';
import { HarmonySettingsHubPage, HarmonyPluginsPage } from '@moviepilot/settings';

import EntryAbility from '../entryability/EntryAbility';

/**
 * MoviePilot HarmonyOS NEXT / HarmonyOS 7 主入口页面：
 * - 手机端采用底部悬浮一体式动态光感导航栏（发现 · 探索 · 订阅 · 更多 · 我的），折叠屏展开/平板自动切换左侧导航栏；
 * - 完整路由栈支持全部一级/二级业务页、独立媒体库浏览与 6 项独立单用途系统诊断页；
 * - HarmonyOS 7 自动启用 `uiMaterial.ImmersiveMaterial` 动态光感，低版本系统平滑自动回退。
 */
@Entry
@Component
struct Index {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) @Watch('onDarkChanged') isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_BREAKPOINT) breakpoint: string = 'sm';

  private onDarkChanged(): void {
    EntryAbility.syncWindowAppearance(this.isDark);
  }
  @State private authStage: string = 'connect'; // 'connect' | 'login' | 'main'
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
  @State private miniPlaying: boolean = true;

  private currentRoute(): string {
    return this.routeStack.length > 0 ? this.routeStack[this.routeStack.length - 1] : 'tab';
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
  }

  private playMedia(req: HarmonyPlaybackRequest): void {
    this.activePlayer = req;
    if (req.isAudio) {
      this.miniMusic = req;
      this.miniPlaying = true;
    }
  }

  private handleLogout(): void {
    MoviePilotRepository.shared().clearSession();
    this.authStage = 'login';
    this.routeStack = [];
    this.selectedTab = 'discover';
  }

  onBackPress(): boolean {
    if (this.activePlayer) {
      if (this.activePlayer.isAudio) {
        this.miniMusic = this.activePlayer;
      }
      this.activePlayer = null;
      return true;
    }
    if (this.routeStack.length > 0) {
      this.popRoute();
      return true;
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
  mainContentBuilder() {
    if (this.currentRoute() === 'tab') {
      if (this.selectedTab === 'discover') {
        HarmonyDiscoverPage({
          onOpenMedia: (it: MpMediaItem) => {
            this.selectedMedia = it;
            this.pushRoute('detail');
          },
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
      } else if (this.selectedTab === 'explore') {
        HarmonyExplorePage({
          initialSource: this.exploreSource,
          onOpenMedia: (it: MpMediaItem) => {
            this.selectedMedia = it;
            this.pushRoute('detail');
          },
          onOpenSearch: () => this.pushRoute('search')
        })
      } else if (this.selectedTab === 'subscribe') {
        HarmonySubscriptionsPage({
          showBack: false,
          initialMode: 'mine',
          onOpenSearch: () => this.pushRoute('search'),
          onOpenCalendar: () => this.pushRoute('calendar'),
          onOpenMedia: (it: MpMediaItem) => {
            this.selectedMedia = it;
            this.pushRoute('detail');
          }
        })
      } else if (this.selectedTab === 'more') {
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
      } else {
        HarmonyDashboardPage({
          userName: this.userName,
          serverUrl: this.serverUrl,
          onOpenShortcutRoute: (routeId: string) => this.pushRoute(routeId),
          onOpenSettings: () => this.pushRoute('settings'),
          onOpenMedia: (it: MpMediaItem) => {
            this.selectedMedia = it;
            this.pushRoute('detail');
          }
        })
      }
    } else if (this.currentRoute() === 'media_library') {
      HarmonyMediaServerLibraryPage({
        initialLibraryId: this.activeLibraryId,
        initialServerName: this.activeLibraryServer,
        onBack: () => this.popRoute(),
        onOpenMedia: (it: MpMediaItem) => {
          this.selectedMedia = it;
          this.pushRoute('detail');
        }
      })
    } else if (this.currentRoute() === 'search') {
      HarmonyGlobalSearchPage({
        onBack: () => this.popRoute(),
        onOpenMedia: (it: MpMediaItem) => {
          this.selectedMedia = it;
          this.pushRoute('detail');
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
        onOpenMedia: (it: MpMediaItem) => {
          this.selectedMedia = it;
          this.pushRoute('detail');
        }
      })
    } else if (this.currentRoute() === 'calendar' || this.currentRoute() === 'subscribe_square') {
      HarmonySubscriptionsPage({
        showBack: true,
        initialTitle: this.currentRoute() === 'calendar' ? '追剧日历' : '订阅广场',
        initialMode: this.currentRoute() === 'calendar' ? 'calendar' : 'square',
        onBack: () => this.popRoute(),
        onOpenMedia: (it: MpMediaItem) => {
          this.selectedMedia = it;
          this.pushRoute('detail');
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
        onLogout: () => this.handleLogout()
      })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      CinematicAmbientGradient()

      if (this.authStage === 'connect') {
        HarmonyServerConnectionPage({
          savedServers: this.savedServers,
          onConnectSuccess: (url: string) => {
            this.serverUrl = url;
            const entry: SavedServerEntry = {
              id: url,
              name: url.replace(/^https?:\/\//, '').split('/')[0],
              url: url,
              username: '',
              lastUsedMs: Date.now()
            };
            this.savedServers = [entry, ...this.savedServers.filter((s: SavedServerEntry) => s.url !== url)];
            this.authStage = 'login';
          },
          onSelectSaved: (entry: SavedServerEntry) => {
            this.serverUrl = entry.url;
            this.authStage = 'login';
          }
        })
      } else if (this.authStage === 'login') {
        HarmonyLoginPage({
          serverUrl: this.serverUrl,
          onSwitchServer: () => { this.authStage = 'connect'; },
          onLoginSuccess: (_token: string, name: string, isSu: boolean, avatar: string) => {
            this.userName = name;
            this.isSuperuser = isSu;
            this.userAvatar = avatar;
            this.authStage = 'main';
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
            this.mainContentBuilder()

            if (this.routeStack.length === 0) {
              FloatingAiMascotButton({
                onTap: () => this.pushRoute('agent')
              })
                .position({ right: 22, bottom: 26 })
            }

            if (this.miniMusic && this.currentRoute() !== 'agent') {
              FloatingMiniMusicBar({
                request: this.miniMusic,
                isPlaying: this.miniPlaying,
                onTogglePlay: () => { this.miniPlaying = !this.miniPlaying; },
                onExpand: () => { this.activePlayer = this.miniMusic; },
                onClose: () => { this.miniMusic = null; }
              })
                .margin({ bottom: 18 })
            }
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height('100%')
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          this.mainContentBuilder()

          if (this.routeStack.length === 0) {
            FloatingAiMascotButton({
              onTap: () => this.pushRoute('agent')
            })
              .position({ right: 16, bottom: 96 })

            Column({ space: 8 }) {
              if (this.miniMusic) {
                FloatingMiniMusicBar({
                  request: this.miniMusic,
                  isPlaying: this.miniPlaying,
                  onTogglePlay: () => { this.miniPlaying = !this.miniPlaying; },
                  onExpand: () => { this.activePlayer = this.miniMusic; },
                  onClose: () => { this.miniMusic = null; }
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      }

      if (this.activePlayer) {
        NativeMediaPlayerView({
          request: this.activePlayer,
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
