import { http } from '@kit.NetworkKit';
import { MoviePilotRepository, RustCoreBridge } from '@moviepilot/core_rust_bridge';

/** 在插件容器绑定的会话内代理资源，动态读取原生 Cookie 并限制刷新及重定向。 */
export class HarmonyPluginResourceClient {
  private serverUrl: string;
  private authToken: string;
  private priming: Promise<void> | null = null;

  /** 绑定容器所属实例和令牌，后续账号切换不会改变旧容器归属。 */
  constructor(serverUrl: string, authToken: string) {
    this.serverUrl = serverUrl.replace(/\/+$/, '');
    this.authToken = authToken;
  }

  /** 检查容器仍属于当前原生会话，防止旧资源请求借用新会话 Cookie。 */
  hasActiveSession(): boolean {
    const repo = MoviePilotRepository.shared();
    return this.authToken.length > 0 && repo.token === this.authToken &&
      repo.baseUrl.replace(/\/+$/, '') === this.serverUrl;
  }

  /** 合并同一容器的首次 Cookie 换取请求，兼容后端自定义资源 Cookie 名。 */
  private async primeResourceCookie(): Promise<void> {
    if (!this.hasActiveSession()) { throw new Error('No active plugin session'); }
    const repo = MoviePilotRepository.shared();
    const url = RustCoreBridge.buildV3EndpointUrl(this.serverUrl, ['media', 'source'], {});
    await repo.transport.execute(url, 'GET', this.authToken);
    if (!this.hasActiveSession()) { throw new Error('Plugin session changed'); }
  }

  /** 首次请求等待资源 Cookie；资源 401 仅刷新重试一次，不将其误判为 Bearer 失效。 */
  async fetch(validatedApiPath: string, locale: string): Promise<http.HttpResponse> {
    if (!this.priming) { this.priming = this.primeResourceCookie(); }
    await this.priming;
    const response = await this.request(validatedApiPath, locale);
    if (response.responseCode !== 401) { return response; }
    await this.primeResourceCookie();
    return this.request(validatedApiPath, locale);
  }

  /** 对已校验的实例资源路径使用最新 Cookie，禁止把凭据随跳转发送至其他来源。 */
  private async request(validatedApiPath: string, locale: string): Promise<http.HttpResponse> {
    const url = `${this.serverUrl}${validatedApiPath}`;
    if (!this.hasActiveSession() || !RustCoreBridge.serverAddressContains(this.serverUrl, url)) {
      throw new Error('Invalid plugin resource session');
    }
    const transport = MoviePilotRepository.shared().transport;
    const headers: Record<string, string> = {
      'Authorization': `Bearer ${this.authToken}`,
      'X-MoviePilot-Locale': locale || 'zh-CN'
    };
    const cookie = transport.getCookieHeaderForUrl(url);
    if (cookie.length > 0) { headers['Cookie'] = cookie; }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: 15000,
      readTimeout: 30000,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false,
      maxRedirects: 0
    };
    if (transport.isAllowSelfSigned()) { options.remoteValidation = 'skip'; }
    const request = http.createHttp();
    try {
      const response = await request.request(url, options);
      if (!this.hasActiveSession()) { throw new Error('Plugin session changed'); }
      return response;
    } finally {
      request.destroy();
    }
  }
}
