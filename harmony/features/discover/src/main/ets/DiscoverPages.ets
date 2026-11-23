import {
  MoviePilotRepository,
  MpMediaItem,
  MpMediaServerLibrary
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  NativeTopStatusBarBlur,
  HarmonyPageHeader,
  HarmonyUnderlineTabBar,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonySurfaceModifier,
  HarmonyThemeColors,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import { HarmonyPlaybackRequest } from '@moviepilot/media_player';

interface ExploreSourceDef {
  key: string;
  label: string;
}

const EXPLORE_SOURCES: ExploreSourceDef[] = [
  { key: 'tmdb_movies', label: 'TheMovieDB 电影' },
  { key: 'tmdb_tvs', label: 'TheMovieDB 剧集' },
  { key: 'douban_movies', label: '豆瓣 电影' },
  { key: 'douban_tvs', label: '豆瓣 剧集' },
  { key: 'bangumi', label: 'Bangumi' },
  { key: 'music', label: '音乐榜单' }
];

/** 通用 2:3 影视海报卡片（真实后端图片 + 右上评分/入库角标）。 */
@Component
struct PosterCard {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop item: MpMediaItem = {
    id: '', mediaId: '', tmdbId: '', doubanId: '', title: '', enTitle: '', year: '', type: '电影',
    overview: '', vote: 0, posterUrl: '', backdropUrl: '', logoUrl: '', source: 'themoviedb',
    inLibrary: false, subtitle: '', percent: 0, serverName: '', playUrl: ''
  };
  @Prop cardWidth: number = 118;
  @Prop fillWidth: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.item.posterUrl.length > 0) {
          if (this.fillWidth) {
            Image(this.item.posterUrl)
              .width('100%')
              .aspectRatio(0.67)
              .borderRadius(14)
              .objectFit(ImageFit.Cover)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          } else {
            Image(this.item.posterUrl)
              .width(this.cardWidth)
              .height(Math.round(this.cardWidth * 1.48))
              .borderRadius(14)
              .objectFit(ImageFit.Cover)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          }
        } else {
          if (this.fillWidth) {
            Column()
              .width('100%')
              .aspectRatio(0.67)
              .borderRadius(14)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          } else {
            Column()
              .width(this.cardWidth)
              .height(Math.round(this.cardWidth * 1.48))
              .borderRadius(14)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          }
        }

        if (this.item.inLibrary) {
          Text('已入库')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(9)
            .backgroundColor('#CC28A745')
            .margin(6)
        } else if (this.item.vote > 0) {
          Text(`★ ${this.item.vote.toFixed(1)}`)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFE27A')
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(9)
            .backgroundColor('#B8121218')
            .margin(6)
        }
      }
      .shadow({ radius: 10, color: this.isDark ? '#33000000' : '#14000000', offsetY: 4 })

      Text(this.item.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(mpPrimaryText(this.isDark))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.fillWidth ? '100%' : this.cardWidth)

      if (this.item.year.length > 0 || this.item.subtitle.length > 0) {
        Text(this.item.subtitle || this.item.year)
          .fontSize(11)
          .fontColor(mpSecondaryText(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(this.fillWidth ? '100%' : this.cardWidth)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onTap())
  }
}

/**
 * 鸿蒙发现首页（全幅沉浸 Hero + 滚动感知状态栏渐进保护 + 动态光感悬浮搜索/模块按钮 + 我的媒体库 + 继续观看 + 推荐片库）。
 */
@Component
export struct HarmonyDiscoverPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @State private loading: boolean = true;
  @State private scrollOffsetY: number = 0;
  @State private heroItems: MpMediaItem[] = [];
  @State private continueItems: MpMediaItem[] = [];
  @State private libraries: MpMediaServerLibrary[] = [];
  @State private recentItems: MpMediaItem[] = [];
  @State private popularMovies: MpMediaItem[] = [];
  @State private popularTvs: MpMediaItem[] = [];
  @State private doubanMovies: MpMediaItem[] = [];
  @State private showModulesSheet: boolean = false;
  @State private showLibrarySheet: boolean = false;
  @State private activeLibraryName: string = '';
  @State private libraryItems: MpMediaItem[] = [];
  @State private loadingLibrary: boolean = false;
  @State private showContinue: boolean = true;
  @State private showLibraries: boolean = true;
  @State private showRecent: boolean = true;
  @State private showMovies: boolean = true;
  @State private showTvs: boolean = true;
  private scroller: Scroller = new Scroller();
  onOpenMedia: (item: MpMediaItem) => void = () => {};
  onOpenExplore: (src: string) => void = () => {};
  onOpenSearch: () => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  aboutToAppear(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchRecommend('tmdb_trending'),
        repo.fetchContinueWatching(),
        repo.fetchMediaServerLibraries(),
        repo.fetchRecentlyAdded(),
        repo.fetchRecommend('tmdb_movies'),
        repo.fetchRecommend('tmdb_tvs'),
        repo.fetchRecommend('douban_movies')
      ]);
      this.heroItems = res[0].slice(0, 6);
      this.continueItems = res[1];
      this.libraries = res[2];
      this.recentItems = res[3].slice(0, 12);
      this.popularMovies = res[4].slice(0, 14);
      this.popularTvs = res[5].slice(0, 14);
      this.doubanMovies = res[6].slice(0, 14);
    } catch {
      // keep existing state
    }
    this.loading = false;
  }

  private async openLibrary(lib: MpMediaServerLibrary): Promise<void> {
    this.activeLibraryName = lib.name;
    this.libraryItems = [];
    this.loadingLibrary = true;
    this.showLibrarySheet = true;
    try {
      this.libraryItems = await MoviePilotRepository.shared().fetchMediaServerBrowse(lib.serverName, lib.id);
    } catch {
      this.libraryItems = [];
    }
    this.loadingLibrary = false;
  }

  private gridColumnsTemplate(): string {
    const cols = HarmonyAdaptiveLayout.posterGridColumns(this.windowWidthVp);
    const arr: string[] = [];
    for (let i = 0; i < cols; i++) { arr.push('1fr'); }
    return arr.join(' ');
  }

  @Builder
  modulesSheetBuilder() {
    Column({ space: 12 }) {
      Text('自定义发现模块').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row() {
          Text('继续观看 (Emby / Plex)').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showContinue }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showContinue = v; })
        }.width('100%')
      }
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row() {
          Text('我的媒体库').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showLibraries }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showLibraries = v; })
        }.width('100%')
      }
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row() {
          Text('最近入库').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showRecent }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showRecent = v; })
        }.width('100%')
      }
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row() {
          Text('TMDB 热门电影').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showMovies }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showMovies = v; })
        }.width('100%')
      }
      CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
        Row() {
          Text('TMDB 热门剧集').fontSize(15).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showTvs }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showTvs = v; })
        }.width('100%')
      }
    }
    .padding(20)
    .width('100%')
  }

  @Builder
  libraryBrowseSheetBuilder() {
    Column({ space: 12 }) {
      Text(`${this.activeLibraryName} (${this.libraryItems.length})`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(mpPrimaryText(this.isDark))
        .width('100%')
      if (this.loadingLibrary) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.accentHex)
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.libraryItems, (it: MpMediaItem) => {
            GridItem() {
              PosterCard({
                item: it,
                fillWidth: true,
                onTap: () => {
                  this.showLibrarySheet = false;
                  this.onOpenMedia(it);
                }
              })
            }
          }, (it: MpMediaItem) => it.id)
        }
        .columnsTemplate(this.gridColumnsTemplate())
        .columnsGap(10)
        .rowsGap(14)
        .layoutWeight(1)
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  @Builder
  mediaShelf(title: string, items: MpMediaItem[], exploreKey: string) {
    if (items.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text(title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          if (exploreKey.length > 0) {
            Text('全部 ›')
              .fontSize(13)
              .fontColor(mpSecondaryText(this.isDark))
              .onClick(() => this.onOpenExplore(exploreKey))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(items, (it: MpMediaItem) => {
              PosterCard({
                item: it,
                cardWidth: 118,
                onTap: () => this.onOpenMedia(it)
              })
            }, (it: MpMediaItem) => it.id)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.scroller) {
        Column({ space: 22 }) {
          // 1. 全幅沉浸 Hero 主视觉轮播（底端自然融入当前鸿蒙深/浅画布色）
          if (this.heroItems.length > 0) {
            Swiper() {
              ForEach(this.heroItems, (hero: MpMediaItem) => {
                Stack({ alignContent: Alignment.Bottom }) {
                  if (hero.backdropUrl.length > 0) {
                    Image(hero.backdropUrl)
                      .width('100%')
                      .height(420)
                      .objectFit(ImageFit.Cover)
                  } else {
                    Column()
                      .width('100%')
                      .height(420)
                      .backgroundColor(HarmonyThemeColors.card(this.isDark))
                  }

                  Column()
                    .width('100%')
                    .height(420)
                    .linearGradient({
                      angle: 180,
                      colors: this.isDark
                        ? [['#55000000', 0], ['#10000000', 0.35], ['#CC0D0D11', 0.8], ['#FF0D0D11', 1]]
                        : [['#40000000', 0], ['#10000000', 0.35], ['#B80D0D11', 0.78], ['#FFF1F3F5', 1]]
                    })

                  Column({ space: 8 }) {
                    Text(hero.title)
                      .fontSize(26)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .textAlign(TextAlign.Center)
                      .maxLines(2)
                    Text(`${hero.type}${hero.year ? ' · ' + hero.year : ''}`)
                      .fontSize(13)
                      .fontColor('#E0FFFFFF')
                    if (hero.overview.length > 0) {
                      Text(hero.overview)
                        .fontSize(12)
                        .fontColor('#C4FFFFFF')
                        .maxLines(2)
                        .textAlign(TextAlign.Center)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    Row({ space: 10 }) {
                      NativeAdaptiveBadge({ text: 'TheMovieDB', tintHex: '#20B58E', filled: true })
                      if (hero.vote > 0) {
                        Text(`★ ${hero.vote.toFixed(1)}`)
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#FFE27A')
                      }
                      Text('查看详情 ›')
                        .fontSize(13)
                        .fontColor(Color.White)
                    }
                    .margin({ top: 4 })
                  }
                  .padding({ left: 22, right: 22, bottom: 28 })
                  .alignItems(HorizontalAlign.Center)
                }
                .onClick(() => this.onOpenMedia(hero))
              }, (hero: MpMediaItem) => hero.id)
            }
            .height(420)
            .width('100%')
            .autoPlay(true)
            .interval(5500)
            .indicator(Indicator.dot().selectedColor(this.accentHex).color('#55FFFFFF'))
          } else {
            Column({ space: 10 }) {
              LoadingProgress().width(36).height(36).color(this.accentHex)
              Text(this.loading ? '正在从 MoviePilot 加载推荐片库…' : '暂无推荐内容')
                .fontSize(13)
                .fontColor(mpSecondaryText(this.isDark))
            }
            .width('100%')
            .height(260)
            .justifyContent(FlexAlign.Center)
          }

          // 2. 继续观看（真实 Emby/Plex 进度 16:9 横幅卡片）
          if (this.showContinue && this.continueItems.length > 0) {
            Column({ space: 12 }) {
              Text('继续观看')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(mpPrimaryText(this.isDark))
                .width('100%')
                .padding({ left: 16, right: 16 })

              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.continueItems, (entry: MpMediaItem) => {
                    Column({ space: 6 }) {
                      Stack({ alignContent: Alignment.BottomStart }) {
                        Image(entry.backdropUrl || entry.posterUrl)
                          .width(236)
                          .height(132)
                          .borderRadius(16)
                          .objectFit(ImageFit.Cover)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                        Column()
                          .width(236)
                          .height(64)
                          .borderRadius({ bottomLeft: 16, bottomRight: 16 })
                          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#CC000000', 1]] })
                        Column({ space: 6 }) {
                          Row() {
                            Text(entry.title)
                              .fontSize(13)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(Color.White)
                              .maxLines(1)
                              .layoutWeight(1)
                            if (entry.percent > 0) {
                              Text(`${entry.percent}%`)
                                .fontSize(11)
                                .fontWeight(FontWeight.Bold)
                                .fontColor('#FFE27A')
                            }
                          }
                          .width('100%')
                          Progress({ value: entry.percent, total: 100, type: ProgressType.Linear })
                            .color(Color.White)
                            .backgroundColor('#44FFFFFF')
                        }
                        .padding({ left: 10, right: 10, bottom: 10 })
                      }
                      .shadow({ radius: 10, color: '#33000000', offsetY: 4 })

                      if (entry.subtitle.length > 0) {
                        Text(entry.subtitle)
                          .fontSize(11)
                          .fontColor(mpSecondaryText(this.isDark))
                          .maxLines(1)
                          .width(236)
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .onClick(() => this.onOpenMedia(entry))
                  }, (entry: MpMediaItem) => entry.id)
                }
                .padding({ left: 16, right: 16 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
          }

          // 3. 我的媒体库（真实 Emby/Plex/Jellyfin 库入口，点击浏览库内全部海报）
          if (this.showLibraries && this.libraries.length > 0) {
            Column({ space: 12 }) {
              Text('我的媒体库')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(mpPrimaryText(this.isDark))
                .width('100%')
                .padding({ left: 16, right: 16 })

              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.libraries, (lib: MpMediaServerLibrary) => {
                    Column() {
                      Stack({ alignContent: Alignment.BottomStart }) {
                        if (lib.imageUrl.length > 0) {
                          Image(lib.imageUrl)
                            .width(164)
                            .height(96)
                            .borderRadius(14)
                            .objectFit(ImageFit.Cover)
                            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                        } else {
                          Column()
                            .width(164)
                            .height(96)
                            .borderRadius(14)
                            .backgroundColor(HarmonyThemeColors.card(this.isDark))
                        }
                        Column()
                          .width(164)
                          .height(54)
                          .borderRadius({ bottomLeft: 14, bottomRight: 14 })
                          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#CC000000', 1]] })
                        Column({ space: 2 }) {
                          Text(lib.name).fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White).maxLines(1)
                          if (lib.serverName.length > 0) {
                            Text(lib.serverName).fontSize(10).fontColor('#CCFFFFFF').maxLines(1)
                          }
                        }
                        .padding({ left: 10, right: 10, bottom: 8 })
                        .alignItems(HorizontalAlign.Start)
                      }
                    }
                    .onClick(() => this.openLibrary(lib))
                  }, (lib: MpMediaServerLibrary) => `${lib.serverName}_${lib.id}`)
                }
                .padding({ left: 16, right: 16 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
            .bindSheet($$this.showLibrarySheet, this.libraryBrowseSheetBuilder(), {
              detents: [SheetSize.LARGE],
              blurStyle: BlurStyle.COMPONENT_THIN,
              dragBar: true,
              backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
            })
          }

          // 4. 最近入库 / 热门电影 / 热门剧集 / 豆瓣高分
          if (this.showRecent) {
            this.mediaShelf('最近入库', this.recentItems, '')
          }
          if (this.showMovies) {
            this.mediaShelf('热门电影', this.popularMovies, 'tmdb_movies')
          }
          if (this.showTvs) {
            this.mediaShelf('热门剧集', this.popularTvs, 'tmdb_tvs')
          }
          this.mediaShelf('豆瓣高分电影', this.doubanMovies, 'douban_movies')

          // 底部模块编排入口
          Button('自定义发现模块')
            .height(42)
            .padding({ left: 22, right: 22 })
            .borderRadius(21)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .fontColor(mpPrimaryText(this.isDark))
            .fontSize(13)
            .onClick(() => { this.showModulesSheet = true; })
            .bindSheet($$this.showModulesSheet, this.modulesSheetBuilder(), {
              detents: [SheetSize.MEDIUM, SheetSize.LARGE],
              blurStyle: BlurStyle.COMPONENT_THIN,
              dragBar: true,
              backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
            })
        }
        .padding({ bottom: 124 })
      }
      .scrollBar(BarState.Off)
      .onDidScroll(() => {
        const off = this.scroller.currentOffset();
        this.scrollOffsetY = off ? off.yOffset : 0;
      })
      .width('100%')
      .height('100%')

      // 滚动感知顶部状态栏保护
      NativeTopStatusBarBlur({ visibilityProgress: Math.min(1, Math.max(0, this.scrollOffsetY / 140)) })

      // 右上角动态光感快捷圆钮（搜索 + 发现模块配置）
      Row({ space: 10 }) {
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(true, 'pill', 19, this.accentHex, true, this.dynamicLight))
        .accessibilityText('自定义发现模块')
        .onClick(() => { this.showModulesSheet = true; })

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(38)
        .height(38)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(true, 'pill', 19, this.accentHex, true, this.dynamicLight))
        .accessibilityText('全局搜索')
        .onClick(() => this.onOpenSearch())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 44 })
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙探索片库页（规范左侧大标题 + 多源筛选芯片 + 自适应窗口列数真海报网格）。 */
@Component
export struct HarmonyExplorePage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop initialSource: string = 'tmdb_movies';
  @State private activeSource: string = 'tmdb_movies';
  @State private activeSort: string = 'popularity.desc';
  @State private items: MpMediaItem[] = [];
  @State private loading: boolean = false;
  onOpenMedia: (item: MpMediaItem) => void = () => {};
  onOpenSearch: () => void = () => {};

  aboutToAppear(): void {
    if (this.initialSource.length > 0) {
      this.activeSource = this.initialSource;
    }
    this.fetchCurrent();
  }

  private async fetchCurrent(): Promise<void> {
    this.loading = true;
    try {
      this.items = await MoviePilotRepository.shared().fetchExplore(this.activeSource, this.activeSort, 1);
    } catch {
      this.items = [];
    }
    this.loading = false;
  }

  private gridColumnsTemplate(): string {
    const cols = HarmonyAdaptiveLayout.posterGridColumns(this.windowWidthVp);
    const arr: string[] = [];
    for (let i = 0; i < cols; i++) { arr.push('1fr'); }
    return arr.join(' ');
  }

  build() {
    Column({ space: 10 }) {
      HarmonyPageHeader({
        title: '探索',
        subtitle: '多数据源榜单与条件筛选',
        primarySymbol: 'sys.symbol.magnifyingglass',
        primaryAccessibility: '全局搜索',
        onPrimaryClick: () => this.onOpenSearch()
      })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(EXPLORE_SOURCES, (src: ExploreSourceDef) => {
            NativeAdaptivePill({
              title: src.label,
              selected: this.activeSource === src.key,
              onTap: () => {
                this.activeSource = src.key;
                this.fetchCurrent();
              }
            })
          }, (src: ExploreSourceDef) => src.key)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      if (this.activeSource.startsWith('tmdb')) {
        Row({ space: 8 }) {
          NativeAdaptivePill({
            title: '热门',
            selected: this.activeSort === 'popularity.desc',
            onTap: () => { this.activeSort = 'popularity.desc'; this.fetchCurrent(); }
          })
          NativeAdaptivePill({
            title: '高分',
            selected: this.activeSort === 'vote_average.desc',
            onTap: () => { this.activeSort = 'vote_average.desc'; this.fetchCurrent(); }
          })
          NativeAdaptivePill({
            title: '最新上映',
            selected: this.activeSort === 'release_date.desc',
            onTap: () => { this.activeSort = 'release_date.desc'; this.fetchCurrent(); }
          })
        }
        .width('100%')
        .padding({ left: 16 })
      }

      if (this.loading && this.items.length === 0) {
        Column({ space: 8 }) {
          LoadingProgress().width(32).height(32).color(this.accentHex)
          Text('正在加载探索片库…').fontSize(13).fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.items, (it: MpMediaItem) => {
            GridItem() {
              PosterCard({
                item: it,
                fillWidth: true,
                onTap: () => this.onOpenMedia(it)
              })
            }
          }, (it: MpMediaItem) => it.id)
        }
        .columnsTemplate(this.gridColumnsTemplate())
        .columnsGap(10)
        .rowsGap(14)
        .padding({ left: 16, right: 16, bottom: 124 })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙全局搜索页（规范下划线页签栏切换全网影视与本地媒体库 + 自适应窗口列数结果网格）。 */
@Component
export struct HarmonyGlobalSearchPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @State private query: string = '';
  @State private scopeIndex: number = 0; // 0: 全网影视, 1: 本地媒体库
  @State private results: MpMediaItem[] = [];
  @State private searching: boolean = false;
  onBack: () => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};

  private async runSearch(): Promise<void> {
    const q = this.query.trim();
    if (!q) { return; }
    this.searching = true;
    try {
      this.results = await MoviePilotRepository.shared().searchMedia(q, this.scopeIndex === 0 ? 'media' : 'library');
    } catch {
      this.results = [];
    }
    this.searching = false;
  }

  private gridColumnsTemplate(): string {
    const cols = HarmonyAdaptiveLayout.posterGridColumns(this.windowWidthVp);
    const arr: string[] = [];
    for (let i = 0; i < cols; i++) { arr.push('1fr'); }
    return arr.join(' ');
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({ title: '全局搜索', onBack: () => this.onBack() })

      Row({ space: 8 }) {
        Column() {
          CinematicPanel({ panelPadding: 6, cornerRadius: 20 }) {
            TextInput({ placeholder: '搜索电影、剧集或本地媒体库…', text: this.query })
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.query = v; })
              .onSubmit(() => this.runSearch())
          }
        }
        .layoutWeight(1)

        Button('搜索')
          .height(44)
          .borderRadius(22)
          .backgroundColor(this.accentHex)
          .fontColor(Color.White)
          .fontSize(14)
          .onClick(() => this.runSearch())
      }
      .padding({ left: 16, right: 16 })

      HarmonyUnderlineTabBar({
        tabs: ['全网影视', '本地媒体库'],
        selectedIndex: this.scopeIndex,
        onSelect: (idx: number) => {
          this.scopeIndex = idx;
          if (this.query.trim().length > 0) {
            this.runSearch();
          }
        }
      })

      if (this.searching) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.accentHex)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.results.length > 0) {
        Grid() {
          ForEach(this.results, (it: MpMediaItem) => {
            GridItem() {
              PosterCard({
                item: it,
                fillWidth: true,
                onTap: () => this.onOpenMedia(it)
              })
            }
          }, (it: MpMediaItem) => it.id)
        }
        .columnsTemplate(this.gridColumnsTemplate())
        .columnsGap(10)
        .rowsGap(14)
        .padding({ left: 16, right: 16, bottom: 40 })
        .layoutWeight(1)
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(36).fontColor([mpSecondaryText(this.isDark)])
          Text('输入片名并点击搜索，支持 TMDB、豆瓣与 Emby 媒体库')
            .fontSize(13)
            .fontColor(mpSecondaryText(this.isDark))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ left: 24, right: 24 })
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
