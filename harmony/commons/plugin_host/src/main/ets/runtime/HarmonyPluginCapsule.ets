import { display } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { MoviePilotRepository, MpRemoteImage } from '@moviepilot/core_rust_bridge';
import {
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import { HarmonyLocalPluginShellView } from './HarmonyLocalPluginShellView';
import { HarmonyPluginHeaderAction } from './HarmonyPluginHostBridgeV2';

/** 鸿蒙最小化悬浮胶囊上的快捷动作项。 */
export interface HarmonyPluginCapsuleAction {
  id: string;
  label: string;
  icon: string;
  active: boolean;
  destructive: boolean;
}

/** 鸿蒙联邦插件全局保活会话与胶囊展示快照。 */
export interface HarmonyPluginCapsuleState {
  pluginId: string;
  pluginName: string;
  serverUrl?: string;
  surface: string;
  navKey: string;
  pluginHasPage: boolean;
  isMinimized: boolean;
  title: string;
  subtitle: string;
  capsuleTitle?: string;
  capsuleArtist?: string;
  statusText: string;
  iconUrl: string;
  mode: string; // 'jump' | 'mini'
  isPlaying: boolean;
  edgeSnapThresholdDp?: number;
  actions: HarmonyPluginCapsuleAction[];
}

/** 识别胶囊内联快捷动作图标类型。 */
function classifyHarmonyCapsuleAction(act: HarmonyPluginCapsuleAction): string {
  const combined = `${act.id} ${act.icon}`.toLowerCase();
  if (combined.includes('prev') || combined.includes('skip-previous') || combined.includes('step-backward')) {
    return 'previous';
  }
  if (combined.includes('play') || combined.includes('pause') || combined.includes('toggle')) {
    return 'play_pause';
  }
  if (combined.includes('next') || combined.includes('skip-next') || combined.includes('step-forward')) {
    return 'next';
  }
  if (combined.includes('heart') || combined.includes('like') || combined.includes('fav')) {
    return 'heart';
  }
  if (
    combined.includes('repeat-one') ||
    combined.includes('repeat_one') ||
    combined.includes('repeat-once') ||
    combined.includes('repeat_once') ||
    combined.includes('loop-one') ||
    combined.includes('loop_one')
  ) {
    return 'repeat_one';
  }
  if (combined.includes('repeat') || combined.includes('loop')) {
    return 'repeat';
  }
  if (combined.includes('shuffle') || combined.includes('random')) {
    return 'shuffle';
  }
  if (combined.includes('lyric') || combined.includes('lrc')) {
    return 'lyrics';
  }
  return 'generic';
}

/** 将播放状态同步写回动作列表中播放/暂停控制项的 `active` 字段。 */
function syncHarmonyPlayActions(
  actions: HarmonyPluginCapsuleAction[],
  isPlaying: boolean
): HarmonyPluginCapsuleAction[] {
  const out: HarmonyPluginCapsuleAction[] = [];
  for (let i = 0; i < actions.length; i++) {
    const act = actions[i];
    if (classifyHarmonyCapsuleAction(act) === 'play_pause') {
      out.push({
        id: act.id,
        label: act.label,
        icon: act.icon,
        active: isPlaying,
        destructive: act.destructive
      });
    } else {
      out.push(act);
    }
  }
  return out;
}

/**
 * 鸿蒙端联邦插件全局保活与紧凑单行最小化胶囊协调器：
 * - 在顶层 `Index.ets` 常驻挂载 `HarmonyGlobalVuePluginOverlay`，最小化时仅收起全屏展示而不销毁 `<Web>`，
 *   确保 Vue 联邦组件状态、音频与定时器在跨 Tab 浏览期间持续保活；
 * - 统一渲染为紧凑单行横向播控胶囊，支持同源相对路径封面鉴权加载与原生播放状态实时同步。
 */
export class HarmonyPluginCapsuleManager {
  static readonly KEY_STATE_JSON = 'mp_harmony_plugin_capsule_json';
  static readonly KEY_MINI_EXPANDED = 'mp_harmony_plugin_capsule_mini_expanded';

  private static instance: HarmonyPluginCapsuleManager | null = null;
  private dispatchActionHandler: ((actionId: string) => void) | null = null;
  private requestBackHandler: (() => boolean) | null = null;

  static shared(): HarmonyPluginCapsuleManager {
    if (!HarmonyPluginCapsuleManager.instance) {
      HarmonyPluginCapsuleManager.instance = new HarmonyPluginCapsuleManager();
    }
    return HarmonyPluginCapsuleManager.instance;
  }

  bindRuntimeHandlers(
    dispatchCapsuleAction: ((actionId: string) => void) | null,
    requestBack: (() => boolean) | null
  ): void {
    this.dispatchActionHandler = dispatchCapsuleAction;
    this.requestBackHandler = requestBack;
  }

  currentState(): HarmonyPluginCapsuleState | null {
    const raw = AppStorage.get<string>(HarmonyPluginCapsuleManager.KEY_STATE_JSON) ?? '';
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as HarmonyPluginCapsuleState;
    } catch {
      return null;
    }
  }

  private saveState(state: HarmonyPluginCapsuleState | null): void {
    AppStorage.setOrCreate(
      HarmonyPluginCapsuleManager.KEY_STATE_JSON,
      state ? JSON.stringify(state) : ''
    );
    if (!state) {
      AppStorage.setOrCreate(HarmonyPluginCapsuleManager.KEY_MINI_EXPANDED, false);
    }
  }

  /** 打开联邦插件全屏层（若同一插件正处于最小化胶囊状态则零重载直接恢复）。 */
  openPlugin(
    pluginId: string,
    pluginName: string,
    surface: string = 'dataPage',
    pluginHasPage: boolean = true,
    iconUrl: string = '',
    navKey: string = ''
  ): void {
    const cur = this.currentState();
    const repoBase = (MoviePilotRepository.shared().baseUrl ?? '').replace(/\/+$/, '');
    if (cur && cur.pluginId.toLowerCase() === pluginId.toLowerCase()) {
      cur.isMinimized = false;
      cur.surface = surface || cur.surface;
      if (repoBase.length > 0) {
        cur.serverUrl = repoBase;
      }
      AppStorage.setOrCreate(HarmonyPluginCapsuleManager.KEY_MINI_EXPANDED, false);
      this.saveState(cur);
      return;
    }
    this.saveState({
      pluginId: pluginId,
      pluginName: pluginName || pluginId,
      serverUrl: repoBase,
      surface: surface || 'dataPage',
      navKey: navKey,
      pluginHasPage: pluginHasPage,
      isMinimized: false,
      title: pluginName || pluginId,
      subtitle: '',
      statusText: '',
      iconUrl: iconUrl,
      mode: 'jump',
      isPlaying: false,
      actions: []
    });
  }

  /** 将当前打开的联邦插件转为紧凑单行最小化悬浮胶囊（不卸载底层 ArkWeb）。 */
  minimizeActive(payload: Record<string, Object>, fallbackPluginId: string, fallbackName: string): void {
    const cur = this.currentState();
    const parsedActions = HarmonyPluginCapsuleManager.parseActions(payload['actions']);
    const rawMode = typeof payload['mode'] === 'string' ? (payload['mode'] as string).toLowerCase() : '';
    const resolvedMode = (rawMode === 'mini' || rawMode === 'jump')
      ? rawMode
      : (parsedActions.length > 0 ? 'mini' : 'jump');
    const resolvedName = (typeof payload['pluginName'] === 'string' && (payload['pluginName'] as string).trim().length > 0)
      ? (payload['pluginName'] as string).trim()
      : (cur ? cur.pluginName : (fallbackName || fallbackPluginId));
    const resolvedTitle = (typeof payload['title'] === 'string' && (payload['title'] as string).trim().length > 0)
      ? (payload['title'] as string).trim()
      : resolvedName;

    const effectiveActions = parsedActions.length > 0 || Array.isArray(payload['actions'])
      ? parsedActions
      : (cur ? cur.actions : []);
    let inferredPlaying = cur ? cur.isPlaying : false;
    for (let i = 0; i < effectiveActions.length; i++) {
      if (classifyHarmonyCapsuleAction(effectiveActions[i]) === 'play_pause') {
        inferredPlaying = effectiveActions[i].active;
        break;
      }
    }
    const resolvedPlaying = typeof payload['isPlaying'] === 'boolean'
      ? (payload['isPlaying'] as boolean)
      : inferredPlaying;
    const repoBase = (MoviePilotRepository.shared().baseUrl ?? '').replace(/\/+$/, '');

    const rawSnap = typeof payload['edgeSnapThresholdDp'] === 'number'
      ? (payload['edgeSnapThresholdDp'] as number)
      : (typeof payload['snapThresholdDp'] === 'number' ? (payload['snapThresholdDp'] as number) : 24);
    const resolvedSnap = Math.max(0, Math.min(72, Math.floor(rawSnap)));

    const next: HarmonyPluginCapsuleState = {
      pluginId: cur ? cur.pluginId : fallbackPluginId,
      pluginName: resolvedName,
      serverUrl: (cur && cur.serverUrl && cur.serverUrl.length > 0) ? cur.serverUrl : repoBase,
      surface: cur ? cur.surface : 'dataPage',
      navKey: cur ? cur.navKey : '',
      pluginHasPage: cur ? cur.pluginHasPage : true,
      isMinimized: true,
      title: resolvedTitle,
      subtitle: typeof payload['subtitle'] === 'string' ? (payload['subtitle'] as string) : (cur ? cur.subtitle : ''),
      capsuleTitle: (typeof payload['capsuleTitle'] === 'string' && (payload['capsuleTitle'] as string).trim().length > 0)
        ? (payload['capsuleTitle'] as string).trim()
        : undefined,
      capsuleArtist: (typeof payload['capsuleArtist'] === 'string' && (payload['capsuleArtist'] as string).trim().length > 0)
        ? (payload['capsuleArtist'] as string).trim()
        : undefined,
      statusText: typeof payload['statusText'] === 'string' ? (payload['statusText'] as string) : (cur ? cur.statusText : ''),
      iconUrl: (typeof payload['iconUrl'] === 'string' && (payload['iconUrl'] as string).trim().length > 0)
        ? (payload['iconUrl'] as string).trim()
        : (cur ? cur.iconUrl : ''),
      mode: resolvedMode,
      isPlaying: resolvedPlaying,
      edgeSnapThresholdDp: resolvedSnap,
      actions: syncHarmonyPlayActions(effectiveActions, resolvedPlaying)
    };
    AppStorage.setOrCreate(HarmonyPluginCapsuleManager.KEY_MINI_EXPANDED, false);
    this.saveState(next);
  }

  /** 在最小化期间局部刷新胶囊标题、副标题、状态或快捷按钮。 */
  updateCapsule(payload: Record<string, Object>): void {
    const cur = this.currentState();
    if (!cur) {
      return;
    }
    if (typeof payload['title'] === 'string' && (payload['title'] as string).trim().length > 0) {
      cur.title = (payload['title'] as string).trim();
    }
    if (typeof payload['subtitle'] === 'string') {
      cur.subtitle = payload['subtitle'] as string;
    }
    if (typeof payload['capsuleTitle'] === 'string') {
      const ct = (payload['capsuleTitle'] as string).trim();
      cur.capsuleTitle = ct.length > 0 ? ct : undefined;
    }
    if (typeof payload['capsuleArtist'] === 'string') {
      const ca = (payload['capsuleArtist'] as string).trim();
      cur.capsuleArtist = ca.length > 0 ? ca : undefined;
    }
    if (typeof payload['statusText'] === 'string') {
      cur.statusText = payload['statusText'] as string;
    }
    if (typeof payload['iconUrl'] === 'string' && (payload['iconUrl'] as string).trim().length > 0) {
      cur.iconUrl = (payload['iconUrl'] as string).trim();
    }
    if (typeof payload['mode'] === 'string') {
      const m = (payload['mode'] as string).toLowerCase();
      if (m === 'jump' || m === 'mini') {
        cur.mode = m;
      }
    }
    if (Array.isArray(payload['actions'])) {
      cur.actions = HarmonyPluginCapsuleManager.parseActions(payload['actions']);
    }
    if (typeof payload['isPlaying'] === 'boolean') {
      cur.isPlaying = payload['isPlaying'] as boolean;
    } else if (Array.isArray(payload['actions'])) {
      for (let i = 0; i < cur.actions.length; i++) {
        if (classifyHarmonyCapsuleAction(cur.actions[i]) === 'play_pause') {
          cur.isPlaying = cur.actions[i].active;
          break;
        }
      }
    }
    if (typeof payload['edgeSnapThresholdDp'] === 'number' || typeof payload['snapThresholdDp'] === 'number') {
      const rawSnap = typeof payload['edgeSnapThresholdDp'] === 'number'
        ? (payload['edgeSnapThresholdDp'] as number)
        : (payload['snapThresholdDp'] as number);
      cur.edgeSnapThresholdDp = Math.max(0, Math.min(72, Math.floor(rawSnap)));
    }
    cur.actions = syncHarmonyPlayActions(cur.actions, cur.isPlaying);
    this.saveState(cur);
  }

  /** 原生音频播放状态变化或调用 `setNowPlaying` 时，实时同步胶囊播放图标与曲目信息，并保留专用短标题。 */
  syncAudioPlaybackState(
    pluginId: string,
    isPlaying: boolean,
    title: string = '',
    subtitle: string = '',
    iconUrl: string = '',
    capsuleTitle: string = '',
    capsuleArtist: string = ''
  ): void {
    const cur = this.currentState();
    if (!cur) {
      return;
    }
    if (pluginId.length > 0 && cur.pluginId.toLowerCase() !== pluginId.toLowerCase()) {
      return;
    }
    const cleanTitle = title.trim();
    const trackChanged = cleanTitle.length > 0 && cleanTitle !== cur.title;
    if (cleanTitle.length > 0) {
      cur.title = cleanTitle;
    }
    if (subtitle.trim().length > 0) {
      cur.subtitle = subtitle.trim();
    }
    if (capsuleTitle.trim().length > 0) {
      cur.capsuleTitle = capsuleTitle.trim();
    } else if (trackChanged) {
      cur.capsuleTitle = undefined;
    }
    if (capsuleArtist.trim().length > 0) {
      cur.capsuleArtist = capsuleArtist.trim();
    } else if (trackChanged) {
      cur.capsuleArtist = undefined;
    }
    if (iconUrl.trim().length > 0) {
      cur.iconUrl = iconUrl.trim();
    }
    cur.isPlaying = isPlaying;
    cur.actions = syncHarmonyPlayActions(cur.actions, isPlaying);
    this.saveState(cur);
  }

  /** 恢复最小化胶囊至全屏联邦插件窗口。 */
  restoreFullWindow(): void {
    const cur = this.currentState();
    if (!cur) {
      return;
    }
    cur.isMinimized = false;
    AppStorage.setOrCreate(HarmonyPluginCapsuleManager.KEY_MINI_EXPANDED, false);
    this.saveState(cur);
  }

  /** 彻底关闭联邦插件并触发底层 ArkWeb 卸载释放。 */
  closeAndDestroy(): void {
    this.dispatchActionHandler = null;
    this.requestBackHandler = null;
    this.saveState(null);
  }

  /** 转发胶囊快捷动作点击给保活中的联邦插件。 */
  dispatchAction(actionId: string): void {
    if (this.dispatchActionHandler) {
      this.dispatchActionHandler(actionId);
    }
  }

  /** 当联邦插件全屏展示时拦截系统物理返回手势并透传 `nav.back`。 */
  handleSystemBackPress(): boolean {
    const cur = this.currentState();
    if (!cur || cur.isMinimized) {
      return false;
    }
    if (this.requestBackHandler && this.requestBackHandler()) {
      return true;
    }
    this.closeAndDestroy();
    return true;
  }

  static parseActions(raw: Object | undefined): HarmonyPluginCapsuleAction[] {
    if (!Array.isArray(raw)) {
      return [];
    }
    const list = raw as Object[];
    const out: HarmonyPluginCapsuleAction[] = [];
    for (let i = 0; i < list.length; i++) {
      const item = list[i] as Record<string, Object>;
      if (!item || typeof item['id'] !== 'string') {
        continue;
      }
      const id = (item['id'] as string).trim();
      if (id.length === 0) {
        continue;
      }
      const label = (typeof item['label'] === 'string' && (item['label'] as string).trim().length > 0)
        ? (item['label'] as string).trim()
        : ((typeof item['title'] === 'string' && (item['title'] as string).trim().length > 0)
          ? (item['title'] as string).trim()
          : id);
      out.push({
        id: id,
        label: label,
        icon: typeof item['icon'] === 'string' ? (item['icon'] as string) : '',
        active: typeof item['active'] === 'boolean' ? (item['active'] as boolean) : false,
        destructive: typeof item['destructive'] === 'boolean' ? (item['destructive'] as boolean) : false
      });
    }
    return out;
  }
}

/**
 * 顶层常驻 Vue 联邦插件保活宿主层：
 * 全屏打开时铺满窗口响应交互，最小化为胶囊时收缩为透明零命中节点持续保活 ArkWeb 实例。
 */
@Component
export struct HarmonyGlobalVuePluginOverlay {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyPluginCapsuleManager.KEY_STATE_JSON) capsuleJson: string = '';

  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  onFallbackToLegacy: (pluginId: string, surface: string) => void = () => {};

  private parseState(): HarmonyPluginCapsuleState | null {
    if (this.capsuleJson.length === 0) {
      return null;
    }
    try {
      return JSON.parse(this.capsuleJson) as HarmonyPluginCapsuleState;
    } catch {
      return null;
    }
  }

  build() {
    if (this.parseState() !== null) {
      Column() {
        HarmonyLocalPluginShellView({
          pluginId: this.parseState()!.pluginId,
          pluginName: this.parseState()!.pluginName,
          serverUrl: this.serverUrl,
          authToken: this.authToken,
          userName: this.userName,
          userAvatar: this.userAvatar,
          isSuperuser: this.isSuperuser,
          surface: this.parseState()!.surface,
          navKey: this.parseState()!.navKey,
          pluginHasPage: this.parseState()!.pluginHasPage,
          onHeaderUpdate: (_title: string, _actions: HarmonyPluginHeaderAction[]) => {},
          onRequestDismiss: () => {
            HarmonyPluginCapsuleManager.shared().closeAndDestroy();
          },
          onFallbackToLegacy: () => {
            const st = this.parseState();
            const pid = st ? st.pluginId : '';
            const surf = st ? st.surface : 'dataPage';
            HarmonyPluginCapsuleManager.shared().closeAndDestroy();
            if (pid.length > 0) {
              this.onFallbackToLegacy(pid, surf);
            }
          }
        })
      }
      .width(this.parseState()!.isMinimized ? 1 : '100%')
      .height(this.parseState()!.isMinimized ? 1 : '100%')
      .padding({ top: this.parseState()!.isMinimized ? 0 : Math.max(8, this.safeTopVp) })
      .backgroundColor(
        this.parseState()!.isMinimized
          ? Color.Transparent
          : HarmonyThemeColors.canvas(this.isDark, this.paletteId, this.pureBlack)
      )
      .opacity(this.parseState()!.isMinimized ? 0 : 1)
      .hitTestBehavior(this.parseState()!.isMinimized ? HitTestMode.None : HitTestMode.Default)
    }
  }
}

/**
 * 鸿蒙跨页面紧凑单行横向悬浮胶囊组件：
 * - 拖动与松手约束在安全区内并持久化位置，靠近左右边缘 `< edgeSnapThresholdDp`（默认 24vp）自动贴边收缩为半圆「超级最小化」；
 * - 点击贴边半圆恢复完整单行胶囊，避免越界丢失。
 */
@Component
export struct HarmonyPluginFloatingCapsule {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 28;
  @StorageLink(HarmonyPluginCapsuleManager.KEY_STATE_JSON) capsuleJson: string = '';
  @StorageLink('mp_harmony_capsule_norm_x') normX: number = 1.0;
  @StorageLink('mp_harmony_capsule_norm_y') normY: number = 0.78;
  @StorageLink('mp_harmony_capsule_docked_edge') dockedEdge: string = 'none';

  @Prop bottomClearanceVp: number = 94;

  @State private isDragging: boolean = false;
  @State private liveDragX: number = 0;
  @State private liveDragY: number = 0;
  @State private pillWidthVp: number = 206;
  @State private pillHeightVp: number = 38;
  private dragBaseX: number = 0;
  private dragBaseY: number = 0;

  private isSuperMinimized(): boolean {
    return this.dockedEdge === 'left' || this.dockedEdge === 'right';
  }

  private viewportSizeVp(): Array<number> {
    try {
      const disp = display.getDefaultDisplaySync();
      const density = disp.densityPixels > 0 ? disp.densityPixels : 3.0;
      return [Math.max(240, disp.width / density), Math.max(360, disp.height / density)];
    } catch {
      return [390, 844];
    }
  }

  private resolvedOriginVp(st: HarmonyPluginCapsuleState): Array<number> {
    const vp = this.viewportSizeVp();
    const vpW = vp[0];
    const vpH = vp[1];
    const itemW = this.isSuperMinimized() ? 42 : Math.max(120, this.pillWidthVp);
    const itemH = Math.max(36, this.pillHeightVp);
    const minY = Math.max(8, this.safeTopVp + 8);
    const maxY = Math.max(minY, vpH - Math.max(10, this.safeBottomVp) - this.bottomClearanceVp - itemH);
    const clampedNormY = Math.max(0, Math.min(1, this.normY));
    const y = Math.max(minY, Math.min(maxY, minY + (maxY - minY) * clampedNormY));

    if (this.dockedEdge === 'left') {
      return [0, y];
    }
    if (this.dockedEdge === 'right') {
      return [Math.max(0, vpW - itemW), y];
    }
    const hMargin = 12;
    const minFreeX = hMargin;
    const maxFreeX = Math.max(minFreeX, vpW - hMargin - itemW);
    const clampedNormX = Math.max(0, Math.min(1, this.normX));
    const x = Math.max(minFreeX, Math.min(maxFreeX, minFreeX + (maxFreeX - minFreeX) * clampedNormX));
    return [x, y];
  }

  private clampDragVp(rawX: number, rawY: number): Array<number> {
    const vp = this.viewportSizeVp();
    const vpW = vp[0];
    const vpH = vp[1];
    const itemW = this.isSuperMinimized() ? 42 : Math.max(120, this.pillWidthVp);
    const itemH = Math.max(36, this.pillHeightVp);
    const minY = Math.max(8, this.safeTopVp + 8);
    const maxY = Math.max(minY, vpH - Math.max(10, this.safeBottomVp) - this.bottomClearanceVp - itemH);
    const maxX = Math.max(0, vpW - itemW);
    return [
      Math.max(0, Math.min(maxX, rawX)),
      Math.max(minY, Math.min(maxY, rawY))
    ];
  }

  private tapHaptic(): void {
    try {
      vibrator.startVibration({ type: 'time', duration: 12 }, { id: 0, usage: 'touch' }).catch(() => {});
    } catch {
      // ignore
    }
  }

  private minimizedState(): HarmonyPluginCapsuleState | null {
    if (this.capsuleJson.length === 0) {
      return null;
    }
    try {
      const parsed = JSON.parse(this.capsuleJson) as HarmonyPluginCapsuleState;
      return parsed.isMinimized ? parsed : null;
    } catch {
      return null;
    }
  }

  /** 解析胶囊封面地址：相对路径 `/` 自动拼接当前实例 `serverUrl`，交由 `MpRemoteImage` 原生同源鉴权加载。 */
  private resolveCoverUrl(st: HarmonyPluginCapsuleState): string {
    const raw = (st.iconUrl ?? '').trim();
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('/')) {
      const base = ((st.serverUrl && st.serverUrl.length > 0)
        ? st.serverUrl
        : (MoviePilotRepository.shared().baseUrl ?? '')).replace(/\/+$/, '');
      return base.length > 0 ? `${base}${raw}` : '';
    }
    return raw;
  }

  /** 获取最多前 3 个内联快捷动作。 */
  private inlineActions(st: HarmonyPluginCapsuleState): HarmonyPluginCapsuleAction[] {
    return (st.actions ?? []).slice(0, 3);
  }

  /** 解析内联按钮前景色。 */
  private resolveActionColor(act: HarmonyPluginCapsuleAction): ResourceColor {
    const kind = classifyHarmonyCapsuleAction(act);
    if (act.destructive) {
      return '#EF4444';
    }
    if (kind === 'heart' && act.active) {
      return '#FF5C8A';
    }
    if (kind !== 'play_pause' && act.active) {
      return this.accentHex;
    }
    return mpPrimaryText(this.isDark);
  }

  @Builder
  private renderInlineActionIcon(act: HarmonyPluginCapsuleAction, isPlaying: boolean) {
    if (classifyHarmonyCapsuleAction(act) === 'previous') {
      SymbolGlyph($r('sys.symbol.backward_end_fill'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    } else if (classifyHarmonyCapsuleAction(act) === 'play_pause') {
      SymbolGlyph(isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    } else if (classifyHarmonyCapsuleAction(act) === 'next') {
      SymbolGlyph($r('sys.symbol.forward_end_fill'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    } else if (classifyHarmonyCapsuleAction(act) === 'heart') {
      Text(act.active ? '♥' : '♡')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolveActionColor(act))
    } else if (classifyHarmonyCapsuleAction(act) === 'repeat_one') {
      SymbolGlyph($r('sys.symbol.repeat_1'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    } else if (classifyHarmonyCapsuleAction(act) === 'repeat') {
      SymbolGlyph($r('sys.symbol.repeat'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    } else if (classifyHarmonyCapsuleAction(act) === 'shuffle') {
      SymbolGlyph($r('sys.symbol.shuffle'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    } else if (classifyHarmonyCapsuleAction(act) === 'lyrics') {
      SymbolGlyph($r('sys.symbol.lyrics_square'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    } else {
      SymbolGlyph($r('sys.symbol.music_note_list'))
        .fontSize(14)
        .fontColor([this.resolveActionColor(act)])
    }
  }

  build() {
    if (this.minimizedState() !== null) {
      if (this.isSuperMinimized()) {
        Row() {
          if (this.resolveCoverUrl(this.minimizedState()!).length > 0) {
            MpRemoteImage({
              src: this.resolveCoverUrl(this.minimizedState()!),
              imgWidth: 28,
              imgHeight: 28,
              imgRadius: 14
            })
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, '28'))
              SymbolGlyph($r('sys.symbol.puzzle'))
                .fontSize(14)
                .fontColor([this.accentHex])
            }
          }
        }
        .padding({
          left: this.dockedEdge === 'left' ? 6 : 8,
          right: this.dockedEdge === 'right' ? 6 : 8,
          top: 5,
          bottom: 5
        })
        .borderRadius({
          topLeft: this.dockedEdge === 'left' ? 0 : 999,
          bottomLeft: this.dockedEdge === 'left' ? 0 : 999,
          topRight: this.dockedEdge === 'right' ? 0 : 999,
          bottomRight: this.dockedEdge === 'right' ? 0 : 999
        })
        .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
        .border({ width: 1, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '88') })
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        .position({
          x: this.isDragging ? this.liveDragX : this.resolvedOriginVp(this.minimizedState()!)[0],
          y: this.isDragging ? this.liveDragY : this.resolvedOriginVp(this.minimizedState()!)[1]
        })
        .onClick(() => {
          this.tapHaptic();
          this.normX = this.dockedEdge === 'left' ? 0.0 : 1.0;
          this.dockedEdge = 'none';
        })
        .gesture(
          PanGesture({ distance: 4 })
            .onActionStart(() => {
              const cur = this.resolvedOriginVp(this.minimizedState()!);
              this.dragBaseX = cur[0];
              this.dragBaseY = cur[1];
              this.liveDragX = cur[0];
              this.liveDragY = cur[1];
              this.isDragging = true;
            })
            .onActionUpdate((ev?: GestureEvent) => {
              if (ev) {
                const clamped = this.clampDragVp(this.dragBaseX + ev.offsetX, this.dragBaseY + ev.offsetY);
                this.liveDragX = clamped[0];
                this.liveDragY = clamped[1];
              }
            })
            .onActionEnd(() => {
              this.settleDragAt(this.liveDragX, this.liveDragY);
            })
            .onActionCancel(() => {
              this.isDragging = false;
            })
        )
      } else {
        Row({ space: 2 }) {
          Row({ space: 6 }) {
            if (this.resolveCoverUrl(this.minimizedState()!).length > 0) {
              MpRemoteImage({
                src: this.resolveCoverUrl(this.minimizedState()!),
                imgWidth: 26,
                imgHeight: 26,
                imgRadius: 13
              })
            } else {
              Stack({ alignContent: Alignment.Center }) {
                Column()
                  .width(26)
                  .height(26)
                  .borderRadius(13)
                  .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, '28'))
                SymbolGlyph($r('sys.symbol.puzzle'))
                  .fontSize(13)
                  .fontColor([this.accentHex])
              }
            }

            Column({ space: 1 }) {
              Text(this.minimizedState()!.capsuleTitle || this.minimizedState()!.title)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(mpPrimaryText(this.isDark))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width(64)
              if ((this.minimizedState()!.capsuleArtist || this.minimizedState()!.subtitle || this.minimizedState()!.statusText).length > 0) {
                Text(this.minimizedState()!.capsuleArtist || this.minimizedState()!.subtitle || this.minimizedState()!.statusText)
                  .fontSize(10)
                  .fontColor(mpSecondaryText(this.isDark))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(64)
              }
            }
            .width(64)
            .alignItems(HorizontalAlign.Start)
          }
          .padding({ right: 2 })
          .onClick(() => {
            this.tapHaptic();
            HarmonyPluginCapsuleManager.shared().restoreFullWindow();
          })

          ForEach(
            this.inlineActions(this.minimizedState()!),
            (act: HarmonyPluginCapsuleAction) => {
              Button({ type: ButtonType.Circle }) {
                this.renderInlineActionIcon(act, this.minimizedState()!.isPlaying)
              }
              .width(25)
              .height(25)
              .backgroundColor(Color.Transparent)
              .accessibilityText(act.label)
              .onClick(() => {
                this.tapHaptic();
                HarmonyPluginCapsuleManager.shared().dispatchAction(act.id);
              })
            },
            (act: HarmonyPluginCapsuleAction) => `${act.id}_${act.active}_${this.minimizedState()!.isPlaying}`
          )

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(11.5)
              .fontColor([mpSecondaryText(this.isDark)])
          }
          .width(23)
          .height(25)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭插件胶囊')
          .onClick(() => {
            this.tapHaptic();
            HarmonyPluginCapsuleManager.shared().closeAndDestroy();
          })
        }
        .padding({ left: 6, right: 4, top: 5, bottom: 5 })
        .borderRadius(999)
        .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
        .border({ width: 1, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '55') })
        .shadow({ radius: 14, color: '#33000000', offsetY: 4 })
        .onAreaChange((_oldVal: Area, newVal: Area) => {
          const w = Number(newVal.width);
          const h = Number(newVal.height);
          if (w > 40) { this.pillWidthVp = w; }
          if (h > 20) { this.pillHeightVp = h; }
        })
        .position({
          x: this.isDragging ? this.liveDragX : this.resolvedOriginVp(this.minimizedState()!)[0],
          y: this.isDragging ? this.liveDragY : this.resolvedOriginVp(this.minimizedState()!)[1]
        })
        .gesture(
          PanGesture({ distance: 4 })
            .onActionStart(() => {
              const cur = this.resolvedOriginVp(this.minimizedState()!);
              this.dragBaseX = cur[0];
              this.dragBaseY = cur[1];
              this.liveDragX = cur[0];
              this.liveDragY = cur[1];
              this.isDragging = true;
            })
            .onActionUpdate((ev?: GestureEvent) => {
              if (ev) {
                const clamped = this.clampDragVp(this.dragBaseX + ev.offsetX, this.dragBaseY + ev.offsetY);
                this.liveDragX = clamped[0];
                this.liveDragY = clamped[1];
              }
            })
            .onActionEnd(() => {
              this.settleDragAt(this.liveDragX, this.liveDragY);
            })
            .onActionCancel(() => {
              this.isDragging = false;
            })
        )
      }
    }
  }

  private settleDragAt(clampedX: number, clampedY: number): void {
    const st = this.minimizedState();
    const vp = this.viewportSizeVp();
    const vpW = vp[0];
    const vpH = vp[1];
    const itemW = this.isSuperMinimized() ? 42 : Math.max(120, this.pillWidthVp);
    const itemH = Math.max(36, this.pillHeightVp);
    const minY = Math.max(8, this.safeTopVp + 8);
    const maxY = Math.max(minY, vpH - Math.max(10, this.safeBottomVp) - this.bottomClearanceVp - itemH);
    const nextNormY = maxY > minY ? Math.max(0, Math.min(1, (clampedY - minY) / (maxY - minY))) : 0.78;
    const snapThreshold = (st && typeof st.edgeSnapThresholdDp === 'number') ? st.edgeSnapThresholdDp : 24;
    const distLeft = Math.max(0, clampedX);
    const distRight = Math.max(0, vpW - (clampedX + itemW));

    this.isDragging = false;
    this.normY = nextNormY;
    if (snapThreshold > 0 && distLeft <= snapThreshold && distLeft <= distRight) {
      if (this.dockedEdge !== 'left') { this.tapHaptic(); }
      this.dockedEdge = 'left';
      this.normX = 0.0;
    } else if (snapThreshold > 0 && distRight <= snapThreshold) {
      if (this.dockedEdge !== 'right') { this.tapHaptic(); }
      this.dockedEdge = 'right';
      this.normX = 1.0;
    } else {
      if (this.dockedEdge !== 'none') { this.tapHaptic(); }
      this.dockedEdge = 'none';
      const hMargin = 12;
      const minFreeX = hMargin;
      const maxFreeX = Math.max(minFreeX, vpW - hMargin - itemW);
      const settledX = Math.max(minFreeX, Math.min(maxFreeX, clampedX));
      this.normX = maxFreeX > minFreeX ? Math.max(0, Math.min(1, (settledX - minFreeX) / (maxFreeX - minFreeX))) : 1.0;
    }
  }
}
