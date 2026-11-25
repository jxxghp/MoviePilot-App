import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { RustCoreBridge } from '@moviepilot/core_rust_bridge';
import { HarmonyAppearanceStore, HarmonyThemeColors, mpPrimaryText, mpSecondaryText } from '@moviepilot/design_system';
import {
  HarmonyPluginBridgeJsProxy,
  HarmonyPluginConfirmSpec,
  HarmonyPluginHeaderAction,
  HarmonyPluginHostBridgeV2,
  HarmonyPluginToastSpec
} from './HarmonyPluginHostBridgeV2';
import { HarmonyPluginRemoteCache } from './HarmonyPluginRemoteCache';
import { buildHarmonyPluginVisualTokens } from './HarmonyPluginVisualTokens';

interface RemoteDescriptorItem {
  id: string;
  url: string;
  name: string;
  sourcePluginId: string;
  version: string;
  bundleHash: string;
}

/**
 * 鸿蒙端本地预热极简联邦运行时 ArkWeb 容器（Route A）：
 * - 通过 `onInterceptRequest` 在虚拟安全源 `https://plugin-shell.moviepilot.local/` 托管 `rawfile/plugin_shell/`
 *   与实例隔离缓存的 `/plugin-remote/{id}/{ver}/*`，彻底摆脱对前端 3000 端口的依赖；
 * - 透明背景透出鸿蒙动态流光画布，实时同步 5 套鸿蒙色板与深浅/纯黑切换；
 * - WebView 内零 Bearer Token，`api.request` 由 `@kit.NetworkKit` 原生代发；
 * - 异常时提供「重新加载」与「用兼容网页容器打开」一键回退。
 */
@Component
export struct HarmonyLocalPluginShellView {
  static readonly VIRTUAL_HOST = 'plugin-shell.moviepilot.local';
  static readonly VIRTUAL_ORIGIN = 'https://plugin-shell.moviepilot.local';
  static readonly SHELL_ENTRY_URL = 'https://plugin-shell.moviepilot.local/shell/plugin-shell.html';

  @StorageLink(HarmonyAppearanceStore.KEY_IS_DARK) @Watch('onVisualChanged') isDark: boolean = true;
  @StorageLink(HarmonyAppearanceStore.KEY_PALETTE_ID) @Watch('onVisualChanged') paletteId: string = 'harmony_blue';
  @StorageLink(HarmonyAppearanceStore.KEY_ACCENT_HEX) @Watch('onVisualChanged') accentHex: string = '#317AF7';
  @StorageLink(HarmonyAppearanceStore.KEY_PURE_BLACK) @Watch('onVisualChanged') pureBlack: boolean = false;
  @StorageLink(HarmonyAppearanceStore.KEY_LOCALE) @Watch('onLocaleChanged') locale: string = 'zh-CN';

  @Prop pluginId: string = '';
  @Prop pluginName: string = '';
  @Prop serverUrl: string = '';
  @Prop authToken: string = '';
  @Prop userName: string = 'admin';
  @Prop userAvatar: string = '';
  @Prop isSuperuser: boolean = true;
  @Prop surface: string = 'dataPage';
  @Prop navKey: string = '';
  @Prop pluginHasPage: boolean = true;

  onHeaderUpdate: (title: string, actions: HarmonyPluginHeaderAction[]) => void = () => {};
  onRequestDismiss: () => void = () => {};
  onFallbackToLegacy: () => void = () => {};
  onRegisterActions: (invoke: (actionId: string) => void, close: () => boolean) => void = () => {};

  @State private isMounted: boolean = false;
  @State private errorMessage: string = '';
  @State private toastText: string = '';
  @State private toastLevel: string = 'info';

  private webController: webview.WebviewController = new webview.WebviewController();
  private bridge: HarmonyPluginHostBridgeV2 | null = null;
  private isShellReady: boolean = false;
  private pendingMountPayloadJson: string = '';
  private toastTimer: number = -1;

  aboutToAppear(): void {
    this.bridge = new HarmonyPluginHostBridgeV2(
      this.webController,
      this.serverUrl,
      this.authToken,
      {
        onShellReady: () => {
          this.isShellReady = true;
          if (this.pendingMountPayloadJson.length > 0 && this.bridge) {
            this.bridge.sendToWeb('plugin.mount', this.pendingMountPayloadJson);
          }
        },
        onPluginMounted: (_pid: string, _surf: string) => {
          this.isMounted = true;
          this.errorMessage = '';
        },
        onPluginError: (_code: string, msg: string, _rec: boolean) => {
          this.isMounted = false;
          this.errorMessage = msg || '本地运行时加载插件失败';
        },
        onPluginClose: () => {
          this.onRequestDismiss();
        },
        onHeaderUpdate: (title: string, actions: HarmonyPluginHeaderAction[]) => {
          this.onHeaderUpdate(title, actions);
        },
        onToast: (toast: HarmonyPluginToastSpec) => {
          this.showToast(toast.level, toast.message);
        },
        onConfirm: (spec: HarmonyPluginConfirmSpec) => {
          this.presentNativeConfirm(spec);
        },
        onOpenRoute: (path: string) => {
          const parsed: string = RustCoreBridge.parseDeepLinkJson(path);
          if (parsed && parsed.length > 2) {
            AppStorage.setOrCreate('mp_pending_deeplink_origin', '');
            AppStorage.setOrCreate('mp_pending_deeplink', parsed);
          }
        }
      },
      () => this.getAbilityContext()
    );
    this.onRegisterActions(
      (actionId: string) => {
        this.bridge?.sendHostAction(actionId);
      },
      () => {
        this.bridge?.sendNavBack();
        return false;
      }
    );
    this.prepareMountPayload();
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
    this.bridge?.sendUnmount();
    this.bridge?.abortAllInFlight();
    this.bridge?.cleanupNativeCapabilities();
  }

  onVisualChanged(): void {
    const tokens = buildHarmonyPluginVisualTokens(this.isDark, this.paletteId, this.accentHex, this.pureBlack);
    this.bridge?.sendVisualTokens(tokens);
  }

  onLocaleChanged(): void {
    this.bridge?.sendLocale(this.locale || 'zh-CN');
  }

  private getAbilityContext(): common.UIAbilityContext | null {
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch {
      return null;
    }
  }

  private showToast(level: string, message: string): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
    this.toastLevel = level;
    this.toastText = message;
    this.toastTimer = setTimeout(() => {
      this.toastText = '';
      this.toastTimer = -1;
    }, 2600);
  }

  private presentNativeConfirm(spec: HarmonyPluginConfirmSpec): void {
    try {
      this.getUIContext().showAlertDialog({
        title: spec.title,
        message: spec.message,
        autoCancel: true,
        primaryButton: {
          value: spec.cancelText,
          action: () => {
            this.bridge?.sendConfirmResult(spec.id, false);
          }
        },
        secondaryButton: {
          value: spec.confirmText,
          fontColor: spec.destructive ? '#EF4444' : this.accentHex,
          action: () => {
            this.bridge?.sendConfirmResult(spec.id, true);
          }
        },
        cancel: () => {
          this.bridge?.sendConfirmResult(spec.id, false);
        }
      });
    } catch {
      this.bridge?.sendConfirmResult(spec.id, false);
    }
  }

  private prepareMountPayload(): void {
    this.isMounted = false;
    this.errorMessage = '';
    this.pendingMountPayloadJson = '';
    const origin = this.serverUrl.replace(/\/+$/, '');
    const remotesUrl = `${origin}/api/v1/plugin/remotes?token=moviepilot`;
    const req = http.createHttp();
    req.request(remotesUrl, {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': `Bearer ${this.authToken}`,
        'X-MoviePilot-Locale': this.locale || 'zh-CN'
      },
      connectTimeout: 12000,
      readTimeout: 20000,
      expectDataType: http.HttpDataType.STRING
    }).then((resp: http.HttpResponse) => {
      req.destroy();
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        this.errorMessage = `获取联邦插件入口失败（HTTP ${resp.responseCode}）`;
        return;
      }
      const rawText = typeof resp.result === 'string' ? resp.result : '';
      const descriptor = this.findDescriptor(rawText, this.pluginId);
      if (!descriptor) {
        this.errorMessage = `未在运行态联邦插件列表中找到 ${this.pluginId}`;
        return;
      }
      const cacheVer = descriptor.bundleHash
        ? (descriptor.version ? `${descriptor.version}-${descriptor.bundleHash}` : descriptor.bundleHash)
        : descriptor.version;
      const plan = RustCoreBridge.normalizePluginRemoteEntry(
        descriptor.sourcePluginId || descriptor.id,
        cacheVer,
        descriptor.url
      );
      if (!plan) {
        this.errorMessage = '联邦插件入口路径不符合安全规范';
        return;
      }
      const virtualEntryUrl = `${HarmonyLocalPluginShellView.VIRTUAL_ORIGIN}${plan.virtual_entry_path}`;
      const tokens = buildHarmonyPluginVisualTokens(this.isDark, this.paletteId, this.accentHex, this.pureBlack);
      const mountObj: Record<string, Object> = {
        'mountId': `ohos_${Date.now()}`,
        'pluginId': this.pluginId,
        'pluginName': this.pluginName || descriptor.name || this.pluginId,
        'remoteEntryUrl': virtualEntryUrl,
        'surface': this.surface || 'dataPage',
        'showSwitch': this.pluginHasPage,
        'locale': this.locale || 'zh-CN',
        'visualTokens': tokens,
        'safeArea': { 'top': 0, 'bottom': 16, 'left': 0, 'right': 0 } as Record<string, Object>,
        'user': {
          'id': 1,
          'superUser': this.isSuperuser,
          'userName': this.userName,
          'avatar': this.userAvatar,
          'level': 2,
          'permissions': {
            'discovery': true,
            'search': true,
            'subscribe': true,
            'manage': true,
            'admin': this.isSuperuser
          } as Record<string, Object>
        } as Record<string, Object>
      };
      if (descriptor.sourcePluginId.length > 0) {
        mountObj['sourcePluginId'] = descriptor.sourcePluginId;
      }
      if (descriptor.version.length > 0) {
        mountObj['pluginVersion'] = descriptor.version;
      }
      if (this.navKey.length > 0) {
        mountObj['navKey'] = this.navKey;
      }
      this.pendingMountPayloadJson = JSON.stringify(mountObj);
      if (this.isShellReady && this.bridge) {
        this.bridge.sendToWeb('plugin.mount', this.pendingMountPayloadJson);
      }
    }).catch((err: Object) => {
      try {
        req.destroy();
      } catch {
        // ignore
      }
      this.errorMessage = err ? String(err) : '无法从后端获取联邦插件入口';
    });
  }

  private findDescriptor(rawJson: string, targetId: string): RemoteDescriptorItem | null {
    try {
      const parsed = JSON.parse(rawJson) as Object;
      let list: Object[] = [];
      if (Array.isArray(parsed)) {
        list = parsed as Object[];
      } else if (parsed && typeof parsed === 'object') {
        const rec = parsed as Record<string, Object>;
        if (Array.isArray(rec['data'])) {
          list = rec['data'] as Object[];
        }
      }
      const targetLower = targetId.toLowerCase();
      for (let i = 0; i < list.length; i++) {
        const item = list[i] as Record<string, Object>;
        if (!item || typeof item['id'] !== 'string' || typeof item['url'] !== 'string') {
          continue;
        }
        if ((item['id'] as string).toLowerCase() === targetLower) {
          return {
            id: item['id'] as string,
            url: item['url'] as string,
            name: typeof item['name'] === 'string' ? (item['name'] as string) : '',
            sourcePluginId: typeof item['source_plugin_id'] === 'string' ? (item['source_plugin_id'] as string) : '',
            version: typeof item['version'] === 'string' ? (item['version'] as string) : '',
            bundleHash: typeof item['bundle_hash'] === 'string' ? (item['bundle_hash'] as string) : ''
          };
        }
      }
    } catch {
      // ignore
    }
    return null;
  }

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
      return this.serveRemotePluginAsset(pathOnly);
    }
    if (pathOnly.startsWith('/api/v1/')) {
      if (method.toUpperCase() !== 'GET' && method.toUpperCase() !== 'HEAD') {
        return this.makeErrorResponse(405, 'Only passive GET allowed');
      }
      return this.servePassiveApiResource(pathAndQuery);
    }
    return this.makeErrorResponse(404, 'Not Found');
  }

  private serveShellRawfile(virtualPath: string): WebResourceResponse {
    const relPath = RustCoreBridge.validatePluginShellAssetPath(virtualPath);
    if (!relPath) {
      return this.makeErrorResponse(400, 'Invalid shell asset path');
    }
    const ctx = this.getAbilityContext();
    if (!ctx) {
      return this.makeErrorResponse(500, 'No UIAbilityContext');
    }
    try {
      const bytes = ctx.resourceManager.getRawFileContentSync(`plugin_shell/${relPath}`);
      const mime = HarmonyPluginRemoteCache.guessMimeType(relPath);
      const resp = new WebResourceResponse();
      resp.setResponseData(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      resp.setResponseMimeType(mime);
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
      return this.makeErrorResponse(404, `Shell asset missing: ${relPath}`);
    }
  }

  private serveRemotePluginAsset(virtualPath: string): WebResourceResponse {
    const target = RustCoreBridge.resolvePluginRemoteUpstream(virtualPath);
    if (!target) {
      return this.makeErrorResponse(400, 'Invalid plugin remote path');
    }
    const ctx = this.getAbilityContext();
    const cacheDir = ctx ? ctx.cacheDir : '';
    const origin = this.serverUrl.replace(/\/+$/, '');

    // 1. 优先命中沙箱磁盘缓存（同步秒返）
    const cached = HarmonyPluginRemoteCache.readSync(
      cacheDir,
      origin,
      target.plugin_id,
      target.version_tag,
      target.asset_rel_path
    );
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

    // 2. 未命中时异步经原生鉴权回源并落盘
    const resp = new WebResourceResponse();
    resp.setResponseIsReady(false);
    const upstreamUrl = `${origin}${target.upstream_api_path}`;
    const req = http.createHttp();
    req.request(upstreamUrl, {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': `Bearer ${this.authToken}`,
        'X-MoviePilot-Locale': this.locale || 'zh-CN'
      },
      connectTimeout: 15000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }).then((httpResp: http.HttpResponse) => {
      req.destroy();
      const buf = httpResp.result instanceof ArrayBuffer ? httpResp.result : new ArrayBuffer(0);
      const mime = HarmonyPluginRemoteCache.guessMimeType(target.asset_rel_path);
      if (httpResp.responseCode >= 200 && httpResp.responseCode < 300 && buf.byteLength > 0) {
        HarmonyPluginRemoteCache.writeSync(
          cacheDir,
          origin,
          target.plugin_id,
          target.version_tag,
          target.asset_rel_path,
          buf
        );
      }
      resp.setResponseData(buf);
      resp.setResponseMimeType(mime);
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(httpResp.responseCode);
      resp.setReasonMessage(httpResp.responseCode >= 200 && httpResp.responseCode < 300 ? 'OK' : 'Error');
      resp.setResponseHeader([
        { headerKey: 'Access-Control-Allow-Origin', headerValue: HarmonyLocalPluginShellView.VIRTUAL_ORIGIN },
        { headerKey: 'Cache-Control', headerValue: 'public, max-age=31536000, immutable' }
      ]);
      resp.setResponseIsReady(true);
    }).catch(() => {
      try {
        req.destroy();
      } catch {
        // ignore
      }
      resp.setResponseData('Upstream fetch failed');
      resp.setResponseMimeType('text/plain');
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(502);
      resp.setReasonMessage('Bad Gateway');
      resp.setResponseIsReady(true);
    });
    return resp;
  }

  private servePassiveApiResource(pathWithQuery: string): WebResourceResponse {
    const normalized = RustCoreBridge.validatePluginApiPath(pathWithQuery);
    if (!normalized) {
      return this.makeErrorResponse(400, 'Invalid API path');
    }
    const resp = new WebResourceResponse();
    resp.setResponseIsReady(false);
    const origin = this.serverUrl.replace(/\/+$/, '');
    const req = http.createHttp();
    req.request(`${origin}${normalized}`, {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': `Bearer ${this.authToken}`,
        'X-MoviePilot-Locale': this.locale || 'zh-CN'
      },
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
      try {
        req.destroy();
      } catch {
        // ignore
      }
      resp.setResponseData('Proxy failed');
      resp.setResponseMimeType('text/plain');
      resp.setResponseEncoding('utf-8');
      resp.setResponseCode(502);
      resp.setReasonMessage('Bad Gateway');
      resp.setResponseIsReady(true);
    });
    return resp;
  }

  private makeErrorResponse(code: number, message: string): WebResourceResponse {
    const resp = new WebResourceResponse();
    resp.setResponseData(message);
    resp.setResponseMimeType('text/plain');
    resp.setResponseEncoding('utf-8');
    resp.setResponseCode(code);
    resp.setReasonMessage(message);
    resp.setResponseIsReady(true);
    return resp;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Web({
        src: HarmonyLocalPluginShellView.SHELL_ENTRY_URL,
        controller: this.webController
      })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .metaViewport(true)
        .mediaPlayGestureAccess(false)
        .backgroundColor(Color.Transparent)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const w = Number(newArea.width);
          const h = Number(newArea.height);
          if (w > 0 && h > 0) {
            try {
              this.webController.runJavaScript("window.dispatchEvent(new Event('resize'));");
            } catch {
              // ignore before webview ready
            }
          }
        })
        .javaScriptProxy({
          object: this.bridge ? this.bridge.jsProxy : new HarmonyPluginBridgeJsProxy(() => {}),
          name: HarmonyPluginHostBridgeV2.PROXY_NAME,
          methodList: ['postMessage'],
          controller: this.webController
        })
        .onPermissionRequest((ev) => {
          if (!ev || !ev.request) {
            return;
          }
          const origin = ev.request.getOrigin() ?? '';
          if (!origin.startsWith(HarmonyLocalPluginShellView.VIRTUAL_ORIGIN)) {
            ev.request.deny();
            return;
          }
          const resources = ev.request.getAccessibleResource() ?? [];
          const bridgeRef = this.bridge;
          if (!bridgeRef) {
            ev.request.deny();
            return;
          }
          const ensurePermissions = async (): Promise<void> => {
            let ok = true;
            for (let i = 0; i < resources.length; i++) {
              const res = resources[i];
              if (res === 'TYPE_AUDIO_CAPTURE') {
                const micOk = await bridgeRef.nativeCapabilities.checkOrRequestOhosPermission('ohos.permission.MICROPHONE', true);
                if (!micOk) { ok = false; }
              } else if (res === 'TYPE_VIDEO_CAPTURE') {
                const camOk = await bridgeRef.nativeCapabilities.checkOrRequestOhosPermission('ohos.permission.CAMERA', true);
                if (!camOk) { ok = false; }
              }
            }
            if (ok) {
              ev.request.grant(resources);
            } else {
              ev.request.deny();
            }
          };
          ensurePermissions().catch(() => {
            try { ev.request.deny(); } catch { /* ignore */ }
          });
        })
        .onInterceptRequest((ev) => {
          if (!ev || !ev.request) {
            return null;
          }
          return this.handleInterceptRequest(
            ev.request.getRequestUrl(),
            ev.request.getRequestMethod()
          );
        })
        .onLoadIntercept((ev) => {
          const url = ev && ev.data ? ev.data.getRequestUrl() : '';
          return !url.startsWith(HarmonyLocalPluginShellView.VIRTUAL_ORIGIN);
        })
        .onRenderExited(() => {
          this.isMounted = false;
          this.errorMessage = '插件渲染进程异常中断，请重新加载';
        })
        .opacity(this.isMounted && this.errorMessage.length === 0 ? 1 : 0.01)
        .animation({ duration: 160, curve: Curve.EaseOut })
        .width('100%')
        .height('100%')

      if (this.errorMessage.length > 0) {
        Column({ space: 12 }) {
          Text('本地运行时加载插件失败')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(mpPrimaryText(this.isDark))
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor(mpSecondaryText(this.isDark))
            .textAlign(TextAlign.Center)
          Row({ space: 12 }) {
            Button('重新加载')
              .backgroundColor(this.accentHex)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.isShellReady = false;
                this.prepareMountPayload();
                try {
                  this.webController.loadUrl(HarmonyLocalPluginShellView.SHELL_ENTRY_URL);
                } catch {
                  // ignore
                }
              })
            Button('用兼容网页容器打开')
              .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
              .fontColor(mpPrimaryText(this.isDark))
              .onClick(() => {
                this.onFallbackToLegacy();
              })
          }
        }
        .padding(20)
        .margin({ left: 16, right: 16 })
        .borderRadius(16)
        .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
        .alignSelf(ItemAlign.Center)
        .position({ y: '35%' })
      } else if (!this.isMounted) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.accentHex)
          Text('正在启动本地插件运行时…')
            .fontSize(13)
            .fontColor(mpSecondaryText(this.isDark))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      if (this.toastText.length > 0) {
        Row({ space: 8 }) {
          Text(this.toastText)
            .fontSize(13)
            .fontColor(mpPrimaryText(this.isDark))
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .margin({ bottom: 20, left: 16, right: 16 })
        .borderRadius(14)
        .backgroundColor(HarmonyThemeColors.card(this.isDark, this.paletteId))
      }
    }
    .width('100%')
    .height('100%')
  }
}
