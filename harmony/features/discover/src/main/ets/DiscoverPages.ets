import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { HarmonyAppearanceStore } from '../../../../commons/design_system/src/main/ets/store/AppearanceStore';
import { HarmonyPlaybackRequest } from '../../../../commons/media_player/src/main/ets/NativeMediaPlayerView';

export interface HarmonyMediaItem {
  id: string;
  title: string;
  year: string;
  type: string;
  overview: string;
  vote: number;
  source: string;
  inLibrary: boolean;
}

/**
 * 鸿蒙发现首页（全幅沉浸主视觉 + 继续观看 16:9 横幅 + 热门影视横栏 + 原生 `bindSheet` 模块编排弹窗）。
 */
@Component
export struct HarmonyDiscoverPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private showModulesSheet: boolean = false;
  @State private showContinue: boolean = true;
  @State private showMovies: boolean = true;
  @State private showTvs: boolean = true;
  onOpenMedia: (item: HarmonyMediaItem) => void = () => {};
  onOpenExplore: (src: string) => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  private readonly items: HarmonyMediaItem[] = [
    { id: '101', title: '奥德赛 THE ODYSSEY', year: '2026', type: '电影', overview: '穿越爱琴海与神话群岛的宏伟冒险史诗。', vote: 8.4, source: 'themoviedb', inLibrary: true },
    { id: '102', title: '流浪地球 3', year: '2026', type: '电影', overview: '太阳危机步步紧逼，人类带着地球踏上星际远征。', vote: 8.7, source: 'themoviedb', inLibrary: false },
    { id: '103', title: '沙丘：救世主', year: '2026', type: '电影', overview: '厄拉科斯金色道路与帝国命运的终极转折。', vote: 8.6, source: 'themoviedb', inLibrary: true },
    { id: '111', title: '合成追剧 S01', year: '2025', type: '电视剧', overview: '高口碑科幻悬疑剧集。', vote: 8.8, source: 'themoviedb', inLibrary: true },
  ];

  @Builder
  modulesSheetBuilder() {
    Column({ space: 12 }) {
      Text('发现模块编排').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
      CinematicPanel({ panelPadding: 14 }) {
        Row() {
          Text('继续观看').fontSize(15).fontColor(Color.White).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showContinue }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showContinue = v; })
        }.width('100%')
      }
      CinematicPanel({ panelPadding: 14 }) {
        Row() {
          Text('热门电影').fontSize(15).fontColor(Color.White).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showMovies }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showMovies = v; })
        }.width('100%')
      }
      CinematicPanel({ panelPadding: 14 }) {
        Row() {
          Text('热门剧集').fontSize(15).fontColor(Color.White).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showTvs }).selectedColor(this.accentHex)
            .onChange((v: boolean) => { this.showTvs = v; })
        }.width('100%')
      }
    }
    .padding(20)
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        // 沉浸主视觉轮播
        Stack({ alignContent: Alignment.Bottom }) {
          Swiper() {
            ForEach(this.items.slice(0, 3), (hero: HarmonyMediaItem) => {
              Stack({ alignContent: Alignment.Bottom }) {
                Column()
                  .width('100%')
                  .height(380)
                  .linearGradient({ angle: 165, colors: [['#4C3A6B', 0], ['#332645', 0.65], ['#30334A', 1]] })
                Column({ space: 8 }) {
                  Text(hero.title).fontSize(25).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text(`${hero.type} · ${hero.year}`).fontSize(13).fontColor('#D9FFFFFF')
                  Text(hero.overview).fontSize(12).fontColor('#B8FFFFFF').maxLines(2).textAlign(TextAlign.Center)
                  Row({ space: 8 }) {
                    NativeAdaptiveBadge({ text: 'TheMovieDB', tintHex: '#42C997', filled: true })
                    Text(`★ ${hero.vote.toFixed(1)}  查看详情`).fontSize(13).fontColor(Color.White)
                  }
                }
                .padding({ left: 20, right: 20, bottom: 26 })
              }
              .onClick(() => this.onOpenMedia(hero))
            })
          }
          .height(380)
          .width('100%')
          .autoPlay(true)

          Button('编排')
            .fontSize(12)
            .backgroundColor('#44FFFFFF')
            .fontColor(Color.White)
            .position({ right: 16, top: 44 })
            .onClick(() => { this.showModulesSheet = true; })
        }
        // 使用鸿蒙系统原生 bindSheet（严禁 Stack 伪造弹窗）
        .bindSheet($$this.showModulesSheet, this.modulesSheetBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE],
          blurStyle: BlurStyle.COMPONENT_THIN,
          dragBar: true,
          backgroundColor: '#CC2F2640'
        })

        // 继续观看
        if (this.showContinue) {
          Column({ space: 10 }) {
            Text('继续观看').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
            Scroll() {
              Row({ space: 12 }) {
                ForEach(['假面骑士 Build · 看到 43%', '三体：黑暗森林 · 看到 68%'], (entry: string) => {
                  CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
                    Column({ space: 8 }) {
                      Text(entry).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White)
                      Progress({ value: entry.includes('43') ? 43 : 68, total: 100, type: ProgressType.Linear })
                        .color(Color.White)
                        .backgroundColor('#33FFFFFF')
                    }
                  }
                  .width(226)
                  .onClick(() => this.onPlayMedia({
                    url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                    title: entry,
                    subtitle: 'Emby · 继续观看',
                    isAudio: false
                  }))
                })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
          }
          .padding({ left: 20, right: 20 })
        }

        // 热门电影横向栏
        if (this.showMovies) {
          Column({ space: 10 }) {
            Row() {
              Text('热门电影').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White).layoutWeight(1)
              Text('更多 ›').fontSize(13).fontColor('#B8FFFFFF').onClick(() => this.onOpenExplore('tmdb_movies'))
            }.width('100%')
            Scroll() {
              Row({ space: 12 }) {
                ForEach(this.items, (it: HarmonyMediaItem) => {
                  CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
                    Column({ space: 6 }) {
                      NativeAdaptiveBadge({ text: it.inLibrary ? '已入库' : `★ ${it.vote.toFixed(1)}`, tintHex: it.inLibrary ? '#34D058' : '#FFC845' })
                      Text(it.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White).maxLines(2)
                      Text(it.year).fontSize(11).fontColor('#88FFFFFF')
                    }.alignItems(HorizontalAlign.Start)
                  }
                  .width(126)
                  .height(166)
                  .onClick(() => this.onOpenMedia(it))
                })
              }
            }
            .scrollable(ScrollDirection.Horizontal)
          }
          .padding({ left: 20, right: 20 })
        }
      }
      .padding({ bottom: 124 })
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙探索片库页：带来源 Logo 的横向小卡片 + 3 行胶囊筛选 + 响应式多列海报网格。 */
@Component
export struct HarmonyExplorePage {
  @State private activeSource: string = 'tmdb_movies';
  @State private activeSort: string = '热门';
  @State private activeGenre: string = '全部类型';
  onOpenMedia: (item: HarmonyMediaItem) => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('探索').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White).margin({ top: 48 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(['TheMovieDB 电影', 'TheMovieDB 剧集', '豆瓣 电影', '豆瓣 剧集', 'Bangumi'], (src: string) => {
            NativeAdaptivePill({
              title: src,
              selected: this.activeSource === src || (this.activeSource === 'tmdb_movies' && src === 'TheMovieDB 电影'),
              onTap: () => { this.activeSource = src; }
            })
          })
        }
        .padding({ left: 20, right: 20 })
      }.scrollable(ScrollDirection.Horizontal)

      Row({ space: 8 }) {
        ForEach(['热门', '最新', '高分'], (s: string) => {
          NativeAdaptivePill({ title: s, selected: this.activeSort === s, onTap: () => { this.activeSort = s; } })
        })
      }.width('100%').padding({ left: 20 })

      Row({ space: 8 }) {
        ForEach(['全部类型', '动作', '科幻', '动画', '剧情'], (g: string) => {
          NativeAdaptivePill({ title: g, selected: this.activeGenre === g, onTap: () => { this.activeGenre = g; } })
        })
      }.width('100%').padding({ left: 20 })

      Grid() {
        ForEach(['钢铁侠', '奥德赛', '野兽之心', '沙丘：救世主', '流浪地球 3', '人生切割术'], (name: string, i: number) => {
          GridItem() {
            CinematicPanel({ panelPadding: 12, cornerRadius: 15 }) {
              Column({ space: 6 }) {
                NativeAdaptiveBadge({ text: i % 2 === 0 ? '8.6' : '已入库', tintHex: i % 2 === 0 ? '#9E7AF5' : '#34D058' })
                Blank()
                Text(name).fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White).maxLines(1)
                Text('2026').fontSize(11).fontColor('#88FFFFFF')
              }
              .height(140)
              .alignItems(HorizontalAlign.Start)
            }
            .onClick(() => this.onOpenMedia({
              id: String(200 + i), title: name, year: '2026', type: '电影',
              overview: '热门精选影片', vote: 8.6, source: 'themoviedb', inLibrary: i % 2 === 1
            }))
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(12)
      .padding({ left: 20, right: 20, bottom: 118 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙全局搜索页（仅媒体库直放，其余进详情页）。 */
@Component
export struct HarmonyGlobalSearchPage {
  @State private query: string = '';
  @State private kind: string = '媒体';
  onBack: () => void = () => {};
  onOpenMedia: (item: HarmonyMediaItem) => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('全局搜索').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text('   ')
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      CinematicPanel({ panelPadding: 10, cornerRadius: 20 }) {
        TextInput({ placeholder: '搜索电影、剧集、媒体库、人物或音乐...', text: this.query })
          .fontColor(Color.White).placeholderColor('#88FFFFFF').backgroundColor(Color.Transparent)
          .onChange((v: string) => { this.query = v; })
      }.padding({ left: 20, right: 20 })

      Row({ space: 8 }) {
        ForEach(['媒体', '媒体库', '人物', '音乐', '合集'], (k: string) => {
          NativeAdaptivePill({ title: k, selected: this.kind === k, onTap: () => { this.kind = k; } })
        })
      }.width('100%').padding({ left: 20 })
    }
    .width('100%')
    .height('100%')
  }
}
