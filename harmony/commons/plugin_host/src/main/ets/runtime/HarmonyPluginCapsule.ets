import { vibrator } from '@kit.SensorServiceKit';
import { MpRemoteImage } from '@moviepilot/core_rust_bridge';
import {
  HarmonyAppearanceStore,
  HarmonyThemeColors,
  NativeAdaptivePill,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import { HarmonyLocalPluginShellView } from './HarmonyLocalPluginShellView';
import { HarmonyPluginHeaderAction } from './HarmonyPluginHostBridgeV2';

/** 鸿蒙最小化悬浮小窗上的快捷动作项。 */
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
  surface: string;
  navKey: string;
  pluginHasPage: boolean;
  isMinimized: boolean;
  title: string;
  subtitle: string;
  statusText: string;
  iconUrl: string;
  mode: string; // 'jump' | 'mini'
  isPlaying: boolean;
  actions: HarmonyPluginCapsuleAction[];
}

/**
 * 鸿蒙端联邦插件全局保活与最小化胶囊协调器：
 * - 在顶层 `Index.ets` 常驻挂载 `HarmonyGlobalVuePluginOverlay`，最小化时仅收起全屏展示而不销毁 `<Web>`，
 *   确保 Vue 联邦组件状态、音频与定时器在跨 Tab 浏览期间持续保活；
 * - 支持「仅点击跳转胶囊 (`jump`)」与「点击展开快捷操作小悬浮窗 (`mini`)」两种模式。
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
    if (cur && cur.pluginId.toLowerCase() === pluginId.toLowerCase()) {
      cur.isMinimized = false;
      cur.surface = surface || cur.surface;
      AppStorage.setOrCreate(HarmonyPluginCapsuleManager.KEY_MINI_EXPANDED, false);
      this.saveState(cur);
      return;
    }
    this.saveState({
      pluginId: pluginId,
      pluginName: pluginName || pluginId,
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

  /** 将当前打开的联邦插件转为最小化悬浮胶囊（不卸载底层 ArkWeb）。 */
  minimizeActive(payload: Record<string, Object>, fallbackPluginId: string, fallbackName: string): void {
    const cur = this.currentState();
    const actions = HarmonyPluginCapsuleManager.parseActions(payload['actions']);
    const rawMode = typeof payload['mode'] === 'string' ? (payload['mode'] as string).toLowerCase() : '';
    const resolvedMode = (rawMode === 'mini' || rawMode === 'jump')
      ? rawMode
      : (actions.length > 0 ? 'mini' : 'jump');
    const resolvedName = (typeof payload['pluginName'] === 'string' && (payload['pluginName'] as string).trim().length > 0)
      ? (payload['pluginName'] as string).trim()
      : (cur ? cur.pluginName : (fallbackName || fallbackPluginId));
    const resolvedTitle = (typeof payload['title'] === 'string' && (payload['title'] as string).trim().length > 0)
      ? (payload['title'] as string).trim()
      : resolvedName;

    const next: HarmonyPluginCapsuleState = {
      pluginId: cur ? cur.pluginId : fallbackPluginId,
      pluginName: resolvedName,
      surface: cur ? cur.surface : 'dataPage',
      navKey: cur ? cur.navKey : '',
      pluginHasPage: cur ? cur.pluginHasPage : true,
      isMinimized: true,
      title: resolvedTitle,
      subtitle: typeof payload['subtitle'] === 'string' ? (payload['subtitle'] as string) : (cur ? cur.subtitle : ''),
      statusText: typeof payload['statusText'] === 'string' ? (payload['statusText'] as string) : (cur ? cur.statusText : ''),
      iconUrl: (typeof payload['iconUrl'] === 'string' && (payload['iconUrl'] as string).trim().length > 0)
        ? (payload['iconUrl'] as string).trim()
        : (cur ? cur.iconUrl : ''),
      mode: resolvedMode,
      isPlaying: typeof payload['isPlaying'] === 'boolean' ? (payload['isPlaying'] as boolean) : (cur ? cur.isPlaying : false),
      actions: actions.length > 0 || Array.isArray(payload['actions']) ? actions : (cur ? cur.actions : [])
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
    if (typeof payload['isPlaying'] === 'boolean') {
      cur.isPlaying = payload['isPlaying'] as boolean;
    }
    if (Array.isArray(payload['actions'])) {
      cur.actions = HarmonyPluginCapsuleManager.parseActions(payload['actions']);
    }
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

  /** 转发小悬浮窗快捷动作点击给保活中的联邦插件。 */
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
 * 鸿蒙跨页面悬浮插件胶囊与快捷操作小悬浮窗组件（支持自由拖拽、仅跳转胶囊与快捷操作面板）。
 */
@Component
export struct HarmonyPluginFloatingCapsule {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageLink(HarmonyPluginCapsuleManager.KEY_STATE_JSON) capsuleJson: string = '';
  @StorageLink(HarmonyPluginCapsuleManager.KEY_MINI_EXPANDED) miniExpanded: boolean = false;

  @State private offsetX: number = 0;
  @State private offsetY: number = 0;
  private dragStartX: number = 0;
  private dragStartY: number = 0;

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

  private isMiniMode(st: HarmonyPluginCapsuleState): boolean {
    return st.mode === 'mini' || st.actions.length > 0;
  }

  build() {
    if (this.minimizedState() !== null) {
      Column({ space: 8 }) {
        if (this.miniExpanded && this.isMiniMode(this.minimizedState()!)) {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              if (this.minimizedState()!.iconUrl.length > 0) {
                MpRemoteImage({
                  src: this.minimizedState()!.iconUrl,
                  imgWidth: 34,
                  imgHeight: 34,
                  imgRadius: 17
                })
              } else {
                Stack({ alignContent: Alignment.Center }) {
                  Column()
                    .width(34)
                    .height(34)
                    .borderRadius(17)
                    .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, '28'))
                  SymbolGlyph($r('sys.symbol.puzzle'))
                    .fontSize(17)
                    .fontColor([this.accentHex])
                }
              }

              Column({ space: 2 }) {
                Text(this.minimizedState()!.title)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(mpPrimaryText(this.isDark))
                  .maxLines(1)
                if ((this.minimizedState()!.subtitle || this.minimizedState()!.statusText).length > 0) {
                  Text(this.minimizedState()!.subtitle || this.minimizedState()!.statusText)
                    .fontSize(11.5)
                    .fontColor(mpSecondaryText(this.isDark))
                    .maxLines(1)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                  .fontSize(14)
                  .fontColor([this.accentHex])
              }
              .width(30)
              .height(30)
              .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, '22'))
              .onClick(() => {
                this.tapHaptic();
                HarmonyPluginCapsuleManager.shared().restoreFullWindow();
              })
            }
            .width('100%')

            if (this.minimizedState()!.actions.length > 0) {
              Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
                ForEach(this.minimizedState()!.actions, (act: HarmonyPluginCapsuleAction) => {
                  NativeAdaptivePill({
                    title: act.label,
                    selected: act.active,
                    onTap: () => {
                      this.tapHaptic();
                      HarmonyPluginCapsuleManager.shared().dispatchAction(act.id);
                    }
                  })
                }, (act: HarmonyPluginCapsuleAction) => `${act.id}_${act.active}`)
              }
            }
          }
          .padding(14)
          .width(268)
          .borderRadius(20)
          .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
          .border({ width: 0.8, color: HarmonyThemeColors.divider(this.isDark) })
          .shadow({ radius: 18, color: '#38000000', offsetY: 6 })
        }

        // 悬浮胶囊主体
        Row({ space: 8 }) {
          if (this.minimizedState()!.iconUrl.length > 0) {
            MpRemoteImage({
              src: this.minimizedState()!.iconUrl,
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
                .fontSize(14)
                .fontColor([this.accentHex])
            }
          }

          Column({ space: 1 }) {
            Text(this.minimizedState()!.title)
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpPrimaryText(this.isDark))
              .maxLines(1)
              .constraintSize({ maxWidth: 156 })
            if ((this.minimizedState()!.statusText || this.minimizedState()!.subtitle).length > 0) {
              Text(this.minimizedState()!.statusText || this.minimizedState()!.subtitle)
                .fontSize(10.5)
                .fontColor(mpSecondaryText(this.isDark))
                .maxLines(1)
                .constraintSize({ maxWidth: 156 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .onClick(() => {
            this.tapHaptic();
            const st = this.minimizedState();
            if (!st) {
              return;
            }
            if (this.isMiniMode(st)) {
              this.miniExpanded = !this.miniExpanded;
            } else {
              HarmonyPluginCapsuleManager.shared().restoreFullWindow();
            }
          })

          if (this.isMiniMode(this.minimizedState()!)) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
                .fontSize(12)
                .fontColor([this.accentHex])
            }
            .width(24)
            .height(24)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.tapHaptic();
              HarmonyPluginCapsuleManager.shared().restoreFullWindow();
            })
          }

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(12)
              .fontColor([mpSecondaryText(this.isDark)])
          }
          .width(24)
          .height(24)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.tapHaptic();
            HarmonyPluginCapsuleManager.shared().closeAndDestroy();
          })
        }
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(999)
        .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
        .border({ width: 1, color: HarmonyAppearanceStore.withAlpha(this.accentHex, '55') })
        .shadow({ radius: 14, color: '#33000000', offsetY: 4 })
      }
      .alignItems(HorizontalAlign.End)
      .offset({ x: this.offsetX, y: this.offsetY })
      .gesture(
        PanGesture({ distance: 4 })
          .onActionStart(() => {
            this.dragStartX = this.offsetX;
            this.dragStartY = this.offsetY;
          })
          .onActionUpdate((ev?: GestureEvent) => {
            if (ev) {
              this.offsetX = this.dragStartX + ev.offsetX;
              this.offsetY = this.dragStartY + ev.offsetY;
            }
          })
      )
    }
  }
}
