import {
  RustCoreBridge,
  MoviePilotRepository,
  MpSiteItem,
  MpWorkflowItem,
  MpWorkflowActionNode,
  MpWorkflowFlowEdge,
  MpWorkflowShareItem,
  formatByteSize
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  NativeAdaptivePill,
  NativeBackHeader,
  HarmonyPillTabBar,
  HarmonySheetHeader,
  HarmonyEntityLogo,
  HarmonyAdaptiveLayout,
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  HarmonyCardGridSkeleton,
  HarmonyWorkflowCanvasSkeleton,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

interface CanvasNodeLayout {
  id: string;
  name: string;
  type: string;
  x: number;
  y: number;
}

const NODE_CARD_W: number = 136;
const NODE_CARD_H: number = 50;

/**
 * 鸿蒙工作流中心与交互式节点画布：
 * - 支持真实运行（`/run`）、启停（`/start`、`/pause`）、删除（`DELETE /api/v1/workflow/{id}`）及社区工作流复用（`/workflow/fork`）；
 * - 修复画布 `PanGesture`/`PinchGesture` 基准偏移并在拖拽时实时重绘三次贝塞尔连线。
 */
@Component
export struct HarmonyWorkflowCanvasPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @State private wfTabIdx: number = 0; // 0: 我的工作流, 1: 工作流广场
  @State private workflows: MpWorkflowItem[] = [];
  @State private shares: MpWorkflowShareItem[] = [];
  @State private activeWorkflowId: number = -1;
  @State private loading: boolean = true;
  @State private loadingShares: boolean = false;
  @State private busyWfId: number = -1;
  @State private forkingId: number = -1;
  @State private notice: string = '';

  // 画布平移与缩放状态（记录起始值，杜绝跳变跑飞）
  @State private scaleVal: number = 1.0;
  @State private offsetX: number = 12;
  @State private offsetY: number = 18;
  @State private selectedNode: string = '';
  private panStartX: number = 12;
  private panStartY: number = 18;
  private pinchStartScale: number = 1.0;
  private canvasReady: boolean = false;
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
      if (this.workflows.length > 0 && this.activeWorkflowId < 0) {
        this.activeWorkflowId = this.workflows[0].id;
      }
    } catch {
      this.workflows = [];
    }
    this.loading = false;
    this.syncSelectedNodeDefault();
    this.drawEdges();
  }

  private async loadSharesIfNeeded(): Promise<void> {
    if (this.shares.length > 0 || this.loadingShares) { return; }
    this.loadingShares = true;
    try {
      this.shares = await MoviePilotRepository.shared().fetchWorkflowShares();
    } catch {
      this.shares = [];
    }
    this.loadingShares = false;
  }

  private activeWorkflow(): MpWorkflowItem | null {
    if (this.workflows.length === 0) { return null; }
    const found = this.workflows.find((w: MpWorkflowItem) => w.id === this.activeWorkflowId);
    return found ?? this.workflows[0];
  }

  private activeNodes(): CanvasNodeLayout[] {
    const wf = this.activeWorkflow();
    if (!wf) {
      return [];
    }
    const rawActions: MpWorkflowActionNode[] = wf.actions ? wf.actions : [];
    if (rawActions.length === 0) {
      return [
        { id: 'n1', name: '获取 RSS 资源', type: 'FetchRssAction', x: 10, y: 24 },
        { id: 'n2', name: '过滤与推送下载', type: 'FilterTorrentsAction', x: 184, y: 106 }
      ];
    }
    let minX = Number.POSITIVE_INFINITY;
    let maxX = Number.NEGATIVE_INFINITY;
    let minY = Number.POSITIVE_INFINITY;
    let maxY = Number.NEGATIVE_INFINITY;
    for (let i = 0; i < rawActions.length; i++) {
      const a = rawActions[i];
      if (a.posX < minX) { minX = a.posX; }
      if (a.posX > maxX) { maxX = a.posX; }
      if (a.posY < minY) { minY = a.posY; }
      if (a.posY > maxY) { maxY = a.posY; }
    }
    const spanX = maxX - minX;
    const spanY = maxY - minY;
    const out: CanvasNodeLayout[] = [];
    for (let i = 0; i < rawActions.length; i++) {
      const a = rawActions[i];
      let nx: number;
      let ny: number;
      if (spanX > 1 || spanY > 1) {
        nx = 8 + (spanX > 1 ? ((a.posX - minX) / spanX) * 186 : (i % 2) * 168);
        ny = 14 + (spanY > 1 ? ((a.posY - minY) / spanY) * 124 : Math.floor(i / 2) * 66);
      } else {
        nx = 8 + (i % 2) * 172;
        ny = 16 + Math.floor(i / 2) * 68;
      }
      out.push({
        id: a.id || `act_${i}`,
        name: a.name || a.type || `节点 ${i + 1}`,
        type: a.type || 'Action',
        x: Math.round(nx),
        y: Math.round(ny)
      });
    }
    return out;
  }

  private activeEdges(nodes: CanvasNodeLayout[]): MpWorkflowFlowEdge[] {
    const wf = this.activeWorkflow();
    if (wf && wf.flows && wf.flows.length > 0) {
      return wf.flows;
    }
    const fallback: MpWorkflowFlowEdge[] = [];
    for (let i = 0; i + 1 < nodes.length; i++) {
      fallback.push({
        id: `e_${i}`,
        source: nodes[i].id,
        target: nodes[i + 1].id
      });
    }
    return fallback;
  }

  private syncSelectedNodeDefault(): void {
    const nodes = this.activeNodes();
    if (nodes.length > 0 && this.selectedNode.length === 0) {
      this.selectedNode = nodes[0].name;
    }
  }

  private drawEdges(): void {
    if (!this.canvasReady) { return; }
    this.ctx.clearRect(0, 0, 1200, 600);
    const nodes = this.activeNodes();
    const edges = this.activeEdges(nodes);
    this.ctx.strokeStyle = this.accentHex;
    this.ctx.lineWidth = 2.6;
    this.ctx.lineCap = 'round';

    for (let i = 0; i < edges.length; i++) {
      const edge = edges[i];
      const src = nodes.find((n: CanvasNodeLayout) => n.id === edge.source);
      const dst = nodes.find((n: CanvasNodeLayout) => n.id === edge.target);
      if (!src || !dst) { continue; }
      const x1 = src.x + this.offsetX + NODE_CARD_W;
      const y1 = src.y + this.offsetY + NODE_CARD_H * 0.5;
      const x2 = dst.x + this.offsetX;
      const y2 = dst.y + this.offsetY + NODE_CARD_H * 0.5;
      const ctrlSpan = Math.max(28, Math.abs(x2 - x1) * 0.5);
      this.ctx.beginPath();
      this.ctx.moveTo(x1, y1);
      this.ctx.bezierCurveTo(x1 + ctrlSpan, y1, x2 - ctrlSpan, y2, x2, y2);
      this.ctx.stroke();

      // 终点锚点圆点
      this.ctx.fillStyle = this.accentHex;
      this.ctx.beginPath();
      this.ctx.arc(x2, y2, 3.4, 0, Math.PI * 2);
      this.ctx.fill();
    }
  }

  private isPaused(wf: MpWorkflowItem): boolean {
    const st = (wf.state || '').toUpperCase();
    return st === 'P' || st === 'PAUSE' || st === 'S' || st === 'STOP';
  }

  @Builder
  private workflowCardMenuBuilder(wf: MpWorkflowItem) {
    Menu() {
      MenuItem({ content: '立即运行一次' })
        .onClick(() => { this.handleRun(wf); })
      MenuItem({ content: this.isPaused(wf) ? '启用工作流' : '暂停工作流' })
        .onClick(() => { this.handleToggleState(wf); })
      MenuItem({ content: '在画布中查看' })
        .onClick(() => {
          this.activeWorkflowId = wf.id;
          this.offsetX = 12;
          this.offsetY = 18;
          this.scaleVal = 1.0;
          const nodes = this.activeNodes();
          this.selectedNode = nodes.length > 0 ? nodes[0].name : '';
          this.drawEdges();
        })
      MenuItem({ content: '删除工作流' })
        .contentFontColor('#E84855')
        .onClick(() => { this.confirmDeleteWorkflow(wf); })
    }
  }

  private async handleRun(wf: MpWorkflowItem): Promise<void> {
    if (this.busyWfId === wf.id) { return; }
    this.busyWfId = wf.id;
    const ok = await MoviePilotRepository.shared().runWorkflow(wf.id);
    this.busyWfId = -1;
    this.notice = ok ? `已触发执行工作流「${wf.name}」` : '执行工作流失败';
    if (ok) { await this.loadWorkflows(); }
  }

  private async handleToggleState(wf: MpWorkflowItem): Promise<void> {
    if (this.busyWfId === wf.id) { return; }
    this.busyWfId = wf.id;
    const paused = this.isPaused(wf);
    const ok = paused
      ? await MoviePilotRepository.shared().startWorkflow(wf.id)
      : await MoviePilotRepository.shared().pauseWorkflow(wf.id);
    this.busyWfId = -1;
    this.notice = ok ? (paused ? `已启用「${wf.name}」` : `已暂停「${wf.name}」`) : '切换工作流状态失败';
    if (ok) { await this.loadWorkflows(); }
  }

  private confirmDeleteWorkflow(wf: MpWorkflowItem): void {
    this.getUIContext().showAlertDialog({
      title: '删除工作流',
      message: `确定要删除工作流「${wf.name}」吗？此操作不可撤销。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: '#E84855',
        action: () => {
          this.executeDeleteWorkflow(wf);
        }
      }
    });
  }

  private async executeDeleteWorkflow(wf: MpWorkflowItem): Promise<void> {
    this.busyWfId = wf.id;
    const ok = await MoviePilotRepository.shared().deleteWorkflow(wf.id);
    this.busyWfId = -1;
    this.notice = ok ? `已删除工作流「${wf.name}」` : '删除工作流失败';
    if (ok) {
      if (this.activeWorkflowId === wf.id) {
        this.activeWorkflowId = -1;
      }
      await this.loadWorkflows();
    }
  }

  private async handleForkShare(sh: MpWorkflowShareItem): Promise<void> {
    if (this.forkingId === sh.id) { return; }
    this.forkingId = sh.id;
    const ok = await MoviePilotRepository.shared().forkWorkflow(sh);
    this.forkingId = -1;
    this.notice = ok ? `已复用工作流「${sh.shareTitle || sh.name}」` : '复用工作流失败';
    if (ok) {
      await this.loadWorkflows();
    }
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: (this.loading && this.workflows.length === 0) ? '工作流' : `工作流 (${this.workflows.length})`,
        trailingSymbol: 'sys.symbol.arrow_clockwise',
        trailingAccessibility: '刷新工作流',
        onBack: () => this.onBack(),
        onTrailingClick: () => {
          if (this.wfTabIdx === 0) {
            this.loadWorkflows();
          } else {
            this.shares = [];
            this.loadSharesIfNeeded();
          }
        }
      })

      HarmonyPillTabBar({
        tabs: [
          (this.loading && this.workflows.length === 0) ? '我的工作流' : `我的工作流 (${this.workflows.length})`,
          '工作流广场'
        ],
        selectedIndex: this.wfTabIdx,
        onSelect: (idx: number) => {
          this.wfTabIdx = idx;
          if (idx === 1) {
            this.loadSharesIfNeeded();
          }
        }
      })

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#34C759').padding({ left: 16, right: 16 }).width('100%')
      }

      if (this.wfTabIdx === 0) {
        Scroll() {
          Column({ space: 12 }) {
            if (this.loading && this.workflows.length === 0) {
              HarmonyCardGridSkeleton({
                variant: 'workflow',
                count: 2,
                horizontalPadding: 0,
                bottomPadding: 4
              })
              HarmonyWorkflowCanvasSkeleton()
            } else if (this.workflows.length === 0) {
              CinematicPanel({ panelPadding: 22, cornerRadius: 18 }) {
                Column({ space: 6 }) {
                  Text('暂无已配置工作流').fontSize(14.5).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                  Text('可切至「工作流广场」一键复用社区自动化模板。').fontSize(12).fontColor(mpSecondaryText(this.isDark))
                }.width('100%').alignItems(HorizontalAlign.Center)
              }
            } else {
              Grid() {
                ForEach(this.workflows, (wf: MpWorkflowItem) => {
                  GridItem() {
                    Column() {
                    CinematicPanel({ panelPadding: 14, cornerRadius: 18, interactive: true }) {
                      Column({ space: 8 }) {
                        Row({ space: 8 }) {
                          Text(wf.name)
                            .fontSize(15)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(mpPrimaryText(this.isDark))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          NativeAdaptiveBadge({
                            text: this.isPaused(wf) ? '已暂停' : '已启用',
                            tintHex: this.isPaused(wf) ? '#F29B38' : '#34C759'
                          })
                          NativeAdaptiveBadge({ text: `${wf.actionCount} 节点`, tintHex: this.accentHex })
                        }.width('100%')

                        if (wf.description.length > 0) {
                          Text(wf.description).fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(2).width('100%')
                        }
                        Row({ space: 8 }) {
                          if (wf.timer.length > 0) {
                            Text(`定时：${RustCoreBridge.analyzeCron(wf.timer).descriptionZh}`)
                              .fontSize(11.5).fontColor(this.accentHex)
                          }
                          if (wf.runCount > 0) {
                            Text(`已执行 ${wf.runCount} 次`).fontSize(11.5).fontColor(mpSecondaryText(this.isDark))
                          }
                        }.width('100%')

                        Row({ space: 8 }) {
                          Row({ space: 4 }) {
                            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(12).fontColor([Color.White])
                            Text('运行').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Color.White)
                          }
                          .padding({ left: 10, right: 12, top: 6, bottom: 6 })
                          .borderRadius(14)
                          .backgroundColor(this.accentHex)
                          .opacity(this.busyWfId === wf.id ? 0.6 : 1)
                          .onClick(() => { this.handleRun(wf); })

                          Row({ space: 4 }) {
                            SymbolGlyph($r(this.isPaused(wf) ? 'sys.symbol.play_fill' : 'sys.symbol.pause_fill'))
                              .fontSize(12).fontColor([mpPrimaryText(this.isDark)])
                            Text(this.isPaused(wf) ? '启用' : '暂停')
                              .fontSize(12).fontWeight(FontWeight.Medium).fontColor(mpPrimaryText(this.isDark))
                          }
                          .padding({ left: 10, right: 12, top: 6, bottom: 6 })
                          .borderRadius(14)
                          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
                          .onClick(() => { this.handleToggleState(wf); })

                          NativeAdaptivePill({
                            title: '画布',
                            selected: (this.activeWorkflow()?.id ?? -1) === wf.id,
                            onTap: () => {
                              this.activeWorkflowId = wf.id;
                              this.offsetX = 12;
                              this.offsetY = 18;
                              this.scaleVal = 1.0;
                              const nodes = this.activeNodes();
                              this.selectedNode = nodes.length > 0 ? nodes[0].name : '';
                              this.drawEdges();
                            }
                          })

                          Blank()

                          Button({ type: ButtonType.Circle }) {
                            SymbolGlyph($r('sys.symbol.trash')).fontSize(14).fontColor(['#E84855'])
                          }
                          .width(32).height(32)
                          .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
                          .accessibilityText('删除工作流')
                          .onClick(() => this.confirmDeleteWorkflow(wf))
                        }.width('100%')
                      }
                    }
                    }
                    .width('100%')
                    .bindContextMenu(this.workflowCardMenuBuilder(wf), ResponseType.LongPress)
                  }
                }, (wf: MpWorkflowItem) => `${wf.id}_${wf.state}_${wf.runCount}`)
              }
              .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
              .columnsGap(12)
              .rowsGap(12)
              .width('100%')

              // 交互式工作流节点画布
              CinematicPanel({ panelPadding: 14, cornerRadius: 20 }) {
                Column({ space: 8 }) {
                  Row() {
                    Text(`节点拓扑画布${this.activeWorkflow() ? ' · ' + (this.activeWorkflow()?.name ?? '') : ''}`)
                      .fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                    Text(`${Math.round(this.scaleVal * 100)}% · 重置`)
                      .fontSize(12).fontColor(this.accentHex)
                      .onClick(() => {
                        this.scaleVal = 1.0;
                        this.offsetX = 12;
                        this.offsetY = 18;
                        this.drawEdges();
                      })
                  }.width('100%')

                  Stack({ alignContent: Alignment.TopStart }) {
                    Canvas(this.ctx)
                      .width('100%')
                      .height(220)
                      .onReady(() => {
                        this.canvasReady = true;
                        this.drawEdges();
                      })

                    ForEach(this.activeNodes(), (nd: CanvasNodeLayout) => {
                      Column({ space: 3 }) {
                        Text(`● ${nd.name}`)
                          .fontSize(11.5)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(nd.type)
                          .fontSize(9.5)
                          .fontColor('#CCFFFFFF')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .width(NODE_CARD_W)
                      .height(NODE_CARD_H)
                      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                      .justifyContent(FlexAlign.Center)
                      .alignItems(HorizontalAlign.Start)
                      .borderRadius(12)
                      .backgroundColor(this.selectedNode === nd.name
                        ? HarmonyAppearanceStore.withAlpha(this.accentHex, 'C8')
                        : '#CC1B2230')
                      .border({
                        width: this.selectedNode === nd.name ? 1.2 : 0.8,
                        color: this.selectedNode === nd.name ? this.accentHex : '#38FFFFFF',
                        radius: 12
                      })
                      .position({ x: nd.x + this.offsetX, y: nd.y + this.offsetY })
                      .onClick(() => { this.selectedNode = nd.name; })
                    }, (nd: CanvasNodeLayout) => nd.id)
                  }
                  .width('100%')
                  .height(220)
                  .clip(true)
                  .borderRadius(14)
                  .backgroundColor(this.isDark ? '#14FFFFFF' : '#0A000000')
                  .scale({ x: this.scaleVal, y: this.scaleVal })
                  .gesture(
                    GestureGroup(GestureMode.Parallel,
                      PanGesture()
                        .onActionStart(() => {
                          this.panStartX = this.offsetX;
                          this.panStartY = this.offsetY;
                        })
                        .onActionUpdate((ev: GestureEvent) => {
                          this.offsetX = Math.max(-160, Math.min(160, Math.round(this.panStartX + ev.offsetX)));
                          this.offsetY = Math.max(-90, Math.min(90, Math.round(this.panStartY + ev.offsetY)));
                          this.drawEdges();
                        }),
                      PinchGesture()
                        .onActionStart(() => {
                          this.pinchStartScale = this.scaleVal;
                        })
                        .onActionUpdate((ev: GestureEvent) => {
                          this.scaleVal = Math.max(0.65, Math.min(1.6, this.pinchStartScale * ev.scale));
                          this.drawEdges();
                        })
                    )
                  )

                  Text(this.selectedNode.length > 0 ? `当前选中节点：${this.selectedNode}（支持单指拖拽与双指缩放）` : '支持单指拖拽画布与双指缩放')
                    .fontSize(11.5)
                    .fontColor(mpSecondaryText(this.isDark))
                    .width('100%')
                }
              }
            }
          }.padding({ left: 16, right: 16, bottom: 44 })
        }.scrollBar(BarState.Off).layoutWeight(1)
      } else {
        if (this.loadingShares) {
          HarmonyCardGridSkeleton({
            variant: 'workflow',
            fillViewport: true,
            bottomPadding: 44
          })
        } else if (this.shares.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.share')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
            Text('暂无社区共享工作流').fontSize(14).fontColor(mpSecondaryText(this.isDark))
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.shares, (sh: MpWorkflowShareItem) => {
              GridItem() {
                CinematicPanel({ panelPadding: 14, cornerRadius: 18 }) {
                  Column({ space: 6 }) {
                    Row({ space: 8 }) {
                      Text(sh.shareTitle || sh.name)
                        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      NativeAdaptiveBadge({ text: `${sh.count} 复用`, tintHex: this.accentHex })
                    }.width('100%')

                    if (sh.shareComment.length > 0) {
                      Text(sh.shareComment)
                        .fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(2).width('100%')
                    }

                    Row({ space: 8 }) {
                      Text(`分享者：${sh.shareUser || '社区用户'}`)
                        .fontSize(11.5).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
                      Button(this.forkingId === sh.id ? '复用中…' : '复用工作流')
                        .height(30).padding({ left: 12, right: 12 }).borderRadius(15)
                        .fontSize(12).fontWeight(FontWeight.Bold)
                        .backgroundColor(this.accentHex).fontColor(Color.White)
                        .enabled(this.forkingId !== sh.id)
                        .onClick(() => { this.handleForkShare(sh); })
                    }.width('100%')
                  }
                }
              }
            }, (sh: MpWorkflowShareItem) => `${sh.id}_${sh.count}`)
          }
          .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
          .columnsGap(12)
          .rowsGap(10)
          .padding({ left: 16, right: 16, bottom: 44 })
          .scrollBar(BarState.Off)
          .layoutWeight(1)
        }
      }
    }.width('100%').height('100%')
  }
}

/**
 * 鸿蒙「站点管理」页（搭载真实 `/api/v1/site/icon/{id}` 图标与精确 0 字节双向流量比例条）。
 */
@Component
export struct HarmonySitesPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @State private sites: MpSiteItem[] = [];
  @State private loading: boolean = true;
  @State private notice: string = '';

  // 流量详情弹层
  @State private selectedSite: MpSiteItem | null = null;
  @State private showDetail: boolean = false;

  // 新增 / 编辑站点弹层
  @State private showEditor: boolean = false;
  @State private isCreateMode: boolean = true;
  @State private edId: number = 0;
  @State private edRawJson: string = '';
  @State private edName: string = '';
  @State private edPriority: string = '1';
  @State private edUrl: string = '';
  @State private edDomain: string = '';
  @State private edRss: string = '';
  @State private edCookie: string = '';
  @State private edUa: string = '';
  @State private edActive: boolean = true;
  @State private edProxy: boolean = false;
  @State private edRender: boolean = false;
  @State private saving: boolean = false;

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

  private openCreateSite(): void {
    this.isCreateMode = true;
    this.edId = 0;
    this.edRawJson = '';
    this.edName = '';
    this.edPriority = String(this.sites.length + 1);
    this.edUrl = '';
    this.edDomain = '';
    this.edRss = '';
    this.edCookie = '';
    this.edUa = '';
    this.edActive = true;
    this.edProxy = false;
    this.edRender = false;
    this.showEditor = true;
  }

  private openEditSite(s: MpSiteItem): void {
    this.isCreateMode = false;
    this.edId = s.id;
    this.edRawJson = s.rawJson ?? '';
    this.edName = s.name;
    this.edPriority = String(s.priority ?? 1);
    this.edUrl = s.url;
    this.edDomain = s.domain;
    this.edRss = s.rss ?? '';
    this.edCookie = s.cookie ?? '';
    this.edUa = s.ua ?? '';
    this.edActive = s.isActive;
    this.edProxy = Boolean(s.proxy);
    this.edRender = Boolean(s.render);
    this.showEditor = true;
  }

  private async saveSiteForm(): Promise<void> {
    if (this.saving || this.edName.trim().length === 0 || this.edUrl.trim().length === 0) { return; }
    this.saving = true;
    const item: MpSiteItem = {
      id: this.edId,
      name: this.edName.trim(),
      domain: this.edDomain.trim(),
      url: this.edUrl.trim(),
      isActive: this.edActive,
      uploadBytes: 0,
      downloadBytes: 0,
      ratio: 0,
      seeding: 0,
      seedingSizeBytes: 0,
      bonus: 0,
      iconDataUri: '',
      priority: Number(this.edPriority) || 1,
      rss: this.edRss.trim(),
      cookie: this.edCookie.trim(),
      ua: this.edUa.trim(),
      proxy: this.edProxy,
      render: this.edRender,
      rawJson: this.edRawJson
    };
    const ok = await MoviePilotRepository.shared().saveSite(item, this.isCreateMode);
    this.saving = false;
    this.showEditor = false;
    this.notice = ok ? `已保存站点「${item.name}」` : '保存站点失败，请检查配置';
    if (ok) { await this.loadSites(); }
  }

  private confirmDeleteCurrentSite(): void {
    const targetId = this.edId;
    const targetName = this.edName;
    this.getUIContext().showAlertDialog({
      title: '确认删除站点',
      message: `确定要删除站点「${targetName}」吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确认删除',
        fontColor: '#E84855',
        action: () => {
          this.executeDeleteSite(targetId, targetName);
        }
      }
    });
  }

  private async executeDeleteSite(siteId: number, siteName: string): Promise<void> {
    this.showEditor = false;
    const ok = await MoviePilotRepository.shared().deleteSite(siteId);
    this.notice = ok ? `已删除站点「${siteName}」` : '删除站点失败';
    await this.loadSites();
  }

  private proportionalUploadPct(s: MpSiteItem): number {
    const total = s.uploadBytes + s.downloadBytes;
    if (total <= 0) { return 0; }
    return Math.max(2, Math.min(98, Math.round((s.uploadBytes / total) * 100)));
  }

  @Builder
  private siteCardMenuBuilder(s: MpSiteItem) {
    Menu() {
      MenuItem({ content: '查看流量详情' })
        .onClick(() => {
          this.selectedSite = s;
          this.showDetail = true;
        })
      MenuItem({ content: '编辑站点配置' })
        .onClick(() => { this.openEditSite(s); })
      MenuItem({ content: '测试站点连通性' })
        .onClick(async () => {
          const msg = await MoviePilotRepository.shared().testSiteConnectivity(s.id);
          this.notice = `${s.name}：${msg}`;
        })
      MenuItem({ content: '删除站点' })
        .contentFontColor('#E84855')
        .onClick(() => {
          this.edId = s.id;
          this.edName = s.name;
          this.confirmDeleteCurrentSite();
        })
    }
  }

  @Builder
  trafficBarBuilder(s: MpSiteItem) {
    if (s.uploadBytes <= 0 && s.downloadBytes <= 0) {
      // 0 B 上传且 0 B 下载：渲染 0% 纯中性空槽，绝不伪造绿/粉假条
      Column()
        .width('100%')
        .height(5)
        .borderRadius(3)
        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
    } else if (s.uploadBytes > 0 && s.downloadBytes <= 0) {
      Column()
        .width('100%')
        .height(5)
        .borderRadius(3)
        .backgroundColor('#34C759')
    } else if (s.uploadBytes <= 0 && s.downloadBytes > 0) {
      Column()
        .width('100%')
        .height(5)
        .borderRadius(3)
        .backgroundColor('#EE6896')
    } else {
      Row({ space: 3 }) {
        Column()
          .height(5)
          .borderRadius(3)
          .backgroundColor('#34C759')
          .layoutWeight(this.proportionalUploadPct(s))
        Column()
          .height(5)
          .borderRadius(3)
          .backgroundColor('#EE6896')
          .layoutWeight(100 - this.proportionalUploadPct(s))
      }.width('100%')
    }
  }

  @Builder
  siteDetailSheetBuilder() {
    Column({ space: 12 }) {
      if (this.selectedSite) {
        HarmonySheetHeader({
          title: this.selectedSite.name,
          cancelText: '关闭',
          actionText: '编辑',
          onCancel: () => { this.showDetail = false; },
          onAction: () => {
            const s = this.selectedSite;
            this.showDetail = false;
            if (s) { this.openEditSite(s); }
          }
        })

        Scroll() {
          Column({ space: 14 }) {
            Row({ space: 10 }) {
              HarmonyEntityLogo({
                kind: 'site',
                value: this.selectedSite.name,
                dataUri: this.selectedSite.iconDataUri,
                logoSize: 28,
                cornerRadius: 7
              })
              Text(this.selectedSite.domain).fontSize(12.5).fontColor(mpSecondaryText(this.isDark)).layoutWeight(1)
            }.width('100%')

            Row({ space: 10 }) {
              Column() {
                CinematicPanel({ panelPadding: 12 }) {
                  Column({ space: 3 }) {
                    Text('累计上传').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                    Text(formatByteSize(this.selectedSite.uploadBytes)).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#34C759')
                  }.alignItems(HorizontalAlign.Start)
                }
              }.layoutWeight(1)
              Column() {
                CinematicPanel({ panelPadding: 12 }) {
                  Column({ space: 3 }) {
                    Text('累计下载').fontSize(11).fontColor(mpSecondaryText(this.isDark))
                    Text(formatByteSize(this.selectedSite.downloadBytes)).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#EE6896')
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
                    Text(`${this.selectedSite.seeding} · ${formatByteSize(this.selectedSite.seedingSizeBytes)}`).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.accentHex)
                  }.alignItems(HorizontalAlign.Start)
                }
              }.layoutWeight(1)
            }

            Button('测试站点连通性')
              .width('100%').height(44).borderRadius(22)
              .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
              .fontColor(mpPrimaryText(this.isDark))
              .onClick(async () => {
                if (!this.selectedSite) { return; }
                const msg = await MoviePilotRepository.shared().testSiteConnectivity(this.selectedSite.id);
                this.notice = `${this.selectedSite.name}：${msg}`;
                this.showDetail = false;
              })
          }
          .width('100%')
          .padding({ bottom: 20 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }

  @Builder
  siteEditorSheetBuilder() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: this.isCreateMode ? '新增站点' : '编辑站点',
        cancelText: '取消',
        actionText: this.saving ? '保存中' : '保存',
        actionEnabled: !this.saving && this.edName.trim().length > 0 && this.edUrl.trim().length > 0,
        onCancel: () => { this.showEditor = false; },
        onAction: () => { this.saveSiteForm(); }
      })

      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              Text('站点名称').fontSize(12).fontColor(mpSecondaryText(this.isDark))
              TextInput({ placeholder: '例如：高清视界', text: this.edName })
                .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
                .onChange((v: string) => { this.edName = v; })
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)

            Column({ space: 4 }) {
              Text('优先级').fontSize(12).fontColor(mpSecondaryText(this.isDark))
              TextInput({ placeholder: '1', text: this.edPriority })
                .type(InputType.Number)
                .fontColor(mpPrimaryText(this.isDark))
                .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
                .onChange((v: string) => { this.edPriority = v; })
            }.width(86).alignItems(HorizontalAlign.Start)
          }.width('100%')

          Text('站点地址 (URL)').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
          TextInput({ placeholder: 'https://example.com', text: this.edUrl })
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
            .onChange((v: string) => { this.edUrl = v; })

          Text('站点域名（留空自动提取）').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
          TextInput({ placeholder: 'example.com', text: this.edDomain })
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
            .onChange((v: string) => { this.edDomain = v; })

          Text('RSS 订阅地址（可选）').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
          TextInput({ placeholder: 'https://example.com/rss...', text: this.edRss })
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
            .onChange((v: string) => { this.edRss = v; })

          Text('站点 Cookie').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
          TextArea({ placeholder: '粘贴浏览器完整 Cookie', text: this.edCookie })
            .height(86)
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
            .onChange((v: string) => { this.edCookie = v; })

          Text('User-Agent（可选）').fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
          TextInput({ placeholder: '留空使用默认 UA', text: this.edUa })
            .fontColor(mpPrimaryText(this.isDark)).placeholderColor(mpSecondaryText(this.isDark))
            .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).borderRadius(12)
            .onChange((v: string) => { this.edUa = v; })

          CinematicPanel({ panelPadding: 14, cornerRadius: 16 }) {
            Column({ space: 10 }) {
              Row() {
                Text('启用站点').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.edActive })
                  .selectedColor(this.accentHex).onChange((v: boolean) => { this.edActive = v; })
              }.width('100%')
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Row() {
                Text('使用代理访问').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.edProxy })
                  .selectedColor(this.accentHex).onChange((v: boolean) => { this.edProxy = v; })
              }.width('100%')
              Divider().color(HarmonyThemeColors.divider(this.isDark))
              Row() {
                Text('浏览器仿真渲染').fontSize(14).fontColor(mpPrimaryText(this.isDark)).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.edRender })
                  .selectedColor(this.accentHex).onChange((v: boolean) => { this.edRender = v; })
              }.width('100%')
            }
          }

          if (!this.isCreateMode) {
            Button('删除此站点')
              .width('100%').height(44).borderRadius(22)
              .backgroundColor(HarmonyThemeColors.softDangerBg(this.isDark))
              .fontColor('#E84855').fontWeight(FontWeight.Bold)
              .onClick(() => { this.confirmDeleteCurrentSite(); })
          }
        }.padding({ bottom: 28 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }
    .padding(20).width('100%').height('100%')
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: (this.loading && this.sites.length === 0) ? '站点管理' : `站点管理 (${this.sites.length})`,
        trailingSymbol: 'sys.symbol.plus',
        trailingAccessibility: '新增站点',
        onBack: () => this.onBack(),
        onTrailingClick: () => this.openCreateSite()
      })

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#34C759').padding({ left: 16, right: 16 }).width('100%')
      }

      if (this.loading && this.sites.length === 0) {
        HarmonyCardGridSkeleton({
          variant: 'site',
          fillViewport: true,
          bottomPadding: 44
        })
      } else if (this.sites.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.worldclock')).fontSize(38).fontColor([mpSecondaryText(this.isDark)])
          Text('暂无已配置站点，点击右上角添加').fontSize(14).fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.sites, (s: MpSiteItem) => {
            GridItem() {
              Column() {
                CinematicPanel({ panelPadding: 15, cornerRadius: 20, interactive: true }) {
                  Column({ space: 8 }) {
                    Row({ space: 10 }) {
                      HarmonyEntityLogo({
                        kind: 'site',
                        value: s.name,
                        dataUri: s.iconDataUri,
                        logoSize: 34,
                        cornerRadius: 9
                      })

                      Column({ space: 2 }) {
                        Row({ space: 6 }) {
                          Text(s.name).fontSize(15).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                          NativeAdaptiveBadge({
                            text: s.isActive ? '已启用' : '已停用',
                            tintHex: s.isActive ? '#34C759' : '#F29B38'
                          })
                        }
                        Text(s.domain).fontSize(11).fontColor(mpSecondaryText(this.isDark))
                      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

                      NativeAdaptivePill({ title: '编辑', selected: false, onTap: () => this.openEditSite(s) })
                    }.width('100%')

                    Row() {
                      Text(`↑ ${formatByteSize(s.uploadBytes)}`).fontSize(12).fontColor('#34C759')
                      Text(`↓ ${formatByteSize(s.downloadBytes)}`).fontSize(12).fontColor('#EE6896').margin({ left: 12 })
                      Blank()
                      Text(`分享率 ${s.ratio > 0 ? s.ratio.toFixed(2) : '--'}${s.seeding > 0 ? ' · 做种 ' + s.seeding : ''}`)
                        .fontSize(11).fontColor(mpSecondaryText(this.isDark))
                    }.width('100%')

                    this.trafficBarBuilder(s)
                  }
                }
              }
              .width('100%')
              .onClick(() => {
                this.selectedSite = s;
                this.showDetail = true;
              })
              .bindContextMenu(this.siteCardMenuBuilder(s), ResponseType.LongPress)
            }
          }, (s: MpSiteItem) => `${s.id}_${s.name}_${s.isActive}_${s.iconDataUri.length}`)
        }
        .columnsTemplate(HarmonyAdaptiveLayout.cardGridTemplate(this.windowWidthVp))
        .columnsGap(12)
        .rowsGap(12)
        .padding({ left: 16, right: 16, bottom: 44 })
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }

      Blank().width(0).height(0).bindSheet($$this.showDetail, this.siteDetailSheetBuilder(), {
        detents: HarmonyAdaptiveLayout.adaptiveSheetDetents(this.windowHeightVp),
        preferType: HarmonyAdaptiveLayout.sheetPreferType(this.windowWidthVp),
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showEditor, this.siteEditorSheetBuilder(), {
        detents: [SheetSize.LARGE],
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
