import {
  RustCoreBridge,
  MoviePilotRepository,
  MpSiteItem,
  MpWorkflowItem,
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

/** 鸿蒙工作流列表 + 纯 ArkUI Canvas 节点画布（真实 `/api/v1/workflow/`）。 */
@Component
export struct HarmonyWorkflowCanvasPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private workflows: MpWorkflowItem[] = [];
  @State private loading: boolean = true;
  @State private scaleVal: number = 1.0;
  @State private offsetX: number = 12;
  @State private offsetY: number = 16;
  @State private selectedNode: string = '获取 RSS 资源';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadWorkflows();
  }

  private async loadWorkflows(): Promise<void> {
    this.loading = true;
    try {
      this.workflows = await MoviePilotRepository.shared().fetchWorkflows();
    } catch {
      this.workflows = [];
    }
    this.loading = false;
  }

  private drawEdges(): void {
    this.ctx.clearRect(0, 0, 360, 220);
    this.ctx.strokeStyle = this.accentHex;
    this.ctx.lineWidth = 3;
    this.ctx.beginPath();
    this.ctx.moveTo(155, 62);
    this.ctx.bezierCurveTo(185, 62, 185, 132, 200, 132);
    this.ctx.stroke();
  }

  build() {
    Column({ space: 12 }) {
      NativeBackHeader({
        title: `工作流 (${this.workflows.length})`,
        trailingText: `${Math.round(this.scaleVal * 100)}%`,
        onBack: () => this.onBack()
      })

      Scroll() {
        Column({ space: 12 }) {
          if (this.workflows.length > 0) {
            ForEach(this.workflows, (wf: MpWorkflowItem) => {
              CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
                Column({ space: 6 }) {
                  Row() {
                    Text(wf.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                    NativeAdaptiveBadge({ text: `${wf.actionCount} 节点`, tintHex: this.accentHex })
                  }.width('100%')
                  if (wf.description.length > 0) {
                    Text(wf.description).fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(2).width('100%')
                  }
                  if (wf.timer.length > 0) {
                    Text(`定时：${RustCoreBridge.analyzeCron(wf.timer).descriptionZh}`).fontSize(11).fontColor('#75C7FF').width('100%')
                  }
                }
              }
            })
          }

          CinematicPanel({ panelPadding: 14, cornerRadius: 20 }) {
            Column({ space: 8 }) {
              Text('交互式节点画布（双指缩放 / 拖拽）').fontSize(14).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark)).width('100%')
              Stack({ alignContent: Alignment.TopStart }) {
                Canvas(this.ctx).width('100%').height(210).onReady(() => this.drawEdges())
                Column({ space: 4 }) {
                  Text('● 获取 RSS 资源').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text('FetchRssAction').fontSize(10).fontColor('#CCFFFFFF')
                }
                .width(142).padding(10).borderRadius(12).backgroundColor('#709E7AF5')
                .border({ width: 1.1, color: '#9E7AF5', radius: 12 })
                .position({ x: 8 + this.offsetX, y: 28 + this.offsetY })
                .onClick(() => { this.selectedNode = '获取 RSS 资源'; })

                Column({ space: 4 }) {
                  Text('● 过滤资源').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text('FilterTorrentsAction').fontSize(10).fontColor('#CCFFFFFF')
                }
                .width(142).padding(10).borderRadius(12).backgroundColor('#88282236')
                .border({ width: 0.8, color: '#33FFFFFF', radius: 12 })
                .position({ x: 168 + this.offsetX, y: 102 + this.offsetY })
                .onClick(() => { this.selectedNode = '过滤资源'; })
              }
              .width('100%')
              .height(210)
              .scale({ x: this.scaleVal, y: this.scaleVal })
              .gesture(
                GestureGroup(GestureMode.Parallel,
                  PanGesture().onActionUpdate((ev: GestureEvent) => {
                    this.offsetX = Math.max(-40, Math.min(40, ev.offsetX * 0.4));
                    this.offsetY = Math.max(-20, Math.min(20, ev.offsetY * 0.4));
                  }),
                  PinchGesture().onActionUpdate((ev: GestureEvent) => {
                    this.scaleVal = Math.max(0.7, Math.min(1.5, ev.scale));
                  })
                )
              )
              Text(`当前选中节点：${this.selectedNode}`).fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
            }
          }
        }.padding({ left: 18, right: 18, bottom: 124 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.width('100%').height('100%')
  }
}

/** 鸿蒙站点管理与双向绿/玫红上下行流量图示页（真实 `/api/v1/site/` + `/api/v1/site/userdata/latest`）。 */
@Component
export struct HarmonySitesPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#9E7AF5';
  @State private sites: MpSiteItem[] = [];
  @State private loading: boolean = true;
  @State private selectedSite: MpSiteItem | null = null;
  @State private showDetail: boolean = false;
  onBack: () => void = () => {};

  aboutToAppear(): void {
    this.loadSites();
  }

  private async loadSites(): Promise<void> {
    this.loading = true;
    try {
      this.sites = await MoviePilotRepository.shared().fetchSites();
    } catch {
      this.sites = [];
    }
    this.loading = false;
  }

  private uploadWeight(s: MpSiteItem): number {
    const total = s.uploadBytes + s.downloadBytes;
    if (total <= 0) { return 50; }
    return Math.max(6, Math.min(94, Math.round((s.uploadBytes / total) * 100)));
  }

  @Builder
  siteDetailSheetBuilder() {
    Column({ space: 14 }) {
      if (this.selectedSite) {
        Text(this.selectedSite.name).fontSize(20).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
        Text(this.selectedSite.domain).fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
        Row({ space: 10 }) {
          Column() {
            CinematicPanel({ panelPadding: 12 }) {
              Column({ space: 3 }) {
                Text('累计上传').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                Text(formatByteSize(this.selectedSite.uploadBytes)).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#75E6A3')
              }.alignItems(HorizontalAlign.Start)
            }
          }.layoutWeight(1)
          Column() {
            CinematicPanel({ panelPadding: 12 }) {
              Column({ space: 3 }) {
                Text('累计下载').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                Text(formatByteSize(this.selectedSite.downloadBytes)).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#F58FBD')
              }.alignItems(HorizontalAlign.Start)
            }
          }.layoutWeight(1)
        }
        Row({ space: 10 }) {
          Column() {
            CinematicPanel({ panelPadding: 12 }) {
              Column({ space: 3 }) {
                Text('分享率').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                Text(this.selectedSite.ratio > 0 ? this.selectedSite.ratio.toFixed(2) : '--').fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
              }.alignItems(HorizontalAlign.Start)
            }
          }.layoutWeight(1)
          Column() {
            CinematicPanel({ panelPadding: 12 }) {
              Column({ space: 3 }) {
                Text('做种数 / 体积').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                Text(`${this.selectedSite.seeding} · ${formatByteSize(this.selectedSite.seedingSizeBytes)}`).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#75C7FF')
              }.alignItems(HorizontalAlign.Start)
            }
          }.layoutWeight(1)
        }
      }
    }.padding(20).width('100%')
  }

  build() {
    Column({ space: 12 }) {
      NativeBackHeader({
        title: `站点管理 (${this.sites.length})`,
        onBack: () => this.onBack()
      })

      if (this.loading && this.sites.length === 0) {
        LoadingProgress().width(32).height(32).color(this.accentHex).margin({ top: 48 })
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.sites, (s: MpSiteItem) => {
              Column() {
                CinematicPanel({ panelPadding: 15, cornerRadius: 20 }) {
                  Column({ space: 8 }) {
                    Row({ space: 8 }) {
                      Stack() {
                        SymbolGlyph($r('sys.symbol.worldclock')).fontSize(18).fontColor([Color.White])
                      }
                      .width(32).height(32).borderRadius(16).backgroundColor('#28FFFFFF')

                      Column({ space: 2 }) {
                        Row({ space: 6 }) {
                          Text(s.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                          NativeAdaptiveBadge({
                            text: s.isActive ? '已启用' : '已停用',
                            tintHex: s.isActive ? '#75E6A3' : '#FFCC6B'
                          })
                        }
                        Text(s.domain).fontSize(11).fontColor(mpSecondaryText(this.isDark))
                      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                      NativeAdaptivePill({ title: '数据', selected: false, onTap: () => { this.selectedSite = s; this.showDetail = true; } })
                    }.width('100%')

                    Row() {
                      Text(`↑ ${formatByteSize(s.uploadBytes)}`).fontSize(12).fontColor('#75E6A3')
                      Text(`↓ ${formatByteSize(s.downloadBytes)}`).fontSize(12).fontColor('#F58FBD').margin({ left: 12 })
                      Blank()
                      Text(`分享率 ${s.ratio > 0 ? s.ratio.toFixed(2) : '--'}${s.seeding > 0 ? ' · 做种 ' + s.seeding : ''}`)
                        .fontSize(11).fontColor(mpSecondaryText(this.isDark))
                    }.width('100%')

                    Row({ space: 3 }) {
                      Column().height(5).borderRadius(3).backgroundColor('#75E6A3').layoutWeight(this.uploadWeight(s))
                      Column().height(5).borderRadius(3).backgroundColor('#F58FBD').layoutWeight(100 - this.uploadWeight(s))
                    }.width('100%')
                  }
                }
              }
              .width('100%')
              .onClick(() => {
                this.selectedSite = s;
                this.showDetail = true;
              })
            })
          }.padding({ left: 18, right: 18, bottom: 124 })
        }.scrollBar(BarState.Off).layoutWeight(1)
      }
    }
    .bindSheet($$this.showDetail, this.siteDetailSheetBuilder(), {
      detents: [SheetSize.MEDIUM],
      blurStyle: BlurStyle.COMPONENT_THIN,
      dragBar: true,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .width('100%')
    .height('100%')
  }
}
