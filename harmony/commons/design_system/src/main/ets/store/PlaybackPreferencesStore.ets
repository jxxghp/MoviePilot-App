import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 视频画面缩放比例模式：自适应黑边 / 铺满裁剪 / 拉伸铺满。 */
export type PlaybackScaleMode = 'fit' | 'fill' | 'stretch';

/** 统一支持的 6 档播放倍速数值。 */
export const PLAYBACK_SPEED_VALUES: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/** 统一支持的 6 档播放倍速展示文案。 */
export const PLAYBACK_SPEED_LABELS: string[] = ['0.5x', '0.75x', '1.0x', '1.25x', '1.5x', '2.0x'];

/** 视频画面比例枚举顺序。 */
export const PLAYBACK_SCALE_MODES: PlaybackScaleMode[] = ['fit', 'fill', 'stretch'];

/** 视频画面比例展示文案。 */
export const PLAYBACK_SCALE_LABELS: string[] = ['自适应', '铺满裁剪', '拉伸'];

interface ResumeRecordEntry {
  key: string;
  posMs: number;
  updatedAt: number;
}

/**
 * 鸿蒙音视频播放偏好与本地断点续播持久化中心（`Preferences` + `AppStorage`）：
 * - 启动时随 `EntryAbility` 预热默认键值并异步水合沙盒 `Preferences`；
 * - 持久化默认画面比例、视频默认倍速（音频固定 1.0x 起播）、中文字幕偏好、画中画自动续播、移动网络提醒与悬浮迷你条开关；
 * - 维护本地播放进度字典（`> 30s` 且 `< 95%` 时记录，`>= 95%` 自动清除完播项）。
 */
export class PlaybackPreferencesStore {
  static readonly KEY_SCALE_MODE: string = 'mp_playback_scale_mode';
  static readonly KEY_DEFAULT_SPEED: string = 'mp_playback_default_speed';
  static readonly KEY_PREFER_ZH_SUB: string = 'mp_playback_prefer_zh_sub';
  static readonly KEY_AUTO_PIP: string = 'mp_playback_auto_pip';
  static readonly KEY_CELLULAR_WARN: string = 'mp_playback_cellular_warn';
  static readonly KEY_KEEP_MINI_BAR: string = 'mp_playback_keep_mini_bar';
  static readonly KEY_STRM_DIRECT: string = 'mp_playback_strm_direct';
  static readonly KEY_DIRECT_PLAY: string = 'mp_playback_direct_play';

  private static readonly PREF_FILE_NAME: string = 'mp_harmony_playback_prefs_v1';
  private static readonly KEY_RESUME_RECORDS: string = 'mp_playback_resume_records_v1';
  private static readonly MAX_RESUME_ENTRIES: number = 200;

  private static pref: preferences.Preferences | null = null;
  private static resumeMap: Map<string, ResumeRecordEntry> = new Map<string, ResumeRecordEntry>();

  /** 确保 `AppStorage` 中已初始化全部播放偏好默认键值。 */
  static ensureAppStorageDefaults(): void {
    const ensure = <T>(key: string, val: T): void => {
      if (!AppStorage.has(key)) {
        AppStorage.setOrCreate(key, val);
      }
    };
    ensure<string>(PlaybackPreferencesStore.KEY_SCALE_MODE, 'fit');
    ensure<number>(PlaybackPreferencesStore.KEY_DEFAULT_SPEED, 1.0);
    ensure<boolean>(PlaybackPreferencesStore.KEY_PREFER_ZH_SUB, true);
    ensure<boolean>(PlaybackPreferencesStore.KEY_AUTO_PIP, true);
    ensure<boolean>(PlaybackPreferencesStore.KEY_CELLULAR_WARN, false);
    ensure<boolean>(PlaybackPreferencesStore.KEY_KEEP_MINI_BAR, true);
    ensure<boolean>(PlaybackPreferencesStore.KEY_STRM_DIRECT, true);
    ensure<boolean>(PlaybackPreferencesStore.KEY_DIRECT_PLAY, true);
  }

  /** 初始化沙盒 `Preferences` 句柄并将已保存的播放偏好与本地续播记录同步至内存与 `AppStorage`。 */
  static async init(context: common.Context): Promise<void> {
    PlaybackPreferencesStore.ensureAppStorageDefaults();
    try {
      if (!PlaybackPreferencesStore.pref) {
        PlaybackPreferencesStore.pref = await preferences.getPreferences(
          context,
          PlaybackPreferencesStore.PREF_FILE_NAME
        );
      }
      const p = PlaybackPreferencesStore.pref;
      if (!p) {
        return;
      }
      const rawScale = await p.get(PlaybackPreferencesStore.KEY_SCALE_MODE, 'fit');
      const scaleStr = typeof rawScale === 'string' ? rawScale : 'fit';
      const normalizedScale = PlaybackPreferencesStore.normalizeScaleMode(scaleStr);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_SCALE_MODE, normalizedScale);

      const rawSpeed = await p.get(PlaybackPreferencesStore.KEY_DEFAULT_SPEED, 1.0);
      const speedNum = typeof rawSpeed === 'number' ? rawSpeed : Number(rawSpeed);
      const normalizedSpeed = PlaybackPreferencesStore.normalizeSpeed(speedNum);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_DEFAULT_SPEED, normalizedSpeed);

      const rawZh = await p.get(PlaybackPreferencesStore.KEY_PREFER_ZH_SUB, true);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_PREFER_ZH_SUB, Boolean(rawZh));

      const rawPip = await p.get(PlaybackPreferencesStore.KEY_AUTO_PIP, true);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_AUTO_PIP, Boolean(rawPip));

      const rawCell = await p.get(PlaybackPreferencesStore.KEY_CELLULAR_WARN, false);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_CELLULAR_WARN, Boolean(rawCell));

      const rawMini = await p.get(PlaybackPreferencesStore.KEY_KEEP_MINI_BAR, true);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_KEEP_MINI_BAR, Boolean(rawMini));

      const rawStrm = await p.get(PlaybackPreferencesStore.KEY_STRM_DIRECT, true);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_STRM_DIRECT, Boolean(rawStrm));

      const rawDirect = await p.get(PlaybackPreferencesStore.KEY_DIRECT_PLAY, true);
      AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_DIRECT_PLAY, Boolean(rawDirect));

      const rawResume = await p.get(PlaybackPreferencesStore.KEY_RESUME_RECORDS, '');
      if (typeof rawResume === 'string' && rawResume.length > 2) {
        PlaybackPreferencesStore.hydrateResumeRecords(rawResume);
      }
    } catch {
      // 预览或沙盒受限环境保持 AppStorage 内存默认值可用
    }
  }

  /** 规范化画面比例字符串。 */
  static normalizeScaleMode(raw: string): PlaybackScaleMode {
    if (raw === 'fill' || raw === 'stretch') {
      return raw;
    }
    return 'fit';
  }

  /** 规范化播放倍速，落入最近的标准倍速档位。 */
  static normalizeSpeed(raw: number): number {
    if (!Number.isFinite(raw) || raw <= 0) {
      return 1.0;
    }
    let best = 1.0;
    let minDiff = 999;
    for (let i = 0; i < PLAYBACK_SPEED_VALUES.length; i++) {
      const candidate = PLAYBACK_SPEED_VALUES[i];
      const diff = Math.abs(candidate - raw);
      if (diff < minDiff) {
        minDiff = diff;
        best = candidate;
      }
    }
    return best;
  }

  /** 返回倍速在 `PLAYBACK_SPEED_VALUES` 中的下标（默认 `2` 即 `1.0x`）。 */
  static speedToIndex(speed: number): number {
    const norm = PlaybackPreferencesStore.normalizeSpeed(speed);
    for (let i = 0; i < PLAYBACK_SPEED_VALUES.length; i++) {
      if (Math.abs(PLAYBACK_SPEED_VALUES[i] - norm) < 0.01) {
        return i;
      }
    }
    return 2;
  }

  /** 返回画面比例在 `PLAYBACK_SCALE_MODES` 中的下标。 */
  static scaleModeToIndex(mode: string): number {
    if (mode === 'fill') { return 1; }
    if (mode === 'stretch') { return 2; }
    return 0;
  }

  /** 返回画面比例中文名称。 */
  static scaleModeLabel(mode: string): string {
    const idx = PlaybackPreferencesStore.scaleModeToIndex(mode);
    return PLAYBACK_SCALE_LABELS[idx];
  }

  /** 返回倍速展示名称（如 `1.0x`、`1.25x`）。 */
  static speedLabel(speed: number): string {
    const idx = PlaybackPreferencesStore.speedToIndex(speed);
    return PLAYBACK_SPEED_LABELS[idx];
  }

  /** 生成设置页「播放偏好」行的动态摘要副标题。 */
  static formatSettingsSummary(scaleMode: string, speed: number, autoPip: boolean): string {
    const scaleTxt = PlaybackPreferencesStore.scaleModeLabel(scaleMode);
    const speedTxt = PlaybackPreferencesStore.speedLabel(speed);
    const pipTxt = autoPip ? '画中画开启' : '画中画关闭';
    return `${scaleTxt} · ${speedTxt} · ${pipTxt}`;
  }

  static setScaleMode(mode: PlaybackScaleMode): void {
    const norm = PlaybackPreferencesStore.normalizeScaleMode(mode);
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_SCALE_MODE, norm);
    PlaybackPreferencesStore.putPrefString(PlaybackPreferencesStore.KEY_SCALE_MODE, norm);
  }

  static setDefaultSpeed(speed: number): void {
    const norm = PlaybackPreferencesStore.normalizeSpeed(speed);
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_DEFAULT_SPEED, norm);
    PlaybackPreferencesStore.putPrefNumber(PlaybackPreferencesStore.KEY_DEFAULT_SPEED, norm);
  }

  static setPreferZhSub(enabled: boolean): void {
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_PREFER_ZH_SUB, enabled);
    PlaybackPreferencesStore.putPrefBool(PlaybackPreferencesStore.KEY_PREFER_ZH_SUB, enabled);
  }

  static setAutoPip(enabled: boolean): void {
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_AUTO_PIP, enabled);
    PlaybackPreferencesStore.putPrefBool(PlaybackPreferencesStore.KEY_AUTO_PIP, enabled);
  }

  static setCellularWarn(enabled: boolean): void {
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_CELLULAR_WARN, enabled);
    PlaybackPreferencesStore.putPrefBool(PlaybackPreferencesStore.KEY_CELLULAR_WARN, enabled);
  }

  static setKeepMiniBar(enabled: boolean): void {
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_KEEP_MINI_BAR, enabled);
    PlaybackPreferencesStore.putPrefBool(PlaybackPreferencesStore.KEY_KEEP_MINI_BAR, enabled);
  }

  static setStrmDirect(enabled: boolean): void {
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_STRM_DIRECT, enabled);
    PlaybackPreferencesStore.putPrefBool(PlaybackPreferencesStore.KEY_STRM_DIRECT, enabled);
  }

  static setDirectPlay(enabled: boolean): void {
    AppStorage.setOrCreate(PlaybackPreferencesStore.KEY_DIRECT_PLAY, enabled);
    PlaybackPreferencesStore.putPrefBool(PlaybackPreferencesStore.KEY_DIRECT_PLAY, enabled);
  }

  static getScaleMode(): PlaybackScaleMode {
    const raw = AppStorage.get<string>(PlaybackPreferencesStore.KEY_SCALE_MODE) ?? 'fit';
    return PlaybackPreferencesStore.normalizeScaleMode(raw);
  }

  static getDefaultVideoSpeed(): number {
    const raw = AppStorage.get<number>(PlaybackPreferencesStore.KEY_DEFAULT_SPEED) ?? 1.0;
    return PlaybackPreferencesStore.normalizeSpeed(raw);
  }

  static getPreferZhSub(): boolean {
    return AppStorage.get<boolean>(PlaybackPreferencesStore.KEY_PREFER_ZH_SUB) ?? true;
  }

  static getAutoPip(): boolean {
    return AppStorage.get<boolean>(PlaybackPreferencesStore.KEY_AUTO_PIP) ?? true;
  }

  static getCellularWarn(): boolean {
    return AppStorage.get<boolean>(PlaybackPreferencesStore.KEY_CELLULAR_WARN) ?? false;
  }

  static getKeepMiniBar(): boolean {
    return AppStorage.get<boolean>(PlaybackPreferencesStore.KEY_KEEP_MINI_BAR) ?? true;
  }

  static getStrmDirect(): boolean {
    return AppStorage.get<boolean>(PlaybackPreferencesStore.KEY_STRM_DIRECT) ?? true;
  }

  static getDirectPlay(): boolean {
    return AppStorage.get<boolean>(PlaybackPreferencesStore.KEY_DIRECT_PLAY) ?? true;
  }

  /**
   * 持久化本地播放断点（毫秒）：
   * - 当 `durMs > 0` 且 `posMs >= durMs * 0.95` 时视为已完播，主动清理断点；
   * - 当 `posMs > 30_000` 且未超过总时长 `95%` 时写入持久化缓存。
   */
  static saveLocalResumeMs(key: string, posMs: number, durMs: number): void {
    const cleanKey = key.trim();
    if (!cleanKey || !Number.isFinite(posMs)) {
      return;
    }
    if (durMs > 0 && posMs >= durMs * 0.95) {
      if (PlaybackPreferencesStore.resumeMap.has(cleanKey)) {
        PlaybackPreferencesStore.resumeMap.delete(cleanKey);
        PlaybackPreferencesStore.flushResumeRecords();
      }
      return;
    }
    if (posMs <= 30000) {
      return;
    }
    const safePos = Math.round(posMs);
    PlaybackPreferencesStore.resumeMap.delete(cleanKey);
    PlaybackPreferencesStore.resumeMap.set(cleanKey, {
      key: cleanKey,
      posMs: safePos,
      updatedAt: Date.now()
    });
    while (PlaybackPreferencesStore.resumeMap.size > PlaybackPreferencesStore.MAX_RESUME_ENTRIES) {
      const oldest = PlaybackPreferencesStore.resumeMap.keys().next().value as string | undefined;
      if (!oldest) {
        break;
      }
      PlaybackPreferencesStore.resumeMap.delete(oldest);
    }
    PlaybackPreferencesStore.flushResumeRecords();
  }

  /** 读取指定媒体键的本地断点位置（毫秒），不存在时返回 `0`。 */
  static getLocalResumeMs(key: string): number {
    const cleanKey = key.trim();
    if (!cleanKey) {
      return 0;
    }
    const hit = PlaybackPreferencesStore.resumeMap.get(cleanKey);
    return hit && hit.posMs > 30000 ? hit.posMs : 0;
  }

  /** 主动清除指定媒体键的本地续播记录（例如用户点击「从头开始」时）。 */
  static clearLocalResumeMs(key: string): void {
    const cleanKey = key.trim();
    if (!cleanKey) {
      return;
    }
    if (PlaybackPreferencesStore.resumeMap.delete(cleanKey)) {
      PlaybackPreferencesStore.flushResumeRecords();
    }
  }

  private static hydrateResumeRecords(rawJson: string): void {
    try {
      const arr = JSON.parse(rawJson) as Object[];
      if (!Array.isArray(arr)) {
        return;
      }
      PlaybackPreferencesStore.resumeMap.clear();
      for (let i = 0; i < arr.length; i++) {
        const rec = arr[i] as Record<string, Object>;
        if (!rec) { continue; }
        const k = typeof rec['key'] === 'string' ? (rec['key'] as string).trim() : '';
        const p = Number(rec['posMs']);
        const u = Number(rec['updatedAt']) || 0;
        if (k.length > 0 && Number.isFinite(p) && p > 30000) {
          PlaybackPreferencesStore.resumeMap.set(k, { key: k, posMs: Math.round(p), updatedAt: u });
        }
      }
    } catch {
      // ignore malformed resume JSON
    }
  }

  private static flushResumeRecords(): void {
    const list: ResumeRecordEntry[] = [];
    PlaybackPreferencesStore.resumeMap.forEach((entry: ResumeRecordEntry) => {
      list.push(entry);
    });
    PlaybackPreferencesStore.putPrefString(PlaybackPreferencesStore.KEY_RESUME_RECORDS, JSON.stringify(list));
  }

  private static putPrefString(key: string, val: string): void {
    const p = PlaybackPreferencesStore.pref;
    if (!p) { return; }
    p.put(key, val).then(() => p.flush()).catch(() => {});
  }

  private static putPrefNumber(key: string, val: number): void {
    const p = PlaybackPreferencesStore.pref;
    if (!p) { return; }
    p.put(key, val).then(() => p.flush()).catch(() => {});
  }

  private static putPrefBool(key: string, val: boolean): void {
    const p = PlaybackPreferencesStore.pref;
    if (!p) { return; }
    p.put(key, val).then(() => p.flush()).catch(() => {});
  }
}
