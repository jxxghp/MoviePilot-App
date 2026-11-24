import {
  MoviePilotRepository,
  MpDashboardStats,
  MpCommunityState,
  MpCommunityMedal,
  MpMessageItem,
  MpSchedulerItem,
  MpMediaItem,
  MpNetworkCheckItem,
  MpRecognizeResult,
  MpRemoteImage,
  formatByteSize,
  formatSpeed
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  CustomModulePref,
  DEFAULT_DASHBOARD_MODULES,
  NativeAdaptiveBadge,
  NativeBackHeader,
  HarmonyPageHeader,
  HarmonyPillTabBar,
  HarmonySheetHeader,
  HarmonyAdaptiveLayout,
  HarmonyThemeColors,
  GeneratedDesignTokens,
  HarmonyAppearanceStore,
  HarmonyEntityLogo,
  HarmonySkeletonHost,
  HarmonySkeletonBlock,
  HarmonyBentoDashboardSkeleton,
  HarmonyCardGridSkeleton,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import {
  NativeCommunityMedalsWidget,
  CommunityMedal3DComponent
} from '@moviepilot/medal_3d';

interface WordCategoryDef {
  id: string;
  label: string;
  settingKey: string;
  title: string;
  description: string;
  placeholder: string;
  inlineHint: string;
  exampleTitle: string;
  examples: string;
  guideNote: string;
}

const WORD_CATEGORIES: WordCategoryDef[] = [
  {
    id: 'identifiers',
    label: '识别词',
    settingKey: 'CustomIdentifiers',
    title: '自定义识别词',
    description: '添加规则对种子名或文件名进行预处理，以校正媒体识别结果。',
    placeholder: '每行输入一组识别规则',
    inlineHint: '支持正则表达式，特殊字符需要 \\ 转义，一行为一组',
    exampleTitle: '支持的配置格式（注意空格）：',
    examples: '屏蔽词\n被替换词 => 替换词\n前定位词 <> 后定位词 >> 集偏移量（EP）\n被替换词 => 替换词 && 前定位词 <> 后定位词 >> 集偏移量（EP）',
    guideNote: '替换词支持 {[tmdbid/doubanid/bangumiid/anilistid=xxx;type=movie/tv;g=xxx;s=xxx;e=xxx]} 直接指定媒体 ID 识别。'
  },
  {
    id: 'release_groups',
    label: '制作组',
    settingKey: 'CustomReleaseGroups',
    title: '自定义制作组 / 字幕组',
    description: '添加系统无法自动识别的制作组或字幕组名称，方便过滤与重命名。',
    placeholder: '每行输入一个制作组或字幕组名称',
    inlineHint: '支持正则表达式，特殊字符需要 \\ 转义，一行代表一个制作组/字幕组',
    exampleTitle: '配置示例：',
    examples: 'ANi\nLoliHouse\nKitaujiSub\nNekomoe\\s*kissaten',
    guideNote: '匹配成功后将作为资源制作组字段写入元数据，并可用于优先级规则组过滤。'
  },
  {
    id: 'placeholders',
    label: '占位符',
    settingKey: 'Customization',
    title: '自定义占位符',
    description: '提取文件名中的特定关键词，整理重命名时通过 {{customization}} 引用。',
    placeholder: '每行输入一个待提取占位符关键词或正则',
    inlineHint: '多个规则换行分隔，匹配内容将按顺序拼接写入自定义占位符',
    exampleTitle: '配置示例：',
    examples: '简繁内封\n杜比视界\n60fps\n高码版',
    guideNote: '在媒体库重命名模板中使用 {{customization}} 即可自动输出命中的自定义标签。'
  },
  {
    id: 'block_words',
    label: '屏蔽词',
    settingKey: 'TransferExcludeWords',
    title: '整理屏蔽词',
    description: '命中以下关键词的目录或文件将在自动/手动整理时直接跳过，避免误入库。',
    placeholder: '每行输入一个屏蔽关键词或正则',
    inlineHint: '支持正则表达式，命中路径或文件名任意片段即跳过整理',
    exampleTitle: '配置示例：',
    examples: 'Sample\nTrailer\n花絮\n特典|SP\\d+',
    guideNote: '适合过滤预告片、样片、宣传片及无需刮削入库的附带特典文件。'
  },
  {
    id: 'episode_rules',
    label: '剧集规则',
    settingKey: 'CustomEpisodeRules',
    title: '自定义剧集识别规则',
    description: '针对非标准命名的剧集补充季集提取规则，提升连载动画与综艺识别准确率。',
    placeholder: '每行输入一条剧集识别正则（含命名分组）',
    inlineHint: '支持正则表达式，可通过分组捕获季数与集数编号',
    exampleTitle: '配置示例：',
    examples: '第(?P<ep>\\d{1,3})话\n\\[(?P<ep>\\d{2,3})\\]\nVol\\.(?P<season>\\d+)\\s*#(?P<ep>\\d+)',
    guideNote: '仅在内置解析无法提取集数时按顺序补充匹配，不影响常规 S01E01 命名。'
  }
];

/**
 * 鸿蒙「我的」主仪表盘：
 * - 顶部呈现用户头像、权限角色、社区勋章数与连接服务端信息卡片，右上角仅保留消息中心入口；
 * - 媒体库统计 4 宫格为「电影 / 剧集 / 剧集单集 / 音乐」+ 分类图标与本月 `+N` 角标；
 * - 消息中心支持交互式回复（`POST /api/v1/message/web`）；
 * - 3D 社区勋章弹窗支持等级徽标、解锁条件、佩戴勋章（`/medals/wear`）与刷新勋章（`/medals/refresh`）。
 */
@Component
export struct HarmonyDashboardPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DASHBOARD_MODULES) modulesRaw: string = '';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageProp('mp_open_messages_revision') @Watch('onOpenMessagesRevisionChanged') openMessagesRevision: number = 0;
  private static lastConsumedMessagesRevision: number = 0;
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @Prop serverUrl: string = '';
  @State private stats: MpDashboardStats = {
    movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0, musicCount: 0,
    storageUsedBytes: 0, storageTotalBytes: 0,
    downloadSpeed: 0, uploadSpeed: 0, downloadSize: 0, uploadSize: 0,
    memoryPercent: 0, memoryUsedBytes: 0, transferCounts: [], scheduleCount: 0
  };
  @State private community: MpCommunityState = { githubLogin: 'MoviePilot', earnedCount: 0, totalCount: 7, medals: [] };
  @State private messages: MpMessageItem[] = [];
  @State private recentItems: MpMediaItem[] = [];
  @State private modules: CustomModulePref[] = DEFAULT_DASHBOARD_MODULES;
  @State private loading: boolean = true;
  @State private hasLoadedOnce: boolean = false;
  @State private loadingMessages: boolean = false;
  @State private showMessagesSheet: boolean = false;
  @State private showModulesSheet: boolean = false;
  @State private showMedalSheet: boolean = false;
  @State private selectedMedal: MpCommunityMedal | null = null;
  @State private medalBusy: boolean = false;
  @State private medalFeedback: string = '';
  @State private replyText: string = '';
  @State private sendingReply: boolean = false;
  @State private msgFeedback: string = '';

  onOpenShortcutRoute: (routeId: string) => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};

  aboutToAppear(): void {
    this.modules = HarmonyAppearanceStore.parseModules(this.modulesRaw, DEFAULT_DASHBOARD_MODULES);
    this.refreshDashboard();
    if (this.openMessagesRevision > HarmonyDashboardPage.lastConsumedMessagesRevision) {
      HarmonyDashboardPage.lastConsumedMessagesRevision = this.openMessagesRevision;
      setTimeout(() => {
        this.presentMessagesFromSystemIntent();
      }, 40);
    }
  }

  onOpenMessagesRevisionChanged(): void {
    if (this.openMessagesRevision > HarmonyDashboardPage.lastConsumedMessagesRevision) {
      HarmonyDashboardPage.lastConsumedMessagesRevision = this.openMessagesRevision;
      this.presentMessagesFromSystemIntent();
    }
  }

  private presentMessagesFromSystemIntent(): void {
    this.showModulesSheet = false;
    this.showMedalSheet = false;
    this.showMessagesSheet = true;
    MoviePilotRepository.shared().fetchMessages().then((list: MpMessageItem[]) => {
      this.messages = list;
    }).catch(() => {});
  }

  private persistModules(next: CustomModulePref[]): void {
    this.modules = next;
    this.modulesRaw = JSON.stringify(next);
  }

  private moveModule(idx: number, delta: number): void {
    const target = idx + delta;
    if (target < 0 || target >= this.modules.length) { return; }
    const copy: CustomModulePref[] = this.modules.map((m: CustomModulePref): CustomModulePref => ({
      id: m.id, title: m.title, enabled: m.enabled
    }));
    const tmp = copy[idx];
    copy[idx] = copy[target];
    copy[target] = tmp;
    this.persistModules(copy);
  }

  private toggleModule(idx: number, enabled: boolean): void {
    const copy: CustomModulePref[] = this.modules.map((m: CustomModulePref, i: number): CustomModulePref => ({
      id: m.id, title: m.title, enabled: i === idx ? enabled : m.enabled
    }));
    this.persistModules(copy);
  }

  private async refreshDashboard(): Promise<void> {
    this.loading = true;
    if (!this.hasLoadedOnce) {
      this.loadingMessages = true;
    }
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchDashboardStats(),
        repo.fetchCommunityMedals(),
        repo.fetchMessages(),
        repo.fetchRecentlyAdded()
      ]);
      this.stats = res[0];
      this.community = res[1];
      this.messages = res[2];
      this.recentItems = res[3].slice(0, 10);
    } catch {
      // keep existing state
    }
    this.hasLoadedOnce = true;
    this.loading = false;
    this.loadingMessages = false;
  }

  private async handleSendReply(): Promise<void> {
    const trimmed = this.replyText.trim();
    if (trimmed.length === 0 || this.sendingReply) { return; }
    this.sendingReply = true;
    this.msgFeedback = '';
    const repo = MoviePilotRepository.shared();
    const ok = await repo.sendWebMessage(trimmed);
    this.sendingReply = false;
    if (ok) {
      this.replyText = '';
      this.msgFeedback = '已发送交互消息';
      this.messages = await repo.fetchMessages();
    } else {
      this.msgFeedback = '发送消息失败，请稍后重试';
    }
  }

  private storageRatioPercent(): number {
    if (this.stats.storageTotalBytes <= 0) { return 0; }
    return Math.min(100, Math.max(0, (this.stats.storageUsedBytes / this.stats.storageTotalBytes) * 100));
  }

  private maxTransfer(): number {
    let m = 1;
    for (let i = 0; i < this.stats.transferCounts.length; i++) {
      if (this.stats.transferCounts[i] > m) { m = this.stats.transferCounts[i]; }
    }
    return m;
  }

  private monthlyBadgeText(delta: number | undefined, fallback: string): string {
    if (delta !== undefined && delta > 0) {
      return `本月 +${delta}`;
    }
    return fallback;
  }

  private isMedalShortLandscape(): boolean {
    return this.windowWidthVp > this.windowHeightVp && this.windowHeightVp > 0 && this.windowHeightVp < 520;
  }

  private resolvedUserAvatarUrl(): string {
    const trimmed = this.userAvatar.trim();
    if (trimmed.length === 0) {
      return '';
    }
    return MoviePilotRepository.shared().resolveImageUrl(trimmed);
  }

  private formattedServerHost(): string {
    const cleaned = this.serverUrl.trim().replace(/^https?:\/\//i, '').replace(/\/+$/, '');
    return cleaned.length > 0 ? cleaned : '未连接服务器';
  }

  @Builder
  userProfileCardBuilder() {
    CinematicPanel({ panelPadding: 16, cornerRadius: 20 }) {
      Row({ space: 14 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Stack({ alignContent: Alignment.Center }) {
            if (this.resolvedUserAvatarUrl().length > 0) {
              MpRemoteImage({
                src: this.resolvedUserAvatarUrl(),
                imgWidth: 58,
                imgHeight: 58,
                imgRadius: 29,
                placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
              })
            } else {
              HarmonyEntityLogo({
                kind: 'avatar',
                value: this.userName,
                logoSize: 58,
                cornerRadius: 29
              })
            }
          }
          .width(62)
          .height(62)
          .borderRadius(31)
          .border({
            width: 1.5,
            color: HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '72' : '48'),
            radius: 31
          })

          Column()
            .width(13)
            .height(13)
            .borderRadius(6.5)
            .backgroundColor('#34C759')
            .border({
              width: 2,
              color: HarmonyThemeColors.card(this.isDark),
              radius: 6.5
            })
            .margin({ right: 1, bottom: 1 })
        }

        Column({ space: 6 }) {
          Text(this.userName || 'admin')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: 8 }) {
            NativeAdaptiveBadge({
              text: this.isSuperuser ? '超级管理员' : '普通成员',
              tintHex: this.accentHex
            })
            if (this.community.earnedCount > 0) {
              NativeAdaptiveBadge({
                text: '🏅 ' + this.community.earnedCount + ' 枚勋章',
                tintHex: '#F2B830'
              })
            }
          }

          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.worldclock'))
              .fontSize(13)
              .fontColor([mpSecondaryText(this.isDark)])
            Text(this.formattedServerHost())
              .fontSize(12)
              .fontColor(mpSecondaryText(this.isDark))
              .maxLines(1)
              .wordBreak(WordBreak.BREAK_ALL)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
    }
  }

  @Builder
  modulesSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '编辑我的模块',
        cancelText: '完成',
        actionText: '恢复默认',
        onCancel: () => { this.showModulesSheet = false; },
        onAction: () => {
          this.persistModules(DEFAULT_DASHBOARD_MODULES.map((m: CustomModulePref): CustomModulePref => ({
            id: m.id, title: m.title, enabled: m.enabled
          })));
        }
      })
      Text('开关显隐并调整仪表盘组件展示顺序')
        .fontSize(12)
        .fontColor(mpSecondaryText(this.isDark))
        .width('100%')

      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.modules, (mod: CustomModulePref, idx: number) => {
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Row({ space: 8 }) {
                Text(mod.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(mpPrimaryText(this.isDark))
                  .layoutWeight(1)

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.arrow_up'))
                    .fontSize(15)
                    .fontColor([idx > 0 ? mpPrimaryText(this.isDark) : mpSecondaryText(this.isDark)])
                }
                .width(32).height(32)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .enabled(idx > 0)
                .opacity(idx > 0 ? 1 : 0.35)
                .onClick(() => this.moveModule(idx, -1))

                Button({ type: ButtonType.Circle }) {
                  SymbolGlyph($r('sys.symbol.arrow_down'))
                    .fontSize(15)
                    .fontColor([idx < this.modules.length - 1 ? mpPrimaryText(this.isDark) : mpSecondaryText(this.isDark)])
                }
                .width(32).height(32)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .enabled(idx < this.modules.length - 1)
                .opacity(idx < this.modules.length - 1 ? 1 : 0.35)
                .onClick(() => this.moveModule(idx, 1))

                Toggle({ type: ToggleType.Switch, isOn: mod.enabled })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => this.toggleModule(idx, v))
              }.width('100%')
            }
          }, (mod: CustomModulePref, idx: number) => `${idx}_${mod.id}_${mod.enabled}`)
        }
        .padding({ bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  @Builder
  messagesSheetBuilder() {
    Column({ space: 10 }) {
      HarmonySheetHeader({
        title: ((this.loading || this.loadingMessages) && this.messages.length === 0)
          ? '消息中心'
          : `消息中心 (${this.messages.length})`,
        cancelText: '关闭',
        actionText: this.loadingMessages ? '加载中' : '刷新',
        actionEnabled: !this.loadingMessages,
        onCancel: () => { this.showMessagesSheet = false; },
        onAction: async () => {
          this.loadingMessages = true;
          try {
            this.messages = await MoviePilotRepository.shared().fetchMessages();
          } catch {
            // keep existing messages
          }
          this.loadingMessages = false;
        }
      })

      if (this.msgFeedback.length > 0) {
        Text(this.msgFeedback).fontSize(11.5).fontColor('#34C759').width('100%')
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.loadingMessages || (this.loading && !this.hasLoadedOnce && this.messages.length === 0)) {
            HarmonyCardGridSkeleton({
              variant: 'service',
              singleColumn: true,
              count: 4,
              horizontalPadding: 0,
              bottomPadding: 8
            })
          } else if (this.messages.length === 0) {
            Text('暂无最新消息通知，可在底部发送命令交互').fontSize(13).fontColor(mpSecondaryText(this.isDark)).margin({ top: 24 })
          } else {
            ForEach(this.messages, (msg: MpMessageItem) => {
              CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
                Row({ space: 12 }) {
                  if (msg.image.length > 0) {
                    MpRemoteImage({
                      src: msg.image,
                      imgWidth: 54,
                      imgHeight: 76,
                      imgRadius: 10,
                      placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                    })
                  }
                  Column({ space: 4 }) {
                    Row() {
                      Text(msg.title).fontSize(14).fontWeight(FontWeight.Bold)
                        .fontColor(mpPrimaryText(this.isDark)).maxLines(1).layoutWeight(1)
                      if (msg.date.length > 0) {
                        Text(msg.date.substring(0, 16)).fontSize(10).fontColor(mpSecondaryText(this.isDark))
                      }
                    }.width('100%')
                    Text(msg.text).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                      .maxLines(4).lineHeight(18).width('100%')
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                }.width('100%')
              }
            }, (msg: MpMessageItem) => msg.id)
          }
        }.padding({ bottom: 8 })
      }.scrollBar(BarState.Off).layoutWeight(1)

      // 交互式回复输入栏（POST /api/v1/message/web）
      Row({ space: 8 }) {
        TextInput({ placeholder: '输入消息或命令（如 /help）…', text: this.replyText })
          .layoutWeight(1)
          .height(42)
          .fontSize(13.5)
          .fontColor(mpPrimaryText(this.isDark))
          .placeholderColor(mpSecondaryText(this.isDark))
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          .borderRadius(21)
          .onChange((v: string) => { this.replyText = v; })
          .onSubmit(() => { this.handleSendReply(); })

        Button(this.sendingReply ? '发送中' : '发送')
          .height(42)
          .padding({ left: 16, right: 16 })
          .borderRadius(21)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(this.accentHex)
          .fontColor(Color.White)
          .enabled(!this.sendingReply && this.replyText.trim().length > 0)
          .onClick(() => { this.handleSendReply(); })
      }.width('100%')
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  medalDetailActionBodyBuilder(medal: MpCommunityMedal) {
    Column({ space: 12 }) {
      Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
        NativeAdaptiveBadge({ text: `Tier ${medal.tier}`, tintHex: '#FFCC6B' })
        NativeAdaptiveBadge({ text: medal.category, tintHex: this.accentHex })
        NativeAdaptiveBadge({
          text: medal.earned ? '已解锁' : '未解锁',
          tintHex: medal.earned ? '#34C759' : '#9AA4B2'
        })
        if (medal.worn || this.community.wornMedalId === medal.id) {
          NativeAdaptiveBadge({ text: '当前佩戴', tintHex: this.accentHex, filled: true })
        }
      }

      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Column({ space: 6 }) {
          Text('解锁条件与里程碑')
            .fontSize(13.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
          Text(medal.criteria || medal.subtitle)
            .fontSize(12.5).fontColor(mpSecondaryText(this.isDark)).lineHeight(18).width('100%')
          if ((medal.facts ?? []).length > 0) {
            ForEach(medal.facts ?? [], (fact: string, fIdx: number) => {
              Text(`• ${fact}`).fontSize(12).fontColor(this.accentHex).width('100%')
            }, (fact: string, fIdx: number) => `dmf_${fIdx}_${fact}`)
          }
        }.alignItems(HorizontalAlign.Start)
      }

      Button((medal.worn || this.community.wornMedalId === medal.id) ? '已佩戴此勋章' : '佩戴勋章')
        .width('100%').height(44).borderRadius(22)
        .backgroundColor(this.accentHex).fontColor(Color.White).fontWeight(FontWeight.Bold)
        .enabled(!this.medalBusy && medal.earned)
        .opacity(medal.earned ? 1 : 0.45)
        .onClick(async () => {
          if (!this.selectedMedal) { return; }
          const targetId = this.selectedMedal.id;
          const targetTitle = this.selectedMedal.title;
          this.medalBusy = true;
          const ok = await MoviePilotRepository.shared().wearCommunityMedal(targetId);
          if (ok) {
            const nextState = await MoviePilotRepository.shared().fetchCommunityMedals();
            this.community = nextState;
            const updated = nextState.medals.find((x: MpCommunityMedal) => x.id === targetId);
            if (updated) { this.selectedMedal = updated; }
            this.medalFeedback = `已佩戴「${targetTitle}」`;
          } else {
            this.medalFeedback = '佩戴勋章失败，请确认已关联 GitHub 账号';
          }
          this.medalBusy = false;
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  medalShowcaseSheetBuilder() {
    Column({ space: 12 }) {
      if (this.selectedMedal) {
        HarmonySheetHeader({
          title: this.selectedMedal.title,
          cancelText: '关闭',
          actionText: this.medalBusy ? '刷新中' : '刷新勋章',
          actionEnabled: !this.medalBusy,
          onCancel: () => { this.showMedalSheet = false; },
          onAction: async () => {
            this.medalBusy = true;
            const nextState = await MoviePilotRepository.shared().refreshCommunityMedals();
            this.community = nextState;
            const curId = this.selectedMedal ? this.selectedMedal.id : '';
            const refreshed = nextState.medals.find((x: MpCommunityMedal) => x.id === curId);
            if (refreshed) { this.selectedMedal = refreshed; }
            this.medalFeedback = '已同步最新社区勋章数据';
            this.medalBusy = false;
          }
        })

        if (this.medalFeedback.length > 0) {
          Text(this.medalFeedback).fontSize(12).fontColor('#34C759').width('100%')
        }

        if (this.isMedalShortLandscape()) {
          Row({ space: 18 }) {
            Scroll() {
              Column() {
                CommunityMedal3DComponent({
                  medalId: this.selectedMedal.id,
                  frontAsset: this.selectedMedal.frontAsset,
                  backAsset: this.selectedMedal.backAsset,
                  title: this.selectedMedal.title,
                  subtitle: this.selectedMedal.subtitle,
                  ownerName: this.community.githubLogin,
                  earnedDate: this.selectedMedal.earnedDate,
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
                this.medalDetailActionBodyBuilder(this.selectedMedal)
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
            Column({ space: 14 }) {
              CommunityMedal3DComponent({
                medalId: this.selectedMedal.id,
                frontAsset: this.selectedMedal.frontAsset,
                backAsset: this.selectedMedal.backAsset,
                title: this.selectedMedal.title,
                subtitle: this.selectedMedal.subtitle,
                ownerName: this.community.githubLogin,
                earnedDate: this.selectedMedal.earnedDate,
                medalSize: 240
              })

              this.medalDetailActionBodyBuilder(this.selectedMedal)
            }
            .alignItems(HorizontalAlign.Center)
            .padding({ bottom: 24 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .width('100%')
        }
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  renderDashboardModule(modId: string) {
    if (modId === 'media_stats') {
      Column({ space: 12 }) {
        Text('媒体库统计').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
        Grid() {
          GridItem() {
            CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
              Column({ space: 6 }) {
                Row() {
                  Text(`${this.stats.movieCount}`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  Stack({ alignContent: Alignment.Center }) {
                    SymbolGlyph($r('sys.symbol.film')).fontSize(16).fontColor(['#F29B38'])
                  }
                  .width(30).height(30).borderRadius(10)
                  .backgroundColor(HarmonyAppearanceStore.withAlpha('#F29B38', this.isDark ? '26' : '18'))
                }.width('100%')
                Text('电影').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                NativeAdaptiveBadge({ text: this.monthlyBadgeText(this.stats.movieMonthly, '电影库'), tintHex: '#F29B38' })
              }.alignItems(HorizontalAlign.Start)
            }
          }
          GridItem() {
            CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
              Column({ space: 6 }) {
                Row() {
                  Text(`${this.stats.tvCount}`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  Stack({ alignContent: Alignment.Center }) {
                    SymbolGlyph($r('sys.symbol.play_circle_fill')).fontSize(16).fontColor([this.accentHex])
                  }
                  .width(30).height(30).borderRadius(10)
                  .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '26' : '18'))
                }.width('100%')
                Text('剧集').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                NativeAdaptiveBadge({ text: this.monthlyBadgeText(this.stats.tvMonthly, '自动追更'), tintHex: this.accentHex })
              }.alignItems(HorizontalAlign.Start)
            }
          }
          GridItem() {
            CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
              Column({ space: 6 }) {
                Row() {
                  Text(`${this.stats.episodeCount}`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  Stack({ alignContent: Alignment.Center }) {
                    SymbolGlyph($r('sys.symbol.bookmark')).fontSize(16).fontColor(['#26B8A8'])
                  }
                  .width(30).height(30).borderRadius(10)
                  .backgroundColor(HarmonyAppearanceStore.withAlpha('#26B8A8', this.isDark ? '26' : '18'))
                }.width('100%')
                Text('剧集单集').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                NativeAdaptiveBadge({ text: this.monthlyBadgeText(this.stats.episodeMonthly, '已刮削'), tintHex: '#26B8A8' })
              }.alignItems(HorizontalAlign.Start)
            }
          }
          GridItem() {
            CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
              Column({ space: 6 }) {
                Row() {
                  Text(`${this.stats.musicCount ?? 0}`).fontSize(26).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  Stack({ alignContent: Alignment.Center }) {
                    SymbolGlyph($r('sys.symbol.music_fill')).fontSize(16).fontColor(['#EE6896'])
                  }
                  .width(30).height(30).borderRadius(10)
                  .backgroundColor(HarmonyAppearanceStore.withAlpha('#EE6896', this.isDark ? '26' : '18'))
                }.width('100%')
                Text('音乐').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                NativeAdaptiveBadge({ text: this.monthlyBadgeText(this.stats.musicMonthly, '音乐库'), tintHex: '#EE6896' })
              }.alignItems(HorizontalAlign.Start)
            }
          }
        }
        .columnsTemplate(this.windowWidthVp >= 680 ? '1fr 1fr 1fr 1fr' : '1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .width('100%')
      }
    } else if (modId === 'storage') {
      Column({ space: 10 }) {
        Text('存储空间').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
        CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
          Row({ space: 18 }) {
            Stack() {
              Progress({ value: this.storageRatioPercent(), total: 100, type: ProgressType.Ring })
                .width(86).height(86).color(this.accentHex).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .style({ strokeWidth: 9 })
              Text(`${this.storageRatioPercent().toFixed(1)}%`).fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
            }
            Column({ space: 4 }) {
              Text(`${formatByteSize(this.stats.storageUsedBytes)} / ${formatByteSize(this.stats.storageTotalBytes)}`)
                .fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
              Text('已用 / 总容量').fontSize(12).fontColor(mpSecondaryText(this.isDark))
              Text(`剩余 ${formatByteSize(Math.max(0, this.stats.storageTotalBytes - this.stats.storageUsedBytes))}`)
                .fontSize(13).fontColor(GeneratedDesignTokens.semanticColor('success', this.isDark))
            }.alignItems(HorizontalAlign.Start)
          }.width('100%')
        }
      }
    } else if (modId === 'downloader') {
      Column({ space: 10 }) {
        Text('下载器').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
        CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
          Column({ space: 10 }) {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text(`↓ ${formatSpeed(this.stats.downloadSpeed)}`).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#34C759')
                Text('实时下载').fontSize(11).fontColor(mpSecondaryText(this.isDark))
              }
              .layoutWeight(1).padding(12).borderRadius(14).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).alignItems(HorizontalAlign.Start)

              Column({ space: 4 }) {
                Text(`↑ ${formatSpeed(this.stats.uploadSpeed)}`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.accentHex)
                Text('实时上传').fontSize(11).fontColor(mpSecondaryText(this.isDark))
              }
              .layoutWeight(1).padding(12).borderRadius(14).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).alignItems(HorizontalAlign.Start)
            }
            Text(`累计下载 ${formatByteSize(this.stats.downloadSize)} · 累计上传 ${formatByteSize(this.stats.uploadSize)}`)
              .fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
          }
        }
      }
    } else if (modId === 'medals' && this.community.medals.length > 0) {
      NativeCommunityMedalsWidget({
        githubLogin: this.community.githubLogin,
        earnedCount: this.community.earnedCount,
        totalCount: this.community.totalCount,
        wornMedalId: this.community.wornMedalId ?? '',
        medals: this.community.medals,
        onSelectMedal: (m: MpCommunityMedal) => {
          this.selectedMedal = m;
          this.medalFeedback = '';
          this.showMedalSheet = true;
        }
      })
    } else if (modId === 'memory') {
      Column({ space: 10 }) {
        Text('内存占用').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
        CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
          Column({ space: 8 }) {
            Row() {
              Text('服务端内存').fontSize(14).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
              Text(`${formatByteSize(this.stats.memoryUsedBytes)} · ${this.stats.memoryPercent.toFixed(1)}%`)
                .fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
            }.width('100%')
            Progress({ value: Math.min(100, Math.max(0, this.stats.memoryPercent)), total: 100, type: ProgressType.Linear })
              .color(this.accentHex)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          }
        }
      }
    } else if (modId === 'recent' && this.recentItems.length > 0) {
      Column({ space: 10 }) {
        Text('近期入库').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.recentItems, (it: MpMediaItem) => {
              Column({ space: 5 }) {
                MpRemoteImage({
                  src: it.posterUrl,
                  imgWidth: 96,
                  imgHeight: 140,
                  imgRadius: 12,
                  placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                })
                Text(it.title).fontSize(12).fontWeight(FontWeight.Medium)
                  .fontColor(mpPrimaryText(this.isDark)).maxLines(1).width(96)
              }
              .alignItems(HorizontalAlign.Start)
              .onClick(() => this.onOpenMedia(it))
            }, (it: MpMediaItem) => `dash_rec_${it.id}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
    } else if (modId === 'transfer_trend' && this.stats.transferCounts.length > 0) {
      Column({ space: 10 }) {
        Text('整理趋势').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
        CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
          Row({ space: 8 }) {
            ForEach(this.stats.transferCounts, (count: number, idx: number) => {
              Column({ space: 4 }) {
                Text(`${count}`).fontSize(10).fontColor(mpSecondaryText(this.isDark))
                Column()
                  .width(20)
                  .height(Math.max(8, Math.round((count / this.maxTransfer()) * 84)))
                  .borderRadius(6)
                  .linearGradient({ angle: 180, colors: [[this.accentHex, 0], [HarmonyAppearanceStore.withAlpha(this.accentHex, '55'), 1]] })
                Text(`D${idx + 1}`).fontSize(10).fontColor(mpSecondaryText(this.isDark))
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.End)
              .height(120)
            })
          }.width('100%')
        }
      }
    } else if (modId === 'schedules') {
      Column() {
        CinematicPanel({ panelPadding: 15, cornerRadius: 18, interactive: true }) {
          Row({ space: 12 }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.clock')).fontSize(20).fontColor([this.accentHex])
            }
            .width(40).height(40).borderRadius(20)
            .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '28' : '18'))

            Column({ space: 2 }) {
              Text('定时任务概览').fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
              Text(`当前共有 ${this.stats.scheduleCount} 项后台定时服务在运行`)
                .fontSize(12).fontColor(mpSecondaryText(this.isDark))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([mpSecondaryText(this.isDark)])
          }.width('100%')
        }
      }
      .width('100%')
      .onClick(() => this.onOpenShortcutRoute('diag_schedulers'))
    }
  }

  build() {
    Column() {
      HarmonyPageHeader({
        title: '我的',
        primarySymbol: 'sys.symbol.bell',
        primaryAccessibility: '消息中心',
        onPrimaryClick: () => { this.showMessagesSheet = true; }
      })

      Scroll() {
        Column({ space: 18 }) {
          if (this.loading && !this.hasLoadedOnce) {
            HarmonyBentoDashboardSkeleton()
          } else {
            this.userProfileCardBuilder()

            ForEach(this.modules, (mod: CustomModulePref) => {
              if (mod.enabled) {
                this.renderDashboardModule(mod.id)
              }
            }, (mod: CustomModulePref) => `dm_${mod.id}_${mod.enabled}`)

            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
                .fontSize(16)
                .fontColor([mpPrimaryText(this.isDark)])
              Text('自定义我的模块')
                .fontSize(13.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(mpPrimaryText(this.isDark))
            }
            .height(42)
            .padding({ left: 20, right: 20 })
            .borderRadius(21)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .border({ width: 0.6, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: 21 })
            .onClick(() => { this.showModulesSheet = true; })
          }
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 128 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      Blank().width(0).height(0).bindSheet($$this.showMessagesSheet, this.messagesSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showModulesSheet, this.modulesSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showMedalSheet, this.medalShowcaseSheetBuilder(), {
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

/**
 * 独立单用途系统诊断与捷径页：
 * - `check`：系统检查
 * - `schedulers`：定时服务（支持一键手动触发）
 * - `logs`：实时日志（支持关键词筛选）
 * - `words`：词表管理（5 类大胶囊切换 + 真实保存）
 * - `recognize`：名称识别（在线解析种子/片名）
 * - `network`：网络测试（多节点实时延迟测试）
 */
@Component
export struct HarmonyDiagnosticsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop initialSection: string = 'schedulers'; // 'check' | 'schedulers' | 'logs' | 'words' | 'recognize' | 'network'
  @State private loading: boolean = true;
  @State private checkFailed: boolean = false;
  @State private notice: string = '';

  @State private schedulers: MpSchedulerItem[] = [];
  @State private logs: string[] = [];
  @State private logFilter: string = '';
  @State private stats: MpDashboardStats = {
    movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0,
    storageUsedBytes: 0, storageTotalBytes: 0,
    downloadSpeed: 0, uploadSpeed: 0, downloadSize: 0, uploadSize: 0,
    memoryPercent: 0, memoryUsedBytes: 0, transferCounts: [], scheduleCount: 0
  };
  @State private sitesCount: number = 0;
  @State private downloadersCount: number = 0;
  @State private mediaServersCount: number = 0;

  @State private wordTabIdx: number = 0;
  @State private wordContent: string = '';
  @State private savingWords: boolean = false;

  @State private recTitle: string = '';
  @State private recSubtitle: string = '';
  @State private recResult: MpRecognizeResult | null = null;
  @State private recognizing: boolean = false;

  @State private netItems: MpNetworkCheckItem[] = [];
  @State private testingNet: boolean = false;

  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadCurrentSection();
  }

  private pageTitle(): string {
    if (this.initialSection === 'check') { return '系统检查'; }
    if (this.initialSection === 'logs') { return '实时日志'; }
    if (this.initialSection === 'words') { return '词表'; }
    if (this.initialSection === 'recognize') { return '名称识别'; }
    if (this.initialSection === 'network') { return '网络测试'; }
    return (this.loading && this.schedulers.length === 0) ? '定时服务' : `定时服务 (${this.schedulers.length})`;
  }

  private activeWordCategory(): WordCategoryDef {
    return WORD_CATEGORIES[Math.min(Math.max(0, this.wordTabIdx), WORD_CATEGORIES.length - 1)];
  }

  private wordLineCount(): number {
    return this.wordContent.split('\n').filter((s: string) => s.trim().length > 0).length;
  }

  private async loadCurrentSection(): Promise<void> {
    this.loading = true;
    this.checkFailed = false;
    this.notice = '';
    const repo = MoviePilotRepository.shared();
    try {
      if (this.initialSection === 'check') {
        const res = await Promise.all([
          repo.fetchDashboardStats(),
          repo.fetchSites(),
          repo.fetchDownloaders(),
          repo.fetchMediaServers()
        ]);
        this.stats = res[0];
        this.sitesCount = res[1].filter((s) => s.isActive).length;
        this.downloadersCount = res[2].filter((d) => d.enabled).length;
        this.mediaServersCount = res[3].filter((m) => m.enabled).length;
      } else if (this.initialSection === 'logs') {
        this.logs = await repo.fetchLiveLogs();
      } else if (this.initialSection === 'words') {
        this.wordContent = await repo.fetchSystemSettingText(this.activeWordCategory().settingKey);
      } else if (this.initialSection === 'network') {
        this.testingNet = true;
        this.netItems = await repo.testNetworkConnectivity();
        this.testingNet = false;
      } else if (this.initialSection === 'schedulers') {
        this.schedulers = await repo.fetchSchedulers();
      }
    } catch {
      this.checkFailed = true;
      this.testingNet = false;
    }
    this.loading = false;
  }

  private async saveWords(): Promise<void> {
    if (this.savingWords) { return; }
    this.savingWords = true;
    const cat = this.activeWordCategory();
    const ok = await MoviePilotRepository.shared().saveSystemSettingText(cat.settingKey, this.wordContent, true);
    this.savingWords = false;
    this.notice = ok ? `已保存「${cat.label}」（共 ${this.wordLineCount()} 条）` : '保存失败，请检查后端状态';
  }

  private filteredLogs(): string[] {
    const q = this.logFilter.trim().toLowerCase();
    if (!q) { return this.logs; }
    return this.logs.filter((line: string) => line.toLowerCase().includes(q));
  }

  build() {
    Column({ space: 10 }) {
      if (this.initialSection === 'words') {
        NativeBackHeader({
          title: '词表',
          trailingText: this.savingWords ? '保存中' : '保存',
          trailingPrimary: true,
          onBack: () => this.onBack(),
          onTrailingClick: () => this.saveWords()
        })
      } else {
        NativeBackHeader({
          title: this.pageTitle(),
          trailingSymbol: this.initialSection === 'recognize' ? '' : 'sys.symbol.arrow_clockwise',
          trailingAccessibility: '刷新',
          onBack: () => this.onBack(),
          onTrailingClick: () => this.loadCurrentSection()
        })
      }

      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(12)
          .fontColor('#34C759')
          .padding({ left: 16, right: 16 })
          .width('100%')
      }

      if (this.initialSection === 'words') {
        HarmonyPillTabBar({
          tabs: WORD_CATEGORIES.map((c: WordCategoryDef) => c.label),
          selectedIndex: this.wordTabIdx,
          scrollable: true,
          onSelect: (idx: number) => {
            this.wordTabIdx = idx;
            this.loadCurrentSection();
          }
        })

        Scroll() {
          Column() {
            Column({ space: 14 }) {
              CinematicPanel({ panelPadding: 16, cornerRadius: 20 }) {
                Column({ space: 10 }) {
                  Row() {
                    Text(this.activeWordCategory().title)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                      .layoutWeight(1)
                    if (this.loading) {
                      HarmonySkeletonHost({ loadingLabel: '正在读取词表条数' }) {
                        HarmonySkeletonBlock({ blockWidth: 46, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
                      }
                    } else {
                      NativeAdaptiveBadge({ text: `${this.wordLineCount()} 条`, tintHex: this.accentHex })
                    }
                  }.width('100%')

                  Text(this.activeWordCategory().description)
                    .fontSize(12.5)
                    .fontColor(mpSecondaryText(this.isDark))
                    .lineHeight(18)
                    .width('100%')

                  if (this.loading) {
                    HarmonySkeletonHost({ loadingLabel: '正在加载词表规则内容' }) {
                      Column({ space: 10 }) {
                        HarmonySkeletonBlock({ blockWidth: '72%', blockHeight: 13, cornerRadius: 4 })
                        HarmonySkeletonBlock({ blockWidth: '54%', blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
                        HarmonySkeletonBlock({ blockWidth: '84%', blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
                        HarmonySkeletonBlock({ blockWidth: '42%', blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
                      }
                      .width('100%')
                      .height(170)
                      .padding(14)
                      .borderRadius(12)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      .alignItems(HorizontalAlign.Start)
                    }
                  } else {
                    TextArea({
                      placeholder: this.activeWordCategory().placeholder,
                      text: this.wordContent
                    })
                      .width('100%')
                      .height(170)
                      .fontSize(13.5)
                      .fontColor(mpPrimaryText(this.isDark))
                      .placeholderColor(mpSecondaryText(this.isDark))
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      .borderRadius(12)
                      .onChange((v: string) => { this.wordContent = v; })
                  }

                  Text(`ⓘ ${this.activeWordCategory().inlineHint}`)
                    .fontSize(11.5)
                    .fontColor(mpSecondaryText(this.isDark))
                    .width('100%')
                }
              }

              CinematicPanel({ panelPadding: 16, cornerRadius: 20 }) {
                Column({ space: 10 }) {
                  Text(`ⓘ ${this.activeWordCategory().exampleTitle}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                    .width('100%')

                  Text(this.activeWordCategory().examples)
                    .fontSize(12.5)
                    .fontColor(mpPrimaryText(this.isDark))
                    .lineHeight(21)
                    .width('100%')
                    .padding(12)
                    .borderRadius(12)
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))

                  Text(this.activeWordCategory().guideNote)
                    .fontSize(12)
                    .fontColor(mpSecondaryText(this.isDark))
                    .lineHeight(18)
                    .width('100%')
                }
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: 820 })
            .padding({ left: 16, right: 16, bottom: 44 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      } else if (this.initialSection === 'recognize') {
        Scroll() {
          Column() {
            Column({ space: 14 }) {
              CinematicPanel({ panelPadding: 16, cornerRadius: 20 }) {
                Column({ space: 10 }) {
                  Text('输入种子标题或文件名').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
                  TextInput({ placeholder: '例如：Dune.Part.Two.2024.2160p.BluRay.x265-GROUP', text: this.recTitle })
                    .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
                    .onChange((v: string) => { this.recTitle = v; })
                  TextInput({ placeholder: '副标题（可选）', text: this.recSubtitle })
                    .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
                    .onChange((v: string) => { this.recSubtitle = v; })
                  Button(this.recognizing ? '识别中…' : '立即识别')
                    .width('100%').height(44).borderRadius(22)
                    .backgroundColor(this.accentHex).fontColor(Color.White).fontWeight(FontWeight.Bold)
                    .enabled(!this.recognizing && this.recTitle.trim().length > 0)
                    .onClick(async () => {
                      this.recognizing = true;
                      this.recResult = await MoviePilotRepository.shared().recognizeTitle(this.recTitle, this.recSubtitle);
                      this.recognizing = false;
                    })
                }
              }

              if (this.recognizing) {
                HarmonySkeletonHost({ loadingLabel: '正在在线解析媒体名称' }) {
                  CinematicPanel({ panelPadding: 16, cornerRadius: 20 }) {
                    Row({ space: 12 }) {
                      HarmonySkeletonBlock({ blockWidth: 72, blockHeight: 106, cornerRadius: 10, shimmerSweep: true })
                      Column({ space: 8 }) {
                        HarmonySkeletonBlock({ blockWidth: '68%', blockHeight: 16, cornerRadius: 5 })
                        HarmonySkeletonBlock({ blockWidth: '52%', blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                        HarmonySkeletonBlock({ blockWidth: '40%', blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                        HarmonySkeletonBlock({ blockWidth: '58%', blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                    }
                    .width('100%')
                  }
                }
              } else if (this.recResult) {
                CinematicPanel({ panelPadding: 16, cornerRadius: 20 }) {
                  Row({ space: 12 }) {
                    if (this.recResult.posterUrl.length > 0) {
                      MpRemoteImage({
                        src: this.recResult.posterUrl,
                        imgWidth: 72,
                        imgHeight: 106,
                        imgRadius: 10,
                        placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                      })
                    }
                    Column({ space: 5 }) {
                      Text(this.recResult.title || '未匹配到媒体')
                        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      Text(`${this.recResult.type}${this.recResult.year ? ' · ' + this.recResult.year : ''}${this.recResult.tmdbId ? ' · TMDB ' + this.recResult.tmdbId : ''}`)
                        .fontSize(12).fontColor(this.accentHex)
                      if (this.recResult.season || this.recResult.episode) {
                        Text(`季/集：${this.recResult.season} ${this.recResult.episode}`).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                      }
                      if (this.recResult.resolution || this.recResult.videoEncode || this.recResult.releaseGroup) {
                        Text([this.recResult.resolution, this.recResult.videoEncode, this.recResult.releaseGroup].filter((x: string) => x.length > 0).join(' · '))
                          .fontSize(12).fontColor('#34C759')
                      }
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  }.width('100%')
                }
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: 760 })
            .padding({ left: 16, right: 16, bottom: 44 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      } else if (this.initialSection === 'network') {
        if (this.loading || this.testingNet) {
          HarmonyCardGridSkeleton({
            variant: 'scheduler',
            fillViewport: true,
            bottomPadding: 44
          })
        } else if (this.netItems.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.worldclock')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
            Text('暂无网络连通性检测记录').fontSize(14).fontColor(mpSecondaryText(this.isDark))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.netItems, (item: MpNetworkCheckItem) => {
              GridItem() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                  Row({ space: 10 }) {
                    Column({ space: 3 }) {
                      Text(item.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      Text(item.detail).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    NativeAdaptiveBadge({
                      text: item.ok ? `${item.latencyMs} ms` : '不可达',
                      tintHex: item.ok ? '#34C759' : '#E84855'
                    })
                  }.width('100%')
                }
              }
            }, (item: MpNetworkCheckItem) => item.name)
          }
          .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
          .columnsGap(10)
          .rowsGap(10)
          .padding({ left: 16, right: 16, bottom: 44 })
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      } else if (this.initialSection === 'check') {
        Scroll() {
          Column() {
            Column({ space: 12 }) {
              if (this.loading) {
                HarmonySkeletonHost({ loadingLabel: '正在自检服务端核心组件状态' }) {
                  CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
                    Column({ space: 12 }) {
                      Row() {
                        HarmonySkeletonBlock({ blockWidth: 112, blockHeight: 15, cornerRadius: 5 })
                        Blank()
                        HarmonySkeletonBlock({ blockWidth: 64, blockHeight: 22, cornerRadius: 10, tone: 'subtle' })
                      }.width('100%')
                      Divider().color(HarmonyThemeColors.divider(this.isDark))
                      ForEach([0, 1, 2, 3, 4], (idx: number) => {
                        Row() {
                          HarmonySkeletonBlock({ blockWidth: 108, blockHeight: 14, cornerRadius: 4, tone: 'subtle' })
                          Blank()
                          HarmonySkeletonBlock({ blockWidth: idx >= 3 ? 116 : 56, blockHeight: 14, cornerRadius: 4 })
                        }.width('100%')
                      }, (idx: number) => `chk_sk_${idx}`)
                    }
                  }
                }
              } else {
                CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
                  Column({ space: 10 }) {
                    Row() {
                      Text('服务端连接状态').fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                      NativeAdaptiveBadge({
                        text: this.checkFailed ? '连接异常' : '运行正常',
                        tintHex: this.checkFailed ? '#E84855' : '#34C759'
                      })
                    }.width('100%')
                    Divider().color(HarmonyThemeColors.divider(this.isDark))
                    Row() {
                      Text('已启用站点').fontSize(14).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
                      Text(`${this.sitesCount} 个`).fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    }.width('100%')
                    Row() {
                      Text('已启用下载器').fontSize(14).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
                      Text(`${this.downloadersCount} 个`).fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    }.width('100%')
                    Row() {
                      Text('已连接媒体服务器').fontSize(14).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
                      Text(`${this.mediaServersCount} 个`).fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    }.width('100%')
                    Row() {
                      Text('后台内存使用').fontSize(14).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
                      Text(`${formatByteSize(this.stats.memoryUsedBytes)} (${this.stats.memoryPercent.toFixed(1)}%)`)
                        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    }.width('100%')
                    Row() {
                      Text('存储空间占用').fontSize(14).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
                      Text(`${formatByteSize(this.stats.storageUsedBytes)} / ${formatByteSize(this.stats.storageTotalBytes)}`)
                        .fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                    }.width('100%')
                  }
                }
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: 760 })
            .padding({ left: 16, right: 16, bottom: 44 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }.scrollBar(BarState.Off).layoutWeight(1).width('100%')
      } else if (this.initialSection === 'logs') {
        Column({ space: 10 }) {
          Row() {
            TextInput({ placeholder: '筛选日志关键词（如 ERROR / INFO）…', text: this.logFilter })
              .width('100%')
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              .borderRadius(14)
              .onChange((v: string) => { this.logFilter = v; })
          }.padding({ left: 16, right: 16 })

          Scroll() {
            CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
              if (this.loading && this.logs.length === 0) {
                HarmonySkeletonHost({ loadingLabel: '正在读取实时运行日志' }) {
                  Column({ space: 9 }) {
                    ForEach([92, 76, 88, 64, 94, 72, 84, 58, 90, 68], (pct: number, idx: number) => {
                      HarmonySkeletonBlock({
                        blockWidth: `${pct}%`,
                        blockHeight: 11.5,
                        cornerRadius: 4,
                        tone: idx % 3 === 0 ? 'block' : 'subtle'
                      })
                    }, (_pct: number, idx: number) => `log_sk_${idx}`)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
              } else if (this.filteredLogs().length === 0) {
                Text('暂无匹配的实时日志输出')
                  .fontSize(12.5)
                  .fontColor(mpSecondaryText(this.isDark))
                  .width('100%')
              } else {
                Column({ space: 6 }) {
                  ForEach(this.filteredLogs(), (line: string, idx: number) => {
                    Text(line)
                      .fontSize(11)
                      .fontColor(line.includes('ERROR') ? '#E84855' : (line.includes('WARN') ? '#F29B38' : mpPrimaryText(this.isDark)))
                      .lineHeight(17)
                      .width('100%')
                  }, (_line: string, idx: number) => `log_${idx}`)
                }
              }
            }
          }
          .padding({ left: 16, right: 16, bottom: 44 })
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
        .layoutWeight(1)
      } else {
        if (this.loading && this.schedulers.length === 0) {
          HarmonyCardGridSkeleton({
            variant: 'scheduler',
            fillViewport: true,
            bottomPadding: 44
          })
        } else if (this.schedulers.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.clock')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
            Text('暂无后台定时服务记录').fontSize(14).fontColor(mpSecondaryText(this.isDark))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.schedulers, (s: MpSchedulerItem) => {
              GridItem() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
                  Row({ space: 10 }) {
                    Column({ space: 3 }) {
                      Text(s.name).fontSize(14.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      Text(`${s.provider} · 下次 ${s.nextRun || '等待调度'}`).fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                    Button('运行')
                      .height(32).padding({ left: 12, right: 12 }).borderRadius(16)
                      .fontSize(12).fontWeight(FontWeight.Medium)
                      .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '2C' : '1A'))
                      .fontColor(this.accentHex)
                      .onClick(async () => {
                        const ok = await MoviePilotRepository.shared().runScheduler(s.id);
                        this.notice = ok ? `已触发定时任务「${s.name}」` : '触发失败';
                      })
                  }.width('100%')
                }
              }
            }, (s: MpSchedulerItem) => s.id)
          }
          .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
          .columnsGap(10)
          .rowsGap(10)
          .padding({ left: 16, right: 16, bottom: 44 })
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}
