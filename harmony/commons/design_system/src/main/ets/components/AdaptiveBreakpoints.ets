import { display } from '@kit.ArkUI';
import { GeneratedDesignTokens } from '../tokens/GeneratedTokens';

/** 鸿蒙「一次开发、多端部署」一多断点枚举。 */
export type HarmonyBreakpoint = 'sm' | 'md' | 'lg';

/**
 * 鸿蒙响应式多形态布局中心（对齐 `shared/design-tokens/layout.json`）：
 * 自动结合窗口宽度 vp 与 `display.getFoldStatus()` 驱动手机、阔折叠屏、平板多栏与网格列数。
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

  static cardGridColumns(widthVp: number): number {
    return widthVp >= 740 ? 2 : 1;
  }
}
