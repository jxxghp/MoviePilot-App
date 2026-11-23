import { rcp } from '@kit.RemoteCommunicationKit';
import { RustCoreBridge } from '../bridge/RustCoreBridge';

/** 原生网络响应快照。 */
export interface NativeHttpResponse {
  status: number;
  body: string;
}

/**
 * ADR-01 鸿蒙原生网络传输层（基于 `@kit.RemoteCommunicationKit` rcp）：
 * 自动尊重系统代理、VPN、IPv6 及自签名 NAS 证书配置，严禁携带认证头的自动重定向。
 */
export class NativeRcpTransport {
  private allowSelfSigned: boolean = false;

  setAllowSelfSigned(allow: boolean): void {
    this.allowSelfSigned = allow;
  }

  /** 执行 REST JSON / Form 请求。 */
  async execute(
    url: string,
    method: string = 'GET',
    token: string = '',
    body: string = '',
    contentType: string = 'application/json'
  ): Promise<NativeHttpResponse> {
    const headers: rcp.RequestHeaders = {
      'content-type': contentType
    };
    if (token.length > 0) {
      headers['authorization'] = `Bearer ${token}`;
    }
    const securityConfig: rcp.SecurityConfiguration = {
      remoteValidation: this.allowSelfSigned ? 'skip' : 'system'
    };
    const session = rcp.createSession({
      requestConfiguration: {
        security: securityConfig,
        transfer: {
          autoRedirect: false,
          timeout: { connectMs: 15000, transferMs: 30000 }
        }
      }
    });
    try {
      const req = new rcp.Request(url, method.toUpperCase(), headers, body.length > 0 ? body : undefined);
      const resp = await session.fetch(req);
      return {
        status: resp.statusCode,
        body: resp.toString() ?? ''
      };
    } finally {
      session.close();
    }
  }

  /** 发起 AI 智能助手 SSE 流式请求并通过回调逐帧推送事件。 */
  async streamAgentSse(
    baseUrl: string,
    token: string,
    prompt: string,
    onChunk: (delta: string) => void
  ): Promise<void> {
    const url = RustCoreBridge.buildV3EndpointUrl(baseUrl, ['agent', 'chat']);
    const resp = await this.execute(
      url,
      'POST',
      token,
      JSON.stringify({ message: prompt, session_id: 'harmony-default' })
    );
    const lines = resp.body.split('\n');
    for (const line of lines) {
      if (line.startsWith('data:')) {
        const data = line.substring(5).trim();
        if (data && data !== '[DONE]') {
          onChunk(data);
        }
      }
    }
  }
}
