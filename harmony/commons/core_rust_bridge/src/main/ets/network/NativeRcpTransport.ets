import { http } from '@kit.NetworkKit';
import { RustCoreBridge } from '../bridge/RustCoreBridge';

interface AgentChatPayload {
  message: string;
  session_id: string;
}

/** 原生网络响应快照。 */
export interface NativeHttpResponse {
  status: number;
  body: string;
}

/**
 * ADR-01 鸿蒙原生网络传输层（基于 `@kit.NetworkKit` 系统 HTTP 栈）：
 * - 完整保持同源 Cookie（登录态与图片代理 session cookie）
 * - 支持 Bearer Token 鉴权、表单与 JSON 编码
 * - 自动适配局域网 IPv4/IPv6、端口映射与反代子路径
 */
export class NativeRcpTransport {
  private allowSelfSigned: boolean = false;
  private cookieJar: Map<string, string> = new Map<string, string>();

  setAllowSelfSigned(allow: boolean): void {
    this.allowSelfSigned = allow;
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

  private captureSetCookies(headerObj: Object | undefined): void {
    if (!headerObj) {
      return;
    }
    const headers = headerObj as Record<string, Object>;
    const raw = headers['set-cookie'] ?? headers['Set-Cookie'];
    if (!raw) {
      return;
    }
    const entries: string[] = Array.isArray(raw) ? (raw as string[]) : [String(raw)];
    for (let i = 0; i < entries.length; i++) {
      const firstPart = entries[i].split(';')[0].trim();
      const eqIdx = firstPart.indexOf('=');
      if (eqIdx > 0) {
        const name = firstPart.substring(0, eqIdx).trim();
        const val = firstPart.substring(eqIdx + 1).trim();
        this.cookieJar.set(name, val);
      }
    }
  }

  /** 执行 REST JSON / Form 请求。 */
  async execute(
    url: string,
    method: string = 'GET',
    token: string = '',
    body: string = '',
    contentType: string = 'application/json'
  ): Promise<NativeHttpResponse> {
    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = 'application/json, text/plain, */*';
    if (body.length > 0 || method.toUpperCase() === 'POST' || method.toUpperCase() === 'PUT') {
      header['Content-Type'] = contentType;
    }
    if (token.length > 0) {
      header['Authorization'] = `Bearer ${token}`;
    }
    const cookieStr = this.getCookieHeader();
    if (cookieStr.length > 0) {
      header['Cookie'] = cookieStr;
    }

    let httpMethod: http.RequestMethod = http.RequestMethod.GET;
    const upper = method.toUpperCase();
    if (upper === 'POST') {
      httpMethod = http.RequestMethod.POST;
    } else if (upper === 'PUT') {
      httpMethod = http.RequestMethod.PUT;
    } else if (upper === 'DELETE') {
      httpMethod = http.RequestMethod.DELETE;
    }

    try {
      const resp = await client.request(url, {
        method: httpMethod,
        header: header,
        extraData: body.length > 0 ? body : undefined,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingCache: false
      });
      this.captureSetCookies(resp.header);
      const text = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result ?? '');
      return {
        status: resp.responseCode,
        body: text
      };
    } finally {
      client.destroy();
    }
  }

  /** 发起 AI 智能助手请求并逐行解析 SSE / JSON 响应。 */
  async streamAgentSse(
    baseUrl: string,
    token: string,
    prompt: string,
    onChunk: (delta: string) => void
  ): Promise<void> {
    const url = RustCoreBridge.buildV3EndpointUrl(baseUrl, ['agent', 'chat']);
    const payload: AgentChatPayload = { message: prompt, session_id: 'harmony-default' };
    const resp = await this.execute(
      url,
      'POST',
      token,
      JSON.stringify(payload)
    );
    const lines = resp.body.split('\n');
    let emitted = false;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.startsWith('data:')) {
        const data = line.substring(5).trim();
        if (data && data !== '[DONE]') {
          emitted = true;
          onChunk(data);
        }
      }
    }
    if (!emitted && resp.body.trim().length > 0) {
      onChunk(resp.body.trim());
    }
  }
}
