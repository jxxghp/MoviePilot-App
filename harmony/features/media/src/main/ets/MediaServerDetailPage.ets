import { common, Want } from '@kit.AbilityKit';
import {
  MoviePilotRepository,
  MpMediaItem,
  MpCastMember,
  MpMediaServerDetail,
  MpMediaServerEpisode,
  MpMediaServerPerson,
  MpMediaServerSource,
  MpMediaServerStream,
  MpRemoteImage,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeTopStatusBarBlur,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonySurfaceModifier,
  HarmonyThemeColors,
  HarmonyEntityLogo,
  HarmonySkeletonHost,
  HarmonyEpisodeStripSkeleton,
  HarmonyMediaDetailBodySkeleton,
  mpPrimaryText,
  mpSecondaryText,
  mpMutedText
} from '@moviepilot/design_system';
import { HarmonyPlaybackRequest } from '@moviepilot/media_player';

interface ExternalLinkChipItem {
  id: string;
  label: string;
  url: string;
}

interface StreamFieldRow {
  label: string;
  value: string;
}

function formatRuntimeMinutes(durationMs: number): string {
  if (!Number.isFinite(durationMs) || durationMs <= 0) { return ''; }
  const mins = Math.max(1, Math.round(durationMs / 60000));
  if (mins >= 60) {
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return m > 0 ? `${h} 小时 ${m} 分钟` : `${h} 小时`;
  }
  return `${mins} 分钟`;
}

/**
 * 鸿蒙媒体服务器（Emby / Jellyfin / Plex / 飞牛 / 绿联 / 极空间）专属详情页：
 * - 响应式沉浸主视觉、媒体服务器品牌标识、一键直连/断点续播与多版本切换；
 * - 剧集采用 16:9 横版剧照卡片横向滚动（优先单集 `thumb`），支持切换分季与点击播放；
 * - 完整呈现「类似作品」（2:3 海报 + 右下角暗色半透明评分角标）、「链接」（豆瓣 / IMDb / TheMovieDb / Trakt 胶囊跳系统浏览器）及「媒体信息」（视频 / 音频 / 字幕纵向参数卡片横滑）。
 */
@Component
export struct HarmonyMediaServerDetailPage {
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
    overview: '', vote: 0, posterUrl: '', backdropUrl: '', logoUrl: '', source: 'mediaserver',
    inLibrary: true, subtitle: '', percent: 0, serverName: '', playUrl: '', serverItemId: ''
  };

  @State private loading: boolean = true;
  @State private detail: MpMediaServerDetail | null = null;
  @State private seasons: MpMediaServerEpisode[] = [];
  @State private activeSeasonIdx: number = 0;
  @State private episodes: MpMediaServerEpisode[] = [];
  @State private loadingEpisodes: boolean = false;
  @State private selectedEpisodeId: string = '';
  @State private fallbackEpisodeSources: MpMediaServerSource[] = [];
  @State private selectedSourceIdx: number = 0;
  @State private similarItems: MpMediaItem[] = [];
  @State private overviewExpanded: boolean = false;
  @State private scrollOffsetY: number = 0;

  // V3 订阅联动状态
  @State private subscribed: boolean = false;
  @State private subscribedSeasons: number[] = [];
  @State private mutatingSubscribe: boolean = false;
  @State private statusMsg: string = '';
  @State private statusIsError: boolean = false;
  private userMutatedSubscribe: boolean = false;
  private loadSeq: number = 0;
  private scroller: Scroller = new Scroller();

  onBack: () => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};
  onOpenPerson: (person: MpCastMember) => void = () => {};
  onSearchResource: (kw: string) => void = () => {};

  aboutToAppear(): void {
    this.loadAll();
  }

  onItemChanged(): void {
    this.detail = null;
    this.seasons = [];
    this.activeSeasonIdx = 0;
    this.episodes = [];
    this.selectedEpisodeId = '';
    this.fallbackEpisodeSources = [];
    this.selectedSourceIdx = 0;
    this.similarItems = [];
    this.overviewExpanded = false;
    this.subscribed = false;
    this.subscribedSeasons = [];
    this.mutatingSubscribe = false;
    this.userMutatedSubscribe = false;
    this.statusMsg = '';
    this.statusIsError = false;
    this.loadAll();
  }

  private targetItemId(): string {
    if (this.item.serverItemId && this.item.serverItemId.length > 0) {
      return this.item.serverItemId;
    }
    return this.item.id;
  }

  private targetServer(): string {
    return this.detail ? this.detail.server : this.item.serverName;
  }

  private isShortLandscape(): boolean {
    return HarmonyAdaptiveLayout.isShortLandscape(this.windowWidthVp, this.windowHeightVp);
  }

  private heroHeightVp(): number {
    return HarmonyAdaptiveLayout.detailHeroHeightVp(this.windowWidthVp, this.windowHeightVp);
  }

  private showToastSafe(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 1800 });
    } catch {
      // ignore toast error
    }
  }

  private isSeriesOrSeason(d: MpMediaServerDetail | null): boolean {
    if (!d) {
      return this.item.type === '电视剧';
    }
    const it = d.itemType.toLowerCase();
    return it === 'series' || it === 'season' || d.mediaType === '电视剧';
  }

  private buildSubscribeProxyItem(d: MpMediaServerDetail | null): MpMediaItem {
    if (!d) { return this.item; }
    const isTv = this.isSeriesOrSeason(d) || d.itemType.toLowerCase() === 'episode';
    let mediaId = '';
    let src = 'themoviedb';
    if (d.tmdbId.length > 0) {
      mediaId = `tmdb:${d.tmdbId}`;
      src = 'themoviedb';
    } else if (d.doubanId.length > 0) {
      mediaId = `douban:${d.doubanId}`;
      src = 'douban';
    } else if (d.mediaSource.length > 0 && d.mediaId.length > 0) {
      mediaId = `${d.mediaSource}:${d.mediaId}`;
      src = d.mediaSource;
    }
    return {
      id: d.itemId,
      mediaId: mediaId || this.item.mediaId,
      tmdbId: d.tmdbId || this.item.tmdbId,
      doubanId: d.doubanId || this.item.doubanId,
      title: d.seriesName.length > 0 && d.itemType.toLowerCase() === 'episode' ? d.seriesName : d.title,
      enTitle: d.originalTitle,
      year: d.year || this.item.year,
      type: isTv ? '电视剧' : (d.mediaType || this.item.type || '电影'),
      overview: d.overview,
      vote: d.rating,
      posterUrl: d.posterUrl || this.item.posterUrl,
      backdropUrl: d.backdropUrl || this.item.backdropUrl,
      logoUrl: this.item.logoUrl,
      source: src,
      inLibrary: true,
      subtitle: d.subtitle,
      percent: Math.round(d.playedPercentage),
      serverName: d.server,
      playUrl: d.playUrl,
      serverItemId: d.itemId,
      imdbId: d.imdbId,
      tvdbId: d.tvdbId
    };
  }

  private currentSeasonNumber(): number | undefined {
    if (this.seasons.length > 0 && this.activeSeasonIdx < this.seasons.length) {
      const sn = this.seasons[this.activeSeasonIdx].seasonNumber;
      if (sn >= 0) { return sn; }
    }
    if (this.detail && this.detail.seasonNumber >= 0) {
      return this.detail.seasonNumber;
    }
    return this.isSeriesOrSeason(this.detail) ? 1 : undefined;
  }

  private isPrimarySubscribed(): boolean {
    const sn = this.currentSeasonNumber();
    if (sn !== undefined && this.seasons.length > 0) {
      return this.subscribedSeasons.includes(sn) || (this.subscribed && this.subscribedSeasons.length === 0);
    }
    return this.subscribed || this.subscribedSeasons.length > 0;
  }

  private async loadAll(): Promise<void> {
    const seq = ++this.loadSeq;
    const itemId = this.targetItemId();
    if (!itemId) {
      this.loading = false;
      return;
    }
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      let fetched = await repo.fetchMediaServerDetail(itemId, this.item.serverName);
      if (seq !== this.loadSeq) { return; }
      if (!fetched) {
        this.loading = false;
        return;
      }
      this.detail = fetched;
      this.loading = false;

      // 1. 若为剧集或季，拉取季与分集卡片，并自动预取首集音视频轨道以展示「媒体信息」
      const lowerType = fetched.itemType.toLowerCase();
      if (lowerType === 'series') {
        const loadedSeasons = await repo.fetchMediaServerSeasons(fetched.itemId, fetched.server);
        if (seq !== this.loadSeq) { return; }
        this.seasons = loadedSeasons;
        if (loadedSeasons.length > 0) {
          let defaultIdx = loadedSeasons.findIndex((s: MpMediaServerEpisode) => s.seasonNumber > 0);
          if (defaultIdx < 0) { defaultIdx = 0; }
          this.activeSeasonIdx = defaultIdx;
          const firstSeason = loadedSeasons[defaultIdx];
          await this.loadSeasonEpisodes(
            fetched.itemId,
            fetched.server,
            firstSeason.itemId,
            firstSeason.seasonNumber >= 0 ? firstSeason.seasonNumber : undefined,
            seq
          );
        } else {
          await this.loadSeasonEpisodes(fetched.itemId, fetched.server, '', 1, seq);
        }
      } else if (lowerType === 'season') {
        const seriesKey = fetched.seriesId || fetched.parentId || fetched.itemId;
        await this.loadSeasonEpisodes(
          seriesKey,
          fetched.server,
          fetched.itemId,
          fetched.seasonNumber >= 0 ? fetched.seasonNumber : undefined,
          seq
        );
      }

      // 2. 补全外部 ID（doubanId / imdbId / tmdbId）后并发查询订阅状态与类似作品
      fetched = await repo.enrichMediaServerExternalIds(fetched);
      if (seq !== this.loadSeq) { return; }
      this.detail = {
        itemId: fetched.itemId,
        server: fetched.server,
        serverType: fetched.serverType,
        itemType: fetched.itemType,
        mediaType: fetched.mediaType,
        title: fetched.title,
        originalTitle: fetched.originalTitle,
        subtitle: fetched.subtitle,
        tagline: fetched.tagline,
        overview: fetched.overview,
        year: fetched.year,
        premiereDate: fetched.premiereDate,
        rating: fetched.rating,
        officialRating: fetched.officialRating,
        durationMs: fetched.durationMs,
        posterUrl: fetched.posterUrl,
        backdropUrl: fetched.backdropUrl,
        thumbUrl: fetched.thumbUrl,
        genres: fetched.genres,
        studios: fetched.studios,
        people: fetched.people,
        mediaSource: fetched.mediaSource,
        mediaId: fetched.mediaId,
        imdbId: fetched.imdbId,
        tmdbId: fetched.tmdbId,
        tvdbId: fetched.tvdbId,
        doubanId: fetched.doubanId,
        parentId: fetched.parentId,
        seriesId: fetched.seriesId,
        seriesName: fetched.seriesName,
        seasonId: fetched.seasonId,
        seasonName: fetched.seasonName,
        seasonNumber: fetched.seasonNumber,
        episodeNumber: fetched.episodeNumber,
        seasonCount: fetched.seasonCount,
        episodeCount: fetched.episodeCount,
        played: fetched.played,
        playedPercentage: fetched.playedPercentage,
        resumePositionMs: fetched.resumePositionMs,
        mediaSources: fetched.mediaSources,
        playUrl: fetched.playUrl,
        canPlay: fetched.canPlay
      };

      const subProxy = this.buildSubscribeProxyItem(this.detail);
      const tailRes = await Promise.all([
        repo.fetchMediaStatus(subProxy),
        repo.fetchMediaServerSimilar(this.detail)
      ]);
      if (seq !== this.loadSeq) { return; }
      if (!this.userMutatedSubscribe) {
        this.subscribed = tailRes[0].subscribed || tailRes[0].seasons.length > 0;
        this.subscribedSeasons = tailRes[0].seasons;
      }
      this.similarItems = tailRes[1];
    } catch {
      this.loading = false;
    }
  }

  private async loadSeasonEpisodes(
    seriesId: string,
    server: string,
    seasonId: string,
    seasonNum: number | undefined,
    expectedSeq: number
  ): Promise<void> {
    this.loadingEpisodes = true;
    try {
      const eps = await MoviePilotRepository.shared().fetchMediaServerSeasonEpisodes(
        seriesId,
        server,
        seasonId,
        seasonNum
      );
      if (expectedSeq !== this.loadSeq) { return; }
      this.episodes = eps;
      if (eps.length > 0) {
        const preferredEp = eps.find((e: MpMediaServerEpisode) => !e.played) ?? eps[0];
        this.selectedEpisodeId = preferredEp.itemId;
        if (!this.detail || this.detail.mediaSources.length === 0) {
          this.loadEpisodeStreamPreview(preferredEp.itemId, server, expectedSeq);
        }
      }
    } catch {
      this.episodes = [];
    }
    this.loadingEpisodes = false;
  }

  private async loadEpisodeStreamPreview(epItemId: string, server: string, expectedSeq: number): Promise<void> {
    if (!epItemId) { return; }
    try {
      const epDetail = await MoviePilotRepository.shared().fetchMediaServerDetail(epItemId, server);
      if (expectedSeq !== this.loadSeq) { return; }
      if (epDetail && epDetail.mediaSources.length > 0) {
        this.fallbackEpisodeSources = epDetail.mediaSources;
        this.selectedSourceIdx = 0;
      }
    } catch {
      // ignore episode stream preview failure
    }
  }

  private activeMediaSources(): MpMediaServerSource[] {
    if (this.detail && this.detail.mediaSources.length > 0) {
      return this.detail.mediaSources;
    }
    return this.fallbackEpisodeSources;
  }

  private activeSource(): MpMediaServerSource | null {
    const list = this.activeMediaSources();
    if (list.length === 0) { return null; }
    const idx = Math.min(Math.max(0, this.selectedSourceIdx), list.length - 1);
    return list[idx];
  }

  private async playTargetItem(overrideItemId?: string, overrideTitle?: string, overrideSubtitle?: string): Promise<void> {
    const srv = this.targetServer();
    let playId = overrideItemId ?? '';
    let playTitle = overrideTitle ?? (this.detail ? this.detail.title : this.item.title);
    let playSub = overrideSubtitle ?? (this.detail ? (this.detail.year || this.detail.server) : this.item.year);

    if (!playId) {
      if (this.detail && this.isSeriesOrSeason(this.detail) && this.episodes.length > 0) {
        const chosen = this.episodes.find((e: MpMediaServerEpisode) => e.itemId === this.selectedEpisodeId)
          ?? this.episodes.find((e: MpMediaServerEpisode) => !e.played)
          ?? this.episodes[0];
        playId = chosen.itemId;
        playTitle = `${this.detail.title} · E${String(chosen.episodeNumber).padStart(2, '0')} ${chosen.title}`;
      } else {
        playId = this.targetItemId();
      }
    }
    if (!playId) { return; }

    const src = this.activeSource();
    const mediaSourceId = (!overrideItemId && src) ? src.id : '';

    try {
      const streamInfo = await MoviePilotRepository.shared().fetchVideoStreamInfo(playId, srv, mediaSourceId);
      if (streamInfo && streamInfo.contentUrl.length > 0) {
        this.onPlayMedia({
          url: streamInfo.contentUrl,
          title: streamInfo.title || playTitle,
          subtitle: playSub,
          isAudio: streamInfo.mediaType === 'audio'
        });
        return;
      }
    } catch {
      // fallback below
    }
    const fallbackPlayUrl = this.detail ? this.detail.playUrl : this.item.playUrl;
    if (fallbackPlayUrl.length > 0) {
      this.onPlayMedia({
        url: fallbackPlayUrl,
        title: playTitle,
        subtitle: playSub,
        isAudio: false
      });
    } else {
      this.statusIsError = true;
      this.statusMsg = '当前条目暂无法获取直连媒体流地址';
      this.showToastSafe(this.statusMsg);
    }
  }

  private async handleToggleSubscribe(): Promise<void> {
    if (this.mutatingSubscribe) { return; }
    const proxy = this.buildSubscribeProxyItem(this.detail);
    const sn = this.currentSeasonNumber();

    if (this.isPrimarySubscribed()) {
      this.getUIContext().showAlertDialog({
        title: '取消订阅',
        message: `确定要取消订阅「${proxy.title}${sn !== undefined && this.seasons.length > 0 ? ' · 第 ' + sn + ' 季' : ''}」吗？`,
        autoCancel: true,
        primaryButton: { value: '保留订阅', action: () => {} },
        secondaryButton: {
          value: '取消订阅',
          fontColor: '#E84855',
          action: async () => {
            this.mutatingSubscribe = true;
            this.userMutatedSubscribe = true;
            const ok = await MoviePilotRepository.shared().deleteMediaSubscribe(proxy, sn);
            this.mutatingSubscribe = false;
            if (ok) {
              if (sn !== undefined) {
                this.subscribedSeasons = this.subscribedSeasons.filter((x: number) => x !== sn);
                this.subscribed = this.subscribedSeasons.length > 0;
              } else {
                this.subscribed = false;
                this.subscribedSeasons = [];
              }
              this.statusIsError = false;
              this.statusMsg = '已取消订阅';
              this.showToastSafe(this.statusMsg);
            } else {
              this.statusIsError = true;
              this.statusMsg = '取消订阅失败';
            }
          }
        }
      });
      return;
    }

    this.mutatingSubscribe = true;
    this.userMutatedSubscribe = true;
    const res = await MoviePilotRepository.shared().addSubscribeWithMessage(proxy, sn);
    this.mutatingSubscribe = false;
    if (res.ok) {
      this.subscribed = true;
      if (sn !== undefined && !this.subscribedSeasons.includes(sn)) {
        const next = [...this.subscribedSeasons, sn];
        next.sort((a: number, b: number) => a - b);
        this.subscribedSeasons = next;
      }
      this.statusIsError = false;
      this.statusMsg = res.message || '已添加至订阅队列';
      this.showToastSafe(this.statusMsg);
    } else {
      this.statusIsError = true;
      this.statusMsg = res.message || '添加订阅失败';
      this.showToastSafe(this.statusMsg);
    }
  }

  private externalLinks(): ExternalLinkChipItem[] {
    const d = this.detail;
    if (!d) { return []; }
    const isTv = this.isSeriesOrSeason(d) || d.itemType.toLowerCase() === 'episode';
    const links: ExternalLinkChipItem[] = [];
    if (d.doubanId.length > 0) {
      links.push({
        id: 'douban',
        label: '豆瓣',
        url: `https://movie.douban.com/subject/${encodeURIComponent(d.doubanId)}/`
      });
    }
    if (d.imdbId.length > 0) {
      links.push({
        id: 'imdb',
        label: 'IMDb',
        url: `https://www.imdb.com/title/${encodeURIComponent(d.imdbId)}/`
      });
    }
    if (d.tmdbId.length > 0) {
      links.push({
        id: 'tmdb',
        label: 'TheMovieDb',
        url: `https://www.themoviedb.org/${isTv ? 'tv' : 'movie'}/${encodeURIComponent(d.tmdbId)}`
      });
    }
    if (d.imdbId.length > 0) {
      links.push({
        id: 'trakt',
        label: 'Trakt',
        url: `https://trakt.tv/${isTv ? 'shows' : 'movies'}/${encodeURIComponent(d.imdbId)}`
      });
    } else if (d.tmdbId.length > 0) {
      links.push({
        id: 'trakt',
        label: 'Trakt',
        url: `https://trakt.tv/search/tmdb/${encodeURIComponent(d.tmdbId)}?id_type=${isTv ? 'show' : 'movie'}`
      });
    }
    if (d.tvdbId.length > 0 && isTv) {
      links.push({
        id: 'tvdb',
        label: 'TheTVDB',
        url: `https://thetvdb.com/dereferrer/series/${encodeURIComponent(d.tvdbId)}`
      });
    }
    return links;
  }

  private openExternalUrl(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };
      ctx.startAbility(want).catch(() => {
        this.showToastSafe('当前设备无法打开外部浏览器');
      });
    } catch {
      this.showToastSafe('当前设备无法打开外部浏览器');
    }
  }

  private buildStreamFieldRows(st: MpMediaServerStream): StreamFieldRow[] {
    const rows: StreamFieldRow[] = [];
    const pushIf = (label: string, val: string): void => {
      const clean = (val ?? '').trim();
      if (clean.length > 0) {
        rows.push({ label: label, value: clean });
      }
    };

    if (st.type === 'video') {
      pushIf('标题', st.displayTitle || st.title);
      pushIf('内嵌标题', st.title);
      pushIf('编码', st.codec);
      if (st.width > 0 && st.height > 0) {
        pushIf('分辨率', `${st.width}x${st.height}`);
      }
      if (st.frameRate !== undefined) {
        pushIf('帧率', st.frameRate);
      }
      pushIf('比特率', st.formattedBitrate);
      pushIf('动态范围', st.videoRange);
      if (st.profile !== undefined) {
        pushIf('配置', st.profile);
      }
      if (st.level !== undefined) {
        pushIf('等级', st.level);
      }
      pushIf('长宽比', st.inferredAspectRatio);
      if (st.isInterlaced !== undefined) {
        pushIf('交错', st.isInterlaced ? '是' : '否');
      }
      if (st.colorPrimaries !== undefined) {
        pushIf('基色', st.colorPrimaries);
      }
      if (st.colorSpace !== undefined) {
        pushIf('色域', st.colorSpace);
      }
      if (st.bitDepth !== undefined && st.bitDepth > 0) {
        pushIf('位深', String(st.bitDepth));
      }
      return rows;
    }

    if (st.type === 'audio') {
      pushIf('标题', st.displayTitle || st.title);
      pushIf('内嵌标题', st.title);
      pushIf('语言', st.language);
      pushIf('布局', st.channelLayout);
      if (st.channels > 0) {
        pushIf('声道', String(st.channels));
      }
      pushIf('编码', st.codec);
      pushIf('比特率', st.formattedBitrate);
      if (st.sampleRate !== undefined && st.sampleRate > 0) {
        pushIf('采样率', `${st.sampleRate}Hz`);
      }
      pushIf('外部', st.isExternal ? '是' : '否');
      pushIf('默认', st.isDefault ? '是' : '否');
      return rows;
    }

    pushIf('标题', st.displayTitle || st.title);
    pushIf('内嵌标题', st.title);
    pushIf('语言', st.language);
    pushIf('编码', st.codec);
    pushIf('强制', st.isForced ? '是' : '否');
    pushIf('外部', st.isExternal ? '是' : '否');
    pushIf('默认', st.isDefault ? '是' : '否');
    return rows;
  }

  private episodeStillUrl(ep: MpMediaServerEpisode): string {
    if (ep.thumbUrl.length > 0) { return ep.thumbUrl; }
    if (ep.backdropUrl.length > 0) { return ep.backdropUrl; }
    if (this.detail && this.detail.backdropUrl.length > 0) { return this.detail.backdropUrl; }
    if (ep.posterUrl.length > 0) { return ep.posterUrl; }
    return this.detail ? this.detail.posterUrl : this.item.backdropUrl;
  }

  @Builder
  episodesHorizontalSectionBuilder() {
    if (this.seasons.length > 0 || this.episodes.length > 0 || this.loadingEpisodes) {
      Column({ space: 12 }) {
        Row() {
          Text('剧集')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          if (!this.loadingEpisodes && this.episodes.length > 0) {
            Text(`共 ${this.episodes.length} 集`)
              .fontSize(12)
              .fontColor(mpSecondaryText(this.isDark))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        if (this.seasons.length > 1) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.seasons, (s: MpMediaServerEpisode, idx: number) => {
                NativeAdaptivePill({
                  title: s.title || (s.seasonNumber >= 0 ? `第 ${s.seasonNumber} 季` : `季 ${idx + 1}`),
                  selected: this.activeSeasonIdx === idx,
                  onTap: () => {
                    if (this.activeSeasonIdx === idx) { return; }
                    this.activeSeasonIdx = idx;
                    if (this.detail) {
                      this.loadSeasonEpisodes(
                        this.detail.itemId,
                        this.detail.server,
                        s.itemId,
                        s.seasonNumber >= 0 ? s.seasonNumber : undefined,
                        this.loadSeq
                      );
                    }
                  }
                })
              }, (s: MpMediaServerEpisode, idx: number) => `${s.itemId}_${idx}_${this.activeSeasonIdx === idx}`)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        if (this.loadingEpisodes) {
          HarmonySkeletonHost({ loadingLabel: '正在加载分集列表' }) {
            HarmonyEpisodeStripSkeleton({
              showHeader: false,
              showSeasonPills: false,
              itemCount: 3
            })
          }
        } else if (this.episodes.length > 0) {
          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.episodes, (ep: MpMediaServerEpisode) => {
                Column({ space: 6 }) {
                  Stack({ alignContent: Alignment.BottomStart }) {
                    if (this.episodeStillUrl(ep).length > 0) {
                      MpRemoteImage({
                        src: this.episodeStillUrl(ep),
                        imgWidth: 228,
                        imgHeight: 128,
                        imgRadius: 14,
                        placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                      })
                    } else {
                      Column()
                        .width(228)
                        .height(128)
                        .borderRadius(14)
                        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    }

                    Column()
                      .width(228)
                      .height(54)
                      .borderRadius({ bottomLeft: 14, bottomRight: 14 })
                      .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#C8000000', 1]] })

                    if (ep.played) {
                      Stack() {
                        SymbolGlyph($r('sys.symbol.checkmark'))
                          .fontSize(11)
                          .fontColor([Color.White])
                      }
                      .width(22)
                      .height(22)
                      .borderRadius(11)
                      .backgroundColor('#E034C759')
                      .position({ right: 8, top: 8 })
                    }

                    Column({ space: 5 }) {
                      Row() {
                        Text(ep.episodeNumber > 0 ? `E${String(ep.episodeNumber).padStart(2, '0')}` : '单集')
                          .fontSize(10.5)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                          .borderRadius(8)
                          .backgroundColor('#B810141E')
                        Blank()
                        if (ep.durationMs > 0) {
                          Text(formatRuntimeMinutes(ep.durationMs))
                            .fontSize(10.5)
                            .fontColor('#E6FFFFFF')
                            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                            .borderRadius(8)
                            .backgroundColor('#8C000000')
                        }
                      }
                      .width('100%')

                      if (ep.playedPercentage > 0 && !ep.played) {
                        Progress({
                          value: Math.min(100, Math.max(0, ep.playedPercentage)),
                          total: 100,
                          type: ProgressType.Linear
                        })
                          .color(this.accentHex)
                          .backgroundColor('#44FFFFFF')
                          .width('100%')
                      }
                    }
                    .width(228)
                    .padding({ left: 8, right: 8, bottom: 8 })

                    if (this.selectedEpisodeId === ep.itemId) {
                      Column()
                        .width(228)
                        .height(128)
                        .borderRadius(14)
                        .border({ width: 1.8, color: this.accentHex, radius: 14 })
                        .hitTestBehavior(HitTestMode.None)
                    }
                  }
                  .shadow({ radius: 10, color: this.isDark ? '#32000000' : '#14000000', offsetY: 4 })

                  Text(`${ep.episodeNumber > 0 ? ep.episodeNumber + '. ' : ''}${ep.title}`)
                    .fontSize(13.5)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(228)

                  if (ep.overview.length > 0 || ep.premiereDate.length > 0) {
                    Text(ep.overview.length > 0 ? ep.overview : ep.premiereDate)
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
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => {
                  this.selectedEpisodeId = ep.itemId;
                  this.loadEpisodeStreamPreview(ep.itemId, ep.server || this.targetServer(), this.loadSeq);
                  const epTitle = this.detail
                    ? `${this.detail.title} · ${ep.episodeNumber > 0 ? 'E' + String(ep.episodeNumber).padStart(2, '0') + ' ' : ''}${ep.title}`
                    : ep.title;
                  this.playTargetItem(ep.itemId, epTitle, ep.premiereDate || this.targetServer());
                })
              }, (ep: MpMediaServerEpisode) => `${ep.itemId}_${this.selectedEpisodeId === ep.itemId}_${ep.played}`)
            }
            .alignItems(VerticalAlign.Top)
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
      }
      .width('100%')
    }
  }

  @Builder
  similarSectionBuilder() {
    if (this.similarItems.length > 0) {
      Column({ space: 12 }) {
        Text('类似作品')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .width('100%')
          .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.similarItems, (sim: MpMediaItem) => {
              Column({ space: 6 }) {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  if (sim.posterUrl.length > 0) {
                    MpRemoteImage({
                      src: sim.posterUrl,
                      imgWidth: 118,
                      imgHeight: 177,
                      imgRadius: 13,
                      placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                    })
                  } else {
                    Column()
                      .width(118)
                      .height(177)
                      .borderRadius(13)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  }

                  if (sim.vote > 0) {
                    Text(sim.vote.toFixed(1))
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .padding({ left: 7, right: 7, top: 2.5, bottom: 2.5 })
                      .borderRadius(8)
                      .backgroundColor('#CC10131A')
                      .margin(6)
                  }
                }
                .shadow({ radius: 10, color: this.isDark ? '#34000000' : '#14000000', offsetY: 4 })

                Text(sim.title)
                  .fontSize(13.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(118)

                if (sim.year.length > 0) {
                  Text(sim.year)
                    .fontSize(12)
                    .fontColor(mpMutedText(this.isDark))
                    .maxLines(1)
                    .width(118)
                }
              }
              .width(118)
              .alignItems(HorizontalAlign.Start)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onOpenMedia(sim))
            }, (sim: MpMediaItem) => `sim_${sim.id}_${sim.mediaId}`)
          }
          .alignItems(VerticalAlign.Top)
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  linksSectionBuilder() {
    if (this.externalLinks().length > 0) {
      Column({ space: 12 }) {
        Text('链接')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .width('100%')
          .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.externalLinks(), (lnk: ExternalLinkChipItem) => {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.link'))
                  .fontSize(14)
                  .fontColor([mpSecondaryText(this.isDark)])
                Text(lnk.label)
                  .fontSize(13.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(mpPrimaryText(this.isDark))
              }
              .height(36)
              .padding({ left: 14, right: 16 })
              .borderRadius(18)
              .backgroundColor(this.isDark ? '#14FFFFFF' : HarmonyThemeColors.chipFill(false))
              .border({
                width: 0.8,
                color: this.isDark ? '#26FFFFFF' : HarmonyThemeColors.borderSubtle(false),
                radius: 18
              })
              .hoverEffect(HoverEffect.Highlight)
              .accessibilityText(`打开 ${lnk.label} 外部链接`)
              .onClick(() => this.openExternalUrl(lnk.url))
            }, (lnk: ExternalLinkChipItem) => lnk.id)
          }
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  streamCardHeaderBuilder(st: MpMediaServerStream) {
    Row({ space: 8 }) {
      if (st.type === 'video') {
        SymbolGlyph($r('sys.symbol.video'))
          .fontSize(17)
          .fontColor([mpPrimaryText(this.isDark)])
        Text('视频')
          .fontSize(15.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
      } else if (st.type === 'audio') {
        SymbolGlyph($r('sys.symbol.speaker_wave_2'))
          .fontSize(17)
          .fontColor([mpPrimaryText(this.isDark)])
        Text('音频')
          .fontSize(15.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
        if (st.isDefault) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(15)
            .fontColor([mpPrimaryText(this.isDark)])
        }
      } else {
        SymbolGlyph($r('sys.symbol.AI_subtitles'))
          .fontSize(17)
          .fontColor([mpPrimaryText(this.isDark)])
        Text('字幕')
          .fontSize(15.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
        if (st.isDefault) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(15)
            .fontColor([mpPrimaryText(this.isDark)])
        }
      }
    }
    .width('100%')
    .margin({ bottom: 4 })
  }

  @Builder
  mediaInfoSectionBuilder() {
    if (this.activeSource() && this.activeSource()!.streams.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text('媒体信息')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
            .layoutWeight(1)
          if (this.activeSource()!.sizeBytes > 0) {
            Text(`${this.activeSource()!.container ? this.activeSource()!.container.toUpperCase() + ' · ' : ''}${formatByteSize(this.activeSource()!.sizeBytes)}`)
              .fontSize(12)
              .fontColor(mpSecondaryText(this.isDark))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.activeSource()!.streams, (st: MpMediaServerStream, sIdx: number) => {
              if (st.type === 'video' || st.type === 'audio' || st.type === 'subtitle') {
                Column({ space: 8 }) {
                  this.streamCardHeaderBuilder(st)

                  ForEach(this.buildStreamFieldRows(st), (row: StreamFieldRow) => {
                    Row({ space: 8 }) {
                      Text(row.label)
                        .fontSize(12.5)
                        .fontColor(mpMutedText(this.isDark))
                      Text(row.value)
                        .fontSize(12.5)
                        .fontColor(mpSecondaryText(this.isDark))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                    .width('100%')
                  }, (row: StreamFieldRow) => `${row.label}_${row.value}`)
                }
                .width(232)
                .padding(16)
                .alignItems(HorizontalAlign.Start)
                .borderRadius(16)
                .backgroundColor(this.isDark ? '#14171F' : HarmonyThemeColors.card(false, this.paletteId))
                .border({
                  width: 0.8,
                  color: this.isDark ? '#24FFFFFF' : HarmonyThemeColors.borderSubtle(false),
                  radius: 16
                })
              }
            }, (st: MpMediaServerStream, sIdx: number) => `${this.selectedSourceIdx}_${sIdx}_${st.index}_${st.type}`)
          }
          .alignItems(VerticalAlign.Top)
          .padding({ left: 16, right: 16 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll(this.scroller) {
        Column({ space: this.isShortLandscape() ? 14 : 20 }) {
          // 1. 顶部响应式 Hero 背景
          Stack({ alignContent: Alignment.BottomStart }) {
            if ((this.detail && (this.detail.backdropUrl || this.detail.posterUrl)) || this.item.backdropUrl || this.item.posterUrl) {
              MpRemoteImage({
                src: (this.detail ? (this.detail.backdropUrl || this.detail.posterUrl) : '') || this.item.backdropUrl || this.item.posterUrl,
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
                    ['#12000000', 0.36],
                    [HarmonyAppearanceStore.withAlpha(HarmonyThemeColors.canvas(true, this.paletteId), 'D8'), 0.80],
                    [HarmonyThemeColors.canvas(true, this.paletteId), 1]
                  ]
                  : [
                    ['#40000000', 0],
                    ['#10000000', 0.36],
                    ['#C0141822', 0.78],
                    [HarmonyThemeColors.canvas(false, this.paletteId), 1]
                  ]
              })

            Column({ space: this.isShortLandscape() ? 5 : 8 }) {
              Text(this.detail ? this.detail.title : this.item.title)
                .fontSize(this.isShortLandscape() ? 21 : 26)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .textAlign(TextAlign.Start)
                .maxLines(this.isShortLandscape() ? 1 : 2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (this.detail && this.detail.tagline.length > 0 && !this.isShortLandscape()) {
                Text(this.detail.tagline)
                  .fontSize(12.5)
                  .fontColor('#D9FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }

              Scroll() {
                Row({ space: 8 }) {
                  Row({ space: 4 }) {
                    HarmonyEntityLogo({
                      kind: 'mediaserver',
                      value: (this.detail ? (this.detail.serverType || this.detail.server) : this.item.serverName) || 'emby',
                      logoSize: 14,
                      cornerRadius: 3
                    })
                    Text((this.detail ? this.detail.server : this.item.serverName) || '媒体库')
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                  }
                  .padding({ left: 7, right: 8, top: 3, bottom: 3 })
                  .borderRadius(10)
                  .backgroundColor('#66000000')

                  if ((this.detail ? this.detail.rating : this.item.vote) > 0) {
                    NativeAdaptiveBadge({
                      text: `★ ${(this.detail ? this.detail.rating : this.item.vote).toFixed(1)}`,
                      tintHex: '#FFC845'
                    })
                  }
                  if ((this.detail ? this.detail.year : this.item.year).length > 0) {
                    NativeAdaptiveBadge({ text: this.detail ? this.detail.year : this.item.year })
                  }
                  if (this.detail && this.detail.durationMs > 0) {
                    NativeAdaptiveBadge({ text: formatRuntimeMinutes(this.detail.durationMs) })
                  }
                  if (this.detail && this.detail.officialRating.length > 0) {
                    NativeAdaptiveBadge({ text: this.detail.officialRating })
                  }
                  if (this.activeSource() && this.activeSource()!.container.length > 0) {
                    NativeAdaptiveBadge({
                      text: this.activeSource()!.container.toUpperCase(),
                      tintHex: this.accentHex,
                      filled: true
                    })
                  }
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(this.isShortLandscape() ? 14 : 20)
          }

          // 2. 主播放与订阅/搜索动作条
          Column({ space: 10 }) {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.play_fill')).fontSize(16).fontColor([Color.White])
                Text(this.detail && this.detail.resumePositionMs > 0 ? '继续播放' : '立即播放')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
              }
            }
            .width('100%')
            .height(48)
            .borderRadius(24)
            .backgroundColor(this.accentHex)
            .onClick(() => { this.playTargetItem(); })

            if (this.activeMediaSources().length > 1) {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.activeMediaSources(), (src: MpMediaServerSource, idx: number) => {
                    NativeAdaptivePill({
                      title: `${src.name || ('版本 ' + (idx + 1))}${src.sizeBytes > 0 ? ' · ' + formatByteSize(src.sizeBytes) : ''}`,
                      selected: this.selectedSourceIdx === idx,
                      onTap: () => { this.selectedSourceIdx = idx; }
                    })
                  }, (src: MpMediaServerSource, idx: number) => `${src.id}_${idx}_${this.selectedSourceIdx === idx}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
            }

            Row({ space: 10 }) {
              if (this.isPrimarySubscribed()) {
                Button() {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(16)
                      .fontColor([Color.White])
                    Text('已订阅')
                      .fontSize(14.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                  }
                }
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor('#34C759')
                .enabled(!this.mutatingSubscribe)
                .onClick(() => { this.handleToggleSubscribe(); })
              } else {
                Button() {
                  Row({ space: 6 }) {
                    SymbolGlyph($r('sys.symbol.bookmark_fill'))
                      .fontSize(16)
                      .fontColor([mpPrimaryText(this.isDark)])
                    Text(this.mutatingSubscribe ? '处理中…' : '添加订阅')
                      .fontSize(14.5)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(mpPrimaryText(this.isDark))
                  }
                }
                .layoutWeight(1)
                .height(44)
                .borderRadius(22)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .enabled(!this.mutatingSubscribe)
                .onClick(() => { this.handleToggleSubscribe(); })
              }

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
              .height(44)
              .borderRadius(22)
              .backgroundColor(Color.Transparent)
              .attributeModifier(new HarmonySurfaceModifier(this.isDark, 'pill', 22, this.accentHex, true, this.dynamicLight))
              .onClick(() => this.onSearchResource(this.detail ? this.detail.title : this.item.title))
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

          if (this.loading && !this.detail) {
            HarmonyMediaDetailBodySkeleton({
              showSeasons: this.isSeriesOrSeason(null),
              showSimilar: true,
              showLinks: true,
              showStreamCards: true
            })
          } else {
            // 3. 剧情简介与类型标签
            if ((this.detail && (this.detail.overview.length > 0 || this.detail.genres.length > 0)) || this.item.overview.length > 0) {
              Column() {
                CinematicPanel({ panelPadding: 16, cornerRadius: 18 }) {
                  Column({ space: 10 }) {
                    Row() {
                      Text('剧情简介')
                        .fontSize(16)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(mpPrimaryText(this.isDark))
                        .layoutWeight(1)
                      if (((this.detail ? this.detail.overview : this.item.overview) || '').length > 68) {
                        Text(this.overviewExpanded ? '收起 ▴' : '展开 ▾')
                          .fontSize(12.5)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.accentHex)
                          .onClick(() => { this.overviewExpanded = !this.overviewExpanded; })
                      }
                    }
                    .width('100%')

                    if ((this.detail ? this.detail.overview : this.item.overview).length > 0) {
                      Text(this.detail ? this.detail.overview : this.item.overview)
                        .fontSize(14)
                        .fontColor(mpSecondaryText(this.isDark))
                        .lineHeight(22)
                        .maxLines(this.overviewExpanded ? 99 : 3)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                        .onClick(() => {
                          if (((this.detail ? this.detail.overview : this.item.overview) || '').length > 68) {
                            this.overviewExpanded = !this.overviewExpanded;
                          }
                        })
                    }

                    if (this.detail && this.detail.genres.length > 0) {
                      Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                        ForEach(this.detail.genres, (g: string) => {
                          NativeAdaptiveBadge({ text: g })
                        }, (g: string) => `ms_genre_${g}`)
                      }
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            }

            // 4. 剧集列表（16:9 横版剧照横滑）
            this.episodesHorizontalSectionBuilder()

            // 5. 演职员表
            if (this.detail && this.detail.people.length > 0) {
              Column({ space: 10 }) {
                Text('演职员')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .width('100%')
                  .padding({ left: 16, right: 16 })

                Scroll() {
                  Row({ space: 14 }) {
                    ForEach(this.detail.people, (p: MpMediaServerPerson) => {
                      Column({ space: 5 }) {
                        if (p.imageUrl.length > 0) {
                          MpRemoteImage({
                            src: p.imageUrl,
                            imgWidth: 66,
                            imgHeight: 66,
                            imgRadius: 33,
                            placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                          })
                        } else {
                          Text((p.name || '演').substring(0, 1))
                            .width(66)
                            .height(66)
                            .borderRadius(33)
                            .textAlign(TextAlign.Center)
                            .fontColor(Color.White)
                            .backgroundColor(this.accentHex)
                        }
                        Text(p.name)
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(mpPrimaryText(this.isDark))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width(74)
                          .textAlign(TextAlign.Center)
                        if (p.role.length > 0) {
                          Text(p.role)
                            .fontSize(10.5)
                            .fontColor(mpSecondaryText(this.isDark))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width(74)
                            .textAlign(TextAlign.Center)
                        }
                      }
                      .alignItems(HorizontalAlign.Center)
                    }, (p: MpMediaServerPerson) => `${p.id}_${p.name}`)
                  }
                  .padding({ left: 16, right: 16 })
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
              }
            }

            // 6. 类似作品（对齐图2）
            this.similarSectionBuilder()

            // 7. 外部链接（对齐图2）
            this.linksSectionBuilder()

            // 8. 媒体信息（对齐图2：视频 / 音频 / 字幕轨道纵向参数卡片）
            this.mediaInfoSectionBuilder()
          }
        }
        .padding({ bottom: Math.max(52, this.safeBottomVp + 32) })
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
