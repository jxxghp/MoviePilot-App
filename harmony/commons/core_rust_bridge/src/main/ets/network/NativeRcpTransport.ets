import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { RustCoreBridge } from '../bridge/RustCoreBridge';

/** 原生网络响应快照。 */
export interface NativeHttpResponse {
  status: number;
  body: string;
}

/** SSE 流式事件回调载荷。 */
export interface SseEventChunk {
  event: string;
  data: string;
}

/**
 * 鸿蒙原生网络传输层（基于 `@kit.NetworkKit` 系统 HTTP 栈）：
 * - 严格通过 `RustCoreBridge.serverAddressContains(baseUrl, url)` 守卫同源边界，绝不向第三方外链泄露 JWT 或 Cookie；
 * - 识别 401 与过期型 403（`RustCoreBridge.classifyAuthStatus === 'logout'`）并触发全局过期登出回调；
 * - 支持自签名 HTTPS 开关、表单、JSON、Multipart 上传与 `requestInStream` 分块流式 SSE。
 */
export class NativeRcpTransport {
  private baseUrl: string = '';
  private allowSelfSigned: boolean = false;
  private cookieJar: Map<string, string> = new Map<string, string>();
  onAuthExpired: (() => void) | null = null;

  /** 绑定当前受信任的 MoviePilot 实例根地址（用于同源凭据守卫）。 */
  setBaseUrl(url: string): void {
    this.baseUrl = url.trim();
  }

  /** 设置是否信任自签名 HTTPS 证书。 */
  setAllowSelfSigned(allow: boolean): void {
    this.allowSelfSigned = allow;
  }

  isAllowSelfSigned(): boolean {
    return this.allowSelfSigned;
  }

  clearCookies(): void {
    this.cookieJar.clear();
  }

  getCookieHeader(): string {
    const parts: string[] = [];
    this.cookieJar.forEach((value: string, key: string) => {
      parts.push(`${key}=${value}`);
    });
    return parts.join('; ');
  }

  /** 严格校验候选 URL 是否归属当前实例同源与子路径边界。 */
  isSameOriginUrl(candidateUrl: string): boolean {
    if (!this.baseUrl || !candidateUrl) {
      return false;
    }
    return RustCoreBridge.serverAddressContains(this.baseUrl, candidateUrl);
  }

  private notifyAuthIfExpired(url: string, token: string, status: number, body: string): void {
    if (!token || !this.isSameOriginUrl(url) || url.includes('/login/access-token')) {
      return;
    }
    if (RustCoreBridge.classifyAuthStatus(status, body) === 'logout') {
      if (this.onAuthExpired) {
        this.onAuthExpired();
      }
    }
  }

  private captureSetCookies(url: string, headerObj: Object | undefined, rawCookies: string = ''): void {
    if (!this.isSameOriginUrl(url)) {
      return;
    }
    if (headerObj) {
      const headers = headerObj as Record<string, Object>;
      const raw = headers['set-cookie'] ?? headers['Set-Cookie'];
      if (raw) {
        const entries: string[] = Array.isArray(raw) ? (raw as string[]) : [String(raw)];
        for (let i = 0; i < entries.length; i++) {
          const lines = entries[i].split(/\r?\n/);
          for (let j = 0; j < lines.length; j++) {
            const firstPart = lines[j].split(';')[0].trim();
            const eqIdx = firstPart.indexOf('=');
            if (eqIdx > 0) {
              const name = firstPart.substring(0, eqIdx).trim();
              const val = firstPart.substring(eqIdx + 1).trim();
              if (name.length > 0) {
                this.cookieJar.set(name, val);
              }
            }
          }
        }
      }
    }
    if (rawCookies && rawCookies.trim().length > 0) {
      const lines = rawCookies.split(/\r?\n/);
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line || line.startsWith('#')) { continue; }
        if (line.includes('\t')) {
          const cols = line.split('\t');
          if (cols.length >= 7 && cols[5].trim().length > 0) {
            this.cookieJar.set(cols[5].trim(), cols[6].trim());
            continue;
          }
        }
        const firstPart = line.split(';')[0].trim();
        const eqIdx = firstPart.indexOf('=');
        if (eqIdx > 0) {
          const name = firstPart.substring(0, eqIdx).trim();
          const val = firstPart.substring(eqIdx + 1).trim();
          if (name.length > 0) {
            this.cookieJar.set(name, val);
          }
        }
      }
    }
  }

  /** 执行 REST JSON / Form 请求（仅对同源实例附加 Authorization 与 Cookie）。 */
  async execute(
    url: string,
    method: string = 'GET',
    token: string = '',
    body: string = '',
    contentType: string = 'application/json',
    extraHeaders?: Record<string, string>
  ): Promise<NativeHttpResponse> {
    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = 'application/json, text/plain, */*';
    const upper = method.toUpperCase();
    if (body.length > 0 || upper === 'POST' || upper === 'PUT') {
      header['Content-Type'] = contentType;
    }
    const sameOrigin = this.isSameOriginUrl(url);
    if (sameOrigin && token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    if (sameOrigin) {
      const cookieStr = this.getCookieHeader();
      if (cookieStr.length > 0) {
        header['Cookie'] = cookieStr;
      }
    }
    if (extraHeaders) {
      const keys = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        header[keys[i]] = extraHeaders[keys[i]];
      }
    }

    let httpMethod: http.RequestMethod = http.RequestMethod.GET;
    if (upper === 'POST') {
      httpMethod = http.RequestMethod.POST;
    } else if (upper === 'PUT') {
      httpMethod = http.RequestMethod.PUT;
    } else if (upper === 'DELETE') {
      httpMethod = http.RequestMethod.DELETE;
    }

    const reqOpts: http.HttpRequestOptions = {
      method: httpMethod,
      header: header,
      extraData: body.length > 0 ? body : undefined,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 35000,
      usingCache: false
    };
    if (this.allowSelfSigned) {
      reqOpts.remoteValidation = 'skip';
    }

    try {
      const resp = await client.request(url, reqOpts);
      this.captureSetCookies(url, resp.header, resp.cookies ?? '');
      const text = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result ?? '');
      this.notifyAuthIfExpired(url, token, resp.responseCode, text);
      return {
        status: resp.responseCode,
        body: text
      };
    } finally {
      client.destroy();
    }
  }

  /** 拉取二进制图片资源（仅在同源时携带 Bearer Token 与 Cookie，防止跨源泄露凭据）。 */
  async fetchBinary(url: string, token: string = ''): Promise<ArrayBuffer | null> {
    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = 'image/*, */*';
    const sameOrigin = this.isSameOriginUrl(url);
    if (sameOrigin && token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    if (sameOrigin) {
      const cookieStr = this.getCookieHeader();
      if (cookieStr.length > 0) {
        header['Cookie'] = cookieStr;
      }
    }
    const reqOpts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 12000,
      readTimeout: 25000,
      usingCache: true
    };
    if (this.allowSelfSigned) {
      reqOpts.remoteValidation = 'skip';
    }
    try {
      const resp = await client.request(url, reqOpts);
      if (resp.responseCode === 401 && sameOrigin && token.length > 0) {
        this.notifyAuthIfExpired(url, token, 401, '');
      }
      if (resp.responseCode >= 200 && resp.responseCode < 300 && resp.result instanceof ArrayBuffer && resp.result.byteLength > 0) {
        return resp.result as ArrayBuffer;
      }
      return null;
    } catch {
      return null;
    } finally {
      client.destroy();
    }
  }

  /** 上传 Multipart 二进制文件（同源凭据守卫）。 */
  async uploadMultipart(
    url: string,
    token: string,
    fieldName: string,
    fileName: string,
    mimeType: string,
    bytes: Uint8Array
  ): Promise<NativeHttpResponse> {
    const boundary = `----MPHarmonyBoundary${Date.now()}`;
    const encoder = new util.TextEncoder();
    const safeName = fileName.replace(/"/g, '_');
    const headStr = `--${boundary}\r\nContent-Disposition: form-data; name="${fieldName}"; filename="${safeName}"\r\nContent-Type: ${mimeType}\r\n\r\n`;
    const tailStr = `\r\n--${boundary}--\r\n`;
    const headBytes = encoder.encodeInto(headStr);
    const tailBytes = encoder.encodeInto(tailStr);
    const combined = new Uint8Array(headBytes.length + bytes.length + tailBytes.length);
    combined.set(headBytes, 0);
    combined.set(bytes, headBytes.length);
    combined.set(tailBytes, headBytes.length + bytes.length);

    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = 'application/json, */*';
    header['Content-Type'] = `multipart/form-data; boundary=${boundary}`;
    const sameOrigin = this.isSameOriginUrl(url);
    if (sameOrigin && token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    if (sameOrigin) {
      const cookieStr = this.getCookieHeader();
      if (cookieStr.length > 0) {
        header['Cookie'] = cookieStr;
      }
    }

    const reqOpts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: combined.buffer,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 20000,
      readTimeout: 60000,
      usingCache: false
    };
    if (this.allowSelfSigned) {
      reqOpts.remoteValidation = 'skip';
    }

    try {
      const resp = await client.request(url, reqOpts);
      this.captureSetCookies(url, resp.header);
      const text = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result ?? '');
      this.notifyAuthIfExpired(url, token, resp.responseCode, text);
      return { status: resp.responseCode, body: text };
    } finally {
      client.destroy();
    }
  }

  /**
   * 发起真实 SSE 流式 POST 请求（基于 `requestInStream` 增量分块解码 + 同源凭据守卫）。
   */
  async streamSsePost(
    url: string,
    token: string,
    payloadJson: string,
    extraHeaders: Record<string, string>,
    onEvent: (ev: SseEventChunk) => void
  ): Promise<number> {
    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = 'text/event-stream, application/json, */*';
    header['Content-Type'] = 'application/json';
    const sameOrigin = this.isSameOriginUrl(url);
    if (sameOrigin && token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    if (sameOrigin) {
      const cookieStr = this.getCookieHeader();
      if (cookieStr.length > 0) {
        header['Cookie'] = cookieStr;
      }
    }
    const keys = Object.keys(extraHeaders);
    for (let i = 0; i < keys.length; i++) {
      header[keys[i]] = extraHeaders[keys[i]];
    }

    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    let pending = '';
    let currentEvent = 'message';
    let dataLines: string[] = [];
    let emittedAny = false;
    let rawFallback = '';

    const flushEvent = () => {
      if (dataLines.length === 0) { return; }
      const joined = dataLines.join('\n').trim();
      dataLines = [];
      const evName = currentEvent || 'message';
      currentEvent = 'message';
      if (joined.length > 0 && joined !== '[DONE]') {
        emittedAny = true;
        onEvent({ event: evName, data: joined });
      }
    };

    const consumeLines = (text: string) => {
      rawFallback += text;
      pending += text;
      const lines = pending.split('\n');
      pending = lines.pop() ?? '';
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i].replace(/\r$/, '');
        if (line.length === 0) {
          flushEvent();
        } else if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          dataLines.push(line.substring(5).trim());
        }
      }
    };

    client.on('headersReceive', (hdr: Object) => {
      this.captureSetCookies(url, hdr);
    });
    client.on('dataReceive', (buf: ArrayBuffer) => {
      const chunkStr = decoder.decodeToString(new Uint8Array(buf), { stream: true });
      consumeLines(chunkStr);
    });

    const streamOpts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: payloadJson,
      connectTimeout: 20000,
      readTimeout: 180000,
      usingCache: false
    };
    if (this.allowSelfSigned) {
      streamOpts.remoteValidation = 'skip';
    }

    try {
      const code = await client.requestInStream(url, streamOpts);
      if (pending.length > 0) {
        consumeLines('\n');
      }
      flushEvent();
      this.notifyAuthIfExpired(url, token, code, rawFallback);
      if (!emittedAny && rawFallback.trim().length > 0) {
        onEvent({ event: 'message', data: rawFallback.trim() });
      }
      return code;
    } finally {
      try {
        client.off('headersReceive');
        client.off('dataReceive');
      } catch {
        // ignore listener cleanup
      }
      client.destroy();
    }
  }

  /** 兼容旧签名：指向真实 V3 `/api/v1/message/agent/stream`。 */
  async streamAgentSse(
    baseUrl: string,
    token: string,
    prompt: string,
    onChunk: (delta: string) => void
  ): Promise<void> {
    this.setBaseUrl(baseUrl);
    const url = RustCoreBridge.buildV3EndpointUrl(baseUrl, ['message', 'agent', 'stream']);
    const payload = JSON.stringify({
      text: prompt,
      session_id: 'harmony-default',
      files: [],
      images: []
    });
    await this.streamSsePost(
      url,
      token,
      payload,
      { 'X-MoviePilot-Agent-Interaction': '1' },
      (ev: SseEventChunk) => onChunk(ev.data)
    );
  }
}
