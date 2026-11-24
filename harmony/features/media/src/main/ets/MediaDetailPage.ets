import {
  MoviePilotRepository,
  MpMediaItem,
  MpCastMember,
  MpSeasonInfo,
  MpPersonDetail,
  MpRemoteImage
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeBackHeader,
  NativeTopStatusBarBlur,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonySurfaceModifier,
  HarmonyThemeColors,
  HarmonyEntityLogo,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import { HarmonyPlaybackRequest } from '@moviepilot/media_player';

/**
 * 鸿蒙沉浸式影视/剧集详情页：
 * - 主视觉标题与徽标列严格左对齐（`HorizontalAlign.Start`）并展示数据源品牌 Logo；
 * - 支持豆瓣 / Bangumi 条目（`GET /api/v1/media/{mediaId}`）完整加载简介、演职员与分季；
 * - 自动查询 `/api/v1/subscribe/media/{mediaid}` 订阅状态；
 * - 剧情简介支持 3 行折叠 + 「展开 / 收起」切换，「添加订阅 / 搜索资源」配备语义图标。
 */
@Component
export struct HarmonyMediaDetailPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop @Watch('onItemChanged') item: MpMediaItem = {
    id: '', mediaId: '', tmdbId: '', doubanId: '', title: '', enTitle: '', year: '', type: '电影',
    overview: '', vote: 0, posterUrl: '', backdropUrl: '', logoUrl: '', source: 'themoviedb',
    inLibrary: false, subtitle: '', percent: 0, serverName: '', playUrl: ''
  };
  @State private hydratedItem: MpMediaItem | null = null;
  @State private scrollOffsetY: number = 0;
  @State private subscribed: boolean = false;
  @State private overviewExpanded: boolean = false;
  @State private cast: MpCastMember[] = [];
  @State private seasons: MpSeasonInfo[] = [];
  @State private statusMsg: string = '';
  private scroller: Scroller = new Scroller();
  onBack: () => void = () => {};
  onSearchResource: (kw: string) => void = () => {};
  onOpenPerson: (person: MpCastMember) => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  aboutToAppear(): void {
    this.loadMeta();
  }

  onItemChanged(): void {
    this.hydratedItem = null;
    this.overviewExpanded = false;
    this.cast = [];
    this.seasons = [];
    this.statusMsg = '';
    this.loadMeta();
  }

  private activeMedia(): MpMediaItem {
    return this.hydratedItem ?? this.item;
  }

  private async loadMeta(): Promise<void> {
    const repo = MoviePilotRepository.shared();
    let workingItem: MpMediaItem = this.item;

    // 1. 当 tmdbId 为空（如豆瓣 / Bangumi 条目）或缺少简介时，调用 GET /api/v1/media/{mediaId} 补全详情与演职员
    if (!workingItem.tmdbId || workingItem.overview.trim().length === 0) {
      try {
        const bundle = await repo.fetchMediaDetailBundle(workingItem);
        if (bundle) {
          workingItem = bundle.item;
          this.hydratedItem = bundle.item;
          if (bundle.cast.length > 0) {
            this.cast = bundle.cast;
          }
          if (bundle.seasons.length > 0) {
            this.seasons = bundle.seasons;
          }
        }
      } catch {
        // keep base item
      }
    }

    // 2. 查询真实订阅状态 GET /api/v1/subscribe/media/{mediaid}
    try {
      this.subscribed = await repo.checkMediaSubscribed(workingItem);
    } catch {
      // ignore check error
    }

    // 3. 若有 tmdbId，补充演职员与分季详情
    if (workingItem.tmdbId.length > 0) {
      try {
        if (this.cast.length === 0) {
          this.cast = await repo.fetchMediaCredits(workingItem.tmdbId, workingItem.type);
        }
        if (this.seasons.length === 0 && (workingItem.type === '电视剧' || workingItem.type.toLowerCase() === 'tv')) {
          this.seasons = await repo.fetchMediaSeasons(workingItem.tmdbId);
        }
      } catch {
        // ignore
      }
    }
  }

  private async triggerSubscribe(): Promise<void> {
    const media = this.activeMedia();
    const ok = await MoviePilotRepository.shared().addSubscribe(media);
    if (ok) {
      this.subscribed = true;
    }
    this.statusMsg = ok ? '已添加至 MoviePilot 订阅队列' : (this.subscribed ? '当前已在订阅队列中' : '订阅请求未确认，请检查是否已存在');
  }

  private sourceDisplayLabel(src: string): string {
    const lower = (src ?? '').toLowerCase();
    if (lower.includes('douban')) { return '豆瓣'; }
    if (lower.includes('bangumi')) { return 'Bangumi'; }
    if (lower.includes('music')) { return 'MusicBrainz'; }
    return 'TMDB';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Column({ space: 18 }) {
          // 全幅主视觉
          Stack({ alignContent: Alignment.BottomStart }) {
            if (this.activeMedia().backdropUrl || this.activeMedia().posterUrl) {
              MpRemoteImage({
                src: this.activeMedia().backdropUrl || this.activeMedia().posterUrl,
                imgWidth: '100%',
                imgHeight: 380,
                placeholderColor: HarmonyThemeColors.card(this.isDark, this.paletteId)
              })
            } else {
              Column()
                .width('100%')
                .height(380)
                .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
            }

            Column()
              .width('100%')
              .height(380)
              .linearGradient({
                angle: 180,
                colors: this.isDark
                  ? [
                    ['#55000000', 0],
                    ['#10000000', 0.35],
                    [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(true, this.paletteId), 'D4'), 0.80],
                    [HarmonyThemeColors.canvas(true, this.paletteId), 1]
                  ]
                  : [
                    ['#40000000', 0],
                    ['#10000000', 0.35],
                    ['#C0141822', 0.78],
                    [HarmonyThemeColors.canvas(false, this.paletteId), 1]
                  ]
              })

            Column({ space: 8 }) {
              if (this.activeMedia().logoUrl.length > 0) {
                MpRemoteImage({
                  src: this.activeMedia().logoUrl,
                  imgWidth: 190,
                  imgHeight: 62,
                  fit: ImageFit.Contain,
                  placeholderColor: Color.Transparent
                })
              } else {
                Text(this.activeMedia().title)
                  .fontSize(26)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .textAlign(TextAlign.Start)
              }

              Row({ space: 8 }) {
                Row({ space: 4 }) {
                  HarmonyEntityLogo({
                    kind: 'media_source',
                    value: this.activeMedia().source || 'themoviedb',
                    logoSize: 14,
                    cornerRadius: 3
                  })
                  Text(this.sourceDisplayLabel(this.activeMedia().source))
                    .fontSize(11)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                }
                .padding({ left: 7, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .backgroundColor('#55000000')

                NativeAdaptiveBadge({ text: this.activeMedia().type || '影视', tintHex: this.accentHex, filled: true })
                if (this.activeMedia().year.length > 0) {
                  NativeAdaptiveBadge({ text: this.activeMedia().year })
                }
                if (this.activeMedia().vote > 0) {
                  NativeAdaptiveBadge({ text: `★ ${this.activeMedia().vote.toFixed(1)}`, tintHex: '#FFC845' })
                }
                if (this.activeMedia().inLibrary) {
                  NativeAdaptiveBadge({ text: '已入库', tintHex: '#52C41A', filled: true })
                }
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(20)
          }

          // 操作按钮（带清晰语义图标）
          Column({ space: 10 }) {
            if (this.activeMedia().inLibrary || this.activeMedia().playUrl.length > 0) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([Color.White])
                  Text('立即播放').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Color.White)
                }
              }
              .width('100%')
              .height(48)
              .borderRadius(24)
              .backgroundColor(this.accentHex)
              .onClick(async () => {
                const cur = this.activeMedia();
                try {
                  const manifest = await MoviePilotRepository.shared().fetchVideoStreamInfo(cur.id, cur.serverName);
                  if (manifest && manifest.contentUrl.length > 0) {
                    this.onPlayMedia({
                      url: manifest.contentUrl,
                      title: manifest.title || cur.title,
                      subtitle: cur.subtitle || cur.year,
                      isAudio: manifest.mediaType === 'audio'
                    });
                    return;
                  }
                } catch {
                  // fallback to item.playUrl
                }
                if (cur.playUrl.length > 0) {
                  this.onPlayMedia({
                    url: cur.playUrl,
                    title: cur.title,
                    subtitle: cur.year,
                    isAudio: false
                  });
                } else {
                  this.statusMsg = '暂未获取到媒体服务器直连播放地址';
                }
              })
            }

            Row({ space: 10 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r(this.subscribed ? 'sys.symbol.checkmark' : 'sys.symbol.bookmark_fill'))
                    .fontSize(16)
                    .fontColor([this.subscribed || !this.activeMedia().inLibrary ? Color.White : mpPrimaryText(this.isDark)])
                  Text(this.subscribed ? '已订阅' : '添加订阅')
                    .fontSize(14.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.subscribed || !this.activeMedia().inLibrary ? Color.White : mpPrimaryText(this.isDark))
                }
              }
              .layoutWeight(1)
              .height(46)
              .borderRadius(23)
              .backgroundColor(this.subscribed ? '#34C759' : (this.activeMedia().inLibrary ? HarmonyThemeColors.chipFill(this.isDark) : this.accentHex))
              .onClick(() => this.triggerSubscribe())

              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.magnifyingglass'))
                    .fontSize(16)
                    .fontColor([mpPrimaryText(this.isDark)])
                  Text('搜索资源')
                    .fontSize(14.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(mpPrimaryText(this.isDark))
                }
              }
              .layoutWeight(1)
              .height(46)
              .borderRadius(23)
              .backgroundColor(Color.Transparent)
              .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 23, this.accentHex, true, this.dynamicLight))
              .onClick(() => this.onSearchResource(this.activeMedia().title))
            }
          }
          .padding({ left: 16, right: 16 })

          if (this.statusMsg.length > 0) {
            Text(this.statusMsg).fontSize(12).fontColor('#52C41A').padding({ left: 16, right: 16 }).width('100%')
          }

          // 可折叠剧情简介（默认 3 行 + 展开/收起）
          Column() {
            CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
              Column({ space: 8 }) {
                Row() {
                  Text('剧情简介')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                    .layoutWeight(1)
                  if ((this.activeMedia().overview || '').length > 68) {
                    Text(this.overviewExpanded ? '收起 ▴' : '展开 ▾')
                      .fontSize(12.5)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.accentHex)
                      .onClick(() => { this.overviewExpanded = !this.overviewExpanded; })
                  }
                }
                .width('100%')

                Text(this.activeMedia().overview || '暂无剧情简介，可添加自动追剧订阅或检索 4K 高清片源。')
                  .fontSize(14)
                  .fontColor(mpSecondaryText(this.isDark))
                  .lineHeight(22)
                  .maxLines(this.overviewExpanded ? 99 : 3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .onClick(() => {
                    if ((this.activeMedia().overview || '').length > 68) {
                      this.overviewExpanded = !this.overviewExpanded;
                    }
                  })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 剧集分季
          if (this.seasons.length > 0) {
            Column({ space: 10 }) {
              Text(`分季 (${this.seasons.length})`)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(mpPrimaryText(this.isDark))
                .width('100%')
                .padding({ left: 16, right: 16 })

              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.seasons, (s: MpSeasonInfo) => {
                    Column({ space: 6 }) {
                      MpRemoteImage({
                        src: s.posterUrl || this.activeMedia().posterUrl,
                        imgWidth: 108,
                        imgHeight: 156,
                        imgRadius: 12,
                        placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                      })
                      Text(s.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark)).maxLines(1).width(108)
                      Text(`共 ${s.episodeCount} 集`).fontSize(11).fontColor(mpSecondaryText(this.isDark)).width(108)
                    }
                    .alignItems(HorizontalAlign.Start)
                  }, (s: MpSeasonInfo) => String(s.seasonNumber))
                }
                .padding({ left: 16, right: 16 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
          }

          // 演职员表（点击演职员可下钻查看个人主页与作品集）
          if (this.cast.length > 0) {
            Column({ space: 10 }) {
              Text('演职员')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(mpPrimaryText(this.isDark))
                .width('100%')
                .padding({ left: 16, right: 16 })

              Scroll() {
                Row({ space: 14 }) {
                  ForEach(this.cast, (c: MpCastMember) => {
                    Column({ space: 5 }) {
                      if (c.profileUrl.length > 0) {
                        MpRemoteImage({
                          src: c.profileUrl,
                          imgWidth: 66,
                          imgHeight: 66,
                          imgRadius: 33,
                          placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                        })
                      } else {
                        Text((c.name || '演').substring(0, 1))
                          .width(66)
                          .height(66)
                          .borderRadius(33)
                          .textAlign(TextAlign.Center)
                          .fontColor(Color.White)
                          .backgroundColor(this.accentHex)
                      }
                      Text(c.name)
                        .fontSize(12)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(mpPrimaryText(this.isDark))
                        .maxLines(1)
                        .width(74)
                        .textAlign(TextAlign.Center)
                      if (c.character.length > 0) {
                        Text(c.character)
                          .fontSize(10)
                          .fontColor(mpSecondaryText(this.isDark))
                          .maxLines(1)
                          .width(74)
                          .textAlign(TextAlign.Center)
                      }
                    }
                    .alignItems(HorizontalAlign.Center)
                    .hoverEffect(HoverEffect.Highlight)
                    .onClick(() => {
                      if (c.id.length > 0 && !c.id.startsWith('actor_')) {
                        this.onOpenPerson(c);
                      }
                    })
                  }, (c: MpCastMember) => `${c.id}_${c.name}`)
                }
                .padding({ left: 16, right: 16 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
          }
        }
        .padding({ bottom: 48 })
      }
      .scrollBar(BarState.Off)
      .onDidScroll(() => {
        const off = this.scroller.currentOffset();
        this.scrollOffsetY = off ? off.yOffset : 0;
      })
      .width('100%')
      .height('100%')

      NativeTopStatusBarBlur({ visibilityProgress: Math.min(1, Math.max(0, this.scrollOffsetY / 150)) })

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .attributeModifier(new HarmonySurfaceModifier(true, 'pill', 20, this.accentHex, true, this.dynamicLight))
      .accessibilityText('返回上一级')
      .position({ left: 16, top: 44 })
      .onClick(() => this.onBack())
    }
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙演职员人物详情页（消费 `/api/v1/tmdb/person/{id}` 与 `/api/v1/tmdb/person/credits/{id}`）。 */
@Component
export struct HarmonyPersonDetailPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop @Watch('onPersonChanged') person: MpCastMember = { id: '', name: '', character: '', profileUrl: '' };
  @State private detail: MpPersonDetail | null = null;
  @State private credits: MpMediaItem[] = [];
  @State private loading: boolean = true;
  onBack: () => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};

  aboutToAppear(): void {
    this.loadPerson();
  }

  onPersonChanged(): void {
    this.loadPerson();
  }

  private async loadPerson(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchPersonDetail(this.person.id),
        repo.fetchPersonCredits(this.person.id)
      ]);
      this.detail = res[0];
      this.credits = res[1];
    } catch {
      // keep fallback person info
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
      NativeBackHeader({
        title: this.detail ? this.detail.name : (this.person.name || '演职员详情'),
        onBack: () => this.onBack()
      })

      Scroll() {
        Column({ space: 16 }) {
          CinematicPanel({ panelPadding: 16, cornerRadius: 20 }) {
            Row({ space: 14 }) {
              if ((this.detail && this.detail.profileUrl.length > 0) || this.person.profileUrl.length > 0) {
                MpRemoteImage({
                  src: this.detail && this.detail.profileUrl.length > 0 ? this.detail.profileUrl : this.person.profileUrl,
                  imgWidth: 76,
                  imgHeight: 76,
                  imgRadius: 38,
                  placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                })
              } else {
                Text((this.person.name || '演').substring(0, 1))
                  .width(76).height(76).borderRadius(38).textAlign(TextAlign.Center)
                  .fontColor(Color.White).fontSize(26).fontWeight(FontWeight.Bold).backgroundColor(this.accentHex)
              }
              Column({ space: 5 }) {
                Text(this.detail ? this.detail.name : this.person.name)
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                if (this.detail && this.detail.department.length > 0) {
                  NativeAdaptiveBadge({ text: this.detail.department, tintHex: this.accentHex })
                }
                if (this.detail && (this.detail.birthday.length > 0 || this.detail.placeOfBirth.length > 0)) {
                  Text(`${this.detail.birthday}${this.detail.placeOfBirth ? ' · ' + this.detail.placeOfBirth : ''}`)
                    .fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(2)
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')
          }

          if (this.detail && this.detail.biography.length > 0) {
            CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
              Column({ space: 6 }) {
                Text('人物简介').fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                Text(this.detail.biography)
                  .fontSize(13)
                  .fontColor(mpSecondaryText(this.isDark))
                  .lineHeight(21)
              }.alignItems(HorizontalAlign.Start).width('100%')
            }
          }

          Text(`参演作品 (${this.credits.length})`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .width('100%')

          if (this.loading && this.credits.length === 0) {
            LoadingProgress().width(32).height(32).color(this.accentHex).margin({ top: 20 })
          } else {
            Grid() {
              ForEach(this.credits, (it: MpMediaItem) => {
                GridItem() {
                  Column({ space: 5 }) {
                    if (it.posterUrl.length > 0) {
                      MpRemoteImage({
                        src: it.posterUrl,
                        imgWidth: '100%',
                        imgAspectRatio: 0.67,
                        imgRadius: 12,
                        placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                      })
                    } else {
                      Column()
                        .width('100%')
                        .aspectRatio(0.67)
                        .borderRadius(12)
                        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    }
                    Text(it.title)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => this.onOpenMedia(it))
                }
              }, (it: MpMediaItem) => it.id)
            }
            .columnsTemplate(this.gridColumnsTemplate())
            .columnsGap(10)
            .rowsGap(14)
            .width('100%')
          }
        }
        .padding({ left: 16, right: 16, bottom: 40 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
