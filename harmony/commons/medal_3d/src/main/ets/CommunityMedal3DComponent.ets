import { curves } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { RustCoreBridge, MedalPalette, MpCommunityMedal } from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  NativeAdaptiveBadge,
  mpPrimaryText,
  mpSecondaryText,
  HarmonyAppearanceStore,
  HarmonyThemeColors
} from '@moviepilot/design_system';

interface MedalDialRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface MedalOutlineSpec {
  outline: number[][];
  dial: MedalDialRect;
}

const medalAssetCache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
const medalOutlineCache: Map<string, MedalOutlineSpec> = new Map<string, MedalOutlineSpec>();

const DEFAULT_DIAL_RECT: MedalDialRect = {
  x: 0.5,
  y: 0.465,
  width: 0.495,
  height: 0.235
};

/**
 * 从主包 `rawfile/community_medals/` 安全解码雕塑级勋章贴图：
 * 严禁对透明 WebP `Image` 直接附加矩形 `.shadow(...)`（避免在鸿蒙渲染管线下产生方形黑底框伪影），
 * 改为使用后置圆形径向柔光阴影垫片呈现自然悬浮立体感。
 */
@Component
struct MedalRawfileImage {
  @Prop @Watch('onAssetChanged') assetName: string = '';
  @Prop imgSize: number = 62;
  @Prop imgOpacity: number = 1.0;
  @Prop showSoftDropShadow: boolean = true;
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
    Stack({ alignContent: Alignment.Center }) {
      if (this.showSoftDropShadow) {
        Column()
          .width(Math.round(this.imgSize * 0.84))
          .height(Math.round(this.imgSize * 0.84))
          .borderRadius(Math.round(this.imgSize * 0.42))
          .translate({ y: Math.max(3, Math.round(this.imgSize * 0.045)) })
          .radialGradient({
            center: ['50%', '50%'],
            radius: Math.round(this.imgSize * 0.42),
            colors: [['#54000000', 0.0], ['#22000000', 0.62], ['#00000000', 1.0]]
          })
          .opacity(this.imgOpacity)
      }

      if (this.pm) {
        Image(this.pm)
          .width(this.imgSize)
          .height(this.imgSize)
          .objectFit(ImageFit.Contain)
          .opacity(this.imgOpacity)
          .backgroundColor(Color.Transparent)
      } else {
        Column()
          .width(Math.round(this.imgSize * 0.82))
          .height(Math.round(this.imgSize * 0.82))
          .borderRadius(Math.round(this.imgSize * 0.41))
          .backgroundColor('#16FFFFFF')
          .opacity(this.imgOpacity)
      }
    }
    .width(this.imgSize)
    .height(this.imgSize)
  }
}

/**
 * 鸿蒙原生 3D 社区勋章与真实背面金属三遍凹雕组件（1:1 对齐 iOS 物理交互与金属质感）：
 * - 解析 `community_medals/*.outline.json` 真实多边形轮廓与 `dial` 铭牌矩形；
 * - 多层金属侧边厚度挤压浮雕 + 随倾角动态扫过的镜面高光带，彻底消除方形暗框伪影；
 * - 背面叠加 5 段开口六边形 + 内部实心播放三角 MoviePilot 印记 + 三遍受光凹雕（亮边/暗槽/主刻）；
 * - 拖拽基于 `dragStartRotY/dragStartRotX` 精确跟手（`offsetX * 0.45`），松手弹簧回正 `rotX -> 0`，翻转按钮支持平滑 180° 弹簧动画。
 */
@Component
export struct CommunityMedal3DComponent {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @Prop @Watch('onMedalPropsChanged') medalId: string = 'code';
  @Prop @Watch('onMedalPropsChanged') frontAsset: string = 'code-front-t4.webp';
  @Prop @Watch('onMedalPropsChanged') backAsset: string = 'code-back.webp';
  @Prop @Watch('onMedalPropsChanged') title: string = '核心代码贡献';
  @Prop subtitle: string = 'Tier 4';
  @Prop @Watch('onMedalPropsChanged') ownerName: string = 'MoviePilot';
  @Prop @Watch('onMedalPropsChanged') earnedDate: string = '2026-11';
  @Prop @Watch('onMedalPropsChanged') medalSize: number = 240;
  @State @Watch('onPoseChanged') private rotY: number = 0;
  @State @Watch('onPoseChanged') private rotX: number = 0;
  @State private frontSpec: MedalOutlineSpec = { outline: [], dial: DEFAULT_DIAL_RECT };
  @State private backSpec: MedalOutlineSpec = { outline: [], dial: DEFAULT_DIAL_RECT };
  private dragStartRotY: number = 0;
  private dragStartRotX: number = 0;
  private rimCanvasReady: boolean = false;
  private backCanvasReady: boolean = false;
  private specCanvasReady: boolean = false;
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private rimCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private backCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private specCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);

  aboutToAppear(): void {
    this.loadOutlineSpecs();
  }

  onMedalPropsChanged(): void {
    this.loadOutlineSpecs();
    this.redrawAllCanvases();
  }

  onPoseChanged(): void {
    this.redrawRimAndSpecular();
    if (this.isShowingBack() && this.backCanvasReady) {
      this.drawEngravedOverlay();
    }
  }

  private palette(): MedalPalette {
    return RustCoreBridge.computeMedalPalette(this.medalId);
  }

  private outlineFileName(webpName: string): string {
    const trimmed = (webpName ?? '').trim();
    if (!trimmed) { return ''; }
    return trimmed.replace(/\.webp$/i, '.outline.json');
  }

  private async readOutlineJson(outlineFile: string): Promise<MedalOutlineSpec> {
    if (!outlineFile) {
      return { outline: [], dial: DEFAULT_DIAL_RECT };
    }
    const cached = medalOutlineCache.get(outlineFile);
    if (cached) {
      return cached;
    }
    try {
      const ctx = this.getUIContext().getHostContext();
      if (!ctx || !ctx.resourceManager) {
        return { outline: [], dial: DEFAULT_DIAL_RECT };
      }
      const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(`community_medals/${outlineFile}`);
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      const jsonText = decoder.decodeToString(bytes);
      const parsed = JSON.parse(jsonText) as Record<string, Object>;
      const pts: number[][] = [];
      if (Array.isArray(parsed['outline'])) {
        const rawPts = parsed['outline'] as Object[];
        for (let i = 0; i < rawPts.length; i++) {
          if (Array.isArray(rawPts[i])) {
            const pair = rawPts[i] as Object[];
            if (pair.length >= 2) {
              const px = Number(pair[0]);
              const py = Number(pair[1]);
              if (Number.isFinite(px) && Number.isFinite(py)) {
                pts.push([px, py]);
              }
            }
          }
        }
      }
      let dial: MedalDialRect = DEFAULT_DIAL_RECT;
      const rawDial = parsed['dial'];
      if (rawDial !== null && rawDial !== undefined && typeof rawDial === 'object' && !Array.isArray(rawDial)) {
        const dRec = rawDial as Record<string, Object>;
        const dx = Number(dRec['x']);
        const dy = Number(dRec['y']);
        const dw = Number(dRec['width']);
        const dh = Number(dRec['height']);
        if (Number.isFinite(dx) && Number.isFinite(dy) && Number.isFinite(dw) && Number.isFinite(dh) && dw > 0.1) {
          dial = { x: dx, y: dy, width: dw, height: dh };
        }
      }
      const spec: MedalOutlineSpec = { outline: pts, dial: dial };
      medalOutlineCache.set(outlineFile, spec);
      return spec;
    } catch {
      return { outline: [], dial: DEFAULT_DIAL_RECT };
    }
  }

  private loadOutlineSpecs(): void {
    const fName = this.outlineFileName(this.frontAsset);
    const bName = this.outlineFileName(this.backAsset);
    Promise.all([
      this.readOutlineJson(fName),
      this.readOutlineJson(bName)
    ]).then((res: MedalOutlineSpec[]) => {
      this.frontSpec = res[0];
      this.backSpec = res[1];
      this.redrawAllCanvases();
    }).catch(() => {});
  }

  private redrawAllCanvases(): void {
    this.redrawRimAndSpecular();
    if (this.backCanvasReady) {
      this.drawEngravedOverlay();
    }
  }

  private redrawRimAndSpecular(): void {
    if (this.rimCanvasReady) {
      this.drawMetallicRimRelief();
    }
    if (this.specCanvasReady) {
      this.drawSpecularSweep();
    }
  }

  private traceOutlinePath(
    ctx: CanvasRenderingContext2D,
    pts: number[][],
    size: number,
    insetPx: number,
    dx: number,
    dy: number
  ): void {
    const drawSize = size - insetPx * 2;
    ctx.beginPath();
    if (pts.length >= 6) {
      for (let i = 0; i < pts.length; i++) {
        const px = insetPx + pts[i][0] * drawSize + dx;
        const py = insetPx + pts[i][1] * drawSize + dy;
        if (i === 0) {
          ctx.moveTo(px, py);
        } else {
          ctx.lineTo(px, py);
        }
      }
      ctx.closePath();
    } else {
      ctx.arc(size / 2 + dx, size / 2 + dy, drawSize * 0.44, 0, Math.PI * 2);
    }
  }

  private resolvedMedalSize(): number {
    return Math.max(120, this.medalSize > 0 ? this.medalSize : 240);
  }

  /** 绘制多层金属侧边浮雕厚度（沿真实 `outline.json` 花瓣/齿轮轮廓挤压）。 */
  private drawMetallicRimRelief(): void {
    const ctx = this.rimCanvasCtx;
    const canvasSize = this.resolvedMedalSize();
    const w = 240;
    ctx.clearRect(0, 0, canvasSize, canvasSize);
    ctx.save();
    const s = canvasSize / w;
    ctx.scale(s, s);
    const p = this.palette();
    const activeOutline = this.isShowingBack() ? this.backSpec.outline : this.frontSpec.outline;
    const radY = (this.rotY * Math.PI) / 180;
    const radX = (this.rotX * Math.PI) / 180;
    const sinY = Math.sin(radY);
    const sinX = Math.sin(radX);
    // 背面翻转时局部坐标系已做水平镜像，侧边法向同步翻转
    const signX = this.isShowingBack() ? 1 : -1;
    const maxExtrudeX = signX * sinY * 8.5;
    const maxExtrudeY = sinX * 4.0;

    const layers = 6;
    for (let layer = layers; layer >= 1; layer--) {
      const t = layer / layers;
      const dx = maxExtrudeX * t;
      const dy = maxExtrudeY * t;
      ctx.save();
      const grad = ctx.createLinearGradient(20, 16, w - 20, w - 16);
      grad.addColorStop(0.0, p.engrave_dark_hex);
      grad.addColorStop(0.45, p.rim_hex);
      grad.addColorStop(0.75, p.base_hex);
      grad.addColorStop(1.0, p.engrave_dark_hex);
      ctx.fillStyle = grad;
      ctx.globalAlpha = 0.55 + (1 - t) * 0.35;
      this.traceOutlinePath(ctx, activeOutline, w, 2, dx, dy);
      ctx.fill();
      ctx.strokeStyle = layer === 1 ? p.engrave_light_hex : p.engrave_dark_hex;
      ctx.lineWidth = layer === 1 ? 1.1 : 0.7;
      ctx.globalAlpha = layer === 1 ? 0.55 : 0.35;
      ctx.stroke();
      ctx.restore();
    }
    ctx.restore();
  }

  /** 对标 Web communityMedalRelief.ts：正对静止时零泛白反光，仅在拖动倾斜时浮现极淡的金属柔光。 */
  private drawSpecularSweep(): void {
    const ctx = this.specCanvasCtx;
    const canvasSize = this.resolvedMedalSize();
    const w = 240;
    ctx.clearRect(0, 0, canvasSize, canvasSize);

    const normY = ((this.rotY % 180) + 180) % 180;
    const distFromFaceDeg = Math.min(normY, 180 - normY);
    const tiltMag = Math.min(1, (distFromFaceDeg + Math.abs(this.rotX) * 1.2) / 36);
    if (tiltMag < 0.05) {
      return;
    }

    const p = this.palette();
    const activeOutline = this.isShowingBack() ? this.backSpec.outline : this.frontSpec.outline;
    const radY = (this.rotY * Math.PI) / 180;
    const sweepRatio = 0.5 + Math.sin(radY * 1.35) * 0.42 - (this.rotX / 68);
    const clampedCenter = Math.max(0.10, Math.min(0.90, sweepRatio));

    ctx.save();
    const s = canvasSize / w;
    ctx.scale(s, s);
    this.traceOutlinePath(ctx, activeOutline, w, 3, 0, 0);
    ctx.clip();

    const grad = ctx.createLinearGradient(0, 0, w, w * 0.88);
    const s0 = Math.max(0, clampedCenter - 0.20);
    const s1 = Math.max(0, clampedCenter - 0.05);
    const s2 = Math.min(1, clampedCenter + 0.05);
    const s3 = Math.min(1, clampedCenter + 0.20);
    grad.addColorStop(0, 'rgba(255,255,255,0)');
    grad.addColorStop(s0, 'rgba(255,255,255,0)');
    grad.addColorStop(s1, p.engrave_light_hex);
    grad.addColorStop(clampedCenter, p.engrave_light_hex);
    grad.addColorStop(s2, p.engrave_light_hex);
    grad.addColorStop(s3, 'rgba(255,255,255,0)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');

    ctx.globalAlpha = tiltMag * 0.13;
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, w);
    ctx.restore();
  }

  /** 绘制真实三遍金属凹雕铭牌（对齐 `*-back.outline.json` `dial` 区域 + 5 段开口六边形与内部播放三角）。 */
  private drawEngravedOverlay(): void {
    const p = this.palette();
    const ctx = this.backCanvasCtx;
    const canvasSize = this.resolvedMedalSize();
    const w = 240;
    ctx.clearRect(0, 0, canvasSize, canvasSize);
    ctx.save();
    const s = canvasSize / w;
    ctx.scale(s, s);

    const dial = this.backSpec.dial ?? DEFAULT_DIAL_RECT;
    const cx = dial.x * w;
    const dialCenterY = dial.y * w;
    const dialW = Math.max(96, dial.width * w);
    const dialH = Math.max(52, dial.height * w);

    // 5 段开口六边形 + 内部 MoviePilot 播放三角三遍凹雕印记
    const drawMakerMarkPass = (ox: number, oy: number, color: string, alpha: number) => {
      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = 2.1;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      const r = 10.5;
      const my = dialCenterY - dialH * 0.62 + oy;
      const mx = cx + ox;

      // 5 段开口正六边形（保留右上第 6 段开口）
      ctx.beginPath();
      for (let i = 0; i < 6; i++) {
        const a = (Math.PI / 3) * i - Math.PI / 6;
        const px = mx + Math.cos(a) * r;
        const py = my + Math.sin(a) * r;
        if (i === 0) {
          ctx.moveTo(px, py);
        } else {
          ctx.lineTo(px, py);
        }
      }
      ctx.stroke();

      // 内部 MoviePilot 实心播放三角
      ctx.beginPath();
      ctx.moveTo(mx - r * 0.28, my - r * 0.38);
      ctx.lineTo(mx + r * 0.44, my);
      ctx.lineTo(mx - r * 0.28, my + r * 0.38);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    };

    // Pass 1: 底部受光亮边 -> Pass 2: 顶部凹槽暗影 -> Pass 3: 主刻印
    drawMakerMarkPass(0.9, 1.1, p.engrave_light_hex, 0.78);
    drawMakerMarkPass(-0.8, -0.9, p.engrave_dark_hex, 0.90);
    drawMakerMarkPass(0, 0, p.engrave_dark_hex, 0.84);

    const drawCarved = (text: string, y: number, size: number, maxWidth: number) => {
      const clean = (text ?? '').trim();
      if (!clean) { return; }
      ctx.save();
      ctx.font = `bold ${size}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      // Pass 1: 底部高光受光边
      ctx.fillStyle = p.engrave_light_hex;
      ctx.globalAlpha = 0.82;
      ctx.fillText(clean, cx + 1.0, y + 1.2, maxWidth);
      // Pass 2: 顶部深色凹槽阴影
      ctx.fillStyle = p.engrave_dark_hex;
      ctx.globalAlpha = 0.92;
      ctx.fillText(clean, cx - 0.9, y - 1.0, maxWidth);
      // Pass 3: 主凹雕文字
      ctx.fillStyle = p.engrave_dark_hex;
      ctx.globalAlpha = 0.84;
      ctx.fillText(clean, cx, y, maxWidth);
      ctx.restore();
    };

    const textMaxW = dialW * 0.92;
    drawCarved('MOVIEPILOT', dialCenterY - dialH * 0.28, 9.5, textMaxW);
    drawCarved(this.title, dialCenterY - dialH * 0.02, 13.5, textMaxW);
    drawCarved(`@${this.ownerName}`, dialCenterY + dialH * 0.24, 11.0, textMaxW);
    drawCarved(this.earnedDate, dialCenterY + dialH * 0.46, 9.5, textMaxW);
    ctx.restore();
  }

  private isShowingBack(): boolean {
    const norm = ((this.rotY % 360) + 360) % 360;
    return norm >= 90 && norm <= 270;
  }

  private flipSmoothly(): void {
    const baseTurn = Math.round(this.rotY / 360) * 360;
    const targetRotY = this.isShowingBack() ? baseTurn : baseTurn + 180;
    this.getUIContext().animateTo({ curve: curves.springMotion(0.50, 0.84) }, () => {
      this.rotY = targetRotY;
      this.rotX = 0;
    });
  }

  build() {
    Column({ space: this.resolvedMedalSize() < 200 ? 8 : 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        // 圆形金属柔和光晕底座（绝无方形硬边）
        Column()
          .width(this.resolvedMedalSize() + 8)
          .height(this.resolvedMedalSize() + 8)
          .borderRadius(Math.round((this.resolvedMedalSize() + 8) / 2))
          .radialGradient({
            center: ['50%', '50%'],
            radius: Math.round((this.resolvedMedalSize() + 8) / 2),
            colors: [[`${this.palette().rim_hex}`, 0.0], ['#00000000', 1.0]]
          })
          .opacity(this.isDark ? 0.14 : 0.09)

        // 3D 透视旋转勋章主体
        Stack({ alignContent: Alignment.Center }) {
          if (!this.isShowingBack()) {
            Stack({ alignContent: Alignment.Center }) {
              Canvas(this.rimCanvasCtx)
                .width(this.resolvedMedalSize())
                .height(this.resolvedMedalSize())
                .hitTestBehavior(HitTestMode.None)
                .onReady(() => {
                  this.rimCanvasReady = true;
                  this.drawMetallicRimRelief();
                })

              MedalRawfileImage({
                assetName: this.frontAsset,
                imgSize: Math.max(116, Math.round(this.resolvedMedalSize() * (236 / 240))),
                imgOpacity: 1.0,
                showSoftDropShadow: true
              })

              Canvas(this.specCanvasCtx)
                .width(this.resolvedMedalSize())
                .height(this.resolvedMedalSize())
                .hitTestBehavior(HitTestMode.None)
                .onReady(() => {
                  this.specCanvasReady = true;
                  this.drawSpecularSweep();
                })
            }
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Canvas(this.rimCanvasCtx)
                .width(this.resolvedMedalSize())
                .height(this.resolvedMedalSize())
                .hitTestBehavior(HitTestMode.None)
                .onReady(() => {
                  this.rimCanvasReady = true;
                  this.drawMetallicRimRelief();
                })

              MedalRawfileImage({
                assetName: this.backAsset,
                imgSize: Math.max(116, Math.round(this.resolvedMedalSize() * (236 / 240))),
                imgOpacity: 1.0,
                showSoftDropShadow: true
              })

              Canvas(this.backCanvasCtx)
                .width(this.resolvedMedalSize())
                .height(this.resolvedMedalSize())
                .hitTestBehavior(HitTestMode.None)
                .onReady(() => {
                  this.backCanvasReady = true;
                  this.drawEngravedOverlay();
                })

              Canvas(this.specCanvasCtx)
                .width(this.resolvedMedalSize())
                .height(this.resolvedMedalSize())
                .hitTestBehavior(HitTestMode.None)
                .onReady(() => {
                  this.specCanvasReady = true;
                  this.drawSpecularSweep();
                })
            }
            .scale({ x: -1, y: 1 })
          }
        }
        .width(this.resolvedMedalSize() + 4)
        .height(this.resolvedMedalSize() + 4)
        .rotate({ x: 0, y: 1, z: 0, angle: this.rotY, perspective: 12 })
        .rotate({ x: 1, y: 0, z: 0, angle: this.rotX, perspective: 12 })
        .gesture(
          PanGesture({ distance: 2 })
            .onActionStart(() => {
              this.dragStartRotY = this.rotY;
              this.dragStartRotX = this.rotX;
            })
            .onActionUpdate((ev: GestureEvent) => {
              this.rotY = this.dragStartRotY + ev.offsetX * 0.45;
              this.rotX = Math.max(-24, Math.min(24, this.dragStartRotX - ev.offsetY * 0.18));
            })
            .onActionEnd(() => {
              this.getUIContext().animateTo({ curve: curves.springMotion(0.45, 0.82) }, () => {
                this.rotX = 0;
              });
            })
        )
      }
      .width(this.resolvedMedalSize() + 16)
      .height(this.resolvedMedalSize() + 16)

      Row({ space: 10 }) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(this.resolvedMedalSize() < 200 ? 13 : 14)
              .fontColor([mpPrimaryText(this.isDark)])
            Text(this.isShowingBack() ? '翻转至正面' : '翻转查看背面雕刻')
              .fontSize(this.resolvedMedalSize() < 200 ? 12 : 13)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpPrimaryText(this.isDark))
          }
          .padding({
            left: this.resolvedMedalSize() < 200 ? 12 : 16,
            right: this.resolvedMedalSize() < 200 ? 12 : 16
          })
        }
        .height(this.resolvedMedalSize() < 200 ? 32 : 36)
        .borderRadius(this.resolvedMedalSize() < 200 ? 16 : 18)
        .backgroundColor(HarmonyThemeColors.chipFill(this.isDark))
        .border({ width: 0.6, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: this.resolvedMedalSize() < 200 ? 16 : 18 })
        .onClick(() => this.flipSmoothly())
      }

      Text(this.resolvedMedalSize() < 200 ? '左右滑动 360° 旋转检视' : '左右滑动 360° 旋转检视金属浮雕与背面三遍凹雕')
        .fontSize(this.resolvedMedalSize() < 200 ? 11 : 12)
        .fontColor(mpSecondaryText(this.isDark))
        .textAlign(TextAlign.Center)
    }
    .alignItems(HorizontalAlign.Center)
  }
}

/** 仪表盘嵌入式自适应列社区勋章矩阵组件（与 iOS `NativeCommunityMedalsWidget` 视觉一致）。 */
@Component
export struct NativeCommunityMedalsWidget {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) windowWidthVp: number = 412;
  @Prop githubLogin: string = 'MoviePilot';
  @Prop earnedCount: number = 0;
  @Prop totalCount: number = 7;
  @Prop wornMedalId: string = '';
  @Prop medals: MpCommunityMedal[] = [];
  onSelectMedal: (medal: MpCommunityMedal) => void = () => {};

  private columnsTemplate(): string {
    if (this.windowWidthVp >= 760) {
      const cols = this.medals.length >= 7 ? 7 : 6;
      const parts: string[] = [];
      for (let i = 0; i < cols; i++) { parts.push('1fr'); }
      return parts.join(' ');
    }
    if (this.windowWidthVp >= 580) {
      return '1fr 1fr 1fr 1fr 1fr';
    }
    return '1fr 1fr 1fr 1fr';
  }

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
                Stack({ alignContent: Alignment.Bottom }) {
                  MedalRawfileImage({
                    assetName: medal.badgeAsset,
                    imgSize: 62,
                    imgOpacity: medal.earned ? 1.0 : 0.32,
                    showSoftDropShadow: medal.earned
                  })
                  if (medal.worn || (this.wornMedalId.length > 0 && this.wornMedalId === medal.id)) {
                    Text('佩戴中')
                      .fontSize(8.5)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .padding({ left: 5, right: 5, top: 1.5, bottom: 1.5 })
                      .borderRadius(7)
                      .backgroundColor(this.accentHex)
                  }
                }
                Text(medal.title)
                  .fontSize(10.5)
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
          }, (medal: MpCommunityMedal) => `${medal.id}_${medal.tier}_${medal.earned}_${medal.worn}`)
        }
        .columnsTemplate(this.columnsTemplate())
        .columnsGap(8)
        .rowsGap(10)
        .width('100%')
      }
    }
  }
}
