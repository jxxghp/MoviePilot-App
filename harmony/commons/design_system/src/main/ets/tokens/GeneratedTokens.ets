// 自动生成自 shared/design-tokens/*.json，请勿手工修改；请运行 python3 tools/sync-all.py。

/** 预设背景渐变色板定义（深色与浅色 4 段色点）。 */
export interface BackgroundPresetToken {
  id: string;
  titleZh: string;
  titleEn: string;
  darkStops: string[];
  lightStops: string[];
}

/** 预设主题强调色定义。 */
export interface AccentPresetToken {
  id: string;
  titleZh: string;
  titleEn: string;
  hex: string;
}

/** 深浅色自适应语义色对。 */
export interface AdaptiveHexToken {
  light: string;
  dark: string;
}

/** 鸿蒙端三端同源视觉 Token（由 shared/design-tokens 自动生成）。 */
export class GeneratedDesignTokens {
  static readonly DEFAULT_MODE: string = 'dark';
  static readonly DEFAULT_BACKGROUND_PRESET: string = 'cinematic';
  static readonly DEFAULT_ACCENT_PRESET: string = 'violet';
  static readonly PANEL_CORNER_RADIUS_VP: number = 24;
  static readonly PANEL_PADDING_VP: number = 18;
  static readonly PANEL_BORDER_WIDTH_VP: number = 0.7;
  static readonly SHEET_CORNER_RADIUS_VP: number = 28;
  static readonly NAV_BLUR_RADIUS: number = 36;
  static readonly NAV_BLUR_SATURATION: number = 1.35;
  static readonly NAV_BLUR_BRIGHTNESS: number = 1.04;
  static readonly POINT_LIGHT_CARD_INTENSITY: number = 1.15;
  static readonly POINT_LIGHT_CARD_RADIUS: number = 160;
  static readonly POINT_LIGHT_NAV_INTENSITY: number = 1.4;
  static readonly POINT_LIGHT_NAV_RADIUS: number = 120;
  static readonly MARGIN_COMPACT_VP: number = 20;
  static readonly MARGIN_WIDE_VP: number = 24;
  static readonly MARGIN_EXPANDED_VP: number = 28;
  static readonly BREAKPOINT_WIDE_VP: number = 680;
  static readonly BREAKPOINT_TABLET_SPLIT_VP: number = 840;
  static readonly BREAKPOINT_EXPANDED_VP: number = 960;
  static readonly AMBIENT_FPS: number = 15;

  static readonly BACKGROUND_PRESETS: BackgroundPresetToken[] = [
    { id: 'cinematic', titleZh: '星夜紫玫', titleEn: 'Starlit Violet', darkStops: ['#30334A', '#4A3B57', '#57384A', '#242E40'], lightStops: ['#F0EDFC', '#F5EBF7', '#FAEDF2', '#EBF0FC'] },
    { id: 'ocean', titleZh: '深海极光', titleEn: 'Ocean Aurora', darkStops: ['#142947', '#1A3D57', '#1F4757', '#122138'], lightStops: ['#E6F2FC', '#E8F7FA', '#EDF5FC', '#E3F0FA'] },
    { id: 'forest', titleZh: '静谧松林', titleEn: 'Quiet Forest', darkStops: ['#1A3330', '#244238', '#2E4030', '#142629'], lightStops: ['#E8F7F2', '#F0FAF0', '#F2F7ED', '#E6F2F0'] },
    { id: 'amber', titleZh: '暖阳琥珀', titleEn: 'Warm Amber', darkStops: ['#3D2B26', '#52362B', '#472E33', '#292129'], lightStops: ['#FCF2E8', '#FCEDE6', '#FAF0ED', '#F5EDEB'] },
    { id: 'graphite', titleZh: '极简石墨', titleEn: 'Minimal Graphite', darkStops: ['#101218', '#181B24', '#151821', '#0C0E14'], lightStops: ['#F2F2F7', '#EDF0F5', '#F2F2F5', '#E8EBF2'] },
    { id: 'custom', titleZh: '自定义', titleEn: 'Custom', darkStops: ['#30334A', '#4A3B57', '#57384A', '#242E40'], lightStops: ['#F0EDFC', '#F5EBF7', '#FAEDF2', '#EBF0FC'] },
  ];

  static readonly ACCENT_PRESETS: AccentPresetToken[] = [
    { id: 'violet', titleZh: '星耀紫', titleEn: 'Starlight Violet', hex: '#9E7AF5' },
    { id: 'azure', titleZh: '极光蓝', titleEn: 'Aurora Azure', hex: '#47A3FA' },
    { id: 'emerald', titleZh: '翡翠绿', titleEn: 'Emerald Green', hex: '#3DC78F' },
    { id: 'rose', titleZh: '珊瑚粉', titleEn: 'Coral Rose', hex: '#EB6B9E' },
    { id: 'amber', titleZh: '琥珀金', titleEn: 'Amber Gold', hex: '#F2A33D' },
    { id: 'custom', titleZh: '自定义', titleEn: 'Custom', hex: '#9E7AF5' },
  ];

  static readonly SEMANTIC: Record<string, AdaptiveHexToken> = {
    'success': { light: '#148A47', dark: '#75E6A3' },
    'warning': { light: '#BD6B08', dark: '#FFCC6B' },
    'danger': { light: '#CC2933', dark: '#FF8A94' },
    'info': { light: '#1A70D6', dark: '#75C7FF' },
    'brand': { light: '#6638C7', dark: '#D6BDFF' },
    'pink': { light: '#C22E75', dark: '#F58FBD' },
    'cyan': { light: '#0D809E', dark: '#75D6E6' },
    'chipFill': { light: '#0E000000', dark: '#17FFFFFF' },
    'chipBorder': { light: '#1C000000', dark: '#26FFFFFF' },
    'chipText': { light: '#E0242424', dark: '#DBFFFFFF' },
    'badgeFill': { light: '#0F000000', dark: '#1AFFFFFF' },
    'badgeMutedText': { light: '#D1474747', dark: '#ADFFFFFF' },
    'fieldFill': { light: '#0E000000', dark: '#17FFFFFF' },
    'fieldBorder': { light: '#1A000000', dark: '#24FFFFFF' },
    'primaryButtonBackground': { light: '#1F1F29', dark: '#F0FFFFFF' },
    'primaryButtonForeground': { light: '#FFFFFF', dark: '#1F1A29' },
    'divider': { light: '#17000000', dark: '#1CFFFFFF' },
    'fallbackBackground': { light: '#F0EDFC', dark: '#29293B' },
    'solidSurface': { light: '#F7F7FC', dark: '#473B52' },
    'roseGlow': { light: '#1AB36396', dark: '#1AB36396' },
  };

  static readonly OHOS_SYMBOLS: Record<string, string> = {
    'tab_discover': 'sys.symbol.sparkles',
    'tab_explore': 'sys.symbol.compass',
    'tab_dashboard': 'sys.symbol.person_crop_circle',
    'tab_settings': 'sys.symbol.gearshape',
    'action_search': 'sys.symbol.magnifyingglass',
    'action_add': 'sys.symbol.plus',
    'action_refresh': 'sys.symbol.arrow_clockwise',
    'action_edit': 'sys.symbol.slider_horizontal_2',
    'action_filter': 'sys.symbol.line_3_horizontal_decrease',
    'menu_subscriptions': 'sys.symbol.heart_square',
    'menu_calendar': 'sys.symbol.calendar',
    'menu_resources': 'sys.symbol.tray_full',
    'menu_downloads': 'sys.symbol.arrow_down_circle',
    'menu_files': 'sys.symbol.folder',
    'menu_history': 'sys.symbol.clock',
    'menu_workflows': 'sys.symbol.share',
    'menu_plugins': 'sys.symbol.puzzle',
    'feature_sites': 'sys.symbol.worldclock',
    'feature_messages': 'sys.symbol.bell',
    'feature_shortcuts': 'sys.symbol.bolt',
    'feature_agent': 'sys.symbol.ai_edit',
    'feature_music': 'sys.symbol.music',
    'feature_users': 'sys.symbol.person_2',
    'feature_appearance': 'sys.symbol.paintbrush',
    'feature_system': 'sys.symbol.cpu',
    'feature_medals': 'sys.symbol.star_circle',
    'player_play': 'sys.symbol.play_fill',
    'player_pause': 'sys.symbol.pause_fill',
    'player_pip': 'sys.symbol.picture_in_picture',
    'player_lock': 'sys.symbol.lock_fill',
    'player_unlock': 'sys.symbol.lock_open_fill',
    'player_subtitles': 'sys.symbol.text_bubble',
    'player_audio_track': 'sys.symbol.waveform',
    'player_aspect': 'sys.symbol.rectangle_expand_vertical',
    'player_speed': 'sys.symbol.timer',
    'mode_dark': 'sys.symbol.moon_fill',
    'mode_light': 'sys.symbol.sun_max_fill',
    'mode_system': 'sys.symbol.circle_lefthalf_inset_filled',
  };

  /** 解析当前深浅色下的语义色值。 */
  static semanticColor(key: string, isDark: boolean): string {
    const pair = GeneratedDesignTokens.SEMANTIC[key];
    if (!pair) { return isDark ? '#FFFFFF' : '#1C1A24'; }
    return isDark ? pair.dark : pair.light;
  }
}
