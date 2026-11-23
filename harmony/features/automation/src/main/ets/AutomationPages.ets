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
  HarmonySheetHeader,
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';

/** 鸿蒙工作流列表 + 交互式节点画布（真实 `/api/v1/workflow/`）。 */
@Component
export struct HarmonyWorkflowCanvasPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
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
                    Text(`定时：${RustCoreBridge.analyzeCron(wf.timer).descriptionZh}`).fontSize(11).fontColor(this.accentHex).width('100%')
                  }
                }
              }
            }, (wf: MpWorkflowItem) => String(wf.id))
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
                .width(142).padding(10).borderRadius(12)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, 'B8'))
                .border({ width: 1.1, color: this.accentHex, radius: 12 })
                .position({ x: 8 + this.offsetX, y: 28 + this.offsetY })
                .onClick(() => { this.selectedNode = '获取 RSS 资源'; })

                Column({ space: 4 }) {
                  Text('● 过滤资源').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text('FilterTorrentsAction').fontSize(10).fontColor('#CCFFFFFF')
                }
                .width(142).padding(10).borderRadius(12).backgroundColor('#B81B2230')
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
        }.padding({ left: 16, right: 16, bottom: 40 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }.width('100%').height('100%')
  }
}

/**
 * 鸿蒙「站点管理」页（支持完整新增、编辑、删除、连通测试与双向流量展示）。
 */
@Component
export struct HarmonySitesPage {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
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
  @State private showDeleteConfirm: boolean = false;

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

  private uploadWeight(s: MpSiteItem): number {
    const total = s.uploadBytes + s.downloadBytes;
    if (total <= 0) { return 50; }
    return Math.max(6, Math.min(94, Math.round((s.uploadBytes / total) * 100)));
  }

  @Builder
  siteDetailSheetBuilder() {
    Column({ space: 14 }) {
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
        Text(this.selectedSite.domain).fontSize(12).fontColor(mpSecondaryText(this.isDark)).width('100%')
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
    }.padding(20).width('100%')
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
              .onClick(() => { this.showDeleteConfirm = true; })
          }
        }.padding({ bottom: 28 })
      }.scrollBar(BarState.Off).layoutWeight(1)
    }
    .bindSheet($$this.showDeleteConfirm, this.deleteConfirmSheetBuilder(), {
      detents: [SheetSize.FIT_CONTENT],
      blurStyle: BlurStyle.COMPONENT_REGULAR,
      dragBar: true,
        showClose: false,
      backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
    })
    .padding(20).width('100%').height('100%')
  }

  @Builder
  deleteConfirmSheetBuilder() {
    Column({ space: 16 }) {
      Text('确认删除站点').fontSize(18).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark)).width('100%')
      Text(`确定要删除站点「${this.edName}」吗？`).fontSize(14).fontColor(mpSecondaryText(this.isDark)).width('100%')
      Row({ space: 12 }) {
        Button('取消').layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor(HarmonyThemeColors.chipFill(this.isDark)).fontColor(mpPrimaryText(this.isDark))
          .onClick(() => { this.showDeleteConfirm = false; })
        Button('确认删除').layoutWeight(1).height(44).borderRadius(22)
          .backgroundColor('#E84855').fontColor(Color.White).fontWeight(FontWeight.Bold)
          .onClick(async () => {
            this.showDeleteConfirm = false;
            this.showEditor = false;
            const ok = await MoviePilotRepository.shared().deleteSite(this.edId);
            this.notice = ok ? `已删除站点「${this.edName}」` : '删除站点失败';
            await this.loadSites();
          })
      }.width('100%')
    }.padding(22).width('100%')
  }

  build() {
    Column({ space: 10 }) {
      NativeBackHeader({
        title: `站点管理 (${this.sites.length})`,
        trailingSymbol: 'sys.symbol.plus',
        trailingAccessibility: '新增站点',
        onBack: () => this.onBack(),
        onTrailingClick: () => this.openCreateSite()
      })

      if (this.notice.length > 0) {
        Text(this.notice).fontSize(12).fontColor('#34C759').padding({ left: 16, right: 16 }).width('100%')
      }

      if (this.loading && this.sites.length === 0) {
        Column() { LoadingProgress().width(32).height(32).color(this.accentHex) }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            ForEach(this.sites, (s: MpSiteItem) => {
              Column() {
                CinematicPanel({ panelPadding: 15, cornerRadius: 20, interactive: true }) {
                  Column({ space: 8 }) {
                    Row({ space: 8 }) {
                      Stack() {
                        SymbolGlyph($r('sys.symbol.worldclock')).fontSize(18).fontColor([this.accentHex])
                      }
                      .width(34).height(34).borderRadius(17)
                      .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, this.isDark ? '26' : '18'))

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

                    Row({ space: 3 }) {
                      Column().height(5).borderRadius(3).backgroundColor('#34C759').layoutWeight(this.uploadWeight(s))
                      Column().height(5).borderRadius(3).backgroundColor('#EE6896').layoutWeight(100 - this.uploadWeight(s))
                    }.width('100%')
                  }
                }
              }
              .width('100%')
              .onClick(() => {
                this.selectedSite = s;
                this.showDetail = true;
              })
            }, (s: MpSiteItem) => `${s.id}_${s.name}_${s.isActive}`)
          }.padding({ left: 16, right: 16, bottom: 40 })
        }.scrollBar(BarState.Off).layoutWeight(1)
      }

      Blank().width(0).height(0).bindSheet($$this.showDetail, this.siteDetailSheetBuilder(), {
        detents: [SheetSize.MEDIUM],
        blurStyle: BlurStyle.COMPONENT_REGULAR,
        dragBar: true,
        showClose: false,
        backgroundColor: HarmonyThemeColors.overlayFallback(this.isDark)
      })
      Blank().width(0).height(0).bindSheet($$this.showEditor, this.siteEditorSheetBuilder(), {
        detents: [SheetSize.LARGE],
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
