import {
  RustCoreBridge,
  MoviePilotRepository,
  MpStorageFile,
  MpTransferHistoryItem,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeBackHeader,
  HarmonyUnderlineTabBar,
  HarmonySegmentedSwitch,
  HarmonyThemeColors,
  HarmonyAppearanceStore,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import { HarmonyPlaybackRequest } from '@moviepilot/media_player';

/**
 * 鸿蒙多存储文件管理与整理历史页：
 * - 使用规范下划线页签栏切换「文件管理 / 整理历史」；
 * - 整理历史使用鸿蒙互斥分段控制器过滤「全部 / 成功 / 失败」；
 * - 支持直接点击音视频文件拉起鸿蒙原生 `AVPlayer` 播放。
 */
@Component
export struct HarmonyLibraryPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @Prop initialMode: string = 'files';
  @State private activeTabIdx: number = 0; // 0: 文件管理, 1: 整理历史
  @State private historyFilterIdx: number = 0; // 0: 全部, 1: 成功, 2: 失败
  @State private currentPath: string = '/';
  @State private files: MpStorageFile[] = [];
  @State private history: MpTransferHistoryItem[] = [];
  @State private loading: boolean = true;
  onBack: () => void = () => {};
  onPlayMedia: (req: HarmonyPlaybackRequest) => void = () => {};

  aboutToAppear(): void {
    this.activeTabIdx = this.initialMode === 'history' ? 1 : 0;
    this.loadData();
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    const repo = MoviePilotRepository.shared();
    try {
      if (this.activeTabIdx === 0) {
        this.files = await repo.fetchStorageFiles('local', this.currentPath);
      } else {
        this.history = await repo.fetchTransferHistory(1, 30);
      }
    } catch {
      // ignore
    }
    this.loading = false;
  }

  private filteredHistory(): MpTransferHistoryItem[] {
    if (this.historyFilterIdx === 1) {
      return this.history.filter((h: MpTransferHistoryItem) => h.status);
    }
    if (this.historyFilterIdx === 2) {
      return this.history.filter((h: MpTransferHistoryItem) => !h.status);
    }
    return this.history;
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: this.activeTabIdx === 0 ? `文件管理 (${this.files.length})` : `整理历史 (${this.history.length})`,
        trailingSymbol: 'sys.symbol.arrow_clockwise',
        trailingAccessibility: '刷新列表',
        onBack: () => this.onBack(),
        onTrailingClick: () => this.loadData()
      })

      HarmonyUnderlineTabBar({
        tabs: ['文件管理', '整理历史'],
        selectedIndex: this.activeTabIdx,
        onSelect: (idx: number) => {
          this.activeTabIdx = idx;
          this.loadData();
        }
      })

      if (this.activeTabIdx === 0) {
        Row({ space: 8 }) {
          NativeAdaptiveBadge({ text: '本地存储', tintHex: '#FAAD14', filled: true })
          Text(this.currentPath)
            .fontSize(12)
            .fontColor(mpSecondaryText(this.isDark))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.currentPath !== '/') {
            Text('返回上级')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accentHex)
              .onClick(() => {
                const parts = this.currentPath.split('/').filter((p: string) => p.length > 0);
                parts.pop();
                this.currentPath = parts.length > 0 ? '/' + parts.join('/') + '/' : '/';
                this.loadData();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      } else {
        Column() {
          HarmonySegmentedSwitch({
            options: ['全部', '成功', '失败'],
            selectedIndex: this.historyFilterIdx,
            onSelect: (idx: number) => { this.historyFilterIdx = idx; }
          })
        }
        .padding({ left: 16, right: 16 })
      }

      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color(this.accentHex)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            if (this.activeTabIdx === 0) {
              ForEach(this.files, (f: MpStorageFile) => {
                Column() {
                  CinematicPanel({ panelPadding: 13, cornerRadius: 16, interactive: true }) {
                    Row({ space: 12 }) {
                      SymbolGlyph($r(f.type === 'dir' ? 'sys.symbol.folder_fill' : 'sys.symbol.doc_text'))
                        .fontSize(22)
                        .fontColor([f.type === 'dir' ? this.accentHex : '#6EA8FE'])
                      Column({ space: 3 }) {
                        Text(f.name)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(mpPrimaryText(this.isDark))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(f.type === 'dir' ? '目录' : formatByteSize(f.sizeBytes))
                          .fontSize(11)
                          .fontColor(mpSecondaryText(this.isDark))
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      if (f.type === 'dir') {
                        Text('›').fontSize(18).fontColor(mpSecondaryText(this.isDark))
                      } else if (RustCoreBridge.detectPlayableMediaKind(f.name).length > 0) {
                        NativeAdaptiveBadge({ text: '直放', tintHex: '#52C41A' })
                      }
                    }.width('100%')
                  }
                }
                .width('100%')
                .onClick(() => {
                  if (f.type === 'dir') {
                    this.currentPath = f.path.endsWith('/') ? f.path : f.path + '/';
                    this.loadData();
                  } else {
                    const kind = RustCoreBridge.detectPlayableMediaKind(f.name);
                    if (kind.length > 0) {
                      const repo = MoviePilotRepository.shared();
                      const streamUrl = `${repo.baseUrl}/api/v1/storage/download?path=${encodeURIComponent(f.path)}&storage=${encodeURIComponent(f.storage)}&token=${encodeURIComponent(repo.token)}`;
                      this.onPlayMedia({
                        url: streamUrl,
                        title: f.name,
                        subtitle: `${f.storage} · ${formatByteSize(f.sizeBytes)}`,
                        isAudio: kind === 'audio'
                      });
                    }
                  }
                })
              }, (f: MpStorageFile) => `${f.storage}_${f.path}`)
            } else {
              ForEach(this.filteredHistory(), (h: MpTransferHistoryItem) => {
                CinematicPanel({ panelPadding: 13, cornerRadius: 16 }) {
                  Row({ space: 12 }) {
                    if (h.posterUrl.length > 0) {
                      Image(h.posterUrl)
                        .width(56)
                        .height(82)
                        .borderRadius(9)
                        .objectFit(ImageFit.Cover)
                        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    }
                    Column({ space: 5 }) {
                      Row() {
                        Text(`${h.title}${h.seasons ? ' ' + h.seasons : ''}${h.episodes ? h.episodes : ''}`)
                          .fontSize(14)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(mpPrimaryText(this.isDark))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                        NativeAdaptiveBadge({
                          text: h.status ? h.mode : '失败',
                          tintHex: h.status ? '#52C41A' : '#FF5C6C'
                        })
                      }.width('100%')
                      Text(`○ ${h.srcStorage}：${h.src}`).fontSize(11).fontColor(mpSecondaryText(this.isDark)).maxLines(1).width('100%')
                      Text(`● ${h.destStorage}：${h.dest}`).fontSize(11).fontColor('#6EA8FE').maxLines(1).width('100%')
                      if (h.date.length > 0) {
                        Text(h.date).fontSize(10).fontColor(mpSecondaryText(this.isDark)).width('100%')
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }.width('100%')
                }
              }, (h: MpTransferHistoryItem) => String(h.id))
            }
          }
          .padding({ left: 16, right: 16, bottom: 40 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}
