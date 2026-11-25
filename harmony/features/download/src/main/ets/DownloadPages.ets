import {
  RustCoreBridge,
  MoviePilotRepository,
  MpResourceItem,
  MpDownloadTask,
  MpSiteItem,
  MpServiceConfig,
  MpDirectoryConfig,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  HarmonySheetHeader,
  HarmonyEntityLogo,
  HarmonyEntityLogoPill,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  HarmonySkeletonHost,
  HarmonySkeletonBlock,
  HarmonyCardGridSkeleton,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

const SORT_MODES: string[][] = [
  ['seeders', '做种最多'],
  ['size', '体积最大'],
  ['pubdate', '最新发布'],
  ['site', '站点排序']
];

const RES_FILTER_OPTIONS: string[] = ['2160p', '1080p', '720p'];
const PROMO_FILTER_OPTIONS: string[] = ['免费', '2X免费', '50%', '30%'];
const QUALITY_FILTER_OPTIONS: string[] = ['BluRay', 'REMUX', 'WEB-DL', 'HDTV'];
const ENCODE_FILTER_OPTIONS: string[] = ['H265', 'H264', 'HEVC', 'AV1'];

/**
 * 鸿蒙「站点资源」页（对齐 iOS 多选站点、Rust 9 维筛选分组与真实下载器/保存目录选择）：
 * - 关键词搜索 + 多选站点弹窗（展示真实 `/api/v1/site/icon/{id}` 图标）；
 * - 委托 `RustCoreBridge.filterAndGroupResources` 执行多维过滤排序；
 * - 推送下载弹窗支持选择已配置的下载器与目标保存目录（`POST /api/v1/download/add`）。
 */
@Component
export struct HarmonyResourceSearchPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @Prop initialKeyword: string = '';
  @State private keyword: string = '';
  @State private sites: MpSiteItem[] = [];
  @State private selectedSiteIds: number[] = [];
  @State private resources: MpResourceItem[] = [];
  @State private loading: boolean = true;
  @State private notice: string = '';

  // 排序与多维筛选
  @State private sortKey: string = 'seeders';
  @State private filterSites: string[] = [];
  @State private filterResolutions: string[] = [];
  @State private filterPromos: string[] = [];
  @State private filterQualities: string[] = [];
  @State private filterEncodes: string[] = [];

  // 弹层状态
  @State private showSiteSheet: boolean = false;
  @State private showSortSheet: boolean = false;
  @State private showFilterSheet: boolean = false;
  @State private showDownloadSheet: boolean = false;
  @State private selectedItem: MpResourceItem | null = null;
  @State private downloaders: MpServiceConfig[] = [];
  @State private directories: MpDirectoryConfig[] = [];
  @State private selectedDownloader: string = '';
  @State private savePath: string = '';
  @State private pushing: boolean = false;

  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.keyword = this.initialKeyword;
    this.initData();
  }

  private async initData(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchSites(),
        repo.fetchDownloaders(),
        repo.fetchDirectories(),
        this.keyword.trim().length > 0
          ? repo.searchSiteResources(this.keyword, [])
          : repo.fetchCachedResources()
      ]);
      this.sites = res[0].filter((s: MpSiteItem) => s.isActive);
      this.downloaders = res[1].filter((d: MpServiceConfig) => d.enabled);
      this.directories = res[2].filter((dir: MpDirectoryConfig) =>
        dir.downloadPath.trim().length > 0 || dir.libraryPath.trim().length > 0
      );
      if (this.downloaders.length > 0) {
        const def = this.downloaders.find((d: MpServiceConfig) => d.isDefault);
        this.selectedDownloader = def ? def.name : this.downloaders[0].name;
      }
      this.resources = res[3];
    } catch {
      this.resources = [];
    }
    this.loading = false;
  }

  private async runSearch(): Promise<void> {
    this.loading = true;
    this.notice = '';
    try {
      this.resources = await MoviePilotRepository.shared().searchSiteResources(this.keyword, this.selectedSiteIds);
    } catch {
      this.resources = [];
    }
    this.loading = false;
  }

  private sortLabel(): string {
    const found = SORT_MODES.find((m: string[]) => m[0] === this.sortKey);
    return found ? found[1] : '做种最多';
  }

  private activeFilterCount(): number {
    return this.filterSites.length + this.filterResolutions.length +
      this.filterPromos.length + this.filterQualities.length + this.filterEncodes.length;
  }

  private siteIconForName(siteName: string): string {
    const found = this.sites.find((s: MpSiteItem) => s.name === siteName);
    return found ? found.iconDataUri : '';
  }

  private resultSiteNames(): string[] {
    const set = new Set<string>();
    for (let i = 0; i < this.resources.length; i++) {
      const n = this.resources[i].siteName.trim();
      if (n.length > 0) { set.add(n); }
    }
    return Array.from(set).sort();
  }

  private toggleInList(list: string[], val: string): string[] {
    if (list.includes(val)) {
      return list.filter((x: string) => x !== val);
    }
    return [...list, val];
  }

  private clearAllFilters(): void {
    this.filterSites = [];
    this.filterResolutions = [];
    this.filterPromos = [];
    this.filterQualities = [];
    this.filterEncodes = [];
  }

  private applyLocalFilterAndSort(source: MpResourceItem[]): MpResourceItem[] {
    const out = source.filter((r: MpResourceItem) => {
      if (this.filterSites.length > 0 && !this.filterSites.includes(r.siteName)) { return false; }
      const hay = `${r.title} ${r.resolution} ${r.resourceType} ${r.videoEncode} ${r.volumeFactor}`.toLowerCase();
      if (this.filterResolutions.length > 0 && !this.filterResolutions.some((x: string) => hay.includes(x.toLowerCase()))) {
        return false;
      }
      if (this.filterPromos.length > 0 && !this.filterPromos.some((x: string) => (r.volumeFactor || '').includes(x))) {
        return false;
      }
      if (this.filterQualities.length > 0 && !this.filterQualities.some((x: string) => hay.includes(x.toLowerCase()))) {
        return false;
      }
      if (this.filterEncodes.length > 0 && !this.filterEncodes.some((x: string) => hay.includes(x.toLowerCase()))) {
        return false;
      }
      return true;
    });
    const sorted = [...out];
    if (this.sortKey === 'size') {
      sorted.sort((a: MpResourceItem, b: MpResourceItem) => b.sizeBytes - a.sizeBytes);
    } else if (this.sortKey === 'pubdate') {
      sorted.sort((a: MpResourceItem, b: MpResourceItem) => (b.pubdate ?? '').localeCompare(a.pubdate ?? ''));
    } else if (this.sortKey === 'site') {
      sorted.sort((a: MpResourceItem, b: MpResourceItem) => a.siteName.localeCompare(b.siteName));
    } else {
      sorted.sort((a: MpResourceItem, b: MpResourceItem) => b.seeders - a.seeders);
    }
    return sorted;
  }

  private filteredResources(): MpResourceItem[] {
    if (this.resources.length === 0) {
      return [];
    }
    if (RustCoreBridge.isNativeLoaded()) {
      try {
        const rustInputs: Record<string, Object>[] = [];
        for (let i = 0; i < this.resources.length; i++) {
          const r = this.resources[i];
          const itemObj: Record<string, Object> = {};
          itemObj['id'] = String(i);
          itemObj['title'] = r.title;
          itemObj['site_name'] = r.siteName;
          itemObj['size'] = r.sizeBytes;
          itemObj['seeders'] = r.seeders;
          itemObj['peers'] = r.peers;
          itemObj['resource_pix'] = r.resolution;
          itemObj['resource_type'] = r.resourceType;
          itemObj['video_encode'] = r.videoEncode;
          itemObj['volume_factor'] = r.volumeFactor;
          itemObj['labels'] = r.volumeFactor.length > 0 ? [r.volumeFactor] : [];
          itemObj['description'] = r.description;
          itemObj['enclosure'] = r.enclosure;
          rustInputs.push(itemObj);
        }
        const criteriaObj: Record<string, Object> = {};
        if (this.filterSites.length > 0) { criteriaObj['sites'] = this.filterSites; }
        if (this.filterResolutions.length > 0) { criteriaObj['resolutions'] = this.filterResolutions; }
        if (this.filterQualities.length > 0) { criteriaObj['resourceTypes'] = this.filterQualities; }
        if (this.filterEncodes.length > 0) { criteriaObj['videoEncodes'] = this.filterEncodes; }
        if (this.filterPromos.length > 0) { criteriaObj['promotions'] = this.filterPromos; }
        criteriaObj['sortBy'] = this.sortKey;

        const outJson = RustCoreBridge.filterAndGroupResources(JSON.stringify(rustInputs), JSON.stringify(criteriaObj));
        const parsed = JSON.parse(outJson) as Record<string, Object>;
        const groupsVal = parsed['groups'];
        if (Array.isArray(groupsVal)) {
          const mapped: MpResourceItem[] = [];
          for (let g = 0; g < groupsVal.length; g++) {
            const grp = groupsVal[g] as Record<string, Object>;
            const grpItems = grp['items'];
            if (Array.isArray(grpItems)) {
              for (let k = 0; k < grpItems.length; k++) {
                const it = grpItems[k] as Record<string, Object>;
                const idx = Number(it['id']);
                if (Number.isFinite(idx) && idx >= 0 && idx < this.resources.length) {
                  mapped.push(this.resources[idx]);
                }
              }
            }
          }
          if (mapped.length > 0 || Number(parsed['filteredCount']) === 0) {
            // 对发布时间与站点排序补充确定性次级顺序
            if (this.sortKey === 'pubdate' || this.sortKey === 'site') {
              return this.applyLocalFilterAndSort(mapped);
            }
            return mapped;
          }
        }
      } catch {
        // Rust JSON 协议回退至本地等价筛选
      }
    }
    return this.applyLocalFilterAndSort(this.resources);
  }

  private siteScopeLabel(): string {
    if (this.selectedSiteIds.length === 0) { return '全站 ▾'; }
    if (this.selectedSiteIds.length === 1) {
      const s = this.sites.find((x: MpSiteItem) => x.id === this.selectedSiteIds[0]);
      return `${s ? s.name : '1 站'} ▾`;
    }
    return `已选 ${this.selectedSiteIds.length} 站 ▾`;
  }

  private directoryTargetPath(dir: MpDirectoryConfig): string {
    return dir.downloadPath.trim().length > 0 ? dir.downloadPath.trim() : dir.libraryPath.trim();
  }

  @Builder
  sitePickerSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '选择搜索站点',
        cancelText: '关闭',
        actionText: this.selectedSiteIds.length === 0 ? '全选' : '全站',
        onCancel: () => { this.showSiteSheet = false; },
        onAction: () => {
          if (this.selectedSiteIds.length === 0) {
            this.selectedSiteIds = this.sites.map((s: MpSiteItem) => s.id);
          } else {
            this.selectedSiteIds = [];
          }
        }
      })

      Text(this.selectedSiteIds.length === 0
        ? '支持多选站点 · 当前：全站（留空自动遵循默认范围）'
        : `支持多选站点 · 当前已选 ${this.selectedSiteIds.length} 个站点`)
        .fontSize(12)
        .fontColor(mpSecondaryText(this.isDark))
        .width('100%')

      Scroll() {
        if (this.loading && this.sites.length === 0) {
          HarmonySkeletonHost({ loadingLabel: '正在加载搜索站点列表' }) {
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
              ForEach([82, 96, 72, 88, 102, 76, 86, 74], (pillW: number, idx: number) => {
                HarmonySkeletonBlock({
                  blockWidth: pillW,
                  blockHeight: 34,
                  cornerRadius: 17,
                  tone: idx === 0 ? 'block' : 'subtle'
                })
              }, (_pillW: number, idx: number) => `site_pill_sk_${idx}`)
            }
            .padding({ bottom: 16 })
          }
        } else {
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(this.sites, (s: MpSiteItem) => {
              HarmonyEntityLogoPill({
                kind: 'site',
                value: s.name,
                dataUri: s.iconDataUri,
                title: s.name,
                selected: this.selectedSiteIds.includes(s.id),
                onTap: () => {
                  if (this.selectedSiteIds.includes(s.id)) {
                    this.selectedSiteIds = this.selectedSiteIds.filter((id: number) => id !== s.id);
                  } else {
                    this.selectedSiteIds = [...this.selectedSiteIds, s.id];
                  }
                }
              })
            }, (s: MpSiteItem) => `res_site_${s.id}`)
          }
          .padding({ bottom: 16 })
        }
      }.align(Alignment.Top).scrollBar(BarState.Off).layoutWeight(1)

      Button(this.keyword.trim().length > 0 ? '应用并搜索' : '应用并浏览')
        .width('100%').height(46).borderRadius(23)
        .backgroundColor(this.accentHex).fontColor(Color.White).fontWeight(FontWeight.Bold)
        .onClick(() => {
          this.showSiteSheet = false;
          this.runSearch();
        })
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  sortSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '排序方式',
        cancelText: '关闭',
        onCancel: () => { this.showSortSheet = false; }
      })
      Scroll() {
        Column({ space: 10 }) {
          ForEach(SORT_MODES, (m: string[]) => {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                Row() {
                  Text(m[1]).fontSize(15).fontWeight(this.sortKey === m[0] ? FontWeight.Bold : FontWeight.Medium)
                    .fontColor(this.sortKey === m[0] ? this.accentHex : mpPrimaryText(this.isDark)).layoutWeight(1)
                  if (this.sortKey === m[0]) {
                    SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([this.accentHex])
                  }
                }.width('100%')
              }
            }
            .width('100%')
            .onClick(() => {
              this.sortKey = m[0];
              this.showSortSheet = false;
            })
          }, (m: string[]) => m[0])
        }
        .width('100%')
        .padding({ bottom: 16 })
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
  filterSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '全部筛选条件',
        cancelText: '关闭',
        actionText: '清空全部',
        onCancel: () => { this.showFilterSheet = false; },
        onAction: () => { this.clearAllFilters(); }
      })

      Scroll() {
        Column({ space: 14 }) {
          if (this.resultSiteNames().length > 0) {
            Text('结果站点（可多选）').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
              ForEach(this.resultSiteNames(), (name: string) => {
                HarmonyEntityLogoPill({
                  kind: 'site',
                  value: name,
                  dataUri: this.siteIconForName(name),
                  title: name,
                  selected: this.filterSites.includes(name),
                  onTap: () => { this.filterSites = this.toggleInList(this.filterSites, name); }
                })
              }, (name: string) => `fs_${name}`)
            }.width('100%')
          }

          Text('分辨率').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(RES_FILTER_OPTIONS, (opt: string) => {
              NativeAdaptivePill({
                title: opt,
                selected: this.filterResolutions.includes(opt),
                onTap: () => { this.filterResolutions = this.toggleInList(this.filterResolutions, opt); }
              })
            }, (opt: string) => `fr_${opt}`)
          }.width('100%')

          Text('促销优惠').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(PROMO_FILTER_OPTIONS, (opt: string) => {
              NativeAdaptivePill({
                title: opt,
                selected: this.filterPromos.includes(opt),
                onTap: () => { this.filterPromos = this.toggleInList(this.filterPromos, opt); }
              })
            }, (opt: string) => `fp_${opt}`)
          }.width('100%')

          Text('质量来源').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(QUALITY_FILTER_OPTIONS, (opt: string) => {
              NativeAdaptivePill({
                title: opt,
                selected: this.filterQualities.includes(opt),
                onTap: () => { this.filterQualities = this.toggleInList(this.filterQualities, opt); }
              })
            }, (opt: string) => `fq_${opt}`)
          }.width('100%')

          Text('视频编码').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            ForEach(ENCODE_FILTER_OPTIONS, (opt: string) => {
              NativeAdaptivePill({
                title: opt,
                selected: this.filterEncodes.includes(opt),
                onTap: () => { this.filterEncodes = this.toggleInList(this.filterEncodes, opt); }
              })
            }, (opt: string) => `fe_${opt}`)
          }.width('100%')
        }.padding({ bottom: 16 })
      }.scrollBar(BarState.Off).layoutWeight(1)

      Button(this.loading ? '查看筛选结果' : `查看 ${this.filteredResources().length} 条结果`)
        .width('100%').height(46).borderRadius(23)
        .backgroundColor(this.accentHex).fontColor(Color.White).fontWeight(FontWeight.Bold)
        .onClick(() => { this.showFilterSheet = false; })
    }.padding(20).width('100%').height('100%')
  }

  @Builder
  downloadConfirmBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '添加下载任务',
        cancelText: '取消',
        onCancel: () => { this.showDownloadSheet = false; }
      })

      Scroll() {
        Column({ space: 12 }) {
          if (this.selectedItem) {
            CinematicPanel({ panelPadding: 12, cornerRadius: 16 }) {
              Column({ space: 4 }) {
                Text(this.selectedItem.title)
                  .fontSize(13.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  .maxLines(3).width('100%')
                Row({ space: 6 }) {
                  HarmonyEntityLogo({
                    kind: 'site',
                    value: this.selectedItem.siteName,
                    dataUri: this.siteIconForName(this.selectedItem.siteName),
                    logoSize: 15,
                    cornerRadius: 4
                  })
                  Text(`${this.selectedItem.siteName} · ${formatByteSize(this.selectedItem.sizeBytes)} · 做种 ${this.selectedItem.seeders}`)
                    .fontSize(12).fontColor(mpSecondaryText(this.isDark))
                }.width('100%')
              }.alignItems(HorizontalAlign.Start)
            }
          }

          Text('选择下载器').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            HarmonyEntityLogoPill({
              kind: 'downloader',
              value: 'downloader',
              title: '默认下载器',
              selected: this.selectedDownloader.length === 0,
              onTap: () => { this.selectedDownloader = ''; }
            })
            ForEach(this.downloaders, (dl: MpServiceConfig) => {
              HarmonyEntityLogoPill({
                kind: 'downloader',
                value: dl.type || dl.name,
                title: dl.name,
                selected: this.selectedDownloader === dl.name,
                onTap: () => { this.selectedDownloader = dl.name; }
              })
            }, (dl: MpServiceConfig) => dl.name)
          }.width('100%')

          Text('选择目标目录').fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpSecondaryText(this.isDark)).width('100%')
          Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
            NativeAdaptivePill({
              title: '自动匹配目录',
              selected: this.savePath.trim().length === 0,
              onTap: () => { this.savePath = ''; }
            })
            ForEach(this.directories, (dir: MpDirectoryConfig, idx: number) => {
              HarmonyEntityLogoPill({
                kind: 'storage',
                value: dir.storage || 'local',
                title: `${dir.name || '目录'} (${this.directoryTargetPath(dir)})`,
                selected: this.savePath === this.directoryTargetPath(dir),
                onTap: () => { this.savePath = this.directoryTargetPath(dir); }
              })
            }, (dir: MpDirectoryConfig, idx: number) => `dl_dir_${idx}_${dir.name}`)
          }.width('100%')

          TextInput({ placeholder: '自定义保存路径（留空遵循目录配置）', text: this.savePath })
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
            .onChange((v: string) => { this.savePath = v; })
        }
        .padding({ bottom: 8 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)

      Button(this.pushing ? '推送中…' : `推送至 ${this.selectedDownloader || '默认下载器'}`)
        .width('100%').height(46).borderRadius(23)
        .backgroundColor(this.accentHex).fontColor(Color.White).fontWeight(FontWeight.Bold)
        .enabled(!this.pushing)
        .onClick(async () => {
          if (!this.selectedItem) { return; }
          this.pushing = true;
          const ok = await MoviePilotRepository.shared().pushDownload(this.selectedItem, this.selectedDownloader, this.savePath);
          this.pushing = false;
          this.showDownloadSheet = false;
          this.notice = ok ? '已成功推送至下载器' : '推送失败，请检查下载器配置';
        })
    }.padding(20).width('100%').height('100%')
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: this.loading ? '站点资源' : `站点资源 (${this.filteredResources().length})`,
        onBack: () => this.onBack()
      })

      Row({ space: 8 }) {
        CinematicPanel({ panelPadding: 6, cornerRadius: 20 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(17).fontColor([mpSecondaryText(this.isDark)]).margin({ left: 6 })
            TextInput({ placeholder: '输入关键词，留空可浏览站点', text: this.keyword })
              .layoutWeight(1)
              .fontSize(13.5)
              .fontColor(mpPrimaryText(this.isDark))
              .placeholderColor(mpSecondaryText(this.isDark))
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.keyword = v; })
              .onSubmit(() => this.runSearch())

            Text(this.siteScopeLabel())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selectedSiteIds.length > 0 ? Color.White : mpPrimaryText(this.isDark))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(this.selectedSiteIds.length > 0 ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
              .onClick(() => { this.showSiteSheet = true; })

            Button(this.keyword.trim().length > 0 ? '搜索' : '浏览')
              .height(34).padding({ left: 12, right: 12 }).borderRadius(17)
              .fontSize(12.5).fontWeight(FontWeight.Bold)
              .backgroundColor(this.accentHex).fontColor(Color.White)
              .onClick(() => this.runSearch())
          }.width('100%')
        }
      }
      .padding({ left: 16, right: 16 })

      Scroll() {
        Row({ space: 8 }) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.sort')).fontSize(13).fontColor([mpPrimaryText(this.isDark)])
            Text(`排序 · ${this.sortLabel()}`).fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(16)
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
          .onClick(() => { this.showSortSheet = true; })

          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.slider_horizontal_2'))
              .fontSize(13)
              .fontColor([this.activeFilterCount() > 0 ? Color.White : mpPrimaryText(this.isDark)])
            Text(this.activeFilterCount() > 0 ? `全部筛选 (${this.activeFilterCount()})` : '全部筛选')
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.activeFilterCount() > 0 ? Color.White : mpPrimaryText(this.isDark))
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(16)
          .backgroundColor(this.activeFilterCount() > 0 ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
          .onClick(() => { this.showFilterSheet = true; })

          NativeAdaptivePill({
            title: '2160p',
            selected: this.filterResolutions.includes('2160p'),
            onTap: () => { this.filterResolutions = this.toggleInList(this.filterResolutions, '2160p'); }
          })
          NativeAdaptivePill({
            title: '免费',
            selected: this.filterPromos.includes('免费'),
            onTap: () => { this.filterPromos = this.toggleInList(this.filterPromos, '免费'); }
          })
          if (this.activeFilterCount() > 0) {
            Text('清空')
              .fontSize(12.5).fontColor('#E84855').fontWeight(FontWeight.Medium)
              .padding({ left: 8, right: 8, top: 8, bottom: 8 })
              .onClick(() => this.clearAllFilters())
          }
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#34C759').padding({ left: 16, right: 16 }).width('100%')
      }

      if (this.loading) {
        HarmonyCardGridSkeleton({
          variant: 'resource',
          fillViewport: true,
          bottomPadding: 40
        })
      } else if (this.filteredResources().length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(36).fontColor([mpSecondaryText(this.isDark)])
          Text('暂无符合筛选条件的站点资源').fontSize(13.5).fontColor(mpSecondaryText(this.isDark))
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.filteredResources().slice(0, 80), (row: MpResourceItem, idx: number) => {
            GridItem() {
              Column() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: true }) {
                  Column({ space: 7 }) {
                    Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 6, unit: 1 } } }) {
                      Row({ space: 4 }) {
                        HarmonyEntityLogo({
                          kind: 'site',
                          value: row.siteName,
                          dataUri: this.siteIconForName(row.siteName),
                          logoSize: 14,
                          cornerRadius: 3
                        })
                        Text(row.siteName)
                          .fontSize(11)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                      }
                      .padding({ left: 6, right: 8, top: 2, bottom: 2 })
                      .borderRadius(8)
                      .backgroundColor(this.accentHex)

                      if (row.resolution.length > 0) {
                        NativeAdaptiveBadge({ text: row.resolution, tintHex: '#5AC8FA' })
                      }
                      if (row.resourceType.length > 0) {
                        NativeAdaptiveBadge({ text: row.resourceType, tintHex: '#8E7BFF' })
                      }
                      if (row.videoEncode.length > 0) {
                        NativeAdaptiveBadge({ text: row.videoEncode, tintHex: '#64A2FF' })
                      }
                      if (row.volumeFactor.length > 0) {
                        NativeAdaptiveBadge({ text: row.volumeFactor, tintHex: '#34C759' })
                      }
                    }.width('100%')

                    Text(row.title)
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(2)
                      .width('100%')

                    if (row.description.length > 0) {
                      Text(row.description)
                        .fontSize(12)
                        .fontColor(mpSecondaryText(this.isDark))
                        .maxLines(2)
                        .width('100%')
                    }

                    Row() {
                      Text(formatByteSize(row.sizeBytes)).fontSize(12).fontColor(mpPrimaryText(this.isDark))
                      Text(`  ↑ ${row.seeders}`).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#34C759')
                      if (row.peers > 0) {
                        Text(`  ↓ ${row.peers}`).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                      }
                      Blank()
                      Text('推送下载 ›').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.accentHex)
                    }.width('100%')
                  }
                }
              }
              .width('100%')
              .onClick(() => {
                this.selectedItem = row;
                this.showDownloadSheet = true;
              })
            }
          }, (row: MpResourceItem, idx: number) => `${idx}_${row.siteName}_${row.title}`)
        }
        .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
        .columnsGap(12)
        .rowsGap(10)
        .padding({ left: 16, right: 16, bottom: 40 })
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }

      Blank().width(0).height(0).bindSheet($$this.showSiteSheet, this.sitePickerSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showSortSheet, this.sortSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showFilterSheet, this.filterSheetBuilder(), {
        detents: [SheetSize.LARGE],
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showDownloadSheet, this.downloadConfirmBuilder(), {
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

/** 鸿蒙「正在下载」管理页（搭载真实下载器品牌图标，支持暂停/恢复与删除任务）。 */
@Component
export struct HarmonyDownloadsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @State private tasks: MpDownloadTask[] = [];
  @State private downloaders: MpServiceConfig[] = [];
  @State private loading: boolean = true;
  @State private notice: string = '';
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadDownloads();
  }

  private async loadDownloads(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchDownloads(),
        this.downloaders.length > 0 ? Promise.resolve(this.downloaders) : repo.fetchDownloaders()
      ]);
      this.tasks = res[0];
      this.downloaders = res[1];
    } catch {
      this.tasks = [];
    }
    this.loading = false;
  }

  private resolveDownloaderType(name: string): string {
    const found = this.downloaders.find((d: MpServiceConfig) => d.name === name);
    return found ? (found.type || found.name) : name;
  }

  private isPaused(state: string): boolean {
    const s = state.toLowerCase();
    return s.includes('pause') || s.includes('stop');
  }

  build() {
    Column({ space: 12 }) {
      NativeBackHeader({
        title: (this.loading && this.tasks.length === 0) ? '下载管理' : `下载管理 (${this.tasks.length})`,
        trailingSymbol: 'sys.symbol.arrow_clockwise',
        trailingAccessibility: '刷新下载任务',
        onBack: () => this.onBack(),
        onTrailingClick: () => this.loadDownloads()
      })

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#34C759').padding({ left: 16, right: 16 }).width('100%')
      }

      if (this.loading && this.tasks.length === 0) {
        HarmonyCardGridSkeleton({
          variant: 'download',
          fillViewport: true,
          bottomPadding: 40
        })
      } else if (this.tasks.length === 0) {
        Column() {
          CinematicPanel({ panelPadding: 28, cornerRadius: 20 }) {
            Column({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(42).fontColor([mpSecondaryText(this.isDark)])
              Text('当前没有正在进行的下载任务').fontSize(15).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
              Text('从站点资源或订阅命中推送后将在此实时显示进度。').fontSize(12).fontColor(mpSecondaryText(this.isDark))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        }
        .padding({ left: 16, right: 16, top: 20 })
      } else {
        Grid() {
          ForEach(this.tasks, (task: MpDownloadTask) => {
            GridItem() {
              CinematicPanel({ panelPadding: 15, cornerRadius: 18 }) {
                Column({ space: 8 }) {
                  Row({ space: 8 }) {
                    HarmonyEntityLogo({
                      kind: 'downloader',
                      value: this.resolveDownloaderType(task.downloader),
                      logoSize: 22,
                      cornerRadius: 6
                    })
                    Text(task.title).fontSize(14.5).fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark)).maxLines(2).layoutWeight(1)
                    if (task.downloader.length > 0) {
                      NativeAdaptiveBadge({ text: task.downloader, tintHex: this.accentHex })
                    }
                  }.width('100%')

                  Progress({ value: task.progress, total: 100, type: ProgressType.Linear })
                    .color(this.accentHex).backgroundColor(HarmonyThemeColors.chipFill(this.isDark))

                  Row() {
                    Text(`↓ ${task.dlspeed}  ↑ ${task.upspeed}`).fontSize(12).fontColor('#34C759')
                    Blank()
                    Text(`${task.progress.toFixed(1)}% · ${formatByteSize(task.sizeBytes)}`)
                      .fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }.width('100%')

                  Row({ space: 10 }) {
                    Button(this.isPaused(task.state) ? '恢复' : '暂停')
                      .height(32).padding({ left: 14, right: 14 }).borderRadius(16).fontSize(12)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      .fontColor(mpPrimaryText(this.isDark))
                      .onClick(async () => {
                        const ok = await MoviePilotRepository.shared().toggleDownloadTask(task.hash, task.downloader, !this.isPaused(task.state));
                        this.notice = ok ? (this.isPaused(task.state) ? '已恢复任务' : '已暂停任务') : '操作失败';
                        await this.loadDownloads();
                      })
                    Blank()
                    Button('删除')
                      .height(32).padding({ left: 14, right: 14 }).borderRadius(16).fontSize(12)
                      .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                      .fontColor('#E84855')
                      .onClick(async () => {
                        const ok = await MoviePilotRepository.shared().deleteDownloadTask(task.hash, task.downloader);
                        this.notice = ok ? '已删除下载任务' : '删除失败';
                        await this.loadDownloads();
                      })
                  }.width('100%')
                }
              }
            }
          }, (task: MpDownloadTask) => task.hash || task.title)
        }
        .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
        .columnsGap(12)
        .rowsGap(12)
        .padding({ left: 16, right: 16, bottom: 40 })
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
    }.width('100%').height('100%')
  }
}
