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

interface ResourceFacetOptionsSnapshot {
  sites: string[];
  promotions: string[];
  resolutions: string[];
  labels: string[];
  editions: string[];
  videoEncodes: string[];
  seasons: string[];
  resourceTypes: string[];
  audioEncodes: string[];
  teams: string[];
}

interface ResourceFacetDimSpec {
  key: string;
  title: string;
  sheetTitle: string;
}

const RESOURCE_FACET_DIMS: ResourceFacetDimSpec[] = [
  { key: 'site', title: '站点', sheetTitle: '结果站点' },
  { key: 'promo', title: '促销', sheetTitle: '促销优惠' },
  { key: 'res', title: '分辨率', sheetTitle: '分辨率' },
  { key: 'label', title: '字幕/标签', sheetTitle: '字幕与标签' },
  { key: 'edition', title: '版本', sheetTitle: '质量版本' },
  { key: 'encode', title: '编码', sheetTitle: '视频编码' },
  { key: 'season', title: '季集', sheetTitle: '季集' },
  { key: 'type', title: '来源', sheetTitle: '资源来源' },
  { key: 'audio', title: '音轨', sheetTitle: '音频编码' },
  { key: 'team', title: '制作组', sheetTitle: '制作组' }
];

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
  @State private siteScopeMode: string = 'default'; // default | all | custom
  @State private selectedSiteIds: number[] = [];
  @State private resources: MpResourceItem[] = [];
  @State private loading: boolean = true;
  @State private notice: string = '';

  // 排序与 9 维 + 季集连续多选筛选（对齐 #67）
  @State private sortKey: string = 'seeders';
  @State private filterSites: string[] = [];
  @State private filterResolutions: string[] = [];
  @State private filterPromos: string[] = [];
  @State private filterEditions: string[] = [];
  @State private filterQualities: string[] = [];
  @State private filterEncodes: string[] = [];
  @State private filterAudioEncodes: string[] = [];
  @State private filterTeams: string[] = [];
  @State private filterLabels: string[] = [];
  @State private filterSeasons: string[] = [];
  @State private openFacetKey: string = '';

  // 弹层状态
  @State private showSitePopup: boolean = false;
  @State private showSiteSheet: boolean = false;
  @State private showSortSheet: boolean = false;
  @State private showFilterSheet: boolean = false;
  @State private showDownloadSheet: boolean = false;
  @State private selectedItem: MpResourceItem | null = null;
  @State private sameSpecVariants: MpResourceItem[] = [];
  @State private selectedVariantKeys: string[] = [];
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

  private resolvedSearchSiteIds(): number[] {
    if (this.siteScopeMode === 'all') {
      return this.sites.map((s: MpSiteItem) => s.id);
    }
    if (this.siteScopeMode === 'custom') {
      return [...this.selectedSiteIds].sort((a: number, b: number) => a - b);
    }
    return [];
  }

  private async runSearch(): Promise<void> {
    this.loading = true;
    this.notice = '';
    try {
      this.resources = await MoviePilotRepository.shared().searchSiteResources(
        this.keyword,
        this.resolvedSearchSiteIds()
      );
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
      this.filterPromos.length + this.filterEditions.length +
      this.filterQualities.length + this.filterEncodes.length +
      this.filterAudioEncodes.length + this.filterTeams.length +
      this.filterLabels.length + this.filterSeasons.length;
  }

  private siteIconForName(siteName: string): string {
    const found = this.sites.find((s: MpSiteItem) => s.name === siteName);
    return found ? found.iconDataUri : '';
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
    this.filterEditions = [];
    this.filterQualities = [];
    this.filterEncodes = [];
    this.filterAudioEncodes = [];
    this.filterTeams = [];
    this.filterLabels = [];
    this.filterSeasons = [];
  }

  private promotionLabelOf(r: MpResourceItem): string {
    const factors = this.resolvedVolumeFactors(r);
    const dl = factors[0];
    const ul = factors[1];
    if (dl === 0 && ul >= 2) { return '2X免费'; }
    if (dl === 0) { return '免费'; }
    if (Math.abs(dl - 0.5) < 0.01) { return '50%'; }
    if (dl > 0 && dl < 1) { return `${Math.round(dl * 100)}%`; }
    return '普通';
  }

  private resolvedVolumeFactors(r: MpResourceItem): number[] {
    const dl = r.downloadVolumeFactor ?? -1;
    const ul = r.uploadVolumeFactor ?? -1;
    if (dl >= 0 && ul >= 0) {
      return [dl, ul];
    }
    return this.parsePromotionFactors(r.volumeFactor);
  }

  private computeFacetOptions(): ResourceFacetOptionsSnapshot {
    const siteSet = new Set<string>();
    const promoSet = new Set<string>();
    const resSet = new Set<string>();
    const labelSet = new Set<string>();
    const editionSet = new Set<string>();
    const encodeSet = new Set<string>();
    const seasonSet = new Set<string>();
    const typeSet = new Set<string>();
    const audioSet = new Set<string>();
    const teamSet = new Set<string>();

    for (let i = 0; i < this.resources.length; i++) {
      const r = this.resources[i];
      if (r.siteName.trim().length > 0) { siteSet.add(r.siteName.trim()); }
      promoSet.add(this.promotionLabelOf(r));
      if (r.resolution.trim().length > 0) { resSet.add(r.resolution.trim()); }
      const ed = (r.edition ?? '').trim();
      if (ed.length > 0) { editionSet.add(ed); }
      if (r.videoEncode.trim().length > 0) { encodeSet.add(r.videoEncode.trim()); }
      const se = (r.seasonEpisode ?? '').trim();
      if (se.length > 0) { seasonSet.add(se); }
      if (r.resourceType.trim().length > 0) { typeSet.add(r.resourceType.trim()); }
      const au = (r.audioEncode ?? '').trim();
      if (au.length > 0) { audioSet.add(au); }
      const tm = (r.resourceTeam ?? '').trim();
      if (tm.length > 0) { teamSet.add(tm); }
      const lbls = r.labels ?? [];
      for (let k = 0; k < lbls.length; k++) {
        const l = lbls[k].trim();
        if (l.length > 0) { labelSet.add(l); }
      }
    }
    return {
      sites: Array.from(siteSet).sort(),
      promotions: Array.from(promoSet).sort(),
      resolutions: Array.from(resSet).sort(),
      labels: Array.from(labelSet).sort(),
      editions: Array.from(editionSet).sort(),
      videoEncodes: Array.from(encodeSet).sort(),
      seasons: Array.from(seasonSet).sort(),
      resourceTypes: Array.from(typeSet).sort(),
      audioEncodes: Array.from(audioSet).sort(),
      teams: Array.from(teamSet).sort()
    };
  }

  private facetSelectionFor(dimKey: string): string[] {
    if (dimKey === 'site') { return this.filterSites; }
    if (dimKey === 'promo') { return this.filterPromos; }
    if (dimKey === 'res') { return this.filterResolutions; }
    if (dimKey === 'label') { return this.filterLabels; }
    if (dimKey === 'edition') { return this.filterEditions; }
    if (dimKey === 'encode') { return this.filterEncodes; }
    if (dimKey === 'season') { return this.filterSeasons; }
    if (dimKey === 'type') { return this.filterQualities; }
    if (dimKey === 'audio') { return this.filterAudioEncodes; }
    if (dimKey === 'team') { return this.filterTeams; }
    return [];
  }

  private setFacetSelectionFor(dimKey: string, next: string[]): void {
    if (dimKey === 'site') { this.filterSites = next; }
    else if (dimKey === 'promo') { this.filterPromos = next; }
    else if (dimKey === 'res') { this.filterResolutions = next; }
    else if (dimKey === 'label') { this.filterLabels = next; }
    else if (dimKey === 'edition') { this.filterEditions = next; }
    else if (dimKey === 'encode') { this.filterEncodes = next; }
    else if (dimKey === 'season') { this.filterSeasons = next; }
    else if (dimKey === 'type') { this.filterQualities = next; }
    else if (dimKey === 'audio') { this.filterAudioEncodes = next; }
    else if (dimKey === 'team') { this.filterTeams = next; }
  }

  private facetOptionsFor(snapshot: ResourceFacetOptionsSnapshot, dimKey: string): string[] {
    let base: string[] = [];
    if (dimKey === 'site') { base = snapshot.sites; }
    else if (dimKey === 'promo') { base = snapshot.promotions; }
    else if (dimKey === 'res') { base = snapshot.resolutions; }
    else if (dimKey === 'label') { base = snapshot.labels; }
    else if (dimKey === 'edition') { base = snapshot.editions; }
    else if (dimKey === 'encode') { base = snapshot.videoEncodes; }
    else if (dimKey === 'season') { base = snapshot.seasons; }
    else if (dimKey === 'type') { base = snapshot.resourceTypes; }
    else if (dimKey === 'audio') { base = snapshot.audioEncodes; }
    else if (dimKey === 'team') { base = snapshot.teams; }
    const sel = this.facetSelectionFor(dimKey);
    const merged: string[] = [...base];
    for (let i = 0; i < sel.length; i++) {
      if (!merged.includes(sel[i])) {
        merged.push(sel[i]);
      }
    }
    return merged;
  }

  private matchIgnoreCaseSet(selected: string[], value: string): boolean {
    if (selected.length === 0) { return true; }
    const lowerVal = value.trim().toLowerCase();
    return selected.some((s: string) => s.trim().toLowerCase() === lowerVal);
  }

  private applyLocalFilterAndSort(source: MpResourceItem[]): MpResourceItem[] {
    const out = source.filter((r: MpResourceItem) => {
      if (!this.matchIgnoreCaseSet(this.filterSites, r.siteName)) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterResolutions, r.resolution)) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterPromos, this.promotionLabelOf(r))) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterEditions, r.edition ?? '')) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterQualities, r.resourceType)) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterEncodes, r.videoEncode)) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterAudioEncodes, r.audioEncode ?? '')) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterTeams, r.resourceTeam ?? '')) { return false; }
      if (!this.matchIgnoreCaseSet(this.filterSeasons, r.seasonEpisode ?? '')) { return false; }
      if (this.filterLabels.length > 0) {
        const itemLabels = (r.labels ?? []).map((x: string) => x.trim().toLowerCase());
        const ok = this.filterLabels.every((req: string) => itemLabels.includes(req.trim().toLowerCase()));
        if (!ok) { return false; }
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

  private parsePromotionFactors(label: string): number[] {
    const clean = (label || '').trim().toUpperCase();
    if (clean.includes('2X') && (clean.includes('免费') || clean.includes('FREE'))) { return [0.0, 2.0]; }
    if (clean.includes('免费') || clean.includes('FREE')) { return [0.0, 1.0]; }
    if (clean.includes('2X') && clean.includes('50')) { return [0.5, 2.0]; }
    if (clean.includes('50')) { return [0.5, 1.0]; }
    if (clean.includes('30')) { return [0.3, 1.0]; }
    if (clean.includes('2X')) { return [1.0, 2.0]; }
    return [1.0, 1.0];
  }

  private variantKeyOf(item: MpResourceItem): string {
    return `${item.siteName}|${item.title}|${item.enclosure}|${item.sizeBytes}`;
  }

  private collectSameSpecVariants(primary: MpResourceItem): MpResourceItem[] {
    const keyOf = (r: MpResourceItem): string =>
      `${(r.resolution || '').toLowerCase()}|${(r.resourceType || '').toLowerCase()}|${(r.videoEncode || '').toLowerCase()}|${r.title.trim().toLowerCase().slice(0, 32)}`;
    const primarySpec = keyOf(primary);
    const out: MpResourceItem[] = [primary];
    const seen = new Set<string>([this.variantKeyOf(primary)]);
    const pool = this.filteredResources();
    for (let i = 0; i < pool.length; i++) {
      const cand = pool[i];
      const ck = this.variantKeyOf(cand);
      if (!seen.has(ck) && keyOf(cand) === primarySpec) {
        seen.add(ck);
        out.push(cand);
      }
    }
    return out;
  }

  private filteredResources(): MpResourceItem[] {
    if (this.resources.length === 0) {
      return [];
    }
    const basePool = this.filterSeasons.length === 0
      ? this.resources
      : this.resources.filter((r: MpResourceItem) => this.matchIgnoreCaseSet(this.filterSeasons, r.seasonEpisode ?? ''));
    if (basePool.length === 0) {
      return [];
    }
    if (RustCoreBridge.isNativeLoaded()) {
      try {
        const rustInputs: Record<string, Object>[] = [];
        for (let i = 0; i < basePool.length; i++) {
          const r = basePool[i];
          const factors = this.resolvedVolumeFactors(r);
          const itemObj: Record<string, Object> = {};
          itemObj['id'] = String(i);
          itemObj['title'] = r.title;
          itemObj['site_name'] = r.siteName;
          itemObj['size'] = r.sizeBytes;
          itemObj['seeders'] = r.seeders;
          itemObj['peers'] = r.peers;
          itemObj['resource_pix'] = r.resolution;
          itemObj['resource_type'] = r.resourceType;
          itemObj['edition'] = r.edition ?? '';
          itemObj['video_encode'] = r.videoEncode;
          itemObj['audio_encode'] = r.audioEncode ?? '';
          itemObj['resource_team'] = r.resourceTeam ?? '';
          itemObj['downloadvolumefactor'] = factors[0];
          itemObj['uploadvolumefactor'] = factors[1];
          itemObj['labels'] = r.labels ?? (r.volumeFactor.length > 0 ? [r.volumeFactor] : []);
          itemObj['description'] = r.description;
          itemObj['enclosure'] = r.enclosure;
          rustInputs.push(itemObj);
        }
        const criteriaObj: Record<string, Object> = {};
        if (this.filterSites.length > 0) { criteriaObj['sites'] = this.filterSites; }
        if (this.filterResolutions.length > 0) { criteriaObj['resolutions'] = this.filterResolutions; }
        if (this.filterEditions.length > 0) { criteriaObj['editions'] = this.filterEditions; }
        if (this.filterQualities.length > 0) { criteriaObj['resourceTypes'] = this.filterQualities; }
        if (this.filterEncodes.length > 0) { criteriaObj['videoEncodes'] = this.filterEncodes; }
        if (this.filterAudioEncodes.length > 0) { criteriaObj['audioEncodes'] = this.filterAudioEncodes; }
        if (this.filterTeams.length > 0) { criteriaObj['teams'] = this.filterTeams; }
        if (this.filterPromos.length > 0) { criteriaObj['promotions'] = this.filterPromos; }
        if (this.filterLabels.length > 0) { criteriaObj['labels'] = this.filterLabels; }
        criteriaObj['sortBy'] = this.sortKey === 'size' ? 'sizeDesc' : (this.sortKey === 'site' ? 'site' : 'seeders');

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
                if (Number.isFinite(idx) && idx >= 0 && idx < basePool.length) {
                  mapped.push(basePool[idx]);
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
    return this.applyLocalFilterAndSort(basePool);
  }

  private hasNonDefaultSiteScope(): boolean {
    return this.siteScopeMode === 'all' || (this.siteScopeMode === 'custom' && this.selectedSiteIds.length > 0);
  }

  private siteScopeLabel(): string {
    if (this.siteScopeMode === 'all') { return '全站 ▾'; }
    if (this.siteScopeMode === 'custom') {
      if (this.selectedSiteIds.length === 0) { return '默认 ▾'; }
      if (this.selectedSiteIds.length === 1) {
        const s = this.sites.find((x: MpSiteItem) => x.id === this.selectedSiteIds[0]);
        return `${s ? s.name : '1站'} ▾`;
      }
      return `${this.selectedSiteIds.length}站 ▾`;
    }
    return '默认 ▾';
  }

  private toggleCustomSearchSite(siteId: number): void {
    let next: number[];
    if (this.siteScopeMode !== 'custom') {
      next = [siteId];
    } else if (this.selectedSiteIds.includes(siteId)) {
      next = this.selectedSiteIds.filter((id: number) => id !== siteId);
    } else {
      next = [...this.selectedSiteIds, siteId];
    }
    this.selectedSiteIds = next;
    this.siteScopeMode = next.length === 0 ? 'default' : 'custom';
  }

  @Builder
  private siteQuickPopupBuilder() {
    Column({ space: 2 }) {
      Row({ space: 8 }) {
        Text('默认（系统设置）')
          .fontSize(13.5)
          .fontWeight(this.siteScopeMode === 'default' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(mpPrimaryText(this.isDark))
          .layoutWeight(1)
        if (this.siteScopeMode === 'default') {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentHex])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(10)
      .onClick(() => {
        this.siteScopeMode = 'default';
        this.selectedSiteIds = [];
        this.showSitePopup = false;
      })

      Row({ space: 8 }) {
        Text('全部站点')
          .fontSize(13.5)
          .fontWeight(this.siteScopeMode === 'all' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(mpPrimaryText(this.isDark))
          .layoutWeight(1)
        if (this.siteScopeMode === 'all') {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(14)
            .fontColor([this.accentHex])
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(10)
      .onClick(() => {
        this.siteScopeMode = 'all';
        this.selectedSiteIds = [];
        this.showSitePopup = false;
      })

      if (this.sites.length > 0) {
        Divider().color(HarmonyThemeColors.chipFill(this.isDark)).margin({ top: 2, bottom: 2 })
        Scroll() {
          Column({ space: 2 }) {
            ForEach(this.sites, (s: MpSiteItem) => {
              Row({ space: 8 }) {
                HarmonyEntityLogo({
                  kind: 'site',
                  value: s.name,
                  dataUri: s.iconDataUri,
                  logoSize: 16,
                  cornerRadius: 4
                })
                Text(s.name)
                  .fontSize(13.5)
                  .fontWeight(this.siteScopeMode === 'custom' && this.selectedSiteIds.includes(s.id)
                    ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(1)
                  .layoutWeight(1)
                if (this.siteScopeMode === 'custom' && this.selectedSiteIds.includes(s.id)) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(14)
                    .fontColor([this.accentHex])
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 9, bottom: 9 })
              .borderRadius(10)
              .onClick(() => {
                // 勾选具体站点时保持菜单展开支持连续多选（对齐 #67）
                this.toggleCustomSearchSite(s.id);
              })
            }, (s: MpSiteItem) => `site_pop_${s.id}`)
          }
        }
        .constraintSize({ maxHeight: 250 })
        .scrollBar(BarState.Off)

        Divider().color(HarmonyThemeColors.chipFill(this.isDark)).margin({ top: 2, bottom: 2 })
        Row() {
          Text('展开站点网格面板…')
            .fontSize(12.5)
            .fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .onClick(() => {
          this.showSitePopup = false;
          this.showSiteSheet = true;
        })
      }
    }
    .width(224)
    .padding(6)
  }

  @Builder
  private facetPopupBuilder(dimKey: string, dimTitle: string) {
    Column({ space: 2 }) {
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.facetOptionsFor(this.computeFacetOptions(), dimKey), (opt: string) => {
            Row({ space: 8 }) {
              if (dimKey === 'site') {
                HarmonyEntityLogo({
                  kind: 'site',
                  value: opt,
                  dataUri: this.siteIconForName(opt),
                  logoSize: 16,
                  cornerRadius: 4
                })
              }
              Text(opt)
                .fontSize(13.5)
                .fontWeight(this.facetSelectionFor(dimKey).includes(opt) ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(mpPrimaryText(this.isDark))
                .maxLines(1)
                .layoutWeight(1)
              if (this.facetSelectionFor(dimKey).includes(opt)) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(14)
                  .fontColor([this.accentHex])
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 9, bottom: 9 })
            .borderRadius(10)
            .onClick(() => {
              // 保持筛选项弹窗展开以支持连续多选（对齐 #67）
              const current = this.facetSelectionFor(dimKey);
              this.setFacetSelectionFor(dimKey, this.toggleInList(current, opt));
            })
          }, (opt: string) => `facet_${dimKey}_${opt}`)
        }
      }
      .constraintSize({ maxHeight: 260 })
      .scrollBar(BarState.Off)

      if (this.facetSelectionFor(dimKey).length > 0) {
        Divider().color(HarmonyThemeColors.chipFill(this.isDark)).margin({ top: 2, bottom: 2 })
        Row() {
          Text(`清空${dimTitle}`)
            .fontSize(13)
            .fontColor('#E84855')
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .borderRadius(10)
        .onClick(() => {
          this.setFacetSelectionFor(dimKey, []);
          this.openFacetKey = '';
        })
      }
    }
    .width(210)
    .padding(6)
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
        actionText: this.siteScopeMode === 'all' ? '默认' : '全站',
        onCancel: () => { this.showSiteSheet = false; },
        onAction: () => {
          if (this.siteScopeMode === 'all') {
            this.siteScopeMode = 'default';
            this.selectedSiteIds = [];
          } else {
            this.siteScopeMode = 'all';
            this.selectedSiteIds = [];
          }
        }
      })

      Row({ space: 8 }) {
        NativeAdaptivePill({
          title: '默认（系统设置）',
          selected: this.siteScopeMode === 'default',
          onTap: () => {
            this.siteScopeMode = 'default';
            this.selectedSiteIds = [];
          }
        })
        NativeAdaptivePill({
          title: '全部站点',
          selected: this.siteScopeMode === 'all',
          onTap: () => {
            this.siteScopeMode = 'all';
            this.selectedSiteIds = [];
          }
        })
      }
      .width('100%')

      Text(this.siteScopeMode === 'all'
        ? '支持多选站点 · 当前：全部站点（覆盖默认搜索范围）'
        : (this.siteScopeMode === 'custom' && this.selectedSiteIds.length > 0
          ? `支持多选站点 · 当前已选 ${this.selectedSiteIds.length} 个站点`
          : '支持多选站点 · 当前：默认（遵循系统设置范围）'))
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
                selected: this.siteScopeMode === 'custom' && this.selectedSiteIds.includes(s.id),
                onTap: () => {
                  this.toggleCustomSearchSite(s.id);
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
          ForEach(RESOURCE_FACET_DIMS, (dim: ResourceFacetDimSpec) => {
            if (this.facetOptionsFor(this.computeFacetOptions(), dim.key).length > 0) {
              Column({ space: 8 }) {
                Row() {
                  Text(`${dim.sheetTitle}（可多选）`)
                    .fontSize(13)
                    .fontColor(mpSecondaryText(this.isDark))
                    .layoutWeight(1)
                  if (this.facetSelectionFor(dim.key).length > 0) {
                    Text(`清空 (${this.facetSelectionFor(dim.key).length})`)
                      .fontSize(12)
                      .fontColor('#E84855')
                      .fontWeight(FontWeight.Medium)
                      .onClick(() => { this.setFacetSelectionFor(dim.key, []); })
                  }
                }
                .width('100%')

                Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
                  ForEach(this.facetOptionsFor(this.computeFacetOptions(), dim.key), (opt: string) => {
                    if (dim.key === 'site') {
                      HarmonyEntityLogoPill({
                        kind: 'site',
                        value: opt,
                        dataUri: this.siteIconForName(opt),
                        title: opt,
                        selected: this.facetSelectionFor(dim.key).includes(opt),
                        onTap: () => {
                          this.setFacetSelectionFor(dim.key, this.toggleInList(this.facetSelectionFor(dim.key), opt));
                        }
                      })
                    } else {
                      NativeAdaptivePill({
                        title: opt,
                        selected: this.facetSelectionFor(dim.key).includes(opt),
                        onTap: () => {
                          this.setFacetSelectionFor(dim.key, this.toggleInList(this.facetSelectionFor(dim.key), opt));
                        }
                      })
                    }
                  }, (opt: string) => `fs_${dim.key}_${opt}`)
                }
                .width('100%')
              }
              .width('100%')
            }
          }, (dim: ResourceFacetDimSpec) => `sheet_dim_${dim.key}`)

          if (this.resources.length === 0 && this.activeFilterCount() === 0) {
            Text('当前暂无可筛选结果，请先输入关键词或选择站点浏览。')
              .fontSize(13)
              .fontColor(mpSecondaryText(this.isDark))
              .width('100%')
          }
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

          if (this.sameSpecVariants.length > 1) {
            Row() {
              Text(`选择同规格站点源（已选 ${this.selectedVariantKeys.length}/${this.sameSpecVariants.length}）`)
                .fontSize(12.5).fontWeight(FontWeight.Medium).fontColor(mpSecondaryText(this.isDark))
              Blank()
              NativeAdaptivePill({
                title: this.selectedVariantKeys.length === this.sameSpecVariants.length ? '仅选主源' : '全选',
                selected: this.selectedVariantKeys.length === this.sameSpecVariants.length,
                onTap: () => {
                  if (this.selectedVariantKeys.length === this.sameSpecVariants.length) {
                    const first = this.sameSpecVariants[0];
                    this.selectedVariantKeys = first ? [this.variantKeyOf(first)] : [];
                  } else {
                    this.selectedVariantKeys = this.sameSpecVariants.map((v: MpResourceItem) => this.variantKeyOf(v));
                  }
                }
              })
            }.width('100%')

            Column({ space: 6 }) {
              ForEach(this.sameSpecVariants, (variant: MpResourceItem) => {
                Row({ space: 8 }) {
                  HarmonyEntityLogo({
                    kind: 'site',
                    value: variant.siteName,
                    dataUri: this.siteIconForName(variant.siteName),
                    logoSize: 18,
                    cornerRadius: 5
                  })
                  Column({ space: 2 }) {
                    Text(`${variant.siteName}${variant.volumeFactor ? ' · ' + variant.volumeFactor : ''}`)
                      .fontSize(13).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    Text(`${formatByteSize(variant.sizeBytes)} · 做种 ${variant.seeders}`)
                      .fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text(this.selectedVariantKeys.includes(this.variantKeyOf(variant)) ? '✓' : '○')
                    .fontSize(15).fontWeight(FontWeight.Bold)
                    .fontColor(this.selectedVariantKeys.includes(this.variantKeyOf(variant)) ? this.accentHex : mpSecondaryText(this.isDark))
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(12)
                .backgroundColor(this.selectedVariantKeys.includes(this.variantKeyOf(variant))
                  ? HarmonyThemeColors.chipFill(this.isDark)
                  : Color.Transparent)
                .onClick(() => {
                  const key = this.variantKeyOf(variant);
                  if (this.selectedVariantKeys.includes(key)) {
                    if (this.selectedVariantKeys.length > 1) {
                      this.selectedVariantKeys = this.selectedVariantKeys.filter((k: string) => k !== key);
                    }
                  } else {
                    this.selectedVariantKeys = [...this.selectedVariantKeys, key];
                  }
                })
              }, (variant: MpResourceItem) => this.variantKeyOf(variant))
            }.width('100%')
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

      Button(this.pushing
        ? '推送中…'
        : (this.selectedVariantKeys.length > 1
          ? `批量推送 ${this.selectedVariantKeys.length} 个源至 ${this.selectedDownloader || '默认下载器'}`
          : `推送至 ${this.selectedDownloader || '默认下载器'}`))
        .width('100%').height(46).borderRadius(23)
        .backgroundColor(this.accentHex).fontColor(Color.White).fontWeight(FontWeight.Bold)
        .enabled(!this.pushing)
        .onClick(async () => {
          if (!this.selectedItem) { return; }
          const targets = this.sameSpecVariants.filter((v: MpResourceItem) =>
            this.selectedVariantKeys.includes(this.variantKeyOf(v))
          );
          const list = targets.length > 0 ? targets : [this.selectedItem];
          this.pushing = true;
          let okCount = 0;
          for (let i = 0; i < list.length; i++) {
            const ok = await MoviePilotRepository.shared().pushDownload(list[i], this.selectedDownloader, this.savePath);
            if (ok) { okCount++; }
          }
          this.pushing = false;
          this.showDownloadSheet = false;
          if (list.length === 1) {
            this.notice = okCount === 1 ? '已成功推送至下载器' : '推送失败，请检查下载器配置';
          } else if (okCount === list.length) {
            this.notice = `已批量推送 ${okCount} 个源至下载器`;
          } else if (okCount > 0) {
            this.notice = `已推送 ${okCount}/${list.length} 个源，部分失败`;
          } else {
            this.notice = '批量推送失败，请检查下载器配置';
          }
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
              .fontColor(this.hasNonDefaultSiteScope() ? Color.White : mpPrimaryText(this.isDark))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(this.hasNonDefaultSiteScope() ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
              .onClick(() => { this.showSitePopup = !this.showSitePopup; })
              .bindPopup(this.showSitePopup, {
                builder: () => { this.siteQuickPopupBuilder(); },
                placement: Placement.BottomRight,
                popupColor: HarmonyThemeColors.overlayFallback(this.isDark),
                enableArrow: false,
                autoCancel: true,
                onStateChange: (e) => {
                  if (!e.isVisible) {
                    this.showSitePopup = false;
                  }
                }
              })

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

          if (this.activeFilterCount() > 0) {
            Text('重置')
              .fontSize(12.5)
              .fontColor('#E84855')
              .fontWeight(FontWeight.Medium)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
              .onClick(() => this.clearAllFilters())
          }

          ForEach(RESOURCE_FACET_DIMS, (dim: ResourceFacetDimSpec) => {
            if (this.facetOptionsFor(this.computeFacetOptions(), dim.key).length > 0) {
              Row({ space: 4 }) {
                Text(this.facetSelectionFor(dim.key).length > 0
                  ? `${dim.title} ${this.facetSelectionFor(dim.key).length}`
                  : dim.title)
                  .fontSize(12.5)
                  .fontWeight(this.facetSelectionFor(dim.key).length > 0 ? FontWeight.Bold : FontWeight.Medium)
                  .fontColor(this.facetSelectionFor(dim.key).length > 0 ? Color.White : mpPrimaryText(this.isDark))
                Text('▾')
                  .fontSize(10)
                  .fontColor(this.facetSelectionFor(dim.key).length > 0 ? Color.White : mpSecondaryText(this.isDark))
              }
              .padding({ left: 12, right: 10, top: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor(this.facetSelectionFor(dim.key).length > 0 || this.openFacetKey === dim.key
                ? (this.facetSelectionFor(dim.key).length > 0 ? this.accentHex : HarmonyThemeColors.chipFill(this.isDark))
                : HarmonyThemeColors.chipFill(this.isDark))
              .onClick(() => {
                this.openFacetKey = this.openFacetKey === dim.key ? '' : dim.key;
              })
              .bindPopup(this.openFacetKey === dim.key, {
                builder: () => { this.facetPopupBuilder(dim.key, dim.title); },
                placement: Placement.Bottom,
                popupColor: HarmonyThemeColors.overlayFallback(this.isDark),
                enableArrow: false,
                autoCancel: true,
                onStateChange: (e) => {
                  if (!e.isVisible && this.openFacetKey === dim.key) {
                    this.openFacetKey = '';
                  }
                }
              })
            }
          }, (dim: ResourceFacetDimSpec) => `bar_dim_${dim.key}`)
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
                this.sameSpecVariants = this.collectSameSpecVariants(row);
                this.selectedVariantKeys = [this.variantKeyOf(row)];
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

  @Builder
  private downloadTaskMenuBuilder(task: MpDownloadTask) {
    Menu() {
      MenuItem({ content: this.isPaused(task.state) ? '恢复任务' : '暂停任务' })
        .onClick(async () => {
          const ok = await MoviePilotRepository.shared().toggleDownloadTask(task.hash, task.downloader, !this.isPaused(task.state));
          this.notice = ok ? (this.isPaused(task.state) ? '已恢复任务' : '已暂停任务') : '操作失败';
          await this.loadDownloads();
        })
      MenuItem({ content: '删除下载任务' })
        .contentFontColor('#E84855')
        .onClick(async () => {
          const ok = await MoviePilotRepository.shared().deleteDownloadTask(task.hash, task.downloader);
          this.notice = ok ? '已删除下载任务' : '删除失败';
          await this.loadDownloads();
        })
    }
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
              Column() {
              CinematicPanel({ panelPadding: 15, cornerRadius: 18, interactive: true }) {
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
                    Blank()
                    Button(this.isPaused(task.state) ? '恢复' : '暂停')
                      .height(32).padding({ left: 14, right: 14 }).borderRadius(16).fontSize(12)
                      .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                      .fontColor(mpPrimaryText(this.isDark))
                      .onClick(async () => {
                        const ok = await MoviePilotRepository.shared().toggleDownloadTask(task.hash, task.downloader, !this.isPaused(task.state));
                        this.notice = ok ? (this.isPaused(task.state) ? '已恢复任务' : '已暂停任务') : '操作失败';
                        await this.loadDownloads();
                      })
                  }.width('100%')
                }
              }
              }
              .width('100%')
              .bindContextMenu(this.downloadTaskMenuBuilder(task), ResponseType.LongPress)
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
