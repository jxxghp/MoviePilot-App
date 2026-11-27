import { cryptoFramework } from '@kit.CryptoArchitectureKit';

interface PendingPasskeySlot {
  resolve: (url: string) => void;
  reject: (err: Error) => void;
  timerId: number;
  resumeGraceTimerId: number;
  launchedAtMs: number;
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

/**
 * 鸿蒙端通行密钥（`moviepilot.passkey` v1）系统浏览器会话协调器：
 * - 生成 32 字节硬件真随机状态种子（64 位十六进制）；
 * - 单次消费 `EntryAbility.handleIncomingWant` 投递的 `moviepilot://passkey/callback#result=...`；
 * - 用户在系统浏览器中未完成认证而直接切回应用时，经短暂宽限窗口自动解除等待，避免按钮长期悬停在加载态。
 */
export class PasskeyAuthManager {
  private static instance: PasskeyAuthManager | null = null;
  private pendingSlot: PendingPasskeySlot | null = null;

  static shared(): PasskeyAuthManager {
    if (!PasskeyAuthManager.instance) {
      PasskeyAuthManager.instance = new PasskeyAuthManager();
    }
    return PasskeyAuthManager.instance;
  }

  /** 生成 32 字节安全随机数的 64 位十六进制字符串。 */
  generateStateHex32(): string {
    const rand = cryptoFramework.createRandom();
    const blob = rand.generateRandomSync(32);
    if (!blob || !blob.data || blob.data.length !== 32) {
      throw new Error('failed');
    }
    return bytesToHex(blob.data);
  }

  /** 由 `EntryAbility.handleIncomingWant` 在收到 `moviepilot://passkey/callback#result=...` 时调用。 */
  handleCallbackUrl(callbackUrl: string): boolean {
    if (!this.pendingSlot) {
      return false;
    }
    const slot = this.pendingSlot;
    this.pendingSlot = null;
    clearTimeout(slot.timerId);
    if (slot.resumeGraceTimerId >= 0) {
      clearTimeout(slot.resumeGraceTimerId);
    }
    slot.resolve(callbackUrl);
    return true;
  }

  /**
   * 由 `EntryAbility.onForeground` 调用：若浏览器拉起已超过 1.2s 且回到前台 900ms 后仍未收到深链回调，
   * 判定为用户主动关闭/返回浏览器并解除挂起。
   */
  notifyAppForegrounded(): void {
    const slot = this.pendingSlot;
    if (!slot) {
      return;
    }
    if (Date.now() - slot.launchedAtMs < 1200) {
      return;
    }
    if (slot.resumeGraceTimerId >= 0) {
      clearTimeout(slot.resumeGraceTimerId);
    }
    slot.resumeGraceTimerId = setTimeout(() => {
      if (this.pendingSlot === slot) {
        this.pendingSlot = null;
        clearTimeout(slot.timerId);
        slot.reject(new Error('canceled'));
      }
    }, 900);
  }

  /** 主动取消当前未完成的通行密钥浏览器等待。 */
  cancelPending(): void {
    const slot = this.pendingSlot;
    if (!slot) {
      return;
    }
    this.pendingSlot = null;
    clearTimeout(slot.timerId);
    if (slot.resumeGraceTimerId >= 0) {
      clearTimeout(slot.resumeGraceTimerId);
    }
    slot.reject(new Error('canceled'));
  }

  /** 拉起系统浏览器访问 `authorizeUrl` 并等待一次性 `moviepilot://passkey/callback` 回流。 */
  waitForCallback(
    authorizeUrl: string,
    timeoutSecs: number,
    launchBrowser: (url: string) => void
  ): Promise<string> {
    this.cancelPending();
    const boundedMs = Math.max(5000, Math.min(120000, Math.round(timeoutSecs * 1000)));
    return new Promise<string>((resolve, reject) => {
      const timerId = setTimeout(() => {
        if (this.pendingSlot && this.pendingSlot.timerId === timerId) {
          if (this.pendingSlot.resumeGraceTimerId >= 0) {
            clearTimeout(this.pendingSlot.resumeGraceTimerId);
          }
          this.pendingSlot = null;
          reject(new Error('expired'));
        }
      }, boundedMs);

      this.pendingSlot = {
        resolve: resolve,
        reject: reject,
        timerId: timerId,
        resumeGraceTimerId: -1,
        launchedAtMs: Date.now()
      };

      try {
        launchBrowser(authorizeUrl);
      } catch {
        clearTimeout(timerId);
        this.pendingSlot = null;
        reject(new Error('failed'));
      }
    });
  }
}
