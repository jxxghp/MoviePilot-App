import { pasteboard } from '@kit.BasicServicesKit';
import {
  RustCoreBridge,
  MoviePilotRepository,
  MpMediaItem,
  MpSubscribeItem,
  MpSubscribeShareItem,
  MpSubscribeDownloadFile,
  MpSubscribeLibraryFile,
  MpSubscribeEpisodeFiles,
  MpSubscribeFilesInfo,
  MpCalendarEpisodeItem,
  MpSiteItem,
  MpServiceConfig,
  MpFilterRuleGroup,
  MpRemoteImage
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  HarmonyPageHeader,
  HarmonyPillTabBar,
  HarmonySegmentedSwitch,
  HarmonySheetHeader,
  HarmonyEntityLogo,
  HarmonyEntityLogoPill,
  HarmonyThemeColors,
  HarmonyAppearanceStore,
  HarmonyAdaptiveLayout,
  HarmonySkeletonHost,
  HarmonySkeletonBlock,
  HarmonyPosterGridSkeleton,
  HarmonyPosterRowCardGridSkeleton,
  HarmonySubscribeFilesSheetSkeleton,
  mpPrimaryText,
  mpSecondaryText,
  mpMutedText
} from '@moviepilot/design_system';

function inferPathResolutionTag(rawText: string): string {
  const s = (rawText ?? '').toLowerCase();
  if (!s) { return ''; }
  if (s.includes('2160p')) { return '2160P'; }
  if (s.includes('4k') || s.includes('uhd')) { return '4K'; }
  if (s.includes('1080p') || s.includes('fhd')) { return '1080P'; }
  if (s.includes('720p')) { return '720P'; }
  return '';
}

const QUALITY_OPTIONS: string[] = ['', '蓝光原盘', 'REMUX', 'BluRay', 'UHD', 'WEB-DL', 'HDTV', 'H265', 'H264'];
const RESOLUTION_OPTIONS: string[] = ['', '4k', '1080p', '720p'];
const EFFECT_OPTIONS: string[] = ['', '杜比视界', '杜比全景声', 'HDR', '60fps'];

/**
 * 鸿蒙「订阅」中心：
 * - 一级页采用统一大胶囊切换「我的订阅 / 订阅广场 / 追剧日历」，支持二级独立模式直达「追剧日历」或「订阅广场」；
 * - 追剧日历真实消费 `GET /api/v1/subscribe/calendar` 展示剧集排期并支持直达详情；
 * - 订阅广场支持点击热门海报或分享卡片查看详情，以及「复用订阅」（`POST /api/v1/subscribe/fork`）；
 * - 订阅编辑器全量搭载品牌图标（下载器与真实站点图标）并无损提交。
 */
@Component
export struct HarmonySubscriptionsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageProp('mp_subscriptions_refresh_rev') @Watch('onSubscriptionsRefreshRevChanged') subscriptionsRefreshRev: number = 0;
  @Prop showBack: boolean = false;
  @Prop initialTitle: string = '订阅';
  @Prop initialMode: string = 'mine'; // 'mine' | 'square' | 'calendar' | 'history'
  @Prop initialHistoryType: string = '电影';
  @State private mainTabIndex: number = 0;
  @State private squareModeIndex: number = 0; // 0: 热门电影, 1: 热门剧集, 2: 社区分享
  @State private filter: string = '全部';
  @State private loading: boolean = true;
  @State private loadingSquare: boolean = false;
  @State private loadingCalendar: boolean = false;
  @State private items: MpSubscribeItem[] = [];
  @State private calendarItems: MpCalendarEpisodeItem[] = [];
  @State private popularMovies: MpMediaItem[] = [];
  @State private popularTvs: MpMediaItem[] = [];
  @State private shares: MpSubscribeShareItem[] = [];
  @State private forkingShareId: number = -1;
  @State private feedbackMsg: string = '';

  // 订阅历史状态（对齐 Web SubscribeHistoryDialog）
  @State private historyTypeIndex: number = 0; // 0: 电影, 1: 电视剧, 2: 音乐
  @State private historyItems: MpSubscribeItem[] = [];
  @State private historyPage: number = 1;
  @State private historyHasMore: boolean = false;
  @State private loadingHistory: boolean = false;
  @State private loadingMoreHistory: boolean = false;
  @State private historyLoadFailed: boolean = false;
  @State private historyGeneration: number = 0;
  @State private reSubscribingId: number = -1;
  @State private confirmDeleteHistorySub: MpSubscribeItem | null = null;
  @State private showHistoryDeleteConfirm: boolean = false;

  // 编辑弹窗全量状态
  @State private showEditor: boolean = false;
  @State private editingSub: MpSubscribeItem | null = null;
  @State private edQuality: string = '';
  @State private edResolution: string = '';
  @State private edEffect: string = '';
  @State private edBestVersion: boolean = false;
  @State private edSeason: string = '';
  @State private edTotalEp: string = '';
  @State private edStartEp: string = '';
  @State private edEpGroup: string = '';
  @State private edDownloader: string = '';
  @State private edSavePath: string = '';
  @State private edSites: number[] = [];
  @State private edFilterGroups: string[] = [];
  @State private edSearchImdb: boolean = false;
  @State private edInterval: number = 0;
  @State private edInclude: string = '';
  @State private edExclude: string = '';
  @State private edCustomWords: string = '';
  @State private showSitePicker: boolean = false;
  @State private showGroupPicker: boolean = false;
  @State private allSites: MpSiteItem[] = [];
  @State private allDownloaders: MpServiceConfig[] = [];
  @State private allRuleGroups: MpFilterRuleGroup[] = [];
  @State private savingEditor: boolean = false;

  // 删除确认弹窗
  @State private confirmDeleteSub: MpSubscribeItem | null = null;
  @State private showDeleteConfirm: boolean = false;

  // 社区分享复用确认弹窗
  @State private pendingForkShare: MpSubscribeShareItem | null = null;
  @State private showForkConfirm: boolean = false;

  // 订阅文件详情弹窗（GET /api/v1/subscribe/files/{subscribe_id}）
  @State private showFilesSheet: boolean = false;
  @State private filesTargetSub: MpSubscribeItem | null = null;
  @State private filesInfo: MpSubscribeFilesInfo | null = null;
  @State private loadingFiles: boolean = false;
  @State private filesModeIdx: number = 0; // 0: 下载文件, 1: 媒体库文件
  @State private filesStatusFilter: string = '全部'; // '全部' | '已入库' | '已下载' | '待入库'

  onBack: () => void = () => {};
  onOpenCalendar: () => void = () => {};
  onOpenSquare: () => void = () => {};
  onOpenHistory: (mtype: string) => void = () => {};
  onOpenMedia: (item: MpMediaItem) => void = () => {};
  onPlayServerItem: (itemId: string, server: string, title: string) => void = () => {};
  onPlayStorageFile: (storage: string, filePath: string, title: string) => void = () => {};

  aboutToAppear(): void {
    if (this.initialMode === 'square') {
      this.mainTabIndex = 1;
      this.loadSquareIfNeeded();
      return;
    }
    if (this.initialMode === 'calendar') {
      this.loadCalendar();
      this.loadSubscriptions();
      return;
    }
    if (this.initialMode === 'history') {
      if (this.initialHistoryType === '电视剧') {
        this.historyTypeIndex = 1;
      } else if (this.initialHistoryType === '音乐') {
        this.historyTypeIndex = 2;
      } else {
        this.historyTypeIndex = 0;
      }
      this.reloadHistoryFirstPage();
      return;
    }
    this.loadSubscriptions();
  }

  private onSubscriptionsRefreshRevChanged(): void {
    if (this.initialMode === 'mine') {
      this.loadSubscriptions();
    }
  }

  private currentHistoryMediaType(): string {
    if (this.historyTypeIndex === 1) { return '电视剧'; }
    if (this.historyTypeIndex === 2) { return '音乐'; }
    return '电影';
  }

  private async reloadHistoryFirstPage(): Promise<void> {
    this.historyGeneration += 1;
    const gen = this.historyGeneration;
    const mtype = this.currentHistoryMediaType();
    this.loadingHistory = true;
    this.loadingMoreHistory = false;
    this.historyLoadFailed = false;
    this.historyPage = 1;
    try {
      const loaded = await MoviePilotRepository.shared().fetchSubscribeHistory(mtype, 1, 30);
      if (gen !== this.historyGeneration) { return; }
      this.historyItems = loaded;
      this.historyPage = 2;
      this.historyHasMore = loaded.length >= 30;
    } catch {
      if (gen !== this.historyGeneration) { return; }
      this.historyItems = [];
      this.historyHasMore = false;
      this.historyLoadFailed = true;
    }
    if (gen === this.historyGeneration) {
      this.loadingHistory = false;
    }
  }

  private async loadMoreHistoryIfNeeded(): Promise<void> {
    if (!this.historyHasMore || this.loadingHistory || this.loadingMoreHistory) {
      return;
    }
    const gen = this.historyGeneration;
    const mtype = this.currentHistoryMediaType();
    const targetPage = this.historyPage;
    this.loadingMoreHistory = true;
    try {
      const pageItems = await MoviePilotRepository.shared().fetchSubscribeHistory(mtype, targetPage, 30);
      if (gen !== this.historyGeneration) { return; }
      if (pageItems.length === 0) {
        this.historyHasMore = false;
      } else {
        const merged: MpSubscribeItem[] = [];
        const seenIds: number[] = [];
        for (let i = 0; i < this.historyItems.length; i++) {
          merged.push(this.historyItems[i]);
          seenIds.push(this.historyItems[i].id);
        }
        let added = 0;
        for (let j = 0; j < pageItems.length; j++) {
          if (seenIds.indexOf(pageItems[j].id) < 0) {
            merged.push(pageItems[j]);
            seenIds.push(pageItems[j].id);
            added += 1;
          }
        }
        this.historyItems = merged;
        this.historyPage = targetPage + 1;
        this.historyHasMore = pageItems.length >= 30 && added > 0;
      }
    } catch {
      // 保留已有分页记录，继续上滑或点击刷新可重试
    }
    if (gen === this.historyGeneration) {
      this.loadingMoreHistory = false;
    }
  }

  private async handleReSubscribeHistory(sub: MpSubscribeItem): Promise<void> {
    if (this.reSubscribingId !== -1) { return; }
    this.reSubscribingId = sub.id;
    const res = await MoviePilotRepository.shared().reSubscribeFromHistory(sub, this.currentHistoryMediaType());
    this.reSubscribingId = -1;
    this.feedbackMsg = res.message;
    if (res.ok) {
      const nextRev = (AppStorage.get<number>('mp_subscriptions_refresh_rev') ?? 0) + 1;
      AppStorage.setOrCreate('mp_subscriptions_refresh_rev', nextRev);
    }
  }

  private async confirmDeleteHistoryAction(): Promise<void> {
    const target = this.confirmDeleteHistorySub;
    this.showHistoryDeleteConfirm = false;
    this.confirmDeleteHistorySub = null;
    if (!target) { return; }
    const ok = await MoviePilotRepository.shared().deleteSubscribeHistory(target.id);
    if (ok) {
      this.historyItems = this.historyItems.filter((it: MpSubscribeItem) => it.id !== target.id);
      this.historyGeneration += 1;
      this.historyPage = Math.floor(this.historyItems.length / 30) + 1;
      this.feedbackMsg = `已删除「${target.name}」的订阅历史记录`;
    } else {
      this.feedbackMsg = '删除订阅历史失败，请稍后重试';
    }
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

  private async loadCalendar(): Promise<void> {
    this.loadingCalendar = true;
    try {
      this.calendarItems = await MoviePilotRepository.shared().fetchSubscribeCalendar();
    } catch {
      this.calendarItems = [];
    }
    this.loadingCalendar = false;
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

  private openSubMediaDetail(sub: MpSubscribeItem): void {
    let tmdbId = '';
    let doubanId = '';
    let mediaId = '';
    let mediaSource = '';
    if (sub.rawJson && sub.rawJson.length > 2) {
      try {
        const rec = JSON.parse(sub.rawJson) as Record<string, Object>;
        if (rec['media_source'] !== undefined && rec['media_source'] !== null) {
          mediaSource = String(rec['media_source']).trim();
        }
        if (rec['media_id'] !== undefined && rec['media_id'] !== null) {
          const rawMid = String(rec['media_id']).trim();
          if (rawMid.length > 0 && rawMid !== '0') {
            if (mediaSource === 'themoviedb' || mediaSource === 'tmdb') {
              tmdbId = rawMid;
              mediaId = `tmdb:${rawMid}`;
            } else if (mediaSource === 'douban') {
              doubanId = rawMid;
              mediaId = `douban:${rawMid}`;
            } else if (mediaSource.length > 0) {
              mediaId = `${mediaSource}:${rawMid}`;
            } else {
              mediaId = rawMid;
            }
          }
        }
        if (!tmdbId && rec['tmdbid'] !== undefined && rec['tmdbid'] !== null) {
          tmdbId = String(rec['tmdbid']);
        }
        if (!doubanId && rec['doubanid'] !== undefined && rec['doubanid'] !== null) {
          doubanId = String(rec['doubanid']);
        }
        if (!mediaId && rec['mediaid'] !== undefined && rec['mediaid'] !== null) {
          mediaId = String(rec['mediaid']);
        }
      } catch {
        // ignore parse error
      }
    }
    const item: MpMediaItem = {
      id: tmdbId || doubanId || mediaId || String(sub.id),
      mediaId: mediaId || (tmdbId ? `tmdb:${tmdbId}` : (doubanId ? `douban:${doubanId}` : '')),
      tmdbId: tmdbId,
      doubanId: doubanId,
      title: sub.name,
      enTitle: '',
      year: sub.year,
      type: sub.type,
      overview: sub.description,
      vote: sub.vote,
      posterUrl: sub.posterUrl,
      backdropUrl: sub.backdropUrl,
      logoUrl: '',
      source: mediaSource.length > 0
        ? mediaSource
        : (doubanId.length > 0 && tmdbId.length === 0 ? 'douban' : 'themoviedb'),
      inLibrary: false,
      subtitle: '',
      percent: 0,
      serverName: '',
      playUrl: ''
    };
    this.onOpenMedia(item);
  }

  private async openFilesSheet(sub: MpSubscribeItem): Promise<void> {
    this.filesTargetSub = sub;
    this.filesInfo = null;
    this.filesModeIdx = 0;
    this.filesStatusFilter = '全部';
    this.loadingFiles = true;
    this.showFilesSheet = true;
    await this.reloadFilesSheet(sub.id);
  }

  private async reloadFilesSheet(subscribeId: number): Promise<void> {
    this.loadingFiles = true;
    try {
      const info = await MoviePilotRepository.shared().fetchSubscribeFiles(subscribeId);
      this.filesInfo = info;
      if (info && info.episodes.length > 0) {
        const hasAnyDl = info.episodes.some((e: MpSubscribeEpisodeFiles) => e.downloads.length > 0);
        const hasAnyLib = info.episodes.some((e: MpSubscribeEpisodeFiles) => e.libraries.length > 0);
        if (!hasAnyDl && hasAnyLib) {
          this.filesModeIdx = 1;
        }
      }
    } catch {
      this.filesInfo = null;
    }
    this.loadingFiles = false;
  }

  private copyPathToClipboard(filePath: string): void {
    const clean = (filePath ?? '').trim();
    if (!clean) { return; }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, clean);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '已复制文件路径', duration: 1600 });
        } catch {
          // ignore toast error
        }
      }).catch(() => {});
    } catch {
      // ignore pasteboard error
    }
  }

  private episodeFileStatus(ep: MpSubscribeEpisodeFiles): string {
    if (ep.libraries.length > 0) { return '已入库'; }
    if (ep.downloads.length > 0) { return '已下载'; }
    return '待入库';
  }

  private episodeFileStatusTint(statusLabel: string): string {
    if (statusLabel === '已入库') { return '#34C759'; }
    if (statusLabel === '已下载') { return '#317AF7'; }
    return '#F29B38';
  }

  private countEpisodesByFileStatus(filterLabel: string): number {
    if (!this.filesInfo) { return 0; }
    const all = this.filesInfo.episodes;
    if (filterLabel === '全部') { return all.length; }
    return all.filter((e: MpSubscribeEpisodeFiles) => this.episodeFileStatus(e) === filterLabel).length;
  }

  private filteredFileEpisodes(): MpSubscribeEpisodeFiles[] {
    if (!this.filesInfo) { return []; }
    if (this.filesStatusFilter === '全部') {
      return this.filesInfo.episodes;
    }
    return this.filesInfo.episodes.filter(
      (e: MpSubscribeEpisodeFiles) => this.episodeFileStatus(e) === this.filesStatusFilter
    );
  }

  private openLibraryFileDetail(lib: MpSubscribeLibraryFile, fallbackSub: MpSubscribeItem | null): void {
    if (!lib.server || !lib.itemId) { return; }
    const targetItem: MpMediaItem = {
      id: lib.itemId,
      mediaId: '',
      tmdbId: '',
      doubanId: '',
      title: fallbackSub ? fallbackSub.name : '媒体库详情',
      enTitle: '',
      year: fallbackSub ? fallbackSub.year : '',
      type: fallbackSub ? fallbackSub.type : '电影',
      overview: fallbackSub ? fallbackSub.description : '',
      vote: fallbackSub ? fallbackSub.vote : 0,
      posterUrl: fallbackSub ? fallbackSub.posterUrl : '',
      backdropUrl: fallbackSub ? fallbackSub.backdropUrl : '',
      logoUrl: '',
      source: 'mediaserver',
      inLibrary: true,
      subtitle: '',
      percent: 0,
      serverName: lib.server,
      playUrl: '',
      serverItemId: lib.itemId
    };
    this.showFilesSheet = false;
    setTimeout(() => {
      this.onOpenMedia(targetItem);
    }, 120);
  }

  private openCalendarMediaDetail(ep: MpCalendarEpisodeItem): void {
    const item: MpMediaItem = {
      id: ep.tmdbId || ep.id,
      mediaId: ep.tmdbId ? `tmdb:${ep.tmdbId}` : '',
      tmdbId: ep.tmdbId,
      doubanId: '',
      title: ep.title,
      enTitle: '',
      year: ep.airDate.length >= 4 ? ep.airDate.substring(0, 4) : '',
      type: '电视剧',
      overview: ep.overview,
      vote: 0,
      posterUrl: ep.posterUrl,
      backdropUrl: '',
      logoUrl: '',
      source: 'themoviedb',
      inLibrary: false,
      subtitle: '',
      percent: 0,
      serverName: '',
      playUrl: ''
    };
    this.onOpenMedia(item);
  }

  private openShareMediaDetail(sh: MpSubscribeShareItem): void {
    const tmdb = sh.tmdbId ?? '';
    const douban = sh.doubanId ?? '';
    const mid = sh.mediaId ?? '';
    const item: MpMediaItem = {
      id: tmdb || douban || mid || String(sh.id),
      mediaId: mid,
      tmdbId: tmdb,
      doubanId: douban,
      title: sh.name || sh.shareTitle,
      enTitle: '',
      year: sh.year,
      type: sh.type || '电视剧',
      overview: sh.shareComment,
      vote: sh.vote,
      posterUrl: sh.posterUrl,
      backdropUrl: '',
      logoUrl: '',
      source: douban.length > 0 && tmdb.length === 0 ? 'douban' : 'themoviedb',
      inLibrary: false,
      subtitle: '',
      percent: 0,
      serverName: '',
      playUrl: ''
    };
    this.onOpenMedia(item);
  }

  private async handleForkShare(sh: MpSubscribeShareItem): Promise<void> {
    if (this.forkingShareId === sh.id) { return; }
    this.forkingShareId = sh.id;
    const ok = await MoviePilotRepository.shared().forkSubscribeShare(sh);
    this.forkingShareId = -1;
    this.feedbackMsg = ok ? `已复用订阅「${sh.shareTitle || sh.name}」` : '复用订阅失败，请稍后重试';
    if (ok) {
      const nextRev = (AppStorage.get<number>('mp_subscriptions_refresh_rev') ?? 0) + 1;
      AppStorage.setOrCreate('mp_subscriptions_refresh_rev', nextRev);
      await this.loadSubscriptions();
      this.shares = await MoviePilotRepository.shared().fetchSubscribeShares();
    }
  }

  private async openEditor(sub: MpSubscribeItem): Promise<void> {
    this.editingSub = sub;
    this.edQuality = sub.quality || '';
    this.edResolution = sub.resolution || '';
    this.edEffect = sub.effect || '';
    this.edBestVersion = Boolean(sub.bestVersion);
    this.edSeason = sub.season > 0 ? String(sub.season) : '';
    this.edTotalEp = sub.totalEpisode > 0 ? String(sub.totalEpisode) : '';
    this.edStartEp = (sub.startEpisode ?? 0) > 0 ? String(sub.startEpisode) : '';
    this.edEpGroup = sub.episodeGroup || '';
    this.edDownloader = sub.downloader || '';
    this.edSavePath = sub.savePath || '';
    this.edSites = sub.sites ? [...sub.sites] : [];
    this.edFilterGroups = sub.filterGroups ? [...sub.filterGroups] : [];
    this.edSearchImdb = Boolean(sub.searchImdbid);
    this.edInterval = sub.interval ?? 0;
    this.edInclude = sub.include || '';
    this.edExclude = sub.exclude || '';
    this.edCustomWords = sub.customWords || '';
    this.showSitePicker = false;
    this.showGroupPicker = false;
    this.showEditor = true;

    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        this.allSites.length > 0 ? Promise.resolve(this.allSites) : repo.fetchSites(),
        this.allDownloaders.length > 0 ? Promise.resolve(this.allDownloaders) : repo.fetchDownloaders(),
        this.allRuleGroups.length > 0 ? Promise.resolve(this.allRuleGroups) : repo.fetchFilterRuleGroups()
      ]);
      this.allSites = res[0];
      this.allDownloaders = res[1];
      this.allRuleGroups = res[2];
    } catch {
      // ignore metadata hydration errors
    }
  }

  private async saveEditorChanges(): Promise<void> {
    if (!this.editingSub || this.savingEditor) { return; }
    this.savingEditor = true;
    const base = this.editingSub;
    const updated: MpSubscribeItem = {
      id: base.id,
      name: base.name,
      year: base.year,
      type: base.type,
      season: Number(this.edSeason) || base.season,
      totalEpisode: Number(this.edTotalEp) || base.totalEpisode,
      lackEpisode: base.lackEpisode,
      state: base.state,
      posterUrl: base.posterUrl,
      backdropUrl: base.backdropUrl,
      vote: base.vote,
      description: base.description,
      savePath: this.edSavePath.trim(),
      quality: this.edQuality,
      resolution: this.edResolution,
      effect: this.edEffect,
      bestVersion: this.edBestVersion,
      startEpisode: Number(this.edStartEp) || 0,
      episodeGroup: this.edEpGroup.trim(),
      downloader: this.edDownloader,
      sites: this.edSites,
      filterGroups: this.edFilterGroups,
      include: this.edInclude.trim(),
      exclude: this.edExclude.trim(),
      customWords: this.edCustomWords.trim(),
      searchImdbid: this.edSearchImdb,
      interval: this.edInterval,
      rawJson: base.rawJson
    };
    const ok = await MoviePilotRepository.shared().saveSubscription(updated);
    this.savingEditor = false;
    this.showEditor = false;
    this.feedbackMsg = ok ? `已保存订阅「${base.name}」` : '保存订阅失败，请稍后重试';
    if (ok) { await this.loadSubscriptions(); }
  }

  private toggleEdSite(siteId: number): void {
    if (this.edSites.includes(siteId)) {
      this.edSites = this.edSites.filter((id: number) => id !== siteId);
    } else {
      this.edSites = [...this.edSites, siteId];
    }
  }

  private toggleEdGroup(groupName: string): void {
    if (this.edFilterGroups.includes(groupName)) {
      this.edFilterGroups = this.edFilterGroups.filter((g: string) => g !== groupName);
    } else {
      this.edFilterGroups = [...this.edFilterGroups, groupName];
    }
  }

  private countByType(t: string): number {
    if (t === '全部') { return this.items.length; }
    return this.items.filter((i: MpSubscribeItem) => i.type === t).length;
  }

  private calendarFallbackTvItems(): MpSubscribeItem[] {
    return this.items.filter((i: MpSubscribeItem) => i.type === '电视剧');
  }

  private filteredItems(): MpSubscribeItem[] {
    if (this.initialMode === 'calendar') {
      return this.calendarFallbackTvItems();
    }
    if (this.filter === '全部') { return this.items; }
    return this.items.filter((i: MpSubscribeItem) => i.type === this.filter);
  }

  private episodeTag(ep: MpCalendarEpisodeItem): string {
    const s = ep.seasonNumber > 0 ? `S${String(ep.seasonNumber).padStart(2, '0')}` : 'S01';
    const e = ep.episodeNumber > 0 ? `E${String(ep.episodeNumber).padStart(2, '0')}` : '';
    return `${s}${e}`;
  }

  private posterColumnsTemplate(): string {
    return HarmonyAdaptiveLayout.posterGridTemplate(this.windowWidthVp);
  }

  @Builder
  editorSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: this.editingSub ? `编辑订阅 · ${this.editingSub.name}` : '编辑订阅',
        cancelText: '取消',
        actionText: this.savingEditor ? '保存中' : '保存',
        actionEnabled: !this.savingEditor,
        onCancel: () => { this.showEditor = false; },
        onAction: () => { this.saveEditorChanges(); }
      })

      Scroll() {
        Column({ space: 14 }) {
          if (this.editingSub) {
            Column() {
              CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.folder'))
                    .fontSize(17)
                    .fontColor([this.accentHex])
                  Column({ space: 2 }) {
                    Text('查看订阅文件详情')
                      .fontSize(14.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                    Text('查看各集已下载种子文件、媒体库入库路径与一键播放')
                      .fontSize(11.5)
                      .fontColor(mpSecondaryText(this.isDark))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(14)
                    .fontColor([mpSecondaryText(this.isDark)])
                }
                .width('100%')
              }
            }
            .width('100%')
            .onClick(() => {
              const target = this.editingSub;
              this.showEditor = false;
              if (target) {
                setTimeout(() => {
                  this.openFilesSheet(target);
                }, 140);
              }
            })
          }

          // 1. 画质与洗版
          Text('画质与洗版').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
            Column({ space: 12 }) {
              Text('质量').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                ForEach(QUALITY_OPTIONS, (q: string) => {
                  NativeAdaptivePill({
                    title: q.length === 0 ? '全部' : q,
                    selected: this.edQuality === q,
                    onTap: () => { this.edQuality = q; }
                  })
                }, (q: string) => `q_${q}`)
              }

              Text('分辨率').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                ForEach(RESOLUTION_OPTIONS, (r: string) => {
                  NativeAdaptivePill({
                    title: r.length === 0 ? '全部' : r.toUpperCase(),
                    selected: this.edResolution.toLowerCase() === r.toLowerCase(),
                    onTap: () => { this.edResolution = r; }
                  })
                }, (r: string) => `r_${r}`)
              }

              Text('特效').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                ForEach(EFFECT_OPTIONS, (e: string) => {
                  NativeAdaptivePill({
                    title: e.length === 0 ? '全部' : e,
                    selected: this.edEffect === e,
                    onTap: () => { this.edEffect = e; }
                  })
                }, (e: string) => `e_${e}`)
              }

              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Row() {
                Text('自动洗版').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.edBestVersion })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => { this.edBestVersion = v; })
              }.width('100%')
            }
          }

          // 2. 剧集设置（电视剧专属）
          if (this.editingSub && this.editingSub.type === '电视剧') {
            Text('剧集设置').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
              Column({ space: 10 }) {
                Row({ space: 8 }) {
                  Column({ space: 4 }) {
                    Text('季数').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                    TextInput({ placeholder: '1', text: this.edSeason })
                      .type(InputType.Number)
                      .fontColor(mpPrimaryText(this.isDark))
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      .borderRadius(10)
                      .onChange((v: string) => { this.edSeason = v; })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                  Column({ space: 4 }) {
                    Text('总集数').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                    TextInput({ placeholder: '自动', text: this.edTotalEp })
                      .type(InputType.Number)
                      .fontColor(mpPrimaryText(this.isDark))
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      .borderRadius(10)
                      .onChange((v: string) => { this.edTotalEp = v; })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                  Column({ space: 4 }) {
                    Text('开始集数').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                    TextInput({ placeholder: '1', text: this.edStartEp })
                      .type(InputType.Number)
                      .fontColor(mpPrimaryText(this.isDark))
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      .borderRadius(10)
                      .onChange((v: string) => { this.edStartEp = v; })
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }.width('100%')

                Text('剧集组（可选）').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
                TextInput({ placeholder: '留空使用默认剧集分组', text: this.edEpGroup })
                  .fontColor(mpPrimaryText(this.isDark))
                  .placeholderColor(mpSecondaryText(this.isDark))
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  .borderRadius(10)
                  .onChange((v: string) => { this.edEpGroup = v; })
              }
            }
          }

          // 3. 下载与保存（搭载真实下载器品牌图标）
          Text('下载与保存').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Text('下载器').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                HarmonyEntityLogoPill({
                  kind: 'downloader',
                  value: 'downloader',
                  title: '默认',
                  selected: this.edDownloader.length === 0,
                  onTap: () => { this.edDownloader = ''; }
                })
                ForEach(this.allDownloaders, (dl: MpServiceConfig) => {
                  HarmonyEntityLogoPill({
                    kind: 'downloader',
                    value: dl.type || dl.name,
                    title: dl.name,
                    selected: this.edDownloader === dl.name,
                    onTap: () => { this.edDownloader = dl.name; }
                  })
                }, (dl: MpServiceConfig) => dl.name)
              }

              Text('保存路径').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              TextInput({ placeholder: '留空遵循目录配置', text: this.edSavePath })
                .fontColor(mpPrimaryText(this.isDark))
                .placeholderColor(mpSecondaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                .borderRadius(10)
                .onChange((v: string) => { this.edSavePath = v; })
            }
          }

          // 4. 站点与优先级规则（搭载真实站点图标）
          Text('站点与优先级规则').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Row() {
                Text('订阅站点').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Text(this.edSites.length === 0 ? '跟随系统设置 ›' : `已选 ${this.edSites.length} 站 ›`)
                  .fontSize(13).fontColor(this.accentHex)
              }
              .width('100%')
              .onClick(() => { this.showSitePicker = !this.showSitePicker; })

              if (this.showSitePicker) {
                Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                  NativeAdaptivePill({
                    title: '跟随系统',
                    selected: this.edSites.length === 0,
                    onTap: () => { this.edSites = []; }
                  })
                  ForEach(this.allSites, (s: MpSiteItem) => {
                    HarmonyEntityLogoPill({
                      kind: 'site',
                      value: s.name,
                      dataUri: s.iconDataUri,
                      title: s.name,
                      selected: this.edSites.includes(s.id),
                      onTap: () => this.toggleEdSite(s.id)
                    })
                  }, (s: MpSiteItem) => `sub_site_${s.id}`)
                }
              }

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row() {
                Text('优先级规则组').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Text(this.edFilterGroups.length === 0 ? '跟随系统设置 ›' : `已选 ${this.edFilterGroups.length} 组 ›`)
                  .fontSize(13).fontColor(this.accentHex)
              }
              .width('100%')
              .onClick(() => { this.showGroupPicker = !this.showGroupPicker; })

              if (this.showGroupPicker) {
                Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                  NativeAdaptivePill({
                    title: '跟随系统',
                    selected: this.edFilterGroups.length === 0,
                    onTap: () => { this.edFilterGroups = []; }
                  })
                  ForEach(this.allRuleGroups, (g: MpFilterRuleGroup) => {
                    NativeAdaptivePill({
                      title: g.name,
                      selected: this.edFilterGroups.includes(g.name),
                      onTap: () => this.toggleEdGroup(g.name)
                    })
                  }, (g: MpFilterRuleGroup) => `sub_grp_${g.name}`)
                }
              }

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row() {
                Text('使用 IMDB ID 精确搜索').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.edSearchImdb })
                  .selectedColor(this.accentHex)
                  .onChange((v: boolean) => { this.edSearchImdb = v; })
              }.width('100%')

              Divider().color(HarmonyThemeColors.divider(this.isDark))

              Row({ space: 8 }) {
                Text('搜索间隔').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Text(this.edInterval <= 0 ? '默认' : `${this.edInterval} 分钟`)
                  .fontSize(13).fontColor(mpSecondaryText(this.isDark))
                Button('−')
                  .height(30).width(34).borderRadius(15)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  .fontColor(mpPrimaryText(this.isDark))
                  .onClick(() => { this.edInterval = Math.max(0, this.edInterval - 10); })
                Button('+')
                  .height(30).width(34).borderRadius(15)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  .fontColor(mpPrimaryText(this.isDark))
                  .onClick(() => { this.edInterval = this.edInterval + 10; })
              }.width('100%')
            }
          }

          // 5. 过滤与识别规则
          Text('过滤与识别规则').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
            Column({ space: 10 }) {
              Text('包含（支持正则）').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              TextInput({ placeholder: '例如：中字|繁简|HDR', text: this.edInclude })
                .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                .onChange((v: string) => { this.edInclude = v; })

              Text('排除（支持正则）').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              TextInput({ placeholder: '例如：国语|CAM|抢先版', text: this.edExclude })
                .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                .onChange((v: string) => { this.edExclude = v; })

              Text('自定义识别词').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
              TextInput({ placeholder: '针对本订阅生效的识别替换规则', text: this.edCustomWords })
                .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                .onChange((v: string) => { this.edCustomWords = v; })
            }
          }
        }
        .padding({ bottom: 32 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  @Builder
  filesStatCardBuilder(label: string, valueText: string, tintHex: string) {
    Column({ space: 4 }) {
      Text(valueText)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(tintHex)
        .maxLines(1)
      Text(label)
        .fontSize(11.5)
        .fontColor(mpSecondaryText(this.isDark))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10, left: 8, right: 8 })
    .borderRadius(14)
    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  downloadFileItemCardBuilder(dl: MpSubscribeDownloadFile) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        if (inferPathResolutionTag(dl.torrentTitle || dl.filePath).length > 0) {
          NativeAdaptiveBadge({
            text: inferPathResolutionTag(dl.torrentTitle || dl.filePath),
            tintHex: this.accentHex,
            filled: true
          })
        }
        if (dl.siteName.length > 0) {
          NativeAdaptiveBadge({ text: dl.siteName, tintHex: '#26B8A8' })
        }
        if (dl.downloader.length > 0) {
          Row({ space: 4 }) {
            HarmonyEntityLogo({
              kind: 'downloader',
              value: dl.downloader,
              logoSize: 15,
              cornerRadius: 4
            })
            Text(dl.downloader)
              .fontSize(11.5)
              .fontColor(mpSecondaryText(this.isDark))
              .maxLines(1)
          }
        }
      }
      .width('100%')

      if (dl.torrentTitle.length > 0) {
        Text(dl.torrentTitle)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(mpPrimaryText(this.isDark))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (dl.hash.length > 0) {
        Text(`HASH · ${dl.hash}`)
          .fontSize(11)
          .fontColor(mpMutedText(this.isDark))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (dl.filePath.length > 0) {
        Row({ space: 8 }) {
          Text(dl.filePath)
            .fontSize(11.5)
            .fontColor(mpSecondaryText(this.isDark))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_text_on_doc_text'))
              .fontSize(12)
              .fontColor([this.accentHex])
            Text('复制路径')
              .fontSize(11.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentHex)
          }
          .padding({ left: 9, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '24' : '16'))
          .onClick(() => this.copyPathToClipboard(dl.filePath))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(11)
    .borderRadius(12)
    .backgroundColor(this.isDark ? '#18FFFFFF' : '#0A000000')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  libraryFileItemCardBuilder(lib: MpSubscribeLibraryFile, activeSub: MpSubscribeItem | null) {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        if (inferPathResolutionTag(lib.filePath).length > 0) {
          NativeAdaptiveBadge({
            text: inferPathResolutionTag(lib.filePath),
            tintHex: '#34C759',
            filled: true
          })
        }
        Row({ space: 5 }) {
          HarmonyEntityLogo({
            kind: lib.server.length > 0 ? 'mediaserver' : 'storage',
            value: lib.server.length > 0 ? (lib.serverType || lib.server) : lib.storage,
            logoSize: 16,
            cornerRadius: 4
          })
          Text(lib.server.length > 0 ? `${lib.server} · ${lib.storage || 'local'}` : (lib.storage || '本地存储'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(mpPrimaryText(this.isDark))
            .maxLines(1)
        }
      }
      .width('100%')

      if (lib.filePath.length > 0) {
        Text(lib.filePath)
          .fontSize(12)
          .fontColor(mpSecondaryText(this.isDark))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      Row({ space: 8 }) {
        if (lib.filePath.length > 0) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_text_on_doc_text'))
              .fontSize(12)
              .fontColor([mpPrimaryText(this.isDark)])
            Text('复制路径')
              .fontSize(11.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpPrimaryText(this.isDark))
          }
          .padding({ left: 9, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          .onClick(() => this.copyPathToClipboard(lib.filePath))
        }

        if (lib.server.length > 0 && lib.itemId.length > 0) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(12)
              .fontColor([Color.White])
            Text('立即播放')
              .fontSize(11.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 10, right: 11, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(this.accentHex)
          .onClick(() => {
            this.showFilesSheet = false;
            this.onPlayServerItem(lib.itemId, lib.server, activeSub ? activeSub.name : '媒体库播放');
          })

          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.film'))
              .fontSize(12)
              .fontColor([this.accentHex])
            Text('媒体库详情')
              .fontSize(11.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentHex)
          }
          .padding({ left: 9, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '24' : '16'))
          .onClick(() => this.openLibraryFileDetail(lib, activeSub))
        } else if (lib.filePath.length > 0 && RustCoreBridge.detectPlayableMediaKind(lib.filePath).length > 0) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(12)
              .fontColor([Color.White])
            Text('立即播放')
              .fontSize(11.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 10, right: 11, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(this.accentHex)
          .onClick(() => {
            this.showFilesSheet = false;
            this.onPlayStorageFile(
              lib.storage || 'local',
              lib.filePath,
              activeSub ? activeSub.name : '订阅文件播放'
            );
          })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(11)
    .borderRadius(12)
    .backgroundColor(this.isDark ? '#18FFFFFF' : '#0A000000')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  filesSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '订阅文件详情',
        cancelText: '关闭',
        actionText: this.loadingFiles ? '加载中' : '刷新',
        actionEnabled: !this.loadingFiles && this.filesTargetSub !== null,
        onCancel: () => { this.showFilesSheet = false; },
        onAction: () => {
          if (this.filesTargetSub) {
            this.reloadFilesSheet(this.filesTargetSub.id);
          }
        }
      })

      Scroll() {
        Column({ space: 14 }) {
          // 1. 顶部订阅摘要与三项统计卡片
          if (this.filesInfo?.subscribe || this.filesTargetSub) {
            CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
              Column({ space: 12 }) {
                Row({ space: 12 }) {
                  if (((this.filesInfo?.subscribe ?? this.filesTargetSub)?.posterUrl ?? '').length > 0) {
                    MpRemoteImage({
                      src: (this.filesInfo?.subscribe ?? this.filesTargetSub)!.posterUrl,
                      imgWidth: 60,
                      imgHeight: 88,
                      imgRadius: 10,
                      placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                    })
                  } else {
                    Column()
                      .width(60)
                      .height(88)
                      .borderRadius(10)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  }

                  Column({ space: 6 }) {
                    Text((this.filesInfo?.subscribe ?? this.filesTargetSub)!.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')

                    Row({ space: 6 }) {
                      if ((this.filesInfo?.subscribe ?? this.filesTargetSub)!.season > 0) {
                        NativeAdaptiveBadge({
                          text: `S${String((this.filesInfo?.subscribe ?? this.filesTargetSub)!.season).padStart(2, '0')}`,
                          tintHex: this.accentHex,
                          filled: true
                        })
                      }
                      if ((this.filesInfo?.subscribe ?? this.filesTargetSub)!.year.length > 0) {
                        NativeAdaptiveBadge({ text: (this.filesInfo?.subscribe ?? this.filesTargetSub)!.year })
                      }
                      NativeAdaptiveBadge({
                        text: (this.filesInfo?.subscribe ?? this.filesTargetSub)!.state === 'S' ? '已暂停' : '订阅中',
                        tintHex: (this.filesInfo?.subscribe ?? this.filesTargetSub)!.state === 'S' ? '#F29B38' : '#34C759'
                      })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')

                if (this.filesInfo) {
                  Row({ space: 8 }) {
                    this.filesStatCardBuilder(
                      '已下载',
                      `${this.filesInfo.downloadedCount}/${this.filesInfo.totalCount}`,
                      this.accentHex
                    )
                    this.filesStatCardBuilder(
                      '已入库',
                      `${this.filesInfo.libraryCount}/${this.filesInfo.totalCount}`,
                      '#34C759'
                    )
                    this.filesStatCardBuilder(
                      '缺失',
                      `${this.filesInfo.missingCount}`,
                      '#F29B38'
                    )
                  }
                  .width('100%')
                } else if (this.loadingFiles) {
                  HarmonySkeletonHost({ loadingLabel: '正在加载订阅文件统计' }) {
                    Row({ space: 8 }) {
                      ForEach([0, 1, 2], (idx: number) => {
                        Column({ space: 6 }) {
                          HarmonySkeletonBlock({ blockWidth: 44, blockHeight: 16, cornerRadius: 5 })
                          HarmonySkeletonBlock({ blockWidth: 38, blockHeight: 11.5, cornerRadius: 4, tone: 'subtle' })
                        }
                        .layoutWeight(1)
                        .padding({ top: 10, bottom: 10, left: 8, right: 8 })
                        .borderRadius(14)
                        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                        .alignItems(HorizontalAlign.Center)
                      }, (idx: number) => `sub_fstat_sk_${idx}`)
                    }
                    .width('100%')
                  }
                }
              }
              .width('100%')
            }
          }

          // 2. 模式切换（下载文件 / 媒体库文件）与状态筛选胶囊
          HarmonySegmentedSwitch({
            options: ['下载文件', '媒体库文件'],
            selectedIndex: this.filesModeIdx,
            onSelect: (idx: number) => { this.filesModeIdx = idx; }
          })

          Scroll() {
            Row({ space: 8 }) {
              ForEach(['全部', '已入库', '已下载', '待入库'], (st: string) => {
                NativeAdaptivePill({
                  title: (this.loadingFiles && !this.filesInfo) ? st : `${st} ${this.countEpisodesByFileStatus(st)}`,
                  selected: this.filesStatusFilter === st,
                  onTap: () => { this.filesStatusFilter = st; }
                })
              }, (st: string) => `file_st_${st}_${(this.loadingFiles && !this.filesInfo) ? 'ld' : this.countEpisodesByFileStatus(st)}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          // 3. 分集/正片文件明细卡片列表
          if (this.loadingFiles && !this.filesInfo) {
            HarmonySubscribeFilesSheetSkeleton({
              showStatTiles: false,
              episodeCount: 3
            })
          } else if (this.filteredFileEpisodes().length === 0) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(34)
                .fontColor([mpSecondaryText(this.isDark)])
              Text('暂无符合筛选条件的关联文件记录')
                .fontSize(13.5)
                .fontColor(mpSecondaryText(this.isDark))
            }
            .width('100%')
            .padding({ top: 28, bottom: 28 })
            .alignItems(HorizontalAlign.Center)
          } else {
            ForEach(this.filteredFileEpisodes(), (ep: MpSubscribeEpisodeFiles) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
                Column({ space: 10 }) {
                  Row({ space: 8 }) {
                    NativeAdaptiveBadge({
                      text: ep.episodeKey === '0' ? '正片' : `E${String(ep.episodeNumber).padStart(2, '0')}`,
                      tintHex: this.accentHex,
                      filled: true
                    })
                    Text(ep.title || (ep.episodeKey === '0' ? '电影正片' : `第 ${ep.episodeNumber} 集`))
                      .fontSize(14.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    NativeAdaptiveBadge({
                      text: this.episodeFileStatus(ep),
                      tintHex: this.episodeFileStatusTint(this.episodeFileStatus(ep))
                    })
                  }
                  .width('100%')

                  if (this.filesModeIdx === 0) {
                    if (ep.downloads.length > 0) {
                      ForEach(ep.downloads, (dl: MpSubscribeDownloadFile, dIdx: number) => {
                        this.downloadFileItemCardBuilder(dl)
                      }, (dl: MpSubscribeDownloadFile, dIdx: number) => `${ep.episodeKey}_dl_${dIdx}_${dl.hash}_${dl.filePath}`)
                    } else {
                      Text(ep.libraries.length > 0 ? '该条目已入库媒体库，可切换至「媒体库文件」查看或播放' : '暂无下载任务或历史记录')
                        .fontSize(12)
                        .fontColor(mpSecondaryText(this.isDark))
                        .width('100%')
                    }
                  } else {
                    if (ep.libraries.length > 0) {
                      ForEach(ep.libraries, (lib: MpSubscribeLibraryFile, lIdx: number) => {
                        this.libraryFileItemCardBuilder(lib, this.filesInfo?.subscribe ?? this.filesTargetSub)
                      }, (lib: MpSubscribeLibraryFile, lIdx: number) => `${ep.episodeKey}_lib_${lIdx}_${lib.itemId}_${lib.filePath}`)
                    } else {
                      Text(ep.downloads.length > 0 ? '已有下载文件记录，等待整理入库' : '尚未入库媒体库')
                        .fontSize(12)
                        .fontColor(mpSecondaryText(this.isDark))
                        .width('100%')
                    }
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }, (ep: MpSubscribeEpisodeFiles) => `${ep.episodeKey}_${this.filesModeIdx}_${ep.downloads.length}_${ep.libraries.length}`)
          }
        }
        .padding({ bottom: 32 })
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  @Builder
  deleteConfirmSheetBuilder() {
    Scroll() {
      Column({ space: 16 }) {
        Text('确认删除订阅')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .width('100%')
        Text(`确定要删除订阅「${this.confirmDeleteSub?.name ?? ''}」吗？此操作无法撤销。`)
          .fontSize(14)
          .fontColor(mpSecondaryText(this.isDark))
          .width('100%')
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1).height(46).borderRadius(23)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .fontColor(mpPrimaryText(this.isDark))
            .onClick(() => { this.showDeleteConfirm = false; })
          Button('确认删除')
            .layoutWeight(1).height(46).borderRadius(23)
            .backgroundColor('#E84855')
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .onClick(async () => {
              const target = this.confirmDeleteSub;
              this.showDeleteConfirm = false;
              if (target) {
                const ok = await MoviePilotRepository.shared().deleteSubscribe(target.id);
                this.feedbackMsg = ok ? `已删除订阅「${target.name}」` : '删除失败';
                await this.loadSubscriptions();
              }
            })
        }.width('100%')
      }
      .padding(22)
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  forkConfirmSheetBuilder() {
    Scroll() {
      Column({ space: 16 }) {
        Text('复用订阅')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(mpPrimaryText(this.isDark))
          .width('100%')
        Text(`将「${this.pendingForkShare ? (this.pendingForkShare.shareTitle || this.pendingForkShare.name) : ''}」的过滤规则添加到我的订阅列表吗？`)
          .fontSize(14)
          .fontColor(mpSecondaryText(this.isDark))
          .width('100%')
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1).height(46).borderRadius(23)
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
            .fontColor(mpPrimaryText(this.isDark))
            .onClick(() => { this.showForkConfirm = false; })
          Button('确认复用')
            .layoutWeight(1).height(46).borderRadius(23)
            .backgroundColor(this.accentHex)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .onClick(() => {
              const target = this.pendingForkShare;
              this.showForkConfirm = false;
              if (target) {
                this.handleForkShare(target);
              }
            })
        }.width('100%')
      }
      .padding(22)
      .width('100%')
    }
    .scrollBar(BarState.Off)
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
              if (it.vote > 0) {
                Text(it.vote.toFixed(1))
                  .fontSize(10.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(8)
                  .backgroundColor('#B810141E')
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
    .padding({ left: 16, right: 16, top: 6, bottom: this.showBack ? 40 : 128 })
    .layoutWeight(1)
  }

  @Builder
  calendarListBuilder() {
    if (this.loadingCalendar || (this.loading && this.calendarItems.length === 0 && this.items.length === 0)) {
      HarmonyPosterRowCardGridSkeleton({
        variant: 'calendar',
        fillViewport: true,
        bottomPadding: this.showBack ? 44 : 128
      })
    } else if (this.calendarItems.length > 0) {
      Grid() {
        ForEach(this.calendarItems, (ep: MpCalendarEpisodeItem) => {
          GridItem() {
            Column() {
              CinematicPanel({ panelPadding: 13, cornerRadius: 18, interactive: true }) {
                Row({ space: 12 }) {
                  if (ep.posterUrl.length > 0) {
                    MpRemoteImage({
                      src: ep.posterUrl,
                      imgWidth: 64,
                      imgHeight: 94,
                      imgRadius: 10,
                      placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                    })
                  } else {
                    Column()
                      .width(64)
                      .height(94)
                      .borderRadius(10)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                  }

                  Column({ space: 6 }) {
                    Row({ space: 8 }) {
                      NativeAdaptiveBadge({
                        text: ep.airDate.length > 0 ? ep.airDate : '近期播出',
                        tintHex: this.accentHex,
                        filled: true
                      })
                      NativeAdaptiveBadge({
                        text: this.episodeTag(ep),
                        tintHex: '#34C759'
                      })
                    }.width('100%')

                    Text(ep.title)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')

                    if (ep.episodeTitle.length > 0) {
                      Text(ep.episodeTitle)
                        .fontSize(12.5)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(mpPrimaryText(this.isDark))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }

                    if (ep.overview.length > 0) {
                      Text(ep.overview)
                        .fontSize(11.5)
                        .fontColor(mpSecondaryText(this.isDark))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
              }
            }
            .width('100%')
            .onClick(() => this.openCalendarMediaDetail(ep))
          }
        }, (ep: MpCalendarEpisodeItem) => ep.id)
      }
      .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
      .columnsGap(12)
      .rowsGap(12)
      .padding({ left: 16, right: 16, top: 4, bottom: this.showBack ? 44 : 128 })
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    } else if (this.calendarFallbackTvItems().length > 0) {
      // 若服务端暂未生成剧集排期，回退展示在追剧集进度列表
      Scroll() {
        Column({ space: 12 }) {
          Text('暂无未来单集排期，以下为当前订阅剧集：')
            .fontSize(12)
            .fontColor(mpSecondaryText(this.isDark))
            .width('100%')
          Grid() {
            ForEach(this.calendarFallbackTvItems(), (sub: MpSubscribeItem) => {
              GridItem() {
                Column() {
                  CinematicPanel({ panelPadding: 13, cornerRadius: 18, interactive: true }) {
                    Row({ space: 12 }) {
                      if (sub.posterUrl.length > 0) {
                        MpRemoteImage({
                          src: sub.posterUrl,
                          imgWidth: 58,
                          imgHeight: 86,
                          imgRadius: 10,
                          placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                        })
                      }
                      Column({ space: 5 }) {
                        Text(`${sub.name}${sub.season > 0 ? ' S' + String(sub.season).padStart(2, '0') : ''}`)
                          .fontSize(14.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).maxLines(1).width('100%')
                        if (sub.totalEpisode > 0) {
                          Text(`已更新 ${RustCoreBridge.computeSubscribeProgress(sub.totalEpisode, sub.lackEpisode).label}`)
                            .fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
                        }
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    }.width('100%')
                  }
                }
                .width('100%')
                .onClick(() => this.openSubMediaDetail(sub))
              }
            }, (sub: MpSubscribeItem) => `cal_fallback_${sub.id}`)
          }
          .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
          .columnsGap(12)
          .rowsGap(12)
          .width('100%')
        }
        .padding({ left: 16, right: 16, top: 4, bottom: this.showBack ? 44 : 128 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    } else {
      Column({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.calendar')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
        Text('暂无近期追剧日历排期').fontSize(14).fontColor(mpSecondaryText(this.isDark))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  subscribeHistoryBuilder() {
    Column({ space: 10 }) {
      Column() {
        HarmonySegmentedSwitch({
          options: ['电影', '电视剧', '音乐'],
          selectedIndex: this.historyTypeIndex,
          onSelect: (idx: number) => {
            if (this.historyTypeIndex !== idx) {
              this.historyTypeIndex = idx;
              this.reloadHistoryFirstPage();
            }
          }
        })
      }
      .padding({ left: 16, right: 16, top: 2 })

      if (this.loadingHistory && this.historyItems.length === 0) {
        HarmonyPosterRowCardGridSkeleton({
          variant: 'subscribe',
          fillViewport: true,
          bottomPadding: 44
        })
      } else if (this.historyLoadFailed && this.historyItems.length === 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
          Text('暂时无法载入订阅历史').fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
          Text('请检查网络连接或点击重试').fontSize(12.5).fontColor(mpSecondaryText(this.isDark))
          NativeAdaptivePill({
            title: '重试',
            selected: true,
            onTap: () => { this.reloadHistoryFirstPage(); }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.historyItems.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
          Text('没有已完成的订阅').fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
          Text('完成的订阅会显示在这里').fontSize(12.5).fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.historyItems, (sub: MpSubscribeItem) => {
            GridItem() {
              Column() {
                CinematicPanel({ panelPadding: 13, cornerRadius: 18, interactive: true }) {
                  Row({ space: 12 }) {
                    Column() {
                      if (sub.posterUrl.length > 0) {
                        MpRemoteImage({
                          src: sub.posterUrl,
                          imgWidth: 68,
                          imgHeight: sub.type === '音乐' ? 68 : 102,
                          imgRadius: 11,
                          placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                        })
                      } else {
                        Column()
                          .width(68)
                          .height(sub.type === '音乐' ? 68 : 102)
                          .borderRadius(11)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      }
                    }

                    Column({ space: 6 }) {
                      Row({ space: 8 }) {
                        Text(sub.name)
                          .fontSize(15.5)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(mpPrimaryText(this.isDark))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                        if (sub.type === '电视剧' && sub.season > 0) {
                          NativeAdaptiveBadge({
                            text: `第 ${sub.season} 季`,
                            tintHex: this.accentHex
                          })
                        }
                      }
                      .width('100%')

                      Row({ space: 6 }) {
                        Text(`${sub.date && sub.date.length > 0 ? sub.date : ''}${(sub.date && sub.date.length > 0 && sub.year.length > 0) ? ' · ' : ''}${sub.year}`)
                          .fontSize(12)
                          .fontColor(mpSecondaryText(this.isDark))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        if (sub.vote > 0) {
                          Text(`★ ${sub.vote.toFixed(1)}`)
                            .fontSize(12)
                            .fontWeight(FontWeight.Medium)
                            .fontColor('#F2B830')
                        }
                      }
                      .width('100%')

                      if (sub.description && sub.description.length > 0) {
                        Text(sub.description)
                          .fontSize(12)
                          .fontColor(mpSecondaryText(this.isDark))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                      }

                      Row({ space: 8 }) {
                        Row({ space: 5 }) {
                          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                            .fontSize(12)
                            .fontColor([this.accentHex])
                          Text(this.reSubscribingId === sub.id ? '重新订阅中…' : '重新订阅')
                            .fontSize(12)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(mpPrimaryText(this.isDark))
                        }
                        .padding({ left: 11, right: 12, top: 6, bottom: 6 })
                        .borderRadius(16)
                        .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '26' : '16'))
                        .opacity(this.reSubscribingId !== -1 ? 0.6 : 1)
                        .accessibilityText(`重新订阅 ${sub.name}`)
                        .onClick(() => {
                          this.handleReSubscribeHistory(sub);
                        })

                        Blank().layoutWeight(1)

                        Button({ type: ButtonType.Circle }) {
                          SymbolGlyph($r('sys.symbol.trash'))
                            .fontSize(15)
                            .fontColor(['#FF453A'])
                        }
                        .width(34)
                        .height(34)
                        .backgroundColor(HarmonyAppearanceStore.withAlpha('#FF453A', this.isDark ? '26' : '16'))
                        .accessibilityText(`删除订阅历史 ${sub.name}`)
                        .onClick(() => {
                          this.confirmDeleteHistorySub = sub;
                          this.showHistoryDeleteConfirm = true;
                        })
                      }
                      .width('100%')
                      .padding({ top: 2 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .onClick(() => {
                if (sub.type !== '音乐') {
                  this.openSubMediaDetail(sub);
                }
              })
            }
          }, (sub: MpSubscribeItem) => `hist_${this.historyTypeIndex}_${sub.id}`)
        }
        .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
        .columnsGap(12)
        .rowsGap(12)
        .padding({ left: 16, right: 16, top: 4, bottom: 44 })
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .onReachEnd(() => {
          this.loadMoreHistoryIfNeeded();
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  historyDeleteConfirmSheetBuilder() {
    Column({ space: 16 }) {
      HarmonySheetHeader({
        title: '删除订阅历史',
        cancelText: '关闭',
        onCancel: () => {
          this.showHistoryDeleteConfirm = false;
          this.confirmDeleteHistorySub = null;
        }
      })

      Text(`确认删除「${this.confirmDeleteHistorySub ? this.confirmDeleteHistorySub.name : ''}」的订阅历史记录吗？`)
        .fontSize(14)
        .fontColor(mpSecondaryText(this.isDark))
        .width('100%')

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(mpPrimaryText(this.isDark))
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          .onClick(() => {
            this.showHistoryDeleteConfirm = false;
            this.confirmDeleteHistorySub = null;
          })

        Button('删除')
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor('#FF453A')
          .onClick(() => {
            this.confirmDeleteHistoryAction();
          })
      }
      .width('100%')
    }
    .padding({ left: 20, right: 20, top: 14, bottom: 28 })
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      if (this.showBack) {
        NativeBackHeader({
          title: this.initialMode === 'calendar'
            ? ((this.loadingCalendar || (this.loading && this.calendarItems.length === 0))
              ? '追剧日历'
              : `追剧日历 (${this.calendarItems.length > 0 ? this.calendarItems.length : this.calendarFallbackTvItems().length})`)
            : (this.initialMode === 'square'
              ? '订阅广场'
              : (this.initialMode === 'history'
                ? '订阅历史'
                : (this.loading && this.items.length === 0 ? this.initialTitle : `${this.initialTitle} (${this.items.length})`))),
          trailingSymbol: (this.initialMode === 'calendar' || this.initialMode === 'history') ? 'sys.symbol.arrow_clockwise' : '',
          trailingAccessibility: this.initialMode === 'calendar'
            ? '刷新日历'
            : (this.initialMode === 'history' ? '刷新订阅历史' : ''),
          onBack: () => this.onBack(),
          onTrailingClick: () => {
            if (this.initialMode === 'calendar') {
              this.loadCalendar();
            } else if (this.initialMode === 'history') {
              this.reloadHistoryFirstPage();
            }
          }
        })
      } else {
        HarmonyPageHeader({
          title: '订阅',
          centerTitle: true,
          leadingPrimarySymbol: 'sys.symbol.calendar',
          leadingPrimaryAccessibility: '追剧日历',
          leadingSecondarySymbol: 'sys.symbol.flame',
          leadingSecondaryAccessibility: '订阅广场',
          primarySymbol: 'sys.symbol.clock',
          primaryAccessibility: '订阅历史',
          onLeadingPrimaryClick: () => {
            this.onOpenCalendar();
          },
          onLeadingSecondaryClick: () => {
            this.onOpenSquare();
          },
          onPrimaryClick: () => {
            const ht = (this.filter === '电视剧' || this.filter === '音乐') ? this.filter : '电影';
            this.onOpenHistory(ht);
          }
        })
      }

      if (this.feedbackMsg.length > 0) {
        Text(this.feedbackMsg)
          .fontSize(12)
          .fontColor('#34C759')
          .padding({ left: 16, right: 16 })
          .width('100%')
      }

      if (this.initialMode === 'calendar') {
        this.calendarListBuilder()
      } else if (this.initialMode === 'history') {
        this.subscribeHistoryBuilder()
      } else {

        if (this.mainTabIndex === 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(['全部', '电影', '电视剧', '音乐'], (tab: string) => {
                NativeAdaptivePill({
                  title: (this.loading && this.items.length === 0) ? tab : `${tab} ${this.countByType(tab)}`,
                  selected: this.filter === tab,
                  onTap: () => { this.filter = tab; }
                })
              }, (tab: string) => `${tab}_${(this.loading && this.items.length === 0) ? 'ld' : this.countByType(tab)}`)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)

          if (this.loading && this.items.length === 0) {
            HarmonyPosterRowCardGridSkeleton({
              variant: 'subscribe',
              fillViewport: true,
              bottomPadding: this.showBack ? 40 : 128
            })
          } else if (this.filteredItems().length === 0) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.bookmark')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
              Text('暂无匹配的订阅条目').fontSize(14).fontColor(mpSecondaryText(this.isDark))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Grid() {
              ForEach(this.filteredItems(), (sub: MpSubscribeItem) => {
                GridItem() {
                  Column() {
                    CinematicPanel({ panelPadding: 13, cornerRadius: 18, interactive: true }) {
                      Row({ space: 12 }) {
                        Column() {
                          if (sub.posterUrl.length > 0) {
                            MpRemoteImage({
                              src: sub.posterUrl,
                              imgWidth: 72,
                              imgHeight: 106,
                              imgRadius: 12,
                              placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                            })
                          } else {
                            Column()
                              .width(72)
                              .height(106)
                              .borderRadius(12)
                              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                          }
                        }

                        Column({ space: 6 }) {
                          Row({ space: 8 }) {
                            Text(`${sub.name}${sub.season > 0 ? ' S' + String(sub.season).padStart(2, '0') : ''}`)
                              .fontSize(15.5)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(mpPrimaryText(this.isDark))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)
                            NativeAdaptiveBadge({
                              text: sub.state === 'S' ? '已暂停' : '订阅中',
                              tintHex: sub.state === 'S' ? '#F29B38' : '#34C759'
                            })
                          }
                          .width('100%')

                        Row({ space: 6 }) {
                          Text(`${sub.year ? sub.year + ' · ' : ''}${sub.type}`)
                            .fontSize(12)
                            .fontColor(mpSecondaryText(this.isDark))
                          if (sub.vote > 0) {
                            Text(`★ ${sub.vote.toFixed(1)}`)
                              .fontSize(12)
                              .fontWeight(FontWeight.Medium)
                              .fontColor('#F2B830')
                          }
                          if (sub.downloader && sub.downloader.length > 0) {
                            HarmonyEntityLogo({
                              kind: 'downloader',
                              value: sub.downloader,
                              logoSize: 15,
                              cornerRadius: 4
                            })
                          }
                        }
                        .width('100%')

                        if (sub.totalEpisode > 0) {
                          Text(`已更新 ${RustCoreBridge.computeSubscribeProgress(sub.totalEpisode, sub.lackEpisode).label}`)
                            .fontSize(11.5)
                            .fontColor(mpSecondaryText(this.isDark))
                            .width('100%')
                          Progress({
                            value: RustCoreBridge.computeSubscribeProgress(sub.totalEpisode, sub.lackEpisode).completed,
                            total: sub.totalEpisode,
                            type: ProgressType.Linear
                          })
                            .color(this.accentHex)
                            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                        }

                        Row({ space: 6 }) {
                          Row({ space: 4 }) {
                            if (sub.state === 'S') {
                              SymbolGlyph($r('sys.symbol.play_fill'))
                                .fontSize(13)
                                .fontColor([mpPrimaryText(this.isDark)])
                            } else {
                              SymbolGlyph($r('sys.symbol.pause_fill'))
                                .fontSize(13)
                                .fontColor([mpPrimaryText(this.isDark)])
                            }
                            Text(sub.state === 'S' ? '恢复' : '暂停')
                              .fontSize(12)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(mpPrimaryText(this.isDark))
                          }
                          .padding({ left: 9, right: 10, top: 6, bottom: 6 })
                          .borderRadius(14)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                          .onClick(async () => {
                            await MoviePilotRepository.shared().toggleSubscribeState(sub);
                            await this.loadSubscriptions();
                          })

                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.folder'))
                              .fontSize(13)
                              .fontColor([mpPrimaryText(this.isDark)])
                            Text('文件')
                              .fontSize(12)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(mpPrimaryText(this.isDark))
                          }
                          .padding({ left: 9, right: 10, top: 6, bottom: 6 })
                          .borderRadius(14)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                          .accessibilityText(`查看 ${sub.name} 文件详情`)
                          .onClick(() => { this.openFilesSheet(sub); })

                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.square_and_pencil'))
                              .fontSize(13)
                              .fontColor([this.accentHex])
                            Text('编辑')
                              .fontSize(12)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(this.accentHex)
                          }
                          .padding({ left: 9, right: 10, top: 6, bottom: 6 })
                          .borderRadius(14)
                          .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '24' : '16'))
                          .onClick(() => this.openEditor(sub))

                          Blank()

                          Button({ type: ButtonType.Circle }) {
                            SymbolGlyph($r('sys.symbol.trash'))
                              .fontSize(15)
                              .fontColor(['#E84855'])
                          }
                          .width(34)
                          .height(34)
                          .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                          .accessibilityText('删除订阅')
                          .onClick(() => {
                            this.confirmDeleteSub = sub;
                            this.showDeleteConfirm = true;
                          })
                        }
                        .width('100%')
                        .margin({ top: 4 })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                  }
                  }
                  .width('100%')
                  .onClick(() => { this.openFilesSheet(sub); })
                }
              }, (sub: MpSubscribeItem) => `${sub.id}_${sub.state}_${sub.lackEpisode}`)
            }
            .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
            .columnsGap(12)
            .rowsGap(12)
            .padding({ left: 16, right: 16, top: 4, bottom: this.showBack ? 40 : 128 })
            .scrollBar(BarState.Off)
            .layoutWeight(1)
          }
        } else if (this.mainTabIndex === 1) {
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
          .padding({ left: 16, right: 16, top: 2 })

          if (this.loadingSquare) {
            if (this.squareModeIndex === 2) {
              HarmonyPosterRowCardGridSkeleton({
                variant: 'share',
                fillViewport: true,
                bottomPadding: this.showBack ? 40 : 128
              })
            } else {
              HarmonyPosterGridSkeleton({
                fillViewport: true,
                bottomPadding: this.showBack ? 40 : 128
              })
            }
          } else if (this.squareModeIndex === 0) {
            this.popularGrid(this.popularMovies)
          } else if (this.squareModeIndex === 1) {
            this.popularGrid(this.popularTvs)
          } else if (this.shares.length === 0) {
            Column({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.flame')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
              Text('暂无社区分享订阅').fontSize(14).fontColor(mpSecondaryText(this.isDark))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Grid() {
              ForEach(this.shares, (sh: MpSubscribeShareItem) => {
                GridItem() {
                  Column() {
                    CinematicPanel({ panelPadding: 13, cornerRadius: 18, interactive: true }) {
                      Row({ space: 12 }) {
                        Column() {
                          if (sh.posterUrl.length > 0) {
                            MpRemoteImage({
                              src: sh.posterUrl,
                              imgWidth: 58,
                              imgHeight: 86,
                              imgRadius: 10,
                              placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                            })
                          } else {
                            Column()
                              .width(58)
                              .height(86)
                              .borderRadius(10)
                              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                          }
                        }

                        Column({ space: 6 }) {
                          Row({ space: 6 }) {
                            Text(sh.shareTitle || sh.name)
                              .fontSize(14.5)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(mpPrimaryText(this.isDark))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)
                            if (sh.count > 0) {
                              Row({ space: 3 }) {
                                SymbolGlyph($r('sys.symbol.flame'))
                                  .fontSize(11)
                                  .fontColor(['#F29B38'])
                                Text(`${sh.count}`)
                                  .fontSize(11)
                                  .fontWeight(FontWeight.Medium)
                                  .fontColor('#F29B38')
                              }
                              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                              .borderRadius(10)
                              .backgroundColor(HarmonyAppearanceStore.withAlpha('#F29B38', this.isDark ? '26' : '16'))
                              .accessibilityText(`复用 ${sh.count} 次`)
                            }
                          }.width('100%')

                          if (sh.shareComment.length > 0) {
                            Text(sh.shareComment)
                              .fontSize(12)
                              .fontColor(mpSecondaryText(this.isDark))
                              .maxLines(2)
                              .width('100%')
                          }

                          Row({ space: 8 }) {
                            Text(`分享者：${sh.shareUser} · ${sh.type}${sh.year ? ' · ' + sh.year : ''}`)
                              .fontSize(11)
                              .fontColor(mpSecondaryText(this.isDark))
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .layoutWeight(1)

                            Row({ space: 4 }) {
                              SymbolGlyph($r('sys.symbol.plus'))
                                .fontSize(12)
                                .fontColor([Color.White])
                              Text(this.forkingShareId === sh.id ? '复用中…' : '复用订阅')
                                .fontSize(12)
                                .fontWeight(FontWeight.Bold)
                                .fontColor(Color.White)
                            }
                            .padding({ left: 10, right: 12, top: 5, bottom: 5 })
                            .borderRadius(14)
                            .backgroundColor(this.accentHex)
                            .opacity(this.forkingShareId === sh.id ? 0.6 : 1)
                            .onClick(() => {
                              if (this.forkingShareId === -1) {
                                this.pendingForkShare = sh;
                                this.showForkConfirm = true;
                              }
                            })
                          }
                          .width('100%')
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                      }.width('100%')
                    }
                  }
                  .width('100%')
                  .onClick(() => {
                    if (this.forkingShareId === -1) {
                      this.pendingForkShare = sh;
                      this.showForkConfirm = true;
                    }
                  })
                }
              }, (sh: MpSubscribeShareItem) => `${sh.id}_${sh.count}`)
            }
            .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
            .columnsGap(12)
            .rowsGap(10)
            .padding({ left: 16, right: 16, top: 6, bottom: this.showBack ? 40 : 128 })
            .scrollBar(BarState.Off)
            .layoutWeight(1)
          }
        } else {
          this.calendarListBuilder()
        }
      }

      Column().width(0).height(0).bindSheet($$this.showFilesSheet, this.filesSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp, false),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showEditor, this.editorSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showDeleteConfirm, this.deleteConfirmSheetBuilder(), {
        detents: (this.windowHeightVp > 0 && this.windowHeightVp < 500)
          ? [SheetSize.LARGE]
          : [SheetSize.FIT_CONTENT, SheetSize.MEDIUM],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showForkConfirm, this.forkConfirmSheetBuilder(), {
        detents: (this.windowHeightVp > 0 && this.windowHeightVp < 500)
          ? [SheetSize.LARGE]
          : [SheetSize.FIT_CONTENT, SheetSize.MEDIUM],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showHistoryDeleteConfirm, this.historyDeleteConfirmSheetBuilder(), {
        detents: (this.windowHeightVp > 0 && this.windowHeightVp < 500)
          ? [SheetSize.LARGE]
          : [SheetSize.FIT_CONTENT, SheetSize.MEDIUM],
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
