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
 * 鸿蒙「更多」工作台一级主页面（严格按 4 大清晰业务域归类，告别混乱分组）：
 * 1. 资源与媒体流转（站点资源 / 站点管理 / 下载管理 / 文件管理 / 整理历史 / 媒体库）
 * 2. 插件与工作流（插件中心 / 工作流）
 * 3. 追剧与广场（追剧日历 / 订阅广场）
 * 4. 系统诊断（系统检查 / 定时服务 / 实时日志 / 词表管理 / 名称识别 / 网络测试，点击直达单功能页）
 */
@Component
export struct HarmonyMoreHubPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_BREAKPOINT) breakpoint: string = 'sm';
  @State private stats: MpDashboardStats = {
    movieCount: 0, tvCount: 0, episodeCount: 0, userCount: 0,
    storageUsedBytes: 0, storageTotalBytes: 0,
    downloadSpeed: 0, uploadSpeed: 0, downloadSize: 0, uploadSize: 0,
    memoryPercent: 0, memoryUsedBytes: 0, transferCounts: [], scheduleCount: 0
  };
  @State private activeDownloads: number = 0;
  @State private activeSites: number = 0;
  @State private installedPlugins: number = 0;
  @State private librariesCount: number = 0;
  @State private workflowsCount: number = 0;
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
        repo.fetchDownloads(),
        repo.fetchSites(),
        repo.fetchPlugins('installed'),
        repo.fetchMediaServerLibraries(),
        repo.fetchWorkflows()
      ]);
      this.stats = res[0];
      const tasks: MpDownloadTask[] = res[1];
      this.activeDownloads = tasks.length;
      this.activeSites = res[2].filter((s) => s.isActive).length;
      this.installedPlugins = res[3].length;
      this.librariesCount = res[4].length;
      this.workflowsCount = res[5].length;
    } catch {
      // keep existing state
    }
  }

  private liveSubtitle(item: MoreToolItem): string {
    if (item.id === 'sites' && this.activeSites > 0) { return `${this.activeSites} 站点启用`; }
    if (item.id === 'downloads') { return `${this.activeDownloads} 个任务`; }
    if (item.id === 'media_library' && this.librariesCount > 0) { return `${this.librariesCount} 个媒体库浏览`; }
    if (item.id === 'plugins' && this.installedPlugins > 0) { return `已装 ${this.installedPlugins} 款`; }
    if (item.id === 'workflows' && this.workflowsCount > 0) { return `${this.workflowsCount} 个自动化编排`; }
    return item.subtitle;
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
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(mpSecondaryText(this.isDark))
        .width('100%')

      Grid() {
        ForEach(items, (item: MoreToolItem) => {
          GridItem() {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: true }) {
                Column({ space: 10 }) {
                  Stack() {
                    SymbolGlyph($r(item.symbolName))
                      .fontSize(20)
                      .fontColor([item.tintHex])
                  }
                  .width(40)
                  .height(40)
                  .borderRadius(20)
                  .backgroundColor(HarmonyAppearanceStore.withAlpha(item.tintHex, this.isDark ? '28' : '1A'))

                  Column({ space: 3 }) {
                    Text(item.title)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(mpPrimaryText(this.isDark))
                      .maxLines(1)
                    Text(this.liveSubtitle(item))
                      .fontSize(11.5)
                      .fontColor(mpSecondaryText(this.isDark))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
              }
            }
            .width('100%')
            .accessibilityText(`${item.title}，${this.liveSubtitle(item)}`)
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
        subtitle: '资源、下载与自动化中心',
        primarySymbol: 'sys.symbol.magnifyingglass',
        primaryAccessibility: '全局搜索',
        onPrimaryClick: () => this.onOpenSearch()
      })

      Scroll() {
        Column({ space: 18 }) {
          // 实时运行概览卡
          Column() {
            CinematicPanel({ panelPadding: 16, cornerRadius: 20, interactive: true }) {
              Column({ space: 12 }) {
                Row() {
                  Text('实时运行概览')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(mpPrimaryText(this.isDark))
                    .layoutWeight(1)
                  NativeAdaptiveBadge({
                    text: this.activeDownloads > 0 ? `${this.activeDownloads} 任务活跃` : '空闲',
                    tintHex: this.activeDownloads > 0 ? '#34C759' : this.accentHex
                  })
                }.width('100%')

                Row({ space: 10 }) {
                  Row({ space: 8 }) {
                    SymbolGlyph($r('sys.symbol.arrow_down')).fontSize(16).fontColor(['#34C759'])
                    Column({ space: 2 }) {
                      Text('下载速度').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                      Text(formatSpeed(this.stats.downloadSpeed))
                        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    }.alignItems(HorizontalAlign.Start)
                  }
                  .layoutWeight(1)
                  .padding(12)
                  .borderRadius(14)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))

                  Row({ space: 8 }) {
                    SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(16).fontColor([this.accentHex])
                    Column({ space: 2 }) {
                      Text('上传速度').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                      Text(formatSpeed(this.stats.uploadSpeed))
                        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    }.alignItems(HorizontalAlign.Start)
                  }
                  .layoutWeight(1)
                  .padding(12)
                  .borderRadius(14)
                  .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                }.width('100%')
              }
            }
          }
          .width('100%')
          .onClick(() => this.onSelectRoute('downloads'))

          // 1. 资源与媒体流转
          this.toolGridSection('资源与媒体流转', MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 0))
          // 2. 插件与工作流
          this.toolGridSection('插件与工作流', MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 1))
          // 3. 追剧与广场
          this.toolGridSection('追剧与广场', MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 2))

          // 4. 系统诊断（6 项独立捷径直达）
          Column({ space: 10 }) {
            Text('系统诊断')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpSecondaryText(this.isDark))
              .width('100%')

            CinematicPanel({ panelPadding: 12, cornerRadius: 20 }) {
              Grid() {
                ForEach(MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 3), (item: MoreToolItem) => {
                  GridItem() {
                    Row({ space: 8 }) {
                      SymbolGlyph($r(item.symbolName))
                        .fontSize(17)
                        .fontColor([item.tintHex])
                      Text(item.title)
                        .fontSize(13.5)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(mpPrimaryText(this.isDark))
                        .maxLines(1)
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
                    .borderRadius(14)
                    .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                    .hoverEffect(HoverEffect.Highlight)
                    .onClick(() => this.onSelectRoute(item.id))
                  }
                }, (item: MoreToolItem) => item.id)
              }
              .columnsTemplate(this.gridTemplate())
              .columnsGap(10)
              .rowsGap(10)
              .width('100%')
            }
          }
          .width('100%')
        }
        .padding({ left: 16, right: 16, top: 6, bottom: 128 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
