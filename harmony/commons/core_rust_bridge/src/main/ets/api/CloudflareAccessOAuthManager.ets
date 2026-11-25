import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { OAuthServerMetadata, RustCoreBridge } from '../bridge/RustCoreBridge';
import { NativeHuksStore } from '../security/NativeHuksStore';

export interface CloudflareAccessSession {
  serverOrigin: string;
  accessToken: string;
  refreshToken?: string;
  expiresAtEpochMs?: number;
  clientId: string;
  tokenEndpoint: string;
  issuer: string;
}

interface PendingCallbackSlot {
  resolve: (url: string) => void;
  reject: (err: Error) => void;
  timerId: number;
}

function bytesToHex(bytes: Uint8Array): string {
  const hexChars = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i] & 0xff;
    out += hexChars.charAt((b >> 4) & 0x0f) + hexChars.charAt(b & 0x0f);
  }
  return out;
}

function generateEntropyHex(): string {
  try {
    const rand = cryptoFramework.createRandom();
    const blob = rand.generateRandomSync(24);
    if (blob && blob.data && blob.data.length > 0) {
      return bytesToHex(blob.data);
    }
  } catch {
    // fallback if hardware RNG unavailable
  }
  return `${Date.now()}_${Math.floor(Math.random() * 1e9)}`;
}

/**
 * 鸿蒙端 Cloudflare Access Managed OAuth（RFC 9728 / RFC 8414 / RFC 7591 / RFC 7636 PKCE）管理器：
 * - 通过系统浏览器发起 OAuth 授权，经 `moviepilot://oauth/callback` 回流 `EntryAbility.handleIncomingWant`；
 * - 凭据按规范化源键加密保存在 `NativeHuksStore`（HUKS AES-256-GCM）；
 * - 同源请求自动合并 `Cookie: CF_Authorization=...` 与 `cf-access-token`，绝不覆盖 MoviePilot `Authorization: Bearer`。
 */
export class CloudflareAccessOAuthManager {
  static readonly REDIRECT_URI: string = 'moviepilot://oauth/callback';

  private static instance: CloudflareAccessOAuthManager | null = null;
  private memoryCache: Map<string, CloudflareAccessSession> = new Map<string, CloudflareAccessSession>();
  private pendingSlot: PendingCallbackSlot | null = null;

  static shared(): CloudflareAccessOAuthManager {
    if (!CloudflareAccessOAuthManager.instance) {
      CloudflareAccessOAuthManager.instance = new CloudflareAccessOAuthManager();
    }
    return CloudflareAccessOAuthManager.instance;
  }

  /** 计算规范化源键 `scheme://host[:port]`（去掉默认端口）。 */
  static normalizedOriginKey(rawUrl: string): string {
    const trimmed = (rawUrl ?? '').trim();
    const m = /^(https?):\/\/([^\/\?#]+)/i.exec(trimmed);
    if (!m || !m[1] || !m[2]) {
      return '';
    }
    const scheme = m[1].toLowerCase();
    let authority = m[2].toLowerCase();
    if (scheme === 'https' && authority.endsWith(':443')) {
      authority = authority.substring(0, authority.length - 4);
    } else if (scheme === 'http' && authority.endsWith(':80')) {
      authority = authority.substring(0, authority.length - 3);
    }
    return `${scheme}://${authority}`;
  }

  /** 从 HUKS 预热指定服务器源的 Cloudflare Access 会话至内存表。 */
  async hydrateOrigin(serverUrl: string): Promise<void> {
    const origin = CloudflareAccessOAuthManager.normalizedOriginKey(serverUrl);
    if (!origin || this.memoryCache.has(origin)) {
      return;
    }
    try {
      const raw = await NativeHuksStore.shared().loadCloudflareSessionJson(origin);
      if (!raw) {
        return;
      }
      const parsed = JSON.parse(raw) as CloudflareAccessSession;
      if (parsed && parsed.accessToken && parsed.accessToken.trim().length > 0) {
        this.memoryCache.set(origin, parsed);
      }
    } catch {
      // ignore corrupted entry
    }
  }

  /** 是否已为指定服务器缓存 Cloudflare Access 会话。 */
  hasSession(serverUrl: string): boolean {
    const origin = CloudflareAccessOAuthManager.normalizedOriginKey(serverUrl);
    if (!origin) { return false; }
    const sess = this.memoryCache.get(origin);
    return Boolean(sess && sess.accessToken && sess.accessToken.trim().length > 0);
  }

  /** 按严格同源源键读取 CF Access 令牌，无记录或跨源时返回空串。 */
  getAccessTokenForUrl(requestUrl: string): string {
    const origin = CloudflareAccessOAuthManager.normalizedOriginKey(requestUrl);
    if (!origin) { return ''; }
    const sess = this.memoryCache.get(origin);
    return sess && sess.accessToken ? sess.accessToken.trim() : '';
  }

  /** 清除指定服务器的 Cloudflare Access 授权。 */
  async clearSession(serverUrl: string): Promise<void> {
    const origin = CloudflareAccessOAuthManager.normalizedOriginKey(serverUrl);
    if (!origin) { return; }
    this.memoryCache.delete(origin);
    await NativeHuksStore.shared().clearCloudflareSession(origin);
  }

  /** 由 `EntryAbility.handleIncomingWant` 在收到 `moviepilot://oauth/callback?...` 时投递回调 URL。 */
  handleCallbackUrl(callbackUrl: string): boolean {
    if (!this.pendingSlot) {
      return false;
    }
    const slot = this.pendingSlot;
    this.pendingSlot = null;
    clearTimeout(slot.timerId);
    slot.resolve(callbackUrl);
    return true;
  }

  /** 若当前服务器的 CF Access 会话临近过期且拥有 `refresh_token`，静默刷新并落盘。 */
  async refreshIfNeeded(serverUrl: string, allowSelfSigned: boolean): Promise<void> {
    await this.hydrateOrigin(serverUrl);
    const origin = CloudflareAccessOAuthManager.normalizedOriginKey(serverUrl);
    if (!origin) { return; }
    const existing = this.memoryCache.get(origin);
    if (!existing || !existing.refreshToken || !existing.expiresAtEpochMs) {
      return;
    }
    if (Date.now() + 120000 < existing.expiresAtEpochMs) {
      return;
    }
    const form = `grant_type=refresh_token&refresh_token=${encodeURIComponent(existing.refreshToken)}&client_id=${encodeURIComponent(existing.clientId)}`;
    const resp = await this.rawRequest(
      existing.tokenEndpoint,
      http.RequestMethod.POST,
      form,
      'application/x-www-form-urlencoded',
      allowSelfSigned
    );
    if (resp.status < 200 || resp.status >= 300) {
      return;
    }
    try {
      const obj = JSON.parse(resp.body) as Record<string, Object>;
      const newAccess = String(obj['access_token'] ?? '').trim();
      if (!newAccess) { return; }
      const newRefresh = String(obj['refresh_token'] ?? '').trim();
      const expiresIn = Number(obj['expires_in']);
      const updated: CloudflareAccessSession = {
        serverOrigin: existing.serverOrigin,
        accessToken: newAccess,
        refreshToken: newRefresh.length > 0 ? newRefresh : existing.refreshToken,
        expiresAtEpochMs: Number.isFinite(expiresIn) && expiresIn > 0 ? Date.now() + expiresIn * 1000 : existing.expiresAtEpochMs,
        clientId: existing.clientId,
        tokenEndpoint: existing.tokenEndpoint,
        issuer: existing.issuer
      };
      await this.persistSession(updated);
    } catch {
      // keep existing
    }
  }

  /** 执行完整的 Cloudflare Access Managed OAuth 认证流程。 */
  async authenticate(
    serverUrl: string,
    allowSelfSigned: boolean,
    launchBrowser: (authorizeUrl: string) => void
  ): Promise<CloudflareAccessSession> {
    const normalized = RustCoreBridge.normalizeServerAddress(serverUrl);
    const origin = CloudflareAccessOAuthManager.normalizedOriginKey(normalized);
    if (!origin) {
      throw new Error('服务地址无效');
    }
    await this.hydrateOrigin(normalized);

    const hintUrl = await this.probeResourceMetadataHint(normalized, allowSelfSigned);
    const serverMeta = await this.discoverServerMetadata(normalized, hintUrl, allowSelfSigned);

    const existing = this.memoryCache.get(origin);
    let clientId = '';
    if (existing && existing.issuer === serverMeta.issuer && existing.clientId.trim().length > 0) {
      clientId = existing.clientId;
    } else if (serverMeta.registrationEndpoint) {
      clientId = await this.registerDynamicClient(serverMeta.registrationEndpoint, allowSelfSigned);
    } else {
      throw new Error('Cloudflare Access 未提供动态客户端注册端点，请检查 OAuth 应用配置');
    }

    const pkce = RustCoreBridge.generatePkcePair(generateEntropyHex());
    const authorizeUrl = RustCoreBridge.buildOAuthAuthorizeUrl(
      serverMeta.authorizationEndpoint,
      clientId,
      CloudflareAccessOAuthManager.REDIRECT_URI,
      pkce.codeChallenge,
      pkce.state,
      'openid email profile offline_access'
    );

    const callbackUrl = await this.awaitBrowserCallback(authorizeUrl, launchBrowser);
    const parsed = RustCoreBridge.parseOAuthCallbackUrl(callbackUrl, pkce.state);
    if (!parsed.valid || !parsed.code) {
      throw new Error(parsed.errorDescription || parsed.error || 'Cloudflare Access 回调校验失败，请重试');
    }

    const session = await this.exchangeCodeForToken(
      origin,
      serverMeta,
      clientId,
      parsed.code,
      pkce.codeVerifier,
      allowSelfSigned
    );
    await this.persistSession(session);
    return session;
  }

  private async persistSession(session: CloudflareAccessSession): Promise<void> {
    this.memoryCache.set(session.serverOrigin, session);
    await NativeHuksStore.shared().saveCloudflareSessionJson(session.serverOrigin, JSON.stringify(session));
  }

  private async awaitBrowserCallback(
    authorizeUrl: string,
    launchBrowser: (url: string) => void
  ): Promise<string> {
    if (this.pendingSlot) {
      clearTimeout(this.pendingSlot.timerId);
      this.pendingSlot.reject(new Error('已发起新的认证会话'));
      this.pendingSlot = null;
    }
    return new Promise<string>((resolve, reject) => {
      const timerId = setTimeout(() => {
        if (this.pendingSlot && this.pendingSlot.timerId === timerId) {
          this.pendingSlot = null;
          reject(new Error('Cloudflare Access 认证等待超时，请重试'));
        }
      }, 5 * 60 * 1000);
      this.pendingSlot = { resolve: resolve, reject: reject, timerId: timerId };
      try {
        launchBrowser(authorizeUrl);
      } catch (e) {
        clearTimeout(timerId);
        this.pendingSlot = null;
        reject(new Error(`无法拉起系统浏览器：${(e as Error).message}`));
      }
    });
  }

  private async probeResourceMetadataHint(serverUrl: string, allowSelfSigned: boolean): Promise<string> {
    try {
      const probeUrl = RustCoreBridge.buildV3EndpointUrl(serverUrl, ['system', 'setup-status']);
      const resp = await this.rawRequest(probeUrl, http.RequestMethod.GET, '', 'application/json', allowSelfSigned);
      const challenge = RustCoreBridge.detectCloudflareAccessChallenge(resp.status, resp.headers, resp.body, probeUrl);
      return challenge.resourceMetadataUrl ?? '';
    } catch {
      return '';
    }
  }

  private async discoverServerMetadata(
    serverUrl: string,
    hintUrl: string,
    allowSelfSigned: boolean
  ): Promise<OAuthServerMetadata> {
    const candidates = RustCoreBridge.buildOAuthDiscoveryUrls(serverUrl, hintUrl);
    const authServers: string[] = [];

    for (let i = 0; i < candidates.length; i++) {
      const resp = await this.rawRequest(candidates[i], http.RequestMethod.GET, '', 'application/json', allowSelfSigned);
      if (resp.status < 200 || resp.status >= 300) { continue; }
      const direct = RustCoreBridge.parseOAuthServerMetadata(resp.body);
      if (direct) { return direct; }
      const servers = RustCoreBridge.parseProtectedResourceMetadata(resp.body);
      for (let j = 0; j < servers.length; j++) {
        if (!authServers.includes(servers[j])) {
          authServers.push(servers[j]);
        }
      }
    }

    for (let i = 0; i < authServers.length; i++) {
      const resp = await this.rawRequest(authServers[i], http.RequestMethod.GET, '', 'application/json', allowSelfSigned);
      if (resp.status < 200 || resp.status >= 300) { continue; }
      const meta = RustCoreBridge.parseOAuthServerMetadata(resp.body);
      if (meta) { return meta; }
    }

    throw new Error('未能发现 Cloudflare Access OAuth 元数据，请确认服务已开启 Cloudflare Access OAuth');
  }

  private async registerDynamicClient(endpoint: string, allowSelfSigned: boolean): Promise<string> {
    const payload = JSON.stringify({
      client_name: 'MoviePilot HarmonyOS',
      redirect_uris: [CloudflareAccessOAuthManager.REDIRECT_URI],
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      token_endpoint_auth_method: 'none'
    });
    const resp = await this.rawRequest(endpoint, http.RequestMethod.POST, payload, 'application/json', allowSelfSigned);
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(`Cloudflare Access 客户端注册失败（HTTP ${resp.status}）`);
    }
    const obj = JSON.parse(resp.body) as Record<string, Object>;
    const clientId = String(obj['client_id'] ?? '').trim();
    if (!clientId) {
      throw new Error('Cloudflare Access 注册响应缺少 client_id');
    }
    return clientId;
  }

  private async exchangeCodeForToken(
    origin: string,
    serverMeta: OAuthServerMetadata,
    clientId: string,
    code: string,
    codeVerifier: string,
    allowSelfSigned: boolean
  ): Promise<CloudflareAccessSession> {
    const form = `grant_type=authorization_code&code=${encodeURIComponent(code)}` +
      `&redirect_uri=${encodeURIComponent(CloudflareAccessOAuthManager.REDIRECT_URI)}` +
      `&client_id=${encodeURIComponent(clientId)}&code_verifier=${encodeURIComponent(codeVerifier)}`;
    const resp = await this.rawRequest(
      serverMeta.tokenEndpoint,
      http.RequestMethod.POST,
      form,
      'application/x-www-form-urlencoded',
      allowSelfSigned
    );
    if (resp.status < 200 || resp.status >= 300) {
      throw new Error(`换取 Cloudflare Access 令牌失败（HTTP ${resp.status}）`);
    }
    const obj = JSON.parse(resp.body) as Record<string, Object>;
    const accessToken = String(obj['access_token'] ?? '').trim();
    if (!accessToken) {
      throw new Error('Cloudflare Access 未返回有效 access_token');
    }
    const refreshToken = String(obj['refresh_token'] ?? '').trim();
    const expiresIn = Number(obj['expires_in']);
    return {
      serverOrigin: origin,
      accessToken: accessToken,
      refreshToken: refreshToken.length > 0 ? refreshToken : undefined,
      expiresAtEpochMs: Number.isFinite(expiresIn) && expiresIn > 0 ? Date.now() + expiresIn * 1000 : undefined,
      clientId: clientId,
      tokenEndpoint: serverMeta.tokenEndpoint,
      issuer: serverMeta.issuer
    };
  }

  private async rawRequest(
    url: string,
    method: http.RequestMethod,
    body: string,
    contentType: string,
    allowSelfSigned: boolean
  ): Promise<RawOAuthResponse> {
    const client = http.createHttp();
    const header: Record<string, string> = {};
    header['Accept'] = 'application/json';
    if (body.length > 0 || method === http.RequestMethod.POST) {
      header['Content-Type'] = contentType;
    }
    const opts: http.HttpRequestOptions = {
      method: method,
      header: header,
      extraData: body.length > 0 ? body : undefined,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000,
      usingCache: false
    };
    if (allowSelfSigned) {
      opts.remoteValidation = 'skip';
    }
    try {
      const resp = await client.request(url, opts);
      const outHeaders: Record<string, string> = {};
      if (resp.header) {
        const rec = resp.header as Record<string, Object>;
        const keys = Object.keys(rec);
        for (let i = 0; i < keys.length; i++) {
          const v = rec[keys[i]];
          if (v !== undefined && v !== null) {
            outHeaders[keys[i]] = String(v);
          }
        }
      }
      const text = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result ?? '');
      return { status: resp.responseCode, body: text, headers: outHeaders };
    } catch {
      return { status: 0, body: '', headers: {} };
    } finally {
      client.destroy();
    }
  }
}

interface RawOAuthResponse {
  status: number;
  body: string;
  headers: Record<string, string>;
}
