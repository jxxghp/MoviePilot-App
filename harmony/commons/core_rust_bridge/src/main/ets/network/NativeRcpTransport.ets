import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { RustCoreBridge } from '../bridge/RustCoreBridge';

/** 原生网络响应快照。 */
export interface NativeHttpResponse {
  status: number;
  body: string;
  etag?: string;
  headers?: Record<string, string>;
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
export interface ByteRangeFetchResult {
  data: ArrayBuffer;
  totalSize: number;
  isPartial: boolean;
}

export class NativeRcpTransport {
  private baseUrl: string = '';
  private allowSelfSigned: boolean = false;
  private cookieJar: Map<string, string> = new Map<string, string>();
  onAuthExpired: (() => void) | null = null;
  cfAccessTokenProvider: ((requestUrl: string) => string) | null = null;

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

  /** 仅当候选 URL 严格同源于当前实例时返回已存储的 Cookie 请求头（含 `resource_token` 与 `CF_Authorization`），严禁跨源泄露。 */
  getCookieHeaderForUrl(url: string): string {
    if (!this.isSameOriginUrl(url)) {
      return '';
    }
    const base = this.getCookieHeader();
    const cfToken = this.cfAccessTokenProvider ? this.cfAccessTokenProvider(url).trim() : '';
    return cfToken.length > 0 ? RustCoreBridge.mergeCfAccessCookie(base, cfToken) : base;
  }

  /** 为同源请求安全附加 `Cookie: CF_Authorization=...`（保留现有同源 Cookie）与 `cf-access-token`，绝不覆盖 `Authorization`。 */
  private applyCloudflareHeaders(header: Record<string, string>, url: string): void {
    if (!this.isSameOriginUrl(url) || !this.cfAccessTokenProvider) {
      return;
    }
    const cfToken = this.cfAccessTokenProvider(url).trim();
    if (cfToken.length === 0) {
      return;
    }
    const existingCookie = header['Cookie'] ?? '';
    const merged = RustCoreBridge.mergeCfAccessCookie(existingCookie, cfToken);
    if (merged.length > 0) {
      header['Cookie'] = merged;
    }
    header['cf-access-token'] = cfToken;
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
    this.applyCloudflareHeaders(header, url);

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
      let respEtag: string | undefined = undefined;
      const respHeaders: Record<string, string> = {};
      if (resp.header) {
        const hRec = resp.header as Record<string, Object>;
        const hKeys = Object.keys(hRec);
        for (let i = 0; i < hKeys.length; i++) {
          const v = hRec[hKeys[i]];
          if (v !== undefined && v !== null) {
            respHeaders[hKeys[i]] = String(v);
          }
        }
        const rawEtag = hRec['etag'] ?? hRec['ETag'];
        if (rawEtag !== undefined && rawEtag !== null) {
          const etagStr = String(rawEtag).trim();
          if (etagStr.length > 0) {
            respEtag = etagStr;
          }
        }
      }
      return {
        status: resp.responseCode,
        body: text,
        etag: respEtag,
        headers: respHeaders
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
      this.applyCloudflareHeaders(header, url);
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

  /** 拉取受体积上限保护的同源二进制载荷（用于外挂字幕 <= 16MB、LRC 歌词 <= 2MB 与封面解码）。 */
  async fetchBytesBounded(url: string, token: string = '', maxBytes: number = 16777216): Promise<ArrayBuffer | null> {
    if (!this.isSameOriginUrl(url)) {
      return null;
    }
    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = '*/*';
    header['Accept-Encoding'] = 'identity';
    if (token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    const cookieStr = this.getCookieHeaderForUrl(url);
    if (cookieStr.length > 0) {
      header['Cookie'] = cookieStr;
    }
    this.applyCloudflareHeaders(header, url);
    const reqOpts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 15000,
      readTimeout: 45000,
      usingCache: false
    };
    if (this.allowSelfSigned) {
      reqOpts.remoteValidation = 'skip';
    }
    try {
      const resp = await client.request(url, reqOpts);
      this.captureSetCookies(url, resp.header, resp.cookies ?? '');
      if (resp.responseCode === 401 || resp.responseCode === 403) {
        this.notifyAuthIfExpired(url, token, resp.responseCode, '');
      }
      if (
        resp.responseCode >= 200 &&
        resp.responseCode < 300 &&
        resp.result instanceof ArrayBuffer &&
        resp.result.byteLength > 0 &&
        resp.result.byteLength <= maxBytes
      ) {
        return resp.result as ArrayBuffer;
      }
      return null;
    } catch {
      return null;
    } finally {
      client.destroy();
    }
  }

  /**
   * 按字节区间（`Range: bytes=start-end`）拉取音频头/尾元数据窗口：
   * 同源请求附加当前实例鉴权/Cookie/CF Access 头；跨源请求仅附加调用方显式提供的安全流头，绝不泄露主实例凭据。
   */
  async fetchByteRange(
    url: string,
    startByte: number,
    endInclusive: number,
    token: string = '',
    customHeaders?: Record<string, string>
  ): Promise<ByteRangeFetchResult | null> {
    const cleanUrl = (url ?? '').trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      return null;
    }
    const maxAccept = Math.max(0, endInclusive - startByte + 1) + 4096;
    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Range'] = `bytes=${Math.max(0, Math.floor(startByte))}-${Math.max(0, Math.floor(endInclusive))}`;
    header['Accept'] = '*/*';
    header['Accept-Encoding'] = 'identity';

    if (this.isSameOriginUrl(cleanUrl)) {
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      const cookieStr = this.getCookieHeaderForUrl(cleanUrl);
      if (cookieStr.length > 0) {
        header['Cookie'] = cookieStr;
      }
      this.applyCloudflareHeaders(header, cleanUrl);
    } else if (customHeaders) {
      const keys = Object.keys(customHeaders);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        const lower = k.trim().toLowerCase();
        const v = customHeaders[k];
        if (lower.length > 0 && v && v.length > 0 && lower !== 'range' && lower !== 'accept-encoding') {
          header[k] = v;
        }
      }
    }

    const reqOpts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 12000,
      readTimeout: 25000,
      usingCache: false
    };
    if (this.allowSelfSigned) {
      reqOpts.remoteValidation = 'skip';
    }
    try {
      const resp = await client.request(cleanUrl, reqOpts);
      if (this.isSameOriginUrl(cleanUrl)) {
        this.captureSetCookies(cleanUrl, resp.header, resp.cookies ?? '');
      }
      if ((resp.responseCode !== 206 && resp.responseCode !== 200) || !(resp.result instanceof ArrayBuffer)) {
        return null;
      }
      const rawBuf = resp.result as ArrayBuffer;
      if (rawBuf.byteLength === 0) {
        return null;
      }
      const outBuf = rawBuf.byteLength > maxAccept ? rawBuf.slice(0, maxAccept) : rawBuf;
      let totalSize = -1;
      const respHdr = resp.header as Record<string, string> | undefined;
      if (respHdr) {
        const hdrKeys = Object.keys(respHdr);
        for (let i = 0; i < hdrKeys.length; i++) {
          const hk = hdrKeys[i];
          const hl = hk.toLowerCase();
          if (hl === 'content-range') {
            const cr = String(respHdr[hk] ?? '');
            const slash = cr.lastIndexOf('/');
            if (slash >= 0) {
              const parsed = parseInt(cr.substring(slash + 1).trim(), 10);
              if (Number.isFinite(parsed) && parsed > 0) {
                totalSize = parsed;
              }
            }
          } else if (hl === 'content-length' && resp.responseCode === 200 && totalSize < 0) {
            const parsed = parseInt(String(respHdr[hk] ?? '').trim(), 10);
            if (Number.isFinite(parsed) && parsed > 0) {
              totalSize = parsed;
            }
          }
        }
      }
      return {
        data: outBuf,
        totalSize: totalSize,
        isPartial: resp.responseCode === 206
      };
    } catch {
      return null;
    } finally {
      client.destroy();
    }
  }

  /**
   * 流式下载同源二进制响应并直接落盘至沙盒临时文件（支持 `POST /api/v1/storage/download` 大体积音视频零内存膨胀缓存）。
   */
  async downloadToFile(
    url: string,
    method: string,
    token: string,
    body: string,
    destPath: string
  ): Promise<boolean> {
    if (!this.isSameOriginUrl(url) || !destPath) {
      return false;
    }
    let fileHandle: fileIo.File | null = null;
    try {
      fileHandle = fileIo.openSync(
        destPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE
      );
    } catch {
      return false;
    }

    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = '*/*';
    const upper = method.toUpperCase();
    if (body.length > 0 || upper === 'POST' || upper === 'PUT') {
      header['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    const cookieStr = this.getCookieHeaderForUrl(url);
    if (cookieStr.length > 0) {
      header['Cookie'] = cookieStr;
    }
    this.applyCloudflareHeaders(header, url);

    let writtenBytes = 0;
    let writeFailed = false;
    let errTextSample = '';
    const errDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });

    client.on('headersReceive', (hdr: Object) => {
      this.captureSetCookies(url, hdr);
    });
    client.on('dataReceive', (buf: ArrayBuffer) => {
      if (writeFailed || !fileHandle) {
        return;
      }
      if (writtenBytes < 2048 && buf.byteLength <= 4096) {
        try {
          errTextSample += errDecoder.decodeToString(new Uint8Array(buf), { stream: true });
        } catch {
          // ignore binary decode
        }
      }
      try {
        fileIo.writeSync(fileHandle.fd, buf);
        writtenBytes += buf.byteLength;
      } catch {
        writeFailed = true;
      }
    });

    const streamOpts: http.HttpRequestOptions = {
      method: upper === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: header,
      extraData: body.length > 0 ? body : undefined,
      connectTimeout: 20000,
      readTimeout: 300000,
      usingCache: false
    };
    if (this.allowSelfSigned) {
      streamOpts.remoteValidation = 'skip';
    }

    let ok = false;
    try {
      const code = await client.requestInStream(url, streamOpts);
      if (code === 401 || code === 403) {
        this.notifyAuthIfExpired(url, token, code, errTextSample);
      }
      ok = !writeFailed && code >= 200 && code < 300 && writtenBytes > 0;
    } catch {
      ok = false;
    } finally {
      try {
        client.off('headersReceive');
        client.off('dataReceive');
      } catch {
        // ignore listener cleanup
      }
      client.destroy();
      if (fileHandle) {
        try {
          fileIo.closeSync(fileHandle.fd);
        } catch {
          // ignore close error
        }
      }
      if (!ok) {
        try {
          fileIo.unlinkSync(destPath);
        } catch {
          // ignore unlink error
        }
      }
    }
    return ok;
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
      this.applyCloudflareHeaders(header, url);
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
      this.applyCloudflareHeaders(header, url);
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
