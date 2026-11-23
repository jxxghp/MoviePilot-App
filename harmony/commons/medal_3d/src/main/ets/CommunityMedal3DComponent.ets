import { RustCoreBridge, MedalPalette } from '../../../../../core_rust_bridge/src/main/ets/bridge/RustCoreBridge';

/**
 * 鸿蒙原生 3D 社区勋章与 OffscreenCanvas 背面金属三遍凹雕组件：
 * 加载 `rawfile/community_medals/` 共享 73 枚 WebP 纹理，消费 Rust 金属色板，支持 360° 3D 翻转检视。
 */
@Component
export struct CommunityMedal3DComponent {
  @Prop medalId: string = 'contributor_gold';
  @Prop assetBaseName: string = 'contributor_gold';
  @Prop title: string = '社区贡献者';
  @Prop ownerName: string = 'MoviePilot 成员';
  @Prop earnedDate: string = '2026-11';
  @State private rotY: number = 0;
  @State private rotX: number = 0;
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private backCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  private palette(): MedalPalette {
    return RustCoreBridge.computeMedalPalette(this.medalId);
  }

  private drawEngravedBack(): void {
    const p = this.palette();
    const ctx = this.backCanvasCtx;
    const w = 188;
    const cx = w / 2;
    const cy = w / 2;
    ctx.clearRect(0, 0, w, w);
    ctx.fillStyle = p.base_hex;
    ctx.beginPath();
    ctx.arc(cx, cy, w * 0.48, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = p.rim_hex;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(cx, cy, w * 0.41, 0, Math.PI * 2);
    ctx.stroke();

    const drawPass = (text: string, y: number, size: number) => {
      ctx.font = `bold ${size}px sans-serif`;
      ctx.textAlign = 'center';
      // Pass 1: 亮边受光
      ctx.fillStyle = p.engrave_light_hex;
      ctx.fillText(text, cx + 1, y + 1);
      // Pass 2: 上缘暗槽
      ctx.fillStyle = p.engrave_dark_hex;
      ctx.fillText(text, cx - 1, y - 1);
      // Pass 3: 主凹雕文字
      ctx.fillText(text, cx, y);
    };

    drawPass('MOVIEPILOT', cy - 34, 11);
    drawPass(this.title, cy - 4, 16);
    drawPass(this.ownerName, cy + 22, 13);
    drawPass(this.earnedDate, cy + 44, 11);
  }

  private isShowingBack(): boolean {
    const norm = ((this.rotY % 360) + 360) % 360;
    return norm >= 90 && norm <= 270;
  }

  build() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (!this.isShowingBack()) {
          Image($rawfile(`community_medals/${this.assetBaseName}.webp`))
            .width(176)
            .height(176)
            .borderRadius(88)
            .objectFit(ImageFit.Cover)
        } else {
          Canvas(this.backCanvasCtx)
            .width(188)
            .height(188)
            .borderRadius(94)
            .scale({ x: -1, y: 1 })
            .onReady(() => this.drawEngravedBack())
        }
      }
      .width(196)
      .height(196)
      .borderRadius(98)
      .backgroundColor(this.palette().base_hex)
      .border({ width: 3, color: this.palette().rim_hex, radius: 98 })
      .rotate({ x: 0, y: 1, z: 0, angle: this.rotY, perspective: 8 })
      .gesture(
        PanGesture()
          .onActionUpdate((ev: GestureEvent) => {
            this.rotY += ev.offsetX * 0.12;
            this.rotX = Math.max(-20, Math.min(20, -ev.offsetY * 0.08));
          })
      )

      Text('左右拖动 360° 翻转查看背面金属凹雕')
        .fontSize(12)
        .fontColor('#99FFFFFF')
    }
    .alignItems(HorizontalAlign.Center)
  }
}
