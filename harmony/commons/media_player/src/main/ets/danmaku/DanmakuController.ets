import { MpDanmakuItem } from '@moviepilot/core_rust_bridge';

/** 屏幕上正在渲染的单条活跃弹幕状态（按 vp 逻辑坐标计算）。 */
export interface ActiveHarmonyDanmaku {
  id: number;
  item: MpDanmakuItem;
  displayText: string;
  track: number;
  x: number;
  y: number;
  width: number;
  speedVpPerSec: number;
  remainingSec: number;
}

/**
 * 鸿蒙端无碰撞弹幕轨道调度引擎（与 iOS/Android 共享同一套 §5.1 追尾判定公式）：
 * - 按 `time_ms` 升序二分定位，Seek 时立即清空屏幕并重定位游标；
 * - 滚动轨依据“右边界安全间距 + 尾端追赶时间差”严格防止重叠；
 * - 顶/底固定轨按轨道剩余驻留时间独立分配并在溢出时礼貌丢弃。
 */
export class HarmonyDanmakuController {
  items: MpDanmakuItem[] = [];
  activeItems: ActiveHarmonyDanmaku[] = [];

  viewportWidth: number = 0;
  viewportHeight: number = 0;
  topSafeMargin: number = 14;

  opacity: number = 0.85;
  fontScale: number = 1.0;
  userSpeed: number = 1.0;
  areaRatio: number = 0.5;
  maxOnScreen: number = 40;

  private cursor: number = 0;
  private playbackClockMs: number = 0;
  private playbackRate: number = 1.0;
  private isPlaying: boolean = false;
  private nextActiveId: number = 1;

  private scrollTracks: (ActiveHarmonyDanmaku | null)[] = [];
  private topTracks: number[] = [];
  private bottomTracks: number[] = [];

  get effectiveFontSizeVp(): number {
    return 17.5 * this.fontScale;
  }

  get effectiveLineHeightVp(): number {
    return this.effectiveFontSizeVp * 1.38;
  }

  updateViewport(widthVp: number, heightVp: number, topInsetVp: number = 14): void {
    const resized = Math.abs(this.viewportWidth - widthVp) > 1 || Math.abs(this.viewportHeight - heightVp) > 1;
    this.viewportWidth = Math.max(0, widthVp);
    this.viewportHeight = Math.max(0, heightVp);
    this.topSafeMargin = Math.max(12, topInsetVp);
    if (resized) {
      this.activeItems = [];
      this.resetTracks();
      this.cursor = this.lowerBound(this.playbackClockMs);
    }
  }

  load(newItems: MpDanmakuItem[], currentPositionMs: number): void {
    this.items = newItems.slice().sort((a: MpDanmakuItem, b: MpDanmakuItem) => a.time_ms - b.time_ms);
    this.activeItems = [];
    this.resetTracks();
    this.playbackClockMs = Math.max(0, currentPositionMs);
    this.cursor = this.lowerBound(this.playbackClockMs);
  }

  clearAll(): void {
    this.items = [];
    this.activeItems = [];
    this.resetTracks();
    this.cursor = 0;
  }

  syncPlayerClock(positionMs: number, playing: boolean, rate: number): void {
    const safePos = Math.max(0, positionMs);
    const delta = Math.abs(safePos - this.playbackClockMs);
    this.isPlaying = playing;
    this.playbackRate = Math.min(3.0, Math.max(0.25, rate));
    if (delta > 650) {
      this.playbackClockMs = safePos;
      this.activeItems = [];
      this.resetTracks();
      this.cursor = this.lowerBound(safePos);
    } else if (delta > 120) {
      this.playbackClockMs = safePos;
    }
  }

  step(dtSec: number, measureWidth: (text: string, fontSizeVp: number) => number): void {
    if (!this.isPlaying || this.viewportWidth <= 10 || this.viewportHeight <= 10) {
      return;
    }
    const clampedDt = Math.min(0.1, Math.max(0, dtSec));
    if (clampedDt <= 0) {
      return;
    }

    this.playbackClockMs += clampedDt * 1000.0 * this.playbackRate;
    const effectiveDt = clampedDt * this.playbackRate;

    // 1. 推进活跃弹幕并淘汰离场条目
    let writeIdx = 0;
    for (let i = 0; i < this.activeItems.length; i++) {
      const slot = this.activeItems[i];
      if (slot.item.mode === 'scroll') {
        slot.x -= slot.speedVpPerSec * effectiveDt;
        if (slot.x + slot.width >= -12) {
          this.activeItems[writeIdx++] = slot;
        } else if (slot.track >= 0 && slot.track < this.scrollTracks.length && this.scrollTracks[slot.track]?.id === slot.id) {
          this.scrollTracks[slot.track] = null;
        }
      } else {
        slot.remainingSec -= effectiveDt;
        if (slot.remainingSec > 0) {
          this.activeItems[writeIdx++] = slot;
        }
      }
    }
    this.activeItems.length = writeIdx;

    for (let i = 0; i < this.topTracks.length; i++) {
      this.topTracks[i] = Math.max(0, this.topTracks[i] - effectiveDt);
    }
    for (let i = 0; i < this.bottomTracks.length; i++) {
      this.bottomTracks[i] = Math.max(0, this.bottomTracks[i] - effectiveDt);
    }

    // 2. 发射当前时间窗口内到点的新弹幕
    this.ensureTrackCapacity();
    const minWindowMs = this.playbackClockMs - 300;
    const maxWindowMs = this.playbackClockMs + 60;

    while (this.cursor < this.items.length) {
      const item = this.items[this.cursor];
      if (item.time_ms < minWindowMs) {
        this.cursor++;
        continue;
      }
      if (item.time_ms > maxWindowMs) {
        break;
      }
      this.cursor++;
      if (this.activeItems.length >= this.maxOnScreen) {
        continue;
      }
      this.trySpawn(item, measureWidth);
    }
  }

  private trySpawn(item: MpDanmakuItem, measureWidth: (text: string, fontSizeVp: number) => number): void {
    const displayText = item.repeat_count > 1 ? `${item.text} ×${item.repeat_count}` : item.text;
    const width = Math.max(20, measureWidth(displayText, this.effectiveFontSizeVp));
    const lineH = this.effectiveLineHeightVp;

    if (item.mode === 'scroll') {
      const baseDuration = 7.5 / Math.min(1.6, Math.max(0.6, this.userSpeed));
      const newSpeed = (this.viewportWidth + width) / Math.max(2.0, baseDuration);
      const safeGap = 24;
      const track = this.findAvailableScrollTrack(newSpeed, safeGap);
      if (track < 0) {
        return;
      }
      const slot: ActiveHarmonyDanmaku = {
        id: this.nextActiveId++,
        item: item,
        displayText: displayText,
        track: track,
        x: this.viewportWidth + 6,
        y: this.topSafeMargin + track * lineH,
        width: width,
        speedVpPerSec: newSpeed,
        remainingSec: baseDuration
      };
      this.scrollTracks[track] = slot;
      this.activeItems.push(slot);
      return;
    }

    if (item.mode === 'top') {
      let track = -1;
      for (let i = 0; i < this.topTracks.length; i++) {
        if (this.topTracks[i] <= 0) {
          track = i;
          break;
        }
      }
      if (track < 0) {
        return;
      }
      const duration = 4.0;
      this.topTracks[track] = duration;
      this.activeItems.push({
        id: this.nextActiveId++,
        item: item,
        displayText: displayText,
        track: track,
        x: Math.max(8, (this.viewportWidth - width) * 0.5),
        y: this.topSafeMargin + track * lineH,
        width: width,
        speedVpPerSec: 0,
        remainingSec: duration
      });
      return;
    }

    let track = -1;
    for (let i = 0; i < this.bottomTracks.length; i++) {
      if (this.bottomTracks[i] <= 0) {
        track = i;
        break;
      }
    }
    if (track < 0) {
      return;
    }
    const duration = 4.0;
    this.bottomTracks[track] = duration;
    const bottomAnchor = Math.max(this.topSafeMargin + lineH, this.viewportHeight - 54 - (track + 1) * lineH);
    this.activeItems.push({
      id: this.nextActiveId++,
      item: item,
      displayText: displayText,
      track: track,
      x: Math.max(8, (this.viewportWidth - width) * 0.5),
      y: bottomAnchor,
      width: width,
      speedVpPerSec: 0,
      remainingSec: duration
    });
  }

  private findAvailableScrollTrack(newSpeed: number, safeGap: number): number {
    for (let i = 0; i < this.scrollTracks.length; i++) {
      const prev = this.scrollTracks[i];
      if (!prev) {
        return i;
      }
      const prevRight = prev.x + prev.width;
      if (prevRight + safeGap > this.viewportWidth) {
        continue;
      }
      const timeForPrevToExit = Math.max(0, prevRight) / Math.max(1, prev.speedVpPerSec);
      const timeForNewToCross = this.viewportWidth / Math.max(1, newSpeed);
      if (timeForNewToCross >= timeForPrevToExit) {
        return i;
      }
    }
    return -1;
  }

  private ensureTrackCapacity(): void {
    const lineH = Math.max(18, this.effectiveLineHeightVp);
    const usableHeight = Math.max(lineH, (this.viewportHeight - this.topSafeMargin - 20) * Math.min(1.0, Math.max(0.25, this.areaRatio)));
    const scrollCount = Math.min(24, Math.max(1, Math.floor(usableHeight / lineH)));
    if (this.scrollTracks.length !== scrollCount) {
      const next: (ActiveHarmonyDanmaku | null)[] = [];
      for (let i = 0; i < scrollCount; i++) {
        next.push(i < this.scrollTracks.length ? this.scrollTracks[i] : null);
      }
      this.scrollTracks = next;
    }
    const fixedCount = Math.min(6, Math.max(1, Math.floor(scrollCount / 2)));
    if (this.topTracks.length !== fixedCount) {
      const nextTop: number[] = [];
      const nextBot: number[] = [];
      for (let i = 0; i < fixedCount; i++) {
        nextTop.push(i < this.topTracks.length ? this.topTracks[i] : 0);
        nextBot.push(i < this.bottomTracks.length ? this.bottomTracks[i] : 0);
      }
      this.topTracks = nextTop;
      this.bottomTracks = nextBot;
    }
  }

  private resetTracks(): void {
    for (let i = 0; i < this.scrollTracks.length; i++) {
      this.scrollTracks[i] = null;
    }
    for (let i = 0; i < this.topTracks.length; i++) {
      this.topTracks[i] = 0;
    }
    for (let i = 0; i < this.bottomTracks.length; i++) {
      this.bottomTracks[i] = 0;
    }
  }

  private lowerBound(targetMs: number): number {
    let lo = 0;
    let hi = this.items.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.items[mid].time_ms < targetMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
