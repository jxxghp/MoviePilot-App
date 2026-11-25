import {
  MoviePilotRepository,
  MpMusicAlbum,
  MpMusicTrackItem,
  MpMusicAlbumDetail,
  MpMusicArtistDetail,
  MpMediaItem,
  MpMediaServerEpisode,
  MpRemoteImage
} from '@moviepilot/core_rust_bridge';
import {
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  NativeAdaptivePill,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import {
  HarmonyPlaybackRequest,
  HarmonyQueueItem,
  formatMediaDurationMs,
  buildPlaybackRequestFromStreamInfo
} from '@moviepilot/media_player';

function formatTrackDurationSec(sec: number): string {
  if (!Number.isFinite(sec) || sec <= 0) {
    return '';
  }
  return formatMediaDurationMs(Math.round(sec * 1000));
}

/**
 * 音乐专辑详情与歌手详情一体化半模态宿主（`bindSheet`）：
 * - 展示专辑封面、发行年份、曲目列表、「播放全部」与「订阅专辑 / 取消订阅」；
 * - 点击歌手胶囊可无缝深入「歌手详情」查看生平简介与代表专辑，点击任一专辑再次切回专辑曲目单；
 * - 点击「播放全部」或任一单曲时自动解析 `/stream-info/music` 并构建整张专辑连播队列。
 */
@Component
export struct MusicAlbumArtistSheetHost {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Link visible: boolean;
  @Prop @Watch('onSeedChanged') seedAlbum: MpMusicAlbum | null = null;
  @Prop @Watch('onTriggerChanged') openTrigger: number = 0;

  @State private mode: 'album' | 'artist' = 'album';
  @State private loadingAlbum: boolean = false;
  @State private loadingArtist: boolean = false;
  @State private albumDetail: MpMusicAlbumDetail | null = null;
  @State private artistDetail: MpMusicArtistDetail | null = null;
  @State private isSubscribed: boolean = false;
  @State private mutatingSubscribe: boolean = false;
  @State private resolvingTrackIdx: number = -1;
  @State private statusTip: string = '';

  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  aboutToAppear(): void {
    if (this.visible && this.seedAlbum) {
      this.loadAlbumFromSeed(this.seedAlbum);
    }
  }

  onSeedChanged(): void {
    if (this.visible && this.seedAlbum) {
      this.loadAlbumFromSeed(this.seedAlbum);
    }
  }

  onTriggerChanged(): void {
    if (this.visible && this.seedAlbum) {
      this.loadAlbumFromSeed(this.seedAlbum);
    }
  }

  private async loadAlbumFromSeed(seed: MpMusicAlbum): Promise<void> {
    this.mode = 'album';
    this.statusTip = '';
    this.resolvingTrackIdx = -1;
    this.loadingAlbum = true;
    const repo = MoviePilotRepository.shared();
    const albumId = (seed.albumId || seed.releaseId || seed.mediaId || seed.id).trim();
    const mediaSource = (seed.mediaSource || 'musicbrainz').trim();
    try {
      const detail = await repo.fetchMusicAlbumDetail(albumId, mediaSource);
      if (detail) {
        if (!detail.coverUrl && seed.coverUrl) {
          detail.coverUrl = seed.coverUrl;
        }
        if (!detail.artist && seed.artist) {
          detail.artist = seed.artist;
        }
        this.albumDetail = detail;
      } else {
        this.albumDetail = {
          id: albumId,
          mediaId: seed.mediaId || albumId,
          releaseId: seed.releaseId || '',
          title: seed.title,
          artist: seed.artist,
          artistId: seed.artistId || '',
          albumType: 'Album',
          releaseDate: seed.year,
          year: seed.year,
          overview: '',
          coverUrl: seed.coverUrl,
          mediaSource: mediaSource,
          totalTracks: 0,
          tracks: []
        };
      }
      this.isSubscribed = await repo.checkMusicAlbumSubscribed(
        this.albumDetail.mediaId || this.albumDetail.id,
        this.albumDetail.mediaSource || mediaSource
      );
    } catch {
      this.statusTip = '专辑详情加载失败，请稍后重试';
    }
    this.loadingAlbum = false;
  }

  private async openArtistView(artistId: string, artistName: string, mediaSource: string): Promise<void> {
    const cleanId = artistId.trim();
    if (!cleanId) {
      this.statusTip = '当前专辑未关联歌手标识';
      return;
    }
    this.mode = 'artist';
    this.loadingArtist = true;
    this.statusTip = '';
    try {
      const detail = await MoviePilotRepository.shared().fetchMusicArtistDetail(cleanId, mediaSource || 'musicbrainz');
      if (detail) {
        this.artistDetail = detail;
      } else {
        this.artistDetail = {
          id: cleanId,
          name: artistName,
          country: '',
          lifeSpan: '',
          overview: '',
          imageUrl: '',
          mediaSource: mediaSource || 'musicbrainz',
          albums: []
        };
      }
    } catch {
      this.statusTip = '歌手详情加载失败';
    }
    this.loadingArtist = false;
  }

  private async handleToggleSubscribe(): Promise<void> {
    const detail = this.albumDetail;
    if (!detail || this.mutatingSubscribe) {
      return;
    }
    this.mutatingSubscribe = true;
    this.statusTip = '';
    const repo = MoviePilotRepository.shared();
    const targetId = detail.mediaId || detail.id;
    const src = detail.mediaSource || 'musicbrainz';
    try {
      if (this.isSubscribed) {
        const ok = await repo.unsubscribeMusicAlbum(targetId, src);
        if (ok) {
          this.isSubscribed = false;
          this.statusTip = '已取消专辑订阅';
        } else {
          this.statusTip = '取消订阅失败';
        }
      } else {
        const ok = await repo.subscribeMusicAlbum(detail);
        if (ok) {
          this.isSubscribed = true;
          this.statusTip = '已添加音乐专辑订阅';
        } else {
          this.statusTip = '订阅专辑失败';
        }
      }
    } catch {
      this.statusTip = '订阅操作异常';
    }
    this.mutatingSubscribe = false;
  }

  private buildAlbumQueue(detail: MpMusicAlbumDetail): HarmonyQueueItem[] {
    const queue: HarmonyQueueItem[] = [];
    for (let i = 0; i < detail.tracks.length; i++) {
      const tr = detail.tracks[i];
      const artist = tr.artist.length > 0 ? tr.artist : detail.artist;
      queue.push({
        itemId: '',
        title: tr.title,
        subtitle: artist.length > 0 ? `${artist} · ${detail.title}` : detail.title,
        artworkUrl: tr.coverUrl.length > 0 ? tr.coverUrl : detail.coverUrl,
        artist: artist,
        album: detail.title,
        mediaSource: tr.mediaSource || detail.mediaSource,
        mediaId: tr.mediaId || tr.id,
        trackNumber: tr.trackNumber > 0 ? tr.trackNumber : (i + 1),
        durationMs: tr.durationSec > 0 ? Math.round(tr.durationSec * 1000) : 0
      });
    }
    return queue;
  }

  private async playAlbumTrackAt(index: number): Promise<void> {
    const detail = this.albumDetail;
    if (!detail || this.resolvingTrackIdx !== -1) {
      return;
    }
    if (detail.tracks.length === 0) {
      // 无曲目明细时按整张专辑名称尝试匹配本地曲库
      this.resolvingTrackIdx = 0;
      this.statusTip = '';
      const stream = await MoviePilotRepository.shared().fetchMusicStreamInfo(
        detail.title,
        detail.artist,
        detail.title,
        detail.mediaSource,
        detail.mediaId || detail.id,
        1
      );
      this.resolvingTrackIdx = -1;
      if (!stream || stream.contentUrl.length === 0) {
        this.statusTip = '本地媒体库暂未找到该专辑音频文件，可先点击订阅';
        return;
      }
      this.visible = false;
      this.onPlayMedia(buildPlaybackRequestFromStreamInfo(
        stream,
        detail.title,
        detail.artist || '音乐播放',
        { overrideArtworkUrl: detail.coverUrl }
      ));
      return;
    }

    if (index < 0 || index >= detail.tracks.length) {
      return;
    }
    const track: MpMusicTrackItem = detail.tracks[index];
    const artist = track.artist.length > 0 ? track.artist : detail.artist;
    this.resolvingTrackIdx = index;
    this.statusTip = '';
    const stream = await MoviePilotRepository.shared().fetchMusicStreamInfo(
      track.title,
      artist,
      detail.title,
      track.mediaSource || detail.mediaSource,
      track.mediaId || track.id,
      track.trackNumber > 0 ? track.trackNumber : (index + 1)
    );
    this.resolvingTrackIdx = -1;
    if (!stream || stream.contentUrl.length === 0) {
      this.statusTip = `媒体库暂未收录《${track.title}》本地音源，可先订阅专辑`;
      return;
    }
    const queue = this.buildAlbumQueue(detail);
    const artwork = track.coverUrl.length > 0 ? track.coverUrl : detail.coverUrl;
    this.visible = false;
    this.onPlayMedia(buildPlaybackRequestFromStreamInfo(
      stream,
      track.title,
      artist.length > 0 ? `${artist} · ${detail.title}` : detail.title,
      {
        queue: queue,
        queueIndex: index,
        overrideArtworkUrl: artwork
      }
    ));
  }

  @Builder
  private albumViewBuilder() {
    if (this.loadingAlbum) {
      Column({ space: 10 }) {
        LoadingProgress()
          .width(34)
          .height(34)
          .color(this.accentHex)
        Text('正在加载专辑曲目…')
          .fontSize(13)
          .fontColor(mpSecondaryText(this.isDark))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.albumDetail) {
      Column({ space: 14 }) {
        // 专辑头部信息卡
        Row({ space: 14 }) {
          if (this.albumDetail.coverUrl.length > 0) {
            MpRemoteImage({
              src: this.albumDetail.coverUrl,
              imgWidth: 104,
              imgHeight: 104,
              imgRadius: 18,
              placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
            })
          } else {
            Stack() {
              SymbolGlyph($r('sys.symbol.music'))
                .fontSize(34)
                .fontColor([this.accentHex])
            }
            .width(104)
            .height(104)
            .borderRadius(18)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          }

          Column({ space: 7 }) {
            Text(this.albumDetail.title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            // 可点击进入歌手详情的歌手胶囊
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.person_fill'))
                .fontSize(13)
                .fontColor([this.accentHex])
              Text(this.albumDetail.artist || '未知歌手')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.accentHex)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.albumDetail.artistId.length > 0) {
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(12)
                  .fontColor([this.accentHex])
              }
            }
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .onClick(() => {
              this.openArtistView(
                this.albumDetail?.artistId ?? '',
                this.albumDetail?.artist ?? '',
                this.albumDetail?.mediaSource ?? 'musicbrainz'
              );
            })

            Text(
              `${this.albumDetail.releaseDate || this.albumDetail.year || '音乐专辑'}` +
              `${this.albumDetail.tracks.length > 0 ? ' · 共 ' + this.albumDetail.tracks.length + ' 首' : ''}`
            )
              .fontSize(11.5)
              .fontColor(mpSecondaryText(this.isDark))
              .maxLines(1)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 18, right: 18 })

        // 主操作行：播放全部 + 订阅切换
        Row({ space: 10 }) {
          Row({ space: 6 }) {
            if (this.resolvingTrackIdx === 0) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(Color.White)
            } else {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(16)
                .fontColor([Color.White])
            }
            Text('播放全部')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .layoutWeight(1)
          .height(42)
          .justifyContent(FlexAlign.Center)
          .borderRadius(21)
          .backgroundColor(this.accentHex)
          .onClick(() => {
            this.playAlbumTrackAt(0).catch(() => {});
          })

          Row({ space: 6 }) {
            SymbolGlyph($r(this.isSubscribed ? 'sys.symbol.checkmark_circle_fill' : 'sys.symbol.plus_circle_fill'))
              .fontSize(16)
              .fontColor([this.isSubscribed ? '#34C759' : mpPrimaryText(this.isDark)])
            Text(this.isSubscribed ? '已订阅' : '订阅专辑')
              .fontSize(13.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isSubscribed ? '#34C759' : mpPrimaryText(this.isDark))
          }
          .padding({ left: 16, right: 16 })
          .height(42)
          .borderRadius(21)
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          .onClick(() => {
            this.handleToggleSubscribe().catch(() => {});
          })
        }
        .width('100%')
        .padding({ left: 18, right: 18 })

        if (this.statusTip.length > 0) {
          Text(this.statusTip)
            .fontSize(12)
            .fontColor(this.accentHex)
            .width('100%')
            .padding({ left: 18, right: 18 })
        }

        // 曲目列表
        if (this.albumDetail.tracks.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.music'))
              .fontSize(30)
              .fontColor([mpSecondaryText(this.isDark)])
            Text('暂无分轨曲目明细，可直接点击上方播放或订阅')
              .fontSize(12.5)
              .fontColor(mpSecondaryText(this.isDark))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 6 }) {
            ForEach(this.albumDetail.tracks, (tr: MpMusicTrackItem, idx: number) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text(String(tr.trackNumber > 0 ? tr.trackNumber : (idx + 1)).padStart(2, '0'))
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpSecondaryText(this.isDark))
                    .width(26)

                  Column({ space: 2 }) {
                    Text(tr.title)
                      .fontSize(14.5)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (tr.artist.length > 0) {
                      Text(tr.artist)
                        .fontSize(11.5)
                        .fontColor(mpSecondaryText(this.isDark))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (tr.durationSec > 0) {
                    Text(formatTrackDurationSec(tr.durationSec))
                      .fontSize(11.5)
                      .fontColor(mpSecondaryText(this.isDark))
                  }

                  if (this.resolvingTrackIdx === idx) {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color(this.accentHex)
                  } else {
                    SymbolGlyph($r('sys.symbol.play_circle'))
                      .fontSize(20)
                      .fontColor([this.accentHex])
                  }
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .borderRadius(14)
                .backgroundColor(HarmonyThemeColors.card(this.isDark))
                .onClick(() => {
                  this.playAlbumTrackAt(idx).catch(() => {});
                })
              }
            }, (tr: MpMusicTrackItem, idx: number) => `trk_${idx}_${tr.id}_${tr.title}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 24 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  private artistViewBuilder() {
    if (this.loadingArtist) {
      Column({ space: 10 }) {
        LoadingProgress()
          .width(34)
          .height(34)
          .color(this.accentHex)
        Text('正在加载歌手作品集…')
          .fontSize(13)
          .fontColor(mpSecondaryText(this.isDark))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.artistDetail) {
      Scroll() {
        Column({ space: 16 }) {
          Row({ space: 14 }) {
            if (this.artistDetail.imageUrl.length > 0) {
              MpRemoteImage({
                src: this.artistDetail.imageUrl,
                imgWidth: 84,
                imgHeight: 84,
                imgRadius: 42,
                placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
              })
            } else {
              Stack() {
                SymbolGlyph($r('sys.symbol.person_fill'))
                  .fontSize(32)
                  .fontColor([this.accentHex])
              }
              .width(84)
              .height(84)
              .borderRadius(42)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            }

            Column({ space: 5 }) {
              Text(this.artistDetail.name)
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor(mpPrimaryText(this.isDark))
              if (this.artistDetail.country.length > 0 || this.artistDetail.lifeSpan.length > 0) {
                Text(
                  `${this.artistDetail.country}${this.artistDetail.country && this.artistDetail.lifeSpan ? ' · ' : ''}${this.artistDetail.lifeSpan}`
                )
                  .fontSize(12)
                  .fontColor(mpSecondaryText(this.isDark))
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          if (this.artistDetail.overview.length > 0) {
            Text(this.artistDetail.overview)
              .fontSize(13)
              .lineHeight(19)
              .fontColor(mpSecondaryText(this.isDark))
              .width('100%')
          }

          Text('代表专辑')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .width('100%')

          if (this.artistDetail.albums.length === 0) {
            Text('暂无更多专辑记录')
              .fontSize(13)
              .fontColor(mpSecondaryText(this.isDark))
              .padding({ top: 12, bottom: 12 })
          } else {
            Grid() {
              ForEach(this.artistDetail.albums, (al: MpMusicAlbum) => {
                GridItem() {
                  Column({ space: 6 }) {
                    if (al.coverUrl.length > 0) {
                      MpRemoteImage({
                        src: al.coverUrl,
                        imgWidth: '100%',
                        imgAspectRatio: 1,
                        imgRadius: 14,
                        placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                      })
                    } else {
                      Stack() {
                        SymbolGlyph($r('sys.symbol.music'))
                          .fontSize(28)
                          .fontColor([this.accentHex])
                      }
                      .width('100%')
                      .aspectRatio(1)
                      .borderRadius(14)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    }
                    Text(al.title)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    if (al.year.length > 0) {
                      Text(al.year)
                        .fontSize(11)
                        .fontColor(mpSecondaryText(this.isDark))
                        .maxLines(1)
                        .width('100%')
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => {
                    this.loadAlbumFromSeed(al).catch(() => {});
                  })
                }
              }, (al: MpMusicAlbum) => `art_al_${al.id}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(10)
            .rowsGap(14)
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 28 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
  }

  @Builder
  private sheetContentBuilder() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        if (this.mode === 'artist') {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(16)
              .fontColor([this.accentHex])
            Text('专辑')
              .fontSize(13.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentHex)
          }
          .padding({ left: 8, right: 10, top: 5, bottom: 5 })
          .borderRadius(14)
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          .onClick(() => {
            this.mode = 'album';
          })
        } else {
          Text('音乐专辑')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
        }

        Blank()

        Stack() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(15)
            .fontColor([mpSecondaryText(this.isDark)])
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
        .onClick(() => {
          this.visible = false;
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16, bottom: 4 })

      if (this.mode === 'artist') {
        this.artistViewBuilder()
      } else {
        this.albumViewBuilder()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HarmonyThemeColors.overlayFallback(this.isDark))
  }

  build() {
    Stack()
      .width(0)
      .height(0)
      .bindSheet($$this.visible, this.sheetContentBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
  }
}

/**
 * 全局搜索已入库剧集快捷选集播放半模态（`bindSheet`）：
 * - 拉取剧集各季与分集列表，点击任意单集直接起播并自动装载本季全集连播队列。
 */
@Component
export struct LibrarySeriesEpisodeSheetHost {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Link visible: boolean;
  @Prop @Watch('onTargetChanged') seriesItem: MpMediaItem | null = null;
  @Prop @Watch('onTriggerChanged') openTrigger: number = 0;

  @State private loading: boolean = false;
  @State private seasons: MpMediaServerEpisode[] = [];
  @State private selectedSeasonIdx: number = 0;
  @State private episodes: MpMediaServerEpisode[] = [];
  @State private playingEpId: string = '';

  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};
  onOpenDetail: (item: MpMediaItem) => void = () => {};

  onTargetChanged(): void {
    if (this.visible && this.seriesItem) {
      this.loadSeasons(this.seriesItem);
    }
  }

  onTriggerChanged(): void {
    if (this.visible && this.seriesItem) {
      this.loadSeasons(this.seriesItem);
    }
  }

  private async loadSeasons(series: MpMediaItem): Promise<void> {
    const seriesId = (series.serverItemId || series.id).trim();
    const server = series.serverName.trim();
    if (!seriesId || !server) {
      return;
    }
    this.loading = true;
    this.seasons = [];
    this.episodes = [];
    this.selectedSeasonIdx = 0;
    const repo = MoviePilotRepository.shared();
    try {
      const sList = await repo.fetchMediaServerSeasons(seriesId, server);
      this.seasons = sList;
      if (sList.length > 0) {
        await this.loadSeasonEpisodes(seriesId, server, sList[0]);
      } else {
        this.episodes = await repo.fetchMediaServerSeasonEpisodes(seriesId, server, '', 1);
      }
    } catch {
      this.episodes = [];
    }
    this.loading = false;
  }

  private async loadSeasonEpisodes(seriesId: string, server: string, season: MpMediaServerEpisode): Promise<void> {
    this.loading = true;
    try {
      this.episodes = await MoviePilotRepository.shared().fetchMediaServerSeasonEpisodes(
        seriesId,
        server,
        season.itemId,
        season.seasonNumber >= 0 ? season.seasonNumber : -1
      );
    } catch {
      this.episodes = [];
    }
    this.loading = false;
  }

  private async playEpisodeAt(idx: number): Promise<void> {
    if (idx < 0 || idx >= this.episodes.length || this.playingEpId.length > 0) {
      return;
    }
    const ep = this.episodes[idx];
    const srv = ep.server || (this.seriesItem?.serverName ?? '');
    this.playingEpId = ep.itemId;
    const stream = await MoviePilotRepository.shared().fetchVideoStreamInfo(ep.itemId, srv);
    this.playingEpId = '';
    if (!stream || stream.contentUrl.length === 0) {
      return;
    }
    const queue: HarmonyQueueItem[] = [];
    for (let i = 0; i < this.episodes.length; i++) {
      const e = this.episodes[i];
      const epTag = e.episodeNumber > 0 ? `E${String(e.episodeNumber).padStart(2, '0')} · ` : '';
      queue.push({
        itemId: e.itemId,
        title: `${epTag}${e.title}`,
        subtitle: this.seriesItem?.title ?? e.seriesName,
        server: e.server || srv,
        artworkUrl: e.thumbUrl || e.posterUrl,
        durationMs: e.durationMs,
        resumePositionMs: e.resumePositionMs
      });
    }
    const epPrefix = ep.episodeNumber > 0 ? `E${String(ep.episodeNumber).padStart(2, '0')} · ` : '';
    this.visible = false;
    this.onPlayMedia(buildPlaybackRequestFromStreamInfo(
      stream,
      `${epPrefix}${ep.title}`,
      this.seriesItem?.title ?? srv,
      {
        queue: queue,
        queueIndex: idx,
        overrideResumeMs: ep.resumePositionMs,
        overrideArtworkUrl: ep.thumbUrl || ep.posterUrl
      }
    ));
  }

  @Builder
  private sheetContentBuilder() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.seriesItem?.title ?? '选集播放')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('选择单集直接进入影院连播')
            .fontSize(11.5)
            .fontColor(mpSecondaryText(this.isDark))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.seriesItem) {
          Text('完整详情')
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.accentHex)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(12)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .onClick(() => {
              const target = this.seriesItem;
              this.visible = false;
              if (target) {
                this.onOpenDetail(target);
              }
            })
        }

        Stack() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(15)
            .fontColor([mpSecondaryText(this.isDark)])
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
        .onClick(() => {
          this.visible = false;
        })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 16 })

      if (this.seasons.length > 1) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.seasons, (s: MpMediaServerEpisode, idx: number) => {
              NativeAdaptivePill({
                title: s.title || `第 ${s.seasonNumber} 季`,
                selected: this.selectedSeasonIdx === idx,
                onTap: () => {
                  this.selectedSeasonIdx = idx;
                  if (this.seriesItem) {
                    this.loadSeasonEpisodes(
                      this.seriesItem.serverItemId || this.seriesItem.id,
                      this.seriesItem.serverName,
                      s
                    ).catch(() => {});
                  }
                }
              })
            }, (s: MpMediaServerEpisode) => `sea_${s.itemId}`)
          }
          .padding({ left: 18, right: 18 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      if (this.loading) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.accentHex)
          Text('正在读取剧集列表…')
            .fontSize(13)
            .fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.episodes.length === 0) {
        Column({ space: 8 }) {
          Text('未查询到可播放单集')
            .fontSize(13.5)
            .fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.episodes, (ep: MpMediaServerEpisode, idx: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(ep.episodeNumber > 0 ? `E${String(ep.episodeNumber).padStart(2, '0')}` : String(idx + 1))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.accentHex)
                  .width(34)

                Column({ space: 2 }) {
                  Text(ep.title)
                    .fontSize(14.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(mpPrimaryText(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (ep.durationMs > 0 || ep.resumePositionMs > 30000) {
                    Text(
                      `${ep.durationMs > 0 ? formatMediaDurationMs(ep.durationMs) : ''}` +
                      `${ep.resumePositionMs > 30000 ? ' · 已看至 ' + formatMediaDurationMs(ep.resumePositionMs) : ''}`
                    )
                      .fontSize(11.5)
                      .fontColor(mpSecondaryText(this.isDark))
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (this.playingEpId === ep.itemId) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                    .color(this.accentHex)
                } else {
                  SymbolGlyph($r('sys.symbol.play_circle_fill'))
                    .fontSize(22)
                    .fontColor([this.accentHex])
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 11, bottom: 11 })
              .borderRadius(14)
              .backgroundColor(HarmonyThemeColors.card(this.isDark))
              .onClick(() => {
                this.playEpisodeAt(idx).catch(() => {});
              })
            }
          }, (ep: MpMediaServerEpisode) => `ep_${ep.itemId}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 24 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HarmonyThemeColors.overlayFallback(this.isDark))
  }

  build() {
    Stack()
      .width(0)
      .height(0)
      .bindSheet($$this.visible, this.sheetContentBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
  }
}
