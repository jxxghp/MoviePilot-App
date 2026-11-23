import {
  CinematicAmbientGradient,
  FloatingFourPlusOneNavBar,
  FloatingOverflowMenuCard,
  HarmonyMainTab
} from '../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import {
  FloatingMiniMusicBar,
  HarmonyPlaybackRequest,
  NativeMediaPlayerView
} from '../../../commons/media_player/src/main/ets/NativeMediaPlayerView';
import { HarmonyServerConnectionPage, HarmonyLoginPage } from '../../../features/auth/src/main/ets/AuthPages';
import { HarmonyDiscoverPage, HarmonyExplorePage, HarmonyGlobalSearchPage, HarmonyMediaItem } from '../../../features/discover/src/main/ets/DiscoverPages';
import { HarmonyMediaDetailPage } from '../../../features/media/src/main/ets/MediaDetailPage';
import { HarmonySubscriptionsPage } from '../../../features/subscribe/src/main/ets/SubscribePages';
import { HarmonyResourceSearchPage, HarmonyDownloadsPage } from '../../../features/download/src/main/ets/DownloadPages';
import { HarmonyLibraryPage } from '../../../features/library/src/main/ets/LibraryPages';
import { HarmonyDashboardPage, HarmonyDiagnosticsPage } from '../../../features/dashboard/src/main/ets/DashboardPages';
import { HarmonyWorkflowCanvasPage, HarmonySitesPage } from '../../../features/automation/src/main/ets/AutomationPages';
import { HarmonyAgentChatPage } from '../../../features/agent/src/main/ets/AgentChatPage';
import { HarmonySettingsHubPage } from '../../../features/settings/src/main/ets/SettingsPages';
import { SavedServerEntry } from '../../../commons/core_rust_bridge/src/main/ets/security/NativeHuksStore';

/**
 * MoviePilot HarmonyOS NEXT 主入口页面：
 * 串联认证状态机、全屏流光背景、4+1 流体动态光感底栏、8 项快捷菜单、
 * 10 大业务模块、自由拖动 AI 悬浮机器人、迷你音乐条与全屏原生播放器。
 */
@Entry
@Component
struct Index {
  @State private authStage: string = 'connect'; // 'connect' | 'login' | 'main'
  @State private serverUrl: string = '';
  @State private userName: string = 'admin';
  @State private isSuperuser: boolean = true;
  @State private savedServers: SavedServerEntry[] = [];
  @State private selectedTab: HarmonyMainTab = 'discover';
  @State private activeRoute: string = 'tab';
  @State private showOverflowMenu: boolean = false;
  @State private selectedMedia: HarmonyMediaItem | null = null;
  @State private activePlayer: HarmonyPlaybackRequest | null = null;
  @State private miniMusic: HarmonyPlaybackRequest | null = null;
  @State private miniPlaying: boolean = true;

  private playMedia(req: HarmonyPlaybackRequest): void {
    this.activePlayer = req;
    if (req.isAudio) {
      this.miniMusic = req;
      this.miniPlaying = true;
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
            this.savedServers = [
              { id: url, name: url.replace(/^https?:\/\//, '').split('/')[0], url: url, username: '', lastUsedMs: Date.now() },
              ...this.savedServers.filter((s) => s.url !== url)
            ];
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
          onLoginSuccess: (_token: string, name: string, isSu: boolean) => {
            this.userName = name;
            this.isSuperuser = isSu;
            this.authStage = 'main';
          }
        })
      } else {
        // 已认证主业务壳
        Stack({ alignContent: Alignment.Bottom }) {
          if (this.activeRoute === 'tab') {
            if (this.selectedTab === 'discover') {
              HarmonyDiscoverPage({
                onOpenMedia: (it: HarmonyMediaItem) => { this.selectedMedia = it; this.activeRoute = 'detail'; },
                onOpenExplore: () => { this.selectedTab = 'explore'; },
                onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
              })
            } else if (this.selectedTab === 'explore') {
              HarmonyExplorePage({
                onOpenMedia: (it: HarmonyMediaItem) => { this.selectedMedia = it; this.activeRoute = 'detail'; }
              })
            } else if (this.selectedTab === 'dashboard') {
              HarmonyDashboardPage({
                onOpenShortcuts: () => { this.activeRoute = 'diagnostics'; }
              })
            } else {
              HarmonySettingsHubPage({
                serverUrl: this.serverUrl,
                userName: this.userName,
                onOpenSites: () => { this.activeRoute = 'sites'; },
                onLogout: () => { this.authStage = 'login'; this.activeRoute = 'tab'; }
              })
            }
          } else if (this.activeRoute === 'search') {
            HarmonyGlobalSearchPage({
              onBack: () => { this.activeRoute = 'tab'; },
              onOpenMedia: (it: HarmonyMediaItem) => { this.selectedMedia = it; this.activeRoute = 'detail'; }
            })
          } else if (this.activeRoute === 'detail' && this.selectedMedia) {
            HarmonyMediaDetailPage({
              item: this.selectedMedia,
              onBack: () => { this.activeRoute = 'tab'; },
              onSearchResource: () => { this.activeRoute = 'resources'; },
              onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
            })
          } else if (this.activeRoute === 'subscriptions' || this.activeRoute === 'calendar') {
            HarmonySubscriptionsPage({ onBack: () => { this.activeRoute = 'tab'; } })
          } else if (this.activeRoute === 'resources') {
            HarmonyResourceSearchPage({ onBack: () => { this.activeRoute = 'tab'; } })
          } else if (this.activeRoute === 'downloads') {
            HarmonyDownloadsPage({ onBack: () => { this.activeRoute = 'tab'; } })
          } else if (this.activeRoute === 'files' || this.activeRoute === 'history') {
            HarmonyLibraryPage({
              onBack: () => { this.activeRoute = 'tab'; },
              onPlayMedia: (req: HarmonyPlaybackRequest) => this.playMedia(req)
            })
          } else if (this.activeRoute === 'workflows') {
            HarmonyWorkflowCanvasPage({ onBack: () => { this.activeRoute = 'tab'; } })
          } else if (this.activeRoute === 'sites') {
            HarmonySitesPage({ onBack: () => { this.activeRoute = 'tab'; } })
          } else if (this.activeRoute === 'diagnostics') {
            HarmonyDiagnosticsPage({ onBack: () => { this.activeRoute = 'tab'; } })
          } else if (this.activeRoute === 'agent') {
            HarmonyAgentChatPage({ onBack: () => { this.activeRoute = 'tab'; } })
          } else {
            HarmonySettingsHubPage({
              serverUrl: this.serverUrl,
              userName: this.userName,
              onOpenSites: () => { this.activeRoute = 'sites'; },
              onLogout: () => { this.authStage = 'login'; this.activeRoute = 'tab'; }
            })
          }

          // 8 项鸿蒙光感快捷菜单
          if (this.showOverflowMenu) {
            Column()
              .width('100%')
              .height('100%')
              .onClick(() => { this.showOverflowMenu = false; })
            FloatingOverflowMenuCard({
              userName: this.userName,
              isSuperuser: this.isSuperuser,
              onSelect: (id: string) => {
                this.showOverflowMenu = false;
                this.activeRoute = id;
              }
            })
              .position({ left: 18, bottom: 92 })
          }

          // 悬浮 AI 入口 + 迷你音乐条 + 4+1 光感底栏
          if (this.activeRoute !== 'agent') {
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
              FloatingFourPlusOneNavBar({
                selectedTab: this.selectedTab,
                userInitial: this.userName.substring(0, 1).toUpperCase(),
                onTabClick: (tab: HarmonyMainTab) => {
                  if (tab === this.selectedTab && this.activeRoute === 'tab') {
                    this.showOverflowMenu = !this.showOverflowMenu;
                  } else {
                    this.showOverflowMenu = false;
                    this.selectedTab = tab;
                    this.activeRoute = 'tab';
                  }
                },
                onPlusOneClick: () => {
                  this.showOverflowMenu = false;
                  this.activeRoute = 'search';
                }
              })
            }
          }
        }
        .width('100%')
        .height('100%')
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
  }
}
