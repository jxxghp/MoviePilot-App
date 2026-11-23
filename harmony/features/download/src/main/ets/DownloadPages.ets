import {
  RustCoreBridge,
  MoviePilotRepository,
  MpResourceItem,
  MpDownloadTask,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

/** 鸿蒙站点资源 9 维筛选页（真实 `/api/v1/search/last` + Rust 筛选引擎 + 下载确认弹层）。 */
@Component
export struct HarmonyResourceSearchPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private selectedRes: string = '全部';
  @State private loading: boolean = true;
  @State private resources: MpResourceItem[] = [];
  @State private showDownloadSheet: boolean = false;
  @State private selectedItem: MpResourceItem | null = null;
  @State private downloader: string = 'qBittorrent';
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadResources();
  }

  private async loadResources(): Promise<void> {
    this.loading = true;
    try {
      this.resources = await MoviePilotRepository.shared().fetchCachedResources();
    } catch {
      this.resources = [];
    }
    this.loading = false;
  }

  private filteredResources(): MpResourceItem[] {
    const out = this.resources.filter((r: MpResourceItem) => {
      if (this.selectedRes === '全部') { return true; }
      return r.resolution.toLowerCase().includes(this.selectedRes.toLowerCase()) ||
        r.title.toLowerCase().includes(this.selectedRes.toLowerCase());
    });
    return out.slice(0, 60);
  }

  @Builder
  downloadConfirmBuilder() {
    Column({ space: 12 }) {
      Text('确认添加下载').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
      Text(this.selectedItem ? this.selectedItem.title : '').fontSize(13).fontColor(mpSecondaryText(this.isDark)).width('100%')
      Row({ space: 8 }) {
        NativeAdaptivePill({ title: 'qBittorrent', selected: this.downloader === 'qBittorrent', onTap: () => { this.downloader = 'qBittorrent'; } })
        NativeAdaptivePill({ title: 'Transmission', selected: this.downloader === 'Transmission', onTap: () => { this.downloader = 'Transmission'; } })
      }.width('100%')
      Button(`推送至 ${this.downloader}`)
        .width('100%').height(46).borderRadius(23).backgroundColor(this.accentHex).fontColor(Color.White)
        .onClick(() => { this.showDownloadSheet = false; })
    }.padding(20).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      NativeBackHeader({
        title: `站点资源 (${this.resources.length})`,
        trailingText: 'Rust 9维',
        onBack: () => this.onBack()
      })

      Row({ space: 8 }) {
        ForEach(['全部', '2160p', '1080p', 'BluRay'], (res: string) => {
          NativeAdaptivePill({ title: res, selected: this.selectedRes === res, onTap: () => { this.selectedRes = res; } })
        })
      }.width('100%').padding({ left: 20 })

      if (this.loading && this.resources.length === 0) {
        LoadingProgress().width(32).height(32).color(this.accentHex).margin({ top: 48 })
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.filteredResources(), (row: MpResourceItem) => {
              Column() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
                  Column({ space: 7 }) {
                    Row({ space: 6 }) {
                      NativeAdaptiveBadge({ text: row.siteName, tintHex: this.accentHex, filled: true })
                      if (row.resolution.length > 0) {
                        NativeAdaptiveBadge({ text: row.resolution, tintHex: '#75C7FF' })
                      }
                      if (row.volumeFactor.length > 0) {
                        NativeAdaptiveBadge({ text: row.volumeFactor, tintHex: '#75E6A3' })
                      }
                    }.width('100%')
                    Text(row.title)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(2)
                      .width('100%')
                    Row() {
                      Text(formatByteSize(row.sizeBytes)).fontSize(12).fontColor('#75E6A3')
                      Text(` · ↑ ${row.seeders}  ↓ ${row.peers}`).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                      Blank()
                      if (row.resourceType.length > 0) {
                        Text(row.resourceType).fontSize(11).fontColor(mpSecondaryText(this.isDark))
                      }
                    }.width('100%')
                  }
                }
              }
              .width('100%')
              .onClick(() => {
                RustCoreBridge.filterAndGroupResources('[]', '{}');
                this.selectedItem = row;
                this.showDownloadSheet = true;
              })
            })
          }.padding({ left: 18, right: 18, bottom: 124 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
    }
    .bindSheet($$this.showDownloadSheet, this.downloadConfirmBuilder(), {
      detents: [SheetSize.MEDIUM],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .width('100%')
    .height('100%')
  }
}

/** 鸿蒙正在下载管理页（真实 `/api/v1/download/`，空态与 iOS 1:1 对齐）。 */
@Component
export struct HarmonyDownloadsPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private tasks: MpDownloadTask[] = [];
  @State private loading: boolean = true;
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadDownloads();
  }

  private async loadDownloads(): Promise<void> {
    this.loading = true;
    try {
      this.tasks = await MoviePilotRepository.shared().fetchDownloads();
    } catch {
      this.tasks = [];
    }
    this.loading = false;
  }

  build() {
    Column({ space: 12 }) {
      NativeBackHeader({ title: '正在下载', onBack: () => this.onBack() })

      if (this.loading) {
        LoadingProgress().width(32).height(32).color(this.accentHex).margin({ top: 48 })
      } else if (this.tasks.length === 0) {
        Column() {
          CinematicPanel({ panelPadding: 28 }) {
            Column({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(42).fontColor([mpSecondaryText(this.isDark)])
              Text('当前没有正在进行的下载任务').fontSize(15).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
              Text('从站点资源或订阅命中推送后将在此实时显示进度。').fontSize(12).fontColor(mpSecondaryText(this.isDark))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        }
        .padding({ left: 20, right: 20, top: 24 })
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.tasks, (task: MpDownloadTask) => {
              CinematicPanel({ panelPadding: 15 }) {
                Column({ space: 8 }) {
                  Text(task.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).maxLines(2).width('100%')
                  Progress({ value: task.progress, total: 100, type: ProgressType.Linear }).color(this.accentHex).backgroundColor('#24FFFFFF')
                  Row() {
                    Text(`↓ ${task.dlspeed}  ↑ ${task.upspeed}`).fontSize(12).fontColor('#75E6A3')
                    Blank()
                    Text(`${task.progress.toFixed(1)}% · ${formatByteSize(task.sizeBytes)}`).fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }.width('100%')
                }
              }
            })
          }.padding({ left: 18, right: 18, bottom: 124 })
        }.layoutWeight(1)
      }
    }.width('100%').height('100%')
  }
}
