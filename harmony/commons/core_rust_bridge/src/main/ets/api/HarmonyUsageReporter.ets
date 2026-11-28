import { http } from '@kit.NetworkKit';
import { bundleManager } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { NativeHuksStore } from '../security/NativeHuksStore';

interface HarmonyUsageReportPayload {
  installation_id: string;
  version: string;
}

interface HarmonyUsageReportResponse {
  code?: number;
}

/**
 * HarmonyOS 客户端匿名安装与版本统计上报器（与 iOS `UsageReporting` / Android `AppUsageReporter` 同等隐私边界）：
 * - 仅在管理员实例显式开启 `USAGE_STATISTIC_SHARE == true` 时触发；
 * - 严格要求统计端点为不含凭证/查询/片段的 `https://` 地址；
 * - 仅上报本机随机生成的 UUID 与真实应用版本号，不携带实例地址、账号、令牌或 Cookie；
 * - 按 `host + version` 实施 24 小时节流，升级新版本后自动补报一次，失败不写入节流标记。
 */
export class HarmonyUsageReporter {
  private static readonly INSTALLATION_ID_KEY: string = 'mp_usage_installation_id';
  private static readonly SUCCESS_KEY_PREFIX: string = 'mp_usage_success_';
  private static readonly REPORT_INTERVAL_MS: number = 24 * 60 * 60 * 1000;
  private static readonly REQUEST_TIMEOUT_MS: number = 15000;
  private static instance: HarmonyUsageReporter | null = null;
  private inFlight: boolean = false;

  static shared(): HarmonyUsageReporter {
    if (!HarmonyUsageReporter.instance) {
      HarmonyUsageReporter.instance = new HarmonyUsageReporter();
    }
    return HarmonyUsageReporter.instance;
  }

  /** 严格校验并归一化统计服务 HTTPS 根地址，拒绝非 HTTPS、内嵌凭据、查询参数与片段。 */
  static normalizeHttpsBase(raw: string): string | null {
    const trimmed = raw.trim();
    if (trimmed.length === 0) { return null; }
    if (!/^https:\/\//i.test(trimmed)) { return null; }
    if (trimmed.includes('?') || trimmed.includes('#') || trimmed.includes('@')) { return null; }
    if (/[\s\u0000-\u001f]/.test(trimmed)) { return null; }
    const withoutScheme = trimmed.substring(8).replace(/\/+$/, '');
    if (withoutScheme.length === 0) { return null; }
    const slashIdx = withoutScheme.indexOf('/');
    const authority = slashIdx >= 0 ? withoutScheme.substring(0, slashIdx) : withoutScheme;
    if (authority.length === 0 || authority.startsWith('.') || authority.endsWith('.') || authority.startsWith(':')) {
      return null;
    }
    return `https://${withoutScheme}`;
  }

  /** 生成 RFC 4122 随机 UUID v4，不包含任何设备或硬件指纹。 */
  private generateUuidV4(): string {
    const bytes = new Uint8Array(16);
    let filled = false;
    try {
      const rand = cryptoFramework.createRandom();
      const blob = rand.generateRandomSync(16);
      if (blob && blob.data && blob.data.length === 16) {
        for (let i = 0; i < 16; i++) {
          bytes[i] = blob.data[i];
        }
        filled = true;
      }
    } catch {
      // fallback below
    }
    if (!filled) {
      let seed = (Date.now() ^ 0x5f3759df) & 0x7fffffff;
      for (let i = 0; i < 16; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        bytes[i] = (seed >> 16) & 0xff;
      }
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hexChars = '0123456789abcdef';
    let hex = '';
    for (let i = 0; i < 16; i++) {
      const b = bytes[i] & 0xff;
      hex += hexChars.charAt((b >> 4) & 0x0f) + hexChars.charAt(b & 0x0f);
    }
    return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
  }

  /** 从系统 BundleInfo 读取真实应用版本号（如 `2.0.3`）。 */
  private resolveAppVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return (info.versionName ?? '').trim();
    } catch {
      return '';
    }
  }

  /** 构造受控长度的 Preferences 节流键（规避 HarmonyOS preferences 80 字节键长上限）。 */
  static buildThrottleKey(base: string, version: string): string {
    const raw = `${HarmonyUsageReporter.SUCCESS_KEY_PREFIX}${base}_${version}`;
    if (raw.length <= 72) {
      return raw;
    }
    let h1 = 0x811c9dc5;
    let h2 = 0x01000193;
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charCodeAt(i);
      h1 = Math.imul(h1 ^ ch, 0x01000193) >>> 0;
      h2 = Math.imul(h2 ^ (ch + i), 0x01000193) >>> 0;
    }
    const cleanVer = version.replace(/[^A-Za-z0-9._-]/g, '').substring(0, 24);
    return `${HarmonyUsageReporter.SUCCESS_KEY_PREFIX}${h1.toString(16)}_${h2.toString(16)}_${cleanVer}`;
  }

  /** 当实例开启使用统计共享时，按 24 小时节流策略发送一次匿名版本上报。 */
  async report(enabled: boolean, rawServerHost: string): Promise<void> {
    if (!enabled || this.inFlight) { return; }
    const base = HarmonyUsageReporter.normalizeHttpsBase(rawServerHost);
    if (!base) { return; }
    const version = this.resolveAppVersion();
    if (version.length === 0) { return; }

    this.inFlight = true;
    const store = NativeHuksStore.shared();
    const client = http.createHttp();
    try {
      const throttleKey = HarmonyUsageReporter.buildThrottleKey(base, version);
      const nowMs = Date.now();
      const lastRaw = await store.loadUsagePreference(throttleKey);
      if (lastRaw.length > 0) {
        const lastMs = Number(lastRaw);
        if (Number.isFinite(lastMs) && nowMs - lastMs < HarmonyUsageReporter.REPORT_INTERVAL_MS && nowMs >= lastMs) {
          return;
        }
      }

      let installationId = (await store.loadUsagePreference(HarmonyUsageReporter.INSTALLATION_ID_KEY)).trim();
      if (installationId.length === 0) {
        installationId = this.generateUuidV4();
        await store.saveUsagePreference(HarmonyUsageReporter.INSTALLATION_ID_KEY, installationId);
      }

      const payload: HarmonyUsageReportPayload = {
        installation_id: installationId,
        version: version
      };
      const endpoint = `${base}/usage/harmony/report`;
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      };
      const resp = await client.request(endpoint, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(payload),
        connectTimeout: HarmonyUsageReporter.REQUEST_TIMEOUT_MS,
        readTimeout: HarmonyUsageReporter.REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING
      });

      if (resp.responseCode === 200) {
        const bodyText = typeof resp.result === 'string' ? resp.result : '';
        if (bodyText.length > 0) {
          const parsed = JSON.parse(bodyText) as HarmonyUsageReportResponse;
          if (parsed && parsed.code === 0) {
            await store.saveUsagePreference(throttleKey, String(nowMs));
          }
        }
      }
    } catch {
      // 匿名统计失败完全静默，不写入节流标记以便下次会话重试
    } finally {
      this.inFlight = false;
      try {
        client.destroy();
      } catch {
        // ignore destroy errors
      }
    }
  }
}
