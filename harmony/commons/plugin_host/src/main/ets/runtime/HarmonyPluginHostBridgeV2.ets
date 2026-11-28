import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { RustCoreBridge } from '@moviepilot/core_rust_bridge';
import { HarmonyPluginNativeCapabilities } from './HarmonyPluginNativeCapabilities';
import { HarmonyPluginVisualTokens } from './HarmonyPluginVisualTokens';

export interface HarmonyPluginHeaderAction {
  id: string;
  title: string;
  icon: string;
  enabled: boolean;
}

export interface HarmonyPluginConfirmSpec {
  id: string;
  title: string;
  message: string;
  confirmText: string;
  cancelText: string;
  destructive: boolean;
}

export interface HarmonyPluginToastSpec {
  level: string;
  message: string;
}

export interface HarmonyPluginBridgeCallbacks {
  onShellReady: () => void;
  onPluginMounted: (mountId: string, title: string) => void;
  onPluginError: (stage: string, message: string, recoverable: boolean) => void;
  onPluginClose: () => void;
  onPluginMinimize?: (requestId: string, payload: Record<string, Object>) => void;
  onCapsuleUpdate?: (payload: Record<string, Object>) => void;
  onPluginRestore?: (requestId: string) => void;
  onNavBackResult: (handled: boolean) => void;
  onHeaderUpdate: (title: string, actions: HarmonyPluginHeaderAction[]) => void;
  onToast: (toast: HarmonyPluginToastSpec) => void;
  onConfirm: (spec: HarmonyPluginConfirmSpec) => void;
  onOpenRoute: (path: string) => void;
  onAgentOpen?: (draft: string) => void;
  onAgentClose?: () => void;
  onAgentEmit?: (name: string, data: Record<string, Object>) => void;
  onAgentPetAnchor?: (x: number, y: number, width: number, height: number) => void;
  onAgentPetAnchorCleared?: () => void;
  onAgentPetInteracting?: (active: boolean) => void;
  onAgentPetSay?: (text: string, durationMs: number) => void;
}

/** ArkWeb `javaScriptProxy` 暴露给壳层的极薄同步代理对象。 */
export class HarmonyPluginBridgeJsProxy {
  private handler: (rawJson: string) => void;

  constructor(handler: (rawJson: string) => void) {
    this.handler = handler;
  }

  postMessage(rawJson: string): void {
    this.handler(rawJson);
  }
}

/**
 * 鸿蒙端 `moviepilot.pluginHost` v2 双向桥接宿主：
 * - 严格对齐 `{ protocol: "moviepilot.pluginHost", major: 2, type, payload }` 与 `bridge.response`；
 * - 所有 `api.request` 经原生 `@kit.NetworkKit` 携带 Bearer Token 代发，WebView 内零令牌。
 */
export class HarmonyPluginHostBridgeV2 {
  static readonly PROXY_NAME = '__mpHarmonyPluginHostV2';
  static readonly PROTOCOL = 'moviepilot.pluginHost';
  static readonly PROTOCOL_MAJOR = 2;

  private controller: webview.WebviewController;
  private serverUrl: string;
  private authToken: string;
  private callbacks: HarmonyPluginBridgeCallbacks;
  private inFlightRequests: Map<string, http.HttpRequest> = new Map<string, http.HttpRequest>();
  readonly nativeCapabilities: HarmonyPluginNativeCapabilities;
  readonly jsProxy: HarmonyPluginBridgeJsProxy;

  constructor(
    controller: webview.WebviewController,
    serverUrl: string,
    authToken: string,
    callbacks: HarmonyPluginBridgeCallbacks,
    getContext: () => common.UIAbilityContext | null = () => null
  ) {
    this.controller = controller;
    this.serverUrl = serverUrl.replace(/\/+$/, '');
    this.authToken = authToken;
    this.callbacks = callbacks;
    this.nativeCapabilities = new HarmonyPluginNativeCapabilities(
      getContext,
      () => this.serverUrl,
      () => this.authToken,
      (requestId: string, ok: boolean, dataJson: string, errCode?: string, errStatus?: number, errMsg?: string) => {
        if (ok) {
          this.sendToWeb('bridge.response', `{"requestId":${JSON.stringify(requestId)},"ok":true,"data":${dataJson}}`);
        } else {
          this.sendApiError(requestId, errStatus ?? 500, errCode ?? 'NATIVE_ERROR', errMsg ?? 'Native capability failed');
        }
      },
      (event: string, dataJson: string) => {
        this.sendToWeb('device.event', `{"event":${JSON.stringify(event)},"data":${dataJson}}`);
      },
      (deepLink: string) => {
        this.callbacks.onOpenRoute(deepLink);
      }
    );
    this.jsProxy = new HarmonyPluginBridgeJsProxy((rawJson: string) => {
      this.handleIncomingMessage(rawJson);
    });
  }

  updateSession(serverUrl: string, authToken: string): void {
    this.serverUrl = serverUrl.replace(/\/+$/, '');
    this.authToken = authToken;
  }

  abortAllInFlight(): void {
    this.inFlightRequests.forEach((req: http.HttpRequest) => {
      try {
        req.destroy();
      } catch {
        // ignore
      }
    });
    this.inFlightRequests.clear();
  }

  cleanupNativeCapabilities(): void {
    this.nativeCapabilities.cleanup();
  }

  sendToWeb(type: string, payloadJson: string = '{}'): void {
    const envelopeJson = `{"protocol":"${HarmonyPluginHostBridgeV2.PROTOCOL}","major":${HarmonyPluginHostBridgeV2.PROTOCOL_MAJOR},"type":${JSON.stringify(type)},"payload":${payloadJson}}`;
    const script = `window.__mpPluginHostReceive && window.__mpPluginHostReceive(${envelopeJson});`;
    try {
      this.controller.runJavaScript(script).catch(() => {});
    } catch {
      // ignore if webview not attached
    }
  }

  sendVisualTokens(tokens: HarmonyPluginVisualTokens): void {
    this.sendToWeb('theme.update', `{"visualTokens":${JSON.stringify(tokens)}}`);
  }

  sendLocale(locale: string): void {
    this.sendToWeb('locale.update', `{"locale":${JSON.stringify(locale)}}`);
  }

  sendAgentState(stateJson: string): void {
    this.sendToWeb('agent.state', stateJson);
  }

  sendAgentEvent(name: string, dataJson: string = '{}'): void {
    this.sendToWeb(
      'agent.event',
      `{"name":${JSON.stringify(name)},"source":"host","data":${dataJson},"at":${Date.now()}}`
    );
  }

  sendHostAction(actionId: string): void {
    this.sendToWeb('host.action', `{"actionId":${JSON.stringify(actionId)}}`);
  }

  sendCapsuleAction(actionId: string): void {
    this.sendToWeb('capsule.action', `{"actionId":${JSON.stringify(actionId)}}`);
  }

  sendSimpleResponse(requestId: string, dataJson: string): void {
    if (requestId.length === 0) {
      return;
    }
    this.sendToWeb('bridge.response', `{"requestId":${JSON.stringify(requestId)},"ok":true,"data":${dataJson}}`);
  }

  sendConfirmResult(id: string, confirmed: boolean): void {
    this.sendToWeb(
      'bridge.response',
      `{"requestId":${JSON.stringify(id)},"ok":true,"data":{"confirmed":${confirmed ? 'true' : 'false'}}}`
    );
  }

  sendUnmount(): void {
    this.sendToWeb('plugin.unmount', '{}');
  }

  sendNavBack(): void {
    this.sendToWeb('nav.back', '{}');
  }

  private handleIncomingMessage(rawJson: string): void {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(rawJson) as Record<string, Object>;
    } catch {
      return;
    }
    if (!parsed || parsed['protocol'] !== HarmonyPluginHostBridgeV2.PROTOCOL) {
      return;
    }
    const type = typeof parsed['type'] === 'string' ? (parsed['type'] as string) : '';
    const emptyObj: Record<string, Object> = {};
    const payload: Record<string, Object> = (parsed['payload'] && typeof parsed['payload'] === 'object')
      ? (parsed['payload'] as Record<string, Object>)
      : emptyObj;

    switch (type) {
      case 'shell.ready':
        this.callbacks.onShellReady();
        break;
      case 'plugin.mounted': {
        const mid = typeof payload['mountId'] === 'string' ? (payload['mountId'] as string) : '';
        const title = typeof payload['title'] === 'string' ? (payload['title'] as string) : '';
        this.callbacks.onPluginMounted(mid, title);
        break;
      }
      case 'plugin.error': {
        const stage = typeof payload['stage'] === 'string' ? (payload['stage'] as string) : 'load';
        const msg = typeof payload['message'] === 'string' ? (payload['message'] as string) : '插件加载失败';
        const rec = typeof payload['recoverable'] === 'boolean' ? (payload['recoverable'] as boolean) : true;
        this.callbacks.onPluginError(stage, msg, rec);
        break;
      }
      case 'plugin.close':
        this.callbacks.onPluginClose();
        break;
      case 'agent.open': {
        const draft = typeof payload['draft'] === 'string' ? (payload['draft'] as string) : '';
        if (this.callbacks.onAgentOpen) {
          this.callbacks.onAgentOpen(draft);
        }
        break;
      }
      case 'agent.close':
        if (this.callbacks.onAgentClose) {
          this.callbacks.onAgentClose();
        }
        break;
      case 'agent.emit': {
        const name = typeof payload['name'] === 'string' ? (payload['name'] as string) : '';
        const data = (payload['data'] && typeof payload['data'] === 'object')
          ? (payload['data'] as Record<string, Object>)
          : ({} as Record<string, Object>);
        if (name.length > 0 && this.callbacks.onAgentEmit) {
          this.callbacks.onAgentEmit(name, data);
        }
        break;
      }
      case 'agent.pet.anchor': {
        const rectObj = payload['rect'] as Record<string, Object> | null | undefined;
        if (rectObj && typeof rectObj === 'object') {
          const x = Number(rectObj['x']);
          const y = Number(rectObj['y']);
          const w = Number(rectObj['width']);
          const h = Number(rectObj['height']);
          if (Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(w) && Number.isFinite(h) && w > 0 && h > 0) {
            if (this.callbacks.onAgentPetAnchor) {
              this.callbacks.onAgentPetAnchor(x, y, w, h);
            }
            break;
          }
        }
        if (this.callbacks.onAgentPetAnchorCleared) {
          this.callbacks.onAgentPetAnchorCleared();
        }
        break;
      }
      case 'agent.pet.interacting': {
        const active = typeof payload['active'] === 'boolean' ? (payload['active'] as boolean) : false;
        if (this.callbacks.onAgentPetInteracting) {
          this.callbacks.onAgentPetInteracting(active);
        }
        break;
      }
      case 'agent.pet.say': {
        const text = typeof payload['text'] === 'string' ? (payload['text'] as string).trim() : '';
        const rawDur = Number(payload['duration']);
        const dur = Number.isFinite(rawDur) ? Math.min(6000, Math.max(1500, Math.round(rawDur))) : 3500;
        if (text.length > 0 && this.callbacks.onAgentPetSay) {
          this.callbacks.onAgentPetSay(text, dur);
        }
        break;
      }
      case 'plugin.minimize': {
        const reqId = typeof payload['requestId'] === 'string' ? (payload['requestId'] as string) : '';
        if (this.callbacks.onPluginMinimize) {
          this.callbacks.onPluginMinimize(reqId, payload);
        } else {
          this.sendSimpleResponse(reqId, '{"minimized":false}');
        }
        break;
      }
      case 'plugin.capsule.update':
        if (this.callbacks.onCapsuleUpdate) {
          this.callbacks.onCapsuleUpdate(payload);
        }
        break;
      case 'plugin.restore': {
        const reqId = typeof payload['requestId'] === 'string' ? (payload['requestId'] as string) : '';
        if (this.callbacks.onPluginRestore) {
          this.callbacks.onPluginRestore(reqId);
        } else {
          this.sendSimpleResponse(reqId, '{"restored":true}');
        }
        break;
      }
      case 'nav.backResult': {
        const handled = typeof payload['handled'] === 'boolean' ? (payload['handled'] as boolean) : false;
        this.callbacks.onNavBackResult(handled);
        break;
      }
      case 'api.request': {
        const reqId = typeof payload['requestId'] === 'string' ? (payload['requestId'] as string) : '';
        if (reqId.length > 0) {
          this.executeApiRequest(reqId, payload);
        }
        break;
      }
      case 'api.abort': {
        const targetId = typeof payload['requestId'] === 'string' ? (payload['requestId'] as string) : '';
        const existing = this.inFlightRequests.get(targetId);
        if (existing) {
          this.inFlightRequests.delete(targetId);
          try {
            existing.destroy();
          } catch {
            // ignore
          }
        }
        break;
      }
      case 'ui.toast': {
        const level = typeof payload['level'] === 'string' ? (payload['level'] as string) : 'info';
        const msg = typeof payload['message'] === 'string' ? (payload['message'] as string) : '';
        if (msg.length > 0) {
          this.callbacks.onToast({ level: level, message: msg });
        }
        break;
      }
      case 'ui.confirm': {
        const confirmId = typeof payload['requestId'] === 'string' ? (payload['requestId'] as string) : '';
        if (confirmId.length === 0) {
          return;
        }
        const title = typeof payload['title'] === 'string' && (payload['title'] as string).length > 0
          ? (payload['title'] as string)
          : '请确认';
        const message = typeof payload['message'] === 'string' ? (payload['message'] as string) : '';
        const confirmText = typeof payload['confirmText'] === 'string' && (payload['confirmText'] as string).length > 0
          ? (payload['confirmText'] as string)
          : '确定';
        const cancelText = typeof payload['cancelText'] === 'string' && (payload['cancelText'] as string).length > 0
          ? (payload['cancelText'] as string)
          : '取消';
        const destructive = typeof payload['destructive'] === 'boolean' ? (payload['destructive'] as boolean) : false;
        this.callbacks.onConfirm({
          id: confirmId,
          title: title,
          message: message,
          confirmText: confirmText,
          cancelText: cancelText,
          destructive: destructive
        });
        break;
      }
      case 'ui.header': {
        const title = typeof payload['title'] === 'string' ? (payload['title'] as string) : '';
        const rawActions = Array.isArray(payload['actions']) ? (payload['actions'] as Object[]) : [];
        const actions: HarmonyPluginHeaderAction[] = [];
        for (let i = 0; i < rawActions.length; i++) {
          const item = rawActions[i] as Record<string, Object>;
          if (item && typeof item['id'] === 'string' && (item['id'] as string).length > 0) {
            const label = typeof item['label'] === 'string'
              ? (item['label'] as string)
              : (typeof item['title'] === 'string' ? (item['title'] as string) : (item['id'] as string));
            actions.push({
              id: item['id'] as string,
              title: label,
              icon: typeof item['icon'] === 'string' ? (item['icon'] as string) : '',
              enabled: !(typeof item['disabled'] === 'boolean' && (item['disabled'] as boolean))
            });
          }
        }
        this.callbacks.onHeaderUpdate(title, actions);
        break;
      }
      case 'nav.openRoute': {
        const route = typeof payload['deepLink'] === 'string'
          ? (payload['deepLink'] as string)
          : (typeof payload['path'] === 'string' ? (payload['path'] as string) : '');
        if (route.length > 0) {
          this.callbacks.onOpenRoute(route);
        }
        break;
      }
      case 'device.haptic': {
        const style = typeof payload['style'] === 'string' ? (payload['style'] as string) : 'light';
        this.nativeCapabilities.triggerHaptic(style);
        break;
      }
      case 'device.clipboard': {
        const text = typeof payload['text'] === 'string' ? (payload['text'] as string) : '';
        const reqId = typeof payload['requestId'] === 'string' ? (payload['requestId'] as string) : '';
        if (text.length > 0) {
          try {
            const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
            pasteboard.getSystemPasteboard().setData(data).catch(() => {});
          } catch {
            // ignore clipboard errors
          }
        }
        if (reqId.length > 0) {
          this.sendToWeb('bridge.response', `{"requestId":${JSON.stringify(reqId)},"ok":true,"data":{"copied":true}}`);
        }
        break;
      }
      default: {
        const reqId = typeof payload['requestId'] === 'string' ? (payload['requestId'] as string) : '';
        this.nativeCapabilities.handle(type, reqId, payload);
        break;
      }
    }
  }

  private executeApiRequest(requestId: string, payload: Record<string, Object>): void {
    const rawPath = typeof payload['path'] === 'string' ? (payload['path'] as string) : '';
    const normalizedPath = RustCoreBridge.validatePluginApiPath(rawPath);
    if (!normalizedPath) {
      this.sendApiError(requestId, 403, 'FORBIDDEN_PATH', 'Blocked unsafe API path');
      return;
    }
    if (!this.serverUrl || !this.authToken) {
      this.sendApiError(requestId, 401, 'NO_SESSION', 'No active session');
      return;
    }
    const methodStr = (typeof payload['method'] === 'string' ? (payload['method'] as string) : 'GET').toUpperCase();
    const httpMethod = this.toHttpMethod(methodStr);
    const fullUrl = this.appendQuery(
      `${this.serverUrl}${normalizedPath}`,
      payload['query'] && typeof payload['query'] === 'object' ? (payload['query'] as Record<string, Object>) : null
    );

    const headers: Record<string, string> = {
      'Authorization': `Bearer ${this.authToken}`,
      'Accept': 'application/json, text/plain, */*',
      'X-MoviePilot-Locale': 'zh-CN'
    };
    const customHeaders = payload['headers'];
    if (customHeaders && typeof customHeaders === 'object') {
      const rec = customHeaders as Record<string, Object>;
      const keys = Object.keys(rec);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        const lower = k.toLowerCase();
        if (lower === 'authorization' || lower === 'cookie' || lower === 'host') {
          continue;
        }
        headers[k] = String(rec[k]);
      }
    }

    const bodyEncoding = typeof payload['bodyEncoding'] === 'string' ? (payload['bodyEncoding'] as string) : '';
    let extraData: string | undefined = undefined;
    if (bodyEncoding === 'json' && payload['body'] !== undefined) {
      extraData = typeof payload['body'] === 'string'
        ? (payload['body'] as string)
        : JSON.stringify(payload['body']);
      if (!headers['Content-Type'] && !headers['content-type']) {
        headers['Content-Type'] = 'application/json; charset=utf-8';
      }
    } else if (bodyEncoding === 'text' && typeof payload['body'] === 'string') {
      extraData = payload['body'] as string;
      if (!headers['Content-Type'] && !headers['content-type']) {
        headers['Content-Type'] = 'text/plain; charset=utf-8';
      }
    }

    const timeoutMs = typeof payload['timeoutMs'] === 'number'
      ? Math.max(3000, Math.min(120000, payload['timeoutMs'] as number))
      : 30000;
    const responseType = typeof payload['responseType'] === 'string' ? (payload['responseType'] as string) : 'json';

    const req = http.createHttp();
    this.inFlightRequests.set(requestId, req);
    req.request(fullUrl, {
      method: httpMethod,
      header: headers,
      extraData: extraData,
      connectTimeout: 15000,
      readTimeout: timeoutMs,
      expectDataType: http.HttpDataType.STRING
    }).then((resp: http.HttpResponse) => {
      this.inFlightRequests.delete(requestId);
      const status = resp.responseCode;
      const ok = status >= 200 && status < 300;
      const text = typeof resp.result === 'string' ? resp.result : String(resp.result ?? '');
      let encoding = 'text';
      let bodyJsonValue = JSON.stringify(text);
      if (responseType !== 'text') {
        if (text.trim().length === 0) {
          encoding = 'json';
          bodyJsonValue = 'null';
        } else {
          try {
            JSON.parse(text);
            encoding = 'json';
            bodyJsonValue = text;
          } catch {
            encoding = 'text';
            bodyJsonValue = JSON.stringify(text);
          }
        }
      }
      if (ok) {
        const payloadJson = `{"requestId":${JSON.stringify(requestId)},"ok":true,"data":{"status":${status},"headers":{},"bodyEncoding":${JSON.stringify(encoding)},"body":${bodyJsonValue}}}`;
        this.sendToWeb('bridge.response', payloadJson);
      } else {
        const payloadJson = `{"requestId":${JSON.stringify(requestId)},"ok":false,"error":{"code":"HTTP_${status}","status":${status},"message":"HTTP ${status}","data":${bodyJsonValue}}}`;
        this.sendToWeb('bridge.response', payloadJson);
      }
      req.destroy();
    }).catch((err: Object) => {
      this.inFlightRequests.delete(requestId);
      const msg = err ? String(err) : 'Network error';
      this.sendApiError(requestId, 0, 'NETWORK_ERROR', msg);
      try {
        req.destroy();
      } catch {
        // ignore
      }
    });
  }

  private sendApiError(requestId: string, status: number, code: string, message: string): void {
    const payloadJson = `{"requestId":${JSON.stringify(requestId)},"ok":false,"error":{"code":${JSON.stringify(code)},"status":${status},"message":${JSON.stringify(message)}}}`;
    this.sendToWeb('bridge.response', payloadJson);
  }

  private toHttpMethod(method: string): http.RequestMethod {
    switch (method) {
      case 'POST':
        return http.RequestMethod.POST;
      case 'PUT':
        return http.RequestMethod.PUT;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      case 'HEAD':
        return http.RequestMethod.HEAD;
      default:
        return http.RequestMethod.GET;
    }
  }

  private appendQuery(baseUrl: string, query: Record<string, Object> | null): string {
    if (!query) {
      return baseUrl;
    }
    const keys = Object.keys(query);
    if (keys.length === 0) {
      return baseUrl;
    }
    const pairs: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const v = query[k];
      if (v === undefined || v === null) {
        continue;
      }
      pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
    }
    if (pairs.length === 0) {
      return baseUrl;
    }
    const sep = baseUrl.includes('?') ? '&' : '?';
    return `${baseUrl}${sep}${pairs.join('&')}`;
  }
}
