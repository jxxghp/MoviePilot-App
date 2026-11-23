import {
  RustCoreBridge,
  MoviePilotRepository,
  MpDashboardStats,
  MpUserItem,
  MpPluginItem,
  MpCommunityState,
  MpCommunityMedal,
  MpSimpleSettingItem,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  GeneratedDesignTokens,
  BackgroundPresetToken,
  AccentPresetToken,
  HarmonyAppearanceStore,
  HarmonyDynamicLight,
  HarmonyThemeColors,
  HarmonyUnderlineTabBar,
  HarmonySegmentedSwitch,
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
 * 鸿蒙原生插件中心独立页面：
 * - 使用规范下划线页签栏切换「已安装 / 插件市场」；
 * - Vuetify 原生插件支持「数据页 / 参数配置」二级下划线页签与真实保存提交；
 * - Vue 模块联邦插件零提示直接进入受控隔离容器，并由原生 `NativeBackHeader` 完整接管标题、操作按钮与关闭返回。
 */
@Component
export struct HarmonyPluginsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop serverUrl: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @State private activeTabIdx: number = 0; // 0: 已安装, 1: 插件市场
  @State private installedPlugins: MpPluginItem[] = [];
  @State private marketPlugins: MpPluginItem[] = [];
  @State private loading: boolean = true;
  @State private activePlugin: MpPluginItem | null = null;
  @State private detailTabIndex: number = 0; // 0: 数据页, 1: 参数配置
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

  private async openPluginDetail(pl: MpPluginItem): Promise<void> {
    this.activePlugin = pl;
    this.chromeTitle = pl.pluginName;
    this.chromeActions = [];
    this.saveNotice = '';
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
  }

  build() {
    if (this.activePlugin) {
      Column() {
        NativeBackHeader({
          title: this.chromeTitle || this.activePlugin.pluginName,
          trailingText: this.chromeActions.length > 0 ? this.chromeActions[0].title : '',
          onBack: () => this.closePluginDetail(),
          onTrailingClick: () => {
            if (this.chromeActions.length > 0) {
              this.vueChromeController.invokeAction(this.chromeActions[0].id);
            }
          }
        })

        if (this.saveNotice.length > 0) {
          Text(this.saveNotice)
            .fontSize(12)
            .fontColor('#52C41A')
            .padding({ left: 16, right: 16, bottom: 6 })
            .width('100%')
        }

        if (!this.isActivePluginVue() && this.activePlugin.hasPage) {
          HarmonyUnderlineTabBar({
            tabs: ['数据页', '参数配置'],
            selectedIndex: this.detailTabIndex,
            onSelect: (idx: number) => { this.detailTabIndex = idx; }
          })
        }

        if (this.loadingDetail) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.accentHex)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.activePlugin.hasPage && this.detailTabIndex === 0) {
          NativePluginDataPageView({
            pluginId: this.activePlugin.id,
            documentJson: this.activePageDoc,
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
            documentJson: this.activeFormDoc,
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
      Column({ space: 8 }) {
        NativeBackHeader({
          title: '插件中心',
          trailingSymbol: 'sys.symbol.arrow_clockwise',
          trailingAccessibility: '刷新插件列表',
          onBack: () => this.onBack(),
          onTrailingClick: () => this.loadInstalled()
        })

        HarmonyUnderlineTabBar({
          tabs: [`已安装 (${this.installedPlugins.length})`, `插件市场 (${this.marketPlugins.length})`],
          selectedIndex: this.activeTabIdx,
          onSelect: (idx: number) => {
            this.activeTabIdx = idx;
            if (idx === 1) {
              this.loadMarketIfNeeded();
            }
          }
        })

        if (this.loading && (this.activeTabIdx === 0 ? this.installedPlugins.length === 0 : this.marketPlugins.length === 0)) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.accentHex)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(
                this.activeTabIdx === 0 ? this.installedPlugins : this.marketPlugins.slice(0, 50),
                (pl: MpPluginItem) => {
                  Column() {
                    CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: this.activeTabIdx === 0 }) {
                      Row({ space: 12 }) {
                        if (pl.iconUrl.length > 0) {
                          Image(pl.iconUrl)
                            .width(42)
                            .height(42)
                            .borderRadius(12)
                            .objectFit(ImageFit.Cover)
                            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                        } else {
                          Stack() {
                            SymbolGlyph($r('sys.symbol.puzzle')).fontSize(20).fontColor([this.accentHex])
                          }
                          .width(42).height(42).borderRadius(12).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                        }

                        Column({ space: 4 }) {
                          Row({ space: 6 }) {
                            Text(pl.pluginName)
                              .fontSize(15)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(mpPrimaryText(this.isDark))
                              .maxLines(1)
                              .layoutWeight(1)
                            if (pl.pluginVersion.length > 0) {
                              NativeAdaptiveBadge({ text: `v${pl.pluginVersion}`, tintHex: this.accentHex })
                            }
                          }.width('100%')
                          Text(pl.pluginDesc || pl.id)
                            .fontSize(12)
                            .fontColor(mpSecondaryText(this.isDark))
                            .maxLines(2)
                            .width('100%')
                          Row({ space: 8 }) {
                            Text(`作者：${pl.pluginAuthor || 'MoviePilot'}`)
                              .fontSize(11)
                              .fontColor(mpSecondaryText(this.isDark))
                            if (pl.renderMode.toLowerCase() === 'vue') {
                              NativeAdaptiveBadge({ text: '联邦视图', tintHex: '#36CFC9' })
                            }
                          }
                        }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                        if (this.activeTabIdx === 0) {
                          NativeAdaptiveBadge({
                            text: pl.state ? '已启用' : '配置',
                            tintHex: pl.state ? '#52C41A' : '#6EA8FE'
                          })
                        }
                      }.width('100%')
                    }
                  }
                  .width('100%')
                  .onClick(() => {
                    if (this.activeTabIdx === 0) {
                      this.openPluginDetail(pl);
                    }
                  })
                },
                (pl: MpPluginItem) => `${this.activeTabIdx}_${pl.id}`
              )
            }
            .padding({ left: 16, right: 16, top: 4, bottom: 40 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
    }
  }
}

/**
 * 鸿蒙设置主中心（由「我的」右上角齿轮进入，支持 HarmonyOS 7 动态光感与低版本自动回退状态透显）：
 * 顶部真实存储容量卡、3 枚快捷磁贴（站点管理/用户管理/插件中心）、
 * 系统配置（下载器/媒体服务器/通知渠道）、外观与动态光感、3D 社区勋章与 Rust 共享内核信息。
 */
@Component
export struct HarmonySettingsHubPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_MODE) appearanceMode: string = 'dark';
  @StorageLink(HarmonyAppearanceStore.KEY_BG_PRESET) bgPreset: string = GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_ANIMATE_BG) animateBg: boolean = false;
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
  @State private installedPlugins: MpPluginItem[] = [];
  @State private downloaders: MpSimpleSettingItem[] = [];
  @State private mediaServers: MpSimpleSettingItem[] = [];
  @State private notifications: MpSimpleSettingItem[] = [];
  @State private community: MpCommunityState = { githubLogin: 'MoviePilot', earnedCount: 0, totalCount: 7, medals: [] };
  @State private showAppearanceSheet: boolean = false;
  @State private showUsersSheet: boolean = false;
  @State private showSystemSheet: boolean = false;
  @State private systemSheetTitle: string = '';
  @State private systemSheetItems: MpSimpleSettingItem[] = [];
  @State private showMedalsSheet: boolean = false;
  @State private activeMedalIdx: number = 0;
  onBack: () => void = () => {};
  onOpenSites: () => void = () => {};
  onOpenPlugins: () => void = () => {};
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
        repo.fetchPlugins('installed'),
        repo.fetchCommunityMedals(),
        repo.fetchSystemSettingList('Downloaders'),
        repo.fetchSystemSettingList('MediaServers'),
        repo.fetchSystemSettingList('Notifications')
      ]);
      this.stats = res[0];
      this.siteCount = res[1].length;
      this.users = res[2];
      this.installedPlugins = res[3];
      this.community = res[4];
      this.downloaders = res[5];
      this.mediaServers = res[6];
      this.notifications = res[7];
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

  @Builder
  appearanceSheetBuilder() {
    Scroll() {
      Column({ space: 14 }) {
        Text('外观与动态光感')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .width('100%')

        // 颜色模式：深色 / 浅色 / 跟随系统（规范互斥分段控制器）
        HarmonySegmentedSwitch({
          options: ['深色', '浅色', '跟随系统'],
          selectedIndex: this.modeIndex(),
          onSelect: (idx: number) => {
            if (idx === 0) {
              this.appearanceMode = 'dark';
              this.isDark = true;
            } else if (idx === 1) {
              this.appearanceMode = 'light';
              this.isDark = false;
            } else {
              this.appearanceMode = 'system';
            }
          }
        })

        // HarmonyOS 7 动态光感分级状态卡与开关
        CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text('HarmonyOS 7 动态光感材质')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(mpPrimaryText(this.isDark))
                Text(HarmonyDynamicLight.tierLabel())
                  .fontSize(11)
                  .fontColor(this.accentHex)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.dynamicLight })
                .selectedColor(this.accentHex)
                .onChange((v: boolean) => { this.dynamicLight = v; })
            }.width('100%')

            Text('在 HarmonyOS 7 启用官方 ImmersiveMaterial 沉浸光感与按压形变；HarmonyOS 6 自动切换 HDS 点光源，低版本自动回退清晰分层底色。')
              .fontSize(11)
              .fontColor(mpSecondaryText(this.isDark))
              .lineHeight(17)
              .width('100%')
          }
        }

        // 顶部柔和氛围微光（默认关闭，保持鸿蒙冷静中性底色）
        CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
          Row() {
            Column({ space: 2 }) {
              Text('顶部氛围微光').fontSize(15).fontColor(mpPrimaryText(this.isDark))
              Text('可选叠加同源色板微光，默认关闭以保证最佳续航与对比度').fontSize(11).fontColor(mpSecondaryText(this.isDark))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.animateBg })
              .selectedColor(this.accentHex)
              .onChange((v: boolean) => { this.animateBg = v; })
          }.width('100%')
        }

        if (this.animateBg) {
          Text('6 套同源氛围色板').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(GeneratedDesignTokens.BACKGROUND_PRESETS, (p: BackgroundPresetToken) => {
              NativeAdaptivePill({ title: p.titleZh, selected: this.bgPreset === p.id, onTap: () => { this.bgPreset = p.id; } })
            })
          }
        }

        Text('主题强调色').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
        Row({ space: 12 }) {
          ForEach(GeneratedDesignTokens.ACCENT_PRESETS.filter((a: AccentPresetToken) => a.id !== 'custom'), (acc: AccentPresetToken) => {
            Column()
              .width(34)
              .height(34)
              .borderRadius(17)
              .backgroundColor(acc.hex)
              .border({ width: this.accentHex === acc.hex ? 3 : 1, color: this.isDark ? Color.White : '#33000000', radius: 17 })
              .onClick(() => { this.accentHex = acc.hex; })
          })
        }.width('100%')
      }
      .padding(20)
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
  }

  @Builder
  usersSheetBuilder() {
    Column({ space: 12 }) {
      Text(`用户管理 (${this.users.length})`).fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.users, (u: MpUserItem) => {
            CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
              Row({ space: 12 }) {
                if (u.avatar.length > 0) {
                  Image(u.avatar).width(42).height(42).borderRadius(21).objectFit(ImageFit.Cover)
                } else {
                  Text(u.name.substring(0, 1).toUpperCase())
                    .width(42).height(42).borderRadius(21).textAlign(TextAlign.Center)
                    .fontColor(Color.White).fontWeight(FontWeight.Bold).backgroundColor(this.accentHex)
                }
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(u.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    NativeAdaptiveBadge({ text: u.isSuperuser ? '超管' : '成员', tintHex: u.isSuperuser ? this.accentHex : '#6EA8FE' })
                  }
                  Text(u.email || (u.isActive ? '账号已启用' : '账号已停用')).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%')
            }
          }, (u: MpUserItem) => String(u.id))
        }
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  systemListSheetBuilder() {
    Column({ space: 12 }) {
      Text(this.systemSheetTitle).fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
      Scroll() {
        Column({ space: 10 }) {
          if (this.systemSheetItems.length === 0) {
            Text('当前未配置该类服务实例').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.systemSheetItems, (it: MpSimpleSettingItem, idx: number) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                Row() {
                  Column({ space: 3 }) {
                    Text(it.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    Text(it.detail || it.type).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  NativeAdaptiveBadge({ text: it.enabled ? '已启用' : '未启用', tintHex: it.enabled ? '#52C41A' : '#FAAD14' })
                }.width('100%')
              }
            }, (it: MpSimpleSettingItem, idx: number) => `${it.name}_${idx}`)
          }
        }
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  medalsSheetBuilder() {
    Column({ space: 14 }) {
      Text(`3D 社区勋章 (${this.community.earnedCount}/${this.community.totalCount})`)
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
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
      NativeBackHeader({ title: '设置', onBack: () => this.onBack() })

      Scroll() {
        Column({ space: 16 }) {
          // 顶部真实存储容量卡
          CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
            Column({ space: 8 }) {
              Row() {
                Text(`● ${this.serverUrl || '127.0.0.1'}`).fontSize(13).fontColor('#52C41A').layoutWeight(1).maxLines(1)
                Text(`${formatByteSize(this.stats.storageUsedBytes)} / ${formatByteSize(this.stats.storageTotalBytes)}`)
                  .fontSize(12).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
              }.width('100%')
              Progress({ value: this.storagePct(), total: 100, type: ProgressType.Linear })
                .color(this.accentHex)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              Row() {
                Text(`已用 ${this.storagePct()}%`).fontSize(11).fontColor(this.accentHex)
                Blank()
                Text(`可用 ${formatByteSize(Math.max(0, this.stats.storageTotalBytes - this.stats.storageUsedBytes))}`)
                  .fontSize(11).fontColor(mpSecondaryText(this.isDark))
              }.width('100%')
            }
          }

          // 三枚快捷磁贴（支持 HarmonyOS 7 交互动态光感）
          Row({ space: 10 }) {
            Column() {
              CinematicPanel({ panelPadding: 12, cornerRadius: 16, interactive: true }) {
                Column({ space: 4 }) {
                  Text('站点管理').fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text(`● ${this.siteCount} 站点`).fontSize(11).fontColor('#52C41A')
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1).onClick(() => this.onOpenSites())

            Column() {
              CinematicPanel({ panelPadding: 12, cornerRadius: 16, interactive: true }) {
                Column({ space: 4 }) {
                  Text('用户管理').fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text(`● ${this.users.length} 位成员`).fontSize(11).fontColor('#52C41A')
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1).onClick(() => { this.showUsersSheet = true; })

            Column() {
              CinematicPanel({ panelPadding: 12, cornerRadius: 16, interactive: true }) {
                Column({ space: 4 }) {
                  Text('插件中心').fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                  Text(`● ${this.installedPlugins.length} 已装`).fontSize(11).fontColor('#52C41A')
                }.alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1).onClick(() => this.onOpenPlugins())
          }

          // 系统与服务配置
          CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
            Column() {
              this.settingsRow('下载器', `${this.downloaders.length} 个已配置`, () => {
                this.systemSheetTitle = '下载器配置';
                this.systemSheetItems = this.downloaders;
                this.showSystemSheet = true;
              })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              this.settingsRow('媒体服务器', `${this.mediaServers.length} 个已连接`, () => {
                this.systemSheetTitle = '媒体服务器';
                this.systemSheetItems = this.mediaServers;
                this.showSystemSheet = true;
              })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              this.settingsRow('消息通知渠道', `${this.notifications.length} 个渠道`, () => {
                this.systemSheetTitle = '消息通知渠道';
                this.systemSheetItems = this.notifications;
                this.showSystemSheet = true;
              })
            }
          }

          // 外观、动态光感、社区勋章与 Rust 内核
          CinematicPanel({ panelPadding: 0, cornerRadius: 18 }) {
            Column() {
              this.settingsRow('外观与动态光感', this.dynamicLight ? HarmonyDynamicLight.materialLevelLabel() : '标准分层', () => {
                this.showAppearanceSheet = true;
              })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              this.settingsRow('3D 社区勋章', `已解锁 ${this.community.earnedCount}/${this.community.totalCount}`, () => {
                this.showMedalsSheet = true;
              })
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              this.settingsRow('Rust 共享内核', `v${RustCoreBridge.version()} · ${RustCoreBridge.isNativeLoaded() ? 'NAPI .so 已加载' : 'ohos-rs'}`, () => {})
            }
          }

          Button(`退出登录（${this.userName}）`)
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor('#28FF5C6C')
            .fontColor('#FF5C6C')
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.onLogout())
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 44 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .bindSheet($$this.showAppearanceSheet, this.appearanceSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .bindSheet($$this.showUsersSheet, this.usersSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .bindSheet($$this.showSystemSheet, this.systemListSheetBuilder(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .bindSheet($$this.showMedalsSheet, this.medalsSheetBuilder(), {
      detents: [SheetSize.LARGE],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  settingsRow(title: string, sub: string, action: () => void) {
    Row() {
      Text(title).fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
      Text(sub).fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(1)
      Text(' ›').fontSize(16).fontColor(mpSecondaryText(this.isDark))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 15, bottom: 15 })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(action)
  }
}
