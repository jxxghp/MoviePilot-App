import { CinematicPanel, NativeAdaptiveBadge, NativeAdaptivePill } from '../../../../commons/design_system/src/main/ets/components/CinematicSurfaces';
import { RustCoreBridge } from '../../../../commons/core_rust_bridge/src/main/ets/bridge/RustCoreBridge';

/**
 * 鸿蒙工作流列表 + 纯 ArkUI Canvas 手势缩放平移节点画布 + 站点管理（双向绿/玫红流量比例条）。
 */
@Component
export struct HarmonyWorkflowCanvasPage {
  @State private scaleVal: number = 1.0;
  @State private offsetX: number = 12;
  @State private offsetY: number = 24;
  @State private selectedNode: string = '获取 RSS 资源';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  onBack: () => void = () => {};

  private drawEdges(): void {
    this.ctx.clearRect(0, 0, 360, 420);
    this.ctx.strokeStyle = '#9E7AF5';
    this.ctx.lineWidth = 3;
    this.ctx.beginPath();
    this.ctx.moveTo(155, 72);
    this.ctx.bezierCurveTo(185, 72, 185, 162, 200, 162);
    this.ctx.stroke();
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('工作流画布').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text(`${Math.round(this.scaleVal * 100)}%`).fontSize(13).fontColor('#9E7AF5')
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      Text(`定时调度：${RustCoreBridge.analyzeCron('*/15 * * * *').descriptionZh}`)
        .fontSize(12).fontColor('#A8FFFFFF').padding({ left: 20 }).width('100%')

      Stack({ alignContent: Alignment.TopStart }) {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .onReady(() => this.drawEdges())

        Column({ space: 4 }) {
          Text('● 获取 RSS 资源').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('FetchRssAction').fontSize(10).fontColor('#AAFFFFFF')
        }
        .width(150).padding(12).borderRadius(14).backgroundColor('#709E7AF5')
        .border({ width: 1.2, color: '#9E7AF5', radius: 14 })
        .position({ x: 16 + this.offsetX, y: 40 + this.offsetY })
        .onClick(() => { this.selectedNode = '获取 RSS 资源'; })

        Column({ space: 4 }) {
          Text('● 过滤资源').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
          Text('FilterTorrentsAction').fontSize(10).fontColor('#AAFFFFFF')
        }
        .width(150).padding(12).borderRadius(14).backgroundColor('#88282236')
        .border({ width: 0.8, color: '#33FFFFFF', radius: 14 })
        .position({ x: 196 + this.offsetX, y: 130 + this.offsetY })
        .onClick(() => { this.selectedNode = '过滤资源'; })
      }
      .layoutWeight(1)
      .width('100%')
      .scale({ x: this.scaleVal, y: this.scaleVal })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PanGesture().onActionUpdate((ev: GestureEvent) => {
            this.offsetX = ev.offsetX;
            this.offsetY = ev.offsetY;
          }),
          PinchGesture().onActionUpdate((ev: GestureEvent) => {
            this.scaleVal = Math.max(0.5, Math.min(1.8, ev.scale));
          })
        )
      )

      CinematicPanel({ panelPadding: 14 }) {
        Column({ space: 8 }) {
          Text(this.selectedNode).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White).width('100%')
          Row({ space: 8 }) {
            NativeAdaptivePill({ title: '编辑参数', selected: true })
            NativeAdaptivePill({ title: '连线', selected: false })
          }.width('100%')
        }
      }.padding({ left: 18, right: 18, bottom: 112 })
    }.width('100%').height('100%')
  }
}

/** 鸿蒙站点管理与双向绿/玫红上下行流量图示页。 */
@Component
export struct HarmonySitesPage {
  onBack: () => void = () => {};

  private readonly sites: string[][] = [
    ['瓷器', 'hdwing.org', '↑ 3.03 TB', '↓ 783.18 GB', '分享率 3.96', '78'],
    ['憨憨', 'hhanclub.net', '↑ 5.99 TB', '↓ 3.11 TB', '分享率 1.92 · 做种 64', '65'],
    ['观众', 'audiences.me', '↑ 17.24 TB', '↓ 4.96 TB', '分享率 3.47 · 做种 128', '77']
  ];

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('‹ 返回').fontSize(15).fontColor(Color.White).onClick(() => this.onBack())
        Blank()
        Text('站点管理 (51)').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Blank()
        Text('+').fontSize(22).fontColor(Color.White)
      }.width('100%').padding({ left: 18, right: 18, top: 46 })

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.sites, (s: string[]) => {
            CinematicPanel({ panelPadding: 15 }) {
              Column({ space: 8 }) {
                Row() {
                  Text(s[0]).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  NativeAdaptiveBadge({ text: '已启用', tintHex: '#75E6A3' }).margin({ left: 8 })
                  Blank()
                  NativeAdaptivePill({ title: '测试', selected: false })
                }.width('100%')
                Text(s[1]).fontSize(12).fontColor('#99FFFFFF').width('100%')
                Row() {
                  Text(s[2]).fontSize(13).fontColor('#75E6A3')
                  Text(s[3]).fontSize(13).fontColor('#F58FBD').margin({ left: 12 })
                  Blank()
                  Text(s[4]).fontSize(12).fontColor('#CCFFFFFF')
                }.width('100%')
                Row({ space: 3 }) {
                  Column().height(5).borderRadius(3).backgroundColor('#75E6A3').layoutWeight(Number(s[5]))
                  Column().height(5).borderRadius(3).backgroundColor('#F58FBD').layoutWeight(100 - Number(s[5]))
                }.width('100%')
              }
            }
          })
        }.padding({ left: 20, right: 20, bottom: 120 })
      }.layoutWeight(1)
    }.width('100%').height('100%')
  }
}
