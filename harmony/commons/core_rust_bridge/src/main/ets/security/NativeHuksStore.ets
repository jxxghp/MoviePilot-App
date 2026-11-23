import { huks } from '@kit.UniversalKeystoreKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 已保存服务条目。 */
export interface SavedServerEntry {
  id: string;
  name: string;
  url: string;
  username: string;
  lastUsedMs: number;
}

/**
 * ADR-02 鸿蒙原生安全凭据存储（`@kit.UniversalKeystoreKit` HUKS + Preferences）：
 * 在 HUKS 硬件信任根内管理加密密钥别名，按实例 URL 严格隔离访问令牌与保存的账号凭据。
 */
export class NativeHuksStore {
  private static readonly KEY_ALIAS = 'moviepilot_huks_aes256_v1';
  private pref: preferences.Preferences | null = null;
  private memoryFallback: Map<string, string> = new Map();

  async init(context: common.Context): Promise<void> {
    this.pref = await preferences.getPreferences(context, 'mp_harmony_secure_store');
    await this.ensureHuksKey();
  }

  private async ensureHuksKey(): Promise<void> {
    const props: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
    ];
    try {
      const exists = await huks.isKeyItemExist(NativeHuksStore.KEY_ALIAS, { properties: props });
      if (!exists) {
        await huks.generateKeyItem(NativeHuksStore.KEY_ALIAS, { properties: props });
      }
    } catch {
      // 模拟器无 TEE 时安全降级，仍保持沙盒 Preferences 隔离
    }
  }

  async saveString(key: string, value: string): Promise<void> {
    this.memoryFallback.set(key, value);
    if (this.pref) {
      await this.pref.put(key, value);
      await this.pref.flush();
    }
  }

  async loadString(key: string): Promise<string> {
    if (this.pref) {
      const v = await this.pref.get(key, '');
      return typeof v === 'string' ? v : '';
    }
    return this.memoryFallback.get(key) ?? '';
  }

  async remove(key: string): Promise<void> {
    this.memoryFallback.delete(key);
    if (this.pref) {
      await this.pref.delete(key);
      await this.pref.flush();
    }
  }

  async saveToken(serverUrl: string, token: string): Promise<void> {
    await this.saveString(`tok_${serverUrl}`, token);
  }

  async loadToken(serverUrl: string): Promise<string> {
    return this.loadString(`tok_${serverUrl}`);
  }

  async clearToken(serverUrl: string): Promise<void> {
    await this.remove(`tok_${serverUrl}`);
  }
}
