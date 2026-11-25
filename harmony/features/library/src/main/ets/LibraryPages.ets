import {
  RustCoreBridge,
  MoviePilotRepository,
  MpStorageFile,
  MpTransferHistoryItem,
  MpStorageConfig,
  MpDirectoryConfig,
  MpMediaItem,
  MpManualTransferPreviewItem,
  MpRemoteImage,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  HarmonyPillTabBar,
  HarmonySegmentedSwitch,
  HarmonySheetHeader,
  HarmonyEntityLogo,
  HarmonyEntityLogoPill,
  HarmonyAdaptiveLayout,
  HarmonyThemeColors,
  HarmonyAppearanceStore,
  HarmonySkeletonHost,
  HarmonySkeletonBlock,
  HarmonyCardGridSkeleton,
  HarmonyPosterRowCardGridSkeleton,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import {
  HarmonyPlaybackRequest,
  resolveLocalStrmFile,
  buildPlaybackRequestFromStreamInfo
} from '@moviepilot/media_player';

const TRANSFER_MODES: string[][] = [
  ['', '自动'],
  ['link', '硬链接'],
  ['softlink', '软链接'],
  ['copy', '复制'],
  ['move', '移动'],
  ['rclone_copy', 'Rclone 复制'],
  ['rclone_move', 'Rclone 移动']
];

const OVERWRITE_MODES: string[][] = [
  ['never', '从不覆盖'],
  ['size', '按大小覆盖'],
  ['always', '总是覆盖'],
  ['latest', '仅保留最新']
];

const MEDIA_TYPES: string[][] = [
  ['', '自动识别'],
  ['电影', '电影'],
  ['电视剧', '电视剧'],
  ['音乐', '音乐']
];

const MEDIA_SOURCES: string[][] = [
  ['', '默认数据源'],
  ['themoviedb', 'TheMovieDB'],
  ['douban', '豆瓣'],
  ['bangumi', 'Bangumi'],
  ['musicbrainz', 'MusicBrainz']
];

interface DeleteModeOption {
  label: string;
  desc: string;
  deleteSrc: boolean;
  deleteDest: boolean;
  danger: boolean;
}

const HISTORY_DELETE_MODES: DeleteModeOption[] = [
  { label: '仅删除历史记录', desc: '保留源文件与媒体库整理文件', deleteSrc: false, deleteDest: false, danger: false },
  { label: '删除历史记录及源文件', desc: '同时清理下载目录中的源文件', deleteSrc: true, deleteDest: false, danger: true },
  { label: '删除历史记录及媒体库文件', desc: '同时移除目标媒体库已整理文件', deleteSrc: false, deleteDest: true, danger: true },
  { label: '同时删除源文件与媒体库文件', desc: '彻底删除记录、源文件与媒体库文件', deleteSrc: true, deleteDest: true, danger: true }
];

/**
 * 鸿蒙多存储文件管理、整理历史与 1:1 对齐 iOS 的全量「手动识别整理」页：
 * - 文件管理搭载真实存储品牌图标（115/阿里云盘/Rclone/SMB/本地），支持系统侧滑返回上级目录；
 * - 整理历史支持点击重整理，并配备 4 模式精准删除弹窗（`DELETE /api/v1/history/transfer`）；
 * - 手动整理完整覆盖数据源与存储品牌图标及「预览整理 / 立即整理」真实提交。
 */
@Component
export struct HarmonyLibraryPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageProp('mp_file_navigate_up_req') @Watch('onExternalNavUpReq') navUpReq: number = 0;
  @Prop initialMode: string = 'files';
  @State private activeTabIdx: number = 0; // 0: 文件管理, 1: 整理历史
  @State private historyFilterIdx: number = 0; // 0: 全部, 1: 成功, 2: 失败
  @State private storages: MpStorageConfig[] = [{ name: '本地存储', type: 'local' }];
  @State private activeStorage: string = 'local';
  @State private currentPath: string = '/';
  @State private files: MpStorageFile[] = [];
  @State private history: MpTransferHistoryItem[] = [];
  @State private historyQuery: string = '';
  @State private loading: boolean = true;
  @State private notice: string = '';
  @State private playingStoragePath: string = '';

  // 整理历史 4 模式删除弹窗状态
  @State private showDeleteHistorySheet: boolean = false;
  @State private deletingHistoryItem: MpTransferHistoryItem | null = null;
  @State private deletingHistoryBusy: boolean = false;

  // 手动识别整理全量弹窗状态
  @State private showTransferSheet: boolean = false;
  @State private mtFile: MpStorageFile | null = null;
  @State private mtLogId: number | null = null;
  @State private mtSrcStorage: string = 'local';
  @State private mtSrcTitle: string = '';
  @State private mtSrcPath: string = '';
  @State private mtDirectories: MpDirectoryConfig[] = [];
  @State private mtTargetStorage: string = 'local';
  @State private mtTargetPath: string = '';
  @State private mtMatchedPathHint: string = '';
  @State private mtMatchedHistoryCount: number = 0;
  @State private mtTransferType: string = '';
  @State private mtOverwriteMode: string = 'never';
  @State private mtMediaType: string = '';
  @State private mtMediaSource: string = '';
  @State private mtMediaId: string = '';
  @State private mtSelectedMediaTitle: string = '';
  @State private mtSeason: string = '';
  @State private mtEpDetail: string = '';
  @State private mtEpFormat: string = '';
  @State private mtEpOffset: string = '';
  @State private mtEpPart: string = '';
  @State private mtEpGroup: string = '';
  @State private mtMusicType: string = '';
  @State private mtMusicMatch: string = 'strict';
  @State private mtMinFilesize: string = '0';
  @State private mtScrape: number = 0; // 0: 自动, 1: 开启, 2: 关闭
  @State private mtTypeFolder: number = 0;
  @State private mtCatFolder: number = 0;
  @State private mtReorganize: boolean = false;
  @State private mtSkipSuccess: boolean = false;
  @State private mtFromHistory: boolean = false;
  @State private mtBackground: boolean = true;
  @State private mtShowAdvanced: boolean = false;
  @State private mtShowSearch: boolean = false;
  @State private mtSearchQuery: string = '';
  @State private mtSearchResults: MpMediaItem[] = [];
  @State private mtSearching: boolean = false;
  @State private mtPreviewItems: MpManualTransferPreviewItem[] = [];
  @State private mtPreviewing: boolean = false;
  @State private mtSubmitting: boolean = false;
  @State private mtFeedback: string = '';
  @State private mtFeedbackErr: boolean = false;

  onBack: () => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  private async playStorageFileItem(
    storage: string,
    filePath: string,
    fileName: string,
    sizeBytes: number
  ): Promise<void> {
    const cleanPath = filePath.trim();
    const cleanStorage = (storage || 'local').trim();
    const displayName = fileName.trim() || cleanPath.substring(cleanPath.lastIndexOf('/') + 1) || '存储媒体';
    const kind = RustCoreBridge.detectPlayableMediaKind(displayName.includes('.') ? displayName : cleanPath);
    if (!cleanPath || !kind || this.playingStoragePath.length > 0) {
      return;
    }
    this.playingStoragePath = cleanPath;
    const subLabel = sizeBytes > 0 ? `${cleanStorage} · ${formatByteSize(sizeBytes)}` : cleanStorage;
    const repo = MoviePilotRepository.shared();

    try {
      const shouldTryTicket = cleanStorage === 'local' || (!RustCoreBridge.isStrmPath(displayName) && !RustCoreBridge.isStrmPath(cleanPath));
      if (shouldTryTicket) {
        const ticketId = await repo.createStorageStreamTicket(cleanStorage, cleanPath, displayName, kind === 'audio' ? 'audio' : 'video');
        if (ticketId.length > 0) {
          const stream = await repo.fetchVideoStreamInfo(ticketId, '');
          if (stream && stream.contentUrl.length > 0) {
            this.playingStoragePath = '';
            this.notice = '';
            this.onPlayMedia(buildPlaybackRequestFromStreamInfo(stream, displayName, subLabel));
            return;
          }
        }
      }

      this.notice = '正在缓冲下载存储媒体文件…';
      const dotIdx = displayName.lastIndexOf('.');
      const ext = dotIdx >= 0 ? displayName.substring(dotIdx) : '';
      const hostCtx = this.getUIContext().getHostContext();
      const cacheDir = hostCtx ? hostCtx.cacheDir : '';
      if (!cacheDir) {
        this.playingStoragePath = '';
        this.notice = '无法获取应用缓存目录';
        return;
      }
      const cachedPath = await repo.downloadStorageFileToCache(
        cleanStorage,
        cleanPath,
        displayName,
        ext,
        cacheDir
      );
      this.playingStoragePath = '';
      if (cachedPath.length > 0) {
        this.notice = '';
        if (RustCoreBridge.isStrmPath(displayName) || RustCoreBridge.isStrmPath(cachedPath)) {
          const strmSpec = resolveLocalStrmFile(cachedPath, true);
          if (!strmSpec) {
            this.notice = '无法解析 STRM 文件中的有效播放直链';
            return;
          }
          const stem = displayName.replace(/\.strm$/i, '') || displayName;
          this.onPlayMedia({
            url: strmSpec.url,
            headers: strmSpec.headers,
            title: stem,
            subtitle: subLabel,
            isAudio: strmSpec.mediaKind === 'audio',
            isSessionBound: false
          });
          return;
        }
        this.onPlayMedia({
          url: cachedPath,
          fdPath: cachedPath,
          cleanupTempOnClose: true,
          title: displayName,
          subtitle: subLabel,
          isAudio: kind === 'audio',
          isSessionBound: true
        });
      } else {
        this.notice = '存储媒体文件下载失败，请检查网络连接或存储配置';
      }
    } catch {
      this.playingStoragePath = '';
      this.notice = '启动存储媒体播放失败';
    }
  }

  aboutToAppear(): void {
    this.activeTabIdx = this.initialMode === 'history' ? 1 : 0;
    this.syncBackInterceptFlag();
    this.initAndLoad();
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('mp_file_can_navigate_up', false);
  }

  private syncBackInterceptFlag(): void {
    const canUp = this.activeTabIdx === 0 && this.currentPath !== '/';
    AppStorage.setOrCreate('mp_file_can_navigate_up', canUp);
  }

  onExternalNavUpReq(): void {
    if (this.activeTabIdx === 0 && this.currentPath !== '/') {
      this.navigateUpDirectory();
    }
  }

  private navigateUpDirectory(): void {
    const parts = this.currentPath.split('/').filter((p: string) => p.length > 0);
    parts.pop();
    this.currentPath = parts.length > 0 ? '/' + parts.join('/') + '/' : '/';
    this.syncBackInterceptFlag();
    this.loadData();
  }

  private async initAndLoad(): Promise<void> {
    try {
      const sts = await MoviePilotRepository.shared().fetchStorages();
      if (sts.length > 0) {
        this.storages = sts;
        if (!sts.some((s: MpStorageConfig) => s.type === this.activeStorage)) {
          this.activeStorage = sts[0].type;
        }
      }
    } catch {
      // keep default local
    }
    await this.loadData();
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    this.syncBackInterceptFlag();
    const repo = MoviePilotRepository.shared();
    try {
      if (this.activeTabIdx === 0) {
        this.files = await repo.fetchStorageFiles(this.activeStorage, this.currentPath);
      } else {
        this.history = await repo.fetchTransferHistory(1, 50);
      }
    } catch {
      // ignore
    }
    this.loading = false;
  }

  private filteredHistory(): MpTransferHistoryItem[] {
    const q = this.historyQuery.trim().toLowerCase();
    return this.history.filter((h: MpTransferHistoryItem) => {
      if (this.historyFilterIdx === 1 && !h.status) { return false; }
      if (this.historyFilterIdx === 2 && h.status) { return false; }
      if (q.length > 0 && !(`${h.title} ${h.src} ${h.dest}`.toLowerCase().includes(q))) { return false; }
      return true;
    });
  }

  private buildManualPayload(preview: boolean, onlyMatch: boolean = false): string {
    const map: Record<string, Object> = {};
    if (this.mtFile) {
      const fObj: Record<string, Object> = {};
      fObj['storage'] = this.mtFile.storage || this.mtSrcStorage;
      fObj['type'] = this.mtFile.type;
      fObj['path'] = this.mtFile.path;
      fObj['name'] = this.mtFile.name;
      fObj['size'] = this.mtFile.sizeBytes;
      if (this.mtFile.extension.length > 0) { fObj['extension'] = this.mtFile.extension; }
      map['fileitem'] = fObj;
    }
    if (this.mtLogId !== null) { map['logid'] = this.mtLogId; }
    if (this.mtTargetStorage.length > 0) { map['target_storage'] = this.mtTargetStorage; }
    if (!onlyMatch && this.mtTargetPath.trim().length > 0) { map['target_path'] = this.mtTargetPath.trim(); }
    if (this.mtMediaSource.length > 0) { map['media_source'] = this.mtMediaSource; }
    if (this.mtMediaId.trim().length > 0) { map['media_id'] = this.mtMediaId.trim(); }
    if (this.mtMediaType.length > 0) { map['type_name'] = this.mtMediaType; }
    if (this.mtMediaType === '音乐' && this.mtMusicType.length > 0) { map['music_type'] = this.mtMusicType; }
    if (this.mtMediaType === '音乐' && this.mtMusicType === 'album') { map['music_track_match'] = this.mtMusicMatch; }
    const sn = Number(this.mtSeason);
    if (this.mtSeason.trim().length > 0 && Number.isFinite(sn)) { map['season'] = Math.round(sn); }
    if (this.mtTransferType.length > 0) { map['transfer_type'] = this.mtTransferType; }
    if (this.mtOverwriteMode.length > 0) { map['overwrite_mode'] = this.mtOverwriteMode; }
    if (this.mtEpFormat.trim().length > 0) { map['episode_format'] = this.mtEpFormat.trim(); }
    if (this.mtEpDetail.trim().length > 0) { map['episode_detail'] = this.mtEpDetail.trim(); }
    if (this.mtEpPart.trim().length > 0) { map['episode_part'] = this.mtEpPart.trim(); }
    if (this.mtEpOffset.trim().length > 0) { map['episode_offset'] = this.mtEpOffset.trim(); }
    if (this.mtEpGroup.trim().length > 0) { map['episode_group'] = this.mtEpGroup.trim(); }
    map['min_filesize'] = Math.max(0, Math.round(Number(this.mtMinFilesize) || 0));
    if (this.mtScrape !== 0) { map['scrape'] = this.mtScrape === 1; }
    if (this.mtTypeFolder !== 0) { map['library_type_folder'] = this.mtTypeFolder === 1; }
    if (this.mtCatFolder !== 0) { map['library_category_folder'] = this.mtCatFolder === 1; }
    map['from_history'] = this.mtFromHistory;
    map['preview'] = preview;
    map['reorganize'] = this.mtSkipSuccess ? false : this.mtReorganize;
    map['skip_success'] = this.mtSkipSuccess;
    return JSON.stringify(map);
  }

  private async openManualTransfer(
    file: MpStorageFile | null,
    logId: number | null,
    srcStorage: string,
    srcTitle: string,
    srcPath: string
  ): Promise<void> {
    this.mtFile = file;
    this.mtLogId = logId;
    this.mtSrcStorage = srcStorage || 'local';
    this.mtSrcTitle = srcTitle;
    this.mtSrcPath = srcPath;
    this.mtTargetStorage = srcStorage || 'local';
    this.mtTargetPath = '';
    this.mtMatchedPathHint = '';
    this.mtMatchedHistoryCount = 0;
    this.mtTransferType = '';
    this.mtOverwriteMode = 'never';
    this.mtMediaType = '';
    this.mtMediaSource = '';
    this.mtMediaId = '';
    this.mtSelectedMediaTitle = '';
    this.mtSeason = '';
    this.mtEpDetail = '';
    this.mtEpFormat = '';
    this.mtEpOffset = '';
    this.mtEpPart = '';
    this.mtEpGroup = '';
    this.mtMusicType = '';
    this.mtMusicMatch = 'strict';
    this.mtMinFilesize = '0';
    this.mtScrape = 0;
    this.mtTypeFolder = 0;
    this.mtCatFolder = 0;
    this.mtReorganize = false;
    this.mtSkipSuccess = false;
    this.mtFromHistory = logId !== null;
    this.mtBackground = true;
    this.mtShowAdvanced = false;
    this.mtShowSearch = false;
    this.mtSearchQuery = srcTitle.split('.')[0].substring(0, 24);
    this.mtSearchResults = [];
    this.mtPreviewItems = [];
    this.mtFeedback = '';
    this.mtFeedbackErr = false;
    this.showTransferSheet = true;

    const repo = MoviePilotRepository.shared();
    try {
      this.mtDirectories = await repo.fetchDirectories();
      const matchPayload = this.buildManualPayload(false, true);
      const res = await Promise.all([
        repo.matchManualTransferTargetPath(matchPayload),
        repo.matchManualTransferHistory(matchPayload)
      ]);
      if (res[0]) {
        if (res[0].targetStorage.length > 0) { this.mtTargetStorage = res[0].targetStorage; }
        if (res[0].targetPath.length > 0) {
          this.mtMatchedPathHint = res[0].targetPath;
          this.mtTargetPath = res[0].targetPath;
        }
        if (res[0].transferType.length > 0) { this.mtTransferType = res[0].transferType; }
        if (res[0].overwriteMode.length > 0) { this.mtOverwriteMode = res[0].overwriteMode; }
      }
      if (res[1]) {
        this.mtMatchedHistoryCount = res[1].historyCount;
        if (res[1].reorganize) { this.mtReorganize = true; }
      }
    } catch {
      // keep manual defaults
    }
  }

  private triStateLabel(state: number): string {
    if (state === 1) { return '开启'; }
    if (state === 2) { return '关闭'; }
    return '自动';
  }

  @Builder
  deleteHistorySheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '删除整理历史',
        cancelText: '取消',
        onCancel: () => { this.showDeleteHistorySheet = false; }
      })
      if (this.deletingHistoryItem) {
        Text(`「${this.deletingHistoryItem.title}」· 请选择删除范围：`)
          .fontSize(13)
          .fontColor(mpSecondaryText(this.isDark))
          .maxLines(2)
          .width('100%')
      }

      Scroll() {
        Column({ space: 10 }) {
          ForEach(HISTORY_DELETE_MODES, (opt: DeleteModeOption) => {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                Row({ space: 10 }) {
                  SymbolGlyph($r('sys.symbol.trash'))
                    .fontSize(18)
                    .fontColor([opt.danger ? '#E84855' : this.accentHex])
                  Column({ space: 3 }) {
                    Text(opt.label)
                      .fontSize(14.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(opt.danger ? '#E84855' : mpPrimaryText(this.isDark))
                      .width('100%')
                    Text(opt.desc)
                      .fontSize(11.5)
                      .fontColor(mpSecondaryText(this.isDark))
                      .width('100%')
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
              }
            }
            .width('100%')
            .opacity(this.deletingHistoryBusy ? 0.55 : 1)
            .onClick(async () => {
              const target = this.deletingHistoryItem;
              if (!target || this.deletingHistoryBusy) { return; }
              this.deletingHistoryBusy = true;
              const ok = await MoviePilotRepository.shared().deleteTransferHistory(target, opt.deleteSrc, opt.deleteDest);
              this.deletingHistoryBusy = false;
              this.showDeleteHistorySheet = false;
              this.notice = ok ? `已执行「${opt.label}」` : '删除整理记录失败';
              if (ok) {
                await this.loadData();
              }
            })
          }, (opt: DeleteModeOption) => opt.label)
        }
        .width('100%')
        .padding({ bottom: 20 })
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
  manualTransferSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '手动识别整理',
        cancelText: '关闭',
        onCancel: () => { this.showTransferSheet = false; }
      })

      Scroll() {
        Column({ space: 12 }) {
          CinematicPanel({ panelPadding: 13, cornerRadius: 16 }) {
            Column({ space: 4 }) {
              Text(this.mtSrcTitle).fontSize(14.5).fontWeight(FontWeight.Bold)
                .fontColor(mpPrimaryText(this.isDark)).maxLines(2).width('100%')
              Row({ space: 6 }) {
                HarmonyEntityLogo({
                  kind: 'storage',
                  value: this.mtSrcStorage,
                  logoSize: 15,
                  cornerRadius: 4
                })
                Text(`${this.mtSrcStorage} · ${this.mtSrcPath}`).fontSize(11.5)
                  .fontColor(mpSecondaryText(this.isDark)).maxLines(2).layoutWeight(1)
              }.width('100%')
              if (this.mtMatchedHistoryCount > 0) {
                NativeAdaptiveBadge({ text: `已匹配历史整理 ${this.mtMatchedHistoryCount} 条`, tintHex: '#F29B38' })
              }
            }.alignItems(HorizontalAlign.Start)
          }

          // 1. 目标存储与路径（搭载存储品牌图标）
          Text('目标存储').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(this.storages, (st: MpStorageConfig) => {
              HarmonyEntityLogoPill({
                kind: 'storage',
                value: st.type,
                title: st.name || st.type,
                selected: this.mtTargetStorage === st.type,
                onTap: () => { this.mtTargetStorage = st.type; }
              })
            }, (st: MpStorageConfig) => `mt_st_${st.type}`)
          }.width('100%')

          if (this.mtDirectories.length > 0) {
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
              ForEach(this.mtDirectories, (d: MpDirectoryConfig) => {
                if (d.libraryPath.length > 0) {
                  HarmonyEntityLogoPill({
                    kind: 'storage',
                    value: d.libraryStorage || d.storage || 'local',
                    title: d.name,
                    selected: this.mtTargetPath === d.libraryPath,
                    onTap: () => {
                      this.mtTargetStorage = d.libraryStorage || this.mtTargetStorage;
                      this.mtTargetPath = d.libraryPath;
                    }
                  })
                }
              }, (d: MpDirectoryConfig) => `mt_dir_${d.name}`)
            }.width('100%')
          }

          Text(this.mtMatchedPathHint.length > 0 ? `目标路径（自动匹配：${this.mtMatchedPathHint}）` : '目标路径（留空自动匹配）')
            .fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
          TextInput({ placeholder: '/video/', text: this.mtTargetPath })
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
            .onChange((v: string) => { this.mtTargetPath = v; })

          // 2. 整理方式 & 覆盖模式
          Text('整理方式').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
            ForEach(TRANSFER_MODES, (m: string[]) => {
              NativeAdaptivePill({
                title: m[1],
                selected: this.mtTransferType === m[0],
                onTap: () => { this.mtTransferType = m[0]; }
              })
            }, (m: string[]) => `tm_${m[0]}`)
          }.width('100%')

          Text('覆盖模式').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
            ForEach(OVERWRITE_MODES, (m: string[]) => {
              NativeAdaptivePill({
                title: m[1],
                selected: this.mtOverwriteMode === m[0],
                onTap: () => { this.mtOverwriteMode = m[0]; }
              })
            }, (m: string[]) => `om_${m[0]}`)
          }.width('100%')

          // 3. 媒体识别与数据源品牌图标
          Text('媒体识别').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
            ForEach(MEDIA_TYPES, (m: string[]) => {
              NativeAdaptivePill({
                title: m[1],
                selected: this.mtMediaType === m[0],
                onTap: () => { this.mtMediaType = m[0]; }
              })
            }, (m: string[]) => `mty_${m[0]}`)
          }.width('100%')

          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
            ForEach(MEDIA_SOURCES, (s: string[]) => {
              if (s[0].length === 0) {
                NativeAdaptivePill({
                  title: s[1],
                  selected: this.mtMediaSource === s[0],
                  onTap: () => { this.mtMediaSource = s[0]; }
                })
              } else {
                HarmonyEntityLogoPill({
                  kind: 'media_source',
                  value: s[0],
                  title: s[1],
                  selected: this.mtMediaSource === s[0],
                  onTap: () => { this.mtMediaSource = s[0]; }
                })
              }
            }, (s: string[]) => `msrc_${s[0]}`)
          }.width('100%')

          Row({ space: 8 }) {
            TextInput({ placeholder: '指定媒体 ID（留空自动识别）', text: this.mtMediaId })
              .layoutWeight(1)
              .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
              .onChange((v: string) => { this.mtMediaId = v; })
            Button(this.mtShowSearch ? '收起搜索' : '在线搜片')
              .height(40).padding({ left: 12, right: 12 }).borderRadius(14).fontSize(12.5)
              .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '2C' : '1A'))
              .fontColor(this.accentHex)
              .onClick(() => { this.mtShowSearch = !this.mtShowSearch; })
          }.width('100%')

          if (this.mtSelectedMediaTitle.length > 0) {
            Text(`已指定媒体：${this.mtSelectedMediaTitle} (${this.mtMediaId})`)
              .fontSize(12).fontColor('#34C759').width('100%')
          }

          if (this.mtShowSearch) {
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  TextInput({ placeholder: '输入片名检索 TMDB / 豆瓣 / Bangumi ID…', text: this.mtSearchQuery })
                    .layoutWeight(1)
                    .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtSearchQuery = v; })
                  Button(this.mtSearching ? '…' : '搜索')
                    .height(38).borderRadius(12).backgroundColor(this.accentHex).fontColor(Color.White).fontSize(12.5)
                    .onClick(async () => {
                      if (this.mtSearchQuery.trim().length === 0) { return; }
                      this.mtSearching = true;
                      this.mtSearchResults = (await MoviePilotRepository.shared().searchMedia(
                        this.mtSearchQuery,
                        this.mtMediaType === '音乐' ? 'music' : 'media',
                        this.mtMediaSource
                      )).slice(0, 6);
                      this.mtSearching = false;
                    })
                }.width('100%')

                if (this.mtSearching) {
                  HarmonySkeletonHost({ loadingLabel: '正在检索匹配媒体' }) {
                    Column({ space: 8 }) {
                      ForEach([0, 1, 2], (idx: number) => {
                        Row({ space: 10 }) {
                          HarmonySkeletonBlock({ blockWidth: 36, blockHeight: 52, cornerRadius: 6, shimmerSweep: true })
                          Column({ space: 5 }) {
                            HarmonySkeletonBlock({ blockWidth: '64%', blockHeight: 13, cornerRadius: 4 })
                            HarmonySkeletonBlock({ blockWidth: '46%', blockHeight: 11, cornerRadius: 4, tone: 'subtle' })
                          }
                          .layoutWeight(1)
                          .alignItems(HorizontalAlign.Start)
                          HarmonySkeletonBlock({ blockWidth: 32, blockHeight: 16, cornerRadius: 5, tone: 'subtle' })
                        }
                        .width('100%')
                        .padding({ top: 4, bottom: 4 })
                      }, (idx: number) => `mt_srch_sk_${idx}`)
                    }
                    .width('100%')
                  }
                } else {
                  ForEach(this.mtSearchResults, (m: MpMediaItem) => {
                    Row({ space: 10 }) {
                      if (m.posterUrl.length > 0) {
                        MpRemoteImage({
                          src: m.posterUrl,
                          imgWidth: 36,
                          imgHeight: 52,
                          imgRadius: 6,
                          placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                        })
                      }
                      Column({ space: 2 }) {
                        Text(m.title).fontSize(13).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).maxLines(1)
                        Text(`${m.type}${m.year ? ' · ' + m.year : ''} · ID: ${m.tmdbId || m.doubanId || m.mediaId || m.id}`)
                          .fontSize(11).fontColor(mpSecondaryText(this.isDark))
                      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                      Text('选用').fontSize(12).fontColor(this.accentHex).fontWeight(FontWeight.Bold)
                    }
                    .width('100%').padding({ top: 4, bottom: 4 })
                    .onClick(() => {
                      this.mtMediaId = m.tmdbId || m.doubanId || m.mediaId || m.id;
                      this.mtMediaSource = m.tmdbId ? 'themoviedb' : (m.doubanId ? 'douban' : (m.source || this.mtMediaSource));
                      if (m.type === '电影' || m.type === '电视剧' || m.type === '音乐') { this.mtMediaType = m.type; }
                      this.mtSelectedMediaTitle = m.title;
                      this.mtShowSearch = false;
                    })
                  }, (m: MpMediaItem) => `mts_${m.id}`)
                }
              }
            }
          }

          // 4. 剧集 / 音乐专属参数
          if (this.mtMediaType === '电视剧') {
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Column({ space: 8 }) {
                Text('剧集精细参数').fontSize(13).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
                Row({ space: 8 }) {
                  TextInput({ placeholder: '季数 (如 1)', text: this.mtSeason }).type(InputType.Number).layoutWeight(1)
                    .fontColor(mpPrimaryText(this.isDark)).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtSeason = v; })
                  TextInput({ placeholder: '指定集 (如 1,2-5)', text: this.mtEpDetail }).layoutWeight(1)
                    .fontColor(mpPrimaryText(this.isDark)).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtEpDetail = v; })
                }.width('100%')
                Row({ space: 8 }) {
                  TextInput({ placeholder: '集匹配格式 (如 {ep})', text: this.mtEpFormat }).layoutWeight(1)
                    .fontColor(mpPrimaryText(this.isDark)).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtEpFormat = v; })
                  TextInput({ placeholder: '集偏移 (如 EP+12)', text: this.mtEpOffset }).layoutWeight(1)
                    .fontColor(mpPrimaryText(this.isDark)).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtEpOffset = v; })
                }.width('100%')
                Row({ space: 8 }) {
                  TextInput({ placeholder: '分段 (如 part1)', text: this.mtEpPart }).layoutWeight(1)
                    .fontColor(mpPrimaryText(this.isDark)).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtEpPart = v; })
                  TextInput({ placeholder: '剧集组 ID', text: this.mtEpGroup }).layoutWeight(1)
                    .fontColor(mpPrimaryText(this.isDark)).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtEpGroup = v; })
                }.width('100%')
              }
            }
          } else if (this.mtMediaType === '音乐') {
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Column({ space: 8 }) {
                Text('音乐整理参数').fontSize(13).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
                Row({ space: 8 }) {
                  NativeAdaptivePill({ title: '自动', selected: this.mtMusicType === '', onTap: () => { this.mtMusicType = ''; } })
                  NativeAdaptivePill({ title: '专辑', selected: this.mtMusicType === 'album', onTap: () => { this.mtMusicType = 'album'; } })
                  NativeAdaptivePill({ title: '单曲', selected: this.mtMusicType === 'track', onTap: () => { this.mtMusicType = 'track'; } })
                }.width('100%')
                if (this.mtMusicType === 'album') {
                  Row({ space: 8 }) {
                    NativeAdaptivePill({ title: '严格曲目匹配', selected: this.mtMusicMatch === 'strict', onTap: () => { this.mtMusicMatch = 'strict'; } })
                    NativeAdaptivePill({ title: '宽松匹配', selected: this.mtMusicMatch === 'loose', onTap: () => { this.mtMusicMatch = 'loose'; } })
                  }.width('100%')
                }
              }
            }
          }

          // 5. 高级三态开关与策略折叠区
          Row() {
            Text('高级选项（刮削、分类目录、体积与重整理）')
              .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(this.accentHex).layoutWeight(1)
            SymbolGlyph($r(this.mtShowAdvanced ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
              .fontSize(16).fontColor([this.accentHex])
          }
          .width('100%').padding({ top: 6, bottom: 4 })
          .onClick(() => { this.mtShowAdvanced = !this.mtShowAdvanced; })

          if (this.mtShowAdvanced) {
            CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
              Column({ space: 10 }) {
                Row() {
                  Text('自动刮削元数据').fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  NativeAdaptivePill({
                    title: this.triStateLabel(this.mtScrape),
                    selected: this.mtScrape !== 0,
                    onTap: () => { this.mtScrape = (this.mtScrape + 1) % 3; }
                  })
                }.width('100%')
                Row() {
                  Text('按媒体类型分类目录').fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  NativeAdaptivePill({
                    title: this.triStateLabel(this.mtTypeFolder),
                    selected: this.mtTypeFolder !== 0,
                    onTap: () => { this.mtTypeFolder = (this.mtTypeFolder + 1) % 3; }
                  })
                }.width('100%')
                Row() {
                  Text('按二级分类创建目录').fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  NativeAdaptivePill({
                    title: this.triStateLabel(this.mtCatFolder),
                    selected: this.mtCatFolder !== 0,
                    onTap: () => { this.mtCatFolder = (this.mtCatFolder + 1) % 3; }
                  })
                }.width('100%')

                Divider().color(HarmonyThemeColors.divider(this.isDark))

                Row({ space: 8 }) {
                  Text('最小文件体积 (MB)').fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  TextInput({ placeholder: '0', text: this.mtMinFilesize })
                    .type(InputType.Number).width(92)
                    .fontColor(mpPrimaryText(this.isDark)).backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(10)
                    .onChange((v: string) => { this.mtMinFilesize = v; })
                }.width('100%')

                Row() {
                  Text('跳过已成功整理文件').fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.mtSkipSuccess })
                    .selectedColor(this.accentHex).onChange((v: boolean) => { this.mtSkipSuccess = v; })
                }.width('100%')
                Row() {
                  Text('重新整理已有历史记录').fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.mtReorganize })
                    .selectedColor(this.accentHex).onChange((v: boolean) => { this.mtReorganize = v; })
                }.width('100%')
                Row() {
                  Text('提交至后台队列执行').fontSize(13.5).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.mtBackground })
                    .selectedColor(this.accentHex).onChange((v: boolean) => { this.mtBackground = v; })
                }.width('100%')
              }
            }
          }

          if (this.mtFeedback.length > 0) {
            Text(this.mtFeedback)
              .fontSize(12.5)
              .fontColor(this.mtFeedbackErr ? '#E84855' : '#34C759')
              .width('100%')
          }

          if (this.mtPreviewItems.length > 0) {
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Column({ space: 8 }) {
                Text(`整理路径预览 (${this.mtPreviewItems.length})`)
                  .fontSize(13.5).fontWeight(FontWeight.Bold).fontColor(this.accentHex).width('100%')
                ForEach(this.mtPreviewItems.slice(0, 12), (pv: MpManualTransferPreviewItem, idx: number) => {
                  Column({ space: 2 }) {
                    if (pv.title.length > 0) {
                      Text(pv.title).fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark)).width('100%')
                    }
                    Text(`→ ${pv.dest || pv.src}`).fontSize(11).fontColor('#34C759').maxLines(2).width('100%')
                  }.width('100%')
                }, (_pv: MpManualTransferPreviewItem, idx: number) => `pv_${idx}`)
              }
            }
          }
        }.padding({ bottom: 16 })
      }.scrollBar(BarState.Off).layoutWeight(1)

      Row({ space: 10 }) {
        Button(this.mtPreviewing ? '预览中…' : '预览整理')
          .layoutWeight(1).height(46).borderRadius(23)
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          .fontColor(mpPrimaryText(this.isDark)).fontWeight(FontWeight.Medium)
          .enabled(!this.mtPreviewing && !this.mtSubmitting)
          .onClick(async () => {
            this.mtPreviewing = true;
            this.mtFeedback = '';
            const res = await MoviePilotRepository.shared().executeManualTransfer(this.buildManualPayload(true), false);
            this.mtPreviewing = false;
            this.mtPreviewItems = res.previewItems;
            this.mtFeedback = res.previewItems.length > 0 ? `已生成 ${res.previewItems.length} 条目标路径预览` : res.message;
            this.mtFeedbackErr = !res.success;
          })

        Button(this.mtSubmitting ? '提交中…' : '立即整理')
          .layoutWeight(1).height(46).borderRadius(23)
          .backgroundColor(this.accentHex)
          .fontColor(Color.White).fontWeight(FontWeight.Bold)
          .enabled(!this.mtPreviewing && !this.mtSubmitting)
          .onClick(async () => {
            this.mtSubmitting = true;
            this.mtFeedback = '';
            const res = await MoviePilotRepository.shared().executeManualTransfer(this.buildManualPayload(false), this.mtBackground);
            this.mtSubmitting = false;
            if (res.success) {
              this.showTransferSheet = false;
              this.notice = res.message || '手动整理任务已提交';
              if (this.activeTabIdx === 1) { await this.loadData(); }
            } else {
              this.mtFeedback = res.message;
              this.mtFeedbackErr = true;
            }
          })
      }.width('100%')
    }.padding(20).width('100%').height('100%')
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: this.activeTabIdx === 0
          ? (this.loading ? '文件管理' : `文件管理 (${this.files.length})`)
          : (this.loading ? '整理历史' : `整理历史 (${this.history.length})`),
        trailingSymbol: 'sys.symbol.arrow_clockwise',
        trailingAccessibility: '刷新列表',
        onBack: () => {
          if (this.activeTabIdx === 0 && this.currentPath !== '/') {
            this.navigateUpDirectory();
          } else {
            this.onBack();
          }
        },
        onTrailingClick: () => this.loadData()
      })

      HarmonyPillTabBar({
        tabs: ['文件管理', '整理历史'],
        selectedIndex: this.activeTabIdx,
        onSelect: (idx: number) => {
          this.activeTabIdx = idx;
          this.syncBackInterceptFlag();
          this.loadData();
        }
      })

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#34C759').padding({ left: 16, right: 16 }).width('100%')
      }

      if (this.activeTabIdx === 0) {
        // 多存储切换胶囊行（搭载真实存储品牌图标）
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.storages, (st: MpStorageConfig) => {
              HarmonyEntityLogoPill({
                kind: 'storage',
                value: st.type,
                title: st.name,
                selected: this.activeStorage === st.type,
                onTap: () => {
                  this.activeStorage = st.type;
                  this.currentPath = '/';
                  this.syncBackInterceptFlag();
                  this.loadData();
                }
              })
            }, (st: MpStorageConfig) => `lib_st_${st.type}`)
          }.padding({ left: 16, right: 16 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

        Row({ space: 8 }) {
          Text(this.currentPath)
            .fontSize(12).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.currentPath !== '/') {
            Text('返回上级')
              .fontSize(12.5).fontWeight(FontWeight.Bold).fontColor(this.accentHex)
              .onClick(() => this.navigateUpDirectory())
          }
        }.width('100%').padding({ left: 16, right: 16 })
      } else {
        Row() {
          TextInput({ placeholder: '搜索片名或路径…', text: this.historyQuery })
            .width('100%')
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(16)
            .onChange((v: string) => { this.historyQuery = v; })
        }.padding({ left: 16, right: 16 })

        Column() {
          HarmonySegmentedSwitch({
            options: ['全部', '成功', '失败'],
            selectedIndex: this.historyFilterIdx,
            onSelect: (idx: number) => { this.historyFilterIdx = idx; }
          })
        }.padding({ left: 16, right: 16 })
      }

      if (this.loading) {
        if (this.activeTabIdx === 0) {
          HarmonyCardGridSkeleton({
            variant: 'file',
            fillViewport: true,
            bottomPadding: 40
          })
        } else {
          HarmonyPosterRowCardGridSkeleton({
            variant: 'history',
            fillViewport: true,
            bottomPadding: 40
          })
        }
      } else if (this.activeTabIdx === 0 && this.files.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
          Text('当前目录为空').fontSize(14).fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.activeTabIdx === 1 && this.filteredHistory().length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.clock')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
          Text('暂无匹配的整理历史记录').fontSize(14).fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          if (this.activeTabIdx === 0) {
            ForEach(this.files, (f: MpStorageFile) => {
              GridItem() {
                Column() {
                  CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                    Row({ space: 10 }) {
                      SymbolGlyph($r(f.type === 'dir' ? 'sys.symbol.folder_fill' : 'sys.symbol.doc_text'))
                        .fontSize(22)
                        .fontColor([f.type === 'dir' ? '#F29B38' : this.accentHex])
                      Column({ space: 3 }) {
                        Text(f.name)
                          .fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(f.type === 'dir' ? '目录' : formatByteSize(f.sizeBytes))
                          .fontSize(11).fontColor(mpSecondaryText(this.isDark))
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

                      if (f.type !== 'dir' && RustCoreBridge.detectPlayableMediaKind(f.name).length > 0) {
                        NativeAdaptivePill({
                          title: this.playingStoragePath === f.path ? '缓冲中…' : '播放',
                          selected: this.playingStoragePath === f.path,
                          onTap: () => {
                            this.playStorageFileItem(
                              f.storage || this.activeStorage,
                              f.path,
                              f.name,
                              f.sizeBytes
                            ).catch(() => {});
                          }
                        })
                      }

                      NativeAdaptivePill({
                        title: '整理',
                        selected: false,
                        onTap: () => this.openManualTransfer(f, null, this.activeStorage, f.name, f.path)
                      })
                    }.width('100%')
                  }
                }
                .width('100%')
                .onClick(() => {
                  if (f.type === 'dir') {
                    this.currentPath = f.path.endsWith('/') ? f.path : f.path + '/';
                    this.syncBackInterceptFlag();
                    this.loadData();
                  } else if (RustCoreBridge.detectPlayableMediaKind(f.name).length > 0) {
                    this.playStorageFileItem(
                      f.storage || this.activeStorage,
                      f.path,
                      f.name,
                      f.sizeBytes
                    ).catch(() => {});
                  } else {
                    this.openManualTransfer(f, null, this.activeStorage, f.name, f.path);
                  }
                })
              }
            }, (f: MpStorageFile) => `${f.storage}_${f.path}`)
          } else {
            ForEach(this.filteredHistory(), (h: MpTransferHistoryItem) => {
              GridItem() {
                CinematicPanel({ panelPadding: 13, cornerRadius: 18 }) {
                  Row({ space: 12 }) {
                    Column() {
                      if (h.posterUrl.length > 0) {
                        MpRemoteImage({
                          src: h.posterUrl,
                          imgWidth: 58,
                          imgHeight: 84,
                          imgRadius: 10,
                          placeholderColor: HarmonyThemeColors.chipFill(this.isDark)
                        })
                      } else {
                        Column()
                          .width(58)
                          .height(84)
                          .borderRadius(10)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      }
                    }
                    .onClick(() => this.openManualTransfer(null, h.id, h.srcStorage, h.title, h.src))

                    Column({ space: 5 }) {
                      Row({ space: 6 }) {
                        Text(`${h.title}${h.seasons ? ' ' + h.seasons : ''}${h.episodes ? h.episodes : ''}`)
                          .fontSize(14.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                          .onClick(() => this.openManualTransfer(null, h.id, h.srcStorage, h.title, h.src))
                        NativeAdaptiveBadge({
                          text: h.status ? '成功' : '失败',
                          tintHex: h.status ? '#34C759' : '#E84855'
                        })
                      }.width('100%')

                      Text(`${h.mode} · ${h.date}`).fontSize(11).fontColor(mpSecondaryText(this.isDark)).width('100%')

                      Row({ space: 5 }) {
                        HarmonyEntityLogo({ kind: 'storage', value: h.srcStorage, logoSize: 13, cornerRadius: 3 })
                        Text(`${h.srcStorage}：${h.src}`)
                          .fontSize(11).fontColor(mpSecondaryText(this.isDark))
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      }.width('100%')

                      Row({ space: 5 }) {
                        HarmonyEntityLogo({ kind: 'storage', value: h.destStorage, logoSize: 13, cornerRadius: 3 })
                        Text(`${h.destStorage}：${h.dest}`)
                          .fontSize(11).fontColor(this.accentHex)
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      }.width('100%')

                      Row({ space: 8 }) {
                        if (h.status && h.dest.length > 0 && RustCoreBridge.detectPlayableMediaKind(h.dest).length > 0) {
                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(12).fontColor([Color.White])
                            Text(this.playingStoragePath === h.dest ? '缓冲中…' : '播放')
                              .fontSize(12)
                              .fontWeight(FontWeight.Bold)
                              .fontColor(Color.White)
                          }
                          .padding({ left: 10, right: 11, top: 5, bottom: 5 })
                          .borderRadius(12)
                          .backgroundColor(this.accentHex)
                          .onClick(() => {
                            const slashIdx = h.dest.lastIndexOf('/');
                            const destName = slashIdx >= 0 ? h.dest.substring(slashIdx + 1) : h.title;
                            this.playStorageFileItem(
                              h.destStorage || 'local',
                              h.dest,
                              destName || h.title,
                              0
                            ).catch(() => {});
                          })
                        }

                        Row({ space: 4 }) {
                          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(12).fontColor([this.accentHex])
                          Text('重新整理').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.accentHex)
                        }
                        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                        .borderRadius(12)
                        .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '24' : '16'))
                        .onClick(() => this.openManualTransfer(null, h.id, h.srcStorage, h.title, h.src))

                        Blank()

                        Button({ type: ButtonType.Circle }) {
                          SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor(['#E84855'])
                        }
                        .width(32)
                        .height(32)
                        .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                        .accessibilityText('删除整理记录')
                        .onClick(() => {
                          this.deletingHistoryItem = h;
                          this.showDeleteHistorySheet = true;
                        })
                      }.width('100%').margin({ top: 2 })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  }.width('100%')
                }
              }
            }, (h: MpTransferHistoryItem) => String(h.id))
          }
        }
        .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
        .columnsGap(10)
        .rowsGap(10)
        .padding({ left: 16, right: 16, bottom: 40 })
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }

      Blank().width(0).height(0).bindSheet($$this.showTransferSheet, this.manualTransferSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showDeleteHistorySheet, this.deleteHistorySheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
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
