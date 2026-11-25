import {
  MoviePilotRepository,
  MpDownloadTask
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  HarmonyAppearanceStore,
  HarmonyPageHeader,
  HarmonyThemeColors,
  MORE_TOOL_ITEMS,
  MoreToolItem,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

/**
 * 鸿蒙「更多」工作台一级主页面（按 3 大清晰业务域归类，右上角承载系统设置入口，站点管理归属设置页，追剧日历与订阅广场归属订阅页）：
 * 1. 资源与媒体流转（站点资源 / 下载管理 / 文件管理 / 整理历史 / 媒体库）
 * 2. 插件与工作流（插件中心 / 工作流）
 * 3. 快捷工具与系统诊断（系统检查 / 定时服务 / 实时日志 / 词表管理 / 名称识别 / 网络测试，点击直达单功能页）
 */
@Component
export struct HarmonyMoreHubPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_BREAKPOINT) breakpoint: string = 'sm';
  @State private activeDownloads: number = 0;
  @State private installedPlugins: number = 0;
  @State private librariesCount: number = 0;
  @State private workflowsCount: number = 0;
  @State private loadingSummary: boolean = true;
  onSelectRoute: (routeId: string) => void = () => {};

  aboutToAppear(): void {
    this.loadSummary();
  }

  private async loadSummary(): Promise<void> {
    this.loadingSummary = true;
    const repo = MoviePilotRepository.shared();
    try {
      const res = await Promise.all([
        repo.fetchDownloads(),
        repo.fetchPlugins('installed'),
        repo.fetchMediaServerLibraries(),
        repo.fetchWorkflows()
      ]);
      const tasks: MpDownloadTask[] = res[0];
      this.activeDownloads = tasks.length;
      this.installedPlugins = res[1].length;
      this.librariesCount = res[2].length;
      this.workflowsCount = res[3].length;
    } catch {
      // keep existing state
    }
    this.loadingSummary = false;
  }

  private liveSubtitle(item: MoreToolItem): string {
    if (this.loadingSummary) { return item.subtitle; }
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
        primarySymbol: 'sys.symbol.gearshape',
        primaryAccessibility: '系统设置',
        onPrimaryClick: () => this.onSelectRoute('settings')
      })

      Scroll() {
        Column({ space: 18 }) {
          // 1. 资源与媒体流转
          this.toolGridSection('资源与媒体流转', MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 0))
          // 2. 插件与工作流
          this.toolGridSection('插件与工作流', MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 1))

          // 3. 快捷工具与系统诊断（6 项独立捷径直达）
          Column({ space: 10 }) {
            Text('快捷工具与系统诊断')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpSecondaryText(this.isDark))
              .width('100%')

            CinematicPanel({ panelPadding: 12, cornerRadius: 20 }) {
              Grid() {
                ForEach(MORE_TOOL_ITEMS.filter((i: MoreToolItem) => i.group === 2), (item: MoreToolItem) => {
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
