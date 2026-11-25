import { MpDanmakuFilterOptions } from '@moviepilot/core_rust_bridge';

/**
 * 鸿蒙端弹幕渲染偏好存储（基于 AppStorage/PersistentStorage，键义与默认值严格对齐 `danmaku-support-design.md` §4.1）。
 */
export class DanmakuPreferencesStore {
  static readonly KEY_ENABLED: string = 'mp_danmaku_enabled';
  static readonly KEY_OPACITY: string = 'mp_danmaku_opacity';
  static readonly KEY_FONT_SCALE: string = 'mp_danmaku_font_scale';
  static readonly KEY_SPEED: string = 'mp_danmaku_speed';
  static readonly KEY_AREA_RATIO: string = 'mp_danmaku_area_ratio';
  static readonly KEY_MAX_ON_SCREEN: string = 'mp_danmaku_max_on_screen';
  static readonly KEY_ALLOW_SCROLL: string = 'mp_danmaku_allow_scroll';
  static readonly KEY_ALLOW_TOP: string = 'mp_danmaku_allow_top';
  static readonly KEY_ALLOW_BOTTOM: string = 'mp_danmaku_allow_bottom';
  static readonly KEY_ALLOW_COLOR: string = 'mp_danmaku_allow_color';
  static readonly KEY_MERGE_DUPLICATES: string = 'mp_danmaku_merge_duplicates';
  static readonly KEY_BLOCK_KEYWORDS: string = 'mp_danmaku_block_keywords';

  private static initialized: boolean = false;

  static ensureInitialized(): void {
    if (DanmakuPreferencesStore.initialized) {
      return;
    }
    DanmakuPreferencesStore.initialized = true;
    try {
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_ENABLED, true);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_OPACITY, 0.85);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_FONT_SCALE, 1.0);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_SPEED, 1.0);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_AREA_RATIO, 0.5);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_MAX_ON_SCREEN, 40);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_ALLOW_SCROLL, true);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_ALLOW_TOP, true);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_ALLOW_BOTTOM, true);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_ALLOW_COLOR, true);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_MERGE_DUPLICATES, true);
      PersistentStorage.persistProp(DanmakuPreferencesStore.KEY_BLOCK_KEYWORDS, '[]');
    } catch {
      AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ENABLED, true);
      AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_OPACITY, 0.85);
      AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_FONT_SCALE, 1.0);
      AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_SPEED, 1.0);
      AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_AREA_RATIO, 0.5);
      AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_MAX_ON_SCREEN, 40);
      AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_SCROLL, true);
      AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_TOP, true);
      AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_BOTTOM, true);
      AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_COLOR, true);
      AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_MERGE_DUPLICATES, true);
      AppStorage.setOrCreate<string>(DanmakuPreferencesStore.KEY_BLOCK_KEYWORDS, '[]');
    }
  }

  static getEnabled(): boolean {
    DanmakuPreferencesStore.ensureInitialized();
    return AppStorage.get<boolean>(DanmakuPreferencesStore.KEY_ENABLED) ?? true;
  }

  static setEnabled(v: boolean): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ENABLED, v);
  }

  static getOpacity(): number {
    DanmakuPreferencesStore.ensureInitialized();
    const raw = AppStorage.get<number>(DanmakuPreferencesStore.KEY_OPACITY) ?? 0.85;
    return Math.min(1.0, Math.max(0.2, raw));
  }

  static setOpacity(v: number): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_OPACITY, Math.min(1.0, Math.max(0.2, v)));
  }

  static getFontScale(): number {
    DanmakuPreferencesStore.ensureInitialized();
    const raw = AppStorage.get<number>(DanmakuPreferencesStore.KEY_FONT_SCALE) ?? 1.0;
    return Math.min(1.5, Math.max(0.75, raw));
  }

  static setFontScale(v: number): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_FONT_SCALE, Math.min(1.5, Math.max(0.75, v)));
  }

  static getSpeed(): number {
    DanmakuPreferencesStore.ensureInitialized();
    const raw = AppStorage.get<number>(DanmakuPreferencesStore.KEY_SPEED) ?? 1.0;
    return Math.min(1.6, Math.max(0.6, raw));
  }

  static setSpeed(v: number): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_SPEED, Math.min(1.6, Math.max(0.6, v)));
  }

  static getAreaRatio(): number {
    DanmakuPreferencesStore.ensureInitialized();
    const raw = AppStorage.get<number>(DanmakuPreferencesStore.KEY_AREA_RATIO) ?? 0.5;
    return Math.min(1.0, Math.max(0.25, raw));
  }

  static setAreaRatio(v: number): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_AREA_RATIO, Math.min(1.0, Math.max(0.25, v)));
  }

  static getMaxOnScreen(): number {
    DanmakuPreferencesStore.ensureInitialized();
    const raw = AppStorage.get<number>(DanmakuPreferencesStore.KEY_MAX_ON_SCREEN) ?? 40;
    return Math.min(100, Math.max(20, Math.round(raw)));
  }

  static setMaxOnScreen(v: number): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<number>(DanmakuPreferencesStore.KEY_MAX_ON_SCREEN, Math.min(100, Math.max(20, Math.round(v))));
  }

  static getAllowScroll(): boolean {
    DanmakuPreferencesStore.ensureInitialized();
    return AppStorage.get<boolean>(DanmakuPreferencesStore.KEY_ALLOW_SCROLL) ?? true;
  }

  static setAllowScroll(v: boolean): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_SCROLL, v);
  }

  static getAllowTop(): boolean {
    DanmakuPreferencesStore.ensureInitialized();
    return AppStorage.get<boolean>(DanmakuPreferencesStore.KEY_ALLOW_TOP) ?? true;
  }

  static setAllowTop(v: boolean): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_TOP, v);
  }

  static getAllowBottom(): boolean {
    DanmakuPreferencesStore.ensureInitialized();
    return AppStorage.get<boolean>(DanmakuPreferencesStore.KEY_ALLOW_BOTTOM) ?? true;
  }

  static setAllowBottom(v: boolean): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_BOTTOM, v);
  }

  static getAllowColor(): boolean {
    DanmakuPreferencesStore.ensureInitialized();
    return AppStorage.get<boolean>(DanmakuPreferencesStore.KEY_ALLOW_COLOR) ?? true;
  }

  static setAllowColor(v: boolean): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_ALLOW_COLOR, v);
  }

  static getMergeDuplicates(): boolean {
    DanmakuPreferencesStore.ensureInitialized();
    return AppStorage.get<boolean>(DanmakuPreferencesStore.KEY_MERGE_DUPLICATES) ?? true;
  }

  static setMergeDuplicates(v: boolean): void {
    DanmakuPreferencesStore.ensureInitialized();
    AppStorage.setOrCreate<boolean>(DanmakuPreferencesStore.KEY_MERGE_DUPLICATES, v);
  }

  static getBlockKeywords(): string[] {
    DanmakuPreferencesStore.ensureInitialized();
    const raw = AppStorage.get<string>(DanmakuPreferencesStore.KEY_BLOCK_KEYWORDS) ?? '[]';
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) {
        const out: string[] = [];
        for (let i = 0; i < parsed.length; i++) {
          const s = String(parsed[i] ?? '').trim();
          if (s.length > 0) {
            out.push(s);
          }
        }
        return out;
      }
    } catch {
      // ignore
    }
    return [];
  }

  static addBlockKeyword(raw: string): string[] {
    const cleaned = raw.trim();
    const cur = DanmakuPreferencesStore.getBlockKeywords();
    if (!cleaned || cur.includes(cleaned)) {
      return cur;
    }
    const next = cur.concat([cleaned]);
    AppStorage.setOrCreate<string>(DanmakuPreferencesStore.KEY_BLOCK_KEYWORDS, JSON.stringify(next));
    return next;
  }

  static removeBlockKeyword(keyword: string): string[] {
    const cur = DanmakuPreferencesStore.getBlockKeywords();
    const next = cur.filter((k: string) => k !== keyword);
    AppStorage.setOrCreate<string>(DanmakuPreferencesStore.KEY_BLOCK_KEYWORDS, JSON.stringify(next));
    return next;
  }

  static toFilterOptions(offsetMs: number): MpDanmakuFilterOptions {
    return {
      allow_scroll: DanmakuPreferencesStore.getAllowScroll(),
      allow_top: DanmakuPreferencesStore.getAllowTop(),
      allow_bottom: DanmakuPreferencesStore.getAllowBottom(),
      allow_color: DanmakuPreferencesStore.getAllowColor(),
      merge_duplicates: DanmakuPreferencesStore.getMergeDuplicates(),
      merge_window_ms: 3000,
      max_per_second: 12,
      block_keywords: DanmakuPreferencesStore.getBlockKeywords(),
      offset_ms: Math.round(offsetMs)
    };
  }
}
