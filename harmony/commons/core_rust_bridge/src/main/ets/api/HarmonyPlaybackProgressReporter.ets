import { bundleManager } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import {
  PendingPlaybackStop,
  PlaybackSyncDecision,
  PlaybackSyncState,
  RustCoreBridge
} from '../bridge/RustCoreBridge';
import { NativeHuksStore } from '../security/NativeHuksStore';
import { MoviePilotRepository, MpProgressReportOptions } from './MoviePilotRepository';

/** 每次成功上报终态 `stopped` 后递增，供详情页与发现页通过 `@StorageProp` 监听并静默刷新进度。 */
export const PLAYBACK_SYNC_REVISION_KEY: string = 'mp_playback_progress_revision';

/** 单次播放会话的状态机持有器（封装 `RustCoreBridge.planPlaybackSyncStep`）。 */
export class HarmonyPlaybackSyncTracker {
  private state: PlaybackSyncState;

  constructor(playSessionId: string = '') {
    this.state = RustCoreBridge.createInitialPlaybackSyncState(playSessionId);
  }

  reset(playSessionId: string = ''): void {
    this.state = RustCoreBridge.createInitialPlaybackSyncState(playSessionId);
  }

  getPlaySessionId(): string {
    return this.state.play_session_id;
  }

  isStopped(): boolean {
    return this.state.stopped_sent;
  }

  step(
    trigger: 'start' | 'tick' | 'pause' | 'resume' | 'seek' | 'track_change' | 'background' | 'stop' | 'finish',
    positionMs: number,
    durationMs: number,
    isPaused: boolean,
    audioStreamIndex?: number | null,
    subtitleStreamIndex?: number | null,
    nowMs: number = Date.now()
  ): PlaybackSyncDecision {
    const decision = RustCoreBridge.planPlaybackSyncStep(this.state, {
      trigger: trigger,
      now_ms: Math.max(0, Math.round(nowMs)),
      position_ms: Math.max(0, Math.round(positionMs)),
      duration_ms: durationMs > 0 ? Math.round(durationMs) : null,
      is_paused: isPaused,
      audio_stream_index: audioStreamIndex ?? null,
      subtitle_stream_index: subtitleStreamIndex ?? null
    });
    this.state = decision.next_state;
    return decision;
  }
}

/**
 * 鸿蒙 App 级播放进度与会话上报器：
 * - 独立于页面组件生命周期，通过串行 Promise 链确保退出播放页时的 `stopped` 终态不被中断；
 * - 持久化匿名 `client_id` 与离线待补报 `stopped` 队列（7 天 TTL / 上限 30 条）；
 * - 终态上报成功后递增 `AppStorage[PLAYBACK_SYNC_REVISION_KEY]` 通知详情页与发现页静默刷新。
 */
export class HarmonyPlaybackProgressReporter {
  private static readonly CLIENT_ID_KEY: string = 'mp_playback_sync_client_id';
  private static readonly PENDING_STOPS_KEY: string = 'mp_playback_sync_pending_stops';
  private static instance: HarmonyPlaybackProgressReporter | null = null;

  private cachedClientId: string = '';
  private clientIdLoaded: boolean = false;
  private serialTail: Promise<void> = Promise.resolve();

  static shared(): HarmonyPlaybackProgressReporter {
    if (!HarmonyPlaybackProgressReporter.instance) {
      HarmonyPlaybackProgressReporter.instance = new HarmonyPlaybackProgressReporter();
    }
    return HarmonyPlaybackProgressReporter.instance;
  }

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

  async ensureClientId(): Promise<string> {
    if (this.clientIdLoaded && this.cachedClientId.length > 0) {
      return this.cachedClientId;
    }
    const store = NativeHuksStore.shared();
    try {
      const stored = (await store.loadUsagePreference(HarmonyPlaybackProgressReporter.CLIENT_ID_KEY)).trim();
      if (stored.length > 0) {
        this.cachedClientId = stored;
        this.clientIdLoaded = true;
        return stored;
      }
    } catch {
      // ignore
    }
    const nextId = this.cachedClientId.length > 0 ? this.cachedClientId : this.generateUuidV4();
    this.cachedClientId = nextId;
    this.clientIdLoaded = true;
    store.saveUsagePreference(HarmonyPlaybackProgressReporter.CLIENT_ID_KEY, nextId).catch(() => {});
    return nextId;
  }

  getDeviceName(): string {
    try {
      const market = (deviceInfo.marketName ?? '').trim();
      if (market.length > 0) { return market; }
      const model = (deviceInfo.productModel ?? '').trim();
      if (model.length > 0) { return model; }
    } catch {
      // fallback
    }
    return 'HarmonyOS';
  }

  getAppVersion(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const ver = (info.versionName ?? '').trim();
      if (ver.length > 0) { return ver; }
    } catch {
      // fallback
    }
    return '2.0.3';
  }

  /** 请求 `/stream-info` 时附加的客户端设备上下文请求头。 */
  async getClientHeaders(): Promise<Record<string, string>> {
    const cid = await this.ensureClientId();
    const headers: Record<string, string> = {};
    headers['X-MP-Client-Id'] = cid;
    headers['X-MP-Device-Name'] = this.getDeviceName();
    headers['X-MP-Platform'] = 'HarmonyOS';
    headers['X-MP-App-Version'] = this.getAppVersion();
    return headers;
  }

  /** 串行提交一条状态机决策至后端，失败的终态 `stopped` 自动持久化等待补报。 */
  enqueueDecision(
    repo: MoviePilotRepository,
    itemId: string,
    server: string,
    mediaSourceId: string,
    decision: PlaybackSyncDecision,
    playSessionId: string,
    durationMs: number,
    audioStreamIndex?: number | null,
    subtitleStreamIndex?: number | null,
    playMethod: string = 'DirectPlay'
  ): void {
    if (!decision.should_report) {
      return;
    }
    const cleanItem = itemId.trim();
    const cleanSrv = server.trim();
    if (
      cleanItem.length === 0 ||
      cleanSrv.length === 0 ||
      cleanItem.startsWith('file.') ||
      cleanItem.startsWith('file:') ||
      cleanItem.startsWith('local:') ||
      cleanItem.startsWith('external:')
    ) {
      return;
    }
    const scope = repo.accountStorageScope();
    const requestBase = repo.baseUrl;
    const requestToken = repo.token;
    if (requestToken.length === 0 || scope.length === 0) { return; }
    const isStop = decision.state === 'stopped';
    const nextWork = async (): Promise<void> => {
      const cid = await this.ensureClientId();
      const opts: MpProgressReportOptions = {
        eventName: decision.event_name ?? undefined,
        playSessionId: playSessionId.trim().length > 0 ? playSessionId.trim() : undefined,
        clientId: cid,
        deviceName: this.getDeviceName(),
        platform: 'HarmonyOS',
        appVersion: this.getAppVersion(),
        playMethod: playMethod,
        playbackTimeMs: decision.playback_time_ms,
        audioStreamIndex: audioStreamIndex !== undefined && audioStreamIndex !== null ? audioStreamIndex : undefined,
        subtitleStreamIndex: subtitleStreamIndex !== undefined && subtitleStreamIndex !== null ? subtitleStreamIndex : undefined,
        seq: decision.seq
      };
      const ok = await repo.reportMediaServerProgress(
        cleanItem,
        cleanSrv,
        mediaSourceId,
        decision.position_ms,
        durationMs,
        decision.is_paused,
        decision.state,
        opts, requestBase, requestToken
      );
      if (isStop) {
        if (ok) {
          this.bumpProgressRevision();
        } else {
          await this.recordPendingStop({
            server: cleanSrv,
            item_id: cleanItem,
            media_source_id: mediaSourceId.trim().length > 0 ? mediaSourceId.trim() : null,
            position_ms: decision.position_ms,
            duration_ms: durationMs > 0 ? Math.round(durationMs) : null,
            play_session_id: playSessionId.trim().length > 0 ? playSessionId.trim() : null,
            playback_time_ms: decision.playback_time_ms,
            seq: decision.seq,
            updated_at_ms: Date.now()
          }, scope);
        }
      }
    };
    this.serialTail = this.serialTail.then(nextWork, nextWork);
  }

  /** 在起播或网络恢复时串行补报离线失败的 `stopped` 终态记录。 */
  flushPendingStops(repo: MoviePilotRepository): void {
    const scope = repo.accountStorageScope();
    const requestBase = repo.baseUrl;
    const requestToken = repo.token;
    if (requestToken.length === 0 || scope.length === 0) { return; }
    const nextWork = async (): Promise<void> => {
      const pending = await this.loadPendingStops(scope);
      if (pending.length === 0) {
        return;
      }
      const cid = await this.ensureClientId();
      const dev = this.getDeviceName();
      const ver = this.getAppVersion();
      const remaining: PendingPlaybackStop[] = [];
      let flushedAny = false;
      for (let i = 0; i < pending.length; i++) {
        const entry = pending[i];
        const ok = await repo.reportMediaServerProgress(
          entry.item_id,
          entry.server,
          entry.media_source_id ?? '',
          entry.position_ms,
          entry.duration_ms ?? 0,
          true,
          'stopped',
          {
            playSessionId: entry.play_session_id ?? undefined,
            clientId: cid,
            deviceName: dev,
            platform: 'HarmonyOS',
            appVersion: ver,
            playMethod: 'DirectPlay',
            playbackTimeMs: entry.playback_time_ms ?? undefined,
            seq: entry.seq ?? undefined
          }, requestBase, requestToken
        );
        if (ok) {
          flushedAny = true;
        } else {
          remaining.push(entry);
        }
      }
      await this.savePendingStops(remaining, scope);
      if (flushedAny) {
        this.bumpProgressRevision();
      }
    };
    this.serialTail = this.serialTail.then(nextWork, nextWork);
  }

  private bumpProgressRevision(): void {
    try {
      const current = AppStorage.get<number>(PLAYBACK_SYNC_REVISION_KEY) ?? 0;
      AppStorage.setOrCreate<number>(PLAYBACK_SYNC_REVISION_KEY, current + 1);
    } catch {
      // ignore in headless environment
    }
  }

  /** 只读取显式实例账号桶，旧版未知归属数据不参与补报。 */
  private async loadPendingStops(scope: string): Promise<PendingPlaybackStop[]> {
    try {
      const raw = (await NativeHuksStore.shared().loadUsagePreference(HarmonyPlaybackProgressReporter.PENDING_STOPS_KEY + '_v2_' + scope)).trim();
      if (raw.length === 0) { return []; }
      const parsed = JSON.parse(raw) as PendingPlaybackStop[];
      if (!Array.isArray(parsed)) { return []; }
      return RustCoreBridge.normalizePendingPlaybackStops(parsed, Date.now());
    } catch {
      return [];
    }
  }

  /** 分桶写入，串行任务不会覆盖别的实例或用户。 */
  private async savePendingStops(entries: PendingPlaybackStop[], scope: string): Promise<void> {
    const normalized = RustCoreBridge.normalizePendingPlaybackStops(entries, Date.now());
    try {
      await NativeHuksStore.shared().saveUsagePreference(
        HarmonyPlaybackProgressReporter.PENDING_STOPS_KEY + '_v2_' + scope,
        normalized.length > 0 ? JSON.stringify(normalized) : ''
      );
    } catch {
      // ignore
    }
  }

  /** 将失败终态保存到发起播放时的固定归属中。 */
  private async recordPendingStop(stop: PendingPlaybackStop, scope: string): Promise<void> {
    const existing = await this.loadPendingStops(scope);
    existing.push(stop);
    await this.savePendingStops(existing, scope);
  }
}
