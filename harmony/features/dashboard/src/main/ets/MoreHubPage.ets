import {
  MoviePilotRepository,
  MpDashboardStats,
  MpDownloadTask,
  formatSpeed
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  HarmonyAppearanceStore,
  HarmonyPageHeader,
  HarmonyThemeColors,
  MORE_TOOL_ITEMS,
  MoreToolItem,
  NativeAdaptiveBadge,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

/**
 * 鸿蒙「更多」工作台一级主页面（替代 iOS 隐藏式二次点击 4+1 浮层）：
 * - 遵循 HarmonyOS 左侧大标题 + 右侧动态光感搜索圆钮规范；
 * - 实时聚合下载器吞吐状态卡片、2 列（手机）/ 4 列（折叠屏展开/平板）响应式工具矩阵与系统诊断快捷入口；
 * - 全部交互卡片启用 `CinematicPanel({ interactive: true })`，在 HarmonyOS 7 自动呈现官方动态光感形变反馈，低版本平滑回退。
 */
@Component
export struct HarmonyMoreHubPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @StorageLink(HarmonyAppearanceStore.KEY_BREAKPOINT) breakpoint: string = 'sm';
  @State private stats: MpDashboardStats = {
    movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0,
    storageUsedBytes: 0, storageTotalBytes: 0,
    downloadSpeed: 0, uploadSpeed: 0, downloadSize: 0, uploadSize: 0,
    memoryPercent: 0, memoryUsedBytes: 0, transferCounts: [], scheduleCount: 0
  };
  @State private activeDownloads: number = 0;
  onSelectRoute: (routeId: string) => void = () => {};
  onOpenSearch: () => void = () => {};

  aboutToAppear(): void {
    this.loadSummary();
  }

  private async loadSummary(): Promise<void> {
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchDashboardStats(),
        repo.fetchDownloads()
      ]);
      this.stats = res[0];
      const tasks: MpDownloadTask[] = res[1];
      this.activeDownloads = tasks.length;
    } catch {
      // keep existing state
    }
  }

  private gridTemplate(): string {
    if (this.breakpoint === 'lg') { return '1fr 1fr 1fr 1fr'; }
    if (this.breakpoint === 'md') { return '1fr 1fr 1fr'; }
    return '1fr 1fr';
  }

  @Builder
  toolGridSection(title: string, items: MoreToolItem[]) {
    Column({ space: 10 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(mpSecondaryText(this.isDark))
        .width('100%')

      Grid() {
        ForEach(items, (item: MoreToolItem) => {
          GridItem() {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: true }) {
                Column({ space: 10 }) {
                  Row() {
                    Stack() {
                      SymbolGlyph($r(item.symbolName))
                        .fontSize(20)
                        .fontColor([item.tintHex])
                    }
                    .width(38)
                    .height(38)
                    .borderRadius(12)
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))

                    Blank()
                    Text('›').fontSize(18).fontColor(mpSecondaryText(this.isDark))
                  }.width('100%')

                  Column({ space: 3 }) {
                    Text(item.title)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(1)
                    Text(item.subtitle)
                      .fontSize(11)
                      .fontColor(mpSecondaryText(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                }
              }
            }
            .width('100%')
            .accessibilityText(`${item.title}，${item.subtitle}`)
            .onClick(() => this.onSelectRoute(item.id))
          }
        }, (item: MoreToolItem) => item.id)
      }
      .columnsTemplate(this.gridTemplate())
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
    }
    .width('100%')
  }

  build() {
    Column() {
      HarmonyPageHeader({
        title: '更多',
        subtitle: '资源、下载、存储与自动化工作台',
        primarySymbol: 'sys.symbol.magnifyingglass',
        primaryAccessibility: '全局搜索',
        onPrimaryClick: () => this.onOpenSearch()
      })

      Scroll() {
        Column({ space: 18 }) {
          // 实时下载器状态速览卡
          Column() {
            CinematicPanel({ panelPadding: 16, cornerRadius: 20, interactive: true }) {
              Row({ space: 12 }) {
                Stack() {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                    .fontSize(24)
                    .fontColor(['#52C41A'])
                }
                .width(44)
                .height(44)
                .borderRadius(14)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))

                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text('下载与传输通道')
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                    NativeAdaptiveBadge({
                      text: this.activeDownloads > 0 ? `${this.activeDownloads} 进行中` : '空闲',
                      tintHex: this.activeDownloads > 0 ? '#52C41A' : this.accentHex
                    })
                  }
                  Text(`↓ ${formatSpeed(this.stats.downloadSpeed)}  ·  ↑ ${formatSpeed(this.stats.uploadSpeed)}  ·  ${this.stats.scheduleCount} 项定时任务`)
                    .fontSize(12)
                    .fontColor(mpSecondaryText(this.isDark))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('›').fontSize(20).fontColor(mpSecondaryText(this.isDark))
              }
              .width('100%')
            }
          }
          .width('100%')
          .onClick(() => this.onSelectRoute('downloads'))

          this.toolGridSection('媒体与资源', MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 0))
          this.toolGridSection('生态与自动化', MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 1))

          // 系统诊断与定时服务快捷入口
          Column() {
            CinematicPanel({ panelPadding: 15, cornerRadius: 18, interactive: true }) {
              Row({ space: 12 }) {
                Stack() {
                  SymbolGlyph($r('sys.symbol.bolt'))
                    .fontSize(20)
                    .fontColor([this.accentHex])
                }
                .width(38)
                .height(38)
                .borderRadius(12)
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))

                Column({ space: 2 }) {
                  Text('捷径与系统诊断')
                    .fontSize(15)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                  Text('查看全部定时任务状态与服务端实时日志')
                    .fontSize(12)
                    .fontColor(mpSecondaryText(this.isDark))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('›').fontSize(20).fontColor(mpSecondaryText(this.isDark))
              }
              .width('100%')
            }
          }
          .width('100%')
          .onClick(() => this.onSelectRoute('diagnostics'))
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 124 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
