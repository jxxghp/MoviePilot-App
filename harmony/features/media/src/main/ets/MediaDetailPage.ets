import {
  MoviePilotRepository,
  MpMediaItem,
  MpMediaRatingBadge,
  MpCastMember,
  MpSeasonInfo,
  MpTmdbEpisodeItem,
  MpPersonDetail,
  MpRemoteImage
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  NativeTopStatusBarBlur,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonySurfaceModifier,
  HarmonyThemeColors,
  HarmonyEntityLogo,
  HarmonyMultiRatingsRow,
  HarmonySkeletonHost,
  HarmonySkeletonBlock,
  HarmonyEpisodeStripSkeleton,
  HarmonyMediaDetailBodySkeleton,
  HarmonyPosterGridSkeleton,
  HarmonyPosterRowCardGridSkeleton,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import {
  HarmonyPlaybackRequest,
  HarmonyQueueItem,
  buildPlaybackRequestFromStreamInfo
} from '@moviepilot/media_player';

/**
 * 鸿蒙沉浸式影视/剧集详情页：
 * - 修复 V3 订阅状态同步、乐观更新防覆盖与静态 `$r(...)` 符号即时刷新；
 * - 支持主按钮与分季胶囊独立添加订阅、点击已订阅按钮弹出原生确认框取消订阅；
 * - 电视剧支持分季切换并以 16:9 横版剧照卡片横向滚动展示单集列表。
 */
@Component
export struct HarmonyMediaDetailPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;
  @Prop @Watch('onItemChanged') item: MpMediaItem = {
    id: '', mediaId: '', tmdbId: '', doubanId: '', title: '', enTitle: '', year: '', type: '电影',
    overview: '', vote: 0, posterUrl: '', backdropUrl: '', logoUrl: '', source: 'themoviedb',
    inLibrary: false, subtitle: '', percent: 0, serverName: '', playUrl: ''
  };
  @State private hydratedItem: MpMediaItem | null = null;
  @State private multiRatings: MpMediaRatingBadge[] = [];
  @State private scrollOffsetY: number = 0;
  @State private subscribed: boolean = false;
  @State private subscribedSeasons: number[] = [];
  @State private mutatingSubscribe: boolean = false;
  @State private overviewExpanded: boolean = false;
  @State private cast: MpCastMember[] = [];
  @State private seasons: MpSeasonInfo[] = [];
  @State private activeSeasonNumber: number = 1;
  @State private tmdbEpisodes: MpTmdbEpisodeItem[] = [];
  @State private loadingDetail: boolean = true;
  @State private loadingEpisodes: boolean = false;
  @State private playableSeriesMap: Record<string, Record<string, string>> = {};
  @State private remoteExistsMap: Record<string, number[]> = {};
  @State private availabilityLoaded: boolean = false;
  @State private statusMsg: string = '';
  @State private statusIsError: boolean = false;
  private userMutatedSubscribe: boolean = false;
  private detailLoadSeq: number = 0;
  private scroller: Scroller = new Scroller();
  onBack: () => void = () => {};
  onSearchResource: (kw: string) => void = () => {};
  onOpenPerson: (person: MpCastMember) => void = () => {};
  onOpenSeasonDetail: (series: MpMediaItem, season: MpSeasonInfo, seriesItemId: string, server: string) => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  aboutToAppear(): void {
    this.loadDetail();
  }

  onItemChanged(): void {
    this.hydratedItem = null;
    this.multiRatings = [];
    this.overviewExpanded = false;
    this.subscribed = false;
    this.subscribedSeasons = [];
    this.mutatingSubscribe = false;
    this.userMutatedSubscribe = false;
    this.cast = [];
    this.seasons = [];
    this.activeSeasonNumber = 1;
    this.tmdbEpisodes = [];
    this.playableSeriesMap = {};
    this.remoteExistsMap = {};
    this.availabilityLoaded = false;
    this.loadingDetail = true;
    this.loadingEpisodes = false;
    this.statusMsg = '';
    this.statusIsError = false;
    this.loadDetail();
  }

  private activeMedia(): MpMediaItem {
    return this.hydratedItem ?? this.item;
  }

  private isTvMedia(target?: MpMediaItem): boolean {
    const m = target ?? this.activeMedia();
    const lower = (m.type ?? '').trim().toLowerCase();
    return lower === '电视剧' || lower === 'tv' || lower === 'series' || lower === '番剧' || this.seasons.length > 0;
  }

  private isSeasonSubscribed(seasonNum: number): boolean {
    return this.subscribedSeasons.includes(seasonNum);
  }

  private isPrimarySubscribed(): boolean {
    if (this.isTvMedia() && this.seasons.length > 0) {
      return this.subscribedSeasons.includes(this.activeSeasonNumber) ||
        (this.subscribed && this.subscribedSeasons.length === 0);
    }
    return this.subscribed || this.subscribedSeasons.length > 0;
  }

  private primarySubscribeLabel(): string {
    if (this.isTvMedia() && this.seasons.length > 0) {
      return `订阅第 ${this.activeSeasonNumber} 季`;
    }
    return '添加订阅';
  }

  private primarySubscribedLabel(): string {
    if (this.isTvMedia() && this.seasons.length > 0 && this.subscribedSeasons.includes(this.activeSeasonNumber)) {
      return `第 ${this.activeSeasonNumber} 季已订阅`;
    }
    return '已订阅';
  }

  private showToastSafe(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
    } catch {
      // ignore toast error on unsupported context
    }
  }

  private async loadDetail(): Promise<void> {
    const seq = ++this.detailLoadSeq;
    this.loadingDetail = true;
    const repo = MoviePilotRepository.shared();
    let workingItem: MpMediaItem = this.item;
    this.multiRatings = repo.seedRatingsForItem(workingItem);

    // 1. 当缺少 tmdbId 或简介为空时，通过 V3 GET /api/v1/media/{rawMediaId}?media_source=... 补全详情与分季
    if (!workingItem.tmdbId || workingItem.overview.trim().length === 0) {
      try {
        const bundle = await repo.fetchMediaDetailBundle(workingItem);
        if (seq !== this.detailLoadSeq) { return; }
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

    // 2. 并发拉取 /api/v1/media/status（入库与各季订阅字典）、/api/v1/subscribe/media/{id}、演职员与季列表
    const needCredits = workingItem.tmdbId.length > 0 && this.cast.length === 0;
    const needSeasons = this.seasons.length === 0 &&
      (workingItem.type === '电视剧' || workingItem.type.toLowerCase() === 'tv');

    try {
      const results = await Promise.all([
        repo.fetchMediaStatus(workingItem),
        repo.checkMediaSubscribed(workingItem),
        needCredits ? repo.fetchMediaCredits(workingItem.tmdbId, workingItem.type) : Promise.resolve(this.cast),
        needSeasons ? repo.fetchMediaSeasonsForItem(workingItem) : Promise.resolve(this.seasons)
      ]);
      if (seq !== this.detailLoadSeq) { return; }

      const mediaStatus = results[0];
      const directSub = results[1];
      if (results[2].length > 0) {
        this.cast = results[2];
      }
      if (results[3].length > 0) {
        this.seasons = results[3];
      }

      // 合并媒体库命中信息，支持已入库条目一键直放
      if (mediaStatus.itemId.length > 0) {
        const merged: MpMediaItem = {
          id: workingItem.id,
          mediaId: workingItem.mediaId,
          tmdbId: workingItem.tmdbId,
          doubanId: workingItem.doubanId,
          title: workingItem.title,
          enTitle: workingItem.enTitle,
          year: workingItem.year,
          type: workingItem.type,
          overview: workingItem.overview,
          vote: workingItem.vote,
          posterUrl: workingItem.posterUrl,
          backdropUrl: workingItem.backdropUrl,
          logoUrl: workingItem.logoUrl,
          source: workingItem.source,
          inLibrary: true,
          subtitle: workingItem.subtitle,
          percent: workingItem.percent,
          serverName: mediaStatus.server || workingItem.serverName,
          playUrl: workingItem.playUrl,
          serverItemId: mediaStatus.itemId,
          imdbId: workingItem.imdbId,
          tvdbId: workingItem.tvdbId
        };
        workingItem = merged;
        this.hydratedItem = merged;
      }

      // 若用户已在请求返回前主动点击订阅/取消订阅，只合并分季而不覆盖用户乐观状态
      if (!this.userMutatedSubscribe) {
        this.subscribed = mediaStatus.subscribed || directSub || mediaStatus.seasons.length > 0;
        this.subscribedSeasons = mediaStatus.seasons;
      } else {
        const mergedSeasons: number[] = [...this.subscribedSeasons];
        for (let i = 0; i < mediaStatus.seasons.length; i++) {
          const sn = mediaStatus.seasons[i];
          if (!mergedSeasons.includes(sn)) {
            mergedSeasons.push(sn);
          }
        }
        mergedSeasons.sort((a: number, b: number) => a - b);
        if (this.subscribed) {
          this.subscribedSeasons = mergedSeasons;
        }
      }

      this.multiRatings = repo.seedRatingsForItem(workingItem);
      repo.fetchMultiSourceRatings(
        workingItem,
        0,
        [],
        workingItem.serverItemId ?? '',
        workingItem.serverName
      ).then((badges: MpMediaRatingBadge[]) => {
        if (seq === this.detailLoadSeq && badges.length > 0) {
          this.multiRatings = badges;
        }
      }).catch(() => {});

      // 3. 初始化电视剧默认选中季并拉取 16:9 横版分集剧照卡片 + 各季入库集数映射
      if (this.seasons.length > 0 || this.isTvMedia(workingItem)) {
        if (this.seasons.length > 0) {
          const preferred = this.seasons.find((s: MpSeasonInfo) => s.seasonNumber > 0) ?? this.seasons[0];
          this.activeSeasonNumber = preferred.seasonNumber;
          this.loadSeasonEpisodes(workingItem, preferred.seasonNumber);
        }
        const seriesSrvId = workingItem.serverItemId ?? '';
        const availRes = await Promise.all([
          seriesSrvId.length > 0
            ? repo.fetchPlayableSeriesEpisodes(seriesSrvId, workingItem.serverName)
            : Promise.resolve({} as Record<string, Record<string, string>>),
          repo.fetchRemoteExistingEpisodes(workingItem)
        ]);
        if (seq === this.detailLoadSeq) {
          this.playableSeriesMap = availRes[0];
          this.remoteExistsMap = availRes[1];
          this.availabilityLoaded = true;
        }
      }
    } catch {
      // keep existing state
    }
    if (seq === this.detailLoadSeq) {
      this.loadingDetail = false;
    }
  }

  private async loadSeasonEpisodes(media: MpMediaItem, seasonNum: number): Promise<void> {
    this.loadingEpisodes = true;
    try {
      this.tmdbEpisodes = await MoviePilotRepository.shared().fetchSeasonEpisodesSmart(
        media,
        seasonNum,
        media.serverItemId ?? '',
        media.serverName
      );
    } catch {
      this.tmdbEpisodes = [];
    }
    this.loadingEpisodes = false;
  }

  private selectSeason(seasonNum: number): void {
    if (this.activeSeasonNumber === seasonNum && this.tmdbEpisodes.length > 0) {
      return;
    }
    this.activeSeasonNumber = seasonNum;
    this.loadSeasonEpisodes(this.activeMedia(), seasonNum);
  }

  private seasonExistingCount(seasonNum: number): number {
    const key = String(seasonNum);
    const seen: number[] = [];
    const pMap = this.playableSeriesMap[key];
    if (pMap) {
      const eKeys = Object.keys(pMap);
      for (let i = 0; i < eKeys.length; i++) {
        const n = Number(eKeys[i]);
        if (Number.isFinite(n) && n > 0 && !seen.includes(n)) {
          seen.push(n);
        }
      }
    }
    const rArr = this.remoteExistsMap[key];
    if (rArr) {
      for (let i = 0; i < rArr.length; i++) {
        if (!seen.includes(rArr[i])) {
          seen.push(rArr[i]);
        }
      }
    }
    return seen.length;
  }

  private episodePlayableItemId(seasonNum: number, epNum: number): string {
    const pMap = this.playableSeriesMap[String(seasonNum)];
    if (!pMap) { return ''; }
    return pMap[String(epNum)] ?? '';
  }

  private isEpisodeInLibrary(seasonNum: number, epNum: number): boolean {
    if (this.episodePlayableItemId(seasonNum, epNum).length > 0) {
      return true;
    }
    const rArr = this.remoteExistsMap[String(seasonNum)];
    return rArr ? rArr.includes(epNum) : false;
  }

  private async playInlineEpisode(seasonNum: number, epNum: number, epTitle: string, stillUrl: string): Promise<void> {
    const cur = this.activeMedia();
    const pMap = this.playableSeriesMap[String(seasonNum)];
    if (!pMap) { return; }
    const targetId = pMap[String(epNum)] ?? '';
    if (!targetId) { return; }
    const eKeys = Object.keys(pMap);
    const sortedNums: number[] = [];
    for (let i = 0; i < eKeys.length; i++) {
      const n = Number(eKeys[i]);
      if (Number.isFinite(n) && n > 0) { sortedNums.push(Math.round(n)); }
    }
    sortedNums.sort((a: number, b: number) => a - b);
    const queue: HarmonyQueueItem[] = [];
    let qIdx = 0;
    for (let i = 0; i < sortedNums.length; i++) {
      const num = sortedNums[i];
      const qid = pMap[String(num)] ?? '';
      if (!qid) { continue; }
      if (num === epNum) { qIdx = queue.length; }
      const hitEp = this.tmdbEpisodes.find((e: MpTmdbEpisodeItem) => e.episodeNumber === num);
      const code = `S${String(seasonNum).padStart(2, '0')}E${String(num).padStart(2, '0')}`;
      queue.push({
        itemId: qid,
        title: hitEp ? `${cur.title} · ${code} · ${hitEp.title}` : `${cur.title} · ${code}`,
        subtitle: cur.serverName,
        server: cur.serverName,
        artworkUrl: (hitEp && hitEp.stillUrl.length > 0) ? hitEp.stillUrl : (cur.posterUrl || cur.backdropUrl),
        trackNumber: num
      });
    }
    try {
      const manifest = await MoviePilotRepository.shared().fetchVideoStreamInfo(targetId, cur.serverName);
      if (manifest && manifest.contentUrl.length > 0) {
        const code = `S${String(seasonNum).padStart(2, '0')}E${String(epNum).padStart(2, '0')}`;
        this.onPlayMedia(buildPlaybackRequestFromStreamInfo(
          manifest,
          `${cur.title} · ${code} · ${epTitle}`,
          cur.serverName || cur.year,
          {
            queue: queue.length > 1 ? queue : undefined,
            queueIndex: queue.length > 1 ? qIdx : undefined,
            overrideArtworkUrl: stillUrl || cur.posterUrl || cur.backdropUrl
          }
        ));
      } else {
        this.statusIsError = true;
        this.statusMsg = '无法读取该集的媒体服务器流地址';
      }
    } catch {
      this.statusIsError = true;
      this.statusMsg = '媒体流请求异常，请稍后重试';
    }
  }

  private async handleAddSubscribe(targetSeason?: number): Promise<void> {
    if (this.mutatingSubscribe) { return; }
    const media = this.activeMedia();
    const isTv = this.isTvMedia(media);
    const seasonToUse: number | undefined = isTv
      ? (targetSeason !== undefined ? targetSeason : (this.seasons.length > 0 ? this.activeSeasonNumber : 1))
      : undefined;

    this.mutatingSubscribe = true;
    this.userMutatedSubscribe = true;
    try {
      const res = await MoviePilotRepository.shared().addSubscribeWithMessage(media, seasonToUse);
      if (res.ok) {
        this.subscribed = true;
        if (seasonToUse !== undefined && !this.subscribedSeasons.includes(seasonToUse)) {
          const next = [...this.subscribedSeasons, seasonToUse];
          next.sort((a: number, b: number) => a - b);
          this.subscribedSeasons = next;
        }
        this.statusIsError = false;
        this.statusMsg = res.message || (seasonToUse !== undefined
          ? `已订阅「${media.title}」第 ${seasonToUse} 季`
          : `已订阅「${media.title}」`);
        this.showToastSafe(this.statusMsg);
      } else {
        this.statusIsError = true;
        this.statusMsg = res.message || '订阅添加失败，请检查数据源配置';
        this.showToastSafe(this.statusMsg);
      }
    } catch {
      this.statusIsError = true;
      this.statusMsg = '网络请求异常，添加订阅失败';
    }
    this.mutatingSubscribe = false;
  }

  private confirmCancelSubscribe(targetSeason?: number): void {
    if (this.mutatingSubscribe) { return; }
    const media = this.activeMedia();
    const isTv = this.isTvMedia(media);
    const seasonToCancel: number | undefined = isTv
      ? (targetSeason !== undefined ? targetSeason : (this.seasons.length > 0 ? this.activeSeasonNumber : undefined))
      : undefined;
    const seasonLabel = seasonToCancel !== undefined ? `第 ${seasonToCancel} 季` : '';

    this.getUIContext().showAlertDialog({
      title: '取消订阅',
      message: `确定要取消订阅「${media.title}${seasonLabel ? ' · ' + seasonLabel : ''}」吗？`,
      autoCancel: true,
      primaryButton: {
        value: '保留订阅',
        action: () => {}
      },
      secondaryButton: {
        value: '取消订阅',
        fontColor: '#E84855',
        action: () => {
          this.executeCancelSubscribe(seasonToCancel);
        }
      }
    });
  }

  private async executeCancelSubscribe(seasonToCancel?: number): Promise<void> {
    if (this.mutatingSubscribe) { return; }
    const media = this.activeMedia();
    this.mutatingSubscribe = true;
    this.userMutatedSubscribe = true;
    try {
      const ok = await MoviePilotRepository.shared().deleteMediaSubscribe(media, seasonToCancel);
      if (ok) {
        if (seasonToCancel !== undefined) {
          this.subscribedSeasons = this.subscribedSeasons.filter((sn: number) => sn !== seasonToCancel);
          this.subscribed = this.subscribedSeasons.length > 0;
        } else {
          this.subscribed = false;
          this.subscribedSeasons = [];
        }
        this.statusIsError = false;
        this.statusMsg = seasonToCancel !== undefined
          ? `已取消第 ${seasonToCancel} 季订阅`
          : '已取消订阅';
        this.showToastSafe(this.statusMsg);
      } else {
        this.statusIsError = true;
        this.statusMsg = '取消订阅失败，请稍后重试';
      }
    } catch {
      this.statusIsError = true;
      this.statusMsg = '取消订阅请求异常';
    }
    this.mutatingSubscribe = false;
  }

  private sourceDisplayLabel(src: string): string {
    const lower = (src ?? '').toLowerCase();
    if (lower.includes('douban')) { return '豆瓣'; }
    if (lower.includes('bangumi')) { return 'Bangumi'; }
    if (lower.includes('anilist')) { return 'AniList'; }
    if (lower.includes('music')) { return 'MusicBrainz'; }
    return 'TMDB';
  }

  private isShortLandscape(): boolean {
    return HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp);
  }

  private heroHeightVp(): number {
    return HarmonyAdaptiveLayout.detailHeroHeightVp(this.windowWidthVp, this.windowHeightVp);
  }

  @Builder
  primarySubscribeButtonBuilder() {
    if (this.isPrimarySubscribed()) {
      Button() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(16)
            .fontColor([Color.White])
          Text(this.primarySubscribedLabel())
            .fontSize(14.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .height(46)
      .borderRadius(23)
      .backgroundColor('#34C759')
      .enabled(!this.mutatingSubscribe)
      .opacity(this.mutatingSubscribe ? 0.72 : 1)
      .accessibilityText(`${this.primarySubscribedLabel()}，点击取消订阅`)
      .onClick(() => this.confirmCancelSubscribe())
    } else {
      Button() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.bookmark_fill'))
            .fontSize(16)
            .fontColor([!this.activeMedia().inLibrary ? Color.White : mpPrimaryText(this.isDark)])
          Text(this.mutatingSubscribe ? '处理中…' : this.primarySubscribeLabel())
            .fontSize(14.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(!this.activeMedia().inLibrary ? Color.White : mpPrimaryText(this.isDark))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .height(46)
      .borderRadius(23)
      .backgroundColor(this.activeMedia().inLibrary ? HarmonyThemeColors.chipFill(this.isDark) : this.accentHex)
      .enabled(!this.mutatingSubscribe)
      .opacity(this.mutatingSubscribe ? 0.72 : 1)
      .accessibilityText(this.primarySubscribeLabel())
      .onClick(() => { this.handleAddSubscribe(); })
    }
  }

  @Builder
  seasonsSectionBuilder() {
    Column({ space: 12 }) {
      Row() {
        Text(`分季 (${this.seasons.length})`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .layoutWeight(1)
        if (this.subscribedSeasons.length > 0) {
          Text(`已订 ${this.subscribedSeasons.length} 季`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#34C759')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.seasons, (s: MpSeasonInfo) => {
            Column({ space: 6 }) {
              Stack({ alignContent: Alignment.TopEnd }) {
                MpRemoteImage({
                  src: s.posterUrl || this.activeMedia().posterUrl,
                  imgWidth: 112,
                  imgHeight: 162,
                  imgRadius: 12,
                  placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                })
                if (this.activeSeasonNumber === s.seasonNumber) {
                  Column()
                    .width(112)
                    .height(162)
                    .borderRadius(12)
                    .border({ width: 2, color: this.accentHex, radius: 12 })
                    .hitTestBehavior(HitTestMode.None)
                }
                if (this.isSeasonSubscribed(s.seasonNumber)) {
                  Row({ space: 3 }) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(10)
                      .fontColor([Color.White])
                    Text('已订')
                      .fontSize(10)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                  }
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(8)
                  .backgroundColor('#E034C759')
                  .margin(6)
                } else if (this.seasonExistingCount(s.seasonNumber) > 0) {
                  Text(
                    (s.episodeCount > 0 && this.seasonExistingCount(s.seasonNumber) < s.episodeCount)
                      ? `${this.seasonExistingCount(s.seasonNumber)}/${s.episodeCount}`
                      : '已入库'
                  )
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(8)
                    .backgroundColor(
                      (s.episodeCount > 0 && this.seasonExistingCount(s.seasonNumber) < s.episodeCount)
                        ? '#E0F29B38'
                        : '#E034C759'
                    )
                    .margin(6)
                }
              }
              .onClick(() => {
                const cur = this.activeMedia();
                this.onOpenSeasonDetail(cur, s, cur.serverItemId ?? '', cur.serverName);
              })

              Row({ space: 2 }) {
                Text(s.name)
                  .fontSize(13)
                  .fontWeight(this.activeSeasonNumber === s.seasonNumber ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.activeSeasonNumber === s.seasonNumber ? this.accentHex : mpPrimaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(11)
                  .fontColor([mpSecondaryText(this.isDark)])
              }
              .width(112)
              .onClick(() => {
                const cur = this.activeMedia();
                this.onOpenSeasonDetail(cur, s, cur.serverItemId ?? '', cur.serverName);
              })

              Text(
                this.seasonExistingCount(s.seasonNumber) > 0
                  ? `已入库 ${this.seasonExistingCount(s.seasonNumber)}/${s.episodeCount || this.seasonExistingCount(s.seasonNumber)} 集`
                  : (this.availabilityLoaded ? `共 ${s.episodeCount} 集 · 未入库` : `共 ${s.episodeCount} 集`)
              )
                .fontSize(11)
                .fontColor(mpSecondaryText(this.isDark))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width(112)
                .onClick(() => this.selectSeason(s.seasonNumber))

              if (this.isSeasonSubscribed(s.seasonNumber)) {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                    .fontSize(12)
                    .fontColor([Color.White])
                  Text('已订阅')
                    .fontSize(11.5)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                }
                .width(112)
                .height(28)
                .justifyContent(FlexAlign.Center)
                .borderRadius(14)
                .backgroundColor('#34C759')
                .onClick(() => this.confirmCancelSubscribe(s.seasonNumber))
              } else {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.bookmark_fill'))
                    .fontSize(12)
                    .fontColor([this.accentHex])
                  Text('订阅本季')
                    .fontSize(11.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.accentHex)
                }
                .width(112)
                .height(28)
                .justifyContent(FlexAlign.Center)
                .borderRadius(14)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '26' : '16'))
                .onClick(() => { this.handleAddSubscribe(s.seasonNumber); })
              }
            }
            .alignItems(HorizontalAlign.Start)
          }, (s: MpSeasonInfo) => `${s.seasonNumber}_${this.isSeasonSubscribed(s.seasonNumber)}_${this.activeSeasonNumber === s.seasonNumber}`)
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      // 当前季 16:9 横版剧集列表（横向滚动）
      if (this.loadingEpisodes) {
        HarmonySkeletonHost({ loadingLabel: `正在加载第 ${this.activeSeasonNumber} 季分集` }) {
          HarmonyEpisodeStripSkeleton({
            showHeader: true,
            showSeasonPills: false,
            itemCount: 3
          })
        }
      } else if (this.tmdbEpisodes.length > 0) {
        Column({ space: 10 }) {
          Row() {
            Text(`剧集 · 第 ${this.activeSeasonNumber} 季 (${this.tmdbEpisodes.length})`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })

          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.tmdbEpisodes, (ep: MpTmdbEpisodeItem) => {
                Column({ space: 6 }) {
                  Stack({ alignContent: Alignment.BottomStart }) {
                    MpRemoteImage({
                      src: ep.stillUrl || this.activeMedia().backdropUrl || this.activeMedia().posterUrl,
                      imgWidth: 228,
                      imgHeight: 128,
                      imgRadius: 14,
                      placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                    })

                    Column()
                      .width(228)
                      .height(48)
                      .borderRadius({ bottomLeft: 14, bottomRight: 14 })
                      .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#BA000000', 1]] })

                    Row() {
                      Text(`E${String(ep.episodeNumber).padStart(2, '0')}`)
                        .fontSize(10.5)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                        .borderRadius(8)
                        .backgroundColor('#B810141E')
                      Blank()
                      if (this.isEpisodeInLibrary(this.activeSeasonNumber, ep.episodeNumber)) {
                        Text('已入库')
                          .fontSize(10)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .borderRadius(8)
                          .backgroundColor('#E034C759')
                          .margin({ right: ep.runtimeMinutes > 0 ? 5 : 0 })
                      } else if (this.availabilityLoaded) {
                        Text('未入库')
                          .fontSize(10)
                          .fontColor('#D9FFFFFF')
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .borderRadius(8)
                          .backgroundColor('#8C1E2230')
                          .margin({ right: ep.runtimeMinutes > 0 ? 5 : 0 })
                      }
                      if (ep.runtimeMinutes > 0) {
                        Text(`${ep.runtimeMinutes} 分钟`)
                          .fontSize(10.5)
                          .fontColor('#E6FFFFFF')
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .borderRadius(8)
                          .backgroundColor('#8C000000')
                      }
                    }
                    .width(228)
                    .padding({ left: 8, right: 8, bottom: 8 })
                  }
                  .onClick(() => {
                    if (this.episodePlayableItemId(this.activeSeasonNumber, ep.episodeNumber).length > 0) {
                      this.playInlineEpisode(
                        this.activeSeasonNumber,
                        ep.episodeNumber,
                        ep.title,
                        ep.stillUrl
                      );
                    }
                  })

                  Text(`${ep.episodeNumber}. ${ep.title}`)
                    .fontSize(13.5)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(228)

                  if (ep.overview.length > 0 || ep.airDate.length > 0) {
                    Text(ep.overview.length > 0 ? ep.overview : ep.airDate)
                      .fontSize(11.5)
                      .fontColor(mpSecondaryText(this.isDark))
                      .lineHeight(16.5)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(228)
                  }
                }
                .width(228)
                .alignItems(HorizontalAlign.Start)
              }, (ep: MpTmdbEpisodeItem) => `${ep.seasonNumber}_${ep.episodeNumber}_${ep.id}`)
            }
            .alignItems(VerticalAlign.Top)
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
        }
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Column({ space: this.isShortLandscape() ? 14 : 18 }) {
          // 全幅主视觉
          Stack({ alignContent: Alignment.BottomStart }) {
            if (this.activeMedia().backdropUrl || this.activeMedia().posterUrl) {
              MpRemoteImage({
                src: this.activeMedia().backdropUrl || this.activeMedia().posterUrl,
                imgWidth: '100%',
                imgHeight: this.heroHeightVp(),
                placeholderColor: HarmonyThemeColors.card(this.isDark, this.paletteId)
              })
            } else {
              Column()
                .width('100%')
                .height(this.heroHeightVp())
                .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
            }

            Column()
              .width('100%')
              .height(this.heroHeightVp())
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

            Column({ space: this.isShortLandscape() ? 5 : 8 }) {
              if (this.activeMedia().logoUrl.length > 0) {
                MpRemoteImage({
                  src: this.activeMedia().logoUrl,
                  imgWidth: this.isShortLandscape() ? 156 : 190,
                  imgHeight: this.isShortLandscape() ? 46 : 62,
                  fit: ImageFit.Contain,
                  placeholderColor: Color.Transparent
                })
              } else {
                Text(this.activeMedia().title)
                  .fontSize(this.isShortLandscape() ? 21 : 26)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .textAlign(TextAlign.Start)
                  .maxLines(this.isShortLandscape() ? 1 : 2)
              }

              // 克制影院排版：年份 · 类型 · 数据源纯文字一行，评分与柔和「已入库」独立承托，去杂色彩虹胶囊。
              Column({ space: 6 }) {
                Text(
                  [
                    this.activeMedia().year,
                    this.activeMedia().type || '影视',
                    this.sourceDisplayLabel(this.activeMedia().source)
                  ].filter((part: string) => part.length > 0).join('  ·  ')
                )
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#D8FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Row({ space: 10 }) {
                  if (this.multiRatings.length > 0) {
                    HarmonyMultiRatingsRow({
                      badges: this.multiRatings,
                      forceLightText: true,
                      compact: this.isShortLandscape()
                    })
                  } else if (this.activeMedia().vote > 0) {
                    Text(`★ ${this.activeMedia().vote.toFixed(1)}`)
                      .fontSize(12.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFCC6B')
                  }
                  if (this.activeMedia().inLibrary) {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                        .fontSize(11)
                        .fontColor(['#5CE08A'])
                      Text('已入库')
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#5CE08A')
                    }
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(10)
                    .backgroundColor('#2E34C759')
                    .border({ width: 0.6, color: '#555CE08A', radius: 10 })
                  }
                }
              }
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(this.isShortLandscape() ? 14 : 20)
          }

          // 操作按钮（带清晰语义图标与静态 $r 符号重绘保障）
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
                if (this.isTvMedia(cur)) {
                  const sKeys = Object.keys(this.playableSeriesMap);
                  const sNums: number[] = [];
                  for (let i = 0; i < sKeys.length; i++) {
                    const sn = Number(sKeys[i]);
                    if (Number.isFinite(sn) && sn >= 0) { sNums.push(Math.round(sn)); }
                  }
                  sNums.sort((a: number, b: number) => {
                    if (a === 0 && b !== 0) { return 1; }
                    if (b === 0 && a !== 0) { return -1; }
                    return a - b;
                  });
                  if (sNums.length > 0) {
                    const firstSeason = sNums[0];
                    const pMap = this.playableSeriesMap[String(firstSeason)];
                    if (pMap) {
                      const eKeys = Object.keys(pMap);
                      const eNums: number[] = [];
                      for (let j = 0; j < eKeys.length; j++) {
                        const en = Number(eKeys[j]);
                        if (Number.isFinite(en) && en > 0) { eNums.push(Math.round(en)); }
                      }
                      eNums.sort((a: number, b: number) => a - b);
                      if (eNums.length > 0) {
                        const firstEp = eNums[0];
                        await this.playInlineEpisode(firstSeason, firstEp, `第 ${firstEp} 集`, cur.backdropUrl || cur.posterUrl);
                        return;
                      }
                    }
                  }
                }
                const streamTargetId = cur.serverItemId && cur.serverItemId.length > 0 ? cur.serverItemId : cur.id;
                try {
                  const manifest = await MoviePilotRepository.shared().fetchVideoStreamInfo(streamTargetId, cur.serverName);
                  if (manifest && manifest.contentUrl.length > 0) {
                    this.onPlayMedia(buildPlaybackRequestFromStreamInfo(
                      manifest,
                      cur.title,
                      cur.subtitle || cur.year,
                      { overrideArtworkUrl: cur.posterUrl || cur.backdropUrl }
                    ));
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
                  this.statusIsError = true;
                  this.statusMsg = '暂未获取到媒体服务器直连播放地址';
                }
              })
            }

            Row({ space: 10 }) {
              this.primarySubscribeButtonBuilder()

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
            Text(this.statusMsg)
              .fontSize(12)
              .fontColor(this.statusIsError ? '#E84855' : '#34C759')
              .padding({ left: 16, right: 16 })
              .width('100%')
          }

          if (this.loadingDetail) {
            HarmonyMediaDetailBodySkeleton({
              showSeasons: this.isTvMedia()
            })
          } else {
            // 剧情简介去玻璃外框裸排，提升正文呼吸感（默认 4 行 + 主题色展开/收起）
            Column({ space: 8 }) {
              Row() {
                Text('剧情简介')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .layoutWeight(1)
                if ((this.activeMedia().overview || '').length > 68) {
                  Text(this.overviewExpanded ? '收起' : '展开全部')
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
                .maxLines(this.overviewExpanded ? 99 : 4)
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
            .padding({ left: 18, right: 18, top: 2, bottom: 2 })

            // 剧集分季与横滑 16:9 分集卡片
            if (this.seasons.length > 0) {
              this.seasonsSectionBuilder()
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
        }
        .padding({ bottom: Math.max(48, this.safeBottomVp + 28) })
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
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(this.isShortLandscape() ? 18 : 20).fontColor([Color.White])
      }
      .width(this.isShortLandscape() ? 36 : 40)
      .height(this.isShortLandscape() ? 36 : 40)
      .backgroundColor(Color.Transparent)
      .attributeModifier(new HarmonySurfaceModifier(
        true,
        'pill',
        this.isShortLandscape() ? 18 : 20,
        this.accentHex,
        true,
        this.dynamicLight
      ))
      .accessibilityText('返回上一级')
      .position({ left: 16, top: Math.max(10, this.safeTopVp + 4) })
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
    this.detail = null;
    this.credits = [];
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
    return HarmonyAdaptiveLayout.posterGridTemplate(this.windowWidthVp);
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
              Column({ space: 6 }) {
                Text(this.detail ? this.detail.name : this.person.name)
                  .fontSize(20).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                if (this.loading && !this.detail) {
                  HarmonySkeletonHost({ loadingLabel: '正在加载演职员资料' }) {
                    Column({ space: 6 }) {
                      HarmonySkeletonBlock({ blockWidth: 64, blockHeight: 20, cornerRadius: 10, tone: 'subtle' })
                      HarmonySkeletonBlock({ blockWidth: 148, blockHeight: 12, cornerRadius: 4, tone: 'subtle' })
                    }
                    .alignItems(HorizontalAlign.Start)
                  }
                } else {
                  if (this.detail && this.detail.department.length > 0) {
                    NativeAdaptiveBadge({ text: this.detail.department, tintHex: this.accentHex })
                  }
                  if (this.detail && (this.detail.birthday.length > 0 || this.detail.placeOfBirth.length > 0)) {
                    Text(`${this.detail.birthday}${this.detail.placeOfBirth ? ' · ' + this.detail.placeOfBirth : ''}`)
                      .fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(2)
                  }
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')
          }

          if (this.loading && !this.detail) {
            HarmonySkeletonHost({ loadingLabel: '正在加载人物简介' }) {
              CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
                Column({ space: 9 }) {
                  HarmonySkeletonBlock({ blockWidth: 76, blockHeight: 15, cornerRadius: 5 })
                  HarmonySkeletonBlock({ blockWidth: '100%', blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
                  HarmonySkeletonBlock({ blockWidth: '92%', blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
                  HarmonySkeletonBlock({ blockWidth: '64%', blockHeight: 13, cornerRadius: 4, tone: 'subtle' })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }
          } else if (this.detail && this.detail.biography.length > 0) {
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

          Text(this.loading ? '参演作品' : `参演作品 (${this.credits.length})`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .width('100%')

          if (this.loading) {
            HarmonyPosterGridSkeleton({
              horizontalPadding: 0,
              bottomPadding: 12
            })
          } else if (this.credits.length === 0) {
            Text('暂无参演作品记录')
              .fontSize(13)
              .fontColor(mpSecondaryText(this.isDark))
              .padding({ top: 12, bottom: 12 })
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

/**
 * 鸿蒙「季媒体与分集详情页」：
 * - 点击媒体详情页的任意分季后进入，展示该季海报、首播日期、集数、入库统计、简介及订阅/资源搜索操作；
 * - 完整列出该季每一集，显示每集的入库状态（已入库 / 未开播 / 未入库）并支持单集点击直放与同季连续播放队列。
 */
@Component
export struct HarmonyMediaSeasonDetailPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) dynamicLight: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;

  @Prop seriesItem: MpMediaItem = {
    id: '', mediaId: '', tmdbId: '', doubanId: '', title: '', enTitle: '', year: '', type: '电视剧',
    overview: '', vote: 0, posterUrl: '', backdropUrl: '', logoUrl: '', source: 'themoviedb',
    inLibrary: false, subtitle: '', percent: 0, serverName: '', playUrl: ''
  };
  @Prop initialSeason: MpSeasonInfo = {
    seasonNumber: 1, name: '第 1 季', episodeCount: 0, airDate: '', posterUrl: '', overview: ''
  };
  @Prop initialSeriesItemId: string = '';
  @Prop initialServer: string = '';

  @State private seasonInfo: MpSeasonInfo = {
    seasonNumber: 1, name: '第 1 季', episodeCount: 0, airDate: '', posterUrl: '', overview: ''
  };
  @State private episodes: MpTmdbEpisodeItem[] = [];
  @State private playableMap: Record<string, string> = {};
  @State private existingNums: number[] = [];
  @State private resolvedSeriesId: string = '';
  @State private resolvedServer: string = '';
  @State private isSubscribed: boolean = false;
  @State private mutatingSubscribe: boolean = false;
  @State private playingEpisodeNum: number = -1;
  @State private overviewExpanded: boolean = false;
  @State private loading: boolean = true;
  @State private statusMsg: string = '';
  @State private statusIsError: boolean = false;

  onBack: () => void = () => {};
  onSearchResource: (kw: string) => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  aboutToAppear(): void {
    this.seasonInfo = {
      seasonNumber: this.initialSeason.seasonNumber,
      name: this.initialSeason.name,
      episodeCount: this.initialSeason.episodeCount,
      airDate: this.initialSeason.airDate,
      posterUrl: this.initialSeason.posterUrl,
      overview: this.initialSeason.overview
    };
    this.resolvedSeriesId = this.initialSeriesItemId;
    this.resolvedServer = this.initialServer;
    this.loadSeasonAll();
  }

  private seasonDisplayTitle(): string {
    if (this.seasonInfo.name && this.seasonInfo.name.trim().length > 0) {
      return this.seasonInfo.name.trim();
    }
    return this.seasonInfo.seasonNumber === 0 ? '特别篇' : `第 ${this.seasonInfo.seasonNumber} 季`;
  }

  private async loadSeasonAll(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    const sNum = this.seasonInfo.seasonNumber;
    try {
      const preResults = await Promise.all([
        repo.fetchMediaStatus(this.seriesItem, sNum),
        repo.fetchMediaSeasonsForItem(this.seriesItem),
        repo.fetchRemoteExistingEpisodes(this.seriesItem, sNum)
      ]);
      const mediaSt = preResults[0];
      const allSeasons = preResults[1];
      const remoteMap = preResults[2];

      if (mediaSt.itemId.length > 0) {
        this.resolvedSeriesId = mediaSt.itemId;
      }
      if (mediaSt.server.length > 0) {
        this.resolvedServer = mediaSt.server;
      }
      this.isSubscribed = mediaSt.seasons.includes(sNum) || mediaSt.subscribed;

      const matchedSeason = allSeasons.find((s: MpSeasonInfo) => s.seasonNumber === sNum);
      if (matchedSeason) {
        this.seasonInfo = {
          seasonNumber: sNum,
          name: matchedSeason.name || this.seasonInfo.name,
          episodeCount: matchedSeason.episodeCount > 0 ? matchedSeason.episodeCount : this.seasonInfo.episodeCount,
          airDate: matchedSeason.airDate || this.seasonInfo.airDate,
          posterUrl: matchedSeason.posterUrl || this.seasonInfo.posterUrl,
          overview: matchedSeason.overview || this.seasonInfo.overview
        };
      }

      const epResults = await Promise.all([
        this.resolvedSeriesId.length > 0
          ? repo.fetchPlayableSeasonEpisodes(this.resolvedSeriesId, sNum, this.resolvedServer)
          : Promise.resolve({} as Record<string, string>),
        repo.fetchSeasonEpisodesSmart(this.seriesItem, sNum, this.resolvedSeriesId, this.resolvedServer)
      ]);
      this.playableMap = epResults[0];

      const mergedExist: number[] = [];
      const rArr = remoteMap[String(sNum)];
      if (rArr) {
        for (let i = 0; i < rArr.length; i++) {
          if (!mergedExist.includes(rArr[i])) {
            mergedExist.push(rArr[i]);
          }
        }
      }
      const pKeys = Object.keys(this.playableMap);
      for (let i = 0; i < pKeys.length; i++) {
        const n = Number(pKeys[i]);
        if (Number.isFinite(n) && n > 0 && !mergedExist.includes(Math.round(n))) {
          mergedExist.push(Math.round(n));
        }
      }
      mergedExist.sort((a: number, b: number) => a - b);
      this.existingNums = mergedExist;

      const loadedEps = epResults[1];
      if (loadedEps.length > 0) {
        this.episodes = loadedEps;
      } else {
        const maxExist = mergedExist.length > 0 ? mergedExist[mergedExist.length - 1] : 0;
        const maxTotal = Math.max(this.seasonInfo.episodeCount, maxExist);
        const fallbackList: MpTmdbEpisodeItem[] = [];
        for (let num = 1; num <= maxTotal; num++) {
          fallbackList.push({
            id: `fallback_${sNum}_${num}`,
            seasonNumber: sNum,
            episodeNumber: num,
            title: `第 ${num} 集`,
            overview: '',
            airDate: '',
            runtimeMinutes: 0,
            vote: 0,
            stillUrl: ''
          });
        }
        this.episodes = fallbackList;
      }
    } catch {
      // keep existing state
    }
    this.loading = false;
  }

  private firstPlayableEpisodeNum(): number {
    const keys = Object.keys(this.playableMap);
    const nums: number[] = [];
    for (let i = 0; i < keys.length; i++) {
      const n = Number(keys[i]);
      if (Number.isFinite(n) && n > 0) { nums.push(Math.round(n)); }
    }
    nums.sort((a: number, b: number) => a - b);
    return nums.length > 0 ? nums[0] : -1;
  }

  private isEpisodePlayable(epNum: number): boolean {
    const val = this.playableMap[String(epNum)] ?? '';
    return val.length > 0;
  }

  private isEpisodeInLib(epNum: number): boolean {
    return this.isEpisodePlayable(epNum) || this.existingNums.includes(epNum);
  }

  private isUpcomingAirDate(airDate: string): boolean {
    if (!airDate || airDate.length < 10) { return false; }
    const d = Date.parse(airDate.substring(0, 10));
    if (!Number.isFinite(d)) { return false; }
    return d > Date.now();
  }

  private async playEpisode(ep: MpTmdbEpisodeItem): Promise<void> {
    if (this.playingEpisodeNum !== -1) { return; }
    const targetId = this.playableMap[String(ep.episodeNumber)] ?? '';
    if (!targetId) { return; }
    this.playingEpisodeNum = ep.episodeNumber;
    this.statusMsg = '';

    const sNum = this.seasonInfo.seasonNumber;
    const keys = Object.keys(this.playableMap);
    const sortedNums: number[] = [];
    for (let i = 0; i < keys.length; i++) {
      const n = Number(keys[i]);
      if (Number.isFinite(n) && n > 0) { sortedNums.push(Math.round(n)); }
    }
    sortedNums.sort((a: number, b: number) => a - b);

    const queue: HarmonyQueueItem[] = [];
    let qIdx = 0;
    for (let i = 0; i < sortedNums.length; i++) {
      const num = sortedNums[i];
      const qid = this.playableMap[String(num)] ?? '';
      if (!qid) { continue; }
      if (num === ep.episodeNumber) { qIdx = queue.length; }
      const hit = this.episodes.find((e: MpTmdbEpisodeItem) => e.episodeNumber === num);
      const code = `S${String(sNum).padStart(2, '0')}E${String(num).padStart(2, '0')}`;
      queue.push({
        itemId: qid,
        title: hit ? `${this.seriesItem.title} · ${code} · ${hit.title}` : `${this.seriesItem.title} · ${code}`,
        subtitle: this.resolvedServer,
        server: this.resolvedServer,
        artworkUrl: (hit && hit.stillUrl.length > 0) ? hit.stillUrl : (this.seasonInfo.posterUrl || this.seriesItem.posterUrl),
        trackNumber: num
      });
    }

    try {
      const manifest = await MoviePilotRepository.shared().fetchVideoStreamInfo(targetId, this.resolvedServer);
      if (manifest && manifest.contentUrl.length > 0) {
        const code = `S${String(sNum).padStart(2, '0')}E${String(ep.episodeNumber).padStart(2, '0')}`;
        this.onPlayMedia(buildPlaybackRequestFromStreamInfo(
          manifest,
          `${this.seriesItem.title} · ${code} · ${ep.title}`,
          this.resolvedServer || this.seasonDisplayTitle(),
          {
            queue: queue.length > 1 ? queue : undefined,
            queueIndex: queue.length > 1 ? qIdx : undefined,
            overrideArtworkUrl: ep.stillUrl || this.seasonInfo.posterUrl || this.seriesItem.posterUrl
          }
        ));
      } else {
        this.statusIsError = true;
        this.statusMsg = '无法获取该集的媒体流地址';
      }
    } catch {
      this.statusIsError = true;
      this.statusMsg = '读取播放流失败，请稍后重试';
    }
    this.playingEpisodeNum = -1;
  }

  private async toggleSeasonSubscribe(): Promise<void> {
    if (this.mutatingSubscribe) { return; }
    const sNum = this.seasonInfo.seasonNumber;
    if (this.isSubscribed) {
      this.getUIContext().showAlertDialog({
        title: '取消订阅',
        message: `确认取消《${this.seriesItem.title}》${this.seasonDisplayTitle()}的订阅吗？`,
        autoCancel: true,
        primaryButton: { value: '保留', action: () => {} },
        secondaryButton: {
          value: '取消订阅',
          fontColor: '#E84855',
          action: async () => {
            this.mutatingSubscribe = true;
            const ok = await MoviePilotRepository.shared().deleteMediaSubscribe(this.seriesItem, sNum);
            this.mutatingSubscribe = false;
            if (ok) {
              this.isSubscribed = false;
              this.statusIsError = false;
              this.statusMsg = `已取消${this.seasonDisplayTitle()}订阅`;
            } else {
              this.statusIsError = true;
              this.statusMsg = '取消订阅失败，请稍后重试';
            }
          }
        }
      });
      return;
    }

    this.mutatingSubscribe = true;
    const res = await MoviePilotRepository.shared().addSubscribeWithMessage(this.seriesItem, sNum);
    this.mutatingSubscribe = false;
    if (res.ok) {
      this.isSubscribed = true;
      this.statusIsError = false;
      this.statusMsg = res.message || `已订阅${this.seasonDisplayTitle()}`;
    } else {
      this.statusIsError = true;
      this.statusMsg = res.message || '订阅添加失败';
    }
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: `${this.seriesItem.title} · ${this.seasonDisplayTitle()}`,
        trailingSymbol: 'sys.symbol.arrow_clockwise',
        trailingAccessibility: '刷新本季信息',
        onBack: () => this.onBack(),
        onTrailingClick: () => { this.loadSeasonAll(); }
      })

      Scroll() {
        Column({ space: 14 }) {
          // 1. 本季媒体信息头卡
          CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
            Row({ space: 14 }) {
              if ((this.seasonInfo.posterUrl || this.seriesItem.posterUrl).length > 0) {
                MpRemoteImage({
                  src: this.seasonInfo.posterUrl || this.seriesItem.posterUrl,
                  imgWidth: 92,
                  imgHeight: 138,
                  imgRadius: 12,
                  placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                })
              } else {
                Column()
                  .width(92)
                  .height(138)
                  .borderRadius(12)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              }

              Column({ space: 7 }) {
                Text(this.seriesItem.title)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(mpSecondaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Text(this.seasonDisplayTitle())
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Row({ space: 8 }) {
                  if (this.seasonInfo.airDate.length > 0) {
                    Text(this.seasonInfo.airDate)
                      .fontSize(12)
                      .fontColor(mpSecondaryText(this.isDark))
                  }
                  if (Math.max(this.seasonInfo.episodeCount, this.episodes.length) > 0) {
                    Text(`共 ${Math.max(this.seasonInfo.episodeCount, this.episodes.length)} 集`)
                      .fontSize(12)
                      .fontColor(mpSecondaryText(this.isDark))
                  }
                  if (this.seriesItem.vote > 0) {
                    Text(`★ ${this.seriesItem.vote.toFixed(1)}`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#F2B830')
                  }
                }
                .width('100%')

                if (this.existingNums.length > 0) {
                  NativeAdaptiveBadge({
                    text: (Math.max(this.seasonInfo.episodeCount, this.episodes.length) > this.existingNums.length)
                      ? `部分入库 ${this.existingNums.length}/${Math.max(this.seasonInfo.episodeCount, this.episodes.length)} 集${this.resolvedServer ? ' · ' + this.resolvedServer : ''}`
                      : `已入库 ${this.existingNums.length}/${Math.max(this.seasonInfo.episodeCount, this.episodes.length)} 集${this.resolvedServer ? ' · ' + this.resolvedServer : ''}`,
                    tintHex: (Math.max(this.seasonInfo.episodeCount, this.episodes.length) > this.existingNums.length)
                      ? '#F29B38'
                      : '#34C759'
                  })
                } else if (!this.loading) {
                  NativeAdaptiveBadge({ text: '未入库', tintHex: '#8E8E93' })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
          }

          // 2. 本季操作栏
          Column({ space: 10 }) {
            if (this.firstPlayableEpisodeNum() > 0) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([Color.White])
                  Text(
                    this.playingEpisodeNum === this.firstPlayableEpisodeNum()
                      ? '准备播放…'
                      : `播放第 ${this.firstPlayableEpisodeNum()} 集${this.resolvedServer ? ' · ' + this.resolvedServer : ''}`
                  )
                    .fontSize(14.5)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .maxLines(1)
                }
              }
              .width('100%')
              .height(46)
              .borderRadius(23)
              .backgroundColor(this.accentHex)
              .onClick(() => {
                const fn = this.firstPlayableEpisodeNum();
                const hit = this.episodes.find((e: MpTmdbEpisodeItem) => e.episodeNumber === fn);
                if (hit) {
                  this.playEpisode(hit);
                }
              })
            }

            Row({ space: 10 }) {
              Button() {
                Row({ space: 6 }) {
                  if (this.isSubscribed) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(15)
                      .fontColor([Color.White])
                  } else {
                    SymbolGlyph($r('sys.symbol.bookmark_fill'))
                      .fontSize(15)
                      .fontColor([Color.White])
                  }
                  Text(this.mutatingSubscribe ? '处理中…' : (this.isSubscribed ? '本季已订阅' : '订阅本季'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                }
              }
              .layoutWeight(1)
              .height(44)
              .borderRadius(22)
              .backgroundColor(this.isSubscribed ? '#34C759' : this.accentHex)
              .onClick(() => { this.toggleSeasonSubscribe(); })

              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.magnifyingglass'))
                    .fontSize(15)
                    .fontColor([mpPrimaryText(this.isDark)])
                  Text('搜索本季')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(mpPrimaryText(this.isDark))
                }
              }
              .layoutWeight(1)
              .height(44)
              .borderRadius(22)
              .backgroundColor(Color.Transparent)
              .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 22, this.accentHex, true, this.dynamicLight))
              .onClick(() => {
                this.onSearchResource(`${this.seriesItem.title} S${String(this.seasonInfo.seasonNumber).padStart(2, '0')}`);
              })
            }
            .width('100%')
          }
          .width('100%')

          if (this.statusMsg.length > 0) {
            Text(this.statusMsg)
              .fontSize(12)
              .fontColor(this.statusIsError ? '#E84855' : '#34C759')
              .width('100%')
          }

          // 3. 本季简介
          if ((this.seasonInfo.overview || this.seriesItem.overview).length > 0) {
            CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
              Column({ space: 8 }) {
                Row() {
                  Text('本季简介')
                    .fontSize(15.5)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                    .layoutWeight(1)
                  if ((this.seasonInfo.overview || this.seriesItem.overview).length > 72) {
                    Text(this.overviewExpanded ? '收起 ▴' : '展开 ▾')
                      .fontSize(12)
                      .fontColor(this.accentHex)
                      .onClick(() => { this.overviewExpanded = !this.overviewExpanded; })
                  }
                }
                .width('100%')

                Text(this.seasonInfo.overview || this.seriesItem.overview)
                  .fontSize(13.5)
                  .fontColor(mpSecondaryText(this.isDark))
                  .lineHeight(21)
                  .maxLines(this.overviewExpanded ? 99 : 4)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }
          }

          // 4. 本季分集列表
          Row() {
            Text('本季剧集')
              .fontSize(17.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))
              .layoutWeight(1)
            if (this.episodes.length > 0) {
              Text(
                this.existingNums.length > 0
                  ? `已入库 ${this.existingNums.length} / 共 ${this.episodes.length} 集`
                  : `共 ${this.episodes.length} 集`
              )
                .fontSize(12)
                .fontColor(mpSecondaryText(this.isDark))
            }
          }
          .width('100%')

          if (this.loading && this.episodes.length === 0) {
            HarmonyPosterRowCardGridSkeleton({
              variant: 'subscribe',
              fillViewport: false,
              bottomPadding: 16
            })
          } else if (this.episodes.length === 0) {
            CinematicPanel({ panelPadding: 22, cornerRadius: 18 }) {
              Column({ space: 6 }) {
                Text('暂无本季分集明细')
                  .fontSize(14.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                Text('数据源尚未提供该季的分集列表。')
                  .fontSize(12.5)
                  .fontColor(mpSecondaryText(this.isDark))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            }
          } else {
            Grid() {
              ForEach(this.episodes, (ep: MpTmdbEpisodeItem) => {
                GridItem() {
                  Column() {
                    CinematicPanel({
                      panelPadding: 12,
                      cornerRadius: 16,
                      interactive: this.isEpisodePlayable(ep.episodeNumber)
                    }) {
                      Column({ space: 9 }) {
                        Row({ space: 12 }) {
                          Stack({ alignContent: Alignment.Center }) {
                            MpRemoteImage({
                              src: ep.stillUrl || this.seriesItem.backdropUrl || this.seasonInfo.posterUrl || this.seriesItem.posterUrl,
                              imgWidth: 132,
                              imgHeight: 74,
                              imgRadius: 10,
                              placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                            })

                            Text(`E${String(ep.episodeNumber).padStart(2, '0')}`)
                              .fontSize(10)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(Color.White)
                              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                              .borderRadius(7)
                              .backgroundColor('#B010141E')
                              .position({ left: 6, top: 6 })

                            if (this.isEpisodePlayable(ep.episodeNumber)) {
                              Column() {
                                SymbolGlyph($r('sys.symbol.play_fill'))
                                  .fontSize(14)
                                  .fontColor([Color.White])
                              }
                              .width(30)
                              .height(30)
                              .borderRadius(15)
                              .justifyContent(FlexAlign.Center)
                              .backgroundColor('#78000000')
                            }
                          }
                          .width(132)
                          .height(74)
                          .onClick(() => {
                            if (this.isEpisodePlayable(ep.episodeNumber)) {
                              this.playEpisode(ep);
                            }
                          })

                          Column({ space: 5 }) {
                            Row({ space: 6 }) {
                              Text(`${ep.episodeNumber}. ${ep.title}`)
                                .fontSize(14.5)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(mpPrimaryText(this.isDark))
                                .maxLines(2)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                .layoutWeight(1)

                              if (this.isEpisodeInLib(ep.episodeNumber)) {
                                NativeAdaptiveBadge({ text: '已入库', tintHex: '#34C759' })
                              } else if (this.isUpcomingAirDate(ep.airDate)) {
                                NativeAdaptiveBadge({ text: '未开播', tintHex: '#64A2FF' })
                              } else {
                                NativeAdaptiveBadge({ text: '未入库', tintHex: '#8E8E93' })
                              }
                            }
                            .width('100%')

                            Row({ space: 8 }) {
                              if (ep.airDate.length > 0) {
                                Text(ep.airDate)
                                  .fontSize(11.5)
                                  .fontColor(mpSecondaryText(this.isDark))
                              }
                              if (ep.runtimeMinutes > 0) {
                                Text(`${ep.runtimeMinutes} 分钟`)
                                  .fontSize(11.5)
                                  .fontColor(mpSecondaryText(this.isDark))
                              }
                              if (ep.vote > 0) {
                                Text(`★ ${ep.vote.toFixed(1)}`)
                                  .fontSize(11.5)
                                  .fontWeight(FontWeight.Medium)
                                  .fontColor('#F2B830')
                              }
                            }
                            .width('100%')

                            if (ep.overview.length > 0) {
                              Text(ep.overview)
                                .fontSize(12)
                                .fontColor(mpSecondaryText(this.isDark))
                                .lineHeight(17)
                                .maxLines(3)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                .width('100%')
                            }
                          }
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)
                        }
                        .width('100%')

                        Row({ space: 8 }) {
                          if (this.isEpisodePlayable(ep.episodeNumber)) {
                            Row({ space: 5 }) {
                              SymbolGlyph($r('sys.symbol.play_fill'))
                                .fontSize(12)
                                .fontColor([Color.White])
                              Text(this.playingEpisodeNum === ep.episodeNumber ? '准备播放…' : '播放本集')
                                .fontSize(12)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(Color.White)
                            }
                            .padding({ left: 12, right: 13, top: 6, bottom: 6 })
                            .borderRadius(15)
                            .backgroundColor(this.accentHex)
                            .onClick(() => { this.playEpisode(ep); })
                          } else {
                            Row({ space: 5 }) {
                              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                                .fontSize(12)
                                .fontColor([mpPrimaryText(this.isDark)])
                              Text('搜本集')
                                .fontSize(12)
                                .fontWeight(FontWeight.Medium)
                                .fontColor(mpPrimaryText(this.isDark))
                            }
                            .padding({ left: 11, right: 12, top: 6, bottom: 6 })
                            .borderRadius(15)
                            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                            .onClick(() => {
                              const code = `S${String(this.seasonInfo.seasonNumber).padStart(2, '0')}E${String(ep.episodeNumber).padStart(2, '0')}`;
                              this.onSearchResource(`${this.seriesItem.title} ${code}`);
                            })
                          }
                          Blank().layoutWeight(1)
                        }
                        .width('100%')
                      }
                      .width('100%')
                    }
                  }
                  .width('100%')
                }
              }, (ep: MpTmdbEpisodeItem) => `season_ep_${ep.seasonNumber}_${ep.episodeNumber}_${this.isEpisodeInLib(ep.episodeNumber)}`)
            }
            .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
            .columnsGap(12)
            .rowsGap(12)
            .width('100%')
          }
        }
        .padding({ left: 16, right: 16, top: 4, bottom: Math.max(40, this.safeBottomVp + 24) })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
