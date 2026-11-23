import { GeneratedDesignTokens, BackgroundPresetToken } from '../tokens/GeneratedTokens';

/** 外观模式：深色 / 浅色 / 跟随系统。 */
export type HarmonyAppearanceMode = 'dark' | 'light' | 'system';

/**
 * 鸿蒙全局外观状态中心：严格消费 `GeneratedDesignTokens`，
 * 通过 AppStorage 实时广播深浅色切换、6 套背景色板、6 套强调色与流光开关。
 */
export class HarmonyAppearanceStore {
  static readonly KEY_IS_DARK = 'mp_is_dark';
  static readonly KEY_BG_PRESET = 'mp_bg_preset';
  static readonly KEY_ACCENT_HEX = 'mp_accent_hex';
  static readonly KEY_ANIMATE_BG = 'mp_animate_bg';

  static initDefaults(): void {
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_IS_DARK, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BG_PRESET, GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ACCENT_HEX, '#9E7AF5');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ANIMATE_BG, true);
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
