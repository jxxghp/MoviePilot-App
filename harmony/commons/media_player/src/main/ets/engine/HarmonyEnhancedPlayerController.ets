import {
  IjkMediaPlayer,
  OnPreparedListener,
  OnVideoSizeChangedListener,
  OnCompletionListener,
  OnErrorListener,
  OnInfoListener,
  OnTimedTextListener
} from '@ohos/ijkplayer';

/** 鸿蒙增强内核（`@ohos/ijkplayer` FFmpeg 内核）回调接口。 */
export interface EnhancedPlayerCallbacks {
  onPrepared: (durationMs: number) => void;
  onVideoSizeChanged: (width: number, height: number) => void;
  onBufferingChanged: (buffering: boolean) => void;
  onProgress: (positionMs: number, durationMs: number, playing: boolean) => void;
  onTimedText: (text: string) => void;
  onCompletion: () => void;
  onError: (what: number, extra: number) => void;
}

/** 增强内核启动配置。 */
export interface EnhancedLoadConfig {
  url: string;
  headers: Record<string, string>;
  startPositionMs: number;
  speed: number;
  forceSoftwareDecode: boolean;
  largeBuffer: boolean;
}

/**
 * 鸿蒙端全能增强内核控制器（基于 `@ohos/ijkplayer`）：
 * - 补齐系统 `AVPlayer` 对 MKV / FLV / TS / M2TS 封装与 DTS / TrueHD / AC3 / EAC3 / FLAC 音轨支持；
 * - 支持硬解（`mediacodec=1`）与强制软解（`mediacodec=0`）、大缓冲档位（15MiB / 50MiB）、
 *   `soundtouch=1` 0.5x~3.0x 变速不变调与自定义 HTTP Headers；
 * - 严格遵守 ArkTS 静态类型约束与单实例安全生命周期释放。
 */
export class HarmonyEnhancedPlayerController {
  private ijk: IjkMediaPlayer | null = null;
  private surfaceContext: object | null = null;
  private xComponentId: string = 'mp_harmony_ijk_surface';
  private pendingConfig: EnhancedLoadConfig | null = null;
  private callbacks: EnhancedPlayerCallbacks | null = null;
  private pollTimer: number = -1;
  private released: boolean = false;
  private prepared: boolean = false;
  private currentSpeed: number = 1.0;
  private pendingStartSeekMs: number = 0;

  /** 绑定 `XComponent(libraryname: 'ijkplayer_napi')` 的 `onLoad` 上下文；若已有待加载配置则立即启动。 */
  bindSurfaceContext(xComponentId: string, ctx: object): void {
    this.xComponentId = xComponentId;
    this.surfaceContext = ctx;
    if (!this.released && this.pendingConfig && this.callbacks) {
      const cfg = this.pendingConfig;
      const cbs = this.callbacks;
      this.pendingConfig = null;
      this.startInternal(cfg, cbs);
    }
  }

  /** 请求加载媒体源；若 XComponent 尚未 `onLoad` 则缓存配置待就绪后自动起播。 */
  load(config: EnhancedLoadConfig, callbacks: EnhancedPlayerCallbacks): void {
    this.released = false;
    this.callbacks = callbacks;
    if (!this.surfaceContext) {
      this.pendingConfig = config;
      return;
    }
    this.pendingConfig = null;
    this.startInternal(config, callbacks);
  }

  private startInternal(config: EnhancedLoadConfig, callbacks: EnhancedPlayerCallbacks): void {
    this.stopPollTimer();
    this.teardownIjkInstance();
    this.prepared = false;
    this.currentSpeed = config.speed > 0 ? config.speed : 1.0;
    this.pendingStartSeekMs = Math.max(0, Math.round(config.startPositionMs));

    try {
      const player = new IjkMediaPlayer(this.xComponentId);
      if (this.surfaceContext) {
        player.setContext(this.surfaceContext, this.xComponentId);
      }
      player.setDebug(false);
      player.native_setup();

      // FFmpeg 解码与缓冲调优（选项类别：1=FORMAT, 2=CODEC, 3=SWS, 4=PLAYER）
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec', config.forceSoftwareDecode ? '0' : '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-auto-rotate', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-handle-resolution-change', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'framedrop', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'soundtouch', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'packet-buffering', '1');
      player.setOption(
        IjkMediaPlayer.OPT_CATEGORY_PLAYER,
        'max-buffer-size',
        config.largeBuffer ? String(50 * 1024 * 1024) : String(15 * 1024 * 1024)
      );
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'reconnect', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'dns_cache_clear', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'analyzeduration', '2000000');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'probesize', '1048576');

      if (this.pendingStartSeekMs > 0) {
        player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'seek-at-start', String(this.pendingStartSeekMs));
      }

      const headerKeys = Object.keys(config.headers);
      if (headerKeys.length > 0) {
        const headerMap = new Map<string, string>();
        for (let i = 0; i < headerKeys.length; i++) {
          const k = headerKeys[i];
          const v = config.headers[k];
          if (k && v && v.length > 0) {
            headerMap.set(k, v);
          }
        }
        if (headerMap.size > 0) {
          player.setDataSourceHeader(headerMap);
        }
      }
      player.setDataSource(config.url);

      const preparedListener: OnPreparedListener = {
        onPrepared: () => {
          if (this.released || this.ijk !== player) { return; }
          this.prepared = true;
          const dur = Math.max(0, player.getDuration());
          if (Math.abs(this.currentSpeed - 1.0) >= 0.01) {
            try {
              player.setSpeed(this.currentSpeed.toFixed(2));
            } catch {
              // ignore
            }
          }
          callbacks.onBufferingChanged(false);
          callbacks.onPrepared(dur);
          this.startPollTimer(player, callbacks);
        }
      };
      player.setOnPreparedListener(preparedListener);

      const sizeListener: OnVideoSizeChangedListener = {
        onVideoSizeChanged: (width: number, height: number, _sarNum: number, _sarDen: number) => {
          if (this.released || this.ijk !== player) { return; }
          if (width > 0 && height > 0) {
            callbacks.onVideoSizeChanged(width, height);
          }
        }
      };
      player.setOnVideoSizeChangedListener(sizeListener);

      const infoListener: OnInfoListener = {
        onInfo: (what: number, _extra: number) => {
          if (this.released || this.ijk !== player) { return; }
          if (what === 701) {
            callbacks.onBufferingChanged(true);
          } else if (what === 702 || what === 3) {
            callbacks.onBufferingChanged(false);
          }
        }
      };
      player.setOnInfoListener(infoListener);

      const timedTextListener: OnTimedTextListener = {
        onTimedText: (text: string) => {
          if (this.released || this.ijk !== player) { return; }
          callbacks.onTimedText((text ?? '').trim());
        }
      };
      player.setOnTimedTextListener(timedTextListener);

      const completionListener: OnCompletionListener = {
        onCompletion: () => {
          if (this.released || this.ijk !== player) { return; }
          this.stopPollTimer();
          callbacks.onCompletion();
        }
      };
      player.setOnCompletionListener(completionListener);

      const errorListener: OnErrorListener = {
        onError: (what: number, extra: number) => {
          if (this.released || this.ijk !== player) { return; }
          this.stopPollTimer();
          callbacks.onError(what, extra);
        }
      };
      player.setOnErrorListener(errorListener);

      player.setMessageListener();
      this.ijk = player;
      player.prepareAsync();
    } catch {
      callbacks.onError(-1, -1);
    }
  }

  private startPollTimer(player: IjkMediaPlayer, callbacks: EnhancedPlayerCallbacks): void {
    this.stopPollTimer();
    this.pollTimer = setInterval(() => {
      if (this.released || this.ijk !== player) {
        this.stopPollTimer();
        return;
      }
      try {
        const pos = Math.max(0, player.getCurrentPosition());
        const dur = Math.max(0, player.getDuration());
        const playing = player.isPlaying();
        callbacks.onProgress(pos, dur, playing);
      } catch {
        // ignore transient poll errors
      }
    }, 400);
  }

  private stopPollTimer(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  play(): void {
    if (this.released || !this.ijk || !this.prepared) { return; }
    try {
      this.ijk.start();
    } catch {
      // ignore
    }
  }

  pause(): void {
    if (this.released || !this.ijk || !this.prepared) { return; }
    try {
      this.ijk.pause();
    } catch {
      // ignore
    }
  }

  seekTo(targetMs: number): void {
    if (this.released || !this.ijk || !this.prepared) { return; }
    try {
      this.ijk.seekTo(String(Math.max(0, Math.round(targetMs))));
    } catch {
      // ignore
    }
  }

  setSpeed(speed: number): void {
    this.currentSpeed = Math.min(3.0, Math.max(0.25, speed));
    if (this.released || !this.ijk || !this.prepared) { return; }
    try {
      this.ijk.setSpeed(this.currentSpeed.toFixed(2));
    } catch {
      // ignore
    }
  }

  setVolume(vol: number): void {
    if (this.released || !this.ijk || !this.prepared) { return; }
    const clamped = Math.min(1.0, Math.max(0.0, vol));
    try {
      this.ijk.setVolume(clamped.toFixed(2), clamped.toFixed(2));
    } catch {
      // ignore
    }
  }

  isPlaying(): boolean {
    if (this.released || !this.ijk || !this.prepared) { return false; }
    try {
      return this.ijk.isPlaying();
    } catch {
      return false;
    }
  }

  private teardownIjkInstance(): void {
    const inst = this.ijk;
    this.ijk = null;
    this.prepared = false;
    if (inst) {
      try { inst.stop(); } catch { /* ignore */ }
      try { inst.reset(); } catch { /* ignore */ }
      try { inst.release(); } catch { /* ignore */ }
    }
  }

  release(): void {
    this.released = true;
    this.pendingConfig = null;
    this.callbacks = null;
    this.stopPollTimer();
    this.teardownIjkInstance();
  }
}
