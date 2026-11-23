import {
  RustCoreBridge,
  MoviePilotRepository,
  MpMediaItem,
  MpSubscribeItem,
  MpSubscribeShareItem
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  HarmonyPageHeader,
  HarmonyUnderlineTabBar,
  HarmonySegmentedSwitch,
  HarmonyThemeColors,
  HarmonyAppearanceStore,
  HarmonyAdaptiveLayout,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

/**
 * 鸿蒙「订阅」中心（同时支持底部一级 Tab 与二级追剧日历跳转）：
 * - 顶部采用规范下划线页签栏切换「我的订阅 / 订阅广场」；
 * - 「我的订阅」支持类别芯片过滤（全部/电影/电视剧/音乐）、2:3 海报、Rust 追剧进度条与暂停/恢复抽屉；
 * - 「订阅广场」采用鸿蒙互斥分段控制器切换「热门电影 / 热门剧集 / 社区分享」并实时拉取真实接口。
 */
@Component
export struct HarmonySubscriptionsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop showBack: boolean = false;
  @Prop initialTitle: string = '订阅';
  @State private mainTabIndex: number = 0; // 0: 我的订阅, 1: 订阅广场
  @State private squareModeIndex: number = 0; // 0: 热门电影, 1: 热门剧集, 2: 社区分享
  @State private filter: string = '全部';
  @State private loading: boolean = true;
  @State private loadingSquare: boolean = false;
  @State private items: MpSubscribeItem[] = [];
  @State private popularMovies: MpMediaItem[] = [];
  @State private popularTvs: MpMediaItem[] = [];
  @State private shares: MpSubscribeShareItem[] = [];
  @State private selectedSub: MpSubscribeItem | null = null;
  @State private showEditor: boolean = false;
  onBack: () => void = () => {};
  onOpenSearch: () => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};

  aboutToAppear(): void {
    this.loadSubscriptions();
  }

  private async loadSubscriptions(): Promise<void> {
    this.loading = true;
    try {
      this.items = await MoviePilotRepository.shared().fetchSubscriptions();
    } catch {
      this.items = [];
    }
    this.loading = false;
  }

  private async loadSquareIfNeeded(): Promise<void> {
    if (this.squareModeIndex === 0 && this.popularMovies.length > 0) { return; }
    if (this.squareModeIndex === 1 && this.popularTvs.length > 0) { return; }
    if (this.squareModeIndex === 2 && this.shares.length > 0) { return; }
    this.loadingSquare = true;
    const repo = MoviePilotRepository.shared();
    try {
      if (this.squareModeIndex === 0) {
        this.popularMovies = await repo.fetchSubscribePopular('电影');
      } else if (this.squareModeIndex === 1) {
        this.popularTvs = await repo.fetchSubscribePopular('电视剧');
      } else {
        this.shares = await repo.fetchSubscribeShares();
      }
    } catch {
      // keep existing state
    }
    this.loadingSquare = false;
  }

  private filteredItems(): MpSubscribeItem[] {
    if (this.filter === '全部') { return this.items; }
    return this.items.filter((i: MpSubscribeItem) => i.type === this.filter);
  }

  private posterColumnsTemplate(): string {
    const cols = HarmonyAdaptiveLayout.posterGridColumns(this.windowWidthVp);
    const parts: string[] = [];
    for (let i = 0; i < cols; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  @Builder
  editorSheetBuilder() {
    Column({ space: 14 }) {
      Text(this.selectedSub ? `订阅详情：${this.selectedSub.name}` : '订阅详情')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(mpPrimaryText(this.isDark))
        .width('100%')

      if (this.selectedSub) {
        CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
          Column({ space: 6 }) {
            Text(`类型：${this.selectedSub.type}${this.selectedSub.year ? ' · ' + this.selectedSub.year : ''}`)
              .fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Text(`质量：${this.selectedSub.quality || '默认'} · 分辨率：${this.selectedSub.resolution || '自动'}`)
              .fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Text(`目录：${this.selectedSub.savePath || '自动分配目录'}`)
              .fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          }
        }
        Button(this.selectedSub.state === 'S' ? '恢复订阅' : '暂停订阅')
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(this.accentHex)
          .fontColor(Color.White)
          .onClick(async () => {
            if (this.selectedSub) {
              await MoviePilotRepository.shared().toggleSubscribeState(this.selectedSub);
              this.showEditor = false;
              await this.loadSubscriptions();
            }
          })
      }
    }
    .padding(20)
    .width('100%')
  }

  @Builder
  popularGrid(list: MpMediaItem[]) {
    Grid() {
      ForEach(list, (it: MpMediaItem) => {
        GridItem() {
          Column({ space: 6 }) {
            Stack({ alignContent: Alignment.TopEnd }) {
              if (it.posterUrl.length > 0) {
                Image(it.posterUrl)
                  .width('100%')
                  .aspectRatio(0.67)
                  .borderRadius(12)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              } else {
                Column()
                  .width('100%')
                  .aspectRatio(0.67)
                  .borderRadius(12)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              }
              if (it.vote > 0) {
                Text(`★ ${it.vote.toFixed(1)}`)
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFE27A')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(8)
                  .backgroundColor('#B8121218')
                  .margin(5)
              }
            }
            Text(it.title)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpPrimaryText(this.isDark))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (it.year.length > 0) {
              Text(it.year).fontSize(11).fontColor(mpSecondaryText(this.isDark)).width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.onOpenMedia(it))
        }
      }, (it: MpMediaItem) => it.id)
    }
    .columnsTemplate(this.posterColumnsTemplate())
    .columnsGap(10)
    .rowsGap(14)
    .padding({ left: 16, right: 16, top: 6, bottom: this.showBack ? 40 : 124 })
    .layoutWeight(1)
  }

  build() {
    Column({ space: 8 }) {
      if (this.showBack) {
        NativeBackHeader({
          title: `${this.initialTitle} (${this.items.length})`,
          onBack: () => this.onBack()
        })
      } else {
        HarmonyPageHeader({
          title: '订阅',
          subtitle: `${this.items.length} 项正在自动追更`,
          primarySymbol: 'sys.symbol.magnifyingglass',
          primaryAccessibility: '全局搜索',
          onPrimaryClick: () => this.onOpenSearch()
        })
      }

      HarmonyUnderlineTabBar({
        tabs: [`我的订阅 (${this.items.length})`, '订阅广场'],
        selectedIndex: this.mainTabIndex,
        onSelect: (idx: number) => {
          this.mainTabIndex = idx;
          if (idx === 1) {
            this.loadSquareIfNeeded();
          }
        }
      })

      if (this.mainTabIndex === 0) {
        Row({ space: 8 }) {
          ForEach(['全部', '电影', '电视剧', '音乐'], (tab: string) => {
            NativeAdaptivePill({ title: tab, selected: this.filter === tab, onTap: () => { this.filter = tab; } })
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })

        if (this.loading && this.items.length === 0) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.accentHex)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.filteredItems().length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.star')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
            Text('暂无匹配的订阅条目').fontSize(14).fontColor(mpSecondaryText(this.isDark))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              ForEach(this.filteredItems(), (sub: MpSubscribeItem) => {
                Column() {
                  CinematicPanel({ panelPadding: 12, cornerRadius: 18, interactive: true }) {
                    Row({ space: 12 }) {
                      if (sub.posterUrl.length > 0) {
                        Image(sub.posterUrl)
                          .width(66)
                          .height(98)
                          .borderRadius(10)
                          .objectFit(ImageFit.Cover)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      } else {
                        Column()
                          .width(66)
                          .height(98)
                          .borderRadius(10)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      }

                      Column({ space: 6 }) {
                        Row() {
                          Text(sub.name)
                            .fontSize(15)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(mpPrimaryText(this.isDark))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          NativeAdaptiveBadge({
                            text: sub.state === 'S' ? '已暂停' : '订阅中',
                            tintHex: sub.state === 'S' ? '#FAAD14' : '#52C41A'
                          })
                        }
                        .width('100%')

                        Text(`${sub.type}${sub.year ? ' · ' + sub.year : ''}${sub.season > 0 ? ' · 第' + sub.season + '季' : ''}`)
                          .fontSize(12)
                          .fontColor(mpSecondaryText(this.isDark))
                          .width('100%')

                        if (sub.totalEpisode > 0) {
                          Text(`追剧进度 ${RustCoreBridge.computeSubscribeProgress(sub.totalEpisode, sub.lackEpisode).label}`)
                            .fontSize(11)
                            .fontColor(this.accentHex)
                            .width('100%')
                          Progress({
                            value: RustCoreBridge.computeSubscribeProgress(sub.totalEpisode, sub.lackEpisode).completed,
                            total: sub.totalEpisode,
                            type: ProgressType.Linear
                          })
                            .color(this.accentHex)
                            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                        }
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .onClick(() => {
                  this.selectedSub = sub;
                  this.showEditor = true;
                })
              }, (sub: MpSubscribeItem) => String(sub.id))
            }
            .padding({ left: 16, right: 16, top: 4, bottom: this.showBack ? 40 : 124 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      } else {
        Column() {
          HarmonySegmentedSwitch({
            options: ['热门电影', '热门剧集', '社区分享'],
            selectedIndex: this.squareModeIndex,
            onSelect: (idx: number) => {
              this.squareModeIndex = idx;
              this.loadSquareIfNeeded();
            }
          })
        }
        .padding({ left: 16, right: 16, top: 4 })

        if (this.loadingSquare) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.accentHex)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.squareModeIndex === 0) {
          this.popularGrid(this.popularMovies)
        } else if (this.squareModeIndex === 1) {
          this.popularGrid(this.popularTvs)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.shares, (sh: MpSubscribeShareItem) => {
                CinematicPanel({ panelPadding: 13, cornerRadius: 18 }) {
                  Row({ space: 12 }) {
                    if (sh.posterUrl.length > 0) {
                      Image(sh.posterUrl)
                        .width(56)
                        .height(82)
                        .borderRadius(10)
                        .objectFit(ImageFit.Cover)
                        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    }
                    Column({ space: 5 }) {
                      Row({ space: 6 }) {
                        Text(sh.shareTitle || sh.name)
                          .fontSize(14)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(mpPrimaryText(this.isDark))
                          .maxLines(1)
                          .layoutWeight(1)
                        NativeAdaptiveBadge({ text: `${sh.count} 复用`, tintHex: this.accentHex })
                      }.width('100%')
                      if (sh.shareComment.length > 0) {
                        Text(sh.shareComment)
                          .fontSize(12)
                          .fontColor(mpSecondaryText(this.isDark))
                          .maxLines(2)
                          .width('100%')
                      }
                      Text(`分享者：${sh.shareUser} · ${sh.type}${sh.year ? ' · ' + sh.year : ''}`)
                        .fontSize(11)
                        .fontColor(mpSecondaryText(this.isDark))
                        .width('100%')
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }.width('100%')
                }
              }, (sh: MpSubscribeShareItem) => String(sh.id))
            }
            .padding({ left: 16, right: 16, top: 6, bottom: this.showBack ? 40 : 124 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      }
    }
    .bindSheet($$this.showEditor, this.editorSheetBuilder(), {
      detents: [SheetSize.MEDIUM],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .width('100%')
    .height('100%')
  }
}
