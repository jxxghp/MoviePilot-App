import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import {
  RustCoreBridge,
  MoviePilotRepository,
  NativeHuksStore,
  MpDashboardStats,
  MpUserItem,
  MpPluginItem,
  MpCommunityState,
  MpCommunityMedal,
  MpSimpleSettingItem,
  MpServiceConfig,
  MpDirectoryConfig,
  MpStorageConfig,
  MpAuthorizationItem,
  MpImageLoader,
  MpRemoteImage,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  HARMONY_PALETTES,
  HarmonyPalettePreset,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonyDynamicLight,
  HarmonyThemeColors,
  HarmonyPillTabBar,
  HarmonySegmentedSwitch,
  HarmonySheetHeader,
  HarmonyEntityLogo,
  HarmonyEntityLogoPill,
  NativeBackHeader,
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  HarmonySkeletonHost,
  HarmonySkeletonBlock,
  HarmonyCardGridSkeleton,
  HarmonyPluginSheetSkeleton,
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

const DOWNLOADER_TYPES: string[][] = [
  ['qbittorrent', 'qBittorrent'],
  ['transmission', 'Transmission'],
  ['rtorrent', 'rTorrent']
];

const MEDIASERVER_TYPES: string[][] = [
  ['emby', 'Emby'],
  ['jellyfin', 'Jellyfin'],
  ['plex', 'Plex'],
  ['trimemedia', '飞牛影视'],
  ['ugreen', '绿联影视'],
  ['zspace', '极空间'],
  ['vyo', 'VYO']
];

const NOTIFICATION_TYPES: string[][] = [
  ['wechat', '企业微信'],
  ['telegram', 'Telegram'],
  ['feishu', '飞书'],
  ['dingtalk', '钉钉'],
  ['slack', 'Slack'],
  ['discord', 'Discord'],
  ['qq', 'QQ / NapCat'],
  ['synologychat', '群晖 Chat'],
  ['vocechat', 'VoceChat'],
  ['clawbot', 'ClawBot'],
  ['chrome', 'WebPush']
];

/**
 * 插件卡片圆角图标：优先渲染远程插件图标，加载中或远程不可达时自动回退至 `logo_plugin.png`。
 */
@Component
struct HarmonyPluginCardIcon {
  @Prop @Watch('onIconUrlChanged') iconUrl: string = '';
  @Prop pluginName: string = '';
  @State private pixelMap: image.PixelMap | null = null;
  private activeUrl: string = '';

  aboutToAppear(): void {
    this.syncIcon();
  }

  onIconUrlChanged(): void {
    this.syncIcon();
  }

  private syncIcon(): void {
    const target = (this.iconUrl ?? '').trim();
    this.activeUrl = target;
    if (!target || target.startsWith('data:image/')) {
      this.pixelMap = null;
      return;
    }
    const cached = MpImageLoader.getCached(target, 240);
    if (cached) {
      this.pixelMap = cached;
      return;
    }
    this.pixelMap = null;
    MpImageLoader.load(target, 240).then((pm: image.PixelMap | null) => {
      if (this.activeUrl === target && pm) {
        this.pixelMap = pm;
      }
    }).catch(() => {});
  }

  build() {
    if (this.iconUrl.startsWith('data:image/')) {
      Image(this.iconUrl)
        .width(44)
        .height(44)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)
    } else if (this.pixelMap) {
      Image(this.pixelMap)
        .width(44)
        .height(44)
        .borderRadius(12)
        .objectFit(ImageFit.Cover)
    } else {
      HarmonyEntityLogo({
        kind: 'plugin',
        value: this.pluginName,
        logoSize: 44,
        cornerRadius: 12
      })
    }
  }
}

/**
 * 鸿蒙「插件中心」独立页面：
 * - 支持「已安装 / 插件市场」切换、市场一键安装（`/api/v1/plugin/install/{id}`）、已安装重置与卸载确认；
 * - 未配置远程图标时统一回退品牌图标 `logo_plugin.png`，并联动系统返回手势关闭详情。
 */
@Component
export struct HarmonyPluginsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageProp('mp_plugin_detail_close_req') @Watch('onExternalCloseDetailReq') closeDetailReq: number = 0;
  @Prop serverUrl: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @State private activeTabIdx: number = 0; // 0: 已安装, 1: 插件市场
  @State private searchQuery: string = '';
  @State private installedPlugins: MpPluginItem[] = [];
  @State private marketPlugins: MpPluginItem[] = [];
  @State private marketLoadedOnce: boolean = false;
  @State private loading: boolean = true;
  @State private installingId: string = '';
  @State private listNotice: string = '';
  @State private activePlugin: MpPluginItem | null = null;
  @State private detailTabIndex: number = 0; // 0: 数据页, 1: 参数配置
  @State private forceWebView: boolean = false;
  @State private activeFormDoc: string = '{}';
  @State private activePageDoc: string = '{}';
  @State private loadingDetail: boolean = false;
  @State private actionBusy: boolean = false;
  @State private chromeTitle: string = '';
  @State private chromeActions: VueChromeAction[] = [];
  @State private saveNotice: string = '';
  private vueChromeController: HarmonyVueChromeController = new HarmonyVueChromeController();
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.syncDetailBackFlag(false);
    this.loadInstalled();
  }

  aboutToDisappear(): void {
    this.syncDetailBackFlag(false);
  }

  private syncDetailBackFlag(isOpen: boolean): void {
    AppStorage.setOrCreate('mp_plugin_detail_open', isOpen);
  }

  onExternalCloseDetailReq(): void {
    if (this.activePlugin !== null) {
      this.closePluginDetail();
    }
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

  private async loadMarketIfNeeded(force: boolean = false): Promise<void> {
    if (!force && this.marketPlugins.length > 0) { return; }
    this.loading = true;
    try {
      this.marketPlugins = await MoviePilotRepository.shared().fetchPlugins('market');
      this.marketLoadedOnce = true;
    } catch {
      this.marketPlugins = [];
      this.marketLoadedOnce = true;
    }
    this.loading = false;
  }

  private isInstalledInList(pluginId: string): boolean {
    return this.installedPlugins.some((p: MpPluginItem) => p.id === pluginId);
  }

  private filteredPlugins(): MpPluginItem[] {
    const src = this.activeTabIdx === 0 ? this.installedPlugins : this.marketPlugins;
    const q = this.searchQuery.trim().toLowerCase();
    if (!q) { return src.slice(0, 80); }
    return src.filter((p: MpPluginItem) =>
      `${p.pluginName} ${p.pluginDesc} ${p.pluginAuthor} ${p.id}`.toLowerCase().includes(q)
    ).slice(0, 80);
  }

  private async handleInstallPlugin(pl: MpPluginItem): Promise<void> {
    if (this.installingId.length > 0) { return; }
    this.installingId = pl.id;
    this.listNotice = '';
    const ok = await MoviePilotRepository.shared().installPlugin(pl.id, pl.repoUrl ?? '');
    this.installingId = '';
    this.listNotice = ok ? `已安装插件「${pl.pluginName}」` : `安装插件「${pl.pluginName}」失败`;
    if (ok) {
      await Promise.all([this.loadInstalled(), this.loadMarketIfNeeded(true)]);
    }
  }

  private async handleResetActivePlugin(): Promise<void> {
    const pl = this.activePlugin;
    if (!pl || this.actionBusy) { return; }
    this.actionBusy = true;
    const ok = await MoviePilotRepository.shared().resetPlugin(pl.id);
    this.actionBusy = false;
    this.saveNotice = ok ? `已重置插件「${pl.pluginName}」数据与配置` : '重置插件失败';
    if (ok) {
      await this.openPluginDetail(pl);
    }
  }

  private confirmUninstallActivePlugin(): void {
    const pl = this.activePlugin;
    if (!pl) { return; }
    this.getUIContext().showAlertDialog({
      title: '卸载插件',
      message: `确定要卸载插件「${pl.pluginName}」吗？卸载后插件配置与运行任务将被移除。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认卸载',
        fontColor: '#E84855',
        action: () => {
          this.executeUninstallPlugin(pl);
        }
      }
    });
  }

  private async executeUninstallPlugin(pl: MpPluginItem): Promise<void> {
    this.actionBusy = true;
    const ok = await MoviePilotRepository.shared().uninstallPlugin(pl.id);
    this.actionBusy = false;
    if (ok) {
      this.activePlugin = null;
      this.syncDetailBackFlag(false);
      this.listNotice = `已卸载插件「${pl.pluginName}」`;
      await Promise.all([this.loadInstalled(), this.marketPlugins.length > 0 ? this.loadMarketIfNeeded(true) : Promise.resolve()]);
    } else {
      this.saveNotice = '卸载插件失败，请检查后端状态';
    }
  }

  private async openPluginDetail(pl: MpPluginItem): Promise<void> {
    this.activePlugin = pl;
    this.syncDetailBackFlag(true);
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
    this.syncDetailBackFlag(false);
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

        // 插件管理动作条（重置与卸载）
        Row({ space: 8 }) {
          if (this.activePlugin.pluginVersion.length > 0) {
            NativeAdaptiveBadge({ text: `v${this.activePlugin.pluginVersion}`, tintHex: this.accentHex })
          }
          Blank()
          NativeAdaptivePill({
            title: '重置插件',
            selected: false,
            onTap: () => { this.handleResetActivePlugin(); }
          })
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(13).fontColor(['#E84855'])
            Text('卸载').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor('#E84855')
          }
          .padding({ left: 10, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
          .onClick(() => this.confirmUninstallActivePlugin())
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

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
          Scroll() {
            Column() {
              HarmonyPluginSheetSkeleton()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .layoutWeight(1)
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
            onRequestDismiss: () => {
              this.activePlugin = null;
              this.syncDetailBackFlag(false);
            }
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
            onRequestDismiss: () => {
              this.activePlugin = null;
              this.syncDetailBackFlag(false);
            },
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
          onTrailingClick: () => {
            if (this.activeTabIdx === 0) {
              this.loadInstalled();
            } else {
              this.loadMarketIfNeeded(true);
            }
          }
        })

        HarmonyPillTabBar({
          tabs: [
            (this.loading && this.activeTabIdx === 0 && this.installedPlugins.length === 0)
              ? '已安装'
              : `已安装 (${this.installedPlugins.length})`,
            ((this.loading && this.activeTabIdx === 1 && this.marketPlugins.length === 0) || (!this.marketLoadedOnce && this.marketPlugins.length === 0))
              ? '插件市场'
              : `插件市场 (${this.marketPlugins.length})`
          ],
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

        if (this.listNotice.length > 0) {
          Text(this.listNotice)
            .fontSize(12)
            .fontColor('#34C759')
            .padding({ left: 16, right: 16 })
            .width('100%')
        }

        if (this.loading && (this.activeTabIdx === 0 ? this.installedPlugins.length === 0 : this.marketPlugins.length === 0)) {
          HarmonyCardGridSkeleton({
            variant: 'plugin',
            fillViewport: true,
            bottomPadding: 44
          })
        } else if (this.filteredPlugins().length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.puzzle')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
            Text('暂无匹配的插件条目').fontSize(14).fontColor(mpSecondaryText(this.isDark))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.filteredPlugins(), (pl: MpPluginItem) => {
              GridItem() {
                Column() {
                  CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: this.activeTabIdx === 0 }) {
                    Row({ space: 12 }) {
                      HarmonyPluginCardIcon({
                        iconUrl: pl.iconUrl,
                        pluginName: pl.pluginName
                      })

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
                      } else if (pl.installed || this.isInstalledInList(pl.id)) {
                        NativeAdaptiveBadge({ text: '已安装', tintHex: '#34C759' })
                      } else {
                        Button(this.installingId === pl.id ? '安装中…' : '安装')
                          .height(30).padding({ left: 12, right: 12 }).borderRadius(15)
                          .fontSize(12).fontWeight(FontWeight.Bold)
                          .backgroundColor(this.accentHex).fontColor(Color.White)
                          .enabled(this.installingId.length === 0)
                          .onClick(() => { this.handleInstallPlugin(pl); })
                      }
                    }.width('100%')
                  }
                }
                .width('100%')
                .onClick(() => {
                  if (this.activeTabIdx === 0) {
                    this.openPluginDetail(pl);
                  } else if (this.isInstalledInList(pl.id)) {
                    const installed = this.installedPlugins.find((x: MpPluginItem) => x.id === pl.id);
                    if (installed) { this.openPluginDetail(installed); }
                  }
                })
              }
            }, (pl: MpPluginItem) => `${this.activeTabIdx}_${pl.id}_${this.isInstalledInList(pl.id)}`)
          }
          .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
          .columnsGap(10)
          .rowsGap(10)
          .padding({ left: 16, right: 16, top: 2, bottom: 44 })
          .scrollBar(BarState.Off)
          .layoutWeight(1)
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
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop title: string = '';
  @Prop sub: string = '';
  @Prop loadingSub: boolean = false;
  @Prop symbolName: string = '';
  @Prop symbolTint: string = '';
  @Prop logoKind: string = '';
  @Prop logoValue: string = '';
  onTap: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      if (this.logoKind.length > 0) {
        HarmonyEntityLogo({
          kind: this.logoKind,
          value: this.logoValue,
          logoSize: 28,
          cornerRadius: 7
        })
      } else if (this.symbolName.length > 0) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r(this.symbolName))
            .fontSize(16)
            .fontColor([this.symbolTint.length > 0 ? this.symbolTint : this.accentHex])
        }
        .width(28)
        .height(28)
        .borderRadius(8)
        .backgroundColor(HarmonyAppearanceStore.withAlpha(
          this.symbolTint.length > 0 ? this.symbolTint : this.accentHex,
          this.isDark ? '26' : '18'
        ))
      }

      Text(this.title).fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
      if (this.loadingSub) {
        HarmonySkeletonBlock({ blockWidth: 52, blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
      } else {
        Text(this.sub).fontSize(12.5).fontColor(mpSecondaryText(this.isDark)).maxLines(1)
      }
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([mpSecondaryText(this.isDark)])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onTap())
  }
}

/**
 * 鸿蒙「设置」主中心（全量对齐 iOS 功能、36 枚品牌图标与安全删除确认）：
 * - 顶部 3 枚磁贴：「站点管理 / 用户管理 / 渠道授权（含 5 分钟绑定码生成与审批撤销）」；
 * - 基础配置完整覆盖「媒体数据源」「订阅与搜索」「下载器」「媒体服务器」「整理与目录」「播放偏好」；
 * - 全部设置行配备前置图标，服务与目录删除统一经系统 `showAlertDialog` 二次确认；
 * - 外观中心支持「显示悬浮智能助手」开关并通过 `NativeHuksStore` 跨重启持久化。
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
  @StorageLink(HarmonyAppearanceStore.KEY_SHOW_AI_MASCOT) showAiMascot: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
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
  @State private authorizations: MpAuthorizationItem[] = [];
  @State private community: MpCommunityState = { githubLogin: 'MoviePilot', earnedCount: 0, totalCount: 7, medals: [] };
  @State private loadingSummary: boolean = true;
  @State private hasLoadedSummaryOnce: boolean = false;
  @State private loadingAuth: boolean = false;
  @State private notice: string = '';

  // 弹层开关
  @State private showAppearanceSheet: boolean = false;
  @State private showUsersSheet: boolean = false;
  @State private showAuthorizationSheet: boolean = false;
  @State private showMediaSourcesSheet: boolean = false;
  @State private showSubscribeSearchSheet: boolean = false;
  @State private showDownloadersSheet: boolean = false;
  @State private showMediaServersSheet: boolean = false;
  @State private showDirectoriesSheet: boolean = false;
  @State private showNotificationsSheet: boolean = false;
  @State private showNotifEditorSheet: boolean = false;
  @State private showPlaybackSheet: boolean = false;
  @State private showMedalsSheet: boolean = false;
  @State private activeMedalIdx: number = 0;
  @State private medalBusy: boolean = false;
  @State private medalNotice: string = '';
  @State private playbackSpeedIdx: number = 1;
  @State private playbackQualityIdx: number = 0;
  @State private playbackPip: boolean = true;

  // 渠道授权状态
  @State private authCode: string = '';
  @State private authCodeHint: string = '';
  @State private authGenerating: boolean = false;

  // 媒体数据源 & 订阅与搜索系统设置状态
  @State private recognizeSource: string = 'themoviedb';
  @State private scrapSource: string = 'themoviedb';
  @State private mediaServerSync: boolean = true;
  @State private savingMediaSources: boolean = false;
  @State private searchSource: string = 'themoviedb';
  @State private subscribeMode: string = 'spider';
  @State private subscribeSearchNow: boolean = false;
  @State private searchMultipleName: boolean = true;
  @State private savingSubSearch: boolean = false;

  // 通知渠道编辑状态
  @State private notifCreate: boolean = true;
  @State private notifOrigName: string = '';
  @State private notifName: string = '';
  @State private notifType: string = 'wechat';
  @State private notifEnabled: boolean = true;
  @State private notifSaving: boolean = false;

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
  onSwitchServer: () => void = () => {};
  onLogout: () => void = () => {};

  aboutToAppear(): void {
    this.loadSettingsSummary();
  }

  private persistAppearanceToDisk(): void {
    NativeHuksStore.shared().saveAppearanceJson(HarmonyAppearanceStore.exportSnapshot()).catch(() => {});
  }

  private async loadSettingsSummary(): Promise<void> {
    if (!this.hasLoadedSummaryOnce) {
      this.loadingSummary = true;
    }
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
        repo.fetchSystemSettingList('Notifications'),
        repo.fetchAuthorizations(),
        repo.fetchSystemSettingString('RECOGNIZE_SOURCE', 'themoviedb'),
        repo.fetchSystemSettingString('SCRAP_SOURCE', 'themoviedb'),
        repo.fetchSystemSettingBool('MEDIASERVER_SYNC', true),
        repo.fetchSystemSettingString('SEARCH_SOURCE', 'themoviedb'),
        repo.fetchSystemSettingString('SUBSCRIBE_MODE', 'spider'),
        repo.fetchSystemSettingBool('SUBSCRIBE_SEARCH', false),
        repo.fetchSystemSettingBool('SEARCH_MULTIPLE_NAME', true)
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
      this.authorizations = res[9];
      this.recognizeSource = res[10];
      this.scrapSource = res[11];
      this.mediaServerSync = res[12];
      this.searchSource = res[13];
      this.subscribeMode = res[14];
      this.subscribeSearchNow = res[15];
      this.searchMultipleName = res[16];
    } catch {
      // ignore
    }
    this.hasLoadedSummaryOnce = true;
    this.loadingSummary = false;
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

  private primaryDownloaderType(): string {
    if (this.downloaders.length > 0) {
      const def = this.downloaders.find((d: MpServiceConfig) => d.isDefault);
      return def ? (def.type || def.name) : (this.downloaders[0].type || this.downloaders[0].name);
    }
    return 'downloader';
  }

  private primaryMediaServerType(): string {
    if (this.mediaServers.length > 0) {
      return this.mediaServers[0].type || this.mediaServers[0].name;
    }
    return 'mediaserver';
  }

  private primaryStorageType(): string {
    if (this.directories.length > 0 && this.directories[0].storage.length > 0) {
      return this.directories[0].storage;
    }
    if (this.storages.length > 0) {
      return this.storages[0].type;
    }
    return 'local';
  }

  private primaryNotificationType(): string {
    if (this.notifications.length > 0) {
      return this.notifications[0].type || this.notifications[0].name;
    }
    return 'notification';
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

  private openNotifEditor(item: MpSimpleSettingItem | null): void {
    this.notifCreate = item === null;
    this.notifOrigName = item ? item.name : '';
    this.notifName = item ? item.name : '';
    this.notifType = item && item.type.length > 0 ? item.type : 'wechat';
    this.notifEnabled = item ? item.enabled : true;
    this.showNotifEditorSheet = true;
  }

  private async saveNotifChannel(): Promise<void> {
    if (this.notifSaving || this.notifName.trim().length === 0) { return; }
    this.notifSaving = true;
    const ok = await MoviePilotRepository.shared().saveNotificationChannel(
      this.notifName.trim(),
      this.notifType,
      this.notifEnabled,
      this.notifCreate ? null : this.notifOrigName
    );
    this.notifSaving = false;
    this.showNotifEditorSheet = false;
    this.notice = ok ? `已保存通知渠道「${this.notifName.trim()}」` : '保存通知渠道失败';
    await this.loadSettingsSummary();
  }

  private confirmDeleteNotif(name: string): void {
    this.getUIContext().showAlertDialog({
      title: '删除通知渠道',
      message: `确定要删除通知渠道「${name}」吗？`,
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确认删除',
        fontColor: '#E84855',
        action: () => {
          MoviePilotRepository.shared().deleteNotificationChannel(name).then(async (ok: boolean) => {
            this.showNotifEditorSheet = false;
            this.notice = ok ? `已删除通知渠道「${name}」` : '删除失败';
            await this.loadSettingsSummary();
          });
        }
      }
    });
  }

  private async saveMediaSourcesSettings(): Promise<void> {
    if (this.savingMediaSources) { return; }
    this.savingMediaSources = true;
    const repo = MoviePilotRepository.shared();
    const res = await Promise.all([
      repo.saveSystemSettingScalar('RECOGNIZE_SOURCE', JSON.stringify(this.recognizeSource)),
      repo.saveSystemSettingScalar('SCRAP_SOURCE', JSON.stringify(this.scrapSource)),
      repo.saveSystemSettingScalar('MEDIASERVER_SYNC', this.mediaServerSync ? 'true' : 'false')
    ]);
    this.savingMediaSources = false;
    this.showMediaSourcesSheet = false;
    this.notice = (res[0] || res[1]) ? '已保存媒体数据源配置' : '保存媒体数据源失败';
  }

  private async saveSubscribeSearchSettings(): Promise<void> {
    if (this.savingSubSearch) { return; }
    this.savingSubSearch = true;
    const repo = MoviePilotRepository.shared();
    const res = await Promise.all([
      repo.saveSystemSettingScalar('SEARCH_SOURCE', JSON.stringify(this.searchSource)),
      repo.saveSystemSettingScalar('SUBSCRIBE_MODE', JSON.stringify(this.subscribeMode)),
      repo.saveSystemSettingScalar('SUBSCRIBE_SEARCH', this.subscribeSearchNow ? 'true' : 'false'),
      repo.saveSystemSettingScalar('SEARCH_MULTIPLE_NAME', this.searchMultipleName ? 'true' : 'false')
    ]);
    this.savingSubSearch = false;
    this.showSubscribeSearchSheet = false;
    this.notice = (res[0] || res[1]) ? '已保存订阅与搜索设置' : '保存订阅与搜索设置失败';
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

  private confirmDeleteItem(kind: string, name: string): void {
    const kindLabel = kind === 'downloader' ? '下载器' : (kind === 'mediaserver' ? '媒体服务器' : '整理目录');
    this.getUIContext().showAlertDialog({
      title: `删除${kindLabel}`,
      message: `确定要删除${kindLabel}「${name}」吗？此操作无法撤销。`,
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '确认删除',
        fontColor: '#E84855',
        action: () => {
          this.executeDeleteItem(kind, name);
        }
      }
    });
  }

  private async executeDeleteItem(kind: string, name: string): Promise<void> {
    const repo = MoviePilotRepository.shared();
    let ok = false;
    if (kind === 'downloader') {
      ok = await repo.deleteDownloader(name);
    } else if (kind === 'mediaserver') {
      ok = await repo.deleteMediaServer(name);
    } else {
      ok = await repo.deleteDirectory(name);
    }
    this.showCrudEditor = false;
    this.notice = ok ? `已删除「${name}」` : '删除失败';
    await this.loadSettingsSummary();
  }

  private copyTextToClipboard(text: string): void {
    try {
      const pbData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(pbData);
      this.authCodeHint = '已复制绑定码到系统剪贴板';
    } catch {
      this.authCodeHint = '复制失败，请手动记录上方绑定码';
    }
  }

  @Builder
  authorizationSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: ((this.loadingSummary || this.loadingAuth) && this.authorizations.length === 0)
          ? '渠道授权'
          : `渠道授权 (${this.authorizations.length})`,
        cancelText: '关闭',
        actionText: this.loadingAuth ? '加载中' : '刷新',
        actionEnabled: !this.loadingAuth,
        onCancel: () => { this.showAuthorizationSheet = false; },
        onAction: async () => {
          this.loadingAuth = true;
          try {
            this.authorizations = await MoviePilotRepository.shared().fetchAuthorizations();
          } catch {
            // keep existing authorizations
          }
          this.loadingAuth = false;
        }
      })

      Scroll() {
        Column({ space: 12 }) {
          CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Text('外部机器人 / 渠道会话绑定')
                .fontSize(14.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
              Text('生成 5 分钟有效绑定码后，在 Telegram / 微信 / 飞书等机器人对话中发送绑定命令即可关联当前管理员身份。')
                .fontSize(12).fontColor(mpSecondaryText(this.isDark)).lineHeight(18).width('100%')

              if (this.authCode.length > 0) {
                Row({ space: 10 }) {
                  Text(this.authCode)
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.accentHex)
                    .letterSpacing(2)
                    .layoutWeight(1)
                  Button('复制')
                    .height(34).padding({ left: 14, right: 14 }).borderRadius(17)
                    .fontSize(12.5).fontWeight(FontWeight.Bold)
                    .backgroundColor(this.accentHex).fontColor(Color.White)
                    .onClick(() => this.copyTextToClipboard(this.authCode))
                }
                .width('100%')
                .padding(12)
                .borderRadius(14)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              }

              if (this.authCodeHint.length > 0) {
                Text(this.authCodeHint).fontSize(11.5).fontColor('#34C759').width('100%')
              }

              Button(this.authGenerating ? '正在生成绑定码…' : '生成 5 分钟绑定码')
                .width('100%').height(42).borderRadius(21)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '2C' : '18'))
                .fontColor(this.accentHex).fontWeight(FontWeight.Bold)
                .enabled(!this.authGenerating)
                .onClick(async () => {
                  this.authGenerating = true;
                  const res = await MoviePilotRepository.shared().generateAuthorizationCode();
                  this.authGenerating = false;
                  this.authCode = res.code;
                  this.authCodeHint = res.message;
                  this.authorizations = await MoviePilotRepository.shared().fetchAuthorizations();
                })
            }
          }

          Text('授权会话与待审批请求').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          if ((this.loadingSummary || this.loadingAuth) && this.authorizations.length === 0) {
            HarmonyCardGridSkeleton({
              variant: 'service',
              singleColumn: true,
              count: 3,
              horizontalPadding: 0,
              bottomPadding: 8
            })
          } else if (this.authorizations.length === 0) {
            CinematicPanel({ panelPadding: 20, cornerRadius: 16 }) {
              Text('当前没有外部渠道授权会话或待审批请求')
                .fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%').textAlign(TextAlign.Center)
            }
          } else {
            ForEach(this.authorizations, (auth: MpAuthorizationItem) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Row({ space: 10 }) {
                  HarmonyEntityLogo({
                    kind: 'notification',
                    value: auth.channel,
                    logoSize: 32,
                    cornerRadius: 8
                  })
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(auth.name).fontSize(14.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      NativeAdaptiveBadge({
                        text: auth.approved ? '已授权' : '待审批',
                        tintHex: auth.approved ? '#34C759' : '#F29B38'
                      })
                    }
                    Text(`${auth.channel}${auth.createdAt ? ' · ' + auth.createdAt : ''}`)
                      .fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                  if (!auth.approved) {
                    Button('批准')
                      .height(30).padding({ left: 12, right: 12 }).borderRadius(15)
                      .fontSize(12).fontWeight(FontWeight.Bold)
                      .backgroundColor('#34C759').fontColor(Color.White)
                      .onClick(async () => {
                        const ok = await MoviePilotRepository.shared().approveAuthorization(auth.id);
                        this.authCodeHint = ok ? `已批准「${auth.name}」` : '审批失败';
                        this.authorizations = await MoviePilotRepository.shared().fetchAuthorizations();
                      })
                  }
                  Button('撤销')
                    .height(30).padding({ left: 12, right: 12 }).borderRadius(15)
                    .fontSize(12).fontColor('#E84855')
                    .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                    .onClick(() => {
                      this.getUIContext().showAlertDialog({
                        title: '撤销渠道授权',
                        message: `确定撤销「${auth.name}」的访问授权吗？`,
                        autoCancel: true,
                        primaryButton: { value: '取消', action: () => {} },
                        secondaryButton: {
                          value: '确认撤销',
                          fontColor: '#E84855',
                          action: () => {
                            MoviePilotRepository.shared().revokeAuthorization(auth.id).then(async (ok: boolean) => {
                              this.authCodeHint = ok ? `已撤销「${auth.name}」` : '撤销失败';
                              this.authorizations = await MoviePilotRepository.shared().fetchAuthorizations();
                            });
                          }
                        }
                      });
                    })
                }.width('100%')
              }
            }, (auth: MpAuthorizationItem) => `${auth.id}_${auth.approved}`)
          }
        }.padding({ bottom: 24 })
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  mediaSourcesSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '媒体数据源',
        cancelText: '取消',
        actionText: this.savingMediaSources ? '保存中' : '保存',
        actionEnabled: !this.savingMediaSources,
        onCancel: () => { this.showMediaSourcesSheet = false; },
        onAction: () => { this.saveMediaSourcesSettings(); }
      })

      Scroll() {
        Column({ space: 14 }) {
          Text('媒体识别数据源').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 10 }) {
              Text('下载与整理时优先用于解析片名与季集信息的数据源：')
                .fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
                HarmonyEntityLogoPill({
                  kind: 'media_source', value: 'themoviedb', title: 'TheMovieDB',
                  selected: this.recognizeSource === 'themoviedb',
                  onTap: () => { this.recognizeSource = 'themoviedb'; }
                })
                HarmonyEntityLogoPill({
                  kind: 'media_source', value: 'douban', title: '豆瓣',
                  selected: this.recognizeSource === 'douban',
                  onTap: () => { this.recognizeSource = 'douban'; }
                })
              }.width('100%')
            }
          }

          Text('元数据刮削数据源').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 10 }) {
              Text('生成本地 NFO 与海报背景图时优先采用的数据源：')
                .fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
                HarmonyEntityLogoPill({
                  kind: 'media_source', value: 'themoviedb', title: 'TheMovieDB',
                  selected: this.scrapSource === 'themoviedb',
                  onTap: () => { this.scrapSource = 'themoviedb'; }
                })
                HarmonyEntityLogoPill({
                  kind: 'media_source', value: 'douban', title: '豆瓣',
                  selected: this.scrapSource === 'douban',
                  onTap: () => { this.scrapSource = 'douban'; }
                })
                HarmonyEntityLogoPill({
                  kind: 'media_source', value: 'bangumi', title: 'Bangumi',
                  selected: this.scrapSource === 'bangumi',
                  onTap: () => { this.scrapSource = 'bangumi'; }
                })
              }.width('100%')
            }
          }

          Text('已接入元数据网络').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 12 }) {
              Row({ space: 12 }) {
                HarmonyEntityLogo({ kind: 'media_source', value: 'tmdb', logoSize: 26, cornerRadius: 6 })
                HarmonyEntityLogo({ kind: 'media_source', value: 'douban', logoSize: 26, cornerRadius: 6 })
                HarmonyEntityLogo({ kind: 'media_source', value: 'bangumi', logoSize: 26, cornerRadius: 6 })
                HarmonyEntityLogo({ kind: 'media_source', value: 'musicbrainz', logoSize: 26, cornerRadius: 6 })
                Text('影视 · 番剧 · MusicBrainz 音乐').fontSize(12).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
              }.width('100%')

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row() {
                Column({ space: 2 }) {
                  Text('同步媒体服务器入库状态').fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text('在发现与探索卡片上实时展示媒体库已入库标记').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.mediaServerSync })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => { this.mediaServerSync = v; })
              }.width('100%')
            }
          }
        }.padding({ bottom: 24 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  subscribeSearchSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '订阅与搜索',
        cancelText: '取消',
        actionText: this.savingSubSearch ? '保存中' : '保存',
        actionEnabled: !this.savingSubSearch,
        onCancel: () => { this.showSubscribeSearchSheet = false; },
        onAction: () => { this.saveSubscribeSearchSettings(); }
      })

      Scroll() {
        Column({ space: 14 }) {
          Text('媒体搜索数据源').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
              HarmonyEntityLogoPill({
                kind: 'media_source', value: 'themoviedb', title: 'TheMovieDB',
                selected: this.searchSource === 'themoviedb',
                onTap: () => { this.searchSource = 'themoviedb'; }
              })
              HarmonyEntityLogoPill({
                kind: 'media_source', value: 'douban', title: '豆瓣',
                selected: this.searchSource === 'douban',
                onTap: () => { this.searchSource = 'douban'; }
              })
              HarmonyEntityLogoPill({
                kind: 'media_source', value: 'bangumi', title: 'Bangumi',
                selected: this.searchSource === 'bangumi',
                onTap: () => { this.searchSource = 'bangumi'; }
              })
              HarmonyEntityLogoPill({
                kind: 'media_source', value: 'musicbrainz', title: 'MusicBrainz',
                selected: this.searchSource === 'musicbrainz',
                onTap: () => { this.searchSource = 'musicbrainz'; }
              })
            }.width('100%')
          }

          Text('订阅运行模式').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          HarmonySegmentedSwitch({
            options: ['自动爬虫检索', '站点 RSS 刷新'],
            selectedIndex: this.subscribeMode === 'rss' ? 1 : 0,
            onSelect: (idx: number) => {
              this.subscribeMode = idx === 1 ? 'rss' : 'spider';
            }
          })

          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 12 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('新增订阅后立即搜索').fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text('添加订阅时立即触发一次全站种子检索下载').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.subscribeSearchNow })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => { this.subscribeSearchNow = v; })
              }.width('100%')

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row() {
                Column({ space: 2 }) {
                  Text('中英文多名称联合搜索').fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text('同时使用中文译名与原始外文名扩大站点命中率').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.searchMultipleName })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => { this.searchMultipleName = v; })
              }.width('100%')
            }
          }
        }.padding({ bottom: 24 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  appearanceSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '主题与外观',
        cancelText: '完成',
        actionText: '恢复默认',
        onCancel: () => {
          this.persistAppearanceToDisk();
          this.showAppearanceSheet = false;
        },
        onAction: () => {
          HarmonyAppearanceStore.resetDefaults();
          this.persistAppearanceToDisk();
        }
      })

      Scroll() {
        Column({ space: 14 }) {
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
              this.persistAppearanceToDisk();
            }
          })

          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 12 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('AMOLED 纯黑模式').fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text('深色画布切换纯黑 #000000，极致对比与省电').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.pureBlack })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => {
                    this.pureBlack = v;
                    this.persistAppearanceToDisk();
                  })
              }.width('100%')

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row() {
                Column({ space: 2 }) {
                  Text('显示悬浮智能助手').fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text('在主界面展示可自由拖拽的 MoviePilot 紫色机器人助手').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.showAiMascot })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => {
                    this.showAiMascot = v;
                    this.persistAppearanceToDisk();
                  })
              }.width('100%')
            }
          }

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
                .onClick(() => {
                  HarmonyAppearanceStore.applyPalette(p.id, this.isDark);
                  this.persistAppearanceToDisk();
                })
              }
            }, (p: HarmonyPalettePreset) => p.id)
          }
          .columnsTemplate(this.windowWidthVp >= 680 ? '1fr 1fr 1fr' : '1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

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
                  .onChange((v: boolean) => {
                    this.dynamicLight = v;
                    this.persistAppearanceToDisk();
                  })
              }.width('100%')

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text('顶部光感微光').fontSize(14.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text('随当前鸿蒙色板柔化顶部光影层次').fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.animateBg })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => {
                    this.animateBg = v;
                    this.persistAppearanceToDisk();
                  })
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
        title: (this.loadingSummary && this.downloaders.length === 0)
          ? '下载器'
          : `下载器 (${this.downloaders.length})`,
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
          if (this.loadingSummary && this.downloaders.length === 0) {
            HarmonyCardGridSkeleton({
              variant: 'service',
              singleColumn: true,
              count: 3,
              horizontalPadding: 0,
              bottomPadding: 8
            })
          } else if (this.downloaders.length === 0) {
            Text('暂未配置下载器，点击右上角「新增」添加').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.downloaders, (dl: MpServiceConfig) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Row({ space: 10 }) {
                  HarmonyEntityLogo({
                    kind: 'downloader',
                    value: dl.type || dl.name,
                    logoSize: 34,
                    cornerRadius: 9
                  })
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(dl.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      if (dl.isDefault) { NativeAdaptiveBadge({ text: '默认', tintHex: this.accentHex }) }
                    }
                    Text(`${dl.type} · ${dl.host || '已配置'}`).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                      .maxLines(1).wordBreak(WordBreak.BREAK_ALL).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.showDownloadersSheet = false;
                    this.openServiceCrud('downloader', dl);
                  })

                  NativeAdaptiveBadge({ text: dl.enabled ? '已启用' : '已停用', tintHex: dl.enabled ? '#34C759' : '#F29B38' })

                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor(['#E84855'])
                  }
                  .width(30).height(30)
                  .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                  .onClick(() => this.confirmDeleteItem('downloader', dl.name))
                }.width('100%')
              }
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
        title: (this.loadingSummary && this.mediaServers.length === 0)
          ? '媒体服务器'
          : `媒体服务器 (${this.mediaServers.length})`,
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
          if (this.loadingSummary && this.mediaServers.length === 0) {
            HarmonyCardGridSkeleton({
              variant: 'service',
              singleColumn: true,
              count: 3,
              horizontalPadding: 0,
              bottomPadding: 8
            })
          } else if (this.mediaServers.length === 0) {
            Text('暂未配置媒体服务器，点击右上角「新增」添加').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.mediaServers, (ms: MpServiceConfig) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Row({ space: 10 }) {
                  HarmonyEntityLogo({
                    kind: 'mediaserver',
                    value: ms.type || ms.name,
                    logoSize: 34,
                    cornerRadius: 9
                  })
                  Column({ space: 3 }) {
                    Text(ms.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    Text(`${ms.type} · ${ms.host || '已配置'}`).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                      .maxLines(1).wordBreak(WordBreak.BREAK_ALL).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.showMediaServersSheet = false;
                    this.openServiceCrud('mediaserver', ms);
                  })

                  NativeAdaptiveBadge({ text: ms.enabled ? '已启用' : '已停用', tintHex: ms.enabled ? '#34C759' : '#F29B38' })

                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor(['#E84855'])
                  }
                  .width(30).height(30)
                  .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                  .onClick(() => this.confirmDeleteItem('mediaserver', ms.name))
                }.width('100%')
              }
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
        title: (this.loadingSummary && this.directories.length === 0)
          ? '整理与目录'
          : `整理与目录 (${this.directories.length})`,
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
          if (this.loadingSummary && this.directories.length === 0) {
            HarmonyCardGridSkeleton({
              variant: 'service',
              singleColumn: true,
              count: 3,
              horizontalPadding: 0,
              bottomPadding: 8
            })
          }
          ForEach(this.directories, (d: MpDirectoryConfig) => {
            CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  HarmonyEntityLogo({
                    kind: 'storage',
                    value: d.libraryStorage || d.storage || 'local',
                    logoSize: 22,
                    cornerRadius: 6
                  })
                  NativeAdaptiveBadge({ text: `#${d.priority}`, tintHex: this.accentHex })
                  Text(d.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    .layoutWeight(1)
                    .onClick(() => {
                      this.showDirectoriesSheet = false;
                      this.openDirectoryCrud(d);
                    })
                  NativeAdaptiveBadge({ text: d.transferType, tintHex: '#34C759' })
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor(['#E84855'])
                  }
                  .width(30).height(30)
                  .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                  .onClick(() => this.confirmDeleteItem('directory', d.name))
                }.width('100%')

                Column({ space: 4 }) {
                  if (d.downloadPath.length > 0) {
                    Row({ space: 5 }) {
                      HarmonyEntityLogo({ kind: 'storage', value: d.storage, logoSize: 14, cornerRadius: 3 })
                      Text(`源 (${d.storage})：${d.downloadPath}`).fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(1).layoutWeight(1)
                    }.width('100%')
                  }
                  if (d.libraryPath.length > 0) {
                    Row({ space: 5 }) {
                      HarmonyEntityLogo({ kind: 'storage', value: d.libraryStorage, logoSize: 14, cornerRadius: 3 })
                      Text(`库 (${d.libraryStorage})：${d.libraryPath}`).fontSize(12).fontColor(this.accentHex).maxLines(1).layoutWeight(1)
                    }.width('100%')
                  }
                }
                .width('100%')
                .onClick(() => {
                  this.showDirectoriesSheet = false;
                  this.openDirectoryCrud(d);
                })
              }
            }
          }, (d: MpDirectoryConfig) => `${d.name}_${d.priority}`)

          if (this.storages.length > 0) {
            Text(`已挂载存储 (${this.storages.length})`).fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Column({ space: 10 }) {
                ForEach(this.storages, (st: MpStorageConfig) => {
                  Row({ space: 10 }) {
                    HarmonyEntityLogo({ kind: 'storage', value: st.type, logoSize: 24, cornerRadius: 6 })
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
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
              ForEach(DOWNLOADER_TYPES, (opt: string[]) => {
                HarmonyEntityLogoPill({
                  kind: 'downloader',
                  value: opt[0],
                  title: opt[1],
                  selected: this.crudType === opt[0],
                  onTap: () => { this.crudType = opt[0]; }
                })
              }, (opt: string[]) => `dl_ty_${opt[0]}`)
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
              ForEach(MEDIASERVER_TYPES, (opt: string[]) => {
                HarmonyEntityLogoPill({
                  kind: 'mediaserver',
                  value: opt[0],
                  title: opt[1],
                  selected: this.crudType === opt[0],
                  onTap: () => { this.crudType = opt[0]; }
                })
              }, (opt: string[]) => `ms_ty_${opt[0]}`)
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
                HarmonyEntityLogoPill({
                  kind: 'storage',
                  value: st.type,
                  title: st.name || st.type,
                  selected: this.dirStorage === st.type,
                  onTap: () => { this.dirStorage = st.type; }
                })
              }, (st: MpStorageConfig) => `ds_${st.type}`)
            }.width('100%')
            TextInput({ placeholder: '下载目录路径', text: this.dirDlPath }).fontColor(mpPrimaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.dirDlPath = v; })
            Text('目标存储与媒体库路径').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
              ForEach(this.storages, (st: MpStorageConfig) => {
                HarmonyEntityLogoPill({
                  kind: 'storage',
                  value: st.type,
                  title: st.name || st.type,
                  selected: this.dirLibStorage === st.type,
                  onTap: () => { this.dirLibStorage = st.type; }
                })
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

          if (!this.crudCreate && this.crudOrigName.length > 0) {
            Button('删除此项配置')
              .width('100%').height(44).borderRadius(22)
              .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
              .fontColor('#E84855').fontWeight(FontWeight.Bold)
              .onClick(() => this.confirmDeleteItem(this.crudKind, this.crudOrigName))
          }
        }.padding({ bottom: 24 })
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  usersSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: (this.loadingSummary && this.users.length === 0)
          ? '用户管理'
          : `用户管理 (${this.users.length})`,
        cancelText: '关闭',
        onCancel: () => { this.showUsersSheet = false; }
      })
      Scroll() {
        Column({ space: 10 }) {
          if (this.loadingSummary && this.users.length === 0) {
            HarmonyCardGridSkeleton({
              variant: 'service',
              singleColumn: true,
              count: 3,
              horizontalPadding: 0,
              bottomPadding: 8
            })
          } else {
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
                    HarmonyEntityLogo({
                      kind: 'avatar',
                      value: u.name,
                      logoSize: 42,
                      cornerRadius: 21
                    })
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
        }
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  notificationsSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: (this.loadingSummary && this.notifications.length === 0)
          ? '通知渠道'
          : `通知渠道 (${this.notifications.length})`,
        cancelText: '关闭',
        actionText: '新增',
        onCancel: () => { this.showNotificationsSheet = false; },
        onAction: () => {
          this.showNotificationsSheet = false;
          this.openNotifEditor(null);
        }
      })
      Scroll() {
        Column({ space: 10 }) {
          if (this.loadingSummary && this.notifications.length === 0) {
            HarmonyCardGridSkeleton({
              variant: 'service',
              singleColumn: true,
              count: 3,
              horizontalPadding: 0,
              bottomPadding: 8
            })
          } else if (this.notifications.length === 0) {
            Text('当前未配置消息通知渠道，点击右上角「新增」添加').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.notifications, (it: MpSimpleSettingItem, idx: number) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Row({ space: 10 }) {
                  HarmonyEntityLogo({
                    kind: 'notification',
                    value: it.type || it.name,
                    logoSize: 32,
                    cornerRadius: 8
                  })
                  Column({ space: 3 }) {
                    Text(it.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    Text(it.detail || it.type).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.showNotificationsSheet = false;
                    this.openNotifEditor(it);
                  })
                  NativeAdaptiveBadge({ text: it.enabled ? '已启用' : '未启用', tintHex: it.enabled ? '#34C759' : '#F29B38' })
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor(['#E84855'])
                  }
                  .width(30).height(30)
                  .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                  .onClick(() => this.confirmDeleteNotif(it.name))
                }.width('100%')
              }
            }, (it: MpSimpleSettingItem, idx: number) => `nf_${idx}_${it.name}_${it.enabled}`)
          }
        }
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  notifEditorSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: this.notifCreate ? '新增通知渠道' : '编辑通知渠道',
        cancelText: '取消',
        actionText: this.notifSaving ? '保存中' : '保存',
        actionEnabled: !this.notifSaving && this.notifName.trim().length > 0,
        onCancel: () => { this.showNotifEditorSheet = false; },
        onAction: () => { this.saveNotifChannel(); }
      })

      Scroll() {
        Column({ space: 12 }) {
          Text('选择消息渠道类型').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(NOTIFICATION_TYPES, (opt: string[]) => {
              HarmonyEntityLogoPill({
                kind: 'notification',
                value: opt[0],
                title: opt[1],
                selected: this.notifType === opt[0],
                onTap: () => {
                  this.notifType = opt[0];
                  if (this.notifName.trim().length === 0) {
                    this.notifName = opt[1];
                  }
                }
              })
            }, (opt: string[]) => `nf_ty_${opt[0]}`)
          }.width('100%')

          Text('渠道实例名称').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          TextInput({ placeholder: '例如：家庭通知群', text: this.notifName })
            .fontColor(mpPrimaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .borderRadius(12)
            .onChange((v: string) => { this.notifName = v; })

          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Row() {
              Text('启用此通知渠道').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.notifEnabled })
                .selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.notifEnabled = v; })
            }.width('100%')
          }

          if (!this.notifCreate && this.notifOrigName.length > 0) {
            Button('删除此通知渠道')
              .width('100%').height(44).borderRadius(22)
              .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
              .fontColor('#E84855').fontWeight(FontWeight.Bold)
              .onClick(() => this.confirmDeleteNotif(this.notifOrigName))
          }
        }.padding({ bottom: 24 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  private isMedalShortLandscape(): boolean {
    return this.windowWidthVp > this.windowHeightVp && this.windowHeightVp > 0 && this.windowHeightVp < 520;
  }

  @Builder
  playbackSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '播放偏好',
        cancelText: '完成',
        onCancel: () => { this.showPlaybackSheet = false; }
      })
      Scroll() {
        Column({ space: 14 }) {
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
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  @Builder
  medalDetailActionBodyBuilder(medal: MpCommunityMedal) {
    Column({ space: 12 }) {
      Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
        NativeAdaptiveBadge({
          text: `Tier ${medal.tier}`,
          tintHex: '#FFCC6B'
        })
        NativeAdaptiveBadge({
          text: medal.category,
          tintHex: this.accentHex
        })
        NativeAdaptiveBadge({
          text: medal.earned ? '已解锁' : '待解锁',
          tintHex: medal.earned ? '#34C759' : '#9AA4B2'
        })
        if (medal.worn || this.community.wornMedalId === medal.id) {
          NativeAdaptiveBadge({ text: '当前佩戴', tintHex: this.accentHex, filled: true })
        }
      }

      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Column({ space: 6 }) {
          Text('解锁条件与记录')
            .fontSize(13.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
          Text(medal.criteria || medal.subtitle)
            .fontSize(12.5).fontColor(mpSecondaryText(this.isDark)).lineHeight(18).width('100%')
          if ((medal.facts ?? []).length > 0) {
            ForEach(medal.facts ?? [], (fact: string, fIdx: number) => {
              Text(`• ${fact}`).fontSize(12).fontColor(this.accentHex).width('100%')
            }, (fact: string, fIdx: number) => `mf_${fIdx}_${fact}`)
          }
        }.alignItems(HorizontalAlign.Start)
      }

      Button((medal.worn || this.community.wornMedalId === medal.id) ? '已佩戴此勋章' : '佩戴勋章')
        .width('100%').height(44).borderRadius(22)
        .backgroundColor(this.accentHex).fontColor(Color.White).fontWeight(FontWeight.Bold)
        .enabled(!this.medalBusy && Boolean(medal.earned))
        .opacity(medal.earned ? 1 : 0.45)
        .onClick(async () => {
          this.medalBusy = true;
          const ok = await MoviePilotRepository.shared().wearCommunityMedal(medal.id);
          if (ok) {
            this.community = await MoviePilotRepository.shared().fetchCommunityMedals();
            this.medalNotice = `已佩戴「${medal.title}」`;
          } else {
            this.medalNotice = '佩戴勋章失败，请确认已绑定 GitHub 社区账号';
          }
          this.medalBusy = false;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  medalsSheetBuilder() {
    Column({ space: 10 }) {
      HarmonySheetHeader({
        title: (this.loadingSummary && this.community.medals.length === 0)
          ? '社区勋章'
          : `社区勋章 (${this.community.earnedCount}/${this.community.totalCount})`,
        cancelText: '关闭',
        actionText: this.medalBusy ? '刷新中' : '刷新勋章',
        actionEnabled: !this.medalBusy,
        onCancel: () => { this.showMedalsSheet = false; },
        onAction: async () => {
          this.medalBusy = true;
          this.community = await MoviePilotRepository.shared().refreshCommunityMedals();
          this.medalBusy = false;
          this.medalNotice = '已同步最新社区勋章解锁状态';
        }
      })

      if (this.medalNotice.length > 0) {
        Text(this.medalNotice).fontSize(12).fontColor('#34C759').width('100%')
      }

      if (this.loadingSummary && this.community.medals.length === 0) {
        HarmonyCardGridSkeleton({
          variant: 'service',
          singleColumn: true,
          count: 3,
          horizontalPadding: 0,
          bottomPadding: 8
        })
      } else if (this.community.medals.length > 0) {
        if (this.isMedalShortLandscape()) {
          Row({ space: 18 }) {
            Scroll() {
              Column() {
                CommunityMedal3DComponent({
                  medalId: this.community.medals[this.activeMedalIdx].id,
                  frontAsset: this.community.medals[this.activeMedalIdx].frontAsset,
                  backAsset: this.community.medals[this.activeMedalIdx].backAsset,
                  title: this.community.medals[this.activeMedalIdx].title,
                  subtitle: this.community.medals[this.activeMedalIdx].subtitle,
                  ownerName: this.community.githubLogin,
                  earnedDate: this.community.medals[this.activeMedalIdx].earnedDate,
                  medalSize: 164
                })
              }
              .padding({ bottom: 12 })
            }
            .scrollBar(BarState.Off)
            .width(204)
            .height('100%')

            Scroll() {
              Column({ space: 12 }) {
                Scroll() {
                  Row({ space: 8 }) {
                    ForEach(this.community.medals, (m: MpCommunityMedal, idx: number) => {
                      NativeAdaptivePill({
                        title: m.title,
                        selected: this.activeMedalIdx === idx,
                        onTap: () => {
                          this.activeMedalIdx = idx;
                          this.medalNotice = '';
                        }
                      })
                    }, (m: MpCommunityMedal) => m.id)
                  }
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')

                this.medalDetailActionBodyBuilder(this.community.medals[this.activeMedalIdx])
              }
              .width('100%')
              .padding({ bottom: 20 })
            }
            .scrollBar(BarState.Off)
            .layoutWeight(1)
            .height('100%')
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.community.medals, (m: MpCommunityMedal, idx: number) => {
                NativeAdaptivePill({
                  title: m.title,
                  selected: this.activeMedalIdx === idx,
                  onTap: () => {
                    this.activeMedalIdx = idx;
                    this.medalNotice = '';
                  }
                })
              }, (m: MpCommunityMedal) => m.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

          Scroll() {
            Column({ space: 14 }) {
              CommunityMedal3DComponent({
                medalId: this.community.medals[this.activeMedalIdx].id,
                frontAsset: this.community.medals[this.activeMedalIdx].frontAsset,
                backAsset: this.community.medals[this.activeMedalIdx].backAsset,
                title: this.community.medals[this.activeMedalIdx].title,
                subtitle: this.community.medals[this.activeMedalIdx].subtitle,
                ownerName: this.community.githubLogin,
                earnedDate: this.community.medals[this.activeMedalIdx].earnedDate,
                medalSize: 240
              })

              this.medalDetailActionBodyBuilder(this.community.medals[this.activeMedalIdx])
            }
            .alignItems(HorizontalAlign.Center)
            .padding({ bottom: 24 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .width('100%')
        }
      }
    }.padding(20).width('100%').height('100%').alignItems(HorizontalAlign.Center)
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
        Column() {
          Column({ space: 16 }) {
            HarmonySkeletonHost({ loadingLabel: '设置概览状态' }) {
              Column({ space: 16 }) {
                CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
                  if (this.loadingSummary) {
                    Column({ space: 9 }) {
                      Row() {
                        Text(`● ${this.serverUrl.replace(/^https?:\/\//, '') || '127.0.0.1'}`)
                          .fontSize(13).fontColor('#34C759').layoutWeight(1).maxLines(1)
                        HarmonySkeletonBlock({ blockWidth: 108, blockHeight: 13, cornerRadius: 4 })
                      }.width('100%')
                      HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 6, cornerRadius: 3, tone: 'subtle' })
                      Row() {
                        HarmonySkeletonBlock({ blockWidth: 56, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                        Blank()
                        HarmonySkeletonBlock({ blockWidth: 78, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                      }.width('100%')
                    }
                  } else {
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
                }

                // 三枚快捷磁贴：站点管理 / 用户管理 / 渠道授权
                Row({ space: 10 }) {
                  Column() {
                    CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                      Column({ space: 4 }) {
                        HarmonyEntityLogo({ kind: 'site', value: 'site', logoSize: 22, cornerRadius: 6 })
                        Text('站点管理').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                        if (this.loadingSummary) {
                          HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                        } else {
                          Text(`● ${this.siteCount} 启用`).fontSize(11).fontColor('#34C759')
                        }
                      }.alignItems(HorizontalAlign.Start)
                    }
                  }.layoutWeight(1).onClick(() => this.onOpenSites())

                  Column() {
                    CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                      Column({ space: 4 }) {
                        SymbolGlyph($r('sys.symbol.person_2')).fontSize(20).fontColor([this.accentHex])
                        Text('用户管理').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                        if (this.loadingSummary) {
                          HarmonySkeletonBlock({ blockWidth: 58, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                        } else {
                          Text(`● ${this.users.length} 位成员`).fontSize(11).fontColor(this.accentHex)
                        }
                      }.alignItems(HorizontalAlign.Start)
                    }
                  }.layoutWeight(1).onClick(() => { this.showUsersSheet = true; })

                  Column() {
                    CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                      Column({ space: 4 }) {
                        SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(20).fontColor(['#34C759'])
                        Text('渠道授权').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                        if (this.loadingSummary) {
                          HarmonySkeletonBlock({ blockWidth: 54, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                        } else {
                          Text(`● 会话 ${this.authorizations.length}`).fontSize(11).fontColor('#34C759')
                        }
                      }.alignItems(HorizontalAlign.Start)
                    }
                  }.layoutWeight(1).onClick(() => { this.showAuthorizationSheet = true; })
                }
              }
              .width('100%')
            }

            // 基础配置分组（全部配备品牌图标或系统符号）
            Text('基础配置').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
              Column() {
                HarmonySettingsRow({
                  title: '媒体数据源',
                  sub: this.recognizeSource === 'douban' ? '豆瓣' : 'TMDB',
                  loadingSub: this.loadingSummary,
                  logoKind: 'media_source',
                  logoValue: this.recognizeSource,
                  onTap: () => { this.showMediaSourcesSheet = true; }
                })
                Divider().color(HarmonyThemeColors.divider(this.isDark))
                HarmonySettingsRow({
                  title: '订阅与搜索',
                  sub: this.subscribeMode === 'rss' ? 'RSS 刷新' : '自动检索',
                  loadingSub: this.loadingSummary,
                  symbolName: 'sys.symbol.bookmark',
                  symbolTint: '#26B8A8',
                  onTap: () => { this.showSubscribeSearchSheet = true; }
                })
                Divider().color(HarmonyThemeColors.divider(this.isDark))
                HarmonySettingsRow({
                  title: '下载器',
                  sub: `${this.downloaders.length} 个`,
                  loadingSub: this.loadingSummary,
                  logoKind: 'downloader',
                  logoValue: this.primaryDownloaderType(),
                  onTap: () => { this.showDownloadersSheet = true; }
                })
                Divider().color(HarmonyThemeColors.divider(this.isDark))
                HarmonySettingsRow({
                  title: '媒体服务器',
                  sub: `${this.mediaServers.length} 个`,
                  loadingSub: this.loadingSummary,
                  logoKind: 'mediaserver',
                  logoValue: this.primaryMediaServerType(),
                  onTap: () => { this.showMediaServersSheet = true; }
                })
                Divider().color(HarmonyThemeColors.divider(this.isDark))
                HarmonySettingsRow({
                  title: '整理与目录',
                  sub: `${this.directories.length} 组映射`,
                  loadingSub: this.loadingSummary,
                  logoKind: 'storage',
                  logoValue: this.primaryStorageType(),
                  onTap: () => { this.showDirectoriesSheet = true; }
                })
                Divider().color(HarmonyThemeColors.divider(this.isDark))
                HarmonySettingsRow({
                  title: '播放偏好',
                  sub: ['自适应', '原画', '1080p'][this.playbackQualityIdx],
                  symbolName: 'sys.symbol.play_circle_fill',
                  symbolTint: '#5AC8FA',
                  onTap: () => { this.showPlaybackSheet = true; }
                })
              }
            }

            // 通知与个性化
            Text('通知与个性化').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
              Column() {
                HarmonySettingsRow({
                  title: '通知渠道',
                  sub: `${this.notifications.length} 个渠道`,
                  loadingSub: this.loadingSummary,
                  logoKind: 'notification',
                  logoValue: this.primaryNotificationType(),
                  onTap: () => { this.showNotificationsSheet = true; }
                })
                Divider().color(HarmonyThemeColors.divider(this.isDark))
                HarmonySettingsRow({
                  title: '主题与外观',
                  sub: `${HarmonyAppearanceStore.paletteById(this.paletteId).titleZh} · ${this.dynamicLight ? HarmonyDynamicLight.materialLevelLabel() : '标准'}`,
                  symbolName: 'sys.symbol.ai_edit',
                  symbolTint: this.accentHex,
                  onTap: () => { this.showAppearanceSheet = true; }
                })
                Divider().color(HarmonyThemeColors.divider(this.isDark))
                HarmonySettingsRow({
                  title: '社区勋章',
                  sub: `已解锁 ${this.community.earnedCount}/${this.community.totalCount}`,
                  loadingSub: this.loadingSummary,
                  symbolName: 'sys.symbol.star',
                  symbolTint: '#F2B830',
                  onTap: () => { this.showMedalsSheet = true; }
                })
              }
            }

          // 账号与版本
          CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
            Column() {
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph($r('sys.symbol.checkmark_shield')).fontSize(16).fontColor([this.accentHex])
                }
                .width(28).height(28).borderRadius(8)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '26' : '18'))

                Text('客户端版本').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                NativeAdaptiveBadge({ text: `v${RustCoreBridge.version()}`, tintHex: this.accentHex })
              }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph($r('sys.symbol.arrow_left_arrow_right')).fontSize(16).fontColor([this.accentHex])
                }
                .width(28).height(28).borderRadius(8)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '26' : '18'))

                Text('切换服务').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Text(this.serverUrl.replace(/^https?:\/\//, '').split('/')[0] || '当前服务')
                  .fontSize(12.5)
                  .fontColor(mpSecondaryText(this.isDark))
                  .maxLines(1)
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([mpSecondaryText(this.isDark)])
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .hoverEffect(HoverEffect.Highlight)
              .accessibilityText('切换 MoviePilot 服务实例')
              .onClick(() => this.onSwitchServer())
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph($r('sys.symbol.power')).fontSize(16).fontColor(['#E84855'])
                }
                .width(28).height(28).borderRadius(8)
                .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))

                Text(`退出登录（${this.userName}）`).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E84855')
              }
              .width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => this.onLogout())
            }
          }
          }
          .width('100%')
          .constraintSize({ maxWidth: 820 })
          .padding({ left: 16, right: 16, top: 6, bottom: 44 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')

      Blank().width(0).height(0).bindSheet($$this.showAppearanceSheet, this.appearanceSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showUsersSheet, this.usersSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showAuthorizationSheet, this.authorizationSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showMediaSourcesSheet, this.mediaSourcesSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showSubscribeSearchSheet, this.subscribeSearchSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showDownloadersSheet, this.downloadersSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showMediaServersSheet, this.mediaServersSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showDirectoriesSheet, this.directoriesSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showNotificationsSheet, this.notificationsSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showNotifEditorSheet, this.notifEditorSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showPlaybackSheet, this.playbackSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showCrudEditor, this.crudEditorSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showMedalsSheet, this.medalsSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
    }
    .width('100%')
    .height('100%')
  }
}
