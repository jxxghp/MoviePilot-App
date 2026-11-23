import { image } from '@kit.ImageKit';
import { RustCoreBridge, MedalPalette, MpCommunityMedal } from '@moviepilot/core_rust_bridge';
import { CinematicPanel, NativeAdaptiveBadge, mpPrimaryText, mpSecondaryText, HarmonyAppearanceStore } from '@moviepilot/design_system';

const medalAssetCache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();

/**
 * 从主包 `rawfile/community_medals/` 安全解码雕塑级勋章贴图（跨 HAR 模块可靠访问主包资源）。
 */
@Component
struct MedalRawfileImage {
  @Prop @Watch('onAssetChanged') assetName: string = '';
  @Prop imgSize: number = 62;
  @Prop imgOpacity: number = 1.0;
  @Prop shadowRadius: number = 10;
  @Prop shadowOffsetY: number = 5;
  @Prop shadowColor: string = '#45000000';
  @State private pm: image.PixelMap | null = null;

  aboutToAppear(): void {
    this.loadRawfile();
  }

  onAssetChanged(): void {
    this.loadRawfile();
  }

  private loadRawfile(): void {
    const key = (this.assetName ?? '').trim();
    if (!key) { return; }
    const hit = medalAssetCache.get(key);
    if (hit) {
      this.pm = hit;
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx || !ctx.resourceManager) { return; }
      ctx.resourceManager.getRawFileContent(`community_medals/${key}`).then(async (bytes: Uint8Array) => {
        try {
          const copyBuf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
          const src = image.createImageSource(copyBuf);
          const decoded = await src.createPixelMap();
          try { src.release(); } catch { /* ignore */ }
          if (decoded) {
            medalAssetCache.set(key, decoded);
            if (this.assetName === key) {
              this.pm = decoded;
            }
          }
        } catch {
          // ignore decode error
        }
      }).catch(() => {});
    } catch {
      // ignore host context error
    }
  }

  build() {
    if (this.pm) {
      Image(this.pm)
        .width(this.imgSize)
        .height(this.imgSize)
        .objectFit(ImageFit.Contain)
        .opacity(this.imgOpacity)
        .shadow({ radius: this.shadowRadius, color: this.shadowColor, offsetY: this.shadowOffsetY })
    } else {
      Column()
        .width(this.imgSize)
        .height(this.imgSize)
        .borderRadius(this.imgSize / 2)
        .backgroundColor('#18FFFFFF')
        .opacity(this.imgOpacity)
    }
  }
}

/**
 * 鸿蒙原生 3D 社区勋章与真实背面金属三遍凹雕组件：
 * - 正面加载 `rawfile/community_medals/` 共享 73 枚真实雕塑级 WebP 浮雕贴图（`code-front-t4.webp` 等）
 * - 背面叠加真实 `-back.webp` 金属底盘 + 5 段开口六边形 MoviePilot 印记 + 三遍受光凹雕（亮边/暗槽/主刻）
 * - 支持 360° 3D 透视旋转、点光源反射与惯性翻转检视
 */
@Component
export struct CommunityMedal3DComponent {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @Prop medalId: string = 'code';
  @Prop frontAsset: string = 'code-front-t4.webp';
  @Prop backAsset: string = 'code-back.webp';
  @Prop title: string = '核心代码贡献';
  @Prop subtitle: string = 'Tier 4';
  @Prop ownerName: string = 'MoviePilot';
  @Prop earnedDate: string = '2026-11';
  @State private rotY: number = 0;
  @State private rotX: number = 0;
  @State private shimmerOffset: number = 0;
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private backCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  private palette(): MedalPalette {
    return RustCoreBridge.computeMedalPalette(this.medalId);
  }

  private drawEngravedOverlay(): void {
    const p = this.palette();
    const ctx = this.backCanvasCtx;
    const w = 240;
    const cx = w / 2;
    const cy = w / 2;
    ctx.clearRect(0, 0, w, w);

    // 5 段开口六边形 MoviePilot 制造商印记
    ctx.save();
    ctx.strokeStyle = p.engrave_dark_hex;
    ctx.lineWidth = 2.4;
    ctx.beginPath();
    const r = 13;
    const my = cy - 52;
    for (let i = 0; i < 6; i++) {
      const a = (Math.PI / 3) * i - Math.PI / 6;
      const px = cx + Math.cos(a) * r;
      const py = my + Math.sin(a) * r;
      if (i === 0) {
        ctx.moveTo(px, py);
      } else if (i !== 5) {
        ctx.lineTo(px, py);
      }
    }
    ctx.stroke();
    ctx.restore();

    const drawCarved = (text: string, y: number, size: number) => {
      ctx.font = `bold ${size}px sans-serif`;
      ctx.textAlign = 'center';
      // Pass 1: 底部高光受光边
      ctx.fillStyle = p.engrave_light_hex;
      ctx.globalAlpha = 0.85;
      ctx.fillText(text, cx + 1.2, y + 1.4);
      // Pass 2: 顶部深色凹槽阴影
      ctx.fillStyle = p.engrave_dark_hex;
      ctx.globalAlpha = 0.92;
      ctx.fillText(text, cx - 1.0, y - 1.1);
      // Pass 3: 主凹雕文字
      ctx.globalAlpha = 0.82;
      ctx.fillText(text, cx, y);
      ctx.globalAlpha = 1.0;
    };

    drawCarved('MOVIEPILOT', cy - 22, 11);
    drawCarved(this.title, cy + 6, 17);
    drawCarved(`@${this.ownerName}`, cy + 32, 13);
    drawCarved(this.earnedDate, cy + 54, 11);
  }

  private isShowingBack(): boolean {
    const norm = ((this.rotY % 360) + 360) % 360;
    return norm >= 90 && norm <= 270;
  }

  build() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        // 金属光晕底座
        Column()
          .width(248)
          .height(248)
          .borderRadius(124)
          .radialGradient({
            center: ['50%', '50%'],
            radius: 130,
            colors: [[`${this.palette().rim_hex}`, 0], ['#00000000', 1]]
          })
          .opacity(0.28)

        // 3D 透视旋转勋章主体
        Stack({ alignContent: Alignment.Center }) {
          if (!this.isShowingBack()) {
            MedalRawfileImage({
              assetName: this.frontAsset,
              imgSize: 236,
              imgOpacity: 1.0,
              shadowRadius: 22,
              shadowOffsetY: 12,
              shadowColor: '#66000000'
            })
          } else {
            Stack({ alignContent: Alignment.Center }) {
              MedalRawfileImage({
                assetName: this.backAsset,
                imgSize: 236,
                imgOpacity: 1.0,
                shadowRadius: 22,
                shadowOffsetY: 12,
                shadowColor: '#66000000'
              })
              Canvas(this.backCanvasCtx)
                .width(240)
                .height(240)
                .onReady(() => this.drawEngravedOverlay())
            }
            .scale({ x: -1, y: 1 })
          }
        }
        .width(244)
        .height(244)
        .rotate({ x: 0, y: 1, z: 0, angle: this.rotY, perspective: 10 })
        .rotate({ x: 1, y: 0, z: 0, angle: this.rotX, perspective: 10 })
        .gesture(
          PanGesture()
            .onActionUpdate((ev: GestureEvent) => {
              this.rotY += ev.offsetX * 0.14;
              this.rotX = Math.max(-22, Math.min(22, -ev.offsetY * 0.08));
              this.shimmerOffset = ev.offsetX * 0.5;
            })
        )
      }
      .width(260)
      .height(260)

      Row({ space: 10 }) {
        Button(this.isShowingBack() ? '翻转至正面' : '翻转查看背面雕刻')
          .fontSize(13)
          .height(36)
          .borderRadius(18)
          .backgroundColor('#28FFFFFF')
          .fontColor(mpPrimaryText(this.isDark))
          .onClick(() => {
            this.rotY = this.isShowingBack() ? 0 : 180;
            this.rotX = 0;
          })
      }

      Text('左右滑动 360° 旋转检视金属浮雕与背面三遍凹雕')
        .fontSize(12)
        .fontColor(mpSecondaryText(this.isDark))
    }
    .alignItems(HorizontalAlign.Center)
  }
}

/** 仪表盘嵌入式 4 列真实社区勋章矩阵组件（与 iOS `NativeCommunityMedalsWidget` 1:1 视觉一致）。 */
@Component
export struct NativeCommunityMedalsWidget {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop githubLogin: string = 'MoviePilot';
  @Prop earnedCount: number = 0;
  @Prop totalCount: number = 7;
  @Prop medals: MpCommunityMedal[] = [];
  onSelectMedal: (medal: MpCommunityMedal) => void = () => {};

  build() {
    CinematicPanel({ panelPadding: 16 }) {
      Column({ space: 12 }) {
        Row() {
          Column({ space: 2 }) {
            Text('社区勋章')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(mpPrimaryText(this.isDark))
            Text(`@${this.githubLogin} · 已解锁 ${this.earnedCount}/${this.totalCount}`)
              .fontSize(11)
              .fontColor(mpSecondaryText(this.isDark))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          NativeAdaptiveBadge({ text: `${this.earnedCount}/${this.totalCount}`, tintHex: '#FFCC6B', filled: false })
        }
        .width('100%')

        Grid() {
          ForEach(this.medals, (medal: MpCommunityMedal) => {
            GridItem() {
              Column({ space: 4 }) {
                MedalRawfileImage({
                  assetName: medal.badgeAsset,
                  imgSize: 62,
                  imgOpacity: medal.earned ? 1.0 : 0.32,
                  shadowRadius: 10,
                  shadowOffsetY: 5,
                  shadowColor: '#45000000'
                })
                Text(medal.title)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(medal.earned ? mpPrimaryText(this.isDark) : mpSecondaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
              .alignItems(HorizontalAlign.Center)
              .onClick(() => this.onSelectMedal(medal))
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(10)
        .width('100%')
        .height(this.medals.length > 4 ? 176 : 88)
      }
    }
  }
}
