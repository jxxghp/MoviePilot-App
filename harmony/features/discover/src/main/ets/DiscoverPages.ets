import {
  MoviePilotRepository,
  MpMediaItem,
  MpMediaServerLibrary,
  MpMusicAlbum,
  MpRemoteImage
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  CustomModulePref,
  DEFAULT_DISCOVER_MODULES,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  NativeTopStatusBarBlur,
  HarmonyPageHeader,
  HarmonyPillTabBar,
  HarmonySheetHeader,
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

interface CategoryEntryDef {
  title: string;
  sourceKey: string;
  posterUrl: string;
}

/**
 * 发现页独立海报横滑模块（使用独立 `@Component` + `@Prop`，确保异步数据加载后 100% 响应式刷新）。
 */
@Component
struct DiscoverMediaShelf {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop title: string = '';
  @Prop items: MpMediaItem[] = [];
  @Prop exploreKey: string = '';
  onOpenMedia: (item: MpMediaItem) => void = () => {};
  onOpenExplore: (src: string) => void = () => {};

  build() {
    if (this.items.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text(this.title)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          if (this.exploreKey.length > 0) {
            Row({ space: 2 }) {
              Text('全部').fontSize(13).fontColor(this.accentHex).fontWeight(FontWeight.Medium)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.accentHex])
            }
            .onClick(() => this.onOpenExplore(this.exploreKey))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.items, (it: MpMediaItem) => {
              PosterCard({
                item: it,
                cardWidth: 116,
                onTap: () => this.onOpenMedia(it)
              })
            }, (it: MpMediaItem) => `${this.title}_${it.id}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
      .width('100%')
    }
  }
}

const EXPLORE_SOURCES: ExploreSourceDef[] = [
  { key: 'tmdb_movies', label: 'TMDB 电影' },
  { key: 'tmdb_tvs', label: 'TMDB 剧集' },
  { key: 'douban_movies', label: '豆瓣 电影' },
  { key: 'douban_tvs', label: '豆瓣 剧集' },
  { key: 'bangumi', label: 'Bangumi' },
  { key: 'music', label: '音乐' }
];

const HOT_SEARCH_KEYWORDS: string[] = [
  '奥德赛', '钢铁侠', '超感神探', '庆余年', '星际穿越', '沙丘', '三体'
];

const SEARCH_SCOPES: string[] = ['媒体', '媒体库', '人物', '音乐', '合集'];
const SEARCH_SCOPE_KEYS: string[] = ['media', 'library', 'person', 'music', 'collection'];

function formatCommaInt(n: number): string {
  const s = String(Math.max(0, Math.round(n)));
  let out = '';
  let cnt = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    out = s[i] + out;
    cnt++;
    if (cnt % 3 === 0 && i > 0) {
      out = ',' + out;
    }
  }
  return out;
}

/** 通用 2:3 影视海报卡片（右上角评分或绿色已入库标记）。 */
@Component
struct PosterCard {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop item: MpMediaItem = {
    id: '', mediaId: '', tmdbId: '', doubanId: '', title: '', enTitle: '', year: '', type: '电影',
    overview: '', vote: 0, posterUrl: '', backdropUrl: '', logoUrl: '', source: 'themoviedb',
    inLibrary: false, subtitle: '', percent: 0, serverName: '', playUrl: ''
  };
  @Prop cardWidth: number = 116;
  @Prop fillWidth: boolean = false;
  @Prop showPlayBadge: boolean = false;
  onTap: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.item.posterUrl.length > 0) {
          if (this.fillWidth) {
            MpRemoteImage({
              src: this.item.posterUrl,
              imgWidth: '100%',
              imgAspectRatio: 0.67,
              imgRadius: 14,
              placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
            })
          } else {
            MpRemoteImage({
              src: this.item.posterUrl,
              imgWidth: this.cardWidth,
              imgHeight: Math.round(this.cardWidth * 1.48),
              imgRadius: 14,
              placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
            })
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

        if (this.showPlayBadge) {
          Stack() {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(12).fontColor([Color.White])
          }
          .width(26)
          .height(26)
          .borderRadius(13)
          .backgroundColor('#99000000')
          .position({ right: 6, bottom: 6 })
        } else if (this.item.inLibrary) {
          Stack() {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(11).fontColor([Color.White])
          }
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor('#E034C759')
          .border({ width: 1.2, color: Color.White, radius: 11 })
          .margin(6)
        } else if (this.item.vote > 0) {
          Text(this.item.vote.toFixed(1))
            .fontSize(10.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .borderRadius(9)
            .backgroundColor('#B810141E')
            .margin(6)
        }
      }
      .shadow({ radius: 10, color: this.isDark ? '#30000000' : '#14000000', offsetY: 4 })

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
 * 鸿蒙「发现」首页（100% 对齐 iOS 10 大模块 + 顶部固定 Hero 锚点 + 媒体库封面无遮挡 + 自定义开关与顺序）：
 * - 继续观看 / 热门电影 / 热门剧集 / 本周趋势 (16:9) / 热门音乐 (1:1) / 豆瓣热映 / 豆瓣 Top250 / 最新入库 / 我的媒体库 / 分类浏览；
 * - 「我的媒体库」封面不叠标题文字、不盖底部黑罩，仅在右上角精巧显示条目数量角标，点击进入独立全屏媒体库页。
 */
@Component
export struct HarmonyDiscoverPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_DISCOVER_MODULES) modulesRaw: string = '';
  @State private loading: boolean = true;
  @State private scrollOffsetY: number = 0;
  @State private heroItems: MpMediaItem[] = [];
  @State private trendingItems: MpMediaItem[] = [];
  @State private continueItems: MpMediaItem[] = [];
  @State private libraries: MpMediaServerLibrary[] = [];
  @State private recentItems: MpMediaItem[] = [];
  @State private popularMovies: MpMediaItem[] = [];
  @State private popularTvs: MpMediaItem[] = [];
  @State private doubanShowing: MpMediaItem[] = [];
  @State private doubanTop250: MpMediaItem[] = [];
  @State private musicAlbums: MpMusicAlbum[] = [];
  @State private modules: CustomModulePref[] = DEFAULT_DISCOVER_MODULES;
  @State private showModulesSheet: boolean = false;
  private scroller: Scroller = new Scroller();
  onOpenMedia: (item: MpMediaItem) => void = () => {};
  onOpenExplore: (src: string) => void = () => {};
  onOpenSearch: () => void = () => {};
  onOpenLibrary: (libraryId: string, serverName: string) => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  aboutToAppear(): void {
    this.modules = HarmonyAppearanceStore.parseModules(this.modulesRaw, DEFAULT_DISCOVER_MODULES);
    this.loadData();
  }

  private persistModules(next: CustomModulePref[]): void {
    this.modules = next;
    this.modulesRaw = JSON.stringify(next);
    this.loadOptionalModulesIfNeeded();
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
        repo.fetchMusicFeed('douban', 1)
      ]);
      this.trendingItems = res[0].slice(0, 14);
      this.heroItems = res[0].slice(0, 6);
      this.continueItems = res[1];
      this.libraries = res[2];
      this.recentItems = res[3].slice(0, 14);
      this.popularMovies = res[4].slice(0, 14);
      this.popularTvs = res[5].slice(0, 14);
      this.musicAlbums = res[6].slice(0, 14);
    } catch {
      // keep existing state
    }
    this.loading = false;
    await this.loadOptionalModulesIfNeeded();
  }

  private async loadOptionalModulesIfNeeded(): Promise<void> {
    const repo = MoviePilotRepository.shared();
    const showShowing = this.modules.some((m: CustomModulePref) => m.id === 'douban_showing' && m.enabled);
    const showTop250 = this.modules.some((m: CustomModulePref) => m.id === 'douban_top250' && m.enabled);
    if (showShowing && this.doubanShowing.length === 0) {
      try { this.doubanShowing = (await repo.fetchDoubanShowing(1)).slice(0, 14); } catch { /* ignore */ }
    }
    if (showTop250 && this.doubanTop250.length === 0) {
      try { this.doubanTop250 = (await repo.fetchDoubanTop250(1)).slice(0, 14); } catch { /* ignore */ }
    }
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

  private async playContinueItem(entry: MpMediaItem): Promise<void> {
    try {
      const manifest = await MoviePilotRepository.shared().fetchVideoStreamInfo(entry.id, entry.serverName);
      if (manifest && manifest.contentUrl.length > 0) {
        this.onPlayMedia({
          url: manifest.contentUrl,
          title: manifest.title || entry.title,
          subtitle: entry.subtitle || entry.serverName,
          isAudio: manifest.mediaType === 'audio'
        });
        return;
      }
    } catch {
      // fall through to detail page
    }
    this.onOpenMedia(entry);
  }

  private categoryEntries(): CategoryEntryDef[] {
    return [
      { title: 'TMDB 电影', sourceKey: 'tmdb_movies', posterUrl: this.popularMovies.length > 0 ? this.popularMovies[0].posterUrl : '' },
      { title: 'TMDB 剧集', sourceKey: 'tmdb_tvs', posterUrl: this.popularTvs.length > 0 ? this.popularTvs[0].posterUrl : '' },
      { title: '豆瓣片库', sourceKey: 'douban_movies', posterUrl: this.popularMovies.length > 1 ? this.popularMovies[1].posterUrl : '' },
      { title: 'Bangumi 番剧', sourceKey: 'bangumi', posterUrl: this.popularTvs.length > 1 ? this.popularTvs[1].posterUrl : '' },
      { title: '音乐探索', sourceKey: 'music', posterUrl: this.musicAlbums.length > 0 ? this.musicAlbums[0].coverUrl : '' }
    ];
  }

  @Builder
  modulesSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '编辑发现模块',
        cancelText: '完成',
        actionText: '恢复默认',
        onCancel: () => { this.showModulesSheet = false; },
        onAction: () => {
          this.persistModules(DEFAULT_DISCOVER_MODULES.map((m: CustomModulePref): CustomModulePref => ({
            id: m.id, title: m.title, enabled: m.enabled
          })));
        }
      })
      Text('开关显隐并调整发现页 10 大模块的展示顺序')
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
              }
              .width('100%')
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
  mediaShelf(title: string, items: MpMediaItem[], exploreKey: string) {
    if (items.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text(title)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          if (exploreKey.length > 0) {
            Row({ space: 2 }) {
              Text('全部').fontSize(13).fontColor(this.accentHex).fontWeight(FontWeight.Medium)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.accentHex])
            }
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
                cardWidth: 116,
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

  @Builder
  trendingBackdropShelf() {
    if (this.trendingItems.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text('本周趋势')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          Row({ space: 2 }) {
            Text('全部').fontSize(13).fontColor(this.accentHex).fontWeight(FontWeight.Medium)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.accentHex])
          }
          .onClick(() => this.onOpenExplore('tmdb_movies'))
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.trendingItems, (it: MpMediaItem) => {
              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.TopEnd }) {
                  MpRemoteImage({
                    src: it.backdropUrl || it.posterUrl,
                    imgWidth: 228,
                    imgHeight: 128,
                    imgRadius: 16,
                    placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                  })
                  if (it.vote > 0) {
                    Text(it.vote.toFixed(1))
                      .fontSize(10.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                      .borderRadius(9)
                      .backgroundColor('#B810141E')
                      .margin(8)
                  }
                }
                Text(it.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(228)
                Text(`${it.year ? it.year + ' · ' : ''}${it.type}`)
                  .fontSize(11.5)
                  .fontColor(mpSecondaryText(this.isDark))
                  .width(228)
              }
              .alignItems(HorizontalAlign.Start)
              .onClick(() => this.onOpenMedia(it))
            }, (it: MpMediaItem) => `tr_${it.id}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
    }
  }

  @Builder
  musicShelf() {
    if (this.musicAlbums.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text('热门音乐')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          Row({ space: 2 }) {
            Text('全部').fontSize(13).fontColor(this.accentHex).fontWeight(FontWeight.Medium)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.accentHex])
          }
          .onClick(() => this.onOpenExplore('music'))
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.musicAlbums, (al: MpMusicAlbum) => {
              Column({ space: 6 }) {
                if (al.coverUrl.length > 0) {
                  MpRemoteImage({
                    src: al.coverUrl,
                    imgWidth: 126,
                    imgHeight: 126,
                    imgRadius: 16,
                    placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                  })
                } else {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.music')).fontSize(32).fontColor([this.accentHex])
                  }
                  .width(126).height(126).borderRadius(16).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                }
                Text(al.title)
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(126)
                Text(`${al.artist || '音乐专辑'}${al.year ? ' · ' + al.year : ''}`)
                  .fontSize(11)
                  .fontColor(mpSecondaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(126)
              }
              .alignItems(HorizontalAlign.Start)
              .onClick(() => this.onOpenExplore('music'))
            }, (al: MpMusicAlbum) => `mu_${al.id}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
    }
  }

  @Builder
  librariesShelf() {
    if (this.libraries.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text('我的媒体库')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          Row({ space: 2 }) {
            Text(this.libraries[0].serverName || '全部')
              .fontSize(13)
              .fontColor(this.accentHex)
              .fontWeight(FontWeight.Medium)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.accentHex])
          }
          .onClick(() => this.onOpenLibrary(this.libraries[0].id, this.libraries[0].serverName))
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        // 封面完全无遮挡：不盖底部渐变、不叠文字标题，仅在右上角精巧显示条目数量角标
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.libraries, (lib: MpMediaServerLibrary) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                if (lib.imageUrl.length > 0) {
                  MpRemoteImage({
                    src: lib.imageUrl,
                    imgWidth: 196,
                    imgHeight: 112,
                    imgRadius: 16,
                    placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                  })
                } else {
                  Stack() {
                    Text(lib.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                  }
                  .width(196)
                  .height(112)
                  .borderRadius(16)
                  .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
                }

                if (lib.itemCount !== undefined && lib.itemCount >= 0) {
                  Text(formatCommaInt(lib.itemCount))
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                    .borderRadius(12)
                    .backgroundColor('#99000000')
                    .border({ width: 0.6, color: '#38FFFFFF', radius: 12 })
                    .margin(8)
                }
              }
              .shadow({ radius: 10, color: this.isDark ? '#30000000' : '#14000000', offsetY: 4 })
              .onClick(() => this.onOpenLibrary(lib.id, lib.serverName))
            }, (lib: MpMediaServerLibrary) => `${lib.serverName}_${lib.id}`)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
    }
  }

  @Builder
  categoriesShelf() {
    Column({ space: 12 }) {
      Text('分类浏览')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(mpPrimaryText(this.isDark))
        .width('100%')

      Grid() {
        ForEach(this.categoryEntries(), (cat: CategoryEntryDef) => {
          GridItem() {
            Column() {
              CinematicPanel({ panelPadding: 9, cornerRadius: 16, interactive: true }) {
                Row({ space: 8 }) {
                  if (cat.posterUrl.length > 0) {
                    MpRemoteImage({
                      src: cat.posterUrl,
                      imgWidth: 36,
                      imgHeight: 36,
                      imgRadius: 9,
                      placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                    })
                  } else {
                    Stack() {
                      SymbolGlyph($r('sys.symbol.film')).fontSize(17).fontColor([this.accentHex])
                    }
                    .width(36).height(36).borderRadius(9).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  }
                  Text(cat.title)
                    .fontSize(13.5)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
              }
            }
            .width('100%')
            .onClick(() => this.onOpenExplore(cat.sourceKey))
          }
        }, (cat: CategoryEntryDef) => `${cat.sourceKey}_${cat.posterUrl}`)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
    }
    .padding({ left: 16, right: 16 })
  }

  @Builder
  renderModuleById(modId: string) {
    if (modId === 'continue' && this.continueItems.length > 0) {
      Column({ space: 12 }) {
        Text('继续观看')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .width('100%')
          .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.continueItems, (entry: MpMediaItem) => {
              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.BottomStart }) {
                  MpRemoteImage({
                    src: entry.backdropUrl || entry.posterUrl,
                    imgWidth: 238,
                    imgHeight: 134,
                    imgRadius: 16,
                    placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                  })
                  Column()
                    .width(238)
                    .height(52)
                    .borderRadius({ bottomLeft: 16, bottomRight: 16 })
                    .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#C8000000', 1]] })
                  Column({ space: 6 }) {
                    if (entry.percent > 0) {
                      Text(`看到 ${entry.percent}%`)
                        .fontSize(11)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                    }
                    Progress({ value: entry.percent, total: 100, type: ProgressType.Linear })
                      .color(Color.White)
                      .backgroundColor('#44FFFFFF')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .padding({ left: 10, right: 10, bottom: 10 })
                }
                .shadow({ radius: 10, color: '#30000000', offsetY: 4 })

                Text(entry.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(1)
                  .width(238)
                if (entry.subtitle.length > 0) {
                  Text(entry.subtitle)
                    .fontSize(11.5)
                    .fontColor(mpSecondaryText(this.isDark))
                    .maxLines(1)
                    .width(238)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .onClick(() => this.playContinueItem(entry))
            }, (entry: MpMediaItem) => entry.id)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
    } else if (modId === 'movies') {
      DiscoverMediaShelf({
        title: '热门电影',
        items: this.popularMovies,
        exploreKey: 'tmdb_movies',
        onOpenMedia: (it: MpMediaItem) => this.onOpenMedia(it),
        onOpenExplore: (src: string) => this.onOpenExplore(src)
      })
    } else if (modId === 'tvs') {
      DiscoverMediaShelf({
        title: '热门剧集',
        items: this.popularTvs,
        exploreKey: 'tmdb_tvs',
        onOpenMedia: (it: MpMediaItem) => this.onOpenMedia(it),
        onOpenExplore: (src: string) => this.onOpenExplore(src)
      })
    } else if (modId === 'trending') {
      this.trendingBackdropShelf()
    } else if (modId === 'douban_music') {
      this.musicShelf()
    } else if (modId === 'douban_showing') {
      DiscoverMediaShelf({
        title: '豆瓣热映',
        items: this.doubanShowing,
        exploreKey: 'douban_movies',
        onOpenMedia: (it: MpMediaItem) => this.onOpenMedia(it),
        onOpenExplore: (src: string) => this.onOpenExplore(src)
      })
    } else if (modId === 'douban_top250') {
      DiscoverMediaShelf({
        title: '豆瓣 Top250',
        items: this.doubanTop250,
        exploreKey: 'douban_movies',
        onOpenMedia: (it: MpMediaItem) => this.onOpenMedia(it),
        onOpenExplore: (src: string) => this.onOpenExplore(src)
      })
    } else if (modId === 'latest') {
      DiscoverMediaShelf({
        title: '最新入库',
        items: this.recentItems,
        exploreKey: '',
        onOpenMedia: (it: MpMediaItem) => this.onOpenMedia(it),
        onOpenExplore: (src: string) => this.onOpenExplore(src)
      })
    } else if (modId === 'libraries') {
      this.librariesShelf()
    } else if (modId === 'categories') {
      this.categoriesShelf()
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll(this.scroller) {
        Column({ space: 22 }) {
          // 1. 顶部固定 Hero 轮播（始终占位 420vp，避免异步数据加载后发生跳滚）
          if (this.heroItems.length > 0) {
            Swiper() {
              ForEach(this.heroItems, (hero: MpMediaItem) => {
                Stack({ alignContent: Alignment.Bottom }) {
                  if (hero.backdropUrl.length > 0) {
                    MpRemoteImage({
                      src: hero.backdropUrl,
                      imgWidth: '100%',
                      imgHeight: 420,
                      placeholderColor: HarmonyThemeColors.card(this.isDark)
                    })
                  } else {
                    Column()
                      .width('100%')
                      .height(420)
                      .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
                  }

                  Column()
                    .width('100%')
                    .height(420)
                    .linearGradient({
                      angle: 180,
                      colors: this.isDark
                        ? [
                          ['#40000000', 0],
                          ['#10000000', 0.36],
                          [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(true, this.paletteId), 'CC'), 0.80],
                          [HarmonyThemeColors.canvas(true, this.paletteId), 1]
                        ]
                        : [
                          ['#30000000', 0],
                          ['#08000000', 0.38],
                          [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(false, this.paletteId), 'C8'), 0.80],
                          [HarmonyThemeColors.canvas(false, this.paletteId), 1]
                        ]
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
                      .fontColor('#E6FFFFFF')
                    if (hero.overview.length > 0) {
                      Text(hero.overview)
                        .fontSize(12)
                        .fontColor('#CCFFFFFF')
                        .maxLines(2)
                        .textAlign(TextAlign.Center)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    Row({ space: 10 }) {
                      NativeAdaptiveBadge({ text: 'TheMovieDB', tintHex: '#20B58E', filled: true })
                      if (hero.vote > 0) {
                        Text(`★ ${hero.vote.toFixed(1)}`)
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#FFE27A')
                      }
                      Text('查看详情 ›')
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
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
              LoadingProgress().width(34).height(34).color(this.accentHex)
              Text(this.loading ? '正在加载发现内容…' : '暂无推荐内容')
                .fontSize(13)
                .fontColor(mpSecondaryText(this.isDark))
            }
            .width('100%')
            .height(420)
            .justifyContent(FlexAlign.Center)
          }

          // 2. 按用户自定义顺序与显隐渲染全部 10 大发现模块
          ForEach(this.modules, (mod: CustomModulePref) => {
            if (mod.enabled) {
              this.renderModuleById(mod.id)
            }
          }, (mod: CustomModulePref) => `${mod.id}_${mod.enabled}`)

          // 3. 底部自定义发现模块入口胶囊
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
              .fontSize(16)
              .fontColor([mpPrimaryText(this.isDark)])
            Text('自定义发现模块')
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
          .bindSheet($$this.showModulesSheet, this.modulesSheetBuilder(), {
            detents: [SheetSize.MEDIUM, SheetSize.LARGE],
            blurStyle: BlurStyle.COMPONENT_REGULAR,
            dragBar: true,
        showClose: false,
            backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
          })
        }
        .padding({ bottom: 128 })
      }
      .scrollBar(BarState.Off)
      .onDidScroll(() => {
        const off = this.scroller.currentOffset();
        this.scrollOffsetY = off ? off.yOffset : 0;
      })
      .width('100%')
      .height('100%')

      NativeTopStatusBarBlur({ visibilityProgress: Math.min(1, Math.max(0, this.scrollOffsetY / 140)) })

      // 顶部栏：位于 Hero 上方时仅右侧悬浮光感搜索圆钮；滚过 Hero 后平滑切换为磨砂导航栏避免遮挡正文
      Row() {
        if (this.scrollOffsetY > 240) {
          Text('发现')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
        }
        Blank()
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(19)
            .fontColor([this.scrollOffsetY > 240 ? mpPrimaryText(this.isDark) : Color.White])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .attributeModifier(new HarmonySurfaceModifier(this.scrollOffsetY > 240 ? this.isDark : true, 'pill', 20, this.accentHex, true, this.dynamicLight))
        .accessibilityText('全局搜索')
        .onClick(() => this.onOpenSearch())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 44, bottom: 10 })
      .backgroundColor(this.scrollOffsetY > 240 ? HarmonyThemeColors.barFallback(this.isDark) : Color.Transparent)
      .backgroundBlurStyle(this.scrollOffsetY > 240 ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}

/**
 * 鸿蒙独立全屏媒体库浏览页（对齐 iOS + 顶部大胶囊媒体库分页 + 实时搜索/排序/类型筛选 + 3 列海报网格）。
 */
@Component
export struct HarmonyMediaServerLibraryPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop initialLibraryId: string = '';
  @Prop initialServerName: string = '';
  @State private libraries: MpMediaServerLibrary[] = [];
  @State private activeIdx: number = 0;
  @State private keyword: string = '';
  @State private activeSort: string = 'DateCreated';
  @State private activeGenre: string = '';
  @State private items: MpMediaItem[] = [];
  @State private loading: boolean = true;
  onBack: () => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};

  private readonly sortOptions: string[][] = [
    ['DateCreated', '最近入库'],
    ['PremiereDate', '发行日期'],
    ['CommunityRating', '评分最高'],
    ['SortName', '名称排序']
  ];

  private readonly genreOptions: string[] = ['', '动作', '科幻', '剧情', '喜剧', '犯罪', '悬疑', '动画'];

  aboutToAppear(): void {
    this.initLibraries();
  }

  private async initLibraries(): Promise<void> {
    this.loading = true;
    try {
      const libs = await MoviePilotRepository.shared().fetchMediaServerLibraries();
      this.libraries = libs;
      if (this.initialLibraryId.length > 0) {
        const found = libs.findIndex((l: MpMediaServerLibrary) => l.id === this.initialLibraryId);
        this.activeIdx = found >= 0 ? found : 0;
      }
      await this.loadActiveLibrary();
    } catch {
      this.loading = false;
    }
  }

  private async loadActiveLibrary(): Promise<void> {
    if (this.libraries.length === 0) {
      this.items = [];
      this.loading = false;
      return;
    }
    const lib = this.libraries[Math.min(this.activeIdx, this.libraries.length - 1)];
    this.loading = true;
    try {
      this.items = await MoviePilotRepository.shared().fetchMediaServerBrowseFiltered(
        lib.serverName,
        lib.id,
        this.keyword,
        this.activeSort,
        this.activeGenre,
        1
      );
    } catch {
      this.items = [];
    }
    this.loading = false;
  }

  private activeLib(): MpMediaServerLibrary | null {
    if (this.libraries.length === 0) { return null; }
    return this.libraries[Math.min(this.activeIdx, this.libraries.length - 1)];
  }

  private gridColumnsTemplate(): string {
    const cols = HarmonyAdaptiveLayout.posterGridColumns(this.windowWidthVp);
    const arr: string[] = [];
    for (let i = 0; i < cols; i++) { arr.push('1fr'); }
    return arr.join(' ');
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: this.activeLib()?.name ?? '媒体库',
        subtitle: this.activeLib()?.serverName ?? this.initialServerName,
        onBack: () => this.onBack()
      })

      if (this.libraries.length > 0) {
        HarmonyPillTabBar({
          tabs: this.libraries.map((l: MpMediaServerLibrary) => l.name),
          selectedIndex: this.activeIdx,
          scrollable: true,
          onSelect: (idx: number) => {
            this.activeIdx = idx;
            this.loadActiveLibrary();
          }
        })
      }

      // 搜索框
      Row({ space: 8 }) {
        CinematicPanel({ panelPadding: 6, cornerRadius: 18 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(17)
              .fontColor([mpSecondaryText(this.isDark)])
              .margin({ left: 8 })
            TextInput({ placeholder: `搜索「${this.activeLib()?.name ?? '媒体库'}」…`, text: this.keyword })
              .layoutWeight(1)
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.keyword = v; })
              .onSubmit(() => this.loadActiveLibrary())
          }
          .width('100%')
        }
      }
      .padding({ left: 16, right: 16 })

      // 排序胶囊行
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.sortOptions, (opt: string[]) => {
            NativeAdaptivePill({
              title: opt[1],
              selected: this.activeSort === opt[0],
              onTap: () => {
                this.activeSort = opt[0];
                this.loadActiveLibrary();
              }
            })
          }, (opt: string[]) => opt[0])
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      // 类型胶囊行
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.genreOptions, (g: string) => {
            NativeAdaptivePill({
              title: g.length === 0 ? '全部类型' : g,
              selected: this.activeGenre === g,
              onTap: () => {
                this.activeGenre = g;
                this.loadActiveLibrary();
              }
            })
          }, (g: string) => `g_${g}`)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      Text(`共 ${this.activeLib()?.itemCount ?? this.items.length} 项${this.activeLib()?.serverName ? ' · ' + this.activeLib()!.serverName : ''}`)
        .fontSize(12)
        .fontColor(mpSecondaryText(this.isDark))
        .width('100%')
        .padding({ left: 16, right: 16 })

      if (this.loading && this.items.length === 0) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.accentHex)
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
                showPlayBadge: true,
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
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙「探索」片库页（统一大胶囊自动滚动页签 + 多维筛选 + 音乐专辑视图）。 */
@Component
export struct HarmonyExplorePage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop @Watch('onInitialSourceChanged') initialSource: string = 'tmdb_movies';
  @State private activeSource: string = 'tmdb_movies';
  @State private activeSort: string = 'popularity.desc';
  @State private activeMusicFeed: string = 'douban';
  @State private items: MpMediaItem[] = [];
  @State private albums: MpMusicAlbum[] = [];
  @State private loading: boolean = false;
  onOpenMedia: (item: MpMediaItem) => void = () => {};
  onOpenSearch: () => void = () => {};

  aboutToAppear(): void {
    if (this.initialSource.length > 0) {
      this.activeSource = this.initialSource;
    }
    this.fetchCurrent();
  }

  onInitialSourceChanged(): void {
    if (this.initialSource.length > 0 && this.initialSource !== this.activeSource) {
      this.activeSource = this.initialSource;
      this.fetchCurrent();
    }
  }

  private activeSourceIndex(): number {
    const idx = EXPLORE_SOURCES.findIndex((s: ExploreSourceDef) => s.key === this.activeSource);
    return idx >= 0 ? idx : 0;
  }

  private async fetchCurrent(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      if (this.activeSource === 'music') {
        this.albums = await repo.fetchMusicFeed(this.activeMusicFeed, 1);
      } else {
        this.items = await repo.fetchExplore(this.activeSource, this.activeSort, 1);
      }
    } catch {
      this.items = [];
      this.albums = [];
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
        primarySymbol: 'sys.symbol.magnifyingglass',
        primaryAccessibility: '全局搜索',
        onPrimaryClick: () => this.onOpenSearch()
      })

      HarmonyPillTabBar({
        tabs: EXPLORE_SOURCES.map((s: ExploreSourceDef) => s.label),
        selectedIndex: this.activeSourceIndex(),
        scrollable: true,
        onSelect: (idx: number) => {
          this.activeSource = EXPLORE_SOURCES[idx].key;
          this.fetchCurrent();
        }
      })

      if (this.activeSource === 'music') {
        Scroll() {
          Row({ space: 8 }) {
            ForEach([['douban', '豆瓣音乐'], ['weekly', '本周榜单'], ['hot', '热门专辑'], ['new', '近期新发']], (f: string[]) => {
              NativeAdaptivePill({
                title: f[1],
                selected: this.activeMusicFeed === f[0],
                onTap: () => {
                  this.activeMusicFeed = f[0];
                  this.fetchCurrent();
                }
              })
            }, (f: string[]) => f[0])
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      } else if (this.activeSource.startsWith('tmdb')) {
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

      if (this.loading && (this.activeSource === 'music' ? this.albums.length === 0 : this.items.length === 0)) {
        Column({ space: 8 }) {
          LoadingProgress().width(32).height(32).color(this.accentHex)
          Text('正在加载片库…').fontSize(13).fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.activeSource === 'music') {
        Grid() {
          ForEach(this.albums, (al: MpMusicAlbum) => {
            GridItem() {
              Column({ space: 6 }) {
                if (al.coverUrl.length > 0) {
                  MpRemoteImage({
                    src: al.coverUrl,
                    imgWidth: '100%',
                    imgAspectRatio: 1,
                    imgRadius: 16,
                    placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                  })
                } else {
                  Stack() {
                    SymbolGlyph($r('sys.symbol.music')).fontSize(32).fontColor([this.accentHex])
                  }
                  .width('100%').aspectRatio(1).borderRadius(16).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                }
                Text(al.title)
                  .fontSize(13.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(`${al.artist || '音乐专辑'}${al.year ? ' · ' + al.year : ''}`)
                  .fontSize(11.5)
                  .fontColor(mpSecondaryText(this.isDark))
                  .maxLines(1)
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
            }
          }, (al: MpMusicAlbum) => al.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(16)
        .padding({ left: 16, right: 16, bottom: 128 })
        .layoutWeight(1)
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
        .padding({ left: 16, right: 16, bottom: 128 })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * 鸿蒙「全局搜索」页：
 * - 顶部统一大胶囊切换 5 大搜索域（媒体 / 媒体库 / 人物 / 音乐 / 合集）；
 * - 热门搜索建议关键词紧贴搜索框正下方顶对齐展示，点击即刻触发检索。
 */
@Component
export struct HarmonyGlobalSearchPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @State private query: string = '';
  @State private scopeIndex: number = 0;
  @State private results: MpMediaItem[] = [];
  @State private searching: boolean = false;
  @State private hasSearched: boolean = false;
  onBack: () => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};

  private async runSearch(overrideKeyword?: string): Promise<void> {
    const q = (overrideKeyword ?? this.query).trim();
    if (!q) { return; }
    this.query = q;
    this.searching = true;
    this.hasSearched = true;
    try {
      const kind = SEARCH_SCOPE_KEYS[Math.min(this.scopeIndex, SEARCH_SCOPE_KEYS.length - 1)];
      this.results = await MoviePilotRepository.shared().searchMedia(q, kind);
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
    Column({ space: 12 }) {
      NativeBackHeader({ title: '全局搜索', onBack: () => this.onBack() })

      HarmonyPillTabBar({
        tabs: SEARCH_SCOPES,
        selectedIndex: this.scopeIndex,
        scrollable: true,
        onSelect: (idx: number) => {
          this.scopeIndex = idx;
          if (this.query.trim().length > 0) {
            this.runSearch();
          }
        }
      })

      Row({ space: 8 }) {
        Column() {
          CinematicPanel({ panelPadding: 6, cornerRadius: 20 }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(18)
                .fontColor([mpSecondaryText(this.isDark)])
                .margin({ left: 8 })
              TextInput({ placeholder: '搜索电影、剧集、媒体库、人物或音乐…', text: this.query })
                .layoutWeight(1)
                .fontColor(mpPrimaryText(this.isDark))
                .placeholderColor(mpSecondaryText(this.isDark))
                .backgroundColor(Color.Transparent)
                .onChange((v: string) => {
                  this.query = v;
                  if (v.trim().length === 0) {
                    this.hasSearched = false;
                    this.results = [];
                  }
                })
                .onSubmit(() => this.runSearch())
            }
            .width('100%')
          }
        }
        .layoutWeight(1)

        Button('搜索')
          .height(44)
          .borderRadius(22)
          .backgroundColor(this.accentHex)
          .fontColor(Color.White)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .onClick(() => this.runSearch())
      }
      .padding({ left: 16, right: 16 })

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
      } else if (!this.hasSearched) {
        // 热门搜索直接位于搜索框正下方顶对齐
        Column({ space: 12 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.flame')).fontSize(16).fontColor([this.accentHex])
            Text('热门搜索')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 10, unit: 1 }, cross: { value: 10, unit: 1 } } }) {
            ForEach(HOT_SEARCH_KEYWORDS, (kw: string) => {
              NativeAdaptivePill({
                title: kw,
                selected: false,
                onTap: () => this.runSearch(kw)
              })
            }, (kw: string) => kw)
          }
          .width('100%')

          Text('切换上方分类胶囊可精准检索媒体库、演职员、音乐与合集')
            .fontSize(12)
            .fontColor(mpSecondaryText(this.isDark))
            .width('100%')
            .margin({ top: 6 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4 })
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(36).fontColor([mpSecondaryText(this.isDark)])
          Text(`未找到与「${this.query}」相关的内容`)
            .fontSize(14)
            .fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
