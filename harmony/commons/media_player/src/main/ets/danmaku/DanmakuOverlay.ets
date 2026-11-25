import { displaySync } from '@kit.ArkGraphics2D';
import { HarmonyDanmakuController } from './DanmakuController';
import { DanmakuPreferencesStore } from './DanmakuPreferences';

/**
 * 鸿蒙原生透明弹幕 Canvas 渲染层：
 * - 位于视频 `XComponent` 之上、手势与控制栏之下，严格设置 `.hitTestBehavior(HitTestMode.None)` 不阻断手势；
 * - 由 `@kit.ArkGraphics2D` `displaySync` 帧同步驱动（降级兜底 16ms 定时），结合固定容量文字宽缓存与双通道描边/填充，流畅无掉帧。
 */
@Component
export struct HarmonyDanmakuOverlay {
  controller: HarmonyDanmakuController = new HarmonyDanmakuController();
  @Prop danmakuActive: boolean = true;
  @Prop isPlaying: boolean = false;
  @Prop pipActive: boolean = false;
  @Prop safeTopVp: number = 14;
  @Prop @Watch('onConfigChanged') configVersion: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;
  private widthCache: Map<string, number> = new Map<string, number>();
  private syncEngine: displaySync.DisplaySync | null = null;
  private fallbackTimer: number = -1;
  private lastFrameMs: number = 0;
  private canvasWidthVp: number = 0;
  private canvasHeightVp: number = 0;

  aboutToAppear(): void {
    this.syncPreferences();
    this.startLoop();
  }

  aboutToDisappear(): void {
    this.stopLoop();
  }

  private onConfigChanged(): void {
    this.syncPreferences();
    if (!this.danmakuActive || this.pipActive) {
      this.clearCanvas();
    } else {
      this.drawFrame();
    }
  }

  private syncPreferences(): void {
    const prevScale = this.controller.fontScale;
    this.controller.opacity = DanmakuPreferencesStore.getOpacity();
    this.controller.fontScale = DanmakuPreferencesStore.getFontScale();
    this.controller.userSpeed = DanmakuPreferencesStore.getSpeed();
    this.controller.areaRatio = DanmakuPreferencesStore.getAreaRatio();
    this.controller.maxOnScreen = DanmakuPreferencesStore.getMaxOnScreen();
    if (Math.abs(prevScale - this.controller.fontScale) > 0.001) {
      this.widthCache.clear();
    }
  }

  private startLoop(): void {
    this.stopLoop();
    this.lastFrameMs = Date.now();
    try {
      const ds = displaySync.create();
      ds.setExpectedFrameRateRange({ expected: 60, min: 30, max: 120 });
      ds.on('frame', (info: displaySync.IntervalInfo) => {
        const nowMs = info.timestamp > 0 ? (info.timestamp / 1_000_000) : Date.now();
        this.onTick(nowMs);
      });
      ds.start();
      this.syncEngine = ds;
    } catch {
      this.fallbackTimer = setInterval(() => {
        this.onTick(Date.now());
      }, 16);
    }
  }

  private stopLoop(): void {
    if (this.syncEngine) {
      try {
        this.syncEngine.stop();
      } catch {
        // ignore
      }
      this.syncEngine = null;
    }
    if (this.fallbackTimer !== -1) {
      clearInterval(this.fallbackTimer);
      this.fallbackTimer = -1;
    }
  }

  private onTick(nowMs: number): void {
    if (!this.canvasReady) {
      this.lastFrameMs = nowMs;
      return;
    }
    const dtSec = this.lastFrameMs > 0 ? Math.min(0.1, Math.max(0, (nowMs - this.lastFrameMs) / 1000)) : (1 / 60);
    this.lastFrameMs = nowMs;

    if (!this.danmakuActive || this.pipActive) {
      if (this.controller.activeItems.length > 0) {
        this.controller.activeItems = [];
        this.clearCanvas();
      }
      return;
    }
    if (this.isPlaying && this.controller.items.length > 0) {
      this.controller.step(dtSec, (text: string, fontSizeVp: number): number => this.measureCached(text, fontSizeVp));
      this.drawFrame();
    }
  }

  private measureCached(text: string, fontSizeVp: number): number {
    const key = `${Math.round(fontSizeVp)}|${text}`;
    const cached = this.widthCache.get(key);
    if (cached !== undefined) {
      return cached;
    }
    this.ctx.font = `bold ${Math.round(fontSizeVp)}vp sans-serif`;
    const measured = this.ctx.measureText(text).width;
    if (this.widthCache.size >= 512) {
      this.widthCache.clear();
    }
    this.widthCache.set(key, measured);
    return measured;
  }

  private clearCanvas(): void {
    if (!this.canvasReady || this.canvasWidthVp <= 0 || this.canvasHeightVp <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
  }

  private drawFrame(): void {
    if (!this.canvasReady || this.canvasWidthVp <= 0 || this.canvasHeightVp <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, this.canvasWidthVp, this.canvasHeightVp);
    if (!this.danmakuActive || this.pipActive) {
      return;
    }
    const active = this.controller.activeItems;
    if (active.length === 0) {
      return;
    }

    const fontSize = Math.round(this.controller.effectiveFontSizeVp);
    const alpha = Math.min(1.0, Math.max(0.2, this.controller.opacity));
    this.ctx.font = `bold ${fontSize}vp sans-serif`;
    this.ctx.textBaseline = 'top';
    this.ctx.lineJoin = 'round';
    this.ctx.lineWidth = 2.6;
    this.ctx.globalAlpha = alpha;
    this.ctx.strokeStyle = 'rgba(0, 0, 0, 0.85)';

    for (let i = 0; i < active.length; i++) {
      const slot = active[i];
      const rgb = slot.item.color_rgb & 0xFFFFFF;
      const hex = `#${rgb.toString(16).padStart(6, '0')}`;
      this.ctx.strokeText(slot.displayText, slot.x, slot.y);
      this.ctx.fillStyle = hex;
      this.ctx.fillText(slot.displayText, slot.x, slot.y);
    }
    this.ctx.globalAlpha = 1.0;
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => {
        this.canvasReady = true;
        this.canvasWidthVp = this.ctx.width;
        this.canvasHeightVp = this.ctx.height;
        this.controller.updateViewport(this.canvasWidthVp, this.canvasHeightVp, Math.max(12, this.safeTopVp));
        this.drawFrame();
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && h > 0) {
          this.canvasWidthVp = w;
          this.canvasHeightVp = h;
          this.controller.updateViewport(w, h, Math.max(12, this.safeTopVp));
          this.widthCache.clear();
        }
      })
  }
}
