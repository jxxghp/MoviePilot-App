import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/** 已保存服务条目。 */
export interface SavedServerEntry {
  id: string;
  name: string;
  url: string;
  username: string;
  lastUsedMs: number;
  allowSelfSigned?: boolean;
}

/** 跨重启持久化的活动登录会话快照。 */
export interface PersistedAuthSession {
  serverUrl: string;
  token: string;
  userName: string;
  isSuperuser: boolean;
  userAvatar: string;
  keepLogin: boolean;
  allowSelfSigned: boolean;
  userLevel?: number;
}

/** 加密保存的账号密码对。 */
export interface SavedCredentialPair {
  username: string;
  password: string;
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

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.trim();
  const len = Math.floor(clean.length / 2);
  const out = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    const byteVal = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
    out[i] = Number.isFinite(byteVal) ? byteVal : 0;
  }
  return out;
}

function utf8Encode(text: string): Uint8Array {
  const enc = new util.TextEncoder();
  return enc.encodeInto(text);
}

function utf8Decode(bytes: Uint8Array): string {
  const dec = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  return dec.decodeToString(bytes);
}

function randomIv12(): Uint8Array {
  try {
    const rand = cryptoFramework.createRandom();
    const blob = rand.generateRandomSync(12);
    if (blob && blob.data && blob.data.length === 12) {
      return blob.data;
    }
  } catch {
    // fallback if crypto random unavailable
  }
  const fallback = new Uint8Array(12);
  let seed = Date.now() & 0x7fffffff;
  for (let i = 0; i < 12; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    fallback[i] = (seed >> 16) & 0xff;
  }
  return fallback;
}

/**
 * ADR-02 鸿蒙原生安全凭据存储（`@kit.UniversalKeystoreKit` HUKS AES-256-GCM + Preferences）：
 * - 在硬件信任根内通过 HUKS AES-GCM 12-byte Nonce + 128-bit AE Tag 加解密敏感 Token 与账号密码；
 * - 模拟器无硬件 TEE 会话能力时平滑降级至沙盒 Preferences 编码存储，绝不丢失登录状态；
 * - 统一持久化活动登录态、已保存服务器列表、记住的凭据、主题外观配置及桌面卡片快照。
 */
export class NativeHuksStore {
  private static readonly KEY_ALIAS: string = 'moviepilot_huks_aes256_v1';
  private static readonly PREF_NAME: string = 'mp_harmony_secure_store';
  private static readonly KEY_ACTIVE_SESSION: string = 'mp_active_session_v2';
  private static readonly KEY_SAVED_SERVERS: string = 'mp_saved_servers_v2';
  private static readonly KEY_APPEARANCE_JSON: string = 'mp_appearance_snapshot_v2';
  static readonly KEY_WIDGET_SNAPSHOT: string = 'mp_widget_snapshot_v1';
  private static readonly AAD_BYTES: Uint8Array = utf8Encode('MoviePilotHarmonyV3');

  private static instance: NativeHuksStore | null = null;
  private pref: preferences.Preferences | null = null;
  private huksAvailable: boolean = false;
  private memoryFallback: Map<string, string> = new Map<string, string>();

  /** 获取全局共享安全存储单例。 */
  static shared(): NativeHuksStore {
    if (!NativeHuksStore.instance) {
      NativeHuksStore.instance = new NativeHuksStore();
    }
    return NativeHuksStore.instance;
  }

  /** 初始化 Preferences 句柄与 HUKS AES-256-GCM 密钥。 */
  async init(context: common.Context): Promise<void> {
    if (!this.pref) {
      try {
        this.pref = await preferences.getPreferences(context, NativeHuksStore.PREF_NAME);
      } catch {
        // memory fallback remains active
      }
    }
    await this.ensureHuksKey();
  }

  private baseAesGcmParams(purpose: huks.HuksKeyPurpose): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
    ];
  }

  private async ensureHuksKey(): Promise<void> {
    const props = this.baseAesGcmParams(
      huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    );
    try {
      const exists = await huks.isKeyItemExist(NativeHuksStore.KEY_ALIAS, { properties: props });
      if (!exists) {
        await huks.generateKeyItem(NativeHuksStore.KEY_ALIAS, { properties: props });
      }
      this.huksAvailable = true;
    } catch {
      this.huksAvailable = false;
    }
  }

  private async encryptSecret(plaintext: string): Promise<string> {
    if (!plaintext) { return ''; }
    const plainBytes = utf8Encode(plaintext);
    if (this.huksAvailable) {
      let handle: number = -1;
      try {
        const iv = randomIv12();
        const props: huks.HuksParam[] = [
          ...this.baseAesGcmParams(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT),
          { tag: huks.HuksTag.HUKS_TAG_NONCE, value: iv },
          { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: NativeHuksStore.AAD_BYTES },
          { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: new Uint8Array(16) }
        ];
        const initRes = await huks.initSession(NativeHuksStore.KEY_ALIAS, { properties: props });
        handle = initRes.handle;
        const finishOpts: huks.HuksOptions = {
          properties: props,
          inData: plainBytes
        };
        const finRes = await huks.finishSession(handle, finishOpts);
        handle = -1;
        if (finRes && finRes.outData && finRes.outData.length > 16) {
          return `huks1:${bytesToHex(iv)}:${bytesToHex(finRes.outData)}`;
        }
      } catch {
        if (handle !== -1) {
          try { await huks.abortSession(handle, { properties: [] }); } catch { /* ignore */ }
        }
        // 模拟器无完整 HUKS 会话支持时平滑降级
      }
    }
    return `plain1:${bytesToHex(plainBytes)}`;
  }

  private async decryptSecret(stored: string): Promise<string> {
    if (!stored) { return ''; }
    if (stored.startsWith('plain1:')) {
      try {
        return utf8Decode(hexToBytes(stored.substring(7)));
      } catch {
        return '';
      }
    }
    if (stored.startsWith('huks1:')) {
      const parts = stored.split(':');
      if (parts.length === 3) {
        const iv = hexToBytes(parts[1]);
        const cipherAndTag = hexToBytes(parts[2]);
        if (iv.length === 12 && cipherAndTag.length > 16) {
          const cipher = cipherAndTag.slice(0, cipherAndTag.length - 16);
          const aeTag = cipherAndTag.slice(cipherAndTag.length - 16);
          let handle: number = -1;
          try {
            const props: huks.HuksParam[] = [
              ...this.baseAesGcmParams(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT),
              { tag: huks.HuksTag.HUKS_TAG_NONCE, value: iv },
              { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: NativeHuksStore.AAD_BYTES },
              { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: aeTag }
            ];
            const initRes = await huks.initSession(NativeHuksStore.KEY_ALIAS, { properties: props });
            handle = initRes.handle;
            const finRes = await huks.finishSession(handle, {
              properties: props,
              inData: cipher
            });
            handle = -1;
            if (finRes && finRes.outData) {
              return utf8Decode(finRes.outData);
            }
          } catch {
            if (handle !== -1) {
              try { await huks.abortSession(handle, { properties: [] }); } catch { /* ignore */ }
            }
            return '';
          }
        }
      }
      return '';
    }
    return stored;
  }

  /** 保存普通字符串键值至沙盒 Preferences。 */
  async saveString(key: string, value: string): Promise<void> {
    this.memoryFallback.set(key, value);
    if (this.pref) {
      try {
        await this.pref.put(key, value);
        await this.pref.flush();
      } catch {
        // ignore preference flush error
      }
    }
  }

  /** 读取沙盒 Preferences 字符串键值。 */
  async loadString(key: string): Promise<string> {
    if (this.pref) {
      try {
        const v = await this.pref.get(key, '');
        if (typeof v === 'string' && v.length > 0) {
          return v;
        }
      } catch {
        // fallback to memory
      }
    }
    return this.memoryFallback.get(key) ?? '';
  }

  /** 删除指定键值。 */
  async remove(key: string): Promise<void> {
    this.memoryFallback.delete(key);
    if (this.pref) {
      try {
        await this.pref.delete(key);
        await this.pref.flush();
      } catch {
        // ignore
      }
    }
  }

  /** 使用 HUKS AES-GCM 加密保存指定服务的 JWT 访问令牌。 */
  async saveToken(serverUrl: string, token: string): Promise<void> {
    const encrypted = await this.encryptSecret(token);
    await this.saveString(`tok_${serverUrl}`, encrypted);
  }

  /** 解密读取指定服务的 JWT 访问令牌。 */
  async loadToken(serverUrl: string): Promise<string> {
    const raw = await this.loadString(`tok_${serverUrl}`);
    return this.decryptSecret(raw);
  }

  /** 清除指定服务的 JWT 访问令牌。 */
  async clearToken(serverUrl: string): Promise<void> {
    await this.remove(`tok_${serverUrl}`);
  }

  /** 持久化当前活动登录会话（敏感令牌走 HUKS AES-GCM 加密）。 */
  async saveActiveSession(session: PersistedAuthSession): Promise<void> {
    if (session.token.length > 0) {
      await this.saveToken(session.serverUrl, session.token);
    }
    const meta: Record<string, Object> = {};
    meta['serverUrl'] = session.serverUrl;
    meta['userName'] = session.userName;
    meta['isSuperuser'] = session.isSuperuser;
    meta['userAvatar'] = session.userAvatar;
    meta['keepLogin'] = session.keepLogin;
    meta['allowSelfSigned'] = session.allowSelfSigned;
    if (session.userLevel !== undefined && Number.isFinite(session.userLevel)) {
      meta['userLevel'] = Math.trunc(session.userLevel);
    }
    await this.saveString(NativeHuksStore.KEY_ACTIVE_SESSION, JSON.stringify(meta));
  }

  /** 恢复上次活动登录会话（含自动解密的访问令牌）。 */
  async loadActiveSession(): Promise<PersistedAuthSession | null> {
    const raw = await this.loadString(NativeHuksStore.KEY_ACTIVE_SESSION);
    if (!raw) { return null; }
    try {
      const rec = JSON.parse(raw) as Record<string, Object>;
      const serverUrl = String(rec['serverUrl'] ?? '').trim();
      if (!serverUrl) { return null; }
      const keepLogin = Boolean(rec['keepLogin']);
      const token = keepLogin ? await this.loadToken(serverUrl) : '';
      const rawLevel = rec['userLevel'];
      const parsedLevel = rawLevel !== undefined ? Number(rawLevel) : NaN;
      return {
        serverUrl: serverUrl,
        token: token,
        userName: String(rec['userName'] ?? 'admin'),
        isSuperuser: rec['isSuperuser'] !== undefined ? Boolean(rec['isSuperuser']) : true,
        userAvatar: String(rec['userAvatar'] ?? ''),
        keepLogin: keepLogin,
        allowSelfSigned: Boolean(rec['allowSelfSigned']),
        userLevel: Number.isFinite(parsedLevel) && parsedLevel >= 0 ? Math.trunc(parsedLevel) : undefined
      };
    } catch {
      return null;
    }
  }

  /** 登出时清空活动登录态与对应令牌（保留服务器地址以便重新登录）。 */
  async clearActiveSession(): Promise<void> {
    const cur = await this.loadActiveSession();
    if (cur && cur.serverUrl.length > 0) {
      await this.clearToken(cur.serverUrl);
      const retained: Record<string, Object> = {};
      retained['serverUrl'] = cur.serverUrl;
      retained['userName'] = cur.userName;
      retained['isSuperuser'] = false;
      retained['userAvatar'] = '';
      retained['keepLogin'] = false;
      retained['allowSelfSigned'] = cur.allowSelfSigned;
      await this.saveString(NativeHuksStore.KEY_ACTIVE_SESSION, JSON.stringify(retained));
      return;
    }
    await this.remove(NativeHuksStore.KEY_ACTIVE_SESSION);
  }

  /** 加密保存指定服务的记住账号密码。 */
  async saveCredentials(serverUrl: string, username: string, password: string): Promise<void> {
    const payloadObj: Record<string, string> = {};
    payloadObj['u'] = username;
    payloadObj['p'] = password;
    const encrypted = await this.encryptSecret(JSON.stringify(payloadObj));
    await this.saveString(`cred_${serverUrl}`, encrypted);
  }

  /** 解密读取指定服务保存的账号密码。 */
  async loadCredentials(serverUrl: string): Promise<SavedCredentialPair | null> {
    if (!serverUrl) { return null; }
    const raw = await this.loadString(`cred_${serverUrl}`);
    if (!raw) { return null; }
    const plain = await this.decryptSecret(raw);
    if (!plain) { return null; }
    try {
      const rec = JSON.parse(plain) as Record<string, Object>;
      const u = String(rec['u'] ?? '');
      const p = String(rec['p'] ?? '');
      if (!u) { return null; }
      return { username: u, password: p };
    } catch {
      return null;
    }
  }

  /** 删除指定服务保存的账号密码。 */
  async clearCredentials(serverUrl: string): Promise<void> {
    await this.remove(`cred_${serverUrl}`);
  }

  /** 使用 HUKS AES-GCM 加密保存指定规范化源的 Cloudflare Access OAuth 会话 JSON。 */
  async saveCloudflareSessionJson(originKey: string, payloadJson: string): Promise<void> {
    const encrypted = await this.encryptSecret(payloadJson);
    await this.saveString(`cf_oauth_${originKey}`, encrypted);
  }

  /** 解密读取指定规范化源的 Cloudflare Access OAuth 会话 JSON。 */
  async loadCloudflareSessionJson(originKey: string): Promise<string> {
    const raw = await this.loadString(`cf_oauth_${originKey}`);
    if (!raw) { return ''; }
    return this.decryptSecret(raw);
  }

  /** 清除指定规范化源的 Cloudflare Access OAuth 会话。 */
  async clearCloudflareSession(originKey: string): Promise<void> {
    await this.remove(`cf_oauth_${originKey}`);
  }

  /** 保存历史连接服务列表。 */
  async saveServersList(servers: SavedServerEntry[]): Promise<void> {
    await this.saveString(NativeHuksStore.KEY_SAVED_SERVERS, JSON.stringify(servers));
  }

  /** 加载历史连接服务列表。 */
  async loadServersList(): Promise<SavedServerEntry[]> {
    const raw = await this.loadString(NativeHuksStore.KEY_SAVED_SERVERS);
    if (!raw) { return []; }
    try {
      const arr = JSON.parse(raw) as Object[];
      if (!Array.isArray(arr)) { return []; }
      const out: SavedServerEntry[] = [];
      for (let i = 0; i < arr.length; i++) {
        const r = arr[i] as Record<string, Object>;
        const url = String(r['url'] ?? '').trim();
        if (!url) { continue; }
        out.push({
          id: String(r['id'] ?? url),
          name: String(r['name'] ?? url.replace(/^https?:\/\//, '').split('/')[0]),
          url: url,
          username: String(r['username'] ?? ''),
          lastUsedMs: Number(r['lastUsedMs']) || Date.now(),
          allowSelfSigned: Boolean(r['allowSelfSigned'])
        });
      }
      return out;
    } catch {
      return [];
    }
  }

  /** 删除一条已保存服务记录并清理其本地加密凭据。 */
  async removeSavedServer(url: string): Promise<SavedServerEntry[]> {
    const current = await this.loadServersList();
    const filtered = current.filter((s: SavedServerEntry) => s.url !== url);
    await this.saveServersList(filtered);
    await this.clearToken(url);
    await this.clearCredentials(url);
    const originMatch = /^(https?:\/\/[^\/\?#]+)/i.exec(url.trim());
    if (originMatch && originMatch[1]) {
      await this.clearCloudflareSession(originMatch[1].toLowerCase());
    }
    return filtered;
  }

  /** 保存主题外观与模块配置 JSON。 */
  async saveAppearanceJson(json: string): Promise<void> {
    await this.saveString(NativeHuksStore.KEY_APPEARANCE_JSON, json);
  }

  /** 读取主题外观与模块配置 JSON。 */
  async loadAppearanceJson(): Promise<string> {
    return this.loadString(NativeHuksStore.KEY_APPEARANCE_JSON);
  }

  /** 保存桌面服务卡片只读缓存快照。 */
  async saveWidgetSnapshot(json: string): Promise<void> {
    await this.saveString(NativeHuksStore.KEY_WIDGET_SNAPSHOT, json);
  }

  /** 读取桌面服务卡片只读缓存快照。 */
  async loadWidgetSnapshot(): Promise<string> {
    return this.loadString(NativeHuksStore.KEY_WIDGET_SNAPSHOT);
  }

  /** 保存匿名版本统计所需的本机偏好键值（随机 installation_id 或 24 小时节流时间戳）。 */
  async saveUsagePreference(key: string, value: string): Promise<void> {
    await this.saveString(key, value);
  }

  /** 读取匿名版本统计所需的本机偏好键值。 */
  async loadUsagePreference(key: string): Promise<string> {
    return this.loadString(key);
  }
}
