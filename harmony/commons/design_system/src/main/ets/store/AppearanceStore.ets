import { GeneratedDesignTokens, BackgroundPresetToken } from '../tokens/GeneratedTokens';

/** 外观模式：深色 / 浅色 / 跟随系统。 */
export type HarmonyAppearanceMode = 'dark' | 'light' | 'system';

/**
 * 鸿蒙全局外观与布局状态中心：
 * - 通过 AppStorage 实时广播深浅/跟随系统模式、HarmonyOS 7 动态光感开关、强调色、氛围色板与窗口断点；
 * - 默认关闭背景动画（`animateBg = false`），保持鸿蒙原生冷静中性画布并兼顾续航与帧率。
 */
export class HarmonyAppearanceStore {
  static readonly KEY_IS_DARK = 'mp_is_dark';
  static readonly KEY_MODE = 'mp_appearance_mode';
  static readonly KEY_BG_PRESET = 'mp_bg_preset';
  static readonly KEY_ACCENT_HEX = 'mp_accent_hex';
  static readonly KEY_ANIMATE_BG = 'mp_animate_bg';
  static readonly KEY_DYNAMIC_LIGHT = 'mp_dynamic_light';
  static readonly KEY_WINDOW_WIDTH_VP = 'mp_window_width_vp';
  static readonly KEY_BREAKPOINT = 'mp_breakpoint';

  static initDefaults(): void {
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_IS_DARK, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_MODE, 'dark');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BG_PRESET, GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ACCENT_HEX, '#9E7AF5');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ANIMATE_BG, false);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP, 412);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BREAKPOINT, 'sm');
  }

  static getStops(presetId: string, isDark: boolean): string[] {
    const found: BackgroundPresetToken | undefined =
      GeneratedDesignTokens.BACKGROUND_PRESETS.find((p) => p.id === presetId);
    const preset = found ?? GeneratedDesignTokens.BACKGROUND_PRESETS[0];
    return isDark ? preset.darkStops : preset.lightStops;
  }

  static getGradientStops(presetId: string, isDark: boolean): [ResourceColor, number][] {
    const stops = HarmonyAppearanceStore.getStops(presetId, isDark);
    return [
      [stops[0], 0.0],
      [stops[1], 0.33],
      [stops[2], 0.70],
      [stops[3], 1.0]
    ];
  }
}
