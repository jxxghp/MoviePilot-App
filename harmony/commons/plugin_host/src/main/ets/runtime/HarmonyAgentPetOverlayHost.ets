import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import {
  MoviePilotRepository,
  MpAgentPetDeclaration,
  MpAgentPetSelection,
  RustCoreBridge
} from '@moviepilot/core_rust_bridge';
import {
  CinematicPanel,
  FloatingAiMascotButton,
  HarmonyAppearanceStore,
  HarmonySheetHeader,
  HarmonyThemeColors,
  NativeAdaptiveBadge,
  mpPrimaryText,
  mpSecondaryText
} from '@moviepilot/design_system';
import {
  HarmonyPluginBridgeJsProxy,
  HarmonyPluginHostBridgeV2
} from './HarmonyPluginHostBridgeV2';
import { HarmonyLocalPluginShellView } from './HarmonyLocalPluginShellView';
import { HarmonyPluginRemoteCache } from './HarmonyPluginRemoteCache';
import { buildHarmonyPluginVisualTokens } from './HarmonyPluginVisualTokens';

/** 描述插件助手在 ArkWeb 舞台中的交互锚点矩形。 */
export interface HarmonyPetAnchorRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * 鸿蒙全局会话作用域 Agent 助手形象管理器：
 * - 读写 `GET /api/v1/plugin/agent_pets`、`GET/POST /api/v1/user/config/AgentPet` 与全局 `AI_AGENT_PET`；
 * - 通过 `AppStorage` 键 `mp_agent_pet_rev` / `mp_agent_pet_name` 向全屏悬浮层与聊天页广播变更；
 * - 任意加载失败或超时自动记录并退回原生内置机器人。
 */
export class HarmonyAgentPetManager {
  static readonly KEY_REV = 'mp_agent_pet_rev';
  static readonly KEY_NAME = 'mp_agent_pet_name';

  private static instance: HarmonyAgentPetManager | null = null;
  private scopeKey: string = '';
  private declarations: MpAgentPetDeclaration[] = [];
  private selection: MpAgentPetSelection = { kind: 'default', pluginId: '', key: '' };
  private adminDefaultPetId: string = '';
  private failedIds: Set<string> = new Set<string>();
  private loading: boolean = false;
  private saving: boolean = false;
  private lastFailure: string = '';

  static shared(): HarmonyAgentPetManager {
    if (!HarmonyAgentPetManager.instance) {
      HarmonyAgentPetManager.instance = new HarmonyAgentPetManager();
    }
    return HarmonyAgentPetManager.instance;
  }

  /** 递增状态版本以通知 ArkUI 刷新关联视图。 */
  private bump(): void {
    const cur = AppStorage.get<number>(HarmonyAgentPetManager.KEY_REV) ?? 0;
    AppStorage.setOrCreate(HarmonyAgentPetManager.KEY_REV, cur + 1);
    const eff = this.effectivePet();
    AppStorage.setOrCreate(HarmonyAgentPetManager.KEY_NAME, eff ? eff.name : '');
  }

  /** 返回当前可选的插件助手声明。 */
  getDeclarations(): MpAgentPetDeclaration[] {
    return this.declarations;
  }

  /** 返回用户当前持久化的助手选择。 */
  getSelection(): MpAgentPetSelection {
    return this.selection;
  }

  /** 返回管理员配置的默认助手 ID。 */
  getAdminDefaultPetId(): string {
    return this.adminDefaultPetId;
  }

  /** 解析管理员默认助手对应的声明。 */
  getAdminDefaultDeclaration(): MpAgentPetDeclaration | null {
    const id = this.adminDefaultPetId.trim();
    if (id.length === 0) { return null; }
    for (let i = 0; i < this.declarations.length; i++) {
      if (this.declarations[i].id === id) {
        return this.declarations[i];
      }
    }
    return null;
  }

  /** 报告助手声明是否正在加载。 */
  isLoading(): boolean {
    return this.loading;
  }

  /** 报告用户选择是否正在保存。 */
  isSaving(): boolean {
    return this.saving;
  }

  /** 返回最近一次加载或保存失败提示。 */
  getLastFailure(): string {
    return this.lastFailure;
  }

  /** 判断指定插件助手是否已被标记为失败。 */
  isFailed(petId: string): boolean {
    return this.failedIds.has(petId);
  }

  /** 解析当前有效助手；失败或内置选择时返回空值。 */
  effectivePet(): MpAgentPetDeclaration | null {
    let requested = '';
    if (this.selection.kind === 'builtin') {
      return null;
    } else if (this.selection.kind === 'plugin') {
      requested = `${this.selection.pluginId}:${this.selection.key}`;
    } else {
      requested = this.adminDefaultPetId.trim();
    }
    if (requested.length === 0 || this.failedIds.has(requested)) {
      return null;
    }
    for (let i = 0; i < this.declarations.length; i++) {
      if (this.declarations[i].id === requested) {
        return this.declarations[i];
      }
    }
    return null;
  }

  /** 清除账号作用域缓存并恢复默认状态。 */
  reset(): void {
    this.scopeKey = '';
    this.declarations = [];
    this.selection = { kind: 'default', pluginId: '', key: '' };
    this.adminDefaultPetId = '';
    this.failedIds.clear();
    this.loading = false;
    this.saving = false;
    this.lastFailure = '';
    this.bump();
  }

  /** 确保指定登录账号的助手状态已加载。 */
  async ensureLoaded(accountScopeKey: string): Promise<void> {
    if (accountScopeKey.length === 0) { return; }
    if (this.scopeKey === accountScopeKey && (this.declarations.length > 0 || this.loading)) {
      return;
    }
    if (this.scopeKey !== accountScopeKey) {
      this.reset();
      this.scopeKey = accountScopeKey;
    }
    await this.refresh(false);
  }

  /** 并发刷新声明、用户选择和管理员默认项。 */
  async refresh(clearFailures: boolean = false): Promise<void> {
    if (clearFailures) {
      this.failedIds.clear();
      this.lastFailure = '';
    }
    this.loading = true;
    this.bump();
    const repo = MoviePilotRepository.shared();
    try {
      const results = await Promise.all([
        repo.fetchAgentPets(),
        repo.fetchAgentPetSelection(),
        repo.fetchGlobalAgentPetDefault()
      ]);
      const nextPets = results[0] as MpAgentPetDeclaration[];
      const oldMap: Map<string, MpAgentPetDeclaration> = new Map<string, MpAgentPetDeclaration>();
      for (let i = 0; i < this.declarations.length; i++) {
        oldMap.set(this.declarations[i].id, this.declarations[i]);
      }
      this.declarations = nextPets;
      for (let i = 0; i < nextPets.length; i++) {
        const prev = oldMap.get(nextPets[i].id);
        if (prev && (prev.pluginVersion !== nextPets[i].pluginVersion || prev.remoteUrl !== nextPets[i].remoteUrl)) {
          this.failedIds.delete(nextPets[i].id);
        }
      }
      this.selection = results[1] as MpAgentPetSelection;
      this.adminDefaultPetId = results[2] as string;
    } catch {
      // keep previous snapshot
    }
    this.loading = false;
    this.bump();
  }

  /** 保存助手选择并同步更新当前状态。 */
  async select(sel: MpAgentPetSelection): Promise<boolean> {
    if (this.saving) { return false; }
    this.saving = true;
    this.lastFailure = '';
    this.bump();
    let succeeded = false;
    try {
      const ok = await MoviePilotRepository.shared().saveAgentPetSelection(sel);
      if (ok) {
        this.selection = sel;
        if (sel.kind === 'plugin') {
          this.failedIds.delete(`${sel.pluginId}:${sel.key}`);
        }
        succeeded = true;
      } else {
        this.lastFailure = '保存助手形象失败，请稍后重试。';
      }
    } catch {
      this.lastFailure = '保存助手形象失败，请稍后重试。';
    }
    this.saving = false;
    this.bump();
    return succeeded;
  }

  /** 记录插件助手故障并提供内置助手回退提示。 */
  markFailed(pet: MpAgentPetDeclaration, reason: string): void {
    this.failedIds.add(pet.id);
    this.lastFailure = `${pet.name} 加载失败（${reason}），已回退内置机器人。`;
    this.bump();
  }
}

/**
 * 鸿蒙端专用于运行 Web AgentPets 插件（`stage` / `renderer`）的全界面透明 ArkWeb 承载层：
 * - `stage` 模式通过 ArkUI `.responseRegion(...)` 按 `pet.setBubbleAnchor(rect)` 精确圈定触摸热区，
 *   宠物外部空白区域 100% 原生穿透给下层所有 ArkUI 页面与滚动列表；拖拽时通过 `setInteracting(true)` 暂扩全屏防丢手势；
 * - 加载超时（10s）或运行出错时自动回退原生高质感机器人。
 */
@Component
struct HarmonyPluginAgentPetWebLayer {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) @Watch('onVisualChanged') isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) @Watch('onVisualChanged') paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) @Watch('onVisualChanged') accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) @Watch('onVisualChanged') pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_LOCALE) locale: string = 'zh-CN';
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_WIDTH_VP) @Watch('onStatePropsChanged') windowWidthVp: number = 412;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) @Watch('onStatePropsChanged') windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_TOP_VP) @Watch('onStatePropsChanged') safeTopVp: number = 38;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) @Watch('onStatePropsChanged') safeBottomVp: number = 16;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_LEFT_VP) safeLeftVp: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_RIGHT_VP) safeRightVp: number = 0;

  @Prop petId: string = '';
  @Prop pluginId: string = '';
  @Prop sourcePluginId: string = '';
  @Prop pluginName: string = '';
  @Prop pluginVersion: string = '';
  @Prop petKey: string = '';
  @Prop petName: string = '';
  @Prop petMode: string = 'stage';
  @Prop petComponent: string = 'AgentPet';
  @Prop petBubbles: string = 'host';
  @Prop remoteUrl: string = '';
  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @Prop @Watch('onStatePropsChanged') isVisible: boolean = true;
  @Prop @Watch('onStatePropsChanged') panelOpen: boolean = false;
  @Prop @Watch('onStatePropsChanged') dockVisible: boolean = true;
  @Prop @Watch('onStatePropsChanged') isWideLayout: boolean = false;
  @Prop miniMusicVisible: boolean = false;

  onOpenAgent: (draft: string) => void = () => {};
  onCloseAgent: () => void = () => {};
  onFailed: (reason: string) => void = () => {};

  @State private isMounted: boolean = false;
  @State private anchorRect: HarmonyPetAnchorRect | null = null;
  @State private isInteracting: boolean = false;
  @State private bubbleText: string = '';
  @State private dragDx: number = 0;
  @State private dragDy: number = 0;

  private lastValidAnchorRect: HarmonyPetAnchorRect | null = null;

  private dragStartDx: number = 0;
  private dragStartDy: number = 0;
  private webController: webview.WebviewController = new webview.WebviewController();
  private bridge: HarmonyPluginHostBridgeV2 | null = null;
  private isShellReady: boolean = false;
  private pendingMountJson: string = '';
  private loadTimeoutId: number = -1;
  private bubbleTimerId: number = -1;

  /** 初始化页面可见期间所需的助手数据和宿主桥。 */
  aboutToAppear(): void {
    this.bridge = new HarmonyPluginHostBridgeV2(
      this.webController,
      this.serverUrl,
      this.authToken,
      {
        onShellReady: () => {
          this.isShellReady = true;
          if (this.pendingMountJson.length > 0 && this.bridge) {
            this.bridge.sendToWeb('plugin.mount', this.pendingMountJson);
            this.pendingMountJson = '';
            this.bridge.sendAgentState(JSON.stringify(this.buildStateObj()));
          }
        },
        onPluginMounted: () => {
          this.clearLoadTimer();
          this.isMounted = true;
          if (this.bridge) {
            this.bridge.sendAgentState(JSON.stringify(this.buildStateObj()));
          }
        },
        onPluginError: (_stage: string, msg: string) => {
          this.clearLoadTimer();
          this.isMounted = false;
          this.onFailed(msg || '插件组件运行异常');
        },
        onPluginClose: () => {},
        onNavBackResult: () => {},
        onHeaderUpdate: () => {},
        onToast: () => {},
        onConfirm: () => {},
        onOpenRoute: () => {},
        onAgentOpen: (draft: string) => {
          setTimeout(() => {
            this.isInteracting = false;
            this.onOpenAgent(draft);
          }, 0);
        },
        onAgentClose: () => {
          setTimeout(() => {
            this.onCloseAgent();
          }, 0);
        },
        onAgentPetAnchor: (x: number, y: number, w: number, h: number) => {
          const rect: HarmonyPetAnchorRect = { x: x, y: y, width: w, height: h };
          if (w > 0 && h > 0) {
            this.lastValidAnchorRect = rect;
          }
          this.anchorRect = rect;
        },
        onAgentPetAnchorCleared: () => {
          this.anchorRect = this.lastValidAnchorRect;
        },
        onAgentPetInteracting: (active: boolean) => {
          this.isInteracting = active;
        },
        onAgentPetSay: (text: string, durationMs: number) => {
          this.showBubble(text, durationMs);
        }
      },
      () => this.getAbilityContext()
    );
        this.dragDx = AppStorage.get<number>('mp_agent_pet_dx') ?? 0;
        this.dragDy = AppStorage.get<number>('mp_agent_pet_dy') ?? 0;
        this.prepareMount();
  }

  /** 释放页面退出后不再需要的计时器与 Web 资源。 */
  aboutToDisappear(): void {
    this.clearLoadTimer();
    if (this.bubbleTimerId !== -1) {
      clearTimeout(this.bubbleTimerId);
      this.bubbleTimerId = -1;
    }
    this.bridge?.sendUnmount();
    this.bridge?.abortAllInFlight();
    this.bridge?.cleanupNativeCapabilities();
  }

  /** 取消插件远程入口加载超时计时器。 */
  private clearLoadTimer(): void {
    if (this.loadTimeoutId !== -1) {
      clearTimeout(this.loadTimeoutId);
      this.loadTimeoutId = -1;
    }
  }

  /** 显示助手回复气泡并安排定时收起。 */
  private showBubble(text: string, durationMs: number): void {
    if (this.bubbleTimerId !== -1) {
      clearTimeout(this.bubbleTimerId);
    }
    this.bubbleText = text;
    this.bubbleTimerId = setTimeout(() => {
      this.bubbleText = '';
      this.bubbleTimerId = -1;
    }, durationMs);
  }

  /** 从当前页面上下文安全获取 UIAbility 上下文。 */
  private getAbilityContext(): common.UIAbilityContext | null {
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch {
      return null;
    }
  }

  /** 在主题令牌变化后通知插件刷新外观。 */
  onVisualChanged(): void {
    const tokens = buildHarmonyPluginVisualTokens(this.isDark, this.paletteId, this.accentHex, this.pureBlack);
    this.bridge?.sendVisualTokens(tokens);
    this.onStatePropsChanged();
  }

  /** 在 Agent 状态属性变化后推送最新快照。 */
  onStatePropsChanged(): void {
    if (this.isShellReady && this.bridge) {
      this.bridge.sendAgentState(JSON.stringify(this.buildStateObj()));
    }
  }

  /** 构造传递给插件的 Agent 状态对象。 */
  private buildStateObj(): Record<string, Object> {
    const visibleNow = this.isVisible && !this.panelOpen;
    const stateObj: Record<string, Object> = {
      'available': true,
      'panelOpen': this.panelOpen,
      'thinking': false,
      'phase': 'idle',
      'pageVisible': visibleNow,
      'motionAllowed': visibleNow,
      'reducedMotion': !visibleNow,
      'theme': this.isDark ? 'dark' : 'light',
      'isMobile': this.windowWidthVp < 960,
      'viewport': {
        'width': this.windowWidthVp,
        'height': this.windowHeightVp,
        'keyboardInset': 0,
        'safeArea': {
          'top': this.safeTopVp,
          'right': this.safeRightVp,
          'bottom': this.safeBottomVp,
          'left': this.safeLeftVp
        } as Record<string, Object>
      } as Record<string, Object>
    };
    if (this.dockVisible && !this.isWideLayout) {
      const dockH = 60;
      const dockY = Math.max(0, this.windowHeightVp - Math.max(10, this.safeBottomVp) - dockH - 6);
      const dockW = Math.min(Math.max(this.windowWidthVp - 32, 220), 420);
      const dockX = (this.windowWidthVp - dockW) * 0.5;
      const bounds: Record<string, Object> = {
        'x': dockX,
        'y': dockY,
        'width': dockW,
        'height': dockH
      };
      stateObj['dock'] = {
        'bounds': bounds,
        'items': [bounds]
      } as Record<string, Object>;
    }
    if (this.petMode !== 'stage') {
      stateObj['motionActive'] = visibleNow;
      stateObj['intent'] = 'idle';
    }
    return stateObj;
  }

  /** 准备远程插件入口、请求代理和 ArkWeb 挂载参数。 */
  private prepareMount(): void {
    const rawUrl = this.remoteUrl.trim();
    if (rawUrl.length === 0) {
      this.onFailed('缺少联邦入口地址');
      return;
    }
    const plan = RustCoreBridge.normalizePluginRemoteEntry(
      this.sourcePluginId || this.pluginId,
      this.pluginVersion,
      rawUrl
    );
    if (!plan) {
      this.onFailed('联邦入口路径无效');
      return;
    }
    const virtualEntryUrl = `${HarmonyLocalPluginShellView.VIRTUAL_ORIGIN}${plan.virtual_entry_path}`;
    const tokens = buildHarmonyPluginVisualTokens(this.isDark, this.paletteId, this.accentHex, this.pureBlack);
    const mountObj: Record<string, Object> = {
      'mountId': `ohos_pet_${Date.now()}`,
      'pluginId': this.pluginId,
      'sourcePluginId': this.sourcePluginId || this.pluginId,
      'pluginName': this.pluginName || this.pluginId,
      'pluginVersion': this.pluginVersion,
      'surface': 'agentPet',
      'exposeComponent': this.petComponent || 'AgentPet',
      'agentPet': {
        'key': this.petKey,
        'mode': this.petMode,
        'bubbles': this.petBubbles || 'host',
        'name': this.petName
      } as Record<string, Object>,
      'agentHostState': this.buildStateObj(),
      'remoteEntryUrl': virtualEntryUrl,
      'locale': this.locale || 'zh-CN',
      'visualTokens': tokens as Object,
      'safeArea': {
        'top': this.safeTopVp,
        'bottom': this.safeBottomVp,
        'left': this.safeLeftVp,
        'right': this.safeRightVp
      } as Record<string, Object>,
      'user': {
        'id': 1,
        'superUser': this.isSuperuser,
        'userName': this.userName,
        'avatar': this.userAvatar,
        'level': this.isSuperuser ? 2 : 1,
        'permissions': {
          'discovery': true,
          'search': true,
          'subscribe': true,
          'manage': this.isSuperuser,
          'admin': this.isSuperuser
        } as Record<string, Object>
      } as Record<string, Object>
    };
    this.pendingMountJson = JSON.stringify(mountObj);
    if (this.isShellReady && this.bridge) {
      this.bridge.sendToWeb('plugin.mount', this.pendingMountJson);
      this.pendingMountJson = '';
    }
    this.clearLoadTimer();
    this.loadTimeoutId = setTimeout(() => {
      this.loadTimeoutId = -1;
      if (!this.isMounted) {
        this.onFailed('加载超时');
      }
    }, 10000);
  }

  /** 按宿主安全策略处理插件 Web 请求。 */
  private handleInterceptRequest(requestUrl: string, method: string): WebResourceResponse | null {
    const prefix = HarmonyLocalPluginShellView.VIRTUAL_ORIGIN;
    if (!requestUrl.startsWith(prefix)) {
      return null;
    }
    const pathAndQuery = requestUrl.substring(prefix.length);
    const pathOnly = pathAndQuery.split('#')[0].split('?')[0];
    if (method.toUpperCase() === 'OPTIONS') {
      const resp = new WebResourceResponse();
      resp.setResponseCode(204);
      resp.setReasonMessage('No Content');
      resp.setResponseMimeType('text/plain');
      resp.setResponseEncoding('utf-8');
      resp.setResponseHeader([
        { headerKey: 'Access-Control-Allow-Origin', headerValue: prefix },
        { headerKey: 'Access-Control-Allow-Methods', headerValue: 'GET, HEAD, OPTIONS' }
      ]);
      resp.setResponseIsReady(true);
      return resp;
    }
    if (pathOnly.startsWith('/shell/')) {
      return this.serveShellRawfile(pathOnly);
    }
    if (pathOnly.startsWith('/plugin-remote/')) {
      return this.serveRemoteAsset(pathOnly);
    }
    if (pathOnly.startsWith('/api/v1/') && (method.toUpperCase() === 'GET' || method.toUpperCase() === 'HEAD')) {
      return this.servePassiveApi(pathAndQuery);
    }
    return this.makeError(404, 'Not Found');
  }

  /** 从本地插件壳资源目录提供静态资源响应。 */
  private serveShellRawfile(virtualPath: string): WebResourceResponse {
    const relPath = RustCoreBridge.validatePluginShellAssetPath(virtualPath);
    const ctx = this.getAbilityContext();
    if (!relPath || !ctx) {
      return this.makeError(400, 'Invalid shell asset');
    }
    try {
      const bytes = ctx.resourceManager.getRawFileContentSync(`plugin_shell/${relPath}`);
      const resp = new WebResourceResponse();
      resp.setResponseData(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      resp.setResponseMimeType(HarmonyPluginRemoteCache.guessMimeType(relPath));
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(200);
      resp.setReasonMessage('OK');
      resp.setResponseHeader([
        { headerKey: 'Access-Control-Allow-Origin', headerValue: HarmonyLocalPluginShellView.VIRTUAL_ORIGIN },
        { headerKey: 'Cache-Control', headerValue: 'no-cache' }
      ]);
      resp.setResponseIsReady(true);
      return resp;
    } catch {
      return this.makeError(404, 'Shell asset missing');
    }
  }

  /** 代理当前插件声明允许访问的远程资源。 */
  private serveRemoteAsset(virtualPath: string): WebResourceResponse {
    const target = RustCoreBridge.resolvePluginRemoteUpstream(virtualPath);
    if (!target) {
      return this.makeError(400, 'Invalid remote path');
    }
    const ctx = this.getAbilityContext();
    const cacheDir = ctx ? ctx.cacheDir : '';
    const origin = this.serverUrl.replace(/\/+$/, '');
    const cached = HarmonyPluginRemoteCache.readSync(cacheDir, origin, target.plugin_id, target.version_tag, target.asset_rel_path);
    if (cached) {
      const resp = new WebResourceResponse();
      resp.setResponseData(cached.buffer);
      resp.setResponseMimeType(cached.mimeType);
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(200);
      resp.setReasonMessage('OK');
      resp.setResponseHeader([
        { headerKey: 'Access-Control-Allow-Origin', headerValue: HarmonyLocalPluginShellView.VIRTUAL_ORIGIN },
        { headerKey: 'Cache-Control', headerValue: 'public, max-age=31536000, immutable' }
      ]);
      resp.setResponseIsReady(true);
      return resp;
    }
    const resp = new WebResourceResponse();
    resp.setResponseIsReady(false);
    const req = http.createHttp();
    req.request(`${origin}${target.upstream_api_path}`, {
      method: http.RequestMethod.GET,
      header: { 'Authorization': `Bearer ${this.authToken}`, 'X-MoviePilot-Locale': this.locale || 'zh-CN' },
      connectTimeout: 15000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }).then((httpResp: http.HttpResponse) => {
      req.destroy();
      const buf = httpResp.result instanceof ArrayBuffer ? httpResp.result : new ArrayBuffer(0);
      const mime = HarmonyPluginRemoteCache.guessMimeType(target.asset_rel_path);
      if (httpResp.responseCode >= 200 && httpResp.responseCode < 300 && buf.byteLength > 0) {
        HarmonyPluginRemoteCache.writeSync(cacheDir, origin, target.plugin_id, target.version_tag, target.asset_rel_path, buf);
      }
      resp.setResponseData(buf);
      resp.setResponseMimeType(mime);
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(httpResp.responseCode);
      resp.setReasonMessage('OK');
      resp.setResponseHeader([
        { headerKey: 'Access-Control-Allow-Origin', headerValue: HarmonyLocalPluginShellView.VIRTUAL_ORIGIN }
      ]);
      resp.setResponseIsReady(true);
    }).catch(() => {
      try { req.destroy(); } catch { /* ignore */ }
      resp.setResponseData('Upstream failed');
      resp.setResponseMimeType('text/plain');
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(502);
      resp.setReasonMessage('Bad Gateway');
      resp.setResponseIsReady(true);
    });
    return resp;
  }

  /** 转发插件助手所需的只读服务 API。 */
  private servePassiveApi(pathWithQuery: string): WebResourceResponse {
    const normalized = RustCoreBridge.validatePluginApiPath(pathWithQuery);
    if (!normalized) {
      return this.makeError(400, 'Invalid API path');
    }
    const resp = new WebResourceResponse();
    resp.setResponseIsReady(false);
    const origin = this.serverUrl.replace(/\/+$/, '');
    const req = http.createHttp();
    req.request(`${origin}${normalized}`, {
      method: http.RequestMethod.GET,
      header: { 'Authorization': `Bearer ${this.authToken}` },
      connectTimeout: 15000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }).then((httpResp: http.HttpResponse) => {
      req.destroy();
      const buf = httpResp.result instanceof ArrayBuffer ? httpResp.result : new ArrayBuffer(0);
      resp.setResponseData(buf);
      resp.setResponseMimeType(HarmonyPluginRemoteCache.guessMimeType(normalized));
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(httpResp.responseCode);
      resp.setReasonMessage('OK');
      resp.setResponseHeader([
        { headerKey: 'Access-Control-Allow-Origin', headerValue: HarmonyLocalPluginShellView.VIRTUAL_ORIGIN }
      ]);
      resp.setResponseIsReady(true);
    }).catch(() => {
      try { req.destroy(); } catch { /* ignore */ }
      resp.setResponseData('Proxy failed');
      resp.setResponseMimeType('text/plain');
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(502);
      resp.setReasonMessage('Bad Gateway');
      resp.setResponseIsReady(true);
    });
    return resp;
  }

  /** 生成符合 WebResourceResponse 结构的错误响应。 */
  private makeError(code: number, message: string): WebResourceResponse {
    const resp = new WebResourceResponse();
    resp.setResponseData(message);
    resp.setResponseMimeType('text/plain');
    resp.setResponseEncoding('utf-8');
    resp.setResponseCode(code);
    resp.setReasonMessage(message);
    resp.setResponseIsReady(true);
    return resp;
  }

  /** 计算需要由插件舞台接收触摸的屏幕区域。 */
  private stageResponseRegions(): Array<Rectangle> {
    if (!this.isVisible || this.panelOpen) {
      return [{ x: 0, y: 0, width: 0, height: 0 }];
    }
    if (this.isInteracting) {
      return [{ x: 0, y: 0, width: '100%', height: '100%' }];
    }
    if (this.anchorRect && this.anchorRect.width > 0 && this.anchorRect.height > 0) {
      return [{
        x: Math.max(0, this.anchorRect.x - 24),
        y: Math.max(0, this.anchorRect.y - 24),
        width: this.anchorRect.width + 48,
        height: this.anchorRect.height + 48
      }];
    }
    return [{ x: 0, y: 0, width: 0, height: 0 }];
  }

  /** 构建插件 Agent 宠物的 ArkWeb 舞台和渲染层。 */
  build() {
    if (this.petMode === 'stage') {
      Stack({ alignContent: Alignment.TopStart }) {
        Web({
          src: HarmonyLocalPluginShellView.SHELL_ENTRY_URL,
          controller: this.webController
        })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .metaViewport(true)
          .mediaPlayGestureAccess(false)
          .backgroundColor(Color.Transparent)
          .opacity(this.isMounted ? 1.0 : 0.0)
          .responseRegion(this.stageResponseRegions())
          .javaScriptProxy({
            object: this.bridge ? this.bridge.jsProxy : new HarmonyPluginBridgeJsProxy(() => {}),
            name: HarmonyPluginHostBridgeV2.PROXY_NAME,
            methodList: ['postMessage'],
            controller: this.webController
          })
          .onInterceptRequest((ev) => {
            if (!ev || !ev.request) { return null; }
            return this.handleInterceptRequest(ev.request.getRequestUrl(), ev.request.getRequestMethod());
          })
          .onRenderExited(() => {
            this.isMounted = false;
            this.onFailed('渲染进程中断');
          })

        if (this.isVisible && !this.panelOpen && this.bubbleText.length > 0 && this.anchorRect) {
          Text(this.bubbleText)
            .fontSize(12)
            .fontColor(mpPrimaryText(this.isDark))
            .maxLines(2)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(14)
            .backgroundColor(HarmonyThemeColors.cardElevated(this.isDark))
            .border({ width: 0.7, color: HarmonyThemeColors.borderSubtle(this.isDark), radius: 14 })
            .constraintSize({ maxWidth: 210 })
            .position({
              x: Math.max(12, Math.min(this.windowWidthVp - 220, this.anchorRect.x + this.anchorRect.width * 0.5 - 100)),
              y: Math.max(this.safeTopVp + 12, this.anchorRect.y - 44)
            })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Web({
          src: HarmonyLocalPluginShellView.SHELL_ENTRY_URL,
          controller: this.webController
        })
          .width(86)
          .height(96)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .metaViewport(true)
          .mediaPlayGestureAccess(false)
          .backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
          .opacity(this.isVisible && !this.panelOpen && this.isMounted ? 1.0 : (this.isMounted ? 0.015 : 0.0))
          .javaScriptProxy({
            object: this.bridge ? this.bridge.jsProxy : new HarmonyPluginBridgeJsProxy(() => {}),
            name: HarmonyPluginHostBridgeV2.PROXY_NAME,
            methodList: ['postMessage'],
            controller: this.webController
          })
          .onInterceptRequest((ev) => {
            if (!ev || !ev.request) { return null; }
            return this.handleInterceptRequest(ev.request.getRequestUrl(), ev.request.getRequestMethod());
          })
          .onRenderExited(() => {
            this.isMounted = false;
            this.onFailed('渲染进程中断');
          })
      }
      .width(86)
      .height(96)
      .position({
        right: 12,
        bottom: (this.dockVisible && !this.isWideLayout ? 86 : 24) + Math.max(10, this.safeBottomVp) + (this.miniMusicVisible ? 68 : 0)
      })
      .translate({ x: this.dragDx, y: this.dragDy })
      .hitTestBehavior(!this.isVisible || this.panelOpen ? HitTestMode.None : HitTestMode.Default)
      .onClick(() => {
        if (this.isVisible && !this.panelOpen) {
          this.onOpenAgent('');
        }
      })
      .gesture(
        PanGesture({ distance: 4 })
          .onActionStart(() => {
            this.dragStartDx = this.dragDx;
            this.dragStartDy = this.dragDy;
          })
          .onActionUpdate((ev: GestureEvent) => {
            this.dragDx = this.dragStartDx + ev.offsetX;
            this.dragDy = this.dragStartDy + ev.offsetY;
          })
          .onActionEnd(() => {
            AppStorage.setOrCreate('mp_agent_pet_dx', this.dragDx);
            AppStorage.setOrCreate('mp_agent_pet_dy', this.dragDy);
          })
      )
    }
  }
}

/**
 * 鸿蒙全界面 Agent 助手形象统一宿主层（挂在 `Index` 根层，覆盖所有 Tab 与二级子页面）。
 */
@Component
export struct HarmonyAgentPetOverlayHost {
  @StorageProp(HarmonyAgentPetManager.KEY_REV) petRev: number = 0;
  @StorageLink(HarmonyAppearanceStore.KEY_WINDOW_HEIGHT_VP) windowHeightVp: number = 892;
  @StorageLink(HarmonyAppearanceStore.KEY_SAFE_BOTTOM_VP) safeBottomVp: number = 16;

  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @Prop isVisible: boolean = true;
  @Prop panelOpen: boolean = false;
  @Prop dockVisible: boolean = true;
  @Prop isWideLayout: boolean = false;
  @Prop miniMusicVisible: boolean = false;

  onOpenAgent: (draft: string) => void = () => {};
  onCloseAgent: () => void = () => {};

  /** 初始化页面可见期间所需的助手数据和宿主桥。 */
  aboutToAppear(): void {
    const scopeKey = `${this.serverUrl}|${this.userName}`;
    HarmonyAgentPetManager.shared().ensureLoaded(scopeKey);
  }

  /** 解析当前页面实际要展示的插件助手。 */
  private activePet(): MpAgentPetDeclaration | null {
    // 读取 petRev 以建立 ArkUI 响应式依赖
    const _rev = this.petRev;
    if (_rev < 0) { return null; }
    return HarmonyAgentPetManager.shared().effectivePet();
  }

  /** 构建插件 Agent 宠物的 ArkWeb 舞台和渲染层。 */
  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.activePet() !== null) {
        HarmonyPluginAgentPetWebLayer({
          petId: this.activePet()!.id,
          pluginId: this.activePet()!.pluginId,
          sourcePluginId: this.activePet()!.sourcePluginId,
          pluginName: this.activePet()!.pluginName,
          pluginVersion: this.activePet()!.pluginVersion,
          petKey: this.activePet()!.key,
          petName: this.activePet()!.name,
          petMode: this.activePet()!.mode,
          petComponent: this.activePet()!.component,
          petBubbles: this.activePet()!.bubbles,
          remoteUrl: this.activePet()!.remoteUrl,
          serverUrl: this.serverUrl,
          authToken: this.authToken,
          userName: this.userName,
          userAvatar: this.userAvatar,
          isSuperuser: this.isSuperuser,
          isVisible: this.isVisible,
          panelOpen: this.panelOpen,
          dockVisible: this.dockVisible,
          isWideLayout: this.isWideLayout,
          miniMusicVisible: this.miniMusicVisible,
          onOpenAgent: (draft: string) => this.onOpenAgent(draft),
          onCloseAgent: () => this.onCloseAgent(),
          onFailed: (reason: string) => {
            const p = this.activePet();
            if (p) {
              HarmonyAgentPetManager.shared().markFailed(p, reason);
            }
          }
        })
      } else if (this.isVisible && !this.panelOpen) {
        FloatingAiMascotButton({
          miniMusicVisible: this.miniMusicVisible,
          baseRight: this.isWideLayout ? 22 : 14,
          baseBottom: this.isWideLayout
            ? Math.max(20, this.safeBottomVp + 10)
            : (this.dockVisible
              ? ((this.windowHeightVp > 0 && this.windowHeightVp < 480 ? 70 : 80) + Math.max(10, this.safeBottomVp))
              : Math.max(20, this.safeBottomVp + 10)),
          motionActive: true,
          onTap: () => this.onOpenAgent('')
        })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

/** 鸿蒙原生「更换助手形象」底部弹窗（选中后点击右上角「保存」持久化并自动关闭，与 Web/iOS/Android 实时互通）。 */
@Component
export struct HarmonyAgentPetPickerSheet {
  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) accentHex: string = '#317AF7';
  @StorageProp(HarmonyAgentPetManager.KEY_REV) petRev: number = 0;
  @State private draftKind: string = 'default';
  @State private draftPluginId: string = '';
  @State private draftKey: string = '';
  @State private hasEditedDraft: boolean = false;
  onClose: () => void = () => {};

  /** 初始化页面可见期间所需的助手数据和宿主桥。 */
  aboutToAppear(): void {
    const cur = HarmonyAgentPetManager.shared().getSelection();
    this.draftKind = cur.kind;
    this.draftPluginId = cur.pluginId;
    this.draftKey = cur.key;
    HarmonyAgentPetManager.shared().refresh(false).then(() => {
      if (!this.hasEditedDraft) {
        const latest = HarmonyAgentPetManager.shared().getSelection();
        this.draftKind = latest.kind;
        this.draftPluginId = latest.pluginId;
        this.draftKey = latest.key;
      }
    });
  }

  /** 返回选择弹层使用的共享助手管理器。 */
  private mgr(): HarmonyAgentPetManager {
    const _rev = this.petRev;
    if (_rev < 0) { return HarmonyAgentPetManager.shared(); }
    return HarmonyAgentPetManager.shared();
  }

  /** 保存弹层中的选择并在成功后关闭弹层。 */
  private saveAndClose(): void {
    const sel: MpAgentPetSelection = {
      kind: (this.draftKind === 'builtin' ? 'builtin' : (this.draftKind === 'plugin' ? 'plugin' : 'default')),
      pluginId: this.draftPluginId,
      key: this.draftKey
    };
    HarmonyAgentPetManager.shared().select(sel).then((ok: boolean) => {
      if (ok) {
        this.onClose();
      }
    });
  }

  /** 构建插件 Agent 宠物的 ArkWeb 舞台和渲染层。 */
  build() {
    Column({ space: 12 }) {
      HarmonySheetHeader({
        title: '更换助手形象',
        cancelText: '取消',
        actionText: this.mgr().isSaving() ? '保存中…' : '保存',
        actionEnabled: !this.mgr().isSaving(),
        onCancel: () => this.onClose(),
        onAction: () => { this.saveAndClose(); }
      })

      if (this.mgr().getLastFailure().length > 0) {
        Text(this.mgr().getLastFailure())
          .fontSize(12)
          .fontColor('#F59E0B')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(12)
          .backgroundColor('#24F59E0B')
          .width('100%')
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.mgr().getAdminDefaultPetId().length > 0) {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(`跟随默认（${this.mgr().getAdminDefaultDeclaration()?.name ?? '内置机器人'}）`)
                        .fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      NativeAdaptiveBadge({ text: '系统默认', tintHex: this.accentHex })
                    }
                    Text('使用管理员配置的默认助手形象')
                      .fontSize(12).fontColor(mpSecondaryText(this.isDark))
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (this.draftKind === 'default') {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(20).fontColor([this.accentHex])
                  }
                }.width('100%')
              }
            }
            .width('100%')
            .onClick(() => {
              this.hasEditedDraft = true;
              this.draftKind = 'default';
              this.draftPluginId = '';
              this.draftKey = '';
            })
          }

          Column() {
            CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text('内置机器人').fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                    NativeAdaptiveBadge({ text: '原生', tintHex: this.accentHex })
                  }
                  Text('原生矢量绘制，支持贴边探头、呼吸眨眼与 16 种动作，零额外内存')
                    .fontSize(12).fontColor(mpSecondaryText(this.isDark))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (this.draftKind === 'builtin' ||
                  (this.draftKind === 'default' && this.mgr().getAdminDefaultPetId().length === 0)) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(20).fontColor([this.accentHex])
                }
              }.width('100%')
            }
          }
          .width('100%')
          .onClick(() => {
            this.hasEditedDraft = true;
            this.draftKind = 'builtin';
            this.draftPluginId = '';
            this.draftKey = '';
          })

          Row() {
            Text(`插件形象（${this.mgr().getDeclarations().length}）`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(mpSecondaryText(this.isDark))
              .layoutWeight(1)
            Text('刷新列表')
              .fontSize(12)
              .fontColor(this.accentHex)
              .onClick(() => { HarmonyAgentPetManager.shared().refresh(true); })
          }
          .width('100%')
          .padding({ left: 4, right: 4, top: 2 })

          ForEach(this.mgr().getDeclarations(), (pet: MpAgentPetDeclaration) => {
            Column() {
              CinematicPanel({ panelPadding: 14, cornerRadius: 16, interactive: true }) {
                Row({ space: 12 }) {
                  if (pet.previewUrl.length > 0 || pet.avatarUrl.length > 0) {
                    Image(pet.previewUrl || pet.avatarUrl)
                      .width(46).height(46).borderRadius(12).objectFit(ImageFit.Contain)
                      .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, '18'))
                  } else {
                    Stack({ alignContent: Alignment.Center }) {
                      SymbolGlyph($r('sys.symbol.ai_edit')).fontSize(20).fontColor([this.accentHex])
                    }
                    .width(46).height(46).borderRadius(12)
                    .backgroundColor(HarmonyAppearanceStore.withAlpha(this.accentHex, '18'))
                  }
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(pet.name).fontSize(14).fontWeight(FontWeight.Bold).fontColor(mpPrimaryText(this.isDark))
                      NativeAdaptiveBadge({
                        text: this.mgr().isFailed(pet.id) ? '异常·保存重试' : (pet.mode === 'stage' ? '全屏舞台' : '悬浮形象'),
                        tintHex: this.accentHex
                      })
                    }
                    Text(pet.description || pet.pluginName)
                      .fontSize(12).fontColor(mpSecondaryText(this.isDark)).maxLines(2)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (this.draftKind === 'plugin' &&
                    this.draftPluginId === pet.pluginId &&
                    this.draftKey === pet.key) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(20).fontColor([this.accentHex])
                  }
                }.width('100%')
              }
            }
            .width('100%')
            .onClick(() => {
              this.hasEditedDraft = true;
              this.draftKind = 'plugin';
              this.draftPluginId = pet.pluginId;
              this.draftKey = pet.key;
            })
          }, (pet: MpAgentPetDeclaration) => pet.id)
        }.padding({ bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .padding(20)
    .width('100%')
    .height('100%')
  }
}
