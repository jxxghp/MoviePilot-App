import { display } from '@kit.ArkUI';
import { GeneratedDesignTokens } from '../tokens/GeneratedTokens';

/** 鸿蒙「一次开发、多端部署」一多断点枚举。 */
export type HarmonyBreakpoint = 'sm' | 'md' | 'lg';

/** 兼容 ArkUI `SheetOptions.detents` 元组签名的弹层档位类型。 */
export type HarmonySheetDetents = [(SheetSize | Length), (SheetSize | Length)?, (SheetSize | Length)?];

/**
 * 鸿蒙响应式多形态布局中心（对齐 `shared/design-tokens/layout.json`）：
 * 自动结合窗口宽高 vp 与 `display.getFoldStatus()` 驱动手机、横屏、阔折叠屏、平板多栏与网格列数。
 */
export class HarmonyAdaptiveLayout {
  static resolveBreakpoint(widthVp: number): HarmonyBreakpoint {
    if (widthVp >= GeneratedDesignTokens.BREAKPOINT_TABLET_SPLIT_VP) {
      return 'lg';
    }
    if (widthVp >= GeneratedDesignTokens.BREAKPOINT_WIDE_VP) {
      return 'md';
    }
    return 'sm';
  }

  /** 判断当前窗口是否处于横屏（宽大于高）。 */
  static isLandscape(widthVp: number, heightVp: number): boolean {
    return widthVp > heightVp;
  }

  /** 判断当前窗口是否为手机/分屏矮横屏（宽大于高且高度小于 480vp）。 */
  static isShortLandscape(widthVp: number, heightVp: number): boolean {
    return widthVp > heightVp && heightVp > 0 && heightVp < 480;
  }

  static isFoldUnfolded(): boolean {
    try {
      const status = display.getFoldStatus();
      return status === display.FoldStatus.FOLD_STATUS_EXPANDED ||
        status === display.FoldStatus.FOLD_STATUS_HALF_FOLDED;
    } catch {
      return false;
    }
  }

  static horizontalMargin(widthVp: number): number {
    if (widthVp >= GeneratedDesignTokens.BREAKPOINT_EXPANDED_VP) {
      return GeneratedDesignTokens.MARGIN_EXPANDED_VP;
    }
    if (widthVp >= GeneratedDesignTokens.BREAKPOINT_WIDE_VP) {
      return GeneratedDesignTokens.MARGIN_WIDE_VP;
    }
    return GeneratedDesignTokens.MARGIN_COMPACT_VP;
  }

  static posterGridColumns(widthVp: number): number {
    if (widthVp >= 1040) { return 6; }
    if (widthVp >= 780) { return 5; }
    if (widthVp >= 540) { return 4; }
    return 3;
  }

  /** 2:3 影视海报网格列模板字符串（响应式 3~6 列，确保骨架与真实网格 1:1 对齐）。 */
  static posterGridTemplate(widthVp: number): string {
    const cols = HarmonyAdaptiveLayout.posterGridColumns(widthVp);
    const parts: string[] = [];
    for (let i = 0; i < cols; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  /** 发现页顶部沉浸 Hero 响应式高度（兼容竖屏、平板宽屏与矮横屏）。 */
  static discoverHeroHeightVp(widthVp: number, heightVp: number): number {
    if (HarmonyAdaptiveLayout.isShortLandscape(widthVp, heightVp)) {
      return Math.max(204, Math.min(244, Math.round(heightVp * 0.58)));
    }
    if (widthVp >= 840 && heightVp >= 480) {
      return 380;
    }
    return 420;
  }

  /** 影视/媒体库详情页顶部沉浸 Hero 响应式高度（兼容竖屏、平板宽屏与矮横屏）。 */
  static detailHeroHeightVp(widthVp: number, heightVp: number): number {
    if (HarmonyAdaptiveLayout.isShortLandscape(widthVp, heightVp)) {
      return Math.max(188, Math.round(heightVp * 0.50));
    }
    if (widthVp >= 840 && heightVp >= 480) {
      return 340;
    }
    return 380;
  }

  /** 1:1 音乐方形专辑网格列模板（`>=1040` 6 列、`>=780` 5 列、`>=540` 4 列、其余 2 列）。 */
  static albumGridColumns(widthVp: number): string {
    let cols = 2;
    if (widthVp >= 1040) {
      cols = 6;
    } else if (widthVp >= 780) {
      cols = 5;
    } else if (widthVp >= 540) {
      cols = 4;
    }
    const parts: string[] = [];
    for (let i = 0; i < cols; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  static cardGridColumns(widthVp: number): number {
    return widthVp >= 740 ? 2 : 1;
  }

  /** 卡片网格列模板字符串（宽屏 2 列，窄屏 1 列）。 */
  static cardGridTemplate(widthVp: number): string {
    return HarmonyAdaptiveLayout.cardGridColumns(widthVp) >= 2 ? '1fr 1fr' : '1fr';
  }

  /**
   * 自适应半屏弹窗高度档位：
   * 矮横屏（`heightVp < 500`）直接展开 `SheetSize.LARGE`，避免 `MEDIUM` 仅剩约 195vp 狭缝。
   */
  static adaptiveSheetDetents(heightVp: number, allowMedium: boolean = true): HarmonySheetDetents {
    if (!allowMedium || (heightVp > 0 && heightVp < 500)) {
      return [SheetSize.LARGE];
    }
    return [SheetSize.MEDIUM, SheetSize.LARGE];
  }

  /** 宽屏（`>=680vp`）弹层优先采用居中模态 `SheetType.CENTER`，避免依附于 `0x0` 锚点的跟手气泡错位。 */
  static sheetPreferType(widthVp: number): SheetType {
    return widthVp >= GeneratedDesignTokens.BREAKPOINT_WIDE_VP ? SheetType.CENTER : SheetType.BOTTOM;
  }
}
