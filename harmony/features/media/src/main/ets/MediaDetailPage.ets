import {
  MoviePilotRepository,
  MpMediaItem,
  MpCastMember,
  MpSeasonInfo,
  MpPersonDetail
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
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import { HarmonyPlaybackRequest } from '@moviepilot/media_player';

/**
 * 鸿蒙沉浸式影视/剧集详情页（真实海报主视觉 + 动态光感悬浮返回 + 分季信息 + 演职员下钻人物页 + 真实订阅提交）。
 */
@Component
export struct HarmonyMediaDetailPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @Prop item: MpMediaItem = {
    id: '', mediaId: '', tmdbId: '', doubanId: '', title: '', enTitle: '', year: '', type: '电影',
    overview: '', vote: 0, posterUrl: '', backdropUrl: '', logoUrl: '', source: 'themoviedb',
    inLibrary: false, subtitle: '', percent: 0, serverName: '', playUrl: ''
  };
  @State private scrollOffsetY: number = 0;
  @State private subscribed: boolean = false;
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

  private async loadMeta(): Promise<void> {
    if (!this.item.tmdbId) { return; }
    const repo = MoviePilotRepository.shared();
    try {
      this.cast = await repo.fetchMediaCredits(this.item.tmdbId, this.item.type);
      if (this.item.type === '电视剧' || this.item.type.toLowerCase() === 'tv') {
        this.seasons = await repo.fetchMediaSeasons(this.item.tmdbId);
      }
    } catch {
      // ignore
    }
  }

  private async triggerSubscribe(): Promise<void> {
    const ok = await MoviePilotRepository.shared().addSubscribe(this.item);
    this.subscribed = ok;
    this.statusMsg = ok ? '已添加至 MoviePilot 订阅队列' : '订阅请求未确认，请检查是否已存在';
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Column({ space: 18 }) {
          // 全幅主视觉
          Stack({ alignContent: Alignment.BottomStart }) {
            if (this.item.backdropUrl || this.item.posterUrl) {
              Image(this.item.backdropUrl || this.item.posterUrl)
                .width('100%')
                .height(380)
                .objectFit(ImageFit.Cover)
            } else {
              Column()
                .width('100%')
                .height(380)
                .backgroundColor(HarmonyThemeColors.card(this.isDark))
            }

            Column()
              .width('100%')
              .height(380)
              .linearGradient({
                angle: 180,
                colors: this.isDark
                  ? [['#55000000', 0], ['#10000000', 0.35], ['#CC0D0D11', 0.8], ['#FF0D0D11', 1]]
                  : [['#40000000', 0], ['#10000000', 0.35], ['#B80D0D11', 0.78], ['#FFF1F3F5', 1]]
              })

            Column({ space: 8 }) {
              Text(this.item.title)
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Row({ space: 8 }) {
                NativeAdaptiveBadge({ text: this.item.type || '影视', tintHex: this.accentHex, filled: true })
                if (this.item.year.length > 0) {
                  NativeAdaptiveBadge({ text: this.item.year })
                }
                if (this.item.vote > 0) {
                  NativeAdaptiveBadge({ text: `★ ${this.item.vote.toFixed(1)}`, tintHex: '#FFC845' })
                }
                if (this.item.inLibrary) {
                  NativeAdaptiveBadge({ text: '已入库', tintHex: '#52C41A', filled: true })
                }
              }
            }
            .padding(20)
          }

          // 操作按钮（主操作品牌强调色 + 动态光感次操作）
          Row({ space: 10 }) {
            Button(this.subscribed ? '已订阅 ✓' : '添加订阅')
              .layoutWeight(1)
              .height(48)
              .borderRadius(24)
              .backgroundColor(this.subscribed ? '#52C41A' : this.accentHex)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
              .onClick(() => this.triggerSubscribe())
            Button('搜索资源')
              .layoutWeight(1)
              .height(48)
              .borderRadius(24)
              .backgroundColor(Color.Transparent)
              .fontColor(mpPrimaryText(this.isDark))
              .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 24, this.accentHex, true, this.dynamicLight))
              .onClick(() => this.onSearchResource(this.item.title))
          }
          .padding({ left: 16, right: 16 })

          if (this.statusMsg.length > 0) {
            Text(this.statusMsg).fontSize(12).fontColor('#52C41A').padding({ left: 16, right: 16 }).width('100%')
          }

          // 简介
          Column() {
            CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
              Column({ space: 8 }) {
                Text('剧情简介').fontSize(16).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                Text(this.item.overview || '暂无剧情简介，可添加自动追剧订阅或检索 4K 高清片源。')
                  .fontSize(14)
                  .fontColor(mpSecondaryText(this.isDark))
                  .lineHeight(22)
              }
              .alignItems(HorizontalAlign.Start)
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
                      Image(s.posterUrl || this.item.posterUrl)
                        .width(108)
                        .height(156)
                        .borderRadius(12)
                        .objectFit(ImageFit.Cover)
                        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
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
                        Image(c.profileUrl)
                          .width(66)
                          .height(66)
                          .borderRadius(33)
                          .objectFit(ImageFit.Cover)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      } else {
                        Text(c.name.substring(0, 1))
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
                    .onClick(() => this.onOpenPerson(c))
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

      NativeTopStatusBarBlur({ visibilityProgress: Math.min(1, Math.max(0, this.scrollOffsetY / 140)) })

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
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop person: MpCastMember = { id: '', name: '', character: '', profileUrl: '' };
  @State private detail: MpPersonDetail | null = null;
  @State private credits: MpMediaItem[] = [];
  @State private loading: boolean = true;
  onBack: () => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};

  aboutToAppear(): void {
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
                Image(this.detail && this.detail.profileUrl.length > 0 ? this.detail.profileUrl : this.person.profileUrl)
                  .width(76)
                  .height(76)
                  .borderRadius(38)
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
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
