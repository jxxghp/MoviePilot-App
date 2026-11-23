import {
  RustCoreBridge,
  MoviePilotRepository,
  MpDashboardStats,
  MpUserItem,
  MpPluginItem,
  MpCommunityState,
  MpCommunityMedal,
  MpSimpleSettingItem,
  MpServiceConfig,
  MpDirectoryConfig,
  MpStorageConfig,
  MpRemoteImage,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  HARMONY_PALETTES,
  HarmonyPalettePreset,
  HarmonyAppearanceStore,
  HarmonyDynamicLight,
  HarmonyThemeColors,
  HarmonyPillTabBar,
  HarmonySegmentedSwitch,
  HarmonySheetHeader,
  NativeBackHeader,
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import { CommunityMedal3DComponent } from '@moviepilot/medal_3d';
import {
  HarmonyVueChromeController,
  NativePluginDataPageView,
  NativePluginHostView,
  VueChromeAction
} from '@moviepilot/plugin_host';

/**
 * 鸿蒙「插件中心」独立页面：
 * - 插件中心与插件详情（「数据页 / 参数配置」）全部统一使用大胶囊分页 `HarmonyPillTabBar`；
 * - 插件原生渲染器已过滤 `<style>`/`<script>` 原始样式节点，并支持网页视图一键切换。
 */
@Component
export struct HarmonyPluginsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop serverUrl: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @State private activeTabIdx: number = 0; // 0: 已安装, 1: 插件市场
  @State private searchQuery: string = '';
  @State private installedPlugins: MpPluginItem[] = [];
  @State private marketPlugins: MpPluginItem[] = [];
  @State private loading: boolean = true;
  @State private activePlugin: MpPluginItem | null = null;
  @State private detailTabIndex: number = 0; // 0: 数据页, 1: 参数配置
  @State private forceWebView: boolean = false;
  @State private activeFormDoc: string = '{}';
  @State private activePageDoc: string = '{}';
  @State private loadingDetail: boolean = false;
  @State private chromeTitle: string = '';
  @State private chromeActions: VueChromeAction[] = [];
  @State private saveNotice: string = '';
  private vueChromeController: HarmonyVueChromeController = new HarmonyVueChromeController();
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadInstalled();
  }

  private async loadInstalled(): Promise<void> {
    this.loading = true;
    try {
      this.installedPlugins = await MoviePilotRepository.shared().fetchPlugins('installed');
    } catch {
      this.installedPlugins = [];
    }
    this.loading = false;
  }

  private async loadMarketIfNeeded(): Promise<void> {
    if (this.marketPlugins.length > 0) { return; }
    this.loading = true;
    try {
      this.marketPlugins = await MoviePilotRepository.shared().fetchPlugins('market');
    } catch {
      this.marketPlugins = [];
    }
    this.loading = false;
  }

  private filteredPlugins(): MpPluginItem[] {
    const src = this.activeTabIdx === 0 ? this.installedPlugins : this.marketPlugins;
    const q = this.searchQuery.trim().toLowerCase();
    if (!q) { return src.slice(0, 60); }
    return src.filter((p: MpPluginItem) =>
      `${p.pluginName} ${p.pluginDesc} ${p.pluginAuthor} ${p.id}`.toLowerCase().includes(q)
    ).slice(0, 60);
  }

  private async openPluginDetail(pl: MpPluginItem): Promise<void> {
    this.activePlugin = pl;
    this.chromeTitle = pl.pluginName;
    this.chromeActions = [];
    this.saveNotice = '';
    this.forceWebView = false;
    this.detailTabIndex = pl.hasPage ? 0 : 1;
    this.loadingDetail = true;
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchPluginFormJson(pl.id),
        pl.hasPage ? repo.fetchPluginPageJson(pl.id) : Promise.resolve('{}')
      ]);
      this.activeFormDoc = res[0];
      this.activePageDoc = res[1];
    } catch {
      this.activeFormDoc = '{}';
      this.activePageDoc = '{}';
    }
    this.loadingDetail = false;
  }

  private isActivePluginVue(): boolean {
    if (this.forceWebView) { return true; }
    if (!this.activePlugin) { return false; }
    if (this.activePlugin.renderMode.toLowerCase() === 'vue') { return true; }
    return this.activeFormDoc.includes('"render_mode":"vue"') || this.activeFormDoc.includes('"render_mode": "vue"')
      || this.activePageDoc.includes('"render_mode":"vue"') || this.activePageDoc.includes('"render_mode": "vue"');
  }

  private closePluginDetail(): void {
    if (this.isActivePluginVue() && this.vueChromeController.requestClose()) {
      return;
    }
    this.activePlugin = null;
    this.chromeTitle = '';
    this.chromeActions = [];
    this.forceWebView = false;
  }

  build() {
    if (this.activePlugin) {
      Column({ space: 8 }) {
        NativeBackHeader({
          title: this.chromeTitle || this.activePlugin.pluginName,
          trailingText: this.chromeActions.length > 0
            ? this.chromeActions[0].title
            : (this.forceWebView ? '原生视图' : '网页视图'),
          onBack: () => this.closePluginDetail(),
          onTrailingClick: () => {
            if (this.chromeActions.length > 0) {
              this.vueChromeController.invokeAction(this.chromeActions[0].id);
            } else {
              this.forceWebView = !this.forceWebView;
            }
          }
        })

        if (this.saveNotice.length > 0) {
          Text(this.saveNotice)
            .fontSize(12)
            .fontColor('#34C759')
            .padding({ left: 16, right: 16 })
            .width('100%')
        }

        if (!this.isActivePluginVue() && this.activePlugin.hasPage) {
          HarmonyPillTabBar({
            tabs: ['数据页', '参数配置'],
            selectedIndex: this.detailTabIndex,
            onSelect: (idx: number) => { this.detailTabIndex = idx; }
          })
        }

        if (this.loadingDetail) {
          Column() { LoadingProgress().width(32).height(32).color(this.accentHex) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.activePlugin.hasPage && this.detailTabIndex === 0) {
          NativePluginDataPageView({
            pluginId: this.activePlugin.id,
            documentJson: this.forceWebView ? '{"render_mode":"vue"}' : this.activePageDoc,
            serverUrl: this.serverUrl,
            authToken: MoviePilotRepository.shared().token,
            userName: this.userName,
            userAvatar: this.userAvatar,
            isSuperuser: this.isSuperuser,
            pluginHasPage: this.activePlugin.hasPage,
            chromeController: this.vueChromeController,
            onChromeTitleChange: (t: string) => { this.chromeTitle = t; },
            onChromeActionsChange: (acts: VueChromeAction[]) => { this.chromeActions = acts; },
            onRequestDismiss: () => { this.activePlugin = null; }
          }).layoutWeight(1)
        } else {
          NativePluginHostView({
            pluginName: this.activePlugin.id,
            documentJson: this.forceWebView ? '{"render_mode":"vue"}' : this.activeFormDoc,
            serverUrl: this.serverUrl,
            authToken: MoviePilotRepository.shared().token,
            userName: this.userName,
            userAvatar: this.userAvatar,
            isSuperuser: this.isSuperuser,
            pluginHasPage: this.activePlugin.hasPage,
            chromeController: this.vueChromeController,
            onChromeTitleChange: (t: string) => { this.chromeTitle = t; },
            onChromeActionsChange: (acts: VueChromeAction[]) => { this.chromeActions = acts; },
            onRequestDismiss: () => { this.activePlugin = null; },
            onSaveFullModel: async (fullJson: string) => {
              if (this.activePlugin) {
                const ok = await MoviePilotRepository.shared().savePluginFormModel(this.activePlugin.id, fullJson);
                this.saveNotice = ok ? '插件配置已保存至 MoviePilot' : '保存失败，请检查服务端状态';
              }
            }
          }).layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    } else {
      Column({ space: 10 }) {
        NativeBackHeader({
          title: '插件中心',
          trailingSymbol: 'sys.symbol.arrow_clockwise',
          trailingAccessibility: '刷新插件列表',
          onBack: () => this.onBack(),
          onTrailingClick: () => this.loadInstalled()
        })

        HarmonyPillTabBar({
          tabs: [`已安装 (${this.installedPlugins.length})`, `插件市场 (${this.marketPlugins.length})`],
          selectedIndex: this.activeTabIdx,
          onSelect: (idx: number) => {
            this.activeTabIdx = idx;
            if (idx === 1) { this.loadMarketIfNeeded(); }
          }
        })

        Row() {
          TextInput({ placeholder: '搜索插件名称、作者或标签…', text: this.searchQuery })
            .width('100%')
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(16)
            .onChange((v: string) => { this.searchQuery = v; })
        }.padding({ left: 16, right: 16 })

        if (this.loading && (this.activeTabIdx === 0 ? this.installedPlugins.length === 0 : this.marketPlugins.length === 0)) {
          Column() { LoadingProgress().width(32).height(32).color(this.accentHex) }
            .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.filteredPlugins(), (pl: MpPluginItem) => {
                Column() {
                  CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: this.activeTabIdx === 0 }) {
                    Row({ space: 12 }) {
                      if (pl.iconUrl.length > 0) {
                        MpRemoteImage({
                          src: pl.iconUrl,
                          imgWidth: 44,
                          imgHeight: 44,
                          imgRadius: 12,
                          placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                        })
                      } else {
                        Stack() {
                          SymbolGlyph($r('sys.symbol.puzzle')).fontSize(20).fontColor([this.accentHex])
                        }
                        .width(44).height(44).borderRadius(12).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      }

                      Column({ space: 4 }) {
                        Row({ space: 6 }) {
                          Text(pl.pluginName).fontSize(15).fontWeight(FontWeight.Bold)
                            .fontColor(mpPrimaryText(this.isDark)).maxLines(1).layoutWeight(1)
                          if (pl.pluginVersion.length > 0) {
                            NativeAdaptiveBadge({ text: `v${pl.pluginVersion}`, tintHex: this.accentHex })
                          }
                        }.width('100%')
                        Text(pl.pluginDesc || pl.id).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                          .maxLines(2).width('100%')
                        Row({ space: 8 }) {
                          Text(`作者：${pl.pluginAuthor || 'MoviePilot'}`).fontSize(11).fontColor(mpSecondaryText(this.isDark))
                          if (pl.hasPage) {
                            NativeAdaptiveBadge({ text: '数据页', tintHex: '#5AC8FA' })
                          }
                        }
                      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                      if (this.activeTabIdx === 0) {
                        NativeAdaptiveBadge({
                          text: pl.state ? '已启用' : '配置',
                          tintHex: pl.state ? '#34C759' : this.accentHex
                        })
                      }
                    }.width('100%')
                  }
                }
                .width('100%')
                .onClick(() => {
                  if (this.activeTabIdx === 0) { this.openPluginDetail(pl); }
                })
              }, (pl: MpPluginItem) => `${this.activeTabIdx}_${pl.id}`)
            }
            .padding({ left: 16, right: 16, top: 2, bottom: 40 })
          }.scrollBar(BarState.Off).layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    }
  }
}

@Component
struct HarmonySettingsRow {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop title: string = '';
  @Prop sub: string = '';
  onTap: () => void = () => {};

  build() {
    Row() {
      Text(this.title).fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
      Text(this.sub).fontSize(12.5).fontColor(mpSecondaryText(this.isDark)).maxLines(1)
      Text(' ›').fontSize(16).fontColor(mpSecondaryText(this.isDark))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 15, bottom: 15 })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onTap())
  }
}

/**
 * 鸿蒙「设置」主中心：
 * - 移除重复的「插件中心」入口，顶部 3 枚磁贴为「站点管理 / 用户管理 / 渠道授权」；
 * - 下载器、媒体服务器、整理与目录均支持完整新增、点击编辑与删除确认并无损持久化；
 * - 内置鸿蒙专属「主题与外观」工作台（5 套鸿蒙色板 + HarmonyOS 7 动态光感 + 实时预览）；
 * - 去除底层技术术语，清晰展示「客户端版本」。
 */
@Component
export struct HarmonySettingsHubPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_MODE) appearanceMode: string = 'dark';
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_ANIMATE_BG) animateBg: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop serverUrl: string = '';
  @Prop userName: string = 'admin';
  @State private stats: MpDashboardStats = {
    movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0,
    storageUsedBytes: 0, storageTotalBytes: 0,
    downloadSpeed: 0, uploadSpeed: 0, downloadSize: 0, uploadSize: 0,
    memoryPercent: 0, memoryUsedBytes: 0, transferCounts: [], scheduleCount: 0
  };
  @State private siteCount: number = 0;
  @State private users: MpUserItem[] = [];
  @State private downloaders: MpServiceConfig[] = [];
  @State private mediaServers: MpServiceConfig[] = [];
  @State private directories: MpDirectoryConfig[] = [];
  @State private storages: MpStorageConfig[] = [];
  @State private notifications: MpSimpleSettingItem[] = [];
  @State private community: MpCommunityState = { githubLogin: 'MoviePilot', earnedCount: 0, totalCount: 7, medals: [] };
  @State private notice: string = '';

  // 弹层开关
  @State private showAppearanceSheet: boolean = false;
  @State private showUsersSheet: boolean = false;
  @State private showDownloadersSheet: boolean = false;
  @State private showMediaServersSheet: boolean = false;
  @State private showDirectoriesSheet: boolean = false;
  @State private showNotificationsSheet: boolean = false;
  @State private showPlaybackSheet: boolean = false;
  @State private showMedalsSheet: boolean = false;
  @State private activeMedalIdx: number = 0;
  @State private playbackSpeedIdx: number = 1;
  @State private playbackQualityIdx: number = 0;
  @State private playbackPip: boolean = true;

  // 服务/目录 CRUD 编辑态
  @State private showCrudEditor: boolean = false;
  @State private crudKind: string = 'downloader'; // 'downloader' | 'mediaserver' | 'directory'
  @State private crudCreate: boolean = true;
  @State private crudOrigName: string = '';
  @State private crudRawJson: string = '';
  @State private crudName: string = '';
  @State private crudType: string = 'qbittorrent';
  @State private crudHost: string = '';
  @State private crudUser: string = '';
  @State private crudPass: string = '';
  @State private crudApiKey: string = '';
  @State private crudPlayHost: string = '';
  @State private crudEnabled: boolean = true;
  @State private crudDefault: boolean = false;
  // 目录字段
  @State private dirPriority: string = '1';
  @State private dirStorage: string = 'local';
  @State private dirDlPath: string = '';
  @State private dirLibStorage: string = 'local';
  @State private dirLibPath: string = '';
  @State private dirTransferType: string = 'link';
  @State private dirMonitorType: string = 'downloader';
  @State private dirRenaming: boolean = true;
  @State private dirScraping: boolean = true;
  @State private dirNotify: boolean = true;
  @State private crudSaving: boolean = false;

  onBack: () => void = () => {};
  onOpenSites: () => void = () => {};
  onLogout: () => void = () => {};

  aboutToAppear(): void {
    this.loadSettingsSummary();
  }

  private async loadSettingsSummary(): Promise<void> {
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchDashboardStats(),
        repo.fetchSites(),
        repo.fetchUsers(),
        repo.fetchCommunityMedals(),
        repo.fetchDownloaders(),
        repo.fetchMediaServers(),
        repo.fetchDirectories(),
        repo.fetchStorages(),
        repo.fetchSystemSettingList('Notifications')
      ]);
      this.stats = res[0];
      this.siteCount = res[1].filter((s) => s.isActive).length;
      this.users = res[2];
      this.community = res[3];
      this.downloaders = res[4];
      this.mediaServers = res[5];
      this.directories = res[6];
      this.storages = res[7];
      this.notifications = res[8];
    } catch {
      // ignore
    }
  }

  private storagePct(): number {
    if (this.stats.storageTotalBytes <= 0) { return 0; }
    return Math.min(100, Math.round((this.stats.storageUsedBytes / this.stats.storageTotalBytes) * 100));
  }

  private modeIndex(): number {
    if (this.appearanceMode === 'light') { return 1; }
    if (this.appearanceMode === 'system') { return 2; }
    return 0;
  }

  private openServiceCrud(kind: string, item: MpServiceConfig | null): void {
    this.crudKind = kind;
    this.crudCreate = item === null;
    this.crudOrigName = item ? item.name : '';
    this.crudRawJson = item ? item.rawJson : '';
    this.crudName = item ? item.name : '';
    this.crudType = item ? item.type : (kind === 'downloader' ? 'qbittorrent' : 'emby');
    this.crudHost = item ? item.host : '';
    this.crudUser = item ? item.username : '';
    this.crudPass = item ? item.password : '';
    this.crudApiKey = item ? item.apikey : '';
    this.crudPlayHost = item ? item.playHost : '';
    this.crudEnabled = item ? item.enabled : true;
    this.crudDefault = item ? item.isDefault : (kind === 'downloader' && this.downloaders.length === 0);
    this.showCrudEditor = true;
  }

  private openDirectoryCrud(item: MpDirectoryConfig | null): void {
    this.crudKind = 'directory';
    this.crudCreate = item === null;
    this.crudOrigName = item ? item.name : '';
    this.crudRawJson = item ? item.rawJson : '';
    this.crudName = item ? item.name : '';
    this.dirPriority = item ? String(item.priority) : String(this.directories.length + 1);
    const defaultSt = this.storages.length > 0 ? this.storages[0].type : 'local';
    this.dirStorage = item ? item.storage : defaultSt;
    this.dirDlPath = item ? item.downloadPath : '';
    this.dirLibStorage = item ? item.libraryStorage : defaultSt;
    this.dirLibPath = item ? item.libraryPath : '';
    this.dirTransferType = item ? item.transferType : 'link';
    this.dirMonitorType = item ? item.monitorType : 'downloader';
    this.dirRenaming = item ? item.renaming : true;
    this.dirScraping = item ? item.scraping : true;
    this.dirNotify = item ? item.notify : true;
    this.showCrudEditor = true;
  }

  private async saveCrud(): Promise<void> {
    if (this.crudSaving || this.crudName.trim().length === 0) { return; }
    this.crudSaving = true;
    const repo = MoviePilotRepository.shared();
    let ok = false;
    if (this.crudKind === 'downloader') {
      ok = await repo.saveDownloader({
        name: this.crudName.trim(), type: this.crudType, host: this.crudHost.trim(),
        username: this.crudUser.trim(), password: this.crudPass, apikey: '', playHost: '',
        enabled: this.crudEnabled, isDefault: this.crudDefault, rawJson: this.crudRawJson
      }, this.crudCreate ? null : this.crudOrigName);
    } else if (this.crudKind === 'mediaserver') {
      ok = await repo.saveMediaServer({
        name: this.crudName.trim(), type: this.crudType, host: this.crudHost.trim(),
        username: '', password: '', apikey: this.crudApiKey.trim(), playHost: this.crudPlayHost.trim(),
        enabled: this.crudEnabled, isDefault: false, rawJson: this.crudRawJson
      }, this.crudCreate ? null : this.crudOrigName);
    } else {
      ok = await repo.saveDirectory({
        name: this.crudName.trim(), priority: Number(this.dirPriority) || 1,
        storage: this.dirStorage, downloadPath: this.dirDlPath.trim(),
        libraryStorage: this.dirLibStorage, libraryPath: this.dirLibPath.trim(),
        transferType: this.dirTransferType, monitorType: this.dirMonitorType,
        renaming: this.dirRenaming, scraping: this.dirScraping, notify: this.dirNotify,
        rawJson: this.crudRawJson
      }, this.crudCreate ? null : this.crudOrigName);
    }
    this.crudSaving = false;
    this.showCrudEditor = false;
    this.notice = ok ? `已保存「${this.crudName.trim()}」` : '保存失败，请检查配置';
    await this.loadSettingsSummary();
  }

  private async deleteCrud(): Promise<void> {
    if (this.crudCreate || this.crudOrigName.length === 0) { return; }
    const repo = MoviePilotRepository.shared();
    let ok = false;
    if (this.crudKind === 'downloader') {
      ok = await repo.deleteDownloader(this.crudOrigName);
    } else if (this.crudKind === 'mediaserver') {
      ok = await repo.deleteMediaServer(this.crudOrigName);
    } else {
      ok = await repo.deleteDirectory(this.crudOrigName);
    }
    this.showCrudEditor = false;
    this.notice = ok ? `已删除「${this.crudOrigName}」` : '删除失败';
    await this.loadSettingsSummary();
  }

  @Builder
  appearanceSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '主题与外观',
        cancelText: '完成',
        actionText: '恢复默认',
        onCancel: () => { this.showAppearanceSheet = false; },
        onAction: () => { HarmonyAppearanceStore.resetDefaults(); }
      })

      Scroll() {
        Column({ space: 14 }) {
          // 实时预览卡片（鸿蒙色系 + 光感微光）
          Column({ space: 10 }) {
            Row() {
              Text('MoviePilot').fontSize(17).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              NativeAdaptiveBadge({ text: HarmonyAppearanceStore.paletteById(this.paletteId).titleZh, tintHex: this.accentHex, filled: true })
            }.width('100%')
            Row({ space: 8 }) {
              NativeAdaptiveBadge({ text: '发现', tintHex: this.accentHex, filled: true })
              NativeAdaptiveBadge({ text: '媒体库', tintHex: this.accentHex })
              NativeAdaptiveBadge({ text: '订阅', tintHex: this.accentHex })
            }.width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor(HarmonyThemeColors.headerTint(this.isDark, this.paletteId))
          .border({ width: 0.8, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '44'), radius: 20 })

          Text('显示模式').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          HarmonySegmentedSwitch({
            options: ['深色', '浅色', '跟随系统'],
            selectedIndex: this.modeIndex(),
            onSelect: (idx: number) => {
              if (idx === 0) {
                this.appearanceMode = 'dark';
                this.isDark = true;
                HarmonyAppearanceStore.applyPalette(this.paletteId, true);
              } else if (idx === 1) {
                this.appearanceMode = 'light';
                this.isDark = false;
                HarmonyAppearanceStore.applyPalette(this.paletteId, false);
              } else {
                this.appearanceMode = 'system';
              }
            }
          })

          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Row() {
              Column({ space: 2 }) {
                Text('AMOLED 纯黑模式').fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                Text('深色画布切换纯黑 #000000，极致对比与省电').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.pureBlack })
                .selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.pureBlack = v; })
            }.width('100%')
          }

          // 5 套鸿蒙专属主题色板（2 列网格，零截断）
          Text('鸿蒙主题色板').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Grid() {
            ForEach(HARMONY_PALETTES, (p: HarmonyPalettePreset) => {
              GridItem() {
                Row({ space: 10 }) {
                  Stack() {
                    if (this.paletteId === p.id) {
                      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(15).fontColor([Color.White])
                    }
                  }
                  .width(32).height(32).borderRadius(16)
                  .backgroundColor(this.isDark ? p.accentDark : p.accentLight)

                  Column({ space: 2 }) {
                    Text(p.titleZh).fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).maxLines(1)
                    Text(p.subtitleZh).fontSize(11.5).fontColor(mpSecondaryText(this.isDark)).maxLines(1)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                }
                .width('100%')
                .padding(12)
                .borderRadius(16)
                .backgroundColor(this.paletteId === p.id
                  ? HarmonyAppearanceStore.withAlpha(this.isDark ? p.accentDark : p.accentLight, this.isDark ? '2B' : '1A')
                  : HarmonyThemeColors.card(this.isDark, this.paletteId))
                .border({
                  width: this.paletteId === p.id ? 1.5 : 0.6,
                  color: this.paletteId === p.id ? (this.isDark ? p.accentDark : p.accentLight) : HarmonyThemeColors.borderSubtle(this.isDark),
                  radius: 16
                })
                .onClick(() => HarmonyAppearanceStore.applyPalette(p.id, this.isDark))
              }
            }, (p: HarmonyPalettePreset) => p.id)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

          // HarmonyOS 7 动态光感材质卡片与低版本自动回退
          Text('动态光感引擎').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 10 }) {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text('HarmonyOS 7 动态光感材质').fontSize(14.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text(HarmonyDynamicLight.tierLabel()).fontSize(11.5).fontColor(this.accentHex)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.dynamicLight })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => { this.dynamicLight = v; })
              }.width('100%')

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text('顶部光感微光').fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text('随当前鸿蒙色板柔化顶部光影层次').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.animateBg })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => { this.animateBg = v; })
              }.width('100%')
            }
          }
        }.padding({ bottom: 28 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  downloadersSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: `下载器 (${this.downloaders.length})`,
        cancelText: '关闭',
        actionText: '新增',
        onCancel: () => { this.showDownloadersSheet = false; },
        onAction: () => {
          this.showDownloadersSheet = false;
          this.openServiceCrud('downloader', null);
        }
      })
      Scroll() {
        Column({ space: 10 }) {
          if (this.downloaders.length === 0) {
            Text('暂未配置下载器，点击右上角「新增」添加').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.downloaders, (dl: MpServiceConfig) => {
              Column() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                  Row({ space: 10 }) {
                    Column({ space: 3 }) {
                      Row({ space: 6 }) {
                        Text(dl.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                        if (dl.isDefault) { NativeAdaptiveBadge({ text: '默认', tintHex: this.accentHex }) }
                      }
                      Text(`${dl.type} · ${dl.host || '已配置'}`).fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(1)
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    NativeAdaptiveBadge({ text: dl.enabled ? '已启用' : '已停用', tintHex: dl.enabled ? '#34C759' : '#F29B38' })
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([mpSecondaryText(this.isDark)])
                  }.width('100%')
                }
              }
              .width('100%')
              .onClick(() => {
                this.showDownloadersSheet = false;
                this.openServiceCrud('downloader', dl);
              })
            }, (dl: MpServiceConfig) => `${dl.name}_${dl.host}_${dl.enabled}`)
          }
        }
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  mediaServersSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: `媒体服务器 (${this.mediaServers.length})`,
        cancelText: '关闭',
        actionText: '新增',
        onCancel: () => { this.showMediaServersSheet = false; },
        onAction: () => {
          this.showMediaServersSheet = false;
          this.openServiceCrud('mediaserver', null);
        }
      })
      Scroll() {
        Column({ space: 10 }) {
          if (this.mediaServers.length === 0) {
            Text('暂未配置媒体服务器，点击右上角「新增」添加').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.mediaServers, (ms: MpServiceConfig) => {
              Column() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                  Row({ space: 10 }) {
                    Column({ space: 3 }) {
                      Text(ms.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      Text(`${ms.type} · ${ms.host || '已配置'}`).fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(1)
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    NativeAdaptiveBadge({ text: ms.enabled ? '已启用' : '已停用', tintHex: ms.enabled ? '#34C759' : '#F29B38' })
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([mpSecondaryText(this.isDark)])
                  }.width('100%')
                }
              }
              .width('100%')
              .onClick(() => {
                this.showMediaServersSheet = false;
                this.openServiceCrud('mediaserver', ms);
              })
            }, (ms: MpServiceConfig) => `${ms.name}_${ms.host}_${ms.enabled}`)
          }
        }
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  directoriesSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: `整理与目录 (${this.directories.length})`,
        cancelText: '关闭',
        actionText: '新增',
        onCancel: () => { this.showDirectoriesSheet = false; },
        onAction: () => {
          this.showDirectoriesSheet = false;
          this.openDirectoryCrud(null);
        }
      })
      Scroll() {
        Column({ space: 12 }) {
          Text('下载与媒体库整理目录').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          ForEach(this.directories, (d: MpDirectoryConfig) => {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                Column({ space: 6 }) {
                  Row({ space: 8 }) {
                    NativeAdaptiveBadge({ text: `#${d.priority}`, tintHex: this.accentHex })
                    Text(d.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                    NativeAdaptiveBadge({ text: d.transferType, tintHex: '#34C759' })
                    SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([mpSecondaryText(this.isDark)])
                  }.width('100%')
                  if (d.downloadPath.length > 0) {
                    Text(`源 (${d.storage})：${d.downloadPath}`).fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(1).width('100%')
                  }
                  if (d.libraryPath.length > 0) {
                    Text(`库 (${d.libraryStorage})：${d.libraryPath}`).fontSize(12).fontColor(this.accentHex).maxLines(1).width('100%')
                  }
                }
              }
            }
            .width('100%')
            .onClick(() => {
              this.showDirectoriesSheet = false;
              this.openDirectoryCrud(d);
            })
          }, (d: MpDirectoryConfig) => `${d.name}_${d.priority}`)

          if (this.storages.length > 0) {
            Text(`已挂载存储 (${this.storages.length})`).fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Column({ space: 8 }) {
                ForEach(this.storages, (st: MpStorageConfig) => {
                  Row() {
                    Text(st.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                    NativeAdaptiveBadge({ text: st.type, tintHex: '#34C759' })
                  }.width('100%')
                }, (st: MpStorageConfig) => st.type)
              }
            }
          }
        }.padding({ bottom: 24 })
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  crudEditorSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: `${this.crudCreate ? '新增' : '编辑'}${this.crudKind === 'downloader' ? '下载器' : (this.crudKind === 'mediaserver' ? '媒体服务器' : '整理目录')}`,
        cancelText: '取消',
        actionText: this.crudSaving ? '保存中' : '保存',
        actionEnabled: !this.crudSaving && this.crudName.trim().length > 0,
        onCancel: () => { this.showCrudEditor = false; },
        onAction: () => { this.saveCrud(); }
      })

      Scroll() {
        Column({ space: 10 }) {
          if (this.crudKind === 'downloader') {
            Row({ space: 8 }) {
              NativeAdaptivePill({ title: 'qBittorrent', selected: this.crudType === 'qbittorrent', onTap: () => { this.crudType = 'qbittorrent'; } })
              NativeAdaptivePill({ title: 'Transmission', selected: this.crudType === 'transmission', onTap: () => { this.crudType = 'transmission'; } })
            }.width('100%')
            TextInput({ placeholder: '名称', text: this.crudName }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudName = v; })
            TextInput({ placeholder: '服务地址（如 http://127.0.0.1:8080）', text: this.crudHost }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudHost = v; })
            TextInput({ placeholder: '用户名', text: this.crudUser }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudUser = v; })
            TextInput({ placeholder: '密码', text: this.crudPass }).type(InputType.Password).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudPass = v; })
            Row() {
              Text('启用此下载器').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.crudEnabled }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.crudEnabled = v; })
            }.width('100%')
            Row() {
              Text('设为默认下载器').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.crudDefault }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.crudDefault = v; })
            }.width('100%')
          } else if (this.crudKind === 'mediaserver') {
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
              ForEach([['emby', 'Emby'], ['jellyfin', 'Jellyfin'], ['plex', 'Plex'], ['trimemedia', '飞牛影视']], (opt: string[]) => {
                NativeAdaptivePill({ title: opt[1], selected: this.crudType === opt[0], onTap: () => { this.crudType = opt[0]; } })
              }, (opt: string[]) => opt[0])
            }.width('100%')
            TextInput({ placeholder: '名称', text: this.crudName }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudName = v; })
            TextInput({ placeholder: '服务器地址（如 http://127.0.0.1:8096）', text: this.crudHost }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudHost = v; })
            TextInput({ placeholder: this.crudType === 'plex' ? 'Token' : 'API Key', text: this.crudApiKey }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudApiKey = v; })
            TextInput({ placeholder: '外网播放地址（可选）', text: this.crudPlayHost }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.crudPlayHost = v; })
            Row() {
              Text('启用此服务器').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.crudEnabled }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.crudEnabled = v; })
            }.width('100%')
          } else {
            Row({ space: 8 }) {
              TextInput({ placeholder: '目录名称', text: this.crudName }).layoutWeight(1).fontColor(mpPrimaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
                .onChange((v: string) => { this.crudName = v; })
              TextInput({ placeholder: '优先级', text: this.dirPriority }).type(InputType.Number).width(84).fontColor(mpPrimaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
                .onChange((v: string) => { this.dirPriority = v; })
            }.width('100%')
            Text('源存储与下载路径').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
              ForEach(this.storages, (st: MpStorageConfig) => {
                NativeAdaptivePill({ title: st.type, selected: this.dirStorage === st.type, onTap: () => { this.dirStorage = st.type; } })
              }, (st: MpStorageConfig) => `ds_${st.type}`)
            }.width('100%')
            TextInput({ placeholder: '下载目录路径', text: this.dirDlPath }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.dirDlPath = v; })
            Text('目标存储与媒体库路径').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
              ForEach(this.storages, (st: MpStorageConfig) => {
                NativeAdaptivePill({ title: st.type, selected: this.dirLibStorage === st.type, onTap: () => { this.dirLibStorage = st.type; } })
              }, (st: MpStorageConfig) => `ls_${st.type}`)
            }.width('100%')
            TextInput({ placeholder: '媒体库路径', text: this.dirLibPath }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.dirLibPath = v; })
            Text('整理方式').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Row({ space: 6 }) {
              ForEach([['link', '硬链接'], ['softlink', '软链接'], ['copy', '复制'], ['move', '移动']], (t: string[]) => {
                NativeAdaptivePill({ title: t[1], selected: this.dirTransferType === t[0], onTap: () => { this.dirTransferType = t[0]; } })
              }, (t: string[]) => t[0])
            }.width('100%')
            Row() {
              Text('智能重命名').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.dirRenaming }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.dirRenaming = v; })
            }.width('100%')
            Row() {
              Text('自动刮削元数据').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.dirScraping }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.dirScraping = v; })
            }.width('100%')
            Row() {
              Text('整理完成发送通知').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.dirNotify }).selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.dirNotify = v; })
            }.width('100%')
          }

          if (!this.crudCreate) {
            Button('删除此项配置')
              .width('100%').height(44).borderRadius(22)
              .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
              .fontColor('#E84855').fontWeight(FontWeight.Bold)
              .onClick(() => this.deleteCrud())
          }
        }.padding({ bottom: 24 })
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  usersSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: `用户管理 (${this.users.length})`,
        cancelText: '关闭',
        onCancel: () => { this.showUsersSheet = false; }
      })
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.users, (u: MpUserItem) => {
            CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
              Row({ space: 12 }) {
                if (u.avatar.length > 0) {
                  MpRemoteImage({
                    src: u.avatar,
                    imgWidth: 42,
                    imgHeight: 42,
                    imgRadius: 21,
                    placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                  })
                } else {
                  Text(u.name.substring(0, 1).toUpperCase())
                    .width(42).height(42).borderRadius(21).textAlign(TextAlign.Center)
                    .fontColor(Color.White).fontWeight(FontWeight.Bold).backgroundColor(this.accentHex)
                }
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(u.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    NativeAdaptiveBadge({ text: u.isSuperuser ? '超管' : '成员', tintHex: u.isSuperuser ? this.accentHex : '#5AC8FA' })
                  }
                  Text(u.email || (u.isActive ? '账号已启用' : '账号已停用')).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%')
            }
          }, (u: MpUserItem) => String(u.id))
        }
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  notificationsSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: `通知渠道 (${this.notifications.length})`,
        cancelText: '关闭',
        onCancel: () => { this.showNotificationsSheet = false; }
      })
      Scroll() {
        Column({ space: 10 }) {
          if (this.notifications.length === 0) {
            Text('当前未配置消息通知渠道').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.notifications, (it: MpSimpleSettingItem, idx: number) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Row() {
                  Column({ space: 3 }) {
                    Text(it.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    Text(it.detail || it.type).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  NativeAdaptiveBadge({ text: it.enabled ? '已启用' : '未启用', tintHex: it.enabled ? '#34C759' : '#F29B38' })
                }.width('100%')
              }
            }, (it: MpSimpleSettingItem, idx: number) => `nf_${idx}_${it.name}`)
          }
        }
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  playbackSheetBuilder() {
    Column({ space: 14 }) {
      HarmonySheetHeader({
        title: '播放偏好',
        cancelText: '完成',
        onCancel: () => { this.showPlaybackSheet = false; }
      })
      Text('默认清晰度').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
      HarmonySegmentedSwitch({
        options: ['自适应', '原画直出', '1080p'],
        selectedIndex: this.playbackQualityIdx,
        onSelect: (idx: number) => { this.playbackQualityIdx = idx; }
      })
      Text('默认倍速').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
      HarmonySegmentedSwitch({
        options: ['0.75x', '1.0x', '1.25x', '1.5x'],
        selectedIndex: this.playbackSpeedIdx,
        onSelect: (idx: number) => { this.playbackSpeedIdx = idx; }
      })
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row() {
          Column({ space: 2 }) {
            Text('画中画浮窗续播').fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
            Text('退至后台时自动切入小窗继续播放').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.playbackPip }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.playbackPip = v; })
        }.width('100%')
      }
    }.padding(20).width('100%')
  }

  @Builder
  medalsSheetBuilder() {
    Column({ space: 14 }) {
      HarmonySheetHeader({
        title: `社区勋章 (${this.community.earnedCount}/${this.community.totalCount})`,
        cancelText: '关闭',
        onCancel: () => { this.showMedalsSheet = false; }
      })
      if (this.community.medals.length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.community.medals, (m: MpCommunityMedal, idx: number) => {
              NativeAdaptivePill({
                title: m.title,
                selected: this.activeMedalIdx === idx,
                onTap: () => { this.activeMedalIdx = idx; }
              })
            }, (m: MpCommunityMedal) => m.id)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

        CommunityMedal3DComponent({
          medalId: this.community.medals[this.activeMedalIdx].id,
          frontAsset: this.community.medals[this.activeMedalIdx].frontAsset,
          backAsset: this.community.medals[this.activeMedalIdx].backAsset,
          title: this.community.medals[this.activeMedalIdx].title,
          subtitle: this.community.medals[this.activeMedalIdx].subtitle,
          ownerName: this.community.githubLogin,
          earnedDate: this.community.medals[this.activeMedalIdx].earnedDate
        })
      }
    }.padding(20).width('100%').alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      NativeBackHeader({
        title: '设置',
        subtitle: this.serverUrl.replace(/^https?:\/\//, ''),
        onBack: () => this.onBack()
      })

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#34C759').padding({ left: 16, right: 16, bottom: 4 }).width('100%')
      }

      Scroll() {
        Column({ space: 16 }) {
          // 顶部真实存储容量卡
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Column({ space: 8 }) {
              Row() {
                Text(`● ${this.serverUrl.replace(/^https?:\/\//, '') || '127.0.0.1'}`)
                  .fontSize(13).fontColor('#34C759').layoutWeight(1).maxLines(1)
                Text(`${formatByteSize(this.stats.storageUsedBytes)} / ${formatByteSize(this.stats.storageTotalBytes)}`)
                  .fontSize(12).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
              }.width('100%')
              Progress({ value: this.storagePct(), total: 100, type: ProgressType.Linear })
                .color(this.accentHex).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              Row() {
                Text(`已用 ${this.storagePct()}%`).fontSize(11.5).fontColor(this.accentHex)
                Blank()
                Text(`可用 ${formatByteSize(Math.max(0, this.stats.storageTotalBytes - this.stats.storageUsedBytes))}`)
                  .fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
              }.width('100%')
            }
          }

          // 三枚快捷磁贴（已移除冗余插件入口：站点管理 / 用户管理 / 渠道授权）
          Row({ space: 10 }) {
            Column() {
              CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                Column({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.worldclock')).fontSize(18).fontColor([this.accentHex])
                  Text('站点管理').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text(`● ${this.siteCount} 启用`).fontSize(11).fontColor('#34C759')
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1).onClick(() => this.onOpenSites())

            Column() {
              CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                Column({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.person_2')).fontSize(18).fontColor([this.accentHex])
                  Text('用户管理').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text(`● ${this.users.length} 位成员`).fontSize(11).fontColor(this.accentHex)
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1).onClick(() => { this.showUsersSheet = true; })

            Column() {
              CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                Column({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.bell')).fontSize(18).fontColor([this.accentHex])
                  Text('渠道授权').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text(`● 已授 ${this.notifications.length}`).fontSize(11).fontColor('#34C759')
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1).onClick(() => { this.showNotificationsSheet = true; })
          }

          // 基础配置分组（全部支持新增、编辑与删除）
          Text('基础配置').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
            Column() {
              HarmonySettingsRow({ title: '下载器', sub: `${this.downloaders.length} 个`, onTap: () => { this.showDownloadersSheet = true; } })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              HarmonySettingsRow({ title: '媒体服务器', sub: `${this.mediaServers.length} 个`, onTap: () => { this.showMediaServersSheet = true; } })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              HarmonySettingsRow({ title: '整理与目录', sub: `${this.directories.length} 组映射`, onTap: () => { this.showDirectoriesSheet = true; } })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              HarmonySettingsRow({ title: '播放偏好', sub: ['自适应', '原画', '1080p'][this.playbackQualityIdx], onTap: () => { this.showPlaybackSheet = true; } })
            }
          }

          // 通知与个性化
          Text('通知与个性化').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
            Column() {
              HarmonySettingsRow({ title: '通知渠道', sub: `${this.notifications.length} 个渠道`, onTap: () => { this.showNotificationsSheet = true; } })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              HarmonySettingsRow({
                title: '主题与外观',
                sub: `${HarmonyAppearanceStore.paletteById(this.paletteId).titleZh} · ${this.dynamicLight ? HarmonyDynamicLight.materialLevelLabel() : '标准'}`,
                onTap: () => { this.showAppearanceSheet = true; }
              })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              HarmonySettingsRow({
                title: '社区勋章',
                sub: `已解锁 ${this.community.earnedCount}/${this.community.totalCount}`,
                onTap: () => { this.showMedalsSheet = true; }
              })
            }
          }

          // 账号与版本（去除底层技术名词）
          CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
            Column() {
              Row() {
                Text('客户端版本').fontSize(15).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
                NativeAdaptiveBadge({ text: `v${RustCoreBridge.version()}`, tintHex: this.accentHex })
              }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.power')).fontSize(18).fontColor(['#E84855'])
                Text(`退出登录（${this.userName}）`).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E84855')
              }
              .width('100%').padding({ left: 16, right: 16, top: 15, bottom: 15 })
              .onClick(() => this.onLogout())
            }
          }
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 44 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      Blank().width(0).height(0).bindSheet($$this.showAppearanceSheet, this.appearanceSheetBuilder(), {
        detents: [SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showUsersSheet, this.usersSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showDownloadersSheet, this.downloadersSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showMediaServersSheet, this.mediaServersSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showDirectoriesSheet, this.directoriesSheetBuilder(), {
        detents: [SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showNotificationsSheet, this.notificationsSheetBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showPlaybackSheet, this.playbackSheetBuilder(), {
        detents: [SheetSize.MEDIUM],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showCrudEditor, this.crudEditorSheetBuilder(), {
        detents: [SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showMedalsSheet, this.medalsSheetBuilder(), {
        detents: [SheetSize.LARGE],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  settingsRow(title: string, sub: string, action: () => void) {
    Row() {
      Text(title).fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
      Text(sub).fontSize(12.5).fontColor(mpSecondaryText(this.isDark)).maxLines(1)
      Text(' ›').fontSize(16).fontColor(mpSecondaryText(this.isDark))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 15, bottom: 15 })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(action)
  }
}
