import { GeneratedDesignTokens, BackgroundPresetToken } from '../tokens/GeneratedTokens';

/** 外观模式：深色 / 浅色 / 跟随系统。 */
export type HarmonyAppearanceMode = 'dark' | 'light' | 'system';

/** 鸿蒙专属主题色板定义（结合 HarmonyOS 7 动态光感与冷静中性分层画布，不强行照搬 iOS 紫雾色系）。 */
export interface HarmonyPalettePreset {
  id: string;
  titleZh: string;
  subtitleZh: string;
  accentDark: string;
  accentLight: string;
  headerTintDark: string;
  headerTintLight: string;
  canvasDark: string;
  canvasLight: string;
  cardDark: string;
  cardLight: string;
  glowStopsDark: [ResourceColor, number][];
  glowStopsLight: [ResourceColor, number][];
}

export const HARMONY_PALETTES: HarmonyPalettePreset[] = [
  {
    id: 'harmony_blue',
    titleZh: '鸿蒙智蓝',
    subtitleZh: '星海深蓝',
    accentDark: '#317AF7',
    accentLight: '#0A59F7',
    headerTintDark: '#121D33',
    headerTintLight: '#E8F0FE',
    canvasDark: '#0B0E14',
    canvasLight: '#F1F3F5',
    cardDark: '#161B24',
    cardLight: '#FFFFFF',
    glowStopsDark: [['#2B4D96', 0.0], ['#162646', 0.45], ['#0B0E14', 1.0]],
    glowStopsLight: [['#C9DCFF', 0.0], ['#E6EFFC', 0.5], ['#F1F3F5', 1.0]]
  },
  {
    id: 'yachuan_teal',
    titleZh: '雅川青韵',
    subtitleZh: '松墨青翠',
    accentDark: '#26B8A8',
    accentLight: '#008A7B',
    headerTintDark: '#0E2424',
    headerTintLight: '#E5F5F2',
    canvasDark: '#0A1010',
    canvasLight: '#F0F4F3',
    cardDark: '#141E1E',
    cardLight: '#FFFFFF',
    glowStopsDark: [['#1B5E57', 0.0], ['#10302E', 0.45], ['#0A1010', 1.0]],
    glowStopsLight: [['#BFEBE5', 0.0], ['#E2F3F0', 0.5], ['#F0F4F3', 1.0]]
  },
  {
    id: 'danxia_amber',
    titleZh: '丹霞琥珀',
    subtitleZh: '暖金暮光',
    accentDark: '#F29B38',
    accentLight: '#C96A0A',
    headerTintDark: '#261A0E',
    headerTintLight: '#FCEFE0',
    canvasDark: '#100D0A',
    canvasLight: '#F5F2EE',
    cardDark: '#1D1813',
    cardLight: '#FFFFFF',
    glowStopsDark: [['#7A4918', 0.0], ['#382311', 0.45], ['#100D0A', 1.0]],
    glowStopsLight: [['#F8D9B5', 0.0], ['#F7EBDD', 0.5], ['#F5F2EE', 1.0]]
  },
  {
    id: 'obsidian_rose',
    titleZh: '曜石玫瑰',
    subtitleZh: '丝绒绯红',
    accentDark: '#EE6896',
    accentLight: '#C43267',
    headerTintDark: '#28131D',
    headerTintLight: '#FBEAF0',
    canvasDark: '#110C0F',
    canvasLight: '#F5F0F2',
    cardDark: '#1E151A',
    cardLight: '#FFFFFF',
    glowStopsDark: [['#7A2444', 0.0], ['#3A1624', 0.45], ['#110C0F', 1.0]],
    glowStopsLight: [['#F7C7D8', 0.0], ['#F6E5EB', 0.5], ['#F5F0F2', 1.0]]
  },
  {
    id: 'nebula_violet',
    titleZh: '星云紫罗',
    subtitleZh: '星夜靛紫',
    accentDark: '#9A78F5',
    accentLight: '#6B5CE7',
    headerTintDark: '#1C162E',
    headerTintLight: '#EFEBFD',
    canvasDark: '#0D0C14',
    canvasLight: '#F2F1F6',
    cardDark: '#181724',
    cardLight: '#FFFFFF',
    glowStopsDark: [['#4C388A', 0.0], ['#241B42', 0.45], ['#0D0C14', 1.0]],
    glowStopsLight: [['#D8CEFB', 0.0], ['#EAE6FA', 0.5], ['#F2F1F6', 1.0]]
  }
];

/** 模块自定义配置项（用于「发现」10 模块与「我的」8 模块的显隐与顺序编排）。 */
export interface CustomModulePref {
  id: string;
  title: string;
  enabled: boolean;
}

export const DEFAULT_DISCOVER_MODULES: CustomModulePref[] = [
  { id: 'continue', title: '继续观看', enabled: true },
  { id: 'movies', title: '热门电影', enabled: true },
  { id: 'tvs', title: '热门剧集', enabled: true },
  { id: 'trending', title: '本周趋势', enabled: true },
  { id: 'douban_music', title: '热门音乐', enabled: true },
  { id: 'douban_showing', title: '豆瓣热映', enabled: false },
  { id: 'douban_top250', title: '豆瓣 Top250', enabled: false },
  { id: 'latest', title: '最新入库', enabled: true },
  { id: 'libraries', title: '我的媒体库', enabled: true },
  { id: 'categories', title: '分类浏览', enabled: true }
];

export const DEFAULT_DASHBOARD_MODULES: CustomModulePref[] = [
  { id: 'media_stats', title: '媒体库统计', enabled: true },
  { id: 'storage', title: '存储空间', enabled: true },
  { id: 'downloader', title: '下载器', enabled: true },
  { id: 'medals', title: '社区勋章', enabled: true },
  { id: 'memory', title: '内存占用', enabled: true },
  { id: 'recent', title: '近期入库', enabled: true },
  { id: 'transfer_trend', title: '整理趋势', enabled: true },
  { id: 'schedules', title: '定时任务概览', enabled: true }
];

/**
 * 鸿蒙全局外观与布局状态中心：
 * - 以鸿蒙智蓝（`#317AF7` / `#0A59F7`）为核心色系，内置 5 套鸿蒙特色深浅色板；
 * - 实时广播深浅/跟随系统模式、HarmonyOS 7 动态光感开关、强调色、微光开关与窗口断点；
 * - 统一管理「发现」与「我的」模块编排配置（支持显隐、上下排序与恢复默认）。
 */
export class HarmonyAppearanceStore {
  static readonly KEY_IS_DARK = 'mp_is_dark';
  static readonly KEY_MODE = 'mp_appearance_mode';
  static readonly KEY_PALETTE_ID = 'mp_harmony_palette_id';
  static readonly KEY_BG_PRESET = 'mp_bg_preset';
  static readonly KEY_ACCENT_HEX = 'mp_accent_hex';
  static readonly KEY_ANIMATE_BG = 'mp_animate_bg';
  static readonly KEY_DYNAMIC_LIGHT = 'mp_dynamic_light';
  static readonly KEY_PURE_BLACK = 'mp_pure_black';
  static readonly KEY_SHOW_AI_MASCOT = 'mp_show_ai_mascot';
  static readonly KEY_LOCALE = 'mp_locale';
  static readonly KEY_ALLOW_SELF_SIGNED = 'mp_allow_self_signed';
  static readonly KEY_WINDOW_WIDTH_VP = 'mp_window_width_vp';
  static readonly KEY_WINDOW_HEIGHT_VP = 'mp_window_height_vp';
  static readonly KEY_BREAKPOINT = 'mp_breakpoint';
  static readonly KEY_DISCOVER_MODULES = 'mp_discover_modules_v2';
  static readonly KEY_DASHBOARD_MODULES = 'mp_dashboard_modules_v2';

  static initDefaults(): void {
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_IS_DARK, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_MODE, 'dark');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_PALETTE_ID, 'harmony_blue');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BG_PRESET, GeneratedDesignTokens.DEFAULT_BACKGROUND_PRESET);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ACCENT_HEX, '#317AF7');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ANIMATE_BG, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_PURE_BLACK, false);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_SHOW_AI_MASCOT, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_LOCALE, 'zh-CN');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ALLOW_SELF_SIGNED, false);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP, 412);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP, 892);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_BREAKPOINT, 'sm');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DISCOVER_MODULES, JSON.stringify(DEFAULT_DISCOVER_MODULES));
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DASHBOARD_MODULES, JSON.stringify(DEFAULT_DASHBOARD_MODULES));
  }

  static paletteById(id: string): HarmonyPalettePreset {
    for (let i = 0; i < HARMONY_PALETTES.length; i++) {
      if (HARMONY_PALETTES[i].id === id) {
        return HARMONY_PALETTES[i];
      }
    }
    return HARMONY_PALETTES[0];
  }

  static applyPalette(id: string, isDark: boolean): void {
    const p = HarmonyAppearanceStore.paletteById(id);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_PALETTE_ID, p.id);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ACCENT_HEX, isDark ? p.accentDark : p.accentLight);
  }

  static resetDefaults(): void {
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_MODE, 'dark');
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_IS_DARK, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_PURE_BLACK, false);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ANIMATE_BG, true);
    AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_SHOW_AI_MASCOT, true);
    HarmonyAppearanceStore.applyPalette('harmony_blue', true);
  }

  /** 导出当前外观与模块编排快照 JSON，供安全持久化跨重启恢复。 */
  static exportSnapshot(): string {
    const snap: Record<string, Object> = {};
    snap['mode'] = AppStorage.get<string>(HarmonyAppearanceStore.KEY_MODE) ?? 'dark';
    snap['isDark'] = AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_IS_DARK) ?? true;
    snap['paletteId'] = AppStorage.get<string>(HarmonyAppearanceStore.KEY_PALETTE_ID) ?? 'harmony_blue';
    snap['accentHex'] = AppStorage.get<string>(HarmonyAppearanceStore.KEY_ACCENT_HEX) ?? '#317AF7';
    snap['pureBlack'] = AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_PURE_BLACK) ?? false;
    snap['dynamicLight'] = AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT) ?? true;
    snap['animateBg'] = AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_ANIMATE_BG) ?? true;
    snap['showAiMascot'] = AppStorage.get<boolean>(HarmonyAppearanceStore.KEY_SHOW_AI_MASCOT) ?? true;
    snap['locale'] = AppStorage.get<string>(HarmonyAppearanceStore.KEY_LOCALE) ?? 'zh-CN';
    snap['discoverModules'] = AppStorage.get<string>(HarmonyAppearanceStore.KEY_DISCOVER_MODULES) ?? '';
    snap['dashboardModules'] = AppStorage.get<string>(HarmonyAppearanceStore.KEY_DASHBOARD_MODULES) ?? '';
    return JSON.stringify(snap);
  }

  /** 从持久化 JSON 恢复外观与模块配置。 */
  static importSnapshot(rawJson: string): void {
    if (!rawJson || rawJson.trim().length === 0) {
      return;
    }
    try {
      const rec = JSON.parse(rawJson) as Record<string, Object>;
      if (!rec || typeof rec !== 'object') { return; }
      const mode = typeof rec['mode'] === 'string' ? (rec['mode'] as string) : 'dark';
      const isDark = typeof rec['isDark'] === 'boolean' ? (rec['isDark'] as boolean) : (mode !== 'light');
      const paletteId = typeof rec['paletteId'] === 'string' ? (rec['paletteId'] as string) : 'harmony_blue';
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_MODE, mode);
      AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_IS_DARK, isDark);
      HarmonyAppearanceStore.applyPalette(paletteId, isDark);
      if (typeof rec['pureBlack'] === 'boolean') {
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_PURE_BLACK, rec['pureBlack'] as boolean);
      }
      if (typeof rec['dynamicLight'] === 'boolean') {
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DYNAMIC_LIGHT, rec['dynamicLight'] as boolean);
      }
      if (typeof rec['animateBg'] === 'boolean') {
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_ANIMATE_BG, rec['animateBg'] as boolean);
      }
      if (typeof rec['showAiMascot'] === 'boolean') {
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_SHOW_AI_MASCOT, rec['showAiMascot'] as boolean);
      }
      if (typeof rec['locale'] === 'string' && (rec['locale'] as string).length > 0) {
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_LOCALE, rec['locale'] as string);
      }
      if (typeof rec['discoverModules'] === 'string' && (rec['discoverModules'] as string).length > 2) {
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DISCOVER_MODULES, rec['discoverModules'] as string);
      }
      if (typeof rec['dashboardModules'] === 'string' && (rec['dashboardModules'] as string).length > 2) {
        AppStorage.setOrCreate(HarmonyAppearanceStore.KEY_DASHBOARD_MODULES, rec['dashboardModules'] as string);
      }
    } catch {
      // ignore malformed snapshot
    }
  }

  /** 将 `#RRGGBB` 或 `#AARRGGBB` 转为带指定 2 位十六进制透明度的 `#AARRGGBB`。 */
  static withAlpha(hex: string, alphaHex: string): string {
    const clean = hex.trim().replace(/^#/, '');
    const rgb = clean.length === 8 ? clean.substring(2) : (clean.length === 6 ? clean : '317AF7');
    return `#${alphaHex}${rgb}`;
  }

  static parseModules(rawJson: string, fallback: CustomModulePref[]): CustomModulePref[] {
    try {
      const parsed = JSON.parse(rawJson) as Object[];
      if (!Array.isArray(parsed) || parsed.length === 0) {
        return fallback.map((m: CustomModulePref): CustomModulePref => ({ id: m.id, title: m.title, enabled: m.enabled }));
      }
      const out: CustomModulePref[] = [];
      const seen = new Set<string>();
      for (let i = 0; i < parsed.length; i++) {
        const rec = parsed[i] as Record<string, Object>;
        const id = String(rec['id'] ?? '');
        const def = fallback.find((d: CustomModulePref) => d.id === id);
        if (def && !seen.has(id)) {
          seen.add(id);
          out.push({ id: def.id, title: def.title, enabled: Boolean(rec['enabled']) });
        }
      }
      for (let i = 0; i < fallback.length; i++) {
        if (!seen.has(fallback[i].id)) {
          out.push({ id: fallback[i].id, title: fallback[i].title, enabled: fallback[i].enabled });
        }
      }
      return out;
    } catch {
      return fallback.map((m: CustomModulePref): CustomModulePref => ({ id: m.id, title: m.title, enabled: m.enabled }));
    }
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
