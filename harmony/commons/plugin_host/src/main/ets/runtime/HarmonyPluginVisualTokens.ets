import { HarmonyAppearanceStore } from '@moviepilot/design_system';

export interface HarmonyPluginVisualSemantic {
  success: string;
  warning: string;
  danger: string;
  info: string;
  brand: string;
}

/** 鸿蒙端向本地联邦运行时壳注入的视觉融合 Token 快照（与 `NativeVisualTokens` 1:1 对齐）。 */
export interface HarmonyPluginVisualTokens {
  mode: string;
  platform: string;
  backgroundPreset: string;
  isAmoledBlack: boolean;
  highContrast: boolean;
  accentHex: string;
  onAccentHex: string;
  textPrimaryHex: string;
  textSecondaryHex: string;
  surfaceGlassRgba: string;
  surfaceElevatedRgba: string;
  surfaceBorderRgba: string;
  surfaceBlurPx: number;
  solidSurfaceHex: string;
  fieldFillRgba: string;
  fieldBorderRgba: string;
  chipFillRgba: string;
  chipBorderRgba: string;
  dividerRgba: string;
  panelRadiusPx: number;
  sheetRadiusPx: number;
  borderWidthPx: number;
  semantic: HarmonyPluginVisualSemantic;
}

function hexToRgbTuple(hex: string): [number, number, number] {
  const clean = (hex ?? '').trim().replace(/^#/, '');
  const rgb = clean.length === 8 ? clean.substring(2) : (clean.length === 6 ? clean : '317AF7');
  const r = parseInt(rgb.substring(0, 2), 16);
  const g = parseInt(rgb.substring(2, 4), 16);
  const b = parseInt(rgb.substring(4, 6), 16);
  return [
    Number.isFinite(r) ? r : 49,
    Number.isFinite(g) ? g : 122,
    Number.isFinite(b) ? b : 247
  ];
}

export function buildHarmonyPluginVisualTokens(
  isDark: boolean,
  paletteId: string,
  accentHex: string,
  pureBlack: boolean
): HarmonyPluginVisualTokens {
  const preset = HarmonyAppearanceStore.paletteById(paletteId);
  const resolvedAccent = accentHex && accentHex.trim().length > 0
    ? accentHex.trim()
    : (isDark ? preset.accentDark : preset.accentLight);
  const rgb = hexToRgbTuple(resolvedAccent);
  const lum = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2];
  const onAccentHex = lum > 186 ? '#18181B' : '#FFFFFF';
  const amoled = isDark && pureBlack;
  const solidSurfaceHex = amoled ? '#000000' : (isDark ? preset.canvasDark : preset.canvasLight);

  return {
    mode: isDark ? 'dark' : 'light',
    platform: 'harmony',
    backgroundPreset: preset.id,
    isAmoledBlack: amoled,
    highContrast: false,
    accentHex: resolvedAccent,
    onAccentHex: onAccentHex,
    textPrimaryHex: isDark ? '#F5F7FA' : '#18181B',
    textSecondaryHex: isDark ? '#A8B1C2' : '#5B6270',
    surfaceGlassRgba: amoled
      ? 'rgba(18,21,28,0.88)'
      : (isDark ? 'rgba(255,255,255,0.09)' : 'rgba(255,255,255,0.74)'),
    surfaceElevatedRgba: amoled
      ? 'rgba(26,30,40,0.94)'
      : (isDark ? 'rgba(22,27,36,0.90)' : 'rgba(255,255,255,0.92)'),
    surfaceBorderRgba: isDark ? 'rgba(255,255,255,0.16)' : 'rgba(15,23,42,0.10)',
    surfaceBlurPx: 20,
    solidSurfaceHex: solidSurfaceHex,
    fieldFillRgba: isDark ? 'rgba(255,255,255,0.07)' : 'rgba(255,255,255,0.82)',
    fieldBorderRgba: isDark ? 'rgba(255,255,255,0.18)' : 'rgba(15,23,42,0.16)',
    chipFillRgba: isDark ? 'rgba(255,255,255,0.11)' : 'rgba(15,23,42,0.06)',
    chipBorderRgba: isDark ? 'rgba(255,255,255,0.16)' : 'rgba(15,23,42,0.12)',
    dividerRgba: isDark ? 'rgba(255,255,255,0.12)' : 'rgba(15,23,42,0.10)',
    panelRadiusPx: 18,
    sheetRadiusPx: 22,
    borderWidthPx: 0.75,
    semantic: {
      success: isDark ? '#34D399' : '#16A34A',
      warning: isDark ? '#FBBF24' : '#D97706',
      danger: isDark ? '#F87171' : '#DC2626',
      info: isDark ? '#38BDF8' : '#0284C7',
      brand: resolvedAccent
    }
  };
}
